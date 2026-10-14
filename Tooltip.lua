-- Tooltip.lua - short and detailed tooltips (SPEC-FINAL 3.12, 7.6; SPEC-themes 4).
--
-- Content is built only while a tooltip is shown. While our tooltip is shown the
-- module listens to TICK and MODIFIER_STATE_CHANGED (Shift switches to the detailed
-- view); both are unregistered as soon as it is hidden or taken by another owner.
-- Fill() reads only the current character (ns.char + the Tracker sync). Refreshes allocate strings only: row tables
-- are reused. Two sections, each under its own title: the short view is the level in
-- progress alone (XP block, session, time at this level, time in the current zone at
-- this level, the level's breakdown); the detailed view (Shift) adds the whole character
-- (played time, instances, time in the current zone, server /played, recent average,
-- the character's breakdown, then its zones, continents, capitals and state totals).
-- ShowFor shows them as two tooltips (see "The pair" below): block 1, the level, on
-- hover; block 2, the character, beside it while Shift is held, their breakdown rows face
-- to face (stacked under it when the two do not fit the screen's width). Broker's
-- tooltip stays one tooltip, the character section below the level's. The rate
-- details (source of the estimate, session / level rates) belong to the detailed view
-- (in the level's section).
-- A rate estimated from the pre-install /played (status "estimate") is shown as
-- "~value" followed by the dimmed L.RATE_ESTIMATE; without any data the XP per hour
-- line says how much counted play is still needed, never a bare "...".
-- A breakdown line lists the parts of the tracked time (world, dungeons, raids, PvP,
-- flight, professions, dead, AFK, inn, city) largest first, gauge segments and legend
-- alike, leaving out the parts that round to 0 %, BD_PER_LINE parts per line: the
-- level's in its section (L.TT_BREAKDOWN_LEVEL), the character's in the detailed one
-- (L.TT_BREAKDOWN_TOTAL), in every tooltip (Broker's too). Instance time (dungeons,
-- raids, PvP) also has its own lines in the character section: the filtered total, then
-- each kind with its AFK part. The averages per level, the level history and the
-- account figures are in the statistics window.
-- Time rebuilt after a crash (Stats.EstTime) is noted under the time it is part of, under
-- the same exclusions; a breakdown mostly rebuilt (more than C.EST_MOST) gets a note
-- under it, since its split is then an estimate.
-- A frozen rate (status "stalled": no XP gained for a while) is shown dimmed with
-- L.STALL_MARK, and a note says for how much counted play no XP came. A detected server
-- level cap replaces the XP block with the cap line and says tracking resumes by itself.
--
-- Themes (SPEC-themes 4): the colours come from a palette (role -> rgba), the classic
-- one (Themes.CLASSIC_TT) unless the caller passes another. ShowFor picks the targets:
-- the shared GameTooltip (block 1) and the addon's own second GameTooltip (block 2) for a
-- native theme (Classic: the lines and colours of before themes, but each breakdown's
-- label alone on its line, with a breakdown bar beside it: PlaceBars), else the two
-- private frames of TooltipFrame.lua, whose TP_Row / TP_Sep / TP_Gauge extensions receive
-- each row with its kind. Any THEME_CHANGED hides the tooltip.
--
-- The reputation's detailed tooltip (ShowFor(owner, nil, "rep"): Bar.lua's hover region
-- over the strip, or over the main track while it shows the reputation): one block,
-- Tooltip.FillRep (the faction, its 8 standings, its rate and the time to the next
-- standing); Shift does nothing there.
-- The PvP detailed tooltip (ShowFor(owner, nil, "pvp"): Bar.lua's hover region over the
-- PvP strip, or over the main track while it shows PvP): one block too, Tooltip.FillPvp
-- (the honor, the rank and this week's cap, the honorable kills, this session's
-- battlegrounds; Pvp.lua's numbers). The PvP rank titles are the game's
-- (Tooltip.PvpRankTitle).
local ADDON, ns = ...
local L, C, Fmt = ns.L, ns.C, ns.Fmt

local type, time, rawget = type, time, rawget
local format, floor = string.format, math.floor
local table_concat = table.concat
local GetTime, IsShiftKeyDown = GetTime, IsShiftKeyDown
local GetFramerate, GetNetStats = GetFramerate, GetNetStats

local Tooltip = {}
ns.Tooltip = Tooltip

local CC_DIM, CC_RESET = C.CC.dim, C.CC.reset
local RECENT_LEVELS = C.RECENT_LEVELS
local TOP_ROWS = 3
local CONT_ROWS = 5
local BD_PER_LINE = 5           -- breakdown parts per tooltip line
local BD_PER_LINE_ACT = 4       -- at most, once a professions or dead part shows (lot 8):
                                -- lines balanced, so that the longer labels still fit

local shownFor = nil            -- owner of our tooltip while it is shown
local shownAt = nil             -- the frame it hangs off (ShowFor's anchor; else its owner)
local shownHint = nil           -- hint line of the shown tooltip (nil = L.TT_HINT)
local shownTT = nil             -- target showing it (block 1): GameTooltip or TooltipFrame frame 1
local shownPal = nil            -- palette of the shown tooltip
local shownKind = nil           -- nil: the general tooltip; "rep": the reputation's (FillRep);
                                -- "pvp": the PvP one (FillPvp)
local rowsZones, rowsCities, rowsCont, rowsContRaw = {}, {}, {}, {}   -- reused Stats row tables
local breakdown = {}            -- reused Stats.Breakdown output (the character)
local levelBreakdown = {}       -- reused Stats.Breakdown output (the level in progress)
local bdParts = {}              -- reused breakdown part texts (tooltip build only)
local bdFracs, bdKeys = {}, {}  -- reused breakdown fractions and gauge keys

-- Breakdown parts (shown largest first, ties in this order): locale key of the label,
-- Stats.Breakdown field, gauge colour key. The flight part (active flight, "t") has no field of its own: active
-- minus the rest. Professions and dead (Activity.lua) are not part of active.
local BD_ORDER = {
  { "BD_WORLD", "world", "world" }, { "BD_DUNGEON", "dungeon", "dungeon" }, { "BD_RAID", "raid", "raid" },
  { "BD_PVP", "pvp", "pvp" }, { "BD_TAXI", false, "taxi" }, { "BD_PROF", "prof", "prof" },
  { "BD_DEAD", "dead", "dead" }, { "BD_AFK", "afk", "afk" }, { "BD_INN", "inn", "inn" },
  { "BD_CITY", "city", "city" },
}

-- Classic palette: Themes.CLASSIC_TT. The local copy (same roles, from C.COLORS) is
-- only used if Themes did not load.
local FALLBACK_TT
local function Classic()
  local Themes = ns.Themes
  local pal = Themes and Themes.CLASSIC_TT
  if pal then return pal end
  if not FALLBACK_TT then
    local K = C.COLORS
    FALLBACK_TT = { title = K.accent, mode = K.label, label = K.label, value = K.value, dim = K.dim,
                    header = K.accent, pause = K.pause, hint = K.dim, levelLabel = K.label,
                    levelValue = K.value, levelValueRested = K.value, rested = K.value, ccDim = C.CC.dim }
  end
  return FALLBACK_TT
end

-- Palette and kind of target of the Fill in progress: set at the start of each Fill and
-- cleared at its end, so that no palette of a previous theme stays referenced (P5).
local P = nil
local isTP = false              -- the target has the TP_Row / TP_Sep / TP_Gauge extensions

---------------------------------------------------------------------------
-- Line helpers (the colours are palette roles). On a TP target each row carries its
-- kind (SPEC-themes 4.4); on a GameTooltip the calls are the pre-theme ones.
---------------------------------------------------------------------------

local function Line(tt, kind, text, c, wrap)
  if isTP then
    tt:TP_Row(kind, text, nil, c, nil, wrap)
  else
    tt:AddLine(text, c[1], c[2], c[3], wrap)
  end
end

local function Double(tt, kind, left, right, lc, rc)
  if isTP then
    tt:TP_Row(kind, left, right, lc, rc)
  else
    tt:AddDoubleLine(left, right, lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
  end
end

local function Pair(tt, left, right)
  Double(tt, "pair", left, right, P.label, P.value)
end

local function PairDim(tt, left, right)
  Double(tt, "pair", left, right, P.label, P.dim)
end

local function Note(tt, text)
  Line(tt, "note", text, P.dim)
end

local function Header(tt, text)
  Line(tt, "header", text, P.header)
end

-- Title of a section of the tooltip (the level in progress, the whole character): the
-- title font of the theme, in the header colour.
local function Section(tt, text)
  Line(tt, "section", text, P.header)
end

-- Separator: on a GameTooltip a "block" separator is the blank line of before themes,
-- the others add nothing.
local function Sep(tt, kind)
  if isTP then
    tt:TP_Sep(kind)
  elseif kind == "block" then
    tt:AddLine(" ")
  end
end

-- Breakdown continuation row (no label).
local function Cont(tt, text)
  Double(tt, "cont", " ", text, P.label, P.value)
end

local function Dur(sec)
  return Fmt.Duration(sec or 0)
end

-- "~value (estimate from your /played)": the value white, the note dimmed.
local function Estimated(text)
  return format("%s %s(%s)%s", ns.Tokens.Approx(text), P.ccDim or CC_DIM, L.RATE_ESTIMATE, CC_RESET)
end

-- Frozen rate value (no XP for a while): the value, "~" when it is the frozen
-- pre-install estimate, then the frozen mark.
local function Frozen(ctx, text)
  if ctx.rateSrc == "prior" then text = ns.Tokens.Approx(text) end
  return text .. L.STALL_MARK
end

-- Grey note that wraps to the tooltip width (long explanations).
local function WrapNote(tt, text)
  Line(tt, "wrap", text, P.dim, true)
end

-- Server level cap detected (C2): replaces the XP block. The count of mobs that gave no
-- XP is at least the detection threshold (the in-memory count starts over after a
-- /reload, the persisted cap stays).
local function FillCap(tt, ctx)
  local level = floor(ctx.capLevel or ctx.level)
  local n = ctx.capMisses
  if type(n) ~= "number" or n < C.CAP_MISSES then n = C.CAP_MISSES end
  Line(tt, "alert", format(L.TT_CAP_FMT, level, floor(n)), P.pause, true)
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

-- Visible breakdown parts, largest first (ties: the BD_ORDER order): fills the reused
-- bdIdx (BD_ORDER indices) and bdSecs (their seconds) and returns their count. A part that
-- rounds to 0 % of the tracked time is left out. Allocation free (insertion sort).
local bdIdx, bdSecs = {}, {}
local function SortedParts(bd)
  local n = 0
  local tracked = bd and bd.tracked or 0
  if tracked > 0 then
    for i = 1, #BD_ORDER do
      local secs = PartSecs(bd, BD_ORDER[i][2])
      if floor(secs / tracked * 100 + 0.5) >= 1 then
        local p = n + 1
        while p > 1 and bdSecs[p - 1] < secs do
          bdIdx[p], bdSecs[p] = bdIdx[p - 1], bdSecs[p - 1]
          p = p - 1
        end
        bdIdx[p], bdSecs[p] = i, secs
        n = n + 1
      end
    end
  end
  return n, tracked
end

-- Texts of the visible breakdown parts ("World 62%", ...), largest first, over the
-- tracked time; parts that round to 0 % are left out. Fills `out` (reused, the surplus is
-- cleared) and returns the count, and true when a professions or dead part is among
-- them. Tooltip builds and /tpl played only.
function Tooltip.BreakdownParts(bd, out)
  out = out or {}
  local n, tracked = SortedParts(bd)
  local act = false
  for k = 1, n do
    local part = BD_ORDER[bdIdx[k]]
    out[k] = format(L.BD_PART_FMT, L[part[1]], Fmt.Percent(bdSecs[k] / tracked, 0))
    if part[2] == "prof" or part[2] == "dead" then act = true end
  end
  for i = #out, n + 1, -1 do out[i] = nil end
  return n, act
end

-- Fractions of the same visible parts (same order, largest first, same 0 % filter as
-- BreakdownParts) and their gauge colour keys (world, dungeon, raid, pvp, taxi, prof, dead,
-- afk, inn, city). Fills the reused `fracs` and `keys` (the surplus is cleared) and
-- returns the count. Allocation free.
function Tooltip.BreakdownFracs(bd, fracs, keys)
  local n, tracked = SortedParts(bd)
  for k = 1, n do
    fracs[k] = bdSecs[k] / tracked
    keys[k] = BD_ORDER[bdIdx[k]][3]
  end
  for i = #fracs, n + 1, -1 do fracs[i] = nil end
  for i = #keys, n + 1, -1 do keys[i] = nil end
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
    -- first row: the level roles of the palette (the value takes the rested role while rested)
    Double(tt, "pair", format(L.TT_LEVEL_FMT, level, level + 1),
      Tokens.PercentText(Tokens.PercentTenths(ctx.xp, ctx.max)),
      P.levelLabel, ctx.rested > 0 and P.levelValueRested or P.levelValue)
    Pair(tt, L.TT_XP, format("%s / %s", Fmt.Number(ctx.xp), Fmt.Number(ctx.max)))
    Pair(tt, L.TT_REMAINING, Fmt.Number(ctx.max - ctx.xp))
    if ctx.rested > 0 and ctx.max > 0 then
      -- "Rested: 11,600 XP (50%)", like the game's XP bar
      Double(tt, "pair", L.TT_RESTED,
        format(L.TT_RESTED_FMT, Fmt.Number(ctx.rested), Fmt.Percent(ctx.rested / ctx.max, 0)), P.label, P.rested)
    end
  else
    PairDim(tt, format(L.TT_LEVEL_FMT, level, level + 1), L.DOTS)
  end
  Sep(tt, "block")

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

  -- mobs to kill, from the average XP of the last C.KILL_RING mobs killed (rest-aware),
  -- with the last one's XP; until a kill is known, a dimmed line says when it will show
  if ctx.valid then
    local n, avg, last = Stats.KillsToLevel(char, ctx.xp, ctx.max, ctx.rested)
    if n and avg then
      Pair(tt, L.TT_KILLS, format(L.TT_KILLS_FMT, Fmt.Number(n), Fmt.Number(avg), Fmt.Number(last or avg)))
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
  Sep(tt, "block")
end

-- The followed reputation (Reputation.lua), while the bar shows it (its strip, or the main
-- track): one row after the XP block, the faction's name as its label (cut with "..." by
-- a themed tooltip when the row would be wider than the theme allows: the value is never
-- cut) and its standing with the points inside it ("Friendly · 1,234 / 6,000 (20.6%)"),
-- the standing alone at Exalted. The standing's name is the game's
-- (FACTION_STANDING_LABEL<n>, the _FEMALE form for a female character), else the addon's
-- own (REP_STANDING_<n>). Key strings built once: no allocation per call.
local STANDING_KEYS, FEMALE_KEYS, OWN_KEYS = {}, {}, {}
for r = 1, 8 do
  STANDING_KEYS[r] = "FACTION_STANDING_LABEL" .. r
  FEMALE_KEYS[r] = "FACTION_STANDING_LABEL" .. r .. "_FEMALE"
  OWN_KEYS[r] = "REP_STANDING_" .. r
end

local function StandingName(reaction)
  local key = STANDING_KEYS[reaction]
  if key == nil then return L.DOTS end
  local IsSecret = ns.Util.IsSecret
  local s
  if type(UnitSex) == "function" then
    local sex = UnitSex("player")
    if not IsSecret(sex) and sex == 3 then s = rawget(_G, FEMALE_KEYS[reaction]) end
  end
  if type(s) ~= "string" or IsSecret(s) or s == "" then s = rawget(_G, key) end
  if type(s) ~= "string" or IsSecret(s) or s == "" then s = L[OWN_KEYS[reaction]] end
  return s
end
Tooltip.StandingName = StandingName

-- PvP rank titles (WoW Forever): the game's PVP_RANK_<e>_<0 Horde | 1 Alliance>, e the
-- Enum.PvPRanks value (5 + rank - 1: rank 1 is 5, rank 14 is 18), the _FEMALE form for a
-- female character when the client has one. nil without a rank or when the client has
-- none (the caller says "Unranked" / "Rank N"). Key strings built once.
local RANK_KEYS = { [0] = {}, [1] = {} }
for f = 0, 1 do
  for e = 5, 18 do
    RANK_KEYS[f][e] = "PVP_RANK_" .. e .. "_" .. f
    RANK_KEYS[f][-e] = "PVP_RANK_" .. e .. "_" .. f .. "_FEMALE"
  end
end

-- Title of PvPRanks value e (5..18), or nil.
local function RankTitleOf(e)
  local IsSecret = ns.Util.IsSecret
  local s
  if type(e) == "number" and e >= 5 and e <= 18 then
    local f = 0
    if type(UnitFactionGroup) == "function" then
      local ok, fac = pcall(UnitFactionGroup, "player")
      if ok and not IsSecret(fac) and fac == "Alliance" then f = 1 end
    end
    local keys = RANK_KEYS[f]
    if type(UnitSex) == "function" then
      local sex = UnitSex("player")
      if not IsSecret(sex) and sex == 3 then s = rawget(_G, keys[-e]) end
    end
    if type(s) ~= "string" or IsSecret(s) or s == "" then s = rawget(_G, keys[e]) end
  end
  if type(s) ~= "string" or IsSecret(s) or s == "" then return nil end
  return s
end

-- The title of PvP rank r (1..14), or nil.
function Tooltip.PvpRankTitle(r)
  if type(r) ~= "number" or r < 1 or r > 14 then return nil end
  return RankTitleOf(r + 4)
end

-- The title of PvPRanks value e (the highest lifetime rank), or nil.
function Tooltip.PvpEnumTitle(e)
  return RankTitleOf(e)
end

local function FillRepRow(tt)
  local Rep = ns.Rep
  if not (Rep and Rep.Shown()) then return end
  local name, reaction, value, span, full = Rep.Get()
  if name == nil then return end
  local standing = StandingName(reaction)
  if full then
    Pair(tt, name, standing)
  else
    local Tokens = ns.Tokens
    Pair(tt, name, format(L.TT_REP_FMT, standing, Fmt.Number(value), Fmt.Number(span),
      Tokens.PercentText(Tokens.PercentTenths(value, span))))
  end
  Sep(tt, "block")
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

-- Breakdown row of the Fill in progress: the line number of its gauge row or labelled row
-- (the first breakdown of the fill), 0 while there is none; Fill returns it. ShowFor lines
-- up the breakdown rows of its two blocks (see "The pair" below).
local fillRow = 0
-- Bar of the Fill in progress (a native block of ShowFor: TooltipFrame.Bar), until its
-- first breakdown takes it; nil otherwise (Broker, /tpl, the private frames).
local fillBar = nil

local function MarkRow(tt)
  if fillRow == 0 and tt.NumLines then fillRow = tt:NumLines() end
end

-- Breakdown of `bucket` (state seconds: the level in progress or the whole character)
-- over its tracked time, into the reused `out`, under `label` (L.TT_BREAKDOWN_LEVEL or
-- L.TT_BREAKDOWN_TOTAL): the parts that are not 0 %, largest first, BD_PER_LINE parts
-- per line (continuation lines have no label). On a TP target the label has a row of its
-- own: a gauge row when the theme has a gauge, else the label alone (it is too long to
-- share a row with the parts in every language). On a GameTooltip given a bar (fillBar:
-- the native blocks of ShowFor) the label has its line too, its right text a space (the
-- bar's right edge), and the parts go into the bar (Tooltip.lua draws it to the label's
-- right: PlaceBars); any other GameTooltip's first line carries the label and the first
-- parts (Broker). Without any part (no tracked time) a dimmed line, which is not a
-- breakdown row (MarkRow). Returns the Stats.Breakdown output.
local function FillBreakdown(tt, bucket, out, label)
  local bd = ns.Stats.Breakdown(bucket, out)
  local nParts, act = Tooltip.BreakdownParts(bd, bdParts)
  local perLine = BD_PER_LINE
  if act then   -- longer labels: at most BD_PER_LINE_ACT parts a line, lines balanced
    local nLines = floor((nParts + BD_PER_LINE_ACT - 1) / BD_PER_LINE_ACT)
    perLine = floor((nParts + nLines - 1) / nLines)
  end
  if nParts == 0 then
    PairDim(tt, label, L.TT_NO_RATE)
    return bd
  end
  -- every text row is a continuation row once the label has its own row
  local labelled = true
  if isTP then
    if not (Tooltip.BreakdownFracs(bd, bdFracs, bdKeys) > 0 and tt:TP_Gauge(label, bdFracs, bdKeys, nParts)) then
      Line(tt, "line", label, P.label)
    end
    labelled = false
    MarkRow(tt)
  elseif fillBar ~= nil then
    local bar = fillBar
    fillBar = nil                               -- one bar a fill: its first breakdown's
    bar.n = Tooltip.BreakdownFracs(bd, bar.fr, bar.key)
    Double(tt, "pair", label, " ", P.label, P.value)
    labelled = false
    MarkRow(tt)
  end
  for first = 1, nParts, perLine do
    local last = first + perLine - 1
    if last > nParts then last = nParts end
    if labelled then
      Pair(tt, label, table_concat(bdParts, L.SEP, first, last))
      labelled = false
      MarkRow(tt)
    else
      Cont(tt, table_concat(bdParts, L.SEP, first, last))
    end
  end
  return bd
end

-- Under a breakdown (bd, from FillBreakdown): a note when more than C.EST_MOST of its
-- tracked time was rebuilt after a crash (`gross`: Stats.EstTime, every key, as the
-- breakdown has no exclusions), i.e. its split is mostly an estimate. Wraps.
local function FillEstMost(tt, bd, gross)
  local tracked = bd.tracked or 0
  if gross <= 0 or tracked <= 0 then return end
  local share = gross / tracked
  if share <= C.EST_MOST then return end
  if share > 1 then share = 1 end
  WrapNote(tt, format(L.TT_EST_MOST_FMT, Fmt.Percent(share, 0)))
end

-- Total (unfiltered) seconds of a continent row key, from the raw rows of this build.
local function ContRawSecs(key, nraw)
  for i = 1, nraw do
    local r = rowsContRaw[i]
    if r.key == key then return r.secs end
  end
  return 0
end

-- Detailed part (Shift), inserted before the hint. One blank line opens it; the
-- blocks below are separated by their accent headers only. The averages per level, the
-- level history and the account figures belong to the statistics window (lot 8).
local function FillDetails(tt, char, mask, bd)
  local Stats = ns.Stats
  Sep(tt, "block")

  -- top zones of the character under the exclusions (names from its zone records); a
  -- zone whose time is all excluded is not listed
  local zones = type(char.zones) == "table" and char.zones or nil
  local _, nz = Stats.TopZones(zones, TOP_ROWS, mask, rowsZones)
  local shown = 0
  for i = 1, nz do
    local row = rowsZones[i]
    if (row.filtered or 0) > 0 then
      if shown == 0 then Header(tt, L.TT_TOP_ZONES) end
      shown = shown + 1
      Pair(tt, Stats.ZoneName(row.key, zones and zones[row.key]), Dur(row.filtered))
    end
  end

  -- continents of the character (dungeons, raids and PvP apart, unplaced time left out):
  -- every continent with time is listed, valued under the exclusions like the zones
  -- above; a continent whose time is all excluded (e.g. only city time with the city
  -- excluded) comes last. A
  -- continent with less than C.CONT_MIN_SECS of total time (a few seconds of loading
  -- screen) is not listed.
  local ncont = 0
  if zones then
    local nraw = Stats.Continents(zones, 0, rowsContRaw) or 0
    local nbig = 0
    for i = 1, nraw do
      if rowsContRaw[i].secs >= C.CONT_MIN_SECS then nbig = nbig + 1 end
    end
    if nbig > 0 then
      local rows, nf = rowsContRaw, nraw
      if mask ~= 0 then
        rows = rowsCont
        nf = Stats.Continents(zones, mask, rowsCont) or 0
      end
      Header(tt, L.SECTION_CONTINENTS)
      for i = 1, nf do
        if ncont >= CONT_ROWS then break end
        local row = rows[i]
        if ContRawSecs(row.key, nraw) >= C.CONT_MIN_SECS then
          Pair(tt, row.name, Dur(row.secs))
          ncont = ncont + 1
        end
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
        if not listed and raw.secs >= C.CONT_MIN_SECS then
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

  -- state totals of the character (raw seconds), set apart from the lists above
  if shown > 0 or ncont > 0 or nc > 0 then Sep(tt, "block") end
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
  -- professions (only once there is any), deaths with the time spent dead or a ghost
  if (bd.prof or 0) > 0 then Pair(tt, L.TT_PROF, Dur(bd.prof)) end
  local life = char.life
  local deaths = Fmt.Number(type(life) == "table" and life.d or 0)
  if (bd.dead or 0) > 0 then deaths = format("%s (%s)", deaths, Dur(bd.dead)) end
  Pair(tt, L.TT_DEATHS, deaths)
  if bd.untracked > 0 then
    Pair(tt, L.TT_UNTRACKED, format("%s (%s)", Dur(bd.untracked), L.TT_UNTRACKED_NOTE))
  end

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

-- The lines of Tooltip.Fill (P and isTP are set, the token context is up to date).
-- `part`: 0 = the whole tooltip in one (Broker, /tpl, the offline tools), 1 = block 1 of
-- the pair (the title and the level in progress; the hint too unless block 2 follows,
-- i.e. unless `detailed`), 2 = block 2 (the whole character, then the hint). Returns
-- false when there is no character data: no character section (no block 2) then.
local function FillBody(tt, detailed, hint, part)
  local Stats = ns.Stats
  local ctx = ns.Tokens.ctx
  local mask = ctx.mask
  local excl = Stats.MaskLabel(mask)
  local char = ns.char

  if part ~= 2 then
    -- 1. title (+ active exclusions)
    if excl then
      Double(tt, "title", L.ADDON_TITLE, format(L.TT_EXCL_FMT, excl), P.title, P.mode)
    else
      Line(tt, "title", L.ADDON_TITLE, P.title)
    end
    -- 2. pause line, 3. read-only line
    if ctx.paused then Line(tt, "alert", format(L.TT_PAUSED_FMT, PauseLabel(ctx.pauseReason)), P.pause) end
    if ns.readOnly then Line(tt, "alert", L.TT_READONLY, P.pause) end
    Sep(tt, "header")
  end
  if type(char) ~= "table" or not ctx.hasChar then
    if part ~= 2 then Note(tt, L.NO_DATA) end
    return false
  end

  local zoneKey = ctx.zoneKey
  local zones = char.zones
  local zoneName = zoneKey ~= nil and Stats.ZoneName(zoneKey, type(zones) == "table" and zones[zoneKey] or nil)
    or L.ZONE_UNKNOWN

  -- 4. the level in progress: its title, the XP block or the max-level line (the server
  -- level cap lines when detected), the watched reputation (while the bar shows its
  -- strip), the session, this level (+ its estimated part), the
  -- time in the current zone at this level and the level's breakdown (+ a note when it
  -- is mostly rebuilt)
  if part ~= 2 then
    local Tracker = ns.Tracker
    local session = Tracker and Tracker.GetSession() or nil
    Section(tt, L.TT_SECTION_LEVEL)
    if ctx.isMax then
      if ctx.isServerCap then
        FillCap(tt, ctx)
      else
        Line(tt, "line", L.TT_MAX_LEVEL, P.value)
      end
      Sep(tt, "block")
    else
      FillXP(tt, ctx, char, session, mask, detailed)
    end
    FillRepRow(tt)
    Pair(tt, L.TT_SESSION, Dur(ctx.sessionTime))
    Pair(tt, L.TT_THIS_LEVEL, Dur(ctx.levelTime))
    local levels = char.levels
    local lb = type(levels) == "table" and levels[ctx.level] or nil
    -- rebuilt after a crash, under the exclusions (never above the line it is noted under)
    -- and gross (the share of the breakdown, FillEstMost)
    local levelEst, levelGross = Stats.EstTime(lb, mask)
    if levelEst > ctx.levelTime then levelEst = ctx.levelTime end
    if levelEst > 0 then Note(tt, format(L.TT_EST_FMT, Dur(levelEst))) end
    -- the zone's tracked time at this level, never above "This level" (the server's level
    -- time once synced, which may be a little behind)
    local lz = lb and zoneKey ~= nil and type(lb.z) == "table" and lb.z[zoneKey] or nil
    local zoneLevel = Stats.Sum(lz, mask)
    if zoneLevel > ctx.levelTime then zoneLevel = ctx.levelTime end
    Pair(tt, format(L.TT_ZONE_FMT, zoneName), Dur(zoneLevel))
    Sep(tt, "block")
    FillEstMost(tt, FillBreakdown(tt, lb, levelBreakdown, L.TT_BREAKDOWN_LEVEL), levelGross)
  end

  -- 5. the whole character (Shift): its title, played (filtered) with its pre-install
  -- and rebuilt parts, time in instances under the exclusions, its whole time in the
  -- current zone, the server /played, the average of the last levels (the overall
  -- average per level is in the statistics window), the character's breakdown (+ a note
  -- when it is mostly rebuilt), then its details. Block 2 of the pair, or below the level
  -- in a tooltip of both (part 0).
  if detailed and part ~= 1 then
    if part == 0 then Sep(tt, "block") end
    local life = type(char.life) == "table" and char.life or nil
    local u = life and life.s and life.s.u or 0
    local lifeEst, lifeGross = Stats.EstTime(life, mask)
    if lifeEst > ctx.played then lifeEst = ctx.played end
    Section(tt, L.TT_SECTION_CHAR)
    Pair(tt, excl and format(L.TT_PLAYED_EXCL_FMT, excl) or L.TT_PLAYED, Dur(ctx.played))
    if excl and u > 0 then Note(tt, format(L.TT_PREINSTALL_FMT, Dur(u))) end
    if lifeEst > 0 then Note(tt, format(L.TT_EST_FMT, Dur(lifeEst))) end
    local inst = InstSecs(life, mask)
    if inst > 0 then Pair(tt, L.TT_INSTANCES, Dur(inst)) end
    Pair(tt, format(L.TT_ZONE_FMT, zoneName), Dur(ctx.zoneTime))
    FillServer(tt, ctx, char)
    local recent, recentN = Stats.RecentAvg(char, mask, RECENT_LEVELS)
    if recent then Pair(tt, format(L.TT_AVG_RECENT_FMT, recentN), Dur(recent)) end
    Sep(tt, "block")
    local bd = FillBreakdown(tt, life, breakdown, L.TT_BREAKDOWN_TOTAL)
    FillEstMost(tt, bd, lifeGross)
    FillDetails(tt, char, mask, bd)
  end

  -- 6. hint, at the bottom of the last block
  if part ~= 1 or not detailed then
    Sep(tt, "footer")
    Line(tt, "hint", hint or L.TT_HINT, P.hint)
  end
  return true
end

-- Fills any GameTooltip-like object with AddLine / AddDoubleLine only (works for LDB
-- display tooltips, which are cleared by their owner before OnTooltipShow), or a
-- TooltipFrame frame through its TP_* extensions. `hint` (optional) replaces the last
-- line, for owners whose clicks differ from the bar's. `pal` (optional): the palette,
-- Themes.CLASSIC_TT by default (Broker passes none: its tooltips stay classic). `part`
-- (optional, FillBody): nil or 0 = the whole tooltip in one (Broker), 1 and 2 = the two
-- blocks of ShowFor's pair, block 2 right after block 1 (it reuses the token context
-- block 1 updated). `bar` (optional, ShowFor's native blocks: TooltipFrame.Bar): the
-- fill's first breakdown on a GameTooltip puts its label alone on its line and its parts
-- into the bar (FillBreakdown). Returns false when there is no character data (no block
-- 2), then the line number of the fill's first breakdown row (0: none; see MarkRow).
function Tooltip.Fill(tt, detailed, hint, pal, part, bar)
  if not tt then return false end
  P = pal or Classic()
  isTP = rawget(tt, "TP_Row") ~= nil       -- rawget: a frame's method table may answer anything
  if part ~= 2 then ns.Tokens.UpdateContext(GetTime()) end
  fillRow = 0
  fillBar = bar
  local more = FillBody(tt, detailed, hint, part or 0)
  P, isTP, fillBar = nil, false, nil
  return more, fillRow
end

---------------------------------------------------------------------------
-- The reputation's detailed tooltip
---------------------------------------------------------------------------

-- The faction: its name, its standing with the points inside it (its colour), the points
-- to the next standing; a note when the faction chosen in the options cannot be read (the
-- game's watched one is shown instead).
local function FillRepFaction(tt, Rep, name, react, value, span, full)
  local Tokens = ns.Tokens
  Header(tt, name)
  local c = Rep.ColorArray(react)
  local standing = StandingName(react)
  if full then
    Line(tt, "line", standing, c)
  else
    Line(tt, "line", format(L.TT_REP_FMT, standing, Fmt.Number(value), Fmt.Number(span),
      Tokens.PercentText(Tokens.PercentTenths(value, span))), c)
    Line(tt, "line", format(L.TT_REP_TO_NEXT_FMT, Fmt.Number(span - value), StandingName(react + 1)), P.value)
  end
  local _, _, _, _, _, _, fallback = Rep.Detail()
  if fallback then Line(tt, "wrap", L.TT_REP_FALLBACK, P.pause, true) end
end

-- The 8 standings: reached ones dimmed and marked, the current one in its colour with its
-- percent (the top at Exalted), the next ones with the points still needed and, with a
-- rate ("ok" or frozen), the estimated time (L.DOTS when the thresholds are not the
-- classic ones: unknown).
local function FillRepStandings(tt, Rep, react, value, span, full, mask)
  local Tokens = ns.Tokens
  Header(tt, L.TT_REP_STANDINGS)
  local _, status, _, _, ps = Rep.Rate(mask)
  local withEta = ps ~= nil and ps > 0 and (status == "ok" or status == "stalled")
  for r = 1, Rep.MAX_REACTION do
    local label = StandingName(r)
    if r < react then
      Double(tt, "pair", label, L.TT_REP_REACHED, P.dim, P.dim)
    elseif r == react then
      local c = Rep.ColorArray(r)
      local right = full and L.TT_REP_TOP or Tokens.PercentText(Tokens.PercentTenths(value, span))
      Double(tt, "pair", format(L.TT_REP_CURRENT_FMT, label), right, c, c)
    else
      local need = Rep.Needed(r)
      if need == nil then
        PairDim(tt, label, L.DOTS)
      elseif withEta and status == "stalled" then
        PairDim(tt, label, format(L.TT_REP_AHEAD_ETA_FMT, Fmt.Number(need), Fmt.ETA(need / ps) .. L.STALL_MARK))
      elseif withEta then
        Pair(tt, label, format(L.TT_REP_AHEAD_ETA_FMT, Fmt.Number(need), Fmt.ETA(need / ps)))
      else
        Pair(tt, label, format(L.TT_REP_AHEAD_FMT, Fmt.Number(need)))
      end
    end
  end
end

-- Reputation per hour (the XP per hour's statuses: no data yet, warming up, frozen), the
-- time to the next standing (none at Exalted), the session's gain.
local function FillRepRate(tt, Rep, full, mask)
  local reph, status, left, stall = Rep.Rate(mask)
  if reph == nil then
    -- (the XP's "available after ~N of counted play" is too wide beside this label)
    PairDim(tt, L.TT_REPH, left >= 60 and format(L.TT_WARMING_FMT, Dur(left)) or L.TT_REP_NODATA)
  elseif status == "ok" then
    Pair(tt, L.TT_REPH, Fmt.Rate(reph))
  elseif status == "stalled" then
    PairDim(tt, L.TT_REPH, Fmt.Rate(reph) .. L.STALL_MARK)
    WrapNote(tt, format(L.TT_REP_STALLED_FMT, L.STALL_MARK, Dur(stall)))
    WrapNote(tt, L.TT_REP_STALLED_RESUME)
  else
    PairDim(tt, L.TT_REPH, Fmt.Rate(reph))
  end
  if not full then
    local eta, est = Rep.Eta(mask)
    if est == "warming" then
      PairDim(tt, L.TT_REP_NEXT, format(L.TT_WARMING_FMT, Dur(left)))
    elseif eta ~= nil and est == "stalled" then
      PairDim(tt, L.TT_REP_NEXT, Fmt.ETA(eta) .. L.STALL_MARK)
    elseif eta ~= nil then
      Pair(tt, L.TT_REP_NEXT, Fmt.ETA(eta))
    else
      PairDim(tt, L.TT_REP_NEXT, L.TT_NO_RATE)
    end
  end
  local gain = Rep.SessionGain()
  if gain > 0 then
    Pair(tt, L.TT_REP_SESSION, format(L.TT_REP_GAIN_FMT, Fmt.Number(gain)))
  else
    PairDim(tt, L.TT_REP_SESSION, Fmt.Number(0))
  end
end

-- The reputation's detailed tooltip: the title row (+ exclusions), the pause and read-only
-- lines as in the general one, then its section (the faction, the standings, the rate),
-- the hint. Any GameTooltip-like object or a TooltipFrame frame; `pal` as Tooltip.Fill.
-- Without a followed faction, a note says how to follow one.
function Tooltip.FillRep(tt, pal)
  if not tt then return end
  P = pal or Classic()
  isTP = rawget(tt, "TP_Row") ~= nil
  local Tokens, Rep = ns.Tokens, ns.Rep
  Tokens.UpdateContext(GetTime())
  local ctx = Tokens.ctx
  local mask = ctx.mask
  local excl = ns.Stats.MaskLabel(mask)
  if excl then
    Double(tt, "title", L.ADDON_TITLE, format(L.TT_EXCL_FMT, excl), P.title, P.mode)
  else
    Line(tt, "title", L.ADDON_TITLE, P.title)
  end
  if ctx.paused then Line(tt, "alert", format(L.TT_PAUSED_FMT, PauseLabel(ctx.pauseReason)), P.pause) end
  if ns.readOnly then Line(tt, "alert", L.TT_READONLY, P.pause) end
  Sep(tt, "header")
  Section(tt, L.TT_SECTION_REP)
  local name, react, value, span, full
  if Rep then name, react, value, span, full = Rep.Get() end
  if name == nil then
    WrapNote(tt, L.TT_REP_NONE)
  else
    FillRepFaction(tt, Rep, name, react, value, span, full)
    Sep(tt, "block")
    FillRepStandings(tt, Rep, react, value, span, full, mask)
    Sep(tt, "block")
    FillRepRate(tt, Rep, full, mask)
  end
  Sep(tt, "footer")
  Line(tt, "hint", L.TT_REP_HINT, P.hint)
  P, isTP = nil, false
end

---------------------------------------------------------------------------
-- The PvP detailed tooltip
---------------------------------------------------------------------------

-- A PvP rate row (Pvp.Rate's values): its statuses as the XP per hour's (dimmed while
-- warming up; dimmed with L.STALL_MARK while paused or kept at a cap).
local function FillPvpRate(tt, label, v, status, left)
  if v == nil then
    PairDim(tt, label, left >= 60 and format(L.TT_WARMING_FMT, Dur(left)) or L.TT_PVP_NODATA)
  elseif status == "ok" then
    Pair(tt, label, Fmt.Rate(v))
  elseif status == "paused" or status == "capped" then
    PairDim(tt, label, Fmt.Rate(v) .. L.STALL_MARK)
  else
    PairDim(tt, label, Fmt.Rate(v))
  end
end

-- A time row from an ETA and its status (Pvp.HonorEta / RankEta).
local function FillPvpEta(tt, label, eta, status, left)
  if status == "warming" and eta == nil then
    PairDim(tt, label, format(L.TT_WARMING_FMT, Dur(left)))
  elseif eta ~= nil and (status == "paused" or status == "capped") then
    PairDim(tt, label, Fmt.ETA(eta) .. L.STALL_MARK)
  elseif eta ~= nil and status == "warming" then
    PairDim(tt, label, Fmt.ETA(eta))
  elseif eta ~= nil then
    Pair(tt, label, Fmt.ETA(eta))
  else
    PairDim(tt, label, L.TT_NO_RATE)
  end
end

-- "1,234 / 25,000 (4.9%)".
local function OfText(v, span)
  local Tokens = ns.Tokens
  return format(L.TT_PVP_OF_FMT, Fmt.Number(v), Fmt.Number(span), Tokens.PercentText(Tokens.PercentTenths(v, span)))
end

-- The honor: the amount toward its cap (its colour from Pvp.WARN of the cap, red at it),
-- this session's gain, per hour, the time to the cap, since when it is at its cap.
local function FillPvpHonor(tt, Pvp, mask)
  Header(tt, L.TT_PVP_HONOR)
  local on, q, max, capAt = Pvp.Honor()
  if not on then
    PairDim(tt, L.TT_PVP_AMOUNT, L.DOTS)
    return
  end
  if max > 0 then
    local _, _, key = Pvp.Value("honor")
    Double(tt, "pair", L.TT_PVP_AMOUNT, OfText(q < max and q or max, max), P.label,
      key == 1 and P.value or Pvp.ColorArray(key))
  else
    Pair(tt, L.TT_PVP_AMOUNT, Fmt.Number(q))
  end
  local gained = Pvp.Session()
  if gained > 0 then
    Pair(tt, L.TT_PVP_SESSION, format(L.TT_REP_GAIN_FMT, Fmt.Number(gained)))
  else
    PairDim(tt, L.TT_PVP_SESSION, Fmt.Number(0))
  end
  local v, status, left = Pvp.Rate("honor", mask)
  FillPvpRate(tt, L.TT_PVP_HONORH, v, status, left)
  if max <= 0 then return end
  if q >= max then
    local since = capAt and (time() - capAt) or 0
    Line(tt, "wrap", format(L.TT_PVP_AT_CAP_FMT, Dur(since)), Pvp.ColorArray(Pvp.KEY_CAP), true)
  else
    local eta, est = Pvp.HonorEta(mask)
    FillPvpEta(tt, L.TT_PVP_CAP_IN, eta, est, left)
  end
end

-- The rank: rank and title, the points inside it, the season total, this week's cap and
-- what is left of it (and when the next rank is that cap: the last one reachable this
-- week), per hour, the time to the next rank (or blocked by the cap until the weekly
-- reset), this session's gain, the season's end. "Season not started" alone before.
local function FillPvpRank(tt, Pvp, mask)
  Header(tt, L.TT_PVP_RANK)
  local on, level, pts, thr, _, noSeason, isMax, total = Pvp.Rank()
  if not on then
    PairDim(tt, L.TT_PVP_RANK_PTS, L.DOTS)
    return
  end
  if noSeason then
    Line(tt, "wrap", L.PVP_NO_SEASON, P.value, true)
    return
  end
  local name, title = Pvp.RankName(level)
  Line(tt, "line", title and (name .. L.SEP .. title) or name, Pvp.ColorArray(Pvp.KEY_RANK))
  if isMax then
    Pair(tt, L.TT_PVP_RANK_PTS, L.PVP_RANK_MAX)
  elseif thr > 0 then
    Pair(tt, L.TT_PVP_RANK_PTS, OfText(pts < thr and pts or thr, thr))
  end
  if total ~= nil then Pair(tt, L.TT_PVP_SEASON_TOTAL, Fmt.Number(total)) end
  local week, capLevel, capTotal, _, capped, last = Pvp.Week()
  if capLevel > 0 and capTotal > 0 then
    Pair(tt, format(L.TT_PVP_WEEK_CAP_FMT, week), format(L.TT_PVP_WEEK_CAP_VAL_FMT, capLevel, Fmt.Number(capTotal)))
    if capped then
      Line(tt, "line", L.PVP_WEEK_CAPPED, P.pause)
    elseif not isMax and total ~= nil and capTotal > total then
      Pair(tt, L.TT_PVP_WEEK_LEFT, Fmt.Number(capTotal - total))
    end
    if last then Line(tt, "wrap", format(L.TT_PVP_LAST_FMT, capLevel), P.value, true) end
  end
  local v, status, left = Pvp.Rate("rank", mask)
  FillPvpRate(tt, L.TT_PVP_RANKH, v, status, left)
  if not isMax then
    local eta, est, nxt = Pvp.RankEta(mask)
    local label = format(L.TT_PVP_NEXT_FMT, nxt or (level + 1))
    if est == "capped" then
      PairDim(tt, label, L.PVP_BLOCKED)
      local reset = Pvp.WeeklyReset()
      WrapNote(tt, reset and format(L.TT_PVP_UNLOCK_FMT, Dur(reset)) or L.TT_PVP_UNLOCK)
    else
      FillPvpEta(tt, label, eta, est, left)
    end
  end
  local _, gained = Pvp.Session()
  if gained > 0 then
    Pair(tt, L.TT_PVP_SESSION, format(L.TT_REP_GAIN_FMT, Fmt.Number(gained)))
  else
    PairDim(tt, L.TT_PVP_SESSION, Fmt.Number(0))
  end
  local ends = Pvp.SeasonEnd()
  if ends then Pair(tt, L.TT_PVP_SEASON_END, Dur(ends)) end
end

-- A count of honorable kills ("..." while unknown).
local function KillRow(tt, label, v)
  if v ~= nil then Pair(tt, label, Fmt.Number(v)) else PairDim(tt, label, L.DOTS) end
end

-- Honorable kills: today, yesterday, this session, lifetime, the highest rank ever.
local function FillPvpKills(tt, Pvp)
  Header(tt, L.TT_PVP_HK)
  local today, yest, ses, life, high = Pvp.Kills()
  KillRow(tt, L.TT_PVP_TODAY, today)
  KillRow(tt, L.TT_PVP_YESTERDAY, yest)
  KillRow(tt, L.TT_PVP_THIS_SESSION, ses)
  KillRow(tt, L.TT_PVP_LIFETIME, life)
  if high ~= nil and high >= 5 then
    Pair(tt, L.TT_PVP_HIGHEST, Tooltip.PvpEnumTitle(high) or format(L.PVP_RANK_FMT, high - 4))
  end
end

-- This session's battlegrounds: played, won - lost, average honor, average length; the one
-- in progress counts when it is left.
local function FillPvpBG(tt, Pvp)
  Header(tt, L.TT_PVP_BG)
  local _, _, won, lost, n, avgHonor, avgDur = Pvp.Session()
  if n == 0 then
    Note(tt, L.TT_PVP_BG_NONE)
  else
    Pair(tt, L.TT_PVP_BG_COUNT, Fmt.Number(n))
    Pair(tt, L.TT_PVP_BG_RECORD, format(L.TT_PVP_WL_FMT, won, lost))
    Pair(tt, L.TT_PVP_BG_HONOR, Fmt.Number(avgHonor or 0))
    Pair(tt, L.TT_PVP_BG_DUR, Dur(avgDur or 0))
  end
  if Pvp.InBG() then Note(tt, L.TT_PVP_BG_NOW) end
end

-- The PvP detailed tooltip: the title row (+ exclusions), the pause and read-only lines as
-- in the general one, then its section (honor, rank, kills, battlegrounds; why a rate is
-- paused), the hint. Any GameTooltip-like object or a TooltipFrame frame; `pal` as
-- Tooltip.Fill. Without PvP data (Classic Era), a note says so.
function Tooltip.FillPvp(tt, pal)
  if not tt then return end
  P = pal or Classic()
  isTP = rawget(tt, "TP_Row") ~= nil
  local Tokens, Pvp = ns.Tokens, ns.Pvp
  Tokens.UpdateContext(GetTime())
  local ctx = Tokens.ctx
  local mask = ctx.mask
  local excl = ns.Stats.MaskLabel(mask)
  if excl then
    Double(tt, "title", L.ADDON_TITLE, format(L.TT_EXCL_FMT, excl), P.title, P.mode)
  else
    Line(tt, "title", L.ADDON_TITLE, P.title)
  end
  if ctx.paused then Line(tt, "alert", format(L.TT_PAUSED_FMT, PauseLabel(ctx.pauseReason)), P.pause) end
  if ns.readOnly then Line(tt, "alert", L.TT_READONLY, P.pause) end
  Sep(tt, "header")
  Section(tt, L.TT_SECTION_PVP)
  if not (Pvp and Pvp.Has()) then
    WrapNote(tt, (Pvp and Pvp.Available()) and L.TT_PVP_NONE or L.OPT_PVP_UNAVAILABLE)
  else
    FillPvpHonor(tt, Pvp, mask)
    Sep(tt, "block")
    FillPvpRank(tt, Pvp, mask)
    local _, hs = Pvp.Rate("honor", mask)
    local _, rs = Pvp.Rate("rank", mask)
    if hs == "paused" or rs == "paused" then
      WrapNote(tt, format(L.TT_PVP_PAUSED_FMT, L.STALL_MARK, Dur(ns.C.PVP_IDLE)))
    end
    Sep(tt, "block")
    FillPvpKills(tt, Pvp)
    Sep(tt, "block")
    FillPvpBG(tt, Pvp)
  end
  Sep(tt, "footer")
  Line(tt, "hint", L.TT_REP_HINT, P.hint)
  P, isTP = nil, false
end

---------------------------------------------------------------------------
-- The pair shown by ShowFor (SPEC-themes 4.1): block 1 (the level in progress) always,
-- block 2 (the whole character) beside it while Shift is held. Side by side: block 1 on
-- the left, block 2 BLOCK_GAP px to its right, each at its own natural width, block 2
-- moved up or down so that the two breakdown rows (the gauge rows, or the native
-- "breakdown" lines) face each other (tops aligned when a block has none). A pair wider
-- than the screen falls back to the stack: block 2 under block 1, one width (the larger
-- natural one), BLOCK_GAP px apart, block 1 on top. The footer hint at the bottom of
-- block 2. Native themes: block 1 is the shared GameTooltip, block 2 the addon's own
-- GameTooltip (NATIVE2_NAME, created once); other themes: the two frames of
-- TooltipFrame.lua. Broker tooltips stay one tooltip (Tooltip.Fill).
-- The native blocks' breakdown bars (PlaceBars): each block's breakdown line carries the
-- label alone (Fill with a bar), and a bar of TooltipFrame.lua (TooltipFrame.Bar, the
-- classic gauge) goes from BAR_GAP px right of the label to the line's right text edge.
-- Block 1's bar is a frame of UIParent anchored to the label's FontString: nothing is
-- added to the shared GameTooltip, whose only hook stays the OnHide one (OnBlock1Hide,
-- which hides that bar); block 2's is its child. A block too narrow for a bar of the
-- gauge's minimum width is widened (SetMinimumWidth, dropped like the stack's).
---------------------------------------------------------------------------

local OWNER_GAP = 4             -- px between the owner and the pair
local BLOCK_GAP = 4             -- px between the two blocks (side by side or stacked)
local BAR_GAP = 8               -- px between a native block's breakdown label and its bar
local NATIVE2_NAME = "TruePlayedCharTooltip"

local shownTT2 = nil            -- block 2 while it is shown (Shift), else nil
local below = false             -- the pair hangs below its owner (7.6), set by ShowFor; "the
                                -- owner" of the placement below is shownAt (ShowFor's anchor)
local placed = nil              -- anchors in place: 1 = block 1 alone, 2 = stacked,
                                -- 3 = side by side, nil = none
local placedW1, placedH, placedH2, placedD = nil, nil, nil, nil   -- what they were set for
local bdRow1, bdRow2 = 0, 0     -- the blocks' breakdown rows (from Fill), 0 = none
local bar1, bar2 = nil, nil     -- the shown native blocks' bars (TooltipFrame.Bar), else nil
local minTT = nil               -- the GameTooltip (block 1) ShowPair gave a minimum width
local hookedTT = nil            -- the GameTooltip (block 1) whose OnHide runs OnBlock1Hide
local nativeTT2 = nil           -- block 2 of the native themes, once created
local lineTexts = {}            -- [GameTooltip] = { [line] = its left text or false }
local rightTexts = {}           -- [GameTooltip] = { [line] = its right text or false }

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

-- Block 2's target beside block 1's `tt`: the second private frame (non-native themes),
-- else the addon's own GameTooltip, created at the first need and kept.
local function Second(tt)
  if tt ~= GameTooltip then
    local TF = ns.TooltipFrame
    return TF and TF.Get(2) or nil
  end
  local t2 = nativeTT2
  if t2 == nil then
    t2 = CreateFrame("GameTooltip", NATIVE2_NAME, UIParent, "GameTooltipTemplate")
    if t2.SetClampedToScreen then t2:SetClampedToScreen(true) end
    nativeTT2 = t2
  end
  return t2
end

-- A size or position read from a frame (nil when unreadable).
local function Size(v)
  if type(v) ~= "number" or ns.Util.IsSecret(v) then return nil end
  return v
end

-- The screen's width and height (UIParent's) in the units of frame `t` (nil when
-- unreadable).
local function ScreenH(t)
  local parent = UIParent
  local h = parent and Size(parent:GetHeight())
  local ps = parent and Size(parent:GetEffectiveScale())
  local ts = Size(t:GetEffectiveScale())
  if h == nil or ps == nil or ts == nil or ts <= 0 then return nil end
  return h * ps / ts
end

local function ScreenW(t)
  local parent = UIParent
  local w = parent and Size(parent:GetWidth())
  local ps = parent and Size(parent:GetEffectiveScale())
  local ts = Size(t:GetEffectiveScale())
  if w == nil or ps == nil or ts == nil or ts <= 0 then return nil end
  return w * ps / ts
end

-- Left text of line `i` of GameTooltip `t` (the client's "<name>TextLeft<i>"), or its
-- right text when `right` ("<name>TextRight<i>"), nil when it has none: looked up once
-- per line (pools only grow, no string built on a refresh).
local function LineText(t, i, right)
  local cache = right and rightTexts or lineTexts
  local list = cache[t]
  if list == nil then
    list = {}
    cache[t] = list
  end
  local fs = list[i]
  if fs == nil then
    local name = t.GetName and t:GetName()
    fs = type(name) == "string" and rawget(_G, name .. (right and "TextRight" or "TextLeft") .. i) or false
    list[i] = fs
  end
  return fs or nil
end

-- Offset (px, down from its top) of the centre of row `row` of shown block `t`, nil when
-- `row` is 0 (no breakdown row) or unreadable: a private frame's layout (TP_RowY), else
-- the centre of that GameTooltip line's left text against the tooltip's top (readable
-- once the tooltip has anchors).
local function RowOffset(t, row)
  if row <= 0 then return nil end
  if rawget(t, "TP_RowY") ~= nil then return t:TP_RowY(row) end
  local fs = LineText(t, row)
  if fs == nil or not fs.GetCenter then return nil end
  local top = Size(t:GetTop())
  local _, cy = fs:GetCenter()
  cy = Size(cy)
  if top == nil or cy == nil then return nil end
  return top - cy
end

-- How far block 1's top sits above block 2's (px, negative: below) so that their
-- breakdown rows have the same centre; 0 (tops aligned) when a block has no breakdown
-- row or a position is unreadable.
local function RowShift(tt, tt2)
  local o1 = RowOffset(tt, bdRow1)
  local o2 = o1 ~= nil and RowOffset(tt2, bdRow2) or nil
  if o2 == nil then return 0 end
  return o1 - o2
end

-- Anchors of block 1 alone (on the owner, as before the pair) and of the stack. Stack:
-- block 2 on the owner (above it: its BOTTOM on the owner's TOP; below it: its TOP lower
-- by block 1's height `h1` and BLOCK_GAP) and block 1 on block 2's TOP, so block 1 is on
-- top either way. Block 2's clamp rect reaches over block 1 (SetClampRectInsets): the
-- screen clamp moves the stack as one piece (one that does not fit covers its owner)
-- instead of pushing one block onto the other. A stack taller than the screen: the clamp
-- rect leaves out the bottom of block 2 (`h2` its height), so block 1 stays whole on top
-- and that bottom goes off the screen. Block 2 is always the addon's own frame: the
-- shared GameTooltip's clamp is never changed. `h1` nil (unreadable): below the owner,
-- block 2 hangs on block 1, each clamped alone.
local function Place(tt, tt2, h1, h2)
  local owner = shownAt
  if tt.ClearAllPoints then tt:ClearAllPoints() end
  if tt2 ~= nil and tt2.ClearAllPoints then tt2:ClearAllPoints() end
  if not tt.SetPoint then return end
  if tt2 == nil then
    if below then
      tt:SetPoint("TOP", owner, "BOTTOM", 0, -OWNER_GAP)
    else
      tt:SetPoint("BOTTOM", owner, "TOP", 0, OWNER_GAP)
    end
    return
  end
  local reach, cut = 0, 0
  if h1 ~= nil then
    reach = h1 + BLOCK_GAP
    local sh = h2 ~= nil and ScreenH(tt2)
    if sh and reach + h2 > sh then cut = reach + h2 - sh end
  end
  if tt2.SetClampRectInsets then tt2:SetClampRectInsets(0, 0, reach, cut) end
  if not below then
    tt2:SetPoint("BOTTOM", owner, "TOP", 0, OWNER_GAP)
  elseif h1 ~= nil then
    tt2:SetPoint("TOP", owner, "BOTTOM", 0, -(OWNER_GAP + reach))
  else
    tt:SetPoint("TOP", owner, "BOTTOM", 0, -OWNER_GAP)
    tt2:SetPoint("TOP", tt, "BOTTOM", 0, -BLOCK_GAP)
    return
  end
  tt:SetPoint("BOTTOM", tt2, "TOP", 0, BLOCK_GAP)
end

-- Anchors side by side: block 1 (`w1` x `h1`) on the left, its top `d` px above block 2's
-- (RowShift), block 2 (height `h2`) BLOCK_GAP px to its right. The pair's box (around
-- both) hangs below the owner or stands on it (7.6), block 1 centred on the owner as when
-- alone. Block 2 is anchored to the owner and block 1 to block 2; block 2's clamp rect
-- covers the box (SetClampRectInsets), so the screen clamp moves both as one piece, never
-- one block alone (the shared GameTooltip's clamp is never changed). A box taller than
-- the screen: the clamp rect keeps the screen's height of it from its top, moved down
-- just enough to keep block 1 whole (block 1 taller than the screen: from its top), so
-- the bottom of block 2 is what goes off the screen.
local function PlaceSide(tt, tt2, w1, h1, h2, d)
  local owner = shownAt
  tt:ClearAllPoints()
  tt2:ClearAllPoints()
  -- the box against block 2's top (y up): from `top` down to `bottom`
  local top = d > 0 and d or 0
  local bottom = d - h1
  if -h2 < bottom then bottom = -h2 end
  local ct, cb = top, bottom
  local sh = ScreenH(tt2)
  if sh and ct - cb > sh then
    cb = ct - sh
    if cb > d - h1 then
      ct = d - h1 + sh
      if ct < d then ct = d end
      cb = ct - sh
    end
  end
  if tt2.SetClampRectInsets then tt2:SetClampRectInsets(-(w1 + BLOCK_GAP), 0, ct, cb + h2) end
  local x = w1 / 2 + BLOCK_GAP
  if below then
    tt2:SetPoint("TOPLEFT", owner, "BOTTOM", x, -(OWNER_GAP + top))
  else
    tt2:SetPoint("BOTTOMLEFT", owner, "TOP", x, OWNER_GAP - h2 - bottom)
  end
  tt:SetPoint("TOPRIGHT", tt2, "TOPLEFT", -BLOCK_GAP, d)
end

-- Width of a shown GameTooltip (nil when unreadable).
local function Width(t)
  return Size(t:GetWidth())
end

-- Drops the minimum width ShowPair set on block 1's GameTooltip (shared: never left
-- for the next owner). Also run by that GameTooltip's OnHide (OnBlock1Hide): the client
-- hides it with its owner without a call to Tooltip.Hide (a menu closed by a click), and
-- the next owner must not show it at our width.
local function ResetMin()
  local t = minTT
  if t == nil then return end
  minTT = nil
  t:SetMinimumWidth(0)
end

-- Block 1's bar (the frame of UIParent over the shared GameTooltip) hidden, whoever shows
-- that GameTooltip now.
local function HideBar1()
  local TF = ns.TooltipFrame
  local b = TF and TF.bar
  if b ~= nil then TF.HideBar(b) end
end

-- The OnHide hook of block 1's GameTooltip (the only script of it the addon touches): its
-- minimum width and its bar go with it.
local function OnBlock1Hide()
  ResetMin()
  HideBar1()
end

-- Hooks OnBlock1Hide on GameTooltip `t` (block 1), once: at its first minimum width or
-- bar.
local function HookHide(t)
  if hookedTT ~= nil then return end
  hookedTT = t
  if t.HookScript then t:HookScript("OnHide", OnBlock1Hide) end
end

local function MinSet(t)
  minTT = t
  HookHide(t)
end

-- Drops that minimum width when our pair lets go of block 1 or shows on target `tt`
-- (nil: none), unless that GameTooltip is shown for another owner: its OnHide drops it
-- then (never reset under another owner's tooltip, which may have set its own).
local function ReleaseMin(tt)
  local t = minTT
  if t ~= nil and (t == tt or not t:IsShown() or t:GetOwner() == shownFor) then ResetMin() end
end

-- Shows GameTooltip `t` `w` px wide (wider than its own width). Whether SetMinimumWidth
-- includes the tooltip's padding is learned at the first use (minPad: what the tooltip
-- adds to its minimum width), then taken off.
local minPad = nil
local function Widen(t, w)
  t:SetMinimumWidth(w - (minPad or 0))
  t:Show()
  if minPad ~= nil then return end
  local got = Width(t)
  if got == nil then return end
  minPad = got > w and got - w or 0
  if minPad > 0 then
    t:SetMinimumWidth(w - minPad)
    t:Show()
  end
end

-- Whether two blocks `w` px wide in all (gap included) fit the screen's width.
local function FitsSide(t, w)
  local sw = ScreenW(t)
  return sw ~= nil and w <= sw
end

-- The width native block `b`'s GameTooltip needs for a bar of the gauge's minimum width
-- (b.need, learned by PlaceBar), 0 when it shows no bar (no bar, or no breakdown row).
local function Need(b, row)
  if b == nil or row <= 0 or b.n <= 0 then return 0 end
  return b.need
end

-- Widens shown GameTooltip `t` to `need` px when narrower (by more than half a px);
-- block 1 (`first`) through MinSet, so that this minimum goes like the stack's
-- (ReleaseMin, OnBlock1Hide).
local function Grow(t, need, first)
  if need <= 0 then return end
  local w = Width(t)
  if w == nil or w > need - 0.5 then return end
  if first then MinSet(t) end
  Widen(t, need)
end

-- Shows the blocks and returns true when they go side by side: both at their natural
-- widths when the two fit the screen's width with BLOCK_GAP between them. Else (false)
-- stacked at the larger natural width: measured before the layout on the private frames;
-- on GameTooltips shown at their own width first, then the narrower one again at the
-- other's (SetMinimumWidth). A native block's natural width is at least what its bar needs
-- (Grow). Block 1 hidden by its own OnShow (see Redraw): neither widened (a minimum set
-- on it then could outlive its OnHide, for the next owner) nor block 2 shown.
local function ShowPair(tt, tt2)
  local tf = rawget(tt, "TP_Measure") ~= nil
  if tt2 == nil then
    if tf then
      tt:TP_MinWidth(0)
      tt:Show()
    else
      ResetMin()
      tt:Show()
      if tt.SetMinimumWidth and tt:IsShown() then Grow(tt, Need(bar1, bdRow1), true) end
    end
    return false
  end
  if tf and rawget(tt2, "TP_Measure") ~= nil then
    local w, w2 = tt:TP_Measure(), tt2:TP_Measure()
    local side = FitsSide(tt2, w + BLOCK_GAP + w2)
    if side then
      w = 0
    elseif w2 > w then
      w = w2
    end
    tt:TP_MinWidth(w)
    tt2:TP_MinWidth(w)
    tt:Show()
    tt2:Show()
    return side
  end
  ResetMin()
  -- block 2 at block 1's scale (a tooltip addon may scale GameTooltip): one unit in px
  local sc = tt.GetScale and tt:GetScale()
  if type(sc) == "number" and tt2.SetScale and tt2:GetScale() ~= sc then tt2:SetScale(sc) end
  local canMin = tt.SetMinimumWidth ~= nil and tt2.SetMinimumWidth ~= nil
  if canMin then tt2:SetMinimumWidth(0) end
  tt:Show()
  if not tt:IsShown() then return false end
  tt2:Show()
  if canMin then
    Grow(tt, Need(bar1, bdRow1), true)
    Grow(tt2, Need(bar2, bdRow2), false)
  end
  local w, w2 = Width(tt), Width(tt2)
  if w == nil or w2 == nil then return false end
  if FitsSide(tt2, w + BLOCK_GAP + w2) then return true end
  if not canMin then return false end
  if w < w2 then
    MinSet(tt)
    Widen(tt, w2)
  elseif w2 < w then
    Widen(tt2, w)
  end
  return false
end

-- Hides block 2 (ours whoever its owner: no other code shows it), and its bar.
local function HideSecond()
  local t2 = shownTT2
  shownTT2 = nil
  if t2 ~= nil and t2:IsShown() then t2:Hide() end
  local TF = ns.TooltipFrame
  local b = TF and TF.bar2
  if b ~= nil then TF.HideBar(b) end
end

local function StillOurs()
  local tt = shownTT
  return shownFor ~= nil and tt ~= nil and tt:IsShown() and tt:GetOwner() == shownFor
end

-- Stops following the shown tooltip: block 2 and the bars are hidden, block 1 left to its
-- new owner (with its minimum width only while that owner shows it: ReleaseMin).
local function Detach()
  HideSecond()
  HideBar1()
  bar1, bar2 = nil, nil
  ReleaseMin(nil)
  shownFor = nil
  shownAt = nil
  shownHint = nil
  shownTT = nil
  shownPal = nil
  shownKind = nil
  placed = nil
  ns.UnregisterMessage("TICK", Tooltip)
  ns.UnregisterEvent("MODIFIER_STATE_CHANGED", Tooltip)
end

-- Anchors of the shown pair (ShowPair's `side`): set again only when block 2 comes or
-- goes, the layout changes (side by side / stacked), or what the anchors depend on
-- changes: side by side, block 1's width, both heights and the rows' shift (RowShift);
-- stacked, both heights. Shown before: a GameTooltip's size is known at its Show, and
-- its lines' positions once it has anchors (the shift is read again after placing, and
-- the pair placed again when it differs).
local function Arrange(tt, tt2, side)
  if tt2 == nil then
    if placed ~= 1 then
      Place(tt, nil)
      placed, placedW1, placedH, placedH2, placedD = 1, nil, nil, nil, nil
    end
    return
  end
  local h1, h2 = Size(tt:GetHeight()), Size(tt2:GetHeight())
  local w1 = side and Size(tt:GetWidth()) or nil
  if w1 ~= nil and h1 ~= nil and h2 ~= nil then
    local d = RowShift(tt, tt2)
    if placed ~= 3 or w1 ~= placedW1 or h1 ~= placedH or h2 ~= placedH2 or d ~= placedD then
      PlaceSide(tt, tt2, w1, h1, h2, d)
      local d2 = RowShift(tt, tt2)
      if d2 ~= d then
        d = d2
        PlaceSide(tt, tt2, w1, h1, h2, d)
      end
      placed, placedW1, placedH, placedH2, placedD = 3, w1, h1, h2, d
    end
    return
  end
  if placed ~= 2 or h1 ~= placedH or h2 ~= placedH2 then
    Place(tt, tt2, h1, h2)
    placed, placedW1, placedH, placedH2, placedD = 2, nil, h1, h2, nil
  end
end

-- Bar `b` of shown native block `t` (a GameTooltip placed by Arrange) on its breakdown
-- line `row` (0: none, the bar hidden): from BAR_GAP px right of the label's text (the
-- frame anchored to that FontString) to the line's right text edge, read from the two
-- texts' positions (known once the block has anchors), at a frame level above the
-- block's and at its scale (`scale`: block 1's, for the frame of UIParent). b.need, the
-- block's width for a bar of the gauge's minimum (b.min), is learned here; returns true
-- (the bar left as it was) when the bar would be narrower than that minimum by more than
-- half a px (the client's sizes are fractional: no second pass for float noise), unless
-- `force` (a block that could not be widened: the bar as wide as the line leaves, hidden
-- under 1 px). Hidden when a position is unreadable.
local function PlaceBar(b, t, row, scale, force)
  local TF = ns.TooltipFrame
  if row <= 0 or b.n <= 0 then
    TF.HideBar(b)
    return false
  end
  local lf, rf = LineText(t, row), LineText(t, row, true)
  local lr = lf ~= nil and Size(lf:GetRight()) or nil
  local rr = rf ~= nil and Size(rf:GetRight()) or nil
  local w = Width(t)
  if lr == nil or rr == nil or w == nil then
    TF.HideBar(b)
    return false
  end
  local bw = rr - lr - BAR_GAP
  b.need = w - bw + b.min
  if bw < b.min - 0.5 and not force then return true end
  if bw < 1 then
    TF.HideBar(b)
    return false
  end
  TF.PlaceBar(b, lf, BAR_GAP, bw, (t:GetFrameLevel() or 0) + 2, scale)
  return false
end

-- The bars of the shown native blocks (bar1, bar2: nil for the private frames). Returns
-- true when a block must be widened first (PlaceBar).
local function PlaceBars(tt, tt2, force)
  local grow = false
  local b = bar1
  if b ~= nil then
    local sc = tt.GetScale and tt:GetScale()
    grow = PlaceBar(b, tt, bdRow1, type(sc) == "number" and sc or 1, force)
  end
  b = bar2
  if b ~= nil and tt2 ~= nil and PlaceBar(b, tt2, bdRow2, 1, force) then grow = true end
  return grow
end

-- Fills, shows and places the pair: block 1, and block 2 while Shift is held (and the
-- character has data); on GameTooltips (native themes) with their breakdown bars, the
-- blocks shown and placed again once when a bar needs a wider block (its first show).
local function Redraw()
  local tt, owner = shownTT, shownFor
  if shownKind ~= nil then                       -- the reputation's or PvP's: one block, no bar
    if tt.ClearLines then tt:ClearLines() end
    if shownKind == "pvp" then Tooltip.FillPvp(tt, shownPal) else Tooltip.FillRep(tt, shownPal) end
    HideSecond()
    if bar1 ~= nil then HideBar1() end
    bar1, bar2, bdRow1 = nil, nil, 0
    Arrange(tt, nil, ShowPair(tt, nil))
    return
  end
  local detailed = IsShiftKeyDown ~= nil and IsShiftKeyDown() and true or false
  local tt2 = detailed and Second(tt) or nil
  local TF = ns.TooltipFrame
  local native = TF ~= nil and rawget(tt, "TP_Row") == nil
  local b1 = native and TF.Bar(1) or nil
  if tt.ClearLines then tt:ClearLines() end
  local more, row = Tooltip.Fill(tt, detailed, shownHint, shownPal, tt2 and 1 or 0, b1)
  if not more then tt2 = nil end
  bdRow1 = row
  local b2 = nil
  if tt2 ~= nil then
    if tt2:GetOwner() ~= owner then
      tt2:SetOwner(owner, "ANCHOR_NONE")
      placed = nil
    elseif tt2.ClearLines then
      tt2:ClearLines()
    end
    b2 = native and TF.Bar(2, tt2) or nil
    local _, row2 = Tooltip.Fill(tt2, true, shownHint, shownPal, 2, b2)
    bdRow2 = row2
  end
  if shownTT2 ~= tt2 then
    HideSecond()
    shownTT2 = tt2
  end
  bar1, bar2 = b1, b2
  if b1 ~= nil and bdRow1 > 0 then HookHide(tt) end
  Arrange(tt, tt2, ShowPair(tt, tt2))
  -- block 1 hidden by its own OnShow (the client's GameTooltip_OnShow in gamepad mode, a
  -- tooltip addon hiding it in combat): no bar placed, as block 1's (a frame of UIParent)
  -- would stay alone on the screen; the next refresh lets go (Detach). Shown, block 1
  -- stays so on the second pass (Show on a shown frame runs no OnShow).
  if not StillOurs() then return end
  if (b1 ~= nil or b2 ~= nil) and PlaceBars(tt, tt2, false) then
    Arrange(tt, tt2, ShowPair(tt, tt2))
    PlaceBars(tt, tt2, true)
  end
end

-- The client hides the GameTooltips with their owner, not the private frames: an owner
-- hidden without OnLeave (the addon compartment menu closed by a click) leaves them shown.
local function OwnerGone()
  local o = shownFor
  return shownTT ~= GameTooltip and o.IsVisible ~= nil and not o:IsVisible()
end

-- TICK and MODIFIER_STATE_CHANGED while shown: redraw, detach when the tooltip was hidden
-- or taken by another owner (block 2 is hidden then), hide both blocks when their owner
-- is gone.
local function OnRefresh()
  if not StillOurs() then
    Detach()
    return
  end
  if OwnerGone() then
    Tooltip.Hide()
    return
  end
  Redraw()
end

-- Target and palette of the active theme (SPEC-themes 4.1): the shared GameTooltip
-- for a native theme (Classic), else the private TooltipFrame.
local function Target()
  local Themes = ns.Themes
  local th = Themes and Themes.Active()
  local tc = th and th.tt
  local pal = tc and tc.colors or Classic()
  if th and not th.native and tc then
    local TF = ns.TooltipFrame
    if TF then return TF.Get(), pal end
  end
  return GameTooltip, pal
end

-- `hint` (optional): last line to show instead of L.TT_HINT (addon compartment). `kind`
-- (optional): "rep" shows the reputation's detailed tooltip (Tooltip.FillRep) instead,
-- "pvp" the PvP one (Tooltip.FillPvp; the rank and the honorable kills read again first:
-- Pvp.ReadAgain, before anything is set up). `anchor`
-- (optional): the frame the tooltip hangs off and whose half of the screen decides above
-- or below (7.6), when the owner is a region inside it (the bar's hover regions: the
-- tooltip goes off the bar, not over it); the owner stays the owner (IsShownFor, Hide).
function Tooltip.ShowFor(owner, hint, kind, anchor)
  if owner == nil then return end
  if kind == "pvp" and ns.Pvp then ns.Pvp.ReadAgain() end
  local tt, pal = Target()
  if tt == nil then return end
  local prev = shownTT
  if prev ~= nil and prev ~= tt and shownFor ~= nil and prev:GetOwner() == shownFor then prev:Hide() end
  HideSecond()                  -- shown again by Redraw while Shift is held
  ReleaseMin(tt)
  tt:SetOwner(owner, "ANCHOR_NONE")
  shownFor = owner
  shownAt = anchor or owner
  shownHint = hint
  shownKind = (kind == "rep" or kind == "pvp") and kind or nil
  shownTT = tt
  shownPal = pal
  below = IsUpperHalf(shownAt)
  placed = nil
  Redraw()
  ns.RegisterMessage("TICK", Tooltip, OnRefresh)
  ns.RegisterEvent("MODIFIER_STATE_CHANGED", Tooltip, OnRefresh)
end

-- Hides both blocks.
function Tooltip.Hide(owner)
  if shownFor == nil then return end
  if owner ~= nil and owner ~= shownFor then return end
  local tt = shownTT
  if tt ~= nil and tt:GetOwner() == shownFor then tt:Hide() end
  Detach()
end

function Tooltip.IsShownFor(owner)
  return owner ~= nil and owner == shownFor and StillOurs()
end

-- A theme switch or recolour (either kind of THEME_CHANGED) hides the tooltip; the next
-- show uses the new theme (SPEC-themes 4.1).
local function OnThemeChanged()
  Tooltip.Hide()
end

if ns.RegisterMessage then
  ns.RegisterMessage("THEME_CHANGED", Tooltip, OnThemeChanged)
end
