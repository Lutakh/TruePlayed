-- tests/test_stats.lua - Stats.lua (IMPL-3), SPEC-FINAL 9.4.
-- Stats is pure: every test builds its records by hand and loads only the files Stats
-- depends on (locales, Core for ns.C, Format), so a failure here points at Stats.
local Stub, T = ...

local format = string.format

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

-- Fixed bucket used by several tests: SumAll = 11178, u = 9000, tracked = 2178.
local function FixedBucket()
  return { s = { w = 1000, W = 200, i = 300, I = 40, c = 500, C = 60, t = 70, T = 8, u = 9000 }, xp = 0 }
end

---------------------------------------------------------------------------
-- Sums and breakdown
---------------------------------------------------------------------------

T.test("Sum over the 8 masks matches hand sums", function()
  local ns, Stats = Load()
  local b = FixedBucket()
  local expected = { [0] = 11178, [1] = 10870, [2] = 10838, [3] = 10570,
                     [4] = 10618, [5] = 10370, [6] = 10278, [7] = 10070 }
  for m = 0, 7 do
    T.eq(Stats.Sum(b, m), expected[m], format("mask %d", m))
  end
  T.eq(Stats.SumAll(b), 11178)
  T.eq(Stats.Tracked(b), 2178)
  T.eq(Stats.SumKeys(b, ns.C.AFK_KEYS), 308)
  T.eq(Stats.SumKeys(b, ns.C.INN_KEYS), 340)
  T.eq(Stats.SumKeys(b, ns.C.CITY_KEYS), 560)
  T.eq(Stats.SumKeys(b, ns.C.TAXI_KEYS), 78)
  -- nil and sparse buckets
  T.eq(Stats.Sum(nil, 3), 0)
  T.eq(Stats.SumAll(nil), 0)
  T.eq(Stats.Tracked(nil), 0)
  T.eq(Stats.Sum({ s = {} }, 7), 0)
  T.eq(Stats.Sum({ s = { W = 5 } }, 1), 0)
  T.eq(Stats.Sum({ s = { u = 5 } }, 7), 5, "u is never excluded")
  T.eq(Stats.Sum({}, 0), 0, "bucket without s")
end)

T.test("Breakdown partitions tracked time and reuses its output table", function()
  local _, Stats = Load()
  local b = FixedBucket()
  b.est = 42
  local out = {}
  T.ok(rawequal(Stats.Breakdown(b, out), out), "returns the given table")
  T.eq(out.active, 1070)
  T.eq(out.afk, 308)
  T.eq(out.inn, 300)
  T.eq(out.city, 500)
  T.eq(out.taxi, 78)
  T.eq(out.untracked, 9000)
  T.eq(out.total, 11178)
  T.eq(out.tracked, 2178)
  T.eq(out.innAll, 340)
  T.eq(out.innAfk, 40)
  T.eq(out.cityAll, 560)
  T.eq(out.cityAfk, 60)
  T.eq(out.est, 42)
  -- percentages are taken over tracked time (critique #10a): the partition sums to it
  T.eq(out.active + out.afk + out.inn + out.city, out.tracked)
  T.near(out.afk / out.tracked, 308 / 2178, 1e-12)
  -- empty bucket
  Stats.Breakdown(nil, out)
  T.eq(out.total, 0)
  T.eq(out.tracked, 0)
  T.eq(out.est, 0)
end)

---------------------------------------------------------------------------
-- Displayed totals
---------------------------------------------------------------------------

T.test("Played: live base minus excluded with a sync, SumAll without", function()
  local _, Stats = Load()
  local char = { level = 10, life = FixedBucket(), levels = {} }
  local sync = { valid = true, total = 20000, g = 100, level = 10, levelValid = false }
  local filtered, base, excluded, live = Stats.Played(char, 1, sync, 110)
  T.eq(base, 20010)
  T.eq(excluded, 308)
  T.eq(filtered, 19702)
  T.eq(live, true)
  -- a restored sync counts as live too
  sync.restored = true
  T.eq((Stats.Played(char, 0, sync, 110)), 20010)

  filtered, base, excluded, live = Stats.Played(char, 1, nil, 110)
  T.eq(base, 11178)
  T.eq(excluded, 308)
  T.eq(filtered, 10870)
  T.eq(live, false)
  -- an invalid sync is ignored
  local invalid = { valid = false, total = 5, g = 0 }
  T.eq(select(2, Stats.Played(char, 0, invalid, 110)), 11178)
  T.eq(select(4, Stats.Played(char, 0, invalid, 110)), false)
  -- never negative
  T.eq((Stats.Played(char, 7, { valid = true, total = 100, g = 110 }, 110)), 0)
  -- no record
  T.eq((Stats.Played(nil, 0, nil, 110)), 0)
end)

T.test("LevelTime is live only with a valid level part for that level", function()
  local _, Stats = Load()
  local char = { level = 10, levels = {
    [10] = { s = { w = 400, W = 100 }, xp = 0 },
    [9] = { s = { w = 900, C = 50 }, xp = 0 },
  } }
  local sync = { valid = true, total = 50000, g = 200, level = 10, levelValid = true, levelPlayed = 700 }
  local filtered, base, live = Stats.LevelTime(char, 10, 1, sync, 230)
  T.eq(base, 730)
  T.eq(filtered, 630)
  T.eq(live, true)
  -- another level: local data
  filtered, base, live = Stats.LevelTime(char, 9, 5, sync, 230)
  T.eq(base, 950)
  T.eq(filtered, 900)
  T.eq(live, false)
  -- level part not valid (race after a level-up, critique #5)
  sync.levelValid = false
  filtered, base, live = Stats.LevelTime(char, 10, 1, sync, 230)
  T.eq(base, 500)
  T.eq(filtered, 400)
  T.eq(live, false)
  -- no sync
  T.eq(select(2, Stats.LevelTime(char, 10, 0, nil, 230)), 500)
  T.eq(select(3, Stats.LevelTime(char, 10, 0, nil, 230)), false)
  -- missing level record
  filtered, base = Stats.LevelTime(char, 42, 0, nil, 230)
  T.eq(filtered, 0)
  T.eq(base, 0)
  T.eq(Stats.SessionTime({ s = { w = 10, W = 5 } }, 1), 10)
  T.eq(Stats.SessionTime(nil, 1), 0)
end)

---------------------------------------------------------------------------
-- Averages
---------------------------------------------------------------------------

T.test("overall average per level (level 1 -> nil)", function()
  local _, Stats = Load()
  T.eq(Stats.AvgPerLevel({ level = 1, life = { s = { w = 500 } }, levels = {} }, 0, nil, 0), nil)
  T.eq(Stats.AvgPerLevel(nil, 0, nil, 0), nil)
  local char = { level = 3, life = { s = { w = 3000, W = 600 } },
                 levels = { [3] = { s = { w = 500, W = 100 }, xp = 0 } } }
  T.eq(Stats.AvgPerLevel(char, 0, nil, 0), 1500)
  T.eq(Stats.AvgPerLevel(char, 1, nil, 0), 1250)
  -- live values: (server total - live level time) / (level - 1)
  local sync = { valid = true, total = 4000, g = 0, level = 3, levelValid = true, levelPlayed = 700 }
  T.eq(Stats.AvgPerLevel(char, 0, sync, 0), 1650)
end)

T.test("recent average skips partial and reconstructed levels and needs 2", function()
  local _, Stats = Load()
  local char = { level = 10, levels = {
    [10] = { s = { w = 50 }, xp = 0 },
    [9] = { s = { w = 9999 }, xp = 0, partial = true },
    [8] = { s = { w = 8888 }, xp = 0, rec = true },
    [7] = { s = { w = 700, W = 70 }, xp = 0, est = 30 },   -- estimated part: still counted
    [6] = { s = { w = 600 }, xp = 0 },
    [5] = { s = { w = 500 }, xp = 0 },
    [4] = { s = { w = 400 }, xp = 0 },                     -- outside the 5-level window
  } }
  local avg, n = Stats.RecentAvg(char, 0, 5)
  T.eq(n, 3)
  T.near(avg, (770 + 600 + 500) / 3, 1e-9)
  avg = Stats.RecentAvg(char, 1, 5)
  T.eq(avg, 600)
  -- default window = C.RECENT_LEVELS
  local avgDefault = Stats.RecentAvg(char, 0)
  T.near(avgDefault, (770 + 600 + 500) / 3, 1e-9)
  -- window of 3 -> only level 7 qualifies -> nil
  avg, n = Stats.RecentAvg(char, 0, 3)
  T.eq(avg, nil)
  T.eq(n, 1)
  -- nothing below level 1
  avg, n = Stats.RecentAvg({ level = 1, levels = { [1] = { s = { w = 5 } } } }, 0, 5)
  T.eq(avg, nil)
  T.eq(n, 0)
end)

---------------------------------------------------------------------------
-- Rates
---------------------------------------------------------------------------

T.test("Rate fallback chain: settled EMA", function()
  local _, Stats = Load()
  local char = { level = 10, levels = { [10] = { s = { w = 5000 }, xp = 99999, xa = 99999, xr = 0, xq = 0 } },
                 ema = Ema(1000, 200, 800, 3600) }
  local xph, A, R, Q, src, status, left = Stats.Rate(char, 0)
  T.near(xph, 2000, 1e-9)
  T.near(A, 1000 / 3600, 1e-12)
  T.near(R, 200 / 3600, 1e-12)
  T.near(Q, 800 / 3600, 1e-12)
  T.eq(src, "ema")
  T.eq(status, "ok")
  T.eq(left, 0)
  -- each mask reads its own entry
  char.ema[2] = { a = 3600, r = 0, q = 0, d = 3600 }
  T.near((Stats.Rate(char, 1)), 3600, 1e-9)
end)

T.test("Rate fallback chain: current level", function()
  local _, Stats = Load()
  local char = { level = 10, ema = Ema(0, 0, 0, 0), levels = {
    [10] = { s = { w = 1800, W = 600, u = 100 }, xp = 1800, xa = 900, xr = 0, xq = 900 },
  } }
  local xph, A, R, Q, src, status, left = Stats.Rate(char, 0)
  T.near(xph, 2700, 1e-9)            -- 1800 XP over 2400 tracked seconds
  T.near(A, 0.375, 1e-12)
  T.eq(R, 0)
  T.near(Q, 0.375, 1e-12)
  T.eq(src, "level")
  T.eq(status, "ok")
  T.eq(left, 0)
  T.near((Stats.Rate(char, 1)), 3600, 1e-9)   -- AFK excluded: 1800 s
end)

T.test("Rate fallback chain: recent levels (partial out, rec in, u out)", function()
  local _, Stats = Load()
  local char = { level = 10, ema = Ema(0, 0, 0, 0), levels = {
    [10] = { s = { w = 100 }, xp = 50, xa = 50, xr = 0, xq = 0 },           -- under FALLBACK_MIN
    [9] = { s = { w = 1000 }, xp = 1000, xa = 600, xr = 100, xq = 300 },
    [8] = { s = { w = 50000 }, xp = 99999, xa = 99999, xr = 0, xq = 0, partial = true },
    [7] = { s = { w = 2000, u = 500 }, xp = 2000, xa = 1500, xr = 0, xq = 500, rec = true },
    [4] = { s = { w = 7777 }, xp = 7777, xa = 7777, xr = 0, xq = 0 },        -- outside the window
  } }
  local xph, A, R, Q, src, status, left = Stats.Rate(char, 0)
  T.near(xph, 3600, 1e-9)            -- 3000 XP over 3000 tracked seconds
  T.near(A, 2100 / 3000, 1e-12)
  T.near(R, 100 / 3000, 1e-12)
  T.near(Q, 800 / 3000, 1e-12)
  T.eq(src, "recent")
  T.eq(status, "ok")
  T.eq(left, 0)
end)

T.test("Rate fallback chain: provisional EMA and no data", function()
  local ns, Stats = Load()
  local C = ns.C
  local char = { level = 10, ema = Ema(400, 0, 100, 300),
                 levels = { [10] = { s = { w = 100 }, xp = 0, xa = 0, xr = 0, xq = 0 } } }
  local xph, A, R, Q, src, status, left = Stats.Rate(char, 0)
  T.near(xph, 6000, 1e-9)
  T.near(A, 400 / 300, 1e-12)
  T.eq(R, 0)
  T.near(Q, 100 / 300, 1e-12)
  T.eq(src, "ema")
  T.eq(status, "warming")
  T.eq(left, C.WARMUP_FULL - 300)

  char.ema = Ema(400, 0, 100, 100)
  xph, A, R, Q, src, status, left = Stats.Rate(char, 0)
  T.eq(xph, nil)
  T.eq(A, 0)
  T.eq(R, 0)
  T.eq(Q, 0)
  T.eq(src, nil)
  T.eq(status, "nodata")
  T.eq(left, C.WARMUP_FULL - 100)

  -- settled clock but no XP at all (e.g. after /tpl reset rate): no data, nothing left
  char.ema = Ema(0, 0, 0, 900)
  T.eq(select(6, Stats.Rate(char, 0)), "nodata")
  T.eq(select(7, Stats.Rate(char, 0)), 0)
  -- missing ema table
  T.eq(select(6, Stats.Rate({ level = 1, levels = {} }, 0)), "nodata")
  T.eq(select(7, Stats.Rate({ level = 1, levels = {} }, 0)), C.WARMUP_FULL)
end)

T.test("ETA statuses around WARMUP_MIN and WARMUP_FULL", function()
  local ns, Stats = Load()
  local C = ns.C
  local char = { level = 10, levels = { [10] = { s = {}, xp = 0 } } }
  local function At(d)
    char.ema = Ema(d * 0.5, 0, 0, d)     -- always 0.5 XP per second
    return Stats.ETA(char, 0, 0, 1000, 0, false)
  end
  local sec, status, src, left = At(C.WARMUP_MIN - 1)
  T.eq(sec, nil)
  T.eq(status, "nodata")
  T.eq(src, nil)
  T.eq(left, C.WARMUP_FULL - (C.WARMUP_MIN - 1))
  sec, status, src, left = At(C.WARMUP_MIN)
  T.near(sec, 2000, 1e-9)
  T.eq(status, "warming")
  T.eq(src, "ema")
  T.eq(left, C.WARMUP_FULL - C.WARMUP_MIN)
  T.eq(select(2, At(C.WARMUP_FULL - 1)), "warming")
  sec, status, src, left = At(C.WARMUP_FULL)
  T.near(sec, 2000, 1e-9)
  T.eq(status, "ok")
  T.eq(src, "ema")
  T.eq(left, 0)
  -- max level
  sec, status = Stats.ETA(char, 0, 0, 1000, 0, true)
  T.eq(sec, nil)
  T.eq(status, "max")
  -- XP already complete
  T.eq((Stats.ETA(char, 0, 1000, 1000, 0, false)), 0)
end)

T.test("EtaRestAware edge cases", function()
  local _, Stats = Load()
  T.eq(Stats.EtaRestAware(1000, 0, 1, 1), 500)      -- no pool
  T.eq(Stats.EtaRestAware(1000, 500, 0, 2), 500)    -- A = 0: the pool is never used
  T.eq(Stats.EtaRestAware(0, 500, 1, 1), 0)         -- R <= 0
  T.eq(Stats.EtaRestAware(-5, 0, 1, 1), 0)
  T.eq(Stats.EtaRestAware(1000, 100, 0, 0), nil)    -- no rate at all
  T.eq(Stats.EtaRestAware(nil, 100, 1, 1), nil)
end)

T.test("EtaRestAware with a rested pool (hand-checked)", function()
  local ns, Stats = Load()
  if ns.C.REST_BONUS ~= 1 or ns.C.REST_DRAIN ~= 2 then
    T.skip("hand-checked values assume REST_BONUS = 1 and REST_DRAIN = 2")
  end
  -- pool drained mid-level: 50 s at 2 XP/s (100 XP, pool 100 -> 0), then 900 XP at 1 XP/s
  T.eq(Stats.EtaRestAware(1000, 100, 1, 0), 950)
  -- with quests: rested speed 3 XP/s for 50 s (150 XP), then 850 XP at 2 XP/s
  T.eq(Stats.EtaRestAware(1000, 100, 1, 1), 475)
  -- pool covering the whole level: 1000 XP at 2 XP/s
  T.eq(Stats.EtaRestAware(1000, 10000, 1, 0), 500)
end)

T.test("secondary rates need RATE_SAMPLE_MIN seconds", function()
  local ns, Stats = Load()
  local C = ns.C
  local session = { s = { w = C.RATE_SAMPLE_MIN - 1 }, xp = 1000 }
  T.eq(Stats.SessionRate(session, 0), nil)
  session.s.w = 1800
  T.near(Stats.SessionRate(session, 0), 2000, 1e-9)
  session.s.W = 1800
  T.near(Stats.SessionRate(session, 0), 1000, 1e-9)
  T.near(Stats.SessionRate(session, 1), 2000, 1e-9)
  T.eq(Stats.SessionRate(nil, 0), nil)
  local char = { level = 5, levels = { [5] = { s = { w = 1800, u = 7200 }, xp = 900 } } }
  T.near(Stats.LevelRate(char, 5, 0), 1800, 1e-9)   -- u is not tracked time
  T.eq(Stats.LevelRate(char, 6, 0), nil)
  char.levels[5].s.w = 100
  T.eq(Stats.LevelRate(char, 5, 0), nil)
end)

---------------------------------------------------------------------------
-- Zones and cities
---------------------------------------------------------------------------

local function CityZones()
  return {
    [1454] = { s = { c = 100, C = 50, t = 1000, T = 20 }, xp = 10, name = "Orgrimmar" },  -- incl. a flight over it
    [1453] = { s = { c = 10 }, xp = 0, name = "Stormwind City" },
    [1446] = { s = { w = 5000, W = 300 }, xp = 9000, name = "Tanaris" },
    [1458] = { s = { C = 20, w = 5 }, xp = 0, name = "Undercity" },   -- removed from the city list below
    i389 = { s = { w = 50 }, xp = 0, name = "Ragefire Chasm" },
  }
end

T.test("TopCities sums only c + C and keeps zones no longer listed as cities", function()
  local ns, Stats = Load()
  ns.db = { cities = { [1458] = false }, chars = {} }
  local zones = CityZones()
  local life = { s = { c = 110, C = 70, t = 1000, T = 20, w = 5055, W = 300 } }
  local out = {}
  local rows, n = Stats.TopCities(zones, 1000, out)
  T.ok(rawequal(rows, out))
  T.eq(n, 3)
  T.eq(#out, 3)
  T.eq(out[1].key, 1454)
  T.eq(out[1].total, 150)
  T.eq(out[1].afk, 50)
  T.eq(out[1].name, "Orgrimmar")
  T.eq(out[2].key, 1458)
  T.eq(out[2].total, 20)
  T.eq(out[2].afk, 20)
  T.eq(out[3].key, 1453)
  T.eq(out[3].total, 10)
  -- invariant 5.17
  local sum = 0
  for i = 1, n do sum = sum + out[i].total end
  T.eq(sum, life.s.c + life.s.C)
  -- top 1, rows reused
  local first = out[1]
  n = select(2, Stats.TopCities(zones, 1, out))
  T.eq(n, 1)
  T.eq(#out, 1)
  T.eq(out[1].key, 1454)
  T.ok(rawequal(out[1], first), "row table recycled")
  -- empty map
  n = select(2, Stats.TopCities(nil, 3, out))
  T.eq(n, 0)
  T.eq(#out, 0)
end)

T.test("IsCityKey: city seconds, overrides and built-in capitals", function()
  local ns, Stats = Load()
  local zones = CityZones()
  T.ok(Stats.IsCityKey(1454, nil), "capital without data")
  T.no(Stats.IsCityKey(1446, zones[1446]))
  T.no(Stats.IsCityKey("i389", zones.i389))
  ns.db = { cities = { [1458] = false, [1446] = true }, chars = {} }
  T.ok(Stats.IsCityKey(1458, zones[1458]), "holds city seconds")
  T.no(Stats.IsCityKey(1458, { s = { w = 5 } }), "override false")
  T.ok(Stats.IsCityKey(1446, zones[1446]), "override true")
  ns.db = nil
  T.ok(Stats.IsCityKey(1453, nil), "no db yet")
end)

T.test("TopZones sorts by filtered time with deterministic ties", function()
  local ns, Stats = Load()
  ns.db = { cities = {}, chars = {} }
  local zones = CityZones()
  local out = {}
  local _, n = Stats.TopZones(zones, 2, 0, out)
  T.eq(n, 2)
  T.eq(out[1].key, 1446)
  T.eq(out[1].filtered, 5300)
  T.eq(out[1].raw, 5300)
  T.eq(out[1].afk, 300)
  T.eq(out[1].xp, 9000)
  T.eq(out[1].isCity, false)
  T.eq(out[1].name, "Tanaris")
  T.eq(out[2].key, 1454)
  T.eq(out[2].raw, 1170)
  T.eq(out[2].isCity, true)
  -- AFK and city excluded: Orgrimmar keeps only its flight time
  _, n = Stats.TopZones(zones, 10, 5, out)
  T.eq(n, 5)
  T.eq(out[1].filtered, 5000)
  T.eq(out[2].key, 1454)
  T.eq(out[2].filtered, 1000)
  T.eq(out[5].filtered, 0)
  -- ties: numeric keys first, then by key
  local tie = { [20] = { s = { w = 10 } }, [10] = { s = { w = 10 } }, b = { s = { w = 10 } }, a = { s = { w = 10 } } }
  _, n = Stats.TopZones(tie, 4, 0, out)
  T.eq(n, 4)
  T.eq(out[1].key, 10)
  T.eq(out[2].key, 20)
  T.eq(out[3].key, "a")
  T.eq(out[4].key, "b")
end)

T.test("ZoneName calls C_Map only for numeric keys, once per key", function()
  local calls = 0
  local orig = C_Map.GetMapInfo
  C_Map.GetMapInfo = function(id)       -- installed before LoadAddon
    calls = calls + 1
    return orig(id)
  end
  local ns, Stats = Load()
  local L = ns.L
  T.eq(Stats.ZoneName("i389", { name = "Ragefire Chasm" }), "Ragefire Chasm")
  T.eq(Stats.ZoneName("i389", nil), L.ZONE_UNKNOWN)
  T.eq(Stats.ZoneName("nDurotar", nil), "Durotar")
  T.eq(Stats.ZoneName("o", nil), L.ZONE_OTHER)
  T.eq(Stats.ZoneName(nil, nil), L.ZONE_UNKNOWN)
  T.eq(calls, 0, "no C_Map call for string keys")
  T.eq(Stats.ZoneName(1411, nil), Stub.maps[1411].name)
  T.eq(Stats.ZoneName(1411, { name = "Old name" }), Stub.maps[1411].name)
  T.eq(calls, 1, "cached per key")
  T.eq(Stats.ZoneName(987654, { name = "Saved name" }), "Saved name")
  T.eq(Stats.ZoneName(987654, nil), L.ZONE_UNKNOWN)
  T.eq(calls, 2)
  Stats.ResetCaches()
  Stats.ZoneName(1411, nil)
  T.eq(calls, 3, "ResetCaches clears the name cache")
  C_Map.GetMapInfo = orig
end)

---------------------------------------------------------------------------
-- Account (two records)
---------------------------------------------------------------------------

local function TwoChars()
  local a = { guid = "Player-1-A", name = "Lutak", level = 12,
    life = { s = { w = 1000, W = 100 }, xp = 0 },
    levels = {
      [10] = { s = { w = 600 }, xp = 6000 },
      [11] = { s = { w = 400, W = 100 }, xp = 4000 },
      [12] = { s = { w = 50 }, xp = 100 },                       -- current: not complete
    },
    zones = { [1411] = { s = { w = 900 }, xp = 9000, name = "Durotar" },
              [1454] = { s = { c = 100, C = 20 }, xp = 0, name = "Orgrimmar" } },
  }
  local b = { guid = "Player-1-B", name = "Lutak", level = 11,   -- same name, other GUID
    life = { s = { w = 2000, I = 200 }, xp = 0 },
    levels = {
      [9] = { s = { w = 9 }, xp = 9, partial = true },
      [10] = { s = { w = 1000, u = 0 }, xp = 5000 },
      [11] = { s = { w = 70 }, xp = 10 },
      [8] = { s = { w = 800 }, xp = 800, rec = true },
    },
    zones = { [1411] = { s = { w = 100 }, xp = 1000 },
              [1413] = { s = { w = 1900, I = 200 }, xp = 4000, name = "The Barrens" } },
  }
  return { cities = {}, xpMax = {}, chars = { [a.guid] = a, [b.guid] = b } }, a, b
end

T.test("account totals and averages over two records", function()
  local _, Stats = Load()
  local db = TwoChars()
  local filtered, raw, n = Stats.Account(db, 0)
  T.eq(filtered, 3300)
  T.eq(raw, 3300)
  T.eq(n, 2)
  filtered, raw = Stats.Account(db, 1)
  T.eq(filtered, 3000)
  T.eq(raw, 3300)

  local rows, count = Stats.AccountLevelAverages(db, 0, {})
  T.eq(count, 2)
  T.eq(rows[1].level, 10)
  T.eq(rows[1].n, 2)
  T.eq(rows[1].avg, 800)
  T.near(rows[1].xph, 3600 * 11000 / 1600, 1e-9)
  T.eq(rows[2].level, 11)
  T.eq(rows[2].n, 1)
  T.eq(rows[2].avg, 500)
  T.near(rows[2].xph, 3600 * 4000 / 500, 1e-9)
  rows = Stats.AccountLevelAverages(db, 1, rows)
  T.eq(rows[2].avg, 400)

  local avg, nChars = Stats.AccountAvgPerLevel(db, 0)
  T.eq(avg, 700)                       -- (600 + 500 + 1000) / 3 complete levels
  T.eq(nChars, 2)
  avg, nChars = Stats.AccountAvgPerLevel({ chars = {} }, 0)
  T.eq(avg, nil)
  T.eq(nChars, 0)
  T.eq(select(3, Stats.Account(nil, 0)), 0)

  local merged = Stats.AccountZones(db, {})
  T.eq(merged[1411].s.w, 1000)
  T.eq(merged[1411].xp, 10000)
  T.eq(merged[1411].name, "Durotar")
  T.eq(merged[1413].s.I, 200)
  T.eq(merged[1454].s.c, 100)
  -- recycled output: entries that disappeared are removed
  db.chars["Player-1-B"] = nil
  merged = Stats.AccountZones(db, merged)
  T.eq(merged[1413], nil)
  T.eq(merged[1411].s.w, 900)
end)

---------------------------------------------------------------------------
-- History tables
---------------------------------------------------------------------------

local function HistoryChar()
  return { level = 10,
    zones = { [1411] = { s = { w = 5000 }, xp = 0, name = "Durotar" },
              [1413] = { s = { w = 300 }, xp = 0, name = "The Barrens" } },
    levels = {
      [10] = { s = { w = 400, W = 100 }, xp = 300, est = 0, srvStart = 50000,
               z = { [1411] = { s = { w = 400, W = 100 }, xp = 300 } } },
      [9] = { s = { w = 1000, I = 60, c = 40, C = 10 }, xp = 5000, est = 600, d = 2,
              srvStart = 48000, srvEnd = 49160, t0 = 1789000000, t1 = 1789100000,
              z = { [1411] = { s = { w = 700 }, xp = 3000 }, [1413] = { s = { w = 300 }, xp = 2000 } } },
      [8] = { s = { w = 800 }, xp = 4000, rec = true, srvStart = 47000, srvEnd = 47830, z = {} },
      [7] = { s = { w = 200, u = 5000 }, xp = 1000, partial = true, z = {} },
    },
  }
end

T.test("LevelHistory: order, flags, server time and gaps", function()
  local ns, Stats = Load()
  local C = ns.C
  local char = HistoryChar()
  local sync = { valid = true, total = 50500, g = 0, level = 10, levelValid = true, levelPlayed = 500 }
  local out = {}
  local rows, n = Stats.LevelHistory(char, 1, sync, 10, out)
  T.ok(rawequal(rows, out))
  T.eq(n, 4)
  T.eq(#out, 4)
  local r1, r2, r3, r4 = out[1], out[2], out[3], out[4]
  T.eq(r1.level, 10)
  T.eq(r1.current, true)
  T.eq(r1.server, 510)
  T.eq(r1.filtered, 410)
  T.eq(r1.raw, 500)
  T.eq(r1.gap, nil)
  T.eq(r1.mainZone, "Durotar")

  T.eq(r2.level, 9)
  T.eq(r2.current, false)
  T.eq(r2.server, 1160)
  T.eq(r2.raw, 1110)
  T.eq(r2.filtered, 1040)             -- AFK excluded
  T.eq(r2.gap, nil, "50 s is within DRIFT_TOL")
  T.eq(r2.est, 600)
  T.eq(r2.xp, 5000)
  T.eq(r2.afk, 70)
  T.eq(r2.inn, 60)
  T.eq(r2.city, 50)
  T.eq(r2.deaths, 2)
  T.eq(r2.reachedAt, 1789000000)
  T.eq(r2.mainZone, "Durotar")
  T.eq(r2.partial, false)
  T.eq(r2.rec, false)

  T.eq(r3.level, 8)
  T.eq(r3.rec, true)
  T.eq(r3.server, 830)
  T.eq(r3.gap, nil)
  T.eq(r3.mainZone, nil)

  T.eq(r4.level, 7)
  T.eq(r4.partial, true)
  T.eq(r4.server, nil)
  T.eq(r4.gap, nil)

  -- a server duration longer than the tracked one by more than DRIFT_TOL is a gap
  char.levels[9].srvEnd = 48000 + 1110 + C.DRIFT_TOL + 40
  Stats.LevelHistory(char, 0, sync, 10, out)
  T.eq(out[2].gap, C.DRIFT_TOL + 40)

  -- without a sync the current level has no server time...
  Stats.LevelHistory(char, 0, nil, 10, out)
  T.eq(out[1].server, nil)
  T.eq(out[1].filtered, 500)
  -- ...and with a sync whose level part is not valid it is derived from srvStart
  sync.levelValid = false
  Stats.LevelHistory(char, 0, sync, 10, out)
  T.eq(out[1].server, 510)
  T.eq(out[1].filtered, 500)

  -- rows shrink with the data
  char.levels[7], char.levels[8] = nil, nil
  n = select(2, Stats.LevelHistory(char, 0, nil, 10, out))
  T.eq(n, 2)
  T.eq(#out, 2)
end)

T.test("LevelHistory: the main zone of a level follows the exclusions", function()
  local ns, Stats = Load()
  local C = ns.C
  local char = {
    level = 12,
    levels = {
      [11] = { s = { c = 1000, w = 1200 }, xp = 0, z = {
        [1454] = { s = { c = 1000 } },       -- Orgrimmar: largest raw time, all city
        [1413] = { s = { w = 600 } },
        [1411] = { s = { w = 600 } },
      } },
      [12] = { s = { w = 10 }, xp = 0, z = { [1411] = { s = { w = 10 } } } },
    },
    zones = {
      [1454] = { s = { c = 1000 }, name = "Orgrimmar" },
      [1411] = { s = { w = 610 }, name = "Durotar" },
      [1413] = { s = { w = 600 }, name = "The Barrens" },
    },
  }
  local out = {}
  Stats.LevelHistory(char, 0, nil, 10, out)
  T.eq(out[2].level, 11)
  T.eq(out[2].mainZone, "Orgrimmar", "no exclusion: largest raw time")
  Stats.LevelHistory(char, C.MASK_CITY, nil, 10, out)
  T.eq(out[2].mainZoneKey, 1411, "city excluded: equal filtered times, numeric key order")
  T.eq(out[2].mainZone, "Durotar")
  char.levels[11].z[1413].s.W = 5          -- same filtered time, larger raw time wins
  Stats.LevelHistory(char, C.MASK_CITY + C.MASK_AFK, nil, 10, out)
  T.eq(out[2].mainZoneKey, 1413)
  char.levels[11].z = { [1454] = { s = { c = 1000 } } }
  Stats.LevelHistory(char, C.MASK_CITY, nil, 10, out)
  T.eq(out[2].mainZone, "Orgrimmar", "only excluded time: still the zone where it was spent")
end)

T.test("SessionHistory: in-progress session first, then newest first", function()
  local ns, Stats = Load()
  local C = ns.C
  local char = { level = 12,
    cur = { t0 = 300, l0 = 12, p0 = 0.1, s = { w = 1800, W = 600 }, xp = 900, d = 1 },
    sessions = {
      { t0 = 100, t1 = 150, l0 = 10, p0 = 0.5, l1 = 11, p1 = 0.2, s = { w = 50 }, xp = 10, d = 0 },
      { t0 = 200, t1 = 260, l0 = 11, p0 = 0.2, l1 = 12, p1 = 0.05, s = { w = 60, I = C.RATE_SAMPLE_MIN }, xp = 20, d = 0 },
    },
  }
  local out = {}
  local _, n = Stats.SessionHistory(char, 1, out)
  T.eq(n, 3)
  T.eq(out[1].current, true)
  T.eq(out[1].t0, 300)
  T.eq(out[1].dur, 1800)
  T.eq(out[1].l1, 12)
  T.eq(out[1].afk, 600)
  T.near(out[1].xph, 1800, 1e-9)
  T.eq(out[2].t0, 200)
  T.eq(out[2].current, false)
  T.eq(out[2].l1, 12)
  T.eq(out[2].p1, 0.05)
  T.eq(out[2].dur, 60)
  T.eq(out[3].t0, 100)
  T.eq(out[3].xph, nil)
  _, n = Stats.SessionHistory({ sessions = {} }, 0, out)
  T.eq(n, 0)
  T.eq(#out, 0)
end)

---------------------------------------------------------------------------
-- Labels, isolation, allocation
---------------------------------------------------------------------------

T.test("MaskLabel is built once per mask and localized", function()
  local ns, Stats = Load()
  local L = ns.L
  T.eq(Stats.MaskLabel(0), nil)
  T.eq(Stats.MaskLabel(1), L.MASK_AFK)
  T.eq(Stats.MaskLabel(5), L.MASK_AFK .. L.SEP .. L.MASK_CITY)
  T.eq(Stats.MaskLabel(7), L.MASK_AFK .. L.SEP .. L.MASK_INN .. L.SEP .. L.MASK_CITY)
  T.ok(rawequal(Stats.MaskLabel(6), Stats.MaskLabel(6)))
  T.eq(Stats.MaskLabel(6), "inn \194\183 city")
end)

T.test("MaskLabel in French", function()
  Stub.locale = "frFR"
  local _, Stats = Load()
  T.eq(Stats.MaskLabel(6), "auberge \194\183 ville")
end)

T.test("no Stats function reads ns.char, ns.session or the Tracker", function()
  local ns, Stats = Load()
  local char = HistoryChar()
  char.guid = "Player-1-A"
  char.life = FixedBucket()
  char.ema = Ema(100, 10, 20, 300)
  char.prior = { xph = 2000, at = 1 }
  char.cur = { t0 = 1, s = { w = 400 }, xp = 10 }
  char.sessions = { { t0 = 0, s = { w = 5 }, xp = 0 } }
  local db = { cities = {}, xpMax = {}, chars = { [char.guid] = char } }
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
  local sync = { valid = true, total = 50500, g = 0, level = 10, levelValid = true, levelPlayed = 500 }
  local ok, err = pcall(function()
    for m = 0, 7 do
      Stats.Sum(char.life, m)
      Stats.Played(char, m, sync, 5)
      Stats.LevelTime(char, 10, m, sync, 5)
      Stats.SessionTime(char.cur, m)
      Stats.AvgPerLevel(char, m, sync, 5)
      Stats.RecentAvg(char, m, 5)
      Stats.Rate(char, m)
      Stats.SessionRate(char.cur, m)
      Stats.LevelRate(char, 9, m)
      Stats.ETA(char, m, 100, 1000, 50, false)
      Stats.TopZones(char.zones, 3, m, {})
      Stats.Continents(char.zones, m, {})
      Stats.LevelHistory(char, m, sync, 5, {})
      Stats.SessionHistory(char, m, {})
      Stats.Account(db, m)
      Stats.AccountLevelAverages(db, m, {})
      Stats.AccountAvgPerLevel(db, m)
      Stats.MaskLabel(m)
    end
    Stats.SumAll(char.life)
    Stats.SumKeys(char.life, ns.C.AFK_KEYS)
    Stats.Tracked(char.life)
    Stats.Breakdown(char.life, {})
    Stats.EtaRestAware(100, 10, 1, 1)
    Stats.IsCityKey(1454, nil)
    Stats.ZoneName(1411, nil)
    Stats.TopCities(char.zones, 3, {})
    Stats.AccountZones(db, {})
    Stats.AccountInstanceTime(db, 1)
    for m = 0, 7 do
      Stats.InstanceTime(char.life, m)
      Stats.TopInstances(char.zones, m, 3, {})
    end
    char.lastKill = { xp = 50, level = 10, at = 1 }
    Stats.KillsToLevel(char, 100, 1000, 50)
    char.killRing = { 40, 50, 60 }        -- round 5: the average of the last kills
    Stats.KillsToLevel(char, 100, 1000, 50)
    Stats.ResetCaches()
  end)
  setmetatable(ns, oldMeta)
  T.ok(ok, err)
  T.eq(#touched, 0, touched[1])
end)

T.test("non-alloc Stats functions allocate nothing", function()
  local ns, Stats = Load()
  local char = HistoryChar()
  char.life = FixedBucket()
  char.ema = Ema(100, 10, 20, 700)
  local session = { s = { w = 400, W = 20 }, xp = 10 }
  local db = { cities = {}, xpMax = {}, chars = { A = char } }
  ns.db = db
  local sync = { valid = true, total = 50500, g = 0, level = 10, levelValid = true, levelPlayed = 500 }
  local out = {}
  local AFK = ns.C.AFK_KEYS
  -- round 5: a full ring of the last kills (their average is the base)
  local ringChar = { lastKill = { xp = 330, level = 10, at = 1 },
                     killRing = { 300, 310, 290, 305, 315, 320, 280, 300, 312, 330 } }
  local function Work(i)
    local m = i % 8
    Stats.Sum(char.life, m)
    Stats.SumAll(char.life)
    Stats.SumKeys(char.life, AFK)
    Stats.Tracked(char.life)
    Stats.Breakdown(char.life, out)
    Stats.Played(char, m, sync, i)
    Stats.LevelTime(char, 10, m, sync, i)
    Stats.SessionTime(session, m)
    Stats.AvgPerLevel(char, m, sync, i)
    Stats.RecentAvg(char, m, 5)
    Stats.Rate(char, m)
    Stats.SessionRate(session, m)
    Stats.LevelRate(char, 9, m)
    Stats.EtaRestAware(1000, 100, 1, 1)
    Stats.ETA(char, m, 100, 1000, 50, false)
    Stats.IsCityKey(1454, nil)
    Stats.ZoneName(1411, nil)
    Stats.ZoneName("nDurotar", nil)
    Stats.Account(db, m)
    Stats.AccountAvgPerLevel(db, m)
    Stats.MaskLabel(m)
    Stats.InstanceTime(char.life, m)
    Stats.KillsToLevel(char, 100 + i, 23200, (i % 3) * 700)
    Stats.KillsToLevel(ringChar, 100 + i, 23200, (i % 3) * 700)
    Stats.AccountInstanceTime(db, m)
  end
  char.lastKill = { xp = 312, level = 10, at = 1 }
  char.life.s.d, char.life.s.R, char.life.s.P = 50, 60, 70
  for i = 1, 16 do Work(i) end          -- warm the caches (names, labels)
  -- T.alloc measure, with one unmeasured call after the full collect (the collect
  -- shrinks the Lua stack; its re-growth is not garbage)
  collectgarbage("collect")
  Work(17)
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, 1000 do Work(i) end
  local kb = collectgarbage("count") - before
  collectgarbage("restart")
  T.ok(kb < 0.5, format("allocated %.3f KB", kb))
end)

---------------------------------------------------------------------------
-- Pre-install estimate (char.prior, feedback F1 / requirement C)
---------------------------------------------------------------------------

-- A record with only the prior: 3600 XP/h = 1 XP per second.
local function PriorChar(ema, level)
  return { level = 10, prior = { xph = 3600, at = 1 }, ema = ema or Ema(0, 0, 0, 0),
           levels = { [10] = level or { s = { w = 10, u = 9000 }, xp = 0, xa = 0, xr = 0, xq = 0 } } }
end

T.test("Rate: the prior alone when nothing is tracked yet, for every mask", function()
  local ns, Stats = Load()
  local C = ns.C
  local char = PriorChar(Ema(0, 0, 0, 90))
  for m = 0, 7 do
    local xph, A, R, Q, src, status, left = Stats.Rate(char, m)
    T.near(xph, 3600, 1e-9, "mask " .. m)
    T.near(A, 1, 1e-12); T.eq(R, 0); T.eq(Q, 0)
    T.eq(src, "prior"); T.eq(status, "estimate")
    T.eq(left, C.WARMUP_FULL - 90)
  end
  -- XP-less tracked time never pulls the prior down (no XP = no evidence yet)
  char.ema = Ema(0, 0, 0, 900)
  T.near((Stats.Rate(char, 0)), 3600, 1e-9)
  T.eq(select(7, Stats.Rate(char, 0)), 0)
  -- ETA from the prior: status passed through
  local sec, status, src = Stats.ETA(char, 3, 400, 1000, 0, false)
  T.near(sec, 600, 1e-9); T.eq(status, "estimate"); T.eq(src, "prior")
  -- without a prior: unchanged behaviour
  char.prior = nil
  T.eq(select(6, Stats.Rate(char, 0)), "nodata")
  -- bad priors are ignored
  for _, bad in ipairs({ { xph = 0 }, { xph = -5 }, { xph = 0 / 0 }, { xph = "9" }, "x", {} }) do
    char.prior = bad
    T.eq(select(6, Stats.Rate(char, 0)), "nodata", T.repr(bad))
  end
end)

T.test("Rate: the prior blends with a short EMA and a short level, then fades out", function()
  local ns, Stats = Load()
  local C = ns.C
  local W, FULL = C.PRIOR_WEIGHT, C.WARMUP_FULL
  -- EMA of 300 s at 2 XP/s (a 400, r 100, q 100): prior weight W * (1 - 300 / FULL)
  local char = PriorChar(Ema(400, 100, 100, 300))
  local w = W * (1 - 300 / FULL)
  local xph, A, R, Q, src, status, left = Stats.Rate(char, 0)
  T.near(xph, 3600 * (600 + w) / (300 + w), 1e-9)
  T.near(A, (400 + w) / (300 + w), 1e-12, "the prior goes to A")
  T.near(R, 100 / (300 + w), 1e-12)
  T.near(Q, 100 / (300 + w), 1e-12)
  T.eq(src, "prior"); T.eq(status, "estimate"); T.eq(left, FULL - 300)
  -- with a prior the provisional EMA is used from its first second (no WARMUP_MIN gap)
  char.ema = Ema(10, 0, 0, 5)
  xph, _, _, _, _, status = Stats.Rate(char, 0)
  w = W * (1 - 5 / FULL)
  T.near(xph, 3600 * (10 + w) / (5 + w), 1e-9); T.eq(status, "estimate")
  -- settled EMA: the prior is ignored
  char.ema = Ema(1200, 0, 0, FULL)
  xph, _, _, _, src, status = Stats.Rate(char, 0)
  T.near(xph, 7200, 1e-9); T.eq(src, "ema"); T.eq(status, "ok")
  -- current level of 450 tracked s (1350 XP): blended; 600 s and more: the level alone
  char.ema = Ema(0, 0, 0, 0)
  char.levels[10] = { s = { w = 450, u = 50 }, xp = 1350, xa = 1350, xr = 0, xq = 0 }
  w = W * (1 - 450 / FULL)
  xph, _, _, _, src, status, left = Stats.Rate(char, 0)
  T.near(xph, 3600 * (1350 + w) / (450 + w), 1e-9)
  T.eq(src, "prior"); T.eq(status, "estimate"); T.eq(left, FULL - 450)
  char.levels[10] = { s = { w = FULL }, xp = 3 * FULL, xa = 3 * FULL, xr = 0, xq = 0 }
  xph, _, _, _, src, status, left = Stats.Rate(char, 0)
  T.near(xph, 10800, 1e-9); T.eq(src, "level"); T.eq(status, "ok"); T.eq(left, 0)
  -- recent levels long enough: unchanged by the prior
  char.levels[10] = { s = { w = 100 }, xp = 50, xa = 50, xr = 0, xq = 0 }
  char.levels[9] = { s = { w = 1000 }, xp = 1000, xa = 1000, xr = 0, xq = 0 }
  xph, _, _, _, src, status = Stats.Rate(char, 0)
  T.near(xph, 3600, 1e-9); T.eq(src, "recent"); T.eq(status, "ok")
end)

T.test("Rate: the estimate moves monotonically from the prior to the tracked rate", function()
  local ns, Stats = Load()
  local FULL = ns.C.WARMUP_FULL
  for _, r in ipairs({ 2, 0.25 }) do          -- tracked rate above, then below the prior (1 XP/s)
    local char = PriorChar()
    local prev
    for T0 = 1, FULL + 10 do
      char.ema = Ema(r * T0, 0, 0, T0)       -- a sample of T0 s at r XP/s
      local v, _, _, _, _, status = Stats.Rate(char, 0)
      T.ok(v ~= nil)
      if prev then
        if r > 1 then T.ok(v >= prev - 1e-9, ("r %s, T %d"):format(r, T0))
        else T.ok(v <= prev + 1e-9, ("r %s, T %d"):format(r, T0)) end
      end
      prev = v
      if T0 >= FULL then T.eq(status, "ok") else T.eq(status, "estimate") end
    end
    T.near(prev, 3600 * r, 1e-9, "the tracked rate exactly, once settled")
  end
end)

T.test("Rate with a prior allocates nothing", function()
  local _, Stats = Load()
  local chars = { PriorChar(), PriorChar(Ema(400, 100, 100, 300)),
                  PriorChar(nil, { s = { w = 450 }, xp = 1350, xa = 1350, xr = 0, xq = 0 }) }
  local function Work(i)
    local ch = chars[i % 3 + 1]
    Stats.Rate(ch, i % 8)
    Stats.ETA(ch, i % 8, 100, 1000, 50, false)
  end
  for i = 1, 16 do Work(i) end
  collectgarbage("collect")
  Work(17)
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, 1000 do Work(i) end
  local kb = collectgarbage("count") - before
  collectgarbage("restart")
  T.ok(kb < 0.5, format("allocated %.3f KB", kb))
end)

---------------------------------------------------------------------------
-- Continents (feedback F5)
---------------------------------------------------------------------------

local function ContinentZones()
  return {
    [1411] = { s = { w = 1000, W = 200 }, xp = 0 },        -- Durotar (Kalimdor)
    [1454] = { s = { c = 300, C = 100 }, xp = 0 },         -- Orgrimmar (Kalimdor)
    [90001] = { s = { w = 100 }, xp = 0 },                 -- Ragefire Chasm map (under Orgrimmar)
    [1414] = { s = { i = 2 }, xp = 0 },                    -- a continent key of an old record
    [1453] = { s = { c = 500 }, xp = 0 },                  -- Stormwind City (Eastern Kingdoms)
    [1458] = { s = { w = 400, C = 50 }, xp = 0 },          -- Undercity (Eastern Kingdoms)
    i389 = { s = { w = 300, W = 10 }, xp = 0 },            -- instance without a map
    i777 = { s = { w = 20 }, xp = 0 },
    nZephras = { s = { w = 7 }, xp = 0 },                  -- zone-text key
    o = { s = { w = 3 }, xp = 0 },                         -- neutral bucket
    [987654] = { s = { w = 11 }, xp = 0 },                 -- unknown map
    [2521] = { s = { w = 5 }, xp = 0 },                    -- continent-typed island under Azeroth
    [1446] = { s = { W = 60 }, xp = 0 },                   -- only AFK time (Tanaris)
  }
end

T.test("Continents: Kalimdor, Eastern Kingdoms, instances; time without a continent left out; sorted; mask applied", function()
  local ns, Stats = Load()
  local L = ns.L
  local zones = ContinentZones()
  local out = {}
  local n = Stats.Continents(zones, 0, out)
  T.eq(n, 4)
  T.eq(#out, 4)
  T.eq(out[1].key, 1414); T.eq(out[1].name, "Kalimdor"); T.eq(out[1].secs, 1200 + 400 + 100 + 2 + 60)
  T.eq(out[2].key, 1415); T.eq(out[2].name, "Eastern Kingdoms"); T.eq(out[2].secs, 500 + 450)
  T.eq(out[3].key, "dungeon"); T.eq(out[3].name, L.BD_DUNGEON); T.eq(out[3].secs, 330)
  T.eq(out[4].key, 2521); T.eq(out[4].name, "Zephras", "a continent-typed key is its own continent")
  T.eq(out[4].secs, 5)
  local sum = 0
  for i = 1, n do sum = sum + out[i].secs end
  local all = 0
  for _, z in pairs(zones) do all = all + Stats.SumAll(z) end
  T.eq(sum, all - (7 + 3 + 11), "every second in one row, but the zone-text key, the neutral bucket and the unknown map")
  -- AFK and city excluded (mask 5): Tanaris (AFK only) gives nothing, the order changes
  n = Stats.Continents(zones, 5, out)
  T.eq(n, 4)
  T.eq(out[1].key, 1414); T.eq(out[1].secs, 1000 + 100 + 2)
  T.eq(out[2].key, 1415); T.eq(out[2].secs, 400)
  T.eq(out[3].key, "dungeon"); T.eq(out[3].secs, 320)
  T.eq(out[4].key, 2521); T.eq(out[4].secs, 5)
  -- ties: numeric keys first
  n = Stats.Continents({ i1 = { s = { w = 5 } }, [1411] = { s = { w = 5 } }, o = { s = { w = 5 } } }, 0, out)
  T.eq(n, 2); T.eq(out[1].key, 1414); T.eq(out[2].key, "dungeon")
  -- nothing but time without a continent: no row
  T.eq(Stats.Continents({ o = { s = { w = 5 } }, nZephras = { s = { w = 9 } } }, 0, out), 0); T.eq(#out, 0)
  -- only rows with time; rows dropped from out
  n = Stats.Continents({ i1 = { s = { w = 5 } }, [1411] = { s = { W = 9 } } }, 1, out)
  T.eq(n, 1); T.eq(#out, 1); T.eq(out[1].key, "dungeon")
  T.eq(Stats.Continents(nil, 0, out), 0); T.eq(#out, 0)
  T.eq(Stats.Continents({}, 0, out), 0)
  -- an account zone map works too
  local db = { chars = { a = { zones = { [1411] = { s = { w = 10 } } } }, b = { zones = { [1453] = { s = { w = 20 } } } } } }
  n = Stats.Continents(Stats.AccountZones(db, {}), 0, out)
  T.eq(n, 2); T.eq(out[1].key, 1415); T.eq(out[2].key, 1414)
  -- French names come from the locale
  Stub.locale = "frFR"
  local ns2, Stats2 = Load()
  Stats2.Continents(ContinentZones(), 0, out)
  T.eq(out[3].name, ns2.L.BD_DUNGEON)
end)

T.test("Continents: dungeons, raids and PvP apart, named like the breakdown", function()
  local ns, Stats = Load()
  local L = ns.L
  local zones = {
    [1411] = { s = { w = 5000 }, xp = 0 },                          -- Kalimdor
    [1458] = { s = { c = 2222, d = 1 }, xp = 0 },                   -- Undercity, a tick of dungeon
    i2999 = { s = { d = 2700, w = 1 }, xp = 0 },                    -- a dungeon
    i389 = { s = { d = 1700, D = 100 }, xp = 0 },                   -- another dungeon
    [90001] = { s = { d = 500, w = 10 }, xp = 0 },                  -- a dungeon map (under Orgrimmar)
    i409 = { s = { r = 3000, R = 200, x = 60 }, xp = 0 },           -- a raid (dead time too)
    i30 = { s = { p = 900, P = 100 }, xp = 0 },                     -- a battleground instance
    [987654] = { s = { p = 400 }, xp = 0, name = "A battleground" }, -- a battleground map
    i489 = { s = { p = 10, d = 20 }, xp = 0 },                      -- mixed: its main kind
  }
  local out = {}
  local function Row(key)
    for i = 1, #out do if out[i].key == key then return out[i] end end
  end
  local n = Stats.Continents(zones, 0, out)
  T.eq(n, 5)
  T.eq(Row(1414).secs, 5000, "Kalimdor: the dungeon map is not in it")
  T.eq(Row(1415).secs, 2223, "Eastern Kingdoms: Undercity stays in it")
  T.eq(Row("dungeon").name, L.BD_DUNGEON); T.eq(Row("dungeon").secs, 2701 + 1800 + 510 + 30)
  T.eq(Row("raid").name, L.BD_RAID); T.eq(Row("raid").secs, 3260)
  T.eq(Row("pvp").name, L.BD_PVP); T.eq(Row("pvp").secs, 1000 + 400)
  T.eq(out[1].key, "dungeon", "sorted by time")
  -- AFK excluded
  Stats.Continents(zones, 1, out)
  T.eq(Row("dungeon").secs, 2701 + 1700 + 510 + 30); T.eq(Row("raid").secs, 3060); T.eq(Row("pvp").secs, 1300)
  -- French names
  Stub.locale = "frFR"
  local _, Stats2 = Load()
  Stats2.Continents(zones, 0, out)
  T.eq(Row("dungeon").name, "Donjons"); T.eq(Row("raid").name, "Raids"); T.eq(Row("pvp").name, "JcJ")
end)

T.test("Continents: C_Map once per zone key, rows reused, no garbage across calls", function()
  local calls = 0
  local orig = C_Map.GetMapInfo
  C_Map.GetMapInfo = function(id)
    calls = calls + 1
    return orig(id)
  end
  local _, Stats = Load()
  local zones = ContinentZones()
  local out = {}
  Stats.Continents(zones, 0, out)
  local first = calls
  T.ok(first > 0)
  local row1 = out[1]
  for m = 0, 7 do Stats.Continents(zones, m, out) end
  T.eq(calls, first, "no C_Map call on a cache hit (names included)")
  local recycled = false
  for i = 1, #out do if rawequal(out[i], row1) then recycled = true end end
  T.ok(recycled, "row tables recycled")
  local small = { [1411] = { s = { w = 10 } } }
  local function Work(i)
    Stats.Continents((i % 2 == 0) and zones or small, i % 8, out)
  end
  for i = 1, 16 do Work(i) end
  collectgarbage("collect")
  Work(17)
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, 1000 do Work(i) end
  local kb = collectgarbage("count") - before
  collectgarbage("restart")
  T.ok(kb < 0.5, format("allocated %.3f KB over 1000 calls", kb))
  Stats.ResetCaches()
  Stats.Continents(zones, 0, out)
  T.ok(calls > first, "ResetCaches clears the continent cache")
  C_Map.GetMapInfo = orig
end)

---------------------------------------------------------------------------
-- Instance time (request A): dungeons, raids, PvP
---------------------------------------------------------------------------

-- FixedBucket plus instance seconds: d 700, D 30, r 900, R 50, p 400, P 20 (= 2100).
local function InstBucket()
  local b = FixedBucket()
  b.s.d, b.s.D, b.s.r, b.s.R, b.s.p, b.s.P = 700, 30, 900, 50, 400, 20
  return b
end

T.test("Breakdown: open world, dungeon, raid and PvP fields; the partition still sums to tracked", function()
  local _, Stats = Load()
  local out = Stats.Breakdown(InstBucket(), {})
  T.eq(out.world, 1000)
  T.eq(out.dungeon, 700); T.eq(out.dungeonAll, 730); T.eq(out.dungeonAfk, 30)
  T.eq(out.raid, 900); T.eq(out.raidAll, 950); T.eq(out.raidAfk, 50)
  T.eq(out.pvp, 400); T.eq(out.pvpAll, 420); T.eq(out.pvpAfk, 20)
  T.eq(out.instAll, 2100)
  T.eq(out.active, 1000 + 700 + 900 + 400 + 70, "w + d + r + p + t")
  T.eq(out.afk, 200 + 30 + 50 + 20 + 40 + 60 + 8, "W + D + R + P + I + C + T")
  T.eq(out.inn, 300); T.eq(out.city, 500); T.eq(out.taxi, 78)
  T.eq(out.total, 11178 + 2100)
  T.eq(out.tracked, 2178 + 2100)
  T.eq(out.active + out.afk + out.inn + out.city, out.tracked)
  -- a bucket without instance keys: zeros, and the old fields unchanged
  local old = Stats.Breakdown(FixedBucket(), out)
  T.eq(old.instAll, 0); T.eq(old.dungeonAll, 0); T.eq(old.raid, 0); T.eq(old.pvpAfk, 0)
  T.eq(old.world, 1000); T.eq(old.active, 1070); T.eq(old.afk, 308)
  Stats.Breakdown(nil, out)
  T.eq(out.instAll, 0); T.eq(out.world, 0)
end)

T.test("Sum and InstanceTime over the 8 masks: instance AFK keys follow the AFK exclusion only", function()
  local ns, Stats = Load()
  local b = InstBucket()
  local base = { [0] = 11178, [1] = 10870, [2] = 10838, [3] = 10570,
                 [4] = 10618, [5] = 10370, [6] = 10278, [7] = 10070 }
  for m = 0, 7 do
    local afk = m % 2 == 1
    T.eq(Stats.Sum(b, m), base[m] + (afk and 2000 or 2100), format("Sum mask %d", m))
    T.eq(Stats.InstanceTime(b, m), afk and 2000 or 2100, format("InstanceTime mask %d", m))
  end
  T.eq(Stats.SumAll(b), 13278)
  T.eq(Stats.SumKeys(b, ns.C.AFK_KEYS), 408)
  T.eq(Stats.SumKeys(b, ns.C.DUNGEON_KEYS), 730)
  T.eq(Stats.SumKeys(b, ns.C.RAID_KEYS), 950)
  T.eq(Stats.SumKeys(b, ns.C.PVP_KEYS), 420)
  T.eq(Stats.InstanceTime(nil, 0), 0)
  T.eq(Stats.InstanceTime({}, 0), 0)
  T.eq(Stats.InstanceTime({ s = { w = 5 } }, nil), 0)
end)

T.test("TopInstances: most played instances with their kind, mask applied, rows reused", function()
  local ns, Stats = Load()
  local zones = {
    [90001] = { s = { d = 3000, D = 600, w = 50 }, xp = 0 },            -- Ragefire Chasm
    i409 = { s = { r = 7200, R = 100 }, xp = 0, name = "Molten Core" },
    i30 = { s = { p = 1800, P = 1500 }, xp = 0, name = "Alterac Valley" },
    i489 = { s = { p = 900, d = 950 }, xp = 0, name = "Mixed" },         -- dungeon wins the kind
    [1411] = { s = { w = 90000 }, xp = 0 },                             -- open world: never listed
    [1454] = { s = { c = 5000 }, xp = 0 },
    o = { s = { d = 99999 }, xp = 0 },                                  -- merged bucket: never listed
    i777 = { s = { D = 400 }, xp = 0, name = "AFK only" },
  }
  local out = {}
  local n = Stats.TopInstances(zones, 0, 10, out)
  T.eq(n, 5); T.eq(#out, 5)
  T.eq(out[1].key, "i409"); T.eq(out[1].secs, 7300); T.eq(out[1].kind, "r"); T.eq(out[1].name, "Molten Core")
  T.eq(out[2].key, 90001); T.eq(out[2].secs, 3600); T.eq(out[2].kind, "d"); T.eq(out[2].name, "Ragefire Chasm")
  T.eq(out[3].key, "i30"); T.eq(out[3].secs, 3300); T.eq(out[3].kind, "p")
  T.eq(out[4].key, "i489"); T.eq(out[4].secs, 1850); T.eq(out[4].kind, "d")
  T.eq(out[5].key, "i777"); T.eq(out[5].secs, 400); T.eq(out[5].kind, "d")
  -- AFK excluded: the AFK-only instance disappears, the others lose their AFK part
  local rows = {}
  for i = 1, 5 do rows[i] = out[i] end
  n = Stats.TopInstances(zones, 1, 10, out)
  T.eq(n, 4); T.eq(#out, 4)
  T.eq(out[1].secs, 7200); T.eq(out[2].key, 90001); T.eq(out[2].secs, 3000)
  T.eq(out[3].key, "i489"); T.eq(out[3].secs, 1850)
  T.eq(out[4].key, "i30"); T.eq(out[4].secs, 1800, "1500 s of AFK removed")
  for i = 1, 4 do
    local same = false
    for j = 1, 5 do if rawequal(out[i], rows[j]) then same = true end end
    T.ok(same, "row tables reused " .. i)
  end
  -- top 2 only; empty inputs
  T.eq(Stats.TopInstances(zones, 0, 2, out), 2)
  T.eq(#out, 2); T.eq(out[1].key, "i409"); T.eq(out[2].key, 90001)
  T.eq(Stats.TopInstances(nil, 0, 5, out), 0); T.eq(#out, 0)
  T.eq(Stats.TopInstances({}, 0, 5, out), 0)
  T.eq(Stats.TopInstances(zones, 0, 5, nil), 0, "no output table: nothing")
  -- the account view: AccountZones merges the same instance across characters
  local db = { chars = { A = { zones = { i409 = { s = { r = 100 }, xp = 0, name = "Molten Core" } } },
                         B = { zones = { i409 = { s = { r = 50, R = 10 }, xp = 0 } } } } }
  ns.db = db
  local acc = Stats.AccountZones(db, {})
  T.eq(Stats.TopInstances(acc, 0, 5, out), 1)
  T.eq(out[1].secs, 160); T.eq(out[1].kind, "r"); T.eq(out[1].name, "Molten Core")
end)

T.test("TopInstances: repeated calls allocate nothing once warm", function()
  local _, Stats = Load()
  local zones = {}
  for i = 1, 12 do zones["i" .. i] = { s = { d = i * 10, R = i }, xp = 0, name = "Instance " .. i } end
  zones[1411] = { s = { w = 500 }, xp = 0 }
  local out = {}
  for m = 0, 7 do Stats.TopInstances(zones, m, 5, out) end
  Stats.TopInstances(zones, 0, 2, out)       -- shrink: surplus rows kept aside
  Stats.TopInstances(zones, 0, 5, out)       -- grow again from the spare rows
  collectgarbage("collect")
  Stats.TopInstances(zones, 3, 5, out)
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, 200 do
    Stats.TopInstances(zones, i % 8, (i % 2 == 0) and 5 or 2, out)
  end
  local kb = collectgarbage("count") - before
  collectgarbage("restart")
  T.ok(kb < 0.5, format("allocated %.3f KB", kb))
  T.eq(#out, 5)
  T.eq(out[1].key, "i12")
end)

T.test("TopInstances: an open-world zone or a capital with a tick of instance time is not an instance", function()
  local _, Stats = Load()
  local zones = {
    [1458] = { s = { c = 2222, d = 1 }, xp = 21922 },     -- Undercity: zoning into an instance below it
    [1413] = { s = { w = 5000, D = 2 }, xp = 0 },         -- the Barrens: the same, AFK
    [90001] = { s = { w = 3000, d = 10 }, xp = 0 },       -- a dungeon map (old records counted w): listed
    [987654] = { s = { p = 600, w = 100 }, xp = 0, name = "A battleground" },   -- mostly PvP: listed
    [987655] = { s = { p = 50, w = 100 }, xp = 0, name = "Not one" },           -- mostly world: not
    i2999 = { s = { d = 3 }, xp = 0, name = "Ruins" },    -- an instance key: always an instance
  }
  local out = {}
  local n = Stats.TopInstances(zones, 0, 10, out)
  local keys = {}
  for i = 1, n do keys[#keys + 1] = out[i].key end
  T.eq(keys, { 987654, 90001, "i2999" })
end)

T.test("ZoneName: an instance is named in the client's language, else as recorded", function()
  local _, Stats = Load()
  Stub.player.instanceNames[2999] = "Ruins of Lordaeron"
  T.eq(Stats.ZoneName("i2999", { name = "Ruines de Lordaeron" }), "Ruins of Lordaeron", "client language first")
  T.eq(Stats.ZoneName("i2999", nil), "Ruins of Lordaeron", "cached")
  T.eq(Stats.ZoneName("i389", { name = "Gouffre de Ragefeu" }), "Gouffre de Ragefeu", "unknown to the client: recorded")
  T.eq(Stats.ZoneName("i0", { name = "Somewhere" }), "Somewhere", "no instance ID")
  T.eq(Stats.ZoneName("nAshenvale", { name = "Orneval" }), "Orneval", "a zone-text key keeps its recorded name")
  T.eq(Stats.ZoneName("nAshenvale", nil), "Ashenvale")
  -- a client that ignores the argument answers the current zone: not an instance name
  local _, Stats2 = Load()
  Stub.player.zoneTextIgnoresArg = true
  Stub.player.zoneText = "Durotar"
  T.eq(Stats2.ZoneName("i43", { name = "Wailing Caverns" }), "Wailing Caverns")
  -- ... unless we are in that instance (its name is the current zone text)
  Stub.player.instanceID = 389
  Stub.player.zoneText = "Ragefire Chasm"
  T.eq(Stats2.ZoneName("i389", { name = "Gouffre de Ragefeu" }), "Ragefire Chasm")
end)

T.test("AccountInstanceTime sums every record's instance time under the mask, and history rows carry it", function()
  local _, Stats = Load()
  local a = { life = InstBucket() }                  -- d 700, D 30, r 900, R 50, p 400, P 20
  local b = { life = { s = { w = 100, r = 40, R = 5, u = 10 } } }
  local db = { chars = { A = a, B = b, C = "junk", D = { life = "x" }, E = {} } }
  T.eq(Stats.AccountInstanceTime(db, 0), 2145)
  T.eq(Stats.AccountInstanceTime(db, 1), 2040, "AFK excluded: D, R, P left out")
  T.eq(Stats.AccountInstanceTime(db, 6), 2145, "inn and city never apply inside instances")
  T.eq(Stats.AccountInstanceTime(db, 7), 2040)
  T.eq(Stats.AccountInstanceTime(nil, 0), 0)
  T.eq(Stats.AccountInstanceTime({ chars = {} }, 0), 0)
  -- level and session rows
  local char = HistoryChar()
  char.levels[10].s.d, char.levels[10].s.D = 30, 5
  char.cur = { t0 = 1, s = { w = 10, p = 20, P = 4 }, xp = 0 }
  local rows = Stats.LevelHistory(char, 1, nil, 10, {})
  T.eq(rows[1].inst, 30, "AFK excluded")
  T.eq(rows[2].inst, 0)
  local srows = Stats.SessionHistory(char, 0, {})
  T.eq(srows[1].inst, 24)
end)

---------------------------------------------------------------------------
-- Mobs to the next level (request E)
---------------------------------------------------------------------------

T.test("KillsToLevel: not rested, from the last kill's base XP", function()
  local _, Stats = Load()
  local char = { level = 20, lastKill = { xp = 312, level = 20, at = 1 } }
  local n, base = Stats.KillsToLevel(char, 58, 23200, 0)
  T.eq(base, 312)
  T.eq(n, 75, "ceil(23142 / 312) = 75")
  T.eq((Stats.KillsToLevel(char, 23200 - 312, 23200, 0)), 1, "exactly one kill")
  T.eq((Stats.KillsToLevel(char, 23200 - 313, 23200, nil)), 2, "one XP short")
  T.eq((Stats.KillsToLevel(char, 23200, 23200, 0)), 0, "already there")
  T.eq((Stats.KillsToLevel(char, 58, 23200, -5)), 75, "a negative pool counts as none")
end)

T.test("KillsToLevel: rested kills give double XP until the pool is drained", function()
  local ns, Stats = Load()
  T.eq(ns.C.REST_BONUS, 1.0); T.eq(ns.C.REST_DRAIN, 2.0)
  local char = { lastKill = { xp = 100 } }
  -- the pool covers everything: 2000 XP to go, 200 per kill, pool 5000 >= 10 * 200
  T.eq((Stats.KillsToLevel(char, 0, 2000, 5000)), 10)
  T.eq((Stats.KillsToLevel(char, 0, 2050, 5000)), 11, "the last kill partly used")
  -- pool of 600: 3 rested kills (600 XP), then 1400 XP at 100 per kill = 14
  T.eq((Stats.KillsToLevel(char, 0, 2000, 600)), 17)
  -- pool of 650: 3 rested kills, a 4th with 25 bonus (125 XP), then 1275 / 100 -> 13
  T.eq((Stats.KillsToLevel(char, 0, 2000, 650)), 17)
  T.eq((Stats.KillsToLevel(char, 0, 2000, 750)), 17, "600 + 175 + 1225 / 100 -> 3 + 1 + 13")
  -- the partial kill alone finishes the level
  T.eq((Stats.KillsToLevel(char, 0, 650, 650)), 4, "600 + 125 >= 650")
  -- the same as a simulation, kill by kill, for many cases
  local function Sim(xp, max, E, base)
    local n = 0
    while xp < max do
      local d = E < 2 * base and E or 2 * base
      E = E - d
      xp = xp + base + d / 2
      n = n + 1
    end
    return n
  end
  for _, c in ipairs({ { 0, 23200, 0, 312 }, { 58, 23200, 23200, 312 }, { 500, 23200, 4000, 312 },
                       { 0, 7600, 333, 45 }, { 7000, 7600, 90, 45 }, { 0, 400, 1, 1 },
                       { 100, 209800, 150000, 1450 } }) do
    local n = Stats.KillsToLevel({ lastKill = { xp = c[4] } }, c[1], c[2], c[3])
    T.eq(n, Sim(c[1], c[2], c[3], c[4]), format("xp %d max %d pool %d base %d", c[1], c[2], c[3], c[4]))
  end
end)

T.test("KillsToLevel: nil without a last kill, at max level, without valid XP values", function()
  local _, Stats = Load()
  local char = { lastKill = { xp = 100 } }
  T.eq(Stats.KillsToLevel(nil, 0, 1000, 0), nil)
  T.eq(Stats.KillsToLevel({}, 0, 1000, 0), nil, "no kill yet")
  T.eq(Stats.KillsToLevel({ lastKill = { xp = 0 } }, 0, 1000, 0), nil)
  T.eq(Stats.KillsToLevel({ lastKill = { xp = 0 / 0 } }, 0, 1000, 0), nil)
  T.eq(Stats.KillsToLevel({ lastKill = "x" }, 0, 1000, 0), nil)
  T.eq(Stats.KillsToLevel(char, 0, 1000, 0, true), nil, "max level")
  Stub.player.xpDisabled = true
  T.eq(Stats.KillsToLevel(char, 0, 1000, 0), nil, "XP gain disabled")
  Stub.player.xpDisabled = false
  local n, base = Stats.KillsToLevel(char, nil, 1000, 0)
  T.eq(n, nil); T.eq(base, 100)
  n, base = Stats.KillsToLevel(char, 0, 0, 0)
  T.eq(n, nil); T.eq(base, 100)
end)

---------------------------------------------------------------------------
-- Round 3: time without XP (C1) - "stalled" status and stalled time (xs)
---------------------------------------------------------------------------

T.test("Rate: a stalled character keeps its rate with status 'stalled' and the seconds without XP", function()
  local ns, Stats = Load()
  local C = ns.C
  local char = { level = 10, ema = Ema(1200, 300, 300, 3600), levels = {} }
  local xph, A, R, Q, src, status, left, secs = Stats.Rate(char, 0)
  T.near(xph, 1800, 1e-9); T.eq(status, "ok"); T.eq(secs, nil, "no 8th return when not stalled")
  char.noXP = C.XP_STALL                      -- the limit itself is not a stall yet
  T.eq(select(6, Stats.Rate(char, 0)), "ok")
  char.noXP = C.XP_STALL + 1
  local xph2, A2, R2, Q2, src2, status2, left2, secs2 = Stats.Rate(char, 3)
  T.eq(xph2, xph, "the frozen value")
  T.eq(A2, A); T.eq(R2, R); T.eq(Q2, Q); T.eq(src2, src); T.eq(left2, left)
  T.eq(status2, "stalled"); T.eq(secs2, C.XP_STALL + 1)
  -- every source can be stalled (here the pre-install estimate) ...
  char.ema = Ema(0, 0, 0, 0)
  char.prior = { xph = 3600, at = 1 }
  local v, _, _, _, s3, st3, _, n3 = Stats.Rate(char, 0)
  T.near(v, 3600, 1e-9); T.eq(s3, "prior"); T.eq(st3, "stalled"); T.eq(n3, C.XP_STALL + 1)
  -- ... but "nodata" stays "nodata"
  char.prior = nil
  T.eq(select(6, Stats.Rate(char, 0)), "nodata")
  -- ETA: the status and the seconds passed through
  char.ema = Ema(1200, 300, 300, 3600)
  local sec, estatus, esrc, eleft, stall = Stats.ETA(char, 0, 100, 1000, 0, false)
  T.near(sec, 900 / (1500 / 3600), 1e-6)
  T.eq(estatus, "stalled"); T.eq(esrc, "ema"); T.eq(eleft, 0); T.eq(stall, C.XP_STALL + 1)
  T.eq(select(2, Stats.ETA(char, 0, 100, 1000, 0, true)), "max", "max level wins")
  -- a bad noXP is ignored
  char.noXP = "x"
  T.eq(select(6, Stats.Rate(char, 0)), "ok")
end)

T.test("Rate fallbacks and level rates leave out stalled time (levels[L].xs), under every mask", function()
  local _, Stats = Load()
  -- level 10: 1000 s of play for 3000 XP, then 2 days capped (w, W, c) held in xs
  local days = 2 * 86400
  local lb = { s = { w = 1000 + days, W = 3600, c = 7200, u = 500 }, xp = 3000, xa = 3000, xr = 0, xq = 0,
               xs = { w = days, W = 3600, c = 7200 } }
  local char = { level = 10, ema = Ema(0, 0, 0, 0), levels = { [10] = lb } }
  for m = 0, 7 do
    local xph, _, _, _, src, status = Stats.Rate(char, m)
    T.near(xph, 3600 * 3000 / 1000, 1e-9, "level rate, mask " .. m)
    T.eq(src, "level"); T.eq(status, "ok")
    T.near(Stats.LevelRate(char, 10, m), 10800, 1e-9, "LevelRate, mask " .. m)
  end
  T.eq(Stats.StallTime(lb, 0), days + 3600 + 7200)
  T.eq(Stats.StallTime(lb, 7), days, "the mask applies to the stalled time too")
  T.eq(Stats.StallTime({ s = {} }, 0), 0)
  -- without xs the same record gives an absurd rate (what R1 forbids)
  lb.xs = nil
  T.ok(Stats.Rate(char, 0) < 200)
  lb.xs = { w = days, W = 3600, c = 7200 }
  -- a level whose rate time is all stalled is skipped: recent levels
  char.levels[10] = { s = { w = days }, xp = 0, xa = 0, xr = 0, xq = 0, xs = { w = days } }
  char.levels[9] = { s = { w = 2000 + 3600 }, xp = 4000, xa = 3000, xr = 0, xq = 1000, xs = { w = 3600 } }
  local xph, _, _, _, src = Stats.Rate(char, 0)
  T.near(xph, 7200, 1e-9); T.eq(src, "recent")
  -- account per-level rates too
  local db = { chars = { a = { level = 10, levels = { [9] = char.levels[9] } } } }
  local rows, n = Stats.AccountLevelAverages(db, 0, {})
  T.eq(n, 1)
  T.near(rows[1].xph, 7200, 1e-9)
  T.eq(rows[1].avg, 5600, "time averages keep the real time spent")
end)

T.test("Rate while stalled allocates nothing", function()
  local ns, Stats = Load()
  local char = { level = 10, ema = Ema(0, 0, 0, 0), noXP = ns.C.XP_STALL + 50,
                 levels = { [10] = { s = { w = 5000 }, xp = 900, xa = 900, xr = 0, xq = 0, xs = { w = 4000 } } } }
  local function Work(i)
    Stats.Rate(char, i % 8)
    Stats.ETA(char, i % 8, 100, 1000, 50, false)
    Stats.LevelRate(char, 10, i % 8)
  end
  for i = 1, 16 do Work(i) end
  local kb = T.alloc(Work, 1000)
  T.ok(kb < 0.5, format("allocated %.3f KB", kb))
end)
