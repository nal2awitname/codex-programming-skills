import Data.List (intercalate)
import System.Environment (getArgs)
import System.Exit (ExitCode (ExitFailure), exitWith)

main :: IO ()
main = do
  values <- getArgs
  putStrLn ("OK:" ++ intercalate "|" values)
  exitWith (ExitFailure 3)
