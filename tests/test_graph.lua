-- tests/test_graph.lua - Graph.lua: FPS / latency history (ring buffers, columns, step
-- line, readout, windows, hide logic, allocation). The widget is hidden so the only
-- samples are the ones each test feeds through Graph.Sample.
local Stub, T = ...

local format = string.format

-- Loads the addon with the widget hidden (no token consumer, no sampling of its own).
local function Start(opts)
  opts = opts or {}
  rawset(_G, "LibStub", nil)
  if opts.locale then Stub.locale = opts.locale end
  rawset(_G, "TruePlayedDB", {
    schema = 1,
    settings = { widget = { shown = false }, requestPlayedAtLogin = false, graph = { window = opts.window or 60 } },
  })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns
end

-- Text region the graph belongs to (upper half of the screen: the panel goes below it).
local function Owner(y)
  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(80, 14)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, y or 300)
  return f
end

-- n ticks; fn(i) returns fps, latHome, latWorld for tick i (nil = no sample).
local function Feed(Graph, n, fn)
  for i = 1, n do
    Stub.Advance(1)
    local f, h, w = fn(i)
    Graph.Sample(Stub.Now(), f, h, w)
  end
end

-- An XP gain: the engine's stall guard (C1) creates its tables once, the first time
-- C.XP_STALL s pass without XP; the allocation windows below start right after a gain
-- so they never include that one-time step.
local function Gain()
  Stub.GrantXP(1)
end

-- Latency re-read every 5 ticks, like Tokens (C.NET_INTERVAL).
local function Every5(i, ms)
  if i % 5 == 1 then return ms, ms end
  return nil, nil
end

local function Color(t)
  local r, g, b = t:GetVertexColor()
  return { r, g, b }
end

local function Rgb(c)
  return { c[1], c[2], c[3] }
end

local function Shown(list)
  local n = 0
  for i = 1, #list do
    if list[i]:IsShown() then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------
-- Samples and ring buffers
---------------------------------------------------------------------------

T.test("lazy: samples create no frame; the panel appears at the first ShowFor", function()
  local ns = Start()
  local Graph = ns.Graph
  T.ok(Graph ~= nil, "ns.Graph")
  Feed(Graph, 10, function() return 60, 40, 42 end)
  T.eq(Graph.frame, nil, "no panel before a hover")
  T.no(Graph.IsShown())
  local owner = Owner()
  Graph.ShowFor(owner)
  T.ok(Graph.frame ~= nil and Graph.frame:IsShown(), "panel shown")
  T.ok(Graph.IsShown())
  T.ok(Graph.GetAnchor() == owner)
  T.eq((Graph.frame:GetPoint(1)), "TOP", "below a text in the upper half")
  Graph.Hide()
  Graph.ShowFor(Owner(-300))
  T.eq((Graph.frame:GetPoint(1)), "BOTTOM", "above a text in the lower half")
  T.eq(Graph.frame:GetFrameStrata(), "TOOLTIP")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("ring: one FPS sample per tick at most, latency only when re-read, 300 kept", function()
  local ns = Start()
  local Graph = ns.Graph
  local now = Stub.Now()
  Graph.Sample(now, 60, nil, nil)
  Graph.Sample(now + 0.2, 61, nil, nil)          -- a data message in the same tick
  T.eq({ Graph.SampleCount() }, { 1, 0 })
  Graph.Sample(now + 1, 62, 40, 55)
  T.eq({ Graph.SampleCount() }, { 2, 1 })
  Graph.Sample(now + 2, nil, nil, nil)            -- nothing to keep
  Graph.Sample(now + 3, 0 / 0, nil, nil)          -- NaN ignored
  T.eq({ Graph.SampleCount() }, { 2, 1 })
  -- 400 more ticks: the oldest samples are dropped, the count stays at 300
  Stub.Advance(1)
  Feed(Graph, 400, function(i) return i, Every5(i, 100) end)
  local nf, nl = Graph.SampleCount()
  T.eq(nf, 300)
  T.eq(nl, 81, "every re-read kept (under 300)")
  -- 5 min graph: column 1 holds the samples 101..105 (average 103), column 60 396..400
  ns.settings.graph.window = 300
  Graph.ShowFor(Owner())
  local tp = Graph.frame.tp
  T.near(tp.colF[1], 103, 1e-9)
  T.near(tp.colF[60], 398, 1e-9)
end)

---------------------------------------------------------------------------
-- Charts
---------------------------------------------------------------------------

T.test("1 min: one column per sample, bars scaled to 60 fps and coloured by quality", function()
  local ns = Start()
  local Graph, COLORS = ns.Graph, ns.C.COLORS
  Feed(Graph, 70, function(i) return (i <= 60) and 60 or 25, Every5(i, 42) end)
  local owner = Owner()
  Graph.ShowFor(owner)
  local tp = Graph.frame.tp
  for k = 1, 50 do T.eq(tp.colF[k], 60, "column " .. k) end
  for k = 51, 60 do T.eq(tp.colF[k], 25, "column " .. k) end
  T.eq(tp.bars[1]:GetHeight(), 40, "60 fps = full height")
  T.eq(tp.bars[60]:GetHeight(), 17, "25 fps: round(25 / 60 * 40)")
  T.eq(Color(tp.bars[1]), Rgb(COLORS.good))
  T.eq(Color(tp.bars[60]), Rgb(COLORS.bad))
  T.eq(Shown(tp.bars), 60)
  -- 144 fps: the scale grows to the next multiple of 30 (150)
  Feed(Graph, 1, function() return 144, nil, nil end)
  Graph.ShowFor(owner)                              -- refresh now (TICK came before the sample)
  T.eq(tp.bars[60]:GetHeight(), 38, "144 / 150 * 40")
  T.eq(tp.bars[59]:GetHeight(), 7, "25 / 150 * 40")
  T.eq(Color(tp.bars[1]), Rgb(COLORS.good))
end)

T.test("latency: a step line, held until the next reading, a riser where it changes", function()
  local ns = Start()
  local Graph, COLORS = ns.Graph, ns.C.COLORS
  -- 100 ms for 30 s, then 260 ms (the game refreshes it about every 30 s)
  Feed(Graph, 60, function(i) return 60, Every5(i, i <= 30 and 100 or 260) end)
  Graph.ShowFor(Owner())
  local tp = Graph.frame.tp
  T.eq(tp.colL[1], 100)
  T.eq(tp.colL[30], 100)
  T.eq(tp.colL[31], 260, "the reading at tick 31 starts the new step")
  T.eq(tp.colL[60], 260)
  T.eq(Shown(tp.segs), 60, "one segment per column")
  -- each step sits on an invisible stalk: moving it is a SetHeight, never a SetPoint
  local y1, y60 = tp.stalks[1]:GetHeight(), tp.stalks[60]:GetHeight()
  T.eq(y1, 9, "100 ms on a 300 ms scale: round(100 / 300 * 28) px")
  T.eq(y60, 24, "260 ms: round(260 / 300 * 28) px")
  T.eq(Shown(tp.riseL) + Shown(tp.riseR), 1, "a single riser")
  T.ok(tp.riseR[30]:IsShown(), "at the change, drawn by the lower column")
  T.eq(tp.riseR[30]:GetHeight(), y60 - y1 + 2)
  T.eq(Color(tp.segs[1]), Rgb(COLORS.good))
  T.eq(Color(tp.segs[60]), Rgb(COLORS.bad))
  -- no reading at all yet for the first columns of a fresh history
  Graph.Hide()
  ns.settings.graph.window = 300
  Graph.ShowFor(Owner())
  T.eq(tp.colL[1], -1, "no latency before the first reading")
  T.no(tp.segs[1]:IsShown())
end)

T.test("gaps: without samples (FPS token hidden) the columns stay empty", function()
  local ns = Start()
  local Graph = ns.Graph
  Feed(Graph, 20, function() return 60, nil, nil end)
  Stub.Advance(20)                                  -- nothing sampled for 20 s
  Feed(Graph, 20, function() return 60, nil, nil end)
  Graph.ShowFor(Owner())
  local tp = Graph.frame.tp
  local empty = 0
  for k = 1, 60 do
    if tp.colF[k] < 0 then empty = empty + 1 end
  end
  T.ok(empty >= 17 and empty <= 20, format("gap drawn as a gap (%d empty columns)", empty))
  T.eq(Shown(tp.bars), 60 - empty)
end)

---------------------------------------------------------------------------
-- Windows, texts, readout
---------------------------------------------------------------------------

T.test("30 s / 1 min / 5 min: title and the age of each column (en)", function()
  local ns = Start({ window = 30 })
  local Graph, L = ns.Graph, ns.L
  Feed(Graph, 40, function() return 60, Every5(1, 40) end)
  local owner = Owner()
  Graph.ShowFor(owner)
  local tp = Graph.frame.tp
  T.eq(tp.title:GetText(), format(L.GRAPH_TITLE_FMT, L.GRAPH_WINDOW_30))
  -- 30 s: two columns per sample, both filled
  T.eq(Shown(tp.bars), 60)
  local function Age(k)
    Stub.RunScript(tp.cols[k], "OnEnter")
    local text = tp.readout:GetText()
    Stub.RunScript(tp.cols[k], "OnLeave")
    return text
  end
  local fps, ms = ns.Fmt.FPS(60), ns.Fmt.Latency(40)
  rawset(Graph.frame, "_mouseOver", true)           -- moving between columns keeps it open
  T.eq(Age(60), format(L.GRAPH_AGO_FMT, format(L.GRAPH_AGE_S_FMT, 1), fps, ms))
  T.eq(Age(1), format(L.GRAPH_AGO_FMT, format(L.GRAPH_AGE_S_FMT, 30), fps, ms))
  ns.settings.graph.window = 300
  Stub.Advance(1)                                   -- the next refresh reads the setting
  T.eq(tp.title:GetText(), format(L.GRAPH_TITLE_FMT, L.GRAPH_WINDOW_300))
  T.eq(Age(1), format(L.GRAPH_AGO_FMT, format(L.GRAPH_AGE_MS_FMT, 5, 0), L.DOTS, L.DOTS),
    "no data 5 min ago")
  T.eq(Age(49), format(L.GRAPH_AGO_FMT, format(L.GRAPH_AGE_MS_FMT, 1, 0), L.DOTS, L.DOTS))
  T.eq(Age(60), format(L.GRAPH_AGO_FMT, format(L.GRAPH_AGE_S_FMT, 5), fps, ms))
  ns.settings.graph.window = 60
  Stub.Advance(1)
  T.eq(tp.title:GetText(), format(L.GRAPH_TITLE_FMT, L.GRAPH_WINDOW_60))
  ns.settings.graph.window = 45                     -- not a choice: 1 min
  Stub.Advance(1)
  T.eq(tp.title:GetText(), format(L.GRAPH_TITLE_FMT, L.GRAPH_WINDOW_60))
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("readout: 'il y a 24 s : 58 fps · 112 ms' on the hovered column, else the newest (frFR)", function()
  local ns = Start({ locale = "frFR" })
  local Graph, L, Fmt = ns.Graph, ns.L, ns.Fmt
  Feed(Graph, 60, function(i) return (i == 37) and 58 or 60, Every5(i, (i < 36) and 60 or 112) end)
  local owner = Owner()
  Graph.ShowFor(owner)
  local tp = Graph.frame.tp
  -- nothing hovered: the newest column
  T.eq(tp.readout:GetText(), format(L.GRAPH_AGO_FMT, "1 s", Fmt.FPS(60), Fmt.Latency(112)))
  T.no(tp.cursor:IsShown())
  -- column 37 = the sample of 24 s ago
  rawset(Graph.frame, "_mouseOver", true)
  Stub.RunScript(tp.cols[37], "OnEnter")
  local text = tp.readout:GetText()
  T.eq(text, format(L.GRAPH_AGO_FMT, "24 s", Fmt.FPS(58), Fmt.Latency(112)))
  local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  T.eq(plain, "il y a 24 s : 58 fps \194\183 112 ms")
  T.ok(tp.cursor:IsShown(), "cursor on the hovered column")
  -- the chart scrolls: the readout follows the column under the mouse
  Feed(Graph, 1, function() return 60, nil, nil end)
  T.eq(tp.readout:GetText(), format(L.GRAPH_AGO_FMT, "24 s", Fmt.FPS(60), Fmt.Latency(112)))
  Stub.RunScript(tp.cols[37], "OnLeave")
  T.no(tp.cursor:IsShown())
  T.eq(tp.readout:GetText(), format(L.GRAPH_AGO_FMT, "1 s", Fmt.FPS(60), Fmt.Latency(112)))
  T.ok(Graph.IsShown(), "still over the panel")
end)

T.test("min / avg / max per chart, dots and 'collecting' without data", function()
  local ns = Start()
  local Graph, L = ns.Graph, ns.L
  local owner = Owner()
  Graph.ShowFor(owner)
  local tp = Graph.frame.tp
  T.eq(tp.readout:GetText(), L.GRAPH_NO_DATA)
  T.eq(tp.fpsStats:GetText(), L.DOTS)
  T.eq(tp.latStats:GetText(), L.DOTS)
  T.eq(tp.note:GetText(), L.GRAPH_LAT_NOTE)
  Graph.Hide()
  local seq = { 50, 60, 70 }
  Feed(Graph, 60, function(i) return seq[(i - 1) % 3 + 1], Every5(i, (i <= 30) and 80 or 120) end)
  Graph.ShowFor(owner)
  T.eq(tp.fpsStats:GetText(), format(L.GRAPH_MIN_AVG_MAX_FMT, "50", "60", "70"))
  T.eq(tp.latStats:GetText(), format(L.GRAPH_MIN_AVG_MAX_FMT, "80", "100", "120"),
    "time-weighted: 30 s at 80, 30 s at 120")
end)

---------------------------------------------------------------------------
-- Visibility
---------------------------------------------------------------------------

T.test("hides when the mouse leaves both the text and the panel; refreshed only while shown", function()
  local ns = Start()
  local Graph = ns.Graph
  Feed(Graph, 30, function(i) return 30 + i, Every5(i, 50) end)
  local owner = Owner()
  Graph.ShowFor(owner)
  local panel = Graph.frame
  local tp = panel.tp
  -- leaving the text towards the panel keeps it
  rawset(panel, "_mouseOver", true)
  Graph.LeaveAnchor(owner)
  T.ok(Graph.IsShown(), "mouse over the panel")
  -- from a column back to the text: kept
  rawset(panel, "_mouseOver", false)
  rawset(owner, "_mouseOver", true)
  Stub.RunScript(tp.cols[10], "OnEnter")
  Stub.RunScript(tp.cols[10], "OnLeave")
  T.ok(Graph.IsShown(), "mouse back over the text")
  Stub.RunScript(panel, "OnLeave")
  T.ok(Graph.IsShown())
  -- out of both
  rawset(owner, "_mouseOver", false)
  Stub.RunScript(tp.cols[10], "OnLeave")
  T.no(Graph.IsShown(), "left both")
  T.no(panel:IsShown())
  -- the text alone, then away
  Graph.ShowFor(owner)
  Graph.LeaveAnchor(owner)
  T.no(Graph.IsShown())
  -- another region's Hide / LeaveAnchor leave it alone
  Graph.ShowFor(owner)
  local other = Owner(0)
  Graph.Hide(other)
  Graph.LeaveAnchor(other)
  T.ok(Graph.IsShown())
  Stub.RunScript(panel, "OnLeave")
  T.no(Graph.IsShown(), "panel left, text not hovered")
  -- refreshed by TICK only while shown
  Graph.ShowFor(owner)
  local n0 = rawget(tp.readout, "_setTextCount")
  Feed(Graph, 5, function(i) return 100 + i, nil, nil end)
  T.ok(rawget(tp.readout, "_setTextCount") >= n0 + 4, "one refresh per tick")
  Graph.Hide()
  local n1 = rawget(tp.readout, "_setTextCount")
  local h = tp.bars[60]:GetHeight()
  Feed(Graph, 10, function(i) return 20 + i, nil, nil end)
  T.eq(rawget(tp.readout, "_setTextCount"), n1, "hidden: no refresh")
  T.eq(tp.bars[60]:GetHeight(), h)
  -- hiding the panel from elsewhere (UIParent hidden) detaches it too
  Graph.ShowFor(owner)
  panel:Hide()
  T.no(Graph.IsShown())
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Allocation (requirement A)
---------------------------------------------------------------------------

-- Same measure as T.alloc, with one unmeasured call after the full collect (the
-- collect shrinks the Lua stack; its regrowth is not garbage).
-- As T.alloc: the collect shrinks the Lua stack (Lua 5.1 halves it), and a step deeper
-- than the warm call (the latency re-read every 5 ticks) would count its re-growth (not
-- garbage, and depending on how large earlier tests left the stack): it is grown first.
local function WarmStack(depth)
  if depth <= 0 then return 0 end
  local a, b, c, d, e, f, g, h = depth, depth, depth, depth, depth, depth, depth, depth
  return WarmStack(depth - 1) + a + b + c + d + e + f + g + h
end

local function Alloc(fn, n)
  collectgarbage("collect")
  WarmStack(200)
  fn(0)
  collectgarbage("stop")
  local before = collectgarbage("count")
  for i = 1, n do fn(i) end
  local after = collectgarbage("count")
  collectgarbage("restart")
  return after - before
end

T.test("allocation: sampling 600 ticks (panel hidden) allocates nothing", function()
  local ns = Start()
  local Graph = ns.Graph
  local t = 0
  local function Step()
    t = t + 1
    Stub.Advance(1)
    local h, w = Every5(t, 40 + t % 3)
    Graph.Sample(Stub.Now(), 55 + t % 9, h, w)
  end
  for _ = 1, 400 do Step() end                     -- rings created and wrapped
  local kb = Alloc(Step, 600)
  T.ok(kb < 0.1, format("allocated %.3f KB", kb))
end)

T.test("allocation: shown panel refreshed 600 ticks, steady values, hovered or not: nothing", function()
  local ns = Start({ window = 300 })
  local Graph = ns.Graph
  local t = 0
  local function Step()
    t = t + 1
    Stub.Advance(1)
    local h, w = Every5(t, 42)
    Graph.Sample(Stub.Now(), 60, h, w)
  end
  for _ = 1, 320 do Step() end
  local owner = Owner()
  Graph.ShowFor(owner)
  Gain()
  for _ = 1, 10 do Step() end
  local kb = Alloc(Step, 600)
  T.ok(kb < 0.1, format("shown: allocated %.3f KB", kb))
  rawset(Graph.frame, "_mouseOver", true)
  Stub.RunScript(Graph.frame.tp.cols[20], "OnEnter")
  Gain()
  for _ = 1, 10 do Step() end
  kb = Alloc(Step, 600)
  T.ok(kb < 0.1, format("hovered: allocated %.3f KB", kb))
end)

T.test("allocation: shown panel with values changing every tick stays small", function()
  local ns = Start({ window = 60 })
  local Graph = ns.Graph
  local t = 0
  local function Step()
    t = t + 1
    Stub.Advance(1)
    local h, w = Every5(t, 40 + math.floor(t / 30) % 3)
    Graph.Sample(Stub.Now(), 50 + t % 23, h, w)
  end
  for _ = 1, 320 do Step() end
  local owner = Owner()
  Graph.ShowFor(owner)
  Gain()
  for _ = 1, 60 do Step() end
  -- nothing is re-anchored while the history scrolls: bars and latency steps only
  -- change height (the stub allocates a table per SetPoint, the game does not)
  local mt = getmetatable(owner).__index
  local setPoint = rawget(mt, "SetPoint")
  local anchors = 0
  rawset(mt, "SetPoint", function(...) anchors = anchors + 1 return setPoint(...) end)
  local ok, kb = pcall(Alloc, Step, 600)
  rawset(mt, "SetPoint", setPoint)
  T.ok(ok, tostring(kb))
  T.eq(anchors, 0, "SetPoint calls while scrolling")
  -- only the texts whose values changed are set, from memoized strings (min / avg /
  -- max, readout): the 23 FPS values x 3 latencies of this history are all built within
  -- the first ticks, then nothing is allocated
  T.ok(kb / 600 < 0.02, format("allocated %.3f KB per tick", kb / 600))
  Gain()
  local again = Alloc(Step, 600)
  T.ok(again < 0.1, format("warm: allocated %.3f KB in 600 ticks", again))
end)

---------------------------------------------------------------------------
-- Themes (design/SPEC-themes.md 4.6)
---------------------------------------------------------------------------

local function TextRgb(fs)
  local r, g, b = fs:GetTextColor()
  return { r, g, b }
end

-- Every region of the panel as a string (type, layer, texture, colours, text, font,
-- justification, shadow, size, anchors, shown) plus the panel's backdrop and size:
-- the look, independent of the object identities of a load.
local function V(x)
  if type(x) == "number" then return format("%.4f", x) end
  return tostring(x)
end

local function Snapshot(root)
  local out = {}
  local function Under(o)
    for _ = 1, 50 do
      o = rawget(o, "_parent")
      if o == nil then return false end
      if o == root then return true end
    end
    return false
  end
  for _, o in ipairs(Stub.regions) do
    if Under(o) then
      local pts = {}
      for i, p in ipairs(o._points) do pts[i] = p.point .. ":" .. tostring(p.relPoint) .. ":" .. V(p.x) .. ":" .. V(p.y) end
      out[#out + 1] = table.concat({
        o._type, V(o._layer), V(o._subLayer), V(o._texture),
        V(o._vR), V(o._vG), V(o._vB), V(o._vA), V(o._text), V(o._font), V(o._fontSize), V(o._fontFlags),
        V(o._tR), V(o._tG), V(o._tB), V(o._tA), V(o._justifyH), V(o._shadowX), V(o._shadowY),
        V(o._sR), V(o._sG), V(o._sB), V(o._sA), V(o._width), V(o._height), V(o._shown),
        table.concat(pts, ","),
      }, "|")
    end
  end
  out[#out + 1] = table.concat({ V(root._bgR), V(root._bgG), V(root._bgB), V(root._bgA), V(root._bdR),
    V(root._bdG), V(root._bdB), V(root._bdA), V(root._width), V(root._height), V(root._strata) }, "|")
  return out
end

T.test("theme: futuriste colours and fonts on the panel; a theme switch re-applies them", function()
  Stub.theme = nil                                  -- the real default theme
  local ns = Start()
  local Graph, Themes, COLORS = ns.Graph, ns.Themes, ns.C.COLORS
  T.eq(Themes.ActiveKey(), "futuriste")
  Feed(Graph, 70, function(i) return (i <= 60) and 60 or 25, Every5(i, 42) end)
  Graph.ShowFor(Owner())
  local panel = Graph.frame
  local tp = panel.tp
  local ui = Themes.Active().ui
  T.eq({ panel._bgR, panel._bgG, panel._bgB, panel._bgA }, { ui.bg[1], ui.bg[2], ui.bg[3], 0.92 }, "backdrop")
  T.eq({ panel._bdR, panel._bdG, panel._bdB, panel._bdA }, { ui.border[1], ui.border[2], ui.border[3], 0.35 },
    "border")
  T.eq(TextRgb(tp.title), Rgb(ui.title), "title")
  T.eq(TextRgb(tp.fpsLabel), Rgb(ui.label), "FPS label")
  T.eq(TextRgb(tp.latLabel), Rgb(ui.label), "latency label")
  T.eq(TextRgb(tp.fpsStats), Rgb(ui.value), "FPS stats")
  T.eq(TextRgb(tp.latStats), Rgb(ui.value), "latency stats")
  T.eq(TextRgb(tp.readout), Rgb(ui.value), "readout")
  T.eq(TextRgb(tp.note), Rgb(ui.dim), "note")
  local cr, cg, cb, ca = tp.cursor:GetVertexColor()
  T.eq({ cr, cg, cb, ca }, { ui.value[1], ui.value[2], ui.value[3], 0.4 }, "cursor")
  -- fonts: the display role on the title, body elsewhere, today's sizes
  local function Font(fs) return { fs:GetFont() } end
  local function Want(role, size)
    local path, sz = Themes.Font(role, size)
    return { path, sz, "" }
  end
  T.eq(Font(tp.title), Want("display", 11))
  T.eq(Font(tp.fpsLabel), Want("body", 10))
  T.eq(Font(tp.readout), Want("body", 10))
  T.eq(Font(tp.note), Want("body", 9))
  T.ok(Font(tp.title)[1] ~= Font(tp.readout)[1], "display and body fonts differ in futuriste")
  -- the quality colours and the geometry stay
  T.eq(Color(tp.bars[1]), Rgb(COLORS.good))
  T.eq(Color(tp.bars[60]), Rgb(COLORS.bad))
  T.eq(panel:GetWidth(), 60 * 4 + 2 * 8)
  -- a switch while the panel exists: the classic look again
  ns.Core.SetSetting("theme", "actuel")
  local bg = COLORS.bg
  T.eq({ panel._bgR, panel._bgG, panel._bgB, panel._bgA }, { bg[1], bg[2], bg[3], 0.92 })
  T.eq(TextRgb(tp.title), Rgb(COLORS.value))
  T.eq(TextRgb(tp.note), Rgb(COLORS.dim))
  T.eq(Font(tp.title), { STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11, "" })
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("theme: under Classic the panel is exactly the pre-theme one (baseline copy)", function()
  local root = Stub.ROOT
  local f = io.open(root .. "tests/baseline/TruePlayed_Camelot.toc", "r")
  if not f then T.skip("no Phase 0 baseline") end
  f:close()
  local function Play()
    local ns = Start({ window = 60 })
    local Graph = ns.Graph
    Feed(Graph, 70, function(i) return 40 + i % 30, Every5(i, 60 + i) end)
    Graph.ShowFor(Owner())
    rawset(Graph.frame, "_mouseOver", true)
    Stub.RunScript(Graph.frame.tp.cols[30], "OnEnter")
    Stub.Advance(1)
    return Snapshot(Graph.frame)
  end
  Stub.ROOT = root .. "tests/baseline/"
  local ok, before = pcall(Play)
  Stub.ROOT = root
  T.ok(ok, tostring(before))
  Stub.Reset()
  local after = Play()
  T.ok(#after > 300, "regions: " .. #after)
  T.eq(after, before)
end)
