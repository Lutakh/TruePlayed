-- tests/test_actuel_golden.lua - the "actuel" (Classic) theme is pixel-identical to the
-- addon before themes (design/SPEC-themes.md D3, 8.2).
--
-- Each scenario is played twice from the same world: on the frozen pre-theme copy
-- (tests/baseline/, Phase 0) and on the current tree with Stub.theme = "actuel". At every
-- stage the visible state of the widget is snapshotted and both runs must give exactly the
-- same snapshots. A snapshot is the sorted list of one line per VISIBLE region under
-- TruePlayedWidget (the region and its ancestors shown, its own alpha above 0, a texture
-- with a size, a FontString with a text) plus one line for the widget itself:
--   * textures: draw layer and sublevel, file, rect relative to the widget, the colour the
--     game draws (the LAST of SetVertexColor / SetGradient / SetGradientAlpha), blend mode,
--     texture coordinates, mask (file and wrap modes), wrap modes, alpha;
--   * font strings: layer, text, font file, size, flags, text colour, justification, shadow
--     (offset and colour), rect, width bound, alpha;
--   * frames (pause marks, graph hover regions): rect, mouse, alpha;
--   * the widget: size, scale, alpha, strata, rect, backdrop and its colours, mouse.
-- Numbers are rounded to 1e-4. Defaults are normalised (no draw layer = ARTWORK, sublevel 0,
-- blend BLEND, full texture coordinates, CLAMP wrap modes), so only what can be seen counts.
-- The tooltip snapshot is GameTooltip's lines, colours and anchor after Tooltip.ShowFor(widget).
local Stub, T = ...

local format, concat, sort = string.format, table.concat, table.sort

local BASELINE = "tests/baseline/"

local function HasBaseline()
  local f = io.open(Stub.ROOT .. BASELINE .. "TruePlayed_Camelot.toc", "r")
  if f then
    f:close()
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Snapshot
---------------------------------------------------------------------------

local function N(x)
  if x == nil then return "nil" end
  if type(x) ~= "number" then return tostring(x) end
  local s = format("%.4f", x)
  if s == "-0.0000" then s = "0.0000" end
  return s
end

local function Ns(...)
  local out = {}
  for i = 1, select("#", ...) do out[i] = N((select(i, ...))) end
  return concat(out, ",")
end

local function List(t)
  if type(t) ~= "table" then return "nil" end
  local out = {}
  for i = 1, #t do out[i] = N(t[i]) end
  return concat(out, ",")
end

local function IsUnder(o, root)
  local p, depth = rawget(o, "_parent"), 0
  while p ~= nil and depth < 50 do
    if p == root then return true end
    p = rawget(p, "_parent")
    depth = depth + 1
  end
  return false
end

local FULL_TC = { ["0.0000,1.0000,0.0000,1.0000"] = true, ["0.0000,0.0000,0.0000,1.0000,1.0000,0.0000,1.0000,1.0000"] = true }

local function Wrap(m)
  if m == nil or m == "CLAMP" then return "C" end
  return tostring(m)
end

-- The colour the game draws: the last of the three colour calls.
local function TexColor(t)
  local v, g, ga = rawget(t, "_vSeq") or 0, rawget(t, "_gSeq") or 0, rawget(t, "_gaSeq") or 0
  if g > v and g >= ga then return "grad(" .. List(rawget(t, "_grad")) .. ")" end
  if ga > v and ga > g then return "gradA(" .. List(rawget(t, "_gradA")) .. ")" end
  local r = rawget(t, "_vR")
  if r == nil then return "v(1,1,1,1)" end
  local a = rawget(t, "_vA")
  return "v(" .. Ns(r, rawget(t, "_vG"), rawget(t, "_vB"), a == nil and 1 or a) .. ")"
end

local function RelRect(o, wl, wb)
  local l, b, w, h = o:GetRect()
  if l == nil then return nil end
  return Ns(l - wl, b - wb, w, h), w, h
end

local function TextureLine(t, wl, wb)
  local rect, w, h = RelRect(t, wl, wb)
  if rect == nil or w <= 0 or h <= 0 then return nil end
  local tc = List(rawget(t, "_tc"))
  if rawget(t, "_tc") == nil or FULL_TC[tc] then tc = "full" end
  local mask = rawget(t, "_mask")
  local maskText = "none"
  if mask ~= nil then
    maskText = tostring(rawget(mask, "_texture")) .. "/" .. Wrap(rawget(mask, "_wrapH")) .. "/"
      .. Wrap(rawget(mask, "_wrapV"))
  end
  local cr = rawget(t, "_cR")
  return concat({
    "Texture", tostring(rawget(t, "_layer") or "ARTWORK"), tostring(rawget(t, "_subLayer") or 0),
    tostring(rawget(t, "_texture")), rect, TexColor(t),
    cr ~= nil and ("ctex(" .. Ns(cr, rawget(t, "_cG"), rawget(t, "_cB"), rawget(t, "_cA")) .. ")") or "-",
    tostring(rawget(t, "_blend") or "BLEND"), "tc=" .. tc, "mask=" .. maskText,
    "wrap=" .. Wrap(rawget(t, "_wrapH")) .. "/" .. Wrap(rawget(t, "_wrapV")), "a=" .. N(t:GetAlpha()),
  }, " | ")
end

local function FontStringLine(fs, wl, wb)
  local text = rawget(fs, "_text")
  if text == nil or text == "" then return nil end
  local rect = RelRect(fs, wl, wb) or "unplaced"
  local sx, sy = rawget(fs, "_shadowX") or 0, rawget(fs, "_shadowY") or 0
  local sa = rawget(fs, "_sA") or 0
  local shadow = "none"
  if (sx ~= 0 or sy ~= 0) and sa > 0 then
    shadow = Ns(sx, sy, rawget(fs, "_sR"), rawget(fs, "_sG"), rawget(fs, "_sB"), sa)
  end
  local tr = rawget(fs, "_tR")
  local color = "nil"
  if tr ~= nil then
    local ta = rawget(fs, "_tA")
    color = Ns(tr, rawget(fs, "_tG"), rawget(fs, "_tB"), ta == nil and 1 or ta)
  end
  return concat({
    "FontString", tostring(rawget(fs, "_layer") or "ARTWORK"), format("%q", tostring(text)),
    tostring(rawget(fs, "_font")), N(rawget(fs, "_fontSize")), tostring(rawget(fs, "_fontFlags") or ""),
    "c=" .. color, tostring(rawget(fs, "_justifyH") or "CENTER"), tostring(rawget(fs, "_justifyV") or "MIDDLE"),
    "shadow=" .. shadow, rect, "w=" .. N(fs:GetWidth()), "a=" .. N(fs:GetAlpha()),
  }, " | ")
end

local function FrameLine(f, wl, wb)
  local rect = RelRect(f, wl, wb) or "unplaced"
  return concat({ "Frame", tostring(rawget(f, "_type")), rect, "mouse=" .. tostring(f:IsMouseEnabled()),
                  "a=" .. N(f:GetAlpha()) }, " | ")
end

local function WidgetLine(w)
  local bd = rawget(w, "_backdrop")
  local bdText = "none"
  if type(bd) == "table" then
    local ins = bd.insets or {}
    bdText = concat({ tostring(bd.bgFile), tostring(bd.edgeFile), tostring(bd.tile), N(bd.tileSize), N(bd.edgeSize),
      Ns(ins.left, ins.right, ins.top, ins.bottom),
      "bg(" .. Ns(rawget(w, "_bgR"), rawget(w, "_bgG"), rawget(w, "_bgB"), rawget(w, "_bgA")) .. ")",
      "border(" .. Ns(rawget(w, "_bdR"), rawget(w, "_bdG"), rawget(w, "_bdB"), rawget(w, "_bdA")) .. ")" }, " ")
  end
  local l, b, ww, hh = w:GetRect()
  return concat({ "Widget", Ns(l, b, ww, hh), "scale=" .. N(w:GetScale()), "a=" .. N(w:GetAlpha()),
    "strata=" .. tostring(w:GetFrameStrata()), "shown=" .. tostring(w:IsShown()),
    "mouse=" .. tostring(w:IsMouseEnabled()), "backdrop=" .. bdText }, " | ")
end

local function BarSnapshot()
  local w = rawget(_G, "TruePlayedWidget")
  if not w then return { "no widget" } end
  local lines = { WidgetLine(w) }
  local wl, wb = w:GetRect()
  wl, wb = wl or 0, wb or 0
  local regions = Stub.regions
  for i = 1, #regions do
    local o = regions[i]
    local ty = rawget(o, "_type")
    if ty ~= "MaskTexture" and IsUnder(o, w) and o:IsVisible() and (o:GetAlpha() or 1) > 0 then
      local line
      if ty == "Texture" then
        line = TextureLine(o, wl, wb)
      elseif ty == "FontString" then
        line = FontStringLine(o, wl, wb)
      else
        line = FrameLine(o, wl, wb)
      end
      if line then lines[#lines + 1] = line end
    end
  end
  sort(lines)
  return lines
end

local function TooltipSnapshot()
  local tt = GameTooltip
  local lines = { "shown=" .. tostring(tt:IsShown()) .. " owner=" .. tostring(tt:GetOwner() == rawget(_G, "TruePlayedWidget")) }
  local pts = rawget(tt, "_points") or {}
  for i = 1, #pts do
    local p = pts[i]
    lines[#lines + 1] = "point " .. concat({ tostring(p.point), tostring(p.rel == rawget(_G, "TruePlayedWidget")),
      tostring(p.relPoint), N(p.x), N(p.y) }, " ")
  end
  local tl, tc = tt._lines, tt._colors
  for i = 1, #tl do
    local l, c = tl[i], tc[i] or {}
    lines[#lines + 1] = format("%q | %q | %s", tostring(l[1]), tostring(l[2]),
      Ns(c[1], c[2], c[3], c[4], c[5], c[6]))
  end
  return lines
end

---------------------------------------------------------------------------
-- Scenarios (identical calls on both trees; nothing here may touch ns.Themes)
---------------------------------------------------------------------------

local function SetRest(amount)
  Stub.player.rest = amount
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
end

local function Set(ns, path, value)
  ns.Core.SetSetting(path, value)
  Stub.Advance(1)
end

local function Tooltips(ns, out, label)
  local w = rawget(_G, "TruePlayedWidget")
  Stub.shift = false
  ns.Tooltip.ShowFor(w)
  out[#out + 1] = { label = label .. " tooltip short", lines = TooltipSnapshot() }
  ns.Tooltip.Hide(w)
  Stub.shift = true
  ns.Tooltip.ShowFor(w)
  out[#out + 1] = { label = label .. " tooltip shift", lines = TooltipSnapshot() }
  ns.Tooltip.Hide(w)
  Stub.shift = false
end

local SCENARIOS = {
  { name = "1. login defaults (unlocked first run)", play = function(ns, snap, out)
      snap("login")
      Tooltips(ns, out, "login")
      Stub.GrantXP(500)
      Stub.Advance(2)
      snap("after 500 xp")
    end },
  { name = "2. rested (xp 2000, rest 3000)", setup = function() Stub.player.xp, Stub.player.rest = 2000, 3000 end,
    play = function(ns, snap, out)
      Set(ns, "widget.locked", true)
      snap("rested")
      Tooltips(ns, out, "rested")
      SetRest(0)
      snap("rest spent")
      SetRest(3000)
      snap("rested again")
      Stub.Kill(120)
      Stub.Advance(2)
      snap("rested kill")
    end },
  { name = "3. rest larger than the rest of the level", setup = function() Stub.player.xp, Stub.player.rest = 2000, 20000 end,
    play = function(ns, snap)
      Set(ns, "widget.locked", true)
      snap("capped rest")
    end },
  { name = "4. max level", setup = function() Stub.player.level, Stub.player.max = 60, 0 end,
    play = function(ns, snap, out)
      Set(ns, "widget.locked", true)
      snap("max level")
      Tooltips(ns, out, "max level")
    end },
  { name = "5. server level cap", setup = function()
      local p = Stub.player
      p.level, p.xp, p.max, p.rest = 20, 58, Stub.xpTable[20], 4000
    end,
    play = function(ns, snap)
      Set(ns, "widget.locked", true)
      snap("before cap")
      Stub.party[1] = 22
      for _ = 1, 3 do
        Stub.KillNoXP({ level = 20 })
        Stub.Advance(30)
      end
      snap("server cap")
    end },
  { name = "6. box style", setup = function() Stub.player.xp, Stub.player.rest = 2000, 3000 end,
    play = function(ns, snap)
      Set(ns, "widget.locked", true)
      Set(ns, "widget.style", "box")
      snap("box rested")
      SetRest(0)
      Stub.GrantXP(1000)
      Stub.Advance(2)
      snap("box after xp")
      Set(ns, "widget.style", "bar")
      snap("back to bar")
    end },
  { name = "7. custom xp, rested and text colours", setup = function() Stub.player.xp = 2000 end,
    play = function(ns, snap)
      Set(ns, "widget.locked", true)
      Set(ns, "widget.xpColor", { 0.9, 0.3, 0.1 })
      Set(ns, "widget.restedColor", { 0.1, 0.7, 0.9 })
      Set(ns, "widget.textColor", { 1, 0.82, 0 })
      snap("custom colours")
      SetRest(3000)
      snap("custom colours rested")
      Set(ns, "widget.restedColor", { 0.2, 0.9, 0.3 })
      snap("rested colour changed while rested")
      Set(ns, "widget.xpColor", false)
      Set(ns, "widget.restedColor", false)
      Set(ns, "widget.textColor", false)
      snap("colours reset")
      SetRest(0)
      snap("colours reset, not rested")
    end },
  { name = "8. bgAlpha 0.5, thick outline, no shadow", setup = function() Stub.player.xp = 3000 end,
    play = function(ns, snap)
      Set(ns, "widget.locked", true)
      Set(ns, "widget.bgAlpha", 0.5)
      Set(ns, "widget.outline", "thick")
      Set(ns, "widget.shadow", false)
      snap("background 0.5")
      Set(ns, "widget.bgAlpha", 1)
      Set(ns, "widget.outline", "none")
      snap("background 1, no outline")
    end },
  { name = "9. pctPos level, width 150, fontSize 16", setup = function() Stub.player.xp = 2000 end,
    play = function(ns, snap)
      Set(ns, "widget.locked", true)
      Set(ns, "widget.pctPos", "level")
      Set(ns, "widget.width", 150)
      Set(ns, "widget.fontSize", 16)
      snap("narrow, big font")
      SetRest(3000)
      snap("narrow rested")
      Set(ns, "widget.slot3Pos", "left")
      Set(ns, "widget.height", 14)
      snap("slot 3 left, height 14")
    end },
  { name = "10. unlocked (veil and hint)", setup = function() Stub.player.xp = 1000 end,
    play = function(ns, snap)
      Set(ns, "widget.locked", true)
      snap("locked")
      Set(ns, "widget.locked", false)
      Set(ns, "widget.fade", true)
      snap("unlocked, faded")
      Stub.RunScript(rawget(_G, "TruePlayedWidget"), "OnEnter")
      snap("hovered")
      Stub.RunScript(rawget(_G, "TruePlayedWidget"), "OnLeave")
    end },
}

-- Plays a scenario on the tree at `root` and returns its stages and the errors reported.
local function Play(sc, root)
  local saveRoot = Stub.ROOT
  Stub.Reset()
  Stub.ROOT = root
  local out, errors = {}, {}
  local ok, err = pcall(function()
    Stub.InstallUI({ ldb = false })
    if sc.setup then sc.setup() end
    local ns = Stub.LoadAddon()
    Stub.LoginSequence({ settle = 3 })
    Stub.Advance(2)
    local function snap(label) out[#out + 1] = { label = label, lines = BarSnapshot() } end
    sc.play(ns, snap, out)
  end)
  Stub.ROOT = saveRoot
  for i = 1, #Stub.errors do errors[i] = (Stub.errors[i]:match("^[^\n]*")) end
  if not ok then errors[#errors + 1] = "raised: " .. tostring(err) end
  return out, errors
end

-- Readable difference of two stage lists (first differing stage).
local function Diff(a, b)
  for i = 1, math.max(#a, #b) do
    local sa, sb = a[i], b[i]
    if not sa or not sb or sa.label ~= sb.label then
      return format("stage %d: '%s' vs '%s'", i, sa and sa.label or "-", sb and sb.label or "-")
    end
    local setA, setB = {}, {}
    for _, l in ipairs(sa.lines) do setA[l] = (setA[l] or 0) + 1 end
    for _, l in ipairs(sb.lines) do setB[l] = (setB[l] or 0) + 1 end
    local onlyA, onlyB = {}, {}
    for l, n in pairs(setA) do if (setB[l] or 0) < n then onlyA[#onlyA + 1] = "  - " .. l end end
    for l, n in pairs(setB) do if (setA[l] or 0) < n then onlyB[#onlyB + 1] = "  + " .. l end end
    if #onlyA > 0 or #onlyB > 0 then
      sort(onlyA)
      sort(onlyB)
      return format("stage '%s' differs (- before themes, + actuel):\n%s\n%s", sa.label,
        concat(onlyA, "\n"), concat(onlyB, "\n"))
    end
    for k = 1, #sa.lines do
      if sa.lines[k] ~= sb.lines[k] then
        return format("stage '%s', line %d (order): %s vs %s", sa.label, k, sa.lines[k], tostring(sb.lines[k]))
      end
    end
  end
  return nil
end

for _, sc in ipairs(SCENARIOS) do
  T.test("golden actuel = before themes: " .. sc.name, function()
    if not HasBaseline() then T.skip("no Phase 0 baseline") end
    local root = Stub.ROOT
    local snapA, errA = Play(sc, root .. BASELINE)
    local snapB, errB = Play(sc, root)
    T.eq(errA, {}, "baseline run errors")
    T.eq(errB, {}, "current run errors")
    T.ok(#snapA > 0, "stages recorded")
    local diff = Diff(snapA, snapB)
    if diff then error(diff, 0) end
    T.eq(snapA, snapB)
  end)
end

T.test("golden: the snapshot sees what the bar draws (sanity of the harness)", function()
  if not HasBaseline() then T.skip("no Phase 0 baseline") end
  local stages = Play({ setup = function() Stub.player.xp, Stub.player.rest = 2000, 3000 end,
    play = function(_, snap) snap("rested") end }, Stub.ROOT .. BASELINE)
  local lines = concat(stages[1].lines, "\n")
  T.match(lines, "Widget |")
  T.match(lines, "Texture | BORDER | 0 | Interface\\Buttons\\WHITE8X8 |", "track")
  T.match(lines, "mask=Interface\\CHARACTERFRAME\\TempPortraitAlphaMask/CLAMPTOBLACKADDITIVE/CLAMPTOBLACKADDITIVE",
    "rounded ends")
  T.match(lines, "grad%(HORIZONTAL,0%.3500,0%.6200,1%.0000,0%.6500,0%.3500,0%.6200,1%.0000,0%.2000%)",
    "rested part gradient")
  T.match(lines, "FontString | OVERLAY | \"LEVEL 10\" | Fonts\\FRIZQT__%.TTF | 11%.0000 | OUTLINE")
  T.no(lines:find("BACKGROUND", 1, true), "measuring FontStrings (alpha 0) are left out")
end)
