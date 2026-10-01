-- tests/test_theme_integration.lua - the themes across modules (design/SPEC-themes.md,
-- phase 2): every setting value switched at run time with the bar, the tooltip (short
-- and Shift), the graph and the window; the insets of the bar panel; one gradient ramp
-- across sliced pieces (bar panel and tooltip); the half-texel cuts of a stretched
-- slice; the user's own configuration (big font, wide and thick bar, French, a level-20
-- druid at a server level cap) under the default, "class" and Classic themes; the
-- rebuild equivalence of a theme switch with a fresh load.
-- The stub measures 6 px per character (colour codes left out).
local Stub, T = ...

local format = string.format

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Start(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false })
  Stub.theme = nil                                -- the shipped default (futuriste)
  local p = Stub.player
  p.class = opts.class or "DRUID"
  if opts.level then p.level = opts.level end
  if opts.xp then p.xp = opts.xp end
  if opts.max then p.max = opts.max end
  p.rest = opts.rest or 0
  if opts.locale then Stub.locale = opts.locale end
  _G.TruePlayedDB = opts.db
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, ns.Bar.frame
end

local function Set(ns, path, value)
  ns.Core.SetSetting(path, value)
  Stub.Advance(1)
end

-- Adds every texture of a handle (a texture or a list of textures) to `set`.
local function AddHandle(set, h)
  if type(h) ~= "table" then return end
  if h.GetObjectType then
    set[h] = true
  else
    for _, t in ipairs(h) do set[t] = true end
  end
end

-- Visible textures drawn directly on the widget that no current handle owns (a region
-- left over from a previous theme or style). Pause marks and hover regions are child
-- frames, not counted.
local function StaleTextures(frame)
  local tp = frame.tp
  local known = {}
  for _, h in pairs(tp.tex) do AddHandle(known, h) end
  for _, h in pairs(tp.panel) do AddHandle(known, h) end
  local out = {}
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_type") == "Texture" and rawget(o, "_parent") == frame and o:IsVisible()
        and not known[o] then
      out[#out + 1] = tostring(rawget(o, "_texture"))
    end
  end
  return out
end

local function ShownRows(tf)
  local n = 0
  for i = 1, tf.tp.n do
    if tf.tp.rows[i].left:IsShown() then n = n + 1 end
  end
  return n
end

-- Left / right x of a bar FontString from its BOTTOMLEFT / BOTTOMRIGHT anchor on the
-- widget's BOTTOMLEFT, with the stub width (6 px per character).
local function Span(fs)
  local point, _, _, x = fs:GetPoint(1)
  local w = fs:GetStringWidth()
  local bound = rawget(fs, "_width") or 0
  if bound > 0 and w > bound then w = bound end
  if point == "BOTTOMRIGHT" then return x - w, x end
  if point == "BOTTOM" then return x - w / 2, x + w / 2 end
  return x, x + w
end

local function Rgba(c)
  return { c.r or c[1], c.g or c[2], c.b or c[3], c.a or c[4] }
end

local function Near4(a, b, msg)
  for i = 1, 4 do T.near(a[i], b[i], 1e-6, msg .. " [" .. i .. "]") end
end

-- From and to colours of a texture's last SetGradient.
local function Grad(t)
  local g = rawget(t, "_grad")
  return { g[2], g[3], g[4], g[5] }, { g[6], g[7], g[8], g[9] }
end

---------------------------------------------------------------------------
-- Every setting value at run time
---------------------------------------------------------------------------

T.test("every setting value at run time: bar, tooltip short / Shift, graph, window", function()
  local ns, frame = Start({ rest = 3000 })
  local Themes, C = ns.Themes, ns.C
  T.eq(Themes.ActiveKey(), "futuriste", "shipped default")
  for _, value in ipairs(C.THEME_CHOICES) do
    Set(ns, "theme", value)
    local key = (value == "class") and "druid" or value
    T.eq(Themes.ActiveKey(), key, value .. ": active theme")
    local th = Themes.Active()
    T.eq(StaleTextures(frame), {}, key .. ": no stale texture")
    for i = 1, 3 do
      local s = frame.tp.slots[i]
      T.ok(s:IsShown() and (s:GetText() or "") ~= "", format("%s: slot %d drawn", key, i))
    end
    T.ok(frame.tp.bl:IsShown() and frame.tp.bl:GetText() ~= "", key .. ": level text")
    -- tooltip: GameTooltip for the native theme, the private frame for the others
    Stub.RunScript(frame, "OnEnter")
    Stub.Advance(1)
    local tf = ns.TooltipFrame.frame
    local short
    if th.native then
      T.ok(GameTooltip:IsShown(), key .. ": GameTooltip shown")
      T.ok(not (tf and tf:IsShown()), key .. ": private frame hidden")
      short = #GameTooltip._lines
    else
      T.ok(tf and tf:IsShown(), key .. ": private frame shown")
      T.ok(not GameTooltip:IsShown() or GameTooltip:GetOwner() ~= frame, key .. ": GameTooltip not used")
      T.ok(tf.tp.nSeps >= 2, key .. ": header and footer separators")
      short = ShownRows(tf)
    end
    T.ok(short > 5, key .. ": short tooltip rows " .. short)
    local function SepHalves(view)
      if th.native then return end
      for i = 1, tf.tp.nSeps do
        local sp = tf.tp.seps[i]
        local cfg = th.tt.sep[sp.kind]
        T.eq(sp.a:IsShown(), cfg ~= nil, format("%s %s: separator %d (%s) drawn", key, view, i, sp.kind))
        T.eq(sp.b:IsShown(), cfg ~= nil and (cfg.mirror == true or cfg.center ~= nil),
          format("%s %s: separator %d (%s) right half only when mirrored or centred", key, view, i, sp.kind))
        T.eq(sp.c ~= nil and sp.c:IsShown(), cfg ~= nil and cfg.center ~= nil,
          format("%s %s: separator %d (%s) ornament piece only when centred", key, view, i, sp.kind))
      end
    end
    SepHalves("short")
    Stub.SetShift(true)
    Stub.Advance(1)
    local long = th.native and #GameTooltip._lines or ShownRows(tf)
    T.ok(long > short, format("%s: Shift adds rows (%d -> %d)", key, short, long))
    SepHalves("Shift")
    Stub.SetShift(false)
    Stub.Advance(1)
    SepHalves("short again")
    Stub.RunScript(frame, "OnLeave")
    T.ok(not (tf and tf:IsShown()) and not (th.native and GameTooltip:IsShown() and GameTooltip:GetOwner() == frame),
      key .. ": tooltip hidden on leave")
    -- graph and window in the theme's colours
    ns.Graph.ShowFor(frame)
    Stub.Advance(1)
    T.ok(ns.Graph.frame:IsShown(), key .. ": graph shown")
    local bg = th.ui.bg
    local gf = ns.Graph.frame
    T.eq({ rawget(gf, "_bgR"), rawget(gf, "_bgG"), rawget(gf, "_bgB"), rawget(gf, "_bgA") },
      { bg[1], bg[2], bg[3], 0.92 }, key .. ": graph backdrop")
    ns.Graph.Hide()
    ns.Window.Show()
    local win = rawget(_G, "TruePlayedStatsFrame")
    T.ok(win and win:IsShown(), key .. ": window shown")
    ns.Window.Hide()
  end
  -- the options panel follows the switches while open
  ns.Options.Open()
  Set(ns, "theme", "mage")
  Set(ns, "theme", "actuel")
  T.eq(#Stub.errors, 0, "no Lua error")
end)

---------------------------------------------------------------------------
-- Bar panel insets, sliced gradients, half-texel cuts
---------------------------------------------------------------------------

T.test("bar panel: the FILL parts keep the theme's insets", function()
  local ns, frame = Start()
  local Themes = ns.Themes
  Set(ns, "widget.bgAlpha", 0.5)
  for _, key in ipairs(Themes.KEYS) do
    Set(ns, "theme", key)
    local th = Themes.Active()
    local parts = type(th.bar.panel) == "table" and th.bar.panel.parts or nil
    if parts then
      local fw, fh = frame:GetWidth(), frame:GetHeight()
      local minL, minB, maxR, maxT
      for _, P in ipairs(parts) do
        if P.anchor == "FILL" then
          local h = frame.tp.panel[P.id]
          local pieces = h.GetObjectType and { h } or h
          for _, t in ipairs(pieces) do
            if t:IsShown() then
              local l, b, w, hh = t:GetRect()
              l, b = l - frame:GetLeft(), b - frame:GetBottom()
              minL = math.min(minL or l, l); minB = math.min(minB or b, b)
              maxR = math.max(maxR or l + w, l + w); maxT = math.max(maxT or b + hh, b + hh)
            end
          end
        end
      end
      local m = { math.huge, math.huge, math.huge, math.huge }
      for _, P in ipairs(parts) do
        if P.anchor == "FILL" then
          for i = 1, 4 do m[i] = math.min(m[i], P.inset and P.inset[i] or 0) end   -- (no inset: 0)
        end
      end
      T.eq({ minL, minB, maxR, maxT }, { m[1], m[4], fw - m[2], fh - m[3] }, key .. ": bar insets")
    end
  end
end)

T.test("sliced gradients: one ramp over the 9 pieces of a panel (bar and tooltip), re-cut on resize only", function()
  local ns, frame = Start()
  local Themes = ns.Themes
  Set(ns, "widget.bgAlpha", 0.6)
  Set(ns, "theme", "mage")
  local th = Themes.Active()
  local P
  for _, p in ipairs(th.bar.panel.parts) do
    if p.id == "panelFill" then P = p end
  end
  T.ok(P and P.kind == "nine" and P.g and P.g.dir == "VERTICAL", "mage panelFill: vertical gradient on a 9-slice")
  local pieces = frame.tp.panel.panelFill
  local from, to = Rgba(P.g[1]), Rgba(P.g[2])           -- (a part: one pair { from, to })
  from[4], to[4] = from[4] * 0.6, to[4] * 0.6                -- alpha "bg"
  local f7, t7 = Grad(pieces[7])
  local f4, t4 = Grad(pieces[4])
  local f1, t1 = Grad(pieces[1])
  Near4(f7, from, "bottom row starts at `from`")
  Near4(t1, to, "top row ends at `to`")
  Near4(t7, f4, "bottom row -> middle row: continuous")
  Near4(t4, f1, "middle row -> top row: continuous")
  local f9 = Grad(pieces[9])
  Near4(f9, f7, "a row has one colour across")
  -- steady ticks: no gradient call
  local seq = rawget(pieces[5], "_gSeq")
  Stub.Advance(30)
  T.eq(rawget(pieces[5], "_gSeq"), seq, "no SetGradient on steady ticks")
  -- the tooltip panel of the same theme
  Stub.RunScript(frame, "OnEnter")
  Stub.Advance(1)
  local tf = ns.TooltipFrame.frame
  local bg = tf.tp.panel.bg
  T.ok(type(bg) == "table" and #bg == 9, "tooltip bg: 9 pieces")
  local _, b7 = Grad(bg[7])
  local a4, b4 = Grad(bg[4])
  local a1 = Grad(bg[1])
  Near4(b7, a4, "tooltip: bottom -> middle continuous")
  Near4(b4, a1, "tooltip: middle -> top continuous")
  local h1 = tf:GetHeight()
  local cut = b7
  Stub.SetShift(true)
  Stub.Advance(1)
  T.ok(tf:GetHeight() > h1, "Shift: taller tooltip")
  local _, b7s = Grad(bg[7])
  T.ok(math.abs(b7s[1] - cut[1]) + math.abs(b7s[4] - cut[4]) > 1e-6, "taller: the ramp is cut again")
  local _, b4s = Grad(bg[4])
  local a1s = Grad(bg[1])
  Near4(b4s, a1s, "taller: still continuous")
  Stub.SetShift(false)
  Stub.RunScript(frame, "OnLeave")
end)

T.test("stretched slices sample half a texel inside their cuts (no corner bleed)", function()
  local ns, frame = Start()
  local th = ns.Themes.Active()
  local Lc
  for _, l in ipairs(th.bar.layers) do
    if l.id == "trackFrame" then Lc = l end
  end
  T.ok(Lc and Lc.kind == "nine", "futuriste trackFrame is a 9-slice")
  local spec = Lc.tex
  local c, tw, thh = spec.slice[1], spec.w, spec.h
  local pieces = frame.tp.tex.trackFrame
  T.eq(pieces[1]._tc, { 0, c / tw, 0, c / thh }, "corner: the whole cut")
  local tc = pieces[5]._tc
  T.near(tc[1], (c + 0.5) / tw, 1e-9, "centre left")
  T.near(tc[2], (tw - c - 0.5) / tw, 1e-9, "centre right")
  T.near(tc[3], (c + 0.5) / thh, 1e-9, "centre top")
  T.near(tc[4], (thh - c - 0.5) / thh, 1e-9, "centre bottom")
end)

---------------------------------------------------------------------------
-- The user's configuration
---------------------------------------------------------------------------

T.test("user configuration: font 14, width 370, height 15, French, level-20 druid at a server cap", function()
  local ns, frame = Start({
    level = 20, xp = 58, max = 23200, locale = "frFR",
    db = { schema = 1, settings = { firstRunDone = true,
      widget = { fontSize = 14, width = 370, height = 15, locked = true } } },
  })
  for _ = 1, 3 do
    Stub.KillNoXP({ level = 20 })
    Stub.Advance(30)
  end
  T.ok(ns.Tracker.IsMax(), "server cap detected")
  local L = ns.L
  local Themes = ns.Themes
  for _, value in ipairs({ "futuriste", "class", "actuel" }) do
    if value ~= "futuriste" then Set(ns, "theme", value) end
    local th = Themes.Active()
    local key = th.key
    local tp = frame.tp
    -- geometry (SPEC-themes 2.4)
    local text, bar = th.text, th.bar
    local function Sz(e)
      local _, s = Themes.Font(text.font[e], 14 + text.size[e])
      return s
    end
    local H = math.max(bar.hMin, 15 + bar.hAdd)
    local topRow = math.max(Sz("s1"), Sz("s3")) + 2
    local bottom = math.max(Sz("level"), Sz("xp"), Sz("s2"))
    if text.split then bottom = math.max(bottom, Sz("levelValue"), Sz("xpLabel")) end
    T.eq({ frame:GetWidth(), frame:GetHeight() },
      { 370 + 2 * bar.pad, bar.pad + topRow + bar.gap + H + bar.gap + bottom + 2 + bar.pad }, key .. ": frame size")
    -- level text with the cap tag, no XP numbers, no % marker
    if text.split then
      local label = format(text.levelFmt == "title" and L.LEVEL_TITLE_FMT or L.LEVEL_SHORT_FMT, 20)
      T.eq(tp.bl:GetText(), label, key .. ": level label")
      T.eq(tp.blv:GetText(), text.levelFmt == "title" and L.LEVEL_CAP_TAG_TITLE or L.LEVEL_CAP_TAG, key .. ": cap tag")
      T.ok(tp.blv:IsShown(), key .. ": cap tag shown")
      T.ok(not tp.xpl:IsShown(), key .. ": no XP label at the cap")
    else
      T.eq(tp.bl:GetText(), format(L.LEVEL_CAP_FMT, 20), key .. ": level text")
    end
    T.ok(not tp.brx:IsShown(), key .. ": no XP numbers at the cap")
    T.ok(not tp.marker:IsShown(), key .. ": no % marker at the cap")
    -- slots drawn, nothing overlapping, everything inside the track width
    for i = 1, 3 do
      T.ok(tp.slots[i]:IsShown() and tp.slots[i]:GetText() ~= "", key .. ": slot " .. i)
    end
    local x0, x1 = bar.pad, bar.pad + 370
    local bottomRow = { tp.bl }
    if text.split then bottomRow[#bottomRow + 1] = tp.blv end
    bottomRow[#bottomRow + 1] = tp.slots[2]
    local prev = x0
    for _, fs in ipairs(bottomRow) do
      local l, r = Span(fs)
      T.ok(l >= prev - 0.5 and r <= x1 + 0.5, format("%s: bottom row %s..%s after %s", key, l, r, prev))
      prev = r
    end
    local l3, r3 = Span(tp.slots[3])
    local l1, r1 = Span(tp.slots[1])
    T.ok(l3 >= x0 and r3 <= l1 and r1 <= x1 + 0.5, key .. ": top row in order")
  end
  T.eq(#Stub.errors, 0, "no Lua error")
end)

T.test("slot 2 colour role: the boards' rate colour, user colour wins", function()
  local ns, frame = Start()
  Set(ns, "widget.slots.2", "session")                -- not dimmed while playing
  local s2 = frame.tp.slots[2]
  local function Color(fs)
    local r, g, b = fs:GetTextColor()
    return { math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5) }
  end
  local th = ns.Themes.Active()
  T.eq(Color(s2), Color({ GetTextColor = function() return th.text.colors.value[1], th.text.colors.value[2],
    th.text.colors.value[3] end }), "futuriste: slot 2 = value (default role)")
  Set(ns, "theme", "rogue")
  T.eq(Color(s2), { 0xa6, 0xe8, 0x7a }, "rogue: the board's green rate")
  Set(ns, "widget.textColor", { 1, 0, 0 })
  T.eq(Color(s2), { 255, 0, 0 }, "a user text colour overrides every role")
end)

---------------------------------------------------------------------------
-- Rebuild equivalence: after a theme switch, with the tooltip shown short,
-- Shift and hidden under the previous theme, the bar and the tooltip draw exactly what
-- a fresh load in the new theme draws (no pooled region keeps a previous theme's
-- coordinates, size, layer, blend, colour or gradient).
---------------------------------------------------------------------------

-- WoW geometry: every anchor constrains an edge (or the centre) and two opposite
-- anchors define the size, overriding SetSize (the stub's GetRect uses point 1 only).
local AN = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 },
             CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 },
             BOTTOMRIGHT = { 1, 0 } }

local function Solve(list, size)
  local lo, hi = list[1], list[1]
  for i = 2, #list do
    local e = list[i]
    if e[1] < lo[1] then lo = e end
    if e[1] > hi[1] then hi = e end
  end
  if hi[1] > lo[1] then
    local s = (hi[2] - lo[2]) / (hi[1] - lo[1])
    return lo[2] - s * lo[1], s
  end
  return lo[2] - size * lo[1], size
end

local function TrueRect(o, depth)
  depth = (depth or 0) + 1
  if depth > 40 or o == nil then return nil end
  if rawget(o, "_isUIParent") then return 0, 0, rawget(o, "_width"), rawget(o, "_height") end
  local pts = rawget(o, "_points")
  if not pts or #pts == 0 then return nil end
  local xs, ys = {}, {}
  for _, p in ipairs(pts) do
    local rl, rb, rw, rh = TrueRect(p.rel or rawget(o, "_parent") or UIParent, depth)
    if not rl then return nil end
    local ra, an = AN[p.relPoint] or AN.CENTER, AN[p.point] or AN.CENTER
    xs[#xs + 1] = { an[1], rl + rw * ra[1] + p.x }
    ys[#ys + 1] = { an[2], rb + rh * ra[2] + p.y }
  end
  local l, w = Solve(xs, rawget(o, "_width") or 0)
  local b, h = Solve(ys, rawget(o, "_height") or 0)
  return l, b, w, h
end

local function R4(x)
  if type(x) ~= "number" then return tostring(x) end
  return format("%.4f", math.floor(x * 10000 + 0.5) / 10000)
end

local function Inside(o, root)
  local p = rawget(o, "_parent")
  while p do
    if p == root then return true end
    p = rawget(p, "_parent")
  end
  return false
end

local function TexLine(o)
  local tc, tcs = rawget(o, "_tc"), "full"
  if tc then
    local v = {}
    for i = 1, 8 do v[i] = R4(tc[i]) end
    tcs = table.concat(v, ",")
    if tcs == "0.0000,1.0000,0.0000,1.0000,nil,nil,nil,nil"
        or tcs == "0.0000,0.0000,0.0000,1.0000,1.0000,0.0000,1.0000,1.0000" then tcs = "full" end
  end
  local col
  local vs, gs, gas = rawget(o, "_vSeq") or 0, rawget(o, "_gSeq") or 0, rawget(o, "_gaSeq") or 0
  if gs > vs and gs > gas then
    local g, v = rawget(o, "_grad"), {}
    for i = 2, 9 do v[#v + 1] = R4(g[i]) end
    col = "grad " .. tostring(g[1]) .. " " .. table.concat(v, " ")
  else
    col = "v " .. R4(rawget(o, "_vR")) .. " " .. R4(rawget(o, "_vG")) .. " " .. R4(rawget(o, "_vB")) .. " "
      .. R4(rawget(o, "_vA"))
  end
  return table.concat({ tostring(rawget(o, "_texture")), tcs, tostring(rawget(o, "_blend") or "BLEND"),
    tostring(rawget(o, "_wrapH")) .. "/" .. tostring(rawget(o, "_wrapV")), col }, " | ")
end

local function TextLine(o)
  return table.concat({ tostring(rawget(o, "_text")),
    tostring(rawget(o, "_font")) .. " " .. tostring(rawget(o, "_fontSize")) .. " " .. tostring(rawget(o, "_fontFlags")),
    R4(rawget(o, "_tR")) .. " " .. R4(rawget(o, "_tG")) .. " " .. R4(rawget(o, "_tB")) .. " " .. R4(rawget(o, "_tA")),
    tostring(rawget(o, "_justifyH")) .. " w" .. R4(rawget(o, "_width")),
    tostring(rawget(o, "_shadowX")) .. " " .. tostring(rawget(o, "_shadowY")) .. " " .. R4(rawget(o, "_sA")) }, " | ")
end

-- Sorted description of every visible texture / FontString drawn under `root`.
local function Snap(root)
  if not root or not root:IsVisible() then return { "hidden" } end
  local out = {}
  local wl, wb = TrueRect(root)
  for _, o in ipairs(Stub.regions) do
    local typ = rawget(o, "_type")
    if (typ == "Texture" or typ == "FontString") and Inside(o, root) and o:IsVisible()
        and (rawget(o, "_alpha") or 1) > 0 then
      local l, b, w, h = TrueRect(o)
      out[#out + 1] = table.concat({ typ, tostring(rawget(o, "_layer")), tostring(rawget(o, "_subLayer") or 0),
        R4(l and l - wl), R4(b and b - wb), R4(w), R4(h),
        typ == "Texture" and TexLine(o) or TextLine(o) }, " | ")
    end
  end
  table.sort(out)
  local w, h = root:GetSize()
  out[#out + 1] = "size " .. R4(w) .. " " .. R4(h)
  return out
end

-- The GameTooltip lines (native themes), with their colours, or "hidden".
local function SnapGT()
  if not GameTooltip:IsShown() then return { "hidden" } end
  local out = {}
  for i, l in ipairs(GameTooltip._lines) do
    local c, v = GameTooltip._colors[i] or {}, {}
    for j = 1, 6 do v[j] = R4(c[j]) end
    out[i] = tostring(l[1]) .. " | " .. tostring(l[2]) .. " | " .. table.concat(v, " ")
  end
  return out
end

-- Loads the addon (theme `initial`), plays `steps`, then snaps the bar,
-- the short tooltip, the Shift tooltip and the short one again (the private frame and
-- the GameTooltip).
local function Drawn(initial, steps)
  Stub.Reset()
  local settings = { firstRunDone = true, widget = { bgAlpha = 0.6, locked = true } }
  settings.theme = initial
  local ns, frame = Start({ rest = 3000, xp = 2000, db = { schema = 1, settings = settings } })
  for _, st in ipairs(steps) do
    if st.theme then ns.Core.SetSetting("theme", st.theme) end
    if st.tip == "short" then Stub.RunScript(frame, "OnEnter") end
    if st.tip == "shift" then Stub.SetShift(true) end
    if st.tip == "unshift" then Stub.SetShift(false) end
    if st.tip == "hide" then Stub.RunScript(frame, "OnLeave") end
    Stub.Advance(1)
  end
  local snaps = { bar = Snap(frame) }
  Stub.RunScript(frame, "OnEnter"); Stub.Advance(1)
  local tf = ns.TooltipFrame.frame
  snaps.tip, snaps.gtTip = Snap(tf), SnapGT()
  Stub.SetShift(true); Stub.Advance(1)
  snaps.shift, snaps.gtShift = Snap(tf), SnapGT()
  Stub.SetShift(false); Stub.Advance(1)
  snaps.short2, snaps.gtShort2 = Snap(tf), SnapGT()
  Stub.RunScript(frame, "OnLeave")
  T.eq(#Stub.errors, 0, "no Lua error")
  return snaps
end

T.test("rebuild equivalence: a theme switch draws exactly what a fresh load draws", function()
  local pairsAB = { { "mage", "futuriste" }, { "warrior", "rogue" }, { "futuriste", "druid" },
                    { "druid", "actuel" }, { "actuel", "warlock" }, { "pixel", "heroic" },
                    { "priest", "hunter" }, { "shaman", "paladin" } }
  local runs = 0
  for _, ab in ipairs(pairsAB) do
    local A, B = ab[1], ab[2]
    local steps = { { theme = A }, { tip = "short" }, { tip = "shift" }, { tip = "unshift" }, { tip = "hide" },
                    { theme = B } }
    -- the fresh load runs as many seconds as the switch (the Shift lines depend on time)
    local idle = {}
    for i = 1, #steps do idle[i] = {} end
    local fresh = Drawn(B, idle)
    T.ok(#fresh.bar > 5 and (#fresh.tip > 10 or #fresh.gtTip > 10), B .. ": the snapshots describe the drawing")
    local got = Drawn(nil, steps)
    runs = runs + 1
    for _, view in ipairs({ "bar", "tip", "shift", "short2", "gtTip", "gtShift", "gtShort2" }) do
      T.eq(got[view], fresh[view], format("%s -> %s, %s", A, B, view))
    end
  end
  T.eq(runs, 8, "runs")
end)
