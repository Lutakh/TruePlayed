-- tests/test_prof.lua - professions time (lot 8, A2): the "f" state from the heuristic of
-- Activity.lua (a trade skill or craft window open while standing still out of combat, a
-- profession cast or channel, the looting grace after gathering / fishing, a craft
-- queue), what it ignores (other spells, other units, Beast Training, a window left open
-- while moving or fighting), its precedence (dead > AFK > professions > flight > places),
-- names in any language, the breakdown and the Shift tooltip, zero garbage per tick.
local Stub, T = ...

local format = string.format

local function Login(db)
  if db then _G.TruePlayedDB = db end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  return ns
end

local function State(ns)
  return (ns.Tracker.GetState())
end

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

local function F(ns) return ns.char.life.s.f or 0 end

---------------------------------------------------------------------------

T.test("prof: a trade skill window open while standing still, out of combat", function()
  local ns = Login()
  Stub.Advance(10)
  Stub.OpenTradeSkill()
  T.eq(State(ns), "f", "at once (TRADE_SKILL_SHOW)")
  Stub.Advance(30)
  Stub.act.speed = 7                         -- running with the window still open
  Stub.Advance(1)
  T.eq(State(ns), "w", "not while moving")
  Stub.Advance(10)
  Stub.act.speed = 0
  Stub.Advance(1)
  T.eq(State(ns), "f")
  Stub.EnterCombat()
  Stub.Advance(1)
  T.eq(State(ns), "w", "not in combat")
  Stub.LeaveCombat()
  Stub.Advance(10)
  Stub.CloseTradeSkill()
  Stub.Advance(1)
  T.eq(State(ns), "w", "closed: back to the place on the next tick")
  local ch = ns.char
  -- 30 + 10 s; moving and combat are read on the tick (one second each way at most)
  T.ok(F(ns) >= 40 and F(ns) <= 43, "about 30 + 10 s: " .. F(ns))
  T.eq(ch.levels[10].s.f, ch.life.s.f, "level"); T.eq(ch.zones[1411].s.f, ch.life.s.f, "zone")
  T.eq(ns.session.s.f, ch.life.s.f, "session")
end)

T.test("prof: gathering cast, then the looting grace; an interrupted cast has none", function()
  local ns = Login()
  Stub.Advance(10)
  Stub.Spell("START", 2366)                  -- Herb Gathering
  T.eq(State(ns), "f")
  Stub.Advance(3)
  Stub.Spell("SUCCEEDED", 2366); Stub.Spell("STOP", 2366)
  Stub.Advance(4)
  T.eq(State(ns), "f", "looting (grace)")
  Stub.Advance(2)
  T.eq(State(ns), "w", "grace over after " .. ns.C.PROF_GRACE .. " s")
  T.eq(F(ns), 3 + ns.C.PROF_GRACE, "cast + grace")
  -- STOP before SUCCEEDED (either order): still the grace
  Stub.Spell("START", 2575); Stub.Advance(2); Stub.Spell("STOP", 2575); Stub.Spell("SUCCEEDED", 2575)
  Stub.Advance(1)
  T.eq(State(ns), "f", "mining: grace after STOP then SUCCEEDED")
  Stub.Advance(10)
  local f0 = F(ns)
  -- interrupted (moved): no grace
  Stub.Spell("START", 8613); Stub.Advance(1); Stub.Spell("INTERRUPTED", 8613); Stub.Spell("STOP", 8613)
  Stub.Advance(1)
  T.eq(State(ns), "w", "skinning interrupted: no grace")
  T.ok(F(ns) - f0 <= 2, "only the cast itself")
end)

T.test("prof: fishing channel (grace after it) and the first aid channel (none)", function()
  local ns = Login()
  Stub.Advance(10)
  Stub.Spell("CHANNEL_START", 7620)          -- Fishing
  Stub.Spell("SUCCEEDED", 7620)              -- the game sends it when a channel starts
  Stub.Advance(15)
  T.eq(State(ns), "f", "still fishing after SUCCEEDED")
  Stub.Spell("CHANNEL_STOP", 7620)           -- the bobber clicked: loot
  Stub.Advance(3)
  T.eq(State(ns), "f", "looting the catch")
  Stub.Advance(5)
  T.eq(State(ns), "w")
  local f0 = F(ns)
  Stub.Spell("CHANNEL_START", 10839)         -- First Aid (Heavy Mageweave Bandage)
  Stub.Advance(8)
  T.eq(State(ns), "f", "bandage channel")
  Stub.Spell("CHANNEL_STOP", 10839)
  Stub.Advance(1)
  T.eq(State(ns), "w", "no grace after a bandage")
  T.ok(F(ns) - f0 >= 8 and F(ns) - f0 <= 9, "the channel: " .. (F(ns) - f0))
end)

T.test("prof: other spells, other units and a stale cast are ignored", function()
  local ns = Login()
  Stub.Advance(5)
  Stub.Spell("START", 133)                   -- Fireball
  Stub.Advance(2)
  T.eq(State(ns), "w", "not a profession spell")
  Stub.Spell("SUCCEEDED", 133); Stub.Spell("STOP", 133)
  Stub.Spell("START", 2366, "target")        -- someone else gathering
  Stub.Spell("CHANNEL_START", 7620, "party1")
  Stub.Advance(2)
  T.eq(State(ns), "w", "other units' casts")
  Stub.Spell("START", 2366)
  Stub.Advance(ns.C.PROF_CAST_MAX + 2)       -- its end event never comes
  T.eq(State(ns), "w", "a cast without end is dropped after C.PROF_CAST_MAX s")
  T.eq(ns.Activity._Classify(133), nil); T.eq(ns.Activity._Classify(nil), nil)
  T.eq(ns.Activity._Classify(7732), 1, "every rank listed")
end)

T.test("prof: spells known by their localized name (any rank, any language)", function()
  Stub.spellNames[99001] = "Herb Gathering"  -- (the stub's default) a rank not in the list
  local ns = Login()
  Stub.Spell("START", 99001)
  T.eq(State(ns), "f", "name match")
  Stub.Reset()
  -- a French client: every name in French, an unlisted rank of "Cueillette"
  for id, name in pairs(Stub.spellNames) do
    if name == "Herb Gathering" then Stub.spellNames[id] = "Cueillette" end
  end
  Stub.spellNames[133] = "Boule de feu"
  ns = Login()
  Stub.Spell("START", 99001)
  T.eq(State(ns), "f", "Cueillette, unlisted rank")
  Stub.Spell("STOP", 99001)
  Stub.Advance(1)
  Stub.Spell("START", 133)
  Stub.Advance(1)
  T.eq(State(ns), "w", "Boule de feu is not a profession")
end)

T.test("prof: craft window (Enchanting yes, Beast Training no) and a craft queue", function()
  local ns = Login()
  Stub.OpenCraft("Beast Training")
  Stub.Advance(5)
  T.eq(State(ns), "w", "the hunter's Beast Training is not a profession")
  Stub.CloseCraft()
  Stub.OpenCraft("Enchanting")
  T.eq(State(ns), "f")
  Stub.CloseCraft()
  Stub.Advance(1)
  T.eq(State(ns), "w")
  -- trade skill: "Create all" started with the window open, the window then closed
  Stub.OpenTradeSkill()
  Stub.Spell("START", 2657)                  -- Copper Bar (Smelting)
  Stub.CloseTradeSkill()
  Stub.Advance(2)
  T.eq(State(ns), "f", "the cast started with the window open")
  Stub.Spell("SUCCEEDED", 2657); Stub.Spell("STOP", 2657)
  Stub.Spell("START", 2657)                  -- the next bar of the queue
  Stub.Advance(2)
  T.eq(State(ns), "f", "the queue goes on with the window closed")
  Stub.Spell("SUCCEEDED", 2657); Stub.Spell("STOP", 2657)
  Stub.Spell("START", 8690)                  -- Hearthstone: not the queue's spell
  Stub.Advance(2)
  T.eq(State(ns), "w", "another spell ends the queue")
  Stub.Spell("STOP", 8690)
end)

T.test("prof: precedence (dead > AFK > professions > flight > city > inn > world)", function()
  local ns = Login()
  Stub.SetMap(1454)                          -- Orgrimmar
  Stub.SetResting(true)
  T.eq(State(ns), "c")
  Stub.OpenTradeSkill()
  T.eq(State(ns), "f", "professions in a city are professions")
  Stub.Advance(20)
  Stub.SetAFK(true)
  T.eq(State(ns), "C", "AFK wins over professions (the AFK key of the place)")
  Stub.SetAFK(false)
  T.eq(State(ns), "f")
  Stub.Die()
  T.eq(State(ns), "x", "dead wins over professions")
  Stub.Resurrect(false)
  Stub.SetTaxi(true)
  T.eq(State(ns), "f", "professions over flight (a window open, the taxi standing still)")
  Stub.act.speed = 30
  Stub.Advance(1)
  T.eq(State(ns), "t", "flying: the open window is not professions time")
  Stub.SetTaxi(false); Stub.act.speed = 0
  Stub.CloseTradeSkill()
  Stub.Advance(1)
  T.eq(State(ns), "c")
  for m = 0, 7 do T.eq(ns.C.INCLUDED[m].f, true, "never excluded, mask " .. m) end
  -- 20 s, plus the second of take-off (the speed is read on the tick)
  T.eq(ns.char.zones[1454].s.f, 21, "the capital's bucket holds its professions time")
  T.eq(ns.char.zones[1454].s.c, 1, "city time only once the window is closed (the last second)")
end)

T.test("prof: a loading screen closes the windows and stops the casts", function()
  local ns = Login()
  Stub.OpenTradeSkill()
  Stub.Spell("CHANNEL_START", 7620)
  Stub.Advance(2)
  T.eq(State(ns), "f")
  Stub.Fire("PLAYER_LEAVING_WORLD")
  Stub.Fire("PLAYER_ENTERING_WORLD", false, false)
  Stub.Advance(1)
  T.eq(State(ns), "w")
end)

T.test("prof: breakdown part and the Shift tooltip line (only when there is any)", function()
  local ns = Login()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  Stub.Advance(120)
  T.no(Find(Fill(ns, true), L.TT_PROF), "no professions line without professions time")
  Stub.OpenTradeSkill(); Stub.Advance(180); Stub.CloseTradeSkill(); Stub.Advance(1)
  local bd = Stats.Breakdown(ns.char.life, {})
  T.eq(bd.prof, 180)
  local parts = {}
  T.eq(ns.Tooltip.BreakdownParts(bd, parts), 2)
  T.eq(parts[1], format(L.BD_PART_FMT, L.BD_PROF, Fmt.Percent(180 / bd.tracked, 0)), "largest first")
  local fracs, keys = {}, {}
  ns.Tooltip.BreakdownFracs(bd, fracs, keys)
  T.eq(keys, { "prof", "world" })
  T.eq(Find(Fill(ns, true), L.TT_PROF)[2], Fmt.Duration(180))
  T.no(Find(Fill(ns, false), L.TT_PROF), "Shift only")
  local _, _, prof = Stats.LevelActivity(ns.char, 10)
  T.eq(prof, 180, "per level")
  local sess = Stats.SessionHistory(ns.char, 0, {})
  T.eq(sess[1].prof, 180, "per session")
  local _, accProf = Stats.AccountActivity(ns.db)
  T.eq(accProf, 180, "account")
end)

T.test("prof: breakdown lines hold at most 4 parts once professions or dead show, balanced", function()
  local ns = Login()
  local L = ns.L
  local function Lines(s)
    ns.char.life.s = s
    local lines, out = Fill(ns, false), {}
    for i, l in ipairs(lines) do
      if l[1] == L.TT_BREAKDOWN then
        out[1] = l[2]
        local j = i + 1
        while lines[j] and lines[j][1] == " " do out[#out + 1] = lines[j][2]; j = j + 1 end
      end
    end
    return out
  end
  local function Parts(text) return select(2, text:gsub(L.SEP, "")) + 1 end
  -- no activity part: 5 a line, as before (5 + 2)
  local old = Lines({ w = 300, t = 100, W = 100, i = 100, c = 100, d = 100, r = 100 })
  T.eq({ #old, Parts(old[1]), Parts(old[2]) }, { 2, 5, 2 })
  -- 7 parts with professions and dead: 4 + 3
  local new = Lines({ w = 300, t = 100, f = 100, x = 100, W = 100, i = 100, c = 100 })
  T.eq({ #new, Parts(new[1]), Parts(new[2]) }, { 2, 4, 3 })
  T.ok(new[1]:find(L.BD_PROF, 1, true) and new[1]:find(L.BD_DEAD, 1, true), "in their place")
  -- 5 parts with dead: 3 + 2; 10 parts: 3 lines of at most 4 (4 + 4 + 2)
  local five = Lines({ w = 300, t = 100, x = 100, W = 100, i = 100 })
  T.eq({ #five, Parts(five[1]), Parts(five[2]) }, { 2, 3, 2 })
  local ten = Lines({ w = 300, d = 100, r = 100, p = 100, t = 100, f = 100, x = 100, W = 100, i = 100, c = 100 })
  T.eq({ #ten, Parts(ten[1]), Parts(ten[2]), Parts(ten[3]) }, { 3, 4, 4, 2 })
end)

T.test("prof: zero garbage per steady tick while crafting and fishing", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  local ns = Login()
  Stub.Advance(300)
  Stub.OpenTradeSkill()
  Stub.Advance(60)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks with a trade skill window open allocated %.2f KB"):format(kb))
  Stub.CloseTradeSkill()
  Stub.Spell("CHANNEL_START", 7620)
  Stub.Advance(2)
  kb = T.alloc(function() Stub.Advance(1) end, 50)
  T.ok(kb <= 1, ("50 ticks fishing allocated %.2f KB"):format(kb))
  T.eq(State(ns), "f")
  -- the grace running out and the place coming back allocate nothing either
  Stub.Spell("CHANNEL_STOP", 7620)
  kb = T.alloc(function() Stub.Advance(1) end, 20)
  T.ok(kb <= 1, ("20 ticks through the grace allocated %.2f KB"):format(kb))
  T.eq(State(ns), "w")
  T.eq(Stub.onUpdateCount, 0)
end)
