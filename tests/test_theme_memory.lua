-- tests/test_theme_memory.lua - memory budgets of the themes (design/NEXT-LOT.md A, M1-M3).
-- The budget tests run on Lua 5.4 and 5.5 only (each skips itself elsewhere): the figures
-- are the 5.4 / 5.5 object sizes; the game's Lua 5.1 is larger for the same objects. CI
-- runs the 5.5 of leafo/gh-actions-lua, hence the margins. The test of what a compile
-- keeps (nothing: M3) runs on every version.
--
-- NEXT-LOT M1 asks for 25 KB or less per compiled theme. That target is NOT met: measured
-- with the method below (this file run alone), 5.5 gives 23.0 (pixel) to 35.7 (warlock),
-- 10 of the 12 non-classic themes over 25 KB; 5.4 gives 26.4 (pixel) to 39.7 (warlock),
-- all 12 over. The decision (a new target, or more work) is pending with the author. Until
-- then each theme has its own budget, its measured size + about 10 % (rounded up), so that
-- a regression of any one theme fails here; none is above the former shared limit (40 KB
-- on 5.5, 44 KB on 5.4).
--
-- Method (every figure is KB of collectgarbage("count"), after GC() = 4 full collects, the
-- smallest of 3 runs: a doubling of the string table, which stays doubled, falls in one run
-- at most):
--   * compiled theme: login with "actuel" (Stub.InstallUI({ ldb = false }),
--     LoginSequence({ settle = 3 }), Advance(2)), then for each key
--     a = GC(); keep = Themes.Compile(key); b = GC(): b - a, which includes the colour
--     program of the theme (programs[th], weak-keyed, alive with keep);
--   * theme sources: the bytes of the 13 source texts the registry keeps, exact on every
--     version (a GC delta is not: Lua 5.5 does not count strings built in a buffer, as
--     Register's compaction does, and the parse of the files may double the string table,
--     32 KB on 5.4, that stays doubled); the registry holds no builder function for them;
--   * what a compile keeps: the same login, a = GC(), Themes.Compile of the 13 keys once
--     (results dropped), b = GC(): b - a, one run (a second one would not see a cache
--     filled by the first);
--   * Themes.lua resident: Locales + Core loaded, a = GC(), Themes.lua loaded and run,
--     b = GC(): b - a (code, constants and the tables it builds at load: fonts, palette);
--   * after login: Stub.Reset(), Stub.InstallUI({ ldb = false }), Stub.theme = key,
--     k0 = GC(), LoadAddon(), LoginSequence({ settle = 3 }), Advance(2), k2 = GC():
--     k2 - k0 (the stub's region tables included: about 0.6 KB a region).
-- A string the process already holds (a constant of another test file) is not counted
-- again: the figures are highest when this file runs alone (lua tests/run.lua
-- test_theme_memory), and the budgets are set from that run. Measured (5.5 / 5.4, KB;
-- round 4 in brackets): compiled futuriste 34.0 / 38.8, actuel 7.3 / 8.3, heroic 29.4 /
-- 32.9, pixel 23.0 / 26.4, warrior 27.2 / 30.6, paladin 27.3 / 30.9, hunter 34.1 / 37.9,
-- rogue 30.6 / 34.4, priest 29.4 / 32.9, shaman 24.7 / 27.8, mage 29.2 / 32.9, warlock
-- 35.7 / 39.7, druid 28.7 / 32.4 (round 4: 23.2 / 25.0 for actuel to 112.4 / 121.7 for
-- warlock); what the 13 compiles keep about 1 KB; sources 65624 bytes of text (round 4:
-- 13 builder functions, about 104 KB of bytecode resident); Themes.lua 119.1 / 121.3
-- (131.3 / 134.3); after login, a script that loads only the stub: actuel 1063.9 /
-- 1158.6 (1221.3 / 1252.7), futuriste 1191.9 / 1296.1 (1409.3 / 1453.1).
-- The automatic reload (crash review part B: AutoReload.lua, about 30 KB of resident code
-- on 5.5, plus its options and strings) raised both after-login budgets by 40 KB.
-- The watched reputation (Reputation.lua, about 17 KB of resident code on 5.5, plus the
-- strip in Bar / BarSkin, its tooltip line, its option, the themes' bar.rep and its
-- strings) raised both after-login budgets by 25 KB.
-- The reputation's second lot (the rate per hour and the faction list in Reputation.lua,
-- now about 38 KB of code on 5.5; the options' Reputation page, RepOptions.lua, about
-- 19 KB; the main bar mode and the hover region in Bar.lua, the detailed tooltip, two
-- tokens and 42 strings) raised both after-login budgets by 85 KB: measured in the full
-- suite (the run CI makes) 1255.0 (actuel) and 1379.7 (futuriste) on 5.5; the 5.4
-- budgets rose by the same 85 KB (not measured: no 5.4 here). Run alone, this file
-- measures more (the strings other test files share are counted, and the login can grow
-- the string table) and the after-login test fails there, as it already did before.
-- The PvP tracking (Pvp.lua, about 68 KB of compiled code on 5.5 with its debug
-- information; the options' PvP page, PvpOptions.lua, about 14 KB; the PvP strip and the
-- main bar mode in Bar / BarSkin, the PvP tooltip section, seven tokens and 86 strings)
-- raised both after-login budgets by 110 KB: measured in the full suite 1360.8 (actuel)
-- and 1485.4 (futuriste) on 5.5, i.e. 105.8 and 105.7 KB more than the figures above;
-- the 5.4 budgets rose by the same 110 KB (not measured: no 5.4 here).
-- The Levels tab's data (world PvP per level in Pvp.lua, Tracker.AddLevelStat, Util.MaxLevel
-- and the repair of pw / wg / w0 / wp in Core.lua, the Levels tab's Stats functions:
-- LevelSegments, the battlegrounds, WorldPvpState, XPOf, FutureLevels, about 11 KB of
-- compiled code on 5.5 in Stats.lua and a few KB in the three others; the honor and kills
-- events now registered whatever is shown) raised both after-login budgets by 30 KB:
-- measured in the full suite 1389.7 (actuel) and 1514.6 (futuriste) on 5.5, i.e. 28.9 and
-- 29.2 KB more than the PvP figures above; the 5.4 budgets rose by the same 30 KB (not
-- measured: no 5.4 here).
-- The Levels tab rework (LevelChart.lua, the histogram, and LevelDetail.lua, the detail
-- sheet's first part, loaded at login though created only at the first show of the tab;
-- 58 new strings in every locale, 16 removed with the Levels table code of Window.lua):
-- measured in the full suite 1482.9 (actuel) and 1607.8 (futuriste) on 5.5, i.e. 93.2 and
-- 93.2 KB more than the figures above.
-- The detail sheet's sections (LevelDetail.lua: the notes, the figure cards, the time
-- breakdown and its PvP row tooltip, the XP split, the zones and instances, the upcoming
-- level, the live step; about 1250 lines, loaded at login though created only at the first
-- show of the tab; 22 new strings in every locale): measured in the full suite 1539.5
-- (actuel) and 1664.4 (futuriste) on 5.5, i.e. 56.6 and 56.6 KB more.
-- The review fixes of the Levels tab (the chips and the sheet's breakdown live, the scale
-- in days, the chart's minimum within the screen, the estimate's mask etaM; 6 new strings
-- in every locale): measured in the full suite 1548.4 (actuel) and 1673.3 (futuriste) on
-- 5.5, i.e. 8.9 and 8.9 KB more. The three raised both after-login budgets by 160 KB in
-- all, to 1570 / 1700: the measure + 21.6 / 26.7 KB, the margin of the lots above (20.3 /
-- 25.4 for the Levels tab's data). A first raise of 100 + 70 KB (1580 / 1710) left 40.5 /
-- 45.6 KB over the measure, about twice that margin: a resident regression of 30 KB would
-- have passed. The 5.4 budgets rose by the same 160 KB (not measured: no 5.4 here).
local Stub, T = ...

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }
local BASE = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua" }

-- Budgets (KB) per version: [version] = { compiled = { each theme }, Themes.lua resident,
-- after login actuel, after login futuriste }. A compiled budget is the theme's measured
-- size + about 10 %, rounded up (see the header: M1's 25 KB is not met).
local BUDGET = {
  ["Lua 5.5"] = {
    compiled = { futuriste = 38, actuel = 9, heroic = 33, pixel = 26, warrior = 30, paladin = 31, hunter = 38,
                 rogue = 34, priest = 33, shaman = 28, mage = 33, warlock = 40, druid = 32 },
    engine = 125, loginActuel = 1570, loginFuturiste = 1700,
  },
  ["Lua 5.4"] = {
    compiled = { futuriste = 43, actuel = 10, heroic = 37, pixel = 30, warrior = 34, paladin = 35, hunter = 42,
                 rogue = 38, priest = 37, shaman = 31, mage = 37, warlock = 44, druid = 36 },
    engine = 128, loginActuel = 1670, loginFuturiste = 1810,
  },
}
local SOURCES_KB = 80          -- NEXT-LOT M3: the resident theme sources, in total
local KEPT_KB = 10             -- NEXT-LOT M3: what compiling the 13 themes once may keep

local function Budget()
  local b = BUDGET[_VERSION]
  if not b then T.skip("memory budgets are set for Lua 5.4 and 5.5 (this is " .. _VERSION .. ")") end
  return b
end

local function GC()
  for _ = 1, 4 do collectgarbage("collect") end
  return collectgarbage("count")
end

-- The smallest of 3 measures of fn() -> KB.
local function Min3(fn)
  local best = math.huge
  for _ = 1, 3 do
    local kb = fn()
    if kb < best then best = kb end
  end
  return best
end

-- 32768 new strings, garbage on return.
local function ManyStrings()
  local t = {}
  for i = 1, 32768 do t[i] = "room" .. i end
  return #t
end

-- Grows the string table, then lets GC() shrink it back to at most 4 times its use: the
-- strings a measure creates then cannot double it (a doubling stays, and would count as
-- kept). Call before the GC() that starts the measure.
local function RoomForStrings()
  ManyStrings()
  GC()
end

local function Upvalue(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end

T.test("memory: every compiled theme fits its own budget (colour program included)", function()
  local b = Budget()
  Stub.InstallUI({ ldb = false })
  Stub.theme = "actuel"
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(2)
  local over = {}
  for _, key in ipairs(KEYS) do
    local kb = Min3(function()
      local a = GC()
      local keep = ns.Themes.Compile(key)
      local after = GC()
      T.ok(keep and keep.key == key, key .. " compiled")
      return after - a
    end)
    local limit = b.compiled[key]
    if kb > limit then over[#over + 1] = string.format("%s: %.1f KB > %d KB", key, kb, limit) end
  end
  T.eq(over, {}, "compiled themes over budget")
end)

-- M3: a source text is loaded into a function at each compile, and the function is
-- dropped at once. A loader that kept it (a cache of the loaded chunks) would leave the
-- bytecode of every compiled theme resident: over 100 KB for the 13.
T.test("memory: compiling the 13 themes once keeps nothing (no loaded source function kept)", function()
  Stub.InstallUI({ ldb = false })
  Stub.theme = "actuel"
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(2)
  local Compile = ns.Themes.Compile
  RoomForStrings()
  local a = GC()
  for i = 1, #KEYS do
    T.ok(Compile(KEYS[i]) ~= nil, KEYS[i] .. " compiled")     -- (the result is dropped)
  end
  local kb = GC() - a
  T.ok(kb < KEPT_KB, string.format("%.1f KB kept after compiling the 13 themes once (limit %d KB)", kb, KEPT_KB))
end)

T.test("memory: the theme sources are compact texts, 80 KB in total, no builder resident", function()
  Budget()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = BASE })
  for _, key in ipairs(KEYS) do
    assert(loadfile(Stub.ROOT .. "Themes/" .. key .. ".lua"))("TruePlayed", ns)
  end
  local registry = Upvalue(ns.Themes.IsRegistered, "registry")
  local bytes, n = 0, 0
  for key, entry in pairs(registry) do
    n = n + 1
    T.eq(type(entry), "string", key .. ": a source text, not a builder function")
    bytes = bytes + (type(entry) == "string" and #entry or 0)
  end
  T.eq(n, #KEYS, "the 13 themes, nothing else")
  T.ok(bytes <= SOURCES_KB * 1024, string.format("source texts: %d bytes", bytes))
end)

T.test("memory: Themes.lua resident (code and load-time tables) fits its budget", function()
  local b = Budget()
  local kb = Min3(function()
    Stub.Reset()
    local ns = Stub.LoadAddon({ files = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua" } })
    local a = GC()
    assert(loadfile(Stub.ROOT .. "Themes.lua"))("TruePlayed", ns)   -- (the main chunk is dropped)
    return GC() - a
  end)
  T.ok(kb <= b.engine, string.format("Themes.lua resident %.1f KB (budget %d KB)", kb, b.engine))
end)

T.test("memory: the addon after login, classic and default themes, fits its budget", function()
  local b = Budget()
  for _, key in ipairs({ "actuel", "futuriste" }) do
    local kb = Min3(function()
      Stub.Reset()
      Stub.InstallUI({ ldb = false })
      Stub.theme = key
      local k0 = GC()
      Stub.LoadAddon()
      Stub.LoginSequence({ settle = 3 })
      Stub.Advance(2)
      return GC() - k0
    end)
    local limit = key == "actuel" and b.loginActuel or b.loginFuturiste
    T.ok(kb <= limit, string.format("%s after login: %.1f KB (budget %d KB)", key, kb, limit))
  end
end)
