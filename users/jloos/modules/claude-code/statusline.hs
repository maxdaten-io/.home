{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (SomeException, catch)
import Control.Monad (guard, void)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Maybe (MaybeT (..), runMaybeT)
import Data.Aeson (FromJSON, decode)
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (catMaybes, fromMaybe)
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Data.Time.LocalTime (ZonedTime, zonedTimeToUTC)
import GHC.Generics (Generic)
import Numeric (showFFloat)
import System.Directory (doesFileExist, getHomeDirectory, getModificationTime)
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeFileName)
import System.Process (proc, readCreateProcessWithExitCode)

--------------------- JSON schema types -----------------------

-- Claude Code statusline JSON (stdin)
data StatusInput = StatusInput
  { model          :: Maybe ModelInfo
  , workspace      :: Maybe WorkspaceInfo
  , context_window :: Maybe ContextWindow
  , output_style   :: Maybe StyleInfo
  } deriving (Generic)
instance FromJSON StatusInput

newtype ModelInfo = ModelInfo { display_name :: String } deriving (Generic)
instance FromJSON ModelInfo

newtype WorkspaceInfo = WorkspaceInfo { current_dir :: String } deriving (Generic)
instance FromJSON WorkspaceInfo

data ContextWindow = ContextWindow
  { remaining_percentage :: Maybe Double
  , total_input_tokens   :: Maybe Int
  , total_output_tokens  :: Maybe Int
  , context_window_size  :: Maybe Int
  } deriving (Generic)
instance FromJSON ContextWindow

newtype StyleInfo = StyleInfo { name :: String } deriving (Generic)
instance FromJSON StyleInfo

-- Credentials file (~/.claude/.credentials.json)
newtype CredFile = CredFile { claudeAiOauth :: Maybe OAuthCred } deriving (Generic)
instance FromJSON CredFile

newtype OAuthCred = OAuthCred { accessToken :: Maybe String } deriving (Generic)
instance FromJSON OAuthCred

-- Usage cache (CLAUDE_USAGE_CACHE)
data UsageWindow = UsageWindow
  { utilization :: Maybe Double
  , resets_at   :: Maybe String
  } deriving (Generic)
instance FromJSON UsageWindow

data UsageCache = UsageCache
  { five_hour :: Maybe UsageWindow
  , seven_day :: Maybe UsageWindow
  } deriving (Generic)
instance FromJSON UsageCache

emptyInput :: StatusInput
emptyInput = StatusInput Nothing Nothing Nothing Nothing

-------------------- Atelier Cave palette --------------------

type Color = (Int, Int, Int)

cOrange, cAqua, cBlue, cPurple, cBg1, cFg0 :: Color
cOrange = (170, 87, 60)
cAqua   = (57, 139, 198)
cBlue   = (87, 109, 219)
cPurple = (149, 90, 231)
cBg1    = (25, 23, 28)
cFg0    = (239, 236, 244)

fgC :: Color -> String
fgC (r, g, b) = "\ESC[38;2;" ++ show r ++ ";" ++ show g ++ ";" ++ show b ++ "m"

bgC :: Color -> String
bgC (r, g, b) = "\ESC[48;2;" ++ show r ++ ";" ++ show g ++ ";" ++ show b ++ "m"

reset :: String
reset = "\ESC[0m"

fgWhite :: String
fgWhite = fgC cFg0

------------------- Nerd font icons -------------------------

iconNix, iconFolder, iconGit, iconRocket, iconBattery, iconCalendar, iconBrain, iconBrush :: Char
iconNix      = '\xF313'   -- nf-linux-nixos
iconFolder   = '\xF07B'   -- nf-fa-folder
iconGit      = '\xE725'   -- nf-dev-git_branch
iconRocket   = '\xF135'   -- nf-fa-rocket
iconBattery  = '\xF0079'  -- nf-md-battery_50
iconCalendar = '\xF051B'  -- nf-md-calendar_clock
iconBrain    = '\xF02A0'  -- nf-md-brain
iconBrush    = '\xF1FC'   -- nf-fa-paint_brush

------------------- Powerline rendering ---------------------

-- | (bg color, entry separator, content)
type Segment = (Color, Char, String)

-- | Standard segment using \xE0B0 arrow as entry separator.
seg :: Color -> String -> Segment
seg c content = (c, '\xE0B0', content)

-- | Render a list of segments with powerline separators.
--
-- Opening:    fg=color \xE0B6 (left half-circle into segment)
-- Transition: fg=prev bg=next [sep] (per-segment separator)
-- Closing:    reset fg=color \xE0B0 (arrow from segment into transparent)
renderLine :: [Segment] -> String
renderLine [] = ""
renderLine ((c, _, content) : rest) =
  fgC c ++ "\xE0B6"
  ++ bgC c ++ fgWhite ++ content
  ++ go c rest
  where
    go prev [] = reset ++ fgC prev ++ "\xE0B0" ++ reset
    go prev ((c', sep, txt) : more) =
      fgC prev ++ bgC c' ++ [sep]
      ++ fgWhite ++ txt
      ++ go c' more

----------------------- Formatting --------------------------

formatTokens :: Int -> String
formatTokens n
  | n >= 1000000 = showFFloat (Just 1) (fromIntegral n / 1000000 :: Double) "M"
  | n >= 1000    = show (n `div` 1000) ++ "K"
  | otherwise    = show n

formatCountdown :: NominalDiffTime -> String
formatCountdown dt
  | secs <= 0    = "now"
  | secs < 3600  = show mins ++ "m"
  | secs < 86400 = show hrs ++ "h " ++ show rMins ++ "m"
  | otherwise     = show days ++ "d " ++ show rHrs ++ "h"
  where
    secs  = floor dt :: Int
    mins  = secs `div` 60
    hrs   = secs `div` 3600
    rMins = (secs `mod` 3600) `div` 60
    days  = secs `div` 86400
    rHrs  = (secs `mod` 86400) `div` 3600

formatUtil :: Double -> Maybe UTCTime -> UTCTime -> String
formatUtil util mReset now =
  show (round util :: Int) ++ "%"
  ++ case mReset of
       Nothing -> ""
       Just resetAt -> " (" ++ formatCountdown (diffUTCTime resetAt now) ++ ")"

--------------------------- Git -----------------------------

gitIn :: String -> [String] -> IO (Maybe String)
gitIn dir args = do
  (exit, out, _) <- readCreateProcessWithExitCode (proc "git" ("-C" : dir : args)) ""
  pure $ case exit of
    ExitSuccess -> Just (stripTrailingNewlines out)
    _           -> Nothing
  where
    stripTrailingNewlines = reverse . dropWhile (== '\n') . reverse

----------------------- Usage cache -------------------------

getUsageCachePath :: IO FilePath
getUsageCachePath = fromMaybe "/tmp/.claude_usage_cache" <$> lookupEnv "CLAUDE_USAGE_CACHE"

data UsageInfo = UsageInfo
  { fiveHourUtil  :: Maybe Double
  , fiveHourReset :: Maybe UTCTime
  , sevenDayUtil  :: Maybe Double
  , sevenDayReset :: Maybe UTCTime
  }

emptyUsage :: UsageInfo
emptyUsage = UsageInfo Nothing Nothing Nothing Nothing

parseISO :: String -> Maybe UTCTime
parseISO s = zonedTimeToUTC <$> (iso8601ParseM s :: Maybe ZonedTime)

toUsageInfo :: UsageCache -> UsageInfo
toUsageInfo (UsageCache mFive mSeven) = UsageInfo
  { fiveHourUtil  = utilization =<< mFive
  , fiveHourReset = parseISO =<< resets_at =<< mFive
  , sevenDayUtil  = utilization =<< mSeven
  , sevenDayReset = parseISO =<< resets_at =<< mSeven
  }

readUsageCache :: FilePath -> IO UsageInfo
readUsageCache cachePath = catch readIt (\e -> let _ = e :: SomeException in pure emptyUsage)
  where
    readIt = do
      exists <- doesFileExist cachePath
      if not exists then pure emptyUsage else do
        bytes <- BL.readFile cachePath
        pure $ maybe emptyUsage toUsageInfo (decode bytes)

---------------------- Fetch mode ---------------------------

isCacheFresh :: FilePath -> UTCTime -> IO Bool
isCacheFresh cachePath now = do
  exists <- doesFileExist cachePath
  if not exists then pure False else do
    mtime <- getModificationTime cachePath
    pure (diffUTCTime now mtime < 30)

runFetch :: IO ()
runFetch = void $ runMaybeT $ do
  cachePath <- lift getUsageCachePath
  now       <- lift getCurrentTime
  fresh     <- lift $ isCacheFresh cachePath now
  guard (not fresh)
  home <- lift getHomeDirectory
  let credPath = home ++ "/.claude/.credentials.json"
  credExists <- lift $ doesFileExist credPath
  guard credExists
  credBytes <- lift $ BL.readFile credPath
  cred  <- MaybeT . pure $ (decode credBytes :: Maybe CredFile)
  oauth <- MaybeT . pure $ claudeAiOauth cred
  token <- MaybeT . pure $ accessToken oauth
  guard (not (null token))
  (exit, out, _) <- lift $ readCreateProcessWithExitCode
    (proc "curl" [ "-sf", "--max-time", "10"
                 , "-H", "Authorization: Bearer " ++ token
                 , "-H", "anthropic-beta: oauth-2025-04-20"
                 , "https://api.anthropic.com/oauth/usage"
                 ]) ""
  guard (exit == ExitSuccess)
  lift $ writeFile cachePath out

----------------------- Statusline --------------------------

runStatusline :: IO ()
runStatusline = do
  input <- BL.getContents
  let si = fromMaybe emptyInput (decode input)

  let cwd    = maybe "" current_dir (workspace si)
      mdl    = maybe "" display_name (model si)
      styl   = maybe "" name (output_style si)
      mCtx   = context_window si
      ctxPct = remaining_percentage =<< mCtx
      inTok  = fromMaybe 0 (total_input_tokens =<< mCtx)
      outTok = fromMaybe 0 (total_output_tokens =<< mCtx)
      ctxMax = fromMaybe 0 (context_window_size =<< mCtx)

  -- Git info
  isGit <- gitIn cwd ["rev-parse", "--git-dir"]
  (branchName, gitSt) <- case isGit of
    Nothing -> pure ("", "")
    Just _  -> do
      mb <- gitIn cwd ["branch", "--show-current"]
      case mb of
        Nothing -> pure ("", "")
        Just "" -> pure ("", "")
        Just b  -> do
          dirty     <- gitIn cwd ["diff", "--quiet"]
          untracked <- gitIn cwd ["ls-files", "--others", "--exclude-standard"]
          let d  = case dirty of Nothing -> "!"; _ -> ""
              u  = case untracked of Just s | not (null s) -> "?"; _ -> ""
              st = case d ++ u of "" -> ""; s -> " " ++ s
          pure (b, st)

  -- Usage info
  cachePath <- getUsageCachePath
  now <- getCurrentTime
  usage <- readUsageCache cachePath

  -- Nix shell detection (like starship's nix_shell module)
  dirIcon <- maybe iconFolder (const iconNix) <$> lookupEnv "IN_NIX_SHELL"

  -- Build segments
  let dir = takeFileName cwd

      segDir = Just (seg cOrange $ [' ', dirIcon, ' '] ++ dir ++ " ")

      segGit | null branchName = Nothing
             | otherwise = Just (seg cAqua $ [' ', iconGit, ' '] ++ branchName ++ gitSt ++ " ")

      segModel = Just (seg cBlue $ [' ', iconRocket, ' '] ++ mdl ++ " ")

      fmt5h u = [' ', iconBattery] ++ " 5h " ++ formatUtil u (fiveHourReset usage) now
      fmt7d u = [' ', iconCalendar] ++ " 7d " ++ formatUtil u (sevenDayReset usage) now
      segUsage = case (fiveHourUtil usage, sevenDayUtil usage) of
        (Nothing, Nothing) -> Nothing
        (Just u5, Nothing) -> Just (seg cPurple $ fmt5h u5 ++ " ")
        (Nothing, Just u7) -> Just (seg cPurple $ fmt7d u7 ++ " ")
        (Just u5, Just u7) -> Just (seg cPurple $ fmt5h u5 ++ fmt7d u7 ++ " ")

      -- \xE0C4 = powerline right hard divider (flame style) for dark tail
      totalTok = inTok + outTok
      segCtx = case ctxPct of
        Nothing -> Nothing
        Just p
          | ctxMax > 0 ->
              let usedPct = 100 - round p :: Int
              in Just (cBg1, '\xE0C4', [' ', iconBrain] ++ " ctx " ++ show usedPct ++ "% "
                          ++ formatTokens totalTok ++ "/" ++ formatTokens ctxMax ++ " ")
          | totalTok > 0 ->
              Just (cBg1, '\xE0C4', [' ', iconBrain, ' '] ++ show (round p :: Int) ++ "% "
                       ++ formatTokens totalTok ++ " ")
          | otherwise ->
              Just (cBg1, '\xE0C4', [' ', iconBrain, ' '] ++ show (round p :: Int) ++ "% ")

      segStyle | null styl || styl == "default" = Nothing
               | otherwise = Just (cBg1, '\xE0C4', [' ', iconBrush, ' '] ++ styl ++ " ")

  putStrLn $ renderLine (catMaybes [segDir, segGit, segModel, segUsage, segCtx, segStyle])

--------------------------- Main ----------------------------

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--fetch"] -> catch runFetch (\e -> let _ = e :: SomeException in pure ())
    _           -> runStatusline
