-- Stats.lua - pure read-only statistics over the saved data (SPEC-FINAL 3.8, 5.10-5.11, 5.17, 5.22, 5.23).
--
-- Rules:
--  * Stats NEVER reads ns.char, ns.session or the Tracker: every function takes the
--    character (or bucket, or db) explicitly; only the current character gets a sync.
--  * Stats never writes into the data it reads.
--  * Functions not marked "(alloc)" do not allocate (they run on the tick path through
--    Tokens.UpdateContext). "(alloc)" functions reuse the `out` tables they are given
--    and are meant for UI refreshes only.
local ADDON, ns = ...
local L, C = ns.L, ns.C

local type, pairs, next, tonumber, pcall, select = type, pairs, next, tonumber, pcall, select
local floor = math.floor
local table_sort, table_concat = table.sort, table.concat
local string_sub, string_byte = string.sub, string.byte
local GetTime = GetTime
local C_Map = C_Map
local GetRealZoneText, GetInstanceInfo = GetRealZoneText, GetInstanceInfo
local wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end

local Stats = {}
ns.Stats = Stats

-- Constants captured once (ns.C is complete when Core.lua has loaded).
local STATE_KEYS = C.STATE_KEYS
local N_STATE_KEYS = #STATE_KEYS
local INCLUDED = C.INCLUDED
local AFK_KEYS = C.AFK_KEYS
local INSTANCE_KEYS = C.INSTANCE_KEYS
local N_INSTANCE_KEYS = #INSTANCE_KEYS
local CAPITALS = C.CAPITALS
local WARMUP_MIN, WARMUP_FULL = C.WARMUP_MIN, C.WARMUP_FULL
local FALLBACK_MIN, RATE_SAMPLE_MIN = C.FALLBACK_MIN, C.RATE_SAMPLE_MIN
local REST_BONUS, REST_DRAIN = C.REST_BONUS, C.REST_DRAIN
local KILL_RING, KILL_XP_MAX = C.KILL_RING, C.KILL_XP_MAX
local RECENT_LEVELS = C.RECENT_LEVELS
local DRIFT_TOL = C.DRIFT_TOL
local PRIOR_WEIGHT = C.PRIOR_WEIGHT
local XP_STALL = C.XP_STALL
local MAX_ZONE_DEPTH = C.MAX_ZONE_DEPTH
local MT_CONTINENT = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or C.MAPTYPE_CONTINENT
local MT_DUNGEON = (Enum and Enum.UIMapType and Enum.UIMapType.Dungeon) or C.MAPTYPE_DUNGEON
local BYTE_I = 105       -- string.byte("i"): instance zone keys "i<instanceID>"
local BYTE_N = 110       -- string.byte("n"): zone-text keys "n<text>"

local EMPTY_EMA = { a = 0, r = 0, q = 0, d = 0 }   -- read-only stand-in for a missing entry

-- Private caches (never saved).
local nameOf = {}        -- zoneKey -> localized name, or false when the map has no name
local contOf = {}        -- numeric zoneKey -> continent uiMapID, or false (none found)
local dungeonOf = {}     -- numeric zoneKey -> true when its map is Dungeon-typed, else false
local maskLabels = {}    -- mask -> "AFK · city" (built once per mask)
local levelList = {}     -- scratch list of level numbers (alloc functions only)
local accN, accT, accX, accD = {}, {}, {}, {}  -- scratch accumulators (AccountLevelAverages)
local contSecs = {}      -- scratch: continent row key -> seconds (Continents)
local spareRows = {}     -- row tables trimmed from a Continents `out`, reused
local SPARE_MAX = 8

---------------------------------------------------------------------------
-- Bucket sums
---------------------------------------------------------------------------

-- Tracked seconds = everything except the untracked "u" key.
local function UntrackedOf(bucket)
  local s = bucket and bucket.s
  return (s and s.u) or 0
end

-- Seconds of a seconds map (`s`, or `xs`) over the state keys that the mask includes.
local function SumMap(s, mask)
  if not s then return 0 end
  local inc = INCLUDED[mask or 0] or INCLUDED[0]
  local total = 0
  for i = 1, N_STATE_KEYS do
    local k = STATE_KEYS[i]
    if inc[k] then
      local v = s[k]
      if v then total = total + v end
    end
  end
  return total
end

-- Seconds over the state keys (C.STATE_KEYS) that the mask includes (nil bucket -> 0).
local function Sum(bucket, mask)
  return SumMap(bucket and bucket.s, mask)
end
Stats.Sum = Sum

-- Stalled seconds of a bucket under the mask: time spent long without any XP (R1),
-- kept by the Tracker in bucket.xs (shaped like bucket.s). Rates leave it out.
local function StallOf(bucket, mask)
  local xs = bucket and bucket.xs
  if type(xs) ~= "table" then return 0 end
  return SumMap(xs, mask)
end
Stats.StallTime = StallOf

-- Open-world PvP seconds of a bucket (bucket.pw: life or levels[L], committed by Pvp.lua
-- through Tracker.AddLevelStat), a part of its active open-world seconds s.w: capped at
-- them (the Tracker's and Pvp's carries may leave it a second above) and at 0. 0 when
-- absent: a level without world PvP and a level never measured read alike (see
-- Stats.WorldPvpState). Never excluded by a mask (w never is).
local function PvpWorldOf(bucket)
  local pw = bucket and bucket.pw
  if type(pw) ~= "number" or not (pw > 0) then return 0 end   -- luacheck: ignore 581 (NaN fails too)
  local s = bucket.s
  local w = type(s) == "table" and s.w or 0
  if type(w) ~= "number" or not (w > 0) then return 0 end   -- luacheck: ignore 581 (NaN fails too)
  if pw > w then pw = w end
  return pw
end

-- Seconds of a bucket rebuilt after a crash (EstimateGap), under the mask: its per-key
-- map es exactly, plus the part saved without keys (est - sum(es): before es existed, or
-- by an older version) valued with the bucket's own place proportions (s without u, x
-- and f, which a rebuilt gap never gets). Never more than the bucket's tracked seconds
-- under the mask, never negative. Returns filtered, gross (max(est, sum(es)), no mask).
local function EstOf(bucket, mask)
  if type(bucket) ~= "table" then return 0, 0 end
  local est = tonumber(bucket.est) or 0
  local es, s = bucket.es, bucket.s
  local v, all = 0, 0
  if type(es) == "table" then v, all = SumMap(es, mask), SumMap(es, 0) end
  local gross = est > all and est or all
  local masked = SumMap(s, mask)
  local legacy = est - all
  if legacy > 0 and s then
    local act = (s.u or 0) + (s.x or 0) + (s.f or 0)
    local places = SumMap(s, 0) - act
    if places > 0 then v = v + legacy * (masked - act) / places end
  end
  local cap = masked - UntrackedOf(bucket)
  if v > cap then v = cap end
  if v < 0 then v = 0 end
  return v, gross
end
Stats.EstTime = EstOf

-- Tracked seconds of a level (or any bucket) that describe its XP rate: included by
-- the mask, without the untracked "u" and without stalled time.
local function RateTime(bucket, mask)
  return Sum(bucket, mask) - UntrackedOf(bucket) - StallOf(bucket, mask)
end

-- Seconds over every state key (C.STATE_KEYS).
local function SumAll(bucket)
  local s = bucket and bucket.s
  if not s then return 0 end
  local total = 0
  for i = 1, N_STATE_KEYS do
    local v = s[STATE_KEYS[i]]
    if v then total = total + v end
  end
  return total
end
Stats.SumAll = SumAll

-- Seconds over an explicit key list (e.g. C.AFK_KEYS).
local function SumKeys(bucket, keyList)
  local s = bucket and bucket.s
  if not s or not keyList then return 0 end
  local total = 0
  for i = 1, #keyList do
    local v = s[keyList[i]]
    if v then total = total + v end
  end
  return total
end
Stats.SumKeys = SumKeys

function Stats.Tracked(bucket)
  return SumAll(bucket) - UntrackedOf(bucket)
end

-- Fills `out` with the state partition of a bucket (see 4.1 "Derived quantities").
-- Percentages must be computed over out.tracked (critique #10a): active + afk + inn +
-- city + dead + prof == tracked. Active time splits into world (open world) + dungeon +
-- raid + pvp + taxi; the *All fields add the AFK time of the same place. dead (x) and
-- prof (f) are the activity states (Activity.lua): one key each, never AFK.
function Stats.Breakdown(bucket, out)
  out = out or {}
  local s = bucket and bucket.s
  local w, W, d, D, r, R, p, P = 0, 0, 0, 0, 0, 0, 0, 0
  local i, I, c, Cc, t, T, u = 0, 0, 0, 0, 0, 0, 0
  local x, f = 0, 0
  if s then
    w, W = s.w or 0, s.W or 0
    d, D = s.d or 0, s.D or 0
    r, R = s.r or 0, s.R or 0
    p, P = s.p or 0, s.P or 0
    i, I = s.i or 0, s.I or 0
    c, Cc = s.c or 0, s.C or 0
    t, T = s.t or 0, s.T or 0
    x, f = s.x or 0, s.f or 0
    u = s.u or 0
  end
  local inst = d + D + r + R + p + P
  local total = w + W + inst + i + I + c + Cc + t + T + x + f + u
  out.dead = x
  out.prof = f
  out.active = w + d + r + p + t
  out.afk = W + D + R + P + I + Cc + T
  out.inn = i
  out.city = c
  out.taxi = t + T
  out.untracked = u
  out.total = total
  out.tracked = total - u
  out.innAll = i + I
  out.innAfk = I
  out.cityAll = c + Cc
  out.cityAfk = Cc
  out.world = w
  out.dungeon = d
  out.raid = r
  out.pvp = p
  out.dungeonAll = d + D
  out.dungeonAfk = D
  out.raidAll = r + R
  out.raidAfk = R
  out.pvpAll = p + P
  out.pvpAfk = P
  out.instAll = inst
  out.est = (bucket and bucket.est) or 0
  return out
end

-- Instance seconds of a bucket (d, D, r, R, p, P) that the mask includes.
local function InstanceTime(bucket, mask)
  local s = bucket and bucket.s
  if not s then return 0 end
  local inc = INCLUDED[mask or 0] or INCLUDED[0]
  local total = 0
  for j = 1, N_INSTANCE_KEYS do
    local k = INSTANCE_KEYS[j]
    if inc[k] then
      local v = s[k]
      if v then total = total + v end
    end
  end
  return total
end
Stats.InstanceTime = InstanceTime

---------------------------------------------------------------------------
-- Displayed totals (5.23)
---------------------------------------------------------------------------

-- Played total. The server is the authority: with a live (or restored) sync the base is
-- the extrapolated server /played, else the locally known total.
-- Returns filtered, base, excluded, live.
function Stats.Played(char, mask, sync, now)
  local life = char and char.life
  local all = SumAll(life)
  local live = sync ~= nil and sync.valid == true and sync.total ~= nil
  local base
  if live then
    now = now or GetTime()
    base = sync.total + (now - (sync.g or now))
  else
    base = all
  end
  local excluded = all - Sum(life, mask)
  local filtered = base - excluded
  if filtered < 0 then filtered = 0 end
  return filtered, base, excluded, live
end

-- The sync carries a valid level part (the server's level /played) for `level`.
local function LevelLive(sync, level)
  return sync ~= nil and sync.valid == true and sync.levelValid == true
    and sync.level == level and sync.levelPlayed ~= nil
end

-- Time spent at `level`. Live only when the sync carries a valid level part for it.
-- Returns filtered, base, live.
function Stats.LevelTime(char, level, mask, sync, now)
  local levels = char and char.levels
  local lb = levels and level and levels[level]
  local all = SumAll(lb)
  local live = LevelLive(sync, level)
  local base
  if live then
    now = now or GetTime()
    base = sync.levelPlayed + (now - (sync.g or now))
  else
    base = all
  end
  local filtered = base - (all - Sum(lb, mask))
  if filtered < 0 then filtered = 0 end
  return filtered, base, live
end

-- Server /played of `level`, the level in progress (everything included, no exclusion):
-- the sync's level part projected to `now` while it is for this level, else the server
-- total projected to `now` less the level's server start (lb.srvStart) once a sync is
-- valid; nil when neither is known or below 0. Second value: true when a server mark of
-- the level was estimated (lb.srvStartEst / srvEndEst: shown with "~"). The rule of the
-- level in progress's row (the detail sheet's "Server /played" card) and of the tooltip's
-- "This level (server /played)" line. No allocation.
function Stats.LevelServer(char, level, sync, now)
  local levels = char and char.levels
  local lb = levels and level and levels[level]
  if type(lb) ~= "table" then return nil, false end
  local server
  if LevelLive(sync, level) then
    now = now or GetTime()
    server = sync.levelPlayed + (now - (sync.g or now))
  elseif sync ~= nil and sync.valid == true and sync.total and lb.srvStart then
    now = now or GetTime()
    server = sync.total + (now - (sync.g or now)) - lb.srvStart
  end
  if server and server < 0 then server = nil end
  return server, (lb.srvStartEst or lb.srvEndEst) and true or false
end

function Stats.SessionTime(session, mask)
  return Sum(session, mask)
end

---------------------------------------------------------------------------
-- Averages per level (5.22)
---------------------------------------------------------------------------

-- Overall average: (played - current level) / (level - 1). Includes pre-install "u".
function Stats.AvgPerLevel(char, mask, sync, now)
  local level = char and char.level
  if not level or level <= 1 then return nil end
  local played = Stats.Played(char, mask, sync, now)
  local current = Stats.LevelTime(char, level, mask, sync, now)
  local v = played - current
  if v < 0 then v = 0 end
  return v / (level - 1)
end

-- Mean filtered time of the completed levels in the window [level - n, level - 1] that
-- are neither partial nor reconstructed; needs at least 2 of them.
-- Returns avg or nil, count.
function Stats.RecentAvg(char, mask, n)
  local levels = char and char.levels
  local level = char and char.level
  if not levels or not level then return nil, 0 end
  n = n or RECENT_LEVELS
  local lo = level - n
  if lo < 1 then lo = 1 end
  local sum, count = 0, 0
  for l = level - 1, lo, -1 do
    local lb = levels[l]
    if type(lb) == "table" and not lb.partial and not lb.rec and SumAll(lb) > 0 then
      sum = sum + Sum(lb, mask)
      count = count + 1
    end
  end
  if count >= 2 then return sum / count, count end
  return nil, count
end

---------------------------------------------------------------------------
-- Rates (5.10, 5.11)
---------------------------------------------------------------------------

-- Pre-install estimate of a record in XP per second (char.prior, written once by the
-- Tracker from the server /played and the XP table), or nil.
local function PriorRate(char)
  local p = char and char.prior
  if type(p) ~= "table" then return nil end
  local xph = p.xph
  if type(xph) ~= "number" or not (xph > 0) then return nil end   -- luacheck: ignore 581 (NaN fails too)
  return xph / 3600
end

-- Weight of the prior, in pseudo-seconds, next to a tracked sample of T seconds:
-- C.PRIOR_WEIGHT at T = 0, fading linearly to 0 at T = WARMUP_FULL. The tracked
-- share T / (T + w) grows monotonically, so the value slides from the prior to the
-- tracked rate and meets it exactly when the sample is complete: no jump.
local function PriorWeight(T)
  if T >= WARMUP_FULL then return 0 end
  if T < 0 then T = 0 end
  return PRIOR_WEIGHT * (1 - T / WARMUP_FULL)
end

-- Rate of a tracked sample (a, r, q XP over T seconds), blended with the prior p
-- (XP per second, or nil) while the sample is short. The prior is attributed to A
-- (mob XP); R and Q come from the tracked part only, so the ETA stays rest-aware.
local function Blend(a, r, q, T, p, src, status, left)
  local w = p and PriorWeight(T) or 0
  if w <= 0 then
    local A, R, Q = a / T, r / T, q / T
    return 3600 * (A + R + Q), A, R, Q, src, status, left
  end
  local D = T + w
  local A, R, Q = (a + p * w) / D, r / D, q / D
  local rest = WARMUP_FULL - T
  if rest < 0 then rest = 0 end
  return 3600 * (A + R + Q), A, R, Q, "prior", "estimate", rest
end

-- Fallback chain: persisted EMA -> current level -> recent levels -> provisional EMA
-- -> pre-install estimate. Returns xph or nil, A, R, Q (XP per included second),
-- src, status, warmupLeft.
-- src "prior" / status "estimate": the value comes (fully or partly) from char.prior.
-- The prior is UNFILTERED (a server /played has no AFK, inn or city split): it is
-- used as is for every mask, and only while the tracked data is short.
-- Level times leave out stalled time (levels[L].xs, R1): days without XP (a server
-- level cap) never dilute a level's rate.
local function RateChain(char, mask)
  local ema = char and char.ema
  local e = (ema and ema[mask + 1]) or EMPTY_EMA
  local ea, er, eq, ed = e.a or 0, e.r or 0, e.q or 0, e.d or 0
  local x = ea + er + eq

  -- 1. settled EMA
  if ed >= WARMUP_FULL and x > 0 then
    local A, R, Q = ea / ed, er / ed, eq / ed
    return 3600 * (A + R + Q), A, R, Q, "ema", "ok", 0
  end

  local p = PriorRate(char)
  local levels = char and char.levels
  local level = char and char.level
  if levels and level then
    -- 2. current level (tracked time only: XP is tracked-only)
    local lb = levels[level]
    if type(lb) == "table" then
      local t = RateTime(lb, mask)
      if t >= FALLBACK_MIN and (lb.xp or 0) > 0 then
        return Blend(lb.xa or 0, lb.xr or 0, lb.xq or 0, t, p, "level", "ok", 0)
      end
    end
    -- 3. recent levels (partial excluded, reconstructed "rec" levels included)
    local lo = level - RECENT_LEVELS
    if lo < 1 then lo = 1 end
    local sa, sr, sq, st = 0, 0, 0, 0
    for l = level - 1, lo, -1 do
      local b = levels[l]
      if type(b) == "table" and not b.partial then
        sa = sa + (b.xa or 0)
        sr = sr + (b.xr or 0)
        sq = sq + (b.xq or 0)
        st = st + RateTime(b, mask)
      end
    end
    if st >= FALLBACK_MIN and (sa + sr + sq) > 0 then
      return Blend(sa, sr, sq, st, p, "recent", "ok", 0)
    end
  end

  -- 4. provisional EMA (with a prior, from the first second: the prior damps it)
  if x > 0 and (ed >= WARMUP_MIN or (p and ed > 0)) then
    if p then return Blend(ea, er, eq, ed, p, "ema", "ok", 0) end
    return 3600 * x / ed, ea / ed, er / ed, eq / ed, "ema", "warming", WARMUP_FULL - ed
  end

  local left = WARMUP_FULL - ed
  if left < 0 then left = 0 end
  -- 5. pre-install estimate alone (no tracked data yet)
  if p then return 3600 * p, p, 0, 0, "prior", "estimate", left end

  -- 6. nothing for this character
  return nil, 0, 0, 0, nil, "nodata", left
end

-- A rate that exists while the character is stalled (C.XP_STALL counted non-AFK seconds
-- without XP, char.noXP, R1) is the frozen one: status "stalled", and the seconds
-- without XP as an 8th return.
local function StallStatus(noXP, xph, A, R, Q, src, status, left)
  if xph ~= nil then return xph, A, R, Q, src, "stalled", left, noXP end
  return xph, A, R, Q, src, status, left
end

function Stats.Rate(char, mask)
  mask = mask or 0
  local noXP = char and char.noXP
  if type(noXP) == "number" and noXP > XP_STALL then
    return StallStatus(noXP, RateChain(char, mask))
  end
  return RateChain(char, mask)
end

-- Secondary rate over the session (raw division, valid for any mask).
function Stats.SessionRate(session, mask)
  if not session then return nil end
  local t = Sum(session, mask)
  if t < RATE_SAMPLE_MIN then return nil end
  return 3600 * (session.xp or 0) / t
end

-- Secondary rate over one level (tracked time only, stalled time left out).
function Stats.LevelRate(char, level, mask)
  local levels = char and char.levels
  local lb = levels and level and levels[level]
  if type(lb) ~= "table" then return nil end
  local t = RateTime(lb, mask)
  if t < RATE_SAMPLE_MIN then return nil end
  return 3600 * (lb.xp or 0) / t
end

-- Seconds to earn R XP with a rested pool E, base mob XP rate A and quest rate Q
-- (per included second). The rested bonus is modelled from the pool, not from history.
function Stats.EtaRestAware(R, E, A, Q)
  if not R then return nil end
  A, Q, E = A or 0, Q or 0, E or 0
  local base = A + Q
  if R <= 0 then return 0 end
  if base <= 0 then return nil end
  if E <= 0 or A <= 0 then return R / base end
  local rested = A * (1 + REST_BONUS) + Q
  local t1 = E / (A * REST_DRAIN)            -- time until the pool is drained
  if t1 * rested >= R then return R / rested end
  return t1 + (R - t1 * rested) / base
end

-- Time to the next level in included counted time.
-- Returns seconds or nil, status ("ok" | "warming" | "estimate" | "stalled" | "nodata" |
-- "max"), src, warmupLeft, stallSecs ("estimate" and "stalled" passed through from
-- Stats.Rate; stallSecs only with "stalled").
function Stats.ETA(char, mask, xp, max, rested, isMax)
  if isMax or (IsXPUserDisabled and IsXPUserDisabled()) then return nil, "max" end
  local _, A, _, Q, src, status, left, stallSecs = Stats.Rate(char, mask)
  if status == "nodata" then return nil, "nodata", nil, left end
  if not xp or not max or max <= 0 then return nil, status, src, left, stallSecs end
  return Stats.EtaRestAware(max - xp, rested or 0, A, Q), status, src, left, stallSecs
end

-- Mobs worth the average base XP (without the rested bonus) of the last C.KILL_RING
-- kills (char.killRing, oldest first) still needed to reach the next level, with the
-- rested pool E: a rested kill gives base * (1 + C.REST_BONUS) and drains
-- base * C.REST_DRAIN from the pool (the engine's model, see Tracker 5.9), the kill that
-- empties it gets a partial bonus. The average is rounded to a whole XP (the count and
-- the XP shown agree); without a ring it is the last kill's XP (char.lastKill.xp).
-- Returns n, avgXP, lastXP (the last kill's XP: lastKill.xp, else the newest ring
-- entry); nil when no kill is known, at max level (isMax, optional 5th argument, or
-- XP gain disabled) or without a valid xp / max (then nil, avgXP, lastXP).
function Stats.KillsToLevel(char, xp, max, rested, isMax)
  if isMax or (IsXPUserDisabled and IsXPUserDisabled()) then return nil end
  local lk = char and char.lastKill
  local last = type(lk) == "table" and lk.xp
  if type(last) ~= "number" or not (last > 0) then last = nil end   -- luacheck: ignore 581 (NaN fails too)
  local base
  local ring = char and char.killRing
  if type(ring) == "table" then
    local top = #ring
    local first = top - KILL_RING + 1
    if first < 1 then first = 1 end
    local sum, k = 0, 0
    for i = top, first, -1 do                  -- newest first: the first valid one is the last kill
      local v = ring[i]
      if type(v) == "number" and v >= 1 and v <= KILL_XP_MAX then   -- NaN and inf fail
        sum, k = sum + v, k + 1
        if last == nil then last = v end
      end
    end
    if k > 0 then base = floor(sum / k + 0.5) end
  end
  if base == nil then base = last end
  if base == nil then return nil end
  if type(xp) ~= "number" or type(max) ~= "number" or max <= 0 then return nil, base, last end
  local R = max - xp
  if R <= 0 then return 0, base, last end
  local E = (type(rested) == "number" and rested > 0) and rested or 0
  local n = 0
  if E > 0 and REST_DRAIN > 0 then
    local full = base * (1 + REST_BONUS)      -- XP of a fully rested kill
    local k = floor(E / (base * REST_DRAIN))  -- fully rested kills the pool allows
    if k * full >= R then
      n = floor(R / full)
      if n * full < R then n = n + 1 end
      return n, base, last
    end
    n = k
    R = R - k * full
    E = E - k * base * REST_DRAIN
    if E > 0 then                             -- the kill that drains what is left
      n = n + 1
      R = R - (base + E * REST_BONUS / REST_DRAIN)
      if R <= 0 then return n, base, last end
    end
  end
  local m = floor(R / base)
  if m * base < R then m = m + 1 end
  return n + m, base, last
end

---------------------------------------------------------------------------
-- Zones
---------------------------------------------------------------------------

-- A zone is a city when it holds city seconds, or when its map is a city
-- (account override in db.cities, else the built-in capitals).
local function IsCityKey(zoneKey, zoneBucket)
  local s = zoneBucket and zoneBucket.s
  if s and ((s.c or 0) + (s.C or 0)) > 0 then return true end
  if type(zoneKey) ~= "number" then return false end
  local db = ns.db
  local cities = db and db.cities
  local override = cities and cities[zoneKey]
  if override ~= nil then return override == true end
  return CAPITALS[zoneKey] == true
end
Stats.IsCityKey = IsCityKey

-- Name of an instance key "i<instanceID>" in the client's language: GetRealZoneText takes
-- the instance map ID. Refused when it is the current zone's text while we are not in
-- that instance (a client ignoring the argument would name every instance after the
-- current zone). nil when unknown: the caller keeps the name recorded when it was played.
local function InstanceName(zoneKey)
  local id = tonumber(string_sub(zoneKey, 2))
  if not id or id <= 0 or not GetRealZoneText then return nil end
  local ok, text = pcall(GetRealZoneText, id)
  if not ok or type(text) ~= "string" or text == "" then return nil end
  local okHere, here = pcall(GetRealZoneText)
  if okHere and here == text then
    local curID = GetInstanceInfo and select(8, GetInstanceInfo())
    if curID ~= id then return nil end
  end
  return text
end

-- Display name of a zone key. C_Map is consulted only for numeric keys (critique #6),
-- once per key (cached; C_Map.GetMapInfo allocates). An instance key is named in the
-- client's language (InstanceName) before the name recorded in its bucket, which is in
-- the language the game had when the instance was played.
local function ZoneName(zoneKey, zoneBucket)
  if zoneKey == nil then return L.ZONE_UNKNOWN end
  if type(zoneKey) == "number" then
    local n = nameOf[zoneKey]
    if n == nil then
      local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zoneKey)
      n = info and info.name
      if type(n) ~= "string" or n == "" then n = false end
      nameOf[zoneKey] = n
    end
    if n then return n end
    return (zoneBucket and zoneBucket.name) or L.ZONE_UNKNOWN
  end
  if zoneKey == "o" then return L.ZONE_OTHER end
  -- once per key: the localized name of an instance, or the text of a "n<zone text>"
  -- key, which carries its own name (4.3)
  local isInst = type(zoneKey) == "string" and string_byte(zoneKey, 1) == BYTE_I
  local n = nameOf[zoneKey]
  if n == nil then
    n = false
    if isInst then
      n = InstanceName(zoneKey) or false
    elseif type(zoneKey) == "string" and string_byte(zoneKey, 1) == BYTE_N and #zoneKey > 1 then
      n = string_sub(zoneKey, 2)
    end
    nameOf[zoneKey] = n
  end
  if isInst and n then return n end
  local bn = zoneBucket and zoneBucket.name
  if bn then return bn end
  return n or L.ZONE_UNKNOWN
end
Stats.ZoneName = ZoneName

-- Deterministic ordering: higher score first, then higher tie value, then numeric keys
-- before string keys, then key order.
local function Before(sa, ta, ka, sb, tb, kb)
  if sa ~= sb then return sa > sb end
  if ta ~= tb then return ta > tb end
  local tya, tyb = type(ka), type(kb)
  if tya ~= tyb then return tya == "number" end
  return ka < kb
end

-- Insertion into a sorted top-n list held in out[1..count]. Row tables are recycled
-- (the evicted last row, or a stale row left beyond `count`). Returns the new count and
-- the row to fill, or nil when the candidate does not enter the list.
local function TopInsert(out, count, n, score, tie, key)
  if count >= n then
    local last = out[count]
    if not Before(score, tie, key, last.score, last.tie, last.key) then return count, nil end
  else
    count = count + 1
  end
  local row = out[count]
  if not row then row = {} end
  local p = count
  while p > 1 do
    local prev = out[p - 1]
    if Before(score, tie, key, prev.score, prev.tie, prev.key) then
      out[p] = prev
      p = p - 1
    else
      break
    end
  end
  out[p] = row
  row.score, row.tie, row.key = score, tie, key
  return count, row
end

-- Drops rows beyond `count` so that #out == count.
local function Trim(out, count)
  for i = #out, count + 1, -1 do out[i] = nil end
end

-- (alloc) Top n zones of a zone map by filtered time.
-- Rows: { key, name, filtered, raw, afk, isCity, xp }.
function Stats.TopZones(zoneMap, n, mask, out)
  out = out or {}
  n = n or 3
  local count = 0
  if type(zoneMap) == "table" and n > 0 then
    for k, z in pairs(zoneMap) do
      if type(z) == "table" then
        local raw = SumAll(z)
        if raw > 0 or (z.xp or 0) > 0 then
          local row
          count, row = TopInsert(out, count, n, Sum(z, mask), raw, k)
          if row then row.bucket = z end
        end
      end
    end
  end
  for i = 1, count do
    local row = out[i]
    local z = row.bucket
    row.bucket = nil
    row.filtered, row.raw = row.score, row.tie
    row.name = ZoneName(row.key, z)
    row.afk = SumKeys(z, AFK_KEYS)
    row.isCity = IsCityKey(row.key, z)
    row.xp = z.xp or 0
  end
  Trim(out, count)
  return out, count
end

-- (alloc) Top n capitals by city time: only c + C counts (a flight over a capital is
-- not city time) and zones are selected by c + C > 0, not by the current city list
-- (critique #7). Rows: { key, name, total, afk }.
function Stats.TopCities(zoneMap, n, out)
  out = out or {}
  n = n or 3
  local count = 0
  if type(zoneMap) == "table" and n > 0 then
    for k, z in pairs(zoneMap) do
      local s = type(z) == "table" and z.s
      if s then
        local afk = s.C or 0
        local total = (s.c or 0) + afk
        if total > 0 then
          local row
          count, row = TopInsert(out, count, n, total, afk, k)
          if row then row.bucket = z end
        end
      end
    end
  end
  for i = 1, count do
    local row = out[i]
    local z = row.bucket
    row.bucket = nil
    row.total, row.afk = row.score, row.tie
    row.name = ZoneName(row.key, z)
  end
  Trim(out, count)
  return out, count
end

-- Instance kind of a zone bucket: "d", "r" or "p" (largest of d + D, r + R, p + P;
-- ties d, then r, then p), or nil when it holds no instance time.
local function InstanceKind(s)
  local d = (s.d or 0) + (s.D or 0)
  local r = (s.r or 0) + (s.R or 0)
  local p = (s.p or 0) + (s.P or 0)
  if d <= 0 and r <= 0 and p <= 0 then return nil end
  if d >= r and d >= p then return "d" end
  if r >= p then return "r" end
  return "p"
end

local instSpare = {}   -- row tables trimmed from a TopInstances `out`, reused

-- True when a numeric zone key is a Dungeon-typed map. Cached per key: C_Map is called
-- on a cache miss only (GetMapInfo allocates).
local function IsDungeonMap(zoneKey)
  local d = dungeonOf[zoneKey]
  if d ~= nil then return d end
  local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zoneKey)
  d = (info and info.mapType == MT_DUNGEON) and true or false
  dungeonOf[zoneKey] = d
  return d
end

-- Most played instances of a zone map (char.zones, levels[L].z or an AccountZones
-- result): rows { key, name, secs, kind } in out[1..count], secs = instance seconds
-- under mask (> 0), kind = the bucket's main instance kind, sorted by secs desc (ties:
-- raw instance time, numeric keys first, key). `out` rows are reused and the surplus
-- is kept in a small private pool, so repeated calls do not grow memory. The merged
-- "o" bucket is never listed, nor a map zone (numeric key) that is not a dungeon map
-- and holds less instance time than other time: an open-world zone or a capital where
-- the game reported the instance a tick before the map while zoning in (Undercity for
-- a second). Rows also carry raw (instance seconds, no exclusion), afk (its AFK part)
-- and xp (the bucket's XP). With `merge`, rows of the same name and kind are one row
-- (sums of secs, raw, afk and xp; the key of the longest part): the game often gives
-- the first seconds in a battleground or a dungeon under its instance ("i<id>") before
-- the map is known, so the same place holds two keys. The 2n longest are merged, then
-- the n longest kept. Tooltip / window builds only. Returns count.
function Stats.TopInstances(zoneMap, mask, n, out, merge)
  if type(out) ~= "table" then return 0 end
  n = n or 5
  local cap = merge and n * 2 or n
  local count = 0
  if type(zoneMap) == "table" and n > 0 then
    for k, z in pairs(zoneMap) do
      local s = type(z) == "table" and z.s
      local raw = s and k ~= "o"
        and (s.d or 0) + (s.D or 0) + (s.r or 0) + (s.R or 0) + (s.p or 0) + (s.P or 0) or 0
      if raw > 0 and type(k) == "number" and raw * 2 < SumAll(z) and not IsDungeonMap(k) then
        raw = 0
      end
      if raw > 0 then
        local secs = InstanceTime(z, mask)
        if secs > 0 then
          if count < cap then
            local row = out[count + 1]
            if type(row) ~= "table" then
              local nSpare = #instSpare
              if nSpare > 0 then
                row = instSpare[nSpare]
                instSpare[nSpare] = nil
              else
                row = {}
              end
              out[count + 1] = row
            end
          end
          local row
          count, row = TopInsert(out, count, cap, secs, raw, k)
          if row then row.bucket = z end
        end
      end
    end
  end
  for i = 1, count do
    local row = out[i]
    local z = row.bucket
    row.bucket = nil
    row.secs, row.raw = row.score, row.tie
    row.afk = row.raw - InstanceTime(z, C.MASK_AFK)
    row.xp = tonumber(z.xp) or 0
    row.name = ZoneName(row.key, z)
    row.kind = InstanceKind(z.s)
  end
  if merge then
    -- rows are sorted by secs desc: a later row of the same place joins the first one,
    -- the merged-away tables go to the tail (spare); then sorted again (sums move up)
    local kept = 0
    for i = 1, count do
      local row, into = out[i], nil
      for j = 1, kept do
        local o = out[j]
        if o.name == row.name and o.kind == row.kind then
          into = o
          break
        end
      end
      if into then
        into.secs, into.raw = into.secs + row.secs, into.raw + row.raw
        into.afk, into.xp = into.afk + row.afk, into.xp + row.xp
      else
        kept = kept + 1
        out[kept], out[i] = row, out[kept]
      end
    end
    for i = 2, kept do
      local row, p = out[i], i
      while p > 1 and Before(row.secs, row.raw, row.key, out[p - 1].secs, out[p - 1].raw, out[p - 1].key) do
        out[p] = out[p - 1]
        p = p - 1
      end
      out[p] = row
    end
    count = kept < n and kept or n
  end
  for i = #out, count + 1, -1 do
    local row = out[i]
    out[i] = nil
    if type(row) == "table" and #instSpare < SPARE_MAX then instSpare[#instSpare + 1] = row end
  end
  return count
end

-- (alloc) Merged zone map over all characters (account view only, 5.19).
-- out[zoneKey] = { s = { ... }, xp, name }; existing entries of `out` are recycled.
function Stats.AccountZones(db, out)
  out = out or {}
  for _, z in pairs(out) do
    wipe(z.s)
    z.xp = 0
    z.name = nil
  end
  local chars = db and db.chars
  if type(chars) == "table" then
    for _, ch in pairs(chars) do
      local zones = type(ch) == "table" and ch.zones
      if type(zones) == "table" then
        for k, z in pairs(zones) do
          if type(z) == "table" then
            local o = out[k]
            if not o then
              o = { s = {}, xp = 0 }
              out[k] = o
            end
            local s, os = z.s, o.s
            if type(s) == "table" then
              for sk, v in pairs(s) do
                if type(v) == "number" then os[sk] = (os[sk] or 0) + v end
              end
            end
            if type(z.xp) == "number" then o.xp = o.xp + z.xp end
            if o.name == nil and z.name then o.name = z.name end
          end
        end
      end
    end
  end
  for k, z in pairs(out) do
    if next(z.s) == nil and z.xp == 0 then out[k] = nil end
  end
  return out
end

-- Continent uiMapID of a numeric zone key: first ancestor (or the map itself) typed
-- Continent; false when the chain has none. Cached per key: C_Map is called on a
-- cache miss only (GetMapInfo allocates).
local function ContinentOf(zoneKey)
  local c = contOf[zoneKey]
  if c ~= nil then return c end
  c = false
  local getInfo = C_Map and C_Map.GetMapInfo
  if getInfo then
    local id, depth = zoneKey, 0
    while id and id ~= 0 and depth < MAX_ZONE_DEPTH do
      local info = getInfo(id)
      if not info then break end
      if info.mapType == MT_CONTINENT then
        c = id
        break
      end
      id = info.parentMapID
      depth = depth + 1
    end
  end
  contOf[zoneKey] = c
  return c
end

-- Rows of the instance kinds, named like the breakdown parts (Dungeons, Raids, PvP).
local KIND_ROW = { d = "dungeon", r = "raid", p = "pvp" }
local KIND_ROW_NAME = { dungeon = "BD_DUNGEON", raid = "BD_RAID", pvp = "BD_PVP" }

-- Row key of a zone key: for an instance key "i<id>" the row of its main kind
-- ("dungeon", "raid" or "pvp"; "dungeon" when it holds no instance time); a map played
-- mostly in an instance (a dungeon or battleground map) the row of that kind too; any
-- other map its continent uiMapID; else "other" (name keys "n<text>", the neutral "o"
-- bucket, maps without a continent).
local function ContinentRowKey(zoneKey, z)
  local tk = type(zoneKey)
  if tk == "string" and string_byte(zoneKey, 1) == BYTE_I then
    return KIND_ROW[InstanceKind(z.s) or "d"]
  end
  if tk ~= "number" then return "other" end
  local kind = InstanceKind(z.s)
  if kind and InstanceTime(z, 0) * 2 >= SumAll(z) then return KIND_ROW[kind] end
  return ContinentOf(zoneKey) or "other"
end

local function ContinentName(key)
  local kindName = KIND_ROW_NAME[key]
  if kindName then return L[kindName] end
  return ZoneName(key, nil)             -- C_Map name, cached in nameOf
end

local function ContinentBefore(x, y)
  return Before(x.secs, 0, x.key, y.secs, 0, y.key)
end

-- (alloc: first calls only) Time per continent of a zone map (char.zones,
-- levels[L].z or an AccountZones result) under `mask`. Fills the array `out`
-- (its previous rows are reused or dropped) with rows { key, name, secs }, secs > 0,
-- sorted by secs descending; returns the row count. Tooltip / window builds only.
-- Time without a continent ("other": flights where the game gave only the continent,
-- the neutral bucket) is left out: a row the player cannot place means nothing to them.
function Stats.Continents(zoneMap, mask, out)
  if type(out) ~= "table" then return 0 end
  wipe(contSecs)
  if type(zoneMap) == "table" then
    for k, z in pairs(zoneMap) do
      if type(z) == "table" then
        local secs = Sum(z, mask)
        if secs > 0 then
          local ck = ContinentRowKey(k, z)   -- secs > 0: z.s is a table
          if ck ~= "other" then contSecs[ck] = (contSecs[ck] or 0) + secs end
        end
      end
    end
  end
  local n = 0
  for ck, secs in pairs(contSecs) do
    n = n + 1
    local row = out[n]
    if type(row) ~= "table" then
      local nSpare = #spareRows
      if nSpare > 0 then
        row = spareRows[nSpare]
        spareRows[nSpare] = nil
      else
        row = {}
      end
      out[n] = row
    end
    row.key, row.secs = ck, secs
    row.name = ContinentName(ck)
  end
  for i = #out, n + 1, -1 do
    local row = out[i]
    out[i] = nil
    if type(row) == "table" and #spareRows < SPARE_MAX then spareRows[#spareRows + 1] = row end
  end
  if n > 1 then table_sort(out, ContinentBefore) end
  wipe(contSecs)
  return n
end

---------------------------------------------------------------------------
-- History tables (alloc, UI refreshes only)
---------------------------------------------------------------------------

local function Descending(a, b) return a > b end

-- Largest zone of a level by filtered time (exclusions applied, request 4), ties
-- by raw time then key; named with the character's zone records.
local function MainZone(char, lb, mask)
  local z = lb.z
  if type(z) ~= "table" then return nil, nil end
  local bestKey, bestScore, bestRaw = nil, 0, 0
  for k, zb in pairs(z) do
    local raw = SumAll(zb)
    if raw > 0 then
      local score = Sum(zb, mask)
      if bestKey == nil or Before(score, raw, k, bestScore, bestRaw, bestKey) then
        bestKey, bestScore, bestRaw = k, score, raw
      end
    end
  end
  if bestKey == nil then return nil, nil end
  local zones = char.zones
  return ZoneName(bestKey, (zones and zones[bestKey]) or z[bestKey]), bestKey
end

local function FillLevelRow(row, char, l, mask, sync, now, isCurrent)
  local lb = char.levels[l]
  local raw = SumAll(lb)
  local filtered, server
  if isCurrent then
    -- the server's level part, else its total less the level's start (Stats.LevelServer)
    filtered = (Stats.LevelTime(char, l, mask, sync, now))
    server = Stats.LevelServer(char, l, sync, now)
  else
    filtered = Sum(lb, mask)
    if lb.srvStart and lb.srvEnd then server = lb.srvEnd - lb.srvStart end
  end
  if server and server < 0 then server = nil end
  local gap = nil
  if server and server - raw > DRIFT_TOL then gap = server - raw end

  row.level = l
  row.filtered = filtered
  row.raw = raw
  row.server = server
  row.serverEst = (lb.srvStartEst or lb.srvEndEst) and true or false
  row.gap = gap
  row.est = lb.est or 0                   -- rebuilt seconds, gross (every key)
  local estF = EstOf(lb, mask)            -- the rebuilt part of `filtered`
  if estF > filtered then estF = filtered end
  row.estF = estF
  row.xp = lb.xp or 0
  row.xph = Stats.LevelRate(char, l, mask)
  row.afk = SumKeys(lb, AFK_KEYS)
  local s = lb.s
  row.inn = s and ((s.i or 0) + (s.I or 0)) or 0
  row.city = s and ((s.c or 0) + (s.C or 0)) or 0
  row.inst = InstanceTime(lb, mask)       -- dungeons + raids + PvP under the mask
  row.mainZone, row.mainZoneKey = MainZone(char, lb, mask)
  row.reachedAt = lb.t0
  -- the level was left (the next one reached): its own end mark, else the start of the
  -- next record (nil for the current level, or when neither is known)
  local nb = not isCurrent and char.levels[l + 1] or nil
  row.endAt = lb.t1 or (type(nb) == "table" and nb.t0) or nil
  row.partial = lb.partial == true
  row.rec = lb.rec == true
  row.deaths = lb.d or 0
  row.dead = s and s.x or 0              -- seconds dead or a ghost (never excluded)
  row.prof = s and s.f or 0              -- seconds of professions (never excluded)
  row.eta, row.etaP = lb.eta, lb.etaP    -- estimate when the level began (nil: none)
  row.etaM = lb.etaM                     -- its exclusion mask (nil: taken by an older version)
  row.pw = PvpWorldOf(lb)                -- open-world PvP seconds (a part of s.w, capped)
  row.xa, row.xq, row.xr = lb.xa or 0, lb.xq or 0, lb.xr or 0   -- XP: mobs, quests and other, rested
  row.max = lb.max                       -- XP from this level to the next (nil: unknown)
  row.stall = StallOf(lb, mask)          -- seconds without XP gain (stalled) under the mask
  row.current = isCurrent
end

-- (alloc) One row per level record, current level first then descending.
-- Rows: { level, filtered, raw, server, gap, est, xp, xph, afk, inn, city, mainZone,
-- reachedAt, partial, rec, deaths, current } (+ serverEst, mainZoneKey, inst, dead, prof,
-- eta, etaP, etaM = the mask eta was taken under (nil: unknown), cum, endAt = epoch the
-- next level was reached, estF = the rebuilt seconds
-- under the mask, at most `filtered`; est is gross; the Levels tab's detail sheet: pw =
-- the open-world PvP seconds capped at s.w (0: none or not measured, see
-- Stats.WorldPvpState), xa / xq / xr = the level's XP from mobs / quests and other /
-- the rested bonus, max = its XP size (nil: unknown), stall = its stalled seconds under
-- the mask, part of `filtered`). `server` is nil when
-- unknown; `gap` is nil unless server - raw > C.DRIFT_TOL. `cum`: see Stats.CumulativeTime (nil above the character's level).
function Stats.LevelHistory(char, mask, sync, now, out)
  out = out or {}
  now = now or GetTime()
  local count = 0
  local levels = char and char.levels
  if type(levels) == "table" then
    wipe(levelList)
    for l, lb in pairs(levels) do
      if type(l) == "number" and type(lb) == "table" then levelList[#levelList + 1] = l end
    end
    table_sort(levelList, Descending)
    local cur = char.level
    -- cumulative time, walked down from the played total (Stats.CumulativeTime)
    local cum, prev = nil, nil
    if cur and type(levels[cur]) == "table" then
      count = count + 1
      local row = out[count] or {}
      out[count] = row
      FillLevelRow(row, char, cur, mask, sync, now, true)
      cum = Stats.Played(char, mask, sync, now)
      row.cum, prev = cum, row.filtered
    end
    for i = 1, #levelList do
      local l = levelList[i]
      if l ~= cur then
        count = count + 1
        local row = out[count] or {}
        out[count] = row
        FillLevelRow(row, char, l, mask, sync, now, false)
        if cum ~= nil and type(cur) == "number" and l < cur then
          cum = cum - prev
          if cum < 0 then cum = 0 end
          row.cum, prev = cum, row.filtered
        else
          row.cum = nil
        end
      end
    end
    wipe(levelList)
  end
  Trim(out, count)
  return out, count
end

local function FillSessionRow(row, s, mask, isCurrent, level)
  row.t0 = s.t0
  row.t1 = s.t1
  row.dur = Sum(s, mask)
  row.l0 = s.l0
  row.p0 = s.p0
  row.l1 = s.l1 or (isCurrent and level) or nil
  row.p1 = s.p1
  row.xp = s.xp or 0
  row.xph = Stats.SessionRate(s, mask)
  row.afk = SumKeys(s, AFK_KEYS)
  row.inst = InstanceTime(s, mask)
  row.deaths = s.d or 0
  local ss = s.s
  row.dead = type(ss) == "table" and ss.x or 0
  row.prof = type(ss) == "table" and ss.f or 0
  row.current = isCurrent
end

-- (alloc) Sessions of one character: the in-progress one (char.cur) first, then the
-- ring newest first. Rows: { t0, dur, l0, p0, l1, p1, xp, xph, afk, current } (+ t1,
-- deaths, inst, dead, prof). For the in-progress row l1 = char.level and p1 is left to the caller.
function Stats.SessionHistory(char, mask, out)
  out = out or {}
  local count = 0
  if type(char) == "table" then
    local cur = char.cur
    if type(cur) == "table" then
      count = count + 1
      local row = out[count] or {}
      out[count] = row
      FillSessionRow(row, cur, mask, true, char.level)
    end
    local ring = char.sessions
    if type(ring) == "table" then
      for i = #ring, 1, -1 do
        local s = ring[i]
        if type(s) == "table" then
          count = count + 1
          local row = out[count] or {}
          out[count] = row
          FillSessionRow(row, s, mask, false, nil)
        end
      end
    end
  end
  Trim(out, count)
  return out, count
end

---------------------------------------------------------------------------
-- Account (explicitly labelled cross-character figures, 5.19)
---------------------------------------------------------------------------

-- Sum of every record's life. Returns filtered, raw, nChars.
function Stats.Account(db, mask)
  local chars = db and db.chars
  if type(chars) ~= "table" then return 0, 0, 0 end
  local filtered, raw, n = 0, 0, 0
  for _, ch in pairs(chars) do
    if type(ch) == "table" then
      local life = ch.life
      filtered = filtered + Sum(life, mask)
      raw = raw + SumAll(life)
      n = n + 1
    end
  end
  return filtered, raw, n
end

-- Instance seconds (dungeons, raids, PvP: d, D, r, R, p, P) under the mask, summed over
-- every record's life: the account line of the detailed tooltip and the account
-- footer of the window.
function Stats.AccountInstanceTime(db, mask)
  local total = 0
  local chars = db and db.chars
  if type(chars) == "table" then
    for _, ch in pairs(chars) do
      if type(ch) == "table" and type(ch.life) == "table" then total = total + InstanceTime(ch.life, mask) end
    end
  end
  return total
end

-- A level counts for averages when it is complete (below the record's level), neither
-- partial nor reconstructed, and holds time.
local function IsCompleteLevel(l, lb, cur)
  return type(l) == "number" and type(lb) == "table" and l < cur
    and not lb.partial and not lb.rec and SumAll(lb) > 0
end

-- (alloc) Per-level averages over all characters. Rows { level, n, avg, xph } sorted by
-- level; xph is nil when the tracked sample is shorter than C.RATE_SAMPLE_MIN.
function Stats.AccountLevelAverages(db, mask, out)
  out = out or {}
  wipe(accN); wipe(accT); wipe(accX); wipe(accD)
  local chars = db and db.chars
  if type(chars) == "table" then
    for _, ch in pairs(chars) do
      local levels = type(ch) == "table" and ch.levels
      local cur = type(ch) == "table" and ch.level
      if type(levels) == "table" and type(cur) == "number" then
        for l, lb in pairs(levels) do
          if IsCompleteLevel(l, lb, cur) then
            local f = Sum(lb, mask)
            accN[l] = (accN[l] or 0) + 1
            accT[l] = (accT[l] or 0) + f
            accX[l] = (accX[l] or 0) + (lb.xp or 0)
            accD[l] = (accD[l] or 0) + f - UntrackedOf(lb) - StallOf(lb, mask)
          end
        end
      end
    end
  end
  wipe(levelList)
  for l in pairs(accN) do levelList[#levelList + 1] = l end
  table_sort(levelList)
  local count = #levelList
  for i = 1, count do
    local l = levelList[i]
    local row = out[i] or {}
    out[i] = row
    row.level = l
    row.n = accN[l]
    row.avg = accT[l] / accN[l]
    local d = accD[l]
    row.xph = (d >= RATE_SAMPLE_MIN) and (3600 * accX[l] / d) or nil
  end
  wipe(levelList)
  Trim(out, count)
  return out, count
end

-- Account average per level over complete, non-partial, non-rec levels of all
-- characters. Returns avg or nil, nChars (characters contributing at least one level).
function Stats.AccountAvgPerLevel(db, mask)
  local chars = db and db.chars
  if type(chars) ~= "table" then return nil, 0 end
  local total, nLevels, nChars = 0, 0, 0
  for _, ch in pairs(chars) do
    local levels = type(ch) == "table" and ch.levels
    local cur = type(ch) == "table" and ch.level
    if type(levels) == "table" and type(cur) == "number" then
      local contributed = false
      for l, lb in pairs(levels) do
        if IsCompleteLevel(l, lb, cur) then
          total = total + Sum(lb, mask)
          nLevels = nLevels + 1
          contributed = true
        end
      end
      if contributed then nChars = nChars + 1 end
    end
  end
  if nLevels == 0 then return nil, nChars end
  return total / nLevels, nChars
end

---------------------------------------------------------------------------
-- Activity per level (lot 8: dead, professions, level-start estimate, cumulative time)
---------------------------------------------------------------------------

-- Activity of one level of char: deaths (count), dead (seconds dead or a ghost), prof
-- (seconds of professions), eta (estimated time to the next level when the level began,
-- seconds, or nil), etaP (the XP fraction at that moment, or nil). All 0 / nil for a
-- level without a record. Neither dead nor prof is ever excluded by a mask.
function Stats.LevelActivity(char, level)
  local levels = char and char.levels
  local lb = type(levels) == "table" and level and levels[level]
  if type(lb) ~= "table" then return 0, 0, 0, nil, nil end
  local s = lb.s
  local dead = type(s) == "table" and s.x or 0
  local prof = type(s) == "table" and s.f or 0
  return lb.d or 0, dead, prof, lb.eta, lb.etaP
end

-- Seconds from the creation of the character (level 1) to the END of `level` (for the
-- current level: to now), counted under the mask like the level times. It is the played
-- total (Stats.Played: the server /played when synced, so the time before the install
-- is included, unfiltered as a server /played has no split) minus the filtered time of
-- every recorded level above `level` up to the current one. A level skipped without a
-- record counts 0 (its time stays in the level below it). nil when the record has no
-- current level or `level` is above it; never below 0.
function Stats.CumulativeTime(char, level, mask, sync, now)
  local levels = char and char.levels
  local cur = char and char.level
  if type(levels) ~= "table" or type(cur) ~= "number" or type(level) ~= "number" or level > cur then
    return nil
  end
  now = now or GetTime()
  local cum = Stats.Played(char, mask, sync, now)
  for l = cur, level + 1, -1 do
    local lb = levels[l]
    if type(lb) == "table" then
      if l == cur then
        cum = cum - Stats.LevelTime(char, l, mask, sync, now)
      else
        cum = cum - Sum(lb, mask)
      end
    end
  end
  if cum < 0 then cum = 0 end
  return cum
end

-- Dead seconds, professions seconds and deaths summed over every record's life (the
-- account figures; never excluded by a mask).
function Stats.AccountActivity(db)
  local dead, prof, deaths = 0, 0, 0
  local chars = db and db.chars
  if type(chars) == "table" then
    for _, ch in pairs(chars) do
      local life = type(ch) == "table" and ch.life
      if type(life) == "table" then
        local s = life.s
        if type(s) == "table" then
          dead = dead + (s.x or 0)
          prof = prof + (s.f or 0)
        end
        deaths = deaths + (life.d or 0)
      end
    end
  end
  return dead, prof, deaths
end

---------------------------------------------------------------------------
-- The Levels tab (histogram and detail sheet): the parts of a bar, the battlegrounds,
-- world PvP measured or not, the XP size of a level, the levels still to play
---------------------------------------------------------------------------

local EMPTY_S = {}                       -- read-only stand-in for a missing `s` or `info`
local CLASSIC_XP = C.CLASSIC_XP
local HUGE = math.huge

-- Fills `out` with the parts of a bucket's bar under the mask (a level record or
-- char.life): world = w less the world PvP, wpvp = the world PvP (pw capped at w, see
-- PvpWorldOf), dungeon = d, raid = r, bg = p (battlegrounds and arenas), taxi = t plus the
-- AFK on a taxi T when the mask includes it (a long flight often turns AFK on its own and
-- is still a flight: the tooltip's flight line, Breakdown's t + T), prof = f, dead = x,
-- city = c and inn = i when the mask includes them (else 0), afk = the other AFK keys (W D
-- R P I C) the mask includes (a battleground's or a dungeon's AFK stays there), untracked
-- = u, total. Returns total. The parts always sum to Stats.Sum(bucket, mask) (u, x and f
-- are never excluded, w is split in two): a stacked bar drawn from them is exactly the
-- bar's height. A nil bucket gives zeros. Nothing allocated (tick path: the current
-- level's bar).
function Stats.LevelSegments(bucket, mask, out)
  local inc = INCLUDED[mask or 0] or INCLUDED[0]
  local s = bucket and bucket.s
  if type(s) ~= "table" then s = EMPTY_S end
  local w = s.w or 0
  local pw = PvpWorldOf(bucket)
  local d, r, p, t, f, x, u = s.d or 0, s.r or 0, s.p or 0, s.t or 0, s.f or 0, s.x or 0, s.u or 0
  if inc.T then t = t + (s.T or 0) end
  local c = inc.c and (s.c or 0) or 0
  local i = inc.i and (s.i or 0) or 0
  local afk = 0
  for j = 1, #AFK_KEYS do
    local k = AFK_KEYS[j]
    if inc[k] and k ~= "T" then afk = afk + (s[k] or 0) end
  end
  out.world, out.wpvp = w - pw, pw
  out.dungeon, out.raid, out.bg, out.taxi = d, r, p, t
  out.prof, out.dead, out.city, out.inn = f, x, c, i
  out.afk, out.untracked = afk, u
  local total = w + d + r + p + t + f + x + c + i + afk + u
  out.total = total
  return total
end

-- Battleground rows: the most seconds first, then the name.
local function BgBefore(x, y)
  if x.secs ~= y.secs then return x.secs > y.secs end
  return x.name < y.name
end

-- (alloc) Battlegrounds and arenas of a zone map: rows { key, name, secs } in
-- out[1..n] of the zones whose main instance kind is "p" (InstanceKind: a battleground's
-- own map, a numeric key, or "i<instanceID>"), secs = their p, plus P when the mask
-- includes it, > 0. A map zone must hold at least as much battleground time as other time
-- besides its dead time x (a battleground's map holds nothing else; an open-world zone or
-- a capital where the game reported the instance a tick before the map is left out). The
-- merged "o" bucket is never listed. Rows of the same name (a battleground saved under its
-- map and its instance key) are merged (key: the larger part's). Sorted by secs desc, then
-- name. Returns n and other = the bucket's own battleground part (s.p, + s.P when
-- included) less the rows, >= 0: time merged into "o" (a level keeps its 10 largest
-- zones), pruned zones, left-out ticks. names: the zone records that hold the names
-- (char.zones; the level's zone buckets have none), else the buckets themselves.
local function Battlegrounds(zmap, names, bucket, mask, out)
  local inc = INCLUDED[mask or 0] or INCLUDED[0]
  local n = 0
  if type(zmap) == "table" then
    for k, z in pairs(zmap) do
      local s = type(z) == "table" and z.s
      if type(s) == "table" and k ~= "o" and InstanceKind(s) == "p" then
        local raw = (s.p or 0) + (s.P or 0)
        if type(k) ~= "number" or raw * 2 >= SumAll(z) - (s.x or 0) then
          local secs = (s.p or 0) + (inc.P and (s.P or 0) or 0)
          if secs > 0 then
            local nb = type(names) == "table" and names[k]
            local name = ZoneName(k, type(nb) == "table" and nb or z)
            local row = nil
            for j = 1, n do
              if out[j].name == name then
                row = out[j]
                break
              end
            end
            if row then
              row.secs = row.secs + secs
              if Before(secs, 0, k, row.ks, 0, row.key) then row.key, row.ks = k, secs end
            else
              n = n + 1
              row = out[n]
              if type(row) ~= "table" then
                row = {}
                out[n] = row
              end
              row.key, row.name, row.secs, row.ks = k, name, secs, secs
            end
          end
        end
      end
    end
  end
  Trim(out, n)
  local sum = 0
  for j = 1, n do
    local row = out[j]
    row.ks = nil
    sum = sum + row.secs
  end
  if n > 1 then table_sort(out, BgBefore) end
  local bs = bucket and bucket.s
  local part = 0
  if type(bs) == "table" then part = (bs.p or 0) + (inc.P and (bs.P or 0) or 0) end
  local other = part - sum
  if other < 0 then other = 0 end
  return n, other
end

-- (alloc) The battlegrounds and arenas played at level L (levels[L].z, named from
-- char.zones): see Battlegrounds. Returns n, other (the level's p (+ P) left after the
-- rows). A level without a record: 0, 0. Hover / rebuild only.
function Stats.LevelBattlegrounds(char, level, mask, out)
  local levels = char and char.levels
  local lb = type(levels) == "table" and level and levels[level]
  if type(lb) ~= "table" then
    Trim(out, 0)
    return 0, 0
  end
  return Battlegrounds(lb.z, char.zones, lb, mask, out)
end

-- (alloc) The same over the character's whole life (char.zones, which carry their names;
-- other = life's p (+ P) left after the rows: the zones pruned at logout among them).
function Stats.LifeBattlegrounds(char, mask, out)
  return Battlegrounds(char and char.zones, nil, char and char.life, mask, out)
end

-- Whether the world PvP of level L was measured (Pvp.lua, char.pvp.w0: the time() it
-- began for this character): "yes" when the level began at or after w0 (t0 >= w0),
-- "partial" when it began before and ended after it (or is the current level, or its
-- start is unknown: the install's level), "no" when w0 is unknown (a record from before
-- it, Classic Era, read-only), the level ended at or before w0 (end = t1, else the next
-- level's t0), it has no record or it was rebuilt whole after a crash (rec: no time was
-- seen). The UI says "not measured on this client" itself when ns.Pvp is not available.
-- Nothing allocated.
function Stats.WorldPvpState(char, level)
  local p = char and char.pvp
  local w0 = type(p) == "table" and p.w0 or nil
  if type(w0) ~= "number" or w0 ~= w0 then return "no" end
  local levels = char.levels
  local lb = type(levels) == "table" and type(level) == "number" and levels[level]
  if type(lb) ~= "table" or lb.rec then return "no" end
  local nb = levels[level + 1]
  local t1 = lb.t1
  if type(t1) ~= "number" then t1 = type(nb) == "table" and nb.t0 or nil end
  if type(t1) == "number" and t1 <= w0 then return "no" end
  local t0 = lb.t0
  if type(t0) == "number" and w0 <= t0 then return "yes" end
  return "partial"
end

-- XP from level l to l + 1 as seen in the game: the character's own (levels[l].max),
-- else the account's (db.xpMax[l]); nil when neither is a number >= 1.
local function KnownXP(char, db, l)
  local levels = char and char.levels
  local lb = type(levels) == "table" and levels[l]
  local v = type(lb) == "table" and lb.max
  if type(v) == "number" and v >= 1 and v < HUGE then return v end
  local xm = type(db) == "table" and db.xpMax
  v = type(xm) == "table" and xm[l]
  if type(v) == "number" and v >= 1 and v < HUGE then return v end
  return nil
end

-- The scale of C.CLASSIC_XP on this client: the mean ratio known / table of the known
-- sizes that contradict the table (1 when none does: the table is right, or unverified).
local function XPRatio(char, db)
  local sum, n = 0, 0
  for l = 1, #CLASSIC_XP do
    local k = KnownXP(char, db, l)
    local t = CLASSIC_XP[l]
    if k and k ~= t then
      sum = sum + k / t
      n = n + 1
    end
  end
  if n == 0 then return 1 end
  return sum / n
end

-- XPOf with the table's scale given (nil: computed when needed).
local function XPOfR(char, db, l, ratio)
  local k = KnownXP(char, db, l)
  if k then return k end
  local t = CLASSIC_XP[l]
  if not t then return nil end
  if ratio == nil then ratio = XPRatio(char, db) end
  return floor(t * ratio + 0.5)
end

-- XP needed from level l to l + 1: levels[l].max, else db.xpMax[l], else C.CLASSIC_XP[l]
-- scaled by the mean ratio known / table of the known sizes (this character's and the
-- account's) that contradict the table (a server with another curve), rounded; nil
-- when nothing is known (l beyond the table without a known size). Nothing allocated.
function Stats.XPOf(char, db, l)
  if type(l) ~= "number" then return nil end
  return XPOfR(char, db, l, nil)
end

-- XP of a Classic mob of the player's level: about 45 + 5 L (the per-level scale of the
-- projection: the pace in kills per hour stays, the XP of a kill grows).
local function MobXP(l)
  return 45 + 5 * l
end

-- Estimated seconds of level l: K s per (XP / MobXP) from the recent levels, else the
-- rate (XP/s at `level`) scaled to l by MobXP; nil without an XP size.
local function EstLevel(char, db, l, ratio, K, rate, level)
  local x = XPOfR(char, db, l, ratio)
  if not x then return nil end
  if K then return K * x / MobXP(l) end
  return x / rate * MobXP(level) / MobXP(l)
end

-- Projection of the levels still to play (an ESTIMATE: the UI prefixes "~"). info =
-- { level, xp, max, rest, valid, isMax, capLevel, top } prepared by the caller (the
-- current character: Tracker.GetXPInfo, GetCapInfo, Util.MaxLevel; another character:
-- char.level, char.xpSnap's xp / max, no rest, valid false), optional sync / now for
-- the time already spent in the current level (Stats.LevelTime). Fills `out`:
--   status  "ok" (from the recent levels), "estimate" (from the XP rate), "nodata",
--           "max" (level >= top, or info.isMax), "cap" (info.capLevel reached: a server
--           cap); no projection but "ok" and "estimate"
--   src     "recent" | "rate" (nil without a projection)
--   cur     seconds left in the current level (nil: unknown)
--   [l]     estimated seconds of level l, l = level + 1 .. top - 1 (nil: no XP size,
--           counted in `missing`); every other index nil
--   total   cur + the sum of the [l] (nil without a projection), top, n (samples)
-- Method: K = sum(time_l) / sum(XPOf(l) / (45 + 5 l)) over the complete levels l of the
-- last C.RECENT_LEVELS (l < level, neither partial nor rec, time_l = Sum(lb, mask) less
-- its stalled and untracked seconds > 0, a known XP size); est(l) = K * XPOf(l) /
-- (45 + 5 l). Needs 2 samples, else the rate: est(l) = XPOf(l) / (A + Q) * (45 + 5 level)
-- / (45 + 5 l) (Stats.Rate under the mask, XP per counted second). The current level:
-- Stats.ETA from xp / max / rest (rest-aware) when info.valid, else est(level) less the
-- time spent in it (>= 0). Nothing allocated after the first call with the same `out`
-- for the same level (the tick path may refresh it). Returns out.
function Stats.FutureLevels(char, db, mask, info, out)
  mask = mask or 0
  if type(info) ~= "table" then info = EMPTY_S end
  local level = info.level
  if type(level) ~= "number" then level = char and char.level end
  local top = info.top
  if type(top) ~= "number" then top = #CLASSIC_XP + 1 end
  local last = out.top
  if type(last) ~= "number" or last < top then last = top end
  for l = 1, last do out[l] = nil end
  out.top, out.n, out.missing = top, 0, 0
  out.cur, out.total, out.src = nil, nil, nil
  if type(level) ~= "number" then
    out.status = "nodata"
    return out
  end
  local cap = info.capLevel
  if type(cap) == "number" and level >= cap then
    out.status = "cap"
    return out
  end
  if level >= top or info.isMax then
    out.status = "max"
    return out
  end
  local ratio = XPRatio(char, db)
  local levels = char and char.levels
  local st, sw, n = 0, 0, 0
  if type(levels) == "table" then
    local lo = level - RECENT_LEVELS
    if lo < 1 then lo = 1 end
    for l = level - 1, lo, -1 do
      local lb = levels[l]
      if type(lb) == "table" and not lb.partial and not lb.rec then
        local t = Sum(lb, mask) - StallOf(lb, mask) - UntrackedOf(lb)
        local x = t > 0 and XPOfR(char, db, l, ratio) or nil
        if x then
          st, sw, n = st + t, sw + x / MobXP(l), n + 1
        end
      end
    end
  end
  out.n = n
  local K, rate = nil, nil
  if n >= 2 and sw > 0 then
    K = st / sw
    out.status, out.src = "ok", "recent"
  else
    local _, A, _, Q = Stats.Rate(char, mask)
    local aq = (A or 0) + (Q or 0)
    if not (aq > 0) then   -- luacheck: ignore 581 (NaN fails too)
      out.status = "nodata"
      return out
    end
    rate = aq
    out.status, out.src = "estimate", "rate"
  end
  local cur = nil
  local xp, max = info.xp, info.max
  if info.valid and type(xp) == "number" and type(max) == "number" and max > 0 then
    cur = Stats.ETA(char, mask, xp, max, info.rest, false)
  end
  if cur == nil then
    local e = EstLevel(char, db, level, ratio, K, rate, level)
    if e then
      cur = e - Stats.LevelTime(char, level, mask, info.sync, info.now)
      if cur < 0 then cur = 0 end
    end
  end
  local total, missing = cur or 0, 0
  for l = level + 1, top - 1 do
    local e = EstLevel(char, db, l, ratio, K, rate, level)
    out[l] = e
    if e then total = total + e else missing = missing + 1 end
  end
  out.cur, out.total, out.missing = cur, total, missing
  return out
end

---------------------------------------------------------------------------
-- Labels and caches
---------------------------------------------------------------------------

-- "AFK · inn · city" style label of a mask (nil for mask 0), built once per mask.
function Stats.MaskLabel(mask)
  if not mask or mask == 0 then return nil end
  local label = maskLabels[mask]
  if label == nil then
    local parts = {}
    if mask % 2 == 1 then parts[#parts + 1] = L.MASK_AFK end
    if floor(mask / 2) % 2 == 1 then parts[#parts + 1] = L.MASK_INN end
    if floor(mask / 4) % 2 == 1 then parts[#parts + 1] = L.MASK_CITY end
    label = table_concat(parts, L.SEP)
    maskLabels[mask] = label
  end
  return label
end

-- Clears the zone name and continent caches (Core.CheckSwap, before DB_SWAPPED).
function Stats.ResetCaches()
  wipe(nameOf)
  wipe(contOf)
  wipe(dungeonOf)
end
