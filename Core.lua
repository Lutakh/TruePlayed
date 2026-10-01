-- Core.lua - constants (ns.C), utilities (ns.Util), the event/message bus,
-- SavedVariables lifecycle (adopt, migrate, repair, late swap), settings,
-- character records, the single 1 s ticker and the performance helpers.
-- See SPEC-FINAL sections 3.1-3.6, 4, 5.1, 5.16, 5.18, 5.20 and 6.
local ADDON, ns = ...
local L = ns.L

-- Upvalues (hot paths must not look up globals). Never cache RequestTimePlayed,
-- ChatFrameUtil or GameTooltip methods here (SPEC 2.4).
local type, pairs, select, tonumber, tostring = type, pairs, select, tonumber, tostring
local pcall, setmetatable, next = pcall, setmetatable, next
local math_floor, math_huge = math.floor, math.huge
local string_format = string.format
local table_sort, table_concat = table.sort, table.concat
local GetTime, time = GetTime, time
local CreateFrame, C_Timer = CreateFrame, C_Timer
local UnitGUID, UnitName, UnitClass, UnitFactionGroup, UnitLevel = UnitGUID, UnitName, UnitClass, UnitFactionGroup, UnitLevel
local GetRealmName = GetRealmName
local IsXPUserDisabled, GetMaxPlayerLevel = IsXPUserDisabled, GetMaxPlayerLevel  -- may be nil (guarded)
local IsPlayerAtEffectiveMaxLevel, IsLevelAtEffectiveMaxLevel = IsPlayerAtEffectiveMaxLevel, IsLevelAtEffectiveMaxLevel  -- idem
local GetMaxLevelForPlayerExpansion = GetMaxLevelForPlayerExpansion                           -- idem
local issecretvalue = issecretvalue                                              -- nil on Era
local securecallfunction, geterrorhandler = securecallfunction, geterrorhandler
local debugprofilestop = debugprofilestop

local loadG = GetTime()   -- GetTime at file load (uptime base for CPU per minute)

---------------------------------------------------------------------------
-- Root fields (SPEC 3.1)
---------------------------------------------------------------------------
ns.ADDON = ADDON or "TruePlayed"

do
  local v
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if getMeta then
    local ok, res = pcall(getMeta, ns.ADDON, "Version")
    if ok then v = res end
  end
  if type(v) ~= "string" or v == "" or v:sub(1, 1) == "@" then v = "dev" end
  ns.VERSION = v

  local iface
  if GetBuildInfo then
    local _, _, _, i = GetBuildInfo()
    iface = tonumber(i)
  end
  ns.interface = iface or 0
end
ns.isForever = ns.interface >= 16000 and ns.interface < 20000
ns.isEra = ns.interface >= 11500 and ns.interface < 11600
ns.readOnly = false
ns.ready = false

---------------------------------------------------------------------------
-- ns.C (SPEC 3.2, normative)
---------------------------------------------------------------------------
local C = {}
ns.C = C

-- lifecycle / timing
C.SCHEMA              = 1
C.TICK                = 1.0    -- the only ticker (seconds)
C.DRIFT_TOL           = 60     -- server/local difference ignored below this (s)
C.MAX_SEGMENT         = 900    -- a Flush longer than this is dropped (sleep, freeze)
C.RELOAD_GAP_MAX      = 300    -- /reload gap credited and sync restored below this (s)
C.MAX_ZONE_DEPTH      = 10
C.ZONE_HOLD_MAX       = 30     -- seconds held on an unresolved map (continent) before the zone-text fallback

-- rates
C.WARMUP_MIN          = 120    -- EMA d below this: no value at all
C.WARMUP_FULL         = 600    -- EMA d at/above this: status "ok" from the EMA
C.FALLBACK_MIN        = 300    -- min tracked seconds for level / recent-level fallbacks
C.RATE_SAMPLE_MIN     = 300    -- min seconds for session/level secondary rates
C.REST_BONUS          = 1.0    -- rested bonus = 100 % of base mob XP (verify in game)
C.REST_DRAIN          = 2.0    -- rest pool drops 2 per point of base mob XP (verify)
C.RECENT_LEVELS       = 5

-- time without XP (R1): past XP_STALL counted non-AFK seconds since the last XP gain the
-- character is "stalled": its time no longer feeds the EMA (frozen, neither decays nor
-- grows) and goes to life.xs / levels[L].xs, which the rate fallbacks leave out. Any XP
-- gain ends it. A server level cap (R2) is detected after CAP_MISSES kills in a row
-- without XP at the same level (the client still reports the real max level, e.g. 60).
C.XP_STALL            = 1200
C.CAP_MISSES          = 3

-- pre-install estimate (requirement C: XP/h never empty for lack of tracked data)
C.PRIOR_WEIGHT        = 1200   -- the prior counts as this many seconds of data, fading to 0 at WARMUP_FULL
C.PRIOR_MIN_PLAYED    = 1800   -- pre-install time needed to trust the prior (30 min)
C.PRIOR_MIN_PER_LEVEL = 600    -- and at least 10 min of it per level gained before the install
                               -- (premade or boosted characters: /played says nothing of a rate)
C.PRIOR_MAX_XPH       = 10000000   -- sanity bound when repairing a saved prior
-- XP to reach the next level, levels 1..59 (Classic / Vanilla table, also used by
-- WoW Forever). Sources: level 20 = 23200 (UnitXPMax seen in game), levels 57-59 =
-- 195000 / 202300 / 209800 (RXPGuides DB/forever/db.lua), the rest from the Classic
-- table. Used only when it matches the client (Tracker checks UnitXPMax and db.xpMax).
C.CLASSIC_XP = {
  400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
  8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
  25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
  50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
  95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
  153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
}

-- bounds (requirement A)
C.SESSION_RING        = 30
C.ZONES_MAX           = 150
C.ZONE_PRUNE_MIN      = 600
C.LEVEL_ZONES_MAX     = 10
C.LATENCY_MEMO_MAX    = 256

-- crash recovery (requirement D)
C.EST_MIN_HISTORY     = 600    -- below this much tracked history, estimated gaps go to "w"
C.EST_NOTIFY_MIN      = 300    -- chat notice when a re-added gap is at least this long

-- /played policy
C.PLAYED_LOGIN_WAIT     = 10
C.PLAYED_LEVELUP_WAIT   = 5
C.PLAYED_MIN_INTERVAL   = 30   -- between two automatic requests
C.PLAYED_MANUAL_MIN     = 2    -- debounce for /tpl sync and reset requests
C.PLAYED_HIDE_TIMEOUT   = 5    -- experimental hide safety timeout
C.PLAYED_FOREIGN_WINDOW = 3    -- a foreign request this recent disables our hide
C.LEVEL_RACE_WINDOW     = 10   -- critique #5
C.LEVEL_RACE_SLACK      = 60
C.LEVEL_FRESH_SLACK     = 3    -- a level time within the seconds since the level-up (+ this) is fresh

-- XP chain
C.XP_BATCH_DELAY      = 0.2
C.XP_BASELINE_DELAY   = 2
C.XP_BASELINE_RETRIES = 5
C.XP_RETRY_DELAY      = 0.5
C.QUEST_PENDING_TTL   = 5
C.POOL_DROP_TTL       = 2
C.TAXI_RECHECK_DELAY  = 0.5

-- kills (mobs to the next level): an XP gain is a kill when a CHAT_MSG_COMBAT_XP_GAIN
-- arrives within KILL_WINDOW of it (either order; the text is never read). Without
-- that event, a non-quest gain is a kill unless a subzone change (discovery XP) came
-- within DISCOVERY_WINDOW of it.
C.KILL_WINDOW         = 1.5
C.DISCOVERY_WINDOW    = 3
C.KILL_XP_MAX         = 1000000   -- sanity bound when repairing a saved char.lastKill

-- UI cadence
C.NET_INTERVAL        = 5      -- GetNetStats at most every 5 s (value changes every ~30 s)
C.WINDOW_ROW_REFRESH  = 5      -- Window refreshes its in-progress row every 5 ticks
C.PERF_SAMPLE_TICKS   = 60
C.GRAPH_RING          = 300    -- FPS / latency history samples (Graph.lua ring buffers)
C.GRAPH_WINDOWS       = { 30, 60, 300 }            -- graph.window choices (seconds)
C.OUTLINES            = { "none", "thin", "thick" } -- widget.outline choices

-- visual themes (design/SPEC-themes.md section 1): the order of every menu; "class" is a
-- setting value (the player's class theme), not a theme key
C.THEME_CHOICES = { "futuriste", "actuel", "heroic", "pixel", "class", "warrior", "paladin",
                    "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }
C.CLASS_THEMES  = { WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
                    PRIEST = "priest", SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock",
                    DRUID = "druid" }

-- state keys. Lowercase = active, uppercase = AFK. d / r / p (dungeon or scenario,
-- raid, battleground or arena) apply only inside an instance, where inn and city
-- never apply; w is the open world (and instances of an unknown type).
C.MASK_AFK, C.MASK_INN, C.MASK_CITY = 1, 2, 4
C.STATE_KEYS   = { "w", "W", "d", "D", "r", "R", "p", "P", "i", "I", "c", "C", "t", "T", "u" }
C.TRACKED_KEYS = { "w", "W", "d", "D", "r", "R", "p", "P", "i", "I", "c", "C", "t", "T" }   -- fixed order, used for largest-remainder splits
C.AFK_KEYS     = { "W", "D", "R", "P", "I", "C", "T" }
C.INN_KEYS     = { "i", "I" }
C.CITY_KEYS    = { "c", "C" }
C.TAXI_KEYS    = { "t", "T" }
C.ACTIVE_KEYS  = { "w", "d", "r", "p", "t" }
C.DUNGEON_KEYS = { "d", "D" }
C.RAID_KEYS    = { "r", "R" }
C.PVP_KEYS     = { "p", "P" }
C.INSTANCE_KEYS = { "d", "D", "r", "R", "p", "P" }
C.IS_AFK  = { W = true, D = true, R = true, P = true, I = true, C = true, T = true }
C.IS_INN  = { i = true, I = true }
C.IS_CITY = { c = true, C = true }
C.IS_INSTANCE = { d = "d", D = "d", r = "r", R = "r", p = "p", P = "p" }   -- key -> instance kind
C.INSTANCE_KIND = {                         -- IsInInstance() instanceType -> place
  party = "d", scenario = "d", raid = "r", pvp = "p", arena = "p",
}
C.KEY = {                                   -- C.KEY[place][isAfk] -> state key (no string building)
  w = { [false] = "w", [true] = "W" },
  d = { [false] = "d", [true] = "D" },
  r = { [false] = "r", [true] = "R" },
  p = { [false] = "p", [true] = "P" },
  i = { [false] = "i", [true] = "I" },
  c = { [false] = "c", [true] = "C" },
  t = { [false] = "t", [true] = "T" },
}
C.INCLUDED = {}                             -- C.INCLUDED[m][k] for m = 0..7, built at file load:
for m = 0, 7 do
  local afk  = m % 2 == 1
  local inn  = math.floor(m / 2) % 2 == 1
  local city = math.floor(m / 4) % 2 == 1
  local row = {}
  for _, k in ipairs(C.STATE_KEYS) do
    local inc = true
    if k ~= "u" then
      if afk and C.IS_AFK[k] then inc = false end
      if inn and C.IS_INN[k] then inc = false end
      if city and C.IS_CITY[k] then inc = false end
    end
    row[k] = inc
  end
  C.INCLUDED[m] = row
end

-- world
C.CAPITALS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
C.MAPTYPE_ZONE, C.MAPTYPE_DUNGEON = 3, 4    -- used when Enum.UIMapType is missing
C.MAPTYPE_COSMIC, C.MAPTYPE_WORLD, C.MAPTYPE_CONTINENT = 0, 1, 2   -- idem; never zone keys
C.TAU_CHOICES = { 5400, 3600, 1200 }        -- slow, normal, fast

-- media (built-in files only)
C.TEX_WHITE       = "Interface\\Buttons\\WHITE8X8"
C.TEX_CIRCLE_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
C.TEX_TT_BG       = "Interface\\Tooltips\\UI-Tooltip-Background"
C.TEX_TT_BORDER   = "Interface\\Tooltips\\UI-Tooltip-Border"
C.ICON            = "Interface\\Icons\\INV_Misc_PocketWatch_01"

C.COLORS = {
  bg       = { 0.059, 0.067, 0.082, 0.85 },
  border   = { 1, 1, 1, 0.10 },
  track    = { 0.106, 0.118, 0.141, 1 },
  fill     = { 0.545, 0.361, 0.965, 1 },   -- purple accent #8B5CF6 (XP fill)
  fillHi   = { 1, 1, 1, 0.10 },
  restedFill = { 0.0, 0.39, 0.88, 1 },     -- XP fill while rested (the game's rested blue)
  rested   = { 0.231, 0.510, 0.965, 0.45 }, -- rested part, before its gradient is applied
  restTick = { 0.6, 0.75, 1, 0.9 },
  label    = { 0.6, 0.6, 0.6 },
  value    = { 1, 1, 1 },
  dim      = { 0.5, 0.5, 0.55 },
  good     = { 0.35, 0.85, 0.45 },
  warn     = { 1, 0.82, 0.25 },
  bad      = { 1, 0.35, 0.35 },
  pause    = { 1, 0.6, 0.2 },
  accent   = { 0.545, 0.361, 0.965 },
}
C.CC = {                                    -- chat/FontString colour prefixes (constant strings)
  label = "|cff999999", value = "|cffffffff", dim = "|cff80808c",
  good = "|cff59d973", warn = "|cffffd140", bad = "|cffff5959",
  pause = "|cffff9933", accent = "|cff8b5cf6", reset = "|r",
}

-- Opacity of the dark background of the versions with an on/off background
-- (C.COLORS.bg alpha): a stored widget.background == true becomes this bgAlpha.
C.LEGACY_BG_ALPHA = 0.85

C.DEFAULTS = {                              -- account-wide settings (requirement B)
  exclude = { afk = false, inn = false, city = false },
  widget = {
    shown = true,
    style = "bar",                          -- "bar" | "box"
    locked = false,                         -- unlocked on first run to place the bar
    point = { "CENTER", "CENTER", 0, -220 },-- point, relativePoint (UIParent), x, y
    scale = 1.0, width = 360, height = 8, fontSize = 11,
    bgAlpha = 0,                            -- dark background opacity 0..1 (0 = the bar alone)
    textColor = false,                      -- false = built-in colours, else { r, g, b } (0..1)
    xpColor = false,                        -- XP fill: false = built-in purple (C.COLORS.fill), else { r, g, b }
    restedColor = false,                    -- fill while rested + lighter rested part: false = built-in
                                            -- blue (C.COLORS.restedFill), else { r, g, b }
    outline = "thin",                       -- "none" | "thin" | "thick"
    shadow = true,                          -- drop shadow on every text
    qualityColors = true,                   -- FPS / latency in green / yellow / red
    slots = { "eta_kills", "xph", "fps_latency" },    -- 1 top-right, 2 after XP text, 3 top
    maxSlots = { "session", "played", "fps_latency" },
    slot3Pos = "center",                    -- "center" (mockup) | "left"
    pctPos = "follow",                      -- "follow" (mockup marker) | "level"
    combatHide = false, fade = false, hideAtMax = false,
  },
  graph = { window = 60 },                  -- FPS / latency history shown: 30 | 60 | 300 s
  theme = "futuriste",                      -- a C.THEME_CHOICES value (Themes.lua resolves it)
  rateTau = 3600,                           -- 5400 | 3600 | 1200
  requestPlayedAtLogin = true,              -- one visible /played at login if none arrives within 10 s
  hidePlayedMsg = false,                    -- EXPERIMENTAL, default OFF (5.13)
  debug = false,
  firstRunDone = false,
}

---------------------------------------------------------------------------
-- ns.Util (SPEC 3.3)
---------------------------------------------------------------------------
local Util = {}
ns.Util = Util

-- A finite number (not NaN, not +-inf).
local function IsNum(v)
  return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end

function Util.Bump(t, k, n)
  t[k] = (t[k] or 0) + n
end

-- Recursive addition of numbers; creates missing sub-tables; ignores other leaves.
function Util.AddInto(dst, src)
  if type(dst) ~= "table" or type(src) ~= "table" then return dst end
  for k, v in pairs(src) do
    local tv = type(v)
    if tv == "number" then
      local d = dst[k]
      if d == nil then
        dst[k] = v
      elseif type(d) == "number" then
        dst[k] = d + v
      end
    elseif tv == "table" then
      local d = dst[k]
      if d == nil then
        d = {}
        dst[k] = d
      end
      if type(d) == "table" then Util.AddInto(d, v) end
    end
  end
  return dst
end

function Util.DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Util.DeepCopy(x) end
  return out
end

-- Fills missing keys only; array tables ([1] ~= nil) are copied whole when
-- missing and never merged; never overwrites an existing value.
function Util.CopyDefaults(dst, defaults)
  if type(dst) ~= "table" or type(defaults) ~= "table" then return dst end
  for k, dv in pairs(defaults) do
    local cur = dst[k]
    if cur == nil then
      if type(dv) == "table" then
        dst[k] = Util.DeepCopy(dv)
      else
        dst[k] = dv
      end
    elseif type(dv) == "table" and type(cur) == "table" and dv[1] == nil then
      Util.CopyDefaults(cur, dv)
    end
  end
  return dst
end

function Util.IsSecret(v)
  return issecretvalue ~= nil and issecretvalue(v) == true
end

-- ok, value = SafeRead(fn, arg). ok is false when the call failed, the value is
-- nil or secret. The secret test comes BEFORE any other test of the value.
-- A third return tells why a read failed ("error", "secret" or "nil"; constant
-- strings) so callers can tell "no value" (e.g. GetXPExhaustion with no rest)
-- from "secret".
local WHY_ERROR, WHY_SECRET, WHY_NIL = "error", "secret", "nil"
function Util.SafeRead(fn, arg)
  if fn == nil then return false, nil, WHY_ERROR end
  local ok, v = pcall(fn, arg)
  if not ok then return false, nil, WHY_ERROR end
  if issecretvalue ~= nil and issecretvalue(v) == true then return false, nil, WHY_SECRET end
  if v == nil then return false, nil, WHY_NIL end
  return true, v
end

-- One guarded API read: the value, or nil when the API is missing, fails or is secret.
local function GuardedCall(fn, arg)
  if fn == nil then return nil end
  local ok, v = pcall(fn, arg)
  if not ok or (issecretvalue ~= nil and issecretvalue(v) == true) then return nil end
  return v
end

local function AtOrAbove(level, maxLevel)
  return type(maxLevel) == "number" and maxLevel > 0 and level >= maxLevel
end

-- The client's max level, with layered checks (as EllesmereUI's XP bar): XP disabled,
-- the "effective max level" helpers, then the expansion and player max levels. Never a
-- hard-coded 60 (Forever may raise the cap). A server cap the client does not know
-- about (the Forever beta: level 20 while every API says 60) is the Tracker's business
-- (Tracker.IsMax, detected cap). Every read is guarded (missing, error, secret).
function Util.IsMaxLevel()
  if GuardedCall(IsXPUserDisabled) == true then return true end
  if GuardedCall(IsPlayerAtEffectiveMaxLevel) == true then return true end
  local level = GuardedCall(UnitLevel, "player")
  if type(level) ~= "number" then return false end
  if GuardedCall(IsLevelAtEffectiveMaxLevel, level) == true then return true end
  if AtOrAbove(level, GuardedCall(GetMaxLevelForPlayerExpansion)) then return true end
  return AtOrAbove(level, GuardedCall(GetMaxPlayerLevel))
end

-- "Name Surname" on Forever, "Name" elsewhere. Allocates: UI only.
function Util.CharName(char)
  if type(char) ~= "table" then return "?" end
  local name = char.name
  if type(name) ~= "string" or name == "" then name = "?" end
  local surname = char.surname
  if type(surname) == "string" and surname ~= "" then
    return name .. " " .. surname
  end
  return name
end

function Util.Print(fmt, ...)
  local text = fmt
  if select("#", ...) > 0 then text = string_format(fmt, ...) end
  if type(text) ~= "string" then text = tostring(text) end
  local frame = DEFAULT_CHAT_FRAME          -- read at call time (other addons replace it)
  if frame and frame.AddMessage then
    frame:AddMessage(L.CHAT_PREFIX .. text)
  end
end

local DEBUG_TAG = "|cff80808c[debug]|r "
-- No-op unless the debug setting is on: callers pass raw values, the string is
-- only built here, so a disabled Debug call allocates nothing.
function Util.Debug(fmt, ...)
  local s = ns.settings
  if not (s and s.debug) then return end
  local n = select("#", ...)
  local text
  if n == 0 then
    text = tostring(fmt)
  else
    local ok, res = pcall(string_format, fmt, ...)
    if ok then
      text = res
    else
      -- e.g. nil passed to %s on Lua 5.1: dump the raw values instead
      local parts = { tostring(fmt) }
      for i = 1, n do parts[#parts + 1] = tostring((select(i, ...))) end
      text = table_concat(parts, " ")
    end
  end
  local frame = DEFAULT_CHAT_FRAME
  if frame and frame.AddMessage then
    frame:AddMessage(L.CHAT_PREFIX .. DEBUG_TAG .. text)
  end
end

function Util.Round(x)
  return math_floor(x + 0.5)
end

function Util.Clamp(x, lo, hi)
  if x < lo then return lo end
  if x > hi then return hi end
  return x
end

-- Lowercased, trimmed words for slash parsing. w1 is always a string ("" for an
-- empty message); w2 and w3 are nil when absent.
function Util.Words(msg)
  if type(msg) ~= "string" then msg = "" end
  local w1, w2, w3 = msg:lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
  if w2 == "" then w2 = nil end
  if w3 == "" then w3 = nil end
  return w1 or "", w2, w3
end

---------------------------------------------------------------------------
-- Error isolation (SPEC 2.7)
---------------------------------------------------------------------------
local SafeCall
if securecallfunction then
  SafeCall = securecallfunction
else
  local function after(ok, ...)
    if not ok then
      local handler = geterrorhandler and geterrorhandler()
      if handler then handler((...)) end
      return
    end
    return ...
  end
  SafeCall = function(fn, ...)
    return after(pcall(fn, ...))
  end
end
ns.SafeCall = SafeCall

---------------------------------------------------------------------------
-- Event and message bus (SPEC 3.4, FROZEN)
-- One list per event/message name: parallel arrays of owners and handlers.
-- Removal leaves a tombstone (false) that is compacted outside dispatch, so a
-- removed handler is never called and a handler added during a dispatch waits
-- for the next one. Dispatch allocates nothing.
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventLists, messageLists = {}, {}

local function NewList()
  return { owners = {}, fns = {}, n = 0, live = 0, depth = 0, dirty = false }
end

local function Compact(list)
  local owners, fns = list.owners, list.fns
  local n, j = list.n, 0
  for i = 1, n do
    local fn = fns[i]
    if fn then
      j = j + 1
      owners[j] = owners[i]
      fns[j] = fn
    end
  end
  for i = j + 1, n do
    owners[i] = nil
    fns[i] = nil
  end
  list.n = j
  list.dirty = false
end

local function FindLive(list, owner)
  local owners, fns = list.owners, list.fns
  for i = 1, list.n do
    if fns[i] and owners[i] == owner then return i end
  end
  return nil
end

local function AddHandler(list, owner, fn)
  local i = FindLive(list, owner)
  if i then
    list.fns[i] = fn                      -- same (name, owner): replace in place
    return
  end
  local n = list.n + 1
  list.n = n
  list.owners[n] = owner
  list.fns[n] = fn
  list.live = list.live + 1
end

local function RemoveHandler(list, owner)
  local i = FindLive(list, owner)
  if not i then return false end
  list.fns[i] = false
  list.live = list.live - 1
  list.dirty = true
  if list.depth == 0 then Compact(list) end
  return true
end

local function Dispatch(list, name, ...)
  local n = list.n
  if n == 0 then return end
  local fns = list.fns
  list.depth = list.depth + 1
  for i = 1, n do
    local fn = fns[i]
    if fn then SafeCall(fn, name, ...) end
  end
  list.depth = list.depth - 1
  if list.dirty and list.depth == 0 then Compact(list) end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = eventLists[event]
  if list and list.live > 0 then Dispatch(list, event, ...) end
end)

function ns.RegisterEvent(event, owner, fn)
  if type(event) ~= "string" or owner == nil or type(fn) ~= "function" then
    Util.Debug("RegisterEvent: bad arguments for %s", tostring(event))
    return false
  end
  local list = eventLists[event]
  if not list then
    list = NewList()
    eventLists[event] = list
  end
  if list.live == 0 then
    local ok, res = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok or res == false then
      Util.Debug("RegisterEvent: %s is not known on this client", event)
      return false
    end
  end
  AddHandler(list, owner, fn)
  return true
end

function ns.UnregisterEvent(event, owner)
  local list = eventLists[event]
  if not list then return end
  if RemoveHandler(list, owner) and list.live == 0 then
    eventFrame:UnregisterEvent(event)
  end
end

function ns.RegisterMessage(msg, owner, fn)
  if msg == nil or owner == nil or type(fn) ~= "function" then
    Util.Debug("RegisterMessage: bad arguments for %s", tostring(msg))
    return
  end
  local list = messageLists[msg]
  if not list then
    list = NewList()
    messageLists[msg] = list
  end
  AddHandler(list, owner, fn)
end

function ns.UnregisterMessage(msg, owner)
  local list = messageLists[msg]
  if list then RemoveHandler(list, owner) end
end

function ns.SendMessage(msg, ...)
  local list = messageLists[msg]
  if list and list.live > 0 then Dispatch(list, msg, ...) end
end

---------------------------------------------------------------------------
-- Cached exclusion mask (SPEC 3.1)
---------------------------------------------------------------------------
local mask = 0

local function RecomputeMask()
  local s = ns.settings
  local ex = type(s) == "table" and s.exclude
  if type(ex) ~= "table" then
    mask = 0
    return
  end
  mask = (ex.afk == true and C.MASK_AFK or 0) + (ex.inn == true and C.MASK_INN or 0) + (ex.city == true and C.MASK_CITY or 0)
end

function ns.GetMask()
  return mask
end

---------------------------------------------------------------------------
-- ns.Core: constructors (SPEC 3.6, 4.1)
---------------------------------------------------------------------------
local Core = {}
ns.Core = Core

Core.MIGRATIONS = {}   -- [n] = function(db): upgrades schema n-1 to n (empty in v0.1)

function Core.NewBucket()
  return { s = {}, xp = 0, d = 0 }
end

function Core.NewLife()
  return { s = {}, xp = 0, xa = 0, xr = 0, xq = 0, d = 0, est = 0 }
end

-- The ONLY constructor for level records, including partial ones (critique #4).
function Core.NewLevel()
  return { s = {}, z = {}, xp = 0, xa = 0, xr = 0, xq = 0, d = 0 }
end

function Core.NewZone()
  return { s = {}, xp = 0 }
end

-- 8 entries, index = mask + 1.
function Core.NewEma()
  local e = {}
  for i = 1, 8 do e[i] = { a = 0, r = 0, q = 0, d = 0 } end
  return e
end

function Core.NewSession()
  local now = time()
  local level = UnitLevel("player")
  if type(level) ~= "number" or level <= 0 then level = nil end
  -- p0 stays nil until the first valid XP baseline (Tracker, 5.9)
  return { t0 = now, l0 = level, p0 = nil, s = {}, xp = 0, d = 0, at = now, g = GetTime() }
end

function Core.NewDB()
  return {
    schema = C.SCHEMA,
    createdAt = time(),
    settings = Util.DeepCopy(C.DEFAULTS),
    cities = {},
    xpMax = {},
    chars = {},
  }
end

-- Identity fields of the logged-in player (Unit APIs are only valid for "player").
local function RefreshIdentity(char)
  local name, surname = UnitName("player")
  if type(name) == "string" and name ~= "" then
    char.name = name
    if type(surname) == "string" and surname ~= "" then
      char.surname = surname
    else
      char.surname = nil
    end
  end
  local realm = GetRealmName and GetRealmName()
  if type(realm) == "string" and realm ~= "" then char.realm = realm end
  local _, class = UnitClass("player")
  if type(class) == "string" and class ~= "" then char.class = class end
  local faction = UnitFactionGroup("player")
  if type(faction) == "string" and faction ~= "" then char.faction = faction end
end

function Core.NewCharRecord(guid)
  local now = time()
  local char = {
    guid = guid,
    firstSeen = now,
    lastSeen = now,
    life = Core.NewLife(),
    levels = {},
    zones = {},
    sessions = {},
    ema = Core.NewEma(),
    -- base, srv, xpSnap, cur, last: nil until the Tracker writes them
  }
  if guid ~= nil and guid == UnitGUID("player") then
    RefreshIdentity(char)
    local level = UnitLevel("player")
    if type(level) == "number" and level > 0 then char.level = level end
  end
  return char
end

---------------------------------------------------------------------------
-- Repair (SPEC 4.6): SavedVariables can be truncated by crashes. Never raise,
-- always rebuild a well-formed shape.
---------------------------------------------------------------------------
local LIFE_FIELDS    = { "xp", "xa", "xr", "xq", "d", "est" }
local LEVEL_FIELDS   = { "xp", "xa", "xr", "xq", "d" }
local ZONE_FIELDS    = { "xp" }
local SESSION_FIELDS = { "xp", "d" }
local LEVEL_OPTIONAL = { "est", "max", "t0", "t1", "srvStart", "srvEnd" }
local EMA_FIELDS     = { "a", "r", "q", "d" }
local CHAR_TABLES    = { "base", "srv", "xpSnap", "cur", "last" }

-- Seconds maps: drop every value that is not a number (NaN included). Inline
-- test: this loop visits every stored second counter of every character.
local function RepairS(s)
  for k, v in pairs(s) do
    if type(v) ~= "number" or v ~= v then s[k] = nil end
  end
end

local function RepairBucket(b, fields)
  if type(b.s) ~= "table" then b.s = {} else RepairS(b.s) end
  for i = 1, #fields do
    local f = fields[i]
    if not IsNum(b[f]) then b[f] = 0 end
  end
end

-- Optional stalled-time map (life.xs, levels[L].xs: seconds per state key without XP
-- for a long while, shaped like `s`): removed unless a table; bad or negative values
-- dropped. Never created here (the Tracker creates it on the first stalled second).
local function RepairXS(b)
  local xs = b.xs
  if xs == nil then return end
  if type(xs) ~= "table" then
    b.xs = nil
    return
  end
  for k, v in pairs(xs) do
    if type(k) ~= "string" or not IsNum(v) or v < 0 then xs[k] = nil end
  end
end

local function RepairZoneMap(map)
  for k, z in pairs(map) do
    if type(z) ~= "table" then
      map[k] = nil
    else
      RepairBucket(z, ZONE_FIELDS)
      if z.name ~= nil and type(z.name) ~= "string" then z.name = nil end
    end
  end
end

local function RepairSessions(char)
  local sessions = char.sessions
  if type(sessions) ~= "table" then
    char.sessions = {}
    return
  end
  -- Fast path (the normal case): a clean array of tables. Trim the oldest.
  local n, count, clean = #sessions, 0, true
  for k, v in pairs(sessions) do
    count = count + 1
    if type(k) ~= "number" or type(v) ~= "table" then clean = false end
  end
  if clean and count == n then
    while #sessions > C.SESSION_RING do table.remove(sessions, 1) end
    for i = 1, #sessions do RepairBucket(sessions[i], SESSION_FIELDS) end
    return
  end
  -- Slow path: holes or junk entries; rebuild in key order.
  local keys = {}
  for k, v in pairs(sessions) do
    if type(k) == "number" and type(v) == "table" then keys[#keys + 1] = k end
  end
  table_sort(keys)
  local entries = {}
  for i = 1, #keys do entries[i] = sessions[keys[i]] end
  for k in pairs(sessions) do sessions[k] = nil end
  local first = #entries - C.SESSION_RING + 1   -- keep the newest entries of the ring
  if first < 1 then first = 1 end
  for i = first, #entries do
    local e = entries[i]
    RepairBucket(e, SESSION_FIELDS)
    sessions[#sessions + 1] = e
  end
end

local function RepairEma(char)
  local ema = char.ema
  if type(ema) ~= "table" then
    char.ema = Core.NewEma()
    return
  end
  for k in pairs(ema) do
    if type(k) ~= "number" or k < 1 or k > 8 or k % 1 ~= 0 then ema[k] = nil end
  end
  for i = 1, 8 do
    local e = ema[i]
    if type(e) ~= "table" then
      ema[i] = { a = 0, r = 0, q = 0, d = 0 }
    else
      for j = 1, #EMA_FIELDS do
        local f = EMA_FIELDS[j]
        local v = e[f]
        if not IsNum(v) or v < 0 then e[f] = 0 end
      end
    end
  end
end

-- Records already repaired during this UI load (weak keys): EnsureChar skips a
-- second full pass right after RepairDB.
local repaired = setmetatable({}, { __mode = "k" })

function Core.RepairChar(char)
  if type(char) ~= "table" then return char end
  repaired[char] = true

  if type(char.life) ~= "table" then
    char.life = Core.NewLife()
  else
    RepairBucket(char.life, LIFE_FIELDS)
    RepairXS(char.life)
  end

  local levels = char.levels
  if type(levels) ~= "table" then
    char.levels = {}
  else
    for lvl, lb in pairs(levels) do
      if type(lvl) ~= "number" or type(lb) ~= "table" then
        levels[lvl] = nil
      else
        RepairBucket(lb, LEVEL_FIELDS)
        RepairXS(lb)
        if type(lb.z) ~= "table" then lb.z = {} else RepairZoneMap(lb.z) end
        for i = 1, #LEVEL_OPTIONAL do
          local f = LEVEL_OPTIONAL[i]
          if lb[f] ~= nil and not IsNum(lb[f]) then lb[f] = nil end
        end
      end
    end
  end

  if type(char.zones) ~= "table" then char.zones = {} else RepairZoneMap(char.zones) end
  RepairSessions(char)
  RepairEma(char)

  for i = 1, #CHAR_TABLES do
    local f = CHAR_TABLES[i]
    if char[f] ~= nil and type(char[f]) ~= "table" then char[f] = nil end
  end
  if char.cur then RepairBucket(char.cur, SESSION_FIELDS) end
  if char.srv and not IsNum(char.srv.total) then char.srv = nil end
  local base = char.base
  if base and not IsNum(base.total) then
    char.base = nil
  elseif base and base.lp ~= nil and not (IsNum(base.lp) and base.lp >= 0 and base.lp <= base.total) then
    base.lp = nil     -- server level time at the install (prior v2)
  end
  local snap = char.xpSnap
  if snap and not (IsNum(snap.level) and IsNum(snap.xp) and IsNum(snap.max)) then char.xpSnap = nil end
  if char.level ~= nil and not IsNum(char.level) then char.level = nil end
  -- prior = { xph, at, v }: pre-install XP/h estimate (optional, Tracker 5.11); v = 2 when
  -- computed from the completed levels only (any other v is dropped: recomputed)
  local prior = char.prior
  if prior ~= nil then
    if type(prior) ~= "table" or not IsNum(prior.xph) or prior.xph <= 0 or prior.xph > C.PRIOR_MAX_XPH then
      char.prior = nil
    else
      if prior.at ~= nil and not IsNum(prior.at) then prior.at = nil end
      if prior.v ~= nil and prior.v ~= 2 then prior.v = nil end
    end
  end
  -- noXP: counted non-AFK seconds since the last XP gain (stall guard); capLevel: level
  -- at which a server level cap was detected (both optional, Tracker)
  if char.noXP ~= nil and not (IsNum(char.noXP) and char.noXP >= 0) then char.noXP = nil end
  local cap = char.capLevel
  if cap ~= nil and not (IsNum(cap) and cap >= 1 and cap % 1 == 0) then char.capLevel = nil end
  -- lastKill = { xp, level, at }: base XP of the last mob killed (Tracker, mobs to go)
  local lk = char.lastKill
  if lk ~= nil then
    if type(lk) ~= "table" or not IsNum(lk.xp) or lk.xp <= 0 or lk.xp > C.KILL_XP_MAX then
      char.lastKill = nil
    else
      lk.xp = math_floor(lk.xp + 0.5)
      if lk.level ~= nil and not (IsNum(lk.level) and lk.level >= 1) then lk.level = nil end
      if lk.at ~= nil and not IsNum(lk.at) then lk.at = nil end
    end
  end
  return char
end

---------------------------------------------------------------------------
-- Settings (SPEC 3.17): one table of accepted paths with their validation.
---------------------------------------------------------------------------
local TOKEN_IDS = {   -- Tokens.ORDER (SPEC 3.11), used when Tokens.lua is absent
  none = true, eta = true, xph = true, pcth = true, xpleft = true, rested = true,
  level_time = true, session = true, played = true, played_server = true,
  afk_session = true, avg_level = true, zone_time = true, fps = true,
  latency = true, fps_latency = true,
  kills = true, eta_kills = true, instance_session = true, instance_total = true,
}
local VALID_POINTS = {
  TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
  RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local SETTINGS = {}   -- path -> { kind, parents = { seg... }, leaf, ... }

local function DefineSetting(path, kind, spec)
  spec = spec or {}
  spec.kind = kind
  spec.path = path
  local parts = {}
  for seg in path:gmatch("[^%.]+") do parts[#parts + 1] = tonumber(seg) or seg end
  spec.leaf = parts[#parts]
  parts[#parts] = nil
  spec.parents = parts
  SETTINGS[path] = spec
end

local function SetOf(list)          -- { a, b } -> { [a] = true, [b] = true } (load time only)
  local set = {}
  for i = 1, #list do set[list[i]] = true end
  return set
end

DefineSetting("exclude.afk", "bool", { mask = true })
DefineSetting("exclude.inn", "bool", { mask = true })
DefineSetting("exclude.city", "bool", { mask = true })
DefineSetting("widget.shown", "bool")
DefineSetting("widget.locked", "bool")
DefineSetting("widget.combatHide", "bool")
DefineSetting("widget.fade", "bool")
DefineSetting("widget.hideAtMax", "bool")
DefineSetting("widget.shadow", "bool")
DefineSetting("widget.qualityColors", "bool")
DefineSetting("widget.style", "enum", { values = { bar = true, box = true } })
DefineSetting("widget.outline", "enum", { values = SetOf(C.OUTLINES) })
DefineSetting("widget.point", "point")
DefineSetting("widget.scale", "num", { min = 0.5, max = 2.0, inv = 20 })   -- step 0.05
DefineSetting("widget.width", "num", { min = 150, max = 600, step = 10 })
DefineSetting("widget.height", "num", { min = 4, max = 16, step = 1 })
DefineSetting("widget.fontSize", "num", { min = 9, max = 16, step = 1 })
DefineSetting("widget.bgAlpha", "num", { min = 0, max = 1, inv = 20 })     -- step 0.05
DefineSetting("widget.textColor", "color")
DefineSetting("widget.xpColor", "color")
DefineSetting("widget.restedColor", "color")
for i = 1, 3 do
  DefineSetting("widget.slots." .. i, "token")
  DefineSetting("widget.maxSlots." .. i, "token")
end
DefineSetting("widget.slot3Pos", "enum", { values = { center = true, left = true } })
DefineSetting("widget.pctPos", "enum", { values = { follow = true, level = true } })
DefineSetting("graph.window", "choice", { values = SetOf(C.GRAPH_WINDOWS) })
DefineSetting("theme", "theme", { values = SetOf(C.THEME_CHOICES) })
DefineSetting("rateTau", "choice", { values = { [5400] = true, [3600] = true, [1200] = true } })
DefineSetting("requestPlayedAtLogin", "bool")
DefineSetting("hidePlayedMsg", "bool")
DefineSetting("debug", "bool")
DefineSetting("firstRunDone", "bool")

local function IsKnownToken(id)
  local Tokens = ns.Tokens
  if Tokens and type(Tokens.DEF) == "table" then return Tokens.DEF[id] ~= nil end
  return TOKEN_IDS[id] == true
end

-- Returns the normalized (clamped / rounded) value, or nil when invalid.
-- strict = true for SetSetting (token ids must be known); false for repair
-- (an id from a newer version is kept; Tokens.Resolve falls back at read time).
local function Normalize(spec, v, strict)
  local kind = spec.kind
  if kind == "bool" then
    if type(v) == "boolean" then return v end
    return nil
  elseif kind == "num" then
    if not IsNum(v) then return nil end
    if spec.inv then
      v = Util.Round(v * spec.inv) / spec.inv    -- exact decimal steps (0.05)
    else
      v = Util.Round(v / spec.step) * spec.step
    end
    return Util.Clamp(v, spec.min, spec.max)
  elseif kind == "enum" then
    if type(v) == "string" and spec.values[v] then return v end
    return nil
  elseif kind == "choice" then
    if IsNum(v) and spec.values[v] then return v end
    return nil
  elseif kind == "token" then
    if type(v) ~= "string" then return nil end
    if strict and not IsKnownToken(v) then return nil end
    return v
  elseif kind == "theme" then
    -- strict: one of C.THEME_CHOICES; repair: any plausible key is kept (written by a
    -- newer version; Themes.Resolve falls back at read time)
    if type(v) ~= "string" then return nil end
    if strict then
      if spec.values[v] then return v end
      return nil
    end
    if #v <= 24 and v:find("^[%a_]+$") then return v end
    return nil
  elseif kind == "point" then
    if type(v) ~= "table" then return nil end
    local p, rp, x, y = v[1], v[2], v[3], v[4]
    if rp == nil then rp = p end
    if not (VALID_POINTS[p] and VALID_POINTS[rp] and IsNum(x) and IsNum(y)) then return nil end
    return { p, rp, Util.Round(x), Util.Round(y) }
  elseif kind == "color" then
    -- false = built-in colours; else { r, g, b } (an { r =, g =, b = } table is
    -- accepted too) stored as an array of 0..1 numbers rounded to 3 decimals
    if v == false then return false end
    if type(v) ~= "table" then return nil end
    local r, g, bl = v[1], v[2], v[3]
    if r == nil and g == nil and bl == nil then r, g, bl = v.r, v.g, v.b end
    if not (IsNum(r) and IsNum(g) and IsNum(bl)) then return nil end
    return { Util.Round(Util.Clamp(r, 0, 1) * 1000) / 1000, Util.Round(Util.Clamp(g, 0, 1) * 1000) / 1000,
             Util.Round(Util.Clamp(bl, 0, 1) * 1000) / 1000 }
  end
  return nil
end

local function SameValue(a, b)
  if a == b then return true end
  if type(a) == "table" and type(b) == "table" then
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
  end
  return false
end

-- C.DEFAULTS walked along the first `depth` parent segments of a path.
local function DefaultNode(spec, depth)
  local node = C.DEFAULTS
  local parents = spec.parents
  for i = 1, depth do
    if type(node) ~= "table" then return nil end
    node = node[parents[i]]
  end
  return node
end

-- Default value of the leaf of a path.
local function DefaultLeaf(spec)
  local node = DefaultNode(spec, #spec.parents)
  if type(node) ~= "table" then return nil end
  return node[spec.leaf]
end

-- Settings whose value may be a table although the default is not (false = built-in
-- colours, else { r, g, b }): their own validation (Normalize) decides.
local FLEX_TYPES = { textColor = true, xpColor = true, restedColor = true }

-- Replaces values whose type differs from the default (e.g. a string where a
-- table is expected); recurses into non-array tables.
local function FixTypes(dst, defaults)
  for k, dv in pairs(defaults) do
    local cur = dst[k]
    if cur ~= nil and type(cur) ~= type(dv) then
      if not FLEX_TYPES[k] then dst[k] = Util.DeepCopy(dv) end
    elseif type(dv) == "table" and type(cur) == "table" and dv[1] == nil then
      FixTypes(cur, dv)
    end
  end
end

-- widget.background (on/off dark background, up to 0.1.0-beta) became the
-- widget.bgAlpha opacity: a background that was on keeps the opacity it had.
local function MigrateBackground(settings)
  local w = settings.widget
  if type(w) ~= "table" or w.background == nil then return end
  if w.background == true and w.bgAlpha == nil then w.bgAlpha = C.LEGACY_BG_ALPHA end
  w.background = nil
end

-- Full settings repair: renamed values, types, missing keys, then every known
-- path validated (invalid -> default, out of range -> clamped).
local function RepairSettings(settings)
  MigrateBackground(settings)
  FixTypes(settings, C.DEFAULTS)
  Util.CopyDefaults(settings, C.DEFAULTS)
  for _, spec in pairs(SETTINGS) do
    local node = settings
    local parents = spec.parents
    for i = 1, #parents do
      local child = node[parents[i]]
      if type(child) ~= "table" then
        child = {}
        node[parents[i]] = child
      end
      node = child
    end
    local cur = node[spec.leaf]
    local nv = Normalize(spec, cur, false)
    if nv == nil then
      node[spec.leaf] = Util.DeepCopy(DefaultLeaf(spec))
    elseif not SameValue(nv, cur) then
      node[spec.leaf] = nv
    end
  end
  return settings
end

-- Settings are saved sparsely (PLAYER_LOGOUT): only the values that differ from
-- C.DEFAULTS reach the file, so a default changed in a later version reaches
-- every user who never touched that setting. Tables saved in full by earlier
-- versions (no db.sparseSettings mark) hold the defaults of their time: a value
-- equal to an OLD default that has changed since was not chosen by the user and
-- takes the current default.
local function SameDeep(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not SameDeep(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local LEGACY_DEFAULTS = {            -- defaults of the versions that saved settings in full (up to 0.1.0-test)
  { path = { "widget", "background" }, old = true },   -- removed since (widget.bgAlpha, default 0)
  { path = { "widget", "slots" }, old = { "eta", "xph", "fps_latency" } },
}

-- A value equal to its old default becomes the current default (removed when the
-- setting no longer exists).
local function ApplyLegacyDefaults(settings)
  for i = 1, #LEGACY_DEFAULTS do
    local rec = LEGACY_DEFAULTS[i]
    local path = rec.path
    local node, def = settings, C.DEFAULTS
    for j = 1, #path - 1 do
      if type(node) ~= "table" then break end
      node = node[path[j]]
      if type(def) == "table" then def = def[path[j]] end
    end
    local leaf = path[#path]
    if type(node) == "table" and SameDeep(node[leaf], rec.old) then
      local current = nil
      if type(def) == "table" then current = def[leaf] end
      node[leaf] = Util.DeepCopy(current)
    end
  end
end

-- Copy of src without the values equal to their default (nil when nothing is
-- left). Settings sub-tables (exclude, widget) are walked; arrays (point, slots)
-- and unknown keys are kept or dropped whole. Logout only (allocates).
local function SparseCopy(src, defaults)
  local out
  for k, v in pairs(src) do
    local dv
    if type(defaults) == "table" then dv = defaults[k] end
    local keep
    if type(v) == "table" and type(dv) == "table" and dv[1] == nil and next(dv) ~= nil then
      keep = SparseCopy(v, dv)
    elseif not SameDeep(v, dv) then
      keep = Util.DeepCopy(v)
    end
    if keep ~= nil then
      out = out or {}
      out[k] = keep
    end
  end
  return out
end

-- In-memory settings for readOnly (SPEC 5.18: nothing written on the real table).
local function ReadOnlySettings(db)
  local src = type(db.settings) == "table" and db.settings or {}
  return RepairSettings(Util.DeepCopy(src))
end

function Core.GetSetting(path)
  local s = ns.settings
  if type(s) ~= "table" or type(path) ~= "string" then return nil end
  local spec = SETTINGS[path]
  local node = s
  if spec then
    local parents = spec.parents
    for i = 1, #parents do
      node = node[parents[i]]
      if type(node) ~= "table" then return nil end
    end
    return node[spec.leaf]
  end
  for seg in path:gmatch("[^%.]+") do
    if type(node) ~= "table" then return nil end
    node = node[tonumber(seg) or seg]
  end
  return node
end

function Core.SetSetting(path, value)
  local spec = SETTINGS[path]
  if not spec then
    Util.Debug("SetSetting: unknown path %s", tostring(path))
    return false
  end
  local s = ns.settings
  if type(s) ~= "table" then return false end
  local v = Normalize(spec, value, true)
  if v == nil then
    Util.Debug("SetSetting: invalid value %s for %s", tostring(value), path)
    return false
  end
  local node = s
  local parents = spec.parents
  for i = 1, #parents do
    local child = node[parents[i]]
    if type(child) ~= "table" then
      local def = DefaultNode(spec, i)
      child = type(def) == "table" and Util.DeepCopy(def) or {}
      node[parents[i]] = child
    end
    node = child
  end
  if SameValue(node[spec.leaf], v) then return false end
  node[spec.leaf] = v
  if spec.mask then RecomputeMask() end
  ns.SendMessage("SETTINGS_CHANGED", path, v)
  return true
end

---------------------------------------------------------------------------
-- Migration, repair and character records (SPEC 3.6, 4.6)
---------------------------------------------------------------------------
local function IsNewer(db)
  local schema = tonumber(db.schema)
  return schema ~= nil and schema > C.SCHEMA
end

function Core.RepairDB(db)
  if type(db) ~= "table" then return end
  if type(db.settings) ~= "table" then db.settings = {} end
  if db.sparseSettings ~= true then
    db.sparseSettings = nil
    ApplyLegacyDefaults(db.settings)   -- a table saved in full by an earlier version
  end
  RepairSettings(db.settings)

  if type(db.cities) ~= "table" then db.cities = {} end
  for id, v in pairs(db.cities) do
    if type(id) ~= "number" or type(v) ~= "boolean" then db.cities[id] = nil end
  end

  if type(db.xpMax) ~= "table" then db.xpMax = {} end
  for lvl, v in pairs(db.xpMax) do
    if type(lvl) ~= "number" or not IsNum(v) or v <= 0 then db.xpMax[lvl] = nil end
  end

  if type(db.chars) ~= "table" then db.chars = {} end
  for guid, char in pairs(db.chars) do
    if type(guid) ~= "string" or type(char) ~= "table" then
      db.chars[guid] = nil
    else
      if char.guid ~= guid then char.guid = guid end
      Core.RepairChar(char)
    end
  end

  if not IsNum(db.createdAt) then db.createdAt = time() end
end

function Core.Migrate(db)
  if type(db) ~= "table" then return false end
  local schema = tonumber(db.schema)
  if schema == nil or schema < 1 then schema = 1 end   -- nil (with or without chars) = 1
  schema = math_floor(schema)
  if schema > C.SCHEMA then return false end
  for n = schema + 1, C.SCHEMA do
    local migrate = Core.MIGRATIONS[n]
    if migrate then migrate(db) end
  end
  db.schema = C.SCHEMA
  Core.RepairDB(db)
  return true
end

-- A memory-only record for readOnly: a repaired copy of the stored record, or a
-- new one. Never inserted into db.chars, so nothing can reach the real table.
local function DetachedChar(db, guid)
  local rec = type(db.chars) == "table" and db.chars[guid] or nil
  if type(rec) == "table" then
    local copy = Util.DeepCopy(rec)
    copy.guid = guid
    return Core.RepairChar(copy)
  end
  return Core.NewCharRecord(guid)
end

function Core.EnsureChar(db, guid)
  if type(db) ~= "table" or guid == nil then return nil end
  if ns.readOnly then return DetachedChar(db, guid) end   -- never creates in readOnly
  if type(db.chars) ~= "table" then db.chars = {} end
  local char = db.chars[guid]
  if type(char) ~= "table" then
    char = Core.NewCharRecord(guid)
    db.chars[guid] = char
    return char
  end
  char.guid = guid
  if not repaired[char] then Core.RepairChar(char) end
  if guid == UnitGUID("player") then
    RefreshIdentity(char)
    char.lastSeen = time()
  end
  return char
end

---------------------------------------------------------------------------
-- Resets (SPEC 5.20)
---------------------------------------------------------------------------
local IDENTITY_FIELDS = { "guid", "name", "surname", "realm", "class", "faction" }

function Core.ResetChar(guid)
  if ns.readOnly or type(ns.db) ~= "table" then return false end
  local cur = ns.char
  local curGuid = cur and cur.guid
  if guid == nil then guid = curGuid end
  if guid == nil then return false end
  local chars = ns.db.chars
  if type(chars) ~= "table" then return false end

  local name
  if guid ~= curGuid then
    local rec = chars[guid]
    if type(rec) ~= "table" then return false end
    name = Util.CharName(rec)
    chars[guid] = nil
  else
    -- Rebuild the current record IN PLACE (the Tracker and the UI keep this table).
    local keep = {}
    for i = 1, #IDENTITY_FIELDS do
      local f = IDENTITY_FIELDS[i]
      keep[f] = cur[f]
    end
    local fresh = Core.NewCharRecord(guid)
    for k in pairs(cur) do cur[k] = nil end
    for k, v in pairs(fresh) do cur[k] = v end
    for k, v in pairs(keep) do cur[k] = v end
    cur.firstSeen = time()
    cur.lastSeen = cur.firstSeen
    chars[guid] = cur
    name = Util.CharName(cur)

    local Tracker = ns.Tracker
    if Tracker and Tracker.OnCharReset then SafeCall(Tracker.OnCharReset) end
    local Played = ns.Played
    if Played and Played.Request then SafeCall(Played.Request, "reset") end
  end

  ns.SendMessage("CHAR_RESET", guid)
  Util.Print(L.RESET_CHAR_DONE_FMT, name)
  return true
end

function Core.ResetRate()
  if ns.readOnly or type(ns.char) ~= "table" then return false end
  ns.char.ema = Core.NewEma()
  ns.SendMessage("XP_CHANGED")
  return true
end

function Core.IsReady()
  return ns.ready == true
end

---------------------------------------------------------------------------
-- Late SavedVariables swap (SPEC 5.16)
---------------------------------------------------------------------------
local schemaWarned = false
local function WarnReadOnly()
  if schemaWarned then return end
  schemaWarned = true
  Util.Print(L.SCHEMA_NEWER)
end

local function InvalidateCaches()
  local Tracker, Stats = ns.Tracker, ns.Stats
  if Tracker and Tracker.InvalidateZoneCache then SafeCall(Tracker.InvalidateZoneCache) end
  if Stats and Stats.ResetCaches then SafeCall(Stats.ResetCaches) end
end

local function CurrentGuid()
  local char = ns.char
  return (char and char.guid) or UnitGUID("player")
end

-- Step 9: re-apply this load's server sync to the new table (projected to now).
-- ApplyReconcile is not part of the frozen interface, so it goes through
-- Tracker.ReconcileServer with the projected values.
local function ReapplySync(Tracker)
  if not (Tracker and Tracker.GetSync and Tracker.ReconcileServer) then return end
  local sync = Tracker.GetSync()
  if not (sync and sync.valid and not sync.restored and IsNum(sync.total) and IsNum(sync.g)) then return end
  local elapsed = GetTime() - sync.g
  if elapsed < 0 then elapsed = 0 end
  local total = math_floor(sync.total + elapsed + 0.5)
  local levelPlayed
  if sync.levelValid and IsNum(sync.levelPlayed) then
    local level
    if Tracker.GetState then
      local _, _, lv = Tracker.GetState()
      level = lv
    end
    if level == nil or sync.level == level then
      levelPlayed = math_floor(sync.levelPlayed + elapsed + 0.5)
    end
  end
  SafeCall(Tracker.ReconcileServer, total, levelPlayed)
end

local function DoSwap(g)
  local guid = CurrentGuid()
  local Tracker = ns.Tracker

  if IsNewer(g) then                 -- data from a newer TruePlayed: read-only from now on
    ns.db = g
    ns.readOnly = true
    ns.settings = ReadOnlySettings(g)
    ns.char = DetachedChar(g, guid)
    RecomputeMask()
    WarnReadOnly()
    InvalidateCaches()
    ns.SendMessage("DB_SWAPPED")
    return
  end

  local oldDb = ns.db
  Core.Migrate(g)
  Util.CopyDefaults(g.settings, C.DEFAULTS)
  local newChar = Core.EnsureChar(g, guid)
  if Tracker and Tracker.ReplayDelta then SafeCall(Tracker.ReplayDelta, newChar) end

  ns.db, ns.settings, ns.char = g, g.settings, newChar
  RecomputeMask()

  -- account-wide XP table: non-nil wins, larger wins
  if type(oldDb) == "table" and type(oldDb.xpMax) == "table" then
    local dst = g.xpMax
    for lvl, v in pairs(oldDb.xpMax) do
      if type(lvl) == "number" and IsNum(v) and v > 0 then
        local d = dst[lvl]
        if not IsNum(d) or v > d then dst[lvl] = v end
      end
    end
  end

  InvalidateCaches()
  ns.SendMessage("DB_SWAPPED")
  ReapplySync(Tracker)
end

local failedSwap   -- a table whose swap raised an error is not retried every tick

-- Never publishes ns.db: a nil global stays nil until PLAYER_LOGOUT (FOREVER-2).
function Core.CheckSwap()
  if ns.readOnly then return end
  local g = TruePlayedDB
  if g == ns.db then return end
  if type(g) ~= "table" or g == failedSwap then return end
  local ok, err = pcall(DoSwap, g)
  if not ok then
    failedSwap = g
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
  end
end

---------------------------------------------------------------------------
-- Ticker and tick profile (SPEC 5.1, 6.6)
---------------------------------------------------------------------------
local profLeft, profCount, profSum, profMax = 0, 0, 0, 0

local function FormatMs(x)
  local s = string_format("%.3f", x or 0)
  local sep = L.DECIMAL_SEP
  if sep ~= "." then s = (s:gsub("%.", sep, 1)) end
  return s
end

function Core.StartTickProfile(n)
  n = math_floor(tonumber(n) or C.PERF_SAMPLE_TICKS)
  if n < 1 then n = 1 end
  profLeft, profCount, profSum, profMax = n, n, 0, 0
end

-- Ticker callback. The ticker passes itself as the argument: ignored (critique #12).
function Core.Tick()
  local t0
  if profLeft > 0 and debugprofilestop then t0 = debugprofilestop() end

  local now = GetTime()
  if not ns.readOnly then Core.CheckSwap() end
  local Tracker = ns.Tracker
  if Tracker and Tracker.Tick then SafeCall(Tracker.Tick, now) end
  local Tokens = ns.Tokens
  if Tokens and Tokens.IsActive and Tokens.IsActive() then SafeCall(Tokens.UpdateContext, now) end
  ns.SendMessage("TICK", now)

  if t0 then
    local dt = debugprofilestop() - t0
    profSum = profSum + dt
    if dt > profMax then profMax = dt end
    profLeft = profLeft - 1
    if profLeft == 0 then
      Util.Print(L.PERF_TICK_FMT, FormatMs(profSum / profCount), FormatMs(profMax), profCount)
    end
  end
end

---------------------------------------------------------------------------
-- Performance measurement (SPEC 6.6). Rare paths: globals read at call time.
---------------------------------------------------------------------------
function Core.GetMemoryKB()
  local update = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
  local get = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
  if not get then return nil end
  if update then pcall(update) end
  local ok, kb = pcall(get, ns.ADDON)
  if ok and IsNum(kb) then return kb end
  return nil
end

-- msTotal, msPerMin (scriptProfile), profilerAvgMs, profilerPeakMs (C_AddOnProfiler).
function Core.GetCPU()
  local total, perMin, avg, peak
  local cvar = GetCVar and GetCVar("scriptProfile")
  if tonumber(cvar) == 1 and UpdateAddOnCPUUsage and GetAddOnCPUUsage then
    pcall(UpdateAddOnCPUUsage)
    local ok, ms = pcall(GetAddOnCPUUsage, ns.ADDON)
    if ok and IsNum(ms) then
      total = ms
      local minutes = (GetTime() - loadG) / 60
      if minutes < 1 then minutes = 1 end   -- avoid absurd rates right after load
      perMin = ms / minutes
    end
  end
  local profiler = C_AddOnProfiler
  local metric = Enum and Enum.AddOnProfilerMetric
  if profiler and profiler.IsEnabled and profiler.GetAddOnMetric and metric then
    local okE, enabled = pcall(profiler.IsEnabled)
    if okE and enabled then
      local okA, a = pcall(profiler.GetAddOnMetric, ns.ADDON, metric.RecentAverageTime)
      if okA and IsNum(a) then avg = a end
      local okP, p = pcall(profiler.GetAddOnMetric, ns.ADDON, metric.PeakTime)
      if okP and IsNum(p) then peak = p end
    end
  end
  return total, perMin, avg, peak
end

---------------------------------------------------------------------------
-- Lifecycle (SPEC 5.1)
---------------------------------------------------------------------------
local ticker
local loginDone, loginAttempts = false, 0
local LOGIN_MAX_ATTEMPTS = 10

-- ADDON_LOADED adoption; also re-run at PLAYER_LOGIN for WTFix (critique #2).
local function Adopt(db)
  ns.readOnly = false
  if Core.Migrate(db) then
    Util.CopyDefaults(db.settings, C.DEFAULTS)
  else
    ns.readOnly = true
  end
  ns.db = db
end

local function OnAddonLoaded(_, name)
  if name ~= ns.ADDON then return end
  ns.UnregisterEvent("ADDON_LOADED", Core)
  local db = TruePlayedDB
  if type(db) == "table" then Adopt(db) end   -- never created here
end

-- WTFix (Forever launcher) protects every addon with SavedVariables by default and
-- rewrites them at each UI load with an older copy: tracking data would roll back.
-- Read-only detection of that setup, one chat warning per UI load.
local wtfixWarned = false
local function CheckWTFix()
  if wtfixWarned then return end
  local boot = WTFIX_BOOTSTRAP
  local targets = type(boot) == "table" and boot.targets
  if type(targets) ~= "table" or targets[ns.ADDON] == nil then return end
  local wdb = WTFIX_DB
  local protected = type(wdb) == "table" and wdb.protectedAddons
  if type(protected) == "table" and protected[ns.ADDON] == false then return end
  wtfixWarned = true
  Util.Print(L.WTFIX_PROTECTED)
end

-- PLAYER_LOGIN steps 3-7; false while the player GUID is unknown.
local function FinishLogin()
  local db = ns.db
  if ns.readOnly then
    ns.settings = ReadOnlySettings(db)
    WarnReadOnly()
  else
    ns.settings = db.settings
  end
  RecomputeMask()

  local guid = UnitGUID("player")
  if guid == nil then return false end
  if ns.readOnly then
    ns.char = DetachedChar(db, guid)
  else
    ns.char = Core.EnsureChar(db, guid)
  end

  local Tracker, Played = ns.Tracker, ns.Played
  if Tracker and Tracker.Start then SafeCall(Tracker.Start) end
  if Played and Played.Init then SafeCall(Played.Init) end

  loginDone = true
  ns.ready = true
  ns.SendMessage("DB_READY")
  SafeCall(CheckWTFix)

  if not ticker then ticker = C_Timer.NewTicker(C.TICK, Core.Tick) end
  return true
end

local function LoginRetry()
  if loginDone then return end
  loginAttempts = loginAttempts + 1
  if FinishLogin() then return end
  if loginAttempts < LOGIN_MAX_ATTEMPTS then
    C_Timer.After(1, LoginRetry)
  else
    Util.Debug("PLAYER_LOGIN: no player GUID after %d attempts", loginAttempts)
  end
end

local function OnPlayerLogin()
  if loginDone then return end
  local g = TruePlayedDB
  if type(g) == "table" and g ~= ns.db then Adopt(g) end   -- the late-applied table wins
  if ns.db == nil then
    -- Private until PLAYER_LOGOUT (FOREVER-2): Forever may apply the file later
    -- and skips it when the global already exists.
    ns.db = Core.NewDB()
    ns.readOnly = false
  end
  if not FinishLogin() then C_Timer.After(1, LoginRetry) end
end

-- Core registered PLAYER_LOGOUT at file load, the Tracker at PLAYER_LOGIN: this
-- runs first, so the Tracker's save lands in a table adopted here.
local function OnPlayerLogout()
  if type(ns.db) ~= "table" then return end
  Core.CheckSwap()   -- a table applied since the last tick wins
  if ns.readOnly then return end
  local db = ns.db
  db.lastVersion = ns.VERSION
  -- Sparse settings (see LEGACY_DEFAULTS): the file keeps only what the user
  -- changed. The saved table is a copy: ns.settings stays complete in memory for
  -- the handlers that run after this one (the Tracker's save reads rateTau).
  if type(ns.settings) == "table" then
    db.settings = SparseCopy(ns.settings, C.DEFAULTS) or {}
    db.sparseSettings = true
  end
  -- SavedVariables are written only at logout or /reload: publishing now loses nothing.
  if type(TruePlayedDB) ~= "table" then TruePlayedDB = ns.db end
end

ns.RegisterEvent("ADDON_LOADED", Core, OnAddonLoaded)
ns.RegisterEvent("PLAYER_LOGIN", Core, OnPlayerLogin)
ns.RegisterEvent("PLAYER_LOGOUT", Core, OnPlayerLogout)
