-- tests/test_level_detail.lua - the detail sheet of the Levels tab (LevelDetail.lua, spec
-- section 5), shown by the chart (tests/test_level_chart.lua has the chart and the sheet's
-- header per kind): a completed level (status date, the six figure cards with the
-- estimate made at its start and how the level went, the time breakdown's bar of the
-- inner width and its rows longest first, the Flight row always, the XP split, the zones
-- and instances), the level in progress (projection card, untracked excess, live cards
-- with keys, no SetPoint, nothing allocated), the approximation notes and "~" (partial,
-- rebuilt, rebuilt part, server gap, stall) and the exclusions' label, an upcoming level
-- (estimate, XP to earn, reached in), no record, the PvP row's tooltip (battlegrounds
-- without their AFK time, other ones, world PvP and its notes per Stats.WorldPvpState and
-- client), the scroll content's height and its reset, the themes (colours, ApplyTheme,
-- P5) and no region created by a second cycle. The review fixes: seven instances in a
-- level (none listed as a zone), "<1%" for a share that rounds to 0, the estimate's
-- verdict under the exclusions it was taken with (etaM), the level in progress following
-- a flight, a battleground and a death live as a rebuild draws it (rows, bar, total,
-- Deaths card; a row more lays the sheet out again), the live steps of the chart and the
-- sheet under exclusions (mask 7) with the projection moving live and a server cap found
-- live, the current level's untracked excess, and the upcoming level's basis line
-- (recent levels or XP rate).
local Stub, T = ...

local format, floor = string.format, math.floor

local T0 = 1700000000
local BG1, BG2 = "i489", "i529"
local DUN, RAID, ORG = "i389", "i409", 1454
-- LevelDetail's layout (its constants)
local PAD, IW, CARD_W, CARD_H, CARD_GAP, VAL_W, ZONE_H = 12, 348, 170, 46, 8, 64, 22

---------------------------------------------------------------------------
-- Fixture (tests/test_level_chart.lua's, with XP, estimates, zones and approximations)
---------------------------------------------------------------------------

-- Level records: none for 1 and 2 (before the install), 3 partial, 4 rebuilt after a crash,
-- 5 .. level - 1 played with every kind of time (world PvP from 16, battlegrounds from 15),
-- their XP split 60 / 30 / 10 % of the level; 12 has a capital, a dungeon and a raid and was
-- estimated at 5000 s (it took 6050), 13 a rebuilt part (600 s) and an estimate of 5000 s
-- (it took 3650), 14 a server time 500 s longer than tracked (start extrapolated) and an
-- estimate 30 s above, 16 600 s without an XP gain.
local function LevelRec(l)
  if l <= 2 then return nil end
  if l == 3 then
    return { partial = true, s = { u = 1500, w = 300 }, d = 0, xp = 0, t1 = T0 + 4 * 3600, eta = 100 }
  end
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
  local max = Stub.xpTable[l]
  local xa, xq = floor(max * 0.6), floor(max * 0.3)
  local r = { s = s, pw = (l >= 16) and 120 or nil, d = (l % 5 == 0) and 2 or 0, t0 = T0 + l * 3600,
              t1 = T0 + (l + 1) * 3600 - 1, z = z, xp = max, xa = xa, xq = xq, xr = max - xa - xq, max = max }
  if l == 12 then
    z[1411].s.w = s.w - 200
    z[ORG] = { s = { c = 200 } }
    z[DUN] = { s = { d = 1200 } }
    z[RAID] = { s = { r = 900 } }
    r.eta = 5000
  elseif l == 13 then
    r.est, r.es, r.eta = 600, { w = 600 }, 5000
  elseif l == 14 then
    r.eta = 3750 + 30
    r.srvStart, r.srvEnd, r.srvStartEst = 50000, 50000 + 3750 + 500, true
  elseif l == 16 then
    r.xs = { w = 600 }
  end
  return r
end

local function AddInto(dst, src)
  for k, v in pairs(src) do dst[k] = (dst[k] or 0) + v end
end

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
  char.zones[DUN] = { name = "Ragefire Chasm", s = { d = 1200 } }
  char.zones[RAID] = { name = "Molten Core", s = { r = 900 } }
  char.pvp = char.pvp or {}
  char.pvp.w0 = T0 + floor(15.5 * 3600)
end

local function Start(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false })
  Stub.theme = opts.theme or "actuel"
  local p = Stub.player
  p.level = opts.level or 20
  p.xp = opts.xp or 9000
  p.max = Stub.xpTable[p.level] or 23200
  Stub.server.total = opts.total or 400000
  Stub.server.levelPlayed = opts.levelPlayed or 40000
  if opts.pvp then Stub.SetPvpAPI(opts.pvp) end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  ns.Core.SetSetting("widget.locked", true)
  Stub.Advance(10)
  Seed(ns, p.level)
  return ns
end

local function Frame() return rawget(_G, "TruePlayedStatsFrame") end
local function Chart() return Frame().tp.chart end
local function Detail() return Frame().tp.detail end
local function Shown(r) return r ~= nil and r:IsShown() and true or false end
local function Text(fs) return rawget(fs, "_text") end

local function Click(k)
  Chart().cols[k].hit:Click("LeftButton")
  return Detail()
end

-- The LevelHistory row of level k under the mask (the sheet's figures).
local function RowOf(ns, k, mask)
  local rows = ns.Stats.LevelHistory(ns.char, mask or 0, ns.Tracker.GetSync(), GetTime(), {})
  for _, r in ipairs(rows) do
    if r.level == k then return r end
  end
  return nil
end

local function Card(c)
  return { Text(c.label), Text(c.value), Text(c.sub) }
end

-- The shown approximation notes.
local function Notes(dt)
  local out = {}
  for j = 1, dt.nNotes do
    T.ok(Shown(dt.notes[j]), "note " .. j .. " shown")
    out[j] = Text(dt.notes[j])
  end
  for j = dt.nNotes + 1, #dt.notes do T.no(Shown(dt.notes[j]), "note " .. j .. " hidden") end
  return out
end

-- The breakdown rows: { label, hint, value, percent }.
local function Rows(dt)
  local out = {}
  for j = 1, dt.time.n do
    local r = dt.time.rows[j]
    T.ok(Shown(r.label) and Shown(r.value) and Shown(r.sq), "row " .. j .. " shown")
    out[j] = { Text(r.label), Text(r.hint), Text(r.value), Text(r.pct) }
  end
  for j = dt.time.n + 1, #dt.time.rows do T.no(Shown(dt.time.rows[j].label), "row " .. j .. " hidden") end
  return out
end

-- The zone rows: { name, time }.
local function Zones(dt)
  local out = {}
  for j = 1, dt.nZones do
    local z = dt.zones[j]
    T.ok(Shown(z.name) and Shown(z.time), "zone " .. j .. " shown")
    out[j] = { Text(z.name), Text(z.time) }
  end
  for j = dt.nZones + 1, #dt.zones do T.no(Shown(dt.zones[j].name), "zone " .. j .. " hidden") end
  return out
end

-- The shown parts of a chained bar: { index, width } left to right, each on the right of
-- the previous one (the first on the content).
local function Bar(segs, n, content)
  local out, before = {}, nil
  for i = 1, n do
    local t = segs[i]
    if t and t:IsShown() then
      out[#out + 1] = { i, t:GetWidth() }
      local _, rel, relPoint = t:GetPoint(1)
      if before then
        T.eq({ rel, relPoint }, { before, "TOPRIGHT" }, "part " .. i .. " after the previous one")
      else
        T.eq(rel, content, "the first part on the content")
      end
      before = t
    end
  end
  return out
end

local function Width(parts)
  local w = 0
  for _, e in ipairs(parts) do w = w + e[2] end
  return w
end

local function Y(r)
  return -select(5, r:GetPoint(1))
end

local function NearColor(fsOrTex, c, what)
  local r, g, b
  if fsOrTex.GetTextColor and rawget(fsOrTex, "_type") == "FontString" then
    r, g, b = fsOrTex:GetTextColor()
  else
    r, g, b = fsOrTex:GetVertexColor()
  end
  T.near(r, c[1], 1e-6, what .. " (r)")
  T.near(g, c[2], 1e-6, what .. " (g)")
  T.near(b, c[3], 1e-6, what .. " (b)")
end

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

local function Gauge(ns)
  local th = ns.Themes.Active()
  local g = th.tt and th.tt.gauge
  return (g and g.colors) or ns.Themes.CLASSIC_GAUGE.colors
end

---------------------------------------------------------------------------
-- A completed level
---------------------------------------------------------------------------

T.test("detail: a completed level: header, cards, time breakdown, XP split, zones and instances", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt, Stats, C = ns.L, ns.Fmt, ns.Stats, ns.C
  local dt = Click(12)
  local row = RowOf(ns, 12)
  T.eq(Text(dt.title), format(L.LEVEL_SPAN_FMT, 12, 13))
  T.eq(Text(dt.status), format(L.LD_DONE_FMT, Fmt.DateTime(T0 + 13 * 3600 - 1)))
  T.eq(Notes(dt), {}, "no approximation note")
  -- cards: Played, Server, Estimated at start (it took 1050 s more), Total, XP/h, Deaths
  T.eq(Stats.Sum(ns.char.levels[12], 0), 6050)
  local c = dt.cards
  T.eq(Card(c.played), { L.LV_PLAYED, Fmt.DurationFull(6050), L.LV_SERVER_SUB })
  T.eq(Card(c.server), { L.TT_SERVER, L.DOTS, L.LV_SERVER_SUB }, "no server split for this level")
  T.eq(Card(c.eta), { L.LD_ETA, Fmt.Duration(5000), format(L.LD_MORE_FMT, Fmt.Duration(1050)) })
  NearColor(c.eta.sub, C.COLORS.warn, "more than expected: warn")
  T.eq(dt.eta, c.eta.value, "tp.detail.eta: the estimate's value")
  T.ok(row.cum ~= nil)
  -- the time until level 13 was reached, in the title's notation ("level 1 » 13"; the
  -- Played chip's "levels 1 to 20" counts the level in progress)
  T.eq(Card(c.cum), { L.LD_CUM, Fmt.DurationFull(row.cum), format(L.LD_CUM_SUB_FMT, 13) })
  T.eq(Card(c.xph), { L.TT_XPH, row.xph and Fmt.Rate(row.xph) or L.DOTS, "" })
  T.eq(Card(c.deaths), { L.TT_DEATHS, "0", L.LD_NONE })
  -- 2 x 3 grid: Played | Server, Estimate | Total, XP/h | Deaths
  for i, key in ipairs({ "played", "server", "eta", "cum", "xph", "deaths" }) do
    local f = c[key].frame
    T.ok(Shown(f), key .. " shown")
    local _, rel, _, x, y = f:GetPoint(1)
    T.eq(rel, dt.content)
    T.eq(x, PAD + ((i - 1) % 2) * (CARD_W + CARD_GAP), key .. ": column")
    T.eq(y, select(5, c.played.frame:GetPoint(1)) - floor((i - 1) / 2) * (CARD_H + CARD_GAP), key .. ": row")
  end
  -- the breakdown: the bar fills the inner width, its parts in the chart's order and colours
  local tm = dt.time
  T.eq(Text(tm.title), L.LD_TIME)
  T.eq(Text(tm.right), format(L.LD_TOTAL_FMT, Fmt.DurationFull(6050)))
  T.eq(tm.total, 6050)
  local parts = Bar(tm.segs, 12, dt.content)
  T.eq(Width(parts), IW, "the parts fill the bar")
  local idx = {}
  for _, e in ipairs(parts) do idx[#idx + 1] = e[1] end
  T.eq(idx, { 1, 3, 4, 6, 7, 9, 10, 11 }, "world, dungeon, raid, flight, professions, city, inn, AFK")
  local gc = Gauge(ns)
  NearColor(tm.segs[1], gc.world, "world part")
  NearColor(tm.segs[3], gc.dungeon, "dungeon part")
  NearColor(tm.segs[6], gc.taxi, "flight part")
  -- the rows: longest first (ties in the fixed order), the Flight row, no PvP row
  local function R(key, v) return { L[key], "", Fmt.DurationFull(v), Fmt.Percent(v / 6050) } end
  T.eq(Rows(dt), { R("BD_WORLD", 2700), R("BD_DUNGEON", 1200), R("BD_RAID", 900), R("TT_PROF", 400),
    R("LV_FLIGHT", 300), R("BD_CITY", 200), R("BD_AFK", 200), R("BD_INN", 150) })
  NearColor(tm.rows[2].sq, gc.dungeon, "the row's square: its part's colour")
  T.eq(tm.pvp, nil, "no PvP at 12")
  T.no(Shown(dt.pvpHit), "no PvP hover area")
  for j = 2, tm.n do T.eq(Y(tm.rows[j].label) - Y(tm.rows[j - 1].label), 17, "rows 17 px apart") end
  -- the XP: gained / size, 60 / 30 / 10 %
  local max = Stub.xpTable[12]
  local xa, xq = floor(max * 0.6), floor(max * 0.3)
  local xp = dt.xp
  T.eq(Text(xp.title), L.LD_XP)
  T.eq(Text(xp.right), format(L.LD_XP_FMT, Fmt.Number(max), Fmt.Number(max)))
  T.eq(Width(Bar(xp.segs, 3, dt.content)), IW)
  local want = { { L.LD_XP_MOBS, xa }, { L.LD_XP_QUESTS, xq }, { L.LD_XP_RESTED, max - xa - xq } }
  for i = 1, 3 do
    local col = xp.cols[i]
    T.eq({ Text(col.label), Text(col.value), Text(col.pct) },
      { want[i][1], Fmt.Number(want[i][2]), Fmt.Percent(want[i][2] / max) }, "XP column " .. i)
  end
  local th = ns.Themes.Active()
  NearColor(xp.segs[1], th.colors.xp, "mobs: the theme's XP colour")
  NearColor(xp.segs[2], gc.city, "quests: the gauge city colour")
  NearColor(xp.segs[3], th.colors.rested, "rested: the theme's rested colour")
  -- zones (the instances aside, the capital marked), then the instances with their kind
  T.eq(Text(dt.zonesTitle), L.LD_ZONES)
  T.eq(Zones(dt), {
    { "Durotar", Fmt.DurationFull(3000) },
    { "Orgrimmar " .. L.CITY_MARK, Fmt.DurationFull(200) },
    { format(L.INST_ROW_FMT, "Ragefire Chasm", L.KIND_DUNGEON), Fmt.DurationFull(1200) },
    { format(L.INST_ROW_FMT, "Molten Core", L.KIND_RAID), Fmt.DurationFull(900) },
  })
  T.no(Shown(dt.zonesEmpty))
  local zr = dt.zones
  local room = IW - VAL_W - 8
  T.eq(zr[1].bar:GetWidth(), room, "the longest row: the full bar")
  T.eq(zr[3].bar:GetWidth(), floor(1200 / 3000 * room + 0.5), "proportional")
  NearColor(zr[1].bar, gc.world, "zone bar: world")
  NearColor(zr[2].bar, gc.city, "capital bar: city")
  NearColor(zr[3].bar, gc.dungeon, "dungeon bar")
  NearColor(zr[4].bar, gc.raid, "raid bar")
  for j = 2, 4 do T.eq(Y(zr[j].name) - Y(zr[j - 1].name), ZONE_H) end
  -- upcoming and no-record parts hidden
  T.no(Shown(dt.up.frame))
  T.ok(dt.norec == nil or not Shown(dt.norec))
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("detail: the estimate card: less than expected (good), near it (no sub), none (dots)", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt, C = ns.L, ns.Fmt, ns.C
  local dt = Click(13)
  T.eq(Card(dt.cards.eta), { L.LD_ETA, Fmt.Duration(5000), format(L.LD_LESS_FMT, Fmt.Duration(1350)) })
  NearColor(dt.cards.eta.sub, C.COLORS.good, "less than expected: good")
  dt = Click(14)
  T.eq(Card(dt.cards.eta), { L.LD_ETA, Fmt.Duration(3780), "" }, "within a minute: no sub")
  dt = Click(15)
  T.eq(Card(dt.cards.eta), { L.LD_ETA, L.DOTS, "" }, "no estimate")
  dt = Click(3)
  T.eq(Card(dt.cards.eta), { L.LD_ETA, Fmt.Duration(100), "" }, "a partial level: no comparison")
  -- the deaths card: 2 deaths and their dead time
  dt = Click(15)
  T.eq(Card(dt.cards.deaths), { L.TT_DEATHS, "2", format(L.LV_DEAD_SUB_FMT, Fmt.DurationFull(240)) })
end)

T.test("detail: the Flight row is always listed (a dash without flight); a level without zones", function()
  local ns = Start()
  ns.char.levels[13].s.t = nil
  ns.char.levels[13].z = nil
  ns.Window.Show("levels")
  local L = ns.L
  local dt = Click(13)
  local flight
  for _, r in ipairs(Rows(dt)) do
    if r[1] == L.LV_FLIGHT then flight = r end
  end
  T.eq(flight, { L.LV_FLIGHT, "", "-", "" }, "Flight: a dash, no percent")
  T.eq(dt.time.rows[dt.time.n].label:GetText(), L.LV_FLIGHT, "and last")
  T.eq(dt.nZones, 0)
  T.ok(Shown(dt.zonesEmpty))
  T.eq(Text(dt.zonesEmpty), L.ROW_ZONES_EMPTY)
  T.eq(dt.content:GetHeight(), Y(dt.zonesEmpty) + 13 + PAD, "the content ends below the empty line")
end)

---------------------------------------------------------------------------
-- Approximations, exclusions
---------------------------------------------------------------------------

T.test("detail: approximation notes and '~' (partial, rebuilt, rebuilt part, server gap, stall)", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local dt = Click(3)
  T.eq(Notes(dt), { L.ROW_PARTIAL_TIP })
  T.eq(Text(dt.cards.played.value), "~" .. Fmt.DurationFull(1800))
  dt = Click(4)
  T.eq(Notes(dt), { L.ROW_REC_TIP })
  T.eq(Text(dt.cards.played.value), "~" .. Fmt.DurationFull(2400))
  dt = Click(13)
  T.eq(Notes(dt), { format(L.ROW_EST_TIP_FMT, Fmt.DurationFull(600)) })
  T.eq(Text(dt.cards.played.value), "~" .. Fmt.DurationFull(3650))
  dt = Click(14)
  T.eq(Notes(dt), { format(L.ROW_GAP_TIP_FMT, Fmt.DurationFull(500)) })
  T.eq(Text(dt.cards.played.value), "~" .. Fmt.DurationFull(3750))
  T.eq(Text(dt.cards.server.value), "~" .. Fmt.DurationFull(3750 + 500), "server start extrapolated: '~'")
  dt = Click(16)
  T.eq(Notes(dt), { format(L.LD_STALL_FMT, Fmt.DurationFull(600)) })
  T.eq(Text(dt.cards.played.value), Fmt.DurationFull(Stats.Sum(ns.char.levels[16], 0)), "a stall is no approximation")
  dt = Click(12)
  T.eq(Notes(dt), {}, "none")
  -- several notes stack below the status line, the cards below them
  local lb = ns.char.levels[14]
  lb.xs = { w = 300 }
  ns.Window.Refresh()
  dt = Click(14)
  T.eq(Notes(dt), { format(L.ROW_GAP_TIP_FMT, Fmt.DurationFull(500)), format(L.LD_STALL_FMT, Fmt.DurationFull(300)) })
  T.ok(Y(dt.notes[1]) > Y(dt.status), "below the status")
  T.ok(Y(dt.notes[2]) > Y(dt.notes[1]), "stacked")
  T.ok(Y(dt.cards.played.frame) > Y(dt.notes[2]), "the cards below the notes")
end)

T.test("detail: the exclusions: Played sub, figures and breakdown under the mask", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  ns.Core.SetSetting("exclude.afk", true)
  ns.Core.SetSetting("exclude.city", true)
  local dt = Click(12)
  local mask = ns.GetMask()
  T.eq(mask, 5)
  local sum = Stats.Sum(ns.char.levels[12], mask)
  T.eq(sum, 6050 - 200 - 200, "without the AFK and city time")
  T.eq(Card(dt.cards.played), { L.LV_PLAYED, Fmt.DurationFull(sum), format(L.TT_EXCL_FMT, Stats.MaskLabel(mask)) })
  T.eq(dt.time.total, sum)
  for _, r in ipairs(Rows(dt)) do
    T.no(r[1] == L.BD_AFK or r[1] == L.BD_CITY, "no row for an excluded part: " .. r[1])
  end
  -- the capital: its time excluded, a dash and last of the zones (the instances follow)
  T.eq(Zones(dt), {
    { "Durotar", Fmt.DurationFull(2800) },
    { "Orgrimmar " .. L.CITY_MARK, "-" },
    { format(L.INST_ROW_FMT, "Ragefire Chasm", L.KIND_DUNGEON), Fmt.DurationFull(1200) },
    { format(L.INST_ROW_FMT, "Molten Core", L.KIND_RAID), Fmt.DurationFull(900) },
  })
  NearColor(dt.zones[2].name, ns.Themes.Active().ui.dim, "the excluded zone dimmed")
  T.no(Shown(dt.zones[2].bar), "and without a bar")
end)

---------------------------------------------------------------------------
-- The level in progress, live
---------------------------------------------------------------------------

T.test("detail: the level in progress: projection card, untracked excess, live cards, no SetPoint", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local ch = Chart()
  local dt = Detail()
  T.eq(ch.state.sel, 20)
  local row = RowOf(ns, 20)
  local approx = row.partial or row.rec or row.estF > 0 or (row.gap or 0) > 0
  local function Played() return (approx and "~" or "") .. Fmt.DurationFull(ch.state.curTime) end
  T.eq(Text(dt.cards.played.value), Played())
  local fut = {}
  local _, xp, max, rest, valid = ns.Tracker.GetXPInfo()
  Stats.FutureLevels(ns.char, ns.db, 0, { level = 20, xp = xp, max = max, rest = rest, valid = valid, top = 60,
    sync = ns.Tracker.GetSync(), now = GetTime() }, fut)
  T.eq(fut.status, "ok")
  T.eq(Card(dt.cards.eta), { L.LD_ETA_CUR, Fmt.ETA(ch.state.curTime + fut.cur),
    format(L.LD_LEFT_FMT, Fmt.Duration(fut.cur)) })
  NearColor(dt.cards.eta.sub, ns.Themes.Active().ui.accent, "time left: accent")
  local pfx = row.serverEst and "~" or ""
  T.eq(Text(dt.cards.server.value), pfx .. Fmt.DurationFull(row.server), "the server's level time")
  T.eq(Text(dt.cards.cum.value), Text(ch.chips[1].value), "total since level 1 = the Played chip")
  -- the breakdown: the shown time, its excess over the parts as untracked
  T.near(dt.time.total, ch.state.curTime, 1e-6)
  T.eq(Width(Bar(dt.time.segs, 12, dt.content)), IW)
  -- XP: the reading of the level in progress
  T.eq(Text(dt.xp.right), format(L.LD_XP_FMT, Fmt.Number(xp), Fmt.Number(max)))
  -- live: an hour later the time cards and the total followed, nothing anchored again
  Stub.Advance(600)
  local k0 = Text(dt.cards.played.value)
  local n = CountSetPoint(dt.panel, function() Stub.Advance(3600) end)
  T.eq(n, 0, "no SetPoint in the sheet while the level grows")
  T.ok(Text(dt.cards.played.value) ~= k0, "Played followed")
  T.eq(Text(dt.cards.played.value), Played())
  T.eq(Text(dt.time.right), format(L.LD_TOTAL_FMT, Fmt.DurationFull(ch.state.curTime)))
  T.eq(Text(dt.cards.cum.value), Text(ch.chips[1].value), "Total followed")
  T.eq(Text(dt.cards.server.value), pfx .. Fmt.DurationFull(ch.state.curTime), "Server followed (mask 0: the same time)")
  -- a rebuild of the same sheet anchors nothing either (the first one after the hour may:
  -- an hour without XP adds the stall note, the sections move down)
  ns.Window.Refresh()
  T.eq(Notes(dt)[dt.nNotes], format(L.LD_STALL_FMT, Fmt.DurationFull(ns.Stats.StallTime(ns.char.levels[20], 0))),
    "an hour without XP: the stall note (at the rebuild)")
  n = CountSetPoint(dt.panel, function() ns.Window.Refresh() end)
  T.eq(n, 0, "a rebuild of the same sheet: no SetPoint")
  -- the live step allocates nothing at a moment without a key change
  local LD, char, sync, now = ns.LevelDetail, ns.char, ns.Tracker.GetSync(), GetTime()
  LD.Live(char, 0, sync, now)
  local kb = T.alloc(function() LD.Live(char, 0, sync, now) end, 600)
  T.ok(kb < 0.05, format("LevelDetail.Live x600: %.3f KB", kb))
  -- another level selected: the live step leaves the sheet alone
  dt = Click(12)
  local before = Text(dt.cards.played.value)
  Stub.Advance(3600)
  T.eq(Text(dt.cards.played.value), before, "a completed level does not move")
  T.eq(Stub.onUpdateCount, 0)
end)

-- Request 2026-10-17: the sheet of "Level 18 » 19" read "Total since level 1 - levels 1 to
-- 18" under the summary's "Time played - levels 1 to 19" (which counts level 19 in
-- progress). The card now says what it counts in the title's notation: until level 19 was
-- reached, or for the level in progress up to now.
T.test("detail: 'Total since level 1' reads 'level 1 » 19' for level 18, ', in progress' for the current level", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt = ns.L, ns.Fmt
  T.eq(format(L.LD_CUM_SUB_FMT, 19), "level 1 \194\187 19")
  T.eq(format(L.LD_CUM_SUB_CUR_FMT, 21), "level 1 \194\187 21, in progress")
  local dt = Click(18)
  T.eq(Text(dt.title), format(L.LEVEL_SPAN_FMT, 18, 19))
  T.eq(Card(dt.cards.cum), { L.LD_CUM, Fmt.DurationFull(RowOf(ns, 18).cum), format(L.LD_CUM_SUB_FMT, 19) })
  dt = Click(20)
  T.eq(dt.kind, "cur")
  T.eq(Card(dt.cards.cum), { L.LD_CUM, Text(Chart().chips[1].value), format(L.LD_CUM_SUB_CUR_FMT, 21) })
  -- the summary chip keeps its own label (it counts the level in progress)
  T.eq(Text(Chart().chips[1].sub), format(L.LV_PLAYED_SUB_FMT, 20))
  -- another character's level in progress: up to its last save, the same label
  local rec = Stub.DeepCopy(ns.char)
  rec.guid, rec.name, rec.level = "Player-4619-0BADF00D", "Other", 12
  for l = 13, 20 do rec.levels[l] = nil end
  ns.db.chars[rec.guid] = rec
  ns.Window.Show("levels", rec.guid)
  T.eq(Text(Detail().cards.cum.sub), format(L.LD_CUM_SUB_CUR_FMT, 13))
  Chart().cols[11].hit:Click("LeftButton")
  T.eq(Text(Detail().cards.cum.sub), format(L.LD_CUM_SUB_FMT, 12))
  -- in French
  Stub.Reset()
  Stub.locale = "frFR"
  ns = Start()
  ns.Window.Show("levels")
  T.eq(Text(Click(18).cards.cum.sub), "niveau 1 \194\187 19")
  T.eq(Text(Click(20).cards.cum.sub), "niveau 1 \194\187 21, en cours")
end)

T.test("detail: another character's level in progress is not live", function()
  local ns = Start()
  local rec = Stub.DeepCopy(ns.char)
  rec.guid, rec.name, rec.level = "Player-4619-0BADF00D", "Other", 12
  for l = 13, 20 do rec.levels[l] = nil end
  rec.srv = { total = 123456, at = time() - 7200 }
  ns.db.chars[rec.guid] = rec
  ns.Window.Show("levels", rec.guid)
  local dt = Detail()
  T.eq(dt.level, 12)
  T.eq(dt.kind, "cur")
  local before = { Text(dt.cards.played.value), Text(dt.cards.cum.value), Text(dt.time.right) }
  Stub.Advance(3600)
  T.eq({ Text(dt.cards.played.value), Text(dt.cards.cum.value), Text(dt.time.right) }, before, "not live")
end)

---------------------------------------------------------------------------
-- Upcoming, no record
---------------------------------------------------------------------------

T.test("detail: an upcoming level (estimate, XP to earn, reached in) and a level without a record", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local ch = Chart()
  local dt = Click(30)
  T.eq(dt.kind, "future")
  local up = dt.up
  T.ok(Shown(up.frame))
  T.eq({ Text(up.label), Text(up.value), Text(up.sub) }, { L.LD_EST_DUR, Fmt.ETA(ch.cols[30].est), L.LD_EST_SUB })
  T.eq(Text(up.xp), format(L.LV_XP_EARN_FMT, Fmt.Number(Stats.XPOf(ns.char, ns.db, 30))))
  local fut = {}
  local _, xp, max, rest, valid = ns.Tracker.GetXPInfo()
  Stats.FutureLevels(ns.char, ns.db, 0, { level = 20, xp = xp, max = max, rest = rest, valid = valid, top = 60,
    sync = ns.Tracker.GetSync(), now = GetTime() }, fut)
  local sum = fut.cur
  for l = 21, 30 do sum = sum + fut[l] end
  T.near(up.sum, sum, 1e-6, "the time left in 20, then 21 .. 30")
  T.eq(Text(up.reach), format(L.LD_REACH_FMT, Fmt.Duration(sum)))
  T.eq(dt.nNotes, 0)
  for _, key in ipairs({ "played", "eta", "deaths" }) do T.no(Shown(dt.cards[key].frame), key .. " hidden") end
  T.no(Shown(dt.time.title))
  T.no(Shown(dt.xp.title))
  T.no(Shown(dt.zonesTitle))
  T.eq(dt.content:GetHeight(), Y(up.reach) + 14 + PAD)
  -- the next level: what is left of this one and its own estimate
  Click(21)
  T.near(up.sum, fut.cur + fut[21], 1e-6)
  -- no record
  dt = Click(1)
  T.eq(dt.kind, "none")
  T.ok(Shown(dt.norec))
  T.eq(Text(dt.norec), L.LD_NO_RECORD)
  T.no(Shown(up.frame))
  T.no(Shown(dt.cards.played.frame))
  T.no(Shown(dt.time.title))
  local lines = math.ceil(dt.norec:GetUnboundedStringWidth() / IW)
  T.eq(dt.content:GetHeight(), Y(dt.norec) + math.max(dt.norec:GetStringHeight(), lines * 14) + PAD,
    "its wrapped lines (12 px + 2 each)")
  -- a played level again: the upcoming and no-record parts hidden
  dt = Click(17)
  T.no(Shown(dt.norec))
  T.no(Shown(up.frame))
  T.ok(Shown(dt.cards.played.frame))
end)

---------------------------------------------------------------------------
-- PvP row
---------------------------------------------------------------------------

T.test("detail: the PvP row's tooltip: battlegrounds without their AFK time, other ones, world PvP, notes", function()
  local ns = Start({ pvp = "forever" })
  local L, Fmt = ns.L, ns.Fmt
  local lb = ns.char.levels[17]
  lb.s.P, lb.z[BG1].s.P = 100, 100          -- 100 s AFK in Warsong Gulch: the AFK part
  ns.Window.Show("levels")
  local dt = Click(17)
  local rows = Rows(dt)
  T.eq(rows[2], { L.BD_PVP, L.LD_HOVER, Fmt.DurationFull(720), Fmt.Percent(720 / 4750) }, "PvP = battlegrounds + world")
  T.eq(rows[1][3], Fmt.DurationFull(3080), "World = open world less world PvP")
  T.eq(dt.time.pvp, 2)
  T.ok(Shown(dt.pvpHit))
  T.eq(Y(dt.pvpHit), Y(dt.time.rows[2].label) - 1, "the hover area on the PvP row")
  T.ok(ns.LevelChart.Owns(dt.pvpHit), "LevelChart.Owns: the sheet's hover frame")
  Stub.RunScript(dt.pvpHit, "OnEnter")
  T.eq(GameTooltip:GetOwner(), dt.pvpHit)
  T.ok(GameTooltip:IsShown())
  local lines = TipLines()
  T.eq(lines[1][1], format(L.LD_PVP_TIP_FMT, Fmt.DurationFull(720)))
  T.eq(Line(lines, L.LV_SEG_BG)[2], Fmt.DurationFull(600))
  T.eq(Line(lines, "   Warsong Gulch")[2], Fmt.DurationFull(400), "its AFK time left out")
  T.eq(Line(lines, "   Arathi Basin")[2], Fmt.DurationFull(200))
  T.eq(Line(lines, "   " .. L.LV_BG_OTHER), nil, "nothing else")
  T.eq(Line(lines, L.LV_WPVP_LONG)[2], Fmt.DurationFull(120))
  T.ok(HasText(lines, format(L.LV_WPVP_DEF_FMT, 15)), "definition")
  T.ok(HasText(lines, format(L.LV_WPVP_SINCE_FMT, Fmt.DateTime(T0 + floor(15.5 * 3600)))), "since")
  local gc = Gauge(ns)
  for i, l in ipairs(GameTooltip._lines) do
    if l[1] == L.LV_SEG_BG then T.near(GameTooltip._colors[i][1], gc.pvp[1], 1e-6, "battlegrounds colour") end
  end
  Stub.RunScript(dt.pvpHit, "OnLeave")
  T.no(GameTooltip:IsShown(), "hidden on leave")
  -- battleground time in no listed zone: "Other battlegrounds"
  lb.s.p = 700
  ns.Window.Refresh()
  dt = Detail()
  Stub.RunScript(dt.pvpHit, "OnEnter")
  lines = TipLines()
  T.eq(lines[1][1], format(L.LD_PVP_TIP_FMT, Fmt.DurationFull(820)))
  T.eq(Line(lines, "   " .. L.LV_BG_OTHER)[2], Fmt.DurationFull(100))
  Stub.RunScript(dt.pvpHit, "OnLeave")
  -- 15 began before world PvP was measured, 16 after; measured later than 17: before
  dt = Click(15)
  Stub.RunScript(dt.pvpHit, "OnEnter")
  T.ok(HasText(TipLines(), L.LV_WPVP_PARTIAL), "15: partly measured")
  Stub.RunScript(dt.pvpHit, "OnLeave")
  dt = Click(16)
  Stub.RunScript(dt.pvpHit, "OnEnter")
  T.no(HasText(TipLines(), L.LV_WPVP_PARTIAL) or HasText(TipLines(), L.LV_WPVP_BEFORE), "16: measured")
  Stub.RunScript(dt.pvpHit, "OnLeave")
  ns.char.pvp.w0 = T0 + 30 * 3600
  dt = Click(17)
  Stub.RunScript(dt.pvpHit, "OnEnter")
  lines = TipLines()
  T.ok(HasText(lines, L.LV_WPVP_BEFORE), "17: not measured at this level")
  T.eq(Line(lines, L.LV_WPVP_LONG)[2], L.DOTS, "not measured: dots, never 0")
  -- a click elsewhere then Window.Hide: the tooltip is the window's (Deactivate hides it)
  ns.Window.Hide()
  T.no(GameTooltip:IsShown(), "Window.Hide hides the sheet's tooltip")
end)

T.test("detail: the PvP row on Classic Era (no PvP API), and under a non-native theme", function()
  local ns = Start()
  T.no(ns.Pvp.Available())
  ns.Window.Show("levels")
  local L = ns.L
  local dt = Click(17)
  Stub.RunScript(dt.pvpHit, "OnEnter")
  local lines = TipLines()
  T.eq(Line(lines, L.LV_WPVP_LONG)[2], L.DOTS)
  T.ok(HasText(lines, L.LV_WPVP_NO_CLIENT))
  Stub.RunScript(dt.pvpHit, "OnLeave")
  -- the themed tooltip frame
  Stub.Reset()
  ns = Start({ theme = "futuriste", pvp = "forever" })
  ns.Window.Show("levels")
  dt = Click(17)
  local tf = ns.TooltipFrame.Get(1)
  Stub.RunScript(dt.pvpHit, "OnEnter")
  T.eq(tf:GetOwner(), dt.pvpHit, "the themed frame")
  T.ok(tf:IsShown())
  local found = false
  for i = 1, tf.tp.n do
    local r = tf.tp.rows[i]
    if r.lt == "   Warsong Gulch" then found = r.rt == ns.Fmt.DurationFull(400) end
  end
  T.ok(found, "the battleground rows")
  ns.Core.SetSetting("theme", "pixel")
  T.no(tf:IsShown(), "THEME_CHANGED hides it")
end)

T.test("detail: the chart's PvP chip lists the battlegrounds without their AFK time too", function()
  local ns = Start({ pvp = "forever" })
  local L, Fmt = ns.L, ns.Fmt
  ns.char.zones[BG1].s.P = 500
  ns.char.life.s.P = (ns.char.life.s.P or 0) + 500
  ns.Window.Show("levels")
  local chip = Chart().chips[4].frame
  Stub.RunScript(chip, "OnEnter")
  local lines = TipLines()
  T.eq(Line(lines, L.LV_SEG_BG)[2], Fmt.DurationFull(3300), "battlegrounds: p only (P is AFK)")
  T.eq(Line(lines, "   Warsong Gulch")[2], Fmt.DurationFull(2000), "the row without its AFK time")
  T.eq(Line(lines, "   " .. L.LV_BG_OTHER)[2], Fmt.DurationFull(300))
  Stub.RunScript(chip, "OnLeave")
end)

---------------------------------------------------------------------------
-- Scroll, themes, regions
---------------------------------------------------------------------------

T.test("detail: the scroll content ends below the last section; another sheet scrolls back to its top", function()
  local ns = Start()
  ns.Window.Show("levels")
  local dt = Click(12)
  T.eq(dt.panel:GetWidth(), 400)
  T.eq(dt.scroll:GetScrollChild(), dt.content)
  local last = dt.zones[dt.nZones]
  T.eq(dt.content:GetHeight(), Y(last.name) + ZONE_H + PAD, "the last zone row's bottom + the padding")
  T.eq(dt.height, dt.content:GetHeight())
  T.ok(dt.content:GetHeight() > dt.panel:GetHeight(), "more than the panel: it scrolls")
  dt.scroll:SetVerticalScroll(120)
  ns.Window.Refresh()
  T.eq(dt.scroll:GetVerticalScroll(), 120, "a rebuild of the same sheet keeps the scroll")
  Click(12)
  T.eq(dt.scroll:GetVerticalScroll(), 120, "the same level clicked again keeps it")
  Click(13)
  T.eq(dt.scroll:GetVerticalScroll(), 0, "another level: from its top")
  T.eq(dt.content:GetHeight(), Y(dt.zones[dt.nZones].name) + ZONE_H + PAD)
end)

T.test("detail: colours from the theme, a switch repaints the sheet", function()
  local ns = Start({ theme = "futuriste", pvp = "forever" })
  ns.Window.Show("levels")
  local dt = Click(17)
  local function Check(key)
    local th = ns.Themes.Active()
    local ui, gc = th.ui, Gauge(ns)
    NearColor(dt.title, ui.title, key .. ": title")
    NearColor(dt.status, ui.label, key .. ": status")
    NearColor(dt.cards.played.label, ui.label, key .. ": card label")
    NearColor(dt.cards.played.value, ui.value, key .. ": card value")
    NearColor(dt.time.segs[1], gc.world, key .. ": world part")
    local wp = { gc.pvp[1] + (1 - gc.pvp[1]) * 0.45, gc.pvp[2] + (1 - gc.pvp[2]) * 0.45,
                 gc.pvp[3] + (1 - gc.pvp[3]) * 0.45 }
    NearColor(dt.time.segs[2], wp, key .. ": world PvP part")
    NearColor(dt.xp.segs[1], th.colors.xp, key .. ": XP mobs")
    NearColor(dt.xp.segs[3], th.colors.rested, key .. ": XP rested")
    NearColor(dt.zones[1].bar, gc.world, key .. ": zone bar")
    NearColor(dt.time.rows[1].sq, gc.world, key .. ": row square")
  end
  Check("futuriste")
  for _, key in ipairs({ "pixel", "actuel", "warlock" }) do
    ns.Core.SetSetting("theme", key)
    dt = Detail()
    Check(key)
  end
  -- the colours are the active theme's even before the next rebuild (ApplyTheme repaints)
  ns.LevelDetail.ApplyTheme(ns.Themes.Active().ui)
  Check("ApplyTheme")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("detail: a theme switch keeps no table of the previous compiled theme (P5)", function()
  local ns = Start({ theme = "futuriste", pvp = "forever" })
  ns.Window.Show("levels")
  local dt = Click(17)
  Stub.RunScript(dt.pvpHit, "OnEnter")
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
  Mark(ns.C.COLORS, permanent)
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
  Stub.RunScript(dt.pvpHit, "OnLeave")
  ns.Core.SetSetting("theme", "pixel")
  ns.Window.Hide()
  ns.Window.Show("levels")
  Click(30)
  Click(1)
  Click(17)
  Stub.Advance(10)
  for _ = 1, 3 do collectgarbage("collect") end
  local left = 0
  for _ in pairs(set) do left = left + 1 end
  T.eq(left, 0, "tables of the previous theme still alive")
end)

T.test("detail: every kind of sheet built twice creates no region the second time", function()
  local ns = Start({ pvp = "forever" })
  ns.Window.Show("levels")
  local function Cycle()
    for _, k in ipairs({ 12, 3, 13, 14, 16, 17, 20, 30, 1 }) do
      local dt = Click(k)
      if dt.pvpHit and dt.pvpHit:IsShown() then
        Stub.RunScript(dt.pvpHit, "OnEnter")
        Stub.RunScript(dt.pvpHit, "OnLeave")
      end
    end
    ns.Window.Refresh()
  end
  Cycle()
  local n0 = Created()
  Cycle()
  T.eq(Created(), n0, "no region created by a second cycle")
  T.eq(#Stub.errors, 0)
end)

---------------------------------------------------------------------------
-- Review fixes
---------------------------------------------------------------------------

-- Counts the chart's full rebuilds and the window's Refresh calls while fn runs.
local function CountBuilds(ns, fn)
  local LC, Win = ns.LevelChart, ns.Window
  local build, refresh, nb, nr = LC.Build, Win.Refresh, 0, 0
  LC.Build = function(...) nb = nb + 1 return build(...) end
  Win.Refresh = function(...) nr = nr + 1 return refresh(...) end
  local ok, err = pcall(fn)
  LC.Build, Win.Refresh = build, refresh
  if not ok then error(err, 0) end
  return nb, nr
end

-- The row of a breakdown (Rows) by its label.
local function RowNamed(rows, label)
  for _, r in ipairs(rows) do
    if r[1] == label then return r end
  end
  return nil
end

-- detailrt-1: from the 6th instance of a level on, an instance was listed as an open-world
-- zone (world colour, no kind) and took one of the 8 zone places.
T.test("detail: seven instances in a level: none listed as an open-world zone; the 5 longest, 8 zones kept", function()
  local ns = Start()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local z = ns.char.levels[18].z               -- Durotar 3800 s, Warsong Gulch 400, Arathi Basin 200
  z.i230 = { name = "Blackrock Depths", s = { d = 900 } }
  z.i229 = { name = "Lower Blackrock Spire", s = { d = 800 } }
  z.i329 = { name = "Stratholme", s = { d = 700 } }
  z.i289 = { name = "Scholomance", s = { d = 500 } }
  z.i30 = { name = "Alterac Valley", s = { p = 300 } }
  for i = 1, 8 do z["nZone " .. i] = { s = { w = 50 + 10 * i } } end   -- 8 small zones, 60 .. 130 s
  ns.Window.Show("levels")
  local dt = Click(18)
  local function Name(k) return Stats.ZoneName(k, ns.char.zones[k] or z[k]) end
  local want = { { "Durotar", Fmt.DurationFull(3800) } }
  for i = 8, 2, -1 do want[#want + 1] = { "Zone " .. i, Fmt.DurationFull(50 + 10 * i) } end
  for _, e in ipairs({ { "i230", 900 }, { "i229", 800 }, { "i329", 700 }, { "i289", 500 } }) do
    want[#want + 1] = { format(L.INST_ROW_FMT, Name(e[1]), L.KIND_DUNGEON), Fmt.DurationFull(e[2]) }
  end
  want[#want + 1] = { format(L.INST_ROW_FMT, Name(BG1), L.KIND_PVP), Fmt.DurationFull(400) }
  T.eq(Zones(dt), want, "8 zones (the 8th small one left out), then the 5 longest instances")
  local gc = Gauge(ns)
  for j = 1, 8 do NearColor(dt.zones[j].bar, gc.world, "zone " .. j .. ": world") end
  for j = 9, 12 do NearColor(dt.zones[j].bar, gc.dungeon, "instance " .. j .. ": dungeon") end
  NearColor(dt.zones[13].bar, gc.pvp, "Warsong Gulch: pvp")
  for j = 1, dt.nZones do
    local s = Text(dt.zones[j].name)
    T.no(s == Name("i30") or s == Name(BG2), "the 6th and 7th instances are not zones: " .. s)
  end
end)

-- In-game report (13/10/2026): "Iles des Sombrelances (PvP)" listed twice in "Zones and
-- instances" (1h 35m and <1m): the battleground's first seconds were recorded under its
-- instance key, the rest under its map. One row, the sum, never a zone.
T.test("detail: a battleground under two keys (instance key, then its map) is one row", function()
  local ns = Start()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local z = ns.char.levels[18].z               -- Durotar 3800 s, Warsong Gulch 400, Arathi Basin 200
  local function Name(k) return Stats.ZoneName(k, ns.char.zones[k] or z[k]) end
  local wsgName = Name(BG1)
  z.i9489 = { name = wsgName, s = { p = 30 } }
  ns.Window.Show("levels")
  local dt = Click(18)
  local wsg = format(L.INST_ROW_FMT, wsgName, L.KIND_PVP)
  local found = {}
  for _, r in ipairs(Zones(dt)) do
    if r[1] == wsg or r[1] == wsgName then found[#found + 1] = r end
  end
  T.eq(found, { { wsg, Fmt.DurationFull(430) } }, "one row, the sum of both keys")
end)

-- A share of the level that rounds to 0 % reads "<1%" (as the chart's Flight chip).
T.test("detail: a breakdown row under 0.5 % of the level reads '<1%', never '0%'", function()
  local ns = Start()
  local L, Fmt = ns.L, ns.Fmt
  ns.char.levels[12].s.x = 20                  -- 20 s dead of 6070
  ns.Window.Show("levels")
  local dt = Click(12)
  T.eq(RowNamed(Rows(dt), L.BD_DEAD), { L.BD_DEAD, "", Fmt.DurationFull(20), format(L.LV_LT_FMT, Fmt.PercentInt(1)) })
  T.eq(RowNamed(Rows(dt), L.BD_INN)[4], Fmt.Percent(150 / 6070), "2 %: the percent")
end)

-- stats-eta-verdict-mask-mismatch: "X more / less than expected" compares the estimate with
-- the time under the same exclusions only (row.etaM); an older record (no etaM) keeps it.
T.test("detail: the estimate's verdict only under the exclusions it was taken with (etaM)", function()
  local ns = Start()
  local L, Fmt = ns.L, ns.Fmt
  local lb = ns.char.levels[12]
  lb.etaM = 0
  ns.Window.Show("levels")
  local dt = Click(12)
  T.eq(Card(dt.cards.eta), { L.LD_ETA, Fmt.Duration(5000), format(L.LD_MORE_FMT, Fmt.Duration(1050)) }, "same mask")
  ns.Core.SetSetting("exclude.afk", true)    -- 200 s AFK left out: 5850 s
  dt = Click(12)
  T.eq(ns.GetMask(), 1)
  T.eq(RowOf(ns, 12, 1).etaM, 0)
  T.eq(Card(dt.cards.eta), { L.LD_ETA, Fmt.Duration(5000), "" }, "taken with the AFK: no verdict without it")
  lb.etaM = 1
  ns.Window.Refresh()
  T.eq(Card(dt.cards.eta), { L.LD_ETA, Fmt.Duration(5000), format(L.LD_MORE_FMT, Fmt.Duration(850)) },
    "taken without the AFK: the verdict")
  lb.etaM = nil
  ns.Window.Refresh()
  T.eq(Text(dt.cards.eta.sub), format(L.LD_MORE_FMT, Fmt.Duration(850)), "an older record: as before")
end)

-- detailrt-2, ux-1: the level in progress follows a flight, a battleground and a death
-- without an XP gain (no rebuild): the breakdown's rows (values, percents, order), its bar
-- and total and the Deaths card are what a rebuild draws; a row more lays the sheet out
-- again (the sections below move down), else nothing is anchored again; nothing allocated
-- at a moment without a key change.
T.test("detail: the level in progress follows a flight, a battleground and a death live, as a rebuild", function()
  local ns = Start({ pvp = "forever" })
  local s20 = ns.char.levels[20].s
  s20.u, s20.w = s20.u - 600, (s20.w or 0) + 600     -- 10 min of world already (the server time kept)
  ns.Window.Show("levels")
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local dt = Detail()
  T.eq(Chart().state.sel, 20)
  local lb, seg = ns.char.levels[20], {}
  local function Live() ns.LevelChart.Live(ns.char, 0, ns.Tracker.GetSync(), GetTime()) end
  -- the sheet below the breakdown's title (the notes above it follow at a rebuild: an hour
  -- without XP adds the stall note)
  local function Sheet()
    local y = Y(dt.time.title)
    return { rows = Rows(dt), bar = Bar(dt.time.segs, 12, dt.content), total = Text(dt.time.right),
             deaths = Card(dt.cards.deaths), xpY = Y(dt.xp.title) - y, h = dt.content:GetHeight() - y }
  end
  -- the live sheet at this moment, then a rebuild at the same moment: the same
  local function AsRebuilt(what)
    Live()
    local live = Sheet()
    T.eq(Width(live.bar), IW, what .. ": the bar full")
    ns.Window.Refresh()
    T.eq(live, Sheet(), what .. ": live = rebuilt")
    Stats.LevelSegments(lb, 0, seg)
    return live
  end
  local n0, y0 = dt.time.n, Y(dt.xp.title)
  T.eq(RowNamed(Rows(dt), L.LV_FLIGHT)[3], "-", "no flight yet")
  -- a flight: the Flight row (always listed) grows and passes World (the rows are places:
  -- the order changes their texts, no anchor; the bar's part chained once); no row more
  local sp
  local nb, nr = CountBuilds(ns, function()
    Stub.SetTaxi(true); Stub.Advance(120)
    T.ok(dt.time.segs[6] ~= nil and dt.time.segs[6]:IsShown(), "the bar's flight part")
    T.eq(Text(dt.time.rows[3].label), L.LV_FLIGHT, "below World")
    sp = CountSetPoint(dt.panel, function() Stub.Advance(1680) end)
    Stub.SetTaxi(false); Stub.Advance(5)
  end)
  T.eq({ nb, nr }, { 0, 0 }, "no rebuild")
  T.eq(sp, 0, "no SetPoint while the flight passes World")
  Live()
  Stats.LevelSegments(lb, 0, seg)
  T.ok(seg.taxi >= 1800, "flight time: " .. seg.taxi)
  T.eq(RowNamed(Rows(dt), L.LV_FLIGHT), { L.LV_FLIGHT, "", Fmt.DurationFull(seg.taxi),
    Fmt.Percent(seg.taxi / dt.time.total) }, "Flight row, live")
  T.eq(Text(dt.time.rows[2].label), L.LV_FLIGHT, "above World now")
  T.eq({ dt.time.n, Y(dt.xp.title) }, { n0, y0 }, "no row more, nothing moved")
  AsRebuilt("flight")
  local y1, h1, z1 = Y(dt.xp.title), dt.content:GetHeight(), dt.nZones
  -- a battleground: the PvP row appears, the sheet is laid out again one row lower
  nb, nr = CountBuilds(ns, function()
    Stub.EnterBG(); Stub.Advance(1200); Stub.LeaveBG(); Stub.Advance(5)
  end)
  T.eq({ nb, nr }, { 0, 0 }, "no rebuild")
  Live()
  Stats.LevelSegments(lb, 0, seg)
  T.ok(seg.bg >= 1200, "battleground time: " .. seg.bg)
  T.eq(RowNamed(Rows(dt), L.BD_PVP), { L.BD_PVP, L.LD_HOVER, Fmt.DurationFull(seg.bg + seg.wpvp),
    Fmt.Percent((seg.bg + seg.wpvp) / dt.time.total) }, "PvP row, live")
  T.eq(dt.time.n, n0 + 1)
  T.eq(Y(dt.pvpHit), Y(dt.time.rows[dt.time.pvp].label) - 1, "the hover area on the PvP row")
  T.eq(Y(dt.xp.title), y1 + 17, "the sections below one row lower")
  T.eq(dt.nZones, z1 + 1, "laid out again: the battleground in the zones too")
  T.eq(dt.content:GetHeight(), h1 + 17 + ZONE_H)
  AsRebuilt("battleground")
  -- a death: the Deaths card and its dead time, a Dead row
  local deaths0 = Text(dt.cards.deaths.value)
  nb, nr = CountBuilds(ns, function()
    Stub.Die(); Stub.Advance(65); Stub.ReleaseSpirit(); Stub.Advance(260); Stub.Resurrect(true); Stub.Advance(5)
  end)
  T.eq({ nb, nr }, { 0, 0 }, "no rebuild")
  Live()
  Stats.LevelSegments(lb, 0, seg)
  T.eq(deaths0, "0")
  T.eq(Card(dt.cards.deaths), { L.TT_DEATHS, "1", format(L.LV_DEAD_SUB_FMT, Fmt.DurationFull(seg.dead)) }, "Deaths, live")
  T.eq(RowNamed(Rows(dt), L.BD_DEAD)[3], Fmt.DurationFull(seg.dead))
  T.eq(dt.time.n, n0 + 2)
  AsRebuilt("death")
  -- steady state: the live step allocates nothing at a moment without a key change
  local LD, char, sync, now = ns.LevelDetail, ns.char, ns.Tracker.GetSync(), GetTime()
  LD.Live(char, 0, sync, now)
  local kb = T.alloc(function() LD.Live(char, 0, sync, now) end, 600)
  T.ok(kb < 0.05, format("LevelDetail.Live x600 with its rows: %.3f KB", kb))
  T.eq(#Stub.errors, 0)
end)

-- tests-live-mask: the live steps of the chart and the sheet under exclusions (mask 7: the
-- filtered time is not the server's); an XP gain between two rebuilds moves the projection
-- live (chip 7, the sheet's estimate and "about X left"); a server cap found while the
-- window is open rebuilds it from the live step.
T.test("detail: live under exclusions (mask 7): filtered and server times; the projection live; a cap found live", function()
  local ns = Start({ levelPlayed = 2000 })
  for _, k in ipairs({ "exclude.afk", "exclude.inn", "exclude.city" }) do ns.Core.SetSetting(k, true) end
  Stub.SetAFK(true); Stub.Advance(600); Stub.SetAFK(false)
  Stub.SetResting(true); Stub.Advance(300); Stub.SetResting(false)
  ns.Window.Show("levels")
  local ch, dt = Chart(), Detail()
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local mask = ns.GetMask()
  T.eq(mask, 7)
  T.eq(ch.state.sel, 20)
  local char = ns.char
  local function Live()
    local sync, now = ns.Tracker.GetSync(), GetTime()
    ns.LevelChart.Live(char, mask, sync, now)
    return sync, now
  end
  Stub.Advance(3600)
  local sync, now = Live()
  local pf, pb = Stats.Played(char, mask, sync, now)
  local lf, lt = Stats.LevelTime(char, 20, mask, sync, now)
  T.ok(lt - lf >= 900 and pb - pf >= 900, format("the exclusions matter: %d, %d", lt - lf, pb - pf))
  T.eq(Text(ch.chips[1].value), Fmt.DurationFull(pf), "Played chip: filtered")
  T.eq(Text(ch.chips[2].value), Fmt.DurationFull(pb), "Server chip: everything")
  T.near(ch.state.curTime, lf, 1e-6, "the current level's time: filtered")
  local row = RowOf(ns, 20, mask)
  local approx = (row.partial or row.rec or row.estF > 0 or (row.gap or 0) > 0) and "~" or ""
  T.eq(Text(dt.cards.played.value), approx .. Fmt.DurationFull(lf), "sheet Played: filtered")
  T.eq(Text(dt.cards.server.value), (row.serverEst and "~" or "") .. Fmt.DurationFull(lt), "sheet Server: everything")
  T.near(dt.time.total, lf, 1e-6, "the breakdown: the filtered time")
  for _, r in ipairs(Rows(dt)) do
    T.no(r[1] == L.BD_AFK or r[1] == L.BD_INN or r[1] == L.BD_CITY, "no row for an excluded part: " .. r[1])
  end
  -- an XP gain right after a rebuild: the projection follows at the next live step (the
  -- coalesced rebuild comes 30 ticks after the last one)
  ns.Window.Refresh()
  local left0 = Text(dt.cards.eta.sub)
  local nb, nr = CountBuilds(ns, function()
    Stub.Advance(1); Stub.GrantXP(3000); Stub.Advance(5)
  end)
  T.eq({ nb, nr }, { 0, 0 }, "no rebuild yet")
  sync, now = Live()
  lf = Stats.LevelTime(char, 20, mask, sync, now)
  local fut = {}
  local _, xp, max, rest, valid = ns.Tracker.GetXPInfo()
  Stats.FutureLevels(char, ns.db, mask, { level = 20, xp = xp, max = max, rest = rest, valid = valid, top = 60,
    sync = sync, now = now }, fut)
  T.eq(fut.status, ch.state.status)
  T.eq(Text(dt.cards.eta.sub), format(L.LD_LEFT_FMT, Fmt.Duration(fut.cur)), "about X left, live")
  T.ok(Text(dt.cards.eta.sub) ~= left0, "it moved: " .. left0)
  T.eq(Text(dt.cards.eta.value), Fmt.ETA(lf + fut.cur), "the level's estimate, live")
  T.eq(Text(ch.chips[7].value), Fmt.ETA(fut.total), "Level 60 in, live")
  -- a server cap found while open (C.CAP_MISSES kills without XP; its XP_CHANGED rebuilds
  -- the window 30 ticks after the last rebuild): the live step rebuilds first
  for _ = 1, 2 do Stub.KillNoXP() end
  ns.Window.Refresh()
  nb, nr = CountBuilds(ns, function()
    Stub.KillNoXP({ fight = 2 })
    Stub.Advance(5)
  end)
  T.eq(ns.Tracker.GetCapInfo(), 20)
  T.eq(nr, 0, "no Refresh")
  T.ok(nb >= 1, "rebuilt by the live step")
  T.eq(ch.state.status, "cap")
  T.eq(Text(ch.chips[7].label), L.CAP_SHORT)
  T.eq(Text(dt.cards.eta.label), L.LD_ETA, "the sheet: no projection any more")
end)

-- tests-untracked-excess (the sheet): the current level's record behind its server time
-- (read-only mode, seconds not yet recorded): the excess is untracked, the total the
-- shown time.
T.test("detail: the current level's server time above its parts goes to the untracked row", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L, Fmt, Stats = ns.L, ns.Fmt, ns.Stats
  local dt = Detail()
  local lb = ns.char.levels[20]
  lb.s.u = (lb.s.u or 0) - 600                 -- the record lags the server's level time
  ns.Window.Refresh()
  local t = Stats.LevelTime(ns.char, 20, 0, ns.Tracker.GetSync(), GetTime())
  local seg = {}
  local sum = Stats.LevelSegments(lb, 0, seg)
  T.ok(t - sum >= 599, "an excess: " .. (t - sum))
  T.near(dt.time.total, t, 1e-6, "the total: the shown time")
  T.eq(Text(dt.time.right), format(L.LD_TOTAL_FMT, Fmt.DurationFull(t)))
  local u = seg.untracked + (t - sum)
  T.eq(RowNamed(Rows(dt), L.TT_UNTRACKED), { L.TT_UNTRACKED, "", Fmt.DurationFull(u), Fmt.Percent(u / t) },
    "untracked: its own part and the excess")
  T.eq(Width(Bar(dt.time.segs, 12, dt.content)), IW)
end)

-- ux-8 / stats-upcoming-basis-text: the upcoming level's basis line says where its estimate
-- comes from (Stats.FutureLevels src): the recent levels' pace, else the current XP rate.
T.test("detail: an upcoming level's basis: the recent levels' pace, else the current XP per hour", function()
  local ns = Start()
  ns.Window.Show("levels")
  local L = ns.L
  local dt = Click(25)
  T.eq(Chart().state.status, "ok")
  T.eq(Text(dt.up.sub), L.LD_EST_SUB, "src recent")
  for l = 5, 19 do ns.char.levels[l].rec = true end   -- no complete level to sample: the XP rate
  ns.Window.Refresh()
  T.eq(Chart().state.status, "estimate")
  dt = Click(25)
  T.eq(dt.kind, "future")
  T.eq(Text(dt.up.sub), L.LD_EST_SUB_RATE, "src rate")
end)

-- The value columns (VAL_W, the breakdown's rows and the zones) keep a duration's minutes
-- past 10 h when the text fits the column (the stub draws 6 px a character), else drop
-- them (Fmt.Duration: "12d 19h", "10 h"): DurFit. The cards keep them (wider).
T.test("detail: a value column keeps the minutes past 10 h when they fit, else drops them (DurFit)", function()
  for _, locale in ipairs({ "enUS", "esES" }) do
    Stub.Reset()
    Stub.locale = locale
    local ns = Start()
    local Fmt, L = ns.Fmt, ns.L
    local lb = ns.char.levels[12]
    local long = 12 * 86400 + 19 * 3600 + 5 * 60        -- 12d 19h 05m
    lb.s.w, lb.s.W = 37380, long                        -- world 10h 23m, AFK 12 days
    lb.z[1411].s.w = 37380 - 500                        -- Durotar: 10h 23m with its AFK and flight
    ns.Window.Show("levels")
    local dt = Click(12)
    local function Value(label)
      for j = 1, dt.time.n do
        local r = dt.time.rows[j]
        if Text(r.label) == label then return Text(r.value), r.value:GetUnboundedStringWidth() end
      end
    end
    local function Zone(name)
      for j = 1, dt.nZones do
        if Text(dt.zones[j].name) == name then return Text(dt.zones[j].time) end
      end
    end
    local function Fits(text) return 6 * #text <= 64 end
    for _, e in ipairs({ { L.BD_WORLD, 37380 }, { L.BD_AFK, long } }) do
      local full = Fmt.DurationFull(e[2])
      local want = Fits(full) and full or Fmt.Duration(e[2])
      local text, w = Value(e[1])
      T.eq(text, want, locale .. ": " .. e[1])
      T.ok(w <= 64, locale .. ": " .. e[1] .. " fits its column (" .. w .. ")")
    end
    T.eq(Zone("Durotar"), Fits(Fmt.DurationFull(37380)) and Fmt.DurationFull(37380) or Fmt.Duration(37380),
      locale .. ": the zone's time")
    T.eq(Text(dt.cards.played.value), Fmt.DurationFull(ns.Stats.Sum(lb, 0)), locale .. ": the Played card to the minute")
    if locale == "enUS" then
      T.eq(Value(L.BD_WORLD), "10h 23m", "enUS: the minutes past 10 h fit")
      T.eq(Value(L.BD_AFK), "12d 19h", "enUS: 12 days and the minutes do not")
      T.eq(Zone("Durotar"), "10h 23m")
    else
      T.eq(Value(L.BD_WORLD), "10 h", "esES: '10 h 23 min' does not fit")
      T.eq(Value(L.BD_AFK), "12 d 19 h")
      T.eq(Zone("Durotar"), "10 h")
    end
  end
end)

-- The current character's level in progress: its zones and notes follow at the next
-- rebuild only (an XP gain), so they keep Fmt.Duration (no minutes past 10 h to fall
-- behind its growing times), as the Zones tab; a level done keeps its minutes (DurFit).
-- Its Server /played card is live on either rule of Stats.LevelServer (the sync's level
-- part, else the server total less the level's server start).
T.test("detail: the level in progress's zones keep Fmt.Duration, its Server card live on either rule", function()
  local ns = Start()
  local Fmt, Stats = ns.Fmt, ns.Stats
  local lb = ns.char.levels[20]
  lb.z = lb.z or {}
  lb.z[1411] = lb.z[1411] or { s = {} }
  lb.z[1411].s.w = (lb.z[1411].s.w or 0) + 37380
  lb.s.w = (lb.s.w or 0) + 37380
  ns.char.levels[12].z[1411].s.w = 37380 - 500        -- a level done: Durotar 10h 23m
  ns.Window.Show("levels")
  local dt = Detail()
  T.eq(dt.level, 20, "the level in progress")
  local function Zone(name)
    for j = 1, dt.nZones do
      if Text(dt.zones[j].name) == name then return Text(dt.zones[j].time) end
    end
  end
  local secs = Stats.Sum(lb.z[1411], 0)
  T.ok(secs >= 36000, "the fixture: past 10 h")
  T.eq(Zone("Durotar"), Fmt.Duration(secs), "the level in progress: Fmt.Duration")
  T.ok(not Zone("Durotar"):find("m", 1, true), "no minute that would fall behind: " .. Zone("Durotar"))
  dt = Click(12)
  T.eq(Zone("Durotar"), "10h 23m", "a level done: to the minute")
  -- the Server card without the sync's level part: the total less the level's start, live
  dt = Click(20)
  local sync = ns.Tracker.GetSync()
  sync.levelValid, sync.levelPlayed = false, nil
  lb.srvStart = sync.total + (GetTime() - sync.g) - 50000
  lb.srvStartEst = nil
  ns.Window.Refresh()
  dt = Detail()
  local function Server() return Stats.LevelServer(ns.char, 20, sync, GetTime()) end
  T.near(Server(), 50000, 1, "the fixture: 13h 53m by the server's start of the level")
  T.eq(Text(dt.cards.server.value), Fmt.DurationFull(Server()), "at the rebuild")
  Stub.Advance(600)
  T.eq(Text(dt.cards.server.value), Fmt.DurationFull(Server()), "600 s later, without a rebuild")
  T.ok(Server() >= 50590, "it grew")
end)

-- The Experience bar in the bar's colours: the theme's, the user's once chosen
-- (widget.xpColor / restedColor), as the tooltip's XP row; a recolour repaints the shown
-- sheet without a rebuild (LevelDetail.Recolor, Window's THEME_CHANGED "colors").
T.test("detail: the Experience bar in the user's XP / rested colours, repainted at a recolour (no rebuild)", function()
  local ns = Start({ theme = "futuriste" })
  ns.Window.Show("levels")
  local dt = Click(17)
  local th = ns.Themes.Active()
  NearColor(dt.xp.segs[1], th.colors.xp, "mobs: the theme's XP colour")
  NearColor(dt.xp.segs[3], th.colors.rested, "rested: the theme's rested colour")
  local n = 0
  local build = ns.LevelChart.Build
  ns.LevelChart.Build = function(...) n = n + 1 return build(...) end
  ns.Core.SetSetting("widget.xpColor", { 0.1, 0.9, 0.1 })
  ns.Core.SetSetting("widget.restedColor", { 0.9, 0.5, 0.1 })
  NearColor(dt.xp.segs[1], { 0.1, 0.9, 0.1 }, "mobs: the user's XP colour")
  NearColor(dt.xp.segs[2], Gauge(ns).city, "quests: the gauge city colour")
  NearColor(dt.xp.segs[3], { 0.9, 0.5, 0.1 }, "rested: the user's rested colour")
  T.eq(n, 0, "no rebuild")
  ns.LevelChart.Build = build
  dt = Click(16)
  NearColor(dt.xp.segs[1], { 0.1, 0.9, 0.1 }, "another sheet: the user's colour")
  ns.Core.SetSetting("widget.xpColor", false)
  ns.Core.SetSetting("widget.restedColor", false)
  NearColor(dt.xp.segs[1], th.colors.xp, "back to the theme's")
  NearColor(dt.xp.segs[3], th.colors.rested, "rested: back to the theme's")
  T.eq(#Stub.errors, 0)
end)
