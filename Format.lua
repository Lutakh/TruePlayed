-- Format.lua - pure text formatting (ns.Fmt). Depends only on ns.L and ns.C.CC.
-- Every "%d" receives a math.floor-ed, finite value (Lua 5.5 raises on
-- non-integral floats). Colour/percent strings are memoized so the hot paths
-- (bar slots refreshed every second) allocate nothing after warm-up; the other
-- functions allocate and are cached by display key (the *Key functions) by
-- their callers. See SPEC-FINAL 3.7.
local ADDON, ns = ...
local L, C = ns.L, ns.C
local CC = C.CC

local type = type
local math_floor, math_ceil = math.floor, math.ceil
local string_format = string.format
local table_concat = table.concat
local date, wipe = date, wipe

local Fmt = {}
ns.Fmt = Fmt

local MAX_SECONDS = 3153600000   -- 100 years: keeps durations finite and small
local MAX_INT = 2147483647       -- keeps "%d" arguments inside 32 bits

-- Non-negative finite seconds (NaN and negatives -> 0, +inf clamped). Not floored.
local function Seconds(sec)
  if type(sec) ~= "number" or sec ~= sec or sec <= 0 then return 0 end
  if sec > MAX_SECONDS then return MAX_SECONDS end
  return sec
end

-- Finite number clamped to +-MAX_INT (NaN -> 0).
local function Finite(n)
  if type(n) ~= "number" or n ~= n then return 0 end
  if n > MAX_INT then return MAX_INT end
  if n < -MAX_INT then return -MAX_INT end
  return n
end

-- "8.2" / "8,2" from an integer count of tenths (t >= 0).
local function Tenths(t)
  local whole = math_floor(t / 10)
  return string_format("%d%s%d", whole, L.DECIMAL_SEP, t - whole * 10)
end

---------------------------------------------------------------------------
-- Durations
---------------------------------------------------------------------------
-- 1h 25m / 1 h 25. <60 s -> DUR_LT_1M; never seconds.
function Fmt.Duration(sec)
  local s = math_floor(Seconds(sec))
  if s < 60 then return L.DUR_LT_1M end
  if s < 3600 then return string_format(L.DUR_M, math_floor(s / 60)) end
  if s < 36000 then
    local h = math_floor(s / 3600)
    return string_format(L.DUR_H_M, h, math_floor((s - h * 3600) / 60))
  end
  if s < 86400 then return string_format(L.DUR_H, math_floor(s / 3600)) end
  local d = math_floor(s / 86400)
  return string_format(L.DUR_D_H, d, math_floor((s - d * 86400) / 3600))
end

-- Integer key: equal keys <=> equal Duration strings.
function Fmt.DurationKey(sec)
  local s = math_floor(Seconds(sec))
  if s < 60 then return 0 end
  if s < 36000 then return math_floor(s / 60) end
  if s < 86400 then return 1000000 + math_floor(s / 3600) end
  return 2000000 + math_floor(s / 3600)
end

-- 3d 4h 12m / 3 j 4 h 12 min.
function Fmt.DurationLong(sec)
  local s = math_floor(Seconds(sec))
  local d = math_floor(s / 86400)
  local rem = s - d * 86400
  local h = math_floor(rem / 3600)
  local m = math_floor((rem - h * 3600) / 60)
  if d > 0 then return string_format(L.DUR_LONG_DHM, d, h, m) end
  if h > 0 then return string_format(L.DUR_LONG_HM, h, m) end
  if m > 0 then return string_format(L.DUR_LONG_M, m) end
  return L.DUR_LT_1M
end

-- ETA body for s >= 60: minutes rounded up below 1 h, 5-minute steps below
-- 10 h, then whole hours, then days + hours from 48 h.
local function EtaBody(s)
  if s < 3600 then
    local m = math_ceil(s / 60)
    if m >= 60 then return string_format(L.DUR_H_M, 1, 0) end
    return string_format(L.DUR_M, m)
  end
  if s < 36000 then
    local m5 = math_floor(s / 300 + 0.5) * 5
    local h = math_floor(m5 / 60)
    if h >= 10 then return string_format(L.DUR_H, h) end
    return string_format(L.DUR_H_M, h, m5 - h * 60)
  end
  local h = math_floor(s / 3600 + 0.5)
  if h < 48 then return string_format(L.DUR_H, h) end
  local d = math_floor(h / 24)
  return string_format(L.DUR_D_H, d, h - d * 24)
end

-- ~1h 25m / ~1 h 25; below one minute ETA_LT_1M; never seconds.
function Fmt.ETA(sec)
  local s = Seconds(sec)
  if s < 60 then return L.ETA_LT_1M end
  return string_format(L.ETA_FMT, EtaBody(s))
end

-- Integer key: equal keys => equal ETA strings.
function Fmt.ETAKey(sec)
  local s = Seconds(sec)
  if s < 60 then return 0 end
  if s < 3600 then return math_ceil(s / 60) end
  if s < 36000 then return 1000 + math_floor(s / 300 + 0.5) end
  return 100000 + math_floor(s / 3600 + 0.5)
end

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
local groups = {}   -- reused buffer for Number

-- 12,340 / 12 340 (NBSP). Own grouping, never BreakUpLargeNumbers (critique #20).
function Fmt.Number(n)
  local v = math_floor(Finite(n) + 0.5)
  if v > MAX_INT then v = MAX_INT end
  local neg = v < 0
  if neg then v = -v end
  local s = string_format("%d", v)
  local len = #s
  if len > 3 then
    local head = len % 3
    if head == 0 then head = 3 end
    local k = 1
    groups[1] = s:sub(1, head)
    for i = head + 1, len, 3 do
      k = k + 1
      groups[k] = s:sub(i, i + 2)
    end
    s = table_concat(groups, L.THOUSANDS_SEP, 1, k)
  end
  if neg then s = "-" .. s end
  return s
end

-- 950, 8.2k, 82k, 1.2M (8,2k in French).
function Fmt.Short(n)
  local v = math_floor(Finite(n) + 0.5)
  if v < 1000 then return string_format("%d", v) end
  if v < 9950 then return string_format(L.NUM_K, Tenths(math_floor(v / 100 + 0.5))) end
  if v < 999500 then return string_format(L.NUM_K, string_format("%d", math_floor(v / 1000 + 0.5))) end
  return string_format(L.NUM_M, Tenths(math_floor(v / 100000 + 0.5)))
end

-- Integer key: equal keys <=> equal Short strings.
function Fmt.ShortKey(n)
  local v = math_floor(Finite(n) + 0.5)
  if v < 1000 then return v end
  if v < 9950 then return 10000 + math_floor(v / 100 + 0.5) end
  if v < 999500 then return 20000 + math_floor(v / 1000 + 0.5) end
  return 30000000 + math_floor(v / 100000 + 0.5)
end

-- 8.2k/h. Callers cache it by ShortKey.
function Fmt.Rate(xph)
  return Fmt.Short(xph) .. L.PER_HOUR
end

-- x in 0..1 (negative -> 0); decimals 0 or 1. 27% / 27,0 %.
function Fmt.Percent(x, decimals)
  if type(x) ~= "number" or x ~= x or x < 0 then x = 0 end
  if x > 1000000 then x = 1000000 end
  local text
  if decimals == 1 then
    text = Tenths(math_floor(x * 1000 + 0.5))
  else
    text = string_format("%d", math_floor(x * 100 + 0.5))
  end
  return string_format(L.PERCENT_FMT, text)
end

local pctMemo = {}
-- p = percent 0..100 (rounded, clamped). Memoized: no allocation after warm-up.
function Fmt.PercentInt(p)
  if type(p) ~= "number" or p ~= p then p = 0 end
  local n
  if p <= 0 then
    n = 0
  elseif p >= 100 then
    n = 100
  else
    n = math_floor(p + 0.5)
  end
  local s = pctMemo[n]
  if not s then
    s = string_format(L.PERCENT_FMT, string_format("%d", n))
    pctMemo[n] = s
  end
  return s
end

-- 8.5 / 8,5; decimals 0 or 1.
function Fmt.Decimal(x, decimals)
  x = Finite(x)
  if decimals == 1 then
    local t = math_floor((x < 0 and -x or x) * 10 + 0.5)
    local s = Tenths(t)
    if x < 0 and t > 0 then s = "-" .. s end
    return s
  end
  return string_format("%d", math_floor(x + 0.5))
end

---------------------------------------------------------------------------
-- FPS / latency (memoized, bounded)
---------------------------------------------------------------------------
local fpsMemo = {}                 -- at most 1000 entries (0..999)
local latMemo, latCount = {}, 0    -- capped at C.LATENCY_MEMO_MAX
local flMemo, flCount = {}, 0      -- capped at C.LATENCY_MEMO_MAX

local function ClampInt(v, hi)
  if type(v) ~= "number" or v ~= v or v <= 0 then return 0 end
  if v >= hi then return hi end
  return math_floor(v + 0.5)
end

-- Coloured number + " fps": >= 60 good, 30..59 warn, < 30 bad.
function Fmt.FPS(fps)
  local n = ClampInt(fps, 999)
  local s = fpsMemo[n]
  if not s then
    local cc = (n >= 60 and CC.good) or (n >= 30 and CC.warn) or CC.bad
    s = string_format(L.FPS_FMT, string_format("%s%d%s", cc, n, CC.reset))
    fpsMemo[n] = s
  end
  return s
end

-- Coloured number + " ms": <= 100 good, <= 250 warn, above bad.
function Fmt.Latency(ms)
  local n = ClampInt(ms, 9999)
  local s = latMemo[n]
  if not s then
    if latCount >= C.LATENCY_MEMO_MAX then
      wipe(latMemo)
      latCount = 0
    end
    local cc = (n <= 100 and CC.good) or (n <= 250 and CC.warn) or CC.bad
    s = string_format(L.MS_FMT, string_format("%s%d%s", cc, n, CC.reset))
    latMemo[n] = s
    latCount = latCount + 1
  end
  return s
end

-- "60 fps · 42 ms".
function Fmt.FPSLatency(fps, ms)
  local nf, nl = ClampInt(fps, 999), ClampInt(ms, 9999)
  local key = nf * 10000 + nl
  local s = flMemo[key]
  if not s then
    if flCount >= C.LATENCY_MEMO_MAX then
      wipe(flMemo)
      flCount = 0
    end
    s = string_format("%s%s%s", Fmt.FPS(nf), L.SEP, Fmt.Latency(nl))
    flMemo[key] = s
    flCount = flCount + 1
  end
  return s
end

---------------------------------------------------------------------------
-- Misc (allocating: UI construction and tooltips only)
---------------------------------------------------------------------------
function Fmt.Colorize(text, cc)
  return cc .. text .. "|r"
end

function Fmt.Date(epoch)
  if type(epoch) ~= "number" or epoch ~= epoch then return L.DOTS end
  return date(L.DATE_FMT, math_floor(epoch))
end

function Fmt.DateTime(epoch)
  if type(epoch) ~= "number" or epoch ~= epoch then return L.DOTS end
  return date(L.DATETIME_FMT, math_floor(epoch))
end

-- 3h 05m ago / il y a 3 h 05.
function Fmt.Ago(sec)
  return string_format(L.AGO_FMT, Fmt.Duration(sec))
end

-- 42.1 / 42,1 (p in 0..1; the tenth is truncated, never 10).
function Fmt.LevelProgress(level, p)
  local lvl = math_floor(Finite(level))
  if type(p) ~= "number" or p ~= p or p < 0 then p = 0 end
  local tenth = math_floor(p * 10)
  if tenth > 9 then tenth = 9 end
  return string_format("%d%s%d", lvl, L.DECIMAL_SEP, tenth)
end
