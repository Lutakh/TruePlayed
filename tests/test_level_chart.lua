-- tests/test_level_chart.lua - the Levels tab of a character (LevelChart.lua, the detail
-- sheet's header (LevelDetail.lua: its sections are tests/test_level_detail.lua's), their
-- Window.lua integration): one stacked bar per level whose pixel
-- stack equals the bar height, the parts in their fixed order, the filters (parts, scale,
-- title, summary), the average line, the ghosts of the upcoming levels and the
-- hide-upcoming toggle, the no-record stub, the selection and the detail sheet, the bar and
-- PvP chip tooltips, the chips (a sub line too wide: its compact form), the progress
-- strip, the live growth (SetHeight only, no SetPoint, no allocation over 600 ticks,
-- nothing created again), another character, the account view, max level and server
-- cap, Classic Era (world PvP not measured), the themes (P5, a recolour does nothing),
-- the window's minimum size, and an ASCII golden of a small fixed data set. The review
-- fixes: the grip saves only what the user changed, a 4:3 / 5:4 screen, the scale in days
-- beyond 10 days, the PvP / Flight / Deaths chips live, "<1%", the filter's own line in the
-- bar tooltip, one flight label, an empty summary, a level-1 character, XP disabled, another
-- character at a server cap, a partial projection ("+"), another character without w0, the
-- selection on a character switch, the current level's untracked excess. GetStringWidth is
-- bounded by the width set, as in the client (stub_ui boundedText).
local Stub, T = ...

local format, floor = string.format, math.floor

local T0 = 1700000000
local BG1, BG2 = "i489", "i529"

---------------------------------------------------------------------------
-- Fixture
---------------------------------------------------------------------------

-- Level records: none for 1 and 2 (before the install), 3 partial, 4 rebuilt after a crash,
-- 5 .. level - 1 played with every kind of time (world PvP from 16, battlegrounds from 15).
local function LevelRec(l)
  if l <= 2 then return nil end
  if l == 3 then return { partial = true, s = { u = 1500, w = 300 }, d = 0, xp = 0, t1 = T0 + 4 * 3600 } end
  if l == 4 then return { rec = true, s = { w = 2400 }, d = 0, xp = 0, t0 = T0 + 4 * 3600, t1 = T0 + 5 * 3600 } end
  local s = { w = 1500 + 100 * l, W = 200, c = 200, i = 150, t = 300 }
  if l % 3 == 0 then s.d = 1200 end
  if l == 12 then s.r = 900 end
  if l % 4 == 0 then s.f = 400 end
  if l % 5 == 0 then s.x = 240 end
  local z = { [1411] = { s = { w = s.w, W = 200, t = 300 } } }
  if l >= 15 then
    s.p = 600
    z[BG1] = { name = "Warsong Gulch", s = { p = 400 } }
    z[BG2] = { name = "Arathi Basin", s = { p = 200 } }
  end
  return { s = s, pw = (l >= 16) and 120 or nil, d = (l % 5 == 0) and 2 or 0, xp = 0, t0 = T0 + l * 3600,
           t1 = T0 + (l + 1) * 3600 - 1, z = z }
end

local function AddInto(dst, src)
  for k, v in pairs(src) do dst[k] = (dst[k] or 0) + v end
end

-- Writes the records of levels 1 .. level - 1, their life totals (taken from the time the
-- first /played put before the install: the life total stays the server's), the life's
-- battlegrounds (300 s of pruned zones: "Other battlegrounds") and the start of world PvP
-- measuring.
local function Seed(ns, level)
  local char = ns.char
  local life = char.life
  life.s = life.s or {}
  local seeded = 300
  for l = 1, level - 1 do
    local r = LevelRec(l)
    char.levels[l] = r
    if r then
      AddInto(life.s, r.s)
      for _, v in pairs(r.s) do seeded = seeded + v end
      life.d = (life.d or 0) + r.d
      if r.pw then life.pw = (life.pw or 0) + r.pw end
    end
  end
  life.s.p = (life.s.p or 0) + 300
  life.s.u = math.max(0, (life.s.u or 0) - seeded)
  char.zones = char.zones or {}
  char.zones[BG1] = { name = "Warsong Gulch", s = { p = 2000 } }
  char.zones[BG2] = { name = "Arathi Basin", s = { p = 1000 } }
  char.pvp = char.pvp or {}
  char.pvp.w0 = T0 + floor(15.5 * 3600)
end

-- A level-20 character (40000 s at level 20 on the server, 400000 s in all) after login;
-- GetStringWidth bounded by an explicit width, as in the client (stub_ui boundedText).
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false, boundedText = true })
  Stub.theme = opts.theme or "actuel"
  if opts.locale then Stub.locale = opts.locale end
  local p = Stub.player
  p.level = opts.level or 20
  p.xp = opts.xp or 9000
  p.max = Stub.xpTable[p.level] or 23200
  if opts.top then p.maxLevel, p.expMaxLevel = opts.top, opts.top end
  if opts.xpOff then p.xpDisabled = true end
  Stub.server.total = opts.total or 400000
  Stub.server.levelPlayed = opts.levelPlayed or 40000
  if opts.pvp then Stub.SetPvpAPI(opts.pvp) end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  ns.Core.SetSetting("widget.locked", true)
  Stub.Advance(10)                   -- the first /played answer (live sync)
  if opts.seed ~= false then Seed(ns, p.level) end
  return ns
end

local function Frame()
  return rawget(_G, "TruePlayedStatsFrame")
end

local function Chart()
  local f = Frame()
  return f and f.tp.chart
end

local function Shown(r)
  return r ~= nil and r:IsShown() and true or false
end

local function Text(fs)
  return rawget(fs, "_text")
end

local function Height(r)
  return rawget(r, "_height") or 0
end

-- The visible segments of column c, bottom-up: { { part index, height } ... }.
local function Stack(c)
  local out = {}
  for i = 1, 12 do
    local t = c.seg[i]
    if t and t:IsShown() and Height(t) > 0 then out[#out + 1] = { i, Height(t) } end
  end
  return out
end

-- GameTooltip lines as { left, right } (the native theme's target).
local function TipLines()
  local out = {}
  for i, l in ipairs(GameTooltip._lines or {}) do out[i] = { l[1], l[2] } end
  return out
end

local function Line(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i] end
  end
  return nil
end

local function HasText(lines, text)
  for i = 1, #lines do
    if lines[i][1] == text or lines[i][2] == text then return true end
  end
  return false
end

local function Under(o, root)
  local p = rawget(o, "_parent")
  for _ = 1, 60 do
    if p == nil then return false end
    if p == root then return true end
    p = rawget(p, "_parent")
  end
  return false
end

-- Counts the SetPoint calls of the regions under `root` while fn runs (test_graph.lua's
-- method; the bar and the rest of the window are not counted).
local function CountSetPoint(root, fn)
  local mt = getmetatable(UIParent).__index
  local orig = rawget(mt, "SetPoint")
  local n = 0
  rawset(mt, "SetPoint", function(self, ...)
    if self == root or Under(self, root) then n = n + 1 end
    return orig(self, ...)
  end)
  local ok, err = pcall(fn)
  rawset(mt, "SetPoint", orig)
  if not ok then error(err, 0) end
  return n
end

local function Created()
  local n = 0
  for _, v in pairs(Stub.created) do n = n + v end
  return n
end

local function Detail()
  return Frame().tp.detail
end

-- Another character: a copy of this one's records at `level` (none above), no live data.
local function Alt(ns, level)
  local rec = Stub.DeepCopy(ns.char)
  rec.guid, rec.name, rec.level = "Player-4619-0BADF00D", "Other", level
  for l = level + 1, 60 do rec.levels[l] = nil end
  ns.db.chars[rec.guid] = rec
  return rec
end

-- Counts the chart's full rebuilds while fn runs.
local function CountBuilds(ns, fn)
  local LC = ns.LevelChart
  local orig, n = LC.Build, 0
  LC.Build = function(...) n = n + 1 return orig(...) end
  local ok, err = pcall(fn)
  LC.Build = orig
  if not ok then error(err, 0) end
  return n
end

---------------------------------------------------------------------------
-- Bars
---------------------------------------------------------------------------

T.test("chart: one column per level, each stack exactly its bar height, parts in their fixed order", function()
  local ns = Start()
  ns.Window.Show("levels")
  Stub.Advance(1)
  local ch = Chart()
  T.ok(ch ~= nil and Shown(ch.root), "chart shown")
  local st, geo = ch.state, ch.geo
  T.eq({ st.level, st.top, st.filter }, { 20, 60, 1 })
  T.eq(st.status, "ok", "an estimate from the last complete levels")
  T.eq(st.nCols, 59, "every level up to 59 (upcoming ones as ghosts)")
  local Stats, out = ns.Stats, {}
  for k = 1, st.nCols do
    local c = ch.cols[k]
    T.ok(Shown(c.hit), k .. ": hit area")
    local sum = 0
    for _, e in ipairs(Stack(c)) do sum = sum + e[2] end
    T.eq(sum, c.H, k .. ": stack = bar height")
    if k < 20 then
      local lb = ns.char.levels[k]
      if lb then
        Stats.LevelSegments(lb, 0, out)
        for i, key in ipairs(ch.segKeys) do T.eq(c.val[i], out[key], k .. " " .. key) end
        T.eq(c.total, Stats.Sum(lb, 0), k .. ": total = Stats.Sum")
      end
    end
  end
  -- kinds
  T.eq({ ch.cols[1].kind, ch.cols[2].kind, ch.cols[3].kind, ch.cols[4].kind, ch.cols[19].kind, ch.cols[20].kind,
         ch.cols[21].kind, ch.cols[59].kind }, { "none", "none", "done", "done", "done", "cur", "future", "future" })
  -- order: world (1) at the bottom, then world PvP, dungeon, ..., each on the one below
  local c18 = ch.cols[18]
  local stack = Stack(c18)
  T.eq(stack[1][1], 1, "world first")
  T.eq(c18.seg[1]:GetPoint(1), "BOTTOMLEFT")
  T.eq(select(2, c18.seg[1]:GetPoint(1)), ch.plot, "the first part sits on the plot")
  for j = 2, #stack do
    local _, rel, relPoint = c18.seg[stack[j][1]]:GetPoint(1)
    T.eq({ rel, relPoint }, { c18.seg[stack[j - 1][1]], "TOPLEFT" }, "part " .. stack[j][1] .. " on the one below")
  end
  for j = 2, #stack do T.ok(stack[j][1] > stack[j - 1][1], "fixed order") end
  -- the tallest bar fits, the scale is a whole step
  T.ok(st.scaleTop % st.step == 0 and st.scaleTop / st.step <= 5, "scale on a step, at most 5 gridlines")
  for k = 1, st.nCols do T.ok(ch.cols[k].H + (ch.cols[k].gOn and ch.cols[k].gH or 0) <= geo.plotH, k .. ": inside") end
  -- the current level: its server time (40000 s + the seconds since) under "all"
  local cur = ch.cols[20]
  T.near(cur.sumAll, ns.Stats.LevelTime(ns.char, 20, 0, ns.Tracker.GetSync(), GetTime()), 5, "current = LevelTime")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("chart: levels without a record show a stub; partial and rebuilt levels a bar", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  for k = 1, 2 do
    local c = ch.cols[k]
    T.eq(c.kind, "none")
    T.ok(Shown(c.stub), k .. ": stub")
    T.eq(Height(c.stub), 2)
    T.eq(#Stack(c), 0, k .. ": no part")
  end
  T.ok(ch.cols[3].partial and ch.cols[4].rec)
  T.ok(ch.cols[3].H > 0 and ch.cols[4].H > 0)
  T.no(Shown(ch.cols[5].stub), "a played level has no stub")
end)

T.test("chart: filters keep their parts, rescale on the filtered values, title and summary follow", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local L = ns.L
  local st = ch.state
  T.eq(Text(ch.title), L.LV_T_ALL)
  T.ok(Shown(ch.toggle), "the upcoming toggle under All")
  local allTop = st.scaleTop
  local want = { world = { 1 }, inst = { 3, 4 }, pvp = { 2, 5 }, flight = { 6 }, prof = { 7 }, dead = { 8 } }
  local titles = { world = "LV_T_WORLD", inst = "LV_T_INST", pvp = "LV_T_PVP", flight = "LV_T_FLIGHT",
                   prof = "LV_T_PROF", dead = "LV_T_DEAD" }
  for f, id in ipairs(ch.filterIds) do
    if id ~= "all" then
      ch.filters[f].btn:Click("LeftButton")
      T.eq(st.filter, f, id)
      T.eq(Text(ch.title), L[titles[id]], id .. ": title")
      T.no(Shown(ch.toggle), id .. ": no toggle")
      T.eq(st.nCols, 20, id .. ": played levels only")
      local mx = 0
      for k = 1, st.nCols do
        local c = ch.cols[k]
        local sum = 0
        for _, i in ipairs(want[id]) do sum = sum + c.val[i] end
        T.eq(c.total, sum, id .. " " .. k .. ": the filter's parts")
        for _, e in ipairs(Stack(c)) do
          local ok = false
          for _, i in ipairs(want[id]) do ok = ok or e[1] == i end
          T.ok(ok, id .. " " .. k .. ": only its parts drawn")
        end
        T.no(c.gOn, id .. ": no ghost")
        if c.total > mx then mx = c.total end
      end
      T.ok(st.scaleTop >= mx * 1.06 - 1e-6 and st.scaleTop < allTop + 1, id .. ": scale from the filtered values")
      local n = 0
      for k = 1, 19 do if ch.cols[k].total >= 60 then n = n + 1 end end
      if ch.cols[20].total >= 60 then n = n + 1 end
      T.match(Text(ch.summary), format("%d", n), id .. ": summary count")
    end
  end
  -- the PvP filter shows 15 .. 19 and the current level
  ch.filters[4].btn:Click("LeftButton")
  T.ok(ch.cols[16].H > 0 and ch.cols[14].H == 0)
  ch.filters[1].btn:Click("LeftButton")
  T.eq(st.nCols, 59, "back to all")
  T.eq(st.scaleTop, allTop)
end)

T.test("chart: the average line is the mean of the complete levels (partial, rebuilt, current out)", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local sum, n = 0, 0
  for k = 5, 19 do
    sum, n = sum + ns.Stats.Sum(ns.char.levels[k], 0), n + 1
  end
  T.near(ch.state.avg, sum / n, 1e-6, "mean of 5 .. 19")
  T.ok(Shown(ch.avg.line) and Shown(ch.avg.label))
  T.eq(Text(ch.avg.label), format(ns.L.LV_AVG_FMT, ns.Fmt.Duration(sum / n)))
  T.eq(Height(ch.avg.stalk), floor(sum / n / ch.state.scaleTop * ch.geo.plotH + 0.5) + 1, "on its stalk")
  -- under a filter: the mean of the filtered values
  ch.filters[2].btn:Click("LeftButton")
  sum = 0
  for k = 5, 19 do sum = sum + ch.cols[k].total end
  T.near(ch.state.avg, sum / n, 1e-6, "World filter")
end)

T.test("chart: ghosts of the upcoming levels from Stats.FutureLevels; the toggle hides them", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local st = ch.state
  local fut = {}
  local _, xp, max, rest, valid = ns.Tracker.GetXPInfo()
  ns.Stats.FutureLevels(ns.char, ns.db, 0, { level = 20, xp = xp, max = max, rest = rest, valid = valid,
    isMax = false, top = 60, sync = ns.Tracker.GetSync(), now = GetTime() }, fut)
  T.eq(fut.status, "ok")
  for k = 21, 59 do
    local c = ch.cols[k]
    T.near(c.est, fut[k], 1e-6, k .. ": estimate")
    T.ok(c.gOn and Shown(c.ghost) and Shown(c.gline), k .. ": ghost")
    T.eq(Height(c.ghost), floor(fut[k] / st.scaleTop * ch.geo.plotH + 0.5), k .. ": ghost height")
    T.eq(#Stack(c), 0, k .. ": nothing solid")
  end
  local cur = ch.cols[20]
  T.ok(cur.gOn, "the current level's remaining estimate")
  T.eq(select(2, cur.ghost:GetPoint(1)), cur.top, "on top of its solid part")
  T.ok(Shown(ch.marker), "the current level's top line")
  T.eq(select(2, ch.marker:GetPoint(1)), cur.top)
  for k = 1, 19 do T.no(ch.cols[k].gOn, k .. ": a played level has no ghost") end
  -- hide upcoming levels
  ch.toggle:Click("LeftButton")
  T.eq(st.nCols, 20)
  T.eq(Text(ch.toggleText), ns.L.LV_SHOW_UPCOMING)
  for k = 21, 59 do T.no(Shown(ch.cols[k].hit), k .. ": hidden") end
  T.no(cur.gOn, "no ghost on the current level either")
  ch.toggle:Click("LeftButton")
  T.eq(st.nCols, 59)
  T.eq(Text(ch.toggleText), ns.L.LV_HIDE_UPCOMING)
  -- the toggle is kept by Show (the filter and the selection are not)
  ch.toggle:Click("LeftButton")
  ch.filters[3].btn:Click("LeftButton")
  ns.Window.Hide()
  ns.Window.Show("levels")
  T.eq({ st.filter, st.hideUp, st.nCols }, { 1, true, 20 })
end)

---------------------------------------------------------------------------
-- Selection, detail sheet, tooltips
---------------------------------------------------------------------------

T.test("chart: selection frame and detail sheet: current level by default, a click selects", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  local dt = Frame().tp.detail
  T.eq(ch.state.sel, 20, "the current level")
  T.ok(Shown(dt.panel), "detail sheet shown")
  T.eq(dt.panel:GetWidth(), 400)
  T.eq(Text(dt.title), format(L.LEVEL_SPAN_FMT, 20, 21))
  local _, xp, max = ns.Tracker.GetXPInfo()
  T.eq(Text(dt.status), format(L.LD_CUR_FMT, Fmt.Percent(xp / max)))
  for i = 1, 4 do T.ok(Shown(ch.sel[i]), "selection frame " .. i) end
  T.eq(select(2, ch.sel[1]:GetPoint(1)), ch.cols[20].hit)
  -- a completed level: its end date
  ch.cols[12].hit:Click("LeftButton")
  T.eq(ch.state.sel, 12)
  T.eq(select(2, ch.sel[1]:GetPoint(1)), ch.cols[12].hit)
  T.eq(Text(dt.title), format(L.LEVEL_SPAN_FMT, 12, 13))
  T.eq(Text(dt.status), format(L.LD_DONE_FMT, Fmt.DateTime(T0 + 13 * 3600 - 1)))
  -- upcoming, no record
  ch.cols[30].hit:Click("LeftButton")
  T.eq({ Text(dt.title), Text(dt.status) }, { format(L.LEVEL_SPAN_FMT, 30, 31), L.LD_UPCOMING })
  ch.cols[1].hit:Click("LeftButton")
  T.eq(Text(dt.status), L.LD_NODATA)
  -- kept by a rebuild, reset by Show, by another character
  ns.Window.Refresh()
  T.eq(ch.state.sel, 1)
  ns.Window.Hide()
  ns.Window.Show("levels")
  T.eq(ch.state.sel, 20, "Show: the current level again")
  -- a selected upcoming level hidden by the toggle: back to the current one
  ch.cols[40].hit:Click("LeftButton")
  ch.toggle:Click("LeftButton")
  T.eq(ch.state.sel, 20)
  T.ok(Frame().tp.detail.content:GetHeight() > 0, "content height")
end)

T.test("chart: bar tooltip of a played, the current, an upcoming and a no-record level", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  local c = ch.cols[15]
  Stub.RunScript(c.hit, "OnEnter")
  T.eq(GameTooltip:GetOwner(), c.hit, "native theme: the GameTooltip")
  T.ok(GameTooltip:IsShown())
  local lines = TipLines()
  T.eq(lines[1][1], format(L.LEVEL_SPAN_FMT, 15, 16), "title")
  local total = ns.Stats.Sum(ns.char.levels[15], 0)
  T.eq(Line(lines, L.LV_PLAYED)[2], Fmt.Duration(total))
  T.eq(Line(lines, L.BD_WORLD)[2], format(L.LV_PART_FMT, Fmt.Duration(3000), Fmt.Percent(3000 / total)))
  T.eq(Line(lines, L.LV_SEG_BG)[2], format(L.LV_PART_FMT, Fmt.Duration(600), Fmt.Percent(600 / total)))
  T.eq(Line(lines, L.BD_DUNGEON)[2], format(L.LV_PART_FMT, Fmt.Duration(1200), Fmt.Percent(1200 / total)))
  T.eq(Line(lines, L.BD_DEAD)[2], format(L.LV_PART_FMT, Fmt.Duration(240), Fmt.Percent(240 / total)))
  T.eq(Line(lines, L.LV_SEG_WPVP), nil, "no world PvP at 15")
  T.eq(Line(lines, L.TT_DEATHS)[2], "2")
  T.eq(Line(lines, L.COL_REACHED)[2], Fmt.DateTime(T0 + 16 * 3600 - 1))
  T.eq(lines[#lines][1], L.LV_CLICK_HINT, "hint last")
  -- the part colours are the gauge colours
  local gc = ns.Themes.CLASSIC_GAUGE.colors
  for i, l in ipairs(GameTooltip._lines) do
    if l[1] == L.BD_WORLD then T.near(GameTooltip._colors[i][1], gc.world[1], 1e-6, "world colour") end
  end
  Stub.RunScript(c.hit, "OnLeave")
  T.no(GameTooltip:IsShown(), "hidden on leave")
  -- world PvP at 17
  Stub.RunScript(ch.cols[17].hit, "OnEnter")
  T.eq(Line(TipLines(), L.LV_SEG_WPVP)[2], format(L.LV_PART_FMT, Fmt.Duration(120),
    Fmt.Percent(120 / ns.Stats.Sum(ns.char.levels[17], 0))))
  Stub.RunScript(ch.cols[17].hit, "OnLeave")
  -- partly estimated: "~"
  Stub.RunScript(ch.cols[3].hit, "OnEnter")
  T.match(Line(TipLines(), L.LV_PLAYED)[2], "^~")
  Stub.RunScript(ch.cols[3].hit, "OnLeave")
  -- the current level
  Stub.RunScript(ch.cols[20].hit, "OnEnter")
  lines = TipLines()
  T.eq(Line(lines, L.COL_REACHED)[2], L.ROW_IN_PROGRESS)
  Stub.RunScript(ch.cols[20].hit, "OnLeave")
  -- upcoming
  local f = ch.cols[25]
  Stub.RunScript(f.hit, "OnEnter")
  lines = TipLines()
  T.eq(lines[2][1], format(L.LV_UPCOMING_FMT, Fmt.ETA(f.est)))
  T.eq(lines[3][1], format(L.LV_XP_EARN_FMT, Fmt.Number(ns.Stats.XPOf(ns.char, ns.db, 25))))
  Stub.RunScript(f.hit, "OnLeave")
  -- no record
  Stub.RunScript(ch.cols[1].hit, "OnEnter")
  T.ok(HasText(TipLines(), L.LV_NO_RECORD))
  -- a click keeps the tooltip's owner check: Deactivate hides it
  ns.Window.Hide()
  T.no(GameTooltip:IsShown(), "Window.Hide hides the chart's tooltip")
end)

T.test("chart: the themed tooltip frame under a non-native theme, the PvP filter's world PvP notes", function()
  local ns = Start({ theme = "futuriste", pvp = "forever" })
  ns.char.pvp.w0 = T0 + floor(15.5 * 3600)
  ns.Window.Show("levels")
  local ch = Chart()
  local L = ns.L
  local tf = ns.TooltipFrame.Get(1)
  local function Rows()
    local out = {}
    for i = 1, tf.tp.n do
      local r = tf.tp.rows[i]
      out[i] = { r.lt, r.rt }
    end
    return out
  end
  ch.filters[4].btn:Click("LeftButton")              -- PvP
  Stub.RunScript(ch.cols[15].hit, "OnEnter")
  T.eq(tf:GetOwner(), ch.cols[15].hit, "the themed frame")
  T.ok(tf:IsShown())
  local rows = Rows()
  T.eq(rows[1][1], format(L.LEVEL_SPAN_FMT, 15, 16))
  T.ok(HasText(rows, L.LV_WPVP_PARTIAL), "15 began before world PvP was measured")
  Stub.RunScript(ch.cols[15].hit, "OnLeave")
  T.no(tf:IsShown())
  Stub.RunScript(ch.cols[10].hit, "OnEnter")
  T.ok(HasText(Rows(), L.LV_WPVP_BEFORE), "10 ended before")
  Stub.RunScript(ch.cols[10].hit, "OnLeave")
  Stub.RunScript(ch.cols[17].hit, "OnEnter")
  T.no(HasText(Rows(), L.LV_WPVP_BEFORE) or HasText(Rows(), L.LV_WPVP_PARTIAL), "17: measured")
  -- a theme switch hides it
  ns.Core.SetSetting("theme", "pixel")
  T.no(tf:IsShown(), "THEME_CHANGED hides the chart's tooltip")
end)

---------------------------------------------------------------------------
-- Chips and strip
---------------------------------------------------------------------------

T.test("chart: the chips (played, server, average, PvP, flight, deaths, level 60 in)", function()
  local ns = Start({ pvp = "forever" })
  ns.char.pvp.w0 = T0 + floor(15.5 * 3600)
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local char, sync, now = ns.char, ns.Tracker.GetSync(), GetTime()
  local chips = ch.chips
  local played, base = Stats.Played(char, 0, sync, now)
  T.eq({ Text(chips[1].label), Text(chips[1].value), Text(chips[1].sub) },
    { L.LV_PLAYED, Fmt.Duration(played), format(L.LV_PLAYED_SUB_FMT, 20) })
  T.eq({ Text(chips[2].label), Text(chips[2].value), Text(chips[2].sub) },
    { L.TT_SERVER, Fmt.Duration(base), L.LV_SERVER_SUB })
  local avg = Stats.AvgPerLevel(char, 0, sync, now)
  local recent, n = Stats.RecentAvg(char, 0, 5)
  T.eq({ Text(chips[3].value), Text(chips[3].sub) },
    { Fmt.Duration(avg), format(L.LV_AVG_RECENT_FMT, n, Fmt.Duration(recent)) })
  local life = {}
  Stats.LevelSegments(char.life, 0, life)
  T.eq(life.bg, 3300)
  T.eq(life.wpvp, 480)
  T.eq({ Text(chips[4].label), Text(chips[4].value), Text(chips[4].sub) },
    { L.BD_PVP, Fmt.Duration(3780), format(L.LV_PVP_SUB_FMT, Fmt.Duration(3300), Fmt.Duration(480)) })
  T.eq({ Text(chips[5].label), Text(chips[5].value), Text(chips[5].sub) },
    { L.LV_FLIGHT, Fmt.Duration(life.taxi), format(L.LV_FLIGHT_SUB_FMT, Fmt.Percent(life.taxi / played)) })
  T.eq({ Text(chips[6].label), Text(chips[6].value), Text(chips[6].sub) },
    { L.TT_DEATHS, "6", format(L.LV_DEAD_SUB_FMT, Fmt.Duration(life.dead)) })
  T.eq({ Text(chips[7].label), Text(chips[7].sub) }, { format(L.LV_TOP_IN_FMT, 60), L.LV_TOP_SUB })
  T.match(Text(chips[7].value), "^~")
  -- the PvP chip's tooltip: each battleground, the other ones, world PvP, its definition
  Stub.RunScript(chips[4].frame, "OnEnter")
  local lines = TipLines()
  T.eq(lines[1][1], format(L.LV_PVP_TIP_FMT, Fmt.Duration(3780)))
  T.eq(Line(lines, L.LV_SEG_BG)[2], Fmt.Duration(3300))
  T.eq(Line(lines, "   Warsong Gulch")[2], Fmt.Duration(2000))
  T.eq(Line(lines, "   Arathi Basin")[2], Fmt.Duration(1000))
  T.eq(Line(lines, "   " .. L.LV_BG_OTHER)[2], Fmt.Duration(300))
  T.eq(Line(lines, L.LV_WPVP_LONG)[2], Fmt.Duration(480))
  T.ok(HasText(lines, format(L.LV_WPVP_DEF_FMT, 15)), "definition")
  T.ok(HasText(lines, format(L.LV_WPVP_SINCE_FMT, Fmt.DateTime(T0 + floor(15.5 * 3600)))), "since")
  Stub.RunScript(chips[4].frame, "OnLeave")
  T.no(GameTooltip:IsShown())
end)

-- A chip's sub line wider than its chip (the stub draws 6 px a character) shows its
-- durations by their largest unit (LevelChart SubFit: here whole days, L.LV_DAYS_FMT); the
-- value and the tooltip keep them in full, and a line that fits keeps them in full even
-- from a day up. GetStringWidth is bounded by the width set, as in the client (Start:
-- stub_ui boundedText): SubFit measures the unbounded width (review chartrt-1: with
-- GetStringWidth the compact form never showed in game).
T.test("chart: a chip's sub line too wide for its chip shows its durations by their largest unit", function()
  local ns = Start({ pvp = "forever" })
  local life = ns.char.life
  life.s.p = life.s.p + 12 * 86400                     -- battlegrounds: 12 days more
  life.s.w = life.s.w + 5 * 86400
  life.pw = life.pw + 4 * 86400 + 12 * 3600            -- world PvP: 4 days 12 hours more
  life.s.x = (life.s.x or 0) + 12 * 86400              -- dead or a ghost: 12 days more
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local seg = {}
  Stats.LevelSegments(life, 0, seg)
  local inner = ch.geo.chipW - 16
  local function Days(v) return format(L.LV_DAYS_FMT, floor(v / 86400)) end
  local full = format(L.LV_PVP_SUB_FMT, Fmt.Duration(seg.bg), Fmt.Duration(seg.wpvp))
  local sub = ch.chips[4].sub
  T.ok(sub:GetUnboundedStringWidth() <= inner, "the shown line fits")
  T.eq(Text(sub), format(L.LV_PVP_SUB_FMT, Days(seg.bg), Days(seg.wpvp)), "PvP: whole days")
  T.ok(6 * #full > inner, "the full line would not fit: " .. full)
  -- the stub is the client's: the full line's GetStringWidth is the chip's width
  local shown = Text(sub)
  sub:SetText(full)
  T.eq({ sub:GetStringWidth(), sub:GetUnboundedStringWidth() > inner }, { inner, true }, "bounded by the width set")
  sub:SetText(shown)
  T.eq(Text(ch.chips[4].value), Fmt.Duration(seg.bg + seg.wpvp), "the value in full")
  T.eq(Text(ch.chips[6].sub), format(L.LV_DEAD_SUB_FMT, Days(seg.dead)), "dead: whole days")
  Stub.RunScript(ch.chips[4].frame, "OnEnter")
  T.eq(Line(TipLines(), L.LV_SEG_BG)[2], Fmt.Duration(seg.bg), "the tooltip in full")
  Stub.RunScript(ch.chips[4].frame, "OnLeave")
  -- shorter: the full line fits again, its durations in full (a day or more included)
  life.s.p, life.pw = 2 * 86400, 0
  ns.Window.Refresh()
  Stats.LevelSegments(life, 0, seg)
  T.ok(seg.bg >= 86400)
  T.eq(seg.wpvp, 0)
  T.eq(Text(ch.chips[4].sub), format(L.LV_PVP_SUB_FMT, Fmt.Duration(seg.bg), "-"), "in full")
end)

T.test("chart: Classic Era (no PvP API): world PvP is 'not measured', never 0", function()
  local ns = Start()
  T.no(ns.Pvp.Available())
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  T.eq(Text(ch.chips[4].sub), format(L.LV_PVP_SUB_FMT, Fmt.Duration(3300), L.DOTS))
  Stub.RunScript(ch.chips[4].frame, "OnEnter")
  local lines = TipLines()
  T.eq(Line(lines, L.LV_WPVP_LONG)[2], L.DOTS)
  T.ok(HasText(lines, L.LV_WPVP_NO_CLIENT))
  Stub.RunScript(ch.chips[4].frame, "OnLeave")
  ch.filters[4].btn:Click("LeftButton")
  Stub.RunScript(ch.cols[17].hit, "OnEnter")
  T.ok(HasText(TipLines(), L.LV_WPVP_NO_CLIENT), "bar tooltip under the PvP filter")
end)

T.test("chart: the progress strip (done, current, estimate left, shares of time and XP)", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local st, sp = ch.state, ch.strip
  T.eq(Text(sp.title), format(L.LV_PROGRESS_FMT, 60))
  local played = Stats.Played(ns.char, 0, ns.Tracker.GetSync(), GetTime())
  local cur = st.curTime
  T.near(st.done, played - cur, 1e-6)
  T.eq(Text(sp.fs1), format(L.LV_DONE_FMT, 19, Fmt.Duration(played - cur)))
  T.eq(Text(sp.fs2), format(L.LV_CUR_FMT, 20, Fmt.Duration(cur)))
  local fut = {}
  local _, xp, max, rest, valid = ns.Tracker.GetXPInfo()
  Stats.FutureLevels(ns.char, ns.db, 0, { level = 20, xp = xp, max = max, rest = rest, valid = valid, top = 60,
    sync = ns.Tracker.GetSync(), now = GetTime() }, fut)
  -- the time left: the "Level 60 in" chip's text and rounding (review ux-3: Fmt.Duration
  -- truncated it an hour below the chip's)
  T.eq(Text(sp.fs3), format(L.LV_LEFT_FMT, Fmt.ETA(fut.total)))
  T.eq(Text(ch.chips[7].value), Fmt.ETA(fut.total), "the same text in the chip")
  T.eq(st.kLeft, st.kTop, "the same key")
  local grand = st.done + cur + fut.total
  local xpDone, xpAll = 0, 0
  for l = 1, 59 do
    local x = Stats.XPOf(ns.char, ns.db, l) or 0
    xpAll = xpAll + x
    if l < 20 then xpDone = xpDone + x end
  end
  T.eq(Text(sp.share), format(L.LV_SHARE_FMT, floor((st.done + cur) / grand * 100), floor((xpDone + xp) / xpAll * 100)))
  local W = ch.geo.trackW
  T.eq(sp.done:GetWidth(), floor(st.done / grand * W + 0.5))
  T.eq(sp.cur:GetWidth(), floor(cur / grand * W + 0.5))
  T.eq(select(2, sp.cur:GetPoint(1)), sp.done, "the current part after the done one")
  T.ok(Shown(sp.fs3) and Shown(sp.sq3))
end)

---------------------------------------------------------------------------
-- Live, allocation, regions
---------------------------------------------------------------------------

T.test("chart: live growth of the current level is SetHeight only (no SetPoint), chips and strip follow", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local Fmt = ns.Fmt
  Stub.Advance(600)                  -- the world part of the current level shows
  local c = ch.cols[20]
  local h0, sig0, top0 = c.H, c.sig, ch.state.scaleTop
  local kPlayed = ch.state.kPlayed
  local n = CountSetPoint(ch.root, function() Stub.Advance(3600) end)
  T.eq(ch.state.scaleTop, top0, "same scale over the hour")
  T.ok(c.H > h0, format("the current bar grew (%d -> %d px)", h0, c.H))
  T.eq(c.sig, sig0, "same visible parts")
  T.eq(n, 0, "no SetPoint while it grows")
  T.ok(ch.state.kPlayed ~= kPlayed, "the Played chip followed")
  local played = ns.Stats.Played(ns.char, 0, ns.Tracker.GetSync(), GetTime())
  T.eq(Text(ch.chips[1].value), Fmt.Duration(played))
  T.eq(Text(ch.strip.fs2), format(ns.L.LV_CUR_FMT, 20, Fmt.Duration(ch.state.curTime)))
  local sum = 0
  for _, e in ipairs(Stack(c)) do sum = sum + e[2] end
  T.eq(sum, c.H, "stack = height after growing")
end)

T.test("chart: 600 ticks open on the chart allocate nothing; a second Build or Show creates nothing", function()
  -- the same timeline twice (the stub is deterministic): the window hidden, then open on
  -- the chart; every live key here changes at most hourly (times over 10 h: the current
  -- level's world part too, a row of the detail sheet's live breakdown)
  local function Step() Stub.Advance(1) end
  local function Run(show)
    Stub.Reset()
    local n = Start({ levelPlayed = 50000, total = 500000 })
    local s20 = n.char.levels[20].s
    s20.w = (s20.w or 0) + 40000
    if show then n.Window.Show("levels") end
    Stub.Advance(700)                -- warm: the first live steps (memoized strings, first key changes)
    return n, T.alloc(Step, 600)
  end
  local _, hidden = Run(false)
  local ns, kb = Run(true)
  T.ok(kb - hidden <= 0.3, format("chart shown: %.2f KB over 600 ticks (window hidden: %.2f KB)", kb, hidden))
  -- the live step itself, at a moment where no key changes: nothing at all
  local LC, char, sync, now = ns.LevelChart, ns.char, ns.Tracker.GetSync(), GetTime()
  LC.Live(char, 0, sync, now)
  local live = T.alloc(function() LC.Live(char, 0, sync, now) end, 600)
  T.ok(live < 0.05, format("LevelChart.Live x600: %.3f KB", live))
  ns.Window.Hide()
  -- nothing created again (every tab shown once first: their rows exist)
  ns.Window.Show("zones")
  ns.Window.Show("sessions")
  ns.Window.Show("levels")
  Stub.RunScript(Chart().cols[12].hit, "OnEnter")
  Stub.RunScript(Chart().cols[12].hit, "OnLeave")
  Stub.Advance(1)
  local n0 = Created()
  ns.Window.Refresh()
  ns.Window.Hide()
  ns.Window.Show("levels")
  ns.Window.Show("zones")
  ns.Window.Show("levels")
  Stub.Advance(10)
  T.eq(Created(), n0, "no region created by a second Build / Show")
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------

T.test("chart: another character (no live, no sync), the account view keeps its table", function()
  local ns = Start()
  -- another character: a copy of this one's records at level 12, no live data
  local rec = Stub.DeepCopy(ns.char)
  rec.guid, rec.name, rec.level = "Player-4619-0BADF00D", "Other", 12
  for l = 13, 20 do rec.levels[l] = nil end
  rec.srv = { total = 123456, at = time() - 7200 }
  ns.db.chars[rec.guid] = rec
  ns.Window.Show("levels", rec.guid)
  local ch = Chart()
  local st = ch.state
  T.eq({ st.char, st.isCur, st.level }, { rec, false, 12 })
  T.ok(Shown(ch.root))
  T.eq(Text(ch.chips[2].value), ns.Fmt.Duration(123456), "server: the snapshot")
  T.eq(Text(ch.chips[2].sub), ns.Fmt.Ago(7200))
  T.eq(st.sel, 12)
  local before = { Text(ch.chips[1].value), ch.cols[12].H }
  Stub.Advance(600)
  T.eq({ Text(ch.chips[1].value), ch.cols[12].H }, before, "not live")
  -- the account view: the table, the chart hidden
  ns.Window.SetView("account")
  T.no(Shown(ch.root), "chart hidden")
  local tp = Frame().tp
  T.eq(tp.layout, tp.layouts.account)
  T.ok(tp.rows[1]:IsShown(), "account rows")
end)

T.test("chart: max level (time at max) and a detected server cap", function()
  local ns = Start({ level = 60, top = 60 })
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  local st = ch.state
  T.ok(st.atMax)
  T.eq(st.nCols, 59)
  T.eq(st.sel, 59, "the last bar")
  T.eq({ Text(ch.chips[7].label), Text(ch.chips[7].value) }, { L.MAX_LEVEL, "60" })
  T.eq(Text(ch.chips[7].sub), format(L.LV_MAX_SUB_FMT, Fmt.Duration(st.curTime)))
  T.eq(Text(ch.strip.share), L.TT_MAX_LEVEL)
  T.no(Shown(ch.strip.fs2))
  T.no(Shown(ch.marker))
  for k = 1, 59 do T.no(ch.cols[k].gOn) end
  Stub.Advance(3600)
  T.eq(Text(ch.chips[7].sub), format(L.LV_MAX_SUB_FMT, Fmt.Duration(st.curTime)), "time at max is live")
  -- a server cap
  Stub.Reset()
  ns = Start()
  for _ = 1, 3 do Stub.KillNoXP() end
  local cap = ns.Tracker.GetCapInfo()
  T.eq(cap, 20)
  ns.Window.Show("levels")
  ch = Chart()
  T.eq(ch.state.status, "cap")
  T.eq({ Text(ch.chips[7].label), Text(ch.chips[7].value) }, { L.CAP_SHORT, format(L.LV_CAP_LEVEL_FMT, 20) })
  T.eq(Text(ch.strip.share), format(L.LV_CAP_FMT, 20))
  T.eq(ch.state.nCols, 20, "no projection")
end)

T.test("chart: the window is at least 1040 x 640 while the chart shows; other tabs keep 700 x 440", function()
  local ns = Start()
  ns.Window.Show("zones")
  local f = Frame()
  T.eq({ f:GetWidth(), f:GetHeight() }, { 700, 440 })
  ns.Window.Show("levels")
  T.eq({ f:GetWidth(), f:GetHeight() }, { 1040, 640 })
  T.eq(ns.settings.window.width, 700, "the setting is not changed")
  T.eq(f.tp.layout, f.tp.layouts.chart)
  T.no(f.tp.header[1]:IsShown(), "no column header")
  -- larger saved size: kept
  ns.Core.SetSetting("window.width", 1200)
  ns.Core.SetSetting("window.height", 800)
  T.eq({ f:GetWidth(), f:GetHeight() }, { 1200, 800 })
  local ch = Chart()
  T.eq(ch.root:GetWidth(), 1200 - 28)
  T.eq(ch.geo.colW, 1200 - 28 - 414)
  ns.Window.SetView("account")
  T.eq(f:GetWidth(), 1200)
end)

---------------------------------------------------------------------------
-- Review fixes (design/NEXT-LOT.md, "review fixes")
---------------------------------------------------------------------------

-- chartrt-3: the grip saves a dimension only when the user changed it; the chart's minimum
-- (1040 x 640 here) is never saved as the window's size.
T.test("chart: the grip saves only a dimension the user changed, never the chart's minimum", function()
  local ns = Start()
  ns.Core.SetSetting("window.width", 800)
  ns.Window.Show("levels")
  local f = Frame()
  local grip = f.tp.grip
  local function Down() grip:GetScript("OnMouseDown")(grip, "LeftButton") end
  local function Up() grip:GetScript("OnMouseUp")(grip, "LeftButton") end
  local ws = ns.settings.window
  T.eq({ f:GetWidth(), f:GetHeight(), ws.width, ws.height }, { 1040, 640, 800, 440 })
  Down()
  Up()
  T.eq({ ws.width, ws.height }, { 800, 440 }, "a click on the grip saves nothing")
  Down()
  f:SetSize(1040, 690)                                  -- what the client does while sizing
  Up()
  T.eq({ ws.width, ws.height }, { 800, 690 }, "a drag down: the height alone")
  T.eq({ f:GetWidth(), f:GetHeight() }, { 1040, 690 })
  ns.Window.Show("zones")
  T.eq({ f:GetWidth(), f:GetHeight() }, { math.max(800, f.tp.layout.need + 50), 690 }, "Zones: the saved width")
  ns.Window.Show("levels")
  Down()
  f:SetSize(1100, 690)
  Up()
  T.eq({ ws.width, ws.height }, { 1100, 690 }, "a width the user chose is saved")
  T.eq(Chart().root:GetWidth(), 1100 - 28)
end)

-- chartrt-4: a 4:3 or 5:4 screen at UI scale 1 (UIParent 1024 or 960 wide) or a large UI
-- scale: the window's minimum is the screen less 20 px (never below 700 x 300), the detail
-- sheet keeps its 400 px and the chart column takes what is left (narrower bars).
T.test("chart: on a 4:3 or 5:4 screen the window fits the screen; the chart column takes what is left", function()
  local ns = Start()
  for _, sz in ipairs({ { 1024, 768 }, { 960, 768 }, { 1024, 600 } }) do
    UIParent:SetSize(sz[1], sz[2])
    ns.Window.Show("levels")
    local f, ch = Frame(), Chart()
    local geo, where = ch.geo, sz[1] .. " x " .. sz[2]
    local w, h = sz[1] - 20, math.min(640, sz[2] - 20)
    T.eq({ ns.LevelChart.MinSize() }, { w, h }, where .. ": the screen less 20 px")
    T.eq({ f:GetWidth(), f:GetHeight() }, { w, h }, where .. ": the window")
    T.eq({ ch.root:GetWidth(), ch.root:GetHeight() }, { w - 28, h - 140 }, where .. ": the root follows")
    T.eq(Detail().panel:GetWidth(), 400, where .. ": the detail sheet keeps its width")
    T.eq(geo.colW, w - 28 - 414, where .. ": the chart column, what is left")
    local last = ch.cols[ch.state.nCols]
    T.ok(last.x + geo.barW <= geo.plotW, where .. ": the last bar inside the plot")
    T.ok(geo.plotH > 100, where .. ": a plot: " .. geo.plotH)
    for i = 1, 7 do
      local p = ch.chips[i].frame:GetPoint(1) and select(4, ch.chips[i].frame:GetPoint(1))
      T.ok(p + geo.chipW <= ch.root:GetWidth(), where .. ": chip " .. i .. " inside the root")
    end
    ns.Window.Hide()
  end
  -- the settings never go below the window's own minimum
  UIParent:SetSize(600, 280)
  T.eq({ ns.LevelChart.MinSize() }, { 700, 300 })
  UIParent:SetSize(1920, 1080)
  ns.Window.Show("levels")
  T.eq({ Frame():GetWidth(), Frame():GetHeight() }, { 1040, 640 }, "a 16:9 screen: 1040 x 640")
  T.eq(#Stub.errors, 0)
end)

-- chartrt-2: a level parked for months (a capped twink, a level stuck at the Forever beta's
-- cap) needs steps beyond 10 days: the scale goes on in days (20, 50, 100... days), at most
-- 5 gridlines over the whole plot, labelled in days.
T.test("chart: a level of 60 days: steps in days beyond 10 days, gridlines over the plot, labels in days", function()
  local ns = Start({ levelPlayed = 60 * 86400, total = 61 * 86400 })
  ns.Window.Show("levels")
  local ch = Chart()
  local st, geo, L = ch.state, ch.geo, ns.L
  T.ok(ch.cols[20].total >= 60 * 86400, "the current level: 60 days")
  local mx = 0
  for k = 1, st.nCols do
    local c = ch.cols[k]
    local v = c.total + (c.gOn and c.est or 0)
    if v > mx then mx = v end
  end
  T.ok(st.scaleTop >= mx * 1.06 - 1e-6, "the tallest bar fits")
  T.eq(st.scaleTop % st.step, 0, "the scale on a step")
  T.ok(st.scaleTop / st.step <= 5, format("at most 5 gridlines: %d steps of %d s", st.scaleTop / st.step, st.step))
  T.eq(st.step, 20 * 86400, "20 days")
  local n, top = 0, 0
  for j = 1, 5 do
    local g = ch.grid[j]
    if Shown(g.line) then
      n = n + 1
      T.eq(Text(g.label), format(L.LV_DAYS_FMT, j * 20), j .. ": in days")
      if g.y > top then top = g.y end
    end
  end
  T.eq(n, st.scaleTop / st.step, "a gridline per step")
  T.eq(top, geo.plotH, "the last gridline at the top of the plot")
  for k = 1, st.nCols do T.ok(ch.cols[k].H <= geo.plotH, k .. ": inside") end
  -- a step of a day reads in days too ("1d", not "24h")
  Stub.Reset()
  ns = Start({ levelPlayed = 4 * 86400, total = 5 * 86400 })
  ns.Window.Show("levels")
  ch = Chart()
  T.eq(ch.state.step, 86400)
  T.eq(Text(ch.grid[1].label), format(ns.L.LV_DAYS_FMT, 1))
end)

-- ux-1: the PvP (and its sub line), Flight and Deaths chips follow a flight, a death and a
-- battleground live (no rebuild: no XP gain), nothing allocated while no key changes.
T.test("chart: the PvP, Flight and Deaths chips follow live; nothing allocated while no key changes", function()
  local ns = Start({ pvp = "forever" })
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local chips, life, seg = ch.chips, ns.char.life, {}
  local d0 = life.d
  local function Played() return (Stats.Played(ns.char, 0, ns.Tracker.GetSync(), GetTime())) end
  local builds = CountBuilds(ns, function()
    Stub.SetTaxi(true); Stub.Advance(1800); Stub.SetTaxi(false)
    Stub.Advance(10)
    Stats.LevelSegments(life, 0, seg)
    T.eq(Text(chips[5].value), Fmt.Duration(seg.taxi), "Flight chip, live")
    T.eq(Text(chips[5].sub), format(L.LV_FLIGHT_SUB_FMT, Fmt.Percent(seg.taxi / Played())))
    Stub.Die(); Stub.Advance(65); Stub.ReleaseSpirit(); Stub.Advance(260); Stub.Resurrect(true)
    Stub.Advance(10)
    Stats.LevelSegments(life, 0, seg)
    T.eq(life.d, d0 + 1)
    T.eq(Text(chips[6].value), Fmt.Number(d0 + 1), "Deaths chip, live")
    T.eq(Text(chips[6].sub), format(L.LV_DEAD_SUB_FMT, Fmt.Duration(seg.dead)))
    local bg0 = seg.bg
    Stub.EnterBG(); Stub.Advance(1800); Stub.LeaveBG()
    Stub.Advance(10)
    Stats.LevelSegments(life, 0, seg)
    T.ok(seg.bg >= bg0 + 1790, "battleground time")
    T.eq(Text(chips[4].value), Fmt.Duration(seg.bg + seg.wpvp), "PvP chip, live")
    T.eq(Text(chips[4].sub), format(L.LV_PVP_SUB_FMT, Fmt.Duration(seg.bg), Fmt.Duration(seg.wpvp)), "its sub line")
  end)
  T.eq(builds, 0, "followed live, not by a rebuild")
  -- no key changes: the live step allocates nothing
  local LC, char, sync, now = ns.LevelChart, ns.char, ns.Tracker.GetSync(), GetTime()
  LC.Live(char, 0, sync, now)
  T.ok(T.alloc(function() LC.Live(char, 0, sync, now) end, 600) < 0.05, "LevelChart.Live x600")
end)

-- ux-7: a flight share above 0 and under 1 % reads "<1%", never "0%".
T.test("chart: a flight share under 1 % reads '<1%', never '0%'", function()
  local ns = Start()
  local life = ns.char.life
  life.s.t = 600                        -- 10 min of flight for 400000 s played
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  T.eq(Text(ch.chips[5].value), Fmt.Duration(600))
  T.eq(Text(ch.chips[5].sub), format(L.LV_FLIGHT_SUB_FMT, format(L.LV_LT_FMT, Fmt.Percent(0.01))))
  life.s.t = 5000                       -- 1.25 %: 1 %
  ns.Window.Refresh()
  T.eq(Text(ch.chips[5].sub), format(L.LV_FLIGHT_SUB_FMT, Fmt.Percent(0.01)))
  life.s.t = 0
  ns.Window.Refresh()
  T.eq({ Text(ch.chips[5].value), Text(ch.chips[5].sub) }, { "-", "" }, "no flight: no share")
end)

-- ux-2: under a filter the bar tooltip first gives the bar's own value (the filter's parts)
-- and its share of the level, in ui.accent; the level's lines follow.
T.test("chart: under a filter the bar tooltip first gives the bar's value and its share of the level", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  ch.filters[4].btn:Click("LeftButton")              -- PvP: battlegrounds + world PvP
  local c = ch.cols[17]
  Stub.RunScript(c.hit, "OnEnter")
  local lines = TipLines()
  T.eq(lines[1][1], format(L.LEVEL_SPAN_FMT, 17, 18))
  T.eq(lines[2], { L.BD_PVP, format(L.LV_PART_FMT, Fmt.Duration(720), Fmt.Percent(720 / c.sumAll)) },
    "the bar's value right after the title")
  T.eq(c.total, 720)
  local accent = ns.Themes.Active().ui and ns.Themes.Active().ui.accent or ns.C.COLORS.accent
  T.near(GameTooltip._colors[2][1], accent[1], 1e-6, "in accent")
  T.eq(Line(lines, L.LV_PLAYED)[2], Fmt.Duration(c.sumAll), "the whole level below")
  T.ok(Line(lines, L.LV_SEG_BG) ~= nil and Line(lines, L.BD_WORLD) ~= nil, "every part below")
  Stub.RunScript(c.hit, "OnLeave")
  -- a level without the activity
  Stub.RunScript(ch.cols[10].hit, "OnEnter")
  T.eq(TipLines()[2], { L.BD_PVP, "-" })
  Stub.RunScript(ch.cols[10].hit, "OnLeave")
  -- "all": no such line
  ch.filters[1].btn:Click("LeftButton")
  Stub.RunScript(c.hit, "OnEnter")
  T.eq(TipLines()[2][1], L.LV_PLAYED)
end)

-- ux-6: one label for flight in the whole view (French: "Vol", the chip's, the pill's and
-- the sheet row's; BD_TAXI "En vol" is the main tooltip's).
T.test("chart: the bar tooltip's flight part has the chip's label (frFR: Vol)", function()
  local ns = Start({ locale = "frFR" })
  ns.Window.Show("levels")
  local ch = Chart()
  local L = ns.L
  T.ok(L.LV_FLIGHT ~= L.BD_TAXI, "two French labels")
  T.eq(Text(ch.chips[5].label), L.LV_FLIGHT)
  Stub.RunScript(ch.cols[15].hit, "OnEnter")
  local lines = TipLines()
  T.ok(Line(lines, L.LV_FLIGHT) ~= nil, "the chip's label")
  T.eq(Line(lines, L.BD_TAXI), nil)
end)

-- ux-4: no "0 levels" summary: nothing to count reads "no time recorded", a few seconds
-- alone their total.
T.test("chart: an empty summary reads 'No time recorded'; a few seconds alone their total", function()
  local ns = Start({ seed = false })
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  local c = ch.cols[20]
  ch.filters[3].btn:Click("LeftButton")              -- Instances: never played
  T.eq(Text(ch.summary), L.LV_SUM_NONE)
  ch.filters[2].btn:Click("LeftButton")              -- World: the seconds since the login
  T.ok(c.total > 0 and c.total < 60, "a few seconds: " .. c.total)
  T.eq(Text(ch.summary), format(L.LD_TOTAL_FMT, Fmt.Duration(c.total)))
  Stub.Advance(120)
  T.eq(Text(ch.summary), format(L.LV_SUM_FILTER_ONE_FMT, Fmt.Duration(c.total), 1), "live: one level")
  -- a character installed at the max level: no level recorded under "all"
  Stub.Reset()
  ns = Start({ level = 60, top = 60, seed = false })
  ns.Window.Show("levels")
  T.eq(Text(Chart().summary), ns.L.LV_SUM_NONE)
end)

-- ux-5: a level-1 character: "level 1", never "levels 1 to 1" (Played chip and the detail
-- sheet's total since level 1).
T.test("chart: a level-1 character reads 'level 1', never 'levels 1 to 1'", function()
  local ns = Start({ level = 1, seed = false, levelPlayed = 120, total = 120 })
  ns.Window.Show("levels")
  local ch = Chart()
  local L = ns.L
  T.eq(ch.state.level, 1)
  T.eq(Text(ch.chips[1].sub), L.LV_PLAYED_SUB_ONE)
  T.eq(Detail().level, 1)
  T.eq(Text(Detail().cards.cum.sub), L.LV_PLAYED_SUB_ONE)
  T.ok(L.LV_PLAYED_SUB_ONE ~= format(L.LV_PLAYED_SUB_FMT, 1))
  -- level 2: the range again
  Stub.Reset()
  ns = Start({ level = 2, seed = false })
  ns.Window.Show("levels")
  T.eq(Text(Chart().chips[1].sub), format(ns.L.LV_PLAYED_SUB_FMT, 2))
end)

-- ux-9: XP disabled below the top level (Util.IsMaxLevel says max): "XP disabled" in the
-- chip and the strip, the level in progress, no projection, no "max level"; live without a
-- rebuild; XP back on: the projection again.
T.test("chart: XP disabled below the top level reads 'XP disabled', never 'max level'", function()
  local ns = Start({ level = 25, xpOff = true })
  ns.Window.Show("levels")
  local ch = Chart()
  local L = ns.L
  local st = ch.state
  T.eq({ st.status, st.atMax, st.xpOff, st.estOK }, { "max", false, true, false })
  T.eq({ Text(ch.chips[7].label), Text(ch.chips[7].value), Text(ch.chips[7].sub) },
    { L.LV_XP_OFF, format(L.LV_CAP_LEVEL_FMT, 25), "" })
  T.eq(Text(ch.strip.share), format(L.LV_XP_OFF_FMT, 25))
  T.ok(Shown(ch.strip.fs2), "the level in progress")
  T.eq(Text(ch.strip.fs2), format(L.LV_CUR_FMT, 25, ns.Fmt.Duration(st.curTime)))
  T.no(Shown(ch.strip.fs3), "no time left")
  T.ok(Shown(ch.marker), "the current level's top line")
  T.eq({ st.sel, st.nCols }, { 25, 25 })
  for k = 1, 25 do T.no(ch.cols[k].gOn, k .. ": no ghost") end
  T.eq(CountBuilds(ns, function() Stub.Advance(600) end), 0, "live: no rebuild")
  -- XP back on: a projection
  Stub.player.xpDisabled = false
  Stub.Fire("ENABLE_XP_GAIN")
  Stub.Advance(10)
  T.eq({ st.xpOff, st.estOK }, { false, true })
  T.eq(Text(ch.chips[7].label), format(L.LV_TOP_IN_FMT, 60))
end)

-- stats-capped-alt-projection: another character stuck at a server cap (char.capLevel, its
-- level) shows the cap as the current character does, no projection to level 60.
T.test("chart: another character at a recorded server cap shows the cap, no projection", function()
  local ns = Start()
  for _ = 1, 3 do Stub.KillNoXP() end
  T.eq(ns.char.capLevel, 20)
  local rec = Alt(ns, 20)
  ns.Window.Show("levels", rec.guid)
  local ch = Chart()
  local L = ns.L
  T.eq({ ch.state.char, ch.state.isCur, ch.state.status }, { rec, false, "cap" })
  T.eq({ Text(ch.chips[7].label), Text(ch.chips[7].value) }, { L.CAP_SHORT, format(L.LV_CAP_LEVEL_FMT, 20) })
  T.eq(Text(ch.strip.share), format(L.LV_CAP_FMT, 20))
  T.eq(ch.state.nCols, 20, "no ghost to 59")
  -- a cap that is not its level any more (it went on): the projection
  rec.level = 21
  ns.Window.Refresh()
  T.eq(ch.state.status, "ok")
end)

-- stats-missing-xp-levels-dropped: levels to play without a known XP size (a max level
-- above 60): the projection is a lower bound ("+"), the strip shows no share.
T.test("chart: levels without an XP size make the projection a lower bound ('+'), no share", function()
  local ns = Start({ top = 70 })
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt, st = ns.L, ns.Fmt, ch.state
  local fut = {}
  local _, xp, max, rest, valid = ns.Tracker.GetXPInfo()
  ns.Stats.FutureLevels(ns.char, ns.db, 0, { level = 20, xp = xp, max = max, rest = rest, valid = valid, top = 70,
    sync = ns.Tracker.GetSync(), now = GetTime() }, fut)
  T.eq({ fut.status, fut.missing }, { "ok", 10 })
  T.ok(st.partial)
  T.eq(Text(ch.chips[7].label), format(L.LV_TOP_IN_FMT, 70))
  T.eq(Text(ch.chips[7].value), Fmt.ETA(fut.total) .. "+")
  T.eq(Text(ch.strip.fs3), format(L.LV_LEFT_FMT, Fmt.ETA(fut.total) .. "+"))
  T.eq(Text(ch.strip.share), "", "no share")
  T.eq(CountBuilds(ns, function() Stub.Advance(600) end), 0, "live: no rebuild")
  T.eq(Text(ch.strip.share), "")
end)

-- tests-alt-no-w0: another character not logged in since this version on a client with the
-- PvP API (no char.pvp, no w0): world PvP reads "...", "not measured yet", no error.
T.test("chart: another character without w0 (world PvP not measured yet): '...' and its note", function()
  local ns = Start({ pvp = "forever" })
  T.ok(ns.Pvp.Available())
  local rec = Alt(ns, 16)
  rec.pvp = nil
  ns.Window.Show("levels", rec.guid)
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  local seg = {}
  ns.Stats.LevelSegments(rec.life, 0, seg)
  T.eq(Text(ch.chips[4].sub), format(L.LV_PVP_SUB_FMT, Fmt.Duration(seg.bg), L.DOTS))
  Stub.RunScript(ch.chips[4].frame, "OnEnter")
  local lines = TipLines()
  T.eq(Line(lines, L.LV_WPVP_LONG)[2], L.DOTS)
  T.ok(HasText(lines, L.LV_WPVP_NONE), "not measured yet")
  T.no(HasText(lines, L.LV_WPVP_NO_CLIENT))
  Stub.RunScript(ch.chips[4].frame, "OnLeave")
  T.eq(#Stub.errors, 0)
end)

-- tests-sel-reset-char: another character through the view list (SetView, no Show): the
-- selection goes to its current level.
T.test("chart: switching to another character selects its current level", function()
  local ns = Start()
  local rec = Alt(ns, 16)
  ns.Window.Show("levels")
  local ch = Chart()
  ch.cols[12].hit:Click("LeftButton")
  T.eq(ch.state.sel, 12)
  ns.Window.SetView(rec.guid)
  T.eq(ch.state.char, rec)
  T.eq(ch.state.sel, 16, "the other character's current level")
  T.eq(Detail().level, 16)
end)

-- tests-untracked-excess (chart): the current level's record behind the server's level
-- time: the excess is "untracked", the bar is the time shown.
T.test("chart: the current level's server time above its parts goes to untracked", function()
  local ns = Start()
  ns.Window.Show("levels")
  local s20 = ns.char.levels[20].s
  local k = (s20.w or 0) >= 600 and "w" or "u"
  s20[k] = s20[k] - 600                 -- the record lags the server's level time
  ns.Window.Refresh()
  local ch = Chart()
  local c = ch.cols[20]
  local t = ns.Stats.LevelTime(ns.char, 20, 0, ns.Tracker.GetSync(), GetTime())
  local seg = {}
  ns.Stats.LevelSegments(ns.char.levels[20], 0, seg)
  T.near(t - ns.Stats.Sum(ns.char.levels[20], 0), 600, 2, "600 s not in the record")
  T.near(c.total, t, 1, "the bar is the level's time")
  T.near(c.val[12], (seg.untracked or 0) + 600, 2, "the excess is untracked")
end)

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------

T.test("chart: colours from the theme's gauge colours, a switch restyles, a recolour does nothing", function()
  local ns = Start({ theme = "futuriste" })
  ns.Window.Show("levels")
  local ch = Chart()
  local function Gauge()
    local th = ns.Themes.Active()
    local g = th.tt and th.tt.gauge
    return (g and g.colors) or ns.Themes.CLASSIC_GAUGE.colors
  end
  local function Check(key)
    local gc = Gauge()
    local ui = ns.Themes.Active().ui
    local c = ch.cols[15]
    local r, _, b = c.seg[1]:GetVertexColor()
    T.near(r, gc.world[1], 1e-6, key .. ": world")
    T.near(b, gc.world[3], 1e-6)
    r = c.seg[3]:GetVertexColor()
    T.near(r, gc.dungeon[1], 1e-6, key .. ": dungeon")
    r = ch.cols[17].seg[2]:GetVertexColor()
    T.near(r, gc.pvp[1] + (1 - gc.pvp[1]) * 0.45, 1e-6, key .. ": world PvP = pvp toward white")
    local mr, mg = ch.marker:GetVertexColor()
    T.near(mr, ui.accent[1], 1e-6, key .. ": marker accent")
    T.near(mg, ui.accent[2], 1e-6)
    r = ch.cols[30].ghost:GetVertexColor()
    T.near(r, ui.dim[1], 1e-6, key .. ": ghost dim")
    r = select(1, ch.title:GetTextColor())
    T.near(r, ui.accent[1], 1e-6, key .. ": title accent")
  end
  Check("futuriste")
  local n = { build = 0 }
  local orig = ns.LevelChart.Build
  ns.LevelChart.Build = function(...) n.build = n.build + 1 return orig(...) end
  ns.Core.SetSetting("widget.xpColor", { 0.3, 0.6, 0.9 })
  T.eq(n.build, 0, "a user colour change does not rebuild the chart")
  for _, key in ipairs({ "pixel", "actuel", "warlock" }) do
    ns.Core.SetSetting("theme", key)
    T.ok(n.build >= 1, key .. ": rebuilt")
    Check(key)
  end
  ns.LevelChart.Build = orig
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("chart: a theme switch keeps no table of the previous compiled theme (P5)", function()
  local ns = Start({ theme = "futuriste" })
  ns.Window.Show("levels")
  Stub.RunScript(Chart().cols[15].hit, "OnEnter")
  Stub.RunScript(Chart().cols[15].hit, "OnLeave")
  Stub.RunScript(Chart().chips[4].frame, "OnEnter")
  local set = setmetatable({}, { __mode = "k" })
  local stack, permanent = { ns.Themes.Active() }, {}
  local function Mark(t, into)
    local st = { t }
    while #st > 0 do
      local x = table.remove(st)
      if not into[x] then
        into[x] = true
        for k, v in next, x do
          if type(k) == "table" then st[#st + 1] = k end
          if type(v) == "table" then st[#st + 1] = v end
        end
      end
    end
  end
  Mark(ns.Themes.CLASSIC_TT, permanent)
  Mark(ns.Themes.CLASSIC_GAUGE, permanent)
  while #stack > 0 do
    local x = table.remove(stack)
    if not set[x] and not permanent[x] then
      set[x] = true
      for k, v in next, x do
        if type(k) == "table" then stack[#stack + 1] = k end
        if type(v) == "table" then stack[#stack + 1] = v end
      end
    end
  end
  local marked = 0
  for _ in pairs(set) do marked = marked + 1 end
  T.ok(marked > 10, "the compiled theme's tables are marked: " .. marked)
  Stub.RunScript(Chart().chips[4].frame, "OnLeave")
  ns.Core.SetSetting("theme", "pixel")
  ns.Window.Hide()
  ns.Window.Show("levels")
  Stub.Advance(10)
  for _ = 1, 3 do collectgarbage("collect") end
  local left = 0
  for _ in pairs(set) do left = left + 1 end
  T.eq(left, 0, "tables of the previous theme still alive")
end)

---------------------------------------------------------------------------
-- ASCII golden
---------------------------------------------------------------------------

local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4 }   -- HIGHLIGHT ignored

-- What `root` draws, one character per cw x ch px cell: a texture paints the cells whose
-- centre it covers, in layer order; glyph(o) -> a character or nil.
local function Ascii(root, cw, chh, glyph)
  local rl, rb, rw, rh = root:GetRect()
  local W, H = floor(rw / cw), floor(rh / chh)
  local list = {}
  for i, o in ipairs(Stub.regions) do
    local ly = LAYER[rawget(o, "_layer") or "ARTWORK"]
    if rawget(o, "_type") == "Texture" and ly and Under(o, root) and o:IsVisible() then
      list[#list + 1] = { o = o, k = (ly * 100 + (rawget(o, "_subLayer") or 0) + 8) * 100000 + i }
    end
  end
  table.sort(list, function(a, b) return a.k < b.k end)
  local grid = {}
  for y = 1, H do
    local row = {}
    for x = 1, W do row[x] = " " end
    grid[y] = row
  end
  for _, e in ipairs(list) do
    local g = glyph(e.o)
    local l, b, w, h = e.o:GetRect()
    if g and l and w > 0 and h > 0 then
      for y = 1, H do
        local cy = rb + rh - (y - 0.5) * chh
        if cy >= b and cy < b + h then
          local row = grid[y]
          for x = 1, W do
            local cx = rl + (x - 0.5) * cw
            if cx >= l and cx < l + w then row[x] = g end
          end
        end
      end
    end
  end
  for y = 1, H do grid[y] = table.concat(grid[y]) end
  return grid
end

local function ByColor(map)
  return function(o)
    local r, g, b, a = o:GetVertexColor()
    if r == nil or (a ~= nil and a <= 0) then return nil end
    for i = 1, #map do
      local c = map[i][1]
      if math.abs(r - c[1]) < 1e-6 and math.abs(g - c[2]) < 1e-6 and math.abs(b - c[3]) < 1e-6
          and (map[i][3] == nil or math.abs((a or 1) - map[i][3]) < 1e-6) then
        return map[i][2]
      end
    end
    return nil
  end
end

T.test("chart: ASCII golden of a small fixed data set (top 12, level 8)", function()
  local ns = Start({ level = 8, top = 12, xp = 1000, seed = false, levelPlayed = 1800, total = 30000 })
  local char = ns.char
  -- 1 none; 2 world 1800; 3 world 1200 + dungeon 1200; 4 world 900 + flight 900; 5 world 2400
  -- + dead 600; 6 world 1500 + battleground 900 (+ world PvP 300 of the world); 7 world 3000
  char.levels[1] = nil
  char.levels[2] = { s = { w = 1800 }, d = 0, xp = 0 }
  char.levels[3] = { s = { w = 1200, d = 1200 }, d = 0, xp = 0 }
  char.levels[4] = { s = { w = 900, t = 900 }, d = 0, xp = 0 }
  char.levels[5] = { s = { w = 2400, x = 600 }, d = 1, xp = 0 }
  char.levels[6] = { s = { w = 1500, p = 900 }, pw = 300, d = 0, xp = 0 }
  char.levels[7] = { s = { w = 3000 }, d = 0, xp = 0 }
  ns.Window.Show("levels")
  local ch = Chart()
  T.eq({ ch.state.top, ch.state.level, ch.state.nCols }, { 12, 8, 11 })
  local gc = ns.Themes.CLASSIC_GAUGE.colors
  local dim = ns.Themes.Active().ui and ns.Themes.Active().ui.dim or ns.C.COLORS.dim
  local wp = { gc.pvp[1] + (1 - gc.pvp[1]) * 0.45, gc.pvp[2] + (1 - gc.pvp[2]) * 0.45, gc.pvp[3] + (1 - gc.pvp[3]) * 0.45 }
  local pic = Ascii(ch.plot, 8, 20, ByColor({
    { gc.world, "W" }, { gc.dungeon, "D" }, { gc.pvp, "B" }, { wp, "V" }, { gc.taxi, "F" }, { gc.dead, "X" },
    { dim, "g", 0.25 }, { dim, "-", 0.9 }, { dim, ".", 0.6 }, { dim, "u", 1 },
  }))
  if os.getenv("TP_ASCII") then
    for _, l in ipairs(pic) do print("|" .. l .. "|") end
  end
  -- 8 x 20 px cells (the plot: 598 - 58 = 540 px, 67 cells); W world, D dungeon, F flight,
  -- X dead, B battlegrounds (world PvP, 300 s of level 6, is under half a cell), u untracked
  -- (the current level's time before the install, ui.dim), g ghosts (the remaining estimate
  -- of 8 on top of it, then 9 .. 11); the 2 px stub of level 1 covers no cell centre
  local golden = {
    "                                                                   ",
    "                                                                   ",
    "                                   gggg                            ",
    "                                   gggg                            ",
    "                                   gggg                            ",
    "                                   gggg                            ",
    "                                   gggg                            ",
    "                                   gggg                            ",
    "                                   gggg           gggg             ",
    "                                   gggg gggg gggg gggg             ",
    "                                   gggg gggg gggg gggg             ",
    "                                   gggg gggg gggg gggg             ",
    "          DDDD      WWWW BBBB WWWW gggg gggg gggg gggg             ",
    "     WWWW DDDD FFFF WWWW BBBB WWWW uuuu gggg gggg gggg             ",
    "     WWWW WWWW FFFF WWWW WWWW WWWW uuuu gggg gggg gggg             ",
    "     WWWW WWWW WWWW WWWW WWWW WWWW uuuu gggg gggg gggg             ",
  }
  T.eq(pic, golden, "plot")
end)

-- Only one of the filter's parts has time on the bar (always so for world, flight,
-- professions, dead; instances or PvP when one of their two parts is empty): that part's row
-- moves under the title, its label in the part's colour and its value in accent, instead of
-- coming twice (the accent line, then the same part in the list). With two parts that have
-- time (instances at 12, PvP at 17), the accent line and every part below.
T.test("chart: a one-part filter's row moves under the title instead of coming twice", function()
  local ns = Start()
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  local c = ch.cols[15]
  local function Count(lines, label)
    local n = 0
    for _, l in ipairs(lines) do if l[1] == label then n = n + 1 end end
    return n
  end
  -- the part's colour, read on the unfiltered tooltip
  Stub.RunScript(c.hit, "OnEnter")
  local deadColor
  for i, l in ipairs(GameTooltip._lines) do
    if l[1] == L.BD_DEAD then deadColor = GameTooltip._colors[i] end
  end
  Stub.RunScript(c.hit, "OnLeave")
  T.ok(deadColor ~= nil)
  local accent = ns.Themes.Active().ui and ns.Themes.Active().ui.accent or ns.C.COLORS.accent
  ch.filters[7].btn:Click("LeftButton")              -- dead or a ghost
  Stub.RunScript(c.hit, "OnEnter")
  local lines = TipLines()
  T.eq(lines[2], { L.BD_DEAD, format(L.LV_PART_FMT, Fmt.Duration(240), Fmt.Percent(240 / c.sumAll)) },
    "the dead row right under the title")
  T.eq(Count(lines, L.BD_DEAD), 1, "once")
  local col = GameTooltip._colors[2]
  T.near(col[1], deadColor[1], 1e-6, "label in the part's colour")
  T.near(col[2], deadColor[2], 1e-6)
  T.near(col[4], accent[1], 1e-6, "value in accent")
  T.eq(Line(lines, L.LV_PLAYED)[2], Fmt.Duration(c.sumAll), "the whole level below")
  T.ok(Line(lines, L.BD_WORLD) ~= nil and Line(lines, L.LV_SEG_BG) ~= nil, "the other parts below")
  Stub.RunScript(c.hit, "OnLeave")
  -- world: the same
  ch.filters[2].btn:Click("LeftButton")
  Stub.RunScript(c.hit, "OnEnter")
  lines = TipLines()
  T.eq(lines[2][1], L.BD_WORLD)
  T.eq(Count(lines, L.BD_WORLD), 1, "world once")
  Stub.RunScript(c.hit, "OnLeave")
  -- the part's colour (unfiltered tooltip of 12: dungeons and a raid; of 17: battlegrounds
  -- and world PvP)
  local function ColorOf(column, label)
    Stub.RunScript(column.hit, "OnEnter")
    local rgb
    for i, l in ipairs(GameTooltip._lines) do
      if l[1] == label then rgb = GameTooltip._colors[i] end
    end
    Stub.RunScript(column.hit, "OnLeave")
    return rgb
  end
  ch.filters[1].btn:Click("LeftButton")
  local dungeonColor = ColorOf(ch.cols[12], L.BD_DUNGEON)
  local bgColor = ColorOf(ch.cols[17], L.LV_SEG_BG)
  T.ok(dungeonColor ~= nil and bgColor ~= nil)
  -- instances at 15: dungeons only, the dungeon row under the title, once (review C-1)
  ch.filters[3].btn:Click("LeftButton")
  Stub.RunScript(c.hit, "OnEnter")
  lines = TipLines()
  T.eq(lines[2], { L.BD_DUNGEON, format(L.LV_PART_FMT, Fmt.Duration(1200), Fmt.Percent(1200 / c.sumAll)) },
    "instances, dungeons only: the dungeon row under the title")
  T.near(GameTooltip._colors[2][1], dungeonColor[1], 1e-6, "in the dungeon colour")
  T.near(GameTooltip._colors[2][4], accent[1], 1e-6, "value in accent")
  T.eq(Count(lines, L.BD_DUNGEON), 1, "dungeons once")
  T.eq(Count(lines, L.LV_F_INST), 0, "no instances line")
  Stub.RunScript(c.hit, "OnLeave")
  -- instances at 12: dungeons and a raid, the accent line and both rows below
  Stub.RunScript(ch.cols[12].hit, "OnEnter")
  lines = TipLines()
  T.eq(lines[2][1], L.LV_F_INST)
  T.near(GameTooltip._colors[2][1], accent[1], 1e-6, "several parts: label in accent")
  T.eq({ Count(lines, L.BD_DUNGEON), Count(lines, L.BD_RAID) }, { 1, 1 }, "both rows stay")
  Stub.RunScript(ch.cols[12].hit, "OnLeave")
  -- PvP at 15: battlegrounds only (no world PvP before 16), the same
  ch.filters[4].btn:Click("LeftButton")
  Stub.RunScript(c.hit, "OnEnter")
  lines = TipLines()
  T.eq(lines[2][1], L.LV_SEG_BG, "PvP, battlegrounds only: the battleground row under the title")
  T.near(GameTooltip._colors[2][1], bgColor[1], 1e-6, "in the battleground colour")
  T.eq(Count(lines, L.LV_SEG_BG), 1, "battlegrounds once")
  Stub.RunScript(c.hit, "OnLeave")
  -- PvP at 17: both parts, the accent line
  Stub.RunScript(ch.cols[17].hit, "OnEnter")
  lines = TipLines()
  T.eq(lines[2][1], L.BD_PVP)
  T.eq({ Count(lines, L.LV_SEG_BG), Count(lines, L.LV_SEG_WPVP) }, { 1, 1 }, "both rows stay")
  Stub.RunScript(ch.cols[17].hit, "OnLeave")
end)

-- A non-zero share that rounds to 0 % reads "<1%", as on the level sheet (review C-2): the
-- filter's line under the title and the rows of the list.
T.test("chart: a share under half a percent reads <1%, never 0%", function()
  local ns = Start()
  local s15 = ns.char.levels[15].s
  s15.w = 60000                       -- a long level: 2 minutes dead are 0.2 %
  s15.x = 120
  ns.Window.Show("levels")
  local ch = Chart()
  local L, Fmt = ns.L, ns.Fmt
  local c = ch.cols[15]
  local lt = format(L.LV_LT_FMT, Fmt.PercentInt(1))
  local want = format(L.LV_PART_FMT, Fmt.Duration(120), lt)
  T.ok(120 / c.sumAll < 0.005, "under half a percent")
  Stub.RunScript(c.hit, "OnEnter")
  T.eq(Line(TipLines(), L.BD_DEAD)[2], want, "unfiltered: the dead row")
  Stub.RunScript(c.hit, "OnLeave")
  ch.filters[7].btn:Click("LeftButton")
  Stub.RunScript(c.hit, "OnEnter")
  local lines = TipLines()
  T.eq(lines[2], { L.BD_DEAD, want }, "dead filter: the line under the title")
  local zero = format(L.LV_PART_FMT, "", Fmt.PercentInt(0))         -- " · 0%"
  for _, l in ipairs(lines) do
    local r = l[2] or ""
    T.no(r:sub(-#zero) == zero, "never 0%: " .. r)
  end
  Stub.RunScript(c.hit, "OnLeave")
end)
