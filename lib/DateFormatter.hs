module DateFormatter where

import Data.Time.Format
import Data.Time.LocalTime

getTimeLocale :: String -> TimeLocale
getTimeLocale "de" = TimeLocale {
        wDays = fmap (\x -> (x, take 2 x)) [ "Sonntag", "Montag", "Dienstag",
                "Mittwoch", "Donnerstag", "Freitag", "Samstag" ],
        months = fmap (\x -> (x, take 3 x)) [ "Januar", "Februar", "März",
                "April", "Mai", "Juni", "Juli", "August", "September",
                "Oktober", "November", "Dezember" ],
        amPm = ("früh", "nachm."),
        dateTimeFmt = "%a %e %b %Y %H:%M:%S",
        dateFmt = "%a, den %e. %B %Y",
        timeFmt = "%H:%M:%S",
        time12Fmt = "%l Uhr %-zM %P",
        knownTimeZones = [
                TimeZone { timeZoneMinutes = 60, timeZoneSummerOnly = False, timeZoneName = "CET" },
                TimeZone { timeZoneMinutes = 120, timeZoneSummerOnly = True, timeZoneName = "CET-DST" }
                ]
        }
getTimeLocale _ = defaultTimeLocale

getTimeAndDate :: String -> IO String
getTimeAndDate localename = do
        localtime <- getZonedTime
        return $ formatTime locale (dateTimeFmt locale) localtime
        where locale = getTimeLocale localename