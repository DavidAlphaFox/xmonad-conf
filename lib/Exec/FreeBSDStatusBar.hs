
import Control.Concurrent
import Data.Char
import Data.Time
import System.Environment
import System.Exit
import System.Posix.Signals
import System.Process
import System.IO
import Text.Printf
import RandR
import Command.CommandPipe
import Control.Monad.Trans.Class
import Control.Monad.Trans.State

type CPUUsed = Int
type CPUTotal = Int
data CPULoad = CPULoad CPUUsed CPUTotal

type MemFree = Int
type MemTotal = Int
data MemLoad = MemLoad MemFree MemTotal

type NetRx = Int
type NetTx = Int
data NetLoad = NetLoad NetRx NetTx

getSysCtlCombinedValue :: String -> IO [ String ]
getSysCtlCombinedValue name =  fmap words $ readProcess "/sbin/sysctl" [ "-n", name ] []

getSysCtlValues :: [ String ] -> IO [ String ]
getSysCtlValues names =  fmap lines $ readProcess "/sbin/sysctl" ("-n":names) []

getCPULoad :: IO CPULoad
getCPULoad = do
        loadv <- getSysCtlCombinedValue "kern.cp_time"
        return $ getSingleCPULoad loadv

getSingleCPULoad :: [ String ] -> CPULoad
getSingleCPULoad xs =
        let ints = fmap (\x -> read x :: Int) xs
            total = sum ints
            used = total - last ints
                in CPULoad used total

allCoreLoads :: IO [ CPULoad ]
allCoreLoads = do
        loadv <- getSysCtlCombinedValue "kern.cp_times"
        return $ splitCPULoads loadv

getBusyCPUs :: ([ CPULoad ], [ CPULoad ] ) -> (Int,Int)
getBusyCPUs (old,cur) =
        (foldr (\x -> (+) (if x then 1 else 0)) 0 $ fmap isbusy $ fmap getCPUPercent (zip old cur), length cur)
        where isbusy perc = perc >= 90

splitCPULoads :: [ String ] -> [ CPULoad ]
splitCPULoads [] = []
splitCPULoads xs =
        (getSingleCPULoad $ take 5 xs) : (splitCPULoads $ drop 5 xs)

getMemLoad :: IO MemLoad
getMemLoad = do
        loadv <- getSysCtlValues [ "vm.stats.vm.v_page_count", "vm.stats.vm.v_free_count", "vm.stats.vm.v_inactive_count" ]
        let ints = fmap (\x -> read x :: Int) loadv
            total = head ints
            free = sum $ tail ints
        return $ MemLoad free total

getNetLoad :: String -> IO NetLoad
getNetLoad iface = do
        str <- readProcess "/usr/bin/netstat" ["-i", "-I", iface, "-bW"] []
        let ls = tail $ lines str
        if (null ls) then
                return $ NetLoad 0 0
                else
                        let rr = words $ head ls
                            rx = read $ rr !! 7
                            tx = read $ rr !! 10
                        in
                                return $ NetLoad rx tx

getCPUPercent :: (CPULoad,CPULoad) -> Int
getCPUPercent (CPULoad oldused oldtotal, CPULoad curused curtotal) =
        let deltatotal = curtotal - oldtotal
            deltaused = curused - oldused
            in if deltatotal > 0 then (100*deltaused) `div` deltatotal else 0

getMemPercent :: MemLoad -> Int
getMemPercent (MemLoad free total) = (total - free) * 100 `div` total

getNetSpeeds :: (NetLoad,NetLoad) -> (String,String)
getNetSpeeds (NetLoad oldrx oldtx, NetLoad currx curtx) =
        (netspeed $ currx-oldrx, netspeed $ curtx - oldtx)

netspeed :: Int -> String
netspeed x
        | x > 2 * 1024 ^ 3          =       (printf "%.2f" (((fromIntegral x)/(1024^3)) :: Double)) ++ "GB"
        | x > 2 * 1024 ^ 2          =       (printf "%.2f" (((fromIntegral x)/(1024^2)) :: Double)) ++ "MB"
        | x > 2 * 1024              =       (printf "%.2f" (((fromIntegral x)/1024) :: Double)) ++ "kB"
        | otherwise                 =       (show x) ++ "B"

isNotTimezone :: String -> Bool
isNotTimezone str = not $ foldr (\x -> (&&) (isUpper x)) True str

filterSeconds :: String -> String
filterSeconds str =
        if fmap isDigit str == [True,True,False,True,True,False,True,True] &&
                fmap (== ':') str == [False,False,True,False,False,True,False,False] then
                        take 5 str else str

getTimeAndDate :: IO String
getTimeAndDate = do
        str <- fmap words $ readProcess "/bin/date" ["+%a %e %b %Y %H:%M"] []
        let f1 = fmap filterSeconds $ filter isNotTimezone str
        return $ unwords f1

getVolume :: IO Int
getVolume = do
        str <- readProcess "/usr/sbin/mixer" ["-S", "vol"] []
        let (left,d:right) = span (/= ':') $ drop 4 str
        return $ (read left + read right) `div` 2

hotCPUColor :: (Int,Int) -> String
hotCPUColor (hot,total)
        | hot == 0              = "lightblue"
        | hot <= total `div` 2  = "orange"
        | otherwise             = "red"

hotMemColor :: Int -> String
hotMemColor perc
        | perc < 60             = "lightblue"
        | perc < 80             = "orange"
        | otherwise             = "red"

displayStats :: Handle -> Int -> (Int,Int) -> Int -> (String,String) -> FilePath -> IO()
displayStats dzen cpu coreloads mem (net_rx,net_tx) homedir = do
        datestr <- getTimeAndDate
        vol <- getVolume
        hPutStrLn dzen $ "^fg(white)^pa(80) |  " ++
                "^fg(lightblue)^i(" ++ homedir ++ "/.xmonad/dzen2/cpu.xbm) ^fg(" ++ hotCPUColor coreloads ++ ")" ++ (show cpu) ++ "% " ++
                "^fg(lightblue)^pa(170) ^i(" ++ homedir ++ "/.xmonad/dzen2/mem.xbm) ^fg(" ++ hotMemColor mem ++ ")" ++ (show mem) ++ "% " ++
                "^fg(lightblue)^pa(235) ^i(" ++ homedir ++ "/.xmonad/dzen2/net_wired.xbm) " ++
                "^fg(lightblue)^pa(250) ^i(" ++ homedir ++ "/.xmonad/dzen2/net_down_03.xbm)" ++ net_rx ++ "   " ++
                "^fg(lightblue)^pa(325) ^i(" ++ homedir ++ "/.xmonad/dzen2/net_up_03.xbm)" ++ net_tx ++ "   " ++
                "^fg(lightblue)^pa(400) ^i(" ++ homedir ++ "/.xmonad/dzen2/volume.xbm) " ++ (show vol) ++ "% " ++
                "^fg(yellow) ^pa(460) " ++ datestr
        hFlush dzen

gatherLoop :: Handle -> Handle -> (TimeZone, Double, Double) -> [ XRandrOutput ] -> CPULoad -> [ CPULoad ]
        -> NetLoad -> FilePath -> String -> RandRState -> IO()
gatherLoop dzen cmdpipe (tz, long, lat) x_Outputs lastcpu lastcoreloads lastnet homedir iface randrstate = do
        cpuload <- getCPULoad
        coreloads <- allCoreLoads
        mem <- fmap getMemPercent getMemLoad
        netload <- getNetLoad iface
        displayStats dzen (getCPUPercent (lastcpu,cpuload))
                (getBusyCPUs (lastcoreloads,coreloads)) mem
                (getNetSpeeds (lastnet, netload)) homedir
        s <- evalStateT (updateDisplayLevel tz long lat x_Outputs) randrstate
        (pipe_still_open, ns) <- runStateT (pollCommands cmdpipe) s
        if pipe_still_open
                then do
                        threadDelay 1000000
                        gatherLoop dzen cmdpipe (tz, long, lat) x_Outputs cpuload coreloads netload homedir iface ns
                else
                        return ()

startFreeBSD :: FilePath -> String -> Double -> Double -> FilePath -> IO()
startFreeBSD homedir iface long lat pipe = do
         -- setEnv "LC_NUMERIC" "C"
         x_Outputs <- xRandrOutputs
         tz <- getCurrentTimeZone
         cpuinit <- getCPULoad
         coreloadsinit <- allCoreLoads
         netinit <- getNetLoad iface
         h <- bindCommandPipe pipe
         let initstate = if (long >= -180.0 && lat >= -180.0) then randRInitState else randRInitNopState
         gatherLoop stdout h (tz, long, lat) x_Outputs cpuinit coreloadsinit netinit homedir iface initstate

pollCommands :: Handle -> DisplayState Bool
pollCommands h = do
        (cmd, eof) <- lift $ getPipeCommandLine h
        case (cmd,eof) of
                (Nothing,True)  ->
                        do
                                lift $ hClose h
                                return False
                (Just cmd,False) -> execCommand cmd >> return True
                _ -> return True

execCommand :: String -> DisplayState ()
execCommand cmd = do
        s <- get
        case cmd of
                "shade_toggle" -> put $ RandRState { active = not $ active s, level = level s }
                _              -> return ()

installSignals :: FilePath -> IO ()
installSignals pipe = do
        ppid <- myThreadId
        mapM_ (\sig -> installHandler sig (Catch $ trap ppid pipe) Nothing)
                [ lostConnection, keyboardSignal, softwareTermination, openEndedPipe ]

trap tid pipe = do
        deleteNamedPipe pipe
        throwTo tid ExitSuccess

main :: IO()
main = do
        args <- getArgs
        case args of
                [ homedir, iface, longitude, latitude ]
                        -> do
                                let long = - (read longitude :: Double)
                                    lat = read latitude :: Double
                                    pipe = pipeFileName homedir
                                installSignals pipe
                                makeNamedPipe pipe
                                startFreeBSD homedir iface long lat pipe
                                deleteNamedPipe pipe
                _       -> error "Error in parameters."
