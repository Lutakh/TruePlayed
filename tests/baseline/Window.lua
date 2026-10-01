local ADDON, ns = ...
local L, C, Util, Fmt = ns.L, ns.C, ns.Util, ns.Fmt

-- Window.lua - statistics window (levels / zones / sessions), built lazily on the
-- first Show. It listens to messages only while shown: a full rebuild on data
-- events, and every C.WINDOW_ROW_REFRESH ticks only the live cells (time of the
-- in-progress level, duration of the live session, footer total) are updated.
-- XP gains only mark the view dirty: the rebuild they need (XP, XP/h, zone order)
-- waits for a live-cell step at least DIRTY_REBUILD_TICKS after the last rebuild,
-- and never happens while another character is viewed (our XP cannot change it).
-- Hovering a level row lists the zones of that level (requirement 4).
-- Zones tab: continents block (Stats.Continents, exclusions applied), then the most
-- played instances (Stats.TopInstances, kind shown after the name), then the top
-- capitals, then every zone; the same blocks for the account view (merged zones).
-- Levels and Sessions tabs: the Inst. column is the time spent in instances (dungeons,
-- raids, PvP) counted under the exclusions, like the time column; the footer adds the
-- instance total when there is one.
-- Requirement B: the view is the current character unless the user picks another
-- character or the account view; every Show resets it to the current character.

local math_floor, math_max = math.floor, math.max
local type, pairs, tonumber = type, pairs, tonumber
local table_sort = table.sort
local format, wipe, tinsert = format, wipe, tinsert
local CreateFrame, UIParent, GetTime = CreateFrame, UIParent, GetTime

local Window = {}
ns.Window = Window

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local WIN_W, WIN_H = 700, 440
local ROW_H = 16
local CONTENT_W = 650
local DASH = "-"
local APPROX = "~"
local VIEW_CURRENT, VIEW_ACCOUNT = "current", "account"
local CITY_ROWS = 6
local INST_ROWS = 8                -- most played instances listed in the Zones tab
-- Rows are pooled, one per data row, and never released: the pool is bounded by the
-- largest tab shown (C.ZONES_MAX zones per character; the account view merges them).
-- A virtual list with a fixed pool is a possible later improvement (review PERF-2).
local ZONE_ROWS = 1000
local TIP_ZONES = 5                -- zones listed in a level row tooltip
local DIRTY_REBUILD_TICKS = 30     -- min ticks between two rebuilds caused by XP gains

local TAB_ORDER = { "levels", "zones", "sessions" }
local TAB_KEY = { levels = "TAB_LEVELS", zones = "TAB_ZONES", sessions = "TAB_SESSIONS" }
local KIND_KEY = { d = "KIND_DUNGEON", r = "KIND_RAID", p = "KIND_PVP" }   -- Stats.TopInstances kinds

-- Column layouts: locale key of the header, x offset, width, justification.
local function Col(key, x, w, j) return { key = key, x = x, w = w, j = j or "LEFT" } end
local LAYOUTS = {
  levels = {   -- the main zone gets the room long French zone names need
    Col("COL_LEVEL", 0, 30), Col("COL_TIME", 32, 62), Col("COL_SERVER", 96, 58),
    Col("COL_XPH", 156, 52), Col("COL_AFK", 210, 52), Col("COL_INN", 264, 52),
    Col("COL_CITY", 318, 52), Col("COL_INST", 372, 52), Col("COL_MAIN_ZONE", 426, 156),
    Col("COL_REACHED", 586, 60),
  },
  account = {
    Col("COL_LEVEL", 0, 40), Col("COL_CHARS", 44, 60), Col("COL_AVG", 110, 100), Col("COL_XPH", 214, 80),
  },
  zones = {    -- instance rows carry their kind after the name: a wide first column
    Col("COL_ZONE", 0, 290), Col("COL_TIME", 294, 80), Col("COL_RAW", 378, 80),
    Col("COL_AFK", 462, 80), Col("COL_XP", 546, 100),
  },
  sessions = {
    Col("COL_DATE", 0, 90), Col("COL_DURATION", 94, 72), Col("COL_LEVELS", 170, 120),
    Col("COL_XP", 294, 84), Col("COL_XPH", 382, 72), Col("COL_AFK", 458, 72),
    Col("COL_INST", 534, 72),
  },
  section = { Col(nil, 0, CONTENT_W) },
}
local MAX_COLS = 10

local WIN_BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BTN_BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }

local EXCLUDE_PATHS = { ["exclude.afk"] = true, ["exclude.inn"] = true, ["exclude.city"] = true }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame, scroll, content
local viewFS, prevBtn, nextBtn, eraseBtn, emptyFS, footer1, footer2
local filterFS, hintFS             -- active exclusions (header), Levels tab hint
local tabBtns = {}
local headerFS = {}
local btnText = {}                 -- [button] = FontString
local rows = {}                    -- pooled row frames
local rowCells = {}                -- [row] = { FontString... }
local rowLayout = {}               -- [row] = applied layout
local rowTip = {}                  -- [row] = reused tooltip data
local nUsed = 0

local curTab = "levels"
local view = VIEW_CURRENT
local listening = false
local tickCount = 0
local sinceRebuild = 0             -- ticks since the last full rebuild
local dirty = false                -- XP changed since the last rebuild

-- live cells (current character only)
local liveLevelRow, liveLevel, liveApprox, liveLevelKey = nil, 0, false, -1
local liveSessionRow, liveSessionKey = nil, -1
local liveTotalKey = -1

-- reused data tables for Stats (alloc) functions: Stats recycles the row tables
-- found in `out` and returns the row count, so they are never wiped here
local levelRows, cityRows, zoneRows, sessionRows, accountRows = {}, {}, {}, {}, {}
local contRows, contRawRows, contNoAfkRows = {}, {}, {}   -- Stats.Continents outputs
local contRaw, contNoAfk, contListed = {}, {}, {}          -- key -> seconds / listed flag
local instRows = {}                -- Stats.TopInstances output
local accountZones = {}
local tipZoneRows = {}             -- level row tooltip (allocation on hover only)
local viewList, otherList = {}, {}
local sortChars

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function CurrentGuid()
  local char = ns.char
  return char and char.guid
end

local function IntText(n)
  return format("%d", math_floor(tonumber(n) or 0))
end

local function DurText(sec)
  sec = tonumber(sec)
  if not sec or sec <= 0 then return DASH end
  return Fmt.Duration(sec)
end

local function TimeText(sec, approx)
  local s = Fmt.Duration(sec or 0)
  if approx then return APPROX .. s end
  return s
end

-- Instance seconds (dungeons, raids, PvP) of a bucket under `mask`.
local function InstSecs(bucket, mask)
  if type(bucket) ~= "table" then return 0 end
  return ns.Stats.InstanceTime(bucket, mask)
end

-- Resolves the viewed character: the current record, another record, or nil
-- for the account view. An erased or vanished record falls back to current.
local function ViewChar()
  if view == VIEW_ACCOUNT then return nil end
  if view ~= VIEW_CURRENT then
    local chars = ns.db and ns.db.chars
    local rec = chars and chars[view]
    if rec and view ~= CurrentGuid() then return rec end
    view = VIEW_CURRENT
  end
  return ns.char
end

local function ZoneNameOf(char, key)
  local Stats = ns.Stats
  if key == nil then return DASH end
  local zones = char and char.zones
  if type(key) == "number" or key == "o" or (zones and zones[key]) then
    return Stats.ZoneName(key, zones and zones[key])
  end
  return tostring(key)            -- already a display name
end

local function MakeButton(parent, text, w, h, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(w, h)
  if b.SetBackdrop then
    b:SetBackdrop(BTN_BACKDROP)
    local t, bd = C.COLORS.track, C.COLORS.border
    b:SetBackdropColor(t[1], t[2], t[3], 1)
    b:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
  end
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  fs:SetText(text)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetTexture(C.TEX_WHITE)
  hl:SetVertexColor(1, 1, 1, 0.08)
  b:SetScript("OnClick", onClick)
  btnText[b] = fs
  return b
end

local function SetButtonEnabled(b, on)
  if on then b:Enable() else b:Disable() end
  local fs = btnText[b]
  if fs then
    local c = on and C.COLORS.value or C.COLORS.dim
    fs:SetTextColor(c[1], c[2], c[3])
  end
end

---------------------------------------------------------------------------
-- Row pool
---------------------------------------------------------------------------

-- Level row tooltip: the zones of that level with the exclusions applied (the
-- viewed character only, requirement B), then the approximation notes.
local function OnRowEnter(self)
  local tip = rowTip[self]
  if not tip or not tip.active then return end
  local char = ViewChar()
  if not char then return end
  local Stats = ns.Stats
  local COLORS = C.COLORS
  local acc, lab, val = COLORS.accent, COLORS.label, COLORS.value
  local tt = GameTooltip
  tt:SetOwner(self, "ANCHOR_RIGHT")
  tt:SetText(format(L.TT_LEVEL_ROW_FMT, tip.level))
  local levels = char.levels
  local lb = type(levels) == "table" and levels[tip.level] or nil
  local zones = type(char.zones) == "table" and char.zones or nil
  local _, n = Stats.TopZones(lb and lb.z, TIP_ZONES, ns.GetMask(), tipZoneRows)
  n = tonumber(n) or 0
  tt:AddLine(format(L.ROW_ZONES_FMT, tip.level), acc[1], acc[2], acc[3])
  if n == 0 then
    tt:AddLine(L.ROW_ZONES_EMPTY, lab[1], lab[2], lab[3])
  end
  for i = 1, n do
    local r = tipZoneRows[i]
    local name = Stats.ZoneName(r.key, zones and zones[r.key])
    if r.isCity then name = name .. " " .. L.CITY_MARK end
    tt:AddDoubleLine(name, DurText(r.filtered), lab[1], lab[2], lab[3], val[1], val[2], val[3])
  end
  if tip.partial then tt:AddLine(L.ROW_PARTIAL_TIP, 1, 1, 1, true) end
  if tip.rec then tt:AddLine(L.ROW_REC_TIP, 1, 1, 1, true) end
  if tip.est > 0 then tt:AddLine(format(L.ROW_EST_TIP_FMT, Fmt.Duration(tip.est)), 1, 1, 1, true) end
  if tip.gap > 0 then tt:AddLine(format(L.ROW_GAP_TIP_FMT, Fmt.Duration(tip.gap)), 1, 1, 1, true) end
  tt:Show()
end

local function OnRowLeave(self)
  if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end

local function NewRow(i)
  local row = CreateFrame("Frame", nil, content)
  row:SetSize(CONTENT_W, ROW_H)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
  row:EnableMouse(true)
  row:SetScript("OnEnter", OnRowEnter)
  row:SetScript("OnLeave", OnRowLeave)
  if i % 2 == 0 then
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(row)
    bg:SetTexture(C.TEX_WHITE)
    bg:SetVertexColor(1, 1, 1, 0.03)
  end
  rows[i] = row
  rowCells[row] = {}
  rowTip[row] = { active = false, level = 0, partial = false, rec = false, est = 0, gap = 0 }
  return row
end

local function GetCell(row, c)
  local cells = rowCells[row]
  local fs = cells[c]
  if not fs then
    fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWordWrap(false)
    cells[c] = fs
  end
  return fs
end

local function ApplyRowLayout(row, layout)
  if rowLayout[row] == layout then return end
  rowLayout[row] = layout
  local cells = rowCells[row]
  for c = 1, #layout do
    local col = layout[c]
    local fs = GetCell(row, c)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
    fs:SetWidth(col.w)
    fs:SetJustifyH(col.j)
    fs:Show()
  end
  for c = #layout + 1, #cells do
    cells[c]:SetText("")
    cells[c]:Hide()
  end
end

local function SetCell(row, c, text, color)
  local fs = rowCells[row][c]
  fs:SetText(text or "")
  color = color or C.COLORS.value
  fs:SetTextColor(color[1], color[2], color[3])
end

local function BeginRows()
  nUsed = 0
  emptyFS:Hide()
  liveLevelRow, liveSessionRow = nil, nil
end

local function NextRow(layout)
  nUsed = nUsed + 1
  local row = rows[nUsed] or NewRow(nUsed)
  ApplyRowLayout(row, layout)
  rowTip[row].active = false
  row:Show()
  return row
end

local function EndRows()
  for i = nUsed + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math_max(1, nUsed * ROW_H))
end

local function Section(text)
  local row = NextRow(LAYOUTS.section)
  SetCell(row, 1, text, C.COLORS.accent)
end

local function ShowEmpty(text)
  emptyFS:SetText(text)
  emptyFS:Show()
end

---------------------------------------------------------------------------
-- Tab builders (allocation allowed: UI rebuild on data events only)
---------------------------------------------------------------------------

local function BuildAccountLevels(mask)
  local out, n = ns.Stats.AccountLevelAverages(ns.db, mask, accountRows)
  out = out or accountRows
  n = n or #out
  for i = 1, n do
    local r = out[i]
    local row = NextRow(LAYOUTS.account)
    SetCell(row, 1, IntText(r.level))
    SetCell(row, 2, IntText(r.n))
    SetCell(row, 3, r.avg and Fmt.Duration(r.avg) or DASH)
    SetCell(row, 4, r.xph and Fmt.Rate(r.xph) or DASH)
  end
  if n == 0 then ShowEmpty(L.NO_DATA) end
end

local function BuildLevels(char, mask, now)
  if not char then return BuildAccountLevels(mask) end
  local isCur = (char == ns.char)
  local sync = isCur and ns.Tracker.GetSync() or nil
  local out, n = ns.Stats.LevelHistory(char, mask, sync, now, levelRows)
  out = out or levelRows
  n = tonumber(n) or #out
  local COLORS = C.COLORS
  for i = 1, n do
    local r = out[i]
    local est = tonumber(r.est) or 0
    local gap = tonumber(r.gap) or 0
    local approx = (r.partial or r.rec or est > 0 or gap > 0) and true or false
    local row = NextRow(LAYOUTS.levels)
    SetCell(row, 1, IntText(r.level), r.current and COLORS.accent or nil)
    SetCell(row, 2, TimeText(r.filtered, approx))
    SetCell(row, 3, r.server and Fmt.Duration(r.server) or DASH, COLORS.label)
    SetCell(row, 4, r.xph and Fmt.Rate(r.xph) or DASH)
    SetCell(row, 5, DurText(r.afk), COLORS.label)
    SetCell(row, 6, DurText(r.inn), COLORS.label)
    SetCell(row, 7, DurText(r.city), COLORS.label)
    SetCell(row, 8, DurText(r.inst), COLORS.label)
    local mz = r.mainZone
    if not (r.mainZoneKey ~= nil and type(mz) == "string") then mz = ZoneNameOf(char, mz) end
    SetCell(row, 9, mz, COLORS.label)
    if r.current then
      SetCell(row, 10, L.ROW_IN_PROGRESS, COLORS.accent)
    else
      SetCell(row, 10, r.reachedAt and Fmt.Date(r.reachedAt) or DASH, COLORS.label)
    end
    local tip = rowTip[row]
    tip.level = math_floor(tonumber(r.level) or 0)
    tip.partial = r.partial and true or false
    tip.rec = r.rec and true or false
    tip.est, tip.gap = est, gap
    tip.active = true                 -- zones of the level (+ notes when approx)
    if r.current and isCur then
      liveLevelRow, liveLevel, liveApprox = row, tip.level, approx
      liveLevelKey = Fmt.DurationKey(r.filtered or 0)
    end
  end
  if n == 0 then ShowEmpty(L.NO_DATA) end
end

-- Continents block (same columns as the zones list): time counted under the
-- exclusions, raw time, AFK part (raw minus the time counted without AFK). Continents
-- whose time is all excluded come last with a dash, like the zones below.
local function AddContinentRow(r, filtered)
  local COLORS = C.COLORS
  local raw = contRaw[r.key] or 0
  local row = NextRow(LAYOUTS.zones)
  SetCell(row, 1, r.name)
  SetCell(row, 2, DurText(filtered))
  SetCell(row, 3, DurText(raw), COLORS.label)
  SetCell(row, 4, DurText(raw - (contNoAfk[r.key] or 0)), COLORS.label)
  SetCell(row, 5, "", COLORS.label)
  contListed[r.key] = true
end

local function BuildContinents(zoneMap, mask)
  local Stats = ns.Stats
  local nr = Stats.Continents(zoneMap, 0, contRawRows) or 0
  if nr <= 0 then return 0 end
  local nf = Stats.Continents(zoneMap, mask, contRows) or 0
  local na = Stats.Continents(zoneMap, C.MASK_AFK, contNoAfkRows) or 0
  wipe(contRaw); wipe(contNoAfk); wipe(contListed)
  for i = 1, nr do
    local r = contRawRows[i]
    contRaw[r.key] = r.secs
  end
  for i = 1, na do
    local r = contNoAfkRows[i]
    contNoAfk[r.key] = r.secs
  end
  Section(L.SECTION_CONTINENTS)
  for i = 1, nf do
    local r = contRows[i]
    AddContinentRow(r, r.secs)
  end
  for i = 1, nr do
    local r = contRawRows[i]
    if not contListed[r.key] then AddContinentRow(r, 0) end
  end
  return nr
end

-- Most played instances (same columns as the zones list): time counted under the
-- exclusions, raw instance time, AFK part, XP; the kind (dungeon, raid, PvP) follows
-- the name. Nothing when no instance was played.
local function BuildInstances(char, zoneMap, mask)
  local n = ns.Stats.TopInstances(zoneMap, mask, INST_ROWS, instRows)
  if n <= 0 then return 0 end
  local COLORS = C.COLORS
  Section(L.INSTANCES_HEADER)
  for i = 1, n do
    local r = instRows[i]
    local bucket = zoneMap[r.key]
    local raw = InstSecs(bucket, 0)
    local kindKey = KIND_KEY[r.kind]
    local name = r.name or ZoneNameOf(char, r.key)
    if kindKey then name = format(L.INST_ROW_FMT, name, L[kindKey]) end
    local xp = type(bucket) == "table" and tonumber(bucket.xp) or 0
    local row = NextRow(LAYOUTS.zones)
    SetCell(row, 1, name)
    SetCell(row, 2, DurText(r.secs))
    SetCell(row, 3, DurText(raw), COLORS.label)
    SetCell(row, 4, DurText(raw - InstSecs(bucket, C.MASK_AFK)), COLORS.label)
    SetCell(row, 5, xp > 0 and Fmt.Number(xp) or DASH, COLORS.label)
  end
  return n
end

local function BuildZones(char, mask)
  local Stats = ns.Stats
  local zoneMap
  if char then
    zoneMap = char.zones or accountZones
  else
    zoneMap = Stats.AccountZones(ns.db, accountZones) or accountZones
  end
  local COLORS = C.COLORS

  -- continents block first (Kalimdor, Eastern Kingdoms, instances, other), then the
  -- most played instances
  local ncont = BuildContinents(zoneMap, mask)
  local ninst = BuildInstances(char, zoneMap, mask)

  -- capitals block: same columns as the list below (time still counted under the
  -- exclusions | raw city time | AFK part)
  local cities, nc = Stats.TopCities(zoneMap, CITY_ROWS, cityRows)
  cities = cities or cityRows
  nc = tonumber(nc) or #cities
  if nc > 0 then
    local inc = C.INCLUDED[mask] or C.INCLUDED[0]
    Section(L.CITIES_HEADER)
    for i = 1, nc do
      local r = cities[i]
      local bucket = zoneMap[r.key]
      local s = type(bucket) == "table" and bucket.s or nil
      local counted = s and (((inc.c and s.c) or 0) + ((inc.C and s.C) or 0)) or 0
      local row = NextRow(LAYOUTS.zones)
      SetCell(row, 1, r.name or ZoneNameOf(char, r.key))
      SetCell(row, 2, DurText(counted))
      SetCell(row, 3, DurText(r.total), COLORS.label)
      SetCell(row, 4, DurText(r.afk), COLORS.label)
      SetCell(row, 5, "", COLORS.label)
    end
  end

  local zones, nz = Stats.TopZones(zoneMap, ZONE_ROWS, mask, zoneRows)
  zones = zones or zoneRows
  nz = tonumber(nz) or #zones
  if nz > 0 then
    if nc > 0 or ncont > 0 or ninst > 0 then Section(L.TAB_ZONES) end
    for i = 1, nz do
      local r = zones[i]
      local name = r.name or ZoneNameOf(char, r.key)
      if r.isCity then name = name .. " " .. L.CITY_MARK end
      local xp = tonumber(r.xp)
      if not xp then
        local bucket = zoneMap[r.key]
        xp = bucket and tonumber(bucket.xp) or 0
      end
      local row = NextRow(LAYOUTS.zones)
      SetCell(row, 1, name)
      SetCell(row, 2, DurText(r.filtered))
      SetCell(row, 3, DurText(r.raw), COLORS.label)
      SetCell(row, 4, DurText(r.afk), COLORS.label)
      SetCell(row, 5, xp > 0 and Fmt.Number(xp) or DASH, COLORS.label)
    end
  end
  if ncont + ninst + nc + nz == 0 then ShowEmpty(L.NO_DATA) end
end

-- "42.3": level + tenths of progress (p clamped below 1 so 42.10 never appears).
local function LevelText(l, p)
  l = tonumber(l)
  if not l then return DASH end
  p = tonumber(p) or 0
  if p < 0 then p = 0 elseif p > 0.99 then p = 0.99 end
  return Fmt.LevelProgress(math_floor(l), p)
end

local function BuildSessions(char, mask)
  if not char then
    ShowEmpty(L.NO_SESSIONS_ACCOUNT)
    return
  end
  local isCur = (char == ns.char)
  local out, n = ns.Stats.SessionHistory(char, mask, sessionRows)
  out = out or sessionRows
  n = tonumber(n) or #out
  local COLORS = C.COLORS
  for i = 1, n do
    local r = out[i]
    local row = NextRow(LAYOUTS.sessions)
    SetCell(row, 1, r.t0 and Fmt.DateTime(r.t0) or DASH, r.current and COLORS.accent or COLORS.label)
    SetCell(row, 2, Fmt.Duration(r.dur or 0))
    local l1, p1 = r.l1, r.p1
    if r.current and isCur then
      -- the in-progress session ends "now": current level and XP fraction
      local lvl, xp, max, _, valid = ns.Tracker.GetXPInfo()
      if valid and type(xp) == "number" and type(max) == "number" and max > 0 then
        l1, p1 = l1 or lvl, xp / max
      end
    end
    if l1 == nil then l1, p1 = r.l0, r.p0 end
    SetCell(row, 3, format(L.RANGE_FMT, LevelText(r.l0, r.p0), LevelText(l1, p1)), COLORS.label)
    SetCell(row, 4, (r.xp and r.xp > 0) and Fmt.Number(r.xp) or DASH)
    SetCell(row, 5, r.xph and Fmt.Rate(r.xph) or DASH)
    SetCell(row, 6, DurText(r.afk), COLORS.label)
    SetCell(row, 7, DurText(r.inst), COLORS.label)
    if r.current and isCur and not liveSessionRow then
      liveSessionRow = row
      liveSessionKey = Fmt.DurationKey(r.dur or 0)
    end
  end
  if n == 0 then ShowEmpty(L.NO_DATA) end
end

---------------------------------------------------------------------------
-- Header, footer
---------------------------------------------------------------------------

local function ByLastSeen(a, b)
  local ra, rb = sortChars[a], sortChars[b]
  local la = ra and tonumber(ra.lastSeen) or 0
  local lb = rb and tonumber(rb.lastSeen) or 0
  if la ~= lb then return la > lb end
  return a < b
end

local function BuildViewList()
  wipe(viewList)
  viewList[1] = VIEW_CURRENT
  local cur = CurrentGuid()
  local chars = ns.db and ns.db.chars
  wipe(otherList)
  if chars then
    for guid in pairs(chars) do
      if guid ~= cur and type(guid) == "string" then
        otherList[#otherList + 1] = guid
      end
    end
    sortChars = chars
    table_sort(otherList, ByLastSeen)       -- most recently seen first
    sortChars = nil
  end
  for i = 1, #otherList do viewList[i + 1] = otherList[i] end
  viewList[#viewList + 1] = VIEW_ACCOUNT
end

local function ViewLabel(char)
  if not char then return L.VIEW_ACCOUNT end
  return format(L.CHAR_FMT, Util.CharName(char), math_floor(tonumber(char.level) or 0))
end

local function UpdateHeader(char, mask)
  BuildViewList()
  viewFS:SetText(ViewLabel(char))
  local excl = ns.Stats.MaskLabel(mask)
  filterFS:SetText(excl and format(L.WIN_FILTER_FMT, excl) or "")
  if curTab == "levels" and char then hintFS:Show() else hintFS:Hide() end
  local multi = #viewList > 1
  SetButtonEnabled(prevBtn, multi)
  SetButtonEnabled(nextBtn, multi)
  SetButtonEnabled(eraseBtn, char ~= nil and not ns.readOnly)
  local COLORS = C.COLORS
  for i = 1, #TAB_ORDER do
    local id = TAB_ORDER[i]
    local fs = btnText[tabBtns[id]]
    local c = (id == curTab) and COLORS.accent or COLORS.label
    fs:SetTextColor(c[1], c[2], c[3])
  end
  local layout
  if curTab == "levels" then
    layout = char and LAYOUTS.levels or LAYOUTS.account
  elseif curTab == "zones" then
    layout = LAYOUTS.zones
  else
    layout = LAYOUTS.sessions
  end
  if curTab == "sessions" and not char then layout = LAYOUTS.section end
  for c = 1, MAX_COLS do
    local fs = headerFS[c]
    local col = layout[c]
    if col and col.key then
      fs:ClearAllPoints()
      fs:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", col.x, 4)
      fs:SetWidth(col.w)
      fs:SetJustifyH(col.j)
      fs:SetText(L[col.key])
      fs:Show()
    else
      fs:SetText("")
      fs:Hide()
    end
  end
end

-- Instance time of the viewed character (or of every character) under `mask`,
-- appended to the footer when there is any.
local function FooterInst(char, mask)
  local total
  if char then
    total = InstSecs(char.life, mask)
  else
    total = ns.Stats.AccountInstanceTime(ns.db, mask)
  end
  if total <= 0 then return "" end
  return L.SEP .. format(L.FOOTER_INST_FMT, Fmt.Duration(total))
end

local function UpdateFooter(char, mask, now)
  local Stats = ns.Stats
  local accAvg, nChars = Stats.AccountAvgPerLevel(ns.db, mask)
  nChars = math_floor(tonumber(nChars) or 0)
  if not accAvg or nChars <= 0 then
    footer2:SetText(L.FOOTER_ACCOUNT_NONE)
  else
    footer2:SetText(format(nChars == 1 and L.FOOTER_ACCOUNT_ONE_FMT or L.FOOTER_ACCOUNT_FMT,
      Fmt.Duration(accAvg), nChars))
  end
  if char then
    local sync = (char == ns.char) and ns.Tracker.GetSync() or nil
    local overall = Stats.AvgPerLevel(char, mask, sync, now)
    local recent, count = Stats.RecentAvg(char, mask, C.RECENT_LEVELS)
    local total = Stats.Played(char, mask, sync, now) or 0
    liveTotalKey = Fmt.DurationKey(total)
    footer1:SetText(format(L.FOOTER_FMT,
      overall and Fmt.Duration(overall) or L.DOTS,
      math_floor(recent and tonumber(count) or C.RECENT_LEVELS),
      recent and Fmt.Duration(recent) or L.DOTS,
      Fmt.Duration(total)) .. FooterInst(char, mask))
  else
    local filtered, _, n = Stats.Account(ns.db, mask)
    n = math_floor(tonumber(n) or 0)
    liveTotalKey = -1
    footer1:SetText(format(n == 1 and L.TT_ACCOUNT_ONE_FMT or L.TT_ACCOUNT_FMT, n) .. L.SEP
      .. Fmt.Duration(filtered or 0) .. FooterInst(nil, mask))
  end
end

---------------------------------------------------------------------------
-- Live cells (every C.WINDOW_ROW_REFRESH ticks; strings only when a key changed)
---------------------------------------------------------------------------

local function UpdateLiveCells()
  if view ~= VIEW_CURRENT then return end
  local char = ns.char
  if not char then return end
  local Stats = ns.Stats
  local mask = ns.GetMask()
  local now = GetTime()
  local sync = ns.Tracker.GetSync()
  if liveLevelRow then
    local filtered = Stats.LevelTime(char, liveLevel, mask, sync, now) or 0
    local key = Fmt.DurationKey(filtered)
    if key ~= liveLevelKey then
      liveLevelKey = key
      SetCell(liveLevelRow, 2, TimeText(filtered, liveApprox))
    end
  end
  if liveSessionRow then
    local session = ns.Tracker.GetSession()
    if session then
      local d = Stats.SessionTime(session, mask) or 0
      local key = Fmt.DurationKey(d)
      if key ~= liveSessionKey then
        liveSessionKey = key
        SetCell(liveSessionRow, 2, Fmt.Duration(d))
      end
    end
  end
  local total = Stats.Played(char, mask, sync, now) or 0
  if Fmt.DurationKey(total) ~= liveTotalKey then
    UpdateFooter(char, mask, now)
  end
end

---------------------------------------------------------------------------
-- Message handlers (registered only while shown)
---------------------------------------------------------------------------

local function OnTick()
  sinceRebuild = sinceRebuild + 1
  tickCount = tickCount + 1
  if tickCount < C.WINDOW_ROW_REFRESH then return end
  tickCount = 0
  if dirty and sinceRebuild >= DIRTY_REBUILD_TICKS then
    Window.Refresh()
  else
    UpdateLiveCells()
  end
end

local function OnData()
  Window.Refresh()
end

local function OnXPChanged()
  -- only the current character's rows and the account totals depend on our XP;
  -- coalesced: rebuilt at a live-cell step, at most every DIRTY_REBUILD_TICKS
  if view ~= VIEW_CURRENT and view ~= VIEW_ACCOUNT then return end
  dirty = true
end

local function OnSettingsChanged(_, path)
  if EXCLUDE_PATHS[path] then Window.Refresh() end
end

local function Activate()
  if listening then return end
  listening = true
  tickCount = 0
  ns.RegisterMessage("TICK", Window, OnTick)
  ns.RegisterMessage("LEVEL_UP", Window, OnData)
  ns.RegisterMessage("PLAYED_SYNCED", Window, OnData)
  ns.RegisterMessage("SESSION_RESET", Window, OnData)
  ns.RegisterMessage("DB_SWAPPED", Window, OnData)
  ns.RegisterMessage("CHAR_RESET", Window, OnData)
  ns.RegisterMessage("SETTINGS_CHANGED", Window, OnSettingsChanged)
  ns.RegisterMessage("XP_CHANGED", Window, OnXPChanged)
end

local function Deactivate()
  if not listening then return end
  listening = false
  ns.UnregisterMessage("TICK", Window)
  ns.UnregisterMessage("LEVEL_UP", Window)
  ns.UnregisterMessage("PLAYED_SYNCED", Window)
  ns.UnregisterMessage("SESSION_RESET", Window)
  ns.UnregisterMessage("DB_SWAPPED", Window)
  ns.UnregisterMessage("CHAR_RESET", Window)
  ns.UnregisterMessage("SETTINGS_CHANGED", Window)
  ns.UnregisterMessage("XP_CHANGED", Window)
  local owner = GameTooltip:GetOwner()
  if owner and rowTip[owner] then GameTooltip:Hide() end
end

---------------------------------------------------------------------------
-- Frame scripts / buttons (created once)
---------------------------------------------------------------------------

local function StepView(delta)
  BuildViewList()
  local n = #viewList
  local idx = 1
  for i = 1, n do
    if viewList[i] == view then idx = i end
  end
  idx = idx + delta
  if idx < 1 then idx = n elseif idx > n then idx = 1 end
  view = viewList[idx]
  Window.Refresh()
end

local function OnPrev() StepView(-1) end
local function OnNext() StepView(1) end

local function OnErase()
  if view == VIEW_ACCOUNT or ns.readOnly then return end
  local guid = (view == VIEW_CURRENT) and CurrentGuid() or view
  if guid and ns.Options and ns.Options.ConfirmErase then ns.Options.ConfirmErase(guid) end
end

local tabOfButton = {}
local function OnTabClick(self)
  local id = tabOfButton[self]
  if id and id ~= curTab then
    curTab = id
    Window.Refresh()
  end
end

local function OnFrameShow()
  Activate()
end

local function OnFrameHide()
  Deactivate()
end

local function OnDragStart(self) self:StartMoving() end
local function OnDragStop(self) self:StopMovingOrSizing() end

local function Create()
  frame = CreateFrame("Frame", "TruePlayedStatsFrame", UIParent, "BackdropTemplate")
  frame:Hide()
  frame:SetSize(WIN_W, WIN_H)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  if frame.SetBackdrop then
    frame:SetBackdrop(WIN_BACKDROP)
    local bg, bd = C.COLORS.bg, C.COLORS.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], 0.95)
    frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
  end
  frame:SetScript("OnDragStart", OnDragStart)
  frame:SetScript("OnDragStop", OnDragStop)
  frame:SetScript("OnShow", OnFrameShow)
  frame:SetScript("OnHide", OnFrameHide)
  tinsert(UISpecialFrames, "TruePlayedStatsFrame")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
  title:SetText(L.WIN_TITLE)
  local lc = C.COLORS.label
  filterFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  filterFS:SetPoint("LEFT", title, "RIGHT", 12, 0)
  filterFS:SetTextColor(lc[1], lc[2], lc[3])

  -- view selector: < label >   and Erase...
  prevBtn = MakeButton(frame, "<", 22, 20, OnPrev)
  prevBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -34)
  viewFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  viewFS:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
  viewFS:SetWidth(300)
  viewFS:SetJustifyH("CENTER")
  nextBtn = MakeButton(frame, ">", 22, 20, OnNext)
  nextBtn:SetPoint("LEFT", viewFS, "RIGHT", 8, 0)
  eraseBtn = MakeButton(frame, L.WIN_ERASE, 96, 20, OnErase)
  eraseBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -34)

  -- tabs (plain buttons)
  local x = 12
  for i = 1, #TAB_ORDER do
    local id = TAB_ORDER[i]
    local b = MakeButton(frame, L[TAB_KEY[id]], 100, 20, OnTabClick)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -62)
    tabBtns[id] = b
    tabOfButton[b] = id
    x = x + 104
  end
  hintFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hintFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -66)
  hintFS:SetJustifyH("RIGHT")
  hintFS:SetTextColor(lc[1], lc[2], lc[3])
  hintFS:SetText(L.LEVELS_HOVER_HINT)

  -- scrolling body
  scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -106)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 50)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_W, 1)
  scroll:SetScrollChild(content)

  for c = 1, MAX_COLS do
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetTextColor(lc[1], lc[2], lc[3])
    fs:SetWordWrap(false)
    headerFS[c] = fs
  end

  emptyFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyFS:SetPoint("CENTER", scroll, "CENTER", 0, 0)
  emptyFS:Hide()

  footer1 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer1:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 28)
  footer1:SetJustifyH("LEFT")
  footer2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer2:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
  footer2:SetJustifyH("LEFT")
  footer2:SetTextColor(lc[1], lc[2], lc[3])

  -- Read-only handles for the offline tests (our own frame).
  frame.tp = { viewText = viewFS, prev = prevBtn, next = nextBtn, erase = eraseBtn, tabs = tabBtns,
               footer1 = footer1, footer2 = footer2, empty = emptyFS, rows = rows, cells = rowCells,
               header = headerFS, filter = filterFS, hint = hintFS }
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Window.IsShown()
  return frame ~= nil and frame:IsShown() and true or false
end

-- Full rebuild of the visible tab (data events, tab/view change).
function Window.Refresh()
  if not frame or not frame:IsShown() or not ns.char then return end
  dirty = false
  sinceRebuild = 0
  local char = ViewChar()
  local mask = ns.GetMask()
  local now = GetTime()
  UpdateHeader(char, mask)
  BeginRows()
  if curTab == "levels" then
    BuildLevels(char, mask, now)
  elseif curTab == "zones" then
    BuildZones(char, mask)
  else
    BuildSessions(char, mask)
  end
  EndRows()
  UpdateFooter(char, mask, now)
end

function Window.SetView(v)
  if v == nil or v == VIEW_CURRENT or v == CurrentGuid() then
    view = VIEW_CURRENT
  elseif v == VIEW_ACCOUNT then
    view = VIEW_ACCOUNT
  else
    local chars = ns.db and ns.db.chars
    view = (chars and chars[v]) and v or VIEW_CURRENT
  end
  Window.Refresh()
end

function Window.Show(tab, v)
  if not ns.ready or not ns.char then return end
  if not frame then Create() end
  curTab = (tab and TAB_KEY[tab]) and tab or "levels"
  view = VIEW_CURRENT                   -- requirement B: reset at every Show
  if v ~= nil then
    if v == VIEW_ACCOUNT then
      view = VIEW_ACCOUNT
    elseif v ~= CurrentGuid() and ns.db and ns.db.chars and ns.db.chars[v] then
      view = v
    end
  end
  frame:Show()
  Activate()
  Window.Refresh()
end

function Window.Hide()
  if frame then frame:Hide() end
  Deactivate()
end

function Window.Toggle(tab)
  if Window.IsShown() then
    if tab and TAB_KEY[tab] and tab ~= curTab then
      curTab = tab
      Window.Refresh()
    else
      Window.Hide()
    end
  else
    Window.Show(tab)
  end
end
