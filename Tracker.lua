local ADDON, ns = ...
-- Tracker.lua - time accounting (state x level x zone), XP chain, rate EMA,
-- session continuity and server /played reconciliation (crash recovery).
-- SPEC-FINAL sections 4, 5.2 - 5.16, 5.20. Hot paths (Tick, Flush, Credit,
-- ComputeState on a zone cache hit, frequent event handlers) never allocate.
-- Round 3: time without XP (stall guard, char.noXP, life.xs / levels[L].xs), server
-- level cap detection (char.capLevel) and the pre-install estimate v2.

local L, C, Util, Fmt = ns.L, ns.C, ns.Util, ns.Fmt

local math_floor, math_exp, math_max = math.floor, math.exp, math.max
local type, pairs, pcall, select = type, pairs, pcall, select
local table_sort, table_remove = table.sort, table.remove
local GetTime, time, wipe = GetTime, time, wipe
local UnitLevel, UnitXP, UnitXPMax, GetXPExhaustion = UnitLevel, UnitXP, UnitXPMax, GetXPExhaustion
local UnitIsAFK, IsResting, UnitOnTaxi = UnitIsAFK, IsResting, UnitOnTaxi
local IsInInstance, GetInstanceInfo, GetRealZoneText = IsInInstance, GetInstanceInfo, GetRealZoneText
local C_Map, C_Timer = C_Map, C_Timer

local SafeRead, Bump = Util.SafeRead, Util.Bump
local INCLUDED, STATE_KEYS, TRACKED_KEYS, KEY = C.INCLUDED, C.STATE_KEYS, C.TRACKED_KEYS, C.KEY
local IS_CITY, IS_INSTANCE, INSTANCE_KIND = C.IS_CITY, C.IS_INSTANCE, C.INSTANCE_KIND
local N_STATE, N_TRACKED = #STATE_KEYS, #TRACKED_KEYS
local MAPTYPE = Enum and Enum.UIMapType
local MT_ZONE = (MAPTYPE and MAPTYPE.Zone) or C.MAPTYPE_ZONE
local MT_DUNGEON = (MAPTYPE and MAPTYPE.Dungeon) or C.MAPTYPE_DUNGEON
local MT_CONTINENT = (MAPTYPE and MAPTYPE.Continent) or C.MAPTYPE_CONTINENT
local MT_WORLD = (MAPTYPE and MAPTYPE.World) or C.MAPTYPE_WORLD
local MT_COSMIC = (MAPTYPE and MAPTYPE.Cosmic) or C.MAPTYPE_COSMIC

local Tracker = {}
ns.Tracker = Tracker

---------------------------------------------------------------------------
-- In-memory state (SPEC 4.5). Tables are created once and reused.
---------------------------------------------------------------------------

local started = false
-- Current segment. lb/lz/zb (+ dlb/dlz/dzb for the delta) cache the buckets of
-- (seg.level, seg.zone); cchar is the character record they belong to.
local seg = { g = 0, key = "w", zone = nil, level = 1, frac = 0 }
local sync = { valid = false, restored = false, total = 0, levelPlayed = nil, level = 0, g = 0, levelValid = false }
local b = { level = 0, xp = 0, max = 0, rest = 0, valid = false }   -- current XP baseline
local delta                                                          -- see NewDelta()

Tracker.sync = sync
Tracker.b = b
Tracker.b0 = nil                 -- first valid baseline of this load (gap XP)
Tracker.delta = nil
Tracker.recLevel = nil           -- level at the previous reconcile point (L0 of 5.15)
Tracker.gapXPPending = false     -- xpSnap not consumed by a reconcile yet
Tracker.pendingReconcile = false -- a reconcile waits for the XP baseline
Tracker.loadLevel = nil
Tracker.loadStartG = nil
Tracker.loadKind = nil
Tracker.levelUpG = nil
Tracker.lastLevelSyncG = nil

local lastAfk, lastResting, lastTaxi, lastIsCity = false, false, false, false
local lastInInstance = false
-- Max level: realMax = the client's own (Util.IsMaxLevel); capped = a server level cap
-- detected at the current level (char.capLevel == seg.level). Tracker.IsMax() = either.
local realMax, capped = false, false

-- Time without XP (R1). char.noXP counts the non-AFK seconds since the last XP gain
-- (persisted); past C.XP_STALL the character is stalled. While stalled or capped the
-- time no longer feeds the EMA and goes to the stalled maps (xs) with this carry.
local XP_STALL = C.XP_STALL
local xsFrac = 0

-- Server level cap (R2): kills without XP. A miss = a combat ended on a dead, eligible
-- target (seen alive during that combat) with no XP gain, no kill marker and the same
-- XP as when it started. C.CAP_MISSES misses in a row at one level set char.capLevel.
-- One table (fields only: no allocation after load).
local cap = {
  misses = 0, missLevel = 0,   -- kills without XP in a row, and their level
  inCombat = false,            -- between PLAYER_REGEN_DISABLED and _ENABLED
  xp = false,                  -- an XP gain or a kill marker since the combat started
  lvl0 = nil, xp0 = 0,         -- level and XP read when it started (lvl0 nil: unreadable)
  tgtOK = false, tgtLevel = 0, -- the current target qualifies (seen alive); its level
}

-- True once life has met the server /played in this load (a reconcile ran, or a
-- /reload continued a load that had): only then does the logout save describe a
-- point where life == server, so only then may it write an XP snapshot.
local anchored = false

-- Segments dropped by Flush (freeze > C.MAX_SEGMENT) since the last reconcile:
-- total seconds and the last dropped (key, zone, level), re-added as such (5.15).
local dropSecs, dropKey, dropZone, dropLevel = 0, nil, nil, nil

-- Zone caches (invalidated on "cities" changes and DB swaps). nameOf is kept:
-- localized names do not depend on the city classification. zoneOf[mapID] is
-- false for an unresolved map (continent, world: see ResolveMiss).
local zoneOf, capOf, instKey, nameKey, nameOf = {}, {}, {}, {}, {}
local aboveOf = {}     -- mapID -> true when above the zone level (repair of old records only)

-- Unresolved maps (5.5, feedback F4): while GetBestMapForUnit gives a continent
-- (first seconds after login, after a loading screen) no zone bucket is created.
-- The seconds, and the zone part of XP gains, are held and credited to the first
-- zone resolved afterwards, with the state of that moment. After C.ZONE_HOLD_MAX
-- seconds the zone-text key ("n" .. GetRealZoneText()) is used instead (capped).
local HOLD_OFF, HOLD_ON, HOLD_CAPPED = 0, 1, 2
local holdState, holdSecs, holdStartG, holdXP = HOLD_OFF, 0, 0, 0
local unresolvedNow = false   -- the last state computation met an unresolved map

-- XP chain state
local pendingQuest, questExpiry, poolDrop, poolExpiry = 0, 0, 0, 0
local batchScheduled, retryArmed, regenRegistered = false, false, false
local baselineTries, baselineScheduled, baselineDone = 0, false, false

-- Kill detection (char.lastKill and char.killRing, mobs to the next level).
-- CHAT_MSG_COMBAT_XP_GAIN is only an occurrence marker: its text is never read (secret
-- in instances on 12.x clients, and parsing it is not allowed, SPEC 2.3). Markers and
-- quest turn-ins form a balance: each marker +1, each quest reward -1 (its own "You
-- gain..." marker is due), so the kills of a batch = the positive balance (one ring
-- entry each). A non-quest gain without a marker waits up to C.KILL_WINDOW for a late
-- one; it is also accepted without any marker when the client never sent one in this
-- load or inside an instance, unless a subzone change (discovery XP) came within
-- C.DISCOVERY_WINDOW of it.
local markSeen = false                  -- a marker arrived in this load
local marks, marksG = 0, 0              -- marker balance and the time of its last change
local xpDeferred = false                -- the XP read waits for the end of combat (secret):
                                        -- markers accumulate until it runs (no expiry)
local pendXP, pendLevel, pendG, pendFallback = 0, 0, 0, false   -- a gain awaiting its marker
local zoneEvtG = -1e9                   -- GetTime of the last subzone change

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function SumAll(s)
  if type(s) ~= "table" then return 0 end
  local t = 0
  for i = 1, N_STATE do
    local v = s[STATE_KEYS[i]]
    if v then t = t + v end
  end
  return t
end

local function SumTracked(s)
  if type(s) ~= "table" then return 0 end
  local t = 0
  for i = 1, N_TRACKED do
    local v = s[TRACKED_KEYS[i]]
    if v then t = t + v end
  end
  return t
end

local function Round3(x)
  return math_floor(x * 1000 + 0.5) / 1000
end

-- Adds x to a numeric field of t.
local function Add(t, f, x)
  t[f] = (t[f] or 0) + x
end

-- Continent, world and cosmic maps are above the zone level: never zone keys, except
-- a continent-typed map without any zone below it: an island played as a zone (Zephras
-- Isle 2521 on Forever, where GetBestMapForUnit returns it; Kalimdor and the Eastern
-- Kingdoms have dozens of zones). Cache misses only (the C_Map calls allocate).
local function IsAboveZone(mapID, mt)
  if mt == MT_WORLD or mt == MT_COSMIC then return true end
  if mt ~= MT_CONTINENT then return false end
  local getChildren = C_Map.GetMapChildrenInfo
  if not getChildren then return true end
  local kids = getChildren(mapID, MT_ZONE, true)
  return not (type(kids) == "table" and kids[1] == nil)
end

-- Deterministic order for mixed zone keys: numbers first, then strings.
local function KeyLess(x, y)
  local tx, ty = type(x), type(y)
  if tx ~= ty then return tx == "number" end
  return x < y
end

local function GetTau()
  local s = ns.settings
  local tau = s and s.rateTau
  if type(tau) ~= "number" or tau < 60 then tau = 3600 end
  return tau
end

local function Send(msg, a1, a2, a3)
  local send = ns.SendMessage
  if send then send(msg, a1, a2, a3) end
end

-- owner = a character record or the delta (both have .levels / .zones)
local function GetLevel(owner, lvl)
  local levels = owner.levels
  local lb = levels[lvl]
  if lb == nil then
    lb = ns.Core.NewLevel()
    levels[lvl] = lb
  else
    if type(lb.s) ~= "table" then lb.s = {} end
    if type(lb.z) ~= "table" then lb.z = {} end
  end
  return lb
end

local function GetSub(map, key)
  local zb = map[key]
  if zb == nil then
    zb = ns.Core.NewZone()
    map[key] = zb
  elseif type(zb.s) ~= "table" then
    zb.s = {}
  end
  return zb
end

local function StoreName(zb, key)
  local nm = nameOf[key]
  if nm ~= nil and zb.name ~= nm then zb.name = nm end
end

local function CharZone(char, key)
  local zb = GetSub(char.zones, key)
  StoreName(zb, key)
  return zb
end

local function NewDelta()
  delta = { life = ns.Core.NewLife(), levels = {}, zones = {} }
  Tracker.delta = delta
end

local function InvalidateCaches()
  seg.cchar = nil
  seg.lb, seg.lz, seg.zb = nil, nil, nil
  seg.dlb, seg.dlz, seg.dzb = nil, nil, nil
end

local function FillCaches(char)
  local lvl, zone = seg.level, seg.zone
  local lb = GetLevel(char, lvl)
  seg.lb = lb
  seg.lz = GetSub(lb.z, zone)
  seg.zb = CharZone(char, zone)
  local dlb = GetLevel(delta, lvl)
  seg.dlb = dlb
  seg.dlz = GetSub(dlb.z, zone)
  seg.dzb = GetSub(delta.zones, zone)
  seg.cchar = char
end

local function RefreshMax()
  realMax = Util.IsMaxLevel() and true or false
end

-- capped follows char.capLevel and the current level.
local function SyncCap()
  local char = ns.char
  local capLevel = char and char.capLevel
  capped = type(capLevel) == "number" and capLevel == seg.level
end

---------------------------------------------------------------------------
-- Credit and EMA decay (5.3, 5.10)
---------------------------------------------------------------------------

-- Adds n seconds of state k in (zone, lvl): life, level, level-zone, zone,
-- session and the same paths of the delta. No table is created except on the
-- first entry into a level or zone.
local function Credit(n, k, zone, lvl)
  if ns.readOnly then return end
  local char = ns.char
  if not char or not delta or zone == nil then return end
  local lb, lz, zb, dlb, dlz, dzb
  if lvl == seg.level and zone == seg.zone then
    if seg.cchar ~= char or not seg.lb then FillCaches(char) end
    lb, lz, zb, dlb, dlz, dzb = seg.lb, seg.lz, seg.zb, seg.dlb, seg.dlz, seg.dzb
  else
    lb = GetLevel(char, lvl)
    lz = GetSub(lb.z, zone)
    zb = CharZone(char, zone)
    dlb = GetLevel(delta, lvl)
    dlz = GetSub(dlb.z, zone)
    dzb = GetSub(delta.zones, zone)
  end
  Bump(char.life.s, k, n)
  Bump(lb.s, k, n)
  Bump(lz.s, k, n)
  Bump(zb.s, k, n)
  local sess = ns.session
  if sess and sess.s then Bump(sess.s, k, n) end
  Bump(delta.life.s, k, n)
  Bump(dlb.s, k, n)
  Bump(dlz.s, k, n)
  Bump(dzb.s, k, n)
end

-- Decays the EMA of every mask that includes state k over dt seconds.
local function DecayEma(dt, k)
  local char = ns.char
  local ema = char and char.ema
  if not ema then return end
  local tau = GetTau()
  local f = math_exp(-dt / tau)
  local g = tau * (1 - f)
  for m = 0, 7 do
    if INCLUDED[m][k] then
      local e = ema[m + 1]
      if e then
        e.a = e.a * f
        e.r = e.r * f
        e.q = e.q * f
        e.d = e.d * f + g
      end
    end
  end
end

---------------------------------------------------------------------------
-- Time without XP (R1): stall guard, stalled maps (xs)
---------------------------------------------------------------------------

local function IsStalled(char)
  local n = char.noXP
  return type(n) == "number" and n > XP_STALL
end

-- The character's time is withheld from the rate: stalled, or at a detected server cap.
local function Withheld(char)
  return not realMax and (capped or IsStalled(char))
end

-- The stalled maps of the current level (life.xs, levels[L].xs, of the record and of
-- the delta) are prepared with every tracked key at 0 when that level becomes current,
-- so that the first stalled second allocates nothing on the tick path (6.2). Zero
-- entries are removed when the level is left and at logout (StripXS): nothing is saved
-- for a character that never stalled.
local function PrepareXS(bucket)
  local xs = bucket.xs
  if type(xs) ~= "table" then
    xs = {}
    bucket.xs = xs
  end
  for i = 1, N_TRACKED do
    local k = TRACKED_KEYS[i]
    if xs[k] == nil then xs[k] = 0 end
  end
end

local function StripXS(bucket)
  local xs = type(bucket) == "table" and bucket.xs
  if type(xs) ~= "table" then return end
  local any = false
  for k, v in pairs(xs) do
    if v == 0 then xs[k] = nil else any = true end
  end
  if not any then bucket.xs = nil end
end

local function PrepareStallMaps()
  local char = ns.char
  if ns.readOnly or not char or not delta or type(char.life) ~= "table" then return end
  PrepareXS(char.life)
  PrepareXS(GetLevel(char, seg.level))
  PrepareXS(delta.life)
  PrepareXS(GetLevel(delta, seg.level))
end

-- Adds n seconds of state k at level lvl to the stalled maps of owner (a record or
-- the delta): life.xs and levels[lvl].xs, shaped like `s` (created when missing).
local function BumpXS(owner, lvl, k, n)
  local life = owner.life
  local xs = life.xs
  if xs == nil then
    xs = {}
    life.xs = xs
  end
  Bump(xs, k, n)
  local lb = GetLevel(owner, lvl)
  xs = lb.xs
  if xs == nil then
    xs = {}
    lb.xs = xs
  end
  Bump(xs, k, n)
end

-- Withheld seconds (fractions carried) of state k at level lvl: record and delta.
local function StallTime(wh, k, lvl)
  local f = xsFrac + wh
  if f < 1 then
    xsFrac = f
    return
  end
  local n = math_floor(f)
  xsFrac = f - n
  local char = ns.char
  if not char or not delta then return end
  BumpXS(char, lvl, k, n)
  BumpXS(delta, lvl, k, n)
end

-- Start of a stall or of a cap: a level without any XP so far holds nothing but time
-- without XP (a character that reached the cap on its level-up, or was installed at
-- it), so all its time joins the stalled maps. A level with XP keeps its time up to
-- now (only the time from now on is withheld). withDelta: also in the delta (moves
-- made during this load, replayed by a late SavedVariables swap).
local function MoveLevelToStall(char, lvl, withDelta)
  local lb = char.levels and char.levels[lvl]
  if type(lb) ~= "table" or (lb.xp or 0) ~= 0 or type(lb.s) ~= "table" then return end
  for i = 1, N_TRACKED do
    local k = TRACKED_KEYS[i]
    local xs = lb.xs
    local v = math_floor((lb.s[k] or 0) - ((xs and xs[k]) or 0))
    if v > 0 then
      BumpXS(char, lvl, k, v)
      if withDelta and delta then BumpXS(delta, lvl, k, v) end
    end
  end
end

-- Records saved before the stall guard have no noXP. A current level without any XP
-- is all time without XP (e.g. the Forever beta character installed at the level 20
-- cap): its non-AFK time starts the count and, past C.XP_STALL, it is stalled time.
-- A level with XP starts the count at 0 (the time of its last gain is unknown).
local function MigrateNoXP(char, lvl)
  local n = 0
  local lb = char.levels and char.levels[lvl]
  if not realMax and type(lb) == "table" and (lb.xp or 0) == 0 and type(lb.s) == "table" then
    for i = 1, N_TRACKED do
      local k = TRACKED_KEYS[i]
      if not C.IS_AFK[k] then n = n + (lb.s[k] or 0) end
    end
  end
  char.noXP = n
  if n > XP_STALL then MoveLevelToStall(char, lvl, false) end
end

-- dt seconds of state k: the EMA decays, except for the part withheld (stalled or
-- capped), which is returned for the stalled maps. Counts the time without XP.
local function AdvanceRate(dt, k)
  local char = ns.char
  if not char or realMax then
    DecayEma(dt, k)
    return 0
  end
  local nx = char.noXP
  if type(nx) ~= "number" then nx = 0 end
  local wh = 0
  if capped or nx > XP_STALL then wh = dt end
  if k ~= "u" and not C.IS_AFK[k] then   -- non-AFK time counts as time without XP
    local nn = nx + dt
    char.noXP = nn
    if wh == 0 and nn > XP_STALL then
      -- the stall starts inside this segment: its end is withheld
      wh = nn - XP_STALL
      if wh > dt then wh = dt end
      MoveLevelToStall(char, seg.level, true)
      Util.Debug("No XP for %d s of play: XP per hour frozen until the next XP gain.", XP_STALL)
    end
  end
  if wh < dt then DecayEma(dt - wh, k) end
  return wh
end

-- An XP gain ended a stall or a cap: an EMA that remembers less XP than this gain holds
-- nothing but time without XP (a character that sat at the cap since its install, or a
-- record from before the stall guard). It restarts, so that this time does not dilute
-- the first gains (R1); the fallback chain (5.11) covers its warm-up.
local function RestartEmptyEma(char, gain)
  local ema = char.ema
  if type(ema) ~= "table" then return end
  for m = 1, 8 do
    local e = ema[m]
    if e and e.a + e.r + e.q < gain then e.a, e.r, e.q, e.d = 0, 0, 0, 0 end
  end
end

-- Any XP gain: the stall and the server cap are over, the miss count restarts.
local function OnXPGained(char)
  cap.xp = true
  cap.misses = 0
  xsFrac = 0
  char.noXP = 0
  if char.capLevel ~= nil then
    char.capLevel = nil
    Util.Debug("XP gained: the level cap is over.")
  end
  capped = false
end

function Tracker.Flush(now)
  if not started then return end
  if now == nil then now = GetTime() end
  local dt = now - seg.g
  seg.g = now
  if dt <= 0 then return end
  if dt > C.MAX_SEGMENT then
    local n = math_floor(dt)
    dropSecs = dropSecs + n
    dropKey, dropZone, dropLevel = seg.key, seg.zone, seg.level
    Util.Debug("Dropped a %d s segment (freeze or sleep); the next server sync re-adds it.", n)
    return
  end
  if holdState == HOLD_ON then
    holdSecs = holdSecs + dt   -- unresolved map: credited (EMA included) on release
    return
  end
  local wh = 0
  if not ns.readOnly then wh = AdvanceRate(dt, seg.key) end
  local frac = seg.frac + dt
  if frac >= 1 then
    local n = math_floor(frac)
    seg.frac = frac - n
    Credit(n, seg.key, seg.zone, seg.level)
  else
    seg.frac = frac
  end
  if wh > 0 then StallTime(wh, seg.key, seg.level) end
end

-- Credits the held seconds (EMA decay included) and the held zone XP to the
-- current segment: seg.key, seg.zone (resolved), seg.level.
local function ReleaseHold()
  local held, gx = holdSecs, holdXP
  holdSecs, holdXP = 0, 0
  local zone = seg.zone
  if zone == nil or ns.readOnly then return end
  if held > 0 then
    local wh = AdvanceRate(held, seg.key)
    local frac = seg.frac + held
    local n = math_floor(frac)
    seg.frac = frac - n
    if n >= 1 then Credit(n, seg.key, zone, seg.level) end
    if wh > 0 then StallTime(wh, seg.key, seg.level) end
  end
  local char = ns.char
  if gx > 0 and char and delta then
    Add(CharZone(char, zone), "xp", gx)
    Add(GetSub(GetLevel(char, seg.level).z, zone), "xp", gx)
    Add(GetSub(delta.zones, zone), "xp", gx)
    Add(GetSub(GetLevel(delta, seg.level).z, zone), "xp", gx)
  end
end

---------------------------------------------------------------------------
-- Zones (5.5) and state (5.4)
---------------------------------------------------------------------------

local function IsCityMap(id)
  local db = ns.db
  local cities = db and db.cities
  local o = cities and cities[id]
  if o ~= nil then return o == true end
  return C.CAPITALS[id] == true
end

-- Structural resolution of a map (cache miss only: GetMapInfo allocates).
-- Returns zoneKey, capKey; zoneKey is false for an unresolved map: a continent,
-- world or cosmic map with no Zone / Dungeon / capital below it in the chain.
local function ResolveMiss(mapID)
  local id, depth = mapID, 0
  local zoneKey, capKey, firstName, firstType, zoneName, capName
  while id and id ~= 0 and depth < C.MAX_ZONE_DEPTH do
    local info = C_Map.GetMapInfo(id)
    if not info then break end
    if depth == 0 then firstName, firstType = info.name, info.mapType end
    if capKey == nil and IsCityMap(id) then
      capKey, capName = id, info.name
    end
    local mt = info.mapType
    if mt == MT_ZONE or mt == MT_DUNGEON then
      zoneKey, zoneName = id, info.name
      local parent = info.parentMapID
      if mt == MT_DUNGEON and capKey == nil and parent and parent ~= 0 and IsCityMap(parent) then
        capKey = parent
        local pinfo = C_Map.GetMapInfo(parent)
        capName = pinfo and pinfo.name
      end
      break
    end
    id = info.parentMapID
    depth = depth + 1
  end
  if zoneKey == nil then
    if IsAboveZone(mapID, firstType) then
      -- e.g. Kalimdor for the first seconds after login: never a zone key (F4)
      zoneOf[mapID] = false
      capOf[mapID] = false
      return false, nil
    end
    zoneKey, zoneName = mapID, firstName   -- leaf map (island typed Continent, orphan, micro)
  end
  zoneOf[mapID] = zoneKey
  capOf[mapID] = capKey or false
  if type(zoneName) == "string" and zoneName ~= "" then nameOf[zoneKey] = zoneName end
  if capKey and type(capName) == "string" and capName ~= "" then nameOf[capKey] = capName end
  return zoneKey, capKey
end

-- Returns zoneKey, isCity, capKey. The structural part is cached per mapID;
-- the instance test is applied on every call (never a city inside an instance).
-- An unresolved map (continent, world) returns nil, false, nil.
function Tracker.ResolveZone(mapID, inInstance)
  local zoneKey = zoneOf[mapID]
  local capKey
  if zoneKey == nil then
    zoneKey, capKey = ResolveMiss(mapID)
  else
    capKey = capOf[mapID]
  end
  if zoneKey == false then return nil, false, nil end
  if inInstance then return zoneKey, false, nil end
  if capKey then return capKey, true, capKey end
  return zoneKey, false, nil
end
local ResolveZone = Tracker.ResolveZone

local function InstanceKey()
  local id = select(8, GetInstanceInfo())
  if type(id) ~= "number" then id = 0 end
  local k = instKey[id]
  if k == nil then
    k = "i" .. math_floor(id)
    instKey[id] = k
    local name = GetInstanceInfo()
    if type(name) == "string" and name ~= "" then nameOf[k] = name end
  end
  return k
end

local function NameKey()
  local text = GetRealZoneText and GetRealZoneText()
  if type(text) ~= "string" then text = "" end
  local k = nameKey[text]
  if k == nil then
    k = "n" .. text
    nameKey[text] = k
    if text ~= "" then nameOf[k] = text end
  end
  return k
end

function Tracker.InvalidateZoneCache()
  wipe(zoneOf)
  wipe(capOf)
end

-- Returns key, zoneKey, mapID, isCity. Secret or failed reads keep the last
-- known value (the secret test happens inside Util.SafeRead, before any
-- boolean test). C_ChatInfo.InChatMessagingLockdown is deliberately ignored.
-- zoneKey is nil on an unresolved map (continent) until the hold is capped.
local function Compute(now)
  local ok, v = SafeRead(UnitIsAFK, "player")
  if ok then lastAfk = (v == true) end
  ok, v = SafeRead(IsResting)
  if ok then lastResting = (v == true) end
  ok, v = SafeRead(UnitOnTaxi, "player")
  if ok then lastTaxi = (v == true) end

  local mapID = C_Map.GetBestMapForUnit("player")
  if type(mapID) ~= "number" then mapID = nil end
  local inst, itype = IsInInstance()
  local inInstance = inst and true or false
  lastInInstance = inInstance
  local zoneKey, isCity
  unresolvedNow = false
  if mapID == nil then
    if inInstance then
      zoneKey, isCity = InstanceKey(), false
    else
      zoneKey, isCity = seg.zone, lastIsCity
      if zoneKey == nil then zoneKey, isCity = NameKey(), false end
    end
  else
    zoneKey, isCity = ResolveZone(mapID, inInstance)
    if zoneKey == nil then
      if inInstance then
        zoneKey, isCity = InstanceKey(), false
      else
        -- unresolved map (continent): held by Reeval, zone text after the cap
        unresolvedNow = true
        isCity = lastIsCity
        if holdState == HOLD_CAPPED or (holdState == HOLD_ON and now - holdStartG >= C.ZONE_HOLD_MAX) then
          zoneKey, isCity = NameKey(), false
        end
      end
    end
  end
  lastIsCity = isCity

  -- inside an instance: its kind (dungeon, raid, PvP), never inn or city
  local place
  if lastTaxi then
    place = "t"
  elseif inInstance then
    place = INSTANCE_KIND[itype] or "w"
  elseif isCity then
    place = "c"
  elseif lastResting then
    place = "i"
  else
    place = "w"
  end
  return KEY[place][lastAfk], zoneKey, mapID, isCity
end

function Tracker.ComputeState()
  return Compute(GetTime())
end
local ComputeState = Tracker.ComputeState

---------------------------------------------------------------------------
-- Level-up (5.8) and zone pruning (4.4)
---------------------------------------------------------------------------

-- Keeps the C.LEVEL_ZONES_MAX largest zones of a completed level and merges the
-- others into "o".
local function PruneLevelZones(lb)
  local z = lb and lb.z
  if type(z) ~= "table" then return end
  local n = 0
  for k in pairs(z) do
    if k ~= "o" then n = n + 1 end
  end
  if n <= C.LEVEL_ZONES_MAX then return end
  local list = {}
  for k, zb in pairs(z) do
    if k ~= "o" then list[#list + 1] = { k = k, raw = SumAll(zb.s) } end
  end
  table_sort(list, function(x, y)
    if x.raw ~= y.raw then return x.raw > y.raw end
    return KeyLess(x.k, y.k)
  end)
  local o = z.o
  if type(o) ~= "table" then o = ns.Core.NewZone() end
  if type(o.s) ~= "table" then o.s = {} end
  for i = C.LEVEL_ZONES_MAX + 1, #list do
    local k = list[i].k
    local zb = z[k]
    if type(zb.s) == "table" then
      for sk, v in pairs(zb.s) do
        if type(v) == "number" then Bump(o.s, sk, v) end
      end
    end
    o.xp = (o.xp or 0) + (zb.xp or 0)
    z[k] = nil
  end
  z.o = o
end

-- At logout: bound char.zones to C.ZONES_MAX (city zones and the current zone
-- are never pruned, see invariant 5.17).
local function PruneZones(char)
  local zones = char.zones
  if type(zones) ~= "table" then return end
  local n = 0
  for _ in pairs(zones) do n = n + 1 end
  if n <= C.ZONES_MAX then return end
  local cand = {}
  for k, zb in pairs(zones) do
    local s = zb.s
    local raw = SumAll(s)
    local city = type(s) == "table" and ((s.c or 0) + (s.C or 0)) or 0
    if raw < C.ZONE_PRUNE_MIN and city == 0 and k ~= seg.zone then
      cand[#cand + 1] = { k = k, raw = raw }
    end
  end
  table_sort(cand, function(x, y)
    if x.raw ~= y.raw then return x.raw < y.raw end
    return KeyLess(x.k, y.k)
  end)
  local i = 1
  while n > C.ZONES_MAX and cand[i] do
    zones[cand[i].k] = nil
    n = n - 1
    i = i + 1
  end
end

local ScheduleBatch   -- defined with the XP chain

-- Idempotent: only the first call for a given level does anything.
function Tracker.OnLevelUp(newLevel)
  if not started or type(newLevel) ~= "number" or newLevel <= seg.level then return end
  if ns.readOnly then
    local old = seg.level
    seg.level = newLevel
    InvalidateCaches()
    RefreshMax()
    SyncCap()
    Send("LEVEL_UP", newLevel, old)
    return
  end
  Tracker.Flush(GetTime())
  local char = ns.char
  local old = seg.level
  local nowE, nowG = time(), GetTime()
  local ob = GetLevel(char, old)
  if not ob.t1 then ob.t1 = nowE end
  local lb = GetLevel(char, newLevel)   -- never replaces an existing record
  if not lb.t0 then lb.t0 = nowE end
  if sync.valid then
    local est = math_floor(sync.total + (nowG - sync.g) + 0.5)
    if lb.srvStart == nil then lb.srvStart = est; lb.srvStartEst = true end
    if ob.srvEnd == nil then ob.srvEnd = est; ob.srvEndEst = true end
  end
  seg.level = newLevel
  char.level = newLevel
  Tracker.levelUpG = nowG
  InvalidateCaches()
  PruneLevelZones(ob)
  RefreshMax()
  -- a new level: a cap detected at the old one is over, the miss count restarts
  if char.capLevel ~= nil and char.capLevel ~= newLevel then char.capLevel = nil end
  cap.misses = 0
  SyncCap()
  StripXS(ob)
  StripXS(delta.levels[old])
  PrepareStallMaps()
  Send("LEVEL_UP", newLevel, old)
  ScheduleBatch()
end

---------------------------------------------------------------------------
-- Kills: char.lastKill = { xp, level, at }, base XP of the last mob killed (shown);
-- char.killRing = { xp, ... }, base XP of the last C.KILL_RING mobs killed, oldest
-- first (their average gives the mobs to go, Stats.KillsToLevel)
---------------------------------------------------------------------------

-- Kills recorded in this load (capped at C.KILL_RING): the newest entries of
-- char.killRing that a late SavedVariables swap carries over (ReplayDelta). A field,
-- not a local: the main chunk is at the Lua 5.1 limit of 200 locals.
Tracker.loadKills = 0

-- Stores the base XP (rested bonus excluded) of `count` kills (default 1) of xp each,
-- made at level lvl. Both tables are created once; later kills only overwrite the
-- fields of lastKill and shift the ring (no allocation once it holds C.KILL_RING).
local function CommitKill(xp, lvl, count)
  local char = ns.char
  if ns.readOnly or not char then return false end
  xp = math_floor(xp + 0.5)
  if xp <= 0 then return false end
  local lk = char.lastKill
  if type(lk) ~= "table" then
    lk = {}
    char.lastKill = lk
  end
  lk.xp, lk.level, lk.at = xp, lvl, time()
  local size = C.KILL_RING
  local ring = char.killRing
  if type(ring) ~= "table" then
    ring = {}
    char.killRing = ring
  end
  count = math_floor(count or 1)
  if count < 1 then count = 1 elseif count > size then count = size end
  for _ = 1, count do
    while #ring >= size do table_remove(ring, 1) end
    ring[#ring + 1] = xp
  end
  count = Tracker.loadKills + count
  Tracker.loadKills = count > size and size or count
  return true
end

-- A subzone change within C.DISCOVERY_WINDOW of g, before or after it.
local function NearZoneChange(g)
  local d = g - zoneEvtG
  if d < 0 then d = -d end
  return d <= C.DISCOVERY_WINDOW
end

-- Decides the gain still waiting for its marker: kept only when accepted without
-- one (fallback) and away from a subzone change. Returns true when it was stored.
local function SettlePending()
  if pendXP <= 0 then return false end
  local ok = false
  if pendFallback and not NearZoneChange(pendG) then ok = CommitKill(pendXP, pendLevel) end
  pendXP = 0
  return ok
end

-- A processed non-quest gain: a = its base mob XP, lvl = the level it was made at.
-- deferred = the gain was read after combat (secret values): it may merge several
-- kills, so it is only recorded with its markers (their count divides it).
local function OnKillGain(a, lvl, now, deferred)
  SettlePending()
  if not deferred and now - marksG > C.KILL_WINDOW then marks = 0 end
  if a <= 0 then return end
  if marks >= 1 then
    CommitKill(a / marks, lvl, marks)   -- several kills in one batch (area damage): per kill
    marks = 0
    return
  end
  if deferred then return end    -- an unknown number of kills: nothing recorded
  pendXP, pendLevel, pendG = a, lvl, now
  pendFallback = (not markSeen) or lastInInstance
end

-- CHAT_MSG_COMBAT_XP_GAIN: counted, never read.
local function OnCombatXP()
  markSeen = true
  cap.xp = true                  -- a kill with XP in this combat: not a miss (server cap)
  local now = GetTime()
  if not xpDeferred and now - marksG > C.KILL_WINDOW then marks = 0 end
  if marks < 0 then
    marks = marks + 1            -- the marker of a quest reward
    marksG = now
    return
  end
  if pendXP > 0 and now - pendG <= C.KILL_WINDOW then
    if NearZoneChange(pendG) then
      pendXP = 0                 -- discovery XP waiting: this marker is the next gain's
    else
      local ok = CommitKill(pendXP, pendLevel)   -- the late marker of the waiting gain
      pendXP = 0
      if ok then Send("XP_CHANGED") end
      return
    end
  end
  marks = marks + 1
  marksG = now
end

---------------------------------------------------------------------------
-- Reevaluate / Tick (5.2, 5.3)
---------------------------------------------------------------------------

local function Reeval(now)
  if not started then return end
  Tracker.Flush(now)
  local key, zone = Compute(now)
  local lvl = UnitLevel("player")
  if type(lvl) == "number" and lvl > seg.level then Tracker.OnLevelUp(lvl) end
  if key ~= seg.key then
    local old = seg.key
    seg.key = key
    Send("STATE_CHANGED", key, old)
  end
  if zone == nil then
    -- unresolved map: hold the seconds, keep the zone (no bucket, no message)
    if holdState == HOLD_OFF then
      holdState = HOLD_ON
      holdStartG = now
    end
    return
  end
  if zone ~= seg.zone then
    seg.zone = zone
    InvalidateCaches()
    local char = ns.char
    if not ns.readOnly and char and type(char.zones) == "table" then
      local zb = char.zones[zone]
      if zb then StoreName(zb, zone) end
    end
    Send("ZONE_KEY_CHANGED", zone)
  end
  if holdState ~= HOLD_OFF then
    if holdState == HOLD_ON then ReleaseHold() end
    holdState = unresolvedNow and HOLD_CAPPED or HOLD_OFF
  end
end

-- Held seconds still pending when the zone must be final (logout): the current
-- zone, or the zone text when none is known yet.
local function ForceRelease()
  if holdState ~= HOLD_ON then return end
  local zone = seg.zone
  if zone == nil then zone = NameKey() end
  if zone ~= seg.zone then
    seg.zone = zone
    InvalidateCaches()
  end
  ReleaseHold()
  holdState = HOLD_OFF
end

-- Old records could hold a continent as a zone (the first seconds after login
-- were credited to Kalimdor, feedback F4). Their buckets (char.zones and every
-- levels[L].z, time and XP) move into the neutral "o" bucket (an island typed
-- Continent keeps its bucket: it is a zone). Login and swap only: one GetMapInfo per
-- numeric key, cached for the session.
local function IsAboveZoneKey(k)
  if type(k) ~= "number" then return false end
  local above = aboveOf[k]
  if above == nil then
    local info = C_Map.GetMapInfo(k)
    local mt = info and info.mapType
    above = (mt ~= nil and IsAboveZone(k, mt)) and true or false
    aboveOf[k] = above
  end
  return above
end

local function MergeAboveZone(map)
  local list
  for k in pairs(map) do
    if IsAboveZoneKey(k) then
      list = list or {}
      list[#list + 1] = k
    end
  end
  if not list then return 0 end
  local o = map.o
  if type(o) ~= "table" then
    o = ns.Core.NewZone()
    map.o = o
  end
  if type(o.s) ~= "table" then o.s = {} end
  for i = 1, #list do
    local zb = map[list[i]]
    if type(zb) == "table" then
      if type(zb.s) == "table" then
        for sk, v in pairs(zb.s) do
          if type(v) == "number" then Bump(o.s, sk, v) end
        end
      end
      if type(zb.xp) == "number" then o.xp = (o.xp or 0) + zb.xp end
    end
    map[list[i]] = nil
  end
  return #list
end

local function RepairContinentZones(char)
  if ns.readOnly or type(char) ~= "table" then return end
  local n = 0
  if type(char.zones) == "table" then n = n + MergeAboveZone(char.zones) end
  if type(char.levels) == "table" then
    for _, lb in pairs(char.levels) do
      if type(lb) == "table" and type(lb.z) == "table" then n = n + MergeAboveZone(lb.z) end
    end
  end
  local last = char.last
  if type(last) == "table" and IsAboveZoneKey(last.zone) then last.zone = "o" end
  if n > 0 then Util.Debug("%d continent bucket(s) moved to the neutral zone.", n) end
end

function Tracker.Reevaluate(_reason)
  Reeval(GetTime())
end

function Tracker.Tick(now)
  if type(now) ~= "number" then now = GetTime() end
  Reeval(now)
  -- a gain that waited for its kill marker long enough (one comparison when idle)
  if pendXP > 0 and now - pendG > C.DISCOVERY_WINDOW then
    if SettlePending() then Send("XP_CHANGED") end
  end
end

---------------------------------------------------------------------------
-- Rate EMA chunk (5.10)
---------------------------------------------------------------------------

-- Feeds a chunk of time (seconds per state key) carrying a, r, q XP into the
-- 8 EMAs of char (crash gaps, replay after a late SV swap).
function Tracker.FeedChunk(char, secondsByKey, a, r, q)
  if ns.readOnly or type(char) ~= "table" or type(char.ema) ~= "table" then return end
  a, r, q = a or 0, r or 0, q or 0
  local tau = GetTau()
  for m = 0, 7 do
    local e = char.ema[m + 1]
    if e then
      local inc = INCLUDED[m]
      local dtm = 0
      if type(secondsByKey) == "table" then
        for i = 1, N_TRACKED do
          local k = TRACKED_KEYS[i]
          if inc[k] then dtm = dtm + (secondsByKey[k] or 0) end
        end
      end
      if dtm > 0 then
        local f = math_exp(-dtm / tau)
        local w = tau * (1 - f) / dtm
        e.a = e.a * f + a * w
        e.r = e.r * f + r * w
        e.q = e.q * f + q * w
        e.d = e.d * f + tau * (1 - f)
      else
        e.a = e.a + a
        e.r = e.r + r
        e.q = e.q + q
      end
    end
  end
end

---------------------------------------------------------------------------
-- Crash recovery: EstimateGap (5.15)
---------------------------------------------------------------------------

-- Splits `total` (integer) proportionally to the non-negative integer weights
-- w[1..n] (largest remainder, ties by index). Returns a new array of integers
-- summing exactly to total. All weights 0 -> equal weights.
local function LargestRemainder(total, w, n)
  local W = 0
  for i = 1, n do W = W + w[i] end
  local ww = w
  if W <= 0 then
    ww = {}
    for i = 1, n do ww[i] = 1 end
    W = n
  end
  local out, rem, idx = {}, {}, {}
  local assigned = 0
  for i = 1, n do
    local num = total * ww[i]
    local q = math_floor(num / W)
    local r = num - q * W
    if r < 0 then q = q - 1; r = r + W elseif r >= W then q = q + 1; r = r - W end
    out[i], rem[i], idx[i] = q, r, i
    assigned = assigned + q
  end
  table_sort(idx, function(x, y)
    if rem[x] ~= rem[y] then return rem[x] > rem[y] end
    return x < y
  end)
  local left = total - assigned
  local j = 1
  while left > 0 and j <= n do
    local i = idx[j]
    out[i] = out[i] + 1
    left = left - 1
    j = j + 1
  end
  return out
end
Tracker._LargestRemainder = LargestRemainder   -- exposed for tests

local function MaxOf(char, l)
  local lb = char.levels[l]
  local mx = lb and lb.max
  if type(mx) == "number" and mx > 0 then return mx end
  local db = ns.db
  mx = db and db.xpMax and db.xpMax[l]
  if type(mx) == "number" and mx > 0 then return mx end
  return nil
end

-- Target of the estimated city share (c, C) of a gap: the character's most-played
-- capital (largest c + C in char.zones, ties by KeyLess), else the last zone when it
-- is a capital, else the neutral "o" bucket. An estimate never makes an ordinary
-- zone look like a city (Top capitals, city marks) and 5.17 still holds.
local function CityZoneFor(char, zone)
  local best, bestSecs = nil, 0
  for k, zb in pairs(char.zones) do
    local s = type(zb) == "table" and zb.s
    if type(s) == "table" then
      local v = (s.c or 0) + (s.C or 0)
      if v > 0 and (best == nil or v > bestSecs or (v == bestSecs and KeyLess(k, best))) then
        best, bestSecs = k, v
      end
    end
  end
  if best ~= nil then return best end
  if type(zone) == "number" and IsCityMap(zone) then return zone end
  return "o"
end

-- Target of the estimated share of an instance kind ("d", "r" or "p" and its AFK
-- key): the last zone when it holds that kind, else the character's main zone of
-- that kind, else "o". An estimate never makes an open-world zone look like an
-- instance (most played instances, Stats.TopInstances).
local function InstZoneFor(char, zone, kind)
  local lo, up = kind, KEY[kind][true]
  local function Secs(zb)
    local s = type(zb) == "table" and zb.s
    if type(s) ~= "table" then return 0 end
    return (s[lo] or 0) + (s[up] or 0)
  end
  if zone ~= "o" and Secs(char.zones[zone]) > 0 then return zone end
  local best, bestSecs = nil, 0
  for k, zb in pairs(char.zones) do
    local v = Secs(zb)
    if v > 0 and k ~= "o" and (best == nil or v > bestSecs or (v == bestSecs and KeyLess(k, best))) then
      best, bestSecs = k, v
    end
  end
  return best or "o"
end

-- Re-adds G lost seconds (server total minus what we know) into real state
-- keys. Segments dropped in this load go back where they were played; the rest
-- is split across levels (server level time + exact XP) and by this character's
-- own historical proportions, attributed to the last known zone (city share: to
-- a capital, see CityZoneFor).
-- P1 = valid server levelPlayed of the current level, or nil.
function Tracker.EstimateGap(char, G, P1)
  if ns.readOnly or type(char) ~= "table" or type(G) ~= "number" or G <= 0 then return end
  G = math_floor(G)
  local levels = char.levels
  local L1 = seg.level
  local L0 = Tracker.recLevel or L1
  if L0 > L1 then L0 = L1 end
  local snap = char.xpSnap
  if type(snap) ~= "table" then snap = nil end
  local b0 = Tracker.b0

  -- 2. state proportions (read BEFORE crediting anything; never "u") ----
  local hist, histTotal = {}, 0
  for i = 1, N_TRACKED do
    local v = char.life.s[TRACKED_KEYS[i]] or 0
    if v < 0 then v = 0 end
    hist[i] = math_floor(v)
    histTotal = histTotal + hist[i]
  end
  local useHistory = histTotal >= C.EST_MIN_HISTORY

  -- 0. dropped segments: key, zone and level known (still estimated time) -
  local secs = {}
  local known = 0
  if dropSecs > 0 and dropZone ~= nil and dropKey ~= nil then
    known = dropSecs < G and dropSecs or G
    local lb = GetLevel(char, dropLevel)
    Bump(char.life.s, dropKey, known)
    Bump(lb.s, dropKey, known)
    Bump(GetSub(lb.z, dropZone).s, dropKey, known)
    Bump(CharZone(char, dropZone).s, dropKey, known)
    lb.est = (lb.est or 0) + known
    secs[dropKey] = known
  end
  dropSecs = 0
  local R = G - known   -- the part split below

  -- 1. level shares of R ------------------------------------------------
  local share, order = {}, {}
  if L1 == L0 then
    share[L1] = R
    order[1] = L1
  else
    local gapL1 = 0
    if P1 then
      gapL1 = Util.Clamp(P1 - SumAll(GetLevel(char, L1).s), 0, R)
      gapL1 = math_floor(gapL1)
    end
    local lv, w, knownW, nKnown = {}, {}, 0, 0
    for l = L0, L1 - 1 do lv[#lv + 1] = l end
    if not P1 then lv[#lv + 1] = L1 end
    for i = 1, #lv do
      local l = lv[i]
      local wi
      if l == L0 then
        local mx = MaxOf(char, l)
        if mx and snap and snap.level == L0 and type(snap.xp) == "number" then
          wi = math_max(0, mx - snap.xp)
        elseif mx then
          wi = math_floor(mx / 2)
        end
      elseif l == L1 then
        if b0 and b0.valid then wi = b0.xp end
      else
        wi = MaxOf(char, l)
      end
      if wi then
        wi = math_floor(wi)
        knownW, nKnown = knownW + wi, nKnown + 1
      end
      w[i] = wi or false
    end
    local mean = 1
    if nKnown > 0 then mean = math_max(1, math_floor(knownW / nKnown + 0.5)) end
    for i = 1, #lv do
      if w[i] == false then w[i] = mean end
    end
    local parts = LargestRemainder(R - gapL1, w, #lv)
    for i = 1, #lv do
      local l = lv[i]
      share[l] = parts[i]
      order[#order + 1] = l
    end
    if P1 then
      share[L1] = gapL1
      order[#order + 1] = L1
    end
    for l = L0 + 1, L1 - 1 do
      local existing = levels[l]
      local lb = GetLevel(char, l)
      if existing == nil or (SumTracked(lb.s) == 0 and (lb.xp or 0) == 0) then lb.rec = true end
    end
  end

  -- 3. zone -------------------------------------------------------------
  local zone = (type(char.last) == "table" and char.last.zone) or seg.zone
  if zone == nil then zone = NameKey() end
  local zb = CharZone(char, zone)
  local cityZone, czb   -- target of the city share, resolved on first use
  local instZone = {}   -- instance kind -> target zone of its share, resolved on first use

  -- 4. credit (not the session, not the delta) --------------------------
  for oi = 1, #order do
    local l = order[oi]
    local n = share[l] or 0
    if n > 0 then
      local lb = GetLevel(char, l)
      local lz = GetSub(lb.z, zone)
      local parts
      if useHistory then
        parts = LargestRemainder(n, hist, N_TRACKED)
      end
      for i = 1, N_TRACKED do
        local k = TRACKED_KEYS[i]
        local p
        if useHistory then p = parts[i] elseif k == "w" then p = n else p = 0 end
        if p > 0 then
          Bump(char.life.s, k, p)
          Bump(lb.s, k, p)
          local kind = IS_INSTANCE[k]
          if IS_CITY[k] then
            if cityZone == nil then
              cityZone = CityZoneFor(char, zone)
              czb = (cityZone == zone) and zb or CharZone(char, cityZone)
            end
            Bump(GetSub(lb.z, cityZone).s, k, p)
            Bump(czb.s, k, p)
          elseif kind then
            local iz = instZone[kind]
            if iz == nil then
              iz = InstZoneFor(char, zone, kind)
              instZone[kind] = iz
            end
            Bump(GetSub(lb.z, iz).s, k, p)
            Bump(CharZone(char, iz).s, k, p)
          else
            Bump(lz.s, k, p)
            Bump(zb.s, k, p)
          end
          secs[k] = (secs[k] or 0) + p
        end
      end
      lb.est = (lb.est or 0) + n
    end
  end
  char.life.est = (char.life.est or 0) + G

  -- 5. gap XP -----------------------------------------------------------
  local gx, complete = {}, false
  if Tracker.gapXPPending and snap and b0 and b0.valid and not realMax
      and type(snap.level) == "number" and type(snap.xp) == "number" then
    if b0.level == snap.level then
      gx[b0.level] = math_max(0, b0.xp - snap.xp)
      complete = true
    elseif b0.level > snap.level then
      complete = true
      local smax = (type(snap.max) == "number" and snap.max > 0 and snap.max) or MaxOf(char, snap.level)
      if smax then gx[snap.level] = math_max(0, smax - snap.xp) else complete = false end
      for l = snap.level + 1, b0.level - 1 do
        local mx = MaxOf(char, l)
        if mx then gx[l] = mx else complete = false end
      end
      gx[b0.level] = b0.xp
    end
  end
  local life = char.life
  local ratio = { math_floor(life.xa or 0), math_floor(life.xr or 0), math_floor(life.xq or 0) }
  if ratio[1] + ratio[2] + ratio[3] <= 0 then ratio[1], ratio[2], ratio[3] = 1, 0, 0 end
  local ga, gr, gq = 0, 0, 0
  for l, gxl in pairs(gx) do
    local x = math_floor(gxl)
    if x > 0 then
      local p = LargestRemainder(x, ratio, 3)
      local lb = GetLevel(char, l)
      local lz = GetSub(lb.z, zone)
      life.xp = (life.xp or 0) + x
      life.xa = (life.xa or 0) + p[1]
      life.xr = (life.xr or 0) + p[2]
      life.xq = (life.xq or 0) + p[3]
      lb.xp = (lb.xp or 0) + x
      lb.xa = (lb.xa or 0) + p[1]
      lb.xr = (lb.xr or 0) + p[2]
      lb.xq = (lb.xq or 0) + p[3]
      zb.xp = (zb.xp or 0) + x
      lz.xp = (lz.xp or 0) + x
      ga, gr, gq = ga + p[1], gr + p[2], gq + p[3]
    end
  end

  -- levels completed during the gap: prune once their time and XP are in
  for l = L0, L1 - 1 do PruneLevelZones(levels[l]) end
  for l in pairs(gx) do
    if l < L0 then PruneLevelZones(levels[l]) end
  end

  -- 6. EMA: one chunk, only when the gap XP is known and complete ---------
  -- A gap never counts as time without XP (noXP, xs). XP gained during it ends a stall
  -- or a server cap; a gap without XP while stalled or capped leaves the EMA frozen.
  local gapXP = ga + gr + gq
  local live = char == ns.char
  local held = live and Withheld(char)
  if gapXP > 0 and live then
    if held then RestartEmptyEma(char, gapXP) end
    OnXPGained(char)
    held = false
  end
  if complete and not held then Tracker.FeedChunk(char, secs, ga, gr, gq) end

  -- 7. notice, 8. debug -------------------------------------------------
  if G >= C.EST_NOTIFY_MIN then Util.Print(L.EST_RECOVERED_FMT, Fmt.Duration(G)) end
  Util.Debug("Gap %d s re-added (%d s dropped in this load): L0 %d L1 %d P1 %d, XP a %d r %d q %d (complete %s)",
    G, known, L0, L1, P1 or -1, ga, gr, gq, complete and "yes" or "no")
end

---------------------------------------------------------------------------
-- Server reconciliation (5.14)
---------------------------------------------------------------------------

-- Pre-install XP/h estimate (5.11, requirement C): XP earned before tracking
-- started / time played before it (life.s.u, the install baseline), with the
-- Classic XP table. Computed once per record, when it can be (install sync, or
-- the first XP baseline of a record synced by an older version), then persisted
-- in char.prior and never recomputed. Only on Forever / Classic Era, and only
-- when the table matches this client: UnitXPMax of the current level and every
-- size learned in db.xpMax.
--
-- v2 (R3, char.prior.v = 2): completed levels only. The time of the install level is
-- mostly idle or capped time (the Forever beta character: 8 h at the level 20 cap for
-- 58 XP), so the estimate is sum(table[1 .. base.level - 1]) over the server /played
-- when the install level began (install total - install levelPlayed). It needs that
-- level start (StartOfBaseLevel); without it the v1 formula above is used, and a v1
-- prior is recomputed once as v2 as soon as the level start is known.

-- Server /played when the install level began, or nil when not known exactly:
-- base.lp (level time at the install sync), else the level record's server start,
-- else the saved sync when it is at that level.
local function StartOfBaseLevel(char, base)
  local lvl, total = base.level, base.total
  local start
  if type(base.lp) == "number" then
    start = total - base.lp
  else
    local lb = char.levels[lvl]
    if type(lb) == "table" and type(lb.srvStart) == "number" and not lb.srvStartEst then
      start = lb.srvStart
    else
      local srv = char.srv
      if type(srv) == "table" and srv.level == lvl and not srv.loc
          and type(srv.total) == "number" and type(srv.levelPlayed) == "number" then
        start = srv.total - srv.levelPlayed
      end
    end
  end
  if type(start) ~= "number" or start ~= start or start <= 0 or start > total then return nil end
  return start
end

-- v2 estimate in XP/h, or nil when a guard fails (same guards as v1 on this time).
local function PriorV2(char, base, tbl)
  local baseLevel = base.level
  local pre = StartOfBaseLevel(char, base)
  if not pre or pre < C.PRIOR_MIN_PLAYED or pre < C.PRIOR_MIN_PER_LEVEL * (baseLevel - 1) then return nil end
  local cum = 0
  for l = 1, baseLevel - 1 do
    local v = tbl[l]
    if v == nil then return nil end
    cum = cum + v
  end
  if cum <= 0 then return nil end
  local xph = cum * 3600 / pre
  if xph > C.PRIOR_MAX_XPH then return nil end
  Util.Debug("Pre-install estimate (completed levels): %d XP in %d s, %d XP/h.", cum, pre, math_floor(xph + 0.5))
  return xph
end

local function TryPrior(char)
  if ns.readOnly or type(char) ~= "table" or not b.valid then return end
  local old = char.prior
  if old ~= nil and (type(old) ~= "table" or old.v == 2) then return end
  if not (ns.isForever or ns.isEra) then return end
  local base, life = char.base, char.life
  if type(base) ~= "table" or type(life) ~= "table" or type(life.s) ~= "table" then return end
  local baseLevel = base.level
  if type(baseLevel) ~= "number" or baseLevel < 2 or type(base.total) ~= "number" then return end
  local tbl = C.CLASSIC_XP
  local lvl = b.level
  if lvl < baseLevel or tbl[lvl] == nil or tbl[lvl] ~= b.max then return end
  local learned = ns.db and ns.db.xpMax
  if type(learned) == "table" then
    for l, v in pairs(learned) do
      local t = tbl[l]
      if t ~= nil and t ~= v then return end
    end
  end
  local xph2 = PriorV2(char, base, tbl)
  if xph2 then
    char.prior = { xph = xph2, at = time(), v = 2 }
    return
  end
  if old ~= nil then return end        -- a v1 prior stays until v2 can be computed
  local pre = life.s.u or 0
  if pre < C.PRIOR_MIN_PLAYED then return end
  -- next to no /played per level (premade or boosted character): not an XP rate
  if pre < C.PRIOR_MIN_PER_LEVEL * (baseLevel - 1) then return end
  local cum = b.xp
  for l = 1, lvl - 1 do cum = cum + tbl[l] end
  cum = cum - (life.xp or 0)   -- the XP earned since the install is tracked
  if cum <= 0 then return end
  local xph = cum * 3600 / pre
  char.prior = { xph = xph, at = time() }
  Util.Debug("Pre-install estimate: %d XP in %d s, %d XP/h.", cum, pre, math_floor(xph + 0.5))
end

local function ApplyReconcile(char, total, lp)
  local life = char.life
  local lvl = seg.level
  local lb = GetLevel(char, lvl)
  total = math_floor(total)
  -- held seconds (unresolved map) are known: they reach life and this level on release
  local held = math_floor(holdSecs)
  local G = total - SumAll(life.s) - held
  local reAdded = 0
  if char.base == nil then
    -- install baseline: all history before the first sync is untracked
    if G > C.DRIFT_TOL then
      Bump(life.s, "u", G)
      reAdded = G
    end
    if lp then
      local GL = lp - SumAll(lb.s) - held
      if GL > C.DRIFT_TOL then
        Bump(lb.s, "u", GL)
        lb.partial = true
      else
        lb.partial = nil
      end
    end
    -- lp: server time of the install level (its start = total - lp: prior v2, R3)
    char.base = { at = time(), total = total, level = lvl, lp = lp and math_floor(lp) or nil }
  else
    if G > C.DRIFT_TOL then
      Tracker.EstimateGap(char, G, lp and lp - held)
      reAdded = G
    elseif G < -C.DRIFT_TOL then
      Util.Debug("Server total is %d s below the tracked total; nothing subtracted.", -G)
    end
    if lp then
      local RL = lp - SumAll(lb.s) - held
      if RL > C.DRIFT_TOL then
        Bump(lb.s, "u", RL)
        Util.Debug("Level %d: %d s of server level time not split (untracked).", lvl, RL)
      end
    end
  end
  if lp then
    lb.srvStart = total - lp
    lb.srvStartEst = nil
    local prev = char.levels[lvl - 1]
    if prev and (prev.srvEnd == nil or prev.srvEndEst) then
      prev.srvEnd = lb.srvStart
      prev.srvEndEst = nil
    end
  end
  Tracker.gapXPPending = false
  Tracker.pendingReconcile = false
  Tracker.recLevel = lvl
  dropSecs = 0      -- included in G (re-added above, or pre-install time)
  anchored = true
  TryPrior(char)
  Send("PLAYED_SYNCED", total, lp, reAdded)
end

-- The sync projected to `now`: total, levelPlayed (nil when not valid for
-- the current level).
local function ProjectedSync(now)
  local total = math_floor(sync.total + (now - sync.g) + 0.5)
  local lp
  if sync.levelValid and sync.level == seg.level and sync.levelPlayed then
    lp = math_floor(sync.levelPlayed + (now - sync.g) + 0.5)
  end
  return total, lp
end

local ScheduleBaseline   -- defined with the XP chain

-- 5.14 step 6: wait for the XP baseline when the gap XP still needs it.
local function MustWaitForBaseline()
  return Tracker.gapXPPending and not Tracker.b0 and not realMax and not baselineDone
end

-- Runs (or re-runs) a reconcile from the current, non-restored sync.
local function ReconcileFromSync()
  if ns.readOnly or not started or not sync.valid or sync.restored or not ns.char then
    Tracker.pendingReconcile = false
    return
  end
  if MustWaitForBaseline() then
    Tracker.pendingReconcile = true
    if not baselineScheduled then ScheduleBaseline() end
    return
  end
  local now = GetTime()
  Tracker.Flush(now)
  local total, lp = ProjectedSync(now)
  ApplyReconcile(ns.char, total, lp)
end

-- True when the message being processed answers OUR /played request sent
-- after g (so it cannot carry the previous level's time).
local function IsOwnAnswerAfter(g)
  local P = ns.Played
  if not (P and P.IsPending and P.GetLastRequestG) then return false end
  if not P.IsPending() then return false end
  local rg = P.GetLastRequestG()
  return type(rg) == "number" and rg > g
end

function Tracker.ReconcileServer(total, levelPlayed)
  if not started or type(total) ~= "number" then return end
  if type(levelPlayed) ~= "number" then levelPlayed = nil end
  local now = GetTime()
  Tracker.Flush(now)
  local lvl = seg.level
  local char = ns.char
  local lb = char and type(char.levels) == "table" and char.levels[lvl]
  -- level part validity: a message requested before a level-up but received
  -- after it carries the OLD level's time (critique #5). A level time that fits
  -- in the seconds since the level-up is fresh (another addon asking at
  -- PLAYER_LEVEL_UP, as RXPGuides does) and is kept: no second request.
  local levelValid = levelPlayed ~= nil
  local lug = Tracker.levelUpG
  if levelValid and lug and now - lug < C.LEVEL_RACE_WINDOW and not IsOwnAnswerAfter(lug)
      and levelPlayed > now - lug + C.LEVEL_FRESH_SLACK then
    levelValid = false
  end
  if levelValid and lb and type(lb.t0) == "number" and levelPlayed > time() - lb.t0 + C.LEVEL_RACE_SLACK then
    levelValid = false
  end
  sync.valid = true
  sync.restored = false
  sync.total = total
  sync.g = now
  sync.level = lvl
  sync.levelValid = levelValid
  sync.levelPlayed = levelValid and levelPlayed or nil
  if levelValid then Tracker.lastLevelSyncG = now end

  if ns.readOnly or not char then
    Send("PLAYED_SYNCED", total, sync.levelPlayed, 0)
    return
  end
  local srv = char.srv
  if type(srv) ~= "table" then srv = {}; char.srv = srv end
  srv.total = total
  srv.levelPlayed = sync.levelPlayed
  srv.level = lvl
  srv.at = time()
  srv.g = now
  srv.ext = false
  srv.loc = nil     -- a real server answer (see OnLogout)
  if MustWaitForBaseline() then
    Tracker.pendingReconcile = true
    if not baselineScheduled then ScheduleBaseline() end
    return
  end
  ApplyReconcile(char, total, sync.levelPlayed)
end

---------------------------------------------------------------------------
-- XP chain (5.9)
---------------------------------------------------------------------------

-- Reads level, xp, max, rest. Returns false when a value is secret or missing.
local function ReadXP()
  local ok, v = SafeRead(UnitXP, "player")
  if not ok or type(v) ~= "number" then return false end
  local xp = v
  ok, v = SafeRead(UnitXPMax, "player")
  if not ok or type(v) ~= "number" then return false end
  local mx = v
  local rest = 0
  if GetXPExhaustion then
    local okc, r = pcall(GetXPExhaustion)
    if not okc or Util.IsSecret(r) then return false end
    if type(r) == "number" and r > 0 then rest = r end
  end
  local lvl = UnitLevel("player")
  if type(lvl) ~= "number" then return false end
  if lvl < seg.level then lvl = seg.level end
  return true, lvl, xp, mx, rest
end

local function SetB(lvl, xp, mx, rest)
  b.level, b.xp, b.max, b.rest = lvl, xp, mx, rest
  b.valid = mx > 0
end

local function RunPendingReconcile()
  if Tracker.pendingReconcile then
    Tracker.pendingReconcile = false
    ReconcileFromSync()
  end
end

-- First valid baseline of the load: b0, xpMax table, session p0, pending reconcile.
local function OnBaselineValid()
  baselineDone = true
  if not Tracker.b0 then
    Tracker.b0 = { level = b.level, xp = b.xp, max = b.max, rest = b.rest, valid = true }
  end
  if not ns.readOnly and ns.char then
    local db = ns.db
    if db and type(db.xpMax) == "table" then db.xpMax[b.level] = b.max end
    local lb = ns.char.levels[b.level]
    if lb then lb.max = b.max end
    local s = ns.session
    if s and s.p0 == nil then s.p0 = Round3(b.xp / b.max) end
    TryPrior(ns.char)   -- a record synced before its first XP read, or by an older version
  end
  RunPendingReconcile()
end

local function BaselineRead()
  baselineScheduled = false
  if not started then return end
  if b.valid then
    OnBaselineValid()
    return
  end
  local ok, lvl, xp, mx, rest = ReadXP()
  if ok and mx > 0 then
    SetB(lvl, xp, mx, rest)
    OnBaselineValid()
    Send("XP_CHANGED")
    return
  end
  baselineTries = baselineTries + 1
  if baselineTries < C.XP_BASELINE_RETRIES then
    ScheduleBaseline()
  else
    baselineDone = true   -- retries exhausted: reconcile without gap XP
    RunPendingReconcile()
  end
end

ScheduleBaseline = function()
  if baselineScheduled then return end
  baselineScheduled = true
  C_Timer.After(C.XP_BASELINE_DELAY, BaselineRead)
end

-- Writes a, r, q XP (xp = their sum) on level l of the record and of the delta,
-- and on its level-zone bucket (none while the zone is held: nil zone).
local function WriteLevelXP(char, l, zone, a, r, q)
  local g = a + r + q
  local lb, dlb = GetLevel(char, l), GetLevel(delta, l)
  Add(lb, "xp", g); Add(lb, "xa", a); Add(lb, "xr", r); Add(lb, "xq", q)
  Add(dlb, "xp", g); Add(dlb, "xa", a); Add(dlb, "xr", r); Add(dlb, "xq", q)
  if zone == nil then return end
  -- a completed level was already pruned (4.4): a merged zone stays in "o"
  local lz = lb.z[zone]
  if lz == nil and l < seg.level and type(lb.z.o) == "table" then
    lz = lb.z.o
  else
    lz = GetSub(lb.z, zone)
  end
  Add(lz, "xp", g)
  Add(GetSub(dlb.z, zone), "xp", g)
end

-- Writes a classified gain from level lOld to lNew (== lOld when no level-up):
-- lOld takes gOld, each skipped level its whole size when withMid (all sizes
-- known), lNew the rest. a, r, q are placed greedily, oldest level first
-- (q, then r, then a, up to each level's part).
local function WriteXP(lOld, lNew, gOld, gain, a, r, q, withMid)
  local char = ns.char
  local zone = seg.zone
  if holdState == HOLD_ON then zone = nil end   -- zone part held with the seconds
  local life = char.life
  Add(life, "xp", gain); Add(life, "xa", a); Add(life, "xr", r); Add(life, "xq", q)
  local dl = delta.life
  Add(dl, "xp", gain); Add(dl, "xa", a); Add(dl, "xr", r); Add(dl, "xq", q)
  if zone ~= nil then
    Add(CharZone(char, zone), "xp", gain)
    Add(GetSub(delta.zones, zone), "xp", gain)
  else
    holdXP = holdXP + gain
  end
  local sess = ns.session
  if sess then Add(sess, "xp", gain) end

  local ra, rr, rq = a, r, q
  local l, room = lOld, gOld
  while l < lNew do
    local tq = rq < room and rq or room; room = room - tq
    local tr = rr < room and rr or room; room = room - tr
    local ta = ra < room and ra or room
    WriteLevelXP(char, l, zone, ta, tr, tq)
    ra, rr, rq = ra - ta, rr - tr, rq - tq
    l = l + 1
    if withMid and l < lNew then
      room = MaxOf(char, l) or 0
    else
      l = lNew
    end
  end
  WriteLevelXP(char, lNew, zone, ra, rr, rq)

  -- the end of a stall or of a server cap (R1, R2)
  if Withheld(char) then RestartEmptyEma(char, gain) end
  OnXPGained(char)

  -- all XP goes to the numerator of every mask (5.9 step 6)
  local ema = char.ema
  if ema then
    for m = 1, 8 do
      local e = ema[m]
      if e then
        e.a = e.a + a
        e.r = e.r + r
        e.q = e.q + q
      end
    end
  end
end

local function OnRegenEnabled()
  ns.UnregisterEvent("PLAYER_REGEN_ENABLED", Tracker)
  regenRegistered = false
  Tracker.ProcessXP()
end

local RunRetry   -- pre-created retry callback

function Tracker.ProcessXP()
  if not started then return end
  RefreshMax()
  local ok, lvl, xp, mx, rest = ReadXP()
  if not ok then
    xpDeferred = true
    if not regenRegistered then
      regenRegistered = true
      ns.RegisterEvent("PLAYER_REGEN_ENABLED", Tracker, OnRegenEnabled)
    end
    return
  end
  local deferred = xpDeferred   -- this read ends a wait for the end of combat
  xpDeferred = false
  -- the chain is cut at max level (5.9 step 4.1), except for the gain that
  -- completes the level before it: that XP belongs to the previous level. A detected
  -- server cap does not cut it: its first XP gain is how the cap ends (R2).
  if ns.readOnly or (realMax and not (b.valid and lvl > b.level)) then
    SetB(lvl, xp, mx, rest)
    Send("XP_CHANGED")
    return
  end
  if not b.valid then
    SetB(lvl, xp, mx, rest)
    if b.valid then OnBaselineValid() end
    Send("XP_CHANGED")
    return
  end

  local now = GetTime()
  if pendingQuest > 0 and now > questExpiry then pendingQuest = 0 end
  if poolDrop > 0 and now > poolExpiry then poolDrop = 0 end

  local lOld = b.level
  local gain, gOld
  local withMid = false
  if lvl == lOld then
    gain = xp - b.xp
    if gain < 0 then
      -- a level-up is in flight (XP already reset, level not yet): retry once
      if not retryArmed then
        retryArmed = true
        C_Timer.After(C.XP_RETRY_DELAY, RunRetry)
        return
      end
      retryArmed = false
      SetB(lvl, xp, mx, rest)
      Send("XP_CHANGED")
      return
    end
    if b.xp == 0 and gain > 0.5 * mx then
      -- false zero at login: re-baseline, ignore the gain
      retryArmed = false
      SetB(lvl, xp, mx, rest)
      Send("XP_CHANGED")
      return
    end
    gOld = gain
  elseif lvl > lOld then
    gOld = b.max - b.xp
    if gOld < 0 then gOld = 0 end
    gain = gOld + xp
    -- skipped levels (several level-ups in one read): their whole size when
    -- every size is known (levels[l].max or db.xpMax), else nothing
    if lvl > lOld + 1 then
      local mid = 0
      for l = lOld + 1, lvl - 1 do
        local m = MaxOf(ns.char, l)
        if not m then
          mid = nil
          break
        end
        mid = mid + m
      end
      if mid then
        gain = gain + mid
        withMid = true
      end
    end
    if mx > 0 and not realMax then
      GetLevel(ns.char, lvl).max = mx
      local db = ns.db
      if db and type(db.xpMax) == "table" then db.xpMax[lvl] = mx end
    end
  else
    retryArmed = false
    SetB(lvl, xp, mx, rest)
    Send("XP_CHANGED")
    return
  end
  retryArmed = false

  local dRest = rest - b.rest
  if gain > 0 then
    local q = pendingQuest
    if q > gain then q = gain end
    pendingQuest = pendingQuest - q
    local m = gain - q
    local drop = poolDrop
    if dRest < 0 then drop = drop - dRest end
    poolDrop = 0
    local r = 0
    if drop > 0 then
      r = math_floor(drop * C.REST_BONUS / C.REST_DRAIN + 0.5)
      if r > m then r = m end
    elseif b.rest > 0 then
      -- gained while rested without a pool drop: not a mob kill
      q = q + m
      m = 0
    end
    local a = m - r
    Util.Debug("XP gain %d dRest %d q %d r %d a %d", gain, dRest, q, r, a)
    WriteXP(lOld, lvl, gOld, gain, a, r, q, withMid)
    if m > 0 then OnKillGain(a, lOld, now, deferred) end   -- mob XP, at the level it started on
  elseif dRest < 0 then
    -- UPDATE_EXHAUSTION may precede the XP update
    poolDrop = poolDrop - dRest
    poolExpiry = now + C.POOL_DROP_TTL
  end
  SetB(lvl, xp, mx, rest)
  Send("XP_CHANGED")
end

RunRetry = function() Tracker.ProcessXP() end

local function RunBatch()
  batchScheduled = false
  Tracker.ProcessXP()
end

ScheduleBatch = function()
  if batchScheduled then return end
  batchScheduled = true
  C_Timer.After(C.XP_BATCH_DELAY, RunBatch)
end

---------------------------------------------------------------------------
-- Server level cap (R2): the Forever beta caps characters (level 20, soon 30)
-- while the client still reports 60. Detected from kills that give no XP.
---------------------------------------------------------------------------

do
  -- Bus owner of the combat events (the Tracker itself owns PLAYER_REGEN_ENABLED while
  -- an XP read waits for the end of combat).
  cap.OWNER = "TruePlayed.Tracker.cap"

  -- Creature types that give no XP (localized by the client): critters, and the totems
  -- dropped by mobs (same name in enUS, frFR and deDE).
  local NO_XP_TYPE = { Critter = true, Bestiole = true, Kleintier = true, Totem = true }

  -- Group members whose level counts for the grey check (Classic: a mob grey for the
  -- highest level member of the party gives no XP to anyone, e.g. a low-level character
  -- run through a dungeon by a high-level one).
  local PARTY = { "party1", "party2", "party3", "party4" }

  -- One guarded unit API read: ok, value. ok is false when the API is missing, fails or
  -- answers a secret value: nothing is decided from it. The unit APIs are read at call
  -- time (combat start / end and target changes only).
  local function UnitRead(fn, a, b2)
    if fn == nil then return false, nil end
    local ok, v = pcall(fn, a, b2)
    if not ok or Util.IsSecret(v) then return false, nil end
    return true, v
  end

  -- Highest mob level that is grey (no XP) for a player of level pl (Classic formula).
  local function GreyLevel(pl)
    if pl <= 5 then return 0 end
    if pl <= 39 then return pl - math_floor(pl / 10) - 5 end
    if pl <= 59 then return pl - math_floor(pl / 5) - 1 end
    return pl - 9
  end
  Tracker._GreyLevel = GreyLevel   -- exposed for tests

  -- Level of the grey check: the player's, or the highest level of the party (read at
  -- the end of a fight only; an unreadable member is left out).
  local function GroupLevel(pl)
    local hl = pl
    for i = 1, #PARTY do
      local ok, v = UnitRead(UnitLevel, PARTY[i])
      if ok and type(v) == "number" and v > hl then hl = v end
    end
    return hl
  end

  -- The current target, alive: an attackable NPC that is not a player, a pet, a trivial
  -- mob, a minion, a critter or a totem. Its level is kept (-1 = skull, never grey).
  local function EvalTarget()
    cap.tgtOK = false
    local ok, v = UnitRead(UnitExists, "target")
    if not ok or not v then return end
    ok, v = UnitRead(UnitIsDead or UnitIsDeadOrGhost, "target")
    if not ok or v then return end
    ok, v = UnitRead(UnitCanAttack, "player", "target")
    if not ok or not v then return end
    ok, v = UnitRead(UnitIsPlayer, "target")
    if not ok or v then return end
    if UnitPlayerControlled then
      ok, v = UnitRead(UnitPlayerControlled, "target")
      if not ok or v then return end
    end
    ok, v = UnitRead(UnitClassification, "target")
    if not ok or v == "trivial" or v == "minus" then return end
    ok, v = UnitRead(UnitCreatureType, "target")
    if not ok or (type(v) == "string" and NO_XP_TYPE[v]) then return end
    ok, v = UnitRead(UnitLevel, "target")
    if not ok or type(v) ~= "number" or (v < 1 and v ~= -1) then return end
    cap.tgtOK, cap.tgtLevel = true, v
  end

  local function SetCap(lvl)
    local char = ns.char
    if ns.readOnly or not char or lvl ~= seg.level then return end
    Tracker.Flush(GetTime())          -- the time so far under the previous regime
    char.capLevel = lvl
    capped = true
    MoveLevelToStall(char, lvl, true)
    Util.Debug("Level cap detected at level %d: no XP from %d kills in a row.", lvl, C.CAP_MISSES)
    Send("XP_CHANGED")
  end

  function cap.OnCombatStart()
    cap.inCombat, cap.xp, cap.tgtOK, cap.lvl0 = true, false, false, nil
    if not started or ns.readOnly or realMax or capped then return end
    local ok, lvl, xp = ReadXP()
    if ok then cap.lvl0, cap.xp0 = lvl, xp end
    EvalTarget()
  end

  function cap.OnTargetChanged()
    if cap.inCombat and cap.lvl0 ~= nil then EvalTarget() end
  end

  -- A miss: the combat ended on the target seen alive and eligible, now dead and not
  -- tapped by someone else, of a level that is not grey (for the highest level of the
  -- party), with no XP gain, no kill marker and the same XP as at its start. Any
  -- unreadable answer: nothing counted.
  function cap.OnCombatEnd()
    if not cap.inCombat then return end
    cap.inCombat = false
    local eligible = cap.tgtOK
    cap.tgtOK = false
    if not eligible or cap.xp or cap.lvl0 == nil or not started or ns.readOnly or realMax or capped then return end
    local ok, v = UnitRead(UnitIsDead or UnitIsDeadOrGhost, "target")
    if not ok or not v then return end
    ok, v = UnitRead(UnitIsTapDenied, "target")
    if not ok or v then return end
    local okx, lvl, xp = ReadXP()
    if not okx or lvl ~= cap.lvl0 or xp ~= cap.xp0 then return end
    local tl = cap.tgtLevel
    if tl ~= -1 and tl <= GreyLevel(GroupLevel(lvl)) then return end
    if cap.missLevel ~= lvl then cap.misses, cap.missLevel = 0, lvl end
    cap.misses = cap.misses + 1
    Util.Debug("Kill without XP at level %d (%d of %d).", lvl, cap.misses, C.CAP_MISSES)
    if cap.misses >= C.CAP_MISSES then SetCap(lvl) end
  end
end

---------------------------------------------------------------------------
-- Sessions (5.7)
---------------------------------------------------------------------------

local function PushSession(char, s, t1, l1, p1)
  s.t1, s.l1, s.p1 = t1, l1, p1
  s.at, s.g = nil, nil
  local ring = char.sessions
  if type(ring) ~= "table" then ring = {}; char.sessions = ring end
  ring[#ring + 1] = s
  while #ring > C.SESSION_RING do table_remove(ring, 1) end
end

local function SnapProgress(snap)
  if type(snap) == "table" and type(snap.xp) == "number" and type(snap.max) == "number" and snap.max > 0 then
    return Round3(snap.xp / snap.max)
  end
  return nil
end

local function NewLiveSession()
  local s = ns.Core.NewSession()
  s.l0 = seg.level
  return s
end

function Tracker.ResetSession()
  if not started or ns.readOnly or not ns.char then return false end
  Tracker.Flush(GetTime())
  local char = ns.char
  local cur = ns.session
  if cur and SumAll(cur.s) > 0 then
    PushSession(char, cur, time(), seg.level, b.valid and Round3(b.xp / b.max) or nil)
  end
  local s = NewLiveSession()
  if b.valid then s.p0 = Round3(b.xp / b.max) end
  ns.session = s
  char.cur = s
  Send("SESSION_RESET")
  return true
end

---------------------------------------------------------------------------
-- Game events (5.6, 5.7)
---------------------------------------------------------------------------

local function OnReevaluate()
  Reeval(GetTime())
end

local function OnFlags(_, unit)
  if unit == nil or unit == "player" then Reeval(GetTime()) end
end

local function TaxiRecheck()
  Reeval(GetTime())
end

local function OnControl()
  Reeval(GetTime())
  C_Timer.After(C.TAXI_RECHECK_DELAY, TaxiRecheck)
end

local function OnXPUpdate(_, unit)
  if unit ~= nil and unit ~= "player" then return end
  Reeval(GetTime())
  ScheduleBatch()
end

local function OnExhaustion()
  ScheduleBatch()
end

local function OnQuestTurnedIn(_, _questID, xpReward)
  if type(xpReward) == "number" and xpReward > 0 then
    local now = GetTime()
    pendingQuest = pendingQuest + xpReward
    questExpiry = now + C.QUEST_PENDING_TTL
    -- its "You gain N experience" comes as a kill marker: owed to the balance
    if not xpDeferred and now - marksG > C.KILL_WINDOW then marks = 0 end
    marks = marks - 1
    marksG = now
  end
  ScheduleBatch()
end

-- Subzone changes: a discovery XP gain comes with one (kill fallback, see OnKillGain).
local function OnZoneEvent()
  local now = GetTime()
  zoneEvtG = now
  Reeval(now)
end

local function OnPlayerLevelUp(_, newLevel)
  Reeval(GetTime())
  local lvl = UnitLevel("player")
  if type(newLevel) ~= "number" then newLevel = 0 end
  if type(lvl) == "number" and lvl > newLevel then newLevel = lvl end
  Tracker.OnLevelUp(newLevel)
end

local function OnDead()
  Reeval(GetTime())
  if ns.readOnly or not ns.char or not delta then return end
  local char = ns.char
  Add(char.life, "d", 1)
  Add(GetLevel(char, seg.level), "d", 1)
  local s = ns.session
  if s then Add(s, "d", 1) end
  Add(delta.life, "d", 1)
  Add(GetLevel(delta, seg.level), "d", 1)
end

local function OnXPGainToggle()
  RefreshMax()
  Send("XP_CHANGED")
end

local function OnLeavingWorld()
  Tracker.Flush(GetTime())
end

local function OnEnteringWorld(_, isInitialLogin, isReloadingUi)
  Reeval(GetTime())
  local char = ns.char
  if not char then return end
  local ro = ns.readOnly
  if isInitialLogin then
    Tracker.loadKind = "login"
    if ro then
      ns.session = NewLiveSession()
    else
      local cur = char.cur
      if type(cur) == "table" and SumAll(cur.s) > 0 then
        PushSession(char, cur, cur.at or cur.t0, Tracker.loadLevel, SnapProgress(char.xpSnap))
      end
      local s = NewLiveSession()
      ns.session = s
      char.cur = s
    end
  elseif isReloadingUi then
    Tracker.loadKind = "reload"
    local startG = Tracker.loadStartG
    if ro then
      ns.session = NewLiveSession()
    else
      local cur = char.cur
      if type(cur) == "table" and type(cur.s) == "table" then
        ns.session = cur
      else
        local s = NewLiveSession()
        ns.session = s
        char.cur = s
      end
      -- GetTime continues across a /reload: credit the reload gap
      local last = char.last
      if type(last) == "table" and type(last.g) == "number" and last.zone ~= nil
          and INCLUDED[0][last.key] ~= nil and last.key ~= "u" and type(last.level) == "number" then
        local d = startG - last.g
        if d > 0 and d < C.RELOAD_GAP_MAX then
          local n = math_floor(d)
          if n > 0 then Credit(n, last.key, last.zone, last.level) end
          -- continuity: a snapshot written by the save right before this /reload
          -- (same epoch as char.last) comes from an anchored load, so this load
          -- is anchored too. An older snapshot still waits for its reconcile.
          local x = char.xpSnap
          if type(x) == "table" and x.at ~= nil and x.at == last.at then
            Tracker.gapXPPending = false
            anchored = true
          end
        end
      end
    end
    -- sync restore (display and request policy only, never a reconcile input)
    local srv = char.srv
    if type(srv) == "table" and not srv.loc and type(srv.g) == "number" and type(srv.total) == "number" then
      local d = startG - srv.g
      if d > 0 and d < C.RELOAD_GAP_MAX then
        sync.valid = true
        sync.restored = true
        sync.total = srv.total + d
        sync.levelValid = type(srv.levelPlayed) == "number"
        sync.levelPlayed = sync.levelValid and (srv.levelPlayed + d) or nil
        sync.level = srv.level or seg.level
        sync.g = startG
      end
    end
  end
  if isInitialLogin or isReloadingUi then
    baselineTries = 0
    ScheduleBaseline()
  end
end

local function OnLogout()
  if not started or ns.readOnly or not ns.char then return end
  local now = GetTime()
  Tracker.Flush(now)
  ForceRelease()
  local at = time()
  local char = ns.char

  local last = char.last
  if type(last) ~= "table" then last = {}; char.last = last end
  last.key, last.zone, last.level, last.g, last.at = seg.key, seg.zone, seg.level, now, at

  local cur = char.cur
  if type(cur) == "table" then cur.at = at; cur.g = now end
  char.lastSeen = at
  char.level = seg.level

  -- server snapshot extrapolated to this save (requirement D)
  local total, lp
  if sync.valid then
    total = math_floor(sync.total + (now - sync.g) + 0.5)
    if sync.levelValid and sync.level == seg.level and sync.levelPlayed then
      lp = math_floor(sync.levelPlayed + (now - sync.g) + 0.5)
    else
      local lb = char.levels[seg.level]
      if lb and type(lb.srvStart) == "number" then lp = total - lb.srvStart end
    end
  elseif type(char.srv) == "table" and type(char.srv.total) == "number" and delta then
    total = char.srv.total + SumAll(delta.life.s)
  end
  if total then
    local srv = char.srv
    if type(srv) ~= "table" then srv = {}; char.srv = srv end
    srv.total, srv.levelPlayed, srv.level, srv.at, srv.g, srv.ext = total, lp, seg.level, at, now, true
    -- loc: no server answer behind this total in this load (a local lower bound,
    -- blind to a crash gap): a /reload must not restore it as a server sync
    srv.loc = (not sync.valid) or nil
  end

  -- XP snapshot: only where life == server /played (anchored), so that the next
  -- gap's XP (b0 - xpSnap) covers exactly the next gap's time. Otherwise life
  -- still misses an older gap whose XP is unknown: drop the snapshot rather than
  -- pretend that gap earned no XP. Without a baseline (a load of a few seconds)
  -- the previous snapshot is kept: no XP was counted since it was taken.
  if b.valid and anchored then
    local x = char.xpSnap
    if type(x) ~= "table" then x = {}; char.xpSnap = x end
    x.level, x.xp, x.max, x.rest, x.at = b.level, b.xp, b.max, b.rest, at
  elseif b.valid then
    char.xpSnap = nil
  end
  if b.valid then
    local db = ns.db
    if db and type(db.xpMax) == "table" then db.xpMax[b.level] = b.max end
  end

  PruneZones(char)
  -- stalled maps: zero entries are not saved (PrepareXS)
  StripXS(char.life)
  if type(char.levels) == "table" then
    for _, lb in pairs(char.levels) do StripXS(lb) end
  end
end

local function OnSettingsChanged(_, path)
  if path == "cities" then Tracker.InvalidateZoneCache() end
end

-- Core.CheckSwap sends DB_SWAPPED after swapping ns.char (5.16); it then
-- re-applies the live sync itself through ReconcileServer (step 9).
local function OnDBSwapped()
  InvalidateCaches()
  SyncCap()
  PrepareStallMaps()
end

local EVENTS = {
  PLAYER_ENTERING_WORLD = OnEnteringWorld,
  PLAYER_LEAVING_WORLD = OnLeavingWorld,
  PLAYER_FLAGS_CHANGED = OnFlags,
  PLAYER_UPDATE_RESTING = OnReevaluate,
  ZONE_CHANGED_NEW_AREA = OnZoneEvent,
  ZONE_CHANGED = OnZoneEvent,
  ZONE_CHANGED_INDOORS = OnZoneEvent,
  PLAYER_CONTROL_LOST = OnControl,
  PLAYER_CONTROL_GAINED = OnControl,
  PLAYER_XP_UPDATE = OnXPUpdate,
  UPDATE_EXHAUSTION = OnExhaustion,
  QUEST_TURNED_IN = OnQuestTurnedIn,
  PLAYER_LEVEL_UP = OnPlayerLevelUp,
  PLAYER_DEAD = OnDead,
  DISABLE_XP_GAIN = OnXPGainToggle,
  ENABLE_XP_GAIN = OnXPGainToggle,
  CHAT_MSG_COMBAT_XP_GAIN = OnCombatXP,   -- occurrence only (kills); pcall-registered by the bus
  PLAYER_LOGOUT = OnLogout,
}
-- fixed registration order (PLAYER_ENTERING_WORLD first: Played relies on it)
local EVENT_ORDER = {
  "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_FLAGS_CHANGED", "PLAYER_UPDATE_RESTING",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_CONTROL_LOST",
  "PLAYER_CONTROL_GAINED", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "QUEST_TURNED_IN",
  "PLAYER_LEVEL_UP", "PLAYER_DEAD", "DISABLE_XP_GAIN", "ENABLE_XP_GAIN", "CHAT_MSG_COMBAT_XP_GAIN",
  "PLAYER_LOGOUT",
}

---------------------------------------------------------------------------
-- Lifecycle (5.7)
---------------------------------------------------------------------------

function Tracker.Start()
  local char = ns.char
  if not char then return end
  local ro = ns.readOnly
  local lvl = UnitLevel("player")
  if type(lvl) ~= "number" or lvl < 1 then lvl = char.level or 1 end
  Tracker.loadLevel = char.level or lvl
  Tracker.recLevel = (type(char.srv) == "table" and char.srv.level) or char.level or lvl
  if not ro then
    if type(char.levels) ~= "table" then char.levels = {} end
    if char.levels[lvl] == nil then
      local lb = ns.Core.NewLevel()
      if char.base == nil then lb.partial = true end
      char.levels[lvl] = lb
    end
    char.level = lvl
  end

  if not ro then RepairContinentZones(char) end

  seg.level = lvl
  seg.zone = nil
  holdState, holdSecs, holdStartG, holdXP = HOLD_OFF, 0, 0, 0
  local key, zone = ComputeState()
  seg.g = GetTime()
  seg.key, seg.zone, seg.frac = key, zone, 0
  if zone == nil then            -- login on an unresolved map (continent)
    holdState = HOLD_ON
    holdStartG = seg.g
  end
  Tracker.loadStartG = seg.g
  Tracker.loadKind = nil
  Tracker.levelUpG = nil
  Tracker.lastLevelSyncG = nil

  NewDelta()
  InvalidateCaches()
  Tracker.gapXPPending = (not ro) and char.xpSnap ~= nil
  Tracker.pendingReconcile = false
  anchored = false
  dropSecs = 0
  sync.valid, sync.restored, sync.levelValid, sync.levelPlayed = false, false, false, nil
  SetB(lvl, 0, 0, 0)
  Tracker.b0 = nil
  pendingQuest, poolDrop, retryArmed = 0, 0, false
  baselineTries, baselineDone = 0, false
  markSeen, marks, marksG, pendXP, zoneEvtG, xpDeferred = false, 0, 0, 0, -1e9, false
  Tracker.loadKills = 0
  started = true

  if not ro and type(char.zones) == "table" and char.zones[zone] then StoreName(char.zones[zone], zone) end
  RefreshMax()
  -- time without XP and server level cap (R1, R2): a cap detected at another level is
  -- over; a record from before the stall guard gets its count
  if not ro then
    if char.capLevel ~= nil and char.capLevel ~= lvl then char.capLevel = nil end
    if char.noXP == nil then MigrateNoXP(char, lvl) end
  end
  SyncCap()
  PrepareStallMaps()
  xsFrac, cap.misses, cap.missLevel = 0, 0, 0
  cap.inCombat, cap.xp, cap.lvl0, cap.tgtOK = false, false, nil, false
  for i = 1, #EVENT_ORDER do
    local ev = EVENT_ORDER[i]
    ns.RegisterEvent(ev, Tracker, EVENTS[ev])
  end
  ns.RegisterEvent("PLAYER_REGEN_DISABLED", cap.OWNER, cap.OnCombatStart)
  ns.RegisterEvent("PLAYER_REGEN_ENABLED", cap.OWNER, cap.OnCombatEnd)
  ns.RegisterEvent("PLAYER_TARGET_CHANGED", cap.OWNER, cap.OnTargetChanged)
  ns.RegisterMessage("SETTINGS_CHANGED", Tracker, OnSettingsChanged)
  ns.RegisterMessage("DB_SWAPPED", Tracker, OnDBSwapped)
end

-- Core.ResetChar has rebuilt the current record in place (5.20).
function Tracker.OnCharReset()
  local char = ns.char
  if not started or not char or ns.readOnly then return end
  NewDelta()
  InvalidateCaches()
  seg.frac = 0
  holdSecs, holdXP = 0, 0   -- held time predates the reset
  local lb = ns.Core.NewLevel()
  lb.partial = true
  if type(char.levels) ~= "table" then char.levels = {} end
  char.levels[seg.level] = lb
  char.level = seg.level
  local s = NewLiveSession()
  if b.valid then s.p0 = Round3(b.xp / b.max) end
  ns.session = s
  char.cur = s
  Tracker.gapXPPending = false
  Tracker.pendingReconcile = false
  Tracker.recLevel = seg.level
  anchored = false
  pendXP, marks = 0, 0      -- a kill waiting for its marker predates the reset
  Tracker.loadKills = 0     -- the kills of this load went with the old record
  -- the new record has no time without XP and no cap yet
  capped, xsFrac, cap.misses, cap.missLevel, cap.tgtOK = false, 0, 0, 0, false
  PrepareStallMaps()
end

-- Late SavedVariables (5.16): replays everything credited since this load into
-- newChar. Called by Core.CheckSwap before ns.char is swapped.
function Tracker.ReplayDelta(newChar)
  if not started or type(newChar) ~= "table" or not delta then return end
  Tracker.Flush(GetTime())
  local Core = ns.Core
  local oldChar = ns.char
  local prevLevel = newChar.level
  Tracker.recLevel = (type(newChar.srv) == "table" and newChar.srv.level) or newChar.level or seg.level
  Tracker.gapXPPending = newChar.xpSnap ~= nil
  anchored = false   -- the new record has not met the server yet (step 9 re-applies the sync)

  if type(newChar.life) ~= "table" then newChar.life = Core.NewLife() end
  if type(newChar.levels) ~= "table" then newChar.levels = {} end
  if type(newChar.zones) ~= "table" then newChar.zones = {} end
  -- its time without XP as saved (before this load's seconds are added)
  if newChar.noXP == nil and not ns.readOnly then MigrateNoXP(newChar, seg.level) end

  -- additive part (never contains reconcile writes: u, est, gap XP)
  Util.AddInto(newChar.life, delta.life)
  for lvl, dl in pairs(delta.levels) do
    local nl = newChar.levels[lvl]
    if nl == nil then
      nl = Core.NewLevel()
      if newChar.base == nil and lvl == seg.level then nl.partial = true end
      newChar.levels[lvl] = nl
    end
    Util.AddInto(nl, dl)
    local ml = oldChar and type(oldChar.levels) == "table" and oldChar.levels[lvl]
    if type(ml) == "table" then
      if ml.t1 ~= nil then nl.t1 = ml.t1 end
      if ml.srvEnd ~= nil then nl.srvEnd, nl.srvEndEst = ml.srvEnd, ml.srvEndEst end
      if ml.max ~= nil then nl.max = ml.max end
      if nl.t0 == nil then nl.t0 = ml.t0 end
      if nl.srvStart == nil then nl.srvStart, nl.srvStartEst = ml.srvStart, ml.srvStartEst end
    end
  end
  for k, dz in pairs(delta.zones) do
    local nz = newChar.zones[k]
    if nz == nil then
      nz = Core.NewZone()
      newChar.zones[k] = nz
    end
    Util.AddInto(nz, dz)
    if nz.name == nil then
      local mz = oldChar and type(oldChar.zones) == "table" and oldChar.zones[k]
      nz.name = (type(mz) == "table" and mz.name) or nameOf[k]
    end
  end

  -- session
  local s = ns.session
  if s then
    local cur = newChar.cur
    if Tracker.loadKind == "login" then
      if type(cur) == "table" and cur ~= s and SumAll(cur.s) > 0 then
        PushSession(newChar, cur, cur.at or cur.t0, prevLevel, SnapProgress(newChar.xpSnap))
      end
      newChar.cur = s
    elseif Tracker.loadKind == "reload" then
      if type(cur) == "table" and cur ~= s then
        if type(cur.s) ~= "table" then cur.s = {} end
        Util.AddInto(cur.s, s.s)
        Add(cur, "xp", s.xp or 0)
        Add(cur, "d", s.d or 0)
        ns.session = cur
      else
        newChar.cur = s
      end
    end
  end

  -- non-additive part: last, xpSnap and base keep the new record's values
  newChar.level = seg.level
  local ms, nsrv = oldChar and oldChar.srv, newChar.srv
  if type(ms) == "table" and (type(nsrv) ~= "table" or (ms.at or 0) > (nsrv.at or 0)) then
    newChar.srv = Util.DeepCopy(ms)
  end
  -- the last kill (the newer one wins)
  local mk, nk = oldChar and oldChar.lastKill, newChar.lastKill
  local mr, nkills = oldChar and oldChar.killRing, Tracker.loadKills
  if type(mk) == "table" and (type(nk) ~= "table" or (mk.at or 0) >= (nk.at or 0)) then
    -- no kill in this load and a strictly newer live kill: the new record is an older copy
    -- (WTFix) whose ring predates that kill too; the live ring follows, so the last kill
    -- shown stays among the averaged ones (same kill on both sides: the new ring is kept)
    if nkills == 0 and type(mr) == "table" and #mr > 0
       and (type(nk) ~= "table" or (mk.at or 0) > (nk.at or 0)) then
      newChar.killRing = Util.DeepCopy(mr)
    end
    newChar.lastKill = Util.DeepCopy(mk)
  end
  -- the kills of this load (the newest entries of the live ring) follow the new record's
  -- own: neither its saved history (a fresh provisional record) nor duplicates (an older
  -- copy of the same record) are lost or added
  if type(mr) == "table" and nkills > 0 then
    local n, size = #mr, C.KILL_RING
    if nkills > n then nkills = n end
    local nr = newChar.killRing
    if type(nr) ~= "table" then
      nr = {}
      newChar.killRing = nr
    end
    for i = n - nkills + 1, n do
      while #nr >= size do table_remove(nr, 1) end
      nr[#nr + 1] = mr[i]
    end
  end

  -- time without XP and server cap: this load's state continues the saved one (the
  -- in-memory count restarted at 0 if an XP gain happened in this load)
  local gained = (delta.life.xp or 0) > 0
  local liveNoXP = oldChar and oldChar.noXP
  if type(liveNoXP) ~= "number" then liveNoXP = 0 end
  if gained then
    newChar.noXP = liveNoXP
  else
    newChar.noXP = (newChar.noXP or 0) + liveNoXP
  end
  local liveCap = oldChar and oldChar.capLevel
  if liveCap == seg.level then
    newChar.capLevel = liveCap
  elseif gained or newChar.capLevel ~= seg.level then
    newChar.capLevel = nil
  end
  if newChar.capLevel == seg.level or IsStalled(newChar) then MoveLevelToStall(newChar, seg.level, false) end

  -- the EMA gets this load's time, without its withheld (stalled or capped) seconds
  local secs = delta.life.s
  local dxs = delta.life.xs
  if type(dxs) == "table" then
    secs = {}
    for k, v in pairs(delta.life.s) do
      local n = v - (dxs[k] or 0)
      if n > 0 then secs[k] = n end
    end
  end
  Tracker.FeedChunk(newChar, secs, delta.life.xa, delta.life.xr, delta.life.xq)
  RepairContinentZones(newChar)
  InvalidateCaches()
end

---------------------------------------------------------------------------
-- City classification (5.5)
---------------------------------------------------------------------------

-- A built-in capital forced to "not a city" in the resolution chain of mapID
-- (same walk as ResolveMiss), so that toggling twice restores the default.
local function OverriddenCapital(mapID, cities)
  local id, depth = mapID, 0
  while id and id ~= 0 and depth < C.MAX_ZONE_DEPTH do
    if C.CAPITALS[id] and cities[id] == false then return id end
    local info = C_Map.GetMapInfo(id)
    if not info then break end
    local mt = info.mapType
    if mt == MT_ZONE or mt == MT_DUNGEON then
      local parent = info.parentMapID
      if mt == MT_DUNGEON and parent and C.CAPITALS[parent] and cities[parent] == false then return parent end
      break
    end
    id = info.parentMapID
    depth = depth + 1
  end
  return nil
end

function Tracker.ToggleCityForCurrentZone()
  if ns.readOnly then return nil, "readonly" end
  local mapID = C_Map.GetBestMapForUnit("player")
  if type(mapID) ~= "number" then return nil, "nozone" end
  local db = ns.db
  if not db then return nil, "nozone" end
  -- never a city inside an instance (5.5): an override would change nothing
  if IsInInstance() then return nil, "instance" end
  if type(db.cities) ~= "table" then db.cities = {} end
  local zk, isCity, capKey = ResolveZone(mapID, false)
  if zk == nil then return nil, "nozone" end   -- a continent is never a city
  local id, value
  if isCity then
    id, value = capKey, false
  else
    id, value = OverriddenCapital(mapID, db.cities) or mapID, true
  end
  local default = C.CAPITALS[id] == true
  if value == default then db.cities[id] = nil else db.cities[id] = value end
  Tracker.InvalidateZoneCache()
  Send("SETTINGS_CHANGED", "cities", id)
  Reeval(GetTime())
  local name = nameOf[id]
  if name == nil then
    local info = C_Map.GetMapInfo(id)
    name = info and info.name
  end
  return id, value, name or L.ZONE_UNKNOWN
end

---------------------------------------------------------------------------
-- Getters (no API call, no allocation)
---------------------------------------------------------------------------

function Tracker.GetState()
  return seg.key, seg.zone, seg.level
end

-- paused, reason: the current state is excluded by mask
function Tracker.IsPaused(mask)
  if mask == nil then mask = ns.GetMask and ns.GetMask() or 0 end
  local row = INCLUDED[mask]
  local k = seg.key
  if not row or row[k] ~= false then return false, nil end
  if mask % 2 == 1 and C.IS_AFK[k] then return true, "afk" end
  if math_floor(mask / 2) % 2 == 1 and C.IS_INN[k] then return true, "inn" end
  return true, "city"
end

function Tracker.GetXPInfo()
  return b.level, b.xp, b.max, b.rest, b.valid
end

function Tracker.IsMax()
  return realMax or capped
end

-- isStalled, secsSinceLastXP: counted non-AFK seconds since the last XP gain (R1).
function Tracker.GetStall()
  local char = ns.char
  local n = char and char.noXP
  if type(n) ~= "number" then n = 0 end
  return (not realMax) and n > XP_STALL, n
end

-- capLevel or nil, isServerCap, misses: the detected server level cap (R2).
-- isServerCap = max level only because of it; misses = kills without XP in a row at
-- the current level (0 after any XP gain; at least C.CAP_MISSES while capped).
function Tracker.GetCapInfo()
  local char = ns.char
  local lvl = capped and char and char.capLevel or nil
  local misses = (cap.missLevel == seg.level) and cap.misses or 0
  if capped and misses < C.CAP_MISSES then misses = C.CAP_MISSES end
  return lvl, capped and not realMax, misses
end

function Tracker.GetSession()
  return ns.session
end

function Tracker.GetSync()
  if sync.valid then return sync end
  return nil
end

function Tracker.GetLevelUpG()
  return Tracker.levelUpG
end

function Tracker.GetLastLevelSyncG()
  return Tracker.lastLevelSyncG
end

function Tracker.GetLoadKind()
  return Tracker.loadKind
end

function Tracker.GetDelta()
  return delta
end
