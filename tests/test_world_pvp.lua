-- tests/test_world_pvp.lua - world PvP per level (Pvp.lua, Tracker.AddLevelStat, Core's
-- repair; the Levels tab's data, design/NEXT-LOT.md): open-world time BETWEEN two world PvP
-- signals less than C.PVP_IDLE apart, counted afterwards (wg, the pending wp per level, w0
-- in char.pvp; levels[L].pw and life.pw, record and delta). A signal: honor gained, or
-- today's honorable kills rising (the honor cap; based on the first read above 0 of a load:
-- a 0 read at the login, then the real count, is no signal), out of a battleground or an
-- arena. Only the Tracker's state "w" counts (not a battleground, a flight, AFK, a city,
-- an inn, dead); a lone signal and the tail after the last one count nothing; a level-up
-- splits; the pending seconds survive a /reload; read-only, Classic Era and no API record
-- nothing; ResetChar wipes; a late SavedVariables swap replays pw once; the repair;
-- allocation.
-- Nothing has to show PvP: by default the bar shows no PvP and the cap alert is off.
local Stub, T = ...

local format = string.format

-- Loads the addon with Forever's PvP API (a season running); opts: api, q, max, hk
-- (today's honorable kills at the login: default the stub's 0, which is no base for the
-- kills signal), db, pvp (settings.pvp), widget (settings.widget: default nothing PvP
-- shown). The cap alert is off unless opts.pvp says otherwise.
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false })
  Stub.SetPvpAPI(opts.api or "forever")
  Stub.SetWeek(2, 5, 3, { quiet = true })
  local s = Stub.pvp
  if opts.q then s.q = opts.q end
  if opts.max then s.max = opts.max end
  if opts.hk then s.hkToday = opts.hk end
  rawset(_G, "TruePlayedDB", opts.db or { schema = 1, settings = { firstRunDone = true,
    widget = opts.widget or {}, pvp = opts.pvp or { capAlert = false } } })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, ns.Pvp
end

-- A world PvP signal by honor (out of a battleground).
local function Honor()
  Stub.GainHonor(10)
end

local function Level(ns, l)
  return ns.char.levels[l]
end

---------------------------------------------------------------------------
-- Measure
---------------------------------------------------------------------------

T.test("world pvp: nothing before a first signal; two signals 10 min apart in the open world: 600 s", function()
  local ns = Start()
  local p = ns.char.pvp
  T.eq(ns.C.PVP_IDLE, 900)
  T.eq(type(p.wp), "table", "the pending map made with the record")
  Stub.Advance(600)
  T.eq({ p.wg, next(p.wp) }, { nil, nil }, "no signal: nothing pending")
  Honor()
  T.eq(p.wg, time(), "the window opens")
  Stub.Advance(600)
  T.eq(p.wp[10], 600, "pending at the level")
  T.eq(Level(ns, 10).pw, nil, "not counted before the second signal")
  Honor()
  T.eq(Level(ns, 10).pw, 600)
  T.eq(ns.char.life.pw, 600)
  T.eq(ns.Tracker.GetDelta().levels[10].pw, 600, "in the delta too")
  T.eq(ns.Tracker.GetDelta().life.pw, 600)
  T.eq(ns.session.pw, nil, "never in the session")
  T.eq(next(p.wp), nil, "committed: nothing pending")
  T.eq(p.wg, time(), "the window starts again")
  T.ok(Level(ns, 10).pw <= Level(ns, 10).s.w, "a part of the open-world time")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: signals 20 min apart count nothing; the tail after the last signal never counts", function()
  local ns = Start()
  local p = ns.char.pvp
  Honor()
  Stub.Advance(1200)
  T.eq(next(p.wp), nil, "the window ran out: the pending seconds dropped")
  Honor()
  T.eq(Level(ns, 10).pw, nil, "20 min apart: nothing")
  Stub.Advance(300)
  Honor()
  T.eq(Level(ns, 10).pw, 300, "5 min apart")
  Stub.Advance(600)
  T.eq(p.wp[10], 600, "the tail pending...")
  Stub.Advance(400)
  T.eq(next(p.wp), nil, "...and dropped once the window runs out")
  Honor()
  T.eq(Level(ns, 10).pw, 300, "the tail after the last signal never counted")
  T.eq(ns.char.life.pw, 300)
  -- a frozen client (a segment over C.MAX_SEGMENT is dropped: no Advance) leaves seconds
  -- pending past the window's end: the next signal drops them, it does not commit them
  Stub.Advance(200)
  T.eq(p.wp[10], 200)
  Stub.Advance(1000, 1000)
  T.eq(p.wp[10], 200, "still pending: no tick saw the window run out")
  Honor()
  T.eq(Level(ns, 10).pw, 300, "1200 s after the last signal: dropped")
  T.eq(next(p.wp), nil)
  T.eq(Stub.errors, {})
end)

T.test("world pvp: a segment begun before the signal counts from the signal on", function()
  local ns, P = Start()
  local p = ns.char.pvp
  Honor()
  P.Advance(30, "w", 10)                           -- e.g. 30 s held on an unresolved map
  T.eq(p.wp[10], nil, "its part before the signal does not count")
  Stub.Advance(5)
  T.eq(p.wp[10], 5)
  T.eq(Stub.errors, {})
end)

T.test("world pvp: a battleground, a flight, AFK, a city, an inn, dead: not counted", function()
  local ns = Start()
  Honor()
  Stub.Advance(100)                                -- the open world: counts
  Stub.SetTaxi(true)
  Stub.Advance(60)
  Stub.SetTaxi(false)
  Stub.SetAFK(true)
  Stub.Advance(60)
  Stub.SetAFK(false)
  Stub.SetMap(1454)                                -- Orgrimmar: a city
  Stub.Advance(60)
  Stub.SetMap(1411)
  Stub.SetResting(true)                            -- an inn in Durotar
  Stub.Advance(60)
  Stub.SetResting(false)
  Stub.Die()
  Stub.Advance(60)
  Stub.Resurrect()
  Stub.EnterBG()
  Stub.Advance(60)
  Stub.LeaveBG()
  Stub.SetMap(1411)
  Stub.Advance(100)                                -- the open world again
  local s = Level(ns, 10).s
  T.eq({ s.t, s.W, s.c, s.i, s.x, s.p }, { 60, 60, 60, 60, 60, 60 }, "each state got its minute")
  Honor()                                          -- 560 s after the first signal
  T.eq(Level(ns, 10).pw, 200, "the open-world seconds only")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: a signal inside a battleground neither opens nor extends the window", function()
  local ns = Start()
  local p = ns.char.pvp
  -- honor and kills in a battleground: no window
  Stub.EnterBG()
  Stub.Advance(30)
  Honor()
  Stub.HK(2)
  T.eq(p.wg, nil, "no world signal in a battleground")
  Stub.LeaveBG()
  Stub.SetMap(1411)
  Stub.Advance(300)
  Honor()                                          -- the first world signal
  T.eq(Level(ns, 10).pw, nil, "nothing counted from the battleground's gains")
  local wg = p.wg
  -- an open window: a gain in a battleground does not extend it
  Stub.Advance(600)
  Stub.EnterBG({ arena = true })
  Honor()
  Stub.HK(1)
  T.eq(p.wg, wg, "an arena's gains: the window unchanged")
  Stub.Advance(100)
  Stub.LeaveBG()
  Stub.SetMap(1411)
  Stub.Advance(250)                                -- 950 s after the world signal
  T.eq(next(p.wp), nil, "the window ran out")
  Honor()
  T.eq(Level(ns, 10).pw, nil, "nothing committed")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: a level-up between two signals splits the time between the two levels", function()
  local ns = Start()
  Honor()
  Stub.Advance(200)
  local pl = Stub.player
  Stub.GrantXP(pl.max - pl.xp + 50)                -- level 11
  T.eq(ns.char.level, 11)
  Stub.Advance(300)
  T.eq({ ns.char.pvp.wp[10], ns.char.pvp.wp[11] }, { 200, 300 })
  Honor()
  T.eq(Level(ns, 10).pw, 200)
  T.eq(Level(ns, 11).pw, 300)
  T.eq(ns.char.life.pw, 500)
  local d = ns.Tracker.GetDelta()
  T.eq({ d.levels[10].pw, d.levels[11].pw, d.life.pw }, { 200, 300, 500 })
  T.eq(Stub.errors, {})
end)

T.test("world pvp: at the honor cap a rise of today's honorable kills is the signal", function()
  local ns = Start({ q = 25000, max = 25000, hk = 3 })   -- 3 kills today: the login's base
  local p = ns.char.pvp
  Stub.HK(1)
  local wg = p.wg
  T.eq(wg, time(), "kills: a signal")
  Stub.Advance(300)
  Stub.GainHonor(10)                               -- held at the cap: no rise, no signal
  T.eq(p.wg, wg)
  Stub.Advance(300)
  Stub.HK(1)
  T.eq(Level(ns, 10).pw, 600)
  -- a lower count (the daily reset) is a base, not a signal
  Stub.DailyReset()
  Stub.Advance(100)
  Stub.Fire("PLAYER_PVP_KILLS_CHANGED", "player")
  T.eq(p.wg, time() - 100, "a fall: no signal")
  T.eq(Stub.errors, {})
end)

-- The base of today's kills is the first read above 0 of a load (review pvpdata-1): the
-- login may read 0 before the data is loaded, then PLAYER_PVP_KILLS_CHANGED brings the
-- real count; that rise is no signal.
T.test("world pvp: 0 read at the login, then the real count: no signal; 10 min later one kill counts nothing", function()
  for _, lone in ipairs({ "kill", "honor" }) do
    Stub.Reset()
    local ns = Start()                             -- the login reads 0 kills today
    local p = ns.char.pvp
    Stub.Advance(5)
    Stub.pvp.hkToday = 25                          -- the real count arrives
    Stub.Fire("PLAYER_PVP_KILLS_CHANGED", "player")
    T.eq(p.wg, nil, lone .. ": the real count is a base, not a signal")
    Stub.Advance(600)                              -- 10 min of questing
    if lone == "kill" then Stub.HK(1) else Honor() end
    T.eq(p.wg, time(), lone .. ": the lone signal opens the window")
    T.eq({ Level(ns, 10).pw, ns.char.life.pw, ns.Tracker.GetDelta().life.pw }, { nil, nil, nil },
      lone .. ": a lone signal counts 0")
  end
  T.eq(Stub.errors, {})
end)

T.test("world pvp: a quick relog with seconds pending, 0 then the real count at the login: nothing committed", function()
  local ns = Start({ hk = 3 })
  Stub.HK(1)                                       -- a real lone kill: the window opens
  Stub.Advance(300)
  T.eq(ns.char.pvp.wp[10], 300, "pending")
  Stub.pvp.hkToday = 0                             -- the next login reads 0 first
  ns = Stub.Restart({ offline = 60, settle = 3 })
  local p = ns.char.pvp
  T.ok(p.wp[10] ~= nil and p.wg ~= nil, "the window and its pending seconds kept")
  Stub.pvp.hkToday = 4                             -- then the real count
  Stub.Fire("PLAYER_PVP_KILLS_CHANGED", "player")
  T.eq({ ns.char.levels[10].pw, ns.char.life.pw }, { nil, nil }, "the real count commits nothing")
  -- a real kill inside the window is the second signal: it commits
  local pending = p.wp[10]
  Stub.HK(1)
  T.eq(ns.char.levels[10].pw, math.floor(pending + 0.5), "two real kills: counted")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: at 0 kills today the first kill is a base only, the next a signal; the honor still signals", function()
  local ns = Start()
  local p = ns.char.pvp
  Stub.Advance(60)
  Stub.HK(1)
  T.eq(p.wg, nil, "the first read above 0: a base")
  Stub.Advance(60)
  Stub.HK(1)
  T.eq(p.wg, time(), "the next kill: a signal")
  Stub.Reset()
  ns = Start()
  Honor()
  T.eq(ns.char.pvp.wg, time(), "the honor: a signal at 0 kills")
  -- based, the daily reset's 0 is a new base and the first kill of the new day a signal
  Stub.Reset()
  ns = Start({ hk = 3 })
  p = ns.char.pvp
  Stub.DailyReset()
  Stub.Advance(60)
  Stub.Fire("PLAYER_PVP_KILLS_CHANGED", "player")
  T.eq(p.wg, nil, "the fall to 0: no signal")
  Stub.HK(1)
  T.eq(p.wg, time(), "the first kill of the new day: a signal")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: with the PvP strip shown (every event registered) it measures the same", function()
  local ns = Start({ widget = { pvp = "rank" }, pvp = { capAlert = true }, hk = 3 })
  Honor()
  Stub.Advance(240)
  Stub.HK(1)
  T.eq(Level(ns, 10).pw, 240)
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Persistence, start of the measure, reset, swap
---------------------------------------------------------------------------

T.test("world pvp: w0 set once; the pending seconds and the window survive a /reload", function()
  local ns = Start()
  local p = ns.char.pvp
  local w0 = p.w0
  T.ok(type(w0) == "number" and w0 <= time() and w0 >= time() - 5, "measuring began at the load")
  Honor()
  local wg = p.wg
  Stub.Advance(300)
  T.eq(p.wp[10], 300)
  local ns2 = Stub.Restart({ reload = true, settle = 3 })
  local p2 = ns2.char.pvp
  T.ok(p2 ~= p, "the record read back from the saved variables")
  T.eq(p2.w0, w0, "w0 kept")
  T.eq(p2.wg, wg, "the window kept")
  local pending = p2.wp[10]
  T.ok(pending >= 300 and pending <= 304, format("the pending seconds kept (%s)", tostring(pending)))
  Honor()                                          -- the first honor read of the load was a base
  T.eq(ns2.char.levels[10].pw, math.floor(pending + 0.5))
  T.eq(Stub.errors, {})
end)

T.test("world pvp: WorldPvpState from w0 and the levels' dates", function()
  local ns = Start()
  local S = ns.Stats
  T.eq(S.WorldPvpState(ns.char, 10), "partial", "the install's level: begun before w0")
  Stub.Advance(10)
  local pl = Stub.player
  Stub.GrantXP(pl.max - pl.xp + 50)
  T.eq(S.WorldPvpState(ns.char, 11), "yes", "reached after w0")
  T.eq(S.WorldPvpState(ns.char, 10), "partial", "ended after w0")
  T.eq(S.WorldPvpState(ns.char, 12), "no", "no record")
  ns.char.pvp.w0 = ns.char.levels[10].t1 + 1
  T.eq(S.WorldPvpState(ns.char, 10), "no", "ended before w0")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: ResetChar wipes pw and the window; measuring starts again", function()
  local ns = Start()
  Honor()
  Stub.Advance(120)
  Honor()
  Stub.Advance(60)
  T.eq(Level(ns, 10).pw, 120)
  T.ok(ns.Core.ResetChar())
  local p = ns.char.pvp
  T.eq({ ns.char.life.pw, Level(ns, 10).pw, p.wg }, { nil, nil, nil })
  T.eq(next(p.wp), nil)
  T.eq(p.w0, time(), "measuring starts again now")
  Stub.Advance(60)
  Honor()
  T.eq(Level(ns, 10).pw, nil, "a lone signal after the reset: nothing")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: a late SavedVariables swap replays this load's pw exactly once", function()
  local ns = Start()
  Honor()
  Stub.Advance(120)
  Honor()                                          -- 120 s in the saved record
  T.eq(Level(ns, 10).pw, 120)
  Stub.Logout()
  local real = Stub.DeepCopy(Stub.saved)
  local guid = Stub.player.guid
  T.eq(real.chars[guid].levels[10].pw, 120)
  -- next session: the saved table appears only after PLAYER_LOGIN
  Stub.Reset({ keepWorld = true })
  rawset(_G, "TruePlayedDB", nil)
  ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(30)
  Honor()                                          -- the blank table: a base, then signals
  Honor()
  Stub.Advance(200)
  Honor()
  T.eq(ns.Tracker.GetDelta().levels[10].pw, 200, "this load's pw in the delta")
  rawset(_G, "TruePlayedDB", real)
  Stub.Advance(2)                                  -- CheckSwap at the next tick
  T.ok(ns.db == real, "swapped")
  T.eq(ns.char.levels[10].pw, 320, "the saved 120 plus this load's 200, once")
  T.eq(ns.char.life.pw, 320)
  Stub.Advance(10)
  T.eq(ns.char.levels[10].pw, 320, "not again")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Nothing recorded: read-only, Classic Era, no API; the guards
---------------------------------------------------------------------------

T.test("world pvp: read-only mode, Classic Era and no API record nothing", function()
  local ns = Start({ db = { schema = 99, settings = { firstRunDone = true }, chars = {} } })
  T.ok(ns.readOnly)
  Honor()
  Stub.Advance(120)
  Honor()
  Stub.HK(1)
  T.eq(ns.char.pvp, nil, "read-only: no record, no w0")
  T.eq({ ns.char.life.pw, Level(ns, 10) and Level(ns, 10).pw }, { nil, nil })
  ns.Tracker.AddLevelStat("pw", 50, 10)
  T.eq(ns.char.life.pw, nil, "AddLevelStat refuses in read-only mode")
  for _, api in ipairs({ "era", "none" }) do
    Stub.Reset()
    ns = Start({ api = api })
    T.eq(Stub.CountRegistered("PLAYER_PVP_KILLS_CHANGED"), 0, api .. ": dormant")
    Honor()
    Stub.Advance(120)
    Honor()
    Stub.HK(1)
    T.eq(ns.char.pvp, nil, api .. ": no record")
    T.eq(ns.char.life.pw, nil, api)
    T.eq(ns.Stats.WorldPvpState(ns.char, 10), "no", api .. ": not measured")
  end
  T.eq(Stub.errors, {})
end)

T.test("world pvp: AddLevelStat adds to life and the level, record and delta; bad amounts refused", function()
  local ns = Start()
  local Tr = ns.Tracker
  Tr.AddLevelStat("pw", 5)                         -- the segment's level
  Tr.AddLevelStat("pw", 7, 9)                      -- another level: its record made
  T.eq({ ns.char.life.pw, Level(ns, 10).pw, Level(ns, 9).pw }, { 12, 5, 7 })
  local d = Tr.GetDelta()
  T.eq({ d.life.pw, d.levels[10].pw, d.levels[9].pw }, { 12, 5, 7 })
  for _, n in ipairs({ 0, -3, 0 / 0, math.huge, "4" }) do Tr.AddLevelStat("pw", n, 10) end
  T.eq({ ns.char.life.pw, Level(ns, 10).pw, d.life.pw }, { 12, 5, 12 }, "0, negative, NaN, inf, a string")
  T.eq(Stub.errors, {})
end)

T.test("world pvp: repair of pw (life, levels) and of wg, w0, wp; no default added", function()
  local ns = Start()
  local Core = ns.Core
  local rec = {
    life = { s = { w = 100 }, pw = -1 },
    levels = {
      [10] = { s = { w = 50 }, pw = 0 / 0 }, [11] = { s = { w = 10 }, pw = 7 },
      [12] = { s = {}, pw = "x" }, [13] = { s = {}, pw = math.huge }, [14] = { s = {}, pw = 0 },
    },
    pvp = { wg = "x", w0 = -3, wp = { [10] = 5.5, [11] = -1, [0] = 3, [2.5] = 1, x = 2, [12] = 0 / 0,
                                      [math.huge] = 1, [13] = 0 } },
  }
  Core.RepairChar(rec)
  T.eq(rec.life.pw, nil, "negative")
  T.eq({ rec.levels[10].pw, rec.levels[11].pw, rec.levels[12].pw, rec.levels[13].pw, rec.levels[14].pw },
    { nil, 7, nil, nil, 0 }, "NaN, a string and inf dropped; 0 and 7 kept")
  T.eq({ rec.pvp.wg, rec.pvp.w0 }, { nil, nil })
  T.eq(rec.pvp.wp, { [10] = 5.5, [13] = 0 }, "whole levels >= 1 to finite seconds >= 0 only")
  rec = { pvp = { wp = 5, wg = 100, w0 = 50 } }
  Core.RepairChar(rec)
  T.eq({ rec.pvp.wp, rec.pvp.wg, rec.pvp.w0 }, { {}, 100, 50 }, "a bad pending map made again")
  rec = { pvp = { h = 3 } }
  Core.RepairChar(rec)
  T.eq(rec.pvp.wp, {}, "a missing one made")
  rec = { life = Core.NewLife(), levels = { [3] = Core.NewLevel() } }
  Core.RepairChar(rec)
  T.eq({ rec.life.pw, rec.levels[3].pw }, { nil, nil }, "no default: not measured is not 0")
  T.eq(Core.NewLevel(), { s = {}, z = {}, xp = 0, xa = 0, xr = 0, xq = 0, d = 0 }, "NewLevel unchanged")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Allocation
---------------------------------------------------------------------------

T.test("world pvp: Advance in the open world inside the window allocates nothing once warm", function()
  local ns, P = Start()
  Honor()
  Stub.Advance(5)                                  -- the level's pending key made
  local kb = T.alloc(function() P.Advance(1, "w", 10) end, 3000)
  T.ok(kb < 0.1, format("Advance in the window: %.3f KB", kb))
  kb = T.alloc(function() P.Advance(1, "t", 10) end, 3000)
  T.ok(kb < 0.1, format("Advance in another state: %.3f KB", kb))
  -- the whole tick inside the window (Tracker -> Pvp.Advance), 600 ticks
  Stub.Advance(5)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 2, format("tick inside the window: %.2f KB over 600 ticks", kb))
  -- and once the window ran out (the pending map emptied, then nothing to do)
  Stub.Advance(900)
  T.eq(next(ns.char.pvp.wp), nil)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 2, format("tick after the window: %.2f KB over 600 ticks", kb))
  T.eq(Stub.onUpdateCount, 0)
end)
