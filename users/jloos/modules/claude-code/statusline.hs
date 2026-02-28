{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Aeson (Value (..), decode)
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (fromMaybe)
import qualified Data.Text as T
import Numeric (showFFloat)
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

--------------------------- Git -----------------------------

gitIn :: String -> [String] -> IO (Maybe String)
gitIn dir args = do
  (exit, out, _) <- readCreateProcessWithExitCode (proc "git" ("-C" : dir : args)) ""
  pure $ case exit of
    ExitSuccess -> Just (stripTrailingNewlines out)
    _           -> Nothing
  where
    stripTrailingNewlines = reverse . dropWhile (== '\n') . reverse

--------------------------- Main ----------------------------

main :: IO ()
main = do
  input <- BL.getContents
  let json = fromMaybe (Object KM.empty) (decode input)

  let cwd    = jsonStr json ["workspace", "current_dir"]
      model  = jsonStr json ["model", "display_name"]
      style  = jsonStr json ["output_style", "name"]
      ctxPct = jsonNum json ["context_window", "remaining_percentage"]
      inTok  = maybe 0 round (jsonNum json ["context_window", "total_input_tokens"]) :: Int
      outTok = maybe 0 round (jsonNum json ["context_window", "total_output_tokens"]) :: Int

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

  -- Build segments
  let dir = takeFileName cwd

      segDir   = bgBrown ++ fgWhite ++ " " ++ dir ++ " " ++ reset

      segGit   | null branch = ""
               | otherwise   = bgBlue ++ fgWhite ++ branch ++ gitSt ++ " " ++ reset

      segModel = bgPurple ++ fgBlue ++ " " ++ fgWhite ++ model ++ " " ++ reset

      segCtx   = case ctxPct of
                   Nothing -> ""
                   Just p  -> bgDark ++ fgGray ++ "  " ++ show (round p :: Int) ++ "% " ++ reset

      totalTok = inTok + outTok
      segTok   | totalTok <= 0 = ""
               | otherwise     = bgDark ++ fgGray ++ "  " ++ formatTokens totalTok ++ " " ++ reset

      segStyle | null style || style == "default" = ""
               | otherwise = bgDark ++ fgGray ++ "  " ++ style ++ " " ++ reset

  putStrLn $ segDir ++ segGit ++ segModel ++ segCtx ++ segTok ++ segStyle
