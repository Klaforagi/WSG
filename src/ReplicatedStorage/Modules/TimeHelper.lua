--------------------------------------------------------------------------------
-- TimeHelper.lua  –  Centralized server-authoritative reset-time helper.
--
-- Used by QuestService (daily reset), WeeklyQuestService (weekly reset), and
-- the client UIs that show countdown timers. ALL reset boundaries flow
-- through this module so they can be corrected in one place.
--
-- Daily reset:  midnight (00:00) Eastern Time, every day.
-- Weekly reset: Saturday 00:00 Eastern Time, every week.
--
-- Eastern Time handles EST (UTC-5) and EDT (UTC-4) using the standard US rule:
--   DST starts: 2nd Sunday of March   at 02:00 local
--   DST ends:   1st Sunday of November at 02:00 local
-- This is sufficient for game-play resets (a one-hour edge case at the
-- transition is acceptable). Centralized so it can be replaced later.
--
-- All "now" calls use os.time() which is UTC seconds-since-epoch on Roblox
-- servers, so this module is server-authoritative regardless of client
-- timezone.
--------------------------------------------------------------------------------

local TimeHelper = {}

local SECONDS_PER_DAY  = 86400
local SECONDS_PER_HOUR = 3600

--------------------------------------------------------------------------------
-- Determine UTC offset (in seconds) for US Eastern Time at the given UTC time.
-- Returns -5*3600 during EST, -4*3600 during EDT.
--------------------------------------------------------------------------------
local function getEasternOffsetSeconds(utcTime)
    local dt = os.date("!*t", utcTime)
    local year  = dt.year
    local month = dt.month
    local day   = dt.day
    local hour  = dt.hour

    -- Compute weekday (1=Sun..7=Sat) of the 1st of March in this year.
    local marchFirst = os.time({ year = year, month = 3, day = 1, hour = 12, min = 0, sec = 0 })
    local marchFirstDow = tonumber(os.date("!%w", marchFirst)) -- 0..6 Sun..Sat
    -- 2nd Sunday of March = 1 + (7 - dow) % 7 + 7
    local secondSundayMarch = 1 + ((7 - marchFirstDow) % 7) + 7

    -- 1st Sunday of November
    local novFirst = os.time({ year = year, month = 11, day = 1, hour = 12, min = 0, sec = 0 })
    local novFirstDow = tonumber(os.date("!%w", novFirst))
    local firstSundayNov = 1 + ((7 - novFirstDow) % 7)

    -- DST window in (year, month, day, hour) UTC -- approximated by treating
    -- the 02:00 local boundary as a simple day cutoff. Acceptable for reset.
    local afterStart =
        (month > 3) or
        (month == 3 and day > secondSundayMarch) or
        (month == 3 and day == secondSundayMarch and hour >= 7) -- 02:00 EST = 07:00 UTC
    local beforeEnd =
        (month < 11) or
        (month == 11 and day < firstSundayNov) or
        (month == 11 and day == firstSundayNov and hour < 6)    -- 02:00 EDT = 06:00 UTC

    if afterStart and beforeEnd then
        return -4 * SECONDS_PER_HOUR -- EDT
    end
    return -5 * SECONDS_PER_HOUR     -- EST
end

TimeHelper.GetEasternOffsetSeconds = getEasternOffsetSeconds

--------------------------------------------------------------------------------
-- Convert a UTC epoch to "Eastern Time" epoch by adding the offset.
-- (Result is a fake epoch suitable for os.date("!*t", ...) to read as ET.)
--------------------------------------------------------------------------------
function TimeHelper.UtcToEasternEpoch(utcTime)
    utcTime = utcTime or os.time()
    return utcTime + getEasternOffsetSeconds(utcTime)
end

--------------------------------------------------------------------------------
-- Daily key — calendar day in Eastern Time. Stable storage key for daily
-- resets. Format: "YYYY-MM-DD".
--------------------------------------------------------------------------------
function TimeHelper.GetDailyKey(utcTime)
    utcTime = utcTime or os.time()
    local etEpoch = TimeHelper.UtcToEasternEpoch(utcTime)
    return os.date("!%Y-%m-%d", etEpoch)
end

--------------------------------------------------------------------------------
-- Weekly key — Saturday-anchored week in Eastern Time. Stable storage key
-- for weekly resets. Format: "YYYY-WMM-DD" of the most recent Saturday 00:00
-- ET (i.e. the start of the current weekly window).
--------------------------------------------------------------------------------
function TimeHelper.GetWeeklyKey(utcTime)
    utcTime = utcTime or os.time()
    local etEpoch = TimeHelper.UtcToEasternEpoch(utcTime)
    local etDt = os.date("!*t", etEpoch)
    -- Saturday = 7 (Sun=1..Sat=7) — convert from os.date %w (0..6 Sun..Sat).
    local etDow = tonumber(os.date("!%w", etEpoch)) -- 0..6 Sun..Sat
    -- Days back to the most recent Saturday.
    -- Saturday %w = 6. daysBack = (etDow + 1) % 7 makes Sat=0, Sun=1, ..., Fri=6.
    local daysBack = (etDow + 1) % 7
    local weekStartEt = etEpoch
        - (etDt.hour * SECONDS_PER_HOUR + etDt.min * 60 + etDt.sec)
        - daysBack * SECONDS_PER_DAY
    return os.date("!%Y-%m-%d", weekStartEt)
end

--------------------------------------------------------------------------------
-- Seconds remaining until the NEXT daily reset (next midnight Eastern).
--------------------------------------------------------------------------------
function TimeHelper.SecondsUntilNextDailyReset(utcTime)
    utcTime = utcTime or os.time()
    local etEpoch = TimeHelper.UtcToEasternEpoch(utcTime)
    local etDt = os.date("!*t", etEpoch)
    local secondsIntoDay = etDt.hour * SECONDS_PER_HOUR + etDt.min * 60 + etDt.sec
    return SECONDS_PER_DAY - secondsIntoDay
end

--------------------------------------------------------------------------------
-- Seconds remaining until the NEXT weekly reset (next Saturday 00:00 Eastern).
--------------------------------------------------------------------------------
function TimeHelper.SecondsUntilNextWeeklyReset(utcTime)
    utcTime = utcTime or os.time()
    local etEpoch = TimeHelper.UtcToEasternEpoch(utcTime)
    local etDt = os.date("!*t", etEpoch)
    local etDow = tonumber(os.date("!%w", etEpoch)) -- 0..6 Sun..Sat
    -- Days forward to next Saturday (exclusive: if today IS Saturday and
    -- before midnight, next reset is in 7 days minus today's elapsed).
    -- daysForward = (6 - etDow) % 7 puts Sat=0 (today, but we want NEXT).
    local daysForward = (6 - etDow) % 7
    if daysForward == 0 then
        daysForward = 7 -- if today is Saturday, next reset is one week away
    end
    local secondsIntoDay = etDt.hour * SECONDS_PER_HOUR + etDt.min * 60 + etDt.sec
    return daysForward * SECONDS_PER_DAY - secondsIntoDay
end

--------------------------------------------------------------------------------
-- Format a number of seconds as a human-readable countdown.
--   >= 1d -> "Xd Yh"
--   >= 1h -> "Hh Mm"
--   else  -> "Mm Ss"
--------------------------------------------------------------------------------
function TimeHelper.FormatCountdown(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local d = math.floor(seconds / 86400)
    local h = math.floor((seconds % 86400) / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if d > 0 then
        return string.format("%dd %dh", d, h)
    elseif h > 0 then
        return string.format("%dh %02dm", h, m)
    else
        return string.format("%dm %02ds", m, s)
    end
end

return TimeHelper
