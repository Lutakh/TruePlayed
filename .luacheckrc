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
  "TruePlayedMinimapButton",  -- named frame (MinimapButton)
  "TruePlayedMiniDisplay",  -- named frame (MiniDisplay)
  "TruePlayedCharTooltip",  -- named frame (Tooltip: block 2 of the native themes, a GameTooltip)
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
  -- activity states (Activity.lua, lot 8): dead (a hunter's Feign Death is not), the
  -- profession spells by name (C_Spell.GetSpellName or GetSpellInfo, events only), a
  -- window open while standing still, the craft window's name (Beast Training is not a
  -- profession). Guarded: any of them may be nil.
  "UnitIsFeignDeath", "GetSpellInfo", "C_Spell", "GetUnitSpeed", "GetCraftName",
  "WTFIX_BOOTSTRAP", "WTFIX_DB",   -- read only: WTFix protection warning (Core)
  "ReloadUI",                      -- "Reload UI" button (Options) and the prompt's "Reload now"
                                   -- (AutoReload), on click; the automatic reload without a click
                                   -- only on clients that allow it (not WoW Forever)
  -- automatic reload (AutoReload.lua): is the player busy? Read at the due moment only,
  -- each one type-checked (some clients lack some of them)
  "UnitAffectingCombat", "UnitCastingInfo", "UnitChannelInfo", "GetCurrentKeyBoardFocus",
  "StaticPopup_IsAnyDialogShown", "GetUIPanel", "InCinematic", "MovieFrame", "ReadyCheckFrame",
  "CursorHasItem", "SpellIsTargeting", "IsPlayerMoving",
  "SettingsPanel", "GameMenuFrame", "KeyBindingFrame", "InterfaceOptionsFrame",   -- no UI panel area
  -- minimap button (MinimapButton.lua: its parent, the drop angle, the minimap shape of
  -- minimap addons; read when the button is created, placed or dropped)
  "Minimap", "GetCursorPosition", "GetMinimapShape",
  -- watched reputation (Reputation.lua, on events only; guarded, any may be nil): the modern
  -- and the Classic Era reads, the retail-only kinds (renown, friendships), the standing
  -- colours; the player's sex for the standing name (Tooltip.lua); the game's label of the
  -- watch checkbox (Options.lua, the option's help)
  "C_Reputation", "GetWatchedFactionInfo", "C_GossipInfo", "FACTION_BAR_COLORS", "UnitSex",
  "SHOW_FACTION_ON_MAINSCREEN",
  -- the faction chosen in the options and the picker's list (Reputation.lua, Classic Era's
  -- globals; the options' menu only, guarded)
  "GetFactionInfoByID", "GetNumFactions", "GetFactionInfo", "ExpandFactionHeader",
  "CollapseFactionHeader",
  -- PvP (Pvp.lua, on events only; guarded, any may be nil, absent on Classic Era): the
  -- honor currency, the PvP rank (major faction 2800), the week and season, the weekly
  -- and daily resets, the honorable kills, a battleground's winner (after the match); the
  -- cap alert's sound
  "C_CurrencyInfo", "C_MajorFactions", "C_SeasonInfo", "C_DateAndTime",
  "GetPVPSessionStats", "GetPVPYesterdayStats", "GetPVPLifetimeStats", "GetBattlefieldWinner",
  "PlaySound", "SOUNDKIT",
  -- the player's side in a match (the winner is compared with it) and the PvP season's
  -- number (a lower season total without a new season is a transient read)
  "GetBattlefieldArenaFaction", "GetCurrentArenaSeason",
}

-- Themes.lua alone reads the chunk loaders: it compiles the theme source texts in an empty
-- environment (loadstring + setfenv on Lua 5.1, the game; load on 5.2+; NEXT-LOT M3).
files["Themes.lua"] = {
  read_globals = { "loadstring", "setfenv", "load" },
}

-- Offline tests: the stubs define the whole WoW API as globals, so global checks are
-- off there; the other checks (unused values, shadowing, unreachable code) still apply.
-- Offline tools that render images of the addon for the CurseForge page (never shipped).
files["media-src"] = {
  std = "+lua51",
  read_globals = { "os", "io", "dofile" },
}

files["tests"] = {
  std = "+lua51",
  allow_defined = true,
  allow_defined_top = true,
  read_globals = { "table", "os", "io" },
  ignore = { "1" },
}
