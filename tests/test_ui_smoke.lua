-- tests/test_ui_smoke.lua - Bar, Window, Options, Broker (IMPL-4), SPEC-FINAL 9.4.
-- Full addon load through the frozen stub plus tests/stub_ui.lua (Stub.InstallUI).
local Stub, T = ...

local format, find, gmatch = string.format, string.find, string.gmatch

local OTHER_GUID = "Player-4619-0BADF00D"

local WHITELIST = {
  TruePlayedDB = true,
  SLASH_TRUEPLAYED1 = true, SLASH_TRUEPLAYED2 = true,
  TruePlayed_OnAddonCompartmentClick = true,
  TruePlayed_OnAddonCompartmentEnter = true,
  TruePlayed_OnAddonCompartmentLeave = true,
  TruePlayedWidget = true, TruePlayedStatsFrame = true,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Loads the addon and logs in. opts.ui = table for Stub.InstallUI (default: all),
-- opts.noUI = true to install nothing, opts.db = prepared TruePlayedDB.
local function Start(opts)
  opts = opts or {}
  if not opts.noUI then Stub.InstallUI(opts.ui) end
  if opts.locale then Stub.locale = opts.locale end
  if opts.level then
    Stub.player.level = opts.level
    Stub.player.max = Stub.xpTable[opts.level] or 0
  end
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = opts.settle or 3 })
  return ns
end

local function Printed(text, from)
  local lines = Stub.printed
  for i = from or 1, #lines do
    if find(lines[i], text, 1, true) then return true end
  end
  return false
end

local function CountPrinted(text, from)
  local n = 0
  local lines = Stub.printed
  for i = from or 1, #lines do
    if find(lines[i], text, 1, true) then n = n + 1 end
  end
  return n
end

-- Longest literal fragment of a format string (text between format specifiers).
local function Frag(fmt)
  local best = ""
  for piece in gmatch(fmt .. "%s", "(.-)%%[%d%.]*[sd]") do
    if #piece > #best then best = piece end
  end
  return best
end

local function Widget()
  return rawget(_G, "TruePlayedWidget")
end

local function SetTextCount(fs)
  local n = rawget(fs, "_setTextCount")
  return type(n) == "number" and n or 0
end

local function LastPopup()
  local p = Stub.popups[#Stub.popups]
  if not p then return nil, nil end
  return p.which or p[1], p.data or p[3]
end

local function OtherRecord()
  return {
    guid = OTHER_GUID, name = "Tamar", realm = "Brisevent", class = "WARRIOR", faction = "Horde",
    level = 30, firstSeen = 1789000000, lastSeen = 1789500000,
    base = { at = 1789000000, total = 100, level = 1 },
    life = { s = { w = 9000000 }, xp = 500000, xa = 500000, xr = 0, xq = 0, d = 3, est = 0 },
    levels = {
      [29] = { s = { w = 8000 }, z = { [1446] = { s = { w = 8000 }, xp = 2000 } },
               xp = 2000, xa = 2000, xr = 0, xq = 0, d = 0, t0 = 1789300000, t1 = 1789400000 },
      [30] = { s = { w = 4000 }, z = { [1446] = { s = { w = 4000 }, xp = 1000 } },
               xp = 1000, xa = 1000, xr = 0, xq = 0, d = 0, t0 = 1789400000 },
    },
    zones = { [1446] = { s = { w = 9000000 }, xp = 500000, name = "Tanaris" } },
    sessions = { { t0 = 1789300000, t1 = 1789310000, l0 = 29, p0 = 0.1, l1 = 29, p1 = 0.9,
                   s = { w = 10000 }, xp = 2000, d = 0 } },
  }
end

---------------------------------------------------------------------------
-- Globals and lazy creation
---------------------------------------------------------------------------

T.test("slash, compartment and popup globals exist right after file load", function()
  local ns = Stub.LoadAddon()                  -- DB_READY never fires in this test
  local L = ns.L
  T.eq(rawget(_G, "SLASH_TRUEPLAYED1"), "/trueplayed")
  T.eq(rawget(_G, "SLASH_TRUEPLAYED2"), "/tpl")
  T.eq(type(SlashCmdList.TRUEPLAYED), "function")
  T.eq(type(rawget(_G, "TruePlayed_OnAddonCompartmentClick")), "function")
  T.eq(type(rawget(_G, "TruePlayed_OnAddonCompartmentEnter")), "function")
  T.eq(type(rawget(_G, "TruePlayed_OnAddonCompartmentLeave")), "function")
  local dlg = StaticPopupDialogs.TRUEPLAYED_ERASE_CHAR
  T.ok(type(dlg) == "table", "popup defined")
  T.eq(dlg.text, "%s")
  T.eq(type(dlg.OnAccept), "function")

  local n = #Stub.printed
  Stub.RunSlash("stats")
  T.ok(Printed(L.NOT_READY, n + 1), "slash before ready prints NOT_READY")
  n = #Stub.printed
  TruePlayed_OnAddonCompartmentClick("TruePlayed", "LeftButton", nil)
  T.ok(Printed(L.NOT_READY, n + 1), "compartment click before ready prints NOT_READY")
  TruePlayed_OnAddonCompartmentEnter("TruePlayed", nil)
  TruePlayed_OnAddonCompartmentLeave("TruePlayed", nil)
  T.eq(Widget(), nil, "no widget before DB_READY")
  T.eq(rawget(_G, "TruePlayedStatsFrame"), nil, "no window before a Show")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("_G writes are limited to the whitelist", function()
  Stub.InstallUI()
  local before = {}
  for k in pairs(_G) do before[k] = true end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(20)
  ns.Window.Show()
  ns.Window.Toggle("zones")
  ns.Window.Toggle("sessions")
  ns.Options.Open()
  ns.Options.ShowContextMenu(ns.Bar.frame)
  Stub.RunSlash("help")
  Stub.RunSlash("played")
  Stub.RunSlash("perf")
  Stub.RunSlash("style box")
  Stub.Advance(65)
  Stub.Logout()
  for k in pairs(_G) do
    if not before[k] then
      T.ok(WHITELIST[k], "unexpected global " .. tostring(k))
    end
  end
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("the widget is created at DB_READY and first run unlocks it", function()
  local ns = Start({ ui = { ldb = false } })
  local L = ns.L
  local f = Widget()
  T.ok(f ~= nil, "TruePlayedWidget created")
  T.ok(ns.Bar.frame == f)
  T.ok(f:IsShown())
  Stub.Advance(5)
  local tp = f.tp
  for i = 1, 3 do T.eq(type(tp.slots[i]:GetText()), "string") end
  T.match(tp.bl:GetText(), "10")
  T.ok(find(tp.brx:GetText() or "", "7,600", 1, true) ~= nil, "XP text shows the level max")
  T.ok(ns.Tokens.IsActive(), "bar is a token consumer")
  T.ok(Printed(L.FIRST_RUN), "first run message")
  T.eq(ns.settings.firstRunDone, true)
  T.eq(ns.settings.widget.locked, false)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("widget.shown = false at login: nothing created, no consumer", function()
  local ns = Start({ ui = { ldb = false }, db = { schema = 1, settings = { widget = { shown = false } } } })
  Stub.Advance(10)
  T.eq(Widget(), nil, "widget stays lazy")
  T.no(ns.Tokens.IsActive())
  Stub.RunSlash("show")
  T.ok(Widget() ~= nil)
  T.ok(ns.Tokens.IsActive())
end)

---------------------------------------------------------------------------
-- Performance (requirement A)
---------------------------------------------------------------------------

T.test("steady state: no SetText on unchanged texts, allocation budget", function()
  local ns = Start({ ui = { ldb = false } })
  Stub.Advance(300)
  local tp = Widget().tp
  local function Counts()
    return { SetTextCount(tp.slots[1]), SetTextCount(tp.slots[2]), SetTextCount(tp.slots[3]),
             SetTextCount(tp.bl), SetTextCount(tp.brx), SetTextCount(tp.marker) }
  end
  local c0 = Counts()
  Stub.Advance(60)
  T.eq(Counts(), c0, "no SetText over 60 ticks when nothing changed")
  local step = function() Stub.Advance(1) end
  local kb = T.alloc(step, 600)
  T.ok(kb <= 2, format("600 ticks with the bar visible allocated %.2f KB (budget 2 KB)", kb))
  T.ok(ns.Tokens.IsActive())
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("hidden widget: TICK work stops and the token consumer is released", function()
  local ns = Start({ ui = { ldb = false } })
  Stub.Advance(5)
  local f = Widget()
  local tp = f.tp
  Stub.RunSlash("hide")
  T.eq(ns.settings.widget.shown, false)
  T.no(f:IsShown())
  T.no(ns.Tokens.IsActive(), "bar consumer released (no LDB)")
  ns.Core.SetSetting("widget.slots.3", "session")
  local c = SetTextCount(tp.slots[3])
  Stub.SetAFK(true)
  Stub.Advance(150)
  T.eq(SetTextCount(tp.slots[3]), c, "no SetText while hidden")
  Stub.RunSlash("show")
  T.ok(f:IsShown())
  T.ok(ns.Tokens.IsActive())
  T.ok(find(tp.slots[3]:GetText(), Frag(ns.L.PFX_SESSION_FMT), 1, true) ~= nil, "session token after show")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("combatHide: invisible and inactive in combat, restored afterwards", function()
  local ns = Start({ ui = { ldb = false } })
  ns.Core.SetSetting("widget.combatHide", true)
  local f = Widget()
  Stub.EnterCombat()
  T.eq(f:GetAlpha(), 0)
  T.no(ns.Tokens.IsActive())
  Stub.LeaveCombat()
  T.eq(f:GetAlpha(), 1)
  T.ok(ns.Tokens.IsActive())
  ns.Core.SetSetting("widget.combatHide", false)
  Stub.EnterCombat()
  T.eq(f:GetAlpha(), 1, "option off: stays visible")
  Stub.LeaveCombat()
end)

T.test("fade: dimmed when not hovered", function()
  local ns = Start({ ui = { ldb = false } })
  local f = Widget()
  ns.Core.SetSetting("widget.fade", true)
  T.near(f:GetAlpha(), 0.35, 1e-9)
  f:GetScript("OnEnter")(f)
  T.eq(f:GetAlpha(), 1)
  f:GetScript("OnLeave")(f)
  T.near(f:GetAlpha(), 0.35, 1e-9)
end)

T.test("hideAtMax: no widget at max level until the option is turned off", function()
  local ns = Start({ ui = { ldb = false }, level = 60,
                     db = { schema = 1, settings = { widget = { hideAtMax = true } } } })
  Stub.Advance(5)
  T.eq(Widget(), nil)
  T.no(ns.Tokens.IsActive())
  ns.Core.SetSetting("widget.hideAtMax", false)
  local f = Widget()
  T.ok(f ~= nil and f:IsShown())
  Stub.Advance(2)
  -- XP tokens are replaced by the max-level slots (default slot 1 at max = session)
  T.ok(find(f.tp.slots[1]:GetText(), Frag(ns.L.PFX_SESSION_FMT), 1, true) ~= nil)
  T.match(f.tp.bl:GetText(), "60")
end)

---------------------------------------------------------------------------
-- Settings and layouts
---------------------------------------------------------------------------

T.test("every SETTINGS_CHANGED path of 3.17 applies without error", function()
  local ns = Start({ ui = { ldb = false } })
  local cases = {
    { "exclude.afk", true }, { "exclude.inn", true }, { "exclude.city", true },
    { "widget.locked", true }, { "widget.bgAlpha", 0.5 }, { "widget.combatHide", true },
    { "widget.fade", true }, { "widget.hideAtMax", true },
    { "widget.style", "box" }, { "widget.style", "bar" },
    { "widget.point", { "TOPLEFT", "TOPLEFT", 100, -100 } },
    { "widget.scale", 1.5 }, { "widget.width", 400 }, { "widget.height", 12 }, { "widget.fontSize", 14 },
    { "widget.slots.1", "session" }, { "widget.slots.2", "played" }, { "widget.slots.3", "fps" },
    { "widget.maxSlots.1", "played" }, { "widget.maxSlots.2", "session" }, { "widget.maxSlots.3", "none" },
    { "widget.slot3Pos", "left" }, { "widget.pctPos", "level" },
    { "rateTau", 1200 }, { "requestPlayedAtLogin", false }, { "hidePlayedMsg", true },
    { "debug", true }, { "debug", false }, { "firstRunDone", true },
    { "widget.shown", false }, { "widget.shown", true },
    { "widget.bgAlpha", 0 }, { "widget.fade", false }, { "widget.locked", false },
    { "widget.textColor", { 1, 0.5, 0 } }, { "widget.textColor", false },
    { "widget.outline", "thick" }, { "widget.outline", "none" }, { "widget.outline", "thin" },
    { "widget.shadow", false }, { "widget.shadow", true },
    { "widget.qualityColors", false }, { "widget.qualityColors", true },
    { "graph.window", 300 }, { "graph.window", 30 }, { "graph.window", 60 },
    { "widget.slots.3", "fps" },
  }
  do                                                 -- C4: bar colours
    local n = #cases
    cases[n + 1] = { "widget.xpColor", { 0.2, 0.4, 0.6 } }
    cases[n + 2] = { "widget.restedColor", { 0.9, 0.1, 0.1 } }
    cases[n + 3] = { "widget.xpColor", false }
    cases[n + 4] = { "widget.restedColor", false }
  end
  for i = 1, #cases do
    local c = cases[i]
    ns.Core.SetSetting(c[1], c[2])
    Stub.Advance(1)
  end
  local f = Widget()
  T.ok(f:IsShown())
  T.eq(f:GetWidth(), 400 + 16, "bar width = width + 2 * padding")
  T.eq(f:GetScale(), 1.5)
  local point, _, relPoint, x, y = f:GetPoint(1)
  T.eq(point, "TOPLEFT")
  T.eq(relPoint, "TOPLEFT")
  T.eq(x, 100)
  T.eq(y, -100)
  T.ok(find(f.tp.slots[1]:GetText(), Frag(ns.L.PFX_SESSION_FMT), 1, true) ~= nil)
  T.ok(find(f.tp.slots[2]:GetText(), Frag(ns.L.PFX_PLAYED_FMT), 1, true) ~= nil)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("bar and box styles, slot 3 position and % marker", function()
  local ns = Start({ ui = { ldb = false } })
  Stub.GrantXP(3800)                           -- 50 % of 7600
  Stub.Advance(2)
  local f = Widget()
  local tp = f.tp
  T.match(tp.marker:GetText(), "50")
  -- the marker never overlaps the level text or the XP text
  local _, _, _, mx = tp.marker:GetPoint(1)
  local pad, W = 8, ns.settings.widget.width
  local blRight = pad + tp.bl:GetStringWidth()
  local brxLeft = pad + W - tp.slots[2]:GetStringWidth() - 8 - tp.brx:GetStringWidth()
  T.ok(mx >= blRight + 6, "marker right of the level text")
  T.ok(mx + tp.marker:GetStringWidth() <= brxLeft - 6 + 0.5, "marker left of the XP text")
  -- pctPos = level: the percent joins the level text
  ns.Core.SetSetting("widget.pctPos", "level")
  T.match(tp.bl:GetText(), "50")
  ns.Core.SetSetting("widget.pctPos", "follow")
  -- slot 3 left / centre
  ns.Core.SetSetting("widget.slot3Pos", "left")
  T.eq((tp.slots[3]:GetPoint(1)), "BOTTOMLEFT")
  ns.Core.SetSetting("widget.slot3Pos", "center")
  T.eq((tp.slots[3]:GetPoint(1)), "BOTTOM")
  -- compact box
  ns.Core.SetSetting("widget.style", "box")
  T.eq(f:GetWidth(), 180)
  T.eq((tp.slots[1]:GetPoint(1)), "TOPLEFT")
  Stub.Advance(3)
  ns.Core.SetSetting("widget.style", "bar")
  T.eq(f:GetWidth(), W + 16)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("frFR widget texts", function()
  Start({ ui = { ldb = false }, locale = "frFR" })
  Stub.Advance(5)
  local tp = Widget().tp
  T.match(tp.bl:GetText(), "^NIVEAU 10")
  T.ok(find(tp.brx:GetText() or "", "XP : ", 1, true) ~= nil)
  T.ok(find(tp.brx:GetText() or "", "7\194\160600", 1, true) ~= nil)
end)

---------------------------------------------------------------------------
-- Tooltip, clicks, context menu
---------------------------------------------------------------------------

T.test("tooltip: Fill on the mock, hover shows and leave hides", function()
  local ns = Start({ ui = { ldb = false } })
  Stub.Advance(3)
  GameTooltip:ClearLines()
  ns.Tooltip.Fill(GameTooltip, true)
  T.ok(#GameTooltip._lines > 5, "detailed tooltip has lines")
  local f = Widget()
  f:GetScript("OnEnter")(f)
  T.ok(ns.Tooltip.IsShownFor(f))
  T.ok(GameTooltip:GetOwner() == f)
  Stub.Advance(3)
  f:GetScript("OnLeave")(f)
  T.no(ns.Tooltip.IsShownFor(f))
end)

T.test("left click toggles the window, right click opens the context menu", function()
  local ns = Start()
  local f = Widget()
  f:GetScript("OnMouseDown")(f, "LeftButton")
  f:GetScript("OnMouseUp")(f, "LeftButton")
  T.ok(ns.Window.IsShown())
  f:GetScript("OnMouseDown")(f, "LeftButton")
  f:GetScript("OnMouseUp")(f, "LeftButton")
  T.no(ns.Window.IsShown())
  f:GetScript("OnMouseUp")(f, "RightButton")
  T.eq(Stub.ui.menus, 1)
  T.ok(Stub.ui.lastMenuOwner == f)
  -- a drag is not a click
  f:GetScript("OnMouseDown")(f, "LeftButton")
  f:GetScript("OnDragStart")(f)
  f:GetScript("OnDragStop")(f)
  f:GetScript("OnMouseUp")(f, "LeftButton")
  T.no(ns.Window.IsShown())
  -- after the drag: the tooltip on hover and the click work again
  f:GetScript("OnLeave")(f)
  f:GetScript("OnEnter")(f)
  T.ok(ns.Tooltip.IsShownFor(f), "tooltip after a drag")
  f:GetScript("OnMouseDown")(f, "LeftButton")
  f:GetScript("OnMouseUp")(f, "LeftButton")
  T.ok(ns.Window.IsShown(), "click after a drag")
end)

T.test("context menu: exclusions, style, lock, stats, hide, options", function()
  local ns = Start()
  local L = ns.L
  local ui = Stub.ui
  ns.Options.ShowContextMenu(ns.Bar.frame)
  local root = ui.lastMenu
  T.ok(ui.FindMenuItem(root, L.ADDON_TITLE) ~= nil, "title")
  local afk = ui.FindMenuItem(root, L.MENU_EXCLUDE_AFK)
  T.ok(afk ~= nil and afk.kind == "checkbox")
  T.no(ui.IsChecked(afk))
  ui.ClickMenuItem(afk)
  T.eq(ns.settings.exclude.afk, true)
  T.ok(ui.IsChecked(afk))
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_EXCLUDE_INN))
  T.eq(ns.settings.exclude.inn, true)
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_EXCLUDE_CITY))
  T.eq(ns.settings.exclude.city, true)
  ui.ClickMenuItem(ui.FindMenuItem(root, L.STYLE_BOX))
  T.eq(ns.settings.widget.style, "box")
  T.ok(ui.IsChecked(ui.FindMenuItem(root, L.STYLE_BOX)))
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_LOCK))
  T.eq(ns.settings.widget.locked, true)
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_STATS))
  T.ok(ns.Window.IsShown())
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_RESET_SESSION))
  local n = #Stub.printed
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_HIDE))
  T.eq(ns.settings.widget.shown, false)
  T.ok(Printed(L.WIDGET_HIDDEN, n + 1))
  local opened = ui.opened
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_OPTIONS))
  T.eq(ui.opened, opened + 1)
end)

T.test("without MenuUtil the context menu opens the options", function()
  local ns = Start({ ui = { menu = false } })
  ns.Options.ShowContextMenu(ns.Bar.frame)
  T.eq(Stub.ui.menus, 0)
  T.eq(Stub.ui.opened, 1)
end)

---------------------------------------------------------------------------
-- Slash commands (7.12)
---------------------------------------------------------------------------

T.test("every /tpl sub-command", function()
  local ns = Start()
  local L = ns.L
  Stub.Advance(15)                             -- login /played answered
  local function Run(cmd, expect)
    local n = #Stub.printed
    Stub.RunSlash(cmd)
    if expect then T.ok(Printed(expect, n + 1), format("/tpl %s -> %q", cmd, expect)) end
  end

  Run("help", L.HELP_HEADER)
  T.ok(Printed(L.HELP_PERF))
  Run("stats")
  T.ok(ns.Window.IsShown())
  Run("stats zones")
  T.ok(ns.Window.IsShown(), "another tab keeps the window open")
  Run("stats zones")
  T.no(ns.Window.IsShown(), "same tab closes it")
  Run("lock", L.LOCKED)
  T.eq(ns.settings.widget.locked, true)
  Run("unlock", L.UNLOCKED)
  T.eq(ns.settings.widget.locked, false)
  Run("hide", L.WIDGET_HIDDEN)
  T.eq(ns.settings.widget.shown, false)
  Run("show", L.WIDGET_SHOWN)
  T.eq(ns.settings.widget.shown, true)
  Run("style box", Frag(L.STYLE_SET_FMT))
  T.eq(ns.settings.widget.style, "box")
  Run("style bar")
  T.eq(ns.settings.widget.style, "bar")
  Run("style", Frag(L.STYLE_SET_FMT))
  T.eq(ns.settings.widget.style, "box", "no argument toggles the style")
  Run("afk on", Frag(L.EXCL_STATE_FMT))
  T.eq(ns.settings.exclude.afk, true)
  Run("afk off")
  T.eq(ns.settings.exclude.afk, false)
  Run("afk")
  T.eq(ns.settings.exclude.afk, true, "no argument toggles")
  Run("inn")
  T.eq(ns.settings.exclude.inn, true)
  Run("city on")
  T.eq(ns.settings.exclude.city, true)
  Run("CITY OFF")
  T.eq(ns.settings.exclude.city, false, "case-insensitive")
  T.eq(ns.db.cities[1411], nil, "/tpl city never touches the city list")
  Run("citytoggle", Frag(L.CITY_ADDED_FMT))
  T.eq(ns.db.cities[1411], true)
  Run("citytoggle", Frag(L.CITY_REMOVED_FMT))
  T.eq(ns.db.cities[1411], nil)
  Run("played", Frag(L.SUM_HEADER_FMT))
  T.ok(Printed(Frag(L.SUM_PLAYED_FMT)))
  Stub.Advance(3)
  local beforeSync = #Stub.printed
  Run("sync", L.SYNC_REQUESTED)
  T.eq(CountPrinted(L.SYNC_REQUESTED, beforeSync + 1), 1, "SYNC_REQUESTED printed once")
  Stub.Advance(1)
  T.ok(Printed(L.SYNCED))
  Run("reset pos", L.RESET_POS_DONE)
  T.eq(ns.settings.widget.point, { "CENTER", "CENTER", 0, -220 })
  Run("reset session", L.RESET_SESSION_DONE)
  Run("reset rate", L.RESET_RATE_DONE)
  local np = #Stub.popups
  Run("reset char")
  T.eq(#Stub.popups, np + 1, "reset char asks for confirmation")
  local which, data = LastPopup()
  T.eq(which, "TRUEPLAYED_ERASE_CHAR")
  T.eq(data, Stub.player.guid)
  Run("debug", L.DEBUG_ON)
  T.eq(ns.settings.debug, true)
  Run("debug", L.DEBUG_OFF)
  T.eq(ns.settings.debug, false)
  Run("perf", Frag(L.PERF_HEADER_FMT))
  T.ok(Printed(Frag(L.PERF_MEM_FMT)))
  T.ok(Printed(Frag(L.PERF_DATA_FMT)))
  T.ok(Printed(Frag(L.PERF_TICK_ARMED_FMT)))
  Stub.Advance(62)
  T.ok(Printed(Frag(L.PERF_TICK_FMT)), "tick profile reported after 60 ticks")
  Run("frobnicate", Frag(L.UNKNOWN_CMD_FMT))
  Run("reset everything", Frag(L.UNKNOWN_CMD_FMT))
  Run("afk maybe", Frag(L.UNKNOWN_CMD_FMT))
  local opened = Stub.ui.opened
  Run("")
  T.eq(Stub.ui.opened, opened + 1, "/tpl opens the options")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("read-only data: resets, city toggle and erase are refused", function()
  local ns = Start({ db = { schema = 99, settings = {}, chars = {} } })
  local L = ns.L
  T.ok(ns.readOnly)
  local n = #Stub.printed
  Stub.RunSlash("reset session")
  Stub.RunSlash("reset rate")
  Stub.RunSlash("citytoggle")
  local np = #Stub.popups
  Stub.RunSlash("reset char")
  T.eq(#Stub.popups, np, "no erase popup in read-only mode")
  T.eq(CountPrinted(L.READONLY_ACTION, n + 1), 4)
end)

T.test("/tpl citytoggle inside an instance says instances never count as cities", function()
  local ns = Start()
  local L = ns.L
  Stub.SetInstance(true, "party", 389, 90001)   -- Ragefire Chasm, under Orgrimmar
  Stub.Advance(1)
  local n = #Stub.printed
  Stub.RunSlash("citytoggle")
  T.eq(CountPrinted(L.CITY_INSTANCE, n + 1), 1, "instance message printed")
  T.eq(CountPrinted(L.NO_ZONE, n + 1), 0, "not the unknown-zone message")
  T.eq(ns.db.cities[90001], nil, "nothing stored")
  T.ok(L.CITY_INSTANCE ~= "CITY_INSTANCE", "key exists in the locale")
end)

---------------------------------------------------------------------------
-- Options panel
---------------------------------------------------------------------------

T.test("Options.Open in combat is deferred until the end of combat", function()
  local ns = Start()
  local L = ns.L
  Stub.EnterCombat()
  local n = #Stub.printed
  ns.Options.Open()
  ns.Options.Open()
  T.eq(CountPrinted(L.COMBAT_DEFERRED, n + 1), 1, "one notice")
  T.eq(Stub.ui.opened, 0)
  Stub.LeaveCombat()
  T.eq(Stub.ui.opened, 1, "opened after combat")
end)

T.test("options panel: lazy content and modern controls", function()
  local ns = Start({ ui = { modern = true } })
  local ui = Stub.ui
  local cat = ui.categories[1]
  T.ok(cat ~= nil, "Settings category registered")
  T.eq(cat.name, ns.L.ADDON_TITLE)
  T.ok(ui.addonCategories[1] == cat, "category added to the AddOns list")
  T.eq(rawget(cat.frame, "controls"), nil, "content not built before the first show")
  ns.Options.Open()
  T.eq(ui.openedID, cat:GetID())
  local controls = rawget(cat.frame, "controls")
  T.ok(type(controls) == "table", "content built on first show")
  -- dropdown
  local dd = controls["widget.style"].widget
  local item = ui.FindMenuItem(rawget(dd, "_root"), ns.L.STYLE_BOX)
  T.ok(item ~= nil and item.kind == "radio")
  ui.ClickMenuItem(item)
  T.eq(ns.settings.widget.style, "box")
  local slot = controls["widget.slots.1"].widget
  ui.ClickMenuItem(ui.FindMenuItem(rawget(slot, "_root"), ns.Tokens.Label("played")))
  T.eq(ns.settings.widget.slots[1], "played")
  local tau = controls["rateTau"].widget
  ui.ClickMenuItem(ui.FindMenuItem(rawget(tau, "_root"), ns.L.REACT_FAST))
  T.eq(ns.settings.rateTau, 1200)
  -- max-level slots offer no XP token
  local maxdd = controls["widget.maxSlots.1"].widget
  T.eq(ui.FindMenuItem(rawget(maxdd, "_root"), ns.Tokens.Label("eta")), nil)
  -- sliders
  local width = controls["widget.width"].widget
  width:SetValue(300)
  T.eq(ns.settings.widget.width, 300)
  local scale = controls["widget.scale"].widget
  scale:SetValue(150)
  T.near(ns.settings.widget.scale, 1.5, 1e-6)
  -- checkbox
  local cb = controls["exclude.afk"].widget
  cb:GetScript("OnClick")(cb)
  T.eq(ns.settings.exclude.afk, true)
  cb:GetScript("OnClick")(cb)
  T.eq(ns.settings.exclude.afk, false)
  -- synced from outside while shown, not while hidden
  ns.Core.SetSetting("widget.width", 500)
  T.eq(width:GetValue(), 500)
  ui.CloseSettings()
  ns.Core.SetSetting("widget.width", 200)
  T.eq(width:GetValue(), 500, "no sync while hidden")
  ns.Options.Open()
  T.eq(width:GetValue(), 200, "synced again on show")
end)

T.test("options panel: fallback controls when the templates are absent", function()
  local ns = Start({ ui = { modern = false } })
  ns.Options.Open()
  local controls = rawget(Stub.ui.categories[1].frame, "controls")
  T.ok(type(controls) == "table")
  local b = controls["widget.style"].widget
  b:GetScript("OnClick")(b, "LeftButton")
  T.eq(ns.settings.widget.style, "box")
  b:GetScript("OnClick")(b, "RightButton")
  T.eq(ns.settings.widget.style, "bar")
  local tau = controls["rateTau"].widget
  tau:GetScript("OnClick")(tau, "LeftButton")         -- normal (3600) -> fast (1200)
  T.eq(ns.settings.rateTau, 1200)
  local s = controls["widget.width"].widget
  s:GetScript("OnValueChanged")(s, 304)               -- snapped to the 10 px step
  T.eq(ns.settings.widget.width, 300)
  local sc = controls["widget.scale"].widget
  sc:GetScript("OnValueChanged")(sc, 75)
  T.near(ns.settings.widget.scale, 0.75, 1e-6)
  local fsz = controls["widget.fontSize"].widget
  fsz:GetScript("OnValueChanged")(fsz, 13)
  T.eq(ns.settings.widget.fontSize, 13)
end)

T.test("erase: confirmation popup, accepting it resets the record", function()
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = OtherRecord() } } })
  ns.Options.Open()
  local np = #Stub.popups
  ns.Options.ConfirmErase(OTHER_GUID)
  T.eq(#Stub.popups, np + 1)
  local which, data = LastPopup()
  T.eq(which, "TRUEPLAYED_ERASE_CHAR")
  T.eq(data, OTHER_GUID)
  T.ok(find(Stub.popups[#Stub.popups].text_arg1 or "", "Tamar", 1, true) ~= nil, "popup names the character")
  StaticPopupDialogs.TRUEPLAYED_ERASE_CHAR.OnAccept(nil, data)
  T.eq(ns.db.chars[OTHER_GUID], nil, "record erased after confirmation")
  T.ok(ns.db.chars[Stub.player.guid] ~= nil, "current record untouched")
end)

T.test("retained memory with the bar visible stays bounded", function()
  local ns = Start({ ui = { ldb = false } })
  Stub.Advance(300)
  collectgarbage("collect")
  local before = collectgarbage("count")
  Stub.Advance(20000)
  collectgarbage("collect")
  local growth = collectgarbage("count") - before
  T.ok(growth < 16, format("retained growth %.2f KB over 20000 ticks (budget 16 KB)", growth))
  T.ok(ns.Tokens.IsActive())
end)

---------------------------------------------------------------------------
-- Statistics window (requirement B)
---------------------------------------------------------------------------

T.test("window: lazy, view switch, reset to current at Show, erase any record", function()
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = OtherRecord() } } })
  local L = ns.L
  Stub.Advance(15)
  T.eq(rawget(_G, "TruePlayedStatsFrame"), nil, "window is lazy")
  ns.Window.Show()
  local wf = rawget(_G, "TruePlayedStatsFrame")
  T.ok(wf ~= nil)
  local listed = false
  for i = 1, #UISpecialFrames do
    if UISpecialFrames[i] == "TruePlayedStatsFrame" then listed = true end
  end
  T.ok(listed, "Escape closes the window")
  local tp = wf.tp
  local curLabel = tp.viewText:GetText()
  T.match(curLabel, "Lutak")
  T.no(find(tp.footer1:GetText(), "104d", 1, true), "current view: only the current character")

  ns.Window.SetView(OTHER_GUID)
  T.match(tp.viewText:GetText(), "Tamar")
  T.ok(find(tp.footer1:GetText(), "104d", 1, true) ~= nil, "other view shows the other record")
  local np = #Stub.popups
  tp.erase:GetScript("OnClick")(tp.erase)
  T.eq(#Stub.popups, np + 1)
  local which, data = LastPopup()
  T.eq(which, "TRUEPLAYED_ERASE_CHAR")
  T.eq(data, OTHER_GUID)

  ns.Window.Toggle("zones")
  T.ok(ns.Window.IsShown())
  ns.Window.Toggle("sessions")
  ns.Window.SetView("account")
  T.eq(tp.viewText:GetText(), L.VIEW_ACCOUNT)
  T.eq(tp.empty:GetText(), L.NO_SESSIONS_ACCOUNT)
  ns.Window.Toggle("levels")
  ns.Window.Toggle("zones")

  ns.Window.Hide()
  T.no(ns.Window.IsShown())
  ns.Window.Show()
  T.eq(tp.viewText:GetText(), curLabel, "Show resets the view to the current character")

  -- arrows: current -> other -> account -> current
  tp.next:GetScript("OnClick")(tp.next)
  T.match(tp.viewText:GetText(), "Tamar")
  tp.next:GetScript("OnClick")(tp.next)
  T.eq(tp.viewText:GetText(), L.VIEW_ACCOUNT)
  tp.next:GetScript("OnClick")(tp.next)
  T.eq(tp.viewText:GetText(), curLabel)
  tp.prev:GetScript("OnClick")(tp.prev)
  T.eq(tp.viewText:GetText(), L.VIEW_ACCOUNT)

  -- erasing the viewed record falls back to the current character
  ns.Window.SetView(OTHER_GUID)
  ns.Core.ResetChar(OTHER_GUID)
  T.eq(tp.viewText:GetText(), curLabel)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("window: live cells update while shown, nothing while hidden", function()
  local ns = Start()
  Stub.Advance(15)
  ns.Window.Show()
  local tp = rawget(_G, "TruePlayedStatsFrame").tp
  local row = tp.rows[1]
  T.ok(row ~= nil, "current level row")
  local cell = tp.cells[row][2]
  local c0 = SetTextCount(cell)
  Stub.Advance(180)
  T.ok(SetTextCount(cell) > c0, "in-progress level time refreshed")
  ns.Window.Hide()
  local c1 = SetTextCount(cell)
  Stub.Advance(180)
  T.eq(SetTextCount(cell), c1, "no refresh while hidden")
end)

---------------------------------------------------------------------------
-- Broker, compartment, isolation
---------------------------------------------------------------------------

T.test("broker: LDB text assigned only on change, clicks and tooltip", function()
  local ns = Start({ ui = { ldb = true } })
  local obj = Stub.ui.ldbObjects["TruePlayed"]
  T.ok(obj ~= nil, "data object created")
  T.ok(ns.Broker.obj == obj)
  T.eq(obj.type, "data source")
  Stub.Advance(300)
  local sets = Stub.ui.ldbTextSets
  Stub.Advance(60)
  T.eq(Stub.ui.ldbTextSets, sets, "no assignment while the text is unchanged")
  ns.Core.SetSetting("widget.slots.1", "session")
  Stub.Advance(130)
  T.ok(Stub.ui.ldbTextSets > sets)
  T.ok(find(obj.text, Frag(ns.L.PFX_SESSION_FMT), 1, true) ~= nil)
  Stub.RunSlash("hide")
  T.ok(ns.Tokens.IsActive(), "broker stays a consumer when the bar is hidden")
  obj.OnClick(nil, "LeftButton")
  T.ok(ns.Window.IsShown())
  obj.OnClick(nil, "RightButton")
  T.eq(Stub.ui.menus, 1)
  GameTooltip:ClearLines()
  obj.OnTooltipShow(GameTooltip)
  T.ok(#GameTooltip._lines > 3)
end)

T.test("no LibStub: no broker object", function()
  local ns = Start({ ui = { ldb = false } })
  T.eq(ns.Broker.obj, nil)
end)

T.test("compartment entry points once ready", function()
  local ns = Start()
  TruePlayed_OnAddonCompartmentClick("TruePlayed", "RightButton", nil)
  T.ok(ns.Window.IsShown())
  TruePlayed_OnAddonCompartmentClick("TruePlayed", "LeftButton", nil)
  T.eq(Stub.ui.opened, 1)
  local btn = CreateFrame("Frame", nil, UIParent)
  TruePlayed_OnAddonCompartmentEnter("TruePlayed", btn)
  T.ok(ns.Tooltip.IsShownFor(btn))
  TruePlayed_OnAddonCompartmentLeave("TruePlayed", btn)
  T.no(ns.Tooltip.IsShownFor(btn))
  TruePlayed_OnAddonCompartmentEnter("TruePlayed", nil)
  TruePlayed_OnAddonCompartmentLeave(nil, nil)
end)

T.test("isolation: the bar shows only the current character", function()
  local ns = Start({ ui = { ldb = false }, db = {
    schema = 1,
    settings = { widget = { slots = { "played", "level_time", "zone_time" } } },
    chars = { [OTHER_GUID] = OtherRecord() },
  } })
  Stub.Advance(20)
  local tp = Widget().tp
  T.ok(find(tp.slots[1]:GetText(), Frag(ns.L.PFX_PLAYED_FMT), 1, true) ~= nil)
  for i = 1, 3 do
    T.no(find(tp.slots[i]:GetText(), "104d", 1, true), "slot " .. i .. " ignores the other record")
  end
end)

---------------------------------------------------------------------------
-- Review fixes: window content, row tooltips, plurals, hints, layouts
---------------------------------------------------------------------------

-- Lines of the GameTooltip mock as { left, right } pairs.
local function TipLines()
  local out = {}
  local lines = GameTooltip._lines or {}
  for i = 1, #lines do out[i] = { lines[i][1], lines[i][2] } end
  return out
end

local function FindLine(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i], i end
  end
  return nil
end

local function StatsTP()
  return rawget(_G, "TruePlayedStatsFrame").tp
end

-- First visible row of the statistics window whose first cell is `text`.
local function RowWith(tp, text)
  for i = 1, #tp.rows do
    local row = tp.rows[i]
    if row:IsShown() and tp.cells[row][1]:GetText() == text then return row end
  end
  return nil
end

local function Cells(tp, row)
  local c = tp.cells[row]
  return { c[1]:GetText(), c[2]:GetText(), c[3]:GetText(), c[4]:GetText(), c[5]:GetText() }
end

-- OtherRecord plus Orgrimmar (1454): 600 s in the city, 100 s of it AFK, at level 29.
local function RecordWithCity()
  local rec = OtherRecord()
  rec.levels[29].z[1454] = { s = { c = 600, C = 100 }, xp = 0 }
  rec.zones[1454] = { s = { c = 600, C = 100 }, xp = 0, name = "Orgrimmar" }
  return rec
end

-- "1 characters", "1 niveaux"... (a count of one followed by a plural noun).
local PLURAL_WORDS = { "characters", "personnages", "levels", "niveaux", "zones", "sessions" }
local function BadPlural(s)
  if type(s) ~= "string" then return nil end
  for i = 1, #PLURAL_WORDS do
    local w = PLURAL_WORDS[i]
    if find(s, "^1 " .. w) or find(s, "[^%d]1 " .. w) then return w end
  end
  return nil
end

T.test("window: XP gains rebuild at most every 30 s, never for another character", function()
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = OtherRecord() } } })
  Stub.Advance(15)
  local Window = ns.Window
  Window.Show("zones")
  local orig = Window.Refresh
  local calls = 0
  Window.Refresh = function(...)
    calls = calls + 1
    return orig(...)
  end
  local function Play(ticks)
    for t = 1, ticks do
      if t % 20 == 0 then Stub.GrantXP(40) end
      Stub.Advance(1)
    end
  end
  Play(300)
  T.ok(calls >= 1, "XP gains still reach the window")
  T.ok(calls <= 10, format("%d full rebuilds in 300 ticks with XP every 20 s (budget 10)", calls))
  Window.SetView(OTHER_GUID)
  calls = 0
  Play(300)
  T.eq(calls, 0, "our XP never changes another character's data")
  Window.Refresh = orig
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("window: hovering a level row lists that level's zones, exclusions applied", function()
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = RecordWithCity() } } })
  local L, Fmt = ns.L, ns.Fmt
  Stub.Advance(15)
  ns.Window.Show("levels", OTHER_GUID)
  local tp = StatsTP()
  T.match(tp.viewText:GetText(), "Tamar")
  T.ok(tp.hint:IsShown(), "the Levels tab says that rows can be hovered")
  T.eq(tp.hint:GetText(), L.LEVELS_HOVER_HINT)
  local row = RowWith(tp, "29")
  T.ok(row ~= nil, "level 29 row")
  row:GetScript("OnEnter")(row)
  T.ok(GameTooltip:GetOwner() == row, "a normal (not approximate) level has a tooltip")
  local lines = TipLines()
  T.eq(lines[1][1], format(L.TT_LEVEL_ROW_FMT, 29))
  T.ok(FindLine(lines, format(L.ROW_ZONES_FMT, 29)) ~= nil, "zones header")
  local tanaris = FindLine(lines, "Tanaris")
  T.ok(tanaris ~= nil, "Tanaris listed")
  T.eq(tanaris[2], Fmt.Duration(8000))
  local org = FindLine(lines, "Orgrimmar " .. L.CITY_MARK)
  T.ok(org ~= nil, "the capital is listed with the city mark")
  T.eq(org[2], Fmt.Duration(700))
  row:GetScript("OnLeave")(row)
  T.no(GameTooltip:IsShown())

  ns.Core.SetSetting("exclude.city", true)
  row = RowWith(tp, "29")
  row:GetScript("OnEnter")(row)
  lines = TipLines()
  local _, iT = FindLine(lines, "Tanaris")
  local iO
  org, iO = FindLine(lines, "Orgrimmar " .. L.CITY_MARK)
  T.ok(iT ~= nil, "Tanaris still listed")
  T.eq(org[2], "-", "excluded time shows a dash")
  T.ok(iO > iT, "the excluded capital comes last")
  row:GetScript("OnLeave")(row)

  -- the current character's level rows have it too (never another record's zones)
  ns.Window.SetView("current")
  row = tp.rows[1]
  row:GetScript("OnEnter")(row)
  lines = TipLines()
  T.ok(FindLine(lines, format(L.ROW_ZONES_FMT, 10)) ~= nil, "current level zones header")
  T.no(FindLine(lines, "Tanaris"), "no zone of the other record")
  row:GetScript("OnLeave")(row)

  -- account rows and other tabs: no level tooltip, no hint
  ns.Window.SetView("account")
  T.no(tp.hint:IsShown(), "no hint in the account view")
  row = tp.rows[1]
  GameTooltip:Hide()
  row:GetScript("OnEnter")(row)
  T.no(GameTooltip:GetOwner() == row, "account rows have no level tooltip")
  ns.Window.SetView("current")
  ns.Window.Toggle("zones")
  T.no(tp.hint:IsShown(), "no hint in the Zones tab")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("window: zones tab shows filtered, raw and AFK times and the capitals block", function()
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = RecordWithCity() } } })
  local L, Fmt = ns.L, ns.Fmt
  Stub.Advance(15)
  ns.Window.Show("zones", OTHER_GUID)
  local tp = StatsTP()
  T.eq(tp.cells[tp.rows[1]][1]:GetText(), L.SECTION_CONTINENTS, "continents block first")
  T.eq(Cells(tp, tp.rows[2]), { "Kalimdor", Fmt.Duration(9000700), Fmt.Duration(9000700), Fmt.Duration(100), "" })
  T.eq(tp.cells[tp.rows[3]][1]:GetText(), L.CITIES_HEADER, "then the capitals block")
  local cap = RowWith(tp, "Orgrimmar")
  T.eq(Cells(tp, cap), { "Orgrimmar", Fmt.Duration(700), Fmt.Duration(700), Fmt.Duration(100), "" })
  local tan = RowWith(tp, "Tanaris")
  T.eq(Cells(tp, tan), { "Tanaris", Fmt.Duration(9000000), Fmt.Duration(9000000), "-", Fmt.Number(500000) })
  T.ok(RowWith(tp, "Orgrimmar " .. L.CITY_MARK) ~= nil, "the capital is also in the list, marked")

  ns.Core.SetSetting("exclude.city", true)
  cap = RowWith(tp, "Orgrimmar")
  T.eq(Cells(tp, cap), { "Orgrimmar", "-", Fmt.Duration(700), Fmt.Duration(100), "" },
    "capitals block: counted time under the exclusions, then raw")
  T.eq(Cells(tp, RowWith(tp, "Kalimdor")), { "Kalimdor", Fmt.Duration(9000000), Fmt.Duration(9000700),
    Fmt.Duration(100), "" }, "continents: city time left out, raw kept")
  local listed = Cells(tp, RowWith(tp, "Orgrimmar " .. L.CITY_MARK))
  T.eq(listed[2], "-")
  T.eq(listed[3], Fmt.Duration(700))

  ns.Core.SetSetting("exclude.city", false)
  ns.Core.SetSetting("exclude.afk", true)
  cap = RowWith(tp, "Orgrimmar")
  T.eq(Cells(tp, cap)[2], Fmt.Duration(600), "AFK part of the capital left out")
end)

T.test("window: the header names the active exclusions", function()
  local ns = Start()
  Stub.Advance(15)
  ns.Window.Show()
  local tp = StatsTP()
  T.eq(tp.filter:GetText(), "")
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(tp.filter:GetText(), format(ns.L.WIN_FILTER_FMT, ns.Stats.MaskLabel(1)))
  ns.Core.SetSetting("exclude.city", true)
  T.eq(tp.filter:GetText(), format(ns.L.WIN_FILTER_FMT, ns.Stats.MaskLabel(5)))
  ns.Core.SetSetting("exclude.afk", false)
  ns.Core.SetSetting("exclude.city", false)
  T.eq(tp.filter:GetText(), "")
end)

T.test("compartment tooltip names the compartment clicks; the bar keeps its hint", function()
  local ns = Start({ ui = { ldb = false } })
  local L = ns.L
  T.ok(L.TT_HINT_COMPARTMENT ~= L.TT_HINT)
  local btn = CreateFrame("Frame", nil, UIParent)
  TruePlayed_OnAddonCompartmentEnter("TruePlayed", btn)
  local lines = TipLines()
  T.eq(lines[#lines][1], L.TT_HINT_COMPARTMENT)
  Stub.Advance(1)                                    -- TICK redraw
  lines = TipLines()
  T.eq(lines[#lines][1], L.TT_HINT_COMPARTMENT, "kept on refresh")
  TruePlayed_OnAddonCompartmentLeave("TruePlayed", btn)
  local f = Widget()
  f:GetScript("OnEnter")(f)
  lines = TipLines()
  T.eq(lines[#lines][1], L.TT_HINT, "the bar tooltip keeps the bar hint")
  f:GetScript("OnLeave")(f)
end)

for _, locale in ipairs({ "enUS", "frFR" }) do
  T.test("plurals: a count of one is singular (" .. locale .. ")", function()
    local ns = Start({ locale = locale })
    local L, Fmt = ns.L, ns.Fmt
    Stub.Advance(15)
    GameTooltip:ClearLines()
    ns.Tooltip.Fill(GameTooltip, true)
    local lines = TipLines()
    T.ok(FindLine(lines, format(L.TT_ACCOUNT_ONE_FMT, 1)) ~= nil, "singular account line")
    for i = 1, #lines do
      T.no(BadPlural(lines[i][1]), "tooltip: " .. tostring(lines[i][1]))
      T.no(BadPlural(lines[i][2]), "tooltip: " .. tostring(lines[i][2]))
    end
    ns.Window.Show("levels", "account")
    local tp = StatsTP()
    local one = format(L.TT_ACCOUNT_ONE_FMT, 1)
    T.eq(tp.footer1:GetText():sub(1, #one), one, "account view footer")
    T.eq(tp.footer2:GetText(), L.FOOTER_ACCOUNT_NONE, "no complete level yet: no count")
    T.no(BadPlural(tp.footer1:GetText()))
    local n = #Stub.printed
    Stub.RunSlash("perf")
    for i = n + 1, #Stub.printed do
      T.no(BadPlural(Stub.printed[i]), "/tpl perf: " .. Stub.printed[i])
    end
    -- one other character with a complete level: singular, with the average
    ns.db.chars[OTHER_GUID] = OtherRecord()
    ns.Window.Refresh()
    T.eq(tp.footer2:GetText(), format(L.FOOTER_ACCOUNT_ONE_FMT, Fmt.Duration(8000), 1))
  end)
end

T.test("options: dropdown menus are regenerated only when their value changed", function()
  local ns = Start({ ui = { modern = true } })
  local ui = Stub.ui
  ns.Options.Open()
  local controls = rawget(ui.categories[1].frame, "controls")
  local base = ui.generateMenus
  local width = controls["widget.width"].widget
  for v = 150, 600, 10 do width:SetValue(v) end
  T.eq(ui.generateMenus, base, "dragging the width slider regenerates no menu")
  local dd = controls["widget.style"].widget
  ui.ClickMenuItem(ui.FindMenuItem(rawget(dd, "_root"), ns.L.STYLE_BOX))
  T.ok(ui.generateMenus - base <= 1, "one changed value: one menu at most")
  base = ui.generateMenus
  ns.Core.SetSetting("widget.slots.1", "played")        -- changed elsewhere (/tpl, menu)
  T.eq(ui.generateMenus, base + 1, "the changed dropdown follows")
  local item = ui.FindMenuItem(rawget(controls["widget.slots.1"].widget, "_root"), ns.Tokens.Label("played"))
  T.ok(ui.IsChecked(item))
end)

T.test("box style: slots 2 and 3 share the second row without overlapping", function()
  local ns = Start({ ui = { ldb = false }, locale = "frFR" })
  ns.Core.SetSetting("widget.slots.2", "played")
  ns.Core.SetSetting("widget.slots.3", "played_server")
  ns.Core.SetSetting("widget.fontSize", 16)
  ns.Core.SetSetting("widget.style", "box")
  Stub.Advance(20)
  local tp = Widget().tp
  local s2, s3 = tp.slots[2], tp.slots[3]
  T.ok(s2:GetWidth() > 0 and s3:GetWidth() > 0, "bounded widths")
  T.ok(s2:GetWidth() + s3:GetWidth() <= 180 - 2 * 6, "the two halves fit in the box")
  ns.Core.SetSetting("widget.style", "bar")
  T.eq(s2:GetWidth(), 0, "bar style: free width again")
  T.eq(s3:GetWidth(), 0)
end)

---------------------------------------------------------------------------
-- Bar geometry (feedback 1): nothing overlaps or leaves the bar, at any width, font
-- size, locale or pause state; the bottom right part degrades in steps.
---------------------------------------------------------------------------

local PAD = 8

-- Horizontal extents (frame coordinates) of every drawn element of a bar style row.
local function Add(items, name, l, r) items[#items + 1] = { name = name, l = l, r = r } end
local function Drawn(fs) return fs:IsShown() and (fs:GetText() or "") ~= "" end

local function BottomItems(tp)
  local items = {}
  Add(items, "level", PAD, PAD + tp.bl:GetStringWidth())
  if tp.marker:IsShown() then
    local _, _, _, x = tp.marker:GetPoint(1)
    Add(items, "marker", x, x + tp.marker:GetStringWidth())
  end
  if Drawn(tp.brx) then
    local _, _, _, x = tp.brx:GetPoint(1)
    Add(items, "xp", x - tp.brx:GetStringWidth(), x)
  end
  if Drawn(tp.sep) then
    local _, _, _, x = tp.sep:GetPoint(1)
    Add(items, "sep", x - tp.sep:GetStringWidth(), x)
  end
  local s2 = tp.slots[2]
  if Drawn(s2) then
    local _, _, _, x = s2:GetPoint(1)
    local l = x - s2:GetStringWidth()
    Add(items, "slot2", l, x)
    if tp.marks[2]:IsShown() then Add(items, "mark2", l - 10, l - 3) end
  end
  return items
end

local function TopItems(tp)
  local items = {}
  local s1, s3 = tp.slots[1], tp.slots[3]
  if Drawn(s1) then
    local _, _, _, x = s1:GetPoint(1)
    local w = s1:GetStringWidth()
    local bound = s1:GetWidth()
    if bound and bound > 0 and bound < w then w = bound end
    Add(items, "slot1", x - w, x)
    if tp.marks[1]:IsShown() then Add(items, "mark1", x - w - 10, x - w - 3) end
  end
  if Drawn(s3) then
    local point, _, _, x = s3:GetPoint(1)
    local w = s3:GetStringWidth()
    if point == "BOTTOM" then
      Add(items, "slot3", x - w / 2, x + w / 2)
      if tp.marks[3]:IsShown() then Add(items, "mark3", x - w / 2 - 10, x - w / 2 - 3) end
    else
      Add(items, "slot3", x, x + w)
      if tp.marks[3]:IsShown() then Add(items, "mark3", x + w + 3, x + w + 10) end
    end
  end
  return items
end

-- Every item inside [PAD, PAD + W], sorted items apart by >= 3 px (>= 6 px after the
-- level text, >= 8 px between slot 3 and slot 1).
local function CheckRow(items, W, what)
  table.sort(items, function(a, b) return a.l < b.l end)
  for i = 1, #items do
    local it = items[i]
    T.ok(it.l >= PAD - 0.5 and it.r <= PAD + W + 0.5,
      format("%s: %s [%.1f, %.1f] inside [%d, %d]", what, it.name, it.l, it.r, PAD, PAD + W))
    if i > 1 then
      local prev = items[i - 1]
      local gap = 3
      if prev.name == "level" then gap = 6 end
      if (prev.name == "slot3" or prev.name == "mark3") and (it.name == "slot1" or it.name == "mark1") then gap = 8 end
      T.ok(it.l >= prev.r + gap - 0.5,
        format("%s: %s (%.1f) at least %d px after %s (%.1f)", what, it.name, it.l, gap, prev.name, prev.r))
    end
  end
end

local function CheckBar(ns, tp, what)
  local W = ns.settings.widget.width
  CheckRow(BottomItems(tp), W, what .. " bottom")
  CheckRow(TopItems(tp), W, what .. " top")
end

local SLOT_SETS = {
  { "eta", "xph", "fps_latency", "center" },
  { "xpleft", "avg_level", "played_server", "center" },   -- long French texts
  { "played", "xpleft", "zone_time", "left" },
  { "none", "played", "session", "center" },
}

for _, locale in ipairs({ "frFR", "enUS" }) do
  T.test("bar geometry: no overlap at any width, font size and pause state (" .. locale .. ")", function()
    local ns = Start({ ui = { ldb = false }, locale = locale, level = 42 })
    Stub.GrantXP(math.floor(Stub.player.max * 0.12) + 7)
    Stub.Advance(5)
    local tp = Widget().tp
    local checked = 0
    for _, set in ipairs(SLOT_SETS) do
      ns.Core.SetSetting("widget.slots.1", set[1])
      ns.Core.SetSetting("widget.slots.2", set[2])
      ns.Core.SetSetting("widget.slots.3", set[3])
      ns.Core.SetSetting("widget.slot3Pos", set[4])
      for _, paused in ipairs({ false, true }) do
        ns.Core.SetSetting("exclude.afk", paused)
        Stub.SetAFK(paused)
        Stub.Advance(1)
        for _, size in ipairs({ 9, 11, 16 }) do
          ns.Core.SetSetting("widget.fontSize", size)
          for W = 150, 600, 30 do
            ns.Core.SetSetting("widget.width", W)
            Stub.Advance(1)
            CheckBar(ns, tp, format("%s %s/%s/%s paused=%s size=%d W=%d", locale, set[1], set[2], set[3],
              tostring(paused), size, W))
            checked = checked + 1
          end
        end
      end
    end
    T.ok(checked >= 300, "configurations checked")
    T.eq(Stub.onUpdateCount, 0)
  end)
end

T.test("bar geometry: random slots, positions, sizes and states never overlap (frFR)", function()
  local ns = Start({ ui = { ldb = false }, locale = "frFR", level = 57 })
  Stub.GrantXP(191234)
  Stub.Advance(5)
  local tp = Widget().tp
  local ORDER = ns.Tokens.ORDER
  local rnd = T.rng(20260930)
  local function Pick(list) return list[1 + math.floor(rnd() * #list)] end
  for n = 1, 150 do
    for i = 1, 3 do ns.Core.SetSetting("widget.slots." .. i, Pick(ORDER)) end
    ns.Core.SetSetting("widget.slot3Pos", Pick({ "center", "left" }))
    ns.Core.SetSetting("widget.pctPos", Pick({ "follow", "follow", "level" }))
    ns.Core.SetSetting("widget.fontSize", 9 + math.floor(rnd() * 8))
    ns.Core.SetSetting("widget.width", 150 + 10 * math.floor(rnd() * 46))
    local paused = rnd() < 0.5
    ns.Core.SetSetting("exclude.afk", paused)
    Stub.SetAFK(paused)
    if rnd() < 0.2 then Stub.GrantXP(math.floor(rnd() * 900)) end
    Stub.fps = 20 + math.floor(rnd() * 200)
    Stub.Advance(1)
    CheckBar(ns, tp, "random #" .. n)
  end
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("bar bottom row: separator at the default width, then short numbers, no label, no slot 2", function()
  local ns = Start({ ui = { ldb = false }, locale = "frFR", level = 42 })
  local L = ns.L
  Stub.GrantXP(12345)
  Stub.Advance(5)
  local tp = Widget().tp
  local max = Stub.player.max
  local full = format(L.XP_FMT, ns.Fmt.Number(12345), ns.Fmt.Number(max))
  T.eq(tp.brx:GetText(), full, "full XP text at the default width")
  T.ok(tp.sep:IsShown(), "separator between the XP text and slot 2")
  T.eq(tp.sep:GetText(), "\194\183")
  T.ok(tp.slots[2]:IsShown())
  local seen = {}
  for W = 600, 150, -10 do
    ns.Core.SetSetting("widget.width", W)
    ns.Core.SetSetting("widget.fontSize", 16)
    local t = tp.brx:IsShown() and tp.brx:GetText() or "(none)"
    local state = t .. "|" .. tostring(tp.slots[2]:IsShown())
    if not seen[state] then seen[#seen + 1] = state; seen[state] = true end
    CheckBar(ns, tp, "W=" .. W)
  end
  -- the steps, in order: full, short numbers (12,3k / 101k), no label, no slot 2
  T.eq(max, 101000)
  local short = format(L.XP_FMT, "12,3k", "101k")
  local bare = format(L.XP_BARE_FMT, "12,3k", "101k")
  local order = { full .. "|true", short .. "|true", bare .. "|true", bare .. "|false" }
  local k = 1
  for i = 1, #seen do
    if seen[i] == order[k] then k = k + 1 end
  end
  T.eq(k, 5, "full -> short -> bare -> bare without slot 2: " .. table.concat(seen, " ; "))
  T.eq(ns.Bar.Compact(58), "58")
  T.eq(ns.Bar.Compact(23200), "23,2k")
  T.eq(ns.Bar.Compact(23000), "23k")
  T.eq(ns.Bar.Compact(209800), "210k")
end)

T.test("bar percent: one decimal like the tooltip, 99.9 % until the level-up, 0.0 % at 0 XP", function()
  local ns = Start({ ui = { ldb = false }, locale = "frFR" })
  local L = ns.L
  local tp = Widget().tp
  Stub.Advance(2)
  T.eq(tp.marker:GetText(), "0,0 %", "0 XP")
  local function TooltipPct()
    GameTooltip:ClearLines()
    ns.Tooltip.Fill(GameTooltip, false)
    local line = FindLine(TipLines(), format(L.TT_LEVEL_FMT, 10, 11))
    return line and line[2]
  end
  T.eq(TooltipPct(), "0,0 %")
  Stub.GrantXP(19)                                 -- 19 / 7600 = 0.25 % -> 0,3 %
  Stub.Advance(1)
  T.eq(tp.marker:GetText(), "0,3 %")
  T.eq(TooltipPct(), "0,3 %")
  Stub.GrantXP(7596 - 19)                          -- 99.947 % -> 99,9 %
  Stub.Advance(1)
  T.eq(tp.marker:GetText(), "99,9 %")
  T.eq(TooltipPct(), "99,9 %")
  Stub.GrantXP(3)                                  -- 7599 / 7600 = 99.987 %: never 100,0 %
  Stub.Advance(1)
  T.eq(tp.marker:GetText(), "99,9 %")
  T.eq(TooltipPct(), "99,9 %")
  CheckBar(ns, tp, "99.9 %")
  -- the level form shows the same text
  ns.Core.SetSetting("widget.pctPos", "level")
  T.eq(tp.bl:GetText(), format(L.LEVEL_PCT_FMT, 10, "99,9 %"))
  T.no(tp.marker:IsShown())
  ns.Core.SetSetting("widget.pctPos", "follow")
  T.ok(tp.marker:IsShown())
  T.eq(ns.Tokens.PercentText(ns.Tokens.PercentTenths(23195, 23200)), "99,9 %", "99.978 %")
  T.eq(ns.Tokens.PercentText(ns.Tokens.PercentTenths(23200, 23200)), "100,0 %", "level complete")
  T.eq(ns.Tokens.PercentText(ns.Tokens.PercentTenths(58, 23200)), "0,3 %")
end)

T.test("bar percent at the level: a level text wider than the bar drops its percent", function()
  local ns = Start({ ui = { ldb = false }, locale = "frFR", level = 59 })
  local L = ns.L
  Stub.GrantXP(208766)                             -- 99.507 % -> 99,5 %
  Stub.Advance(5)
  local tp = Widget().tp
  local withPct = format(L.LEVEL_PCT_FMT, 59, ns.Tokens.PercentText(ns.Tokens.PercentTenths(208766, 209800)))
  local methods = getmetatable(tp.bl).__index
  local orig = methods.GetStringWidth
  -- widths that grow with the font size (the stub counts 6 px per character at any size)
  methods.GetStringWidth = function(self)
    local _, size = self:GetFont()
    return orig(self) * (size or 12) / 9
  end
  local ok, err = pcall(function()
    ns.Core.SetSetting("widget.pctPos", "level")
    ns.Core.SetSetting("widget.fontSize", 16)
    T.eq(tp.bl:GetText(), withPct, "default width: level and percent")
    ns.Core.SetSetting("widget.width", 150)
    T.eq(tp.bl:GetText(), format(L.LEVEL_SHORT_FMT, 59), "narrow bar, big font: the level alone")
    T.ok(tp.bl:GetStringWidth() <= 150, "inside the bar")
    CheckBar(ns, tp, "W=150 size=16 pctPos=level")
    ns.Core.SetSetting("widget.width", 360)
    T.eq(tp.bl:GetText(), withPct, "back to level and percent")
  end)
  methods.GetStringWidth = orig
  if not ok then error(err, 0) end
end)

---------------------------------------------------------------------------
-- Feedback 1: the user's own SavedVariables (druid level 20, 58 / 23 200 XP, 1 d 13 h
-- of /played before the install, standing in Thunder Bluff, the three exclusions on)
---------------------------------------------------------------------------

local USER_GUID = "Player-4619-00C0FFEE"

local function UserDB()
  local ema = {}
  local d = { 64.47661824730345, 64.47661824730345, 61.80137601073682, 61.80137601073682,
              2.721970436125817, 2.721970436125817, 0, 0 }
  for i = 1, 8 do ema[i] = { a = 0, r = 0, q = 0, d = d[i] } end
  return {
    xpMax = { [20] = 23200 }, createdAt = 1790799275, lastVersion = "0.1.0-test", cities = {}, schema = 1,
    settings = {
      rateTau = 3600, debug = false, exclude = { inn = false, afk = false, city = false },
      hidePlayedMsg = false, firstRunDone = true, requestPlayedAtLogin = true,
      widget = {
        scale = 1, fontSize = 11, point = { "CENTER", "CENTER", 0, -220 }, style = "bar", shown = true,
        background = true, slots = { "eta", "xph", "fps_latency" }, fade = false, locked = false,
        combatHide = false, hideAtMax = false, maxSlots = { "session", "played", "fps_latency" },
        height = 8, slot3Pos = "center", pctPos = "follow", width = 360,
      },
    },
    chars = {
      [USER_GUID] = {
        last = { at = 1790799340, key = "c", zone = 1456, level = 20, g = 649327.767 },
        guid = USER_GUID, sessions = {}, class = "DRUID",
        levels = {
          [20] = { partial = true, s = { u = 30328, c = 63, i = 2 }, xa = 0, xr = 0, d = 0, xp = 0, xq = 0,
                   z = { [1414] = { s = { i = 2 }, xp = 0 }, [1456] = { s = { c = 63 }, xp = 0 } },
                   max = 23200, srvStart = 104914 },
        },
        level = 20, base = { at = 1790799277, total = 135243, level = 20 }, realm = "Classic Beta PvP",
        zones = { [1414] = { name = "Kalimdor", xp = 0, s = { i = 2 } },
                  [1456] = { name = "Thunder Bluff", xp = 0, s = { c = 63 } } },
        cur = { at = 1790799340, p0 = 0.003, t0 = 1790799275, g = 649327.767, s = { i = 2, c = 63 },
                d = 0, xp = 0, l0 = 20 },
        ema = ema,
        xpSnap = { at = 1790799340, max = 23200, level = 20, rest = 0, xp = 58 },
        life = { est = 0, s = { u = 135242, c = 63, i = 2 }, xa = 0, xr = 0, d = 0, xp = 0, xq = 0 },
        name = "Lutak", faction = "Horde", firstSeen = 1790799275,
        srv = { at = 1790799340, total = 135306, levelPlayed = 30392, level = 20, g = 649327.767, ext = true },
        lastSeen = 1790799340, surname = "Brisevent",
      },
    },
  }
end

-- Logs the user's character in, in Thunder Bluff, the three exclusions on.
local function StartUser(opts)
  opts = opts or {}
  Stub.maps[1456] = { mapType = 3, parentMapID = 1414, name = "Thunder Bluff" }
  local p = Stub.player
  p.guid, p.name, p.surname, p.realm, p.class = USER_GUID, "Lutak", "Brisevent", "Classic Beta PvP", "DRUID"
  p.level, p.xp, p.max, p.rest = 20, 58, 23200, 0
  p.mapID, p.zoneText, p.resting = 1456, "Thunder Bluff", true
  Stub.server.total, Stub.server.levelPlayed = 135306, 30392
  local db = UserDB()
  if opts.prior then db.chars[USER_GUID].prior = opts.prior end
  local ns = Start({ ui = opts.ui or { ldb = false }, locale = "frFR", db = db })
  ns.Core.SetSetting("exclude.afk", true)
  ns.Core.SetSetting("exclude.inn", true)
  ns.Core.SetSetting("exclude.city", true)
  Stub.Advance(15)
  return ns
end

-- Pre-install estimate of the druid (R3, C3, prior v2): the completed levels only, the
-- 167 200 XP of levels 1-19 in the 104 914 s played before level 20, ~5,7k/h (the
-- lifetime /played of v1 gave ~4,5k/h: 167 258 XP in 135 242 s, mostly time at the cap).
-- A v1 record (no v) is recomputed once at login.
local function UserPriorText(ns)
  local p = ns.char.prior
  T.eq(type(p) == "table" and p.v, 2, "prior v2")
  T.near(p.xph, 167200 * 3600 / 104914, 1, "167 200 XP (levels 1-19) in 104 914 s")
  return "~5,7k/h"
end

T.test("user data: the bar reads 'XP : 58 / 23 200 · ~5,7k/h', paused, nothing overlaps", function()
  local ns = StartUser({ prior = { xph = 4500, at = 1790799277 } })
  local L = ns.L
  local tp = Widget().tp
  local est = UserPriorText(ns)
  T.ok(ns.Tracker.IsPaused(ns.GetMask()), "chrono paused in the city")
  T.eq(ns.Tokens.ctx.rateStatus, "estimate")
  T.eq(tp.brx:GetText(), "XP : 58 / 23\194\160200")
  T.ok(tp.sep:IsShown(), "separator")
  T.eq(tp.slots[2]:GetText(), est)
  T.eq(tp.slots[1]:GetText():sub(1, 1), "~")
  T.ok(tp.marks[1]:IsShown() and tp.marks[2]:IsShown(), "pause marks kept")
  T.eq(tp.marker:GetText(), "0,3 %")
  T.ok(tp.marker:IsShown())
  CheckBar(ns, tp, "user bar")
  -- no dark background: the settings of 0.1.0-test were saved in full (legacy default)
  if ns.C.DEFAULTS.widget.bgAlpha ~= nil then
    T.eq(ns.settings.widget.background, nil, "on/off background replaced by an opacity")
    T.eq(ns.settings.widget.bgAlpha, 0)
  else
    T.eq(ns.settings.widget.background, false)
  end
  -- tooltip: the values with their source, never a bare "..."
  GameTooltip:ClearLines()
  ns.Tooltip.Fill(GameTooltip, true)
  local lines = TipLines()
  local rate = FindLine(lines, L.TT_XPH)
  T.ok(rate[2]:find(est, 1, true) == 1, "XP per hour: " .. tostring(rate[2]))
  T.ok(rate[2]:find(L.RATE_ESTIMATE, 1, true) ~= nil)
  local eta = FindLine(lines, L.TT_NEXT_LEVEL)
  T.eq(eta[2]:sub(1, 1), "~")
  T.ok(eta[2]:find(L.RATE_ESTIMATE, 1, true) ~= nil)
  T.eq(FindLine(lines, format(L.TT_LEVEL_FMT, 20, 21))[2], "0,3 %")
  T.ok(FindLine(lines, format(L.TT_PAUSED_FMT, L.PAUSE_CITY)) ~= nil, "pause line")
  -- /tpl played names the estimate too
  local from = #Stub.printed + 1
  Stub.RunSlash("played")
  T.ok(Printed(est .. " (" .. L.RATE_ESTIMATE .. ")", from), "/tpl played summary")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("user data: the estimate computed at login from the server /played (~5,7k/h)", function()
  local ns = StartUser()
  local tp = Widget().tp
  T.ok(type(ns.char.prior) == "table", "pre-install estimate computed")
  T.eq(ns.Tokens.ctx.rateStatus, "estimate")
  -- R3: completed levels only (the level 20 time is mostly capped / idle time)
  T.eq(tp.slots[2]:GetText(), UserPriorText(ns))
  T.eq(tp.brx:GetText(), "XP : 58 / 23\194\160200")
  T.eq(tp.slots[1]:GetText():sub(1, 1), "~")
  CheckBar(ns, tp, "user bar, computed estimate")
end)

T.test("user data without any estimate: the tooltip explains what is missing", function()
  local ns = StartUser()
  local L = ns.L
  ns.char.prior = nil
  GameTooltip:ClearLines()
  ns.Tooltip.Fill(GameTooltip, false)
  local rate = FindLine(TipLines(), L.TT_XPH)
  T.ok(rate[2] ~= L.DOTS, "never a bare '...'")
  local left = ns.Tokens.ctx.warmupLeft
  T.eq(rate[2], left >= 60 and format(L.TT_NODATA_FMT, ns.Fmt.Duration(left)) or L.TT_NODATA_XP)
  CheckBar(ns, Widget().tp, "user bar, no data")
end)

T.test("broker: an estimate shows with its '~'", function()
  local ns = StartUser({ ui = { ldb = true }, prior = { xph = 4500, at = 1790799277 } })
  local obj = Stub.ui.ldbObjects["TruePlayed"]
  local est = UserPriorText(ns)
  T.ok(obj ~= nil)
  T.ok(find(obj.text, est, 1, true) ~= nil, "broker text: " .. tostring(obj.text))
  local plain = obj.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")   -- dim while paused
  T.eq(plain:sub(-#est), est)
  T.eq(plain:sub(1, 1), "~", "slot 1 (time to level) first")
  T.eq(ns.Tokens.ctx.rateStatus, "estimate")
end)

for _, modern in ipairs({ true, false }) do
  T.test("fresh install: no background, the opacity slider at 0 %, moving it sets the opacity ("
      .. (modern and "modern" or "fallback") .. " slider)", function()
    local ns = Start({ ui = { modern = modern } })
    T.eq(ns.C.DEFAULTS.widget.bgAlpha, 0)
    T.eq(ns.settings.widget.bgAlpha, 0)
    T.eq(ns.settings.widget.background, nil)
    ns.Options.Open()
    local controls = rawget(Stub.ui.categories[1].frame, "controls")
    T.eq(controls["widget.background"], nil, "the on/off checkbox is gone")
    local s = controls["widget.bgAlpha"].widget
    T.eq(s:GetValue(), 0, "slider reflects the default")
    if modern then
      s:SetValue(50)
    else
      s:GetScript("OnValueChanged")(s, 52)           -- snapped to the 5 % step
      T.eq(controls["widget.bgAlpha"].valueText:GetText(), format(ns.L.SLIDER_PCT_FMT, 50))
    end
    T.near(ns.settings.widget.bgAlpha, 0.5, 1e-9)
    ns.Core.SetSetting("widget.bgAlpha", 0.85)       -- e.g. a migrated dark background
    T.eq(s:GetValue(), 85, "synced from elsewhere while shown")
    ns.Core.SetSetting("widget.bgAlpha", 0)
    T.eq(s:GetValue(), 0)
  end)
end

T.test("window: continents for the character and the account, instances and other apart", function()
  local rec = RecordWithCity()
  rec.zones[1453] = { s = { c = 500, C = 50 }, xp = 0, name = "Stormwind City" }
  rec.zones.i389 = { s = { w = 700, W = 30 }, xp = 900, name = "Ragefire Chasm" }
  rec.zones.o = { s = { w = 40 }, xp = 0 }
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = rec } } })
  local L, Fmt = ns.L, ns.Fmt
  Stub.Advance(15)
  ns.Window.Show("zones", OTHER_GUID)
  local tp = StatsTP()
  T.eq(tp.cells[tp.rows[1]][1]:GetText(), L.SECTION_CONTINENTS)
  local names = {}
  for i = 2, 5 do names[#names + 1] = tp.cells[tp.rows[i]][1]:GetText() end
  T.eq(names, { "Kalimdor", L.CONT_INSTANCES, "Eastern Kingdoms", L.CONT_OTHER }, "sorted by time")
  T.eq(Cells(tp, RowWith(tp, "Kalimdor")),
    { "Kalimdor", Fmt.Duration(9000700), Fmt.Duration(9000700), Fmt.Duration(100), "" })
  T.eq(Cells(tp, RowWith(tp, L.CONT_INSTANCES)),
    { L.CONT_INSTANCES, Fmt.Duration(730), Fmt.Duration(730), Fmt.Duration(30), "" })
  T.eq(tp.cells[tp.rows[6]][1]:GetText(), L.CITIES_HEADER, "the capitals block follows")
  -- city excluded: Eastern Kingdoms (city time only) keeps its row, dashed, last
  ns.Core.SetSetting("exclude.city", true)
  T.eq(tp.filter:GetText(), format(L.WIN_FILTER_FMT, ns.Stats.MaskLabel(4)), "header names the exclusion")
  names = {}
  for i = 2, 5 do names[#names + 1] = tp.cells[tp.rows[i]][1]:GetText() end
  T.eq(names, { "Kalimdor", L.CONT_INSTANCES, L.CONT_OTHER, "Eastern Kingdoms" })
  T.eq(Cells(tp, RowWith(tp, "Eastern Kingdoms")),
    { "Eastern Kingdoms", "-", Fmt.Duration(550), Fmt.Duration(50), "" })
  -- account view: every character's zones merged (the current one plays in Durotar)
  ns.Core.SetSetting("exclude.city", false)
  ns.Window.SetView("account")
  T.eq(tp.cells[tp.rows[1]][1]:GetText(), L.SECTION_CONTINENTS)
  local mine = ns.Stats.SumAll(ns.char.zones[1411])
  T.ok(mine > 0, "current character has Durotar time")
  T.eq(Cells(tp, RowWith(tp, "Kalimdor"))[3], Fmt.Duration(9000700 + mine))
  T.eq(tp.filter:GetText(), "")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("max level: the bar is drawn full and dimmed, not empty", function()
  local ns = Start({ ui = { ldb = false }, level = 60 })
  Stub.Advance(2)
  local tp = Widget().tp
  T.ok(tp.tex.fillM:IsShown(), "fill drawn at max level")
  local _, _, _, a = tp.tex.fillM:GetVertexColor()
  T.ok(type(a) == "number" and a < 1, "dimmed fill")
  T.eq(tp.brx:GetText(), "", "no XP text")
  T.match(tp.bl:GetText(), "60")
  T.ok(ns.Tracker.IsMax())
end)

---------------------------------------------------------------------------
-- Round 3: instance time, rested XP, mobs to kill, text colour and readability,
-- FPS / latency graph option, new tokens (requests A-F)
---------------------------------------------------------------------------

local function FillTip(ns, detailed)
  GameTooltip:ClearLines()
  ns.Tooltip.Fill(GameTooltip, detailed)
  return TipLines()
end

local function Controls()
  return rawget(Stub.ui.categories[1].frame, "controls")
end

-- OtherRecord with a dungeon, a raid and a battleground (level 29 holds the dungeon).
local function RecordWithInstances()
  local rec = OtherRecord()
  rec.zones.i389 = { s = { d = 3000, D = 300 }, xp = 4500, name = "Ragefire Chasm" }
  rec.zones.i409 = { s = { r = 5000 }, xp = 0, name = "Molten Core" }
  rec.zones.i489 = { s = { p = 1200, P = 100 }, xp = 0, name = "Warsong Gulch" }
  local s = rec.life.s
  s.d, s.D, s.r, s.p, s.P = 3000, 300, 5000, 1200, 100
  rec.levels[29].s.d, rec.levels[29].s.D = 3000, 300
  rec.levels[29].z.i389 = { s = { d = 3000, D = 300 }, xp = 4500 }
  return rec
end

for _, locale in ipairs({ "enUS", "frFR" }) do
  T.test("tooltip breakdown: fixed order, parts at 0 % left out, five parts per line (" .. locale .. ")", function()
    local ns = Start({ ui = { ldb = false }, locale = locale })
    local L, Fmt = ns.L, ns.Fmt
    Stub.Advance(3)
    local life = ns.char.life
    local function P(key, pct) return format(L.BD_PART_FMT, L[key], Fmt.Percent(pct / 100, 0)) end
    -- 10 000 s tracked (the untracked pre-install time is left out of the shares)
    life.s = { w = 5000, W = 100, d = 2000, D = 500, r = 1000, p = 500, t = 200, i = 400, c = 300, u = 7000 }
    local lines = FillTip(ns, false)
    local line, idx = FindLine(lines, L.TT_BREAKDOWN)
    T.eq(line[2], table.concat({ P("BD_WORLD", 50), P("BD_DUNGEON", 20), P("BD_RAID", 10), P("BD_PVP", 5),
      P("BD_TAXI", 2) }, L.SEP), "first line: world, dungeons, raids, PvP, flight")
    T.eq(lines[idx + 1], { " ", table.concat({ P("BD_AFK", 6), P("BD_INN", 4), P("BD_CITY", 3) }, L.SEP) },
      "second line without a label: AFK (all kinds), inn, city")
    -- no raid, no PvP, 0.2 % of flight: those parts are left out, one line
    life.s = { w = 6480, W = 100, d = 2000, D = 500, t = 20, i = 600, c = 300 }
    lines = FillTip(ns, false)
    line, idx = FindLine(lines, L.TT_BREAKDOWN)
    local expected = table.concat({ P("BD_WORLD", 65), P("BD_DUNGEON", 20), P("BD_AFK", 6), P("BD_INN", 6),
      P("BD_CITY", 3) }, L.SEP)
    T.eq(line[2], expected)
    T.eq(lines[idx + 1][2], nil, "one line only")
    T.no(find(line[2], L.BD_TAXI, 1, true), "flight rounds to 0 %: left out")
    -- /tpl played prints the same parts
    local n = #Stub.printed
    Stub.RunSlash("played")
    T.ok(Printed(expected, n + 1), "/tpl played breakdown")
    -- nothing tracked yet: an explanation, never "0 %" parts
    life.s = { u = 5000 }
    line = FindLine(FillTip(ns, false), L.TT_BREAKDOWN)
    T.eq(line[2], L.TT_NO_RATE)
  end)
end

T.test("tooltip: instance time in the short view, each kind with its AFK part and the account total in the details", function()
  local ns = Start({ ui = { ldb = false }, db = { schema = 1, chars = { [OTHER_GUID] = RecordWithInstances() } } })
  local L, Fmt = ns.L, ns.Fmt
  Stub.Advance(3)
  T.no(FindLine(FillTip(ns, false), L.TT_INSTANCES), "no instance line before any instance")
  T.no(FindLine(FillTip(ns, true), L.BD_DUNGEON), "no dungeon line before any dungeon")
  local s = ns.char.life.s
  s.d, s.D, s.r, s.p, s.P = 3000, 600, 7200, 900, 100
  T.eq(FindLine(FillTip(ns, false), L.TT_INSTANCES)[2], Fmt.Duration(11800))
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(FindLine(FillTip(ns, false), L.TT_INSTANCES)[2], Fmt.Duration(11100), "AFK excluded")
  ns.Core.SetSetting("exclude.afk", false)
  local det = FillTip(ns, true)
  T.eq(FindLine(det, L.BD_DUNGEON)[2], format(L.TT_OF_WHICH_AFK_FMT, Fmt.Duration(3600), Fmt.Duration(600)))
  T.eq(FindLine(det, L.BD_RAID)[2], format(L.TT_OF_WHICH_AFK_FMT, Fmt.Duration(7200), Fmt.Duration(0)))
  T.eq(FindLine(det, L.BD_PVP)[2], format(L.TT_OF_WHICH_AFK_FMT, Fmt.Duration(1000), Fmt.Duration(100)))
  -- account: this character plus the other one (9 600 s of instances)
  T.eq(FindLine(det, L.TT_ACCOUNT_INST)[2], Fmt.Duration(11800 + 9600))
  -- only the kinds played get a line
  s.r, s.p, s.P = nil, nil, nil
  det = FillTip(ns, true)
  T.ok(FindLine(det, L.BD_DUNGEON) ~= nil)
  T.no(FindLine(det, L.BD_RAID), "no raid line without raid time")
  T.no(FindLine(det, L.BD_PVP), "no PvP line without PvP time")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("tooltip: rested line like the game's XP bar ('Repos\195\169 : 11 600 XP (50 %)')", function()
  Stub.player.rest = 11600
  local ns = Start({ ui = { ldb = false }, locale = "frFR", level = 20 })
  local L = ns.L
  Stub.Advance(3)
  local line = FindLine(FillTip(ns, false), L.TT_RESTED)
  T.ok(line ~= nil, "rested line")
  T.eq(line[1], "Repos\195\169")
  T.eq(line[2], "11\194\160600 XP (50 %)")
  -- English
  Stub.Reset()
  Stub.player.rest = 11600
  ns = Start({ ui = { ldb = false }, level = 20 })
  Stub.Advance(3)
  T.eq(FindLine(FillTip(ns, false), ns.L.TT_RESTED)[2], "11,600 XP (50%)")
  -- no rested XP: no line
  Stub.Reset()
  ns = Start({ ui = { ldb = false }, level = 20 })
  Stub.Advance(3)
  T.no(FindLine(FillTip(ns, false), ns.L.TT_RESTED), "not rested: no line")
end)

T.test("tooltip: mobs to kill right under the next level line, from the last kill (frFR)", function()
  Stub.player.xp = 58
  local ns = Start({ ui = { ldb = false }, locale = "frFR", level = 20 })
  local L, Fmt = ns.L, ns.Fmt
  Stub.Advance(3)
  ns.char.lastKill = nil
  local lines = FillTip(ns, false)
  local _, iNext = FindLine(lines, L.TT_NEXT_LEVEL)
  local kills, iKills = FindLine(lines, L.TT_KILLS)
  T.ok(kills ~= nil, "kills line")
  T.eq(iKills, iNext + 1, "right under the next level line")
  T.eq(kills[2], L.TT_KILLS_NODATA, "no kill known yet")
  T.ok(kills[2] ~= L.DOTS)
  -- the user's druid: 58 / 23 200 XP, last mob 610 XP, not rested -> ~38
  ns.char.lastKill = { xp = 610, level = 20, at = time() }
  T.eq(select(2, ns.Stats.KillsToLevel(ns.char, 58, 23200, 0)), 610)
  lines = FillTip(ns, false)
  _, iNext = FindLine(lines, L.TT_NEXT_LEVEL)
  kills, iKills = FindLine(lines, L.TT_KILLS)
  T.eq(kills[2], "~38 (dernier : 610 XP)")
  T.eq(iKills, iNext + 1)
  local det = FillTip(ns, true)
  T.eq(FindLine(det, L.TT_KILLS)[2], "~38 (dernier : 610 XP)", "same line in the detailed view")
  -- rested: kills give more XP, so fewer mobs (the count follows Stats.KillsToLevel)
  Stub.Reset()
  Stub.player.xp, Stub.player.rest = 58, 11600
  ns = Start({ ui = { ldb = false }, locale = "frFR", level = 20 })
  Stub.Advance(3)
  ns.char.lastKill = { xp = 610, level = 20, at = time() }
  local n = ns.Stats.KillsToLevel(ns.char, 58, 23200, 11600)
  T.ok(type(n) == "number" and n < 38, "rest-aware count: " .. tostring(n))
  T.eq(FindLine(FillTip(ns, false), L.TT_KILLS)[2], format(L.TT_KILLS_FMT, Fmt.Number(n), Fmt.Number(610)))
end)

T.test("tooltip: no mobs line at max level", function()
  local ns = Start({ ui = { ldb = false }, level = 60 })
  Stub.Advance(3)
  ns.char.lastKill = { xp = 610, level = 60, at = time() }
  T.no(FindLine(FillTip(ns, false), ns.L.TT_KILLS))
  T.no(FindLine(FillTip(ns, true), ns.L.TT_KILLS))
end)

T.test("window: most played instances with their kind, for the character and the account", function()
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = RecordWithInstances() } } })
  local L, Fmt = ns.L, ns.Fmt
  Stub.Advance(15)
  ns.Window.Show("zones", OTHER_GUID)
  local tp = StatsTP()
  local mc = format(L.INST_ROW_FMT, "Molten Core", L.KIND_RAID)
  local rfc = format(L.INST_ROW_FMT, "Ragefire Chasm", L.KIND_DUNGEON)
  local wsg = format(L.INST_ROW_FMT, "Warsong Gulch", L.KIND_PVP)
  local header = RowWith(tp, L.INSTANCES_HEADER)
  T.ok(header ~= nil, "instances block")
  local hi
  for i = 1, #tp.rows do if tp.rows[i] == header then hi = i end end
  T.eq(tp.cells[tp.rows[1]][1]:GetText(), L.SECTION_CONTINENTS, "after the continents")
  T.eq({ tp.cells[tp.rows[hi + 1]][1]:GetText(), tp.cells[tp.rows[hi + 2]][1]:GetText(),
         tp.cells[tp.rows[hi + 3]][1]:GetText() }, { mc, rfc, wsg }, "sorted by time")
  T.eq(tp.cells[tp.rows[hi + 4]][1]:GetText(), L.TAB_ZONES, "then the zones (this record has no capital)")
  T.eq(Cells(tp, RowWith(tp, mc)), { mc, Fmt.Duration(5000), Fmt.Duration(5000), "-", "-" })
  T.eq(Cells(tp, RowWith(tp, rfc)), { rfc, Fmt.Duration(3300), Fmt.Duration(3300), Fmt.Duration(300), Fmt.Number(4500) })
  T.eq(Cells(tp, RowWith(tp, wsg)), { wsg, Fmt.Duration(1300), Fmt.Duration(1300), Fmt.Duration(100), "-" })
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(Cells(tp, RowWith(tp, rfc)), { rfc, Fmt.Duration(3000), Fmt.Duration(3300), Fmt.Duration(300), Fmt.Number(4500) },
    "AFK excluded: counted time without the AFK part, raw kept")
  ns.Core.SetSetting("exclude.afk", false)
  -- footer: the instance total of the viewed character
  T.ok(find(tp.footer1:GetText(), format(L.FOOTER_INST_FMT, Fmt.Duration(9600)), 1, true) ~= nil, "footer")
  -- account view: every character's instances merged
  ns.Window.SetView("account")
  T.ok(RowWith(tp, L.INSTANCES_HEADER) ~= nil, "account view block")
  T.eq(Cells(tp, RowWith(tp, mc))[2], Fmt.Duration(5000))
  T.ok(find(tp.footer1:GetText(), format(L.FOOTER_INST_FMT, Fmt.Duration(9600)), 1, true) ~= nil,
    "account footer")
  -- the current character never entered an instance: no block, no footer part
  ns.Window.SetView("current")
  T.eq(RowWith(tp, L.INSTANCES_HEADER), nil)
  T.no(find(tp.footer1:GetText(), Frag(L.FOOTER_INST_FMT), 1, true))
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("window: Levels and Sessions tabs have an instance column, under the exclusions", function()
  local rec = RecordWithInstances()
  rec.sessions[1].s.r, rec.sessions[1].s.R = 1800, 200
  local ns = Start({ db = { schema = 1, chars = { [OTHER_GUID] = rec } } })
  local L, Fmt = ns.L, ns.Fmt
  Stub.Advance(15)
  ns.Window.Show("levels", OTHER_GUID)
  local tp = StatsTP()
  T.eq(tp.header[7]:GetText(), L.COL_CITY)
  T.eq(tp.header[8]:GetText(), L.COL_INST)
  T.eq(tp.header[9]:GetText(), L.COL_MAIN_ZONE)
  T.eq(tp.header[10]:GetText(), L.COL_REACHED)
  local c = tp.cells[RowWith(tp, "29")]
  T.eq(c[8]:GetText(), Fmt.Duration(3300), "instance time of the level")
  T.eq(c[9]:GetText(), "Tanaris", "main zone")
  T.eq(tp.cells[RowWith(tp, "30")][8]:GetText(), "-", "no instance at level 30")
  ns.Core.SetSetting("exclude.afk", true)
  T.eq(tp.cells[RowWith(tp, "29")][8]:GetText(), Fmt.Duration(3000), "AFK part left out, like the time column")
  ns.Core.SetSetting("exclude.afk", false)
  -- sessions
  ns.Window.Toggle("sessions")
  T.eq(tp.header[7]:GetText(), L.COL_INST)
  T.eq(tp.cells[tp.rows[1]][7]:GetText(), Fmt.Duration(2000), "raid time of the session")
  -- account view of the Levels tab: its own columns, no instance column
  ns.Window.Toggle("levels")
  ns.Window.SetView("account")
  T.eq(tp.header[8]:GetText(), "")
end)

T.test("options: text colour through the game's colour picker (10.2.5 API), cancel and reset", function()
  local ns = Start({ ui = { modern = true } })
  local ui = Stub.ui
  ns.Options.Open()
  local rec = Controls()["widget.textColor"]
  T.ok(rec ~= nil, "colour control")
  local swatch, reset = rec.widget, rec.reset
  T.eq(ns.settings.widget.textColor, false, "built-in colours by default")
  T.no(reset:IsEnabled(), "nothing to reset")
  T.eq({ rec.swatch:GetVertexColor() }, { 1, 1, 1, 1 }, "the swatch shows the built-in white")
  swatch:GetScript("OnClick")(swatch)
  local info = ui.pickerInfo
  T.ok(info ~= nil and type(info.swatchFunc) == "function" and type(info.cancelFunc) == "function")
  T.eq({ info.r, info.g, info.b, info.hasOpacity }, { 1, 1, 1, false })
  T.eq(ns.settings.widget.textColor, false, "opening the picker changes nothing")
  ui.PickColor(1, 0.5, 0)
  T.eq(ns.settings.widget.textColor, { 1, 0.5, 0 })
  T.eq({ rec.swatch:GetVertexColor() }, { 1, 0.5, 0, 1 }, "swatch follows")
  T.ok(reset:IsEnabled())
  ui.PickColor(0.2, 0.4, 0.6)
  T.eq(ns.settings.widget.textColor, { 0.2, 0.4, 0.6 })
  ui.CancelColor()
  T.eq(ns.settings.widget.textColor, false, "Cancel restores the colours the picker opened with")
  swatch:GetScript("OnClick")(swatch)
  ui.PickColor(0, 1, 0)
  T.eq(ns.settings.widget.textColor, { 0, 1, 0 })
  swatch:GetScript("OnClick")(swatch)
  T.eq({ ui.pickerInfo.r, ui.pickerInfo.g, ui.pickerInfo.b }, { 0, 1, 0 }, "reopens on the stored colour")
  ui.CancelColor()
  T.eq(ns.settings.widget.textColor, { 0, 1, 0 })
  reset:GetScript("OnClick")(reset)
  T.eq(ns.settings.widget.textColor, false, "reset: built-in colours again")
  T.no(reset:IsEnabled())
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("options: text colour with the older colour picker API", function()
  local ns = Start({ ui = { modern = false, colorPicker = "legacy" } })
  local ui = Stub.ui
  ns.Options.Open()
  local rec = Controls()["widget.textColor"]
  local picker = rawget(_G, "ColorPickerFrame")
  T.eq(picker.SetupColorPickerAndShow, nil, "legacy picker")
  rec.widget:GetScript("OnClick")(rec.widget)
  T.ok(picker:IsShown())
  T.eq(ns.settings.widget.textColor, false, "setting the start colour writes nothing")
  T.eq(type(picker.func), "function")
  T.eq(picker.hasOpacity, false)
  T.eq(picker.previousValues, { r = 1, g = 1, b = 1 })
  ui.PickColor(1, 0, 0)
  T.eq(ns.settings.widget.textColor, { 1, 0, 0 })
  ui.CancelColor()
  T.eq(ns.settings.widget.textColor, false)
  -- picking the start colour back after a real change is a choice: it is kept
  rec.widget:GetScript("OnClick")(rec.widget)
  ui.PickColor(0.5, 0.5, 0.5)
  ui.PickColor(1, 1, 1)
  T.eq(ns.settings.widget.textColor, { 1, 1, 1 })
  -- no colour picker at all: the swatch does nothing
  Stub.Reset()
  ns = Start({ ui = { colorPicker = false } })
  ns.Options.Open()
  rec = Controls()["widget.textColor"]
  rec.widget:GetScript("OnClick")(rec.widget)
  T.eq(ns.settings.widget.textColor, false)
end)

for _, modern in ipairs({ true, false }) do
  T.test("options: outline, shadow, quality colours and graph history (" .. (modern and "modern" or "fallback")
      .. " controls)", function()
    local ns = Start({ ui = { modern = modern } })
    local L, ui = ns.L, Stub.ui
    ns.Options.Open()
    local controls = Controls()
    local w = ns.settings.widget
    T.eq({ w.outline, w.shadow, w.qualityColors, ns.settings.graph.window }, { "thin", true, true, 60 }, "defaults")
    local outline, graph = controls["widget.outline"].widget, controls["graph.window"].widget
    if modern then
      local root = rawget(outline, "_root")
      T.ok(ui.IsChecked(ui.FindMenuItem(root, L.OUTLINE_THIN)), "thin outline checked")
      ui.ClickMenuItem(ui.FindMenuItem(root, L.OUTLINE_THICK))
      T.eq(w.outline, "thick")
      ui.ClickMenuItem(ui.FindMenuItem(root, L.OUTLINE_NONE))
      T.eq(w.outline, "none")
      root = rawget(graph, "_root")
      T.ok(ui.IsChecked(ui.FindMenuItem(root, L.GRAPH_WINDOW_60)), "1 min checked")
      ui.ClickMenuItem(ui.FindMenuItem(root, L.GRAPH_WINDOW_300))
      T.eq(ns.settings.graph.window, 300)
      ui.ClickMenuItem(ui.FindMenuItem(root, L.GRAPH_WINDOW_30))
      T.eq(ns.settings.graph.window, 30)
    else
      outline:GetScript("OnClick")(outline, "LeftButton")        -- thin -> thick
      T.eq(w.outline, "thick")
      outline:GetScript("OnClick")(outline, "LeftButton")        -- thick -> none (wraps)
      T.eq(w.outline, "none")
      outline:GetScript("OnClick")(outline, "RightButton")       -- back to thick
      T.eq(w.outline, "thick")
      graph:GetScript("OnClick")(graph, "LeftButton")            -- 1 min -> 5 min
      T.eq(ns.settings.graph.window, 300)
      graph:GetScript("OnClick")(graph, "LeftButton")            -- 5 min -> 30 s
      T.eq(ns.settings.graph.window, 30)
    end
    for _, path in ipairs({ "widget.shadow", "widget.qualityColors" }) do
      local cb = controls[path].widget
      T.ok(cb:GetChecked(), path .. " ticked by default")
      cb:GetScript("OnClick")(cb)
      T.eq(ns.Core.GetSetting(path), false, path)
      T.no(cb:GetChecked())
      cb:GetScript("OnClick")(cb)
      T.eq(ns.Core.GetSetting(path), true, path)
    end
    T.eq(Stub.onUpdateCount, 0)
  end)
end

T.test("options: the slot dropdowns offer the new infos; max-level slots only the non-XP ones", function()
  local ns = Start({ ui = { modern = true } })
  local Tokens, ui = ns.Tokens, Stub.ui
  local NEW = { "kills", "eta_kills", "instance_session", "instance_total" }
  ns.Options.Open()
  local controls = Controls()
  local slotRoot = rawget(controls["widget.slots.1"].widget, "_root")
  local maxRoot = rawget(controls["widget.maxSlots.1"].widget, "_root")
  for i = 1, #NEW do
    local id = NEW[i]
    local label = Tokens.Label(id)
    T.no(find(label, "^TOKEN_"), "localized label for " .. id)
    T.ok(ui.FindMenuItem(slotRoot, label) ~= nil, id .. " in the slot dropdown")
    T.eq(ui.FindMenuItem(maxRoot, label) ~= nil, not Tokens.DEF[id].xp, id .. " at max level")
  end
  T.ok(Tokens.DEF.kills.xp and Tokens.DEF.eta_kills.xp, "mob counts are XP infos")
  ui.ClickMenuItem(ui.FindMenuItem(slotRoot, Tokens.Label("kills")))
  T.eq(ns.settings.widget.slots[1], "kills")
  ui.ClickMenuItem(ui.FindMenuItem(maxRoot, Tokens.Label("instance_total")))
  T.eq(ns.settings.widget.maxSlots[1], "instance_total")
  T.eq(ns.C.DEFAULTS.widget.slots, { "eta_kills", "xph", "fps_latency" }, "new default slots")
end)

-- Every literal L.KEY / L["KEY"] of the addon files exists in both locales.
T.test("locales: every key used by the addon exists in enUS and frFR", function()
  local function LoadLocale(file, locale)
    Stub.locale = locale
    local chunk = assert(loadfile(Stub.ROOT .. file))
    local ns = {}
    if locale ~= "enUS" then ns.L = {} end
    chunk("TruePlayed", ns)
    return ns.L
  end
  local en = LoadLocale("Locales/enUS.lua", "enUS")
  local fr = LoadLocale("Locales/frFR.lua", "frFR")
  local files = {}
  local toc = io.open(Stub.ROOT .. "TruePlayed_Camelot.toc", "r")
  for raw in toc:lines() do
    local line = raw:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" and not line:find("^Locales") then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  toc:close()
  local used, n = {}, 0
  for i = 1, #files do
    local f = io.open(Stub.ROOT .. files[i], "r")
    if f then
      local src = f:read("*a")
      f:close()
      src = src:gsub("%-%-[^\n]*", "")                      -- comments
      for key in gmatch(src, "[^%w_%.]L%.([%u][%u%d_]+)") do
        if not used[key] then used[key] = files[i]; n = n + 1 end
      end
      for key in gmatch(src, "[^%w_%.]L%[\"([%u][%u%d_]+)\"%]") do
        if not used[key] then used[key] = files[i]; n = n + 1 end
      end
    end
  end
  T.ok(n > 150, "keys found: " .. n)
  for key, file in pairs(used) do
    T.ok(rawget(en, key) ~= nil, "enUS misses " .. key .. " (used in " .. file .. ")")
    T.ok(rawget(fr, key) ~= nil, "frFR misses " .. key .. " (used in " .. file .. ")")
  end
  -- keys of this round named by the contract (tokens and graph of the bar)
  for _, key in ipairs({ "TOKEN_KILLS", "TOKEN_ETA_KILLS", "TOKEN_INSTANCE_SESSION", "TOKEN_INSTANCE_TOTAL",
                         "KILLS_FMT", "GRAPH_TITLE_FMT", "GRAPH_AGO_FMT", "GRAPH_MIN_AVG_MAX_FMT",
                         "GRAPH_LAT_NOTE" }) do
    T.ok(rawget(en, key) ~= nil and rawget(fr, key) ~= nil, key)
  end
  T.eq(format(fr.KILLS_FMT, "38"), "38 monstres")
  T.eq(format(en.KILLS_FMT, "38"), "38 mobs")
  T.eq(format(fr.KILLS_ONE_FMT, "1"), "1 monstre")
  T.eq(format(en.KILLS_ONE_FMT, "1"), "1 mob")
  T.eq(format(fr.GRAPH_AGO_FMT, format(fr.GRAPH_AGE_S_FMT, 23), "58 fps", "112 ms"), "il y a 23 s : 58 fps \194\183 112 ms")
end)

T.test("locales: frFR translates every enUS key with the same format arguments", function()
  local function LoadLocale(file, locale)
    Stub.locale = locale
    local chunk = assert(loadfile(Stub.ROOT .. file))
    local ns = {}
    if locale ~= "enUS" then ns.L = {} end
    chunk("TruePlayed", ns)
    return ns.L
  end
  local en = LoadLocale("Locales/enUS.lua", "enUS")
  local fr = LoadLocale("Locales/frFR.lua", "frFR")
  local DATE_PATTERNS = { DATE_FMT = true, DATETIME_FMT = true }
  local function Specs(s)
    s = s:gsub("%%%%", "")
    local list = {}
    for spec in gmatch(s, "%%[%-%d%.]*[sd]") do list[#list + 1] = spec:sub(-1) end
    return table.concat(list)
  end
  local n = 0
  for k, v in pairs(en) do
    n = n + 1
    T.ok(type(fr[k]) == "string", "frFR misses " .. tostring(k))
    if type(fr[k]) == "string" and not DATE_PATTERNS[k] then
      T.eq(Specs(fr[k]), Specs(v), "format arguments of " .. k)
    end
  end
  for k in pairs(fr) do
    T.ok(rawget(en, k) ~= nil, "frFR key unknown in enUS: " .. tostring(k))
  end
  T.ok(n > 200, "enUS keys loaded")
end)

---------------------------------------------------------------------------
-- Round 4: bar colours in the options (R4, C4), the user's druid at the beta's level
-- cap (R2, C2), new locale texts
---------------------------------------------------------------------------

T.test("options: XP bar and rested colours through the colour picker, one reset for both", function()
  local ns = Start({ ui = { modern = true } })
  local ui, C, L = Stub.ui, ns.C, ns.L
  ns.Options.Open()
  local controls = Controls()
  local xp, rested = controls["widget.xpColor"], controls["widget.restedColor"]
  local reset = controls["widget.barColors"]
  T.ok(xp ~= nil and rested ~= nil and reset ~= nil, "two swatches and a reset button")
  T.ok(xp.reset == reset.widget and rested.reset == reset.widget, "one reset button for both swatches")
  -- the swatches show the game's colours: purple, rested blue
  local f = C.COLORS.fill
  T.eq({ xp.swatch:GetVertexColor() }, { f[1], f[2], f[3], 1 })
  T.eq({ rested.swatch:GetVertexColor() }, { 0.0, 0.39, 0.88, 1 })
  T.no(reset.widget:IsEnabled(), "nothing to reset")
  -- the picker opens on the colour of the clicked swatch
  rested.widget:GetScript("OnClick")(rested.widget)
  T.eq({ ui.pickerInfo.r, ui.pickerInfo.g, ui.pickerInfo.b }, { 0.0, 0.39, 0.88 })
  ui.CancelColor()
  xp.widget:GetScript("OnClick")(xp.widget)
  T.eq({ ui.pickerInfo.r, ui.pickerInfo.g, ui.pickerInfo.b }, { f[1], f[2], f[3] })
  T.eq(ns.settings.widget.textColor, false, "the text colour is left alone")
  T.eq(C.DEFAULTS.widget.xpColor, false, "C4 default")
  T.eq(C.DEFAULTS.widget.restedColor, false)
  T.eq(ns.settings.widget.xpColor, false, "opening the picker changes nothing")
  ui.PickColor(1, 0.5, 0)
  T.eq(ns.settings.widget.xpColor, { 1, 0.5, 0 })
  T.eq({ xp.swatch:GetVertexColor() }, { 1, 0.5, 0, 1 }, "swatch follows")
  T.ok(reset.widget:IsEnabled())
  ui.CancelColor()
  T.eq(ns.settings.widget.xpColor, false, "Cancel restores the colour the picker opened with")
  xp.widget:GetScript("OnClick")(xp.widget)
  ui.PickColor(0.2, 0.8, 0.4)
  rested.widget:GetScript("OnClick")(rested.widget)
  ui.PickColor(0.9, 0.1, 0.1)
  T.eq(ns.settings.widget.xpColor, { 0.2, 0.8, 0.4 })
  T.eq(ns.settings.widget.restedColor, { 0.9, 0.1, 0.1 }, "each swatch writes its own colour")
  T.eq(ns.settings.widget.textColor, false)
  -- the bar follows
  local tp = Widget().tp
  local r, g, b = tp.tex.fillM:GetVertexColor()
  T.ok(math.abs(r - 0.2) < 1e-9 and math.abs(g - 0.8) < 1e-9 and math.abs(b - 0.4) < 1e-9, "bar recoloured")
  -- "Theme colours": both back at once, the text colour untouched
  ns.Core.SetSetting("widget.textColor", { 1, 1, 0 })
  reset.widget:GetScript("OnClick")(reset.widget)
  T.eq(ns.settings.widget.xpColor, false)
  T.eq(ns.settings.widget.restedColor, false)
  T.eq(ns.settings.widget.textColor, { 1, 1, 0 })
  T.no(reset.widget:IsEnabled())
  T.eq({ xp.swatch:GetVertexColor() }, { f[1], f[2], f[3], 1 })
  -- the text colour keeps its own reset
  local text = controls["widget.textColor"]
  text.reset:GetScript("OnClick")(text.reset)
  T.eq(ns.settings.widget.textColor, false)
  T.eq(L.OPT_BAR_COLORS_RESET, "Theme colours")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("options: the bar colour texts and notes (frFR)", function()
  local ns = Start({ ui = { modern = false }, locale = "frFR" })
  local L = ns.L
  ns.Options.Open()
  T.eq(L.OPT_BAR_COLORS_RESET, "Couleurs du th\195\168me")
  T.eq(L.OPT_XP_COLOR, "Couleur de la barre d'XP")
  T.eq(L.OPT_RESTED_COLOR, "Couleur de l'XP de repos")
  local reset = Controls()["widget.barColors"]
  T.ok(reset ~= nil, "reset button with the fallback controls")
  T.no(reset.widget:IsEnabled(), "nothing to reset yet")
  T.no(find(L.OPT_TEXT_COLOR_NOTE, "violette", 1, true), "no longer says the bar keeps the game's colours")
  T.eq(format(L.OPT_NOTE_STALL_FMT, 20):sub(1, #"Apr\195\168s 20 minutes"), "Apr\195\168s 20 minutes")
  T.ok(find(format(L.OPT_NOTE_CAP_FMT, 3), "3 monstres de suite", 1, true) ~= nil)
end)

T.test("user data: the druid at the beta's level 20 cap, the bar and the tooltip say so (frFR)", function()
  local ns = StartUser({ prior = { xph = 4500, at = 1790799277 } })
  local L = ns.L
  local tp = Widget().tp
  local Tracker = ns.Tracker
  -- the real engine (C2): three level 20 mobs killed without any XP set the cap
  T.eq(tp.bl:GetText(), "NIVEAU 20")
  for i = 1, 3 do
    T.no(Tracker.IsMax(), "not capped before kill " .. i)
    Stub.KillNoXP({ level = 20, creatureType = "B\195\170te" })
    Stub.Advance(5)
  end
  local capLevel, isServerCap, misses = Tracker.GetCapInfo()
  T.eq(capLevel, 20); T.eq(isServerCap, true); T.eq(misses, 3)
  T.eq(ns.char.capLevel, 20, "persisted")
  Stub.Advance(1)
  T.eq(tp.bl:GetText(), "NIVEAU 20 \194\183 PLAFOND")
  T.eq(tp.brx:GetText(), "", "no XP text at the cap")
  CheckBar(ns, tp, "user bar at the cap")
  local lines = FillTip(ns, false)
  local capLine = "Niveau 20 : plafond actuel du serveur (aucune XP sur les 3 derniers monstres)"
  local _, i = FindLine(lines, capLine)
  T.ok(i ~= nil, "cap line")
  T.eq(lines[i + 1], { L.TT_XP, "58 / 23\194\160200" }, "where the XP stopped")
  T.eq(lines[i + 2][1], L.TT_CAP_RESUME)
  T.no(FindLine(lines, L.TT_MAX_LEVEL))
  local from = #Stub.printed + 1
  Stub.RunSlash("played")
  T.ok(Printed("Niveau 20 : plafond actuel du serveur", from), "/tpl played")
  -- the cap is raised, XP comes again: the cap is over and the XP bar is back by itself
  Stub.Kill(145)
  Stub.Advance(1)
  T.eq(Tracker.GetCapInfo(), nil)
  T.no(Tracker.IsMax())
  T.eq(tp.brx:GetText(), "XP : 203 / 23\194\160200")
  T.eq(tp.bl:GetText(), "NIVEAU 20")
  CheckBar(ns, tp, "user bar after the cap")
  T.ok(FindLine(FillTip(ns, false), L.TT_NEXT_LEVEL) ~= nil)
end)

T.test("locales: texts of the level cap and of the frozen rate (en, fr)", function()
  local function LoadLocale(file, locale)
    Stub.locale = locale
    local chunk = assert(loadfile(Stub.ROOT .. file))
    local ns = {}
    if locale ~= "enUS" then ns.L = {} end
    chunk("TruePlayed", ns)
    return ns.L
  end
  local en = LoadLocale("Locales/enUS.lua", "enUS")
  local fr = LoadLocale("Locales/frFR.lua", "frFR")
  T.eq(format(fr.TT_CAP_FMT, 20, 3), "Niveau 20 : plafond actuel du serveur (aucune XP sur les 3 derniers monstres)")
  T.eq(format(en.TT_CAP_FMT, 20, 3), "Level 20: current server level cap (no XP from the last 3 mobs)")
  T.eq(format(fr.TT_STALLED_FMT, fr.STALL_MARK, "3 h"), "* XP/h fig\195\169e : aucun gain d'XP depuis 3 h de jeu")
  T.eq(format(en.TT_STALLED_FMT, en.STALL_MARK, "3h"), "* XP per hour frozen: no XP gained for 3h of play")
  T.eq(format(fr.LEVEL_CAP_FMT, 20), "NIVEAU 20 \194\183 PLAFOND")
  T.eq(format(fr.SUM_CAP_FMT, 20), "Niveau 20 : plafond actuel du serveur. Le suivi de l'XP reprend tout seul.")
  T.eq(fr.CAP_SHORT, "Plafond serveur")
  T.eq(en.STALL_MARK, fr.STALL_MARK)
end)
