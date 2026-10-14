-- tests/test_pvp.lua - the PvP engine on WoW Forever (Pvp.lua): the honor and the PvP rank
-- read from their APIs (bases at the first read of a load, gains between reads: the
-- quantity's own rise, never the event's quantityChange; spending and a new season taking
-- a new base), the PvP time (battlegrounds, the open world up to C.PVP_IDLE after a gain, then
-- paused), the rates (warm-up, statuses, kept at the honor cap, the weekly cap, the max
-- rank; the rank's EMA untouched while nothing shows PvP), no season (the beta's values), the honorable kills (stale counts after a login),
-- the battlegrounds of the session (won, lost, averages; PVP_MATCH_COMPLETE or
-- GetBattlefieldWinner, never C_PvP's scores), the honor cap alert (after the fight, once
-- per reaching, the option), char.pvp (persisted, repaired, reset, nothing in read-only
-- mode), Classic Era's dormancy, guards (secrets, errors, odd fields) and the allocation
-- of the TICK path. The stub (tests/stub_pvp.lua) installs no PvP API unless a test says
-- so; Start installs Forever's with a season running (week 2, cap rank 5) by default.
local Stub, T = ...

local format, exp = string.format, math.exp

local TAU = 3600                 -- settings.rateTau (default)

-- Counted seconds of an EMA after n seconds of PvP time from zero.
local function D(n)
  return TAU * (1 - exp(-n / TAU))
end

-- Loads the addon; opts: api ("forever"), season (false: the beta's week -1, cap 0), week,
-- cap, prev, total (season total of the rank), q, max (honor), hkLife, bg (logged in a
-- battleground), db, theme, ui, settings ({ path = value }). Without opts.db the PvP strip
-- shows the rank from the login on (something shows PvP: every event registered).
local function Start(opts)
  opts = opts or {}
  Stub.InstallUI(opts.ui or { ldb = false })
  if opts.theme then Stub.theme = opts.theme end
  Stub.SetPvpAPI(opts.api or "forever")
  local s = Stub.pvp
  if opts.season ~= false then Stub.SetWeek(opts.week or 2, opts.cap or 5, opts.prev or 3, { quiet = true }) end
  if opts.total then s.total = opts.total end
  if opts.q then s.q = opts.q end
  if opts.max then s.max = opts.max end
  if opts.hkLife then s.hkLife = opts.hkLife end
  rawset(_G, "TruePlayedDB", opts.db or { schema = 1, settings = { firstRunDone = true, widget = { pvp = "rank" } } })
  if opts.bg then
    Stub.player.inInstance, Stub.player.instanceType = true, "pvp"
  end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  for k, v in pairs(opts.settings or {}) do ns.Core.SetSetting(k, v) end
  return ns, ns.Pvp
end

local function Pack(...)
  return { n = select("#", ...), ... }
end

local function Now()
  return time()
end

---------------------------------------------------------------------------
-- Reads and gains
---------------------------------------------------------------------------

T.test("pvp: the first read of a load takes the bases (honor, rank, kills); nothing counts as a gain", function()
  local ns, P = Start({ total = 1000 })
  T.ok(P.Available())
  T.ok(P.Has())
  local on, q, max, capAt = P.Honor()
  T.eq({ on, q, max, capAt }, { true, 1024, 25000, nil })
  local r = Pack(P.Rank())
  T.eq({ r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9] }, { true, 1, 250, 900, 14, false, false, 1000, 750 },
    "rank 1, 250 of its 900 points, season total 1000")
  local p = ns.char.pvp
  T.eq({ p.h, p.k, p.hk }, { 1024, 1000, 87 }, "the bases")
  T.eq({ p.he[1].a, p.ke[1].a, p.g }, { 0, 0, nil }, "no gain, no PvP time")
  T.eq({ P.Session() }, { 0, 0, 0, 0, 0 })
  T.eq({ P.Week() }, { 2, 5, 5250, 3, false, false }, "week 2, rank 5 at most (5,250 points)")
  local today, yest, ses, life, high = P.Kills()
  T.eq({ today, yest, ses, life, high }, { 0, 0, 0, 87, 0 })
  local v, status = P.Rate("honor", 0)
  T.eq({ v, status }, { nil, "nodata" })
  T.eq(P.MainKind(), "rank")
  T.eq(Stub.errors, {})
end)

T.test("pvp honor: gains from the quantity's rise (the event's payload not used), spending takes a new base", function()
  local ns, P = Start()
  local p = ns.char.pvp
  Stub.Advance(10)
  Stub.GainHonor(100)
  T.eq({ p.he[1].a, p.h, (P.Session()) }, { 100, 1124, 100 })
  T.eq(p.g, Now(), "the time of the last gain")
  for m = 1, 8 do T.eq(p.he[m].a, 100, "every mask") end
  Stub.GainHonor(50, { change = 500 })            -- the payload above the rise: the rise
  T.eq(p.he[1].a, 150)
  Stub.GainHonor(50, { change = 20 })             -- below it (two gains read at once): the rise
  T.eq(p.he[1].a, 200)
  Stub.GainHonor(30, { change = "x" })            -- not a number: the rise
  T.eq(p.he[1].a, 230)
  Stub.GainHonor(30, { change = Stub.SECRET })    -- secret: the rise
  T.eq(p.he[1].a, 260)
  Stub.GainHonor(30, { change = -5 })             -- negative: the rise
  T.eq(p.he[1].a, 290)
  -- another currency: not even read
  local reads = Stub.pvp.calls.GetCurrencyInfo
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1901, 5, 5)
  T.eq(Stub.pvp.calls.GetCurrencyInfo, reads, "another currency")
  -- no currency id (a refresh of every currency): read; no rise, no gain
  Stub.Fire("CURRENCY_DISPLAY_UPDATE")
  T.eq(Stub.pvp.calls.GetCurrencyInfo, reads + 1)
  T.eq(p.he[1].a, 290)
  -- spending: a new base, the rate unchanged
  Stub.SpendHonor(500)
  T.eq({ p.h, p.he[1].a, (P.Session()) }, { 814, 290, 290 })
  Stub.GainHonor(40)
  T.eq({ p.h, p.he[1].a, (P.Session()) }, { 854, 330, 330 }, "from the new base")
  -- an event sent twice: the second one sees no rise
  Stub.GainHonor(25, { quiet = true })
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792, 879, 25)
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792, 879, 25)
  T.eq(p.he[1].a, 355)
  T.eq(Stub.errors, {})
end)

T.test("pvp rank: gains from the season total, a new rank, another faction ignored, a new season", function()
  local ns, P = Start({ total = 1000 })
  local p = ns.char.pvp
  Stub.GainRankPoints(300)
  T.eq({ p.ke[1].a, p.k }, { 300, 1300 })
  local _, rs = P.Session()
  T.eq(rs, 300, "rank points this session")
  Stub.GainRankPoints(500)                         -- 1800: rank 2 (1650), 150 of 1050
  local r = Pack(P.Rank())
  T.eq({ r[2], r[3], r[4], r[8], r[9] }, { 2, 150, 1050, 1800, 1650 })
  T.eq(p.ke[1].a, 800)
  -- another major faction's event: not read
  local reads = Stub.pvp.calls.GetProgression
  Stub.Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2510, 3, 2)
  T.eq(Stub.pvp.calls.GetProgression, reads, "another faction")
  Stub.Fire("UPDATE_FACTION")
  T.eq(p.ke[1].a, 800, "no change, no gain")
  -- a new season (the total drops, the week number starts over): a new base
  Stub.pvp.total = 0
  Stub.SetWeek(1, 3, 0)
  T.eq({ p.k, p.ke[1].a }, { 0, 800 })
  Stub.GainRankPoints(200)
  T.eq(p.ke[1].a, 1000)
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- PvP time and the rates
---------------------------------------------------------------------------

T.test("pvp time: nothing before a gain; the open world counts 15 min after a gain, then pauses", function()
  local ns, P = Start()
  local p = ns.char.pvp
  T.eq(ns.C.PVP_IDLE, 900)
  Stub.Advance(600)
  T.eq({ p.he[1].d, p.ke[1].d }, { 0, 0 }, "no PvP time without a gain")
  Stub.GainHonor(100)
  Stub.Advance(300)
  T.near(p.he[1].d, D(300), 3, "5 min after the gain")
  T.near(p.ke[1].d, D(300), 3, "the rank's rate counts the same time")
  local v, status = P.Rate("honor", 0)
  T.eq(status, "warming")
  T.near(v, 3600 * p.he[1].a / p.he[1].d, 1e-6)
  Stub.Advance(900)                                -- 20 min after the gain: 15 counted
  T.near(p.he[1].d, D(900), 3, "only C.PVP_IDLE seconds after the gain")
  local a, d = p.he[1].a, p.he[1].d
  v, status = P.Rate("honor", 0)
  T.eq(status, "paused")
  Stub.Advance(1800)
  T.eq({ p.he[1].a, p.he[1].d }, { a, d }, "paused: no decay")
  local v2, status2, _, idle = P.Rate("honor", 0)
  T.eq({ v2, status2 }, { v, "paused" }, "the rate kept as it was")
  T.ok(idle >= 3000, "seconds since the last gain")
  -- the next gain resumes it
  Stub.GainHonor(50)
  T.eq(select(2, P.Rate("honor", 0)), "ok")
  Stub.Advance(60)
  T.near(p.he[1].d, d * exp(-60 / TAU) + D(60), 2, "counting again")
  T.eq(Stub.errors, {})
end)

T.test("pvp time: a battleground counts all its time, gains or not; the pause applies once out", function()
  local ns, P = Start()
  local p = ns.char.pvp
  Stub.EnterBG()
  T.eq({ P.InBG() }, { true, true })
  Stub.Advance(600)
  T.near(p.he[1].d, D(600), 3, "every second of the battleground, before a first gain too")
  T.eq({ P.Rate("honor", 0) }, { nil, "nodata", 0 }, "no value before a first gain")
  Stub.GainHonor(100)
  Stub.Advance(1500)
  T.near(p.he[1].d, D(2100), 3, "every second of the battleground")
  local _, status = P.Rate("honor", 0)
  T.eq(status, "ok", "not paused in a battleground, 25 min after the gain")
  Stub.LeaveBG()
  T.eq({ P.InBG() }, { false, false })
  _, status = P.Rate("honor", 0)
  T.eq(status, "paused", "out of it, more than 15 min after the gain")
  local d = p.he[1].d
  Stub.Advance(300)
  T.eq(p.he[1].d, d)
  -- an arena is PvP time too, without the battleground's main bar
  Stub.EnterBG({ arena = true })
  T.eq({ P.InBG() }, { true, false })
  Stub.Advance(60)
  T.ok(p.he[1].d > d)
  T.eq(Stub.errors, {})
end)

-- Nothing shows PvP (UPDATE_FACTION not registered: no rank gain counted): the rank's EMA
-- must not decay either, with the cap alert off or on (review pvpdata-2); shown, the rank
-- measures from a new base at its real rate.
T.test("pvp rates: nothing shows PvP: the rank EMA neither counts nor decays; shown, its real rate", function()
  for _, alert in ipairs({ false, true }) do
    Stub.Reset()
    local ns, P = Start({ db = { schema = 1, settings = { firstRunDone = true, widget = {},
      pvp = { capAlert = alert } } } })
    local p = ns.char.pvp
    local what = alert and "alert on" or "alert off"
    T.ok(P.Rank() ~= nil, what .. ": the rank read once (the season running)")
    Stub.EnterBG()
    for _ = 1, 10 do
      Stub.GainHonor(20)
      Stub.GainRankPoints(50)
      Stub.Advance(60)
    end
    T.eq({ p.ke[1].a, p.ke[1].d }, { 0, 0 }, what .. ": the rank EMA untouched")
    T.near(p.he[1].d, D(600), 3, what .. ": the honor counted")
    ns.Core.SetSetting("widget.pvp", "rank")      -- shown: a new base, the gains counted
    for _ = 1, 10 do
      Stub.GainHonor(20)
      Stub.GainRankPoints(50)
      Stub.Advance(60)
    end
    local v = P.Rate("rank", 0)
    T.ok(v and v > 2700 and v < 3300, format("%s: about 3,000 points per hour (%s)", what, tostring(v)))
  end
  T.eq(Stub.errors, {})
end)

T.test("pvp rates: warm-up (nothing, then dimmed from 120 counted s, ok from 600), the value per hour", function()
  local ns, P = Start()
  local p = ns.char.pvp
  Stub.EnterBG()
  Stub.GainHonor(100)
  Stub.Advance(60)
  local v, status, left = P.Rate("honor", 0)
  T.eq({ v, status }, { nil, "nodata" })
  T.near(left, 600 - D(60), 2, "counted seconds still needed")
  Stub.Advance(70)
  v, status = P.Rate("honor", 0)
  T.eq(status, "warming")
  T.near(v, 3600 * p.he[1].a / p.he[1].d, 1e-6)
  for _ = 1, 10 do
    Stub.Advance(60)
    Stub.GainHonor(100)
  end
  v, status = P.Rate("honor", 0)
  T.eq(status, "ok")
  T.ok(v > 4000 and v < 7000, format("about 6,000 honor per hour: %.0f", v))
  -- the time to the cap at that rate (counted seconds)
  local eta, est = P.HonorEta(0)
  T.eq(est, "ok")
  T.near(eta, (25000 - Stub.pvp.q) / (v / 3600), 1e-6)
  -- per exclusion mask: the same here (nothing excluded)
  local v1 = P.Rate("honor", 1)
  T.near(v1, v, 1e-6)
  T.eq(Stub.errors, {})
end)

T.test("pvp rates: at the honor cap the gains are lost and the rate is kept (capped); spent, it measures", function()
  local ns, P = Start({ q = 24800 })
  local p = ns.char.pvp
  Stub.EnterBG()
  Stub.GainHonor(50)
  Stub.Advance(700)
  T.eq(select(3, P.Value("honor")), ns.Pvp.KEY_WARN, "orange from 90 % of the cap")
  local t0 = Now()
  Stub.GainHonor(400)                              -- 24850 + 400: held at 25000
  T.eq({ P.Honor() }, { true, 25000, 25000, t0 })
  local a = p.he[1].a
  Stub.GainHonor(100)                              -- lost: no rise
  T.eq(p.he[1].a, a, "a gain at the cap is lost: nothing counted")
  local d = p.he[1].d
  Stub.Advance(300)
  T.eq({ p.he[1].a, p.he[1].d }, { a, d }, "not decayed at the cap")
  local _, status = P.Rate("honor", 0)
  T.eq(status, "capped")
  T.eq({ P.HonorEta(0) }, { 0, "capped" })
  T.eq({ P.Value("honor") }, { 25000, 25000, ns.Pvp.KEY_CAP, true })
  -- the rank's rate is not held by the honor cap
  T.ok(p.ke[1].d > 0)
  Stub.SpendHonor(1000)
  T.eq(select(4, P.Honor()), nil, "below the cap again")
  _, status = P.Rate("honor", 0)
  T.eq(status, "ok")
  Stub.Advance(10)
  T.ok(p.he[1].d > d, "measures again")
  T.eq({ P.Value("honor") }, { 24000, 25000, ns.Pvp.KEY_WARN, false })
  T.eq(Stub.errors, {})
end)

T.test("pvp rank: the weekly cap (the next rank is the cap, then capped until the weekly reset), the max rank", function()
  local ns, P = Start({ cap = 3, total = 2500 })   -- rank 2 (1650), 850 of 1050; cap 2700
  local p = ns.char.pvp
  T.eq({ P.Week() }, { 2, 3, 2700, 3, false, true }, "rank 3 is the week's last")
  Stub.EnterBG()
  Stub.GainRankPoints(100)
  Stub.Advance(300)
  local eta, est, nxt = P.RankEta(0)
  T.eq({ est, nxt }, { "warming", 3 })
  T.ok(eta > 0)
  Stub.GainRankPoints(500)                         -- held at 2700: rank 3, 0 of 1200
  local r = Pack(P.Rank())
  T.eq({ r[2], r[3], r[4], r[8] }, { 3, 0, 1200, 2700 })
  T.eq({ P.Week() }, { 2, 3, 2700, 3, true, false }, "the week's cap reached")
  T.eq({ P.RankEta(0) }, { nil, "capped", 4 })
  local _, status = P.Rate("rank", 0)
  T.eq(status, "capped")
  local a, d = p.ke[1].a, p.ke[1].d
  Stub.Advance(300)
  T.eq({ p.ke[1].a, p.ke[1].d }, { a, d }, "not decayed at the week's cap")
  T.ok(p.he[1].d > 0, "the honor's rate goes on")
  local r1, r2, r3 = P.MainRight(0)
  T.eq({ r1, r2, r3 }, { ns.L.PVP_WEEK_CAPPED, ns.L.PVP_WEEK_CAPPED_SHORT, ns.L.PVP_WEEK_CAPPED_SHORT })
  T.eq(P.WeeklyReset(), 3 * 86400)
  -- the weekly reset: a higher cap
  Stub.SetWeek(3, 5, 3)
  T.eq({ P.Week() }, { 3, 5, 5250, 3, false, false })
  local _, est2 = P.RankEta(0)
  T.ok(est2 ~= "capped")
  Stub.Advance(10)
  T.ok(p.ke[1].d > d)
  -- the max rank: full, no next rank
  Stub.SetWeek(10, 14, 13, { quiet = true })
  Stub.GainRankPoints(30000)
  r = Pack(P.Rank())
  T.eq({ r[2], r[7], r[8] }, { 14, true, 24750 })
  T.eq({ P.Value("rank") }, { 3000, 3000, 4, true })
  T.eq({ P.RankEta(0) }, { nil, "max", nil })
  T.eq(select(5, P.Week()), false, "the max rank is not a weekly cap")
  r1 = P.MainRight(0)
  T.eq(r1, ns.L.PVP_RANK_MAX)
  _, status = P.Rate("rank", 0)
  T.eq(status, "capped")
  -- no threshold read at the top: still full, nothing divided by zero
  local api = rawget(_G, "C_MajorFactions")
  local orig = api.GetMajorFactionProgressionInfo
  api.GetMajorFactionProgressionInfo = function(id)
    local t = orig(id)
    t.renownLevelThreshold = 0
    return t
  end
  Stub.Fire("UPDATE_FACTION")
  T.eq({ P.Value("rank") }, { 1, 1, 4, true })
  T.eq(Stub.errors, {})
end)

T.test("pvp: no season (the beta's values) shows the honor toward its cap and divides by nothing", function()
  local ns, P = Start({ season = false })
  local p = ns.char.pvp
  local r = Pack(P.Rank())
  T.eq({ r[1], r[2], r[3], r[4], r[6], r[7], r[8] }, { true, 0, 0, 750, true, false, 0 })
  T.eq({ P.Week() }, { -1, 0, 0, 0, false, false })
  T.eq(P.MainKind(), "honor", "no season: the honor toward its cap")
  T.eq({ P.RankEta(0) }, { nil, "noseason", nil })
  T.eq(P.MainRight(0), nil)
  T.eq({ P.Value("rank") }, { 0, 750, 4, false })
  Stub.EnterBG()
  Stub.GainHonor(100)
  Stub.Advance(300)
  T.eq(p.ke[1].d, 0, "the rank's rate does not count without a season")
  T.ok(p.he[1].d > 0)
  T.eq(P.SeasonEnd(), nil, "0 from the game: unknown")
  -- a week number with no cap and no point is no season either; points make one
  Stub.SetWeek(1, 0, 0)
  T.eq(select(6, P.Rank()), true)
  Stub.GainRankPoints(100)
  T.eq(select(6, P.Rank()), false, "points: a season")
  T.eq(P.MainKind(), "rank")
  -- neither: no main kind (the bar shows the XP)
  Stub.pvp.total = 0
  Stub.SetWeek(-1, 0, 0)
  Stub.pvp.max = 0
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792, Stub.pvp.q, 0)
  T.eq(P.MainKind(), nil)
  T.eq(P.MainMode({ main = "pvp" }), "xp")
  T.eq({ P.HonorEta(0) }, { nil, "nocap" })
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Kills and battlegrounds
---------------------------------------------------------------------------

T.test("pvp kills: today, yesterday, this session, lifetime; a stale 0 or lower count after login ignored", function()
  local ns, P = Start({ hkLife = 0 })              -- the count reads 0 right after the login
  local k = Pack(P.Kills())                        -- today, yesterday, session, lifetime
  T.eq({ k[1], k[2], k[3], k[4] }, { 0, 0, nil, 0 }, "no session count from a 0")
  Stub.pvp.hkLife = 87
  Stub.HK(2)
  k = Pack(P.Kills())
  T.eq({ k[1], k[3], k[4] }, { 2, 2, 89 },
    "the first real count, less today's kills since the session began, is the session's start")
  Stub.HK(3)
  k = Pack(P.Kills())
  T.eq({ k[1], k[3], k[4] }, { 5, 5, 92 })
  Stub.pvp.hkLife = 10                             -- an old value: ignored
  Stub.Fire("PLAYER_PVP_KILLS_CHANGED", "player")
  T.eq(select(4, P.Kills()), 92)
  T.eq(ns.char.pvp.hk, 92)
  Stub.pvp.hkLife = 92
  Stub.pvp.hkYest = 14
  Stub.pvp.hkHigh = 9
  P.ReadAgain()                                    -- the tooltip reads them again
  local _, y, _, _, high = P.Kills()
  T.eq({ y, high }, { 14, 9 })
  -- across a reload: the session goes on
  ns = Stub.Restart({ reload = true, settle = 3 })
  Stub.HK(1)
  k = Pack(ns.Pvp.Kills())
  T.eq({ k[3], k[4] }, { 6, 93 })
  -- unreadable counts
  Stub.pvp.secret.hk = true
  ns.Pvp.ReadAgain()
  k = Pack(ns.Pvp.Kills())
  T.eq({ k[1], k[2] }, { nil, nil })
  T.eq(select(4, ns.Pvp.Kills()), 93, "the last lifetime count kept")
  T.eq(Stub.errors, {})
end)

T.test("pvp battlegrounds: won, lost, a draw, the winner's fallback, averages; C_PvP's scores never read", function()
  local ns, P = Start()
  T.eq(Stub.player.faction, "Horde")
  Stub.EnterBG({ loading = true })
  local p = ns.char.pvp
  T.ok(type(p.b) == "table" and p.b.at == Now(), "a battleground in progress")
  Stub.Advance(600)
  Stub.GainHonor(300)
  Stub.MatchComplete(0, 900)                       -- the Horde won, in 15 min
  Stub.LeaveBG({ loading = true })
  T.eq(p.b, nil)
  T.eq({ P.Session() }, { 300, 0, 1, 0, 1, 300, 900 })
  -- lost, the length from the time spent (no duration given)
  Stub.EnterBG()
  local at = Now()
  Stub.Advance(1200)
  Stub.GainHonor(100)
  Stub.MatchComplete(1, nil)
  Stub.Advance(30)
  Stub.LeaveBG()
  local h, _, w, l, n, ah, ad = P.Session()
  T.eq({ h, w, l, n, ah }, { 400, 1, 1, 2, 200 })
  T.near(ad, (900 + (Now() - at)) / 2, 1e-9)
  -- a draw: neither
  Stub.EnterBG()
  Stub.MatchComplete(255, 600)
  Stub.LeaveBG()
  T.eq({ select(3, P.Session()) }, { 1, 1, 3, 400 / 3, (900 + 1230 + 600) / 3 })
  -- no PVP_MATCH_COMPLETE: GetBattlefieldWinner at UPDATE_BATTLEFIELD_STATUS
  Stub.EnterBG()
  Stub.pvp.winner = 0
  Stub.Fire("UPDATE_BATTLEFIELD_STATUS", 1)
  Stub.LeaveBG()
  T.eq({ select(3, P.Session()) }, { 2, 1, 4, 100, (900 + 1230 + 600) / 4 })
  -- an Alliance character: the winner 1 is a win
  Stub.player.faction = "Alliance"
  Stub.EnterBG()
  Stub.MatchComplete(1, 60)
  Stub.LeaveBG()
  local _, _, w2, l2, n2 = P.Session()
  T.eq({ w2, l2, n2 }, { 3, 1, 5 })
  -- a match completed outside a battleground: nothing
  Stub.MatchComplete(1, 60)
  T.eq(select(5, P.Session()), 5)
  T.eq(Stub.pvp.calls.Score, 0, "C_PvP's scores never read")
  T.eq(Stub.errors, {})
end)

T.test("pvp battlegrounds: one in progress across a reload is kept; one left while logged out is dropped", function()
  local ns = Start()
  Stub.EnterBG()
  Stub.GainHonor(100)
  Stub.Advance(60)
  local at = ns.char.pvp.b.at
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.eq(ns.char.pvp.b.at, at, "kept across a reload")
  T.eq({ ns.Pvp.InBG() }, { true, true })
  Stub.MatchComplete(0, 300)
  Stub.LeaveBG()
  T.eq(select(5, ns.Pvp.Session()), 1)
  -- logged out inside, back outside: not counted
  Stub.EnterBG()
  Stub.Logout()
  Stub.player.inInstance, Stub.player.instanceType = false, "none"
  ns = Stub.Restart({ crash = true, settle = 3 })
  T.eq(ns.char.pvp.b, nil, "dropped")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- The honor cap alert
---------------------------------------------------------------------------

T.test("pvp alert: at the cap a sound and the frame, once per reaching; OK hides it; armed again below", function()
  local ns, P = Start({ q = 24990 })
  T.eq(P.GetAlert(), nil, "not built before")
  Stub.GainHonor(10)
  local f, pending = P.GetAlert()
  T.ok(f and f:IsShown(), "shown")
  T.no(pending)
  T.eq(Stub.pvp.sounds, { { 8959, "Master" } })
  T.match(f.tp.text:GetText(), "25,000")
  T.eq(f.tp.title:GetText(), ns.L.ADDON_TITLE)
  T.eq(f.tp.okText:GetText(), ns.L.PVP_ALERT_OK)
  T.eq(ns.char.pvp.a, true)
  Stub.RunScript(f.tp.ok, "OnClick")
  T.no(f:IsShown(), "OK hides it")
  Stub.GainHonor(100)
  Stub.Fire("CURRENCY_DISPLAY_UPDATE")
  T.no(f:IsShown())
  T.eq(#Stub.pvp.sounds, 1, "once per reaching")
  -- across a reload: not again
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.eq(#Stub.pvp.sounds, 1)
  -- spent: armed again
  Stub.SpendHonor(50)
  T.eq(ns.char.pvp.a, nil)
  Stub.GainHonor(50)
  T.eq(#Stub.pvp.sounds, 2, "the next reaching")
  T.ok(ns.Pvp.GetAlert():IsShown())
  -- spending while it is shown hides it
  Stub.SpendHonor(10)
  T.no(ns.Pvp.GetAlert():IsShown())
  T.eq(Stub.errors, {})
end)

T.test("pvp alert: reached in a fight it waits for its end; the option off stops it", function()
  local ns, P = Start({ q = 24900 })
  Stub.EnterCombat()
  Stub.GainHonor(200)
  local f, pending = P.GetAlert()
  T.ok(pending, "waits for the end of the fight")
  T.ok(f == nil or not f:IsShown())
  T.eq(#Stub.pvp.sounds, 0)
  -- (the game's PLAYER_REGEN_ENABLED shows it: the stub's event frame is shared, Tracker
  -- always holds that event, so a count of registered frames proves nothing)
  Stub.Advance(30)
  f, pending = P.GetAlert()
  T.ok(pending and (f == nil or not f:IsShown()), "still waiting 30 s later: no polling")
  Stub.LeaveCombat()
  f, pending = P.GetAlert()
  T.ok(f:IsShown(), "shown once out of combat")
  T.no(pending)
  T.eq(#Stub.pvp.sounds, 1)
  -- the option off: a pending alert is dropped, none comes
  Stub.RunScript(f.tp.ok, "OnClick")
  Stub.SpendHonor(100)
  ns.Core.SetSetting("pvp.capAlert", false)
  Stub.GainHonor(200)
  T.no(f:IsShown())
  T.eq(#Stub.pvp.sounds, 1, "off: no alert")
  Stub.SpendHonor(100)
  ns.Core.SetSetting("pvp.capAlert", true)
  Stub.EnterCombat()
  Stub.GainHonor(200)
  T.ok(select(2, P.GetAlert()))
  ns.Core.SetSetting("pvp.capAlert", false)
  T.no(select(2, P.GetAlert()), "turned off while waiting")
  Stub.LeaveCombat()
  T.no(f:IsShown())
  T.eq(#Stub.pvp.sounds, 1)
  T.eq(Stub.errors, {})
end)

T.test("pvp alert: no SOUNDKIT on the client: the raid warning's id", function()
  local _, P = Start({ q = 24990 })
  rawset(_G, "SOUNDKIT", nil)
  Stub.GainHonor(10)
  T.eq(Stub.pvp.sounds, { { 8959, "Master" } })
  T.ok(P.GetAlert():IsShown())
  -- no PlaySound at all: the frame alone
  Stub.SpendHonor(10)
  rawset(_G, "PlaySound", nil)
  Stub.GainHonor(10)
  T.ok(P.GetAlert():IsShown())
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- The main bar's mode (the override)
---------------------------------------------------------------------------

T.test("pvp main mode: widget.main, the battleground override (instance type pvp only), XP without data", function()
  local _, P = Start()
  local w = { main = "xp", pvpAuto = true }
  T.eq(P.MainMode(w), "xp", "outside")
  Stub.EnterBG()
  T.eq(P.MainMode(w), "pvp", "in a battleground")
  T.eq(w.main, "xp", "nothing written")
  T.eq(P.MainMode({ main = "rep", pvpAuto = true }), "pvp")
  T.eq(P.MainMode({ main = "xp", pvpAuto = false }), "xp", "the option off")
  Stub.LeaveBG()
  Stub.EnterBG({ arena = true })
  T.eq(P.MainMode(w), "xp", "an arena is not a battleground")
  Stub.LeaveBG()
  T.eq(P.MainMode({ main = "pvp" }), "pvp")
  T.eq(P.MainMode({ main = "rep" }), "rep")
  T.eq(P.MainMode(nil), "xp")
  T.eq(P.StripKind({ pvp = "honor" }), "honor")
  T.eq(P.StripKind({ pvp = "rank" }), "rank")
  T.eq(P.StripKind({ pvp = "off" }), nil)
end)

---------------------------------------------------------------------------
-- char.pvp
---------------------------------------------------------------------------

T.test("pvp record: kept across a reload (new bases), repaired, reset with every rate, wiped by ResetChar", function()
  local ns = Start()
  Stub.EnterBG()
  for _ = 1, 10 do
    Stub.Advance(60)
    Stub.GainHonor(100)
    Stub.GainRankPoints(50)
  end
  local p = ns.char.pvp
  local a, ka, g = p.he[1].a, p.ke[1].a, p.g
  -- honor changed while away (another addon's account, a spending): a new base, no gain
  Stub.pvp.q = Stub.pvp.q + 5000
  local ns2 = Stub.Restart({ reload = true, settle = 3 })
  p = ns2.char.pvp
  T.near(p.he[1].a, a, 1, "the honor EMA kept")
  T.near(p.ke[1].a, ka, 1, "the rank EMA kept")
  T.eq(p.g, g, "the time of the last gain kept")
  T.eq(p.h, Stub.pvp.q, "a new base")
  Stub.GainHonor(10)
  T.near(p.he[1].a, a + 10, 2)
  -- /tpl reset rate (Core.ResetRate): the PvP rates too
  local Core = ns2.Core
  Stub.RunSlash("reset rate")
  T.eq({ p.he[1].a, p.he[1].d, p.ke[1].a, p.ke[1].d }, { 0, 0, 0, 0 })
  -- the options' button: Pvp.ResetRate
  Stub.GainHonor(10)
  T.ok(ns2.Pvp.ResetRate())
  T.eq(ns2.char.pvp.he[1].a, 0)
  -- repair
  local rec = { pvp = { h = "x", k = -5, g = 12, c = -1, hk = 4, a = 1, he = { { a = 1, d = 2 } },
                        ke = {}, s = { t = 5, h = -2, r = 3, k = "y" }, b = { at = 5, h = 0, r = 7 } } }
  for i = 1, 8 do rec.pvp.ke[i] = { a = 1, d = 2 } end
  rec.pvp.ke.junk = 1
  Core.RepairChar(rec)
  T.eq(rec.pvp, { g = 12, hk = 4, ke = { { a = 1, d = 2 }, { a = 1, d = 2 }, { a = 1, d = 2 }, { a = 1, d = 2 },
                                         { a = 1, d = 2 }, { a = 1, d = 2 }, { a = 1, d = 2 }, { a = 1, d = 2 } },
                  s = { t = 5, r = 3 }, wp = {} }, "every bad field dropped; the world PvP pending map recreated")
  rec = { pvp = { s = { h = 1 }, b = { at = 5, h = 2, r = 1, d = 300, i = 30 } } }
  Core.RepairChar(rec)
  T.eq(rec.pvp, { b = { at = 5, h = 2, r = 1, d = 300, i = 30 }, wp = {} }, "a session without its t dropped")
  rec = { pvp = { s = { t = 5, d = 3, k = 80 }, b = { at = 5, h = 2, d = "x", i = -1 } } }
  Core.RepairChar(rec)
  T.eq(rec.pvp, { s = { t = 5, d = 3, k = 80 }, b = { at = 5, h = 2 }, wp = {} },
    "today's kills kept; a bad length or id dropped")
  rec = { pvp = "x" }
  Core.RepairChar(rec)
  T.eq(rec.pvp, nil)
  -- ResetChar: wiped, new bases at once
  T.ok(Core.ResetChar())
  p = ns2.char.pvp
  T.ok(type(p) == "table", "a new record")
  T.eq({ p.he[1].a, p.ke[1].a, p.g, p.h }, { 0, 0, nil, Stub.pvp.q })
  T.eq({ ns2.Pvp.Session() }, { 0, 0, 0, 0, 0 })
  T.eq(Stub.errors, {})
end)

T.test("pvp record: read-only mode writes nothing and refuses a reset; the values still show", function()
  local ns, P = Start({ db = { schema = 99, settings = { firstRunDone = true }, chars = {} } })
  T.ok(ns.readOnly)
  T.eq(ns.char.pvp, nil)
  Stub.EnterBG()
  Stub.GainHonor(100)
  Stub.Advance(60)
  Stub.MatchComplete(0, 60)
  Stub.LeaveBG()
  T.eq(ns.char.pvp, nil, "no record written")
  T.ok(P.Has())
  T.eq(select(2, P.Honor()), 1124)
  T.eq({ P.Rate("honor", 0) }, { nil, "nodata", 0 })
  T.no(P.ResetRate())
  -- the whole tick in read-only mode (the PvP main bar and strip shown, the resets' check,
  -- the token context): nothing allocated in steady state
  ns.Core.SetSetting("widget.main", "pvp")
  ns.Core.SetSetting("widget.slots.1", "rank_eta")
  Stub.Advance(5)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 2, format("read-only PvP tick: %.2f KB over 600 ticks", kb))
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Clients, guards
---------------------------------------------------------------------------

T.test("pvp on Classic Era (no currency, no major faction): dormant, no event, nothing written", function()
  for _, api in ipairs({ "era", "none" }) do
    Stub.Reset()
    local before = Stub.CountRegistered("CURRENCY_DISPLAY_UPDATE")
    local ns, P = Start({ api = api })
    T.no(P.Available(), api)
    T.no(P.Has())
    T.eq(Stub.CountRegistered("CURRENCY_DISPLAY_UPDATE"), before, api .. ": no event")
    T.eq(Stub.CountRegistered("PVP_MATCH_COMPLETE"), 0)
    T.eq(ns.char.pvp, nil)
    T.eq(P.MainKind(), nil)
    T.eq(P.MainMode({ main = "pvp", pvpAuto = true }), "xp")
    T.eq(P.StripKind({ pvp = "honor" }), nil)
    T.eq({ P.Rate("honor", 0) }, { nil, "nodata", 0 })
    Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792, 5, 5)
    Stub.Advance(60)
    T.eq(ns.char.pvp, nil)
    T.eq(#Stub.pvp.sounds, 0)
    T.eq(Stub.errors, {}, api)
  end
end)

T.test("pvp guards: secret, missing or odd values read as unknown; erroring APIs are contained", function()
  local ns, P = Start()
  local s = Stub.pvp
  s.secret.quantity = true
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.no((P.Honor()), "a secret quantity: unknown")
  T.ok(P.Has(), "the rank still read")
  s.secret = { info = true }
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  Stub.Fire("UPDATE_FACTION")
  T.no(P.Has(), "both unreadable")
  s.secret = { maxQuantity = true, weekNumber = true }
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  Stub.Fire("UPDATE_FACTION")
  T.eq({ P.Honor() }, { true, 1024, 0 }, "no cap known")
  T.eq(select(6, P.Rank()), true, "no week: no season")
  s.secret = { renownLevelThreshold = true }
  Stub.Fire("UPDATE_FACTION")
  T.no((P.Rank()), "a secret threshold: no rank")
  s.secret = {}
  -- odd fields
  local cur, maj = rawget(_G, "C_CurrencyInfo"), rawget(_G, "C_MajorFactions")
  cur.GetCurrencyInfo = function() return { quantity = "12", maxQuantity = -4 } end
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.no((P.Honor()))
  cur.GetCurrencyInfo = function() return { quantity = 0 / 0 } end
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.no((P.Honor()), "NaN")
  cur.GetCurrencyInfo = function() error("boom") end
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.no((P.Honor()))
  cur.GetCurrencyInfo = function() return 5 end
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792)
  T.no((P.Honor()))
  maj.GetMajorFactionProgressionInfo = function() error("boom") end
  Stub.Fire("UPDATE_FACTION")
  T.no((P.Rank()))
  maj.GetMajorFactionProgressionInfo = function()
    return { renownLevel = 2, renownReputationEarned = 10, renownLevelThreshold = 1050 }
  end
  maj.GetTotalReputationForRenownLevel = function() error("boom") end
  Stub.Fire("UPDATE_FACTION")
  local r = Pack(P.Rank())
  T.eq({ r[1], r[2], r[5], r[8], r[9] }, { true, 2, 0, nil, nil }, "the totals unknown")
  T.eq(select(6, P.Rank()), false, "rank 2 with points: a season, even without a week number")
  rawset(_G, "C_DateAndTime", { GetSecondsUntilWeeklyReset = function() error("boom") end })
  rawset(_G, "C_SeasonInfo", { GetTimeUntilCurrentPVPSeasonEnd = function() return Stub.SECRET end })
  T.eq({ P.WeeklyReset(), P.SeasonEnd() }, { nil, nil })
  rawset(_G, "GetPVPSessionStats", function() error("boom") end)
  rawset(_G, "GetPVPLifetimeStats", function() return "x", -1 end)
  P.ReadAgain()
  local today, _, _, life = P.Kills()
  T.eq(today, nil)
  T.eq(life, 87, "the last lifetime count kept")
  rawset(_G, "IsInInstance", function() return Stub.SECRET, Stub.SECRET end)
  Stub.Fire("ZONE_CHANGED_NEW_AREA")
  T.eq({ P.InBG() }, { false, false }, "a secret place: the last one")
  rawset(_G, "GetBattlefieldWinner", function() error("boom") end)
  T.eq(ns.Tooltip.PvpRankTitle(99), nil)
  T.eq(Stub.errors, {})
end)

T.test("pvp: Advance, the getters, the token context and the main bar's texts allocate nothing", function()
  local ns, P = Start({ total = 1000 })
  Stub.EnterBG()
  for _ = 1, 12 do
    Stub.Advance(60)
    Stub.GainHonor(100)
    Stub.GainRankPoints(40)
  end
  local ctx = ns.Tokens.ctx
  local kb = T.alloc(function() P.Advance(1, "p") end, 3000)
  T.ok(kb < 0.1, format("Advance: %.3f KB", kb))
  local function Calls()
    P.Rate("honor", 0)
    P.Rate("rank", 1)
    P.HonorEta(0)
    P.RankEta(0)
    P.Honor()
    P.Rank()
    P.Week()
    P.Kills()
    P.Session()
    P.Value("honor")
    P.Value("rank")
    P.MainKind()
    P.MainMode(ns.settings.widget)
    P.StripKind(ns.settings.widget)
    P.Color(2)
    P.ColorArray(3)
    P.RankName(1)
    P.FillContext(ctx, 0)
    P.MainRight(0)
  end
  Calls()                                          -- the cached strings made once
  kb = T.alloc(Calls, 3000)
  T.ok(kb < 0.1, format("getters: %.3f KB", kb))
  T.eq(Stub.onUpdateCount, 0)
end)
