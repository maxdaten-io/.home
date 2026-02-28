{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Exception (SomeException, catch)
import Data.Aeson (Value (..), decode)
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import Data.Time.Clock (NominalDiffTime, UTCTime, diffUTCTime, getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Data.Time.LocalTime (ZonedTime, zonedTimeToUTC)
import Numeric (showFFloat)
import System.Directory (doesFileExist, getHomeDirectory, getModificationTime)
import System.Environment (getArgs)
import System.Exit (ExitCode (..))
import System.FilePath (takeFileName)
import System.Process (proc, readCreateProcessWithExitCode)

-------------------- Atelier Cave palette --------------------

-- Background colors
bgBrown, bgBlue, bgPurple, bgDark :: String
bgBrown  = "\ESC[48;2;160;110;59m"
bgBlue   = "\ESC[48;2;57;139;198m"
bgPurple = "\ESC[48;2;87;109;219m"
bgDark   = "\ESC[48;2;25;23;28m"

-- Foreground colors
fgWhite, fgBlue, fgGray :: String
fgWhite = "\ESC[38;2;239;236;244m"
fgBlue  = "\ESC[38;2;57;139;198m"
fgGray  = "\ESC[38;2;113;105;101m"

reset :: String
reset = "\ESC[0m"

------------------------ JSON helpers ------------------------

lookupNested :: Value -> [T.Text] -> Maybe Value
lookupNested v [] = Just v
lookupNested (Object obj) (k : ks) =
  case KM.lookup (K.fromText k) obj of
    Just v  -> lookupNested v ks
    Nothing -> Nothing
lookupNested _ _ = Nothing

jsonStr :: Value -> [T.Text] -> String
jsonStr v path = case lookupNested v path of
  Just (String t) -> T.unpack t
  _               -> ""

jsonMaybeStr :: Value -> [T.Text] -> Maybe String
jsonMaybeStr v path = case lookupNested v path of
  Just (String t) -> Just (T.unpack t)
  _               -> Nothing

jsonNum :: Value -> [T.Text] -> Maybe Double
jsonNum v path = case lookupNested v path of
  Just (Number n) -> Just (realToFrac n)
  _               -> Nothing

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

usageCachePath :: FilePath
usageCachePath = "/tmp/.claude_usage_cache"

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

readUsageCache :: IO UsageInfo
readUsageCache = catch readIt (\e -> let _ = e :: SomeException in pure emptyUsage)
  where
    readIt = do
      exists <- doesFileExist usageCachePath
      if not exists then pure emptyUsage else do
        bytes <- BL.readFile usageCachePath
        case decode bytes of
          Nothing -> pure emptyUsage
          Just json -> pure UsageInfo
            { fiveHourUtil  = jsonNum json ["five_hour", "utilization"]
            , fiveHourReset = parseISO =<< jsonMaybeStr json ["five_hour", "resets_at"]
            , sevenDayUtil  = jsonNum json ["seven_day", "utilization"]
            , sevenDayReset = parseISO =<< jsonMaybeStr json ["seven_day", "resets_at"]
            }

formatUsageSeg :: String -> Maybe Double -> Maybe UTCTime -> UTCTime -> String
formatUsageSeg label mUtil mReset now = case mUtil of
  Nothing -> ""
  Just util ->
    let countdown = case mReset of
          Nothing -> ""
          Just resetAt ->
            let diff = diffUTCTime resetAt now
            in " (" ++ formatCountdown diff ++ ")"
    in bgDark ++ fgGray ++ "  " ++ label ++ " " ++ show (round util :: Int) ++ "%" ++ countdown ++ " " ++ reset

---------------------- Fetch mode ---------------------------

isCacheFresh :: UTCTime -> IO Bool
isCacheFresh now = do
  exists <- doesFileExist usageCachePath
  if not exists then pure False else do
    mtime <- getModificationTime usageCachePath
    pure (diffUTCTime now mtime < 30)

runFetch :: IO ()
runFetch = do
  now <- getCurrentTime
  fresh <- isCacheFresh now
  if fresh then pure () else do
    home <- getHomeDirectory
    let credPath = home ++ "/.claude/.credentials.json"
    credExists <- doesFileExist credPath
    if not credExists then pure () else do
      credBytes <- BL.readFile credPath
      case decode credBytes of
        Nothing -> pure ()
        Just credJson -> do
          let token = jsonStr credJson ["claudeAiOauth", "accessToken"]
          if null token then pure () else do
            (exit, out, _) <- readCreateProcessWithExitCode
              (proc "curl" [ "-sf", "--max-time", "10"
                           , "-H", "Authorization: Bearer " ++ token
                           , "-H", "anthropic-beta: oauth-2025-04-20"
                           , "https://api.anthropic.com/oauth/usage"
                           ]) ""
            case exit of
              ExitSuccess -> writeFile usageCachePath out
              _           -> pure ()

----------------------- Statusline --------------------------

runStatusline :: IO ()
runStatusline = do
  input <- BL.getContents
  let json = fromMaybe (Object KM.empty) (decode input)

  let cwd    = jsonStr json ["workspace", "current_dir"]
      model  = jsonStr json ["model", "display_name"]
      style  = jsonStr json ["output_style", "name"]
      ctxPct = jsonNum json ["context_window", "remaining_percentage"]
      inTok  = maybe 0 round (jsonNum json ["context_window", "total_input_tokens"]) :: Int
      outTok = maybe 0 round (jsonNum json ["context_window", "total_output_tokens"]) :: Int
      ctxMax = maybe 0 round (jsonNum json ["context_window", "context_window_size"]) :: Int

  -- Git info
  isGit <- gitIn cwd ["rev-parse", "--git-dir"]
  (branch, gitSt) <- case isGit of
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
          pure (" " ++ b, st)

  -- Usage info
  now <- getCurrentTime
  usage <- readUsageCache

  -- Build segments
  let dir = takeFileName cwd

      segDir   = bgBrown ++ fgWhite ++ " " ++ dir ++ " " ++ reset

      segGit   | null branch = ""
               | otherwise   = bgBlue ++ fgWhite ++ branch ++ gitSt ++ " " ++ reset

      segModel = bgPurple ++ fgBlue ++ " " ++ fgWhite ++ model ++ " " ++ reset

      seg5h    = formatUsageSeg "5h" (fiveHourUtil usage) (fiveHourReset usage) now
      seg7d    = formatUsageSeg "7d" (sevenDayUtil usage) (sevenDayReset usage) now

      totalTok = inTok + outTok
      segCtx   = case ctxPct of
                   Nothing -> ""
                   Just p
                     | ctxMax > 0 ->
                         let usedPct = 100 - round p :: Int
                         in bgDark ++ fgGray ++ "  ctx " ++ show usedPct ++ "% "
                            ++ formatTokens totalTok ++ "/" ++ formatTokens ctxMax ++ " " ++ reset
                     | totalTok > 0 ->
                         bgDark ++ fgGray ++ "  " ++ show (round p :: Int) ++ "% "
                         ++ formatTokens totalTok ++ " " ++ reset
                     | otherwise ->
                         bgDark ++ fgGray ++ "  " ++ show (round p :: Int) ++ "% " ++ reset

      segStyle | null style || style == "default" = ""
               | otherwise = bgDark ++ fgGray ++ "  " ++ style ++ " " ++ reset

  putStrLn $ segDir ++ segGit ++ segModel ++ seg5h ++ seg7d ++ segCtx ++ segStyle

--------------------------- Main ----------------------------

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["--fetch"] -> catch runFetch (\e -> let _ = e :: SomeException in pure ())
    _           -> runStatusline
