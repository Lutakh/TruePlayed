-- tests/test_round4_regress.lua - regressions found by the fourth verification round of
-- the themes (design/SPEC-themes.md): the private tooltip of a hidden owner, the truncated tooltip label after a rebuild, what a
-- theme switch keeps of the previous compiled theme (P5), the work done by a user colour
-- change, the colour of a gradient layer on a client that ignores SetGradient.
-- The stub measures 6 px per character (colour codes left out). Themes.Compile returns the
-- warnings of the test-only validator (tests/theme_validate.lua).
local Stub, T = ...
local TV = dofile(Stub.ROOT .. "tests/theme_validate.lua")

local format = string.format

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Start(theme, opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false })
  Stub.theme = theme
  if opts.xp then Stub.player.xp = opts.xp end
  if opts.rest then Stub.player.rest = opts.rest end
  if opts.locale then Stub.locale = opts.locale end
  local ns = Stub.LoadAddon()
  TV.Install(ns)
  Stub.LoginSequence({ settle = 3 })
  return ns, ns.Bar.frame
end

local function Set(ns, path, value)
  ns.Core.SetSetting(path, value)
  Stub.Advance(1)
end

-- The shared method table of the stub's regions (every frame, texture and FontString).
local function Methods()
  return getmetatable(UIParent).__index
end

-- Runs body() with the stub method `name` replaced by fn(original, self, ...); the
-- original is restored even when body fails.
local function WithMethod(name, fn, body)
  local M = Methods()
  local orig = rawget(M, name)
  rawset(M, name, function(self, ...) return fn(orig, self, ...) end)
  local ok, err = pcall(body)
  rawset(M, name, orig)
  if not ok then error(err, 0) end
end

-- The client's GetStringWidth: a FontString with an explicit width reports at most that
-- width (GetUnboundedStringWidth gives the whole text).
local function Bounded(orig, self)
  local w = orig(self)
  local b = rawget(self, "_width") or 0
  if b > 0 and w > b then return b end
  return w
end

---------------------------------------------------------------------------
-- R2: the private tooltip of an owner hidden without OnLeave (addon compartment)
---------------------------------------------------------------------------

T.test("R2: the private tooltip ends when its owner is hidden without OnLeave", function()
  local ns = Start(nil)                                -- futuriste: the private frame
  local btn = CreateFrame("Button", nil, UIParent)
  btn:SetSize(100, 20)
  btn:SetPoint("CENTER")
  btn:Show()
  TruePlayed_OnAddonCompartmentEnter("TruePlayed", btn)
  local tf = ns.TooltipFrame.frame
  T.ok(tf and tf:IsShown() and tf:GetOwner() == btn, "shown for the compartment entry")
  local fills = 0
  local orig = ns.Tooltip.Fill
  ns.Tooltip.Fill = function(...) fills = fills + 1 return orig(...) end
  Stub.Advance(1)
  T.eq(fills, 1, "refreshed on TICK while its owner is shown")
  fills = 0
  btn:Hide()                                           -- the menu closes: no OnLeave
  Stub.Advance(5)
  ns.Tooltip.Fill = orig
  T.no(tf:IsShown(), "hidden with its owner (at the next refresh at the latest)")
  T.ok(fills <= 1, "no refresh of a tooltip whose owner is gone (" .. fills .. ")")
  T.no(ns.Tooltip.IsShownFor(btn), "no longer shown for the entry")
  -- the bar itself: shown again on hover, hidden with the bar at once (OnHide)
  local frame = ns.Bar.frame
  Stub.RunScript(frame, "OnEnter")
  T.ok(tf:IsShown() and tf:GetOwner() == frame, "shown for the bar")
  frame:Hide()
  T.no(tf:IsShown(), "hidden at once with the bar")
end)

T.test("R2: a visible owner keeps its private tooltip and its refreshes", function()
  local ns, frame = Start(nil)
  Stub.RunScript(frame, "OnEnter")
  local tf = ns.TooltipFrame.frame
  local fills = 0
  local orig = ns.Tooltip.Fill
  ns.Tooltip.Fill = function(...) fills = fills + 1 return orig(...) end
  Stub.Advance(5)
  ns.Tooltip.Fill = orig
  T.ok(tf:IsShown() and tf:GetOwner() == frame, "still shown")
  T.eq(fills, 5, "one refresh per TICK")
end)

---------------------------------------------------------------------------
-- R3: a truncated tooltip label stays truncated after a rebuild (recolour, theme switch)
---------------------------------------------------------------------------

local LONG = "Reconstitue apres plantage du client et rechargement de l'interface"
local VALUE = "12 h 34 min"
local WHITE = { 1, 1, 1, 1 }

-- Shows the private frame with a title and one pair row whose label cannot fit; returns
-- the frame width, the label box and whether the drawn label overlaps the value.
local function ShowLong(ns)
  local tf = ns.TooltipFrame.Get()
  tf:SetOwner(UIParent, "ANCHOR_NONE")
  tf:TP_Row("title", "TruePlayed", nil, WHITE)
  tf:TP_Row("pair", LONG, VALUE, WHITE, WHITE)
  tf:Show()
  local tt = ns.Themes.Active().tt
  local row = tf.tp.rows[2]
  local inner = tf:GetWidth() - tt.pad[1] - tt.pad[2]
  local room = inner - row.right:GetUnboundedStringWidth() - tt.gap
  local box = rawget(row.left, "_width") or 0
  local drawn = (box > 0) and box or row.left:GetUnboundedStringWidth()
  return { w = tf:GetWidth(), box = box, overlaps = drawn > room }
end

T.test("R3: a cut tooltip label is measured unbounded again after a recolour or a theme switch", function()
  WithMethod("GetStringWidth", Bounded, function()
    local ns = Start(nil)
    local fresh = ShowLong(ns)
    T.ok(fresh.box > 0 and not fresh.overlaps, "fresh futuriste: the label is cut before the value")
    Set(ns, "widget.xpColor", { 0, 1, 0 })
    T.eq(ShowLong(ns), fresh, "after a recolour: as a fresh show")
    Stub.Advance(3)
    T.eq(ShowLong(ns), fresh, "and on the next shows")
    Set(ns, "theme", "pixel")
    local switched = ShowLong(ns)
    Stub.Reset()
    local ns2 = Start("pixel")
    T.eq(switched, ShowLong(ns2), "after a switch to pixel: as a fresh pixel show")
  end)
end)

---------------------------------------------------------------------------
-- PERF-1: a theme switch keeps nothing of the previous compiled theme (P5)
---------------------------------------------------------------------------

-- Every table reachable from `root`, marked in a weak-keyed set; returns it and its size.
-- Tables in `skip` (and below them) are left out.
local function Mark(root, skip)
  local set = setmetatable({}, { __mode = "k" })
  local n = 0
  skip = skip or {}
  local stack = { root }
  while #stack > 0 do
    local t = table.remove(stack)
    if not set[t] and not skip[t] then
      set[t] = true
      n = n + 1
      for k, v in next, t do
        if type(k) == "table" and not set[k] then stack[#stack + 1] = k end
        if type(v) == "table" and not set[v] then stack[#stack + 1] = v end
      end
    end
  end
  return set, n
end

local function Exercise(ns, frame)
  Stub.RunScript(frame, "OnEnter")
  Stub.Advance(1)
  Stub.SetShift(true)
  Stub.Advance(1)
  Stub.SetShift(false)
  Stub.Advance(1)
  Stub.RunScript(frame, "OnLeave")
  ns.Graph.ShowFor(frame)
  Stub.Advance(1)
  ns.Graph.Hide()
  ns.Window.Show()
  Stub.Advance(1)
  ns.Window.Hide()
end

T.test("PERF-1: after a theme switch no table of the previous compiled theme stays alive", function()
  local ns, frame = Start(nil, { xp = 2000, rest = 3000 })
  Set(ns, "widget.bgAlpha", 0.5)
  Exercise(ns, frame)
  local order = { "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue", "priest",
                  "shaman", "mage", "warlock", "druid", "futuriste", "actuel" }
  -- the classic palette is a constant of Themes, shared by the native theme (th.tt.colors)
  local permanent = Mark(ns.Themes.CLASSIC_TT)
  local alive = {}
  for _, key in ipairs(order) do
    local prevKey = ns.Themes.ActiveKey()
    local old, n = Mark(ns.Themes.Active(), permanent)
    T.ok(n > 10, prevKey .. ": tables marked")
    Set(ns, "theme", key)
    -- right after the switch (nothing shown since), then after using everything again
    for pass = 1, 2 do
      if pass == 2 then Exercise(ns, frame) end
      for _ = 1, 3 do collectgarbage("collect") end
      local left = 0
      for _ in pairs(old) do left = left + 1 end
      if left > 0 then alive[#alive + 1] = format("%s -> %s (pass %d): %d of %d", prevKey, key, pass, left, n) end
    end
  end
  T.eq(alive, {}, "tables of the previous compiled theme still alive")
end)

---------------------------------------------------------------------------
-- F1 (parity): a user XP / rested colour change does no work in the graph and the window
---------------------------------------------------------------------------

T.test("F1-parity: an XP colour change neither rebuilds the window nor restyles the graph", function()
  for _, key in ipairs({ "actuel", "futuriste" }) do
    Stub.Reset()
    local ns, frame = Start(key)
    Stub.Advance(30)
    Set(ns, "widget.locked", true)
    Stub.RunScript(frame.tp.hits[3], "OnEnter")       -- the graph panel is created
    Stub.RunScript(frame.tp.hits[3], "OnLeave")
    Stub.Advance(2)
    ns.Window.Show("levels")
    ns.Options.Open()
    local n = { opt = 0, win = 0, graph = 0, wapply = 0 }
    local o1, o2, o3, o4 = ns.Options.Refresh, ns.Window.Refresh, ns.Graph.ApplyTheme, ns.Window.ApplyTheme
    ns.Options.Refresh = function(...) n.opt = n.opt + 1 return o1(...) end
    ns.Window.Refresh = function(...) n.win = n.win + 1 return o2(...) end
    ns.Graph.ApplyTheme = function(...) n.graph = n.graph + 1 return o3(...) end
    ns.Window.ApplyTheme = function(...) n.wapply = n.wapply + 1 return o4(...) end
    ns.Core.SetSetting("widget.xpColor", { 0.3, 0.6, 0.9 })
    ns.Core.SetSetting("widget.restedColor", { 0.2, 0.9, 0.4 })
    T.eq(n, { opt = 2, win = 0, graph = 0, wapply = 0 }, key .. ": work per colour change")
    -- a theme switch still restyles both
    ns.Core.SetSetting("theme", key == "actuel" and "mage" or "actuel")
    T.eq(n.graph, 1, key .. ": the graph follows a theme switch")
    T.eq(n.wapply, 1, key .. ": the window follows a theme switch")
    T.ok(n.win >= 1, key .. ": the shown window is rebuilt at a theme switch")
    ns.Options.Refresh, ns.Window.Refresh, ns.Graph.ApplyTheme, ns.Window.ApplyTheme = o1, o2, o3, o4
  end
end)

T.test("F1-parity: the ui roles of every theme do not follow the user colours", function()
  local ns = Start(nil)
  for _, key in ipairs(KEYS) do
    local th, warnings = ns.Themes.Compile(key)
    T.ok(th, key)
    T.eq(warnings, {}, key .. ": no warning")
    local before = {}
    for role, c in pairs(th.ui) do before[role] = { c[1], c[2], c[3] } end
    ns.Core.SetSetting("widget.xpColor", { 0, 1, 0 })
    ns.Core.SetSetting("widget.restedColor", { 1, 0, 0 })
    local th2 = ns.Themes.Compile(key)
    for role, c in pairs(th2.ui) do T.eq({ c[1], c[2], c[3] }, before[role], key .. " ui." .. role) end
    ns.Core.SetSetting("widget.xpColor", false)
    ns.Core.SetSetting("widget.restedColor", false)
  end
end)

---------------------------------------------------------------------------
-- F2 (parity): a gradient layer has its flat colour when the client ignores SetGradient
---------------------------------------------------------------------------

T.test("F2-parity: Classic's rested part is not white when SetGradient silently does nothing", function()
  WithMethod("SetGradient", function() end, function()
    local _, frame = Start("actuel", { xp = 2000, rest = 3000 })
    Stub.Advance(3)
    local t = frame.tp.tex.rested
    T.ok(t:IsShown(), "rested part shown")
    local r, g, b, a = t:GetVertexColor()
    T.ok(r ~= nil, "a vertex colour was set")
    -- the flat colour of the classic rested part (REST_FLAT_0 of the pre-theme code)
    T.near(r, 0.35, 1e-6, "r")
    T.near(g, 0.62, 1e-6, "g")
    T.near(b, 1.0, 1e-6, "b")
    T.near(a, 0.40, 1e-6, "a")
  end)
end)

T.test("F2-parity: the flat colour comes before the gradient (the gradient is the last colour call)", function()
  local _, frame = Start("actuel", { xp = 2000, rest = 3000 })
  Stub.Advance(3)
  local t = frame.tp.tex.rested
  T.ok(rawget(t, "_grad") ~= nil, "gradient applied")
  T.ok((rawget(t, "_gSeq") or 0) > (rawget(t, "_vSeq") or 0), "SetGradient after SetVertexColor")
end)

---------------------------------------------------------------------------
-- Fidelity with the real fonts (tests/fontmetrics.lua)
---------------------------------------------------------------------------

local FM = dofile(Stub.ROOT .. "tests/fontmetrics.lua")
local fontWidth                                        -- loaded once (the font files are read lazily)
local function RealWidths(body)
  fontWidth = fontWidth or FM.New(Stub.ROOT)
  local restore = FM.Install(Stub, fontWidth)
  local ok, err = pcall(body, fontWidth)
  restore()
  if not ok then error(err, 0) end
end

-- A level-20 character (as on the boards) after some play: "kills" = 8 kills in 4 min
-- (estimate status, the widest values), "none" = no kill yet, "long" = an hour of kills.
local function StartPlay(theme, locale, play)
  Stub.InstallUI({ ldb = false })
  Stub.theme = theme
  Stub.locale = locale
  local p = Stub.player
  p.level, p.xp, p.rest = 20, 10115, 0
  p.max = Stub.xpTable[20] or 23200
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Set(ns, "widget.locked", true)
  if play == "kills" then
    for _ = 1, 8 do Stub.Advance(30); Stub.Kill(171) end
  elseif play == "long" then
    for _ = 1, 60 do Stub.Advance(60); Stub.Kill(171) end
  elseif play == "stall" then
    for _ = 1, 8 do Stub.Advance(30); Stub.Kill(171) end
    Stub.Advance(900)
  elseif play == "activity" then
    -- lot 8: every breakdown part but the instances, 12 deaths and 1 h 05 dead, crafting
    for _ = 1, 20 do Stub.Advance(60); Stub.Kill(171) end
    for _ = 1, 12 do Stub.Die(); Stub.Advance(65); Stub.ReleaseSpirit(); Stub.Advance(260); Stub.Resurrect(true) end
    Stub.OpenTradeSkill(); Stub.Advance(1500); Stub.CloseTradeSkill()
    Stub.SetAFK(true); Stub.Advance(900); Stub.SetAFK(false)
    Stub.SetTaxi(true); Stub.Advance(600); Stub.SetTaxi(false)
    Stub.SetMap(1454); Stub.Advance(600); Stub.SetMap(1411)
    Stub.SetResting(true); Stub.Advance(600); Stub.SetResting(false)
  elseif play == "cap" then
    for _ = 1, 3 do Stub.KillNoXP() end
  end
  Stub.Advance(2)
  return ns, ns.Bar.frame
end

-- Rows of the shown private tooltip that do not fit: a cut label (a pair whose label and
-- value do not fit the inner width) or a single-line row wider than the inner width.
local function CutRows(ns)
  local tf = ns.TooltipFrame.frame
  local tt = ns.Themes.Active().tt
  local inner = tf:GetWidth() - tt.pad[1] - tt.pad[2]
  local out = {}
  for i = 1, tf.tp.n do
    local row = tf.tp.rows[i]
    if not row.wrap and row.left:IsShown() then
      local lw = row.left:GetUnboundedStringWidth()
      local need = lw
      if row.right:IsShown() and row.kind ~= "title" then
        need = lw + tt.gap + row.right:GetUnboundedStringWidth()
      end
      if (rawget(row.left, "_width") or 0) > 0 or need > inner + 0.5 then
        out[#out + 1] = format("%q %.0f > %.0f", tostring(row.left:GetText()), need, inner)
      end
    end
  end
  return out
end

T.test("F1-fidelity: no tooltip row is cut with the real fonts (every theme, enUS / frFR, short / Shift)", function()
  RealWidths(function()
    local bad = {}
    for _, key in ipairs(KEYS) do
      if key ~= "actuel" then
        for _, locale in ipairs({ "enUS", "frFR" }) do
          for _, play in ipairs({ "kills", "none", "long", "stall", "cap", "activity" }) do
            Stub.Reset()
            local ns, frame = StartPlay(key, locale, play)
            for _, shift in ipairs({ false, true }) do
              Stub.SetShift(shift)
              ns.Tooltip.ShowFor(frame)
              Stub.Advance(1)
              for _, s in ipairs(CutRows(ns)) do
                bad[#bad + 1] = format("%s %s %s %s: %s", key, locale, play, shift and "Shift" or "short", s)
              end
              ns.Tooltip.Hide()
            end
            Stub.SetShift(false)
          end
        end
      end
    end
    T.eq(bad, {}, "cut tooltip rows")
  end)
end)

-- The widest values the XP block can take (the longest warm-up, a days-long estimated
-- ETA, a 6-digit estimated rate, ...) beside their labels fit the widest tooltip of every
-- theme, with MARGIN px to spare for the client's own glyph metrics (hinting, kerning).
local MARGIN = 16

T.test("F1-fidelity: the widest XP rows fit every theme's widest tooltip with a margin", function()
  fontWidth = fontWidth or FM.New(Stub.ROOT)
  local Width = fontWidth
  local bad = {}
  for _, locale in ipairs({ "enUS", "frFR" }) do
    Stub.Reset()
    local ns = Start(nil, { locale = locale })
    local L, Fmt = ns.L, ns.Fmt
    local function Estimated(text)
      return format("%s %s(%s)%s", ns.Tokens.Approx(text), "|cff999999", L.RATE_ESTIMATE, "|r")
    end
    local rows = {
      { L.TT_XPH, format(L.TT_NODATA_FMT, Fmt.Duration(ns.C.WARMUP_FULL)) },
      { L.TT_NEXT_LEVEL, Estimated(Fmt.ETA(2 * 86400 + 5 * 3600)) },
      { L.TT_XPH, Estimated(Fmt.Rate(123456)) },
      { L.TT_KILLS, L.TT_KILLS_NODATA },
      { L.TT_KILLS, format(L.TT_KILLS_FMT, Fmt.Number(1234), Fmt.Number(12345), Fmt.Number(12345)) },
      { L.TT_NEXT_LEVEL, format(L.TT_WARMING_FMT, Fmt.Duration(ns.C.WARMUP_FULL)) },
    }
    for _, key in ipairs(KEYS) do
      if key ~= "actuel" then
        Set(ns, "theme", key)
        local tt = ns.Themes.Active().tt
        local bp, bs = ns.Themes.Font(tt.fonts.body[1], tt.fonts.body[2])
        local vf = tt.fonts.value or tt.fonts.body
        local vp, vs = ns.Themes.Font(vf[1], vf[2])
        for _, r in ipairs(rows) do
          local need = Width(bp, bs, r[1]) + tt.gap + Width(vp, vs, r[2]) + tt.pad[1] + tt.pad[2]
          if need + MARGIN > tt.width[2] then
            bad[#bad + 1] = format("%s %s: %q + %q needs %.0f + %d > %d", key, locale, r[1], r[2], need, MARGIN,
              tt.width[2])
          end
        end
      end
    end
  end
  T.eq(bad, {}, "XP rows wider than the tooltip")
end)

---------------------------------------------------------------------------
-- F2 (fidelity): the warlock bar's "XP :" label in the board's soul blue
---------------------------------------------------------------------------

T.test("F2-fidelity: the warlock XP label is soulHi #a3a4f6 (Demoniste board)", function()
  local _, frame = Start("warlock", { xp = 2000 })
  local xpl = frame.tp.xpl
  T.ok(xpl and xpl:IsShown(), "split XP label shown")
  local r, g, b = xpl:GetTextColor()
  local function Byte(x) return math.floor(x * 255 + 0.5) end
  T.eq({ Byte(r), Byte(g), Byte(b) }, { 0xa3, 0xa4, 0xf6 }, "XP label colour")
end)

---------------------------------------------------------------------------
-- F3 (fidelity): the bar's background panel reaches under the end ornaments
---------------------------------------------------------------------------

-- x0, x1, y0, y1 of a texture placed on one BOTTOMLEFT point of the widget (BarSkin).
local function Box(t)
  local p = rawget(t, "_points") and t._points[1]
  if not p then return nil end
  local x, y = p.x or 0, p.y or 0
  return x, x + (rawget(t, "_width") or 0), y, y + (rawget(t, "_height") or 0)
end

local function EachTexture(h, fn)
  if type(h) ~= "table" then return end
  if h.GetObjectType then fn(h) else for _, t in ipairs(h) do fn(t) end end
end

T.test("F3-fidelity: with a background, every bar layer lies over the panel (bar style)", function()
  local bad = {}
  for _, key in ipairs(KEYS) do
    if key ~= "actuel" then
      Stub.Reset()
      local ns, frame = Start(key, { xp = 10115, rest = 5600 })
      Set(ns, "widget.bgAlpha", 0.6)
      local pl, pr = math.huge, -math.huge
      for _, h in pairs(frame.tp.panel) do
        EachTexture(h, function(t)
          local x0, x1 = Box(t)
          if x0 and t:IsShown() then pl, pr = math.min(pl, x0), math.max(pr, x1) end
        end)
      end
      for id, h in pairs(frame.tp.tex) do
        EachTexture(h, function(t)
          local x0, x1 = Box(t)
          if id ~= "veil" and x0 and t:IsShown() and (x0 < pl or x1 > pr) then
            bad[#bad + 1] = format("%s %s: x %.0f..%.0f, panel %.0f..%.0f", key, id, x0, x1, pl, pr)
          end
        end)
      end
    end
  end
  table.sort(bad)
  T.eq(bad, {}, "bar layers outside the panel")
end)

---------------------------------------------------------------------------
-- F4 (fidelity): the shaman's elemental stones (Chaman board)
---------------------------------------------------------------------------

T.test("F4-fidelity: four shaman stones at 12.5 / 37.5 / 62.5 / 87.5 %, clear of the top text row", function()
  for _, fs in ipairs({ 11, 14, 16 }) do
    Stub.Reset()
    local ns, frame = Start("shaman")
    Set(ns, "widget.fontSize", fs)
    local tp = frame.tp
    local stones = tp.tex.stones
    T.eq(#stones, 4, "four stones")
    local ox = select(4, tp.tex.track:GetPoint(1))
    local W = tp.tex.track:GetWidth()
    -- the stone art (stud.tga, 32 x 32 drawn 16 x 16) starts on its second texel row
    local artTop = -math.huge
    for i, t in ipairs(stones) do
      local x0, x1, _, y1 = Box(t)
      T.eq((x0 + x1) / 2 - ox, math.floor(W * (2 * i - 1) / 8 + 0.5), format("fs %d: stone %d centre", fs, i))
      artTop = math.max(artTop, y1 - 0.5)
    end
    for _, i in ipairs({ 1, 3 }) do                       -- the top row: slots 1 and 3
      local s = tp.slots[i]
      local _, _, _, _, y = s:GetPoint(1)
      T.ok(s:IsShown() and y >= artTop, format("fs %d: slot %d bottom %.1f clears the stones (art top %.1f)", fs, i,
        y, artTop))
    end
  end
end)

---------------------------------------------------------------------------
-- F6 (fidelity): centred separator ornaments keep their proportions
---------------------------------------------------------------------------

-- Horizontal and vertical scale (px per texel) of a separator piece.
local function Scale(t, spec)
  local tc = rawget(t, "_tc")
  local du, dv = math.abs(tc[2] - tc[1]) * spec.w, math.abs(tc[4] - tc[3]) * spec.h
  return t:GetWidth() / du, t:GetHeight() / dv
end

T.test("F6-fidelity: the leaf, arrow, rune and elemental separators are not stretched", function()
  local seen = {}
  for _, key in ipairs({ "druid", "hunter", "mage", "shaman" }) do
    Stub.Reset()
    local ns, frame = Start(key, { xp = 10115 })
    local th = ns.Themes.Active()
    for _, shift in ipairs({ false, true }) do
      Stub.SetShift(shift)
      ns.Tooltip.ShowFor(frame)
      Stub.Advance(1)
      local tf = ns.TooltipFrame.frame
      local inner = tf:GetWidth() - th.tt.pad[1] - th.tt.pad[2]
      for i = 1, tf.tp.nSeps do
        local s = tf.tp.seps[i]
        local cfg = th.tt.sep[s.kind]
        if cfg and cfg.tex.path:find("sep", 1, true) then
          local where = format("%s %s sep %d (%s)", key, shift and "Shift" or "short", i, s.kind)
          T.ok(cfg.center ~= nil, where .. ": a centred ornament")
          T.ok(s.c and s.c:IsShown() and s.a:IsShown() and s.b:IsShown(), where .. ": three pieces shown")
          local sx, sy = Scale(s.c, cfg.tex)
          T.near(sx / sy, 1, 0.03, where .. ": ornament proportions")
          T.near(s.a:GetWidth() + s.c:GetWidth() + s.b:GetWidth(), inner, 1e-9, where .. ": pieces fill the width")
          local ax = select(4, s.a:GetPoint(1))
          T.eq(select(4, s.c:GetPoint(1)), ax + s.a:GetWidth(), where .. ": ornament after the left side")
          T.eq(select(4, s.b:GetPoint(1)), ax + s.a:GetWidth() + s.c:GetWidth(), where .. ": right side after it")
          seen[key] = true
        end
      end
      ns.Tooltip.Hide()
    end
    Stub.SetShift(false)
  end
  T.eq(seen, { druid = true, hunter = true, mage = true, shaman = true }, "separators checked")
end)

---------------------------------------------------------------------------
-- Compiler rules added by this round (fixture under a key whose file is not loaded)
---------------------------------------------------------------------------

T.test("compile: ui roles must not follow the user colours; sep center and ticks mid are checked", function()
  Stub.theme = nil
  local ns = Stub.LoadAddon({ files = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua" } })
  TV.Install(ns)
  Stub.LoginSequence()
  local function Fixture(ui, seps, ticks)
    return {
      name = "THEME_HUNTER",
      fonts = { display = "Orbitron", body = "Rajdhani" },
      colors = { xp = "#ff2bd6", rested = "#22d3ee", label = "#a3bfcf", value = "#f0fbff", dim = "#7f96a9",
                 accent = "#22d3ee", xpish = "xp-.2" },
      media = { line = { 256, 8, grey = true }, dash = { 16, 2, grey = true } },
      bar = { layers = {
        { id = "track", layer = "BORDER" },
        { id = "ticks", ticks = ticks, sub = 3 },
        { id = "dash", file = "dash", sub = 4 },
      } },
      tooltip = { fonts = { title = { "display", 13 }, body = { "body", 14 }, note = { "body", 12 },
                            hint = { "body", 12 } },
                  colors = { title = "accent" },
                  panel = { parts = { { id = "bg", color = "#000000" } } }, sep = seps },
      ui = ui,
    }
  end
  local UI = { bg = "#000000", border = "accent", title = "accent", accent = "accent", label = "label",
               value = "value", dim = "dim" }
  local src
  ns.Themes.Register("hunter", function() return src end)
  local function Compile(ui, seps, ticks)
    src = Fixture(ui, seps, ticks)
    local th, w = ns.Themes.Compile("hunter")
    T.ok(th, "compiled")
    return th, table.concat(w, "\n")
  end
  -- clean fixture: no warning, the compiled fields
  local th, w = Compile(UI, { block = { h = 8, file = "line", center = 48 } }, { n = 4, w = 2, mid = true })
  T.eq(w, "", "clean fixture")
  T.eq(th.tt.sep.block.center, 48, "compiled center")
  T.eq(th.bar.layers[2].ticks, { n = 4, w = 2, mid = true }, "compiled mid ticks")
  -- ui roles reading xp / rested (directly or through a named colour)
  local ui2 = {}
  for k, v in pairs(UI) do ui2[k] = v end
  ui2.title, ui2.accent = "xpish", "rested+.2"
  local _, w2 = Compile(ui2, nil, { n = 4 })
  T.match(w2, "ui%.title: must not depend on the xp / rested colours", "ui.title through a named colour")
  T.match(w2, "ui%.accent: must not depend on the xp / rested colours", "ui.accent")
  -- center: inside the art, a file, and not with mirror / tile / grad
  local _, w3 = Compile(UI, { block = { h = 8, file = "line", center = 255 },
                              header = { h = 1, center = 4 },
                              footer = { h = 8, file = "line", center = 48, mirror = true } }, { n = 4 })
  T.match(w3, "sep%.block%.center must be a whole number", "center too wide")
  T.match(w3, "sep%.header%.center must be a whole number", "center without a file")
  T.match(w3, "sep%.footer%.center excludes mirror", "center with mirror")
  -- mid must be a boolean
  local _, w4 = Compile(UI, nil, { n = 4, mid = 1 })
  T.match(w4, "ticks: mid must be a boolean", "mid type")
end)

---------------------------------------------------------------------------
-- F7 (fidelity): no black colour under the transparent edge of bright art
---------------------------------------------------------------------------

-- Transparent texels (alpha 0) with a black colour 4-adjacent to visible bright texels
-- (alpha > 0, luma > 128) in a 32-bit uncompressed TGA: filtering (UI scale, minified
-- art) blends that black into the edge, a dark fringe on thin bright lines.
local function BlackFringes(path)
  local f = io.open(path, "rb")
  if not f then return -1 end
  local s = f:read("*a")
  f:close()
  local w, h = s:byte(13) + 256 * s:byte(14), s:byte(15) + 256 * s:byte(16)
  local o = 18 + s:byte(1)
  local function At(x, y) return o + (y * w + x) * 4 + 1 end   -- B, G, R, A
  local n = 0
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local i = At(x, y)
      local b, g, r, a = s:byte(i, i + 3)
      if a == 0 and r == 0 and g == 0 and b == 0 then
        local bright = false
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          local nx, ny = x + d[1], y + d[2]
          if nx >= 0 and nx < w and ny >= 0 and ny < h then
            local j = At(nx, ny)
            local b2, g2, r2, a2 = s:byte(j, j + 3)
            if a2 > 0 and 0.299 * r2 + 0.587 * g2 + 0.114 * b2 > 128 then bright = true end
          end
        end
        if bright then n = n + 1 end
      end
    end
  end
  return n
end

T.test("F7-fidelity: the theme textures carry colour into their transparent edges", function()
  local ns = Start(nil)
  local files = {}
  local function Walk(t, seen)
    if seen[t] then return end
    seen[t] = true
    for _, v in pairs(t) do
      if type(v) == "table" then Walk(v, seen) end
    end
    local p = rawget(t, "path")
    if type(p) == "string" then
      local rel = p:match("\\Media\\Themes\\(.+)$")
      if rel then files[(rel:gsub("\\", "/"))] = true end
    end
  end
  for _, key in ipairs(KEYS) do Walk(ns.Themes.Compile(key), {}) end
  local list = {}
  for rel in pairs(files) do list[#list + 1] = rel end
  table.sort(list)
  T.ok(#list > 100, "theme textures found: " .. #list)
  local bad = {}
  for _, rel in ipairs(list) do
    local n = BlackFringes(Stub.ROOT .. "Media/Themes/" .. rel)
    if n ~= 0 then bad[#bad + 1] = format("%s: %d", rel, n) end
  end
  T.eq(bad, {}, "black texels under bright edges")
end)
