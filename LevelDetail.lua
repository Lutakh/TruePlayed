local ADDON, ns = ...
local L, C, Fmt = ns.L, ns.C, ns.Fmt

-- LevelDetail.lua - the detail sheet of the level selected in the Levels tab of a
-- character (LevelChart.lua): a 400 px panel right of the chart, below the chips, with a
-- scroll frame (UIPanelScrollFrameTemplate) and its content frame. Every text is in the
-- body font role, as the chart's (the display role is kept to Themes.DISPLAY_KEYS, whose
-- glyphs every display font has), section titles in ui.title. Top to bottom:
--  * header: the title (L.LEVEL_SPAN_FMT, "Level 19 » 20"), the status line ("Completed on
--    <Fmt.DateTime>" = the date the next level was reached, L.DOTS when unknown; "In
--    progress: P % of the level's XP" in ui.accent, L.DOTS without an XP reading;
--    "Upcoming"; "No data"), then the approximation notes as wrapped ui.dim lines (the
--    old level row tooltip's: begun before the install ROW_PARTIAL_TIP, rebuilt whole
--    ROW_REC_TIP, the rebuilt part under the exclusions ROW_EST_TIP_FMT (Stats row.estF),
--    the server time not split ROW_GAP_TIP_FMT (row.gap), and LD_STALL_FMT: the seconds
--    without an XP gain, row.stall);
--  * a played level (done, or in progress): six figure cards (2 x 3): Played (the shown
--    time, "~" when partly estimated: partial, rec, estF > 0 or gap > 0; sub: the
--    exclusions, else "everything included"), Server /played (row.server, "~" when
--    extrapolated), Estimated at start (row.eta; sub: how much more (warn) or less (good)
--    the level took, from a minute, for a level neither partial nor rebuilt and an
--    estimate taken under the current exclusions (row.etaM; nil, an older record: shown);
--    the current level with a projection: "Level estimate" = its time + the time left, sub
--    "about X left" in ui.accent), Total since level 1 (row.cum, the time until the next
--    level was reached; sub: "level 1 » 20", the title's arrow, and for the level in
--    progress "level 1 » 20, in progress": up to now, live), XP per hour (row.xph),
--    Deaths (count; sub: the dead time, "none", or nothing for deaths recorded before the
--    dead time was); "Time breakdown": a 10 px stacked bar of the parts of
--    Stats.LevelSegments under the mask in the chart's fixed order and colours (the
--    current level's server excess over its parts is "untracked", as its bar), then one
--    row per category of at least a second, the longest first (colour square, label,
--    duration, percent of the total, "<1%" for a share that rounds to 0): World (open
--    world less world PvP), Dungeons, Raids, PvP (battlegrounds + world PvP, with the
--    "(hover)" hint), Flight (always listed: a dash when none), Professions, Dead, City,
--    Inn, AFK, untracked. Hovering the PvP row shows its split through LevelChart's
--    tooltip helper: the battlegrounds one by one (Stats.LevelBattlegrounds under the
--    mask with AFK left out: a battleground's AFK time is in the AFK part, so the rows
--    plus "Other battlegrounds" make the battleground part), world PvP (L.DOTS when not
--    measured, never 0), its definition and, after Stats.WorldPvpState, "measured since
--    <w0>", "measured only for part of this level", "not measured at this level" or "not
--    measured on this client" (ns.Pvp unavailable); "Experience": "xp / max XP" (the XP
--    reading of the level in progress, else the level's gain and size), a 3-part bar mobs
--    (xa, the bar's XP colour: the user's, else the theme's) / quests and other (xq, the
--    gauge city colour) / rested bonus (xr, the bar's rested colour) and their values and
--    percents; "Zones and instances": Stats.TopZones of the level (8 at most; named from
--    char.zones, a capital with L.CITY_MARK, an excluded zone with a dash and last; never
--    an instance: every one of the level, Stats.TopInstances under mask 0, is left out,
--    however many) with a small bar proportional to the longest row (gauge world, city),
--    then Stats.TopInstances under the mask, merged by name (the 5 longest, "name (kind)",
--    gauge dungeon / raid / pvp; a battleground first seen under its instance key is one
--    row);
--  * an upcoming level: "Estimated duration" (Fmt.ETA of its FutureLevels estimate), its
--    basis (FutureLevels src: "recent", the pace over the last levels; "rate", the current
--    XP per hour), "XP to earn" (Stats.XPOf) and "Reached in about <the play time until it
--    is done>" (the time left in the current level + the estimates up to this one);
--  * no record: one wrapped line (reached before TruePlayed was installed).
--
-- API (LevelChart.lua only): LevelDetail.Show(parent, char, level, ctx) builds the sheet of
-- `level` (allocation allowed: a click or a rebuild) and returns the test handles (the
-- chart stores them as frame.tp.detail); ctx = { isCur, mask, sync, now, row (the
-- Stats.LevelHistory row of the level, or nil), kind ("done", "cur", "future", "none"),
-- est (estimated seconds of an upcoming level / left in the current one), time (its shown
-- seconds), level (the character's level), top, status and fut (Stats.FutureLevels: the
-- chart's own table, kept for Live), xp, max (the XP reading of the current level), y, h,
-- w (place: below the chips, right of the root) }. LevelDetail.Live(char, mask, sync,
-- now) is the live step of the current level of the current character (LevelChart.Live,
-- every C.WINDOW_ROW_REFRESH ticks, while it is selected): the Played, Server, Total,
-- estimate and Deaths cards and the time breakdown (its total, its bar's widths, its rows'
-- values and percents, sorted again in their places) follow the time and the level's
-- parts with Fmt.DurationFullKey / DurationKey / ETAKey keys (a string only when a key
-- changes, a width only when a pixel changes, no anchor while the rows keep their order:
-- nothing allocated otherwise; a flight, a battleground, a death or AFK time shows
-- without an XP gain); a row more or less moves the sections below: the sheet is laid out
-- again (Lay, rare). The notes, the XP and the zones follow at the next rebuild (an XP
-- gain rebuilds the window within 30 s). Hide; ApplyTheme(ui) (fonts: the body role;
-- colours: copies of the `ui` roles, of the gauge colours and of the bar's XP / rested
-- colours, P5); Recolor() (a change of the user's XP / rested colours: the copies read
-- again and painted, Window's THEME_CHANGED "colors"); Owns(owner) (the PvP row's hover
-- frame: Window.Deactivate, LevelChart.Owns).
--
-- Durations: every measured one (the Played, Server /played and Total cards, the dead
-- time, the notes, the time breakdown, the zones, the PvP row's tooltip) keeps its
-- minutes past 10 h (Fmt.DurationFull: "10h 23m", "1d 19h 05m"); in the value columns of
-- the breakdown and the zones a time that does not fit with them (a language with long
-- units: "2 d 23 h 59 min") drops them (Fmt.Duration, DurFit). The notes and the zones of
-- the current character's level in progress keep Fmt.Duration (Grows: no live step
-- refreshes them, their times grow until the next rebuild). The estimates (the
-- "Estimated at start" card and how the level went against it, the time left, an
-- upcoming level's figures) keep Fmt.Duration and Fmt.ETA.
--
-- Layout: every region has one TOPLEFT anchor on the content frame and an explicit size,
-- anchored again only when its place changes (a rebuild of the same sheet anchors nothing:
-- the chart's live growth stays SetPoint-free); the stacked bars are chained (each part on
-- the right of the previous shown one) and anchored again only when their set of parts
-- changes. The content's height is the bottom of its last section; a new sheet (another
-- level or character) scrolls back to its top.
--
-- Performance: created at the first Show of each section, pooled (notes, rows, zones),
-- never per tick; texts and colours set only when they changed.

local math_floor, math_ceil, math_max = math.floor, math.ceil, math.max
local type, tonumber, tostring, pairs, setmetatable = type, tonumber, tostring, pairs, setmetatable
local format = string.format
local CreateFrame = CreateFrame

local LevelDetail = {}
ns.LevelDetail = LevelDetail

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local W = 400
local PAD = 12
local SCROLL_W = 28                -- room of the scroll bar on the right
local CW = W - SCROLL_W            -- content width
local IW = CW - 2 * PAD            -- inner width (348)
local TITLE_SIZE, STATUS_SIZE, NOTE_SIZE = 15, 12, 11
local GAP = 14                     -- between two sections
local CARD_GAP, CARD_H, CARD_PAD = 8, 46, 8
local CARD_W = math_floor((IW - CARD_GAP) / 2)
local HEAD_H = 18                  -- a section's title row
local BAR_H = 10
local ROW_H = 17
local SQ = 9
local VAL_W, PCT_W = 64, 52        -- right-aligned value and percent columns
local XCOL_W = math_floor((IW - 16) / 3)
local XCOL_H = 40
local ZONE_H, ZONE_BAR_H = 22, 4
local ZONES_MAX, INST_MAX, BG_ROWS = 8, 5, 10
local UP_H = 58
local APPROX, DASH = "~", "-"
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }

-- Parts of a level (Stats.LevelSegments fields) in the chart's fixed order and their gauge
-- colour keys (false: ui.dim), as LevelChart draws them.
local SEG_KEYS = { "world", "wpvp", "dungeon", "raid", "bg", "taxi", "prof", "dead", "city", "inn", "afk",
                   "untracked" }
local NSEG = #SEG_KEYS
local SEG_GAUGE = { "world", "pvp", "dungeon", "raid", "pvp", "taxi", "prof", "dead", "city", "inn", "afk", false }
local P_WORLD, P_WPVP, P_DUNGEON, P_RAID, P_BG, P_CITY, P_UNTRACKED = 1, 2, 3, 4, 5, 9, 12

-- Breakdown rows: label, colour (a part index), parts summed (the PvP row: world PvP and
-- battlegrounds).
local CAT_LABEL = { "BD_WORLD", "BD_DUNGEON", "BD_RAID", "BD_PVP", "LV_FLIGHT", "TT_PROF", "BD_DEAD", "BD_CITY",
                    "BD_INN", "BD_AFK", "TT_UNTRACKED" }
local CAT_PART = { 1, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }
local NCAT = #CAT_LABEL
local CAT_PVP, CAT_FLIGHT = 4, 5

local CARD_KEYS = { "played", "server", "eta", "cum", "xph", "deaths" }
local XP_PARTS = { "xa", "xq", "xr" }
local XP_LABEL = { "LD_XP_MOBS", "LD_XP_QUESTS", "LD_XP_RESTED" }
local KIND_KEY = { d = "KIND_DUNGEON", r = "KIND_RAID", p = "KIND_PVP" }
local KIND_PART = { d = P_DUNGEON, r = P_RAID, p = P_BG }

-- Colours: copies (components) of the active theme's (P5).
local UI_ROLES = { "bg", "border", "title", "accent", "label", "value", "dim" }
local K = C.COLORS
local CLASSIC_UI = { bg = K.bg, border = K.border, title = K.value, accent = K.accent, label = K.label,
                     value = K.value, dim = K.dim }
local UIC = {}                     -- [role] = { r, g, b }
for i = 1, #UI_ROLES do UIC[UI_ROLES[i]] = { 1, 1, 1 } end
local SEGC = {}                    -- [part] = { r, g, b }
for i = 1, NSEG do SEGC[i] = { 1, 1, 1 } end
local XPC = { xa = { 1, 1, 1 }, xq = { 1, 1, 1 }, xr = { 1, 1, 1 } }
local FIXED = { good = K.good, warn = K.warn }   -- C.COLORS: not a theme's table
local BOX_BG = { 0, 0, 0 }
local WPVP_MIX = 0.45
local colored = false

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

-- ctx: the last Show's context (LevelChart's table, kept for Lay from Live), time: the
-- shown seconds of the last Lay, barY / rowsY: the breakdown bar's and rows' place.
local S = {
  char = nil, level = 0, kind = nil, isCur = false, mask = 0, approx = false, fut = nil, estOK = false,
  serverLive = false, serverPfx = "", kTime = -1, kServer = -1, kCum = -1, kEst = -1, kLeft = -1,
  kTotal = -1, kDeaths = -1, kDead = -1, ctx = nil, time = 0, barY = 0, rowsY = 0,
  statusRole = "label", placedY = -1, placedH = -1, barSig = -1, xpSig = -1, pvpRow = nil,
}

local panel, scroll, content, titleFS, statusFS
local own = setmetatable({}, { __mode = "k" })       -- frames whose tooltip this sheet shows
local txt = setmetatable({}, { __mode = "k" })       -- [FontString] = text set
local roleOf = setmetatable({}, { __mode = "k" })    -- [FontString] = colour role
local texRole = setmetatable({}, { __mode = "k" })   -- [Texture] = colour role
local texA = setmetatable({}, { __mode = "k" })      -- [Texture] = alpha
local posX = setmetatable({}, { __mode = "k" })      -- [region] = anchored x / y
local posY = setmetatable({}, { __mode = "k" })
local styled, sizeOf = {}, {}      -- body-role FontStrings and their sizes
local boxes = {}                   -- backdrop frames (cards, the upcoming box)
local notes = {}                   -- approximation notes (pool)
local cards = {}
local TM = { rows = {}, segs = {}, n = 0 }           -- "Time breakdown"
local XP = { segs = {}, cols = {} }                  -- "Experience"
local ZN = { rows = {}, n = 0 }                      -- "Zones and instances"
local UP = {}                                        -- an upcoming level
local pvpHit, norecFS
local tp

-- reused data
local segOut, val = {}, {}
for i = 1, NSEG do val[i] = 0 end
local catVal, order = {}, {}
local zoneRows, instRows, allInst, instKind, bgRows = {}, {}, {}, {}, {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function Num(v)
  v = tonumber(v)
  if not v or v ~= v then return 0 end
  return v
end

-- A measured duration to the minute, a dash for nothing.
local function DurOrDash(v)
  if v and v > 0 then return Fmt.DurationFull(v) end
  return DASH
end

-- Integer key: equal keys <=> equal DurOrDash strings (0: the dash).
local function DashKey(v)
  if v and v > 0 then return Fmt.DurationFullKey(v) + 1 end
  return 0
end

local function CopyColor(dst, src, fallback)
  if type(src) ~= "table" then src = fallback end
  if type(src) ~= "table" then src = K.value end
  dst[1], dst[2], dst[3] = Num(src[1]), Num(src[2]), Num(src[3])
end

-- The user's colour of the bar (widget.xpColor / widget.restedColor: `field`), nil when
-- the built-in one applies.
local function UserColor(field)
  local s = ns.settings
  local w = type(s) == "table" and s.widget or nil
  local c = type(w) == "table" and w[field] or nil
  if type(c) == "table" and c[1] then return c end
  return nil
end

-- The colours of the active theme: `ui` roles (the window's UI table, else the theme's),
-- gauge colours (th.tt.gauge.colors, else Themes.CLASSIC_GAUGE), XP / rested (the user's
-- colours of the bar, else th.colors: the bar's and the tooltip's XP row's).
local function ReadColors(ui)
  local Themes = ns.Themes
  local th = Themes and Themes.Active()
  if type(ui) ~= "table" then ui = th and type(th.ui) == "table" and th.ui or CLASSIC_UI end
  for i = 1, #UI_ROLES do
    local role = UI_ROLES[i]
    CopyColor(UIC[role], ui[role], CLASSIC_UI[role])
  end
  local tc = th and th.tt
  local gg = type(tc) == "table" and tc.gauge or nil
  local gc = type(gg) == "table" and gg.colors or nil
  if type(gc) ~= "table" then
    local cg = Themes and Themes.CLASSIC_GAUGE
    gc = cg and cg.colors or nil
  end
  if type(gc) ~= "table" then gc = nil end
  for i = 1, NSEG do
    local key = SEG_GAUGE[i]
    CopyColor(SEGC[i], (key and gc) and gc[key] or nil, UIC.dim)
  end
  local w = SEGC[P_WPVP]
  for j = 1, 3 do w[j] = w[j] + (1 - w[j]) * WPVP_MIX end
  local cols = th and type(th.colors) == "table" and th.colors or nil
  CopyColor(XPC.xa, UserColor("xpColor") or (cols and cols.xp), K.accent)
  CopyColor(XPC.xq, gc and gc.city, UIC.title)
  CopyColor(XPC.xr, UserColor("restedColor") or (cols and cols.rested), K.restedFill)
  local bg, v = UIC.bg, UIC.value
  for j = 1, 3 do BOX_BG[j] = bg[j] + (v[j] - bg[j]) * 0.06 end
  colored = true
end

local function RoleColor(role)
  if type(role) == "number" then return SEGC[role] or UIC.dim end
  return UIC[role] or XPC[role] or FIXED[role] or UIC.value
end

local function SetFontOf(fs, size)
  local Themes = ns.Themes
  if Themes and Themes.SetFont then
    Themes.SetFont(fs, "body", size, "none")
  else
    fs:SetFont(STANDARD_TEXT_FONT or DEFAULT_FONT, size, "")
  end
end

local function NewText(parent, size, justify, role)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  SetFontOf(fs, size)
  styled[#styled + 1] = fs
  sizeOf[fs] = size
  role = role or "value"
  roleOf[fs] = role
  local c = RoleColor(role)
  fs:SetTextColor(c[1], c[2], c[3])
  return fs
end

-- A wrapping FontString of the inner width.
local function NewWrap(size, role)
  local fs = NewText(content, size, "LEFT", role)
  fs:SetWordWrap(true)
  fs:SetWidth(IW)
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

-- A measured duration in a value column (VAL_W px, right-aligned: the breakdown's rows,
-- the zones): to the minute (DurOrDash), or without the minutes (Fmt.Duration) when that
-- is wider than the column. Measured only from 10 h (below, both texts are the same) and
-- only when the value's key changed: its unbounded width, the client bounding
-- GetStringWidth by the width set (GetStringWidth on a client without
-- GetUnboundedStringWidth).
local function DurFit(fs, v)
  Text(fs, DurOrDash(v))
  if not v or v < 36000 then return end
  local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth() or fs:GetStringWidth()
  if Num(w) > VAL_W then Text(fs, Fmt.Duration(v)) end
end

-- The sheet shows the current character's level in progress: its notes and zones, which
-- only follow at the next rebuild, keep Fmt.Duration (Rough), as minutes past 10 h would
-- fall behind its growing times (the Zones tab's rule, Window.lua).
local function Grows()
  return S.kind == "cur" and S.isCur
end

local function Rough(v)
  if v and v > 0 then return Fmt.Duration(v) end
  return DASH
end

-- The colour role of a FontString (tinted when it changed).
local function Role(fs, role)
  if roleOf[fs] == role then return end
  roleOf[fs] = role
  local c = RoleColor(role)
  fs:SetTextColor(c[1], c[2], c[3])
end

local function NewTex(layer, sub)
  local t = content:CreateTexture(nil, layer, nil, sub)
  t:SetTexture(C.TEX_WHITE)
  return t
end

-- The colour role and alpha of a texture (set when they changed).
local function Paint(t, role, a)
  a = a or 1
  if texRole[t] == role and texA[t] == a then return end
  texRole[t], texA[t] = role, a
  local c = RoleColor(role)
  t:SetVertexColor(c[1], c[2], c[3], a)
end

-- One anchor (the content's top left) per region, set again only when it moved.
local function Place(r, x, y)
  if posX[r] == x and posY[r] == y then return end
  posX[r], posY[r] = x, y
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
end

local function Vis(r, on)
  if on then
    if not r:IsShown() then r:Show() end
  elseif r:IsShown() then
    r:Hide()
  end
end

local function Width(r, w)
  if w < 1 then w = 1 end
  if r:GetWidth() ~= w then r:SetWidth(w) end
end

-- Height of a wrapped text: the game's (GetStringHeight of a FontString with a width),
-- at least its lines estimated from its unbounded width.
local function WrapHeight(fs, size)
  local h = Num(fs:GetStringHeight())
  local f = fs.GetUnboundedStringWidth
  local w = f and Num(f(fs)) or 0
  local lines = math_max(1, math_ceil(w / IW))
  local est = lines * (size + 2)
  if est > h then h = est end
  return math_ceil(h)
end

local function PvpAvailable()
  local P = ns.Pvp
  return P ~= nil and P.Available ~= nil and P.Available() and true or false
end

-- The mask with the AFK keys left out (C.MASK_AFK set): a battleground's AFK time (P) is
-- in the AFK part.
local MASK_AFK = C.MASK_AFK or 1
local function NoAfk(mask)
  mask = math_floor(Num(mask))
  if math_floor(mask / MASK_AFK) % 2 == 1 then return mask end
  return mask + MASK_AFK
end

---------------------------------------------------------------------------
-- Painting (creation and ApplyTheme)
---------------------------------------------------------------------------

local function PaintBox(f)
  if not f.SetBackdrop then return end
  local bd = UIC.border
  f:SetBackdropColor(BOX_BG[1], BOX_BG[2], BOX_BG[3], 0.9)
  f:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.35)
end

local function PaintPanel()
  if not panel.SetBackdrop then return end
  local bg, bd, v = UIC.bg, UIC.border, UIC.value
  panel:SetBackdropColor(bg[1] + (v[1] - bg[1]) * 0.04, bg[2] + (v[2] - bg[2]) * 0.04,
    bg[3] + (v[3] - bg[3]) * 0.04, 0.9)
  panel:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.35)
end

local function Repaint()
  PaintPanel()
  for i = 1, #boxes do PaintBox(boxes[i]) end
  for fs, role in pairs(roleOf) do
    local c = RoleColor(role)
    fs:SetTextColor(c[1], c[2], c[3])
  end
  for t, role in pairs(texRole) do
    local c = RoleColor(role)
    t:SetVertexColor(c[1], c[2], c[3], texA[t] or 1)
  end
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------

local function NewBox()
  local f = CreateFrame("Frame", nil, content, "BackdropTemplate")
  if f.SetBackdrop then f:SetBackdrop(BACKDROP) end
  boxes[#boxes + 1] = f
  PaintBox(f)
  return f
end

local function Create(parent)
  panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  if panel.SetBackdrop then panel:SetBackdrop(BACKDROP) end
  scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CW, 1)
  scroll:SetScrollChild(content)
  if not colored then ReadColors(nil) end
  titleFS = NewText(content, TITLE_SIZE, "LEFT", "title")
  titleFS:SetWidth(IW)
  Place(titleFS, PAD, PAD)
  statusFS = NewText(content, STATUS_SIZE, "LEFT", "label")
  statusFS:SetWidth(IW)
  PaintPanel()
  tp = { panel = panel, scroll = scroll, content = content, title = titleFS, status = statusFS, width = W,
         notes = notes, nNotes = 0, cards = cards, time = TM, xp = XP, zones = ZN.rows, nZones = 0, up = UP,
         height = 0 }
end

local function NewCard(i)
  local f = NewBox()
  f:SetSize(CARD_W, CARD_H)
  local c = { frame = f }
  c.label = NewText(f, 10, "LEFT", "label")
  c.label:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_PAD, -5)
  c.value = NewText(f, 14, "LEFT", "value")
  c.value:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_PAD, -17)
  c.sub = NewText(f, 10, "LEFT", "dim")
  c.sub:SetPoint("TOPLEFT", f, "TOPLEFT", CARD_PAD, -33)
  c.label:SetWidth(CARD_W - 2 * CARD_PAD)
  c.value:SetWidth(CARD_W - 2 * CARD_PAD)
  c.sub:SetWidth(CARD_W - 2 * CARD_PAD)
  cards[i] = c
  cards[CARD_KEYS[i]] = c
  return c
end

-- A section's title row: the title (left) and an optional text on the right.
local function NewHead(sec, right)
  sec.title = NewText(content, 12, "LEFT", "title")
  sec.title:SetWidth(IW)
  if right then
    sec.right = NewText(content, 11, "RIGHT", "dim")
    sec.right:SetWidth(IW)
  end
end

local OnPvpEnter, OnPvpLeave        -- the PvP row's hover (below)

local function NewRow(j)
  local r = {}
  r.sq = NewTex("ARTWORK", 0)
  r.sq:SetSize(SQ, SQ)
  r.label = NewText(content, 12, "LEFT", "value")
  r.hint = NewText(content, 10, "LEFT", "dim")
  r.hint:SetPoint("LEFT", r.label, "RIGHT", 4, 0)
  r.value = NewText(content, 12, "RIGHT", "value")
  r.value:SetWidth(VAL_W)
  r.pct = NewText(content, 11, "RIGHT", "dim")
  r.pct:SetWidth(PCT_W)
  TM.rows[j] = r
  return r
end

local function NewPvpHit()
  local f = CreateFrame("Frame", nil, content)
  f:EnableMouse(true)
  f:SetSize(IW + 8, ROW_H)
  local hl = f:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(C.TEX_WHITE)
  hl:SetAllPoints(f)
  hl:SetVertexColor(1, 1, 1, 0.08)
  f:SetScript("OnEnter", OnPvpEnter)
  f:SetScript("OnLeave", OnPvpLeave)
  own[f] = true
  pvpHit = f
  tp.pvpHit = f
  return f
end

local function NewZoneRow(j)
  local z = {}
  z.name = NewText(content, 12, "LEFT", "value")
  z.name:SetWidth(IW - VAL_W - 8)
  z.time = NewText(content, 12, "RIGHT", "value")
  z.time:SetWidth(VAL_W)
  z.bar = NewTex("ARTWORK", 0)
  z.bar:SetHeight(ZONE_BAR_H)
  ZN.rows[j] = z
  return z
end

---------------------------------------------------------------------------
-- Chained bars (the breakdown, the XP split): parts left to right, cumulative rounding
---------------------------------------------------------------------------

local barW = {}                    -- scratch: pixel widths of a bar's parts

-- Draws the n values of a bar of the inner width at (x, y): pixel widths by cumulative
-- rounding (the parts fill the bar exactly), a part's texture created the first time it
-- shows (coloured by roles[i]: a part index or a role name), each shown part chained on
-- the right of the previous one; anchored again only when the set of shown parts (its
-- bits in S[sigKey]) or the bar's place changed, else SetWidth only.
local function DrawBar(segs, n, values, total, x, y, sigKey, roles)
  local sig, acc, prev, bit = 0, 0, 0, 1
  for i = 1, n do
    local wpx = 0
    local v = values[i]
    if total > 0 and v > 0 then
      acc = acc + v
      local edge = math_floor(acc / total * IW + 0.5)
      wpx = edge - prev
      prev = edge
    end
    barW[i] = wpx
    if wpx > 0 then sig = sig + bit end
    bit = bit * 2
  end
  local anchor = sig ~= S[sigKey] or posX[segs] ~= x or posY[segs] ~= y
  if anchor then
    S[sigKey] = sig
    posX[segs], posY[segs] = x, y
  end
  local before = nil
  for i = 1, n do
    local t, wpx = segs[i], barW[i]
    if wpx > 0 then
      if not t then
        t = NewTex("ARTWORK", 1)
        t:SetHeight(BAR_H)
        segs[i] = t
      end
      Paint(t, roles[i], 1)
      if anchor then
        t:ClearAllPoints()
        if before then
          t:SetPoint("TOPLEFT", before, "TOPRIGHT", 0, 0)
        else
          t:SetPoint("TOPLEFT", content, "TOPLEFT", x, -y)
        end
      end
      Width(t, wpx)
      Vis(t, true)
      before = t
    elseif t then
      Vis(t, false)
    end
  end
end

local function HideBar(segs, n, sigKey)
  for i = 1, n do
    local t = segs[i]
    if t then Vis(t, false) end
  end
  S[sigKey] = -1
end

local function RowVis(r, on)
  Vis(r.sq, on)
  Vis(r.label, on)
  Vis(r.hint, on)
  Vis(r.value, on)
  Vis(r.pct, on)
end

local function ColVis(c, on)
  Vis(c.sq, on)
  Vis(c.label, on)
  Vis(c.value, on)
  Vis(c.pct, on)
end

local function ZoneVis(z, on)
  Vis(z.name, on)
  Vis(z.time, on)
  Vis(z.bar, on)
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

-- Status line of the selected level.
local function StatusOf(ctx)
  local kind = ctx.kind
  if kind == "done" then
    local row = ctx.row
    local at = row and tonumber(row.endAt)
    return format(L.LD_DONE_FMT, at and Fmt.DateTime(at) or L.DOTS), "label"
  elseif kind == "cur" then
    local xp, max = tonumber(ctx.xp), tonumber(ctx.max)
    local p = (xp and max and max > 0) and Fmt.Percent(math_max(0, xp) / max) or L.DOTS
    return format(L.LD_CUR_FMT, p), "accent"
  elseif kind == "future" then
    return L.LD_UPCOMING, "label"
  end
  return L.LD_NODATA, "dim"
end

-- The approximation notes of a played level; returns the y below them.
local function FillNotes(row, y)
  local n = 0
  local function Add(s)
    n = n + 1
    local fs = notes[n]
    if not fs then
      fs = NewWrap(NOTE_SIZE, "dim")
      notes[n] = fs
    end
    Text(fs, s)
    y = y + 5
    Place(fs, PAD, y)
    Vis(fs, true)
    y = y + WrapHeight(fs, NOTE_SIZE)
  end
  if row then
    if row.partial then Add(L.ROW_PARTIAL_TIP) end
    if row.rec then Add(L.ROW_REC_TIP) end
    local D = Grows() and Rough or Fmt.DurationFull
    if Num(row.estF) > 0 then Add(format(L.ROW_EST_TIP_FMT, D(row.estF))) end
    if Num(row.gap) > 0 then Add(format(L.ROW_GAP_TIP_FMT, D(row.gap))) end
    if Num(row.stall) > 0 then Add(format(L.LD_STALL_FMT, D(row.stall))) end
  end
  for j = n + 1, #notes do Vis(notes[j], false) end
  tp.nNotes = n
  return y
end

local function Card(i, label, value, sub, subRole)
  local c = cards[i]
  Text(c.label, label)
  Text(c.value, value)
  Text(c.sub, sub or "")
  Role(c.sub, subRole or "dim")
end

-- "Estimated at start" (row.eta and how the level went), or for the level in progress
-- with a projection: its estimated duration and the time left.
local function FillEta(row, ctx, t)
  local fut = ctx.fut
  if ctx.kind == "cur" and S.estOK and type(fut) == "table" and fut.cur ~= nil then
    local left = Num(fut.cur)
    S.kEst, S.kLeft = Fmt.ETAKey(t + left), Fmt.DurationKey(left)
    Card(3, L.LD_ETA_CUR, Fmt.ETA(t + left), format(L.LD_LEFT_FMT, Fmt.Duration(left)), "accent")
    return
  end
  local eta = row and Num(row.eta) or 0
  if eta <= 0 then
    Card(3, L.LD_ETA, L.DOTS)
    return
  end
  local sub, role = nil, nil
  -- the verdict compares like with like: not for an estimate taken under other exclusions
  -- (row.etaM: the mask at the capture; nil for an older record, compared as before)
  local etaM = row.etaM
  if ctx.kind == "done" and not row.partial and not row.rec and (etaM == nil or etaM == S.mask) then
    local diff = t - eta
    if diff >= 60 then
      sub, role = format(L.LD_MORE_FMT, Fmt.Duration(diff)), "warn"
    elseif diff <= -60 then
      sub, role = format(L.LD_LESS_FMT, Fmt.Duration(-diff)), "good"
    end
  end
  Card(3, L.LD_ETA, Fmt.Duration(eta), sub, role)
end

-- The Deaths card: the count, and the dead time, "none", or nothing for deaths recorded
-- before the dead time was (keys: Live sets it again only when one changed).
local function DeathsCard(deaths, dead)
  S.kDeaths, S.kDead = deaths, DashKey(dead)
  local sub = ""
  if dead > 0 then
    sub = format(L.LV_DEAD_SUB_FMT, Fmt.DurationFull(dead))
  elseif deaths == 0 then
    sub = L.LD_NONE
  end
  Card(6, L.TT_DEATHS, Fmt.Number(deaths), sub)
end

local function FillCards(level, ctx, y)
  if not cards[1] then
    for i = 1, #CARD_KEYS do NewCard(i) end
    tp.eta = cards[3].value
  end
  local row = ctx.row
  local t = S.time
  local Stats = ns.Stats
  -- Played
  local d = Fmt.DurationFull(t)
  local label = Stats.MaskLabel(S.mask)
  Card(1, L.LV_PLAYED, S.approx and (APPROX .. d) or d, label and format(L.TT_EXCL_FMT, label) or L.LV_SERVER_SUB)
  S.kTime = Fmt.DurationFullKey(t)
  -- Server /played
  local server = row and tonumber(row.server)
  S.serverPfx = (row and row.serverEst) and APPROX or ""
  if server then
    Card(2, L.TT_SERVER, S.serverPfx .. Fmt.DurationFull(server), L.LV_SERVER_SUB)
    S.kServer = Fmt.DurationFullKey(server)
  else
    Card(2, L.TT_SERVER, L.DOTS, L.LV_SERVER_SUB)
    S.kServer = -1
  end
  S.serverLive = ctx.kind == "cur" and S.isCur and server ~= nil
  FillEta(row, ctx, t)
  -- Total since level 1 (until the next level was reached: "level 1 » 19", the title's
  -- arrow; the level in progress: up to now, "level 1 » 19, in progress"), XP per hour,
  -- deaths
  local cum = row and tonumber(row.cum)
  Card(4, L.LD_CUM, cum and Fmt.DurationFull(cum) or L.DOTS,
    format(ctx.kind == "cur" and L.LD_CUM_SUB_CUR_FMT or L.LD_CUM_SUB_FMT, level + 1))
  S.kCum = cum and Fmt.DurationFullKey(cum) or -1
  local xph = row and tonumber(row.xph)
  Card(5, L.TT_XPH, xph and Fmt.Rate(xph) or L.DOTS, "")
  DeathsCard(row and math_floor(Num(row.deaths)) or 0, row and Num(row.dead) or 0)
  for i = 1, #CARD_KEYS do
    local c = cards[i]
    Place(c.frame, PAD + ((i - 1) % 2) * (CARD_W + CARD_GAP), y + math_floor((i - 1) / 2) * (CARD_H + CARD_GAP))
    Vis(c.frame, true)
  end
  return y + 3 * CARD_H + 2 * CARD_GAP
end

local function HideCards()
  for i = 1, #cards do Vis(cards[i].frame, false) end
end

-- Parts of the level under the mask (val[1..NSEG]) and its total; the level in progress
-- (cur) gets its shown time t's excess over its parts in "untracked" (as its bar).
local function ReadParts(char, level, cur, t)
  local levels = char.levels
  local lb = type(levels) == "table" and levels[level] or nil
  if type(lb) ~= "table" then lb = nil end
  ns.Stats.LevelSegments(lb, S.mask, segOut)
  local sum = 0
  for i = 1, NSEG do
    local v = Num(segOut[SEG_KEYS[i]])
    val[i] = v
    sum = sum + v
  end
  if cur and t > sum then
    val[P_UNTRACKED] = val[P_UNTRACKED] + (t - sum)
    sum = t
  end
  return sum
end

-- Rows of the breakdown: the categories of at least a second (Flight always), longest
-- first (ties: the fixed order); returns their count.
local function SortCats()
  local n = 0
  for c = 1, NCAT do
    local v = val[CAT_PART[c]]
    if c == CAT_PVP then v = v + val[P_WPVP] end
    catVal[c] = v
    if v >= 1 or c == CAT_FLIGHT then
      n = n + 1
      local j = n
      while j > 1 and catVal[order[j - 1]] < v do
        order[j] = order[j - 1]
        j = j - 1
      end
      order[j] = c
    end
  end
  for j = n + 1, #order do order[j] = nil end
  return n
end

-- The breakdown's total, bar and rows from val[1..NSEG] (the bar at S.barY, the rows from
-- S.rowsY): a row is a slot (its category may change when the order does); the total's
-- and each row's value and percent strings are built only when their key changed (force,
-- a Show: always), the bar's parts only resized when a pixel changed. Live (no force)
-- returns false, drawing no row, when the count of rows changed: the sections below move.
local function DrawTime(total, force)
  local key = Fmt.DurationFullKey(total)
  if force or key ~= S.kTotal then
    S.kTotal = key
    Text(TM.right, format(L.LD_TOTAL_FMT, Fmt.DurationFull(total)))
  end
  DrawBar(TM.segs, NSEG, val, total, PAD, S.barY, "barSig", TM.roles)
  local n = SortCats()
  if not force and n ~= TM.n then return false end
  S.pvpRow = nil
  for j = 1, n do
    local c = order[j]
    local r = TM.rows[j] or NewRow(j)
    local v = catVal[c]
    local ry = S.rowsY + (j - 1) * ROW_H
    Paint(r.sq, CAT_PART[c], 1)
    Place(r.sq, PAD, ry + 4)
    Text(r.label, L[CAT_LABEL[c]])
    Place(r.label, PAD + SQ + 7, ry + 1)
    Text(r.hint, c == CAT_PVP and L.LD_HOVER or "")
    key = DashKey(v)
    if force or key ~= r.kv then
      r.kv = key
      DurFit(r.value, v)
    end
    Place(r.value, PAD + IW - PCT_W - VAL_W, ry + 1)
    -- percent of the total (memoized strings); a share that rounds to 0 reads "<1%"
    key = (v >= 1 and total > 0) and math_floor(v / total * 100 + 0.5) or -1
    if force or key ~= r.kp then
      r.kp = key
      local p = ""
      if key > 0 then
        p = Fmt.PercentInt(key)
      elseif key == 0 then
        p = format(L.LV_LT_FMT, Fmt.PercentInt(1))
      end
      Text(r.pct, p)
    end
    Place(r.pct, PAD + IW - PCT_W, ry + 2)
    r.cat = c
    RowVis(r, true)
    if c == CAT_PVP then
      S.pvpRow = j
      local hit = pvpHit or NewPvpHit()
      Place(hit, PAD - 4, ry)
      Vis(hit, true)
    end
  end
  for j = n + 1, #TM.rows do
    local r = TM.rows[j]
    RowVis(r, false)
    r.cat = nil
  end
  if pvpHit and not S.pvpRow then Vis(pvpHit, false) end
  TM.n, TM.pvp, TM.total = n, S.pvpRow, total
  return true
end

local function FillTime(char, level, ctx, y)
  if not TM.title then
    NewHead(TM, true)
    TM.track = NewTex("ARTWORK", 0)
    TM.track:SetSize(IW, BAR_H)
    TM.roles = {}
    for i = 1, NSEG do TM.roles[i] = i end
  end
  Text(TM.title, L.LD_TIME)
  Place(TM.title, PAD, y)
  Place(TM.right, PAD, y + 1)
  Vis(TM.title, true)
  Vis(TM.right, true)
  y = y + HEAD_H
  Place(TM.track, PAD, y)
  Paint(TM.track, "bg", 1)
  Vis(TM.track, true)
  S.barY, S.rowsY = y, y + BAR_H + 6
  DrawTime(ReadParts(char, level, ctx.kind == "cur", S.time), true)
  return S.rowsY + TM.n * ROW_H
end

local function HideTime()
  if not TM.title then return end
  Vis(TM.title, false)
  Vis(TM.right, false)
  Vis(TM.track, false)
  HideBar(TM.segs, NSEG, "barSig")
  for j = 1, #TM.rows do RowVis(TM.rows[j], false) end
  if pvpHit then Vis(pvpHit, false) end
  TM.n, TM.pvp, S.pvpRow = 0, nil, nil
end

local function FillXP(char, level, ctx, y)
  if not XP.title then
    NewHead(XP, true)
    XP.track = NewTex("ARTWORK", 0)
    XP.track:SetSize(IW, BAR_H)
    for i = 1, 3 do
      local c = {}
      c.sq = NewTex("ARTWORK", 0)
      c.sq:SetSize(8, 8)
      c.label = NewText(content, 10, "LEFT", "label")
      c.label:SetWidth(XCOL_W - 12)
      c.value = NewText(content, 12, "LEFT", "value")
      c.value:SetWidth(XCOL_W)
      c.pct = NewText(content, 10, "LEFT", "dim")
      c.pct:SetWidth(XCOL_W)
      XP.cols[i] = c
    end
  end
  local row = ctx.row
  local gained, size
  if ctx.kind == "cur" and tonumber(ctx.xp) and tonumber(ctx.max) and Num(ctx.max) > 0 then
    gained, size = Num(ctx.xp), Num(ctx.max)
  else
    gained = row and Num(row.xp) or 0
    size = (row and tonumber(row.max)) or ns.Stats.XPOf(char, ns.db, level)
  end
  Text(XP.title, L.LD_XP)
  Text(XP.right, format(L.LD_XP_FMT, Fmt.Number(gained), size and Fmt.Number(size) or L.DOTS))
  Place(XP.title, PAD, y)
  Place(XP.right, PAD, y + 1)
  y = y + HEAD_H
  Place(XP.track, PAD, y)
  Paint(XP.track, "bg", 1)
  local parts = XP.values
  if not parts then
    parts = { 0, 0, 0 }
    XP.values = parts
  end
  local total = 0
  for i = 1, 3 do
    local v = row and math_max(0, Num(row[XP_PARTS[i]])) or 0
    parts[i] = v
    total = total + v
  end
  DrawBar(XP.segs, 3, parts, total, PAD, y, "xpSig", XP_PARTS)
  y = y + BAR_H + 6
  for i = 1, 3 do
    local c = XP.cols[i]
    local x = PAD + (i - 1) * (XCOL_W + 8)
    Paint(c.sq, XP_PARTS[i], 1)
    Place(c.sq, x, y + 2)
    Text(c.label, L[XP_LABEL[i]])
    Place(c.label, x + 12, y)
    Text(c.value, Fmt.Number(parts[i]))
    Place(c.value, x, y + 13)
    Text(c.pct, total > 0 and Fmt.Percent(parts[i] / total) or "")
    Place(c.pct, x, y + 28)
    ColVis(c, true)
  end
  Vis(XP.title, true)
  Vis(XP.right, true)
  Vis(XP.track, true)
  XP.total, XP.gained, XP.size = total, gained, size
  return y + XCOL_H
end

local function HideXP()
  if not XP.title then return end
  Vis(XP.title, false)
  Vis(XP.right, false)
  Vis(XP.track, false)
  HideBar(XP.segs, 3, "xpSig")
  for i = 1, 3 do ColVis(XP.cols[i], false) end
end

local function ZoneRow(j, name, secs, part, maxSecs, y)
  local z = ZN.rows[j] or NewZoneRow(j)
  Text(z.name, name)
  Role(z.name, secs > 0 and "value" or "dim")
  if Grows() then Text(z.time, Rough(secs)) else DurFit(z.time, secs) end
  Place(z.name, PAD, y)
  Place(z.time, PAD + IW - VAL_W, y)
  Paint(z.bar, part, 1)
  Place(z.bar, PAD, y + 15)
  local w = (maxSecs > 0) and math_floor(secs / maxSecs * (IW - VAL_W - 8) + 0.5) or 0
  if w < 2 then w = 2 end
  Width(z.bar, w)
  Vis(z.name, true)
  Vis(z.time, true)
  Vis(z.bar, secs > 0)
  z.secs = secs
  return y + ZONE_H
end

-- The zones of the level (its instances aside), then its instances.
local function FillZones(char, level, y)
  if not ZN.title then
    NewHead(ZN, false)
    ZN.empty = NewText(content, 11, "LEFT", "dim")
    ZN.empty:SetWidth(IW)
    tp.zonesTitle, tp.zonesEmpty = ZN.title, ZN.empty
  end
  local Stats = ns.Stats
  local levels = char.levels
  local lb = type(levels) == "table" and levels[level] or nil
  local zmap = type(lb) == "table" and lb.z or nil
  local names = type(char.zones) == "table" and char.zones or nil
  Text(ZN.title, L.LD_ZONES)
  Place(ZN.title, PAD, y)
  Vis(ZN.title, true)
  y = y + HEAD_H
  -- every instance of the level is set aside, not only the shown ones (a 6th one would
  -- be listed as an open-world zone): TopInstances under mask 0 (any time) lists them
  -- all, the zone list takes as many more rows; the INST_MAX longest under the mask show
  for k in pairs(instKind) do instKind[k] = nil end
  local nKeys = 0
  if type(zmap) == "table" then
    for _ in pairs(zmap) do nKeys = nKeys + 1 end
  end
  local nAll = Stats.TopInstances(zmap, 0, nKeys, allInst) or 0
  for i = 1, nAll do instKind[allInst[i].key] = allInst[i].kind or "d" end
  local nInst = Stats.TopInstances(zmap, S.mask, INST_MAX, instRows, true) or 0
  local _, nz = Stats.TopZones(zmap, ZONES_MAX + nAll, S.mask, zoneRows)
  nz = math_floor(Num(nz))
  local maxSecs = 0
  for i = 1, nz do
    local r = zoneRows[i]
    if not instKind[r.key] and Num(r.filtered) > maxSecs then maxSecs = Num(r.filtered) end
  end
  for i = 1, nInst do
    if Num(instRows[i].secs) > maxSecs then maxSecs = Num(instRows[i].secs) end
  end
  local n, shown = 0, 0
  for i = 1, nz do
    local r = zoneRows[i]
    if not instKind[r.key] and shown < ZONES_MAX then
      shown, n = shown + 1, n + 1
      local name = Stats.ZoneName(r.key, (names and names[r.key]) or (zmap and zmap[r.key]))
      local part = P_WORLD
      if r.isCity then
        name = name .. " " .. L.CITY_MARK
        part = P_CITY
      end
      y = ZoneRow(n, name, Num(r.filtered), part, maxSecs, y)
    end
  end
  for i = 1, nInst do
    local r = instRows[i]
    local kind = r.kind or "d"
    local name = Stats.ZoneName(r.key, (names and names[r.key]) or (zmap and zmap[r.key]))
    n = n + 1
    y = ZoneRow(n, format(L.INST_ROW_FMT, name, L[KIND_KEY[kind] or "KIND_DUNGEON"]), Num(r.secs),
      KIND_PART[kind] or P_DUNGEON, maxSecs, y)
  end
  for j = n + 1, #ZN.rows do ZoneVis(ZN.rows[j], false) end
  ZN.n, tp.nZones = n, n
  if n == 0 then
    Text(ZN.empty, L.ROW_ZONES_EMPTY)
    Place(ZN.empty, PAD, y)
    Vis(ZN.empty, true)
    y = y + NOTE_SIZE + 2
  else
    Vis(ZN.empty, false)
  end
  return y
end

local function HideZones()
  if not ZN.title then return end
  Vis(ZN.title, false)
  Vis(ZN.empty, false)
  for j = 1, #ZN.rows do ZoneVis(ZN.rows[j], false) end
  ZN.n, tp.nZones = 0, 0
end

-- An upcoming level: its estimate, its basis, its XP and when it would be done.
local function FillUpcoming(char, level, ctx, y)
  if not UP.frame then
    local f = NewBox()
    f:SetSize(IW, UP_H)
    UP.frame = f
    UP.label = NewText(f, 11, "LEFT", "label")
    UP.label:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -7)
    UP.value = NewText(f, 18, "LEFT", "value")
    UP.value:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -21)
    UP.sub = NewText(f, 10, "LEFT", "dim")
    UP.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -42)
    UP.label:SetWidth(IW - 20)
    UP.value:SetWidth(IW - 20)
    UP.sub:SetWidth(IW - 20)
    UP.xp = NewText(content, 12, "LEFT", "label")
    UP.xp:SetWidth(IW)
    UP.reach = NewText(content, 12, "LEFT", "label")
    UP.reach:SetWidth(IW)
  end
  local est = Num(ctx.est)
  local fut = ctx.fut
  Text(UP.label, L.LD_EST_DUR)
  Text(UP.value, est > 0 and Fmt.ETA(est) or L.DOTS)
  -- the basis: the recent levels' pace, else (src "rate": too few complete levels) the XP rate
  Text(UP.sub, (type(fut) == "table" and fut.src == "recent") and L.LD_EST_SUB or L.LD_EST_SUB_RATE)
  Place(UP.frame, PAD, y)
  y = y + UP_H + 8
  local xp = ns.Stats.XPOf(char, ns.db, level)
  Text(UP.xp, xp and format(L.LV_XP_EARN_FMT, Fmt.Number(xp)) or "")
  Place(UP.xp, PAD, y)
  -- the play time until this level is done: what is left of the current one, then the
  -- estimates of the levels up to this one
  local sum, known = 0, type(fut) == "table" and fut.cur ~= nil
  if known then
    sum = Num(fut.cur)
    for l = math_floor(Num(ctx.level)) + 1, level do
      local e = fut[l]
      if e == nil then
        known = false
        break
      end
      sum = sum + Num(e)
    end
  end
  Text(UP.reach, known and format(L.LD_REACH_FMT, Fmt.Duration(sum)) or "")
  Place(UP.reach, PAD, y + 17)
  Vis(UP.frame, true)
  Vis(UP.xp, true)
  Vis(UP.reach, true)
  UP.sum = known and sum or nil
  return y + 17 + 14
end

local function HideUpcoming()
  if not UP.frame then return end
  Vis(UP.frame, false)
  Vis(UP.xp, false)
  Vis(UP.reach, false)
end

local function FillNoRecord(y)
  if not norecFS then
    norecFS = NewWrap(12, "label")
    tp.norec = norecFS
  end
  Text(norecFS, L.LD_NO_RECORD)
  Place(norecFS, PAD, y)
  Vis(norecFS, true)
  return y + WrapHeight(norecFS, 12)
end

---------------------------------------------------------------------------
-- PvP row tooltip (LevelChart's one-shot helper)
---------------------------------------------------------------------------

OnPvpEnter = function(self)
  local char, level = S.char, S.level
  local LC = ns.LevelChart
  if not char or not LC or not LC.TipBegin then return end
  local Stats = ns.Stats
  local levels = char.levels
  local lb = type(levels) == "table" and levels[level] or nil
  Stats.LevelSegments(type(lb) == "table" and lb or nil, S.mask, segOut)
  local bg, wp = Num(segOut.bg), Num(segOut.wpvp)
  local n, other = Stats.LevelBattlegrounds(char, level, NoAfk(S.mask), bgRows)
  n, other = math_floor(Num(n)), Num(other)
  local avail = PvpAvailable()
  local st = avail and Stats.WorldPvpState(char, level) or "no"
  local measured = avail and st ~= "no"
  LC.TipBegin(self)
  LC.TipRow("title", format(L.LD_PVP_TIP_FMT, DurOrDash(bg + wp)), nil, "title")
  LC.TipRow("pair", L.LV_SEG_BG, DurOrDash(bg), SEGC[P_BG], "value")
  for i = 1, n do
    local r = bgRows[i]
    if i > BG_ROWS then
      other = other + Num(r.secs)
    else
      LC.TipRow("pair", "   " .. tostring(r.name), Fmt.DurationFull(Num(r.secs)), "label", "value")
    end
  end
  if other >= 60 then LC.TipRow("pair", "   " .. L.LV_BG_OTHER, Fmt.DurationFull(other), "label", "value") end
  LC.TipRow("pair", L.LV_WPVP_LONG, measured and DurOrDash(wp) or L.DOTS, SEGC[P_WPVP], "value")
  LC.TipSep("block")
  LC.TipRow("wrap", format(L.LV_WPVP_DEF_FMT, math_floor(Num(C.PVP_IDLE) / 60 + 0.5)), nil, "dim", nil, true)
  local note
  if not avail then
    note = L.LV_WPVP_NO_CLIENT
  elseif st == "no" then
    note = L.LV_WPVP_BEFORE
  elseif st == "partial" then
    note = L.LV_WPVP_PARTIAL
  else
    note = format(L.LV_WPVP_SINCE_FMT, Fmt.DateTime(char.pvp.w0))
  end
  LC.TipRow("wrap", note, nil, "dim", nil, true)
  LC.TipShow(self, "TOPLEFT", "BOTTOMLEFT", 20, -2)
end

OnPvpLeave = function(self)
  local LC = ns.LevelChart
  if LC and LC.TipHide then LC.TipHide(self) end
end

---------------------------------------------------------------------------
-- Public API (LevelChart.lua)
---------------------------------------------------------------------------

-- Lays the sheet of `level` out from ctx, t = its shown seconds (Show; Live again when the
-- breakdown gains or loses a row: the sections below move).
local function Lay(char, level, ctx, t)
  local kind = ctx.kind
  if level ~= S.level or char ~= S.char or kind ~= S.kind then
    scroll:SetVerticalScroll(0)       -- another sheet: from its top
  end
  local row = ctx.row
  S.char, S.level, S.kind, S.ctx, S.time = char, level, kind, ctx, t
  S.isCur, S.mask, S.fut = ctx.isCur and true or false, ctx.mask or 0, ctx.fut
  S.estOK = ctx.status == "ok" or ctx.status == "estimate"
  S.approx = row ~= nil and (row.partial or row.rec or Num(row.estF) > 0 or Num(row.gap) > 0) and true or false
  S.kTime, S.kServer, S.kCum, S.kEst, S.kLeft = -1, -1, -1, -1, -1
  Text(titleFS, format(L.LEVEL_SPAN_FMT, level, level + 1))
  local status, role = StatusOf(ctx)
  Text(statusFS, status)
  Role(statusFS, role)
  Place(statusFS, PAD, PAD + TITLE_SIZE + 5)
  local played = (kind == "done" or kind == "cur")
  local y = FillNotes(played and row or nil, PAD + TITLE_SIZE + 5 + STATUS_SIZE)
  if played then
    y = FillCards(level, ctx, y + GAP)
    y = FillTime(char, level, ctx, y + GAP)
    y = FillXP(char, level, ctx, y + GAP)
    y = FillZones(char, level, y + GAP)
  else
    HideCards()
    HideTime()
    HideXP()
    HideZones()
  end
  if kind == "future" then
    y = FillUpcoming(char, level, ctx, y + GAP)
  else
    HideUpcoming()
  end
  if kind == "none" then
    y = FillNoRecord(y + GAP)
  elseif norecFS then
    Vis(norecFS, false)
  end
  local h = math_ceil(y + PAD)
  if content:GetHeight() ~= h then content:SetHeight(h) end
  panel:Show()
  tp.level, tp.kind, tp.height = level, kind, h
end

function LevelDetail.Show(parent, char, level, ctx)
  if parent == nil or type(char) ~= "table" or type(ctx) ~= "table" then return tp end
  if not panel then Create(parent) end
  local py, ph = math_floor(Num(ctx.y)), math_floor(Num(ctx.h))
  if py ~= S.placedY or ph ~= S.placedH then
    S.placedY, S.placedH = py, ph
    panel:ClearAllPoints()
    panel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -py)
    panel:SetSize(W, ph)
    scroll:SetSize(CW, math_max(1, ph - 2))
  end
  Lay(char, math_floor(Num(level)), ctx, Num(ctx.time))
  return tp
end

-- Live step of the selected level in progress of the current character: its time
-- breakdown, its time and Deaths cards (strings only when a key changes).
function LevelDetail.Live(char, mask, sync, now)
  if S.kind ~= "cur" or not S.isCur or char ~= S.char or mask ~= S.mask or not panel or not panel:IsShown() then
    return
  end
  local Stats = ns.Stats
  local level = S.level
  local t = Num((Stats.LevelTime(char, level, mask, sync, now)))
  -- the breakdown first: a row more or less lays the sheet out again (its cards too)
  if not DrawTime(ReadParts(char, level, true, t), false) then Lay(char, level, S.ctx, t) end
  local key = Fmt.DurationFullKey(t)
  if key ~= S.kTime then
    S.kTime = key
    local d = Fmt.DurationFull(t)
    Text(cards[1].value, S.approx and (APPROX .. d) or d)
  end
  if S.serverLive then
    -- the card's rule (the level row's server, Stats.LevelServer): the sync's level part,
    -- else its total less the level's server start, both growing
    local srv = Stats.LevelServer(char, level, sync, now)
    if srv then
      key = Fmt.DurationFullKey(srv)
      if key ~= S.kServer then
        S.kServer = key
        local d = Fmt.DurationFull(srv)
        Text(cards[2].value, S.serverPfx ~= "" and (S.serverPfx .. d) or d)
      end
    end
  end
  local played = Num((Stats.Played(char, mask, sync, now)))
  key = Fmt.DurationFullKey(played)
  if S.kCum ~= -1 and key ~= S.kCum then
    S.kCum = key
    Text(cards[4].value, Fmt.DurationFull(played))
  end
  local fut = S.fut
  if S.estOK and type(fut) == "table" and fut.cur ~= nil then
    local left = Num(fut.cur)
    key = Fmt.ETAKey(t + left)
    if key ~= S.kEst then
      S.kEst = key
      Text(cards[3].value, Fmt.ETA(t + left))
    end
    key = Fmt.DurationKey(left)
    if key ~= S.kLeft then
      S.kLeft = key
      Text(cards[3].sub, format(L.LD_LEFT_FMT, Fmt.Duration(left)))
    end
  end
  -- a death and the dead time (segOut: the level's parts just read)
  local levels = char.levels
  local lb = type(levels) == "table" and levels[level] or nil
  local deaths = type(lb) == "table" and math_floor(Num(lb.d)) or 0
  local dead = Num(segOut.dead)
  if deaths ~= S.kDeaths or DashKey(dead) ~= S.kDead then DeathsCard(deaths, dead) end
end

function LevelDetail.Hide()
  if panel then panel:Hide() end
end

-- Theme switch: colours and fonts again (texts set again by the next Show).
function LevelDetail.ApplyTheme(ui)
  ReadColors(ui)
  if not panel then return end
  for i = 1, #styled do
    local fs = styled[i]
    SetFontOf(fs, sizeOf[fs])
  end
  for fs in pairs(txt) do txt[fs] = nil end
  Repaint()
end

-- A recolour (the user's XP / rested colours: THEME_CHANGED "colors", Window.lua): the
-- colours read again and painted, the texts kept (no rebuild).
function LevelDetail.Recolor()
  ReadColors(nil)
  if panel then Repaint() end
end

function LevelDetail.Owns(owner)
  return owner ~= nil and own[owner] == true
end
