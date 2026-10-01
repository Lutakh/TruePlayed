-- tests/test_theme_memory.lua - memory budgets of the themes (design/NEXT-LOT.md A, M1-M3).
-- Lua 5.4 and 5.5 only (each test skips itself elsewhere): the figures are the 5.4 / 5.5
-- object sizes; the game's Lua 5.1 is larger for the same objects. CI runs the 5.5 of
-- leafo/gh-actions-lua, hence the margins.
--
-- Method (every figure is KB of collectgarbage("count"), after GC() = 4 full collects, the
-- smallest of 3 runs, with the string table grown beforehand (Room) so that its doubling
-- - up to 16 KB on 5.5, depending on what the process holds - never falls in a measure):
--   * compiled theme: login with "actuel" (Stub.InstallUI({ ldb = false }),
--     LoginSequence({ settle = 3 }), Advance(2)), then for each key
--     a = GC(); keep = Themes.Compile(key); b = GC(): b - a, which includes the colour
--     program of the theme (programs[th], weak-keyed, alive with keep);
--   * theme sources: the bytes of the 13 source texts the registry keeps (exact on every
--     version: Lua 5.5 does not count strings built in a buffer, as Register's compaction
--     does, in collectgarbage("count")), and the GC delta of loading the 13 theme files
--     after Themes.lua; the registry holds no builder function for them;
--   * Themes.lua resident: Locales + Core loaded, a = GC(), Themes.lua loaded and run,
--     b = GC(): b - a (code, constants and the tables it builds at load: fonts, palette);
--   * after login: Stub.Reset(), Stub.InstallUI({ ldb = false }), Stub.theme = key,
--     k0 = GC(), LoadAddon(), LoginSequence({ settle = 3 }), Advance(2), k2 = GC():
--     k2 - k0 (the stub's region tables included: about 0.6 KB a region).
-- A string the process already holds (a constant of another test file) is not counted
-- again: the figures are highest when this file runs alone (lua tests/run.lua
-- test_theme_memory), and the budgets are set from that run. Measured when written
-- (5.5 / 5.4, KB; round 4 in brackets): compiled 7.3 / 8.3 (actuel) to 35.7 / 39.7
-- (warlock) (23.2 / 25.0 to 112.4 / 121.7); sources 65624 bytes of text (round 4: 13
-- builder functions, about 104 KB of bytecode resident); Themes.lua 119.1 / 121.3
-- (131.3 / 134.3); after login, a script that loads only the stub: actuel 1063.9 /
-- 1158.6 (1221.3 / 1252.7), futuriste 1191.9 / 1296.1 (1409.3 / 1453.1).
local Stub, T = ...

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }
local BASE = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua" }

-- Budgets (KB) per version: [version] = { compiled (every theme), compiled actuel,
-- Themes.lua resident, after login actuel, after login futuriste }.
local BUDGET = {
  ["Lua 5.5"] = { compiled = 40, actuel = 9, engine = 125, loginActuel = 1120, loginFuturiste = 1250 },
  ["Lua 5.4"] = { compiled = 44, actuel = 10, engine = 128, loginActuel = 1220, loginFuturiste = 1360 },
}
local SOURCES_KB = 80          -- NEXT-LOT M3: the resident theme sources, in total

local function Budget()
  local b = BUDGET[_VERSION]
  if not b then T.skip("memory budgets are set for Lua 5.4 and 5.5 (this is " .. _VERSION .. ")") end
  return b
end

local function GC()
  for _ = 1, 4 do collectgarbage("collect") end
  return collectgarbage("count")
end

-- Room in the string table: 30000 strings held while measuring (the table only grows
-- when it is full and only shrinks below a quarter full; these are created, and the
-- table resized, before the first GC() of a measure).
local function Room()
  local hold = {}
  for i = 1, 30000 do hold[i] = "theme memory room " .. i end
  return hold
end

-- The smallest of 3 measures of fn() -> KB.
local function Min3(fn)
  local hold = Room()
  local best = math.huge
  for _ = 1, 3 do
    local kb = fn()
    if kb < best then best = kb end
  end
  hold[1] = nil
  return best
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

T.test("memory: every compiled theme fits its budget (colour program included)", function()
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
    local limit = key == "actuel" and b.actuel or b.compiled
    if kb > limit then over[#over + 1] = string.format("%s: %.1f KB > %d KB", key, kb, limit) end
  end
  T.eq(over, {}, "compiled themes over budget")
end)

T.test("memory: the theme sources are compact texts, 80 KB in total, no builder resident", function()
  Budget()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = BASE })
  local hold = Room()
  local a = GC()
  for _, key in ipairs(KEYS) do
    assert(loadfile(Stub.ROOT .. "Themes/" .. key .. ".lua"))("TruePlayed", ns)   -- (the chunk is dropped)
  end
  local loaded = GC() - a
  hold[1] = nil
  local registry = Upvalue(ns.Themes.IsRegistered, "registry")
  local bytes = 0
  for _, key in ipairs(KEYS) do
    local entry = registry[key]
    T.eq(type(entry), "string", key .. ": a source text, not a builder function")
    bytes = bytes + (type(entry) == "string" and #entry or 0)
  end
  T.ok(bytes <= SOURCES_KB * 1024, string.format("source texts: %d bytes", bytes))
  T.ok(loaded <= SOURCES_KB, string.format("13 theme files resident: %.1f KB", loaded))
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
