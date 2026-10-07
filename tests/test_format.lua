-- tests/test_format.lua - Format.lua (SPEC-FINAL 3.7, 9.4 "test_format").
-- Loads only the foundation files, so it does not depend on other modules.
local Stub, T = ...

local FILES = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Format.lua" }
local NBSP = "\194\160"

local function Load(locale)
  Stub.locale = locale or "enUS"
  return Stub.LoadAddon({ files = FILES })
end

-- true when s is valid UTF-8 and every code point is <= U+00FF (SPEC 2.6)
local function IsLatin1(s)
  if type(s) ~= "string" then return false end
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    if b < 0x80 then
      i = i + 1
    elseif b == 0xC2 or b == 0xC3 then
      local b2 = s:byte(i + 1)
      if not b2 or b2 < 0x80 or b2 > 0xBF then return false end
      i = i + 2
    else
      return false
    end
  end
  return true
end

---------------------------------------------------------------------------
-- Durations
---------------------------------------------------------------------------
local DURATIONS = {
  { 0, "<1m", "< 1 min" },
  { 59, "<1m", "< 1 min" },
  { 60, "1m", "1 min" },
  { 3599, "59m", "59 min" },
  { 3600, "1h 00m", "1 h 00" },
  { 5100, "1h 25m", "1 h 25" },
  { 35999, "9h 59m", "9 h 59" },
  { 36000, "10h", "10 h" },
  { 86399, "23h", "23 h" },
  { 90000, "1d 01h", "1 j 01 h" },
  { -5, "<1m", "< 1 min" },
}

T.test("Duration enUS", function()
  local Fmt = Load("enUS").Fmt
  for _, c in ipairs(DURATIONS) do T.eq(Fmt.Duration(c[1]), c[2], "Duration(" .. c[1] .. ")") end
  T.eq(Fmt.Duration(nil), "<1m", "nil")
  T.eq(Fmt.Duration(0 / 0), "<1m", "NaN")
end)

T.test("Duration frFR", function()
  local Fmt = Load("frFR").Fmt
  for _, c in ipairs(DURATIONS) do T.eq(Fmt.Duration(c[1]), c[3], "Duration(" .. c[1] .. ")") end
end)

T.test("DurationKey equal iff Duration strings equal (0..200000 step 7)", function()
  local Fmt = Load("enUS").Fmt
  local byKey, byText = {}, {}
  for s = 0, 200000, 7 do
    local key, text = Fmt.DurationKey(s), Fmt.Duration(s)
    if byKey[key] ~= nil and byKey[key] ~= text then
      error("key " .. key .. " maps to '" .. byKey[key] .. "' and '" .. text .. "'")
    end
    if byText[text] ~= nil and byText[text] ~= key then
      error("text '" .. text .. "' has keys " .. byText[text] .. " and " .. key)
    end
    byKey[key], byText[text] = text, key
  end
end)

T.test("DurationLong", function()
  local Fmt = Load("enUS").Fmt
  T.eq(Fmt.DurationLong(3 * 86400 + 4 * 3600 + 12 * 60), "3d 4h 12m")
  T.eq(Fmt.DurationLong(3700), "1h 01m")
  T.eq(Fmt.DurationLong(125), "2m")
  T.eq(Fmt.DurationLong(30), "<1m")
  Fmt = Load("frFR").Fmt
  T.eq(Fmt.DurationLong(3 * 86400 + 4 * 3600 + 12 * 60), "3 j 4 h 12 min")
  T.eq(Fmt.DurationLong(3700), "1 h 01 min")
end)

---------------------------------------------------------------------------
-- ETA
---------------------------------------------------------------------------
T.test("ETA rounding: ceil below 1 h, 5-minute steps, hours, days", function()
  local Fmt = Load("enUS").Fmt
  T.eq(Fmt.ETA(0), "<1m")
  T.eq(Fmt.ETA(59.9), "<1m")
  T.eq(Fmt.ETA(60), "~1m")
  T.eq(Fmt.ETA(61), "~2m", "minutes are rounded up below one hour")
  T.eq(Fmt.ETA(1500), "~25m")
  T.eq(Fmt.ETA(3599), "~1h 00m", "59.98 min rounds up to one hour")
  T.eq(Fmt.ETA(3600), "~1h 00m", "3599 and 3600 are consistent")
  T.eq(Fmt.ETA(5100), "~1h 25m")
  T.eq(Fmt.ETA(5249), "~1h 25m")
  T.eq(Fmt.ETA(5250), "~1h 30m", "5-minute steps")
  T.eq(Fmt.ETA(35849), "~9h 55m")
  T.eq(Fmt.ETA(35850), "~10h", "rounding up to 10 h switches to the hours form")
  T.eq(Fmt.ETA(36000), "~10h")
  T.eq(Fmt.ETA(170999), "~47h")
  T.eq(Fmt.ETA(171000), "~2d 00h")
  T.eq(Fmt.ETA(200000), "~2d 08h")
  Fmt = Load("frFR").Fmt
  T.eq(Fmt.ETA(30), "< 1 min")
  T.eq(Fmt.ETA(5100), "~1 h 25")
  T.eq(Fmt.ETA(1500), "~25 min")
  T.eq(Fmt.ETA(3599), "~1 h 00")
end)

T.test("ETA never shows seconds; ETAKey equal => ETA equal", function()
  local Fmt = Load("enUS").Fmt
  local byKey = {}
  for s = 0, 250000, 13 do
    local text = Fmt.ETA(s)
    T.no(text:find("%d+s"), "no seconds in " .. text)
    local key = Fmt.ETAKey(s)
    if byKey[key] ~= nil and byKey[key] ~= text then
      error("ETAKey " .. key .. " maps to '" .. byKey[key] .. "' and '" .. text .. "'")
    end
    byKey[key] = text
  end
  -- fractional seconds use the same thresholds
  T.eq(Fmt.ETAKey(3599.5), Fmt.ETAKey(3599.9))
end)

---------------------------------------------------------------------------
-- Numbers
---------------------------------------------------------------------------
T.test("Number enUS / frFR, negatives, rounding", function()
  local Fmt = Load("enUS").Fmt
  T.eq(Fmt.Number(12340), "12,340")
  T.eq(Fmt.Number(0), "0")
  T.eq(Fmt.Number(999), "999")
  T.eq(Fmt.Number(1000), "1,000")
  T.eq(Fmt.Number(1234567), "1,234,567")
  T.eq(Fmt.Number(-12340), "-12,340")
  T.eq(Fmt.Number(12339.6), "12,340")
  T.eq(Fmt.Number(nil), "0")
  Fmt = Load("frFR").Fmt
  T.eq(Fmt.Number(12340), "12" .. NBSP .. "340")
  T.eq(Fmt.Number(1234567), "1" .. NBSP .. "234" .. NBSP .. "567")
  T.eq(Fmt.Number(-45800), "-45" .. NBSP .. "800")
end)

T.test("Short at the band boundaries (EN and FR)", function()
  local Fmt = Load("enUS").Fmt
  T.eq(Fmt.Short(999), "999")
  T.eq(Fmt.Short(999.5), "1.0k")
  T.eq(Fmt.Short(8200), "8.2k")
  T.eq(Fmt.Short(9949), "9.9k")
  T.eq(Fmt.Short(9950), "10k")
  T.eq(Fmt.Short(82000), "82k")
  T.eq(Fmt.Short(999499), "999k")
  T.eq(Fmt.Short(999500), "1.0M")
  T.eq(Fmt.Short(1.2e6), "1.2M")
  T.eq(Fmt.Rate(8200), "8.2k/h")
  Fmt = Load("frFR").Fmt
  T.eq(Fmt.Short(8200), "8,2k")
  T.eq(Fmt.Short(999500), "1,0M")
  T.eq(Fmt.Short(1.2e6), "1,2M")
  T.eq(Fmt.Rate(8200), "8,2k/h")
end)

T.test("ShortKey equal <=> Short equal", function()
  local Fmt = Load("enUS").Fmt
  local byKey, byText = {}, {}
  local values = {}
  for v = 0, 20000, 3 do values[#values + 1] = v end
  for v = 20000, 2000000, 997 do values[#values + 1] = v end
  for _, v in ipairs(values) do
    local key, text = Fmt.ShortKey(v), Fmt.Short(v)
    if byKey[key] ~= nil and byKey[key] ~= text then error("ShortKey " .. key .. " ambiguous") end
    if byText[text] ~= nil and byText[text] ~= key then error("Short '" .. text .. "' has two keys") end
    byKey[key], byText[text] = text, key
  end
end)

T.test("Percent, PercentInt (memoized), Decimal, LevelProgress", function()
  local Fmt = Load("enUS").Fmt
  T.eq(Fmt.Percent(0.27, 0), "27%")
  T.eq(Fmt.Percent(0.27, 1), "27.0%")
  T.eq(Fmt.Percent(0.1234, 1), "12.3%")
  T.eq(Fmt.Percent(-1, 0), "0%")
  T.eq(Fmt.PercentInt(27), "27%")
  T.eq(Fmt.PercentInt(27.4), "27%")
  T.eq(Fmt.PercentInt(150), "100%")
  T.eq(Fmt.PercentInt(-3), "0%")
  T.ok(rawequal(Fmt.PercentInt(42), Fmt.PercentInt(42)), "identical memoized string")
  T.eq(Fmt.Decimal(8.46, 1), "8.5")
  T.eq(Fmt.Decimal(8.46, 0), "8")
  T.eq(Fmt.Decimal(-0.25, 1), "-0.3")
  T.eq(Fmt.LevelProgress(42, 0.123), "42.1")
  T.eq(Fmt.LevelProgress(42, 1), "42.9", "never 42.10")
  T.eq(Fmt.LevelProgress(42, 0), "42.0")
  Fmt = Load("frFR").Fmt
  T.eq(Fmt.Percent(0.27, 0), "27 %")
  T.eq(Fmt.Percent(0.27, 1), "27,0 %")
  T.eq(Fmt.PercentInt(27), "27 %")
  T.eq(Fmt.Decimal(8.46, 1), "8,5")
  T.eq(Fmt.LevelProgress(42, 0.123), "42,1")
end)

---------------------------------------------------------------------------
-- FPS / latency colours and memoization
---------------------------------------------------------------------------
T.test("FPS and latency colours at the thresholds", function()
  local ns = Load("enUS")
  local Fmt, CC = ns.Fmt, ns.C.CC
  local function fps(cc, n) return cc .. n .. "|r fps" end
  local function ms(cc, n) return cc .. n .. "|r ms" end
  T.eq(Fmt.FPS(29), fps(CC.bad, "29"))
  T.eq(Fmt.FPS(30), fps(CC.warn, "30"))
  T.eq(Fmt.FPS(59), fps(CC.warn, "59"))
  T.eq(Fmt.FPS(60), fps(CC.good, "60"))
  T.eq(Fmt.FPS(59.6), fps(CC.good, "60"), "rounded before colouring")
  T.eq(Fmt.FPS(5000), fps(CC.good, "999"), "clamped")
  T.eq(Fmt.Latency(100), ms(CC.good, "100"))
  T.eq(Fmt.Latency(101), ms(CC.warn, "101"))
  T.eq(Fmt.Latency(250), ms(CC.warn, "250"))
  T.eq(Fmt.Latency(251), ms(CC.bad, "251"))
  T.eq(Fmt.Latency(123456), ms(CC.bad, "9999"), "clamped")
  T.eq(Fmt.FPSLatency(60, 42), fps(CC.good, "60") .. " · " .. ms(CC.good, "42"))
  T.eq(Fmt.Colorize("x", CC.good), CC.good .. "x|r")
end)

T.test("memoized formatters allocate nothing after warm-up; latency memo is bounded", function()
  local ns = Load("enUS")
  local Fmt = ns.Fmt
  Fmt.FPS(60); Fmt.Latency(42); Fmt.FPSLatency(60, 42); Fmt.PercentInt(27)
  local kb = T.alloc(function()
    Fmt.FPS(60)
    Fmt.Latency(42)
    Fmt.FPSLatency(60, 42)
    Fmt.PercentInt(27)
  end, 2000)
  T.ok(kb <= 0.5, "allocated " .. kb .. " KB")
  -- more distinct values than the cap: still correct (the memo is wiped, not grown)
  for v = 0, 3 * ns.C.LATENCY_MEMO_MAX do
    T.match(Fmt.Latency(v), "|r ms$")
    T.match(Fmt.FPSLatency(v % 200, v), " ms$")
  end
  T.eq(Fmt.Latency(42), ns.C.CC.good .. "42|r ms")
end)

---------------------------------------------------------------------------
-- Dates
---------------------------------------------------------------------------
-- Lot 8: DateTime always has the year, the hours and the minutes; by default (settings
-- window.dateFmt = window.clock = "auto") the date and clock of the language: English
-- month / day / year on a 12-hour clock, French day / month / year at "14h05".
T.test("Date, DateTime and Ago patterns", function()
  local Fmt = Load("enUS").Fmt
  T.match(Fmt.Date(1790000000), "^%d%d/%d%d/%d%d%d%d$")
  T.match(Fmt.DateTime(1790000000), "^%d%d/%d%d/%d%d%d%d %d?%d:%d%d [AP]M$")
  T.eq(Fmt.Ago(11100), "3h 05m ago")
  T.eq(Fmt.Date(nil), "...")
  T.eq(Fmt.DateTime(nil), "...")
  Fmt = Load("frFR").Fmt
  T.match(Fmt.DateTime(1790000000), "^%d%d/%d%d/%d%d%d%d %d%dh%d%d$")
  T.eq(Fmt.Ago(11100), "il y a 3 h 05")
end)

-- Local times (any time zone of the machine running the tests).
local function At(hour, min) return os.time({ year = 2026, month = 10, day = 7, hour = hour, min = min, sec = 30 }) end

T.test("DateTime: every date format and clock of the settings window.dateFmt / window.clock", function()
  local ns = Load("enUS")
  local Fmt = ns.Fmt
  ns.settings = ns.settings or {}
  local function Set(dateFmt, clock)
    ns.settings.window = { width = 700, height = 440, dateFmt = dateFmt, clock = clock }
  end
  Set("auto", "auto")
  T.eq(Fmt.DateTime(At(14, 5)), "10/07/2026 2:05 PM", "English: the language's date, 12-hour clock")
  T.eq(Fmt.DateTime(At(0, 7)), "10/07/2026 12:07 AM", "midnight hour")
  T.eq(Fmt.DateTime(At(12, 0)), "10/07/2026 12:00 PM", "noon")
  T.eq(Fmt.DateTime(At(9, 59)), "10/07/2026 9:59 AM")
  Set("auto", "24")
  T.eq(Fmt.DateTime(At(14, 5)), "10/07/2026 14:05")
  T.eq(Fmt.DateTime(At(9, 5)), "10/07/2026 09:05")
  Set("dmy", "24")
  T.eq(Fmt.DateTime(At(14, 5)), "07/10/2026 14:05")
  Set("mdy", "12")
  T.eq(Fmt.DateTime(At(14, 5)), "10/07/2026 2:05 PM")
  Set("ymd", "24")
  T.eq(Fmt.DateTime(At(14, 5)), "2026-10-07 14:05")
  Set("ymd", "12")
  T.eq(Fmt.DateTime(At(23, 59)), "2026-10-07 11:59 PM")
  Set("dmy", "auto")
  T.eq(Fmt.DateTime(At(14, 5)), "07/10/2026 2:05 PM", "auto clock with a chosen date")
  ns.settings.window = nil
  T.eq(Fmt.DateTime(At(14, 5)), "10/07/2026 2:05 PM", "no settings: the language's")
  -- French: day / month / year, "14h05"; an explicit clock overrides it
  ns = Load("frFR")
  Fmt = ns.Fmt
  ns.settings = ns.settings or {}
  Set("auto", "auto")
  T.eq(Fmt.DateTime(At(14, 5)), "07/10/2026 14h05")
  Set("auto", "12")
  T.eq(Fmt.DateTime(At(14, 5)), "07/10/2026 2:05 PM", "every player may choose the 12-hour clock")
  Set("mdy", "24")
  T.eq(Fmt.DateTime(At(14, 5)), "10/07/2026 14:05")
end)

---------------------------------------------------------------------------
-- Robustness: %d never receives a non-integral float; outputs are Latin-1
---------------------------------------------------------------------------
local ODD = { 0.4, 59.9, 60.5, 3599.5, 5100.7, 35999.99, 86399.5, 90000.25, 1e9 + 0.5,
              -0.5, -3600.5, 1 / 0, -1 / 0, 0 / 0, 999.5, 9949.5, 999499.6, 1234.567 }

local function everyOutput(Fmt)
  local out = {}
  for _, x in ipairs(ODD) do
    out[#out + 1] = Fmt.Duration(x)
    out[#out + 1] = Fmt.DurationLong(x)
    out[#out + 1] = Fmt.ETA(x)
    out[#out + 1] = Fmt.Number(x)
    out[#out + 1] = Fmt.Short(x)
    out[#out + 1] = Fmt.Rate(x)
    out[#out + 1] = Fmt.Percent(x / 100, 0)
    out[#out + 1] = Fmt.Percent(x / 100, 1)
    out[#out + 1] = Fmt.PercentInt(x)
    out[#out + 1] = Fmt.Decimal(x, 0)
    out[#out + 1] = Fmt.Decimal(x, 1)
    out[#out + 1] = Fmt.FPS(x)
    out[#out + 1] = Fmt.Latency(x)
    out[#out + 1] = Fmt.FPSLatency(x, x)
    out[#out + 1] = Fmt.Ago(x)
    out[#out + 1] = Fmt.LevelProgress(x, x / 1000)
    T.eq(type(Fmt.DurationKey(x)), "number")
    T.eq(type(Fmt.ETAKey(x)), "number")
    T.eq(type(Fmt.ShortKey(x)), "number")
  end
  out[#out + 1] = Fmt.Date(1790000000.7)
  out[#out + 1] = Fmt.DateTime(1790000000.7)
  return out
end

T.test("fractional / infinite / NaN inputs never break %d; outputs are Latin-1 (EN)", function()
  local Fmt = Load("enUS").Fmt
  for _, s in ipairs(everyOutput(Fmt)) do
    T.eq(type(s), "string")
    T.ok(IsLatin1(s), "Latin-1: " .. s)
  end
end)

T.test("fractional / infinite / NaN inputs never break %d; outputs are Latin-1 (FR)", function()
  local Fmt = Load("frFR").Fmt
  for _, s in ipairs(everyOutput(Fmt)) do
    T.eq(type(s), "string")
    T.ok(IsLatin1(s), "Latin-1: " .. s)
  end
end)
