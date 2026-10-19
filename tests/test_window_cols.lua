-- tests/test_window_cols.lua - lot 8 part B (UI): the tooltip breakdown largest first, the
-- Shift tooltip without the averages / level history / account lines, and the statistics
-- window: columns shown only when used and laid out again, level rows "19 » 20" with the
-- date the next level was reached and the cumulative time, the date format and clock
-- settings, the resizable window (size saved), the capitals Time column, the options.
-- Levels tab rework: the Levels table of a character became the chart (LevelChart.lua);
-- its tests here were ported to the bars (tooltip title, Reached line, parts), the strip
-- and chips (cumulative and played time), the detail sheet's status date and the chart's
-- minimum size; the header tests run on the Zones / Sessions / account tables; the Est.
-- column test reads the detail sheet's "Estimated at start" card (LevelDetail.lua).
local Stub, T = ...

local format = string.format
local RAQUO = " \194\187 "

local function Login(db)
  if db then _G.TruePlayedDB = db end
  Stub.InstallUI({ ldb = false })
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

local function Find(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i], i end
  end
  return nil
end

local function Frame() return rawget(_G, "TruePlayedStatsFrame") end
local function TP() return Frame().tp end
local function Span(l) return l .. RAQUO .. (l + 1) end

local function RowWith(tp, text)
  for _, row in ipairs(tp.rows) do
    if row:IsShown() and tp.cells[row][1]:GetText() == text then return row end
  end
  return nil
end

local function Cell(tp, row, id)
  local c = tp.layout.pos[id]
  return c and tp.cells[row][c]:GetText() or nil
end

-- Ids of the visible columns, in order.
local function Ids(tp)
  local out = {}
  for c = 1, tp.layout.n do out[c] = tp.layout.cols[c].id end
  return out
end

-- The Levels tab of a character is the chart (LevelChart.lua): its handles, and the
-- tooltip of the bar of level k (the classic theme: GameTooltip) as { left, right } lines,
-- the bar left afterwards.
local function Chart() return TP().chart end
local function BarTip(k)
  local hit = Chart().cols[k].hit
  hit:GetScript("OnEnter")(hit)
  local out = {}
  for i, l in ipairs(GameTooltip._lines or {}) do out[i] = { l[1] or l.left, l[2] or l.right } end
  hit:GetScript("OnLeave")(hit)
  return out
end
local function Right(lines, left)
  local l = Find(lines, left)
  return l and l[2] or nil
end

-- Headers in order, without overlap, the last one inside the content; every shown row
-- cell placed like its header.
local function CheckGeometry(tp, what)
  local f = Frame()
  local prevEnd = -1
  for c = 1, tp.layout.n do
    local fs = tp.header[c]
    T.ok(fs:IsShown(), what .. ": header " .. c .. " shown")
    local p = rawget(fs, "_points")[1]
    T.ok(p.x >= prevEnd, what .. ": column " .. c .. " starts after the previous one")
    prevEnd = p.x + fs:GetWidth()
  end
  T.ok(prevEnd <= f:GetWidth() - 50 + 0.5, what .. ": the last column ends inside the content " .. prevEnd)
  for c = tp.layout.n + 1, #tp.header do T.no(tp.header[c]:IsShown(), what .. ": header " .. c .. " hidden") end
  for _, row in ipairs(tp.rows) do
    if row:IsShown() and row:GetWidth() > 0 then
      T.eq(row:GetWidth(), f:GetWidth() - 50, what .. ": row width")
    end
  end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

T.test("tooltip breakdown: largest first in the legend and the gauge", function()
  local ns = Login()
  local L, Fmt = ns.L, ns.Fmt
  local life = ns.char.life
  -- city 40 %, world 30 %, AFK 20 %, inn 10 % (the short view shows the level's breakdown,
  -- Shift adds the character's: both get the same seconds)
  life.s = { w = 3000, W = 2000, i = 1000, c = 4000 }
  ns.char.levels[Stub.player.level].s = { w = 3000, W = 2000, i = 1000, c = 4000 }
  local line = Find(Fill(ns, false), L.TT_BREAKDOWN_LEVEL)
  local function P(key, pct) return format(L.BD_PART_FMT, L[key], Fmt.Percent(pct / 100, 0)) end
  T.eq(line[2], table.concat({ P("BD_CITY", 40), P("BD_WORLD", 30), P("BD_AFK", 20), P("BD_INN", 10) }, L.SEP))
  local fracs, keys = {}, {}
  T.eq(ns.Tooltip.BreakdownFracs(ns.Stats.Breakdown(life, {}), fracs, keys), 4)
  T.eq(keys, { "city", "world", "afk", "inn" })
  T.ok(fracs[1] >= fracs[2] and fracs[2] >= fracs[3] and fracs[3] >= fracs[4], "segments largest first")
end)

T.test("tooltip Shift: top zones of the character, no average / last levels / account / rebuilt lines", function()
  local ns = Login()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  Stub.Advance(120)                                     -- Durotar at level 10
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)   -- level 11
  Stub.SetMap(1413); Stub.Advance(300)                  -- The Barrens
  Stub.SetMap(1454); Stub.Advance(200)                  -- Orgrimmar (a capital)
  Stub.SetMap(1413); Stub.Advance(1)
  ns.char.life.est = 600                                -- "rebuilt after a crash" part
  local det = Fill(ns, true)
  local _, h = Find(det, L.TT_TOP_ZONES)
  T.ok(h, "Top zones header")
  T.eq(det[h + 1][1], "The Barrens")
  T.eq(det[h + 2][1], "Orgrimmar")
  T.eq(det[h + 3][1], "Durotar", "a zone of the previous level too: the whole character")
  T.eq(det[h + 3][2], Fmt.Duration(Stats.Sum(ns.char.zones[1411], 0)))
  -- the city excluded: the capital's time is excluded, it drops out of the top
  ns.Core.SetSetting("exclude.city", true)
  det = Fill(ns, true)
  _, h = Find(det, L.TT_TOP_ZONES)
  T.eq({ det[h + 1][1], det[h + 2][1] }, { "The Barrens", "Durotar" })
  T.no(det[h + 3] and det[h + 3][1] == "Orgrimmar", "a zone whose time is all excluded is not listed")
  ns.Core.SetSetting("exclude.city", false)
  -- the blocks that moved to the statistics window
  for _, detailed in ipairs({ false, true }) do
    for _, l in ipairs(Fill(ns, detailed)) do
      local left = tostring(l[1])
      T.no(left == "Average per level" or left == "Last levels" or left:find("^Level %d+$")
        or left:find("^Account") or left == "Rebuilt after crashes", "moved to the window: " .. left)
    end
  end
  -- the rebuilt part stays as the sub-line under /played (once)
  local n = 0
  for _, l in ipairs(Fill(ns, true)) do
    if l[1] == format(L.TT_EST_FMT, Fmt.Duration(600)) then n = n + 1 end
  end
  T.eq(n, 1, "rebuilt sub-line under /played")
  -- deaths on one line with the time dead (lot 8 part A)
  Stub.Die(); Stub.Advance(60); Stub.Resurrect(false); Stub.Advance(1)
  local deaths = Find(Fill(ns, true), L.TT_DEATHS)
  T.eq(deaths[2], format("%s (%s)", Fmt.Number(1), Fmt.Duration(60)))
end)

---------------------------------------------------------------------------
-- Window: columns
---------------------------------------------------------------------------

-- Levels tab rework: the Levels tab of a character is the chart, without any table column
-- (its former optional columns are the parts of a bar: they are listed in the bar tooltip
-- when used, in the chart's fixed order; tests/test_level_chart.lua checks the stacks).
-- The Sessions and Zones parts are unchanged.
T.test("window: a column empty for every row of the view is not shown; the others are laid out again", function()
  local ns = Login()
  local L = ns.L
  Stub.Advance(120)
  ns.Window.Show("levels")
  local tp = TP()
  T.ok(Chart() ~= nil and Chart().root:IsShown(), "levels: the chart")
  T.eq(tp.layout.n, 0, "levels: no table column")
  for c = 1, #tp.headerCells do T.no(tp.headerCells[c]:IsShown(), "levels: header cell " .. c .. " hidden") end
  local lines = BarTip(10)
  for _, key in ipairs({ "BD_AFK", "BD_INN", "BD_CITY", "BD_DUNGEON", "BD_RAID", "BD_DEAD", "TT_PROF" }) do
    T.eq(Find(lines, L[key]), nil, "no " .. key .. " part yet")
  end
  T.ok(Find(lines, L.BD_WORLD) ~= nil, "the world part")
  -- AFK, inn and city time appear: their parts, in their place
  Stub.SetAFK(true); Stub.Advance(120); Stub.SetAFK(false)
  Stub.SetResting(true); Stub.Advance(60); Stub.SetResting(false)
  Stub.SetMap(1454); Stub.Advance(60); Stub.SetMap(1411)
  Stub.Die(); Stub.Advance(30); Stub.Resurrect(false)
  Stub.OpenTradeSkill(); Stub.Advance(60); Stub.CloseTradeSkill()
  Stub.Advance(1)
  ns.Window.Refresh()
  T.eq(tp.layout.n, 0, "levels: still no table column")
  lines = BarTip(10)
  local at = {}
  for i, l in ipairs(lines) do at[l[1]] = i end
  for _, key in ipairs({ "TT_PROF", "BD_DEAD", "BD_CITY", "BD_INN", "BD_AFK" }) do T.ok(at[L[key]] ~= nil, key .. " part") end
  T.ok(at[L.BD_WORLD] < at[L.TT_PROF] and at[L.TT_PROF] < at[L.BD_DEAD] and at[L.BD_DEAD] < at[L.BD_CITY]
    and at[L.BD_CITY] < at[L.BD_INN] and at[L.BD_INN] < at[L.BD_AFK], "the chart's fixed order")
  T.no(at[L.BD_DUNGEON] or at[L.BD_RAID], "still no instance")
  -- sessions and zones follow the same rule
  ns.Window.Toggle("sessions")
  local pos = tp.layout.pos
  T.ok(pos.dead and pos.prof and pos.afk, "sessions: dead, professions, AFK")
  T.eq(pos.inst, nil, "sessions: no instance column")
  CheckGeometry(tp, "sessions")
  ns.Window.Toggle("zones")
  CheckGeometry(tp, "zones")
  T.eq(Stub.onUpdateCount, 0)
end)

-- Levels tab rework: the rows "L » L+1" became the bars of the chart. The bar tooltip title
-- names the step (L.LEVEL_SPAN_FMT), its Reached line is the date the next level was
-- reached (in progress for the current one); the former Total column is the strip legend
-- "Levels 1 to N" (the time from level 1 to the end of the last complete level) and the
-- Played chip (to now, live). The account rows keep the "L » L+1" labels.
T.test("window: level bars read 'Level L » L+1', Reached = the next level, Total = time from level 1", function()
  local ns = Login()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  Stub.Advance(600)
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)      -- 10 -> 11
  Stub.Advance(900)
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)      -- 11 -> 12
  Stub.Advance(300)
  ns.Window.Show("levels")
  local tp, ch = TP(), Chart()
  T.ok(ch ~= nil and ch.root:IsShown(), "the chart")
  T.eq(ch.state.level, 12)
  local cur, t11, t10 = BarTip(12), BarTip(11), BarTip(10)
  T.eq(cur[1][1], format(L.LEVEL_SPAN_FMT, 12, 13), "the level in progress")
  T.eq(t11[1][1], format(L.LEVEL_SPAN_FMT, 11, 12))
  T.eq(t10[1][1], format(L.LEVEL_SPAN_FMT, 10, 11))
  T.eq(Right(cur, L.COL_REACHED), L.ROW_IN_PROGRESS)
  local levels = ns.char.levels
  T.eq(Right(t11, L.COL_REACHED), Fmt.DateTime(levels[12].t0), "11 » 12: when 12 was reached")
  T.eq(Right(t10, L.COL_REACHED), Fmt.DateTime(levels[11].t0))
  T.ok(levels[11].t0 ~= levels[10].t0, "not the date level 10 began")
  T.eq(Right(t11, L.LV_PLAYED), Fmt.DurationFull(Stats.Sum(levels[11], 0)), "the bar: the level's own time")
  -- Total: from level 1 to the end of the last complete level; the Played chip runs to now
  local sync = ns.Tracker.GetSync()
  local now = GetTime()
  T.eq(ch.strip.fs1:GetText(), format(L.LV_DONE_SPAN_FMT, 1, 12, Fmt.DurationFull(Stats.CumulativeTime(ns.char, 11, 0, sync, now))))
  local played = Stats.Played(ns.char, 0, sync, now)
  T.eq(ch.chips[1].value:GetText(), Fmt.DurationFull(played))
  T.eq(Stats.CumulativeTime(ns.char, 11, 0, sync, now) - Stats.CumulativeTime(ns.char, 10, 0, sync, now),
    Stats.Sum(levels[11], 0), "consecutive totals differ by the level's time")
  -- live: the Played chip follows the played time
  Stub.Advance(240)
  T.eq(ch.chips[1].value:GetText(), Fmt.DurationFull(Stats.Played(ns.char, 0, ns.Tracker.GetSync(), GetTime())))
  -- the account view uses the same labels
  ns.Window.SetView("account")
  T.ok(RowWith(tp, Span(11)) ~= nil, "account rows: 11 » 12 (complete levels)")
  T.eq(Stub.onUpdateCount, 0)
end)

-- Levels tab rework: the Levels table and its Est. column are gone; the estimate made when
-- the level began (row.eta) is the "Estimated at start" figure card of the detail sheet
-- (LevelDetail, spec section 5.2), right below the Played card in the cards' 2 x 3 grid (the
-- column sat right of the time). The level in progress shows its projection there ("Level
-- estimate", the time left below), so the level is completed first (one more level-up).
T.test("window: the Est. card sits next to the time it took", function()
  local ns = Login()
  local L, Fmt = ns.L, ns.Fmt
  for _ = 1, 12 do Stub.Advance(60); Stub.Kill(200) end
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)
  Stub.Advance(2)
  for _ = 1, 3 do Stub.Advance(60); Stub.Kill(200) end
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)
  Stub.Advance(2)
  T.eq(Stub.player.level, 12)
  ns.Window.Show("levels")
  local tp = TP()
  local hit = Chart().cols[11].hit
  hit:GetScript("OnClick")(hit, "LeftButton")
  local cards = tp.detail.cards
  local _, _, _, px, py = cards.played.frame:GetPoint(1)
  local _, _, _, ex, ey = cards.eta.frame:GetPoint(1)
  T.eq(ex, px, "the Played card's column")
  T.eq(py - ey, cards.played.frame:GetHeight() + 8, "right below it")
  T.eq(cards.eta.label:GetText(), L.LD_ETA)
  T.ok(ns.char.levels[11].eta ~= nil)
  T.eq(tp.detail.eta:GetText(), Fmt.Duration(ns.char.levels[11].eta))
  T.eq(cards.played.value:GetText(), Fmt.DurationFull(ns.Stats.Sum(ns.char.levels[11], 0)), "the time it took")
end)

---------------------------------------------------------------------------
-- Dates
---------------------------------------------------------------------------

-- Levels tab rework: the Reached date of a level is in its bar tooltip and in the status
-- line of its detail sheet ("Completed on <date>"); both follow the settings, the sheet
-- refreshed while shown. The Sessions part is unchanged.
T.test("window: dates follow window.dateFmt and window.clock (Reached and Sessions)", function()
  local ns = Login()
  local L = ns.L
  Stub.Advance(300)
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)
  Stub.Advance(60)
  ns.Window.Show("levels")
  local tp = TP()
  T.match(Right(BarTip(10), L.COL_REACHED), "^%d%d/%d%d/%d%d%d%d %d?%d:%d%d [AP]M$", "enUS auto: 12-hour clock")
  local hit = Chart().cols[10].hit
  hit:GetScript("OnClick")(hit, "LeftButton")
  T.eq(tp.detail.status:GetText(), format(L.LD_DONE_FMT, ns.Fmt.DateTime(ns.char.levels[11].t0)), "detail: completed on")
  T.match(tp.detail.status:GetText(), "%d%d/%d%d/%d%d%d%d %d?%d:%d%d [AP]M$")
  ns.Core.SetSetting("window.dateFmt", "ymd")
  ns.Core.SetSetting("window.clock", "24")
  T.match(Right(BarTip(10), L.COL_REACHED), "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$", "the next hover: the new format")
  T.match(tp.detail.status:GetText(), "%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$", "detail refreshed while shown")
  ns.Window.Toggle("sessions")
  T.match(Cell(tp, tp.rows[1], "date"), "^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$", "sessions dates too")
  ns.Core.SetSetting("window.dateFmt", "dmy")
  ns.Core.SetSetting("window.clock", "12")
  T.match(Cell(tp, tp.rows[1], "date"), "^%d%d/%d%d/%d%d%d%d %d?%d:%d%d [AP]M$")
  T.eq(Cell(tp, tp.rows[1], "date"), ns.Fmt.DateTime(ns.char.cur.t0))
end)

T.test("settings: window size, date format and clock: defaults, repair, sparse save", function()
  _G.TruePlayedDB = { schema = 1, sparseSettings = true, chars = {},
    settings = { window = { width = 99999, height = "tall", dateFmt = "dd.mm", clock = 24 } } }
  local ns = Login()
  local w = ns.settings.window
  T.eq(ns.C.DEFAULTS.window, { width = 700, height = 440, dateFmt = "auto", clock = "auto" })
  T.eq(w.width, 1800, "clamped")
  T.eq(w.height, 440, "wrong type: the default")
  T.eq(w.dateFmt, "auto", "unknown format: the default")
  T.eq(w.clock, "auto", "a number is not a clock")
  local Core = ns.Core
  T.no(Core.SetSetting("window.dateFmt", "dd.mm"), "refused")
  T.ok(Core.SetSetting("window.dateFmt", "ymd"))
  T.ok(Core.SetSetting("window.clock", "12"))
  T.ok(Core.SetSetting("window.width", 950))
  T.ok(Core.SetSetting("window.height", 120))
  T.eq(w.height, 300, "clamped to the minimum")
  Core.SetSetting("window.height", 440)
  Stub.Logout()
  T.eq(Stub.saved.settings.window, { width = 950, dateFmt = "ymd", clock = "12" }, "only what differs")
end)

---------------------------------------------------------------------------
-- Size
---------------------------------------------------------------------------

-- Levels tab rework: the table checks of this test run in the Zones tab (its zone column
-- takes the extra room as the Levels main zone column did); the chart is never smaller than
-- its minimum (LevelChart.MinSize, 1040 x 640) while the saved size stays the player's.
T.test("window: resized with the grip, size saved, never narrower than its columns", function()
  local ns = Login()
  Stub.Advance(120)
  ns.Window.Show("zones")
  local f, tp = Frame(), TP()
  local need = tp.layout.need + 50
  T.eq(f:GetWidth(), math.max(700, need))
  T.eq(f:GetHeight(), 440)
  local grip = tp.grip
  T.ok(grip ~= nil and grip:IsShown(), "resize grip")
  f:SetSize(1000, 600)                                  -- what the client does while sizing
  grip:GetScript("OnMouseUp")(grip, "LeftButton")
  T.eq({ ns.settings.window.width, ns.settings.window.height }, { 1000, 600 }, "saved")
  T.eq(f:GetWidth(), 1000)
  T.eq(f:GetHeight(), 600)
  local zone = tp.layout.cols[tp.layout.pos.zone]
  T.eq(zone.cw, zone.w + 950 - tp.layout.need, "the zone column takes the extra room")
  CheckGeometry(tp, "wide")
  -- narrower than the columns: the window keeps the width they need
  f:SetSize(400, 100)
  grip:GetScript("OnMouseUp")(grip, "LeftButton")
  T.eq(ns.settings.window.width, 700, "clamped")
  T.eq(ns.settings.window.height, 300)
  T.eq(f:GetWidth(), math.max(700, need))
  T.eq(f:GetHeight(), 300)
  CheckGeometry(tp, "narrow")
  -- the chart: its minimum size, the saved one unchanged
  ns.Window.Toggle("levels")
  T.eq({ ns.LevelChart.MinSize() }, { 1040, 640 })
  T.eq({ f:GetWidth(), f:GetHeight() }, { 1040, 640 }, "the chart's minimum")
  T.eq({ ns.settings.window.width, ns.settings.window.height }, { 700, 300 }, "the setting unchanged")
  f:SetSize(1100, 700)
  grip:GetScript("OnMouseUp")(grip, "LeftButton")
  T.eq({ ns.settings.window.width, ns.settings.window.height }, { 1100, 700 }, "saved from the chart")
  T.eq({ f:GetWidth(), f:GetHeight() }, { 1100, 700 })
  T.eq(Chart().root:GetWidth(), 1100 - 28, "the chart follows the window")
  f:SetSize(400, 100)
  grip:GetScript("OnMouseUp")(grip, "LeftButton")
  T.eq({ ns.settings.window.width, ns.settings.window.height }, { 700, 300 }, "clamped by the settings")
  T.eq({ f:GetWidth(), f:GetHeight() }, { 1040, 640 }, "never smaller than the chart")
  ns.Window.Toggle("zones")
  T.eq({ f:GetWidth(), f:GetHeight() }, { math.max(700, need), 300 }, "the other tabs: the saved size")
  -- the size is kept for the next show
  ns.Core.SetSetting("window.width", 900)
  ns.Window.Hide()
  ns.Window.Show("zones")
  T.eq(f:GetWidth(), 900)
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Zones: capitals
---------------------------------------------------------------------------

T.test("zones: the capitals Time column is the capital's time under the exclusions", function()
  local ns = Login()
  local Fmt = ns.Fmt
  Stub.SetMap(1454)
  Stub.Advance(600)                                     -- city
  Stub.SetAFK(true); Stub.Advance(120); Stub.SetAFK(false)
  Stub.OpenTradeSkill(); Stub.Advance(300); Stub.CloseTradeSkill()   -- crafting in the capital
  Stub.SetMap(1411); Stub.Advance(60)
  ns.Window.Show("zones")
  local tp = TP()
  local cap = RowWith(tp, "Orgrimmar")
  local total = 600 + 120 + 300
  T.eq(Cell(tp, cap, "time"), Fmt.Duration(total), "nothing excluded: all its time")
  T.eq(Cell(tp, cap, "raw"), Fmt.Duration(total))
  T.eq(Cell(tp, cap, "afk"), Fmt.Duration(120))
  ns.Core.SetSetting("exclude.city", true)
  cap = RowWith(tp, "Orgrimmar")
  T.eq(Cell(tp, cap, "time"), Fmt.Duration(300), "city excluded: the professions time is left")
  T.eq(Cell(tp, cap, "raw"), Fmt.Duration(total))
  -- the same value as its row in the zone list
  local listed = RowWith(tp, "Orgrimmar " .. ns.L.CITY_MARK)
  T.eq(Cell(tp, listed, "time"), Cell(tp, cap, "time"))
  ns.Core.SetSetting("exclude.city", false)
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(Cell(tp, RowWith(tp, "Orgrimmar"), "time"), Fmt.Duration(600 + 300), "AFK excluded")
end)

---------------------------------------------------------------------------
-- Column help: a "?" icon after every header, its tooltip on hover
---------------------------------------------------------------------------

-- Zones and Sessions cells: the Sessions' Duration column (CellDur) keeps a duration's
-- minutes up to a day ("10h 23m"), from a day up without them (Fmt.Duration: "2d 03h"),
-- as "12 d 23 h 59 min" would not fit it in the languages with long units; the session in
-- progress is a live cell. The other cells (the Zones tab, the Sessions' AFK / Inst. /
-- Dead / Prof.) keep Fmt.Duration: no live step refreshes them, so minutes past 10 h would
-- fall behind the current zone's or session's growing times (review of 17/10/2026).
T.test("zones and sessions: the Duration column keeps the minutes up to a day, the other cells Fmt.Duration", function()
  local ns = Login()
  local Fmt = ns.Fmt
  local char = ns.char
  local long = 2 * 86400 + 3 * 3600 + 5 * 60
  char.zones[1413] = { name = "The Barrens", s = { w = 37380 }, xp = 0 }
  char.zones[1446] = { name = "Tanaris", s = { w = long }, xp = 0 }
  local t = 1789000000
  char.sessions = {
    { t0 = t, t1 = t + 37380, l0 = 5, l1 = 6, s = { w = 37380, W = 37380 }, xp = 1000, d = 0 },
    { t0 = t + 86400, t1 = t + 86400 + long, l0 = 6, l1 = 7, s = { w = long }, xp = 1000, d = 0 },
  }
  ns.Window.Show("zones")
  local tp = TP()
  local barrens, tanaris = RowWith(tp, "The Barrens"), RowWith(tp, "Tanaris")
  T.ok(barrens and tanaris, "the zone rows")
  T.eq(Cell(tp, barrens, "time"), Fmt.Duration(37380), "a zone past 10 h: without the minutes")
  T.eq(Cell(tp, barrens, "time"), "10h")
  T.eq(Cell(tp, tanaris, "time"), "2d 03h", "a day and more: days and hours")
  ns.Window.Show("sessions")
  local s1, s2 = RowWith(tp, Fmt.DateTime(t)), RowWith(tp, Fmt.DateTime(t + 86400))
  T.ok(s1 and s2, "the session rows")
  T.eq(Cell(tp, s1, "dur"), "20h 46m", "a session under a day (AFK included): to the minute")
  T.eq(Cell(tp, s2, "dur"), "2d 03h", "a day and more: without the minutes")
  T.eq(Cell(tp, s1, "afk"), "10h", "its AFK column: Fmt.Duration")
  ns.Window.Hide()
end)

-- The cells that grow while the window shows them, without an XP gain (no rebuild): the
-- session in progress's Duration is live to the minute; the current zone's cell keeps
-- Fmt.Duration, so it never shows a minute that is behind.
T.test("zones and sessions: the session in progress live to the minute; the current zone never behind", function()
  local ns = Login()
  local Fmt, Stats = ns.Fmt, ns.Stats
  local char = ns.char
  local cur = char.cur
  T.ok(type(cur) == "table" and cur == ns.session, "the fixture: the session in progress")
  cur.s.w = (cur.s.w or 0) + 37380
  local zk = ns.Tokens.ctx.zoneKey
  local z = char.zones[zk]
  T.ok(type(z) == "table", "the fixture: the current zone")
  z.s.w = (z.s.w or 0) + 37380
  ns.Window.Show("sessions")
  local tp = TP()
  local row = RowWith(tp, Fmt.DateTime(cur.t0))
  T.ok(row ~= nil, "the session in progress's row")
  local function Now() return Stats.SessionTime(cur, ns.GetMask()) end
  T.eq(Cell(tp, row, "dur"), Fmt.DurationFull(Now()), "at Show")
  Stub.Advance(600)
  T.eq(Cell(tp, row, "dur"), Fmt.DurationFull(Now()), "600 s later, without an XP gain")
  T.ok(Now() >= 36000, "the fixture: past 10 h (" .. Now() .. ")")
  ns.Window.Show("zones")
  local name = z.name or Stats.ZoneName(zk, z)
  local zr = RowWith(tp, name)
  T.ok(zr ~= nil, "the current zone's row")
  local before = Cell(tp, zr, "time")
  T.eq(before, Fmt.Duration(Stats.Sum(z, ns.GetMask())), "at Show: Fmt.Duration")
  T.ok(not before:find("m", 1, true), "past 10 h: no minute shown (" .. before .. ")")
  Stub.Advance(600)
  T.eq(Cell(tp, zr, "time"), before, "600 s later: not rebuilt, and still true to the hour")
  T.eq(before, Fmt.Duration(Stats.Sum(z, ns.GetMask())))
  ns.Window.Hide()
end)

-- The footer of the account view follows the current character's growing time to the
-- minute (Stats.Account: every record's life), as the character view's does: a live
-- step, without an XP gain; its text set only when a minute changed.
T.test("window: the account view's footer is live to the minute (no XP gain), set only on a change", function()
  local ns = Login()
  local Fmt, Stats = ns.Fmt, ns.Stats
  ns.char.life.s.w = (ns.char.life.s.w or 0) + 40000
  ns.Window.Show("levels", "account")
  local tp = TP()
  local f1 = tp.footer1
  local function Expect(what)
    local total = Stats.Account(ns.db, ns.GetMask())
    local text = f1:GetText()
    T.ok(text:find(ns.L.SEP .. Fmt.DurationFull(total), 1, true) ~= nil, what .. ": " .. text .. " for "
      .. Fmt.DurationFull(total))
  end
  Expect("at Show")
  local sets = 0
  local orig = f1.SetText
  rawset(f1, "SetText", function(self, text) sets = sets + 1 return orig(self, text) end)
  Stub.Advance(600)
  Expect("600 s later")
  T.ok(sets >= 9 and sets <= 11, "set once a minute (" .. sets .. " in 600 s)")
  rawset(f1, "SetText", nil)
  ns.Window.Hide()
end)

local function VColor(t) local r, g, b = t:GetVertexColor() return { r, g, b } end
local function C3(c) return { c[1], c[2], c[3] } end

-- Every visible header of the shown layout: the cell covers the column and takes the
-- mouse, the text leaves room for the icon, the icon follows the text inside the column
-- (stub GetStringWidth: 6 px a character), tinted ui.dim; hovering shows the column name
-- and its own tip, tints the icon ui.accent, leaving hides the tooltip. Returns the number
-- of headers checked.
local function CheckHelp(ns, tp, what)
  local L = ns.L
  local ui = ns.Themes.Active().ui
  local lay, room = tp.layout, tp.iconRoom
  for c = 1, lay.n do
    local col = lay.cols[c]
    local fs, cell, icon = tp.header[c], tp.headerCells[c], tp.headerIcons[c]
    local where = what .. " " .. col.id
    T.ok(cell:IsShown() and cell:IsMouseEnabled(), where .. ": mouse cell shown")
    local p = rawget(cell, "_points")[1]
    T.eq({ p.point, p.relPoint, p.x }, { "BOTTOMLEFT", "TOPLEFT", col.x }, where .. ": cell at the column")
    T.eq(cell:GetWidth(), col.cw, where .. ": cell as wide as the column")
    T.eq(fs:GetWidth(), col.cw - room, where .. ": the text leaves room for the icon")
    T.eq(fs:GetText(), L[col.key])
    T.match(icon:GetTexture(), "\\Media\\Themes\\common\\help%.tga$", where .. ": the addon's icon")
    T.ok(icon:IsVisible(), where .. ": icon visible")
    local ip = rawget(icon, "_points")[1]
    T.ok(ip.rel == fs and ip.point == "LEFT" and ip.relPoint == "LEFT", where .. ": icon after the text")
    T.eq(ip.x, math.min(6 * #L[col.key], col.cw - room) + 2, where .. ": right after the text")
    T.ok(ip.x + icon:GetWidth() <= col.cw, where .. ": icon inside its column")
    T.eq(VColor(icon), C3(ui.dim), where .. ": icon in the theme's dim colour")
    cell:GetScript("OnEnter")(cell)
    T.ok(GameTooltip:GetOwner() == cell and GameTooltip:IsShown(), where .. ": tooltip shown")
    local lines = GameTooltip._lines
    T.eq(#lines, 2, where .. ": title and explanation")
    T.eq(lines[1][1], L[col.key], where .. ": title = column name")
    T.eq(lines[2][1], L[col.tip], where .. ": explanation")
    T.ok(type(L[col.tip]) == "string" and L[col.tip] ~= col.tip, where .. ": tip text exists")
    T.eq(VColor(icon), C3(ui.accent), where .. ": hovered icon in the accent colour")
    cell:GetScript("OnLeave")(cell)
    T.no(GameTooltip:IsShown(), where .. ": hidden on leave")
    T.eq(VColor(icon), C3(ui.dim), where .. ": back to dim")
  end
  for c = lay.n + 1, #tp.headerCells do T.no(tp.headerCells[c]:IsShown(), what .. ": unused cell " .. c .. " hidden") end
  return lay.n
end

T.test("window: every column header has a help icon and a tooltip saying what the column holds", function()
  local ns = Login()
  -- every optional column of the Levels and Sessions tabs but the instances
  for _ = 1, 12 do Stub.Advance(60); Stub.Kill(200) end
  Stub.SetAFK(true); Stub.Advance(120); Stub.SetAFK(false)
  Stub.SetResting(true); Stub.Advance(60); Stub.SetResting(false)
  Stub.SetMap(1454); Stub.Advance(60); Stub.SetMap(1411)
  Stub.Die(); Stub.Advance(30); Stub.Resurrect(false)
  Stub.OpenTradeSkill(); Stub.Advance(60); Stub.CloseTradeSkill()
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)
  for _ = 1, 8 do Stub.Advance(60); Stub.Kill(200) end    -- a complete level: account XP/h
  Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)
  Stub.Advance(2)
  ns.Window.Show("levels")
  local tp = TP()
  -- Levels tab rework: the chart has no column header, so no help icon (every cell hidden)
  T.eq(CheckHelp(ns, tp, "levels (the chart)"), 0)
  ns.Window.Toggle("zones")
  CheckHelp(ns, tp, "zones")
  ns.Window.Toggle("sessions")
  local n = CheckHelp(ns, tp, "sessions")
  T.ok(n >= 8, "sessions: most columns shown (" .. n .. ")")
  local seen = {}
  for _, id in ipairs(Ids(tp)) do seen[id] = true end
  for _, id in ipairs({ "xp", "xph", "afk", "dead", "prof" }) do T.ok(seen[id], "sessions: " .. id .. " shown") end
  ns.Window.SetView("account")
  CheckHelp(ns, tp, "account sessions (no column)")
  ns.Window.Toggle("levels")
  CheckHelp(ns, tp, "account levels")
  -- the same column in another tab explains its own content
  local function TipOf(id)
    local col = tp.layout.cols[tp.layout.pos[id]]
    return col.tip
  end
  T.eq(TipOf("xph"), "COL_XPH_ACCOUNT_TIP")
  ns.Window.SetView("current")                          -- the chart: the Levels table tips went with it
  T.eq(tp.layout.n, 0)
  ns.Window.Toggle("zones")
  T.eq(TipOf("time"), "COL_TIME_ZONES_TIP")
  ns.Window.Toggle("sessions")
  T.eq(TipOf("xph"), "COL_XPH_SESSIONS_TIP")
  T.eq(TipOf("xp"), "COL_XP_SESSIONS_TIP")
  T.eq(Stub.onUpdateCount, 0)
end)

-- Levels tab rework: the header hovered while the tab changes starts in the Sessions tab;
-- the column that goes away is the last Sessions one when the chart (no column) is shown;
-- the row tooltip that a header leave must not hide is the bar tooltip of the chart.
T.test("window: a hovered header follows its column, its tooltip goes with the column or the window", function()
  local ns = Login()
  local L = ns.L
  Stub.Advance(120)
  ns.Window.Show("sessions")
  local tp = TP()
  -- the second header hovered while the tab changes: the new column's tooltip
  local cell = tp.headerCells[2]
  cell:GetScript("OnEnter")(cell)
  T.eq(GameTooltip._lines[1][1], L.COL_DURATION)
  ns.Window.Toggle("zones")
  T.ok(GameTooltip:GetOwner() == cell and GameTooltip:IsShown(), "still the owner")
  T.eq(GameTooltip._lines[1][1], L.COL_TIME)
  T.eq(GameTooltip._lines[2][1], L.COL_TIME_ZONES_TIP, "the zones tab's own explanation")
  cell:GetScript("OnLeave")(cell)
  -- the last header hovered when its column goes away: tooltip hidden, icon back to dim
  ns.Window.Toggle("sessions")
  local n = tp.layout.n
  cell = tp.headerCells[n]
  cell:GetScript("OnEnter")(cell)
  T.eq(GameTooltip._lines[1][1], L[tp.layout.cols[n].key])
  ns.Window.Toggle("levels")
  T.ok(tp.layout.n < n, "fewer columns (the chart: none)")
  T.no(cell:IsShown(), "cell hidden")
  T.no(GameTooltip:IsShown(), "its tooltip hidden")
  T.eq(VColor(tp.headerIcons[n]), C3(ns.Themes.Active().ui.dim))
  -- hovered when the window closes
  ns.Window.Toggle("sessions")
  cell = tp.headerCells[1]
  cell:GetScript("OnEnter")(cell)
  ns.Window.Hide()
  T.no(GameTooltip:IsShown(), "hidden with the window")
  -- a bar tooltip is not taken for a header one (and the other way round)
  ns.Window.Show("levels")
  local hit = Chart().cols[10].hit
  hit:GetScript("OnEnter")(hit)
  T.eq(GameTooltip._lines[1][1], format(L.LEVEL_SPAN_FMT, 10, 11))
  cell:GetScript("OnLeave")(cell)
  T.ok(GameTooltip:IsShown() and GameTooltip:GetOwner() == hit, "leaving a header keeps a bar's tooltip")
  hit:GetScript("OnLeave")(hit)
  T.no(GameTooltip:IsShown(), "the bar's leave hides it")
end)

-- Levels tab rework: shown on the Zones tab (the chart has no header).
T.test("window: the help icons follow the theme; nothing is created again", function()
  local ns = Login()
  Stub.Advance(120)
  ns.Window.Show("zones")
  local tp = TP()
  local Themes = ns.Themes
  local count = #tp.headerIcons
  for _, key in ipairs({ "futuriste", "druid", "actuel" }) do
    ns.Core.SetSetting("theme", key)
    local ui = Themes.Active().ui
    for c = 1, tp.layout.n do
      T.eq(VColor(tp.headerIcons[c]), C3(ui.dim), key .. ": icon " .. c)
      T.eq({ tp.header[c]:GetTextColor() }, C3(ui.label), key .. ": header " .. c)
    end
    local cell = tp.headerCells[1]
    cell:GetScript("OnEnter")(cell)
    T.eq(VColor(tp.headerIcons[1]), C3(ui.accent), key .. ": hovered")
    cell:GetScript("OnLeave")(cell)
  end
  -- a theme switch while a header is hovered keeps it highlighted
  local cell = tp.headerCells[2]
  cell:GetScript("OnEnter")(cell)
  ns.Core.SetSetting("theme", "futuriste")
  T.eq(VColor(tp.headerIcons[2]), C3(Themes.Active().ui.accent))
  T.eq(VColor(tp.headerIcons[1]), C3(Themes.Active().ui.dim))
  cell:GetScript("OnLeave")(cell)
  T.eq(#tp.headerIcons, count, "no icon created by the theme switches")
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

for _, case in ipairs({ { "enUS", false }, { "frFR", true } }) do
  local code, is24 = case[1], case[2]
  T.test("options: statistics window section, date format examples and the 24-hour clock (" .. code .. ")", function()
    Stub.locale = code
    local ns = Login()
    local L = ns.L
    ns.Options.Open()
    local panel = Stub.ui.categories[1].frame
    local controls = panel.controls
    local dd = controls["window.dateFmt"]
    T.ok(dd ~= nil, "date format dropdown")
    local labels = {}
    for i, ch in ipairs(dd.choices) do labels[i] = ch.label end
    T.eq(labels[2], "31/12/2026")
    T.eq(labels[3], "12/31/2026")
    T.eq(labels[4], "2026-12-31")
    T.eq(labels[1], format(L.DATE_AUTO_FMT, os.date(L.DATE_FMT, 1798718400)))
    local clock = controls["window.clock"]
    T.ok(clock ~= nil, "clock checkbox")
    T.eq(clock.label:GetText(), L.OPT_CLOCK24)
    T.eq(clock.widget:GetChecked() and true or false, is24, "auto: the language's clock")
    clock.widget:GetScript("OnClick")(clock.widget)
    T.eq(ns.settings.window.clock, is24 and "12" or "24", "a click chooses the other clock")
    T.eq(clock.widget:GetChecked() and true or false, not is24)
    clock.widget:GetScript("OnClick")(clock.widget)
    T.eq(ns.settings.window.clock, is24 and "24" or "12")
    T.eq(Stub.errors, {})
  end)
end
