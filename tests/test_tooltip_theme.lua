-- tests/test_tooltip_theme.lua - the themed tooltip (design/SPEC-themes.md 4, 8.5): the
-- private TooltipFrame of the non-native themes (rows, separators, gauge, panel), its
-- change-only refreshes, the classic paths (the Classic theme keeps GameTooltip, Broker
-- tooltips keep the classic palette), and the pair of ShowFor (block 2 beside block 1
-- with Shift, the breakdown bars face to face, placed and clamped as one box; the stack
-- when the screen is too narrow), and the breakdown bars of the native blocks (the
-- classic gauge beside each breakdown label: a frame of UIParent over the shared
-- GameTooltip, a child of block 2; shown only with our tooltip; the blocks widened for
-- them). Also the light theming of the statistics window (4.6, Window.ApplyTheme; the
-- graph panel is in test_graph.lua).
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

-- Those lines (and colours) as ShowFor's native blocks show them: each breakdown's label
-- alone on its line (its right text a space, under the bar), its first parts on a
-- continuation row of their own (same colours: label and value), the next ones as they
-- were.
local function BarLayout(ns, lines, colors)
  local L = ns.L
  local outL, outC = {}, {}
  for i, l in ipairs(lines) do
    local c = colors and colors[i]
    if (l[1] == L.TT_BREAKDOWN_LEVEL or l[1] == L.TT_BREAKDOWN_TOTAL) and l[2] ~= L.TT_NO_RATE then
      outL[#outL + 1] = { l[1], " " }
      outC[#outC + 1] = c
      outL[#outL + 1] = { " ", l[2] }
      outC[#outC + 1] = c
    else
      outL[#outL + 1] = l
      outC[#outC + 1] = c
    end
  end
  return outL, outC
end

-- Index of the line of GameTooltip-like `t` whose left text is `label` (nil: none).
local function LineOf(t, label)
  for i, l in ipairs(t._lines) do
    if l[1] == label then return i end
  end
  return nil
end

-- Whether native breakdown bar `b` (TooltipFrame.Bar) is visible.
local function BarOn(b)
  return b ~= nil and b.frame:IsVisible()
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
  local lines, colors = BarLayout(ns, Native(ns, false))
  T.eq(GameTooltip._lines, lines, "the classic lines (the breakdown's label alone: its bar beside it)")
  T.eq(GameTooltip._colors, colors, "the classic colours")
end)

---------------------------------------------------------------------------
-- Content
---------------------------------------------------------------------------

T.test("content parity, separators and gauge: short and Shift (block 2 beside block 1)", function()
  local ns, w = Start(nil)
  local Tooltip, L = ns.Tooltip, ns.L
  for _, shift in ipairs({ false, true }) do
    Stub.shift = shift
    Tooltip.ShowFor(w)
    local tp = ns.TooltipFrame.frame.tp
    local f2 = ns.TooltipFrame.frame2
    local lines = Native(ns, shift)
    -- the two blocks read as the one tooltip of Fill (Broker), less the blank line that
    -- opens its character section: block 2 is a frame of its own
    local texts, seps = FrameTexts(tp), SepCounts(tp)
    if shift then
      T.ok(f2 and f2:IsShown() and f2:GetOwner() == w, "Shift: block 2 shown for the same owner")
      for _, t in ipairs(FrameTexts(f2.tp)) do texts[#texts + 1] = t end
      local s2 = SepCounts(f2.tp)
      T.eq(seps.footer, 0, "block 1: no footer while block 2 shows")
      T.eq(s2.header, 0, "block 2: no header separator (its section title heads it)")
      for k, v in pairs(s2) do seps[k] = (seps[k] or 0) + v end
    else
      T.ok(f2 == nil or not f2:IsShown(), "short view: block 1 alone")
    end
    T.eq(texts, NativeTexts(lines), "row texts in order (shift " .. tostring(shift) .. ")")
    T.eq(seps, { header = 1, block = NativeBlanks(lines) - (shift and 1 or 0), footer = 1 }, "separators")
    -- kinds: title first, then the level section's title; block 1's breakdown is a gauge
    -- row then continuation rows only; the hint is the last row of the last block
    T.eq(tp.rows[1].kind, "title")
    T.eq(tp.rows[2].kind, "section")
    T.eq(tp.rows[2].left:GetText(), L.TT_SECTION_LEVEL)
    local last = shift and f2.tp or tp
    T.eq(last.rows[last.n].kind, "hint", "hint at the bottom of the last block")
    T.eq(last.rows[last.n].left:GetText(), L.TT_HINT)
    local gaugeRows = {}
    for i = 1, tp.n do
      local row = tp.rows[i]
      if row.kind == "gauge" then gaugeRows[#gaugeRows + 1] = i end
      T.ok(row.kind ~= "section" or row.left:GetText() ~= L.TT_SECTION_CHAR, "block 1: no character section")
      T.ok(row.kind ~= "hint" or not shift, "block 1: no hint while block 2 shows")
    end
    local levelParts = Tooltip.BreakdownParts(
      ns.Stats.Breakdown(ns.char.levels[ns.Tokens.ctx.level], {}), {})
    T.ok(levelParts > 0, "the level in progress has a breakdown")
    T.eq(#gaugeRows, 1, "block 1: the level's breakdown alone")
    T.eq(tp.rows[gaugeRows[1]].left:GetText(), L.TT_BREAKDOWN_LEVEL, "block 1: the level's breakdown label")
    T.eq(ShownCount(tp.gauges[1]), levelParts, "the level's gauge: one segment per part")
    if shift then
      -- block 2: its section title first, the character's breakdown with its own gauge
      local tp2 = f2.tp
      T.eq(tp2.rows[1].kind, "section")
      T.eq(tp2.rows[1].left:GetText(), L.TT_SECTION_CHAR)
      local g
      for i = 1, tp2.n do
        if tp2.rows[i].kind == "gauge" then
          T.eq(g, nil, "block 2: one gauge")
          g = i
        end
      end
      T.ok(g, "block 2: the character's gauge")
      T.eq(tp2.rows[g].left:GetText(), L.TT_BREAKDOWN_TOTAL, "block 2: the total breakdown label")
      T.eq(tp2.rows[g + 1].kind, "cont")
      T.eq(tp2.rows[g + 2].kind, "cont", "7 parts: two text rows")
      local nParts = Tooltip.BreakdownParts(ns.Stats.Breakdown(ns.char.life, {}), {})
      T.eq(nParts, 7)
      T.eq(ShownCount(tp2.gauges[1]), nParts, "the character's gauge: one segment per part")
      T.eq(ShownCount(tp2.gauges[2]), 0)
      T.eq(ShownCount(tp.gauges[2]), 0, "block 1: no second gauge")
    end
    Tooltip.Hide(w)
    T.no(ns.TooltipFrame.frame:IsShown())
    T.ok(f2 == nil or not f2:IsShown(), "hide hides both blocks")
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
  T.eq(tp.rows[2].left:GetText(), L.TT_SECTION_LEVEL)
  T.eq(Rgb(tp.rows[2].left), C3(pal.header), "section title: the header role")
  local level = tp.rows[3]
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
  -- gauge colours by part key (the short view: the level's breakdown)
  local keys = {}
  ns.Tooltip.BreakdownFracs(ns.Stats.Breakdown(ns.char.levels[ns.Tokens.ctx.level], {}), {}, keys)
  for i = 1, #keys do
    local c = tt.gauge.colors[keys[i]]
    local r, g, b = tp.gauge[i]:GetVertexColor()
    T.ok(Near(r, c[1]) and Near(g, c[2]) and Near(b, c[3]), "segment " .. i .. " colour " .. keys[i])
  end
  -- fonts: the title role on the title and the section titles, body on the rows
  local title = tp.rows[1].left
  T.eq((title:GetFont()), (ns.Themes.Font(tt.fonts.title[1], tt.fonts.title[2])))
  T.eq(select(2, title:GetFont()), select(2, ns.Themes.Font(tt.fonts.title[1], tt.fonts.title[2])))
  T.eq((tp.rows[2].left:GetFont()), (ns.Themes.Font(tt.fonts.title[1], tt.fonts.title[2])), "section title font")
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
    local blocks = { ns.TooltipFrame.frame.tp }
    if shift then blocks[2] = ns.TooltipFrame.frame2.tp end
    for b, tp in ipairs(blocks) do
      local n = 0
      for i = 1, tp.n do
        local right = tp.rows[i].right
        local text = right:GetText()
        if right:IsShown() and text and text ~= "" then
          n = n + 1
          local path, size = right:GetFont()
          T.eq({ path, size }, { path15, 15 },
            "block " .. b .. " row " .. i .. " (" .. tostring(tp.rows[i].kind) .. "): value font")
        end
      end
      T.ok(n >= 5, "block " .. b .. ": value cells drawn: " .. n)
    end
    ns.Tooltip.Hide(w)
  end
  Stub.shift = false
end)

---------------------------------------------------------------------------
-- The pair: block 2 (the character, Shift) beside block 1 (the level in progress), their
-- breakdown bars face to face; stacked under it when the two do not fit the screen's width
---------------------------------------------------------------------------

-- An owner of 80 x 14 px centred at (960 + x, 540 + y) on the 1920 x 1080 stub screen.
local function Owner(y, x)
  local o = CreateFrame("Frame", nil, UIParent)
  o:SetSize(80, 14)
  o:SetPoint("CENTER", UIParent, "CENTER", x or 0, y)
  o:Show()
  return o
end

-- The two blocks of the active theme: the private frames, or GameTooltip and the
-- addon's own second GameTooltip (nil until the first Shift).
local function Blocks(ns)
  if ns.Themes.Active().native then return GameTooltip, rawget(_G, "TruePlayedCharTooltip") end
  return ns.TooltipFrame.frame, ns.TooltipFrame.frame2
end

local function Point(f)
  local point, rel, relPoint, x, y = f:GetPoint(1)
  return { point, rel, relPoint, x, y, f:GetNumPoints() }
end

local function Edges(f)
  local l, b, w, h = f:GetRect()
  return l, b, l + w, b + h
end

-- A screen `w` px wide (UIParent; 1920 by default): 600 is too narrow for the two blocks
-- side by side in every theme, wide enough for the stack.
local function ScreenWidth(w)
  rawset(UIParent, "_width", w)
end

-- Centre y (screen) of a block's breakdown bar: on a private frame, its gauge (the first
-- segment) when the row labelled `label` is a gauge row, else that row's label; on a
-- GameTooltip, the left text of the line labelled `label` (the client's
-- "<name>TextLeft<i>"). nil when the block has no such row.
local function BarY(f, label)
  if rawget(f, "TP_Row") then
    local tp = f.tp
    for i = 1, tp.n do
      local row = tp.rows[i]
      if row.left:GetText() == label and row.left:IsShown() then
        local r = row.kind == "gauge" and tp.gauges[1][1] or row.left
        return (select(2, r:GetCenter()))
      end
    end
    return nil
  end
  for i, l in ipairs(f._lines) do
    if l[1] == label then return (select(2, _G[f:GetName() .. "TextLeft" .. i]:GetCenter())) end
  end
  return nil
end

-- Checks two shown blocks side by side: block 2 4 px right of block 1, its breakdown bar
-- at the height of block 1's (unless `tops`: the tops aligned instead). Returns the box
-- around both (left, bottom, right, top).
local function CheckSide(ns, f1, f2, where, tops)
  local L = ns.L
  local l1, b1, r1, t1 = Edges(f1)
  local l2, b2, r2, t2 = Edges(f2)
  T.near(l2, r1 + 4, 1e-9, where .. ": block 2 4 px right of block 1")
  if tops then
    T.near(t2, t1, 1e-9, where .. ": the tops aligned")
  else
    local y1, y2 = BarY(f1, L.TT_BREAKDOWN_LEVEL), BarY(f2, L.TT_BREAKDOWN_TOTAL)
    T.ok(y1 ~= nil and y2 ~= nil, where .. ": both breakdown rows")
    T.near(y2 or 0, y1 or -1, 1e-9, where .. ": the breakdown bars face to face")
  end
  return l1, math.min(b1, b2), r2, math.max(t1, t2)
end

T.test("pair: block 2 beside block 1 while Shift is held, natural widths, bars face to face (both theme kinds)", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    local ns = Start(theme)
    local Tooltip, L = ns.Tooltip, ns.L
    -- owners where the pair fits on its side of the owner (the next tests: where it does not)
    for _, case in ipairs({ { y = 300, below = true }, { y = -300, below = false } }) do
      local where = theme .. (case.below and " below" or " above")
      local owner = Owner(case.y)
      Stub.SetShift(false)
      Tooltip.ShowFor(owner)
      local f1, f2 = Blocks(ns)
      T.ok(f1:IsShown() and f1:GetOwner() == owner, where .. ": block 1 on hover")
      T.ok(f2 == nil or not f2:IsShown(), where .. ": no block 2 without Shift")
      local alone = case.below and { "TOP", owner, "BOTTOM", 0, -4, 1 } or { "BOTTOM", owner, "TOP", 0, 4, 1 }
      T.eq(Point(f1), alone, where .. ": block 1 alone placed as before")
      -- Shift: block 2 comes beside block 1, the pair is placed again
      Stub.SetShift(true)
      f1, f2 = Blocks(ns)
      T.ok(f2 and f2:IsShown() and f2:GetOwner() == owner, where .. ": block 2 while Shift is held")
      T.ok(f1:IsShown(), where .. ": block 1 stays")
      -- (GameTooltip by its template, as in the game)
      T.ok(f2:IsClampedToScreen() and f1:IsClampedToScreen(), where .. ": both clamped to the screen")
      -- each block at its own natural width: no width given to either
      local w1, w2 = f1:GetWidth(), f2:GetWidth()
      T.ok(w1 ~= w2, where .. ": the fixture: two natural widths (" .. w1 .. ", " .. w2 .. ")")
      if rawget(f1, "TP_Measure") then
        T.eq({ w1, w2 }, { f1:TP_Measure(), f2:TP_Measure() }, where .. ": each block at its natural width")
      else
        T.eq({ GameTooltip:GetMinimumWidth(), f2:GetMinimumWidth() }, { 0, 0 }, where .. ": no minimum width")
      end
      -- the labels: block 1's breakdown is the level's, block 2's the total
      T.ok(BarY(f1, L.TT_BREAKDOWN_LEVEL) and not BarY(f1, L.TT_BREAKDOWN_TOTAL), where .. ": block 1's label")
      T.ok(BarY(f2, L.TT_BREAKDOWN_TOTAL) and not BarY(f2, L.TT_BREAKDOWN_LEVEL), where .. ": block 2's label")
      local l, b, r, t = CheckSide(ns, f1, f2, where)
      local ol, ob, or_, ot = Edges(owner)
      local l1, b1, r1, t1 = Edges(f1)
      local _, b2, _, t2 = Edges(f2)
      T.near((l1 + r1) / 2, (ol + or_) / 2, 1e-9, where .. ": block 1 centred on the owner, as alone")
      T.ok(t2 < t1, where .. ": block 2 starts lower (its bar is nearer its top): " .. t2 .. " < " .. t1)
      T.ok(b2 < b1, where .. ": and ends lower")
      if case.below then
        T.near(t, ob - 4, 1e-9, where .. ": the pair 4 px under the owner")
      else
        T.near(b, ot + 4, 1e-9, where .. ": the pair 4 px over the owner")
      end
      T.ok(l >= 0 and r <= UIParent:GetWidth() and b >= 0 and t <= UIParent:GetHeight(), where .. ": on the screen")
      -- block 2 on the owner, block 1 on block 2; block 2's clamp rect is the pair's box
      T.eq(Point(f1), { "TOPRIGHT", f2, "TOPLEFT", -4, t1 - t2, 1 }, where .. ": block 1 on block 2's left")
      T.eq(f2:GetNumPoints(), 1)
      T.ok(select(2, f2:GetPoint(1)) == owner, where .. ": block 2 on the owner")
      local il, ir, it, ib = f2:GetClampRectInsets()
      T.eq({ il, ir }, { -(w1 + 4), 0 }, where .. ": block 2's clamp reaches over block 1")
      T.near(it, t - t2, 1e-9, where .. ": up to the pair's top")
      T.near(ib, b - b2, 1e-9, where .. ": down to the pair's bottom")
      if f1 == GameTooltip then
        T.eq({ f1:GetClampRectInsets() }, { 0, 0, 0, 0 }, where .. ": the shared GameTooltip's clamp untouched")
      end
      -- refreshed together on TICK, placed once
      local clears = 0
      for _, f in ipairs({ f1, f2 }) do
        local orig = f.ClearAllPoints
        rawset(f, "ClearAllPoints", function(self) clears = clears + 1 return orig(self) end)
      end
      Stub.Advance(3)
      T.eq(clears, 0, where .. ": steady ticks keep the anchors")
      T.ok(f2:IsShown() and f1:IsShown(), where .. ": both still shown")
      rawset(f1, "ClearAllPoints", nil)       -- the frames' own method again
      rawset(f2, "ClearAllPoints", nil)
      -- Shift released: block 2 goes, block 1 alone placed as before; pressed again: the pair
      Stub.SetShift(false)
      T.no(f2:IsShown(), where .. ": block 2 hidden on release")
      T.eq(Point(f1), alone, where .. ": block 1 back on the owner")
      if rawget(f1, "TP_Measure") then T.eq(f1:GetWidth(), f1:TP_Measure(), where .. ": block 1 at its width") end
      Stub.SetShift(true)
      T.ok(f2:IsShown(), where .. ": and back on the next press")
      CheckSide(ns, f1, f2, where .. ", pressed again")
      Tooltip.Hide(owner)
      T.no(f1:IsShown(), where .. ": hide: block 1")
      T.no(f2:IsShown(), where .. ": hide: block 2")
      Stub.SetShift(false)
    end
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- The screen clamp moves the pair as one piece: at a side edge of the screen, or where it
-- does not fit on its side of the owner (it then covers the owner), both blocks move
-- together, 4 px apart, their bars still face to face; never one block alone.
T.test("pair: the screen clamp moves both blocks as one piece (side edges, no room below or above)", function()
  for _, theme in ipairs({ "futuriste", "pixel", "actuel" }) do
    Stub.Reset()
    local ns, w = Start(theme)
    local Tooltip = ns.Tooltip
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    local cases = {
      { x = 900, y = 300, what = "at the right edge", edge = "right" },
      { x = -900, y = -300, what = "at the left edge", edge = "left" },
      { y = 1, what = "no room below", room = "below" },
      { y = -1, what = "no room above", room = "above" },
      { owner = w, what = "above the bar (default place)" },
    }
    for _, case in ipairs(cases) do
      local owner = case.owner or Owner(case.y, case.x)
      local where = theme .. ", " .. case.what
      Stub.SetShift(true)
      Tooltip.ShowFor(owner)
      local f1, f2 = Blocks(ns)
      T.ok(f2 and f2:IsShown(), where .. ": block 2 shown")
      local l, b, r, t = CheckSide(ns, f1, f2, where)
      T.ok(l >= -1e-9 and r <= W + 1e-9 and b >= -1e-9 and t <= H + 1e-9, where .. ": the whole pair on the screen")
      local ol, ob, or_, ot = Edges(owner)
      local cx = (ol + or_) / 2
      if case.edge == "right" then
        T.ok(cx + f1:GetWidth() / 2 + 4 + f2:GetWidth() > W, where .. ": the fixture: off the right edge")
        T.near(r, W, 1e-9, where .. ": both moved left, against the edge")
      elseif case.edge == "left" then
        T.ok(cx - f1:GetWidth() / 2 < 0, where .. ": the fixture: block 1 off the left edge")
        T.near(l, 0, 1e-9, where .. ": both moved right, against the edge")
      elseif case.room then
        local room = case.room == "below" and ob - 4 or H - ot - 4
        T.ok(t - b > room, where .. ": the fixture: the pair does not fit on its side (" .. (t - b) .. " > " .. room .. ")")
        if case.room == "below" then
          T.near(b, 0, 1e-9, where .. ": moved up to the screen's bottom, over the owner")
        else
          T.near(t, H, 1e-9, where .. ": moved down to the screen's top, over the owner")
        end
      end
      Tooltip.Hide(owner)
      Stub.SetShift(false)
    end
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- A pair taller than the whole screen (a UI 768 units high: the game's without a UI
-- scale, or less): block 2's clamp rect keeps the screen's height of the pair from its
-- top, so block 1 stays whole and only the bottom of block 2 goes off the screen.
T.test("pair: a pair taller than the screen keeps block 1 whole, only block 2's bottom off it", function()
  for _, case in ipairs({ { theme = "futuriste", h = 700 }, { theme = "pixel", h = 768 }, { theme = "actuel", h = 500 } }) do
    Stub.Reset()
    local ns, w = Start(case.theme)
    local Tooltip = ns.Tooltip
    local H = case.h
    rawset(UIParent, "_height", H)
    for _, o in ipairs({ { owner = w, what = "above the bar" }, { y = 100, what = "below an owner" } }) do
      local owner = o.owner or Owner(o.y)
      local where = case.theme .. ", " .. o.what
      Stub.SetShift(true)
      Tooltip.ShowFor(owner)
      local f1, f2 = Blocks(ns)
      local function Check(what)
        local _, b, _, t = CheckSide(ns, f1, f2, what)
        local _, b1, _, t1 = Edges(f1)
        local _, b2, _, t2 = Edges(f2)
        local total = math.max(t1, t2) - math.min(b1, b2)
        T.ok(total > H, what .. ": the fixture: taller than the screen (" .. total .. ")")
        T.ok(b1 >= -1e-9 and t1 <= H + 1e-9, what .. ": block 1 whole on the screen")
        T.near(t, H, 1e-9, what .. ": the pair's top at the screen's top")
        T.near(b, H - total, 1e-9, what .. ": only its bottom off the screen")
        T.ok(b2 < 0 and b2 < b1, what .. ": the bottom of block 2")
        T.near(select(4, f2:GetClampRectInsets()), (t - b2) - H, 1e-9, what .. ": block 2's clamp leaves it out")
      end
      Check(where)
      -- block 2 grows (AFK excluded: its pre-install note, above its breakdown): placed again
      local h2 = f2:GetHeight()
      ns.Core.SetSetting("exclude.afk", true)
      Stub.Advance(1)
      T.ok(f2:GetHeight() > h2, where .. ": block 2 grew")
      Check(where .. ", block 2 grown")
      ns.Core.SetSetting("exclude.afk", false)
      Tooltip.Hide(owner)
      Stub.SetShift(false)
    end
    T.eq(#Stub.errors, 0, case.theme .. ": no Lua error")
  end
end)

-- The anchors depend on block 1's width, both heights and where each breakdown row sits:
-- a block whose rows change (block 1's read-only line, block 2's pre-install note, both
-- above their breakdowns) places the pair again at that refresh, the bars still face to face.
T.test("pair: a block changes height: the pair is placed again at that refresh, bars still face to face", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    local ns = Start(theme)
    local Tooltip = ns.Tooltip
    for _, y in ipairs({ 300, -300 }) do
      local where = theme .. (y > 0 and " below" or " above")
      local owner = Owner(y)
      Stub.SetShift(true)
      Tooltip.ShowFor(owner)
      local f1, f2 = Blocks(ns)
      local _, ob, _, ot = Edges(owner)
      local function Check(what)
        local _, b, _, t = CheckSide(ns, f1, f2, where .. what)
        if y > 0 then
          T.near(t, ob - 4, 1e-9, where .. what .. ": still 4 px under the owner")
        else
          T.near(b, ot + 4, 1e-9, where .. what .. ": still 4 px over the owner")
        end
      end
      local h1, h2 = f1:GetHeight(), f2:GetHeight()
      ns.readOnly = true                          -- block 1 gets its read-only line
      Stub.Advance(1)
      T.ok(f1:GetHeight() > h1, where .. ": block 1 grew")
      Check(", block 1 grown")
      ns.readOnly = false
      Stub.Advance(1)
      T.eq(f1:GetHeight(), h1, where .. ": block 1 back")
      Check(", block 1 back")
      ns.Core.SetSetting("exclude.afk", true)     -- block 2 gets its pre-install note
      Stub.Advance(1)
      T.ok(f2:GetHeight() > h2, where .. ": block 2 grew")
      Check(", block 2 grown")
      ns.Core.SetSetting("exclude.afk", false)
      Stub.Advance(1)
      Check(", block 2 back")
      Tooltip.Hide(owner)
      Stub.SetShift(false)
    end
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- The pair's box is what is placed and clamped, whichever block makes its top or bottom:
-- rows added under block 1's fill (block 1 then ends lower than block 2) or over block 2's
-- (block 2's bar lower in its block: block 2 starts higher). Taller than the screen with
-- block 2 starting higher: the clamp rect is moved down to keep block 1 whole, so block 2's
-- top goes off the screen too (the bars still face to face).
T.test("pair: whichever block makes the pair's top or bottom, the box is placed and clamped", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    local ns = Start(theme)
    local Tooltip = ns.Tooltip
    local fill = Tooltip.Fill
    local pad1, pad2 = 0, 0                      -- rows added under block 1's fill, over block 2's
    Tooltip.Fill = function(tt, detailed, hint, pal, part)
      if part == 2 then for i = 1, pad2 do tt:AddLine("pad " .. i) end end
      local more, row = fill(tt, detailed, hint, pal, part)
      if part == 1 then for i = 1, pad1 do tt:AddLine("pad " .. i) end end
      return more, row
    end
    for _, case in ipairs({ { pad1 = 25, pad2 = 0, what = "block 1 ends lower" },
                            { pad1 = 0, pad2 = 15, what = "block 2 starts higher" } }) do
      pad1, pad2 = case.pad1, case.pad2
      for _, y in ipairs({ 350, -350 }) do
        local where = theme .. ", " .. case.what .. (y > 0 and ", below" or ", above")
        local owner = Owner(y)
        Stub.SetShift(true)
        Tooltip.ShowFor(owner)
        local f1, f2 = Blocks(ns)
        local _, b, _, t = CheckSide(ns, f1, f2, where)
        local _, b1, _, t1 = Edges(f1)
        local _, b2, _, t2 = Edges(f2)
        if pad1 > 0 then
          T.ok(b1 < b2, where .. ": the fixture: block 1 ends lower (" .. b1 .. " < " .. b2 .. ")")
        else
          T.ok(t2 > t1, where .. ": the fixture: block 2 starts higher (" .. t2 .. " > " .. t1 .. ")")
        end
        local _, ob, _, ot = Edges(owner)
        if y > 0 then
          T.near(t, ob - 4, 1e-9, where .. ": the pair 4 px under the owner")
        else
          T.near(b, ot + 4, 1e-9, where .. ": the pair 4 px over the owner")
        end
        T.ok(b >= 0 and t <= UIParent:GetHeight(), where .. ": on the screen")
        Tooltip.Hide(owner)
      end
    end
    -- block 2 starting higher, the pair taller than a screen block 1 fits on
    Tooltip.ShowFor(Owner(300))
    local f1, f2 = Blocks(ns)
    local _, b1, _, t1 = Edges(f1)
    local _, _, _, t2 = Edges(f2)
    local h1 = t1 - b1
    local H = math.floor(h1 + (t2 - t1) / 2)
    T.ok(t2 > t1 and h1 < H, theme .. ": the fixture: block 1 (" .. h1 .. ") fits a screen of " .. H)
    Tooltip.Hide()
    rawset(UIParent, "_height", H)
    for _, y in ipairs({ 50, -50 }) do
      local where = theme .. ", taller than the screen, block 2 higher" .. (y > 0 and ", below" or ", above")
      local owner = Owner(y)
      Tooltip.ShowFor(owner)
      local _, b, _, t = CheckSide(ns, f1, f2, where)
      _, b1, _, t1 = Edges(f1)
      _, _, _, t2 = Edges(f2)
      T.ok(t - b > H, where .. ": the fixture: taller than the screen (" .. (t - b) .. " > " .. H .. ")")
      T.ok(b1 >= -1e-9 and t1 <= H + 1e-9, where .. ": block 1 whole on the screen")
      T.near(b1, 0, 1e-9, where .. ": its bottom on the screen's")
      T.ok(t2 > H, where .. ": block 2's top off the screen")
      Tooltip.Hide(owner)
    end
    Tooltip.Fill = fill
    Stub.SetShift(false)
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- A block without a breakdown row (no tracked time: its "breakdown" line has no part,
-- no bar to face): the tops of the two blocks are aligned.
T.test("pair: a block without a breakdown row: the tops aligned (both theme kinds)", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    local ns = Start(theme)
    local Tooltip, L = ns.Tooltip, ns.L
    local parts = Tooltip.BreakdownParts
    local empty                                   -- "level" or "total": the breakdown left without parts
    Tooltip.BreakdownParts = function(bd, out)
      local life = ns.Stats.Breakdown(ns.char.life, {})
      local total = bd.tracked == life.tracked
      if (empty == "total") == total and empty ~= nil then
        for i = #out, 1, -1 do out[i] = nil end
        return 0, false
      end
      return parts(bd, out)
    end
    for _, which in ipairs({ "level", "total" }) do
      for _, y in ipairs({ 300, -300 }) do
        local where = theme .. ", no " .. which .. " breakdown" .. (y > 0 and ", below" or ", above")
        empty = which
        local owner = Owner(y)
        Stub.SetShift(true)
        Tooltip.ShowFor(owner)
        local f1, f2 = Blocks(ns)
        local label = which == "level" and L.TT_BREAKDOWN_LEVEL or L.TT_BREAKDOWN_TOTAL
        local f = which == "level" and f1 or f2
        local found = false
        if rawget(f, "TP_Row") then
          for i = 1, f.tp.n do
            local row = f.tp.rows[i]
            if row.left:GetText() == label then
              found = row.kind == "pair" and row.right:GetText() == L.TT_NO_RATE
            end
          end
        else
          for _, l in ipairs(f._lines) do
            if l[1] == label then found = l[2] == L.TT_NO_RATE end
          end
        end
        T.ok(found, where .. ": the fixture: the dimmed line without parts")
        local _, b, _, t = CheckSide(ns, f1, f2, where, true)
        local _, ob, _, ot = Edges(owner)
        if y > 0 then T.near(t, ob - 4, 1e-9, where .. ": under the owner") else T.near(b, ot + 4, 1e-9, where) end
        T.eq(select(5, f1:GetPoint(1)), 0, where .. ": block 1 on block 2's top")
        -- the parts come back: the bars face to face at the next refresh
        empty = nil
        Stub.Advance(1)
        CheckSide(ns, f1, f2, where .. ", parts back")
        Tooltip.Hide(owner)
        Stub.SetShift(false)
      end
    end
    Tooltip.BreakdownParts = parts
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- The stack, the fallback of a screen too narrow for the pair side by side: block 2 under
-- block 1, one width (the larger natural one), 4 px apart, block 1 on top, placed below or
-- above the owner as one piece. A screen that narrows (or widens) while shown switches at
-- the next refresh.
T.test("stack: a screen too narrow for the pair: block 2 under block 1, same width (both theme kinds)", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    local ns = Start(theme)
    local Tooltip = ns.Tooltip
    ScreenWidth(600)
    -- owners where the whole stack fits on the screen (the next test: where it does not)
    for _, case in ipairs({ { y = 500, below = true }, { y = -450, below = false } }) do
      local where = theme .. (case.below and " below" or " above")
      local owner = Owner(case.y)
      Stub.SetShift(false)
      Tooltip.ShowFor(owner)
      local f1 = Blocks(ns)
      local alone = case.below and { "TOP", owner, "BOTTOM", 0, -4, 1 } or { "BOTTOM", owner, "TOP", 0, 4, 1 }
      T.eq(Point(f1), alone, where .. ": block 1 alone placed as before")
      Stub.SetShift(true)
      local f2
      f1, f2 = Blocks(ns)
      T.ok(f2 and f2:IsShown() and f2:GetOwner() == owner, where .. ": block 2 while Shift is held")
      local ol, ob, or_, ot = Edges(owner)
      local l1, b1, r1, t1 = Edges(f1)
      local l2, b2, r2, t2 = Edges(f2)
      T.eq(f2:GetWidth(), f1:GetWidth(), where .. ": same width")
      T.eq({ l2, r2 }, { l1, r1 }, where .. ": one column")
      T.near((l1 + r1) / 2, (ol + or_) / 2, 1e-9, where .. ": centred on the owner")
      -- block 2 on the owner, block 1 on block 2; block 2's clamp rect reaches over block 1
      local h1 = f1:GetHeight()
      T.eq(Point(f1), { "BOTTOM", f2, "TOP", 0, 4, 1 }, where .. ": block 1 on block 2 (on top)")
      T.eq({ f2:GetClampRectInsets() }, { 0, 0, h1 + 4, 0 }, where .. ": block 2 clamped with block 1")
      if f1 == GameTooltip then
        T.eq({ f1:GetClampRectInsets() }, { 0, 0, 0, 0 }, where .. ": the shared GameTooltip's clamp untouched")
      end
      if case.below then
        T.eq(Point(f2), { "TOP", owner, "BOTTOM", 0, -(4 + h1 + 4), 1 }, where .. ": block 2 under block 1's room")
        T.near(t1, ob - 4, 1e-9, where .. ": block 1 under the owner")
        T.near(t2, b1 - 4, 1e-9, where .. ": 4 px between the blocks")
      else
        T.eq(Point(f2), { "BOTTOM", owner, "TOP", 0, 4, 1 }, where .. ": block 2 on the owner")
        T.near(b2, ot + 4, 1e-9)
        T.near(b1, t2 + 4, 1e-9, where .. ": 4 px between the blocks")
      end
      -- refreshed together on TICK, placed once
      local clears = 0
      for _, f in ipairs({ f1, f2 }) do
        local orig = f.ClearAllPoints
        rawset(f, "ClearAllPoints", function(self) clears = clears + 1 return orig(self) end)
      end
      Stub.Advance(3)
      T.eq(clears, 0, where .. ": steady ticks keep the anchors")
      rawset(f1, "ClearAllPoints", nil)
      rawset(f2, "ClearAllPoints", nil)
      -- the screen widens: side by side at the next refresh; narrows again: the stack
      ScreenWidth(1920)
      Stub.Advance(1)
      CheckSide(ns, f1, f2, where .. ", wide screen")
      if rawget(f1, "TP_Measure") then
        T.eq({ f1:GetWidth(), f2:GetWidth() }, { f1:TP_Measure(), f2:TP_Measure() }, where .. ": natural widths")
      else
        T.eq(GameTooltip:GetMinimumWidth(), 0, where .. ": GameTooltip at its own width")
      end
      ScreenWidth(600)
      Stub.Advance(1)
      l1, b1, r1 = Edges(f1)
      local _                                      -- (block 2's bottom: not needed here)
      l2, _, r2, t2 = Edges(f2)
      T.eq({ l2, r2 }, { l1, r1 }, where .. ": one column again")
      T.near(b1, t2 + 4, 1e-9, where .. ": stacked again, 4 px apart")
      -- Shift released: block 2 goes, block 1 alone placed as before
      Stub.SetShift(false)
      T.no(f2:IsShown(), where .. ": block 2 hidden on release")
      T.eq(Point(f1), alone, where .. ": block 1 back on the owner")
      Tooltip.Hide(owner)
      T.no(f1:IsShown() or f2:IsShown(), where .. ": hide: both")
    end
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- The screen clamp moves the stack as one piece: where the stack does not fit on its side
-- of the owner, both blocks move together (covering the owner), 4 px apart, never one
-- pushed onto the other (each block clamped alone did that).
T.test("stack: a stack that does not fit on its side moves as one piece, never one block onto the other", function()
  for _, theme in ipairs({ "futuriste", "pixel", "actuel" }) do
    Stub.Reset()
    local ns, w = Start(theme)
    local Tooltip = ns.Tooltip
    ScreenWidth(600)
    local H = UIParent:GetHeight()
    local cases = { { y = 60, what = "below an owner" }, { y = -60, what = "above an owner" } }
    if theme ~= "actuel" then cases[3] = { owner = w, what = "above the bar (default place)" } end
    for _, case in ipairs(cases) do
      local owner = case.owner or Owner(case.y)
      local where = theme .. ", " .. case.what
      Stub.SetShift(true)
      Tooltip.ShowFor(owner)
      local f1, f2 = Blocks(ns)
      T.ok(f2 and f2:IsShown(), where .. ": block 2 shown")
      local _, ob, _, ot = Edges(owner)
      local l1, b1, r1, t1 = Edges(f1)
      local l2, b2, r2, t2 = Edges(f2)
      local total = (t1 - b1) + 4 + (t2 - b2)
      local room = case.y and case.y > 0 and ob - 4 or H - ot - 4
      T.ok(total > room and total <= H, where .. ": the fixture: the stack does not fit on its side ("
        .. total .. " > " .. room .. ") but fits on the screen")
      T.near(b1, t2 + 4, 1e-9, where .. ": block 1 right on block 2, 4 px apart (no overlap)")
      T.ok(b2 >= -1e-9 and t1 <= H + 1e-9, where .. ": the whole stack on the screen")
      T.eq({ l2, r2 }, { l1, r1 }, where .. ": one column")
      Tooltip.Hide(owner)
      Stub.SetShift(false)
    end
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- A stack taller than the whole screen (a UI 768 units high: the game's without a UI
-- scale): block 2's clamp rect leaves out its bottom, so block 1 stays whole at the top of
-- the screen, block 2 right under it, and only block 2's last lines go off the screen.
T.test("stack: a stack taller than the screen keeps block 1 whole on top, only block 2's bottom off it", function()
  for _, case in ipairs({ { theme = "futuriste", h = 768 }, { theme = "pixel", h = 768 }, { theme = "actuel", h = 600 } }) do
    Stub.Reset()
    local ns, w = Start(case.theme)
    local Tooltip = ns.Tooltip
    local H = case.h
    rawset(UIParent, "_height", H)
    ScreenWidth(600)
    for _, o in ipairs({ { owner = w, what = "above the bar" }, { y = 100, what = "below an owner" } }) do
      local owner = o.owner or Owner(o.y)
      local where = case.theme .. ", " .. o.what
      Stub.SetShift(true)
      Tooltip.ShowFor(owner)
      local f1, f2 = Blocks(ns)
      local _, b1, _, t1 = Edges(f1)
      local _, b2, _, t2 = Edges(f2)
      local total = (t1 - b1) + 4 + (t2 - b2)
      T.ok(total > H, where .. ": the fixture: taller than the screen (" .. total .. ")")
      T.near(b1, t2 + 4, 1e-9, where .. ": 4 px apart, no overlap")
      T.near(t1, H, 1e-9, where .. ": block 1 whole, at the top of the screen")
      T.near(b2, H - total, 1e-9, where .. ": only block 2's bottom off the screen")
      local l, r, top, bottom = f2:GetClampRectInsets()
      T.eq({ l, r, top }, { 0, 0, (t1 - b1) + 4 }, where .. ": block 2's clamp reaches over block 1")
      T.near(bottom, total - H, 1e-9, where .. ": and leaves out the part that cannot fit")
      -- block 2 grows (AFK excluded: its pre-install note): placed again at that refresh
      local h2 = f2:GetHeight()
      ns.Core.SetSetting("exclude.afk", true)
      Stub.Advance(1)
      T.ok(f2:GetHeight() > h2, where .. ": block 2 grew")
      _, b1, _, t1 = Edges(f1)
      _, b2, _, t2 = Edges(f2)
      total = (t1 - b1) + 4 + (t2 - b2)
      T.near(b1, t2 + 4, 1e-9, where .. ": still 4 px apart")
      T.near(t1, H, 1e-9, where .. ": block 1 still whole on top")
      T.near(select(4, f2:GetClampRectInsets()), total - H, 1e-9, where .. ": the cut follows")
      ns.Core.SetSetting("exclude.afk", false)
      Tooltip.Hide(owner)
      Stub.SetShift(false)
    end
    T.eq(#Stub.errors, 0, case.theme .. ": no Lua error")
  end
end)

-- Block 2's anchor (below the owner) and its clamp depend on block 1's height: a block 1
-- that grows or shrinks (here the read-only line) places the stack again at that refresh.
T.test("stack: block 1 changes height: the stack is placed again at that refresh, 4 px apart", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    local ns = Start(theme)
    local Tooltip = ns.Tooltip
    ScreenWidth(600)
    for _, y in ipairs({ 500, -450 }) do
      local where = theme .. (y > 0 and " below" or " above")
      local owner = Owner(y)
      Stub.SetShift(true)
      Tooltip.ShowFor(owner)
      local f1, f2 = Blocks(ns)
      local h0 = f1:GetHeight()
      ns.readOnly = true                          -- block 1 gets its read-only line
      Stub.Advance(1)
      local h1 = f1:GetHeight()
      T.ok(h1 > h0, where .. ": block 1 grew (" .. h0 .. " -> " .. h1 .. ")")
      local _, b1, _, t1 = Edges(f1)
      local _, b2, _, t2 = Edges(f2)
      local _, ob, _, ot = Edges(owner)
      T.near(b1, t2 + 4, 1e-9, where .. ": still 4 px apart")
      T.eq({ f2:GetClampRectInsets() }, { 0, 0, h1 + 4, 0 }, where .. ": block 2's clamp follows")
      if y > 0 then
        T.near(t1, ob - 4, 1e-9, where .. ": block 1 still under the owner")
      else
        T.near(b2, ot + 4, 1e-9, where .. ": block 2 still on the owner")
      end
      ns.readOnly = false
      Stub.Advance(1)
      T.eq(f1:GetHeight(), h0, where .. ": back")
      _, b1 = Edges(f1)
      _, _, _, t2 = Edges(f2)
      T.near(b1, t2 + 4, 1e-9, where .. ": 4 px apart again")
      Tooltip.Hide(owner)
      Stub.SetShift(false)
    end
    T.eq(#Stub.errors, 0, theme .. ": no Lua error")
  end
end)

-- The client hides GameTooltip with its owner (a menu closed by a click hides its button
-- without OnLeave) before any call to Tooltip.Hide: the minimum width given to block 1
-- (stacked: one width) goes with that hide, and the refresh that then finds another
-- owner leaves that owner's own minimum alone. Side by side, none is ever given.
T.test("native: block 1's minimum width goes when GameTooltip hides; another owner's is never reset", function()
  local ns, w = Start("actuel")
  local Tooltip = ns.Tooltip
  Stub.SetShift(true)
  Tooltip.ShowFor(w)
  T.eq(GameTooltip:GetMinimumWidth(), 0, "side by side: GameTooltip at its own width")
  Tooltip.Hide(w)
  ScreenWidth(600)                                -- stacked from here on
  Tooltip.ShowFor(w)
  T.ok(GameTooltip:GetMinimumWidth() > 0, "block 1 widened (block 2 is the wider here)")
  GameTooltip:Hide()                              -- the client, with the owner, no OnLeave
  T.eq(GameTooltip:GetMinimumWidth(), 0, "no minimum left once GameTooltip hides")
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")   -- the next owner, before our next tick
  GameTooltip:SetMinimumWidth(123)
  GameTooltip:AddLine("someone else")
  GameTooltip:Show()
  Stub.Advance(2)                                 -- our refresh: not ours any more
  T.no(Tooltip.IsShownFor(w))
  T.eq(GameTooltip:GetMinimumWidth(), 123, "the other owner's minimum kept")
  GameTooltip:Hide()
  -- another owner takes the shown GameTooltip without hiding it: our minimum stays until
  -- that tooltip hides (never reset under it), then goes
  Tooltip.ShowFor(w)
  local ours = GameTooltip:GetMinimumWidth()
  T.ok(ours > 0)
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:AddLine("someone else")
  GameTooltip:Show()
  Stub.Advance(2)
  T.no(Tooltip.IsShownFor(w))
  T.eq(GameTooltip:GetMinimumWidth(), ours, "not reset under the other owner's tooltip")
  -- our next show on the private frames (another theme) leaves it alone too
  ns.Core.SetSetting("theme", "futuriste")
  Tooltip.ShowFor(w)
  T.ok(ns.TooltipFrame.frame:IsShown())
  T.eq(GameTooltip:GetMinimumWidth(), ours, "a show on the private frames does not reset it either")
  Tooltip.Hide(w)
  GameTooltip:Hide()
  T.eq(GameTooltip:GetMinimumWidth(), 0, "gone with its hide")
  -- a stacked show widened block 1; the screen widens while shown: side by side, the
  -- minimum dropped at that refresh
  ns.Core.SetSetting("theme", "actuel")
  Tooltip.ShowFor(w)
  T.ok(GameTooltip:GetMinimumWidth() > 0, "stacked: widened")
  ScreenWidth(1920)
  Stub.Advance(1)
  T.eq(GameTooltip:GetMinimumWidth(), 0, "side by side: dropped at the next refresh")
  Tooltip.Hide(w)
  Stub.SetShift(false)
  T.eq(#Stub.errors, 0)
end)

T.test("pair: the footer hint ends block 2 (minimap hint too), side by side or stacked", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    for _, narrow in ipairs({ false, true }) do
      Stub.Reset()
      local ns, w = Start(theme)
      local L = ns.L
      local where = theme .. (narrow and ", stacked" or ", side by side")
      if narrow then ScreenWidth(600) end
      local hint = L.TT_HINT_MM_OPTIONS
      Stub.SetShift(false)
      ns.Tooltip.ShowFor(w, hint)
      local f1 = Blocks(ns)
      local function LastText(f)
        if rawget(f, "TP_Row") then
          local tp = f.tp
          return tp.rows[tp.n].left:GetText(), tp.rows[tp.n].kind
        end
        local lines = f._lines
        return lines[#lines][1], "hint"
      end
      T.eq({ LastText(f1) }, { hint, "hint" }, where .. ": short: the hint ends block 1")
      Stub.SetShift(true)
      local f2
      f1, f2 = Blocks(ns)
      T.eq({ LastText(f2) }, { hint, "hint" }, where .. ": Shift: the hint ends block 2")
      T.ok(LastText(f1) ~= hint, where .. ": Shift: not in block 1")
      local w1, w2 = f1:GetWidth(), f2:GetWidth()
      if narrow then
        -- the width: the larger natural one, block 1 never narrower than alone
        T.eq(w1, w2, where .. ": same width")
        if rawget(f1, "TP_Measure") then
          local m1, m2 = f1:TP_Measure(), f2:TP_Measure()
          T.eq(w1, math.max(m1, m2), where .. ": the larger natural width")
        else
          -- GameTooltip widened (SetMinimumWidth) to block 2's width only when narrower,
          -- for this show only
          local m = GameTooltip:GetMinimumWidth()
          T.ok(m == 0 or m == w2, where .. ": GameTooltip widened to block 2 (" .. m .. ")")
        end
      else
        CheckSide(ns, f1, f2, where)
      end
      ns.Tooltip.Hide(w)
      Stub.SetShift(false)
      if not rawget(f1, "TP_Measure") then
        T.eq(GameTooltip:GetMinimumWidth(), 0, where .. ": the shared GameTooltip keeps no minimum width")
      end
    end
  end
end)

T.test("stack: when block 1 is the wider one, block 2 takes its width (both theme kinds)", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    local ns, w = Start(theme)
    ScreenWidth(600)
    ns.L.ADDON_TITLE = string.rep("W", 80)        -- a title row wider than any of block 2
    Stub.SetShift(true)
    ns.Tooltip.ShowFor(w)
    local f1, f2 = Blocks(ns)
    T.ok(f2 and f2:IsShown(), theme .. ": block 2 shown")
    T.eq(f2:GetWidth(), f1:GetWidth(), theme .. ": same width")
    if rawget(f1, "TP_Measure") then
      T.ok(f1:TP_Measure() > f2:TP_Measure(), theme .. ": block 1 measures wider")
      T.eq(f2:GetWidth(), f1:TP_Measure(), theme .. ": block 2 at block 1's width")
    else
      T.eq(GameTooltip:GetMinimumWidth(), 0, theme .. ": GameTooltip at its own width")
      T.eq(f2:GetMinimumWidth(), f1:GetWidth(), theme .. ": block 2 widened to it")
    end
    -- Shift released: block 1 alone, at its own width
    Stub.SetShift(false)
    T.no(f2:IsShown())
    if rawget(f1, "TP_Measure") then T.eq(f1:GetWidth(), f1:TP_Measure(), theme .. ": block 1 alone") end
    ns.Tooltip.Hide(w)
  end
end)

-- The client's SetMinimumWidth may count the tooltip's padding or not: the first widening
-- (stacked) learns which, so both GameTooltips end up one width either way.
T.test("native: one width when stacked, whether SetMinimumWidth includes the padding or not", function()
  local ns, w = Start("actuel")
  ScreenWidth(600)
  -- this client: the minimum is the text's width, the padding (20 px here) comes on top
  local show = GameTooltip.Show
  rawset(GameTooltip, "Show", function(self)
    local min = rawget(self, "_minWidth")
    rawset(self, "_minWidth", nil)
    show(self)                                  -- the lines' own width, padding included
    rawset(self, "_minWidth", min)
    if min and min + 20 > self._width then self._width = min + 20 end
  end)
  Stub.SetShift(true)
  ns.Tooltip.ShowFor(w)
  local t2 = rawget(_G, "TruePlayedCharTooltip")
  T.ok(GameTooltip:GetMinimumWidth() > 0, "block 1 widened (block 2 is the wider here)")
  T.eq(GameTooltip:GetWidth(), t2:GetWidth(), "same width")
  Stub.Advance(3)
  T.eq(GameTooltip:GetWidth(), t2:GetWidth(), "same width on refreshes")
  ns.Tooltip.Hide(w)
  Stub.SetShift(false)
  T.eq(GameTooltip:GetMinimumWidth(), 0, "no minimum width left on GameTooltip")
end)

T.test("pair: hiding the tooltip hides both blocks (leave, owner gone, theme change, foreign owner)", function()
  local ns, w = Start(nil)
  local Tooltip, Core = ns.Tooltip, ns.Core
  Stub.SetShift(true)
  -- leave
  Stub.RunScript(w, "OnEnter")
  local f1, f2 = Blocks(ns)
  T.ok(f1:IsShown() and f2 and f2:IsShown(), "both shown on hover with Shift")
  Stub.RunScript(w, "OnLeave")
  T.no(f1:IsShown() or f2:IsShown(), "leave: both hidden")
  -- an owner hidden without OnLeave (addon compartment): both hidden at the next refresh
  local btn = Owner(0)
  Tooltip.ShowFor(btn)
  T.ok(f1:IsShown() and f2:IsShown())
  btn:Hide()
  Stub.Advance(2)
  T.no(f1:IsShown() or f2:IsShown(), "owner gone: both hidden")
  T.no(Tooltip.IsShownFor(btn))
  -- a theme switch
  Tooltip.ShowFor(w)
  T.ok(f2:IsShown())
  Core.SetSetting("theme", "druid")
  T.no(f1:IsShown() or f2:IsShown(), "theme change: both hidden")
  -- native: another addon takes GameTooltip; our block 2 goes at the next tick
  Core.SetSetting("theme", "actuel")
  Tooltip.ShowFor(w)
  local g1, g2 = Blocks(ns)
  T.ok(g1 == GameTooltip and g2 and g2:IsShown(), "actuel: both GameTooltips shown")
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:AddLine("someone else")
  GameTooltip:Show()
  Stub.Advance(2)
  T.no(g2:IsShown(), "foreign owner: block 2 hidden")
  T.ok(GameTooltip:IsShown() and GameTooltip:NumLines() == 1, "the foreign tooltip left alone")
  T.no(Tooltip.IsShownFor(w))
  Stub.SetShift(false)
  T.eq(#Stub.errors, 0)
end)

T.test("pair: TICK refreshes both blocks, no region, font or text work on steady values", function()
  local ns, w = Start(nil)
  local Tooltip, L = ns.Tooltip, ns.L
  Stub.SetShift(true)
  Tooltip.ShowFor(w)
  Stub.SetShift(false)
  Stub.SetShift(true)
  local f1, f2 = Blocks(ns)
  local tp2 = f2.tp
  local function Net()
    for i = 1, tp2.n do
      if tp2.rows[i].left:GetText() == L.TT_NET then return tp2.rows[i].right:GetText() end
    end
  end
  local n0 = Net()
  T.ok(n0 ~= nil, "block 2: the network line")
  Stub.fps = 31
  Stub.Advance(1)
  T.ok(Net() ~= n0, "block 2 refreshed on TICK: " .. tostring(n0) .. " -> " .. tostring(Net()))
  local c0, fonts0 = Created(), Stub.calls.SetFont
  local texts, counts = {}, {}
  for _ = 1, 60 do
    for i = 1, tp2.n do
      local row = tp2.rows[i]
      texts[i], counts[i] = row.right:GetText(), rawget(row.right, "_setTextCount")
    end
    Stub.Advance(1)
    for i = 1, tp2.n do
      local row = tp2.rows[i]
      if row.right:GetText() == texts[i] then
        T.eq(rawget(row.right, "_setTextCount"), counts[i], "block 2: no SetText on an unchanged value " .. i)
      end
    end
  end
  T.eq(Created(), c0, "no region created while both are shown")
  T.eq(Stub.calls.SetFont, fonts0, "no SetFont on steady ticks")
  T.ok(f1:IsShown() and f2:IsShown())
  Tooltip.Hide(w)
  Stub.SetShift(false)
  T.eq(Stub.onUpdateCount, 0)
end)

-- A steady refresh of the shown pair allocates nothing outside the fill (whose texts are
-- strings): Tooltip.Fill is replayed (the last real fill's rows, no string built, the
-- same breakdown rows returned), and on the GameTooltips the stub's own line and size
-- work is taken out (it builds strings). What is measured: the refresh handler, the
-- second block's target, the show (natural widths or one width), the fit test, the
-- breakdown rows' positions (TP_RowY, the line texts looked up once) and the anchor checks.
T.test("pair: a steady refresh allocates nothing (side by side and stacked, both theme kinds)", function()
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    for _, narrow in ipairs({ false, true }) do
      Stub.Reset()
      local ns, w = Start(theme)
      local Tooltip = ns.Tooltip
      local where = theme .. (narrow and ", stacked" or ", side by side")
      if narrow then ScreenWidth(600) end
      Stub.SetShift(true)
      Tooltip.ShowFor(w)
      Stub.Advance(1)
      local f1, f2 = Blocks(ns)
      -- the last real fill of each block, and what Fill returned for it
      local fill = Tooltip.Fill
      local rec = {}
      Tooltip.Fill = function(tt, ...)
        local more, row = fill(tt, ...)
        rec[tt] = { more = more, row = row }
        return more, row
      end
      Stub.Advance(1)
      Tooltip.Fill = fill
      T.ok(rec[f1] and rec[f2] and rec[f1].row > 0 and rec[f2].row > 0, where .. ": both fills seen, with their rows")
      local replay
      local saved = {}                          -- the GameTooltips' own ClearLines and Show
      if rawget(f1, "TP_Row") then
        local pal = ns.Themes.Active().tt.colors
        for _, f in ipairs({ f1, f2 }) do
          local r, tp = rec[f], f.tp
          r.n, r.kinds, r.lefts, r.rights = tp.n, {}, {}, {}
          for i = 1, tp.n do
            local row = tp.rows[i]
            r.kinds[i], r.lefts[i] = row.kind, row.left:GetText()
            r.rights[i] = row.right:IsShown() and row.right:GetText() or nil
          end
        end
        replay = function(tt)
          local r = rec[tt]
          for i = 1, r.n do tt:TP_Row(r.kinds[i], r.lefts[i], r.rights[i], pal.label, pal.value) end
          return r.more, r.row
        end
      else
        for _, f in ipairs({ f1, f2 }) do
          saved[f] = { rawget(f, "ClearLines"), rawget(f, "Show") }
          rawset(f, "ClearLines", function() end)
          rawset(f, "Show", function(self) self._shown = true end)
        end
        replay = function(tt)
          local r = rec[tt]
          return r.more, r.row
        end
      end
      Tooltip.Fill = replay
      local function Refresh() Stub.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1) end
      Refresh()
      Refresh()
      local _, _, _, t1 = Edges(f1)
      -- native: both breakdown bars shown, never anchored, sized or recoloured again
      local bars, barCalls = { ns.TooltipFrame.bar, ns.TooltipFrame.bar2 }, 0
      local barMethods = { "ClearAllPoints", "SetPoint", "SetSize", "SetFrameLevel", "SetScale", "SetVertexColor",
                           "Show", "Hide" }
      if not rawget(f1, "TP_Row") then
        T.ok(BarOn(bars[1]) and BarOn(bars[2]), where .. ": both bars shown")
        for _, b in ipairs(bars) do
          for _, r in ipairs({ b.frame, b.segs[1], b.segs[2] }) do
            for _, m in ipairs(barMethods) do
              local orig = r[m]
              rawset(r, m, function(...)
                barCalls = barCalls + 1
                return orig(...)
              end)
            end
          end
        end
      end
      local kb = T.alloc(Refresh, 500)
      Tooltip.Fill = fill
      T.ok(kb < 0.5, where .. format(": allocated %.3f KB over 500 refreshes", kb))
      T.ok(f1:IsShown() and f2:IsShown() and Tooltip.IsShownFor(w), where .. ": still shown")
      T.eq(select(4, Edges(f1)), t1, where .. ": in place")
      if not rawget(f1, "TP_Row") then
        T.eq(barCalls, 0, where .. ": the bars untouched on steady refreshes")
        T.ok(BarOn(bars[1]) and BarOn(bars[2]), where .. ": both bars still shown")
        for _, b in ipairs(bars) do
          for _, r in ipairs({ b.frame, b.segs[1], b.segs[2] }) do
            for _, m in ipairs(barMethods) do rawset(r, m, nil) end
          end
        end
      end
      for f, m in pairs(saved) do
        rawset(f, "ClearLines", m[1])
        rawset(f, "Show", m[2])
      end
      Stub.Advance(1)                           -- the real fill again
      if not narrow then CheckSide(ns, f1, f2, where .. ", real fill") end
      Tooltip.Hide(w)
      Stub.SetShift(false)
      T.eq(#Stub.errors, 0, where .. ": no Lua error")
    end
  end
end)

T.test("pair: a theme change skins both frames once (shared section, own parts)", function()
  local ns, w = Start(nil)
  local Tooltip, Core, Themes = ns.Tooltip, ns.Core, ns.Themes
  Stub.SetShift(true)
  Tooltip.ShowFor(w)
  local f1, f2 = Blocks(ns)
  local function CheckSkin(key)
    local tt = Themes.Active().tt
    for b, f in ipairs({ f1, f2 }) do
      local tp = f.tp
      local n = 0
      for _, p in ipairs(tt.panel.parts) do
        local h = tp.panel[p.id]
        T.ok(h ~= nil, key .. " block " .. b .. ": panel part " .. p.id)
        local t = h and (h.GetTexture and h or h[1])
        if t then T.eq(t:GetTexture(), p.tex.path, key .. " block " .. b .. ": " .. p.id .. " art") end
        n = n + 1
      end
      local np = 0
      for _ in pairs(tp.panel) do np = np + 1 end
      T.eq(np, n, key .. " block " .. b .. ": only this theme's parts")
      local fw = f:GetWidth()
      T.ok(fw >= tt.width[1] and fw <= tt.width[2], key .. " block " .. b .. ": width " .. fw)
      T.eq((tp.rows[1].left:GetFont()), (Themes.Font(tt.fonts.title[1], tt.fonts.title[2])),
        key .. " block " .. b .. ": first row in the title font")
    end
  end
  CheckSkin("futuriste")
  -- no theme work on refreshes: the panel art is set once per theme change
  local sets = 0
  for _, f in ipairs({ f1, f2 }) do
    for _, h in pairs(f.tp.panel) do
      local t = h.GetTexture and h or h[1]
      local orig = t.SetTexture
      rawset(t, "SetTexture", function(...) sets = sets + 1 return orig(...) end)
    end
  end
  Stub.Advance(5)
  T.eq(sets, 0, "no SetTexture on the panels while shown")
  for _, key in ipairs({ "druid", "pixel" }) do
    Core.SetSetting("theme", key)
    T.no(f1:IsShown() or f2:IsShown(), key .. ": both hidden on the switch")
    Tooltip.ShowFor(w)
    T.ok(f1:IsShown() and f2:IsShown(), key .. ": both shown again")
    CheckSkin(key)
  end
  Tooltip.Hide(w)
  Stub.SetShift(false)
end)

T.test("Broker keeps one tooltip with both sections and both breakdown labels; the pair's frames are never used", function()
  Stub.InstallUI({ ldb = true })
  for _, theme in ipairs({ "futuriste", "actuel" }) do
    Stub.Reset()
    Stub.InstallUI({ ldb = true })
    local ns = Start(theme, { ldb = true })
    local L = ns.L
    local obj = Stub.ui.ldbObjects.TruePlayed
    T.ok(obj ~= nil, "LDB object")
    Stub.shift = true
    local tt = Stub.NewTooltip()
    obj.OnTooltipShow(tt)
    Stub.shift = false
    local level, char, hints = 0, 0, 0
    for _, l in ipairs(tt._lines) do
      if l[1] == L.TT_SECTION_LEVEL then level = level + 1 end
      if l[1] == L.TT_SECTION_CHAR then char = char + 1 end
      if l[1] == L.TT_HINT then hints = hints + 1 end
    end
    T.eq({ level, char, hints }, { 1, 1, 1 }, theme .. ": one tooltip, both sections, one hint")
    local labels = {}
    for _, l in ipairs(tt._lines) do
      if l[1] == L.TT_BREAKDOWN_LEVEL or l[1] == L.TT_BREAKDOWN_TOTAL then labels[#labels + 1] = l[1] end
    end
    T.eq(labels, { L.TT_BREAKDOWN_LEVEL, L.TT_BREAKDOWN_TOTAL }, theme .. ": the level's breakdown, then the total")
    T.eq(tt._lines[#tt._lines][1], L.TT_HINT, theme .. ": hint last")
    T.eq(tt._lines, (Native(ns, true)), theme .. ": the classic lines of Fill")
    T.eq(ns.TooltipFrame.frame2, nil, theme .. ": no block 2 frame")
    T.eq(rawget(_G, "TruePlayedCharTooltip"), nil, theme .. ": no second GameTooltip")
    -- text only: each breakdown's label with its first parts, no bar
    for _, l in ipairs(tt._lines) do
      if l[1] == L.TT_BREAKDOWN_LEVEL or l[1] == L.TT_BREAKDOWN_TOTAL then
        T.ok(type(l[2]) == "string" and l[2]:find("%%"), theme .. ": " .. l[1] .. " with its parts (" .. tostring(l[2]) .. ")")
      end
    end
    T.eq(ns.TooltipFrame.bar, nil, theme .. ": no breakdown bar")
    T.eq(ns.TooltipFrame.bar2, nil, theme .. ": no breakdown bar")
  end
end)

T.test("native: block 2 is the addon's own GameTooltip, created once; its lines are the character's", function()
  local ns, w = Start("actuel")
  local Tooltip, L = ns.Tooltip, ns.L
  T.eq(rawget(_G, "TruePlayedCharTooltip"), nil, "not created before the first Shift")
  Tooltip.ShowFor(w)
  T.eq(rawget(_G, "TruePlayedCharTooltip"), nil, "not created by a short tooltip")
  Stub.SetShift(true)
  local t2 = rawget(_G, "TruePlayedCharTooltip")
  T.ok(t2 ~= nil and t2 ~= GameTooltip, "created at the first Shift")
  T.eq(t2:GetObjectType(), "GameTooltip")
  T.ok(t2:GetParent() == UIParent)
  T.ok(t2:IsShown() and t2:GetOwner() == w)
  T.eq(ns.TooltipFrame.frame, nil, "no private frame for a native theme")
  -- the lines: block 1's, then block 2's = the one tooltip of Fill less the blank line
  -- that opens its character section
  local all = {}
  for _, l in ipairs(GameTooltip._lines) do all[#all + 1] = l end
  T.eq(t2._lines[1][1], L.TT_SECTION_CHAR, "block 2 opens with its section title")
  for _, l in ipairs(t2._lines) do all[#all + 1] = l end
  local one = BarLayout(ns, (Native(ns, true)))
  local want = {}
  for i, l in ipairs(one) do
    if not (l[1] == " " and l[2] == nil and one[i + 1] and one[i + 1][1] == L.TT_SECTION_CHAR) then
      want[#want + 1] = l
    end
  end
  T.eq(all, want, "block 1 + block 2 = the whole tooltip (breakdown labels alone: their bars beside them)")
  T.eq(t2._lines[#t2._lines][1], L.TT_HINT, "the hint ends block 2")
  -- created once
  Tooltip.Hide(w)
  T.no(t2:IsShown())
  local c0 = Created()
  Tooltip.ShowFor(w)
  T.ok(rawget(_G, "TruePlayedCharTooltip") == t2 and t2:IsShown(), "the same frame again")
  T.eq(Created(), c0, "no frame created")
  Tooltip.Hide(w)
  Stub.SetShift(false)
end)

---------------------------------------------------------------------------
-- Native breakdown bars: the classic gauge beside each native block's breakdown label
-- (block 1's a frame of UIParent over the shared GameTooltip, block 2's its child)
---------------------------------------------------------------------------

-- An rgba array of a compiled colour (a per-state list gives its first entry).
local function Rgba(c)
  while type(c) == "table" and type(c[1]) == "table" do c = c[1] end
  return c
end

-- Checks bar `b` of shown native block `t` on the line labelled `label`, for the
-- breakdown of `bucket`: the label alone, the parts on the next rows; the bar from 8 px
-- right of the label to the line's right text edge, on the label's line; its segments
-- (classic gauge: order, colours, widths, 1 px inside the outline) and its frame.
local function CheckBar(ns, t, b, label, bucket, where)
  local Tooltip, L = ns.Tooltip, ns.L
  local G = ns.Themes.CLASSIC_GAUGE
  local f = b.frame
  T.ok(f:IsShown() and f:IsVisible(), where .. ": bar shown")
  local i = LineOf(t, label)
  T.ok(i ~= nil, where .. ": the breakdown line")
  T.eq(t._lines[i], { label, " " }, where .. ": the label alone on its line (a space on the right)")
  local parts, fr, keys = {}, {}, {}
  local n = Tooltip.BreakdownParts(ns.Stats.Breakdown(bucket, {}), parts)
  T.eq(Tooltip.BreakdownFracs(ns.Stats.Breakdown(bucket, {}), fr, keys), n)
  local got = {}
  local j = i + 1
  while t._lines[j] and t._lines[j][1] == " " and t._lines[j][2] ~= nil do
    got[#got + 1] = t._lines[j][2]
    j = j + 1
  end
  T.eq(table.concat(got, L.SEP), table.concat(parts, L.SEP), where .. ": every part on the next rows, right-aligned")
  -- the bar: from the label to the right text edge, on the label's line
  local lf = _G[t:GetName() .. "TextLeft" .. i]
  local rf = _G[t:GetName() .. "TextRight" .. i]
  local fl, fb, fw, fh = f:GetRect()
  T.near(fl, lf:GetRight() + 8, 1e-9, where .. ": 8 px right of the label")
  T.near(fl + fw, rf:GetRight(), 1e-9, where .. ": up to the line's right text")
  T.near(rf:GetRight(), t:GetLeft() + t:GetWidth() - 10, 1e-9, where .. ": (the tooltip's right text edge)")
  T.near(fb + fh / 2, select(2, lf:GetCenter()), 1e-9, where .. ": on the label's line")
  T.ok(fw >= G.min, where .. ": at least the minimum width (" .. fw .. ")")
  T.eq(fh, G.h + 2, where .. ": the gauge's height and its outline")
  -- the outline: the whole bar, the classic dark
  local o = b.outline
  T.ok(o:IsVisible(), where .. ": outline")
  T.eq({ o:GetRect() }, { fl, fb, fw, fh }, where .. ": the outline fills the bar")
  T.eq({ o:GetVertexColor() }, { G.outline[1], G.outline[2], G.outline[3], G.outline[4] }, where .. ": outline colour")
  -- the segments: the parts largest first (8 at most), the classic gauge's colours,
  -- widths in proportion adding up to the bar less the gaps, 1 px inside the outline
  local ns_ = n > 8 and 8 or n
  T.eq(b.n, ns_, where .. ": one segment a part")
  local total = 0
  for s = 1, ns_ do total = total + fr[s] end
  local avail = fw - 2 - G.gap * (ns_ - 1)
  local x, sum = fl + 1, 0
  for s = 1, 8 do
    local seg = b.segs[s]
    if s <= ns_ then
      T.ok(seg ~= nil and seg:IsVisible(), where .. ": segment " .. s)
      local c = G.colors[keys[s]]
      T.ok(c ~= nil, where .. ": a classic colour for " .. tostring(keys[s]))
      T.eq({ seg:GetVertexColor() }, { c[1], c[2], c[3], c[4] }, where .. ": segment " .. s .. " colour (" .. keys[s] .. ")")
      local sl, sb, sw, sh = seg:GetRect()
      T.near(sl, x, 1e-9, where .. ": segment " .. s .. " right after the previous one")
      T.near(sb, fb + 1, 1e-9, where .. ": segment " .. s .. " 1 px above the outline's bottom")
      T.eq(sh, G.h)
      T.ok(math.abs(sw - avail * fr[s] / total) <= 1, where .. ": segment " .. s .. " in proportion")
      x = sl + sw + G.gap
      sum = sum + sw
    else
      T.ok(seg == nil or not seg:IsShown(), where .. ": no segment " .. s)
    end
  end
  T.near(sum, avail, 1e-9, where .. ": the segments fill the bar")
  T.near(x - G.gap, fl + fw - 1, 1e-9, where .. ": up to 1 px inside the outline")
  -- the frame: strata TOOLTIP, above its block, no mouse, anonymous
  T.eq(f:GetFrameStrata(), "TOOLTIP", where)
  T.ok(f:GetFrameLevel() > t:GetFrameLevel(), where .. ": above its block")
  T.no(f:IsMouseEnabled(), where .. ": no mouse")
  T.eq(f:GetName(), nil, where .. ": anonymous")
end

T.test("native bars: on both blocks, the label alone and the parts below; the classic gauge's segments", function()
  local ns, w = Start("actuel")
  local Tooltip, L, TF = ns.Tooltip, ns.L, ns.TooltipFrame
  local G = ns.Themes.CLASSIC_GAUGE
  -- the classic gauge: the default theme's breakdown colours, every key
  local fut = ns.Themes.Compile("futuriste").tt.gauge.colors
  local keys = 0
  for k, c in pairs(fut) do
    keys = keys + 1
    local a, b = Rgba(c), G.colors[k]
    T.ok(b ~= nil, "classic colour " .. k)
    for i = 1, 4 do T.near(b and b[i] or -1, a[i] or 1, 1e-9, "classic colour " .. k .. " = Futuriste's") end
  end
  T.eq(keys, 10, "the 10 breakdown colour keys")
  T.eq({ G.min, G.h, G.gap }, { 80, 6, 1 })
  T.eq(TF.bar, nil, "no bar before the first show")
  for _, shift in ipairs({ false, true }) do
    Stub.SetShift(shift)
    Tooltip.ShowFor(w)
    local t2 = rawget(_G, "TruePlayedCharTooltip")
    CheckBar(ns, GameTooltip, TF.bar, L.TT_BREAKDOWN_LEVEL, ns.char.levels[ns.Tokens.ctx.level],
      "block 1 (shift " .. tostring(shift) .. ")")
    T.ok(TF.bar.frame:GetParent() == UIParent, "block 1's bar: a frame of UIParent, not of the shared GameTooltip")
    T.eq(TF.bar.frame:GetScale(), GameTooltip:GetScale(), "at GameTooltip's scale")
    if shift then
      CheckBar(ns, t2, TF.bar2, L.TT_BREAKDOWN_TOTAL, ns.char.life, "block 2")
      T.ok(TF.bar2.frame:GetParent() == t2, "block 2's bar: a child of block 2 (the addon's own GameTooltip)")
      T.eq(TF.bar2.n, 7, "the character's 7 parts")
      -- side by side: the breakdown lines face to face, and so do the bars
      CheckSide(ns, GameTooltip, t2, "bars")
      T.near(select(2, TF.bar.frame:GetCenter()), select(2, TF.bar2.frame:GetCenter()), 1e-9, "the bars level")
    else
      T.ok(TF.bar2 == nil or not BarOn(TF.bar2), "short view: block 1's bar alone")
    end
    Tooltip.Hide(w)
  end
  -- a second show creates no region; steady ticks neither
  Stub.SetShift(true)
  local c0 = Created()
  Tooltip.ShowFor(w)
  Stub.Advance(30)
  T.eq(Created(), c0, "no region created by a second show or on ticks")
  T.ok(BarOn(TF.bar) and BarOn(TF.bar2))
  Tooltip.Hide(w)
  -- a tooltip addon scales GameTooltip: block 1's bar (a frame of UIParent) follows it;
  -- block 2's bar is block 2's child (block 2 takes GameTooltip's scale)
  GameTooltip:SetScale(1.25)
  Tooltip.ShowFor(w)
  T.eq(TF.bar.frame:GetScale(), 1.25, "block 1's bar at GameTooltip's scale")
  T.eq(TF.bar2.frame:GetScale(), 1, "block 2's bar: its parent's scale")
  T.eq(rawget(_G, "TruePlayedCharTooltip"):GetScale(), 1.25)
  Tooltip.Hide(w)
  GameTooltip:SetScale(1)
  Tooltip.ShowFor(w)
  T.eq(TF.bar.frame:GetScale(), 1, "back to 1")
  Tooltip.Hide(w)
  Stub.SetShift(false)
  T.eq(Stub.onUpdateCount, 0, "no OnUpdate")
  T.eq(#Stub.errors, 0)
end)

T.test("native bars: shown only with our tooltip (client hide, leave, foreign owner, no breakdown, Shift, theme)", function()
  local ns, w = Start("actuel")
  local Tooltip, L, TF, Core, Stats = ns.Tooltip, ns.L, ns.TooltipFrame, ns.Core, ns.Stats
  Stub.SetShift(true)
  Tooltip.ShowFor(w)
  local b1, b2 = TF.bar, TF.bar2
  T.ok(BarOn(b1) and BarOn(b2), "both bars with the pair")
  -- the client hides GameTooltip with its owner (no OnLeave): block 1's bar at once
  GameTooltip:Hide()
  T.no(BarOn(b1), "client hide: block 1's bar at once (the OnHide hook)")
  Stub.Advance(1)
  T.no(BarOn(b2), "block 2's bar with block 2, at the next refresh")
  -- leave
  Tooltip.ShowFor(w)
  T.ok(BarOn(b1) and BarOn(b2))
  Tooltip.Hide(w)
  T.no(BarOn(b1) or BarOn(b2), "leave: both bars")
  -- another addon takes the shown GameTooltip without hiding it: block 1's bar goes at
  -- our next refresh, and its tooltip is left alone
  Tooltip.ShowFor(w)
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:AddLine("someone else")
  GameTooltip:Show()
  Stub.Advance(1)
  T.no(BarOn(b1), "foreign owner: block 1's bar hidden")
  T.no(BarOn(b2), "and block 2's")
  T.ok(GameTooltip:IsShown() and GameTooltip:NumLines() == 1, "the foreign tooltip left alone")
  Stub.Advance(2)
  T.no(BarOn(b1), "never shown again on it")
  GameTooltip:Hide()
  -- a client whose SetOwner hides the shown tooltip first: at once
  Tooltip.ShowFor(w)
  T.ok(BarOn(b1))
  GameTooltip:Hide()
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  T.no(BarOn(b1), "hidden with it")
  -- a fill without breakdown (no tracked time at this level): no bar on block 1, block
  -- 2's still there; back with the breakdown
  Tooltip.ShowFor(w)
  local breakdown = Stats.Breakdown
  Stats.Breakdown = function(bucket, out)
    if bucket ~= ns.char.life then bucket = nil end
    return breakdown(bucket, out)
  end
  Stub.Advance(1)
  local i = LineOf(GameTooltip, L.TT_BREAKDOWN_LEVEL)
  T.eq(GameTooltip._lines[i], { L.TT_BREAKDOWN_LEVEL, L.TT_NO_RATE }, "no breakdown: the dimmed line")
  T.no(BarOn(b1), "no breakdown: no bar")
  T.ok(BarOn(b2), "block 2's breakdown and bar still there")
  CheckSide(ns, GameTooltip, rawget(_G, "TruePlayedCharTooltip"), "no breakdown on block 1", true)
  Stats.Breakdown = breakdown
  Stub.Advance(1)
  T.ok(BarOn(b1), "back with the breakdown")
  -- Shift released: block 2 and its bar go; pressed again: back
  Stub.SetShift(false)
  T.no(BarOn(b2), "Shift released: block 2's bar")
  T.ok(BarOn(b1), "block 1's stays")
  Stub.SetShift(true)
  T.ok(BarOn(b2), "pressed again")
  -- the bars follow their blocks: another owner, at the screen's right edge (the pair
  -- moved by the clamp), above or below it
  for _, y in ipairs({ 300, -300 }) do
    local edge = Owner(y, 930)
    Tooltip.ShowFor(edge)
    local t2 = rawget(_G, "TruePlayedCharTooltip")
    local _, _, r2 = Edges(t2)
    T.near(r2, UIParent:GetWidth(), 1e-9, "(the pair against the screen's right edge)")
    CheckBar(ns, GameTooltip, b1, L.TT_BREAKDOWN_LEVEL, ns.char.levels[ns.Tokens.ctx.level], "edge " .. y)
    CheckBar(ns, t2, b2, L.TT_BREAKDOWN_TOTAL, ns.char.life, "edge " .. y .. ", block 2")
    T.near(select(2, b1.frame:GetCenter()), select(2, b2.frame:GetCenter()), 1e-9, "edge " .. y .. ": the bars level")
    Tooltip.Hide(edge)
  end
  Tooltip.ShowFor(w)
  T.ok(BarOn(b1) and BarOn(b2))
  -- a theme change hides both; a private-frame theme has no native bar
  Core.SetSetting("theme", "futuriste")
  T.no(BarOn(b1) or BarOn(b2), "theme change: both bars")
  Tooltip.ShowFor(w)
  T.ok(TF.frame:IsShown())
  T.no(BarOn(b1) or BarOn(b2), "futuriste: no native bar")
  Tooltip.Hide(w)
  Core.SetSetting("theme", "actuel")
  Tooltip.ShowFor(w)
  T.ok(BarOn(b1) and BarOn(b2), "Classic again: both bars")
  Tooltip.Hide(w)
  Stub.SetShift(false)
  T.eq(#Stub.errors, 0)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("native bars: nothing added to the shared GameTooltip; its one hook is OnHide, set once", function()
  local ns, w = Start("actuel")
  local Tooltip, L = ns.Tooltip, ns.L
  local hooks, scripts = {}, 0
  local hook = GameTooltip.HookScript
  rawset(GameTooltip, "HookScript", function(self, name, fn)
    hooks[#hooks + 1] = name
    return hook(self, name, fn)
  end)
  rawset(GameTooltip, "SetScript", function() scripts = scripts + 1 end)
  local before = {}
  for k in pairs(GameTooltip) do before[k] = true end
  -- every path: short, Shift side by side, stacked (a minimum width), a bar that needs a
  -- wider block, the client's hide, ours, a foreign owner
  Tooltip.ShowFor(w)
  Stub.Advance(2)
  Stub.SetShift(true)
  Stub.Advance(2)
  ScreenWidth(600)
  Stub.Advance(2)
  GameTooltip:Hide()
  Stub.Advance(1)
  ScreenWidth(1920)
  L.TT_BREAKDOWN_LEVEL = string.rep("W", 60)
  Tooltip.ShowFor(w)
  Stub.Advance(2)
  T.ok(GameTooltip:GetMinimumWidth() > 0, "(a minimum width for the bar)")
  Tooltip.Hide(w)
  Tooltip.ShowFor(w)
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:AddLine("someone else")
  GameTooltip:Show()
  Stub.Advance(2)
  GameTooltip:Hide()
  Stub.SetShift(false)
  T.eq(hooks, { "OnHide" }, "one hook on GameTooltip: OnHide")
  T.eq(scripts, 0, "no script set on GameTooltip")
  for k in pairs(GameTooltip) do
    if not before[k] then
      T.ok(type(k) == "string" and k:sub(1, 1) == "_", "no field written on GameTooltip (the stub's own aside): " .. tostring(k))
    end
  end
  local mine = 0
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_parent") == GameTooltip then mine = mine + 1 end
  end
  T.eq(mine, 0, "no region or frame made on GameTooltip")
  local f = ns.TooltipFrame.bar.frame
  T.ok(f:GetParent() == UIParent, "block 1's bar: a frame of UIParent")
  T.eq(#Stub.errors, 0)
end)

T.test("native bars: a block too narrow for the bar is widened; that minimum goes like the stack's", function()
  local ns, w = Start("actuel")
  local Tooltip, L, TF = ns.Tooltip, ns.L, ns.TooltipFrame
  local G = ns.Themes.CLASSIC_GAUGE
  L.TT_BREAKDOWN_LEVEL = string.rep("W", 60)    -- block 1's widest line: 360 px of label
  Tooltip.ShowFor(w)
  local f = TF.bar.frame
  T.ok(f:IsShown())
  T.eq(f:GetWidth(), G.min, "the bar at its minimum width")
  T.eq(GameTooltip:GetWidth(), 10 + 360 + 8 + G.min + 10, "block 1 just wide enough (its own width: 426)")
  T.eq(GameTooltip:GetMinimumWidth(), GameTooltip:GetWidth(), "through its minimum width")
  CheckBar(ns, GameTooltip, TF.bar, L.TT_BREAKDOWN_LEVEL, ns.char.levels[ns.Tokens.ctx.level], "widened")
  T.eq(Point(GameTooltip)[1], (select(2, w:GetCenter()) > 540) and "TOP" or "BOTTOM", "still placed on the owner")
  -- steady ticks: no flapping, no anchor or size work on the bar
  local calls = 0
  for _, m in ipairs({ "ClearAllPoints", "SetPoint", "SetSize", "SetWidth" }) do
    local orig = f[m]
    rawset(f, m, function(...)
      calls = calls + 1
      return orig(...)
    end)
  end
  Stub.Advance(3)
  T.eq(calls, 0, "steady ticks: the bar untouched")
  for _, m in ipairs({ "ClearAllPoints", "SetPoint", "SetSize", "SetWidth" }) do rawset(f, m, nil) end
  T.eq(f:GetWidth(), G.min)
  T.eq(GameTooltip:GetWidth(), 468)
  -- released like the stack's: the client's hide, ours
  GameTooltip:Hide()
  T.eq(GameTooltip:GetMinimumWidth(), 0, "client hide: the minimum dropped")
  T.no(f:IsShown(), "and the bar")
  Tooltip.ShowFor(w)
  T.ok(GameTooltip:GetMinimumWidth() > 0)
  Tooltip.Hide(w)
  T.eq(GameTooltip:GetMinimumWidth(), 0, "our hide: dropped")
  -- a foreign owner: never reset under its tooltip, dropped when it hides
  Tooltip.ShowFor(w)
  local ours = GameTooltip:GetMinimumWidth()
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:AddLine("someone else")
  GameTooltip:Show()
  Stub.Advance(2)
  T.eq(GameTooltip:GetMinimumWidth(), ours, "not reset under the other owner's tooltip")
  T.no(f:IsShown(), "our bar gone")
  GameTooltip:Hide()
  T.eq(GameTooltip:GetMinimumWidth(), 0, "gone with its hide")
  -- block 2 too (its own GameTooltip), side by side: the bars still face to face
  L.TT_BREAKDOWN_TOTAL = string.rep("W", 70)
  Stub.SetShift(true)
  Tooltip.ShowFor(w)
  local t2 = rawget(_G, "TruePlayedCharTooltip")
  T.eq(TF.bar2.frame:GetWidth(), G.min, "block 2's bar at its minimum")
  T.eq(t2:GetWidth(), 10 + 420 + 8 + G.min + 10, "block 2 just wide enough")
  CheckBar(ns, t2, TF.bar2, L.TT_BREAKDOWN_TOTAL, ns.char.life, "block 2 widened")
  CheckSide(ns, GameTooltip, t2, "widened pair")
  T.near(select(2, f:GetCenter()), select(2, TF.bar2.frame:GetCenter()), 1e-9, "the bars level")
  Stub.Advance(2)
  CheckSide(ns, GameTooltip, t2, "widened pair, on refreshes")
  Tooltip.Hide(w)
  Stub.SetShift(false)
  T.eq(GameTooltip:GetMinimumWidth(), 0, "no minimum width left on GameTooltip")
  T.eq(#Stub.errors, 0)
end)

-- The client's SetMinimumWidth may count the tooltip's padding or not (the stack's
-- widening learns which): a bar's widening ends at the same width either way.
T.test("native bars: the widening for a bar, whether SetMinimumWidth includes the padding or not", function()
  local ns, w = Start("actuel")
  local G = ns.Themes.CLASSIC_GAUGE
  local show = GameTooltip.Show
  rawset(GameTooltip, "Show", function(self)
    local min = rawget(self, "_minWidth")
    rawset(self, "_minWidth", nil)
    show(self)                                  -- the lines' own width, padding included
    rawset(self, "_minWidth", min)
    if min and min + 20 > self._width then self._width = min + 20 end
  end)
  ns.L.TT_BREAKDOWN_LEVEL = string.rep("W", 60)
  ns.Tooltip.ShowFor(w)
  T.eq(GameTooltip:GetWidth(), 468, "just wide enough")
  T.eq(GameTooltip:GetMinimumWidth(), 448, "the padding taken off")
  T.eq(ns.TooltipFrame.bar.frame:GetWidth(), G.min)
  Stub.Advance(3)
  T.eq(GameTooltip:GetWidth(), 468, "on refreshes too")
  T.eq(ns.TooltipFrame.bar.frame:GetWidth(), G.min)
  ns.Tooltip.Hide(w)
  T.eq(GameTooltip:GetMinimumWidth(), 0)
end)

-- The client's sizes are fractional: a block widened for its bar may come out a hair
-- narrower than asked. The bar is then at its minimum all the same, and a refresh makes
-- one pass (shown at its own width, then widened), never a second one to widen again.
T.test("native bars: fractional sizes of the client: the bar at its minimum, one pass a refresh", function()
  local ns, w = Start("actuel")
  local show = GameTooltip.Show
  local shows = 0
  rawset(GameTooltip, "Show", function(self)
    shows = shows + 1
    show(self)
    self._width = self._width - 1e-9
  end)
  ns.L.TT_BREAKDOWN_LEVEL = string.rep("W", 60)
  ns.Tooltip.ShowFor(w)
  local f = ns.TooltipFrame.bar.frame
  T.ok(f:IsShown())
  T.near(f:GetWidth(), 80, 1e-6, "the bar at its minimum")
  T.eq(GameTooltip:GetMinimumWidth(), 468, "widened to the bar's minimum")
  shows = 0
  Stub.Advance(1)
  T.eq(shows, 2, "one pass on a refresh: its own width, then widened")
  T.near(f:GetWidth(), 80, 1e-6)
  ns.Tooltip.Hide(w)
  T.eq(GameTooltip:GetMinimumWidth(), 0)
  T.eq(#Stub.errors, 0)
end)

-- GameTooltip hidden by its own OnShow, during our Show: the client in gamepad mode
-- (GameTooltip_OnShow, with frame controls shown and GamepadDisableTooltips), a tooltip
-- addon hiding it in combat. No bar (block 1's is a frame of UIParent) or block 2 left
-- alone on the screen, no minimum width left on GameTooltip for the next owner; the next
-- refresh lets go. Every path: side by side (a bar that
-- needs a wider block 1), stacked (block 1 widened to block 2's width), block 1 alone
-- narrower than its bar needs (learned on an earlier, wider show). Here the client's
-- SetMinimumWidth adds the padding, and no widening ran yet: the one learning it (a
-- second minimum, after block 1's OnHide dropped the first) is the one to watch.
T.test("native bars: GameTooltip hidden by its own OnShow: no bar, block 2 or minimum width left", function()
  local ns, w = Start("actuel")
  local Tooltip, L, TF = ns.Tooltip, ns.L, ns.TooltipFrame
  -- the client's SetMinimumWidth (every GameTooltip's: block 2 too) adds the padding
  local function Pad(t)
    rawset(t, "SetMinimumWidth", function(self, mw)
      self._min0 = mw
      self._minWidth = mw > 0 and mw + 20 or 0
    end)
    rawset(t, "GetMinimumWidth", function(self) return rawget(self, "_min0") or 0 end)
  end
  Pad(GameTooltip)
  local refuse = false
  GameTooltip:HookScript("OnShow", function(self)
    if refuse then self:Hide() end
  end)
  local t2
  -- refused show of the case `where`: nothing of ours stays, the next owner's tooltip at
  -- its own width, nothing on the refreshes
  local function Refused(where, hint)
    refuse = true
    Tooltip.ShowFor(w, hint)
    refuse = false
    T.no(GameTooltip:IsShown(), where .. ": (GameTooltip hidden by its OnShow)")
    T.no(BarOn(TF.bar), where .. ": no bar left alone at once")
    T.ok(t2 == nil or not t2:IsShown(), where .. ": no block 2 left alone")
    T.no(BarOn(TF.bar2), where .. ": nor its bar")
    T.eq(GameTooltip:GetMinimumWidth(), 0, where .. ": no minimum width left on GameTooltip")
    T.no(Tooltip.IsShownFor(w), where .. ": let go")
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip:AddLine("someone else")
    GameTooltip:Show()
    T.eq(GameTooltip:GetWidth(), 6 * 12 + 20, where .. ": the next tooltip at its own width")
    Stub.Advance(2)
    T.no(BarOn(TF.bar) or BarOn(TF.bar2), where .. ": no bar on the refreshes")
    T.ok(GameTooltip:IsShown() and GameTooltip:NumLines() == 1, where .. ": the other tooltip left alone")
    GameTooltip:Hide()
  end
  -- a first show as usual, side by side (short labels: no widening, nothing learned)
  Stub.SetShift(true)
  Tooltip.ShowFor(w)
  t2 = rawget(_G, "TruePlayedCharTooltip")
  Pad(t2)
  T.ok(BarOn(TF.bar) and BarOn(TF.bar2), "(both bars)")
  Tooltip.Hide(w)
  -- side by side, block 1's bar now needing a wider block
  L.TT_BREAKDOWN_LEVEL = string.rep("W", 60)
  Refused("side by side")
  -- stacked, block 1 (426 px) narrower than block 2 (486 px): widened to it
  L.TT_BREAKDOWN_TOTAL = string.rep("W", 70)
  ScreenWidth(600)
  Refused("stacked")
  ScreenWidth(1920)
  -- block 1 alone: a first show made wide by its hint (the bar wide, nothing widened),
  -- then refused without it (426 px, its bar needs 468)
  Stub.SetShift(false)
  local hint = string.rep("W", 80)
  Tooltip.ShowFor(w, hint)
  T.ok(BarOn(TF.bar) and TF.bar.frame:GetWidth() > 80, "(a wide bar)")
  T.eq(GameTooltip:GetMinimumWidth(), 0, "(not widened)")
  Tooltip.Hide(w)
  Refused("alone")
  -- shown again: as usual, the widening learned on a shown tooltip
  Stub.SetShift(true)
  Tooltip.ShowFor(w)
  T.ok(Tooltip.IsShownFor(w))
  CheckBar(ns, GameTooltip, TF.bar, L.TT_BREAKDOWN_LEVEL, ns.char.levels[ns.Tokens.ctx.level], "shown again")
  CheckBar(ns, t2, TF.bar2, L.TT_BREAKDOWN_TOTAL, ns.char.life, "shown again, block 2")
  T.eq(TF.bar.frame:GetWidth(), 80, "block 1 widened for its bar")
  T.eq(GameTooltip:GetMinimumWidth(), GameTooltip:GetWidth() - 20, "the padding taken off")
  Tooltip.Hide(w)
  T.eq(GameTooltip:GetMinimumWidth(), 0)
  Stub.SetShift(false)
  T.eq(#Stub.errors, 0)
end)

-- A breakdown of more than 8 parts (here all 10 kinds, 1 % or more each): 8 segments,
-- the 8 largest, their widths in proportion to those 8 only, so they fill the native bar
-- and a frame theme's gauge to its edge.
T.test("breakdown of 10 parts: 8 segments filling the native bar and the frame gauge", function()
  local ten = { s = { w = 5000, d = 4000, r = 3500, p = 3000, t = 2500, f = 2000, x = 1500, W = 1200,
                      i = 1000, c = 800 } }
  -- the level's breakdown replaced by those 10 parts
  local function Ten(ns)
    local breakdown = ns.Stats.Breakdown
    ns.Stats.Breakdown = function(bucket, out)
      if bucket == ns.char.levels[ns.Tokens.ctx.level] then bucket = ten end
      return breakdown(bucket, out)
    end
  end
  -- native: block 1's bar
  local ns, w = Start("actuel")
  local fr, keys = {}, {}
  T.eq(ns.Tooltip.BreakdownFracs(ns.Stats.Breakdown(ten, {}), fr, keys), 10, "(10 visible parts)")
  Ten(ns)
  ns.Tooltip.ShowFor(w)
  local b = ns.TooltipFrame.bar
  T.eq(b.n, 8, "native: 8 segments")
  CheckBar(ns, GameTooltip, b, ns.L.TT_BREAKDOWN_LEVEL, ten, "10 parts")
  T.eq({ keys[1], keys[8] }, { "world", "afk" }, "(the 8 largest: world to afk)")
  ns.Tooltip.Hide(w)
  T.eq(#Stub.errors, 0)
  -- a frame theme: the gauge spans the same width as with the level's own parts
  ns, w = Start(nil)
  ns.Tooltip.ShowFor(w)
  local segs = ns.TooltipFrame.frame.tp.gauges[1]
  local function Span(n)
    local l1 = segs[1]:GetRect()
    local ln, _, wn = segs[n]:GetRect()
    return ln + wn - l1
  end
  local n0 = ShownCount(segs)
  T.ok(n0 > 0 and n0 < 8, "(the level's own parts: " .. n0 .. ")")
  local full = Span(n0)
  ns.Tooltip.Hide(w)
  Ten(ns)
  ns.Tooltip.ShowFor(w)
  T.eq(ShownCount(segs), 8, "frame gauge: 8 segments")
  T.near(Span(8), full, 1e-9, "frame gauge: the 8 fill it to its edge")
  local fut = ns.Themes.Compile("futuriste").tt.gauge.colors
  for s = 1, 8 do
    local c = Rgba(fut[keys[s]])
    local got = { segs[s]:GetVertexColor() }
    for k = 1, 3 do
      T.near(got[k], c[k], 1e-9, "frame gauge: segment " .. s .. " colour (" .. keys[s] .. ")")
    end
  end
  ns.Tooltip.Hide(w)
  T.eq(#Stub.errors, 0)
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
          local f1, f2 = Blocks(ns)
          if th.native then
            T.ok(GameTooltip:NumLines() > 5, key .. ": GameTooltip")
          else
            local tp = f1.tp
            T.ok(tp.n > 10, key .. ": rows")
            T.eq(tp.rows[1].kind, "title")
            local fw = f1:GetWidth()
            T.ok(fw >= th.tt.width[1] and fw <= th.tt.width[2], key .. " width " .. fw)
          end
          if shift then
            T.ok(f2 and f2:IsShown() and f2:NumLines() > 10, key .. ": block 2")
            CheckSide(ns, f1, f2, key)            -- beside block 1, the breakdown bars face to face
          else
            T.ok(f2 == nil or not f2:IsShown(), key .. ": no block 2")
          end
          Tooltip.Hide(w)
          T.ok(f2 == nil or not f2:IsShown(), key .. ": hidden with block 1")
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
-- window changed then). The Levels tab rework redesigned the Levels tab of a character:
-- the chart's subtree (LevelChart, its detail sheet inside) is left out too (checked apart
-- under Classic in the test below), the table's scroll frame keeps everything but its
-- shown flag (hidden in the chart view, shown in the other ones: checked apart), and the
-- Levels hint keeps everything but its text (a new text, "Click a bar to see the level's
-- detail.": checked apart), and so does the frame height (the chart's minimum height:
-- checked apart). The table's content frame is the scroll child when no row was created
-- yet (a window first shown on the chart).
local function Snapshot(root, chrome)
  local out = {}
  local tp = rawget(root, "tp")
  local content = tp and tp.rows[1] and rawget(tp.rows[1], "_parent")
  local scrollF
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_parent") == root and o._type == "ScrollFrame" then scrollF = o end
  end
  if not content and scrollF then content = rawget(scrollF, "_scrollChild") end
  local chart = tp and tp.chart and tp.chart.root
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
    if chart and (o == chart or IsUnder(o, chart)) then return true end
    return false
  end
  for _, o in ipairs(Stub.regions) do
    if IsUnder(o, root) and not Skipped(o) then
      local pts = {}
      for i, p in ipairs(o._points) do pts[i] = p.point .. ":" .. tostring(p.relPoint) .. ":" .. V(p.x) .. ":" .. V(p.y) end
      local fo = rawget(o, "_fontObject")
      local text, shown = V(o._text), V(o._shown)
      if chrome and tp and o == tp.hint then text = "<hint>" end
      if chrome and o == scrollF then shown = "<table>" end
      out[#out + 1] = table.concat({
        o._type, V(o._layer), V(o._texture), V(o._vR), V(o._vG), V(o._vB), V(o._vA), text,
        V(o._font), V(o._fontSize), V(o._fontFlags), type(fo) == "table" and V(fo._name) or V(fo),
        V(o._tR), V(o._tG), V(o._tB), V(o._justifyH), V(o._width), V(o._height), shown,
        V(o._bgR), V(o._bgA), V(o._bdR), V(o._bdA), table.concat(pts, ","),
      }, "|")
    end
  end
  out[#out + 1] = table.concat({ V(root._bgR), V(root._bgG), V(root._bgB), V(root._bgA), V(root._bdR),
    V(root._bdG), V(root._bdB), V(root._bdA), chrome and "" or V(root._width), chrome and "" or V(root._height) }, "|")
  return out
end

-- Levels tab rework: the Levels tab of a character is the chart (LevelChart.lua); the roles
-- of the former in-progress level row are checked on it (chip label and value, the accent
-- title and current-level marker), the column headers and cells on the Sessions tab.
T.test("Window: futuriste backdrop, title font and cell colours; a switch while shown", function()
  local ns = Start(nil)
  local Window, Themes = ns.Window, ns.Themes
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
  -- the chart: label, value and accent roles
  local ch = tp.chart
  T.ok(ch ~= nil and ch.root:IsShown(), "the chart")
  local function VC(t) local r, g, b = t:GetVertexColor() return { r, g, b } end
  T.eq(Rgb(ch.chips[1].label), C3(ui.label), "chip label: label")
  T.eq(Rgb(ch.chips[1].value), C3(ui.value), "chip value: value")
  T.eq(Rgb(ch.title), C3(ui.accent), "chart title: accent")
  T.ok(ch.marker:IsShown(), "current level marker")
  T.eq(VC(ch.marker), C3(ui.accent), "current level: accent")
  -- the column headers and cells (Sessions tab)
  Window.Toggle("sessions")
  T.eq(Rgb(tp.header[1]), C3(ui.label), "column headers")
  local cells = tp.cells[tp.rows[1]]
  T.ok(tp.rows[1]:IsShown(), "the session in progress")
  T.eq(Rgb(cells[1]), C3(ui.accent), "the session in progress: accent")
  T.eq(Rgb(cells[2]), C3(ui.value), "duration: value")
  Window.Toggle("levels")
  -- Classic while shown: classic colours, the GameFontNormal title again
  ns.Core.SetSetting("theme", "actuel")
  local K = ns.C.COLORS
  T.eq({ f._bgR, f._bgG, f._bgB, f._bgA }, { K.bg[1], K.bg[2], K.bg[3], 0.95 })
  T.eq(Rgb(ch.chips[1].label), C3(K.label), "repainted with the classic label")
  T.eq(VC(ch.marker), C3(K.accent), "repainted with the classic accent")
  T.ok(tp.title:GetFontObject() == GameFontNormal, "title back on GameFontNormal")
  -- and back: the display font is set again (the Themes font cache followed the switch)
  ns.Core.SetSetting("theme", "futuriste")
  T.eq((tp.title:GetFont()), path)
  T.eq(VC(ch.marker), C3(ui.accent))
end)

-- Lot 8 redesigned the columns (labels, hidden empty columns, new ones), the dates and
-- the size of the window (resize grip): those parts are compared with the classic look
-- (game font objects, classic colours) below, and the rest of the window must still be
-- exactly the pre-theme one. The Levels tab rework replaced the Levels table of a
-- character by the chart: Snapshot leaves its subtree, the table scroll's shown flag and
-- the hint's text out (see there); they are checked below: the hint's new text, the table
-- hidden in the chart view and shown elsewhere, the chart drawn with the classic palette
-- (C.COLORS roles, the classic gauge colours) and the game font only.
T.test("Window: under Classic the window is exactly the pre-theme one (baseline copy)", function()
  local root = Stub.ROOT
  local f = io.open(root .. "tests/baseline/TruePlayed_Camelot.toc", "r")
  if not f then T.skip("no Phase 0 baseline") end
  f:close()
  local function Play(tab)
    local ns = Start(Stub.ROOT == root and "actuel" or nil)
    ns.Window.Show(tab)
    Stub.Advance(10)
    local win = rawget(_G, "TruePlayedStatsFrame")
    return Snapshot(win, true), ns, win:GetHeight()
  end
  for _, tab in ipairs({ "levels", "zones", "sessions" }) do
    Stub.Reset()
    Stub.ROOT = root .. "tests/baseline/"
    local ok, before, _, beforeH = pcall(Play, tab)
    Stub.ROOT = root
    T.ok(ok, tostring(before))
    Stub.Reset()
    local after, ns, afterH = Play(tab)
    T.ok(#after > 20, tab .. " regions: " .. #after)
    T.eq(after, before, tab)
    T.eq(beforeH, 440, tab .. ": the pre-theme height")
    T.eq(afterH, tab == "levels" and 640 or beforeH, tab .. ": the height (the chart: its minimum)")
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
    for c = 1, tp.layout.n do
      T.eq(rawget(tp.header[c], "_fontObject"), "GameFontHighlightSmall", tab .. " header font object")
      T.eq(Rgb(tp.header[c]), C3(K.label), tab .. " header colour")
    end
    local scrollF
    for _, o in ipairs(Stub.regions) do
      if rawget(o, "_parent") == rawget(_G, "TruePlayedStatsFrame") and o._type == "ScrollFrame" then scrollF = o end
    end
    T.ok(scrollF ~= nil, tab .. ": the table's scroll frame")
    if tab == "levels" then
      T.eq(n, 0, "levels: no table cell (the chart)")
      T.no(scrollF:IsShown(), "levels: the table hidden")
      T.ok(tp.hint:IsShown(), "levels: the hint")
      T.eq(tp.hint:GetText(), ns.L.LEVELS_HOVER_HINT, "levels: the hint's new text")
      -- the chart under Classic: the C.COLORS roles and the classic gauge colours, the game font
      local ch = tp.chart
      T.ok(ch ~= nil and ch.root:IsShown(), "levels: the chart")
      local Themes = ns.Themes
      local classic = {}
      local function Allow(c) classic[V(c[1]) .. V(c[2]) .. V(c[3])] = true end
      for _, role in ipairs({ "value", "label", "accent", "dim", "border", "bg" }) do Allow(K[role]) end
      for _, c in pairs(Themes.CLASSIC_GAUGE.colors) do Allow(c) end
      Allow({ 1, 1, 1 })                                    -- the bars' highlight (white, alpha 0.08)
      -- the detail sheet (LevelDetail, under the chart's root): its XP split in the theme's
      -- XP and rested colours (the classic bar's), the estimate's sub in C.COLORS good / warn
      local tc = Themes.Active().colors
      if type(tc) == "table" and tc.xp then Allow(tc.xp) end
      if type(tc) == "table" and tc.rested then Allow(tc.rested) end
      Allow(K.good)
      Allow(K.warn)
      local nfs, ntex = 0, 0
      for _, o in ipairs(Stub.regions) do
        if IsUnder(o, ch.root) then
          if o._type == "FontString" then
            nfs = nfs + 1
            T.eq(rawget(o, "_font"), (Themes.Font("body", rawget(o, "_fontSize"))), "chart text: the body font")
            T.ok(classic[V(o._tR) .. V(o._tG) .. V(o._tB)], "chart text colour is a classic one: " .. V(o._text))
          elseif o._type == "Texture" and o._vR ~= nil then
            ntex = ntex + 1
            local key = V(o._vR) .. V(o._vG) .. V(o._vB)
            -- the world PvP part is the pvp colour mixed toward white (LevelChart WPVP_MIX)
            local pvp = Themes.CLASSIC_GAUGE.colors.pvp
            local mix = V(pvp[1] + (1 - pvp[1]) * 0.45) .. V(pvp[2] + (1 - pvp[2]) * 0.45) .. V(pvp[3] + (1 - pvp[3]) * 0.45)
            T.ok(classic[key] or key == mix, "chart texture colour is a classic one: " .. key)
          end
        end
      end
      T.ok(nfs > 20 and ntex > 20, format("chart regions checked: %d texts, %d textures", nfs, ntex))
    else
      T.ok(n > 0, tab .. " cells")
      T.ok(scrollF:IsShown(), tab .. ": the table shown")
      T.no(tp.hint:IsShown(), tab .. ": no Levels hint")
      T.no(tp.chart and tp.chart.root:IsShown(), tab .. ": no chart")
    end
  end
end)

-- A row is drawn in the font of its slot: the font's glyph replacements apply (futuriste's
-- title font, Orbitron, has no "»" nor "·": "Level 30 » 31" showed a box), the raw text
-- stays the cache key, and a theme switch sets the texts again in the new fonts.
T.test("themed frame: rows show their font's glyph replacements, set again after a theme switch", function()
  local ns, w = Start(nil)
  local TF = ns.TooltipFrame
  local RAW = "Level 30 \194\187 31"
  local function Fill()
    local tf = TF.Get(1)
    tf:SetOwner(w, "ANCHOR_NONE")
    tf:ClearLines()
    tf:TP_Row("title", RAW, nil)
    tf:TP_Row("pair", "Dead", "5m \194\183 4%")
    return tf, tf.tp.rows[1], tf.tp.rows[2]
  end
  T.eq(ns.Themes.ActiveKey(), "futuriste")
  local tf, r1, r2 = Fill()
  T.eq(r1.left:GetText(), "Level 30 > 31", "title (Orbitron): the arrow drawn as >")
  T.eq(r1.lt, RAW, "the raw text is the cache key")
  T.eq(r2.right:GetText(), "5m \194\183 4%", "value (Rajdhani): unchanged")
  -- the same texts again: nothing is set again
  local sets = 0
  local orig = r1.left.SetText
  r1.left.SetText = function(fs, s) sets = sets + 1; return orig(fs, s) end
  Fill()
  T.eq(sets, 0, "unchanged texts are not set again")
  r1.left.SetText = orig
  tf:Hide()
  -- another theme (pixel: Press Start 2P has the glyph): the raw text again
  ns.Core.SetSetting("theme", "pixel")
  tf, r1 = Fill()
  T.eq(r1.left:GetText(), RAW, "pixel: no replacement")
  tf:Hide()
  ns.Core.SetSetting("theme", "futuriste")
  tf, r1 = Fill()
  T.eq(r1.left:GetText(), "Level 30 > 31", "back to futuriste: replaced again")
  tf:Hide()
end)
