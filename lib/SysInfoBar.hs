
import Control.Concurrent
import Control.Monad
import Data.Char
import Data.Either
import Data.Word
import System.BSD.Sysctl
import System.Directory
import System.Environment
import System.Exit
import System.Posix.Signals
import System.Process
import System.IO
import System.IO.Error
import System.Info
import Text.Printf
import Text.Read

import qualified DateFormatter as DF

type NetRx = Int
type NetTx = Int
data NetLoad = NetLoad NetRx NetTx

type CPUUsed = Int
type CPUTotal = Int
data CPULoad = CPULoad CPUUsed CPUTotal

type MemTotal = Int
type MemFree = Int
data MemStat = MemStat MemTotal MemFree

type SwapPercent = Int

getFreeBSDNetLoad :: String -> IO NetLoad
getFreeBSDNetLoad iface = do
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

-- getOpenBSDNetLoad :: String -> IO NetLoad
-- getOpenBSDNetLoad iface = do
--         str <- readProcess "/usr/bin/netstat" ["-i", "-I", iface, "-b"] []
--         let ls = tail $ lines str
--         if (null ls) then
--                 return $ NetLoad 0 0
--                 else
--                         let rr = words $ head ls
--                             rx = read $ rr !! 4
--                             tx = read $ rr !! 5
--                         in
--                                 return $ NetLoad rx tx

getNetSpeeds :: (NetLoad,NetLoad) -> (String,String)
getNetSpeeds (NetLoad oldrx oldtx, NetLoad currx curtx) =
        (netspeed $ currx-oldrx, netspeed $ curtx - oldtx)

netspeed :: Int -> String
netspeed x
        | x > 2 * 1024 ^ 3          =       (printf "% 5.2f" (((fromIntegral x)/(1024^3)) :: Double)) ++ "GB"
        | x > 2 * 1024 ^ 2          =       (printf "% 5.2f" (((fromIntegral x)/(1024^2)) :: Double)) ++ "MB"
        | x > 2 * 1024              =       (printf "% 5.2f" (((fromIntegral x)/1024) :: Double)) ++ "kB"
        | otherwise                 =       (printf "% 5d " x) ++ "B "

isNotTimezone :: String -> Bool
isNotTimezone str = not $ foldr (\x -> (&&) (isUpper x)) True str

endsWithDot :: String -> Bool
endsWithDot str = (length str > 0) && (last str) == '.'

filterSeconds :: String -> String
filterSeconds str =
        if fmap isDigit str == [True,True,False,True,True,False,True,True] &&
                fmap (== ':') str == [False,False,True,False,False,True,False,False] then
                        take 5 str else str

hotCPUColor :: Int -> String
hotCPUColor perc
        | perc < 33             = "lightblue"
        | perc < 66             = "orange"
        | otherwise             = "red"

hotMemColor :: MemStat -> String
hotMemColor memstat
        | perc < 60             = "lightblue"
        | perc < 80             = "orange"
        | otherwise             = "red"
        where perc = getMemPercent memstat

hotSwapColor :: Int -> String
hotSwapColor perc
        | perc < 5             = "lightblue"
        | perc < 20             = "orange"
        | otherwise             = "red"

displayStats :: String -> Handle -> Int -> MemStat -> SwapPercent -> (String,String) -> IO()
displayStats locale pipe cpuperc memstat swapperc (net_rx,net_tx) = do
        datestr <- DF.getTimeAndDate locale
        hPutStrLn pipe $
                "<icon=cpu.xbm/><fc=" ++ hotCPUColor cpuperc ++ "> " ++ (show cpuperc) ++ "%</fc>   " ++
                "<icon=mem.xbm/><fc=" ++ hotMemColor memstat ++ "> " ++ (show $ getMemPercent memstat) ++ "%</fc>   " ++
                "<icon=swap.xbm/><fc=" ++ hotSwapColor swapperc ++ "> " ++ (show swapperc) ++ "%</fc>   " ++
                "<icon=net_wired.xbm/> " ++
                "<icon=net_down_03.xbm/> " ++ net_rx ++ " " ++
                "<icon=net_up_03.xbm/> " ++ net_tx ++ " " ++
                "<fc=yellow>" ++ datestr ++ "</fc>"
        hFlush pipe

getSwapStats :: IO SwapPercent
getSwapStats = do
        swap <- fmap rights $
                mapM (\nr -> tryIOError (
                        sysctlNameToOidArgs "vm.swap_info" [ nr ] >>=
                                sysctlPeekArray :: IO [Word32])) [0..15]
        let tot = sum $ fmap (!! 3) swap
            used = sum $ fmap (!! 4) swap
        return $ fromIntegral $ (used * 100) `div` tot

gatherLoop :: String -> (OID, Int, OID) -> CPULoad -> (String -> IO NetLoad) -> Handle
        -> NetLoad -> String -> IO()
gatherLoop locale (oid_cpuload, memtotal, oid_memused) oldcpuload netloadfunc pipe lastnet iface = do
        cpuload <- getCPULoad oid_cpuload
        memstat <- getMemStat (memtotal, oid_memused)
        netload <- netloadfunc iface
        swapload <- getSwapStats
        displayStats locale pipe (getCPUPercent (oldcpuload, cpuload)) memstat swapload (getNetSpeeds (lastnet, netload))
        threadDelay 1000000
        gatherLoop locale (oid_cpuload, memtotal, oid_memused) cpuload netloadfunc pipe netload iface

startBSD :: String -> String -> Handle -> IO()
startBSD locale iface pipe = do
        oid_cpuload <- sysctlNameToOid "kern.cp_time"
        oid_memtotal <- sysctlNameToOid "vm.stats.vm.v_page_count"
        oid_memfree <- sysctlNameToOid "vm.stats.vm.v_free_count"
        cpuload <- getCPULoad oid_cpuload
        netinit <- getFreeBSDNetLoad iface
        memtotal <- sysctlReadUInt oid_memtotal
        gatherLoop locale (oid_cpuload, fromIntegral memtotal, oid_memfree)
                cpuload getFreeBSDNetLoad pipe netinit iface

getCPUPercent :: (CPULoad,CPULoad) -> Int
getCPUPercent (CPULoad oldused oldtotal, CPULoad curused curtotal) =
        let     deltatotal = curtotal - oldtotal
                deltaused = curused - oldused
                in if deltatotal > 0 then (100*deltaused) `div` deltatotal else 0

getMemPercent :: MemStat -> Int
getMemPercent (MemStat total free) = 100 - ((free * 100) `div` total)

getMemStat :: (Int, OID) -> IO MemStat
getMemStat (memtotal, oid_memfree) = do
        memfree <- sysctlReadUInt oid_memfree
        return $ MemStat memtotal (fromIntegral memfree)

getCPULoad :: OID -> IO CPULoad
getCPULoad oid_cpuload = do
        cpuloads2 <- sysctlPeekArray oid_cpuload :: IO [Word64]
        let     cpuloads = fmap fromIntegral cpuloads2
                total = sum cpuloads
                used = total - last cpuloads
                in return $ CPULoad used total

spawnPipe :: [ String ] -> IO Handle
spawnPipe cmd = do
        (Just hin, _, _, _) <- createProcess (proc (head cmd) (tail cmd)){ std_in = CreatePipe }
        return hin

xmobarSysInfo :: FilePath -> [ String ]
xmobarSysInfo homedir = [ "xmobar", homedir ++ "/.xmonad/sysinfo_xmobar.rc" ]

installSignals :: IO ()
installSignals = do
        ppid <- myThreadId
        mapM_ (\sig -> installHandler sig (Catch $ trap ppid) Nothing)
                [ lostConnection, keyboardSignal, softwareTermination, processStatusChanged ]

trap tid = do
        throwTo tid ExitSuccess

main = do
        homedir <- getHomeDirectory
        args <- getArgs
        case args of
                [ locale, iface ]      -> spawnPipe (xmobarSysInfo homedir) >>= (
                        case os of
                                "freebsd" -> startBSD locale iface
                                _         -> error $ "Unknown operating system " ++ os
                        )
                _              -> error "Error in parameters. Need locale and network interface."
