local ADDON, ns = ...
local C = ns.C

-- BarSkin.lua - the themed drawing of the bar widget (SPEC-themes 2.4, 3.4), used by Bar.lua
-- only. Bar.lua keeps the texts and the behaviour; this file owns every region of the
-- progress line and of the panel, and the measuring FontStrings ("meters").
--
-- Calls (all from Bar.lua):
--   * Init(frame, tex, panel, newMeter) once, at widget creation. `tex` and `panel` are the
--     handle tables frame.tp.tex / frame.tp.panel: Build clears and refills them, keeping
--     their identity (tex.veil, owned by Bar.lua, survives);
--   * Build(th, style) at creation, on a theme change and on a style change: pooled regions
--     are given to the layers of th.bar.layers kept by the style (`when`) and to the panel
--     parts; regions left over are hidden and kept for later builds (regions are created
--     only when a pool is empty, never destroyed);
--   * Layout(ox, oy, W, H, isBar) when the geometry changes: rows of every layer, static
--     layers (track, trackStart, trackEnd, ticks) placed, dynamic ones redrawn by the next
--     Draw;
--   * SetState(k) when the fill state changes (0 normal, 1 rested, 2 max level) and
--     Draw(px, rpx) when px, rpx or the state change - never on a steady tick;
--   * Recolor() after THEME_CHANGED "colors" (compiled colours rewritten in place);
--   * Panel(alpha, w, h) at layout: the panel parts, hidden as a whole at alpha 0; in the
--     box style the FILL insets are moved per side so that the outermost FILL part fits
--     the box (the bar-style insets wrap ornaments the box does not draw);
--   * SetMeterFonts / Measure / Sub: text widths in the font of each text element.
-- Performance: SetState, Draw, Measure and Sub create no table and no closure; a vertex
-- colour or a gradient is set only when its values change (cached per layer), a gradient
-- lazily when its layer is shown (L5); positions are set only when they change.

local math_floor, math_min = math.floor, math.min
local type, tonumber, pairs, ipairs = type, tonumber, pairs, ipairs

local BarSkin = {}
ns.BarSkin = BarSkin

local Themes = ns.Themes

local MASK_WRAP = "CLAMPTOBLACKADDITIVE"

-- spans placed by Layout only (L7); every other span is drawn by Draw
local STATIC_SPAN = { track = true, trackStart = true, trackEnd = true }
-- spans whose colour depends on the fill state even without `base` (maxAlpha in state 2)
local FILL_SPAN = { fill = true, fillEnd = true }
-- panel parts anchored by a point: fractions of the frame size
local ANCHOR_X = { TOPLEFT = 0, TOP = 0.5, TOPRIGHT = 1, LEFT = 0, CENTER = 0.5, RIGHT = 1,
                   BOTTOMLEFT = 0, BOTTOM = 0.5, BOTTOMRIGHT = 1 }
local ANCHOR_Y = { TOPLEFT = 1, TOP = 1, TOPRIGHT = 1, LEFT = 0.5, CENTER = 0.5, RIGHT = 0.5,
                   BOTTOMLEFT = 0, BOTTOM = 0, BOTTOMRIGHT = 0 }
-- measured text elements (SPEC-themes 2.5); the level value and the XP label in split themes only
local METER_BAR = { "s1", "s2", "s3", "level", "levelValue", "xpLabel", "xp", "sep", "marker" }
local METER_BOX = { "s1", "s2", "s3" }
local SPLIT_ONLY = { levelValue = true, xpLabel = true }
local NO_LAYERS = {}

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame, texH, panelH, NewMeter
local rounded = false            -- CreateMaskTexture available: rounded caps
local freePlain, freeMasked = {}, {}   -- hidden textures ready for reuse
local info = {}                  -- [texture] = { owner, layer, sub, blend, fresh, tw, th }

local th                         -- compiled theme of the current build
local style = "bar"
local recOf, partOf = {}, {}     -- [compiled layer / part] = record (current theme only)
local recs, nRecs = {}, 0        -- layer records of the current build, in draw order
local dyns, nDyns = {}, 0        -- the ones Draw looks at
local parts, nParts = {}, 0      -- panel part records of the current build
local capsSpan = {}              -- [span] = true when a `caps` layer of that span is built

local ox, oy, W, H = 0, 0, 0, 0  -- track origin (frame BOTTOMLEFT offsets) and size
local capsOn = false
local px, state = 0, 0
local panelA, panelW, panelHt, panelDirty = 0, 0, 0, true
-- box style: FILL insets moved per side (l, r, t, b) so that the outermost FILL part fits
-- the box frame (bar-style insets wrap ornaments the box does not draw)
local insetShift = { 0, 0, 0, 0 }

local meters = {}                -- measuring FontStrings (pool, never shown: alpha 0)
local mRole, mDelta, nMeters = {}, {}, 0   -- [i] role and size delta of meter i
local meterOf = { bar = {}, box = {} }     -- [style][element] = meter index

local xpKey, restKey = nil, nil  -- user colours the skin was last synced with

---------------------------------------------------------------------------
-- Region pools
---------------------------------------------------------------------------

-- A hidden texture for `owner` (a compiled layer or panel part). A free texture last used
-- by the same owner comes first and needs no reset; any other free one is reset (B1) and
-- gets its file again. Masked textures (caps ends) live in their own pool.
local function Get(owner, layer, sub, masked)
  local pool = masked and freeMasked or freePlain
  local n = #pool
  if n == 0 then
    local t = frame:CreateTexture(nil, layer, nil, sub)
    if masked then
      local m = frame:CreateMaskTexture()
      m:SetTexture(C.TEX_CIRCLE_MASK, MASK_WRAP, MASK_WRAP)
      m:SetAllPoints(t)
      t:AddMaskTexture(m)
    end
    t:Hide()
    info[t] = { owner = owner, layer = layer, sub = sub, blend = "BLEND", fresh = true, tw = -1, th = -1 }
    return t
  end
  local k = n
  for i = n, 1, -1 do
    if info[pool[i]].owner == owner then
      k = i
      break
    end
  end
  local t = pool[k]
  pool[k] = pool[n]
  pool[n] = nil
  local I = info[t]
  if I.owner ~= owner then
    t:ClearAllPoints()
    t:SetTexCoord(0, 1, 0, 1)
    t:SetBlendMode("BLEND")
    I.owner, I.blend, I.fresh, I.tw, I.th = owner, "BLEND", true, -1, -1
  end
  if I.layer ~= layer or I.sub ~= sub then
    t:SetDrawLayer(layer, sub)
    I.layer, I.sub = layer, sub
  end
  return t
end

local function Put(t, masked)
  t:Hide()
  local pool = masked and freeMasked or freePlain
  pool[#pool + 1] = t
end

-- File, coordinates and blend mode of a texture just taken from the pool (never a colour).
local function Setup(t, spec, blend)
  local I = info[t]
  if I.fresh and spec then
    I.fresh = false
    Themes.SetTex(t, spec)                       -- sets the spec's blend mode too
    I.blend = spec.blend or "BLEND"
  end
  blend = blend or "BLEND"
  if I.blend ~= blend then
    I.blend = blend
    t:SetBlendMode(blend)
  end
end

---------------------------------------------------------------------------
-- Records (one per built layer or panel part)
---------------------------------------------------------------------------

local function NewRec(L)
  local kind = L.kind or "tex"
  local span = L.span or "track"
  local R = {
    L = L, kind = kind, span = span, on = false, shown = false, n = 0,
    stateful = (L.dyn or FILL_SPAN[span]) and true or false,
    x0 = false, x1 = false, y0 = 0, y1 = 0,
    cr = false, cg = false, cb = false, ca = false,
    gv = {}, gdirty = true, gpair = {},
  }
  if kind == "three" or kind == "nine" or kind == "ticks" then R.list = {} end
  if kind == "ticks" then
    R.xs, R.vis = {}, {}
    R.dynamic = L.ticks ~= nil and L.ticks.clip == "fill"
  else
    R.dynamic = not STATIC_SPAN[span]
  end
  return R
end

-- N - 1 ticks between the N parts, or N at their middles (`mid`).
local function TickCount(L)
  local tk = L.ticks
  local n = tk and tonumber(tk.n) or 0
  n = math_floor(n)
  if not (tk and tk.mid) then n = n - 1 end
  return n > 0 and n or 0
end

-- Textures of a record from the pools (all hidden); colours and gradients start over.
local function Acquire(R, defLayer, defSub)
  local L = R.L
  local layer, sub = L.layer or defLayer, L.sub or defSub
  local spec, kind = L.tex, R.kind
  local blend = spec and spec.blend
  if kind == "tex" then
    R.t = Get(L, layer, sub, false)
    Setup(R.t, spec, blend)
  elseif kind == "caps" then
    R.t1 = Get(L, layer, sub, rounded)
    R.t2 = Get(L, layer, sub, false)
    R.t3 = Get(L, layer, sub, rounded)
    Setup(R.t1, spec, blend)
    Setup(R.t2, spec, blend)
    Setup(R.t3, spec, blend)
  else
    local n = (kind == "three" and 3) or (kind == "nine" and 9) or TickCount(L)
    local list = R.list
    for i = 1, n do
      local t = Get(L, layer, sub, false)
      Setup(t, spec, blend)
      list[i] = t
    end
    R.n = n
  end
  R.on, R.shown, R.x0, R.x1 = true, false, false, false
  R.cr, R.cg, R.cb, R.ca, R.gdirty = false, false, false, false, true
  R.sw, R.sh = false, false
  local gv = R.gv
  for i = 1, 8 do gv[i] = false end
end

local function Release(R)
  if not R.on then return end
  R.on, R.shown = false, false
  local kind = R.kind
  if kind == "tex" then
    Put(R.t, false)
    R.t = nil
  elseif kind == "caps" then
    Put(R.t1, rounded)
    Put(R.t2, false)
    Put(R.t3, rounded)
    R.t1, R.t2, R.t3 = nil, nil, nil
  else
    local list = R.list
    for i = 1, R.n do
      Put(list[i], false)
      list[i] = nil
    end
    R.n = 0
  end
end

local function HideAll(R)
  local kind = R.kind
  if kind == "tex" then
    R.t:Hide()
  elseif kind == "caps" then
    R.t1:Hide(); R.t2:Hide(); R.t3:Hide()
  else
    local list = R.list
    for i = 1, R.n do list[i]:Hide() end
  end
end

---------------------------------------------------------------------------
-- Colours (L5, L6)
---------------------------------------------------------------------------

local function EachVertex(R, r, g, b, a)
  local kind = R.kind
  if kind == "tex" then
    R.t:SetVertexColor(r, g, b, a)
  elseif kind == "caps" then
    R.t1:SetVertexColor(r, g, b, a)
    R.t2:SetVertexColor(r, g, b, a)
    R.t3:SetVertexColor(r, g, b, a)
  else
    local list = R.list
    for i = 1, R.n do list[i]:SetVertexColor(r, g, b, a) end
  end
end

-- L6 (Themes.Gradient): SetGradient with colour tables, else SetGradientAlpha, else the
-- flat colour. `pair` = { from, to, dir = }. A 3-slice or a 9-slice placed at least once
-- gets one ramp across its pieces (Themes.GradientSliced), not the ramp on every piece.
local function EachGrad(R, pair, flat)
  local Gradient = Themes.Gradient
  local kind = R.kind
  if kind == "tex" then
    Gradient(R.t, pair, flat)
  elseif kind == "caps" then
    Gradient(R.t1, pair, flat)
    Gradient(R.t2, pair, flat)
    Gradient(R.t3, pair, flat)
  elseif (kind == "three" or kind == "nine") and R.sw then
    local slice = R.L.tex and R.L.tex.slice
    Themes.GradientSliced(R.list, R.n, pair, flat, nil, R.sw, R.sh, slice and slice[2] or 0)
  else
    local list = R.list
    for i = 1, R.n do Gradient(list[i], pair, flat) end
  end
end

-- Fill state whose colours a layer shows: the current one for the layers that follow the
-- fill state (`base` used, or a fill span), else 0.
local function StateOf(R)
  return R.stateful and state or 0
end

-- Alpha factor of state 2 over state 0 (SPEC-themes 2.8): the layer's own (m), else the
-- bar's maxAlpha on a fill span, else none.
local function MaxAlpha(R)
  local m = R.L.m
  if m == nil and FILL_SPAN[R.span] then m = th.bar.maxAlpha end
  return m
end

-- Compiled colours of state k (SPEC-themes 2.8): an entry is one colour (or one gradient
-- pair { from, to, dir = }) for every state, or a per-state list; a state 2 without an
-- entry of its own is state 0 with its alpha scaled by MaxAlpha, written into tables of
-- the record (created once, at the first use: never on a steady tick).
local function StateColor(R, x, k, key)
  local c = x
  if type(x[1]) == "table" then
    c = x[k + 1]
    if c then return c end
    c = x[1]
  end
  local m = k == 2 and MaxAlpha(R)
  if not m then return c end
  local own = R[key]
  if not own then
    own = { 0, 0, 0, 0 }
    R[key] = own
  end
  own[1], own[2], own[3], own[4] = c[1], c[2], c[3], c[4] * m
  return own
end

local function StatePair(R, g, k)
  local p = g
  if type(g[1][1]) == "table" then
    p = g[k + 1]
    if p then return p end
    p = g[1]
  end
  local m = k == 2 and MaxAlpha(R)
  if not m then return p end
  local own = R.ownPair
  if not own then
    own = { { 0, 0, 0, 0 }, { 0, 0, 0, 0 } }
    R.ownPair = own
  end
  local f, t, of, ot = p[1], p[2], own[1], own[2]
  of[1], of[2], of[3], of[4] = f[1], f[2], f[3], f[4] * m
  ot[1], ot[2], ot[3], ot[4] = t[1], t[2], t[3], t[4] * m
  own.dir = p.dir
  return own
end

local function ApplyGradient(R)
  R.gdirty = false
  local L = R.L
  local k = StateOf(R)
  local pair = StatePair(R, L.g, k)
  if pair.dir == nil then pair = R.gpair end    -- (a pair without its direction)
  EachGrad(R, pair, L.f and StateColor(R, L.f, k, "ownFlat") or pair[1])
end

-- Vertex colour (or gradient) of the current state, set only when its values changed;
-- a changed gradient waits until the layer is shown (L5).
local function ApplyColor(R)
  local L = R.L
  local k = StateOf(R)
  if L.g then
    local pair = StatePair(R, L.g, k)
    local f, t, v = pair[1], pair[2], R.gv
    if v[1] ~= f[1] or v[2] ~= f[2] or v[3] ~= f[3] or v[4] ~= f[4]
        or v[5] ~= t[1] or v[6] ~= t[2] or v[7] ~= t[3] or v[8] ~= t[4] then
      v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8] = f[1], f[2], f[3], f[4], t[1], t[2], t[3], t[4]
      R.gdirty = true
      if pair.dir == nil then
        local gp = R.gpair
        gp[1], gp[2], gp.dir = f, t, L.g.dir
      end
    end
    if R.gdirty and R.shown then ApplyGradient(R) end
    return
  end
  local c = L.c and StateColor(R, L.c, k, "ownColor")
  if not c then return end
  local r, g, b, a = c[1], c[2], c[3], c[4] or 1
  if r ~= R.cr or g ~= R.cg or b ~= R.cb or a ~= R.ca then
    R.cr, R.cg, R.cb, R.ca = r, g, b, a
    EachVertex(R, r, g, b, a)
  end
end

---------------------------------------------------------------------------
-- Geometry (L1..L4, L7); x in track space, rows from the track's top edge
---------------------------------------------------------------------------

local function Place(t, x, y)
  t:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, y)
end

-- One texture over w x h at (x, y) from the frame's BOTTOMLEFT; tiled art gets its repeat
-- coordinates again only when its size changed.
local function PlaceOne(t, spec, x, y, w, h)
  t:SetSize(w, h)
  Place(t, x, y)
  if spec and spec.tile then
    local I = info[t]
    if I.tw ~= w or I.th ~= h then
      I.tw, I.th = w, h
      Themes.Tile(t, spec, w, h)
    end
  end
  t:Show()
end

local function Rows(R)
  local L = R.L
  local band = L.band
  local y0, y1
  if band then
    y0 = math_floor(band[1] * H + 0.5)
    y1 = math_floor(band[2] * H + 0.5)
  else
    y0 = L.top or 0
    if L.h then y1 = y0 + L.h else y1 = H - (L.bottom or 0) end
  end
  R.y0, R.y1 = y0, y1
end

-- Range spans: [a, b] shrunk by half the track height on each side under drawn caps of the
-- same span (capInset), then widened by `pad`.
local function RangeX(L, a, b)
  if L.capInset and capsOn and capsSpan[L.span] and b - a >= H then
    local h2 = math_floor(H / 2)
    a, b = a + h2, b - h2
  end
  local pad = L.pad
  if pad then a, b = a - (pad[1] or 0), b + (pad[2] or 0) end
  return a, b
end

-- Anchor spans: a `w` wide box centred on, ending at or starting at the anchor, plus dx.
local function AnchorX(L, at)
  local w = L.w or 0
  local align = L.align
  local x
  if align == "right" then
    x = at - w
  elseif align == "left" then
    x = at
  else
    x = at - math_floor(w / 2)
  end
  x = x + (L.dx or 0)
  return x, x + w
end

-- Size of a 3-slice / 9-slice record: a gradient that runs across its cuts (any on a
-- 9-slice, a horizontal one on a 3-slice) depends on it and is applied again after a
-- resize (Show), never on a steady tick.
local function SlicedSize(R, w, h)
  if R.sw == w and R.sh == h then return end
  R.sw, R.sh = w, h
  local g = R.L.g
  if g and (R.kind == "nine" or g.dir == "HORIZONTAL") then R.gdirty = true end
end

local function PlaceRec(R, x0, x1)
  local L = R.L
  local h = R.y1 - R.y0
  local w = x1 - x0
  local x, y = ox + x0, oy + H - R.y1
  local kind = R.kind
  if kind == "tex" then
    PlaceOne(R.t, L.tex, x, y, w, h)
  elseif kind == "caps" then
    -- L3: rounded ends (h x h discs) when the range is wide enough, else one flat piece
    local t1, t2, t3 = R.t1, R.t2, R.t3
    if capsOn and w >= h then
      local h2 = math_floor(h / 2)
      t1:SetSize(h, h); Place(t1, x, y); t1:Show()
      t3:SetSize(h, h); Place(t3, x + w - h, y); t3:Show()
      local mw = w - 2 * h2
      if mw > 0 then
        t2:SetSize(mw, h); Place(t2, x + h2, y); t2:Show()
      else
        t2:Hide()
      end
    else
      t1:Hide(); t3:Hide()
      t2:SetSize(w, h); Place(t2, x, y); t2:Show()
    end
  elseif kind == "three" then
    Themes.PlaceThree(R.list, L.tex, frame, x, y, w, h)   -- shows / hides each piece
    SlicedSize(R, w, h)
  elseif kind == "nine" then
    Themes.PlaceNine(R.list, L.tex, frame, x, y, w, h)
    SlicedSize(R, w, h)
  end
end

-- Shows R over [x0, x1] (moved only when that changed) or hides it (L2); a gradient waiting
-- for the layer is applied when it is shown (L5).
local function Show(R, vis, x0, x1)
  if vis and x1 > x0 and R.y1 > R.y0 then
    if R.shown and x0 == R.x0 and x1 == R.x1 then return end
    R.x0, R.x1 = x0, x1
    PlaceRec(R, x0, x1)
    R.shown = true
    if R.gdirty and R.L.g then ApplyGradient(R) end      -- first show, or a resized slice
  elseif R.shown then
    R.shown, R.x0, R.x1 = false, false, false
    HideAll(R)
  end
end

-- Ticks i = 1..N-1 at floor(W*i/N + 0.5) - floor(w/2) (`mid`: i = 1..N at the middles,
-- floor(W*(2i-1)/(2N) + 0.5) - floor(w/2)): placed at layout; clipped ones are shown by
-- Draw (only when their visibility flips).
local function PlaceTicks(R)
  local tk = R.L.ticks
  local n, tw = tonumber(tk.n) or 1, tk.w or 1
  local half = math_floor(tw / 2)
  local mid = tk.mid
  local h, y = R.y1 - R.y0, oy + H - R.y1
  local list, xs, vis = R.list, R.xs, R.vis
  local clip = R.dynamic
  local ok = h > 0 and tw > 0
  for i = 1, R.n do
    local t = list[i]
    local x
    if mid then
      x = math_floor(W * (2 * i - 1) / (2 * n) + 0.5) - half
    else
      x = math_floor(W * i / n + 0.5) - half
    end
    xs[i] = x
    if ok then
      t:SetSize(tw, h)
      Place(t, ox + x, y)
    end
    if clip then
      vis[i] = false
      t:Hide()
    elseif ok then
      t:Show()
    else
      t:Hide()
    end
  end
  R.shown = ok
  if not ok then
    for i = 1, R.n do xs[i] = W + 1 end   -- never shown by Draw
  end
  if ok and R.gdirty and R.L.g then ApplyGradient(R) end
end

local function ClipTicks(R)
  local list, xs, vis = R.list, R.xs, R.vis
  for i = 1, R.n do
    local on = px > 0 and xs[i] < px
    if on ~= vis[i] then
      vis[i] = on
      if on then list[i]:Show() else list[i]:Hide() end
    end
  end
end

---------------------------------------------------------------------------
-- Panel parts (2.4.2, B7)
---------------------------------------------------------------------------

local function PartAlpha(P, a)
  local mode = P.alpha
  if mode == "bg" then return a end
  if mode == "line" then return math_min(1, 2 * a) end
  return tonumber(mode) or 1
end

-- Colour of a part: its colour alpha (or gradient alphas) times its alpha factor. The
-- scaled gradient tables are the record's own (created with it).
local function PartColor(R, a)
  local P = R.L
  local f = PartAlpha(P, a)
  local g = P.g
  if g then
    local from, to, gp = g[1], g[2], R.gpair
    local gf, gt = gp[1], gp[2]
    gf[1], gf[2], gf[3], gf[4] = from[1], from[2], from[3], from[4] * f
    gt[1], gt[2], gt[3], gt[4] = to[1], to[2], to[3], to[4] * f
    gp.dir = g.dir
    local fl, flat = P.f, R.gflat
    if fl then
      flat[1], flat[2], flat[3], flat[4] = fl[1], fl[2], fl[3], (fl[4] or 1) * f
    else
      flat[1], flat[2], flat[3], flat[4] = gf[1], gf[2], gf[3], gf[4]
    end
    EachGrad(R, gp, flat)
    return
  end
  local c = P.c
  if c then EachVertex(R, c[1], c[2], c[3], (c[4] or 1) * f) end
end

local function PlacePart(R, fw, fh)
  local P = R.L
  local anchor = P.anchor or "FILL"
  local x, y, w, h
  if anchor == "FILL" then
    local ins = P.inset
    local l, r, t, b = 0, 0, 0, 0
    if ins then
      l, r = ins[1] or ins.l or 0, ins[2] or ins.r or 0
      t, b = ins[3] or ins.t or 0, ins[4] or ins.b or 0
    end
    local sh = insetShift
    l, r, t, b = l + sh[1], r + sh[2], t + sh[3], b + sh[4]
    x, y, w, h = l, b, fw - l - r, fh - t - b
  else
    w, h = P.w or 0, P.h or 0
    local fx, fy = ANCHOR_X[anchor] or 0, ANCHOR_Y[anchor] or 0
    x = fw * fx + (P.x or 0) - w * fx
    y = fh * fy + (P.y or 0) - h * fy
  end
  if w <= 0 or h <= 0 then
    HideAll(R)
    return
  end
  if R.kind == "nine" then
    Themes.PlaceNine(R.list, P.tex, frame, x, y, w, h)
    R.sw, R.sh = w, h                            -- PartColor follows (sliced gradient)
  else
    PlaceOne(R.t, P.tex, x, y, w, h)
  end
end

-- place = false: colours only (THEME_CHANGED "colors": no geometry work).
local function ApplyPanel(place)
  panelDirty = false
  local a = panelA
  for i = 1, nParts do
    local R = parts[i]
    if a <= 0 then
      HideAll(R)
    else
      if place then PlacePart(R, panelW, panelHt) end
      PartColor(R, a)
    end
  end
end

local function BuildPanel()
  for k in pairs(panelH) do panelH[k] = nil end
  local p = th.bar and th.bar.panel
  local list = type(p) == "table" and p.parts or nil
  local n = 0
  if list then
    for i, P in ipairs(list) do
      local R = partOf[P]
      if not R then
        R = NewRec(P)
        R.gpair[1], R.gpair[2] = { 0, 0, 0, 0 }, { 0, 0, 0, 0 }
        R.gflat = { 0, 0, 0, 0 }
        partOf[P] = R
      end
      if not R.on then Acquire(R, "BACKGROUND", -8 + i - 1) end
      n = n + 1
      parts[n] = R
      if P.id then panelH[P.id] = (R.kind == "nine") and R.list or R.t end
    end
  end
  for i = n + 1, nParts do parts[i] = nil end
  nParts = n
  local sh = insetShift
  sh[1], sh[2], sh[3], sh[4] = 0, 0, 0, 0
  if style == "box" then
    local m1, m2, m3, m4 = nil, nil, nil, nil
    for i = 1, n do
      local P = parts[i].L
      local ins = P.inset
      if (P.anchor or "FILL") == "FILL" then
        local l, r = ins and (ins[1] or ins.l) or 0, ins and (ins[2] or ins.r) or 0
        local t, b = ins and (ins[3] or ins.t) or 0, ins and (ins[4] or ins.b) or 0
        if not m1 or l < m1 then m1 = l end
        if not m2 or r < m2 then m2 = r end
        if not m3 or t < m3 then m3 = t end
        if not m4 or b < m4 then m4 = b end
      end
    end
    if m1 then sh[1], sh[2], sh[3], sh[4] = -m1, -m2, -m3, -m4 end
  end
  panelDirty = true
end

---------------------------------------------------------------------------
-- Meters: one invisible FontString per (role, size delta) of the theme's measured texts
---------------------------------------------------------------------------

local function MeterIndex(role, delta)
  for i = 1, nMeters do
    if mRole[i] == role and mDelta[i] == delta then return i end
  end
  local i = nMeters + 1
  nMeters = i
  mRole[i], mDelta[i] = role, delta
  if not meters[i] then meters[i] = NewMeter() end
  return i
end

-- Bar elements first, then box: under the classic theme this gives the three meters of
-- the classic look (font + 2, font, font - 1), each element measured in its own font.
local function AssignMeters()
  local text = th.text
  local font, size, boxSize = text.font, text.size, text.boxSize
  local split = text.split
  nMeters = 0
  local bar, box = meterOf.bar, meterOf.box
  for k in pairs(bar) do bar[k] = nil end
  for i = 1, #METER_BAR do
    local e = METER_BAR[i]
    if split or not SPLIT_ONLY[e] then
      bar[e] = MeterIndex(font[e] or "body", size[e] or 0)
    end
  end
  for i = 1, #METER_BOX do
    local e = METER_BOX[i]
    box[e] = MeterIndex(font[e] or "body", boxSize[e] or 0)
  end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function BarSkin.Init(f, texTable, panelTable, newMeter)
  frame, texH, panelH, NewMeter = f, texTable, panelTable, newMeter
  rounded = type(f.CreateMaskTexture) == "function"
end

function BarSkin.Build(newTh, newStyle)
  if newTh ~= th then
    for L, R in pairs(recOf) do
      Release(R)
      recOf[L] = nil
    end
    for P, R in pairs(partOf) do
      Release(R)
      partOf[P] = nil
    end
    for _, I in pairs(info) do I.owner = false end   -- nothing keeps the old theme (P5)
    th = newTh
    AssignMeters()
  end
  style = newStyle
  for k in pairs(capsSpan) do capsSpan[k] = nil end
  local layers = th.bar and th.bar.layers or NO_LAYERS
  local n, nd = 0, 0
  for i = 1, #layers do
    local L = layers[i]
    local R = recOf[L]
    if L.when == nil or L.when == style then
      if not R then
        R = NewRec(L)
        recOf[L] = R
      end
      if not R.on then Acquire(R, "ARTWORK", 0) end
      n = n + 1
      recs[n] = R
      if R.dynamic then
        nd = nd + 1
        dyns[nd] = R
      end
      if R.kind == "caps" then capsSpan[R.span] = true end
    elseif R then
      Release(R)
    end
  end
  for i = n + 1, nRecs do recs[i] = nil end
  for i = nd + 1, nDyns do dyns[i] = nil end
  nRecs, nDyns = n, nd

  -- handles: frame.tp.tex[id] (caps / three: id .. "L" / "M" / "R"; nine / ticks: arrays)
  for k in pairs(texH) do
    if k ~= "veil" then texH[k] = nil end
  end
  for i = 1, nRecs do
    local R = recs[i]
    local id, kind = R.L.id, R.kind
    if id then
      if kind == "tex" then
        texH[id] = R.t
      elseif kind == "caps" then
        texH[id .. "L"], texH[id .. "M"], texH[id .. "R"] = R.t1, R.t2, R.t3
      elseif kind == "three" then
        local list = R.list
        texH[id .. "L"], texH[id .. "M"], texH[id .. "R"] = list[1], list[2], list[3]
      else
        texH[id] = R.list
      end
    end
  end
  for i = 1, nRecs do ApplyColor(recs[i]) end
  BuildPanel()
end

function BarSkin.Layout(x, y, w, h, isBar)
  ox, oy, W, H = x, y, w, h
  capsOn = rounded and isBar and true or false
  for i = 1, nRecs do
    local R = recs[i]
    Rows(R)
    R.x0, R.x1 = false, false
    local L, span = R.L, R.span
    if R.kind == "ticks" then
      PlaceTicks(R)
    elseif span == "track" then
      local a, b = RangeX(L, 0, W)
      Show(R, true, a, b)
    elseif span == "trackStart" then
      local a, b = AnchorX(L, 0)
      Show(R, true, a, b)
    elseif span == "trackEnd" then
      local a, b = AnchorX(L, W)
      Show(R, true, a, b)
    end
  end
end

function BarSkin.SetState(k)
  state = k
  for i = 1, nRecs do
    local R = recs[i]
    if R.stateful then ApplyColor(R) end
  end
end

function BarSkin.Draw(p, r)
  px = p
  for i = 1, nDyns do
    local R = dyns[i]
    local span = R.span
    if R.kind == "ticks" then
      ClipTicks(R)
    elseif span == "fill" then
      local a, b = RangeX(R.L, 0, p)
      Show(R, p > 0, a, b)
    elseif span == "rested" then
      local a, b = RangeX(R.L, p, r)
      Show(R, r > p, a, b)
    elseif span == "fillEnd" then
      local a, b = AnchorX(R.L, p)
      Show(R, p > 0 and p < W and state ~= 2, a, b)
    elseif span == "restEnd" then
      local a, b = AnchorX(R.L, r)
      Show(R, r > p, a, b)
    end
  end
end

function BarSkin.Recolor()
  for i = 1, nRecs do ApplyColor(recs[i]) end
  if nParts > 0 and not panelDirty then ApplyPanel(false) end
end

-- Panel parts: hidden at alpha 0, else placed on the w x h frame and coloured (only when
-- the alpha, the size, the theme or its colours changed).
function BarSkin.Panel(a, w, h)
  if not panelDirty and a == panelA and w == panelW and h == panelHt then return end
  panelA, panelW, panelHt = a, w, h
  ApplyPanel(true)
end

function BarSkin.SetMeterFonts(fontSize, outline)
  for i = 1, nMeters do
    Themes.SetFont(meters[i], mRole[i], fontSize + mDelta[i], outline)
  end
end

-- Width of `text` in the font of element e (style "bar" or "box"), measured on a meter.
function BarSkin.Measure(e, box, text)
  local m = meters[(box and meterOf.box or meterOf.bar)[e] or 1]
  if not m then return 0 end
  m:SetText(text)
  return m:GetStringWidth() or 0
end

-- `text` as drawn by element e: the font's substitutions (2.6); the same string without any.
function BarSkin.Sub(e, text)
  local role = th and th.text.font[e]
  if role and text and Themes.HasSubst(role) then return Themes.Subst(role, text) end
  return text
end

-- Stored XP / rested colours ({ r, g, b } or false) as integer keys: true when they differ
-- from the last call. Bar.lua notices with it a settings table replaced behind Themes' back.
local function Unit(x)
  x = tonumber(x)
  if not x or x ~= x or x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function ColorKey(v)
  if type(v) ~= "table" then return -1 end
  local r, g, b = v[1], v[2], v[3]
  if r == nil and g == nil and b == nil then r, g, b = v.r, v.g, v.b end
  if not (tonumber(r) and tonumber(g) and tonumber(b)) then return -1 end
  -- base 1001: components 0..1000, no two colours share a key
  return (math_floor(Unit(r) * 1000 + 0.5) * 1001 + math_floor(Unit(g) * 1000 + 0.5)) * 1001
    + math_floor(Unit(b) * 1000 + 0.5)
end

function BarSkin.SyncUserColors(w)
  local xk, rk = ColorKey(w.xpColor), ColorKey(w.restedColor)
  local changed = xk ~= xpKey or rk ~= restKey
  xpKey, restKey = xk, rk
  return changed
end
