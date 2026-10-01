local ADDON, ns = ...
local L, C, Util, Fmt = ns.L, ns.C, ns.Util, ns.Fmt

-- Bar.lua - the on-screen widget (style "bar" = the mockup, style "box" = compact).
--
-- Performance contract (SPEC 6):
--   * no per-frame script; the widget listens to TICK only while it is visible and active;
--   * Refresh() allocates nothing when no displayed text changed and calls SetText
--     only when a slot string changed (token strings are cached by Tokens);
--   * XP visuals (fill, rested, level/XP texts, % marker) change only on XP_CHANGED,
--     LEVEL_UP, DB_SWAPPED, CHAR_RESET or a layout change, and every draw call is
--     skipped when the integer pixel value did not change;
--   * like the game's own XP bar, the fill is blue while rested XP is left
--     (GetXPExhaustion() > 0) and purple otherwise; the rested part (current XP to
--     current XP + rested, capped at the level end) is a lighter blue fading out. The
--     colours change only when that state changes (XP / exhaustion / level events).
--     widget.xpColor / widget.restedColor ({ r, g, b } or false = those built-in
--     colours) replace the purple and the blue; the rested part and its end tick are
--     then lighter shades of the rested colour;
--   * bar style, bottom row "LEVEL 20   0.3%        XP: 58 / 23,200 · ~4.5k/h": the right
--     part (XP text, separator, pause mark, slot 2) never reaches the level text. Text
--     widths are measured (GetStringWidth on hidden-proof "meter" FontStrings) only
--     when a text changes, then the right part degrades in steps until it fits: short
--     numbers (58 / 23.2k), no "XP:" label, slot 2 in its short form (a token with
--     one, e.g. eta_kills -> the ETA alone), no slot 2, and at last slot 2 alone or
--     nothing. The % marker (one decimal, like the tooltip) only takes the space left;
--     with pctPos = "level", a level text wider than the bar drops its percent;
--   * bar style, top row: slot 1 (top right, with its pause mark) is bounded to the
--     inner width; slot 3 (top centre or left) is shifted away from slot 1. A token
--     with a short form uses it (slot 1 first) rather than leaving slot 3 out; slot 3 is
--     hidden only when it cannot be drawn clear of slot 1 even then;
--   * texts: one colour for every text when widget.textColor is set (else the built-in
--     white / grey), outline (none / thin / thick) and drop shadow; FPS / latency keep
--     their green / yellow / red numbers unless widget.qualityColors is off;
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
local type, tonumber, pcall = type, tonumber, pcall
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
local PAD          = 8      -- bar style inner padding
local BOX_PAD      = 6      -- box style inner padding
local BOX_WIDTH    = 180    -- box style fixed width (scale applies)
local BOX_LINE     = 2      -- box style progress line height
local BOX_GAP      = 8      -- box style gap between slot 2 and slot 3
local SEP_GAP      = 4      -- gap on each side of the separator between the XP text and slot 2
local MARKER_GAP   = 6      -- min gap between the % marker and its neighbours
local EDGE_GAP     = 6      -- min gap between the level text and the right part of the bottom row
local TOP_GAP      = 8      -- min gap between slot 3 and slot 1 (top row)
local MARK_W       = 7      -- pause mark width
local MARK_GAP     = 3      -- gap between a pause mark and its slot text
local MARK_SPACE   = MARK_W + MARK_GAP
local BOX_S1_W     = BOX_WIDTH - 2 * BOX_PAD - MARK_SPACE          -- box style slot 1 width
local BOX_HALF     = math_floor((BOX_WIDTH - 2 * BOX_PAD - BOX_GAP) / 2)   -- box style slots 2 / 3
local FADE_ALPHA   = 0.35
local MAX_FILL_ALPHA = 0.35 -- fill alpha at max level
local VEIL_ALPHA   = 0.20
local EMPTY        = ""
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local SEP_TEXT     = strtrim(L.SEP or "")      -- "·" between the XP text and slot 2
if SEP_TEXT == "" then SEP_TEXT = "\194\183" end
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
  ["widget.style"] = true, ["widget.scale"] = true, ["widget.width"] = true,
  ["widget.height"] = true, ["widget.fontSize"] = true, ["widget.background"] = true,
  ["widget.bgAlpha"] = true, ["widget.outline"] = true, ["widget.shadow"] = true,
  ["widget.slot3Pos"] = true, ["widget.pctPos"] = true,
}
local STYLE_PATHS = {                         -- colours only: no new measures
  ["widget.textColor"] = true, ["widget.qualityColors"] = true,
}
local BAR_COLOR_PATHS = {                     -- fill / rested colours: no text work
  ["widget.xpColor"] = true, ["widget.restedColor"] = true,
}

---------------------------------------------------------------------------
-- State (module-private)
---------------------------------------------------------------------------

local frame                      -- the widget (== Bar.frame once created)
local rounded = false            -- CreateMaskTexture available: rounded track ends
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
local useAlt = {}                -- [i] the short form is drawn
local shownText = {}             -- [i] text currently set on the slot FontString
local lastId = {}                -- [i] token id resolved for the slot
local slotColor = {}             -- [i] colour table used when the slot is not dim
local slotDrawn = {}             -- [i] false while the layout leaves the slot out (no room)
local markOn = {}                -- [i] pause mark drawn
local hit, hitWant, hitOn = {}, {}, {}   -- [i] graph hover region over an FPS / latency slot
local tex = {}                   -- named textures
local bl, brx, sepFS, marker, hint
local meterS, meterM, meterL     -- invisible FontStrings used to measure texts (font - 1, font, font + 2)
local allTexts = {}              -- every visible FontString (outline, shadow)

-- applied layout
local style = "bar"
local ox, oy, lineW, lineH = PAD, 0, 300, 8   -- progress line origin and size
local topY = 0                   -- bottom of the top row (bar style)
local capsOn = false
local usePctMarker, usePctLevel = false, false
local slot3Left = false
local fontSize = 11

-- text style (widget.outline / shadow / textColor / qualityColors)
local fontFlags = "OUTLINE"
local shadowOn = true
local qualityOn = true
local customOn = false
local customRGB = { 1, 1, 1 }
local dimColor = C.COLORS.dim

-- measured widths (bar style; refreshed only when the measured text changes)
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
local fillKey = -1               -- fill colour state: 0 normal, 1 rested, 2 max level
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

local function SetFontSize(fs, size)
  fs:SetFont(STANDARD_TEXT_FONT or DEFAULT_FONT, size, fontFlags)
end

local function ApplyShadow(fs)
  if shadowOn then
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
  else
    fs:SetShadowOffset(0, 0)
    fs:SetShadowColor(0, 0, 0, 0)
  end
end

local function NewFontString(layer)
  local fs = frame:CreateFontString(nil, layer or "OVERLAY")
  SetFontSize(fs, 11)
  fs:SetWordWrap(false)                 -- one line; a bounded width ends with "..."
  ApplyShadow(fs)
  fs:SetJustifyV("BOTTOM")
  return fs
end

local function NewTexture(layer, sublevel, color)
  local t = frame:CreateTexture(nil, layer, nil, sublevel)
  t:SetTexture(C.TEX_WHITE)
  t:SetVertexColor(color[1], color[2], color[3], color[4] or 1)
  return t
end

-- A square texture shown as a disc (circle mask) when masks are available.
local function NewCap(layer, sublevel, color)
  local t = NewTexture(layer, sublevel, color)
  if rounded then
    local m = frame:CreateMaskTexture()
    m:SetTexture(C.TEX_CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(t)
    t:AddMaskTexture(m)
  end
  return t
end

local function Place(t, x, y)
  t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)
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
  useAlt[i] = use
  local t = (use and lastAlt[i]) or lastText[i] or EMPTY
  if t ~= shownText[i] then
    shownText[i] = t
    slotFS[i]:SetText(t)
  end
end

-- Width of `text` in the font of `meter` (never shown to the player).
local function Measure(meter, text)
  meter:SetText(text)
  return meter:GetStringWidth() or 0
end

-- Meter in the font of slot i for the current style.
local function SlotMeter(i)
  if i == 1 then return meterL end
  if i == 2 and style == "bar" then return meterM end
  return meterS
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
  local OUTLINE_FLAGS = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
  local DEFAULT_FLAGS = "OUTLINE"                -- widget.outline = "thin"
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
    fontFlags = OUTLINE_FLAGS[w.outline] or DEFAULT_FLAGS
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
    dimColor = customOn and customDim or C.COLORS.dim
  end

  -- Dark background: widget.bgAlpha (0 = none); a record not migrated yet may still
  -- have the former on/off widget.background.
  ApplyBackground = function(w)
    if not frame.SetBackdrop then return end
    local a = tonumber(w.bgAlpha)
    if a == nil then a = (w.background == true) and LEGACY_BG_ALPHA or 0 end
    a = Unit(a)
    if a > 0 then
      frame:SetBackdrop(BACKDROP)
      local bg, bd = C.COLORS.bg, C.COLORS.border
      frame:SetBackdropColor(bg[1], bg[2], bg[3], a)
      frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], (bd[4] or 1) * math_min(1, a / LEGACY_BG_ALPHA))
    else
      frame:SetBackdrop(nil)
    end
  end
end

local function SetColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

-- Built-in colours (values white, labels grey) or the custom colour on every text.
local function ApplyTextColors()
  local COLORS = C.COLORS
  local lc = customOn and customRGB or COLORS.label
  local vc = customOn and customRGB or COLORS.value
  SetColor(bl, lc)
  SetColor(brx, lc)
  SetColor(sepFS, lc)
  SetColor(marker, lc)
  SetColor(hint, lc)
  slotColor[1] = vc
  if style == "bar" then slotColor[2] = vc else slotColor[2] = lc end
  slotColor[3] = lc
  for i = 1, NSLOTS do lastDim[i] = nil end    -- the next Refresh sets the slot colours
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
-- Progress line drawing (all values are integer pixels)
---------------------------------------------------------------------------

local function DrawTrack()
  local tL, tM, tR = tex.trackL, tex.trackM, tex.trackR
  if capsOn then
    local h2 = math_floor(lineH / 2)
    tL:SetSize(lineH, lineH); Place(tL, ox, oy); tL:Show()
    tR:SetSize(lineH, lineH); Place(tR, ox + lineW - lineH, oy); tR:Show()
    tM:SetSize(lineW - 2 * h2, lineH); Place(tM, ox + h2, oy); tM:Show()
  else
    tL:Hide(); tR:Hide()
    tM:SetSize(lineW, lineH); Place(tM, ox, oy); tM:Show()
  end
end

local function DrawFill(px)
  local fL, fM, fR, hi = tex.fillL, tex.fillM, tex.fillR, tex.fillHi
  if px <= 0 then
    fL:Hide(); fM:Hide(); fR:Hide(); hi:Hide()
    return
  end
  local hiX, hiW
  if capsOn and px >= lineH then
    local h2 = math_floor(lineH / 2)
    Place(fL, ox, oy); fL:Show()
    Place(fR, ox + px - lineH, oy); fR:Show()
    local mw = px - 2 * h2
    if mw > 0 then
      fM:SetWidth(mw); Place(fM, ox + h2, oy); fM:Show()
    else
      fM:Hide()
    end
    hiX, hiW = ox + h2, mw
  else
    fL:Hide(); fR:Hide()
    fM:SetWidth(px); Place(fM, ox, oy); fM:Show()
    hiX, hiW = ox, px
  end
  if style == "bar" and hiW > 0 then
    hi:SetWidth(hiW); Place(hi, hiX, oy + lineH - 1); hi:Show()
  else
    hi:Hide()
  end
end

local function DrawRested(px, rpx)
  local r, t = tex.rested, tex.restTick
  if rpx > px then
    r:SetWidth(rpx - px); Place(r, ox + px, oy); r:Show()
    Place(t, ox + rpx - 1, oy); t:Show()
  else
    r:Hide(); t:Hide()
  end
end

local ApplyFillColor, ReadBarColors
do
  -- The game's XP bar while rested (GetXPExhaustion() > 0); purple (C.COLORS.fill) otherwise.
  local RESTED_FILL  = C.COLORS.restedFill
  -- Rested part: the same blue, lighter, fading out towards current XP + rested.
  local REST_FROM_0  = { r = 0.35, g = 0.62, b = 1.0, a = 0.65 }
  local REST_TO_0    = { r = 0.35, g = 0.62, b = 1.0, a = 0.20 }
  local REST_FLAT_0  = { 0.35, 0.62, 1.0, 0.40 }  -- when the client has no usable gradient
  local REST_LIGHTEN = 0.35                       -- rested part: 35 % of the way to white
  local TICK_LIGHTEN = 0.6                        -- its end tick: 60 %
  Bar.DEFAULT_XP_COLOR = C.COLORS.fill            -- read-only: the options' swatches
  Bar.DEFAULT_RESTED_COLOR = RESTED_FILL

  -- colours in use (reused tables, rewritten only when a colour setting changes)
  local fillC   = { 0, 0, 0, 1 }                  -- fill while not rested (and at max level)
  local restC   = { 0, 0, 0, 1 }                  -- fill while rested
  local fromC   = { r = 0, g = 0, b = 0, a = REST_FROM_0.a }
  local toC     = { r = 0, g = 0, b = 0, a = REST_TO_0.a }
  local flatC   = { 0, 0, 0, REST_FLAT_0[4] }
  local tickC   = { 0, 0, 0, 1 }
  local xpKey, restKey = nil, nil                 -- colour settings read last time
  local restGradient = false                      -- rested overlay colours applied

  local function Unit(x)
    x = tonumber(x)
    if not x or x ~= x or x < 0 then return 0 end
    if x > 1 then return 1 end
    return x
  end

  -- { r, g, b } (an { r =, g =, b = } table too) or nil for false / invalid values.
  local function ReadRGB(v)
    if type(v) ~= "table" then return nil end
    local r, g, b = v[1], v[2], v[3]
    if r == nil and g == nil and b == nil then r, g, b = v.r, v.g, v.b end
    if not (tonumber(r) and tonumber(g) and tonumber(b)) then return nil end
    return Unit(r), Unit(g), Unit(b)
  end

  -- Integer key of a colour setting (-1 = built-in colours): change detection. Each
  -- component rounds to 0..1000 (1001 values): base 1001, so that no two colours share
  -- a key (base 1000 gave (0, 1, 0) and (0.001, 0, 0) the same one).
  local function ColorKey(r, g, b)
    if r == nil then return -1 end
    return (math_floor(r * 1000 + 0.5) * 1001 + math_floor(g * 1000 + 0.5)) * 1001
      + math_floor(b * 1000 + 0.5)
  end

  local function Set3(t, r, g, b)
    t[1], t[2], t[3] = r, g, b
  end

  local function Lighten(x, k)
    return x + (1 - x) * k
  end

  -- widget.xpColor / widget.restedColor: returns true when the colours in use changed
  -- (the next draw applies them: fill state and rested overlay forced).
  ReadBarColors = function(w)
    local xr, xg, xb = ReadRGB(w.xpColor)
    local rr, rg, rb = ReadRGB(w.restedColor)
    local xk, rk = ColorKey(xr, xg, xb), ColorKey(rr, rg, rb)
    if xk == xpKey and rk == restKey then return false end
    xpKey, restKey = xk, rk
    if xr then
      Set3(fillC, xr, xg, xb)
      fillC[4] = 1
    else
      local f = C.COLORS.fill
      Set3(fillC, f[1], f[2], f[3])
      fillC[4] = f[4] or 1
    end
    if rr then
      Set3(restC, rr, rg, rb)
      local lr, lg, lb = Lighten(rr, REST_LIGHTEN), Lighten(rg, REST_LIGHTEN), Lighten(rb, REST_LIGHTEN)
      fromC.r, fromC.g, fromC.b = lr, lg, lb
      toC.r, toC.g, toC.b = lr, lg, lb
      Set3(flatC, lr, lg, lb)
      Set3(tickC, Lighten(rr, TICK_LIGHTEN), Lighten(rg, TICK_LIGHTEN), Lighten(rb, TICK_LIGHTEN))
      tickC[4] = C.COLORS.restTick[4] or 1
    else
      Set3(restC, RESTED_FILL[1], RESTED_FILL[2], RESTED_FILL[3])
      fromC.r, fromC.g, fromC.b = REST_FROM_0.r, REST_FROM_0.g, REST_FROM_0.b
      toC.r, toC.g, toC.b = REST_TO_0.r, REST_TO_0.g, REST_TO_0.b
      Set3(flatC, REST_FLAT_0[1], REST_FLAT_0[2], REST_FLAT_0[3])
      local t = C.COLORS.restTick
      Set3(tickC, t[1], t[2], t[3])
      tickC[4] = t[4] or 1
    end
    restGradient = false
    fillKey = -1
    return true
  end

  -- Rested part: a horizontal gradient (Texture:SetGradient with colour tables, 10.0+
  -- API; SetGradientAlpha before that), else a flat lighter colour; its end tick
  -- lighter still. Applied the first time the character is rested, and again after a
  -- colour change.
  local function ApplyRestOverlay()
    restGradient = true
    tex.restTick:SetVertexColor(tickC[1], tickC[2], tickC[3], tickC[4])
    local t = tex.rested
    if t.SetGradient and pcall(t.SetGradient, t, "HORIZONTAL", fromC, toC) then return end
    local f, e = fromC, toC
    if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, "HORIZONTAL",
        f.r, f.g, f.b, f.a, e.r, e.g, e.b, e.a) then
      return
    end
    t:SetVertexColor(flatC[1], flatC[2], flatC[3], flatC[4])
  end

  -- Fill colour: 0 = XP colour (purple), 1 = rested colour (blue), 2 = max level
  -- (XP colour, dimmed).
  ApplyFillColor = function(key)
    local c = (key == 1) and restC or fillC
    local h = C.COLORS.fillHi
    local k = (key == 2) and MAX_FILL_ALPHA or 1
    local a = (c[4] or 1) * k
    tex.fillL:SetVertexColor(c[1], c[2], c[3], a)
    tex.fillM:SetVertexColor(c[1], c[2], c[3], a)
    tex.fillR:SetVertexColor(c[1], c[2], c[3], a)
    tex.fillHi:SetVertexColor(h[1], h[2], h[3], (h[4] or 1) * k)
    if key == 1 and not restGradient then ApplyRestOverlay() end
  end
end

---------------------------------------------------------------------------
-- Bar style layout of the text rows (widths measured on text changes only)
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
-- separator, XP text. It must stay EDGE_GAP px clear of the level text; it degrades
-- in steps until it does: short numbers, no "XP:" label, slot 2 in its short form, no
-- slot 2 (XP text alone), then slot 2 alone, then nothing.
local function LayoutBottom()
  bottomDirty = false
  markerDirty = true
  local right = PAD + lineW
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
      sepFS:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", sx, PAD)
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
      brx:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", bx, PAD)
    end
    x = x - xpW[v]
  elseif brxCur ~= EMPTY then
    brxCur = EMPTY                                 -- no stale XP text (max level)
    brx:SetText(EMPTY)
  end
  SetBrxShown(v > 0)
  clusterLeft = x
end

-- Slot 3 beside a slot 1 whose left edge (pause mark included) is at limit - TOP_GAP:
-- fits, and the centre x when slot 3 is centred (shifted left to stay clear).
local function PlaceSlot3(limit, w3, m3)
  if slot3Left then return PAD + w3 + m3 <= limit, nil end   -- anchored at PAD, mark on its right
  local cx = PAD + math_floor(lineW / 2)
  if cx + w3 / 2 > limit then cx = math_floor(limit - w3 / 2) end
  return cx - w3 / 2 - m3 >= PAD, cx               -- mark on its left
end

-- Top row: slot 1 at the right (with its pause mark on its left), bounded to the inner
-- width; slot 3 centred (shifted left when it would come closer than TOP_GAP px to
-- slot 1) or at the left. Short forms are used, slot 1 first, when both do not fit;
-- slot 3 is left out when it cannot be drawn clear of slot 1 even then.
local function LayoutTop()
  topDirty = false
  local right = PAD + lineW
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
  local left = PAD + wBL + MARKER_GAP
  local right = clusterLeft - MARKER_GAP
  if right - left < mW then
    SetMarkerVisible(false)                     -- no room: never drawn over a text
    return
  end
  SetMarkerVisible(true)
  local x = PAD + math_max(fillPx, 0) - mW / 2  -- centred on the fill end
  if x < left then
    x = left
  elseif x + mW > right then
    x = right - mW
  end
  x = math_floor(x + 0.5)
  if x ~= markerX then
    markerX = x
    marker:ClearAllPoints()
    marker:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, PAD)
  end
end

-- Box style: a slot whose token has a short form uses it when the full text is wider
-- than the slot.
local function ChooseBoxVariant(i)
  local use = false
  if lastAlt[i] ~= nil then
    local bound = (i == 1) and BOX_S1_W or BOX_HALF
    use = slotW[i] > bound
  end
  SetVariant(i, use)
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
  -- colours of the game's bar: blue while rested; max level: full width, dimmed
  local fk = isMax and 2 or ((E > 0) and 1 or 0)
  if fk ~= fillKey then
    fillKey = fk
    ApplyFillColor(fk)
  end
  local px = 0
  if isMax then
    px = lineW
  elseif showXP then
    px = math_floor(lineW * pct + 0.5)
  end
  local rpx = (rfrac > 0) and math_floor(lineW * rfrac + 0.5) or 0
  if px ~= fillPx then
    fillPx = px
    DrawFill(px)
    restPx = -1
    markerDirty = true
  end
  if rpx ~= restPx then
    restPx = rpx
    DrawRested(px, rpx)
  end

  if style ~= "bar" then return end
  local Tokens = ns.Tokens

  -- bottom-left: level (and the % with one decimal when pctPos = "level"; "CAP" at a
  -- detected server level cap)
  local tenths = showXP and Tokens.PercentTenths(xp, max) or 0
  local withPct = usePctLevel and showXP
  local key = level * 10000 + (withPct and (tenths + 1) or 0)
  if isCap then key = -1 - level end
  if key ~= blKey then
    blKey = key
    local text
    if withPct then
      text = format(L.LEVEL_PCT_FMT, level, Tokens.PercentText(tenths))
      wBL = Measure(meterM, text)
      -- narrow bar, big font: the level alone rather than a text running past the edge
      if wBL > lineW then text = nil end
    elseif isCap then
      text = format(L.LEVEL_CAP_FMT, level)
      wBL = Measure(meterM, text)
      if wBL > lineW then text = nil end
    end
    if text == nil then
      text = format(L.LEVEL_SHORT_FMT, level)
      wBL = Measure(meterM, text)
    end
    bl:SetText(text)
    bottomDirty = true
  end

  -- XP text variants, left of slot 2 (none at max level / before the first valid read)
  local xkey = showXP and (xp * 1000003 + max) or -2
  if xkey ~= brxKey then
    brxKey = xkey
    if showXP then
      local cx, cm = Compact(xp), Compact(max)
      xpText[1] = format(L.XP_FMT, Fmt.Number(xp), Fmt.Number(max))
      xpText[2] = format(L.XP_FMT, cx, cm)
      xpText[3] = format(L.XP_BARE_FMT, cx, cm)
      for i = 1, 3 do xpW[i] = Measure(meterM, xpText[i]) end
    else
      xpText[1], xpText[2], xpText[3] = nil, nil, nil
      xpW[1], xpW[2], xpW[3] = 0, 0, 0
    end
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
    local text = Tokens.PercentText(tenths)
    marker:SetText(text)
    wMarker = Measure(meterS, text)
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
  local isBar = style == "bar"
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
      if isBar or alt ~= nil then
        local meter = SlotMeter(i)
        slotW[i] = Measure(meter, text)
        slotWAlt[i] = (alt ~= nil) and Measure(meter, alt) or 0
      end
      if isBar then
        if i == 2 then bottomDirty = true else topDirty = true end
      else
        ChooseBoxVariant(i)
      end
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
      if isBar then
        if i == 2 then bottomDirty = true else topDirty = true end
      end
    end
  end
  if isBar then
    if bottomDirty then LayoutBottom() end
    if topDirty then LayoutTop() end
    if markerDirty then PlaceMarker() end
  end
end

---------------------------------------------------------------------------
-- Public: layout
---------------------------------------------------------------------------

-- Text anchors, measures and caches start over (new style, fonts or sizes).
local function ResetTextLayout()
  local s1, s2, s3 = slotFS[1], slotFS[2], slotFS[3]
  s1:ClearAllPoints(); s2:ClearAllPoints(); s3:ClearAllPoints()
  -- every slot drawn until the bar layout decides otherwise
  for i = 1, NSLOTS do SetDrawn(i, true) end
  SetFontSize(meterS, fontSize - 1)
  SetFontSize(meterM, fontSize)
  SetFontSize(meterL, fontSize + 2)
  brxX, sepX, s3X, s1Bound, brxCur = false, false, false, -1, nil
  sepFS:Hide()
  sepShown = false
end

-- Bar style (the mockup): sizes, fonts and fixed anchors. The right part of each row
-- is placed by LayoutBottom / LayoutTop from the measured texts.
local function ApplyBarStyle(w)
  local s1, s2, s3 = slotFS[1], slotFS[2], slotFS[3]
  local W = math_floor(Clamp(w.width, 150, 600, 360))
  local H = math_floor(Clamp(w.height, 4, 16, 8))
  local topRow, bottomRow = fontSize + 4, fontSize + 2
  local trackY = PAD + bottomRow + 3
  topY = trackY + H + 3
  frame:SetSize(W + 2 * PAD, PAD + topRow + 3 + H + 3 + bottomRow + PAD)
  ox, oy, lineW, lineH = PAD, trackY, W, H
  capsOn = rounded

  -- slot 1: top right, font + 2
  SetFontSize(s1, fontSize + 2)
  s1:SetJustifyH("RIGHT")
  s1:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PAD + W, topY)
  AnchorMark(1, "left")
  -- slot 2: bottom right (after the XP text)
  SetFontSize(s2, fontSize)
  s2:SetJustifyH("RIGHT")
  s2:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PAD + W, PAD)
  AnchorMark(2, "left")
  -- slot 3: top centre (mockup) or top left
  SetFontSize(s3, fontSize - 1)
  slot3Left = (w.slot3Pos == "left")
  if slot3Left then
    s3:SetJustifyH("LEFT")
    s3:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, topY)
    AnchorMark(3, "right")
  else
    s3:SetJustifyH("CENTER")
    s3X = PAD + math_floor(W / 2)
    s3:SetPoint("BOTTOM", frame, "BOTTOMLEFT", s3X, topY)
    AnchorMark(3, "left")
  end

  -- bottom row texts (the XP text and the separator are placed by LayoutBottom)
  SetFontSize(bl, fontSize)
  bl:ClearAllPoints()
  bl:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", PAD, PAD)
  bl:Show()
  SetFontSize(brx, fontSize)
  brx:ClearAllPoints()
  brx:SetPoint("BOTTOMRIGHT", frame, "BOTTOMLEFT", PAD + W, PAD)
  brx:Show()
  brxShown = true
  SetFontSize(sepFS, fontSize)
  sepFS:SetText(SEP_TEXT)
  wSep = Measure(meterM, SEP_TEXT)
  s1:SetWidth(0); s2:SetWidth(0); s3:SetWidth(0)   -- free widths (the box style bounds them)
  SetFontSize(marker, fontSize - 1)
  usePctMarker = (w.pctPos ~= "level")
  usePctLevel = not usePctMarker
  -- widths of the current slot texts (and short forms) in the new fonts
  for i = 1, NSLOTS do
    local t, a = lastText[i], lastAlt[i]
    slotW[i] = (t ~= nil and t ~= EMPTY) and Measure(SlotMeter(i), t) or 0
    slotWAlt[i] = (a ~= nil) and Measure(SlotMeter(i), a) or 0
  end
  topDirty, bottomDirty = true, true
end

-- Compact box: fixed width, slot 1 on top, slots 2 and 3 side by side below.
local function ApplyBoxStyle()
  local s1, s2, s3 = slotFS[1], slotFS[2], slotFS[3]
  local rowH1, rowH2 = fontSize + 4, fontSize + 1
  frame:SetSize(BOX_WIDTH, BOX_PAD + rowH1 + 1 + rowH2 + 3 + BOX_LINE + BOX_PAD)
  ox, oy, lineW, lineH = BOX_PAD, BOX_PAD, BOX_WIDTH - 2 * BOX_PAD, BOX_LINE
  capsOn = false

  SetFontSize(s1, fontSize + 2)
  s1:SetJustifyH("LEFT")
  s1:SetPoint("TOPLEFT", frame, "TOPLEFT", BOX_PAD, -BOX_PAD)
  AnchorMark(1, "right")
  SetFontSize(s2, fontSize - 1)
  s2:SetJustifyH("LEFT")
  s2:SetPoint("TOPLEFT", frame, "TOPLEFT", BOX_PAD, -(BOX_PAD + rowH1 + 1))
  AnchorMark(2, "right")
  SetFontSize(s3, fontSize - 1)
  s3:SetJustifyH("RIGHT")
  s3:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -BOX_PAD, -(BOX_PAD + rowH1 + 1))
  AnchorMark(3, "left")
  -- slot 1 keeps its pause mark inside the box; slots 2 and 3 share the second row:
  -- each gets half of it (long texts end with "..." instead of overlapping)
  s1:SetWidth(BOX_S1_W)
  s2:SetWidth(BOX_HALF); s3:SetWidth(BOX_HALF)

  bl:Hide(); brx:Hide()
  brxShown = false
  usePctMarker, usePctLevel = false, false
  -- short forms where the full text is wider than its slot (measured in the box fonts)
  for i = 1, NSLOTS do
    local a = lastAlt[i]
    if a ~= nil then
      slotW[i] = Measure(SlotMeter(i), lastText[i] or EMPTY)
      slotWAlt[i] = Measure(SlotMeter(i), a)
    end
    ChooseBoxVariant(i)
  end
end

function Bar.ApplyLayout()
  if not frame then return end
  local w = Widget()
  if not w then return end

  style = (w.style == "box") and "box" or "bar"
  fontSize = math_floor(Clamp(w.fontSize, 9, 16, 11))
  frame:SetScale(Clamp(w.scale, 0.5, 2.0, 1.0))
  ReadTextStyle(w)
  ReadBarColors(w)
  ApplyBackground(w)
  for i = 1, #allTexts do ApplyShadow(allTexts[i]) end

  ResetTextLayout()
  if style == "bar" then
    ApplyBarStyle(w)
  else
    ApplyBoxStyle()
  end

  -- progress line sizes
  tex.fillL:SetSize(lineH, lineH)
  tex.fillR:SetSize(lineH, lineH)
  tex.fillM:SetHeight(lineH)
  tex.fillHi:SetHeight(1)
  tex.rested:SetHeight(lineH)
  tex.restTick:SetSize(1, lineH)
  DrawTrack()

  SetFontSize(hint, math_max(9, fontSize - 1))
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
  rounded = type(frame.CreateMaskTexture) == "function"
  local w = Widget()
  if w then ReadTextStyle(w) end

  local COLORS = C.COLORS
  tex.trackL = NewCap("BORDER", 0, COLORS.track)
  tex.trackM = NewTexture("BORDER", 0, COLORS.track)
  tex.trackR = NewCap("BORDER", 0, COLORS.track)
  tex.rested = NewTexture("ARTWORK", 1, COLORS.rested)
  tex.fillL = NewCap("ARTWORK", 2, COLORS.fill)
  tex.fillM = NewTexture("ARTWORK", 2, COLORS.fill)
  tex.fillR = NewCap("ARTWORK", 2, COLORS.fill)
  tex.fillHi = NewTexture("ARTWORK", 3, COLORS.fillHi)
  tex.restTick = NewTexture("ARTWORK", 4, COLORS.restTick)
  local acc = COLORS.accent
  tex.veil = NewTexture("OVERLAY", 7, { acc[1], acc[2], acc[3], VEIL_ALPHA })
  tex.veil:SetAllPoints(frame)
  tex.fillL:Hide(); tex.fillM:Hide(); tex.fillR:Hide(); tex.fillHi:Hide()
  tex.rested:Hide(); tex.restTick:Hide()

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
  -- text measuring (never seen: alpha 0); measuring a slot that the layout hides would
  -- otherwise depend on the width a hidden FontString reports
  meterS = NewFontString("BACKGROUND")
  meterM = NewFontString("BACKGROUND")
  meterL = NewFontString("BACKGROUND")
  meterS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  meterM:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  meterL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
  meterS:SetAlpha(0); meterM:SetAlpha(0); meterL:SetAlpha(0)

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

  -- Read-only handles for the offline tests (our own frame).
  frame.tp = { slots = slotFS, marks = slotMark, bl = bl, brx = brx, sep = sepFS, marker = marker,
               hint = hint, tex = tex, hits = hit }

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
  if LAYOUT_PATHS[path] then
    Bar.ApplyLayout()
  elseif BAR_COLOR_PATHS[path] or (type(path) == "string" and (path:find("widget.xpColor.", 1, true) == 1
      or path:find("widget.restedColor.", 1, true) == 1)) then
    local w = Widget()
    if w and ReadBarColors(w) then Bar.UpdateXP() end
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
