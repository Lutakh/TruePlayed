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
-- The followed reputation (Reputation.lua): reph (its points per hour, "Rep. 312/h") and
-- rep_eta (the time to its next standing, "Honored: ~3h 10m"; the standing alone at
-- Exalted) are not XP tokens: they stay at max level. Same statuses as the XP rate (dim
-- while warming up, dim with L.STALL_MARK while frozen); L.DOTS without a faction or a
-- rate yet. A slot showing one of them turns the reputation's reads on (Reputation.lua).
-- PvP (Pvp.lua, WoW Forever; L.DOTS elsewhere): honor ("Honor 1,234 / 25,000"), honor_h
-- (its rate), honor_eta (the time to its cap; "Honor capped" at it), rank ("Rank 7 ·
-- 450 / 1,050"), rank_h (rank points per hour), rank_eta (the time to the next rank; the
-- weekly cap, the max rank or no season instead, dimmed), hk_today (honorable kills
-- today). Not XP tokens: they stay at max level. The PvP rates are dimmed while warming
-- up, and dimmed with L.STALL_MARK while paused (no PvP gain for a while outside a
-- battleground) or kept at a cap. DEF.pvp marks them: the options offer them only where
-- the PvP APIs exist (Pvp.Available).
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
                 "zone_time", "instance_session", "instance_total", "reph", "rep_eta", "honor", "honor_h",
                 "honor_eta", "rank", "rank_h", "rank_eta", "hk_today", "fps", "latency", "fps_latency" }

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
  reph          = { label = "TOKEN_REPH",          xp = false, pausable = true },
  rep_eta       = { label = "TOKEN_REP_ETA",       xp = false, pausable = true },
  honor         = { label = "TOKEN_HONOR",         xp = false, pausable = false, pvp = true },
  honor_h       = { label = "TOKEN_HONOR_H",       xp = false, pausable = true, pvp = true },
  honor_eta     = { label = "TOKEN_HONOR_ETA",     xp = false, pausable = true, pvp = true },
  rank          = { label = "TOKEN_RANK",          xp = false, pausable = false, pvp = true },
  rank_h        = { label = "TOKEN_RANK_H",        xp = false, pausable = true, pvp = true },
  rank_eta      = { label = "TOKEN_RANK_ETA",      xp = false, pausable = true, pvp = true },
  hk_today      = { label = "TOKEN_HK_TODAY",      xp = false, pausable = false, pvp = true },
  fps           = { label = "TOKEN_FPS",           xp = false, pausable = false, need = "fps" },
  latency       = { label = "TOKEN_LATENCY",       xp = false, pausable = false, need = "lat" },
  fps_latency   = { label = "TOKEN_FPS_LATENCY",   xp = false, pausable = false, need = "fpslat" },
}
local DEF = Tokens.DEF

local AFK_KEYS = C.AFK_KEYS
local NET_INTERVAL = C.NET_INTERVAL
local RECENT_LEVELS = C.RECENT_LEVELS
local MAX_KILLS = 1000000          -- sanity bound on the mobs-to-go count

-- Localized strings are read from L at use time, never copied at file load: Core
-- writes the language chosen by the "language" setting into L when the settings are
-- adopted, after this file ran (a copy would keep the client's language). A read of
-- an existing key allocates nothing.

---------------------------------------------------------------------------
-- Context (reused table; fields listed in 3.11, plus hasChar, valid, zoneKey, stateKey,
-- kills / killXP (mobs to the next level and the average base XP of the last 10 kills,
-- nil when unknown), instSession / instTotal (instance seconds under the mask, nil without a
-- character), stalled / stallSecs (rate status "stalled" and the counted seconds since
-- the last XP gain), isServerCap / capLevel / capMisses (max level because of a
-- detected server level cap, Tracker.GetCapInfo) and repOn / reph / repStatus / repEta /
-- repNext (a faction followed, its points per hour and their status, the seconds to its
-- next standing and that standing: Rep.Rate, Rep.Eta), and the PvP fields of
-- Pvp.FillContext (pvpOn, honorOn / honor / honorMax / honorh / honorStatus / honorEta /
-- honorEtaStatus, rankOn / rankLevel / rankPts / rankThr / noSeason / rankMax / rankh /
-- rankStatus / rankEta / rankEtaStatus / rankNext, hkToday))
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
  c.repOn, c.reph, c.repStatus, c.repEta, c.repNext = false, nil, "nodata", nil, nil
  c.pvpOn, c.honorOn, c.honor, c.honorMax, c.honorh, c.honorStatus = false, false, 0, 0, nil, "nodata"
  c.honorEta, c.honorEtaStatus = nil, "nodata"
  c.rankOn, c.rankLevel, c.rankPts, c.rankThr, c.noSeason, c.rankMax = false, 0, 0, 0, true, false
  c.rankh, c.rankStatus, c.rankEta, c.rankEtaStatus, c.rankNext, c.hkToday = nil, "nodata", nil, "none", nil, nil
end
ClearCtx()
ctx.now, ctx.mask = 0, 0

-- Consumers ("bar" 3 slots, "broker" 2 slots, "mini" 3 infos) and the samplers they need.
-- A consumer with its own choice of tokens (the mini display) gives a resolver: i -> id.
local consumers, consumerCount = {}, 0
local resolvers = {}
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
  for owner, nSlots in pairs(consumers) do
    local resolve = resolvers[owner] or Tokens.Resolve
    for i = 1, nSlots do
      local def = DEF[resolve(i)]
      if def and NET_NEEDS[def.need] then net = true end
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

  -- the followed reputation: its rate and the time to its next standing
  local Rep = ns.Rep
  if Rep and Rep.Has() then
    local reph, rstatus = Rep.Rate(mask)
    local reta, _, rnext = Rep.Eta(mask)
    c.repOn, c.reph, c.repStatus, c.repEta, c.repNext = true, reph, rstatus, reta, rnext
  else
    c.repOn, c.reph, c.repStatus, c.repEta, c.repNext = false, nil, "nodata", nil, nil
  end

  -- PvP: the honor, the rank, their rates and times, the kills of the day
  local Pvp = ns.Pvp
  if Pvp then
    Pvp.FillContext(c, mask)
  else
    c.pvpOn, c.honorOn, c.rankOn, c.hkToday = false, false, false, nil
  end

  -- mobs to the next level from the average of the last 10 kills (rest-aware; nil without
  -- a kill or at max)
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
    s = format(L.PERCENT_FMT, format("%d%s%d", whole, L.DECIMAL_SEP, t - whole * 10))
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
  if ctx.isServerCap then return L.CAP_SHORT end
  return L.MAX_LEVEL
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
  if sec == nil then return L.DOTS, true end
  local k = Fmt.ETAKey(sec)
  local mode = RateMode(status)
  if k ~= lastKey.eta or mode ~= lastEst.eta then
    lastKey.eta, lastEst.eta = k, mode
    local text = Fmt.ETA(sec)
    if mode % 2 == 1 then text = Approx(text) end
    if mode >= 2 then text = text .. L.STALL_MARK end
    lastText.eta = text
  end
  return lastText.eta, status == "warming" or status == "stalled"
end

R.xph = function()
  if ctx.isMax then return MaxText(), true end
  local xph = ctx.xph
  if xph == nil then return L.DOTS, true end
  local k = Fmt.ShortKey(xph)
  local status = ctx.rateStatus
  local mode = RateMode(status)
  if k ~= lastKey.xph or mode ~= lastEst.xph then
    lastKey.xph, lastEst.xph = k, mode
    local text = Fmt.Rate(xph)
    if mode % 2 == 1 then text = APPROX .. text end
    if mode >= 2 then text = text .. L.STALL_MARK end
    lastText.xph = text
  end
  return lastText.xph, status == "warming" or status == "stalled"
end

-- Percent of the current level per hour: one decimal below 10, integer above.
R.pcth = function()
  if ctx.isMax then return MaxText(), true end
  local xph = ctx.xph
  if xph == nil or not ctx.valid then return L.DOTS, true end
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
    local text = format(L.PCTH_FMT, num)
    if mode % 2 == 1 then text = APPROX .. text end
    if mode >= 2 then text = text .. L.STALL_MARK end
    lastText.pcth = text
  end
  return lastText.pcth, status == "warming" or status == "stalled"
end

R.xpleft = function()
  if ctx.isMax then return MaxText(), true end
  if not ctx.valid then return L.DOTS, true end
  local left = floor(ctx.max - ctx.xp)
  if left < 0 then left = 0 end
  if left ~= lastKey.xpleft then
    lastKey.xpleft = left
    lastText.xpleft = format(L.XPLEFT_FMT, Fmt.Number(left))
  end
  return lastText.xpleft, false
end

-- Rested pool in percent of the level (the pool can exceed 100 %: 150 % in Classic).
R.rested = function()
  if ctx.isMax then return MaxText(), true end
  if not ctx.valid then return L.DOTS, true end
  local n = floor(ctx.rested * 100 / ctx.max + 0.5)
  if n < 0 then n = 0 end
  if n ~= lastKey.rested then
    lastKey.rested = n
    local pct
    if n <= 100 then pct = Fmt.PercentInt(n) else pct = format(L.PERCENT_FMT, format("%d", n)) end
    lastText.rested = format(L.RESTED_FMT, pct)
  end
  return lastText.rested, false
end

R.level_time = function()
  if not ctx.hasChar then return L.DOTS, true end
  return TimeText("level_time", L.PFX_LEVEL_FMT, ctx.levelTime), false
end

R.session = function()
  if not ctx.hasChar then return L.DOTS, true end
  return TimeText("session", L.PFX_SESSION_FMT, ctx.sessionTime), false
end

R.played = function()
  if not ctx.hasChar then return L.DOTS, true end
  return TimeText("played", L.PFX_PLAYED_FMT, ctx.played), false
end

-- Live server /played; the last saved snapshot (dim) when no sync arrived yet.
R.played_server = function()
  local v = ctx.playedServer
  if v == nil then return L.DOTS, true end
  return TimeText("played_server", L.PFX_SERVER_FMT, v), not ctx.playedLive
end

R.afk_session = function()
  if not ctx.hasChar then return L.DOTS, true end
  return TimeText("afk_session", L.PFX_AFK_FMT, ctx.afkSession), false
end

R.avg_level = function()
  local v = ctx.avgLevel
  if v == nil then return L.DOTS, true end
  return TimeText("avg_level", L.PFX_AVG_FMT, v), false
end

R.zone_time = function()
  if not ctx.hasChar then return L.DOTS, true end
  return TimeText("zone_time", L.PFX_ZONE_FMT, ctx.zoneTime), false
end

R.instance_session = function()
  local v = ctx.instSession
  if v == nil then return L.DOTS, true end
  return TimeText("instance_session", L.PFX_INST_SESSION_FMT, v), false
end

R.instance_total = function()
  local v = ctx.instTotal
  if v == nil then return L.DOTS, true end
  return TimeText("instance_total", L.PFX_INST_TOTAL_FMT, v), false
end

-- "38 mobs", "1 mob" (no "~": the callers add it where the count stands alone).
local killsN, killsText = nil, nil
local function KillsPart(n)
  if n ~= killsN then
    killsN = n
    killsText = format((n == 1) and L.KILLS_ONE_FMT or L.KILLS_FMT, Fmt.Number(n))
  end
  return killsText
end

-- Mobs to the next level, an estimate from the average of the last 10 kills: "~38 mobs".
R.kills = function()
  if ctx.isMax then return MaxText(), true end
  local n = ctx.kills
  if n == nil then return L.DOTS, true end
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
    lastText.eta_kills = format("%s%s%s", eta, L.SEP, part)
  end
  return lastText.eta_kills, dim, eta
end

-- The followed reputation's points per hour: "Rep. 312/h".
R.reph = function()
  local v = ctx.reph
  if v == nil then return L.DOTS, true end
  local k = Fmt.ShortKey(v)
  local status = ctx.repStatus
  local mode = status == "stalled" and 2 or 0
  if k ~= lastKey.reph or mode ~= lastEst.reph then
    lastKey.reph, lastEst.reph = k, mode
    local text = format(L.PFX_REPH_FMT, Fmt.Rate(v))
    if mode == 2 then text = text .. L.STALL_MARK end
    lastText.reph = text
  end
  return lastText.reph, status == "warming" or status == "stalled"
end

-- Name of standing r (the game's, Tooltip.StandingName).
local function RepStanding(r)
  local Tt = ns.Tooltip
  if Tt and Tt.StandingName then return Tt.StandingName(r) end
  return L.DOTS
end

-- Time to the followed faction's next standing: "Honored: ~3h 10m"; at Exalted the
-- standing alone (dim: nothing left to reach).
R.rep_eta = function()
  if not ctx.repOn then return L.DOTS, true end
  local nxt = ctx.repNext
  if nxt == nil then return RepStanding(8), true end
  local sec = ctx.repEta
  if sec == nil then return L.DOTS, true end
  local status = ctx.repStatus
  local k = Fmt.ETAKey(sec) * 10 + nxt
  local mode = status == "stalled" and 2 or 0
  if k ~= lastKey.rep_eta or mode ~= lastEst.rep_eta then
    lastKey.rep_eta, lastEst.rep_eta = k, mode
    local text = format(L.REP_ETA_FMT, RepStanding(nxt), Fmt.ETA(sec))
    if mode == 2 then text = text .. L.STALL_MARK end
    lastText.rep_eta = text
  end
  return lastText.rep_eta, status == "warming" or status == "stalled"
end

-- PvP (Pvp.lua). Status of a PvP rate shown with L.STALL_MARK: paused or kept at a cap.
local function PvpMarked(status)
  return status == "paused" or status == "capped"
end

-- The honor toward its cap: "Honor 1,234 / 25,000" (the amount alone without a cap).
R.honor = function()
  if not ctx.honorOn then return L.DOTS, true end
  local q, mx = ctx.honor, ctx.honorMax
  local k = q * 1000003 + mx
  if k ~= lastKey.honor then
    lastKey.honor = k
    if mx > 0 then
      lastText.honor = format(L.PFX_HONOR_FMT, Fmt.Number(q), Fmt.Number(mx))
    else
      lastText.honor = format(L.PFX_HONOR_ONLY_FMT, Fmt.Number(q))
    end
  end
  return lastText.honor, false
end

-- A PvP rate: "<prefix> 1.2k/h" (pattern fmt), cached under id.
local function PvpRate(id, fmt, v, status)
  if v == nil then return L.DOTS, true end
  local k = Fmt.ShortKey(v)
  local mode = PvpMarked(status) and 2 or 0
  if k ~= lastKey[id] or mode ~= lastEst[id] then
    lastKey[id], lastEst[id] = k, mode
    local text = format(fmt, Fmt.Rate(v))
    if mode == 2 then text = text .. L.STALL_MARK end
    lastText[id] = text
  end
  return lastText[id], status == "warming" or mode == 2
end

R.honor_h = function()
  if not ctx.honorOn then return L.DOTS, true end
  return PvpRate("honor_h", L.PFX_HONORH_FMT, ctx.honorh, ctx.honorStatus)
end

-- Time to the honor cap: "Cap: ~3h 10m"; "Honor capped" at it (not dim: act on it).
R.honor_eta = function()
  if not ctx.honorOn or ctx.honorMax <= 0 then return L.DOTS, true end
  local st = ctx.honorEtaStatus
  if st == "capped" then return L.PVP_AT_CAP, false end
  local sec = ctx.honorEta
  if sec == nil then return L.DOTS, true end
  local k = Fmt.ETAKey(sec)
  local mode = PvpMarked(st) and 2 or 0
  if k ~= lastKey.honor_eta or mode ~= lastEst.honor_eta then
    lastKey.honor_eta, lastEst.honor_eta = k, mode
    local text = format(L.HONOR_ETA_FMT, Fmt.ETA(sec))
    if mode == 2 then text = text .. L.STALL_MARK end
    lastText.honor_eta = text
  end
  return lastText.honor_eta, st == "warming" or mode == 2
end

-- The PvP rank: "Rank 7 · 450 / 1,050"; "Rank 14" at the max rank; "No season" before.
R.rank = function()
  if not ctx.rankOn then return L.DOTS, true end
  if ctx.noSeason then return L.PVP_NO_SEASON_SHORT, true end
  local lv, pts, thr = ctx.rankLevel, ctx.rankPts, ctx.rankThr
  local k = ctx.rankMax and -1 - lv or (lv * 1000003 + pts) * 1000003 + thr
  if k ~= lastKey.rank then
    lastKey.rank = k
    if ctx.rankMax then
      lastText.rank = format(L.PVP_RANK_FMT, lv)
    else
      lastText.rank = format(L.PFX_RANK_FMT, lv, Fmt.Number(pts), Fmt.Number(thr))
    end
  end
  return lastText.rank, false
end

R.rank_h = function()
  if not ctx.rankOn or ctx.noSeason then return L.DOTS, true end
  return PvpRate("rank_h", L.PFX_RANKH_FMT, ctx.rankh, ctx.rankStatus)
end

-- Time to the next rank: "Rank 8: ~1h 35m"; the weekly cap, the max rank or no season
-- instead (dimmed: nothing to wait for this week).
R.rank_eta = function()
  if not ctx.rankOn then return L.DOTS, true end
  local st = ctx.rankEtaStatus
  if st == "noseason" then return L.PVP_NO_SEASON_SHORT, true end
  if st == "max" then return L.PVP_RANK_MAX, true end
  if st == "capped" then return L.PVP_WEEK_CAPPED_SHORT, true end
  local sec, nxt = ctx.rankEta, ctx.rankNext
  if sec == nil or nxt == nil then return L.DOTS, true end
  local k = Fmt.ETAKey(sec) * 100 + nxt
  local mode = PvpMarked(st) and 2 or 0
  if k ~= lastKey.rank_eta or mode ~= lastEst.rank_eta then
    lastKey.rank_eta, lastEst.rank_eta = k, mode
    local text = format(L.RANK_ETA_FMT, nxt, Fmt.ETA(sec))
    if mode == 2 then text = text .. L.STALL_MARK end
    lastText.rank_eta = text
  end
  return lastText.rank_eta, st == "warming" or mode == 2
end

-- Honorable kills today: "HK 12".
R.hk_today = function()
  local n = ctx.hkToday
  if n == nil then return L.DOTS, true end
  if n ~= lastKey.hk_today then
    lastKey.hk_today = n
    lastText.hk_today = format(L.PFX_HK_FMT, Fmt.Number(n))
  end
  return lastText.hk_today, false
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

-- `resolve` (optional): function(i) -> token id of the consumer's i-th text; the bar's
-- slots (Tokens.Resolve) by default.
function Tokens.Acquire(owner, nSlots, resolve)
  if owner == nil then return end
  if consumers[owner] == nil then consumerCount = consumerCount + 1 end
  consumers[owner] = nSlots or 3
  resolvers[owner] = resolve
  RefreshNeeds()
  Tokens.UpdateContext(GetTime())
end

function Tokens.Release(owner)
  if owner == nil or consumers[owner] == nil then return end
  consumers[owner] = nil
  resolvers[owner] = nil
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
