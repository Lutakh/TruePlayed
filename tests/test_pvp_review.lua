-- tests/test_pvp_review.lua - the PvP review's findings (Pvp.lua, Bar.lua, Tooltip.lua,
-- Tokens.lua, PvpOptions.lua), each proved by the case that showed it: the PvP strip drawn
-- again after a fight that hid the bar, an empty read at the login taken as no base (and
-- the bases taken again at PLAYER_ENTERING_WORLD), two battlegrounds in a row, a stale read
-- around a new rank, two honor gains read at once, the PvP strip's own region in the PvP
-- main mode, the rank that ends at this week's cap, the weekly and the daily reset passing
-- without an event, the cap alert re-armed by a valid read only, a strip that would repeat
-- the main bar, rank points without a week number, the winner against the player's side,
-- the events only while something shows PvP (and the place read all the same: a reload
-- in a battleground), and the wording of two labels. The stub: tests/stub_pvp.lua (empty
-- reads, stale rank reads, Stub.WeeklyReset, Stub.DailyReset, Stub.ChainBG).
local Stub, T = ...

local format, floor = string.format, math.floor

-- Loads the addon (widget shown); opts: api, season (false: none), week, cap, total, q,
-- theme, ui, level, xp, rest, watched, db; widget / pvp / debug: settings stored before the
-- login ({ key = value } of settings.widget / settings.pvp, settings.debug); settings: set
-- after it.
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI(opts.ui or { ldb = false })
  if opts.theme then Stub.theme = opts.theme end
  Stub.SetPvpAPI(opts.api or "forever")
  local s = Stub.pvp
  if opts.season ~= false then Stub.SetWeek(opts.week or 2, opts.cap or 5, 3, { quiet = true }) end
  if opts.total then s.total = opts.total end
  if opts.q then s.q = opts.q end
  if opts.db then
    rawset(_G, "TruePlayedDB", opts.db)
  elseif opts.widget or opts.pvp then
    rawset(_G, "TruePlayedDB", { schema = 1, settings = { firstRunDone = true, widget = opts.widget or {},
                                                          pvp = opts.pvp, debug = opts.debug } })
  end
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

-- A strip as drawn (tp.rep or tp.pvp): nil when hidden, else { y, h, fill }.
local function Strip(tp, which)
  local st = tp[which or "pvp"]
  if not st or not st.bg:IsShown() then return nil end
  local _, _, _, _, y = st.bg:GetPoint(1)
  return { y = y, h = st.bg:GetHeight(), fill = st.fill:IsShown() and st.fill:GetWidth() or 0 }
end

local function Hit(h)
  if not h or not h:IsShown() then return nil end
  local _, _, _, x, y = h:GetPoint(1)
  return { x = x, y = y, w = h:GetWidth(), h = h:GetHeight() }
end

local function TipRows(ns)
  local tf = ns.TooltipFrame.frame
  local out = {}
  for i = 1, tf.tp.n do
    local row = tf.tp.rows[i]
    if row.left:IsShown() then
      out[#out + 1] = { left = row.left:GetText(), right = row.right:IsShown() and row.right:GetText() or nil }
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

---------------------------------------------------------------------------
-- 1. A fight at max level with hideAtMax and combatHide (review case H)
---------------------------------------------------------------------------

T.test("pvp review 1: max level, PvP main bar hidden for a fight: the honor strip gained in it is drawn after", function()
  local _, f, tp = Start({ theme = "warrior", total = 2000, level = 60,
                            settings = { ["widget.main"] = "pvp", ["widget.pvp"] = "honor", ["widget.hideAtMax"] = true,
                                         ["widget.combatHide"] = true, ["pvp.capAlert"] = false } })
  T.ok(f:IsShown(), "shown: it shows PvP")
  Stub.EnterCombat()
  Stub.GainHonor(10000)                            -- PVP_CHANGED while the bar is hidden
  Stub.LeaveCombat()
  Stub.Advance(2)
  local s = Strip(tp)
  T.ok(s ~= nil, "the honor strip")
  T.eq(s.fill, floor(tp.pvp.bg:GetWidth() * Stub.pvp.q / 25000 + 0.5), "redrawn after the fight")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 3. An empty read at the login (review case P)
---------------------------------------------------------------------------

T.test("pvp review 3: an empty honor read (0 / 0, not discovered) is no base; nothing counts as a gain", function()
  -- the first read of the load (DB_READY) is empty, the world's read the real one
  Stub.pvp.empty = { honor = 1 }
  local ns = Start({ q = 12000, widget = { pvp = "honor" }, debug = true })
  local P = ns.Pvp
  local p = ns.char.pvp
  T.eq({ p.he[1].a, (P.Session()) }, { 0, 0 }, "12,000 held: no gain")
  T.eq(p.h, 12000, "the base")
  -- /tpl debug: the two reads of the login, the first one empty and not a base
  local seen = {}
  for _, line in ipairs(Stub.printed) do
    if line:find("PvP read: honor 0 / 0 (base 0)", 1, true) then seen.read = true end
    if line:find("PvP world: honor 12000 / 25000 (base 1)", 1, true) then seen.world = true end
  end
  T.eq(seen, { read = true, world = true }, "the debug lines of the login")
  Stub.GainHonor(100)
  T.eq({ p.he[1].a, (P.Session()) }, { 100, 100 })
  -- both reads of a load empty (DB_READY and PLAYER_ENTERING_WORLD): the first real read
  -- (a CURRENCY_DISPLAY_UPDATE once the data is there) is the base
  Stub.pvp.empty = { honor = 2 }
  ns = Stub.Restart({ reload = true, settle = 3 })
  p = ns.char.pvp
  T.eq({ (ns.Pvp.Honor()) }, { true }, "read (empty)")
  local a = p.he[1].a
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.near(p.he[1].a, a, 1e-6, "the first real read: a base")
  Stub.GainHonor(50)
  T.near(p.he[1].a, a + 50, 1e-6)
  -- discovered false alone (a quantity with a cap): no base either
  Stub.pvp.discovered = false
  ns = Stub.Restart({ reload = true, settle = 3 })
  p = ns.char.pvp
  a = p.he[1].a
  Stub.pvp.discovered = true
  Stub.GainHonor(25)
  T.near(p.he[1].a, a, 1e-6, "the first discovered read: a base")
  T.eq(Stub.errors, {})
end)

T.test("pvp review 3: an empty rank read (rank 0, no point, maxLevel 0) is no base", function()
  Stub.pvp.empty = { rank = 2 }                    -- DB_READY's and the world's reads
  local ns = Start({ total = 3000, widget = { pvp = "rank" } })
  local p = ns.char.pvp
  T.eq((select(2, ns.Pvp.Session())), 0)
  Stub.Fire("UPDATE_FACTION")                      -- the data is there: rank 3 (2700) + 300
  T.eq({ p.ke[1].a, (select(2, ns.Pvp.Session())), p.k }, { 0, 0, 3000 }, "a base, no gain")
  Stub.GainRankPoints(100)
  T.eq({ p.ke[1].a, (select(2, ns.Pvp.Session())) }, { 100, 100 })
  T.eq(Stub.errors, {})
end)

T.test("pvp review 3: PLAYER_ENTERING_WORLD at a login or a reload takes the bases again; a loading screen does not", function()
  -- the first read of the load sees an old quantity, the world's the real one
  local api
  Stub.InstallUI({ ldb = false })
  Stub.SetPvpAPI("forever")
  Stub.SetWeek(2, 5, 3, { quiet = true })
  Stub.pvp.q = 12000
  Stub.pvp.total = 2000
  api = rawget(_G, "C_CurrencyInfo")
  local orig = api.GetCurrencyInfo
  local calls = 0
  api.GetCurrencyInfo = function(id)
    calls = calls + 1
    local t = orig(id)
    if calls == 1 and type(t) == "table" then t.quantity = 500 end
    return t
  end
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { firstRunDone = true, widget = { pvp = "honor" } } })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  local p = ns.char.pvp
  T.ok(calls >= 2, "read twice")
  T.eq({ p.he[1].a, (ns.Pvp.Session()), p.h }, { 0, 0, 12000 }, "the world's read: the base")
  -- a loading screen (into a battleground): a gain read there counts
  Stub.GainHonor(300, { quiet = true })
  Stub.EnterBG({ loading = true })
  T.eq({ p.he[1].a, (ns.Pvp.Session()) }, { 300, 300 }, "counted")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 4. Two battlegrounds in a row (review case O)
---------------------------------------------------------------------------

T.test("pvp review 4: from one battleground straight into the next (another map or the same): two games", function()
  local ns = Start({ total = 1000, widget = { pvp = "honor" }, pvp = { capAlert = false } })
  local P = ns.Pvp
  Stub.EnterBG({ loading = true, id = 30 })
  Stub.Advance(600)
  Stub.GainHonor(300)
  Stub.MatchComplete(0, 600)                       -- won (the player is Horde)
  Stub.ChainBG(31)                                 -- another battleground's map
  Stub.Advance(500)
  Stub.GainHonor(100)
  Stub.MatchComplete(1, 500)                       -- lost
  local _, _, w, l, n = P.Session()
  T.eq({ w, l, n }, { 1, 0, 1 }, "the first closed when the second began")
  Stub.ChainBG(31)                                 -- the same map again, its match over
  Stub.Advance(400)
  Stub.GainHonor(50)
  Stub.MatchComplete(0, 400)
  -- a reload inside keeps the game in progress (same instance, no loading screen)
  ns = Stub.Restart({ reload = true, settle = 3 })
  P = ns.Pvp
  Stub.LeaveBG({ loading = true })
  local h, _, w2, l2, n2, ah, ad = P.Session()
  T.eq({ h, w2, l2, n2 }, { 450, 2, 1, 3 }, "three games: two won, one lost")
  T.eq({ ah, ad }, { 150, 500 })
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 5. A stale read around a new rank (review case D), a drop that is no new season
---------------------------------------------------------------------------

T.test("pvp review 5: a new rank read with a stale rank or stale points counts the real rise only", function()
  local ns = Start({ total = 1600, widget = { pvp = "rank" } })   -- rank 1 (750), 850 of 900
  local p = ns.char.pvp
  local P = ns.Pvp
  Stub.GainRankPoints(100, { stale = "level" })    -- the renown event: rank 1 with 50 points
  T.eq({ p.ke[1].a, select(2, P.Session()), p.k }, { 100, 100, 1700 }, "the old rank, the new points")
  Stub.GainRankPoints(1050, { stale = "points" })  -- 2750: rank 3 (2700) read with 50 + 1000?
  T.eq({ p.ke[1].a, select(2, P.Session()), p.k }, { 1150, 1150, 2750 }, "the new rank, the old points")
  T.eq(select(2, P.Rank()), 3)
  T.eq(Stub.errors, {})
end)

T.test("pvp review 5: a lower total in the same week and season is ignored; a new season takes a new base", function()
  local ns = Start({ total = 1700, widget = { pvp = "rank" } })
  local p = ns.char.pvp
  Stub.pvp.total = 800                             -- a transient low read
  Stub.Fire("UPDATE_FACTION")
  T.eq({ p.k, p.ke[1].a }, { 1700, 0 }, "no new base, no gain")
  T.eq(select(8, ns.Pvp.Rank()), 800, "shown as read")
  Stub.pvp.total = 1750
  Stub.Fire("UPDATE_FACTION")
  T.eq({ p.k, p.ke[1].a }, { 1750, 50 }, "the real rise only")
  -- a new week number with a lower total: a new season
  Stub.pvp.total = 0
  Stub.SetWeek(1, 3, 0)
  T.eq({ p.k, p.ke[1].a }, { 0, 50 })
  Stub.GainRankPoints(200)
  T.eq(p.ke[1].a, 250)
  -- a new season number alone
  Stub.pvp.season = 37
  Stub.pvp.total = 100
  Stub.Fire("UPDATE_FACTION")
  T.eq({ p.k, p.ke[1].a }, { 100, 250 })
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 6. Two honor gains read at once (review case C)
---------------------------------------------------------------------------

T.test("pvp review 6: two honor gains already applied when the first event is read: both count", function()
  local ns = Start({ widget = { pvp = "honor" } })
  local p = ns.char.pvp
  local a0 = p.he[1].a
  Stub.pvp.q = Stub.pvp.q + 150                    -- 100 then 50, applied before the handler runs
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792, Stub.pvp.q, 100, 1, nil)
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792, Stub.pvp.q, 50, 1, nil)
  T.eq(p.he[1].a - a0, 150)
  T.eq((ns.Pvp.Session()), 150)
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 7. The PvP strip under the PvP main bar (review case E)
---------------------------------------------------------------------------

T.test("pvp review 7: in the PvP main mode the PvP strip keeps its own region and the PvP tooltip", function()
  local ns, f, tp = Start({ theme = "warrior", total = 1000,
                            settings = { ["widget.main"] = "pvp", ["widget.pvp"] = "honor" } })
  local s = Strip(tp)
  T.ok(s ~= nil, "the honor strip")
  local track, strip = Hit(tp.pvpHit), Hit(tp.pvpStripHit)
  T.ok(track ~= nil and strip ~= nil, "two regions")
  T.ok(strip.y <= s.y and strip.y + strip.h >= s.y + s.h, "one over the strip")
  T.ok(strip.y + strip.h <= track.y + 0.001, "not over the track")
  Stub.RunScript(tp.pvpStripHit, "OnEnter")
  T.ok(ns.Tooltip.IsShownFor(tp.pvpStripHit))
  local rows = TipRows(ns)
  T.ok(FindRow(rows, ns.L.TT_SECTION_PVP) ~= nil, "the PvP tooltip")
  T.ok(FindRow(rows, ns.L.TT_PVP_HONOR) ~= nil)
  local tf = ns.TooltipFrame.frame
  local _, rel = tf:GetPoint(1)
  T.ok(rel == f, "off the bar's frame")
  Stub.RunScript(tp.pvpStripHit, "OnLeave")
  T.no(ns.Tooltip.IsShownFor(tp.pvpStripHit))
  -- the XP mode: no second region
  ns.Core.SetSetting("widget.main", "xp")
  T.eq(Hit(tp.pvpStripHit), nil)
  T.ok(Hit(tp.pvpHit) ~= nil, "the strip's region")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 8. The rank that ends at this week's cap
---------------------------------------------------------------------------

T.test("pvp review 8: the next rank is this week's cap: said on the bar and in the tooltip; no cap mark", function()
  local ns, _, tp = Start({ theme = "futuriste", cap = 3, total = 2000,
                            settings = { ["widget.main"] = "pvp" } })   -- rank 2: 1650 .. 2700, cap rank 3
  local L, P = ns.L, ns.Pvp
  T.eq(P.CapFrac, nil, "no cap mark function")
  T.eq(ns.BarSkin.CapMark, nil)
  T.eq(tp.capMark, nil)
  T.eq({ P.Week() }, { 2, 3, 2700, 3, false, true }, "the next rank is this week's last")
  Stub.EnterBG()
  for _ = 1, 4 do
    Stub.Advance(60)
    Stub.GainRankPoints(30)
  end
  Stub.Advance(1)
  local t1 = P.MainRight(0)
  local v = P.Rate("rank", 0)
  local eta = P.RankEta(0)
  T.eq(t1, format(L.PVP_MAIN_RATE_FMT, ns.Fmt.Rate(v), format(L.PVP_NEXT_CAP_FMT, 3, ns.Fmt.ETA(eta))))
  Stub.RunScript(tp.pvpHit, "OnEnter")
  Stub.Advance(1)
  T.ok(FindRow(TipRows(ns), format(L.TT_PVP_LAST_FMT, 3)) ~= nil, "the tooltip says it")
  Stub.RunScript(tp.pvpHit, "OnLeave")
  -- a cap two ranks ahead: not said
  Stub.SetWeek(2, 4, 3)
  T.eq(select(6, P.Week()), false)
  Stub.Advance(1)
  t1 = P.MainRight(0)
  T.no(t1:find(format(L.PVP_NEXT_CAP_FMT, 3, ""), 1, true), "the usual text")
  Stub.RunScript(tp.pvpHit, "OnEnter")
  Stub.Advance(1)
  T.eq(FindRow(TipRows(ns), format(L.TT_PVP_LAST_FMT, 4)), nil)
  Stub.RunScript(tp.pvpHit, "OnLeave")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 9. The weekly reset passing without an event (review case N)
---------------------------------------------------------------------------

T.test("pvp review 9: the weekly reset passes without an event: the rank read again; and when the tooltip opens", function()
  local ns, _, tp = Start({ cap = 3, total = 2700, settings = { ["widget.pvp"] = "rank" } })
  local P = ns.Pvp
  T.eq(select(5, P.Week()), true, "capped")
  T.eq(select(2, P.RankEta(0)), "capped")
  local reads = Stub.pvp.calls.GetProgression
  Stub.Advance(30)
  T.eq(Stub.pvp.calls.GetProgression, reads, "no read while the countdown runs")
  Stub.WeeklyReset(4)                              -- week 3, cap rank 4, 7 days to the next one
  Stub.Advance(2)
  T.eq({ P.Week() }, { 3, 4, 3900, 3, false, true }, "the new cap read")
  T.ok(select(2, P.RankEta(0)) ~= "capped")
  -- the tooltip opening reads it again too
  Stub.pvp.cap = 5
  Stub.RunScript(tp.pvpHit, "OnEnter")
  T.eq(select(2, P.Week()), 5)
  Stub.RunScript(tp.pvpHit, "OnLeave")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 10. The cap alert (review cases Q and K)
---------------------------------------------------------------------------

T.test("pvp review 10: at the cap, an unreadable or empty cap read does not arm the alert again", function()
  local ns = Start({ q = 24990, widget = { pvp = "honor" } })
  Stub.GainHonor(10)
  T.eq(#Stub.pvp.sounds, 1)
  Stub.RunScript(ns.Pvp.GetAlert().tp.ok, "OnClick")
  Stub.pvp.secret.maxQuantity = true               -- one read without its cap
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  Stub.pvp.secret.maxQuantity = nil
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.eq(#Stub.pvp.sounds, 1, "the same reaching")
  T.eq(ns.char.pvp.a, true)
  Stub.pvp.empty = { honor = 1 }                   -- an empty read
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.eq(#Stub.pvp.sounds, 1)
  -- a valid read below the cap arms it
  Stub.SpendHonor(10)
  T.eq(ns.char.pvp.a, nil)
  Stub.GainHonor(10)
  T.eq(#Stub.pvp.sounds, 2)
  T.eq(Stub.errors, {})
end)

T.test("pvp review 10: read-only mode at the cap: one alert for the load, kept in memory", function()
  local ns = Start({ q = 25000, db = { schema = 99, settings = { firstRunDone = true }, chars = {} } })
  T.ok(ns.readOnly)
  T.eq(#Stub.pvp.sounds, 1, "at the login")
  Stub.RunScript(ns.Pvp.GetAlert().tp.ok, "OnClick")
  Stub.pvp.secret.maxQuantity = true
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  Stub.pvp.secret.maxQuantity = nil
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  Stub.Advance(60)
  T.eq(#Stub.pvp.sounds, 1, "not again in this load")
  T.eq(ns.char.pvp, nil, "nothing written")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 11. A strip that would repeat the main bar
---------------------------------------------------------------------------

T.test("pvp review 11: a PvP strip showing what the PvP main bar shows is hidden; the other one shows", function()
  local ns, _, tp = Start({ theme = "futuriste", total = 2000, settings = { ["widget.main"] = "pvp" } })
  ns.Core.SetSetting("widget.pvp", "rank")
  T.eq(Strip(tp), nil, "the rank under the rank: hidden")
  T.eq(Hit(tp.pvpStripHit), nil)
  ns.Core.SetSetting("widget.pvp", "honor")
  T.ok(Strip(tp) ~= nil, "the honor under the rank")
  ns.Core.SetSetting("widget.main", "xp")
  ns.Core.SetSetting("widget.pvp", "rank")
  T.ok(Strip(tp) ~= nil, "the rank under the XP")
  -- before a season the main bar shows the honor: the honor strip hidden, the rank's shown
  Stub.Reset()
  ns, _, tp = Start({ theme = "futuriste", season = false, settings = { ["widget.main"] = "pvp",
                                                                       ["widget.pvp"] = "honor" } })
  T.eq(ns.Pvp.MainKind(), "honor")
  T.eq(Strip(tp), nil, "the honor under the honor: hidden")
  ns.Core.SetSetting("widget.pvp", "rank")
  T.ok(Strip(tp) ~= nil)
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 13. Rank points without a week number (review case J)
---------------------------------------------------------------------------

T.test("pvp review 13: rank points with week -1: the rank shows (no 'season not started'), its rate measures", function()
  local ns = Start({ season = false, total = 3000, settings = { ["widget.pvp"] = "rank" } })
  local P = ns.Pvp
  local r = { P.Rank() }
  T.eq({ r[2], r[6] }, { 3, false }, "rank 3, a season")
  T.eq(P.MainKind(), "rank")
  Stub.EnterBG()
  Stub.GainRankPoints(100)
  Stub.Advance(300)
  T.ok(ns.char.pvp.ke[1].d > 0, "measured")
  T.eq(select(2, P.RankEta(0)), "warming")
  -- week -1 and no point: no season
  Stub.Reset()
  ns = Start({ season = false, total = 0, settings = { ["widget.pvp"] = "rank" } })
  T.eq(select(6, ns.Pvp.Rank()), true)
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 14. The daily reset passing without an event (review case L)
---------------------------------------------------------------------------

T.test("pvp review 14: the daily reset passes without an event: today's kills read again (token, tooltip)", function()
  local ns, _, tp = Start({ theme = "futuriste", total = 1000,
                            settings = { ["widget.slots.1"] = "hk_today", ["widget.pvp"] = "honor" } })
  local Tokens, L = ns.Tokens, ns.L
  Stub.HK(5)
  Stub.Advance(1)
  T.eq(Tokens.Render("hk_today"), format(L.PFX_HK_FMT, "5"))
  Stub.Advance(30)
  T.eq(Tokens.Render("hk_today"), format(L.PFX_HK_FMT, "5"), "nothing while the countdown runs")
  Stub.DailyReset()
  Stub.Advance(2)
  T.eq(Tokens.Render("hk_today"), format(L.PFX_HK_FMT, "0"), "the new day")
  T.eq(select(2, ns.Pvp.Kills()), 5, "yesterday's")
  -- the tooltip opening reads them too
  Stub.pvp.hkToday = 2
  Stub.RunScript(tp.pvpHit, "OnEnter")
  Stub.Advance(1)
  T.eq(FindRow(TipRows(ns), L.TT_PVP_TODAY).right, "2")
  Stub.RunScript(tp.pvpHit, "OnLeave")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 15. The winner and the arenas
---------------------------------------------------------------------------

T.test("pvp review 15: the winner against GetBattlefieldArenaFaction (UnitFactionGroup without it); arenas not counted", function()
  local ns = Start({ widget = { pvp = "honor" } })
  local P = ns.Pvp
  T.eq(Stub.player.faction, "Horde")
  Stub.pvp.team = 1                                -- on the Alliance's side
  Stub.EnterBG()
  Stub.MatchComplete(1, 300)
  Stub.LeaveBG()
  T.eq({ select(3, P.Session()) }, { 1, 0, 1, 0, 300 }, "won with the Alliance's side")
  Stub.pvp.team = nil                              -- not given: the player's faction
  Stub.EnterBG()
  Stub.MatchComplete(1, 300)
  Stub.LeaveBG()
  T.eq({ select(3, P.Session()) }, { 1, 1, 2, 0, 300 })
  -- an arena: PvP time, no battleground counted
  Stub.EnterBG({ arena = true })
  T.eq({ P.InBG() }, { true, false })
  Stub.GainHonor(100)
  Stub.Advance(300)
  Stub.MatchComplete(0, 300)
  Stub.LeaveBG()
  T.eq(select(5, P.Session()), 2, "the arena not counted")
  T.ok(ns.char.pvp.he[1].d > 0, "its time counted for the rates")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 16. The events only while something shows PvP
---------------------------------------------------------------------------

T.test("pvp review 16: the rank and battleground events only while something shows PvP; the honor for the alert", function()
  local ns = Start({ total = 1000, pvp = { capAlert = false }, widget = {} })
  local calls = Stub.pvp.calls
  local P = ns.Pvp
  local function Reads()
    return calls.GetProgression, calls.GetCurrencyInfo
  end
  -- nothing shows PvP, no alert. Adapted for the world PvP per level (design/NEXT-LOT.md,
  -- Levels tab: the statistics window always shows PvP, so its signals are measured
  -- whatever the bar shows): the honor and today's kills are read on their own events
  -- (world PvP signals), once each; everything else stays off as before: the rank is not
  -- read (UPDATE_FACTION not registered), no zone event (the place read by Pvp.Advance
  -- alone, for the honor rate: no battleground counted), TICK does no PvP work (no reset
  -- countdown read) and nothing sends PVP_CHANGED (no UI work).
  local ticks, changed, owner = 0, 0, {}
  local dt = rawget(_G, "C_DateAndTime")
  local weekly = dt.GetSecondsUntilWeeklyReset
  dt.GetSecondsUntilWeeklyReset = function()
    ticks = ticks + 1
    return weekly()
  end
  ns.RegisterMessage("PVP_CHANGED", owner, function() changed = changed + 1 end)
  local r0, c0 = Reads()
  Stub.GainRankPoints(100)
  Stub.GainHonor(100)
  Stub.HK(1)
  Stub.EnterBG()
  Stub.Advance(60)
  T.eq({ P.InBG() }, { true, true }, "inside: the place read by Pvp.Advance")
  Stub.LeaveBG()
  local rN, cN = Reads()
  T.eq(rN, r0, "the rank not read")
  T.eq(cN, c0 + 1, "the honor read on its event, nothing more")
  T.eq((P.Kills()), 1, "today's kills read on their event")
  T.eq(select(5, P.Session()), 0, "no battleground")
  T.eq(ticks, 0, "no PvP work on TICK")
  T.eq(changed, 0, "no PVP_CHANGED")
  ns.UnregisterMessage("PVP_CHANGED", owner)
  -- the alert: the honor alone
  ns.Core.SetSetting("pvp.capAlert", true)
  r0, c0 = Reads()
  Stub.GainHonor(100)
  Stub.GainRankPoints(100)
  local r1, c1 = Reads()
  T.eq(r1, r0, "the rank not read")
  T.ok(c1 > c0, "the honor read")
  -- each way to show PvP turns every read on; a new base then (nothing counted from before)
  for _, set in ipairs({ { "widget.pvp", "rank", "off" }, { "widget.main", "pvp", "xp" }, { "widget.pvpAuto", true, false },
                         { "widget.slots.2", "rank_h", "none" }, { "widget.maxSlots.1", "honor", "none" } }) do
    ns.Core.SetSetting("pvp.capAlert", false)
    local a = ns.char.pvp.ke[1].a
    Stub.GainRankPoints(500)                       -- unseen
    ns.Core.SetSetting(set[1], set[2])
    T.eq(ns.char.pvp.ke[1].a, a, set[1] .. ": a new base")
    r0 = calls.GetProgression
    Stub.GainRankPoints(10)
    T.ok(calls.GetProgression > r0, set[1] .. ": read")
    T.eq(ns.char.pvp.ke[1].a, a + 10, set[1] .. ": counted")
    ns.Core.SetSetting(set[1], set[3])
    r0 = calls.GetProgression
    Stub.GainRankPoints(10)
    T.eq(calls.GetProgression, r0, set[1] .. ": off again")
  end
  -- the mini display's infos
  ns.Core.SetSetting("mini.infos.1", "rank")
  r0 = calls.GetProgression
  Stub.GainRankPoints(10)
  T.eq(calls.GetProgression, r0, "a hidden mini display")
  ns.Core.SetSetting("mini.shown", true)
  r0 = calls.GetProgression
  Stub.GainRankPoints(10)
  T.ok(calls.GetProgression > r0, "the mini display shows a PvP info")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 17. A reload in a battleground, nothing showing PvP
---------------------------------------------------------------------------

T.test("pvp review 17: nothing shows PvP, a reload in a battleground, then an hour out of it: the honor rate pauses", function()
  Start({ total = 1000, widget = {} })
  Stub.EnterBG({ loading = true })
  local ns = Stub.Restart({ reload = true, online = 5, settle = 3 })
  local P, IDLE = ns.Pvp, ns.C.PVP_IDLE
  T.eq({ P.InBG() }, { true, true }, "in the battleground at the load")
  Stub.GainHonor(100)
  Stub.Advance(60)
  -- the zone events are not registered: Pvp.Advance reads the place itself (the honor rate
  -- is measured whatever is shown), else the hour out of the battleground counts as PvP
  -- time and drags the honor per hour down
  Stub.LeaveBG({ loading = true })
  Stub.Advance(1)
  T.eq({ P.InBG() }, { false, false }, "left: the place read again")
  local d0 = ns.char.pvp.he[1].d
  Stub.Advance(3600)
  T.ok(ns.char.pvp.he[1].d - d0 <= IDLE, format("at most %d s counted out of it (%.1f)", IDLE, ns.char.pvp.he[1].d - d0))
  T.eq(select(2, P.Rate("honor", 0)), "paused", "paused 15 min after the last gain")
  T.eq(select(5, P.Session()), 0, "no battleground counted")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- 18. Wording
---------------------------------------------------------------------------

T.test("pvp review 18: the rank points per hour never read as a rank number; the week's cap label", function()
  for _, code in ipairs({ "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }) do
    local saved = Stub.locale
    Stub.locale = code
    local lns = {}
    if code ~= "enUS" then lns.L = {} end
    assert(loadfile(Stub.ROOT .. "Locales/" .. code .. ".lua"))("TruePlayed", lns)
    Stub.locale = saved
    local L = (code == "enUS") and lns.L or lns.LOCALES[code]
    local rate = L.PFX_RANKH_FMT:gsub("%%s", "")
    local rank = L.PVP_RANK_FMT:gsub("%%d", "")
    T.ok(rate ~= rank, code .. ": " .. L.PFX_RANKH_FMT .. " vs " .. L.PVP_RANK_FMT)
  end
  Stub.locale = "frFR"
  local ns = Start({ total = 1000, settings = { ["widget.pvp"] = "rank" } })
  T.eq(ns.L.TT_PVP_WEEK_CAP_FMT, "Plafond de la semaine %d")
  T.eq(ns.L.PFX_RANKH_FMT, "Pts de rang %s")
  T.eq(Stub.errors, {})
end)
