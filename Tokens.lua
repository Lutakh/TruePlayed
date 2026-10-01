-- Tokens.lua - display tokens for the widget slots and the broker (SPEC-FINAL 3.11, 7.3).
--
-- One reused context table (Tokens.ctx) is refreshed by Core.Tick while at least one
-- consumer is active, and on data messages. Each token keeps its last display key and
-- text: a string is formatted only when the displayed value changes, so the tick path
-- allocates nothing in steady state (requirement A).
-- FPS is sampled only while an active consumer shows an FPS token (at most once per
-- tick); latency only while a latency token is shown, at most every C.NET_INTERVAL s.
-- Rate status "estimate" (value taken, fully or partly, from the pre-install /played
-- estimate) is shown with a leading "~" on the rate tokens; it is not dimmed.
-- The FPS / latency history graph (Graph.lua) needs both series: a visible fps, latency
-- or fps_latency token samples both, and each sample is handed to Graph.Sample from
-- this path (latency only when it was re-read).
-- eta_kills returns a 4th value from Render: its shorter form (the ETA alone), used by
-- the bar when the full text does not fit.
-- Rate status "stalled" (no XP gained for a while: the engine froze the rate so idle
-- time never drags it down): the rate tokens show the frozen value dimmed, followed by
-- L.STALL_MARK; the tooltip says for how long no XP was gained.
-- Detected server level cap (Tracker.GetCapInfo, isServerCap): the character counts as
-- max level (Tracker.IsMax), and the XP tokens that are still rendered say
-- L.CAP_SHORT instead of L.MAX_LEVEL.
local ADDON, ns = ...
local L, C, Fmt = ns.L, ns.C, ns.Fmt

local type, pairs, tonumber = type, pairs, tonumber
local format, floor, ceil = string.format, math.floor, math.ceil
local GetTime, wipe = GetTime, wipe
local GetFramerate, GetNetStats = GetFramerate, GetNetStats

local Tokens = {}
ns.Tokens = Tokens

Tokens.ORDER = { "none", "eta", "eta_kills", "kills", "xph", "pcth", "xpleft", "rested",
                 "level_time", "session", "played", "played_server", "afk_session", "avg_level",
                 "zone_time", "instance_session", "instance_total", "fps", "latency", "fps_latency" }

Tokens.DEF = {
  none          = { label = "TOKEN_NONE",          xp = false, pausable = false },
  eta           = { label = "TOKEN_ETA",           xp = true,  pausable = true,  need = "rate" },
  eta_kills     = { label = "TOKEN_ETA_KILLS",     xp = true,  pausable = true,  need = "rate" },
  kills         = { label = "TOKEN_KILLS",         xp = true,  pausable = false },
  xph           = { label = "TOKEN_XPH",           xp = true,  pausable = true,  need = "rate" },
  pcth          = { label = "TOKEN_PCTH",          xp = true,  pausable = true,  need = "rate" },
  xpleft        = { label = "TOKEN_XPLEFT",        xp = true,  pausable = false },
  rested        = { label = "TOKEN_RESTED",        xp = true,  pausable = false },
  level_time    = { label = "TOKEN_LEVEL_TIME",    xp = false, pausable = true },
  session       = { label = "TOKEN_SESSION",       xp = false, pausable = true },
  played        = { label = "TOKEN_PLAYED",        xp = false, pausable = true },
  played_server = { label = "TOKEN_PLAYED_SERVER", xp = false, pausable = false },
  afk_session   = { label = "TOKEN_AFK_SESSION",   xp = false, pausable = false },
  avg_level     = { label = "TOKEN_AVG_LEVEL",     xp = false, pausable = true },
  zone_time     = { label = "TOKEN_ZONE_TIME",     xp = false, pausable = true },
  instance_session = { label = "TOKEN_INSTANCE_SESSION", xp = false, pausable = true },
  instance_total   = { label = "TOKEN_INSTANCE_TOTAL",   xp = false, pausable = true },
  fps           = { label = "TOKEN_FPS",           xp = false, pausable = false, need = "fps" },
  latency       = { label = "TOKEN_LATENCY",       xp = false, pausable = false, need = "lat" },
  fps_latency   = { label = "TOKEN_FPS_LATENCY",   xp = false, pausable = false, need = "fpslat" },
}
local DEF = Tokens.DEF

local AFK_KEYS = C.AFK_KEYS
local NET_INTERVAL = C.NET_INTERVAL
local RECENT_LEVELS = C.RECENT_LEVELS
local MAX_KILLS = 1000000          -- sanity bound on the mobs-to-go count

-- Localized patterns (the locale is fixed for the whole UI load).
local DOTS, MAX_LEVEL, CAP_SHORT, STALL_MARK = L.DOTS, L.MAX_LEVEL, L.CAP_SHORT, L.STALL_MARK
local PFX_LEVEL, PFX_SESSION, PFX_PLAYED = L.PFX_LEVEL_FMT, L.PFX_SESSION_FMT, L.PFX_PLAYED_FMT
local PFX_SERVER, PFX_AFK, PFX_AVG, PFX_ZONE = L.PFX_SERVER_FMT, L.PFX_AFK_FMT, L.PFX_AVG_FMT, L.PFX_ZONE_FMT
local XPLEFT_FMT, RESTED_FMT, PCTH_FMT, PERCENT_FMT = L.XPLEFT_FMT, L.RESTED_FMT, L.PCTH_FMT, L.PERCENT_FMT
local KILLS_FMT, KILLS_ONE_FMT, SEP = L.KILLS_FMT, L.KILLS_ONE_FMT, L.SEP
local PFX_INST_SESSION, PFX_INST_TOTAL = L.PFX_INST_SESSION_FMT, L.PFX_INST_TOTAL_FMT

---------------------------------------------------------------------------
-- Context (reused table; fields listed in 3.11, plus hasChar, valid, zoneKey, stateKey,
-- kills / killXP (mobs to the next level and the base XP of the last kill, nil when
-- unknown), instSession / instTotal (instance seconds under the mask, nil without a
-- character), stalled / stallSecs (rate status "stalled" and the counted seconds since
-- the last XP gain) and isServerCap / capLevel / capMisses (max level because of a
-- detected server level cap, Tracker.GetCapInfo))
---------------------------------------------------------------------------

local ctx = {}
Tokens.ctx = ctx

local function ClearCtx()
  local c = ctx
  c.hasChar, c.valid = false, false
  c.level, c.isMax = 1, false
  c.xp, c.max, c.rested, c.pct = 0, 0, 0, 0
  c.paused, c.pauseReason = false, nil
  c.xph, c.rateSrc, c.rateStatus, c.warmupLeft = nil, nil, "nodata", 0
  c.eta, c.etaStatus = nil, "nodata"
  c.sessionTime, c.levelTime, c.played, c.afkSession, c.zoneTime = 0, 0, 0, 0, 0
  c.playedServer, c.playedLive, c.avgLevel = nil, false, nil
  c.zoneKey, c.stateKey = nil, nil
  c.kills, c.killXP = nil, nil
  c.instSession, c.instTotal = nil, nil
  c.stalled, c.stallSecs = false, 0
  c.isServerCap, c.capLevel, c.capMisses = false, nil, nil
end
ClearCtx()
ctx.now, ctx.mask = 0, 0

-- Consumers ("bar" 3 slots, "broker" 2 slots) and the samplers they need.
local consumers, consumerCount = {}, 0
local needFps, needLat = false, false
local lastNet = nil          -- GetTime of the last GetNetStats call
local initialized = false

-- Per-token caches: last display key, display mode (rate tokens: 1 = estimate "~",
-- 2 = frozen mark, 3 = both) and text.
local lastKey, lastText, lastEst = {}, {}, {}
local lastMax = nil          -- Tracker.IsMax at the last context refresh

local APPROX = "~"
local APPROX_BYTE = 126            -- "~"

-- Leading "~" for an estimated value (never doubled: ETA texts may already have one).
local function Approx(text)
  if text:byte(1) == APPROX_BYTE then return text end
  return APPROX .. text
end
Tokens.Approx = Approx

local function SampleFps()
  local fps = GetFramerate and GetFramerate() or 0
  ctx.fps = fps
  return fps
end

local function SampleNet(now)
  lastNet = now
  local home, world = 0, 0
  if GetNetStats then
    local _, _, h, w = GetNetStats()
    home, world = h or 0, w or 0
  end
  ctx.latHome, ctx.latWorld = home, world
end

local function NetDue(now)
  return ctx.latHome == nil or lastNet == nil or now - lastNet >= NET_INTERVAL
end

-- FPS for a render: the value sampled this tick when a consumer needs it, else a fresh
-- read (rendering outside the consumers, e.g. an options preview).
local function CurrentFps()
  local fps = ctx.fps
  if needFps and fps ~= nil then return fps end
  return SampleFps()
end

-- Latency shown = max(home, world), refreshed at most every C.NET_INTERVAL s.
local function CurrentLatency()
  local now = GetTime()
  if NetDue(now) then SampleNet(now) end
  local home, world = ctx.latHome, ctx.latWorld
  if world > home then return world end
  return home
end

---------------------------------------------------------------------------
-- Slot resolution (7.3)
---------------------------------------------------------------------------

function Tokens.DefaultSlot(i, atMax)
  local w = C.DEFAULTS and C.DEFAULTS.widget
  local list = w and (atMax and w.maxSlots or w.slots)
  local id = list and list[i]
  if id == nil or DEF[id] == nil then return "none" end
  return id
end

local function IsMaxNow()
  local Tracker = ns.Tracker
  return Tracker ~= nil and Tracker.IsMax ~= nil and Tracker.IsMax() == true
end

-- Token id shown in slot i: unknown ids fall back to the slot default (critique #21);
-- at max level XP tokens are replaced by the max-level slot (never an XP token).
function Tokens.Resolve(i)
  local settings = ns.settings
  local w = settings and settings.widget
  local slots = w and w.slots
  local id = slots and slots[i]
  if id == nil or DEF[id] == nil then id = Tokens.DefaultSlot(i) end
  if DEF[id].xp and IsMaxNow() then
    local maxSlots = w and w.maxSlots
    local mid = maxSlots and maxSlots[i]
    if mid == nil or DEF[mid] == nil then mid = Tokens.DefaultSlot(i, true) end
    if DEF[mid].xp then mid = "none" end
    id = mid
  end
  return id
end

function Tokens.Label(id)
  local def = DEF[id]
  if not def then return L.TOKEN_NONE end
  return L[def.label]
end

-- Tokens that show FPS and / or latency (their slots also get the history graph).
local NET_NEEDS = { fps = true, lat = true, fpslat = true }

function Tokens.IsNetToken(id)
  local def = DEF[id]
  return def ~= nil and NET_NEEDS[def.need] == true
end

-- Recomputes which samplers the active consumers need (settings, level, max-level and
-- consumer changes only; never per tick). The history graph shows both series, so any
-- visible FPS or latency token samples both (FPS every tick, latency every
-- C.NET_INTERVAL s: the game refreshes GetNetStats only about every 30 s).
local function RefreshNeeds()
  local net = false
  for _, nSlots in pairs(consumers) do
    for i = 1, nSlots do
      if NET_NEEDS[DEF[Tokens.Resolve(i)].need] then net = true end
    end
  end
  needFps, needLat = net, net
end

---------------------------------------------------------------------------
-- Context refresh (tick path: no allocation)
---------------------------------------------------------------------------

function Tokens.UpdateContext(now)
  now = now or GetTime()
  local c = ctx
  c.now = now
  local GetMask = ns.GetMask
  local mask = GetMask and GetMask() or 0
  c.mask = mask

  local char, Tracker, Stats = ns.char, ns.Tracker, ns.Stats
  if type(char) ~= "table" or not Tracker or not Stats then
    ClearCtx()
    return
  end
  c.hasChar = true

  -- state, level and XP (last valid read, no API call)
  local key, zoneKey, level = Tracker.GetState()
  local xLevel, xp, xMax, rested, valid = Tracker.GetXPInfo()
  level = level or xLevel or char.level or 1
  c.level = level
  c.stateKey, c.zoneKey = key, zoneKey
  local isMax = Tracker.IsMax() == true
  c.isMax = isMax
  if isMax ~= lastMax then
    -- max level (or a server level cap) reached or left: the slots resolve differently
    lastMax = isMax
    RefreshNeeds()
  end
  -- detected server level cap (C2): max level for now, resumes with the next XP gain
  local capLevel, isServerCap, misses
  local GetCapInfo = Tracker.GetCapInfo
  if isMax and GetCapInfo then capLevel, isServerCap, misses = GetCapInfo() end
  if isServerCap == true and type(capLevel) == "number" then
    c.isServerCap, c.capLevel = true, capLevel
    c.capMisses = type(misses) == "number" and misses or nil
  else
    c.isServerCap, c.capLevel, c.capMisses = false, nil, nil
  end
  if valid and xp and xMax and xMax > 0 then
    rested = rested or 0
    c.valid, c.xp, c.max, c.rested = true, xp, xMax, rested
    local p = xp / xMax
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    c.pct = p
  else
    c.valid, c.xp, c.max, c.rested, c.pct = false, 0, 0, 0, 0
  end

  local paused, reason = Tracker.IsPaused(mask)
  c.paused = paused == true
  c.pauseReason = c.paused and reason or nil

  -- rate and ETA (fallback chain 5.11; ETA = Stats.ETA with the rate computed once)
  local xph, A, _, Q, src, status, left, stallSecs = Stats.Rate(char, mask)
  c.xph, c.rateSrc, c.rateStatus, c.warmupLeft = xph, src, status, left or 0
  -- no XP for a while (C1): the frozen rate, and the counted seconds since the last gain
  if status == "stalled" then
    local GetStall = Tracker.GetStall
    if GetStall then
      local _, secs = GetStall()
      if type(secs) == "number" then stallSecs = secs end
    end
    if type(stallSecs) ~= "number" or stallSecs ~= stallSecs or stallSecs < 0 then stallSecs = 0 end
    c.stalled, c.stallSecs = true, stallSecs
  else
    c.stalled, c.stallSecs = false, 0
  end
  if isMax then
    c.eta, c.etaStatus = nil, "max"
  elseif status == "nodata" or not c.valid then
    c.eta, c.etaStatus = nil, "nodata"
  else
    local sec = Stats.EtaRestAware(c.max - c.xp, c.rested, A, Q)
    c.eta = sec
    c.etaStatus = sec and status or "nodata"
  end

  -- times (current character only; the sync belongs to it, 5.19)
  local sync = Tracker.GetSync()
  local session = Tracker.GetSession()
  c.sessionTime = Stats.SessionTime(session, mask)
  c.afkSession = Stats.SumKeys(session, AFK_KEYS)
  c.levelTime = (Stats.LevelTime(char, level, mask, sync, now))
  local played, base, _, live = Stats.Played(char, mask, sync, now)
  c.played, c.playedLive = played, live
  if live then
    c.playedServer = base
  else
    local srv = char.srv
    c.playedServer = type(srv) == "table" and srv.total or nil
  end
  local avg = Stats.RecentAvg(char, mask, RECENT_LEVELS)
  if avg == nil then avg = Stats.AvgPerLevel(char, mask, sync, now) end
  c.avgLevel = avg
  local zones = char.zones
  if zoneKey ~= nil and type(zones) == "table" then
    c.zoneTime = Stats.Sum(zones[zoneKey], mask)
  else
    c.zoneTime = 0
  end

  -- instance time (dungeons, raids, PvP) of the session and of the whole character
  c.instSession = Stats.InstanceTime(session, mask)
  c.instTotal = Stats.InstanceTime(char.life, mask)

  -- mobs to the next level from the last kill (rest-aware; nil without a kill or at max)
  local kills, killXP
  if c.valid and not isMax then
    kills, killXP = Stats.KillsToLevel(char, c.xp, c.max, c.rested)
    if type(kills) ~= "number" or kills ~= kills or kills < 0 or kills > MAX_KILLS then
      kills, killXP = nil, nil
    else
      kills = ceil(kills - 1e-9)
    end
  end
  c.kills, c.killXP = kills, killXP

  -- samplers, only for what a visible consumer shows; the graph keeps the history
  if needFps then
    local fps = SampleFps()
    local home, world
    if needLat and NetDue(now) then
      SampleNet(now)
      home, world = c.latHome, c.latWorld
    end
    local Graph = ns.Graph
    if Graph and Graph.Sample then Graph.Sample(now, fps, home, world) end
  elseif needLat and NetDue(now) then
    SampleNet(now)
  end
end

---------------------------------------------------------------------------
-- Level percent with one decimal (tooltip and bar share it): "0,3 %", "99,9 %".
-- Rounded to the tenth like Fmt.Percent(x, 1), but never "100,0 %" before the
-- level-up (99.95 % shows 99,9 %). Memoized per tenth: 1001 strings at most.
---------------------------------------------------------------------------

local pctText = {}

-- Tenths of a percent of the level, 0..1000 (999 at most while xp < max).
function Tokens.PercentTenths(xp, max)
  if type(xp) ~= "number" or type(max) ~= "number" or xp ~= xp or max <= 0 then return 0 end
  local t = floor(xp * 1000 / max + 0.5)
  if t < 0 then t = 0 end
  if t > 999 and xp < max then t = 999 end
  if t > 1000 then t = 1000 end
  return t
end

function Tokens.PercentText(tenths)
  local t = floor(tonumber(tenths) or 0)
  if t < 0 then t = 0 elseif t > 1000 then t = 1000 end
  local s = pctText[t]
  if not s then
    local whole = floor(t / 10)
    s = format(PERCENT_FMT, format("%d%s%d", whole, L.DECIMAL_SEP, t - whole * 10))
    pctText[t] = s
  end
  return s
end

---------------------------------------------------------------------------
-- Renderers: each returns text, dim. Texts are rebuilt only when their key changes.
---------------------------------------------------------------------------

local function TimeText(id, pattern, sec)
  local k = Fmt.DurationKey(sec)
  if k ~= lastKey[id] then
    lastKey[id] = k
    lastText[id] = format(pattern, Fmt.Duration(sec))
  end
  return lastText[id]
end

local R = {}

R.none = function() return "", false end

-- Text of the XP tokens at max level: "Max level", or "Server cap" for a detected
-- server level cap (the character is only stopped for now).
local function MaxText()
  if ctx.isServerCap then return CAP_SHORT end
  return MAX_LEVEL
end

-- Display mode of a rate text: 1 = estimate from /played ("~" prefix), 2 = frozen
-- (no XP for a while: L.STALL_MARK after it; a frozen estimate keeps its "~").
local function RateMode(status)
  if status == "estimate" then return 1 end
  if status == "stalled" then
    if ctx.rateSrc == "prior" then return 3 end
    return 2
  end
  return 0
end

-- Rate tokens: dim while the EMA warms up and while frozen; "~" prefix for an estimate
-- from /played; the frozen mark after a frozen value.
R.eta = function()
  local status = ctx.etaStatus
  if status == "max" then return MaxText(), true end
  local sec = ctx.eta
  if sec == nil then return DOTS, true end
  local k = Fmt.ETAKey(sec)
  local mode = RateMode(status)
  if k ~= lastKey.eta or mode ~= lastEst.eta then
    lastKey.eta, lastEst.eta = k, mode
    local text = Fmt.ETA(sec)
    if mode % 2 == 1 then text = Approx(text) end
    if mode >= 2 then text = text .. STALL_MARK end
    lastText.eta = text
  end
  return lastText.eta, status == "warming" or status == "stalled"
end

R.xph = function()
  if ctx.isMax then return MaxText(), true end
  local xph = ctx.xph
  if xph == nil then return DOTS, true end
  local k = Fmt.ShortKey(xph)
  local status = ctx.rateStatus
  local mode = RateMode(status)
  if k ~= lastKey.xph or mode ~= lastEst.xph then
    lastKey.xph, lastEst.xph = k, mode
    local text = Fmt.Rate(xph)
    if mode % 2 == 1 then text = APPROX .. text end
    if mode >= 2 then text = text .. STALL_MARK end
    lastText.xph = text
  end
  return lastText.xph, status == "warming" or status == "stalled"
end

-- Percent of the current level per hour: one decimal below 10, integer above.
R.pcth = function()
  if ctx.isMax then return MaxText(), true end
  local xph = ctx.xph
  if xph == nil or not ctx.valid then return DOTS, true end
  local v = xph * 100 / ctx.max
  local tenths = floor(v * 10 + 0.5)
  local k
  if tenths < 100 then k = tenths else k = 1000 + floor(v + 0.5) end
  local status = ctx.rateStatus
  local mode = RateMode(status)
  if k ~= lastKey.pcth or mode ~= lastEst.pcth then
    lastKey.pcth, lastEst.pcth = k, mode
    local num
    if k < 1000 then num = Fmt.Decimal(tenths / 10, 1) else num = format("%d", k - 1000) end
    local text = format(PCTH_FMT, num)
    if mode % 2 == 1 then text = APPROX .. text end
    if mode >= 2 then text = text .. STALL_MARK end
    lastText.pcth = text
  end
  return lastText.pcth, status == "warming" or status == "stalled"
end

R.xpleft = function()
  if ctx.isMax then return MaxText(), true end
  if not ctx.valid then return DOTS, true end
  local left = floor(ctx.max - ctx.xp)
  if left < 0 then left = 0 end
  if left ~= lastKey.xpleft then
    lastKey.xpleft = left
    lastText.xpleft = format(XPLEFT_FMT, Fmt.Number(left))
  end
  return lastText.xpleft, false
end

-- Rested pool in percent of the level (the pool can exceed 100 %: 150 % in Classic).
R.rested = function()
  if ctx.isMax then return MaxText(), true end
  if not ctx.valid then return DOTS, true end
  local n = floor(ctx.rested * 100 / ctx.max + 0.5)
  if n < 0 then n = 0 end
  if n ~= lastKey.rested then
    lastKey.rested = n
    local pct
    if n <= 100 then pct = Fmt.PercentInt(n) else pct = format(PERCENT_FMT, format("%d", n)) end
    lastText.rested = format(RESTED_FMT, pct)
  end
  return lastText.rested, false
end

R.level_time = function()
  if not ctx.hasChar then return DOTS, true end
  return TimeText("level_time", PFX_LEVEL, ctx.levelTime), false
end

R.session = function()
  if not ctx.hasChar then return DOTS, true end
  return TimeText("session", PFX_SESSION, ctx.sessionTime), false
end

R.played = function()
  if not ctx.hasChar then return DOTS, true end
  return TimeText("played", PFX_PLAYED, ctx.played), false
end

-- Live server /played; the last saved snapshot (dim) when no sync arrived yet.
R.played_server = function()
  local v = ctx.playedServer
  if v == nil then return DOTS, true end
  return TimeText("played_server", PFX_SERVER, v), not ctx.playedLive
end

R.afk_session = function()
  if not ctx.hasChar then return DOTS, true end
  return TimeText("afk_session", PFX_AFK, ctx.afkSession), false
end

R.avg_level = function()
  local v = ctx.avgLevel
  if v == nil then return DOTS, true end
  return TimeText("avg_level", PFX_AVG, v), false
end

R.zone_time = function()
  if not ctx.hasChar then return DOTS, true end
  return TimeText("zone_time", PFX_ZONE, ctx.zoneTime), false
end

R.instance_session = function()
  local v = ctx.instSession
  if v == nil then return DOTS, true end
  return TimeText("instance_session", PFX_INST_SESSION, v), false
end

R.instance_total = function()
  local v = ctx.instTotal
  if v == nil then return DOTS, true end
  return TimeText("instance_total", PFX_INST_TOTAL, v), false
end

-- "38 mobs", "1 mob" (no "~": the callers add it where the count stands alone).
local killsN, killsText = nil, nil
local function KillsPart(n)
  if n ~= killsN then
    killsN = n
    killsText = format((n == 1) and KILLS_ONE_FMT or KILLS_FMT, Fmt.Number(n))
  end
  return killsText
end

-- Mobs to the next level, an estimate from the last kill: "~38 mobs".
R.kills = function()
  if ctx.isMax then return MaxText(), true end
  local n = ctx.kills
  if n == nil then return DOTS, true end
  local part = KillsPart(n)
  if part ~= lastKey.kills then
    lastKey.kills = part
    lastText.kills = Approx(part)
  end
  return lastText.kills, false
end

-- "~5h 07m · 38 mobs"; the 3rd value is the shorter form (the ETA alone) that the bar
-- shows when the full text does not fit. Either part alone when the other is unknown.
local ekEta, ekPart = nil, nil
R.eta_kills = function()
  if ctx.isMax then return MaxText(), true end
  if ctx.kills == nil then return R.eta() end
  if ctx.eta == nil then return R.kills() end
  local eta, dim = R.eta()
  local part = KillsPart(ctx.kills)
  if eta ~= ekEta or part ~= ekPart then
    ekEta, ekPart = eta, part
    lastText.eta_kills = format("%s%s%s", eta, SEP, part)
  end
  return lastText.eta_kills, dim, eta
end

-- Fmt memoizes these strings per value: no cache needed here.
R.fps = function()
  return Fmt.FPS(CurrentFps()), false
end

R.latency = function()
  return Fmt.Latency(CurrentLatency()), false
end

R.fps_latency = function()
  return Fmt.FPSLatency(CurrentFps(), CurrentLatency()), false
end

-- Returns text, dim, paused, alt. Paused (a pausable token while the current state is
-- excluded by the mask) implies dim. alt = a shorter text for the same token (eta_kills:
-- the ETA alone) or nil. Unknown ids render as an empty slot.
function Tokens.Render(id)
  local fn = R[id]
  if not fn then return "", false, false end
  local text, dim, alt = fn()
  local paused = false
  if ctx.paused and DEF[id].pausable then
    paused = true
    dim = true
  end
  return text, dim == true, paused, alt
end

-- The text without its colour codes (FPS / latency drawn in the widget's text colour
-- when widget.qualityColors is off). Memoized by the coloured string (the Fmt memos
-- keep those strings alive), capped: zero allocation once warm.
local plainMemo, plainCount = {}, 0
local PLAIN_MAX = 512

function Tokens.Plain(text)
  if type(text) ~= "string" then return text end
  local s = plainMemo[text]
  if s then return s end
  if not text:find("|", 1, true) then return text end
  s = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  s = s:gsub("|r", "")
  if plainCount >= PLAIN_MAX then
    wipe(plainMemo)
    plainCount = 0
  end
  plainMemo[text] = s
  plainCount = plainCount + 1
  return s
end

---------------------------------------------------------------------------
-- Consumers and messages
---------------------------------------------------------------------------

function Tokens.IsActive()
  return consumerCount > 0
end

function Tokens.Acquire(owner, nSlots)
  if owner == nil then return end
  if consumers[owner] == nil then consumerCount = consumerCount + 1 end
  consumers[owner] = nSlots or 3
  RefreshNeeds()
  Tokens.UpdateContext(GetTime())
end

function Tokens.Release(owner)
  if owner == nil or consumers[owner] == nil then return end
  consumers[owner] = nil
  consumerCount = consumerCount - 1
  RefreshNeeds()
end

-- Messages that can change which token a slot resolves to (settings, level, max level).
local NEEDS_MESSAGES = {
  SETTINGS_CHANGED = true, LEVEL_UP = true, XP_CHANGED = true, DB_SWAPPED = true, CHAR_RESET = true,
}
local DATA_MESSAGES = {
  "XP_CHANGED", "STATE_CHANGED", "SETTINGS_CHANGED", "PLAYED_SYNCED", "LEVEL_UP",
  "SESSION_RESET", "DB_SWAPPED", "CHAR_RESET", "ZONE_KEY_CHANGED",
}

-- Registered for the whole UI load (at DB_READY, before Bar and Broker register theirs,
-- so the context is fresh when their handlers run); a no-op while nobody consumes.
local function OnDataMessage(msg)
  if NEEDS_MESSAGES[msg] then RefreshNeeds() end
  if consumerCount > 0 then Tokens.UpdateContext(GetTime()) end
end

function Tokens.Init()
  if initialized then return end
  initialized = true
  for i = 1, #DATA_MESSAGES do
    ns.RegisterMessage(DATA_MESSAGES[i], Tokens, OnDataMessage)
  end
  RefreshNeeds()
  Tokens.UpdateContext(GetTime())
end

function Tokens.OnDBReady()
  Tokens.Init()
end

ns.RegisterMessage("DB_READY", Tokens, Tokens.OnDBReady)
