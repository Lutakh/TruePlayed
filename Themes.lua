-- Themes.lua - visual themes (design/SPEC-themes.md): the registry and the compiler of
-- the theme sources (2.1-2.8), the active theme (S5-S7, 3.3), the fonts (2.6, 3.2) and the
-- texture helpers shared by the bar, the tooltip and the panels (6.3).
--
-- Performance contract:
--   * a theme source (compact text, M3) is turned into its table only when the theme is
--     compiled (activation, a theme switch, tests); only the active compiled theme is
--     referenced (compile programs are weak-keyed);
--   * the compiled form is compact (M1): plain { r, g, b, a } colour arrays, the static
--     ones shared within a compile, no per-state copy a reader can derive, no default
--     field (the metatable of each compiled record gives the defaults);
--   * colour expressions are parsed at compile time only; Recolor() rewrites the numbers
--     of the SAME compiled tables (the dynamic colours only): no allocation, stable table
--     identities;
--   * SetFont, Font, Subst, HasSubst, SetTex, Tile, PlaceThree, PlaceNine and Gradient
--     allocate nothing; SetFont, Tile and the Place helpers skip the game calls that would
--     not change anything (per-region weak caches);
--   * nothing here runs on TICK.
-- The compiler is robust and silent: bad data falls back on the defaults. The warnings
-- of a theme source come from the test-only validator (tests/theme_validate.lua, M2).
local ADDON, ns = ...
local L, C = ns.L, ns.C

local type, pairs, ipairs, tonumber, tostring = type, pairs, ipairs, tonumber, tostring
local pcall, error, setmetatable, rawget, next = pcall, error, setmetatable, rawget, next
local math_floor, math_min, math_max = math.floor, math.min, math.max
local string_find, string_sub, string_gsub = string.find, string.sub, string.gsub
local string_match, string_format, table_concat = string.match, string.format, table.concat
local GetLocale, UnitClass = GetLocale, UnitClass
-- Theme sources are compiled in an empty environment (M3): Lua 5.1 (the game) has
-- loadstring and setfenv, Lua 5.2+ (the offline tests) load with an environment. The only
-- file allowed to read these (tests/lint51.lua, .luacheckrc, tests/check_globals.lua).
local loadstring, setfenv, load = loadstring, setfenv, load

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
-- Compiled form (SPEC-themes 2.8). Colours are plain { r, g, b, a } arrays. A field equal
-- to its default is not stored: the metatable of the record gives it (the defaults below
-- are shared constants, never written). Readers index fields as usual.
---------------------------------------------------------------------------
local function Byte255(x)
  return math_floor(math_min(1, math_max(0, x or 0)) * 255 + 0.5)
end

-- "|cffrrggbb" of a colour (tooltip ccDim).
local function ColorCode(c)
  return string_format("|cff%02x%02x%02x", Byte255(c[1]), Byte255(c[2]), Byte255(c[3]))
end

local TEXT_ELEMS = { "s1", "s2", "s3", "level", "levelValue", "xpLabel", "xp", "sep", "marker", "hint" }
local TEXT_SIZE = { s1 = 2, s2 = 0, s3 = -1, level = 0, levelValue = 0, xpLabel = 0, xp = 0, sep = 0,
                    marker = -1, hint = -1 }

-- The metatables of the compiled records (their __index: the defaults).
local MT = {}
do
  local white = { 1, 1, 1, 1 }
  MT.spec = { __index = { path = WHITE, w = 8, h = 8, l = 0, r = 1, t = 0, b = 1, blend = "BLEND" } }
  local whiteSpec = setmetatable({}, MT.spec)            -- the white 8 x 8 file
  MT.layer = { __index = { kind = "tex", span = "track", layer = "ARTWORK", sub = 0, tex = whiteSpec,
    top = 0, bottom = 0, capInset = false, align = "center", dx = 0, dyn = false, c = white } }
  MT.part = { __index = { kind = "tex", layer = "BACKGROUND", tex = whiteSpec, anchor = "FILL", x = 0, y = 0,
    alpha = 1, dyn = false, c = white } }
  MT.sep = { __index = { h = 1, above = 6, below = 5, mirror = false, tex = whiteSpec, dyn = false, c = white } }
  MT.leader = { __index = { h = 1, y = 3, min = 12, tex = whiteSpec, dyn = false, c = white } }
  MT.icon = { __index = { gap = 6, tex = whiteSpec } }
  MT.gauge = { __index = { w = 176, h = 6, gap = 2 } }
  MT.ticks = { __index = { w = 1 } }
  MT.tt = { __index = { native = false, width = { 280, 440 }, pad = { 12, 12, 10, 10 }, gap = 8, lineGap = 3,
    panel = { parts = {} }, sep = {} } }
  MT.font = { __index = {} }                              -- every text element: "body"
  for i = 1, #TEXT_ELEMS do MT.font.__index[TEXT_ELEMS[i]] = "body" end
  MT.size = { __index = TEXT_SIZE }
  MT.shadow = { __index = { x = 1, y = -1 } }
  MT.text = { __index = { font = setmetatable({}, MT.font), size = setmetatable({}, MT.size),
    split = false, splitGap = 4, levelFmt = "upper",
    shadow = setmetatable({ c = { 0, 0, 0, 0.8 } }, MT.shadow) } }
  MT.bar = { __index = { pad = 8, gap = 3, hAdd = 0, hMin = 4, maxAlpha = 0.35, panel = "backdrop" } }
  MT.fonts = { __index = function(t, k)                   -- num defaults to body
    if k == "num" then return rawget(t, "body") end
  end }
end

-- The classic tooltip palette (4.3), shared by the native themes (th.tt.colors).
do
  local K = C.COLORS
  local function Copy(c) return { c[1], c[2], c[3], c[4] or 1 } end
  Themes.CLASSIC_TT = {
    title = Copy(K.accent), mode = Copy(K.label), label = Copy(K.label), value = Copy(K.value),
    dim = Copy(K.dim), header = Copy(K.accent), pause = Copy(K.pause), hint = Copy(K.dim),
    levelLabel = Copy(K.label), levelValue = Copy(K.value), levelValueRested = Copy(K.value),
    rested = Copy(K.value), ccDim = C.CC.dim,
  }
end

---------------------------------------------------------------------------
-- Colour expressions (2.3). Parsed into nodes at compile time:
--   { kind, r, g, b, a (K_LIT), ref (K_NAME: the name, then the linked node), alpha,
--     uXp, uRested, uBase (the dynamic sources the evaluation may read), bad,
--     [1..] = modifiers: op (1 lighten, -1 darken), k, op, k, ... }
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
  for i = 1, #node, 2 do
    local x = node[i + 1]
    if node[i] > 0 then
      r, g, b = r + (1 - r) * x, g + (1 - g) * x, b + (1 - b) * x   -- lighten
    else
      r, g, b = r * (1 - x), g * (1 - x), b * (1 - x)               -- darken
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

-- The colour program of a compiled theme (programs[th]): the dynamic colours only, 5
-- entries each (out = the compiled array, node, def or false, k = fill state, f = alpha
-- factor), plus xp / rested (the theme's nodes), dimOf (the tooltip palette when its dim
-- is dynamic: ccDim follows) and u (the user colours of the last run).
-- Rewrites every dynamic colour in place from the current E.
local function RunProgram(prog)
  E.prog = prog
  for i = 1, #prog, 5 do
    local out, node, def, k = prog[i], prog[i + 1], prog[i + 2], prog[i + 3]
    local r, g, b, a
    if def and not UsesUser(node, k) then
      r, g, b, a = Eval(def, k)
    else
      r, g, b, a = Eval(node, k)
    end
    out[1], out[2], out[3], out[4] = r, g, b, a * prog[i + 4]
  end
  local tc = prog.dimOf
  if tc then tc.ccDim = ColorCode(tc.dim) end    -- only when the tooltip dim is dynamic
  E.prog = nil
  local u = prog.u
  u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8] = E.xpOn, E.xr, E.xg, E.xb, E.rsOn, E.rr, E.rg, E.rb
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
  local u = prog.u
  return u[1] ~= E.xpOn or u[5] ~= E.rsOn or u[2] ~= E.xr or u[3] ~= E.xg or u[4] ~= E.xb
    or u[6] ~= E.rr or u[7] ~= E.rg or u[8] ~= E.rb
end

---------------------------------------------------------------------------
-- Compiler (compile time only: these allocate). Bad data falls back on the defaults and
-- is reported by nothing here: the tests validate the sources (tests/theme_validate.lua).
---------------------------------------------------------------------------
local function Set(list)
  local t = {}
  for i = 1, #list do t[list[i]] = true end
  return t
end

local function IsNum(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- A number field: the value, or `def` when absent or invalid.
local function Num(v, def, lo, hi, int)
  if v == nil or not IsNum(v) or (lo and v < lo) or (hi and v > hi) or (int and v % 1 ~= 0) then return def end
  return v
end

local function Choice(v, def, set)
  if v == nil or not set[v] then return def end
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

-- One colour expression -> node (nil when it is not one).
local function ParseExpr(s, allowBase)
  local node, rest
  local hex = string_match(s, "^#(%x+)")
  if hex then
    if #hex ~= 6 and #hex ~= 8 then return nil end
    node = { kind = K_LIT, r = tonumber(string_sub(hex, 1, 2), 16) / 255,
             g = tonumber(string_sub(hex, 3, 4), 16) / 255, b = tonumber(string_sub(hex, 5, 6), 16) / 255,
             a = (#hex == 8) and tonumber(string_sub(hex, 7, 8), 16) / 255 or 1 }
    rest = string_sub(s, #hex + 2)
  else
    local name = string_match(s, "^([%a_][%w_]*)")
    if not name then return nil end
    rest = string_sub(s, #name + 1)
    if name == "none" then
      node = { kind = K_LIT, r = 0, g = 0, b = 0, a = 0 }
    elseif name == "xp" then
      node = { kind = K_XP, uXp = true }
    elseif name == "rested" then
      node = { kind = K_RESTED, uRested = true }
    elseif name == "base" then
      if not allowBase then return nil end
      node = { kind = K_BASE, uBase = true }
    else
      node = { kind = K_NAME, ref = name }
    end
  end
  local pos, n = 1, #rest
  while pos <= n do
    local op, num, nextPos = string_match(rest, "^([%+%-@])([%d%.]+)()", pos)
    local x = num and tonumber(num)
    if not op or not x or x < 0 or x > 1 then return nil end
    if op == "@" then
      if nextPos <= n then return nil end
      node.alpha = x
    else
      node[#node + 1] = (op == "+") and 1 or -1
      node[#node + 1] = x
    end
    pos = nextPos
  end
  return node
end

local function ParseNumeric(v)
  local n = #v
  local ok = (n == 3 or n == 4)
  for i = 1, n do
    local x = v[i]
    if not IsNum(x) or x < 0 or x > 1 then ok = false end
  end
  for k in pairs(v) do
    if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then ok = false end
  end
  if not ok then return nil end
  return { kind = K_LIT, r = v[1], g = v[2], b = v[3], a = v[4] or 1 }
end

-- Links names and propagates the dynamic flags (cycles and depth > 4 are refused: bad).
-- The visit state of the nodes lives in the compile (ctx.vs, ctx.vd), not in the nodes.
local Visit
Visit = function(ctx, node)
  local state = ctx.vs[node]
  if state == 2 then return ctx.vd[node] end
  if state == 1 then
    node.bad = true
    return 0
  end
  ctx.vs[node] = 1
  local depth = 0
  local kind = node.kind
  local targets
  if kind == K_NAME then
    local ref = ctx.colorNodes[node.ref]
    if not ref then
      node.bad, node.ref = true, nil
    else
      node.ref = ref
      depth = 1 + Visit(ctx, ref)
      if depth > 4 then node.bad = true end
      targets = ref
    end
  elseif kind == K_XP then
    targets = ctx.colorNodes.xp
  elseif kind == K_RESTED then
    targets = ctx.colorNodes.rested
  elseif kind == K_BASE then
    local x, r = ctx.colorNodes.xp, ctx.colorNodes.rested
    if x then Visit(ctx, x); node.uXp = node.uXp or x.uXp; node.uRested = node.uRested or x.uRested end
    if r then Visit(ctx, r); node.uXp = node.uXp or r.uXp; node.uRested = node.uRested or r.uRested end
  end
  if targets and kind ~= K_NAME then Visit(ctx, targets) end
  if targets then
    if targets.bad and kind ~= K_NAME then node.bad = true end
    node.uXp = node.uXp or targets.uXp
    node.uRested = node.uRested or targets.uRested
    node.uBase = node.uBase or targets.uBase
  end
  ctx.vs[node], ctx.vd[node] = 2, depth
  return depth
end

-- An expression of a section: one node per text within a compile (they evaluate alike;
-- the entries of `colors` keep their own nodes, linked together first).
local function SectionExpr(ctx, s, allowBase)
  local key = (allowBase and "+" or "-") .. s
  local node = ctx.exprs[key]
  if node == nil then
    node = ParseExpr(s, allowBase) or false
    ctx.exprs[key] = node
  end
  return node or nil
end

-- A colour value (string, numeric table or { expr, def = ... }) -> node, defNode.
-- Nodes are linked at once unless `defer` (the entries of `colors`, linked together).
local function ParseColor(ctx, v, allowBase, defer)
  local node, def
  local tv = type(v)
  if tv == "string" then
    if defer then node = ParseExpr(v, allowBase) else node = SectionExpr(ctx, v, allowBase) end
  elseif tv == "table" and type(v[1]) == "number" then
    node = ParseNumeric(v)
  elseif tv == "table" and type(v[1]) == "string" then
    if defer then node = ParseExpr(v[1], allowBase) else node = SectionExpr(ctx, v[1], allowBase) end
    if v.def ~= nil and not (type(v.def) == "table" and type(v.def[1]) == "string") then
      def = ParseColor(ctx, v.def, allowBase, defer)
    end
  end
  if not defer then
    if node then Visit(ctx, node) end
    if def then Visit(ctx, def) end
  end
  return node or WHITE_NODE, def
end

local function IsStatic(node)
  return not (node.uXp or node.uRested or node.uBase)
end

-- The 4 numbers of a colour as a key (exact: "%.17g" tells every double apart, -0 too).
local function ColorKey(r, g, b, a)
  return string_format("%.17g,%.17g,%.17g,%.17g", r, g, b, a)
end
local WHITE_KEY = ColorKey(1, 1, 1, 1)
local SHADOW_KEY = ColorKey(0, 0, 0, 0.8)                -- the default text shadow colour

-- A small list of numbers or strings (band, pad, inset, slice, rotated coordinates, font
-- slot): one table per value within a compile (compiled tables are never written).
local function Shared(ctx, t)
  local key = ""
  for i = 1, #t do
    local v = t[i]
    key = key .. (type(v) == "number" and string_format("%.17g", v) or tostring(v)) .. ","
  end
  local s = ctx.lists[key]
  if s then return s end
  ctx.lists[key] = t
  return t
end

-- A compiled colour. A static one (nothing it reads can change) is evaluated now and is
-- one array per value within the compile; a dynamic one gets its own array, written by
-- RunProgram at the end of the compile and by every recolour (so a shared array never
-- changes under another use).
local function Slot(ctx, node, def, k, f)
  node, k, f = node or WHITE_NODE, k or 0, f or 1
  if IsStatic(node) and (not def or IsStatic(def)) then
    local r, g, b, a
    if def then r, g, b, a = Eval(def, k) else r, g, b, a = Eval(node, k) end
    a = a * f
    local key = ColorKey(r, g, b, a)
    local c = ctx.interned[key]
    if not c then
      c = { r, g, b, a }
      ctx.interned[key] = c
    end
    return c
  end
  local out = { 0, 0, 0, 0 }
  local p = ctx.prog
  local n = #p
  p[n + 1], p[n + 2], p[n + 3], p[n + 4], p[n + 5] = out, node, def or false, k, f
  return out
end

-- A colour that never depends on the fill state (also returns its node and def).
local function Single(ctx, v, default)
  if v == nil then v = default end
  local node, def = ParseColor(ctx, v, false)
  return Slot(ctx, node, def, 0, 1), node, def
end

---------------------------------------------------------------------------
-- Media references and texture specs (6.1, 6.3)
---------------------------------------------------------------------------
-- file -> path, texture width, height (nil: the white file, also for a file that is not
-- a declared media). One path string per file within a compile.
local function MediaRef(ctx, file)
  if type(file) ~= "string" then return nil end
  local dir, name = string_match(file, "^(common)/(.+)$")
  local decl
  if dir then
    decl = COMMON_MEDIA[name]
  else
    dir, name = ctx.key, file
    decl = ctx.media[name]
  end
  if type(decl) ~= "table" then return nil end
  local path = ctx.paths[file]
  if not path then
    path = MEDIA_ROOT .. "Themes\\" .. dir .. "\\" .. name .. ".tga"
    ctx.paths[file] = path
  end
  return path, decl[1], decl[2]
end

local ROTS = { [0] = true, [90] = true, [180] = true, [270] = true }
local TILES = { H = true, V = true, HV = true }
local BLENDS = { BLEND = true, ADD = true }

local function Numbers(t)
  if not t then return "" end
  local s = ""
  for i = 1, #t do s = s .. string_format("%.17g", t[i]) .. " " end
  return s
end

-- texSpec = { path, w, h, blend, l, r, t, b (the rect, unflipped), flipX, flipY,
--             tc8 = nil | { 8 numbers } (rot), tile = nil | "H" | "V" | "HV",
--             slice = nil | { texels, px } }, defaults in MT.spec; nil = the white file
-- with every default. SetTex sets the coordinates of the rect (flipped) of a spec that
-- is neither tiled nor sliced. Equal specs are one table within a compile.
local function TexSpec(ctx, src, file, slice)
  local path, tw, th = MediaRef(ctx, file)
  if not path then path, tw, th = WHITE, 8, 8 end
  local blend = Choice(src.blend, "BLEND", BLENDS)
  local l, r, t, b = 0, 1, 0, 1
  local rect = src.rect
  if rect ~= nil then
    local x, y, w, h = type(rect) == "table" and rect[1], type(rect) == "table" and rect[2],
      type(rect) == "table" and rect[3], type(rect) == "table" and rect[4]
    if IsNum(x) and IsNum(y) and IsNum(w) and IsNum(h) and x >= 0 and y >= 0 and w > 0 and h > 0
        and x + w <= tw and y + h <= th then
      l, r, t, b = x / tw, (x + w) / tw, y / th, (y + h) / th
    end
  end
  local fx, fy = src.flipX == true, src.flipY == true
  local rot = Choice(src.rot, 0, ROTS)
  local tile = Choice(src.tile, nil, TILES)
  local tc8
  if slice then
    tile = nil
  elseif not tile and rot ~= 0 then
    local L0, R0, T0, B0 = l, r, t, b
    if fx then L0, R0 = R0, L0 end
    if fy then T0, B0 = B0, T0 end
    if rot == 90 then
      tc8 = { L0, B0, R0, B0, L0, T0, R0, T0 }
    elseif rot == 180 then
      tc8 = { R0, B0, R0, T0, L0, B0, L0, T0 }
    else
      tc8 = { R0, T0, L0, T0, R0, B0, L0, B0 }
    end
  end
  local key = path .. "|" .. tw .. "|" .. th .. "|" .. blend .. "|" .. Numbers({ l, r, t, b }) .. "|"
    .. tostring(fx) .. tostring(fy) .. "|" .. tostring(tile) .. "|" .. Numbers(tc8) .. "|" .. Numbers(slice)
  local spec = ctx.specs[key]
  if spec ~= nil then return spec or nil end
  if path == WHITE and blend == "BLEND" and l == 0 and r == 1 and t == 0 and b == 1 and not (fx or fy or tile
      or tc8 or slice) then
    ctx.specs[key] = false
    return nil
  end
  spec = setmetatable({}, MT.spec)
  if path ~= WHITE then spec.path = path end
  if tw ~= 8 then spec.w = tw end
  if th ~= 8 then spec.h = th end
  if blend ~= "BLEND" then spec.blend = blend end
  if l ~= 0 then spec.l = l end
  if r ~= 1 then spec.r = r end
  if t ~= 0 then spec.t = t end
  if b ~= 1 then spec.b = b end
  if fx then spec.flipX = true end
  if fy then spec.flipY = true end
  spec.tile = tile
  if tc8 then spec.tc8 = Shared(ctx, tc8) end
  if slice then spec.slice = Shared(ctx, slice) end
  ctx.specs[key] = spec
  return spec
end

---------------------------------------------------------------------------
-- Colours of an item (layer, part, separator, leader)
---------------------------------------------------------------------------
local DIRS = { HORIZONTAL = true, VERTICAL = true }
local FILL_SPAN = { fill = true, fillEnd = true }

local function Dyn(node, def)
  return (node and node.uBase) or (def and def.uBase) or false
end

-- One colour of an item: its state-0 colour, or a per-state list { state 0, state 1
-- [, state 2] } (see Paint).
local function Entry(ctx, node, def, list, dyn, alpha, maxA)
  local c1 = Slot(ctx, node, def, 0, alpha)
  if not list then return c1 end
  local c2 = dyn and Slot(ctx, node, def, 1, alpha) or c1
  if maxA ~= 1 and alpha ~= 1 then return { c1, c2, Slot(ctx, node, def, 2, alpha * maxA) } end
  return { c1, c2 }
end

-- A gradient pair { from, to, dir = }: one table per (from, to, dir) within a compile.
local function Pair(ctx, from, to, dir)
  local byFrom = ctx.pairs[from]
  if not byFrom then
    byFrom = {}
    ctx.pairs[from] = byFrom
  end
  local key = dir .. "\0"
  local byTo = byFrom[to]
  if not byTo then
    byTo = {}
    byFrom[to] = byTo
  end
  local p = byTo[key]
  if not p then
    p = { from, to, dir = dir }
    byTo[key] = p
  end
  return p
end

-- Fills item.c, or item.g (and item.f when the source has a flat colour), plus item.dyn
-- and item.m, from color / grad / flat of src; alpha is folded into the colours. A bar
-- layer follows the fill state (BarSkin) when it uses `base` (dyn) or has a fill span:
-- state 1 differs from state 0 only for `base`, and state 2 is state 0 with its alpha
-- times maxA. Per-state lists are made only when needed: for `base` (states 0 and 1),
-- and for a state 2 of its own when the layer has an alpha of its own besides maxA
-- (alpha * maxA folded at compile time). Otherwise the reader scales the alpha of state 0
-- by m (the same product as the compile, alpha being 1): bar.maxAlpha for a fill span,
-- else 1, or item.m when the layer's maxAlpha differs.
local function Paint(ctx, item, src, allowBase, alpha, maxA, span, barMaxA)
  local cN, cD = ParseColor(ctx, src.color or "#ffffff", allowBase)
  local dir, fromN, fromD, toN, toD
  local grad = src.grad
  if grad ~= nil and type(grad) == "table" and DIRS[grad[1]] then
    dir = grad[1]
    fromN, fromD = ParseColor(ctx, grad[2], allowBase)
    toN, toD = ParseColor(ctx, grad[3], allowBase)
  end
  local fN, fD
  if src.flat ~= nil then
    fN, fD = ParseColor(ctx, src.flat, allowBase)
  elseif dir then
    fN, fD = fromN, fromD
  end
  local dyn = Dyn(cN, cD)
  if dir then dyn = dyn or Dyn(fromN, fromD) or Dyn(toN, toD) or Dyn(fN, fD) end
  if dyn then item.dyn = true end
  local stateful = dyn or (span ~= nil and FILL_SPAN[span])
  local list = stateful and (dyn or (maxA ~= 1 and alpha ~= 1)) or false
  if stateful and not (maxA ~= 1 and alpha ~= 1) then
    local m = (alpha == 1) and maxA or 1
    if m ~= (FILL_SPAN[span] and barMaxA or 1) then item.m = m end
  end
  if dir then
    local from = Entry(ctx, fromN, fromD, list, dyn, alpha, maxA)
    local to = Entry(ctx, toN, toD, list, dyn, alpha, maxA)
    if list then
      local p1 = Pair(ctx, from[1], to[1], dir)
      local g = { p1, Pair(ctx, from[2], to[2], dir) }
      if from[3] then g[3] = Pair(ctx, from[3], to[3], dir) end
      item.g = g
    else
      item.g = Pair(ctx, from, to, dir)
    end
    if src.flat ~= nil then item.f = Entry(ctx, fN, fD, list, dyn, alpha, maxA) end
  else
    local c = Entry(ctx, cN, cD, list, dyn, alpha, maxA)
    if c ~= ctx.interned[WHITE_KEY] then item.c = c end    -- (white: the default)
  end
end

---------------------------------------------------------------------------
-- bar section (2.4)
---------------------------------------------------------------------------
local SPAN_KIND = { track = "range", fill = "range", rested = "range",
                    fillEnd = "anchor", restEnd = "anchor", trackStart = "anchor", trackEnd = "anchor" }
local DRAW_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true }
local ALIGNS = { center = true, left = true, right = true }
local CLIPS = { fill = true }
local POINTS = Set({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM",
  "BOTTOMRIGHT" })
local NO_SOURCE = {}

-- { file, texels, px } of three / nine -> file, slice
local function SliceSrc(v)
  if type(v) ~= "table" or type(v[1]) ~= "string" or not IsNum(v[2]) or v[2] <= 0
      or not IsNum(v[3]) or v[3] <= 0 then
    return nil, nil
  end
  return v[1], { v[2], v[3] }
end

local function CompileLayer(ctx, src, i, barMaxAlpha)
  if type(src) ~= "table" then return nil end
  local id = src.id
  if type(id) ~= "string" or id == "" then id = "layer" .. i end
  local Lc = setmetatable({ id = id }, MT.layer)
  local kind = "tex"
  if src.caps ~= nil and src.caps ~= false then kind = "caps" end
  if src.three ~= nil then kind = "three" end
  if src.nine ~= nil then kind = "nine" end
  if src.ticks ~= nil then kind = "ticks" end
  if kind ~= "tex" then Lc.kind = kind end
  local span = Choice(src.span, "track", SPAN_KIND)
  local isRange = SPAN_KIND[span] == "range"
  if span ~= "track" then Lc.span = span end
  local layer = Choice(src.layer, "ARTWORK", DRAW_LAYERS)
  if layer ~= "ARTWORK" then Lc.layer = layer end
  local sub = Num(src.sub, 0, -8, 7, true)
  if sub ~= 0 then Lc.sub = sub end

  -- texture
  if kind == "three" or kind == "nine" then
    local file, slice = SliceSrc(src[kind])
    Lc.tex = TexSpec(ctx, src, file, slice or { 1, 1 })
  else
    Lc.tex = TexSpec(ctx, src, src.file)
  end

  -- vertical extent
  local top, bottom = Num(src.top, 0), Num(src.bottom, 0)
  if top ~= 0 then Lc.top = top end
  if bottom ~= 0 then Lc.bottom = bottom end
  Lc.h = Num(src.h, nil, 0)
  local band = src.band
  if type(band) == "table" and IsNum(band[1]) and IsNum(band[2]) and band[1] >= 0 and band[2] <= 1
      and band[1] < band[2] and #band == 2 then
    Lc.band = Shared(ctx, { band[1], band[2] })
  end

  -- horizontal extent
  local pad = src.pad
  if type(pad) == "table" and IsNum(pad[1]) and IsNum(pad[2]) and (pad[1] ~= 0 or pad[2] ~= 0) then
    Lc.pad = Shared(ctx, { pad[1], pad[2] })
  end
  if src.capInset == true then Lc.capInset = true end
  if not isRange and kind ~= "ticks" then Lc.w = Num(src.w, nil, 1) or 1 end
  local align, dx = Choice(src.align, "center", ALIGNS), Num(src.dx, 0)
  if align ~= "center" then Lc.align = align end
  if dx ~= 0 then Lc.dx = dx end

  if kind == "ticks" then
    local t = src.ticks
    if type(t) ~= "table" then t = NO_SOURCE end
    local tk = setmetatable({ n = Num(t.n, 2, 2, 100, true) }, MT.ticks)
    local w = Num(t.w, 1, 1, 16, true)
    if w ~= 1 then tk.w = w end
    tk.clip = Choice(t.clip, nil, CLIPS)
    if t.mid == true then tk.mid = true end   -- N ticks at the middles of the N parts
    Lc.ticks = tk
  end

  -- colours: alpha factors folded in
  local alpha = Num(src.alpha, 1, 0, 1)
  local maxA = Num(src.maxAlpha, FILL_SPAN[span] and barMaxAlpha or 1, 0, 1)
  Paint(ctx, Lc, src, true, alpha, maxA, span, barMaxAlpha)
  return Lc
end

-- Panel parts (2.4.2): bar panel (alpha "bg" / "line" / number) and tooltip panel
-- (numbers only). A numeric alpha is folded into the colours (alpha is then 1). `sub` is
-- stored when it differs from -8 + n - 1 (n = the part's position in the compiled list,
-- the readers' default).
local function CompilePart(ctx, src, i, n, isTooltip)
  if type(src) ~= "table" then return nil end
  local id = src.id
  if type(id) ~= "string" or id == "" then id = "part" .. i end
  local P = setmetatable({ id = id }, MT.part)
  if src.nine ~= nil then
    local file, slice = SliceSrc(src.nine)
    P.kind = "nine"
    P.tex = TexSpec(ctx, src, file, slice or { 1, 1 })
  else
    P.tex = TexSpec(ctx, src, src.file)
  end
  local layer = Choice(src.layer, "BACKGROUND", DRAW_LAYERS)
  if layer ~= "BACKGROUND" then P.layer = layer end
  local defSub = -8 + i - 1
  if defSub > 7 then defSub = 7 end
  local sub = Num(src.sub, defSub, -8, 7, true)
  if sub ~= -8 + n - 1 then P.sub = sub end
  local anchor = src.anchor or "FILL"
  if anchor ~= "FILL" and not POINTS[anchor] then anchor = "FILL" end
  if anchor == "FILL" then
    local ins = src.inset
    if type(ins) == "table" and IsNum(ins[1]) and IsNum(ins[2]) and IsNum(ins[3]) and IsNum(ins[4])
        and (ins[1] ~= 0 or ins[2] ~= 0 or ins[3] ~= 0 or ins[4] ~= 0) then
      P.inset = Shared(ctx, { ins[1], ins[2], ins[3], ins[4] })
    end
  else
    P.anchor = anchor
    local x, y = Num(src.x, 0), Num(src.y, 0)
    if x ~= 0 then P.x = x end
    if y ~= 0 then P.y = y end
    P.w, P.h = Num(src.w, nil, 1) or 1, Num(src.h, nil, 1) or 1
  end
  local alpha, factor = src.alpha, 1
  if alpha == nil then
    alpha = 1
  elseif (alpha == "bg" or alpha == "line") and not isTooltip then
    factor = 1
  elseif IsNum(alpha) and alpha >= 0 and alpha <= 1 then
    factor, alpha = alpha, 1
  else
    alpha = 1
  end
  if alpha ~= 1 then P.alpha = alpha end
  Paint(ctx, P, src, false, factor, 1, nil)
  return P
end

local function CompileParts(ctx, parts, isTooltip)
  local out = {}
  if type(parts) ~= "table" then return out end
  for i = 1, #parts do
    local P = CompilePart(ctx, parts[i], i, #out + 1, isTooltip)
    if P then out[#out + 1] = P end
  end
  return out
end

local function CompileBar(ctx, bar)
  if type(bar) ~= "table" then bar = NO_SOURCE end
  local out = setmetatable({}, MT.bar)
  local pad, gap = Num(bar.pad, 8, 0, 64, true), Num(bar.gap, 3, 0, 32, true)
  if pad ~= 8 then out.pad = pad end
  if gap ~= 3 then out.gap = gap end
  local h = bar.height
  if type(h) == "table" then
    local add, min = Num(h.add, 0, -16, 32, true), Num(h.min, 4, 1, 64, true)
    if add ~= 0 then out.hAdd = add end
    if min ~= 4 then out.hMin = min end
  end
  local maxA = Num(bar.maxAlpha, 0.35, 0, 1)
  if maxA ~= 0.35 then out.maxAlpha = maxA end
  local layers = {}
  if type(bar.layers) == "table" then
    for i = 1, #bar.layers do
      local Lc = CompileLayer(ctx, bar.layers[i], i, maxA)
      if Lc then layers[#layers + 1] = Lc end
    end
  end
  out.layers = layers
  local panel = bar.panel
  if type(panel) == "table" and type(panel.parts) == "table" then
    out.panel = { parts = CompileParts(ctx, panel.parts, false) }
  end
  return out
end

---------------------------------------------------------------------------
-- text section (2.5)
---------------------------------------------------------------------------
local TEXT_ROLES = { "label", "value", "levelLabel", "levelValue", "xpText", "sep", "marker", "hint",
                     "slot2", "slot3", "dimmed" }
local TEXT_ROLE_DEF = { label = "label", value = "value", levelLabel = "label", levelValue = "value",
                        xpText = "label", sep = "label", marker = "label", hint = "label", slot2 = "value",
                        slot3 = "label", dimmed = "dim" }
local FONT_ROLES = { display = true, body = true, num = true, game = true }
-- Elements that render arbitrary strings: never the display role (SPEC 8.3; `hint` shows a
-- free locale sentence, so it is included too).
local NO_DISPLAY = { s1 = true, s2 = true, s3 = true, xp = true, sep = true, levelValue = true, hint = true }
local TEXT_VALID = Set(TEXT_ELEMS)
local LEVEL_FMTS = { upper = true, title = true }

local function IsRole(_, v) return FONT_ROLES[v] == true end
local function IsDelta(_, v) return IsNum(v) and v % 1 == 0 and v >= -8 and v <= 16 end

-- An element map: the valid entries that differ from the default (mt), nil when none.
local function ElemMap(src, mt, valid, check)
  if type(src) ~= "table" then return nil end
  local out, any = setmetatable({}, mt), false
  local def = mt.__index
  for k, v in pairs(src) do
    if valid[k] and check(k, v) and v ~= def[k] then
      out[k] = v
      any = true
    end
  end
  return any and out or nil
end

local function CompileText(ctx, text)
  if type(text) ~= "table" then text = NO_SOURCE end
  local out = setmetatable({}, MT.text)
  local font = ElemMap(text.font, MT.font, TEXT_VALID, IsRole)
  if font then
    for e in pairs(NO_DISPLAY) do
      if font[e] == "display" then font[e] = nil end      -- the default, body
    end
    if next(font) ~= nil then out.font = font end
  end
  out.size = ElemMap(text.size, MT.size, TEXT_VALID, IsDelta)
  if text.split == true then out.split = true end
  local splitGap, levelFmt = Num(text.splitGap, 4, 0, 32, true), Choice(text.levelFmt, "upper", LEVEL_FMTS)
  if splitGap ~= 4 then out.splitGap = splitGap end
  if levelFmt ~= "upper" then out.levelFmt = levelFmt end

  local roles = type(text.colors) == "table" and text.colors or NO_SOURCE
  local colors = {}
  for i = 1, #TEXT_ROLES do
    local role = TEXT_ROLES[i]
    colors[role] = Single(ctx, roles[role], TEXT_ROLE_DEF[role])
  end
  out.colors = colors

  local sh = type(text.shadow) == "table" and text.shadow or NO_SOURCE
  local c = Single(ctx, sh.color, { 0, 0, 0, 0.8 })
  local x, y = Num(sh.x, 1, -8, 8), Num(sh.y, -1, -8, 8)
  if c ~= ctx.interned[SHADOW_KEY] or x ~= 1 or y ~= -1 then
    local shadow = setmetatable({ c = c }, MT.shadow)
    if x ~= 1 then shadow.x = x end
    if y ~= -1 then shadow.y = y end
    out.shadow = shadow
  end
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
local TT_FONTS = { "title", "body", "value", "note", "hint" }
local GAUGE_KEYS = { "world", "dungeon", "raid", "pvp", "taxi", "prof", "dead", "afk", "inn", "city" }

local function CompileSep(ctx, s)
  if type(s) ~= "table" then return nil end
  local out = setmetatable({}, MT.sep)
  local h, above, below = Num(s.h, 1, 1, 32, true), Num(s.above, 6, 0, 64, true), Num(s.below, 5, 0, 64, true)
  if h ~= 1 then out.h = h end
  if above ~= 6 then out.above = above end
  if below ~= 5 then out.below = below end
  if s.mirror == true then out.mirror = true end
  out.tex = TexSpec(ctx, s, s.file)
  Paint(ctx, out, s, false, 1, 1, nil)
  -- center: the middle `center` texels (an ornament) keep the art's proportions, the two
  -- sides (lines) stretch to the tooltip width
  local c = s.center
  if c ~= nil then
    local spec = out.tex
    local artW = (spec.r - spec.l) * spec.w      -- (rect: the art is the rectangle)
    if artW < 0 then artW = -artW end
    if s.file ~= nil and IsNum(c) and c % 1 == 0 and c >= 2 and c <= artW - 2
        and not (out.mirror or spec.tile or s.grad ~= nil) then
      out.center = c
    end
  end
  return out
end

local function CompileTooltip(ctx, tt)
  if type(tt) ~= "table" or tt.native == true then
    return { native = true, colors = Themes.CLASSIC_TT }   -- every other field ignored
  end
  local out = setmetatable({}, MT.tt)
  local w = tt.width
  if type(w) == "table" and IsNum(w[1]) and IsNum(w[2]) and w[1] > 0 and w[2] >= w[1]
      and (w[1] ~= 280 or w[2] ~= 440) then
    out.width = { w[1], w[2] }
  end
  local p = tt.pad
  if type(p) == "table" and IsNum(p[1]) and IsNum(p[2]) and IsNum(p[3]) and IsNum(p[4])
      and (p[1] ~= 12 or p[2] ~= 12 or p[3] ~= 10 or p[4] ~= 10) then
    out.pad = { p[1], p[2], p[3], p[4] }
  end
  local gap, lineGap = Num(tt.gap, 8, 0, 64), Num(tt.lineGap, 3, 0, 32)
  if gap ~= 8 then out.gap = gap end
  if lineGap ~= 3 then out.lineGap = lineGap end

  -- fonts: { role, size }; value is left out when it equals body (the readers' default)
  local fonts = {}
  local src = type(tt.fonts) == "table" and tt.fonts or NO_SOURCE
  for i = 1, #TT_FONTS do
    local name = TT_FONTS[i]
    local f = src[name]
    if f == nil and name == "value" then f = src.body end
    local role, size = "body", 12
    if type(f) == "table" and FONT_ROLES[f[1]] and IsNum(f[2]) and f[2] >= 6 and f[2] <= 40 then
      role, size = f[1], f[2]
    end
    if role == "display" and name ~= "title" then role = "body" end
    fonts[name] = Shared(ctx, { role, size })
  end
  if fonts.value == fonts.body then fonts.value = nil end
  out.fonts = fonts

  local roles = type(tt.colors) == "table" and tt.colors or NO_SOURCE
  local colors = {}
  local dimNode, dimDef
  for i = 1, #TT_ROLES do
    local role = TT_ROLES[i]
    local c, node, def = Single(ctx, roles[role], TT_ROLE_DEF[role])
    colors[role] = c
    if role == "dim" then dimNode, dimDef = node, def end
  end
  out.colors = colors
  -- ccDim follows the dim whenever the program rewrites it (Slot: a dynamic node or def)
  if dimNode and (not IsStatic(dimNode) or (dimDef and not IsStatic(dimDef))) then ctx.prog.dimOf = colors end

  local panel = tt.panel
  if type(panel) == "table" and type(panel.parts) == "table" then
    local parts = CompileParts(ctx, panel.parts, true)
    if #parts > 0 then out.panel = { parts = parts } end
  end

  local icon = tt.titleIcon
  if type(icon) == "table" and type(icon[1]) == "string" and IsNum(icon[2]) and IsNum(icon[3]) then
    local ic = setmetatable({ tex = TexSpec(ctx, NO_SOURCE, icon[1]), w = icon[2], h = icon[3] }, MT.icon)
    local igap = Num(icon.gap, 6, 0, 32)
    if igap ~= 6 then ic.gap = igap end
    out.titleIcon = ic
  end

  local sep = tt.sep
  if type(sep) == "table" then
    local s = { header = CompileSep(ctx, sep.header), block = CompileSep(ctx, sep.block),
                footer = CompileSep(ctx, sep.footer) }
    if next(s) ~= nil then out.sep = s end
  end

  local ld = tt.leader
  if type(ld) == "table" then
    local leader = setmetatable({}, MT.leader)
    local lh, ly, lmin = Num(ld.h, 1, 1, 16, true), Num(ld.y, 3, -16, 32), Num(ld.min, 12, 0, 200)
    if lh ~= 1 then leader.h = lh end
    if ly ~= 3 then leader.y = ly end
    if lmin ~= 12 then leader.min = lmin end
    leader.tex = TexSpec(ctx, { tile = ld.tile or "H", rect = ld.rect, blend = ld.blend }, ld.file)
    Paint(ctx, leader, ld, false, 1, 1, nil)
    out.leader = leader
  end

  local gg = tt.gauge
  if type(gg) == "table" then
    local gauge = setmetatable({}, MT.gauge)
    local gw, gh, ggap = Num(gg.w, 176, 16, 512, true), Num(gg.h, 6, 1, 32, true), Num(gg.gap, 2, 0, 16, true)
    if gw ~= 176 then gauge.w = gw end
    if gh ~= 6 then gauge.h = gh end
    if ggap ~= 2 then gauge.gap = ggap end
    if gg.outline ~= nil then gauge.outline = Single(ctx, gg.outline) end
    local gc = type(gg.colors) == "table" and gg.colors or NO_SOURCE
    local colors2 = {}
    for i = 1, #GAUGE_KEYS do
      local k = GAUGE_KEYS[i]
      colors2[k] = Single(ctx, gc[k], "dim")
    end
    gauge.colors = colors2
    out.gauge = gauge
  end
  return out
end

---------------------------------------------------------------------------
-- Compile (2.8)
---------------------------------------------------------------------------
local UI_ROLES = { "bg", "border", "title", "accent", "label", "value", "dim" }
local RESERVED_NAMES = { base = true, none = true }
local registry = {}                         -- key -> compact source text, or builder function
local programs = setmetatable({}, WEAK_K)   -- compiled theme -> its colour program
local genCounter = 0

local function CompileFonts(fonts)
  local out = setmetatable({}, MT.fonts)
  if type(fonts) ~= "table" then fonts = NO_SOURCE end
  for _, role in ipairs({ "display", "body", "num" }) do
    local name = fonts[role]
    if name == nil and role == "num" then
      name = rawget(out, "body")
    elseif name ~= "game" and not FONTS[name] then
      name = "game"
    end
    if role ~= "display" and name ~= nil and FONTS[name] and FONTS[name].display then name = "game" end
    out[role] = name
  end
  if rawget(out, "num") == rawget(out, "body") then out.num = nil end   -- the default
  return out
end

local function CompileMedia(media)
  local out = {}
  if type(media) ~= "table" then return out end
  for name, d in pairs(media) do
    if type(name) == "string" and string_find(name, "^[a-z0-9_]+$") and type(d) == "table"
        and IsPow2(d[1]) and IsPow2(d[2]) then
      out[name] = d
    end
  end
  return out
end

-- The named colours: parsed, then linked together (any order).
local function CompileColors(ctx, colors)
  local nodes, defs = {}, {}
  ctx.colorNodes = nodes
  if type(colors) ~= "table" then colors = NO_SOURCE end
  for name, v in pairs(colors) do
    if type(name) == "string" and string_find(name, "^[%a_][%w_]*$") and not RESERVED_NAMES[name] then
      nodes[name], defs[name] = ParseColor(ctx, v, false, true)
    end
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
    Visit(ctx, node)
    if defs[name] then Visit(ctx, defs[name]) end
  end
  ctx.colorDefs = defs
  ctx.prog.xp, ctx.prog.rested = nodes.xp, nodes.rested
end

-- th.colors: the theme's own colours, before any user override (static colours): those
-- the addon reads (xp, rested: Themes.DefaultColor; bg, border: the classic backdrop)
-- and the required ones (label, value, dim, accent, pause). Other names stay in the
-- source.
local PALETTE = { "xp", "rested", "label", "value", "dim", "accent", "pause", "bg", "border" }

local function Palette(ctx)
  local saveX, saveR = E.xpOn, E.rsOn
  E.xpOn, E.rsOn = false, false
  E.prog = ctx.prog
  local out = {}
  for i = 1, #PALETTE do
    local name = PALETTE[i]
    local node = ctx.colorNodes[name]
    if node then
      local def = ctx.colorDefs[name]
      local r, g, b, a
      if def then r, g, b, a = Eval(def, 0) else r, g, b, a = Eval(node, 0) end
      local key = ColorKey(r, g, b, a)
      local c = ctx.interned[key]
      if not c then
        c = { r, g, b, a }
        ctx.interned[key] = c
      end
      out[name] = c
    end
  end
  E.prog = nil
  E.xpOn, E.rsOn = saveX, saveR
  return out
end

local function CompileUI(ctx, ui)
  local out = {}
  if type(ui) ~= "table" then ui = NO_SOURCE end
  for i = 1, #UI_ROLES do
    local role = UI_ROLES[i]
    -- (the graph and the window are restyled at a theme switch only, never on a recolour)
    out[role] = Single(ctx, ui[role], role == "bg" and "#000000" or "label")
  end
  return out
end

local function CompileBody(ctx, src)
  local th = { key = ctx.key, gen = 0 }
  ctx.media = CompileMedia(src.media)
  th.fonts = CompileFonts(src.fonts)
  CompileColors(ctx, src.colors)
  th.accent = Slot(ctx, ctx.colorNodes.accent or WHITE_NODE, ctx.colorDefs.accent, 0, 1)
  th.bar = CompileBar(ctx, src.bar)
  th.text = CompileText(ctx, src.text)
  th.tt = CompileTooltip(ctx, src.tooltip)
  if th.tt.native then th.native = true end
  th.ui = CompileUI(ctx, src.ui)
  RunProgram(ctx.prog)
  if not th.native then th.tt.colors.ccDim = ColorCode(th.tt.colors.dim) end   -- (dynamic: every run)
  th.colors = Palette(ctx)
  return th
end

---------------------------------------------------------------------------
-- Theme sources (M3): each Themes/<key>.lua registers its source text, "return { ... }"
-- (plain data, no comment), kept compact; it is compiled into a function, in an empty
-- environment, each time the theme is compiled, and the function is dropped at once.
-- Builder functions are accepted too (tests).
---------------------------------------------------------------------------
-- Indentation, line ends and the blanks around = , { } removed outside string literals.
local function CompactCode(code)
  code = string_gsub(code, "\n[ \t]+", "\n")
  return (string_gsub(code, "%s*([=,{}])%s*", "%1"))
end

local function Compact(text)
  local out, n, i, len = {}, 0, 1, #text
  while i <= len do
    local q = string_find(text, "[\"']", i)
    n = n + 1
    out[n] = CompactCode(string_sub(text, i, (q or len + 1) - 1))
    if not q then break end
    local quote, j = string_sub(text, q, q), q + 1
    while j <= len do
      local ch = string_sub(text, j, j)
      if ch == "\\" then
        j = j + 2
      elseif ch == quote then
        break
      else
        j = j + 1
      end
    end
    n = n + 1
    out[n] = string_sub(text, q, j)
    i = j + 1
  end
  return table_concat(out)
end
Themes.CompactSource = Compact

-- The function of a source text, in an empty environment (Lua 5.1, the game: loadstring
-- and setfenv; 5.2+: load with an environment).
local function LoadSource(text, key)
  local name = "=Themes/" .. tostring(key)
  if setfenv then
    local fn, err = loadstring(text, name)
    if fn then setfenv(fn, {}) end
    return fn, err
  end
  return load(text, name, "t", {})
end

-- The source table of a registered theme, built afresh. Returns true and the value the
-- source (or the builder) returned, false and the error, or nil (not registered).
function Themes.Source(key)
  local entry = registry[key]
  if entry == nil then return nil end
  local fn = entry
  if type(entry) == "string" then
    local err
    fn, err = LoadSource(entry, key)
    if not fn then return false, err end
  end
  return pcall(fn)
end

-- Pure: compiles a registered theme with the current user colours; the active theme is
-- left alone. Returns th, or nil and the reason when the theme cannot be built.
local function Compile(key)
  local ok, src = Themes.Source(key)
  if ok == nil then return nil, tostring(key) .. ": not a registered theme" end
  if not ok or type(src) ~= "table" then return nil, tostring(key) .. ": builder failed: " .. tostring(src) end
  local ctx = { key = key, prog = { u = {} }, media = {}, colorNodes = {}, colorDefs = {}, vs = {}, vd = {},
                interned = {}, specs = {}, paths = {}, lists = {}, pairs = {}, exprs = {} }
  local saveProg = E.prog
  ReadUserColors()
  local okC, th = pcall(CompileBody, ctx, src)
  E.prog = saveProg
  if not okC then return nil, tostring(key) .. ": compile error: " .. tostring(th) end
  genCounter = genCounter + 1
  th.gen = genCounter
  programs[th] = ctx.prog
  return th
end
Themes.Compile = Compile

-- source: the text "return { ... }" of the theme (Themes/<key>.lua), or a builder
-- function returning the source table.
function Themes.Register(key, source)
  if key == "class" or not IS_KEY[key] then
    error("Themes.Register: unknown theme key " .. tostring(key), 2)
  end
  if registry[key] ~= nil then error("Themes.Register: duplicate theme key " .. tostring(key), 2) end
  if type(source) == "string" and string_find(source, "^%s*return%s*{") then
    source = Compact(source)
  elseif type(source) ~= "function" then
    error("Themes.Register: a source text \"return { ... }\" or a builder function expected", 2)
  end
  registry[key] = source
end

function Themes.IsRegistered(key)
  return registry[key] ~= nil
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
  if type(key) ~= "string" or not registry[key] then
    key = registry.futuriste and "futuriste" or "actuel"
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
  local th, reason = Compile(key)
  if not th and ns.Util then ns.Util.Debug("theme: %s", reason) end
  if not th and key ~= "futuriste" then th = Compile("futuriste") end
  if not th and key ~= "actuel" then th = Compile("actuel") end
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
local WRAP_H = { H = "REPEAT", HV = "REPEAT", V = "CLAMP" }
local WRAP_V = { V = "REPEAT", HV = "REPEAT", H = "CLAMP" }
function Themes.SetTex(t, spec)
  local tile = spec.tile
  if tile then
    t:SetTexture(spec.path, WRAP_H[tile], WRAP_V[tile])
  else
    t:SetTexture(spec.path)
  end
  local tc8 = spec.tc8
  if tc8 then
    t:SetTexCoord(tc8[1], tc8[2], tc8[3], tc8[4], tc8[5], tc8[6], tc8[7], tc8[8])
  elseif not tile and not spec.slice then
    local l, r, tt, b = spec.l, spec.r, spec.t, spec.b
    local fx, fy = spec.flipX, spec.flipY
    if fx or fy or l ~= 0 or r ~= 1 or tt ~= 0 or b ~= 1 then
      if fx then l, r = r, l end
      if fy then tt, b = b, tt end
      t:SetTexCoord(l, r, tt, b)
    end
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

-- Direction, from, to and flat colour of any gradient form: one pair { from, to, dir = }
-- (the compiled form), a per-state list of pairs (k = the fill state, default 0; a state
-- without an entry gives the first: the state-2 alpha is the caller's, see BarSkin), or
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
-- the layer's own colour instead of the default opaque white. SetGradient takes colour
-- tables with r, g, b, a fields: two scratch tables of this file carry the values (a
-- colour is an rgba array; hash-only and hybrid tables are read too).
local GF = { r = 0, g = 0, b = 0, a = 0 }
local GT = { r = 0, g = 0, b = 0, a = 0 }

local function ApplyGradient(t, dir, from, to, flat)
  local fl = flat or from
  t:SetVertexColor(fl[1] or fl.r, fl[2] or fl.g, fl[3] or fl.b, fl[4] or fl.a or 1)
  local gf, gt = GF, GT
  gf.r, gf.g, gf.b, gf.a = from[1] or from.r, from[2] or from.g, from[3] or from.b, from[4] or from.a or 1
  gt.r, gt.g, gt.b, gt.a = to[1] or to.r, to[2] or to.g, to[3] or to.b, to[4] or to.a or 1
  if t.SetGradient and pcall(t.SetGradient, t, dir, gf, gt) then return 1 end
  if t.SetGradientAlpha and pcall(t.SetGradientAlpha, t, dir, gf.r, gf.g, gf.b, gf.a, gt.r, gt.g, gt.b,
      gt.a) then
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
-- Gradient; every piece gets the same flat colour (the from colour when none); the
-- colours at the cuts live in reused tables (no allocation), and no table of the caller
-- stays referenced after the call.
local cut1 = { 0, 0, 0, 0 }
local cut2 = { 0, 0, 0, 0 }
local seg1, seg2, seg3 = {}, {}, {}

local function Lerp(out, from, to, f)
  local r0, g0, b0, a0 = from[1] or from.r, from[2] or from.g, from[3] or from.b, from[4] or from.a or 1
  local r1, g1, b1, a1 = to[1] or to.r, to[2] or to.g, to[3] or to.b, to[4] or to.a or 1
  out[1], out[2], out[3], out[4] = r0 + (r1 - r0) * f, g0 + (g1 - g0) * f, b0 + (b1 - b0) * f, a0 + (a1 - a0) * f
end

function Themes.GradientSliced(texs, n, g, flat, k, w, h, p)
  local dir, from, to, fl = GradientParts(g, flat, k)
  fl = fl or from
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
  seg1[1], seg3[2] = nil, nil       -- the caller's colours are not kept (P5)
  return res
end
