{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TupleSections #-}

module Main where

import Control.Exception (SomeException, catch)
import Control.Monad (guard, void)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Maybe (MaybeT (..), runMaybeT)
import Data.Aeson (FromJSON, decode)
import Data.ByteString.Lazy qualified as BL
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Data.Time.LocalTime (ZonedTime, zonedTimeToUTC)
import GHC.Generics (Generic)
import Numeric (showFFloat)
import System.Console.Terminal.Size (hSize, width)
import System.Directory (doesFileExist, getHomeDirectory, getModificationTime)
import System.Environment (getArgs, getEnvironment, lookupEnv)
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
    , output_style :: Maybe StyleInfo
    }
    deriving (Generic)
instance FromJSON StatusInput

newtype ModelInfo = ModelInfo {display_name :: String} deriving (Generic)
instance FromJSON ModelInfo

newtype WorkspaceInfo = WorkspaceInfo {current_dir :: String} deriving (Generic)
instance FromJSON WorkspaceInfo

data ContextWindow = ContextWindow
    { remaining_percentage :: Maybe Double
    , total_input_tokens :: Maybe Int
    , total_output_tokens :: Maybe Int
    , context_window_size :: Maybe Int
    }
    deriving (Generic)
instance FromJSON ContextWindow

newtype StyleInfo = StyleInfo {name :: String} deriving (Generic)
instance FromJSON StyleInfo

-- Credentials file (~/.claude/.credentials.json)
newtype CredFile = CredFile {claudeAiOauth :: Maybe OAuthCred} deriving (Generic)
instance FromJSON CredFile

newtype OAuthCred = OAuthCred {accessToken :: Maybe String} deriving (Generic)
instance FromJSON OAuthCred

-- Usage cache (CLAUDE_USAGE_CACHE)
data UsageWindow = UsageWindow
    { utilization :: Maybe Double
    , resets_at :: Maybe String
    }
    deriving (Generic)
instance FromJSON UsageWindow

data UsageCache = UsageCache
    { five_hour :: Maybe UsageWindow
    , seven_day :: Maybe UsageWindow
    }
    deriving (Generic)
instance FromJSON UsageCache

emptyInput :: StatusInput
emptyInput = StatusInput Nothing Nothing Nothing Nothing

----------------------- Formatting --------------------------

formatTokens :: Int -> String
formatTokens n
    | n >= 1000000 = showFFloat (Just 1) (fromIntegral n / 1000000 :: Double) "M"
    | n >= 1000 = show (n `div` 1000) ++ "K"
    | otherwise = show n

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

formatUtil :: Double -> Maybe UTCTime -> UTCTime -> String
formatUtil util mReset now =
    show (round util :: Int)
        ++ "%"
        ++ case mReset of
            Nothing -> ""
            Just resetAt -> " (" ++ formatCountdown (diffUTCTime resetAt now) ++ ")"

----------------------- Usage cache -------------------------

getUsageCachePath :: IO FilePath
getUsageCachePath = fromMaybe "/tmp/.claude_usage_cache" <$> lookupEnv "CLAUDE_USAGE_CACHE"

data UsageInfo = UsageInfo
    { fiveHourUtil :: Maybe Double
    , fiveHourReset :: Maybe UTCTime
    , sevenDayUtil :: Maybe Double
    , sevenDayReset :: Maybe UTCTime
    }

emptyUsage :: UsageInfo
emptyUsage = UsageInfo Nothing Nothing Nothing Nothing

parseISO :: String -> Maybe UTCTime
parseISO s = zonedTimeToUTC <$> (iso8601ParseM s :: Maybe ZonedTime)

toUsageInfo :: UsageCache -> UsageInfo
toUsageInfo (UsageCache mFive mSeven) =
    UsageInfo
        { fiveHourUtil = utilization =<< mFive
        , fiveHourReset = parseISO =<< resets_at =<< mFive
        , sevenDayUtil = utilization =<< mSeven
        , sevenDayReset = parseISO =<< resets_at =<< mSeven
        }

readUsageCache :: FilePath -> IO UsageInfo
readUsageCache cachePath = catch readIt (\e -> let _ = e :: SomeException in pure emptyUsage)
  where
    readIt = do
        exists <- doesFileExist cachePath
        if not exists
            then pure emptyUsage
            else do
                bytes <- BL.readFile cachePath
                pure $ maybe emptyUsage toUsageInfo (decode bytes)

---------------------- Fetch mode ---------------------------

isCacheFresh :: FilePath -> UTCTime -> IO Bool
isCacheFresh cachePath now = do
    exists <- doesFileExist cachePath
    if not exists
        then pure False
        else do
            mtime <- getModificationTime cachePath
            pure (diffUTCTime now mtime < 30)

runFetch :: IO ()
runFetch = void $ runMaybeT $ do
    cachePath <- lift getUsageCachePath
    now <- lift getCurrentTime
    fresh <- lift $ isCacheFresh cachePath now
    guard (not fresh)
    home <- lift getHomeDirectory
    let credPath = home ++ "/.claude/.credentials.json"
    credExists <- lift $ doesFileExist credPath
    guard credExists
    credBytes <- lift $ BL.readFile credPath
    cred <- MaybeT . pure $ (decode credBytes :: Maybe CredFile)
    oauth <- MaybeT . pure $ claudeAiOauth cred
    token <- MaybeT . pure $ accessToken oauth
    guard (not (null token))
    (exit, out, _) <-
        lift $
            readCreateProcessWithExitCode
                ( proc
                    "curl"
                    [ "-sf"
                    , "--max-time"
                    , "10"
                    , "-H"
                    , "Authorization: Bearer " ++ token
                    , "-H"
                    , "anthropic-beta: oauth-2025-04-20"
                    , "https://api.anthropic.com/oauth/usage"
                    ]
                )
                ""
    guard (exit == ExitSuccess)
    lift $ writeFile cachePath out

------------------- Nerd font icons -------------------------

iconNix, iconFolder, iconRocket, iconBattery, iconCalendar, iconBrain, iconBrush :: Char
iconNix = '\xF313' -- nf-linux-nixos
iconFolder = '\xF07B' -- nf-fa-folder
iconRocket = '\xF135' -- nf-fa-rocket
iconBattery = '\xF0079' -- nf-md-battery_50
iconCalendar = '\xF051B' -- nf-md-calendar_clock
iconBrain = '\xF02A0' -- nf-md-brain
iconBrush = '\xF1FC' -- nf-fa-paint_brush

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

runStatusline :: IO ()
runStatusline = do
    input <- BL.getContents
    let si = fromMaybe emptyInput (decode input)

    let cwd = maybe "" current_dir (workspace si)
        mdl = maybe "" display_name (model si)
        styl = maybe "" name (output_style si)
        mCtx = context_window si
        ctxPct = remaining_percentage =<< mCtx
        inTok = fromMaybe 0 (total_input_tokens =<< mCtx)
        outTok = fromMaybe 0 (total_output_tokens =<< mCtx)
        ctxMax = fromMaybe 0 (context_window_size =<< mCtx)

    -- Git: just a boolean check — Starship handles branch/status rendering
    hasGit <- if null cwd then pure False else isGitRepo cwd

    -- Usage info
    cachePath <- getUsageCachePath
    now <- getCurrentTime
    usage <- readUsageCache cachePath

    -- Nix shell detection
    dirIcon <- maybe iconFolder (const iconNix) <$> lookupEnv "IN_NIX_SHELL"

    -- Build content strings
    let dir = takeFileName cwd

        fmt5h u = [iconBattery] ++ " 5h " ++ formatUtil u (fiveHourReset usage) now
        fmt7d u = [iconCalendar] ++ " 7d " ++ formatUtil u (sevenDayReset usage) now
        usageStr = case (fiveHourUtil usage, sevenDayUtil usage) of
            (Nothing, Nothing) -> Nothing
            (Just u5, Nothing) -> Just $ fmt5h u5
            (Nothing, Just u7) -> Just $ fmt7d u7
            (Just u5, Just u7) -> Just $ fmt5h u5 ++ " " ++ fmt7d u7

        totalTok = inTok + outTok
        ctxStr = case ctxPct of
            Nothing -> Nothing
            Just p
                | ctxMax > 0 ->
                    let usedPct = 100 - round p :: Int
                     in Just $
                            [iconBrain]
                                ++ " ctx "
                                ++ show usedPct
                                ++ "% "
                                ++ formatTokens totalTok
                                ++ "/"
                                ++ formatTokens ctxMax
                | totalTok > 0 ->
                    Just $
                        [iconBrain, ' ']
                            ++ show (round p :: Int)
                            ++ "% "
                            ++ formatTokens totalTok
                | otherwise ->
                    Just $ [iconBrain, ' '] ++ show (round p :: Int) ++ "%"

        styleStr
            | null styl || styl == "default" = Nothing
            | otherwise = Just $ [iconBrush, ' '] ++ styl

        hasUsage = isJust usageStr
        hasDark = isJust ctxStr || isJust styleStr

    -- Build env var list for Starship
    let envs =
            catMaybes
                [ Just ("CLAUDE_DIR", [dirIcon, ' '] ++ dir)
                , Just ("CLAUDE_MODEL", [iconRocket, ' '] ++ mdl)
                , fmap ("CLAUDE_USAGE",) usageStr
                , fmap ("CLAUDE_CTX",) ctxStr
                , fmap ("CLAUDE_STYLE",) styleStr
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

--------------------------- Main ----------------------------

main :: IO ()
main = do
    args <- getArgs
    case args of
        ["--fetch"] -> catch runFetch (\e -> let _ = e :: SomeException in pure ())
        _ -> runStatusline
