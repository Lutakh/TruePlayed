-- TooltipFrame.lua - the private tooltip frame of the non-native themes (SPEC-themes 4.5).
--
-- One anonymous frame (strata TOOLTIP, clamped to the screen, no mouse), created at the
-- first Get() and never released. It answers the GameTooltip calls Tooltip.lua makes
-- (SetOwner, GetOwner, ClearLines, AddLine, AddDoubleLine, NumLines, Show, Hide, ...)
-- plus three extensions that carry the kind of each row: TP_Row, TP_Sep and TP_Gauge.
-- It never writes anything on GameTooltip.
--
-- Performance contract (SPEC-themes D5, 4.5):
--   * rows ({ left, right, leader }), separators and the 8 gauge segments are pooled;
--     pools only grow, so a show whose rows fit the pools creates no region;
--   * the theme parts (panel, title icon, separator and leader art, fonts) are applied
--     at the first show after a theme change (th.gen differs), never on a refresh;
--   * a refresh (once per TICK while shown) costs no FontString work for steady values:
--     SetText and GetStringWidth only when a row's text (or its font) changed, colours
--     only when they changed, anchors only when a row moved or changed kind, and no
--     table is created.
-- Texture specs are the compiled ones of SPEC-themes 2.8 ({ path, w, h, tc, tc8, tile,
-- slice }, defaults from their metatable); gradients follow L6 (SetGradient with colour
-- tables, then SetGradientAlpha, then the flat colour).
local ADDON, ns = ...
local C = ns.C

local type, wipe = type, wipe
local floor, ceil = math.floor, math.ceil
local CreateFrame, UIParent = CreateFrame, UIParent

local TF = {}
ns.TooltipFrame = TF
TF.frame = nil

local WHITE = C.TEX_WHITE
local MAX_SEGS = 8              -- gauge segments: the 8 breakdown parts
local DEFAULT_TEXT = { 1, 1, 1, 1 }
local SEP_BLANK = 4             -- a separator kind the theme lacks: lineGap + this, blank
-- 9-slice anchors: each slice has a TOPLEFT and a BOTTOMRIGHT point on a corner of its
-- box, [row][col] = the box point they use.
local NINE_TL = { { "TOPLEFT", "TOPLEFT", "TOPRIGHT" }, { "TOPLEFT", "TOPLEFT", "TOPRIGHT" },
                  { "BOTTOMLEFT", "BOTTOMLEFT", "BOTTOMRIGHT" } }
local NINE_BR = { { "TOPLEFT", "TOPRIGHT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT" },
                  { "BOTTOMLEFT", "BOTTOMRIGHT", "BOTTOMRIGHT" } }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame, tp                 -- the frame and its test handles (frame.tp)
local FrameShow, FrameHide      -- the frame's own Show / Hide (shadowed by the methods below)
local owner = nil
local rows, seps, segs = {}, {}, {}
local order, nItems = {}, 0     -- display order: row index (> 0) or -separator index
local shownRows, shownSeps = 0, 0
local sk = nil                  -- the applied theme parts (normalized), see Build
local skinGen, skinTh = -1, nil
local curW, inner = 0, 0        -- width of the current layout, its inner width
local sizeW, sizeH = -1, -1     -- size applied to the frame
local plainPool, ninePool = {}, {}
local tiledParts = {}           -- FILL panel parts whose tiling depends on the frame size
local gradNines = {}            -- 9-slice panel parts with a gradient: (pieces, part) pairs
local gFr, gKey, gN, gRow = {}, {}, 0, 0   -- gauge of the current fill (row index gRow)
local segX, segW, segY, segK, segOn = {}, {}, {}, {}, {}
local gaugeShown = false
local outline, icon = nil, nil
local olX, olY, olOn = -1, -1, false   -- gauge outline position, shown
local iconOn = false
local iconY = -1
local lineBufL, lineBufR = { 1, 1, 1, 1 }, { 1, 1, 1, 1 }   -- AddLine / AddDoubleLine colours

---------------------------------------------------------------------------
-- Compiled theme data (read at Build only; allocations allowed there). Colours are the
-- compiled rgba arrays; a gradient is one compiled pair { from, to, dir = }, applied with
-- Themes.Gradient (the tooltip has no fill state).
---------------------------------------------------------------------------

-- An rgba array: a compiled colour as it is; a per-state list gives its first entry.
local function RGBA(c)
  if type(c) ~= "table" then return nil end
  if type(c[1]) == "number" then return c end
  if type(c[1]) == "table" then return RGBA(c[1]) end
  if c.r ~= nil then return { c.r, c.g, c.b, c.a or 1 } end
  return nil
end

local function Num(v, def)
  if type(v) == "number" then return v end
  return def
end

-- Texture spec of a theme item (SPEC 2.8 / Themes TexSpec); white when it has none.
local WHITE_SPEC = { path = WHITE, w = 8, h = 8 }
local function Spec(item)
  local spec = item.tex
  if type(spec) == "table" and type(spec.path) == "string" then return spec end
  return WHITE_SPEC
end

-- Font slot { role, size } -> { role, size, effective size (Themes.Font) }.
local function FontSlot(f, role, size)
  if type(f) == "table" then
    role = f.role or f[1] or role
    size = f.size or f[2] or size
  end
  local eff = size
  local Themes = ns.Themes
  if Themes and Themes.Font then
    local _, s = Themes.Font(role, size)
    if type(s) == "number" then eff = s end
  end
  return { role, size, eff }
end

-- Colour of an item into `out`: c (flat rgba), g / f (gradient and its fallback colour:
-- the from colour when the item has none) and gm (the same gradient reversed, for the
-- right half of a mirrored separator: same fallback colour).
local function Paint(out, item)
  out.c = RGBA(item.c) or DEFAULT_TEXT
  local g = item.g
  if type(g) == "table" and type(g[1]) == "table" and type(g[2]) == "table" then
    out.g, out.f = g, item.f or g[1]
    out.gm = { g.dir, g[2], g[1] }
  end
  return out
end

local function NormSep(s)
  if type(s) ~= "table" then return false end
  local out = { h = Num(s.h, 1), above = Num(s.above, 6), below = Num(s.below, 5),
                spec = Spec(s), mirror = s.mirror == true, center = Num(s.center, nil) }
  return Paint(out, s)
end

local function NormPart(p, i)
  if type(p) ~= "table" then return nil end
  local spec = Spec(p)
  local inset = type(p.inset) == "table" and p.inset or nil
  local out = {
    id = p.id or ("part" .. i), spec = spec,
    nine = p.kind == "nine" and type(spec.slice) == "table",
    layer = p.layer or "BACKGROUND", sub = Num(p.sub, -8 + i - 1),
    anchor = p.anchor or "FILL",
    l = inset and Num(inset[1], 0) or 0, r = inset and Num(inset[2], 0) or 0,
    t = inset and Num(inset[3], 0) or 0, b = inset and Num(inset[4], 0) or 0,
    x = Num(p.x, 0), y = Num(p.y, 0), w = Num(p.w, 1), h = Num(p.h, 1),
  }
  return Paint(out, p)
end

-- The tooltip section of the active theme in the form the layout reads. Missing values
-- take the SPEC 4.2 defaults; a theme without the section (or no Themes) gets a plain
-- dark panel.
local function Normalize(th)
  local tt = th and th.tt or nil
  if type(tt) ~= "table" then tt = {} end
  local width = type(tt.width) == "table" and tt.width or {}
  local pad = type(tt.pad) == "table" and tt.pad or {}
  local fonts = type(tt.fonts) == "table" and tt.fonts or {}
  local s = {
    wmin = Num(width[1], 280), wmax = Num(width[2], 440),
    padL = Num(pad[1], 12), padR = Num(pad[2], 12), padT = Num(pad[3], 10), padB = Num(pad[4], 10),
    gap = Num(tt.gap, 8), lineGap = Num(tt.lineGap, 3),
    parts = {}, sep = {},
    label = RGBA(type(tt.colors) == "table" and tt.colors.label) or C.COLORS.label,
  }
  s.fTitle = FontSlot(fonts.title, "display", 13)
  s.fBody = FontSlot(fonts.body, "body", 13)
  s.fValue = FontSlot(fonts.value or fonts.body, "body", 13)
  s.fNote = FontSlot(fonts.note, "body", 12)
  s.fHint = FontSlot(fonts.hint, "body", 11)
  local panel = type(tt.panel) == "table" and tt.panel or nil
  local parts = panel and type(panel.parts) == "table" and panel.parts or nil
  if parts and #parts > 0 then
    for i = 1, #parts do
      local p = NormPart(parts[i], i)
      if p then s.parts[#s.parts + 1] = p end
    end
  else
    local bg = C.COLORS.bg
    s.parts[1] = NormPart({ id = "bg", c = { bg[1], bg[2], bg[3], 0.92 } }, 1)
  end
  local ti = tt.titleIcon
  if type(ti) == "table" then
    s.icon = { spec = Spec(ti), w = Num(ti.w, 12), h = Num(ti.h, 12), gap = Num(ti.gap, 6) }
  end
  local sep = type(tt.sep) == "table" and tt.sep or {}
  s.sep.header, s.sep.block, s.sep.footer = NormSep(sep.header), NormSep(sep.block), NormSep(sep.footer)
  local ld = tt.leader
  if type(ld) == "table" then
    s.leader = Paint({ spec = Spec(ld), h = Num(ld.h, 1), y = Num(ld.y, 3), min = Num(ld.min, 12) }, ld)
  end
  local g = tt.gauge
  if type(g) == "table" and type(g.colors) == "table" then
    local cols = {}
    for k, v in pairs(g.colors) do cols[k] = RGBA(v) end
    s.gauge = { w = Num(g.w, 176), h = Num(g.h, 6), gap = Num(g.gap, 2), outline = RGBA(g.outline), colors = cols }
  end
  return s
end

---------------------------------------------------------------------------
-- Texture helpers (Themes.SetTex / Tile / Gradient; a reused texture is reset first)
---------------------------------------------------------------------------

local function SetTex(t, spec)
  t:SetTexCoord(0, 1, 0, 1)
  local Themes = ns.Themes
  if Themes and Themes.SetTex then
    Themes.SetTex(t, spec)
  else
    t:SetTexture(spec.path)
    t:SetBlendMode("BLEND")
  end
end

-- Repeat coordinates of a tiled texture drawn w x h px (skipped when unchanged).
local function Tile(t, spec, w, h)
  if not spec.tile then return end
  ns.Themes.Tile(t, spec, w > 0 and w or 0, h > 0 and h or 0)
end

-- Colour of an item (Paint form): its gradient (L6), else its vertex colour.
local function Colorize(t, item, mirror)
  if item.g then
    ns.Themes.Gradient(t, mirror and item.gm or item.g, item.f)
    return
  end
  local c = item.c
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
end

-- Half a texel inwards at both ends of a stretched middle range (as Themes' PlaceNine):
-- bilinear filtering then never smears the corner texels into the stretched pieces.
local function Inset(a, b, n)
  local d = 0.5 / n
  if b - a >= 2 * d - 1e-9 then return a + d, b - d end
  if a - b >= 2 * d - 1e-9 then return a - d, b + d end
  return a, b
end

-- Slice boundaries of a 9-slice spec: 4 u (left to right as drawn) and 4 v (top to
-- bottom as drawn), mirrored by flipX / flipY (SPEC 6.3), plus the middle column (mu)
-- and row (mv) moved in by half a texel.
local function NineCuts(spec)
  local c = spec.slice[1]
  local tw, th = spec.w or 1, spec.h or 1
  local cu, cv = c / tw, c / th
  local l, r, t, b = spec.l or 0, spec.r or 1, spec.t or 0, spec.b or 1
  local u = spec.flipX and { r, r - cu, l + cu, l } or { l, l + cu, r - cu, r }
  local v = spec.flipY and { b, b - cv, t + cv, t } or { t, t + cv, b - cv, b }
  local mu1, mu2 = Inset(u[2], u[3], tw)
  local mv1, mv2 = Inset(v[2], v[3], th)
  return u, v, { mu1, mu2 }, { mv1, mv2 }
end

---------------------------------------------------------------------------
-- Panel parts (built at the first show after a theme change)
---------------------------------------------------------------------------

local function NewPlain()
  local t = frame:CreateTexture(nil, "BACKGROUND")
  plainPool[#plainPool + 1] = t
  return t
end

-- 9 slices plus an invisible box texture (the anchor of a point-anchored 9-slice).
local function NewNine()
  local g = {}
  for i = 1, 9 do g[i] = frame:CreateTexture(nil, "BACKGROUND") end
  g.box = frame:CreateTexture(nil, "BACKGROUND")
  g.box:Hide()
  ninePool[#ninePool + 1] = g
  return g
end

-- Anchors a region to the part's box: the whole frame inset (FILL), or a fixed-size
-- rectangle at a point of the frame.
local function PlaceBox(t, p)
  t:ClearAllPoints()
  if p.anchor == "FILL" then
    t:SetPoint("TOPLEFT", frame, "TOPLEFT", p.l, -p.t)
    t:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -p.r, p.b)
  else
    t:SetPoint(p.anchor, frame, p.anchor, p.x, p.y)
    t:SetSize(p.w, p.h)
  end
end

-- 9-slice inside its box with anchors only: the corners keep their size, the edges and
-- the centre follow the box, so a resize of the tooltip needs no work. Corners are cut
-- at slice[1] texels of the texture rectangle and drawn at slice[2] px (SPEC 6.3); a
-- flipped rectangle (l > r or t > b) mirrors the whole 9-slice.
local function ConfigureNine(g, p)
  local spec = p.spec
  local px = spec.slice[2]
  local us, vs, mu, mv = NineCuts(spec)
  local box, il, ir, it, ib = frame, p.l, p.r, p.t, p.b
  if p.anchor ~= "FILL" then
    box, il, ir, it, ib = g.box, 0, 0, 0, 0
    PlaceBox(box, p)
  end
  local x1 = { il, il + px, -ir - px }
  local y1 = { -it, -it - px, ib + px }
  local x2 = { il + px, -ir - px, -ir }
  local y2 = { -it - px, ib + px, ib }
  for i = 1, 9 do
    local sl = g[i]
    local col, row = (i - 1) % 3 + 1, floor((i - 1) / 3) + 1
    SetTex(sl, spec)
    local u1, u2, v1, v2 = us[col], us[col + 1], vs[row], vs[row + 1]
    if col == 2 then u1, u2 = mu[1], mu[2] end
    if row == 2 then v1, v2 = mv[1], mv[2] end
    sl:SetTexCoord(u1, u2, v1, v2)
    sl:SetDrawLayer(p.layer, p.sub)
    sl:ClearAllPoints()
    sl:SetPoint("TOPLEFT", box, NINE_TL[row][col], x1[col], y1[row])
    sl:SetPoint("BOTTOMRIGHT", box, NINE_BR[row][col], x2[col], y2[row])
    if not p.g then Colorize(sl, p) end
    sl:Show()
  end
  if p.g then                     -- one ramp over the 9 pieces: set by Layout (size known)
    gradNines[#gradNines + 1] = g
    gradNines[#gradNines + 1] = p
  end
end

local function BuildPanel()
  local panel = tp.panel
  wipe(panel)
  wipe(tiledParts)
  wipe(gradNines)
  local nPlain, nNine = 0, 0
  local parts = sk.parts
  for i = 1, #parts do
    local p = parts[i]
    if p.nine then
      nNine = nNine + 1
      local g = ninePool[nNine] or NewNine()
      ConfigureNine(g, p)
      panel[p.id] = g
    else
      nPlain = nPlain + 1
      local t = plainPool[nPlain] or NewPlain()
      SetTex(t, p.spec)
      t:SetDrawLayer(p.layer, p.sub)
      PlaceBox(t, p)
      if p.spec.tile then
        if p.anchor == "FILL" then
          tiledParts[#tiledParts + 1] = t
          tiledParts[#tiledParts + 1] = p
        else
          Tile(t, p.spec, p.w, p.h)
        end
      end
      Colorize(t, p)
      t:Show()
      panel[p.id] = t
    end
  end
  for i = nPlain + 1, #plainPool do plainPool[i]:Hide() end
  for i = nNine + 1, #ninePool do
    local g = ninePool[i]
    for k = 1, 9 do g[k]:Hide() end
  end
end

---------------------------------------------------------------------------
-- Theme application (first show after a theme change)
---------------------------------------------------------------------------

local function Build(th)
  sk = Normalize(th)
  BuildPanel()
  local ic = sk.icon
  if ic then
    if not icon then
      icon = frame:CreateTexture(nil, "ARTWORK", nil, 3)
      tp.icon = icon
    end
    SetTex(icon, ic.spec)
    icon:SetSize(ic.w, ic.h)
    icon:SetVertexColor(1, 1, 1, 1)             -- baked art (SPEC 6.2)
  elseif icon then
    icon:Hide()
  end
  iconY, iconOn = -1, false
  if outline and sk.gauge and sk.gauge.outline then
    local c = sk.gauge.outline
    outline:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  end
  olX, olY = -1, -1
  for i = 1, #segK do segK[i], segY[i] = false, -1 end
  -- every cache of the pooled rows and separators is stale: fonts, colours, art, anchors
  for i = 1, #rows do
    local row = rows[i]
    row.fk, row.lr, row.rr = false, false, false
    row.y, row.lgen = -1, -1
  end
  for i = 1, #seps do seps[i].cfg = false end
  sizeW, sizeH = -1, -1
end

local function EnsureSkin()
  local Themes = ns.Themes
  local th = Themes and Themes.Active() or nil
  local gen = th and th.gen or 0
  if sk and gen == skinGen and th == skinTh then return end
  skinGen, skinTh = gen, th
  Build(th)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function NewText(justify)
  local fs = frame:CreateFontString(nil, "OVERLAY")
  fs:SetJustifyH(justify)
  fs:SetWordWrap(false)
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:Hide()
  return fs
end

local function NewRow(i)
  local row = {
    kind = false, left = NewText("LEFT"), right = NewText("RIGHT"), leader = nil,
    wrap = false, lt = false, rt = false, lw = -1, rw = -1, wh = -1,
    lr = false, lg = 0, lb = 0, la = 0, rr = false, rg = 0, rb = 0, ra = 0,
    fk = false, lslot = nil, rslot = nil, lcw = 0, wwrap = false,
    y = -1, ak = false, ax = -1, ah = -1, ls = false, rs = false,
    lgen = -1, ldx = -1, ldy = -1, ldw = -1, lds = false,
  }
  rows[i] = row
  return row
end

-- Font slots of a row kind (SPEC 4.5): left, right.
local function SlotsOf(kind)
  if kind == "title" then return sk.fTitle, sk.fBody end
  if kind == "note" or kind == "wrap" then return sk.fNote, sk.fValue end
  if kind == "hint" then return sk.fHint, sk.fValue end
  return sk.fBody, sk.fValue
end

local function ApplyRowFonts(row, kind)
  local Themes = ns.Themes
  local ls, rs = SlotsOf(kind)
  if Themes and Themes.SetFont then
    Themes.SetFont(row.left, ls[1], ls[2], "none")
    Themes.SetFont(row.right, rs[1], rs[2], "none")
  else
    local game = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    row.left:SetFont(game, ls[2], "")
    row.right:SetFont(game, rs[2], "")
  end
  row.left:SetJustifyH(kind == "hint" and "CENTER" or "LEFT")
  row.lslot, row.rslot = ls, rs
  row.fk = kind
  row.lw, row.rw, row.wh = -1, -1, -1
  row.ak = false
end

local function SetColorL(row, c)
  local r, g, b, a = c[1], c[2], c[3], c[4] or 1
  if r ~= row.lr or g ~= row.lg or b ~= row.lb or a ~= row.la then
    row.lr, row.lg, row.lb, row.la = r, g, b, a
    row.left:SetTextColor(r, g, b, a)
  end
end

local function SetColorR(row, c)
  local r, g, b, a = c[1], c[2], c[3], c[4] or 1
  if r ~= row.rr or g ~= row.rg or b ~= row.rb or a ~= row.ra then
    row.rr, row.rg, row.rb, row.ra = r, g, b, a
    row.right:SetTextColor(r, g, b, a)
  end
end

---------------------------------------------------------------------------
-- Methods (copied onto the frame: a duck-typed GameTooltip subset + TP_ extensions)
---------------------------------------------------------------------------

local M = {}

function M.TP_Row(self, kind, left, right, lc, rc, wrap)
  if not sk then EnsureSkin() end
  local n = tp.n + 1
  tp.n = n
  local row = rows[n] or NewRow(n)
  if row.fk ~= kind then ApplyRowFonts(row, kind) end
  row.kind = kind
  row.wrap = (wrap or kind == "wrap") and true or false
  if left == nil then left = "" end
  if left ~= row.lt then
    row.lt = left
    row.left:SetText(left)
    row.lw, row.wh = -1, -1
  end
  if right ~= row.rt then
    row.rt = right
    if right ~= nil then row.right:SetText(right) end
    row.rw = -1
  end
  SetColorL(row, lc or DEFAULT_TEXT)
  if right ~= nil then SetColorR(row, rc or DEFAULT_TEXT) end
  nItems = nItems + 1
  order[nItems] = n
end

function M.TP_Sep(self, kind)
  local i = tp.nSeps + 1
  tp.nSeps = i
  local s = seps[i]
  if not s then
    s = { kind = false, a = frame:CreateTexture(nil, "ARTWORK", nil, 0),
          b = frame:CreateTexture(nil, "ARTWORK", nil, 0), cfg = false, y = -1, w = -1, on = false }
    s.a:Hide()
    s.b:Hide()
    seps[i] = s
  end
  s.kind = kind
  nItems = nItems + 1
  order[nItems] = -i
end

-- Breakdown gauge row: `label`, then one segment per part (fracs[i] of the width,
-- colour of keys[i]). Returns false (nothing added) when the theme has no gauge.
function M.TP_Gauge(self, label, fracs, keys, n)
  if not sk then EnsureSkin() end
  if not sk.gauge or type(n) ~= "number" or n <= 0 then return false end
  if n > MAX_SEGS then n = MAX_SEGS end
  for i = 1, n do
    gFr[i] = fracs[i] or 0
    gKey[i] = keys[i] or "world"
  end
  gN = n
  M.TP_Row(self, "gauge", label, nil, sk.label, nil)
  gRow = tp.n
  return true
end

function M.ClearLines(self)
  EnsureSkin()
  tp.n, tp.nSeps = 0, 0
  nItems, gN, gRow = 0, 0, 0
end

function M.SetOwner(self, o)
  owner = o
  M.ClearLines(self)
end

function M.GetOwner(self)
  return owner
end

function M.NumLines(self)
  return tp.n
end

function M.AddLine(self, text, r, g, b, wrap)
  local c = lineBufL
  c[1], c[2], c[3] = r or 1, g or 1, b or 1
  M.TP_Row(self, wrap and "wrap" or "line", text, nil, c, nil, wrap)
end

function M.AddDoubleLine(self, left, right, lr, lg, lb, rr, rg, rb)
  local a, b = lineBufL, lineBufR
  a[1], a[2], a[3] = lr or 1, lg or 1, lb or 1
  b[1], b[2], b[3] = rr or 1, rg or 1, rb or 1
  M.TP_Row(self, "pair", left, right, a, b)
end

---------------------------------------------------------------------------
-- Layout (Show): change-only
---------------------------------------------------------------------------

local function HasLeader(kind)
  return sk.leader ~= nil and (kind == "pair" or kind == "gauge")
end

-- Natural width of a non-wrapping row (measured texts, SPEC 4.5). The client's
-- GetStringWidth is bounded by an explicit width: a label cut by a previous layout (or a
-- wrapping row turned single-line) is freed first, whatever made it measured again (its
-- text, its font after a rebuild); PrepareRow cuts it again when it still does not fit.
local function Natural(row, i)
  local kind = row.kind
  if row.lw < 0 then
    if row.lcw > 0 then
      row.left:SetWidth(0)
      row.lcw = 0
      row.wh = -1
    end
    row.lw = row.left:GetStringWidth() or 0
  end
  local w = row.lw
  if kind == "title" and i == 1 and sk.icon then w = w + sk.icon.w + sk.icon.gap end
  local gap = sk.gap
  if kind == "gauge" then
    w = w + gap + sk.gauge.w + 1
  elseif row.rt ~= nil then
    if row.rw < 0 then row.rw = row.right:GetStringWidth() or 0 end
    w = w + gap + row.rw
  end
  if HasLeader(kind) then w = w + gap + sk.leader.min end
  return w
end

local function RowHeight(row)
  local ls, rs = row.lslot, row.rslot
  local h = ls[3]
  if row.wrap then
    if row.wh < 0 then row.wh = row.left:GetStringHeight() or h end
    if row.wh > h then h = row.wh end
  elseif row.rt ~= nil and rs[3] > h then
    h = rs[3]
  end
  local kind = row.kind
  if kind == "title" and sk.icon and sk.icon.h > h then h = sk.icon.h end
  if kind == "gauge" and sk.gauge.h + 2 > h then h = sk.gauge.h + 2 end
  return h + sk.lineGap
end

local function LeaderTex(row)
  local t = row.leader
  if not t then
    t = frame:CreateTexture(nil, "ARTWORK", nil, 0)
    row.leader = t
  end
  if row.lgen ~= skinGen then
    local ld = sk.leader
    SetTex(t, ld.spec)
    Colorize(t, ld)
    row.lgen = skinGen
    row.ldw = -1
  end
  return t
end

-- Leader between the label and the value (or the gauge), `y` px above the row bottom;
-- hidden when shorter than its minimum.
local function PlaceLeader(row, top, h)
  local show = false
  local ld = sk.leader
  if HasLeader(row.kind) then
    local gap = sk.gap
    local rw = (row.kind == "gauge") and sk.gauge.w + 1 or ((row.rt ~= nil) and row.rw or 0)
    local w = inner - row.lw - rw - 2 * gap
    if w >= ld.min then
      show = true
      local t = LeaderTex(row)
      local x = sk.padL + row.lw + gap
      local y = top + h - ld.y - ld.h
      if x ~= row.ldx or y ~= row.ldy or w ~= row.ldw then
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
        t:SetSize(w, ld.h)
        if w ~= row.ldw then Tile(t, ld.spec, w, ld.h) end
        row.ldx, row.ldy, row.ldw = x, y, w
      end
    end
  end
  if show ~= row.lds then
    row.lds = show
    if show then row.leader:Show() elseif row.leader then row.leader:Hide() end
  end
end

-- Width of the left text: the inner width when it wraps, cut when it would cover the
-- value, else free. Runs before the row height is read (a wrapping height depends on it).
local function PrepareRow(row)
  local want = 0
  if row.wrap then
    want = inner
  elseif row.rt ~= nil and row.kind ~= "title" then
    local room = inner - row.rw - sk.gap
    if row.lw > room then want = (room > 1) and room or 1 end
  end
  if row.wrap ~= row.wwrap then
    row.wwrap = row.wrap
    row.left:SetWordWrap(row.wrap)
    row.wh = -1
  end
  if want ~= row.lcw then
    row.lcw = want
    row.left:SetWidth(want)
    row.wh = -1
  end
end

local function PlaceRow(row, i, top, h)
  local kind = row.kind
  local x = sk.padL
  if kind == "title" and i == 1 and sk.icon then x = x + sk.icon.w + sk.icon.gap end
  if top ~= row.y or kind ~= row.ak or x ~= row.ax or h ~= row.ah then
    row.y, row.ak, row.ax, row.ah = top, kind, x, h
    local lf = row.left
    local ly
    if row.wrap then
      ly = top + floor(sk.lineGap / 2)
    else
      ly = top + floor((h - row.lslot[3]) / 2)
    end
    lf:ClearAllPoints()
    if kind == "hint" then
      lf:SetPoint("TOP", frame, "TOP", 0, -ly)
    else
      lf:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -ly)
    end
    local rf = row.right
    rf:ClearAllPoints()
    rf:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -sk.padR, -(top + floor((h - row.rslot[3]) / 2)))
  end
  if not row.ls then
    row.ls = true
    row.left:Show()
  end
  local rshow = row.rt ~= nil
  if rshow ~= row.rs then
    row.rs = rshow
    if rshow then row.right:Show() else row.right:Hide() end
  end
  PlaceLeader(row, top, h)
end

local function HideRow(row)
  if row.ls then
    row.ls = false
    row.left:Hide()
  end
  if row.rs then
    row.rs = false
    row.right:Hide()
  end
  if row.lds then
    row.lds = false
    row.leader:Hide()
  end
end

-- Shows or hides the pieces of a separator: a (the whole line, the left half of a mirrored
-- one, the left side of a centred one), b (the right half / side), c (a centred ornament).
local function SepParts(s, cfg, on)
  if on then s.a:Show() else s.a:Hide() end
  if on and cfg and (cfg.mirror or cfg.center) then s.b:Show() else s.b:Hide() end
  local c = s.c
  if c then
    if on and cfg and cfg.center then c:Show() else c:Hide() end
  end
end

-- Coordinates of a separator with a centred ornament: the middle `center` texels for c,
-- the sides for a and b, which stretch and so stop half a texel before the cuts.
local function CenterCoords(s, cfg)
  local spec = cfg.spec
  local l, r, t, b = spec.l or 0, spec.r or 1, spec.t or 0, spec.b or 1
  if spec.flipX then l, r = r, l end
  if spec.flipY then t, b = b, t end
  local d = (r > l) and 1 or -1
  local mid, half = (l + r) / 2, cfg.center / spec.w * d / 2
  local u1, u2, e = mid - half, mid + half, 0.5 / spec.w * d
  s.a:SetTexCoord(l, u1 - e, t, b)
  s.c:SetTexCoord(u1, u2, t, b)
  s.b:SetTexCoord(u2 + e, r, t, b)
end

local function ConfigureSep(s, cfg)
  s.cfg = cfg
  s.w = -1
  if not cfg then return end
  SetTex(s.a, cfg.spec)
  Colorize(s.a, cfg)
  if cfg.mirror then
    SetTex(s.b, cfg.spec)
    Colorize(s.b, cfg, true)
  elseif cfg.center then
    if not s.c then
      s.c = frame:CreateTexture(nil, "ARTWORK", nil, 0)
      s.c:Hide()
    end
    SetTex(s.b, cfg.spec)
    SetTex(s.c, cfg.spec)
    CenterCoords(s, cfg)
    Colorize(s.b, cfg)
    Colorize(s.c, cfg)
  end
  -- a shown separator taking another kind (the short and the Shift tooltips put different
  -- kinds at the same index): its pieces follow the new kind
  if s.on then SepParts(s, cfg, true) end
end

local function PlacePiece(t, x, y, w, h)
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
  t:SetSize(w, h)
end

-- Returns the height the separator takes.
local function PlaceSep(s, top)
  local cfg = sk.sep[s.kind] or false
  if cfg ~= s.cfg then ConfigureSep(s, cfg) end
  if not cfg then
    if s.on then
      s.on = false
      SepParts(s, cfg, false)
    end
    return sk.lineGap + SEP_BLANK
  end
  local y = top + cfg.above
  if y ~= s.y or inner ~= s.w then
    s.y, s.w = y, inner
    local x = sk.padL
    if cfg.center then
      -- the ornament at the art's proportions (its texel height drawn cfg.h px), centred
      local spec = cfg.spec
      local artH = ((spec.b or 1) - (spec.t or 0)) * spec.h
      if artH < 0 then artH = -artH end
      local cw = floor(cfg.center * cfg.h / artH + 0.5)
      if cw > inner - 2 then cw = inner - 2 end
      local wl = floor((inner - cw) / 2)
      PlacePiece(s.a, x, y, wl, cfg.h)
      PlacePiece(s.c, x + wl, y, cw, cfg.h)
      PlacePiece(s.b, x + wl + cw, y, inner - cw - wl, cfg.h)
    else
      local wa = cfg.mirror and floor(inner / 2) or inner
      PlacePiece(s.a, x, y, wa, cfg.h)
      Tile(s.a, cfg.spec, wa, cfg.h)
      if cfg.mirror then
        PlacePiece(s.b, x + wa, y, inner - wa, cfg.h)
        Tile(s.b, cfg.spec, inner - wa, cfg.h)
      end
    end
  end
  if not s.on then
    s.on = true
    SepParts(s, cfg, true)
  end
  return cfg.above + cfg.h + cfg.below
end

local function HideSep(s)
  if s.on then
    s.on = false
    SepParts(s, s.cfg, false)
  end
end

-- Gauge of the gauge row: right-aligned, vertically centred; segments split the width
-- minus the gaps by cumulative rounding (their widths add up exactly).
local function PlaceGauge(top, h)
  local g = sk.gauge
  local x0 = curW - sk.padR - g.w
  local y = top + floor((h - g.h) / 2)
  if g.outline then
    if not outline then
      outline = frame:CreateTexture(nil, "ARTWORK", nil, 1)
      outline:SetTexture(WHITE)
      local c = g.outline
      outline:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end
    if olY ~= y or olX ~= x0 then
      olY, olX = y, x0
      outline:ClearAllPoints()
      outline:SetPoint("TOPLEFT", frame, "TOPLEFT", x0 - 1, -(y - 1))
      outline:SetSize(g.w + 2, g.h + 2)
    end
    if not olOn then
      olOn = true
      outline:Show()
    end
  elseif outline and olOn then
    olOn = false
    outline:Hide()
  end
  local n = gN
  local avail = g.w - g.gap * (n - 1)
  local total = 0
  for i = 1, n do total = total + gFr[i] end
  if total <= 0 then total = 1 end
  local acc, prev = 0, 0
  for i = 1, MAX_SEGS do
    local t = segs[i]
    if i <= n then
      if not t then
        t = frame:CreateTexture(nil, "ARTWORK", nil, 2)
        t:SetTexture(WHITE)
        segs[i] = t
        segX[i], segW[i], segY[i], segK[i], segOn[i] = -1, -1, -1, false, true
      end
      acc = acc + gFr[i]
      local edge = (i == n) and avail or floor(avail * acc / total + 0.5)
      local w = edge - prev
      local x = x0 + prev + g.gap * (i - 1)
      prev = edge
      if w > 0 then
        if x ~= segX[i] or w ~= segW[i] or y ~= segY[i] then
          segX[i], segW[i], segY[i] = x, w, y
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
          t:SetSize(w, g.h)
        end
        local key = gKey[i]
        if key ~= segK[i] then
          segK[i] = key
          local c = g.colors[key] or DEFAULT_TEXT
          t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
        end
        if not segOn[i] then
          segOn[i] = true
          t:Show()
        end
      elseif segOn[i] then
        segOn[i] = false
        t:Hide()
      end
    elseif t and segOn[i] then
      segOn[i] = false
      t:Hide()
    end
  end
  gaugeShown = true
end

local function HideGauge()
  if not gaugeShown then return end
  gaugeShown = false
  for i = 1, MAX_SEGS do
    if segs[i] and segOn[i] then
      segOn[i] = false
      segs[i]:Hide()
    end
  end
  if outline and olOn then
    olOn = false
    outline:Hide()
  end
end

local function Layout()
  local n = tp.n
  -- width: the widest non-wrapping row, clamped
  local nat = 0
  for i = 1, n do
    local row = rows[i]
    if not row.wrap then
      local w = Natural(row, i)
      if w > nat then nat = w end
    end
  end
  -- rounded up: measured widths are fractional, and a frame narrower than its widest row
  -- (even by a fraction of a pixel) would cut that row's label
  local W = ceil(nat + sk.padL + sk.padR - 0.001)
  if W < sk.wmin then W = sk.wmin elseif W > sk.wmax then W = sk.wmax end
  inner = W - sk.padL - sk.padR
  curW = W
  -- rows and separators from the top, in order
  local y = sk.padT
  local hasGauge = false
  for k = 1, nItems do
    local idx = order[k]
    if idx > 0 then
      local row = rows[idx]
      PrepareRow(row)
      local h = RowHeight(row)
      PlaceRow(row, idx, y, h)
      if idx == 1 and row.kind == "title" and sk.icon then
        local iy = y + floor((h - sk.icon.h) / 2)
        if iy ~= iconY then
          iconY = iy
          icon:ClearAllPoints()
          icon:SetPoint("TOPLEFT", frame, "TOPLEFT", sk.padL, -iy)
        end
        if not iconOn then
          iconOn = true
          icon:Show()
        end
      end
      if idx == gRow then
        hasGauge = true
        PlaceGauge(y, h)
      end
      y = y + h
    else
      y = y + PlaceSep(seps[-idx], y)
    end
  end
  if not hasGauge then HideGauge() end
  if iconOn and not (sk.icon and n > 0 and rows[1].kind == "title") then
    iconOn = false
    icon:Hide()
  end
  local H = floor(y + sk.padB + 0.5)
  for i = n + 1, shownRows do HideRow(rows[i]) end
  shownRows = n
  for i = tp.nSeps + 1, shownSeps do HideSep(seps[i]) end
  shownSeps = tp.nSeps
  if W ~= sizeW or H ~= sizeH then
    sizeW, sizeH = W, H
    frame:SetSize(W, H)
    for i = 1, #tiledParts, 2 do
      local p = tiledParts[i + 1]
      Tile(tiledParts[i], p.spec, W - p.l - p.r, H - p.t - p.b)
    end
    for i = 1, #gradNines, 2 do
      local p = gradNines[i + 1]
      local bw, bh = p.w, p.h
      if p.anchor == "FILL" then bw, bh = W - p.l - p.r, H - p.t - p.b end
      ns.Themes.GradientSliced(gradNines[i], 9, p.g, p.f, nil, bw, bh, p.spec.slice[2])
    end
  end
end

function M.Show(self)
  EnsureSkin()
  Layout()
  FrameShow(self)
end

function M.Hide(self)
  FrameHide(self)
  owner = nil
end

-- A theme switch or recolour (Tooltip.lua hides the tooltip): the next show builds the
-- theme parts again (th.gen differs anyway), so the references to the previous compiled
-- theme are dropped now rather than at that show (only the active one is kept, P5).
local function OnThemeChanged()
  if not frame then return end
  sk, skinTh, skinGen = nil, nil, -1
  wipe(tiledParts)
  wipe(gradNines)
  for i = 1, #seps do seps[i].cfg = false end
end

if ns.RegisterMessage then
  ns.RegisterMessage("THEME_CHANGED", TF, OnThemeChanged)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- The frame, created at the first call (SPEC-themes 4.1).
function TF.Get()
  if frame then return frame end
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetFrameStrata("TOOLTIP")
  frame:SetClampedToScreen(true)
  frame:EnableMouse(false)
  FrameShow, FrameHide = frame.Show, frame.Hide
  FrameHide(frame)
  for k, fn in pairs(M) do frame[k] = fn end
  -- Read-only handles for the offline tests (our own frame).
  tp = { rows = rows, n = 0, seps = seps, nSeps = 0, gauge = segs, icon = nil, panel = {} }
  frame.tp = tp
  TF.frame = frame
  return frame
end
