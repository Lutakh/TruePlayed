-- tests/test_exclusions.lua - the professions and dead exclusions (1.4.0): the mask on 5
-- bits (C.MASK_PROF, C.MASK_DEAD: 32 masks, C.INCLUDED), the settings exclude.prof /
-- exclude.dead (options panel, context menu, /tpl prof | dead), the played total, the level
-- time and the rates without that time, the pause and its tooltip line, the EMA lists of 8
-- widened to 32 (Core.WidenEma) with the rate of a new mask equal to the old one at first,
-- the rebuilt time of an older record (Stats.EstTime), the bars' parts under every mask,
-- the mask label within a budget (Stats.MaskLabel) and the statistics window's header.
local Stub, T = ...

local format = string.format

local function Login(db)
  if db then _G.TruePlayedDB = db end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns
end

local function Fill(ns, detailed)
  local tt = GameTooltip
  tt:ClearLines()
  ns.Tooltip.Fill(tt, detailed)
  local out = {}
  for i, l in ipairs(tt._lines or {}) do out[i] = { l[1] or l.left, l[2] or l.right } end
  return out
end

local function HasLine(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return true end
  end
  return false
end

local function Bit(m, b) return math.floor(m / b) % 2 == 1 end

---------------------------------------------------------------------------

T.test("masks: 32 of them; f excluded by MASK_PROF only, x by MASK_DEAD only; 0..7 unchanged", function()
  local ns = Login()
  local C = ns.C
  T.eq({ C.MASK_PROF, C.MASK_DEAD, C.MASK_COUNT, C.MASK_OLD_COUNT }, { 8, 16, 32, 8 })
  T.eq(C.INCLUDED[C.MASK_COUNT], nil, "no mask past the last one")
  for m = 0, C.MASK_COUNT - 1 do
    local row = C.INCLUDED[m]
    T.ok(type(row) == "table", "mask " .. m)
    T.eq(row.f, not Bit(m, C.MASK_PROF), "professions under mask " .. m)
    T.eq(row.x, not Bit(m, C.MASK_DEAD), "dead under mask " .. m)
    T.eq(row.u, true, "untracked never excluded, mask " .. m)
    local old = C.INCLUDED[m % C.MASK_OLD_COUNT]
    for _, k in ipairs(C.STATE_KEYS) do
      if k ~= "f" and k ~= "x" then T.eq(row[k], old[k], format("mask %d key %s: as mask %d", m, k, m % 8)) end
    end
  end
  -- AFK, inn and city never exclude professions or dead time
  for m = 0, 7 do T.eq({ C.INCLUDED[m].f, C.INCLUDED[m].x }, { true, true }, "mask " .. m) end
end)

T.test("settings: exclude.prof / exclude.dead set the mask; /tpl prof | dead; options; context menu", function()
  Stub.InstallUI({ ldb = false })
  local ns = Login()
  local L, C = ns.L, ns.C
  T.eq(ns.C.DEFAULTS.exclude, { afk = false, inn = false, city = false, prof = false, dead = false })
  T.eq(ns.GetMask(), 0)
  ns.Core.SetSetting("exclude.prof", true)
  T.eq(ns.GetMask(), C.MASK_PROF)
  ns.Core.SetSetting("exclude.dead", true)
  T.eq(ns.GetMask(), C.MASK_PROF + C.MASK_DEAD)
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(ns.GetMask(), 25)
  -- /tpl: no argument toggles, on / off set; each prints its state
  local n = #Stub.printed
  Stub.RunSlash("prof")
  T.eq(ns.settings.exclude.prof, false, "/tpl prof toggles")
  T.ok(#Stub.printed > n and Stub.printed[#Stub.printed]:find(L.MENU_EXCLUDE_PROF, 1, true) ~= nil, "printed")
  Stub.RunSlash("dead off")
  T.eq(ns.settings.exclude.dead, false)
  Stub.RunSlash("dead on")
  T.eq(ns.settings.exclude.dead, true)
  T.ok(Stub.printed[#Stub.printed]:find(L.MENU_EXCLUDE_DEAD, 1, true) ~= nil)
  T.eq(ns.GetMask(), C.MASK_AFK + C.MASK_DEAD)
  n = #Stub.printed
  Stub.RunSlash("dead maybe")
  T.ok(#Stub.printed == n + 1 and ns.settings.exclude.dead == true, "a bad argument: unknown, nothing changed")
  T.ok(L.HELP_EXCLUDE:find("prof", 1, true) and L.HELP_EXCLUDE:find("dead", 1, true), "help line")
  -- the options panel: two checkboxes after city
  ns.Options.Open()
  local controls = rawget(Stub.ui.categories[1].frame, "controls")
  T.eq(controls["exclude.prof"].index, controls["exclude.city"].index + 1)
  T.eq(controls["exclude.dead"].index, controls["exclude.prof"].index + 1)
  -- the bar's context menu
  local ui = Stub.ui
  ns.Options.ShowContextMenu(ns.Bar.frame)
  local root = ui.lastMenu
  local prof = ui.FindMenuItem(root, L.MENU_EXCLUDE_PROF)
  local dead = ui.FindMenuItem(root, L.MENU_EXCLUDE_DEAD)
  T.ok(prof ~= nil and prof.kind == "checkbox" and dead ~= nil and dead.kind == "checkbox")
  T.no(ui.IsChecked(prof))
  T.ok(ui.IsChecked(dead))
  ui.ClickMenuItem(prof)
  T.eq(ns.settings.exclude.prof, true)
  ui.ClickMenuItem(dead)
  T.eq(ns.settings.exclude.dead, false)
  -- saved sparsely like the others
  Stub.Logout()
  T.eq(_G.TruePlayedDB.settings.exclude, { afk = true, prof = true })
end)

T.test("dead excluded: played, level and zone times leave it out; paused 'time dead'; tooltip", function()
  local ns = Login()
  local L, C, Stats = ns.L, ns.C, ns.Stats
  Stub.Advance(100)
  Stub.Die()
  Stub.Advance(30)
  Stub.ReleaseSpirit()
  Stub.Advance(50)
  T.eq({ ns.Tracker.IsPaused(0) }, { false, nil }, "not paused without the exclusion")
  T.eq({ ns.Tracker.IsPaused(C.MASK_DEAD) }, { true, "dead" })
  T.eq({ ns.Tracker.IsPaused(C.MASK_AFK + C.MASK_DEAD) }, { true, "dead" }, "AFK while dead is dead")
  ns.Core.SetSetting("exclude.dead", true)
  Stub.Advance(1)
  local lines = Fill(ns)
  T.ok(HasLine(lines, format(L.TT_PAUSED_FMT, L.PAUSE_DEAD)), "the pause line")
  T.ok(lines[1][2] == format(L.TT_EXCL_FMT, L.MASK_DEAD), "the title says what is excluded")
  Stub.Resurrect(true)
  Stub.Advance(20)
  T.eq({ ns.Tracker.IsPaused() }, { false, nil }, "alive: counted again")
  local ch = ns.char
  local x = ch.life.s.x
  T.ok(x >= 80 and x <= 82, "dead time: " .. x)
  local f0, b0, e0 = Stats.Played(ch, 0, nil)
  local f1, b1, e1 = Stats.Played(ch, C.MASK_DEAD, nil)
  T.eq(b1, b0)
  T.eq(e0, 0)
  T.eq(e1, x, "the dead time excluded")
  T.eq(f1, f0 - x)
  T.eq(Stats.Sum(ch.levels[10], C.MASK_DEAD), Stats.Sum(ch.levels[10], 0) - x, "the level")
  T.eq(Stats.Sum(ch.zones[1411], C.MASK_DEAD), Stats.Sum(ch.zones[1411], 0) - ch.zones[1411].s.x, "the zone")
  T.eq(Stats.Sum(ns.session, C.MASK_DEAD), Stats.Sum(ns.session, 0) - x, "the session")
  -- the whole activity stays where it is the subject: deaths and dead time
  local dead, _, deaths = Stats.AccountActivity(ns.db)
  T.eq({ dead, deaths }, { x, 1 })
  T.eq(select(2, Stats.LevelActivity(ch, 10)), x)
end)

T.test("professions excluded: their time left out, paused 'profession time'; AFK while crafting stays AFK", function()
  local ns = Login()
  local L, C, Stats = ns.L, ns.C, ns.Stats
  ns.Core.SetSetting("exclude.prof", true)
  Stub.Advance(10)
  Stub.OpenTradeSkill()
  Stub.Advance(1)
  T.eq((ns.Tracker.GetState()), "f")
  T.eq({ ns.Tracker.IsPaused() }, { true, "prof" })
  T.ok(HasLine(Fill(ns), format(L.TT_PAUSED_FMT, L.PAUSE_PROF)), "the pause line")
  Stub.Advance(40)
  Stub.SetAFK(true)
  T.eq((ns.Tracker.GetState()), "W", "AFK while crafting: the AFK key of the place")
  T.eq({ ns.Tracker.IsPaused() }, { false, nil }, "not excluded by professions")
  Stub.Advance(30)
  Stub.SetAFK(false)
  Stub.CloseTradeSkill()
  Stub.Advance(5)
  local ch = ns.char
  local f = ch.life.s.f
  T.ok(f >= 40 and f <= 42, "professions time: " .. f)
  T.eq(Stats.Sum(ch.life, C.MASK_PROF), Stats.Sum(ch.life, 0) - f)
  T.eq(Stats.Sum(ch.life, C.MASK_PROF + C.MASK_AFK), Stats.Sum(ch.life, C.MASK_AFK) - f, "with AFK too")
  T.eq(Stats.Sum(ch.life, C.MASK_DEAD), Stats.Sum(ch.life, 0), "the dead exclusion leaves it")
end)

T.test("rates: a mask with dead excluded counts no dead time; the XP of every mask grows alike", function()
  local ns = Login()
  local C = ns.C
  for _ = 1, 20 do
    Stub.Advance(30)
    Stub.Kill(100)
  end
  Stub.Advance(5)
  local ema = ns.char.ema
  T.eq(#ema, C.MASK_COUNT)
  local d0, dd = ema[1].d, ema[C.MASK_DEAD + 1].d
  T.near(dd, d0, 1e-6, "no dead time yet: the same counted time")
  Stub.Die()
  Stub.Advance(120)                    -- below C.XP_STALL: the rates still run
  Stub.Resurrect(false)
  Stub.Advance(1)
  T.ok(ema[1].d > d0 + 60, format("mask 0 counted the dead time: %.1f -> %.1f", d0, ema[1].d))
  T.ok(ema[C.MASK_DEAD + 1].d < dd + 5, "mask 16 did not (a tick around the death at most)")
  T.ok(ema[C.MASK_DEAD + C.MASK_PROF + 1].d < dd + 5, "nor mask 24")
  T.ok(ema[C.MASK_DEAD + 1].a > ema[1].a, "its XP decayed less (no dead time)")
  local a0, a16 = ema[1].a, ema[C.MASK_DEAD + 1].a
  Stub.Kill(100)
  Stub.Advance(5)
  T.ok(ema[1].a > a0 and ema[C.MASK_DEAD + 1].a > a16, "a gain feeds every mask")
  -- the rate under dead excluded is the higher one (the same XP over less time)
  local r0 = ns.Stats.Rate(ns.char, 0)
  local r16 = ns.Stats.Rate(ns.char, C.MASK_DEAD)
  T.ok(r0 and r16 and r16 > r0, format("%s > %s", tostring(r16), tostring(r0)))
end)

T.test("migration: saved EMA lists of 8 widened to 32, a new mask's rate equal to its old mask's", function()
  local guid = Stub.player.guid
  local ema, re, he = {}, {}, {}
  for i = 1, 8 do
    ema[i] = { a = 1000 * i, r = 100, q = 10 * i, d = 4000 + i }
    re[i] = { a = 50 * i, d = 3600 + i }
    he[i] = { a = 70 * i, d = 3000 + i }
  end
  local ns = Login({ schema = 1, chars = { [guid] = {
    guid = guid, level = 10, life = { s = { w = 50000 } }, levels = {}, zones = {}, sessions = {},
    ema = ema, rep = { id = 529, f = 529, v = 100, e = re, n = 0 }, pvp = { he = he },
  } } })
  local C = ns.C
  local ch = ns.char
  T.eq(#ch.ema, C.MASK_COUNT)
  T.eq(#ch.rep.e, C.MASK_COUNT)
  T.eq(#ch.pvp.he, C.MASK_COUNT)
  for m = C.MASK_OLD_COUNT, C.MASK_COUNT - 1 do
    local src = m % C.MASK_OLD_COUNT + 1
    T.eq(ch.ema[m + 1], ema[src], "XP, mask " .. m)
    T.ok(ch.ema[m + 1] ~= ch.ema[src], "a copy, not the same table")
    T.eq(ch.rep.e[m + 1], re[src], "reputation, mask " .. m)
    T.eq(ch.pvp.he[m + 1], he[src], "honor, mask " .. m)
  end
  T.near(ch.ema[1].a, 1000, 2, "the old masks kept (a few seconds of play since)")
  T.near(ch.ema[1].d, 4001, 2)
  local r0 = ns.Stats.Rate(ch, 0)
  T.ok(r0 ~= nil, "a rate")
  T.eq(ns.Stats.Rate(ch, C.MASK_DEAD), r0, "dead excluded: the same rate right after the update")
  T.eq(ns.Stats.Rate(ch, C.MASK_PROF + 3), ns.Stats.Rate(ch, 3), "professions + AFK + inn: as AFK + inn")
end)

T.test("EstTime: an older rebuilt time is valued without the activity the mask excludes", function()
  local ns = Login()
  local Stats, C = ns.Stats, ns.C
  -- 600 s of places, 300 professions, 100 dead; 200 s rebuilt by an older version (no es)
  local b = { s = { w = 400, c = 200, f = 300, x = 100 }, est = 200 }
  T.eq((Stats.EstTime(b, 0)), 200)
  T.eq((Stats.EstTime(b, C.MASK_PROF)), 200, "the places only: excluding professions leaves it")
  T.eq((Stats.EstTime(b, C.MASK_DEAD)), 200)
  T.eq((Stats.EstTime(b, C.MASK_PROF + C.MASK_DEAD)), 200)
  T.near((Stats.EstTime(b, C.MASK_CITY + C.MASK_PROF)), 200 * 400 / 600, 1e-9, "the city share left out")
  -- with a per-key map: exactly its keys under the mask
  local b2 = { s = { w = 400, f = 300, x = 100 }, est = 150, es = { w = 150 } }
  T.eq((Stats.EstTime(b2, C.MASK_PROF + C.MASK_DEAD)), 150)
end)

T.test("LevelSegments: under every mask the parts sum to Stats.Sum (prof / dead 0 when excluded)", function()
  local ns = Login()
  local Stats, C = ns.Stats, ns.C
  local b = { s = { w = 1000, W = 50, d = 300, D = 20, r = 200, R = 10, p = 150, P = 5, i = 90, I = 9, c = 80,
                    C = 8, t = 70, T = 7, x = 60, f = 40, u = 33 }, pw = 100 }
  local out = {}
  for m = 0, C.MASK_COUNT - 1 do
    local total = Stats.LevelSegments(b, m, out)
    T.eq(total, Stats.Sum(b, m), "mask " .. m)
    T.eq(out.prof, Bit(m, C.MASK_PROF) and 0 or 40, "professions, mask " .. m)
    T.eq(out.dead, Bit(m, C.MASK_DEAD) and 0 or 60, "dead, mask " .. m)
  end
end)

T.test("MaskLabel: every exclusion named without a budget; within one, the first ones then +N", function()
  local ns = Login()
  local Stats, L, C = ns.Stats, ns.L, ns.C
  local S = L.SEP
  T.eq(Stats.MaskLabel(0), nil)
  T.eq(Stats.MaskLabel(C.MASK_PROF), L.MASK_PROF)
  T.eq(Stats.MaskLabel(C.MASK_DEAD), L.MASK_DEAD)
  T.eq(Stats.MaskLabel(31), table.concat({ L.MASK_AFK, L.MASK_INN, L.MASK_CITY, L.MASK_PROF, L.MASK_DEAD }, S))
  T.eq(Stats.MaskLabel(7, 3), table.concat({ L.MASK_AFK, L.MASK_INN, L.MASK_CITY }, S), "three within three")
  T.eq(Stats.MaskLabel(31, 3), format(L.MASK_MORE_FMT, L.MASK_AFK .. S .. L.MASK_INN, 3), "two named, +3")
  T.eq(Stats.MaskLabel(25, 2), format(L.MASK_MORE_FMT, L.MASK_AFK, 2))
  T.eq(Stats.MaskLabel(24, 2), L.MASK_PROF .. S .. L.MASK_DEAD)
  T.eq(Stats.MaskLabel(24, 1), format(L.MASK_MORE_FMT, L.MASK_PROF, 1), "at least one named")
  T.eq(Stats.MaskLabel(31), Stats.MaskLabel(31), "cached")
  T.ok(Stats.MaskLabel(31, 3) ~= Stats.MaskLabel(31), "one cache entry per budget")
  for m = 1, C.MASK_COUNT - 1 do
    for _, budget in ipairs({ C.MASK_LABEL_TT, C.MASK_LABEL_WIN, C.MASK_LABEL_CARD }) do
      local label = Stats.MaskLabel(m, budget)
      local items = select(2, label:gsub(S, S)) + 1
      if label:find("+", 1, true) then items = items + 1 end   -- "+N" is an item too
      T.ok(items <= budget, format("mask %d budget %d: %q", m, budget, label))
    end
  end
end)

T.test("window: the header follows the professions and dead exclusions (within its budget)", function()
  Stub.InstallUI({ ldb = false })
  local ns = Login()
  local L, C, Stats = ns.L, ns.C, ns.Stats
  ns.Window.Show("zones")
  local tp = rawget(_G, "TruePlayedStatsFrame").tp
  T.eq(rawget(tp.filter, "_text"), "")
  ns.Core.SetSetting("exclude.dead", true)
  T.eq(rawget(tp.filter, "_text"), format(L.WIN_FILTER_FMT, L.MASK_DEAD), "refreshed at once")
  for _, k in ipairs({ "afk", "inn", "city", "prof" }) do ns.Core.SetSetting("exclude." .. k, true) end
  T.eq(rawget(tp.filter, "_text"), format(L.WIN_FILTER_FMT, Stats.MaskLabel(31, C.MASK_LABEL_WIN)))
end)
