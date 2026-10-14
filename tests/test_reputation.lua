-- tests/test_reputation.lua - the watched reputation (Reputation.lua): the strip under the
-- bar's XP track (Bar.lua, BarSkin.lua, the themes' bar.rep), its tooltip line
-- (Tooltip.lua), its option (widget.rep, Options.lua) and the reads of both client APIs
-- (tests/stub_reputation.lua: C_Reputation on Forever, GetWatchedFactionInfo on Classic Era).
-- The stub watches no faction unless a test says so. Its default thresholds: Friendly is
-- 3000 .. 9000 (6000 points).
local Stub, T = ...

local format, floor = string.format, math.floor

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }
local ALL = { "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }

-- Friendly, 1200 of 6000 into it (20 %).
local function Friendly(value)
  return { name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = value or 4200 }
end

-- Loads the addon (widget shown, Stub.theme unless opts.theme); opts.watched: the faction
-- watched at login; opts.api: the client's API ("forever" by default, "era", "none").
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI(opts.ui or { ldb = false })
  if opts.theme then Stub.theme = opts.theme end
  if opts.locale then Stub.locale = opts.locale end
  if opts.api then Stub.SetRepAPI(opts.api) end
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  Stub.rep.watched = opts.watched
  Stub.player.xp = opts.xp or 2000
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  local f = ns.Bar.frame
  T.ok(f ~= nil, "widget created")
  return ns, f, f.tp
end

local function Rgb(r, g, b)
  return { floor(r * 1000 + 0.5), floor(g * 1000 + 0.5), floor(b * 1000 + 0.5) }
end

local function Vertex(t)
  local r, g, b, a = t:GetVertexColor()
  return Rgb(r, g, b), floor((a or 1) * 1000 + 0.5)
end

local function C4(c) return Rgb(c[1], c[2], c[3]), floor((c[4] or 1) * 1000 + 0.5) end

-- The strip as drawn: nil when hidden, else { x, y, w, h, fill (0: none), colour }.
local function Strip(tp)
  local rep = tp.rep
  if not rep or not rep.bg:IsShown() then return nil end
  local _, _, _, x, y = rep.bg:GetPoint(1)
  local fill = rep.fill:IsShown() and rep.fill:GetWidth() or 0
  local col = rep.fill:IsShown() and Vertex(rep.fill) or nil
  return { x = x, y = y, w = rep.bg:GetWidth(), h = rep.bg:GetHeight(), fill = fill, color = col }
end

local function Height(f)
  local _, h = f:GetSize()
  return h
end

-- y of the BOTTOMRIGHT anchor of slot 1 (the top row: track y + H + gap).
local function TopY(tp)
  local _, _, _, _, y = tp.slots[1]:GetPoint(1)
  return y
end

local function AnchorY(fs)
  local _, _, _, _, y = fs:GetPoint(1)
  return y
end

-- Frame geometry of the theme (SPEC-themes 2.4, Bar.lua ApplyBarStyle): H, bottomRow, the
-- frame height without the strip and the room the strip adds.
local function Geometry(ns)
  local Themes = ns.Themes
  local th = Themes.Active()
  local text, bar = th.text, th.bar
  local function Sz(e)
    local _, s = Themes.Font(text.font[e], 11 + text.size[e])
    return s
  end
  local H = math.max(bar.hMin, 8 + bar.hAdd)
  local topRow = math.max(Sz("s1"), Sz("s3")) + 2
  local bottom = math.max(Sz("level"), Sz("xp"), Sz("s2"))
  if text.split then bottom = math.max(bottom, Sz("levelValue"), Sz("xpLabel")) end
  local bottomRow = bottom + 2
  local r = bar.rep
  local rb = math.max(0, r.off + r.h + r.clear - bar.gap)
  return { H = H, bottomRow = bottomRow, rb = rb, pad = bar.pad, gap = bar.gap, rep = r,
           fh = bar.pad + topRow + bar.gap + H + bar.gap + bottomRow + bar.pad }
end

-- Rows below the track's bottom edge of the theme's layers that span the whole track and
-- are not soft halos (three-slices: shadows, auras): the "hard" frames the strip must clear.
local function HardDepth(th, H)
  local deepest = 0
  for _, L in ipairs(th.bar.layers) do
    if (L.span or "track") == "track" and L.kind ~= "three" and L.kind ~= "ticks" then
      local y1
      if L.band then
        y1 = floor(L.band[2] * H + 0.5)
      elseif L.h then
        y1 = (L.top or 0) + L.h
      else
        y1 = H - (L.bottom or 0)
      end
      if y1 - H > deepest then deepest = y1 - H end
    end
  end
  return deepest
end

-- Rows below the track's bottom edge of the ornaments that follow the fill's end (markers,
-- needles, tabs, arrows and their glows): they move along the strip, so none may reach into
-- it (it would hide the strip there and read as a reputation marker).
local function MarkerDepth(th, H)
  local deepest = 0
  for _, L in ipairs(th.bar.layers) do
    if L.span == "fillEnd" or L.span == "restEnd" then
      local y1
      if L.band then
        y1 = floor(L.band[2] * H + 0.5)
      elseif L.h then
        y1 = (L.top or 0) + L.h
      else
        y1 = H - (L.bottom or 0)
      end
      if y1 - H > deepest then deepest = y1 - H end
    end
  end
  return deepest
end

-- Rows of block 1 of the themed tooltip: { left, right, kind } (shown rows only).
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
  for i, r in ipairs(rows) do
    if r.left == left then return r, i end
  end
  return nil
end

local function IndexOf(rows, left)
  local _, i = FindRow(rows, left)
  return i
end

-- Lines of the shared GameTooltip (native theme): { left, right }.
local function NativeLines()
  local out = {}
  for i, l in ipairs(GameTooltip._lines) do out[i] = { left = l[1], right = l[2] } end
  return out
end

local function Controls()
  return rawget(Stub.ui.categories[1].frame, "controls")
end

---------------------------------------------------------------------------
-- Shown or not, progress, colours
---------------------------------------------------------------------------

T.test("reputation: nothing without a watched faction (no region, the layout of before), shown once one is", function()
  local ns, f, tp = Start({ theme = "futuriste" })
  T.eq(ns.settings.widget.rep, true, "on by default")
  T.no(ns.Rep.Shown())
  T.eq(tp.rep, nil, "no region created while nothing is watched")
  local g = Geometry(ns)
  T.eq(Height(f), g.fh, "frame height of the theme without the strip")
  local top0, bl0 = TopY(tp), AnchorY(tp.bl)
  Stub.WatchFaction(Friendly())
  T.ok(ns.Rep.Shown(), "a watched faction: shown")
  local s = Strip(tp)
  T.ok(s ~= nil, "strip drawn")
  T.eq({ s.x, s.w, s.h }, { g.pad, 360, g.rep.h }, "track's x and width, the theme's height")
  T.eq(s.fill, 72, "1200 / 6000 of 360 px")
  T.eq(s.color, Rgb(0, 0.6, 0.1), "Friendly: FACTION_BAR_COLORS[5]")
  T.eq(Height(f), g.fh + g.rb, "the frame grows by the strip's room")
  T.eq(TopY(tp), top0 + g.rb, "the top row (and the track) move up")
  T.eq(AnchorY(tp.bl), bl0, "the text row under the bar stays")
  local trackY = TopY(tp) - g.H - g.gap
  T.eq(s.y, trackY - g.rep.off - g.rep.h, "off px under the track")
  -- no faction again: hidden, the layout of before
  Stub.WatchFaction(nil)
  T.no(ns.Rep.Shown())
  T.eq(Strip(tp), nil, "hidden")
  T.eq(Height(f), g.fh)
  T.eq(TopY(tp), top0)
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("reputation: progress inside each standing, its colour, Exalted full, values clamped", function()
  local ns, _, tp = Start({ theme = "actuel", watched = Friendly() })
  T.eq(Strip(tp).fill, 72)
  local K = ns.Rep.COLORS
  for r = 1, 7 do
    local t = Stub.REP_THRESHOLDS[r]
    local span = t[2] - t[1]
    Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = r, min = t[1], max = t[2],
                        value = t[1] + floor(span / 4) })
    local s = Strip(tp)
    T.eq(s.fill, floor(360 * floor(span / 4) / span + 0.5), "standing " .. r .. ": a quarter")
    T.eq(s.color, Rgb(K[r][1], K[r][2], K[r][3]), "standing " .. r .. ": its colour")
  end
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 8, min = 42000, max = 42999, value = 42000 })
  T.eq(Strip(tp).fill, 360, "Exalted: full")
  T.eq(Strip(tp).color, Rgb(0, 0.6, 0.1))
  -- the start of a standing: the background alone
  Stub.WatchFaction(Friendly(3000))
  T.eq(Strip(tp).fill, 0, "0 points: no fill")
  T.no(tp.rep.fill:IsShown())
  T.ok(tp.rep.bg:IsShown())
  Stub.WatchFaction(Friendly(1000))
  T.eq(Strip(tp).fill, 0, "below the threshold: clamped")
  Stub.WatchFaction(Friendly(12000))
  T.eq(Strip(tp).fill, 360, "past the next threshold: clamped")
  -- the game's colours when it has them, else the classic copy
  rawget(_G, "FACTION_BAR_COLORS")[5] = { r = 0.1, g = 0.2, b = 0.9 }
  Stub.WatchFaction(Friendly(4200))
  T.eq(Strip(tp).color, Rgb(0.1, 0.2, 0.9), "FACTION_BAR_COLORS")
  rawget(_G, "FACTION_BAR_COLORS")[5] = nil
  Stub.WatchFaction(Friendly(4300))
  T.eq(Strip(tp).color, Rgb(0, 0.6, 0.1), "an entry missing: the classic colour")
  rawset(_G, "FACTION_BAR_COLORS", nil)
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 3, min = -3000, max = 0, value = -1500 })
  T.eq(Strip(tp).color, Rgb(0.75, 0.27, 0), "no FACTION_BAR_COLORS: the classic colours")
end)

T.test("reputation: invalid or secret data shows nothing, never an error", function()
  local ns, _, tp = Start({ theme = "pixel", watched = Friendly() })
  T.ok(ns.Rep.Shown())
  -- shown, then `t` watched (after `setup`): nothing shown
  local function Case(t, what, setup)
    Stub.WatchFaction(Friendly())
    T.ok(ns.Rep.Shown(), what .. ": shown first")
    if setup then setup() end
    Stub.WatchFaction(t)
    T.no(ns.Rep.Shown(), what)
    T.eq(Strip(tp), nil, what .. ": strip hidden")
    Stub.rep.secret, Stub.rep.secretFields = false, {}
  end
  Case(nil, "no faction")
  Case({ name = "", factionID = 0, reaction = 0, min = 0, max = 0, value = 0 }, "the empty table of no faction")
  Case({ name = "Darnassus", factionID = 0, reaction = 5, min = 3000, max = 9000, value = 4200 }, "factionID 0")
  Case({ name = "", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 }, "no name")
  Case({ name = "Darnassus", factionID = 69, reaction = 0, min = 3000, max = 9000, value = 4200 }, "reaction 0")
  Case({ name = "Darnassus", factionID = 69, reaction = 9, min = 3000, max = 9000, value = 4200 }, "reaction 9")
  Case({ name = "Darnassus", factionID = 69, reaction = 0 / 0, min = 3000, max = 9000, value = 4200 }, "reaction NaN")
  Case({ name = "Darnassus", factionID = 69, reaction = 5, min = 9000, max = 9000, value = 9000 }, "max = min")
  Case({ name = "Darnassus", factionID = 69, reaction = 5, min = 9000, max = 3000, value = 4200 }, "max < min")
  Case({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 1 / 0, value = 4200 }, "max infinite")
  -- Exalted needs no thresholds: full whatever they are
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 8, min = 42999, max = 42999, value = 42999 })
  T.ok(ns.Rep.Shown(), "Exalted with max = min: full")
  T.eq(Strip(tp).fill, 360)
  -- secret values: the whole read, the name, a threshold (Exalted reads none of them)
  Case(Friendly(), "a secret read", function() Stub.rep.secret = true end)
  Case(Friendly(), "a secret name", function() Stub.rep.secretFields = { name = true } end)
  Case(Friendly(), "a secret standing", function() Stub.rep.secretFields = { currentStanding = true } end)
  Case(Friendly(), "a secret reaction", function() Stub.rep.secretFields = { reaction = true } end)
  Case(Friendly(), "a secret factionID", function() Stub.rep.secretFields = { factionID = true } end)
  Stub.rep.secretFields = { currentStanding = true, currentReactionThreshold = true, nextReactionThreshold = true }
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 8, min = 42000, max = 42999, value = 42500 })
  T.ok(ns.Rep.Shown(), "Exalted with secret thresholds and standing: full")
  T.eq(Strip(tp).fill, 360)
  Stub.rep.secretFields = {}
  -- an API that raises
  local api = rawget(_G, "C_Reputation")
  local get = api.GetWatchedFactionData
  Case(Friendly(), "the API raises", function() api.GetWatchedFactionData = function() error("boom") end end)
  api.GetWatchedFactionData = get
  Case(Friendly(), "the API returns no table", function()
    api.GetWatchedFactionData = function() return "not a table" end
  end)
  api.GetWatchedFactionData = get
  Stub.WatchFaction(Friendly())
  T.ok(ns.Rep.Shown(), "back")
  T.eq(Stub.errors, {})
end)

T.test("reputation: retail-only kinds (renown, friendships) show nothing; paragon (Exalted) is full", function()
  local ns, _, tp = Start({ theme = "druid", watched = Friendly() })
  T.ok(ns.Rep.Shown())
  Stub.rep.major[2510] = true
  Stub.WatchFaction({ name = "Valdrakken Accord", factionID = 2510, reaction = 4, min = 0, max = 2500, value = 1200 })
  T.no(ns.Rep.Shown(), "a major faction (renown)")
  Stub.rep.friends[2640] = true
  Stub.WatchFaction({ name = "Brann Bronzebeard", factionID = 2640, reaction = 5, min = 0, max = 2000, value = 300 })
  T.no(ns.Rep.Shown(), "a friendship")
  Stub.WatchFaction({ name = "The Assembly of the Deeps", factionID = 2594, reaction = 8, min = 42000, max = 42000,
                      value = 42000 })
  T.ok(ns.Rep.Shown(), "Exalted (paragon): full")
  T.eq(Strip(tp).fill, 360)
  -- a client without C_GossipInfo: renown still known, the rest as usual
  rawset(_G, "C_GossipInfo", nil)
  Stub.WatchFaction({ name = "Ironforge", factionID = 47, reaction = 6, min = 9000, max = 21000, value = 15000 })
  T.ok(ns.Rep.Shown())
  T.eq(Strip(tp).fill, 180)
end)

---------------------------------------------------------------------------
-- Client APIs and events
---------------------------------------------------------------------------

T.test("reputation: Classic Era's GetWatchedFactionInfo (six returns, nothing when none, no ID on old clients)", function()
  local ns, f, tp = Start({ theme = "actuel", api = "era" })
  T.eq(rawget(_G, "C_Reputation"), nil, "Era: no C_Reputation")
  T.no(ns.Rep.Shown())
  local h0 = Height(f)
  Stub.WatchFaction({ name = "Stormwind", factionID = 72, reaction = 6, min = 9000, max = 21000, value = 12000 })
  T.ok(ns.Rep.Shown())
  T.eq(Strip(tp).fill, 90, "3000 / 12000 of 360 px")
  T.eq(Height(f), h0 + 4, "Classic: 4 px more")
  T.ok(Stub.calls.GetWatchedFactionInfo > 0)
  T.eq(Stub.calls.GetWatchedFactionData, 0)
  Stub.WatchFaction({ name = "Stormwind", reaction = 6, min = 9000, max = 21000, value = 15000 })
  T.ok(ns.Rep.Shown(), "no factionID (older Era clients)")
  T.eq(Strip(tp).fill, 180)
  Stub.WatchFaction(nil)
  T.no(ns.Rep.Shown(), "name nil: none")
  Stub.rep.secret = true
  Stub.WatchFaction({ name = "Stormwind", factionID = 72, reaction = 6, min = 9000, max = 21000, value = 12000 })
  T.no(ns.Rep.Shown(), "a secret read")
  Stub.rep.secret = false
  -- the setter, without any event (the post-hook)
  Stub.WatchFaction({ name = "Ironforge", factionID = 47, reaction = 5, min = 3000, max = 9000, value = 6000 },
    { quiet = true })
  T.no(ns.Rep.Shown(), "nothing read without an event")
  SetWatchedFactionIndex(3)
  T.ok(ns.Rep.Shown(), "the game's setter (hooked)")
  T.eq(Strip(tp).fill, 180)
end)

T.test("reputation: a C_Reputation with paragon functions only: Era's API, its global setter hooked", function()
  local ns, _, tp = Start({ theme = "actuel", api = "eraParagon" })
  T.eq(type(rawget(_G, "C_Reputation")), "table", "a C_Reputation table")
  T.eq(rawget(_G, "C_Reputation").SetWatchedFactionByIndex, nil, "without the setters")
  Stub.WatchFaction({ name = "Stormwind", factionID = 72, reaction = 6, min = 9000, max = 21000, value = 12000 })
  T.ok(ns.Rep.Shown())
  T.eq(Strip(tp).fill, 90)
  T.ok(Stub.calls.GetWatchedFactionInfo > 0, "read with GetWatchedFactionInfo")
  -- another faction ticked in the game's panel: the global setter, no event
  Stub.WatchFaction({ name = "Ironforge", factionID = 47, reaction = 5, min = 3000, max = 9000, value = 6000 },
    { quiet = true })
  T.eq(Strip(tp).fill, 90, "nothing read without an event")
  SetWatchedFactionIndex(3)
  T.eq(Strip(tp).fill, 180, "the global setter (hooked)")
  T.eq(Stub.errors, {})
end)

T.test("reputation: neither API: nothing, no error; the option and the strip stay off", function()
  local ns, _, tp = Start({ theme = "futuriste", api = "none", watched = Friendly() })
  T.no(ns.Rep.Shown())
  T.eq(tp.rep, nil)
  Stub.Fire("UPDATE_FACTION")
  T.no(ns.Rep.Shown())
end)

T.test("reputation: events only: UPDATE_FACTION, FACTION_STANDING_CHANGED, PLAYER_ENTERING_WORLD, the setters", function()
  local ns, _, tp = Start({ theme = "warrior", watched = Friendly() })
  T.eq(Strip(tp).fill, 72)
  T.eq(Stub.CountRegistered("UPDATE_FACTION"), 1)
  T.eq(Stub.CountRegistered("FACTION_STANDING_CHANGED"), 1)
  -- a gain: UPDATE_FACTION
  Stub.GainRep(1800)
  T.eq(Strip(tp).fill, 180, "3000 / 6000")
  -- across a standing: FACTION_STANDING_CHANGED (then UPDATE_FACTION)
  Stub.GainRep(3000)
  T.eq(Stub.rep.watched.reaction, 6)
  T.eq(Strip(tp).fill, 0, "Honored, 0 / 12000")
  T.eq(Vertex(tp.rep.fill), Rgb(0, 0.6, 0.1), "Honored's colour")
  Stub.GainRep(-3000)
  T.eq(Stub.rep.watched.reaction, 5, "back to Friendly")
  T.eq(Strip(tp).fill, 180)
  -- each event alone
  local w = Stub.rep.watched
  w.value = 7500
  Stub.Fire("FACTION_STANDING_CHANGED", 69, 5)
  T.eq(Strip(tp).fill, 270, "FACTION_STANDING_CHANGED alone")
  w.value = 6000
  Stub.Fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq(Strip(tp).fill, 180, "PLAYER_ENTERING_WORLD")
  -- another faction picked in the game's panel: its setters (no event needed)
  Stub.WatchFaction({ name = "Ironforge", factionID = 47, reaction = 3, min = -3000, max = 0, value = -2250 },
    { quiet = true })
  T.eq(Strip(tp).fill, 180, "no read without an event")
  C_Reputation.SetWatchedFactionByIndex(4)
  T.eq(Strip(tp).fill, 90, "SetWatchedFactionByIndex (hooked)")
  T.eq(Strip(tp).color, Rgb(0.75, 0.27, 0), "Unfriendly")
  Stub.WatchFaction(nil, { quiet = true })
  C_Reputation.SetWatchedFactionByID(0)
  T.no(ns.Rep.Shown(), "SetWatchedFactionByID (hooked): none")
  -- no read and no event without the option
  ns.Core.SetSetting("widget.rep", false)
  T.eq(Stub.CountRegistered("UPDATE_FACTION"), 0, "unregistered with the option off")
  T.eq(Stub.CountRegistered("FACTION_STANDING_CHANGED"), 0)
  local reads = Stub.calls.GetWatchedFactionData
  Stub.WatchFaction(Friendly())
  C_Reputation.SetWatchedFactionByIndex(2)
  T.eq(Stub.calls.GetWatchedFactionData, reads, "no read with the option off")
  T.no(ns.Rep.Shown())
end)

T.test("reputation: a client without FACTION_STANDING_CHANGED (the bus tolerates it)", function()
  Stub.unknownEvents.FACTION_STANDING_CHANGED = true
  local ns, _, tp = Start({ theme = "rogue", watched = Friendly() })
  T.ok(ns.Rep.Shown())
  Stub.GainRep(600)
  T.eq(Strip(tp).fill, 108, "UPDATE_FACTION alone")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- The option and the settings
---------------------------------------------------------------------------

T.test("reputation: widget.rep turns the strip and the line off and on; default and repair", function()
  local ns, f, tp = Start({ theme = "heroic", watched = Friendly() })
  local g = Geometry(ns)
  T.eq(Height(f), g.fh + g.rb)
  ns.Core.SetSetting("widget.rep", false)
  T.no(ns.Rep.Shown())
  T.eq(Strip(tp), nil, "off: hidden")
  T.eq(Height(f), g.fh, "off: the layout without the strip")
  ns.Core.SetSetting("widget.rep", true)
  T.ok(ns.Rep.Shown())
  T.eq(Strip(tp).fill, 72, "on again: read at once")
  T.eq(Height(f), g.fh + g.rb)
  T.eq(ns.Core.SetSetting("widget.rep", "yes"), false, "a bool only")
  -- saved values: kept, repaired, a whole table swapped late
  Stub.Reset()
  local ns2 = Start({ theme = "heroic", watched = Friendly(),
                      db = { schema = 1, settings = { firstRunDone = true, widget = { rep = false } } } })
  T.eq(ns2.settings.widget.rep, false, "kept off")
  T.no(ns2.Rep.Shown())
  Stub.Reset()
  local ns3 = Start({ theme = "heroic", watched = Friendly(),
                      db = { schema = 1, settings = { firstRunDone = true, widget = { rep = "yes" } } } })
  T.eq(ns3.settings.widget.rep, true, "repaired: the default")
  T.ok(ns3.Rep.Shown())
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { firstRunDone = true, widget = { rep = false } } })
  ns3.Core.CheckSwap()
  Stub.Advance(1)
  T.no(ns3.Rep.Shown(), "a late table with the option off")
  T.eq(Strip(ns3.Bar.frame.tp), nil)
end)

T.test("reputation: the options checkbox on the Reputation page, its help icon and tooltip", function()
  local ns = Start({ theme = "futuriste", ui = { modern = true }, watched = Friendly() })
  local L = ns.L
  ns.Options.Open()
  local controls = Controls()
  T.no(controls["widget.rep"], "no longer in Display")
  T.no(controls["help.rep"])
  -- Display keeps a pointer note right after Show the bar
  local note = false
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_text") == L.OPT_REP_MOVED then note = true end
  end
  T.ok(note, "the pointer note")
  -- the page: TruePlayed > Reputation
  local sub = Stub.ui.subcategories[1]
  T.ok(sub ~= nil and sub.parent == Stub.ui.categories[1], "a subcategory of TruePlayed's")
  T.eq(sub.name, L.OPT_REP_PAGE)
  Settings.OpenToCategory(sub.ID)
  local page = rawget(sub.frame, "controls")
  local check, help = page["widget.rep"], page["help.rep"]
  T.ok(check and check.kind == "check", "a checkbox")
  T.ok(help and help.kind == "help", "its help record")
  T.eq(check.label:GetText(), L.OPT_REP)
  T.eq(help.index, check.index + 1)
  T.eq(check.helpRoom, 18)
  T.eq(rawget(check.widget, "_checked"), true, "ticked (default)")
  -- the help: the faction (the game's checkbox label), what the strip shows, the details
  local f, icon = help.widget, help.icon
  T.eq(icon:GetTexture(), ns.C.TEX_HELP)
  f:GetScript("OnEnter")(f)
  local got = GameTooltip._lines
  T.eq(#got, 4, "title and three lines")
  T.eq(got[1][1], L.OPT_REP, "the label as title")
  T.eq(got[2][1], format(L.OPT_REP_HELP_WHERE_FMT, "Show as Experience Bar"), "the game's own label")
  T.eq(got[3][1], L.OPT_REP_HELP_STRIP)
  T.eq(got[4][1], L.OPT_REP_HELP_TIP)
  T.eq(GameTooltip._colors[2], { 1, 0.82, 0 }, "gold")
  T.no(got[5], "no click line (that is the automatic reload's)")
  f:GetScript("OnLeave")(f)
  T.no(GameTooltip:IsShown())
  -- unticked: off
  Stub.RunScript(check.widget, "OnClick", "LeftButton")
  T.eq(ns.settings.widget.rep, false)
  T.no(ns.Rep.Shown())
  -- without the game's string: the addon's own
  rawset(_G, "SHOW_FACTION_ON_MAINSCREEN", nil)
  f:GetScript("OnEnter")(f)
  T.eq(GameTooltip._lines[2][1], format(L.OPT_REP_HELP_WHERE_FMT, L.OPT_REP_GAME_CHECK))
  f:GetScript("OnLeave")(f)
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Layout in every theme
---------------------------------------------------------------------------

T.test("reputation: every theme: the strip under the track, clear of its frame and of the text row", function()
  for _, key in ipairs(KEYS) do
    Stub.Reset()
    local ns, f, tp = Start({ theme = key })
    local th = ns.Themes.Active()
    local g = Geometry(ns)
    local r = g.rep
    T.eq(Height(f), g.fh, key .. ": no strip, no room")
    local bl0, brx0, s20, top0 = AnchorY(tp.bl), AnchorY(tp.brx), AnchorY(tp.slots[2]), TopY(tp)
    Stub.WatchFaction(Friendly())
    local s = Strip(tp)
    T.ok(s ~= nil, key .. ": shown")
    T.eq(Height(f), g.fh + g.rb, key .. ": frame + max(0, off + h + clear - gap)")
    T.eq(TopY(tp), top0 + g.rb, key .. ": the track and the top row move up by the same")
    T.eq({ AnchorY(tp.bl), AnchorY(tp.brx), AnchorY(tp.slots[2]) }, { bl0, brx0, s20 },
      key .. ": the text row under the bar does not move")
    local trackY = TopY(tp) - g.H - g.gap
    T.eq(s.y + s.h, trackY - r.off, key .. ": off px under the track")
    T.eq({ s.x, s.w }, { g.pad, 360 }, key .. ": the track's x and width")
    T.ok(s.h >= 2 and s.h <= 4, key .. ": discreet (2 to 4 px)")
    -- clear of the frames around the track (the soft halos drawn under it may cross it, and
    -- the ornaments at the track's ends cover the strip's ends as they cover the track's)
    T.ok(r.off >= HardDepth(th, g.H) + 1, format("%s: 1 px clear of the frame (%d px below the track)", key,
      HardDepth(th, g.H)))
    -- clear of the fill-end marker, wherever the fill ends (its glow may touch the top edge)
    T.ok(r.off >= MarkerDepth(th, g.H), format("%s: clear of the fill-end marker (%d px below the track)", key,
      MarkerDepth(th, g.H)))
    -- clear of the text row (its box: the biggest font + 2 px, from pad)
    T.ok(s.y >= g.pad + g.bottomRow + 1, format("%s: above the text row (%d >= %d)", key, s.y, g.pad + g.bottomRow + 1))
    T.ok(s.y - (g.pad + g.bottomRow) >= r.clear, key .. ": clear px above the text row")
    -- its draw layers: over the panel and the halos, under the ornaments
    local _, sub = tp.rep.bg:GetDrawLayer()
    T.eq({ tp.rep.bg:GetDrawLayer() }, { "BORDER", 6 }, key .. ": background layer")
    T.eq({ tp.rep.fill:GetDrawLayer() }, { "BORDER", 7 }, key .. ": fill layer")
    T.ok(sub == 6)
    -- the background: the theme's colour
    T.eq({ Vertex(tp.rep.bg) }, { C4(r.c) }, key .. ": background colour")
    T.eq(#Stub.errors, 0, key)
  end
end)

T.test("reputation: the strip's room per theme (no growth where it fits in the gap)", function()
  local want = { futuriste = 7, actuel = 4, heroic = 5, pixel = 5, warrior = 5, paladin = 6, hunter = 5,
                 rogue = 9, priest = 9, shaman = 0, mage = 4, warlock = 10, druid = 5 }
  for _, key in ipairs(KEYS) do
    Stub.Reset()
    local ns = Start({ theme = key, watched = Friendly() })
    T.eq(Geometry(ns).rb, want[key], key)
  end
end)

T.test("reputation: a theme switch re-skins the strip (same textures, new place and background)", function()
  local ns, f, tp = Start({ theme = "futuriste", watched = Friendly() })
  local bg, fill = tp.rep.bg, tp.rep.fill
  local created = Stub.created.Texture
  for _, key in ipairs({ "druid", "actuel", "pixel", "shaman", "warlock", "futuriste" }) do
    ns.Core.SetSetting("theme", key)
    Stub.Advance(1)
    local g = Geometry(ns)
    T.ok(tp.rep.bg == bg and tp.rep.fill == fill, key .. ": the same textures")
    T.eq(Height(f), g.fh + g.rb, key .. ": its room")
    T.eq({ Vertex(bg) }, { C4(g.rep.c) }, key .. ": its background")
    T.eq(Strip(tp).fill, 72, key .. ": the fill kept")
    T.eq(Strip(tp).color, Rgb(0, 0.6, 0.1))
  end
  -- the second cycle creates no texture for the strip (the theme pools are B1's)
  local before = Stub.created.Texture
  for _, key in ipairs({ "druid", "actuel", "pixel", "shaman", "warlock", "futuriste" }) do
    ns.Core.SetSetting("theme", key)
    Stub.Advance(1)
  end
  T.eq(Stub.created.Texture, before, "no texture created on a second cycle")
  T.ok(created > 0)
  -- a recolour in place (THEME_CHANGED "colors") re-applies the background
  local c = ns.Themes.Active().bar.rep.c
  local saved = { c[1], c[2], c[3], c[4] }
  c[1], c[2], c[3], c[4] = 0.25, 0.5, 0.75, 0.5
  ns.Core.SetSetting("widget.xpColor", { 0.2, 0.9, 0.3 })
  Stub.Advance(1)
  T.eq({ Vertex(bg) }, { Rgb(0.25, 0.5, 0.75), 500 }, "recoloured with the theme")
  c[1], c[2], c[3], c[4] = saved[1], saved[2], saved[3], saved[4]
end)

-- A weak reference to the active theme's strip background (built here, so that no register
-- of the test keeps the theme alive).
local function WeakRepColor(ns)
  return setmetatable({ c = ns.Themes.Active().bar.rep.c }, { __mode = "v" })
end

T.test("reputation: hidden, then a theme switch: nothing keeps the old theme's strip colour (P5)", function()
  local ns, _, tp = Start({ theme = "futuriste", watched = Friendly() })
  local weak = WeakRepColor(ns)
  T.ok(weak.c ~= nil, "futuriste's strip background")
  Stub.WatchFaction(nil)
  T.eq(Strip(tp), nil, "hidden")
  ns.Core.SetSetting("theme", "druid")
  Stub.Advance(1)
  for _ = 1, 3 do collectgarbage("collect") end
  T.eq(weak.c, nil, "collected with the old compiled theme")
  Stub.WatchFaction(Friendly())
  T.eq({ Vertex(tp.rep.bg) }, { C4(ns.Themes.Active().bar.rep.c) }, "shown again: druid's background")
end)

T.test("reputation: bar style changes (width, height, font size, scale) keep the strip right", function()
  local ns, f, tp = Start({ theme = "mage", watched = Friendly() })
  ns.Core.SetSetting("widget.width", 200)
  Stub.Advance(1)
  T.eq(Strip(tp).w, 200)
  T.eq(Strip(tp).fill, 40, "1200 / 6000 of 200 px")
  ns.Core.SetSetting("widget.height", 16)
  ns.Core.SetSetting("widget.fontSize", 16)
  Stub.Advance(1)
  local g = Geometry(ns)
  local _, fh = f:GetSize()
  T.ok(fh > g.fh, "taller")
  local trackY = TopY(tp) - math.max(ns.Themes.Active().bar.hMin, 16 + ns.Themes.Active().bar.hAdd) - g.gap
  T.eq(Strip(tp).y + Strip(tp).h, trackY - g.rep.off, "still off px under the track")
end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

T.test("reputation: the tooltip line after the XP block (themed), its format, Exalted, female, no labels", function()
  local ns, f = Start({ theme = "druid", watched = Friendly() })
  local L = ns.L
  ns.Tooltip.ShowFor(f)
  Stub.Advance(1)
  local rows = TipRows(ns)
  local row, i = FindRow(rows, "Darnassus")
  T.ok(row ~= nil, "a row with the faction's name")
  T.eq(row.right, "Friendly · 1,200 / 6,000 (20.0%)")
  T.eq(i + 1, IndexOf(rows, L.TT_SESSION), "right before the session")
  T.ok(i > IndexOf(rows, L.TT_XPH), "after the XP block")
  -- Exalted: the standing alone
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 8, min = 42000, max = 42999, value = 42999 })
  Stub.Advance(1)
  T.eq(FindRow(TipRows(ns), "Darnassus").right, "Exalted")
  -- a female character: the _FEMALE label
  Stub.rep.sex = 3
  Stub.WatchFaction(Friendly(8999))
  Stub.Advance(1)
  T.eq(FindRow(TipRows(ns), "Darnassus").right, "Friendly (f) · 5,999 / 6,000 (99.9%)")
  -- no game label: the addon's own
  Stub.SetRepGlobals(false)
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 7, min = 21000, max = 42000, value = 31500 })
  Stub.Advance(1)
  T.eq(FindRow(TipRows(ns), "Darnassus").right, format(L.TT_REP_FMT, L.REP_STANDING_7, "10,500", "21,000", "50.0%"))
  -- gone with the faction, and with the option
  Stub.WatchFaction(nil)
  Stub.Advance(1)
  T.eq(FindRow(TipRows(ns), "Darnassus"), nil, "no faction: no line")
  Stub.WatchFaction(Friendly())
  Stub.Advance(1)
  T.ok(FindRow(TipRows(ns), "Darnassus") ~= nil)
  ns.Core.SetSetting("widget.rep", false)
  Stub.Advance(1)
  T.eq(FindRow(TipRows(ns), "Darnassus"), nil, "option off: no line")
  ns.Tooltip.Hide()
end)

T.test("reputation: the tooltip line in Classic (GameTooltip), at max level, with Shift and in Broker's", function()
  local ns, f = Start({ theme = "actuel", watched = Friendly() })
  local L = ns.L
  ns.Tooltip.ShowFor(f)
  Stub.Advance(1)
  local lines = NativeLines()
  local at
  for i, l in ipairs(lines) do
    if l.left == "Darnassus" then at = i end
  end
  T.ok(at ~= nil, "the line")
  T.eq(lines[at].right, "Friendly · 1,200 / 6,000 (20.0%)")
  T.eq(lines[at - 1].left, " ", "after the XP block's blank line")
  T.eq(lines[at + 1].left, " ", "a blank line after it")
  T.eq(lines[at + 2].left, L.TT_SESSION)
  -- Shift: block 1 keeps it, block 2 has none
  Stub.SetShift(true)
  Stub.Advance(1)
  local n = 0
  for _, l in ipairs(NativeLines()) do
    if l.left == "Darnassus" then n = n + 1 end
  end
  T.eq(n, 1, "block 1 only")
  Stub.SetShift(false)
  ns.Tooltip.Hide()
  -- Broker's one tooltip (Tooltip.Fill): the line too
  local tt = Stub.NewTooltip()
  ns.Tooltip.Fill(tt, true)
  local found = false
  for _, l in ipairs(tt._lines) do
    if l[1] == "Darnassus" then found = true end
  end
  T.ok(found, "Broker's tooltip")
  -- max level: after the max-level line
  Stub.Reset()
  Stub.player.level = 60
  local ns2, f2 = Start({ theme = "futuriste", watched = Friendly() })
  T.ok(ns2.Tracker.IsMax(), "max level")
  ns2.Tooltip.ShowFor(f2)
  Stub.Advance(1)
  local rows = TipRows(ns2)
  local _, i = FindRow(rows, "Darnassus")
  T.ok(i ~= nil and IndexOf(rows, ns2.L.TT_MAX_LEVEL) == i - 1, "after the max-level line")
end)

---------------------------------------------------------------------------
-- Performance
---------------------------------------------------------------------------

T.test("reputation: the bar's tick with the strip shown: no read, no draw, nothing allocated, no OnUpdate", function()
  local _, _, tp = Start({ theme = "futuriste", watched = Friendly() })
  T.ok(Strip(tp) ~= nil)
  Stub.Advance(300)
  local reads = Stub.calls.GetWatchedFactionData
  local fill, bg = tp.rep.fill, tp.rep.bg
  local v0, b0, w0 = rawget(fill, "_vSeq"), rawget(bg, "_vSeq"), fill:GetWidth()
  Stub.Advance(60)
  T.eq(Stub.calls.GetWatchedFactionData, reads, "no read on TICK")
  T.eq({ rawget(fill, "_vSeq"), rawget(bg, "_vSeq") }, { v0, b0 }, "no colour call on TICK")
  T.eq(fill:GetWidth(), w0)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 2, format("bar + strip: %.2f KB over 600 ticks", kb))
  T.eq(Stub.onUpdateCount, 0)
  -- an UPDATE_FACTION that changes nothing drawn: no message, no draw
  local seq = rawget(fill, "_vSeq")
  local p0 = select(5, fill:GetPoint(1))
  Stub.Fire("UPDATE_FACTION")
  T.eq(rawget(fill, "_vSeq"), seq, "nothing redrawn")
  T.eq(select(5, fill:GetPoint(1)), p0)
end)

---------------------------------------------------------------------------
-- Widths: the tooltip line with long faction names (real fonts)
---------------------------------------------------------------------------

-- A usual long faction name, and an extreme one, in the language of each client (the
-- non-Latin ones as UTF-8 byte escapes: sources stay in the Latin-1 range, check_encoding).
local NAMES = {
  enUS = { "Thorium Brotherhood", "Hydraxian Waterlords" },
  frFR = { "Confrérie du thorium", "Entraîneurs de sabres-d'hiver" },
  deDE = { "Thoriumbruderschaft", "Hydraxianische Wasserfürsten" },
  esES = { "Hermandad del Torio", "Instructores de Sableinvernal" },
  esMX = { "Hermandad del Torio", "Instructores de Sableinvernal" },
  itIT = { "Confraternita del Torio", "Addestratori di Fiere dell'Inverno" },
  ptBR = { "Irmandade do Tório", "Treinadores de Sabres-do-inverno" },
  ruRU = { "\208\145\209\128\208\176\209\130\209\129\209\130\208\178\208\190 \208\162\208\190\209\128\208\184\209\143",
           "\208\159\208\190\208\178\208\181\208\187\208\184\209\130\208\181\208\187\208\184 \208\146\208\190\208\180\209\139 \208\147\208\184\208\180\209\128\208\176\208\186\209\129\208\184\209\129\208\176" },
  koKR = { "\237\134\160\235\165\168 \235\140\128\236\158\165\236\161\176\237\149\169",
           "\237\158\136\235\147\156\235\157\189\236\139\156\236\149\136 \235\172\188\236\157\152 \234\181\176\236\163\188" },
  zhCN = { "\231\145\159\233\147\182\229\133\132\229\188\159\228\188\154",
           "\230\181\183\232\190\190\229\184\140\228\186\154\230\176\180\229\133\131\231\180\160" },
  zhTW = { "\231\145\159\233\138\128\229\133\132\229\188\159\230\156\131",
           "\230\181\183\233\129\148\229\184\140\228\186\158\230\176\180\229\133\131\231\180\160" },
}

T.test("widths: the reputation row in every theme and language: usual names whole, the value never cut", function()
  local FM = dofile(Stub.ROOT .. "tests/fontmetrics.lua")
  local Width = FM.New(Stub.ROOT)
  local restore = FM.Install(Stub, Width)
  local ok, err = pcall(function()
    local bad, cut = {}, 0
    for _, code in ipairs(ALL) do
      Stub.Reset()
      Stub.player.level, Stub.player.xp = 20, 10115
      Stub.player.max = Stub.xpTable[20] or 23200
      local ns, f = Start({ theme = "futuriste", locale = code, watched = Friendly() })
      ns.Core.SetSetting("widget.locked", true)
      for _, key in ipairs(KEYS) do
        if key ~= "actuel" then
          ns.Core.SetSetting("theme", key)
          Stub.Advance(1)
          local tt = ns.Themes.Active().tt
          for which = 1, 2 do
            local name = NAMES[code][which]
            for r = 1, 7 do
              local t = Stub.REP_THRESHOLDS[r]
              Stub.WatchFaction({ name = name, factionID = 69, reaction = r, min = t[1], max = t[2], value = t[2] - 1 })
              ns.Tooltip.ShowFor(f)
              Stub.Advance(1)
              local tf = ns.TooltipFrame.frame
              local inner = tf:GetWidth() - tt.pad[1] - tt.pad[2]
              local row = FindRow(TipRows(ns), name)
              if not row then
                bad[#bad + 1] = format("%s %s %d: no row", key, code, r)
              else
                local lw = row.row.left:GetUnboundedStringWidth()
                local rw = row.row.right:GetUnboundedStringWidth()
                local bounded = (rawget(row.row.left, "_width") or 0) > 0
                if rw + tt.gap + 40 > inner + 0.5 then
                  bad[#bad + 1] = format("%s %s %d: the value %q (%.0f px) leaves no room in %.0f", key, code, r,
                    row.right, rw, inner)
                end
                if which == 1 and (bounded or lw + tt.gap + rw > inner + 0.5) then
                  bad[#bad + 1] = format("%s %s %d: %q cut (%.0f + %.0f > %.0f)", key, code, r, name, lw, rw, inner)
                end
                if which == 2 and bounded then
                  -- cut only when the whole row is wider than the tooltip may be
                  if lw + tt.gap + rw <= inner - 1 then
                    bad[#bad + 1] = format("%s %s %d: the long name is cut but fits", key, code, r)
                  end
                  cut = cut + 1
                end
                if tf:GetWidth() > tt.width[2] then
                  bad[#bad + 1] = format("%s %s: tooltip %.0f wider than %d", key, code, tf:GetWidth(), tt.width[2])
                end
              end
              ns.Tooltip.Hide()
            end
          end
        end
      end
      if #Stub.errors > 0 then bad[#bad + 1] = code .. ": " .. tostring(Stub.errors[1]) end
    end
    if os.getenv and os.getenv("TP_LIST_WIDTHS") then
      for i = 1, #bad do print("  reputation row: " .. bad[i]) end
      print(format("  reputation row: the extreme names are cut (with ...) in %d cases", cut))
    end
    T.eq(bad, {}, "reputation rows")
  end)
  restore()
  if not ok then error(err, 0) end
end)
