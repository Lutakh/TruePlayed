-- tests/theme_validate.lua - the theme validator (test-only code, design/NEXT-LOT.md M2).
--
-- The shipped compiler (Themes.lua) stays robust: it falls back on bad data and says
-- nothing. The warnings live here: this file is the round-4 compiler of Themes.lua, moved
-- out of the addon unchanged (same parse, same fallbacks, the same warning texts) and run
-- on the theme source. It also returns the compiled theme in the round-4 form, so that
-- the tests can check that the compact compiled form of the addon carries the same
-- values (Canon below).
--
-- Use (from a test, after Stub.LoadAddon):
--   local TV = dofile(Stub.ROOT .. "tests/theme_validate.lua")
--   TV.Install(ns)        -- ns.Themes.Compile(key) then returns th, warnings (a list)
--   TV.Compile(ns, key, builder) -> legacyTh, warnings   (builder: () -> source table)
--   TV.Canon(th)          -- either form -> the canonical drawn values (see Canon)
-- Never loaded by the addon (not in the TOC); written for Lua 5.1 and 5.5.
local TV = {}

-- Set from the namespace before every compile (TV.Compile).
local ns, C, Themes, FONTS, COMMON_MEDIA, MEDIA_ROOT, WHITE

local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring
local pcall = pcall
local math_floor, math_min, math_max = math.floor, math.min, math.max
local string_find, string_sub = string.find, string.sub
local string_match, string_format = string.match, string.format

---------------------------------------------------------------------------
-- Colours: hybrid tables (the round-4 compiled form)
---------------------------------------------------------------------------
local function NewColor(r, g, b, a)
  r, g, b, a = r or 0, g or 0, b or 0, a or 1
  return { r, g, b, a, r = r, g = g, b = b, a = a }
end

local function SetColor4(t, r, g, b, a)
  t[1], t[2], t[3], t[4] = r, g, b, a
  t.r, t.g, t.b, t.a = r, g, b, a
end

local function Byte255(x)
  return math_floor(math_min(1, math_max(0, x or 0)) * 255 + 0.5)
end

-- "|cffrrggbb" of a colour (tooltip ccDim).
local function ColorCode(c)
  return string_format("|cff%02x%02x%02x", Byte255(c[1]), Byte255(c[2]), Byte255(c[3]))
end

---------------------------------------------------------------------------
-- Colour expressions (2.3). Parsed into nodes at compile time:
--   { kind, r, g, b, a (K_LIT), name / ref (K_NAME), mods = { op, k, ... }, alpha,
--     uXp, uRested, uBase (the dynamic sources the evaluation may read), bad }
-- Evaluation reads E (user colours and the program being run) and allocates nothing.
---------------------------------------------------------------------------
local K_LIT, K_XP, K_RESTED, K_BASE, K_NAME = 1, 2, 3, 4, 5
local WHITE_NODE = { kind = K_LIT, r = 1, g = 1, b = 1, a = 1 }

-- Evaluation state: user colours (widget.xpColor / widget.restedColor) and the program.
local E = { xpOn = false, xr = 0, xg = 0, xb = 0, rsOn = false, rr = 0, rg = 0, rb = 0, prog = nil }

local Eval
Eval = function(node, k)
  local r, g, b, a
  local kind = node.kind
  if node.bad then
    r, g, b, a = 1, 1, 1, 1
  elseif kind == K_LIT then
    r, g, b, a = node.r, node.g, node.b, node.a
  elseif kind == K_NAME then
    r, g, b, a = Eval(node.ref, k)
  elseif kind == K_RESTED or (kind == K_BASE and k == 1) then
    if E.rsOn then r, g, b, a = E.rr, E.rg, E.rb, 1 else r, g, b, a = Eval(E.prog.rested, k) end
  else                                           -- K_XP, or K_BASE in states 0 and 2
    if E.xpOn then r, g, b, a = E.xr, E.xg, E.xb, 1 else r, g, b, a = Eval(E.prog.xp, k) end
  end
  local mods = node.mods
  if mods then
    for i = 1, #mods, 2 do
      local x = mods[i + 1]
      if mods[i] > 0 then
        r, g, b = r + (1 - r) * x, g + (1 - g) * x, b + (1 - b) * x   -- lighten
      else
        r, g, b = r * (1 - x), g * (1 - x), b * (1 - x)               -- darken
      end
    end
  end
  if node.alpha then a = node.alpha end
  return r, g, b, a
end

-- Does the evaluation of `node` in fill state k read a user colour? (`def` rule)
local function UsesUser(node, k)
  if node.uXp and E.xpOn then return true end
  if node.uRested and E.rsOn then return true end
  if node.uBase then
    if k == 1 then return E.rsOn end
    return E.xpOn
  end
  return false
end

-- A compiled colour slot: out = the hybrid table, node / def, k = fill state, f = factor.
local function WriteSlot(s)
  local node, k = s.node, s.k
  local r, g, b, a
  if s.def and not UsesUser(node, k) then
    r, g, b, a = Eval(s.def, k)
  else
    r, g, b, a = Eval(node, k)
  end
  SetColor4(s.out, r, g, b, a * s.f)
end

-- Rewrites every colour of a compiled theme in place from the current E.
local function RunProgram(prog)
  E.prog = prog
  local slots = prog.slots
  for i = 1, #slots do WriteSlot(slots[i]) end
  local tc = prog.ccDimOf
  if tc then tc.ccDim = ColorCode(tc.dim) end    -- only when the tooltip dim is dynamic
  E.prog = nil
  prog.xpOn, prog.xr, prog.xg, prog.xb = E.xpOn, E.xr, E.xg, E.xb
  prog.rsOn, prog.rr, prog.rg, prog.rb = E.rsOn, E.rr, E.rg, E.rb
end

local function Unit(x)
  if x ~= x or x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

-- { r, g, b } (or { r =, g =, b = }) -> three numbers, or nil (false / invalid).
local function ReadRGB(v)
  if type(v) ~= "table" then return nil end
  local r, g, b = v[1], v[2], v[3]
  if r == nil and g == nil and b == nil then r, g, b = v.r, v.g, v.b end
  r, g, b = tonumber(r), tonumber(g), tonumber(b)
  if not (r and g and b) then return nil end
  return Unit(r), Unit(g), Unit(b)
end

-- Reads widget.xpColor / widget.restedColor into E.
local function ReadUserColors()
  local s = ns.settings
  local w = type(s) == "table" and s.widget or nil
  local xr, xg, xb, rr, rg, rb
  if type(w) == "table" then
    xr, xg, xb = ReadRGB(w.xpColor)
    rr, rg, rb = ReadRGB(w.restedColor)
  end
  E.xpOn, E.rsOn = xr ~= nil, rr ~= nil
  E.xr, E.xg, E.xb = xr or 0, xg or 0, xb or 0
  E.rr, E.rg, E.rb = rr or 0, rg or 0, rb or 0
end

---------------------------------------------------------------------------
-- Compiler helpers (compile time only: these allocate)
---------------------------------------------------------------------------
local function Set(list)
  local t = {}
  for i = 1, #list do t[list[i]] = true end
  return t
end

local function Warn(ctx, fmt, ...)
  local w = ctx.warnings
  w[#w + 1] = ctx.key .. ": " .. string_format(fmt, ...)
end

local function CheckFields(ctx, t, allowed, where)
  for k in pairs(t) do
    if not allowed[k] then Warn(ctx, "%s: unknown field '%s'", where, tostring(k)) end
  end
end

local function IsNum(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A number field: the value, or `def` (with a warning when present but invalid).
local function Num(ctx, v, def, where, lo, hi, int)
  if v == nil then return def end
  if not IsNum(v) or (lo and v < lo) or (hi and v > hi) or (int and v % 1 ~= 0) then
    Warn(ctx, "%s: invalid number %s", where, tostring(v))
    return def
  end
  return v
end

local function Choice(ctx, v, def, set, where)
  if v == nil then return def end
  if not set[v] then
    Warn(ctx, "%s: invalid value %s", where, tostring(v))
    return def
  end
  return v
end

local function IsPow2(n)
  if not IsNum(n) or n < 1 or n > 256 or n % 1 ~= 0 then return false end
  while n > 1 do
    if n % 2 ~= 0 then return false end
    n = n / 2
  end
  return true
end

-- One colour expression -> node (nil after a warning).
local function ParseExpr(ctx, s, where, allowBase)
  local node = { kind = K_LIT, r = 1, g = 1, b = 1, a = 1 }
  local rest
  local hex = string_match(s, "^#(%x+)")
  if hex then
    if #hex ~= 6 and #hex ~= 8 then
      Warn(ctx, "%s: '%s' needs 6 or 8 hex digits", where, s)
      return nil
    end
    node.r = tonumber(string_sub(hex, 1, 2), 16) / 255
    node.g = tonumber(string_sub(hex, 3, 4), 16) / 255
    node.b = tonumber(string_sub(hex, 5, 6), 16) / 255
    node.a = (#hex == 8) and tonumber(string_sub(hex, 7, 8), 16) / 255 or 1
    rest = string_sub(s, #hex + 2)
  else
    local name = string_match(s, "^([%a_][%w_]*)")
    if not name then
      Warn(ctx, "%s: '%s' is not a colour", where, s)
      return nil
    end
    rest = string_sub(s, #name + 1)
    if name == "none" then
      node.r, node.g, node.b, node.a = 0, 0, 0, 0
    elseif name == "xp" then
      node.kind, node.uXp = K_XP, true
    elseif name == "rested" then
      node.kind, node.uRested = K_RESTED, true
    elseif name == "base" then
      if not allowBase then
        Warn(ctx, "%s: 'base' is only valid in bar.layers", where)
        return nil
      end
      node.kind, node.uBase = K_BASE, true
    else
      node.kind, node.name = K_NAME, name
    end
  end
  local pos, n = 1, #rest
  while pos <= n do
    local op, num, nextPos = string_match(rest, "^([%+%-@])([%d%.]+)()", pos)
    local x = num and tonumber(num)
    if not op or not x or x < 0 or x > 1 then
      Warn(ctx, "%s: bad modifier in '%s' (+k, -k, @a with k, a in 0..1)", where, s)
      return nil
    end
    if op == "@" then
      if nextPos <= n then
        Warn(ctx, "%s: '@' must come last in '%s'", where, s)
        return nil
      end
      node.alpha = x
    else
      local mods = node.mods
      if not mods then
        mods = {}
        node.mods = mods
      end
      mods[#mods + 1] = (op == "+") and 1 or -1
      mods[#mods + 1] = x
    end
    pos = nextPos
  end
  return node
end

local function ParseNumeric(ctx, v, where)
  local n = #v
  local ok = (n == 3 or n == 4)
  for i = 1, n do
    local x = v[i]
    if not IsNum(x) or x < 0 or x > 1 then ok = false end
  end
  for k in pairs(v) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then ok = false end
  end
  if not ok then
    Warn(ctx, "%s: a numeric colour is { r, g, b [, a] } in 0..1", where)
    return nil
  end
  return { kind = K_LIT, r = v[1], g = v[2], b = v[3], a = v[4] or 1 }
end

-- Links names and propagates the dynamic flags (cycles and depth > 4 are refused).
local Visit
Visit = function(ctx, node, where)
  if node.state == 2 then return node.depth end
  if node.state == 1 then
    Warn(ctx, "%s: colour cycle through '%s'", where, tostring(node.name or "xp/rested"))
    node.bad = true
    return 0
  end
  node.state = 1
  local depth = 0
  local kind = node.kind
  local targets
  if kind == K_NAME then
    local ref = ctx.colorNodes[node.name]
    if not ref then
      Warn(ctx, "%s: unknown colour '%s'", where, node.name)
      node.bad = true
    else
      node.ref = ref
      depth = 1 + Visit(ctx, ref, where)
      if depth > 4 then
        Warn(ctx, "%s: colour '%s' is nested more than 4 deep", where, node.name)
        node.bad = true
      end
      targets = ref
    end
  elseif kind == K_XP then
    targets = ctx.colorNodes.xp
  elseif kind == K_RESTED then
    targets = ctx.colorNodes.rested
  elseif kind == K_BASE then
    local x, r = ctx.colorNodes.xp, ctx.colorNodes.rested
    if x then Visit(ctx, x, where); node.uXp = node.uXp or x.uXp; node.uRested = node.uRested or x.uRested end
    if r then Visit(ctx, r, where); node.uXp = node.uXp or r.uXp; node.uRested = node.uRested or r.uRested end
  end
  if targets and kind ~= K_NAME then Visit(ctx, targets, where) end
  if targets then
    if targets.bad and kind ~= K_NAME then node.bad = true end
    node.uXp = node.uXp or targets.uXp
    node.uRested = node.uRested or targets.uRested
    node.uBase = node.uBase or targets.uBase
  end
  node.state, node.depth = 2, depth
  return depth
end

-- A colour value (string, numeric table or { expr, def = ... }) -> node, defNode.
-- Nodes are linked at once unless `defer` (the entries of `colors`, linked together).
local function ParseColor(ctx, v, where, allowBase, defer)
  local node, def
  local tv = type(v)
  if tv == "string" then
    node = ParseExpr(ctx, v, where, allowBase)
  elseif tv == "table" and type(v[1]) == "number" then
    node = ParseNumeric(ctx, v, where)
  elseif tv == "table" and type(v[1]) == "string" then
    for k in pairs(v) do
      if k ~= 1 and k ~= "def" then Warn(ctx, "%s: unknown field '%s' in a colour", where, tostring(k)) end
    end
    node = ParseExpr(ctx, v[1], where, allowBase)
    if v.def ~= nil then
      if type(v.def) == "table" and type(v.def[1]) == "string" then
        Warn(ctx, "%s: 'def' cannot have its own 'def'", where)
      else
        def = ParseColor(ctx, v.def, where .. ".def", allowBase, defer)
      end
    end
  else
    Warn(ctx, "%s: not a colour (%s)", where, tostring(v))
  end
  if not defer then
    if node then Visit(ctx, node, where) end
    if def then Visit(ctx, def, where) end
  end
  return node or WHITE_NODE, def
end

local function IsStatic(node)
  return not (node.uXp or node.uRested or node.uBase)
end

-- Registers a compiled colour (written by RunProgram at the end of the compile and by
-- every Recolor).
local function Slot(ctx, node, def, k, f)
  local out = NewColor()
  local slots = ctx.prog.slots
  slots[#slots + 1] = { out = out, node = node or WHITE_NODE, def = def, k = k or 0, f = f or 1 }
  return out
end

-- Three per-state colours (index k + 1); one shared table when they cannot differ.
local function States(ctx, node, def, dyn, alpha, maxA)
  local c1 = Slot(ctx, node, def, 0, alpha)
  local c2 = dyn and Slot(ctx, node, def, 1, alpha) or c1
  local c3 = (dyn or maxA ~= 1) and Slot(ctx, node, def, 2, alpha * maxA) or c1
  return { c1, c2, c3 }
end

-- A colour that never depends on the fill state.
local function Single(ctx, v, where, default)
  if v == nil then v = default end
  local node, def = ParseColor(ctx, v, where, false)
  return Slot(ctx, node, def, 0, 1), node
end

---------------------------------------------------------------------------
-- Media references and texture specs (6.1, 6.3)
---------------------------------------------------------------------------
-- file -> path, texture width, height, grey (white 8 x 8 when nil or unknown).
local function MediaRef(ctx, file, where)
  if file == nil then return WHITE, 8, 8, true end
  if type(file) ~= "string" then
    Warn(ctx, "%s: file must be a media name", where)
    return WHITE, 8, 8, true
  end
  local dir, name = string_match(file, "^(common)/(.+)$")
  local decl
  if dir then
    decl = COMMON_MEDIA[name]
  else
    dir, name = ctx.key, file
    decl = ctx.media[name]
  end
  if not string_find(name, "^[a-z0-9_]+$") then
    Warn(ctx, "%s: media name '%s' must be lowercase [a-z0-9_]", where, file)
  end
  if type(decl) ~= "table" then
    Warn(ctx, "%s: media '%s' is not declared", where, file)
    return WHITE, 8, 8, true
  end
  ctx.usedMedia[file] = true
  return MEDIA_ROOT .. "Themes\\" .. dir .. "\\" .. name .. ".tga", decl[1], decl[2], decl.grey == true
end

local ROTS = { [0] = true, [90] = true, [180] = true, [270] = true }
local TILES = { H = true, V = true, HV = true }
local BLENDS = { BLEND = true, ADD = true }

-- texSpec = { path, w, h, grey, blend, l, r, t, b (rect, unflipped), flipX, flipY,
--             tc = nil | { l, r, t, b }, tc8 = nil | { 8 numbers }, tile, wrapH, wrapV,
--             slice = nil | { texels, px } }
local function TexSpec(ctx, src, file, where, slice)
  local path, tw, th, grey = MediaRef(ctx, file, where)
  local spec = { path = path, w = tw, h = th, grey = grey,
                 blend = Choice(ctx, src.blend, "BLEND", BLENDS, where .. ".blend") }
  local l, r, t, b = 0, 1, 0, 1
  local rect = src.rect
  if rect ~= nil then
    local x, y, w, h = type(rect) == "table" and rect[1], type(rect) == "table" and rect[2],
      type(rect) == "table" and rect[3], type(rect) == "table" and rect[4]
    if IsNum(x) and IsNum(y) and IsNum(w) and IsNum(h) and x >= 0 and y >= 0 and w > 0 and h > 0
        and x + w <= tw and y + h <= th then
      l, r, t, b = x / tw, (x + w) / tw, y / th, (y + h) / th
    else
      Warn(ctx, "%s: rect must be { x, y, w, h } inside the %dx%d texture", where, tw, th)
    end
  end
  spec.l, spec.r, spec.t, spec.b = l, r, t, b
  local fx, fy = src.flipX == true, src.flipY == true
  if src.flipX ~= nil and type(src.flipX) ~= "boolean" then Warn(ctx, "%s: flipX must be a boolean", where) end
  if src.flipY ~= nil and type(src.flipY) ~= "boolean" then Warn(ctx, "%s: flipY must be a boolean", where) end
  spec.flipX, spec.flipY = fx, fy
  local rot = Choice(ctx, src.rot, 0, ROTS, where .. ".rot")
  local tile = Choice(ctx, src.tile, nil, TILES, where .. ".tile")
  if slice then
    spec.slice = slice
    if tile then Warn(ctx, "%s: tile is not supported with three / nine", where) end
    if rot ~= 0 then Warn(ctx, "%s: rot is not supported with three / nine", where) end
    return spec
  end
  if tile then
    if rot ~= 0 then Warn(ctx, "%s: rot is not supported with tile", where) end
    spec.tile = tile
    spec.wrapH = (tile == "H" or tile == "HV") and "REPEAT" or "CLAMP"
    spec.wrapV = (tile == "V" or tile == "HV") and "REPEAT" or "CLAMP"
    return spec
  end
  local L0, R0, T0, B0 = l, r, t, b
  if fx then L0, R0 = R0, L0 end
  if fy then T0, B0 = B0, T0 end
  if rot == 90 then
    spec.tc8 = { L0, B0, R0, B0, L0, T0, R0, T0 }
  elseif rot == 180 then
    spec.tc8 = { R0, B0, R0, T0, L0, B0, L0, T0 }
  elseif rot == 270 then
    spec.tc8 = { R0, T0, L0, T0, R0, B0, L0, B0 }
  elseif rect ~= nil or fx or fy then
    spec.tc = { L0, R0, T0, B0 }
  end
  return spec
end

-- Baked (non-grey) art is drawn with a white vertex colour (6.2).
local function CheckBakedTint(ctx, spec, node, where)
  if spec.grey or not IsStatic(node) or node.bad then return end
  local r, g, b = Eval(node, 0)
  if r < 0.999 or g < 0.999 or b < 0.999 then
    Warn(ctx, "%s: baked media '%s' must be drawn with a white colour (alpha only)", where, spec.path)
  end
end

---------------------------------------------------------------------------
-- Gradient source -> per-state pairs and flat colours
---------------------------------------------------------------------------
local DIRS = { HORIZONTAL = true, VERTICAL = true }

local function ParseGrad(ctx, grad, where, allowBase)
  if type(grad) ~= "table" or not DIRS[grad[1]] then
    Warn(ctx, "%s: grad must be { \"HORIZONTAL\" | \"VERTICAL\", from, to }", where)
    return nil
  end
  for k in pairs(grad) do
    if k ~= 1 and k ~= 2 and k ~= 3 then Warn(ctx, "%s: unknown field '%s' in grad", where, tostring(k)) end
  end
  local fromN, fromD = ParseColor(ctx, grad[2], where .. ".grad.from", allowBase)
  local toN, toD = ParseColor(ctx, grad[3], where .. ".grad.to", allowBase)
  return { dir = grad[1], fromN = fromN, fromD = fromD, toN = toN, toD = toD }
end

local function Dyn(node, def)
  return (node and node.uBase) or (def and def.uBase) or false
end

-- Fills item.c / item.g / item.f (and item.dyn) from color / grad / flat of `src`.
local function Paint(ctx, item, src, where, allowBase, alpha, maxA)
  local cN, cD = ParseColor(ctx, src.color or "#ffffff", where .. ".color", allowBase)
  local gp
  if src.grad ~= nil then gp = ParseGrad(ctx, src.grad, where, allowBase) end
  local fN, fD
  if src.flat ~= nil then
    if not gp then Warn(ctx, "%s: flat needs grad", where) end
    fN, fD = ParseColor(ctx, src.flat, where .. ".flat", allowBase)
  elseif gp then
    fN, fD = gp.fromN, gp.fromD
  end
  local dyn = Dyn(cN, cD)
  if gp then dyn = dyn or Dyn(gp.fromN, gp.fromD) or Dyn(gp.toN, gp.toD) or Dyn(fN, fD) end
  item.dyn = dyn and true or false
  item.c = States(ctx, cN, cD, dyn, alpha, maxA)
  item.color = item.c[1]
  if gp then
    local from = States(ctx, gp.fromN, gp.fromD, dyn, alpha, maxA)
    local to = States(ctx, gp.toN, gp.toD, dyn, alpha, maxA)
    local dir = gp.dir
    local p1 = { from[1], to[1], dir = dir }
    local p2 = (from[2] == from[1] and to[2] == to[1]) and p1 or { from[2], to[2], dir = dir }
    local p3 = (from[3] == from[1] and to[3] == to[1]) and p1 or { from[3], to[3], dir = dir }
    item.g = { dir = dir, p1, p2, p3 }
    item.f = States(ctx, fN, fD, dyn, alpha, maxA)
  end
  return cN
end

---------------------------------------------------------------------------
-- bar section (2.4)
---------------------------------------------------------------------------
local SPAN_KIND = { track = "range", fill = "range", rested = "range",
                    fillEnd = "anchor", restEnd = "anchor", trackStart = "anchor", trackEnd = "anchor" }
local DRAW_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true }
local ALIGNS = { center = true, left = true, right = true }
local LAYER_FIELDS = Set({ "id", "span", "layer", "sub", "file", "rect", "flipX", "flipY", "rot", "tile",
  "blend", "color", "grad", "flat", "alpha", "maxAlpha", "top", "h", "bottom", "band", "pad",
  "capInset", "w", "align", "dx", "caps", "three", "nine", "ticks" })
local BAR_FIELDS = Set({ "pad", "gap", "height", "maxAlpha", "layers", "panel" })
local PART_FIELDS = Set({ "id", "file", "nine", "rect", "flipX", "flipY", "tile", "blend", "color", "grad",
  "flat", "anchor", "inset", "x", "y", "w", "h", "alpha", "layer", "sub" })
local POINTS = Set({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM",
  "BOTTOMRIGHT" })

-- { file, texels, px } of three / nine -> file, slice
local function SliceSrc(ctx, v, where, what)
  if type(v) ~= "table" or type(v[1]) ~= "string" or not IsNum(v[2]) or v[2] <= 0
      or not IsNum(v[3]) or v[3] <= 0 then
    Warn(ctx, "%s: %s must be { file, texels, px }", where, what)
    return nil, nil
  end
  return v[1], { v[2], v[3] }
end

local function CompileLayer(ctx, src, i, ids, barMaxAlpha)
  local where = "bar.layers[" .. i .. "]"
  if type(src) ~= "table" then
    Warn(ctx, "%s: a layer is a table", where)
    return nil
  end
  local id = src.id
  if type(id) ~= "string" or id == "" then
    Warn(ctx, "%s: missing id", where)
    id = "layer" .. i
  end
  where = "layer '" .. id .. "'"
  if ids[id] then Warn(ctx, "%s: duplicate id", where) end
  ids[id] = true
  CheckFields(ctx, src, LAYER_FIELDS, where)
  local Lc = { id = id }

  local kind, nk = "tex", 0
  if src.caps ~= nil and src.caps ~= false then kind, nk = "caps", nk + 1 end
  if src.three ~= nil then kind, nk = "three", nk + 1 end
  if src.nine ~= nil then kind, nk = "nine", nk + 1 end
  if src.ticks ~= nil then kind, nk = "ticks", nk + 1 end
  if nk > 1 then Warn(ctx, "%s: caps, three, nine and ticks exclude each other", where) end
  if src.caps ~= nil and type(src.caps) ~= "boolean" then Warn(ctx, "%s: caps must be a boolean", where) end
  Lc.kind = kind

  local span = Choice(ctx, src.span, "track", SPAN_KIND, where .. ".span")
  local isRange = SPAN_KIND[span] == "range"
  Lc.span = span
  Lc.layer = Choice(ctx, src.layer, "ARTWORK", DRAW_LAYERS, where .. ".layer")
  Lc.sub = Num(ctx, src.sub, 0, where .. ".sub", -8, 7, true)

  -- texture
  if kind == "three" or kind == "nine" then
    local file, slice = SliceSrc(ctx, src[kind], where, kind)
    if src.file ~= nil then Warn(ctx, "%s: file is ignored with %s (give it in %s)", where, kind, kind) end
    Lc.tex = TexSpec(ctx, src, file, where, slice or { 1, 1 })
  else
    if kind == "caps" and src.file ~= nil then Warn(ctx, "%s: caps use the white file only", where) end
    Lc.tex = TexSpec(ctx, src, src.file, where)
  end
  Lc.blend = Lc.tex.blend

  -- vertical extent
  Lc.top = Num(ctx, src.top, 0, where .. ".top")
  Lc.bottom = Num(ctx, src.bottom, 0, where .. ".bottom")
  Lc.h = Num(ctx, src.h, nil, where .. ".h", 0)
  local band = src.band
  if band ~= nil then
    if type(band) == "table" and IsNum(band[1]) and IsNum(band[2]) and band[1] >= 0 and band[2] <= 1
        and band[1] < band[2] and #band == 2 then
      Lc.band = { band[1], band[2] }
    else
      Warn(ctx, "%s: band must be { f0, f1 } with 0 <= f0 < f1 <= 1", where)
    end
  end

  -- horizontal extent
  local pad = src.pad
  if pad ~= nil then
    if not isRange then Warn(ctx, "%s: pad applies to range spans only", where) end
    if type(pad) == "table" and IsNum(pad[1]) and IsNum(pad[2]) then
      Lc.pad = { pad[1], pad[2] }
    else
      Warn(ctx, "%s: pad must be { left, right }", where)
    end
  end
  Lc.pad = Lc.pad or { 0, 0 }
  if src.capInset ~= nil and type(src.capInset) ~= "boolean" then
    Warn(ctx, "%s: capInset must be a boolean", where)
  end
  Lc.capInset = src.capInset == true
  if Lc.capInset and not isRange then Warn(ctx, "%s: capInset applies to range spans only", where) end
  if not isRange and kind ~= "ticks" then
    Lc.w = Num(ctx, src.w, nil, where .. ".w", 1)
    if Lc.w == nil then
      Warn(ctx, "%s: anchor span '%s' needs a width w", where, span)
      Lc.w = 1
    end
  elseif src.w ~= nil then
    Warn(ctx, "%s: w applies to anchor spans only", where)
  end
  Lc.align = Choice(ctx, src.align, "center", ALIGNS, where .. ".align")
  Lc.dx = Num(ctx, src.dx, 0, where .. ".dx")

  if kind == "ticks" then
    local t = src.ticks
    if type(t) ~= "table" then
      Warn(ctx, "%s: ticks must be { n = N, w = 1, clip = nil | \"fill\", mid = bool? }", where)
      t = {}
    end
    CheckFields(ctx, t, Set({ "n", "w", "clip", "mid" }), where .. ".ticks")
    if t.mid ~= nil and type(t.mid) ~= "boolean" then Warn(ctx, "%s.ticks: mid must be a boolean", where) end
    Lc.ticks = {
      n = Num(ctx, t.n, 2, where .. ".ticks.n", 2, 100, true),
      w = Num(ctx, t.w, 1, where .. ".ticks.w", 1, 16, true),
      clip = Choice(ctx, t.clip, nil, { fill = true }, where .. ".ticks.clip"),
      mid = (t.mid == true) or nil,     -- N ticks at the middles of the N parts
    }
  end

  -- colours: alpha factors folded into c / g / f
  local alpha = Num(ctx, src.alpha, 1, where .. ".alpha", 0, 1)
  local maxA = Num(ctx, src.maxAlpha, (span == "fill" or span == "fillEnd") and barMaxAlpha or 1,
    where .. ".maxAlpha", 0, 1)
  local cN = Paint(ctx, Lc, src, where, true, alpha, maxA)
  CheckBakedTint(ctx, Lc.tex, cN, where)
  return Lc
end

-- Panel parts (2.4.2): bar panel (alpha "bg" / "line" / number) and tooltip panel
-- (numbers only). A numeric alpha is folded into c (part.alpha is then 1).
local function CompilePart(ctx, src, i, ids, where0, isTooltip)
  local where = where0 .. "[" .. i .. "]"
  if type(src) ~= "table" then
    Warn(ctx, "%s: a part is a table", where)
    return nil
  end
  local id = src.id
  if type(id) ~= "string" or id == "" then
    Warn(ctx, "%s: missing id", where)
    id = "part" .. i
  end
  where = where0 .. " '" .. id .. "'"
  if ids[id] then Warn(ctx, "%s: duplicate id", where) end
  ids[id] = true
  CheckFields(ctx, src, PART_FIELDS, where)
  local P = { id = id }
  if src.nine ~= nil then
    local file, slice = SliceSrc(ctx, src.nine, where, "nine")
    if src.file ~= nil then Warn(ctx, "%s: file is ignored with nine", where) end
    P.kind = "nine"
    P.tex = TexSpec(ctx, src, file, where, slice or { 1, 1 })
  else
    P.kind = "tex"
    P.tex = TexSpec(ctx, src, src.file, where)
  end
  P.blend = P.tex.blend
  P.layer = Choice(ctx, src.layer, "BACKGROUND", DRAW_LAYERS, where .. ".layer")
  local defSub = -8 + i - 1
  if defSub > 7 then defSub = 7 end
  P.sub = Num(ctx, src.sub, defSub, where .. ".sub", -8, 7, true)
  local anchor = src.anchor or "FILL"
  if anchor ~= "FILL" and not POINTS[anchor] then
    Warn(ctx, "%s: anchor must be FILL or a point name", where)
    anchor = "FILL"
  end
  P.anchor = anchor
  if anchor == "FILL" then
    local ins = src.inset
    local l, r, t, b = 0, 0, 0, 0
    if ins ~= nil then
      if type(ins) == "table" and IsNum(ins[1]) and IsNum(ins[2]) and IsNum(ins[3]) and IsNum(ins[4]) then
        l, r, t, b = ins[1], ins[2], ins[3], ins[4]
      else
        Warn(ctx, "%s: inset must be { l, r, t, b }", where)
      end
    end
    P.inset = { l, r, t, b, l = l, r = r, t = t, b = b }
    if src.x ~= nil or src.y ~= nil or src.w ~= nil or src.h ~= nil then
      Warn(ctx, "%s: x, y, w, h need a point anchor", where)
    end
  else
    if src.inset ~= nil then Warn(ctx, "%s: inset needs anchor FILL", where) end
    P.x = Num(ctx, src.x, 0, where .. ".x")
    P.y = Num(ctx, src.y, 0, where .. ".y")
    P.w = Num(ctx, src.w, nil, where .. ".w", 1)
    P.h = Num(ctx, src.h, nil, where .. ".h", 1)
    if not P.w or not P.h then
      Warn(ctx, "%s: a point anchor needs w and h", where)
      P.w, P.h = P.w or 1, P.h or 1
    end
  end
  local alpha, factor = src.alpha, 1
  if alpha == nil then
    alpha = 1
  elseif (alpha == "bg" or alpha == "line") and not isTooltip then
    factor = 1
  elseif IsNum(alpha) and alpha >= 0 and alpha <= 1 then
    factor, alpha = alpha, 1
  else
    Warn(ctx, "%s: alpha must be %s", where, isTooltip and "a number in 0..1" or "\"bg\", \"line\" or 0..1")
    alpha = 1
  end
  P.alpha = alpha
  local cN = Paint(ctx, P, src, where, false, factor, 1)
  CheckBakedTint(ctx, P.tex, cN, where)
  return P
end

local function CompileParts(ctx, parts, where, isTooltip)
  local out, ids = {}, {}
  if type(parts) ~= "table" then
    Warn(ctx, "%s: parts must be a list", where)
    return out
  end
  for i = 1, #parts do
    local P = CompilePart(ctx, parts[i], i, ids, where, isTooltip)
    if P then out[#out + 1] = P end
  end
  return out
end

local function CompileBar(ctx, bar)
  if type(bar) ~= "table" then
    Warn(ctx, "bar section missing")
    bar = { layers = {} }
  end
  CheckFields(ctx, bar, BAR_FIELDS, "bar")
  local out = {
    pad = Num(ctx, bar.pad, 8, "bar.pad", 0, 64, true),
    gap = Num(ctx, bar.gap, 3, "bar.gap", 0, 32, true),
    hAdd = 0, hMin = 4,
  }
  local h = bar.height
  if h ~= nil then
    if type(h) == "table" then
      CheckFields(ctx, h, Set({ "add", "min" }), "bar.height")
      out.hAdd = Num(ctx, h.add, 0, "bar.height.add", -16, 32, true)
      out.hMin = Num(ctx, h.min, 4, "bar.height.min", 1, 64, true)
    else
      Warn(ctx, "bar.height must be { add, min }")
    end
  end
  local maxA = Num(ctx, bar.maxAlpha, 0.35, "bar.maxAlpha", 0, 1)
  local layers = {}
  if type(bar.layers) ~= "table" or #bar.layers == 0 then
    Warn(ctx, "bar.layers is required")
  else
    local ids = {}
    for i = 1, #bar.layers do
      local Lc = CompileLayer(ctx, bar.layers[i], i, ids, maxA)
      if Lc then layers[#layers + 1] = Lc end
    end
  end
  out.layers = layers
  local panel = bar.panel
  if panel == nil or panel == "backdrop" then
    out.panel = "backdrop"
  elseif type(panel) == "table" and type(panel.parts) == "table" then
    CheckFields(ctx, panel, Set({ "parts" }), "bar.panel")
    out.panel = { parts = CompileParts(ctx, panel.parts, "bar.panel.parts", false) }
  else
    Warn(ctx, "bar.panel must be \"backdrop\" or { parts = { ... } }")
    out.panel = "backdrop"
  end
  return out
end

---------------------------------------------------------------------------
-- text section (2.5)
---------------------------------------------------------------------------
local TEXT_ELEMS = { "s1", "s2", "s3", "level", "levelValue", "xpLabel", "xp", "sep", "marker", "hint" }
local TEXT_SIZE = { s1 = 2, s2 = 0, s3 = -1, level = 0, levelValue = 0, xpLabel = 0, xp = 0, sep = 0,
                    marker = -1, hint = -1 }
local TEXT_ROLES = { "label", "value", "levelLabel", "levelValue", "xpText", "sep", "marker", "hint",
                     "slot2", "slot3", "dimmed" }
local TEXT_ROLE_DEF = { label = "label", value = "value", levelLabel = "label", levelValue = "value",
                        xpText = "label", sep = "label", marker = "label", hint = "label", slot2 = "value",
                        slot3 = "label", dimmed = "dim" }
local FONT_ROLES = { display = true, body = true, num = true, game = true }
-- Elements that render arbitrary strings: never the display role (SPEC 8.3; `hint` shows a
-- free locale sentence, so it is included too).
local NO_DISPLAY = { s1 = true, s2 = true, s3 = true, xp = true, sep = true, levelValue = true, hint = true }
local TEXT_FIELDS = Set({ "font", "size", "split", "splitGap", "levelFmt", "colors", "shadow" })
local LEVEL_FMTS = { upper = true, title = true }

local function ElemMap(ctx, src, where, defaults, valid, check)
  local out = {}
  for k, v in pairs(defaults) do out[k] = v end
  if src == nil then return out end
  if type(src) ~= "table" then
    Warn(ctx, "%s must be a table", where)
    return out
  end
  for k, v in pairs(src) do
    if not valid[k] then
      Warn(ctx, "%s: unknown element '%s'", where, tostring(k))
    elseif check(k, v) then
      out[k] = v
    else
      Warn(ctx, "%s.%s: invalid value %s", where, tostring(k), tostring(v))
    end
  end
  return out
end

local function CompileText(ctx, text)
  if text == nil then text = {} end
  if type(text) ~= "table" then
    Warn(ctx, "text must be a table")
    text = {}
  end
  CheckFields(ctx, text, TEXT_FIELDS, "text")
  local valid = Set(TEXT_ELEMS)
  local fontDef = {}
  for i = 1, #TEXT_ELEMS do fontDef[TEXT_ELEMS[i]] = "body" end
  local out = {}
  out.font = ElemMap(ctx, text.font, "text.font", fontDef, valid, function(_, v) return FONT_ROLES[v] == true end)
  for e in pairs(NO_DISPLAY) do
    if out.font[e] == "display" then
      Warn(ctx, "text.font.%s: shows arbitrary text, so it cannot use the display role", e)
      out.font[e] = "body"
    end
  end
  local function IsDelta(_, v) return IsNum(v) and v % 1 == 0 and v >= -8 and v <= 16 end
  out.size = ElemMap(ctx, text.size, "text.size", TEXT_SIZE, valid, IsDelta)
  if text.split ~= nil and type(text.split) ~= "boolean" then Warn(ctx, "text.split must be a boolean") end
  out.split = text.split == true
  out.splitGap = Num(ctx, text.splitGap, 4, "text.splitGap", 0, 32, true)
  out.levelFmt = Choice(ctx, text.levelFmt, "upper", LEVEL_FMTS, "text.levelFmt")

  local roles = text.colors
  if roles ~= nil and type(roles) ~= "table" then
    Warn(ctx, "text.colors must be a table")
    roles = nil
  end
  roles = roles or {}
  CheckFields(ctx, roles, Set(TEXT_ROLES), "text.colors")
  local colors = {}
  for i = 1, #TEXT_ROLES do
    local role = TEXT_ROLES[i]
    colors[role] = Single(ctx, roles[role], "text.colors." .. role, TEXT_ROLE_DEF[role])
  end
  out.colors = colors

  local sh = text.shadow
  local shadow = { x = 1, y = -1 }
  if sh ~= nil and type(sh) ~= "table" then
    Warn(ctx, "text.shadow must be { color, x, y }")
    sh = nil
  end
  sh = sh or {}
  CheckFields(ctx, sh, Set({ "color", "x", "y" }), "text.shadow")
  shadow.c = Single(ctx, sh.color, "text.shadow.color", { 0, 0, 0, 0.8 })
  shadow.x = Num(ctx, sh.x, 1, "text.shadow.x", -8, 8)
  shadow.y = Num(ctx, sh.y, -1, "text.shadow.y", -8, 8)
  out.shadow = shadow
  return out
end

---------------------------------------------------------------------------
-- tooltip section (4.2, 4.3)
---------------------------------------------------------------------------
local TT_ROLES = { "title", "mode", "label", "value", "dim", "header", "pause", "hint", "levelLabel",
                   "levelValue", "levelValueRested", "rested" }
local TT_ROLE_DEF = { title = "accent", mode = "label", label = "label", value = "value", dim = "dim",
                      header = "accent", pause = "pause", hint = "dim", levelLabel = "label",
                      levelValue = "value", levelValueRested = "value", rested = "value" }
local TT_FIELDS = Set({ "native", "width", "pad", "gap", "lineGap", "fonts", "colors", "panel", "titleIcon",
  "sep", "leader", "gauge" })
local TT_FONTS = { "title", "body", "value", "note", "hint" }
local GAUGE_KEYS = { "world", "dungeon", "raid", "pvp", "taxi", "afk", "inn", "city" }
local SEP_FIELDS = Set({ "h", "above", "below", "file", "tile", "color", "grad", "flat", "mirror", "rect",
  "flipX", "flipY", "blend", "center" })

local function CompileSep(ctx, s, where)
  if s == nil then return nil end
  if type(s) ~= "table" then
    Warn(ctx, "%s must be a table", where)
    return nil
  end
  CheckFields(ctx, s, SEP_FIELDS, where)
  local out = {
    h = Num(ctx, s.h, 1, where .. ".h", 1, 32, true),
    above = Num(ctx, s.above, 6, where .. ".above", 0, 64, true),
    below = Num(ctx, s.below, 5, where .. ".below", 0, 64, true),
  }
  if s.mirror ~= nil and type(s.mirror) ~= "boolean" then Warn(ctx, "%s.mirror must be a boolean", where) end
  out.mirror = s.mirror == true
  out.tex = TexSpec(ctx, s, s.file, where)
  out.blend = out.tex.blend
  local cN = Paint(ctx, out, s, where, false, 1, 1)
  CheckBakedTint(ctx, out.tex, cN, where)
  -- center: the middle `center` texels (an ornament) keep the art's proportions, the two
  -- sides (lines) stretch to the tooltip width
  local c = s.center
  if c ~= nil then
    local artW = (out.tex.r - out.tex.l) * out.tex.w      -- (rect: the art is the rectangle)
    if artW < 0 then artW = -artW end
    if s.file == nil or not IsNum(c) or c % 1 ~= 0 or c < 2 or c > artW - 2 then
      Warn(ctx, "%s.center must be a whole number of texels inside the separator's art", where)
    elseif out.mirror or out.tex.tile or s.grad ~= nil then
      Warn(ctx, "%s.center excludes mirror, tile and grad", where)
    else
      out.center = c
    end
  end
  return out
end

local function CompileTooltip(ctx, tt)
  if type(tt) ~= "table" then
    Warn(ctx, "tooltip section missing")
    return { native = true, colors = Themes.CLASSIC_TT }
  end
  if tt.native == true then
    return { native = true, colors = Themes.CLASSIC_TT }   -- every other field ignored
  end
  CheckFields(ctx, tt, TT_FIELDS, "tooltip")
  if tt.native ~= nil and tt.native ~= false then Warn(ctx, "tooltip.native must be a boolean") end
  local out = { native = false }
  local w = tt.width
  local wmin, wmax = 280, 440
  if w ~= nil then
    if type(w) == "table" and IsNum(w[1]) and IsNum(w[2]) and w[1] > 0 and w[2] >= w[1] then
      wmin, wmax = w[1], w[2]
    else
      Warn(ctx, "tooltip.width must be { min, max }")
    end
  end
  out.width = { wmin, wmax, min = wmin, max = wmax }
  local p = tt.pad
  local pl, pr, pt, pb = 12, 12, 10, 10
  if p ~= nil then
    if type(p) == "table" and IsNum(p[1]) and IsNum(p[2]) and IsNum(p[3]) and IsNum(p[4]) then
      pl, pr, pt, pb = p[1], p[2], p[3], p[4]
    else
      Warn(ctx, "tooltip.pad must be { l, r, t, b }")
    end
  end
  out.pad = { pl, pr, pt, pb, l = pl, r = pr, t = pt, b = pb }
  out.gap = Num(ctx, tt.gap, 8, "tooltip.gap", 0, 64)
  out.lineGap = Num(ctx, tt.lineGap, 3, "tooltip.lineGap", 0, 32)

  local fonts = {}
  local src = tt.fonts
  if type(src) ~= "table" then
    Warn(ctx, "tooltip.fonts is required")
    src = {}
  end
  CheckFields(ctx, src, Set(TT_FONTS), "tooltip.fonts")
  for i = 1, #TT_FONTS do
    local name = TT_FONTS[i]
    local f = src[name]
    if f == nil and name == "value" then f = src.body end
    local role, size = "body", 12
    if type(f) == "table" and FONT_ROLES[f[1]] and IsNum(f[2]) and f[2] >= 6 and f[2] <= 40 then
      role, size = f[1], f[2]
    else
      Warn(ctx, "tooltip.fonts.%s must be { role, size }", name)
    end
    if role == "display" and name ~= "title" then
      Warn(ctx, "tooltip.fonts.%s: shows arbitrary text, so it cannot use the display role", name)
      role = "body"
    end
    fonts[name] = { role, size, role = role, size = size }
  end
  out.fonts = fonts

  local roles = tt.colors
  if type(roles) ~= "table" then
    Warn(ctx, "tooltip.colors is required")
    roles = {}
  end
  CheckFields(ctx, roles, Set(TT_ROLES), "tooltip.colors")
  local colors = {}
  local dimNode
  for i = 1, #TT_ROLES do
    local role = TT_ROLES[i]
    local c, node = Single(ctx, roles[role], "tooltip.colors." .. role, TT_ROLE_DEF[role])
    colors[role] = c
    if role == "dim" then dimNode = node end
  end
  out.colors = colors
  if dimNode and not IsStatic(dimNode) then ctx.prog.ccDimOf = colors end

  local panel = tt.panel
  if type(panel) ~= "table" or type(panel.parts) ~= "table" then
    Warn(ctx, "tooltip.panel = { parts = { ... } } is required")
    out.panel = { parts = {} }
  else
    CheckFields(ctx, panel, Set({ "parts" }), "tooltip.panel")
    out.panel = { parts = CompileParts(ctx, panel.parts, "tooltip.panel.parts", true) }
  end

  local icon = tt.titleIcon
  if icon ~= nil then
    if type(icon) == "table" and type(icon[1]) == "string" and IsNum(icon[2]) and IsNum(icon[3]) then
      CheckFields(ctx, icon, Set({ 1, 2, 3, "gap" }), "tooltip.titleIcon")
      out.titleIcon = { tex = TexSpec(ctx, {}, icon[1], "tooltip.titleIcon"), w = icon[2], h = icon[3],
                        gap = Num(ctx, icon.gap, 6, "tooltip.titleIcon.gap", 0, 32) }
    else
      Warn(ctx, "tooltip.titleIcon must be { file, w, h, gap = 6 }")
    end
  end

  local sep = tt.sep
  out.sep = {}
  if sep ~= nil then
    if type(sep) == "table" then
      CheckFields(ctx, sep, Set({ "header", "block", "footer" }), "tooltip.sep")
      out.sep.header = CompileSep(ctx, sep.header, "tooltip.sep.header")
      out.sep.block = CompileSep(ctx, sep.block, "tooltip.sep.block")
      out.sep.footer = CompileSep(ctx, sep.footer, "tooltip.sep.footer")
    else
      Warn(ctx, "tooltip.sep must be { header, block, footer }")
    end
  end

  local ld = tt.leader
  if ld ~= nil then
    if type(ld) == "table" then
      CheckFields(ctx, ld, Set({ "file", "tile", "h", "y", "color", "min", "rect", "blend" }), "tooltip.leader")
      local leader = {
        h = Num(ctx, ld.h, 1, "tooltip.leader.h", 1, 16, true),
        y = Num(ctx, ld.y, 3, "tooltip.leader.y", -16, 32),
        min = Num(ctx, ld.min, 12, "tooltip.leader.min", 0, 200),
      }
      local tsrc = { tile = ld.tile or "H", rect = ld.rect, blend = ld.blend }
      leader.tex = TexSpec(ctx, tsrc, ld.file, "tooltip.leader")
      leader.blend = leader.tex.blend
      local cN = Paint(ctx, leader, ld, "tooltip.leader", false, 1, 1)
      CheckBakedTint(ctx, leader.tex, cN, "tooltip.leader")
      out.leader = leader
    else
      Warn(ctx, "tooltip.leader must be a table")
    end
  end

  local gg = tt.gauge
  if gg ~= nil then
    if type(gg) == "table" then
      CheckFields(ctx, gg, Set({ "w", "h", "gap", "outline", "colors" }), "tooltip.gauge")
      local gauge = {
        w = Num(ctx, gg.w, 176, "tooltip.gauge.w", 16, 512, true),
        h = Num(ctx, gg.h, 6, "tooltip.gauge.h", 1, 32, true),
        gap = Num(ctx, gg.gap, 2, "tooltip.gauge.gap", 0, 16, true),
      }
      if gg.outline ~= nil then gauge.outline = Single(ctx, gg.outline, "tooltip.gauge.outline") end
      local gc = type(gg.colors) == "table" and gg.colors or {}
      if type(gg.colors) ~= "table" then Warn(ctx, "tooltip.gauge.colors is required") end
      CheckFields(ctx, gc, Set(GAUGE_KEYS), "tooltip.gauge.colors")
      local colors2 = {}
      for i = 1, #GAUGE_KEYS do
        local k = GAUGE_KEYS[i]
        if gc[k] == nil and type(gg.colors) == "table" then
          Warn(ctx, "tooltip.gauge.colors.%s is missing", k)
        end
        colors2[k] = Single(ctx, gc[k], "tooltip.gauge.colors." .. k, "dim")
      end
      gauge.colors = colors2
      out.gauge = gauge
    else
      Warn(ctx, "tooltip.gauge must be a table")
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Compile (2.8)
---------------------------------------------------------------------------
local TOP_FIELDS = Set({ "name", "fonts", "colors", "media", "bar", "text", "tooltip", "ui" })
local REQUIRED_COLORS = { "xp", "rested", "label", "value", "dim", "accent" }
local UI_ROLES = { "bg", "border", "title", "accent", "label", "value", "dim" }
local RESERVED_NAMES = { base = true, none = true }

local function CompileFonts(ctx, fonts)
  local out = {}
  if type(fonts) ~= "table" then
    Warn(ctx, "fonts = { display, body, num? } is required")
    fonts = {}
  end
  CheckFields(ctx, fonts, Set({ "display", "body", "num" }), "fonts")
  for _, role in ipairs({ "display", "body", "num" }) do
    local name = fonts[role]
    if name == nil and role == "num" then
      name = out.body
    elseif name ~= "game" and not FONTS[name] then
      Warn(ctx, "fonts.%s: unknown font '%s'", role, tostring(name))
      name = "game"
    end
    if role ~= "display" and name ~= nil and FONTS[name] and FONTS[name].display then
      Warn(ctx, "fonts.%s: %s is a display-only font", role, name)
      name = "game"
    end
    out[role] = name
  end
  return out
end

local function CompileMedia(ctx, media)
  local out = {}
  if media == nil then return out end
  if type(media) ~= "table" then
    Warn(ctx, "media must be a table")
    return out
  end
  for name, d in pairs(media) do
    local where = "media." .. tostring(name)
    if type(name) ~= "string" or not string_find(name, "^[a-z0-9_]+$") then
      Warn(ctx, "%s: media names are lowercase [a-z0-9_]", where)
    elseif type(d) ~= "table" or not IsPow2(d[1]) or not IsPow2(d[2]) then
      Warn(ctx, "%s: must be { w, h, grey = bool? } with power-of-two sizes up to 256", where)
    else
      CheckFields(ctx, d, Set({ 1, 2, "grey" }), where)
      if d.grey ~= nil and type(d.grey) ~= "boolean" then Warn(ctx, "%s: grey must be a boolean", where) end
      out[name] = d
    end
  end
  return out
end

-- The named colours: parsed, then linked together (any order), then checked.
local function CompileColors(ctx, colors)
  local nodes, defs = {}, {}
  ctx.colorNodes = nodes
  if type(colors) ~= "table" then
    Warn(ctx, "colors is required")
    colors = {}
  end
  for name, v in pairs(colors) do
    if type(name) ~= "string" or not string_find(name, "^[%a_][%w_]*$") or RESERVED_NAMES[name] then
      Warn(ctx, "colors: invalid colour name '%s'", tostring(name))
    else
      nodes[name], defs[name] = ParseColor(ctx, v, "colors." .. name, false, true)
    end
  end
  for i = 1, #REQUIRED_COLORS do
    local name = REQUIRED_COLORS[i]
    if not nodes[name] then Warn(ctx, "colors.%s is required", name) end
  end
  if not nodes.pause then
    local p = C.COLORS.pause
    nodes.pause = { kind = K_LIT, r = p[1], g = p[2], b = p[3], a = p[4] or 1 }
  end
  if not nodes.xp then
    local f = C.COLORS.fill
    nodes.xp = { kind = K_LIT, r = f[1], g = f[2], b = f[3], a = f[4] or 1 }
  end
  if not nodes.rested then
    local f = C.COLORS.restedFill
    nodes.rested = { kind = K_LIT, r = f[1], g = f[2], b = f[3], a = f[4] or 1 }
  end
  for name, node in pairs(nodes) do
    Visit(ctx, node, "colors." .. name)
    if defs[name] then Visit(ctx, defs[name], "colors." .. name .. ".def") end
  end
  ctx.colorDefs = defs
  ctx.prog.xp, ctx.prog.rested = nodes.xp, nodes.rested
end

-- th.colors: the theme's own palette, before any user override (static).
local function Palette(ctx)
  local saveX, saveR = E.xpOn, E.rsOn
  E.xpOn, E.rsOn = false, false
  E.prog = ctx.prog
  local out = {}
  for name, node in pairs(ctx.colorNodes) do
    local def = ctx.colorDefs[name]
    local r, g, b, a
    if def then r, g, b, a = Eval(def, 0) else r, g, b, a = Eval(node, 0) end
    out[name] = NewColor(r, g, b, a)
  end
  E.prog = nil
  E.xpOn, E.rsOn = saveX, saveR
  return out
end

local function CompileUI(ctx, ui)
  local out = {}
  if type(ui) ~= "table" then
    Warn(ctx, "ui is required")
    ui = {}
  end
  CheckFields(ctx, ui, Set(UI_ROLES), "ui")
  for i = 1, #UI_ROLES do
    local role = UI_ROLES[i]
    if ui[role] == nil then Warn(ctx, "ui.%s is required", role) end
    local c, node = Single(ctx, ui[role], "ui." .. role, role == "bg" and "#000000" or "label")
    -- the graph and the window are restyled at a theme switch only, never on a recolour
    if not IsStatic(node) then Warn(ctx, "ui.%s: must not depend on the xp / rested colours", role) end
    out[role] = c
  end
  return out
end

local function CompileBody(ctx, src)
  CheckFields(ctx, src, TOP_FIELDS, "theme")
  local th = { key = ctx.key, gen = 0 }
  if type(src.name) ~= "string" or src.name == "" then Warn(ctx, "name (a locale key) is required") end
  th.name = src.name
  ctx.media = CompileMedia(ctx, src.media)
  th.fonts = CompileFonts(ctx, src.fonts)
  CompileColors(ctx, src.colors)
  E.prog = ctx.prog                     -- compile-time checks evaluate colours
  th.accent = Slot(ctx, ctx.colorNodes.accent or WHITE_NODE, ctx.colorDefs.accent, 0, 1)
  th.bar = CompileBar(ctx, src.bar)
  th.text = CompileText(ctx, src.text)
  th.tt = CompileTooltip(ctx, src.tooltip)
  th.native = th.tt.native == true
  th.ui = CompileUI(ctx, src.ui)
  for name in pairs(ctx.media) do
    if not ctx.usedMedia[name] then Warn(ctx, "media '%s' is declared but never used", name) end
  end
  RunProgram(ctx.prog)
  if not th.native then th.tt.colors.ccDim = ColorCode(th.tt.colors.dim) end   -- (dynamic: every run)
  th.colors = Palette(ctx)
  -- Recolouring only rewrites the colours that read a user colour: the static slots (and
  -- the parse nodes only they hold) are dropped now that their values are written.
  local slots, kept = ctx.prog.slots, {}
  for i = 1, #slots do
    local sl = slots[i]
    if not IsStatic(sl.node) or (sl.def and not IsStatic(sl.def)) then kept[#kept + 1] = sl end
  end
  ctx.prog.slots = kept
  return th
end

---------------------------------------------------------------------------
-- Entry points
---------------------------------------------------------------------------

-- The round-4 Themes.Compile on `builder` (a function returning the source table, nil
-- when the key is not registered): the round-4 compiled theme (nil when it cannot be
-- built) and the warnings, with the texts of the round-4 compiler. The user colours of
-- ns.settings are read as by the addon.
function TV.Compile(nsArg, key, builder)
  ns = nsArg
  C, Themes = ns.C, ns.Themes
  FONTS, COMMON_MEDIA = Themes.FONTS, Themes.COMMON_MEDIA
  MEDIA_ROOT = "Interface\\AddOns\\" .. (ns.ADDON or "TruePlayed") .. "\\Media\\"
  WHITE = C.TEX_WHITE
  if not builder then return nil, { tostring(key) .. ": not a registered theme" } end
  local ok, src = pcall(builder)
  if not ok or type(src) ~= "table" then
    return nil, { tostring(key) .. ": builder failed: " .. tostring(src) }
  end
  local ctx = { key = key, warnings = {}, prog = { slots = {} }, usedMedia = {}, media = {},
                colorNodes = {}, colorDefs = {} }
  local saveProg = E.prog
  ReadUserColors()
  local okC, th = pcall(CompileBody, ctx, src)
  E.prog = saveProg
  if not okC then
    local w = ctx.warnings
    w[#w + 1] = tostring(key) .. ": compile error: " .. tostring(th)
    return nil, w
  end
  return th, ctx.warnings
end

-- A builder for the registered `key` of the addon (Themes.Source: the source table of a
-- source text or of a builder function, or its error), nil when the key is not
-- registered.
function TV.Builder(nsArg, key)
  local Th = nsArg.Themes
  if not Th.IsRegistered(key) then return nil end
  return function()
    local ok, src = Th.Source(key)
    if not ok then error(src, 0) end
    return src
  end
end

---------------------------------------------------------------------------
-- Canonical drawn values of a compiled theme, in either form (round 4 or compact):
-- what the engines read, defaults applied, every colour as its 4 numbers, the colours of
-- the three fill states of a bar layer that follows the state (a `base` layer or a fill
-- span) and the state-0 colours of everything else.
---------------------------------------------------------------------------
local FILL_SPAN = { fill = true, fillEnd = true }
-- th.colors names the addon reads or the tests require (the compact form has only these)
local PALETTE = { "xp", "rested", "label", "value", "dim", "accent", "pause", "bg", "border" }
local WRAP_H = { H = "REPEAT", HV = "REPEAT", V = "CLAMP" }
local WRAP_V = { V = "REPEAT", HV = "REPEAT", H = "CLAMP" }

local function Rgba(c)
  if type(c) ~= "table" then return c end
  return { c[1], c[2], c[3], c[4] }
end

local function Copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for i = 1, #t do out[i] = t[i] end
  return out
end

local function IsList(x) return type(x) == "table" and type(x[1]) == "table" end

-- Colour of state k of a colour entry (a colour, or a per-state list): a list without an
-- entry for state 2 gives state 0; state 2 of a compact layer with `m` scales the alpha.
local function StateColor(x, k, m)
  local c = x
  if IsList(x) then c = x[k + 1] or x[1] end
  if k == 2 and m and not (IsList(x) and x[3]) then return { c[1], c[2], c[3], c[4] * m } end
  return Rgba(c)
end

local function StatePair(g, k, m)
  local p = g
  if IsList(g[1]) then p = g[k + 1] or g[1] end
  local f, t = p[1], p[2]
  if k == 2 and m and not (IsList(g[1]) and g[3]) then
    return { { f[1], f[2], f[3], f[4] * m }, { t[1], t[2], t[3], t[4] * m }, p.dir or g.dir }
  end
  return { Rgba(f), Rgba(t), p.dir or g.dir }
end

-- A texture spec, with the coordinates SetTex sets: the round-4 tc, or (compact form) the
-- rect flipped when it differs from the whole texture, for a spec neither tiled nor
-- sliced. Coordinates of the whole texture (0, 1, 0, 1) count as none: the engines reset
-- a texture to them before SetTex.
local function Spec(s)
  local tc = Copy(s.tc)
  if tc and tc[1] == 0 and tc[2] == 1 and tc[3] == 0 and tc[4] == 1 then tc = nil end
  if not tc and not s.tc8 and not s.tile and not s.slice then
    local l, r, t, b = s.l, s.r, s.t, s.b
    if s.flipX or s.flipY or l ~= 0 or r ~= 1 or t ~= 0 or b ~= 1 then
      if s.flipX then l, r = r, l end
      if s.flipY then t, b = b, t end
      tc = { l, r, t, b }
    end
  end
  return { path = s.path, w = s.w, h = s.h, blend = s.blend or "BLEND", l = s.l, r = s.r, t = s.t, b = s.b,
           flipX = s.flipX == true, flipY = s.flipY == true, tile = s.tile,
           wrapH = s.wrapH or WRAP_H[s.tile], wrapV = s.wrapV or WRAP_V[s.tile],
           tc = tc, tc8 = Copy(s.tc8), slice = Copy(s.slice) }
end

-- Colours of an item for the states 0 .. last (m: the alpha factor of state 2 when the
-- item has no entry of its own for it, see Themes.lua Paint).
local function CanonPaint(out, item, last, m)
  if item.g then
    out.g, out.f = {}, {}
    for k = 0, last do
      local pair = StatePair(item.g, k, m)
      out.g[k + 1] = pair
      out.f[k + 1] = item.f and StateColor(item.f, k, m) or pair[1]
    end
  else
    out.c = {}
    for k = 0, last do out.c[k + 1] = StateColor(item.c, k, m) end
  end
  return out
end

local function Layer(L, barMaxA)
  local span = L.span or "track"
  local stateful = L.dyn or FILL_SPAN[span]
  local pad = L.pad
  if pad and pad[1] == 0 and pad[2] == 0 then pad = nil end
  local tk = L.ticks
  return CanonPaint({ id = L.id, kind = L.kind or "tex", span = span, layer = L.layer or "ARTWORK", sub = L.sub or 0,
    tex = Spec(L.tex), top = L.top or 0, bottom = L.bottom or 0, h = L.h, band = Copy(L.band),
    pad = Copy(pad), capInset = L.capInset == true, w = L.w, align = L.align or "center", dx = L.dx or 0,
    ticks = tk and { n = tk.n, w = tk.w or 1, clip = tk.clip, mid = tk.mid == true } or nil,
    stateful = stateful and true or false }, L, stateful and 2 or 0,
    L.m or (FILL_SPAN[span] and barMaxA) or nil)
end

local function Part(P, i)
  local anchor = P.anchor or "FILL"
  local out = { id = P.id, kind = P.kind or "tex", tex = Spec(P.tex), layer = P.layer or "BACKGROUND",
    sub = P.sub or (-8 + i - 1), anchor = anchor, alpha = P.alpha or 1 }
  if anchor == "FILL" then
    local ins = P.inset
    out.inset = ins and { ins[1], ins[2], ins[3], ins[4] } or { 0, 0, 0, 0 }
  else
    out.x, out.y, out.w, out.h = P.x or 0, P.y or 0, P.w, P.h
  end
  return CanonPaint(out, P, 0)
end

local function Parts(list)
  local out = {}
  for i, P in ipairs(list or {}) do out[i] = Part(P, i) end
  return out
end

local function Sep(s)
  if not s then return nil end
  return CanonPaint({ h = s.h or 1, above = s.above or 6, below = s.below or 5, mirror = s.mirror == true,
                 center = s.center, tex = Spec(s.tex) }, s, 0)
end

local function Map(t, f)
  local out = {}
  for k, v in pairs(t) do out[k] = f(v) end
  return out
end

function TV.Canon(th)
  if not th then return nil end
  local out = { key = th.key, native = th.native == true, accent = Rgba(th.accent), ui = Map(th.ui, Rgba),
                colors = {} }
  for _, name in ipairs(PALETTE) do out.colors[name] = Rgba(th.colors[name]) end
  out.fonts = { display = th.fonts.display, body = th.fonts.body, num = th.fonts.num or th.fonts.body }
  local bar = th.bar
  local layers = {}
  for i, L in ipairs(bar.layers or {}) do layers[i] = Layer(L, bar.maxAlpha) end
  out.bar = { pad = bar.pad or 8, gap = bar.gap or 3, hAdd = bar.hAdd or 0, hMin = bar.hMin or 4, layers = layers,
              panel = type(bar.panel) == "table" and Parts(bar.panel.parts) or (bar.panel or "backdrop") }
  local text = th.text
  local tx = { split = text.split == true, splitGap = text.splitGap or 4, levelFmt = text.levelFmt or "upper",
               font = {}, size = {}, colors = Map(text.colors, Rgba) }
  for _, e in ipairs(TEXT_ELEMS) do
    tx.font[e] = text.font[e]
    tx.size[e] = text.size[e]
  end
  local sh = text.shadow
  tx.shadow = { x = sh.x, y = sh.y, c = Rgba(sh.c) }
  out.text = tx
  local tt = th.tt
  if tt.native then
    out.tt = { native = true, classic = tt.colors == Themes.CLASSIC_TT }
  else
    local width, pad, fonts = tt.width, tt.pad, tt.fonts
    local t = { width = { width[1], width[2] }, pad = { pad[1], pad[2], pad[3], pad[4] }, gap = tt.gap,
                lineGap = tt.lineGap, colors = {}, fonts = {}, sep = {} }
    for k, v in pairs(tt.colors) do t.colors[k] = Rgba(v) end
    for _, name in ipairs({ "title", "body", "value", "note", "hint" }) do
      local f = fonts[name] or (name == "value" and fonts.body)
      t.fonts[name] = f and { f[1], f[2] }
    end
    t.panel = Parts(tt.panel and tt.panel.parts)
    local ic = tt.titleIcon
    if ic then t.titleIcon = { tex = Spec(ic.tex), w = ic.w, h = ic.h, gap = ic.gap or 6 } end
    local sep = tt.sep or {}
    t.sep = { header = Sep(sep.header), block = Sep(sep.block), footer = Sep(sep.footer) }
    local ld = tt.leader
    if ld then
      t.leader = CanonPaint({ h = ld.h or 1, y = ld.y or 3, min = ld.min or 12, tex = Spec(ld.tex) }, ld, 0)
    end
    local gg = tt.gauge
    if gg then
      t.gauge = { w = gg.w or 176, h = gg.h or 6, gap = gg.gap or 2, outline = Rgba(gg.outline),
                  colors = Map(gg.colors, Rgba) }
    end
    out.tt = t
  end
  return out
end

---------------------------------------------------------------------------
-- Reading a compiled item as the engines do (the tests' view of SPEC-themes 2.8)
---------------------------------------------------------------------------

-- True when a bar layer follows the fill state (BarSkin): `base` used, or a fill span.
function TV.Stateful(L)
  return (L.dyn or FILL_SPAN[L.span or "track"]) and true or false
end

-- The alpha factor of state 2 over state 0 of an item without a state-2 entry of its own.
local function MaxAlpha(th, L)
  local m = L.m
  if m == nil and FILL_SPAN[L.span or "track"] then m = th.bar.maxAlpha end
  return m
end

-- Entry of fill state k of a colour entry x (a colour, or a per-state list) of item L: the
-- compiled table itself when it has one (identity can be checked), else a new table
-- (state 2 derived from state 0). Items that do not follow the state give state 0.
local function Entry(th, L, x, k)
  if not TV.Stateful(L) then k = 0 end
  local c = x
  if IsList(x) then
    c = x[k + 1]
    if c then return c end
    c = x[1]
  end
  local m = k == 2 and MaxAlpha(th, L)
  if m then return { c[1], c[2], c[3], c[4] * m } end
  return c
end

-- The vertex colour of item L in fill state k (an item without gradient).
function TV.Color(th, L, k)
  return Entry(th, L, L.c, k or 0)
end

-- The gradient pair of item L in fill state k: from, to, dir.
function TV.Pair(th, L, k)
  k = k or 0
  local g = L.g
  if not TV.Stateful(L) then k = 0 end
  local p = g
  if IsList(g[1]) then
    p = g[k + 1]
    if not p then
      p = g[1]
      local m = k == 2 and MaxAlpha(th, L)
      if m then
        local f, t = p[1], p[2]
        return { f[1], f[2], f[3], f[4] * m }, { t[1], t[2], t[3], t[4] * m }, p.dir
      end
    end
    return p[1], p[2], p.dir
  end
  local m = k == 2 and MaxAlpha(th, L)
  if m then
    local f, t = p[1], p[2]
    return { f[1], f[2], f[3], f[4] * m }, { t[1], t[2], t[3], t[4] * m }, p.dir
  end
  return p[1], p[2], p.dir
end

-- The flat colour of a gradient item in fill state k (its from colour when it has none).
function TV.Flat(th, L, k)
  if L.f then return Entry(th, L, L.f, k or 0) end
  return (TV.Pair(th, L, k))
end

-- The draw sublevel of panel part P at position i of its list (the readers' default).
function TV.PartSub(P, i)
  return P.sub or (-8 + i - 1)
end

-- Makes ns.Themes.Compile(key) return th, warnings (the validator's list, with the
-- reasons of a theme that cannot be built), and check on every call that the compiled
-- theme draws exactly what the round-4 compiler compiled (TV.Canon, numbers compared
-- with ==): an error names the first difference.
function TV.Install(nsArg)
  local Th = nsArg.Themes
  local compile = Th.Compile
  Th.Compile = function(key)
    local legacy, warnings = TV.Compile(nsArg, key, TV.Builder(nsArg, key))
    local th = compile(key)
    if (th == nil) ~= (legacy == nil) then
      error(string.format("theme_validate: %s: compiled %s, round-4 compiler %s", tostring(key),
        tostring(th ~= nil), tostring(legacy ~= nil)), 2)
    end
    if th then
      local same, path, a, b = TV.Same(TV.Canon(th), TV.Canon(legacy), "")
      if not same then
        error(string.format("theme_validate: %s: compiled %s = %s, round-4 compiler %s", tostring(key), path,
          tostring(a), tostring(b)), 2)
      end
    end
    return th, warnings
  end
  return Th.Compile
end

-- Deep equality (numbers with ==): true, or false, the path and the two values.
function TV.Same(a, b, path)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false, path, a, b end
  for k, v in pairs(a) do
    local ok, p, x, y = TV.Same(v, b[k], path .. "." .. tostring(k))
    if not ok then return false, p, x, y end
  end
  for k, v in pairs(b) do
    if a[k] == nil then return false, path .. "." .. tostring(k), nil, v end
  end
  return true
end

return TV
