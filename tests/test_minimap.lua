-- tests/test_minimap.lua - the minimap button (MinimapButton.lua, design/NEXT-LOT.md backlog 3):
-- creation on the minimap edge with the addon icon, position by angle and minimap shape,
-- drag (the cursor angle on release, lock, the release is not a click), hover (the bar's
-- tooltip, Shift detailed, the hint of the left-click action), the left-click actions,
-- the context menu (its Hide and Show entries), /tpl minimap, independence from the bar,
-- settings repair and sparse save, no OnUpdate and no garbage per tick.
-- The stub's Minimap (tests/stub_ui.lua, minimap = true) is 140 x 140, centre 1790, 990.
local Stub, T = ...

local format, find = string.format, string.find

local MM_X, MM_Y = 1790, 990

local function Start(opts)
  opts = opts or {}
  local ui = { minimap = opts.minimap ~= false, minimapShape = opts.shape, ldb = false }
  Stub.InstallUI(ui)
  if opts.theme then Stub.theme = opts.theme end
  if opts.level then
    Stub.player.level = opts.level
    Stub.player.max = Stub.xpTable[opts.level] or 0
  end
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, ns.MinimapButton.button
end

local function Printed(text, from)
  local lines = Stub.printed
  for i = from or 1, #lines do
    if find(lines[i], text, 1, true) then return true end
  end
  return false
end

-- Offset of the button centre from the minimap centre.
local function Offset(b)
  local x, y = b:GetCenter()
  return x - MM_X, y - MM_Y
end

-- Last line of the shown GameTooltip (the classic theme of the stub).
local function LastLine()
  local ls = rawget(GameTooltip, "_lines") or {}
  local l = ls[#ls]
  return l and l[1]
end

local function Click(b, button)
  Stub.RunScript(b, "OnMouseDown", button)
  Stub.RunScript(b, "OnClick", button)
end

local function Drag(b, x, y)
  Stub.RunScript(b, "OnMouseDown", "LeftButton")
  Stub.RunScript(b, "OnDragStart", "LeftButton")
  Stub.ui.Cursor(x, y)
  Stub.RunScript(b, "OnDragStop")
  Stub.RunScript(b, "OnClick", "LeftButton")      -- a client may still send the click
end

---------------------------------------------------------------------------
-- Creation and position
---------------------------------------------------------------------------

T.test("minimap button: on the minimap, the addon icon, shown by default at 225 degrees", function()
  local ns, b = Start()
  T.ok(b ~= nil, "created")
  T.ok(b:IsShown(), "shown by default")
  T.eq(b:GetName(), "TruePlayedMinimapButton", "named (minimap button collectors)")
  T.ok(b:GetParent() == Stub.ui.minimap, "a child of the minimap")
  T.eq(b.tp.icon:GetTexture(), ns.C.ICON, "the TOC / compartment icon")
  T.eq(ns.Core.GetSetting("minimap.angle"), 225)
  local dx, dy = Offset(b)
  -- round minimap: radius 70 + 5, at 225 degrees
  T.near(dx, -75 * math.sqrt(0.5), 0.01, "x")
  T.near(dy, -75 * math.sqrt(0.5), 0.01, "y")
  T.eq(Stub.onUpdateCount, 0, "no OnUpdate")
  T.eq(Stub.errors, {})
end)

T.test("minimap button: no Minimap frame, no button and no error", function()
  local ns, b = Start({ minimap = false })
  T.eq(b, nil)
  Stub.RunSlash("minimap")
  Stub.Advance(2)
  T.eq(ns.MinimapButton.button, nil)
  T.eq(Stub.errors, {})
end)

T.test("minimap button: the angle and the minimap shape (round, square, corners)", function()
  local ns, b = Start()
  for _, a in ipairs({ 0, 90, 180, 270, 30 }) do
    ns.Core.SetSetting("minimap.angle", a)
    local dx, dy = Offset(b)
    T.near(dx, 75 * math.cos(math.rad(a)), 0.01, a .. ": x")
    T.near(dy, 75 * math.sin(math.rad(a)), 0.01, a .. ": y")
  end
  -- square minimap: the button runs along the edges, near the corner on the diagonal
  -- (LibDBIcon's: the diagonal radius minus 10 px, clamped to the edges)
  Stub.Reset()
  ns, b = Start({ shape = "SQUARE" })
  ns.Core.SetSetting("minimap.angle", 45)
  local dx, dy = Offset(b)
  local diag = (math.sqrt(2 * 75 * 75) - 10) * math.sqrt(0.5)
  T.ok(diag > 75 * math.sqrt(0.5) + 10, "further out than on a round minimap")
  T.near(dx, diag, 0.01, "square: towards the corner (x)")
  T.near(dy, diag, 0.01, "square: towards the corner (y)")
  ns.Core.SetSetting("minimap.angle", 30)
  dx, dy = Offset(b)
  T.near(dx, 75, 0.01, "square: clamped onto the right edge")
  T.near(dy, 0.5 * (math.sqrt(2 * 75 * 75) - 10), 0.01, "square: along the right edge")
  ns.Core.SetSetting("minimap.angle", 0)
  dx, dy = Offset(b)
  T.near(dx, 75, 0.01)
  T.near(dy, 0, 0.01)
  -- a corner shape: round in that quadrant only (top right is quadrant 3: x > 0, y > 0)
  T.eq(select(2, ns.MinimapButton.Offset(45, 140, 140, { false, false, true, false })),
    75 * math.sin(math.rad(45)), "round quadrant")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Drag
---------------------------------------------------------------------------

T.test("minimap button: drag follows the cursor, snaps back on the edge at the cursor angle", function()
  local ns, b = Start()
  local moved = false
  local start = b.StartMoving
  rawset(b, "StartMoving", function(self) moved = true; return start(self) end)
  -- release above the minimap: 90 degrees
  Drag(b, MM_X, MM_Y + 200)
  T.ok(moved, "the frame's own move (no OnUpdate)")
  T.eq(ns.Core.GetSetting("minimap.angle"), 90, "saved")
  local dx, dy = Offset(b)
  T.near(dx, 0, 0.01)
  T.near(dy, 75, 0.01, "on the edge")
  T.no(ns.Window.IsShown(), "the release is not a click")
  -- release left of the minimap: 180 degrees; below left: 225
  Drag(b, MM_X - 50, MM_Y)
  T.eq(ns.Core.GetSetting("minimap.angle"), 180)
  Drag(b, MM_X - 10, MM_Y - 10)
  T.eq(ns.Core.GetSetting("minimap.angle"), 225)
  -- a real click afterwards works
  Click(b, "LeftButton")
  T.ok(ns.Window.IsShown(), "next click: statistics")
  T.eq(Stub.onUpdateCount, 0)
  -- saved, and used again at the next login
  Drag(b, MM_X + 30, MM_Y + 30)
  T.eq(ns.Core.GetSetting("minimap.angle"), 45)
  Stub.Logout()
  T.eq(Stub.saved.settings.minimap, { angle = 45 }, "sparse: only the angle")
  T.eq(Stub.errors, {})
end)

T.test("minimap button: locked, a drag does nothing", function()
  local ns, b = Start()
  ns.Core.SetSetting("minimap.locked", true)
  local moved = false
  rawset(b, "StartMoving", function() moved = true end)
  Drag(b, MM_X, MM_Y + 200)
  T.no(moved, "no move")
  T.eq(ns.Core.GetSetting("minimap.angle"), 225, "angle kept")
  -- the release was a click then (no drag happened)
  T.ok(ns.Window.IsShown(), "a plain click")
end)

---------------------------------------------------------------------------
-- Hover, clicks, menu
---------------------------------------------------------------------------

T.test("minimap button: hover shows the bar's tooltip (Shift: detailed) with the left-click hint", function()
  local ns, b = Start()
  local L = ns.L
  Stub.RunScript(b, "OnEnter")
  T.ok(ns.Tooltip.IsShownFor(b), "the tooltip, owned by the button")
  T.eq(GameTooltip:GetOwner(), b)
  T.eq(LastLine(), L.TT_HINT, "default action: statistics")
  local short = GameTooltip:NumLines()
  Stub.SetShift(true)
  Stub.Advance(1)
  T.ok(GameTooltip:NumLines() > short, "Shift: the detailed view")
  Stub.SetShift(false)
  Stub.RunScript(b, "OnLeave")
  T.no(ns.Tooltip.IsShownFor(b), "hidden on leave")
  local hints = { options = L.TT_HINT_MM_OPTIONS, bar = L.TT_HINT_MM_BAR, mini = L.TT_HINT_MM_MINI,
                  stats = L.TT_HINT }
  for action, hint in pairs(hints) do
    ns.Core.SetSetting("minimap.click", action)
    Stub.RunScript(b, "OnEnter")
    T.eq(LastLine(), hint, action .. ": hint")
    Stub.RunScript(b, "OnLeave")
  end
  -- a drag hides the tooltip and does not show it again
  Stub.RunScript(b, "OnEnter")
  Stub.RunScript(b, "OnDragStart", "LeftButton")
  T.no(ns.Tooltip.IsShownFor(b), "hidden while dragged")
  Stub.RunScript(b, "OnEnter")
  T.no(ns.Tooltip.IsShownFor(b), "not while dragged")
  Stub.RunScript(b, "OnDragStop")
  T.eq(Stub.errors, {})
end)

T.test("minimap button: the left-click actions (statistics, options, XP bar, mini display)", function()
  local ns, b = Start()
  local L = ns.L
  -- statistics (default): toggles the window
  Click(b, "LeftButton")
  T.ok(ns.Window.IsShown(), "statistics shown")
  Click(b, "LeftButton")
  T.no(ns.Window.IsShown(), "and hidden")
  -- options
  ns.Core.SetSetting("minimap.click", "options")
  local opened = Stub.ui.opened
  Click(b, "LeftButton")
  T.eq(Stub.ui.opened, opened + 1, "options opened")
  Stub.ui.CloseSettings()
  -- XP bar on / off
  ns.Core.SetSetting("minimap.click", "bar")
  local n = #Stub.printed
  Click(b, "LeftButton")
  T.eq(ns.Core.GetSetting("widget.shown"), false, "bar hidden")
  T.no(ns.Bar.frame:IsShown())
  T.ok(Printed(L.WIDGET_HIDDEN, n + 1))
  Click(b, "LeftButton")
  T.eq(ns.Core.GetSetting("widget.shown"), true, "bar shown again")
  T.ok(ns.Bar.frame:IsShown())
  -- mini display on / off
  ns.Core.SetSetting("minimap.click", "mini")
  n = #Stub.printed
  Click(b, "LeftButton")
  T.eq(ns.Core.GetSetting("mini.shown"), true, "mini shown")
  T.ok(ns.MiniDisplay.frame:IsShown())
  T.ok(Printed(L.MINI_SHOWN, n + 1))
  Click(b, "LeftButton")
  T.eq(ns.Core.GetSetting("mini.shown"), false)
  T.no(ns.MiniDisplay.frame:IsShown())
  T.ok(Printed(L.MINI_HIDDEN, n + 1))
  T.eq(Stub.errors, {})
end)

T.test("minimap button: right click opens the bar's menu on the button; its Hide hides the button", function()
  local ns, b = Start()
  local L, ui = ns.L, Stub.ui
  Stub.RunScript(b, "OnEnter")
  Click(b, "RightButton")
  T.ok(ui.lastMenuOwner == b, "anchored to the button")
  T.no(ns.Tooltip.IsShownFor(b), "the tooltip makes room for the menu")
  local root = ui.lastMenu
  for _, key in ipairs({ "MENU_EXCLUDE_AFK", "MENU_THEME", "MENU_LOCK", "MENU_STATS", "MENU_OPTIONS",
                         "MENU_SHOW", "MENU_HIDE" }) do
    T.ok(ui.FindMenuItem(root, L[key]) ~= nil, key)
  end
  -- Show: the three displays, each one on / off
  local show = ui.FindMenuItem(root, L.MENU_SHOW)
  T.eq(#show.children, 3)
  T.ok(ui.IsChecked(ui.FindMenuItem(show, L.MENU_SHOW_BAR)))
  T.no(ui.IsChecked(ui.FindMenuItem(show, L.MENU_SHOW_MINI)))
  T.ok(ui.IsChecked(ui.FindMenuItem(show, L.MENU_SHOW_MINIMAP)))
  ui.ClickMenuItem(ui.FindMenuItem(show, L.MENU_SHOW_MINI))
  T.ok(ns.MiniDisplay.frame ~= nil and ns.MiniDisplay.frame:IsShown(), "mini display from the menu")
  ui.ClickMenuItem(ui.FindMenuItem(show, L.MENU_SHOW_BAR))
  T.no(ns.Bar.frame:IsShown(), "bar off from the menu")
  -- Hide (opened from the button) hides the button, not the bar
  ui.ClickMenuItem(ui.FindMenuItem(show, L.MENU_SHOW_BAR))
  local n = #Stub.printed
  ui.ClickMenuItem(ui.FindMenuItem(root, L.MENU_HIDE))
  T.no(b:IsShown(), "button hidden")
  T.eq(ns.Core.GetSetting("minimap.shown"), false)
  T.ok(ns.Bar.frame:IsShown(), "bar untouched")
  T.ok(Printed(L.MINIMAP_HIDDEN, n + 1), "says how to bring it back")
  -- the bar's own menu still hides the bar
  ns.Options.ShowContextMenu(ns.Bar.frame)
  ui.ClickMenuItem(ui.FindMenuItem(ui.lastMenu, L.MENU_HIDE))
  T.no(ns.Bar.frame:IsShown(), "bar menu: the bar")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Slash, help, settings
---------------------------------------------------------------------------

T.test("/tpl minimap toggles the button; /tpl help lists minimap and mini", function()
  local ns, b = Start()
  local L = ns.L
  local n = #Stub.printed
  Stub.RunSlash("minimap")
  T.no(b:IsShown())
  T.eq(ns.Core.GetSetting("minimap.shown"), false)
  T.ok(Printed(L.MINIMAP_HIDDEN, n + 1))
  Stub.RunSlash("MINIMAP")
  T.ok(b:IsShown(), "case-insensitive, shown again")
  T.ok(Printed(L.MINIMAP_SHOWN, n + 1))
  n = #Stub.printed
  Stub.RunSlash("help")
  T.ok(Printed(L.HELP_MINIMAP, n + 1), "help: minimap")
  T.ok(Printed(L.HELP_MINI, n + 1), "help: mini")
  T.ok(find(L.HELP_MINIMAP, "/tpl minimap", 1, true) ~= nil)
  T.ok(find(L.HELP_MINI, "/tpl mini", 1, true) ~= nil)
  T.eq(Stub.errors, {})
end)

T.test("minimap button: hidden at login stays uncreated until shown", function()
  local ns, b = Start({ db = { schema = 1, settings = { minimap = { shown = false } } } })
  T.eq(b, nil, "not created while hidden")
  Stub.RunSlash("minimap")
  b = ns.MinimapButton.button
  T.ok(b ~= nil and b:IsShown(), "created when shown")
end)

T.test("minimap settings: repair drops invalid values, the defaults are not saved", function()
  local ns = Start({ db = { schema = 1, settings = {
    minimap = { shown = "yes", locked = 1, angle = "north", click = "dance" } } } })
  local s = ns.settings.minimap
  T.eq(s, { shown = true, locked = false, angle = 225, click = "stats" }, "back to the defaults")
  T.ok(ns.MinimapButton.button:IsShown())
  T.no(ns.Core.SetSetting("minimap.click", "dance"), "unknown action refused")
  T.ok(ns.Core.SetSetting("minimap.angle", 400), "clamped")
  T.eq(s.angle, 359)
  ns.Core.SetSetting("minimap.angle", 225)
  Stub.Logout()
  T.eq(Stub.saved.settings.minimap, nil, "nothing saved at the defaults")
  -- an out-of-range angle from the file is clamped
  Stub.Reset()
  ns = Start({ db = { schema = 1, settings = { minimap = { angle = -20.4, click = "mini" } } } })
  T.eq(ns.settings.minimap.angle, 0)
  T.eq(ns.settings.minimap.click, "mini")
end)

---------------------------------------------------------------------------
-- The bar hidden; memory
---------------------------------------------------------------------------

T.test("minimap button: with the bar hidden, the tooltip, the statistics and the menu still work", function()
  local ns, b = Start({ db = { schema = 1, settings = { widget = { shown = false } } } })
  T.eq(ns.Bar.frame, nil, "no bar at all")
  for _ = 1, 4 do
    Stub.Advance(30)
    Stub.Kill(171)
  end
  Stub.RunScript(b, "OnEnter")
  T.ok(GameTooltip:NumLines() > 5, "the full tooltip")
  T.ok(ns.Tooltip.IsShownFor(b))
  Stub.Advance(2)
  Stub.RunScript(b, "OnLeave")
  Click(b, "LeftButton")
  T.ok(ns.Window.IsShown(), "statistics")
  Click(b, "RightButton")
  T.ok(Stub.ui.lastMenuOwner == b, "menu")
  T.eq(ns.Bar.frame, nil, "still no bar")
  T.eq(Stub.errors, {})
end)

T.test("minimap button: no garbage per steady tick (bar hidden, button shown)", function()
  local ns, b = Start({ db = { schema = 1, settings = { widget = { shown = false } } } })
  T.ok(b:IsShown())
  Stub.Advance(30)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1.5, format("%.2f KB over 600 ticks", kb))
  T.eq(Stub.onUpdateCount, 0)
  T.ok(ns.MinimapButton.IsShown())
end)
