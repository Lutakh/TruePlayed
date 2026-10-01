-- tests/test_bar_theme.lua - the themed bar (design/SPEC-themes.md 2.4, 2.5, 3.4, 8.4):
-- every theme builds with all its layer handles and stays allocation-free on steady ticks,
-- regions are pooled across theme switches, the futuriste geometry, colours, split texts
-- and panel, the classic look after a switch at run time, lazy gradients.
-- The stub measures 6 px per character (colour codes left out).
local Stub, T = ...

local format = string.format
local floor = math.floor

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Loads the addon with the widget shown. opts.theme: the default theme (nil = the real
-- default, futuriste); opts.xp / opts.rest / opts.level: the player at login.
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false })
  Stub.theme = opts.theme
  if opts.level then Stub.player.level = opts.level end
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

local function SetRest(amount)
  Stub.player.rest = amount
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
end

local function Rgb(r, g, b)
  return { floor(r * 1000 + 0.5), floor(g * 1000 + 0.5), floor(b * 1000 + 0.5) }
end

local function Hex(h)
  return Rgb(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
end

local function Vertex(t)
  local r, g, b, a = t:GetVertexColor()
  return Rgb(r, g, b), a
end

local function SetTextCount(fs)
  local n = fs and rawget(fs, "_setTextCount")
  return type(n) == "number" and n or 0
end

local function Copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function IsTexture(t)
  return type(t) == "table" and t.GetObjectType ~= nil and t:GetObjectType() == "Texture"
end

local function SortedKeys(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = k end
  table.sort(out)
  return out
end

-- Every layer of the theme kept by `style` has its handles in tp.tex (caps / three:
-- id .. "L" / "M" / "R"; nine: 9 textures; ticks: N - 1), and nothing else is there
-- but the veil.
local function CheckHandles(ns, tp, style)
  local th = ns.Themes.Active()
  local want = { veil = true }
  for _, Lc in ipairs(th.bar.layers) do
    if Lc.when == nil or Lc.when == style then
      local id, kind = Lc.id, Lc.kind
      if kind == "caps" or kind == "three" then
        for _, s in ipairs({ "L", "M", "R" }) do
          T.ok(IsTexture(tp.tex[id .. s]), th.key .. ": tex." .. id .. s)
          want[id .. s] = true
        end
      elseif kind == "nine" or kind == "ticks" then
        local list = tp.tex[id]
        T.eq(type(list), "table", th.key .. ": tex." .. id)
        local nTicks = Lc.ticks and (Lc.ticks.mid and Lc.ticks.n or Lc.ticks.n - 1)
        T.eq(#list, kind == "nine" and 9 or nTicks, th.key .. ": tex." .. id .. " count")
        for i = 1, #list do T.ok(IsTexture(list[i]), th.key .. ": tex." .. id .. "[" .. i .. "]") end
        want[id] = true
      else
        T.ok(IsTexture(tp.tex[id]), th.key .. ": tex." .. id)
        want[id] = true
      end
    end
  end
  for k in pairs(tp.tex) do T.ok(want[k], th.key .. ": no stale handle tex." .. tostring(k)) end
  T.ok(IsTexture(tp.tex.veil), "veil kept")
end

-- Frame size of the bar style (SPEC-themes 2.4), from the compiled theme and the font
-- sizes after snapping.
local function BarFrameSize(ns, width, height, fontSize)
  local Themes = ns.Themes
  local th = Themes.Active()
  local text = th.text
  local function Sz(e)
    local _, s = Themes.Font(text.font[e], fontSize + text.size[e])
    return s
  end
  local bar = th.bar
  local H = math.max(bar.hMin, height + bar.hAdd)
  local topRow = math.max(Sz("s1"), Sz("s3")) + 2
  local bottom = math.max(Sz("level"), Sz("xp"), Sz("s2"))
  if text.split then bottom = math.max(bottom, Sz("levelValue"), Sz("xpLabel")) end
  local bottomRow = bottom + 2
  return width + 2 * bar.pad, bar.pad + topRow + bar.gap + H + bar.gap + bottomRow + bar.pad, H
end

-- SetText counts of the bar texts (slots, level, XP, and the split texts when present).
local function TextCounts(tp)
  return { SetTextCount(tp.slots[1]), SetTextCount(tp.slots[2]), SetTextCount(tp.slots[3]),
           SetTextCount(tp.bl), SetTextCount(tp.brx), SetTextCount(tp.blv), SetTextCount(tp.xpl) }
end

-- Every part of tp.panel (a texture or a 9-slice list).
local function EachPart(panel, fn)
  for id, p in pairs(panel) do
    if IsTexture(p) then
      fn(id, p)
    else
      for i = 1, #p do fn(id, p[i]) end
    end
  end
end

local function PartColor(th, id)
  for _, P in ipairs(th.bar.panel.parts) do
    if P.id == id then return P.c[1] end
  end
end

-- Sorted description of what is drawn under the widget: every shown, non-transparent
-- region whose parents are shown (meters, alpha 0, are left out; mask textures draw
-- nothing themselves: a masked texture says "mask"), with its geometry, texture, colour
-- (the last colour call wins, as in the game) and text.
local function R4(x)
  if type(x) ~= "number" then return tostring(x) end
  return format("%.4f", x)
end

local function Drawn(widget)
  local out = {}
  local wl, wb = widget:GetLeft(), widget:GetBottom()
  for _, o in ipairs(Stub.regions) do
    local p, inside = o, false
    while p do
      if p == widget then inside = true break end
      p = rawget(p, "_parent")
    end
    local typ = rawget(o, "_type")
    if inside and o ~= widget and typ ~= "MaskTexture" and o:IsVisible() and (rawget(o, "_alpha") or 1) > 0 then
      local l, b, w, h = o:GetRect()
      local parts = { typ, tostring(rawget(o, "_layer")), tostring(rawget(o, "_subLayer") or 0),
                      R4(l and l - wl), R4(b and b - wb), R4(w), R4(h) }
      if typ == "Texture" then
        local tc = rawget(o, "_tc")
        local tcs = tc and table.concat({ R4(tc[1]), R4(tc[2]), R4(tc[3]), R4(tc[4]) }, ",") or "0.0000,1.0000,0.0000,1.0000"
        parts[#parts + 1] = tostring(rawget(o, "_texture"))
        parts[#parts + 1] = tcs
        parts[#parts + 1] = tostring(rawget(o, "_blend") or "BLEND")
        parts[#parts + 1] = rawget(o, "_mask") and "mask" or "-"
        local vs, gs, gas = rawget(o, "_vSeq") or 0, rawget(o, "_gSeq") or 0, rawget(o, "_gaSeq") or 0
        if gs > vs and gs > gas then
          local g = rawget(o, "_grad")
          parts[#parts + 1] = "grad " .. g[1] .. " " .. R4(g[2]) .. " " .. R4(g[3]) .. " " .. R4(g[4]) .. " "
            .. R4(g[5]) .. " " .. R4(g[6]) .. " " .. R4(g[7]) .. " " .. R4(g[8]) .. " " .. R4(g[9])
        else
          parts[#parts + 1] = "v " .. R4(rawget(o, "_vR")) .. " " .. R4(rawget(o, "_vG")) .. " "
            .. R4(rawget(o, "_vB")) .. " " .. R4(rawget(o, "_vA"))
        end
      elseif typ == "FontString" then
        parts[#parts + 1] = tostring(rawget(o, "_text"))
        parts[#parts + 1] = tostring(rawget(o, "_font")) .. " " .. tostring(rawget(o, "_fontSize")) .. " "
          .. tostring(rawget(o, "_fontFlags"))
        parts[#parts + 1] = R4(rawget(o, "_tR")) .. " " .. R4(rawget(o, "_tG")) .. " " .. R4(rawget(o, "_tB"))
          .. " " .. R4(rawget(o, "_tA"))
        parts[#parts + 1] = tostring(rawget(o, "_justifyH"))
        parts[#parts + 1] = tostring(rawget(o, "_shadowX")) .. " " .. tostring(rawget(o, "_shadowY")) .. " "
          .. R4(rawget(o, "_sA"))
      end
      out[#out + 1] = table.concat(parts, " | ")
    end
  end
  table.sort(out)
  local w, h = widget:GetSize()
  out[#out + 1] = "size " .. R4(w) .. " " .. R4(h)
  if widget:GetBackdrop() then           -- colours left by a former backdrop draw nothing
    out[#out + 1] = "backdrop " .. R4(rawget(widget, "_bgR")) .. " " .. R4(rawget(widget, "_bgA")) .. " "
      .. R4(rawget(widget, "_bdR")) .. " " .. R4(rawget(widget, "_bdA"))
  end
  return out
end

-- T.eq on two Drawn() lists, reporting the first lines that differ.
local function SameDrawing(a, b, msg)
  local onlyA, onlyB, inB, inA = {}, {}, {}, {}
  for i = 1, #b do inB[b[i]] = (inB[b[i]] or 0) + 1 end
  for i = 1, #a do inA[a[i]] = (inA[a[i]] or 0) + 1 end
  for i = 1, #a do
    if (inB[a[i]] or 0) < (inA[a[i]] or 0) then onlyA[#onlyA + 1] = a[i] end
  end
  for i = 1, #b do
    if (inA[b[i]] or 0) < (inB[b[i]] or 0) then onlyB[#onlyB + 1] = b[i] end
  end
  if #onlyA > 0 or #onlyB > 0 then
    T.eq({ got = onlyA[1], want = onlyB[1] }, {}, msg .. format(" (%d / %d lines differ)", #onlyA, #onlyB))
  end
  T.eq(#a, #b, msg)
end

---------------------------------------------------------------------------
-- Every theme (8.4)
---------------------------------------------------------------------------

for _, key in ipairs(KEYS) do
  T.test("theme " .. key .. ": builds, every layer handle, 2.4 frame size, quiet allocation-free steady ticks", function()
    local ns, f, tp = Start({ theme = key, xp = 2000, rest = 3000 })
    T.eq(ns.Themes.ActiveKey(), key, "theme active")
    CheckHandles(ns, tp, "bar")
    local w, h = BarFrameSize(ns, 360, 8, 11)
    T.eq({ f:GetSize() }, { w, h }, "frame size (2.4)")
    T.ok(tp.tex.veil:IsShown(), "unlocked: veil")

    -- steady: no SetText on the bar texts, no SetFont, nothing allocated
    Stub.Advance(300)
    local c0, fonts = TextCounts(tp), Stub.calls.SetFont
    Stub.Advance(60)
    T.eq(TextCounts(tp), c0, "no SetText over 60 steady ticks")
    T.eq(Stub.calls.SetFont, fonts, "no SetFont over 60 steady ticks")
    local kb = T.alloc(function() Stub.Advance(1) end, 600)
    T.ok(kb <= 2, format("%s: %.2f KB over 600 ticks", key, kb))

    -- box style: the layers without `when = "bar"` only
    Set(ns, "widget.style", "box")
    CheckHandles(ns, tp, "box")
    T.no(tp.bl:IsShown())
    T.ok(tp.blv == nil or not tp.blv:IsShown(), "no level value in the box")
    T.ok(tp.xpl == nil or not tp.xpl:IsShown(), "no XP label in the box")
    Set(ns, "widget.style", "bar")
    CheckHandles(ns, tp, "bar")
    T.eq(#Stub.errors, 0)
    T.eq(Stub.onUpdateCount, 0)
  end)
end

---------------------------------------------------------------------------
-- Region pools (B1, P4)
---------------------------------------------------------------------------

T.test("pools: after one cycle through the 13 themes (bar and box), another cycle creates no region", function()
  local ns = Start({ theme = "actuel", xp = 2000, rest = 3000 })
  Set(ns, "widget.bgAlpha", 0.5)             -- panel parts drawn too
  Set(ns, "widget.pctPos", "level")          -- split level values too
  local function Cycle()
    for _, key in ipairs(KEYS) do Set(ns, "theme", key) end
    Set(ns, "widget.style", "box")
    for _, key in ipairs(KEYS) do Set(ns, "theme", key) end
    Set(ns, "widget.style", "bar")
  end
  Cycle()
  local before = Copy(Stub.created)
  Cycle()
  T.eq(Stub.created, before, "second cycle: no region created")
  T.eq(#Stub.errors, 0)
end)

---------------------------------------------------------------------------
-- Futuriste (the default theme)
---------------------------------------------------------------------------

T.test("futuriste: default theme, 14 px track, 2.4 frame size, ticks, clipped segments, end-of-fill marker", function()
  local ns, f, tp = Start({ xp = 2000 })
  T.eq(ns.Themes.ActiveKey(), "futuriste", "the default theme")
  local th = ns.Themes.Active()
  local W, H = 360, 14
  local fw, fh, h = BarFrameSize(ns, W, 8, 11)
  T.eq(h, H, "track height: widget.height 8 + 6")
  T.eq(tp.tex.track:GetHeight(), H)
  T.eq({ f:GetSize() }, { fw, fh })
  local ox = th.bar.pad
  local _, _, _, tx = tp.tex.track:GetPoint(1)
  T.eq(tx, ox, "track at the padding")

  local ticks = tp.tex.ticks
  T.eq(#ticks, 9)
  for i = 1, 9 do
    local _, _, _, x = ticks[i]:GetPoint(1)
    T.eq(x, ox + floor(W * i / 10 + 0.5), "tick " .. i)
    T.ok(ticks[i]:IsShown())
  end
  local px = floor(W * 2000 / 7600 + 0.5)
  local segs = tp.tex.fillSegs
  local shown = 0
  for i = 1, 9 do
    local x = floor(W * i / 10 + 0.5)
    T.eq(segs[i]:IsShown(), x < px, "segment " .. i)
    if segs[i]:IsShown() then shown = shown + 1 end
  end
  T.eq(shown, 2, "segments left of the fill end only")
  local _, _, _, mx = tp.tex.marker:GetPoint(1)
  T.eq(mx, ox + px - 1, "marker centred on the fill end")
  T.eq(tp.tex.marker:GetWidth(), 2)
  T.ok(tp.tex.marker:IsShown())

  -- XP gained: dynamic layers follow, segments flip
  Stub.GrantXP(1800)                            -- 3800 / 7600: half the bar
  Stub.Advance(1)
  px = floor(W * 3800 / 7600 + 0.5)
  _, _, _, mx = tp.tex.marker:GetPoint(1)
  T.eq(mx, ox + px - 1)
  T.eq(tp.tex.fill:GetWidth(), px)
  for i = 1, 9 do T.eq(segs[i]:IsShown(), floor(W * i / 10 + 0.5) < px, "segment " .. i .. " after XP") end
  T.eq(#Stub.errors, 0)
end)

T.test("futuriste colours: magenta fill, cyan while rested, a custom XP colour without relayout", function()
  local ns, f, tp = Start({ xp = 2000 })
  local fill = tp.tex.fill
  T.eq((Vertex(fill)), Hex("ff2bd6"), "magenta")
  SetRest(3000)
  T.eq((Vertex(fill)), Hex("22d3ee"), "cyan while rested")
  T.ok(tp.tex.rested:IsShown())
  SetRest(0)
  T.eq((Vertex(fill)), Hex("ff2bd6"))

  local size = { f:GetSize() }
  local created, fonts = Copy(Stub.created), Stub.calls.SetFont
  local points = 0
  local setPoint = fill.SetPoint
  rawset(fill, "SetPoint", function(self, ...)
    points = points + 1
    return setPoint(self, ...)
  end)
  Set(ns, "widget.xpColor", { 0, 1, 0 })
  T.eq((Vertex(fill)), Rgb(0, 1, 0), "green fill")
  T.eq({ f:GetSize() }, size, "no relayout")
  T.eq(Stub.created, created, "no new region")
  T.eq(Stub.calls.SetFont, fonts, "no font set")
  T.eq(points, 0, "fill not moved")
  -- steady ticks: the fill is not touched
  Stub.Advance(30)
  T.eq(points, 0, "no SetPoint on steady ticks")
  Set(ns, "widget.xpColor", false)
  T.eq((Vertex(fill)), Hex("ff2bd6"), "the theme's colour again")
  T.eq(#Stub.errors, 0)
end)

T.test("futuriste at max level: full fill at 0.35 alpha, no rested part, no end-of-fill marker", function()
  Stub.player.xp, Stub.player.max, Stub.player.rest = 0, 0, 5000
  local ns, _, tp = Start({ level = 60 })
  T.ok(ns.Tracker.IsMax())
  local rgb, a = Vertex(tp.tex.fill)
  T.eq(rgb, Hex("ff2bd6"))
  T.near(a, 0.35, 1e-6, "dimmed")
  T.eq(tp.tex.fill:GetWidth(), 360)
  T.no(tp.tex.rested:IsShown())
  T.no(tp.tex.marker:IsShown())
  for i = 1, 9 do T.ok(tp.tex.fillSegs[i]:IsShown(), "every segment under a full fill") end
end)

T.test("futuriste split texts: level label + value, XP label + XP value, cap tag", function()
  local ns, f, tp = Start({ xp = 2000 })
  local L, Fmt, Tokens = ns.L, ns.Fmt, ns.Tokens
  Set(ns, "widget.width", 600)
  T.eq(tp.bl:GetText(), format(L.LEVEL_SHORT_FMT, 10))
  T.ok(tp.xpl ~= nil and tp.blv ~= nil, "split texts created")
  T.eq(tp.xpl:GetText(), L.XP_LABEL)
  T.eq(tp.brx:GetText(), format(L.XP_BARE_FMT, Fmt.Number(2000), Fmt.Number(7600)))
  T.ok(tp.xpl:IsShown() and tp.brx:IsShown())
  T.no(tp.blv:IsShown(), "no level value while the percent follows the bar")
  -- the XP label ends splitGap px left of the XP value
  local gap = ns.Themes.Active().text.splitGap
  local _, _, _, bx = tp.brx:GetPoint(1)
  local _, _, _, lx = tp.xpl:GetPoint(1)
  T.eq(lx, floor(bx - tp.brx:GetStringWidth() - gap + 0.5))

  -- percent next to the level: the level value
  Set(ns, "widget.pctPos", "level")
  local pct = Tokens.PercentText(Tokens.PercentTenths(2000, 7600))
  T.ok(tp.blv:IsShown())
  T.eq(tp.blv:GetText(), pct)
  T.eq(tp.bl:GetText(), format(L.LEVEL_SHORT_FMT, 10), "label alone")
  local _, _, _, vx = tp.blv:GetPoint(1)
  T.eq(vx, floor(f.tp.bl:GetStringWidth() + ns.Themes.Active().bar.pad + gap + 0.5), "value after the label")

  -- narrow bar: the XP label goes before the numbers do
  Set(ns, "widget.width", 150)
  if tp.brx:IsShown() and not tp.xpl:IsShown() then
    T.eq(tp.brx:GetText(), format(L.XP_BARE_FMT, ns.Bar.Compact(2000), ns.Bar.Compact(7600)))
  end
  Set(ns, "widget.width", 600)

  -- detected server level cap: the cap tag as level value
  local state = { capped = true }
  local Tracker = ns.Tracker
  local isMax = Tracker.IsMax
  Tracker.IsMax = function() return state.capped or isMax() end
  Tracker.GetCapInfo = function()
    if state.capped then return ns.char.level, true, 3 end
    return nil, false, 0
  end
  Stub.Advance(1)
  T.eq(tp.bl:GetText(), format(L.LEVEL_SHORT_FMT, 10))
  T.eq(tp.blv:GetText(), L.LEVEL_CAP_TAG)
  T.no(tp.xpl:IsShown(), "no XP text at the cap")
  T.no(tp.brx:IsShown())
  -- steady at the cap: the level texts are not set again
  local c0 = { SetTextCount(tp.bl), SetTextCount(tp.blv), SetTextCount(tp.xpl), SetTextCount(tp.brx) }
  Stub.Advance(30)
  T.eq({ SetTextCount(tp.bl), SetTextCount(tp.blv), SetTextCount(tp.xpl), SetTextCount(tp.brx) }, c0)
  T.eq(#Stub.errors, 0)
end)

T.test("futuriste panel: hidden at bgAlpha 0, parts at bgAlpha (bg) and twice it (line)", function()
  local ns, f, tp = Start()
  local th = ns.Themes.Active()
  local panel = tp.panel
  T.ok(type(panel.panelFill) == "table" and #panel.panelFill == 9, "nine-slice fill")
  T.ok(type(panel.panelLine) == "table" and #panel.panelLine == 9, "nine-slice line")
  EachPart(panel, function(id, t) T.no(t:IsShown(), id .. " hidden at 0") end)
  T.eq(f:GetBackdrop(), nil)

  Set(ns, "widget.bgAlpha", 0.5)
  T.eq(f:GetBackdrop(), nil, "parts, not the tooltip backdrop")
  local fillA, lineA = PartColor(th, "panelFill")[4], PartColor(th, "panelLine")[4]
  for i = 1, 9 do
    local _, _, _, a = panel.panelFill[i]:GetVertexColor()
    T.near(a, 0.5 * fillA, 1e-6, "panelFill alpha")
    T.ok(panel.panelFill[i]:IsShown())
    _, _, _, a = panel.panelLine[i]:GetVertexColor()
    T.near(a, 1 * lineA, 1e-6, "panelLine alpha")
  end
  -- the fill covers the frame
  local l, b, w, h = panel.panelFill[1]:GetRect()
  T.ok(l ~= nil and w > 0 and h > 0)
  T.eq(f:GetLeft(), l, "top-left corner at the frame's left edge")
  local _, _, fw, fh = f:GetRect()
  local _, b9, w9 = panel.panelFill[9]:GetRect()
  T.eq(b9, f:GetBottom(), "bottom-right corner at the bottom")
  T.eq(l + fw, select(1, panel.panelFill[9]:GetRect()) + w9, "and the right edge")
  T.ok(fh > 0)

  Set(ns, "widget.bgAlpha", 0.25)
  local _, _, _, a = panel.panelLine[1]:GetVertexColor()
  T.near(a, 0.5 * lineA, 1e-6, "line: twice the background alpha")
  Set(ns, "widget.bgAlpha", 0)
  EachPart(panel, function(id, t) T.no(t:IsShown(), id .. " hidden again") end)
  T.eq(#Stub.errors, 0)
end)

T.test("futuriste rested gradients: applied when first shown, not again while unchanged, again after a colour change", function()
  local ns, _, tp = Start({ xp = 2000 })
  local rested = tp.tex.rested
  T.no(rested:IsShown())
  local grads = 0
  rawset(rested, "SetGradient", function() grads = grads + 1 end)
  SetRest(3000)
  T.ok(rested:IsShown())
  T.eq(grads, 1, "first show")
  Stub.Advance(30)
  T.eq(grads, 1, "steady")
  SetRest(0)
  SetRest(800)
  T.eq(grads, 1, "shown again, same colours: kept")
  Set(ns, "widget.restedColor", { 1, 0, 0 })
  T.eq(grads, 2, "recoloured while shown")
  SetRest(0)
  Set(ns, "widget.restedColor", false)
  T.eq(grads, 2, "hidden: waits")
  SetRest(500)
  T.eq(grads, 3, "applied when shown")
  T.eq(#Stub.errors, 0)
end)

---------------------------------------------------------------------------
-- Theme switches at run time
---------------------------------------------------------------------------

T.test("switch to the classic theme at run time: classic handles, backdrop, texts and the same drawing as at login", function()
  local ns, f, tp = Start({ xp = 2000, rest = 3000 })
  Set(ns, "widget.bgAlpha", 0.5)
  Set(ns, "widget.pctPos", "level")
  Set(ns, "theme", "actuel")
  T.eq(ns.Themes.ActiveKey(), "actuel")
  T.eq(SortedKeys(tp.tex), { "fillHi", "fillL", "fillM", "fillR", "restTick", "rested", "trackL", "trackM",
                             "trackR", "veil" }, "the classic handles")
  T.eq(next(tp.panel), nil, "no panel part")
  T.ok(f:GetBackdrop() ~= nil, "the classic backdrop")
  T.no(tp.blv:IsShown())
  T.no(tp.xpl:IsShown())
  local L, Tokens = ns.L, ns.Tokens
  T.eq(tp.bl:GetText(), format(L.LEVEL_PCT_FMT, 10, Tokens.PercentText(Tokens.PercentTenths(2000, 7600))))
  T.eq({ f:GetSize() }, { 376, 58 }, "classic frame size")
  T.eq((Vertex(tp.tex.fillM)), Rgb(0.0, 0.39, 0.88), "the game's rested blue")
  local switched = Drawn(f)

  -- the same settings, classic theme from the start
  Stub.Reset()
  local ns2, f2 = Start({ theme = "actuel", xp = 2000, rest = 3000 })
  Set(ns2, "widget.bgAlpha", 0.5)
  Set(ns2, "widget.pctPos", "level")
  SameDrawing(switched, Drawn(f2), "switched at run time = classic at login")
end)

T.test("switch back and forth: the futuriste drawing is the same as at login, box style too", function()
  local ns, f = Start({ xp = 2000, rest = 3000 })
  Set(ns, "widget.bgAlpha", 0.5)
  local first = Drawn(f)
  Set(ns, "theme", "actuel")
  Set(ns, "widget.style", "box")
  Set(ns, "theme", "futuriste")
  local box = Drawn(f)
  Set(ns, "widget.style", "bar")
  SameDrawing(Drawn(f), first, "futuriste after actuel and the box")
  Stub.Reset()
  local ns2, f2 = Start({ xp = 2000, rest = 3000 })
  Set(ns2, "widget.bgAlpha", 0.5)
  Set(ns2, "widget.style", "box")
  SameDrawing(box, Drawn(f2), "box style after switches = box style at login")
end)

T.test("THEME_CHANGED: the widget follows the theme; the theme setting itself is left to Themes (S8)", function()
  local ns, f, tp = Start({ theme = "actuel", xp = 2000 })
  local Bar = ns.Bar
  local refresh, layout, refreshes, layouts = Bar.Refresh, Bar.ApplyLayout, 0, 0
  Bar.Refresh = function(...)
    refreshes = refreshes + 1
    return refresh(...)
  end
  Bar.ApplyLayout = function(...)
    layouts = layouts + 1
    return layout(...)
  end
  -- a SETTINGS_CHANGED "theme" whose resolved theme does not change: no work at all
  ns.SendMessage("SETTINGS_CHANGED", "theme", "actuel")
  T.eq(refreshes + layouts, 0, "ignored")
  -- a colour path: Themes recolours (THEME_CHANGED "colors"), no layout
  local size, fonts = { f:GetSize() }, Stub.calls.SetFont
  ns.Core.SetSetting("widget.xpColor", { 0, 1, 0 })
  T.eq(layouts, 0, "colour paths: no layout")
  T.eq(Stub.calls.SetFont, fonts)
  T.eq({ f:GetSize() }, size)
  T.eq((Vertex(tp.tex.fillM)), Rgb(0, 1, 0))
  Bar.Refresh, Bar.ApplyLayout = refresh, layout
  ns.Core.SetSetting("theme", "futuriste")
  T.eq(ns.Themes.ActiveKey(), "futuriste")
  T.ok(tp.tex.fill ~= nil and tp.tex.fillM == nil, "rebuilt at once")
  local fw, fh = BarFrameSize(ns, 360, 8, 11)
  T.eq({ f:GetSize() }, { fw, fh })
  T.eq(#Stub.errors, 0)
end)

T.test("levelFmt title: one level text with the percent or the cap tag, label + value when split", function()
  local ns, f, tp = Start({ theme = "actuel", xp = 2000 })
  local L, Tokens = ns.L, ns.Tokens
  local th = ns.Themes.Active()
  th.text.levelFmt = "title"                     -- test-only change of the compiled theme
  Set(ns, "widget.style", "box")                 -- a style change rebuilds the skin
  Set(ns, "widget.style", "bar")
  Set(ns, "widget.width", 600)
  T.eq(tp.bl:GetText(), format(L.LEVEL_TITLE_FMT, 10))
  Set(ns, "widget.pctPos", "level")
  local pct = Tokens.PercentText(Tokens.PercentTenths(2000, 7600))
  T.eq(tp.bl:GetText(), format(L.LEVEL_TITLE_FMT, 10) .. L.SEP .. pct)
  -- split + title
  Set(ns, "theme", "futuriste")
  th = ns.Themes.Active()
  th.text.levelFmt = "title"
  Set(ns, "widget.style", "box")
  Set(ns, "widget.style", "bar")
  T.eq(tp.bl:GetText(), format(L.LEVEL_TITLE_FMT, 10))
  T.eq(tp.blv:GetText(), pct)
  T.eq(#Stub.errors, 0)
  T.ok(f ~= nil)
end)
