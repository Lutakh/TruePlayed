local ADDON, ns = ...
local L, Util = ns.L, ns.Util

-- PvpOptions.lua - the "PvP" options: a page of its own, a second subcategory of
-- TruePlayed's in the game's Settings (Options.Init registers it after the reputation's:
-- Options.RegisterPvpSub), or a section of the single panel after the reputation's when
-- the client cannot register one (Options.BuildPvpSection). Built on its first show with
-- Options.lua's controls (Options.UI), which keep their records in the same list:
-- Options.Refresh syncs every page, the listeners and Options.IsShown cover this one too
-- (AutoReload: no reload without a click while it is shown). The content, each control
-- with its "?":
--   * "Strip under the bar" (widget.pvp): None / Honor / Rank (Pvp.lua; under the
--     reputation's strip when both show; not drawn when it would repeat the PvP main bar);
--   * "Main bar" (widget.main, the same setting as the reputation page's dropdown:
--     Options.MainChoices): Experience / Reputation / PvP;
--   * "PvP on the bar in battlegrounds" (widget.pvpAuto): a temporary override while in a
--     battleground, widget.main untouched;
--   * "Alert when the honor is capped" (pvp.capAlert);
--   * "Honor and rank per hour": a "Reset" button (Pvp.ResetRate; /tpl reset rate resets
--     every rate), record kind "button", path "pvp.resetRate"; read-only mode refuses it.
-- On a client without the PvP APIs (Classic Era) the page holds a short note only.

local format = string.format
local CreateFrame = CreateFrame

local Options = ns.Options
if not Options then return end

local page = nil                  -- the page's canvas frame (Settings subcategory)
local subOk = false               -- the subcategory is registered
local built, shown = false, false
local readOnlyNote = nil

local function Pvp()
  return ns.Pvp
end

local function Available()
  local P = Pvp()
  return P ~= nil and P.Available()
end

local function OnResetRate()
  if Options.UI.ReadOnlyRefused() then return end
  local P = Pvp()
  if P and P.ResetRate() then Util.Print(L.PVP_RESET_RATE_DONE) end
end

local function SyncNothing() end

-- The choices of widget.main: RepOptions.lua's (Options.MainChoices), else the same here.
local function MainChoices()
  if Options.MainChoices then return Options.MainChoices() end
  return { { value = "xp", label = L.REP_MAIN_XP }, { value = "rep", label = L.REP_MAIN_REP },
           { value = "pvp", label = L.REP_MAIN_PVP } }
end

-- The controls (into the current canvas: this page's, or the single panel's section).
local function BuildControls(UI)
  if not Available() then
    UI.AddNote(L.OPT_PVP_UNAVAILABLE)
    return
  end
  UI.AddNote(L.OPT_PVP_PAGE_NOTE)
  UI.AddHelp(UI.AddDropdown(L.OPT_PVP_STRIP, "widget.pvp", {
    { value = "off", label = L.PVP_STRIP_OFF }, { value = "honor", label = L.PVP_STRIP_HONOR },
    { value = "rank", label = L.PVP_STRIP_RANK },
  }), "pvpStrip")
  UI.AddHelp(UI.AddDropdown(L.OPT_REP_MAIN, "widget.main", MainChoices()), "pvpMain")
  UI.AddHelp(UI.AddCheckbox(L.OPT_PVP_AUTO, "widget.pvpAuto"), "pvpAuto")
  UI.AddHelp(UI.AddCheckbox(L.OPT_PVP_ALERT, "pvp.capAlert"), "pvpAlert")
  local label = UI.AddLabel(L.OPT_PVP_RESET_LABEL)
  local b = UI.MakeButton(UI.Content(), L.OPT_PVP_RESET_RATE, 170, 22, OnResetRate)
  b:SetPoint("TOPLEFT", UI.Content(), "TOPLEFT", UI.CONTROL_X, UI.Cursor())
  UI.Move(-30)
  UI.AddHelp(UI.Register({ kind = "button", path = "pvp.resetRate", label = label, Sync = SyncNothing }, b),
    "pvpReset")
end

-- The section of the single panel (Options.lua's Build, after the reputation's).
function Options.BuildPvpSection()
  local UI = Options.UI
  UI.AddHeader(L.OPT_PVP_PAGE)
  BuildControls(UI)
end

local function Build()
  built = true
  local UI = Options.UI
  local first = #UI.Controls() + 1
  local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -28, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(UI.CONTENT_W, 100)
  scroll:SetScrollChild(content)
  UI.Canvas(content, -8)
  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", content, "TOPLEFT", UI.LABEL_X - 8, -8)
  title:SetText(L.OPT_PVP_PAGE)
  UI.Move(-20)
  readOnlyNote = UI.AddNote(L.OPT_NOTE_READONLY)
  local pc = ns.C.COLORS.pause
  readOnlyNote:SetTextColor(pc[1], pc[2], pc[3])
  BuildControls(UI)
  content:SetHeight(-UI.Cursor() + 16)
  -- Read-only handles for the offline tests (our own frame): this page's records.
  local list, byPath = UI.Controls(), {}
  for i = first, #list do byPath[list[i].path] = list[i] end
  page.controls = byPath
end

local function OnShow()
  if not built then Build() end
  shown = true
  Options.Listen(true)
  Options.Refresh()
end

local function OnHide()
  if not shown then return end
  shown = false
  Options.Listen(false)
end

-- Options.Init, with TruePlayed's category: the page as its subcategory (pcall'd: absent
-- or failing, PvP is a section of the main panel instead).
function Options.RegisterPvpSub(category)
  local S = Settings
  if subOk or type(S) ~= "table" or type(S.RegisterCanvasLayoutSubcategory) ~= "function" then return end
  page = CreateFrame("Frame", nil, UIParent)
  page:Hide()
  page:SetScript("OnShow", OnShow)
  page:SetScript("OnHide", OnHide)
  local ok, sub = pcall(S.RegisterCanvasLayoutSubcategory, category, page, L.OPT_PVP_PAGE)
  subOk = ok and sub ~= nil
  if not subOk then
    page:SetScript("OnShow", nil)
    page:SetScript("OnHide", nil)
    page = nil
  end
end

-- PvP has its own page (else a section of the main panel).
function Options.HasPvpPage()
  return subOk
end

function Options.PvpShown()
  return shown
end

-- Options.Refresh, after the controls: the read-only note of this page.
function Options.PvpRefresh()
  if not readOnlyNote then return end
  if ns.readOnly then readOnlyNote:Show() else readOnlyNote:Hide() end
end

-- The "?" of the PvP controls (Options.lua's help icons, Options.HelpLines).
local HelpLines = Options.HelpLines

HelpLines.pvpStrip = function(tt, add)
  add(tt, L.OPT_PVP_STRIP_HELP_WHAT)
  add(tt, L.OPT_PVP_STRIP_HELP_TIP)
  add(tt, L.OPT_PVP_STRIP_HELP_SAME)
end

HelpLines.pvpMain = function(tt, add)
  add(tt, L.OPT_PVP_MAIN_HELP_WHAT)
  add(tt, format(L.OPT_REP_MAIN_HELP_XP_FMT, L.OPT_HIDE_MAX))
  add(tt, L.OPT_PVP_HELP_XP_STRIP)
  add(tt, L.OPT_PVP_MAIN_HELP_SAME)
end

HelpLines.pvpAuto = function(tt, add)
  add(tt, L.OPT_PVP_AUTO_HELP)
  add(tt, L.OPT_PVP_HELP_XP_STRIP)
end

HelpLines.pvpAlert = function(tt, add)
  add(tt, L.OPT_PVP_ALERT_HELP)
end

HelpLines.pvpReset = function(tt, add)
  add(tt, format(L.OPT_PVP_RESET_HELP_FMT, ns.Fmt.Duration(ns.C.PVP_IDLE)))
  add(tt, L.OPT_PVP_RESET_HELP_PAUSE)
end
