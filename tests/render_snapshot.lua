-- tests/render_snapshot.lua - render-identity snapshot (design/NEXT-LOT.md A, "proof of
-- render identity"). Not a test file (not in tests/run.lua): a tool that writes what the
-- addon DRAWS, so that two checkouts can be compared line by line.
--
-- Usage (from the root of the checkout that holds this file):
--   TZ=UTC lua tests/render_snapshot.lua <outfile> [addonRoot/]
-- The stub (tests/wowstub.lua, tests/stub_ui.lua) is the one of the checkout this file
-- lives in; the addon files are loaded from addonRoot (default: the same checkout; the
-- trailing "/" is required). Comparing a pass against the commit taken before it:
--   TZ=UTC lua tests/render_snapshot.lua /tmp/rs-base.txt /path/to/base/checkout/
--   TZ=UTC lua tests/render_snapshot.lua /tmp/rs-new.txt
--   diff /tmp/rs-base.txt /tmp/rs-new.txt          (must print nothing)
-- TZ=UTC: the Sessions tab shows date() texts, which follow the time zone.
--
-- Coverage: the 13 themes x 8 scenarios (defaults, rested, max level, server cap, box
-- style, custom colours, bgAlpha 0.5 + thick outline + no shadow, unlocked), each loaded
-- with the theme and again after a switch from another theme (pooled regions reused),
-- plus one session switching through every theme with a recolour and a style change.
-- Views of each scenario: the widget, the tooltip short and with Shift (the private
-- frame, and the GameTooltip for the native theme), the graph, the window (3 tabs) and
-- the options panel.
--
-- What is written is what the game would draw, never a raw stub field that could be
-- stale or depend on table addresses:
--   * the colour of a texture is the last of SetVertexColor / SetColorTexture /
--     SetGradient / SetGradientAlpha (the stub's sequence numbers);
--   * defaults are normalised (draw layer ARTWORK, sublayer 0, blend BLEND, full texture
--     coordinates, CLAMP wrap);
--   * rectangles are absolute (anchors solved as the game does: two opposite anchors set
--     the size), relative to the snapped root; anchors name their target (parent, root,
--     a global name, or type@rect), never a table address;
--   * the lines of a view are a sorted multiset (pooled regions change hands in an order
--     that follows table addresses);
--   * numbers use "%.17g" (any last-bit difference shows), -0 is written 0, NaN "nan";
--   * errors reported through geterrorhandler, and errors raised, are written too.
-- Methods the stub does not record (it answers unknown methods with a no-op) are
-- recorded by a hook on the stub's method table: Set* calls only, last arguments.

local ROOT
do
  local script = ((arg and arg[0]) or "tests/render_snapshot.lua"):gsub("\\", "/")
  local root, n = script:gsub("tests/render_snapshot%.lua$", "")
  if n == 0 or root == "" then root = "./" end
  ROOT = root
end

local OUT = arg and arg[1]
local ADDON_ROOT = (arg and arg[2]) or ROOT
if not OUT then
  io.stderr:write("usage: lua tests/render_snapshot.lua <outfile> [addonRoot/]\n")
  os.exit(2)
end
if ADDON_ROOT:sub(-1) ~= "/" then ADDON_ROOT = ADDON_ROOT .. "/" end

local Stub = dofile(ROOT .. "tests/wowstub.lua")
Stub.ROOT = ROOT
Stub.AddInstaller(dofile(ROOT .. "tests/stub_ui.lua"))

local format, concat, sort = string.format, table.concat, table.sort
local UIParentObj = rawget(_G, "UIParent")

---------------------------------------------------------------------------
-- Numbers and values
---------------------------------------------------------------------------
local function N(x)
  if type(x) ~= "number" then return tostring(x) end
  if x ~= x then return "nan" end
  local s = format("%.17g", x)
  if s == "-0" then s = "0" end
  return s
end

-- Any argument value, without table addresses.
local function V(x)
  local t = type(x)
  if t == "number" then return N(x) end
  if t == "string" then return format("%q", x) end
  if t == "table" then
    local name = rawget(x, "_name")
    if name then return "@" .. tostring(name) end
    local ty = rawget(x, "_type")
    return ty and ("<" .. tostring(ty) .. ">") or "<table>"
  end
  return tostring(x)
end

---------------------------------------------------------------------------
-- Unrecorded Set* methods (the stub's no-op answer to unknown methods)
---------------------------------------------------------------------------
do
  local methods = getmetatable(UIParentObj).__index
  local mt = getmetatable(methods)
  local baseIndex = mt.__index
  local recorders = {}
  mt.__index = function(t, k)
    local f = baseIndex(t, k)
    if f and type(k) == "string" and k:sub(1, 3) == "Set" then
      local rec = recorders[k]
      if not rec then
        rec = function(self, ...)
          local u = rawget(self, "_unk")
          if not u then
            u = {}
            rawset(self, "_unk", u)
          end
          local parts = {}
          for i = 1, select("#", ...) do parts[i] = V((select(i, ...))) end
          u[k] = concat(parts, ",")
        end
        recorders[k] = rec
      end
      return rec
    end
    return f
  end
end

---------------------------------------------------------------------------
-- Geometry: anchors solved as the game does (the stub's GetRect reads point 1 only)
---------------------------------------------------------------------------
local AN = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 },
             CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 },
             BOTTOMRIGHT = { 1, 0 } }

local function Solve(list, size)
  local lo, hi = list[1], list[1]
  for i = 2, #list do
    local e = list[i]
    if e[1] < lo[1] then lo = e end
    if e[1] > hi[1] then hi = e end
  end
  if hi[1] > lo[1] then
    local s = (hi[2] - lo[2]) / (hi[1] - lo[1])
    return lo[2] - s * lo[1], s
  end
  return lo[2] - size * lo[1], size
end

local function TrueRect(o, depth)
  depth = (depth or 0) + 1
  if depth > 40 or o == nil then return nil end
  if rawget(o, "_isUIParent") then return 0, 0, rawget(o, "_width"), rawget(o, "_height") end
  local pts = rawget(o, "_points")
  if not pts or #pts == 0 then return nil end
  local xs, ys = {}, {}
  for _, p in ipairs(pts) do
    local rl, rb, rw, rh = TrueRect(p.rel or rawget(o, "_parent") or UIParentObj, depth)
    if not rl then return nil end
    local ra, an = AN[p.relPoint] or AN.CENTER, AN[p.point] or AN.CENTER
    xs[#xs + 1] = { an[1], rl + rw * ra[1] + p.x }
    ys[#ys + 1] = { an[2], rb + rh * ra[2] + p.y }
  end
  local l, w = Solve(xs, rawget(o, "_width") or 0)
  local b, h = Solve(ys, rawget(o, "_height") or 0)
  return l, b, w, h
end

local function Under(o, root)
  local p, d = rawget(o, "_parent"), 0
  while p ~= nil and d < 60 do
    if p == root then return true end
    p, d = rawget(p, "_parent"), d + 1
  end
  return false
end

-- The stub's GetEffectiveAlpha is the region's own alpha: multiply along the parents.
local function EffAlpha(o)
  local a, d = 1, 0
  while o and d < 60 do
    a = a * (rawget(o, "_alpha") or 1)
    o, d = rawget(o, "_parent"), d + 1
  end
  return a
end

local function RelName(rel, o, root)
  if rel == nil or rel == rawget(o, "_parent") then return "parent" end
  if rel == root then return "root" end
  local name = rawget(rel, "_name")
  if name then return name end
  local l, b, w, h = TrueRect(rel)
  return tostring(rawget(rel, "_type")) .. "@" .. N(l) .. "," .. N(b) .. "," .. N(w) .. "," .. N(h)
end

local function Points(o, root)
  local pts = rawget(o, "_points") or {}
  local out = {}
  for i, p in ipairs(pts) do
    out[i] = tostring(p.point) .. ">" .. RelName(p.rel, o, root) .. "." .. tostring(p.relPoint)
      .. "(" .. N(p.x) .. "," .. N(p.y) .. ")"
  end
  return concat(out, ";")
end

---------------------------------------------------------------------------
-- One line per drawn object
---------------------------------------------------------------------------
local function List(t)
  if type(t) ~= "table" then return "-" end
  local o = {}
  for i = 1, #t do o[i] = V(t[i]) end
  return concat(o, ",")
end

local function Unk(o)
  local u = rawget(o, "_unk")
  if not u then return "" end
  local keys = {}
  for k in pairs(u) do keys[#keys + 1] = k end
  sort(keys)
  local out = {}
  for i, k in ipairs(keys) do out[i] = k .. "(" .. u[k] .. ")" end
  return " | unk=" .. concat(out, ";")
end

local function Wrap(m)
  if m == nil or m == "CLAMP" then return "C" end
  return tostring(m)
end

local function Quad(o, a, b, c, d)
  return N(rawget(o, a)) .. "," .. N(rawget(o, b)) .. "," .. N(rawget(o, c)) .. "," .. N(rawget(o, d))
end

local function Head(o, root, rl, rb)
  local l, b, w, h = TrueRect(o)
  local rect = l and (N(l - rl) .. "," .. N(b - rb) .. "," .. N(w) .. "," .. N(h)) or "unplaced"
  local ty = rawget(o, "_type")
  local layer = rawget(o, "_layer")
  if ty == "Texture" or ty == "FontString" or ty == "MaskTexture" then layer = layer or "ARTWORK" end
  return concat({ tostring(ty), tostring(layer), N(rawget(o, "_subLayer") or 0),
    "rect=" .. rect, "size=" .. N(rawget(o, "_width")) .. "x" .. N(rawget(o, "_height")),
    "pts=" .. Points(o, root), "a=" .. N(rawget(o, "_alpha")), "ea=" .. N(EffAlpha(o)),
    "sc=" .. N(rawget(o, "_scale")) }, " | ")
end

local function TextureColor(o)
  local v, g, ga = rawget(o, "_vSeq") or 0, rawget(o, "_gSeq") or 0, rawget(o, "_gaSeq") or 0
  if g > v and g >= ga then return "grad(" .. List(rawget(o, "_grad")) .. ")" end
  if ga > v and ga > g then return "gradA(" .. List(rawget(o, "_gradA")) .. ")" end
  if rawget(o, "_vR") == nil then return "v(1,1,1,1)" end
  local a = rawget(o, "_vA")
  return "v(" .. N(rawget(o, "_vR")) .. "," .. N(rawget(o, "_vG")) .. "," .. N(rawget(o, "_vB")) .. ","
    .. N(a == nil and 1 or a) .. ")"
end

local function Line(o, root, rl, rb)
  local ty = rawget(o, "_type")
  local head = Head(o, root, rl, rb)
  if ty == "Texture" or ty == "MaskTexture" then
    local file = rawget(o, "_texture")
    local fileText = tostring(file)
    if file == nil and rawget(o, "_cR") ~= nil then
      fileText = "ctex(" .. Quad(o, "_cR", "_cG", "_cB", "_cA") .. ")"
    end
    local tc = List(rawget(o, "_tc"))
    if tc == "-" or tc == "0,1,0,1" or tc == "0,0,0,1,1,0,1,1" then tc = "full" end
    local mask = rawget(o, "_mask")
    local maskText = "-"
    if mask then
      maskText = tostring(rawget(mask, "_texture")) .. "/" .. Wrap(rawget(mask, "_wrapH")) .. "/"
        .. Wrap(rawget(mask, "_wrapV"))
    end
    return concat({ head, "file=" .. fileText,
      "wrap=" .. Wrap(rawget(o, "_wrapH")) .. "/" .. Wrap(rawget(o, "_wrapV")), TextureColor(o),
      "tc=" .. tc, "blend=" .. tostring(rawget(o, "_blend") or "BLEND"), "mask=" .. maskText }, " | ")
      .. Unk(o)
  elseif ty == "FontString" then
    local fo = rawget(o, "_fontObject")
    return concat({ head, format("%q", tostring(rawget(o, "_text"))),
      "font=" .. tostring(rawget(o, "_font")) .. "," .. N(rawget(o, "_fontSize")) .. ","
        .. tostring(rawget(o, "_fontFlags")),
      "fo=" .. (type(fo) == "table" and tostring(rawget(fo, "_name")) or tostring(fo)),
      "tc=" .. Quad(o, "_tR", "_tG", "_tB", "_tA"),
      "j=" .. tostring(rawget(o, "_justifyH")) .. "/" .. tostring(rawget(o, "_justifyV")),
      "sh=" .. N(rawget(o, "_shadowX")) .. "," .. N(rawget(o, "_shadowY")) .. ","
        .. Quad(o, "_sR", "_sG", "_sB", "_sA") }, " | ") .. Unk(o)
  end
  local bd = rawget(o, "_backdrop")
  local bdText = "-"
  if type(bd) == "table" then
    local ins = type(bd.insets) == "table" and bd.insets or {}
    bdText = concat({ tostring(bd.bgFile), tostring(bd.edgeFile), tostring(bd.tile), N(bd.tileSize),
      N(bd.edgeSize), N(ins.left), N(ins.right), N(ins.top), N(ins.bottom) }, ",")
  end
  return concat({ head, "bd=" .. bdText, "bg=" .. Quad(o, "_bgR", "_bgG", "_bgB", "_bgA"),
    "bdc=" .. Quad(o, "_bdR", "_bdG", "_bdB", "_bdA"), "strata=" .. tostring(rawget(o, "_strata")),
    "lvl=" .. tostring(rawget(o, "_level")), "mouse=" .. tostring(rawget(o, "_mouse")) }, " | ") .. Unk(o)
end

-- Every visible object drawn under root (sorted), after the root's own line.
local function Snap(root)
  if not root then return { "absent" } end
  if not root:IsVisible() then return { "hidden" } end
  local rl, rb = TrueRect(root)
  rl, rb = rl or 0, rb or 0
  local lines = {}
  for _, o in ipairs(Stub.regions) do
    if Under(o, root) and o:IsVisible() and EffAlpha(o) > 0 then
      local keep = true
      if rawget(o, "_type") == "FontString" then
        local t = rawget(o, "_text")
        keep = t ~= nil and t ~= ""
      end
      if keep then lines[#lines + 1] = Line(o, root, rl, rb) end
    end
  end
  sort(lines)
  table.insert(lines, 1, "ROOT " .. Line(root, UIParentObj, 0, 0))
  return lines
end

-- The shared GameTooltip (outside Stub.regions): owner, anchors, lines and colours.
local function SnapGT()
  local tt = rawget(_G, "GameTooltip")
  local owner = rawget(tt, "_owner")
  local out = { "shown=" .. tostring(tt:IsShown()) .. " owner="
    .. tostring(type(owner) == "table" and rawget(owner, "_name") or owner) }
  for i, p in ipairs(rawget(tt, "_points") or {}) do
    out[#out + 1] = "pt" .. i .. " " .. tostring(p.point) .. " "
      .. tostring(type(p.rel) == "table" and rawget(p.rel, "_name") or p.rel) .. " "
      .. tostring(p.relPoint) .. " " .. N(p.x) .. " " .. N(p.y)
  end
  if tt:IsShown() then
    local lines, colors = rawget(tt, "_lines") or {}, rawget(tt, "_colors") or {}
    for i, l in ipairs(lines) do
      local c = colors[i] or {}
      out[#out + 1] = format("%q|%q|", tostring(l[1]), tostring(l[2]))
        .. concat({ N(c[1]), N(c[2]), N(c[3]), N(c[4]), N(c[5]), N(c[6]) }, ",")
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------
local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }

local function Set(ns, path, v)
  ns.Core.SetSetting(path, v)
  Stub.Advance(1)
end

local SCENARIOS = {
  { name = "defaults" },
  { name = "rested",
    setup = function() Stub.player.xp, Stub.player.rest = 2000, 3000 end,
    play = function(ns) Set(ns, "widget.locked", true) end },
  { name = "maxlevel",
    setup = function() Stub.player.level, Stub.player.xp, Stub.player.max = 60, 0, 0 end,
    play = function(ns) Set(ns, "widget.locked", true) end },
  { name = "servercap",
    setup = function()
      local p = Stub.player
      p.level, p.xp, p.max, p.rest = 20, 58, Stub.xpTable[20], 4000
    end,
    play = function(ns)
      Set(ns, "widget.locked", true)
      Stub.party[1] = 22
      for _ = 1, 3 do
        Stub.KillNoXP({ level = 20 })
        Stub.Advance(30)
      end
    end },
  { name = "box",
    setup = function() Stub.player.xp, Stub.player.rest = 2000, 3000 end,
    play = function(ns)
      Set(ns, "widget.locked", true)
      Set(ns, "widget.style", "box")
    end },
  { name = "colours",
    setup = function() Stub.player.xp, Stub.player.rest = 2000, 3000 end,
    play = function(ns)
      Set(ns, "widget.locked", true)
      Set(ns, "widget.xpColor", { 0.9, 0.3, 0.1 })
      Set(ns, "widget.restedColor", { 0.1, 0.7, 0.9 })
      Set(ns, "widget.textColor", { 1, 0.82, 0 })
    end },
  { name = "bg05",
    setup = function() Stub.player.xp = 3000 end,
    play = function(ns)
      Set(ns, "widget.locked", true)
      Set(ns, "widget.bgAlpha", 0.5)
      Set(ns, "widget.outline", "thick")
      Set(ns, "widget.shadow", false)
    end },
  { name = "unlocked",
    setup = function() Stub.player.xp = 1000 end,
    play = function(ns)
      Set(ns, "widget.locked", false)
      Set(ns, "widget.fade", true)
      Stub.RunScript(rawget(_G, "TruePlayedWidget"), "OnEnter")
    end },
}

---------------------------------------------------------------------------
-- Output
---------------------------------------------------------------------------
local out = {}

local function Emit(label, lines)
  out[#out + 1] = "== " .. label .. " (" .. #lines .. ")"
  for i = 1, #lines do out[#out + 1] = lines[i] end
end

local function EmitErrors()
  local errors = Stub.errors or {}
  for i = 1, #errors do out[#out + 1] = "ERROR " .. (tostring(errors[i]):match("^[^\n]*")) end
end

-- The bar and the tooltip (short, then Shift).
local function EmitBarAndTip(ns, label)
  local w = rawget(_G, "TruePlayedWidget")
  Emit(label .. " bar", Snap(w))
  Stub.shift = false
  Stub.RunScript(w, "OnEnter")
  Stub.Advance(1)
  Emit(label .. " tip", Snap(ns.TooltipFrame.frame))
  Emit(label .. " gt", SnapGT())
  Stub.SetShift(true)
  Stub.Advance(1)
  Emit(label .. " tipShift", Snap(ns.TooltipFrame.frame))
  Emit(label .. " gtShift", SnapGT())
  Stub.SetShift(false)
  Stub.RunScript(w, "OnLeave")
end

-- Every view: bar, tooltips, graph, window (3 tabs), options panel.
local function EmitViews(ns, label)
  local w = rawget(_G, "TruePlayedWidget")
  EmitBarAndTip(ns, label)
  ns.Graph.ShowFor(w)
  Stub.Advance(1)
  Emit(label .. " graph", Snap(ns.Graph.frame))
  ns.Graph.Hide()
  for _, tab in ipairs({ "levels", "zones", "sessions" }) do
    ns.Window.Show(tab)
    Stub.Advance(1)
    Emit(label .. " window " .. tab, Snap(rawget(_G, "TruePlayedStatsFrame")))
  end
  ns.Window.Hide()
  ns.Options.Open()
  Stub.Advance(1)
  local cat = Stub.ui and Stub.ui.categories and Stub.ui.categories[1]
  Emit(label .. " options", Snap(cat and cat.frame))
  Stub.ui.CloseSettings()
end

-- A fresh session: Stub.theme = start, then (optionally) a switch to `key`.
local function Session(label, start, key, setup, play, views)
  Stub.Reset()
  Stub.ROOT = ADDON_ROOT
  Stub.InstallUI({ ldb = false })
  Stub.theme = start
  if setup then setup() end
  local ok, err = pcall(function()
    local ns = Stub.LoadAddon()
    Stub.LoginSequence({ settle = 3 })
    Stub.Advance(2)
    if key ~= start then
      ns.Core.SetSetting("theme", key)
      Stub.Advance(1)
    end
    if play then play(ns) end
    views(ns, label)
  end)
  Stub.ROOT = ROOT
  if not ok then out[#out + 1] = "RAISED " .. (tostring(err):match("^[^\n]*")) end
  EmitErrors()
end

local t0 = os.clock()

-- 1. Each theme loaded at login, 8 scenarios.
for _, key in ipairs(KEYS) do
  for _, sc in ipairs(SCENARIOS) do
    Session(key .. "/" .. sc.name, key, key, sc.setup, sc.play, EmitViews)
  end
end

-- 2. Each theme reached by a switch from the previous one in KEYS (regions of the
--    previous theme are pooled and reused), 8 scenarios.
for i, key in ipairs(KEYS) do
  local prev = KEYS[(i - 2) % #KEYS + 1]
  for _, sc in ipairs(SCENARIOS) do
    Session("switch " .. prev .. ">" .. key .. "/" .. sc.name, prev, key, sc.setup, sc.play, EmitViews)
  end
end

-- 3. One session through every theme (twice the list, the second time with user colours
--    and in the box style, back to the bar style at the end), the tooltip shown at each
--    step so that its pools change hands too.
Session("chain", "actuel", "actuel", function() Stub.player.xp, Stub.player.rest = 2000, 3000 end,
  function(ns) Set(ns, "widget.locked", true) end,
  function(ns, label)
    local steps = {}
    for _, key in ipairs(KEYS) do steps[#steps + 1] = key end
    steps[#steps + 1] = "colours"
    for _, key in ipairs(KEYS) do steps[#steps + 1] = key end
    steps[#steps + 1] = "bar"
    for n, step in ipairs(steps) do
      if step == "colours" then
        Set(ns, "widget.xpColor", { 0.2, 0.8, 0.3 })
        Set(ns, "widget.restedColor", { 0.8, 0.2, 0.6 })
        Set(ns, "widget.style", "box")
      elseif step == "bar" then
        Set(ns, "widget.xpColor", false)
        Set(ns, "widget.style", "bar")
      else
        Set(ns, "theme", step)
      end
      EmitBarAndTip(ns, label .. " " .. n .. " " .. step)
    end
  end)

local f = assert(io.open(OUT, "w"))
f:write(concat(out, "\n"), "\n")
f:close()
io.stderr:write(format("%d lines, %.2f s (%s, addon root %s)\n", #out, os.clock() - t0, _VERSION, ADDON_ROOT))
