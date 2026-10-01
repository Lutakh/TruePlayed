local ADDON, ns = ...
local L, C, Util, Fmt = ns.L, ns.C, ns.Util, ns.Fmt
local Themes, Skin = ns.Themes, ns.BarSkin

-- Bar.lua - the on-screen widget: the XP bar (the mockup).
--
-- Performance contract (SPEC 6):
--   * no per-frame script; the widget listens to TICK only while it is visible and active;
--   * Refresh() allocates nothing when no displayed text changed and calls SetText
--     only when a slot string changed (token strings are cached by Tokens);
--   * XP visuals (fill, rested, level/XP texts, % marker) change only on XP_CHANGED,
--     LEVEL_UP, DB_SWAPPED, CHAR_RESET or a layout change, and every draw call is
--     skipped when the integer pixel value did not change;
--   * the look comes from the active theme (Themes.Active(), SPEC-themes): BarSkin.lua
--     draws its layers (track, fill, rested part, ornaments) and its panel; this file
--     keeps the texts, their fonts (Themes.SetFont) and colours, and the behaviour. Like
--     the game's own XP bar, the fill takes the rested colour while rested XP is left
--     (GetXPExhaustion() > 0) and the XP colour otherwise; the rested part runs from
--     current XP to current XP + rested, capped at the level end. The fill state (normal,
--     rested, max level) changes only on XP / exhaustion / level events. The XP and
--     rested colours (theme or widget.xpColor / widget.restedColor) are compiled by
--     Themes, which sends THEME_CHANGED "colors" when they change;
--   * bottom row "LEVEL 20   0.3%        XP: 58 / 23,200 · ~4.5k/h": the right
--     part (XP text, separator, pause mark, slot 2) never reaches the level text. Text
--     widths are measured (GetStringWidth on hidden-proof "meter" FontStrings) only
--     when a text changes, then the right part degrades in steps until it fits: short
--     numbers (58 / 23.2k), no "XP:" label, slot 2 in its short form (a token with
--     one, e.g. eta_kills -> the ETA alone), no slot 2, and at last slot 2 alone or
--     nothing. The % marker (one decimal, like the tooltip) only takes the space left;
--     with pctPos = "level", a level text wider than the bar drops its percent;
--   * top row: slot 1 (top right, with its pause mark) is bounded to the
--     inner width; slot 3 (top centre or left) is shifted away from slot 1. A token
--     with a short form uses it (slot 1 first) rather than leaving slot 3 out; slot 3 is
--     hidden only when it cannot be drawn clear of slot 1 even then;
--   * texts: one colour for every text when widget.textColor is set (else the theme's
--     text colours), outline (none / thin / thick) and drop shadow; FPS / latency keep
--     their green / yellow / red numbers unless widget.qualityColors is off. Split themes
--     draw the level and the XP numbers as label + value (two FontStrings each);
--   * slots showing FPS / latency get a mouse region over their text: hovering it shows
--     the history graph (Graph.lua) instead of the tooltip; clicks and drags on it act
--     on the widget;
--   * at max level the fill is drawn full width and dimmed (no empty-looking track);
--     a detected server level cap (Tracker.GetCapInfo) is drawn the same way, the level
--     text reading "LEVEL 20 · CAP"; the tick notices when the character enters or
--     leaves max level (the cap is set after a fight, cleared by the next XP gain);
--   * hideAtMax hides the widget at the real max level only, never at a server level
--     cap (the cap explanation stays one hover away, and the cap is temporary);
--   * hidden (shown = false, hideAtMax, combatHide in combat) => TICK unregistered and
--     the "bar" token consumer released, so FPS/latency are no longer sampled for it.

local math_floor, math_min, math_max = math.floor, math.min, math.max
local type, tonumber = type, tonumber
local format = format
local CreateFrame, UIParent = CreateFrame, UIParent
local InCombatLockdown, UnitLevel = InCombatLockdown, UnitLevel

local Bar = {}
ns.Bar = Bar
Bar.frame = nil

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local NSLOTS       = 3
local SLOT_E       = { "s1", "s2", "s3" }   -- text element of each slot (SPEC-themes 2.5)
local SEP_GAP      = 4      -- gap on each side of the separator between the XP text and slot 2
local MARKER_GAP   = 6      -- min gap between the % marker and its neighbours
local EDGE_GAP     = 6      -- min gap between the level text and the right part of the bottom row
local TOP_GAP      = 8      -- min gap between slot 3 and slot 1 (top row)
local MARK_W       = 7      -- pause mark width
local MARK_GAP     = 3      -- gap between a pause mark and its slot text
local MARK_SPACE   = MARK_W + MARK_GAP
local FADE_ALPHA   = 0.35
local VEIL_ALPHA   = 0.20
local EMPTY        = ""
local BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- SETTINGS_CHANGED paths grouped by the work they need.
local VISIBILITY_PATHS = {
  ["widget.shown"] = true, ["widget.hideAtMax"] = true, ["widget.combatHide"] = true,
}
local LAYOUT_PATHS = {
  ["widget.scale"] = true, ["widget.width"] = true,
  ["widget.height"] = true, ["widget.fontSize"] = true, ["widget.background"] = true,
  ["widget.bgAlpha"] = true, ["widget.outline"] = true, ["widget.shadow"] = true,
  ["widget.slot3Pos"] = true, ["widget.pctPos"] = true,
}
local STYLE_PATHS = {                         -- colours only: no new measures
  ["widget.textColor"] = true, ["widget.qualityColors"] = true,
}
-- "theme", widget.xpColor* and widget.restedColor* are Themes' (SPEC-themes S8): Bar
-- follows THEME_CHANGED instead.

---------------------------------------------------------------------------
-- State (module-private)
---------------------------------------------------------------------------

local frame                      -- the widget (== Bar.frame once created)
local th                         -- compiled theme the widget is drawn with
local skinGen = false            -- th.gen of the last skin build / recolour (false: none yet)
local inited = false
local active = false             -- TICK registered + "bar" token consumer acquired
local watching = false           -- XP_CHANGED / LEVEL_UP registered (widget.shown)
local regenOn = false            -- PLAYER_REGEN_* registered (widget.combatHide)
local inCombat = false
local combatHidden = false
local hovered = false
local dragging = false           -- from OnDragStart until the drag ends (EndDrag)
local dropped = false            -- OnDragStop ended a drag: its mouse-up is not a click
local xpPending = true           -- XP not valid yet: re-check on TICK until it is

-- regions
local slotFS, slotMark = {}, {}
local lastText, lastDim, lastPaused = {}, {}, {}
local lastAlt = {}               -- [i] short form of the slot's token (or nil)
local shownText = {}             -- [i] text currently set on the slot FontString
local lastId = {}                -- [i] token id resolved for the slot
local slotColor = {}             -- [i] colour table used when the slot is not dim
local slotDrawn = {}             -- [i] false while the layout leaves the slot out (no room)
local markOn = {}                -- [i] pause mark drawn
local hit, hitWant, hitOn = {}, {}, {}   -- [i] graph hover region over an FPS / latency slot
local tex = {}                   -- named textures (BarSkin's layers + tex.veil)
local bl, brx, sepFS, marker, hint
local allTexts = {}              -- every visible FontString (outline, shadow)
-- split themes (SPEC-themes 2.5): level label (bl) + level value (blv), XP label (xpl) +
-- XP value (brx); blv / xpl are created at the first split build
local sp = {
  on = false, gap = 4, title = false, blv = nil, xpl = nil,
  wXPL = 0, valW = { 0, 0, 0 },      -- XP label width, XP value width of each variant
  blText = nil, blvText = nil,       -- texts set on bl / blv
  blvOn = false, xplOn = false, blvX = false, xplX = false,
}

-- applied layout
local pad = 8                    -- frame padding (the theme's bar.pad)
local ox, oy, lineW, lineH = 8, 0, 300, 8     -- progress line origin and size
local topY = 0                   -- bottom of the top row
local usePctMarker, usePctLevel = false, false
local slot3Left = false
local fontSize = 11

-- text style (widget.outline / shadow / textColor / qualityColors)
local outline = "thin"           -- widget.outline for Themes.SetFont: "none" | "thin" | "thick"
local shadowOn = true
local qualityOn = true
local customOn = false
local customRGB = { 1, 1, 1 }
local dimColor = C.COLORS.dim

-- measured widths (refreshed only when the measured text changes)
local slotW = { 0, 0, 0 }
local slotWAlt = { 0, 0, 0 }     -- widths of the short forms
local wBL, wSep, wMarker = 0, 0, 0
local xpText, xpW = {}, { 0, 0, 0 }   -- XP text variants: full, short numbers, no label
local brxCur = nil               -- variant text currently set on the XP FontString
local clusterLeft = 0            -- left edge of the bottom row's right part
local brxX, sepX, s3X, s1Bound = false, false, false, -1
local topDirty, bottomDirty = true, true

-- XP visual caches (integers; -1 = force redraw)
local fillPx, restPx = -1, -1
local blKey, brxKey = -1, -1
local pctKey = -1                -- tenths of a percent shown by the marker
local markerShown = false        -- marker wanted (pctPos = "follow" and XP shown)
local markerVisible = false      -- marker drawn (wanted and room for it)
local markerX = false
local markerDirty = false
local brxShown = true            -- XP text drawn
local sepShown = false           -- separator drawn (XP text and slot 2 both drawn)
local fillKey = -1               -- fill state: 0 normal, 1 rested, 2 max level
local drawnMax = nil             -- IsMax() when the XP visuals were last drawn

local ApplyHit                   -- forward declaration (graph hover regions)

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function Widget()
  local s = ns.settings
  return s and s.widget
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

-- Max level only because of a detected server level cap (C2): a temporary state.
local function IsServerCap()
  local T = ns.Tracker
  if T == nil or T.GetCapInfo == nil then return false end
  local capLevel, isServerCap = T.GetCapInfo()
  return isServerCap == true and capLevel ~= nil
end

-- Font of text element e (SPEC-themes 2.5) on fs, at widget.fontSize + delta (fs nil:
-- nothing set). Returns the size the font really gets (pixel fonts snap): the row heights.
local function ElemFont(fs, e, delta)
  local role = th.text.font[e] or "body"
  local size = fontSize + (delta or 0)
  if fs then Themes.SetFont(fs, role, size, outline) end
  local _, z = Themes.Font(role, size)
  return z or size
end

-- Drop shadow of the theme (widget.shadow on), or none (offset 0, alpha 0).
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

local function NewFontString(layer)
  local fs = frame:CreateFontString(nil, layer or "OVERLAY")
  Themes.SetFont(fs, "body", 11, outline)
  fs:SetWordWrap(false)                 -- one line; a bounded width ends with "..."
  ApplyShadow(fs)
  fs:SetJustifyV("BOTTOM")
  return fs
end

-- Pause marks: two 2 x 7 px white bars next to a slot text.
local function NewPauseMark()
  local m = CreateFrame("Frame", nil, frame)
  m:SetSize(MARK_W, 7)
  local a = m:CreateTexture(nil, "OVERLAY")
  a:SetTexture(C.TEX_WHITE)
  a:SetVertexColor(1, 1, 1, 0.7)
  a:SetSize(2, 7)
  a:SetPoint("LEFT", m, "LEFT", 0, 0)
  local b = m:CreateTexture(nil, "OVERLAY")
  b:SetTexture(C.TEX_WHITE)
  b:SetVertexColor(1, 1, 1, 0.7)
  b:SetSize(2, 7)
  b:SetPoint("RIGHT", m, "RIGHT", 0, 0)
  m:Hide()
  return m
end

local function AnchorMark(i, side)
  local m, fs = slotMark[i], slotFS[i]
  m:ClearAllPoints()
  if side == "right" then
    m:SetPoint("LEFT", fs, "RIGHT", MARK_GAP, 0)
  else
    m:SetPoint("RIGHT", fs, "LEFT", -MARK_GAP, 0)
  end
end

-- Pause mark of slot i: shown while the slot is paused and drawn (Show/Hide on change).
local function ApplyMark(i)
  local want = (lastPaused[i] and slotDrawn[i] ~= false) and true or false
  if want == markOn[i] then return end
  markOn[i] = want
  if want then slotMark[i]:Show() else slotMark[i]:Hide() end
end

-- Slot i drawn or left out by the layout (Show/Hide on change only).
local function SetDrawn(i, on)
  if slotDrawn[i] == on then return end
  slotDrawn[i] = on
  if on then slotFS[i]:Show() else slotFS[i]:Hide() end
  ApplyMark(i)
  ApplyHit(i)
end

-- Slot i shows its full text or its short form (SetText only when the text changes).
local function SetVariant(i, use)
  local t = Skin.Sub(SLOT_E[i], (use and lastAlt[i]) or lastText[i] or EMPTY)
  if t ~= shownText[i] then
    shownText[i] = t
    slotFS[i]:SetText(t)
  end
end

-- Width of slot text t in the slot's font (never shown: a meter).
local function SlotWidth(i, t)
  local e = SLOT_E[i]
  return Skin.Measure(e, Skin.Sub(e, t))
end

-- Compact XP numbers for a narrow bar: 58, 950, 8.2k, 23.2k, 210k (8,2k in French).
local function Compact(n)
  local v = math_floor((tonumber(n) or 0) + 0.5)
  if v < 1000 then return format("%d", v) end
  if v < 99950 then
    local t = math_floor(v / 100 + 0.5)          -- tenths of k
    local whole = math_floor(t / 10)
    local dec = t - whole * 10
    if dec == 0 then return format(L.NUM_K, format("%d", whole)) end
    return format(L.NUM_K, format("%d%s%d", whole, L.DECIMAL_SEP, dec))
  end
  return Fmt.Short(v)
end
Bar.Compact = Compact

---------------------------------------------------------------------------
-- Text style and colours
---------------------------------------------------------------------------

local ReadTextStyle, ApplyBackground
do
  local OUTLINES = { none = true, thin = true, thick = true }   -- anything else reads "thin"
  local LEGACY_BG_ALPHA = C.LEGACY_BG_ALPHA or 0.85   -- the former on/off dark background
  local customDim = { 1, 1, 1, 0.55 }            -- dim state of a custom text colour

  local function Unit(x)
    x = tonumber(x)
    if not x or x ~= x or x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
  end

  -- widget.outline / shadow / qualityColors / textColor ({ r, g, b } or false).
  ReadTextStyle = function(w)
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
    dimColor = customOn and customDim or th.text.colors.dimmed or C.COLORS.dim
  end

  -- Background: widget.bgAlpha (0 = none); a record not migrated yet may still have the
  -- former on/off widget.background. A theme with panel parts draws them (BarSkin, over
  -- the fw x fh frame); "backdrop" is the classic tooltip backdrop in the theme's colours,
  -- its border fading with the background.
  ApplyBackground = function(w, fw, fh)
    local a = tonumber(w.bgAlpha)
    if a == nil then a = (w.background == true) and LEGACY_BG_ALPHA or 0 end
    a = Unit(a)
    if type(th.bar.panel) == "table" then
      if frame.SetBackdrop then frame:SetBackdrop(nil) end
      Skin.Panel(a, fw, fh)
      return
    end
    if not frame.SetBackdrop then return end
    if a > 0 then
      frame:SetBackdrop(BACKDROP)
      local K, cs, ui = C.COLORS, th.colors, th.ui
      local bg = (cs and cs.bg) or (ui and ui.bg) or K.bg
      local bd = (cs and cs.border) or (ui and ui.border) or K.border
      frame:SetBackdropColor(bg[1], bg[2], bg[3], a)
      frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], (K.border[4] or 1) * math_min(1, a / LEGACY_BG_ALPHA))
    else
      frame:SetBackdrop(nil)
    end
  end
end

local function SetColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- The theme's text colours (SPEC-themes 2.5 roles) or the custom colour on every text.
local function ApplyTextColors()
  local tc = th.text.colors
  local custom = customOn and customRGB
  SetColor(bl, custom or tc.levelLabel)
  SetColor(brx, custom or tc.xpText)
  SetColor(sepFS, custom or tc.sep)
  SetColor(marker, custom or tc.marker)
  SetColor(hint, custom or tc.hint)
  if sp.blv then
    SetColor(sp.blv, custom or tc.levelValue)
    SetColor(sp.xpl, custom or tc.label)
  end
  slotColor[1] = custom or tc.value
  slotColor[2] = custom or tc.slot2 or tc.value
  slotColor[3] = custom or tc.slot3
  for i = 1, NSLOTS do lastDim[i] = nil end    -- the next Refresh sets the slot colours
end

-- Unlocked veil: the theme's accent colour (L8).
local function ApplyVeil()
  local acc = th.accent or C.COLORS.accent
  tex.veil:SetVertexColor(acc[1], acc[2], acc[3], VEIL_ALPHA)
end

---------------------------------------------------------------------------
-- Alpha, lock, position
---------------------------------------------------------------------------

local function ApplyAlpha()
  if not frame then return end
  local w = Widget()
  local a = 1
  if combatHidden then
    a = 0
  elseif w and w.fade and not hovered then
    a = FADE_ALPHA
  end
  frame:SetAlpha(a)
end

local function ApplyLock()
  if not frame then return end
  local w = Widget()
  local unlocked = not (w and w.locked)
  if unlocked then
    tex.veil:Show()
    hint:Show()
  else
    tex.veil:Hide()
    hint:Hide()
  end
end

local function ApplyPosition()
  if not frame then return end
  local w = Widget()
  local p = w and w.point
  local point, rel, x, y = "CENTER", "CENTER", 0, -220
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
-- Layout of the text rows (widths measured on text changes only)
---------------------------------------------------------------------------

local function SetBrxShown(on)
  if on == brxShown then return end
  brxShown = on
  if on then brx:Show() else brx:Hide() end
end

local function SetSepShown(on)
  if on == sepShown then return end
  sepShown = on
  if on then sepFS:Show() else sepFS:Hide() end
end

-- Bottom row, right part (from the right edge): slot 2 (+ its pause mark on its left),
-- separator, XP text (split themes: XP label + XP value). It must stay EDGE_GAP px clear
-- of the level text; it degrades in steps until it does: short numbers, no "XP:" label,
-- slot 2 in its short form, no slot 2 (XP text alone), then slot 2 alone, then nothing.
local function LayoutBottom()
  bottomDirty = false
  markerDirty = true
  local right = pad + lineW
  local avail = lineW - wBL - EDGE_GAP
  local t2 = lastText[2]
  local has2 = t2 ~= nil and t2 ~= EMPTY
  local m2 = lastPaused[2] and MARK_SPACE or 0
  local full2 = has2 and (slotW[2] + m2) or 0
  local hasAlt2 = has2 and lastAlt[2] ~= nil
  local short2 = hasAlt2 and (slotWAlt[2] + m2) or 0
  local hasXP = xpText[1] ~= nil
  local sepPart = wSep + 2 * SEP_GAP
  local v, show2, use2 = 0, false, false
  if hasXP and has2 then
    for i = 1, 3 do
      if v == 0 and xpW[i] + sepPart + full2 <= avail then v = i end
    end
    if v == 0 and hasAlt2 then
      for i = 1, 3 do
        if v == 0 and xpW[i] + sepPart + short2 <= avail then v, use2 = i, true end
      end
    end
    show2 = v > 0
  end
  if v == 0 then
    if hasXP then
      for i = 1, 3 do
        if v == 0 and xpW[i] <= avail then v = i end
      end
    end
    if v == 0 and has2 then
      if full2 <= avail then
        show2 = true
      elseif hasAlt2 and short2 <= avail then
        show2, use2 = true, true
      end
    end
  end
  SetVariant(2, use2)
  SetDrawn(2, show2 or not has2)

  local part2 = use2 and short2 or full2
  local x = right
  if show2 then x = right - part2 end
  local sepOn = v > 0 and show2
  if sepOn then
    local sx = math_floor(x - SEP_GAP + 0.5)       -- separator's right edge
    if sx ~= sepX then
      sepX = sx
      sepFS:ClearAllPoints()
      sepFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", sx, pad)
    end
    x = x - SEP_GAP - wSep - SEP_GAP
  end
  SetSepShown(sepOn)
  if v > 0 then
    local text = xpText[v]
    if text ~= brxCur then
      brxCur = text
      brx:SetText(text)
    end
    local bx = math_floor(x + 0.5)                 -- XP text's right edge
    if bx ~= brxX then
      brxX = bx
      brx:ClearAllPoints()
      brx:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", bx, pad)
    end
    if sp.on then                                  -- XP label left of the value (variants 1, 2)
      local lon = v < 3
      if lon then
        local lx = math_floor(x - sp.valW[v] - sp.gap + 0.5)
        if lx ~= sp.xplX then
          sp.xplX = lx
          sp.xpl:ClearAllPoints()
          sp.xpl:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", lx, pad)
        end
      end
      if lon ~= sp.xplOn then
        sp.xplOn = lon
        if lon then sp.xpl:Show() else sp.xpl:Hide() end
      end
    end
    x = x - xpW[v]
  else
    if brxCur ~= EMPTY then
      brxCur = EMPTY                               -- no stale XP text (max level)
      brx:SetText(EMPTY)
    end
    if sp.xplOn then
      sp.xplOn = false
      sp.xpl:Hide()
    end
  end
  SetBrxShown(v > 0)
  clusterLeft = x
end

-- Slot 3 beside a slot 1 whose left edge (pause mark included) is at limit - TOP_GAP:
-- fits, and the centre x when slot 3 is centred (shifted left to stay clear).
local function PlaceSlot3(limit, w3, m3)
  if slot3Left then return pad + w3 + m3 <= limit, nil end   -- anchored at pad, mark on its right
  local cx = pad + math_floor(lineW / 2)
  if cx + w3 / 2 > limit then cx = math_floor(limit - w3 / 2) end
  return cx - w3 / 2 - m3 >= pad, cx               -- mark on its left
end

-- Top row: slot 1 at the right (with its pause mark on its left), bounded to the inner
-- width; slot 3 centred (shifted left when it would come closer than TOP_GAP px to
-- slot 1) or at the left. Short forms are used, slot 1 first, when both do not fit;
-- slot 3 is left out when it cannot be drawn clear of slot 1 even then.
local function LayoutTop()
  topDirty = false
  local right = pad + lineW
  local t1, t3 = lastText[1], lastText[3]
  local has1 = t1 ~= nil and t1 ~= EMPTY
  local has3 = t3 ~= nil and t3 ~= EMPTY
  local m1 = lastPaused[1] and MARK_SPACE or 0
  local m3 = lastPaused[3] and MARK_SPACE or 0
  local alt1 = has1 and lastAlt[1] ~= nil
  local alt3 = has3 and lastAlt[3] ~= nil
  local use1, use3, show3, cx = false, false, false, nil
  if has3 then
    -- combinations in order: full + full, short 1, short 3, both short
    for c = 1, 4 do
      local s1, s3 = (c == 2 or c == 4), (c >= 3)
      if not show3 and (alt1 or not s1) and (alt3 or not s3) then
        local w1 = has1 and (s1 and slotWAlt[1] or slotW[1]) or 0
        if w1 + m1 <= lineW then
          local limit = has1 and (right - w1 - m1 - TOP_GAP) or right
          local fits, x = PlaceSlot3(limit, s3 and slotWAlt[3] or slotW[3], m3)
          if fits then show3, use1, use3, cx = true, s1, s3, x end
        end
      end
    end
  end
  if not show3 and alt1 and slotW[1] + m1 > lineW then use1 = true end

  -- slot 1 bounded to the inner width (ends with "...")
  local w1 = has1 and (use1 and slotWAlt[1] or slotW[1]) or 0
  local bound = 0
  if w1 + m1 > lineW then bound = math_max(lineW - m1, 1) end
  if bound ~= s1Bound then
    s1Bound = bound
    slotFS[1]:SetWidth(bound)
  end
  SetVariant(1, use1)
  SetDrawn(1, true)

  SetVariant(3, use3)
  if not has3 then
    SetDrawn(3, true)
    return
  end
  SetDrawn(3, show3)
  if show3 and cx and cx ~= s3X then
    s3X = cx
    local s3 = slotFS[3]
    s3:ClearAllPoints()
    s3:SetPoint("BOTTOM", frame, "BOTTOMLEFT", cx, topY)
  end
end

-- % marker (pctPos = "follow"): centred on the fill end, clamped between the level
-- text and the right part of the row; hidden when the free space is narrower than it.
local function SetMarkerVisible(on)
  if on == markerVisible then return end
  markerVisible = on
  if on then marker:Show() else marker:Hide() end
end

local function PlaceMarker()
  markerDirty = false
  if not markerShown then return end
  local mW = wMarker
  local left = pad + wBL + MARKER_GAP
  local right = clusterLeft - MARKER_GAP
  if right - left < mW then
    SetMarkerVisible(false)                     -- no room: never drawn over a text
    return
  end
  SetMarkerVisible(true)
  local x = pad + math_max(fillPx, 0) - mW / 2  -- centred on the fill end
  if x < left then
    x = left
  elseif x + mW > right then
    x = right - mW
  end
  x = math_floor(x + 0.5)
  if x ~= markerX then
    markerX = x
    marker:ClearAllPoints()
    marker:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, pad)
  end
end

-- Level text (bottom left): "LEVEL 20", with the percent text `pct` (pctPos = "level")
-- or the cap tag (isCap); levelFmt "title" gives "Level 20 · ...". Split themes draw
-- the level label and that value as two texts (bl, blv). A level text wider than the
-- bar drops its value. Texts are set only when they change.
local function LevelText(level, pct, isCap)
  local title = sp.title
  local label = format(title and L.LEVEL_TITLE_FMT or L.LEVEL_SHORT_FMT, level)
  local value = pct or (isCap and (title and L.LEVEL_CAP_TAG_TITLE or L.LEVEL_CAP_TAG)) or nil
  local text, vt, wl, wv = nil, nil, 0, 0
  if sp.on then
    text = Skin.Sub("level", label)
    wl = Skin.Measure("level", text)
    if value then
      vt = Skin.Sub("levelValue", value)
      wv = Skin.Measure("levelValue", vt)
      if wl + sp.gap + wv > lineW then vt = nil end
    end
    wBL = vt and (wl + sp.gap + wv) or wl
  else
    if value then
      if title then
        text = label .. L.SEP .. value              -- only when the level key changes
      elseif pct then
        text = format(L.LEVEL_PCT_FMT, level, pct)
      else
        text = format(L.LEVEL_CAP_FMT, level)
      end
      text = Skin.Sub("level", text)
      wBL = Skin.Measure("level", text)
      -- narrow bar, big font: the level alone rather than a text running past the edge
      if wBL > lineW then text = nil end
    end
    if text == nil then
      text = Skin.Sub("level", label)
      wBL = Skin.Measure("level", text)
    end
  end
  if text ~= sp.blText then
    sp.blText = text
    bl:SetText(text)
  end
  local blv = sp.blv
  if not blv then return end
  if vt then
    if vt ~= sp.blvText then
      sp.blvText = vt
      blv:SetText(vt)
    end
    local x = math_floor(pad + wl + sp.gap + 0.5)
    if x ~= sp.blvX then
      sp.blvX = x
      blv:ClearAllPoints()
      blv:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, pad)
    end
  end
  local on = vt ~= nil
  if on ~= sp.blvOn then
    sp.blvOn = on
    if on then blv:Show() else blv:Hide() end
  end
end

-- XP text variants, left of slot 2: 1 = "XP: 1,234 / 5,678", 2 = compact numbers,
-- 3 = compact numbers without the label (split themes: the label is its own text, xpW
-- the width of label + gap + value). None at max level / before the first valid read.
local function XPTexts(show, xp, max)
  local valW = sp.valW
  if not show then
    xpText[1], xpText[2], xpText[3] = nil, nil, nil
    xpW[1], xpW[2], xpW[3] = 0, 0, 0
    valW[1], valW[2], valW[3] = 0, 0, 0
    return
  end
  local cx, cm = Compact(xp), Compact(max)
  if sp.on then
    local full = Skin.Sub("xp", format(L.XP_BARE_FMT, Fmt.Number(xp), Fmt.Number(max)))
    local short = Skin.Sub("xp", format(L.XP_BARE_FMT, cx, cm))
    xpText[1], xpText[2], xpText[3] = full, short, short
    valW[1] = Skin.Measure("xp", full)
    valW[2] = Skin.Measure("xp", short)
    valW[3] = valW[2]
    local lw = sp.wXPL + sp.gap
    xpW[1], xpW[2], xpW[3] = lw + valW[1], lw + valW[2], valW[2]
  else
    xpText[1] = Skin.Sub("xp", format(L.XP_FMT, Fmt.Number(xp), Fmt.Number(max)))
    xpText[2] = Skin.Sub("xp", format(L.XP_FMT, cx, cm))
    xpText[3] = Skin.Sub("xp", format(L.XP_BARE_FMT, cx, cm))
    for i = 1, 3 do
      local w = Skin.Measure("xp", xpText[i])
      xpW[i], valW[i] = w, w
    end
  end
end

---------------------------------------------------------------------------
-- Public: XP visuals
---------------------------------------------------------------------------

function Bar.UpdateXP()
  if not frame then return end
  local T = ns.Tracker
  local level, xp, max, rested, valid
  if T and T.GetXPInfo then
    level, xp, max, rested, valid = T.GetXPInfo()
  end
  local isMax = IsMax()
  drawnMax = isMax
  local isCap = isMax and IsServerCap()
  if type(level) ~= "number" then
    level = (ns.char and ns.char.level) or UnitLevel("player") or 1
  end
  level = math_floor(level)
  valid = (valid and type(xp) == "number" and type(max) == "number" and max > 0) and true or false
  xpPending = (not valid) and not isMax
  local showXP = valid and not isMax

  -- fill + rested (integer pixels, redrawn only on change)
  local pct, rfrac, E = 0, 0, 0
  if showXP then
    pct = xp / max
    if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
    E = (type(rested) == "number" and rested > 0) and rested or 0
    if E > 0 then rfrac = math_min(xp + E, max) / max end
  end
  -- fill state of the game's bar: rested colour while rested; max level: full width, dimmed
  local fk = isMax and 2 or ((E > 0) and 1 or 0)
  if fk ~= fillKey then
    fillKey = fk
    Skin.SetState(fk)
    fillPx = -1                                    -- end-of-fill layers follow the state
  end
  local px = 0
  if isMax then
    px = lineW
  elseif showXP then
    px = math_floor(lineW * pct + 0.5)
  end
  local rpx = (rfrac > 0) and math_floor(lineW * rfrac + 0.5) or 0
  if px ~= fillPx or rpx ~= restPx then
    if px ~= fillPx then markerDirty = true end
    fillPx, restPx = px, rpx
    Skin.Draw(px, rpx)
  end

  local Tokens = ns.Tokens

  -- bottom-left: level (and the % with one decimal when pctPos = "level"; "CAP" at a
  -- detected server level cap)
  local tenths = showXP and Tokens.PercentTenths(xp, max) or 0
  local withPct = usePctLevel and showXP
  local key = level * 10000 + (withPct and (tenths + 1) or 0)
  if isCap then key = -1 - level end
  if key ~= blKey then
    blKey = key
    LevelText(level, withPct and Tokens.PercentText(tenths) or nil, isCap)
    bottomDirty = true
  end

  -- XP text variants, left of slot 2 (none at max level / before the first valid read)
  local xkey = showXP and (xp * 1000003 + max) or -2
  if xkey ~= brxKey then
    brxKey = xkey
    XPTexts(showXP, xp, max)
    bottomDirty = true
  end

  -- % marker following the fill (shown by PlaceMarker when it has room)
  local wantMarker = usePctMarker and showXP
  if wantMarker ~= markerShown then
    markerShown = wantMarker
    if not wantMarker then SetMarkerVisible(false) end
    markerDirty = true
  end
  if wantMarker and tenths ~= pctKey then
    pctKey = tenths
    local text = Skin.Sub("marker", Tokens.PercentText(tenths))
    marker:SetText(text)
    wMarker = Skin.Measure("marker", text)
    markerDirty = true
  end
  if bottomDirty then LayoutBottom() end
  if markerDirty then PlaceMarker() end
end

---------------------------------------------------------------------------
-- Public: slot texts (TICK path - allocation free)
---------------------------------------------------------------------------

function Bar.Refresh()
  if not frame or not active then return end
  local Tokens = ns.Tokens
  for i = 1, NSLOTS do
    local id = Tokens.Resolve(i)
    local text, dim, paused, alt = Tokens.Render(id)
    if text == nil then text = EMPTY end
    if id ~= lastId[i] then
      lastId[i] = id
      hitWant[i] = Tokens.IsNetToken(id)
      ApplyHit(i)
    end
    -- FPS / latency in the text colour instead of green / yellow / red
    if hitWant[i] and not qualityOn then text = Tokens.Plain(text) end
    if text ~= lastText[i] or alt ~= lastAlt[i] then
      lastText[i], lastAlt[i] = text, alt
      slotW[i] = SlotWidth(i, text)
      slotWAlt[i] = (alt ~= nil) and SlotWidth(i, alt) or 0
      if i == 2 then bottomDirty = true else topDirty = true end
    end
    dim = (dim or paused) and true or false
    if dim ~= lastDim[i] then
      lastDim[i] = dim
      SetColor(slotFS[i], dim and dimColor or slotColor[i])
    end
    paused = paused and true or false
    if paused ~= lastPaused[i] then
      lastPaused[i] = paused
      ApplyMark(i)
      if i == 2 then bottomDirty = true else topDirty = true end
    end
  end
  if bottomDirty then LayoutBottom() end
  if topDirty then LayoutTop() end
  if markerDirty then PlaceMarker() end
end

---------------------------------------------------------------------------
-- Public: layout
---------------------------------------------------------------------------

-- Text anchors, measures and caches start over (new theme, fonts or sizes).
local function ResetTextLayout()
  local s1, s2, s3 = slotFS[1], slotFS[2], slotFS[3]
  s1:ClearAllPoints(); s2:ClearAllPoints(); s3:ClearAllPoints()
  -- every slot drawn until the bar layout decides otherwise
  for i = 1, NSLOTS do SetDrawn(i, true) end
  Skin.SetMeterFonts(fontSize, outline)
  brxX, sepX, s3X, s1Bound, brxCur = false, false, false, -1, nil
  sp.blvX, sp.xplX = false, false
  sepFS:Hide()
  sepShown = false
end

-- Split texts of the theme (2.5): blv / xpl are created at the first split build and
-- hidden whenever the theme does not draw them.
local function SetupSplit()
  local text = th.text
  sp.on = text.split and true or false
  sp.gap = text.splitGap or 4
  sp.title = text.levelFmt == "title"
  if sp.on and not sp.blv then
    local blv, xpl = NewFontString("OVERLAY"), NewFontString("OVERLAY")
    blv:Hide(); xpl:Hide()
    sp.blv, sp.xpl = blv, xpl
    allTexts[#allTexts + 1] = blv
    allTexts[#allTexts + 1] = xpl
    frame.tp.blv, frame.tp.xpl = blv, xpl
  end
end

local function HideSplit()
  if sp.blvOn then
    sp.blvOn = false
    sp.blv:Hide()
  end
  if sp.xplOn then
    sp.xplOn = false
    sp.xpl:Hide()
  end
end

-- The bar (the mockup): sizes, fonts and fixed anchors (SPEC-themes 2.4 geometry: the
-- theme's padding, gaps and track height, rows sized by the theme's fonts). The right part
-- of each row is placed by LayoutBottom / LayoutTop from the measured texts. Returns the
-- frame size.
local function ApplyBarStyle(w)
  local s1, s2, s3 = slotFS[1], slotFS[2], slotFS[3]
  local bar, size = th.bar, th.text.size
  pad = bar.pad or 8
  local gap = bar.gap or 3
  local W = math_floor(Clamp(w.width, 150, 600, 360))
  local H = math_max(bar.hMin or 4, math_floor(Clamp(w.height, 4, 16, 8)) + (bar.hAdd or 0))
  local topRow = math_max(ElemFont(s1, "s1", size.s1), ElemFont(s3, "s3", size.s3)) + 2
  local bottomRow = math_max(ElemFont(bl, "level", size.level), ElemFont(brx, "xp", size.xp),
    ElemFont(s2, "s2", size.s2))
  if sp.on then
    bottomRow = math_max(bottomRow, ElemFont(sp.blv, "levelValue", size.levelValue),
      ElemFont(sp.xpl, "xpLabel", size.xpLabel))
  else
    HideSplit()
  end
  bottomRow = bottomRow + 2
  local trackY = pad + bottomRow + gap
  topY = trackY + H + gap
  local fw, fh = W + 2 * pad, pad + topRow + gap + H + gap + bottomRow + pad
  frame:SetSize(fw, fh)
  ox, oy, lineW, lineH = pad, trackY, W, H

  -- slot 1: top right
  s1:SetJustifyH("RIGHT")
  s1:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", pad + W, topY)
  AnchorMark(1, "left")
  -- slot 2: bottom right (after the XP text)
  s2:SetJustifyH("RIGHT")
  s2:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", pad + W, pad)
  AnchorMark(2, "left")
  -- slot 3: top centre (mockup) or top left
  slot3Left = (w.slot3Pos == "left")
  if slot3Left then
    s3:SetJustifyH("LEFT")
    s3:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, topY)
    AnchorMark(3, "right")
  else
    s3:SetJustifyH("CENTER")
    s3X = pad + math_floor(W / 2)
    s3:SetPoint("BOTTOM", frame, "BOTTOMLEFT", s3X, topY)
    AnchorMark(3, "left")
  end

  -- bottom row texts (the XP text and the separator are placed by LayoutBottom)
  bl:ClearAllPoints()
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", pad, pad)
  bl:Show()
  brx:ClearAllPoints()
  brx:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", pad + W, pad)
  brx:Show()
  brxShown = true
  ElemFont(sepFS, "sep", size.sep)
  -- "·" between the XP text and slot 2: L.SEP without its spaces, read here (the
  -- language is applied into L after the files load)
  local st = strtrim(L.SEP or "")
  if st == "" then st = "\194\183" end
  st = Skin.Sub("sep", st)
  sepFS:SetText(st)
  wSep = Skin.Measure("sep", st)
  ElemFont(marker, "marker", size.marker)
  usePctMarker = (w.pctPos ~= "level")
  usePctLevel = not usePctMarker
  if sp.on then
    local xl = Skin.Sub("xpLabel", L.XP_LABEL)
    sp.xpl:SetText(xl)
    sp.wXPL = Skin.Measure("xpLabel", xl)
  end
  -- widths of the current slot texts (and short forms) in the new fonts
  for i = 1, NSLOTS do
    local t, a = lastText[i], lastAlt[i]
    slotW[i] = (t ~= nil and t ~= EMPTY) and SlotWidth(i, t) or 0
    slotWAlt[i] = (a ~= nil) and SlotWidth(i, a) or 0
  end
  topDirty, bottomDirty = true, true
  return fw, fh
end

function Bar.ApplyLayout()
  if not frame then return end
  local w = Widget()
  if not w then return end
  local t = Themes.Active()
  -- stored XP / rested colours changed without a SETTINGS_CHANGED (settings table
  -- replaced, DB_SWAPPED): Themes recolours, THEME_CHANGED "colors" follows (K12)
  if Skin.SyncUserColors(w) and t == th and skinGen ~= false then Themes.Recolor() end

  local rebuild = skinGen == false or t ~= th
  th = t
  fontSize = math_floor(Clamp(w.fontSize, 9, 16, 11))
  frame:SetScale(Clamp(w.scale, 0.5, 2.0, 1.0))
  ReadTextStyle(w)
  if rebuild then
    Skin.Build(t)                                -- regions of the theme's layers and panel
    SetupSplit()
    ApplyVeil()
  elseif t.gen ~= skinGen then
    Skin.Recolor()                               -- colours rewritten in place (gen + 1)
    ApplyVeil()
  end
  skinGen = t.gen
  for i = 1, #allTexts do ApplyShadow(allTexts[i]) end

  ResetTextLayout()
  local fw, fh = ApplyBarStyle(w)
  ApplyBackground(w, fw, fh)
  Skin.Layout(ox, oy, lineW, lineH)              -- static layers placed

  ElemFont(hint, "hint", math_max(9, fontSize + (th.text.size.hint or -1)) - fontSize)
  hint:SetText(Skin.Sub("hint", L.UNLOCKED_HINT))
  ApplyTextColors()

  -- force every cached visual to be redrawn once
  fillPx, restPx, blKey, brxKey, pctKey, fillKey = -1, -1, -1, -1, -1, -1
  marker:Hide()
  markerShown, markerVisible, markerX, markerDirty = false, false, false, true

  ApplyPosition()
  ApplyLock()
  ApplyAlpha()
  Bar.UpdateXP()
  Bar.Refresh()
end

-- THEME_CHANGED (SPEC-themes S7): "colors" recolours the skin and the texts in place (no
-- geometry work); a new theme rebuilds the widget.
local function OnThemeChanged(_, _, _, kind)
  if not frame then return end
  local t = Themes.Active()
  if kind == "colors" and t == th and skinGen ~= false then
    skinGen = t.gen
    local w = Widget()
    if w then
      Skin.SyncUserColors(w)
      ReadTextStyle(w)
    end
    Skin.Recolor()                               -- layers and panel, current fill state
    ApplyVeil()
    ApplyTextColors()
    Bar.Refresh()
    return
  end
  Bar.ApplyLayout()
end

---------------------------------------------------------------------------
-- Frame scripts (created once)
---------------------------------------------------------------------------

local function ShowTooltip(self)
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.ShowFor then Tooltip.ShowFor(self) end
end

local function HideTooltip(self)
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.Hide then Tooltip.Hide(self) end
end

local function HideGraph(owner)
  local Graph = ns.Graph
  if Graph and Graph.Hide then Graph.Hide(owner) end
end

local function OnEnter(self)
  hovered = true
  ApplyAlpha()
  if not dragging then ShowTooltip(self) end
end

local function OnLeave(self)
  hovered = false
  ApplyAlpha()
  HideTooltip(self)
end

-- Ends a drag once, whichever of OnDragStop / OnMouseUp the game sends first: stops
-- the move and stores the rounded position. Returns true when a drag was ended.
local function EndDrag(self)
  self:StopMovingOrSizing()
  if not dragging then return false end
  dragging = false
  local point, _, rel, x, y = self:GetPoint(1)
  if type(point) == "string" then
    ns.Core.SetSetting("widget.point", {
      point, (type(rel) == "string") and rel or point,
      Util.Round(tonumber(x) or 0), Util.Round(tonumber(y) or 0),
    })
  end
  ApplyPosition()   -- re-anchor to UIParent with the rounded values
  return true
end

local function OnMouseDown()
  dragging, dropped = false, false
end

local function OnMouseUp(self, button)
  if EndDrag(self) or dropped then
    dropped = false           -- the release that ends a drag is not a click
    return
  end
  if button == "RightButton" then
    if ns.Options and ns.Options.ShowContextMenu then ns.Options.ShowContextMenu(self) end
  elseif button == "LeftButton" then
    if ns.Window and ns.Window.Toggle then ns.Window.Toggle() end
  end
end

local function OnDragStart(self)
  local w = Widget()
  if not w or w.locked then return end
  dragging = true
  HideTooltip(self)
  HideGraph()
  self:StartMoving()
end

local function OnDragStop(self)
  if EndDrag(self) then dropped = true end   -- its mouse-up may still come: not a click
end

local function OnHide(self)
  hovered = false
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.IsShownFor and Tooltip.IsShownFor(self) then Tooltip.Hide(self) end
  HideGraph()
end

-- Hover regions over the FPS / latency texts: the history graph instead of the tooltip
-- (never both); clicks and drags act on the widget.
local NewHit
do
  local function HitEnter(self)
    hovered = true
    ApplyAlpha()
    if dragging then return end
    HideTooltip(frame)
    local Graph = ns.Graph
    if Graph and Graph.ShowFor then Graph.ShowFor(self) end
  end

  local function HitLeave(self)
    hovered = false
    ApplyAlpha()
    local Graph = ns.Graph
    if Graph and Graph.LeaveAnchor then Graph.LeaveAnchor(self) end
  end

  local function HitMouseDown(_, button)
    OnMouseDown(frame, button)
  end

  local function HitMouseUp(_, button)
    OnMouseUp(frame, button)
  end

  local function HitDragStart()
    OnDragStart(frame)
  end

  local function HitDragStop()
    OnDragStop(frame)
  end

  local function HitHide(self)
    HideGraph(self)
  end

  NewHit = function(i)
    local h = CreateFrame("Frame", nil, frame)
    h:SetAllPoints(slotFS[i])
    h:EnableMouse(true)
    h:RegisterForDrag("LeftButton")
    h:SetScript("OnEnter", HitEnter)
    h:SetScript("OnLeave", HitLeave)
    h:SetScript("OnMouseDown", HitMouseDown)
    h:SetScript("OnMouseUp", HitMouseUp)
    h:SetScript("OnDragStart", HitDragStart)
    h:SetScript("OnDragStop", HitDragStop)
    h:SetScript("OnHide", HitHide)
    hit[i] = h
    return h
  end
end

-- Region of slot i: shown while the widget is active and the slot draws an FPS /
-- latency token (created on first need, Show/Hide on change only).
ApplyHit = function(i)
  local want = (active and hitWant[i] and slotDrawn[i] ~= false) and true or false
  if want == (hitOn[i] == true) then return end
  hitOn[i] = want
  local h = hit[i]
  if want then
    if not h then h = NewHit(i) end
    h:Show()
  elseif h then
    h:Hide()
  end
end

---------------------------------------------------------------------------
-- Creation (lazy: only when the widget has to be shown)
---------------------------------------------------------------------------

local function CreateWidget()
  frame = CreateFrame("Frame", "TruePlayedWidget", UIParent, "BackdropTemplate")
  Bar.frame = frame
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  th = Themes.Active()
  local w = Widget()
  if w then ReadTextStyle(w) end

  -- the progress line and the panel are BarSkin's (built by ApplyLayout); the veil is ours
  local veil = frame:CreateTexture(nil, "OVERLAY", nil, 7)
  veil:SetTexture(C.TEX_WHITE)
  veil:SetAllPoints(frame)
  tex.veil = veil

  for i = 1, NSLOTS do
    slotFS[i] = NewFontString("OVERLAY")
    slotMark[i] = NewPauseMark()
    lastText[i], lastDim[i], lastPaused[i] = nil, nil, false
    slotDrawn[i], markOn[i] = true, false
    allTexts[#allTexts + 1] = slotFS[i]
  end
  bl = NewFontString("OVERLAY")
  brx = NewFontString("OVERLAY")
  sepFS = NewFontString("OVERLAY")
  marker = NewFontString("OVERLAY")
  marker:Hide()
  sepFS:Hide()

  hint = NewFontString("OVERLAY")
  hint:SetPoint("BOTTOM", frame, "TOP", 0, 2)
  hint:SetText(L.UNLOCKED_HINT)
  allTexts[#allTexts + 1] = bl
  allTexts[#allTexts + 1] = brx
  allTexts[#allTexts + 1] = sepFS
  allTexts[#allTexts + 1] = marker
  allTexts[#allTexts + 1] = hint

  frame:SetScript("OnEnter", OnEnter)
  frame:SetScript("OnLeave", OnLeave)
  frame:SetScript("OnMouseDown", OnMouseDown)
  frame:SetScript("OnMouseUp", OnMouseUp)
  frame:SetScript("OnDragStart", OnDragStart)
  frame:SetScript("OnDragStop", OnDragStop)
  frame:SetScript("OnHide", OnHide)

  -- Read-only handles for the offline tests (our own frame); blv / xpl come with the
  -- first split theme.
  local panel = {}
  frame.tp = { slots = slotFS, marks = slotMark, bl = bl, brx = brx, sep = sepFS, marker = marker,
               hint = hint, tex = tex, panel = panel, hits = hit }
  -- text measuring (never seen: alpha 0); measuring a slot that the layout hides would
  -- otherwise depend on the width a hidden FontString reports. BarSkin keeps one per
  -- font and size of the theme's texts.
  Skin.Init(frame, tex, panel, function()
    local m = NewFontString("BACKGROUND")
    m:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    m:SetAlpha(0)
    return m
  end)

  Bar.ApplyLayout()
end

---------------------------------------------------------------------------
-- Activation / visibility
---------------------------------------------------------------------------

local UpdateVisibility   -- forward declaration

-- Max level (or a server level cap) reached or left without an XP message (the cap is
-- detected after a fight): visibility (hideAtMax) and the XP visuals follow at the next
-- tick. One boolean compare per tick otherwise.
local function OnTick()
  if IsMax() ~= drawnMax then
    if not UpdateVisibility() then return end
    Bar.UpdateXP()
  elseif xpPending then
    Bar.UpdateXP()
  end
  Bar.Refresh()
end

local function OnRefreshMsg()
  Bar.Refresh()
end

local function OnDataReset()
  Bar.UpdateXP()
  Bar.Refresh()
end

local function SetActive(on)
  if on == active then return end
  active = on
  local Tokens = ns.Tokens
  if on then
    ns.RegisterMessage("TICK", Bar, OnTick)
    ns.RegisterMessage("STATE_CHANGED", Bar, OnRefreshMsg)
    ns.RegisterMessage("SESSION_RESET", Bar, OnRefreshMsg)
    ns.RegisterMessage("PLAYED_SYNCED", Bar, OnRefreshMsg)
    ns.RegisterMessage("CHAR_RESET", Bar, OnDataReset)
    Tokens.Acquire("bar", NSLOTS)          -- also refreshes the token context
    Bar.UpdateXP()
    Bar.Refresh()
    for i = 1, NSLOTS do ApplyHit(i) end
  else
    ns.UnregisterMessage("TICK", Bar)
    ns.UnregisterMessage("STATE_CHANGED", Bar)
    ns.UnregisterMessage("SESSION_RESET", Bar)
    ns.UnregisterMessage("PLAYED_SYNCED", Bar)
    ns.UnregisterMessage("CHAR_RESET", Bar)
    Tokens.Release("bar")
    for i = 1, NSLOTS do ApplyHit(i) end
    if frame then OnHide(frame) end
  end
end

local function OnXPMsg()
  if UpdateVisibility() then
    Bar.UpdateXP()
    Bar.Refresh()
  end
end

local function SetWatching(on)
  if on == watching then return end
  watching = on
  if on then
    ns.RegisterMessage("XP_CHANGED", Bar, OnXPMsg)
    ns.RegisterMessage("LEVEL_UP", Bar, OnXPMsg)
  else
    ns.UnregisterMessage("XP_CHANGED", Bar)
    ns.UnregisterMessage("LEVEL_UP", Bar)
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
    ns.RegisterEvent("PLAYER_REGEN_DISABLED", Bar, OnRegenDisabled)
    ns.RegisterEvent("PLAYER_REGEN_ENABLED", Bar, OnRegenEnabled)
  else
    ns.UnregisterEvent("PLAYER_REGEN_DISABLED", Bar)
    ns.UnregisterEvent("PLAYER_REGEN_ENABLED", Bar)
    inCombat = false
  end
end

-- Applies widget.shown / hideAtMax / combatHide. Returns true when active.
UpdateVisibility = function()
  local w = Widget()
  if not w then return false end
  local shown = w.shown and true or false
  SetWatching(shown)
  SetRegenEvents(shown and w.combatHide and true or false)
  -- hideAtMax: the real max level only (a server level cap is temporary)
  local want = shown and not (w.hideAtMax and IsMax() and not IsServerCap())
  if want and not frame then CreateWidget() end
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
-- Messages kept while initialised (rare: needed to come back when shown again)
---------------------------------------------------------------------------

local function OnSettingsChanged(_, path)
  if VISIBILITY_PATHS[path] then
    UpdateVisibility()
    return
  end
  if not frame then return end
  if path == "theme" or (type(path) == "string" and (path:find("widget.xpColor", 1, true) == 1
      or path:find("widget.restedColor", 1, true) == 1)) then
    return                                         -- Themes' (S8): THEME_CHANGED follows
  end
  if LAYOUT_PATHS[path] then
    Bar.ApplyLayout()
  elseif STYLE_PATHS[path] or (type(path) == "string" and path:find("widget.textColor.", 1, true) == 1) then
    local w = Widget()
    if w then ReadTextStyle(w) end
    ApplyTextColors()
    Bar.Refresh()
  elseif path == "widget.locked" then
    ApplyLock()
  elseif path == "widget.point" then
    ApplyPosition()
  elseif path == "widget.fade" then
    ApplyAlpha()
  else
    Bar.Refresh()        -- exclusions, slots, max slots, rateTau...
  end
end

local function OnDBSwapped()
  UpdateVisibility()
  if frame then Bar.ApplyLayout() end
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Bar.Init()
  if inited then return end
  inited = true
  ns.RegisterMessage("SETTINGS_CHANGED", Bar, OnSettingsChanged)
  ns.RegisterMessage("DB_SWAPPED", Bar, OnDBSwapped)
  ns.RegisterMessage("THEME_CHANGED", Bar, OnThemeChanged)
  UpdateVisibility()
end

function Bar.OnDBReady()
  Bar.Init()
end

function Bar.SetLocked(locked)
  ns.Core.SetSetting("widget.locked", locked and true or false)
  ApplyLock()
end

function Bar.SetShown(shown)
  ns.Core.SetSetting("widget.shown", shown and true or false)
  if inited then UpdateVisibility() end
end

function Bar.ResetPosition()
  ns.Core.SetSetting("widget.point", Util.DeepCopy(C.DEFAULTS.widget.point))
  ApplyPosition()
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", Bar, Bar.OnDBReady)
end
