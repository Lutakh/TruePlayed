-- Themes.lua - visual themes (design/SPEC-themes.md): the registry and the compiler of
-- the theme files (2.1-2.8), the active theme (S5-S7, 3.3), the fonts (2.6, 3.2) and the
-- texture helpers shared by the bar, the tooltip and the panels (6.3).
--
-- Performance contract:
--   * builders run only when a theme is compiled (activation, a theme switch, tests); only
--     the active compiled theme is referenced (compile programs are weak-keyed);
--   * colour expressions are parsed at compile time only; Recolor() rewrites the numbers
--     of the SAME compiled tables: no allocation, stable table identities;
--   * SetFont, Font, Subst, HasSubst, SetTex, Tile, PlaceThree, PlaceNine and Gradient
--     allocate nothing; SetFont, Tile and the Place helpers skip the game calls that would
--     not change anything (per-region weak caches);
--   * nothing here runs on TICK.
--
-- Compiled colours are "hybrid" tables { r, g, b, a, r = r, g = g, b = b, a = a }: an rgba
-- array for SetVertexColor / SetTextColor and a colour table for Texture:SetGradient.
local ADDON, ns = ...
local L, C = ns.L, ns.C

local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring
local pcall, error, setmetatable = pcall, error, setmetatable
local math_floor, math_min, math_max = math.floor, math.min, math.max
local string_find, string_sub, string_gsub = string.find, string.sub, string.gsub
local string_match, string_format = string.match, string.format
local GetLocale, UnitClass = GetLocale, UnitClass

local Themes = {}
ns.Themes = Themes

local WEAK_K = { __mode = "k" }
local MEDIA_ROOT = "Interface\\AddOns\\" .. (ns.ADDON or "TruePlayed") .. "\\Media\\"
local WHITE = C.TEX_WHITE
local GAME_FONT_FALLBACK = "Fonts\\FRIZQT__.TTF"
Themes.GAME_FONT_FALLBACK = GAME_FONT_FALLBACK

-- The 13 theme keys (C.THEME_CHOICES without "class"), in menu order.
local KEYS, IS_KEY = {}, {}
for _, v in ipairs(C.THEME_CHOICES) do
  if v ~= "class" then
    KEYS[#KEYS + 1] = v
    IS_KEY[v] = true
  end
end
Themes.KEYS = KEYS

---------------------------------------------------------------------------
-- Fonts (2.6): the 23 bundled OFL fonts. subst = plain-text replacements for glyphs a
-- font lacks; min / snap / max = size rules; mono = MONOCHROME rendering.
---------------------------------------------------------------------------
local FONTS = {}
local FONT_BY_PATH = {}
do
  local DIR = MEDIA_ROOT .. "Fonts\\"
  local function Add(name, file, cyr, extra)
    local e = extra or {}
    e.name, e.file, e.path, e.cyr = name, file, DIR .. file, cyr
    local subst = e.subst
    if subst then
      for i = 1, #subst do
        local p = subst[i]
        p[3] = string_gsub(p[1], "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")   -- gsub pattern
        p[4] = string_gsub(p[2], "%%", "%%%%")                         -- replacement
      end
    end
    FONTS[name] = e
    FONT_BY_PATH[e.path] = e
  end
  Add("Orbitron", "Orbitron-Bold.ttf", false, { display = true, subst = {
    { "\194\183", "\226\128\162" },   -- middle dot -> bullet
    { "\194\171", "\"" },             -- guillemets -> straight quote
    { "\194\187", "\"" },
  } })
  Add("Rajdhani", "Rajdhani-SemiBold.ttf", false)
  Add("Cinzel", "Cinzel-Bold.ttf", false)
  Add("EBGaramond", "EBGaramond-Medium.ttf", true)
  Add("PressStart2P", "PressStart2P-Regular.ttf", true, { min = 8, snap = 8, max = 16, mono = true })
  Add("PixelifySans", "PixelifySans-Regular.ttf", false)
  Add("UncialAntiqua", "UncialAntiqua-Regular.ttf", false)
  Add("AlegreyaSans", "AlegreyaSans-Medium.ttf", true)
  Add("GrenzeGotisch", "GrenzeGotisch-SemiBold.ttf", false)
  Add("BarlowCondensed", "BarlowCondensed-Medium.ttf", false)
  Add("CormorantSC", "CormorantSC-Bold.ttf", true)
  Add("CormorantGaramond", "CormorantGaramond-SemiBold.ttf", true)
  Add("GermaniaOne", "GermaniaOne-Regular.ttf", false)
  Add("Signika", "Signika-Medium.ttf", false)
  Add("IMFellEnglishSC", "IMFellEnglishSC-Regular.ttf", false)
  Add("Barlow", "Barlow-Medium.ttf", false)
  Add("Philosopher", "Philosopher-Bold.ttf", true)
  Add("Lora", "Lora-Medium.ttf", true)
  Add("Metamorphous", "Metamorphous-Regular.ttf", false)
  Add("NunitoSans", "NunitoSans-SemiBold.ttf", true)
  Add("Macondo", "Macondo-Regular.ttf", false, { subst = { { "\194\160", " " } } })   -- NBSP
  Add("Spectral", "Spectral-Medium.ttf", true)
  Add("UnifrakturCook", "UnifrakturCook-Bold.ttf", false)
end
Themes.FONTS = FONTS

-- Locale keys of the texts a "display" font may render (with percent and number texts).
Themes.DISPLAY_KEYS = { "LEVEL_SHORT_FMT", "LEVEL_TITLE_FMT", "LEVEL_PCT_FMT", "LEVEL_CAP_FMT",
  "LEVEL_CAP_TAG", "LEVEL_CAP_TAG_TITLE", "XP_LABEL", "ADDON_TITLE", "WIN_TITLE",
  "GRAPH_TITLE_FMT", "GRAPH_WINDOW_30", "GRAPH_WINDOW_60", "GRAPH_WINDOW_300" }

-- Media shared by every theme (6.1): "common/<name>" = Media/Themes/common/<name>.tga.
local COMMON_MEDIA = {
  glow = { 64, 32, grey = true },   -- soft horizontal glow, 3-sliced with 16-texel caps
}
Themes.COMMON_MEDIA = COMMON_MEDIA

---------------------------------------------------------------------------
-- Colours: hybrid tables, the classic tooltip palette (4.3)
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

do
  local K = C.COLORS
  local function Copy(c) return NewColor(c[1], c[2], c[3], c[4] or 1) end
  Themes.CLASSIC_TT = {
    title = Copy(K.accent), mode = Copy(K.label), label = Copy(K.label), value = Copy(K.value),
    dim = Copy(K.dim), header = Copy(K.accent), pause = Copy(K.pause), hint = Copy(K.dim),
    levelLabel = Copy(K.label), levelValue = Copy(K.value), levelValueRested = Copy(K.value),
    rested = Copy(K.value), ccDim = C.CC.dim,
  }
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

-- True when E differs from the user colours a program was last run with.
local function UserColorsDiffer(prog)
  return prog.xpOn ~= E.xpOn or prog.rsOn ~= E.rsOn
    or prog.xr ~= E.xr or prog.xg ~= E.xg or prog.xb ~= E.xb
    or prog.rr ~= E.rr or prog.rg ~= E.rg or prog.rb ~= E.rb
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
local WHENS = { bar = true, box = true }
local LAYER_FIELDS = Set({ "id", "span", "layer", "sub", "file", "rect", "flipX", "flipY", "rot", "tile",
  "blend", "color", "grad", "flat", "alpha", "maxAlpha", "top", "h", "bottom", "band", "pad",
  "capInset", "w", "align", "dx", "caps", "three", "nine", "ticks", "when" })
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
  Lc.when = Choice(ctx, src.when, nil, WHENS, where .. ".when")

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
local BOX_SIZE = { s1 = 2, s2 = -1, s3 = -1 }
local TEXT_ROLES = { "label", "value", "levelLabel", "levelValue", "xpText", "sep", "marker", "hint",
                     "slot2", "slot3", "dimmed" }
local TEXT_ROLE_DEF = { label = "label", value = "value", levelLabel = "label", levelValue = "value",
                        xpText = "label", sep = "label", marker = "label", hint = "label", slot2 = "value",
                        slot3 = "label", dimmed = "dim" }
local FONT_ROLES = { display = true, body = true, num = true, game = true }
-- Elements that render arbitrary strings: never the display role (SPEC 8.3; `hint` shows a
-- free locale sentence, so it is included too).
local NO_DISPLAY = { s1 = true, s2 = true, s3 = true, xp = true, sep = true, levelValue = true, hint = true }
local TEXT_FIELDS = Set({ "font", "size", "boxSize", "split", "splitGap", "levelFmt", "colors", "shadow" })
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
  out.boxSize = ElemMap(ctx, text.boxSize, "text.boxSize", BOX_SIZE, Set({ "s1", "s2", "s3" }), IsDelta)
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
local builders = {}
local programs = setmetatable({}, WEAK_K)   -- compiled theme -> its colour program
local genCounter = 0

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

-- Pure: compiles a registered theme with the current user colours; the active theme is
-- left alone. Returns th (nil when the theme cannot be built) and a list of warnings.
function Themes.Compile(key)
  local builder = builders[key]
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
  genCounter = genCounter + 1
  th.gen = genCounter
  programs[th] = ctx.prog
  return th, ctx.warnings
end

function Themes.Register(key, builder)
  if key == "class" or not IS_KEY[key] then
    error("Themes.Register: unknown theme key " .. tostring(key), 2)
  end
  if builders[key] then error("Themes.Register: duplicate theme key " .. tostring(key), 2) end
  if type(builder) ~= "function" then error("Themes.Register: builder function expected", 2) end
  builders[key] = builder
end

function Themes.IsRegistered(key)
  return builders[key] ~= nil
end

---------------------------------------------------------------------------
-- Active theme (S5-S7, 3.3)
---------------------------------------------------------------------------
local activeTh, activeKey
local ClearTexCaches             -- texture helper caches (defined with the helpers below)
local ready = false        -- DB_READY seen: the class is known
local resolved = false     -- the setting was resolved after DB_READY (the result is kept)

function Themes.Resolve(value, classFile)
  local key = value
  if value == "class" then key = C.CLASS_THEMES[classFile] or "futuriste" end
  if type(key) ~= "string" or not builders[key] then
    key = builders.futuriste and "futuriste" or "actuel"
  end
  return key
end

function Themes.Setting()
  local s = ns.settings
  local v = type(s) == "table" and s.theme or nil
  if type(v) ~= "string" then v = C.DEFAULTS.theme end
  return v
end

local function ClassFile()
  if not UnitClass then return nil end
  local ok, _, cls = pcall(UnitClass, "player")
  if ok and type(cls) == "string" then return cls end
  return nil
end

-- Compiles `key` (then futuriste, then actuel when it cannot be built) and makes it
-- active; the previous compiled theme is dropped.
local function Activate(key)
  local th, warnings = Themes.Compile(key)
  if warnings and #warnings > 0 and ns.Util then
    for i = 1, #warnings do ns.Util.Debug("theme: %s", warnings[i]) end
  end
  if not th and key ~= "futuriste" then th = Themes.Compile("futuriste") end
  if not th and key ~= "actuel" then th = Themes.Compile("actuel") end
  if th then
    activeTh, activeKey = th, th.key
    ClearTexCaches()              -- they hold specs of the previous theme (P5)
  end
end

-- The compiled active theme. Before DB_READY: resolved without a class, every call
-- (nothing is kept but the compiled theme). The first call after DB_READY resolves with
-- the class, silently, and the result is kept until the setting or the table changes.
function Themes.Active()
  if not resolved or not activeTh then
    local key = Themes.Resolve(Themes.Setting(), ready and ClassFile() or nil)
    if ready then resolved = true end
    if key ~= activeKey or not activeTh then
      Activate(key)
    else
      local prog = programs[activeTh]
      ReadUserColors()
      if prog and UserColorsDiffer(prog) then
        RunProgram(prog)
        genCounter = genCounter + 1
        activeTh.gen = genCounter
      end
    end
  end
  return activeTh
end

function Themes.ActiveKey()
  Themes.Active()
  return activeKey
end

-- Theme default of the XP / rested colour (before the user's override): Options swatches.
function Themes.DefaultColor(which)
  local th = Themes.Active()
  return th and th.colors[which] or nil
end

-- Recolours the active theme in place after a user colour change, then
-- THEME_CHANGED(key, key, "colors").
function Themes.Recolor()
  local th = activeTh
  if not th then return end
  local prog = programs[th]
  if not prog then return end
  ReadUserColors()
  RunProgram(prog)
  genCounter = genCounter + 1
  th.gen = genCounter
  ns.SendMessage("THEME_CHANGED", activeKey, activeKey, "colors")
end

-- "theme" changed or the SavedVariables table was swapped: resolve again.
local function Reresolve(swapped)
  if not ready then return end
  if not activeTh then
    resolved = false              -- nobody holds a theme yet: Active() resolves later
    return
  end
  local key = Themes.Resolve(Themes.Setting(), ClassFile())
  resolved = true
  if key ~= activeKey then
    local prev = activeKey
    Activate(key)
    if activeKey ~= prev then ns.SendMessage("THEME_CHANGED", activeKey, prev, "theme") end
  elseif swapped then
    local prog = programs[activeTh]
    ReadUserColors()
    if prog and UserColorsDiffer(prog) then Themes.Recolor() end
  end
end

local function IsColorPath(path)
  return type(path) == "string" and (string_find(path, "widget.xpColor", 1, true) == 1
    or string_find(path, "widget.restedColor", 1, true) == 1)
end

ns.RegisterMessage("SETTINGS_CHANGED", Themes, function(_, path)
  if path == "theme" then
    Reresolve(false)
  elseif IsColorPath(path) then
    Themes.Recolor()
  end
end)
ns.RegisterMessage("DB_SWAPPED", Themes, function() Reresolve(true) end)
ns.RegisterMessage("DB_READY", Themes, function()
  ready = true
  resolved = false               -- the first Active() call resolves with the class, silently
end)

---------------------------------------------------------------------------
-- Fonts: resolution (2.6), SetFont with its cache and the missing-file probe (3.2)
---------------------------------------------------------------------------
local FLAGS = {
  [false] = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" },
  [true] = { none = "MONOCHROME", thin = "MONOCHROME,OUTLINE", thick = "MONOCHROME,THICKOUTLINE" },
}
local fsPath = setmetatable({}, WEAK_K)
local fsSize = setmetatable({}, WEAK_K)
local fsFlags = setmetatable({}, WEAK_K)
local probe = nil              -- nil: not probed yet; true: SetFont reports success
local missingWarned = false

local function GameFont()
  return STANDARD_TEXT_FONT or GAME_FONT_FALLBACK
end

-- FONTS entry used for a role of the active theme (nil = the game font).
local function RoleEntry(role)
  if role == "game" then return nil end
  local th = Themes.Active()
  local fonts = th and th.fonts
  if not fonts then return nil end
  local name = fonts[role] or fonts.body
  if name == nil or name == "game" then return nil end
  local e = FONTS[name]
  if not e or e.missing then return nil end
  local loc = GetLocale and GetLocale()
  if loc == "koKR" or loc == "zhCN" or loc == "zhTW" then return nil end
  if loc == "ruRU" and not e.cyr then return nil end
  return e
end

function Themes.Font(role, size)
  local e = RoleEntry(role)
  size = math_floor((tonumber(size) or 12) + 0.5)
  if not e then return GameFont(), size, false end
  local lo, snap, hi = e.min, e.snap, e.max
  if lo and size < lo then size = lo end
  if snap then size = math_max(snap, math_floor(size / snap + 0.5) * snap) end
  if hi and size > hi then size = hi end
  return e.path, size, e.mono == true
end

function Themes.FontFailed(path)
  local e = FONT_BY_PATH[path]
  if not e then return end
  e.missing = true
  if missingWarned then return end
  missingWarned = true
  if ns.Util and ns.Util.Print then ns.Util.Print(L.THEME_FONT_MISSING, e.file) end
end

-- outline: "none" | "thin" | "thick" (widget.outline; anything else = thin, as Bar).
function Themes.SetFont(fs, role, size, outline)
  local path, sz, mono = Themes.Font(role, size)
  local set = FLAGS[mono]
  local flags = set[outline] or set.thin
  if fsPath[fs] == path and fsSize[fs] == sz and fsFlags[fs] == flags then return path end
  if probe == nil then probe = fs:SetFont(GameFont(), 12, "") and true or false end
  local ok = fs:SetFont(path, sz, flags)
  if not ok and probe and FONT_BY_PATH[path] then
    Themes.FontFailed(path)
    path, sz = Themes.Font(role, size)      -- the game font now
    fs:SetFont(path, sz, flags)
  end
  fsPath[fs], fsSize[fs], fsFlags[fs] = path, sz, flags
  return path
end

function Themes.HasSubst(role)
  local e = RoleEntry(role)
  return e ~= nil and e.subst ~= nil
end

-- The text with the font's replacements applied; the SAME string when none applies.
function Themes.Subst(role, text)
  local e = RoleEntry(role)
  local list = e and e.subst
  if not list or type(text) ~= "string" then return text end
  for i = 1, #list do
    local p = list[i]
    if string_find(text, p[1], 1, true) then text = (string_gsub(text, p[3], p[4])) end
  end
  return text
end

---------------------------------------------------------------------------
-- Texture helpers (6.3). Weak per-texture caches skip calls that change nothing; SetTex
-- (called after every reset of a pooled texture) clears a texture's entries, and a theme
-- switch clears them all (Activate: their values are specs of the compiled theme, and
-- only the active compiled theme may stay referenced, P5).
---------------------------------------------------------------------------
local tileSpec = setmetatable({}, WEAK_K)
local tileW = setmetatable({}, WEAK_K)
local tileH = setmetatable({}, WEAK_K)
local sliceSpec = setmetatable({}, WEAK_K)   -- [piece] = spec of its slice coordinates
local slicePos = setmetatable({}, WEAK_K)    -- [piece] = its position (1..3 / 1..9) in that slice

ClearTexCaches = function()
  for t in pairs(tileSpec) do tileSpec[t] = nil end
  for t in pairs(tileW) do tileW[t] = nil end
  for t in pairs(tileH) do tileH[t] = nil end
  for t in pairs(sliceSpec) do sliceSpec[t] = nil end
  for t in pairs(slicePos) do slicePos[t] = nil end
end

-- Path (+ wrap modes when tiled), texture coordinates and blend mode; never a colour.
function Themes.SetTex(t, spec)
  if spec.tile then
    t:SetTexture(spec.path, spec.wrapH, spec.wrapV)
  else
    t:SetTexture(spec.path)
  end
  local tc8, tc = spec.tc8, spec.tc
  if tc8 then
    t:SetTexCoord(tc8[1], tc8[2], tc8[3], tc8[4], tc8[5], tc8[6], tc8[7], tc8[8])
  elseif tc then
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
  end
  t:SetBlendMode(spec.blend or "BLEND")
  tileSpec[t], sliceSpec[t], slicePos[t] = nil, nil, nil
end

-- Repeat coordinates of a tiled texture drawn w x h px (1 texel = 1 px).
function Themes.Tile(t, spec, w, h)
  if tileSpec[t] == spec and tileW[t] == w and tileH[t] == h then return end
  tileSpec[t], tileW[t], tileH[t] = spec, w, h
  local tile = spec.tile
  local l, r, tt, b = spec.l, spec.r, spec.t, spec.b
  if tile == "H" or tile == "HV" then l, r = 0, (w > 0 and w or 0) / spec.w end
  if tile == "V" or tile == "HV" then tt, b = 0, (h > 0 and h or 0) / spec.h end
  if spec.flipX then l, r = r, l end
  if spec.flipY then tt, b = b, tt end
  t:SetTexCoord(l, r, tt, b)
end

local function Place(t, rel, x, y, w, h)
  if w <= 0 or h <= 0 then
    t:Hide()
    return
  end
  t:SetSize(w, h)
  t:SetPoint("BOTTOMLEFT", rel, "BOTTOMLEFT", x, y)
  t:Show()
end

-- Half a texel inwards at both ends of a stretched middle range [a, b] of a texture n
-- texels wide (a > b when mirrored): bilinear filtering then never blends the corner
-- texels into the stretched piece (it would smear them over half a texel times the
-- stretch, e.g. 11 px of a frame line along a 360 px track). A range of one texel
-- collapses to that texel's centre; an empty one is left alone.
local function Inset(a, b, n)
  local d = 0.5 / n
  if b - a >= 2 * d - 1e-9 then return a + d, b - d end
  if a - b >= 2 * d - 1e-9 then return a - d, b + d end
  return a, b
end

-- Slice boundaries (texture coordinates) of a spec: 4 u values (left to right as drawn)
-- and 4 v values (top to bottom as drawn), mirrored by flipX / flipY, plus the middle
-- column (mu2, mu3) and the middle row (mv2, mv3) moved in by half a texel (Inset).
local function Cuts(spec, horizontalOnly)
  local c = spec.slice[1]
  local cu, cv = c / spec.w, c / spec.h
  local l, r, t, b = spec.l, spec.r, spec.t, spec.b
  local u1, u2, u3, u4 = l, l + cu, r - cu, r
  if spec.flipX then u1, u2, u3, u4 = r, r - cu, l + cu, l end
  local v1, v2, v3, v4 = t, t + cv, b - cv, b
  if horizontalOnly then v2, v3 = t, b end
  if spec.flipY then
    if horizontalOnly then
      v1, v4 = b, t
      v2, v3 = b, t
    else
      v1, v2, v3, v4 = b, b - cv, t + cv, t
    end
  end
  local mu2, mu3 = Inset(u2, u3, spec.w)
  local mv2, mv3 = v2, v3
  if not horizontalOnly then mv2, mv3 = Inset(v2, v3, spec.h) end
  return u1, u2, u3, u4, v1, v2, v3, v4, mu2, mu3, mv2, mv3
end

-- True when a piece already has the coordinates of position i of spec. Every piece is
-- checked: a caller may hand the same textures back in another order (pooled textures
-- taken again by their layer), and a piece then holds another position's coordinates.
local function SliceOK(t, spec, i)
  return sliceSpec[t] == spec and slicePos[t] == i
end

local function SliceSet(t, spec, i)
  sliceSpec[t], slicePos[t] = spec, i
end

-- Horizontal 3-slice (L4): texs = { L, M, R }, at x, y (BOTTOMLEFT of rel), w x h px.
function Themes.PlaceThree(texs, spec, rel, x, y, w, h)
  local tL, tM, tR = texs[1], texs[2], texs[3]
  if not (SliceOK(tL, spec, 1) and SliceOK(tM, spec, 2) and SliceOK(tR, spec, 3)) then
    local u1, u2, u3, u4, v1, _, _, v4, mu2, mu3 = Cuts(spec, true)
    tL:SetTexCoord(u1, u2, v1, v4)
    tM:SetTexCoord(mu2, mu3, v1, v4)
    tR:SetTexCoord(u3, u4, v1, v4)
    SliceSet(tL, spec, 1)
    SliceSet(tM, spec, 2)
    SliceSet(tR, spec, 3)
  end
  local p = spec.slice[2]
  local side, mid = p, w - 2 * p
  if w < 2 * p then
    side = math_floor(w / 2)
    mid = 0
  end
  Place(tL, rel, x, y, side, h)
  Place(tR, rel, x + w - side, y, side, h)
  Place(tM, rel, x + side, y, mid, h)
end

-- 9-slice (6.3): texs[1..9] = TL, T, TR, L, C, R, BL, B, BR, at x, y (BOTTOMLEFT of rel).
function Themes.PlaceNine(texs, spec, rel, x, y, w, h)
  local ok = true
  for i = 1, 9 do
    if not SliceOK(texs[i], spec, i) then
      ok = false
      break
    end
  end
  if not ok then
    local u1, u2, u3, u4, v1, v2, v3, v4, mu2, mu3, mv2, mv3 = Cuts(spec, false)
    texs[1]:SetTexCoord(u1, u2, v1, v2); texs[2]:SetTexCoord(mu2, mu3, v1, v2); texs[3]:SetTexCoord(u3, u4, v1, v2)
    texs[4]:SetTexCoord(u1, u2, mv2, mv3); texs[5]:SetTexCoord(mu2, mu3, mv2, mv3); texs[6]:SetTexCoord(u3, u4, mv2, mv3)
    texs[7]:SetTexCoord(u1, u2, v3, v4); texs[8]:SetTexCoord(mu2, mu3, v3, v4); texs[9]:SetTexCoord(u3, u4, v3, v4)
    for i = 1, 9 do SliceSet(texs[i], spec, i) end
  end
  local p = spec.slice[2]
  if w < 2 * p or h < 2 * p then p = math_floor(math_min(w, h) / 2) end
  local mw, mh = w - 2 * p, h - 2 * p
  local xr, yt = x + w - p, y + h - p
  Place(texs[1], rel, x, yt, p, p);     Place(texs[2], rel, x + p, yt, mw, p);     Place(texs[3], rel, xr, yt, p, p)
  Place(texs[4], rel, x, y + p, p, mh); Place(texs[5], rel, x + p, y + p, mw, mh); Place(texs[6], rel, xr, y + p, p, mh)
  Place(texs[7], rel, x, y, p, p);      Place(texs[8], rel, x + p, y, mw, p);      Place(texs[9], rel, xr, y, p, p)
end

-- Direction, from, to and flat colour of any gradient form: a compiled per-state gradient
-- { dir =, pair1..3 } (k = the fill state, default 0), one pair { from, to, dir = }, or
-- { dir, from, to }; `flat` is a colour or a per-state list of colours.
local function GradientParts(g, flat, k)
  local dir, from, to
  local first = g[1]
  if type(first) == "string" then
    dir, from, to = first, g[2], g[3]
  elseif type(first) == "table" and type(first[1]) == "table" then
    local pair = g[(k or 0) + 1] or first
    dir, from, to = g.dir or pair.dir, pair[1], pair[2]
  else
    dir, from, to = g.dir, first, g[2]
  end
  if flat and type(flat[1]) == "table" then flat = flat[(k or 0) + 1] or flat[1] end
  return dir, from, to, flat
end

-- The flat colour (the from colour when none) comes first: a gradient drawn over it
-- replaces it, and a client that accepts the gradient call but draws nothing still shows
-- the layer's own colour instead of the default opaque white.
local function ApplyGradient(t, dir, from, to, flat)
  local fl = flat or from
  t:SetVertexColor(fl.r or fl[1], fl.g or fl[2], fl.b or fl[3], fl.a or fl[4] or 1)
  if t.SetGradient and pcall(t.SetGradient, t, dir, from, to) then return 1 end
  if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, dir, from.r or from[1], from.g or from[2],
      from.b or from[3], from.a or from[4] or 1, to.r or to[1], to.g or to[2], to.b or to[3],
      to.a or to[4] or 1) then
    return 2
  end
  return 3
end

-- Gradient (L6): the flat colour, then SetGradient with colour tables, else
-- SetGradientAlpha. Returns 1, 2 or 3 (3 = only the flat colour; forms of GradientParts).
function Themes.Gradient(t, g, flat, k)
  local dir, from, to, fl = GradientParts(g, flat, k)
  return ApplyGradient(t, dir, from, to, fl)
end

-- Gradient over a horizontal 3-slice (n = 3: L, M, R) or a 9-slice (n = 9: TL .. BR)
-- drawn w x h px with corners of p px (sized as PlaceThree / PlaceNine size them): each
-- piece gets the part of the ramp it covers, so the pieces read as one surface (the same
-- ramp on every piece would restart in each row or column). Same forms and result as
-- Gradient; the colours at the cuts live in reused tables (no allocation).
local cut1 = { 0, 0, 0, 0, r = 0, g = 0, b = 0, a = 0 }
local cut2 = { 0, 0, 0, 0, r = 0, g = 0, b = 0, a = 0 }
local seg1, seg2, seg3 = {}, {}, {}

local function Lerp(out, from, to, f)
  local r0, g0, b0, a0 = from.r or from[1], from.g or from[2], from.b or from[3], from.a or from[4] or 1
  local r1, g1, b1, a1 = to.r or to[1], to.g or to[2], to.b or to[3], to.a or to[4] or 1
  SetColor4(out, r0 + (r1 - r0) * f, g0 + (g1 - g0) * f, b0 + (b1 - b0) * f, a0 + (a1 - a0) * f)
end

function Themes.GradientSliced(texs, n, g, flat, k, w, h, p)
  local dir, from, to, fl = GradientParts(g, flat, k)
  local horizontal = dir == "HORIZONTAL"
  if n == 3 and not horizontal then
    local res
    for i = 1, 3 do res = ApplyGradient(texs[i], dir, from, to, fl) end
    return res
  end
  local side = p or 0
  if n == 3 then
    if w < 2 * side then side = math_floor(w / 2) end
  elseif w < 2 * side or h < 2 * side then
    side = math_floor(math_min(w, h) / 2)
  end
  local len = horizontal and w or h
  local f1, f2 = 0, 1
  if len > 0 then f1, f2 = side / len, (len - side) / len end
  Lerp(cut1, from, to, f1)
  Lerp(cut2, from, to, f2)
  seg1[1], seg1[2] = from, cut1     -- left column / bottom row
  seg2[1], seg2[2] = cut1, cut2
  seg3[1], seg3[2] = cut2, to       -- right column / top row
  local res
  for i = 1, n do
    local seg
    if horizontal then
      local col = (i - 1) % 3
      seg = (col == 0 and seg1) or (col == 1 and seg2) or seg3
    else                              -- 9-slice rows top to bottom: TL T TR / L C R / BL B BR
      local row = math_floor((i - 1) / 3)
      seg = (row == 2 and seg1) or (row == 1 and seg2) or seg3
    end
    res = ApplyGradient(texs[i], dir, seg[1], seg[2], fl)
  end
  return res
end
