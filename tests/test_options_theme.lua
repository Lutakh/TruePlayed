-- tests/test_options_theme.lua - the theme in the options panel, the context menu and
-- /tpl theme; the theme locale keys (SPEC-themes 5.6, 5.7, 8.5).
-- Full addon load with the real default theme (Stub.theme = nil: futuriste) unless a
-- test names one; the player of the stub is a mage.
local Stub, T = ...

local format, find, upper, concat = string.format, string.find, string.upper, table.concat

-- SPEC-themes S2, written out: the order every menu uses.
local KEYS = { "futuriste", "actuel", "heroic", "pixel", "class", "warrior", "paladin",
               "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- opts.theme = Stub.theme (nil: the real default), opts.ui = Stub.InstallUI options,
-- opts.locale, opts.db = prepared TruePlayedDB.
local function Start(opts)
  opts = opts or {}
  Stub.theme = opts.theme
  Stub.InstallUI(opts.ui)
  if opts.locale then Stub.locale = opts.locale end
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns
end

local function Controls()
  return rawget(Stub.ui.categories[1].frame, "controls")
end

local function Printed(text, from)
  local lines = Stub.printed
  for i = from or 1, #lines do
    if find(lines[i], text, 1, true) then return true end
  end
  return false
end

-- THEME_CHANGED recorder: returns the list of { key, prev, kind } received.
local function RecordThemeChanges(ns)
  local got = {}
  ns.RegisterMessage("THEME_CHANGED", got, function(_, key, prev, kind)
    got[#got + 1] = { key, prev, kind }
  end)
  return got
end

-- The swatch shows c (rgb), opaque.
local function SwatchIs(rec, c, msg, tol)
  tol = tol or 1e-6
  local r, g, b, a = rec.swatch:GetVertexColor()
  T.near(r, c[1], tol, msg .. " (r)")
  T.near(g, c[2], tol, msg .. " (g)")
  T.near(b, c[3], tol, msg .. " (b)")
  T.eq(a, 1, msg .. " (alpha)")
end

local function Hex(h)
  return { tonumber(h:sub(2, 3), 16) / 255, tonumber(h:sub(4, 5), 16) / 255, tonumber(h:sub(6, 7), 16) / 255 }
end

local function TopY(widget)
  local _, _, _, _, y = widget:GetPoint(1)
  return y
end

local function LoadLocale(file, locale)
  Stub.locale = locale
  local chunk = assert(loadfile(Stub.ROOT .. file))
  local ns = {}
  if locale ~= "enUS" then ns.L = {} end
  chunk("TruePlayed", ns)
  return ns.L
end

---------------------------------------------------------------------------
-- Options panel
---------------------------------------------------------------------------

T.test("options: the theme dropdown is the first Display control, in C.THEME_CHOICES order", function()
  local ns = Start({ ui = { modern = true } })
  local L, C, ui = ns.L, ns.C, Stub.ui
  T.eq(C.THEME_CHOICES, KEYS, "C.THEME_CHOICES (SPEC S2)")
  T.eq(ns.Core.GetSetting("theme"), "futuriste", "real default")
  ns.Options.Open()
  local controls = Controls()
  local rec = controls.theme
  T.ok(rec ~= nil and rec.kind == "dropdown", "theme dropdown")
  T.eq(rec.label:GetText(), L.OPT_THEME)
  -- first control after the Display header: right after the exclusion checkboxes,
  -- right before "Show the bar"
  T.eq(rec.index, controls["exclude.city"].index + 1, "first control after the exclusions")
  T.eq(controls["widget.shown"].index, rec.index + 1, "then the existing Display controls")
  -- the two notes sit between the dropdown and "Show the bar"
  local yTheme, yShown = TopY(rec.widget), TopY(controls["widget.shown"].widget)
  T.ok(yTheme - yShown > 30 + 2 * 6, "room for the two notes under the dropdown")
  local regions = rawget(Stub, "regions")
  if type(regions) == "table" then
    for _, text in ipairs({ L.OPT_THEME_NOTE, L.OPT_THEME_RESTART_NOTE }) do
      local found
      for i = 1, #regions do
        local o = regions[i]
        if type(o) == "table" and rawget(o, "_text") == text then found = o end
      end
      T.ok(found ~= nil, "note shown: " .. text)
      if found then
        local y = TopY(found)
        T.ok(y < yTheme and y > yShown, "note between the dropdown and the next control")
      end
    end
  end
  -- one radio per choice, in order, with its localized name
  local root = rawget(rec.widget, "_root")
  local values, labels = {}, {}
  for i = 1, #root.children do
    local item = root.children[i]
    T.eq(item.kind, "radio")
    values[i] = item.data.value
    labels[item.text] = true
    T.eq(item.text, L["THEME_" .. upper(item.data.value)], "label of " .. item.data.value)
    T.ok(type(item.text) == "string" and item.text ~= "" and not find(item.text, "^THEME_"),
      "localized label for " .. item.data.value)
  end
  T.eq(values, KEYS, "dropdown values")
  local n = 0
  for _ in pairs(labels) do n = n + 1 end
  T.eq(n, #KEYS, "distinct labels")
  T.ok(ui.IsChecked(ui.FindMenuItem(root, L.THEME_FUTURISTE)), "the current theme is checked")
  T.no(ui.IsChecked(ui.FindMenuItem(root, L.THEME_ACTUEL)))
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("options: theme dropdown in French with the fallback controls", function()
  local ns = Start({ ui = { modern = false }, locale = "frFR" })
  local L = ns.L
  ns.Options.Open()
  local rec = Controls().theme
  T.ok(rec ~= nil, "theme control with the fallback controls")
  T.eq(L.OPT_THEME, "Th\195\168me")
  local expect = { "Futuriste", "Classique", "Heroic fantasy", "Pixel r\195\169tro", "Classe (auto)", "Guerrier",
                   "Paladin", "Chasseur", "Voleur", "Pr\195\170tre", "Chaman", "Mage", "D\195\169moniste", "Druide" }
  for i = 1, #KEYS do
    T.eq(rec.choices[i].value, KEYS[i], "value " .. i)
    T.eq(rec.choices[i].label, expect[i], "French label of " .. KEYS[i])
  end
  -- the cycle button walks the choices in order, both ways
  local b = rec.widget
  b:GetScript("OnClick")(b, "LeftButton")
  T.eq(ns.settings.theme, "actuel")
  b:GetScript("OnClick")(b, "RightButton")
  T.eq(ns.settings.theme, "futuriste")
  b:GetScript("OnClick")(b, "RightButton")
  T.eq(ns.settings.theme, "druid", "wraps around")
end)

T.test("options: selecting a theme sets the setting and fires THEME_CHANGED once", function()
  local ns = Start({ ui = { modern = true } })
  local L, ui, Themes = ns.L, Stub.ui, ns.Themes
  ns.Options.Open()
  T.eq(Themes.ActiveKey(), "futuriste")
  local got = RecordThemeChanges(ns)
  local root = rawget(Controls().theme.widget, "_root")
  ui.ClickMenuItem(ui.FindMenuItem(root, L.THEME_MAGE))
  T.eq(ns.settings.theme, "mage")
  T.eq(got, { { "mage", "futuriste", "theme" } }, "one THEME_CHANGED")
  T.eq(Themes.ActiveKey(), "mage")
  root = rawget(Controls().theme.widget, "_root")       -- regenerated for the new value
  T.ok(ui.IsChecked(ui.FindMenuItem(root, L.THEME_MAGE)))
  ui.ClickMenuItem(ui.FindMenuItem(root, L.THEME_MAGE))
  T.eq(#got, 1, "same value again: nothing")
  -- "class" for a mage resolves to mage: the setting changes, the theme does not
  ui.ClickMenuItem(ui.FindMenuItem(root, L.THEME_CLASS))
  T.eq(ns.settings.theme, "class")
  T.eq(#got, 1, "class -> mage for a mage: no THEME_CHANGED")
  root = rawget(Controls().theme.widget, "_root")
  T.ok(ui.IsChecked(ui.FindMenuItem(root, L.THEME_CLASS)), "the dropdown follows the setting")
  T.no(ui.IsChecked(ui.FindMenuItem(root, L.THEME_MAGE)))
  ui.ClickMenuItem(ui.FindMenuItem(root, L.THEME_ACTUEL))
  T.eq(got[2], { "actuel", "mage", "theme" })
  T.eq(#got, 2)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("options: the bar colour swatches show the theme's colours and follow THEME_CHANGED", function()
  local ns = Start({ ui = { modern = true } })
  local C, L, ui, Themes = ns.C, ns.L, Stub.ui, ns.Themes
  ns.Options.Open()
  local controls = Controls()
  local xp, rested, reset = controls["widget.xpColor"], controls["widget.restedColor"], controls["widget.barColors"]
  -- futuriste (default): its magenta and cyan
  SwatchIs(xp, Themes.DefaultColor("xp"), "futuriste xp")
  SwatchIs(rested, Themes.DefaultColor("rested"), "futuriste rested")
  SwatchIs(xp, Hex("#ff2bd6"), "futuriste xp is the board's magenta", 0.003)
  SwatchIs(rested, Hex("#22d3ee"), "futuriste rested is the board's cyan", 0.003)
  T.no(reset.widget:IsEnabled(), "nothing to reset")
  -- switch through the dropdown: the classic purple and blue
  ui.ClickMenuItem(ui.FindMenuItem(rawget(controls.theme.widget, "_root"), L.THEME_ACTUEL))
  SwatchIs(xp, C.COLORS.fill, "classic xp")
  SwatchIs(rested, C.COLORS.restedFill, "classic rested")
  -- switch elsewhere (/tpl) while the panel is shown
  Stub.RunSlash("theme mage")
  SwatchIs(xp, Themes.DefaultColor("xp"), "mage xp")
  T.ok(math.abs(Themes.DefaultColor("xp")[1] - C.COLORS.fill[1]) > 1e-3
    or math.abs(Themes.DefaultColor("xp")[3] - C.COLORS.fill[3]) > 1e-3, "mage has its own xp colour")
  SwatchIs(rested, Themes.DefaultColor("rested"), "mage rested")
  -- hidden panel: no sync; synced again at the next show
  ui.CloseSettings()
  local before = { xp.swatch:GetVertexColor() }
  ns.Core.SetSetting("theme", "warrior")
  T.eq({ xp.swatch:GetVertexColor() }, before, "no sync while hidden")
  ns.Options.Open()
  SwatchIs(xp, Themes.DefaultColor("xp"), "warrior xp after reopening")
  -- a colour of the user's beats the theme, across theme changes; the reset brings the
  -- theme's colours back
  ns.Core.SetSetting("widget.xpColor", { 0, 1, 0 })
  SwatchIs(xp, { 0, 1, 0 }, "custom xp")
  T.ok(reset.widget:IsEnabled())
  ns.Core.SetSetting("theme", "druid")
  SwatchIs(xp, { 0, 1, 0 }, "custom xp kept by a theme change")
  SwatchIs(rested, Themes.DefaultColor("rested"), "druid rested")
  reset.widget:GetScript("OnClick")(reset.widget)
  T.eq(ns.settings.widget.xpColor, false)
  SwatchIs(xp, Themes.DefaultColor("xp"), "druid xp after the reset")
  T.no(reset.widget:IsEnabled())
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("options: a THEME_CHANGED alone refreshes the swatches, only while the panel is shown", function()
  local ns = Start({ ui = { modern = true } })
  local Themes = ns.Themes
  ns.Options.Open()
  local xp = Controls()["widget.xpColor"]
  local real = Themes.DefaultColor
  local fake = { 0.1, 0.2, 0.3, 1 }
  Themes.DefaultColor = function(which)
    if which == "xp" then return fake end
    return real(which)
  end
  local key = Themes.ActiveKey()
  ns.SendMessage("THEME_CHANGED", key, key, "colors")
  SwatchIs(xp, fake, "refreshed by THEME_CHANGED")
  Stub.ui.CloseSettings()
  fake = { 0.9, 0.8, 0.7, 1 }
  ns.SendMessage("THEME_CHANGED", key, key, "colors")
  SwatchIs(xp, { 0.1, 0.2, 0.3 }, "no listener while hidden")
  Themes.DefaultColor = real
end)

---------------------------------------------------------------------------
-- Context menu
---------------------------------------------------------------------------

T.test("context menu: a Theme submenu after Style, one radio per choice", function()
  local ns = Start()
  local L, ui = ns.L, Stub.ui
  ns.Options.ShowContextMenu(ns.Bar.frame)
  local root = ui.lastMenu
  local styleAt, themeAt
  for i = 1, #root.children do
    local item = root.children[i]
    if item.text == L.MENU_STYLE then styleAt = i end
    if item.text == L.MENU_THEME then themeAt = i end
  end
  T.ok(styleAt ~= nil and themeAt ~= nil, "Style and Theme entries")
  T.eq(themeAt, styleAt + 1, "Theme right after the Style submenu")
  local menu = root.children[themeAt]
  T.eq(menu.kind, "button")
  T.eq(#menu.children, #KEYS, "one entry per choice")
  for i = 1, #KEYS do
    local item = menu.children[i]
    T.eq(item.kind, "radio")
    T.eq(item.data, KEYS[i])
    T.eq(item.text, L["THEME_" .. upper(KEYS[i])])
    T.eq(ui.IsChecked(item), KEYS[i] == "futuriste", "checked: " .. KEYS[i])
  end
  T.eq(ns.Themes.ActiveKey(), "futuriste")
  local got = RecordThemeChanges(ns)
  local warlock = ui.FindMenuItem(menu, L.THEME_WARLOCK)
  ui.ClickMenuItem(warlock)
  T.eq(ns.settings.theme, "warlock")
  T.ok(ui.IsChecked(warlock))
  T.no(ui.IsChecked(ui.FindMenuItem(menu, L.THEME_FUTURISTE)))
  T.eq(got, { { "warlock", "futuriste", "theme" } })
  T.eq(ns.Themes.ActiveKey(), "warlock")
  ui.ClickMenuItem(ui.FindMenuItem(menu, L.THEME_ACTUEL))
  T.eq(ns.settings.theme, "actuel", "Classic brings the previous look back")
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- /tpl theme
---------------------------------------------------------------------------

T.test("/tpl theme lists, /tpl theme <name> sets, anything else is unknown", function()
  local ns = Start()
  local L, C = ns.L, ns.C
  local list = concat(C.THEME_CHOICES, ", ")
  local n = #Stub.printed
  Stub.RunSlash("theme")
  T.ok(Printed(format(L.THEME_LIST_FMT, L.THEME_FUTURISTE, list), n + 1), "current theme and the names")
  T.eq(ns.settings.theme, "futuriste", "listing changes nothing")
  T.eq(ns.Themes.ActiveKey(), "futuriste")
  local got = RecordThemeChanges(ns)
  n = #Stub.printed
  Stub.RunSlash("theme mage")
  T.eq(ns.settings.theme, "mage")
  T.ok(Printed(format(L.THEME_SET_FMT, L.THEME_MAGE), n + 1))
  T.eq(ns.Themes.ActiveKey(), "mage")
  T.eq(#got, 1)
  Stub.RunSlash("theme WARLOCK")
  T.eq(ns.settings.theme, "warlock", "case-insensitive")
  n = #Stub.printed
  Stub.RunSlash("theme class")
  T.eq(ns.settings.theme, "class")
  T.ok(Printed(format(L.THEME_SET_FMT, L.THEME_CLASS), n + 1))
  T.eq(ns.Themes.ActiveKey(), "mage", "class theme of the mage")
  n = #Stub.printed
  Stub.RunSlash("theme")
  T.ok(Printed(format(L.THEME_LIST_FMT, L.THEME_CLASS, list), n + 1), "the setting, not the resolved theme")
  n = #Stub.printed
  Stub.RunSlash("theme foo")
  T.ok(Printed(format(L.UNKNOWN_CMD_FMT, "theme foo"), n + 1), "unknown theme")
  T.eq(ns.settings.theme, "class", "unchanged")
  Stub.RunSlash("theme Mage-Bad")
  T.eq(ns.settings.theme, "class")
  n = #Stub.printed
  Stub.RunSlash("theme actuel")
  T.eq(ns.settings.theme, "actuel")
  T.ok(Printed(format(L.THEME_SET_FMT, L.THEME_ACTUEL), n + 1))
  -- help: the theme line right after the style line
  n = #Stub.printed
  Stub.RunSlash("help")
  local styleAt
  for i = n + 1, #Stub.printed do
    if find(Stub.printed[i], L.HELP_STYLE, 1, true) then styleAt = i end
  end
  T.ok(styleAt ~= nil, "help lists the style command")
  T.ok(find(Stub.printed[styleAt + 1] or "", L.HELP_THEME, 1, true) ~= nil, "HELP_THEME after HELP_STYLE")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("/tpl theme in French", function()
  Start({ locale = "frFR" })
  local n = #Stub.printed
  Stub.RunSlash("theme")
  T.ok(Printed("Th\195\168me : Futuriste. Disponibles : futuriste, actuel, heroic, pixel, class, warrior, "
    .. "paladin, hunter, rogue, priest, shaman, mage, warlock, druid", n + 1))
  n = #Stub.printed
  Stub.RunSlash("theme warlock")
  T.ok(Printed("Th\195\168me : D\195\169moniste", n + 1))
  n = #Stub.printed
  Stub.RunSlash("help")
  T.ok(Printed("/tpl theme [nom] - affiche ou change le th\195\168me", n + 1))
end)

T.test("/tpl theme shows a theme kept from a newer version as it is", function()
  local ns = Start({ ui = { modern = true }, db = { schema = 1, settings = { theme = "newtheme" } } })
  local L, C = ns.L, ns.C
  T.eq(ns.Core.GetSetting("theme"), "newtheme", "kept by the repair (S3)")
  local n = #Stub.printed
  Stub.RunSlash("theme")
  T.ok(Printed(format(L.THEME_LIST_FMT, "newtheme", concat(C.THEME_CHOICES, ", ")), n + 1))
  ns.Options.Open()                                     -- no choice matches: no error
  local root = rawget(Controls().theme.widget, "_root")
  for i = 1, #root.children do
    T.no(Stub.ui.IsChecked(root.children[i]), "nothing checked for an unknown key")
  end
  Stub.RunSlash("theme heroic")
  T.eq(ns.settings.theme, "heroic")
end)

---------------------------------------------------------------------------
-- Locales (SPEC-themes 5.7)
---------------------------------------------------------------------------

T.test("locales: the theme keys in enUS and frFR", function()
  local en = LoadLocale("Locales/enUS.lua", "enUS")
  local fr = LoadLocale("Locales/frFR.lua", "frFR")
  for i = 1, #KEYS do
    local key = "THEME_" .. upper(KEYS[i])
    T.ok(type(rawget(en, key)) == "string" and rawget(en, key) ~= "", "enUS " .. key)
    T.ok(type(rawget(fr, key)) == "string" and rawget(fr, key) ~= "", "frFR " .. key)
  end
  T.eq({ en.THEME_FUTURISTE, en.THEME_ACTUEL, en.THEME_HEROIC, en.THEME_PIXEL, en.THEME_CLASS },
       { "Futuristic", "Classic", "Heroic fantasy", "Pixel (old school)", "Class (automatic)" })
  T.eq({ fr.THEME_FUTURISTE, fr.THEME_ACTUEL, fr.THEME_HEROIC, fr.THEME_PIXEL, fr.THEME_CLASS },
       { "Futuriste", "Classique", "Heroic fantasy", "Pixel r\195\169tro", "Classe (auto)" })
  T.eq({ en.THEME_PRIEST, en.THEME_WARLOCK, fr.THEME_PRIEST, fr.THEME_WARLOCK },
       { "Priest", "Warlock", "Pr\195\170tre", "D\195\169moniste" })
  T.eq({ en.OPT_THEME, en.MENU_THEME, fr.OPT_THEME, fr.MENU_THEME },
       { "Theme", "Theme", "Th\195\168me", "Th\195\168me" })
  T.eq({ en.OPT_TEXT_COLOR_RESET, en.OPT_BAR_COLORS_RESET }, { "Theme colours", "Theme colours" })
  T.eq({ fr.OPT_TEXT_COLOR_RESET, fr.OPT_BAR_COLORS_RESET }, { "Couleurs du th\195\168me", "Couleurs du th\195\168me" })
  T.ok(find(en.OPT_BAR_COLORS_NOTE, "theme's colours", 1, true) ~= nil, "enUS bar colours note names the theme")
  T.ok(find(fr.OPT_BAR_COLORS_NOTE, "couleurs du th\195\168me", 1, true) ~= nil, "frFR bar colours note names the theme")
  T.no(find(en.OPT_BAR_COLORS_NOTE, "purple", 1, true))
  T.eq(en.HELP_THEME, "/tpl theme [name] - show or change the theme")
  T.eq(fr.HELP_THEME, "/tpl theme [nom] - affiche ou change le th\195\168me")
  T.eq(format(en.THEME_SET_FMT, "Mage"), "Theme: Mage")
  T.eq(format(fr.THEME_SET_FMT, "Mage"), "Th\195\168me : Mage")
  T.eq(format(en.THEME_LIST_FMT, "Classic", "a, b"), "Theme: Classic. Available: a, b")
  T.eq(format(fr.THEME_LIST_FMT, "Classique", "a, b"), "Th\195\168me : Classique. Disponibles : a, b")
  T.eq({ format(en.LEVEL_TITLE_FMT, 20), en.LEVEL_CAP_TAG, en.LEVEL_CAP_TAG_TITLE, en.XP_LABEL },
       { "Level 20", "CAP", "Cap", "XP:" })
  T.eq({ format(fr.LEVEL_TITLE_FMT, 20), fr.LEVEL_CAP_TAG, fr.LEVEL_CAP_TAG_TITLE, fr.XP_LABEL },
       { "Niveau 20", "PLAFOND", "Plafond", "XP :" })
  T.ok(find(format(en.THEME_FONT_MISSING, "Orbitron-Bold.ttf"), "(Orbitron-Bold.ttf)", 1, true) ~= nil)
  T.ok(find(format(fr.THEME_FONT_MISSING, "Orbitron-Bold.ttf"), "(Orbitron-Bold.ttf)", 1, true) ~= nil)
  for _, key in ipairs({ "OPT_THEME_NOTE", "OPT_THEME_RESTART_NOTE" }) do
    T.ok(type(rawget(en, key)) == "string" and #en[key] > 40, "enUS " .. key)
    T.ok(type(rawget(fr, key)) == "string" and #fr[key] > 40, "frFR " .. key)
  end
  T.ok(find(en.OPT_THEME_RESTART_NOTE, "/reload", 1, true) ~= nil)
  T.ok(find(fr.OPT_THEME_RESTART_NOTE, "/reload", 1, true) ~= nil)
end)
