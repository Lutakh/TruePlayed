-- tests/test_bar.lua - Bar.lua, round 3: rested fill colours, text style (colour,
-- outline, shadow, background opacity, quality colours), short forms of a slot
-- (eta_kills), FPS / latency hover regions and the history graph, allocation.
-- Round 4: XP bar and rested colours, server level cap and frozen rate on the bar.
-- The stub measures 6 px per character (colour codes left out).
local Stub, T = ...

local format, find = string.format, string.find

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Loads the addon with the widget shown. opts.xp / opts.rest: the player's XP and
-- rest pool at login; opts.locale.
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false })
  if opts.locale then Stub.locale = opts.locale end
  if opts.xp then Stub.player.xp = opts.xp end
  if opts.rest then Stub.player.rest = opts.rest end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  local f = ns.Bar.frame
  T.ok(f ~= nil, "widget created")
  return ns, f, f.tp
end

local function Set(ns, path, value)
  ns.Core.SetSetting(path, value)
  Stub.Advance(1)
end

-- New rest pool, as the game reports it (UPDATE_EXHAUSTION, then the XP batch).
local function SetRest(amount)
  Stub.player.rest = amount
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
end

local function Rgb(r, g, b)
  return { math.floor(r * 1000 + 0.5), math.floor(g * 1000 + 0.5), math.floor(b * 1000 + 0.5) }
end

local function C3(c)
  return Rgb(c[1], c[2], c[3])
end

local function Vertex(t)
  local r, g, b, a = t:GetVertexColor()
  return Rgb(r, g, b), a
end

local function TextColor(fs)
  local r, g, b, a = fs:GetTextColor()
  return Rgb(r, g, b), a
end

local function Flags(fs)
  local _, _, flags = fs:GetFont()
  return flags
end

local function SetTextCount(fs)
  local n = rawget(fs, "_setTextCount")
  return type(n) == "number" and n or 0
end

-- Replaces the rendering of some tokens by fixed texts: { id = { text, alt } }.
local function FixedTokens(ns, map)
  local Tokens = ns.Tokens
  local render = Tokens.Render
  Tokens.Render = function(id)
    local e = map[id]
    if e then return e[1], false, false, e[2] end
    return render(id)
  end
end

local function Width(fs)
  return fs:GetStringWidth()
end

-- x of the right edge of a text anchored by its BOTTOMRIGHT / BOTTOM point.
local function AnchorX(fs)
  local _, _, _, x = fs:GetPoint(1)
  return x
end

---------------------------------------------------------------------------
-- Rested fill (K8)
---------------------------------------------------------------------------

T.test("rested: blue fill and a lighter gradient part capped at the level end, purple otherwise", function()
  local ns, _, tp = Start({ xp = 2000 })
  local C, tex = ns.C, tp.tex
  -- not rested: the purple accent, no rested part
  T.eq((Vertex(tex.fillM)), C3(C.COLORS.fill), "purple while not rested")
  T.no(tex.rested:IsShown())
  -- record the gradient and the fill colour calls from now on
  local grads, fills = {}, 0
  rawset(tex.rested, "SetGradient", function(_, orient, from, to)
    grads[#grads + 1] = { orient = orient, from = from, to = to }
  end)
  local setVertex = tex.fillM.SetVertexColor
  rawset(tex.fillM, "SetVertexColor", function(self, ...)
    fills = fills + 1
    return setVertex(self, ...)
  end)

  SetRest(3000)
  T.eq((Vertex(tex.fillM)), Rgb(0.0, 0.39, 0.88), "the game's rested blue")
  T.eq(#grads, 1, "gradient applied once")
  local g = grads[1]
  T.eq(g.orient, "HORIZONTAL")
  T.ok(type(g.from) == "table" and type(g.to) == "table", "colour tables")
  T.ok(g.from.b >= 0.99 and g.from.r > 0.0, "lighter blue")
  T.ok(g.to.a < g.from.a, "fading out towards current XP + rested")
  -- 360 px: fill to 2000 / 7600, rested part to 5000 / 7600
  local px = math.floor(360 * 2000 / 7600 + 0.5)
  local rpx = math.floor(360 * 5000 / 7600 + 0.5)
  T.ok(tex.rested:IsShown())
  T.eq(tex.rested:GetWidth(), rpx - px)
  T.eq(fills, 1, "fill colour set once")

  -- steady ticks: no colour call at all
  Stub.Advance(30)
  T.eq(fills, 1, "no fill colour call on steady ticks")
  T.eq(#grads, 1)

  -- a pool larger than the rest of the level: capped at the level end
  SetRest(20000)
  T.eq(tex.rested:GetWidth(), 360 - px, "capped at the level end")
  local _, _, _, tickX = tex.restTick:GetPoint(1)
  T.eq(tickX, 8 + 360 - 1, "rest tick at the end of the bar")
  T.eq(fills, 1, "still rested: same colour, no call")

  -- rest spent: purple again, rested part hidden; rested again: no second gradient
  SetRest(0)
  T.eq((Vertex(tex.fillM)), C3(C.COLORS.fill))
  T.no(tex.rested:IsShown())
  SetRest(500)
  T.eq((Vertex(tex.fillM)), Rgb(0.0, 0.39, 0.88))
  T.eq(#grads, 1, "gradient colours kept on the texture")
  T.eq(fills, 3)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("rested: rested at login, and the fallbacks when the gradient API is missing", function()
  -- rested at login: blue from the first draw
  local ns, _, tp = Start({ xp = 1000, rest = 800 })
  T.eq((Vertex(tp.tex.fillM)), Rgb(0.0, 0.39, 0.88))
  T.ok(tp.tex.rested:IsShown())

  -- a client without the colour-table SetGradient: SetGradientAlpha
  Stub.Reset()
  ns, _, tp = Start({ xp = 1000 })
  local alphaArgs
  rawset(tp.tex.rested, "SetGradient", function() error("bad argument #2") end)
  rawset(tp.tex.rested, "SetGradientAlpha", function(_, ...)
    alphaArgs = { ... }
  end)
  SetRest(800)
  T.ok(alphaArgs ~= nil, "SetGradientAlpha used")
  T.eq(#alphaArgs, 9)
  T.eq(alphaArgs[1], "HORIZONTAL")
  T.ok(alphaArgs[9] < alphaArgs[5], "fading out")

  -- neither API: a flat lighter blue
  Stub.Reset()
  ns, _, tp = Start({ xp = 1000 })
  rawset(tp.tex.rested, "SetGradient", function() error("no") end)
  rawset(tp.tex.rested, "SetGradientAlpha", function() error("no") end)
  SetRest(800)
  local rgb, a = Vertex(tp.tex.rested)
  T.eq(rgb, Rgb(0.35, 0.62, 1.0))
  T.near(a, 0.40, 1e-9)
  T.eq(#Stub.errors, 0, "no error reported")
end)

T.test("max level: purple dimmed, never the rested blue", function()
  Stub.player.level = 60
  Stub.player.xp, Stub.player.max, Stub.player.rest = 0, 0, 5000
  local ns, _, tp = Start()
  T.ok(ns.Tracker.IsMax(), "level 60 is the max level of the stub world")
  local rgb, a = Vertex(tp.tex.fillM)
  T.eq(rgb, C3(ns.C.COLORS.fill))
  T.ok(a < 1, "dimmed")
  T.no(tp.tex.rested:IsShown())
end)

---------------------------------------------------------------------------
-- Text style (K8, F)
---------------------------------------------------------------------------

T.test("text colour: one custom colour on every text, reset to the built-in colours", function()
  local ns, _, tp = Start()
  local C = ns.C
  T.eq(ns.settings.widget.textColor, false, "built-in colours by default")
  T.eq((TextColor(tp.bl)), C3(C.COLORS.label))
  local c1 = TextColor(tp.slots[1])
  T.ok(T.repr(c1) == T.repr(C3(C.COLORS.value)) or T.repr(c1) == T.repr(C3(C.COLORS.dim)),
       "slot 1 white or dim: " .. T.repr(c1))
  local texts = { tp.bl, tp.brx, tp.sep, tp.marker, tp.hint }
  Set(ns, "widget.textColor", { 1, 0.5, 0 })
  for i = 1, #texts do T.eq((TextColor(texts[i])), Rgb(1, 0.5, 0), "text " .. i) end
  for i = 1, 3 do
    local rgb, a = TextColor(tp.slots[i])
    T.eq(rgb, Rgb(1, 0.5, 0), "slot " .. i)
    T.ok(a == 1 or math.abs(a - 0.55) < 1e-9, "full or dimmed (0.55)")
  end
  -- out of range values are clamped
  Set(ns, "widget.textColor", { 2, -1, 0.25 })
  if ns.settings.widget.textColor[1] == 2 then
    T.eq((TextColor(tp.bl)), Rgb(1, 0, 0.25), "clamped to 0..1")
  end
  Set(ns, "widget.textColor", false)
  T.eq((TextColor(tp.bl)), C3(C.COLORS.label), "built-in label grey again")
  T.eq((TextColor(tp.brx)), C3(C.COLORS.label))
end)

T.test("outline none / thin / thick and shadow on / off apply to every text", function()
  local ns, _, tp = Start()
  local texts = { tp.slots[1], tp.slots[2], tp.slots[3], tp.bl, tp.brx, tp.sep, tp.marker, tp.hint }
  T.eq(ns.settings.widget.outline, "thin", "readable default: thin outline")
  T.eq(ns.settings.widget.shadow, true, "readable default: shadow")
  for i = 1, #texts do T.eq(Flags(texts[i]), "OUTLINE", "default " .. i) end
  local expect = { none = "", thick = "THICKOUTLINE", thin = "OUTLINE" }
  for _, v in ipairs({ "none", "thick", "thin" }) do
    Set(ns, "widget.outline", v)
    for i = 1, #texts do T.eq(Flags(texts[i]), expect[v], v .. " " .. i) end
  end
  for i = 1, #texts do
    T.eq(rawget(texts[i], "_shadowX"), 1)
    T.eq(rawget(texts[i], "_shadowY"), -1)
  end
  Set(ns, "widget.shadow", false)
  for i = 1, #texts do
    T.eq(rawget(texts[i], "_shadowX"), 0, "no shadow " .. i)
    T.eq(rawget(texts[i], "_sA"), 0)
  end
  Set(ns, "widget.shadow", true)
  T.eq(rawget(tp.bl, "_shadowX"), 1)
  T.ok(rawget(tp.bl, "_sA") > 0)
end)

T.test("background: none at 0, the chosen opacity, a legacy on/off background at 0.85", function()
  local ns, f = Start()
  T.eq(ns.settings.widget.bgAlpha, 0, "no background by default")
  T.eq(f:GetBackdrop(), nil)
  Set(ns, "widget.bgAlpha", 0.5)
  T.ok(f:GetBackdrop() ~= nil)
  T.near(rawget(f, "_bgA"), 0.5, 1e-9)
  local bd = ns.C.COLORS.border
  T.near(rawget(f, "_bdA"), (bd[4] or 1) * 0.5 / 0.85, 1e-9, "border fades with the background")
  Set(ns, "widget.bgAlpha", 1)
  T.near(rawget(f, "_bgA"), 1, 1e-9)
  T.near(rawget(f, "_bdA"), bd[4] or 1, 1e-9)
  Set(ns, "widget.bgAlpha", 0)
  T.eq(f:GetBackdrop(), nil)
  -- a record the migration has not seen: the former on/off switch
  local w = ns.settings.widget
  w.bgAlpha, w.background = nil, true
  ns.Bar.ApplyLayout()
  T.near(rawget(f, "_bgA"), 0.85, 1e-9)
  w.background = false
  ns.Bar.ApplyLayout()
  T.eq(f:GetBackdrop(), nil)
end)

T.test("quality colours off: FPS / latency in the text colour, back on: green / yellow / red", function()
  local ns, _, tp = Start()
  Set(ns, "widget.slots.3", "fps_latency")
  local s3 = tp.slots[3]
  T.ok(find(s3:GetText(), "|c", 1, true) ~= nil, "coloured numbers by default")
  Set(ns, "widget.qualityColors", false)
  local plain = s3:GetText()
  T.no(find(plain, "|c", 1, true), "no colour code")
  T.eq(plain, ns.Tokens.Plain((ns.Tokens.Render("fps_latency"))))
  -- steady: the stripped text is cached (no SetText, no garbage)
  local n = SetTextCount(s3)
  Stub.Advance(20)
  T.eq(SetTextCount(s3), n)
  Set(ns, "widget.qualityColors", true)
  T.ok(find(s3:GetText(), "|c", 1, true) ~= nil)
  -- other tokens are left as they are
  Set(ns, "widget.slots.3", "session")
  T.eq(s3:GetText(), (ns.Tokens.Render("session")))
end)

---------------------------------------------------------------------------
-- Short forms (K5 eta_kills in the bar)
---------------------------------------------------------------------------

local FULL = "~2 h 05 min \194\183 38 mobs"     -- 21 characters: 126 px
local SHORT = "~2 h 05 min"                      -- 11 characters: 66 px

T.test("top row: eta_kills uses its short form rather than dropping slot 3", function()
  local ns, _, tp = Start()
  FixedTokens(ns, { eta_kills = { FULL, SHORT }, session = { "Sess. 1 h 00", nil } })   -- 12 ch: 72 px
  Set(ns, "widget.slots.1", "eta_kills")
  Set(ns, "widget.slots.3", "session")
  local s1, s3 = tp.slots[1], tp.slots[3]
  local shortSeen = false
  for width = 360, 150, -10 do                      -- widget.width steps by 10
    Set(ns, "widget.width", width)
    local t1 = s1:GetText()
    T.ok(t1 == FULL or t1 == SHORT, "slot 1 text at " .. width)
    T.ok(s3:IsShown(), "slot 3 kept at " .. width)
    -- slot 3 (centred on its anchor) stays 8 px clear of slot 1 (right-aligned)
    local left1 = 8 + width - Width(s1)
    local right3 = AnchorX(s3) + Width(s3) / 2
    T.ok(right3 <= left1 - 8, format("no overlap at %d: %s / %s", width, right3, left1))
    if t1 == SHORT then
      shortSeen = true
      -- the full text would not have left room for slot 3
      T.ok(width < 206, "short form only when needed (" .. width .. ")")
    else
      T.ok(width >= 206, "full text when it fits (" .. width .. ")")
    end
  end
  T.ok(shortSeen, "short form used on a narrow bar")
  Set(ns, "widget.width", 360)
  T.eq(s1:GetText(), FULL, "full text again")
end)

T.test("top row: slot 3 left out only when even the short form leaves no room", function()
  local ns, _, tp = Start()
  FixedTokens(ns, { eta_kills = { FULL, SHORT }, session = { "Session 1 h 23 min 4", nil } })   -- 20 ch: 120 px
  Set(ns, "widget.slots.1", "eta_kills")
  Set(ns, "widget.slots.3", "session")
  Set(ns, "widget.width", 150)
  T.no(tp.slots[3]:IsShown(), "no room for slot 3")
  T.eq(tp.slots[1]:GetText(), FULL, "slot 1 alone keeps its full text when it fits")
  Set(ns, "widget.width", 200)
  T.ok(tp.slots[3]:IsShown())
  T.eq(tp.slots[1]:GetText(), SHORT)
end)

T.test("bottom row: slot 2 short form before dropping it; box style: short form in a half row", function()
  local ns, _, tp = Start()
  FixedTokens(ns, { eta_kills = { FULL, SHORT } })
  Set(ns, "widget.slots.2", "eta_kills")
  local s2 = tp.slots[2]
  T.eq(s2:GetText(), FULL, "full text at the default width")
  local shortSeen = false
  for width = 360, 150, -10 do
    Set(ns, "widget.width", width)
    local blRight = 8 + Width(tp.bl)
    if s2:IsShown() then
      local t2 = s2:GetText()
      T.ok(t2 == FULL or t2 == SHORT)
      if t2 == SHORT then shortSeen = true end
      T.ok(8 + width - Width(s2) >= blRight + 6, "slot 2 clear of the level text at " .. width)
    end
    if tp.brx:IsShown() then
      local left = AnchorX(tp.brx) - Width(tp.brx)
      T.ok(left >= blRight + 6, "XP text clear of the level text at " .. width)
    end
  end
  T.ok(shortSeen, "slot 2 short form used before slot 2 is dropped")

  Set(ns, "widget.width", 360)
  Set(ns, "widget.style", "box")
  T.eq(s2:GetText(), SHORT, "box: 126 px do not fit the 80 px half row")
  Set(ns, "widget.slots.1", "eta_kills")
  T.eq(tp.slots[1]:GetText(), FULL, "box: slot 1 has 158 px")
  Set(ns, "widget.style", "bar")
  T.eq(tp.slots[1]:GetText(), FULL)
end)

---------------------------------------------------------------------------
-- FPS / latency hover regions and the graph (K6)
---------------------------------------------------------------------------

T.test("hover regions: only over FPS / latency slots, graph instead of the tooltip", function()
  local ns, f, tp = Start()
  local Graph, Tooltip = ns.Graph, ns.Tooltip
  Set(ns, "widget.slots.3", "fps_latency")
  Set(ns, "widget.slots.2", "xph")
  local h3 = tp.hits[3]
  T.ok(h3 ~= nil and h3:IsShown(), "region over slot 3")
  T.ok(tp.hits[2] == nil or not tp.hits[2]:IsShown(), "none over slot 2")
  T.ok(rawget(h3, "_allPoints") == tp.slots[3], "covers the slot text")
  -- widget hovered: tooltip; moving onto the FPS text: graph only
  Stub.RunScript(f, "OnEnter")
  T.ok(Tooltip.IsShownFor(f), "tooltip over the widget")
  Stub.RunScript(f, "OnLeave")
  Stub.RunScript(h3, "OnEnter")
  T.no(Tooltip.IsShownFor(f), "never both")
  T.ok(Graph.IsShown(), "graph shown")
  T.ok(Graph.GetAnchor() == h3)
  Stub.Advance(3)
  T.ok(Graph.IsShown(), "stays while hovered")
  Stub.RunScript(h3, "OnLeave")
  T.no(Graph.IsShown(), "hidden when the mouse leaves the text (not onto the graph)")

  -- slot changed to a non-network token: region hidden
  Set(ns, "widget.slots.3", "session")
  T.no(h3:IsShown())
  Set(ns, "widget.slots.2", "fps")
  T.ok(tp.hits[2] ~= nil and tp.hits[2]:IsShown(), "created on first need")
  Set(ns, "widget.slots.1", "latency")
  T.ok(tp.hits[1] ~= nil and tp.hits[1]:IsShown())

  -- widget hidden: regions and graph hidden
  Stub.RunScript(tp.hits[2], "OnEnter")
  T.ok(Graph.IsShown())
  Set(ns, "widget.shown", false)
  T.no(Graph.IsShown(), "graph hidden with the widget")
  T.no(tp.hits[2]:IsShown())
  Set(ns, "widget.shown", true)
  T.ok(tp.hits[2]:IsShown())
  T.no(Graph.IsShown(), "not shown again without a hover")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("hover regions: clicks and drags act on the widget", function()
  local ns, f, tp = Start()
  local Graph = ns.Graph
  Set(ns, "widget.slots.3", "fps_latency")
  local h = tp.hits[3]
  Stub.RunScript(h, "OnMouseDown", "LeftButton")
  Stub.RunScript(h, "OnMouseUp", "LeftButton")
  T.ok(ns.Window.IsShown(), "left click toggles the window")
  Stub.RunScript(h, "OnMouseDown", "LeftButton")
  Stub.RunScript(h, "OnMouseUp", "LeftButton")
  T.no(ns.Window.IsShown())
  local menus = Stub.ui.menus
  Stub.RunScript(h, "OnMouseUp", "RightButton")
  T.eq(Stub.ui.menus, menus + 1, "right click: context menu")
  T.ok(Stub.ui.lastMenuOwner == f, "menu of the widget")
  -- a drag from the text moves the widget and hides the graph
  T.eq(ns.settings.widget.locked, false, "unlocked at first run")
  Stub.RunScript(h, "OnEnter")
  T.ok(Graph.IsShown())
  Stub.RunScript(h, "OnMouseDown", "LeftButton")
  Stub.RunScript(h, "OnDragStart")
  T.no(Graph.IsShown(), "graph hidden while dragging")
  Stub.RunScript(h, "OnDragStop")
  T.eq(type(ns.settings.widget.point), "table", "position saved")
  Stub.RunScript(h, "OnMouseUp", "LeftButton")
  T.no(ns.Window.IsShown(), "a drag is not a click")
  -- the drag is over: hovering the text shows the graph again, a click is a click again
  Stub.RunScript(h, "OnLeave")
  Stub.RunScript(h, "OnEnter")
  T.ok(Graph.IsShown(), "graph after a drag")
  Stub.RunScript(h, "OnMouseDown", "LeftButton")
  Stub.RunScript(h, "OnMouseUp", "LeftButton")
  T.ok(ns.Window.IsShown(), "click after a drag")
end)

T.test("drag: the new position is saved whichever of OnDragStop / OnMouseUp comes first", function()
  local ns, f = Start()
  T.eq(ns.settings.widget.locked, false, "unlocked at first run")
  local function Drag(x, y, mouseUpFirst)
    Stub.RunScript(f, "OnMouseDown", "LeftButton")
    Stub.RunScript(f, "OnDragStart")
    T.eq(rawget(f, "_moving"), true, "moving")
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, y)   -- where the mouse took it
    if mouseUpFirst then
      Stub.RunScript(f, "OnMouseUp", "LeftButton")
      Stub.RunScript(f, "OnDragStop")
    else
      Stub.RunScript(f, "OnDragStop")
      Stub.RunScript(f, "OnMouseUp", "LeftButton")
    end
    T.eq(rawget(f, "_moving"), false, "stopped")
  end
  Drag(111, -222, false)
  T.eq(ns.settings.widget.point, { "TOPLEFT", "TOPLEFT", 111, -222 }, "drag stop, then mouse up")
  T.no(ns.Window.IsShown(), "not a click")
  Drag(333.4, -444.6, true)
  T.eq(ns.settings.widget.point, { "TOPLEFT", "TOPLEFT", 333, -445 }, "mouse up, then drag stop")
  T.no(ns.Window.IsShown(), "not a click")
  -- after either order: the tooltip on hover, and a click is a click
  Stub.RunScript(f, "OnEnter")
  T.ok(ns.Tooltip.IsShownFor(f), "tooltip after a drag")
  Stub.RunScript(f, "OnLeave")
  Stub.RunScript(f, "OnMouseDown", "LeftButton")
  Stub.RunScript(f, "OnMouseUp", "LeftButton")
  T.ok(ns.Window.IsShown(), "click after a drag")
end)

T.test("combatHide: the hover regions follow the widget", function()
  local ns, _, tp = Start()
  Set(ns, "widget.slots.3", "fps_latency")
  Set(ns, "widget.combatHide", true)
  T.ok(tp.hits[3]:IsShown())
  Stub.EnterCombat()
  Stub.Advance(1)
  T.no(tp.hits[3]:IsShown(), "no hover region while hidden in combat")
  Stub.LeaveCombat()
  Stub.Advance(1)
  T.ok(tp.hits[3]:IsShown())
end)

---------------------------------------------------------------------------
-- Performance
---------------------------------------------------------------------------

T.test("allocation: 600 ticks with the bar and the hovered graph, no extra SetText", function()
  local ns, _, tp = Start()
  Set(ns, "widget.slots.3", "fps_latency")
  Set(ns, "widget.qualityColors", false)
  Stub.Advance(300)
  local slots = tp.slots
  local function Counts()
    return { SetTextCount(slots[1]), SetTextCount(slots[2]), SetTextCount(slots[3]),
             SetTextCount(tp.bl), SetTextCount(tp.brx) }
  end
  local c0 = Counts()
  Stub.Advance(60)
  T.eq(Counts(), c0, "no SetText over 60 steady ticks")
  local step = function() Stub.Advance(1) end
  local kb = T.alloc(step, 600)
  T.ok(kb <= 2, format("bar visible: %.2f KB over 600 ticks", kb))
  -- graph shown over the FPS text: steady values, nothing more
  Stub.RunScript(tp.hits[3], "OnEnter")
  T.ok(ns.Graph.IsShown())
  Stub.Advance(120)
  kb = T.alloc(step, 600)
  T.ok(kb <= 2, format("bar + graph: %.2f KB over 600 ticks", kb))
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Round 4: bar colours (R4, C4), server level cap and frozen rate on the bar (C1, C2)
---------------------------------------------------------------------------

-- Sets a widget setting through Core.SetSetting (C4 for the colours). SetSetting refuses
-- an unchanged value: it must then be the stored one, and SETTINGS_CHANGED is sent
-- anyway, to check that the bar redraws nothing for it.
local function SetBarColor(ns, path, value)
  if not ns.Core.SetSetting(path, value) then
    local leaf = path:match("^widget%.(.+)$")
    T.eq(ns.settings.widget[leaf], value, "setting accepted: " .. path)
    ns.SendMessage("SETTINGS_CHANGED", path, value)
  end
  Stub.Advance(1)
end

local function Lighter(c, k)
  return { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] + (1 - c[3]) * k }
end

T.test("bar colours: custom XP and rested colours, a lighter rested part, back to the game's colours", function()
  local ns, _, tp = Start({ xp = 2000 })
  local C, tex = ns.C, tp.tex
  local grads = {}
  rawset(tex.rested, "SetGradient", function(_, orient, from, to)
    grads[#grads + 1] = { orient = orient, from = { from.r, from.g, from.b, from.a }, to = { to.r, to.g, to.b, to.a } }
  end)
  T.eq(ns.settings.widget.xpColor or false, false, "the game's colours by default")
  T.eq(ns.settings.widget.restedColor or false, false)
  T.eq((Vertex(tex.fillM)), C3(C.COLORS.fill))

  -- XP colour: the fill while not rested
  SetBarColor(ns, "widget.xpColor", { 1, 0.5, 0 })
  T.eq((Vertex(tex.fillM)), Rgb(1, 0.5, 0), "orange fill")
  T.eq((Vertex(tex.fillL)), Rgb(1, 0.5, 0), "rounded ends too")
  -- rested: the game's blue until a rested colour is chosen
  SetRest(3000)
  T.eq((Vertex(tex.fillM)), Rgb(0.0, 0.39, 0.88))
  T.eq(#grads, 1)
  T.eq(C3(grads[1].from), Rgb(0.35, 0.62, 1.0), "built-in lighter blue")
  -- rested colour: the fill, the rested part (lighter, fading) and its end tick
  SetBarColor(ns, "widget.restedColor", { 0, 0.8, 0.2 })
  T.eq((Vertex(tex.fillM)), Rgb(0, 0.8, 0.2), "green rested fill")
  T.eq(#grads, 2, "rested part recoloured at once")
  local g = grads[2]
  T.eq(C3(g.from), C3(Lighter({ 0, 0.8, 0.2 }, 0.35)), "lighter shade")
  T.eq(C3(g.to), C3(g.from))
  T.ok(g.to[4] < g.from[4], "still fading out")
  T.eq((Vertex(tex.restTick)), C3(Lighter({ 0, 0.8, 0.2 }, 0.6)), "end tick lighter still")
  -- steady ticks: no colour call
  local calls = 0
  local set = tex.fillM.SetVertexColor
  rawset(tex.fillM, "SetVertexColor", function(self, ...)
    calls = calls + 1
    return set(self, ...)
  end)
  Stub.Advance(30)
  T.eq(calls, 0, "no colour call on steady ticks")
  T.eq(#grads, 2)
  -- rest spent: the XP colour again
  SetRest(0)
  T.eq((Vertex(tex.fillM)), Rgb(1, 0.5, 0))
  -- the same value again: nothing redrawn
  SetBarColor(ns, "widget.xpColor", { 1, 0.5, 0 })
  T.eq(calls, 1)
  -- back to the game's colours (what the options' reset button does)
  SetBarColor(ns, "widget.xpColor", false)
  SetBarColor(ns, "widget.restedColor", false)
  T.eq((Vertex(tex.fillM)), C3(C.COLORS.fill), "purple again")
  SetRest(500)
  T.eq((Vertex(tex.fillM)), Rgb(0.0, 0.39, 0.88), "blue again")
  T.eq(C3(grads[#grads].from), Rgb(0.35, 0.62, 1.0), "built-in rested part again")
  T.eq((Vertex(tex.restTick)), C3(C.COLORS.restTick))
  T.eq(#Stub.errors, 0)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("bar colours: the box style and the max level use them too; a flat rested part without gradients", function()
  Stub.player.level = 60
  Stub.player.xp, Stub.player.max, Stub.player.rest = 0, 0, 0
  local ns, _, tp = Start()
  SetBarColor(ns, "widget.xpColor", { 0.2, 0.9, 0.9 })
  local rgb, a = Vertex(tp.tex.fillM)
  T.eq(rgb, Rgb(0.2, 0.9, 0.9), "max level: the XP colour")
  T.ok(a < 1, "dimmed")
  -- box style, below max level, no gradient API: flat lighter rested colour
  Stub.Reset()
  ns, _, tp = Start({ xp = 1000 })
  rawset(tp.tex.rested, "SetGradient", function() error("no") end)
  rawset(tp.tex.rested, "SetGradientAlpha", function() error("no") end)
  SetBarColor(ns, "widget.style", "box")
  SetBarColor(ns, "widget.restedColor", { 1, 0, 0 })
  SetRest(800)
  T.eq((Vertex(tp.tex.fillM)), Rgb(1, 0, 0))
  local flat, fa = Vertex(tp.tex.rested)
  T.eq(flat, C3(Lighter({ 1, 0, 0 }, 0.35)))
  T.near(fa, 0.40, 1e-9)
  -- invalid stored values read as the game's colours
  ns.settings.widget.restedColor = { "x" }
  ns.Bar.ApplyLayout()
  T.eq((Vertex(tp.tex.fillM)), Rgb(0.0, 0.39, 0.88))
  T.eq(#Stub.errors, 0, "no error reported")
end)

T.test("bar colours: every change of a stored colour redraws (no two colours share a change key)", function()
  local ns, _, tp = Start({ xp = 2000 })
  local tex = tp.tex
  -- each pair differs by one thousandth carried into the next component: with a key
  -- r * 1e6 + g * 1e3 + b (components 0..1000) both colours of a pair got the same key
  local pairs3 = {
    { { 0, 1, 0 }, { 0.001, 0, 0 } },
    { { 0, 0, 1 }, { 0, 0.001, 0 } },
    { { 0.5, 1, 1 }, { 0.501, 0.001, 0 } },
  }
  for _, p in ipairs(pairs3) do
    SetBarColor(ns, "widget.xpColor", p[1])
    T.eq((Vertex(tex.fillM)), Rgb(p[1][1], p[1][2], p[1][3]))
    SetBarColor(ns, "widget.xpColor", p[2])
    T.eq((Vertex(tex.fillM)), Rgb(p[2][1], p[2][2], p[2][3]), "fill follows the second colour")
  end
  SetRest(800)
  SetBarColor(ns, "widget.restedColor", { 0, 1, 0 })
  SetBarColor(ns, "widget.restedColor", { 0.001, 0, 0 })
  T.eq((Vertex(tex.fillM)), Rgb(0.001, 0, 0), "rested fill follows too")
  T.eq(#Stub.errors, 0)
end)

-- Makes the Tracker answer like the engine at a detected server level cap (C2) while
-- `state.capped` is true.
local function FakeCap(ns, state)
  local Tracker = ns.Tracker
  local isMax = Tracker.IsMax
  Tracker.IsMax = function()
    if state.capped then return true end
    return isMax()
  end
  Tracker.GetCapInfo = function()
    if state.capped then return ns.char.level, true, 3 end
    return nil, false, 0
  end
end

T.test("server level cap: max-level look and 'NIVEAU 10 · PLAFOND' at the next tick, back with XP (frFR)", function()
  local ns, f, tp = Start({ locale = "frFR", xp = 2000 })
  local L = ns.L
  local state = { capped = false }
  FakeCap(ns, state)
  Stub.Advance(1)
  T.eq(tp.bl:GetText(), "NIVEAU 10")
  T.ok(tp.brx:GetText() ~= "", "XP text")
  -- the engine sets the cap after a fight, without an XP message: the tick notices
  state.capped = true
  Stub.Advance(1)
  T.eq(tp.bl:GetText(), "NIVEAU 10 \194\183 PLAFOND")
  T.eq(tp.bl:GetText(), format(L.LEVEL_CAP_FMT, 10))
  local _, a = Vertex(tp.tex.fillM)
  T.ok(a < 1, "full and dimmed like at max level")
  T.eq(tp.tex.fillM:GetWidth() > 300, true, "drawn full")
  T.eq(tp.brx:GetText(), "", "no XP text")
  T.no(tp.marker:IsShown(), "no percent marker")
  T.eq(ns.Tokens.Resolve(1), "session", "max-level infos")
  T.eq(tp.slots[1]:GetText(), (ns.Tokens.Render("session")), "slot 1 shows the session time")
  -- hideAtMax does not hide the widget at a server cap (temporary, explained on hover)
  ns.Core.SetSetting("widget.hideAtMax", true)
  Stub.Advance(1)
  T.ok(f:IsShown(), "still shown at the server cap")
  Stub.RunScript(f, "OnEnter")
  local found = false
  for _, l in ipairs(GameTooltip._lines) do
    if l[1] == format(L.TT_CAP_FMT, 10, 3) then found = true end
  end
  T.ok(found, "hover explains the cap")
  Stub.RunScript(f, "OnLeave")
  -- steady at the cap: no SetText, nothing allocated beyond the per-minute texts
  Stub.Advance(60)
  local n = SetTextCount(tp.bl)
  Stub.Advance(30)
  T.eq(SetTextCount(tp.bl), n, "level text set once")
  -- XP again: the engine clears the cap, the bar is back at the next tick
  state.capped = false
  Stub.Advance(1)
  T.eq(tp.bl:GetText(), "NIVEAU 10")
  T.ok(tp.brx:GetText() ~= "")
  local px = math.floor(360 * 2000 / 7600 + 0.5)
  T.eq(tp.tex.fillM:GetWidth() <= px, true, "fill back to the XP")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("hideAtMax: hidden at the real max level reached without an XP message", function()
  local ns, f = Start()
  local Tracker = ns.Tracker
  ns.Core.SetSetting("widget.hideAtMax", true)
  Stub.Advance(1)
  T.ok(f:IsShown())
  local real = false
  Tracker.IsMax = function() return real end
  Tracker.GetCapInfo = function() return nil, false, 0 end
  real = true
  Stub.Advance(1)
  T.no(f:IsShown(), "hidden at the next tick")
  T.no(ns.Tokens.IsActive())
end)

T.test("server level cap with a narrow bar and a big font: the level alone, nothing overlaps", function()
  local ns, _, tp = Start({ locale = "frFR" })
  local state = { capped = true }
  FakeCap(ns, state)
  Stub.Advance(1)
  ns.Core.SetSetting("widget.fontSize", 16)
  ns.Core.SetSetting("widget.width", 150)
  Stub.Advance(1)
  local text = tp.bl:GetText()
  T.ok(Width(tp.bl) <= 150, "inside the bar: " .. text)
  if tp.slots[2]:IsShown() and tp.slots[2]:GetText() ~= "" then
    T.ok(8 + 150 - Width(tp.slots[2]) >= 8 + Width(tp.bl) + 6, "slot 2 clear of the level text")
  end
end)

T.test("frozen rate on the bar: the marked value, dimmed, set once", function()
  local ns, _, tp = Start()
  local Stats, Tracker, C = ns.Stats, ns.Tracker, ns.C
  local rate = Stats.Rate
  local frozen
  Stats.Rate = function(char, mask)
    frozen = frozen or { rate(char, mask) }
    local f = frozen
    return 8200, f[2], f[3], f[4], "ema", "stalled", 0, 7200
  end
  Tracker.GetStall = function() return true, 7200 end
  Stub.Advance(1)
  T.eq(tp.slots[2]:GetText(), "8.2k/h*")
  T.eq((TextColor(tp.slots[2])), C3(C.COLORS.dim), "dimmed")
  local n = SetTextCount(tp.slots[2])
  Stub.Advance(60)
  T.eq(SetTextCount(tp.slots[2]), n, "set once")
  local kb = T.alloc(function() Stub.Advance(1) end, 300)
  T.ok(kb <= 1.5, format("frozen: %.2f KB over 300 ticks", kb))
  Stats.Rate = rate
  Stub.Advance(1)
  T.no(tp.slots[2]:GetText():find("*", 1, true), "live again")
end)
