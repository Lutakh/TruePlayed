-- tests/test_levels_extra.lua - per-level additions (lot 8, A3) and short continents (A4):
-- the level-start estimate (levels[L].eta / etaP / etaM), the cumulative time to the end
-- of each level (Stats.CumulativeTime, LevelHistory rows), the Levels tab columns Dead and Est.
-- (the Levels tab rework: the Dead part and deaths line of the chart's bars, the Deaths
-- and "Estimated at start" cards of the detail sheet), continents with less than
-- C.CONT_MIN_SECS hidden in the tooltip and the Zones tab (data kept), saved-data repair
-- and a late SavedVariables swap.
local Stub, T = ...

local OTHER_GUID = "Player-4619-0BADF00D"

local function Login(db, settle)
  if db then _G.TruePlayedDB = db end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = settle })
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

local function Has(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return true end
  end
  return false
end

local function StatsTP()
  return rawget(_G, "TruePlayedStatsFrame").tp
end

local function RowWith(tp, text)
  for _, row in ipairs(tp.rows) do
    if row:IsShown() and tp.cells[row][1]:GetText() == text then return row end
  end
  return nil
end

-- Plays `n` minutes with one kill of `xp` each (a measured rate after 10 minutes).
local function Grind(n, xp)
  for _ = 1, n do
    Stub.Advance(60)
    Stub.Kill(xp)
  end
end

---------------------------------------------------------------------------
-- A3. level-start estimate
---------------------------------------------------------------------------

T.test("eta: stored when a level begins (time to level shown then), once", function()
  local ns = Login()
  local ch, Stats = ns.char, ns.Stats
  Grind(12, 200)
  local rate, _, _, _, _, status = Stats.Rate(ch, 0)
  T.eq(status, "ok", "a measured rate")
  T.ok(rate > 0)
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 100)     -- level 11, 100 XP in
  Stub.Advance(1)
  local lb = ch.levels[11]
  T.ok(lb and lb.eta, "level 11 has its estimate")
  local expect = Stats.ETA(ch, ns.GetMask(), 100, Stub.player.max, Stub.player.rest, false)
  T.near(lb.eta, expect, expect * 0.01 + 1, "the time to level shown at the level-up")
  T.eq(lb.etaP, math.floor(100 / Stub.player.max * 1000 + 0.5) / 1000, "XP fraction then")
  local first = lb.eta
  Grind(5, 200)
  T.eq(lb.eta, first, "never recomputed")
  local _, _, _, eta, etaP = Stats.LevelActivity(ch, 11)
  T.eq({ eta, etaP }, { lb.eta, lb.etaP }, "Stats.LevelActivity")
  local rows = Stats.LevelHistory(ch, 0, ns.Tracker.GetSync(), Stub.Now(), {})
  T.eq({ rows[1].level, rows[1].eta, rows[1].etaP }, { 11, lb.eta, lb.etaP }, "LevelHistory row")
end)

-- The exclusion mask the estimate was taken under (levels[L].etaM): the sheet compares the
-- level's time with it only under that mask (review stats-eta-verdict-mask-mismatch).
T.test("eta: the mask it was taken under is stored (etaM), in the history row; repaired; kept by a late swap", function()
  local ns = Login()
  local ch, Stats = ns.char, ns.Stats
  Grind(12, 200)
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(ns.GetMask(), 1)
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 100)     -- level 11 under mask 1
  Stub.Advance(1)
  local lb = ch.levels[11]
  T.ok(lb and lb.eta, "level 11 has its estimate")
  T.eq(lb.etaM, 1, "taken with AFK excluded")
  ns.Core.SetSetting("exclude.afk", false)
  ns.Core.SetSetting("exclude.city", true)
  Grind(3, 200)
  T.eq(lb.etaM, 1, "a later mask change leaves it")
  local rows = Stats.LevelHistory(ch, ns.GetMask(), ns.Tracker.GetSync(), Stub.Now(), {})
  T.eq({ rows[1].level, rows[1].eta, rows[1].etaM }, { 11, lb.eta, 1 }, "LevelHistory row")
  T.eq({ rows[2].level, rows[2].etaM }, { 10, 0 }, "the install level's, taken under mask 0")
  -- repair: a whole 0..7 kept, anything else dropped (eta itself kept)
  Stub.Reset()
  local guid = Stub.player.guid
  local function Lb(etaM) return { s = { w = 10 }, z = {}, xp = 0, d = 0, eta = 3600, etaP = 0, etaM = etaM } end
  ns = Login({ schema = 1, chars = { [guid] = {
    guid = guid, level = 12, life = { s = { w = 50 } },
    levels = { [1] = Lb(0), [2] = Lb(7), [3] = Lb(3), [4] = Lb(-1), [5] = Lb(8), [6] = Lb(2.5), [7] = Lb("1"),
               [8] = Lb(0 / 0), [9] = Lb(1 / 0), [10] = Lb(nil) },
    zones = {}, sessions = {},
  } } })
  local lv, got = ns.char.levels, {}
  for l = 1, 10 do got[l] = lv[l].etaM == nil and "-" or lv[l].etaM end
  T.eq(got, { 0, 7, 3, "-", "-", "-", "-", "-", "-", "-" }, "etaM repaired")
  T.eq(lv[5].eta, 3600, "the estimate kept without its mask")
  -- a late SavedVariables swap: this load's estimate keeps its mask
  Stub.Reset()
  Login()
  Stub.Advance(120)
  Stub.Logout()
  local real = Stub.DeepCopy(Stub.saved)
  Stub.Reset({ keepWorld = true })
  ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(30)
  Stub.GrantXP(Stub.player.max)                       -- level 11 with the "~" estimate
  Stub.Advance(2)
  local blank = ns.char
  T.eq(blank.levels[11].etaM, 0, "taken under mask 0 in the blank table")
  _G.TruePlayedDB = real
  Stub.Advance(2)
  T.ok(ns.char ~= blank, "swapped")
  T.eq(ns.char.levels[11].etaM, 0, "carried by the swap")
  T.eq(Stub.errors, {})
end)

T.test("eta: the install level takes its first measured estimate; the pre-install one is shown at a level start", function()
  local ns = Login()
  local ch = ns.char
  Stub.Advance(15)                                    -- install sync at +10 s
  T.ok(ch.prior ~= nil, "a pre-install estimate exists")
  T.eq(ch.levels[10].eta, nil, "install level: not from the pre-install estimate")
  Grind(12, 200)
  T.ok(ch.levels[10].eta ~= nil, "install level: its first measured estimate")
  T.ok(ch.levels[10].etaP > ns.C.ETA_START_FRAC, "taken mid-level (partial level)")
  -- a level-up right away on a second character: the shown "~" estimate is stored
  Stub.Reset()
  ns = Login()
  ch = ns.char
  Stub.Advance(15)
  Stub.GrantXP(Stub.player.max)
  Stub.Advance(1)
  local _, _, _, _, _, status = ns.Stats.Rate(ch, 0)
  T.eq(status, "estimate")
  T.ok(ch.levels[11].eta ~= nil, "the estimate shown at the level-up")
  T.eq(ch.levels[11].etaP, 0)
end)

T.test("eta: no rate when the level begins and none before 5 %: nothing stored", function()
  Stub.server.total, Stub.server.levelPlayed = 100, 50   -- too short for a pre-install estimate
  local ns = Login()
  local ch = ns.char
  Stub.Advance(5)
  T.eq(ch.prior, nil)
  Stub.GrantXP(Stub.player.max)                          -- level 11, no rate at all
  Stub.Advance(2)
  T.eq(ch.levels[11].eta, nil, "no rate: nothing")
  Stub.GrantXP(math.floor(Stub.player.max * 0.2))        -- past C.ETA_START_FRAC
  Grind(12, 200)
  T.eq(ch.levels[11].eta, nil, "a rate that comes after 5 % of the level is not a level-start estimate")
  T.eq(ch.levels[10].eta, nil, "older levels have none")
end)

T.test("eta: zero garbage per tick while waiting for a rate and once stored", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  Stub.server.total, Stub.server.levelPlayed = 100, 50
  local ns = Login()
  Stub.Advance(5)
  Stub.GrantXP(Stub.player.max)
  Stub.Advance(60)
  T.eq(ns.char.levels[11].eta, nil)
  local kb = T.alloc(function() Stub.Advance(1) end, 300)
  T.ok(kb <= 1, ("300 ticks waiting for a rate allocated %.2f KB"):format(kb))
end)

---------------------------------------------------------------------------
-- A3. cumulative time
---------------------------------------------------------------------------

-- Level 3 record: pre-install time (u) before level 2, levels 2 and 3 tracked.
local function CumRecord()
  return {
    guid = OTHER_GUID, level = 3,
    life = { s = { u = 1000, w = 800, W = 100, x = 50 }, xp = 0, d = 1 },
    levels = {
      [2] = { s = { w = 500, W = 100, x = 50 }, z = {}, xp = 0, d = 1 },
      [3] = { s = { w = 300 }, z = {}, xp = 0, d = 0 },
    },
    zones = {}, sessions = {},
  }
end

T.test("cumulative time to the end of each level: played total down, exclusions applied", function()
  local ns = Login()
  local Stats = ns.Stats
  local rec = CumRecord()
  -- mask 0: played 1950 = u 1000 + 950 tracked
  T.eq(Stats.CumulativeTime(rec, 3, 0, nil, 0), 1950, "current level: the played total")
  T.eq(Stats.CumulativeTime(rec, 2, 0, nil, 0), 1650, "end of level 2")
  T.eq(Stats.CumulativeTime(rec, 1, 0, nil, 0), 1000, "end of level 1: the pre-install time")
  T.eq(Stats.CumulativeTime(rec, 4, 0, nil, 0), nil, "above the level")
  -- AFK excluded: the played total and every level lose their AFK part (dead stays)
  T.eq(Stats.CumulativeTime(rec, 3, 1, nil, 0), 1850)
  T.eq(Stats.CumulativeTime(rec, 2, 1, nil, 0), 1550)
  T.eq(Stats.CumulativeTime(rec, 1, 1, nil, 0), 1000, "level 2 counted 550 under the mask")
  -- a live sync: the current level is the server's
  local sync = { valid = true, total = 3000, g = 0, level = 3, levelValid = true, levelPlayed = 400 }
  T.eq(Stats.CumulativeTime(rec, 3, 0, sync, 0), 3000)
  T.eq(Stats.CumulativeTime(rec, 2, 0, sync, 0), 2600)
  -- LevelHistory carries the same values
  local rows = Stats.LevelHistory(rec, 1, nil, 0, {})
  T.eq({ rows[1].level, rows[1].cum }, { 3, 1850 })
  T.eq({ rows[2].level, rows[2].cum, rows[2].dead, rows[2].deaths }, { 2, 1550, 50, 1 })
  -- never below 0
  rec.life.s = { w = 10 }
  T.eq(Stats.CumulativeTime(rec, 1, 0, nil, 0), 0)
end)

---------------------------------------------------------------------------
-- A3. Levels tab: Dead and Est. columns
---------------------------------------------------------------------------

-- Lot 8 part B: the columns are laid out from the visible ones (tests/test_window_cols.lua
-- has the general checks); here the Dead and Est. columns of part A.
-- Levels tab rework: the Levels table became the chart. The Dead column is the Dead part
-- of a bar and the deaths line of its tooltip; the columns "without overlap" are the bars,
-- side by side inside the plot; a character without deaths has no Dead part and the
-- window keeps the chart's minimum width; the detail sheet's Deaths card has the count and
-- the dead time. The Est. column moves to the detail sheet's "Estimated at start" card
-- (the test below).
-- GameTooltip lines { left, right } of the chart's bar of level k, the bar left afterwards.
local function BarTip(tp, k)
  local hit = tp.chart.cols[k].hit
  hit:GetScript("OnEnter")(hit)
  local out = {}
  for i, l in ipairs(GameTooltip._lines or {}) do out[i] = { l[1] or l.left, l[2] or l.right } end
  hit:GetScript("OnLeave")(hit)
  return out
end

local function Right(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i][2] end
  end
  return nil
end

local function Dying()
  Grind(12, 200)
  Stub.Die(); Stub.Advance(30); Stub.ReleaseSpirit(); Stub.Advance(270); Stub.Resurrect(true)
  Stub.Die(); Stub.Advance(10); Stub.Resurrect(false)
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 50)
  Stub.Advance(2)
end

T.test("window: Dead (time and deaths) and Est. columns, shown when used, without overlap", function()
  local ns = Login()
  local L, Fmt = ns.L, ns.Fmt
  Dying()
  ns.Window.Show("levels")
  local tp = StatsTP()
  local f = rawget(_G, "TruePlayedStatsFrame")
  local ch = tp.chart
  T.ok(ch ~= nil and ch.root:IsShown(), "the chart")
  -- the bars side by side, the last one inside the plot
  local prevEnd = -1
  for k = 1, ch.state.nCols do
    local hit = ch.cols[k].hit
    local p = rawget(hit, "_points")[1]
    T.ok(p.x >= prevEnd, "bar " .. k .. " starts after the previous one")
    prevEnd = p.x + hit:GetWidth()
  end
  T.ok(prevEnd <= ch.geo.plotW, "the last bar ends inside the plot: " .. prevEnd)
  T.ok(ch.root:GetWidth() <= f:GetWidth() - 28, "the chart inside the window")
  local t10 = BarTip(tp, 10)
  T.eq(Right(t10, L.BD_DEAD), string.format(L.LV_PART_FMT, Fmt.Duration(310), Fmt.Percent(310 / ch.cols[10].sumAll)),
    "the dead time of level 10")
  T.eq(Right(t10, L.TT_DEATHS), Fmt.Number(2), "two deaths")
  local t11 = BarTip(tp, 11)
  T.eq(Right(t11, L.BD_DEAD), nil, "no dead time at level 11")
  T.eq(Right(t11, L.TT_DEATHS), nil, "no death at level 11")
  -- the detail sheet's Deaths card: the count and the dead time, "none" at 11
  local hit = ch.cols[10].hit
  hit:GetScript("OnClick")(hit, "LeftButton")
  local deaths = tp.detail.cards.deaths
  T.eq({ deaths.label:GetText(), deaths.value:GetText(), deaths.sub:GetText() },
    { L.TT_DEATHS, Fmt.Number(2), string.format(L.LV_DEAD_SUB_FMT, Fmt.Duration(310)) }, "detail: deaths at 10")
  hit = ch.cols[11].hit
  hit:GetScript("OnClick")(hit, "LeftButton")
  T.eq({ deaths.value:GetText(), deaths.sub:GetText() }, { Fmt.Number(0), L.LD_NONE }, "detail: none at 11")
  -- a character without any: no Dead part, the chart's minimum width
  ns.db.chars[OTHER_GUID] = { guid = OTHER_GUID, name = "Tamar", level = 5, life = { s = { w = 50 } },
    levels = { [5] = { s = { w = 50 }, z = {}, xp = 0, d = 0 } }, zones = {}, sessions = {} }
  ns.Core.RepairChar(ns.db.chars[OTHER_GUID])
  ns.Window.SetView(OTHER_GUID)
  T.eq(f:GetWidth(), 1040)
  local t5 = BarTip(tp, 5)
  T.eq(Right(t5, L.BD_DEAD), nil)
  T.eq(Right(t5, L.TT_DEATHS), nil)
  ns.Window.Toggle("zones")
  T.eq(f:GetWidth(), 700, "other tabs: the base width")
  ns.Window.Hide()
  T.eq(Stub.onUpdateCount, 0)
end)

-- Levels tab rework: the estimate made when a level began (levels[L].eta) is shown by the
-- detail sheet's "Estimated at start" card (LevelDetail, spec section 5.2): the install
-- level's first estimate at level 10, its own at level 11, dots for a level without any.
-- The level in progress shows its projection there instead, so 11 is completed first.
T.test("window: the detail sheet shows the estimate made when the level began", function()
  local ns = Login()
  local Fmt = ns.Fmt
  Dying()
  Grind(3, 200)
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)     -- level 12: 11 completed
  Stub.Advance(2)
  ns.Window.Show("levels")
  local tp = StatsTP()
  local function Eta(k)
    local hit = tp.chart.cols[k].hit
    hit:GetScript("OnClick")(hit, "LeftButton")
    return tp.detail.eta and tp.detail.eta:GetText()
  end
  T.ok(ns.char.levels[10].eta ~= nil and ns.char.levels[11].eta ~= nil)
  T.eq(Eta(10), Fmt.Duration(ns.char.levels[10].eta), "install level: its first estimate")
  T.eq(Eta(11), Fmt.Duration(ns.char.levels[11].eta))
  ns.char.levels[11].eta = nil
  ns.Window.Refresh()
  T.eq(Eta(11), ns.L.DOTS, "none: dots")
end)

T.test("window: deaths recorded before this version (no dead time) show the count alone", function()
  local ns = Login()
  ns.char.levels[10].d = 3
  ns.Window.Show("levels")
  local tp = StatsTP()
  local L = ns.L
  local t10 = BarTip(tp, 10)
  T.eq(Right(t10, ns.L.TT_DEATHS), ns.Fmt.Number(3), "the count alone")
  T.eq(Right(t10, L.BD_DEAD), nil, "no dead time")
  -- the detail sheet's Deaths card: the count, no sub (neither a dead time nor "none")
  local deaths = tp.detail.cards.deaths
  T.eq({ deaths.value:GetText(), deaths.sub:GetText() }, { ns.Fmt.Number(3), "" }, "detail: the count alone")
end)

---------------------------------------------------------------------------
-- A4. continents shorter than a minute
---------------------------------------------------------------------------

T.test("continents with less than a minute are not listed (tooltip and Zones tab), data kept", function()
  local ns = Login()
  local L = ns.L
  Stub.Advance(120)                                   -- Durotar (Kalimdor): 2 minutes
  local zones = ns.char.zones
  zones[1453] = { s = { w = 30 }, xp = 0 }            -- Stormwind: Eastern Kingdoms, 30 s
  zones.i389 = { s = { w = 59 }, xp = 0 }             -- "Instances": 59 s
  zones.o = { s = { w = 600 }, xp = 0 }               -- no continent: never listed
  local lines = Fill(ns, true)
  T.ok(Has(lines, L.SECTION_CONTINENTS))
  T.ok(Has(lines, "Kalimdor"))
  T.no(Has(lines, "Eastern Kingdoms"), "30 s: not listed")
  T.no(Has(lines, L.BD_DUNGEON), "59 s: not listed")
  T.no(Has(lines, "Other"), "time without a continent: not listed")
  T.ok(zones[1453] and zones.i389 and zones.o, "the data stays")
  ns.Window.Show("zones")
  local tp = StatsTP()
  T.ok(RowWith(tp, "Kalimdor"))
  T.eq(RowWith(tp, "Eastern Kingdoms"), nil)
  T.eq(RowWith(tp, L.BD_DUNGEON), nil)
  T.eq(RowWith(tp, "Other"), nil)
  T.ok(RowWith(tp, "Stormwind City " .. L.CITY_MARK), "the zone itself is still listed")
  -- a minute: listed (also with the time excluded by a mask, dashed)
  zones.i389.s.w = 60
  zones[1453].s = { c = 60 }
  ns.Core.SetSetting("exclude.city", true)
  ns.Window.Refresh()
  T.ok(RowWith(tp, L.BD_DUNGEON), "60 s: listed")
  T.eq(RowWith(tp, "Other"), nil)
  T.eq(tp.cells[RowWith(tp, "Eastern Kingdoms")][2]:GetText(), "-", "excluded city time: dashed")
  lines = Fill(ns, true)
  T.ok(Has(lines, L.BD_DUNGEON)); T.ok(Has(lines, "Eastern Kingdoms"))
  T.no(Has(lines, "Other"))
  -- nothing but short continents: no Continents block at all
  for k in pairs(zones) do zones[k] = nil end
  zones[1411] = { s = { w = 20 }, xp = 0 }
  T.no(Has(Fill(ns, true), L.SECTION_CONTINENTS), "tooltip")
  ns.Window.Refresh()
  T.eq(RowWith(tp, L.SECTION_CONTINENTS), nil, "Zones tab")
end)

---------------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------------

T.test("repair: bad level-start estimates are dropped, good ones kept", function()
  local guid = Stub.player.guid
  local function Lb(eta, etaP) return { s = { w = 10 }, z = {}, xp = 0, d = 0, eta = eta, etaP = etaP } end
  local ns = Login({ schema = 1, chars = { [guid] = {
    guid = guid, level = 10, life = { s = { w = 50 } },
    levels = { [5] = Lb(-5, 2), [6] = Lb("x", -0.1), [7] = Lb(0 / 0, 0 / 0), [8] = Lb(1 / 0, 0.5),
               [9] = Lb(3600, 0.02), [10] = Lb(nil, nil) },
    zones = {}, sessions = {},
  } } })
  local lv = ns.char.levels
  for l = 5, 7 do T.eq({ lv[l].eta, lv[l].etaP }, {}, "level " .. l) end
  T.eq({ lv[8].eta, lv[8].etaP }, { nil, 0.5 }, "inf dropped, fraction kept")
  T.eq({ lv[9].eta, lv[9].etaP }, { 3600, 0.02 })
end)

T.test("late SavedVariables swap: this load's level-start estimate and dead time follow", function()
  Login()
  Stub.Advance(120)
  Stub.Logout()
  local real = Stub.DeepCopy(Stub.saved)
  Stub.Reset({ keepWorld = true })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(30)
  Stub.GrantXP(Stub.player.max)                       -- level 11 with the "~" estimate
  Stub.Advance(2)
  Stub.Die(); Stub.Advance(20); Stub.Resurrect(false)
  local blank = ns.char
  T.ok(blank.levels[11].eta ~= nil)
  local eta, etaP = blank.levels[11].eta, blank.levels[11].etaP
  _G.TruePlayedDB = real
  Stub.Advance(2)
  local ch = ns.char
  T.ok(ch ~= blank, "swapped")
  T.eq({ ch.levels[11].eta, ch.levels[11].etaP }, { eta, etaP })
  T.eq(ch.life.s.x, 20); T.eq(ch.levels[11].s.x, 20); T.eq(ch.life.d, 1)
end)
