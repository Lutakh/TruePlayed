local ADDON, ns = ...
local L, C, Fmt = ns.L, ns.C, ns.Fmt

-- LevelChart.lua - the Levels tab of a character in the statistics window ("histogram of
-- the journey"): a row of figure chips, the activity filters, one stacked bar per level,
-- ghost bars for the levels still to play, an average line, the "progress toward level
-- <top>" strip, and the one-shot tooltip helper shared with LevelDetail.lua (the 400 px
-- detail sheet of the selected level, right of the chart). The account view of the tab
-- keeps the window's table (Window.lua).
--
-- Driven by Window.lua only (no subscription here): Build (full rebuild: Window.Refresh of
-- the Levels tab of a character), Live (every C.WINDOW_ROW_REFRESH ticks from the
-- window's live-cell step, current character only), Hide (another tab or view), Reset
-- (every Window.Show: the selection goes back to the viewed character's current level and
-- the filter to "all"; "hide upcoming levels" is kept), ApplyTheme (Window.ApplyTheme),
-- Owns (Window.Deactivate), MinSize (the window is at least 1040 x 640 frame pixels while
-- the chart shows, at most the screen: UIParent less 20 px, a 4:3 or 5:4 screen at UI
-- scale 1 is 1024 or 960 wide; never below the window's own 700 x 300; the saved size is
-- not changed). On a narrower screen the chart column and its plot take what is left
-- beside the 400 px detail sheet (narrower bars, more pill rows).
--
-- Geometry: the root sits inside TruePlayedStatsFrame below the tabs (y = -90) down to
-- above the footers (50 px from the bottom), 14 px from both sides. The chips span the
-- whole root width (seven chips in the chart column alone would be too narrow for the
-- long languages); a chip's sub line that does not fit its chip (PvP, dead, recent or
-- max-level times in a long language) shows its durations by their largest unit only
-- (SubFit: whole days or hours; measured with GetUnboundedStringWidth, as the client
-- bounds GetStringWidth by the width set), the chip's value and tooltip keep them in full;
-- below them, left, the chart column (root width - 400 - 14): the title line (filter title,
-- summary), the filter pills (they wrap to a second row when the language needs it) and
-- the "hide upcoming levels" toggle on the right, the plot (y labels
-- in the AXIS_W px on its left, level numbers below it at 1 and every multiple of 5, or
-- every level when the columns are wide), the progress strip at the bottom; right, the
-- detail sheet (LevelDetail.Show, anchored on the root's top right below the chips).
-- Every region has one anchor and an explicit size computed from the frame size (Layout,
-- again only when the size or the fonts changed).
--
-- Bars: the bar of level L is the time spent AT L (from L to L + 1), for L = 1 .. top - 1
-- (top = Util.MaxLevel(); the time at the max level is a chip, not a bar). A bar stacks
-- the parts of Stats.LevelSegments in the fixed order world, world PvP, dungeon, raid,
-- battlegrounds, flight, professions, dead, city, inn, AFK, untracked, under the user's
-- exclusions (the parts sum to Stats.Sum); the current level adds the difference between
-- Stats.LevelTime (live: the server's level /played) and its local parts to "untracked".
-- A filter keeps only its parts (World: world; Instances: dungeon + raid; PvP: world PvP +
-- battlegrounds; Flight; Professions; Dead) and the scale is computed on the filtered
-- values. Pixel heights use cumulative rounding (a stack is exactly its bar's height). A
-- segment texture is created the first time its part shows in that column; a column's
-- segments are chained (each on the top of the one below) and anchored again only when the
-- set of visible parts changes or the columns are laid out again: live growth is SetHeight
-- only. Levels without a record (before the installation, gaps) show a 2 px dim stub.
-- Under "all" with an estimate (Stats.FutureLevels "ok" or "estimate") and unless hidden,
-- every level up to top - 1 has a column: the levels to play show a ghost bar (ui.dim,
-- 1 px top line) of their estimated time, the current level a ghost of its estimated
-- remaining time on top of its solid part; the current level's solid part has a 1 px
-- ui.accent top line. Scale: the largest bar (ghost included) x 1.06 rounded up to a step
-- of STEPS that needs at most GRID_MAX gridlines, beyond 10 days 20, 50, 100, 200, 500...
-- days (a level parked for months); a label in whole days (L.LV_DAYS_FMT) from a day,
-- else whole hours, else Fmt.Duration; gridlines, their labels and the average
-- line (mean of the shown values of the complete levels, neither partial nor rebuilt, the
-- current one excluded) each sit on an invisible "stalk" texture (Graph.lua's trick): a
-- new scale is SetHeight only.
--
-- Selection: a click on a column selects its level (1 px ui.title frame around the column)
-- and LevelDetail.Show shows it. Hovering a column shows its one-shot tooltip (under a
-- filter first the bar's own value, the filter's parts, with its share of the level, in
-- ui.accent; when only one of the filter's parts has time on that bar, that part's label in
-- its colour and the value in accent, and the part is not listed again below; then the
-- level's time with
-- "~" when partly estimated, the non-zero parts with duration and percent in their colours
-- (a non-zero share under 0.5 % reads "<1%", as on the sheet),
-- deaths, XP per hour, reached date or in progress, the world PvP note under the PvP
-- filter; an upcoming level: its estimate and the XP to earn; no record: why), hovering
-- the PvP chip the PvP split (each battleground without its AFK time, which is in the AFK
-- part: the rows and "Other battlegrounds" make up the battlegrounds line; world PvP, its
-- definition, since when it is measured or "not measured on this client" when ns.Pvp is not
-- available: never shown as 0 then).
--
-- Performance: everything is created lazily at the first Build and pooled (columns up to
-- top - 1, their segments, ghosts, stubs and labels); a second Build creates nothing. Live
-- refreshes the current column, the estimates of the upcoming ones, every chip but the
-- average (Played, server, PvP and its sub line, Flight and its share, Deaths and the dead
-- time, "level <top> in"), the strip and the summary with integer keys (Fmt.DurationKey /
-- ETAKey / whole percents): strings are built only when a key changed, Set* calls only when
-- a value changed, and nothing is allocated otherwise (Stats.LevelSegments, LevelTime,
-- Played and FutureLevels with this module's reused tables do not allocate). A new scale
-- redraws every column (SetHeight only). Tooltips allocate on mouse events only.
--
-- Projection (Stats.FutureLevels): "Level <top> in ~X" (chip) and "~X left" (strip) are
-- the same Fmt.ETA text; "+" after it when some levels to play have no known XP size (its
-- `missing`: the time is a lower bound, and the strip shows no share then). A character
-- whose XP is disabled below the top level (Util.IsMaxLevel, status "max") is not at the
-- max level: "XP disabled" in the chip and the strip, its level in progress, no projection.
-- Another character's server cap is its recorded char.capLevel while it equals its level
-- (the Tracker's rule).
--
-- Tooltip helper (also used by LevelDetail.lua): LevelChart.TipBegin(owner) takes the
-- themed TooltipFrame.Get(1) under a non-native theme, else the GameTooltip, with the
-- theme's tooltip palette (th.tt.colors, Themes.CLASSIC_TT); TipRow(kind, left, right, lc,
-- rc, wrap) adds a row (colours: a palette role name or an { r, g, b } table), TipSep(kind)
-- a separator, TipShow(anchor, point, relPoint, x, y) places and shows it, TipHide(owner)
-- hides it when still ours (any owner when nil). Nothing of the palette is kept after
-- TipShow (P5). Window.Deactivate and every THEME_CHANGED hide it.
--
-- Themes (SPEC-themes 4.6): every text uses the body role of the theme (Themes.SetFont);
-- the colours are copies (components) of the active theme's `ui` roles and of its gauge
-- colours (th.tt.gauge.colors, else Themes.CLASSIC_GAUGE.colors; world PvP = the pvp colour
-- mixed 45 % toward white, untracked = ui.dim), read again by ApplyTheme: no table of a
-- previous compiled theme is kept (P5). The `ui` roles never follow the user colours.
--
-- Test handles: frame.tp.chart = { root, chips, filters, toggle, plot, cols, grid, avg,
-- strip, sel, marker, title, summary, xlabels (cols[k].xl), tip, state, geo, segKeys,
-- filterIds }; a column record holds seg[i] (textures by part index), segH[i], val[i],
-- total, sumAll, est, kind ("done", "cur", "future", "none"), ghost, gline, stub, hit, xl.
-- frame.tp.detail = LevelDetail's own handles.

local math_floor, math_ceil, math_max, math_min = math.floor, math.ceil, math.max, math.min
local type, tonumber, pairs, rawget, setmetatable = type, tonumber, pairs, rawget, setmetatable
local format = string.format
local CreateFrame, GetTime, time, UIParent = CreateFrame, GetTime, time, UIParent

local LevelChart = {}
ns.LevelChart = LevelChart

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local MIN_W, MIN_H = 1040, 640     -- window size while the chart shows (frame pixels)
local SCREEN_MARGIN = 20           -- MinSize: at most the screen (UIParent) less this
local ROOT_X, ROOT_TOP, ROOT_BOTTOM = 14, 90, 50   -- the root inside the window frame
local DETAIL_W, DETAIL_GAP = 400, 14
local NCHIPS = 7
local CHIP_H, CHIP_GAP, CHIP_PAD = 44, 6, 8
local COL_TOP = CHIP_H + 8         -- top of the chart column and of the detail sheet
local TITLE_H = 16
local PILL_H, PILL_GAP, PILL_PAD, PILL_SQ = 18, 4, 6, 8
local AXIS_W = 58                  -- y labels left of the plot: "2 h 30 min" (es, it, pt), ruRU, koKR
local XLAB_H = 14                  -- level numbers, below the plot
local STRIP_H = 58
local PITCH_MAX = 40               -- widest column pitch (few levels shown)
local XLAB_ALL = 18                -- from this pitch every column has its number
local SCALE_PAD = 1.06
local GRID_MAX = 5
local STEPS = { 600, 1800, 3600, 7200, 14400, 28800, 86400, 172800, 432000, 864000 }  -- then 20, 50, 100... days
local GHOST_A, STUB_H = 0.25, 2
local WPVP_MIX = 0.45
local BG_ROWS = 10                 -- battlegrounds listed in the PvP chip tooltip
local APPROX, DASH = "~", "-"
local PLUS = "+"                   -- after a projection that lacks some levels (no XP size known)
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }

-- Parts of a bar, bottom-up (Stats.LevelSegments fields), their gauge colour keys (false:
-- ui.dim) and their tooltip labels.
local SEG_KEYS = { "world", "wpvp", "dungeon", "raid", "bg", "taxi", "prof", "dead", "city", "inn", "afk",
                   "untracked" }
local NSEG = #SEG_KEYS
local UNTRACKED = NSEG
local SEG_GAUGE = { "world", "pvp", "dungeon", "raid", "pvp", "taxi", "prof", "dead", "city", "inn", "afk", false }
local SEG_LABEL = { "BD_WORLD", "LV_SEG_WPVP", "BD_DUNGEON", "BD_RAID", "LV_SEG_BG", "LV_FLIGHT", "TT_PROF",
                    "BD_DEAD", "BD_CITY", "BD_INN", "BD_AFK", "TT_UNTRACKED" }   -- flight: the chip's, pill's and sheet's label
local BIT = {}
for i = 1, NSEG do BIT[i] = 2 ^ (i - 1) end

-- Activity filters: pill label, title, colour square (a part index; 0 = ui.accent), parts.
local FILTER_ID    = { "all", "world", "inst", "pvp", "flight", "prof", "dead" }
local FILTER_KEY   = { "LV_F_ALL", "BD_WORLD", "LV_F_INST", "BD_PVP", "LV_FLIGHT", "TT_PROF", "BD_DEAD" }
local FILTER_TITLE = { "LV_T_ALL", "LV_T_WORLD", "LV_T_INST", "LV_T_PVP", "LV_T_FLIGHT", "LV_T_PROF", "LV_T_DEAD" }
local FILTER_SQ    = { 0, 1, 3, 5, 6, 7, 8 }
local FILTER_SEGS  = { false, { 1 }, { 3, 4 }, { 2, 5 }, { 6 }, { 7 }, { 8 } }
local NFILTERS = #FILTER_ID
local FILTER_ON = {}               -- [f][i] = part i counts under filter f
for f = 1, NFILTERS do
  local on, segs = {}, FILTER_SEGS[f]
  for i = 1, NSEG do on[i] = not segs end
  if segs then
    for j = 1, #segs do on[segs[j]] = true end
  end
  FILTER_ON[f] = on
end

-- Colours: copies of the active theme's (components only, P5).
local UI_ROLES = { "bg", "border", "title", "accent", "label", "value", "dim" }
local K = C.COLORS
local CLASSIC_UI = { bg = K.bg, border = K.border, title = K.value, accent = K.accent, label = K.label,
                     value = K.value, dim = K.dim }
local UIC = {}                     -- [role] = { r, g, b, 1 }
for i = 1, #UI_ROLES do UIC[UI_ROLES[i]] = { 1, 1, 1, 1 } end
local SEGC = {}                    -- [part] = { r, g, b, 1 }
for i = 1, NSEG do SEGC[i] = { 1, 1, 1, 1 } end
local BOX_BG = { 0, 0, 0, 1 }      -- chips, pills, strip: ui.bg 6 % toward ui.value
local FALLBACK_TT

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local S = {
  frame = nil, root = nil, char = nil, isCur = false, mask = 0,
  filter = 1, hideUp = false, sel = nil,
  level = 1, top = 60, nCols = 0, shown = 0, showFut = false, estOK = false, atMax = false,
  xpOff = false, partial = false,
  status = "nodata", capLevel = nil, scaleTop = -1, step = 0, avg = nil,
  curTime = 0, played = 0, done = 0, xpDone = 0, xpTotal = 0,
  kPlayed = -1, kServer = -1, serverLive = false, kTop = -1, kSum = -1, kCur = -1, kLeft = -1, kShare = -1,
  kBg = -1, kWp = -1, kPv = -1, kTaxi = -1, kTaxiP = -1, kDead = -1, kDeaths = -1,
  wDone = -1, wCur = -1, selAt = nil, selVer = -1, mRel = nil, mVer = -1, mOn = false, colored = false,
  legendAt = nil, curAt = nil,
}
-- geometry: root size, font version (bumped by ApplyTheme) and the applied one, layout
-- version (columns placed again when it changes)
local G = { W = -1, H = -1, fv = 0, afv = -1, ver = 0, colW = 0, plotW = 0, plotH = 0, plotTop = 0, pitch = 0,
            barW = 0, nCols = -1, chipW = 0, trackW = 0, pillRows = 1 }

local cols = {}                    -- [level] = column record (lazy, pooled)
local colOf = setmetatable({}, { __mode = "k" })     -- [hit button] = level
local pillOf = setmetatable({}, { __mode = "k" })    -- [pill button] = filter index
local own = setmetatable({}, { __mode = "k" })       -- frames whose tooltip this module shows
local txt = setmetatable({}, { __mode = "k" })       -- [FontString] = text set
local styled, sizeOf = {}, {}      -- body-role FontStrings and their sizes
local chips, pills, grid = {}, {}, {}
local avg = { y = -1, on = true }
local strip = {}
local selTex = {}
local plot, toggle, toggleFS, titleFS, sumFS, marker, axisL, axisB
local TP

-- reused data (no allocation once warm)
local segOut, lifeSeg = {}, {}
local fut = {}                     -- Stats.FutureLevels output
local info = { level = 1, xp = nil, max = nil, rest = nil, valid = false, isMax = false, capLevel = nil,
               top = 60, sync = nil, now = nil }
local hist, rowOf = {}, {}         -- Stats.LevelHistory rows, [level] = row (Build)
local bgRows = {}                  -- PvP chip tooltip (allocation on hover only)
local tmpH = {}
for i = 1, NSEG do tmpH[i] = 0 end
local xMemo, axisMemo = {}, {}     -- level numbers, gridline labels (bounded: levels, the steps x 5)
local dctx = {}                    -- LevelDetail context of the selection

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Num(v)
  v = tonumber(v)
  if not v or v ~= v then return 0 end
  return v
end

local function Round(v)
  return math_floor(v + 0.5)
end

local function CopyColor(dst, src, fallback)
  if type(src) ~= "table" then src = fallback end
  dst[1], dst[2], dst[3], dst[4] = Num(src[1]), Num(src[2]), Num(src[3]), 1
end

-- The colours of the active theme: `ui` roles (the window's UI table) and gauge colours.
local function ReadColors(ui)
  if type(ui) ~= "table" then ui = CLASSIC_UI end
  for i = 1, #UI_ROLES do
    local role = UI_ROLES[i]
    CopyColor(UIC[role], ui[role], CLASSIC_UI[role])
  end
  local Themes = ns.Themes
  local th = Themes and Themes.Active()
  local tc = th and th.tt
  local gg = type(tc) == "table" and tc.gauge or nil
  local gc = type(gg) == "table" and gg.colors or nil
  if type(gc) ~= "table" then
    local cg = Themes and Themes.CLASSIC_GAUGE
    gc = cg and cg.colors or nil
  end
  for i = 1, NSEG do
    local key = SEG_GAUGE[i]
    CopyColor(SEGC[i], (key and type(gc) == "table") and gc[key] or nil, UIC.dim)
  end
  local w = SEGC[2]
  for j = 1, 3 do w[j] = w[j] + (1 - w[j]) * WPVP_MIX end
  local bg, v = UIC.bg, UIC.value
  for j = 1, 3 do BOX_BG[j] = bg[j] + (v[j] - bg[j]) * 0.06 end
  S.colored = true
end

local function SetFontOf(fs, size)
  local Themes = ns.Themes
  if Themes and Themes.SetFont then
    Themes.SetFont(fs, "body", size, "none")
  else
    fs:SetFont(STANDARD_TEXT_FONT or DEFAULT_FONT, size, "")
  end
end

local function NewText(parent, size, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  SetFontOf(fs, size)
  styled[#styled + 1] = fs
  sizeOf[fs] = size
  return fs
end

-- Sets a text when it changed (the body font's glyph replacements applied).
local function Text(fs, s)
  if s == nil then s = "" end
  if txt[fs] == s then return end
  txt[fs] = s
  local Themes = ns.Themes
  if s ~= "" and Themes and Themes.HasSubst and Themes.HasSubst("body") then s = Themes.Subst("body", s) end
  fs:SetText(s)
end

local function Tint(fs, c)
  fs:SetTextColor(c[1], c[2], c[3])
end

local function NewTex(parent, layer, sub)
  local t = parent:CreateTexture(nil, layer, nil, sub)
  t:SetTexture(C.TEX_WHITE)
  return t
end

local function Paint(t, c, a)
  t:SetVertexColor(c[1], c[2], c[3], a or 1)
end

local function NewBox(kind, parent)
  local f = CreateFrame(kind, nil, parent, "BackdropTemplate")
  if f.SetBackdrop then f:SetBackdrop(BACKDROP) end
  return f
end

local function PaintBox(f, active)
  if not f.SetBackdrop then return end
  local bd = active and UIC.accent or UIC.border
  f:SetBackdropColor(BOX_BG[1], BOX_BG[2], BOX_BG[3], 0.9)
  f:SetBackdropBorderColor(bd[1], bd[2], bd[3], active and 0.9 or 0.35)
end

local function DurOrDash(v)
  if v and v > 0 then return Fmt.Duration(v) end
  return DASH
end

-- Key of DurOrDash(v) (and of Compact(v)): DurationKey + 1, 0 for the dash.
local function DashKey(v)
  if v > 0 then return Fmt.DurationKey(v) + 1 end
  return 0
end

-- The projection's text (chip 7 and the strip's "left"): Fmt.ETA, PLUS after it when
-- levels to play have no estimate (S.partial: the time is a lower bound).
local function TopETA(v)
  local s = Fmt.ETA(v)
  if S.partial then return s .. PLUS end
  return s
end

-- The window's minimum while the chart shows (LevelChart.MinSize, header).
local function MinSize()
  local w, h = MIN_W, MIN_H
  local sw, sh = Num(UIParent:GetWidth()) - SCREEN_MARGIN, Num(UIParent:GetHeight()) - SCREEN_MARGIN
  if sw > 0 and sw < w then w = math_floor(sw) end
  if sh > 0 and sh < h then h = math_floor(sh) end
  return math_max(w, C.WINDOW_MIN_W), math_max(h, C.WINDOW_MIN_H)
end

-- Compact form of a duration for a chip's sub line: its largest unit only (whole days,
-- L.LV_DAYS_FMT, from one day; whole hours, L.DUR_H, from one hour; else Fmt.Duration);
-- a dash for nothing.
local function Compact(v)
  if v and v >= 86400 then return format(L.LV_DAYS_FMT, math_floor(v / 86400)) end
  if v and v >= 3600 then return format(L.DUR_H, math_floor(v / 3600)) end
  return DurOrDash(v)
end

-- Sets a chip's sub line to `full`, or to `short` (the same line with Compact durations)
-- when `full` does not fit the chip (measured here only: a sub line is set on a rebuild or
-- when its key changes). Its unbounded width: the client bounds GetStringWidth by the
-- width set (Layout), so it never exceeds the chip (GetStringWidth on a client without
-- GetUnboundedStringWidth).
local function SubFit(ch, full, short)
  local fs = ch.sub
  Text(fs, full)
  if short == full then return end
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
  if Num(w) > G.chipW - 2 * CHIP_PAD then Text(fs, short) end
end

local function PvpAvailable()
  local P = ns.Pvp
  return P ~= nil and P.Available ~= nil and P.Available() and true or false
end

-- World PvP is measured for this character (on this client, since char.pvp.w0).
local function WorldMeasured(char)
  local p = char and char.pvp
  return PvpAvailable() and type(p) == "table" and tonumber(p.w0) ~= nil
end

---------------------------------------------------------------------------
-- One-shot tooltip helper (shared with LevelDetail.lua)
---------------------------------------------------------------------------

local tip = { tt = nil, owner = nil, pal = nil, isTP = false }

local function Palette()
  local Themes = ns.Themes
  local th = Themes and Themes.Active()
  local tc = th and th.tt
  local pal = type(tc) == "table" and tc.colors or nil
  if type(pal) ~= "table" then pal = Themes and Themes.CLASSIC_TT end
  if type(pal) ~= "table" then
    if not FALLBACK_TT then
      FALLBACK_TT = { title = K.accent, label = K.label, value = K.value, dim = K.dim, header = K.accent,
                      hint = K.dim }
    end
    pal = FALLBACK_TT
  end
  return th, tc, pal
end

-- Starts a tooltip for `owner` (filled with TipRow, shown by TipShow); returns it.
function LevelChart.TipBegin(owner)
  if owner == nil then return nil end
  local th, tc, pal = Palette()
  local tt = GameTooltip
  local TF = ns.TooltipFrame
  if th and not th.native and type(tc) == "table" and TF then tt = TF.Get(1) end
  local prev = tip.tt
  if prev and prev ~= tt and tip.owner and prev:GetOwner() == tip.owner then prev:Hide() end
  tt:SetOwner(owner, "ANCHOR_NONE")
  tip.tt, tip.owner, tip.pal = tt, owner, pal
  tip.isTP = rawget(tt, "TP_Row") ~= nil
  return tt
end

local function TipColor(c, default)
  if type(c) == "string" then c = tip.pal[c] end
  if type(c) ~= "table" then c = tip.pal[default] end
  if type(c) ~= "table" then c = UIC.value end
  return c
end

-- kind: a TooltipFrame row kind (title, section, header, pair, line, note, wrap, hint...);
-- lc / rc: palette role names or colour tables; wrap: the left text wraps.
function LevelChart.TipRow(kind, left, right, lc, rc, wrap)
  local tt = tip.tt
  if not tt or not tip.pal then return end
  local a = TipColor(lc, right ~= nil and "label" or "value")
  if right ~= nil then
    local b = TipColor(rc, "value")
    if tip.isTP then
      tt:TP_Row(kind, left, right, a, b)
    else
      tt:AddDoubleLine(left, right, a[1], a[2], a[3], b[1], b[2], b[3])
    end
  elseif tip.isTP then
    tt:TP_Row(kind, left, nil, a, nil, wrap and true or nil)
  else
    tt:AddLine(left, a[1], a[2], a[3], wrap and true or false)
  end
end

-- A separator ("block": a blank line on a GameTooltip).
function LevelChart.TipSep(kind)
  local tt = tip.tt
  if not tt then return end
  kind = kind or "block"
  if tip.isTP then
    tt:TP_Sep(kind)
  elseif kind == "block" then
    tt:AddLine(" ")
  end
end

function LevelChart.TipShow(anchor, point, relPoint, x, y)
  local tt = tip.tt
  if not tt then return end
  tt:ClearAllPoints()
  tt:SetPoint(point or "TOPLEFT", anchor or tip.owner, relPoint or "TOPRIGHT", x or 4, y or 0)
  tt:Show()
  tip.pal = nil
end

-- Hides the tooltip when it is still ours (and shown for `owner`, any owner when nil).
function LevelChart.TipHide(owner)
  local tt, o = tip.tt, tip.owner
  if not tt then return end
  if owner ~= nil and owner ~= o then return end
  if tt:GetOwner() == o then tt:Hide() end
  tip.tt, tip.owner, tip.pal = nil, nil, nil
end

-- A frame of the chart or of the detail sheet that shows these tooltips.
function LevelChart.Owns(owner)
  if owner == nil then return false end
  if own[owner] then return true end
  local LD = ns.LevelDetail
  return LD ~= nil and LD.Owns ~= nil and LD.Owns(owner) and true or false
end

local function OnTipLeave(self)
  LevelChart.TipHide(self)
end

---------------------------------------------------------------------------
-- Painting (creation and ApplyTheme)
---------------------------------------------------------------------------

local function PaintChip(ch)
  PaintBox(ch.frame, false)
  Tint(ch.label, UIC.label)
  Tint(ch.sub, UIC.dim)
  Tint(ch.value, UIC[ch.vc] or UIC.value)
end

local function ChipColor(ch, role)
  if ch.vc == role then return end
  ch.vc = role
  Tint(ch.value, UIC[role])
end

local function PaintPill(f)
  local p = pills[f]
  local on = (f == S.filter)
  PaintBox(p.btn, on)
  Tint(p.fs, on and UIC.value or UIC.label)
  local sq = FILTER_SQ[f]
  Paint(p.sq, sq == 0 and UIC.accent or SEGC[sq], 1)
end

local function PaintCol(c)
  local seg = c.seg
  for i = 1, NSEG do
    local t = seg[i]
    if t then Paint(t, SEGC[i], 1) end
  end
  if c.ghost then
    Paint(c.ghost, UIC.dim, GHOST_A)
    Paint(c.gline, UIC.dim, 0.9)
  end
  if c.stub then Paint(c.stub, UIC.dim, 0.6) end
  if c.xl then Tint(c.xl, c.k == S.level and UIC.accent or UIC.dim) end
end

local function PaintStrip()
  PaintBox(strip.frame, false)
  Tint(strip.title, UIC.value)
  Tint(strip.share, UIC.dim)
  Paint(strip.track, UIC.dim, 0.3)
  Paint(strip.done, UIC.accent, 1)
  Paint(strip.cur, SEGC[1], 1)
  Paint(strip.sq1, UIC.accent, 1)
  Paint(strip.sq2, SEGC[1], 1)
  Paint(strip.sq3, UIC.dim, 0.5)
  Tint(strip.fs1, UIC.label)
  Tint(strip.fs2, UIC.label)
  Tint(strip.fs3, UIC.label)
end

local function Repaint()
  for i = 1, NCHIPS do PaintChip(chips[i]) end
  for f = 1, NFILTERS do PaintPill(f) end
  PaintBox(toggle, false)
  Tint(toggleFS, UIC.label)
  Tint(titleFS, UIC.accent)
  Tint(sumFS, UIC.dim)
  Paint(axisL, UIC.border, 0.5)
  Paint(axisB, UIC.border, 0.5)
  for j = 1, GRID_MAX do
    Paint(grid[j].line, UIC.border, 0.12)
    Tint(grid[j].label, UIC.dim)
  end
  Paint(avg.line, UIC.accent, 0.75)
  Paint(avg.bg, UIC.bg, 0.85)
  Tint(avg.label, UIC.accent)
  Paint(marker, UIC.accent, 1)
  for i = 1, 4 do Paint(selTex[i], UIC.title, 1) end
  for _, c in pairs(cols) do PaintCol(c) end
  PaintStrip()
end

---------------------------------------------------------------------------
-- Columns (lazy, pooled)
---------------------------------------------------------------------------

local OnColClick, OnColEnter        -- column scripts (below)

local function NewCol(k)
  local c = { k = k, seg = {}, segH = {}, val = {}, x = 0, ver = -1, sig = -1, H = 0, total = 0, sumAll = 0,
              est = 0, kind = "none", partial = false, rec = false, gH = -1, gOn = false, stubOn = false }
  for i = 1, NSEG do c.segH[i], c.val[i] = 0, 0 end
  local hit = CreateFrame("Button", nil, plot)
  hit:SetScript("OnClick", OnColClick)
  hit:SetScript("OnEnter", OnColEnter)
  hit:SetScript("OnLeave", OnTipLeave)
  local hl = NewTex(hit, "HIGHLIGHT")
  hl:SetAllPoints(hit)
  hl:SetVertexColor(1, 1, 1, 0.08)
  c.hit = hit
  colOf[hit], own[hit] = k, true
  cols[k] = c
  return c
end

local function NewSeg(c, i)
  local t = NewTex(plot, "ARTWORK", 0)
  Paint(t, SEGC[i], 1)
  c.seg[i] = t
  return t
end

local function NewGhost(c)
  local g = NewTex(plot, "ARTWORK", 1)
  Paint(g, UIC.dim, GHOST_A)
  g:SetWidth(G.barW)
  local gl = NewTex(plot, "ARTWORK", 2)
  Paint(gl, UIC.dim, 0.9)
  gl:SetPoint("BOTTOMLEFT", g, "TOPLEFT", 0, -1)
  gl:SetSize(G.barW, 1)
  c.ghost, c.gline = g, gl
  return g
end

local function NewStub(c)
  local s = NewTex(plot, "ARTWORK", 0)
  Paint(s, UIC.dim, 0.6)
  s:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", c.x, 0)
  s:SetSize(G.barW, STUB_H)
  c.stub = s
  return s
end

local function XText(k)
  local s = xMemo[k]
  if not s then
    s = format("%d", k)
    xMemo[k] = s
  end
  return s
end

-- Places a column for the current layout (G.ver): hit area, stub, ghost width, number.
local function PlaceCol(c)
  local k = c.k
  c.x = 2 + (k - 1) * G.pitch
  local hit = c.hit
  hit:ClearAllPoints()
  hit:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", c.x, 0)
  hit:SetSize(G.barW, G.plotH)
  hit:Show()
  if c.stub then
    c.stub:ClearAllPoints()
    c.stub:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", c.x, 0)
    c.stub:SetWidth(G.barW)
  end
  if c.ghost then
    c.ghost:SetWidth(G.barW)
    c.gline:SetWidth(G.barW)
  end
  if k == 1 or k % 5 == 0 or G.pitch >= XLAB_ALL then
    local xl = c.xl
    if not xl then
      xl = NewText(plot, 10, "CENTER")
      Tint(xl, UIC.dim)
      c.xl = xl
    end
    xl:ClearAllPoints()
    xl:SetPoint("TOP", plot, "BOTTOMLEFT", c.x + G.barW / 2, -3)
    Text(xl, XText(k))
    xl:Show()
  elseif c.xl then
    c.xl:Hide()
  end
  c.ver = G.ver
  c.sig = -1                         -- segments anchored again
  c.gRel = nil
end

local function HideCol(c)
  c.hit:Hide()
  local seg, segH = c.seg, c.segH
  for i = 1, NSEG do
    if seg[i] then seg[i]:Hide() end
    segH[i] = 0
  end
  c.sig, c.ver, c.top, c.gRel = -1, -1, nil, nil
  if c.gOn then
    c.gOn = false
    c.ghost:Hide()
    c.gline:Hide()
  end
  if c.stubOn then
    c.stubOn = false
    c.stub:Hide()
  end
  if c.xl then c.xl:Hide() end
end

-- Draws a column for the scale: the visible parts (cumulative rounding), anchored again
-- only when their set changed; the ghost on top; the stub of a level without record.
local function DrawColumn(c)
  if c.ver ~= G.ver then PlaceCol(c) end
  local scale, plotH = S.scaleTop, G.plotH
  local on, val, total = FILTER_ON[S.filter], c.val, c.total
  local H = 0
  if total > 0 and scale > 0 then
    H = Round(total / scale * plotH)
    if H < 1 then H = 1 elseif H > plotH then H = plotH end
  end
  local sig, acc, prev = 0, 0, 0
  for i = 1, NSEG do
    local h = 0
    if H > 0 and on[i] then
      local v = val[i]
      if v > 0 then
        acc = acc + v
        local edge = Round(acc / total * H)
        h = edge - prev
        prev = edge
        if h > 0 then sig = sig + BIT[i] end
      end
    end
    tmpH[i] = h
  end
  local seg, segH = c.seg, c.segH
  if sig ~= c.sig then
    c.sig = sig
    local below = nil
    for i = 1, NSEG do
      local t, h = seg[i], tmpH[i]
      if h > 0 then
        if not t then t = NewSeg(c, i) end
        t:ClearAllPoints()
        if below then
          t:SetPoint("BOTTOMLEFT", below, "TOPLEFT", 0, 0)
        else
          t:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", c.x, 0)
        end
        t:SetSize(G.barW, h)
        segH[i] = h
        t:Show()
        below = t
      elseif t then
        segH[i] = 0
        t:Hide()
      end
    end
    c.top = below
  else
    for i = 1, NSEG do
      local h = tmpH[i]
      if h > 0 and h ~= segH[i] then
        segH[i] = h
        seg[i]:SetHeight(h)
      end
    end
  end
  c.H = H
  local gh = 0
  if S.showFut and c.est > 0 and scale > 0 and (c.kind == "cur" or c.kind == "future") then
    gh = Round(c.est / scale * plotH)
    if gh < 1 then gh = 1 end
    if H + gh > plotH then gh = plotH - H end
  end
  if gh > 0 then
    local g = c.ghost or NewGhost(c)
    local rel = c.top or plot
    if c.gRel ~= rel then
      c.gRel = rel
      g:ClearAllPoints()
      if c.top then
        g:SetPoint("BOTTOMLEFT", c.top, "TOPLEFT", 0, 0)
      else
        g:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", c.x, 0)
      end
    end
    if c.gH ~= gh then
      c.gH = gh
      g:SetHeight(gh)
    end
    if not c.gOn then
      c.gOn = true
      g:Show()
      c.gline:Show()
    end
  elseif c.gOn then
    c.gOn = false
    c.ghost:Hide()
    c.gline:Hide()
  end
  local stub = (c.kind == "none")
  if stub ~= c.stubOn then
    c.stubOn = stub
    if stub then
      (c.stub or NewStub(c)):Show()
    else
      c.stub:Hide()
    end
  end
end

-- The 1 px ui.accent line on top of the current level's solid part.
local function DrawMarker()
  local c = (not S.atMax) and cols[S.level] or nil
  local rel = (c and c.H > 0) and c.top or nil
  if rel then
    if S.mRel ~= rel or S.mVer ~= G.ver then
      S.mRel, S.mVer = rel, G.ver
      marker:ClearAllPoints()
      marker:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
      marker:SetSize(G.barW, 1)
    end
    if not S.mOn then
      S.mOn = true
      marker:Show()
    end
  elseif S.mOn then
    S.mOn = false
    marker:Hide()
  end
end

---------------------------------------------------------------------------
-- Data of a column
---------------------------------------------------------------------------

local function FillParts(c, lb, mask)
  local val = c.val
  if lb then
    ns.Stats.LevelSegments(lb, mask, segOut)
    for i = 1, NSEG do val[i] = Num(segOut[SEG_KEYS[i]]) end
  else
    for i = 1, NSEG do val[i] = 0 end
  end
end

-- Parts, kind and estimate of column c (S.curTime and fut are up to date).
local function FillCol(c, char, mask)
  local k, level = c.k, S.level
  local levels = char.levels
  local lb = type(levels) == "table" and levels[k] or nil
  if type(lb) ~= "table" then lb = nil end
  c.partial = lb ~= nil and lb.partial == true
  c.rec = lb ~= nil and lb.rec == true
  c.est = 0
  local val = c.val
  if k < level then
    c.kind = lb and "done" or "none"
    FillParts(c, lb, mask)
  elseif k == level then
    c.kind = "cur"
    FillParts(c, lb, mask)
    local sum = 0
    for i = 1, NSEG do sum = sum + val[i] end
    if S.curTime > sum then val[UNTRACKED] = val[UNTRACKED] + (S.curTime - sum) end
    if S.estOK then c.est = Num(fut.cur) end
  else
    c.kind = "future"
    FillParts(c, nil, mask)
    c.est = Num(fut[k])
  end
  local on, all, total = FILTER_ON[S.filter], 0, 0
  for i = 1, NSEG do
    local v = val[i]
    all = all + v
    if on[i] then total = total + v end
  end
  c.sumAll, c.total = all, total
end

-- Stats.FutureLevels input: the live XP of the current character, else its snapshot and
-- its recorded server cap (char.capLevel while it is its level: the Tracker's SyncCap rule;
-- the field goes at its next XP gain or level).
local function FillInfo(char, sync, now)
  info.level, info.top, info.sync, info.now = S.level, S.top, sync, now
  local T = ns.Tracker
  if S.isCur and T then
    local _, xp, max, rest, valid = T.GetXPInfo()
    info.xp, info.max, info.rest, info.valid = xp, max, rest, valid and true or false
    info.isMax = T.IsMax() and true or false
    info.capLevel = T.GetCapInfo()
  else
    local snap = char.xpSnap
    if type(snap) ~= "table" or (snap.level ~= nil and snap.level ~= char.level) then snap = nil end
    info.xp, info.max = snap and snap.xp or nil, snap and snap.max or nil
    info.rest, info.valid, info.isMax = nil, false, false
    local cap = tonumber(char.capLevel)
    info.capLevel = (cap ~= nil and cap == char.level) and cap or nil
  end
end

---------------------------------------------------------------------------
-- Scale, gridlines, average
---------------------------------------------------------------------------

-- A gridline's label: whole days from a day (L.LV_DAYS_FMT), whole hours, else a duration.
local function AxisText(v)
  local s = axisMemo[v]
  if not s then
    if v % 86400 == 0 then
      s = format(L.LV_DAYS_FMT, math_floor(v / 86400))
    elseif v % 3600 == 0 then
      s = format(L.DUR_H, math_floor(v / 3600))
    else
      s = Fmt.Duration(v)
    end
    axisMemo[v] = s
  end
  return s
end

local function DrawAvg()
  local a = S.avg
  local on = a ~= nil and a > 0 and S.scaleTop > 0
  if on then
    local y = Round(a / S.scaleTop * G.plotH)
    if y > G.plotH then y = G.plotH end
    if avg.y ~= y then
      avg.y = y
      avg.stalk:SetHeight(y + 1)
    end
  end
  if on ~= avg.on then
    avg.on = on
    if on then
      avg.line:Show()
      avg.bg:Show()
      avg.label:Show()
    else
      avg.line:Hide()
      avg.bg:Hide()
      avg.label:Hide()
    end
  end
end

-- New scale from the shown values (bars + ghosts); returns true when it changed (every
-- column drawn again), always redraws when `force`.
local function Rescale(force)
  local n, mx = S.nCols, 0
  for k = 1, n do
    local c = cols[k]
    local v = c.total
    if S.showFut and (c.kind == "cur" or c.kind == "future") then v = v + c.est end
    if v > mx then mx = v end
  end
  mx = mx * SCALE_PAD
  local step, top = STEPS[#STEPS], nil
  for i = 1, #STEPS do
    local s = STEPS[i]
    local m = math_ceil(mx / s)
    if m <= GRID_MAX then
      if m < 1 then m = 1 end
      step, top = s, m * s
      break
    end
  end
  if not top then
    -- beyond STEPS: 20, 50, 100, 200, 500... days (x 2, 2.5, 2), at most GRID_MAX lines
    local s = step
    for i = 1, 30 do
      s = s * ((i % 3 == 2) and 2.5 or 2)
      local m = math_ceil(mx / s)
      if m <= GRID_MAX then
        step, top = s, m * s
        break
      end
    end
    if not top then top = math_ceil(mx / step) * step end   -- not finite
  end
  if top == S.scaleTop and not force then return false end
  S.scaleTop, S.step = top, step
  local plotH = G.plotH
  for j = 1, GRID_MAX do
    local gl = grid[j]
    local v = j * step
    if v <= top then
      local y = Round(v / top * plotH)
      if gl.y ~= y then
        gl.y = y
        gl.stalk:SetHeight(y + 1)
      end
      Text(gl.label, AxisText(v))
      if not gl.on then
        gl.on = true
        gl.line:Show()
        gl.label:Show()
      end
    elseif gl.on then
      gl.on = false
      gl.line:Hide()
      gl.label:Hide()
    end
  end
  DrawAvg()
  for k = 1, n do DrawColumn(cols[k]) end
  return true
end

local function ComputeAvg()
  local sum, n = 0, 0
  for k = 1, math_min(S.nCols, S.level - 1) do
    local c = cols[k]
    if c.kind == "done" and not c.partial and not c.rec then
      sum, n = sum + c.total, n + 1
    end
  end
  S.avg = (n > 0) and sum / n or nil
  if S.avg then Text(avg.label, format(L.LV_AVG_FMT, Fmt.Duration(S.avg))) end
end

---------------------------------------------------------------------------
-- Layout (Build only: when the frame size or the fonts changed)
---------------------------------------------------------------------------

-- Filter pills left to right (a second row when they do not fit before the toggle).
local function PlacePills(colW)
  local root = S.root
  for f = 1, NFILTERS do Text(pills[f].fs, L[FILTER_KEY[f]]) end
  toggleFS:SetText(L.LV_HIDE_UPCOMING)
  local w1 = Num(toggleFS:GetStringWidth())
  toggleFS:SetText(L.LV_SHOW_UPCOMING)
  local w2 = Num(toggleFS:GetStringWidth())
  txt[toggleFS] = nil                -- set again by FillHeader
  local y0 = COL_TOP + TITLE_H + 6
  local tw = math_ceil(math_max(w1, w2)) + 2 * PILL_PAD
  toggle:ClearAllPoints()
  toggle:SetPoint("TOPRIGHT", root, "TOPLEFT", colW, -y0)
  toggle:SetSize(tw, PILL_H)
  local avail = colW - tw - 10
  local x, row = 0, 0
  for f = 1, NFILTERS do
    local p = pills[f]
    local w = math_ceil(Num(p.fs:GetStringWidth())) + 2 * PILL_PAD + PILL_SQ + 4
    if x > 0 and x + w > avail then
      row, x = row + 1, 0
    end
    p.btn:ClearAllPoints()
    p.btn:SetPoint("TOPLEFT", root, "TOPLEFT", x, -(y0 + row * (PILL_H + 4)))
    p.btn:SetSize(w, PILL_H)
    p.w = w
    x = x + w + PILL_GAP
  end
  G.pillRows = row + 1
end

local function Layout(frame)
  local W = math_floor(Num(frame:GetWidth()) + 0.5) - 2 * ROOT_X
  local H = math_floor(Num(frame:GetHeight()) + 0.5) - ROOT_TOP - ROOT_BOTTOM
  local minW, minH = MinSize()
  if W < minW - 2 * ROOT_X then W = minW - 2 * ROOT_X end
  if H < minH - ROOT_TOP - ROOT_BOTTOM then H = minH - ROOT_TOP - ROOT_BOTTOM end
  if W == G.W and H == G.H and G.afv == G.fv then return end
  G.W, G.H, G.afv = W, H, G.fv
  local root = S.root
  root:SetSize(W, H)
  local cw = math_floor((W - (NCHIPS - 1) * CHIP_GAP) / NCHIPS)
  G.chipW = cw
  for i = 1, NCHIPS do
    local ch = chips[i]
    ch.frame:ClearAllPoints()
    ch.frame:SetPoint("TOPLEFT", root, "TOPLEFT", (i - 1) * (cw + CHIP_GAP), 0)
    ch.frame:SetSize(cw, CHIP_H)
    local inner = cw - 2 * CHIP_PAD
    ch.label:SetWidth(inner)
    ch.value:SetWidth(inner)
    ch.sub:SetWidth(inner)
  end
  local colW = W - DETAIL_W - DETAIL_GAP
  G.colW = colW
  titleFS:ClearAllPoints()
  titleFS:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -COL_TOP)
  sumFS:ClearAllPoints()
  sumFS:SetPoint("TOPRIGHT", root, "TOPLEFT", colW, -COL_TOP - 1)
  PlacePills(colW)
  local top = COL_TOP + TITLE_H + 6 + G.pillRows * (PILL_H + 4) + 4
  local plotH = math_max(1, H - top - XLAB_H - 8 - STRIP_H)   -- (a window of 300 px only: 1)
  G.plotTop, G.plotH, G.plotW = top, plotH, colW - AXIS_W
  plot:ClearAllPoints()
  plot:SetPoint("TOPLEFT", root, "TOPLEFT", AXIS_W, -top)
  plot:SetSize(G.plotW, plotH)
  axisL:SetSize(1, plotH)
  axisB:SetSize(G.plotW, 1)
  for j = 1, GRID_MAX do grid[j].line:SetSize(G.plotW, 1) end
  avg.line:SetSize(G.plotW, 1)
  strip.frame:ClearAllPoints()
  strip.frame:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 0, 0)
  strip.frame:SetSize(colW, STRIP_H)
  G.trackW = colW - 20
  strip.track:SetSize(G.trackW, 10)
  G.nCols = -1                       -- the columns are laid out again
  G.ver = G.ver + 1
end

local function ColGeometry(n)
  if n == G.nCols then return end
  G.nCols = n
  local pitch = math_floor((G.plotW - 2) / n)
  if pitch > PITCH_MAX then pitch = PITCH_MAX end
  if pitch < 2 then pitch = 2 end
  G.pitch = pitch
  G.barW = pitch - math_max(1, math_floor(pitch / 5))
  G.ver = G.ver + 1
end

---------------------------------------------------------------------------
-- Chips, title line, strip
---------------------------------------------------------------------------

-- Server /played: the live value, else the last snapshot with its age (never the local
-- total under this label, critique #21).
local function FillServer(char, base, live)
  local ch = chips[2]
  Text(ch.label, L.TT_SERVER)
  S.serverLive = live and true or false
  if live then
    S.kServer = Fmt.DurationKey(base)
    Text(ch.value, Fmt.Duration(base))
    Text(ch.sub, L.LV_SERVER_SUB)
    ChipColor(ch, "value")
    return
  end
  S.kServer = -1
  local srv = char.srv
  local total = type(srv) == "table" and tonumber(srv.total) or nil
  if total then
    Text(ch.value, Fmt.Duration(total))
    local at = tonumber(srv.at)
    if at then
      local age = time() - at
      if age < 0 then age = 0 end
      Text(ch.sub, Fmt.Ago(age))
    else
      Text(ch.sub, L.LV_SERVER_SUB)
    end
  else
    Text(ch.value, L.DOTS)
    Text(ch.sub, "")
  end
  ChipColor(ch, "label")
end

-- "Level <top> in" (the projection), the max level (and the time there), the server cap,
-- the XP disabled below the top level.
local function FillTop()
  local ch = chips[7]
  ChipColor(ch, "accent")
  if S.atMax then
    S.kTop = Fmt.DurationKey(S.curTime)
    Text(ch.label, L.MAX_LEVEL)
    Text(ch.value, XText(S.level))
    SubFit(ch, format(L.LV_MAX_SUB_FMT, Fmt.Duration(S.curTime)), format(L.LV_MAX_SUB_FMT, Compact(S.curTime)))
  elseif S.status == "cap" or S.xpOff then
    S.kTop = -1
    Text(ch.label, S.xpOff and L.LV_XP_OFF or L.CAP_SHORT)
    Text(ch.value, format(L.LV_CAP_LEVEL_FMT, S.xpOff and S.level or S.capLevel or S.level))
    Text(ch.sub, "")
  else
    Text(ch.label, format(L.LV_TOP_IN_FMT, S.top))
    Text(ch.sub, L.LV_TOP_SUB)
    if S.estOK then
      S.kTop = Fmt.ETAKey(fut.total)
      Text(ch.value, TopETA(fut.total))
    else
      S.kTop = -1
      Text(ch.value, L.DOTS)
    end
  end
end

-- The PvP (and its battlegrounds / world sub line), Flight (and its share of the played
-- time, "< 1 %" for a non-zero share under 1 %) and Deaths (and the dead time) chips from
-- the character's life totals under the mask: Build (force) and every live step, their
-- texts set again only when one of their keys changed (nothing allocated otherwise).
local function FillActivity(char, filtered, force)
  local life = type(char.life) == "table" and char.life or nil
  ns.Stats.LevelSegments(life, S.mask, lifeSeg)
  local bg, wp = Num(lifeSeg.bg), Num(lifeSeg.wpvp)
  local measured = WorldMeasured(char)
  local kb, kw, kv = DashKey(bg), measured and DashKey(wp) or -1, DashKey(bg + wp)
  local ch
  if force or kb ~= S.kBg or kw ~= S.kWp or kv ~= S.kPv then
    S.kBg, S.kWp, S.kPv = kb, kw, kv
    ch = chips[4]
    Text(ch.label, L.BD_PVP)
    Text(ch.value, DurOrDash(bg + wp))
    SubFit(ch, format(L.LV_PVP_SUB_FMT, DurOrDash(bg), measured and DurOrDash(wp) or L.DOTS),
      format(L.LV_PVP_SUB_FMT, Compact(bg), measured and Compact(wp) or L.DOTS))
  end
  local taxi = Num(lifeSeg.taxi)
  local kt, kp = DashKey(taxi), -1
  if taxi > 0 and filtered > 0 then
    local x = taxi / filtered
    kp = (x < 0.01) and 0 or math_floor(x * 100 + 0.5)   -- Fmt.Percent's rounding
  end
  if force or kt ~= S.kTaxi or kp ~= S.kTaxiP then
    S.kTaxi, S.kTaxiP = kt, kp
    ch = chips[5]
    Text(ch.label, L.LV_FLIGHT)
    Text(ch.value, DurOrDash(taxi))
    local share = ""
    if kp == 0 then
      share = format(L.LV_FLIGHT_SUB_FMT, format(L.LV_LT_FMT, Fmt.PercentInt(1)))
    elseif kp > 0 then
      share = format(L.LV_FLIGHT_SUB_FMT, Fmt.PercentInt(kp))
    end
    Text(ch.sub, share)
  end
  local dead = Num(lifeSeg.dead)
  local kd, ks = math_floor(Num(life and life.d)), (dead >= 60) and Fmt.DurationKey(dead) or -1
  if force or kd ~= S.kDeaths or ks ~= S.kDead then
    S.kDeaths, S.kDead = kd, ks
    ch = chips[6]
    Text(ch.label, L.TT_DEATHS)
    Text(ch.value, Fmt.Number(kd))
    if ks >= 0 then
      SubFit(ch, format(L.LV_DEAD_SUB_FMT, Fmt.Duration(dead)), format(L.LV_DEAD_SUB_FMT, Compact(dead)))
    else
      Text(ch.sub, "")
    end
  end
end

local function FillChips(char, mask, sync, now)
  local Stats = ns.Stats
  local filtered, base, _, live = Stats.Played(char, mask, sync, now)
  filtered = Num(filtered)
  S.played = filtered
  local ch = chips[1]
  Text(ch.label, L.LV_PLAYED)
  Text(ch.value, Fmt.Duration(filtered))
  Text(ch.sub, (S.level == 1) and L.LV_PLAYED_SUB_ONE or format(L.LV_PLAYED_SUB_FMT, S.level))
  S.kPlayed = Fmt.DurationKey(filtered)
  FillServer(char, Num(base), live)
  ch = chips[3]
  local a = Stats.AvgPerLevel(char, mask, sync, now)
  local recent, count = Stats.RecentAvg(char, mask, C.RECENT_LEVELS)
  Text(ch.label, L.LV_AVG)
  Text(ch.value, a and Fmt.Duration(a) or L.DOTS)
  if recent then
    local n = math_floor(Num(count))
    SubFit(ch, format(L.LV_AVG_RECENT_FMT, n, Fmt.Duration(recent)), format(L.LV_AVG_RECENT_FMT, n, Compact(recent)))
  else
    Text(ch.sub, "")
  end
  FillActivity(char, filtered, true)
  FillTop()
end

-- Shown time and count of the played levels (under a filter: the levels with at least a
-- minute of the activity); no level to count: "no time recorded", or the few seconds
-- alone (L.LD_TOTAL_FMT), never "0 levels".
local function DrawSummary(force)
  local f, sum, n = S.filter, 0, 0
  for k = 1, math_min(S.level, S.top - 1, S.nCols) do
    local c = cols[k]
    if c.kind ~= "none" then
      sum = sum + c.total
      if f == 1 or c.total >= 60 then n = n + 1 end
    end
  end
  local key = DashKey(sum) * 1000 + n
  if key == S.kSum and not force then return end
  S.kSum = key
  if n == 0 then
    Text(sumFS, (sum > 0) and format(L.LD_TOTAL_FMT, Fmt.Duration(sum)) or L.LV_SUM_NONE)
    return
  end
  local fmt
  if f == 1 then
    fmt = (n == 1) and L.LV_SUM_ONE_FMT or L.LV_SUM_FMT
  else
    fmt = (n == 1) and L.LV_SUM_FILTER_ONE_FMT or L.LV_SUM_FILTER_FMT
  end
  Text(sumFS, format(fmt, Fmt.Duration(sum), n))
end

local function FillHeader()
  Text(titleFS, L[FILTER_TITLE[S.filter]])
  for f = 1, NFILTERS do PaintPill(f) end
  if S.filter == 1 and S.estOK then
    Text(toggleFS, S.hideUp and L.LV_SHOW_UPCOMING or L.LV_HIDE_UPCOMING)
    toggle:Show()
  else
    toggle:Hide()
  end
  DrawSummary(true)
end

-- The XP of the levels below the current one and of every level to top - 1 (Stats.XPOf).
local function XPSums(char)
  local Stats, db = ns.Stats, ns.db
  local done, total = 0, 0
  for l = 1, S.top - 1 do
    local x = Num(Stats.XPOf(char, db, l))
    total = total + x
    if l < S.level then done = done + x end
  end
  S.xpDone, S.xpTotal = done, total
end

-- Widths, share and legend of the strip (strings only when a key changed).
local function DrawStrip(force)
  local W = G.trackW
  local cur, left = S.curTime, S.estOK and Num(fut.total) or 0
  local xpCur = Num(info.xp)
  local xpPart = (S.xpTotal > 0) and (S.xpDone + xpCur) / S.xpTotal or 0
  if xpPart > 1 then xpPart = 1 end
  local pX = math_floor(xpPart * 100)
  local wDone, wCur, pT = 0, 0, 0
  local key
  if S.atMax then
    wDone, key = W, -2
  elseif S.estOK then
    local grand = S.done + cur + left
    if grand <= 0 then grand = 1 end
    wDone, wCur = Round(S.done / grand * W), Round(cur / grand * W)
    pT = math_floor((S.done + cur) / grand * 100)
    key = S.partial and -5 or pT * 1000 + pX
  else
    if S.xpTotal > 0 then
      wDone, wCur = Round(S.xpDone / S.xpTotal * W), Round(xpCur / S.xpTotal * W)
    end
    key = (S.status == "cap") and -3 or S.xpOff and -4 or pX
  end
  if force or key ~= S.kShare then
    S.kShare = key
    local s
    if S.atMax then
      s = L.TT_MAX_LEVEL
    elseif S.partial then
      s = ""                         -- levels without an XP size: neither share is known
    elseif S.estOK then
      s = format(L.LV_SHARE_FMT, pT, pX)
    elseif S.status == "cap" then
      s = format(L.LV_CAP_FMT, S.capLevel or S.level)
    elseif S.xpOff then
      s = format(L.LV_XP_OFF_FMT, S.level)
    else
      s = format(L.LV_XP_SHARE_FMT, pX)
    end
    Text(strip.share, s)
  end
  if wDone < 1 then wDone = 1 end    -- >= 1 px: the next part is anchored on it
  if wDone > W then wDone = W end
  if wCur < 1 then wCur = 1 end
  if wDone + wCur > W then wCur = math_max(1, W - wDone) end
  if wDone ~= S.wDone then
    S.wDone = wDone
    strip.done:SetWidth(wDone)
  end
  if wCur ~= S.wCur then
    S.wCur = wCur
    strip.cur:SetWidth(wCur)
  end
  if not S.atMax then
    local kc = Fmt.DurationKey(cur)
    if force or kc ~= S.kCur then
      S.kCur = kc
      Text(strip.fs2, format(L.LV_CUR_FMT, S.level, Fmt.Duration(cur)))
    end
    if S.estOK then
      local kl = Fmt.ETAKey(left)      -- the chip's text and key ("Level <top> in")
      if force or kl ~= S.kLeft then
        S.kLeft = kl
        Text(strip.fs3, format(L.LV_LEFT_FMT, TopETA(left)))
      end
    end
  end
end

local function ShowIf(r, on)
  if on then r:Show() else r:Hide() end
end

local function FillStrip(char)
  XPSums(char)
  S.done = math_max(0, S.played - S.curTime)
  Text(strip.title, format(L.LV_PROGRESS_FMT, S.top))
  local nDone = S.level - 1
  local hasDone = nDone >= 1
  if hasDone then
    local d = Fmt.Duration(S.done)
    Text(strip.fs1, nDone == 1 and format(L.LV_DONE_ONE_FMT, d) or format(L.LV_DONE_FMT, nDone, d))
  end
  ShowIf(strip.done, hasDone)
  ShowIf(strip.sq1, hasDone)
  ShowIf(strip.fs1, hasDone)
  local hasCur = not S.atMax
  ShowIf(strip.cur, hasCur)
  ShowIf(strip.sq2, hasCur)
  ShowIf(strip.fs2, hasCur)
  local hasLeft = hasCur and S.estOK
  ShowIf(strip.sq3, hasLeft)
  ShowIf(strip.fs3, hasLeft)
  -- the current part after the done one (or at the track's start), the legend likewise
  local rel = hasDone and strip.done or strip.track
  if S.curAt ~= rel then
    S.curAt = rel
    strip.cur:ClearAllPoints()
    if hasDone then
      strip.cur:SetPoint("LEFT", strip.done, "RIGHT", 0, 0)
    else
      strip.cur:SetPoint("LEFT", strip.track, "LEFT", 0, 0)
    end
  end
  rel = hasDone and strip.fs1 or strip.frame
  if S.legendAt ~= rel then
    S.legendAt = rel
    strip.sq2:ClearAllPoints()
    if hasDone then
      strip.sq2:SetPoint("LEFT", strip.fs1, "RIGHT", 14, 0)
    else
      strip.sq2:SetPoint("TOPLEFT", strip.frame, "TOPLEFT", 10, -42)
    end
  end
  DrawStrip(true)
end

---------------------------------------------------------------------------
-- Selection and detail sheet
---------------------------------------------------------------------------

local function PlaceSel()
  local k = S.sel
  local c = k and k <= S.nCols and cols[k] or nil
  if not c then
    if S.selAt then
      S.selAt = nil
      for i = 1, 4 do selTex[i]:Hide() end
    end
    return
  end
  if S.selAt == k and S.selVer == G.ver then return end
  S.selAt, S.selVer = k, G.ver
  local hit = c.hit
  local t, b, l, r = selTex[1], selTex[2], selTex[3], selTex[4]
  t:ClearAllPoints()
  t:SetPoint("BOTTOMLEFT", hit, "TOPLEFT", -1, 0)
  t:SetSize(G.barW + 2, 1)
  b:ClearAllPoints()
  b:SetPoint("TOPLEFT", hit, "BOTTOMLEFT", -1, 0)
  b:SetSize(G.barW + 2, 1)
  l:ClearAllPoints()
  l:SetPoint("TOPRIGHT", hit, "TOPLEFT", 0, 0)
  l:SetSize(1, G.plotH)
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", hit, "TOPRIGHT", 0, 0)
  r:SetSize(1, G.plotH)
  for i = 1, 4 do selTex[i]:Show() end
end

local function ShowDetail(sync, now)
  local LD = ns.LevelDetail
  if not LD then return end
  local k = S.sel
  local c = k and cols[k]
  if not c or k > S.nCols then
    LD.Hide()
    return
  end
  dctx.isCur, dctx.mask, dctx.sync, dctx.now = S.isCur, S.mask, sync, now
  dctx.row, dctx.kind, dctx.est = rowOf[k], c.kind, c.est
  dctx.time = (c.kind == "cur") and S.curTime or c.sumAll
  dctx.level, dctx.top, dctx.status, dctx.fut = S.level, S.top, S.status, fut
  dctx.xp, dctx.max = info.xp, info.max
  dctx.y, dctx.h, dctx.w = COL_TOP, G.H - COL_TOP, DETAIL_W
  local tp = LD.Show(S.root, S.char, k, dctx)
  local f = S.frame
  if f and f.tp then f.tp.detail = tp end
end

---------------------------------------------------------------------------
-- Mouse
---------------------------------------------------------------------------

-- World PvP note of a level (PvP filter, bar tooltip), nil when measured all along.
local function WorldNote(char, k)
  if not PvpAvailable() then return L.LV_WPVP_NO_CLIENT end
  local st = ns.Stats.WorldPvpState(char, k)
  if st == "partial" then return L.LV_WPVP_PARTIAL end
  if st == "no" then return L.LV_WPVP_BEFORE end
  return nil
end

-- Share of the level's time as the sheet reads it: a non-zero share that rounds to 0 is "<1%".
local function Share(v, sum)
  local p = (sum > 0) and math_floor(v / sum * 100 + 0.5) or 0
  if p == 0 and v >= 1 then return format(L.LV_LT_FMT, Fmt.PercentInt(1)) end
  return Fmt.PercentInt(p)
end

-- The one part of the filter that has time on this bar (nil: none or several). Its row
-- moves under the title instead of coming twice.
local function OnlyPart(c)
  local segs = FILTER_SEGS[S.filter]
  if not segs then return nil end
  local only
  for n = 1, #segs do
    local j = segs[n]
    if c.val[j] >= 1 then
      if only then return nil end
      only = j
    end
  end
  return only or (#segs == 1 and segs[1]) or nil
end

OnColEnter = function(self)
  local k = colOf[self]
  local c = k and cols[k]
  local char = S.char
  if not c or not char then return end
  local LC = LevelChart
  LC.TipBegin(self)
  LC.TipRow("title", format(L.LEVEL_SPAN_FMT, k, k + 1), nil, "title")
  local kind = c.kind
  if kind == "done" or kind == "cur" then
    local row = rowOf[k]
    local value = (kind == "cur") and S.curTime or c.sumAll
    local sum = c.sumAll
    -- Only one of the filter's parts has time here (always so for world, flight, professions,
    -- dead; instances or PvP with a single part): its row moves up under the title (label in
    -- its colour, value in accent) instead of coming twice.
    local only = OnlyPart(c)
    if S.filter ~= 1 then
      -- the bar's own value (the filter's parts) and its share of the level, then the level
      local v = c.total
      LC.TipRow("pair", only and L[SEG_LABEL[only]] or L[FILTER_KEY[S.filter]],
        (v >= 1) and format(L.LV_PART_FMT, Fmt.Duration(v), Share(v, sum)) or DASH,
        only and SEGC[only] or UIC.accent, UIC.accent)
    end
    local approx = row ~= nil and (row.partial or row.rec or Num(row.estF) > 0 or Num(row.gap) > 0)
    LC.TipRow("pair", L.LV_PLAYED, (approx and APPROX or "") .. Fmt.Duration(value))
    for i = 1, NSEG do
      local v = c.val[i]
      if v >= 1 and i ~= only then
        LC.TipRow("pair", L[SEG_LABEL[i]], format(L.LV_PART_FMT, Fmt.Duration(v), Share(v, sum)),
          SEGC[i], "value")
      end
    end
    local deaths = row and math_floor(Num(row.deaths)) or 0
    if deaths > 0 then LC.TipRow("pair", L.TT_DEATHS, Fmt.Number(deaths)) end
    if row and row.xph then LC.TipRow("pair", L.TT_XPH, Fmt.Rate(row.xph)) end
    if kind == "cur" then
      LC.TipRow("pair", L.COL_REACHED, L.ROW_IN_PROGRESS, "label", UIC.accent)
    elseif row and row.endAt then
      LC.TipRow("pair", L.COL_REACHED, Fmt.DateTime(row.endAt))
    end
    if FILTER_ID[S.filter] == "pvp" then
      local note = WorldNote(char, k)
      if note then LC.TipRow("wrap", note, nil, "dim", nil, true) end
    end
  elseif kind == "future" then
    LC.TipRow("line", format(L.LV_UPCOMING_FMT, c.est > 0 and Fmt.ETA(c.est) or L.DOTS), nil, "value")
    local xp = ns.Stats.XPOf(char, ns.db, k)
    if xp then LC.TipRow("line", format(L.LV_XP_EARN_FMT, Fmt.Number(xp)), nil, "label") end
  else
    LC.TipRow("wrap", L.LV_NO_RECORD, nil, "dim", nil, true)
  end
  LC.TipRow("hint", L.LV_CLICK_HINT, nil, "hint")
  LC.TipShow(self, "TOPLEFT", "TOPRIGHT", 4, 0)
end

-- PvP chip: the battlegrounds one by one, the other ones, world PvP and what it is.
local function OnPvpEnter(self)
  local char = S.char
  if not char then return end
  local Stats, LC = ns.Stats, LevelChart
  local life = type(char.life) == "table" and char.life or nil
  Stats.LevelSegments(life, S.mask, lifeSeg)
  local bg, wp = Num(lifeSeg.bg), Num(lifeSeg.wpvp)
  -- the rows under the mask with the AFK keys left out: a battleground's AFK time (P) is in
  -- the AFK part, not in the battlegrounds line above (p only), which the rows make up
  local m = math_floor(Num(S.mask))
  if m % 2 == 0 then m = m + C.MASK_AFK end
  local n, other = Stats.LifeBattlegrounds(char, m, bgRows)
  n, other = math_floor(Num(n)), Num(other)
  LC.TipBegin(self)
  LC.TipRow("title", format(L.LV_PVP_TIP_FMT, DurOrDash(bg + wp)), nil, "title")
  LC.TipRow("pair", L.LV_SEG_BG, DurOrDash(bg), SEGC[5], "value")
  for i = 1, n do
    local r = bgRows[i]
    if i > BG_ROWS then
      other = other + Num(r.secs)
    else
      LC.TipRow("pair", "   " .. tostring(r.name), Fmt.Duration(Num(r.secs)), "label", "value")
    end
  end
  if other >= 60 then LC.TipRow("pair", "   " .. L.LV_BG_OTHER, Fmt.Duration(other), "label", "value") end
  local measured = WorldMeasured(char)
  LC.TipRow("pair", L.LV_WPVP_LONG, measured and DurOrDash(wp) or L.DOTS, SEGC[2], "value")
  LC.TipSep("block")
  LC.TipRow("wrap", format(L.LV_WPVP_DEF_FMT, math_floor(Num(C.PVP_IDLE) / 60 + 0.5)), nil, "dim", nil, true)
  if not PvpAvailable() then
    LC.TipRow("wrap", L.LV_WPVP_NO_CLIENT, nil, "dim", nil, true)
  elseif measured then
    LC.TipRow("wrap", format(L.LV_WPVP_SINCE_FMT, Fmt.DateTime(char.pvp.w0)), nil, "dim", nil, true)
  else
    LC.TipRow("wrap", L.LV_WPVP_NONE, nil, "dim", nil, true)
  end
  LC.TipShow(self, "TOPLEFT", "BOTTOMLEFT", 0, -4)
end

-- Filter or toggle clicked: the chart alone is built again (same character and mask).
local function Rebuild()
  if not S.frame or not S.char then return end
  local sync = S.isCur and ns.Tracker and ns.Tracker.GetSync() or nil
  LevelChart.Build(S.frame, S.char, S.isCur, S.mask, GetTime(), sync, nil)
end

local function OnPillClick(self)
  local f = pillOf[self]
  if not f or f == S.filter then return end
  S.filter = f
  LevelChart.TipHide()
  Rebuild()
end

local function OnToggleClick()
  S.hideUp = not S.hideUp
  Rebuild()
end

OnColClick = function(self)
  local k = colOf[self]
  if not k or not S.char or k > S.nCols then return end
  S.sel = k
  PlaceSel()
  ShowDetail(S.isCur and ns.Tracker and ns.Tracker.GetSync() or nil, GetTime())
end

---------------------------------------------------------------------------
-- Creation (first Build)
---------------------------------------------------------------------------

local function NewChip(root, i)
  local f = NewBox("Frame", root)
  local ch = { frame = f, vc = "value" }
  ch.label = NewText(f, 10, "LEFT")
  ch.label:SetPoint("TOPLEFT", f, "TOPLEFT", CHIP_PAD, -5)
  ch.value = NewText(f, 13, "LEFT")
  ch.value:SetPoint("TOPLEFT", f, "TOPLEFT", CHIP_PAD, -17)
  ch.sub = NewText(f, 10, "LEFT")
  ch.sub:SetPoint("TOPLEFT", f, "TOPLEFT", CHIP_PAD, -32)
  chips[i] = ch
end

local function NewPill(root, f)
  local b = NewBox("Button", root)
  local p = { btn = b, w = 0 }
  p.sq = NewTex(b, "ARTWORK", 0)
  p.sq:SetSize(PILL_SQ, PILL_SQ)
  p.sq:SetPoint("LEFT", b, "LEFT", PILL_PAD, 0)
  p.fs = NewText(b, 11, "LEFT")
  p.fs:SetPoint("LEFT", p.sq, "RIGHT", 4, 0)
  local hl = NewTex(b, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetVertexColor(1, 1, 1, 0.08)
  b:SetScript("OnClick", OnPillClick)
  pillOf[b] = f
  pills[f] = p
end

local function CreateStrip(root)
  local f = NewBox("Frame", root)
  strip.frame = f
  strip.title = NewText(f, 12, "LEFT")
  strip.title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -7)
  strip.share = NewText(f, 11, "RIGHT")
  strip.share:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -8)
  strip.track = NewTex(f, "ARTWORK", 0)
  strip.track:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -25)
  strip.done = NewTex(f, "ARTWORK", 1)
  strip.done:SetPoint("LEFT", strip.track, "LEFT", 0, 0)
  strip.done:SetSize(1, 10)
  strip.cur = NewTex(f, "ARTWORK", 1)
  strip.cur:SetSize(1, 10)
  for i = 1, 3 do
    local sq = NewTex(f, "ARTWORK", 0)
    sq:SetSize(8, 8)
    local fs = NewText(f, 11, "LEFT")
    fs:SetPoint("LEFT", sq, "RIGHT", 4, 0)
    strip["sq" .. i], strip["fs" .. i] = sq, fs
  end
  strip.sq1:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -42)
  strip.sq3:SetPoint("LEFT", strip.fs2, "RIGHT", 14, 0)
end

local function CreatePlot(root)
  plot = CreateFrame("Frame", nil, root)
  axisL = NewTex(plot, "BORDER", 1)
  axisL:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, 0)
  axisB = NewTex(plot, "BORDER", 1)
  axisB:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, 0)
  for j = 1, GRID_MAX do
    -- an invisible stalk (never hidden: an anchor) sized to the line's height
    local st = NewTex(plot, "BACKGROUND", 0)
    st:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, 0)
    st:SetSize(1, 1)
    st:SetVertexColor(1, 1, 1, 0)
    local ln = NewTex(plot, "BORDER", 0)
    ln:SetPoint("BOTTOMLEFT", st, "TOPLEFT", 0, -1)
    local lab = NewText(plot, 10, "RIGHT")
    lab:SetPoint("RIGHT", ln, "LEFT", -6, 0)
    grid[j] = { stalk = st, line = ln, label = lab, y = -1, on = true }
  end
  local st = NewTex(plot, "BACKGROUND", 0)
  st:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, 0)
  st:SetSize(1, 1)
  st:SetVertexColor(1, 1, 1, 0)
  avg.stalk = st
  avg.line = NewTex(plot, "OVERLAY", 0)
  avg.line:SetPoint("BOTTOMLEFT", st, "TOPLEFT", 0, -1)
  avg.label = NewText(plot, 10, "LEFT")
  avg.label:SetPoint("BOTTOMLEFT", avg.line, "TOPLEFT", 6, 2)
  avg.bg = NewTex(plot, "ARTWORK", 7)
  avg.bg:SetPoint("TOPLEFT", avg.label, "TOPLEFT", -3, 1)
  avg.bg:SetPoint("BOTTOMRIGHT", avg.label, "BOTTOMRIGHT", 3, -1)
  marker = NewTex(plot, "ARTWORK", 3)
  marker:Hide()
  for i = 1, 4 do
    selTex[i] = NewTex(plot, "OVERLAY", 1)
    selTex[i]:Hide()
  end
end

local function Create(frame)
  local root = CreateFrame("Frame", nil, frame)
  root:SetPoint("TOPLEFT", frame, "TOPLEFT", ROOT_X, -ROOT_TOP)
  root:SetSize(MIN_W - 2 * ROOT_X, MIN_H - ROOT_TOP - ROOT_BOTTOM)
  S.root = root
  for i = 1, NCHIPS do NewChip(root, i) end
  local pv = chips[4].frame
  pv:EnableMouse(true)
  pv:SetScript("OnEnter", OnPvpEnter)
  pv:SetScript("OnLeave", OnTipLeave)
  own[pv] = true
  titleFS = NewText(root, 12, "LEFT")
  sumFS = NewText(root, 11, "RIGHT")
  for f = 1, NFILTERS do NewPill(root, f) end
  toggle = NewBox("Button", root)
  toggleFS = NewText(toggle, 11, "CENTER")
  toggleFS:SetPoint("CENTER", toggle, "CENTER", 0, 0)
  local hl = NewTex(toggle, "HIGHLIGHT")
  hl:SetAllPoints(toggle)
  hl:SetVertexColor(1, 1, 1, 0.08)
  toggle:SetScript("OnClick", OnToggleClick)
  CreatePlot(root)
  CreateStrip(root)
  Repaint()
  TP = { root = root, chips = chips, filters = pills, toggle = toggle, toggleText = toggleFS, plot = plot,
         cols = cols, grid = grid, avg = avg, strip = strip, sel = selTex, marker = marker, title = titleFS,
         summary = sumFS, tip = tip, state = S, geo = G, segKeys = SEG_KEYS, filterIds = FILTER_ID,
         axis = { left = axisL, bottom = axisB } }
end

---------------------------------------------------------------------------
-- Public API (Window.lua)
---------------------------------------------------------------------------

-- Full rebuild for `char` (the current character when isCur: live data, sync).
function LevelChart.Build(frame, char, isCur, mask, now, sync, ui)
  if frame == nil or type(char) ~= "table" then return end
  local Stats = ns.Stats
  S.frame = frame
  if not S.colored then ReadColors(ui) end
  if not S.root then Create(frame) end
  S.root:Show()
  if char ~= S.char then S.sel = nil end
  S.char, S.isCur, S.mask = char, isCur and true or false, mask
  now = now or GetTime()
  local top = math_floor(Num(ns.Util.MaxLevel()))
  if top < 2 then top = 2 end
  local level = math_floor(Num(char.level))
  if level < 1 then level = 1 elseif level > top then level = top end
  S.top, S.level = top, level
  FillInfo(char, sync, now)
  Stats.FutureLevels(char, ns.db, mask, info, fut)
  local st = fut.status or "nodata"
  S.status, S.capLevel = st, info.capLevel
  S.atMax = level >= top
  S.xpOff = st == "max" and not S.atMax      -- XP disabled below the top level (Util.IsMaxLevel)
  S.estOK = (st == "ok" or st == "estimate") and not S.atMax
  S.partial = S.estOK and Num(fut.missing) > 0
  S.showFut = S.filter == 1 and not S.hideUp and S.estOK
  local nCols = S.showFut and (top - 1) or math_min(level, top - 1)
  if nCols < 1 then nCols = 1 end
  local out, n = Stats.LevelHistory(char, mask, sync, now, hist)
  for l in pairs(rowOf) do rowOf[l] = nil end
  out = out or hist
  for i = 1, math_floor(Num(n)) do
    local r = out[i]
    if type(r) == "table" and r.level then rowOf[r.level] = r end
  end
  Layout(frame)
  ColGeometry(nCols)
  S.curTime = Num((Stats.LevelTime(char, level, mask, sync, now)))
  for k = 1, nCols do FillCol(cols[k] or NewCol(k), char, mask) end
  for k = nCols + 1, S.shown do
    local c = cols[k]
    if c then HideCol(c) end
  end
  S.nCols, S.shown = nCols, nCols
  ComputeAvg()
  Rescale(true)
  DrawMarker()
  for k = 1, nCols do
    local xl = cols[k].xl
    if xl then Tint(xl, k == level and UIC.accent or UIC.dim) end
  end
  FillChips(char, mask, sync, now)
  FillHeader()
  FillStrip(char)
  local sel = S.sel
  if not sel or sel > nCols then
    sel = math_min(level, top - 1, nCols)
    if sel < 1 then sel = 1 end
    S.sel = sel
  end
  PlaceSel()
  ShowDetail(sync, now)
  if frame.tp then frame.tp.chart = TP end
end

-- Live step (current character): the current column, the estimates, the live chips, the
-- strip, the summary and the detail sheet of the current level. Allocates nothing unless a
-- shown string changes.
function LevelChart.Live(char, mask, sync, now)
  local root = S.root
  if not root or not S.isCur or char ~= S.char or mask ~= S.mask or not root:IsShown() then return end
  local Stats = ns.Stats
  local filtered, base, _, live = Stats.Played(char, mask, sync, now)
  filtered = Num(filtered)
  S.played = filtered
  local key = Fmt.DurationKey(filtered)
  if key ~= S.kPlayed then
    S.kPlayed = key
    Text(chips[1].value, Fmt.Duration(filtered))
  end
  if live then
    key = Fmt.DurationKey(base)
    if key ~= S.kServer or not S.serverLive then FillServer(char, Num(base), true) end
  end
  FillActivity(char, filtered, false)
  S.curTime = Num((Stats.LevelTime(char, S.level, mask, sync, now)))
  if S.atMax then
    key = Fmt.DurationKey(S.curTime)
    if key ~= S.kTop then
      S.kTop = key
      SubFit(chips[7], format(L.LV_MAX_SUB_FMT, Fmt.Duration(S.curTime)), format(L.LV_MAX_SUB_FMT, Compact(S.curTime)))
    end
    return
  end
  FillInfo(char, sync, now)
  Stats.FutureLevels(char, ns.db, mask, info, fut)
  local st = fut.status or "nodata"
  local estOK = (st == "ok" or st == "estimate")
  -- another kind of projection (an estimate appears or goes, max / XP disabled, cap, levels
  -- without an estimate): rebuilt (rare); "ok" <-> "estimate" only changes the status
  if estOK ~= S.estOK or (st ~= S.status and not estOK) or (estOK and (Num(fut.missing) > 0) ~= S.partial) then
    LevelChart.Build(S.frame, char, true, mask, now, sync, nil)
    return
  end
  S.status = st
  local level = S.level
  local c = cols[level]
  FillCol(c, char, mask)
  local n = S.nCols
  if S.showFut then
    for k = level + 1, n do cols[k].est = Num(fut[k]) end
  end
  if not Rescale(false) then
    DrawColumn(c)
    if S.showFut then
      for k = level + 1, n do DrawColumn(cols[k]) end
    end
  end
  DrawMarker()
  if S.estOK then
    key = Fmt.ETAKey(fut.total)
    if key ~= S.kTop then
      S.kTop = key
      Text(chips[7].value, TopETA(fut.total))
    end
  end
  DrawStrip(false)
  DrawSummary(false)
  if S.sel == level then
    local LD = ns.LevelDetail
    if LD then LD.Live(char, mask, sync, now) end
  end
end

function LevelChart.Hide()
  LevelChart.TipHide()
  if S.root then S.root:Hide() end
  local LD = ns.LevelDetail
  if LD then LD.Hide() end
end

-- Window.Show: the selection back to the viewed character's current level, filter "all".
function LevelChart.Reset()
  S.sel = nil
  S.filter = 1
end

function LevelChart.MinSize()
  return MinSize()
end

-- Theme switch: colours and fonts again (texts set again by the next Build), tooltip hidden.
function LevelChart.ApplyTheme(ui)
  ReadColors(ui)
  LevelChart.TipHide()
  if not S.root then return end
  for i = 1, #styled do
    local fs = styled[i]
    SetFontOf(fs, sizeOf[fs])
  end
  for fs in pairs(txt) do txt[fs] = nil end
  G.fv = G.fv + 1                    -- pills measured again
  S.kShare, S.kSum = -1, -1
  Repaint()
end
