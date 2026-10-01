-- tests/test_theme_compact.lua - the memory pass of the themes (design/NEXT-LOT.md A):
--   M1 the compact compiled form: plain rgba colour arrays (static ones one per value
--      within a compile, dynamic ones each its own), no default field stored, the same
--      drawn values as the round-4 compiler for the 13 themes;
--   M2 the shipped compiler is silent and robust: bad data falls back exactly as the
--      round-4 compiler did (tests/theme_validate.lua holds that compiler and its
--      warnings);
--   M3 the theme sources: compact source texts, compiled on demand in an empty
--      environment, losslessly compacted, without comment or function.
local Stub, T = ...
local TV = dofile(Stub.ROOT .. "tests/theme_validate.lua")

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }
local BASE = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- The engine, then the 13 theme files with Register wrapped: raw[key] = the text (or
-- builder) each file registers, before Register compacts it. Returns ns, raw, and the
-- shipped Themes.Compile (before the validator wraps it).
local function LoadAll()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = BASE })
  local raw = {}
  local register = ns.Themes.Register
  ns.Themes.Register = function(key, source)
    raw[key] = source
    register(key, source)
  end
  for _, key in ipairs(KEYS) do
    local chunk = assert(loadfile(Stub.ROOT .. "Themes/" .. key .. ".lua"))
    chunk("TruePlayed", ns)
  end
  ns.Themes.Register = register
  local compile = ns.Themes.Compile
  TV.Install(ns)
  return ns, raw, compile
end

-- An upvalue of a Themes function (test-only introspection).
local function Upvalue(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end

-- A source text evaluated as Lua code, in an empty environment.
local LOADSTRING, SETFENV = rawget(_G, "loadstring"), rawget(_G, "setfenv")   -- Lua 5.1 only
local function Eval(text)
  local fn, err
  if SETFENV then
    fn, err = LOADSTRING(text)
    if fn then SETFENV(fn, {}) end
  else
    fn, err = load(text, "=text", "t", {})
  end
  assert(fn, err)
  return fn()
end

-- Every colour slot of a compiled theme: { path, table } (the tables the engines read).
local function Colours(th)
  local out = {}
  local function Add(path, c)
    if type(c) == "table" then out[#out + 1] = { path, c } end
  end
  local function Entry(path, x)
    if type(x) ~= "table" then return end
    if type(x[1]) == "table" then
      for i = 1, #x do Entry(path .. "[" .. i .. "]", x[i]) end
    else
      Add(path, x)
    end
  end
  local function Grad(path, g)
    if type(g) ~= "table" then return end
    if type(g[1]) == "table" and type(g[1][1]) == "table" then
      for i = 1, #g do Grad(path .. "[" .. i .. "]", g[i]) end
    else
      Add(path .. ".from", g[1])
      Add(path .. ".to", g[2])
    end
  end
  local function Item(path, it)
    Entry(path .. ".c", rawget(it, "c"))
    Grad(path .. ".g", it.g)
    Entry(path .. ".f", it.f)
  end
  for i, L in ipairs(th.bar.layers) do Item("layer " .. L.id .. i, L) end
  if type(th.bar.panel) == "table" then
    for i, P in ipairs(th.bar.panel.parts) do Item("bar part " .. i, P) end
  end
  for k, c in pairs(th.text.colors) do Add("text.colors." .. k, c) end
  Add("text.shadow.c", rawget(th.text, "shadow") and th.text.shadow.c)
  for k, c in pairs(th.ui) do Add("ui." .. k, c) end
  for k, c in pairs(th.colors) do Add("colors." .. k, c) end
  Add("accent", th.accent)
  local tt = th.tt
  if not tt.native then
    for k, c in pairs(tt.colors) do Add("tt.colors." .. k, c) end
    for i, P in ipairs(tt.panel.parts) do Item("tt part " .. i, P) end
    for k, s in pairs(tt.sep) do Item("tt.sep." .. k, s) end
    if tt.leader then Item("tt.leader", tt.leader) end
    if tt.gauge then
      Add("tt.gauge.outline", tt.gauge.outline)
      for k, c in pairs(tt.gauge.colors) do Add("tt.gauge.colors." .. k, c) end
    end
  end
  return out
end

-- Fields of the compiled records equal to their default (the metatable's __index).
local function StoredDefaults(th)
  local bad, seen = {}, {}
  local function Walk(t, path)
    if type(t) ~= "table" or seen[t] then return end
    seen[t] = true
    local mt = getmetatable(t)
    local def = mt and type(mt.__index) == "table" and mt.__index or nil
    for k, v in pairs(t) do
      if def and def[k] ~= nil and def[k] == v then bad[#bad + 1] = path .. "." .. tostring(k) end
      Walk(v, path .. "." .. tostring(k))
    end
  end
  Walk(th, "th")
  local fonts = th.fonts
  if rawget(fonts, "num") ~= nil and rawget(fonts, "num") == rawget(fonts, "body") then bad[#bad + 1] = "fonts.num" end
  local function Parts(list, where)
    for i, P in ipairs(list or {}) do
      if rawget(P, "sub") == -8 + i - 1 then bad[#bad + 1] = where .. "[" .. i .. "].sub" end
    end
  end
  if type(th.bar.panel) == "table" then Parts(th.bar.panel.parts, "bar.panel.parts") end
  if not th.tt.native then
    Parts(rawget(th.tt, "panel") and th.tt.panel.parts, "tt.panel.parts")
    if th.tt.fonts.value == th.tt.fonts.body then bad[#bad + 1] = "tt.fonts.value" end
  end
  return bad
end

-- Every table reachable from root through next() (not through metatables).
local function Mark(root)
  local set, stack = {}, { root }
  while #stack > 0 do
    local t = table.remove(stack)
    if not set[t] then
      set[t] = true
      for k, v in next, t do
        if type(k) == "table" then stack[#stack + 1] = k end
        if type(v) == "table" then stack[#stack + 1] = v end
      end
    end
  end
  return set
end

-- A source with bad data everywhere the compiler falls back (round-4 warnings), under
-- the key `hunter` (its file is not loaded by these tests).
local function BadSource()
  return {
    name = 42, extra = true,
    fonts = { display = "NoSuch", body = "Orbitron", num = 7 },
    colors = {
      xp = "#12345", rested = { 2, 0, 0 }, label = "loopA", loopA = "loopB", loopB = "loopA",
      value = "deep1", deep1 = "deep2", deep2 = "deep3", deep3 = "deep4", deep4 = "deep5",
      deep5 = "deep6", deep6 = "#ffffff", dim = "base+.2", accent = "xp@.5+.2", ["bad name"] = "#000000",
      none = "#ffffff", hot = "xp+.45", rs = "rested-.3@.8", def = { "rested+.1", def = { "xp", def = "#000000" } },
      unknown = "nosuchcolour@.5", numeric = { 0.1, 0.2, 0.3, 0.4, 0.5 },
    },
    media = { ok = { 16, 16 }, bad = { 15, 16 }, Upper = { 8, 8 }, grey = { 8, 8, grey = "yes" }, big = { 512, 8 } },
    bar = {
      pad = -3, gap = 1.5, height = { add = 99, min = "x" }, maxAlpha = 2,
      layers = {
        "not a table",
        { span = "middle", sub = 9, layer = "TOP", file = "nosuch", rect = { 0, 0, 99, 99 }, rot = 45, tile = "X",
          blend = "MUL", top = "x", h = -1 },
        { id = "dup", span = "fill", color = "base@.5", alpha = 0.5, maxAlpha = 0.5 },
        { id = "dup", span = "fillEnd" },
        { id = "t", ticks = "x" },
        { id = "t2", ticks = { n = 500, w = 0, clip = "all", mid = 1 } },
        { id = "three", three = { "ok", -1, 4 }, file = "ok" },
        { id = "nine", nine = { "ok", 4, 4 }, flipX = "yes", band = { 0.5, 0.2 }, pad = { "a", 1 } },
        { id = "g", span = "rested", grad = { "DIAGONAL", "#fff", "#000" }, flat = "#ffffff" },
        { id = "g2", span = "fill", grad = { "VERTICAL", "base", "xp@0" }, flat = "rested", alpha = 0.6 },
        { id = "g3", span = "track", grad = { "HORIZONTAL", { "rested", def = "#102030" }, "base-.5" } },
        -- a static fill-span gradient with an alpha and a maxAlpha of its own: an explicit
        -- state 2 (alpha x maxAlpha folded at compile time), not state 0 x bar.maxAlpha
        { id = "g4", span = "fill", grad = { "VERTICAL", "#ffffff@.4", "#000000@.8" }, flat = "#808080@.6",
          alpha = 0.5, maxAlpha = 0.5 },
        { id = "caps", caps = "yes", file = "ok" },
        { id = "anchor", span = "trackEnd", w = 0.5, align = "middle", dx = "x", capInset = 1 },
        { id = "rot", file = "ok", rot = 90, rect = { 0, 0, 8, 8 }, flipY = true },
        { id = "pad0", span = "fill", pad = { 0, 0 }, color = { "base", def = "#334455" }, maxAlpha = 1 },
        { id = "uncommon", file = "common/nosuch", band = { 0, 1, 2 } },
      },
      panel = { parts = { 5, { id = "p", anchor = "NOWHERE", inset = { 1 }, alpha = "line", x = 3 },
                          { anchor = "TOP", w = -1, alpha = 7, grad = { "HORIZONTAL", "xp", "rested" } },
                          { id = "z", inset = { 0, 0, 0, 0 }, alpha = 0.25, color = "rs", sub = 7 } } },
    },
    text = { font = { s1 = "display", level = "nope", wat = "body", marker = "display" },
             size = { s1 = 99, s2 = 1.5, hint = 3 }, boxSize = "x", split = "yes", splitGap = 99,
             levelFmt = "lower", colors = { label = "base", marker = "hot", slot2 = 5 },
             shadow = { color = "rs", x = 99 } },
    tooltip = { native = "no", width = { 500, 100 }, pad = { 1, 2, 3 }, gap = -1, lineGap = "x",
                fonts = { title = { "display", 99 }, body = { "display", 14 }, note = "x" },
                colors = { title = "base", rested = "rested+.2", dim = "rs" },
                panel = { parts = { { id = "a", nine = { "ok", 4, 4 }, grad = { "VERTICAL", "#000000", "#ffffff" } } } },
                titleIcon = { "ok", "x", 3 },
                sep = { header = { file = "ok", center = 1 }, block = 5,
                        footer = { file = "ok", mirror = true, center = 4, grad = { "HORIZONTAL", "xp", "xp@0" } } },
                leader = { file = "ok", tile = "V", h = 99 }, gauge = { w = 1, colors = { world = "#000" } } },
    ui = { bg = "rested", title = 3 },
  }
end

---------------------------------------------------------------------------
-- M1: compact compiled form
---------------------------------------------------------------------------

T.test("compact form: every colour is a plain rgba array; one array per static value, one per dynamic colour", function()
  local ns = LoadAll()
  Stub.LoginSequence()
  local programs = Upvalue(ns.Themes.Recolor, "programs")
  for _ = 1, 2 do
    for _, key in ipairs(KEYS) do
      local th = ns.Themes.Compile(key)
      local prog = programs[th]
      local dynamic, nDyn = {}, 0
      for i = 1, #prog, 5 do
        T.no(dynamic[prog[i]], key .. ": a dynamic colour is its own array")
        dynamic[prog[i]] = true
        nDyn = nDyn + 1
      end
      local byValue, seen = {}, {}
      for _, e in ipairs(Colours(th)) do
        local path, c = e[1], e[2]
        local keys = 0
        for _ in pairs(c) do keys = keys + 1 end
        T.ok(keys == 4 and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
          and type(c[4]) == "number", key .. " " .. path .. ": 4 numbers, nothing else")
        seen[c] = true
        if not dynamic[c] then
          local v = string.format("%.17g %.17g %.17g %.17g", c[1], c[2], c[3], c[4])
          T.ok(byValue[v] == nil or byValue[v] == c, key .. " " .. path .. ": one array per static value")
          byValue[v] = c
        end
      end
      for c in pairs(dynamic) do T.ok(seen[c], key .. ": every dynamic colour is drawn somewhere") end
      if key == "futuriste" or key == "actuel" then T.ok(nDyn > 0, key .. ": dynamic colours") end
    end
    ns.Core.SetSetting("widget.xpColor", { 0.2, 0.9, 0.3 })   -- again with user colours
    ns.Core.SetSetting("widget.restedColor", { 0.9, 0.2, 0.3 })
  end
  T.eq(#Stub.errors, 0)
end)

T.test("compact form: no field equal to its default is stored (records, text, tooltip, specs)", function()
  local ns = LoadAll()
  Stub.LoginSequence()
  for _, key in ipairs(KEYS) do
    T.eq(StoredDefaults(ns.Themes.Compile(key)), {}, key .. ": stored defaults")
  end
  local th = ns.Themes.Compile("actuel")
  T.eq(next(th.text.size), nil, "actuel: every text size is the default")
  T.eq(rawget(th.bar, "pad"), nil, "bar.pad 8: not stored")
  T.eq(th.bar.pad, 8, "read through the defaults")
end)

T.test("compact form: draws exactly what the round-4 compiler compiled (13 themes, user colours on and off)", function()
  local ns, _, compile = LoadAll()
  Stub.LoginSequence()
  for pass = 1, 3 do
    for _, key in ipairs(KEYS) do
      local th = compile(key)
      local legacy, warnings = TV.Compile(ns, key, TV.Builder(ns, key))
      T.eq(warnings, {}, key)
      local same, path, a, b = TV.Same(TV.Canon(th), TV.Canon(legacy), "")
      T.ok(same, string.format("%s (pass %d): %s = %s, round 4: %s", key, pass, tostring(path), tostring(a), tostring(b)))
    end
    if pass == 1 then
      ns.Core.SetSetting("widget.xpColor", { 0.15, 0.5, 0.85 })
    else
      ns.Core.SetSetting("widget.restedColor", { 1, 0.4, 0 })
    end
  end
end)

T.test("compact form: a recolour rewrites the dynamic arrays only, in place", function()
  local ns = LoadAll()
  Stub.LoginSequence()
  local Th = ns.Themes
  local programs = Upvalue(Th.Recolor, "programs")
  local th = Th.Active()
  T.eq(th.key, "futuriste")
  local prog = programs[th]
  local dynamic = {}
  for i = 1, #prog, 5 do dynamic[prog[i]] = true end
  local before = {}
  for _, e in ipairs(Colours(th)) do before[e[2]] = { e[2][1], e[2][2], e[2][3], e[2][4] } end
  ns.Core.SetSetting("widget.xpColor", { 0, 1, 0 })
  ns.Core.SetSetting("widget.restedColor", { 1, 0, 0 })
  T.ok(Th.Active() == th, "the same compiled theme")
  local changed = 0
  for c, v in pairs(before) do
    if dynamic[c] then
      if not TV.Same({ c[1], c[2], c[3], c[4] }, v, "") then changed = changed + 1 end
    else
      T.eq({ c[1], c[2], c[3], c[4] }, v, "a static colour keeps its value")
    end
  end
  T.ok(changed > 10, "dynamic colours rewritten: " .. changed)
end)

T.test("compact form: two compiles share no table; GradientSliced keeps no colour of the caller", function()
  local ns = LoadAll()
  Stub.LoginSequence()
  local Th = ns.Themes
  for _, key in ipairs({ "futuriste", "warlock", "actuel" }) do
    local a, b = Mark(Th.Compile(key)), Mark(Th.Compile(key))
    local classic = Mark(Th.CLASSIC_TT)            -- the classic palette: a constant of Themes
    local shared = 0
    for t in pairs(a) do
      if b[t] and not classic[t] then shared = shared + 1 end
    end
    T.eq(shared, 0, key .. ": tables shared by two compiles (static colours are shared within one only)")
  end
  local th = Th.Compile("mage")
  local P
  for _, p in ipairs(th.bar.panel.parts) do
    if p.kind == "nine" and p.g then P = p end
  end
  T.ok(P, "mage: a 9-slice panel part with a gradient")
  local f = CreateFrame("Frame", nil, UIParent)
  local t9 = {}
  for i = 1, 9 do t9[i] = f:CreateTexture() end
  T.eq(Th.GradientSliced(t9, 9, P.g, P.f, nil, 200, 100, 10), 1)
  for _, name in ipairs({ "seg1", "seg2", "seg3" }) do
    local seg = Upvalue(Th.GradientSliced, name)
    T.ok(seg[1] ~= P.g[1] and seg[2] ~= P.g[1] and seg[1] ~= P.g[2] and seg[2] ~= P.g[2], name .. ": no compiled colour kept")
  end
  for i = 1, 9 do T.eq(type(rawget(t9[i], "_grad")), "table", "SetGradient took r, g, b, a tables") end
end)

---------------------------------------------------------------------------
-- M2: the shipped compiler is silent, the validator reports
---------------------------------------------------------------------------

T.test("compiler: bad data everywhere falls back exactly as the round-4 compiler, silently", function()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = BASE })
  local compile = ns.Themes.Compile
  local src
  ns.Themes.Register("hunter", function() return src end)
  Stub.LoginSequence()
  for pass = 1, 2 do
    src = BadSource()
    local th, second = compile("hunter")
    T.ok(th, "compiled despite the bad data")
    T.eq(second, nil, "no warning list from the shipped compiler")
    src = BadSource()
    local legacy, warnings = TV.Compile(ns, "hunter", function() return src end)
    T.ok(legacy and #warnings > 40, "the validator reports the bad data: " .. #warnings .. " warnings")
    local same, path, a, b = TV.Same(TV.Canon(th), TV.Canon(legacy), "")
    T.ok(same, string.format("pass %d: %s = %s, round 4: %s", pass, tostring(path), tostring(a), tostring(b)))
    ns.Core.SetSetting("widget.xpColor", { 0.3, 0.3, 0.9 })
  end
  -- what cannot be built: nil and a reason, never an error
  src = 42
  local th, reason = compile("hunter")
  T.eq(th, nil)
  T.match(reason, "^hunter: builder failed: 42")
  ns.Themes.Register("mage", function() error("boom") end)
  th, reason = compile("mage")
  T.eq(th, nil)
  T.match(reason, "builder failed: .*boom")
  ns.Themes.Register("rogue", "return { bar = { layers = { { id = 'x' } } }, oops")
  th, reason = compile("rogue")
  T.eq(th, nil)
  T.match(reason, "^rogue: builder failed: ")
  T.eq(compile("nosuch"), nil)
  T.eq(#Stub.errors, 0)
end)

T.test("compiler: the validator (test-only) holds the warnings; the addon has none", function()
  local f = assert(io.open(Stub.ROOT .. "Themes.lua", "r"))
  local text = f:read("*a")
  f:close()
  T.no(text:find("unknown field", 1, true), "no warning text in Themes.lua")
  T.no(text:find("Warn(", 1, true), "no Warn call in Themes.lua")
  T.no(text:find("CheckFields", 1, true), "no field check in Themes.lua")
  f = assert(io.open(Stub.ROOT .. "tests/theme_validate.lua", "r"))
  text = f:read("*a")
  f:close()
  T.ok(text:find("unknown field", 1, true) and text:find("local function Warn", 1, true), "the validator has them")
end)

---------------------------------------------------------------------------
-- M3: the theme sources
---------------------------------------------------------------------------

T.test("sources: 13 compact texts, no builder function resident, no comment and no function inside", function()
  local ns, raw = LoadAll()
  local registry = Upvalue(ns.Themes.IsRegistered, "registry")
  for _, key in ipairs(KEYS) do
    T.eq(type(raw[key]), "string", key .. ": a source text is registered")
    T.eq(type(registry[key]), "string", key .. ": the registry holds text, not a builder")
    T.no(raw[key]:find("--", 1, true), key .. ": no comment inside the source")
    T.no(raw[key]:find("function", 1, true), key .. ": no function inside the source")
    T.match(raw[key], "^%s*return%s*{", key)
    T.no(registry[key]:find("\n[ \t]"), key .. ": no indentation kept")
    T.ok(#registry[key] < #raw[key], key .. ": compacted")
  end
end)

-- The backslash escapes of a source text other than those Lua 5.1 (the game) and 5.2+ read
-- the same way: \ddd, \n, \\, \" and \' (a \x.., \z or \u{..} is 5.2+ only and reads as
-- plain letters in 5.1). lint51 sees a source text as one long-bracket string: this is
-- its check of the string literals inside.
local function BadEscapes(text)
  local bad, i = {}, 1
  while true do
    local j = string.find(text, "\\", i, true)
    if not j then return bad end
    local c = string.sub(text, j + 1, j + 1)
    if not string.find(c, "^[%dn\\\"']$") then bad[#bad + 1] = "\\" .. c end
    i = j + 2
  end
end

T.test("sources: only escapes that Lua 5.1 reads the same way, no long bracket inside (13 themes)", function()
  local _, raw = LoadAll()
  for _, key in ipairs(KEYS) do
    T.eq(BadEscapes(raw[key]), {}, key .. ": escapes that Lua 5.1 reads differently")
    T.no(raw[key]:find("%[=*%["), key .. ": no long bracket inside the source")
  end
  T.eq(BadEscapes("a = \"\\065\\n\\\\\\\"\", b = '\\''"), {}, "the kept escapes")
  T.eq(BadEscapes("c = \"#\\x33\\x38b000\", d = \"\\z \\u{41}\\t\""), { "\\x", "\\x", "\\z", "\\u", "\\t" },
    "5.2+ escapes (and the ones the list does not keep) found")
end)

T.test("sources: the compaction is lossless (13 themes), strings kept as they are", function()
  local ns, raw = LoadAll()
  local Th = ns.Themes
  for _, key in ipairs(KEYS) do
    local full = Eval(raw[key])
    local compact = Eval(Th.CompactSource(raw[key]))
    T.ok(TV.Same(compact, full, ""), key .. ": compacted text = text")
    local ok, src = Th.Source(key)
    T.ok(ok and TV.Same(src, full, ""), key .. ": Themes.Source = the text")
    local ok2, again = Th.Source(key)
    T.ok(ok2 and again ~= src, key .. ": a new table each time (nothing kept)")
  end
  local text = "return {\n  a = \"x = { y , z }\",\n  b = 'it\\'s = {',\n  c = \"q\\\"  ,  }\",\n  d = { 1 , 2 },\n}"
  T.eq(Eval(Th.CompactSource(text)), Eval(text), "blanks inside strings kept")
  T.eq(Th.CompactSource(text), "return{a=\"x = { y , z }\",b='it\\'s = {',c=\"q\\\"  ,  }\",d={1,2},}", "the compact text")
end)

T.test("sources: actuel writes C.COLORS out exactly (the same numbers)", function()
  local ns = LoadAll()
  local _, src = ns.Themes.Source("actuel")
  local K = ns.C.COLORS
  local map = { xp = "fill", rested = "restedFill", label = "label", value = "value", dim = "dim", accent = "accent",
                pause = "pause", track = "track", bg = "bg", border = "border" }
  local n = 0
  for name, c in pairs(src.colors) do
    n = n + 1
    T.ok(map[name], "actuel colour " .. name .. " is a C.COLORS one")
    T.eq(c, K[map[name]], "colors." .. name .. " = C.COLORS." .. tostring(map[name]))
  end
  T.eq(n, 10)
  local layers = {}
  for _, L in ipairs(src.bar.layers) do layers[L.id] = L end
  T.eq(layers.fillHi.color, K.fillHi, "fillHi = C.COLORS.fillHi")
  T.eq(layers.restTick.color.def, K.restTick, "restTick def = C.COLORS.restTick")
end)

T.test("sources: Register takes a source text or a builder; a text runs in an empty environment", function()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = BASE })
  local Th = ns.Themes
  T.raises(function() Th.Register("mage", "not a source") end, "a text that is not a source")
  T.raises(function() Th.Register("mage", 42) end, "a number")
  T.raises(function() Th.Register("mage", { name = "THEME_MAGE" }) end, "a table")
  T.no(Th.IsRegistered("mage"))
  Th.Register("mage", "\n  return { name = tostring(1) }")
  local ok, err = Th.Source("mage")
  T.no(ok, "tostring is not visible from a source text")
  T.match(tostring(err), "tostring")
  Th.Register("rogue", "return { name = ns, other = _G, C = C }")
  local ok2, src = Th.Source("rogue")
  T.ok(ok2 and next(src) == nil, "no global, no namespace visible")
  T.eq(Th.Compile("rogue") ~= nil, true, "compiles (every section falls back)")
  T.eq(Th.Source("nosuch"), nil, "not registered")
  T.eq(#Stub.errors, 0)
end)
