{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module Main where

import Control.Exception (SomeException, catch)
import Data.Aeson (FromJSON, decode)
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import GHC.Generics (Generic)
import System.Console.Terminal.Size (hSize, width)
import System.Environment (getEnvironment, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeFileName)
import System.IO (IOMode (ReadMode), hClose, openFile)
import System.Process (CreateProcess (env), proc, readCreateProcessWithExitCode)

--------------------- JSON schema types -----------------------

-- Claude Code statusline JSON (stdin)
data StatusInput = StatusInput
    { model :: Maybe ModelInfo
    , workspace :: Maybe WorkspaceInfo
    , context_window :: Maybe ContextWindow
    , rate_limits :: Maybe RateLimits
    }
    deriving (Generic)
instance FromJSON StatusInput

newtype ModelInfo = ModelInfo {display_name :: String} deriving (Generic)
instance FromJSON ModelInfo

newtype WorkspaceInfo = WorkspaceInfo {current_dir :: String} deriving (Generic)
instance FromJSON WorkspaceInfo

data ContextWindow = ContextWindow
    { remaining_percentage :: Maybe Double
    }
    deriving (Generic)
instance FromJSON ContextWindow

data RateLimits = RateLimits
    { five_hour :: Maybe UsageWindow
    , seven_day :: Maybe UsageWindow
    }
    deriving (Generic)
instance FromJSON RateLimits

data UsageWindow = UsageWindow
    { used_percentage :: Maybe Double
    , resets_at :: Maybe Double -- Unix epoch seconds
    }
    deriving (Generic)
instance FromJSON UsageWindow

emptyInput :: StatusInput
emptyInput = StatusInput Nothing Nothing Nothing Nothing

----------------------- Formatting --------------------------

formatCountdown :: NominalDiffTime -> String
formatCountdown dt
    | secs <= 0 = "now"
    | secs < 3600 = show mins ++ "m"
    | secs < 86400 = show hrs ++ "h " ++ show rMins ++ "m"
    | otherwise = show days ++ "d " ++ show rHrs ++ "h"
  where
    secs = floor dt :: Int
    mins = secs `div` 60
    hrs = secs `div` 3600
    rMins = (secs `mod` 3600) `div` 60
    days = secs `div` 86400
    rHrs = (secs `mod` 86400) `div` 3600

----------------------- Usage info --------------------------

data UsageInfo = UsageInfo
    { fiveHourUtil :: Maybe Double
    , fiveHourReset :: Maybe UTCTime
    , sevenDayUtil :: Maybe Double
    , sevenDayReset :: Maybe UTCTime
    }

emptyUsage :: UsageInfo
emptyUsage = UsageInfo Nothing Nothing Nothing Nothing

epochToUTC :: Double -> UTCTime
epochToUTC = posixSecondsToUTCTime . realToFrac

toUsageInfo :: RateLimits -> UsageInfo
toUsageInfo (RateLimits mFive mSeven) =
    UsageInfo
        { fiveHourUtil = used_percentage =<< mFive
        , fiveHourReset = epochToUTC <$> (resets_at =<< mFive)
        , sevenDayUtil = used_percentage =<< mSeven
        , sevenDayReset = epochToUTC <$> (resets_at =<< mSeven)
        }

------------------- Nerd font icons -------------------------

iconNix, iconFolder, iconRocket, iconBattery, iconCalendar, iconDatabase :: Char
iconNix = '\xF313' -- nf-linux-nixos
iconFolder = '\xF07B' -- nf-fa-folder
iconRocket = '\xF135' -- nf-fa-rocket
iconBattery = '\xF0079' -- nf-md-battery_50
iconCalendar = '\xF051B' -- nf-md-calendar_clock
iconDatabase = '\xF01BC' -- nf-md-database

---------------------- Context bar --------------------------

{- | 10-cell bar of used context, e.g. used=10 -> "█░░░░░░░░░ 10%".
  Raw 24-bit ANSI fg escapes; starship passes env values through verbatim.
  Bg stays whatever the CLAUDE_CTX segment sets (color_bg3).
-}
ctxBar :: Int -> String
ctxBar used =
    fg fill (replicate n '█')
        ++ fg empty (replicate (10 - n) '░')
        ++ fg fg0 (" " ++ show used ++ "%")
  where
    n = max 0 (min 10 ((used + 5) `div` 10)) -- round half up, clamp
    fill
        | used <= 10 = green
        | used <= 75 = grey
        | used <= 80 = yellow
        | otherwise = red
    fg (r, g, b) str = "\ESC[38;2;" ++ show r ++ ";" ++ show g ++ ";" ++ show b ++ "m" ++ str
    -- Atelier Cave palette (modules/home/_palette.nix)
    fg0 = (0xef, 0xec, 0xf4) :: (Int, Int, Int)
    green = (0x2a, 0x92, 0x92)
    grey = (0xc5, 0xc1, 0xcb) -- lighter than color_text_dim; must read on color_bg3
    empty = (0x8b, 0x87, 0x92) -- color_text_dim
    yellow = (0xa0, 0x6e, 0x3b)
    red = (0xbe, 0x46, 0x78)

-------------------- Terminal width -------------------------

{- | Detect terminal width: COLUMNS env var > /dev/tty query > fallback 120.
  stdout is a pipe when Claude Code invokes us, so we open /dev/tty directly.
-}
getTerminalWidth :: IO String
getTerminalWidth = do
    mCols <- lookupEnv "COLUMNS"
    case mCols of
        Just c | not (null c) -> pure c
        _ -> queryTty `catch` \(_ :: SomeException) -> pure "120"
  where
    queryTty = do
        h <- openFile "/dev/tty" ReadMode
        mSize <- hSize h
        hClose h
        pure $ maybe "120" (show . subtract 5 . width) mSize

----------------------- Statusline --------------------------

-- | Check whether cwd is inside a git repository.
isGitRepo :: String -> IO Bool
isGitRepo cwd = do
    (exit, _, _) <-
        readCreateProcessWithExitCode
            (proc "git" ["-C", cwd, "rev-parse", "--git-dir"])
            ""
    pure (exit == ExitSuccess)

main :: IO ()
main = do
    input <- BL.getContents
    let si = fromMaybe emptyInput (decode input)

    let cwd = maybe "" current_dir (workspace si)
        mdl = maybe "" display_name (model si)
        mCtx = context_window si
        ctxPct = remaining_percentage =<< mCtx

    -- Git: just a boolean check — Starship handles branch/status rendering
    hasGit <- if null cwd then pure False else isGitRepo cwd

    -- Usage info from native rate_limits (Nothing pre-2.1.80 = no usage shown)
    now <- getCurrentTime
    let usage = maybe emptyUsage toUsageInfo (rate_limits si)

    -- Nix shell detection
    dirIcon <- maybe iconFolder (const iconNix) <$> lookupEnv "IN_NIX_SHELL"

    -- Build content strings
    let dir = takeFileName cwd

        fmtPct u = show (round u :: Int) ++ "%"
        fmtReset mR = case mR of
            Nothing -> ""
            Just r -> " " ++ formatCountdown (diffUTCTime r now)
        usageStr = case (fiveHourUtil usage, sevenDayUtil usage) of
            (Nothing, Nothing) -> Nothing
            (Just u5, Nothing) -> Just $ [iconBattery] ++ " " ++ fmtPct u5 ++ fmtReset (fiveHourReset usage)
            (Nothing, Just u7) -> Just $ [iconCalendar] ++ " " ++ fmtPct u7 ++ fmtReset (sevenDayReset usage)
            (Just u5, Just u7) -> Just $ [iconBattery] ++ " " ++ fmtPct u5 ++ fmtReset (fiveHourReset usage) ++ " " ++ [iconCalendar] ++ " " ++ fmtPct u7 ++ fmtReset (sevenDayReset usage)

        ctxStr = fmap (\p -> [iconDatabase, ' '] ++ ctxBar (100 - round p)) ctxPct

        hasUsage = isJust usageStr
        hasDark = isJust ctxStr

    -- Build env var list for Starship
    let envs =
            catMaybes
                [ Just ("CLAUDE_DIR", [dirIcon, ' '] ++ dir)
                , Just ("CLAUDE_MODEL", [iconRocket, ' '] ++ mdl)
                , fmap ("CLAUDE_USAGE",) usageStr
                , fmap ("CLAUDE_CTX",) ctxStr
                , if hasGit then Nothing else Just ("CLAUDE_NO_GIT", "1")
                , -- Right side sentinels
                  if hasUsage && hasDark then Just ("CLAUDE_R_U2D", "1") else Nothing
                , if hasUsage && not hasDark then Just ("CLAUDE_R_UEND", "1") else Nothing
                , if not hasUsage && hasDark then Just ("CLAUDE_R_DOPEN", "1") else Nothing
                ]

    -- Call starship
    starshipBin <- fromMaybe "starship" <$> lookupEnv "STARSHIP_BIN"
    cols <- getTerminalWidth
    parentEnv <- getEnvironment
    let fullEnv = parentEnv ++ envs
        starshipArgs =
            ["prompt", "--profile", "claude", "--terminal-width", cols]
                ++ if null cwd then [] else ["--path", cwd]
    (_, out, _) <-
        readCreateProcessWithExitCode
            (proc starshipBin starshipArgs){env = Just fullEnv}
            ""
    putStr out
