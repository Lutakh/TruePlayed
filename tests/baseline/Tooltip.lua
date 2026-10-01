-- Tooltip.lua - short and detailed tooltips (SPEC-FINAL 3.12, 7.6).
--
-- Content is built only while a tooltip is shown. While our GameTooltip is shown the
-- module listens to TICK and MODIFIER_STATE_CHANGED (Shift switches to the detailed
-- view); both are unregistered as soon as it is hidden or taken by another owner.
-- Fill() reads only the current character (ns.char + the Tracker sync), except the
-- explicitly labelled account line (5.19). Refreshes allocate strings only: row tables
-- are reused. The short view keeps the essentials; the rate details (source of the
-- estimate, session / level rates) belong to the detailed view.
-- A rate estimated from the pre-install /played (status "estimate") is shown as
-- "~value" followed by the dimmed L.RATE_ESTIMATE; without any data the XP per hour
-- line says how much counted play is still needed, never a bare "...".
-- The breakdown line lists the parts of the tracked time in a fixed order (world,
-- dungeons, raids, PvP, flight, AFK, inn, city), leaving out the parts that round to
-- 0 %, BD_PER_LINE parts per line. Instance time (dungeons, raids, PvP) also has its
-- own lines: the filtered total in the short view, each kind with its AFK part and
-- the account total in the detailed view.
-- A frozen rate (status "stalled": no XP gained for a while) is shown dimmed with
-- L.STALL_MARK, and a note says for how much counted play no XP came. A detected server
-- level cap replaces the XP block with the cap line and says tracking resumes by itself.
local ADDON, ns = ...
local L, C, Fmt = ns.L, ns.C, ns.Fmt

local type, time = type, time
local format, floor = string.format, math.floor
local table_concat = table.concat
local GetTime, IsShiftKeyDown = GetTime, IsShiftKeyDown
local GetFramerate, GetNetStats = GetFramerate, GetNetStats

local Tooltip = {}
ns.Tooltip = Tooltip

local COLORS = C.COLORS
local LR, LG, LB = COLORS.label[1], COLORS.label[2], COLORS.label[3]
local VR, VG, VB = COLORS.value[1], COLORS.value[2], COLORS.value[3]
local DR, DG, DB = COLORS.dim[1], COLORS.dim[2], COLORS.dim[3]
local PR, PG, PB = COLORS.pause[1], COLORS.pause[2], COLORS.pause[3]
local AR, AG, AB = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
local CC_DIM, CC_RESET = C.CC.dim, C.CC.reset
local RECENT_LEVELS = C.RECENT_LEVELS
local TOP_ROWS = 3
local CONT_ROWS = 5
local BD_PER_LINE = 5           -- breakdown parts per tooltip line

local shownFor = nil            -- owner of our GameTooltip while it is shown
local shownHint = nil           -- hint line of the shown tooltip (nil = L.TT_HINT)
local rowsZones, rowsCities, rowsCont, rowsContRaw = {}, {}, {}, {}   -- reused Stats row tables
local breakdown = {}            -- reused Stats.Breakdown output
local bdParts = {}              -- reused breakdown part texts (tooltip build only)

-- Breakdown parts, fixed order: locale key of the label, Stats.Breakdown field. The
-- flight part (active flight, "t") has no field of its own: active minus the rest.
local BD_ORDER = {
  { "BD_WORLD", "world" }, { "BD_DUNGEON", "dungeon" }, { "BD_RAID", "raid" }, { "BD_PVP", "pvp" },
  { "BD_TAXI", false }, { "BD_AFK", "afk" }, { "BD_INN", "inn" }, { "BD_CITY", "city" },
}

---------------------------------------------------------------------------
-- Line helpers (labels grey, values white)
---------------------------------------------------------------------------

local function Pair(tt, left, right)
  tt:AddDoubleLine(left, right, LR, LG, LB, VR, VG, VB)
end

local function PairDim(tt, left, right)
  tt:AddDoubleLine(left, right, LR, LG, LB, DR, DG, DB)
end

local function Note(tt, text)
  tt:AddLine(text, DR, DG, DB)
end

local function Header(tt, text)
  tt:AddLine(text, AR, AG, AB)
end

local function Blank(tt)
  tt:AddLine(" ")
end

local function Dur(sec)
  return Fmt.Duration(sec or 0)
end

-- "~value (estimate from your /played)": the value white, the note dimmed.
local function Estimated(text)
  return format("%s %s(%s)%s", ns.Tokens.Approx(text), CC_DIM, L.RATE_ESTIMATE, CC_RESET)
end

-- Frozen rate value (no XP for a while): the value, "~" when it is the frozen
-- pre-install estimate, then the frozen mark.
local function Frozen(ctx, text)
  if ctx.rateSrc == "prior" then text = ns.Tokens.Approx(text) end
  return text .. L.STALL_MARK
end

-- Grey note that wraps to the tooltip width (long explanations).
local function WrapNote(tt, text)
  tt:AddLine(text, DR, DG, DB, true)
end

-- Server level cap detected (C2): replaces the XP block. The count of mobs that gave no
-- XP is at least the detection threshold (the in-memory count starts over after a
-- /reload, the persisted cap stays).
local function FillCap(tt, ctx)
  local level = floor(ctx.capLevel or ctx.level)
  local n = ctx.capMisses
  if type(n) ~= "number" or n < C.CAP_MISSES then n = C.CAP_MISSES end
  tt:AddLine(format(L.TT_CAP_FMT, level, floor(n)), PR, PG, PB, true)
  if ctx.valid then
    Pair(tt, L.TT_XP, format("%s / %s", Fmt.Number(ctx.xp), Fmt.Number(ctx.max)))
  end
  WrapNote(tt, L.TT_CAP_RESUME)
end

-- No rate yet: how much counted play (under the current exclusions) is still needed.
local function NoRateText(ctx)
  local left = ctx.warmupLeft or 0
  if left >= 60 then return format(L.TT_NODATA_FMT, Dur(left)) end
  return L.TT_NODATA_XP
end

local function PauseLabel(reason)
  if reason == "inn" then return L.PAUSE_INN end
  if reason == "city" then return L.PAUSE_CITY end
  return L.PAUSE_AFK
end

-- Seconds of one breakdown part (field false = active flight: active minus open
-- world, dungeons, raids and PvP).
local function PartSecs(bd, field)
  if field == false then
    local flight = bd.active - bd.world - bd.dungeon - bd.raid - bd.pvp
    return flight > 0 and flight or 0
  end
  return bd[field] or 0
end

-- Instance seconds (dungeons, raids, PvP) of a bucket under `mask`.
local function InstSecs(bucket, mask)
  if type(bucket) ~= "table" then return 0 end
  return ns.Stats.InstanceTime(bucket, mask)
end

-- Texts of the visible breakdown parts ("World 62%", ...) in the fixed order, over
-- the tracked time; parts that round to 0 % are left out. Fills `out` (reused, the
-- surplus is cleared) and returns the count. Tooltip builds and /tpl played only.
function Tooltip.BreakdownParts(bd, out)
  out = out or {}
  local n = 0
  local tracked = bd and bd.tracked or 0
  if tracked > 0 then
    for i = 1, #BD_ORDER do
      local part = BD_ORDER[i]
      local secs = PartSecs(bd, part[2])
      if floor(secs / tracked * 100 + 0.5) >= 1 then
        n = n + 1
        out[n] = format(L.BD_PART_FMT, L[part[1]], Fmt.Percent(secs / tracked, 0))
      end
    end
  end
  for i = #out, n + 1, -1 do out[i] = nil end
  return n
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

-- XP block (4): level, XP, remaining, rested, next level, XP per hour (+ rate details
-- in the detailed view).
local function FillXP(tt, ctx, char, session, mask, detailed)
  local Stats = ns.Stats
  local level = floor(ctx.level)
  if ctx.valid then
    local Tokens = ns.Tokens
    Pair(tt, format(L.TT_LEVEL_FMT, level, level + 1), Tokens.PercentText(Tokens.PercentTenths(ctx.xp, ctx.max)))
    Pair(tt, L.TT_XP, format("%s / %s", Fmt.Number(ctx.xp), Fmt.Number(ctx.max)))
    Pair(tt, L.TT_REMAINING, Fmt.Number(ctx.max - ctx.xp))
    if ctx.rested > 0 and ctx.max > 0 then
      -- "Rested: 11,600 XP (50%)", like the game's XP bar
      Pair(tt, L.TT_RESTED, format(L.TT_RESTED_FMT, Fmt.Number(ctx.rested), Fmt.Percent(ctx.rested / ctx.max, 0)))
    end
  else
    PairDim(tt, format(L.TT_LEVEL_FMT, level, level + 1), L.DOTS)
  end
  Blank(tt)

  local status = ctx.etaStatus
  local estimate = ctx.rateStatus == "estimate"
  local stalled = ctx.rateStatus == "stalled"
  if status == "warming" then
    PairDim(tt, L.TT_NEXT_LEVEL, format(L.TT_WARMING_FMT, Dur(ctx.warmupLeft)))
  elseif ctx.eta ~= nil then
    if stalled or status == "stalled" then
      PairDim(tt, L.TT_NEXT_LEVEL, Frozen(ctx, Fmt.ETA(ctx.eta)))
    elseif estimate or status == "estimate" then
      Pair(tt, L.TT_NEXT_LEVEL, Estimated(Fmt.ETA(ctx.eta)))
    else
      Pair(tt, L.TT_NEXT_LEVEL, Fmt.ETA(ctx.eta))
    end
    if detailed and ctx.rateSrc == "level" then
      Note(tt, L.TT_SRC_LEVEL)
    elseif detailed and ctx.rateSrc == "recent" then
      Note(tt, L.TT_SRC_RECENT)
    end
  else
    PairDim(tt, L.TT_NEXT_LEVEL, L.TT_NO_RATE)
  end

  -- mobs to kill, from the XP of the last mob killed (rest-aware); until a kill is
  -- known, a dimmed line says when it will show
  if ctx.valid then
    local n, base = Stats.KillsToLevel(char, ctx.xp, ctx.max, ctx.rested)
    if n and base then
      Pair(tt, L.TT_KILLS, format(L.TT_KILLS_FMT, Fmt.Number(n), Fmt.Number(base)))
    else
      PairDim(tt, L.TT_KILLS, L.TT_KILLS_NODATA)
    end
  end

  if ctx.xph == nil then
    PairDim(tt, L.TT_XPH, NoRateText(ctx))
  elseif ctx.rateStatus == "ok" then
    Pair(tt, L.TT_XPH, Fmt.Rate(ctx.xph))
  elseif estimate then
    Pair(tt, L.TT_XPH, Estimated(Fmt.Rate(ctx.xph)))
  elseif stalled then
    -- frozen: idle time without XP is kept out of the rate (C1); since when, and why
    PairDim(tt, L.TT_XPH, Frozen(ctx, Fmt.Rate(ctx.xph)))
    WrapNote(tt, format(L.TT_STALLED_FMT, L.STALL_MARK, Dur(ctx.stallSecs)))
    WrapNote(tt, L.TT_STALLED_RESUME)
  else
    PairDim(tt, L.TT_XPH, Fmt.Rate(ctx.xph))
  end
  if detailed then
    local sessionRate = Stats.SessionRate(session, mask)
    local levelRate = Stats.LevelRate(char, ctx.level, mask)
    if sessionRate or levelRate then
      Note(tt, format(L.TT_RATES_FMT,
        sessionRate and Fmt.Rate(sessionRate) or L.DOTS,
        levelRate and Fmt.Rate(levelRate) or L.DOTS))
    end
  end
  Blank(tt)
end

-- Server /played: live value, else the last saved snapshot with its age (never the
-- local total under this label, critique #21).
local function FillServer(tt, ctx, char)
  if ctx.playedLive then
    Pair(tt, L.TT_SERVER, Dur(ctx.playedServer))
    return
  end
  local srv = char.srv
  if type(srv) == "table" and srv.total then
    if srv.at then
      local age = time() - srv.at
      if age < 0 then age = 0 end
      PairDim(tt, L.TT_SERVER, format(L.TT_SERVER_AGE_FMT, Dur(srv.total), Fmt.Ago(age)))
    else
      PairDim(tt, L.TT_SERVER, Dur(srv.total))
    end
  else
    PairDim(tt, L.TT_SERVER, L.DOTS)
  end
end

-- Detailed part (Shift), inserted before the hint. One blank line opens it; the
-- blocks below are separated by their accent headers only.
local function FillDetails(tt, ctx, char, mask, recent, overall, bd)
  local Stats = ns.Stats
  Blank(tt)
  -- both averages: the short part shows the recent one when it exists, else the
  -- overall one; add the overall one here when it is not visible yet
  if recent then
    if overall then Pair(tt, L.TT_AVG_LEVEL, Dur(overall)) else PairDim(tt, L.TT_AVG_LEVEL, L.DOTS) end
  end

  -- top zones of the current level (names from the character's zone records)
  local levels = char.levels
  local lb = type(levels) == "table" and levels[ctx.level] or nil
  local zones = type(char.zones) == "table" and char.zones or nil
  local _, nz = Stats.TopZones(lb and lb.z, TOP_ROWS, mask, rowsZones)
  if nz > 0 then
    Header(tt, L.TT_TOP_ZONES)
    for i = 1, nz do
      local row = rowsZones[i]
      Pair(tt, Stats.ZoneName(row.key, zones and zones[row.key]), Dur(row.filtered))
    end
  end

  -- continents of the character (instances and unplaced time apart): every continent with
  -- time is listed, valued under the exclusions like the zones above; a continent whose
  -- time is all excluded (e.g. only city time with the city excluded) comes last
  local ncont = 0
  if zones then
    local nraw = Stats.Continents(zones, 0, rowsContRaw) or 0
    if nraw > 0 then
      local rows, nf = rowsContRaw, nraw
      if mask ~= 0 then
        rows = rowsCont
        nf = Stats.Continents(zones, mask, rowsCont) or 0
      end
      Header(tt, L.SECTION_CONTINENTS)
      for i = 1, nf do
        if ncont >= CONT_ROWS then break end
        local row = rows[i]
        Pair(tt, row.name, Dur(row.secs))
        ncont = ncont + 1
      end
      for i = 1, nraw do
        if ncont >= CONT_ROWS then break end
        local raw = rowsContRaw[i]
        local listed = false
        for j = 1, nf do
          if rows[j].key == raw.key then
            listed = true
            break
          end
        end
        if not listed then
          Pair(tt, raw.name, Dur(0))
          ncont = ncont + 1
        end
      end
    end
  end

  -- most played capitals (character scope, request 8)
  local _, nc = Stats.TopCities(zones, TOP_ROWS, rowsCities)
  if nc > 0 then
    Header(tt, L.TT_TOP_CITIES)
    for i = 1, nc do
      local row = rowsCities[i]
      Pair(tt, row.name, format(L.TT_OF_WHICH_AFK_FMT, Dur(row.total), Dur(row.afk)))
    end
  end

  -- last completed levels ("~" = partial, reconstructed or partly estimated)
  local shown = 0
  if type(levels) == "table" then
    local l = floor(ctx.level) - 1
    while l >= 1 and shown < TOP_ROWS do
      local b = levels[l]
      if type(b) == "table" and Stats.SumAll(b) > 0 then
        if shown == 0 then Header(tt, L.TT_LAST_LEVELS) end
        shown = shown + 1
        local text = Dur(Stats.Sum(b, mask))
        if b.partial or b.rec or (b.est or 0) > 0 then text = "~" .. text end
        Pair(tt, format(L.TT_LEVEL_ROW_FMT, l), text)
      end
      l = l - 1
    end
  end

  -- state totals of the character (raw seconds), set apart from the lists above
  if recent or nz > 0 or ncont > 0 or nc > 0 or shown > 0 then Blank(tt) end
  Pair(tt, L.TT_INN, format(L.TT_OF_WHICH_AFK_FMT, Dur(bd.innAll), Dur(bd.innAfk)))
  Pair(tt, L.TT_CITY, format(L.TT_OF_WHICH_AFK_FMT, Dur(bd.cityAll), Dur(bd.cityAfk)))
  -- instance time by kind, with its AFK part (only the kinds played)
  if (bd.dungeonAll or 0) > 0 then
    Pair(tt, L.BD_DUNGEON, format(L.TT_OF_WHICH_AFK_FMT, Dur(bd.dungeonAll), Dur(bd.dungeonAfk)))
  end
  if (bd.raidAll or 0) > 0 then
    Pair(tt, L.BD_RAID, format(L.TT_OF_WHICH_AFK_FMT, Dur(bd.raidAll), Dur(bd.raidAfk)))
  end
  if (bd.pvpAll or 0) > 0 then
    Pair(tt, L.BD_PVP, format(L.TT_OF_WHICH_AFK_FMT, Dur(bd.pvpAll), Dur(bd.pvpAfk)))
  end
  Pair(tt, L.TT_AFK, Dur(bd.afk))
  Pair(tt, L.TT_TAXI, Dur(bd.taxi))
  local life = char.life
  Pair(tt, L.TT_DEATHS, Fmt.Number(type(life) == "table" and life.d or 0))
  if bd.untracked > 0 then
    Pair(tt, L.TT_UNTRACKED, format("%s (%s)", Dur(bd.untracked), L.TT_UNTRACKED_NOTE))
  end
  if bd.est > 0 then
    Pair(tt, L.TT_EST_TOTAL, format("%s (%s)", Dur(bd.est), L.TT_EST_NOTE))
  end

  -- explicit account line (5.19 step 4); singular for one character
  local accFiltered, _, nChars = Stats.Account(ns.db, mask)
  Pair(tt, format(nChars == 1 and L.TT_ACCOUNT_ONE_FMT or L.TT_ACCOUNT_FMT, nChars), Dur(accFiltered))
  -- instance time of every character (same exclusions), when there is any
  local accInst = Stats.AccountInstanceTime(ns.db, mask)
  if accInst > 0 then Pair(tt, L.TT_ACCOUNT_INST, Dur(accInst)) end

  -- network (read only while the detailed tooltip is shown)
  local fps = GetFramerate and GetFramerate() or 0
  local home, world = 0, 0
  if GetNetStats then
    local _, _, h, w = GetNetStats()
    home, world = h or 0, w or 0
  end
  Pair(tt, L.TT_NET, format(L.TT_NET_FMT, Fmt.FPS(fps), Fmt.Latency(home), Fmt.Latency(world)))
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Fills any GameTooltip-like object with AddLine / AddDoubleLine only (works for LDB
-- display tooltips, which are cleared by their owner before OnTooltipShow). `hint`
-- (optional) replaces the last line, for owners whose clicks differ from the bar's.
function Tooltip.Fill(tt, detailed, hint)
  if not tt then return end
  local Tokens, Stats = ns.Tokens, ns.Stats
  local now = GetTime()
  Tokens.UpdateContext(now)
  local ctx = Tokens.ctx
  local mask = ctx.mask
  local excl = Stats.MaskLabel(mask)
  local char = ns.char

  -- 1. title (+ active exclusions)
  if excl then
    tt:AddDoubleLine(L.ADDON_TITLE, format(L.TT_EXCL_FMT, excl), AR, AG, AB, LR, LG, LB)
  else
    tt:AddLine(L.ADDON_TITLE, AR, AG, AB)
  end
  -- 2. pause line, 3. read-only line
  if ctx.paused then tt:AddLine(format(L.TT_PAUSED_FMT, PauseLabel(ctx.pauseReason)), PR, PG, PB) end
  if ns.readOnly then tt:AddLine(L.TT_READONLY, PR, PG, PB) end
  if type(char) ~= "table" or not ctx.hasChar then
    Note(tt, L.NO_DATA)
    return
  end

  local Tracker = ns.Tracker
  local session = Tracker and Tracker.GetSession() or nil
  local sync = Tracker and Tracker.GetSync() or nil
  local life = type(char.life) == "table" and char.life or nil
  local u = life and life.s and life.s.u or 0
  local lifeEst = life and life.est or 0

  -- 4. XP block, or the max-level line (the server level cap lines when detected)
  if ctx.isMax then
    if ctx.isServerCap then
      FillCap(tt, ctx)
    else
      tt:AddLine(L.TT_MAX_LEVEL, VR, VG, VB)
    end
    Blank(tt)
  else
    FillXP(tt, ctx, char, session, mask, detailed)
  end

  -- 5. session and this level (+ estimated part of this level)
  Pair(tt, L.TT_SESSION, Dur(ctx.sessionTime))
  Pair(tt, L.TT_THIS_LEVEL, Dur(ctx.levelTime))
  local levels = char.levels
  local lb = type(levels) == "table" and levels[ctx.level] or nil
  local levelEst = lb and lb.est or 0
  if levelEst > 0 then Note(tt, format(L.TT_EST_FMT, Dur(levelEst))) end

  -- 6. current zone
  local zoneKey = ctx.zoneKey
  local zones = char.zones
  local zoneName = zoneKey ~= nil and Stats.ZoneName(zoneKey, type(zones) == "table" and zones[zoneKey] or nil)
    or L.ZONE_UNKNOWN
  Pair(tt, format(L.TT_ZONE_FMT, zoneName), Dur(ctx.zoneTime))

  -- 7. played (filtered) with its pre-install and rebuilt parts
  Pair(tt, excl and format(L.TT_PLAYED_EXCL_FMT, excl) or L.TT_PLAYED, Dur(ctx.played))
  if excl and u > 0 then Note(tt, format(L.TT_PREINSTALL_FMT, Dur(u))) end
  if lifeEst > 0 then Note(tt, format(L.TT_EST_FMT, Dur(lifeEst))) end
  -- time in instances (dungeons, raids, PvP) under the exclusions, once there is any
  local inst = InstSecs(life, mask)
  if inst > 0 then Pair(tt, L.TT_INSTANCES, Dur(inst)) end

  -- 8. server /played
  FillServer(tt, ctx, char)

  -- 9. average per level: the recent one is preferred (critique #10c)
  local recent, recentN = Stats.RecentAvg(char, mask, RECENT_LEVELS)
  local overall = Stats.AvgPerLevel(char, mask, sync, now)
  if recent then
    Pair(tt, format(L.TT_AVG_RECENT_FMT, recentN), Dur(recent))
  elseif overall then
    Pair(tt, L.TT_AVG_LEVEL, Dur(overall))
    if excl and u > 0 then Note(tt, format(L.TT_PREINSTALL_FMT, Dur(u))) end
  end

  -- 10-11. breakdown over tracked time: the parts that are not 0 %, fixed order,
  -- BD_PER_LINE parts per line (continuation lines have no label)
  Blank(tt)
  local bd = Stats.Breakdown(life, breakdown)
  local nParts = Tooltip.BreakdownParts(bd, bdParts)
  if nParts == 0 then
    PairDim(tt, L.TT_BREAKDOWN, L.TT_NO_RATE)
  else
    local left = L.TT_BREAKDOWN
    for first = 1, nParts, BD_PER_LINE do
      local last = first + BD_PER_LINE - 1
      if last > nParts then last = nParts end
      Pair(tt, left, table_concat(bdParts, L.SEP, first, last))
      left = " "
    end
  end

  if detailed then FillDetails(tt, ctx, char, mask, recent, overall, bd) end

  -- 12. hint
  Note(tt, hint or L.TT_HINT)
end

-- Tooltip anchor (7.6): below the owner when it sits in the upper half of the screen.
local function IsUpperHalf(owner)
  if not owner.GetCenter then return false end
  local _, cy = owner:GetCenter()
  if not cy then return false end
  local scale = owner.GetEffectiveScale and owner:GetEffectiveScale() or 1
  local parent = UIParent
  local height = parent and parent.GetHeight and parent:GetHeight() or 768
  local parentScale = parent and parent.GetEffectiveScale and parent:GetEffectiveScale() or 1
  return cy * scale > height * parentScale / 2
end

local function StillOurs()
  local tt = GameTooltip
  return shownFor ~= nil and tt ~= nil and tt:IsShown() and tt:GetOwner() == shownFor
end

local function Detach()
  shownFor = nil
  shownHint = nil
  ns.UnregisterMessage("TICK", Tooltip)
  ns.UnregisterEvent("MODIFIER_STATE_CHANGED", Tooltip)
end

local function Redraw()
  local tt = GameTooltip
  if tt.ClearLines then tt:ClearLines() end
  Tooltip.Fill(tt, IsShiftKeyDown ~= nil and IsShiftKeyDown() and true or false, shownHint)
  tt:Show()
end

-- TICK and MODIFIER_STATE_CHANGED while shown: redraw, or detach when the tooltip was
-- hidden or taken by another owner.
local function OnRefresh()
  if not StillOurs() then
    Detach()
    return
  end
  Redraw()
end

-- `hint` (optional): last line to show instead of L.TT_HINT (addon compartment).
function Tooltip.ShowFor(owner, hint)
  local tt = GameTooltip
  if owner == nil or tt == nil then return end
  tt:SetOwner(owner, "ANCHOR_NONE")
  if tt.ClearAllPoints then tt:ClearAllPoints() end
  if tt.SetPoint then
    if IsUpperHalf(owner) then
      tt:SetPoint("TOP", owner, "BOTTOM", 0, -4)
    else
      tt:SetPoint("BOTTOM", owner, "TOP", 0, 4)
    end
  end
  shownFor = owner
  shownHint = hint
  Redraw()
  ns.RegisterMessage("TICK", Tooltip, OnRefresh)
  ns.RegisterEvent("MODIFIER_STATE_CHANGED", Tooltip, OnRefresh)
end

function Tooltip.Hide(owner)
  if shownFor == nil then return end
  if owner ~= nil and owner ~= shownFor then return end
  local tt = GameTooltip
  if tt ~= nil and tt:GetOwner() == shownFor then tt:Hide() end
  Detach()
end

function Tooltip.IsShownFor(owner)
  return owner ~= nil and owner == shownFor and StillOurs()
end
