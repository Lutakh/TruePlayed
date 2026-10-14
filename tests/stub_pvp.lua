-- tests/stub_pvp.lua - stub extension for PvP on WoW Forever (Pvp.lua: the honor, the PvP
-- rank, the honorable kills, the battlegrounds). Returns an installer run at the end of
-- every Stub.Reset(); by default NO PvP API is installed (Classic Era's case), so every
-- other test, golden and snapshot draws exactly what it drew before PvP existed. A restart
-- that keeps the world (Stub.Restart: a reload, a logout) keeps the PvP state and API.
--
-- Stub.SetPvpAPI(mode):
--   "forever"  C_CurrencyInfo.GetCurrencyInfo (a new table per call: quantity, maxQuantity,
--              totalEarned 0 as on the beta), C_MajorFactions.GetMajorFactionProgressionInfo
--              (2800 only; a new table per call) and GetTotalReputationForRenownLevel,
--              GetCurrentArenaSeason, C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd,
--              C_DateAndTime.GetSecondsUntilWeeklyReset / GetSecondsUntilDailyReset,
--              GetPVPSessionStats, GetPVPYesterdayStats, GetPVPLifetimeStats (kills,
--              highest rank), GetBattlefieldWinner, GetBattlefieldArenaFaction, PlaySound,
--              SOUNDKIT, and C_PvP.GetScoreInfo / GetScoreInfoByPlayerGuid that raise an
--              error (secret during a match: never to be called)
--   "era"      Classic Era: GetPVPLifetimeStats (kills, dishonorable, rank) and PlaySound
--              only (no currency, no major faction)
--   "none"     none of them (the default)
-- Stub.pvp (reset by every Reset that does not keep the world):
--   q, max          the honor and its cap (1024 / 25000: the beta's values)
--   discovered      the currency's discovered flag (true)
--   total           the rank's season total (level, points and threshold follow from it
--                   and Stub.PVP_TOTALS: 750 to rank 1, +150 a rank, 2350 to rank 11, ...
--                   24750 to rank 14)
--   week, cap, prev weekNumber, currentWeekProgressiveMaxLevel, previous...
--                   (default: -1, 0, 0: no season, as on the beta)
--   maxLevel        14
--   season          GetCurrentArenaSeason (36, the beta's)
--   seasonEnd, reset, daily  seconds (GetTimeUntilCurrentPVPSeasonEnd: 0, the beta's; the
--                   weekly reset: 3 days; the daily reset: 12 hours; fixed: a reset passing
--                   is Stub.WeeklyReset / Stub.DailyReset)
--   hkToday, hkYest, hkLife, hkHigh   the honorable kills (and the highest PvPRanks value)
--   winner          GetBattlefieldWinner (nil)
--   team            GetBattlefieldArenaFaction (nil: the function returns nil, the addon
--                   falls back to UnitFactionGroup)
--   empty           { honor = n, rank = n }: the next n reads are empty, as before the data
--                   is loaded at a login (the currency: quantity 0, maxQuantity 0,
--                   discovered false; the rank: level 0, points 0, threshold 0, maxLevel 0)
--   stale           one rank read with a stale field ({ level = n } or { points = n }),
--                   then consistent again (Stub.GainRankPoints' opts.stale)
--   secret          { [field] = true }: that field reads as Stub.SECRET (quantity,
--                   maxQuantity, renownLevel, renownReputationEarned, renownLevelThreshold,
--                   weekNumber, currentWeekProgressiveMaxLevel, info (the whole table),
--                   hk (the kill counts))
--   sounds          the PlaySound calls ({ kit, channel })
--   calls           GetCurrencyInfo / GetProgression / Score counts
-- Rank titles: PVP_RANK_5_0 .. PVP_RANK_18_1 (Horde 0, Alliance 1; "<Horde|Alliance> N"),
-- PVP_RANK_7_0_FEMALE ("Horde 3 (f)") for the female form; Stub.SetPvpTitles(false)
-- removes them.
-- Helpers (events as the game sends them):
--   Stub.GainHonor(n, opts)   quantity + n (held at the cap); CURRENCY_DISPLAY_UPDATE
--                             (1792, quantity, quantityChange = opts.change or the rise,
--                             gain source); opts.quiet: no event
--   Stub.SpendHonor(n)        quantity - n; CURRENCY_DISPLAY_UPDATE with -n
--   Stub.GainRankPoints(n, opts)  the season total + n (held at the week's cap and the max
--                             rank); MAJOR_FACTION_RENOWN_LEVEL_CHANGED (2800, new, old)
--                             on a new rank, then UPDATE_FACTION; opts.stale = "level"
--                             (that event's read sees the old rank with the new points) or
--                             "points" (the new rank with the old points), the
--                             UPDATE_FACTION read consistent
--   Stub.SetWeek(week, cap, prev, opts)  a new week (opts.quiet: no event; else
--                             UPDATE_FACTION)
--   Stub.SetSeason(on)        on: week 1 with a cap of rank 3; off: the beta's -1, 0
--   Stub.WeeklyReset(cap, opts)  the weekly reset passes: week + 1, the cap (default: one
--                             rank more), the countdown back to 7 days; no event unless
--                             opts.event (UPDATE_FACTION)
--   Stub.DailyReset()         the daily reset passes: today's kills become yesterday's, 0
--                             today, the countdown back to 24 hours; no event
--   Stub.EnterBG(opts) / Stub.LeaveBG(opts)   an instance of type "pvp" (opts.arena:
--                             "arena"; opts.id: its instance id, 30) entered / left
--                             (ZONE_CHANGED_NEW_AREA; with opts.loading,
--                             PLAYER_ENTERING_WORLD as after a loading screen)
--   Stub.ChainBG(id)          from a battleground straight into the next one (a queue that
--                             pops inside): instance id `id` (default: the same map, 30),
--                             PLAYER_ENTERING_WORLD after the loading screen
--   Stub.MatchComplete(winner, duration)   PVP_MATCH_COMPLETE (winner: 0 Horde, 1 Alliance,
--                             255 draw) then UPDATE_BATTLEFIELD_STATUS (GetBattlefieldWinner
--                             gives winner)
--   Stub.HK(n)                n honorable kills (today, lifetime); PLAYER_PVP_KILLS_CHANGED

local THRESHOLDS = { 750, 900, 1050, 1200, 1350, 1500, 1650, 1800, 1950, 2100, 2350, 2500, 2650, 3000 }

-- TOTALS[r]: the season total that reaches rank r (TOTALS[0] = 0, TOTALS[14] = 24750).
local TOTALS = { [0] = 0 }
for r = 1, #THRESHOLDS do TOTALS[r] = TOTALS[r - 1] + THRESHOLDS[r] end

local HONOR_ID, RANK_ID = 1792, 2800

local function NewState(player)
  return {
    player = player, mode = "none",
    q = 1024, max = 25000, discovered = true, total = 0, week = -1, cap = 0, prev = 0, maxLevel = 14,
    season = 36, seasonEnd = 0, reset = 3 * 86400, daily = 12 * 3600,
    hkToday = 0, hkYest = 0, hkLife = 87, hkHigh = 0, winner = nil, team = nil,
    secret = {}, sounds = {}, empty = {}, stale = nil,
    calls = { GetCurrencyInfo = 0, GetProgression = 0, Score = 0 },
  }
end

return function(Stub)
  local keep = type(Stub.pvp) == "table" and Stub.pvp.player == Stub.player
  if not keep then Stub.pvp = NewState(Stub.player) end
  Stub.PVP_THRESHOLDS, Stub.PVP_TOTALS = THRESHOLDS, TOTALS

  local function F(name, v)
    if Stub.pvp.secret[name] then return Stub.SECRET end
    return v
  end

  -- Rank, points inside it, its threshold, from the season total.
  local function Place(total)
    local s = Stub.pvp
    local top = s.maxLevel
    local level = 0
    for r = 1, top do
      if total >= TOTALS[r] then level = r end
    end
    if level >= top then return top, 0, THRESHOLDS[top] end
    return level, total - TOTALS[level], THRESHOLDS[level + 1]
  end
  Stub.PvpPlace = Place

  local function GetCurrencyInfo(id)
    local s = Stub.pvp
    s.calls.GetCurrencyInfo = s.calls.GetCurrencyInfo + 1
    if id ~= HONOR_ID then return nil end
    if s.secret.info then return Stub.SECRET end
    local e = s.empty.honor
    if type(e) == "number" and e > 0 then
      s.empty.honor = e - 1
      return { name = "", quantity = 0, maxQuantity = 0, totalEarned = 0, quantityEarnedThisWeek = 0,
               canEarnPerWeek = false, maxWeeklyQuantity = 0, iconFileID = 0, discovered = false, quality = 1 }
    end
    return { name = "Honor", quantity = F("quantity", s.q), maxQuantity = F("maxQuantity", s.max),
             totalEarned = 0, quantityEarnedThisWeek = 0, canEarnPerWeek = false, maxWeeklyQuantity = 0,
             iconFileID = 1455894, discovered = s.discovered, quality = 1 }
  end

  local function GetProgression(id)
    local s = Stub.pvp
    s.calls.GetProgression = s.calls.GetProgression + 1
    if id ~= RANK_ID then return nil end
    if s.secret.info then return Stub.SECRET end
    local e = s.empty.rank
    if type(e) == "number" and e > 0 then
      s.empty.rank = e - 1
      return { factionID = RANK_ID, renownLevel = 0, renownReputationEarned = 0, renownLevelThreshold = 0,
               maxLevel = 0, weekNumber = 0, currentWeekProgressiveMaxLevel = 0, previousWeekProgressiveMaxLevel = 0 }
    end
    local level, pts, thr = Place(s.total)
    local st = s.stale
    if st then
      s.stale = nil
      if st.level then level = st.level end
      if st.points then pts = st.points end
    end
    return { factionID = RANK_ID, renownLevel = F("renownLevel", level),
             renownReputationEarned = F("renownReputationEarned", pts),
             renownLevelThreshold = F("renownLevelThreshold", thr), maxLevel = s.maxLevel,
             weekNumber = F("weekNumber", s.week),
             currentWeekProgressiveMaxLevel = F("currentWeekProgressiveMaxLevel", s.cap),
             previousWeekProgressiveMaxLevel = s.prev }
  end

  local function TotalFor(id, level)
    if id ~= RANK_ID or type(level) ~= "number" then return nil end
    return TOTALS[level]
  end

  local function Count(v)
    if Stub.pvp.secret.hk then return Stub.SECRET end
    return v
  end

  local function Score()
    Stub.pvp.calls.Score = Stub.pvp.calls.Score + 1
    error("C_PvP score read during a match (secret)", 2)
  end

  local function PlaySound(kit, channel)
    local list = Stub.pvp.sounds
    list[#list + 1] = { kit, channel }
    return true, 1
  end

  local NAMES = { "C_CurrencyInfo", "C_MajorFactions", "C_SeasonInfo", "C_DateAndTime", "C_PvP",
                  "GetPVPSessionStats", "GetPVPYesterdayStats", "GetPVPLifetimeStats",
                  "GetBattlefieldWinner", "GetBattlefieldArenaFaction", "GetCurrentArenaSeason",
                  "PlaySound", "SOUNDKIT" }

  function Stub.SetPvpAPI(mode)
    Stub.pvp.mode = mode
    for _, n in ipairs(NAMES) do rawset(_G, n, nil) end
    if mode == "forever" then
      rawset(_G, "C_CurrencyInfo", { GetCurrencyInfo = GetCurrencyInfo })
      rawset(_G, "C_MajorFactions", { GetMajorFactionProgressionInfo = GetProgression,
                                      GetTotalReputationForRenownLevel = TotalFor })
      rawset(_G, "C_SeasonInfo", { GetTimeUntilCurrentPVPSeasonEnd = function() return Stub.pvp.seasonEnd end })
      rawset(_G, "C_DateAndTime", { GetSecondsUntilWeeklyReset = function() return Stub.pvp.reset end,
                                    GetSecondsUntilDailyReset = function() return Stub.pvp.daily end })
      rawset(_G, "GetCurrentArenaSeason", function() return Stub.pvp.season end)
      rawset(_G, "C_PvP", { GetScoreInfo = Score, GetScoreInfoByPlayerGuid = Score })
      rawset(_G, "GetPVPSessionStats", function() return Count(Stub.pvp.hkToday), 0 end)
      rawset(_G, "GetPVPYesterdayStats", function() return Count(Stub.pvp.hkYest), 0 end)
      rawset(_G, "GetPVPLifetimeStats", function() return Count(Stub.pvp.hkLife), Stub.pvp.hkHigh end)
      rawset(_G, "GetBattlefieldWinner", function() return Stub.pvp.winner end)
      rawset(_G, "GetBattlefieldArenaFaction", function() return Stub.pvp.team end)
      rawset(_G, "PlaySound", PlaySound)
      rawset(_G, "SOUNDKIT", { RAID_WARNING = 8959, IG_MAINMENU_OPEN = 850 })
    elseif mode == "era" then
      rawset(_G, "GetPVPLifetimeStats", function() return Count(Stub.pvp.hkLife), 0, Stub.pvp.hkHigh end)
      rawset(_G, "PlaySound", PlaySound)
    end
  end

  function Stub.SetPvpTitles(on)
    for f = 0, 1 do
      for e = 5, 18 do
        local name = (f == 0 and "Horde " or "Alliance ") .. (e - 4)
        rawset(_G, "PVP_RANK_" .. e .. "_" .. f, on and name or nil)
      end
    end
    rawset(_G, "PVP_RANK_7_0_FEMALE", on and "Horde 3 (f)" or nil)
  end

  function Stub.GainHonor(n, opts)
    local s = Stub.pvp
    local q = s.q + n
    if s.max > 0 and q > s.max then q = s.max end
    local rise = q - s.q
    s.q = q
    if opts and opts.quiet then return end
    local change = rise
    if opts and opts.change ~= nil then change = opts.change end
    Stub.Fire("CURRENCY_DISPLAY_UPDATE", HONOR_ID, q, change, 1, nil)
  end

  function Stub.SpendHonor(n)
    local s = Stub.pvp
    if n > s.q then n = s.q end
    s.q = s.q - n
    Stub.Fire("CURRENCY_DISPLAY_UPDATE", HONOR_ID, s.q, -n, nil, 1)
  end

  function Stub.GainRankPoints(n, opts)
    local s = Stub.pvp
    local old, oldPts = Place(s.total)
    local t = s.total + n
    local limit = TOTALS[s.maxLevel]
    if s.cap > 0 and TOTALS[s.cap] < limit then limit = TOTALS[s.cap] end
    if t > limit then t = limit end
    if t < 0 then t = 0 end
    s.total = t
    local new = Place(t)
    if new ~= old then
      local stale = opts and opts.stale
      if stale == "level" then s.stale = { level = old } elseif stale == "points" then s.stale = { points = oldPts } end
      Stub.Fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", RANK_ID, new, old)
      s.stale = nil
    end
    Stub.Fire("UPDATE_FACTION")
  end

  function Stub.SetWeek(week, cap, prev, opts)
    local s = Stub.pvp
    s.week, s.cap, s.prev = week, cap, prev or s.cap
    if not (opts and opts.quiet) then Stub.Fire("UPDATE_FACTION") end
  end

  function Stub.SetSeason(on)
    if on then Stub.SetWeek(1, 3, 0, { quiet = true }) else Stub.SetWeek(-1, 0, 0, { quiet = true }) end
  end

  function Stub.WeeklyReset(cap, opts)
    local s = Stub.pvp
    s.prev = s.cap
    s.week = s.week + 1
    s.cap = cap or (s.cap + 1)
    s.reset = 7 * 86400
    if opts and opts.event then Stub.Fire("UPDATE_FACTION") end
  end

  function Stub.DailyReset()
    local s = Stub.pvp
    s.hkYest, s.hkToday = s.hkToday, 0
    s.daily = 86400
  end

  function Stub.EnterBG(opts)
    Stub.SetInstance(true, (opts and opts.arena) and "arena" or "pvp", (opts and opts.id) or 30, nil)
    if opts and opts.loading then Stub.Fire("PLAYER_ENTERING_WORLD", false, false) end
  end

  function Stub.ChainBG(id)
    Stub.SetInstance(true, "pvp", id or 30, nil)
    Stub.Fire("PLAYER_ENTERING_WORLD", false, false)
  end

  function Stub.LeaveBG(opts)
    Stub.SetInstance(false, "none", 0, nil)
    if opts and opts.loading then Stub.Fire("PLAYER_ENTERING_WORLD", false, false) end
  end

  function Stub.MatchComplete(winner, duration)
    Stub.pvp.winner = winner
    Stub.Fire("PVP_MATCH_COMPLETE", winner, duration)
    Stub.Fire("UPDATE_BATTLEFIELD_STATUS", 1)
  end

  function Stub.HK(n)
    local s = Stub.pvp
    s.hkToday = s.hkToday + n
    s.hkLife = s.hkLife + n
    Stub.Fire("PLAYER_PVP_KILLS_CHANGED", "player")
  end

  Stub.SetPvpAPI(Stub.pvp.mode)
  Stub.SetPvpTitles(true)
end
