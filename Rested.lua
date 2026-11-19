local ADDON, ns = ...
-- Rested.lua - the rested XP cap and the "rested XP full" alert.
--
-- The cap (Tooltip.lua's "Rested cap" row): the rested pool holds at most C.REST_CAP of the
-- level's XP (150 %). On WoW Forever the Legacy perk Well Rested raises it by
-- C.WELL_RESTED.step per rank (4 %, 5 ranks), the cap multiplied: 168 % at rank 3. The rank
-- is the character's own (Legacy perks are bought per character), read from its Legacy
-- talent config (C_Traits: node C.WELL_RESTED.node of the Adventure tree; no aura or spell
-- tells it) and checked against the perk's spell (a later build that moves the perk: the
-- tree is searched for the spell). Read at the first ask, then cached until a trait event
-- or a loading screen; a tree the client cannot read (no config: a character without any
-- Legacy perk, or the data not in yet) reads the last rank read this session (0 if none)
-- and is read again at the next ask. The logout saves it; a rank never read this session
-- keeps the last save's (on 2026-11-17 a character with the perk was saved without it: the
-- tree not read at its logout). A client without the trait API or the tree reads rank 0:
-- the cap stays 150 %.
--
-- The alert (widget.restAlert, off by default): the characters whose rested XP is full.
-- This one: the pool the game reports, below the max level. The others: the pool saved at
-- their last logout (char.rested; else, for a character of this character's realm not
-- seen since this version, the older char.xpSnap, resting when char.last's state was an
-- inn or a capital, without its rank; not when the record's level is another or a server
-- cap was found at it. Another realm's record never seen since may be a closed realm's,
-- a beta's: it counts once logged out with this version), grown since by C.REST_GAIN of
-- their level's XP every C.REST_GAIN_SECS (x C.REST_GAIN_OUT when they logged out outside
-- an inn or a capital), faster by their Well Rested rank's percent, up to their cap. A
-- character below the max level only, whose last logout is not older than
-- C.REST_ALERT_DAYS. Bar.lua shows its icon while the list is not
-- empty, Tooltip.lua names them (FullText). While the option is on, the list is made again
-- on XP_CHANGED and LEVEL_UP (this character's pool), the trait events, DB_SWAPPED and
-- CHAR_RESET, and on the TICK when the next character fills up or leaves the window (one
-- time() compare per tick); "RESTED_ALERT" is sent when its size changes. Off, nothing
-- listens but the trait events and the logout. Making the list allocates nothing (records
-- in reused arrays); FullText makes the names, for the tooltip.
--
-- The alts' section (widget.restAlts, off by default; Tooltip.lua): every other character
-- the alert would watch, with its pool and its cap in levels and the time until it is
-- full, fullest first (Rested.Alts, made when the tooltip asks; nothing listens for it).
--
-- Saved at each logout (and /reload) below the max level: char.rested = { r, m, l, at,
-- inn, k } (Core repairs it): the pool, the level's XP, the level, time(), logged out
-- resting (an inn or a capital: true, else nil; IsResting as seen while playing, kept
-- through the logout: see ReadResting), the Well Rested rank (nil: none). At the
-- max level, XP disabled or a server level cap (Tracker.IsMax) it is false: nothing to
-- watch, and the older xpSnap is not used either. Every save is checked when read (a
-- newer version's data, read-only, is not repaired).

local L, C, Util = ns.L, ns.C, ns.Util

local type, pairs, pcall, tonumber = type, pairs, pcall, tonumber
local floor, math_huge = math.floor, math.huge
local format, table_concat = string.format, table.concat

local Rested = {}
ns.Rested = Rested

local WR = C.WELL_RESTED
local CAP, GAIN, GAIN_SECS, GAIN_OUT = C.REST_CAP, C.REST_GAIN, C.REST_GAIN_SECS, C.REST_GAIN_OUT
local ALERT_SECS = C.REST_ALERT_DAYS * 86400
local NAMES_SHOWN = 4     -- characters FullText names; past that, the first ones and "+N"

-- A pool within this share of its cap is full: the game counts whole XP points, the cap
-- here is rounded, and the alert must not wait for the last fraction of a point.
Rested.FULL = 0.999
local FULL = Rested.FULL

-- State keys of a rest area (char.last.key of an older save): an inn or a capital.
local RESTING = {}
for _, keys in pairs({ C.INN_KEYS, C.CITY_KEYS }) do
  for i = 1, #keys do RESTING[keys[i]] = true end
end

-- The events after which the rank is read again: the Legacy config changed or came in
-- (and PLAYER_ENTERING_WORLD: OnEnteringWorld).
local TRAIT_EVENTS = { "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "TRAIT_NODE_CHANGED",
                       "TRAIT_TREE_CHANGED" }

---------------------------------------------------------------------------
-- Well Rested rank
---------------------------------------------------------------------------

local rank = nil          -- cached rank (nil: to read)
local lastRank = nil      -- the last rank read this session (kept through the trait events)
local ranks = WR.ranks    -- the perk's ranks (the node's maxRanks once read)
local node = WR.node      -- the perk's node (found again by its spell if it moved)

-- A number the addon may use (not secret, not NaN), else nil.
local function Num(v)
  if Util.IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
  return v
end

-- The spell of a node's entry, nil when the client cannot tell.
local function NodeSpell(CT, configID, info)
  if type(CT.GetEntryInfo) ~= "function" or type(CT.GetDefinitionInfo) ~= "function" then return nil end
  local active = info.activeEntry
  local entryID = type(active) == "table" and Num(active.entryID) or nil
  if entryID == nil and type(info.entryIDs) == "table" then entryID = Num(info.entryIDs[1]) end
  if entryID == nil then return nil end
  local ok, entry = pcall(CT.GetEntryInfo, configID, entryID)
  if not ok or type(entry) ~= "table" or Num(entry.definitionID) == nil then return nil end
  local ok2, def = pcall(CT.GetDefinitionInfo, entry.definitionID)
  if not ok2 or type(def) ~= "table" then return nil end
  return Num(def.spellID)
end

-- Whether a node's info is the perk's: false for another node's spell, a node the tree
-- does not have (its ID differs, or no rank to buy); true when the client cannot tell.
local function IsPerk(CT, configID, info, id)
  local nid = Num(info.ID)
  if nid ~= nil and nid ~= id then return false end
  local m = info.maxRanks
  if m ~= nil and not (Num(m) and m >= 1) then return false end
  local spell = NodeSpell(CT, configID, info)
  return spell == nil or spell == WR.spell
end

-- The node of the perk's spell in its tree (a build that moved it): its ID and info; else
-- nil, nil and whether the tree was read (true: some node of it answered with its own ID,
-- so the perk is not there; false: none did, the tree's data not in yet: read again).
local function FindPerk(CT, configID)
  if type(CT.GetTreeNodes) ~= "function" then return nil, nil, true end
  local ok, nodes = pcall(CT.GetTreeNodes, WR.tree)
  if not ok or type(nodes) ~= "table" then return nil, nil, false end
  local read = false
  for i = 1, #nodes do
    local id = Num(nodes[i])
    if id ~= nil and id ~= node then
      local okN, info = pcall(CT.GetNodeInfo, configID, id)
      if okN and type(info) == "table" and Num(info.ID) == id then
        read = true
        if NodeSpell(CT, configID, info) == WR.spell then return id, info end
      end
    end
  end
  return nil, nil, read
end

-- rank, ranks, keep (false: read again at the next ask).
local function ReadRank()
  local CT = C_Traits
  if type(CT) ~= "table" or type(CT.GetConfigIDByTreeID) ~= "function" or type(CT.GetNodeInfo) ~= "function" then
    return 0, WR.ranks, true                     -- no trait API: no Legacy perk here
  end
  local ok, configID = pcall(CT.GetConfigIDByTreeID, WR.tree)
  configID = ok and Num(configID) or nil
  if configID == nil then return 0, WR.ranks, false end   -- no config (yet)
  local okN, info = pcall(CT.GetNodeInfo, configID, node)
  if not okN or type(info) ~= "table" then return 0, WR.ranks, false end
  if not IsPerk(CT, configID, info, node) then
    local id, found, read = FindPerk(CT, configID)
    if id == nil then return 0, WR.ranks, read end   -- no such perk (read), or the tree not in
    node, info = id, found
  end
  -- activeRank: what the character has (a change staged in the frame is not)
  local r = Num(info.activeRank) or Num(info.currentRank)
  if r == nil then return 0, WR.ranks, false end
  local m = Num(info.maxRanks)
  if m == nil or m < 1 then m = WR.ranks end
  m, r = floor(m), floor(r)
  if r < 0 then r = 0 elseif r > m then r = m end
  return r, m, true
end

-- This character's Well Rested rank (0: none, or a client without Legacy perks), the
-- perk's ranks and whether the tree was read (false: the last rank read this session, 0
-- if none). Allocates only when it reads the tree (C_Traits' tables).
function Rested.Rank()
  if rank == nil then
    local r, m, keep = ReadRank()
    ranks = m
    if not keep then return lastRank or r, m, false end
    rank, lastRank = r, r
  end
  return rank, ranks, true
end

-- The perk's name in the client's language (the game's), else the addon's.
function Rested.PerkName()
  local CS = C_Spell
  if type(CS) == "table" and type(CS.GetSpellName) == "function" then
    local ok, name = pcall(CS.GetSpellName, WR.spell)
    if ok and not Util.IsSecret(name) and type(name) == "string" and name ~= "" then return name end
  end
  return L.WELL_RESTED
end

---------------------------------------------------------------------------
-- Cap and estimate (pure)
---------------------------------------------------------------------------

-- The cap in levels for a Well Rested rank: 1.5 at rank 0, 1.68 at rank 3.
function Rested.CapFrac(r)
  return CAP * (1 + WR.step * (tonumber(r) or 0))
end

-- The cap in XP of a level of `max` XP (rounded), and in levels.
function Rested.Cap(max, r)
  local f = Rested.CapFrac(r)
  return floor(max * f + 0.5), f
end

-- Whether a pool of `rest` XP is full for a cap of `cap` XP.
function Rested.IsFull(rest, cap)
  return cap > 0 and rest >= cap * FULL
end

-- A finite number (saved data: a newer version's, read-only, is not repaired).
local function Fin(v)
  return type(v) == "number" and v == v and v > -math_huge and v < math_huge
end

-- A pool, a level's XP, a level and a time in range.
local function InRange(r, m, l, at)
  return Fin(r) and r >= 0 and Fin(m) and m > 0 and Fin(l) and l >= 1 and Fin(at)
end

-- A saved state (char.rested, or an older save of a character of `realm`, this
-- character's: see the header): { r, m, l, at, inn, k, old }, written into `out` (old:
-- the older save, whose Well Rested rank is not known: k 0); nil when there is none,
-- nothing to watch (false) or not in range.
local function Saved(char, out, realm)
  local s = char.rested
  if type(s) == "table" then
    if not InRange(s.r, s.m, s.l, s.at) then return nil end
    local k = s.k
    if not (Fin(k) and k > 0) then k = 0 end
    out.r, out.m, out.l, out.at, out.inn, out.k, out.old = s.r, s.m, s.l, s.at, s.inn == true, k, false
    return out
  end
  if s ~= nil then return nil end                -- false: saved with nothing to watch
  if realm == nil or char.realm ~= realm then return nil end   -- another realm's: maybe gone
  local x = char.xpSnap
  if type(x) ~= "table" or not InRange(x.rest, x.max, x.level, x.at) then return nil end
  -- the record's level since, or a server cap found at this one: not this snapshot's pool
  local lv, cap = char.level, char.capLevel
  if (lv ~= nil and lv ~= x.level) or (cap ~= nil and cap == x.level) then return nil end
  local last = char.last
  out.r, out.m, out.l, out.at, out.k, out.old = x.rest, x.max, x.level, x.at, 0, true
  out.inn = type(last) == "table" and RESTING[last.key] == true
  return out
end
Rested.Saved = Saved

-- The pool of a saved state at `now` (time()), grown since its logout up to its cap; the
-- cap; and when the pool is full (<= now: full already).
function Rested.Estimate(s, now)
  local k = s.k or 0
  local cap = Rested.Cap(s.m, k)
  local perSec = s.m * GAIN / GAIN_SECS * (1 + WR.step * k)
  if not s.inn then perSec = perSec * GAIN_OUT end
  local need = cap * FULL - s.r
  local fullAt = s.at
  if need > 0 then fullAt = s.at + need / perSec end
  local est = s.r
  if now > s.at then est = est + (now - s.at) * perSec end
  if est > cap then est = cap end
  return est, cap, fullAt
end

---------------------------------------------------------------------------
-- The alert
---------------------------------------------------------------------------

local on = false               -- widget.restAlert
local list, gid, lvl = {}, {}, {}   -- the other characters whose pool is full: record, key, level
local nList = 0
local selfFull = false         -- this character's pool is full
local nextAt = math_huge       -- time() of the next change: a character fills up or leaves
local sentCount = 0            -- the count RESTED_ALERT last said
local tmp = {}                 -- Saved()'s output, reused

-- Into the list, level descending then key (a stable order). Returns the new size.
local function Insert(n, key, char, level)
  local i = n
  while i >= 1 and (lvl[i] < level or (lvl[i] == level and gid[i] > key)) do
    list[i + 1], gid[i + 1], lvl[i + 1] = list[i], gid[i], lvl[i]
    i = i - 1
  end
  list[i + 1], gid[i + 1], lvl[i + 1] = char, key, level
  return n + 1
end

local function Recompute()
  local n, nxt = 0, math_huge
  selfFull = false
  if on then
    local now = time()
    local cur = ns.char
    local curKey = type(cur) == "table" and cur.guid or nil
    -- this character: the pool the game reports
    local T = ns.Tracker
    if T and curKey ~= nil then
      local _, _, max, rest, valid = T.GetXPInfo()
      if valid and max > 0 and not T.IsMax() then
        selfFull = Rested.IsFull(rest, (Rested.Cap(max, (Rested.Rank()))))
      end
    end
    -- the others: their saved pool, grown since
    local db = ns.db
    local chars = type(db) == "table" and db.chars or nil
    if type(chars) == "table" then
      local top = Util.MaxLevel()
      local realm = curKey ~= nil and cur.realm or nil
      for key, char in pairs(chars) do
        if type(key) == "string" and key ~= curKey and type(char) == "table" then
          local s = Saved(char, tmp, realm)
          if s and s.l < top and s.at + ALERT_SECS > now then
            local _, _, fullAt = Rested.Estimate(s, now)
            if fullAt <= now then
              n = Insert(n, key, char, s.l)
              fullAt = s.at + ALERT_SECS              -- then it leaves the window
            end
            if fullAt < nxt then nxt = fullAt end
          end
        end
      end
    end
  end
  for i = n + 1, nList do list[i], gid[i], lvl[i] = nil, nil, nil end
  nList, nextAt = n, nxt
  local count = n + (selfFull and 1 or 0)
  if count ~= sentCount then
    sentCount = count
    ns.SendMessage("RESTED_ALERT", count)
  end
end
Rested.Recompute = Recompute

-- The characters whose rested XP is full (0 while the option is off), this one included.
function Rested.Count()
  return nList + (selfFull and 1 or 0)
end

-- Whether this character's rested XP is full (false while the option is off).
function Rested.SelfFull()
  return selfFull
end

-- "this character · Name Surname (23) · Other (12)": who is full, nil when nobody (or the
-- option off); past NAMES_SHOWN, the first ones and "+N". Allocates: the tooltip only.
local parts = {}
function Rested.FullText()
  local total = Rested.Count()
  if total == 0 then return nil end
  local named = total
  if named > NAMES_SHOWN then named = NAMES_SHOWN - 1 end
  local n = 0
  if selfFull then
    n = 1
    parts[1] = L.TT_REST_SELF
  end
  for i = 1, nList do
    if n >= named then break end
    n = n + 1
    parts[n] = format(L.TT_REST_ALT_FMT, Util.CharName(list[i]), floor(lvl[i]))
  end
  local text = table_concat(parts, L.SEP, 1, n)
  for i = 1, n do parts[i] = nil end
  if total > n then text = format(L.MASK_MORE_FMT, text, total - n) end
  return text
end

---------------------------------------------------------------------------
-- The alts' section (widget.restAlts, the tooltip)
---------------------------------------------------------------------------

-- The other characters the alert would watch (a usable save, below the max level, within
-- C.REST_ALERT_DAYS; this one left out), whatever the alert's option, fullest first (then
-- by key): their record, saved level, share of their cap (0 .. 1, 1 once full), when
-- their pool is full (<= now: full), the pool and the cap in levels (1.68: 168% of the
-- level's XP) and whether the save is an older one (its Well Rested rank not known). In
-- reused arrays (Rested.Alt reads them); returns their count. Asked by the tooltip only.
local altChar, altLvl, altFrac, altFull, altKey = {}, {}, {}, {}, {}
local altRest, altCap, altOld = {}, {}, {}
local nAlts = 0
function Rested.Alts(now)
  local n = 0
  local cur = ns.char
  local curKey = type(cur) == "table" and cur.guid or nil
  local db = ns.db
  local chars = type(db) == "table" and db.chars or nil
  if type(chars) == "table" then
    local top = Util.MaxLevel()
    local realm = curKey ~= nil and cur.realm or nil
    for key, char in pairs(chars) do
      if type(key) == "string" and key ~= curKey and type(char) == "table" then
        local s = Saved(char, tmp, realm)
        if s and s.l < top and s.at + ALERT_SECS > now then
          local est, cap, fullAt = Rested.Estimate(s, now)
          local frac = 1
          if fullAt > now and cap > 0 then frac = est / cap end
          local rest, capLv, old = est / s.m, Rested.CapFrac(s.k), s.old == true
          local i = n
          while i >= 1 and (altFrac[i] < frac or (altFrac[i] == frac and altKey[i] > key)) do
            altChar[i + 1], altLvl[i + 1], altFrac[i + 1], altFull[i + 1], altKey[i + 1] =
              altChar[i], altLvl[i], altFrac[i], altFull[i], altKey[i]
            altRest[i + 1], altCap[i + 1], altOld[i + 1] = altRest[i], altCap[i], altOld[i]
            i = i - 1
          end
          altChar[i + 1], altLvl[i + 1], altFrac[i + 1], altFull[i + 1], altKey[i + 1] = char, s.l, frac, fullAt, key
          altRest[i + 1], altCap[i + 1], altOld[i + 1] = rest, capLv, old
          n = n + 1
        end
      end
    end
  end
  for i = n + 1, nAlts do
    altChar[i], altLvl[i], altFrac[i], altFull[i], altKey[i] = nil, nil, nil, nil, nil
    altRest[i], altCap[i], altOld[i] = nil, nil, nil
  end
  nAlts = n
  return n
end

-- Row i of the last Rested.Alts: the record, its level, its share of the cap, when full,
-- the pool and the cap in levels, whether the save is an older one.
function Rested.Alt(i)
  return altChar[i], altLvl[i], altFrac[i], altFull[i], altRest[i], altCap[i], altOld[i]
end

-- A character fills up or leaves the window: one compare per tick otherwise.
local function OnTick()
  if time() >= nextAt then Recompute() end
end

-- Applies widget.restAlert: listens while it is on, and makes the list again.
function Rested.Apply()
  local s = ns.settings
  local want = type(s) == "table" and type(s.widget) == "table" and s.widget.restAlert == true
  if want ~= on then
    on = want
    if on then
      ns.RegisterMessage("XP_CHANGED", Rested, Recompute)
      ns.RegisterMessage("LEVEL_UP", Rested, Recompute)
      ns.RegisterMessage("TICK", Rested, OnTick)
    else
      ns.UnregisterMessage("XP_CHANGED", Rested)
      ns.UnregisterMessage("LEVEL_UP", Rested)
      ns.UnregisterMessage("TICK", Rested)
    end
  end
  Recompute()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnTraitEvent()
  rank = nil
  if on then Recompute() end
end

-- Whether this character rests (an inn or a capital), as IsResting said while it played:
-- read at PLAYER_ENTERING_WORLD and PLAYER_UPDATE_RESTING, then kept from
-- PLAYER_LEAVING_WORLD on (a loading screen, a /reload, the logout) until the next
-- PLAYER_ENTERING_WORLD. At PLAYER_LOGOUT the game answers false even in a capital
-- (Forever 1.60.1: characters logged out in Orgrimmar, last state "c", saved with no
-- rest area), and it may clear the flag while the world is left.
local resting, leaving = false, false
local function ReadResting()
  if leaving then return end
  local ok, v = Util.SafeRead(IsResting)
  if ok then resting = v == true end
end

local function OnEnteringWorld()
  leaving = false
  ReadResting()
  OnTraitEvent()
end

local function OnLeavingWorld()
  leaving = true
end

-- The pool at the logout (and /reload), for the alert of the next sessions.
local function OnLogout()
  local char = ns.char
  local T = ns.Tracker
  if ns.readOnly or type(char) ~= "table" or not T then return end
  if T.IsMax() then
    char.rested = false                        -- nothing to watch: max level, XP disabled, a cap
    return
  end
  local level, _, max, rest, valid = T.GetXPInfo()
  if not valid or max <= 0 then return end        -- not read: the last save stays
  local s = char.rested
  if type(s) ~= "table" then
    s = {}
    char.rested = s
  end
  s.r, s.m, s.l, s.at = rest, max, level, time()
  local ok, live = Util.SafeRead(IsResting)
  s.inn = ((ok and live == true) or resting) or nil
  -- the rank (the last one read this session, see Rested.Rank); never read this session
  -- (the tree not readable from the login to the logout): the last save's
  local r = Rested.Rank()
  if lastRank == nil then r = Num(s.k) or 0 end
  s.k = r > 0 and r or nil
end

local function OnSettingsChanged(_, path)
  if path == "widget.restAlert" then Rested.Apply() end
end

local inited = false
local function Init()
  if inited then
    Rested.Apply()
    return
  end
  inited = true
  for i = 1, #TRAIT_EVENTS do ns.RegisterEvent(TRAIT_EVENTS[i], Rested, OnTraitEvent) end
  ns.RegisterEvent("PLAYER_ENTERING_WORLD", Rested, OnEnteringWorld)
  ns.RegisterEvent("PLAYER_LEAVING_WORLD", Rested, OnLeavingWorld)
  ns.RegisterEvent("PLAYER_UPDATE_RESTING", Rested, ReadResting)
  ReadResting()
  ns.RegisterEvent("PLAYER_LOGOUT", Rested, OnLogout)
  ns.RegisterMessage("SETTINGS_CHANGED", Rested, OnSettingsChanged)
  ns.RegisterMessage("DB_SWAPPED", Rested, Rested.Apply)
  ns.RegisterMessage("CHAR_RESET", Rested, Recompute)
  Rested.Apply()
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", Rested, Init)
end
