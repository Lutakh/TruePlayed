-- tests/test_tracker.lua - Tracker: time accounting, states, zones, XP chain,
-- EMA, sessions, /reload continuity, late SV swap, allocations (SPEC 9.4).
local Stub, T = ...

local floor = math.floor
local KEYS = { "w", "W", "d", "D", "r", "R", "p", "P", "i", "I", "c", "C", "t", "T", "u" }

local function SumAll(s)
  local t = 0
  if not s then return 0 end
  for _, k in ipairs(KEYS) do t = t + (s[k] or 0) end
  return t
end

local function Count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- Fresh addon: optional SV table, settle seconds.
local function Login(db, settle)
  if db then _G.TruePlayedDB = db end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = settle })
  return ns
end

-- Counts the messages `msg` sent from now on.
local function Spy(ns, msg)
  local box = { n = 0, args = {} }
  ns.RegisterMessage(msg, "test-spy-" .. msg, function(_, a1, a2, a3)
    box.n = box.n + 1
    box.args[box.n] = { a1, a2, a3 }
  end)
  return box
end

local function State(ns)
  local key, zone, level = ns.Tracker.GetState()
  return key, zone, level
end

---------------------------------------------------------------------------
-- 1. basic credit
---------------------------------------------------------------------------

T.test("100 s in the world credit life, level, level-zone, zone and session", function()
  local ns = Login()
  Stub.Advance(100)
  local ch = ns.char
  T.eq(ch.life.s.w, 100, "life")
  T.eq(ch.levels[10].s.w, 100, "level")
  T.eq(ch.levels[10].z[1411].s.w, 100, "level zone")
  T.eq(ch.zones[1411].s.w, 100, "zone")
  T.eq(ns.session.s.w, 100, "session")
  T.eq(ns.Tracker.GetDelta().life.s.w, 100, "delta")
  T.eq(ch.zones[1411].name, "Durotar", "zone name stored")
  T.eq(ns.char.cur, ns.session, "live session persisted as char.cur")
end)

---------------------------------------------------------------------------
-- 2. fraction carry
---------------------------------------------------------------------------

T.test("AFK at t = 10.5: w = 10, W = 89 or 90, total exact", function()
  local ns = Login()
  Stub.Advance(10.5)
  Stub.SetAFK(true)
  Stub.Advance(89.5)
  local s = ns.char.life.s
  T.eq(s.w, 10, "w")
  T.ok(s.W == 89 or s.W == 90, "W = " .. tostring(s.W))
  T.eq(s.w + s.W, 100, "total")
  T.eq((State(ns)), "W")
end)

---------------------------------------------------------------------------
-- 3. precedence and zones
---------------------------------------------------------------------------

T.test("precedence: taxi > city > resting > world, AFK orthogonal", function()
  local ns = Login()
  Stub.SetMap(1454)                         -- Orgrimmar
  local k, z = State(ns)
  T.eq(k, "c"); T.eq(z, 1454)
  Stub.SetResting(true)                     -- rested inside a capital: still city
  T.eq((State(ns)), "c")
  Stub.player.afk = true
  Stub.SetTaxi(true)                        -- flight over the city while AFK
  T.eq((State(ns)), "T")
  Stub.Advance(5)
  T.eq(ns.char.zones[1454].s.T, 5, "flight seconds go to the zone under the flight")
  T.eq(ns.char.zones[1454].s.c, nil, "a flight over a city is not city time")
  Stub.SetTaxi(false)
  Stub.SetAFK(false)
  Stub.SetMap(1411)                         -- resting outside a capital
  T.eq((State(ns)), "i")
  Stub.SetResting(false)
  T.eq((State(ns)), "w")
end)

T.test("maps under a capital, instances, continent-typed islands", function()
  local ns = Login()
  Stub.SetMap(90003)                        -- Valley of Strength (micro under 1454)
  local k, z = State(ns)
  T.eq(k, "c"); T.eq(z, 1454)
  Stub.SetMap(90002)                        -- Cleft of Shadow (dungeon floor, not an instance)
  k, z = State(ns)
  T.eq(k, "c"); T.eq(z, 1454)
  Stub.SetInstance(true, "party", 389, 90001)   -- Ragefire Chasm instance
  k, z = State(ns)
  T.eq(k, "d"); T.eq(z, 90001)
  Stub.SetInstance(true, "party", 34, 90004)    -- the Stockade: never a city inside an instance
  k, z = State(ns)
  T.eq(k, "d"); T.eq(z, 90004)
  Stub.SetInstance(true, "party", 777, nil)     -- instance without a map
  k, z = State(ns)
  T.eq(k, "d"); T.eq(z, "i777")
  -- a map typed Continent without any zone below it is an island played as a zone
  -- (Zephras Isle on Forever, where GetBestMapForUnit returns it): a zone key at once
  Stub.player.zoneText = "Zephras Isle"
  Stub.SetInstance(false, "none", 0, 2521)
  k, z = State(ns)
  T.eq(k, "w"); T.eq(z, 2521)
  Stub.Advance(3)
  T.eq(ns.char.zones[2521].s.w, 3, "island seconds credited at once, never held")
  -- a continent with zones below it (Kalimdor) is never a zone key: its seconds are
  -- held, then go to the zone text after C.ZONE_HOLD_MAX seconds
  Stub.player.zoneText = "Durotar"
  Stub.SetMap(1414)
  k, z = State(ns)
  T.eq(k, "w"); T.eq(z, 2521, "unresolved: zone unchanged while the seconds are held")
  Stub.Advance(ns.C.ZONE_HOLD_MAX + 1)
  k, z = State(ns)
  T.eq(k, "w"); T.eq(z, "nDurotar", "zone text after the cap")
  T.eq(ns.char.zones[1414], nil, "no bucket for a continent")
  T.eq(ns.char.zones.nDurotar.s.w, ns.C.ZONE_HOLD_MAX + 1, "held seconds credited, none lost")
  T.eq(ns.char.zones[2521].s.w, 3, "nothing credited to the previous zone")
  Stub.player.mapID = nil                       -- map unknown: previous zone kept
  Stub.Fire("ZONE_CHANGED")
  k, z = State(ns)
  T.eq(k, "w"); T.eq(z, "nDurotar")
end)

T.test("city overrides: db.cities and /tpl citytoggle", function()
  local ns = Login({ schema = 1, cities = { [1458] = false } })
  local spy = Spy(ns, "SETTINGS_CHANGED")
  Stub.SetMap(1458)                         -- Undercity forced "not a city"
  T.eq((State(ns)), "w")
  Stub.SetMap(1411)
  local id, isCity, name = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(id, 1411); T.eq(isCity, true); T.eq(name, "Durotar")
  T.eq(ns.db.cities[1411], true)
  T.eq((State(ns)), "c", "future seconds count as city")
  T.eq(spy.args[spy.n][1], "cities"); T.eq(spy.args[spy.n][2], 1411)
  id, isCity = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(id, 1411); T.eq(isCity, false)
  T.eq(ns.db.cities[1411], nil, "override equal to the default is removed")
  T.eq((State(ns)), "w")
  Stub.SetMap(90003)                        -- inside Orgrimmar: toggles the capital itself
  id, isCity = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(id, 1454); T.eq(isCity, false)
  T.eq(ns.db.cities[1454], false)
  T.eq((State(ns)), "w")
  id, isCity = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(id, 1454); T.eq(isCity, true, "toggling twice restores the default")
  T.eq(ns.db.cities[1454], nil)
  T.eq((State(ns)), "c")
  Stub.player.mapID = nil
  local none, err = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(none, nil); T.eq(err, "nozone")
end)

T.test("/tpl citytoggle inside an instance changes nothing (instances are never cities)", function()
  local ns = Login()
  Stub.SetInstance(true, "party", 389, 90001)   -- Ragefire Chasm, under Orgrimmar
  T.eq((State(ns)), "d")
  local spy = Spy(ns, "SETTINGS_CHANGED")
  local id, err = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(id, nil); T.eq(err, "instance")
  T.eq(ns.db.cities[90001], nil, "no useless override stored")
  T.eq(ns.db.cities[1454], nil)
  T.eq(spy.n, 0)
  T.eq((State(ns)), "d")
end)

---------------------------------------------------------------------------
-- 4. secret values and chat lockdown
---------------------------------------------------------------------------

T.test("chat lockdown does not freeze AFK; a secret AFK flag keeps the last state", function()
  _G.C_ChatInfo = { InChatMessagingLockdown = function() return true end }
  local ns = Login()
  Stub.SetAFK(true)
  T.eq((State(ns)), "W", "AFK read despite the chat lockdown")
  Stub.SetAFK(false)
  T.eq((State(ns)), "w")
  Stub.secret.afk = true
  Stub.SetAFK(true)                         -- the client hides the flag
  T.eq((State(ns)), "w", "secret: previous state kept")
  Stub.Advance(3)
  T.eq((State(ns)), "w")
  Stub.secret.afk = false
  Stub.Fire("PLAYER_FLAGS_CHANGED", "player")
  T.eq((State(ns)), "W")
  Stub.secret.resting, Stub.secret.taxi = true, true
  Stub.Advance(2)
  T.eq((State(ns)), "W", "secret resting/taxi keep their last values")
end)

---------------------------------------------------------------------------
-- 5. loading screens and dropped segments
---------------------------------------------------------------------------

T.test("loading screen: its seconds go to the pre-load state", function()
  local ns = Login()
  Stub.Advance(30)
  Stub.Fire("PLAYER_LEAVING_WORLD")
  Stub.Advance(20)
  Stub.SetMap(1446)                         -- new zone known after the loading screen
  Stub.Fire("PLAYER_ENTERING_WORLD", false, false)
  Stub.Advance(10)
  local ch = ns.char
  T.eq(ch.life.s.w, 60)
  T.eq(ch.zones[1411].s.w, 50)
  T.eq(ch.zones[1446].s.w, 10)
  T.eq(ns.Tracker.GetLoadKind(), "login", "a loading screen is not a new load")
end)

T.test("a segment longer than 900 s is dropped (with a debug line)", function()
  local ns = Login()
  Stub.Advance(20)
  ns.settings.debug = true
  local start = Stub.Now()
  local first
  ns.RegisterMessage("TICK", "test-first-tick", function(_, now) if not first then first = now end end)
  local before = SumAll(ns.char.life.s)
  local printed = #Stub.printed
  Stub.Advance(1000, 1000)
  if not first or first - start < 900 then
    T.skip("this stub fires timers at their due time: the ticker cannot be frozen")
  end
  T.eq(SumAll(ns.char.life.s), before, "nothing credited for the frozen period")
  T.ok(#Stub.printed > printed, "debug line printed")
  Stub.Advance(5)
  T.eq(SumAll(ns.char.life.s), before + 5, "counting resumes")
end)

---------------------------------------------------------------------------
-- 6. /reload continuity and real login
---------------------------------------------------------------------------

T.test("/reload: gap credited to the last state, session resumed, sync restored", function()
  local ns = Login()
  Stub.Advance(60)                          -- the login /played at +10 s gives a sync
  T.ok(ns.Tracker.GetSync(), "synced before the reload")
  local w = ns.char.life.s.w
  ns = Stub.Restart({ reload = true, offline = 4 })
  T.eq(ns.Tracker.GetLoadKind(), "reload")
  T.eq(ns.char.life.s.w, w + 4, "4 s reload gap credited")
  T.eq(ns.session, ns.char.cur, "session resumed")
  T.eq(ns.session.s.w, 64, "same session")
  local sync = ns.Tracker.GetSync()
  T.ok(sync and sync.restored, "sync restored")
  Stub.Advance(15)
  T.eq(Stub.requests, 0, "no /played request after a reload")
  T.eq(#ns.char.sessions, 0, "no ring push on reload")
end)

T.test("real login: no gap credit, previous session closed into the ring", function()
  Login()
  Stub.Advance(60)
  local ns = Stub.Restart({ offline = 4 })
  local ch = ns.char
  T.eq(ns.Tracker.GetLoadKind(), "login")
  T.eq(ch.life.s.w, 60, "character screen time is not played")
  T.eq(#ch.sessions, 1)
  local closed = ch.sessions[1]
  T.eq(closed.s.w, 60)
  T.ok(closed.t1 ~= nil and closed.at == nil and closed.g == nil, "closed session fields")
  T.eq(closed.l1, 10)
  T.ok(ns.session ~= closed and ch.cur == ns.session, "new live session")
  T.eq(SumAll(ns.session.s), 0)
end)

T.test("the session ring keeps the 30 most recent sessions", function()
  Login()
  Stub.Advance(3)
  local ns
  for i = 1, 32 do
    ns = Stub.Restart({})
    Stub.Advance(3 + i)
  end
  local ring = ns.char.sessions
  T.eq(#ring, 30)
  T.eq(ring[30].s.w, 3 + 31, "newest closed session last")
end)

---------------------------------------------------------------------------
-- 7. level-up idempotency
---------------------------------------------------------------------------

T.test("level-up: a tick between UnitLevel and PLAYER_LEVEL_UP gives one LEVEL_UP", function()
  local ns = Login()
  Stub.Advance(5)
  local spy = Spy(ns, "LEVEL_UP")
  local P = Stub.player
  P.level, P.xp, P.max = 11, 0, Stub.xpTable[11]
  Stub.Advance(1)                           -- the tick catches the missed level-up
  T.eq(spy.n, 1)
  T.eq(spy.args[1][1], 11); T.eq(spy.args[1][2], 10)
  T.eq(select(3, State(ns)), 11)
  Stub.Advance(10)
  local lb = ns.char.levels[11]
  local secs = SumAll(lb.s)
  T.ok(secs >= 10, "seconds credited to the new level")
  T.ok(lb.t0 ~= nil and ns.char.levels[10].t1 ~= nil, "t0 / t1 set")
  Stub.Fire("PLAYER_LEVEL_UP", 11)          -- the late event
  Stub.Advance(1)
  T.eq(spy.n, 1, "exactly one LEVEL_UP")
  T.eq(ns.char.levels[11], lb, "record never replaced")
  T.ok(SumAll(lb.s) >= secs, "nothing erased")
  T.eq(Count(ns.char.levels), 2)
end)

T.test("level-up XP split: max - 800 then +2000 -> 800 to N, 1200 to N+1", function()
  Stub.player.xp = Stub.xpTable[10] - 800
  local ns = Login()
  Stub.Advance(5)
  local spy = Spy(ns, "LEVEL_UP")
  Stub.GrantXP(2000, { noLevelEvent = true })
  Stub.Advance(2)
  Stub.Fire("PLAYER_LEVEL_UP", 11)
  Stub.Advance(1)
  local ch = ns.char
  T.eq(spy.n, 1)
  T.eq(ch.levels[10].xp, 800)
  T.eq(ch.levels[11].xp, 1200)
  T.eq(ch.life.xp, 2000)
  T.eq(ch.levels[11].max, Stub.xpTable[11])
  T.eq(ns.db.xpMax[11], Stub.xpTable[11])
  T.eq(ch.levels[10].z[1411].xp, 800)
  T.eq(ch.levels[11].z[1411].xp, 1200)
  T.eq(ch.zones[1411].xp, 2000)
  T.eq(ns.session.xp, 2000)
end)

T.test("level-up with the level event first splits the same way", function()
  Stub.player.xp = Stub.xpTable[10] - 300
  local ns = Login()
  Stub.Advance(5)
  Stub.GrantXP(1000, { levelEventFirst = true })
  Stub.Advance(2)
  T.eq(ns.char.levels[10].xp, 300)
  T.eq(ns.char.levels[11].xp, 700)
end)

T.test("a gain over two levels also counts the skipped level when its size is known", function()
  local ns = Login({ schema = 1, xpMax = { [11] = Stub.xpTable[11] } })
  Stub.Advance(5)
  local x10, x11 = Stub.xpTable[10], Stub.xpTable[11]
  Stub.GrantXP(x10 + x11 + 400, { quest = 1000 })   -- rest of 10, all of 11, 400 into 12
  Stub.Advance(2)
  T.eq(Stub.player.level, 12)
  local ch, d = ns.char, ns.Tracker.GetDelta()
  T.eq(ch.levels[10].xp, x10)
  T.eq(ch.levels[11].xp, x11, "the skipped level gets its whole XP")
  T.eq(ch.levels[12].xp, 400)
  T.eq(ch.life.xp, x10 + x11 + 400)
  T.eq(ch.life.xq, 1000)
  for l = 10, 12 do
    local lb = ch.levels[l]
    T.eq(lb.xa + lb.xr + lb.xq, lb.xp, "a + r + q == xp at level " .. l)
    T.eq(d.levels[l].xp, lb.xp, "delta level " .. l)
  end
  T.eq(ch.levels[10].xq, 1000, "quest XP placed on the oldest level first")
  T.eq(ch.levels[11].z[1411].xp, x11)
  T.eq(ch.zones[1411].xp, x10 + x11 + 400)
  T.eq(SumAll(ch.levels[11].s), 0, "no time invented for the skipped level")
  T.eq(ns.Stats.AccountAvgPerLevel(ns.db, 0), nil, "a level without time is not an average sample")
end)

T.test("a gain over two levels with an unknown skipped size: nothing invented", function()
  local ns = Login()
  Stub.Advance(5)
  T.eq(ns.db.xpMax[11], nil)
  local x10, x11 = Stub.xpTable[10], Stub.xpTable[11]
  Stub.GrantXP(x10 + x11 + 400)
  Stub.Advance(2)
  T.eq(Stub.player.level, 12)
  local ch = ns.char
  T.eq(ch.levels[11], nil, "no record for the skipped level")
  T.eq(ch.levels[10].xp, x10)
  T.eq(ch.levels[12].xp, 400)
  T.eq(ch.life.xp, x10 + 400)
end)

T.test("the gain that completes the level before the max level is counted on that level", function()
  local P = Stub.player
  P.level, P.xp, P.max = 59, 2000, Stub.xpTable[59]
  local ns = Login()
  Stub.Advance(5)
  T.no(ns.Tracker.IsMax())
  local ch = ns.char
  local ema0 = ch.ema[1].a + ch.ema[1].r + ch.ema[1].q
  local need = Stub.xpTable[59] - 2000
  Stub.GrantXP(need)                         -- ding 60 (max level)
  Stub.Advance(2)
  T.eq(P.level, 60)
  T.ok(ns.Tracker.IsMax())
  T.eq(ch.levels[59].xp, need, "last gain of level 59")
  T.eq(ch.life.xp, need)
  T.eq(ch.levels[60] and ch.levels[60].xp or 0, 0)
  T.eq(ch.levels[60] and ch.levels[60].max, nil, "no XP size stored for the max level")
  T.ok(ch.ema[1].a + ch.ema[1].r + ch.ema[1].q > ema0)
  Stub.GrantXP(500)                          -- at max level: nothing more is counted
  Stub.Advance(2)
  T.eq(ch.life.xp, need)
end)

---------------------------------------------------------------------------
-- 8. XP event disorder, false zero
---------------------------------------------------------------------------

T.test("XP reset before PLAYER_LEVEL_UP: retry, then correct split", function()
  Stub.player.xp = Stub.xpTable[10] - 500
  local ns = Login()
  Stub.Advance(5)
  local P = Stub.player
  P.xp = 300                                -- XP already reset, level not yet
  Stub.Fire("PLAYER_XP_UPDATE", "player")
  Stub.Advance(0.3)
  T.eq(ns.char.life.xp, 0, "negative gain not counted")
  P.level, P.max = 11, Stub.xpTable[11]
  Stub.Fire("PLAYER_LEVEL_UP", 11)
  Stub.Advance(1)
  T.eq(ns.char.levels[10].xp, 500)
  T.eq(ns.char.levels[11].xp, 300)
  T.eq(ns.char.life.xp, 800)
end)

T.test("a negative gain that persists re-baselines without counting", function()
  Stub.player.xp = 3000
  local ns = Login()
  Stub.Advance(5)
  Stub.player.xp = 1000                     -- e.g. an XP loss we cannot explain
  Stub.Fire("PLAYER_XP_UPDATE", "player")
  Stub.Advance(2)
  T.eq(ns.char.life.xp, 0)
  Stub.GrantXP(100)
  Stub.Advance(1)
  T.eq(ns.char.life.xp, 100, "counting resumes from the new baseline")
end)

T.test("false zero at login is ignored", function()
  Stub.player.xp = 0
  local ns = Login()
  Stub.Advance(5)                           -- baseline read at +2 s: xp 0
  Stub.player.xp = 6000                     -- real value (> half the level) shows up
  Stub.Fire("PLAYER_XP_UPDATE", "player")
  Stub.Advance(1)
  T.eq(ns.char.life.xp, 0)
  Stub.GrantXP(100)
  Stub.Advance(1)
  T.eq(ns.char.life.xp, 100)
end)

T.test("an XP read that is secret waits for the end of combat", function()
  local ns = Login()
  Stub.Advance(5)
  Stub.secret.xp = true
  Stub.GrantXP(250)
  Stub.Advance(1)
  T.eq(ns.char.life.xp, 0)
  Stub.secret.xp = false
  Stub.LeaveCombat()
  Stub.Advance(1)
  T.eq(ns.char.life.xp, 250)
end)

---------------------------------------------------------------------------
-- 9. rest / quest classification
---------------------------------------------------------------------------

T.test("classification: rested pool, quests, rested without drop, exhaustion first", function()
  Stub.player.rest = 1000
  local ns = Login()
  Stub.Advance(5)
  local life = ns.char.life
  Stub.GrantXP(200, { restDrop = 200 })     -- mob kill with the rested bonus
  Stub.Advance(1)
  T.eq(life.xr, 100, "rested bonus"); T.eq(life.xa, 100, "base"); T.eq(life.xq, 0)
  Stub.GrantXP(500, { quest = 500 })
  Stub.Advance(1)
  T.eq(life.xq, 500, "quest")
  Stub.GrantXP(300)                         -- rested, no pool drop: not a mob
  Stub.Advance(1)
  T.eq(life.xq, 800, "exploration while rested"); T.eq(life.xa, 100)
  -- UPDATE_EXHAUSTION processed before the XP update
  Stub.player.rest = Stub.player.rest - 200
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(0.5)
  Stub.player.xp = Stub.player.xp + 200
  Stub.Fire("PLAYER_XP_UPDATE", "player")
  Stub.Advance(1)
  T.eq(life.xr, 200, "pool drop kept for the next gain"); T.eq(life.xa, 200)
  local lb = ns.char.levels[10]
  T.eq(lb.xp, life.xp); T.eq(lb.xa, life.xa); T.eq(lb.xr, life.xr); T.eq(lb.xq, life.xq)
  T.eq(life.xp, life.xa + life.xr + life.xq)
  T.eq(ns.session.p0, 0, "session start progress filled by the baseline")
end)

T.test("a quest reward and its XP event in either order", function()
  local ns = Login()
  Stub.Advance(5)
  Stub.GrantXP(400, { quest = 400, order = "exhaustionFirst" })
  Stub.Advance(1)
  T.eq(ns.char.life.xq, 400)
  Stub.Advance(10)                          -- pending quest XP expires
  Stub.GrantXP(50)
  Stub.Advance(1)
  T.eq(ns.char.life.xa, 50)
end)

---------------------------------------------------------------------------
-- 10. EMA
---------------------------------------------------------------------------

T.test("EMA: excluded AFK does not lower the AFK-excluded rate; toggling is instant", function()
  local ns = Login()
  Stub.Advance(60)
  T.near(ns.char.ema[1].d, 60, 1, "d ~ elapsed while t << tau")
  for _ = 1, 50 do
    Stub.Advance(36)
    Stub.GrantXP(100)                       -- 10000 XP/h
  end
  Stub.Advance(1)
  local function xph(m)
    local e = ns.char.ema[m + 1]
    return 3600 * (e.a + e.r + e.q) / e.d
  end
  local v0, v1 = xph(0), xph(1)
  T.near(v0, 10000, 1000, "rate while active")
  T.eq(v0, v1, "no excluded time yet")
  Stub.SetAFK(true)
  Stub.Advance(1800)
  T.eq(xph(1), v1, "mask 1 (AFK excluded) unchanged by 30 min of AFK")
  T.ok(xph(0) < 0.7 * v0, "mask 0 lower")
  local r0 = ns.Stats.Rate(ns.char, ns.GetMask())
  ns.Core.SetSetting("exclude.afk", true)
  local r1, _, _, _, src, status = ns.Stats.Rate(ns.char, ns.GetMask())
  T.ok(r1 > r0, "toggling the exclusion changes the value without new data")
  T.near(r1, v1, 0.001)
  T.eq(src, "ema"); T.eq(status, "ok")
  local paused, why = ns.Tracker.IsPaused(ns.GetMask())
  T.ok(paused); T.eq(why, "afk")
end)

T.test("IsPaused reasons for inn and city exclusions", function()
  local ns = Login()
  T.no((ns.Tracker.IsPaused(7)), "world time is never paused")
  Stub.SetResting(true)
  local p, why = ns.Tracker.IsPaused(2)
  T.ok(p); T.eq(why, "inn")
  Stub.SetResting(false)
  Stub.SetMap(1454)
  p, why = ns.Tracker.IsPaused(4)
  T.ok(p); T.eq(why, "city")
  T.no((ns.Tracker.IsPaused(3)))
  Stub.SetAFK(true)
  p, why = ns.Tracker.IsPaused(5)
  T.ok(p); T.eq(why, "afk")
end)

---------------------------------------------------------------------------
-- 11. max level
---------------------------------------------------------------------------

T.test("max level: no XP or EMA writes, time continues", function()
  local P = Stub.player
  P.level, P.xp, P.max = 60, 0, 209800
  local ns = Login()
  Stub.Advance(5)
  T.ok(ns.Tracker.IsMax())
  P.xp = 500
  Stub.Fire("PLAYER_XP_UPDATE", "player")
  Stub.Advance(60)
  T.eq(ns.char.life.xp, 0)
  T.eq(ns.char.ema[1].a + ns.char.ema[1].r + ns.char.ema[1].q, 0)
  T.eq(ns.char.life.s.w, 65)
end)

T.test("XP gain disabled counts as max level and is refreshed by its event", function()
  local ns = Login()
  Stub.Advance(3)
  T.no(ns.Tracker.IsMax())
  local spy = Spy(ns, "XP_CHANGED")
  Stub.player.xpDisabled = true
  Stub.Fire("DISABLE_XP_GAIN")
  T.ok(ns.Tracker.IsMax())
  T.ok(spy.n >= 1)
  Stub.GrantXP(300)
  Stub.Advance(1)
  T.eq(ns.char.life.xp, 0)
  Stub.player.xpDisabled = false
  Stub.Fire("ENABLE_XP_GAIN")
  T.no(ns.Tracker.IsMax())
end)

---------------------------------------------------------------------------
-- 12. late SavedVariables swap (critique #3d)
---------------------------------------------------------------------------

T.test("late SV swap: real u unchanged, this load's seconds added once", function()
  Login()
  Stub.Advance(120)                         -- install sync at +10 s
  Stub.Logout()
  local real = Stub.DeepCopy(Stub.saved)
  local guid = Stub.player.guid
  local realU = real.chars[guid].life.s.u
  local realW = real.chars[guid].life.s.w
  local realLevelU = real.chars[guid].levels[10].s.u
  T.ok(realU and realU > 300000, "install put the pre-install time into u")

  -- next session: the SV table only appears after PLAYER_LOGIN (WTFix-like)
  Stub.Reset({ keepWorld = true })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(30)                          -- blank table synced: u = the whole /played
  local blank = ns.char
  T.ok((blank.life.s.u or 0) > 300000, "blank table got the install u")
  _G.TruePlayedDB = real
  Stub.Advance(2)                           -- CheckSwap at the next tick
  T.ok(ns.db == real and ns.char ~= blank, "swapped")
  local ch = ns.char
  T.eq(ch.life.s.u, realU, "real u unchanged")
  T.eq(ch.levels[10].s.u, realLevelU, "level u unchanged")
  T.eq(ch.life.s.w, realW + ns.Tracker.GetDelta().life.s.w, "this load's seconds added once")
  T.ok(blank.life.s.w <= ns.Tracker.GetDelta().life.s.w, "the blank table stopped counting")
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 2, "SumAll(life) == server total")
  T.eq(ch.life.est or 0, 0, "nothing estimated")
  T.eq(#ch.sessions, 1, "the real table's previous session closed")
  T.eq(ch.cur, ns.session)
  Stub.Advance(10)
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 2)
  T.eq(ch.zones[1411].s.w, ch.life.s.w)
end)

---------------------------------------------------------------------------
-- misc
---------------------------------------------------------------------------

T.test("death, session reset and character reset", function()
  local ns = Login()
  Stub.Advance(30)
  Stub.Fire("PLAYER_DEAD")
  T.eq(ns.char.life.d, 1); T.eq(ns.char.levels[10].d, 1); T.eq(ns.session.d, 1)
  local ema = ns.char.ema[1].d
  local spy = Spy(ns, "SESSION_RESET")
  T.ok(ns.Tracker.ResetSession())
  T.eq(spy.n, 1)
  T.eq(#ns.char.sessions, 1)
  T.eq(ns.char.sessions[1].s.w, 30)
  T.eq(SumAll(ns.session.s), 0)
  T.eq(ns.char.cur, ns.session)
  T.eq(ns.char.ema[1].d, ema, "rates untouched by a session reset")
  Stub.Advance(5)
  T.eq(ns.session.s.w, 5)
  -- character reset (Core rebuilds the record in place, then calls the Tracker)
  T.ok(ns.Core.ResetChar(Stub.player.guid))
  T.ok(ns.char.levels[10].partial, "current level partial after a reset")
  T.eq(ns.char.base, nil)
  Stub.Advance(5)
  T.eq(ns.char.life.s.w, 5, "counting restarts in the rebuilt record")
  T.eq(ns.char.zones[1411].s.w, 5)
end)

T.test("zones bounded at logout; level zones merged into 'o' at level-up", function()
  for i = 1, 160 do
    Stub.maps[50000 + i] = { mapType = 3, parentMapID = 1414, name = "Zone " .. i }
  end
  local ns = Login()
  Stub.SetMap(1454)
  Stub.Advance(2)                           -- a small city zone: never pruned
  for i = 1, 160 do
    Stub.SetMap(50000 + i)
    Stub.Advance(1)
  end
  T.ok(Count(ns.char.levels[10].z) > 10)
  Stub.GrantXP(Stub.xpTable[10])            -- level-up: level 10 is complete
  Stub.Advance(2)
  local z10 = ns.char.levels[10].z
  T.eq(Count(z10), 11, "10 largest + 'o'")
  T.ok(z10.o and SumAll(z10.o.s) > 0)
  Stub.Logout()
  local zones = ns.char.zones
  T.eq(Count(zones), 150)
  T.ok(zones[1454] ~= nil, "city zone kept")
  T.ok(zones[50160] ~= nil, "current zone kept")
end)

T.test("read-only mode: state computed, nothing written", function()
  local ns = Login({ schema = 99, chars = {} })
  T.ok(ns.readOnly)
  Stub.Advance(30)
  Stub.SetAFK(true)
  T.eq((State(ns)), "W")
  T.eq(SumAll(ns.char.life.s), 0, "no credit")
  local id, err = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(id, nil); T.eq(err, "readonly")
  T.no(ns.Tracker.ResetSession())
  Stub.Logout()
  T.eq(Count(Stub.saved.chars), 0, "no record created")
  T.eq(Stub.saved.lastVersion, nil)
end)

---------------------------------------------------------------------------
-- 13. allocations
---------------------------------------------------------------------------

T.test("steady state: 600 ticks allocate <= 1 KB, 20000 ticks retain < 16 KB, no OnUpdate", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(300)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks allocated %.2f KB"):format(kb))
  collectgarbage("collect")
  local m0 = collectgarbage("count")
  Stub.Advance(20000)
  collectgarbage("collect")
  local m1 = collectgarbage("count")
  T.ok(m1 - m0 < 16, ("retained %.2f KB"):format(m1 - m0))
  T.eq(Stub.onUpdateCount, 0)
  T.eq(ns.char.life.s.w, 20900)
end)

---------------------------------------------------------------------------
-- 14. continents are never zones (feedback F4)
---------------------------------------------------------------------------

local function AddKalimdorCity()
  Stub.maps[1456] = { mapType = 3, parentMapID = 1414, name = "Thunder Bluff" }
  Stub.maps[1412] = { mapType = 3, parentMapID = 1414, name = "Mulgore" }
  Stub.maps[1437] = { mapType = 3, parentMapID = 1415, name = "Wetlands" }
end

T.test("login on a continent map: no Kalimdor zone, the held seconds go to the city found next", function()
  AddKalimdorCity()
  local p = Stub.player
  p.mapID, p.resting, p.zoneText = 1414, true, "Thunder Bluff"   -- inn of Thunder Bluff
  local ns = Login()
  local spy = Spy(ns, "ZONE_KEY_CHANGED")
  Stub.Advance(2)
  T.eq(select(2, ns.Tracker.GetState()), nil, "no zone while the map is a continent")
  T.eq(SumAll(ns.char.life.s), 0, "seconds held, not credited")
  Stub.SetMap(1456)
  local ch = ns.char
  T.eq(ch.zones[1414], nil, "no Kalimdor bucket")
  T.eq(ch.levels[10].z[1414], nil)
  T.eq(ch.zones[1456].s.c, 2, "held seconds credited with the state once resolved (city)")
  T.eq(ch.life.s.i, nil, "never counted as inn time")
  T.near(ch.ema[1].d, 2, 0.01, "mask 0 clock advanced by the held seconds")
  T.near(ch.ema[5].d, 0, 1e-9, "city-excluded clock: the held seconds were city time")
  T.eq(spy.n, 1); T.eq(spy.args[1][1], 1456, "one ZONE_KEY_CHANGED, never with a continent")
  Stub.Advance(3)
  T.eq(ch.zones[1456].s.c, 5)
  -- a continent is never made a city
  p.mapID = 1414
  local id, err = ns.Tracker.ToggleCityForCurrentZone()
  T.eq(id, nil); T.eq(err, "nozone")
  T.eq(ns.db.cities[1414], nil)
end)

T.test("loading screen onto a continent map: seconds held, then credited to the new zone", function()
  AddKalimdorCity()
  local ns = Login()
  Stub.Advance(30)
  Stub.Fire("PLAYER_LEAVING_WORLD")
  Stub.Advance(20)                          -- the loading screen goes to the pre-load state
  Stub.player.mapID = 1415                  -- Eastern Kingdoms for the first seconds
  Stub.player.zoneText = "Wetlands"
  Stub.Fire("PLAYER_ENTERING_WORLD", false, false)
  Stub.Advance(3)
  local ch = ns.char
  T.eq(ch.zones[1415], nil)
  T.eq(ch.life.s.w, 50, "held seconds not credited yet")
  T.eq(select(2, ns.Tracker.GetState()), 1411, "zone unchanged while held")
  Stub.SetMap(1437)
  T.eq(ch.zones[1437].s.w, 3, "held seconds go to the first zone resolved afterwards")
  Stub.Advance(7)
  T.eq(ch.zones[1437].s.w, 10)
  T.eq(ch.zones[1411].s.w, 50)
  T.eq(ch.life.s.w, 60, "no second lost")
  T.eq(ch.levels[10].z[1415], nil)
  T.eq(ch.levels[10].z[1437].s.w, 10)
end)

T.test("a continent map beyond the cap: zone text key; held XP follows the seconds; no double count", function()
  AddKalimdorCity()
  local p = Stub.player
  p.mapID, p.zoneText = 1414, "Mulgore"
  local ns = Login()
  local C = ns.C
  Stub.Advance(5)                           -- XP baseline at +2 s
  Stub.GrantXP(100)
  Stub.Advance(1)
  local ch = ns.char
  T.eq(ch.life.xp, 100, "life XP written at once")
  T.eq(ch.levels[10].xp, 100)
  T.eq(ch.zones.nMulgore, nil, "zone part held")
  Stub.Advance(C.ZONE_HOLD_MAX - 6)         -- the install sync (+10 s) happened while held
  T.eq(select(2, ns.Tracker.GetState()), "nMulgore", "zone text after the cap")
  T.eq(ch.zones.nMulgore.s.w, C.ZONE_HOLD_MAX)
  T.eq(ch.zones.nMulgore.xp, 100)
  T.eq(ch.levels[10].z.nMulgore.xp, 100)
  T.eq(ns.Tracker.GetDelta().zones.nMulgore.xp, 100)
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 1, "held seconds not counted twice by the install")
  Stub.Advance(5)
  T.eq(ch.zones.nMulgore.s.w, C.ZONE_HOLD_MAX + 5, "the zone text while the map stays unresolved")
  Stub.SetMap(1412)
  Stub.Advance(4)
  T.eq(ch.zones[1412].s.w, 4, "a resolved map ends the fallback at once")
  T.eq(ch.zones[1414], nil)
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 1)
end)

T.test("logout while the map is unresolved: the held seconds are saved to the zone text", function()
  local p = Stub.player
  p.mapID, p.zoneText = 1414, "Durotar"
  Login()
  Stub.Advance(5)
  Stub.Logout()
  local ch = Stub.saved.chars[p.guid]
  T.eq(ch.zones[1414], nil)
  T.eq(ch.zones.nDurotar.s.w, 5)
  T.eq(ch.last.zone, "nDurotar")
end)

T.test("repair on load: continent buckets of old records move to the neutral zone", function()
  local db = { schema = 1, chars = { [Stub.player.guid] = {
    level = 10, base = { total = 1000, at = 1, level = 10 },
    life = { s = { w = 110, i = 2, c = 63 }, xp = 500 },
    zones = { [1414] = { s = { i = 2 }, xp = 0, name = "Kalimdor" },
              [947] = { s = { w = 10 }, xp = 50, name = "Azeroth" },
              [1411] = { s = { w = 100 }, xp = 450, name = "Durotar" },
              [1454] = { s = { c = 63 }, xp = 0, name = "Orgrimmar" },
              [2521] = { s = { w = 7 }, xp = 0, name = "Zephras" } },
    levels = { [10] = { s = { w = 110, i = 2, c = 63 }, xp = 500,
                        z = { [1414] = { s = { i = 2 }, xp = 0 }, [947] = { s = { w = 10 }, xp = 50 },
                              [1411] = { s = { w = 100 }, xp = 450 }, [1454] = { s = { c = 63 }, xp = 0 } } } },
    last = { key = "i", zone = 1414, level = 10, g = 1, at = 1 },
  } } }
  local ns = Login(db)
  local ch = ns.char
  T.eq(ch.zones[1414], nil); T.eq(ch.zones[947], nil)
  T.eq(ch.zones.o.s, { i = 2, w = 10 }); T.eq(ch.zones.o.xp, 50)
  T.eq(ch.zones[1411].s.w, 100, "zones untouched")
  T.eq(ch.zones[1454].s.c, 63)
  T.eq(ch.zones[2521].s.w, 7, "an island typed Continent (no zone below it) keeps its bucket")
  local z = ch.levels[10].z
  T.eq(z[1414], nil); T.eq(z[947], nil)
  T.eq(z.o.s, { i = 2, w = 10 }); T.eq(z.o.xp, 50)
  T.eq(ch.last.zone, "o", "last segment no longer points at a continent")
  local total = 0
  for _, zb in pairs(ch.zones) do total = total + SumAll(zb.s) end
  T.eq(total, 182, "no second lost")
end)

---------------------------------------------------------------------------
-- 15. pre-install XP/h estimate (feedback F1, requirement C)
---------------------------------------------------------------------------

-- The user's SavedVariables after the first in-game test (druid level 20, 58 XP,
-- 1 d 13 h played, 8 h 25 on this level, installed a minute before logout).
local USER_GUID = "Player-4619-00C0FFEE"
local function UserSV()
  local e0 = { a = 0, r = 0, q = 0 }
  local function E(d) return { a = e0.a, r = e0.r, q = e0.q, d = d } end
  return {
    xpMax = { [20] = 23200 },
    createdAt = 1790799275,
    settings = {
      rateTau = 3600, debug = false, exclude = { inn = false, afk = false, city = false },
      hidePlayedMsg = false, firstRunDone = true,
      widget = { scale = 1, fontSize = 11, point = { "CENTER", "CENTER", 0, -220 }, style = "bar",
                 shown = true, background = true, slots = { "eta", "xph", "fps_latency" }, fade = false,
                 locked = false, combatHide = false, hideAtMax = false,
                 maxSlots = { "session", "played", "fps_latency" }, height = 8, slot3Pos = "center",
                 pctPos = "follow", width = 360 },
      requestPlayedAtLogin = true,
    },
    lastVersion = "0.1.0-test",
    cities = {},
    schema = 1,
    chars = {
      [USER_GUID] = {
        last = { at = 1790799340, key = "c", zone = 1456, level = 20, g = 649327.767 },
        guid = USER_GUID,
        sessions = {},
        class = "DRUID",
        levels = { [20] = { partial = true, s = { u = 30328, c = 63, i = 2 }, xa = 0, xr = 0, d = 0, xp = 0, xq = 0,
                            z = { [1414] = { s = { i = 2 }, xp = 0 }, [1456] = { s = { c = 63 }, xp = 0 } },
                            max = 23200, srvStart = 104914 } },
        level = 20,
        base = { at = 1790799277, total = 135243, level = 20 },
        realm = "Classic Beta PvP",
        zones = { [1414] = { name = "Kalimdor", xp = 0, s = { i = 2 } },
                  [1456] = { name = "Thunder Bluff", xp = 0, s = { c = 63 } } },
        cur = { at = 1790799340, p0 = 0.003, t0 = 1790799275, g = 649327.767, s = { i = 2, c = 63 }, d = 0, xp = 0, l0 = 20 },
        ema = { E(64.47661824730345), E(64.47661824730345), E(61.80137601073682), E(61.80137601073682),
                E(2.721970436125817), E(2.721970436125817), E(0), E(0) },
        xpSnap = { at = 1790799340, max = 23200, level = 20, rest = 0, xp = 58 },
        life = { est = 0, s = { u = 135242, c = 63, i = 2 }, xa = 0, xr = 0, d = 0, xp = 0, xq = 0 },
        name = "Lutak",
        faction = "Horde",
        firstSeen = 1790799275,
        srv = { at = 1790799340, total = 135306, levelPlayed = 30392, level = 20, g = 649327.767, ext = true },
        lastSeen = 1790799340,
        surname = "Brisevent",
      },
    },
  }
end

local function UserWorld()
  AddKalimdorCity()
  local p = Stub.player
  p.guid, p.name, p.surname, p.realm = USER_GUID, "Lutak", "Brisevent", "Classic Beta PvP"
  p.class, p.classLocalized = "DRUID", "Druid"
  p.level, p.xp, p.max, p.rest = 20, 58, 23200, 0
  p.mapID, p.zoneText, p.resting = 1456, "Thunder Bluff", true
  Stub.server.total, Stub.server.levelPlayed = 135307, 30393
end

T.test("user's SV: estimate ~5.7k XP/h from the completed levels (v2), ETA ~4 h, Kalimdor repaired", function()
  UserWorld()
  local ns = Login(UserSV())
  local ch = ns.char
  T.eq(ch.prior, nil, "nothing before the first XP read")
  local xph0, _, _, _, _, status0 = ns.Stats.Rate(ch, 0)
  T.eq(xph0, nil); T.eq(status0, "nodata", "the old behaviour, fixed below")
  Stub.Advance(3)                           -- XP baseline at +2 s
  T.ok(ch.prior, "prior computed from the saved install baseline")
  -- R3: levels 1-19 (167 200 XP) over the /played before level 20 began (srvStart
  -- 104 914 s); the 8 h at the level 20 cap no longer count (v1 gave ~4.45k)
  local expected = 167200 * 3600 / 104914
  T.eq(ch.prior.v, 2)
  T.near(ch.prior.xph, expected, 1e-6)
  T.ok(ch.prior.xph > 5700 and ch.prior.xph < 5800, ("%.1f XP/h"):format(ch.prior.xph))
  for m = 0, 7 do
    local xph, A, R, Q, src, status = ns.Stats.Rate(ch, m)
    T.near(xph, expected, 1e-6, "mask " .. m)
    T.near(A, expected / 3600, 1e-9)
    T.eq(R, 0); T.eq(Q, 0)
    T.eq(src, "prior"); T.eq(status, "estimate")
  end
  local sec, status, src = ns.Stats.ETA(ch, 7, 58, 23200, 0, false)
  T.eq(status, "estimate"); T.eq(src, "prior")
  T.near(sec, 23142 * 3600 / expected, 1e-3)
  T.ok(sec > 3.8 * 3600 and sec < 4.3 * 3600, ("ETA %.2f h"):format(sec / 3600))
  -- F4 on the same data: Kalimdor merged into the neutral zone, Thunder Bluff kept
  T.eq(ch.zones[1414], nil)
  T.eq(ch.zones.o.s.i, 2)
  T.eq(ch.levels[20].z[1414], nil)
  T.eq(ch.levels[20].z.o.s.i, 2)
  T.ok(ch.zones[1456].s.c >= 63)
  -- the login /played changes nothing: computed once, never recomputed
  local prior = ch.prior
  Stub.Advance(20)
  T.ok(ch.prior == prior and ch.prior.xph == expected)
  -- persistence: restart and /reload
  ns = Stub.Restart({ offline = 3600 })
  Stub.Advance(3)
  T.near(ns.char.prior.xph, expected, 1e-6, "saved and restored")
  T.eq(select(6, ns.Stats.Rate(ns.char, 0)), "estimate")
  ns = Stub.Restart({ reload = true, offline = 2 })
  T.near(ns.char.prior.xph, expected, 1e-6, "kept across /reload")
end)

T.test("pre-install estimate: per character, never shared", function()
  UserWorld()
  local sv = UserSV()
  local other = "Player-4619-0BADF00D"
  sv.chars[other] = { guid = other, name = "Alt", level = 30, base = { total = 200000, at = 1, level = 30 },
                      life = { s = { u = 200000 }, xp = 0 }, levels = { [30] = { s = { u = 5000 }, xp = 0 } } }
  local ns = Login(sv)
  Stub.Advance(3)
  T.ok(ns.char.prior ~= nil)
  local alt = ns.db.chars[other]
  T.eq(alt.prior, nil, "another record is never touched")
  T.eq(select(6, ns.Stats.Rate(alt, 0)), "nodata")
  -- the alt logs in: its own estimate, the druid's unchanged
  local druidPrior = ns.char.prior.xph
  Stub.Logout()
  local saved = Stub.DeepCopy(Stub.saved)
  T.eq(#Stub.errors, 0, "no Lua error before the switch")
  Stub.Reset()
  AddKalimdorCity()
  local p = Stub.player
  p.guid, p.level, p.xp, p.max = other, 30, 1000, 47400
  _G.TruePlayedDB = saved
  ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(3)
  local xp30 = 0
  for l = 1, 29 do xp30 = xp30 + Stub.xpTable[l] end
  T.near(ns.char.prior.xph, (xp30 + 1000) * 3600 / 200000, 1e-6)
  T.near(ns.db.chars[USER_GUID].prior.xph, druidPrior, 1e-9)
end)

T.test("pre-install estimate at the install sync; conditions (level, time, XP table, client)", function()
  local function Fresh(level, xp, total, opts)
    T.eq(#Stub.errors, 0, "no Lua error in the previous case")
    Stub.Reset()
    opts = opts or {}
    if opts.interface then Stub.build.interface = opts.interface end
    local p = Stub.player
    p.level, p.xp, p.max = level, xp, opts.max or Stub.xpTable[level]
    Stub.server.total, Stub.server.levelPlayed = total, math.min(total, 600)
    local ns = Login(opts.db)
    Stub.Advance(15)                        -- baseline +2 s, login /played +10 s
    T.ok(ns.char.base, "install sync done")
    return ns, ns.char
  end
  -- level 20, 5000 XP, 48 h played, 10 min of it at level 20: v2 (R3), the completed
  -- levels over the /played before level 20 began (install total - its level time)
  local ns, ch = Fresh(20, 5000, 172800)
  local u = ch.life.s.u
  T.ok(u and u > 172000)
  T.ok(ch.base.lp and ch.base.lp >= 600 and ch.base.lp < 620, "level time at the install kept")
  T.eq(ch.prior.v, 2)
  T.near(ch.prior.xph, 167200 * 3600 / (ch.base.total - ch.base.lp), 1e-6)
  T.eq(select(6, ns.Stats.Rate(ch, 0)), "estimate")
  -- level 1 (fresh character) and level 2 with 20 min played: no estimate
  ns, ch = Fresh(1, 100, 900)
  T.eq(ch.prior, nil, "level 1")
  T.eq(select(6, ns.Stats.Rate(ch, 0)), "nodata")
  _, ch = Fresh(2, 100, 1200)
  T.eq(ch.prior, nil, "less than 30 min before the install")
  _, ch = Fresh(1, 100, 7200)
  T.eq(ch.prior, nil, "level 1 even with time")
  Stub.player.level, Stub.player.max = 2, 900
  Stub.Advance(60)
  T.eq(ch.prior, nil, "never computed later from a level-1 install")
  -- next to no /played per level (premade or boosted character): no estimate
  ns, ch = Fresh(58, 0, 7200)
  T.eq(ch.prior, nil, "level 58 after 2 h played: not an XP rate")
  T.eq(select(6, ns.Stats.Rate(ch, 0)), "nodata")
  _, ch = Fresh(20, 5000, 600 * 19 + 600)
  T.ok(ch.prior, "10 min of /played per level before the install is enough")
  -- the XP table does not match this client
  _, ch = Fresh(20, 5000, 172800, { max = 23000 })
  T.eq(ch.prior, nil, "UnitXPMax differs from the table")
  _, ch = Fresh(20, 5000, 172800, { db = { schema = 1, xpMax = { [15] = 14000 } } })
  T.eq(ch.prior, nil, "a learned size differs from the table")
  ns, ch = Fresh(20, 5000, 172800, { interface = 110205 })
  T.no(ns.isForever or ns.isEra)
  T.eq(ch.prior, nil, "other clients: no Classic table")
end)

T.test("transition: the estimate slides monotonically to the tracked rate, never nil", function()
  -- prior 3600 XP/h (levels 1-19: 167200 XP in the 167200 s before level 20), then a
  -- mob of 60 XP every 30 s (7200 XP/h)
  local p = Stub.player
  p.level, p.xp, p.max = 20, 5000, 23200
  Stub.server.total, Stub.server.levelPlayed = 172200, 5000
  local ns = Login()
  Stub.Advance(10.5)                        -- install sync at +10.1 s
  local ch = ns.char
  T.ok(ch.prior)
  T.near(ch.prior.xph, 3600, 1)
  local prev, last
  local seen = {}
  for k = 1, 80 do
    Stub.Advance(29.5)
    local xph = ns.Stats.Rate(ch, 0)
    T.ok(xph ~= nil, "never nil between kills")
    Stub.GrantXP(60)
    Stub.Advance(0.5)
    local v, _, _, _, src, status = ns.Stats.Rate(ch, 0)
    T.ok(v ~= nil, "never nil")
    seen[status] = true
    if prev then T.ok(v >= prev - 1e-6, ("kill %d: %.1f after %.1f"):format(k, v, prev)) end
    prev, last = v, { v = v, src = src, status = status }
    local sec, etaStatus = ns.Stats.ETA(ch, 0, p.xp, p.max, 0, false)
    T.ok(sec and sec > 0 and etaStatus == status, "ETA always shown")
  end
  T.ok(seen.estimate and seen.ok, "estimate first, then ok")
  T.eq(last.status, "ok"); T.eq(last.src, "ema")
  T.near(last.v, 7200, 7200 * 0.05, "tracked rate reached")
end)

---------------------------------------------------------------------------
-- 16. instance time: dungeons, raids, PvP (request A)
---------------------------------------------------------------------------

T.test("instance kinds: party / scenario -> d, raid -> r, pvp / arena -> p, AFK uppercase", function()
  local ns = Login()
  local spy = Spy(ns, "STATE_CHANGED")
  local cases = {
    { "party", "d" }, { "scenario", "d" }, { "raid", "r" }, { "pvp", "p" }, { "arena", "p" },
    { "neighborhood", "w" },                -- an instance type this version does not know
  }
  for _, c in ipairs(cases) do
    Stub.SetInstance(true, c[1], 500, nil)
    T.eq((State(ns)), c[2], c[1])
    Stub.SetAFK(true)
    T.eq((State(ns)), ns.C.KEY[c[2]][true], c[1] .. " AFK")
    Stub.SetAFK(false)
  end
  -- resting inside an instance: never inn time (nor city); taxi keeps precedence
  Stub.SetInstance(true, "raid", 409, nil)
  Stub.SetResting(true)
  T.eq((State(ns)), "r", "no inn inside an instance")
  Stub.SetResting(false)
  Stub.SetInstance(false, nil, 0, 1454)
  T.eq((State(ns)), "c", "back outside: city again")
  Stub.SetInstance(false, nil, 0, 1411)
  T.eq((State(ns)), "w")
  T.ok(spy.n >= 12, "STATE_CHANGED for every change")
  T.eq(spy.args[1][2], "w", "old key passed")
end)

T.test("instance seconds reach life, level, zone and session; AFK exclusion pauses D", function()
  local ns = Login()
  Stub.Advance(10)                          -- open world
  Stub.SetInstance(true, "party", 389, 90001)
  Stub.Advance(30)
  Stub.SetAFK(true); Stub.Advance(20); Stub.SetAFK(false)
  Stub.SetInstance(true, "raid", 409, nil)
  Stub.Advance(40)
  Stub.SetInstance(true, "pvp", 30, nil)
  Stub.Advance(15)
  Stub.SetAFK(true)
  local paused, why = ns.Tracker.IsPaused(1)
  T.ok(paused); T.eq(why, "afk")
  T.no((ns.Tracker.IsPaused(6)), "inn and city exclusions never pause instance time")
  Stub.Advance(5)
  Stub.SetAFK(false)
  Stub.SetInstance(false, nil, 0, 1411)
  Stub.Advance(1)
  local ch = ns.char
  local s = ch.life.s
  T.eq(s.w, 11); T.eq(s.d, 30); T.eq(s.D, 20); T.eq(s.r, 40); T.eq(s.p, 15); T.eq(s.P, 5)
  T.eq(ch.levels[10].s.d, 30)
  T.eq(ch.zones[90001].s.d, 30); T.eq(ch.zones[90001].s.D, 20)
  T.eq(ch.zones.i409.s.r, 40)
  T.eq(ch.zones.i30.s.p, 15); T.eq(ch.zones.i30.s.P, 5)
  T.eq(ch.levels[10].z.i409.s.r, 40)
  T.eq(ns.session.s.r, 40)
  T.eq(ns.Tracker.GetDelta().life.s.D, 20)
  T.eq(SumAll(s) - (s.u or 0), 121, "every second counted once (u = pre-install time)")
  local bd = ns.Stats.Breakdown(ch.life, {})
  T.eq(bd.world, 11); T.eq(bd.dungeon, 30); T.eq(bd.dungeonAll, 50); T.eq(bd.dungeonAfk, 20)
  T.eq(bd.raidAll, 40); T.eq(bd.pvpAll, 20); T.eq(bd.pvpAfk, 5); T.eq(bd.instAll, 110)
  T.eq(bd.active, 11 + 30 + 40 + 15); T.eq(bd.afk, 25)
  T.eq(ns.Stats.InstanceTime(ch.life, 1), 85, "AFK excluded")
  T.eq(ns.Stats.InstanceTime(ns.session, 0), 110)
  -- rates: excluded instance AFK does not advance the AFK-excluded clock
  T.near(ch.ema[1].d - ch.ema[2].d, 25, 1, "D and P seconds only in mask 0 (decayed a little)")
end)

T.test("old records: instance time counted as w stays w (no migration)", function()
  local db = { schema = 1, sparseSettings = true, chars = { [Stub.player.guid] = {
    level = 10, base = { total = 1000, at = 1, level = 10 },
    life = { s = { w = 5000, u = 1000 }, xp = 0 },
    levels = { [10] = { s = { w = 5000 }, xp = 0, z = { [90001] = { s = { w = 3000 }, xp = 0 } } } },
    zones = { [90001] = { s = { w = 3000 }, xp = 0, name = "Ragefire Chasm" } },
  } } }
  local ns = Login(db)
  local ch = ns.char
  T.eq(ch.zones[90001].s, { w = 3000 })
  T.eq(ch.life.s.w, 5000)
  Stub.SetInstance(true, "party", 389, 90001)
  Stub.Advance(10)
  T.eq(ch.zones[90001].s, { w = 3000, d = 10 }, "new seconds are dungeon time")
  local rows = {}
  T.eq(ns.Stats.TopInstances(ch.zones, 0, 5, rows), 1)
  T.eq(rows[1].secs, 10, "only the new dungeon seconds are instance time")
end)

T.test("steady state in a raid (and AFK in a dungeon): 600 ticks allocate <= 1 KB", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.SetInstance(true, "raid", 409, nil)
  Stub.Advance(300)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks in a raid allocated %.2f KB"):format(kb))
  Stub.SetInstance(true, "party", 389, 90001)
  Stub.SetAFK(true)
  Stub.Advance(60)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 AFK ticks in a dungeon allocated %.2f KB"):format(kb))
  -- state changes between known keys and zones allocate nothing either
  Stub.SetAFK(false)
  Stub.Advance(2)
  kb = T.alloc(function(i)
    Stub.player.afk = i % 2 == 0
    Stub.Fire("PLAYER_FLAGS_CHANGED", "player")
    Stub.Advance(1)
  end, 200)
  T.ok(kb <= 1, ("200 AFK toggles allocated %.2f KB"):format(kb))
  T.eq(ns.char.life.s.r, 900)
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- 17. kills: char.lastKill (mobs to the next level, request E)
---------------------------------------------------------------------------

-- A logged-in character with a valid XP baseline.
local function KillLogin(db)
  local ns = Login(db)
  Stub.Advance(3)
  return ns
end

T.test("a kill with its combat XP message records the base XP, level and time", function()
  local ns = KillLogin()
  T.eq(ns.char.lastKill, nil, "none yet")
  local spy = Spy(ns, "XP_CHANGED")
  Stub.Kill(120)
  Stub.Advance(1)
  T.eq(ns.char.lastKill, { xp = 120, level = 10, at = time() })
  T.ok(spy.n >= 1, "XP_CHANGED after the kill")
  local lk = ns.char.lastKill
  Stub.Advance(5)
  Stub.Kill(95, { marker = "after" })       -- message after the XP update: same result
  Stub.Advance(1)
  T.ok(ns.char.lastKill == lk, "the table is reused")
  T.eq(lk.xp, 95)
  T.eq(ns.char.life.xa, 215)
end)

T.test("rested kills record the base XP, without the rested bonus", function()
  Stub.player.rest = 1000
  local ns = KillLogin()
  Stub.Kill(100)                            -- 200 XP, pool -200
  Stub.Advance(1)
  T.eq(ns.char.life.xr, 100)
  T.eq(ns.char.lastKill.xp, 100)
  Stub.player.rest = 50
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
  Stub.Kill(100)                            -- the pool runs out: 125 XP
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 100, "partial bonus removed too")
end)

T.test("quest rewards are never kills, even with their own XP message", function()
  local ns = KillLogin()
  Stub.Kill(80)
  Stub.Advance(1)
  Stub.Advance(5)
  -- a quest turn-in: QUEST_TURNED_IN, XP, then "You gain 400 experience."
  Stub.GrantXP(400, { quest = 400 })
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 400 experience.")
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 80, "the quest did not replace the last kill")
  -- the quest's message first, then the turn-in
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 300 experience.")
  Stub.GrantXP(300, { quest = 300 })
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 80)
  -- a kill and a quest reward in the same batch: the kill part only
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 70 experience.")
  Stub.GrantXP(270, { quest = 200 })
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 200 experience.")
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 70)
  T.eq(ns.char.life.xq, 900)
end)

T.test("discoveries are never kills; grey mobs (0 XP) change nothing", function()
  local ns = KillLogin()
  Stub.Kill(60)
  Stub.Advance(5)
  Stub.Discover(250)                        -- system message, no combat XP message
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 60, "discovery XP ignored")
  -- rested discovery: no pool drop, classified as quest/other by the XP chain
  Stub.player.rest = 500
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
  Stub.Discover(250)
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 60)
  -- a grey mob: no XP, no message
  Stub.Kill(0, { marker = false })
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 60)
  -- a stray message without XP expires: the next kill (rested) is not halved
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "?")
  Stub.Advance(5)
  Stub.Kill(90)
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 90)
  T.eq(Stub.player.rest, 500 - 180, "the kill used the pool, the discoveries did not")
end)

T.test("a kill right after a discovery records the kill, whichever of its message and XP comes first", function()
  local ns = KillLogin()
  Stub.Kill(60)                             -- messages seen in this load
  Stub.Advance(5)
  -- discovery XP processed (waiting, no message), a kill's message 0.5 s later
  Stub.Discover(80)
  Stub.Advance(0.5)
  Stub.Kill(145)                            -- message, then XP
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 145, "message first: the kill, not the discovery")
  Stub.Discover(90)
  Stub.Advance(0.5)
  Stub.Kill(150, { marker = "after" })      -- XP, then its message before the batch runs
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 150, "message after the XP: the kill, not the discovery")
  -- away from any subzone change, a late message still validates the waiting gain
  Stub.Advance(5)
  Stub.Kill(75, { marker = false })
  Stub.Advance(0.5)
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "late")
  T.eq(ns.char.lastKill.xp, 75)
end)

T.test("area damage: several kills in one batch give the XP of one kill", function()
  local ns = KillLogin()
  Stub.Kill(110, { count = 4 })
  Stub.Advance(1)
  T.eq(ns.char.life.xa, 440)
  T.eq(ns.char.lastKill.xp, 110)
  Stub.player.rest = 300                    -- rested for 1.5 kills of the next pull
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
  Stub.Kill(100, { count = 3 })             -- 200 + 150 + 100 XP
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 100)
end)

T.test("group kills: the share of this character is the kill XP", function()
  local ns = KillLogin()
  Stub.Kill(37)                             -- a 5-player group share
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 37)
end)

T.test("a late message (after the XP was processed) still marks the kill", function()
  local ns = KillLogin()
  Stub.Kill(50)                             -- messages seen in this load
  Stub.Advance(5)
  local spy = Spy(ns, "XP_CHANGED")
  Stub.Kill(75, { marker = false })
  Stub.Advance(0.5)                         -- XP processed, no message yet
  T.eq(ns.char.lastKill.xp, 50)
  local n = spy.n
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "late")
  T.eq(ns.char.lastKill.xp, 75)
  T.eq(spy.n, n + 1, "XP_CHANGED for the tokens")
  -- once messages are seen, a gain without one outside an instance is not a kill
  Stub.Advance(5)
  Stub.GrantXP(40)
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 75)
end)

T.test("inside instances the message text is secret and never read; a missing message falls back", function()
  local ns = KillLogin()
  Stub.Kill(50)                             -- messages seen outside
  Stub.Advance(1)
  Stub.SetInstance(true, "party", 389, 90001)
  Stub.Advance(5)
  Stub.Kill(140)                            -- secret text inside the instance
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 140)
  T.eq(#Stub.errors, 0, "the secret text was not touched")
  -- messages suppressed by the client inside the instance: accepted after the window
  Stub.Kill(160, { marker = false })
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 140, "waits for a possible message")
  Stub.Advance(4)
  T.eq(ns.char.lastKill.xp, 160, "accepted without a message inside an instance")
end)

T.test("no combat XP message on this client: non-quest gains are kills, except discoveries", function()
  Stub.unknownEvents.CHAT_MSG_COMBAT_XP_GAIN = true   -- the event cannot even be registered
  local ns = KillLogin()
  T.eq(#Stub.errors, 0)
  local spy = Spy(ns, "XP_CHANGED")
  Stub.Kill(65)
  Stub.Advance(1)
  T.eq(ns.char.lastKill, nil, "decided after the discovery window")
  local n = spy.n
  Stub.Advance(4)
  T.eq(ns.char.lastKill.xp, 65)
  T.eq(spy.n, n + 1, "XP_CHANGED when it is decided")
  Stub.Discover(300)                        -- zone change first
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 65, "discovery ignored")
  Stub.Advance(5)
  Stub.GrantXP(210)
  Stub.Fire("ZONE_CHANGED")                 -- zone change right after the XP
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 65, "discovery ignored (zone change after the XP)")
  Stub.GrantXP(300, { quest = 300 })
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 65, "quest ignored")
  Stub.Advance(5)
  Stub.Kill(66)
  Stub.Advance(1)
  Stub.Kill(67)                             -- a newer gain settles the previous one
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 67)
end)

T.test("XP secret during a fight: the kills' messages divide the XP read after combat", function()
  local ns = KillLogin()
  Stub.Kill(40)                             -- messages seen in this load
  Stub.Advance(5)
  Stub.SetInstance(true, "party", 389, 90001)
  Stub.Advance(5)
  Stub.EnterCombat()
  Stub.secret.xp = true                     -- a 12.x client may hide XP values in combat
  for _ = 1, 3 do
    Stub.Kill(130)                          -- one message per kill, seconds apart
    Stub.Advance(4)
  end
  T.eq(ns.char.lastKill.xp, 40, "nothing read during the fight")
  Stub.secret.xp = false
  Stub.LeaveCombat()
  Stub.Advance(1)
  T.eq(ns.char.life.xa, 40 + 390)
  T.eq(ns.char.lastKill.xp, 130, "390 XP over 3 messages")
  -- the same fight without any message (suppressed): an unknown number of kills
  Stub.EnterCombat()
  Stub.secret.xp = true
  Stub.Kill(150, { marker = false }); Stub.Advance(4)
  Stub.Kill(150, { marker = false }); Stub.Advance(4)
  Stub.secret.xp = false
  Stub.LeaveCombat()
  Stub.Advance(5)
  T.eq(ns.char.lastKill.xp, 130, "not recorded as one 300 XP kill")
end)

T.test("the kill that levels up is recorded at the level it was made", function()
  Stub.player.xp = Stub.player.max - 100
  local ns = KillLogin()
  Stub.Kill(300)
  Stub.Advance(1)
  T.eq(Stub.player.level, 11)
  T.eq(ns.char.lastKill.xp, 300)
  T.eq(ns.char.lastKill.level, 10)
end)

T.test("last kill: saved per character, kept across restart and /reload", function()
  local ns = KillLogin()
  Stub.Kill(88)
  Stub.Advance(1)
  local at = ns.char.lastKill.at
  ns = Stub.Restart({ offline = 600 })
  T.eq(ns.char.lastKill, { xp = 88, level = 10, at = at })
  ns = Stub.Restart({ reload = true, offline = 2 })
  T.eq(ns.char.lastKill.xp, 88)
  local n, base = ns.Stats.KillsToLevel(ns.char, Stub.player.xp, Stub.player.max, 0)
  T.eq(base, 88)
  T.eq(n, math.ceil((Stub.player.max - Stub.player.xp) / 88))
  -- another character of the account: its own record, nothing shared
  Stub.Logout()
  local saved = Stub.DeepCopy(Stub.saved)
  Stub.Reset()
  local p = Stub.player
  local first = p.guid
  p.guid, p.name, p.level, p.xp, p.max = "Player-4619-0BADF00D", "Alt", 30, 100, 47400
  local alt = KillLogin(saved)
  T.eq(alt.char.lastKill, nil, "the alt has no last kill")
  T.eq(alt.Stats.KillsToLevel(alt.char, 100, 47400, 0), nil)
  Stub.Kill(400)
  Stub.Advance(1)
  T.eq(alt.char.lastKill.xp, 400)
  T.eq(alt.db.chars[first].lastKill.xp, 88, "the first character's kill untouched")
end)

T.test("last kill: late SV swap carries this load's kill; reset char clears it; max level and read-only", function()
  Login()
  Stub.Advance(3)
  Stub.Kill(44)
  Stub.Advance(5)
  Stub.Logout()
  local real = Stub.DeepCopy(Stub.saved)
  real.chars[Stub.player.guid].lastKill = { xp = 44, level = 10, at = 1 }
  Stub.Reset({ keepWorld = true })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(3)
  Stub.Kill(52)
  Stub.Advance(1)
  _G.TruePlayedDB = real
  Stub.Advance(2)
  T.ok(ns.db == real, "swapped")
  T.eq(ns.char.lastKill.xp, 52, "this load's kill wins over the older saved one")
  T.ok(ns.Core.ResetChar(Stub.player.guid))
  T.eq(ns.char.lastKill, nil, "reset with the rest of the record")
  -- max level: nothing recorded
  Stub.Reset()
  local P = Stub.player
  P.level, P.xp, P.max = 60, 0, 209800
  ns = KillLogin()
  Stub.Kill(500)
  Stub.Advance(5)
  T.eq(ns.char.lastKill, nil)
  -- read-only: nothing written
  Stub.Reset()
  ns = KillLogin({ schema = 99, chars = {} })
  Stub.Kill(500)
  Stub.Advance(5)
  T.eq(ns.char.lastKill, nil)
end)

T.test("kill tracking allocates nothing per tick; one table per record", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(3)
  Stub.Kill(30)
  Stub.Advance(5)
  local lk = ns.char.lastKill
  for _ = 1, 20 do
    Stub.Kill(30, { marker = false })       -- waiting gains, settled by the tick
    Stub.Advance(5)
  end
  T.ok(ns.char.lastKill == lk, "same table")
  Stub.Advance(60)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks allocated %.2f KB"):format(kb))
end)

---------------------------------------------------------------------------
-- 18. round 3 (C1): time without XP - stall guard (R1)
---------------------------------------------------------------------------

local function Copy(t)
  local o = {}
  for k, v in pairs(t) do o[k] = v end
  return o
end

-- A logged-in level 10 character with a warm EMA: n mobs of 100 XP, one every 36 s.
local function WarmLogin(n, db)
  local ns = Login(db)
  for _ = 1, n or 50 do
    Stub.Advance(36)
    Stub.Kill(100)
  end
  Stub.Advance(1)
  return ns
end

T.test("stall: past 20 min of non-AFK play without XP the EMA freezes, the time goes to xs", function()
  local ns = WarmLogin(50)
  local C, ch, Tracker = ns.C, ns.char, ns.Tracker
  local stalled, secs = Tracker.GetStall()
  T.no(stalled); T.ok(secs < 2, "count restarted by the last gain")
  -- AFK time is not counted (it still lowers the AFK-included rate, as before)
  Stub.SetAFK(true)
  Stub.Advance(1800)
  Stub.SetAFK(false)
  local _, n0 = Tracker.GetStall()
  T.ok(n0 < 2, "AFK seconds are not time without XP")
  -- just under 20 min of play: still decaying, status "ok"
  Stub.Advance(C.XP_STALL - n0 - 5)
  T.no((Tracker.GetStall()))
  T.eq(select(6, ns.Stats.Rate(ch, 0)), "ok")
  T.eq(ch.levels[10].xs.w, 0, "nothing withheld yet")
  Stub.Advance(10)                             -- the stall starts in this step
  local st, n1 = Tracker.GetStall()
  T.ok(st); T.ok(n1 > C.XP_STALL)
  local e0, e7 = Copy(ch.ema[1]), Copy(ch.ema[8])
  local xph, _, _, _, src, status, _, stallSecs = ns.Stats.Rate(ch, 0)
  T.eq(status, "stalled"); T.eq(src, "ema"); T.near(stallSecs, n1, 1e-9)
  local sec, etaStatus, _, _, etaStall = ns.Stats.ETA(ch, 0, Stub.player.xp, Stub.player.max, 0, false)
  T.ok(sec > 0); T.eq(etaStatus, "stalled"); T.near(etaStall, n1, 1e-9)
  -- hours more in the world, a city and AFK: the EMA neither decays nor grows
  Stub.Advance(3600)
  Stub.SetMap(1454)
  Stub.Advance(600)
  Stub.SetAFK(true)
  Stub.Advance(300)
  Stub.SetAFK(false)
  Stub.SetMap(1411)
  T.eq(ch.ema[1], e0, "mask 0 frozen")
  T.eq(ch.ema[8], e7, "mask 7 frozen")
  T.near((ns.Stats.Rate(ch, 0)), xph, 1e-9)
  -- the withheld seconds, per state key, in the level, in life and in the delta
  local xs = ch.levels[10].xs
  T.near(xs.w, 3600 + 5, 2)
  T.eq(xs.c, 600); T.eq(xs.C, 300)
  T.near(ch.life.xs.w, xs.w, 1e-9); T.eq(ch.life.xs.c, 600)
  T.eq(Tracker.GetDelta().levels[10].xs.c, 600)
  T.near(select(2, Tracker.GetStall()), n1 + 4200, 2, "world and city count, AFK does not")
  T.ok(ch.levels[10].s.w >= xs.w, "stalled time is a part of the level time")
  -- an XP gain ends it: count at 0, the EMA gets the XP and runs again
  Stub.Kill(100)
  Stub.Advance(1)
  st, secs = Tracker.GetStall()
  T.no(st); T.ok(secs <= 1, "count restarted at the gain")
  T.eq(select(6, ns.Stats.Rate(ch, 0)), "ok")
  T.ok(ch.ema[1].a > e0.a, "the gain reaches the EMA")
  T.near(ch.ema[1].d, e0.d, 2, "a warm EMA is not restarted")
  local w1 = xs.w
  Stub.Advance(60)
  T.eq(xs.w, w1, "nothing withheld any more")
  T.ok(ch.ema[1].d ~= e0.d, "the EMA decays again")
end)

T.test("stall at a level without any XP (installed at the cap): the first gains are not diluted", function()
  local P = Stub.player
  P.level, P.xp, P.max = 20, 58, 23200
  Stub.server.total, Stub.server.levelPlayed = 135243, 30329   -- the user's druid at install
  local ns = Login()
  Stub.Advance(12)                              -- install sync (+10 s)
  local ch = ns.char
  T.eq(ch.prior.v, 2)
  local prior = ch.prior.xph
  T.near(prior, 167200 * 3600 / 104914, 5)
  -- 2 h at the cap: stalled after 20 min, and then the whole level is stalled time
  Stub.Advance(7200)
  T.ok((ns.Tracker.GetStall()))
  local lb = ch.levels[20]
  T.near(lb.xs.w, lb.s.w, 1, "all the level time")
  T.eq(ch.ema[1].a, 0)
  T.ok(ch.ema[1].d > 600, "the EMA clock holds time without XP only")
  local _, _, _, _, src, status = ns.Stats.Rate(ch, 0)
  T.eq(src, "prior"); T.eq(status, "stalled")
  -- the cap is raised: a mob of 145 XP every 40 s (13 050 XP/h). Without the stall
  -- guard the first kill gave ~70 XP/h (145 XP over 2 h) and a time to level in days.
  local lo = math.min(prior, 13050)
  for k = 1, 60 do
    Stub.Kill(145)
    Stub.Advance(1)
    for _, m in ipairs({ 0, 7 }) do
      local xph = ns.Stats.Rate(ch, m)
      T.ok(xph and xph > 0.7 * lo, ("kill %d, mask %d: %.0f XP/h"):format(k, m, xph or -1))
      local sec = ns.Stats.ETA(ch, m, P.xp, P.max, 0, false)
      T.ok(sec and sec < 23200 * 3600 / (0.7 * lo), ("kill %d: ETA %.1f h"):format(k, (sec or 0) / 3600))
    end
    Stub.Advance(39)
  end
  local xph, _, _, _, _, status2 = ns.Stats.Rate(ch, 0)
  T.eq(status2, "ok")
  T.near(xph, 13050, 13050 * 0.15, "the tracked rate once warm")
end)

T.test("stall: persisted across logout and /reload, per character; zero entries never saved", function()
  local ns = WarmLogin(10)
  local C, ch = ns.C, ns.char
  Stub.Logout()
  T.eq(Stub.saved.chars[Stub.player.guid].levels[10].xs, nil, "no stalled time: nothing saved")
  T.eq(Stub.saved.chars[Stub.player.guid].life.xs, nil)
  ns = Stub.Restart({ crash = true })
  Stub.Advance(C.XP_STALL + 100)
  local st, n = ns.Tracker.GetStall()
  T.ok(st)
  local e = Copy(ns.char.ema[1])
  ns = Stub.Restart({ offline = 3600 })
  T.ok((ns.Tracker.GetStall()), "still stalled after a restart")
  T.near(select(2, ns.Tracker.GetStall()), n, 2)
  Stub.Advance(600)
  T.eq(ns.char.ema[1].a, e.a, "still frozen")
  local saved = Stub.saved.chars[Stub.player.guid]
  T.ok(saved.levels[10].xs.w > 90, "stalled seconds saved")
  T.eq(saved.levels[10].xs.i, nil, "zero entries are not saved")
  ns = Stub.Restart({ reload = true, online = 2 })
  T.ok((ns.Tracker.GetStall()), "kept across /reload")
  -- another character: its own count
  Stub.Logout()
  local db = Stub.DeepCopy(Stub.saved)
  Stub.Reset()
  Stub.player.guid = "Player-4619-0BADF00D"
  _G.TruePlayedDB = db
  ns = Stub.LoadAddon()
  Stub.LoginSequence()
  T.no((ns.Tracker.GetStall()), "a new character is not stalled")
  T.ok(ns.db.chars["Player-4619-00A629CA"].noXP > C.XP_STALL, "the other record untouched")
  T.eq(ns.char.life.xs and ns.char.life.xs.w or 0, 0)
  T.eq(ch.guid, "Player-4619-00A629CA")
end)

T.test("stall and cap: zero allocation per tick, onset included", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(3)
  Stub.Kill(100)
  Stub.Advance(1000)
  -- the stall starts inside the measured ticks
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok((ns.Tracker.GetStall()))
  T.ok(kb < 0.1, ("600 ticks around the stall onset allocated %.3f KB"):format(kb))
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb < 0.1, ("600 stalled ticks allocated %.3f KB"):format(kb))
  -- stalled AFK (the first AFK second creates the AFK key of the time buckets, as
  -- always; the stalled maps already hold every key)
  Stub.SetAFK(true)
  Stub.Advance(5)
  kb = T.alloc(function() Stub.Advance(1) end, 300)
  T.ok(kb < 0.1, ("300 stalled AFK ticks allocated %.3f KB"):format(kb))
  Stub.SetAFK(false)
  -- capped: kills without XP, then ticks
  Stub.Kill(100)
  Stub.Advance(5)
  for _ = 1, 3 do
    Stub.KillNoXP()
    Stub.Advance(20)
  end
  T.ok(ns.Tracker.IsMax(), "capped")
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb < 0.1, ("600 capped ticks allocated %.3f KB"):format(kb))
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("stall: records from before the stall guard get their count at login", function()
  local P = Stub.player
  local guid = P.guid
  local function Rec(levelXP)
    return { schema = 1, sparseSettings = true, chars = { [guid] = {
      guid = guid, level = 10, base = { total = 300000, at = 1, level = 9 },
      life = { s = { w = 4000, W = 500, c = 900, u = 290000 }, xp = levelXP },
      levels = { [10] = { s = { w = 3000, W = 500, c = 900 }, xp = levelXP, xa = levelXP, xr = 0, xq = 0 } },
    } } }
  end
  -- a level without XP: its non-AFK time (3900 s) is time without XP, and stalled time
  local ns = Login(Rec(0))
  local ch = ns.char
  T.near(ch.noXP, 3900, 1)
  T.ok((ns.Tracker.GetStall()))
  T.eq(ch.levels[10].xs.w, 3000); T.eq(ch.levels[10].xs.W, 500); T.eq(ch.levels[10].xs.c, 900)
  T.eq(ch.life.xs.w, 3000)
  -- a level with XP: the count starts at 0 (the time of its last gain is unknown)
  Stub.Reset()
  ns = Login(Rec(1500))
  T.near(ns.char.noXP, 0, 1)
  T.no((ns.Tracker.GetStall()))
  T.eq(ns.char.levels[10].xs.w, 0)
end)

---------------------------------------------------------------------------
-- 19. round 3 (C2): server level cap (R2)
---------------------------------------------------------------------------

local function Misses(ns)
  return (select(3, ns.Tracker.GetCapInfo()))
end

T.test("server cap: 3 kills in a row without XP set the cap; time withheld; XP again resumes", function()
  local ns = WarmLogin(30)
  local ch, Tracker, P = ns.char, ns.Tracker, Stub.player
  local xp0 = ch.life.xp
  local spy = Spy(ns, "XP_CHANGED")
  Stub.KillNoXP()
  Stub.Advance(20)
  local capL, isCap, misses = Tracker.GetCapInfo()
  T.eq(capL, nil); T.eq(isCap, false); T.eq(misses, 1)
  Stub.KillNoXP()
  Stub.Advance(20)
  T.eq(Misses(ns), 2); T.no(Tracker.IsMax())
  local n0 = spy.n
  Stub.KillNoXP()
  capL, isCap, misses = Tracker.GetCapInfo()
  T.eq(capL, 10); T.eq(isCap, true); T.eq(misses, 3)
  T.ok(Tracker.IsMax(), "the cap counts as max level")
  T.ok(spy.n > n0, "XP_CHANGED sent at once")
  T.eq(ch.capLevel, 10)
  -- while capped: EMA frozen, time withheld, ETA "max" for the caller
  local e = Copy(ch.ema[1])
  Stub.Advance(3600)
  Stub.KillNoXP()
  T.eq(ch.ema[1], e)
  T.near(ch.levels[10].xs.w, 3610, 3)
  T.eq(select(2, ns.Stats.ETA(ch, 0, P.xp, P.max, 0, Tracker.IsMax())), "max")
  -- XP again: the cap is over by itself (the chain is never cut by a detected cap)
  Stub.Kill(100)
  Stub.Advance(1)
  capL, isCap, misses = Tracker.GetCapInfo()
  T.eq(capL, nil); T.eq(isCap, false); T.eq(misses, 0)
  T.no(Tracker.IsMax()); T.eq(ch.capLevel, nil)
  T.eq(ch.life.xp, xp0 + 100, "the gain counted")
  T.ok(ch.ema[1].a > e.a)
  T.eq(#Stub.errors, 0)
end)

T.test("server cap: every guard of a miss", function()
  local ns = WarmLogin(5)
  local Tracker = ns.Tracker
  -- one fight: target fields, then what happens before the end of combat
  local function Fight(t, during)
    Stub.SetTarget(t)
    Stub.EnterCombat()
    Stub.Advance(5)
    if Stub.target then Stub.target.dead = true end
    if during then during() end
    Stub.LeaveCombat()
    Stub.Advance(2)
  end
  -- each case from a count of 0 (an XP gain resets it), so that no cap is set
  local function Case(name, t, during, expected)
    Stub.Kill(20)
    Stub.Advance(2)
    T.eq(Misses(ns), 0)
    Fight(t, during)
    T.eq(Misses(ns), expected, name)
  end
  Case("an eligible mob", {}, nil, 1)
  -- target not dead at the end of combat
  Case("alive", {}, function() Stub.target.dead = false end, 0)
  Case("a player", { isPlayer = true }, nil, 0)
  Case("a pet", { playerControlled = true }, nil, 0)
  Case("tapped by someone else", { tapDenied = true }, nil, 0)
  Case("not attackable", { canAttack = false }, nil, 0)
  Case("trivial", { classification = "trivial" }, nil, 0)
  Case("minion", { classification = "minus" }, nil, 0)
  Case("critter", { creatureType = "Critter" }, nil, 0)
  Case("critter (frFR)", { creatureType = "Bestiole" }, nil, 0)
  Case("totem", { creatureType = "Totem" }, nil, 0)
  T.eq(Tracker._GreyLevel(10), 4)
  Case("grey (level 4 at 10)", { level = 4 }, nil, 0)
  Case("not grey (level 5 at 10)", { level = 5 }, nil, 1)
  -- in a party the grey check uses the highest level (Classic: no XP for anyone from a
  -- mob grey for that member, e.g. a low-level character run through by a level 60)
  Stub.party[2] = 60
  T.eq(Tracker._GreyLevel(60), 51)
  Case("grey for a level 60 party member", { level = 12 }, nil, 0)
  Case("not grey for the party member", { level = 52 }, nil, 1)
  Stub.party[2] = 8
  Case("a lower party member changes nothing", { level = 5 }, nil, 1)
  Stub.party[2] = nil
  -- a target that was already dead when it became the target (an old corpse)
  Case("a corpse targeted in combat", {}, function() Stub.SetTarget({ dead = true }) end, 0)
  -- the target changed during the fight to a live mob that then died: counted
  Case("switched to another live mob", { level = 2 }, function()
    Stub.SetTarget({})
    Stub.target.dead = true
  end, 1)
  Case("skull level", { level = -1 }, nil, 1)
  -- no target at the end
  Case("no target", {}, function() Stub.SetTarget(nil) end, 0)
  -- a kill marker in the fight: XP was given
  Case("kill marker", {}, function() Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "x") end, 0)
  -- XP changed during the fight without a marker (read directly at its end)
  Case("XP changed", {}, function() Stub.GrantXP(50) end, 0)
  -- two misses, then an XP gain: the count restarts
  Fight({}); Fight({})
  T.eq(Misses(ns), 2)
  Fight({}, function() Stub.GrantXP(50) end)
  T.eq(Misses(ns), 0, "an XP gain resets the count")
  T.no(Tracker.IsMax())
  -- a combat that started before the addon saw it (no PLAYER_REGEN_DISABLED)
  Stub.SetTarget({ dead = true })
  Stub.LeaveCombat()
  T.eq(Misses(ns), 0)
  -- a level-up restarts the count
  Fight({}); Fight({})
  T.eq(Misses(ns), 2)
  Stub.GrantXP(Stub.player.max)                -- ding 11
  Stub.Advance(2)
  T.eq(Stub.player.level, 11)
  T.eq(Misses(ns), 0)
  T.eq(#Stub.errors, 0)
end)

T.test("server cap: secret, missing or failing APIs decide nothing", function()
  local ns = WarmLogin(5)
  local function Fight()
    Stub.SetTarget({})
    Stub.EnterCombat()
    Stub.Advance(5)
    Stub.target.dead = true
    Stub.LeaveCombat()
    Stub.Advance(2)
  end
  Stub.secret.target = true
  Fight(); Fight(); Fight(); Fight()
  T.eq(Misses(ns), 0, "secret target")
  T.no(ns.Tracker.IsMax())
  Stub.secret.target = false
  Stub.secret.xp = true
  Fight()
  T.eq(Misses(ns), 0, "secret XP")
  Stub.secret.xp = false
  Stub.Advance(1)
  for _, name in ipairs({ "UnitExists", "UnitIsTapDenied", "UnitCanAttack", "UnitClassification",
                          "UnitCreatureType", "UnitIsPlayer" }) do
    local saved = _G[name]
    _G[name] = nil
    Fight()
    T.eq(Misses(ns), 0, name .. " missing")
    _G[name] = function() error("API change") end
    Fight()
    T.eq(Misses(ns), 0, name .. " failing")
    _G[name] = saved
  end
  -- UnitIsDead missing: UnitIsDeadOrGhost is used instead (the stub answers false for
  -- the target: never dead, so nothing is counted)
  local isDead = _G.UnitIsDead
  _G.UnitIsDead = nil
  Fight()
  T.eq(Misses(ns), 0)
  _G.UnitIsDead = isDead
  -- UnitPlayerControlled is an extra filter: without it a miss still counts
  local pc = _G.UnitPlayerControlled
  _G.UnitPlayerControlled = nil
  Fight()
  T.eq(Misses(ns), 1)
  _G.UnitPlayerControlled = pc
  T.eq(#Stub.errors, 0, "no error reported")
end)

T.test("server cap: persisted per character; over at a new level; kept across /reload", function()
  local ns = WarmLogin(5)
  for _ = 1, 3 do Stub.KillNoXP(); Stub.Advance(10) end
  T.ok(ns.Tracker.IsMax())
  ns = Stub.Restart({ offline = 7200 })
  T.ok(ns.Tracker.IsMax(), "capped after a restart")
  local capL, isCap, misses = ns.Tracker.GetCapInfo()
  T.eq(capL, 10); T.eq(isCap, true); T.eq(misses, 3)
  local e = Copy(ns.char.ema[1])
  Stub.Advance(600)
  T.eq(ns.char.ema[1], e, "still withheld")
  ns = Stub.Restart({ reload = true, online = 2 })
  T.ok(ns.Tracker.IsMax(), "kept across /reload")
  -- another character is never capped by this one
  Stub.Logout()
  local db = Stub.DeepCopy(Stub.saved)
  Stub.Reset()
  Stub.player.guid = "Player-4619-0BADF00D"
  _G.TruePlayedDB = db
  ns = Stub.LoadAddon()
  Stub.LoginSequence()
  T.no(ns.Tracker.IsMax())
  T.eq(ns.db.chars["Player-4619-00A629CA"].capLevel, 10, "the other record untouched")
  -- the capped character comes back at a higher level (played elsewhere): cap over
  Stub.Logout()
  db = Stub.DeepCopy(Stub.saved)
  Stub.Reset()
  local P = Stub.player
  P.level, P.xp, P.max = 11, 200, Stub.xpTable[11]
  _G.TruePlayedDB = db
  ns = Stub.LoadAddon()
  Stub.LoginSequence()
  T.no(ns.Tracker.IsMax())
  T.eq(ns.char.capLevel, nil)
end)

T.test("server cap: the real max level stays max, no cap counted there", function()
  local P = Stub.player
  P.level, P.xp, P.max = 60, 0, 209800
  local ns = Login()
  Stub.Advance(5)
  for _ = 1, 4 do Stub.KillNoXP({ level = 60 }); Stub.Advance(5) end
  local capL, isCap, misses = ns.Tracker.GetCapInfo()
  T.eq(capL, nil); T.eq(isCap, false); T.eq(misses, 0)
  T.ok(ns.Tracker.IsMax())
  T.no((ns.Tracker.GetStall()), "no stall at the real max level")
  Stub.Advance(1500)
  T.no((ns.Tracker.GetStall()))
end)

---------------------------------------------------------------------------
-- 20. round 3: the user's SavedVariables (beta cap at 20, prior v1, exclusions on)
---------------------------------------------------------------------------

-- The druid of TruePlayed_SV_user.lua (2026-10-01): level 20, 58 / 23200 XP for 8 h
-- at the beta cap, prior v1 (4452 XP/h from the lifetime /played), no stall data.
local function UserSV3()
  local ema = {}
  for i, d in ipairs({ 2712.77, 2690.39, 2709.79, 2687.34, 1960.65, 1919.31, 1955.16, 1913.67 }) do
    ema[i] = { a = 0, r = 0, q = 0, d = d }
  end
  return {
    xpMax = { 400, 900, 1400, [20] = 23200 }, createdAt = 1790799275, sparseSettings = true,
    settings = { firstRunDone = true, exclude = { inn = true, afk = true, city = true },
                 widget = { locked = true } },
    lastVersion = "0.1.0-test", schema = 1, cities = {},
    chars = { [USER_GUID] = {
      guid = USER_GUID, name = "Lutak", surname = "Brisevent", class = "DRUID", faction = "Horde",
      realm = "Classic Beta PvP", level = 20, firstSeen = 1790799275, lastSeen = 1790806411,
      last = { at = 1790806411, key = "W", zone = 1440, level = 20, g = 656399.086 },
      sessions = { { s = { i = 12, t = 182, c = 2212, w = 2044 }, t1 = 1790803727, d = 0, xp = 0,
                     l0 = 20, l1 = 20, t0 = 1790799275, p0 = 0.003, p1 = 0.003 } },
      prior = { at = 1790805818, xph = 4452.23229470135 },
      levels = { [20] = { partial = true, s = { i = 12, c = 2212, u = 30328, t = 182, w = 2547, W = 91 },
                          xa = 0, xr = 0, d = 0, xp = 0, xq = 0, srvStart = 104914, max = 23200,
                          z = { [1440] = { s = { w = 681, W = 91 }, xp = 0 },
                                [1456] = { s = { c = 2212, t = 26 }, xp = 0 },
                                [1442] = { s = { i = 10, t = 82, w = 1866 }, xp = 0 },
                                [1412] = { s = { t = 48 }, xp = 0 }, [1413] = { s = { t = 26 }, xp = 0 },
                                o = { s = { i = 2 }, xp = 0 } } } },
      base = { at = 1790799277, total = 135243, level = 20 },
      zones = { [1440] = { s = { w = 681, W = 91 }, name = "Orneval", xp = 0 },
                [1456] = { s = { c = 2212, t = 26 }, name = "Thunder Bluff", xp = 0 },
                [1442] = { s = { i = 10, t = 82, w = 1866 }, name = "Les Serres-Rocheuses", xp = 0 },
                [1412] = { s = { t = 48 }, name = "Mulgore", xp = 0 },
                [1413] = { s = { t = 26 }, name = "Les Tarides", xp = 0 },
                o = { s = { i = 2 }, xp = 0 } },
      cur = { at = 1790806411, g = 656399.086, l0 = 20, p0 = 0.003, s = { w = 503, W = 91 }, d = 0, xp = 0,
              t0 = 1790805816 },
      ema = ema,
      xpSnap = { at = 1790806411, max = 23200, level = 20, rest = 0, xp = 58 },
      life = { xa = 0, s = { i = 12, c = 2212, u = 135242, t = 182, w = 2547, W = 91 }, est = 0, xr = 0, d = 0,
               xp = 0, xq = 0 },
      srv = { at = 1790806411, total = 140288, levelPlayed = 35374, level = 20, g = 656399.086, ext = true },
    } },
  }
end

T.test("user's SV (round 3): prior v1 -> v2 ~5.7k XP/h, 8 h at the cap = stalled, sane when XP resumes", function()
  AddKalimdorCity()
  Stub.maps[1440] = { mapType = 3, parentMapID = 1414, name = "Ashenvale" }
  local P = Stub.player
  P.guid, P.name, P.surname, P.realm = USER_GUID, "Lutak", "Brisevent", "Classic Beta PvP"
  P.class, P.classLocalized = "DRUID", "Druid"
  P.level, P.xp, P.max, P.rest = 20, 58, 23200, 0
  P.mapID, P.zoneText = 1440, "Ashenvale"
  Stub.server.total, Stub.server.levelPlayed = 140400, 35486
  local ns = Login(UserSV3())
  local ch = ns.char
  -- the 8 h at the cap were never withheld (older version): migrated at login
  T.near(ch.noXP, 12 + 2212 + 182 + 2547, 1, "non-AFK time of the level without XP")
  T.ok((ns.Tracker.GetStall()))
  T.eq(ch.levels[20].xs, { w = 2547, W = 91, i = 12, c = 2212, t = 182,
                           d = 0, D = 0, r = 0, R = 0, p = 0, P = 0, I = 0, C = 0, T = 0 })
  T.eq(ch.prior.v, nil, "v1 until the first XP read")
  Stub.Advance(3)                               -- XP baseline: v1 recomputed once as v2
  T.eq(ch.prior.v, 2)
  local v2 = 167200 * 3600 / 104914
  T.near(ch.prior.xph, v2, 1e-6)
  T.ok(v2 > 5700 and v2 < 5800)
  local prior = ch.prior
  Stub.Advance(20)                              -- the login /played: never recomputed again
  T.ok(ch.prior == prior)
  -- the user's exclusions (AFK, inn, city): mask 7
  local mask = ns.GetMask()
  T.eq(mask, 7)
  local xph, _, _, _, src, status = ns.Stats.Rate(ch, mask)
  T.near(xph, v2, 1e-6); T.eq(src, "prior"); T.eq(status, "stalled")
  local sec = ns.Stats.ETA(ch, mask, 58, 23200, 0, false)
  T.near(sec, 23142 * 3600 / v2, 1)
  T.ok(sec > 3.9 * 3600 and sec < 4.2 * 3600, ("ETA %.2f h"):format(sec / 3600))
  -- three kills without XP: the beta cap is detected and shown as max level
  for _ = 1, 3 do Stub.KillNoXP({ level = 20 }); Stub.Advance(30) end
  T.ok(ns.Tracker.IsMax())
  T.eq(ns.Tracker.GetCapInfo(), 20)
  -- days later the cap is raised: 145 XP per mob, one every 40 s
  ns = Stub.Restart({ offline = 3 * 86400 })
  ch = ns.char
  Stub.Advance(15)
  T.ok(ns.Tracker.IsMax(), "still capped until XP comes")
  for k = 1, 40 do
    Stub.Kill(145)
    Stub.Advance(1)
    local r = ns.Stats.Rate(ch, 7)
    T.ok(r and r > 0.7 * v2, ("kill %d: %.0f XP/h"):format(k, r or -1))
    Stub.Advance(39)
  end
  T.no(ns.Tracker.IsMax())
  T.eq(ch.capLevel, nil)
  T.eq(#Stub.errors, 0)
end)
