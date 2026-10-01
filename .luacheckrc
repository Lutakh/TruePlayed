-- Luacheck configuration for TruePlayed (World of Warcraft addon, Lua 5.1 runtime).
-- Mirrors SPEC-FINAL section 2.2 (the only allowed global writes) and section 2.3
-- (the only WoW API globals addon code may read). Run by CI: `luacheck .`

std = "lua51"
max_line_length = false
codes = true
self = false                -- never report the implicit, unused `self` of methods

exclude_files = {
  ".release/**",            -- BigWigs packager output
  ".lua/**",                -- Lua installed by leafo/gh-actions-lua in CI
  ".lua-build/**",          -- ... and its build folder
  ".luarocks/**",
  ".install/**",
  "tests/baseline/**",      -- frozen pre-theme copy of the addon (golden test, SPEC-themes 8.2)
}

ignore = {
  "212/self",               -- explicit `self` argument of script handlers
  "212/_.*",                -- `_`-prefixed arguments are unused on purpose
  "211/_.*",
  "211/ADDON",              -- every file starts with `local ADDON, ns = ...` (SPEC 1.3)
}

-- Lua 5.1 functions that WoW does not provide, or that SPEC 2.3 forbids in addon code.
not_globals = {
  "os", "io", "print", "load", "loadstring", "loadfile", "dofile",
  "require", "module", "package", "debug", "setfenv", "getfenv", "newproxy",
}

-- SPEC 2.2: the only globals the addon may create or assign.
globals = {
  "TruePlayedDB",
  "SLASH_TRUEPLAYED1",
  "SLASH_TRUEPLAYED2",
  "TruePlayed_OnAddonCompartmentClick",
  "TruePlayed_OnAddonCompartmentEnter",
  "TruePlayed_OnAddonCompartmentLeave",
  "TruePlayedWidget",       -- named frame (Bar)
  "TruePlayedStatsFrame",   -- named frame (Window)
}

read_globals = {
  -- SPEC 2.2: writable fields of otherwise read-only Blizzard tables.
  SlashCmdList = {
    other_fields = true,
    fields = { TRUEPLAYED = { read_only = false } },
  },
  StaticPopupDialogs = {
    other_fields = true,
    fields = { TRUEPLAYED_ERASE_CHAR = { read_only = false, other_fields = true } },
  },
  ChatFrameUtil = {
    other_fields = true,
    fields = { DisplayTimePlayed = { read_only = false } },   -- experimental hide only (SPEC 5.13)
  },
  -- colour pickers on clients before 10.2.5: the shared picker is set up through its fields
  -- (Options OpenColorPicker; newer clients take SetupColorPickerAndShow)
  ColorPickerFrame = {
    other_fields = true,
    fields = {
      hasOpacity = { read_only = false }, opacityFunc = { read_only = false },
      previousValues = { read_only = false, other_fields = true },
      func = { read_only = false }, cancelFunc = { read_only = false },
    },
  },
  -- `local unpack = unpack or table.unpack` idiom (SPEC 2.4).
  table = { fields = { unpack = {} } },

  -- SPEC 2.3: WoW API allowlist (read only).
  "GetTime", "time", "date", "format", "strsplit", "strtrim", "strjoin",
  "wipe", "tinsert", "tremove", "Mixin",
  "GetBuildInfo", "GetLocale", "C_AddOns", "GetAddOnMetadata",
  "C_Timer", "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME",
  "RequestTimePlayed", "hooksecurefunc", "securecallfunction", "geterrorhandler",
  "issecretvalue",
  "UnitName", "UnitGUID", "UnitClass", "UnitFactionGroup", "UnitIsDeadOrGhost",
  "UnitLevel", "UnitXP", "UnitXPMax", "GetXPExhaustion", "IsXPUserDisabled",
  "GetMaxPlayerLevel", "UnitIsAFK", "IsResting", "UnitOnTaxi", "GetRealmName",
  "IsInInstance", "GetInstanceInfo", "GetRealZoneText", "C_Map", "Enum",
  "InCombatLockdown", "IsShiftKeyDown", "GetFramerate", "GetNetStats", "GetCVar",
  "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "UpdateAddOnCPUUsage",
  "GetAddOnCPUUsage", "C_AddOnProfiler", "debugprofilestop", "C_XMLUtil",
  "Settings", "InterfaceOptions_AddCategory", "MenuUtil",
  "MinimalSliderWithSteppersMixin", "LibStub",
  "StaticPopup_Show", "StaticPopup_Hide", "UISpecialFrames",
  "STANDARD_TEXT_FONT", "YES", "NO",
  "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable",
  "BackdropTemplateMixin", "AddonCompartmentFrame",
  -- max level, layered as EllesmereUI's XP bar (Core Util.IsMaxLevel; guarded, may be nil)
  "IsPlayerAtEffectiveMaxLevel", "IsLevelAtEffectiveMaxLevel", "GetMaxLevelForPlayerExpansion",
  -- server level cap detection: the target of a kill without XP (Tracker; guarded, read
  -- at combat start / end and on target changes only)
  "UnitExists", "UnitIsDead", "UnitCanAttack", "UnitIsPlayer", "UnitPlayerControlled",
  "UnitIsTapDenied", "UnitClassification", "UnitCreatureType",
  "WTFIX_BOOTSTRAP", "WTFIX_DB",   -- read only: WTFix protection warning (Core)
  "ReloadUI",                      -- "Reload UI" button under the language option (Options, on click only)
}

-- Offline tests: the stubs define the whole WoW API as globals, so global checks are
-- off there; the other checks (unused values, shadowing, unreachable code) still apply.
files["tests"] = {
  std = "+lua51",
  allow_defined = true,
  allow_defined_top = true,
  read_globals = { "table", "os", "io" },
  ignore = { "1" },
}
