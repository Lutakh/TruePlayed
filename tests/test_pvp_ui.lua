-- tests/test_pvp_ui.lua - PvP on the bar and in the UI (Bar.lua, BarSkin.lua, Tooltip.lua,
-- Tokens.lua, PvpOptions.lua): the PvP strip (honor: gold, orange from Pvp.WARN of the
-- cap, red at it; rank; none), stacked under the reputation's strip in every theme, the
-- hover regions split between the two strips, the detailed PvP tooltip (themed and
-- native: honor, rank, weekly cap, kills, battlegrounds, the pause, no season, Classic
-- Era), the main bar's PvP mode in every theme (the rank's colour on every fill layer, its
-- texts, the max rank dimmed, the honor before a season), the battleground override
-- that never writes widget.main, hideAtMax, the tick (no allocation, no read), the PvP
-- tokens, and the options' PvP page (controls, helps, reset, read-only, Classic Era's
-- note, the section of the single panel). The stub: tests/stub_pvp.lua (Forever's API
-- installed by Start; rank titles "Horde N" / "Alliance N").
local Stub, T = ...

local format, floor = string.format, math.floor

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }

-- Loads the addon (widget shown); opts: api, season (false: none), week, cap, total, q,
-- theme, ui, level, xp, rest, watched (a reputation), db, settings ({ path = value }).
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI(opts.ui or { ldb = false })
  if opts.theme then Stub.theme = opts.theme end
  Stub.SetPvpAPI(opts.api or "forever")
  local s = Stub.pvp
  if opts.season ~= false then Stub.SetWeek(opts.week or 2, opts.cap or 5, 3, { quiet = true }) end
  if opts.total then s.total = opts.total end
  if opts.q then s.q = opts.q end
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  Stub.rep.watched = opts.watched
  local p = Stub.player
  if opts.level then
    p.level = opts.level
    p.max = Stub.xpTable[opts.level] or p.max
  end
  p.xp = opts.xp or 2000
  if opts.rest ~= nil then p.rest = opts.rest end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  for k, v in pairs(opts.settings or {}) do ns.Core.SetSetting(k, v) end
  return ns, ns.Bar.frame, ns.Bar.frame and ns.Bar.frame.tp
end

local function Friendly()
  return { name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 }
end

local function Rgb(r, g, b)
  return { floor(r * 1000 + 0.5), floor(g * 1000 + 0.5), floor(b * 1000 + 0.5) }
end

local function Vertex(t)
  local r, g, b = t:GetVertexColor()
  return Rgb(r, g, b)
end

local function PvpRgb(ns, k)
  return Rgb(ns.Pvp.Color(k))
end

-- A strip as drawn (tp.rep or tp.pvp): nil when hidden, else { x, y, w, h, fill, color }.
local function Strip(tp, which)
  local st = tp[which or "pvp"]
  if not st or not st.bg:IsShown() then return nil end
  local _, _, _, x, y = st.bg:GetPoint(1)
  local fill = st.fill:IsShown() and st.fill:GetWidth() or 0
  local col = st.fill:IsShown() and Vertex(st.fill) or nil
  return { x = x, y = y, w = st.bg:GetWidth(), h = st.bg:GetHeight(), fill = fill, color = col }
end

local function Hit(h)
  if not h or not h:IsShown() then return nil end
  local _, _, _, x, y = h:GetPoint(1)
  return { x = x, y = y, w = h:GetWidth(), h = h:GetHeight() }
end

-- Rows of the themed tooltip: { left, right, kind, row }.
local function TipRows(ns)
  local tf = ns.TooltipFrame.frame
  local out = {}
  for i = 1, tf.tp.n do
    local row = tf.tp.rows[i]
    if row.left:IsShown() then
      out[#out + 1] = { left = row.left:GetText(), right = row.right:IsShown() and row.right:GetText() or nil,
                        kind = row.kind, row = row }
    end
  end
  return out
end

local function FindRow(rows, left)
  for _, r in ipairs(rows) do
    if r.left == left then return r end
  end
  return nil
end

local function CountMsg(ns, msg)
  local box = { n = 0 }
  ns.RegisterMessage(msg, box, function() box.n = box.n + 1 end)
  return box
end

---------------------------------------------------------------------------
-- The strip
---------------------------------------------------------------------------

T.test("pvp strip: the honor (gold, orange from 90 %, red at the cap), the rank, none", function()
  local ns, f, tp = Start({ theme = "futuriste", total = 1000 })
  T.eq(Strip(tp), nil, "off by default")
  local h0 = select(2, f:GetSize())
  ns.Core.SetSetting("widget.pvp", "honor")
  local s = Strip(tp)
  T.ok(s ~= nil, "shown")
  T.eq(s.fill, floor(s.w * 1024 / 25000 + 0.5))
  T.eq(s.color, PvpRgb(ns, ns.Pvp.KEY_HONOR))
  T.ok(select(2, f:GetSize()) > h0, "the frame grows")
  Stub.GainHonor(22000)                            -- 23024: 92 %
  s = Strip(tp)
  T.eq(s.color, PvpRgb(ns, ns.Pvp.KEY_WARN), "orange from 90 %")
  T.eq(s.fill, floor(s.w * 23024 / 25000 + 0.5))
  Stub.GainHonor(5000)
  s = Strip(tp)
  T.eq({ s.fill, s.color }, { s.w, PvpRgb(ns, ns.Pvp.KEY_CAP) }, "full and red at the cap")
  ns.Core.SetSetting("widget.pvp", "rank")
  s = Strip(tp)
  T.eq({ s.fill, s.color }, { floor(s.w * 250 / 900 + 0.5), PvpRgb(ns, ns.Pvp.KEY_RANK) }, "250 of 900")
  ns.Core.SetSetting("widget.pvp", "off")
  T.eq(Strip(tp), nil)
  T.eq(select(2, f:GetSize()), h0, "the frame as before")
  T.eq(Stub.errors, {})
end)

T.test("pvp strip, every theme: under the reputation's strip (1 px gap, same size), the hover regions split", function()
  for _, key in ipairs(KEYS) do
    Stub.Reset()
    local ns, f, tp = Start({ theme = key, watched = Friendly() })
    local r0 = Strip(tp, "rep")
    T.ok(r0 ~= nil, key .. ": the reputation's strip")
    local h0 = select(2, f:GetSize())
    ns.Core.SetSetting("widget.pvp", "honor")
    local r, p = Strip(tp, "rep"), Strip(tp, "pvp")
    local dy = select(2, f:GetSize()) - h0         -- the frame grew below: everything moved up
    T.eq({ r.x, r.y - dy, r.w, r.h, r.fill }, { r0.x, r0.y, r0.w, r0.h, r0.fill },
      key .. ": the reputation's strip in place under the track")
    T.ok(p ~= nil, key .. ": the PvP strip")
    T.eq({ p.x, p.w, p.h }, { r.x, r.w, r.h }, key .. ": same x, width, height")
    T.eq(p.y, r.y - 1 - r.h, key .. ": 1 px under it")
    T.ok(select(2, f:GetSize()) - h0 <= r.h + 1, key .. ": the frame grows by what it needs")
    local _, _, _, _, rowY = tp.slots[2]:GetPoint(1)
    T.ok(p.y >= rowY, key .. ": above the text row")
    -- the regions: the reputation's over its strip, PvP's below, not overlapping
    local rh, ph = Hit(tp.repHit), Hit(tp.pvpHit)
    T.ok(rh ~= nil and ph ~= nil, key .. ": both regions")
    T.ok(rh.y <= r.y and rh.y + rh.h >= r.y + r.h, key .. ": the reputation's covers its strip")
    T.ok(ph.y <= p.y and ph.y + ph.h >= p.y + p.h, key .. ": PvP's covers its strip")
    T.ok(ph.y + ph.h <= rh.y + 0.001, key .. ": no overlap")
    -- the PvP strip alone: in the reputation's place
    ns.Core.SetSetting("widget.rep", false)
    p = Strip(tp, "pvp")
    dy = select(2, f:GetSize()) - h0
    T.eq({ p.x, p.y - dy, p.w, p.h }, { r0.x, r0.y, r0.w, r0.h }, key .. ": in its place")
    T.eq(select(2, f:GetSize()), h0, key .. ": the frame as with the reputation's strip alone")
    T.eq(Hit(tp.repHit), nil)
    T.ok(Hit(tp.pvpHit) ~= nil)
    T.eq(Stub.errors, {}, key)
  end
end)

T.test("pvp strip: the XP strip of the reputation's main bar, then the PvP strip; dragging and clicks", function()
  local ns, f, tp = Start({ theme = "warrior", watched = Friendly(), settings = { ["widget.main"] = "rep",
                                                                                   ["widget.pvp"] = "rank" } })
  local x, p = Strip(tp, "rep"), Strip(tp, "pvp")
  T.ok(x ~= nil and p ~= nil, "the XP strip and the PvP strip")
  T.eq(p.y, x.y - 1 - x.h)
  local ph = Hit(tp.pvpHit)
  T.ok(ph.y + ph.h <= x.y + 0.001, "the XP strip keeps the general tooltip")
  Stub.RunScript(tp.pvpHit, "OnEnter")
  T.ok(ns.Tooltip.IsShownFor(tp.pvpHit))
  local rows = TipRows(ns)
  T.ok(FindRow(rows, ns.L.TT_SECTION_PVP) ~= nil, "the PvP tooltip")
  T.eq(FindRow(rows, ns.L.TT_SECTION_REP), nil)
  Stub.RunScript(tp.pvpHit, "OnMouseUp", "LeftButton")
  T.ok(ns.Window.IsShown(), "a click: the statistics window")
  ns.Window.Hide()
  Stub.RunScript(tp.pvpHit, "OnMouseDown", "LeftButton")
  Stub.RunScript(tp.pvpHit, "OnDragStart")
  T.eq(rawget(f, "_moving"), true, "drags the bar")
  T.no(ns.Tooltip.IsShownFor(tp.pvpHit))
  Stub.RunScript(tp.pvpHit, "OnDragStop")
  Stub.RunScript(tp.pvpHit, "OnMouseUp", "LeftButton")
  Stub.RunScript(tp.pvpHit, "OnLeave")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- The detailed tooltip
---------------------------------------------------------------------------

T.test("pvp tooltip (themed): honor, rank and title, the weekly cap, kills, battlegrounds, the hint", function()
  local ns, _, tp = Start({ theme = "futuriste", total = 1000, settings = { ["widget.pvp"] = "honor" } })
  local L, Fmt = ns.L, ns.Fmt
  Stub.RunScript(tp.pvpHit, "OnEnter")
  Stub.Advance(1)
  local rows = TipRows(ns)
  T.eq(rows[1].left, L.ADDON_TITLE)
  T.eq(FindRow(rows, L.TT_SECTION_PVP).kind, "section")
  T.eq(FindRow(rows, L.TT_PVP_HONOR).kind, "header")
  T.eq(FindRow(rows, L.TT_PVP_AMOUNT).right, "1,024 / 25,000 (4.1%)")
  T.eq(FindRow(rows, L.TT_PVP_HONORH).right, L.TT_PVP_NODATA)
  T.eq(FindRow(rows, L.TT_PVP_CAP_IN).right, L.TT_NO_RATE)
  T.eq(FindRow(rows, L.TT_PVP_RANK).kind, "header")
  local title = FindRow(rows, "Rank 1 · Horde 1")
  T.ok(title ~= nil, "the rank and the game's title")
  T.eq(Rgb(title.row.left:GetTextColor()), PvpRgb(ns, ns.Pvp.KEY_RANK))
  T.eq(FindRow(rows, L.TT_PVP_RANK_PTS).right, "250 / 900 (27.8%)")
  T.eq(FindRow(rows, L.TT_PVP_SEASON_TOTAL).right, "1,000")
  T.eq(FindRow(rows, format(L.TT_PVP_WEEK_CAP_FMT, 2)).right, format(L.TT_PVP_WEEK_CAP_VAL_FMT, 5, "5,250"))
  T.eq(FindRow(rows, L.TT_PVP_WEEK_LEFT).right, "4,250")
  T.eq(FindRow(rows, format(L.TT_PVP_NEXT_FMT, 2)).right, L.TT_NO_RATE)
  T.eq(FindRow(rows, L.TT_PVP_HK).kind, "header")
  T.eq(FindRow(rows, L.TT_PVP_TODAY).right, "0")
  T.eq(FindRow(rows, L.TT_PVP_THIS_SESSION).right, "0")
  T.eq(FindRow(rows, L.TT_PVP_LIFETIME).right, "87")
  T.eq(FindRow(rows, L.TT_PVP_HIGHEST), nil, "never ranked: no highest rank")
  T.ok(FindRow(rows, L.TT_PVP_BG_NONE) ~= nil)
  T.eq(FindRow(rows, L.TT_PVP_SEASON_END), nil, "the season's end unknown")
  T.eq(rows[#rows].left, L.TT_REP_HINT)
  -- a battleground with gains: the rates, the one in progress, then its record
  Stub.EnterBG()
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainHonor(100)
    Stub.GainRankPoints(25)
    Stub.HK(1)
  end
  Stub.pvp.seasonEnd = 86400 * 20
  Stub.Advance(1)
  rows = TipRows(ns)
  local v = ns.Pvp.Rate("honor", 0)
  T.eq(FindRow(rows, L.TT_PVP_HONORH).right, Fmt.Rate(v))
  T.eq(FindRow(rows, L.TT_PVP_SESSION).right, format(L.TT_REP_GAIN_FMT, "1,200"))
  T.ok(FindRow(rows, L.TT_PVP_BG_NOW) ~= nil, "one in progress")
  T.eq(FindRow(rows, L.TT_PVP_TODAY).right, "12")
  T.eq(FindRow(rows, L.TT_PVP_THIS_SESSION).right, "12")
  T.eq(FindRow(rows, L.TT_PVP_SEASON_END).right, ns.Fmt.Duration(86400 * 20))
  local eta = ns.Pvp.RankEta(0)
  T.eq(FindRow(rows, format(L.TT_PVP_NEXT_FMT, 2)).right, Fmt.ETA(eta))
  Stub.MatchComplete(0, 720)
  Stub.LeaveBG()
  Stub.Advance(1)
  rows = TipRows(ns)
  T.eq(FindRow(rows, L.TT_PVP_BG_COUNT).right, "1")
  T.eq(FindRow(rows, L.TT_PVP_BG_RECORD).right, format(L.TT_PVP_WL_FMT, 1, 0))
  T.eq(FindRow(rows, L.TT_PVP_BG_HONOR).right, "1,200")
  T.eq(FindRow(rows, L.TT_PVP_BG_DUR).right, ns.Fmt.Duration(720))
  -- paused out of the battleground, 15 min after the last gain
  Stub.Advance(ns.C.PVP_IDLE + 10)
  rows = TipRows(ns)
  T.match(FindRow(rows, L.TT_PVP_HONORH).right, "%*$")
  T.ok(FindRow(rows, format(L.TT_PVP_PAUSED_FMT, L.STALL_MARK, ns.Fmt.Duration(ns.C.PVP_IDLE))) ~= nil,
    "why it is paused")
  Stub.RunScript(tp.pvpHit, "OnLeave")
  T.no(ns.Tooltip.IsShownFor(tp.pvpHit))
  T.eq(Stub.errors, {})
end)

T.test("pvp tooltip: at the cap, blocked by the weekly cap, the max rank, no season, the titles", function()
  local ns, _, tp = Start({ theme = "druid", cap = 3, total = 2600, q = 24990,
                            settings = { ["widget.pvp"] = "rank", ["pvp.capAlert"] = false } })
  local L = ns.L
  Stub.GainHonor(10)
  Stub.GainRankPoints(500)                         -- held at 2700: the week's cap
  Stub.Advance(30)
  Stub.RunScript(tp.pvpHit, "OnEnter")
  Stub.Advance(1)
  local rows = TipRows(ns)
  local at = FindRow(rows, format(L.TT_PVP_AT_CAP_FMT, ns.Fmt.Duration(31)))
  T.ok(at ~= nil, "at the cap for 31 s")
  T.eq(Rgb(at.row.left:GetTextColor()), PvpRgb(ns, ns.Pvp.KEY_CAP), "in red")
  T.eq(FindRow(rows, L.TT_PVP_CAP_IN), nil)
  T.ok(FindRow(rows, L.PVP_WEEK_CAPPED) ~= nil, "the week's cap reached")
  T.eq(FindRow(rows, format(L.TT_PVP_NEXT_FMT, 4)).right, L.PVP_BLOCKED)
  T.ok(FindRow(rows, format(L.TT_PVP_UNLOCK_FMT, ns.Fmt.Duration(3 * 86400))) ~= nil, "until the weekly reset")
  T.eq(FindRow(rows, L.TT_PVP_WEEK_LEFT), nil)
  -- no weekly reset known
  rawset(_G, "C_DateAndTime", nil)
  Stub.Advance(1)
  T.ok(FindRow(TipRows(ns), L.TT_PVP_UNLOCK) ~= nil)
  -- the highest rank ever (PvPRanks 5 + rank - 1) and a female title
  Stub.pvp.hkHigh = 7
  Stub.rep.sex = 3
  Stub.HK(1)
  Stub.Advance(1)
  rows = TipRows(ns)
  T.eq(FindRow(rows, L.TT_PVP_HIGHEST).right, "Horde 3 (f)")
  T.ok(FindRow(rows, "Rank 3 · Horde 3 (f)") ~= nil, "the _FEMALE title")
  Stub.rep.sex = 2
  Stub.player.faction = "Alliance"
  Stub.Advance(1)
  T.ok(FindRow(TipRows(ns), "Rank 3 · Alliance 3") ~= nil, "the Alliance's title")
  Stub.SetPvpTitles(false)
  Stub.Advance(1)
  rows = TipRows(ns)
  T.ok(FindRow(rows, "Rank 3") ~= nil, "no title: the number alone")
  T.eq(FindRow(rows, L.TT_PVP_HIGHEST).right, format(L.PVP_RANK_FMT, 3))
  -- the max rank
  Stub.SetWeek(10, 14, 13, { quiet = true })
  Stub.GainRankPoints(30000)
  Stub.Advance(1)
  rows = TipRows(ns)
  T.eq(FindRow(rows, L.TT_PVP_RANK_PTS).right, L.PVP_RANK_MAX)
  T.eq(FindRow(rows, format(L.TT_PVP_NEXT_FMT, 15)), nil, "no next rank")
  -- no season
  Stub.SetWeek(-1, 0, 0, { quiet = true })
  Stub.pvp.total = 0
  Stub.Fire("UPDATE_FACTION")
  Stub.Advance(1)
  rows = TipRows(ns)
  T.ok(FindRow(rows, L.PVP_NO_SEASON) ~= nil)
  T.eq(FindRow(rows, L.TT_PVP_RANK_PTS), nil)
  Stub.RunScript(tp.pvpHit, "OnLeave")
  T.eq(Stub.errors, {})
end)

T.test("pvp tooltip: the native one (GameTooltip), no data, Classic Era's note", function()
  local ns, _, tp = Start({ theme = "actuel", settings = { ["widget.pvp"] = "honor" } })
  local L = ns.L
  Stub.RunScript(tp.pvpHit, "OnEnter")
  Stub.Advance(1)
  local function Has(lines, left, right)
    for _, l in ipairs(lines) do
      if l[1] == left and (right == nil or l[2] == right) then return l end
    end
    return nil
  end
  local lines = GameTooltip._lines
  T.ok(Has(lines, L.ADDON_TITLE) ~= nil)
  T.ok(Has(lines, L.TT_SECTION_PVP) ~= nil)
  T.ok(Has(lines, L.TT_PVP_AMOUNT, "1,024 / 25,000 (4.1%)") ~= nil)
  T.ok(Has(lines, L.TT_PVP_LIFETIME, "87") ~= nil)
  T.eq(lines[#lines][1], L.TT_REP_HINT)
  Stub.RunScript(tp.pvpHit, "OnLeave")
  -- nothing readable
  Stub.pvp.secret.info = true
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  Stub.Fire("UPDATE_FACTION")
  local tt = Stub.NewTooltip()
  ns.Tooltip.FillPvp(tt)
  T.ok(Has(tt._lines, L.TT_PVP_NONE) ~= nil, "no PvP data yet")
  T.no(tp.pvpHit:IsShown(), "no strip without data")
  -- Classic Era: the note
  Stub.Reset()
  local ns2 = Start({ api = "era" })
  tt = Stub.NewTooltip()
  ns2.Tooltip.FillPvp(tt)
  T.ok(Has(tt._lines, L.OPT_PVP_UNAVAILABLE) ~= nil, "not available on this client")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- The main bar's PvP mode
---------------------------------------------------------------------------

-- The fill layers: { shown, width } each, and with `colors` their colours too (the vertex
-- colour and the first gradient stop).
local function FillLook(ns, tp, colors)
  local out = {}
  for _, L in ipairs(ns.Themes.Active().bar.layers) do
    local t = tp.tex[L.id] or tp.tex[L.id .. "M"]
    if type(t) == "table" and not t.GetWidth then t = t[1] end
    if (L.span == "fill" or L.span == "fillEnd") and type(t) == "table" and t.GetWidth then
      out[L.id] = { t:IsShown(), t:IsShown() and t:GetWidth() or 0 }
      if colors then
        local grad = rawget(t, "_grad")
        out[L.id][3] = Vertex(t)
        out[L.id][4] = grad and Rgb(grad[2] or 0, grad[3] or 0, grad[4] or 0) or false
      end
    end
  end
  return out
end

T.test("pvp main mode, every theme: the rank on the track, its colour, its texts, the XP in the strip", function()
  for _, key in ipairs(KEYS) do
    Stub.Reset()
    local max = Stub.xpTable[Stub.player.level]
    -- the XP at a third of the level, as the rank (350 / 1,050): the same fill
    local ns, _, tp = Start({ theme = key, total = 2000, xp = max / 3, rest = 0 })
    local L, Skin = ns.L, ns.BarSkin
    local th = ns.Themes.Active()
    local xpLook = FillLook(ns, tp)
    local xpTexts = { tp.bl:GetText(), tp.brx:GetText(), tp.marker:GetText() }
    local themeMsgs = CountMsg(ns, "THEME_CHANGED")
    ns.Core.SetSetting("widget.main", "pvp")
    T.eq(FillLook(ns, tp), xpLook, key .. ": a third drawn alike")
    local pvpLook = FillLook(ns, tp, true)
    if key == "actuel" or key == "futuriste" then
      T.eq(Vertex(tp.tex.fill or tp.tex.fillM), PvpRgb(ns, ns.Pvp.KEY_RANK), key .. ": the rank's colour")
    end
    T.eq(themeMsgs.n, 0, key .. ": no THEME_CHANGED")
    if th.text.split then
      T.eq(tp.bl:GetText(), Skin.Sub("xp", "Rank 2"), key .. ": the rank")
      T.eq(tp.blv:GetText(), Skin.Sub("levelValue", "Horde 2"), key .. ": its title")
      T.eq(tp.xpl:GetText(), Skin.Sub("xpLabel", L.PVP_LABEL), key .. ": the PvP label")
    else
      T.eq(tp.bl:GetText(), Skin.Sub("xp", "Rank 2 · Horde 2"), key .. ": rank · title")
    end
    local brx = tp.brx:GetText()
    T.ok(tp.brx:IsShown() and (brx == Skin.Sub("xp", "350 / 1,050") or brx == Skin.Sub("xp", "350 / 1.1k")),
      key .. ": the points before a rate " .. tostring(brx))
    T.eq(tp.marker:GetText(), Skin.Sub("marker", "33.3%"), key .. ": the % marker")
    local s = Strip(tp, "rep")
    T.ok(s ~= nil, key .. ": the XP strip")
    T.eq(s.fill, floor(s.w / 3 + 0.5), key .. ": a third of XP")
    local hit = Hit(tp.pvpHit)
    T.ok(hit ~= nil and hit.h >= 1, key .. ": the main track's region")
    ns.Core.SetSetting("widget.main", "xp")
    T.eq(FillLook(ns, tp), xpLook, key .. ": the XP again")
    T.eq({ tp.bl:GetText(), tp.brx:GetText(), tp.marker:GetText() }, xpTexts, key .. ": the XP texts again")
    T.eq(Hit(tp.pvpHit), nil, key .. ": no region")
    -- every fill layer exactly as the XP mode draws it with the rank's colour as the XP
    -- colour (the theme's own expressions of `base`, every layer and gradient stop)
    local cr, cg, cb = ns.Pvp.Color(ns.Pvp.KEY_RANK)
    ns.Core.SetSetting("widget.xpColor", { cr, cg, cb })
    T.eq(pvpLook, FillLook(ns, tp, true), key .. ": every fill layer in the rank's colour")
    ns.Core.SetSetting("widget.xpColor", false)
    T.eq(Stub.errors, {}, key)
  end
end)

T.test("pvp main mode: the rate texts, refreshed by the tick; the next rank as the week's cap; the max rank", function()
  local ns, f, tp = Start({ theme = "futuriste", cap = 3, total = 2000, settings = { ["widget.main"] = "pvp" } })
  local L, Skin = ns.L, ns.BarSkin
  Stub.EnterBG()
  for _ = 1, 4 do
    Stub.Advance(60)
    Stub.GainRankPoints(30)
  end
  Stub.Advance(1)
  local t1, t2, t3 = ns.Pvp.MainRight(0)
  T.ok(t1 ~= nil, "a rate")
  local brx = tp.brx:GetText()
  T.ok(brx == Skin.Sub("xp", t1) or brx == Skin.Sub("xp", t2) or brx == Skin.Sub("xp", t3), tostring(brx))
  T.match(t1, "^" .. ns.Fmt.Rate(ns.Pvp.Rate("rank", 0)):gsub("%p", "%%%0"))
  T.ok(t1:find(format(L.PVP_NEXT_CAP_FMT, 3, ""), 1, true) ~= nil, "rank 3 is this week's cap: said")
  -- the tick redraws the right texts only when they change (the rate moves a lot while it
  -- warms up), and reads nothing
  local reads = Stub.pvp.calls.GetProgression + Stub.pvp.calls.GetCurrencyInfo
  local seen, versions = {}, 0
  local sets = 0
  local brxSet = tp.brx.SetText
  tp.brx.SetText = function(self, ...)
    sets = sets + 1
    return brxSet(self, ...)
  end
  for _ = 1, 120 do
    Stub.Advance(1)
    local _, _, _, ver = ns.Pvp.MainRight(0)
    if not seen[ver] then seen[ver], versions = true, versions + 1 end
  end
  tp.brx.SetText = nil
  T.ok(sets <= 2 * versions, format("%d text sets for %d versions", sets, versions))
  T.eq(Stub.pvp.calls.GetProgression + Stub.pvp.calls.GetCurrencyInfo, reads, "no read on TICK")
  -- steady (paused out of the battleground): nothing allocated, no OnUpdate
  Stub.LeaveBG()
  Stub.Advance(ns.C.PVP_IDLE + 30)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 2, format("PvP main bar: %.2f KB over 600 ticks", kb))
  T.eq(Stub.onUpdateCount, 0)
  T.match(tp.brx:GetText(), "%*", "paused: the mark")
  -- the week's cap reached
  Stub.EnterBG()
  Stub.GainRankPoints(5000)
  T.eq(tp.brx:GetText(), Skin.Sub("xp", L.PVP_WEEK_CAPPED))
  T.eq(tp.bl:GetText(), Skin.Sub("xp", "Rank 3"))
  T.eq(tp.blv:GetText(), Skin.Sub("levelValue", "Horde 3"))
  -- the max rank: full, dimmed, "Max rank"
  Stub.SetWeek(10, 14, 13)
  Stub.GainRankPoints(30000)
  T.eq(tp.tex.fill:GetWidth(), tp.tex.track:GetWidth(), "full")
  local _, _, _, a = tp.tex.fill:GetVertexColor()
  T.near(a, ns.Themes.Active().bar.maxAlpha, 1e-6, "dimmed")
  T.eq(tp.brx:GetText(), Skin.Sub("xp", L.PVP_RANK_MAX))
  T.no(tp.marker:IsShown(), "no % marker")
  -- back to the XP: the theme's colour
  ns.Core.SetSetting("widget.main", "xp")
  T.match(tp.bl:GetText(), "LEVEL")
  T.ok(f:IsShown())
  T.eq(Stub.errors, {})
end)

T.test("pvp main mode: no season shows the honor toward its cap (gold, red and full at the cap, not dimmed)", function()
  local ns, _, tp = Start({ theme = "futuriste", season = false, settings = { ["widget.main"] = "pvp",
                                                                             ["pvp.capAlert"] = false } })
  local L, Skin = ns.L, ns.BarSkin
  T.eq(Vertex(tp.tex.fill), PvpRgb(ns, ns.Pvp.KEY_HONOR))
  T.eq(tp.bl:GetText(), Skin.Sub("xp", L.TT_PVP_HONOR))
  T.eq(tp.blv:GetText(), Skin.Sub("levelValue", L.PVP_NO_SEASON))
  local brx = tp.brx:GetText()
  T.ok(brx == Skin.Sub("xp", "1,024 / 25,000") or brx == Skin.Sub("xp", "1k / 25k"), tostring(brx))
  Stub.GainHonor(30000)
  T.eq(Vertex(tp.tex.fill), PvpRgb(ns, ns.Pvp.KEY_CAP), "red at the cap")
  T.eq(tp.tex.fill:GetWidth(), tp.tex.track:GetWidth())
  local _, _, _, a = tp.tex.fill:GetVertexColor()
  T.ok(a > ns.Themes.Active().bar.maxAlpha + 0.01, "not dimmed: act on it")
  -- no cap either: the XP
  Stub.pvp.max = 0
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.match(tp.bl:GetText(), "LEVEL")
  T.eq(ns.settings.widget.main, "pvp", "the setting kept")
  T.eq(Stub.errors, {})
end)

T.test("pvp main mode: the battleground override never writes widget.main; leaving goes back to the choice", function()
  local ns, _, tp = Start({ theme = "futuriste", total = 2000, watched = Friendly(),
                            settings = { ["widget.pvpAuto"] = true } })
  local Skin = ns.BarSkin
  local w = ns.settings.widget
  T.match(tp.bl:GetText(), "LEVEL")
  Stub.EnterBG({ loading = true })
  T.eq(tp.bl:GetText(), Skin.Sub("xp", "Rank 2"), "PvP in the battleground")
  T.eq(w.main, "xp", "widget.main untouched")
  Stub.LeaveBG({ loading = true })
  T.match(tp.bl:GetText(), "LEVEL", "the XP again")
  -- from the reputation's mode
  ns.Core.SetSetting("widget.main", "rep")
  Stub.EnterBG()
  T.eq(tp.bl:GetText(), Skin.Sub("xp", "Rank 2"))
  Stub.LeaveBG()
  T.eq(tp.bl:GetText(), Skin.Sub("xp", "Darnassus"), "the reputation again")
  T.eq(w.main, "rep")
  -- already PvP: leaving changes nothing
  ns.Core.SetSetting("widget.main", "pvp")
  Stub.EnterBG()
  Stub.LeaveBG()
  T.eq(tp.bl:GetText(), Skin.Sub("xp", "Rank 2"))
  -- an arena: no override
  ns.Core.SetSetting("widget.main", "xp")
  Stub.EnterBG({ arena = true })
  T.match(tp.bl:GetText(), "LEVEL")
  Stub.LeaveBG()
  -- the option off
  ns.Core.SetSetting("widget.pvpAuto", false)
  Stub.EnterBG()
  T.match(tp.bl:GetText(), "LEVEL")
  -- turned on inside: at once
  ns.Core.SetSetting("widget.pvpAuto", true)
  T.eq(tp.bl:GetText(), Skin.Sub("xp", "Rank 2"))
  T.eq(w.main, "xp")
  T.eq(Stub.errors, {})
end)

T.test("pvp main mode: never hidden by hideAtMax while it shows PvP (chosen or in a battleground)", function()
  local ns, f = Start({ theme = "druid", total = 2000, level = 60,
                        settings = { ["widget.hideAtMax"] = true, ["widget.pvpAuto"] = true } })
  T.ok(ns.Tracker.IsMax())
  T.no(f:IsShown(), "the XP mode hides it at max level")
  Stub.EnterBG()
  T.ok(f:IsShown(), "shown in a battleground")
  Stub.LeaveBG()
  T.no(f:IsShown())
  ns.Core.SetSetting("widget.main", "pvp")
  T.ok(f:IsShown(), "shown: it shows PvP")
  T.eq(Strip(f.tp, "rep"), nil, "no XP strip at max level")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Tokens
---------------------------------------------------------------------------

T.test("pvp tokens: honor, its rate and cap time, the rank, its rate and next rank, kills today", function()
  local ns = Start({ total = 1000, settings = { ["widget.slots.1"] = "rank_h" } })   -- a PvP token shown
  local Tokens, L, Fmt = ns.Tokens, ns.L, ns.Fmt
  Tokens.Acquire("test", 3)
  local function R(id)
    local text, dim = Tokens.Render(id)
    return text, dim
  end
  T.eq({ R("honor") }, { format(L.PFX_HONOR_FMT, "1,024", "25,000"), false })
  T.eq({ R("honor_h") }, { L.DOTS, true }, "no rate yet")
  T.eq({ R("honor_eta") }, { L.DOTS, true })
  T.eq({ R("rank") }, { format(L.PFX_RANK_FMT, 1, "250", "900"), false })
  T.eq({ R("rank_h") }, { L.DOTS, true })
  T.eq({ R("rank_eta") }, { L.DOTS, true })
  T.eq({ R("hk_today") }, { format(L.PFX_HK_FMT, "0"), false })
  Stub.EnterBG()
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainHonor(100)
    Stub.GainRankPoints(25)
    Stub.HK(2)
  end
  Tokens.UpdateContext()
  local hv = ns.Pvp.Rate("honor", 0)
  T.eq({ R("honor_h") }, { format(L.PFX_HONORH_FMT, Fmt.Rate(hv)), false })
  local eta = ns.Pvp.HonorEta(0)
  T.eq({ R("honor_eta") }, { format(L.HONOR_ETA_FMT, Fmt.ETA(eta)), false })
  local rv = ns.Pvp.Rate("rank", 0)
  T.eq({ R("rank_h") }, { format(L.PFX_RANKH_FMT, Fmt.Rate(rv)), false })
  local reta = ns.Pvp.RankEta(0)
  T.eq({ R("rank_eta") }, { format(L.RANK_ETA_FMT, 2, Fmt.ETA(reta)), false })
  T.eq({ R("hk_today") }, { format(L.PFX_HK_FMT, "24"), false })
  -- paused: dimmed with the mark
  Stub.LeaveBG()
  Stub.Advance(ns.C.PVP_IDLE + 5)
  Tokens.UpdateContext()
  local text, dim = R("honor_h")
  T.match(text, "%*$")
  T.ok(dim)
  -- the cap: "Honor capped", not dimmed
  Stub.GainHonor(30000)
  Tokens.UpdateContext()
  T.eq({ R("honor_eta") }, { L.PVP_AT_CAP, false })
  -- the week's cap, the max rank, no season
  Stub.SetWeek(2, 1, 0)                            -- cap rank 1: reached
  Tokens.UpdateContext()
  T.eq({ R("rank_eta") }, { L.PVP_WEEK_CAPPED_SHORT, true })
  Stub.SetWeek(10, 14, 13, { quiet = true })
  Stub.GainRankPoints(30000)
  Tokens.UpdateContext()
  T.eq({ R("rank") }, { format(L.PVP_RANK_FMT, 14), false })
  T.eq({ R("rank_eta") }, { L.PVP_RANK_MAX, true })
  Stub.SetWeek(-1, 0, 0, { quiet = true })
  Stub.pvp.total = 0
  Stub.Fire("UPDATE_FACTION")
  Tokens.UpdateContext()
  T.eq({ R("rank") }, { L.PVP_NO_SEASON_SHORT, true })
  T.eq({ R("rank_eta") }, { L.PVP_NO_SEASON_SHORT, true })
  T.eq({ R("rank_h") }, { L.DOTS, true })
  -- not XP tokens: they stay at max level
  for _, id in ipairs({ "honor", "honor_h", "honor_eta", "rank", "rank_h", "rank_eta", "hk_today" }) do
    T.eq(Tokens.DEF[id].xp, false, id)
  end
  T.eq(Stub.errors, {})
end)

T.test("pvp tokens on Classic Era: dots, and not offered by the options", function()
  local ns = Start({ api = "era", ui = { modern = true } })
  local Tokens, L = ns.Tokens, ns.L
  Tokens.Acquire("test", 3)
  for _, id in ipairs({ "honor", "honor_h", "honor_eta", "rank", "rank_h", "rank_eta", "hk_today" }) do
    local text, dim = Tokens.Render(id)
    T.eq({ text, dim }, { L.DOTS, true }, id)
    T.ok(Tokens.DEF[id].pvp, id .. ": marked")
  end
  ns.Options.Open()
  local controls = rawget(Stub.ui.categories[1].frame, "controls")
  local values = {}
  for _, ch in ipairs(controls["widget.slots.1"].choices) do values[ch.value] = true end
  T.no(values.honor, "not offered")
  T.ok(values.reph, "the others are")
  Stub.ui.CloseSettings()
  -- Forever: offered
  Stub.Reset()
  ns = Start({ ui = { modern = true } })
  ns.Options.Open()
  controls = rawget(Stub.ui.categories[1].frame, "controls")
  values = {}
  for _, ch in ipairs(controls["widget.slots.1"].choices) do values[ch.value] = true end
  T.ok(values.honor and values.hk_today, "offered on Forever")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- The options' PvP page
---------------------------------------------------------------------------

local function Page()
  local sub = Stub.ui.subcategories[2]
  Settings.OpenToCategory(sub.ID)
  return rawget(sub.frame, "controls"), sub
end

local function Lines(rec)
  Stub.RunScript(rec.widget, "OnEnter")
  local out = {}
  for i, l in ipairs(GameTooltip._lines) do out[i] = l[1] end
  Stub.RunScript(rec.widget, "OnLeave")
  return out
end

T.test("options: the PvP page (second subcategory), its controls, helps, the reset, read-only", function()
  local ns, f = Start({ theme = "futuriste", ui = { modern = true }, total = 1000 })
  local L = ns.L
  ns.Options.Open()
  local page, sub = Page()
  T.eq(sub.name, L.OPT_PVP_PAGE)
  T.eq(Stub.ui.subcategories[1].name, L.OPT_REP_PAGE, "after the reputation's")
  T.ok(ns.Options.IsShown(), "counts as the options shown")
  local kinds = {}
  for path, rec in pairs(page) do kinds[path] = rec.kind end
  T.eq(kinds, { ["widget.pvp"] = "dropdown", ["help.pvpStrip"] = "help", ["widget.main"] = "dropdown",
                ["help.pvpMain"] = "help", ["widget.pvpAuto"] = "check", ["help.pvpAuto"] = "help",
                ["pvp.capAlert"] = "check", ["help.pvpAlert"] = "help", ["pvp.resetRate"] = "button",
                ["help.pvpReset"] = "help" })
  T.ok(page["widget.pvp"].index < page["widget.main"].index and page["widget.main"].index < page["widget.pvpAuto"].index
       and page["widget.pvpAuto"].index < page["pvp.capAlert"].index
       and page["pvp.capAlert"].index < page["pvp.resetRate"].index, "in this order")
  -- the strip
  local dd = page["widget.pvp"]
  local values = {}
  for i, ch in ipairs(dd.choices) do values[i] = ch.value end
  T.eq(values, { "off", "honor", "rank" })
  Stub.ui.ClickMenuItem(Stub.ui.FindMenuItem(dd.widget._root, L.PVP_STRIP_HONOR))
  T.eq(ns.settings.widget.pvp, "honor")
  T.ok(f.tp.pvp.bg:IsShown(), "the bar follows")
  -- the main bar: the same setting as the reputation page's, PvP offered on both
  local mm = page["widget.main"]
  values = {}
  for i, ch in ipairs(mm.choices) do values[i] = ch.value end
  T.eq(values, { "xp", "rep", "pvp" })
  Stub.ui.ClickMenuItem(Stub.ui.FindMenuItem(mm.widget._root, L.REP_MAIN_PVP))
  T.eq(ns.settings.widget.main, "pvp")
  T.eq(f.tp.bl:GetText(), ns.BarSkin.Sub("xp", "Rank 1"))
  Settings.OpenToCategory(Stub.ui.subcategories[1].ID)
  local repPage = rawget(Stub.ui.subcategories[1].frame, "controls")
  T.ok(repPage ~= nil, "the reputation page built")
  values = {}
  for i, ch in ipairs(repPage["widget.main"].choices) do values[i] = ch.value end
  T.eq(values, { "xp", "rep", "pvp" }, "on the reputation page too")
  page = Page()
  -- helps
  T.eq(Lines(page["help.pvpStrip"]), { L.OPT_PVP_STRIP, L.OPT_PVP_STRIP_HELP_WHAT, L.OPT_PVP_STRIP_HELP_TIP,
    L.OPT_PVP_STRIP_HELP_SAME })
  T.eq(Lines(page["help.pvpMain"]), { L.OPT_REP_MAIN, L.OPT_PVP_MAIN_HELP_WHAT,
    format(L.OPT_REP_MAIN_HELP_XP_FMT, L.OPT_HIDE_MAX), L.OPT_PVP_HELP_XP_STRIP, L.OPT_PVP_MAIN_HELP_SAME })
  T.eq(Lines(page["help.pvpAuto"]), { L.OPT_PVP_AUTO, L.OPT_PVP_AUTO_HELP, L.OPT_PVP_HELP_XP_STRIP })
  T.eq(Lines(page["help.pvpAlert"]), { L.OPT_PVP_ALERT, L.OPT_PVP_ALERT_HELP })
  T.eq(Lines(page["help.pvpReset"]), { L.OPT_PVP_RESET_LABEL,
    format(L.OPT_PVP_RESET_HELP_FMT, ns.Fmt.Duration(900)), L.OPT_PVP_RESET_HELP_PAUSE })
  -- the checkboxes
  Stub.RunScript(page["widget.pvpAuto"].widget, "OnClick")
  T.eq(ns.settings.widget.pvpAuto, true)
  Stub.RunScript(page["pvp.capAlert"].widget, "OnClick")
  T.eq(ns.settings.pvp.capAlert, false)
  ns.Core.SetSetting("pvp.capAlert", true)
  T.eq(rawget(page["pvp.capAlert"].widget, "_checked"), true, "synced")
  -- the reset button
  Stub.EnterBG()
  for _ = 1, 3 do
    Stub.Advance(60)
    Stub.GainHonor(50)
  end
  T.ok(ns.char.pvp.he[1].a > 0)
  Stub.RunScript(page["pvp.resetRate"].widget, "OnClick", "LeftButton")
  T.eq(ns.char.pvp.he[1].a, 0)
  T.ok(Stub.printed[#Stub.printed]:find(L.PVP_RESET_RATE_DONE, 1, true) ~= nil)
  -- read-only: refused
  Stub.GainHonor(50)
  ns.readOnly = true
  Stub.RunScript(page["pvp.resetRate"].widget, "OnClick", "LeftButton")
  T.ok(Stub.printed[#Stub.printed]:find(L.READONLY_ACTION, 1, true) ~= nil)
  ns.readOnly = false
  T.ok(ns.char.pvp.he[1].a > 0, "kept")
  Stub.ui.CloseSettings()
  T.no(ns.Options.IsShown())
  T.eq(Stub.errors, {})
end)

T.test("options: the PvP page on Classic Era holds its note only; the main bar offers no PvP", function()
  local ns = Start({ api = "era", ui = { modern = true } })
  local L = ns.L
  ns.Options.Open()
  local page, sub = Page()
  T.eq(sub.name, L.OPT_PVP_PAGE)
  T.eq(next(page), nil, "no control")
  local note = false
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_text") == L.OPT_PVP_UNAVAILABLE then note = true end
  end
  T.ok(note, "the note")
  Settings.OpenToCategory(Stub.ui.subcategories[1].ID)
  local repPage = rawget(Stub.ui.subcategories[1].frame, "controls")
  local values = {}
  for i, ch in ipairs(repPage["widget.main"].choices) do values[i] = ch.value end
  T.eq(values, { "xp", "rep" }, "no PvP choice")
  T.eq(Stub.errors, {})
end)

T.test("options: no subcategory: a PvP section in the main panel, after the reputation's", function()
  for _, ui in ipairs({ { modern = true, subcategory = false }, { settings = false } }) do
    Stub.Reset()
    local ns = Start({ ui = ui })
    ns.Options.Open()
    local panel
    for _, o in ipairs(Stub.regions) do
      local c = rawget(o, "controls")
      if type(c) == "table" and c["widget.shown"] then panel = o end
    end
    T.ok(panel ~= nil, "the main panel")
    local c = panel.controls
    T.ok(c["widget.pvp"] and c["widget.pvpAuto"] and c["pvp.capAlert"] and c["pvp.resetRate"], "the section's controls")
    T.ok(c["widget.pvp"].index > c["rep.resetRate"].index, "after the reputation's")
    T.no(ns.Options.HasPvpPage())
    T.eq(Stub.errors, {})
  end
end)

---------------------------------------------------------------------------
-- The reputation review's fixes, where PvP shares the code
---------------------------------------------------------------------------

local function Box(o)
  local l, b, w, h = o:GetRect()
  if not l then return nil end
  return { l = l, b = b, r = l + w, t = b + h }
end

local function Overlap(a, b)
  return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end

T.test("pvp hover regions: the detailed tooltip hangs off the bar's frame, never over the bar", function()
  local ns, f, tp = Start({ theme = "druid", total = 2000, settings = { ["widget.pvp"] = "rank" } })
  for _, main in ipairs({ "xp", "pvp" }) do
    ns.Core.SetSetting("widget.main", main)
    local hit = tp.pvpHit
    T.ok(hit:IsShown(), main)
    Stub.RunScript(hit, "OnEnter")
    T.ok(ns.Tooltip.IsShownFor(hit), main .. ": shown for the region")
    T.ok(FindRow(TipRows(ns), ns.L.TT_SECTION_PVP) ~= nil, main .. ": the PvP tooltip")
    local tf = ns.TooltipFrame.frame
    local p, rel, rp = tf:GetPoint(1)
    T.eq({ p, rel == f, rp }, { "BOTTOM", true, "TOP" }, main .. ": above the bar's frame")
    T.no(Overlap(Box(tf), Box(f)), main .. ": clear of the bar")
    Stub.RunScript(hit, "OnLeave")
    T.no(ns.Tooltip.IsShownFor(hit))
  end
  ns.Core.SetSetting("widget.point", { "TOP", "TOP", 0, -40 })
  Stub.RunScript(tp.pvpHit, "OnEnter")
  local tf = ns.TooltipFrame.frame
  local p, rel, rp = tf:GetPoint(1)
  T.eq({ p, rel == f, rp }, { "TOP", true, "BOTTOM" }, "the upper half: below the bar's frame")
  T.no(Overlap(Box(tf), Box(f)))
  Stub.RunScript(tp.pvpHit, "OnLeave")
  T.eq(Stub.errors, {})
end)

T.test("pvp main mode: hidden by hideAtMax after a battleground, shown again it draws the XP", function()
  local ns, f, tp = Start({ theme = "futuriste", total = 2000, level = 60,
                            settings = { ["widget.hideAtMax"] = true, ["widget.pvpAuto"] = true } })
  T.no(f:IsShown(), "the XP mode hides it at max level")
  Stub.EnterBG()
  T.ok(f:IsShown(), "PvP in the battleground")
  T.eq(tp.bl:GetText(), ns.BarSkin.Sub("xp", "Rank 2"))
  Stub.LeaveBG()
  T.no(f:IsShown(), "hidden again")
  ns.Core.SetSetting("widget.hideAtMax", false)
  T.ok(f:IsShown())
  T.match(tp.bl:GetText(), "LEVEL", "the XP mode's level text, not the rank")
  T.eq(Vertex(tp.tex.fill), Rgb(1, 0x2b / 255, 0xd6 / 255), "the theme's own fill colour")
  T.eq(Stub.errors, {})
end)

T.test("pvp main mode: hidden for a fight at max level with hideAtMax, what changed is drawn after", function()
  local ns, f, tp = Start({ theme = "futuriste", total = 2000, level = 60, watched = Friendly(),
                      settings = { ["widget.main"] = "rep", ["widget.hideAtMax"] = true,
                                   ["widget.pvpAuto"] = true, ["widget.combatHide"] = true } })
  T.eq(tp.bl:GetText(), ns.BarSkin.Sub("xp", "Darnassus"), "the reputation")
  Stub.EnterCombat()
  T.no(f:IsMouseEnabled(), "combat-hidden")
  Stub.EnterBG()                                   -- the battleground's PvP override
  Stub.LeaveCombat()
  T.eq(tp.bl:GetText(), ns.BarSkin.Sub("xp", "Rank 2"), "PvP after the fight")
  T.eq(Vertex(tp.tex.fill), PvpRgb(ns, ns.Pvp.KEY_RANK))
  T.eq(Stub.errors, {})
end)

T.test("pvp main mode, futuriste: the texts the theme derives from the XP colour follow the fill", function()
  local ns, _, tp = Start({ theme = "futuriste", total = 2000 })
  local function Lighter(r, g, b)
    return Rgb(r + (1 - r) * 0.45, g + (1 - g) * 0.45, b + (1 - b) * 0.45)
  end
  local xp = ns.Themes.Active().colors.xp
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(xp[1], xp[2], xp[3]))
  ns.Core.SetSetting("widget.main", "pvp")
  T.ok(tp.marker:IsShown())
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(ns.Pvp.Color(ns.Pvp.KEY_RANK)), "the rank's colour, lighter")
  ns.Core.SetSetting("widget.main", "xp")
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(xp[1], xp[2], xp[3]), "the XP colour again")
  T.eq(Stub.errors, {})
end)

T.test("options: the reputation strip's box in the PvP main mode: it acts, the note says where the XP goes", function()
  local ns, f = Start({ theme = "futuriste", ui = { modern = true }, total = 2000, watched = Friendly() })
  local L = ns.L
  ns.Options.Open()
  local sub = Stub.ui.subcategories[1]
  Settings.OpenToCategory(sub.ID)
  local rec = rawget(sub.frame, "controls")["widget.rep"]
  local note = nil
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_text") == L.OPT_REP_STRIP_MAIN_NOTE then note = o end
  end
  T.ok(note ~= nil and not note:IsShown(), "no note in the XP mode")
  ns.Core.SetSetting("widget.main", "pvp")
  T.ok(rec.widget:IsEnabled(), "the box acts (the reputation's strip at max level, the tooltip line)")
  T.ok(note:IsShown(), "the note: the strip shows the XP below the max level")
  T.ok(Strip(f.tp, "rep") ~= nil, "the XP strip")
  Stub.RunScript(rec.widget, "OnClick")
  T.eq(ns.settings.widget.rep, false)
  T.no(ns.Rep.Shown(), "no reputation line")
  ns.Core.SetSetting("widget.main", "xp")
  T.no(note:IsShown())
  T.eq(Stub.errors, {})
end)

T.test("options: the main page's reset clears every rate (XP, reputation, PvP); each page's its own", function()
  local ns = Start({ ui = { modern = true }, total = 1000, watched = Friendly() })
  local L = ns.L
  local char = ns.char
  local function Fill()
    Stub.EnterBG()
    for _ = 1, 3 do
      Stub.Advance(60)
      Stub.GrantXP(100)
      Stub.GainRep(50)
      Stub.GainHonor(50)
    end
    Stub.LeaveBG()
  end
  local function Rates()
    return { xp = char.ema[1].a > 0, rep = char.rep.e[1].a > 0, pvp = char.pvp.he[1].a > 0 }
  end
  Fill()
  T.eq(Rates(), { xp = true, rep = true, pvp = true })
  -- the reputation page's: the reputation's only
  Settings.OpenToCategory(Stub.ui.subcategories[1].ID)
  Stub.RunScript(rawget(Stub.ui.subcategories[1].frame, "controls")["rep.resetRate"].widget, "OnClick", "LeftButton")
  T.eq(Rates(), { xp = true, rep = false, pvp = true })
  -- the PvP page's: PvP's only
  Fill()
  Settings.OpenToCategory(Stub.ui.subcategories[2].ID)
  Stub.RunScript(rawget(Stub.ui.subcategories[2].frame, "controls")["pvp.resetRate"].widget, "OnClick", "LeftButton")
  T.eq(Rates(), { xp = true, rep = true, pvp = false })
  -- the main page's (and /tpl reset rate): every rate, and its message says so
  Fill()
  ns.Options.Open()
  local button = nil
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_text") == L.OPT_RESET_RATE then button = rawget(o, "_parent") or o end
  end
  T.ok(button ~= nil, "the main page's button")
  Stub.RunScript(button, "OnClick", "LeftButton")
  T.eq(Rates(), { xp = false, rep = false, pvp = false })
  T.ok(Stub.printed[#Stub.printed]:find(L.RESET_RATE_DONE, 1, true) ~= nil)
  Fill()
  ns.Options.HandleSlash("reset rate")
  T.eq(Rates(), { xp = false, rep = false, pvp = false })
  T.eq(Stub.errors, {})
end)
