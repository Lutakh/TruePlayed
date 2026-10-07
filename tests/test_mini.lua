-- tests/test_mini.lua - the mini display (MiniDisplay.lua, design/NEXT-LOT.md backlog 4):
-- opt-in, 1 to 3 infos of the bar's catalog, one line or stacked, the level percentage and
-- the thin XP line, texts that never overlap nor leave the frame (stub widths, then the
-- real fonts of every theme), the bar's theme (fonts, colours, outline, shadow, panel at
-- its own opacity, XP colours) and theme switches, max level, hover / clicks / menu / drag
-- / lock, fade and combat hide, independence from the bar, FPS sampling, no garbage per
-- steady tick, settings repair and sparse save, the options section.
-- The stub measures 6 px per character.
local Stub, T = ...

local format, find = string.format, string.find
local FM = dofile(Stub.ROOT .. "tests/fontmetrics.lua")

local PAD_X, PAD_Y, LINE_H = 8, 5, 3
local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }

-- Loads the addon with the mini display shown (opts.shown = false: the defaults) and
-- logs in. opts.mini / opts.settings: stored settings; opts.theme, opts.level, opts.locale.
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false, modern = opts.modern })
  if opts.theme then Stub.theme = opts.theme end
  if opts.locale then Stub.locale = opts.locale end
  if opts.level then
    Stub.player.level = opts.level
    Stub.player.max = Stub.xpTable[opts.level] or 0
  end
  local settings = opts.settings or {}
  if opts.shown ~= false then
    local m = opts.mini or {}
    if m.shown == nil then m.shown = true end
    settings.mini = m
  end
  rawset(_G, "TruePlayedDB", { schema = 1, settings = settings })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, ns.MiniDisplay.frame
end

local function Play(n)
  for _ = 1, n or 6 do
    Stub.Advance(30)
    Stub.Kill(171)
  end
  Stub.Advance(2)
end

local function Set(ns, path, value)
  ns.Core.SetSetting(path, value)
  Stub.Advance(1)
end

local function Printed(text, from)
  local lines = Stub.printed
  for i = from or 1, #lines do
    if find(lines[i], text, 1, true) then return true end
  end
  return false
end

local function Rgb(c)
  return { math.floor(c[1] * 1000 + 0.5), math.floor(c[2] * 1000 + 0.5), math.floor(c[3] * 1000 + 0.5) }
end

local function TextRgb(fs)
  local r, g, b = fs:GetTextColor()
  return Rgb({ r, g, b })
end

local function SetTextCount(fs)
  return rawget(fs, "_setTextCount") or 0
end

-- Shown texts as { name, l, r, top, bottom } in pixels from the frame's top left corner,
-- from their LEFT anchors on the frame's TOPLEFT and their measured widths.
local function Texts(f)
  local out = {}
  local function add(name, fs)
    if not fs:IsShown() then return end
    local p, rel, rp, x, y = fs:GetPoint(1)
    T.ok(p == "LEFT" and rel == f and rp == "TOPLEFT", name .. ": anchored on the frame")
    local h = rawget(fs, "_fontSize") or 12
    out[#out + 1] = { name = name, l = x, r = x + fs:GetStringWidth(), top = -y - h / 2, bottom = -y + h / 2 }
  end
  local tp = f.tp
  for k = 1, 3 do
    add("info" .. k, tp.items[k])
    add("sep" .. k, tp.seps[k])
  end
  add("pct", tp.pct)
  return out
end

-- Every shown text inside the frame (padding included), no two texts overlapping, the
-- XP line below the texts. Problems go to `bad`.
local function CheckLayout(f, what, bad)
  local W, H = f:GetWidth(), f:GetHeight()
  local list = Texts(f)
  for i, a in ipairs(list) do
    if a.l < PAD_X - 0.01 or a.r > W - PAD_X + 0.01 then
      bad[#bad + 1] = format("%s: %s [%.1f, %.1f] outside 0..%.1f", what, a.name, a.l, a.r, W)
    end
    if a.top < 0 or a.bottom > H + 0.01 then
      bad[#bad + 1] = format("%s: %s [%.1f, %.1f] outside 0..%.1f (height)", what, a.name, a.top, a.bottom, H)
    end
    for j = i + 1, #list do
      local b = list[j]
      local sameRow = a.top < b.bottom and b.top < a.bottom
      if sameRow and a.l < b.r and b.l < a.r then
        bad[#bad + 1] = format("%s: %s and %s overlap", what, a.name, b.name)
      end
    end
    if f.tp.track:IsShown() and a.bottom > H - PAD_Y - LINE_H + 0.01 then
      bad[#bad + 1] = format("%s: %s runs into the XP line", what, a.name)
    end
  end
  return #list
end

-- The infos drawn, in order.
local function Shown(f)
  local out = {}
  for k = 1, 3 do
    local fs = f.tp.items[k]
    if fs:IsShown() then out[#out + 1] = fs:GetText() end
  end
  return out
end

---------------------------------------------------------------------------
-- Defaults, opt-in
---------------------------------------------------------------------------

T.test("mini display: off by default; /tpl mini shows time to level + mobs, XP per hour and the XP line", function()
  local ns, f = Start({ shown = false })
  local L, Tokens = ns.L, ns.Tokens
  T.eq(f, nil, "no frame while off")
  T.no(ns.MiniDisplay.IsActive(), "no consumer")
  T.eq(ns.settings.mini.infos, { "eta_kills", "xph", "none" }, "default infos")
  T.eq(ns.settings.mini.layout, "horizontal")
  T.eq(ns.settings.mini.xp, "line")
  local n = #Stub.printed
  Stub.RunSlash("mini")
  f = ns.MiniDisplay.frame
  T.ok(f ~= nil and f:IsShown(), "shown")
  T.eq(f:GetName(), "TruePlayedMiniDisplay")
  T.ok(Printed(L.MINI_SHOWN, n + 1))
  Play()
  T.eq(Shown(f), { (Tokens.Render("eta_kills")), (Tokens.Render("xph")) }, "the two default infos")
  T.ok(find(f.tp.items[1]:GetText(), "~", 1, true) ~= nil, "mobs to kill in info 1")
  T.ok(f.tp.seps[1]:IsShown() and not f.tp.seps[2]:IsShown(), "one separator")
  T.ok(f.tp.track:IsShown() and f.tp.fill:IsShown(), "the XP line")
  local p = Stub.player
  T.eq(f.tp.fill:GetWidth(), math.floor(f.tp.track:GetWidth() * p.xp / p.max + 0.5), "fill = XP / max")
  T.eq(f.tp.track:GetWidth(), f:GetWidth() - 2 * PAD_X, "the line spans the inner width")
  local bad = {}
  CheckLayout(f, "default", bad)
  T.eq(bad, {})
  n = #Stub.printed
  Stub.RunSlash("mini")
  T.no(f:IsShown(), "/tpl mini again: hidden")
  T.no(ns.MiniDisplay.IsActive())
  T.ok(Printed(L.MINI_HIDDEN, n + 1))
  T.eq(Stub.errors, {})
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Layouts
---------------------------------------------------------------------------

T.test("layouts: one line or stacked, 1 to 3 infos, with or without %: no overlap, inside the frame", function()
  local ns, f = Start({ theme = "futuriste" })
  Play()
  local combos = {
    { "eta_kills", "none", "none" }, { "eta_kills", "xph", "none" }, { "eta_kills", "xph", "fps_latency" },
    { "played", "session", "zone_time" }, { "kills", "none", "pcth" },
  }
  local bad = {}
  for _, layout in ipairs({ "horizontal", "vertical" }) do
    Set(ns, "mini.layout", layout)
    for _, xp in ipairs({ "none", "pct", "line", "both" }) do
      Set(ns, "mini.xp", xp)
      for _, c in ipairs(combos) do
        for i = 1, 3 do ns.Core.SetSetting("mini.infos." .. i, c[i]) end
        Stub.Advance(1)
        local what = layout .. " " .. xp .. " " .. table.concat(c, ",")
        local n = CheckLayout(f, what, bad)
        local want = 0
        for i = 1, 3 do if c[i] ~= "none" then want = want + 1 end end
        T.eq(#Shown(f), want, what .. ": infos drawn")
        local seps = 0
        for k = 1, 3 do if f.tp.seps[k]:IsShown() then seps = seps + 1 end end
        local pct = (xp == "pct" or xp == "both")
        if layout == "horizontal" then
          T.eq(seps, want - 1 + (pct and 1 or 0), what .. ": separators")
        else
          T.eq(seps, 0, what .. ": no separator when stacked")
          -- one line per info (and one for the %), all at the left padding
          local ys = {}
          for k = 1, 3 do
            local fs = f.tp.items[k]
            if fs:IsShown() then
              local _, _, _, x, y = fs:GetPoint(1)
              T.eq(x, PAD_X, what .. ": left aligned")
              T.no(ys[y], what .. ": its own line")
              ys[y] = true
            end
          end
        end
        T.eq(n, want + seps + (pct and 1 or 0), what .. ": texts")
        T.eq(f.tp.pct:IsShown(), pct, what .. ": %")
        T.eq(f.tp.track:IsShown(), xp == "line" or xp == "both", what .. ": XP line")
      end
    end
  end
  T.eq(bad, {}, "layout problems")
  T.eq(Stub.errors, {})
end)

T.test("layouts: the frame follows its texts (wider infos, wider frame)", function()
  local ns, f = Start()
  Play()
  Set(ns, "mini.infos.2", "none")
  local w1 = f:GetWidth()
  Set(ns, "mini.infos.2", "played")
  local w2 = f:GetWidth()
  local sepW = f.tp.seps[1]:GetStringWidth()
  T.eq(w2, w1 + 5 + sepW + 5 + f.tp.items[2]:GetStringWidth(), "info 2 + separator and gaps")
  Set(ns, "mini.layout", "vertical")
  T.eq(f:GetWidth(), 2 * PAD_X + math.max(f.tp.items[1]:GetStringWidth(), f.tp.items[2]:GetStringWidth()),
    "stacked: the widest line")
end)

---------------------------------------------------------------------------
-- Infos
---------------------------------------------------------------------------

T.test("infos: any token of the bar's catalog; unknown ids fall back; info 1 never empty", function()
  local ns, f = Start({ mini = { infos = { "bogus", "none", "session" } } })
  local Tokens = ns.Tokens
  Play()
  T.eq(ns.settings.mini.infos[1], "bogus", "kept by the repair (a newer version's token)")
  T.eq(ns.MiniDisplay.Resolve(1), "eta_kills", "unknown: the default")
  T.eq(Shown(f), { (Tokens.Render("eta_kills")), (Tokens.Render("session")) })
  Set(ns, "mini.infos.1", "none")
  T.eq(ns.MiniDisplay.Resolve(1), "eta_kills", "info 1 never empty")
  for _, id in ipairs(Tokens.ORDER) do
    Set(ns, "mini.infos.3", id)
    local text = Tokens.Render(id)
    local shown = Shown(f)
    if id == "none" or text == "" then
      T.eq(#shown, 1, id .. ": nothing drawn for an empty info")
    else
      T.eq(shown[2], text, id .. ": drawn after info 1 (info 2 is empty)")
    end
  end
  T.eq(Stub.errors, {})
end)

T.test("max level: the XP infos are left out, one of them says Max level", function()
  local ns, f = Start({ level = 60, mini = { infos = { "eta_kills", "xph", "session" }, xp = "both" } })
  local L = ns.L
  Stub.Advance(70)
  T.ok(ns.Tracker.IsMax(), "max level")
  local shown = Shown(f)
  T.eq(#shown, 2)
  T.eq(shown[1], L.MAX_LEVEL, "Max level once")
  T.eq(shown[2], (ns.Tokens.Render("session")))
  T.no(f.tp.pct:IsShown(), "no percentage")
  T.eq(f.tp.fill:GetWidth(), f.tp.track:GetWidth(), "XP line full")
  local _, _, _, a = f.tp.fill:GetVertexColor()
  T.near(a, 0.35, 1e-9, "dimmed")
  T.eq(Stub.errors, {})
end)

T.test("the level percentage (and both): the bar's one-decimal percent, updated with XP", function()
  local ns, f = Start({ mini = { xp = "pct" } })
  local Tokens = ns.Tokens
  Play()
  local p = Stub.player
  T.eq(f.tp.pct:GetText(), Tokens.PercentText(Tokens.PercentTenths(p.xp, p.max)))
  T.no(f.tp.track:IsShown(), "no XP line")
  local before = f.tp.pct:GetText()
  Stub.Kill(171)
  Stub.Advance(2)
  T.ok(f.tp.pct:GetText() ~= before, "follows the XP")
  T.eq(f.tp.pct:GetText(), Tokens.PercentText(Tokens.PercentTenths(p.xp, p.max)))
  local h = f:GetHeight()
  Set(ns, "mini.xp", "both")
  T.ok(f.tp.track:IsShown() and f.tp.pct:IsShown())
  T.eq(f:GetHeight(), h + LINE_H + 3, "the line below the texts")
  Set(ns, "mini.xp", "none")
  T.no(f.tp.track:IsShown() or f.tp.pct:IsShown())
  -- rested: the fill takes the rested colour, as the bar
  Set(ns, "mini.xp", "line")
  local th = ns.Themes.Active()
  T.eq(Rgb({ f.tp.fill:GetVertexColor() }), Rgb(th.colors.xp), "XP colour")
  Stub.player.rest = 3000
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(2)
  T.eq(Rgb({ f.tp.fill:GetVertexColor() }), Rgb(th.colors.rested), "rested colour")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------

-- Font path and size the theme gives an element at size 11 + its delta.
local function ThemeFont(ns, e)
  local th = ns.Themes.Active()
  local path, size = ns.Themes.Font(th.text.font[e] or "body", 11 + (th.text.size[e] or 0))
  return path, size
end

local function ShownPanel(f)
  local n = 0
  for _, t in ipairs(f.tp.panel) do
    if t:IsShown() then n = n + 1 end
  end
  return n
end

local function PanelCount(ns)
  local p = ns.Themes.Active().bar.panel
  local n = 0
  for _, P in ipairs(type(p) == "table" and p.parts or {}) do n = n + (P.kind == "nine" and 9 or 1) end
  return n
end

T.test("theme: the bar's fonts, colours, shadow and panel; a theme switch restyles it", function()
  local ns, f = Start({ theme = "futuriste" })
  Play()
  local tp = f.tp
  local function CheckTheme(key)
    local th = ns.Themes.Active()
    T.eq(ns.Themes.ActiveKey(), key)
    local path, size = ThemeFont(ns, "s1")
    local fp, fsz, flags = tp.items[1]:GetFont()
    T.eq({ fp, fsz }, { path, size }, key .. ": the bar's info 1 font")
    T.ok(find(flags, "OUTLINE", 1, true) ~= nil, key .. ": thin outline (default)")
    path, size = ThemeFont(ns, "sep")
    fp, fsz = tp.seps[1]:GetFont()
    T.eq({ fp, fsz }, { path, size }, key .. ": the separator font")
    T.eq(TextRgb(tp.items[2]), Rgb(th.text.colors.value), key .. ": value colour")
    T.eq(TextRgb(tp.seps[1]), Rgb(th.text.colors.sep), key .. ": separator colour")
    local s = th.text.shadow
    T.eq(rawget(tp.items[1], "_sA"), s and s.c[4] or 0.8, key .. ": the theme's shadow")
    local want = PanelCount(ns)
    T.eq(ShownPanel(f), want, key .. ": the theme's panel parts")
    if want == 0 then
      T.ok(rawget(f, "_backdrop") ~= nil, key .. ": the classic backdrop")
    else
      T.eq(rawget(f, "_backdrop"), nil, key .. ": no backdrop under the panel")
    end
    local bad = {}
    CheckLayout(f, key, bad)
    T.eq(bad, {}, key .. ": layout")
  end
  CheckTheme("futuriste")
  for _, key in ipairs(KEYS) do
    Set(ns, "theme", key)
    CheckTheme(key)
  end
  -- its own opacity: 0 hides the panel (and the backdrop), any other value shows it
  Set(ns, "theme", "futuriste")
  Set(ns, "mini.bgAlpha", 0)
  T.eq(ShownPanel(f), 0, "opacity 0: no panel")
  Set(ns, "mini.bgAlpha", 0.5)
  T.eq(ShownPanel(f), PanelCount(ns))
  local fill = ns.Themes.Active().bar.panel.parts[1]
  local _, _, _, a = tp.panel[1]:GetVertexColor()
  T.near(a, (fill.c and fill.c[4] or 1) * 0.5, 1e-6, "the part's alpha x the opacity")
  Set(ns, "theme", "actuel")
  Set(ns, "mini.bgAlpha", 0)
  T.eq(rawget(f, "_backdrop"), nil, "classic: no backdrop at 0")
  T.eq(Stub.errors, {})
end)

T.test("theme: the bar's text colour, outline, shadow, quality colours and XP colour", function()
  local ns, f = Start({ theme = "heroic", mini = { infos = { "eta_kills", "fps", "none" } } })
  Play()
  local tp = f.tp
  Set(ns, "widget.textColor", { 1, 0.5, 0 })
  T.eq(TextRgb(tp.items[1]), Rgb({ 1, 0.5, 0 }), "custom text colour")
  T.eq(TextRgb(tp.seps[1]), Rgb({ 1, 0.5, 0 }))
  Set(ns, "widget.textColor", false)
  T.eq(TextRgb(tp.items[1]), Rgb(ns.Themes.Active().text.colors.value), "theme colours back")
  Set(ns, "widget.outline", "thick")
  T.eq(select(3, tp.items[1]:GetFont()), "THICKOUTLINE")
  Set(ns, "widget.outline", "none")
  T.eq(select(3, tp.items[1]:GetFont()), "")
  Set(ns, "widget.shadow", false)
  T.eq(rawget(tp.items[1], "_sA"), 0, "no shadow")
  T.ok(find(tp.items[2]:GetText(), "|c", 1, true) ~= nil, "FPS in quality colours")
  Set(ns, "widget.qualityColors", false)
  T.no(find(tp.items[2]:GetText(), "|c", 1, true), "FPS in the text colour")
  Set(ns, "widget.xpColor", { 0, 1, 0 })
  T.eq(Rgb({ tp.fill:GetVertexColor() }), Rgb({ 0, 1, 0 }), "the user's XP colour")
  Set(ns, "widget.xpColor", false)
  T.eq(Rgb({ tp.fill:GetVertexColor() }), Rgb(ns.Themes.Active().colors.xp), "the theme's again")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Mouse
---------------------------------------------------------------------------

T.test("mouse: hover tooltip, click statistics, right-click menu (Hide hides it), drag, lock", function()
  local ns, f = Start()
  local L, ui = ns.L, Stub.ui
  Play()
  Stub.RunScript(f, "OnEnter")
  T.ok(ns.Tooltip.IsShownFor(f), "the bar's tooltip")
  local ls = rawget(GameTooltip, "_lines")
  T.eq(ls[#ls][1], L.TT_HINT, "the bar's hint")
  Stub.RunScript(f, "OnLeave")
  T.no(ns.Tooltip.IsShownFor(f))
  -- left click: statistics
  Stub.RunScript(f, "OnMouseDown", "LeftButton")
  Stub.RunScript(f, "OnMouseUp", "LeftButton")
  T.ok(ns.Window.IsShown(), "statistics")
  ns.Window.Hide()
  -- drag: the new position is saved, the release is not a click
  Stub.RunScript(f, "OnMouseDown", "LeftButton")
  Stub.RunScript(f, "OnDragStart", "LeftButton")
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100.4, -49.6)
  Stub.RunScript(f, "OnDragStop")
  Stub.RunScript(f, "OnMouseUp", "LeftButton")
  T.eq(ns.Core.GetSetting("mini.point"), { "TOPLEFT", "TOPLEFT", 100, -50 }, "saved, rounded")
  T.no(ns.Window.IsShown(), "not a click")
  -- locked: no drag
  Set(ns, "mini.locked", true)
  local moved = false
  rawset(f, "StartMoving", function() moved = true end)
  Stub.RunScript(f, "OnDragStart", "LeftButton")
  T.no(moved, "locked")
  -- reset position (options button)
  ns.MiniDisplay.ResetPosition()
  T.eq(ns.Core.GetSetting("mini.point"), ns.C.DEFAULTS.mini.point)
  T.eq({ f:GetPoint(1) }, { "TOP", UIParent, "TOP", 0, -12 })
  -- right click: the menu, its Hide hides the mini display only
  Stub.RunScript(f, "OnMouseDown", "RightButton")
  Stub.RunScript(f, "OnMouseUp", "RightButton")
  T.ok(ui.lastMenuOwner == f, "menu on the mini display")
  local n = #Stub.printed
  ui.ClickMenuItem(ui.FindMenuItem(ui.lastMenu, L.MENU_HIDE))
  T.no(f:IsShown(), "hidden")
  T.eq(ns.Core.GetSetting("mini.shown"), false)
  T.ok(ns.Bar.frame:IsShown(), "the bar stays")
  T.ok(Printed(L.MINI_HIDDEN, n + 1))
  T.eq(Stub.errors, {})
end)

T.test("fade and hide in combat, as the bar's options", function()
  local ns, f = Start()
  Set(ns, "mini.fade", true)
  T.near(f:GetAlpha(), 0.35, 1e-9, "faded")
  Stub.RunScript(f, "OnEnter")
  T.eq(f:GetAlpha(), 1, "full on hover")
  Stub.RunScript(f, "OnLeave")
  T.near(f:GetAlpha(), 0.35, 1e-9)
  Set(ns, "mini.fade", false)
  T.eq(f:GetAlpha(), 1)
  Set(ns, "mini.combatHide", true)
  Stub.EnterCombat()
  Stub.Advance(1)
  T.eq(f:GetAlpha(), 0, "invisible in combat")
  T.no(f:IsMouseEnabled(), "no mouse in combat")
  T.no(ns.MiniDisplay.IsActive(), "no tick in combat")
  Stub.LeaveCombat()
  Stub.Advance(1)
  T.eq(f:GetAlpha(), 1)
  T.ok(f:IsMouseEnabled())
  T.ok(ns.MiniDisplay.IsActive())
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Independence, sampling, memory
---------------------------------------------------------------------------

T.test("bar hidden: the mini display keeps ticking; an FPS info samples FPS", function()
  local ns, f = Start({ settings = { widget = { shown = false } }, mini = { infos = { "fps", "session", "none" } } })
  T.eq(ns.Bar.frame, nil, "no bar")
  Stub.fps = 60
  Stub.Advance(2)
  T.ok(find(f.tp.items[1]:GetText(), "60", 1, true) ~= nil, "60 fps")
  Stub.fps = 144
  Stub.Advance(1)
  T.ok(find(f.tp.items[1]:GetText(), "144", 1, true) ~= nil, "sampled every tick")
  local calls = Stub.calls.GetFramerate
  Set(ns, "mini.infos.1", "session")
  Stub.Advance(5)
  T.eq(Stub.calls.GetFramerate, calls, "no FPS info, no sampling")
  -- the tooltip of the mini display, with the bar hidden
  Stub.RunScript(f, "OnEnter")
  T.ok(GameTooltip:NumLines() > 5)
  Stub.RunScript(f, "OnLeave")
  T.eq(Stub.errors, {})
end)

T.test("steady ticks: no SetText, no SetSize, no SetFont, no garbage (both layouts, 3 infos, % and line)", function()
  local ns, f = Start({ theme = "futuriste",
    mini = { infos = { "eta_kills", "xph", "fps_latency" }, xp = "both" } })
  Stub.GrantXP(1234)
  -- the rate texts follow the fading pre-install estimate: fixed texts for the steady part
  local Tokens = ns.Tokens
  local render = Tokens.Render
  local fixed = { eta_kills = "~1h 10m \194\183 6 mobs", xph = "~5.5k/h" }
  for _, layout in ipairs({ "horizontal", "vertical" }) do
    Set(ns, "mini.layout", layout)
    Stub.Advance(300)
    Tokens.Render = function(id)
      if fixed[id] then return fixed[id], false, false end
      return render(id)
    end
    Stub.Advance(1)
    local tp = f.tp
    local texts = SetTextCount(tp.items[1]) + SetTextCount(tp.items[2]) + SetTextCount(tp.pct)
    local fonts = Stub.calls.SetFont
    local sizes = 0
    local setSize = f.SetSize
    rawset(f, "SetSize", function(self, ...) sizes = sizes + 1; return setSize(self, ...) end)
    Stub.Advance(60)
    T.eq(SetTextCount(tp.items[1]) + SetTextCount(tp.items[2]) + SetTextCount(tp.pct), texts,
      layout .. ": no SetText over 60 steady ticks")
    T.eq(Stub.calls.SetFont, fonts, layout .. ": no SetFont")
    T.eq(sizes, 0, layout .. ": no SetSize")
    rawset(f, "SetSize", nil)
    local kb = T.alloc(function() Stub.Advance(1) end, 600)
    T.ok(kb <= 1, format("%s: %.2f KB over 600 steady ticks", layout, kb))
    Tokens.Render = render
  end
  T.eq(Stub.onUpdateCount, 0)
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Settings and options
---------------------------------------------------------------------------

T.test("settings: repair drops invalid values; only changed values are saved", function()
  local ns = Start({ shown = false, settings = { mini = {
    shown = "yes", locked = 2, point = { "NOWHERE", 1, 2 }, infos = { 5, "xph" }, layout = "diagonal",
    xp = 3, scale = 9, bgAlpha = -1, fade = "y", combatHide = {} } } })
  local m = ns.settings.mini
  T.eq(m.shown, false)
  T.eq(m.locked, false)
  T.eq(m.point, { "TOP", "TOP", 0, -12 })
  T.eq(m.infos, { "eta_kills", "xph", "none" })
  T.eq(m.layout, "horizontal")
  T.eq(m.xp, "line")
  T.eq(m.scale, 2, "clamped")
  T.eq(m.bgAlpha, 0, "clamped")
  T.eq(m.fade, false)
  T.eq(m.combatHide, false)
  T.eq(ns.MiniDisplay.frame, nil, "not shown")
  T.no(ns.Core.SetSetting("mini.layout", "diagonal"))
  T.no(ns.Core.SetSetting("mini.infos.2", "bogus"), "unknown token refused")
  ns.Core.SetSetting("mini.scale", 1)
  ns.Core.SetSetting("mini.bgAlpha", 0.6)
  Stub.Logout()
  T.eq(Stub.saved.settings.mini, nil, "defaults: nothing saved")
  Stub.Reset()
  ns = Start({ mini = { layout = "vertical" } })
  ns.Core.SetSetting("mini.infos.3", "fps")
  Stub.Logout()
  T.eq(Stub.saved.settings.mini, { shown = true, layout = "vertical", infos = { "eta_kills", "xph", "fps" } })
end)

T.test("options: the minimap and mini display section writes every new setting", function()
  local ns = Start({ shown = false, modern = true })
  local L, ui = ns.L, Stub.ui
  ns.Options.Open()
  local controls = rawget(ui.categories[1].frame, "controls")
  for _, path in ipairs({ "minimap.shown", "minimap.locked", "minimap.click", "mini.shown", "mini.infos.1",
                          "mini.infos.2", "mini.infos.3", "mini.layout", "mini.xp", "mini.scale",
                          "mini.bgAlpha", "mini.locked", "mini.combatHide", "mini.fade" }) do
    T.ok(controls[path] ~= nil, path)
  end
  T.ok(controls["mini.shown"].index > controls["graph.window"].index, "after the FPS section")
  T.ok(controls["mini.shown"].index < controls.rateTau.index, "before Calculation")
  -- info 1 offers no "none"; 2 and 3 do
  local function Values(path)
    local root = rawget(controls[path].widget, "_root")
    local out = {}
    for i, item in ipairs(root.children) do out[i] = item.data.value end
    return out, root
  end
  local v1 = Values("mini.infos.1")
  T.eq(#v1, #ns.Tokens.ORDER - 1)
  T.ok(v1[1] ~= "none")
  T.eq((Values("mini.infos.2"))[1], "none")
  T.eq(Values("minimap.click"), { "stats", "options", "bar", "mini" })
  -- the mini display from its checkbox, then a dropdown choice and a slider
  Stub.RunScript(controls["mini.shown"].widget, "OnClick", "LeftButton")
  T.ok(ns.MiniDisplay.frame ~= nil and ns.MiniDisplay.frame:IsShown(), "checkbox shows it")
  local _, root = Values("mini.layout")
  ui.ClickMenuItem(ui.FindMenuItem(root, L.LAYOUT_V))
  T.eq(ns.settings.mini.layout, "vertical")
  controls["mini.scale"].widget:SetValue(150)
  T.eq(ns.settings.mini.scale, 1.5)
  T.eq(ns.MiniDisplay.frame:GetScale(), 1.5)
  local _, rootClick = Values("minimap.click")
  ui.ClickMenuItem(ui.FindMenuItem(rootClick, L.CLICK_MINI))
  T.eq(ns.settings.minimap.click, "mini")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Real fonts
---------------------------------------------------------------------------

T.test("widths: real fonts, every theme, Latin, Cyrillic and Han texts: no overlap, inside the frame", function()
  local Width = FM.New(Stub.ROOT)
  local restore = FM.Install(Stub, Width)
  local ok, err = pcall(function()
    local bad = {}
    for _, code in ipairs({ "enUS", "deDE", "ruRU", "zhCN" }) do
      for _, key in ipairs(KEYS) do
        Stub.Reset()
        local ns, f = Start({ theme = key, locale = code,
          mini = { infos = { "eta_kills", "played", "fps_latency" }, xp = "both" } })
        Play(4)
        for _, layout in ipairs({ "horizontal", "vertical" }) do
          ns.Core.SetSetting("mini.layout", layout)
          Stub.Advance(1)
          CheckLayout(f, key .. " " .. code .. " " .. layout, bad)
        end
        if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
      end
    end
    T.eq(bad, {}, "real fonts")
  end)
  restore()
  if not ok then error(err, 0) end
end)
