-- tests/test_rep_detail.lua - the reputation bar's second lot: the rate engine of the
-- followed faction (Reputation.lua: gains between reads, losses left out, a new faction
-- starts over, frozen past C.XP_STALL, warm-up, exclusion masks, char.rep persisted and
-- repaired, nothing written in read-only mode), the faction chosen in TruePlayed and the
-- picker's walk of the game's list (headers expanded, read, collapsed again; our own
-- UPDATE_FACTION burst ignored), the detailed tooltip (Tooltip.FillRep: standings, rate,
-- time to the next standing; themed and native), its hover region (Bar.lua), the main bar
-- mode (widget.main = "rep") in every theme, the tokens reph / rep_eta and the options'
-- Reputation page (RepOptions.lua). The stub (tests/stub_reputation.lua) watches no
-- faction unless a test says so; Friendly is 3000 .. 9000 there.
local Stub, T = ...

local format, floor = string.format, math.floor

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }

-- Friendly, 1,200 of 6,000 into it (20 %).
local function Friendly(value)
  return { name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = value or 4200 }
end

local function Neutral(value)
  return { name = "Darnassus", factionID = 69, reaction = 4, min = 0, max = 3000, value = value or 2500 }
end

local function Exalted()
  return { name = "Darnassus", factionID = 69, reaction = 8, min = 42000, max = 42999, value = 42999 }
end

-- Loads the addon (widget shown); opts: theme, watched, api, ui, xp, rest, level, db, main.
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI(opts.ui or { ldb = false })
  if opts.theme then Stub.theme = opts.theme end
  if opts.api then Stub.SetRepAPI(opts.api) end
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  if opts.tree then Stub.SetFactions(Stub.REP_TREE()) end
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
  if opts.main then ns.Core.SetSetting("widget.main", opts.main) end
  return ns, ns.Bar.frame, ns.Bar.frame and ns.Bar.frame.tp
end

local function Rgb(r, g, b)
  return { floor(r * 1000 + 0.5), floor(g * 1000 + 0.5), floor(b * 1000 + 0.5) }
end

local function Vertex(t)
  local r, g, b = t:GetVertexColor()
  return Rgb(r, g, b)
end

-- The strip as drawn: nil when hidden, else { x, y, w, h, fill, color }.
local function Strip(tp)
  local rep = tp.rep
  if not rep or not rep.bg:IsShown() then return nil end
  local _, _, _, x, y = rep.bg:GetPoint(1)
  local fill = rep.fill:IsShown() and rep.fill:GetWidth() or 0
  local col = rep.fill:IsShown() and Vertex(rep.fill) or nil
  return { x = x, y = y, w = rep.bg:GetWidth(), h = rep.bg:GetHeight(), fill = fill, color = col }
end

-- Rows of block 1 of the themed tooltip: { left, right, kind, row }.
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

local function NativeLines()
  local out = {}
  for i, l in ipairs(GameTooltip._lines) do out[i] = { left = l[1], right = l[2], color = GameTooltip._colors[i] } end
  return out
end

local function CountMsg(ns, msg)
  local box = { n = 0 }
  ns.RegisterMessage(msg, box, function() box.n = box.n + 1 end)
  return box
end

---------------------------------------------------------------------------
-- The rate engine
---------------------------------------------------------------------------

T.test("rep rate: the first read is a base, gains between reads count, losses do not", function()
  local ns = Start({ watched = Friendly() })
  local R = ns.Rep
  local r = ns.char.rep
  T.ok(type(r) == "table" and r.f == 69 and r.v == 4200, "a base at the first read")
  T.eq(r.e[1].a, 0, "nothing gained yet")
  T.eq(R.SessionGain(), 0)
  Stub.GainRep(100)
  T.eq(r.v, 4300)
  for m = 1, 8 do T.near(r.e[m].a, 100, 1e-9, "every mask gains") end
  Stub.GainRep(-50)                                -- a loss: the base moves, nothing counted
  T.eq(r.v, 4250)
  T.near(r.e[1].a, 100, 1e-9, "a loss does not count")
  Stub.GainRep(80)
  T.near(r.e[1].a, 180, 1e-9, "the gain from the lower base")
  T.eq(R.SessionGain(), 180)
  -- an event that changes nothing: nothing counted
  Stub.Fire("UPDATE_FACTION")
  T.near(r.e[1].a, 180, 1e-9)
  -- never parsed from the chat
  Stub.Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Darnassus increased by 9999.")
  T.near(r.e[1].a, 180, 1e-9, "the chat is never read")
end)

T.test("rep rate: warm-up (nodata, warming, ok), decay with settings.rateTau, the time to the next standing", function()
  local ns = Start({ watched = Friendly() })
  local R, C = ns.Rep, ns.C
  local reph, status, left = R.Rate(0)
  T.eq({ reph, status, left }, { nil, "nodata", 0 }, "no gain yet: it takes a gain, not time")
  Stub.Advance(60)
  Stub.GainRep(50)
  reph, status, left = R.Rate(0)
  T.eq(status, "nodata")
  T.ok(reph == nil and left > 400 and left < C.WARMUP_FULL, "counted seconds still needed")
  for _ = 1, 2 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  reph, status = R.Rate(0)
  T.eq(status, "warming")
  T.ok(reph ~= nil and reph > 0, "a value while warming up")
  for _ = 1, 10 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  local ps
  reph, status, left, _, ps = R.Rate(0)
  T.eq(status, "ok")
  T.eq(left, 0)
  local x = ns.char.rep.e[1]
  T.near(reph, 3600 * x.a / x.d, 1e-6, "points per counted hour")
  T.ok(reph > 2000 and reph < 3500, format("about 3,000 per hour (%.0f)", reph))
  -- decay: the EMA's counted seconds follow tau (3600 s by default)
  T.ok(x.d > 700 and x.d < 13 * 60, format("decayed counted seconds %.1f", x.d))
  -- time to the next standing: what is left of Friendly at that rate
  local eta, est, nxt = R.Eta(0)
  T.eq(nxt, 6)
  T.eq(est, "ok")
  T.near(eta, (9000 - ns.Rep.Detail()) / ps, 1e-6)
  -- Exalted: no next standing
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 8, min = 42000, max = 42999, value = 42500 })
  eta, est, nxt = R.Eta(0)
  T.eq({ eta, est, nxt }, { nil, "max", nil })
end)

T.test("rep rate: frozen after C.XP_STALL counted seconds without a gain; AFK time is not counted", function()
  local ns = Start({ watched = Friendly() })
  local R, C = ns.Rep, ns.C
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  local r = ns.char.rep
  T.eq(r.n, 0, "a gain resets the count")
  -- AFK: not time without a gain
  Stub.SetAFK(true)
  Stub.Advance(C.XP_STALL + 120)
  T.eq(r.n, 0, "AFK time does not count")
  local afkMask = C.MASK_AFK
  local dAll, dAfk = r.e[1].d, r.e[afkMask + 1].d
  Stub.Advance(60)
  T.ok(r.e[1].d > dAll, "mask 0 counts AFK time")
  T.eq(r.e[afkMask + 1].d, dAfk, "the AFK-excluded mask does not")
  Stub.SetAFK(false)
  Stub.Advance(C.XP_STALL + 30)
  local reph, status, _, stall = R.Rate(0)
  T.eq(status, "stalled")
  T.ok(stall > C.XP_STALL)
  local a, d = r.e[1].a, r.e[1].d
  Stub.Advance(300)
  T.eq({ r.e[1].a, r.e[1].d }, { a, d }, "frozen: neither decays nor grows")
  T.eq((R.Rate(0)), reph)
  -- the next gain resumes it (it remembers more than this gain: kept)
  Stub.GainRep(20)
  T.eq(r.n, 0)
  T.near(r.e[1].a, a + 20, 1e-9)
  T.eq(select(2, R.Rate(0)), "ok")
end)

T.test("rep rate: after a long stall an EMA that remembers less than the gain starts over", function()
  local ns = Start({ watched = Friendly() })
  local C = ns.C
  Stub.Advance(60)
  Stub.GainRep(5)
  Stub.Advance(C.XP_STALL + 600)
  local r = ns.char.rep
  T.ok(r.n > C.XP_STALL)
  Stub.GainRep(300)
  T.eq({ r.e[1].a, r.e[1].d }, { 300, 0 }, "restarted: the idle time does not dilute the new rate")
end)

T.test("rep rate: another faction takes a new base and starts over; the session gain follows", function()
  local ns = Start({ watched = Friendly() })
  local R = ns.Rep
  for _ = 1, 3 do
    Stub.Advance(60)
    Stub.GainRep(40)
  end
  T.eq(R.SessionGain(), 120)
  Stub.WatchFaction({ name = "Argent Dawn", factionID = 529, reaction = 4, min = 0, max = 3000, value = 1500 })
  local r = ns.char.rep
  T.eq({ r.f, r.v, r.e[1].a, r.e[1].d, r.s }, { 529, 1500, 0, 0, 0 }, "a new base, nothing carried over")
  T.eq(R.SessionGain(), 0)
  Stub.GainRep(25)
  T.eq(R.SessionGain(), 25)
  -- back to the first one: a new base again
  Stub.WatchFaction(Friendly(4320))
  T.eq({ r.f, r.v, r.e[1].a }, { 69, 4320, 0 })
end)

T.test("rep rate: persisted in char.rep, a new base after a reload, repaired, reset with the XP rate", function()
  local ns = Start({ watched = Friendly() })
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  local a = ns.char.rep.e[1].a
  local ns2 = Stub.Restart({ settle = 3 })
  local r = ns2.char.rep
  T.ok(type(r) == "table" and r.f == 69, "kept across a reload")
  T.near(r.e[1].a, a, 1, "the EMA kept")
  -- played elsewhere: the next read is a base, not a gain
  Stub.WatchFaction(Friendly(6000))
  T.eq(r.v, 6000)
  T.near(r.e[1].a, a, 1, "no gain from what changed while away")
  Stub.GainRep(10)
  T.ok(r.e[1].a > a, "gains count again")
  -- repair of a damaged record
  local Core = ns2.Core
  local rec = { rep = { id = -3, f = "x", v = 12, e = { { a = -1, d = 5 } }, n = -2, s = "y", t = {} } }
  Core.RepairChar(rec)
  T.eq(rec.rep, { n = 0 }, "every bad field dropped")
  rec = { rep = { id = 529, f = 69, v = 4200, e = {}, n = 30, s = 12, t = 5 } }
  for i = 1, 8 do rec.rep.e[i] = { a = 1, d = 2 } end
  rec.rep.e.junk = true
  Core.RepairChar(rec)
  T.eq(rec.rep.id, 529)
  T.eq(rec.rep.e.junk, nil, "stray keys of e dropped")
  T.eq(#rec.rep.e, 8)
  rec = { rep = 5 }
  Core.RepairChar(rec)
  T.eq(rec.rep, nil)
  -- /tpl reset rate: both rates start over
  T.ok(Core.ResetRate())
  T.eq({ r.e[1].a, r.e[1].d }, { 0, 0 })
end)

T.test("rep rate: read-only mode writes nothing, refuses a choice and a reset", function()
  local ns = Start({ watched = Friendly(),
                     db = { schema = 99, settings = { firstRunDone = true }, chars = {} } })
  T.ok(ns.readOnly)
  T.eq(ns.char.rep, nil, "no record written")
  Stub.Advance(60)
  Stub.GainRep(100)
  T.eq(ns.char.rep, nil)
  T.ok(ns.Rep.Has(), "the faction is still shown")
  T.no(ns.Rep.SetChosen(529))
  T.no(ns.Rep.ResetRate())
  local kb = T.alloc(function() ns.Rep.Advance(1, "w") end, 1000)
  T.ok(kb < 0.1)
end)

T.test("rep rate: Advance and the getters allocate nothing", function()
  local ns = Start({ watched = Friendly() })
  local R = ns.Rep
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  local function Calls()
    R.Advance(1, "w")
    R.Rate(0)
    R.Eta(1)
    R.SessionGain()
    R.Get()
    R.Detail()
    R.Needed(7)
    R.ColorArray(5)
  end
  Calls()                                          -- the colour arrays are cached once
  local kb = T.alloc(Calls, 5000)
  T.ok(kb < 0.1, format("%.3f KB", kb))
end)

T.test("rep rate: ResetChar keeps the chosen faction and wipes the rest", function()
  local ns = Start({ watched = Friendly(), tree = true })
  T.ok(ns.Rep.SetChosen(529))
  Stub.GainRepID(529, 30)
  T.ok(ns.char.rep.e[1].a > 0)
  T.ok(ns.Core.ResetChar())
  T.eq(ns.char.rep.id, 529, "the choice is a setting")
  local r = ns.char.rep
  T.eq(r.f, 529, "measured again at once: a new base")
  T.eq(r.e[1].a, 0)
end)

---------------------------------------------------------------------------
-- The faction chosen in TruePlayed, the picker's list
---------------------------------------------------------------------------

T.test("chosen faction: read by ID, the game's watched one untouched, the fallback said", function()
  local ns = Start({ watched = Friendly(), tree = true })
  local R = ns.Rep
  local changed = CountMsg(ns, "REP_CHANGED")
  T.eq(R.Chosen(), nil)
  local _, _, _, _, id, src, fb = R.Detail()
  T.eq({ id, src, fb }, { 69, "game", false })
  T.ok(R.SetChosen(529))
  T.eq(ns.char.rep.id, 529)
  T.eq((R.Get()), "Argent Dawn")
  _, _, _, _, id, src, fb = R.Detail()
  T.eq({ id, src, fb }, { 529, "chosen", false })
  T.ok(changed.n >= 1, "REP_CHANGED")
  T.eq(Stub.rep.watched.factionID, 69, "the game's choice is never changed")
  -- the game's watched faction changes: the chosen one stays
  Stub.WatchFaction(Friendly(5000))
  T.eq((R.Get()), "Argent Dawn")
  -- gains of the chosen faction count
  Stub.GainRepID(529, 75)
  T.eq(R.SessionGain(), 75)
  -- unreadable: the game's instead, and the detail says so
  Stub.rep.missing[529] = true
  Stub.Fire("UPDATE_FACTION")
  T.eq((R.Get()), "Darnassus")
  _, _, _, _, id, src, fb = R.Detail()
  T.eq({ id, src, fb }, { 69, "game", true })
  Stub.rep.missing[529] = nil
  Stub.Fire("UPDATE_FACTION")
  T.eq((R.Get()), "Argent Dawn")
  -- invalid IDs refused
  for _, bad in ipairs({ 0, -1, 1.5, "529", true }) do T.no(R.SetChosen(bad), tostring(bad)) end
  -- back to the game's
  T.ok(R.SetChosen(nil))
  T.eq(ns.char.rep.id, nil)
  T.eq((R.Get()), "Darnassus")
  -- per character, persisted
  R.SetChosen(21)
  local ns2 = Stub.Restart({ settle = 3 })
  T.eq(ns2.char.rep.id, 21)
end)

T.test("chosen faction: Classic Era's GetFactionInfoByID", function()
  local ns = Start({ watched = Friendly(), api = "era", tree = true })
  local R = ns.Rep
  T.ok(R.SetChosen(21))
  local name, react = R.Get()
  T.eq({ name, react }, { "Booty Bay", 7 })
  Stub.rep.missing[21] = true
  Stub.Fire("UPDATE_FACTION")
  T.eq((R.Get()), "Darnassus", "the game's instead")
  T.eq(select(7, R.Detail()), true)
end)

local function Names(groups)
  local out = {}
  for _, g in ipairs(groups) do
    local items = {}
    for _, it in ipairs(g.items) do items[#items + 1] = format("%s/%d/%s", it.name, it.id, tostring(it.reaction)) end
    out[#out + 1] = { name = g.name, items = items }
  end
  return out
end

for _, api in ipairs({ "forever", "era" }) do
  T.test("faction list (" .. api .. "): collapsed headers expanded, read, collapsed again; our burst ignored", function()
    local ns = Start({ watched = Friendly(), api = api, tree = true })
    local R = ns.Rep
    local tree = Stub.rep.factions
    local readsBefore = Stub.calls.GetWatchedFactionData + Stub.calls.GetWatchedFactionInfo
    local changed = CountMsg(ns, "REP_CHANGED")
    local groups = R.ListFactions()
    T.eq(Names(groups), {
      { name = "Classic", items = { "Stormwind/72/5", "Darnassus/69/6", "Argent Dawn/529/4" } },
      { name = "Inactive", items = { "Booty Bay/21/7" } },
    })
    T.eq(tree[1].collapsed, nil, "an open header stays open")
    T.eq(tree[1].children[1].collapsed, true, "the sub-header collapsed again")
    T.eq(tree[2].collapsed, true, "Inactive collapsed again")
    T.eq({ Stub.calls.Expand, Stub.calls.Collapse }, { 2, 2 })
    T.no(R.IsBusy())
    local reads = Stub.calls.GetWatchedFactionData + Stub.calls.GetWatchedFactionInfo - readsBefore
    T.eq(reads, 1, "one read after the walk, none during its burst")
    T.eq(changed.n, 0, "nothing shown changed")
    -- a header the player left open is not touched; a sub-header with its own reputation is
    -- a choice
    tree[2].collapsed = false
    tree[1].children[1].factionID = 469
    tree[1].children[1].value = 100
    Stub.calls.Expand, Stub.calls.Collapse = 0, 0
    groups = R.ListFactions()
    T.eq(Names(groups)[1].items[1], "Alliance/469/4")
    T.eq(tree[2].collapsed, false)
    T.eq({ Stub.calls.Expand, Stub.calls.Collapse }, { 1, 1 })
  end)
end

T.test("faction list: a client without the list functions, and an empty list", function()
  local ns = Start({ watched = Friendly(), api = "none" })
  T.eq(ns.Rep.ListFactions(), {})
  Stub.Reset()
  local ns2 = Start({ watched = Friendly() })
  T.eq(ns2.Rep.ListFactions(), {})
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- The detailed tooltip and its hover region
---------------------------------------------------------------------------

T.test("rep tooltip (themed): the faction, its 8 standings, the rate, the hint", function()
  local ns, _, tp = Start({ theme = "druid", watched = Friendly() })
  local L = ns.L
  local hit = tp.repHit
  T.ok(hit ~= nil and hit:IsShown(), "the hover region")
  Stub.RunScript(hit, "OnEnter")
  Stub.Advance(1)
  T.ok(ns.Tooltip.IsShownFor(hit))
  local rows = TipRows(ns)
  T.eq(rows[1].left, L.ADDON_TITLE)
  T.eq(FindRow(rows, L.TT_SECTION_REP).kind, "section")
  T.eq(FindRow(rows, "Darnassus").kind, "header")
  local cur = FindRow(rows, "Friendly · 1,200 / 6,000 (20.0%)")
  T.ok(cur ~= nil, "the standing and the points")
  T.eq(Rgb(cur.row.left:GetTextColor()), Rgb(ns.Rep.Color(5)), "in the standing's colour")
  T.ok(FindRow(rows, format(L.TT_REP_TO_NEXT_FMT, "4,800", "Honored")) ~= nil, "the points to Honored")
  T.eq(FindRow(rows, L.TT_REP_STANDINGS).kind, "header")
  local dim = ns.Themes.Active().tt.colors.dim
  for _, name in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral" }) do
    local r = FindRow(rows, name)
    T.eq(r.right, L.TT_REP_REACHED, name .. " reached")
    T.eq(Rgb(r.row.left:GetTextColor()), Rgb(dim[1], dim[2], dim[3]), name .. " dimmed")
  end
  local c = FindRow(rows, format(L.TT_REP_CURRENT_FMT, "Friendly"))
  T.eq(c.right, "20.0%", "the current one marked, its percent")
  T.eq(Rgb(c.row.right:GetTextColor()), Rgb(ns.Rep.Color(5)))
  T.eq(FindRow(rows, "Honored").right, format(L.TT_REP_AHEAD_FMT, "4,800"))
  T.eq(FindRow(rows, "Revered").right, format(L.TT_REP_AHEAD_FMT, "16,800"))
  T.eq(FindRow(rows, "Exalted").right, format(L.TT_REP_AHEAD_FMT, "37,800"))
  T.eq(FindRow(rows, L.TT_REPH).right, L.TT_REP_NODATA)
  T.eq(FindRow(rows, L.TT_REP_NEXT).right, L.TT_NO_RATE)
  T.eq(FindRow(rows, L.TT_REP_SESSION).right, "0")
  T.eq(rows[#rows].left, L.TT_REP_HINT)
  T.eq(rows[#rows].kind, "hint")
  -- with a rate: per hour, the time to each next standing
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  Stub.Advance(1)
  rows = TipRows(ns)
  local reph, status, _, _, ps = ns.Rep.Rate(0)
  T.eq(status, "ok")
  local Fmt = ns.Fmt
  T.eq(FindRow(rows, L.TT_REPH).right, Fmt.Rate(reph))
  T.eq(FindRow(rows, L.TT_REP_NEXT).right, Fmt.ETA(4200 / ps))
  T.eq(FindRow(rows, "Honored").right, format(L.TT_REP_AHEAD_ETA_FMT, "4,200", Fmt.ETA(4200 / ps)))
  T.eq(FindRow(rows, "Exalted").right, format(L.TT_REP_AHEAD_ETA_FMT, "37,200", Fmt.ETA(37200 / ps)))
  T.eq(FindRow(rows, L.TT_REP_SESSION).right, format(L.TT_REP_GAIN_FMT, "600"))
  -- frozen: the mark and the notes
  Stub.Advance(ns.C.XP_STALL + 60)
  rows = TipRows(ns)
  T.match(FindRow(rows, L.TT_REPH).right, "%*$")
  T.ok(FindRow(rows, L.TT_REP_STALLED_RESUME) ~= nil, "why it is frozen")
  -- the hover ends: hidden
  Stub.RunScript(hit, "OnLeave")
  T.no(ns.Tooltip.IsShownFor(hit))
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("rep tooltip: Exalted, a female character, the fallback note, no faction, Classic (GameTooltip)", function()
  local ns, _, tp = Start({ theme = "futuriste", watched = Exalted(), tree = true })
  local L = ns.L
  Stub.RunScript(tp.repHit, "OnEnter")
  Stub.Advance(1)
  local rows = TipRows(ns)
  T.ok(FindRow(rows, "Exalted") ~= nil, "the standing alone")
  T.eq(FindRow(rows, format(L.TT_REP_CURRENT_FMT, "Exalted")).right, L.TT_REP_TOP)
  for _, name in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered" }) do
    T.eq(FindRow(rows, name).right, L.TT_REP_REACHED, name)
  end
  T.eq(FindRow(rows, L.TT_REP_NEXT), nil, "no next standing")
  -- female labels
  Stub.rep.sex = 3
  Stub.WatchFaction(Friendly())
  Stub.Advance(1)
  rows = TipRows(ns)
  T.ok(FindRow(rows, format(L.TT_REP_CURRENT_FMT, "Friendly (f)")) ~= nil, "the _FEMALE label")
  T.ok(FindRow(rows, "Friendly (f) · 1,200 / 6,000 (20.0%)") ~= nil)
  Stub.rep.sex = 2
  -- the chosen faction cannot be read: said
  ns.Rep.SetChosen(529)
  Stub.rep.missing[529] = true
  Stub.Fire("UPDATE_FACTION")
  Stub.Advance(1)
  T.ok(FindRow(TipRows(ns), L.TT_REP_FALLBACK) ~= nil, "the fallback note")
  Stub.RunScript(tp.repHit, "OnLeave")
  -- Classic: the shared GameTooltip, the same content
  Stub.Reset()
  local ns2, _, tp2 = Start({ theme = "actuel", watched = Friendly() })
  Stub.RunScript(tp2.repHit, "OnEnter")
  Stub.Advance(1)
  local lines = NativeLines()
  local function Has(left, right)
    for _, l in ipairs(lines) do
      if l.left == left and (right == nil or l.right == right) then return l end
    end
    return nil
  end
  T.ok(Has(L.ADDON_TITLE) ~= nil)
  T.ok(Has(L.TT_SECTION_REP) ~= nil)
  T.ok(Has("Darnassus") ~= nil)
  local cur = Has("Friendly · 1,200 / 6,000 (20.0%)")
  T.ok(cur ~= nil)
  T.eq(Rgb(cur.color[1], cur.color[2], cur.color[3]), Rgb(ns2.Rep.Color(5)))
  T.ok(Has(format(L.TT_REP_CURRENT_FMT, "Friendly"), "20.0%") ~= nil)
  T.ok(Has("Neutral", L.TT_REP_REACHED) ~= nil)
  T.ok(Has(L.TT_REPH, L.TT_REP_NODATA) ~= nil)
  T.eq(lines[#lines].left, L.TT_REP_HINT)
  Stub.RunScript(tp2.repHit, "OnLeave")
  -- no faction: a note says how to follow one (Tooltip.FillRep on any tooltip)
  Stub.WatchFaction(nil)
  local tt = Stub.NewTooltip()
  ns2.Tooltip.FillRep(tt)
  local found = false
  for _, l in ipairs(tt._lines) do
    if l[1] == L.TT_REP_NONE then found = true end
  end
  T.ok(found, "the note")
end)

T.test("rep hover region: over the strip's gap, shown with the strip only, clicks and drags on the bar", function()
  local ns, f, tp = Start({ theme = "futuriste", watched = Friendly() })
  local hit = tp.repHit
  local s = Strip(tp)
  local _, rel, _, x, y = hit:GetPoint(1)
  T.ok(rel == f)
  T.eq(x, s.x, "from the track's left edge")
  T.ok(y <= s.y and y + hit:GetHeight() >= s.y + s.h, "covers the strip")
  T.eq(hit:GetWidth(), s.w)
  local _, _, _, _, trackY = tp.tex.track:GetPoint(1)
  T.ok(y + hit:GetHeight() <= trackY + 0.5, "up to the track's bottom edge, not over it")
  local _, _, _, _, rowY = tp.slots[2]:GetPoint(1)
  T.ok(y >= rowY, "above the text row")
  -- the general tooltip on the bar, the detailed one on the region (never both)
  Stub.RunScript(f, "OnEnter")
  T.ok(ns.Tooltip.IsShownFor(f))
  Stub.RunScript(f, "OnLeave")
  Stub.RunScript(hit, "OnEnter")
  T.ok(ns.Tooltip.IsShownFor(hit))
  T.no(ns.Tooltip.IsShownFor(f))
  -- clicks act on the bar
  Stub.RunScript(hit, "OnMouseDown", "LeftButton")
  Stub.RunScript(hit, "OnMouseUp", "LeftButton")
  T.ok(ns.Window.IsShown(), "left click: the statistics window")
  ns.Window.Hide()
  local menus = Stub.ui.menus
  Stub.RunScript(hit, "OnMouseUp", "RightButton")
  T.eq(Stub.ui.menus, menus + 1, "right click: the bar's menu")
  -- a drag moves the bar and hides the detailed tooltip
  Stub.RunScript(hit, "OnEnter")
  Stub.RunScript(hit, "OnMouseDown", "LeftButton")
  Stub.RunScript(hit, "OnDragStart")
  T.eq(rawget(f, "_moving"), true)
  T.no(ns.Tooltip.IsShownFor(hit), "hidden while dragging")
  Stub.RunScript(hit, "OnDragStop")
  T.eq(type(ns.settings.widget.point), "table", "position saved")
  Stub.RunScript(hit, "OnMouseUp", "LeftButton")
  T.no(ns.Window.IsShown(), "a drag is not a click")
  Stub.RunScript(hit, "OnLeave")
  -- no strip: no region
  ns.Core.SetSetting("widget.rep", false)
  T.no(hit:IsShown(), "option off")
  ns.Core.SetSetting("widget.rep", true)
  T.ok(hit:IsShown())
  Stub.WatchFaction(nil)
  T.no(hit:IsShown(), "no faction")
  Stub.WatchFaction(Friendly())
  T.ok(hit:IsShown())
  -- hidden in combat with combatHide; the tooltip goes with it
  ns.Core.SetSetting("widget.combatHide", true)
  Stub.RunScript(hit, "OnEnter")
  Stub.EnterCombat()
  T.no(hit:IsShown(), "combat-hidden")
  T.no(ns.Tooltip.IsShownFor(hit))
  Stub.LeaveCombat()
  T.ok(hit:IsShown())
  ns.Core.SetSetting("widget.shown", false)
  T.no(hit:IsShown(), "bar hidden")
end)

---------------------------------------------------------------------------
-- The main bar mode (widget.main = "rep")
---------------------------------------------------------------------------

-- Fill-span textures of the theme's layers (shown or not), with their width and colour.
local function FillLook(ns, tp)
  local out = {}
  for _, L in ipairs(ns.Themes.Active().bar.layers) do
    local t = tp.tex[L.id] or tp.tex[L.id .. "M"]  -- caps / three: the middle part
    if type(t) == "table" and not t.GetWidth then t = t[1] end   -- nine / ticks: arrays
    if (L.span == "fill" or L.span == "fillEnd") and type(t) == "table" and t.GetWidth then
      local grad = rawget(t, "_grad")
      out[L.id] = { shown = t:IsShown(), w = t:IsShown() and t:GetWidth() or 0,
                    color = { Vertex(t), grad and Rgb(grad[2] or 0, grad[3] or 0, grad[4] or 0) or false } }
    end
  end
  return out
end

local function Widths(look)
  local out = {}
  for id, v in pairs(look) do out[id] = { v.shown, v.w } end
  return out
end

T.test("main bar mode, every theme: the reputation on the track, its colour, its texts, the XP in the strip", function()
  for _, key in ipairs(KEYS) do
    Stub.Reset()
    -- the XP at 20 % of the level, as the reputation (1,200 / 6,000): the same fill
    local max = Stub.xpTable[Stub.player.level]
    local ns, f, tp = Start({ theme = key, watched = Friendly(), xp = max / 5, rest = 0 })
    local L, Skin = ns.L, ns.BarSkin
    local th = ns.Themes.Active()
    local xpLook = FillLook(ns, tp)
    local xpTexts = { tp.bl:GetText(), tp.brx:GetText(), tp.marker:GetText() }
    -- the strip's region ends at the track's bottom edge (x, that edge, the track's width)
    local _, _, _, sx, sy = tp.repHit:GetPoint(1)
    local xpHit = { sx, sy + tp.repHit:GetHeight(), tp.repHit:GetWidth() }
    local h0 = select(2, f:GetSize())
    local themeMsgs = CountMsg(ns, "THEME_CHANGED")
    ns.Core.SetSetting("widget.main", "rep")
    local look = FillLook(ns, tp)
    T.eq(Widths(look), Widths(xpLook), key .. ": the fill of 20 % drawn alike")
    if key == "actuel" or key == "futuriste" then
      T.eq(Vertex(tp.tex.fill or tp.tex.fillM), Rgb(ns.Rep.Color(5)), key .. ": exactly the standing's colour")
    end
    T.eq(themeMsgs.n, 0, key .. ": no THEME_CHANGED")
    -- texts: faction and standing at the left, the points at the right
    local name = Skin.Sub("xp", "Darnassus")
    if th.text.split then
      T.eq(tp.bl:GetText(), name, key .. ": the faction")
      T.eq(tp.blv:GetText(), Skin.Sub("levelValue", "Friendly"), key .. ": its standing")
      T.ok(tp.blv:IsShown())
      local lab = Skin.Sub("xpLabel", L.REP_LABEL)
      T.eq(tp.xpl:GetText(), lab, key .. ": the reputation's label")
    else
      T.eq(tp.bl:GetText(), Skin.Sub("xp", "Darnassus · Friendly"), key .. ": faction · standing")
    end
    local full, short = Skin.Sub("xp", "1,200 / 6,000"), Skin.Sub("xp", "1.2k / 6k")
    local brx = tp.brx:GetText()
    T.ok(tp.brx:IsShown() and (brx == full or brx == short), key .. ": the points " .. tostring(brx))
    T.eq(tp.marker:GetText(), Skin.Sub("marker", "20.0%"), key .. ": the % marker")
    -- the XP in the strip (below max level), in the XP colour
    local s = Strip(tp)
    T.ok(s ~= nil, key .. ": the strip")
    T.eq(s.fill, floor(s.w / 5 + 0.5), key .. ": 20 % of XP")
    local xc = th.colors.xp
    T.eq(s.color, Rgb(xc[1], xc[2], xc[3]), key .. ": the theme's XP colour")
    T.eq(select(2, f:GetSize()), h0, key .. ": the XP strip in the reputation strip's room")
    -- the main track's region: the detailed tooltip
    local hit = tp.repHit
    T.ok(hit:IsShown())
    local _, _, _, hx, hy = hit:GetPoint(1)
    T.eq({ hx, hy, hit:GetWidth() }, xpHit, key .. ": over the track, from its bottom edge")
    T.ok(hit:GetHeight() >= 1)
    -- back to the XP: as before
    ns.Core.SetSetting("widget.main", "xp")
    T.eq(FillLook(ns, tp), xpLook, key .. ": the XP fill and colours again")
    T.eq({ tp.bl:GetText(), tp.brx:GetText(), tp.marker:GetText() }, xpTexts, key .. ": the XP texts again")
    if th.text.split then T.eq(tp.xpl:GetText(), Skin.Sub("xpLabel", L.XP_LABEL)) end
    -- every fill layer exactly as the XP mode draws it with the standing's colour as the XP
    -- colour (the theme's own expressions of `base`, every layer and gradient stop)
    local cr, cg, cb = ns.Rep.Color(5)
    ns.Core.SetSetting("widget.xpColor", { cr, cg, cb })
    T.eq(look, FillLook(ns, tp), key .. ": every fill layer in the standing's colour")
    ns.Core.SetSetting("widget.xpColor", false)
    T.eq(FillLook(ns, tp), xpLook, key .. ": the theme's colours again")
    T.eq(Stub.errors, {}, key)
  end
end)

T.test("main bar mode: a new standing recolours without closing a tooltip; Exalted full and dimmed", function()
  local ns, f, tp = Start({ theme = "futuriste", watched = Neutral(), main = "rep" })
  T.eq(Vertex(tp.tex.fill), Rgb(ns.Rep.Color(4)), "Neutral's colour")
  ns.Tooltip.ShowFor(f)
  Stub.Advance(1)
  Stub.GainRep(1000)                               -- Neutral -> Friendly
  T.eq(Vertex(tp.tex.fill), Rgb(ns.Rep.Color(5)), "Friendly's colour")
  T.ok(ns.Tooltip.IsShownFor(f), "the open tooltip stays")
  ns.Tooltip.Hide()
  -- Exalted: full width, dimmed like the max level, no points, no marker
  Stub.WatchFaction(Exalted())
  T.eq(tp.tex.fill:GetWidth(), 360)
  local _, _, _, a = tp.tex.fill:GetVertexColor()
  T.near(a, ns.Themes.Active().bar.maxAlpha, 1e-6, "dimmed")
  T.eq(tp.bl:GetText(), ns.BarSkin.Sub("xp", "Darnassus"))
  T.eq(tp.blv:GetText(), ns.BarSkin.Sub("levelValue", "Exalted"))
  T.no(tp.brx:IsShown(), "no points")
  T.no(tp.marker:IsShown(), "no marker")
  -- no faction any more: the XP again, the theme's colour
  Stub.WatchFaction(nil)
  T.eq(Vertex(tp.tex.fill), Rgb(1, 0x2b / 255, 0xd6 / 255), "the theme's own fill colour")
  T.match(tp.bl:GetText(), "LEVEL")
  -- a user XP colour reaches the strip in the reputation mode
  Stub.WatchFaction(Friendly())
  ns.Core.SetSetting("widget.xpColor", { 0, 1, 0 })
  T.eq(Strip(tp).color, Rgb(0, 1, 0))
  T.eq(Vertex(tp.tex.fill), Rgb(ns.Rep.Color(5)), "the fill keeps the standing's colour")
end)

T.test("main bar mode: at max level no strip, never hidden by hideAtMax while it shows the reputation", function()
  local ns, f, tp = Start({ theme = "druid", watched = Friendly(), level = 60, main = "rep" })
  T.ok(ns.Tracker.IsMax())
  T.eq(Strip(tp), nil, "no XP strip at max level")
  T.eq(tp.bl:GetText(), ns.BarSkin.Sub("xp", "Darnassus"))
  ns.Core.SetSetting("widget.hideAtMax", true)
  T.ok(f:IsShown(), "shown: it shows the reputation")
  Stub.WatchFaction(nil)
  T.no(f:IsShown(), "no faction: the XP mode's hideAtMax")
  Stub.WatchFaction(Friendly())
  T.ok(f:IsShown(), "back with the faction")
  ns.Core.SetSetting("widget.main", "xp")
  T.no(f:IsShown(), "the XP mode hides it at max level")
  ns.Core.SetSetting("widget.main", "rep")
  T.ok(f:IsShown())
  T.eq(Stub.errors, {})
end)

T.test("main bar mode: the XP strip comes and goes with the max level; caches follow the mode", function()
  local p = Stub.player
  local ns, f, tp = Start({ theme = "warrior", watched = Friendly(), level = 59, main = "rep" })
  T.ok(Strip(tp) ~= nil, "the XP strip below max level")
  local h = select(2, f:GetSize())
  Stub.GrantXP(p.max - p.xp + 10)                  -- level 60: max level
  Stub.Advance(2)
  T.ok(ns.Tracker.IsMax())
  T.eq(Strip(tp), nil, "no strip at max level")
  T.ok(select(2, f:GetSize()) <= h)
  -- the bar's tick: nothing allocated, no read, no OnUpdate
  Stub.Advance(120)
  local reads = Stub.calls.GetWatchedFactionData
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 2, format("reputation main bar: %.2f KB over 600 ticks", kb))
  T.eq(Stub.calls.GetWatchedFactionData, reads, "no read on TICK")
  T.eq(Stub.onUpdateCount, 0)
end)

---------------------------------------------------------------------------
-- Tokens
---------------------------------------------------------------------------

T.test("tokens reph / rep_eta: the rate, the time to the next standing, Exalted, none, at max level", function()
  local ns = Start({ watched = Friendly(), level = 60 })
  local Tokens, L, Fmt = ns.Tokens, ns.L, ns.Fmt
  Tokens.Acquire("test", 3)
  local text, dim = Tokens.Render("reph")
  T.eq({ text, dim }, { L.DOTS, true }, "no rate yet")
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  Tokens.UpdateContext()
  local reph, _, _, _, ps = ns.Rep.Rate(0)
  text, dim = Tokens.Render("reph")
  T.eq(text, format(L.PFX_REPH_FMT, Fmt.Rate(reph)))
  T.no(dim)
  text = Tokens.Render("rep_eta")
  T.eq(text, format(L.REP_ETA_FMT, "Honored", Fmt.ETA(4200 / ps)))
  -- not XP tokens: kept at max level in a slot of the bar (an XP token gives way to its
  -- max-level slot there), and shown in a max-level slot
  ns.Core.SetSetting("widget.maxSlots.1", "session")
  ns.Core.SetSetting("widget.slots.1", "reph")
  T.eq(Tokens.Resolve(1), "reph", "kept at max level")
  ns.Core.SetSetting("widget.slots.1", "rep_eta")
  T.eq(Tokens.Resolve(1), "rep_eta", "kept at max level")
  ns.Core.SetSetting("widget.slots.1", "xph")
  T.eq(Tokens.Resolve(1), "session", "an XP token gives way (the check above means something)")
  ns.Core.SetSetting("widget.maxSlots.1", "reph")
  T.eq(Tokens.Resolve(1), "reph")
  -- frozen
  Stub.Advance(ns.C.XP_STALL + 30)
  text, dim = Tokens.Render("reph")
  T.match(text, "%*$")
  T.ok(dim)
  -- Exalted
  Stub.WatchFaction(Exalted())
  Tokens.UpdateContext()
  text, dim = Tokens.Render("rep_eta")
  T.eq({ text, dim }, { "Exalted", true })
  -- no faction
  Stub.WatchFaction(nil)
  Tokens.UpdateContext()
  T.eq({ Tokens.Render("rep_eta") }, { L.DOTS, true, false })
  -- a token in a slot turns the reads on, even with the strip off
  ns.Core.SetSetting("widget.rep", false)
  Stub.WatchFaction(Friendly())
  T.ok(ns.Rep.Has(), "read for the token")
  ns.Core.SetSetting("widget.maxSlots.1", "session")
  T.no(ns.Rep.Has(), "nothing shows it: no reads")
end)

---------------------------------------------------------------------------
-- The options' Reputation page
---------------------------------------------------------------------------

local function Page()
  local sub = Stub.ui.subcategories[1]
  Settings.OpenToCategory(sub.ID)
  return rawget(sub.frame, "controls"), sub
end

T.test("options: the Reputation page (subcategory), its controls, helps, refresh and IsShown", function()
  local ns, f = Start({ theme = "futuriste", ui = { modern = true }, watched = Friendly(), tree = true })
  local L = ns.L
  ns.Options.Open()
  T.ok(ns.Options.IsShown())
  local page, sub = Page()
  T.eq(sub.name, L.OPT_REP_PAGE)
  T.ok(rawget(Stub.ui.categories[1].frame, "_shown") ~= true, "the main page hidden")
  T.ok(ns.Options.IsShown(), "the page counts as the options shown (AutoReload)")
  local kinds = {}
  for path, rec in pairs(page) do kinds[path] = rec.kind end
  T.eq(kinds, { ["widget.rep"] = "check", ["help.rep"] = "help", ["widget.main"] = "dropdown",
                ["help.repMain"] = "help", ["rep.faction"] = "faction", ["help.repFaction"] = "help",
                ["rep.resetRate"] = "button" })
  T.ok(page["widget.rep"].index < page["widget.main"].index and page["widget.main"].index < page["rep.faction"].index
       and page["rep.faction"].index < page["rep.resetRate"].index, "in this order")
  -- the main bar dropdown
  local dd = page["widget.main"]
  T.eq({ dd.choices[1].value, dd.choices[1].label, dd.choices[2].value, dd.choices[2].label },
       { "xp", L.REP_MAIN_XP, "rep", L.REP_MAIN_REP })
  Stub.ui.ClickMenuItem(Stub.ui.FindMenuItem(dd.widget._root, L.REP_MAIN_REP))
  T.eq(ns.settings.widget.main, "rep")
  T.eq(f.tp.bl:GetText(), ns.BarSkin.Sub("xp", "Darnassus"), "the bar follows")
  -- helps
  local function Lines(rec)
    Stub.RunScript(rec.widget, "OnEnter")
    local out = {}
    for i, l in ipairs(GameTooltip._lines) do out[i] = l[1] end
    Stub.RunScript(rec.widget, "OnLeave")
    return out
  end
  T.eq(Lines(page["help.repMain"]), { L.OPT_REP_MAIN, L.OPT_REP_MAIN_HELP_WHAT,
    format(L.OPT_REP_MAIN_HELP_XP_FMT, L.OPT_HIDE_MAX), L.OPT_REP_MAIN_HELP_NONE })
  T.eq(Lines(page["help.repFaction"]), { L.OPT_REP_FACTION,
    format(L.OPT_REP_FACTION_HELP_AUTO_FMT, "Show as Experience Bar"), L.OPT_REP_FACTION_HELP_CHAR,
    L.OPT_REP_FACTION_HELP_RATE })
  -- the icon after a dropdown goes right of it
  local _, rel = page["help.repMain"].widget:GetPoint(1)
  T.ok(rel == dd.widget, "right of the dropdown")
  -- refresh while only this page is shown
  ns.Core.SetSetting("widget.rep", false)
  T.eq(rawget(page["widget.rep"].widget, "_checked"), false, "synced")
  ns.Core.SetSetting("widget.rep", true)
  -- reset button
  for _ = 1, 3 do
    Stub.Advance(60)
    Stub.GainRep(50)
  end
  T.ok(ns.char.rep.e[1].a > 0)
  Stub.RunScript(page["rep.resetRate"].widget, "OnClick", "LeftButton")
  T.eq(ns.char.rep.e[1].a, 0)
  T.ok(Stub.printed[#Stub.printed]:find(L.REP_RESET_RATE_DONE, 1, true) ~= nil)
  -- closed: no longer shown
  Stub.ui.CloseSettings()
  T.no(ns.Options.IsShown())
  T.eq(Stub.errors, {})
end)

T.test("options: the faction picker (menu): auto, the game's headers, a pick, read-only refused", function()
  local ns = Start({ theme = "futuriste", ui = { modern = true }, watched = Friendly(), tree = true })
  local L = ns.L
  ns.Options.Open()
  local page = Page()
  local rec = page["rep.faction"]
  local dd = rec.widget
  dd:GenerateMenu()
  local root = dd._root
  local auto = root.children[1]
  T.eq({ auto.kind, auto.text }, { "radio", L.OPT_REP_FACTION_AUTO })
  T.ok(Stub.ui.IsChecked(auto), "auto by default")
  local classic = Stub.ui.FindMenuItem(root, "Classic")
  T.eq(classic.kind, "button", "a submenu per header")
  T.ok(classic.scroll ~= nil, "a long list scrolls")
  local texts = {}
  for _, c in ipairs(classic.children) do texts[#texts + 1] = c.text end
  T.eq(texts, { "Stormwind (Friendly)", "Darnassus (Honored)", "Argent Dawn (Neutral)" })
  T.eq(Stub.rep.factions[2].collapsed, true, "the game's list as the player left it")
  -- a pick: this character's faction
  Stub.ui.ClickMenuItem(Stub.ui.FindMenuItem(root, "Argent Dawn (Neutral)"))
  T.eq(ns.Rep.Chosen(), 529)
  T.eq((ns.Rep.Get()), "Argent Dawn")
  root = dd._root
  T.ok(Stub.ui.IsChecked(Stub.ui.FindMenuItem(root, "Argent Dawn (Neutral)")), "the menu follows")
  T.no(Stub.ui.IsChecked(root.children[1]))
  -- a chosen faction missing from the list keeps an entry
  ns.Rep.SetChosen(999)
  ns.Options.Refresh()
  T.ok(Stub.ui.FindMenuItem(dd._root, format(L.OPT_REP_FACTION_MISSING_FMT, 999)) ~= nil)
  -- auto again
  Stub.ui.ClickMenuItem(dd._root.children[1])
  T.eq(ns.Rep.Chosen(), nil)
  -- read-only: refused
  ns.readOnly = true
  local n = #Stub.printed
  Stub.ui.ClickMenuItem(Stub.ui.FindMenuItem(dd._root, "Booty Bay (Revered)"))
  T.eq(ns.Rep.Chosen(), nil, "unchanged")
  T.ok(#Stub.printed > n and Stub.printed[#Stub.printed]:find(L.READONLY_ACTION, 1, true) ~= nil)
  Stub.RunScript(page["rep.resetRate"].widget, "OnClick", "LeftButton")
  T.ok(Stub.printed[#Stub.printed]:find(L.READONLY_ACTION, 1, true) ~= nil)
  ns.readOnly = false
  T.eq(Stub.errors, {})
end)

T.test("options: without MenuUtil the picker is a button cycling through the factions", function()
  local ns = Start({ ui = { modern = false }, watched = Friendly(), tree = true })
  local L = ns.L
  ns.Options.Open()
  local rec = Page()["rep.faction"]
  local b = rec.widget
  local function Text() return rawget(b, "_text") or (b.GetText and b:GetText()) end
  local fs = nil
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_parent") == b and rawget(o, "_type") == "FontString" then fs = o end
  end
  local function Label() return fs and fs:GetText() or Text() end
  T.eq(Label(), L.OPT_REP_FACTION_AUTO)
  Stub.RunScript(b, "OnClick", "LeftButton")
  T.eq(ns.Rep.Chosen(), 72, "the first faction of the list")
  T.eq(Label(), "Stormwind (Friendly)")
  Stub.RunScript(b, "OnClick", "RightButton")
  T.eq(ns.Rep.Chosen(), nil, "back to auto")
  Stub.RunScript(b, "OnClick", "RightButton")
  T.eq(ns.Rep.Chosen(), 21, "auto, backwards: the last one")
  T.eq(Stub.errors, {})
end)

T.test("options: no subcategory (standalone panel, older Settings): a Reputation section in the main panel", function()
  for _, ui in ipairs({ { modern = true, subcategory = false }, { settings = false } }) do
    Stub.Reset()
    local ns = Start({ ui = ui, watched = Friendly(), tree = true })
    local L = ns.L
    ns.Options.Open()
    local panel
    for _, o in ipairs(Stub.regions) do
      local c = rawget(o, "controls")
      if type(c) == "table" and c["widget.shown"] then panel = o end
    end
    T.ok(panel ~= nil, "the main panel")
    local c = panel.controls
    T.ok(c["widget.rep"] and c["widget.main"] and c["rep.faction"] and c["rep.resetRate"], "the section's controls")
    T.ok(c["widget.rep"].index > c["widget.hideAtMax"].index, "after Display")
    local note = false
    for _, o in ipairs(Stub.regions) do
      if rawget(o, "_text") == L.OPT_REP_MOVED then note = true end
    end
    T.no(note, "no pointer to a page that does not exist")
    T.no(ns.Options.HasSubPage())
    T.eq(Stub.errors, {})
  end
end)

---------------------------------------------------------------------------
-- Review of the reputation features: the fixes and the gaps it found
---------------------------------------------------------------------------

-- The rect of a frame (x, y, w, h) or nil.
local function Box(o)
  local l, b, w, h = o:GetRect()
  if not l then return nil end
  return { l = l, b = b, r = l + w, t = b + h }
end

-- True when the two rects share an area.
local function Overlap(a, b)
  return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end

T.test("rep hover regions: the detailed tooltip hangs off the bar's frame, never over the bar", function()
  local ns, f, tp = Start({ theme = "druid", watched = Friendly() })
  -- where the general tooltip goes (the lower half of the screen: above the bar)
  Stub.RunScript(f, "OnEnter")
  local tf = ns.TooltipFrame.frame
  local general = { tf:GetPoint(1) }
  T.ok(general[2] == f)
  Stub.RunScript(f, "OnLeave")
  for _, main in ipairs({ "xp", "rep" }) do
    ns.Core.SetSetting("widget.main", main)
    local hit = tp.repHit
    T.ok(hit:IsShown(), main)
    Stub.RunScript(hit, "OnEnter")
    T.ok(ns.Tooltip.IsShownFor(hit), main .. ": shown for the region")
    local p, rel, rp, x, y = tf:GetPoint(1)
    T.ok(rel == f, main .. ": anchored to the bar's frame, not to the region inside it")
    T.eq({ p, rp, x, y }, { general[1], general[3], general[4], general[5] }, main .. ": as the general one")
    T.no(Overlap(Box(tf), Box(f)), main .. ": clear of the bar")
    Stub.RunScript(hit, "OnLeave")
    T.no(ns.Tooltip.IsShownFor(hit), main .. ": hidden with the hover")
  end
  -- the upper half of the screen: below the bar, still clear of it
  ns.Core.SetSetting("widget.point", { "TOP", "TOP", 0, -40 })
  for _, main in ipairs({ "xp", "rep" }) do
    ns.Core.SetSetting("widget.main", main)
    Stub.RunScript(tp.repHit, "OnEnter")
    local p, rel, rp = tf:GetPoint(1)
    T.eq({ p, rel == f, rp }, { "TOP", true, "BOTTOM" }, main .. ": below the bar")
    T.no(Overlap(Box(tf), Box(f)), main .. ": clear of the bar")
    Stub.RunScript(tp.repHit, "OnLeave")
  end
  -- Classic (the shared GameTooltip), main bar mode: the same content and anchor
  Stub.Reset()
  local ns2, f2, tp2 = Start({ theme = "actuel", watched = Friendly(), main = "rep" })
  local L = ns2.L
  Stub.RunScript(tp2.repHit, "OnEnter")
  Stub.Advance(1)
  T.ok(ns2.Tooltip.IsShownFor(tp2.repHit))
  local _, rel = GameTooltip:GetPoint(1)
  T.ok(rel == f2, "GameTooltip anchored to the bar's frame")
  local seen = {}
  for _, l in ipairs(NativeLines()) do seen[l.left] = l end
  T.ok(seen[L.TT_SECTION_REP] ~= nil and seen.Darnassus ~= nil, "the reputation's detailed tooltip")
  local cur = seen["Friendly · 1,200 / 6,000 (20.0%)"]
  T.ok(cur ~= nil, "the standing and the points")
  T.eq(Rgb(cur.color[1], cur.color[2], cur.color[3]), Rgb(ns2.Rep.Color(5)))
  local lines = NativeLines()
  T.eq(lines[#lines].left, L.TT_REP_HINT, "the reputation's hint, not the general one's")
  Stub.RunScript(tp2.repHit, "OnLeave")
  T.no(GameTooltip:IsShown())
  T.eq(Stub.errors, {})
end)

T.test("chosen faction: unreadable for a while, the game's shown; its rate and session gain kept", function()
  local ns = Start({ watched = Friendly(), tree = true })
  local R = ns.Rep
  T.ok(R.SetChosen(529))
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainRepID(529, 50)
  end
  local r = ns.char.rep
  local a, d = r.e[1].a, r.e[1].d
  local reph, status = R.Rate(0)
  T.eq({ R.SessionGain(), status }, { 600, "ok" })
  T.ok(a > 0)
  -- one failed read, then a good one (REVIEW B)
  Stub.rep.missing[529] = true
  Stub.Fire("UPDATE_FACTION")
  local _, _, _, _, id, src, fb = R.Detail()
  T.eq({ id, src, fb }, { 69, "game", true }, "the game's faction, the fallback said")
  T.eq({ r.f, r.e[1].a, r.e[1].d }, { 529, a, d }, "the game's faction is not measured: no new base")
  T.eq({ R.Rate(0) }, { nil, "nodata", 0, 0, nil }, "no rate for the game's faction")
  T.eq(R.SessionGain(), 0)
  Stub.rep.missing[529] = nil
  Stub.Fire("UPDATE_FACTION")
  T.eq({ r.f, r.e[1].a, r.e[1].d }, { 529, a, d }, "the rate kept")
  T.eq(R.SessionGain(), 600, "the session's gain kept")
  T.eq({ R.Rate(0) }, { reph, status, 0, 0, a / d })
  -- a gain made while it could not be read counts at the next read
  Stub.rep.missing[529] = true
  Stub.GainRepID(529, 40)
  Stub.rep.missing[529] = nil
  Stub.Fire("UPDATE_FACTION")
  T.eq(R.SessionGain(), 640)
  -- a client that cannot read a faction under a collapsed header: the same
  Stub.rep.visibleOnly = true
  local tree = Stub.rep.factions
  tree[1].collapsed = true                         -- Classic (Argent Dawn inside) collapsed
  Stub.Fire("UPDATE_FACTION")
  T.eq(select(7, R.Detail()), true, "unreadable under a collapsed header: the fallback")
  T.eq({ r.f, R.SessionGain() }, { 529, 0 })
  tree[1].collapsed = nil
  Stub.Fire("UPDATE_FACTION")
  T.eq({ select(6, R.Detail()) }, { "chosen", false, true })
  T.eq(R.SessionGain(), 640, "kept across it")
  -- the picker's walk under such a client: the same, no new base
  local groups = R.ListFactions()
  T.ok(#groups > 0)
  T.eq({ r.f, R.SessionGain() }, { 529, 640 })
  T.eq(Stub.errors, {})
end)

T.test("rep rate: the session's gain kept across a /reload, started over at a new login", function()
  local ns = Start({ watched = Friendly() })
  Stub.GainRep(100)
  T.eq(ns.Rep.SessionGain(), 100)
  local ns2 = Stub.Restart({ settle = 3, reload = true })
  Stub.WatchFaction(Friendly(4300))                -- the first read of the load: a base
  T.eq(ns2.Rep.SessionGain(), 100, "the same session after a /reload")
  Stub.GainRep(10)
  T.eq(ns2.Rep.SessionGain(), 110)
  local ns3 = Stub.Restart({ settle = 3 })         -- a new login: a new session
  Stub.WatchFaction(Friendly(4310))
  T.eq(ns3.Rep.SessionGain(), 0)
  Stub.GainRep(5)
  T.eq(ns3.Rep.SessionGain(), 5)
end)

T.test("main bar mode: hidden by hideAtMax with the faction lost, shown again it draws the XP", function()
  local ns, f, tp = Start({ theme = "futuriste", watched = Friendly(), level = 60, main = "rep" })
  ns.Core.SetSetting("widget.hideAtMax", true)
  T.ok(f:IsShown())
  Stub.WatchFaction(nil)                           -- the XP mode's hideAtMax: hidden
  T.no(f:IsShown())
  ns.Core.SetSetting("widget.hideAtMax", false)    -- shown again (REVIEW A)
  T.ok(f:IsShown())
  T.match(tp.bl:GetText(), "LEVEL", "the XP mode's level text")
  T.eq(tp.brx:IsShown() and tp.brx:GetText() or nil, nil, "no points at max level")
  T.eq(Vertex(tp.tex.fill), Rgb(1, 0x2b / 255, 0xd6 / 255), "the theme's own fill colour")
  T.eq(tp.tex.fill:GetWidth(), tp.tex.track:GetWidth(), "full at max level")
  local themeFill = Vertex(tp.tex.fill)
  -- a faction again: the reputation at once; lost while hidden by the bar's own switch:
  -- the XP when shown again
  Stub.WatchFaction(Friendly())
  T.eq(tp.bl:GetText(), ns.BarSkin.Sub("xp", "Darnassus"))
  ns.Core.SetSetting("widget.shown", false)
  Stub.WatchFaction(nil)
  ns.Core.SetSetting("widget.shown", true)
  T.match(tp.bl:GetText(), "LEVEL")
  T.eq(Vertex(tp.tex.fill), themeFill)
  T.eq(Stub.errors, {})
end)

T.test("main bar mode: the strip checkbox greyed out, with its note (the strip shows the XP)", function()
  local ns, f = Start({ theme = "futuriste", ui = { modern = true }, watched = Friendly(), tree = true })
  local L = ns.L
  ns.Options.Open()
  local page = Page()
  local rec = page["widget.rep"]
  local cb = rec.widget
  local function Note()
    for _, o in ipairs(Stub.regions) do
      if rawget(o, "_text") == L.OPT_REP_STRIP_MAIN_NOTE then return o end
    end
    return nil
  end
  local note = Note()
  T.ok(note ~= nil, "the note exists")
  T.ok(cb:IsEnabled(), "the XP mode: the box acts")
  T.no(note:IsShown(), "no note in the XP mode")
  ns.Core.SetSetting("widget.main", "rep")
  T.no(cb:IsEnabled(), "greyed out in the reputation mode")
  T.ok(note:IsShown(), "the note says why")
  local dim = ns.C.COLORS.dim
  T.eq(Rgb(rec.label:GetTextColor()), Rgb(dim[1], dim[2], dim[3]), "its label dimmed")
  -- a click changes nothing
  Stub.RunScript(cb, "OnClick")
  T.eq(ns.settings.widget.rep, true, "the setting kept")
  -- the bar: the XP strip and the tooltip line, whatever the box (as the note says)
  ns.Core.SetSetting("widget.rep", false)
  T.ok(Strip(f.tp) ~= nil, "the XP strip")
  T.ok(ns.Rep.Shown(), "the reputation shown by the main bar")
  ns.Core.SetSetting("widget.rep", true)
  -- back to the XP: the box acts again
  ns.Core.SetSetting("widget.main", "xp")
  T.ok(cb:IsEnabled())
  T.no(note:IsShown())
  local v = ns.C.COLORS.value
  T.eq(Rgb(rec.label:GetTextColor()), Rgb(v[1], v[2], v[3]), "its label no longer dimmed")
  Stub.RunScript(cb, "OnClick")
  T.eq(ns.settings.widget.rep, false, "the box acts")
  T.eq(Strip(f.tp), nil, "no strip")
  T.eq(Stub.errors, {})
end)

T.test("main bar mode, futuriste: the texts the theme derives from the XP colour follow the fill", function()
  local ns, _, tp = Start({ theme = "futuriste", watched = Neutral() })
  local th = ns.Themes.Active()
  local function Lighter(r, g, b, k)
    k = k or 0.45
    return Rgb(r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k)
  end
  local xr, xg, xb = th.colors.xp[1], th.colors.xp[2], th.colors.xp[3]
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(xr, xg, xb, 0.45), "the XP mode: the XP colour, lighter")
  local mini = th.text.colors.marker
  local miniRgb = Rgb(mini[1], mini[2], mini[3])
  ns.Core.SetSetting("widget.main", "rep")
  T.ok(tp.marker:IsShown())
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(ns.Rep.Color(4)), "the standing's colour, lighter")
  -- a new standing: the marker follows (no THEME_CHANGED)
  Stub.GainRep(1000)
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(ns.Rep.Color(5)), "Friendly's")
  T.eq(Rgb(mini[1], mini[2], mini[3]), miniRgb, "the theme's own colour (mini display) untouched")
  -- the user's XP colour does not reach it in this mode; the user's text colour wins
  ns.Core.SetSetting("widget.xpColor", { 0, 0, 1 })
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(ns.Rep.Color(5)))
  ns.Core.SetSetting("widget.textColor", { 1, 0, 0 })
  T.eq(Rgb(tp.marker:GetTextColor()), Rgb(1, 0, 0))
  ns.Core.SetSetting("widget.textColor", false)
  -- the XP again: the XP colour (the user's), lighter
  ns.Core.SetSetting("widget.main", "xp")
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(0, 0, 1, 0.45))
  ns.Core.SetSetting("widget.xpColor", false)
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(xr, xg, xb, 0.45))
  -- a theme switch in the reputation mode: the new theme's own colours
  ns.Core.SetSetting("widget.main", "rep")
  ns.Core.SetSetting("theme", "druid")
  tp = ns.Bar.frame.tp
  local dm = ns.Themes.Active().text.colors.marker
  T.eq(Rgb(tp.marker:GetTextColor()), Rgb(dm[1], dm[2], dm[3]), "druid: its marker colour (not derived)")
  ns.Core.SetSetting("theme", "futuriste")
  tp = ns.Bar.frame.tp
  T.eq(Rgb(tp.marker:GetTextColor()), Lighter(ns.Rep.Color(5)), "futuriste again: the standing's")
  T.eq(Stub.errors, {})
end)

T.test("faction list: a header without a reputation of its own is not offered (forever, Era)", function()
  for _, api in ipairs({ "forever", "era" }) do
    Stub.Reset()
    local ns = Start({ watched = Friendly(), api = api, tree = true })
    local alliance = Stub.rep.factions[1].children[1]
    alliance.factionID, alliance.noRep = 469, true   -- an ID, no reputation (isHeaderWithRep false)
    T.eq(Names(ns.Rep.ListFactions()), {
      { name = "Classic", items = { "Stormwind/72/5", "Darnassus/69/6", "Argent Dawn/529/4" } },
      { name = "Inactive", items = { "Booty Bay/21/7" } },
    }, api)
    T.eq(alliance.collapsed, true, api .. ": collapsed again")
    alliance.noRep, alliance.value = nil, 100       -- with its own reputation: a choice
    T.eq(Names(ns.Rep.ListFactions())[1].items[1], "Alliance/469/4", api)
    T.eq(Stub.errors, {}, api)
  end
end)

T.test("faction list: two headers of the same name without an ID come back each as it was", function()
  local ns = Start({ watched = Friendly() })
  local function Tree(c1, c2)
    return {
      { name = "Other", header = true, collapsed = c1, children = { { name = "A", factionID = 1, value = 10 } } },
      { name = "Other", header = true, collapsed = c2, children = { { name = "B", factionID = 2, value = 20 } } },
    }
  end
  for _, c in ipairs({ { nil, true }, { true, nil }, { true, true } }) do
    local tree = Tree(c[1], c[2])
    Stub.SetFactions(tree)
    T.eq(Names(ns.Rep.ListFactions()), { { name = "Other", items = { "A/1/4" } }, { name = "Other", items = { "B/2/4" } } })
    T.eq({ tree[1].collapsed, tree[2].collapsed }, { c[1], c[2] }, tostring(c[1]) .. "/" .. tostring(c[2]))
  end
  T.eq(Stub.errors, {})
end)

T.test("faction list: a client that sends its burst later: plain reads after the walk, nothing changes", function()
  local ns = Start({ watched = Friendly(), tree = true })
  local R = ns.Rep
  local tree = Stub.rep.factions
  Stub.rep.async = true
  local changed = CountMsg(ns, "REP_CHANGED")
  local before = Stub.calls.GetWatchedFactionData
  T.eq(#R.ListFactions(), 2)
  T.eq(Stub.calls.GetWatchedFactionData - before, 1, "one read after the walk")
  local n = Stub.FlushFactionEvents()
  T.eq(n, 4, "the burst arrives after the walk")
  T.eq(Stub.calls.GetWatchedFactionData - before, 1 + n, "each one a plain read")
  T.eq(changed.n, 0, "nothing shown changed: no REP_CHANGED")
  T.eq({ tree[1].collapsed, tree[1].children[1].collapsed, tree[2].collapsed }, { nil, true, true })
  -- a chosen faction's rate is not touched by it
  T.ok(R.SetChosen(529))
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainRepID(529, 50)
  end
  local r = ns.char.rep
  local a = r.e[1].a
  R.ListFactions()
  Stub.FlushFactionEvents()
  T.eq({ r.f, r.e[1].a, R.SessionGain() }, { 529, a, 600 })
  T.eq(Stub.errors, {})
end)
