local ADDON, ns = ...
local L, C, Util = ns.L, ns.C, ns.Util

-- Pvp.lua - PvP on WoW Forever: the honor (a currency the player spends, held up to a cap)
-- and the PvP rank (points gained in battlegrounds and PvP quests, summed over a season,
-- with a weekly cap on the rank one can reach). Feeds the thin PvP strip under the bar and
-- the main bar's PvP mode (Bar.lua), the detailed PvP tooltip (Tooltip.FillPvp), the PvP
-- tokens (Tokens.lua), the options' PvP page (PvpOptions.lua) and the honor cap alert.
--
-- Data (every call guarded: a missing function, a nil table, a non-number field, a secret
-- value all read as "unknown"; nothing is hard-coded but the two ids of Core.lua):
--   * honor: C_CurrencyInfo.GetCurrencyInfo(C.PVP_HONOR_ID): quantity, maxQuantity (the
--     cap; 0: none), discovered. totalEarned / quantityEarnedThisWeek are not used (0 in
--     the beta while the quantity is not). 0 with no cap, or not discovered: an empty
--     read (the data not loaded yet, as at PLAYER_LOGIN);
--   * rank: C_MajorFactions.GetMajorFactionProgressionInfo(C.PVP_RANK_FACTION):
--     renownLevel (the rank, 0..maxLevel), renownReputationEarned (points inside the
--     rank), renownLevelThreshold (points of the rank), weekNumber, the weekly cap
--     currentWeekProgressiveMaxLevel; C_MajorFactions.GetTotalReputationForRenownLevel
--     gives the season totals (total = total of the rank + points; the cap's total: the
--     caps are whole ranks); GetCurrentArenaSeason the season's number. The season has not
--     begun (the beta: weekNumber -1, no point) when there is no point and weekNumber < 1
--     or the weekly cap is 0: "no season", shown as such, nothing divided by it. Rank 0,
--     no point and maxLevel 0: an empty read;
--   * honorable kills: GetPVPSessionStats (today), GetPVPYesterdayStats,
--     GetPVPLifetimeStats (lifetime, highest rank: it may read 0 or an old value right
--     after a login: a lifetime count below the last one read is ignored);
--   * battlegrounds: IsInInstance ("pvp" or "arena": the PvP time; "pvp" alone for the
--     main bar's automatic PvP mode and the session's battlegrounds), GetInstanceInfo's
--     instance id; the result at PVP_MATCH_COMPLETE (the winner against the player's side,
--     GetBattlefieldArenaFaction, else the faction; its duration), else
--     GetBattlefieldWinner on UPDATE_BATTLEFIELD_STATUS. C_PvP's score functions are never
--     called (secret during a match), the chat is never read (secret in instances on
--     12.x; parsing it is not allowed: SPEC 2.3);
--   * the resets: C_DateAndTime.GetSecondsUntilWeeklyReset / GetSecondsUntilDailyReset.
-- Classic Era (no currency API or no major faction API): dormant, no event registered.
-- Events (Subscribe): CURRENCY_DISPLAY_UPDATE and PLAYER_PVP_KILLS_CHANGED whenever the
-- APIs exist (the world PvP below is measured whatever is shown: the statistics window
-- always shows it); the rank, place and match events and TICK only while something shows
-- PvP (Wanted: the strip, the main bar's PvP mode or its battleground override, a PvP token
-- on the bar or the shown mini display). Nothing shown and no cap alert: the honor and
-- kills events stay cheap (the reads, the bases, the gains and the world signal; no
-- PVP_CHANGED, no UI work); UPDATE_FACTION, the zone events, the match events and TICK
-- are not registered, the rank is not read, the place only by Pvp.Advance (the honor
-- rate's PvP time; no battleground counted); turned on, the reads take new bases.
--
-- Gains: the rise of the honor quantity between two reads (the quantity's own rise: an
-- amount lost at the cap or an event sent twice does not count, two gains read at once
-- both do; the event's quantityChange is not read) and the rise of the rank's season
-- total, counted on UPDATE_FACTION and the other reads, not on a new rank's event (its
-- read may pair the new rank with the old points or the reverse). Spending and a new
-- season (a lower total with a new weekNumber or season number) take a new base; a lower
-- total in the same week and season is a transient read, ignored. The first real read of
-- a load is a base only (an empty one is not; a login's or a reload's
-- PLAYER_ENTERING_WORLD takes the bases again). TICK watches the weekly and daily
-- countdowns: the weekly reset reads the rank again, the daily one today's kills.
-- The rates (XP parity, Tracker.lua / Reputation.lua): one EMA per exclusion mask for the
-- honor (char.pvp.he) and one for the rank points (ke), { a = points, d = counted seconds },
-- decayed by Tracker's AdvanceRate (Pvp.Advance) with settings.rateTau (the rank's only
-- while something shows PvP: its gains are counted then only), a value from
-- C.WARMUP_MIN counted seconds ("warming"), "ok" from C.WARMUP_FULL. Only PvP time
-- counts: the time in a battleground, and the open-world time less than C.PVP_IDLE seconds
-- after the last honor or rank gain (char.pvp.g, a time(): reloads and logouts do not reset
-- it). Past it, outside a battleground, the rates pause: no decay, status "paused", until
-- the next gain. At the honor cap the honor rate is kept as it was (status "capped": the
-- gains are lost, nothing to measure), as is the rank rate at this week's cap or the max
-- rank.
-- World PvP per level (the Levels tab): open-world time BETWEEN two world PvP signals less
-- than C.PVP_IDLE seconds apart, counted afterwards, so a lone kill counts 0 and the 15
-- minutes after the last fight never count. A signal: a rise of the honor quantity, or of
-- today's honorable kills (GetPVPSessionStats: the honor cap stops the honor, not the
-- kills), read while not in a battleground or an arena (IsInInstance read again on the
-- event). char.pvp.wg is the time() of the last signal, wp the open-world seconds since it
-- per level ({ [level] = seconds }, fed by Pvp.Advance with the Tracker's state "w" only:
-- not AFK, flying, in a city or an inn, dead, crafting or in an instance; at the level of
-- the segment, so a level-up between two signals splits them), w0 the time() measuring
-- began for this character (once: levels ended before it are "not measured", Stats.
-- WorldPvpState). A signal less than C.PVP_IDLE seconds after wg commits wp (rounded per
-- level) to levels[L].pw and life.pw through Tracker.AddLevelStat (record and delta);
-- wp is dropped once wg is C.PVP_IDLE seconds old. pw is a part of s.w (Stats caps it).
-- Nothing in read-only mode, in Classic Era, at a /reload gap or in a rebuilt crash gap
-- (no Advance there). Today's kills are based on the first read above 0 of a load: a 0
-- read before the data is loaded, then the real count, is a base, not a signal (else it
-- would open a window at the login, and commit the pending seconds of a quick relog).
-- The cap alert (pvp.capAlert): when the honor reaches its cap (once per reaching, armed
-- again by a valid read below it), out of combat (else at PLAYER_REGEN_ENABLED), a sound
-- and the addon's own small frame (the automatic reload's look) with an OK button.
-- Persisted per character in char.pvp (see Core.RepairChar), created at the first read;
-- nothing is written in read-only mode. Pvp.Advance, the getters and the TICK check
-- allocate nothing; reads run on events (and on a reset passing, the tooltip opening)
-- only. PVP_CHANGED is sent when anything shown changed.

local type, pcall, format, pairs, next, wipe = type, pcall, string.format, pairs, next, wipe
local math_floor, math_exp, math_huge = math.floor, math.exp, math.huge
local time = time

local Pvp = {}
ns.Pvp = Pvp

local HONOR_ID, RANK_ID, IDLE = C.PVP_HONOR_ID, C.PVP_RANK_FACTION, C.PVP_IDLE
local WARMUP_MIN, WARMUP_FULL = C.WARMUP_MIN, C.WARMUP_FULL
local INCLUDED = C.INCLUDED
local IsSecret = Util.IsSecret

Pvp.WARN = 0.9                 -- the honor strip turns orange from this share of the cap

-- Colours by key: 1 honor, 2 honor from Pvp.WARN of its cap, 3 honor at its cap, 4 rank.
local COLORS = {
  { 0.96, 0.76, 0.2 }, { 1, 0.5, 0.1 }, { 0.9, 0.16, 0.12 }, { 0.45, 0.62, 1 },
}
Pvp.COLORS = COLORS
Pvp.KEY_HONOR, Pvp.KEY_WARN, Pvp.KEY_CAP, Pvp.KEY_RANK = 1, 2, 3, 4

-- What is read (the getters return these numbers).
local S = {
  on = false,                  -- the client has the APIs (the events: Subscribe)
  honor = false, q = 0, max = 0, capAt = nil, alerted = false,
  rank = false, level = 0, pts = 0, thr = 0, maxLevel = 0, week = 0, capLevel = 0, prevCap = 0,
  season = nil,                -- GetCurrentArenaSeason (nil: unknown)
  total = nil, start = nil, capTotal = 0, noSeason = true,
  bg = false, bgPvp = false,   -- in a battleground (or an arena); a battleground ("pvp")
  hkToday = nil, hkYest = nil, hkLife = nil, hkHigh = nil,
}
-- The same fields as last sent with PVP_CHANGED (filled below, from S).
local sent = {}
local hBased, kBased = nil, nil   -- char record whose honor / rank base this load took
local hkBased = nil                -- char record whose today's kills base (world signal) it took
local kWeek, kSeason = nil, nil    -- the week number and the season of the rank's last read
local ver = 0                      -- MainRight's texts version

local function IsNum(v)
  return type(v) == "number" and v == v and v ~= math_huge and v ~= -math_huge
end

-- A finite number that can be read, else nil (the secret test first).
local function Num(v)
  if IsSecret(v) or not IsNum(v) then return nil end
  return v
end

local function Settings()
  local s = ns.settings
  return type(s) == "table" and s or nil
end

-- The client has what the module reads (Classic Era has neither).
local function Available()
  local cur, maj = C_CurrencyInfo, C_MajorFactions
  return type(cur) == "table" and type(cur.GetCurrencyInfo) == "function"
    and type(maj) == "table" and type(maj.GetMajorFactionProgressionInfo) == "function"
end

---------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------

local function HonorFields(t)
  return t.quantity, t.maxQuantity, t.discovered
end

-- Quantity and cap (0: none) of the honor, and whether the read is empty (the data not
-- loaded yet, as at a login: 0 with no cap, or the currency not discovered), or nil.
local function ReadHonor()
  local api = C_CurrencyInfo
  local fn = type(api) == "table" and api.GetCurrencyInfo
  if type(fn) ~= "function" then return nil end
  local ok, t = pcall(fn, HONOR_ID)
  if not ok or IsSecret(t) or type(t) ~= "table" then return nil end
  local okf, q, mx, disc = pcall(HonorFields, t)
  if not okf then return nil end
  q, mx = Num(q), Num(mx)
  if q == nil or q < 0 then return nil end
  if mx == nil or mx < 0 then mx = 0 end
  q, mx = math_floor(q + 0.5), math_floor(mx + 0.5)
  return q, mx, (q == 0 and mx == 0) or (not IsSecret(disc) and disc == false)
end

local function RankFields(t)
  return t.renownLevel, t.renownReputationEarned, t.renownLevelThreshold, t.maxLevel, t.weekNumber,
    t.currentWeekProgressiveMaxLevel, t.previousWeekProgressiveMaxLevel
end

-- Season total needed to reach rank `level` (nil: unknown).
local function TotalFor(fn, level)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, RANK_ID, level)
  if not ok then return nil end
  v = Num(v)
  if v == nil or v < 0 then return nil end
  return math_floor(v + 0.5)
end

local function Int(v)
  return math_floor(v + 0.5)
end

-- The PvP season's number (GetCurrentArenaSeason), or nil.
local function SeasonNumber()
  local fn = GetCurrentArenaSeason
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn)
  if not ok then return nil end
  v = Num(v)
  return v and Int(v) or nil
end

-- The rank into S (S.rank false when it cannot be read). "empty" for a read without data
-- (rank 0, no point, maxLevel 0: not loaded yet), which leaves an earlier read in S, else
-- "ok"; nil when unreadable.
local function ReadRank()
  local api = C_MajorFactions
  local fn = type(api) == "table" and api.GetMajorFactionProgressionInfo
  local had = S.rank
  S.rank = false
  if type(fn) ~= "function" then return nil end
  local ok, t = pcall(fn, RANK_ID)
  if not ok or IsSecret(t) or type(t) ~= "table" then return nil end
  local okf, lv, pts, thr, mxl, wk, cap, prev = pcall(RankFields, t)
  if not okf then return nil end
  lv, pts, thr = Num(lv), Num(pts), Num(thr)
  if lv == nil or pts == nil or thr == nil or lv < 0 or pts < 0 or thr < 0 then return nil end
  mxl, wk, cap, prev = Num(mxl), Num(wk) or 0, Num(cap) or 0, Num(prev) or 0
  if mxl == nil or mxl < 0 then mxl = 0 end
  if cap < 0 then cap = 0 end
  lv, pts, thr, mxl, cap = Int(lv), Int(pts), Int(thr), Int(mxl), Int(cap)
  if lv == 0 and pts == 0 and mxl == 0 and had then
    S.rank = true                                  -- an empty read: the last one stays
    return "empty"
  end
  local tot = api.GetTotalReputationForRenownLevel
  local start = (lv == 0) and 0 or TotalFor(tot, lv)
  local capTotal = 0
  if cap > 0 then capTotal = TotalFor(tot, cap) or 0 end
  S.rank, S.level, S.pts, S.thr, S.maxLevel = true, lv, pts, thr, mxl
  S.week, S.capLevel, S.prevCap = Int(wk), cap, Int(prev)
  S.season = SeasonNumber()
  S.start = start
  S.total = start and (start + pts) or nil
  S.capTotal = capTotal
  -- no season: no point (rank 0, a total of 0) and no week number or no weekly cap
  local none = (S.total == 0) or (S.total == nil and lv == 0 and pts == 0)
  S.noSeason = none and (wk < 1 or cap == 0)
  if lv == 0 and pts == 0 and mxl == 0 then return "empty" end
  return "ok"
end

local function IsMaxRank()
  return S.rank and S.maxLevel > 0 and S.level >= S.maxLevel
end

-- This week's cap reached (the max rank is not a weekly cap).
local function WeekCapped()
  return S.rank and not IsMaxRank() and S.capTotal > 0 and S.total ~= nil and S.total >= S.capTotal
end

-- The next rank is this week's cap (the last one reachable this week: the game's caps are
-- whole ranks, so this rank's end is the cap).
local function LastRank()
  return S.rank and not IsMaxRank() and not WeekCapped() and S.capTotal > 0 and S.start ~= nil and S.thr > 0
    and S.capTotal <= S.start + S.thr
end

local function HonorCapped()
  return S.honor and S.max > 0 and S.q >= S.max
end

-- The rank can still move this week (the rank rate measures).
local function RankActive()
  return S.rank and not S.noSeason and S.total ~= nil and not IsMaxRank() and not WeekCapped()
end

-- First return of a stats function (honorable kills), or nil.
local function Kills(fn)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn)
  if not ok then return nil end
  v = Num(v)
  if v == nil or v < 0 then return nil end
  return Int(v)
end

-- Lifetime kills and highest rank (Forever: kills, rank; Classic: kills, dishonorable, rank).
local function Lifetime()
  local fn = GetPVPLifetimeStats
  if type(fn) ~= "function" then return nil, nil end
  local ok, a, b, c = pcall(fn)
  if not ok then return nil, nil end
  a = Num(a)
  local high = Num(c)
  if c == nil then high = Num(b) end
  if a ~= nil and a < 0 then a = nil end
  return a and Int(a) or nil, high and Int(high) or nil
end

-- The instance's id (GetInstanceInfo's 8th value), or nil.
local function InstanceId()
  local fn = GetInstanceInfo
  if type(fn) ~= "function" then return nil end
  local ok, _, _, _, _, _, _, _, id = pcall(fn)
  if not ok then return nil end
  id = Num(id)
  if id == nil or id <= 0 then return nil end
  return Int(id)
end

-- In a battleground or an arena, in a battleground ("pvp"); the last state when secret.
local function ReadPlace()
  local fn = IsInInstance
  if type(fn) ~= "function" then return false, false end
  local ok, inside, kind = pcall(fn)
  if not ok or IsSecret(inside) or IsSecret(kind) then return S.bg, S.bgPvp end
  if inside ~= true then return false, false end
  return kind == "pvp" or kind == "arena", kind == "pvp"
end

---------------------------------------------------------------------------
-- The character's record (char.pvp), the session, the gains
---------------------------------------------------------------------------

local function NewEma()
  local e = {}
  for m = 1, 8 do e[m] = { a = 0, d = 0 } end
  return e
end

-- char.pvp when it exists (never created here).
local function Rec()
  local char = ns.char
  local p = type(char) == "table" and char.pvp or nil
  return type(p) == "table" and p or nil
end

-- char.pvp, created (with its EMAs) when missing; nil in read-only mode. Events only.
local function Record()
  if ns.readOnly then return nil end
  local char = ns.char
  if type(char) ~= "table" then return nil end
  local p = char.pvp
  if type(p) ~= "table" then
    p = {}
    char.pvp = p
  end
  if type(p.he) ~= "table" then p.he = NewEma() end
  if type(p.ke) ~= "table" then p.ke = NewEma() end
  if type(p.wp) ~= "table" then p.wp = {} end       -- world PvP pending (reused: wipe)
  return p
end

local function SessionT0()
  local s = ns.session
  return type(s) == "table" and s.t0 or nil
end

-- The session's counters, started over when the session changed (events only); nil
-- before the session is known (the first reads of a load, before PLAYER_ENTERING_WORLD:
-- a reload goes on with the session it had).
-- k: the lifetime kills at its start, the last count read (0 reads as unknown: the count
-- may read 0 right after a login; the first count above 0 is taken then, less the kills
-- of today since the session began: d, today's count at its start).
local function Session(p)
  local t0 = SessionT0()
  local s = p.s
  if t0 == nil then return nil end
  if type(s) ~= "table" or s.t ~= t0 then
    local k = Num(p.hk)
    if k ~= nil and k <= 0 then k = nil end
    s = { t = t0, h = 0, r = 0, w = 0, l = 0, n = 0, bh = 0, bd = 0, k = k, d = S.hkToday }
    p.s = s
  end
  return s
end

-- The session's counters when they are this session's (read only), else nil.
local function CurSession()
  local p = Rec()
  local s = p and p.s
  if type(s) ~= "table" or s.t ~= SessionT0() then return nil end
  return s
end

local function Gain(p, which, d)
  local e = (which == "h") and p.he or p.ke
  for m = 1, 8 do
    local x = e[m]
    x.a = x.a + d
  end
  p.g = time()
  local s = Session(p)
  if not s then return end
  if which == "h" then s.h = (s.h or 0) + d else s.r = (s.r or 0) + d end
end

-- A world PvP signal now (see the header; the caller checked the place): the open-world
-- seconds pending since the last one (p.wp) are committed to their levels when it came
-- less than IDLE seconds ago (rounded per level, Tracker.AddLevelStat "pw"), else they
-- are dropped; then the window starts again from now. Events only.
local function WorldSignal(p)
  local t = time()
  local wp = p.wp
  if type(wp) ~= "table" then
    wp = {}
    p.wp = wp
  end
  local last = Num(p.wg)
  if last ~= nil and t - last < IDLE then
    local T = ns.Tracker
    local add = T and T.AddLevelStat
    if add then
      for lvl, secs in pairs(wp) do
        local n = Num(secs)
        n = n and math_floor(n + 0.5) or 0
        if n > 0 then add("pw", n, lvl) end
      end
    end
  end
  wipe(wp)
  p.wg = t
end

-- Decays the EMA of every mask that includes state k by factor f (and g counted seconds).
local function Decay(e, k, f, g)
  for m = 0, 7 do
    if INCLUDED[m][k] then
      local x = e[m + 1]
      if type(x) == "table" then
        x.a = x.a * f
        x.d = x.d * f + g
      end
    end
  end
end

---------------------------------------------------------------------------
-- The honor cap alert
---------------------------------------------------------------------------

local alert = nil              -- the frame (created at its first show)
local pending = false          -- waiting for the end of the fight

local PROMPT_W, TEXT_W, BTN_H = 340, 310, 22
local BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BTN_BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }
local RAID_WARNING = 8959      -- SOUNDKIT.RAID_WARNING where the client has no SOUNDKIT

local function UIColor(role)
  local Themes = ns.Themes
  local th = Themes and Themes.Active and Themes.Active()
  local ui = type(th) == "table" and th.ui
  local c = type(ui) == "table" and ui[role]
  if type(c) == "table" then return c end
  return C.COLORS[role] or C.COLORS.value
end

local function HideAlert()
  if alert then alert:Hide() end
end

local function OnOk()
  HideAlert()
end

local function BuildAlert()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:Hide()
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  if f.SetBackdrop then f:SetBackdrop(BACKDROP) end
  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText(L.ADDON_TITLE)
  local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOP", title, "BOTTOM", 0, -8)
  text:SetWidth(TEXT_W)
  text:SetJustifyH("CENTER")
  local ok = CreateFrame("Button", nil, f, "BackdropTemplate")
  if ok.SetBackdrop then ok:SetBackdrop(BTN_BACKDROP) end
  local fs = ok:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER", ok, "CENTER", 0, 0)
  fs:SetText(L.PVP_ALERT_OK)
  ok:SetSize(100, BTN_H)
  local hl = ok:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(ok)
  hl:SetTexture(C.TEX_WHITE)
  hl:SetVertexColor(1, 1, 1, 0.08)
  ok:SetScript("OnClick", OnOk)
  ok:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  f:SetWidth(PROMPT_W)
  -- read-only handles for the offline tests (our own frame)
  f.tp = { title = title, text = text, ok = ok, okText = fs }
  alert = f
  return f
end

-- The theme's colours, read at each show (an alert is rare).
local function ApplyLook(f)
  local tp = f.tp
  if f.SetBackdrop then
    local bg, bd = UIColor("bg"), UIColor("border")
    f:SetBackdropColor(bg[1], bg[2], bg[3], 0.95)
    f:SetBackdropBorderColor(bd[1], bd[2], bd[3], C.COLORS.border[4])
  end
  local ac, vc, bd = UIColor("accent"), UIColor("value"), UIColor("border")
  tp.title:SetTextColor(ac[1], ac[2], ac[3])
  tp.text:SetTextColor(vc[1], vc[2], vc[3])
  local ok, tr = tp.ok, C.COLORS.track
  if ok.SetBackdrop then
    ok:SetBackdropColor(tr[1], tr[2], tr[3], 1)
    ok:SetBackdropBorderColor(bd[1], bd[2], bd[3], C.COLORS.border[4])
  end
  tp.okText:SetTextColor(vc[1], vc[2], vc[3])
end

local function InCombat()
  if type(InCombatLockdown) == "function" then
    local ok, v = pcall(InCombatLockdown)
    if ok and not IsSecret(v) and v then return true end
  end
  if type(UnitAffectingCombat) == "function" then
    local ok, v = pcall(UnitAffectingCombat, "player")
    if ok and not IsSecret(v) and v then return true end
  end
  return false
end

local function AlertOn()
  local s = Settings()
  local p = s and s.pvp
  return not (type(p) == "table" and p.capAlert == false)
end

local function StopWaiting()
  if not pending then return end
  pending = false
  ns.UnregisterEvent("PLAYER_REGEN_ENABLED", Pvp)
end

-- The sound and the frame, now (the honor is at its cap, out of combat). Marked shown for
-- this reaching (char.pvp.a; in memory too: read-only mode).
local function ShowAlert()
  StopWaiting()
  S.alerted = true
  local p = Record()
  if p then p.a = true end
  local kit = type(SOUNDKIT) == "table" and Num(SOUNDKIT.RAID_WARNING) or RAID_WARNING
  if type(PlaySound) == "function" then pcall(PlaySound, kit, "Master") end
  local f = alert or BuildAlert()
  ApplyLook(f)
  local tp = f.tp
  tp.text:SetText(format(L.PVP_ALERT_FMT, ns.Fmt.Number(S.max)))
  local h = tp.text:GetStringHeight()
  if type(h) ~= "number" or h <= 0 then h = 14 end
  f:SetHeight(math_floor(12 + 14 + 8 + h + 12 + BTN_H + 12 + 0.5))
  f:Show()
end

local function OnRegenEnabled()
  StopWaiting()
  if HonorCapped() and not S.alerted and AlertOn() then ShowAlert() end
end

-- The honor reached its cap: alert now, or once the fight is over.
local function RequestAlert()
  if S.alerted or not AlertOn() then return end
  if InCombat() then
    if not pending then
      pending = true
      ns.RegisterEvent("PLAYER_REGEN_ENABLED", Pvp, OnRegenEnabled)
    end
    return
  end
  ShowAlert()
end

-- Below the cap again (spent: a valid read under it): armed for the next reaching.
local function Rearm(p)
  S.capAt, S.alerted = nil, false
  if p then p.c, p.a = nil, nil end
  StopWaiting()
  HideAlert()
end

-- The cap state after an honor read: since when, and the alert. Armed again only by a
-- valid read below the cap (a cap read 0 or unreadable once is no spending). In read-only
-- mode the alert shown stays in memory (S.alerted) for the load.
local function CapState(p)
  if not HonorCapped() then
    if S.max > 0 and S.q < S.max
        and (S.capAt ~= nil or S.alerted or pending or (p and (p.c ~= nil or p.a ~= nil))) then
      Rearm(p)
    end
    return
  end
  if S.capAt == nil then S.capAt = (p and Num(p.c)) or time() end
  if p then
    if p.c == nil then p.c = S.capAt end
    if p.a == true then S.alerted = true end
  end
  RequestAlert()
end

---------------------------------------------------------------------------
-- Updates (events)
---------------------------------------------------------------------------

local FIELDS = { "honor", "q", "max", "rank", "level", "pts", "thr", "maxLevel", "capLevel", "capTotal",
                 "noSeason", "total", "bg", "bgPvp" }

-- PVP_CHANGED when anything shown changed.
local function Changed()
  local diff = false
  for i = 1, #FIELDS do
    local f = FIELDS[i]
    if sent[f] ~= S[f] then
      sent[f] = S[f]
      diff = true
    end
  end
  if diff then
    ver = ver + 1
    ns.SendMessage("PVP_CHANGED")
  end
end

-- The honor read again: its rise since the last read is a gain (the quantity's own rise:
-- an amount lost at the cap or an event sent twice does not count, two gains read at once
-- both do). An empty read (not loaded yet) is no base, no gain and no cap state, and leaves
-- an earlier read shown.
local function UpdateHonor()
  local q, mx, empty = ReadHonor()
  if q == nil then
    S.honor = false
    return
  end
  if empty then
    if not S.honor then S.honor, S.q, S.max = true, q, mx end
    return
  end
  S.honor, S.q, S.max = true, q, mx
  local p = Record()
  if p then
    local char = ns.char
    if hBased ~= char then
      hBased = char
      p.h = q                                    -- the first real read of this load: a base only
    else
      local prev = p.h
      p.h = q
      if IsNum(prev) and q > prev then
        Gain(p, "h", q - prev)
        if not (ReadPlace()) then WorldSignal(p) end   -- honor gained out of a battleground
      end
    end
  end
  CapState(p)
end

-- The rank read again; a rise of the season total is a gain. `count` false: shown only (a
-- new rank's event, whose read may pair the new rank with the old points or the reverse;
-- the UPDATE_FACTION after it counts). A lower total in the same week and season is a
-- transient read: ignored (no base, no gain); a new week number or season with a lower
-- total is a new season: a new base. An empty read is no base.
local function UpdateRank(count)
  local how = ReadRank()
  if how ~= "ok" or S.total == nil or count == false then return end
  local p = Record()
  if not p then return end
  local char, total = ns.char, S.total
  local prev = p.k
  if kBased == char and IsNum(prev) and total < prev and S.week == kWeek and S.season == kSeason then
    return
  end
  local first = kBased ~= char or not IsNum(prev) or total < prev
  kBased, kWeek, kSeason = char, S.week, S.season
  p.k = total
  if not first and total > prev then Gain(p, "k", total - prev) end
end

-- Honorable kills; the lifetime count never goes back (an old value after a login). A rise
-- of today's count since the last read of this load, out of a battleground, is a world PvP
-- signal (it goes on at the honor cap). The base of a load is its first read above 0 (a 0
-- read before the data is loaded, then the real count, is no signal; so the first kill of
-- the day of a character at 0 is a base only, its honor still a signal); a fall once based
-- (the daily reset) is a new base.
local function UpdateKills()
  local before = S.hkToday
  S.hkToday = Kills(GetPVPSessionStats)
  local today, char = S.hkToday, ns.char
  if today ~= nil and today > 0 then               -- (0: no base, and never a rise)
    if hkBased == char and before ~= nil and today > before and not (ReadPlace()) then
      local p = Record()
      if p then WorldSignal(p) end
    end
    hkBased = char
  end
  S.hkYest = Kills(GetPVPYesterdayStats)
  local life, high = Lifetime()
  S.hkHigh = high
  local p = Rec()
  local last = p and Num(p.hk) or S.hkLife
  if life ~= nil and (last == nil or life >= last) then
    S.hkLife = life
    if p and not ns.readOnly then
      local s = Session(p)                       -- (a new one starts from the count before)
      p.hk = life
      if s and s.d == nil then s.d = S.hkToday end
      if s and s.k == nil and life > 0 then      -- no earlier count: from this one, less the
        local d = Num(s.d)                       -- kills of today since the session began
        s.k = life - ((d and today and today > d) and (today - d) or 0)
      end
    end
  elseif last ~= nil then
    S.hkLife = last
  end
end

-- The player's side in the match: GetBattlefieldArenaFaction (0 Horde, 1 Alliance; the
-- game's results screen compares the winner with it), else the player's faction; nil.
local function Side()
  local fn = GetBattlefieldArenaFaction
  if type(fn) == "function" then
    local ok, v = pcall(fn)
    v = ok and Num(v) or nil
    if v == 0 or v == 1 then return v end
  end
  if type(UnitFactionGroup) ~= "function" then return nil end
  local ok, fac = pcall(UnitFactionGroup, "player")
  if not ok or IsSecret(fac) then return nil end
  return (fac == "Horde" and 0) or (fac == "Alliance" and 1) or nil
end

-- 1 won, 0 lost, 2 neither side (a draw); nil unknown.
local function Result(winner)
  local w = Num(winner)
  if w == nil then return nil end
  if w ~= 0 and w ~= 1 then return 2 end
  local mine = Side()
  if mine == nil then return nil end
  return (w == mine) and 1 or 0
end

-- A battleground left: the session's counters.
local function CloseBG(p)
  local b = p.b
  p.b = nil
  local s = Session(p)
  if type(b) ~= "table" or not s then return end
  s.n = (s.n or 0) + 1
  local gained = (s.h or 0) - (b.h or 0)
  if gained > 0 then s.bh = (s.bh or 0) + gained end
  local dur = Num(b.d)
  if dur == nil or dur <= 0 then dur = time() - (b.at or time()) end
  if dur > 0 then s.bd = (s.bd or 0) + dur end
  if b.r == 1 then s.w = (s.w or 0) + 1 elseif b.r == 0 then s.l = (s.l or 0) + 1 end
end

-- Where the player is: a battleground (instance type "pvp"; an arena counts as PvP time,
-- not as a battleground) entered or left. The one in progress (p.b, its instance id i) is
-- closed when the player leaves it, when the instance id changes, and at a loading screen
-- inside a battleground once its match is over (`fresh`: from one battleground straight
-- into the next, the same map included). A reload keeps it (same instance, no loading
-- screen); one left while logged out is dropped.
local function UpdatePlace(fresh)
  local bg, bgPvp = ReadPlace()
  local p = Record()
  if p then
    local b = p.b
    if type(b) == "table" then
      local id, bi = bgPvp and InstanceId() or nil, Num(b.i)
      if not bgPvp or (id ~= nil and bi ~= nil and id ~= bi) or (fresh and (b.r ~= nil or b.d ~= nil)) then
        if S.bgPvp then CloseBG(p) else p.b = nil end
      end
    end
    if bgPvp and type(p.b) ~= "table" then
      local s = Session(p)
      p.b = { at = time(), h = s and s.h or 0, i = InstanceId() }
    end
  end
  S.bg, S.bgPvp = bg, bgPvp
end

-- subCur: the honor shown or the cap alert on (Subscribe); without either, an honor event
-- only reads and records (the world signal), no PVP_CHANGED.
local subCur = false

local function OnCurrency(_, currencyType)
  local id = Num(currencyType)
  if id ~= nil and id ~= HONOR_ID then return end
  UpdateHonor()
  if subCur then Changed() end
end

local function OnFaction(event, id)
  local fid = Num(id)
  -- MAJOR_FACTION_RENOWN_LEVEL_CHANGED of another faction (UPDATE_FACTION has no payload)
  if fid ~= nil and fid ~= RANK_ID then return end
  UpdateRank(event ~= "MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
  Changed()
end

local function OnKills()
  UpdateKills()
end

local function OnPlace()
  UpdatePlace()
  Changed()
end

local function ReadAll(fresh)
  UpdatePlace(fresh)
  UpdateHonor()
  UpdateRank()
  UpdateKills()
  Changed()
end

-- /tpl debug: what a read gave and whether it took the bases (-1: not read; base 1 taken,
-- 0 not: an empty read at PLAYER_LOGIN, before the data is loaded). Events only.
local function DebugReads(when)
  local char = ns.char
  Util.Debug("PvP %s: honor %d / %d (base %d), rank %d, %d points, max rank %d (base %d)", when,
    S.honor and S.q or -1, S.honor and S.max or -1, (hBased ~= nil and hBased == char) and 1 or 0,
    S.rank and S.level or -1, S.rank and S.pts or -1, S.rank and S.maxLevel or -1,
    (kBased ~= nil and kBased == char) and 1 or 0)
end

-- A login or a reload: the bases taken again (the reads at PLAYER_LOGIN may come before
-- the data); any other loading screen: a new place.
local function OnWorld(_, isLogin, isReload)
  local start = isLogin == true or isReload == true
  if start then hBased, kBased, hkBased = nil, nil, nil end
  ReadAll(not start)
  if start then DebugReads("world") end
end

local function OnMatch(_, winner, duration)
  if not S.bgPvp then return end
  local p = Record()
  local b = p and p.b
  if type(b) ~= "table" then return end
  local r = Result(winner)
  if r ~= nil then b.r = r end
  local d = Num(duration)
  if d ~= nil and d > 0 then b.d = Int(d) end
end

local function OnStatus()
  if not S.bgPvp then return end
  local p = Rec()
  local b = p and p.b
  if type(b) ~= "table" or b.r ~= nil or ns.readOnly then return end
  local fn = GetBattlefieldWinner
  if type(fn) ~= "function" then return end
  local ok, w = pcall(fn)
  if not ok then return end
  local r = Result(w)
  if r ~= nil then b.r = r end
end

-- The resets passing (TICK while something shows PvP): a countdown that rose by more than
-- RESET_JUMP s since the last tick. The weekly one reads the rank again (the new cap; read
-- once more RESET_AGAIN s later, in case the game updates it a little after), the daily
-- one today's kills. Two API calls a tick, nothing allocated.
local RESET_JUMP, RESET_AGAIN = 3600, 30
local wLast, dLast, againAt = nil, nil, nil

-- Seconds of a countdown (C_DateAndTime), nil when unknown.
local function Countdown(fn)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn)
  if not ok then return nil end
  v = Num(v)
  if v == nil or v <= 0 then return nil end
  return v
end

local function OnTick(_, now)
  local api = C_DateAndTime
  if type(api) ~= "table" then return end
  local w = Countdown(api.GetSecondsUntilWeeklyReset)
  if w ~= nil then
    local passed = wLast ~= nil and w > wLast + RESET_JUMP
    wLast = w
    if passed then
      againAt = type(now) == "number" and now + RESET_AGAIN or nil
      UpdateRank()
      Changed()
    end
  end
  if againAt ~= nil and type(now) == "number" and now >= againAt then
    againAt = nil
    UpdateRank()
    Changed()
  end
  local d = Countdown(api.GetSecondsUntilDailyReset)
  if d ~= nil then
    local passed = dLast ~= nil and d > dLast + RESET_JUMP
    dLast = d
    if passed then UpdateKills() end
  end
end

for i = 1, #FIELDS do sent[FIELDS[i]] = S[FIELDS[i]] end

-- The events while something shows PvP (Wanted). Nothing shows PvP: none of them (an
-- UPDATE_FACTION is sent at every reputation gain), the rank not read, the place by
-- Pvp.Advance only, the session's battlegrounds not counted; turned on, the reads take
-- new bases. The honor and today's kills (WORLD_EVENTS) are registered whenever the APIs
-- exist: the world PvP signals, the honor rate and the cap alert.
local USE_EVENTS = {
  UPDATE_FACTION = OnFaction, MAJOR_FACTION_RENOWN_LEVEL_CHANGED = OnFaction,
  PLAYER_ENTERING_WORLD = OnWorld, ZONE_CHANGED_NEW_AREA = OnPlace,
  PVP_MATCH_COMPLETE = OnMatch, UPDATE_BATTLEFIELD_STATUS = OnStatus,
}
local WORLD_EVENTS = { CURRENCY_DISPLAY_UPDATE = OnCurrency, PLAYER_PVP_KILLS_CHANGED = OnKills }
local subUse, subOn = false, false

-- A PvP token in list t (the bar's slots, the mini display's infos)? Tokens.DEF[id].pvp.
local function UsesToken(t)
  if type(t) ~= "table" then return false end
  local Tk = ns.Tokens
  local def = Tk and Tk.DEF
  if type(def) ~= "table" then return false end
  for i = 1, 3 do
    local d = def[t[i]]
    if type(d) == "table" and d.pvp then return true end
  end
  return false
end

-- Something shows PvP: the strip, the main bar's PvP mode or its battleground override, a
-- PvP token on the bar (its slots, at max level too) or in the shown mini display.
local function Wanted()
  local s = Settings()
  if not s then return false end
  local w = s.widget
  if type(w) == "table" and (w.pvp == "honor" or w.pvp == "rank" or w.main == "pvp" or w.pvpAuto == true
      or UsesToken(w.slots) or UsesToken(w.maxSlots)) then
    return true
  end
  local m = s.mini
  return type(m) == "table" and m.shown == true and UsesToken(m.infos)
end

local function Subscribe()
  local on = S.on and true or false
  local use = on and Wanted()
  subCur = on and (use or AlertOn())
  if on ~= subOn then
    subOn = on
    hBased, hkBased = nil, nil                     -- not read meanwhile: new bases
    for ev, fn in pairs(WORLD_EVENTS) do
      if on then ns.RegisterEvent(ev, Pvp, fn) else ns.UnregisterEvent(ev, Pvp) end
    end
  end
  if use ~= subUse then
    subUse = use
    kBased = nil
    wLast, dLast, againAt = nil, nil, nil
    for ev, fn in pairs(USE_EVENTS) do
      if use then ns.RegisterEvent(ev, Pvp, fn) else ns.UnregisterEvent(ev, Pvp) end
    end
    if use then ns.RegisterMessage("TICK", Pvp, OnTick) else ns.UnregisterMessage("TICK", Pvp) end
  end
end

local function SetEnabled(on)
  if on ~= S.on then
    S.on = on
    hBased, kBased, hkBased = nil, nil, nil
    if not on then
      S.honor, S.rank, S.bg, S.bgPvp = false, false, false, false
      StopWaiting()
      HideAlert()
    end
  end
  Subscribe()
end

---------------------------------------------------------------------------
-- Public: state
---------------------------------------------------------------------------

-- The settings or the record changed (DB_READY, DB_SWAPPED, CHAR_RESET, what shows PvP):
-- the events follow, then everything is read again. The record's world PvP measuring
-- starts now if it never did (char.pvp.w0; not in read-only mode).
function Pvp.Refresh()
  SetEnabled(Available())
  if S.on then
    local p = Record()
    if p and Num(p.w0) == nil then p.w0 = time() end
    ReadAll()
    DebugReads("read")
  else
    Changed()
  end
end

-- The client has the PvP APIs (else the module stays dormant: Classic Era).
function Pvp.Available()
  return Available()
end

-- Honor or rank read.
function Pvp.Has()
  return S.on and (S.honor or S.rank)
end

-- read, quantity, cap (0: none), time() it reached its cap (nil: below).
function Pvp.Honor()
  return S.honor, S.q, S.max, S.capAt
end

-- read, rank, points inside it, points of the rank, max rank (0: unknown), no season, the
-- max rank reached, season total (nil: unknown), total of the rank (nil: unknown).
function Pvp.Rank()
  return S.rank, S.level, S.pts, S.thr, S.maxLevel, S.noSeason, IsMaxRank(), S.total, S.start
end

-- This week: its number, the rank cap (0: none), its season total (0: none), the cap of the
-- week before, reached, the next rank is the cap (the last one reachable this week).
function Pvp.Week()
  return S.week, S.capLevel, S.capTotal, S.prevCap, WeekCapped(), LastRank() and true or false
end

-- In a battleground or an arena; in a battleground (instance type "pvp").
function Pvp.InBG()
  return S.bg, S.bgPvp
end

-- Honorable kills: today, yesterday, this session, lifetime, highest rank (PvPRanks, nil:
-- unknown). Any may be nil.
function Pvp.Kills()
  local s = CurSession()
  local ses = nil
  if s and Num(s.k) and S.hkLife ~= nil then
    ses = S.hkLife - s.k
    if ses < 0 then ses = 0 end
  end
  return S.hkToday, S.hkYest, ses, S.hkLife, S.hkHigh
end

-- The tooltip opens: the rank (a weekly reset may have passed without an event) and the
-- kills (the daily one) read again.
function Pvp.ReadAgain()
  if not S.on then return end
  UpdateRank()
  UpdateKills()
  Changed()
end

-- This session: honor gained, rank points gained, wins, losses, battlegrounds, their
-- average honor (nil: none), their average seconds (nil: none).
function Pvp.Session()
  local s = CurSession()
  if not s then return 0, 0, 0, 0, 0, nil, nil end
  local n = s.n or 0
  local ah, ad = nil, nil
  if n > 0 then
    ah = (s.bh or 0) / n
    ad = (s.bd or 0) / n
  end
  return s.h or 0, s.r or 0, s.w or 0, s.l or 0, n, ah, ad
end

-- Seconds to the weekly reset, to the season's end (nil: unknown).
function Pvp.WeeklyReset()
  local api = C_DateAndTime
  return Countdown(type(api) == "table" and api.GetSecondsUntilWeeklyReset)
end

function Pvp.SeasonEnd()
  local api = C_SeasonInfo
  local fn = type(api) == "table" and api.GetTimeUntilCurrentPVPSeasonEnd
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn)
  if not ok then return nil end
  v = Num(v)
  if v == nil or v <= 0 then return nil end
  return v
end

---------------------------------------------------------------------------
-- Public: the rates
---------------------------------------------------------------------------

-- Rate of `which` ("honor" | "rank") under `mask`: per hour (nil: none yet), status
-- ("nodata" | "warming" | "ok" | "paused" | "capped"), counted seconds still needed before
-- "ok", seconds since the last PvP gain (nil: none), per counted second. No allocation.
function Pvp.Rate(which, mask)
  local p = Rec()
  local e = p and ((which == "rank") and p.ke or p.he)
  if type(e) ~= "table" then return nil, "nodata", 0, nil, nil end
  local x = e[(mask or 0) + 1]
  if type(x) ~= "table" then return nil, "nodata", 0, nil, nil end
  local a, d = x.a, x.d
  if not IsNum(a) or not IsNum(d) then return nil, "nodata", 0, nil, nil end
  local g = Num(p.g)
  local idle = g and (time() - g) or nil
  if idle ~= nil and idle < 0 then idle = 0 end
  local left = WARMUP_FULL - d
  if left < 0 then left = 0 end
  local status
  if a > 0 and d >= WARMUP_FULL then
    status = "ok"
  elseif a > 0 and d >= WARMUP_MIN then
    status = "warming"
  else
    -- no gain yet: time alone will not do
    if not (a > 0) then left = 0 end   -- luacheck: ignore 581 (NaN fails too)
    return nil, "nodata", left, idle, nil
  end
  if which == "rank" then
    if IsMaxRank() or WeekCapped() then status = "capped" end
  elseif HonorCapped() then
    status = "capped"
  end
  if status ~= "capped" and not S.bg and (idle == nil or idle >= IDLE) then status = "paused" end
  local ps = a / d
  return 3600 * ps, status, left, idle, ps
end

-- Counted seconds to the honor cap at the current rate (0 at the cap; nil: no cap or no
-- rate), and the rate's status ("capped" at the cap, "nocap" without one).
function Pvp.HonorEta(mask)
  if not S.honor or S.max <= 0 then return nil, "nocap" end
  if S.q >= S.max then return 0, "capped" end
  local _, status, _, _, ps = Pvp.Rate("honor", mask)
  if not ps or ps <= 0 then return nil, status end
  return (S.max - S.q) / ps, status
end

-- Counted seconds to the next rank (nil: none), its status ("none" no rank read,
-- "noseason", "max", "capped" at this week's cap, else the rate's), and the next rank.
function Pvp.RankEta(mask)
  if not S.rank then return nil, "none", nil end
  if S.noSeason then return nil, "noseason", nil end
  if IsMaxRank() then return nil, "max", nil end
  local nxt = S.level + 1
  if WeekCapped() then return nil, "capped", nxt end
  local _, status, _, _, ps = Pvp.Rate("rank", mask)
  if not ps or ps <= 0 then return nil, status, nxt end
  return (S.thr - S.pts) / ps, status, nxt
end

-- dt counted seconds of state k at level lvl, ending now (Tracker's AdvanceRate, every
-- Flush; never in read-only mode): the PvP part of them decays the EMAs (see the header;
-- the rank's only while something shows PvP, subUse: else UPDATE_FACTION is not
-- registered, no rank gain is counted, and the decay alone would bias its rate down);
-- in state "w", the part inside the world PvP window [wg, wg + IDLE] is pending at lvl
-- (p.wp, committed by the next signal); the window run out, the pending seconds are
-- dropped. Nothing shows PvP (no zone event): the place is read here, else a load in a
-- battleground would count all the time after it as PvP time. Allocation free (the first
-- pending second of a level after a signal adds its key: an event's cost).
function Pvp.Advance(dt, k, lvl)
  if not S.on or ns.readOnly or type(dt) ~= "number" or dt <= 0 then return end
  local p = Rec()
  if not p then return end
  if not subUse then S.bg, S.bgPvp = ReadPlace() end
  local wg, wp = Num(p.wg), p.wp
  if wg ~= nil and type(wp) == "table" then
    local now = time()
    if now - wg >= IDLE then
      if next(wp) ~= nil then wipe(wp) end
    elseif k == "w" and type(lvl) == "number" then
      local from = now - dt
      if from < wg then from = wg end
      if now > from then wp[lvl] = (wp[lvl] or 0) + (now - from) end
    end
  end
  local n = dt
  if not S.bg then
    local last = Num(p.g)
    if last == nil then return end
    local left = last + IDLE - (time() - dt)     -- PvP time left at the segment's start
    if left <= 0 then return end
    if left < dt then n = left end
  end
  local s = Settings()
  local tau = s and s.rateTau
  if type(tau) ~= "number" or tau < 60 then tau = 3600 end
  local f = math_exp(-n / tau)
  local g = tau * (1 - f)
  if type(p.he) == "table" and S.honor and not HonorCapped() then Decay(p.he, k, f, g) end
  if type(p.ke) == "table" and subUse and RankActive() then Decay(p.ke, k, f, g) end
end

-- Both rates start over (the options' button, Core.ResetRate). False in read-only mode.
function Pvp.ResetRate()
  if ns.readOnly then return false end
  local p = Rec()
  if p then
    p.he, p.ke = NewEma(), NewEma()
  end
  ver = ver + 1
  return true
end

---------------------------------------------------------------------------
-- Public: what the bar shows
---------------------------------------------------------------------------

-- The main track's PvP content: "rank" (a season running), else "honor" (with a cap),
-- else nil (the main bar shows the XP).
function Pvp.MainKind()
  if not S.on then return nil end
  if S.rank and not S.noSeason then return "rank" end
  if S.honor and S.max > 0 then return "honor" end
  return nil
end

-- What the main track shows: widget.main, "pvp" while in a battleground with
-- widget.pvpAuto (a temporary override: widget.main is never written), "xp" for "pvp"
-- without PvP data.
function Pvp.MainMode(w)
  local m = type(w) == "table" and w.main or "xp"
  local want = m == "pvp" or (type(w) == "table" and w.pvpAuto == true and S.bgPvp)
  if want and Pvp.MainKind() ~= nil then return "pvp" end
  if m == "pvp" then return "xp" end
  return m
end

-- What the PvP strip shows (widget.pvp): "honor" (with a cap), "rank" (a rank read), nil.
function Pvp.StripKind(w)
  if not S.on then return nil end
  local k = type(w) == "table" and w.pvp or nil
  if k == "honor" and S.honor and S.max > 0 then return "honor" end
  if k == "rank" and S.rank then return "rank" end
  return nil
end

-- Colour key of the honor: 1 normal, 2 from Pvp.WARN of the cap, 3 at the cap.
local function HonorKey()
  if S.max > 0 and S.q >= S.max then return 3 end
  if S.max > 0 and S.q >= S.max * Pvp.WARN then return 2 end
  return 1
end

-- value, span, colour key, full of "honor" or "rank" (nil: nothing).
function Pvp.Value(kind)
  if kind == "honor" then
    if not S.honor or S.max <= 0 then return nil end
    local q = S.q
    if q > S.max then q = S.max end
    return q, S.max, HonorKey(), S.q >= S.max
  elseif kind == "rank" then
    if not S.rank then return nil end
    if IsMaxRank() then
      local t = S.thr > 0 and S.thr or 1           -- full (no threshold read at the top)
      return t, t, 4, true
    end
    local thr = S.thr
    local v = S.pts
    if thr <= 0 then return 0, 1, 4, false end
    if v > thr then v = thr end
    return v, thr, 4, false
  end
  return nil
end

-- The colour of key k: three numbers, nothing allocated.
function Pvp.Color(k)
  local c = COLORS[k] or COLORS[1]
  return c[1], c[2], c[3]
end

-- The same as an { r, g, b, 1 } array (tooltip rows): one per key, made at its first use.
local rgba = {}
function Pvp.ColorArray(k)
  local t = rgba[k]
  if not t then
    local c = COLORS[k] or COLORS[1]
    t = { c[1], c[2], c[3], 1 }
    rgba[k] = t
  end
  return t
end

-- "Rank 7" and the rank's title (Tooltip.PvpRankTitle: the game's, by faction and sex;
-- nil when it has none). The rank 0 has its title alone. Cached per rank.
local rankNames = {}
function Pvp.RankName(level)
  local Tt = ns.Tooltip
  local title = Tt and Tt.PvpRankTitle and Tt.PvpRankTitle(level) or nil
  if level == nil or level <= 0 then return title or L.PVP_UNRANKED, nil end
  local n = rankNames[level]
  if not n then
    n = format(L.PVP_RANK_FMT, level)
    rankNames[level] = n
  end
  return n, title
end

-- The main track's right text in the rank mode: three variants (longest first) and their
-- version (a new one when a text changed), or nil (the bar shows the rank's points: no
-- rate yet). The longest says when the next rank is this week's cap. Strings made only
-- when what they show changed (TICK path).
local rk, ek, sk, lk = nil, nil, nil, nil
local r1, r2, r3 = nil, nil, nil
function Pvp.MainRight(mask)
  if not S.rank or S.noSeason then return nil end
  local k1, k2, k3, k4
  if IsMaxRank() then
    k1, k2, k3, k4 = -1, 0, 0, S.level
  elseif WeekCapped() then
    k1, k2, k3, k4 = -2, 0, 0, S.level
  else
    local v, status = Pvp.Rate("rank", mask)
    if v == nil then return nil end
    local eta = Pvp.RankEta(mask)
    k1 = ns.Fmt.ShortKey(v)
    k2 = eta and ns.Fmt.ETAKey(eta) or -1
    k3 = ((status == "paused" or status == "capped") and 1 or 0) + (LastRank() and 2 or 0)
    k4 = S.level
    if k1 ~= rk or k2 ~= ek or k3 ~= sk or k4 ~= lk then
      local rate = ns.Fmt.Rate(v)
      if k3 % 2 == 1 then rate = rate .. L.STALL_MARK end
      local nxt
      if eta then
        local e = ns.Fmt.ETA(eta)
        nxt = format(k3 >= 2 and L.PVP_NEXT_CAP_FMT or L.PVP_NEXT_RANK_FMT, S.level + 1, e)
        r3 = e
      else
        nxt, r3 = L.DOTS, rate
      end
      r1 = format(L.PVP_MAIN_RATE_FMT, rate, nxt)
      r2 = rate .. L.SEP .. r3
      rk, ek, sk, lk = k1, k2, k3, k4
      ver = ver + 1
    end
    return r1, r2, r3, ver
  end
  if k1 ~= rk or k4 ~= lk then
    rk, ek, sk, lk = k1, k2, k3, k4
    if k1 == -1 then
      r1, r2, r3 = L.PVP_RANK_MAX, L.PVP_RANK_MAX, L.PVP_RANK_MAX
    else
      r1, r2, r3 = L.PVP_WEEK_CAPPED, L.PVP_WEEK_CAPPED_SHORT, L.PVP_WEEK_CAPPED_SHORT
    end
    ver = ver + 1
  end
  return r1, r2, r3, ver
end

-- The token context (Tokens.UpdateContext, TICK path: no allocation).
function Pvp.FillContext(c, mask)
  c.pvpOn = Pvp.Has() and true or false
  c.honorOn, c.honor, c.honorMax = S.on and S.honor, S.q, S.max
  local v, st = Pvp.Rate("honor", mask)
  c.honorh, c.honorStatus = v, st
  c.honorEta, c.honorEtaStatus = Pvp.HonorEta(mask)
  c.rankOn, c.rankLevel, c.rankPts, c.rankThr = S.on and S.rank, S.level, S.pts, S.thr
  c.noSeason, c.rankMax = S.noSeason, IsMaxRank() and true or false
  v, st = Pvp.Rate("rank", mask)
  c.rankh, c.rankStatus = v, st
  c.rankEta, c.rankEtaStatus, c.rankNext = Pvp.RankEta(mask)
  c.hkToday = S.on and S.hkToday or nil
end

-- The alert frame (tests), and whether it waits for the end of a fight.
function Pvp.GetAlert()
  return alert, pending
end

local function OnSettingsChanged(_, path)
  if type(path) ~= "string" then return end
  if path == "pvp.capAlert" and not AlertOn() then
    StopWaiting()
    HideAlert()
  end
  -- what shows PvP (or the alert): the events follow (Subscribe), read again when they change
  if path == "pvp.capAlert" or path == "widget.pvp" or path == "widget.main" or path == "widget.pvpAuto"
      or path == "mini.shown" or path:find("widget.slots.", 1, true) == 1
      or path:find("widget.maxSlots.", 1, true) == 1 or path:find("mini.infos.", 1, true) == 1 then
    local use, cur = subUse, subCur
    Subscribe()
    if S.on and (use ~= subUse or cur ~= subCur) then ReadAll() end
  end
end

-- Another record (a late SavedVariables table) or this one rebuilt: new bases.
local function OnRecord()
  hBased, kBased, hkBased = nil, nil, nil
  S.capAt, S.alerted = nil, false
  StopWaiting()
  HideAlert()
  Pvp.Refresh()
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", Pvp, Pvp.Refresh)
  ns.RegisterMessage("DB_SWAPPED", Pvp, OnRecord)
  ns.RegisterMessage("CHAR_RESET", Pvp, OnRecord)
  ns.RegisterMessage("SETTINGS_CHANGED", Pvp, OnSettingsChanged)
end
