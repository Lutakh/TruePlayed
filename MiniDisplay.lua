local ADDON, ns = ...
local L, C, Util = ns.L, ns.C, ns.Util
local Themes = ns.Themes

-- MiniDisplay.lua - the mini display (design/NEXT-LOT.md, backlog 4): a small movable
-- frame showing 1 to 3 compact infos chosen from the bar's catalog (Tokens: mini.infos),
-- optionally the level percentage and / or a thin XP line (mini.xp), for players who do
-- not want the XP bar. Opt-in (mini.shown, /tpl mini, the context menu).
--   * It follows the bar's theme: the theme's fonts and text colours (the bar's info 1
--     font for the infos, its separator and marker fonts), widget.textColor,
--     widget.outline, widget.shadow and widget.qualityColors, the theme's bar panel
--     (else the classic backdrop in the theme's colours) at its own opacity
--     (mini.bgAlpha), and the theme's XP / rested colours (or widget.xpColor /
--     widget.restedColor) for the XP line. Any THEME_CHANGED restyles it.
--   * Layout (mini.layout): "horizontal" (one line, the bar's separator between infos)
--     or "vertical" (one info per line). The frame is sized to its texts, which are
--     measured (invisible "meter" FontStrings, as the bar) only when a text changes:
--     texts never overlap and never leave the frame. Scale: mini.scale.
--   * At max level the XP infos are left out, but one of them still says "Max level".
--   * Hover: the bar's tooltip; left click: the statistics window; right click: the
--     context menu; left drag unless mini.locked; mini.fade and mini.combatHide work like
--     the bar's options.
-- Performance (as Bar.lua): no per-frame script; TICK only while shown and active;
-- SetText, SetFont, GetStringWidth, colours, anchors and sizes only on change; regions
-- created once (panel textures pooled across theme switches); zero allocation per
-- steady tick (token strings and percent texts are cached by Tokens).

local math_floor, math_max, math_min = math.floor, math.max, math.min
local type, tonumber = type, tonumber
local strtrim = strtrim
local CreateFrame, UIParent = CreateFrame, UIParent
local InCombatLockdown = InCombatLockdown

local Mini = {}
ns.MiniDisplay = Mini
Mini.frame = nil

local N = 3                       -- infos at most
local BASE_SIZE = 11              -- text size the theme's size deltas apply to (the bar's default)
local PAD_X, PAD_Y = 8, 5
local PANEL_BLEED = 2   -- px a theme panel may reach past the frame (PlacePart)
local GAP = 5                     -- on each side of a separator (horizontal layout)
local ROW_GAP = 2                 -- between two lines (vertical layout)
local LINE_H, LINE_GAP = 3, 3     -- the XP line, and its gap below the texts
local MIN_W = 24                  -- inner width when nothing is shown
local FADE_ALPHA = 0.35
local MAX_FILL_ALPHA = 0.35       -- the XP line at max level: full, dimmed (as the bar)
local LEGACY_BG_ALPHA = C.LEGACY_BG_ALPHA or 0.85
local EMPTY = ""
local BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local OUTLINES = { none = true, thin = true, thick = true }
-- panel parts anchored by a point: fractions of the frame size (BarSkin)
local ANCHOR_X = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1,
                   BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
local ANCHOR_Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
                   BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }

-- SETTINGS_CHANGED paths grouped by the work they need.
local VISIBILITY_PATHS = { ["mini.shown"] = true, ["mini.combatHide"] = true }
local LAYOUT_PATHS = {
  ["mini.layout"] = true, ["mini.xp"] = true, ["mini.scale"] = true, ["mini.bgAlpha"] = true,
  ["widget.outline"] = true, ["widget.shadow"] = true,
}
local STYLE_PATHS = { ["widget.textColor"] = true, ["widget.qualityColors"] = true }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame, th
local skinGen = false             -- th.gen the frame was styled with (false: never)
local inited, active = false, false
local regenOn, inCombat, combatHidden = false, false, false
local hovered, dragging, dropped = false, false, false

-- regions
local itemFS, sepFS = {}, {}      -- [k] text of the k-th drawn info / separator after it
local pctFS, track, fill
local meterItem, meterSep, meterPct
local itemOn, sepOn = {}, {}      -- shown
local pctOn = false

-- texts (k = position among the drawn infos)
local rawText, itemDim, itemW = {}, {}, {}   -- raw token text, dim state, measured width
local nItems = -1
local pctRaw, pctText, pctW = nil, EMPTY, 0
local sepText, sepW = EMPTY, 0
local itemX, itemY, sepX, sepY = {}, {}, {}, {}
local pctX, pctY = false, false
local layoutDirty = true
local frameW, frameH = -1, -1
local lineW = -1

-- style
local vertical, showLine, showPct = false, true, false
local outline, shadowOn, qualityOn, customOn = "thin", true, true, false
local customRGB, customDim = { 1, 1, 1, 1 }, { 1, 1, 1, 0.55 }
local valueColor, sepColor, pctColor, dimColor = C.COLORS.value, C.COLORS.label, C.COLORS.label, C.COLORS.dim
local itemRole, itemSize, sepRole, sepSize, pctRole, pctSize = "body", BASE_SIZE, "body", BASE_SIZE, "body", BASE_SIZE
local rowH = 13

-- XP line
local xpKey, fillPx, fillState = false, -1, -1
local fillFrac = 0
local lineXP, lineRested = C.COLORS.fill, C.COLORS.restedFill

-- panel
local parts, nParts = {}, 0       -- part records of the current theme
local texPool, poolUsed = {}, 0   -- panel textures (pooled across theme switches)
local panelShown, panelA = false, -1
local backdropOn = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Settings()
  local s = ns.settings
  return s and s.mini
end

local function Widget()
  local s = ns.settings
  return s and s.widget
end

local function Unit(x)
  x = tonumber(x)
  if not x or x ~= x or x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function Clamp(x, lo, hi, default)
  x = tonumber(x) or default
  if x ~= x then x = default end
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

local function IsMax()
  local T = ns.Tracker
  return T ~= nil and T.IsMax ~= nil and T.IsMax() and true or false
end

local function SetColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local function Sub(role, text)
  if Themes.HasSubst(role) then return Themes.Subst(role, text) end
  return text
end

local function Measure(meter, text)
  meter:SetText(text)
  local w = meter:GetStringWidth() or 0
  return math_floor(w + 0.999)                 -- whole pixels, never less than the text
end

local function SetShownFlag(t, k, fs, on)
  if t[k] == on then return end
  t[k] = on
  if on then fs:Show() else fs:Hide() end
end

-- Token id of info i (mini.infos): an unknown id falls back to the default of that
-- info; info 1 is never empty. Also the resolver Tokens samples FPS / latency for.
local DEFAULT_INFOS = C.DEFAULTS.mini.infos

function Mini.Resolve(i)
  local m = Settings()
  local infos = m and m.infos
  local id = type(infos) == "table" and infos[i] or nil
  local DEF = ns.Tokens.DEF
  if id == nil or DEF[id] == nil then id = DEFAULT_INFOS[i] or "none" end
  if i == 1 and id == "none" then id = DEFAULT_INFOS[1] end
  return id
end
local Resolve = Mini.Resolve

---------------------------------------------------------------------------
-- Theme panel (the bar's panel parts, or the classic backdrop), mini.bgAlpha
---------------------------------------------------------------------------

local function PanelTex(n)
  local t = texPool[n]
  if not t then
    t = frame:CreateTexture(nil, "BACKGROUND")
    t:Hide()
    texPool[n] = t
  end
  return t
end

-- Regions of the theme's panel parts (theme change only: allocations allowed).
local function BuildPanel()
  local p = th.bar and th.bar.panel
  local list = type(p) == "table" and p.parts or nil
  local used, n = 0, 0
  if list then
    for i = 1, #list do
      local P = list[i]
      n = n + 1
      local R = parts[n]
      if not R then
        R = { list = {}, pair = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }, flat = { 0, 0, 0, 0 } }
        parts[n] = R
      end
      R.P, R.nine, R.w, R.h = P, P.kind == "nine", false, false
      local count = R.nine and 9 or 1
      local sub = P.sub or math_min(-8 + i - 1, 7)
      for j = 1, count do
        used = used + 1
        local t = PanelTex(used)
        t:Hide()
        t:ClearAllPoints()
        t:SetTexCoord(0, 1, 0, 1)
        t:SetDrawLayer(P.layer or "BACKGROUND", sub)
        if P.tex then Themes.SetTex(t, P.tex) else t:SetTexture(C.TEX_WHITE) end
        R.list[j] = t
      end
      for j = count + 1, #R.list do R.list[j] = nil end
      R.n = count
    end
  end
  for i = n + 1, #parts do parts[i].P = nil end
  nParts = n
  for j = used + 1, #texPool do texPool[j]:Hide() end
  poolUsed = used
  panelShown, panelA = false, -1
end

local function PartAlpha(P, a)
  local mode = P.alpha
  if mode == "bg" then return a end
  if mode == "line" then return math_min(1, 2 * a) end
  return tonumber(mode) or 1
end

local function PlacePart(R, fw, fh)
  local P = R.P
  local anchor = P.anchor or "FILL"
  local x, y, w, h
  if anchor == "FILL" then
    local ins = P.inset
    local l, r, t, b = 0, 0, 0, 0
    -- The bar's panel insets fit the bar, not the mini display: inside the bar frame
    -- (heroic: 9 px from its top and bottom, where the bar keeps its texts) or far
    -- outside it (druid, warrior: around the end caps). The mini display's texts fill its
    -- frame, so its panel covers the frame, plus at most a 2 px border bleed.
    if ins then
      l, r = math_max(math_min(ins[1] or 0, 0), -PANEL_BLEED), math_max(math_min(ins[2] or 0, 0), -PANEL_BLEED)
      t, b = math_max(math_min(ins[3] or 0, 0), -PANEL_BLEED), math_max(math_min(ins[4] or 0, 0), -PANEL_BLEED)
    end
    x, y, w, h = l, b, fw - l - r, fh - t - b
  else
    w, h = P.w or 0, P.h or 0
    local fx, fy = ANCHOR_X[anchor] or 0, ANCHOR_Y[anchor] or 0
    x = fw * fx + (P.x or 0) - w * fx
    y = fh * fy + (P.y or 0) - h * fy
  end
  local list = R.list
  if w <= 0 or h <= 0 then
    for j = 1, R.n do list[j]:Hide() end
    R.w = false
    return
  end
  if R.nine then
    Themes.PlaceNine(list, P.tex, frame, x, y, w, h)
  else
    local t = list[1]
    t:SetSize(w, h)
    t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)
    if P.tex and P.tex.tile then Themes.Tile(t, P.tex, w, h) end
    t:Show()
  end
  R.w, R.h = w, h
end

local function ColorPart(R, a)
  local P = R.P
  local f = PartAlpha(P, a)
  local g = P.g
  if g then
    local from, to, gp = g[1], g[2], R.pair
    local gf, gt = gp[1], gp[2]
    gf[1], gf[2], gf[3], gf[4] = from[1], from[2], from[3], (from[4] or 1) * f
    gt[1], gt[2], gt[3], gt[4] = to[1], to[2], to[3], (to[4] or 1) * f
    gp.dir = g.dir
    local fl, flat = P.f, R.flat
    if fl then
      flat[1], flat[2], flat[3], flat[4] = fl[1], fl[2], fl[3], (fl[4] or 1) * f
    else
      flat[1], flat[2], flat[3], flat[4] = gf[1], gf[2], gf[3], gf[4]
    end
    if R.nine and R.w then
      local slice = P.tex and P.tex.slice
      Themes.GradientSliced(R.list, 9, gp, flat, nil, R.w, R.h, slice and slice[2] or 0)
    else
      for j = 1, R.n do Themes.Gradient(R.list[j], gp, flat) end
    end
    return
  end
  local c = P.c or C.COLORS.bg
  local alpha = (c[4] or 1) * f
  for j = 1, R.n do R.list[j]:SetVertexColor(c[1], c[2], c[3], alpha) end
end

-- Panel at alpha a over the frame: placed on size changes, coloured on alpha / theme
-- changes (force = true: both).
local function ApplyPanel(force)
  local m = Settings()
  local a = Unit(m and m.bgAlpha)
  if nParts > 0 then
    if backdropOn then
      backdropOn = false
      if frame.SetBackdrop then frame:SetBackdrop(nil) end
    end
    if a <= 0 then
      if panelShown then
        panelShown = false
        for j = 1, poolUsed do texPool[j]:Hide() end
      end
      panelA = a
      return
    end
    local recolor = force or a ~= panelA or not panelShown
    for i = 1, nParts do
      local R = parts[i]
      PlacePart(R, frameW, frameH)
      -- a sliced gradient follows the size (one ramp across the 9 pieces)
      if recolor or (R.nine and R.P.g) then ColorPart(R, a) end
    end
    panelShown, panelA = true, a
    return
  end
  if not frame.SetBackdrop then return end
  if a > 0 then
    if not backdropOn or force or a ~= panelA then
      backdropOn = true
      frame:SetBackdrop(BACKDROP)
      local K, cs, ui = C.COLORS, th.colors, th.ui
      local bg = (cs and cs.bg) or (ui and ui.bg) or K.bg
      local bd = (cs and cs.border) or (ui and ui.border) or K.border
      frame:SetBackdropColor(bg[1], bg[2], bg[3], a)
      frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], (K.border[4] or 1) * math_min(1, a / LEGACY_BG_ALPHA))
    end
  elseif backdropOn then
    backdropOn = false
    frame:SetBackdrop(nil)
  end
  panelA = a
end

---------------------------------------------------------------------------
-- Text style, fonts, colours
---------------------------------------------------------------------------

local function ApplyShadow(fs)
  local s = shadowOn and th and th.text.shadow
  if s then
    local c = s.c
    fs:SetShadowOffset(s.x or 1, s.y or -1)
    fs:SetShadowColor(c[1], c[2], c[3], c[4] or 1)
  elseif shadowOn then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
  else
    fs:SetShadowOffset(0, 0)
    fs:SetShadowColor(0, 0, 0, 0)
  end
end

-- widget.outline / shadow / qualityColors / textColor, the theme's text colours, the
-- XP line colours (widget.xpColor / restedColor, else the theme's).
local function ReadStyle()
  local w = Widget() or C.DEFAULTS.widget
  outline = OUTLINES[w.outline] and w.outline or "thin"
  shadowOn = w.shadow ~= false
  qualityOn = w.qualityColors ~= false
  customOn = false
  local tc = w.textColor
  if type(tc) == "table" then
    local r, g, b = tc[1], tc[2], tc[3]
    if r == nil and g == nil and b == nil then r, g, b = tc.r, tc.g, tc.b end
    if tonumber(r) and tonumber(g) and tonumber(b) then
      r, g, b = Unit(r), Unit(g), Unit(b)
      customRGB[1], customRGB[2], customRGB[3] = r, g, b
      customDim[1], customDim[2], customDim[3] = r, g, b
      customOn = true
    end
  end
  local colors = th.text.colors
  valueColor = customOn and customRGB or colors.value or C.COLORS.value
  sepColor = customOn and customRGB or colors.sep or C.COLORS.label
  pctColor = customOn and customRGB or colors.marker or C.COLORS.label
  dimColor = customOn and customDim or colors.dimmed or C.COLORS.dim
  local cs = th.colors
  lineXP = (type(w.xpColor) == "table" and w.xpColor[1] and w.xpColor) or (cs and cs.xp) or C.COLORS.fill
  lineRested = (type(w.restedColor) == "table" and w.restedColor[1] and w.restedColor)
    or (cs and cs.rested) or C.COLORS.restedFill
end

local function ApplyColors()
  for k = 1, N do
    itemDim[k] = nil                             -- the next Refresh sets the item colours
    SetColor(sepFS[k], sepColor)
  end
  SetColor(pctFS, pctColor)
  local K, cs, ui = C.COLORS, th.colors, th.ui
  local bg = (cs and cs.bg) or (ui and ui.bg) or K.track
  track:SetVertexColor(bg[1], bg[2], bg[3], 0.8)
  fillState = -1                                 -- the next XP update colours the fill
end

-- Fonts of the theme (the bar's info 1, separator and marker elements) at BASE_SIZE + the
-- theme's size deltas; rowH = the tallest of them.
local function ApplyFonts()
  local font, size = th.text.font, th.text.size
  itemRole, itemSize = font.s1 or "body", BASE_SIZE + (size.s1 or 0)
  sepRole, sepSize = font.sep or "body", BASE_SIZE + (size.sep or 0)
  pctRole, pctSize = font.marker or "body", BASE_SIZE + (size.marker or 0)
  for k = 1, N do
    Themes.SetFont(itemFS[k], itemRole, itemSize, outline)
    Themes.SetFont(sepFS[k], sepRole, sepSize, outline)
    ApplyShadow(itemFS[k])
    ApplyShadow(sepFS[k])
  end
  Themes.SetFont(pctFS, pctRole, pctSize, outline)
  ApplyShadow(pctFS)
  Themes.SetFont(meterItem, itemRole, itemSize, outline)
  Themes.SetFont(meterSep, sepRole, sepSize, outline)
  Themes.SetFont(meterPct, pctRole, pctSize, outline)
  local _, z1 = Themes.Font(itemRole, itemSize)
  local _, z2 = Themes.Font(sepRole, sepSize)
  local _, z3 = Themes.Font(pctRole, pctSize)
  rowH = math_max(z1 or itemSize, z2 or sepSize, showPct and (z3 or pctSize) or 0) + 2
end

---------------------------------------------------------------------------
-- Layout (on text or size changes only)
---------------------------------------------------------------------------

local function Anchor(fs, xs, ys, k, x, y)
  if xs[k] == x and ys[k] == y then return end
  xs[k], ys[k] = x, y
  fs:ClearAllPoints()
  fs:SetPoint("LEFT", frame, "TOPLEFT", x, y)
end

local function PlacePct(x, y)
  if pctX == x and pctY == y then return end
  pctX, pctY = x, y
  pctFS:ClearAllPoints()
  pctFS:SetPoint("LEFT", frame, "TOPLEFT", x, y)
end

local function SetLine(w)
  if w == lineW then return end
  lineW = w
  track:SetWidth(w)
  fillPx = -1
end

local function DrawFill()
  local px = math_floor(lineW * fillFrac + 0.5)
  if px == fillPx then return end
  fillPx = px
  if px > 0 then
    fill:SetWidth(px)
    fill:Show()
  else
    fill:Hide()
  end
end

local function Layout()
  layoutDirty = false
  local hasPct = showPct and pctText ~= EMPTY
  local rows = 0
  local contentW = 0
  local y0 = -(PAD_Y + rowH / 2)
  if vertical then
    for k = 1, nItems do
      Anchor(itemFS[k], itemX, itemY, k, PAD_X, y0 - rows * (rowH + ROW_GAP))
      rows = rows + 1
      if itemW[k] > contentW then contentW = itemW[k] end
    end
    for k = 1, N do SetShownFlag(sepOn, k, sepFS[k], false) end
    if hasPct then
      PlacePct(PAD_X, y0 - rows * (rowH + ROW_GAP))
      rows = rows + 1
      if pctW > contentW then contentW = pctW end
    end
  else
    local x = PAD_X
    for k = 1, nItems do
      if k > 1 then
        Anchor(sepFS[k - 1], sepX, sepY, k - 1, x + GAP, y0)
        x = x + GAP + sepW + GAP
      end
      Anchor(itemFS[k], itemX, itemY, k, x, y0)
      x = x + itemW[k]
    end
    local sepAfter = (hasPct and nItems > 0) and nItems or 0
    if sepAfter > 0 then
      Anchor(sepFS[sepAfter], sepX, sepY, sepAfter, x + GAP, y0)
      x = x + GAP + sepW + GAP
    end
    if hasPct then
      PlacePct(x, y0)
      x = x + pctW
    end
    for k = 1, N do SetShownFlag(sepOn, k, sepFS[k], k < nItems or k == sepAfter) end
    contentW = x - PAD_X
    if nItems > 0 or hasPct then rows = 1 end
  end
  if pctOn ~= hasPct then
    pctOn = hasPct
    if hasPct then pctFS:Show() else pctFS:Hide() end
  end
  if contentW < MIN_W then contentW = MIN_W end
  local textH = rows > 0 and (rows * rowH + (rows - 1) * ROW_GAP) or 0
  local h = PAD_Y + textH + PAD_Y
  if showLine then h = h + LINE_H + (rows > 0 and LINE_GAP or 0) end
  local w = contentW + 2 * PAD_X
  if showLine then
    SetLine(contentW)
    DrawFill()
  end
  if w ~= frameW or h ~= frameH then
    frameW, frameH = w, h
    frame:SetSize(w, h)
    ApplyPanel(false)
  end
end

---------------------------------------------------------------------------
-- XP (level percentage, XP line): redrawn only when XP, max, rest or max level change
---------------------------------------------------------------------------

local function UpdateXP()
  if not (showLine or showPct) then return end
  local T = ns.Tracker
  local _, xp, max, rested, valid
  if T and T.GetXPInfo then _, xp, max, rested, valid = T.GetXPInfo() end
  local isMax = IsMax()
  local showXP = valid and type(xp) == "number" and type(max) == "number" and max > 0 and not isMax
  local isRested = showXP and type(rested) == "number" and rested > 0
  local key
  if isMax then
    key = -1
  elseif showXP then
    key = (xp * 1000003 + max) * 2 + (isRested and 1 or 0)
  else
    key = -2
  end
  if key == xpKey then return end
  xpKey = key
  if showPct then
    local Tokens = ns.Tokens
    local t = showXP and Tokens.PercentText(Tokens.PercentTenths(xp, max)) or EMPTY
    if t ~= pctRaw then
      pctRaw = t
      pctText = t ~= EMPTY and Sub(pctRole, t) or EMPTY
      if pctText ~= EMPTY then
        pctFS:SetText(pctText)
        pctW = Measure(meterPct, pctText)
      else
        pctW = 0
      end
      layoutDirty = true
    end
  end
  if showLine then
    local frac = 0
    if isMax then
      frac = 1
    elseif showXP then
      frac = xp / max
      if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    end
    fillFrac = frac
    local state = isMax and 2 or (isRested and 1 or 0)
    if state ~= fillState then
      fillState = state
      local c = (state == 1) and lineRested or lineXP
      fill:SetVertexColor(c[1], c[2], c[3], (state == 2) and MAX_FILL_ALPHA or 1)
    end
    DrawFill()
  end
end

---------------------------------------------------------------------------
-- Public: refresh (TICK path - allocation free)
---------------------------------------------------------------------------

-- Info k shows `text` (raw token text), dimmed or not.
local function SetItem(k, text, dim)
  local fs = itemFS[k]
  SetShownFlag(itemOn, k, fs, true)
  if text ~= rawText[k] then
    rawText[k] = text
    local t = Sub(itemRole, text)
    fs:SetText(t)
    itemW[k] = Measure(meterItem, t)
    layoutDirty = true
  end
  if dim ~= itemDim[k] then
    itemDim[k] = dim
    SetColor(fs, dim and dimColor or valueColor)
  end
end

function Mini.Refresh()
  if not frame or not active then return end
  local Tokens = ns.Tokens
  local DEF = Tokens.DEF
  local isMax = IsMax()
  local k, maxUsed = 0, false
  for i = 1, N do
    local id = Resolve(i)
    if id ~= "none" then
      if DEF[id].xp and isMax then
        if maxUsed then id = nil else maxUsed = true end   -- "Max level" once
      end
      if id then
        local text, dim, paused = Tokens.Render(id)
        if type(text) == "string" and text ~= EMPTY then
          if not qualityOn and Tokens.IsNetToken(id) then text = Tokens.Plain(text) end
          k = k + 1
          SetItem(k, text, (dim or paused) and true or false)
        end
      end
    end
  end
  if k ~= nItems then
    nItems = k
    for j = k + 1, N do
      SetShownFlag(itemOn, j, itemFS[j], false)
      rawText[j] = nil
    end
    layoutDirty = true
  end
  UpdateXP()
  if layoutDirty then Layout() end
end

---------------------------------------------------------------------------
-- Alpha, position
---------------------------------------------------------------------------

local function ApplyAlpha()
  if not frame then return end
  local m = Settings()
  local a = 1
  if combatHidden then
    a = 0
  elseif m and m.fade and not hovered then
    a = FADE_ALPHA
  end
  frame:SetAlpha(a)
end

local function ApplyPosition()
  if not frame then return end
  local m = Settings()
  local p = m and m.point
  local def = C.DEFAULTS.mini.point
  local point, rel, x, y = def[1], def[2], def[3], def[4]
  if type(p) == "table" and type(p[1]) == "string" then
    point = p[1]
    rel = (type(p[2]) == "string") and p[2] or point
    x = tonumber(p[3]) or 0
    y = tonumber(p[4]) or 0
  end
  frame:ClearAllPoints()
  frame:SetPoint(point, UIParent, rel, x, y)
end

---------------------------------------------------------------------------
-- Layout from the settings and the theme
---------------------------------------------------------------------------

function Mini.ApplyLayout()
  if not frame then return end
  local m = Settings() or C.DEFAULTS.mini
  local t = Themes.Active()
  local rebuild = skinGen == false or t ~= th
  th = t
  vertical = m.layout == "vertical"
  local xpMode = m.xp
  showLine = xpMode == "line" or xpMode == "both"
  showPct = xpMode == "pct" or xpMode == "both"
  frame:SetScale(Clamp(m.scale, 0.5, 2.0, 1.0))
  ReadStyle()
  if rebuild then BuildPanel() end
  skinGen = t.gen
  ApplyFonts()
  ApplyColors()
  -- separator: L.SEP without its spaces (read here: the language is applied after load)
  local st = strtrim(L.SEP or "")
  if st == "" then st = "\194\183" end
  sepText = Sub(sepRole, st)
  for k = 1, N do sepFS[k]:SetText(sepText) end
  sepW = Measure(meterSep, sepText)
  -- every text set and measured again, every anchor and size placed again
  for k = 1, N do
    rawText[k], itemX[k], itemY[k], sepX[k], sepY[k] = nil, false, false, false, false
  end
  nItems, pctRaw, pctText, pctW, pctX, pctY = -1, nil, EMPTY, 0, false, false
  xpKey, lineW, fillPx = false, -1, -1
  frameW, frameH = -1, -1
  if showLine then
    track:Show()
  else
    track:Hide()
    fill:Hide()
  end
  if not showPct and pctOn then
    pctOn = false
    pctFS:Hide()
  end
  ApplyPosition()
  ApplyAlpha()
  layoutDirty = true
  if active then
    Mini.Refresh()
  else
    Layout()
  end
  ApplyPanel(true)
end

-- THEME_CHANGED: "colors" recolours in place (panel, texts, XP line); a new theme restyles.
local function OnThemeChanged(_, _, _, kind)
  if not frame then return end
  local t = Themes.Active()
  if kind == "colors" and t == th and skinGen ~= false then
    skinGen = t.gen
    ReadStyle()
    ApplyColors()
    xpKey = false
    ApplyPanel(true)
    Mini.Refresh()
    return
  end
  Mini.ApplyLayout()
end

---------------------------------------------------------------------------
-- Frame scripts (created once)
---------------------------------------------------------------------------

local function HideTooltip(self)
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.Hide then Tooltip.Hide(self) end
end

local function OnEnter(self)
  hovered = true
  ApplyAlpha()
  if dragging then return end
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.ShowFor then Tooltip.ShowFor(self) end
end

local function OnLeave(self)
  hovered = false
  ApplyAlpha()
  HideTooltip(self)
end

-- Ends a drag once (OnDragStop or OnMouseUp, whichever comes first) and stores the
-- rounded position. Returns true when a drag was ended.
local function EndDrag(self)
  self:StopMovingOrSizing()
  if not dragging then return false end
  dragging = false
  local point, _, rel, x, y = self:GetPoint(1)
  if type(point) == "string" then
    ns.Core.SetSetting("mini.point", {
      point, (type(rel) == "string") and rel or point,
      Util.Round(tonumber(x) or 0), Util.Round(tonumber(y) or 0),
    })
  end
  ApplyPosition()
  return true
end

local function OnMouseDown()
  dragging, dropped = false, false
end

local function OnMouseUp(self, button)
  if EndDrag(self) or dropped then
    dropped = false
    return
  end
  if button == "RightButton" then
    if ns.Options and ns.Options.ShowContextMenu then ns.Options.ShowContextMenu(self) end
  elseif button == "LeftButton" then
    if ns.Window and ns.Window.Toggle then ns.Window.Toggle() end
  end
end

local function OnDragStart(self)
  local m = Settings()
  if not m or m.locked then return end
  dragging = true
  HideTooltip(self)
  self:StartMoving()
end

local function OnDragStop(self)
  if EndDrag(self) then dropped = true end
end

local function OnHide(self)
  hovered = false
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.IsShownFor and Tooltip.IsShownFor(self) then Tooltip.Hide(self) end
end

---------------------------------------------------------------------------
-- Creation (lazy: only when the mini display has to be shown)
---------------------------------------------------------------------------

local function NewText(layer)
  local fs = frame:CreateFontString(nil, layer or "OVERLAY")
  Themes.SetFont(fs, "body", BASE_SIZE, "thin")
  fs:SetWordWrap(false)
  fs:SetJustifyH("LEFT")
  return fs
end

local function NewMeter()
  local m = NewText("BACKGROUND")
  m:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  m:SetAlpha(0)                                  -- never seen; always "shown" for measures
  return m
end

local function Create()
  frame = CreateFrame("Frame", "TruePlayedMiniDisplay", UIParent, "BackdropTemplate")
  Mini.frame = frame
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  for k = 1, N do
    itemFS[k] = NewText("OVERLAY")
    itemFS[k]:Hide()
    itemOn[k] = false
    sepFS[k] = NewText("OVERLAY")
    sepFS[k]:Hide()
    sepOn[k] = false
  end
  pctFS = NewText("OVERLAY")
  pctFS:Hide()
  pctOn = false
  meterItem, meterSep, meterPct = NewMeter(), NewMeter(), NewMeter()
  track = frame:CreateTexture(nil, "ARTWORK", nil, 0)
  track:SetTexture(C.TEX_WHITE)
  track:SetHeight(LINE_H)
  track:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD_X, PAD_Y)
  fill = frame:CreateTexture(nil, "ARTWORK", nil, 1)
  fill:SetTexture(C.TEX_WHITE)
  fill:SetHeight(LINE_H)
  fill:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD_X, PAD_Y)
  fill:Hide()
  frame:SetScript("OnEnter", OnEnter)
  frame:SetScript("OnLeave", OnLeave)
  frame:SetScript("OnMouseDown", OnMouseDown)
  frame:SetScript("OnMouseUp", OnMouseUp)
  frame:SetScript("OnDragStart", OnDragStart)
  frame:SetScript("OnDragStop", OnDragStop)
  frame:SetScript("OnHide", OnHide)
  -- read-only handles for the offline tests (our own frame)
  frame.tp = { items = itemFS, seps = sepFS, pct = pctFS, track = track, fill = fill, panel = texPool }
  Mini.ApplyLayout()
end

---------------------------------------------------------------------------
-- Activation / visibility
---------------------------------------------------------------------------

local UpdateVisibility   -- forward declaration

local function OnRefreshMsg()
  Mini.Refresh()
end

local function SetActive(on)
  if on == active then return end
  active = on
  local Tokens = ns.Tokens
  if on then
    ns.RegisterMessage("TICK", Mini, OnRefreshMsg)
    ns.RegisterMessage("STATE_CHANGED", Mini, OnRefreshMsg)
    ns.RegisterMessage("SESSION_RESET", Mini, OnRefreshMsg)
    ns.RegisterMessage("PLAYED_SYNCED", Mini, OnRefreshMsg)
    ns.RegisterMessage("CHAR_RESET", Mini, OnRefreshMsg)
    ns.RegisterMessage("XP_CHANGED", Mini, OnRefreshMsg)
    ns.RegisterMessage("LEVEL_UP", Mini, OnRefreshMsg)
    Tokens.Acquire("mini", N, Resolve)           -- also refreshes the token context
    Mini.Refresh()
  else
    ns.UnregisterMessage("TICK", Mini)
    ns.UnregisterMessage("STATE_CHANGED", Mini)
    ns.UnregisterMessage("SESSION_RESET", Mini)
    ns.UnregisterMessage("PLAYED_SYNCED", Mini)
    ns.UnregisterMessage("CHAR_RESET", Mini)
    ns.UnregisterMessage("XP_CHANGED", Mini)
    ns.UnregisterMessage("LEVEL_UP", Mini)
    Tokens.Release("mini")
    if frame then OnHide(frame) end
  end
end

local function OnRegenDisabled()
  inCombat = true
  UpdateVisibility()
end

local function OnRegenEnabled()
  inCombat = false
  UpdateVisibility()
end

local function SetRegenEvents(on)
  if on == regenOn then return end
  regenOn = on
  if on then
    inCombat = InCombatLockdown() and true or false
    ns.RegisterEvent("PLAYER_REGEN_DISABLED", Mini, OnRegenDisabled)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", Mini, OnRegenEnabled)
  else
    ns.UnregisterEvent("PLAYER_REGEN_DISABLED", Mini)
    ns.UnregisterEvent("PLAYER_REGEN_ENABLED", Mini)
    inCombat = false
  end
end

-- Applies mini.shown / combatHide. Returns true when active.
UpdateVisibility = function()
  local m = Settings()
  if not m then return false end
  local want = m.shown == true
  SetRegenEvents(want and m.combatHide == true)
  if want and not frame then Create() end
  if frame then
    if want then
      combatHidden = regenOn and inCombat
      frame:Show()
      frame:EnableMouse(not combatHidden)
      ApplyAlpha()
      SetActive(not combatHidden)
    else
      combatHidden = false
      frame:Hide()
      SetActive(false)
    end
  end
  return active
end

---------------------------------------------------------------------------
-- Messages kept while initialised
---------------------------------------------------------------------------

local function OnSettingsChanged(_, path)
  if VISIBILITY_PATHS[path] then
    UpdateVisibility()
    return
  end
  if not frame then return end
  if path == "theme" or (type(path) == "string" and (path:find("widget.xpColor", 1, true) == 1
      or path:find("widget.restedColor", 1, true) == 1)) then
    return                                         -- Themes': THEME_CHANGED follows
  end
  if LAYOUT_PATHS[path] then
    Mini.ApplyLayout()
  elseif STYLE_PATHS[path] or (type(path) == "string" and path:find("widget.textColor.", 1, true) == 1) then
    ReadStyle()
    ApplyColors()
    for k = 1, N do rawText[k] = nil end            -- quality colours: texts set again
    Mini.Refresh()
  elseif path == "mini.point" then
    ApplyPosition()
  elseif path == "mini.fade" then
    ApplyAlpha()
  else
    Mini.Refresh()                                 -- infos, exclusions, rateTau...
  end
end

local function OnDBSwapped()
  UpdateVisibility()
  if frame then Mini.ApplyLayout() end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Mini.Init()
  if inited then return end
  inited = true
  ns.RegisterMessage("SETTINGS_CHANGED", Mini, OnSettingsChanged)
  ns.RegisterMessage("DB_SWAPPED", Mini, OnDBSwapped)
  ns.RegisterMessage("THEME_CHANGED", Mini, OnThemeChanged)
  UpdateVisibility()
end

function Mini.SetShown(shown)
  ns.Core.SetSetting("mini.shown", shown and true or false)
  if inited then UpdateVisibility() end
end

-- /tpl mini, the minimap button's "mini" action: shows or hides it, and says so.
function Mini.Toggle()
  local m = Settings()
  local shown = not (m and m.shown == true)
  Mini.SetShown(shown)
  Util.Print(shown and L.MINI_SHOWN or L.MINI_HIDDEN)
end

function Mini.IsActive()
  return active
end

function Mini.ResetPosition()
  ns.Core.SetSetting("mini.point", Util.DeepCopy(C.DEFAULTS.mini.point))
  ApplyPosition()
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", Mini, Mini.Init)
end
