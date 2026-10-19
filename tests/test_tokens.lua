-- tests/test_tokens.lua - Tokens.lua and Tooltip.lua (IMPL-3), SPEC-FINAL 9.4.
-- Full addon load with prepared SavedVariables. The widget is hidden and LibStub is
-- removed, so the only token consumer is the one each test acquires ("test").
local Stub, T = ...

local format = string.format
local OTHER_GUID = "Player-4619-0BADF00D"

local function Ema(a, r, q, d)
  local t = {}
  for i = 1, 8 do t[i] = { a = a, r = r, q = q, d = d } end
  return t
end

-- Character record of the stub player (schema 4.1). By default: completed levels 5..L-1,
-- a settled EMA of ~20k XP/h, pre-install time, no sync and no crash estimate.
local function Record(opts)
  local p = Stub.player
  local lvl = opts.level or p.level
  local rec = {
    guid = p.guid, name = p.name, surname = p.surname, realm = p.realm, class = p.class,
    faction = p.faction, level = lvl, firstSeen = 1789900000, lastSeen = 1789990000,
    base = { at = 1789900000, total = 300000, level = 5 },
    life = { s = { w = 20000, W = 1200, i = 800, I = 400, c = 1500, C = 600, t = 300, T = 60, u = opts.u or 300000 },
             xp = 40000, xa = 30000, xr = 5000, xq = 5000, d = 3, est = opts.lifeEst or 0 },
    levels = {},
    zones = {
      [1411] = { s = { w = 20000, W = 1200, i = 800, I = 400 }, xp = 40000, name = "Durotar" },
      [1454] = { s = { c = 1500, C = 600, t = 300, T = 60 }, xp = 0, name = "Orgrimmar" },
    },
    sessions = {},
    ema = opts.ema or Ema(12000, 3000, 5000, 3600),
    srv = opts.srv,
    prior = opts.prior,
    lastKill = opts.lastKill,
    killRing = opts.killRing,                -- round 5: base XP of the last kills
    noXP = opts.noXP,                        -- C1: counted seconds since the last XP gain
    capLevel = opts.capLevel,                -- C2: detected server level cap
    rep = opts.rep,                          -- the followed reputation's rate (Reputation.lua)
    pvp = opts.pvp,                          -- the PvP rates (Pvp.lua)
  }
  if not opts.noHistory then
    for lv = 5, lvl - 1 do
      rec.levels[lv] = { s = { w = 3000, W = 200 }, xp = 5000, xa = 4000, xr = 500, xq = 500, d = 0,
                         est = 0, max = 5000, t0 = 1789900000 + lv * 1000, t1 = 1789900000 + lv * 1000 + 999,
                         z = { [1411] = { s = { w = 3000, W = 200 }, xp = 5000 } } }
    end
    rec.levels[lvl] = { s = { w = 1000, W = 60 }, xp = 3000, xa = 2400, xr = 300, xq = 300, d = 0,
                        est = opts.levelEst or 0, t0 = 1789990000,
                        z = { [1411] = { s = { w = 1000, W = 60 }, xp = 3000 } } }
  else
    rec.levels[lvl] = { s = { w = 100 }, xp = 0, xa = 0, xr = 0, xq = 0, d = 0, est = 0, z = {} }
  end
  return rec
end

-- Another character with the same name and huge numbers (isolation, 5.19).
local function OtherRecord()
  local big = 9000000
  return {
    guid = OTHER_GUID, name = Stub.player.name, realm = "Brisevent", class = "WARRIOR", faction = "Horde",
    level = 10, firstSeen = 1789000000, lastSeen = 1789500000,
    base = { at = 1789000000, total = 100, level = 1 },
    life = { s = { w = big, W = big, c = big, u = big }, xp = big, xa = big, xr = 0, xq = 0, d = 99, est = big },
    levels = { [10] = { s = { w = big }, xp = big, xa = big, xr = 0, xq = 0, d = 0, est = big, z = {} },
               [9] = { s = { w = big }, xp = big, xa = big, xr = 0, xq = 0, d = 0, z = {} },
               [8] = { s = { w = big }, xp = big, xa = big, xr = 0, xq = 0, d = 0, z = {} } },
    zones = { [1411] = { s = { w = big }, xp = big, name = "Durotar" } },
    sessions = { { t0 = 1, t1 = 2, l0 = 9, l1 = 10, s = { w = big }, xp = big, d = 0 } },
    cur = { t0 = 3, l0 = 10, s = { w = big, W = big }, xp = big, d = 0 },
    ema = Ema(big, 0, 0, 3600),
    srv = { total = 99999999, level = 10, at = 1789500000, g = 5, ext = true },
  }
end

-- The followed reputation with a settled rate of 500 points per hour (opts.rep of Start):
-- Darnassus, Friendly, 1,200 / 6,000.
local function RepData()
  Stub.rep.watched = { name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 }
  local e = {}
  for i = 1, 8 do e[i] = { a = 500, d = 3600 } end
  return { f = 69, v = 4200, e = e, n = 0 }
end

-- WoW Forever's PvP (tests/stub_pvp.lua): a season running, rank 1, and both PvP rates
-- measured (the last gain a minute before the login: not paused).
local function PvpData()
  Stub.SetPvpAPI("forever")
  Stub.SetWeek(2, 5, 3, { quiet = true })
  Stub.pvp.total = 1000
  local he, ke = {}, {}
  for i = 1, 8 do
    he[i] = { a = 3000, d = 3600 }
    ke[i] = { a = 900, d = 3600 }
  end
  return { he = he, ke = ke, g = time() - 60 }
end

-- Loads the addon on a prepared TruePlayedDB and logs in (XP baseline read at +2 s).
local function Start(opts)
  opts = opts or {}
  rawset(_G, "LibStub", nil)                 -- no LDB consumer in this file
  if opts.locale then Stub.locale = opts.locale end
  local p = Stub.player
  if opts.level then
    p.level = opts.level
    p.max = Stub.xpTable[opts.level] or 0
  end
  p.xp = opts.xp or 3000
  p.rest = opts.rest or 1000
  local db = {
    schema = 1, createdAt = 1789900000,
    settings = { widget = { shown = false }, requestPlayedAtLogin = false },
    cities = {}, xpMax = {}, chars = {},
  }
  db.chars[p.guid] = Record(opts)
  if opts.other then db.chars[OTHER_GUID] = OtherRecord() end
  _G.TruePlayedDB = db
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns
end

-- Simulates a /played answer that matches what the addon knows (no gap to re-add).
local function LiveSync(ns)
  local Stats = ns.Stats
  local char = ns.char
  Stub.Fire("TIME_PLAYED_MSG", math.floor(Stats.SumAll(char.life)), math.floor(Stats.SumAll(char.levels[char.level])))
  Stub.Advance(0)
end

-- Fills the GameTooltip mock and returns its lines as { left, right } pairs.
local function Fill(ns, detailed)
  local tt = GameTooltip
  tt:ClearLines()
  ns.Tooltip.Fill(tt, detailed)
  local out = {}
  local lines = tt._lines or {}
  for i = 1, #lines do
    local l = lines[i]
    out[i] = { l[1] or l.left, l[2] or l.right }
  end
  return out
end

local function Find(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i] end
  end
  return nil
end

-- True when text is an output of the format string fmt (every %s matched lazily).
local function MatchesFormat(text, fmt)
  if type(text) ~= "string" then return false end
  local p = fmt:gsub("%%s", "@@@")
  p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  p = p:gsub("@@@", ".-")
  return text:find("^" .. p .. "$") ~= nil
end

local function HasText(lines, text)
  for i = 1, #lines do
    if lines[i][1] == text or lines[i][2] == text then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Tokens
---------------------------------------------------------------------------

T.test("every token renders a non-empty text with data", function()
  local ns = Start({ lastKill = { xp = 120, level = 10, at = 1789990000 }, rep = RepData(), pvp = PvpData() })
  LiveSync(ns)
  local Tokens, Stats, Fmt, L = ns.Tokens, ns.Stats, ns.Fmt, ns.L
  Tokens.Acquire("test", 3)
  local ctx = Tokens.ctx
  T.ok(ctx.valid, "XP baseline read")
  T.eq(ctx.rateStatus, "ok")
  T.ok(ctx.playedLive, "sync received")
  for _, id in ipairs(Tokens.ORDER) do
    local text, dim, paused = Tokens.Render(id)
    T.eq(type(text), "string", id)
    T.eq(type(dim), "boolean", id)
    T.eq(type(paused), "boolean", id)
    if id == "none" then
      T.eq(text, "")
    else
      T.ok(text ~= "" and text ~= L.DOTS, id .. " has a value")
      T.no(dim, id .. " not dim")
    end
    T.ok(Tokens.Label(id) ~= nil and Tokens.Label(id) ~= "", id .. " label")
  end
  -- values come from Stats with the context of the current character
  local now = Stub.Now()
  local sync = ns.Tracker.GetSync()
  local played = Stats.Played(ns.char, 0, sync, now)
  T.eq((Tokens.Render("played")), format(L.PFX_PLAYED_FMT, Fmt.Duration(played)))
  T.eq((Tokens.Render("xph")), Fmt.Rate(ctx.xph))
  -- the followed reputation: 500 points per hour, 4,800 points to Honored
  T.eq((Tokens.Render("reph")), format(L.PFX_REPH_FMT, Fmt.Rate(500)))
  T.eq((Tokens.Render("rep_eta")), format(L.REP_ETA_FMT, "Honored", Fmt.ETA(4800 / 500 * 3600)))
  T.eq((Tokens.Render("eta")), Fmt.ETA(ctx.eta))
  T.eq((Tokens.Render("xpleft")), format(L.XPLEFT_FMT, Fmt.Number(ctx.max - ctx.xp)))
  T.eq((Tokens.Render("zone_time")), format(L.PFX_ZONE_FMT, Fmt.Duration(Stats.Sum(ns.char.zones[1411], 0))))
  T.eq((Tokens.Render("fps_latency")), Fmt.FPSLatency(Stub.fps, math.max(Stub.net.home, Stub.net.world)))
  -- cached strings: same object while the display key does not change
  T.ok(rawequal((Tokens.Render("played")), (Tokens.Render("played"))))
  -- unknown id
  local text, dim, paused = Tokens.Render("no_such_token")
  T.eq(text, "")
  T.no(dim)
  T.no(paused)
end)

T.test("eta and xph are dim while warming", function()
  local ns = Start({ ema = Ema(400, 0, 100, 300), noHistory = true })
  local Tokens, Fmt = ns.Tokens, ns.Fmt
  ns.char.prior = nil                        -- tracked data only (no pre-install estimate)
  Tokens.Acquire("test", 3)
  local ctx = Tokens.ctx
  T.eq(ctx.rateStatus, "warming")
  T.eq(ctx.etaStatus, "warming")
  local text, dim = Tokens.Render("eta")
  T.eq(text, Fmt.ETA(ctx.eta))
  T.ok(dim)
  text, dim = Tokens.Render("xph")
  T.eq(text, Fmt.Rate(ctx.xph))
  T.ok(dim)
  T.ok(select(2, Tokens.Render("pcth")), "pcth dim")
  -- the tooltip says when the estimate settles
  local lines = Fill(ns, false)
  local line = Find(lines, ns.L.TT_NEXT_LEVEL)
  T.ok(line, "next level line")
  T.eq(line[2], format(ns.L.TT_WARMING_FMT, Fmt.Duration(ctx.warmupLeft)))
end)

T.test("eta and xph show dots, dim, without any data; the tooltip says what is missing", function()
  local ns = Start({ ema = Ema(0, 0, 0, 0), noHistory = true })
  local Tokens, L, Fmt = ns.Tokens, ns.L, ns.Fmt
  ns.char.prior = nil                        -- a brand-new character: nothing to estimate from
  Tokens.Acquire("test", 3)
  T.eq(Tokens.ctx.rateStatus, "nodata")
  for _, id in ipairs({ "eta", "xph", "pcth" }) do
    local text, dim = Tokens.Render(id)
    T.eq(text, L.DOTS, id)
    T.ok(dim, id)
  end
  local lines = Fill(ns, false)
  T.eq(Find(lines, L.TT_NEXT_LEVEL)[2], L.TT_NO_RATE)
  -- never an unexplained "...": counted play still needed (C.WARMUP_FULL = 10 min)
  local left = Tokens.ctx.warmupLeft
  T.ok(left >= 60, "warm-up left")
  T.eq(Find(lines, L.TT_XPH)[2], format(L.TT_NODATA_FMT, Fmt.Duration(left)))
  -- enough counted time but no XP gained yet: the first XP gain is what is missing
  -- (real Stats.Rate: a complete EMA sample of C.WARMUP_FULL + 100 s without any XP)
  ns.char.ema = Ema(0, 0, 0, ns.C.WARMUP_FULL + 100)
  T.eq(select(6, ns.Stats.Rate(ns.char, Tokens.ctx.mask or 0)), "nodata")
  T.eq(Find(Fill(ns, false), L.TT_XPH)[2], L.TT_NODATA_XP)
  for i = 1, #lines do
    T.ok(lines[i][2] ~= L.DOTS or lines[i][1] == L.TT_SERVER, "no bare dots: " .. tostring(lines[i][1]))
  end
end)

-- A character installed with play time behind it: rate from the pre-install estimate.
local function EstimateStart(locale)
  return Start({ ema = Ema(0, 0, 0, 0), noHistory = true, prior = { xph = 4500, at = 1789990000 },
                 locale = locale })
end

T.test("estimate from /played: '~' on the rate tokens, not dimmed, kept while paused", function()
  local ns = EstimateStart()
  local Tokens, Fmt = ns.Tokens, ns.Fmt
  Tokens.Acquire("test", 3)
  local ctx = Tokens.ctx
  T.eq(ctx.rateStatus, "estimate")
  T.eq(ctx.rateSrc, "prior")
  T.eq(ctx.etaStatus, "estimate")
  local text, dim = Tokens.Render("xph")
  T.eq(text, "~" .. Fmt.Rate(4500))
  T.eq(text, "~4.5k/h")
  T.no(dim, "an estimate is not dimmed")
  text, dim = Tokens.Render("eta")
  T.eq(text, Fmt.ETA(ctx.eta), "the ETA text already starts with ~")
  T.eq(text:sub(1, 1), "~")
  T.no(dim)
  text = Tokens.Render("pcth")
  T.eq(text:sub(1, 1), "~")
  T.eq(Tokens.Approx("<1m"), "~<1m")
  T.eq(Tokens.Approx("~1h 25m"), "~1h 25m", "never doubled")
  -- the estimate stays visible (dim + pause marks) while the chrono is paused
  ns.Core.SetSetting("exclude.afk", true)
  Stub.SetAFK(true)
  Stub.Advance(1)
  local paused
  text, dim, paused = Tokens.Render("xph")
  T.eq(text, "~4.5k/h")
  T.ok(dim)
  T.ok(paused)
  T.ok(Tokens.ctx.paused)
  -- switching to real data drops the "~" at once (cache keyed by the estimate flag)
  ns.char.prior = nil
  ns.char.ema = Ema(4500 * 3600 / 3600, 0, 0, 3600)
  Tokens.UpdateContext(Stub.Now())
  T.eq(Tokens.ctx.rateStatus, "ok")
  T.eq((Tokens.Render("xph")), "4.5k/h")
end)

T.test("estimate from /played: the tooltip shows ~value and the dimmed source (en, fr)", function()
  for _, locale in ipairs({ "enUS", "frFR" }) do
    Stub.Reset()
    local ns = EstimateStart(locale)
    local Tokens, Fmt, L, CC = ns.Tokens, ns.Fmt, ns.L, ns.C.CC
    Tokens.Acquire("test", 3)
    local lines = Fill(ns, false)
    local rate = Find(lines, L.TT_XPH)
    T.eq(rate[2], format("~%s %s(%s)%s", Fmt.Rate(4500), CC.dim, L.RATE_ESTIMATE, CC.reset), locale)
    local eta = Find(lines, L.TT_NEXT_LEVEL)
    T.eq(eta[2], format("%s %s(%s)%s", Fmt.ETA(Tokens.ctx.eta), CC.dim, L.RATE_ESTIMATE, CC.reset), locale)
    if locale == "frFR" then
      T.ok(rate[2]:find("~4,5k/h", 1, true) == 1, "French decimal comma")
      T.ok(rate[2]:find("estimation d'après votre /played", 1, true) ~= nil)
    end
    -- detailed view: no "based on this level" note for an estimate
    local det = Fill(ns, true)
    T.no(HasText(det, L.TT_SRC_LEVEL))
    T.no(HasText(det, L.TT_SRC_RECENT))
  end
end)

T.test("detailed tooltip: continents section with the exclusions applied", function()
  local ns = Start()
  local L, Fmt = ns.L, ns.Fmt
  ns.char.zones.i389 = { s = { w = 900 }, xp = 1200, name = "Ragefire Chasm" }
  ns.char.zones.o = { s = { w = 90 }, xp = 0 }
  local lines = Fill(ns, true)
  local head
  for i = 1, #lines do
    if lines[i][1] == L.SECTION_CONTINENTS then head = i end
  end
  T.ok(head ~= nil, "continents header")
  -- Durotar + Orgrimmar are both on Kalimdor (stub maps), then the instance; the time
  -- without a continent (the neutral bucket) is not listed
  local kal = 20000 + 1200 + 800 + 400 + 1500 + 600 + 300 + 60
  T.eq(lines[head + 1], { "Kalimdor", Fmt.Duration(kal) })
  T.eq(lines[head + 2], { L.BD_DUNGEON, Fmt.Duration(900) })
  T.no(HasText(lines, "Other"), "no Other row")
  T.no(HasText(Fill(ns, false), L.SECTION_CONTINENTS), "detailed view only")
  ns.Core.SetSetting("exclude.city", true)
  lines = Fill(ns, true)
  local row = Find(lines, "Kalimdor")
  T.eq(row[2], Fmt.Duration(kal - 1500 - 600), "city time left out")
  -- a continent whose time is all excluded keeps its line, last, valued like the zones
  -- above ("< 1 min"): the section never vanishes in town with the city excluded (FB1-F5)
  ns.char.zones[1453] = { s = { c = 5000, C = 400 }, xp = 0, name = "Stormwind City" }
  lines = Fill(ns, true)
  for i = 1, #lines do
    if lines[i][1] == L.SECTION_CONTINENTS then head = i end
  end
  T.eq(lines[head + 1], { "Kalimdor", Fmt.Duration(kal - 1500 - 600) })
  T.eq(lines[head + 2], { L.BD_DUNGEON, Fmt.Duration(900) })
  T.eq(lines[head + 3], { "Eastern Kingdoms", Fmt.Duration(0) })
  -- all three exclusions and only city time: the section still lists the continent
  ns.char.zones = { [1453] = ns.char.zones[1453] }
  ns.Core.SetSetting("exclude.afk", true)
  ns.Core.SetSetting("exclude.inn", true)
  lines = Fill(ns, true)
  head = nil
  for i = 1, #lines do
    if lines[i][1] == L.SECTION_CONTINENTS then head = i end
  end
  T.ok(head ~= nil, "continents header with everything excluded")
  T.eq(lines[head + 1], { "Eastern Kingdoms", Fmt.Duration(0) })
end)

T.test("pausable tokens are dim and paused while the current state is excluded", function()
  local ns = Start()
  local Tokens, DEF, L = ns.Tokens, ns.Tokens.DEF, ns.L
  Tokens.Acquire("test", 3)
  ns.Core.SetSetting("exclude.afk", true)
  Stub.SetAFK(true)
  Stub.Advance(1)
  local ctx = Tokens.ctx
  T.ok(ctx.paused, "paused")
  T.eq(ctx.pauseReason, "afk")
  for _, id in ipairs(Tokens.ORDER) do
    local _, dim, paused = Tokens.Render(id)
    if DEF[id].pausable then
      T.ok(paused, id .. " paused")
      T.ok(dim, id .. " dim")
    else
      T.no(paused, id .. " not pausable")
    end
  end
  local lines = Fill(ns, false)
  T.ok(HasText(lines, format(L.TT_PAUSED_FMT, L.PAUSE_AFK)), "tooltip pause line")
  -- the exclusion is only a filter: switching it off un-pauses at once
  ns.Core.SetSetting("exclude.afk", false)
  T.no(Tokens.ctx.paused)
  local _, dim, paused = Tokens.Render("played")
  T.no(paused)
  T.no(dim)
end)

T.test("Resolve falls back to the slot default for unknown ids", function()
  local ns = Start()
  local Tokens = ns.Tokens
  T.eq(Tokens.DefaultSlot(1), "eta_kills", "time to level + mobs to kill by default")
  T.eq(Tokens.DefaultSlot(2), "xph")
  T.eq(Tokens.DefaultSlot(3), "fps_latency")
  T.eq(Tokens.DefaultSlot(1, true), "session")
  T.eq(Tokens.DefaultSlot(4), "none")
  T.eq(Tokens.Resolve(1), "eta_kills")
  ns.settings.widget.slots[1] = "removed_in_a_future_version"
  T.eq(Tokens.Resolve(1), "eta_kills")
  ns.settings.widget.slots[2] = "played"
  T.eq(Tokens.Resolve(2), "played")
  ns.settings.widget.slots[3] = nil
  T.eq(Tokens.Resolve(3), "fps_latency")
end)

T.test("Resolve swaps XP tokens for the max-level slots", function()
  local ns = Start({ level = 60 })
  local Tokens, L = ns.Tokens, ns.L
  T.ok(ns.Tracker.IsMax(), "max level")
  T.eq(Tokens.Resolve(1), "session")
  T.eq(Tokens.Resolve(2), "played")
  T.eq(Tokens.Resolve(3), "fps_latency")
  ns.settings.widget.maxSlots[2] = "xph"          -- an XP token is never shown at max level
  T.eq(Tokens.Resolve(2), "none")
  ns.settings.widget.maxSlots[1] = "bogus"
  T.eq(Tokens.Resolve(1), "session")
  ns.settings.widget.slots[3] = "rested"
  ns.settings.widget.maxSlots[3] = "zone_time"
  T.eq(Tokens.Resolve(3), "zone_time")
  -- rendering an XP token anyway shows the max-level text
  Tokens.Acquire("test", 3)
  T.eq(Tokens.ctx.etaStatus, "max")
  T.eq((Tokens.Render("eta")), L.MAX_LEVEL)
  -- the tooltip replaces the XP block
  local lines = Fill(ns, false)
  T.ok(HasText(lines, L.TT_MAX_LEVEL), "max level line")
  T.no(Find(lines, L.TT_XP), "no XP line")
  T.no(Find(lines, L.TT_NEXT_LEVEL), "no next level line")
end)

T.test("English and French texts", function()
  local ns = Start({ ema = Ema(8200, 0, 0, 3600) })
  local Tokens, L = ns.Tokens, ns.L
  Tokens.Acquire("test", 3)
  T.eq((Tokens.Render("xpleft")), "4,600 XP to go")
  T.eq((Tokens.Render("rested")), "Rested 13%")
  T.eq((Tokens.Render("xph")), "8.2k/h")
  T.eq(Tokens.Label("eta"), "Time to next level")
  T.eq(L.TOKEN_ETA, "Time to next level")
end)

T.test("French texts", function()
  local ns = Start({ locale = "frFR", ema = Ema(8200, 0, 0, 3600) })
  local Tokens = ns.Tokens
  Tokens.Acquire("test", 3)
  T.eq((Tokens.Render("xpleft")), "4\194\160600 XP restants")
  T.eq((Tokens.Render("rested")), "Repos 13 %")
  T.eq((Tokens.Render("xph")), "8,2k/h")
  T.eq(Tokens.Label("eta"), "Temps avant le prochain niveau")
  local lines = Fill(ns, false)
  T.ok(Find(lines, "Niveau en cours"), "French title of the level section")
  T.no(Find(lines, "Temps de jeu"), "the played time is in the detailed view")
  lines = Fill(ns, true)
  T.ok(Find(lines, "Total du personnage"), "French title of the character section")
  T.ok(Find(lines, "Temps de jeu"), "French played label")
end)

T.test("FPS and latency are sampled only for a visible slot that shows them", function()
  local fpsCalls, netCalls = 0, 0
  local origFps, origNet = GetFramerate, GetNetStats
  GetFramerate = function() fpsCalls = fpsCalls + 1; return origFps() end   -- before LoadAddon
  GetNetStats = function() netCalls = netCalls + 1; return origNet() end
  local ns = Start()
  local Tokens = ns.Tokens
  T.no(Tokens.IsActive())
  Stub.Advance(10)
  T.eq(fpsCalls, 0, "no consumer")
  T.eq(netCalls, 0, "no consumer")
  Tokens.Acquire("test", 2)                       -- eta + xph only
  Stub.Advance(10)
  T.eq(fpsCalls, 0, "slots 1-2 do not show FPS")
  T.eq(netCalls, 0, "slots 1-2 do not show latency")
  Tokens.Acquire("test", 3)                       -- slot 3 = fps_latency
  fpsCalls, netCalls = 0, 0
  Stub.Advance(10)
  for i = 1, 3 do Tokens.Render(Tokens.Resolve(i)) end
  T.ok(fpsCalls >= 9 and fpsCalls <= 11, format("about 1 FPS read per tick (%d)", fpsCalls))
  T.ok(netCalls >= 1 and netCalls <= 3, format("latency at most every 5 s (%d)", netCalls))
  Tokens.Release("test")
  T.no(Tokens.IsActive())
  fpsCalls, netCalls = 0, 0
  Stub.Advance(10)
  T.eq(fpsCalls, 0, "released")
  T.eq(netCalls, 0, "released")
  GetFramerate, GetNetStats = origFps, origNet
end)

T.test("the context is refreshed by the ticker only while a consumer is active", function()
  local ns = Start()
  local Tokens = ns.Tokens
  local before = Tokens.ctx.now
  Stub.Advance(3)
  T.eq(Tokens.ctx.now, before, "idle: no refresh")
  Tokens.Acquire("test", 1)
  local acquired = Tokens.ctx.now
  Stub.Advance(2)
  T.ok(Tokens.ctx.now > acquired and Stub.Now() - Tokens.ctx.now < 1, "refreshed by the ticker")
  Tokens.Release("test")
  local frozen = Tokens.ctx.now
  Stub.Advance(2)
  T.eq(Tokens.ctx.now, frozen)
end)

T.test("tokens and tooltip read only the current character (5.19)", function()
  local ns = Start({ other = true })
  local Tokens, Stats, Fmt, L = ns.Tokens, ns.Stats, ns.Fmt, ns.L
  T.eq(ns.char.guid, Stub.player.guid)
  T.ok(ns.db.chars[OTHER_GUID], "other record kept")
  Tokens.Acquire("test", 3)
  local char = ns.char
  local playedText = format(L.PFX_PLAYED_FMT, Fmt.Duration(Stats.SumAll(char.life)))
  T.eq((Tokens.Render("played")), playedText)
  T.eq((Tokens.Render("zone_time")), format(L.PFX_ZONE_FMT, Fmt.Duration(Stats.Sum(char.zones[1411], 0))))
  T.eq((Tokens.Render("level_time")), format(L.PFX_LEVEL_FMT, Fmt.Duration(Stats.SumAll(char.levels[10]))))
  local recent = Stats.RecentAvg(char, 0, ns.C.RECENT_LEVELS)
  T.eq((Tokens.Render("avg_level")), format(L.PFX_AVG_FMT, Fmt.Duration(recent)))
  T.ok(Tokens.ctx.xph < 100000, "rate from the current EMA")
  T.eq((Tokens.Render("played_server")), L.DOTS, "no sync and no srv for this character")
  T.ok(Tokens.ctx.sessionTime < 60, "session of this load")

  local lines = Fill(ns, true)
  local played = Find(lines, L.TT_PLAYED)
  T.ok(played, "played line")
  T.eq(played[2], Fmt.Duration(Stats.SumAll(char.life)))
  T.no(HasText(lines, format(L.TT_EST_FMT, Fmt.Duration(9000000))), "no estimate from the other record")
  -- no cross-character figure at all (lot 8: the account lines moved to the window)
  T.no(Find(lines, format(L.TT_ACCOUNT_FMT, 2)), "no account line")
  for i = 1, #lines do
    T.no(lines[i][2] == Fmt.Duration(Stats.Account(ns.db, 0)), "no account total: " .. tostring(lines[i][1]))
  end
end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

T.test("tooltip shows the rebuilt-after-crash lines when est > 0", function()
  local ns = Start({ lifeEst = 2100, levelEst = 600 })
  local L, Fmt = ns.L, ns.Fmt
  local lines = Fill(ns, false)
  T.no(HasText(lines, format(L.TT_EST_FMT, Fmt.Duration(2100))), "no played sub-line: the short view is the level")
  T.ok(HasText(lines, format(L.TT_EST_FMT, Fmt.Duration(600))), "this level sub-line")
  -- lot 8: the detailed view repeats nothing at the bottom (the sub-lines say it)
  local detailed = Fill(ns, true)
  T.ok(HasText(detailed, format(L.TT_EST_FMT, Fmt.Duration(600))), "this level sub-line (Shift)")
  local n = 0
  for i = 1, #detailed do
    if HasText({ detailed[i] }, format(L.TT_EST_FMT, Fmt.Duration(2100))) then n = n + 1 end
    T.no(detailed[i][1] == "Rebuilt after crashes", "no bottom estimate line")
    T.no(detailed[i][2] and string.find(detailed[i][2], "(estimated split)", 1, true), "no estimated split")
  end
  T.eq(n, 1, "the played sub-line only, once")
end)

-- Crash review A1: the rebuilt part noted under "This level" / "Played" is valued under the
-- same exclusions as that line, and never exceeds it.
T.test("tooltip: the rebuilt time is under the exclusions of the line above, never more than it", function()
  local ns = Start()
  local L, Fmt = ns.L, ns.Fmt
  local lb = ns.char.levels[ns.char.level]
  -- the reported case: 10 min of play and 50 min of AFK rebuilt after a crash
  lb.s = { w = 600, W = 3000 }
  lb.est, lb.es = 3000, { W = 3000 }
  local lines = Fill(ns, false)
  T.eq(Find(lines, L.TT_THIS_LEVEL)[2], Fmt.DurationFull(3600))
  T.ok(HasText(lines, format(L.TT_EST_FMT, Fmt.Duration(3000))), "no exclusion: all of it")
  ns.Core.SetSetting("exclude.afk", true)
  lines = Fill(ns, false)
  T.eq(Find(lines, L.TT_THIS_LEVEL)[2], Fmt.DurationFull(600), "This level, AFK excluded")
  for i = 1, #lines do
    T.no(MatchesFormat(lines[i][1], L.TT_EST_FMT), "the rebuilt part was AFK: no sub-line")
  end
  -- an older record (est without es): the level's own place shares, 3000 x 600 / 3600
  lb.es = nil
  lines = Fill(ns, false)
  T.ok(HasText(lines, format(L.TT_EST_FMT, Fmt.Duration(500))), "older record: its share of the 10 min")
  T.no(HasText(lines, format(L.TT_EST_FMT, Fmt.Duration(3000))), "never the gross 50 min")
  -- the character (Shift): the same rules, at most the played time shown
  lb.es = { W = 3000 }
  local life = ns.char.life
  life.s.W = life.s.W + 3000
  life.est, life.es = 3000, { W = 3000 }
  local detailed = Fill(ns, true)
  for i = 1, #detailed do
    T.no(MatchesFormat(detailed[i][1], L.TT_EST_FMT), "AFK excluded: no rebuilt sub-line, level or played")
  end
  ns.Core.SetSetting("exclude.afk", false)
  detailed = Fill(ns, true)
  local n = 0
  for i = 1, #detailed do
    if detailed[i][1] == format(L.TT_EST_FMT, Fmt.Duration(3000)) then n = n + 1 end
  end
  T.eq(n, 2, "this level and played, no exclusion")
  -- /tpl played prints the same sub-line, under the exclusions too
  local estPat = L.TT_EST_FMT:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("%%%%s", "(.-)") .. "$"
  local function PrintedEst()               -- durations of the printed rebuilt sub-lines
    local out = {}
    for i = 1, #Stub.printed do
      local d = Stub.printed[i]:match(estPat)
      if d then out[#out + 1] = d end
    end
    Stub.printed = {}
    return out
  end
  Stub.printed = {}
  Stub.RunSlash("played")
  T.eq(PrintedEst(), { Fmt.Duration(3000) }, "/tpl played: the rebuilt part")
  ns.Core.SetSetting("exclude.afk", true)
  Stub.RunSlash("played")
  T.eq(PrintedEst(), {}, "/tpl played, AFK excluded: no rebuilt sub-line")
end)

-- Crash review A2: under a breakdown more than C.EST_MOST rebuilt (gross share of its
-- tracked time: the breakdown has no exclusions), a note says its split is estimated.
T.test("tooltip: a breakdown mostly rebuilt after a crash says so, right under it", function()
  local ns = Start()
  local L, Fmt, C = ns.L, ns.Fmt, ns.C
  T.eq(C.EST_MOST, 0.5)
  local lb = ns.char.levels[ns.char.level]
  lb.s = { w = 1000, W = 60 }                 -- 1060 s tracked
  local function Notes(lines)
    local out = {}
    for i = 1, #lines do
      if MatchesFormat(lines[i][1], L.TT_EST_MOST_FMT) then out[#out + 1] = i end
    end
    return out
  end
  -- exactly half: no note
  lb.est, lb.es = 530, { w = 530 }
  T.eq(Notes(Fill(ns, false)), {}, "50 %: no note")
  -- more than half: the note, after the level's breakdown rows
  lb.est, lb.es = 600, { w = 540, W = 60 }
  local lines = Fill(ns, false)
  local idx = Notes(lines)
  T.eq(#idx, 1)
  T.eq(lines[idx[1]][1], format(L.TT_EST_MOST_FMT, Fmt.Percent(600 / 1060, 0)))
  local bd = 0
  for i = 1, #lines do if lines[i][1] == L.TT_BREAKDOWN_LEVEL then bd = i end end
  T.ok(bd > 0 and idx[1] > bd, "below the breakdown")
  for i = bd + 1, idx[1] - 1 do T.eq(lines[i][1], " ", "only its continuation rows between") end
  -- the gross share, whatever the exclusions (the breakdown shows every key)
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(#Notes(Fill(ns, false)), 1, "AFK excluded: still the breakdown's share")
  ns.Core.SetSetting("exclude.afk", false)
  -- an older record (est only) larger than the level: capped at 100 %
  lb.es, lb.est = nil, 5000
  lines = Fill(ns, false)
  T.eq(lines[Notes(lines)[1]][1], format(L.TT_EST_MOST_FMT, Fmt.Percent(1, 0)), "at most 100 %")
  -- the character (Shift): its own share, under its own breakdown
  lb.est, lb.es = 0, nil
  T.eq(Notes(Fill(ns, true)), {}, "neither breakdown mostly rebuilt")
  local life = ns.char.life
  local tracked = ns.Stats.Tracked(life)
  life.est, life.es = 20000, { w = 18000, W = 1200, c = 800 }
  lines = Fill(ns, true)
  idx = Notes(lines)
  T.eq(#idx, 1, "the character's breakdown only")
  T.eq(lines[idx[1]][1], format(L.TT_EST_MOST_FMT, Fmt.Percent(20000 / tracked, 0)))
  local bds = {}
  for i = 1, #lines do
    if lines[i][1] == L.TT_BREAKDOWN_LEVEL or lines[i][1] == L.TT_BREAKDOWN_TOTAL then bds[#bds + 1] = i end
  end
  T.eq(#bds, 2)
  T.eq({ lines[bds[1]][1], lines[bds[2]][1] }, { L.TT_BREAKDOWN_LEVEL, L.TT_BREAKDOWN_TOTAL })
  T.ok(idx[1] > bds[2], "under the character's breakdown")
  T.eq(Notes(Fill(ns, false)), {}, "the short view has no character breakdown")
  lb.est, lb.es = 1000, { w = 1000 }
  T.eq(#Notes(Fill(ns, true)), 2, "both breakdowns")
end)

T.test("tooltip has no rebuilt-after-crash line without an estimate", function()
  local ns = Start()
  local L = ns.L
  local lines = Fill(ns, true)
  for i = 1, #lines do
    T.no(MatchesFormat(lines[i][1], L.TT_EST_FMT), "no est sub-line")
  end
end)

T.test("tooltip shows the pre-install line only with an exclusion", function()
  local ns = Start({ u = 300000 })
  local L, Fmt = ns.L, ns.Fmt
  local pre = format(L.TT_PREINSTALL_FMT, Fmt.Duration(300000))
  T.no(HasText(Fill(ns, true), pre), "no exclusion")
  ns.Core.SetSetting("exclude.afk", true)
  local excl = ns.Stats.MaskLabel(1)
  local short = Fill(ns, false)
  T.no(HasText(short, pre), "the short view is the level: no pre-install line")
  T.ok(HasText(short, format(L.TT_EXCL_FMT, excl)), "title shows the exclusion (short view)")
  local lines = Fill(ns, true)
  T.ok(HasText(lines, pre), "exclusion on")
  T.ok(Find(lines, format(L.TT_PLAYED_EXCL_FMT, excl)), "played label names the exclusion")
  T.ok(HasText(lines, format(L.TT_EXCL_FMT, excl)), "title shows the exclusion")
  local untracked = Find(Fill(ns, true), L.TT_UNTRACKED)
  T.eq(untracked[2], format("%s (%s)", Fmt.Duration(300000), L.TT_UNTRACKED_NOTE))
end)

T.test("tooltip server line: saved snapshot with its age, then live", function()
  local at = 1790000000 - 3600
  local ns = Start({ srv = { total = 400000, levelPlayed = 900, level = 10, at = at, g = 1, ext = true } })
  local L, Fmt, Tokens = ns.L, ns.Fmt, ns.Tokens
  T.no(Find(Fill(ns, false), L.TT_SERVER), "the server /played is in the detailed view")
  local lines = Fill(ns, true)
  local line = Find(lines, L.TT_SERVER)
  T.ok(line, "server line")
  T.eq(line[2], format(L.TT_SERVER_AGE_FMT, Fmt.Duration(400000), Fmt.Ago(time() - at)))
  Tokens.Acquire("test", 3)
  local text, dim = Tokens.Render("played_server")
  T.eq(text, format(L.PFX_SERVER_FMT, Fmt.Duration(400000)))
  T.ok(dim, "snapshot is dim")
  -- live after a sync
  LiveSync(ns)
  line = Find(Fill(ns, true), L.TT_SERVER)
  T.eq(line[2], Fmt.Duration(Tokens.ctx.playedServer))
  T.no(select(2, Tokens.Render("played_server")), "live")
end)

T.test("tooltip: the last-levels average (Shift); the overall one and the level history are in the window", function()
  local ns = Start()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  T.no(Find(Fill(ns, false), format(L.TT_AVG_RECENT_FMT, 5)), "not in the short view (the level)")
  local recent, n = Stats.RecentAvg(ns.char, 0, ns.C.RECENT_LEVELS)
  T.eq(n, 5)
  local overall = Fmt.Duration(Stats.AvgPerLevel(ns.char, 0, ns.Tracker.GetSync(), Stub.Now()))
  local detailed = Fill(ns, true)
  local line = Find(detailed, format(L.TT_AVG_RECENT_FMT, 5))
  T.ok(line, "Last 5 levels line")
  T.eq(line[2], Fmt.Duration(recent))
  for i = 1, #detailed do
    T.no(detailed[i][2] == overall and detailed[i][1] ~= format(L.TT_AVG_RECENT_FMT, 5),
      "no overall average line: " .. tostring(detailed[i][1]))
    T.no(string.find(tostring(detailed[i][1]), "^Level %d+$"), "no last levels row")
  end
  T.ok(HasText(detailed, L.TT_TOP_ZONES))
  T.ok(HasText(detailed, L.TT_TOP_CITIES))
  local city
  for i = 1, #detailed do
    if detailed[i][1] == L.TT_TOP_CITIES then city = detailed[i + 1] end
  end
  T.eq(city[1], "Orgrimmar")
  T.eq(city[2], format(L.TT_OF_WHICH_AFK_FMT, Fmt.Duration(2100), Fmt.Duration(600)))
  T.ok(Find(detailed, L.TT_NET), "network line")
end)

T.test("tooltip: no average line without level history (the window footer has the overall one)", function()
  local ns = Start({ noHistory = true })
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local overall = Stats.AvgPerLevel(ns.char, 0, ns.Tracker.GetSync(), Stub.Now())
  T.ok(overall, "an overall average exists")
  for _, detailed in ipairs({ false, true }) do
    local lines = Fill(ns, detailed)
    T.no(Find(lines, format(L.TT_AVG_RECENT_FMT, 5)))
    for i = 1, #lines do T.no(lines[i][2] == Fmt.Duration(overall), "no overall average: " .. tostring(lines[i][1])) end
  end
  ns.Window.Show("levels")
  local footer = rawget(_G, "TruePlayedStatsFrame").tp.footer1:GetText()
  T.ok(string.find(footer, Fmt.DurationFull(overall), 1, true), "the window footer has it: " .. footer)
end)

T.test("tooltip XP block and breakdowns over tracked time: the level, then (Shift) the character", function()
  local ns = Start()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local lines = Fill(ns, false)
  T.eq(lines[1][1], L.ADDON_TITLE)
  T.eq(lines[2][1], L.TT_SECTION_LEVEL, "the level section's title")
  T.no(Find(lines, L.TT_SECTION_CHAR), "no character section in the short view")
  T.no(Find(lines, L.TT_PLAYED), "no played line in the short view")
  T.no(Find(lines, L.TT_INSTANCES), "no instance line in the short view")
  local xp = Find(lines, L.TT_XP)
  T.eq(xp[2], format("%s / %s", Fmt.Number(3000), Fmt.Number(Stub.player.max)))
  T.eq(Find(lines, L.TT_REMAINING)[2], Fmt.Number(Stub.player.max - 3000))
  T.ok(Find(lines, L.TT_RESTED), "rested line")
  T.eq(Find(lines, L.TT_NEXT_LEVEL)[2], Fmt.ETA(ns.Tokens.ctx.eta))
  -- the short view: the breakdown of the level in progress only
  local lbd = Stats.Breakdown(ns.char.levels[ns.Tokens.ctx.level], {})
  local function Part(bd, key, secs) return format(L.BD_PART_FMT, L[key], Fmt.Percent(secs / bd.tracked, 0)) end
  T.eq(Find(lines, L.TT_BREAKDOWN_LEVEL)[2], table.concat({ Part(lbd, "BD_WORLD", lbd.world),
    Part(lbd, "BD_AFK", lbd.afk) }, L.SEP), "the level's breakdown: world and AFK only")
  T.no(Find(lines, L.TT_BREAKDOWN_TOTAL), "the short view: no total breakdown")
  T.ok(HasText(lines, L.TT_HINT), "hint")
  T.eq(lines[#lines][1], L.TT_HINT, "hint last")
  -- Shift: the level's breakdown, then the character's ("Total breakdown") under its
  -- section title
  local detailed = Fill(ns, true)
  local first, second, charTitle
  for i = 1, #detailed do
    if detailed[i][1] == L.TT_BREAKDOWN_LEVEL then first = first or i end
    if detailed[i][1] == L.TT_BREAKDOWN_TOTAL then second = second or i end
    if detailed[i][1] == L.TT_SECTION_CHAR then charTitle = i end
  end
  T.ok(first and second and charTitle, "two breakdowns and the character section")
  T.ok(first < charTitle and charTitle < second, "the character section between them")
  T.eq(detailed[first][2], Find(lines, L.TT_BREAKDOWN_LEVEL)[2], "the level's breakdown, as in the short view")
  T.ok(Find(detailed, L.TT_PLAYED), "played line (Shift)")
  local bd = Stats.Breakdown(ns.char.life, {})
  local flight = bd.active - bd.world - bd.dungeon - bd.raid - bd.pvp
  T.eq(detailed[second][2], table.concat({ Part(bd, "BD_WORLD", bd.world), Part(bd, "BD_AFK", bd.afk),
    Part(bd, "BD_CITY", bd.city), Part(bd, "BD_INN", bd.inn), Part(bd, "BD_TAXI", flight) }, L.SEP),
    "largest first: world, AFK, city, inn, flight (no instance time: those parts are left out)")
  T.eq(detailed[#detailed][1], L.TT_HINT, "hint last (Shift)")
end)

-- Under "This level" (filtered, to the minute), the level's /played without any filter
-- while something is excluded: the detail sheet's Server card (Stats.LevelServer), "~"
-- when a server mark of the level was estimated; nothing without a server value.
T.test("tooltip: This level (server /played) under This level, only while something is excluded", function()
  local ns = Start()
  local L, Fmt, Stats, Tokens = ns.L, ns.Fmt, ns.Stats, ns.Tokens
  local char = ns.char
  local function Index(lines, left)
    for i = 1, #lines do
      if lines[i][1] == left then return i end
    end
  end
  -- no sync yet: no server value, no line (an exclusion or not)
  ns.Core.SetSetting("exclude.afk", true)
  T.no(Find(Fill(ns, false), L.TT_THIS_LEVEL_SERVER), "no sync: no server line")
  ns.Core.SetSetting("exclude.afk", false)
  -- a level part over 10 h, as tracked (no gap to rebuild; the level begun long enough
  -- ago for it): both lines to the minute
  local lb = char.levels[char.level]
  lb.t0, lb.s.w = time() - 86400, 40000
  Stub.Fire("TIME_PLAYED_MSG", math.floor(Stats.SumAll(char.life)), math.floor(Stats.SumAll(lb)))
  Stub.Advance(0)
  local lines = Fill(ns, false)
  T.no(Find(lines, L.TT_THIS_LEVEL_SERVER), "nothing excluded: no server line (This level is it)")
  T.eq(Find(lines, L.TT_THIS_LEVEL)[2], Fmt.DurationFull(Tokens.ctx.levelTime))
  ns.Core.SetSetting("exclude.afk", true)
  for _, detailed in ipairs({ false, true }) do
    lines = Fill(ns, detailed)
    local ctx = Tokens.ctx
    local srv, est = Stats.LevelServer(char, ctx.level, ns.Tracker.GetSync(), ctx.now)
    T.ok(srv ~= nil and srv >= 36000 and not est, "the fixture: a live level part over 10 h")
    local i = Index(lines, L.TT_THIS_LEVEL)
    T.eq(lines[i][2], Fmt.DurationFull(ctx.levelTime), "This level: filtered, to the minute")
    T.eq(lines[i + 1], { L.TT_THIS_LEVEL_SERVER, Fmt.DurationFull(srv) }, "right under it: the server's, unfiltered")
    T.ok(lines[i + 1][2]:find("^%d+h %d%dm$") ~= nil, "with its minutes: " .. lines[i + 1][2])
    T.ok(srv - ctx.levelTime >= 60, "the AFK time left out of This level only")
    local n = 0
    for j = 1, #lines do
      if lines[j][1] == L.TT_THIS_LEVEL_SERVER then n = n + 1 end
    end
    T.eq(n, 1, "once (Shift: the level's section only)")
  end
  -- an estimated server mark: "~"
  lb.srvStartEst = true
  lines = Fill(ns, false)
  local srv = Stats.LevelServer(char, Tokens.ctx.level, ns.Tracker.GetSync(), Tokens.ctx.now)
  T.eq(Find(lines, L.TT_THIS_LEVEL_SERVER)[2], Tokens.Approx(Fmt.DurationFull(srv)), "estimated: '~'")
  lb.srvStartEst = nil
  -- under a crash note: the note stays with This level, the server line after it
  lb.est, lb.es = 600, { w = 600 }
  lines = Fill(ns, false)
  local i = Index(lines, L.TT_THIS_LEVEL)
  T.ok(MatchesFormat(lines[i + 1][1], L.TT_EST_FMT), "the rebuilt note right under This level")
  T.eq(lines[i + 2][1], L.TT_THIS_LEVEL_SERVER, "then the server line")
end)

-- Right above the level's breakdown, the level's XP by source (as the detail sheet's
-- Experience bar): monsters, quests and other, rested bonus, those of 1 % or more, in that
-- order, two a line; on a plain GameTooltip (Broker) the label and the first two on one
-- line, the third on a continuation line. Nothing without XP by source, nothing at the
-- max level.
T.test("tooltip: the level's XP by source right above its breakdown; none without XP or at max level", function()
  local ns = Start()
  local L, Fmt = ns.L, ns.Fmt
  local function Part(key, x) return format(L.BD_PART_FMT, L[key], Fmt.Percent(x, 0)) end
  local function Index(lines, left)
    for i = 1, #lines do
      if lines[i][1] == left then return i end
    end
  end
  for _, detailed in ipairs({ false, true }) do
    local lines = Fill(ns, detailed)
    local i = Index(lines, L.TT_XP_LEVEL)
    T.ok(i ~= nil, "the XP row")
    T.eq(lines[i][2], Part("LD_XP_MOBS", 0.8) .. L.SEP .. Part("LD_XP_QUESTS", 0.1),
      "monsters, quests and other, in that order, two a line")
    T.eq(lines[i + 1], { " ", Part("LD_XP_RESTED", 0.1) }, "then the rested bonus on a continuation line")
    T.eq(lines[i + 2][1], L.TT_BREAKDOWN_LEVEL, "right above the level's breakdown")
    local n = 0
    for j = 1, #lines do
      if lines[j][1] == L.TT_XP_LEVEL then n = n + 1 end
    end
    T.eq(n, 1, "once (Shift: the level's section only)")
  end
  -- a source under 0.5 %: left out; the order kept (rested before monsters' would be by size)
  local lb = ns.char.levels[ns.char.level]
  lb.xa, lb.xq, lb.xr = 1000, 4, 3000
  local lines = Fill(ns, false)
  local i = Index(lines, L.TT_XP_LEVEL)
  T.eq(lines[i][2], Part("LD_XP_MOBS", 1000 / 4004) .. L.SEP .. Part("LD_XP_RESTED", 3000 / 4004),
    "the fixed order, the 0 % quest part left out: one line")
  T.eq(lines[i + 1][1], L.TT_BREAKDOWN_LEVEL)
  -- no XP by source: no row (the breakdown stays)
  lb.xa, lb.xq, lb.xr = 0, 0, 0
  lines = Fill(ns, false)
  T.no(Find(lines, L.TT_XP_LEVEL), "all three at 0: no row")
  T.ok(Find(lines, L.TT_BREAKDOWN_LEVEL), "the breakdown stays")
  lb.xa, lb.xq, lb.xr = nil, nil, nil
  T.no(Find(Fill(ns, false), L.TT_XP_LEVEL), "no fields: no row")
  -- the max level: no row
  Stub.Reset()
  ns = Start({ level = 60 })
  T.ok(ns.Tokens.ctx.isMax, "the fixture: max level")
  local xp = ns.char.levels[60]
  T.ok((xp.xa or 0) + (xp.xq or 0) + (xp.xr or 0) > 0, "the fixture: XP by source at that level")
  for _, detailed in ipairs({ false, true }) do
    T.no(Find(Fill(ns, detailed), ns.L.TT_XP_LEVEL), "max level: no XP row")
  end
end)

T.test("tooltip zone line: the time at this level on hover, the character's in its Shift section", function()
  local ns = Start()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local ctx, char = ns.Tokens.ctx, ns.char
  local label = format(L.TT_ZONE_FMT, "Durotar")
  local atLevel = Stats.Sum(char.levels[Stub.player.level].z[1411], 0)
  local whole = Stats.Sum(char.zones[1411], 0)
  T.ok(atLevel > 0 and whole > atLevel * 10, "the fixture: much more time in the zone before this level")
  local short = Fill(ns, false)
  T.eq(Find(short, label)[2], Fmt.Duration(atLevel), "short view: the zone's time at this level")
  local n, values = 0, {}
  local charTitle
  local detailed = Fill(ns, true)
  for i = 1, #detailed do
    if detailed[i][1] == L.TT_SECTION_CHAR then charTitle = i end
    if detailed[i][1] == label then
      n = n + 1
      values[n] = { i, detailed[i][2] }
    end
  end
  T.eq(n, 2, "Shift: the level's zone line and the character's")
  T.ok(values[1][1] < charTitle and charTitle < values[2][1], "one in each section")
  T.eq(values[1][2], Fmt.Duration(atLevel))
  T.eq(values[2][2], Fmt.Duration(ctx.zoneTime))
  T.eq(ctx.zoneTime, whole, "the bar's zone_time stays the character's")
end)

-- "This level" takes the server's level time once synced; the zone's time at this level is
-- tracked time: a server a little behind (a drift under C.DRIFT_TOL is kept) must not show
-- more time in the zone than in the whole level.
T.test("tooltip zone line: never above This level (a live server level time a little behind)", function()
  local ns = Start()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local char = ns.char
  local label = format(L.TT_ZONE_FMT, "Durotar")
  local lb = char.levels[char.level]
  local tracked = Stats.SumAll(lb)
  T.eq(Stats.Sum(lb.z[1411], 0), tracked, "the fixture: the whole level in this zone")
  Stub.Fire("TIME_PLAYED_MSG", math.floor(Stats.SumAll(char.life)), math.floor(tracked) - 90)
  Stub.Advance(0)
  local short = Fill(ns, false)
  local ctx = ns.Tokens.ctx
  T.ok(ctx.levelTime < Stats.Sum(lb.z[1411], 0) - 60, "the fixture: This level well below the zone's tracked time")
  T.eq(Find(short, L.TT_THIS_LEVEL)[2], Fmt.DurationFull(ctx.levelTime))
  T.eq(Find(short, label)[2], Fmt.Duration(ctx.levelTime), "the zone line capped to This level")
  -- Shift: the same in block 1's section; the character's zone line is not capped by it
  local detailed = Fill(ns, true)
  T.eq(Find(detailed, label)[2], Fmt.Duration(ctx.levelTime))
end)

T.test("ShowFor refreshes while shown and detaches on hide or owner change", function()
  local ns = Start()
  local Tooltip = ns.Tooltip
  local owner = CreateFrame("Frame", nil, UIParent)
  owner:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  Tooltip.ShowFor(owner)
  T.ok(GameTooltip:IsShown())
  T.ok(Tooltip.IsShownFor(owner))
  local short = GameTooltip:NumLines()
  T.ok(short > 5)
  Stub.SetShift(true)                                -- MODIFIER_STATE_CHANGED: detailed
  local tt2 = rawget(_G, "TruePlayedCharTooltip")
  T.ok(tt2 and tt2:IsShown() and tt2:GetOwner() == owner, "detailed view: block 2 under the tooltip")
  T.ok(tt2:NumLines() > 5, "block 2: the character")
  Stub.SetShift(false)
  T.no(tt2:IsShown(), "block 2 hidden when Shift is released")
  Stub.Advance(1)                                    -- TICK refresh
  T.eq(GameTooltip:NumLines(), short)
  Tooltip.Hide(owner)
  T.no(GameTooltip:IsShown())
  T.no(Tooltip.IsShownFor(owner))
  GameTooltip:ClearLines()
  Stub.Advance(3)
  T.eq(GameTooltip:NumLines(), 0, "no refresh after hide")
  -- another owner takes the tooltip: we stop at the next tick and never hide it (block 2,
  -- ours, is hidden then)
  Tooltip.ShowFor(owner)
  Stub.SetShift(true)
  T.ok(tt2:IsShown())
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:ClearLines()
  GameTooltip:AddLine("someone else")
  GameTooltip:Show()
  Stub.Advance(2)
  Stub.SetShift(false)
  T.eq(GameTooltip:NumLines(), 1)
  T.no(Tooltip.IsShownFor(owner))
  T.no(tt2:IsShown(), "block 2 hidden with the detach")
  Tooltip.Hide(owner)
  T.ok(GameTooltip:IsShown(), "foreign tooltip left alone")
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Round 3: mobs to kill, instance time, plain FPS / latency, graph sampling
---------------------------------------------------------------------------

-- Replaces Stats.KillsToLevel on this test's ns (fresh per test) by a fixed answer:
-- the token formatting is tested apart from the engine's rest model.
local function FixedKills(ns, n, base)
  ns.Stats.KillsToLevel = function() return n, base end
end

T.test("kills and eta_kills: '~38 mobs', '~ETA · 38 mobs' and its short form (en, fr)", function()
  for _, locale in ipairs({ "enUS", "frFR" }) do
    Stub.Reset()
    local ns = Start({ locale = locale })
    local Tokens, Fmt, L = ns.Tokens, ns.Fmt, ns.L
    FixedKills(ns, 38, 120)
    Tokens.Acquire("test", 3)
    local ctx = Tokens.ctx
    T.eq(ctx.kills, 38, locale)
    T.eq(ctx.killXP, 120)
    local text, dim, paused, alt = Tokens.Render("kills")
    T.eq(text, "~" .. format(L.KILLS_FMT, "38"), locale)
    T.no(dim)
    T.no(paused)
    T.eq(alt, nil)
    local eta = Fmt.ETA(ctx.eta)
    text, dim, paused, alt = Tokens.Render("eta_kills")
    T.eq(text, eta .. L.SEP .. format(L.KILLS_FMT, "38"), locale)
    T.no(paused)
    T.eq(alt, eta, "short form = the ETA alone")
    T.no(dim)
    T.eq(text:sub(1, 1), "~")
    T.ok(not text:find("~", 2, true), "a single leading ~")
    if locale == "frFR" then
      T.eq((Tokens.Render("kills")), "~38 monstres")
    else
      T.eq((Tokens.Render("kills")), "~38 mobs")
    end
    -- cached strings while nothing changes
    T.ok(rawequal((Tokens.Render("eta_kills")), (Tokens.Render("eta_kills"))))
    T.ok(rawequal((Tokens.Render("kills")), (Tokens.Render("kills"))))
    -- big counts use the thousands separator
    FixedKills(ns, 1234.2, 5)
    Tokens.UpdateContext(Stub.Now())
    T.eq(ctx.kills, 1235, "rounded up: 1234.2 kills need 1235")
    T.eq((Tokens.Render("kills")), "~" .. format(L.KILLS_FMT, Fmt.Number(1235)))
    -- the last mob: singular
    FixedKills(ns, 1, 120)
    Tokens.UpdateContext(Stub.Now())
    T.eq((Tokens.Render("kills")), (locale == "frFR") and "~1 monstre" or "~1 mob", locale)
  end
end)

T.test("eta_kills falls back to either part; kills is dim dots without a kill, max level text", function()
  local ns = Start()
  local Tokens, Fmt, L = ns.Tokens, ns.Fmt, ns.L
  FixedKills(ns, nil, nil)
  Tokens.Acquire("test", 3)
  local ctx = Tokens.ctx
  T.eq(ctx.kills, nil)
  local text, dim = Tokens.Render("kills")
  T.eq(text, L.DOTS)
  T.ok(dim, "no kill yet: dim")
  local alt
  text, dim, _, alt = Tokens.Render("eta_kills")
  T.eq(text, Fmt.ETA(ctx.eta), "no kill: the ETA alone")
  T.eq(alt, nil)
  T.no(dim)
  -- a kill known but no rate yet: the count alone, not dimmed
  FixedKills(ns, 12, 300)
  ns.char.prior = nil
  ns.char.ema = Ema(0, 0, 0, 0)
  ns.char.levels = { [ns.char.level] = { s = { w = 10 }, xp = 0, xa = 0, xr = 0, xq = 0, d = 0, z = {} } }
  Tokens.UpdateContext(Stub.Now())
  T.eq(ctx.eta, nil)
  text, dim, _, alt = Tokens.Render("eta_kills")
  T.eq(text, "~" .. format(L.KILLS_FMT, "12"))
  T.no(dim)
  T.eq(alt, nil)
  -- not a pausable count; eta_kills pauses like the ETA
  T.no(Tokens.DEF.kills.pausable)
  T.ok(Tokens.DEF.eta_kills.pausable)
  T.ok(Tokens.DEF.kills.xp and Tokens.DEF.eta_kills.xp, "XP tokens: replaced at max level")
end)

T.test("kills at max level: max level text, no count", function()
  local ns = Start({ level = 60, lastKill = { xp = 500, level = 60, at = 1789990000 } })
  local Tokens, L = ns.Tokens, ns.L
  Tokens.Acquire("test", 3)
  T.eq(Tokens.ctx.kills, nil)
  T.eq((Tokens.Render("kills")), L.MAX_LEVEL)
  T.eq((Tokens.Render("eta_kills")), L.MAX_LEVEL)
  T.eq(Tokens.Resolve(1), "session", "eta_kills replaced by the max-level slot")
end)

T.test("kills with the engine: count from the last kill, rest-aware, updated by a new kill", function()
  local ns = Start({ lastKill = { xp = 100, level = 10, at = 1789990000 } })
  local Tokens, Stats = ns.Tokens, ns.Stats
  Tokens.Acquire("test", 3)
  local ctx = Tokens.ctx
  local n = Stats.KillsToLevel(ns.char, ctx.xp, ctx.max, ctx.rested)
  T.ok(type(n) == "number" and n > 0, "engine count")
  T.eq(ctx.kills, n)
  -- rested kills give double XP: fewer mobs than without rest
  local plain = math.ceil((ctx.max - ctx.xp) / 100)
  T.ok(ctx.rested > 0, "rested at login (Start: 1000 rested XP)")
  T.ok(ctx.kills < plain, "rest-aware")
  Stub.Kill(200)                           -- a bigger mob: fewer of them to go
  Stub.Advance(2)
  T.eq(ns.char.lastKill and ns.char.lastKill.xp, 200, "lastKill from the kill")
  T.eq(ctx.kills, Stats.KillsToLevel(ns.char, ctx.xp, ctx.max, ctx.rested))
  T.ok(ctx.kills < n)
end)

T.test("instance tokens: session and total instance time with the exclusions", function()
  local ns = Start()
  local Tokens, Stats, Fmt, L = ns.Tokens, ns.Stats, ns.Fmt, ns.L
  local s = ns.char.life.s
  s.d, s.D, s.r, s.R, s.p, s.P = 3600, 600, 1800, 120, 900, 60
  Tokens.Acquire("test", 3)
  local total = 3600 + 600 + 1800 + 120 + 900 + 60
  T.eq(Tokens.ctx.instTotal, total)
  T.eq((Tokens.Render("instance_total")), format(L.PFX_INST_TOTAL_FMT, Fmt.Duration(total)))
  T.eq(Tokens.ctx.instSession, 0, "no instance this session")
  T.eq((Tokens.Render("instance_session")), format(L.PFX_INST_SESSION_FMT, Fmt.Duration(0)))
  -- AFK excluded: D, R, P left out
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(Tokens.ctx.instTotal, 3600 + 1800 + 900)
  T.eq(Tokens.ctx.instTotal, Stats.InstanceTime(ns.char.life, 1))
  -- time in a dungeon counts for the session
  Stub.SetInstance(true, "party", 389, 90001)
  Stub.Advance(120)
  T.ok(Tokens.ctx.instSession >= 110, "session instance time: " .. tostring(Tokens.ctx.instSession))
  local text, dim, paused = Tokens.Render("instance_session")
  T.eq(text, format(L.PFX_INST_SESSION_FMT, Fmt.Duration(Tokens.ctx.instSession)))
  T.no(dim)
  T.no(paused)
  T.ok(Tokens.DEF.instance_session.pausable and not Tokens.DEF.instance_session.xp)
end)

T.test("Plain strips the colour codes of FPS / latency texts, memoized", function()
  local ns = Start()
  local Tokens, Fmt = ns.Tokens, ns.Fmt
  local coloured = Fmt.FPSLatency(60, 42)
  T.ok(coloured:find("|c", 1, true) ~= nil, "coloured numbers")
  local plain = Tokens.Plain(coloured)
  T.eq(plain, "60 fps" .. ns.L.SEP .. "42 ms")
  T.ok(rawequal(Tokens.Plain(coloured), plain), "memoized")
  T.eq(Tokens.Plain("~1h 25m"), "~1h 25m")
  T.eq(Tokens.Plain(nil), nil)
  T.ok(Tokens.IsNetToken("fps") and Tokens.IsNetToken("latency") and Tokens.IsNetToken("fps_latency"))
  T.no(Tokens.IsNetToken("eta"))
  T.no(Tokens.IsNetToken("bogus"))
end)

T.test("graph: a visible FPS or latency token samples both series into Graph.Sample", function()
  local fpsCalls, netCalls = 0, 0
  local origFps, origNet = GetFramerate, GetNetStats
  GetFramerate = function() fpsCalls = fpsCalls + 1; return origFps() end   -- before LoadAddon
  GetNetStats = function() netCalls = netCalls + 1; return origNet() end
  local ns = Start()
  local Tokens, Graph = ns.Tokens, ns.Graph
  T.ok(Graph ~= nil and Graph.Sample ~= nil, "Graph.lua loaded (TOC)")
  T.eq(select(1, Graph.SampleCount()), 0)
  Tokens.Acquire("test", 2)                       -- eta_kills + xph: no sampling
  Stub.Advance(10)
  T.eq(select(1, Graph.SampleCount()), 0, "no FPS token: nothing kept")
  ns.settings.widget.slots[2] = "fps"             -- FPS only: latency is sampled too
  ns.SendMessage("SETTINGS_CHANGED", "widget.slots.2", "fps")
  fpsCalls, netCalls = 0, 0
  Stub.Advance(20)
  local nf, nl = Graph.SampleCount()
  T.ok(nf >= 19 and nf <= 21, format("one FPS sample per tick (%d)", nf))
  T.ok(nl >= 4 and nl <= 5, format("latency kept when re-read, every 5 s (%d)", nl))
  T.ok(netCalls >= 4 and netCalls <= 5, format("GetNetStats every 5 s (%d)", netCalls))
  -- data messages refresh the context between ticks: still one FPS sample per tick
  for _ = 1, 5 do ns.SendMessage("STATE_CHANGED", "w", "w") end
  T.eq(select(1, Graph.SampleCount()), nf, "no extra sample between ticks")
  Tokens.Release("test")
  Stub.Advance(10)
  T.eq(select(1, Graph.SampleCount()), nf, "released: no more samples")
  GetFramerate, GetNetStats = origFps, origNet
end)

---------------------------------------------------------------------------
-- Allocation budgets (6.7)
---------------------------------------------------------------------------

-- Same measure as T.alloc (GC stopped, collectgarbage("count") difference), with one
-- unmeasured call right after the full collect. The collect also shrinks the Lua stack
-- and CallInfo list; without the warm call, re-growing them on the first deep tick
-- (Tick -> SafeCall -> Tokens -> Stats) is counted: a constant 0.4-1.7 KB that is not
-- garbage and does not depend on the number of ticks.
-- The warm call may take a shallower path than some ticks: the stack is also grown first,
-- as T.alloc does (how large earlier tests left it decides whether the collect shrinks it
-- below the deepest tick).
local function WarmStack(depth)
  if depth <= 0 then return 0 end
  local a, b, c, d, e, f, g, h = depth, depth, depth, depth, depth, depth, depth, depth
  return WarmStack(depth - 1) + a + b + c + d + e + f + g + h
end

local function Alloc(fn, n)
  collectgarbage("collect")
  WarmStack(200)
  fn(0)
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, n do fn(i) end
  local after = collectgarbage("count")
  collectgarbage("restart")
  return after - before
end

T.test("allocation: nothing at all in a steady state (AFK excluded, default slots)", function()
  local ns = Start()
  local Tokens = ns.Tokens
  ns.Core.SetSetting("exclude.afk", true)
  Stub.SetAFK(true)                          -- excluded time: the rate clock does not move
  Tokens.Acquire("test", 3)
  local function Step()
    Stub.Advance(1)
    for i = 1, 3 do Tokens.Render(Tokens.Resolve(i)) end
  end
  for _ = 1, 300 do Step() end
  local kb = Alloc(Step, 600)
  T.ok(kb < 0.1, format("allocated %.3f KB", kb))
end)

T.test("allocation: nothing at all in a steady state with a full kill ring (kills tokens shown)", function()
  local ns = Start({ lastKill = { xp = 330, level = 10, at = 1789990000 },
                     killRing = { 300, 310, 290, 305, 315, 320, 280, 300, 312, 330 } })
  local Tokens = ns.Tokens
  ns.Core.SetSetting("widget.slots.1", "kills")
  ns.Core.SetSetting("widget.slots.2", "eta_kills")
  ns.Core.SetSetting("exclude.afk", true)
  Stub.SetAFK(true)                          -- excluded time: the rate clock does not move
  Tokens.Acquire("test", 3)
  T.eq({ Tokens.Resolve(1), Tokens.Resolve(2) }, { "kills", "eta_kills" })
  T.eq(Tokens.ctx.killXP, 306, "the rounded average of the ring")
  T.ok(type(Tokens.ctx.kills) == "number" and Tokens.ctx.kills > 0)
  T.eq(Tokens.ctx.kills, ns.Stats.KillsToLevel(ns.char, Tokens.ctx.xp, Tokens.ctx.max, Tokens.ctx.rested))
  local function Step()
    Stub.Advance(1)
    for i = 1, 3 do Tokens.Render(Tokens.Resolve(i)) end
  end
  for _ = 1, 300 do Step() end
  local kb = Alloc(Step, 600)
  T.ok(kb < 0.1, format("allocated %.3f KB", kb))
end)

T.test("allocation: FPS changing every second (within the memo) allocates nothing", function()
  local ns = Start()
  local Tokens = ns.Tokens
  ns.Core.SetSetting("exclude.afk", true)
  Stub.SetAFK(true)                          -- only the FPS / latency slot changes
  Tokens.Acquire("test", 3)
  T.eq(Tokens.Resolve(3), "fps_latency", "default slot 3")
  local t = 0
  local function Step()
    t = t + 1
    Stub.fps = 57 + t % 7                    -- 57..63 fps: a new value every second
    local lat = 38 + (math.floor(t / 30) % 5) * 4
    Stub.net.home, Stub.net.world = lat, lat -- latency drifts every 30 s
    Stub.Advance(1)
    for i = 1, 3 do Tokens.Render(Tokens.Resolve(i)) end
  end
  for _ = 1, 300 do Step() end              -- warm-up: the 35 (fps, ms) pairs are memoized
  local before = Tokens.Render("fps_latency")
  Step()
  T.ok(Tokens.Render("fps_latency") ~= before, "the FPS text really changes every second")
  local kb = Alloc(Step, 600)
  T.ok(kb < 0.1, format("allocated %.3f KB", kb))
end)

T.test("allocation: 600 ticks with the default slots <= 1 KB", function()
  local ns = Start()
  local Tokens = ns.Tokens
  Tokens.Acquire("test", 3)
  local function Step()
    Stub.Advance(1)
    for i = 1, 3 do Tokens.Render(Tokens.Resolve(i)) end
  end
  for _ = 1, 300 do Step() end
  local kb = Alloc(Step, 600)                -- only ETA / XP-per-hour text changes
  T.ok(kb <= 1, format("allocated %.3f KB", kb))
end)

-- 8 KB for the 20 tokens of before; the reputation's two add about 3 KB here: without a
-- gain its rate decays, and below 1,000 per hour its whole number changes every ~15 ticks
-- (a text formatted only when the shown value changes, as the XP per hour's).
T.test("allocation: 600 ticks rendering all 22 tokens <= 12 KB", function()
  local ns = Start({ lastKill = { xp = 120, level = 10, at = 1789990000 }, rep = RepData() })
  LiveSync(ns)
  ns.char.life.s.d, ns.char.life.s.r = 1800, 600   -- instance time
  local Tokens = ns.Tokens
  local ORDER = Tokens.ORDER
  Tokens.Acquire("test", 3)
  local function Step()
    Stub.Advance(1)
    for i = 1, #ORDER do Tokens.Render(ORDER[i]) end
  end
  for _ = 1, 300 do Step() end
  local kb = Alloc(Step, 600)                -- per-minute time texts, the two rates
  T.ok(kb <= 12, format("allocated %.3f KB", kb))
end)

---------------------------------------------------------------------------
-- Round 4: frozen rate (C1, no XP for a while) and server level cap (C2)
-- The first tests replace Stats.Rate / Tracker.GetStall / Tracker.IsMax /
-- Tracker.GetCapInfo by the values of the contract, so they run whatever the state of
-- the engine; the last ones use the engine itself and are skipped until it has them.
---------------------------------------------------------------------------

local STALL_SECS = 3 * 3600 + 300            -- 3 h 05 of counted play without XP

-- Stats.Rate as the engine returns it while stalled: the value frozen at the first
-- call (the EMA neither decays nor grows), status "stalled", stallSecs as an extra
-- return (src "prior" for a frozen estimate).
local function StallRate(ns, src)
  local Stats, Tracker = ns.Stats, ns.Tracker
  local rate = Stats.Rate
  local frozen = {}
  Stats.Rate = function(char, mask)
    local f = frozen[mask or 0]
    if not f then
      f = { rate(char, mask) }
      frozen[mask or 0] = f
    end
    return f[1], f[2], f[3], f[4], src or f[5], "stalled", 0, STALL_SECS
  end
  Tracker.GetStall = function() return true, STALL_SECS end
  return function() Stats.Rate = rate end
end

-- Tracker.IsMax / GetCapInfo as the engine answers at a detected server level cap.
local function ServerCap(ns, misses)
  local Tracker = ns.Tracker
  local level = ns.char.level
  Tracker.IsMax = function() return true end
  Tracker.GetCapInfo = function() return level, true, misses end
end

local function Colors(tt, i)
  return tt._colors[i] or {}
end

local function Near3(a, r, g, b)
  return a ~= nil and math.abs(a[1] - r) < 1e-6 and math.abs(a[2] - g) < 1e-6 and math.abs(a[3] - b) < 1e-6
end

T.test("stalled: xph, eta, pcth and eta_kills show the frozen value dimmed with the mark", function()
  local ns = Start({ ema = Ema(8200, 0, 0, 3600), lastKill = { xp = 120, level = 10, at = 1789990000 } })
  local Tokens, Fmt, L = ns.Tokens, ns.Fmt, ns.L
  local restore = StallRate(ns)
  Tokens.Acquire("test", 3)
  local ctx = Tokens.ctx
  T.eq(ctx.rateStatus, "stalled")
  T.eq(ctx.etaStatus, "stalled", "passed through to the ETA")
  T.ok(ctx.stalled)
  T.eq(ctx.stallSecs, STALL_SECS)
  T.eq(L.STALL_MARK, "*")
  local text, dim = Tokens.Render("xph")
  T.eq(text, "8.2k/h*", "frozen rate with its mark")
  T.ok(dim, "dimmed")
  text, dim = Tokens.Render("eta")
  T.eq(text, Fmt.ETA(ctx.eta) .. "*")
  T.ok(dim)
  text, dim = Tokens.Render("pcth")
  T.eq(text:sub(-1), "*")
  T.ok(dim)
  local alt
  text, dim, _, alt = Tokens.Render("eta_kills")
  T.eq(alt, Fmt.ETA(ctx.eta) .. "*", "short form: the frozen ETA")
  T.eq(text:sub(1, #alt), alt)
  T.ok(text:find(format(L.KILLS_FMT, Fmt.Number(ctx.kills)), 1, true) ~= nil, "mobs still counted")
  T.ok(dim)
  -- a frozen pre-install estimate keeps its "~"
  restore()
  restore = StallRate(ns, "prior")
  Tokens.UpdateContext(Stub.Now())
  T.eq((Tokens.Render("xph")), "~8.2k/h*")
  T.eq((Tokens.Render("eta")):sub(1, 1), "~")
  T.eq((Tokens.Render("eta")):sub(-1), "*")
  -- XP again: the live value, no mark, not dimmed (cache keyed by the display mode)
  restore()
  Tokens.UpdateContext(Stub.Now())
  T.eq(Tokens.ctx.rateStatus, "ok")
  T.no(Tokens.ctx.stalled)
  text, dim = Tokens.Render("xph")
  T.eq(text, "8.2k/h")
  T.no(dim)
  T.no((Tokens.Render("eta")):find("*", 1, true), "no mark")
end)

T.test("stalled: the tooltip says since when no XP came, and /tpl played too (frFR)", function()
  local ns = Start({ locale = "frFR", ema = Ema(8200, 0, 0, 3600) })
  local Tokens, Fmt, L, C = ns.Tokens, ns.Fmt, ns.L, ns.C
  StallRate(ns)
  Tokens.Acquire("test", 3)
  local lines = Fill(ns, false)
  local tt = GameTooltip
  local rate, iRate
  for i = 1, #lines do
    if lines[i][1] == L.TT_XPH then rate, iRate = lines[i], i end
  end
  T.eq(rate[2], "8,2k/h*")
  local dim = C.COLORS.dim
  local col = Colors(tt, iRate)
  T.ok(Near3({ col[4], col[5], col[6] }, dim[1], dim[2], dim[3]), "value dimmed")
  local note = "* XP/h fig\195\169e : aucun gain d'XP depuis 3 h 05 de jeu"
  T.eq(format(L.TT_STALLED_FMT, L.STALL_MARK, Fmt.Duration(STALL_SECS)), note)
  T.eq(lines[iRate + 1][1], note, "right under the XP per hour")
  T.eq(lines[iRate + 2][1], L.TT_STALLED_RESUME)
  T.ok(tt._lines[iRate + 1] ~= nil)
  local eta = Find(lines, L.TT_NEXT_LEVEL)
  T.eq(eta[2], Fmt.ETA(Tokens.ctx.eta) .. "*")
  -- /tpl played: the marked values, then the same explanation
  local from = #Stub.printed + 1
  Stub.RunSlash("played")
  local found, foundNote = false, false
  for i = from, #Stub.printed do
    if Stub.printed[i]:find("8,2k/h*", 1, true) then found = true end
    if Stub.printed[i]:find(note, 1, true) then foundNote = true end
  end
  T.ok(found, "summary with the frozen rate")
  T.ok(foundNote, "summary explains it")
end)

T.test("server level cap: XP tokens give way to the max-level infos, tooltip explains (frFR)", function()
  local ns = Start({ locale = "frFR" })
  local Tokens, L, C = ns.Tokens, ns.L, ns.C
  Tokens.Acquire("test", 3)
  T.no(Tokens.ctx.isServerCap)
  ServerCap(ns, 0)
  Tokens.UpdateContext(Stub.Now())
  local ctx = Tokens.ctx
  T.ok(ctx.isMax and ctx.isServerCap)
  T.eq(ctx.capLevel, 10)
  T.eq(Tokens.Resolve(1), "session", "max-level slot 1")
  T.eq(Tokens.Resolve(2), "played")
  local text, dim = Tokens.Render("xph")
  T.eq(text, L.CAP_SHORT)
  T.eq(text, "Plafond serveur")
  T.ok(dim)
  T.eq((Tokens.Render("eta")), L.CAP_SHORT)
  T.eq((Tokens.Render("kills")), L.CAP_SHORT)
  -- tooltip: the cap line (orange, at least the detection threshold after a /reload),
  -- the XP where it stopped, and how it ends
  local lines = Fill(ns, false)
  local capLine = "Niveau 10 : plafond actuel du serveur (aucune XP sur les 3 derniers monstres)"
  local iCap
  for i = 1, #lines do if lines[i][1] == capLine then iCap = i end end
  T.ok(iCap ~= nil, "cap line")
  local pc = C.COLORS.pause
  T.ok(Near3(Colors(GameTooltip, iCap), pc[1], pc[2], pc[3]), "orange like the pause line")
  T.eq(lines[iCap + 1], { L.TT_XP, "3\194\160000 / 7\194\160600" })
  T.eq(lines[iCap + 2][1], L.TT_CAP_RESUME)
  T.eq(L.TT_CAP_RESUME, "Le suivi de l'XP reprend tout seul d\195\168s que le serveur redonne de l'XP.")
  T.no(HasText(lines, L.TT_MAX_LEVEL), "not the max level")
  T.no(Find(lines, L.TT_NEXT_LEVEL))
  T.no(Find(lines, L.TT_KILLS))
  -- more misses than the threshold: the real count
  ServerCap(ns, 5)
  lines = Fill(ns, false)
  T.ok(HasText(lines, format(L.TT_CAP_FMT, 10, 5)))
  -- /tpl played
  local from = #Stub.printed + 1
  Stub.RunSlash("played")
  local found = false
  for i = from, #Stub.printed do
    if Stub.printed[i]:find(format(L.SUM_CAP_FMT, 10), 1, true) then found = true end
  end
  T.ok(found, "summary names the cap")
  -- the real max level stays the max level
  ns.Tracker.GetCapInfo = function() return nil, false, 0 end
  Tokens.UpdateContext(Stub.Now())
  T.no(Tokens.ctx.isServerCap)
  T.eq((Tokens.Render("xph")), L.MAX_LEVEL)
  T.ok(HasText(Fill(ns, false), L.TT_MAX_LEVEL))
end)

T.test("allocation: a frozen rate and a server cap allocate nothing on steady ticks", function()
  local ns = Start({ ema = Ema(8200, 0, 0, 3600) })
  local Tokens = ns.Tokens
  StallRate(ns)
  ns.Core.SetSetting("widget.slots.1", "eta")
  ns.Core.SetSetting("widget.slots.3", "pcth")
  Tokens.Acquire("test", 3)
  local function Step()
    Stub.Advance(1)
    for i = 1, 3 do Tokens.Render(Tokens.Resolve(i)) end
  end
  for _ = 1, 30 do Step() end
  local kb = Alloc(Step, 600)
  T.ok(kb < 0.5, format("stalled: allocated %.3f KB", kb))
  ServerCap(ns, 3)
  for _ = 1, 30 do Step() end
  kb = Alloc(Step, 600)
  T.ok(kb < 1, format("server cap: allocated %.3f KB", kb))
end)

T.test("engine C1: a persisted stall freezes the rate until the next XP gain", function()
  local ns = Start({ locale = "frFR", ema = Ema(8200, 0, 0, 3600), noXP = 1200 + 3 * 3600 })
  T.eq(ns.C.XP_STALL, 1200)
  local Tokens, Fmt, L = ns.Tokens, ns.Fmt, ns.L
  Tokens.Acquire("test", 3)
  local stalled, secs = ns.Tracker.GetStall()
  T.ok(stalled, "stalled at login")
  T.eq(Tokens.ctx.rateStatus, "stalled")
  T.eq((Tokens.Render("xph")), Fmt.Rate(Tokens.ctx.xph) .. L.STALL_MARK)
  T.ok(HasText(Fill(ns, false), format(L.TT_STALLED_FMT, L.STALL_MARK, Fmt.Duration(secs))))
  -- a kill: the stall ends, the rate is live again
  Stub.Kill(120)
  Stub.Advance(2)
  T.no((ns.Tracker.GetStall()))
  T.ok(Tokens.ctx.rateStatus ~= "stalled")
  T.no((Tokens.Render("xph")):find(L.STALL_MARK, 1, true))
  T.no(HasText(Fill(ns, false), L.TT_STALLED_RESUME))
end)

T.test("engine C2: a persisted server cap shows the cap until XP comes again", function()
  local ns = Start({ locale = "frFR", capLevel = Stub.player.level })
  local Tokens, L = ns.Tokens, ns.L
  Tokens.Acquire("test", 3)
  local capLevel, isServerCap = ns.Tracker.GetCapInfo()
  T.eq(capLevel, 10)
  T.eq(isServerCap, true)
  T.ok(ns.Tracker.IsMax(), "the cap counts as max level")
  T.ok(Tokens.ctx.isServerCap)
  local lines = Fill(ns, false)
  T.ok(HasText(lines, L.TT_CAP_RESUME), "cap explained")
  T.no(HasText(lines, L.TT_MAX_LEVEL))
  -- the server gives XP again: back to the XP block by itself
  Stub.Kill(120)
  Stub.Advance(2)
  T.eq((ns.Tracker.GetCapInfo()), nil, "cap cleared by the XP gain")
  T.no(ns.Tracker.IsMax())
  T.no(Tokens.ctx.isServerCap)
  lines = Fill(ns, false)
  T.no(HasText(lines, L.TT_CAP_RESUME))
  T.ok(Find(lines, L.TT_NEXT_LEVEL) ~= nil, "XP block back")
end)
