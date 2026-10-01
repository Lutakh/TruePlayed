-- tests/test_theme.lua - Themes.lua and the theme setting (design/SPEC-themes.md 1, 2.3,
-- 2.6, 2.8, 3.1-3.3, 6.3, 8.3): setting, repair, resolution, THEME_CHANGED, in-place
-- recolour, compiled form, fonts (resolution, snapping, SetFont cache, missing files),
-- substitutions and the texture helpers.
-- Most tests load the foundation and the theme engine only (no Bar / Tooltip / Options),
-- and register their own fixture themes under keys whose file is not loaded.
-- Themes.Compile is wrapped by the test-only validator (tests/theme_validate.lua): it
-- returns the warnings of the source, and checks that every compile draws what the
-- round-4 compiler compiled.
local Stub, T = ...
local TV = dofile(Stub.ROOT .. "tests/theme_validate.lua")

local CORE = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua" }
local ENGINE = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua", "Themes/actuel.lua" }
local GAME = "Fonts\\FRIZQT__.TTF"

-- Every theme file of the TOC (foundation + engine + Themes/*.lua).
local function ThemeFiles()
  local files = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua" }
  local f = io.open(Stub.ROOT .. "TruePlayed_Camelot.toc", "r")
  if f then
    for line in f:lines() do
      local entry = line:gsub("\r$", ""):match("^%s*(Themes\\[%w_]+%.lua)%s*$")
      entry = entry and entry:gsub("\\", "/")
      local h = entry and io.open(Stub.ROOT .. entry, "r")    -- a theme not landed yet is skipped
      if h then
        h:close()
        files[#files + 1] = entry
      end
    end
    f:close()
  end
  return files
end

local function Load(files, theme)
  Stub.theme = theme
  local ns = Stub.LoadAddon({ files = files })
  if ns.Themes then TV.Install(ns) end
  return ns
end

local function Messages(ns)
  local got = {}
  ns.RegisterMessage("THEME_CHANGED", "test", function(_, key, prev, kind)
    got[#got + 1] = { key, prev, kind }
  end)
  return got
end

local function R3(c)
  return { math.floor(c[1] * 1000 + 0.5), math.floor(c[2] * 1000 + 0.5), math.floor(c[3] * 1000 + 0.5),
           math.floor((c[4] or 1) * 1000 + 0.5) }
end

local function Hex(s)
  return { tonumber(s:sub(2, 3), 16) / 255, tonumber(s:sub(4, 5), 16) / 255, tonumber(s:sub(6, 7), 16) / 255, 1 }
end

local function Lighten(c, k)
  return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k, c[4] }
end

local function Layer(th, id)
  for _, Lc in ipairs(th.bar.layers) do
    if Lc.id == id then return Lc end
  end
  return nil
end

-- A small but complete theme source (every compiled feature), fonts overridable.
local function Fixture(fonts)
  return {
    name = "THEME_FUTURISTE",
    fonts = fonts or { display = "Orbitron", body = "Rajdhani" },
    colors = {
      xp = "#ff2bd6", rested = "#22d3ee", label = "#a3bfcf", value = "#f0fbff", dim = "#7f96a9",
      accent = "cyan", cyan = "#22d3ee", navy = "#060c1a", hot = "xp+.45", ink = { 0.004, 0.016, 0.043 },
    },
    media = { line = { 16, 2, grey = true }, frame = { 32, 32 }, icon = { 16, 16 } },
    bar = {
      pad = 10, gap = 4, height = { add = 6, min = 10 },
      layers = {
        { id = "track", layer = "BORDER", grad = { "VERTICAL", "#03060e@.93", "#0c1426@.88" },
          flat = "#070d1a@.9" },
        { id = "glow", span = "fill", three = { "common/glow", 16, 8 }, pad = { 8, 8 }, top = -6,
          bottom = -6, layer = "BORDER", sub = -2, blend = "ADD", color = "base@.55" },
        { id = "rested", span = "rested", sub = 1, grad = { "HORIZONTAL", "rested+.5@.62", "rested+.5@0" } },
        { id = "fill", span = "fill", sub = 3, color = "base" },
        { id = "band", span = "fill", band = { 0, 0.28 }, sub = 4, grad = { "VERTICAL", "#ffffff@.12", "#ffffff@.72" } },
        { id = "ticks", ticks = { n = 10 }, layer = "BORDER", sub = 2, color = "#a5f3fc@.26" },
        { id = "segs", ticks = { n = 10, clip = "fill" }, sub = 6, color = "ink@.5", alpha = 0.5 },
        { id = "line", file = "line", tile = "H", top = 0, h = 1, sub = 5 },
        { id = "frame", nine = { "frame", 8, 8 }, pad = { 1, 1 }, top = -1, bottom = -1, sub = 7 },
        { id = "bracket", span = "trackEnd", file = "icon", flipX = true, w = 8, align = "left", dx = 2,
          layer = "OVERLAY" },
        { id = "marker", span = "fillEnd", w = 2, top = -4, bottom = -4, layer = "OVERLAY", color = "base+.85" },
      },
      panel = { parts = {
        { id = "panelFill", color = "navy", alpha = "bg" },
        { id = "accentTop", anchor = "TOPLEFT", x = 15, y = 0, w = 96, h = 2, color = "cyan", alpha = 0.5 },
      } },
    },
    text = {
      font = { level = "display", marker = "display", xp = "num" },
      size = { s1 = 3, hint = 0 },
      split = true, splitGap = 5,
      colors = { marker = "hot", levelValue = "#ffffff" },
      shadow = { color = "ink@.85" },
    },
    tooltip = {
      fonts = { title = { "display", 13 }, body = { "body", 15 }, note = { "body", 13 }, hint = { "body", 12 } },
      colors = { title = "cyan", levelValue = "xp+.45", rested = "rested+.45" },
      panel = { parts = { { id = "bg", color = "navy@.95" }, { id = "line", color = "cyan", alpha = 0.5 } } },
      titleIcon = { "icon", 12, 12, gap = 8 },
      sep = { header = { grad = { "HORIZONTAL", "cyan@.6", "cyan@0" } },
              block = { file = "line", tile = "H", color = "cyan@.3" } },
      leader = { color = "cyan@.24" },
      gauge = { w = 176, h = 6, gap = 2, outline = "ink@.6",
                colors = { world = "cyan", dungeon = "#a855f7", raid = "#818cf8", pvp = "#fb923c",
                           taxi = "#f472b6", afk = "#64748b", inn = "#fde68a", city = "#facc15" } },
    },
    ui = { bg = "navy", border = "cyan", title = "cyan", accent = "cyan", label = "label", value = "value",
           dim = "dim" },
  }
end

-- Engine only, with fixture themes under keys whose files are not loaded.
local function LoadEngine(opts)
  opts = opts or {}
  if opts.locale then Stub.locale = opts.locale end
  local ns = Load(ENGINE, opts.theme)
  local reg = opts.register or { futuriste = Fixture() }
  for key, src in pairs(reg) do
    ns.Themes.Register(key, function() return src end)
  end
  return ns
end

---------------------------------------------------------------------------
-- Setting (S1-S4)
---------------------------------------------------------------------------

T.test("theme setting: default futuriste, the 14 choices accepted, anything else refused", function()
  local ns = Load(CORE, nil)
  Stub.LoginSequence()
  local C, Core = ns.C, ns.Core
  T.eq(C.DEFAULTS.theme, "futuriste")
  T.eq(ns.settings.theme, "futuriste")
  T.eq(C.THEME_CHOICES, { "futuriste", "actuel", "heroic", "pixel", "class", "warrior", "paladin",
                          "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" })
  T.eq(C.CLASS_THEMES.MAGE, "mage")
  T.eq(C.CLASS_THEMES.DRUID, "druid")
  local changed = {}
  ns.RegisterMessage("SETTINGS_CHANGED", "test", function(_, path, v) changed[#changed + 1] = { path, v } end)
  for _, v in ipairs(C.THEME_CHOICES) do
    Core.SetSetting("theme", v)
    T.eq(ns.settings.theme, v, v)
    T.eq(Core.GetSetting("theme"), v)
  end
  T.eq(#changed, 13, "one SETTINGS_CHANGED per change (futuriste was already set)")
  T.eq(changed[1], { "theme", "actuel" })
  for _, bad in ipairs({ "foo", "Mage", "newtheme", "", 42, true, false, { "mage" } }) do
    T.no(Core.SetSetting("theme", bad), tostring(bad))
  end
  T.eq(ns.settings.theme, "druid", "unchanged by refused values")
end)

T.test("theme setting: repair keeps a plausible key of a newer version, drops anything else", function()
  local function Stored(v)
    Stub.Reset()
    _G.TruePlayedDB = { schema = 1, sparseSettings = true, settings = { theme = v } }
    local ns = Load(CORE, nil)
    Stub.LoginSequence()
    return ns.settings.theme
  end
  T.eq(Stored("newtheme"), "newtheme", "kept: written by a newer version")
  T.eq(Stored("mage"), "mage")
  T.eq(Stored("class"), "class")
  T.eq(Stored("new_theme_x"), "new_theme_x")
  T.eq(Stored(string.rep("a", 24)), string.rep("a", 24))
  T.eq(Stored(string.rep("a", 25)), "futuriste", "longer than 24")
  T.eq(Stored(42), "futuriste")
  T.eq(Stored("bad-key!"), "futuriste")
  T.eq(Stored("two words"), "futuriste")
  T.eq(Stored(""), "futuriste")
  T.eq(Stored({ "mage" }), "futuriste")
  T.eq(#Stub.errors, 0)
end)

T.test("theme setting: saved sparsely (the default is dropped, a choice kept) and reloaded", function()
  Load(CORE, nil)
  Stub.LoginSequence()
  Stub.Logout()
  T.eq(Stub.saved.settings.theme, nil, "futuriste = the default: not in the file")
  local ns = Stub.Restart({ files = CORE })
  T.ok(ns.Core.SetSetting("theme", "mage"))
  Stub.Logout()
  T.eq(Stub.saved.settings.theme, "mage")
  ns = Stub.Restart({ files = CORE })
  T.eq(ns.settings.theme, "mage")
  T.ok(ns.Core.SetSetting("theme", "class"))
  Stub.Logout()
  T.eq(Stub.saved.settings.theme, "class", "the setting value, never the resolved key")
end)

T.test("stub: Stub.theme is 'actuel' after Reset, written into the defaults by LoadAddon", function()
  T.eq(Stub.theme, "actuel")
  local ns = Stub.LoadAddon({ files = CORE })
  T.eq(ns.C.DEFAULTS.theme, "actuel", "legacy tests keep the classic look")
  Stub.LoginSequence()
  T.eq(ns.settings.theme, "actuel")
  Stub.Logout()
  T.eq(Stub.saved.settings.theme, nil, "equal to the (patched) default: not saved")
  ns = Stub.Restart({ files = CORE })
  T.eq(Stub.theme, "actuel", "kept by a keepWorld restart")
  T.eq(ns.C.DEFAULTS.theme, "actuel")
  Stub.Reset()
  Stub.theme = nil
  ns = Stub.LoadAddon({ files = CORE })
  T.eq(ns.C.DEFAULTS.theme, "futuriste", "nil = the real default")
  Stub.Reset()
  Stub.theme = "pixel"
  ns = Stub.LoadAddon({ files = CORE })
  T.eq(ns.C.DEFAULTS.theme, "pixel")
  Stub.Reset()
  T.eq(Stub.theme, "actuel", "Reset restores it")
  T.eq(Stub.created, { Texture = 0, MaskTexture = 0, FontString = 0, Frame = 0 })
  T.eq(#Stub.regions, 0)
  T.eq(Stub.calls.SetFont, 0)
  T.eq(Stub.missingFonts, {})
end)

---------------------------------------------------------------------------
-- Resolution and messages (S5-S7, 3.3)
---------------------------------------------------------------------------

T.test("Resolve: class theme, unknown class, unregistered key; actuel when futuriste is missing", function()
  local ns = Load(ThemeFiles(), nil)
  local Th = ns.Themes
  T.eq(Th.Resolve("class", "MAGE"), "mage")
  T.eq(Th.Resolve("class", "WARRIOR"), "warrior")
  T.eq(Th.Resolve("class", nil), "futuriste")
  T.eq(Th.Resolve("class", "DEATHKNIGHT"), "futuriste")
  T.eq(Th.Resolve("newtheme", "MAGE"), "futuriste")
  T.eq(Th.Resolve(nil, nil), "futuriste")
  T.eq(Th.Resolve("actuel", "MAGE"), "actuel")
  for _, k in ipairs(Th.KEYS) do
    if Th.IsRegistered(k) then T.eq(Th.Resolve(k, nil), k, k) end
  end
  -- futuriste not registered: actuel (always registered)
  Stub.Reset()
  ns = Load(ENGINE, nil)
  T.eq(ns.Themes.Resolve("futuriste", nil), "actuel")
  T.eq(ns.Themes.Resolve("class", "MAGE"), "actuel")
  Stub.LoginSequence()
  T.eq(ns.Themes.ActiveKey(), "actuel")
end)

T.test("Register: unknown keys, 'class' and duplicates are developer errors", function()
  local ns = LoadEngine()
  local Th = ns.Themes
  T.raises(function() Th.Register("class", function() return {} end) end)
  T.raises(function() Th.Register("nosuch", function() return {} end) end)
  T.raises(function() Th.Register("actuel", function() return {} end) end, "duplicate")
  T.raises(function() Th.Register("mage", "not a function") end)
  T.ok(Th.IsRegistered("actuel"))
  T.ok(Th.IsRegistered("futuriste"))
  T.no(Th.IsRegistered("mage"))
  T.eq(#Th.KEYS, 13)
end)

T.test("THEME_CHANGED: one per real change, none at DB_READY, none for class -> mage as a mage", function()
  local ns = LoadEngine({ register = { futuriste = Fixture(), mage = Fixture(), warrior = Fixture() } })
  local Th, Core = ns.Themes, ns.Core
  local got = Messages(ns)
  Stub.LoginSequence({ settle = 3 })
  local th = Th.Active()
  T.eq(th.key, "futuriste")
  Stub.Advance(5)
  T.eq(#got, 0, "none at DB_READY nor at the first resolution")
  T.ok(Th.Active() == th, "kept")

  Core.SetSetting("theme", "mage")
  T.eq(got, { { "mage", "futuriste", "theme" } })
  T.eq(Th.ActiveKey(), "mage")
  local mageTh = Th.Active()
  T.ok(mageTh ~= th and mageTh.gen > th.gen, "a new compile, a higher gen")
  Core.SetSetting("theme", "class")                     -- the player is a mage
  T.eq(#got, 1, "class -> mage for a mage: no message")
  T.eq(Th.Setting(), "class")
  T.ok(Th.Active() == mageTh, "not recompiled")
  Core.SetSetting("theme", "actuel")
  T.eq(got[2], { "actuel", "mage", "theme" })
  Core.SetSetting("theme", "newtheme")                  -- refused by SetSetting
  T.eq(#got, 2)
  Stub.player.class = "WARRIOR"
  Core.SetSetting("theme", "class")
  T.eq(got[3], { "warrior", "actuel", "theme" })
  Core.SetSetting("theme", "heroic")                    -- not registered here: futuriste
  T.eq(got[4], { "futuriste", "warrior", "theme" })
  T.eq(#got, 4)
  T.eq(#Stub.errors, 0)
end)

T.test("Active before DB_READY: resolved without a class and not kept; silent at the first call after", function()
  local ns = LoadEngine({ theme = "class", register = { futuriste = Fixture(), warrior = Fixture() } })
  Stub.player.class = "WARRIOR"
  local Th = ns.Themes
  local got = Messages(ns)
  T.eq(Th.ActiveKey(), "futuriste", "no class before DB_READY")
  T.eq(Th.Setting(), "class")
  Stub.LoginSequence()
  T.eq(Th.ActiveKey(), "warrior", "resolved again with the class")
  T.eq(#got, 0, "silent")
  T.eq(#Stub.errors, 0)
end)

-- Themes.Active(): the same key, but user colours that changed without SETTINGS_CHANGED
-- (here: the saved settings adopted at ADDON_LOADED, after an early Active() call): the
-- active theme is recoloured in place, silently.
T.test("Active: user colours changed behind Themes' back are applied silently, in place (same table, gen up)", function()
  local ns = LoadEngine({ theme = "actuel" })
  local Th = ns.Themes
  local got = Messages(ns)
  local th = Th.Active()                            -- before ADDON_LOADED: the defaults
  T.eq(th.key, "actuel")
  local fill = Layer(th, "fill")
  local c1, gen = fill.c[1], th.gen
  T.eq(R3(c1), R3(ns.C.COLORS.fill), "the theme's own XP colour")
  _G.TruePlayedDB = { schema = 1, sparseSettings = true,
                      settings = { theme = "actuel", widget = { xpColor = { 0, 1, 0 } } } }
  Stub.LoginSequence()
  T.ok(Th.Active() == th, "the same compiled theme")
  T.ok(fill.c[1] == c1, "the same colour array")
  T.eq(R3(c1), { 0, 1000, 0, 1000 }, "rewritten with the saved XP colour")
  T.ok(th.gen > gen, "a higher gen (the engines redraw)")
  local gen2 = th.gen
  T.ok(Th.Active() == th and th.gen == gen2, "kept: no second recolour")
  T.eq(#got, 0, "silent: no THEME_CHANGED")
  T.eq(#Stub.errors, 0)
end)

T.test("DB_SWAPPED: another theme sends THEME_CHANGED once; other user colours a recolour", function()
  local ns = LoadEngine()
  local Th = ns.Themes
  Stub.LoginSequence()
  local got = Messages(ns)
  Th.Active()
  _G.TruePlayedDB = { schema = 1, sparseSettings = true, settings = { theme = "actuel" } }
  Stub.Advance(1)
  T.eq(got, { { "actuel", "futuriste", "theme" } })
  T.eq(Th.ActiveKey(), "actuel")
  local th = Th.Active()
  local fill = Layer(th, "fill")
  _G.TruePlayedDB = { schema = 1, sparseSettings = true,
                      settings = { theme = "actuel", widget = { xpColor = { 0, 1, 0 } } } }
  Stub.Advance(1)
  T.eq(got[2], { "actuel", "actuel", "colors" })
  T.eq(R3(fill.c[1]), { 0, 1000, 0, 1000 })
  _G.TruePlayedDB = { schema = 1, sparseSettings = true,
                      settings = { theme = "actuel", widget = { xpColor = { 0, 1, 0 } } } }
  Stub.Advance(1)
  T.eq(#got, 2, "same theme, same colours: nothing")
  T.eq(#Stub.errors, 0)
end)

---------------------------------------------------------------------------
-- In-place recolour (2.3, S7)
---------------------------------------------------------------------------

T.test("Recolor: xpColor / restedColor give 'colors', gen + 1 and the same tables, rewritten", function()
  local ns = LoadEngine()
  local Th, Core = ns.Themes, ns.Core
  Stub.LoginSequence()
  local got = Messages(ns)
  local th = Th.Active()
  local fill, glow, marker, rested = Layer(th, "fill"), Layer(th, "glow"), Layer(th, "marker"), Layer(th, "rested")
  local c1, c2 = fill.c[1], fill.c[2]
  local hot, layers, g1 = th.text.colors.marker, th.bar.layers, rested.g
  local gen = th.gen
  T.eq(R3(c1), R3(Hex("#ff2bd6")), "theme xp")
  T.eq(R3(c2), R3(Hex("#22d3ee")), "theme rested")
  T.eq(fill.c[3], nil, "state 2 has no colour of its own: state 0 with bar.maxAlpha")
  T.eq(R3(TV.Color(th, fill, 2)), R3({ c1[1], c1[2], c1[3], 0.35 }), "max level: dimmed")

  T.ok(Core.SetSetting("widget.xpColor", { 0, 1, 0 }))
  T.eq(got, { { "futuriste", "futuriste", "colors" } })
  T.eq(th.gen, gen + 1)
  T.ok(Th.Active() == th, "same compiled theme")
  T.ok(fill.c[1] == c1 and fill.c[2] == c2 and fill.c[3] == nil and th.bar.layers == layers, "same tables")
  T.ok(th.text.colors.marker == hot and rested.g == g1)
  T.eq(R3(c1), { 0, 1000, 0, 1000 })
  T.eq(c1[1], 0); T.eq(c1[2], 1); T.eq(c1[4], 1)
  T.eq(R3(TV.Color(th, fill, 2)), { 0, 1000, 0, 350 })
  T.eq(R3(c2), R3(Hex("#22d3ee")), "rested state unchanged")
  T.eq(R3(hot), R3(Lighten({ 0, 1, 0, 1 }, 0.45)), "named colour using xp follows")
  T.eq(R3(glow.c[1]), { 0, 1000, 0, 550 })
  T.eq(R3(TV.Color(th, glow, 2)), { 0, 1000, 0, math.floor(0.55 * 0.35 * 1000 + 0.5) })
  T.eq(R3(marker.c[1]), R3(Lighten({ 0, 1, 0, 1 }, 0.85)))
  T.eq(R3(th.text.colors.label), R3(Hex("#a3bfcf")), "a static colour keeps its value (written once)")
  T.eq(R3(th.colors.xp), R3(Hex("#ff2bd6")), "th.colors: the theme default, before the override")
  T.eq(R3(Th.DefaultColor("xp")), R3(Hex("#ff2bd6")))

  T.ok(Core.SetSetting("widget.restedColor", { r = 1, g = 0, b = 0 }))
  T.eq(got[2], { "futuriste", "futuriste", "colors" })
  T.eq(th.gen, gen + 2)
  T.eq(R3(c2), { 1000, 0, 0, 1000 })
  local from1, to1 = TV.Pair(th, rested, 1)
  T.eq(R3(from1), R3({ 1, 0.5, 0.5, 0.62 }), "rested+.5@.62")
  T.eq(R3(to1), R3({ 1, 0.5, 0.5, 0 }))
  -- a sub-path (a single component written by another version) is a colour path too
  ns.SendMessage("SETTINGS_CHANGED", "widget.restedColor.2", 0.5)
  T.eq(#got, 3)
  T.ok(Core.SetSetting("widget.xpColor", false))
  T.ok(Core.SetSetting("widget.restedColor", false))
  T.eq(R3(c1), R3(Hex("#ff2bd6")), "back to the theme colours")
  T.eq(R3(c2), R3(Hex("#22d3ee")))
  T.eq(#got, 5)
  -- other paths: nothing
  Core.SetSetting("widget.width", 400)
  Core.SetSetting("widget.textColor", { 1, 1, 0 })
  T.eq(#got, 5)
end)

T.test("Recolor allocates nothing (numbers rewritten in place)", function()
  local ns = LoadEngine()
  Stub.LoginSequence()
  ns.Core.SetSetting("widget.xpColor", { 0.2, 0.4, 0.6 })
  local Th = ns.Themes
  Th.Active()
  Th.Recolor()
  local kb = T.alloc(function() Th.Recolor() end, 200)
  T.ok(kb < 0.01, string.format("Recolor allocated %.3f KB over 200 calls", kb))
end)

-- tt.colors.ccDim (the colour code of the tooltip's estimate tag) follows a recolour
-- whenever tt.colors.dim does: also for a static colour whose `def` reads a user colour
-- (the def is what is drawn while the colour itself never reads one).
T.test("Recolor: ccDim follows a tooltip dim that changes through its def", function()
  local src = Fixture()
  src.tooltip.colors.dim = { "#d02f0a", def = "rested+.5" }
  local ns = LoadEngine({ register = { futuriste = Fixture(), mage = src } })
  local Th, Core = ns.Themes, ns.Core
  Stub.LoginSequence()
  Core.SetSetting("theme", "mage")
  local th = Th.Active()
  T.eq(th.key, "mage")
  local P = th.tt.colors
  local function Code(c)
    local function B(x) return math.floor(x * 255 + 0.5) end
    return string.format("|cff%02x%02x%02x", B(c[1]), B(c[2]), B(c[3]))
  end
  local theme = Code(Lighten(Hex("#22d3ee"), 0.5))
  T.eq(P.ccDim, theme, "the def with the theme's rested colour")
  T.ok(Core.SetSetting("widget.restedColor", { 1, 0, 0 }))
  T.eq(R3(P.dim), { 1000, 500, 500, 1000 }, "dim rewritten (rested+.5)")
  T.eq(P.ccDim, "|cffff8080", "ccDim follows")
  T.ok(Core.SetSetting("widget.restedColor", false))
  T.eq(P.ccDim, theme, "back to the theme's")
  -- a dim that never changes is left alone
  Core.SetSetting("theme", "futuriste")
  local cc = Th.Active().tt.colors.ccDim
  T.ok(Core.SetSetting("widget.restedColor", { 1, 0, 0 }))
  T.eq(Th.Active().tt.colors.ccDim, cc)
  T.eq(#Stub.errors, 0)
end)

T.test("def: the hand-tuned colour while the user keeps the theme's own (actuel rested part)", function()
  local ns = LoadEngine({ theme = "actuel" })
  Stub.LoginSequence()
  local Th, Core, C = ns.Themes, ns.Core, ns.C
  local th = Th.Active()
  T.eq(th.key, "actuel")
  local rested, tick = Layer(th, "rested"), Layer(th, "restTick")
  -- the rested part does not follow the fill state: one pair { from, to } and one flat colour
  T.eq(R3(rested.g[1]), R3({ 0.35, 0.62, 1.0, 0.65 }))
  T.eq(R3(rested.g[2]), R3({ 0.35, 0.62, 1.0, 0.20 }))
  T.eq(R3(rested.f), R3({ 0.35, 0.62, 1.0, 0.40 }))
  T.eq(R3(tick.c), R3(C.COLORS.restTick))
  T.ok(Core.SetSetting("widget.restedColor", { 0.1, 0.7, 0.2 }))
  local u = { 0.1, 0.7, 0.2, 1 }
  local function L(k, a) local c = Lighten(u, k); c[4] = a; return R3(c) end
  T.eq(R3(rested.g[1]), L(0.35, 0.65), "rested+.35@.65")
  T.eq(R3(rested.g[2]), L(0.35, 0.20))
  T.eq(R3(rested.f), L(0.35, 0.40))
  T.eq(R3(tick.c), L(0.6, 0.9))
  -- exactly the legacy arithmetic (Bar.lua Lighten): x + (1 - x) * k
  T.eq(rested.g[1][2], 0.7 + (1 - 0.7) * 0.35)
  T.ok(Core.SetSetting("widget.xpColor", { 0.9, 0.9, 0.1 }))
  T.eq(R3(rested.g[1]), L(0.35, 0.65), "the xp colour does not matter to the rested part")
  T.ok(Core.SetSetting("widget.restedColor", false))
  T.eq(R3(rested.g[1]), R3({ 0.35, 0.62, 1.0, 0.65 }), "def again")
end)

---------------------------------------------------------------------------
-- Compiled form (2.8)
---------------------------------------------------------------------------

T.test("Compile is pure and gives the 2.8 form (kinds, spans, dyn, per-state colours, textures)", function()
  local ns = LoadEngine()
  Stub.LoginSequence()
  local Th = ns.Themes
  T.eq(Th.ActiveKey(), "futuriste")
  local th, warnings = Th.Compile("actuel")
  T.eq(warnings, {})
  T.eq(Th.ActiveKey(), "futuriste", "the active theme is left alone")
  T.eq(th.key, "actuel")
  T.ok(th.native)
  T.ok(th.tt.native and th.tt.colors == Th.CLASSIC_TT, "native tooltip: the classic palette itself")
  T.eq({ th.fonts.display, th.fonts.body, th.fonts.num }, { "game", "game", "game" })
  T.eq(rawget(th.fonts, "num"), nil, "num = body: not stored (the default)")
  T.eq(th.bar.panel, "backdrop")
  T.eq({ th.bar.pad, th.bar.gap, th.bar.hAdd, th.bar.hMin }, { 8, 3, 0, 4 })
  local ids = {}
  for i, Lc in ipairs(th.bar.layers) do ids[i] = Lc.id .. ":" .. Lc.kind .. ":" .. Lc.span end
  T.eq(ids, { "track:caps:track", "rested:tex:rested", "fill:caps:fill", "fillHi:tex:fill", "restTick:tex:restEnd" })
  local fill, hi, track = Layer(th, "fill"), Layer(th, "fillHi"), Layer(th, "track")
  T.ok(fill.dyn and not hi.dyn and not track.dyn)
  T.ok(type(track.c[1]) == "number", "static, maxAlpha 1: one colour")
  T.ok(TV.Color(th, track, 1) == track.c and TV.Color(th, track, 2) == track.c, "the same table in every state")
  T.ok(type(hi.c[1]) == "number" and TV.Color(th, hi, 1) == hi.c, "static fill layer: one colour, states 0 and 1")
  T.no(TV.Same(R3(TV.Color(th, hi, 2)), R3(hi.c), ""), "static fill layer: state 2 differs (maxAlpha)")
  T.eq(R3(TV.Color(th, hi, 2)), { 1000, 1000, 1000, 35 })
  T.ok(fill.c[1] ~= fill.c[2] and not TV.Same(R3(fill.c[2]), R3(TV.Color(th, fill, 2)), ""), "three states")
  T.eq(fill.tex.path, ns.C.TEX_WHITE)
  T.eq({ fill.layer, fill.sub, fill.tex.blend }, { "ARTWORK", 2, "BLEND" })
  T.eq({ hi.top, hi.h, hi.bottom, hi.capInset }, { 0, 1, 0, true })
  local tick = Layer(th, "restTick")
  T.eq({ tick.w, tick.align, tick.dx }, { 1, "right", 0 })
  T.eq(th.text.font.s1, "body")
  local size = { s1 = 2, s2 = 0, s3 = -1, level = 0, levelValue = 0, xpLabel = 0, xp = 0, sep = 0,
                 marker = -1, hint = -1 }
  for e, v in pairs(size) do T.eq(th.text.size[e], v, "text.size." .. e) end
  T.eq(next(th.text.size), nil, "the defaults: nothing stored")
  T.eq({ th.text.split, th.text.splitGap, th.text.levelFmt }, { false, 4, "upper" })
  T.eq(R3(th.text.shadow.c), { 0, 0, 0, 800 })
  T.eq({ th.text.shadow.x, th.text.shadow.y }, { 1, -1 })
  local K = ns.C.COLORS
  T.eq(R3(th.text.colors.label), R3(K.label)); T.eq(R3(th.text.colors.value), R3(K.value))
  T.eq(R3(th.text.colors.dimmed), R3(K.dim)); T.eq(R3(th.text.colors.xpText), R3(K.label))
  T.eq(R3(th.accent), R3(K.accent))
  T.eq(R3(th.ui.bg), R3(K.bg)); T.eq(R3(th.ui.border), R3(K.border)); T.eq(R3(th.ui.title), R3(K.value))
  T.eq(R3(th.colors.xp), R3(K.fill)); T.eq(R3(th.colors.rested), R3(K.restedFill))
  T.eq(R3(th.colors.bg), R3(K.bg), "the whole palette is exposed (backdrop colours)")
  -- compiled colours are plain rgba arrays: the 4 numbers and nothing else
  for _, c in ipairs({ th.text.colors.label, th.accent, th.ui.bg, Layer(th, "track").c }) do
    local keys = 0
    for _ in pairs(c) do keys = keys + 1 end
    T.eq(keys, 4)
    for i = 1, 4 do T.eq(type(c[i]), "number") end
  end
end)

T.test("Compile: fixture features (three, nine, tile, ticks, anchors, panel parts, tooltip, text)", function()
  local ns = LoadEngine()
  local Th = ns.Themes
  local th, warnings = Th.Compile("futuriste")
  T.eq(warnings, {})
  T.eq({ th.bar.pad, th.bar.gap, th.bar.hAdd, th.bar.hMin }, { 10, 4, 6, 10 })
  T.eq({ th.fonts.display, th.fonts.body, th.fonts.num }, { "Orbitron", "Rajdhani", "Rajdhani" })
  T.eq(rawget(th.fonts, "num"), nil, "num = body: not stored")
  local glow = Layer(th, "glow")
  T.eq(glow.kind, "three")
  T.eq(glow.tex.slice, { 16, 8 })
  T.eq(glow.tex.path, "Interface\\AddOns\\TruePlayed\\Media\\Themes\\common\\glow.tga")
  T.eq({ glow.tex.w, glow.tex.h, glow.tex.blend }, { 64, 32, "ADD" })
  T.eq(rawget(glow, "blend"), nil, "the blend mode lives in the texture spec only")
  T.eq(glow.pad, { 8, 8 })
  T.ok(glow.dyn)
  local frame = Layer(th, "frame")
  T.eq(frame.kind, "nine")
  T.eq(frame.tex.path, "Interface\\AddOns\\TruePlayed\\Media\\Themes\\futuriste\\frame.tga")
  local line = Layer(th, "line")
  T.eq(line.tex.tile, "H")
  local probe = CreateFrame("Frame"):CreateTexture()
  Th.SetTex(probe, line.tex)
  T.eq({ probe._wrapH, probe._wrapV }, { "REPEAT", "CLAMP" }, "wrap modes of tile H")
  local ticks, segs = Layer(th, "ticks"), Layer(th, "segs")
  T.eq({ ticks.ticks.n, ticks.ticks.w, ticks.ticks.clip, ticks.ticks.mid }, { 10, 1 })
  T.eq({ segs.ticks.n, segs.ticks.w, segs.ticks.clip, segs.ticks.mid }, { 10, 1, "fill" })
  T.eq(R3(segs.c), { 4, 16, 43, 250 }, "colour alpha x layer alpha")
  T.ok(TV.Color(th, segs, 2) == segs.c, "span track: no maxAlpha")
  local bracket = Layer(th, "bracket")
  T.ok(bracket.tex.flipX)
  probe = CreateFrame("Frame"):CreateTexture()
  Th.SetTex(probe, bracket.tex)
  T.eq(probe._tc, { 1, 0, 0, 1 }, "flipX")
  T.eq({ bracket.w, bracket.align, bracket.dx, bracket.span }, { 8, "left", 2, "trackEnd" })
  local marker = Layer(th, "marker")
  local m3 = Lighten(Hex("#ff2bd6"), 0.85)
  m3[4] = 0.35
  T.eq(R3(TV.Color(th, marker, 2)), R3(m3), "fillEnd: bar.maxAlpha in state 2")
  local band = Layer(th, "band")
  T.eq(band.band, { 0, 0.28 })
  T.eq(band.g.dir, "VERTICAL")
  local f0, t0 = TV.Pair(th, band, 0)
  local f1, t1 = TV.Pair(th, band, 1)
  local f2 = TV.Pair(th, band, 2)
  T.ok(f0 == band.g[1] and t0 == band.g[2] and f1 == f0 and t1 == t0 and R3(f2)[4] ~= R3(f0)[4],
    "static pair; state 2 dimmed")
  T.ok(band.f == nil and R3(TV.Flat(th, band, 0))[4] == 120, "flat defaults to from")
  local track = Layer(th, "track")
  T.eq(R3(track.f), R3({ 7 / 255, 13 / 255, 26 / 255, 0.9 }))
  local rested = Layer(th, "rested")
  T.ok(#rested.g[1] == 4 and rested.g.dir == "HORIZONTAL", "pairs carry dir, colours are rgba arrays")
  -- panel parts: a numeric alpha folded into c, "bg" kept
  local parts = th.bar.panel.parts
  T.eq({ parts[1].id, parts[1].alpha, TV.PartSub(parts[1], 1), parts[1].anchor, parts[1].layer }, { "panelFill", "bg", -8, "FILL", "BACKGROUND" })
  T.eq(parts[1].inset, nil, "no inset: 0 on every side (the readers' default)")
  T.eq({ parts[2].alpha, TV.PartSub(parts[2], 2), parts[2].x, parts[2].y, parts[2].w, parts[2].h }, { 1, -7, 15, 0, 96, 2 })
  T.eq(R3(parts[2].c)[4], 500)
  -- text
  T.eq(th.text.font.level, "display"); T.eq(th.text.font.xp, "num"); T.eq(th.text.font.s2, "body")
  T.eq(th.text.size.s1, 3); T.eq(th.text.size.s2, 0); T.eq(th.text.size.hint, 0)
  T.eq({ th.text.split, th.text.splitGap }, { true, 5 })
  T.eq(R3(th.text.shadow.c), R3({ 0.004, 0.016, 0.043, 0.85 }))
  -- tooltip
  local tt = th.tt
  T.no(tt.native)
  T.eq({ tt.width[1], tt.width[2] }, { 280, 440 })
  T.eq({ tt.pad[1], tt.pad[2], tt.pad[3], tt.pad[4] }, { 12, 12, 10, 10 })
  T.eq({ tt.gap, tt.lineGap }, { 8, 3 })
  T.eq(tt.fonts.value, nil, "value defaults to body (readers: fonts.value or fonts.body)")
  T.eq(tt.fonts.body, { "body", 15 })
  T.eq(tt.fonts.title, { "display", 13 })
  T.eq(R3(tt.colors.mode), R3(Hex("#a3bfcf")), "mode defaults to label")
  T.eq(R3(tt.colors.header), R3(Hex("#22d3ee")), "header defaults to accent")
  T.eq(R3(tt.colors.pause), R3(ns.C.COLORS.pause), "pause defaults to C.COLORS.pause")
  T.eq(tt.colors.ccDim, "|cff7f96a9")
  T.eq(R3(tt.colors.levelValue), R3(Lighten(Hex("#ff2bd6"), 0.45)))
  T.eq(#tt.panel.parts, 2)
  T.eq(R3(tt.panel.parts[2].c)[4], 500)
  T.eq({ tt.titleIcon.w, tt.titleIcon.h, tt.titleIcon.gap }, { 12, 12, 8 })
  T.eq(tt.sep.header.g.dir, "HORIZONTAL")
  T.eq({ tt.sep.header.h, tt.sep.header.above, tt.sep.header.below, tt.sep.header.mirror }, { 1, 6, 5, false })
  T.eq(tt.sep.block.tex.tile, "H")
  T.eq(tt.sep.footer, nil, "a missing kind: blank space (TooltipFrame)")
  T.eq({ tt.leader.h, tt.leader.y, tt.leader.min, tt.leader.tex.tile }, { 1, 3, 12, "H" })
  T.eq({ tt.gauge.w, tt.gauge.h, tt.gauge.gap }, { 176, 6, 2 })
  T.eq(R3(tt.gauge.colors.city), R3(Hex("#facc15")))
  T.eq(R3(tt.gauge.outline)[4], 600)
end)

T.test("Compile warnings: unknown fields, bad colours, base outside layers, cycles, media, fonts", function()
  local bad = Fixture({ display = "Orbitron", body = "Orbitron", num = "NoSuchFont" })
  bad.extra = 1
  bad.colors.loopA = "loopB"
  bad.colors.loopB = "loopA"
  bad.colors.deep1, bad.colors.deep2, bad.colors.deep3 = "deep2", "deep3", "deep4"
  bad.colors.deep4, bad.colors.deep5, bad.colors.deep6 = "deep5", "deep6", "#ffffff"
  bad.colors.useDeep = "deep1"
  bad.colors.usesBase = "base+.2"
  bad.colors.badHex = "#12345"
  bad.colors.badMod = "#123456@.5+.2"
  bad.colors.badRange = "#123456+2"
  bad.bar.layers[#bad.bar.layers + 1] = { id = "fill", file = "nosuch", sub = 9, span = "middle", wat = 1 }
  bad.bar.layers[#bad.bar.layers + 1] = { id = "end", span = "fillEnd" }
  bad.text.font.s1 = "display"
  bad.text.colors.label = "base"
  bad.tooltip.colors.dim = "unknownColour"
  bad.ui.title = nil
  local ns = LoadEngine({ register = { futuriste = Fixture(), mage = bad } })
  local _, warnings = ns.Themes.Compile("mage")
  local all = table.concat(warnings, "\n")
  local expect = {
    "theme: unknown field 'extra'",
    "fonts.body: Orbitron is a display%-only font",
    "fonts.num: unknown font 'NoSuchFont'",
    "colour cycle",
    "nested more than 4 deep",
    "colors.usesBase: 'base' is only valid in bar.layers",
    "colors.badHex",
    "'@' must come last",
    "colors.badRange: bad modifier",
    "duplicate id",
    "media 'nosuch' is not declared",
    "layer 'fill'.sub: invalid number 9",
    "layer 'fill'.span: invalid value middle",
    "unknown field 'wat'",
    "anchor span 'fillEnd' needs a width w",
    "text.font.s1: shows arbitrary text",
    "text.colors.label: 'base' is only valid in bar.layers",
    "unknown colour 'unknownColour'",
    "ui.title is required",
  }
  for _, pattern in ipairs(expect) do
    T.ok(all:find(pattern) ~= nil, "warning '" .. pattern .. "' in:\n" .. all)
  end
  for _, w in ipairs(warnings) do T.match(w, "^mage: ", "warnings name the theme") end
  -- a builder that fails or returns nothing: no theme, a warning, no error
  ns.Themes.Register("pixel", function() error("boom") end)
  local th, w2 = ns.Themes.Compile("pixel")
  T.eq(th, nil)
  T.match(w2[1], "builder failed")
  T.eq(ns.Themes.Compile("nosuch"), nil)
  T.eq(#Stub.errors, 0)
end)

T.test("Active falls back to futuriste, then actuel, when a theme cannot be built", function()
  local ns = LoadEngine({ register = { futuriste = Fixture(), mage = 42 } })
  Stub.LoginSequence()
  local got = Messages(ns)
  ns.Themes.Active()
  ns.Core.SetSetting("theme", "mage")
  T.eq(ns.Themes.ActiveKey(), "futuriste")
  T.eq(#got, 0, "the resolved key did not really change")
  T.eq(#Stub.errors, 0)
end)

T.test("CLASSIC_TT: the classic palette from C.COLORS, ccDim = C.CC.dim exactly", function()
  local ns = LoadEngine()
  local P, K = ns.Themes.CLASSIC_TT, ns.C.COLORS
  T.eq(P.ccDim, ns.C.CC.dim)
  local expect = { title = K.accent, mode = K.label, label = K.label, value = K.value, dim = K.dim,
                   header = K.accent, pause = K.pause, hint = K.dim, levelLabel = K.label,
                   levelValue = K.value, levelValueRested = K.value, rested = K.value }
  for role, c in pairs(expect) do
    T.eq({ P[role][1], P[role][2], P[role][3], P[role][4] }, { c[1], c[2], c[3], c[4] or 1 }, role)
    local keys = 0
    for _ in pairs(P[role]) do keys = keys + 1 end
    T.eq(keys, 4, role .. ": a plain rgba array")
  end
end)

---------------------------------------------------------------------------
-- Fonts (2.6, 3.2)
---------------------------------------------------------------------------

local function FontFixtures()
  return {
    futuriste = Fixture({ display = "Orbitron", body = "Rajdhani" }),
    heroic = Fixture({ display = "Cinzel", body = "EBGaramond", num = "Rajdhani" }),
    pixel = Fixture({ display = "PressStart2P", body = "PixelifySans" }),
    mage = Fixture({ display = "Macondo", body = "Spectral" }),
  }
end

T.test("Font: theme fonts, ruRU keeps Cyrillic fonts only, CJK clients use the game font", function()
  local ns = LoadEngine({ register = FontFixtures() })
  Stub.LoginSequence()
  local Th, F = ns.Themes, ns.Themes.FONTS
  T.eq({ Th.Font("body", 12) }, { F.Rajdhani.path, 12, false })
  T.eq(F.Rajdhani.path, "Interface\\AddOns\\TruePlayed\\Media\\Fonts\\Rajdhani-SemiBold.ttf")
  T.eq({ Th.Font("display", 12.4) }, { F.Orbitron.path, 12, false })
  T.eq({ Th.Font("num", 12.6) }, { F.Rajdhani.path, 13, false }, "num defaults to body")
  T.eq({ Th.Font("game", 12) }, { GAME, 12, false })
  Stub.locale = "ruRU"
  T.eq(Th.Font("body", 12), GAME, "Rajdhani has no Cyrillic")
  T.eq(Th.Font("display", 12), GAME)
  ns.Core.SetSetting("theme", "heroic")
  T.eq(Th.Font("body", 12), F.EBGaramond.path, "EBGaramond covers Cyrillic")
  T.eq(Th.Font("num", 12), GAME, "Rajdhani as num: game")
  T.eq(Th.Font("display", 12), GAME, "Cinzel: game")
  for _, loc in ipairs({ "zhCN", "zhTW", "koKR" }) do
    Stub.locale = loc
    T.eq(Th.Font("body", 12), GAME, loc)
    T.eq(Th.Font("display", 12), GAME, loc)
  end
  Stub.locale = "frFR"
  T.eq(Th.Font("body", 12), F.EBGaramond.path)
  STANDARD_TEXT_FONT = "Fonts\\ARIALN.TTF"
  T.eq(Th.Font("game", 12), "Fonts\\ARIALN.TTF", "STANDARD_TEXT_FONT read at call time")
end)

T.test("Font: PressStart2P sizes snap to 8 / 16 (min 8, max 16), MONOCHROME flags", function()
  local ns = LoadEngine({ theme = "pixel", register = FontFixtures() })
  Stub.LoginSequence()
  local Th, path = ns.Themes, ns.Themes.FONTS.PressStart2P.path
  T.eq({ Th.Font("display", 11) }, { path, 8, true })
  T.eq({ Th.Font("display", 13) }, { path, 16, true })
  T.eq({ Th.Font("display", 12) }, { path, 16, true })
  T.eq({ Th.Font("display", 4) }, { path, 8, true }, "min")
  T.eq({ Th.Font("display", 30) }, { path, 16, true }, "max")
  T.eq({ Th.Font("body", 11) }, { Th.FONTS.PixelifySans.path, 11, false })
  local fs = CreateFrame("Frame"):CreateFontString()
  Th.SetFont(fs, "display", 11, "thin")
  T.eq({ fs:GetFont() }, { path, 8, "MONOCHROME,OUTLINE" })
  Th.SetFont(fs, "display", 11, "none")
  T.eq(select(3, fs:GetFont()), "MONOCHROME")
  Th.SetFont(fs, "display", 11, "thick")
  T.eq(select(3, fs:GetFont()), "MONOCHROME,THICKOUTLINE")
  Th.SetFont(fs, "body", 11, "thick")
  T.eq(select(3, fs:GetFont()), "THICKOUTLINE")
  Th.SetFont(fs, "body", 11, "none")
  T.eq(select(3, fs:GetFont()), "")
  Th.SetFont(fs, "body", 11, nil)
  T.eq(select(3, fs:GetFont()), "OUTLINE", "anything else = thin, as Bar")
end)

T.test("SetFont: one probe, then the game call only when path, size or flags change", function()
  local ns = LoadEngine({ register = FontFixtures() })
  Stub.LoginSequence()
  local Th = ns.Themes
  local f = CreateFrame("Frame")
  local a, b = f:CreateFontString(), f:CreateFontString()
  local calls = Stub.calls
  T.eq(calls.SetFont, 0)
  T.eq(Th.SetFont(a, "body", 12, "thin"), Th.FONTS.Rajdhani.path)
  T.eq(calls.SetFont, 2, "the probe (game font, 12, \"\") then the font")
  T.eq({ a:GetFont() }, { Th.FONTS.Rajdhani.path, 12, "OUTLINE" })
  Th.SetFont(a, "body", 12, "thin")
  Th.SetFont(a, "body", 12.2, "thin")
  T.eq(calls.SetFont, 2, "same path, size and flags: skipped")
  Th.SetFont(b, "body", 12, "thin")
  T.eq(calls.SetFont, 3, "another FontString: its own cache, no second probe")
  Th.SetFont(a, "body", 13, "thin")
  Th.SetFont(a, "body", 13, "thick")
  Th.SetFont(a, "display", 13, "thick")
  T.eq(calls.SetFont, 6)
  ns.Core.SetSetting("theme", "heroic")
  Th.SetFont(a, "display", 13, "thick")
  T.eq(calls.SetFont, 7, "a theme switch changes the path")
  T.eq(a:GetFont(), Th.FONTS.Cinzel.path)
  local kb = T.alloc(function() Th.SetFont(a, "display", 13, "thick") end, 500)
  T.ok(kb < 0.01, string.format("steady SetFont allocated %.3f KB", kb))
end)

T.test("missing font file: game font instead, one message per session, entry marked", function()
  local ns = LoadEngine({ register = FontFixtures() })
  Stub.LoginSequence()
  local Th = ns.Themes
  Stub.missingFonts[Th.FONTS.Rajdhani.path] = true
  Stub.missingFonts[Th.FONTS.Orbitron.path] = true
  local f = CreateFrame("Frame")
  local a, b, c = f:CreateFontString(), f:CreateFontString(), f:CreateFontString()
  local n0 = #Stub.printed
  T.eq(Th.SetFont(a, "body", 12, "thin"), GAME)
  T.eq({ a:GetFont() }, { GAME, 12, "OUTLINE" })
  T.ok(Th.FONTS.Rajdhani.missing)
  T.eq(#Stub.printed, n0 + 1)
  T.ok(Stub.printed[#Stub.printed]:find(ns.L.CHAT_PREFIX, 1, true) == 1)
  T.ok(Stub.printed[#Stub.printed]:find("Rajdhani-SemiBold.ttf", 1, true) ~= nil, "names the file")
  T.eq(Th.Font("body", 12), GAME, "resolution skips the missing entry")
  Th.SetFont(b, "body", 12, "thin")
  Th.SetFont(c, "display", 12, "thin")                 -- another missing file
  T.eq(c:GetFont(), GAME)
  T.eq(#Stub.printed, n0 + 1, "one message per session")
  T.eq(#Stub.errors, 0)
end)

T.test("missing font: no detection when the game font itself does not report success (K7)", function()
  local ns = LoadEngine({ register = FontFixtures() })
  Stub.LoginSequence()
  local Th = ns.Themes
  Stub.missingFonts[GAME] = true                         -- the probe fails
  Stub.missingFonts[Th.FONTS.Rajdhani.path] = true
  local fs = CreateFrame("Frame"):CreateFontString()
  T.eq(Th.SetFont(fs, "body", 12, "thin"), Th.FONTS.Rajdhani.path)
  T.no(Th.FONTS.Rajdhani.missing)
  T.eq(#Stub.printed, 0)
end)

T.test("Subst: Orbitron and Macondo replacements; the same string, without allocation, otherwise", function()
  local ns = LoadEngine({ register = FontFixtures() })
  Stub.LoginSequence()
  local Th = ns.Themes
  T.ok(Th.HasSubst("display"))
  T.no(Th.HasSubst("body"))
  T.no(Th.HasSubst("game"))
  T.eq(Th.Subst("display", "LEVEL 12 \194\183 45.2%"), "LEVEL 12 \226\128\162 45.2%")
  T.eq(Th.Subst("display", "\194\171a\194\187 \194\171b\194\187"), "\"a\" \"b\"")
  local s = "LEVEL 12"
  T.ok(rawequal(Th.Subst("display", s), s))
  T.ok(rawequal(Th.Subst("body", "a \194\183 b"), "a \194\183 b"), "Rajdhani: no replacement")
  T.eq(Th.Subst("display", nil), nil)
  local kb = T.alloc(function() Th.Subst("display", s) end, 1000)
  T.eq(kb, 0, "no allocation when nothing matches")
  kb = T.alloc(function() Th.HasSubst("display") end, 1000)
  T.eq(kb, 0)
  ns.Core.SetSetting("theme", "mage")
  T.ok(Th.HasSubst("display"), "Macondo")
  T.eq(Th.Subst("display", "1\194\160234"), "1 234", "NBSP")
  Stub.locale = "ruRU"
  T.no(Th.HasSubst("display"), "game font in ruRU: nothing to replace")
end)

T.test("FONTS: the 23 bundled fonts with their files, Cyrillic flags and size rules", function()
  local ns = LoadEngine()
  local F = ns.Themes.FONTS
  local n = 0
  for name, e in pairs(F) do
    n = n + 1
    T.eq(e.name, name)
    T.match(e.file, "^[%w]+%-[%w]+%.ttf$", name)
    T.eq(e.path, "Interface\\AddOns\\TruePlayed\\Media\\Fonts\\" .. e.file)
    T.eq(type(e.cyr), "boolean")
  end
  T.eq(n, 23)
  T.eq({ F.PressStart2P.min, F.PressStart2P.snap, F.PressStart2P.max, F.PressStart2P.mono }, { 8, 8, 16, true })
  T.ok(F.EBGaramond.cyr and not F.Rajdhani.cyr and F.Spectral.cyr)
  T.eq(#ns.Themes.DISPLAY_KEYS, 13)
  T.eq(ns.Themes.COMMON_MEDIA.glow, { 64, 32, grey = true })
  T.eq(ns.Themes.GAME_FONT_FALLBACK, GAME)
end)

---------------------------------------------------------------------------
-- Texture helpers (6.3, L6)
---------------------------------------------------------------------------

local function Spec(ns, src, file, slice)
  local key = "futuriste"
  local fx = Fixture()
  fx.media.tex64 = { 64, 32, grey = true }
  fx.bar.layers[#fx.bar.layers + 1] = { id = "probe", file = file or "tex64", rect = src.rect,
    flipX = src.flipX, flipY = src.flipY, rot = src.rot, tile = src.tile, three = slice and { "tex64", slice[1], slice[2] } or nil }
  if slice then fx.bar.layers[#fx.bar.layers].file = nil end
  ns.Themes.Register(key, function() return fx end)
  local th = ns.Themes.Compile(key)
  return Layer(th, "probe").tex
end

T.test("SetTex: path, wrap modes when tiled, rect / flip / rot coordinates, blend; never a colour", function()
  local ns = Load(ENGINE, nil)
  local Th = ns.Themes
  local f = CreateFrame("Frame")
  local t = f:CreateTexture()
  local spec = Spec(ns, { rect = { 16, 8, 32, 16 }, flipY = true })
  T.eq({ spec.l, spec.r, spec.t, spec.b, spec.flipY }, { 0.25, 0.75, 0.25, 0.75, true }, "the rect, unflipped")
  Th.SetTex(t, spec)
  T.eq(t._texture, "Interface\\AddOns\\TruePlayed\\Media\\Themes\\futuriste\\tex64.tga")
  T.eq({ t._wrapH, t._wrapV }, { nil, nil }, "not tiled: SetTexture(path) only")
  T.eq(t._tc, { 0.25, 0.75, 0.75, 0.25 })
  T.eq(t._blend, "BLEND")
  T.eq(t._vR, nil, "no colour")
  Stub.Reset(); ns = Load(ENGINE, nil); Th = ns.Themes
  t = CreateFrame("Frame"):CreateTexture()
  spec = Spec(ns, { rot = 90 })
  Th.SetTex(t, spec)
  T.eq(t._tc, { 0, 1, 1, 1, 0, 0, 1, 0 }, "90 deg: UL=(l,b) LL=(r,b) UR=(l,t) LR=(r,t)")
  Stub.Reset(); ns = Load(ENGINE, nil); Th = ns.Themes
  t = CreateFrame("Frame"):CreateTexture()
  spec = Spec(ns, { tile = "HV" })
  Th.SetTex(t, spec)
  T.eq({ t._wrapH, t._wrapV }, { "REPEAT", "REPEAT" })
  T.eq(t._tc, nil, "Tile sets the coordinates")
  local n = 0
  local orig = t.SetTexCoord
  rawset(t, "SetTexCoord", function(self, ...) n = n + 1; return orig(self, ...) end)
  Th.Tile(t, spec, 100, 10)
  T.eq(t._tc, { 0, 100 / 64, 0, 10 / 32 })
  Th.Tile(t, spec, 100, 10)
  T.eq(n, 1, "same size: no call")
  Th.Tile(t, spec, 120, 10)
  T.eq(n, 2)
  Th.SetTex(t, spec)
  Th.Tile(t, spec, 120, 10)
  T.eq(n, 3, "SetTex (a reset) clears the cache")
end)

T.test("PlaceThree / PlaceNine: pieces, sizes, narrow widths, mirrored coordinates, cached", function()
  local ns = Load(ENGINE, nil)
  local Th = ns.Themes
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(400, 100)
  f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  local spec = Spec(ns, {}, nil, { 16, 8 })
  local t3 = { f:CreateTexture(), f:CreateTexture(), f:CreateTexture() }
  Th.PlaceThree(t3, spec, f, 10, 20, 100, 14)
  local function R(t) local l, b, w, h = t:GetRect(); return { l, b, w, h, t:IsShown() } end
  T.eq(R(t3[1]), { 10, 20, 8, 14, true })
  T.eq(R(t3[2]), { 18, 20, 84, 14, true })
  T.eq(R(t3[3]), { 102, 20, 8, 14, true })
  local h64 = 0.5 / 64                    -- half a texel of the 64-texel-wide texture
  T.eq(t3[1]._tc, { 0, 0.25, 0, 1 }); T.eq(t3[3]._tc, { 0.75, 1, 0, 1 })
  T.eq(t3[2]._tc, { 0.25 + h64, 0.75 - h64, 0, 1 }, "stretched middle: half a texel in (no corner bleed)")
  Th.PlaceThree(t3, spec, f, 10, 20, 11, 14)
  T.eq(R(t3[1]), { 10, 20, 5, 14, true }, "narrower than 2 caps: floor(w/2) each")
  T.eq(R(t3[3]), { 16, 20, 5, 14, true })
  T.no(t3[2]:IsShown(), "middle hidden")
  t3[1]._tc[1] = 99
  Th.PlaceThree(t3, spec, f, 10, 20, 50, 14)
  T.eq(t3[1]._tc[1], 99, "coordinates set once per spec")
  T.ok(t3[2]:IsShown())

  local fx = Fixture()
  fx.media.tex64 = { 64, 32, grey = true }
  fx.bar.layers[#fx.bar.layers + 1] = { id = "probe", nine = { "tex64", 8, 4 }, flipX = true }
  Th.Register("mage", function() return fx end)
  local nine = Layer(Th.Compile("mage"), "probe").tex
  local t9 = {}
  for i = 1, 9 do t9[i] = f:CreateTexture() end
  Th.PlaceNine(t9, nine, f, 0, 0, 40, 20)
  T.eq(R(t9[1]), { 0, 16, 4, 4, true }, "TL")
  T.eq(R(t9[2]), { 4, 16, 32, 4, true }, "T")
  T.eq(R(t9[5]), { 4, 4, 32, 12, true }, "C")
  T.eq(R(t9[9]), { 36, 0, 4, 4, true }, "BR")
  T.eq(t9[1]._tc, { 1, 1 - 8 / 64, 0, 8 / 32 }, "flipX: the left piece shows the right corner, mirrored")
  T.eq(t9[9]._tc, { 8 / 64, 0, 1 - 8 / 32, 1 })
  T.eq(t9[2]._tc, { 1 - 8 / 64 - h64, 8 / 64 + h64, 0, 8 / 32 }, "top edge: inset along x only (mirrored)")
  T.eq(t9[4]._tc, { 1, 1 - 8 / 64, 8 / 32 + 0.5 / 32, 1 - 8 / 32 - 0.5 / 32 }, "left edge: inset along y only")
  T.eq(t9[5]._tc, { 1 - 8 / 64 - h64, 8 / 64 + h64, 8 / 32 + 0.5 / 32, 1 - 8 / 32 - 0.5 / 32 }, "centre: both")
  Th.PlaceNine(t9, nine, f, 0, 0, 6, 20)
  T.eq(R(t9[1]), { 0, 17, 3, 3, true }, "narrow: p = floor(min(w, h) / 2)")
  T.no(t9[2]:IsShown(), "no middle column")
end)

T.test("GradientSliced: one ramp across the pieces of a 3-slice / 9-slice, no allocation", function()
  local ns = LoadEngine()
  local Th = ns.Themes
  local f = CreateFrame("Frame", nil, UIParent)
  local t9 = {}
  for i = 1, 9 do t9[i] = f:CreateTexture() end
  local from = { 0, 0, 0, 1, r = 0, g = 0, b = 0, a = 1 }
  local to = { 1, 1, 1, 0, r = 1, g = 1, b = 1, a = 0 }
  local g = { "VERTICAL", from, to }
  -- 100 px high, corners of 10 px: bottom row 0 -> .1, middle .1 -> .9, top .9 -> 1
  T.eq(Th.GradientSliced(t9, 9, g, from, nil, 200, 100, 10), 1)
  local function G(t) local q = t._grad; return { q[1], q[2], q[5], q[6], q[9] } end
  local function Close(a, b, msg)
    T.eq(a[1], b[1], msg)
    for i = 2, #b do T.near(a[i], b[i], 1e-9, (msg or "") .. " [" .. i .. "]") end
  end
  Close(G(t9[7]), { "VERTICAL", 0, 1, 0.1, 0.9 }, "BL: bottom row")
  Close(G(t9[5]), { "VERTICAL", 0.1, 0.9, 0.9, 0.1 }, "C: middle row")
  Close(G(t9[2]), { "VERTICAL", 0.9, 0.1, 1, 0 }, "T: top row")
  -- horizontal over a 9-slice: columns
  Th.GradientSliced(t9, 9, { "HORIZONTAL", from, to }, from, nil, 200, 100, 10)
  Close(G(t9[4]), { "HORIZONTAL", 0, 1, 0.05, 0.95 }, "L: left column")
  Close(G(t9[6]), { "HORIZONTAL", 0.95, 0.05, 1, 0 }, "R: right column")
  -- 3-slice: a horizontal ramp is cut at the caps (narrow: floor(w / 2) each), a vertical one is whole
  local t3 = { t9[1], t9[2], t9[3] }
  Th.GradientSliced(t3, 3, { "HORIZONTAL", from, to }, from, nil, 40, 10, 8)
  Close(G(t3[2]), { "HORIZONTAL", 0.2, 0.8, 0.8, 0.2 }, "M")
  Th.GradientSliced(t3, 3, { "HORIZONTAL", from, to }, from, nil, 10, 10, 8)
  Close(G(t3[1]), { "HORIZONTAL", 0, 1, 0.5, 0.5 }, "narrow: cut in the middle")
  Th.GradientSliced(t3, 3, { "VERTICAL", from, to }, from, nil, 40, 10, 8)
  Close(G(t3[2]), { "VERTICAL", 0, 1, 1, 0 }, "vertical on a 3-slice: the whole ramp")
  local kb = T.alloc(function() Th.GradientSliced(t9, 9, g, from, nil, 200, 100, 10) end, 200)
  T.ok(kb < 0.01, string.format("GradientSliced allocated %.3f KB", kb))
end)

T.test("Gradient: SetGradient, else SetGradientAlpha, else the flat colour; any compiled form", function()
  local ns = LoadEngine()
  local Th = ns.Themes
  local th = Th.Compile("futuriste")
  local rested = Layer(th, "rested")
  local t = CreateFrame("Frame"):CreateTexture()
  -- a per-state list of pairs (the form of a `base` layer): k picks the pair
  local band = Layer(th, "band")
  local states = { rested.g, band.g }
  T.eq(Th.Gradient(t, states, nil, 1), 1)
  local from, to = band.g[1], band.g[2]
  T.eq(t._grad, { "VERTICAL", from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4] })
  T.eq(Th.Gradient(t, rested.g, rested.f, 1), 1, "one pair")
  from, to = rested.g[1], rested.g[2]
  T.eq(t._grad, { "HORIZONTAL", from[1], from[2], from[3], from[4], to[1], to[2], to[3], to[4] })
  T.eq(Th.Gradient(t, { "VERTICAL", from, to }, from), 1, "{ dir, from, to }")
  T.eq(t._grad[1], "VERTICAL")
  rawset(t, "SetGradient", function() error("no colour tables here") end)
  T.eq(Th.Gradient(t, states, nil, 0), 2)
  T.eq(t._gradA, { "HORIZONTAL", rested.g[1][1], rested.g[1][2], rested.g[1][3], rested.g[1][4],
                   rested.g[2][1], rested.g[2][2], rested.g[2][3], rested.g[2][4] })
  rawset(t, "SetGradientAlpha", function() error("old client") end)
  T.eq(Th.Gradient(t, rested.g, rested.f, 0), 3)
  local fl = rested.f or rested.g[1]                -- no flat colour: the from colour
  T.eq({ t:GetVertexColor() }, { fl[1], fl[2], fl[3], fl[4] })
  local t2 = CreateFrame("Frame"):CreateTexture()
  Th.Gradient(t2, rested.g, rested.f, 1)
  local kb = T.alloc(function() Th.Gradient(t2, rested.g, rested.f, 1) end, 200)
  T.ok(kb < 0.01, string.format("Gradient allocated %.3f KB", kb))
end)
