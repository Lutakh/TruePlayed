local ADDON, ns = ...
local L, C, Util, Fmt = ns.L, ns.C, ns.Util, ns.Fmt

-- Options.lua - options panel (Settings canvas, content built on first show),
-- context menu, slash commands, addon compartment entry points, erase popup,
-- /tpl played and /tpl perf. The whitelisted globals (SPEC 2.2) are defined at
-- file load so they work even if DB_READY never fires (critique #18).
-- The colours (text, XP bar, rested) use the game's colour picker:
-- ColorPickerFrame:SetupColorPickerAndShow when the client has it (10.2.5+ API, Forever),
-- else the older field-based API. The picker is only read when a colour swatch is
-- clicked; one swatch at a time owns it. "Theme colours" under the bar colours puts
-- both bar colours back to the active theme's own (SPEC-themes 5.6): the swatches show
-- Themes.DefaultColor and follow THEME_CHANGED while the panel is shown.
-- The theme (SPEC-themes 5.6) is chosen in Display (first control), in the context
-- menu (Theme submenu) or with /tpl theme [name]; all three share ThemeChoices().
-- The language of the addon (setting "language", C.LANGUAGES) is chosen in Display
-- (after "Hide at max level") or with /tpl lang [value]: either one only offers the
-- languages the client's font can draw (LanguageOffered) and only changes the setting, which Core applies into L at the next UI load (the "Reload UI"
-- button under the dropdown calls ReloadUI). In read-only mode both refuse a change
-- (READONLY_ACTION, like the data actions): nothing would be saved for the reload. The
-- Reload UI button stays a plain reload. Localized strings are read from L at use
-- time, never copied at file load (the language is applied after the files load).

local math_floor, math_abs = math.floor, math.abs
local type, pairs, ipairs, tonumber, pcall = type, pairs, ipairs, tonumber, pcall
local string_gsub, string_find = string.gsub, string.find
local date = date
local table_concat = table.concat
local format, strtrim = format, strtrim
local CreateFrame, UIParent, GetTime = CreateFrame, UIParent, GetTime
local InCombatLockdown, UnitLevel, UnitGUID = InCombatLockdown, UnitLevel, UnitGUID

local Options = {}
ns.Options = Options

---------------------------------------------------------------------------
-- Whitelisted globals, defined at file load (SPEC 2.2, 7.10, 7.12)
---------------------------------------------------------------------------

local function PrintRaw(text)
  if Util and Util.Print then
    Util.Print(text)
  elseif DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage((L.CHAT_PREFIX or "") .. text)
  end
end

local function NotReady()
  PrintRaw(L.NOT_READY)
end

SLASH_TRUEPLAYED1 = "/trueplayed"
SLASH_TRUEPLAYED2 = "/tpl"
if type(SlashCmdList) == "table" then
  SlashCmdList.TRUEPLAYED = function(msg)
    if ns.ready and ns.Options and ns.Options.HandleSlash then
      ns.Options.HandleSlash(msg)
    else
      NotReady()
    end
  end
end

function TruePlayed_OnAddonCompartmentClick(_addonName, mouseButton, _menuButtonFrame)
  if not ns.ready then
    NotReady()
    return
  end
  if mouseButton == "RightButton" then
    if ns.Window then ns.Window.Toggle() end
  else
    if ns.Options then ns.Options.Toggle() end
  end
end

function TruePlayed_OnAddonCompartmentEnter(_addonName, menuButtonFrame)
  if not ns.ready or menuButtonFrame == nil or not ns.Tooltip then return end
  -- the compartment's clicks differ from the bar's (7.10): its own hint line
  ns.Tooltip.ShowFor(menuButtonFrame, L.TT_HINT_COMPARTMENT)
end

function TruePlayed_OnAddonCompartmentLeave(_addonName, menuButtonFrame)
  if menuButtonFrame == nil or not ns.Tooltip then return end
  ns.Tooltip.Hide(menuButtonFrame)
end

if type(StaticPopupDialogs) == "table" then
  StaticPopupDialogs.TRUEPLAYED_ERASE_CHAR = {
    text = "%s",                     -- filled with format(L.CONFIRM_ERASE_CHAR_FMT, name)
    button1 = YES, button2 = NO,     -- replaced by L.ERASE_YES / ERASE_NO at show time
    OnAccept = function(self, data)
      if ns.Core and ns.Core.ResetChar then ns.Core.ResetChar(data) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local CONTENT_W = 600
local LABEL_X, CONTROL_X = 20, 250
local PANEL_W, PANEL_H = 660, 540
local DEC_PATTERNS = { "%.1f", "%.2f", "%.3f" }
local EMPTY_T = {}

local SLIDER_BACKDROP = {
  bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
  edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
  tile = true, tileSize = 8, edgeSize = 8,
  insets = { left = 3, right = 3, top = 6, bottom = 6 },
}
local PANEL_BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BTN_BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }

local EXCLUDE_LABEL = { afk = "MENU_EXCLUDE_AFK", inn = "MENU_EXCLUDE_INN", city = "MENU_EXCLUDE_CITY" }
local TEXT_COLOR_PATH = "widget.textColor"
local XP_COLOR_PATH = "widget.xpColor"
local RESTED_COLOR_PATH = "widget.restedColor"
local BAR_COLORS_RESET = "widget.barColors"       -- record key of the bar colours reset button
local SWATCH_BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }
local STATS_TABS = { levels = true, zones = true, sessions = true }
local THEME_PATH = "theme"

-- Theme choices (SPEC-themes 5.6), in C.THEME_CHOICES order with LITERAL locale keys
-- (the locale test finds them). One table for the options dropdown, the context menu
-- and /tpl theme, built on first use: always after DB_READY, so its labels are in the
-- language Core applied into L (a table built at file load would keep the client's).
local ThemeChoices
do
  local list
  function ThemeChoices()
    if not list then
      list = {
        { value = "futuriste", label = L.THEME_FUTURISTE },
        { value = "actuel", label = L.THEME_ACTUEL },
        { value = "heroic", label = L.THEME_HEROIC },
        { value = "pixel", label = L.THEME_PIXEL },
        { value = "class", label = L.THEME_CLASS },
        { value = "warrior", label = L.THEME_WARRIOR },
        { value = "paladin", label = L.THEME_PALADIN },
        { value = "hunter", label = L.THEME_HUNTER },
        { value = "rogue", label = L.THEME_ROGUE },
        { value = "priest", label = L.THEME_PRIEST },
        { value = "shaman", label = L.THEME_SHAMAN },
        { value = "mage", label = L.THEME_MAGE },
        { value = "warlock", label = L.THEME_WARLOCK },
        { value = "druid", label = L.THEME_DRUID },
      }
    end
    return list
  end
end

-- Short /tpl lang alias of a C.LANGUAGES value, shown by the listing and the help line;
-- the full code is accepted too, in any case (Util.Words lowercases). A value without an
-- alias is listed and typed as its code.
local LANG_ALIAS = { auto = "auto", enUS = "en", frFR = "fr", deDE = "de", esES = "es", esMX = "mx",
                     itIT = "it", ptBR = "pt", ruRU = "ru", koKR = "ko", zhCN = "cn", zhTW = "tw" }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local inited = false
local panel, category, standalone
local built, panelShown = false, false
local deferredOpen = false
local controls = {}               -- array of control records
local recOf = {}                  -- [widget] = control record
local btnText = {}                -- [plain button] = FontString
local resetPath = {}              -- [colour reset button] = setting path it clears
local cityLine, readOnlyNote
local syncing = false
local breakdownOut, breakdownParts = {}, {}
local pickerPrev = nil            -- colour before the colour picker opened (Cancel)
local pickPath = TEXT_COLOR_PATH  -- setting the colour picker writes
local pickR, pickG, pickB = 1, 1, 1   -- colour the picker opened with
local pickerFresh = false         -- nothing picked since the picker opened

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function GetSetting(path)
  return ns.Core.GetSetting(path)
end

local function SetSetting(path, value)
  return ns.Core.SetSetting(path, value)
end

local function HasTemplate(name)
  if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo) then return false end
  local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
  return ok and info ~= nil
end

-- Numbers with a few decimals for /tpl perf, with the localized separator.
local function Dec(v, n)
  local s = format(DEC_PATTERNS[n] or DEC_PATTERNS[1], tonumber(v) or 0)
  local sep = L.DECIMAL_SEP
  if sep ~= "." then s = string_gsub(s, "%.", sep) end
  return s
end

local function CurrentGuid()
  return (ns.char and ns.char.guid) or UnitGUID("player")
end

local function Count(t)
  local n = 0
  if type(t) == "table" then
    for _ in pairs(t) do n = n + 1 end
  end
  return n
end

local function ReadOnlyRefused()
  if ns.readOnly then
    Util.Print(L.READONLY_ACTION)
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Shared actions (slash, menu, options buttons)
---------------------------------------------------------------------------

local function ResetSessionAction()
  if ReadOnlyRefused() then return end
  if ns.Tracker.ResetSession() then Util.Print(L.RESET_SESSION_DONE) end
end

local function ResetRateAction()
  if ReadOnlyRefused() then return end
  if ns.Core.ResetRate() then Util.Print(L.RESET_RATE_DONE) end
end

local function ResetPosAction()
  ns.Bar.ResetPosition()
  Util.Print(L.RESET_POS_DONE)
end

local function CityToggleAction()
  if ReadOnlyRefused() then return end
  local id, state, name = ns.Tracker.ToggleCityForCurrentZone()
  if not id then
    if state == "readonly" then
      Util.Print(L.READONLY_ACTION)
    elseif state == "instance" then
      Util.Print(L.CITY_INSTANCE)
    else
      Util.Print(L.NO_ZONE)
    end
    return
  end
  if type(name) ~= "string" or name == "" then
    local zones = ns.char and ns.char.zones
    name = ns.Stats.ZoneName(id, zones and zones[id])
  end
  Util.Print(state and L.CITY_ADDED_FMT or L.CITY_REMOVED_FMT, name)
end

local function SetExclusion(key, value)
  local path = "exclude." .. key
  if value == nil then value = not GetSetting(path) end
  SetSetting(path, value and true or false)
  Util.Print(L.EXCL_STATE_FMT, L[EXCLUDE_LABEL[key]], value and L.ON or L.OFF)
end

-- Display name of a theme setting value; nil for a value that is not a choice.
local function ThemeLabel(value)
  local choices = ThemeChoices()
  for i = 1, #choices do
    local ch = choices[i]
    if ch.value == value then return ch.label end
  end
  return nil
end

-- /tpl theme [name]: without a name, prints the current setting and the accepted
-- names (a key kept by the repair from a newer version is shown as it is); with a
-- valid name, sets it. false = not a theme name (the caller prints Unknown).
local function ThemeCommand(name)
  if name == nil then
    local cur = GetSetting(THEME_PATH)
    Util.Print(L.THEME_LIST_FMT, ThemeLabel(cur) or tostring(cur), table_concat(C.THEME_CHOICES, ", "))
    return true
  end
  local label = ThemeLabel(name)
  if not label then return false end
  SetSetting(THEME_PATH, name)
  Util.Print(L.THEME_SET_FMT, label)
  return true
end

-- A C.LANGUAGES_NATIVE_ONLY language on a client in another language: its script would
-- not draw there.
local function ForeignScript(value)
  return C.LANGUAGES_NATIVE_ONLY[value] == true and value ~= GetLocale()
end

-- Display name of a "language" setting value, each in its own language (the same in
-- every locale file; the code instead where its script would not draw); nil for a value
-- that is not a choice. Read at use time: the names are in L once the language applied.
local function LanguageLabel(value)
  if value == "auto" then return L.LANG_AUTO end
  if ForeignScript(value) then return value end
  if value == "enUS" then return L.LANG_ENUS end
  if value == "frFR" then return L.LANG_FRFR end
  if value == "deDE" then return L.LANG_DEDE end
  if value == "esES" then return L.LANG_ESES end
  if value == "esMX" then return L.LANG_ESMX end
  if value == "itIT" then return L.LANG_ITIT end
  if value == "ptBR" then return L.LANG_PTBR end
  if value == "ruRU" then return L.LANG_RURU end
  if value == "koKR" then return L.LANG_KOKR end
  if value == "zhCN" then return L.LANG_ZHCN end
  if value == "zhTW" then return L.LANG_ZHTW end
  return nil
end

-- The languages offered, in C.LANGUAGES order: every one the client's font can draw
-- (a native-only language on its own client only), plus the stored setting (shown
-- selected even when it came from another client).
local function LanguageOffered(value)
  return not ForeignScript(value) or value == GetSetting("language")
end

-- The /tpl lang aliases of the offered languages, joined by `sep`.
local function LanguageAliases(sep)
  local codes, names = C.LANGUAGES, {}
  for i = 1, #codes do
    local v = codes[i]
    if LanguageOffered(v) then names[#names + 1] = LANG_ALIAS[v] or v end
  end
  return table_concat(names, sep)
end

-- /tpl lang [value]: without a value, prints the current setting and the accepted
-- values (the offered ones, LanguageAliases); with a valid one, sets it (the message
-- says a /reload applies it, even when the value did not change: the language may
-- still be pending). Read-only mode refuses a value: nothing is saved, so the next UI
-- load would come back to the stored language. false = not an offered language (the
-- caller prints Unknown).
local function LanguageCommand(arg)
  local codes = C.LANGUAGES
  if arg == nil then
    local cur = GetSetting("language")
    Util.Print(L.LANG_LIST_FMT, LanguageLabel(cur) or tostring(cur), LanguageAliases(", "))
    return true
  end
  local value
  for i = 1, #codes do
    local v = codes[i]
    if (arg == LANG_ALIAS[v] or arg == v:lower()) and LanguageOffered(v) then value = v end
  end
  if not value then return false end
  if ReadOnlyRefused() then return true end
  SetSetting("language", value)
  Util.Print(L.LANG_SET_FMT, LanguageLabel(value) or value)
  return true
end

---------------------------------------------------------------------------
-- Controls (options panel content, built on first show)
---------------------------------------------------------------------------

local content, cursorY

local function MakeButton(parent, text, w, h, onClick)
  local b
  if HasTemplate("UIPanelButtonTemplate") then
    b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h)
    b:SetText(text)
  else
    b = CreateFrame("Button", nil, parent, "BackdropTemplate")
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
    btnText[b] = fs
  end
  b:SetScript("OnClick", onClick)
  return b
end

local function SetButtonText(b, text)
  local fs = btnText[b]
  if fs then fs:SetText(text) else b:SetText(text) end
end

local function SetButtonEnabled(b, on)
  if on then b:Enable() else b:Disable() end
  local fs = btnText[b]
  if fs then
    local c = on and C.COLORS.value or C.COLORS.dim
    fs:SetTextColor(c[1], c[2], c[3])
  end
end

local function AddHeader(text)
  cursorY = cursorY - 14
  local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_X - 8, cursorY)
  fs:SetText(text)
  cursorY = cursorY - 22
  return fs
end

local function AddNote(text)
  local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_X, cursorY)
  fs:SetWidth(CONTENT_W - LABEL_X - 20)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  local lc = C.COLORS.label
  fs:SetTextColor(lc[1], lc[2], lc[3])
  local h = fs:GetStringHeight()
  if type(h) ~= "number" or h <= 0 then h = 14 end
  cursorY = cursorY - h - 6
  return fs
end

local function AddLabel(text)
  local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_X + 4, cursorY - 4)
  fs:SetWidth(CONTROL_X - LABEL_X - 12)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function Register(rec, widget)
  controls[#controls + 1] = rec
  rec.index = #controls             -- creation order (tests: the theme is the first Display control)
  rec.widget = widget
  recOf[widget] = rec
  return rec
end

-- Checkbox ------------------------------------------------------------------

local function OnCheckClick(self)
  local rec = recOf[self]
  if not rec then return end
  if not rec.disabled then
    SetSetting(rec.path, not GetSetting(rec.path))
  end
  rec.Sync(rec)
end

local function SyncCheck(rec)
  local cb = rec.widget
  cb:SetChecked(GetSetting(rec.path) and true or false)
  if rec.disabled then cb:Disable() else cb:Enable() end
end

local function AddCheckbox(text, path)
  local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_X, cursorY)
  local fs = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
  fs:SetText(text)
  cb:SetScript("OnClick", OnCheckClick)
  cursorY = cursorY - 26
  return Register({ kind = "check", path = path, label = fs, Sync = SyncCheck }, cb)
end

-- Dropdown ------------------------------------------------------------------
-- choices: array of { value = v, label = text }

local function ChoiceIndex(rec)
  local cur = GetSetting(rec.path)
  for i = 1, #rec.choices do
    if rec.choices[i].value == cur then return i end
  end
  return 1
end

local function IsChoiceSelected(choice)
  return GetSetting(choice.path) == choice.value
end

-- Every dropdown and cycle button writes through here. The language applies only at
-- the next UI load, which a read-only session saves nothing for: refused like the
-- data actions (the message of /tpl lang), the control keeps showing the setting.
local function WriteChoice(path, value)
  if path == "language" and ReadOnlyRefused() then return end
  SetSetting(path, value)
end

local function SetChoiceSelected(choice)
  WriteChoice(choice.path, choice.value)
end

-- The menu description is rebuilt only when the value changed (a slider drag sends
-- one SETTINGS_CHANGED per step and must not regenerate every dropdown each time).
local function SyncModernDropdown(rec)
  local v = GetSetting(rec.path)
  if v == rec.last then return end
  rec.last = v
  local dd = rec.widget
  if type(dd.GenerateMenu) == "function" then dd:GenerateMenu() end
end

local function OnCycleClick(self, button)
  local rec = recOf[self]
  if not rec then return end
  local n = #rec.choices
  local i = ChoiceIndex(rec) + ((button == "RightButton") and -1 or 1)
  if i < 1 then i = n elseif i > n then i = 1 end
  WriteChoice(rec.path, rec.choices[i].value)
  rec.Sync(rec)
end

local function SyncCycle(rec)
  SetButtonText(rec.widget, rec.choices[ChoiceIndex(rec)].label)
end

local function AddDropdown(text, path, choices)
  local label = AddLabel(text)
  for i = 1, #choices do choices[i].path = path end
  local rec = { kind = "dropdown", path = path, choices = choices, label = label }
  local widget
  if MenuUtil and HasTemplate("WowStyle1DropdownTemplate") then
    widget = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    widget:SetWidth(220)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", CONTROL_X, cursorY)
    rec.Sync = SyncModernDropdown
    rec.modern = true
    widget:SetupMenu(function(_, root)
      for i = 1, #choices do
        local ch = choices[i]
        root:CreateRadio(ch.label, IsChoiceSelected, SetChoiceSelected, ch)
      end
    end)
    rec.last = GetSetting(path)         -- SetupMenu generated the menu for this value
  else
    widget = MakeButton(content, "", 220, 22, OnCycleClick)
    widget:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", CONTROL_X, cursorY)
    rec.Sync = SyncCycle
  end
  cursorY = cursorY - 30
  return Register(rec, widget)
end

-- Slider --------------------------------------------------------------------

local function FormatPx(v)
  return format(L.SLIDER_PX_FMT, math_floor((tonumber(v) or 0) + 0.5))
end

local function FormatPct(v)
  return format(L.SLIDER_PCT_FMT, math_floor((tonumber(v) or 0) + 0.5))
end

local function Snap(rec, v)
  v = tonumber(v) or rec.min
  v = rec.min + math_floor((v - rec.min) / rec.step + 0.5) * rec.step
  if v < rec.min then v = rec.min elseif v > rec.max then v = rec.max end
  return v
end

local function SliderValue(rec)
  local v = tonumber(GetSetting(rec.path)) or rec.min
  return math_floor(v * rec.factor + 0.5)
end

local function WriteSlider(rec, v)
  if syncing then return end
  v = Snap(rec, v)
  SetSetting(rec.path, (rec.factor == 1) and v or v / rec.factor)
end

local function OnModernSliderChanged(rec, value)
  WriteSlider(rec, value)
end

local function SyncModernSlider(rec)
  rec.widget:SetValue(SliderValue(rec))
end

local function OnFallbackSliderChanged(self, value)
  local rec = recOf[self]
  if not rec then return end
  local v = Snap(rec, value)
  rec.valueText:SetText(rec.formatter(v))
  WriteSlider(rec, v)
end

local function SyncFallbackSlider(rec)
  local v = SliderValue(rec)
  rec.widget:SetValue(v)
  rec.valueText:SetText(rec.formatter(v))
end

local function AddSlider(text, path, min, max, step, factor, formatter)
  local label = AddLabel(text)
  local rec = { kind = "slider", path = path, min = min, max = max, step = step,
                factor = factor or 1, formatter = formatter, label = label }
  local widget
  local SliderMixin = MinimalSliderWithSteppersMixin
  if SliderMixin and HasTemplate("MinimalSliderWithSteppersTemplate") then
    widget = CreateFrame("Frame", nil, content, "MinimalSliderWithSteppersTemplate")
    widget:SetWidth(250)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", CONTROL_X, cursorY)
    local formatters
    if type(SliderMixin.Label) == "table" and SliderMixin.Label.Right ~= nil then
      formatters = { [SliderMixin.Label.Right] = formatter }
    end
    syncing = true
    widget:Init(SliderValue(rec), min, max, math_floor((max - min) / step + 0.5), formatters)
    syncing = false
    local event = type(SliderMixin.Event) == "table" and SliderMixin.Event.OnValueChanged or "OnValueChanged"
    widget:RegisterCallback(event, OnModernSliderChanged, rec)
    rec.Sync = SyncModernSlider
    rec.modern = true
  else
    widget = CreateFrame("Slider", nil, content, "BackdropTemplate")
    widget:SetOrientation("HORIZONTAL")
    widget:SetSize(200, 17)
    widget:SetPoint("TOPLEFT", content, "TOPLEFT", CONTROL_X, cursorY - 2)
    if widget.SetBackdrop then widget:SetBackdrop(SLIDER_BACKDROP) end
    widget:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    widget:SetMinMaxValues(min, max)
    widget:SetValueStep(step)
    widget:SetObeyStepOnDrag(true)
    widget:EnableMouseWheel(false)
    local vt = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    vt:SetPoint("LEFT", widget, "RIGHT", 10, 0)
    rec.valueText = vt
    widget:SetScript("OnValueChanged", OnFallbackSliderChanged)
    rec.Sync = SyncFallbackSlider
  end
  cursorY = cursorY - 32
  return Register(rec, widget)
end

-- Colours (swatch, optional reset) --------------------------------------------
-- false (or nil) = the active theme's colours, shown by the swatch: its XP and rested
-- colours before any user override (Themes.DefaultColor) for the bar, its value text
-- colour for the texts; else { r, g, b }. Read at sync time only (panel shown).

local function DefaultColor(path)
  local Themes = ns.Themes
  if path == XP_COLOR_PATH or path == RESTED_COLOR_PATH then
    local isXP = (path == XP_COLOR_PATH)
    local c = Themes and Themes.DefaultColor and Themes.DefaultColor(isXP and "xp" or "rested")
    if type(c) == "table" then return c end
    return isXP and C.COLORS.fill or C.COLORS.restedFill
  end
  local th = Themes and Themes.Active and Themes.Active()
  local tc = type(th) == "table" and type(th.text) == "table" and th.text.colors
  local c = type(tc) == "table" and tc.value
  if type(c) == "table" then return c end
  return C.COLORS.value
end

local function ColorRGB(path)
  local v = GetSetting(path)
  if type(v) == "table" then
    return tonumber(v[1]) or 1, tonumber(v[2]) or 1, tonumber(v[3]) or 1
  end
  local c = DefaultColor(path)
  return c[1], c[2], c[3]
end

local function CopyColor(v)
  if type(v) == "table" then return { v[1], v[2], v[3] } end
  return false
end

local function SameColor(r, g, b)
  return math_abs(r - pickR) < 0.0005 and math_abs(g - pickG) < 0.0005 and math_abs(b - pickB) < 0.0005
end

-- Picker callbacks (module level: the picker keeps them while it is open). The picker
-- reports its start colour when it opens (both APIs): that is not a choice, so the
-- built-in colours stay until the user actually moves the colour.
local function OnPickerColor()
  local picker = ColorPickerFrame
  if type(picker) ~= "table" or type(picker.GetColorRGB) ~= "function" then return end
  local r, g, b = picker:GetColorRGB()
  if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return end
  if pickerFresh then
    if SameColor(r, g, b) then return end
    pickerFresh = false
  end
  SetSetting(pickPath, { r, g, b })
end

local function OnPickerCancel()
  if pickerPrev == nil then return end
  SetSetting(pickPath, CopyColor(pickerPrev))
end

local function OpenColorPicker(path)
  local picker = ColorPickerFrame
  if type(picker) ~= "table" then return end
  pickPath = path
  pickerPrev = CopyColor(GetSetting(path))
  local r, g, b = ColorRGB(path)
  pickR, pickG, pickB = r, g, b
  pickerFresh = true
  if type(picker.SetupColorPickerAndShow) == "function" then
    picker:SetupColorPickerAndShow({
      r = r, g = g, b = b, hasOpacity = false,
      swatchFunc = OnPickerColor, cancelFunc = OnPickerCancel,
    })
  elseif type(picker.SetColorRGB) == "function" then
    -- older API (before 10.2.5): the shared picker is configured through its fields
    picker.hasOpacity, picker.opacityFunc = false, nil
    picker.previousValues = { r = r, g = g, b = b }
    picker.func, picker.cancelFunc = OnPickerColor, OnPickerCancel
    picker:SetColorRGB(r, g, b)
    picker:Show()
  end
end

local function OnSwatchClick(self)
  local rec = recOf[self]
  if rec then OpenColorPicker(rec.path) end
end

local function OnColorReset(self)
  SetSetting((self and resetPath[self]) or TEXT_COLOR_PATH, false)
end

local function SyncColor(rec)
  local r, g, b = ColorRGB(rec.path)
  rec.swatch:SetVertexColor(r, g, b, 1)
  if rec.reset and not rec.sharedReset then
    SetButtonEnabled(rec.reset, type(GetSetting(rec.path)) == "table")
  end
end

-- A colour swatch for `path`; with `resetText`, a reset button beside it.
local function AddColorPicker(text, path, resetText)
  local label = AddLabel(text)
  local b = CreateFrame("Button", nil, content, "BackdropTemplate")
  b:SetSize(44, 20)
  b:SetPoint("TOPLEFT", content, "TOPLEFT", CONTROL_X, cursorY - 1)
  if b.SetBackdrop then
    b:SetBackdrop(SWATCH_BACKDROP)
    local t, bd = C.COLORS.track, C.COLORS.border
    b:SetBackdropColor(t[1], t[2], t[3], 1)
    b:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.6)
  end
  local swatch = b:CreateTexture(nil, "ARTWORK")
  swatch:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3)
  swatch:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
  swatch:SetTexture(C.TEX_WHITE)
  b:SetScript("OnClick", OnSwatchClick)
  local reset
  if resetText then
    reset = MakeButton(content, resetText, 160, 22, OnColorReset)
    reset:SetPoint("LEFT", b, "RIGHT", 12, 0)
    resetPath[reset] = path
  end
  cursorY = cursorY - 30
  return Register({ kind = "color", path = path, label = label, swatch = swatch, reset = reset,
                    Sync = SyncColor }, b)
end

-- Bar colours reset: both back to the theme's colours (enabled when one is custom).
local function OnBarColorsReset()
  SetSetting(XP_COLOR_PATH, false)
  SetSetting(RESTED_COLOR_PATH, false)
end

local function SyncBarColorsReset(rec)
  SetButtonEnabled(rec.widget, type(GetSetting(XP_COLOR_PATH)) == "table"
    or type(GetSetting(RESTED_COLOR_PATH)) == "table")
end

-- One reset button under the bar colour swatches; it is their `reset` too (shared:
-- its state is kept by its own record, enabled while either colour is custom).
local function AddBarColorsReset(xpRec, restedRec)
  local b = MakeButton(content, L.OPT_BAR_COLORS_RESET, 170, 22, OnBarColorsReset)
  b:SetPoint("TOPLEFT", content, "TOPLEFT", CONTROL_X, cursorY)
  cursorY = cursorY - 30
  xpRec.reset, xpRec.sharedReset = b, true
  restedRec.reset, restedRec.sharedReset = b, true
  return Register({ kind = "button", path = BAR_COLORS_RESET, Sync = SyncBarColorsReset }, b)
end

-- Language: "Reload UI" under the dropdown (the chosen language applies at the next UI
-- load). Registered under its own pseudo-path ("language" is the dropdown's record);
-- nothing to sync. Choosing a language never reloads by itself.
local function OnReloadClick()
  if type(ReloadUI) == "function" then ReloadUI() end
end

local function SyncNothing() end

local function AddLanguage()
  local choices = {}
  for i = 1, #C.LANGUAGES do
    local v = C.LANGUAGES[i]
    if LanguageOffered(v) then choices[#choices + 1] = { value = v, label = LanguageLabel(v) or v } end
  end
  AddDropdown(L.OPT_LANGUAGE, "language", choices)
  AddNote(L.OPT_LANGUAGE_NOTE)
  local b = MakeButton(content, L.OPT_RELOAD, 170, 22, OnReloadClick)
  b:SetPoint("TOPLEFT", content, "TOPLEFT", CONTROL_X, cursorY)
  cursorY = cursorY - 30
  return Register({ kind = "button", path = "language.reload", Sync = SyncNothing }, b)
end

-- Buttons ---------------------------------------------------------------------

local function AddButtonRow(defs)
  local x = LABEL_X
  for i = 1, #defs do
    local d = defs[i]
    local b = MakeButton(content, d[1], d[3] or 170, 22, d[2])
    b:SetPoint("TOPLEFT", content, "TOPLEFT", x, cursorY)
    x = x + (d[3] or 170) + 8
  end
  cursorY = cursorY - 30
end

---------------------------------------------------------------------------
-- Options panel content
---------------------------------------------------------------------------

local function TokenChoices(xpAllowed)
  local list = {}
  local Tokens = ns.Tokens
  for _, id in ipairs(Tokens.ORDER) do
    local def = Tokens.DEF[id]
    if xpAllowed or not (def and def.xp) then
      list[#list + 1] = { value = id, label = Tokens.Label(id) }
    end
  end
  return list
end

local function UpdateCityLine()
  if not cityLine then return end
  local T = ns.Tracker
  local _, zoneKey, _, isCity = T.ComputeState()
  local zones = ns.char and ns.char.zones
  local name = (zoneKey ~= nil) and ns.Stats.ZoneName(zoneKey, zones and zones[zoneKey]) or L.ZONE_UNKNOWN
  cityLine:SetText(format(L.OPT_CITY_CURRENT_FMT, name, isCity and L.CITY_YES or L.CITY_NO))
end

local function OnOpenStats() ns.Window.Show() end
local function OnResetPos() ResetPosAction() end
local function OnResetSession() ResetSessionAction() end
local function OnResetRate() ResetRateAction() end
local function OnResetChar() Options.ConfirmErase(CurrentGuid()) end
local function OnCityToggle()
  CityToggleAction()
  UpdateCityLine()
end

-- 2d. Minimap button and mini display: the info choices come from the bar's catalog
-- (info 1 is never empty), the look from the bar's theme and text options.
local function OnMiniResetPos()
  ns.MiniDisplay.ResetPosition()
  Util.Print(L.RESET_POS_DONE)
end

local function BuildMiniSection()
  AddHeader(L.OPT_MINI_SECTION)
  AddCheckbox(L.OPT_MM_SHOW, "minimap.shown")
  AddCheckbox(L.OPT_MM_LOCK, "minimap.locked")
  AddDropdown(L.OPT_MM_CLICK, "minimap.click", {
    { value = "stats", label = L.CLICK_STATS },
    { value = "options", label = L.CLICK_OPTIONS },
    { value = "bar", label = L.CLICK_BAR },
    { value = "mini", label = L.CLICK_MINI },
  })
  AddNote(L.OPT_MM_NOTE)
  AddCheckbox(L.OPT_MINI_SHOW, "mini.shown")
  AddNote(L.OPT_MINI_NOTE)
  local first = TokenChoices(true)
  table.remove(first, 1)                        -- "none" (Tokens.ORDER[1])
  AddDropdown(format(L.OPT_MINI_INFO_FMT, 1), "mini.infos.1", first)
  AddDropdown(format(L.OPT_MINI_INFO_FMT, 2), "mini.infos.2", TokenChoices(true))
  AddDropdown(format(L.OPT_MINI_INFO_FMT, 3), "mini.infos.3", TokenChoices(true))
  AddDropdown(L.OPT_MINI_LAYOUT, "mini.layout",
    { { value = "horizontal", label = L.LAYOUT_H }, { value = "vertical", label = L.LAYOUT_V } })
  AddDropdown(L.OPT_MINI_XP, "mini.xp", {
    { value = "none", label = L.MINI_XP_NONE },
    { value = "pct", label = L.MINI_XP_PCT },
    { value = "line", label = L.MINI_XP_LINE },
    { value = "both", label = L.MINI_XP_BOTH },
  })
  AddSlider(L.OPT_SCALE, "mini.scale", 50, 200, 5, 100, FormatPct)
  AddSlider(L.OPT_BG_ALPHA, "mini.bgAlpha", 0, 100, 5, 100, FormatPct)
  AddCheckbox(L.OPT_LOCK, "mini.locked")
  AddCheckbox(L.OPT_COMBAT_HIDE, "mini.combatHide")
  AddCheckbox(L.OPT_FADE, "mini.fade")
  AddButtonRow({ { L.OPT_RESET_POS, OnMiniResetPos } })
end

-- 2e. Statistics window: the format of its dates (examples written in each format, the
-- language's one first) and the clock. The clock setting is "auto" | "24" | "12": the
-- checkbox shows the clock in use (auto = the language's) and a click writes the other one.
local DATE_EXAMPLE = 1798718400           -- 31 Dec 2026 at noon UTC (that day in every time zone)

local function ClockIs24()
  local v = GetSetting("window.clock")
  if v == "24" then return true end
  if v == "12" then return false end
  return not string_find(L.TIME_FMT, "%I", 1, true)
end

local function OnClockClick(self)
  local rec = recOf[self]
  if not rec then return end
  SetSetting("window.clock", ClockIs24() and "12" or "24")
  rec.Sync(rec)
end

local function SyncClock(rec)
  rec.widget:SetChecked(ClockIs24())
end

local function BuildWindowSection()
  AddHeader(L.OPT_WINDOW)
  AddDropdown(L.OPT_DATE_FMT, "window.dateFmt", {
    { value = "auto", label = format(L.DATE_AUTO_FMT, date(L.DATE_FMT, DATE_EXAMPLE)) },
    { value = "dmy", label = date("%d/%m/%Y", DATE_EXAMPLE) },
    { value = "mdy", label = date("%m/%d/%Y", DATE_EXAMPLE) },
    { value = "ymd", label = date("%Y-%m-%d", DATE_EXAMPLE) },
  })
  local rec = AddCheckbox(L.OPT_CLOCK24, "window.clock")
  rec.Sync = SyncClock
  rec.widget:SetScript("OnClick", OnClockClick)
  AddNote(L.OPT_WINDOW_NOTE)
end

local function Build()
  built = true
  local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, standalone and -28 or -4)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 4)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(CONTENT_W, 100)
  scroll:SetScrollChild(content)
  cursorY = -8

  local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_X - 8, cursorY)
  title:SetText(L.ADDON_TITLE)
  cursorY = cursorY - 20
  readOnlyNote = AddNote(L.OPT_NOTE_READONLY)
  local pc = C.COLORS.pause
  readOnlyNote:SetTextColor(pc[1], pc[2], pc[3])

  -- 1. Exclusions
  AddHeader(L.OPT_EXCLUSIONS)
  AddCheckbox(L.MENU_EXCLUDE_AFK, "exclude.afk")
  AddCheckbox(L.MENU_EXCLUDE_INN, "exclude.inn")
  AddCheckbox(L.MENU_EXCLUDE_CITY, "exclude.city")
  AddNote(L.OPT_EXCLUSIONS_HELP)
  AddNote(L.OPT_CITY_HELP)

  -- 2. Display (the theme first, SPEC-themes 5.6)
  AddHeader(L.OPT_DISPLAY)
  AddDropdown(L.OPT_THEME, THEME_PATH, ThemeChoices())
  AddNote(L.OPT_THEME_NOTE)
  AddNote(L.OPT_THEME_RESTART_NOTE)
  AddCheckbox(L.OPT_SHOW, "widget.shown")
  AddDropdown(L.OPT_SLOT1, "widget.slots.1", TokenChoices(true))
  AddDropdown(L.OPT_SLOT2, "widget.slots.2", TokenChoices(true))
  AddDropdown(L.OPT_SLOT3, "widget.slots.3", TokenChoices(true))
  AddNote(L.OPT_SLOTS_NOTE)
  AddDropdown(L.OPT_SLOT3_POS, "widget.slot3Pos",
    { { value = "center", label = L.POS_CENTER }, { value = "left", label = L.POS_LEFT } })
  AddDropdown(L.OPT_PCT_POS, "widget.pctPos",
    { { value = "follow", label = L.PCT_FOLLOW }, { value = "level", label = L.PCT_LEVEL } })
  AddNote(L.OPT_MAX_SLOTS)
  for i = 1, 3 do
    AddDropdown(format(L.OPT_MAX_SLOT_FMT, i), "widget.maxSlots." .. i, TokenChoices(false))
  end
  AddSlider(L.OPT_WIDTH, "widget.width", 150, 600, 10, 1, FormatPx)
  AddSlider(L.OPT_HEIGHT, "widget.height", 4, 16, 1, 1, FormatPx)
  AddSlider(L.OPT_SCALE, "widget.scale", 50, 200, 5, 100, FormatPct)
  AddSlider(L.OPT_FONT_SIZE, "widget.fontSize", 9, 16, 1, 1, FormatPx)
  AddCheckbox(L.OPT_LOCK, "widget.locked")
  AddCheckbox(L.OPT_COMBAT_HIDE, "widget.combatHide")
  AddCheckbox(L.OPT_FADE, "widget.fade")
  AddCheckbox(L.OPT_HIDE_MAX, "widget.hideAtMax")
  AddLanguage()

  -- 2b. Texts (readability without a background: outline and shadow by default)
  AddHeader(L.OPT_TEXTS)
  AddColorPicker(L.OPT_TEXT_COLOR, TEXT_COLOR_PATH, L.OPT_TEXT_COLOR_RESET)
  AddNote(L.OPT_TEXT_COLOR_NOTE)
  AddDropdown(L.OPT_OUTLINE, "widget.outline", {
    { value = "none", label = L.OUTLINE_NONE },
    { value = "thin", label = L.OUTLINE_THIN },
    { value = "thick", label = L.OUTLINE_THICK },
  })
  AddCheckbox(L.OPT_SHADOW, "widget.shadow")
  AddSlider(L.OPT_BG_ALPHA, "widget.bgAlpha", 0, 100, 5, 100, FormatPct)

  -- 2b'. Bar colours (the theme's XP and rested colours by default)
  AddHeader(L.OPT_BAR_COLORS)
  AddBarColorsReset(AddColorPicker(L.OPT_XP_COLOR, XP_COLOR_PATH),
                    AddColorPicker(L.OPT_RESTED_COLOR, RESTED_COLOR_PATH))
  AddNote(L.OPT_BAR_COLORS_NOTE)

  -- 2c. FPS and latency
  AddHeader(L.OPT_NET)
  AddCheckbox(L.OPT_QUALITY_COLORS, "widget.qualityColors")
  AddNote(L.OPT_QUALITY_COLORS_NOTE)
  AddDropdown(L.OPT_GRAPH_WINDOW, "graph.window", {
    { value = 30, label = L.GRAPH_WINDOW_30 },
    { value = 60, label = L.GRAPH_WINDOW_60 },
    { value = 300, label = L.GRAPH_WINDOW_300 },
  })
  AddNote(L.OPT_GRAPH_NOTE)

  -- 2d. Minimap button and mini display (both work with the bar hidden)
  BuildMiniSection()

  -- 2e. Statistics window (date format, clock)
  BuildWindowSection()

  -- 3. Calculation
  AddHeader(L.OPT_CALC)
  AddDropdown(L.OPT_REACTIVITY, "rateTau", {
    { value = 5400, label = L.REACT_SLOW },
    { value = 3600, label = L.REACT_NORMAL },
    { value = 1200, label = L.REACT_FAST },
  })
  AddNote(L.OPT_REACTIVITY_HELP)
  AddCheckbox(L.OPT_REQUEST_PLAYED, "requestPlayedAtLogin")
  AddNote(L.OPT_REQUEST_PLAYED_HELP)
  local hide = AddCheckbox(L.OPT_HIDE_PLAYED, "hidePlayedMsg")
  local canHide = ns.Played and ns.Played.CanHide and ns.Played.CanHide()
  if not canHide then
    hide.disabled = true
    local dc = C.COLORS.dim
    hide.label:SetTextColor(dc[1], dc[2], dc[3])
    AddNote(L.OPT_HIDE_PLAYED_NA)
  end
  AddNote(L.OPT_HIDE_PLAYED_HELP)

  -- 4. Cities
  AddHeader(L.OPT_CITIES)
  cityLine = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  cityLine:SetPoint("TOPLEFT", content, "TOPLEFT", LABEL_X, cursorY)
  cityLine:SetWidth(CONTENT_W - LABEL_X - 20)
  cityLine:SetJustifyH("LEFT")
  cursorY = cursorY - 20
  AddButtonRow({ { L.OPT_CITY_TOGGLE, OnCityToggle, 300 } })

  -- 5. Data
  AddHeader(L.OPT_DATA)
  AddButtonRow({ { L.OPT_OPEN_STATS, OnOpenStats }, { L.OPT_RESET_POS, OnResetPos },
                 { L.OPT_RESET_SESSION, OnResetSession } })
  AddButtonRow({ { L.OPT_RESET_RATE, OnResetRate }, { L.OPT_RESET_CHAR, OnResetChar, 260 } })
  AddNote(L.OPT_NOTE_PREINSTALL)
  AddNote(L.OPT_NOTE_IDLE)
  -- no XP for a while (C1) and the server level cap (C2): the thresholds of the engine
  AddNote(format(L.OPT_NOTE_STALL_FMT, math_floor(C.XP_STALL / 60 + 0.5)))
  AddNote(format(L.OPT_NOTE_CAP_FMT, C.CAP_MISSES))
  AddNote(L.OPT_NOTE_CRASH)
  AddNote(L.OPT_NOTE_CITY)
  AddNote(format(L.OPT_VERSION_FMT, ns.VERSION or "dev"))

  content:SetHeight(-cursorY + 16)

  -- Read-only handles for the offline tests (our own frame).
  local byPath = {}
  for i = 1, #controls do byPath[controls[i].path] = controls[i] end
  panel.controls = byPath
end

---------------------------------------------------------------------------
-- Panel lifecycle: listeners only while shown
---------------------------------------------------------------------------

-- SETTINGS_CHANGED on every path, "theme" included (SPEC-themes S8 is about drawing:
-- here it only syncs the controls, and THEME_CHANGED is not sent when the setting
-- changes but the resolved theme does not, e.g. "class" -> "mage" for a mage), except
-- the bar colours: Themes answers those with THEME_CHANGED "colors" (S7), which
-- refreshes the controls once (one colour picker step = one refresh). THEME_CHANGED
-- (either kind): the theme colours shown by the swatches.
local function OnOptSettingsChanged()
  Options.Refresh()
end

local function IsBarColorPath(path)
  return type(path) == "string" and (path:find("widget.xpColor", 1, true) == 1
    or path:find("widget.restedColor", 1, true) == 1)
end

local function OnOptSettingChanged(_, path)
  if not IsBarColorPath(path) then Options.Refresh() end
end

local function OnOptZoneChanged()
  if panelShown then UpdateCityLine() end
end

local function OnPanelShow()
  if not built then Build() end
  if not panelShown then
    panelShown = true
    ns.RegisterMessage("SETTINGS_CHANGED", Options, OnOptSettingChanged)
    ns.RegisterMessage("ZONE_KEY_CHANGED", Options, OnOptZoneChanged)
    ns.RegisterMessage("DB_SWAPPED", Options, OnOptSettingsChanged)
    ns.RegisterMessage("CHAR_RESET", Options, OnOptSettingsChanged)
    ns.RegisterMessage("THEME_CHANGED", Options, OnOptSettingsChanged)
  end
  Options.Refresh()
end

local function OnPanelHide()
  if not panelShown then return end
  panelShown = false
  ns.UnregisterMessage("SETTINGS_CHANGED", Options)
  ns.UnregisterMessage("ZONE_KEY_CHANGED", Options)
  ns.UnregisterMessage("DB_SWAPPED", Options)
  ns.UnregisterMessage("CHAR_RESET", Options)
  ns.UnregisterMessage("THEME_CHANGED", Options)
end

local function OnPanelDragStart(self) self:StartMoving() end
local function OnPanelDragStop(self) self:StopMovingOrSizing() end

-- Standalone host when the Settings API is missing: our own movable frame.
local function MakeStandalone()
  standalone = true
  panel:SetSize(PANEL_W, PANEL_H)
  panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  panel:SetFrameStrata("DIALOG")
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", OnPanelDragStart)
  panel:SetScript("OnDragStop", OnPanelDragStop)
  if panel.SetBackdrop then
    panel:SetBackdrop(PANEL_BACKDROP)
    local bg, bd = C.COLORS.bg, C.COLORS.border
    panel:SetBackdropColor(bg[1], bg[2], bg[3], 0.95)
    panel:SetBackdropBorderColor(bd[1], bd[2], bd[3], bd[4])
  end
  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
end

local function OnLauncherClick()
  Options.Open()
end

local function CategoryID()
  if not category then return nil end
  if type(category.GetID) == "function" then
    local ok, id = pcall(category.GetID, category)
    if ok and id ~= nil then return id end
  end
  return category.ID
end

local function DoOpen()
  if category then
    pcall(Settings.OpenToCategory, CategoryID())
  elseif panel then
    panel:Show()
    OnPanelShow()
  end
end

local function OnRegenOpen()
  deferredOpen = false
  ns.UnregisterEvent("PLAYER_REGEN_ENABLED", Options)
  DoOpen()
end

local function FirstRun()
  local s = ns.settings
  if ns.readOnly or not s or s.firstRunDone then return end
  SetSetting("widget.locked", false)
  if s.widget and s.widget.shown then Util.Print(L.FIRST_RUN) end
  SetSetting("firstRunDone", true)
end

---------------------------------------------------------------------------
-- Context menu (MenuUtil); module-level callbacks, data = setting path / value
---------------------------------------------------------------------------

local function IsSettingOn(path)
  return GetSetting(path) == true
end

local function ToggleSettingPath(path)
  SetSetting(path, not GetSetting(path))
end

local function IsTheme(value)
  return GetSetting(THEME_PATH) == value
end

local function SetThemeValue(value)
  SetSetting(THEME_PATH, value)
end

local function MenuStats() ns.Window.Toggle() end
local function MenuResetSession() ResetSessionAction() end
-- "Hide" hides what the menu was opened from: the minimap button, the mini display, else
-- the bar (data = the menu's owner).
local function MenuHide(owner)
  local MB, Mini = ns.MinimapButton, ns.MiniDisplay
  if owner ~= nil and MB and owner == MB.button then
    MB.SetShown(false)
    Util.Print(L.MINIMAP_HIDDEN)
  elseif owner ~= nil and Mini and owner == Mini.frame then
    Mini.SetShown(false)
    Util.Print(L.MINI_HIDDEN)
  else
    ns.Bar.SetShown(false)
    Util.Print(L.WIDGET_HIDDEN)
  end
end
local function MenuOptions() Options.Open() end

function Options.BuildContextMenu(owner, root)
  if type(root) ~= "table" then return end
  if root.CreateTitle then root:CreateTitle(L.ADDON_TITLE) end
  root:CreateCheckbox(L.MENU_EXCLUDE_AFK, IsSettingOn, ToggleSettingPath, "exclude.afk")
  root:CreateCheckbox(L.MENU_EXCLUDE_INN, IsSettingOn, ToggleSettingPath, "exclude.inn")
  root:CreateCheckbox(L.MENU_EXCLUDE_CITY, IsSettingOn, ToggleSettingPath, "exclude.city")
  if root.CreateDivider then root:CreateDivider() end
  local themeMenu = root:CreateButton(L.MENU_THEME)
  local themes = ThemeChoices()
  for i = 1, #themes do
    local ch = themes[i]
    themeMenu:CreateRadio(ch.label, IsTheme, SetThemeValue, ch.value)
  end
  root:CreateCheckbox(L.MENU_LOCK, IsSettingOn, ToggleSettingPath, "widget.locked")
  -- the three ways to see the information, each one on / off from any of them
  local showMenu = root:CreateButton(L.MENU_SHOW)
  showMenu:CreateCheckbox(L.MENU_SHOW_BAR, IsSettingOn, ToggleSettingPath, "widget.shown")
  showMenu:CreateCheckbox(L.MENU_SHOW_MINI, IsSettingOn, ToggleSettingPath, "mini.shown")
  showMenu:CreateCheckbox(L.MENU_SHOW_MINIMAP, IsSettingOn, ToggleSettingPath, "minimap.shown")
  root:CreateButton(L.MENU_STATS, MenuStats)
  root:CreateButton(L.MENU_RESET_SESSION, MenuResetSession)
  root:CreateButton(L.MENU_HIDE, MenuHide, owner)
  root:CreateButton(L.MENU_OPTIONS, MenuOptions)
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function Options.Init()
  if inited then return end
  inited = true
  panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  panel:Hide()
  panel:SetScript("OnShow", OnPanelShow)
  panel:SetScript("OnHide", OnPanelHide)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, L.ADDON_TITLE)
    if ok and cat then
      category = cat
      pcall(Settings.RegisterAddOnCategory, cat)
    end
  end
  if not category then
    MakeStandalone()
    if InterfaceOptions_AddCategory then
      -- Old options UI: a small launcher page that opens the standalone panel.
      local launcher = CreateFrame("Frame", nil, UIParent)
      launcher:Hide()
      launcher.name = L.ADDON_TITLE
      local b = MakeButton(launcher, L.MENU_OPTIONS, 180, 22, OnLauncherClick)
      b:SetPoint("TOPLEFT", launcher, "TOPLEFT", 16, -16)
      pcall(InterfaceOptions_AddCategory, launcher)
    end
  end
  FirstRun()
end

function Options.OnDBReady()
  Options.Init()
end

function Options.Open()
  if not inited then Options.Init() end
  if InCombatLockdown() then
    if not deferredOpen then
      deferredOpen = true
      Util.Print(L.COMBAT_DEFERRED)
      ns.RegisterEvent("PLAYER_REGEN_ENABLED", Options, OnRegenOpen)
    end
    return
  end
  DoOpen()
end

function Options.Toggle()
  if standalone and panel and panel:IsShown() then
    panel:Hide()
    OnPanelHide()
    return
  end
  Options.Open()
end

function Options.Refresh()
  if not built or not panelShown then return end
  syncing = true
  for i = 1, #controls do
    local rec = controls[i]
    rec.Sync(rec)
  end
  syncing = false
  UpdateCityLine()
  if ns.readOnly then readOnlyNote:Show() else readOnlyNote:Hide() end
end

function Options.ShowContextMenu(owner)
  if ns.Tooltip and owner then ns.Tooltip.Hide(owner) end
  if MenuUtil and MenuUtil.CreateContextMenu then
    MenuUtil.CreateContextMenu(owner or UIParent, Options.BuildContextMenu)
  else
    Options.Open()
  end
end

function Options.ConfirmErase(guid)
  if ReadOnlyRefused() then return end
  guid = guid or CurrentGuid()
  local rec
  if ns.char and guid == CurrentGuid() then
    rec = ns.char
  else
    rec = ns.db and ns.db.chars and ns.db.chars[guid]
  end
  if not rec or not guid then return end
  -- the buttons in the addon's language (the game's YES / NO follow the client's); set
  -- here, not at file load: the language is applied into L after the files load
  local dialog = type(StaticPopupDialogs) == "table" and StaticPopupDialogs.TRUEPLAYED_ERASE_CHAR
  if dialog then dialog.button1, dialog.button2 = L.ERASE_YES, L.ERASE_NO end
  StaticPopup_Show("TRUEPLAYED_ERASE_CHAR", format(L.CONFIRM_ERASE_CHAR_FMT, Util.CharName(rec)), nil, guid)
end

function Options.PrintPlayedSummary()
  local char = ns.char
  if not char then return end
  local Stats, T = ns.Stats, ns.Tracker
  local mask = ns.GetMask()
  local now = GetTime()
  local sync = T.GetSync()
  local level = math_floor(tonumber(char.level) or UnitLevel("player") or 0)
  local life = char.life or EMPTY_T
  local s = life.s or EMPTY_T

  Util.Print(L.SUM_HEADER_FMT, Util.CharName(char), level)
  local filtered, base, excluded = Stats.Played(char, mask, sync, now)
  Util.Print(L.SUM_PLAYED_FMT, Fmt.Duration(filtered or 0), Fmt.Duration(base or 0))
  local u = tonumber(s.u) or 0
  if mask ~= 0 and u > 0 then Util.Print(L.TT_PREINSTALL_FMT, Fmt.Duration(u)) end
  local est = tonumber(life.est) or 0
  if est > 0 then Util.Print(L.TT_EST_FMT, Fmt.Duration(est)) end
  if mask ~= 0 then
    Util.Print(L.SUM_EXCLUDED_FMT, Fmt.Duration(excluded or 0), Stats.MaskLabel(mask) or "")
  end
  -- breakdown parts as in the tooltip (fixed order, parts at 0 % left out); the text
  -- holds percent signs, so it is printed verbatim
  local bd = Stats.Breakdown(life, breakdownOut)
  local nParts = ns.Tooltip.BreakdownParts(bd, breakdownParts)
  if nParts > 0 then Util.Print(table_concat(breakdownParts, L.SEP, 1, nParts)) end
  local levelFiltered = Stats.LevelTime(char, level, mask, sync, now)
  local avg = Stats.AvgPerLevel(char, mask, sync, now)
  Util.Print(L.SUM_LEVEL_FMT, Fmt.Duration(levelFiltered or 0), avg and Fmt.Duration(avg) or L.DOTS)
  if T.IsMax() then
    -- a detected server level cap is not the max level: it says tracking resumes
    local capLevel, isServerCap
    if T.GetCapInfo then capLevel, isServerCap = T.GetCapInfo() end
    if isServerCap == true and type(capLevel) == "number" then
      Util.Print(L.SUM_CAP_FMT, math_floor(capLevel))
    else
      Util.Print(L.SUM_MAX)
    end
    return
  end
  local _, xp, max, rested, valid = T.GetXPInfo()
  local sec
  if valid then sec = Stats.ETA(char, mask, xp, max, rested or 0, false) end
  local xph, _, _, _, src, status, _, stallSecs = Stats.Rate(char, mask)
  if sec and xph then
    if status == "estimate" then
      -- estimated from the pre-install /played: "~" and the source, like the tooltip
      Util.Print(L.SUM_ETA_FMT, ns.Tokens.Approx(Fmt.ETA(sec)),
        format("~%s (%s)", Fmt.Rate(xph), L.RATE_ESTIMATE))
    elseif status == "stalled" then
      -- frozen rate (no XP for a while): the mark, then since when, like the tooltip
      local mark, eta, rate = L.STALL_MARK, Fmt.ETA(sec), Fmt.Rate(xph)
      if src == "prior" then eta, rate = ns.Tokens.Approx(eta), "~" .. rate end
      if T.GetStall then
        local _, secs = T.GetStall()
        if type(secs) == "number" then stallSecs = secs end
      end
      Util.Print(L.SUM_ETA_FMT, eta .. mark, rate .. mark)
      Util.Print(L.TT_STALLED_FMT, mark, Fmt.Duration(tonumber(stallSecs) or 0))
    else
      Util.Print(L.SUM_ETA_FMT, Fmt.ETA(sec), Fmt.Rate(xph))
    end
  else
    Util.Print(L.SUM_ETA_NONE)
  end
end

function Options.PrintPerf()
  local Core = ns.Core
  Util.Print(L.PERF_HEADER_FMT, ns.VERSION or "dev", math_floor(tonumber(ns.interface) or 0))
  local kb = Core.GetMemoryKB()
  if kb then
    Util.Print(L.PERF_MEM_FMT, Fmt.Decimal(kb, 1))
  else
    Util.Print(L.PERF_MEM_NA)
  end
  local total, perMin, profAvg, profPeak = Core.GetCPU()
  if total then
    Util.Print(L.PERF_CPU_FMT, Dec(total, 1), Dec(perMin, 3))
  else
    Util.Print(L.PERF_CPU_OFF)
  end
  if profAvg then
    Util.Print(L.PERF_PROFILER_FMT, Dec(profAvg, 3), Dec(profPeak, 3))
  end
  local char = ns.char or EMPTY_T
  local chars = ns.db and ns.db.chars
  Util.Print(L.PERF_DATA_FMT, Count(char.levels), Count(char.zones), Count(char.sessions), Count(chars))
  Core.StartTickProfile(C.PERF_SAMPLE_TICKS)
  Util.Print(L.PERF_TICK_ARMED_FMT, C.PERF_SAMPLE_TICKS)
end

local function PrintHelp()
  Util.Print(L.HELP_HEADER)
  local out = DEFAULT_CHAT_FRAME
  local keys = { "HELP_OPTIONS", "HELP_STATS", "HELP_LOCK", "HELP_SHOW", "HELP_THEME",
                 "HELP_LANG", "HELP_MINIMAP", "HELP_MINI", "HELP_EXCLUDE", "HELP_CITY", "HELP_PLAYED", "HELP_SYNC", "HELP_RESET",
                 "HELP_DEBUG", "HELP_PERF" }
  for i = 1, #keys do
    local line = L[keys[i]]
    if keys[i] == "HELP_LANG" then line = format(line, LanguageAliases(" | ")) end
    if out then out:AddMessage("  " .. line) else Util.Print(line) end
  end
end

local function Unknown(msg)
  Util.Print(L.UNKNOWN_CMD_FMT, strtrim(msg or ""))
end

-- /tpl sub-commands (SPEC 7.12). Sub-commands are English and case-insensitive.
function Options.HandleSlash(msg)
  msg = msg or ""
  local w1, w2 = Util.Words(msg)
  if w1 == nil or w1 == "" then
    Options.Toggle()
  elseif w1 == "help" then
    PrintHelp()
  elseif w1 == "stats" then
    ns.Window.Toggle(STATS_TABS[w2 or ""] and w2 or nil)
  elseif w1 == "lock" or w1 == "unlock" then
    local locked = (w1 == "lock")
    ns.Bar.SetLocked(locked)
    Util.Print(locked and L.LOCKED or L.UNLOCKED)
  elseif w1 == "show" or w1 == "hide" then
    local shown = (w1 == "show")
    ns.Bar.SetShown(shown)
    Util.Print(shown and L.WIDGET_SHOWN or L.WIDGET_HIDDEN)
  elseif w1 == "theme" then
    if not ThemeCommand(w2) then Unknown(msg) end
  elseif w1 == "lang" then
    if not LanguageCommand(w2) then Unknown(msg) end
  elseif w1 == "minimap" then
    ns.MinimapButton.Toggle()
  elseif w1 == "mini" then
    ns.MiniDisplay.Toggle()
  elseif EXCLUDE_LABEL[w1] then
    if w2 == nil or w2 == "" then
      SetExclusion(w1, nil)
    elseif w2 == "on" or w2 == "off" then
      SetExclusion(w1, w2 == "on")
    else
      Unknown(msg)
    end
  elseif w1 == "citytoggle" then
    CityToggleAction()
  elseif w1 == "played" then
    Options.PrintPlayedSummary()
  elseif w1 == "sync" then
    -- Played prints SYNC_REQUESTED / SYNC_THROTTLED itself for manual requests
    ns.Played.Request("manual")
  elseif w1 == "reset" then
    if w2 == "pos" then
      ResetPosAction()
    elseif w2 == "session" then
      ResetSessionAction()
    elseif w2 == "rate" then
      ResetRateAction()
    elseif w2 == "char" then
      Options.ConfirmErase(CurrentGuid())
    else
      Unknown(msg)
    end
  elseif w1 == "debug" then
    local on = not GetSetting("debug")
    SetSetting("debug", on)
    Util.Print(on and L.DEBUG_ON or L.DEBUG_OFF)
  elseif w1 == "perf" then
    Options.PrintPerf()
  else
    Unknown(msg)
  end
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", Options, Options.OnDBReady)
end
