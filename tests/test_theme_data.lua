-- tests/test_theme_data.lua - the data of every theme file (design/SPEC-themes.md 2, 4.2,
-- 4.3, 6.1, 8.3): all 13 themes registered, zero compile warnings, fonts, media references,
-- ids, sublevels, bands, overlapping layers, required colours and roles, `base` only in
-- bar layers, and the display role kept away from arbitrary text.
-- The checks read the source table AND the compiled theme, so a compiler slip that would
-- swallow a problem without a warning still shows up here. The warnings come from the
-- test-only validator (tests/theme_validate.lua, installed on Themes.Compile).
local Stub, T = ...
local TV = dofile(Stub.ROOT .. "tests/theme_validate.lua")

local BASE = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua" }
local DRAW_LAYERS = { BACKGROUND = true, BORDER = true, ARTWORK = true, OVERLAY = true }
local KINDS = { tex = true, caps = true, three = true, nine = true, ticks = true }
local FONT_ROLES = { display = true, body = true, num = true, game = true }
-- Bar texts that show arbitrary strings (SPEC 8.3, plus the unlocked hint sentence).
local NO_DISPLAY_TEXT = { "s1", "s2", "s3", "xp", "sep", "levelValue", "hint" }
local TEXT_ELEMS = { "s1", "s2", "s3", "level", "levelValue", "xpLabel", "xp", "sep", "marker", "hint" }
local TEXT_ROLES = { "label", "value", "levelLabel", "levelValue", "xpText", "sep", "marker", "hint",
                     "slot3", "dimmed" }
local TT_ROLES = { "title", "mode", "label", "value", "dim", "header", "pause", "hint", "levelLabel",
                   "levelValue", "levelValueRested", "rested" }
local TT_FONTS = { "title", "body", "value", "note", "hint" }
local REQUIRED_COLORS = { "xp", "rested", "label", "value", "dim", "accent" }
local UI_ROLES = { "bg", "border", "title", "accent", "label", "value", "dim" }
local GAUGE_KEYS = { "world", "dungeon", "raid", "pvp", "taxi", "afk", "inn", "city" }

---------------------------------------------------------------------------
-- Loading: the engine, then every Themes\*.lua of the TOC with Register wrapped so that
-- the source tables can be read too (builders[key]() builds the registered source).
---------------------------------------------------------------------------
local function ReadFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- "Themes/<key>.lua" entries of the TOC, in order, and the line of Themes.lua.
local function TocThemeFiles()
  local list, enginePos = {}, nil
  local toc = ReadFile(Stub.ROOT .. "TruePlayed_Camelot.toc") or ""
  local n = 0
  for raw in (toc .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 2) ~= "##" then
      n = n + 1
      if line == "Themes.lua" then enginePos = n end
      local entry = line:match("^Themes\\([%w_]+)%.lua$")
      if entry then list[#list + 1] = { key = entry, file = "Themes/" .. entry .. ".lua", pos = n } end
    end
  end
  return list, enginePos
end

local function LoadAll()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = BASE })
  TV.Install(ns)
  local builders, missing, problems = {}, {}, {}
  local register = ns.Themes.Register
  ns.Themes.Register = function(key, source)
    register(key, source)
    builders[key] = TV.Builder(ns, key)
  end
  for _, e in ipairs((TocThemeFiles())) do
    local path = Stub.ROOT .. e.file
    if not ReadFile(path) then
      missing[#missing + 1] = e.file
    else
      local chunk, err = loadfile(path)
      if not chunk then
        problems[#problems + 1] = tostring(err)
      else
        local ok, err2 = pcall(chunk, "TruePlayed", ns)
        if not ok then problems[#problems + 1] = e.file .. ": " .. tostring(err2) end
      end
    end
  end
  ns.Themes.Register = register
  return ns, builders, missing, problems
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Add(list, fmt, ...)
  list[#list + 1] = string.format(fmt, ...)
end

local function IsUnit(x)
  return type(x) == "number" and x == x and x >= 0 and x <= 1
end

local function IsRGBA(c)
  return type(c) == "table" and IsUnit(c[1]) and IsUnit(c[2]) and IsUnit(c[3]) and IsUnit(c[4])
end

-- Every string of the source table that is a colour expression whose source is `base`,
-- with its path. Paths are "a.b[3].c".
local function FindBase(v, path, out, seen)
  if type(v) == "string" then
    if v == "base" or v:find("^base[%+%-@%s]") then out[#out + 1] = path end
  elseif type(v) == "table" and not seen[v] then
    seen[v] = true
    for k, x in pairs(v) do
      local p
      if type(k) == "number" then p = path .. "[" .. k .. "]"
      elseif path == "" then p = tostring(k)
      else p = path .. "." .. tostring(k) end
      FindBase(x, p, out, seen)
    end
  end
  return out
end

-- Every compiled texture spec (a table with a string `path`) of a compiled theme.
local function FindTex(v, path, out, seen)
  if type(v) ~= "table" or seen[v] then return out end
  seen[v] = true
  if type(v.path) == "string" then out[#out + 1] = { path = path, tex = v } end
  for k, x in pairs(v) do
    if type(x) == "table" then
      local p = type(k) == "number" and (path .. "[" .. k .. "]") or (path .. "." .. tostring(k))
      FindTex(x, p, out, seen)
    end
  end
  return out
end

local function Root()
  return "Interface\\AddOns\\TruePlayed\\Media\\Themes\\"
end

-- Rows [y0, y1) of a compiled layer for a track height H (2.4.1).
local function Rows(Lc, H)
  if Lc.band then
    return math.floor(Lc.band[1] * H + 0.5), math.floor(Lc.band[2] * H + 0.5)
  end
  local y0 = Lc.top or 0
  if Lc.h then return y0, y0 + Lc.h end
  return y0, H - (Lc.bottom or 0)
end

local RANGE = { track = true, fill = true, rested = true }

-- Columns [x0, x1) for a track width W, fill px and rested rpx; nil when hidden.
local function Cols(Lc, W, px, rpx)
  local span = Lc.span or "track"
  if Lc.kind == "ticks" then
    if Lc.ticks and Lc.ticks.clip == "fill" then return 0, px end
    return 0, W
  end
  if RANGE[span] then
    local a, b
    if span == "track" then a, b = 0, W
    elseif span == "fill" then a, b = 0, px
    else a, b = px, rpx end
    if b <= a then return nil end
    local pad = Lc.pad or { 0, 0 }
    return a - (pad[1] or 0), b + (pad[2] or 0)
  end
  local anchor = (span == "fillEnd" and px) or (span == "restEnd" and rpx) or (span == "trackStart" and 0) or W
  local w = Lc.w or 0
  local x0
  if Lc.align == "left" then x0 = anchor
  elseif Lc.align == "right" then x0 = anchor - w
  else x0 = anchor - math.floor(w / 2) end
  x0 = x0 + (Lc.dx or 0)
  return x0, x0 + w
end

-- Layers that share a (layer, sub) pair and overlap at some reachable size.
local function Overlaps(th, out)
  local heights = {}
  for user = 4, 16 do                            -- widget.height range
    local H = user + th.bar.hAdd
    if H < th.bar.hMin then H = th.bar.hMin end
    heights[#heights + 1] = H
  end
  local W = 200
  local states = { { 80, 140 }, { 10, 190 }, { 150, 160 } }
  local list = {}
  for _, Lc in ipairs(th.bar.layers) do list[#list + 1] = Lc end
  local reported = {}
  for i = 1, #list do
    for j = i + 1, #list do
      local a, b = list[i], list[j]
      if a.layer == b.layer and a.sub == b.sub then
        local hit
        for _, H in ipairs(heights) do
          local ay0, ay1 = Rows(a, H)
          local by0, by1 = Rows(b, H)
          if ay1 > ay0 and by1 > by0 and ay0 < by1 and by0 < ay1 then
            for _, s in ipairs(states) do
              local ax0, ax1 = Cols(a, W, s[1], s[2])
              local bx0, bx1 = Cols(b, W, s[1], s[2])
              if ax0 and bx0 and ax1 > ax0 and bx1 > bx0 and ax0 < bx1 and bx0 < ax1 then
                hit = H
                break
              end
            end
          end
          if hit then break end
        end
        local key = a.id .. "/" .. b.id
        if hit and not reported[key] then
          reported[key] = true
          Add(out, "layers %s and %s overlap (H = %d) on the same %s %d", a.id, b.id,
            hit, a.layer, a.sub)
        end
      end
    end
  end
end

-- ids, handles, sublevels, bands and kinds of the bar layers.
local function CheckLayers(th, out)
  local ids, handles = {}, {}
  local function Handle(h, id)
    if handles[h] then Add(out, "texture handle %s of layer %s is also used by %s", h, id, handles[h]) end
    handles[h] = id
  end
  for i, Lc in ipairs(th.bar.layers) do
    local id = Lc.id
    if type(id) ~= "string" or id == "" then
      Add(out, "bar.layers[%d]: missing id", i)
    else
      if ids[id] then Add(out, "bar.layers[%d]: duplicate id %s", i, id) end
      ids[id] = true
      if Lc.kind == "caps" or Lc.kind == "three" then
        Handle(id .. "L", id); Handle(id .. "M", id); Handle(id .. "R", id)
      else
        Handle(id, id)
      end
      if id == "veil" then Add(out, "bar.layers: id 'veil' is reserved for Bar.lua") end
    end
    if not KINDS[Lc.kind] then Add(out, "%s: kind %s", tostring(id), tostring(Lc.kind)) end
    if not DRAW_LAYERS[Lc.layer] then Add(out, "%s: draw layer %s", tostring(id), tostring(Lc.layer)) end
    if type(Lc.sub) ~= "number" or Lc.sub % 1 ~= 0 or Lc.sub < -8 or Lc.sub > 7 then
      Add(out, "%s: sub %s outside -8..7", tostring(id), tostring(Lc.sub))
    end
    if Lc.band ~= nil then
      local b = Lc.band
      if not (type(b) == "table" and IsUnit(b[1]) and IsUnit(b[2]) and b[1] < b[2]) then
        Add(out, "%s: band must be { f0, f1 } with 0 <= f0 < f1 <= 1", tostring(id))
      end
    end
    -- what is drawn in each fill state: the vertex colour, or the gradient and its flat colour
    for k = 0, 2 do
      local ok
      if Lc.g then
        local from, to = TV.Pair(th, Lc, k)
        ok = IsRGBA(from) and IsRGBA(to) and IsRGBA(TV.Flat(th, Lc, k))
      else
        ok = IsRGBA(TV.Color(th, Lc, k))
      end
      if not ok then Add(out, "%s: compiled colours of state %d are not rgba tables in 0..1", tostring(id), k) end
    end
  end
end

local function CheckParts(parts, where, out)
  local ids = {}
  for i, P in ipairs(parts) do
    if type(P.id) ~= "string" or P.id == "" then Add(out, "%s[%d]: missing id", where, i) end
    if P.id and ids[P.id] then Add(out, "%s[%d]: duplicate id %s", where, i, P.id) end
    if P.id then ids[P.id] = true end
    if not DRAW_LAYERS[P.layer] then Add(out, "%s.%s: draw layer %s", where, tostring(P.id), tostring(P.layer)) end
    local sub = TV.PartSub(P, i)
    if type(sub) ~= "number" or sub % 1 ~= 0 or sub < -8 or sub > 7 then
      Add(out, "%s.%s: sub %s outside -8..7", where, tostring(P.id), tostring(sub))
    end
  end
end

-- Every compiled texture comes from a declared media of the theme or from COMMON_MEDIA,
-- with the declared size, or is the white file.
local function CheckMedia(ns, key, th, src, out)
  local media = type(src.media) == "table" and src.media or {}
  local white = ns.C.TEX_WHITE
  local own = Root() .. key .. "\\"
  local common = Root() .. "common\\"
  for _, e in ipairs(FindTex(th, "th", {}, {})) do
    local p = e.tex.path
    if p ~= white then
      local decl, name
      if p:sub(1, #own) == own then
        name = p:sub(#own + 1):match("^([a-z0-9_]+)%.tga$")
        decl = name and media[name]
      elseif p:sub(1, #common) == common then
        name = p:sub(#common + 1):match("^([a-z0-9_]+)%.tga$")
        decl = name and ns.Themes.COMMON_MEDIA[name]
      end
      if not decl then
        Add(out, "%s: texture %s is neither declared media nor the white file", e.path, p)
      elseif e.tex.w ~= decl[1] or e.tex.h ~= decl[2] then
        Add(out, "%s: %s compiled as %sx%s, declared %dx%d", e.path, name, tostring(e.tex.w),
          tostring(e.tex.h), decl[1], decl[2])
      end
    end
  end
  for name, d in pairs(media) do
    if type(name) ~= "string" or not name:find("^[a-z0-9_]+$") then
      Add(out, "media name %s is not lowercase [a-z0-9_]", tostring(name))
    end
    if type(d) ~= "table" then Add(out, "media.%s is not { w, h }", tostring(name)) end
  end
end

local function CheckFonts(ns, th, out)
  local FONTS = ns.Themes.FONTS
  for _, role in ipairs({ "display", "body", "num" }) do
    local name = th.fonts[role]
    if name ~= "game" and not FONTS[name] then Add(out, "fonts.%s: %s is not in Themes.FONTS", role, tostring(name)) end
    if role ~= "display" then
      if name == "Orbitron" then Add(out, "fonts.%s: Orbitron is display only", role) end
      if FONTS[name] and FONTS[name].display then Add(out, "fonts.%s: %s is display only", role, name) end
    end
  end
  for _, e in ipairs(TEXT_ELEMS) do
    if not FONT_ROLES[th.text.font[e]] then Add(out, "text.font.%s: role %s", e, tostring(th.text.font[e])) end
  end
  for _, e in ipairs(NO_DISPLAY_TEXT) do
    if th.text.font[e] == "display" then Add(out, "text.font.%s uses the display role", e) end
  end
  if not th.native then
    for _, name in ipairs(TT_FONTS) do
      local f = th.tt.fonts[name] or (name == "value" and th.tt.fonts.body)   -- (the readers' rule)
      local role = f and f[1]
      if not FONT_ROLES[role] then Add(out, "tooltip.fonts.%s: role %s", name, tostring(role)) end
      if name ~= "title" and role == "display" then Add(out, "tooltip.fonts.%s uses the display role", name) end
    end
  end
end

local function CheckColors(th, src, out)
  local sc = type(src.colors) == "table" and src.colors or {}
  for _, name in ipairs(REQUIRED_COLORS) do
    if sc[name] == nil then Add(out, "colors.%s is missing from the source", name) end
    if not IsRGBA(th.colors[name]) then Add(out, "th.colors.%s is not an rgba colour", name) end
  end
  if not IsRGBA(th.colors.pause) then Add(out, "th.colors.pause is not an rgba colour") end
  if not IsRGBA(th.accent) then Add(out, "th.accent is not an rgba colour") end
  for _, role in ipairs(UI_ROLES) do
    if not IsRGBA(th.ui[role]) then Add(out, "ui.%s is not an rgba colour", role) end
  end
  for _, role in ipairs(TEXT_ROLES) do
    if not IsRGBA(th.text.colors[role]) then Add(out, "text.colors.%s is not an rgba colour", role) end
  end
  if not th.native then
    for _, role in ipairs(TT_ROLES) do
      if not IsRGBA(th.tt.colors[role]) then Add(out, "tooltip.colors.%s is not an rgba colour", role) end
    end
    local cc = th.tt.colors.ccDim
    if type(cc) ~= "string" or not cc:find("^|cff%x%x%x%x%x%x$") then
      Add(out, "tooltip.colors.ccDim %s is not a |cffrrggbb code", tostring(cc))
    end
    if th.tt.gauge then
      for _, k in ipairs(GAUGE_KEYS) do
        if not IsRGBA(th.tt.gauge.colors[k]) then Add(out, "tooltip.gauge.colors.%s is not an rgba colour", k) end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Tests
---------------------------------------------------------------------------

T.test("theme data: the TOC loads the 13 theme files after Themes.lua and all 13 register", function()
  local list, enginePos = TocThemeFiles()
  T.ok(enginePos, "Themes.lua is in the TOC")
  local inToc = {}
  for _, e in ipairs(list) do
    inToc[e.key] = true
    T.ok(e.pos > enginePos, e.file .. " is listed after Themes.lua")
  end
  local ns, builders, missing, problems = LoadAll()
  T.eq(problems, {}, "theme files load without error")
  T.eq(missing, {}, "every theme file of the TOC exists")
  local unregistered, notInToc = {}, {}
  for _, key in ipairs(ns.C.THEME_CHOICES) do
    if key ~= "class" then
      if not ns.Themes.IsRegistered(key) or not builders[key] then unregistered[#unregistered + 1] = key end
      if not inToc[key] then notInToc[#notInToc + 1] = key end
    end
  end
  T.eq(unregistered, {}, "every theme key is registered")
  T.eq(notInToc, {}, "every theme key has its Themes\\<key>.lua line in the TOC")
  T.eq(#ns.Themes.KEYS, 13, "13 theme keys")
end)

T.test("theme data: a theme file only registers its own key", function()
  local ns = LoadAll()
  for _, e in ipairs((TocThemeFiles())) do
    local text = ReadFile(Stub.ROOT .. e.file)
    if text then
      local keys = {}
      for k in text:gmatch("Register%(%s*\"([%w_]+)\"") do keys[#keys + 1] = k end
      T.eq(keys, { e.key }, e.file .. " registers exactly its key")
    end
  end
  T.ok(ns.Themes.IsRegistered("actuel"))
end)

-- One test per key, so that a problem names its theme.
local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }

for _, key in ipairs(KEYS) do
  T.test("theme data: " .. key, function()
    local ns, builders = LoadAll()
    Stub.LoginSequence()
    if not builders[key] then T.skip(key .. " is not registered (see the registration test)") end
    local src = builders[key]()
    T.eq(type(src), "table", "the builder returns the source table")
    local th, warnings = ns.Themes.Compile(key)
    T.eq(warnings, {}, key .. ": compile warnings")
    T.ok(th, key .. " compiles")

    local problems = {}
    -- name: the THEME_<KEY> locale key, present in enUS and translated in frFR
    if src.name ~= "THEME_" .. key:upper() then Add(problems, "name %s, expected THEME_%s", tostring(src.name), key:upper()) end
    if rawget(ns.L, src.name) == nil then Add(problems, "%s is missing from Locales/enUS.lua", tostring(src.name)) end
    local fr = ReadFile(Stub.ROOT .. "Locales/frFR.lua") or ""
    if not fr:find("\nL%." .. tostring(src.name) .. "%s*=") then
      Add(problems, "%s is missing from Locales/frFR.lua", tostring(src.name))
    end
    CheckFonts(ns, th, problems)
    CheckMedia(ns, key, th, src, problems)
    CheckLayers(th, problems)
    if type(th.bar.panel) == "table" then CheckParts(th.bar.panel.parts, "bar.panel.parts", problems) end
    if not th.native then CheckParts(th.tt.panel.parts, "tooltip.panel.parts", problems) end
    Overlaps(th, problems)
    CheckColors(th, src, problems)
    -- `base` (the fill colour of the current state) only means something in bar layers
    for _, path in ipairs(FindBase(src, "", {}, {})) do
      if not path:find("^bar%.layers%[") then Add(problems, "%s uses 'base' outside bar.layers", path) end
    end
    if key == "actuel" then
      T.ok(th.native, "actuel keeps the native tooltip")
      T.eq(th.bar.panel, "backdrop", "actuel keeps the legacy backdrop")
    else
      T.no(th.native, key .. ": only actuel uses the native tooltip")
    end
    T.eq(problems, {}, key .. ": data problems")
  end)
end

T.test("theme data: the checks above catch broken data (fixture)", function()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = BASE })   -- engine only: "hunter" is free for the fixture
  TV.Install(ns)
  Stub.LoginSequence()
  local src = {
    name = "THEME_HUNTER",
    fonts = { display = "Orbitron", body = "Rajdhani" },
    colors = { xp = "#ff2bd6", rested = "#22d3ee", label = "#a3bfcf", value = "#f0fbff", dim = "#7f96a9",
               accent = "#22d3ee" },
    media = { line = { 16, 2, grey = true } },
    bar = { layers = {
      { id = "track", layer = "BORDER" },
      { id = "trackLow", band = { 0.5, 1 }, layer = "BORDER" },               -- overlaps track, same sub
      { id = "fillTop", span = "fill", band = { 0, 0.5 }, sub = 2, color = "base" },
      { id = "fillLow", span = "fill", band = { 0.5, 1 }, sub = 2, color = "base-.3" },   -- disjoint: fine
      { id = "glow", span = "fill", three = { "line", 4, 4 }, sub = 3 },
      { id = "glowL", span = "trackStart", w = 4, layer = "OVERLAY" },        -- handle clash with glow's L
    } },
    text = { font = { hint = "display" } },
    tooltip = { fonts = { title = { "display", 13 }, body = { "body", 14 }, note = { "display", 12 },
                          hint = { "body", 12 } },
                colors = { title = "base" },
                panel = { parts = { { id = "bg", color = "#000000" } } } },
    ui = { bg = "#000000", border = "accent", title = "accent", accent = "accent", label = "label",
           value = "value", dim = "dim" },
  }
  ns.Themes.Register("hunter", function() return src end)
  local th, warnings = ns.Themes.Compile("hunter")
  T.ok(th)
  local joined = table.concat(warnings, "\n")
  T.match(joined, "text%.font%.hint: shows arbitrary text", "hint in display warns")
  T.match(joined, "tooltip%.fonts%.note: shows arbitrary text", "tooltip note in display warns")
  T.match(joined, "tooltip%.colors%.title: 'base' is only valid in bar%.layers", "base outside layers warns")
  local problems = {}
  Overlaps(th, problems)
  CheckLayers(th, problems)
  local text = table.concat(problems, "\n")
  T.match(text, "layers track and trackLow overlap", "overlap found")
  T.no(text:find("fillTop and fillLow", 1, true), "disjoint bands are not an overlap")
  T.match(text, "texture handle glowL of layer glowL is also used by glow", "handle clash found")
  local bases = FindBase(src, "", {}, {})
  table.sort(bases)
  T.eq(bases, { "bar.layers[3].color", "bar.layers[4].color", "tooltip.colors.title" })
end)
