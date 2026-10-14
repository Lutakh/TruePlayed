-- tests/test_levels_data.lua - the Levels tab's data (Stats.lua, Util.MaxLevel): the parts
-- of a bar (Stats.LevelSegments, summing to Stats.Sum under every mask, world PvP capped
-- at the open world, the AFK on a taxi in the flight unless AFK is excluded), the
-- battlegrounds of a level or of the life (merged by name, the remainder as "other"),
-- whether a level's world PvP was measured (Stats.WorldPvpState),
-- the XP size of a level (Stats.XPOf, the table scaled by the known sizes that contradict
-- it), the projection of the levels still to play (Stats.FutureLevels: statuses, the K
-- formula on a hand-computed example, the rate fallback, the current level), the history
-- row's new fields, purity and allocation. Records are built by hand; only the files
-- Stats depends on are loaded (as tests/test_stats.lua).
local Stub, T = ...

local format, floor = string.format, math.floor

local FILES = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Format.lua", "Stats.lua" }

local function Load()
  local ns = Stub.LoadAddon({ files = FILES })
  return ns, ns.Stats
end

local function Ema(a, r, q, d)
  local t = {}
  for i = 1, 8 do t[i] = { a = a, r = r, q = q, d = d } end
  return t
end

-- Every state key, and world PvP: Sum(mask 0) = 6656.
local function RichBucket()
  return { s = { w = 1000, W = 100, d = 900, D = 90, r = 800, R = 80, p = 700, P = 70, i = 600, I = 60,
                 c = 500, C = 50, t = 400, T = 40, x = 300, f = 200, u = 100 }, pw = 250, xp = 0 }
end

local PARTS = { "world", "wpvp", "dungeon", "raid", "bg", "taxi", "prof", "dead", "city", "inn", "afk", "untracked" }

local function PartsSum(out)
  local t = 0
  for _, k in ipairs(PARTS) do t = t + out[k] end
  return t
end

---------------------------------------------------------------------------
-- LevelSegments
---------------------------------------------------------------------------

T.test("LevelSegments: the parts sum to Stats.Sum under every mask; world PvP split from the world", function()
  local _, Stats = Load()
  local b = RichBucket()
  local out = {}
  for m = 0, 7 do
    local total = Stats.LevelSegments(b, m, out)
    T.eq(total, Stats.Sum(b, m), format("mask %d: total", m))
    T.eq(out.total, total)
    T.eq(PartsSum(out), Stats.Sum(b, m), format("mask %d: parts", m))
  end
  Stats.LevelSegments(b, 0, out)
  T.eq({ out.world, out.wpvp, out.dungeon, out.raid, out.bg, out.taxi, out.prof, out.dead, out.city, out.inn,
         out.afk, out.untracked }, { 750, 250, 900, 800, 700, 440, 200, 300, 500, 600, 450, 100 },
    "mask 0: the AFK on a taxi (T) in the flight, the other AFK keys in afk")
  Stats.LevelSegments(b, 1, out)
  T.eq({ out.city, out.inn, out.afk, out.taxi }, { 500, 600, 0, 400 }, "mask 1: no AFK key, T out of the flight")
  Stats.LevelSegments(b, 7, out)
  T.eq({ out.world, out.wpvp, out.city, out.inn, out.afk, out.taxi, out.dead, out.prof, out.untracked, out.total },
    { 750, 250, 0, 0, 0, 400, 300, 200, 100, 4400 }, "mask 7: AFK, inn and city out; dead, prof and u never")
  Stats.LevelSegments(b, 2, out)
  T.eq({ out.inn, out.city, out.afk, out.taxi }, { 0, 500, 390, 440 }, "mask 2: i and I out, the other AFK keys in")
end)

T.test("LevelSegments: a flight turned AFK is flight (the tooltip's flight line); AFK in a battleground stays AFK", function()
  local _, Stats = Load()
  local out, bd = {}, {}
  local b = { s = { w = 300, t = 600, T = 900, p = 400, P = 120, W = 30 } }   -- a long flight, AFK after 5 min
  Stats.LevelSegments(b, 0, out)
  T.eq({ out.taxi, out.afk, out.bg, out.total }, { 1500, 150, 400, 2350 }, "mask 0")
  T.eq(out.taxi, Stats.Breakdown(b, bd).taxi, "the main tooltip's flight line (t + T)")
  for m = 0, 7 do
    Stats.LevelSegments(b, m, out)
    T.eq(PartsSum(out), Stats.Sum(b, m), format("mask %d: the parts still sum", m))
    T.eq(out.taxi, (m % 2 == 1) and 600 or 1500, format("mask %d: T with the AFK only", m))
  end
  Stats.LevelSegments(b, 1, out)
  T.eq({ out.taxi, out.afk, out.bg, out.total }, { 600, 0, 400, 1300 }, "mask 1: AFK excluded, T too")
end)

T.test("LevelSegments: world PvP capped at the open world, absent or bad reads 0; nil bucket; char.life", function()
  local _, Stats = Load()
  local out = {}
  Stats.LevelSegments({ s = { w = 100, d = 50 }, pw = 130 }, 0, out)
  T.eq({ out.world, out.wpvp, out.total }, { 0, 100, 150 }, "pw above w: capped")
  for _, pw in ipairs({ -5, 0 / 0, "x" }) do
    Stats.LevelSegments({ s = { w = 100 }, pw = pw }, 0, out)
    T.eq({ out.world, out.wpvp }, { 100, 0 }, tostring(pw))
  end
  Stats.LevelSegments({ s = { w = 100 } }, 0, out)
  T.eq({ out.world, out.wpvp }, { 100, 0 }, "not measured: all world")
  Stats.LevelSegments({ s = { W = 100 }, pw = 50 }, 0, out)
  T.eq({ out.world, out.wpvp, out.afk }, { 0, 0, 100 }, "AFK world time is never world PvP")
  T.eq(Stats.LevelSegments(nil, 3, out), 0)
  T.eq(PartsSum(out), 0, "a nil bucket: zeros")
  local life = { s = { w = 5000, t = 700, p = 300 }, pw = 1200, xp = 0, d = 3 }
  T.eq(Stats.LevelSegments(life, 0, out), 6000)
  T.eq({ out.world, out.wpvp, out.taxi, out.bg }, { 3800, 1200, 700, 300 }, "char.life")
end)

---------------------------------------------------------------------------
-- Battlegrounds
---------------------------------------------------------------------------

-- Level 20 played in two battlegrounds (Warsong Gulch under its map 9001 and its instance
-- key "i489", Arathi Basin 9002), a tick of PvP in Durotar, the merged "o", a dungeon.
local function BgChar()
  return {
    level = 21,
    zones = { [9001] = { s = { p = 1600, P = 100 }, name = "Warsong Gulch" },
              [9002] = { s = { p = 500 }, name = "Arathi Basin" },
              ["i489"] = { s = { p = 300 } },
              [9003] = { s = { d = 400 }, name = "Ragefire Chasm" },
              [1411] = { s = { w = 9000, p = 3 }, name = "Durotar" },
              [9004] = { s = { p = 200, x = 300 }, name = "Alterac Valley" } },
    life = { s = { p = 2650, P = 100, w = 9000, d = 400, x = 300 }, xp = 0 },
    levels = {
      [20] = { s = { p = 1160, P = 100, w = 5000, d = 400, x = 120 }, xp = 0, z = {
        [9001] = { s = { p = 600, P = 100, x = 120 } },
        ["i489"] = { s = { p = 300 } },
        [9002] = { s = { p = 200 } },
        [1411] = { s = { w = 5000, p = 3 } },
        o = { s = { p = 50 } },
        [9003] = { s = { d = 400 } },
      } },
    },
  }
end

T.test("LevelBattlegrounds: per battleground (merged by name), P under the mask, other = the remainder", function()
  local _, Stats = Load()
  Stub.player.instanceNames[489] = "Warsong Gulch"
  local char = BgChar()
  local out = {}
  local n, other = Stats.LevelBattlegrounds(char, 20, 0, out)
  T.eq(n, 2)
  T.eq(out, { { key = 9001, name = "Warsong Gulch", secs = 1000 }, { key = 9002, name = "Arathi Basin", secs = 200 } },
    "map and instance key merged; Durotar's tick, the merged zone and the dungeon left out")
  T.eq(other, 1260 - 1200, "the level's p + P less the rows")
  local first = out[1]
  n, other = Stats.LevelBattlegrounds(char, 20, 1, out)
  T.eq(n, 2)
  T.eq({ out[1].secs, out[2].secs, other }, { 900, 200, 60 }, "AFK excluded: P left out, rows and segment alike")
  T.ok(rawequal(out[1], first) or rawequal(out[2], first), "rows reused")
  -- the larger part names the merged row's key
  char.levels[20].z["i489"].s.p = 900
  char.levels[20].s.p = 1760
  Stats.LevelBattlegrounds(char, 20, 0, out)
  T.eq({ out[1].key, out[1].secs, out[1].ks }, { "i489", 1600, nil })
  -- the same time: sorted by name
  char.levels[20].z[9002].s.p = 1600
  Stats.LevelBattlegrounds(char, 20, 0, out)
  T.eq({ out[1].name, out[2].name }, { "Arathi Basin", "Warsong Gulch" })
  -- a level without a record, or without battlegrounds
  n, other = Stats.LevelBattlegrounds(char, 5, 0, out)
  T.eq({ n, other, #out }, { 0, 0, 0 })
  char.levels[20].z = {}
  n, other = Stats.LevelBattlegrounds(char, 20, 0, out)
  T.eq({ n, other }, { 0, 1860 }, "everything merged away: all in other")
end)

T.test("LifeBattlegrounds: char.zones with their names; a battleground map with dead time is kept", function()
  local _, Stats = Load()
  Stub.player.instanceNames[489] = "Warsong Gulch"
  local char = BgChar()
  local out = {}
  local n, other = Stats.LifeBattlegrounds(char, 0, out)
  T.eq(n, 3)
  T.eq({ out[1].name, out[1].secs, out[2].name, out[2].secs, out[3].name, out[3].secs },
    { "Warsong Gulch", 2000, "Arathi Basin", 500, "Alterac Valley", 200 })
  T.eq(other, 2750 - 2700, "Durotar's tick")
  T.eq({ Stats.LifeBattlegrounds(nil, 0, out) }, { 0, 0 })
end)

---------------------------------------------------------------------------
-- WorldPvpState
---------------------------------------------------------------------------

T.test("WorldPvpState: yes, partial or no from w0 and the level's start and end", function()
  local _, Stats = Load()
  local function Char(w0)
    return { level = 5, pvp = { w0 = w0 }, levels = {
      [1] = { t0 = 100, t1 = 900 },
      [2] = { t0 = 900 },                          -- its end: level 3's start
      [3] = { t0 = 1000, t1 = 1100 },
      [4] = { t0 = 1100, rec = true },
      [5] = { t0 = 1200 },                         -- current
    } }
  end
  local c = Char(1000)
  T.eq({ Stats.WorldPvpState(c, 1), Stats.WorldPvpState(c, 2), Stats.WorldPvpState(c, 3),
         Stats.WorldPvpState(c, 4), Stats.WorldPvpState(c, 5), Stats.WorldPvpState(c, 6) },
    { "no", "no", "yes", "no", "yes", "no" }, "ended before; ended at w0; begun at w0; rebuilt; current; none")
  c = Char(1050)
  T.eq({ Stats.WorldPvpState(c, 3), Stats.WorldPvpState(c, 5) }, { "partial", "yes" })
  c = Char(1300)
  T.eq(Stats.WorldPvpState(c, 5), "partial", "the current level begun before w0")
  c.levels[5].t0 = nil
  T.eq(Stats.WorldPvpState(c, 5), "partial", "the install's level: start unknown")
  T.eq(Stats.WorldPvpState(Char(nil), 5), "no", "no w0: a record from before")
  T.eq(Stats.WorldPvpState(Char("x"), 5), "no")
  T.eq(Stats.WorldPvpState({ levels = {} }, 5), "no", "no char.pvp")
  T.eq(Stats.WorldPvpState(nil, 5), "no")
end)

---------------------------------------------------------------------------
-- XPOf
---------------------------------------------------------------------------

T.test("XPOf: the level's own size, the account's, the table; scaled by the sizes that contradict it", function()
  local ns, Stats = Load()
  local X = ns.C.CLASSIC_XP
  local char = { levels = { [10] = { max = 7700 }, [5] = { max = 2800 } } }
  local db = { xpMax = { [13] = 11400 } }
  T.eq(Stats.XPOf(char, db, 10), 7700, "levels[l].max first")
  T.eq(Stats.XPOf(char, db, 13), 11400, "db.xpMax next")
  T.eq(Stats.XPOf(nil, nil, 30), X[30], "the table, nothing known")
  -- one contradicting size (7700 / 7600) scales the table; the agreeing ones do not count
  T.eq(Stats.XPOf(char, db, 30), floor(X[30] * 7700 / 7600 + 0.5))
  -- contradicting sizes: their mean ratio (2 and 3: 2.5)
  db.xpMax = { [20] = 2 * X[20], [21] = 3 * X[21], [6] = X[6] }
  char.levels[10] = nil
  T.eq(Stats.XPOf(char, db, 20), 2 * X[20], "known: as is")
  T.eq(Stats.XPOf(char, db, 30), floor(X[30] * 2.5 + 0.5), "the mean ratio of the contradicting ones")
  T.eq(Stats.XPOf(char, db, 5), 2800)
  -- beyond the table
  T.eq(Stats.XPOf(char, db, 60), nil, "nothing known: nil")
  db.xpMax[60] = 300000
  T.eq(Stats.XPOf(char, db, 60), 300000)
  -- bad values are unknown
  db.xpMax = { [14] = "x", [15] = -5, [16] = 0 / 0, [17] = math.huge }
  char.levels = { [18] = { max = 0 } }
  for l = 14, 18 do T.eq(Stats.XPOf(char, db, l), X[l], "bad " .. l) end
  T.eq(Stats.XPOf(char, db, "x"), nil)
end)

---------------------------------------------------------------------------
-- FutureLevels
---------------------------------------------------------------------------

-- Level 12 (1000 s so far); complete levels 10 and 11 give K = 50 exactly:
-- time 4000 + 4400 = 8400 s; XP / (45 + 5 l) = 7600 / 95 + 8800 / 100 = 80 + 88 = 168.
-- Level 9 partial and 8 rebuilt are left out; 11's stalled and untracked seconds too.
local function FutureChar()
  return {
    level = 12,
    ema = Ema(0, 0, 0, 0),
    levels = {
      [8] = { s = { w = 50000 }, xp = 0, rec = true },
      [9] = { s = { w = 90000 }, xp = 0, partial = true },
      [10] = { s = { w = 3600, W = 400 }, xp = 7600, xa = 7600, xr = 0, xq = 0 },
      [11] = { s = { w = 4450, u = 50 }, xs = { w = 50 }, xp = 8800, xa = 8800, xr = 0, xq = 0 },
      [12] = { s = { w = 1000 }, xp = 1100, xa = 1100, xr = 0, xq = 0 },
    },
  }
end

T.test("FutureLevels: K from the recent complete levels (hand-computed), the current level, the total", function()
  local ns, Stats = Load()
  local X = ns.C.CLASSIC_XP
  local char = FutureChar()
  local out = {}
  local info = { level = 12, valid = false, top = 21 }
  T.ok(rawequal(Stats.FutureLevels(char, nil, 0, info, out), out))
  T.eq({ out.status, out.src, out.n, out.top, out.missing }, { "ok", "recent", 2, 21, 0 })
  local K = 8400 / 168
  T.eq(K, 50)
  T.near(out[13], 50 * X[13] / 110, 1e-9, "est(13) = K XP(13) / (45 + 65)")
  T.eq(out[20], 8000, "est(20) = 50 * 23200 / 145")
  T.near(out.cur, 50 * X[12] / 105 - 1000, 1e-9, "the current level: est(12) less the 1000 s spent")
  local total = out.cur
  for l = 13, 20 do total = total + out[l] end
  T.near(out.total, total, 1e-6)
  T.eq({ out[12], out[21], out[1] }, { nil, nil, nil }, "only the levels to play")
  -- the AFK exclusion: level 10 counts 3600 s, K = 8000 / 168
  Stats.FutureLevels(char, nil, 1, info, out)
  T.near(out[20], 8000 / 168 * X[20] / 145, 1e-9)
  -- valid XP: the current level from Stats.ETA (a settled rate of 3 XP/s)
  char.ema = Ema(7200, 0, 3600, 3600)
  info.valid, info.xp, info.max, info.rest = true, 1100, 10100, 0
  Stats.FutureLevels(char, nil, 0, info, out)
  T.eq(out.cur, 3000, "(10100 - 1100) / 3")
  T.eq(out[20], 8000, "the levels to play still from K")
  -- a contradicting known size (level 11: twice the table) scales the table: level 10's
  -- unknown size too (K = 8400 / (160 + 176) = 25), and the levels to play
  Stats.FutureLevels(char, { xpMax = { [11] = 2 * X[11] } }, 0, info, out)
  T.eq(out.status, "ok")
  T.near(out[20], 8400 / (2 * 80 + 2 * 88) * 2 * X[20] / 145, 1e-6)
  T.eq(out[20], 8000)
end)

T.test("FutureLevels: one sample falls back on the XP rate (estimate); no rate: nodata", function()
  local ns, Stats = Load()
  local X = ns.C.CLASSIC_XP
  local char = FutureChar()
  char.levels[10] = nil
  char.ema = Ema(7200, 0, 3600, 3600)              -- A = 2, Q = 1 XP per second
  local out = {}
  local info = { level = 12, xp = 1100, max = 10100, rest = 0, valid = true, top = 21 }
  Stats.FutureLevels(char, nil, 0, info, out)
  T.eq({ out.status, out.src, out.n }, { "estimate", "rate", 1 })
  T.near(out[13], X[13] / 3 * 105 / 110, 1e-9, "XP(13) / (A + Q) scaled by (45 + 5*12) / (45 + 5*13)")
  T.near(out[20], 5600, 1e-9)
  T.eq(out.cur, 3000)
  -- not valid: est(12) less the time spent
  info.valid = false
  Stats.FutureLevels(char, nil, 0, info, out)
  T.near(out.cur, X[12] / 3 - 1000, 1e-9)
  -- no sample and no rate
  char = { level = 12, levels = {}, ema = Ema(0, 0, 0, 0) }
  Stats.FutureLevels(char, nil, 0, info, out)
  T.eq({ out.status, out.src, out.cur, out.total, out[13] }, { "nodata", nil, nil, nil, nil })
end)

T.test("FutureLevels: max level, server cap, no level; a later call clears the earlier levels", function()
  local _, Stats = Load()
  local char = FutureChar()
  local out = {}
  Stats.FutureLevels(char, nil, 0, { level = 12, top = 21 }, out)
  T.ok(out[20] ~= nil)
  Stats.FutureLevels(char, nil, 0, { level = 21, top = 21 }, out)
  T.eq({ out.status, out.cur, out.total, out[20], out[13] }, { "max", nil, nil, nil, nil }, "level >= top")
  Stats.FutureLevels(char, nil, 0, { level = 12, top = 21, isMax = true }, out)
  T.eq(out.status, "max", "the client says max (XP disabled)")
  Stats.FutureLevels(char, nil, 0, { level = 12, top = 21, capLevel = 12 }, out)
  T.eq({ out.status, out.total }, { "cap", nil }, "a server cap")
  Stats.FutureLevels(nil, nil, 0, nil, out)
  T.eq({ out.status, out.top }, { "nodata", 60 }, "no level: the table's top")
  -- a smaller top after a larger one: the levels above it cleared
  Stats.FutureLevels(char, nil, 0, { level = 12, top = 30 }, out)
  T.ok(out[29] ~= nil)
  Stats.FutureLevels(char, nil, 0, { level = 12, top = 21 }, out)
  T.eq({ out[29], out[21], out.top }, { nil, nil, 21 })
  -- a level without an XP size: counted in missing, left out of the total
  Stats.FutureLevels(char, nil, 0, { level = 12, top = 62 }, out)
  T.eq({ out.missing, out[60], out[61] }, { 2, nil, nil }, "levels 60 and 61: no size known")
  T.ok(out[59] > 0)
end)

---------------------------------------------------------------------------
-- History rows, Util.MaxLevel
---------------------------------------------------------------------------

T.test("LevelHistory rows: world PvP (capped), XP split, XP size, stalled time under the mask", function()
  local _, Stats = Load()
  local char = { level = 10, zones = {}, levels = {
    [10] = { s = { w = 500 }, xp = 0, z = {} },
    [9] = { s = { w = 100, W = 60 }, pw = 150, xp = 35, xa = 10, xq = 20, xr = 5, max = 6500,
            xs = { w = 30, W = 10 }, z = {} },
  } }
  local out = {}
  Stats.LevelHistory(char, 0, nil, 10, out)
  local r9 = out[2]
  T.eq({ r9.level, r9.pw, r9.xa, r9.xq, r9.xr, r9.max, r9.stall }, { 9, 100, 10, 20, 5, 6500, 40 })
  Stats.LevelHistory(char, 1, nil, 10, out)
  T.eq(out[2].stall, 30, "the AFK stalled seconds excluded")
  T.eq({ out[1].pw, out[1].xa, out[1].max, out[1].stall }, { 0, 0, nil, 0 }, "nothing recorded")
end)

T.test("Util.MaxLevel: the expansion's max level, the player's, else the table's end (60)", function()
  local ns = Load()
  local U = ns.Util
  local pl = Stub.player
  T.eq(U.MaxLevel(), 60)
  pl.expMaxLevel, pl.maxLevel = 70, 60
  T.eq(U.MaxLevel(), 70, "the expansion first")
  pl.expMaxLevel = nil
  T.eq(U.MaxLevel(), 60, "the player max level")
  pl.maxLevel = 65.7
  T.eq(U.MaxLevel(), 65, "a whole level")
  for _, v in ipairs({ 0, -1, "x", Stub.SECRET, 0 / 0 }) do
    pl.expMaxLevel, pl.maxLevel = v, v
    T.eq(U.MaxLevel(), #ns.C.CLASSIC_XP + 1, "unknown: " .. tostring(v))
  end
  local exp, max = rawget(_G, "GetMaxLevelForPlayerExpansion"), rawget(_G, "GetMaxPlayerLevel")
  rawset(_G, "GetMaxLevelForPlayerExpansion", function() error("boom") end)
  rawset(_G, "GetMaxPlayerLevel", nil)
  T.eq(U.MaxLevel(), 60, "an error, a missing API")
  rawset(_G, "GetMaxLevelForPlayerExpansion", exp)
  rawset(_G, "GetMaxPlayerLevel", max)
end)

---------------------------------------------------------------------------
-- Purity, allocation
---------------------------------------------------------------------------

T.test("the levels' Stats functions read neither ns.char, ns.session nor the Tracker", function()
  local ns, Stats = Load()
  local char = BgChar()
  char.pvp = { w0 = 1 }
  char.ema = Ema(100, 10, 20, 700)
  local fut = FutureChar()
  local db = { cities = {}, xpMax = { [20] = 23200 }, chars = { A = char } }
  ns.db = db
  rawset(ns, "char", nil)
  rawset(ns, "session", nil)
  rawset(ns, "Tracker", nil)
  local touched = {}
  local oldMeta = getmetatable(ns)
  setmetatable(ns, { __index = function(_, k)
    if k == "char" or k == "session" or k == "Tracker" then touched[#touched + 1] = k end
    return nil
  end })
  local ok, err = pcall(function()
    for m = 0, 7 do
      Stats.LevelSegments(char.levels[20], m, {})
      Stats.LevelBattlegrounds(char, 20, m, {})
      Stats.LifeBattlegrounds(char, m, {})
      Stats.FutureLevels(fut, db, m, { level = 12, valid = false, top = 21 }, {})
      Stats.FutureLevels(fut, db, m, { level = 12, xp = 10, max = 10100, valid = true, top = 21 }, {})
    end
    Stats.WorldPvpState(char, 20)
    Stats.XPOf(char, db, 30)
  end)
  setmetatable(ns, oldMeta)
  T.ok(ok, err)
  T.eq(#touched, 0, touched[1])
end)

T.test("LevelSegments, WorldPvpState, XPOf and FutureLevels (same out, same level) allocate nothing", function()
  local _, Stats = Load()
  local b = RichBucket()
  local seg = {}
  local fut = FutureChar()
  fut.pvp = { w0 = 1 }
  fut.levels[12].t0 = 5
  local db = { xpMax = { [20] = 2 * 23200 } }
  local out = {}
  local infoA = { level = 12, valid = false, top = 60 }
  local infoB = { level = 12, xp = 1100, max = 10100, rest = 500, valid = true, top = 60 }
  local rateChar = FutureChar()
  rateChar.levels[10] = nil
  rateChar.ema = Ema(7200, 0, 3600, 3600)
  local function Work(i)
    local m = i % 8
    Stats.LevelSegments(b, m, seg)
    Stats.WorldPvpState(fut, 12)
    Stats.WorldPvpState(fut, 11)
    Stats.XPOf(fut, db, 30)
    Stats.FutureLevels(fut, db, m, (i % 2 == 0) and infoA or infoB, out)
    Stats.FutureLevels(rateChar, db, m, infoB, out)
  end
  for i = 1, 16 do Work(i) end
  local kb = T.alloc(Work, 1000)
  T.ok(kb < 0.5, format("allocated %.3f KB", kb))
end)
