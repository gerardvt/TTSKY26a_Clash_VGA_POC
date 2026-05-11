import System.Environment (getArgs)
import qualified Clash.Main as Clash

main :: IO ()
main = getArgs >>= Clash.defaultMain
