-- tests/test_crash.lua - crash recovery (requirement D, SPEC 5.14 / 5.15): the
-- 11 scenarios of 5.15, with exact integers, plus a zone-pruning regression (12)
-- and the review fixes (13-19): city share, XP snapshot chain, local server
-- totals after a /reload, dropped segments.
local Stub, T = ...

local floor = math.floor
local KEYS = { "w", "W", "d", "D", "r", "R", "p", "P", "i", "I", "c", "C", "t", "T", "u" }
local TRACKED = { "w", "W", "d", "D", "r", "R", "p", "P", "i", "I", "c", "C", "t", "T" }
local AFK = { W = true, D = true, R = true, P = true, I = true, C = true, T = true }
local IDX = {}                              -- key -> index in TRACKED (and in a split)
for i, k in ipairs(TRACKED) do IDX[k] = i end

local function SumAll(s)
  local t = 0
  if not s then return 0 end
  for _, k in ipairs(KEYS) do t = t + (s[k] or 0) end
  return t
end

local function Copy(t) return Stub.DeepCopy(t) end

-- Independent largest-remainder split (ties by index).
local function LR(total, w)
  local n, W = #w, 0
  for i = 1, n do W = W + w[i] end
  local out, rem, idx, given = {}, {}, {}, 0
  for i = 1, n do
    out[i] = floor(total * w[i] / W)
    rem[i] = total * w[i] - out[i] * W
    idx[i] = i
    given = given + out[i]
  end
  table.sort(idx, function(a, b) if rem[a] ~= rem[b] then return rem[a] > rem[b] end return a < b end)
  for j = 1, total - given do out[idx[j]] = out[idx[j]] + 1 end
  return out
end

local function Printed(text)
  local n = 0
  for _, line in ipairs(Stub.printed) do
    if line:find(text, 1, true) then n = n + 1 end
  end
  return n
end

-- Fires the server answer now; returns total, levelPlayed.
local function Sync()
  local total, lp = floor(Stub.server.total), floor(Stub.server.levelPlayed)
  Stub.Fire("TIME_PLAYED_MSG", total, lp)
  return total, lp
end

local function Saved()
  return Stub.saved.chars[Stub.player.guid]
end

-- Session 1: install sync, then a varied history (world with mobs, a quest,
-- AFK, city, inn), login requests switched off (tests fire the server answer
-- themselves), clean save. Returns the ns of session 2, already logged in.
local function History(extra)
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(15)                          -- install sync at +10 s
  for _ = 1, 20 do
    Stub.Advance(60)
    Stub.GrantXP(40)
  end
  Stub.GrantXP(300, { quest = 300 })
  Stub.SetAFK(true); Stub.Advance(300); Stub.SetAFK(false)
  Stub.SetMap(1454); Stub.Advance(300)
  Stub.SetMap(1411); Stub.SetResting(true); Stub.Advance(300); Stub.SetResting(false)
  Stub.Advance(60)
  ns.settings.requestPlayedAtLogin = false
  if extra then extra(ns) end
  return Stub.Restart({})
end

local function EstimatedSplit(before, G)
  local w = {}
  for i, k in ipairs(TRACKED) do w[i] = before[k] or 0 end
  return LR(G, w)
end

---------------------------------------------------------------------------

T.test("1. crash without level-up: split by own history, last zone, EMA fed", function()
  History()
  Stub.SetMap(1413)                         -- session 2: 3 h in the Barrens, then a crash
  for _ = 1, 180 do
    Stub.Advance(60)
    Stub.GrantXP(20)
  end
  local ns = Stub.Restart({ crash = true })  -- SV from the end of session 1
  local ch, saved = ns.char, Saved()
  Stub.Advance(3)                           -- XP baseline
  local before = Copy(ch.life.s)
  local zoneBefore = SumAll(ch.zones[1411].s)
  local cityBefore = SumAll(ch.zones[1454].s)
  local xpBefore = ch.life.xp
  local total = Sync()
  local G = total - SumAll(before)
  T.ok(G >= 10790 and G <= 10810, "gap ~ 3 h, got " .. G)
  T.eq(ch.life.est, G, "life.est")
  T.eq(ch.levels[10].est, G, "level est")
  T.eq(ch.life.s.u, before.u, "u unchanged")
  T.eq(SumAll(ch.life.s), total, "SumAll(life) == server total")
  local split = EstimatedSplit(before, G)
  local estAFK, afkBefore = 0, 0
  for i, k in ipairs(TRACKED) do
    T.eq((ch.life.s[k] or 0) - (before[k] or 0), split[i], "key " .. k)
    if AFK[k] then estAFK = estAFK + split[i]; afkBefore = afkBefore + (before[k] or 0) end
  end
  T.eq(saved.last.zone, 1411)
  -- last known zone, except the city share: to the main capital (E1, see test 13)
  local cityShare = split[IDX.c] + split[IDX.C]
  T.eq(SumAll(ch.zones[1411].s) - zoneBefore, G - cityShare, "credited to the last known zone")
  T.eq(SumAll(ch.zones[1454].s) - cityBefore, cityShare, "city share credited to Orgrimmar")
  T.ok(SumAll(ch.zones[1413].s) <= 3, "the new load's zone only has the seconds counted since the load")
  -- AFK exclusion removes the estimated AFK part (it lives in real keys)
  T.ok(estAFK > 0)
  local sync, now = ns.Tracker.GetSync(), Stub.Now()
  local f0 = ns.Stats.Played(ch, 0, sync, now)
  local f1, _, ex1 = ns.Stats.Played(ch, 1, sync, now)
  T.eq(ex1, afkBefore + estAFK)
  T.eq(f0 - f1, afkBefore + estAFK)
  -- gap XP exact, classified by the historical a : q ratio
  T.eq(ch.life.xp - xpBefore, 3600)
  local p = LR(3600, { saved.life.xa, saved.life.xr, saved.life.xq })
  T.eq(ch.life.xa - saved.life.xa, p[1]); T.eq(ch.life.xq - saved.life.xq, p[3])
  -- EMA: a long gap dominates -> ~ gap XP / gap time
  local xph, _, _, _, src, status = ns.Stats.Rate(ch, 0)
  T.eq(src, "ema"); T.eq(status, "ok")
  T.near(xph, 3600 * 3600 / G, 80, "rate after the crash")
  T.eq(Printed(ns.L.EST_RECOVERED_FMT:match("^(.-)%%s")), 1, "recovery notice")
  T.eq(ns.Played.GetLastMessageG() ~= nil, true)
end)

T.test("2. crash with level-ups 10 -> 12: levels by server level time and XP weights", function()
  History(function(n) n.db.xpMax[11] = Stub.xpTable[11] end)
  for _ = 1, 180 do                         -- session 2: 3 h, 96 XP per minute: 10 -> 12
    Stub.Advance(60)
    Stub.GrantXP(96)
  end
  T.eq(Stub.player.level, 12)
  local ns = Stub.Restart({ crash = true })
  local ch, saved = ns.char, Saved()
  Stub.Advance(3)
  local b0 = ns.Tracker.b0
  T.eq(b0.level, 12)
  local before = Copy(ch.life.s)
  local counted12 = SumAll(ch.levels[12].s)
  local snap = saved.xpSnap
  T.eq(snap.level, 10)
  local total, P1 = Sync()
  local G = total - SumAll(before)
  local gapL1 = P1 - counted12
  local shares = LR(G - gapL1, { Stub.xpTable[10] - snap.xp, Stub.xpTable[11] })
  T.eq(ch.levels[12].est, gapL1, "level 12: server level time minus counted")
  T.eq(ch.levels[10].est, shares[1], "level 10 share")
  T.eq(ch.levels[11].est, shares[2], "level 11 share")
  T.eq(ch.life.est, G)
  T.ok(ch.levels[11].rec, "level 11 reconstructed")
  T.eq(ch.levels[12].srvStart, total - P1)
  T.eq(ch.levels[11].srvEnd, ch.levels[12].srvStart)
  T.eq(ch.levels[10].xp - saved.levels[10].xp, Stub.xpTable[10] - snap.xp, "gap XP level 10")
  T.eq(ch.levels[11].xp, Stub.xpTable[11], "gap XP level 11")
  T.eq(ch.levels[12].xp, b0.xp, "gap XP level 12")
  T.eq(ch.life.xp - saved.life.xp, 180 * 96, "all the XP of the lost session")
  T.eq(SumAll(ch.life.s), total)
  local _, _, _, _, src, status = ns.Stats.Rate(ch, 0)
  T.eq(src, "ema"); T.eq(status, "ok")
end)

T.test("3. play without the addon behaves like a crash", function()
  History()
  local ns = Stub.Restart({ playElsewhere = { sec = 3600, xp = 5000 } })
  local ch, saved = ns.char, Saved()
  Stub.Advance(3)
  local before = Copy(ch.life.s)
  local total = Sync()
  local G = total - SumAll(before)
  T.ok(G >= 3595 and G <= 3605, "gap ~ 1 h, got " .. G)
  T.eq(ch.life.est, G)
  T.eq(ch.life.s.u, saved.life.s.u)
  local split = EstimatedSplit(before, G)
  for i, k in ipairs(TRACKED) do T.eq((ch.life.s[k] or 0) - (before[k] or 0), split[i], k) end
  T.eq(ch.life.xp - saved.life.xp, 5000)
  T.eq(SumAll(ch.life.s), total)
end)

T.test("4. a second sync 20 s later adds nothing", function()
  History()
  local ns = Stub.Restart({ playElsewhere = { sec = 1800, xp = 1000 } })
  Stub.Advance(3)
  Sync()
  local ch = ns.char
  local est, u, xp = ch.life.est, ch.life.s.u, ch.life.xp
  local ema = Copy(ch.ema[1])
  Stub.Advance(20)
  local total = Sync()
  T.eq(ch.life.est, est)
  T.eq(ch.life.s.u, u)
  T.eq(ch.life.xp, xp)
  T.near(SumAll(ch.life.s), total, 1)
  T.near(ch.ema[1].d, ema.d * math.exp(-20 / 3600) + 3600 * (1 - math.exp(-20 / 3600)), 1e-6, "only the normal decay")
end)

T.test("5. a message before the XP baseline: reconcile deferred, same final numbers", function()
  History()
  local ns = Stub.Restart({ playElsewhere = { sec = 3600, xp = 5000 } })
  local ch, saved = ns.char, Saved()
  local total = Sync()                      -- RXPGuides asks at PLAYER_ENTERING_WORLD
  T.eq(ch.life.est, 0, "deferred until the XP baseline")
  T.ok(ns.Tracker.pendingReconcile)
  Stub.Advance(3)
  T.no(ns.Tracker.pendingReconcile)
  T.ok(ch.life.est >= 3595 and ch.life.est <= 3605, "gap re-added, got " .. ch.life.est)
  T.eq(ch.life.xp - saved.life.xp, 5000, "gap XP exact")
  T.near(SumAll(ch.life.s), total + 3, 1)
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 1)
end)

T.test("6. first install: everything to u, no estimate, no EMA change", function()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(12)                          -- login request at +10 s
  local ch = ns.char
  T.ok(ch.base ~= nil)
  T.eq(ch.life.s.u, 360000)
  T.eq(ch.life.est, 0)
  T.eq(ch.levels[10].s.u, 5000)
  T.ok(ch.levels[10].partial)
  T.eq(ch.ema[1].a, 0)
  T.ok(ch.ema[1].d < 20, "EMA clock only counts the tracked seconds")
  T.eq(Printed(ns.L.EST_RECOVERED_FMT:match("^(.-)%%s")), 0)
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 1)
end)

T.test("7. /tpl reset char then sync: install semantics again", function()
  local ns = History()
  Stub.Advance(30)
  local spy = 0
  ns.RegisterMessage("CHAR_RESET", "test-spy", function() spy = spy + 1 end)
  local requests = Stub.requests
  T.ok(ns.Core.ResetChar(Stub.player.guid))
  T.eq(spy, 1)
  Stub.Advance(2)
  T.eq(Stub.requests, requests + 1, "reset asks the server")
  local ch = ns.char
  T.ok(ch.base ~= nil)
  T.eq(ch.life.est, 0)
  T.ok(ch.life.s.u > 360000, "whole /played is pre-install again")
  T.ok(ch.levels[10].partial)
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 1)
end)

T.test("8. late SV swap after a gap: no double counting", function()
  History()
  Stub.Logout()
  local real = Copy(Stub.saved)
  local savedChar = real.chars[Stub.player.guid]
  local realU = savedChar.life.s.u
  -- 30 min played elsewhere, then a load where the SV appears late
  Stub.server.total = Stub.server.total + 1800
  Stub.server.levelPlayed = Stub.server.levelPlayed + 1800
  Stub.Reset({ keepWorld = true })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(15)                          -- blank table: install sync
  _G.TruePlayedDB = real
  Stub.Advance(2)                           -- swap at the next tick
  local ch = ns.char
  T.ok(ns.db == real)
  T.eq(ch.life.s.u, realU, "u of the real table unchanged")
  T.near(ch.life.est, 1800, 1, "the gap is re-added once")
  T.near(SumAll(ch.life.s), floor(Stub.server.total), 1, "no double counting")
  T.eq(ch.life.xp, savedChar.life.xp, "no XP invented")
end)

T.test("9. negative gap: nothing subtracted", function()
  local ns = History()
  Stub.Advance(10)
  local ch = ns.char
  local before, est = SumAll(ch.life.s), ch.life.est
  local lvl = Copy(ch.levels[10].s)
  Stub.Fire("TIME_PLAYED_MSG", floor(Stub.server.total) - 500, floor(Stub.server.levelPlayed))
  T.eq(SumAll(ch.life.s), before)
  T.eq(ch.life.est, est)
  T.eq(ch.levels[10].s, lvl)
end)

T.test("10. a dropped > 900 s segment is re-added at the next sync (L0 = recLevel)", function()
  local ns = History()
  Stub.Advance(20)
  -- level-up answered by our own request: recLevel becomes 11
  Stub.GrantXP(Stub.xpTable[10])
  Stub.Advance(10)
  T.eq(ns.Tracker.recLevel, 11)
  local ch = ns.char
  local est10 = ch.levels[10].est or 0
  local start, first = Stub.Now(), nil
  ns.RegisterMessage("TICK", "test-first-tick", function(_, now) if not first then first = now end end)
  Stub.Advance(1000, 1000)                  -- client frozen: the segment is dropped
  if not first or first - start < 900 then
    T.skip("this stub fires timers at their due time: the ticker cannot be frozen")
  end
  local before = Copy(ch.life.s)
  local total = Sync()
  local G = total - SumAll(before)
  T.ok(G >= 995 and G <= 1001, "dropped time re-added, got " .. G)
  T.eq(ch.levels[11].est, G, "all to the level of the last reconcile")
  T.eq(ch.levels[10].est or 0, est10)
  T.eq(SumAll(ch.life.s), total)
end)

T.test("11. rate status stays ok after a clean restart and after a crash", function()
  local ns = History()
  local xph1, _, _, _, src1, status1 = ns.Stats.Rate(ns.char, 0)
  T.eq(status1, "ok"); T.eq(src1, "ema")
  ns = Stub.Restart({})                     -- clean restart
  local xph2, _, _, _, _, status2 = ns.Stats.Rate(ns.char, 0)
  T.eq(status2, "ok")
  T.near(xph2, xph1, xph1 * 0.01, "same value after the restart")
  Stub.Advance(600)
  ns = Stub.Restart({ crash = true })
  local _, _, _, _, _, status3 = ns.Stats.Rate(ns.char, 0)
  T.eq(status3, "ok", "never nodata after a crash")
  Stub.Advance(3)
  Sync()
  local _, _, _, _, _, status4 = ns.Stats.Rate(ns.char, 0)
  T.eq(status4, "ok")
  ns.Core.ResetRate()                       -- level data remains: fallback, not nodata
  local _, _, _, _, src5, status5 = ns.Stats.Rate(ns.char, 0)
  T.eq(status5, "ok"); T.eq(src5, "level")
end)

T.test("12. a gap that completes a level: that level's zones pruned after the gap is written", function()
  for i = 1, 14 do
    Stub.maps[51000 + i] = { mapType = 3, parentMapID = 1414, name = "Zone " .. i }
  end
  local function ZoneTotals(z)
    local n, secs, xp = 0, 0, 0
    for _, zb in pairs(z) do
      n = n + 1
      secs = secs + SumAll(zb.s)
      xp = xp + (zb.xp or 0)
    end
    return n, secs, xp
  end
  History(function()
    for i = 1, 14 do                        -- 14 small zones, the last one (saved as
      Stub.SetMap(51000 + i)                -- char.last.zone) the smallest
      Stub.Advance(35 - i)
    end
  end)
  Stub.Advance(5)                           -- session 2: 5 s at level 10, level 11, then a crash
  Stub.GrantXP(Stub.xpTable[10])
  Stub.Advance(600)
  T.eq(Stub.player.level, 11)
  local ns = Stub.Restart({ crash = true })
  local ch, saved = ns.char, Saved()
  Stub.Advance(3)
  local n0, secs0, xp0 = ZoneTotals(ch.levels[10].z)
  T.ok(n0 > 10, "level 10 not pruned before the sync")
  Sync()
  local est10 = ch.levels[10].est
  T.ok(est10 and est10 > 0, "level 10 received a gap share")
  local n1, secs1, xp1 = ZoneTotals(ch.levels[10].z)
  T.eq(n1, 11, "10 largest + 'o'")
  T.ok(ch.levels[10].z.o ~= nil)
  T.eq(secs1, secs0 + est10, "no second lost or added by the prune")
  T.eq(xp1, xp0 + Stub.xpTable[10] - saved.xpSnap.xp, "gap XP kept in the pruned zones")
  T.eq(ch.levels[10].xp - saved.levels[10].xp, Stub.xpTable[10] - saved.xpSnap.xp)
end)

---------------------------------------------------------------------------
-- Review fixes: city share of an estimated gap (E1), XP snapshot chain
-- (ENG-1), local server totals after a /reload (ENG-2), dropped segments (ENG-4)
---------------------------------------------------------------------------

-- City seconds (c + C) of a split in TRACKED order.
local function CityPart(split)
  local n = 0
  for i, k in ipairs(TRACKED) do
    if k == "c" or k == "C" then n = n + split[i] end
  end
  return n
end

local function CitySecs(s)
  if not s then return 0 end
  return (s.c or 0) + (s.C or 0)
end

T.test("13. the estimated city share goes to the main capital, never to an ordinary zone", function()
  History()
  Stub.SetMap(1413)                         -- session 2: 3 h in the Barrens, then a crash
  for _ = 1, 180 do
    Stub.Advance(60)
    Stub.GrantXP(20)
  end
  local ns = Stub.Restart({ crash = true })
  local ch, saved = ns.char, Saved()
  Stub.Advance(3)
  T.eq(saved.last.zone, 1411, "last zone: Durotar, not a city")
  local before = Copy(ch.life.s)
  local dur0, org0 = Copy(ch.zones[1411].s), Copy(ch.zones[1454].s)
  local lzOrg0 = CitySecs(ch.levels[10].z[1454].s)
  local total = Sync()
  local G = total - SumAll(before)
  local split = EstimatedSplit(before, G)
  local city = CityPart(split)
  T.ok(city > 0, "the history holds city time")
  T.eq(SumAll(ch.zones[1411].s) - SumAll(dur0), G - city, "the last zone gets the rest of the gap")
  T.eq(CitySecs(ch.zones[1411].s), 0, "no city seconds in Durotar")
  T.eq((ch.zones[1454].s.c or 0) - (org0.c or 0), split[IDX.c], "c to Orgrimmar")
  T.eq((ch.zones[1454].s.C or 0) - (org0.C or 0), split[IDX.C], "C to Orgrimmar")
  local lz = ch.levels[10].z
  T.eq(CitySecs(lz[1411].s), 0, "level-zone bucket of Durotar")
  T.eq(CitySecs(lz[1454].s) - lzOrg0, city, "level-zone bucket of Orgrimmar")
  local rows, n = ns.Stats.TopCities(ch.zones, 1000)
  local sum = 0
  for i = 1, n do
    T.ok(rows[i].key ~= 1411, "Durotar is not a top capital")
    sum = sum + rows[i].total
  end
  T.eq(rows[1].key, 1454)
  T.eq(sum, CitySecs(ch.life.s), "5.17: zones hold every city second")
  T.no(ns.Stats.IsCityKey(1411, ch.zones[1411]), "Durotar not marked as a city")
end)

T.test("14. no capital in the zones: the city share goes to the last zone only if it is a capital", function()
  History()
  local saved = Saved()
  saved.zones[1454] = nil                   -- city history without its zone (damaged record)
  saved.levels[10].z[1454] = nil
  local ns = Stub.Restart({ crash = true, playElsewhere = { sec = 3600, xp = 0 } })
  local ch = ns.char
  Stub.Advance(3)
  local before = Copy(ch.life.s)
  local dur0 = SumAll(ch.zones[1411].s)
  local total = Sync()
  local G = total - SumAll(before)
  local city = CityPart(EstimatedSplit(before, G))
  T.ok(city > 0)
  T.eq(SumAll(ch.zones[1411].s) - dur0, G - city, "Durotar: everything but the city share")
  T.eq(CitySecs(ch.zones[1411].s), 0)
  T.eq(CitySecs(ch.zones.o.s), city, "city share parked in the neutral 'o' bucket")
  T.eq(CitySecs(ch.levels[10].z.o.s), city)
end)

T.test("14b. no capital in the zones, last zone a capital: the whole gap goes there", function()
  History()
  local saved = Saved()
  saved.zones[1454] = nil
  saved.levels[10].z[1454] = nil
  saved.last.zone = 1458                    -- Undercity (built-in capital)
  local ns = Stub.Restart({ crash = true, playElsewhere = { sec = 3600, xp = 0 } })
  local ch = ns.char
  Stub.Advance(3)
  local before = Copy(ch.life.s)
  local total = Sync()
  local G = total - SumAll(before)
  local city = CityPart(EstimatedSplit(before, G))
  T.ok(city > 0)
  T.eq(SumAll(ch.zones[1458].s), G)
  T.eq(CitySecs(ch.zones[1458].s), city)
  T.eq(ch.zones.o, nil, "no neutral bucket needed")
end)

T.test("15. crash, then /reload before the login sync: the next sync does not crush the rate", function()
  History(function(n) n.settings.requestPlayedAtLogin = true end)
  Stub.Advance(15)                          -- session 2: login sync
  Stub.SetMap(1413)
  for _ = 1, 180 do
    Stub.Advance(60)
    Stub.GrantXP(20)                        -- 1200 XP/h
  end
  local ns = Stub.Restart({ crash = true })  -- session 3 starts from the save of session 1
  Stub.Advance(5)                           -- XP baseline read, login /played not sent yet
  ns = Stub.Restart({ reload = true, online = 1 })
  for _ = 1, 60 do
    Stub.Advance(60)
    Stub.GrantXP(20)
  end
  local before = ns.Stats.Rate(ns.char, 0)
  ns = Stub.Restart({})
  Stub.Advance(15)                          -- login sync of session 4
  local sync = ns.Tracker.GetSync()
  T.ok(sync and not sync.restored, "server answer received")
  local after, _, _, _, src, status = ns.Stats.Rate(ns.char, 0)
  T.eq(src, "ema"); T.eq(status, "ok")
  T.near(after, before, before * 0.1, "rate kept by the login sync")
  T.near(SumAll(ns.char.life.s), floor(Stub.server.total), 1)
end)

T.test("16. login request off: crash, two sessions without a sync, then /played keeps the rate", function()
  History()                                 -- login requests off
  Stub.SetMap(1413)
  for _ = 1, 180 do
    Stub.Advance(60)
    Stub.GrantXP(20)
  end
  local ns = Stub.Restart({ crash = true })
  for _ = 1, 2 do                           -- sessions 3 and 4: 20 min each, no sync
    for _ = 1, 20 do
      Stub.Advance(60)
      Stub.GrantXP(20)
    end
    ns = Stub.Restart({})
    T.eq(ns.char.xpSnap, nil, "a load that never met the server saves no snapshot")
  end
  for _ = 1, 20 do                          -- session 5, then /played
    Stub.Advance(60)
    Stub.GrantXP(20)
  end
  local before = ns.Stats.Rate(ns.char, 0)
  local est = ns.char.life.est
  local total = Sync()
  T.ok(ns.char.life.est - est >= 10790, "the crash gap is re-added")
  local after, _, _, _, src, status = ns.Stats.Rate(ns.char, 0)
  T.eq(src, "ema"); T.eq(status, "ok")
  T.near(after, before, before * 0.1, "no 3 h chunk without XP fed to the rate")
  T.eq(SumAll(ns.char.life.s), total)
end)

T.test("17. /reload after a synced load keeps the XP snapshot chain", function()
  local ns = History()                      -- session 2, login requests off
  Stub.Advance(3)
  Sync()                                    -- session 2 meets the server
  Stub.Advance(60)
  ns = Stub.Restart({ reload = true, online = 3 })
  local sync = ns.Tracker.GetSync()
  T.ok(sync and sync.restored, "sync restored")
  Stub.Advance(60)
  Stub.GrantXP(100)
  Stub.Advance(60)
  ns = Stub.Restart({ playElsewhere = { sec = 3600, xp = 5000 } })
  local ch = ns.char
  T.ok(ch.xpSnap ~= nil, "the reloaded load saved a snapshot")
  Stub.Advance(3)
  local xp = ch.life.xp
  Sync()
  T.near(ch.life.est, 3600, 2, "gap re-added")
  T.eq(ch.life.xp - xp, 5000, "gap XP exact")
end)

T.test("18. /reload before the first sync: a local total is not restored as a server sync", function()
  History(function(n) n.settings.requestPlayedAtLogin = true end)
  Stub.Advance(15)
  for _ = 1, 180 do Stub.Advance(60) end
  local ns = Stub.Restart({ crash = true })
  Stub.Advance(5)
  T.eq(Stub.requests, 0, "login request not sent yet")
  ns = Stub.Restart({ reload = true, online = 1 })
  T.ok(Saved().srv.loc, "saved as a local lower bound")
  T.eq(ns.Tracker.GetSync(), nil, "not restored as a server sync")
  Stub.Advance(11)
  T.eq(Stub.requests, 1, "the login request goes out after the reload")
  T.ok(ns.char.life.est >= 10790, "crash gap re-added in this load")
  T.near(SumAll(ns.char.life.s), floor(Stub.server.total), 1)
  T.eq(ns.char.srv.loc, nil, "a server answer clears the flag")
end)

T.test("19. a dropped segment is re-added where it was played (key, zone, level)", function()
  local ns = History()
  Stub.Advance(3)
  Sync()                                    -- nothing missing so far
  local ch = ns.char
  Stub.SetMap(1446)                         -- Tanaris, not AFK
  local start, first = Stub.Now(), nil
  ns.RegisterMessage("TICK", "test-first-tick", function(_, now) if not first then first = now end end)
  local before = Copy(ch.life.s)
  local est0 = ch.life.est
  local dur0 = SumAll(ch.zones[1411].s)
  local tan0 = ch.zones[1446] and ch.zones[1446].s.w or 0
  Stub.Advance(1000, 1000)                  -- client frozen: the segment is dropped
  if not first or first - start < 900 then
    T.skip("this stub fires timers at their due time: the ticker cannot be frozen")
  end
  local total = Sync()
  local G = total - SumAll(before)
  T.ok(G >= 999 and G <= 1001, "gap ~ 1000 s, got " .. G)
  local known = math.min(G, 1000)
  local tan = ch.zones[1446] and ch.zones[1446].s.w or 0
  local lzTan = ch.levels[10].z[1446] and ch.levels[10].z[1446].s.w or 0
  T.eq(tan - tan0, known, "Tanaris gets the frozen seconds as 'w'")
  T.eq(lzTan, known, "level-zone bucket of Tanaris")
  T.ok(SumAll(ch.zones[1411].s) - dur0 <= G - known, "the last logout zone gets at most the rest")
  T.ok((ch.life.s.W or 0) - (before.W or 0) <= G - known, "no active time turned into AFK")
  T.eq(ch.life.est - est0, G, "still counted as estimated")
  T.eq(SumAll(ch.life.s), total)
end)

T.test("20. instance history: the gap's dungeon / raid / PvP shares go to instance zones only", function()
  History(function()
    Stub.SetInstance(true, "party", 389, 90001); Stub.Advance(1200)   -- Ragefire Chasm
    Stub.SetAFK(true); Stub.Advance(120); Stub.SetAFK(false)
    Stub.SetInstance(true, "raid", 409, nil); Stub.Advance(900)       -- Molten Core
    Stub.SetInstance(true, "pvp", 30, nil); Stub.Advance(600)         -- a battleground
    Stub.SetInstance(false, nil, 0, 1411); Stub.Advance(60)
  end)
  Stub.SetMap(1413)                         -- session 2: 3 h in the Barrens, then a crash
  for _ = 1, 180 do
    Stub.Advance(60)
    Stub.GrantXP(20)
  end
  local ns = Stub.Restart({ crash = true })
  local ch, saved = ns.char, Saved()
  Stub.Advance(3)
  T.eq(saved.last.zone, 1411, "last zone: Durotar, open world")
  local before = Copy(ch.life.s)
  local z0 = {}
  for _, k in ipairs({ 1411, 90001, "i409", "i30", 1454 }) do z0[k] = Copy(ch.zones[k].s) end
  local total = Sync()
  local G = total - SumAll(before)
  local split = EstimatedSplit(before, G)
  T.eq(SumAll(ch.life.s), total, "SumAll(life) == server total")
  for i, k in ipairs(TRACKED) do
    T.eq((ch.life.s[k] or 0) - (before[k] or 0), split[i], "key " .. k)
  end
  T.ok(split[IDX.d] > 0 and split[IDX.D] > 0 and split[IDX.r] > 0 and split[IDX.p] > 0, "instance shares")
  local function Delta(k, key) return (ch.zones[k].s[key] or 0) - (z0[k][key] or 0) end
  T.eq(Delta(90001, "d"), split[IDX.d]); T.eq(Delta(90001, "D"), split[IDX.D])
  T.eq(Delta("i409", "r"), split[IDX.r])
  T.eq(Delta("i30", "p"), split[IDX.p])
  for _, key in ipairs({ "d", "D", "r", "R", "p", "P" }) do
    T.eq(Delta(1411, key), 0, "no instance time in the open-world zone: " .. key)
  end
  T.eq(Delta(1411, "w"), split[IDX.w], "open-world share to the last zone")
  local lz = ch.levels[10].z
  T.ok((lz[90001].s.d or 0) >= split[IDX.d], "level-zone bucket of the dungeon")
  local rows = {}
  local n = ns.Stats.TopInstances(ch.zones, 0, 10, rows)
  T.eq(n, 3, "only real instances are listed")
  T.eq(rows[1].key, 90001); T.eq(rows[1].kind, "d")
  local bd = ns.Stats.Breakdown(ch.life, {})
  T.eq(bd.active + bd.afk + bd.inn + bd.city, bd.tracked)
end)

---------------------------------------------------------------------------
-- Round 3 (C1, C2): crash gaps and time without XP
---------------------------------------------------------------------------

T.test("20. a crash gap never counts as time without XP; gap XP ends a stall", function()
  History()
  -- session 2: 3 h in the Barrens with XP, then a crash
  Stub.SetMap(1413)
  for _ = 1, 180 do
    Stub.Advance(60)
    Stub.GrantXP(20)
  end
  local ns = Stub.Restart({ crash = true })
  local ch = ns.char
  Stub.Advance(3)
  local n0 = ch.noXP
  Sync()
  T.eq(ch.noXP, 0, "the gap XP is an XP gain")
  T.ok(n0 ~= nil)
  T.eq(ch.levels[10].xs.w, 0, "no stalled time from a gap")
  T.eq(ch.life.xs.w, 0)
  T.no((ns.Tracker.GetStall()))
end)

T.test("21. while stalled, a gap without XP leaves the EMA frozen and stays out of the stall", function()
  History()
  local ns = Stub.Restart({})
  Stub.Advance(3)
  Sync()                                    -- anchored: the save holds an XP snapshot
  Stub.Advance(1300)                        -- session 2: stalled after 20 min without XP
  T.ok((ns.Tracker.GetStall()))
  -- saved, then 1 h played without TruePlayed (no XP)
  local ns2 = Stub.Restart({ playElsewhere = { sec = 3600, xp = 0 } })
  local ch = ns2.char
  Stub.Advance(3)
  local e = Copy(ch.ema[1])
  local n = ch.noXP
  local xs = Copy(ch.levels[10].xs)
  local total = Sync()
  T.ok(ch.life.est > 3500, "the gap is re-added")
  T.near(SumAll(ch.life.s), total, 1)
  T.eq(ch.ema[1], e, "EMA frozen: the gap brought no XP")
  T.eq(ch.noXP, n, "a gap is never counted as time without XP")
  T.eq(ch.levels[10].xs, xs, "nor as stalled time")
end)

T.test("22. at a detected server cap, gap XP (the cap was raised meanwhile) ends the cap", function()
  History()
  local ns = Stub.Restart({})
  Stub.Advance(3)
  Sync()                                    -- anchored: the save holds an XP snapshot
  for _ = 1, 3 do
    Stub.KillNoXP()
    Stub.Advance(10)
  end
  T.ok(ns.Tracker.IsMax(), "capped")
  -- the cap is raised while the addon is off: 1 h with 2000 XP elsewhere
  local ns2 = Stub.Restart({ playElsewhere = { sec = 3600, xp = 2000 } })
  local ch = ns2.char
  T.ok(ns2.Tracker.IsMax(), "still capped before the reconcile")
  Stub.Advance(3)
  Sync()
  T.no(ns2.Tracker.IsMax(), "gap XP: the cap is over")
  T.eq(ch.capLevel, nil)
  T.eq(ch.noXP, 0)
end)
