-- tests/test_dead.lua - time spent dead (lot 8, A1): the "x" state from PLAYER_DEAD to the
-- resurrection (the ghost run included), its precedence over every other state, deaths and
-- dead time per level, session, zone and account, the breakdown and the Shift tooltip,
-- saved-data repair, crash recovery (no share) and zero garbage per tick while dead.
local Stub, T = ...

local format = string.format

local function Login(db, settle)
  if db then _G.TruePlayedDB = db end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = settle })
  return ns
end

local function State(ns)
  return (ns.Tracker.GetState())
end

-- GameTooltip lines as { left, right } after Tooltip.Fill.
local function Fill(ns, detailed)
  local tt = GameTooltip
  tt:ClearLines()
  ns.Tooltip.Fill(tt, detailed)
  local out = {}
  for i, l in ipairs(tt._lines or {}) do out[i] = { l[1] or l.left, l[2] or l.right } end
  return out
end

local function Find(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i] end
  end
  return nil
end

---------------------------------------------------------------------------

T.test("dead: from PLAYER_DEAD to the resurrection, ghost run included, in every bucket", function()
  local ns = Login()
  Stub.Advance(10)
  T.eq(State(ns), "w")
  Stub.Die()
  T.eq(State(ns), "x", "dead at once (PLAYER_DEAD)")
  Stub.Advance(30)
  Stub.ReleaseSpirit()                       -- PLAYER_ALIVE as a ghost: still dead
  T.eq(State(ns), "x", "a ghost is still dead")
  Stub.SetMap(1413)                          -- the ghost run crosses into the Barrens
  Stub.Advance(60)
  Stub.Resurrect(true)                       -- PLAYER_UNGHOST at the corpse
  T.eq(State(ns), "w", "alive again")
  Stub.Advance(10)
  local ch = ns.char
  T.eq(ch.life.s.x, 90, "life: 30 s dead + 60 s ghost run")
  T.eq(ch.life.s.w, 20, "world: before and after, never the ghost run")
  T.eq(ch.levels[10].s.x, 90, "level")
  T.eq(ch.levels[10].z[1411].s.x, 30, "level zone where the body lies")
  T.eq(ch.zones[1411].s.x, 30, "zone")
  T.eq(ch.zones[1413].s.x, 60, "the ghost run's zone")
  T.eq(ns.session.s.x, 90, "session")
  T.eq(ns.Tracker.GetDelta().life.s.x, 90, "delta (late SavedVariables replay)")
  T.eq(ch.life.d, 1, "one death"); T.eq(ch.levels[10].d, 1); T.eq(ns.session.d, 1)
  local dead, prof, deaths = ns.Stats.AccountActivity(ns.db)
  T.eq({ dead, prof, deaths }, { 90, 0, 1 }, "account figures")
end)

T.test("dead: found on the tick without any event; a resurrection without event too", function()
  local ns = Login()
  Stub.Advance(5)
  Stub.player.dead = true                    -- no PLAYER_DEAD (e.g. dead at login)
  Stub.Advance(1)
  T.eq(State(ns), "x", "the 1 s tick reads UnitIsDeadOrGhost")
  Stub.Advance(20)
  Stub.player.dead = false
  Stub.Advance(1)
  T.eq(State(ns), "w")
  T.ok(ns.char.life.s.x >= 20 and ns.char.life.s.x <= 21, "20 s (+ the tick boundary): " .. ns.char.life.s.x)
end)

T.test("dead: wins over AFK, city, inn, instances and professions; never excluded", function()
  local ns = Login()
  Stub.SetAFK(true)
  Stub.Die()
  T.eq(State(ns), "x", "AFK while dead is dead")
  Stub.SetMap(1454)                          -- Orgrimmar (capital)
  Stub.SetResting(true)
  T.eq(State(ns), "x", "dead in a capital, resting")
  Stub.OpenTradeSkill()
  T.eq(State(ns), "x", "dead with a trade skill window open")
  Stub.CloseTradeSkill()
  Stub.SetInstance(true, "party", 389, 90001)
  T.eq(State(ns), "x", "dead in a dungeon")
  local C = ns.C
  for m = 0, 7 do T.eq(C.INCLUDED[m].x, true, "mask " .. m) end
  ns.Core.SetSetting("exclude.afk", true)
  ns.Core.SetSetting("exclude.inn", true)
  ns.Core.SetSetting("exclude.city", true)
  T.no((ns.Tracker.IsPaused()), "dead time is never paused")
  Stub.Advance(40)
  Stub.SetInstance(false)
  Stub.SetMap(1454)
  Stub.Resurrect(false)
  T.eq(State(ns), "C", "alive: the AFK key of the capital")
  local ch = ns.char
  T.eq(ch.life.s.x, 40)
  T.eq(ns.Stats.Sum(ch.life, 7) - (ch.life.s.u or 0), 40, "counted under every exclusion")
  T.eq(ch.levels[10].z[90001].s.x, 40, "the dungeon's bucket keeps its dead time")
  T.eq(ns.Stats.InstanceTime(ch.life, 0), 0, "dead time is not dungeon time")
end)

T.test("dead: a hunter's Feign Death is not death", function()
  local ns = Login()
  Stub.act.feign = true
  Stub.player.dead = true
  Stub.Fire("PLAYER_DEAD")
  Stub.Advance(10)
  T.eq(State(ns), "w")
  T.eq(ns.char.life.s.x, nil)
  Stub.act.feign = false
  Stub.Advance(1)
  T.eq(State(ns), "x", "really dead once Feign Death is over")
end)

T.test("deaths and dead time per level: the level of each death", function()
  local ns = Login()
  Stub.Advance(5)
  Stub.Die(); Stub.Advance(30); Stub.Resurrect(false)
  Stub.GrantXP(Stub.player.max)              -- level 11
  Stub.Advance(2)
  T.eq(ns.char.level, 11)
  for _ = 1, 2 do
    Stub.Die(); Stub.Advance(15); Stub.ReleaseSpirit(); Stub.Advance(45); Stub.Resurrect(true)
    Stub.Advance(5)
  end
  local Stats, ch = ns.Stats, ns.char
  local d10, x10 = Stats.LevelActivity(ch, 10)
  local d11, x11, f11 = Stats.LevelActivity(ch, 11)
  T.eq({ d10, x10 }, { 1, 30 })
  T.eq({ d11, x11, f11 }, { 2, 120, 0 })
  T.eq({ Stats.LevelActivity(ch, 3) }, { 0, 0, 0 }, "no record: zeros")
  local rows = Stats.LevelHistory(ch, 0, ns.Tracker.GetSync(), Stub.Now(), {})
  T.eq(rows[1].level, 11)
  T.eq({ rows[1].deaths, rows[1].dead }, { 2, 120 }, "Levels rows carry deaths and dead time")
  T.eq({ rows[2].deaths, rows[2].dead }, { 1, 30 })
  T.eq(ch.life.d, 3); T.eq(ch.life.s.x, 150)
  local sess = Stats.SessionHistory(ch, 0, {})
  T.eq({ sess[1].deaths, sess[1].dead }, { 3, 150 }, "session row")
end)

T.test("dead: breakdown part, gauge key and the Shift tooltip line 'Deaths  n (time)'", function()
  local ns = Login()
  local L, Fmt, Stats, Tooltip = ns.L, ns.Fmt, ns.Stats, ns.Tooltip
  Stub.Advance(240)
  Stub.Die(); Stub.Advance(60); Stub.ReleaseSpirit(); Stub.Advance(65); Stub.Resurrect(true)
  Stub.Advance(1)
  local bd = Stats.Breakdown(ns.char.life, {})
  T.eq(bd.dead, 125); T.eq(bd.prof, 0)
  T.eq(bd.active + bd.afk + bd.inn + bd.city + bd.dead + bd.prof, bd.tracked, "partition")
  local parts = {}
  local n = Tooltip.BreakdownParts(bd, parts)
  T.eq(n, 2)
  T.eq(parts[2], format(L.BD_PART_FMT, L.BD_DEAD, Fmt.Percent(125 / bd.tracked, 0)), "after the world")
  local fracs, keys = {}, {}
  T.eq(Tooltip.BreakdownFracs(bd, fracs, keys), 2)
  T.eq(keys, { "world", "dead" })
  local short = Fill(ns, false)
  T.no(Find(short, L.TT_DEATHS), "the short view has no deaths line")
  T.ok(Find(short, L.TT_BREAKDOWN)[2]:find(L.BD_DEAD, 1, true), "breakdown line names it")
  local lines = Fill(ns, true)
  T.eq(Find(lines, L.TT_DEATHS)[2], format("%s (%s)", Fmt.Number(1), Fmt.Duration(125)), "count and time, one line")
  -- deaths recorded before this version (no dead time): the count alone
  ns.char.life.s.x = nil
  T.eq(Find(Fill(ns, true), L.TT_DEATHS)[2], Fmt.Number(1))
end)

T.test("dead: every theme with a gauge has its dead and professions colours", function()
  local ns = Login()
  local Themes = ns.Themes
  local n = 0
  for _, key in ipairs(ns.C.THEME_CHOICES) do
    if key ~= "class" then
      ns.Core.SetSetting("theme", key)
      local th = Themes.Active()
      local g = th and th.tt and th.tt.gauge
      if g then
        n = n + 1
        for _, k in ipairs({ "dead", "prof" }) do
          local c = g.colors[k]
          T.ok(type(c) == "table" and type(c[1]) == "number" and type(c[4]) == "number", key .. " " .. k)
        end
        T.ok(g.colors.dead ~= g.colors.world and g.colors.prof ~= g.colors.world, key .. ": own colours")
      end
    end
  end
  T.ok(n >= 11, "themes with a gauge: " .. n)
end)

T.test("dead: saved-data repair drops bad dead / professions seconds, keeps good ones", function()
  local guid = Stub.player.guid
  local ns = Login({ schema = 1, chars = { [guid] = {
    guid = guid, level = 10,
    life = { s = { w = 100, x = -5, f = "12" }, xp = 0, d = 2 },
    levels = { [10] = { s = { w = 100, x = 30, f = 0 / 0 }, z = {}, xp = 0, d = 2 } },
    zones = { [1411] = { s = { w = 100, x = 20, f = -1 }, xp = 0 } },
    sessions = { { t0 = 1, s = { x = 7, f = 8 }, xp = 0, d = 0 } },
  } } })
  local ch = ns.char
  T.eq(ch.life.s.x, nil, "negative dropped"); T.eq(ch.life.s.f, nil, "string dropped")
  T.eq(ch.levels[10].s.x, 30, "valid kept"); T.eq(ch.levels[10].s.f, nil, "NaN dropped")
  T.eq(ch.zones[1411].s.x, 20); T.eq(ch.zones[1411].s.f, nil)
  T.eq(ch.sessions[1].s.x, 7); T.eq(ch.sessions[1].s.f, 8)
  -- an older record without the keys works (zeros)
  local bd = ns.Stats.Breakdown({ s = { w = 50 } }, {})
  T.eq({ bd.dead, bd.prof, bd.tracked }, { 0, 0, 50 })
end)

T.test("dead: a sparse save (no x / f key for a character that never died or crafted)", function()
  local ns = Login()
  Stub.Advance(30)
  Stub.Logout()
  local rec = Stub.saved.chars[Stub.player.guid]
  T.eq(rec.life.s.x, nil); T.eq(rec.life.s.f, nil)
  T.eq(rec.levels[10].eta, nil, "no level-start estimate without a measured rate (install level)")
  T.ok(ns.char ~= nil)
end)

T.test("dead: a crash gap is split over the places only (no dead / professions share)", function()
  local ns = Login()
  Stub.Advance(15)                           -- install sync at +10 s
  for _ = 1, 20 do Stub.Advance(60); Stub.GrantXP(40) end
  Stub.Die(); Stub.Advance(600); Stub.Resurrect(false)
  Stub.OpenTradeSkill(); Stub.Advance(600); Stub.CloseTradeSkill()
  Stub.Advance(60)
  ns.settings.requestPlayedAtLogin = false
  Stub.Restart({})
  Stub.SetMap(1413)
  Stub.Advance(3600)                         -- lost by the crash below
  ns = Stub.Restart({ crash = true })
  Stub.Advance(3)
  local ch = ns.char
  local x0, f0, w0 = ch.life.s.x, ch.life.s.f, ch.life.s.w
  T.ok(x0 >= 600 and f0 >= 600, "history holds dead and professions time")
  Stub.Fire("TIME_PLAYED_MSG", math.floor(Stub.server.total), math.floor(Stub.server.levelPlayed))
  T.ok((ch.life.est or 0) >= 3590, "gap re-added: " .. tostring(ch.life.est))
  T.eq(ch.life.s.x, x0, "no dead share"); T.eq(ch.life.s.f, f0, "no professions share")
  T.ok(ch.life.s.w - w0 >= 3590, "the gap went to the places")
end)

T.test("dead: zero garbage per steady tick while dead and as a ghost", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  local ns = Login()
  Stub.Advance(300)
  Stub.Die()
  Stub.Advance(60)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 dead ticks allocated %.2f KB"):format(kb))
  Stub.ReleaseSpirit()
  Stub.SetMap(1413)
  Stub.Advance(60)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ghost ticks allocated %.2f KB"):format(kb))
  T.eq(State(ns), "x")
  T.eq(Stub.onUpdateCount, 0)
end)
