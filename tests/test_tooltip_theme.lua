-- tests/test_tooltip_theme.lua - the themed tooltip (design/SPEC-themes.md 4, 8.5): the
-- private TooltipFrame of the non-native themes (rows, separators, gauge, panel), its
-- change-only refreshes, and the classic paths (the Classic theme keeps GameTooltip,
-- Broker tooltips keep the classic palette). Also the light theming of the statistics
-- window (4.6, Window.ApplyTheme; the graph panel is in test_graph.lua).
local Stub, T = ...

local format = string.format

local function Ema(a, r, q, d)
  local t = {}
  for i = 1, 8 do t[i] = { a = a, r = r, q = q, d = d } end
  return t
end

-- Character record of the stub player: completed levels, zones, a capital, and play in
-- every kind of place so the breakdown has 7 parts (two lines: a continuation row).
local function Record()
  local p = Stub.player
  local lvl = p.level
  local rec = {
    guid = p.guid, name = p.name, surname = p.surname, realm = p.realm, class = p.class,
    faction = p.faction, level = lvl, firstSeen = 1789900000, lastSeen = 1789990000,
    base = { at = 1789900000, total = 300000, level = 5 },
    life = { s = { w = 20000, W = 1200, d = 3000, r = 1000, i = 800, I = 400, c = 1500, C = 600, t = 300,
                   T = 60, u = 300000 },
             xp = 40000, xa = 30000, xr = 5000, xq = 5000, d = 3, est = 0 },
    levels = {},
    zones = {
      [1411] = { s = { w = 20000, W = 1200, i = 800, I = 400 }, xp = 40000, name = "Durotar" },
      [1454] = { s = { c = 1500, C = 600, t = 300, T = 60 }, xp = 0, name = "Orgrimmar" },
    },
    sessions = {},
    ema = Ema(12000, 3000, 5000, 3600),
  }
  for lv = 5, lvl - 1 do
    rec.levels[lv] = { s = { w = 3000, W = 200 }, xp = 5000, xa = 4000, xr = 500, xq = 500, d = 0,
                       est = 0, max = 5000, t0 = 1789900000 + lv * 1000, t1 = 1789900000 + lv * 1000 + 999,
                       z = { [1411] = { s = { w = 3000, W = 200 }, xp = 5000 } } }
  end
  rec.levels[lvl] = { s = { w = 1000, W = 60 }, xp = 3000, xa = 2400, xr = 300, xq = 300, d = 0,
                      est = 0, t0 = 1789990000, z = { [1411] = { s = { w = 1000, W = 60 }, xp = 3000 } } }
  return rec
end

-- Loads the addon with `theme` as the default theme (nil = the real default, futuriste),
-- the widget shown, on a prepared record; returns ns and the widget.
local function Start(theme, opts)
  opts = opts or {}
  Stub.theme = theme
  if not opts.ldb then rawset(_G, "LibStub", nil) end
  local p = Stub.player
  p.xp = 3000
  p.rest = opts.rest or 1000
  local db = {
    schema = 1, createdAt = 1789900000,
    settings = { requestPlayedAtLogin = false },
    cities = {}, xpMax = {}, chars = {},
  }
  db.chars[p.guid] = Record()
  _G.TruePlayedDB = db
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, rawget(_G, "TruePlayedWidget")
end

-- Texts of a GameTooltip-like mock, in order, without the blank " " lines: left and
-- right of each line (a " " left text is skipped too).
local function NativeTexts(lines)
  local out = {}
  for i = 1, #lines do
    local l, r = lines[i][1], lines[i][2]
    if l ~= " " then out[#out + 1] = l end
    if r ~= nil then out[#out + 1] = r end
  end
  return out
end

local function NativeBlanks(lines)
  local n = 0
  for i = 1, #lines do
    if lines[i][1] == " " and lines[i][2] == nil then n = n + 1 end
  end
  return n
end

-- The same flattening for the rows of the TooltipFrame.
local function FrameTexts(tp)
  local out = {}
  for i = 1, tp.n do
    local row = tp.rows[i]
    local l = row.left:GetText()
    if l ~= " " then out[#out + 1] = l end
    if row.right:IsShown() then out[#out + 1] = row.right:GetText() end
  end
  return out
end

local function SepCounts(tp)
  local c = { header = 0, block = 0, footer = 0 }
  for i = 1, tp.nSeps do
    local k = tp.seps[i].kind
    c[k] = (c[k] or 0) + 1
  end
  return c
end

local function ShownCount(list)
  local n = 0
  for i = 1, #list do
    if list[i]:IsShown() then n = n + 1 end
  end
  return n
end

local function Created()
  local c = Stub.created
  return c.Texture + c.MaskTexture + c.FontString + c.Frame
end

local function Near(a, b)
  return math.abs((a or -1) - (b or -2)) < 1e-6
end

local function Rgb(fs)
  local r, g, b = fs:GetTextColor()
  return { r, g, b }
end

local function C3(c)
  return { c[1], c[2], c[3] }
end

-- Lines of a fresh mock filled the classic way (what Broker's tooltips get).
local function Native(ns, detailed)
  local tt = Stub.NewTooltip()
  ns.Tooltip.Fill(tt, detailed)
  return tt._lines, tt._colors
end

---------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------

T.test("futuriste: ShowFor uses the private frame; GameTooltip stays hidden and empty", function()
  local ns, w = Start(nil)
  local Tooltip, TF = ns.Tooltip, ns.TooltipFrame
  T.eq(ns.Themes.ActiveKey(), "futuriste")
  T.ok(TF ~= nil, "ns.TooltipFrame")
  T.eq(TF.frame, nil, "created at the first show only")
  local before = {}
  for k in pairs(GameTooltip) do before[k] = true end
  GameTooltip:ClearLines()
  Tooltip.ShowFor(w)
  local f = TF.frame
  T.ok(f ~= nil and f:IsShown(), "private frame shown")
  T.ok(f:GetOwner() == w)
  T.ok(Tooltip.IsShownFor(w))
  T.no(GameTooltip:IsShown(), "GameTooltip hidden")
  T.eq(GameTooltip:NumLines(), 0, "GameTooltip empty")
  for k in pairs(GameTooltip) do T.ok(before[k], "no new field on GameTooltip: " .. tostring(k)) end
  T.eq(f:GetFrameStrata(), "TOOLTIP")
  T.ok(f:IsClampedToScreen())
  T.no(f:IsMouseEnabled())
  T.eq(f:GetName(), nil, "anonymous")
  -- anchored like the native one: below an owner in the upper half of the screen
  local point, rel, relPoint, x, y = f:GetPoint(1)
  T.ok(rel == w)
  if select(2, w:GetCenter()) > 540 then
    T.eq({ point, relPoint, x, y }, { "TOP", "BOTTOM", 0, -4 })
  else
    T.eq({ point, relPoint, x, y }, { "BOTTOM", "TOP", 0, 4 })
  end
  -- refreshed on TICK while shown, detached when hidden
  Stub.Advance(2)
  T.ok(Tooltip.IsShownFor(w))
  Tooltip.Hide(w)
  T.no(f:IsShown())
  T.no(Tooltip.IsShownFor(w))
  T.eq(f:GetOwner(), nil)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("actuel uses GameTooltip and never creates the private frame", function()
  local ns, w = Start("actuel")
  T.eq(ns.Themes.ActiveKey(), "actuel")
  ns.Tooltip.ShowFor(w)
  T.ok(GameTooltip:IsShown())
  T.ok(GameTooltip:GetOwner() == w)
  T.ok(GameTooltip:NumLines() > 5)
  T.eq(ns.TooltipFrame.frame, nil)
  local lines, colors = Native(ns, false)
  T.eq(GameTooltip._lines, lines, "the classic lines")
  T.eq(GameTooltip._colors, colors, "the classic colours")
end)

---------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------

T.test("content parity, separators and gauge: short and Shift", function()
  local ns, w = Start(nil)
  local Tooltip, L = ns.Tooltip, ns.L
  for _, shift in ipairs({ false, true }) do
    Stub.shift = shift
    Tooltip.ShowFor(w)
    local tp = ns.TooltipFrame.frame.tp
    local lines = Native(ns, shift)
    T.eq(FrameTexts(tp), NativeTexts(lines), "row texts in order (shift " .. tostring(shift) .. ")")
    T.eq(SepCounts(tp), { header = 1, block = NativeBlanks(lines), footer = 1 }, "separators")
    -- kinds: title first, hint last, the gauge row then continuation rows only
    T.eq(tp.rows[1].kind, "title")
    T.eq(tp.rows[tp.n].kind, "hint")
    T.eq(tp.rows[tp.n].left:GetText(), L.TT_HINT)
    local gaugeRow
    for i = 1, tp.n do
      if tp.rows[i].kind == "gauge" then gaugeRow = i end
    end
    T.ok(gaugeRow, "gauge row")
    T.eq(tp.rows[gaugeRow].left:GetText(), L.TT_BREAKDOWN)
    T.eq(tp.rows[gaugeRow + 1].kind, "cont")
    T.eq(tp.rows[gaugeRow + 2].kind, "cont", "7 parts: two text rows")
    local nParts = Tooltip.BreakdownParts(ns.Stats.Breakdown(ns.char.life, {}), {})
    T.eq(nParts, 7)
    T.eq(ShownCount(tp.gauge), nParts, "one segment per part")
    Tooltip.Hide(w)
  end
  Stub.shift = false
end)

T.test("palette roles: rows take the theme's tooltip colours", function()
  local ns, w = Start(nil)
  local Tooltip, L = ns.Tooltip, ns.L
  Tooltip.ShowFor(w)
  local tp = ns.TooltipFrame.frame.tp
  local pal = ns.Themes.Active().tt.colors
  T.eq(Rgb(tp.rows[1].left), C3(pal.title), "title")
  local function Row(text)
    for i = 1, tp.n do
      if tp.rows[i].left:GetText() == text then return tp.rows[i] end
    end
  end
  local xp = Row(L.TT_XP)
  T.eq(xp.kind, "pair")
  T.eq(Rgb(xp.left), C3(pal.label))
  T.eq(Rgb(xp.right), C3(pal.value))
  local level = tp.rows[2]
  T.eq(level.left:GetText(), format(L.TT_LEVEL_FMT, Stub.player.level, Stub.player.level + 1))
  T.eq(Rgb(level.left), C3(pal.levelLabel))
  T.eq(Rgb(level.right), C3(pal.levelValueRested), "rested: the rested level value role")
  T.eq(Rgb(Row(L.TT_RESTED).right), C3(pal.rested))
  T.eq(Rgb(tp.rows[tp.n].left), C3(pal.hint))
  T.eq(tp.rows[tp.n].left:GetJustifyH(), "CENTER", "hint centred")
end)

T.test("panel, title icon, separators, leaders, gauge and fonts follow the theme", function()
  local ns, w = Start(nil)
  ns.Tooltip.ShowFor(w)
  local f = ns.TooltipFrame.frame
  local tp = f.tp
  local th = ns.Themes.Active()
  local tt = th.tt
  -- panel: one handle per part; a 9-slice part is a list of 9 textures
  for _, p in ipairs(tt.panel.parts) do
    local h = tp.panel[p.id]
    T.ok(h ~= nil, "panel part " .. p.id)
    if p.kind == "nine" then
      T.eq(#h, 9, p.id .. " 9-slice")
      T.eq(h[1]:GetTexture(), p.tex.path)
    else
      T.eq(h:GetTexture(), p.tex.path)
    end
  end
  -- icon left of the title
  if tt.titleIcon then
    T.ok(tp.icon and tp.icon:IsShown(), "title icon")
    T.eq(tp.icon:GetTexture(), tt.titleIcon.tex.path)
    local _, _, _, ix = tp.icon:GetPoint(1)
    local _, _, _, lx = tp.rows[1].left:GetPoint(1)
    T.eq(lx, ix + tt.titleIcon.w + tt.titleIcon.gap, "title text after the icon")
  end
  -- separators: the header one carries its gradient, the footer one is mirrored
  for i = 1, tp.nSeps do
    local s = tp.seps[i]
    local cfg = tt.sep[s.kind]
    if cfg then
      T.ok(s.a:IsShown(), s.kind .. " separator shown")
      T.eq(s.a:GetTexture(), cfg.tex.path)
      if cfg.g then T.ok(rawget(s.a, "_grad") ~= nil, s.kind .. " gradient") end
      if cfg.mirror then
        T.ok(s.b:IsShown(), "mirrored half")
        local ga, gb = rawget(s.a, "_grad"), rawget(s.b, "_grad")
        T.eq({ gb[2], gb[3], gb[4], gb[5] }, { ga[6], ga[7], ga[8], ga[9] }, "right half reversed")
      end
      if cfg.tex.tile then T.eq(rawget(s.a, "_wrapH"), "REPEAT", s.kind .. " tiled") end
    end
  end
  -- leaders: on pair rows that have room
  if tt.leader then
    local n = 0
    for i = 1, tp.n do
      local row = tp.rows[i]
      if row.leader and row.leader:IsShown() then
        n = n + 1
        T.eq(row.kind == "pair" or row.kind == "gauge", true, "leader on a pair or gauge row")
      end
    end
    T.ok(n > 3, "leaders shown")
  end
  -- gauge colours by part key
  local keys = {}
  ns.Tooltip.BreakdownFracs(ns.Stats.Breakdown(ns.char.life, {}), {}, keys)
  for i = 1, #keys do
    local c = tt.gauge.colors[keys[i]]
    local r, g, b = tp.gauge[i]:GetVertexColor()
    T.ok(Near(r, c[1]) and Near(g, c[2]) and Near(b, c[3]), "segment " .. i .. " colour " .. keys[i])
  end
  -- fonts: the title role on the title, body on the rows, note on the notes
  local title = tp.rows[1].left
  T.eq((title:GetFont()), (ns.Themes.Font(tt.fonts.title[1], tt.fonts.title[2])))
  T.eq(select(2, title:GetFont()), select(2, ns.Themes.Font(tt.fonts.title[1], tt.fonts.title[2])))
  T.eq((tp.rows[3].left:GetFont()), (ns.Themes.Font(tt.fonts.body[1], tt.fonts.body[2])))
  -- width inside the theme's bounds
  local fw = f:GetWidth()
  T.ok(fw >= tt.width[1] and fw <= tt.width[2], "width " .. fw)
end)

-- SPEC-themes 2.4.2 / 4.2: a part without `sub` is drawn at BACKGROUND -8 + n - 1 (n: its
-- place in the list). The compact form leaves that default out, so TooltipFrame's own
-- default is what draws it. Expected values: the source's (Themes/futuriste.lua).
T.test("futuriste: the tooltip panel parts are drawn at their sublevels (the -8 + n - 1 default included)", function()
  local ns, w = Start(nil)
  ns.Tooltip.ShowFor(w)
  local tp = ns.TooltipFrame.frame.tp
  local want = { bg = -8, glowTL = -7, scan = -6, grid = -5, line = -4, accTopGlow = -3, accBottomGlow = -3,
                 accTop = -2, accLeft = -1, accBottom = -2, accRight = -1 }
  local n = 0
  for id in pairs(tp.panel) do
    n = n + 1
    T.ok(want[id] ~= nil, "part " .. tostring(id) .. " is a futuriste part")
  end
  T.eq(n, 11, "the 11 parts")
  for id, sub in pairs(want) do
    local h = tp.panel[id]
    local list = h.GetDrawLayer and { h } or { h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8], h[9] }
    for i = 1, #list do
      local t = list[i]
      T.eq({ t:GetDrawLayer() }, { "BACKGROUND", sub }, id .. " [" .. i .. "] draw layer")
      T.ok(t:IsShown(), id .. " shown")
    end
  end
end)

-- SPEC-themes 4.5: the value column takes tooltip.fonts.value, else fonts.body. Futuriste
-- writes value = body ({ "body", 15 }); the compact form leaves value out, so TooltipFrame's
-- fallback is what draws the values: 15, never the generic 13.
T.test("futuriste: the value cells are drawn at the theme's body size (15), short and Shift", function()
  local ns, w = Start(nil)
  local path15, size15 = ns.Themes.Font("body", 15)
  T.eq(size15, 15)
  for _, shift in ipairs({ false, true }) do
    Stub.shift = shift
    ns.Tooltip.ShowFor(w)
    local tp = ns.TooltipFrame.frame.tp
    local n = 0
    for i = 1, tp.n do
      local right = tp.rows[i].right
      local text = right:GetText()
      if right:IsShown() and text and text ~= "" then
        n = n + 1
        local path, size = right:GetFont()
        T.eq({ path, size }, { path15, 15 }, "row " .. i .. " (" .. tostring(tp.rows[i].kind) .. "): value font")
      end
    end
    T.ok(n >= 5, "value cells drawn: " .. n)
    ns.Tooltip.Hide(w)
  end
  Stub.shift = false
end)

---------------------------------------------------------------------------
-- Performance
---------------------------------------------------------------------------

T.test("pools: a second show creates no region; 300 steady ticks set only changed texts", function()
  local ns, w = Start(nil)
  local Tooltip = ns.Tooltip
  Tooltip.ShowFor(w)
  Stub.SetShift(true)                      -- the detailed view grows the pools
  Stub.SetShift(false)
  Tooltip.Hide(w)
  local c0 = Created()
  Tooltip.ShowFor(w)
  Stub.SetShift(true)
  Stub.SetShift(false)
  T.eq(Created(), c0, "second show: no region created")
  local tp = ns.TooltipFrame.frame.tp
  Stub.Advance(1)
  -- GetStringWidth calls on the tooltip's own texts (the widget measures its texts too)
  local measures = 0
  local measure = getmetatable(tp.rows[1].left).__index.GetStringWidth
  local function Counted(self)
    measures = measures + 1
    return measure(self)
  end
  for i = 1, #tp.rows do
    rawset(tp.rows[i].left, "GetStringWidth", Counted)
    rawset(tp.rows[i].right, "GetStringWidth", Counted)
  end
  local fonts0 = Stub.calls.SetFont
  local texts, counts = {}, {}
  for _ = 1, 300 do
    for i = 1, tp.n do
      local row = tp.rows[i]
      texts[i], counts[i] = row.left:GetText(), rawget(row.left, "_setTextCount")
      texts[-i], counts[-i] = row.right:GetText(), rawget(row.right, "_setTextCount")
    end
    local n0, gw0 = tp.n, measures
    Stub.Advance(1)
    T.eq(tp.n, n0, "same rows")
    local changed = 0
    for i = 1, tp.n do
      local row = tp.rows[i]
      if row.left:GetText() == texts[i] then
        T.eq(rawget(row.left, "_setTextCount"), counts[i], "no SetText on an unchanged row " .. i)
      else
        changed = changed + 1
      end
      if row.right:GetText() == texts[-i] then
        T.eq(rawget(row.right, "_setTextCount"), counts[-i], "no SetText on an unchanged value " .. i)
      else
        changed = changed + 1
      end
    end
    T.ok(measures - gw0 <= changed, "measures only the changed texts")
  end
  T.eq(Stub.calls.SetFont, fonts0, "no SetFont on steady ticks")
  T.eq(Created(), c0, "no region created while shown")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("allocation: refilling the frame with the same rows allocates nothing", function()
  local ns, w = Start(nil)
  ns.Tooltip.ShowFor(w)
  local f = ns.TooltipFrame.frame
  local tp = f.tp
  -- the rows of this fill, replayed as they came (kinds, texts, colours)
  local pal = ns.Themes.Active().tt.colors
  local kinds, lefts, rights = {}, {}, {}
  for i = 1, tp.n do
    local row = tp.rows[i]
    kinds[i], lefts[i] = row.kind, row.left:GetText()
    rights[i] = row.right:IsShown() and row.right:GetText() or nil
  end
  local n = tp.n
  local function Refill()
    f:ClearLines()
    for i = 1, n do
      if i == 2 then f:TP_Sep("header") end
      f:TP_Row(kinds[i], lefts[i], rights[i], pal.label, pal.value)
    end
    f:Show()
  end
  Refill()
  local kb = T.alloc(Refill, 500)
  T.ok(kb < 0.5, format("allocated %.3f KB", kb))
end)

T.test("every theme: tooltip, graph and window show; a second cycle creates no region", function()
  local ns, w = Start(nil)
  local Themes, Core, Tooltip = ns.Themes, ns.Core, ns.Tooltip
  local owner = CreateFrame("Frame", nil, UIParent)
  owner:SetSize(80, 14)
  owner:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
  local function Cycle()
    local n = 0
    for _, key in ipairs(Themes.KEYS) do
      if Themes.IsRegistered(key) then
        n = n + 1
        Core.SetSetting("theme", key)
        T.eq(Themes.ActiveKey(), key)
        for _, shift in ipairs({ false, true }) do
          Stub.shift = shift
          Tooltip.ShowFor(w)
          Stub.Advance(1)
          T.ok(Tooltip.IsShownFor(w), key .. " tooltip shown")
          local th = Themes.Active()
          if th.native then
            T.ok(GameTooltip:NumLines() > 5, key .. ": GameTooltip")
          else
            local tp = ns.TooltipFrame.frame.tp
            T.ok(tp.n > 10, key .. ": rows")
            T.eq(tp.rows[1].kind, "title")
            local fw = ns.TooltipFrame.frame:GetWidth()
            T.ok(fw >= th.tt.width[1] and fw <= th.tt.width[2], key .. " width " .. fw)
          end
          Tooltip.Hide(w)
        end
        Stub.shift = false
        ns.Graph.ShowFor(owner)
        Stub.Advance(1)
        ns.Graph.Hide()
        ns.Window.Show()
        Stub.Advance(1)
        ns.Window.Hide()
      end
    end
    return n
  end
  local n = Cycle()
  T.ok(n >= 2, "themes cycled: " .. n)
  local c0 = Created()
  Cycle()
  T.eq(Created(), c0, "second cycle: no region created")
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Theme changes, Broker, helpers
---------------------------------------------------------------------------

T.test("a theme change (either kind) hides the tooltip; the next show uses the new theme", function()
  local ns, w = Start(nil)
  local Tooltip, Core = ns.Tooltip, ns.Core
  Tooltip.ShowFor(w)
  local f = ns.TooltipFrame.frame
  T.ok(f:IsShown())
  Core.SetSetting("theme", "actuel")
  T.no(f:IsShown(), "hidden on THEME_CHANGED theme")
  T.no(Tooltip.IsShownFor(w))
  Tooltip.ShowFor(w)
  T.ok(GameTooltip:IsShown(), "Classic: GameTooltip")
  T.no(f:IsShown())
  Core.SetSetting("theme", "futuriste")
  T.no(GameTooltip:IsShown(), "GameTooltip hidden on the switch back")
  Tooltip.ShowFor(w)
  T.ok(f:IsShown())
  Core.SetSetting("widget.xpColor", { 0, 1, 0 })
  T.no(f:IsShown(), "hidden on THEME_CHANGED colors")
  Tooltip.ShowFor(w)
  T.ok(f:IsShown(), "shown again with the recoloured theme")
end)

T.test("Broker: Fill on a mock tooltip keeps the classic colours while futuriste is active", function()
  Stub.InstallUI({ ldb = true })
  local ns = Start(nil, { ldb = true })
  T.eq(ns.Themes.ActiveKey(), "futuriste")
  local obj = Stub.ui.ldbObjects.TruePlayed
  T.ok(obj ~= nil, "LDB object")
  local tt = Stub.NewTooltip()
  obj.OnTooltipShow(tt)
  local K = ns.C.COLORS
  T.eq(tt._colors[1], { K.accent[1], K.accent[2], K.accent[3] }, "title: classic accent")
  local L = ns.L
  for i, l in ipairs(tt._lines) do
    if l[1] == L.TT_XP then
      T.eq(tt._colors[i], { K.label[1], K.label[2], K.label[3], K.value[1], K.value[2], K.value[3] })
    end
  end
  local lines = Native(ns, false)
  T.eq(tt._lines, lines)
  T.eq(ns.TooltipFrame.frame, nil, "Broker never uses the private frame")
end)

T.test("BreakdownFracs: same order (largest first) and 0 % filter as BreakdownParts, reused tables", function()
  local ns = Start("actuel")
  local Tooltip = ns.Tooltip
  local bd = { tracked = 1000, active = 900, world = 600, dungeon = 100, raid = 0, pvp = 4,
               afk = 50, inn = 0, city = 50 }
  local fracs, keys = { 9, 9, 9, 9, 9, 9, 9, 9 }, { "x", "x", "x", "x", "x", "x", "x", "x" }
  local n = Tooltip.BreakdownFracs(bd, fracs, keys)
  T.eq(n, Tooltip.BreakdownParts(bd, {}))
  T.eq(n, 5)
  T.eq(keys, { "world", "taxi", "dungeon", "afk", "city" }, "largest first, ties in the fixed order")
  T.eq(#fracs, 5)
  T.near(fracs[1], 0.6)
  T.near(fracs[2], 0.196, 1e-9)
  T.near(fracs[3], 0.1)
  T.near(fracs[4], 0.05)
  T.near(fracs[5], 0.05)
  -- the legend lists the same parts in the same order
  local parts = {}
  Tooltip.BreakdownParts(bd, parts)
  local L = ns.L
  T.eq(parts[2], format(L.BD_PART_FMT, L.BD_TAXI, ns.Fmt.Percent(0.196, 0)), "legend: flight second")
  T.eq(parts[3], format(L.BD_PART_FMT, L.BD_DUNGEON, ns.Fmt.Percent(0.1, 0)), "legend: dungeons third")
  T.eq(Tooltip.BreakdownFracs({ tracked = 0 }, fracs, keys), 0)
  T.eq(#fracs + #keys, 0)
  local kb = T.alloc(function() Tooltip.BreakdownFracs(bd, fracs, keys) end, 1000)
  T.ok(kb < 0.1, format("allocated %.3f KB", kb))
end)

---------------------------------------------------------------------------
-- Statistics window (SPEC-themes 4.6)
---------------------------------------------------------------------------

local function V(x)
  if type(x) == "number" then return format("%.4f", x) end
  return tostring(x)
end

local function IsUnder(o, root)
  for _ = 1, 50 do
    o = rawget(o, "_parent")
    if o == nil then return false end
    if o == root then return true end
  end
  return false
end

-- Every region of the window as a string, plus its backdrop (see test_graph.lua).
-- chrome = true: the parts lot 8 did not redesign only (no row, cell, column header with
-- its help cell and icon, or resize grip, no frame width: the columns and the size of the
-- window changed then).
local function Snapshot(root, chrome)
  local out = {}
  local tp = rawget(root, "tp")
  local content = tp and tp.rows[1] and rawget(tp.rows[1], "_parent")
  local skip = {}
  if chrome and tp then
    for _, fs in pairs(tp.header) do skip[fs] = true end
    for _, cell in pairs(tp.headerCells or {}) do skip[cell] = true end
    if tp.grip then skip[tp.grip] = true end
  end
  local function Skipped(o)
    if not chrome then return false end
    if skip[o] or skip[rawget(o, "_parent")] or o == content then return true end
    if content and IsUnder(o, content) then return true end
    if tp.grip and IsUnder(o, tp.grip) then return true end
    return false
  end
  for _, o in ipairs(Stub.regions) do
    if IsUnder(o, root) and not Skipped(o) then
      local pts = {}
      for i, p in ipairs(o._points) do pts[i] = p.point .. ":" .. tostring(p.relPoint) .. ":" .. V(p.x) .. ":" .. V(p.y) end
      local fo = rawget(o, "_fontObject")
      out[#out + 1] = table.concat({
        o._type, V(o._layer), V(o._texture), V(o._vR), V(o._vG), V(o._vB), V(o._vA), V(o._text),
        V(o._font), V(o._fontSize), V(o._fontFlags), type(fo) == "table" and V(fo._name) or V(fo),
        V(o._tR), V(o._tG), V(o._tB), V(o._justifyH), V(o._width), V(o._height), V(o._shown),
        V(o._bgR), V(o._bgA), V(o._bdR), V(o._bdA), table.concat(pts, ","),
      }, "|")
    end
  end
  out[#out + 1] = table.concat({ V(root._bgR), V(root._bgG), V(root._bgB), V(root._bgA), V(root._bdR),
    V(root._bdG), V(root._bdB), V(root._bdA), chrome and "" or V(root._width), V(root._height) }, "|")
  return out
end

T.test("Window: futuriste backdrop, title font and cell colours; a switch while shown", function()
  local ns = Start(nil)
  local Window, Themes, L = ns.Window, ns.Themes, ns.L
  Window.Show("levels")
  local f = rawget(_G, "TruePlayedStatsFrame")
  T.ok(f and f:IsShown(), "window shown")
  local tp = f.tp
  local ui = Themes.Active().ui
  T.eq({ f._bgR, f._bgG, f._bgB, f._bgA }, { ui.bg[1], ui.bg[2], ui.bg[3], 0.95 }, "backdrop")
  T.eq({ f._bdR, f._bdG, f._bdB, f._bdA }, { ui.border[1], ui.border[2], ui.border[3], ns.C.COLORS.border[4] },
    "border: theme colour, the window's own alpha")
  local path, size = Themes.Font("display", 12)
  T.eq({ tp.title:GetFont() }, { path, size, "" }, "title: display font, GameFontNormal size")
  T.eq(Rgb(tp.footer2), C3(ui.label), "label texts")
  T.eq(Rgb(tp.header[1]), C3(ui.label), "column headers")
  -- the in-progress level row: accent level cell and tag, label and value cells
  local pos = tp.layout.pos
  local cur
  for _, row in ipairs(tp.rows) do
    if row:IsShown() and tp.cells[row][pos.reached]:GetText() == L.ROW_IN_PROGRESS then cur = row end
  end
  T.ok(cur, "in-progress level row")
  local cells = tp.cells[cur]
  T.eq(Rgb(cells[1]), C3(ui.accent), "current level: accent")
  T.eq(Rgb(cells[pos.reached]), C3(ui.accent))
  T.eq(Rgb(cells[pos.cum]), C3(ui.label), "total time: label")
  T.eq(Rgb(cells[2]), C3(ui.value), "time: value")
  -- Classic while shown: classic colours, the GameFontNormal title again
  ns.Core.SetSetting("theme", "actuel")
  local K = ns.C.COLORS
  T.eq({ f._bgR, f._bgG, f._bgB, f._bgA }, { K.bg[1], K.bg[2], K.bg[3], 0.95 })
  T.eq(Rgb(cells[1]), C3(K.accent), "refilled with the classic accent")
  T.eq(Rgb(cells[pos.cum]), C3(K.label))
  T.ok(tp.title:GetFontObject() == GameFontNormal, "title back on GameFontNormal")
  -- and back: the display font is set again (the Themes font cache followed the switch)
  ns.Core.SetSetting("theme", "futuriste")
  T.eq((tp.title:GetFont()), path)
end)

-- Lot 8 redesigned the columns (labels, hidden empty columns, new ones), the dates and
-- the size of the window (resize grip): those parts are compared with the classic look
-- (game font objects, classic colours) below, and the rest of the window must still be
-- exactly the pre-theme one.
T.test("Window: under Classic the window is exactly the pre-theme one (baseline copy)", function()
  local root = Stub.ROOT
  local f = io.open(root .. "tests/baseline/TruePlayed_Camelot.toc", "r")
  if not f then T.skip("no Phase 0 baseline") end
  f:close()
  local function Play(tab)
    local ns = Start(Stub.ROOT == root and "actuel" or nil)
    ns.Window.Show(tab)
    Stub.Advance(10)
    return Snapshot(rawget(_G, "TruePlayedStatsFrame"), true), ns
  end
  for _, tab in ipairs({ "levels", "zones", "sessions" }) do
    Stub.Reset()
    Stub.ROOT = root .. "tests/baseline/"
    local ok, before = pcall(Play, tab)
    Stub.ROOT = root
    T.ok(ok, tostring(before))
    Stub.Reset()
    local after, ns = Play(tab)
    T.ok(#after > 20, tab .. " regions: " .. #after)
    T.eq(after, before, tab)
    -- the redesigned parts keep the classic look: game font objects, classic colours
    local tp = rawget(_G, "TruePlayedStatsFrame").tp
    local K = ns.C.COLORS
    local okColor = { [V(K.value[1]) .. V(K.value[2])] = true, [V(K.label[1]) .. V(K.label[2])] = true,
                      [V(K.accent[1]) .. V(K.accent[2])] = true }
    local n = 0
    for _, row in ipairs(tp.rows) do
      if row:IsShown() then
        for _, fs in ipairs(tp.cells[row]) do
          if fs:IsShown() then
            n = n + 1
            T.eq(rawget(fs, "_fontObject"), "GameFontHighlightSmall", tab .. " cell font object")
            T.eq(rawget(fs, "_font"), nil, tab .. " cell: no SetFont")
            T.ok(okColor[V(fs._tR) .. V(fs._tG)], tab .. " cell colour is a classic one")
          end
        end
      end
    end
    T.ok(n > 0, tab .. " cells")
    for c = 1, tp.layout.n do
      T.eq(rawget(tp.header[c], "_fontObject"), "GameFontHighlightSmall", tab .. " header font object")
      T.eq(Rgb(tp.header[c]), C3(K.label), tab .. " header colour")
    end
  end
end)
