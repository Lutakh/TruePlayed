local ADDON, ns = ...
local L, Util = ns.L, ns.Util

-- RepOptions.lua - the "Reputation" options: a page of its own, a subcategory of
-- TruePlayed's in the game's Settings (Options.Init registers it: Options.RegisterSub), or
-- a section of the single panel after Display when the client cannot register one (the
-- standalone panel, an older Settings API: Options.BuildRepSection). Built on its first
-- show with Options.lua's controls (Options.UI), which keep their records in the same
-- list: Options.Refresh syncs both pages, the listeners and Options.IsShown cover both
-- (AutoReload: no reload without a click while either is shown). The content:
--   * "Show the reputation under the bar" (widget.rep), with its "?" (moved from Display,
--     which keeps a pointer note when this page exists). With Reputation as the main bar
--     the strip shows the XP whatever the box: greyed out, with a note saying so (the note
--     alone with PvP as the main bar: the box still shows the reputation's strip at the
--     max level, and its tooltip line);
--   * "Main bar" (widget.main): Experience / Reputation / PvP (what the bar's main track
--     shows; PvP only where the client has it: Options.MainChoices, shared with the PvP
--     page, PvpOptions.lua), with its "?";
--   * "Faction to follow": this character's choice (Reputation.lua, char.rep.id). The first
--     entry is the game's watched faction ("auto", the default); then the game's factions
--     under their headers (one submenu each), "Name (Standing)". The list is read when
--     the menu is generated (Rep.ListFactions: the collapsed headers of the game's list
--     expanded, read, collapsed again); a chosen faction missing from it keeps an entry.
--     TruePlayed never changes the game's watched faction. Without MenuUtil (or the
--     dropdown template): a button cycling through the same choices (right-click:
--     backwards). Record kind "faction", path "rep.faction"; read-only mode refuses a
--     change (L.READONLY_ACTION), like the data actions;
--   * "Reset the reputation rate" (Rep.ResetRate: the reputation's alone; the main page's
--     button and /tpl reset rate reset every rate), record kind "button", path
--     "rep.resetRate".

local type, format = type, string.format
local CreateFrame = CreateFrame

local Options = ns.Options
if not Options then return end

local page = nil                  -- the page's canvas frame (Settings subcategory)
local subOk = false               -- the subcategory is registered
local built, shown = false, false
local readOnlyNote = nil
local faction = nil               -- the faction picker's record
local SCROLL_H = 420              -- px of a long faction menu before it scrolls

local function Rep()
  return ns.Rep
end

-- Name of standing r (the game's, Tooltip.StandingName).
local function Standing(r)
  local Tt = ns.Tooltip
  if r ~= nil and Tt and Tt.StandingName then return Tt.StandingName(r) end
  return nil
end

-- 0: the game's watched faction (auto); else the chosen factionID.
local function Current()
  local R = Rep()
  return R and R.Chosen() or 0
end

-- Text of the current choice (the cycle button; the dropdown shows its selected radio).
local function CurrentLabel()
  local id = Current()
  if id == 0 then return L.OPT_REP_FACTION_AUTO end
  local R = Rep()
  local name, react = R.Get()
  local _, _, _, _, fid, src = R.Detail()
  if name ~= nil and src == "chosen" and fid == id then
    local st = Standing(react)
    if st then return format(L.OPT_REP_FACTION_FMT, name, st) end
    return name
  end
  return format(L.OPT_REP_FACTION_MISSING_FMT, id)
end

local function ItemLabel(it)
  local st = Standing(it.reaction)
  if st then return format(L.OPT_REP_FACTION_FMT, it.name, st) end
  return it.name
end

-- Chooses id (0: the game's watched faction) for this character.
local function Pick(id)
  if Options.UI.ReadOnlyRefused() then return end
  local R = Rep()
  if not R then return end
  R.SetChosen(id ~= 0 and id or nil)
  Options.Refresh()
end

local function IsPicked(id)
  return Current() == id
end

local function SetMenuScroll(desc)
  if type(desc.SetScrollMode) == "function" then desc:SetScrollMode(SCROLL_H) end
end

-- The menu: auto first, then one submenu per header of the game's list (the factions
-- before the first header, if any, at the top level), a chosen faction missing from the
-- list last.
local function Generate(_, root)
  root:CreateRadio(L.OPT_REP_FACTION_AUTO, IsPicked, Pick, 0)
  local R = Rep()
  if not R then return end
  local groups = R.ListFactions()
  local chosen = Current()
  local seen = chosen == 0
  for g = 1, #groups do
    local grp = groups[g]
    local parent = root
    if grp.name then
      parent = root:CreateButton(grp.name)
      SetMenuScroll(parent)
    end
    local items = grp.items
    for i = 1, #items do
      local it = items[i]
      if it.id == chosen then seen = true end
      parent:CreateRadio(ItemLabel(it), IsPicked, Pick, it.id)
    end
  end
  if not seen then root:CreateRadio(format(L.OPT_REP_FACTION_MISSING_FMT, chosen), IsPicked, Pick, chosen) end
  SetMenuScroll(root)
end

-- Modern dropdown: the menu generated again when the choice changed (another character,
-- a pick); the walk of the game's list runs then, and when the menu opens.
local function SyncModern(rec)
  local cur = Current()
  if cur == rec.last then return end
  rec.last = cur
  local dd = rec.widget
  if type(dd.GenerateMenu) == "function" then dd:GenerateMenu() end
end

-- Cycle button: the choices in the menu's order, read at the click.
local function OnCycleClick(_, button)
  local R = Rep()
  if not R then return end
  local ids = { 0 }
  local groups = R.ListFactions()
  for g = 1, #groups do
    local items = groups[g].items
    for i = 1, #items do ids[#ids + 1] = items[i].id end
  end
  local cur, at = Current(), 1
  for i = 1, #ids do
    if ids[i] == cur then at = i end
  end
  at = at + ((button == "RightButton") and -1 or 1)
  if at < 1 then at = #ids elseif at > #ids then at = 1 end
  Pick(ids[at])
  faction.Sync(faction)
end

local function SyncCycle(rec)
  Options.UI.SetButtonText(rec.widget, CurrentLabel())
end

local function AddFaction(UI)
  local label = UI.AddLabel(L.OPT_REP_FACTION)
  local rec = { kind = "faction", path = "rep.faction", label = label }
  local parent = UI.Content()
  local widget
  if MenuUtil and UI.HasTemplate("WowStyle1DropdownTemplate") then
    widget = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    widget:SetWidth(220)
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTROL_X, UI.Cursor())
    rec.Sync = SyncModern
    rec.modern = true
    widget:SetupMenu(Generate)
    rec.last = Current()                -- SetupMenu generated the menu for this choice
  else
    widget = UI.MakeButton(parent, "", 220, 22, OnCycleClick)
    widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widget:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTROL_X, UI.Cursor())
    rec.Sync = SyncCycle
  end
  UI.Move(-30)
  faction = UI.Register(rec, widget)
  return faction
end

local function OnResetRate()
  if Options.UI.ReadOnlyRefused() then return end
  local R = Rep()
  if R and R.ResetRate() then Util.Print(L.REP_RESET_RATE_DONE) end
end

local function SyncNothing() end

-- The strip's box (Options.lua's checkbox record, its own Sync kept as SyncBase): greyed
-- out with Reputation as the main bar, the note shown with Reputation or PvP there.
local function SyncStrip(rec)
  local s = ns.settings
  local w = type(s) == "table" and s.widget or nil
  local main = type(w) == "table" and w.main or "xp"
  rec.disabled = main == "rep"
  rec.SyncBase(rec)
  local K = ns.C.COLORS
  local c = rec.disabled and K.dim or K.value
  rec.label:SetTextColor(c[1], c[2], c[3])
  if main == "rep" or main == "pvp" then rec.note:Show() else rec.note:Hide() end
end

-- The choices of widget.main (a new list per dropdown): PvP where the client has it.
function Options.MainChoices()
  local list = { { value = "xp", label = L.REP_MAIN_XP }, { value = "rep", label = L.REP_MAIN_REP } }
  local P = ns.Pvp
  if P and P.Available() then list[#list + 1] = { value = "pvp", label = L.REP_MAIN_PVP } end
  return list
end

-- The controls (into the current canvas: this page's, or the single panel's section).
local function BuildControls(UI)
  local strip = UI.AddCheckbox(L.OPT_REP, "widget.rep")
  UI.AddHelp(strip, "rep")
  strip.note = UI.AddNote(L.OPT_REP_STRIP_MAIN_NOTE)
  strip.note:Hide()
  strip.SyncBase, strip.Sync = strip.Sync, SyncStrip
  UI.AddHelp(UI.AddDropdown(L.OPT_REP_MAIN, "widget.main", Options.MainChoices()), "repMain")
  UI.AddHelp(AddFaction(UI), "repFaction")
  UI.AddNote(L.OPT_REP_FACTION_NOTE)
  local b = UI.MakeButton(UI.Content(), L.OPT_REP_RESET_RATE, 260, 22, OnResetRate)
  b:SetPoint("TOPLEFT", UI.Content(), "TOPLEFT", UI.LABEL_X, UI.Cursor())
  UI.Move(-30)
  UI.Register({ kind = "button", path = "rep.resetRate", Sync = SyncNothing }, b)
end

-- The section of the single panel (Options.lua's Build, after Display).
function Options.BuildRepSection()
  local UI = Options.UI
  UI.AddHeader(L.OPT_REP_PAGE)
  UI.AddNote(L.OPT_REP_PAGE_NOTE)
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
  title:SetText(L.OPT_REP_PAGE)
  UI.Move(-20)
  readOnlyNote = UI.AddNote(L.OPT_NOTE_READONLY)
  local pc = ns.C.COLORS.pause
  readOnlyNote:SetTextColor(pc[1], pc[2], pc[3])
  UI.AddNote(L.OPT_REP_PAGE_NOTE)
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
-- or failing, the reputation is a section of the main panel instead).
function Options.RegisterSub(category)
  local S = Settings
  if subOk or type(S) ~= "table" or type(S.RegisterCanvasLayoutSubcategory) ~= "function" then return end
  page = CreateFrame("Frame", nil, UIParent)
  page:Hide()
  page:SetScript("OnShow", OnShow)
  page:SetScript("OnHide", OnHide)
  local ok, sub = pcall(S.RegisterCanvasLayoutSubcategory, category, page, L.OPT_REP_PAGE)
  subOk = ok and sub ~= nil
  if not subOk then
    page:SetScript("OnShow", nil)
    page:SetScript("OnHide", nil)
    page = nil
  end
end

-- The reputation has its own page (else a section of the main panel).
function Options.HasSubPage()
  return subOk
end

function Options.SubShown()
  return shown
end

-- Options.Refresh, after the controls: the read-only note of this page.
function Options.SubRefresh()
  if not readOnlyNote then return end
  if ns.readOnly then readOnlyNote:Show() else readOnlyNote:Hide() end
end

-- The "?" of the reputation's controls (Options.lua's help icons, Options.HelpLines).
local HelpLines = Options.HelpLines

-- The strip: which faction (the one chosen below, else the game's watched one: the
-- game's own checkbox label, in the client's language), what the strip shows, where the
-- details are.
HelpLines.rep = function(tt, add)
  local game = SHOW_FACTION_ON_MAINSCREEN
  if type(game) ~= "string" or Util.IsSecret(game) or game == "" then game = L.OPT_REP_GAME_CHECK end
  add(tt, format(L.OPT_REP_HELP_WHERE_FMT, game))
  add(tt, L.OPT_REP_HELP_STRIP)
  add(tt, L.OPT_REP_HELP_TIP)
end

HelpLines.repMain = function(tt, add)
  add(tt, L.OPT_REP_MAIN_HELP_WHAT)
  local P = ns.Pvp
  if P and P.Available() then add(tt, L.OPT_PVP_MAIN_HELP_WHAT) end
  add(tt, format(L.OPT_REP_MAIN_HELP_XP_FMT, L.OPT_HIDE_MAX))
  add(tt, L.OPT_REP_MAIN_HELP_NONE)
end

HelpLines.repFaction = function(tt, add)
  local game = SHOW_FACTION_ON_MAINSCREEN
  if type(game) ~= "string" or Util.IsSecret(game) or game == "" then game = L.OPT_REP_GAME_CHECK end
  add(tt, format(L.OPT_REP_FACTION_HELP_AUTO_FMT, game))
  add(tt, L.OPT_REP_FACTION_HELP_CHAR)
  add(tt, L.OPT_REP_FACTION_HELP_RATE)
end
