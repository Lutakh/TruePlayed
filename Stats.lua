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

local type, pairs, next = type, pairs, next
local floor = math.floor
local table_sort, table_concat = table.sort, table.concat
local string_sub, string_byte = string.sub, string.byte
local GetTime = GetTime
local C_Map = C_Map
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
local BYTE_I = 105       -- string.byte("i"): instance zone keys "i<instanceID>"

local EMPTY_EMA = { a = 0, r = 0, q = 0, d = 0 }   -- read-only stand-in for a missing entry

-- Private caches (never saved).
local nameOf = {}        -- zoneKey -> localized name, or false when the map has no name
local contOf = {}        -- numeric zoneKey -> continent uiMapID, or false (none found)
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

-- Time spent at `level`. Live only when the sync carries a valid level part for it.
-- Returns filtered, base, live.
function Stats.LevelTime(char, level, mask, sync, now)
  local levels = char and char.levels
  local lb = levels and level and levels[level]
  local all = SumAll(lb)
  local live = sync ~= nil and sync.valid == true and sync.levelValid == true
    and sync.level == level and sync.levelPlayed ~= nil
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

-- Display name of a zone key. C_Map is consulted only for numeric keys (critique #6),
-- once per key (cached; C_Map.GetMapInfo allocates).
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
  local bn = zoneBucket and zoneBucket.name
  if bn then return bn end
  -- "n<zone text>" keys carry their own name (4.3); derive it once.
  local n = nameOf[zoneKey]
  if n == nil then
    n = false
    if type(zoneKey) == "string" and string_sub(zoneKey, 1, 1) == "n" and #zoneKey > 1 then
      n = string_sub(zoneKey, 2)
    end
    nameOf[zoneKey] = n
  end
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

-- Most played instances of a zone map (char.zones, levels[L].z or an AccountZones
-- result): rows { key, name, secs, kind } in out[1..count], secs = instance seconds
-- under mask (> 0), kind = the bucket's main instance kind, sorted by secs desc (ties:
-- raw instance time, numeric keys first, key). `out` rows are reused and the surplus
-- is kept in a small private pool, so repeated calls do not grow memory. The merged
-- "o" bucket is never listed. Tooltip / window builds only. Returns count.
function Stats.TopInstances(zoneMap, mask, n, out)
  if type(out) ~= "table" then return 0 end
  n = n or 5
  local count = 0
  if type(zoneMap) == "table" and n > 0 then
    for k, z in pairs(zoneMap) do
      local s = type(z) == "table" and z.s
      if s and k ~= "o" then
        local secs = InstanceTime(z, mask)
        if secs > 0 then
          local raw = (s.d or 0) + (s.D or 0) + (s.r or 0) + (s.R or 0) + (s.p or 0) + (s.P or 0)
          if count < n then
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
          count, row = TopInsert(out, count, n, secs, raw, k)
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
    row.name = ZoneName(row.key, z)
    row.kind = InstanceKind(z.s)
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

-- Row key of a zone key: continent uiMapID, "inst" (instance keys "i<id>") or
-- "other" (name keys "n<text>", the neutral "o" bucket, maps without a continent).
local function ContinentRowKey(zoneKey)
  local tk = type(zoneKey)
  if tk == "number" then return ContinentOf(zoneKey) or "other" end
  if tk == "string" and string_byte(zoneKey, 1) == BYTE_I then return "inst" end
  return "other"
end

local function ContinentName(key)
  if key == "inst" then return L.CONT_INSTANCES end
  if key == "other" then return L.CONT_OTHER end
  return ZoneName(key, nil)             -- C_Map name, cached in nameOf
end

local function ContinentBefore(x, y)
  return Before(x.secs, 0, x.key, y.secs, 0, y.key)
end

-- (alloc: first calls only) Time per continent of a zone map (char.zones,
-- levels[L].z or an AccountZones result) under `mask`. Fills the array `out`
-- (its previous rows are reused or dropped) with rows { key, name, secs }, secs > 0,
-- sorted by secs descending; returns the row count. Tooltip / window builds only.
function Stats.Continents(zoneMap, mask, out)
  if type(out) ~= "table" then return 0 end
  wipe(contSecs)
  if type(zoneMap) == "table" then
    for k, z in pairs(zoneMap) do
      if type(z) == "table" then
        local secs = Sum(z, mask)
        if secs > 0 then
          local ck = ContinentRowKey(k)
          contSecs[ck] = (contSecs[ck] or 0) + secs
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
    local base, live
    filtered, base, live = Stats.LevelTime(char, l, mask, sync, now)
    if live then
      server = base
    elseif sync ~= nil and sync.valid == true and sync.total and lb.srvStart then
      -- level part not usable, but the server total and the level start are known
      server = sync.total + (now - (sync.g or now)) - lb.srvStart
    end
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
  row.est = lb.est or 0
  row.xp = lb.xp or 0
  row.xph = Stats.LevelRate(char, l, mask)
  row.afk = SumKeys(lb, AFK_KEYS)
  local s = lb.s
  row.inn = s and ((s.i or 0) + (s.I or 0)) or 0
  row.city = s and ((s.c or 0) + (s.C or 0)) or 0
  row.inst = InstanceTime(lb, mask)       -- dungeons + raids + PvP under the mask
  row.mainZone, row.mainZoneKey = MainZone(char, lb, mask)
  row.reachedAt = lb.t0
  row.partial = lb.partial == true
  row.rec = lb.rec == true
  row.deaths = lb.d or 0
  row.dead = s and s.x or 0              -- seconds dead or a ghost (never excluded)
  row.prof = s and s.f or 0              -- seconds of professions (never excluded)
  row.eta, row.etaP = lb.eta, lb.etaP    -- estimate when the level began (nil: none)
  row.current = isCurrent
end

-- (alloc) One row per level record, current level first then descending.
-- Rows: { level, filtered, raw, server, gap, est, xp, xph, afk, inn, city, mainZone,
-- reachedAt, partial, rec, deaths, current } (+ serverEst, mainZoneKey, inst, dead, prof,
-- eta, etaP, cum). `server` is nil when unknown; `gap` is nil unless server - raw >
-- C.DRIFT_TOL. `cum`: see Stats.CumulativeTime (nil above the character's level).
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
end
