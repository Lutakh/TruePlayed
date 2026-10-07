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
-- Columns (lot 8): each tab lists its columns; an optional column is shown only when a
-- row of the current view has a value in it (Inst., Inn, City, AFK, Dead, Est., Prof.,
-- ...), and the visible ones are laid out again (EndRows) from their fixed widths, the
-- flexible column (main zone, zone) taking the room left. The window is as wide as its
-- columns need, at least the size saved in the settings (window.width / height); the
-- grip in the bottom-right corner resizes it and saves the size.
-- Levels tab: a row is the time spent AT a level, labelled "19 » 20" (from 19 to 20);
-- Reached = when the next level was reached, Total = the time from level 1 to that
-- moment (Stats.CumulativeTime), Est. = the time to level estimated when the level
-- began, Dead = time dead or a ghost with the deaths of the level ("5m (2)"). Inst. is
-- the time spent in instances (dungeons, raids, PvP) counted under the exclusions, like
-- the time column; the footer adds the instance total when there is one. Dates follow
-- the settings window.dateFmt and window.clock (Fmt.DateTime).
-- Continents with less than C.CONT_MIN_SECS of total time are not listed.
-- Column help: every column header is followed by a small circled "?" (the addon's
-- Media/Themes/common/help.tga, tinted ui.dim, ui.accent while hovered); hovering the
-- header cell (an invisible frame the width of the column, the only mouse-enabled part of
-- the header) shows the column name and what it holds (locale key col.tip) in the
-- GameTooltip. The cells and icons are created with their header FontString, placed again
-- only when the layout changes, and recoloured by Window.ApplyTheme.
-- Requirement B: the view is the current character unless the user picks another
-- character or the account view; every Show resets it to the current character.
-- Themes (SPEC-themes 4.6): Window.ApplyTheme sets the backdrop colours and the title
-- font (display role, same size) at creation and on THEME_CHANGED "theme" (the `ui` roles
-- never follow the user's XP / rested colours: a recolour changes nothing here); the
-- cells keep their GameFont* objects and read the `ui` colours of the active theme when
-- they are filled.

local math_floor, math_max = math.floor, math.max
local type, pairs, tonumber, setmetatable = type, pairs, tonumber, setmetatable
local table_sort = table.sort
local format, wipe, tinsert = format, wipe, tinsert
local CreateFrame, UIParent, GetTime = CreateFrame, UIParent, GetTime

local Window = {}
ns.Window = Window

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local WIN_W, WIN_H = C.WINDOW_MIN_W, 440   -- minimum width, default height (settings window.*)
local MARGIN_W = 50                -- frame width - content width (insets, scroll bar)
local ROW_H = 16
local GAP = 4                      -- between two columns
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
local GRIP_TEX = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"
-- Column help icon (Themes.COMMON_MEDIA.help, 32 x 32 white art tinted at fill time),
-- drawn ICON_GAP after the header text; a header text has the column width minus
-- ICON_ROOM, so the icon always stays inside its column.
local HELP_TEX = "Interface\\AddOns\\" .. (ns.ADDON or ADDON or "TruePlayed") .. "\\Media\\Themes\\common\\help.tga"
local ICON_SIZE, ICON_GAP = 10, 2
local ICON_ROOM = ICON_GAP + ICON_SIZE
local HEADER_H = 16                -- height of a header cell (the mouse area of a column header)
local TIP_TEXT = { 1, 0.82, 0 }    -- explanation lines of a header tooltip (the game's normal gold)

local TAB_ORDER = { "levels", "zones", "sessions" }
local TAB_KEY = { levels = "TAB_LEVELS", zones = "TAB_ZONES", sessions = "TAB_SESSIONS" }
local KIND_KEY = { d = "KIND_DUNGEON", r = "KIND_RAID", p = "KIND_PVP" }   -- Stats.TopInstances kinds

-- Columns: id (what the builders fill), locale key of the header, width (the minimum of
-- the flexible column), optional (shown only when a row has a value), flexible, locale key
-- of the header tooltip (default: the header key .. "_TIP"; a column whose meaning differs
-- from one tab to another has its own, COL_<X>_<TAB>_TIP). The widths fit the widest
-- header followed by its help icon (ICON_ROOM) and the widest value of every language
-- (tests/test_locales.lua). Headers are left-justified: the icon follows the text.
local function Col(id, key, w, opt, flex, tip)
  return { id = id, key = key, tip = tip or (key .. "_TIP"), w = w, opt = opt or false, flex = flex or false,
           j = "LEFT", x = 0, cw = w }
end
-- A layout: every column of a tab, the visible ones (cols, set by EndRows), the cell index
-- of each visible id (pos), and a version bumped whenever the placement changes.
local function Layout(all) return { all = all, cols = {}, pos = {}, n = 0, ver = 0, need = 0 } end
local LAYOUTS = {
  levels = Layout({
    Col("level", "COL_LEVEL", 56), Col("time", "COL_TIME", 64), Col("eta", "COL_ETA", 62, true),
    Col("cum", "COL_CUM", 68, true), Col("server", "COL_SERVER", 62, true), Col("xph", "COL_XPH", 52, true),
    Col("afk", "COL_AFK", 58, true), Col("inn", "COL_INN", 58, true), Col("city", "COL_CITY", 58, true),
    Col("inst", "COL_INST", 58, true), Col("dead", "COL_DEAD", 82, true), Col("prof", "COL_PROF", 58, true),
    Col("zone", "COL_MAIN_ZONE", 130, false, true), Col("reached", "COL_REACHED", 100),
  }),
  account = Layout({
    Col("level", "COL_LEVEL", 56), Col("chars", "COL_CHARS", 60), Col("avg", "COL_AVG", 100),
    Col("xph", "COL_XPH", 80, true, false, "COL_XPH_ACCOUNT_TIP"),
  }),
  zones = Layout({   -- instance rows carry their kind after the name: a wide first column
    Col("zone", "COL_ZONE", 240, false, true), Col("time", "COL_TIME", 64, false, false, "COL_TIME_ZONES_TIP"),
    Col("raw", "COL_RAW", 64), Col("afk", "COL_AFK", 64, true), Col("xp", "COL_XP", 76, true),
  }),
  sessions = Layout({
    Col("date", "COL_DATE", 100), Col("dur", "COL_DURATION", 64), Col("levels", "COL_LEVELS", 72),
    Col("xp", "COL_XP", 70, true, false, "COL_XP_SESSIONS_TIP"),
    Col("xph", "COL_XPH", 52, true, false, "COL_XPH_SESSIONS_TIP"), Col("afk", "COL_AFK", 58, true),
    Col("inst", "COL_INST", 58, true), Col("dead", "COL_DEAD", 82, true), Col("prof", "COL_PROF", 58, true),
  }),
  none = Layout({}),               -- the account view of the Sessions tab (a message only)
}
local SECTION = {}                 -- marker layout of the section rows (one cell, full width)

local WIN_BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BTN_BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }

local EXCLUDE_PATHS = { ["exclude.afk"] = true, ["exclude.inn"] = true, ["exclude.city"] = true }
local WINDOW_PATHS = { ["window.width"] = true, ["window.height"] = true, ["window.dateFmt"] = true,
                       ["window.clock"] = true }
local BORDER_ALPHA = C.COLORS.border[4]

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local frame, scroll, content, grip
local viewFS, prevBtn, nextBtn, eraseBtn, emptyFS, footer1, footer2
local filterFS, hintFS             -- active exclusions (header), Levels tab hint
local titleFS, titleSize = nil, 12 -- window title (display font of the theme, GameFontNormal size)
local titleThemed = false          -- the title font was set by a theme (not GameFontNormal)
local tabBtns = {}
local headerFS = {}                -- [c] = header FontString of visible column c
local headerCell = {}              -- [c] = its mouse cell (Frame, the column's width)
local headerIcon = {}              -- [c] = its help icon (Texture of the cell)
local cellIndex = {}               -- [cell] = c
local btnText = {}                 -- [button] = FontString
local rows = {}                    -- pooled row frames
local rowCells = {}                -- [row] = { FontString... }
local rowLayout = {}               -- [row] = applied layout (LAYOUTS.x or SECTION)
local rowVer = {}                  -- [row] = version of that layout when applied
local rowW = {}                    -- [row] = applied width
local rowText = {}                 -- [row] = { [column id] = text } of the build in progress
local rowColor = {}                -- [row] = { [column id] = colour or false (value) }
local rowSection = {}              -- [row] = section title, or false for a data row
local rowTip = {}                  -- [row] = reused tooltip data
local cellText = setmetatable({}, { __mode = "k" })   -- [FontString] = text set (SetText on change)
local cellColor = setmetatable({}, { __mode = "k" })  -- [FontString] = colour set
local used = {}                    -- [column id] = true: a row of this build has a value there
local nUsed = 0

local curTab = "levels"
local curLayout = LAYOUTS.levels   -- layout of the build in progress / shown
local headerLayout, headerVer = nil, -1
local frameW, frameH = WIN_W, WIN_H  -- applied frame size (set on change only)
local contentW = WIN_W - MARGIN_W
local minW = -1                    -- applied resize bound
local view = VIEW_CURRENT
local listening = false
local tickCount = 0
local sinceRebuild = 0             -- ticks since the last full rebuild
local dirty = false                -- XP changed since the last rebuild

-- live cells (current character only)
local liveLevelRow, liveLevel, liveApprox, liveLevelKey = nil, 0, false, -1
local liveCumKey = -1
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

-- `ui` colours of the active theme (accent, label, value, dim...): read at every fill
-- (ReadUI); the classic colours until then or without Themes.
local CLASSIC_UI = { bg = C.COLORS.bg, border = C.COLORS.border, title = C.COLORS.value,
                     accent = C.COLORS.accent, label = C.COLORS.label, value = C.COLORS.value,
                     dim = C.COLORS.dim }
local UI = CLASSIC_UI

local function ReadUI()
  local Themes = ns.Themes
  local th = Themes and Themes.Active()
  local ui = th and th.ui
  UI = (type(ui) == "table") and ui or CLASSIC_UI
  return UI
end

-- Title font: the theme's display role at the GameFontNormal size; a theme whose display
-- font is the game font (Classic) keeps the GameFontNormal object itself, as before
-- themes. Themes.SetFont is told about the switch back so that its cache stays true.
local function ApplyTitleFont()
  local Themes = ns.Themes
  if not Themes then return end
  local th = Themes.Active()
  local fonts = th and th.fonts
  if not fonts or fonts.display == nil or fonts.display == "game" then
    if titleThemed then
      Themes.SetFont(titleFS, "game", titleSize, "none")
      titleFS:SetFontObject(GameFontNormal)
      titleThemed = false
    end
    return
  end
  Themes.SetFont(titleFS, "display", titleSize, "none")
  titleThemed = true
end

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

-- "19 » 20": the row of a level record L holds the time spent at L, until L + 1.
local function LevelSpan(l)
  l = math_floor(tonumber(l) or 0)
  return format(L.RANGE_FMT, IntText(l), IntText(l + 1))
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

-- "5m (2)": time dead and the number of deaths; the count alone without dead time
-- (deaths recorded before this version); a dash for neither.
local function DeadText(sec, deaths)
  sec, deaths = tonumber(sec) or 0, math_floor(tonumber(deaths) or 0)
  if sec <= 0 then return deaths > 0 and format("(%d)", deaths) or DASH end
  return format("%s (%d)", Fmt.Duration(sec), deaths)
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
    local c = on and UI.value or UI.dim
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
  tt:SetText(format(L.LEVEL_SPAN_FMT, tip.level, tip.level + 1))
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
  row:SetSize(contentW, ROW_H)
  rowW[row] = contentW
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
  rowText[row], rowColor[row], rowSection[row] = {}, {}, false
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

-- Text and colour of a cell, each set only when it changed.
local function SetFS(fs, text, color)
  if cellText[fs] ~= text then
    cellText[fs] = text
    fs:SetText(text)
  end
  if cellColor[fs] ~= color then
    cellColor[fs] = color
    fs:SetTextColor(color[1], color[2], color[3])
  end
end

-- Places the cells of a row for `layout` (the visible columns, or one full-width cell for
-- a section row); nothing is done when that placement is already applied.
local function PlaceCells(row, layout)
  if rowW[row] ~= contentW then
    rowW[row] = contentW
    row:SetWidth(contentW)
  end
  local ver = layout == SECTION and contentW or layout.ver
  if rowLayout[row] == layout and rowVer[row] == ver then return end
  rowLayout[row], rowVer[row] = layout, ver
  local cells = rowCells[row]
  local n = 1
  if layout == SECTION then
    local fs = GetCell(row, 1)
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", 0, 0)
    fs:SetWidth(contentW)
    fs:SetJustifyH("LEFT")
    fs:Show()
  else
    n = layout.n
    for c = 1, n do
      local col = layout.cols[c]
      local fs = GetCell(row, c)
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
      fs:SetWidth(col.cw)
      fs:SetJustifyH(col.j)
      fs:Show()
    end
  end
  for c = n + 1, #cells do
    local fs = cells[c]
    cellText[fs] = ""
    fs:SetText("")
    fs:Hide()
  end
end

-- The texts of a row go to its id-keyed table during a build (Put); EndRows writes them
-- into the cells of the visible columns.
local function Put(row, id, text, color)
  rowText[row][id] = text
  rowColor[row][id] = color or false
  if text ~= nil and text ~= "" and text ~= DASH then used[id] = true end
end

-- A live cell (a row already shown): its text, written at once when its column shows.
local function PutLive(row, id, text)
  rowText[row][id] = text
  local c = curLayout.pos[id]
  if c and rowLayout[row] == curLayout then SetFS(rowCells[row][c], text, rowColor[row][id] or UI.value) end
end

local function BeginRows(layout)
  nUsed = 0
  curLayout = layout
  for id in pairs(used) do used[id] = nil end
  emptyFS:Hide()
  liveLevelRow, liveSessionRow = nil, nil
end

local function NextRow()
  nUsed = nUsed + 1
  local row = rows[nUsed] or NewRow(nUsed)
  local texts = rowText[row]
  for id in pairs(texts) do texts[id] = nil end
  rowSection[row] = false
  rowTip[row].active = false
  row:Show()
  return row
end

local function Section(text)
  local row = NextRow()
  rowSection[row] = text
end

-- Visible columns of the build (optional ones with a value), their places and widths, and
-- the frame size: as wide as the columns need, at least the saved size. The version of the
-- layout is bumped when a placement changed (the rows are placed again).
local function LayOut(layout)
  local all, cols, pos = layout.all, layout.cols, layout.pos
  local n, need, changed = 0, 0, false
  for i = 1, #all do
    local col = all[i]
    if not col.opt or used[col.id] then
      n = n + 1
      if cols[n] ~= col then cols[n], changed = col, true end
      need = need + col.w + (n > 1 and GAP or 0)
    end
  end
  for i = #cols, n + 1, -1 do cols[i], changed = nil, true end
  if n ~= layout.n then changed = true end
  layout.n, layout.need = n, need
  for id in pairs(pos) do pos[id] = nil end
  -- frame size: settings, never narrower than the columns
  local ws = ns.settings and ns.settings.window
  local w = math_max(WIN_W, need + MARGIN_W, math_floor(tonumber(ws and ws.width) or WIN_W))
  local h = math_floor(tonumber(ws and ws.height) or WIN_H)
  if w ~= frameW then
    frameW = w
    frame:SetWidth(w)
  end
  if h ~= frameH then
    frameH = h
    frame:SetHeight(h)
  end
  if w - MARGIN_W ~= contentW then
    contentW = w - MARGIN_W
    content:SetWidth(contentW)
  end
  local lo = math_max(WIN_W, need + MARGIN_W)
  if lo ~= minW then
    minW = lo
    if frame.SetResizeBounds then
      frame:SetResizeBounds(lo, C.WINDOW_MIN_H, C.WINDOW_MAX_W, C.WINDOW_MAX_H)
    elseif frame.SetMinResize then
      frame:SetMinResize(lo, C.WINDOW_MIN_H)
      if frame.SetMaxResize then frame:SetMaxResize(C.WINDOW_MAX_W, C.WINDOW_MAX_H) end
    end
  end
  local x = 0
  for c = 1, n do
    local col = cols[c]
    local cw = col.w
    if col.flex then cw = cw + contentW - need end
    if col.x ~= x or col.cw ~= cw then col.x, col.cw, changed = x, cw, true end
    pos[col.id] = c
    x = x + cw + GAP
  end
  if changed then layout.ver = layout.ver + 1 end
end

local function EndRows()
  local layout = curLayout
  LayOut(layout)
  local cols, n = layout.cols, layout.n
  for i = 1, nUsed do
    local row = rows[i]
    local sec = rowSection[row]
    if sec then
      PlaceCells(row, SECTION)
      SetFS(rowCells[row][1], sec, UI.accent)
    else
      PlaceCells(row, layout)
      local texts, colors, cells = rowText[row], rowColor[row], rowCells[row]
      for c = 1, n do
        local id = cols[c].id
        SetFS(cells[c], texts[id] or "", colors[id] or UI.value)
      end
    end
  end
  for i = nUsed + 1, #rows do rows[i]:Hide() end
  content:SetHeight(math_max(1, nUsed * ROW_H))
  frame.tp.layout = layout
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
    local row = NextRow()
    Put(row, "level", LevelSpan(r.level))
    Put(row, "chars", IntText(r.n))
    Put(row, "avg", r.avg and Fmt.Duration(r.avg) or DASH)
    Put(row, "xph", r.xph and Fmt.Rate(r.xph) or DASH)
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
  local COLORS = UI
  local label = COLORS.label
  for i = 1, n do
    local r = out[i]
    local est = tonumber(r.est) or 0
    local gap = tonumber(r.gap) or 0
    local approx = (r.partial or r.rec or est > 0 or gap > 0) and true or false
    local row = NextRow()
    Put(row, "level", LevelSpan(r.level), r.current and COLORS.accent or nil)
    Put(row, "time", TimeText(r.filtered, approx))
    local eta = tonumber(r.eta)
    Put(row, "eta", (eta and eta > 0) and Fmt.Duration(eta) or DASH, label)
    local cum = tonumber(r.cum)
    Put(row, "cum", cum and Fmt.Duration(cum) or DASH, label)
    Put(row, "server", r.server and Fmt.Duration(r.server) or DASH, label)
    Put(row, "xph", r.xph and Fmt.Rate(r.xph) or DASH)
    Put(row, "afk", DurText(r.afk), label)
    Put(row, "inn", DurText(r.inn), label)
    Put(row, "city", DurText(r.city), label)
    Put(row, "inst", DurText(r.inst), label)
    Put(row, "dead", DeadText(r.dead, r.deaths), label)
    Put(row, "prof", DurText(r.prof), label)
    local mz = r.mainZone
    if not (r.mainZoneKey ~= nil and type(mz) == "string") then mz = ZoneNameOf(char, mz) end
    Put(row, "zone", mz, label)
    if r.current then
      Put(row, "reached", L.ROW_IN_PROGRESS, COLORS.accent)
    else
      Put(row, "reached", r.endAt and Fmt.DateTime(r.endAt) or DASH, label)
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
      liveCumKey = Fmt.DurationKey(cum or 0)
    end
  end
  if n == 0 then ShowEmpty(L.NO_DATA) end
end

-- Continents block (same columns as the zones list): time counted under the
-- exclusions, raw time, AFK part (raw minus the time counted without AFK). Continents
-- whose time is all excluded come last with a dash, like the zones below.
local function AddContinentRow(r, filtered)
  local label = UI.label
  local raw = contRaw[r.key] or 0
  local row = NextRow()
  Put(row, "zone", r.name)
  Put(row, "time", DurText(filtered))
  Put(row, "raw", DurText(raw), label)
  Put(row, "afk", DurText(raw - (contNoAfk[r.key] or 0)), label)
  Put(row, "xp", "", label)
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
  -- continents with less than C.CONT_MIN_SECS of total time are left out (the data stays)
  local MIN = C.CONT_MIN_SECS
  local listed = 0
  for i = 1, nr do
    if contRawRows[i].secs >= MIN then listed = listed + 1 end
  end
  if listed == 0 then return 0 end
  Section(L.SECTION_CONTINENTS)
  for i = 1, nf do
    local r = contRows[i]
    if (contRaw[r.key] or 0) >= MIN then AddContinentRow(r, r.secs) end
  end
  for i = 1, nr do
    local r = contRawRows[i]
    if not contListed[r.key] and r.secs >= MIN then AddContinentRow(r, 0) end
  end
  return listed
end

-- Most played instances (same columns as the zones list): time counted under the
-- exclusions, raw instance time, AFK part, XP; the kind (dungeon, raid, PvP) follows
-- the name. Nothing when no instance was played.
local function BuildInstances(char, zoneMap, mask)
  local n = ns.Stats.TopInstances(zoneMap, mask, INST_ROWS, instRows)
  if n <= 0 then return 0 end
  local label = UI.label
  Section(L.INSTANCES_HEADER)
  for i = 1, n do
    local r = instRows[i]
    local bucket = zoneMap[r.key]
    local raw = InstSecs(bucket, 0)
    local kindKey = KIND_KEY[r.kind]
    local name = r.name or ZoneNameOf(char, r.key)
    if kindKey then name = format(L.INST_ROW_FMT, name, L[kindKey]) end
    local xp = type(bucket) == "table" and tonumber(bucket.xp) or 0
    local row = NextRow()
    Put(row, "zone", name)
    Put(row, "time", DurText(r.secs))
    Put(row, "raw", DurText(raw), label)
    Put(row, "afk", DurText(raw - InstSecs(bucket, C.MASK_AFK)), label)
    Put(row, "xp", xp > 0 and Fmt.Number(xp) or DASH, label)
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
  local label = UI.label

  -- continents block first (Kalimdor, Eastern Kingdoms, instances, other), then the
  -- most played instances
  local ncont = BuildContinents(zoneMap, mask)
  local ninst = BuildInstances(char, zoneMap, mask)

  -- capitals block (the most city time first): the same values as their rows in the zone
  -- list below, i.e. the time of the capital counted under the exclusions (raw minus the
  -- excluded parts: with the city excluded, what is left is its flight, professions and
  -- dead time), the raw time and its AFK part
  local cities, nc = Stats.TopCities(zoneMap, CITY_ROWS, cityRows)
  cities = cities or cityRows
  nc = tonumber(nc) or #cities
  if nc > 0 then
    Section(L.CITIES_HEADER)
    for i = 1, nc do
      local r = cities[i]
      local bucket = zoneMap[r.key]
      local row = NextRow()
      Put(row, "zone", r.name or ZoneNameOf(char, r.key))
      Put(row, "time", DurText(Stats.Sum(bucket, mask)))
      Put(row, "raw", DurText(Stats.SumAll(bucket)), label)
      Put(row, "afk", DurText(Stats.SumKeys(bucket, C.AFK_KEYS)), label)
      local xp = type(bucket) == "table" and tonumber(bucket.xp) or 0
      Put(row, "xp", xp > 0 and Fmt.Number(xp) or DASH, label)
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
      local row = NextRow()
      Put(row, "zone", name)
      Put(row, "time", DurText(r.filtered))
      Put(row, "raw", DurText(r.raw), label)
      Put(row, "afk", DurText(r.afk), label)
      Put(row, "xp", xp > 0 and Fmt.Number(xp) or DASH, label)
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
  local COLORS = UI
  local label = COLORS.label
  for i = 1, n do
    local r = out[i]
    local row = NextRow()
    Put(row, "date", r.t0 and Fmt.DateTime(r.t0) or DASH, r.current and COLORS.accent or label)
    Put(row, "dur", Fmt.Duration(r.dur or 0))
    local l1, p1 = r.l1, r.p1
    if r.current and isCur then
      -- the in-progress session ends "now": current level and XP fraction
      local lvl, xp, max, _, valid = ns.Tracker.GetXPInfo()
      if valid and type(xp) == "number" and type(max) == "number" and max > 0 then
        l1, p1 = l1 or lvl, xp / max
      end
    end
    if l1 == nil then l1, p1 = r.l0, r.p0 end
    Put(row, "levels", format(L.RANGE_FMT, LevelText(r.l0, r.p0), LevelText(l1, p1)), label)
    Put(row, "xp", (r.xp and r.xp > 0) and Fmt.Number(r.xp) or DASH)
    Put(row, "xph", r.xph and Fmt.Rate(r.xph) or DASH)
    Put(row, "afk", DurText(r.afk), label)
    Put(row, "inst", DurText(r.inst), label)
    Put(row, "dead", DeadText(r.dead, r.deaths), label)
    Put(row, "prof", DurText(r.prof), label)
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

local function TintIcon(c, color)
  local icon = headerIcon[c]
  if icon then icon:SetVertexColor(color[1], color[2], color[3]) end
end

-- Header tooltip: the column name, then what the column holds (allocation-free: two
-- locale strings). The cell's column is read from the applied header layout.
local function OnHeaderEnter(self)
  local c = cellIndex[self]
  local lay = headerLayout
  local col = c and lay and c <= lay.n and lay.cols[c] or nil
  if not col then return end
  local tt = GameTooltip
  tt:SetOwner(self, "ANCHOR_TOP")
  tt:SetText(L[col.key], 1, 1, 1)
  tt:AddLine(L[col.tip], TIP_TEXT[1], TIP_TEXT[2], TIP_TEXT[3], true)
  tt:Show()
  TintIcon(c, UI.accent)
end

local function OnHeaderLeave(self)
  local c = cellIndex[self]
  if c then TintIcon(c, UI.dim) end
  if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end

-- Column header c (created at Create for the first columns, later on demand): its
-- FontString, and its mouse cell holding the help icon (both hidden until placed).
local function NewHeader(c)
  local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetWordWrap(false)
  local lc = UI.label
  fs:SetTextColor(lc[1], lc[2], lc[3])
  local cell = CreateFrame("Frame", nil, frame)
  cell:Hide()
  cell:EnableMouse(true)
  cell:SetScript("OnEnter", OnHeaderEnter)
  cell:SetScript("OnLeave", OnHeaderLeave)
  local icon = cell:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetTexture(HELP_TEX)
  headerFS[c], headerCell[c], headerIcon[c] = fs, cell, icon
  cellIndex[cell] = c
  TintIcon(c, UI.dim)
  return fs
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
  local COLORS = UI
  for i = 1, #TAB_ORDER do
    local id = TAB_ORDER[i]
    local fs = btnText[tabBtns[id]]
    local c = (id == curTab) and COLORS.accent or COLORS.label
    fs:SetTextColor(c[1], c[2], c[3])
  end
end

-- Column headers of the visible columns (placed again only when the layout changed): the
-- text gets the column width minus ICON_ROOM, the help icon follows the text, and the
-- mouse cell covers the column. A hovered header whose column changed shows the new
-- column's tooltip; a hidden one drops its tooltip.
local function ApplyHeaders(layout)
  if headerLayout == layout and headerVer == layout.ver then return end
  headerLayout, headerVer = layout, layout.ver
  local n = layout.n
  local owner = GameTooltip:GetOwner()
  for c = 1, math_max(n, #headerFS) do
    local fs = headerFS[c]
    local col = c <= n and layout.cols[c] or nil
    if col then
      if fs == nil then fs = NewHeader(c) end
      local room = col.cw - ICON_ROOM
      fs:ClearAllPoints()
      fs:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", col.x, 4)
      fs:SetWidth(room)
      fs:SetJustifyH(col.j)
      fs:SetText(L[col.key])
      fs:Show()
      local tw = fs:GetStringWidth() or 0
      if tw > room then tw = room end
      local icon, cell = headerIcon[c], headerCell[c]
      icon:ClearAllPoints()
      icon:SetPoint("LEFT", fs, "LEFT", tw + ICON_GAP, 0)
      cell:ClearAllPoints()
      cell:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", col.x, 2)       -- the text and the icon
      cell:SetSize(col.cw, HEADER_H)
      cell:Show()
      if owner == cell then OnHeaderEnter(cell) end
    elseif fs ~= nil then
      fs:SetText("")
      fs:Hide()
      local cell = headerCell[c]
      if owner == cell then OnHeaderLeave(cell) end
      cell:Hide()
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
      PutLive(liveLevelRow, "time", TimeText(filtered, liveApprox))
    end
  end
  if liveSessionRow then
    local session = ns.Tracker.GetSession()
    if session then
      local d = Stats.SessionTime(session, mask) or 0
      local key = Fmt.DurationKey(d)
      if key ~= liveSessionKey then
        liveSessionKey = key
        PutLive(liveSessionRow, "dur", Fmt.Duration(d))
      end
    end
  end
  local total = Stats.Played(char, mask, sync, now) or 0
  local totalKey = Fmt.DurationKey(total)
  -- the Total column of the in-progress level: the played total up to now
  if liveLevelRow and totalKey ~= liveCumKey then
    liveCumKey = totalKey
    PutLive(liveLevelRow, "cum", Fmt.Duration(total))
  end
  if totalKey ~= liveTotalKey then
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
  if EXCLUDE_PATHS[path] or WINDOW_PATHS[path] then Window.Refresh() end
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
  if owner and cellIndex[owner] then
    OnHeaderLeave(owner)
  elseif owner and rowTip[owner] then
    GameTooltip:Hide()
  end
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

-- Resize grip (bottom-right corner): the frame is sized by the client while the button is
-- held (no script runs meanwhile); on release the size is saved (window.width / height,
-- clamped by the settings) and the columns are laid out again for it.
local function OnGripDown(_, button)
  if button == "LeftButton" and frame.StartSizing then frame:StartSizing("BOTTOMRIGHT") end
end

local function OnGripUp()
  frame:StopMovingOrSizing()
  local w, h = frame:GetWidth(), frame:GetHeight()
  frameW, frameH = -1, -1             -- the client changed the size: set it again
  local Core = ns.Core
  local changed = false               -- a changed setting refreshes the window (OnSettingsChanged)
  if Core and Core.SetSetting then
    if type(w) == "number" and Core.SetSetting("window.width", math_floor(w + 0.5)) then changed = true end
    if type(h) == "number" and Core.SetSetting("window.height", math_floor(h + 0.5)) then changed = true end
  end
  if not changed then Window.Refresh() end
end

local function Create()
  frame = CreateFrame("Frame", "TruePlayedStatsFrame", UIParent, "BackdropTemplate")
  frame:Hide()
  frame:SetSize(WIN_W, WIN_H)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  if frame.SetResizable then frame:SetResizable(true) end
  frame:SetFrameStrata("DIALOG")
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
  if frame.SetBackdrop then frame:SetBackdrop(WIN_BACKDROP) end
  frame:SetScript("OnDragStart", OnDragStart)
  frame:SetScript("OnDragStop", OnDragStop)
  frame:SetScript("OnShow", OnFrameShow)
  frame:SetScript("OnHide", OnFrameHide)
  tinsert(UISpecialFrames, "TruePlayedStatsFrame")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleFS = title
  local _, size = title:GetFont()             -- the size of GameFontNormal
  titleSize = tonumber(size) or 12
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -12)
  title:SetText(L.WIN_TITLE)
  filterFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  filterFS:SetPoint("LEFT", title, "RIGHT", 12, 0)

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
  hintFS:SetText(L.LEVELS_HOVER_HINT)

  -- scrolling body
  scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -106)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 50)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(contentW, 1)
  scroll:SetScrollChild(content)

  for c = 1, 10 do NewHeader(c) end

  grip = CreateFrame("Button", nil, frame)
  grip:SetSize(16, 16)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture(GRIP_TEX .. "Up")
  grip:SetPushedTexture(GRIP_TEX .. "Down")
  grip:SetHighlightTexture(GRIP_TEX .. "Highlight")
  grip:SetScript("OnMouseDown", OnGripDown)
  grip:SetScript("OnMouseUp", OnGripUp)

  emptyFS = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyFS:SetPoint("CENTER", scroll, "CENTER", 0, 0)
  emptyFS:Hide()

  footer1 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer1:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 28)
  footer1:SetJustifyH("LEFT")
  footer2 = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  footer2:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 12)
  footer2:SetJustifyH("LEFT")

  -- Read-only handles for the offline tests (our own frame).
  frame.tp = { viewText = viewFS, prev = prevBtn, next = nextBtn, erase = eraseBtn, tabs = tabBtns,
               footer1 = footer1, footer2 = footer2, empty = emptyFS, rows = rows, cells = rowCells,
               header = headerFS, headerCells = headerCell, headerIcons = headerIcon, iconRoom = ICON_ROOM,
               layouts = LAYOUTS, filter = filterFS, hint = hintFS, title = titleFS, grip = grip,
               layout = curLayout }

  Window.ApplyTheme()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Window.IsShown()
  return frame ~= nil and frame:IsShown() and true or false
end

-- Theme of the window (SPEC-themes 4.6): backdrop colours (the module keeps its own
-- alphas), the title in the display font at its size, the label colour of the static
-- texts, the dim colour of the header help icons (accent for a hovered one); a shown
-- window is refilled so its cells take the new colours.
function Window.ApplyTheme()
  if not frame then return end
  local ui = ReadUI()
  if frame.SetBackdrop then
    local bg, bd = ui.bg, ui.border
    frame:SetBackdropColor(bg[1], bg[2], bg[3], 0.95)
    frame:SetBackdropBorderColor(bd[1], bd[2], bd[3], BORDER_ALPHA)
  end
  ApplyTitleFont()
  -- the colours kept for the cells are tables of the previous theme: dropped (P5), the
  -- next fill sets every colour again
  for fs in pairs(cellColor) do cellColor[fs] = nil end
  for i = 1, #rows do
    local colors = rowColor[rows[i]]
    for id in pairs(colors) do colors[id] = nil end
  end
  local lc = ui.label
  filterFS:SetTextColor(lc[1], lc[2], lc[3])
  hintFS:SetTextColor(lc[1], lc[2], lc[3])
  footer2:SetTextColor(lc[1], lc[2], lc[3])
  for c = 1, #headerFS do headerFS[c]:SetTextColor(lc[1], lc[2], lc[3]) end
  local owner = GameTooltip:GetOwner()
  for c = 1, #headerIcon do TintIcon(c, owner == headerCell[c] and ui.accent or ui.dim) end
  if frame:IsShown() then Window.Refresh() end
end

-- Full rebuild of the visible tab (data events, tab/view change).
function Window.Refresh()
  if not frame or not frame:IsShown() or not ns.char then return end
  ReadUI()
  dirty = false
  sinceRebuild = 0
  local char = ViewChar()
  local mask = ns.GetMask()
  local now = GetTime()
  UpdateHeader(char, mask)
  local layout
  if curTab == "levels" then
    layout = char and LAYOUTS.levels or LAYOUTS.account
  elseif curTab == "zones" then
    layout = LAYOUTS.zones
  else
    layout = char and LAYOUTS.sessions or LAYOUTS.none
  end
  BeginRows(layout)
  if curTab == "levels" then
    BuildLevels(char, mask, now)
  elseif curTab == "zones" then
    BuildZones(char, mask)
  else
    BuildSessions(char, mask)
  end
  EndRows()
  ApplyHeaders(layout)
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

-- A theme switch while the window exists ("colors": the `ui` roles do not follow the user
-- colours, Themes warns at compile time when a theme makes them).
local function OnThemeChanged(_, _, _, kind)
  if frame and kind ~= "colors" then Window.ApplyTheme() end
end

if ns.RegisterMessage then
  ns.RegisterMessage("THEME_CHANGED", Window, OnThemeChanged)
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
