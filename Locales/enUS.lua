-- Locales/enUS.lua - base (English) strings of TruePlayed.
-- Creates ns.L, the one locale table every module captures at file load (never
-- replaced). A key missing in another locale falls back to this English text; a key
-- missing everywhere shows its own name (visible bug, never an error).
-- Also registers an English copy of the strings as ns.LOCALES.enUS (outside L): Core
-- applies the language chosen by the "language" setting into L when the settings are
-- adopted (English first, then the chosen locale over it), then drops ns.LOCALES at
-- PLAYER_LOGIN.
-- A new language <code> (a GetLocale() value such as deDE) needs, and only needs:
--   1. Locales/<code>.lua: a copy of frFR.lua with its CODE local set to "<code>" (the
--      registration and the file-load check both read it), every value translated, with
--      the same format arguments in the same order (tests/test_locales.lua);
--   2. TruePlayed_Camelot.toc: the file listed after the other locale files, and its
--      Notes-<code> / Category-<code> lines (Latin-1 languages only: the TOC is Latin-1);
--   3. Core.lua: <code> appended to C.LANGUAGES (the setting's values, the order of the
--      options dropdown and of the /tpl lang listing); a language whose script the fonts
--      of the other clients cannot draw (Cyrillic, Hangul, Han) also goes in
--      C.LANGUAGES_NATIVE_ONLY, and its locale file may then hold any UTF-8 character
--      (tests/check_encoding.lua NATIVE_LOCALES);
--   4. every locale file: a LANG_<CODE> key holding the language's name written in that
--      language (the same text in every file; outside Latin-1 as decimal escapes in the
--      Latin-1 files), and Options.lua LanguageLabel returning it for <code>;
--   5. Options.lua LANG_ALIAS: the short /tpl lang alias (optional: without one, the
--      listing shows the code and the command takes the code). HELP_LANG lists the
--      offered aliases by itself.
-- Short words: the bar, the tooltip rows, option labels, buttons and menu entries must
-- fit (tests/test_locales.lua measures them with the real fonts).
-- Keys marked [fmt] are format patterns: %s / %d arguments, literal percent as %%.
-- Latin-1 characters only (see SPEC-FINAL 2.6); the names of the native-only languages
-- are decimal escapes.
local _, ns = ...
local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

-- General and chat
L.ADDON_TITLE             = "TruePlayed"
L.CHAT_PREFIX             = "|cff8b5cf6TruePlayed|r: "
L.FIRST_RUN               = "Drag the bar where you like, then right-click > Lock. Hover it for details (Shift: more), click it for statistics. Options: /tpl"
L.ON                      = "on"
L.OFF                     = "off"
L.EXCL_STATE_FMT          = "%s: %s"  -- [fmt] exclusion label (MENU_EXCLUDE_*), ON/OFF
L.CITY_ADDED_FMT          = "%s now counts as a city."  -- [fmt] zone name
L.CITY_REMOVED_FMT        = "%s no longer counts as a city."  -- [fmt] zone name
L.NO_ZONE                 = "Current zone unknown, try again in a moment."
L.CITY_INSTANCE           = "Instances never count as cities."
L.UNKNOWN_CMD_FMT         = 'Unknown command "%s". Type /tpl help.'  -- [fmt] command
L.SYNC_REQUESTED          = "Asking the server for /played..."
L.SYNCED                  = "/played synced."
L.SYNC_THROTTLED          = "Please wait a few seconds before asking again."
L.RESET_POS_DONE          = "Position reset."
L.RESET_SESSION_DONE      = "Session reset."
L.RESET_RATE_DONE         = "XP per hour reset."
L.RESET_CHAR_DONE_FMT     = "Data erased for %s."  -- [fmt] character name
L.WIDGET_SHOWN            = "Bar shown."
L.WIDGET_HIDDEN           = "Bar hidden. Type /tpl show to bring it back."
L.MINIMAP_SHOWN           = "Minimap button shown."
L.MINIMAP_HIDDEN          = "Minimap button hidden. Type /tpl minimap to bring it back."
L.MINI_SHOWN              = "Mini display shown."
L.MINI_HIDDEN             = "Mini display hidden. Type /tpl mini to bring it back."
L.LOCKED                  = "Bar locked."
L.UNLOCKED                = "Bar unlocked: drag it to move it."
L.THEME_SET_FMT           = "Theme: %s"  -- [fmt] THEME_* name
L.THEME_LIST_FMT          = "Theme: %s. Available: %s"  -- [fmt] THEME_* name of the setting, theme keys (/tpl theme <key>)
L.LANG_SET_FMT            = "Language: %s. Type /reload to apply it."  -- [fmt] LANG_* name
L.LANG_LIST_FMT           = "Language: %s. Available: %s. A change applies after /reload."  -- [fmt] LANG_* name of the setting, accepted values (/tpl lang <value>)
L.DEBUG_ON                = "Debug messages on."
L.DEBUG_OFF               = "Debug messages off."
L.SCHEMA_NEWER            = "Your data was saved by a newer TruePlayed. Please update the addon; tracking is paused."
L.READONLY_ACTION         = "Not available: your data was saved by a newer TruePlayed (read-only mode)."
L.NOT_READY               = "TruePlayed did not finish loading (see the error window)."
L.COMBAT_DEFERRED         = "Options will open after combat."
L.EST_RECOVERED_FMT       = "Recovered %s of play time missing since your last save (crash or play without TruePlayed). Its split is estimated from your usual habits."  -- [fmt] duration
L.THEME_FONT_MISSING      = "A theme font could not be loaded (%s); the game font is used instead. Restart the game after an update."  -- [fmt] font file name (printed once per session, after CHAT_PREFIX)
L.WTFIX_PROTECTED         = "WTFix puts TruePlayed's data back to an older copy at every load, so your recent play history would be lost. Type /wtfix and untick TruePlayed: TruePlayed then keeps its own data and resyncs with the server /played."

-- Help
L.HELP_HEADER             = "Commands:"
L.HELP_OPTIONS            = "/tpl - options"
L.HELP_STATS              = "/tpl stats [levels | zones | sessions] - statistics window"
L.HELP_LOCK               = "/tpl lock | unlock - lock or move the bar"
L.HELP_SHOW               = "/tpl show | hide - show or hide the bar"
L.HELP_THEME              = "/tpl theme [name] - show or change the theme"
L.HELP_LANG               = "/tpl lang [%s] - show or change the language of TruePlayed (after /reload)"  -- [fmt] the offered /tpl lang values, joined by " | "
L.HELP_MINIMAP            = "/tpl minimap - show or hide the minimap button"
L.HELP_MINI               = "/tpl mini - show or hide the mini display"
L.HELP_EXCLUDE            = "/tpl afk | inn | city [on | off] - exclusions (no argument: toggle)"
L.HELP_CITY               = "/tpl citytoggle - count the current zone as a city (or not)"
L.HELP_PLAYED             = "/tpl played - summary in chat"
L.HELP_SYNC               = "/tpl sync - refresh the server /played"
L.HELP_RESET              = "/tpl reset pos | session | rate | char - reset the bar position, the session, XP per hour, or erase this character (asks first)"
L.HELP_DEBUG              = "/tpl debug - debug messages"
L.HELP_PERF               = "/tpl perf - memory and CPU used by TruePlayed"

-- /tpl played summary
L.SUM_HEADER_FMT          = "%s - level %d"  -- [fmt] name, level
L.SUM_PLAYED_FMT          = "Played: %s (server /played %s)"  -- [fmt] filtered, server
L.SUM_EXCLUDED_FMT        = "Excluded: %s (%s)"  -- [fmt] duration, mask label
L.SUM_LEVEL_FMT           = "This level: %s · average per level: %s"  -- [fmt] durations
L.SUM_ETA_FMT             = "Next level in %s at %s"  -- [fmt] ETA, rate
L.SUM_ETA_NONE            = "Next level: not enough data yet."
L.SUM_MAX                 = "Max level reached."
L.SUM_CAP_FMT             = "Level %d: current server level cap. XP tracking resumes by itself."  -- [fmt] level (detected server level cap)

-- /tpl perf
L.PERF_HEADER_FMT         = "TruePlayed %s - performance (client %d):"  -- [fmt] version, interface
L.PERF_MEM_FMT            = "Memory (code + saved data of all characters): %s KB"  -- [fmt] number
L.PERF_MEM_NA             = "Memory: not available on this client."
L.PERF_CPU_FMT            = "CPU: %s ms since load (%s ms per minute)"  -- [fmt] numbers
L.PERF_CPU_OFF            = "CPU: type /console scriptProfile 1 then /reload to measure. It slows the game: set it back to 0 afterwards."
L.PERF_PROFILER_FMT       = "Profiler: %s ms per frame on average, peak %s ms"  -- [fmt] numbers
L.PERF_DATA_FMT           = "Data of this character: levels %d, zones %d, sessions %d. Characters: %d"  -- [fmt] counts (label form: no plural agreement)
L.PERF_TICK_ARMED_FMT     = "Measuring the next %d seconds..."  -- [fmt] ticks
L.PERF_TICK_FMT           = "Tick: %s ms on average, %s ms max over %d ticks"  -- [fmt] numbers, count

-- Formats
L.DUR_D_H                 = "%dd %02dh"  -- [fmt] days, hours
L.DUR_H_M                 = "%dh %02dm"  -- [fmt] hours, minutes
L.DUR_H                   = "%dh"  -- [fmt] hours
L.DUR_M                   = "%dm"  -- [fmt] minutes
L.DUR_LT_1M               = "<1m"
L.DUR_LONG_DHM            = "%dd %dh %02dm"  -- [fmt]
L.DUR_LONG_HM             = "%dh %02dm"  -- [fmt]
L.DUR_LONG_M              = "%dm"  -- [fmt]
L.ETA_FMT                 = "~%s"  -- [fmt] duration
L.ETA_LT_1M               = "<1m"
L.AGO_FMT                 = "%s ago"  -- [fmt] duration
L.DECIMAL_SEP             = "."
L.THOUSANDS_SEP           = ","
L.NUM_K                   = "%sk"  -- [fmt] number text
L.NUM_M                   = "%sM"  -- [fmt] number text
L.PERCENT_FMT             = "%s%%"  -- [fmt] number text
L.PER_HOUR                = "/h"
L.FPS_FMT                 = "%s fps"  -- [fmt] coloured number
L.MS_FMT                  = "%s ms"  -- [fmt] coloured number
L.DATE_FMT                = "%m/%d/%Y"  -- date() pattern
L.DATETIME_FMT            = "%m/%d %H:%M"  -- date() pattern
L.DOTS                    = "..."
L.SEP                     = " · "
L.RANGE_FMT               = "%s » %s"  -- [fmt] from, to

-- Tokens (option labels) and token texts
L.TOKEN_NONE              = "Nothing"
L.TOKEN_ETA               = "Time to next level"
L.TOKEN_XPH               = "XP per hour"
L.TOKEN_PCTH              = "% of level per hour"
L.TOKEN_XPLEFT            = "XP to go"
L.TOKEN_RESTED            = "Rested XP"
L.TOKEN_LEVEL_TIME        = "Time this level"
L.TOKEN_SESSION           = "Session time"
L.TOKEN_PLAYED            = "Played (filtered)"
L.TOKEN_PLAYED_SERVER     = "Server /played"
L.TOKEN_AFK_SESSION       = "AFK this session"
L.TOKEN_AVG_LEVEL         = "Average time per level"
L.TOKEN_ZONE_TIME         = "Time in current zone"
L.TOKEN_FPS               = "FPS"
L.TOKEN_LATENCY           = "Latency"
L.TOKEN_FPS_LATENCY       = "FPS + latency"
L.TOKEN_KILLS             = "Mobs to kill"
L.TOKEN_ETA_KILLS         = "Time to level + mobs to kill"
L.TOKEN_INSTANCE_SESSION  = "Instance time this session"
L.TOKEN_INSTANCE_TOTAL    = "Total instance time"
L.PFX_LEVEL_FMT           = "Level %s"  -- [fmt] duration
L.PFX_SESSION_FMT         = "Session %s"  -- [fmt] duration
L.PFX_PLAYED_FMT          = "Total %s"  -- [fmt] duration
L.PFX_SERVER_FMT          = "/played %s"  -- [fmt] duration
L.PFX_AFK_FMT             = "AFK %s"  -- [fmt] duration
L.PFX_AVG_FMT             = "Avg %s/lvl"  -- [fmt] duration
L.PFX_ZONE_FMT            = "Zone %s"  -- [fmt] duration
L.PFX_INST_SESSION_FMT    = "Inst. %s"  -- [fmt] duration (instances this session)
L.PFX_INST_TOTAL_FMT      = "Inst. total %s"  -- [fmt] duration (instances, whole character)
L.XPLEFT_FMT              = "%s XP to go"  -- [fmt] number
L.RESTED_FMT              = "Rested %s"  -- [fmt] percent text
L.PCTH_FMT                = "%s%%/h"  -- [fmt] number text
L.KILLS_FMT               = "%s mobs"  -- [fmt] number text
L.KILLS_ONE_FMT           = "%s mob"  -- [fmt] number text (exactly 1)
L.STALL_MARK              = "*"  -- after a frozen XP per hour / time to level (no XP for a while)
L.CAP_SHORT               = "Server cap"  -- XP infos at a detected server level cap

-- Widget
L.LEVEL_SHORT_FMT         = "LEVEL %d"  -- [fmt] level
L.LEVEL_PCT_FMT           = "LEVEL %d · %s"  -- [fmt] level, percent text
L.LEVEL_CAP_FMT           = "LEVEL %d · CAP"  -- [fmt] level (detected server level cap)
L.XP_FMT                  = "XP: %s / %s"  -- [fmt] numbers
L.XP_BARE_FMT             = "%s / %s"  -- [fmt] numbers (narrow bar: the XP label is dropped)
L.XP_LABEL                = "XP:"  -- themes with split texts: label before the XP numbers (XP_BARE_FMT)
L.LEVEL_TITLE_FMT         = "Level %d"  -- [fmt] level (themes with title-case level texts)
L.LEVEL_CAP_TAG           = "CAP"  -- themes: detected server level cap, after the level (upper case)
L.LEVEL_CAP_TAG_TITLE     = "Cap"  -- themes: detected server level cap, after LEVEL_TITLE_FMT
L.UNLOCKED_HINT           = "Drag to move · Right-click: menu"
L.MAX_LEVEL               = "Max level"

-- Tooltip
L.TT_LEVEL_FMT            = "Level %d » %d"  -- [fmt] level, next level
L.TT_XP                   = "XP"
L.TT_REMAINING            = "To go"
L.TT_RESTED               = "Rested"
L.TT_RESTED_FMT           = "%s XP (%s)"  -- [fmt] number, percent of the level
L.TT_NEXT_LEVEL           = "Next level"
L.TT_XPH                  = "XP per hour"
L.TT_KILLS                = "Mobs to kill"
L.TT_KILLS_FMT            = "~%s (average: %s XP, last: %s XP)"  -- [fmt] count, average XP of the last 10 kills, XP of the last kill (both without rested bonus)
L.TT_KILLS_NODATA         = "shown after your next kill"
L.TT_RATES_FMT            = "session %s · level %s"  -- [fmt] rates
L.TT_WARMING_FMT          = "estimate in ~%s"  -- [fmt] duration
L.TT_NO_RATE              = "not enough data yet"
L.TT_NODATA_FMT           = "available after ~%s of counted play"  -- [fmt] duration
L.TT_NODATA_XP            = "available after your first XP gain"
L.RATE_ESTIMATE           = "estimate from your /played"
L.TT_SRC_LEVEL            = "based on this level so far"
L.TT_SRC_RECENT           = "based on your last levels"
L.TT_PAUSED_FMT           = "Timer paused: %s excluded"  -- [fmt] PAUSE_*
L.PAUSE_AFK               = "AFK time"
L.PAUSE_INN               = "inn time"
L.PAUSE_CITY              = "city time"
L.MASK_AFK                = "AFK"
L.MASK_INN                = "inn"
L.MASK_CITY               = "city"
L.TT_READONLY             = "Read-only: data from a newer TruePlayed"
L.TT_EXCL_FMT             = "excl. %s"  -- [fmt] mask label
L.TT_SESSION              = "Session"
L.TT_THIS_LEVEL           = "This level"
L.TT_ZONE_FMT             = "Zone: %s"  -- [fmt] zone name
L.TT_PLAYED               = "Played"
L.TT_PLAYED_EXCL_FMT      = "Played (excl. %s)"  -- [fmt] mask label
L.TT_PREINSTALL_FMT       = "incl. %s before install, unfiltered"  -- [fmt] duration
L.TT_EST_FMT              = "incl. %s rebuilt after a crash"  -- [fmt] duration
L.TT_SERVER               = "Server /played"
L.TT_SERVER_AGE_FMT       = "%s (%s)"  -- [fmt] duration, AGO text
L.TT_AVG_LEVEL            = "Average per level"
L.TT_AVG_RECENT_FMT       = "Average, last %d levels"  -- [fmt] count (always >= 2)
L.TT_BREAKDOWN            = "Breakdown"
L.BD_PART_FMT             = "%s %s"  -- [fmt] part label (BD_*), percent
L.BD_WORLD                = "World"
L.BD_DUNGEON              = "Dungeons"
L.BD_RAID                 = "Raids"
L.BD_PVP                  = "PvP"
L.BD_TAXI                 = "Flight"
L.BD_AFK                  = "AFK"
L.BD_INN                  = "Inn"
L.BD_CITY                 = "City"
L.BD_PROF                 = "Prof."  -- professions (gathering, crafting, fishing...)
L.BD_DEAD                 = "Dead"  -- dead or a ghost
L.TT_INSTANCES            = "In instances"
L.TT_HINT                 = "Shift: details · Click: stats · Right-click: menu"
L.TT_HINT_COMPARTMENT     = "Shift: details · Click: options · Right-click: stats"
L.TT_HINT_MM_OPTIONS      = "Shift: details · Click: options · Right-click: menu"  -- minimap button, left click = options (TT_HINT: statistics)
L.TT_HINT_MM_BAR          = "Shift: details · Click: XP bar · Right-click: menu"  -- left click = show / hide the XP bar
L.TT_HINT_MM_MINI         = "Shift: details · Click: mini display · Right-click: menu"  -- left click = show / hide the mini display
L.TT_MAX_LEVEL            = "Max level reached"
L.TT_CAP_FMT              = "Level %d: current server level cap (no XP from the last %d mobs)"  -- [fmt] level, mobs killed without XP (3 or more)
L.TT_CAP_RESUME           = "XP tracking resumes by itself as soon as the server gives XP again."
L.TT_STALLED_FMT          = "%s XP per hour frozen: no XP gained for %s of play"  -- [fmt] STALL_MARK, duration of counted play
L.TT_STALLED_RESUME       = "It resumes with your next XP gain; time spent without XP is left out."
L.TT_TOP_ZONES            = "Top zones this level"
L.TT_TOP_CITIES           = "Top capitals"
L.SECTION_CONTINENTS      = "Continents"
L.CONT_INSTANCES          = "Instances"
L.CONT_OTHER              = "Other"
L.TT_OF_WHICH_AFK_FMT     = "%s (AFK %s)"  -- [fmt] durations
L.TT_LAST_LEVELS          = "Last levels"
L.TT_LEVEL_ROW_FMT        = "Level %d"  -- [fmt] level
L.TT_INN                  = "Inn / rest area"
L.TT_CITY                 = "City"
L.TT_AFK                  = "AFK"
L.TT_TAXI                 = "Flight"
L.TT_DEATHS               = "Deaths"
L.TT_PROF                 = "Professions"
L.TT_UNTRACKED            = "Before install / untracked"
L.TT_UNTRACKED_NOTE       = "not split"
L.TT_EST_TOTAL            = "Rebuilt after crashes"
L.TT_EST_NOTE             = "estimated split"
L.TT_ACCOUNT_FMT          = "Account (%d characters)"  -- [fmt] count (2 or more)
L.TT_ACCOUNT_ONE_FMT      = "Account (%d character)"  -- [fmt] count (1)
L.TT_ACCOUNT_INST         = "Account, in instances"
L.TT_NET                  = "FPS · home · world"
L.TT_NET_FMT              = "%s · %s · %s"  -- [fmt] fps, home, world

-- Context menu
L.MENU_EXCLUDE_AFK        = "Exclude AFK time"
L.MENU_EXCLUDE_INN        = "Exclude inn / rest area time"
L.MENU_EXCLUDE_CITY       = "Exclude city time"
L.MENU_LOCK               = "Lock"
L.MENU_THEME              = "Theme"
L.MENU_STATS              = "Statistics..."
L.MENU_RESET_SESSION      = "Reset session"
L.MENU_HIDE               = "Hide"
L.MENU_OPTIONS            = "Options..."
L.MENU_SHOW               = "Show"  -- submenu: XP bar / mini display / minimap button on or off
L.MENU_SHOW_BAR           = "XP bar"
L.MENU_SHOW_MINI          = "Mini display"
L.MENU_SHOW_MINIMAP       = "Minimap button"

-- Options panel
L.OPT_EXCLUSIONS          = "Exclusions"
L.OPT_EXCLUSIONS_HELP     = "Exclusions only change what is shown: nothing is deleted and everything is recalculated right away."
L.OPT_CITY_HELP           = "Cities: Stormwind, Ironforge, Darnassus, Orgrimmar, Thunder Bluff, Undercity (/tpl citytoggle adds or removes the current zone). Inn / rest area: any other rest area."
L.OPT_DISPLAY             = "Display"
L.OPT_THEME               = "Theme"
L.OPT_THEME_NOTE          = "Changes the look of the bar, its tooltip, the graph and the statistics window. Colours you pick below replace the theme's own."
L.OPT_THEME_RESTART_NOTE  = "After installing or updating TruePlayed, restart the game (a /reload is not enough) so that the theme fonts and textures load."
L.OPT_SHOW                = "Show the bar"
L.OPT_SLOT1               = "Info 1 (large)"
L.OPT_SLOT2               = "Info 2"
L.OPT_SLOT3               = "Info 3"
L.OPT_SLOT3_POS           = "Info 3 position"
L.OPT_SLOTS_NOTE          = "Info 1 top right, info 2 after the XP, info 3 on top."
L.POS_CENTER              = "Top center"
L.POS_LEFT                = "Top left"
L.OPT_PCT_POS             = "Level percentage"
L.PCT_FOLLOW              = "Follows the bar"
L.PCT_LEVEL               = "Next to the level"
L.OPT_MAX_SLOTS           = "At max level, replace XP infos with:"
L.OPT_MAX_SLOT_FMT        = "Info %d at max level"  -- [fmt] slot index
L.OPT_WIDTH               = "Width"
L.OPT_HEIGHT              = "Bar height"
L.OPT_SCALE               = "Scale"
L.OPT_FONT_SIZE           = "Text size"
L.OPT_LOCK                = "Lock position"
L.OPT_COMBAT_HIDE         = "Hide in combat"
L.OPT_FADE                = "Fade when the mouse is away"
L.OPT_HIDE_MAX            = "Hide at max level"
L.OPT_LANGUAGE            = "Language (Langue)"
L.OPT_LANGUAGE_NOTE       = "The language of TruePlayed changes after a UI reload (button below or /reload). Names provided by the game (zones, mobs, instances, characters) stay in the language of the game client."
L.OPT_RELOAD              = "Reload UI"
L.LANG_AUTO               = "Auto"
L.LANG_ENUS               = "English"
L.LANG_FRFR               = "Français"
L.LANG_DEDE               = "Deutsch"
L.LANG_ESES               = "Español (EU)"
L.LANG_ESMX               = "Español (AL)"
L.LANG_ITIT               = "Italiano"
L.LANG_PTBR               = "Português (BR)"
L.LANG_RURU               = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185"  -- Russian, in Cyrillic (escaped: this file is Latin-1)
L.LANG_KOKR               = "\237\149\156\234\181\173\236\150\180"  -- Korean, in Hangul (escaped)
L.LANG_ZHCN               = "\231\174\128\228\189\147\228\184\173\230\150\135"  -- Simplified Chinese (escaped)
L.LANG_ZHTW               = "\231\185\129\233\171\148\228\184\173\230\150\135"  -- Traditional Chinese (escaped)
L.OPT_TEXTS               = "Texts"
L.OPT_TEXT_COLOR          = "Text colour"
L.OPT_TEXT_COLOR_RESET    = "Theme colours"
L.OPT_TEXT_COLOR_NOTE     = "Applies to every text of the bar. The colours of the bar itself are set below."
L.OPT_OUTLINE             = "Text outline"
L.OUTLINE_NONE            = "None"
L.OUTLINE_THIN            = "Thin"
L.OUTLINE_THICK           = "Thick"
L.OPT_SHADOW              = "Text shadow"
L.OPT_BG_ALPHA            = "Background opacity"
L.OPT_BAR_COLORS          = "Bar colours"
L.OPT_XP_COLOR            = "XP bar colour"
L.OPT_RESTED_COLOR        = "Rested XP colour"
L.OPT_BAR_COLORS_RESET    = "Theme colours"
L.OPT_BAR_COLORS_NOTE     = "Until you pick your own, the bar uses the theme's colours. While you are rested, the bar takes the rested XP colour, and a lighter shade of it shows how far your rested XP goes. At max level the bar is drawn full, in the XP bar colour, dimmed."
L.OPT_NET                 = "FPS and latency"
L.OPT_QUALITY_COLORS      = "Quality colours (green, yellow, red)"
L.OPT_QUALITY_COLORS_NOTE = "Unticked, FPS and latency use the text colour."
L.OPT_GRAPH_WINDOW        = "Graph history"
L.OPT_GRAPH_NOTE          = "Hover the FPS or latency on the bar to see their graph, then hover the graph to read a value. The game refreshes latency only about every 30 seconds."
L.OPT_MINI_SECTION        = "Minimap button and mini display"
L.OPT_MM_SHOW             = "Show the minimap button"
L.OPT_MM_LOCK             = "Lock the minimap button"
L.OPT_MM_CLICK            = "Button left click"
L.CLICK_STATS             = "Statistics"
L.CLICK_OPTIONS           = "Options"
L.CLICK_BAR               = "Toggle the XP bar"
L.CLICK_MINI              = "Toggle the mini display"
L.OPT_MM_NOTE             = "Hover the button for the bar's tooltip, right-click it for the menu, drag it around the minimap."
L.OPT_MINI_SHOW           = "Show the mini display"
L.OPT_MINI_NOTE           = "A small frame with the infos you choose, in the theme, text colour, outline and shadow of the bar. Hover it for the tooltip, right-click it for the menu, drag it to move it."
L.OPT_MINI_INFO_FMT       = "Info %d"  -- [fmt] info index (1 to 3)
L.OPT_MINI_LAYOUT         = "Layout"
L.LAYOUT_H                = "One line"
L.LAYOUT_V                = "Stacked"
L.OPT_MINI_XP             = "XP progress"
L.MINI_XP_NONE            = "None"
L.MINI_XP_PCT             = "Percentage"
L.MINI_XP_LINE            = "Thin bar"
L.MINI_XP_BOTH            = "Percentage + bar"
L.OPT_CALC                = "Calculation"
L.OPT_REACTIVITY          = "XP per hour reactivity"
L.OPT_REACTIVITY_HELP     = "How fast XP per hour follows your recent pace."
L.REACT_SLOW              = "Slow (90 min)"
L.REACT_NORMAL            = "Normal (60 min)"
L.REACT_FAST              = "Fast (20 min)"
L.OPT_REQUEST_PLAYED      = "Ask the server for /played at login"
L.OPT_REQUEST_PLAYED_HELP = "Needed to recover time after a crash. The usual /played lines appear once in chat, only if no other addon asked within 10 seconds."
L.OPT_HIDE_PLAYED         = "Hide the /played lines when TruePlayed asks (experimental)"
L.OPT_HIDE_PLAYED_HELP    = "Briefly intercepts the chat's /played display while TruePlayed's own request is pending. A /played you type is always shown. It may disturb the chat in dungeons: turn it off if you see chat errors."
L.OPT_HIDE_PLAYED_NA      = "Not available on this client."
L.OPT_CITIES              = "Cities"
L.OPT_CITY_CURRENT_FMT    = "Current zone: %s (%s)"  -- [fmt] zone name, CITY_YES/CITY_NO
L.CITY_YES                = "counted as a city"
L.CITY_NO                 = "not a city"
L.OPT_CITY_TOGGLE         = "Count / stop counting this zone as a city"
L.OPT_DATA                = "Data"
L.OPT_OPEN_STATS          = "Statistics..."
L.OPT_RESET_POS           = "Reset position"
L.OPT_RESET_SESSION       = "Reset session"
L.OPT_RESET_RATE          = "Reset XP per hour"
L.OPT_RESET_CHAR          = "Erase this character's data"
L.CONFIRM_ERASE_CHAR_FMT  = "Erase all TruePlayed data for %s? This cannot be undone."  -- [fmt] name
L.ERASE_YES               = "Yes"  -- the erase popup's buttons (the game's YES / NO follow the client)
L.ERASE_NO                = "No"
L.OPT_NOTE_PREINSTALL     = "Time played before TruePlayed was installed cannot be split and is never excluded."
L.OPT_NOTE_IDLE           = "The few minutes before the game flags you AFK automatically still count as active."
L.OPT_NOTE_CRASH          = "After a game crash (or play without TruePlayed), the missing time is taken back from the server /played and split using your own habits; it is marked as rebuilt."
L.OPT_NOTE_CITY           = "City time is counted by map: the whole capital counts as city, not only its inn."
L.OPT_NOTE_STALL_FMT      = "After %d minutes of play without any XP (a level cap, a long break in town...), XP per hour and the time to next level freeze: that time is left out, and they resume with your next XP gain."  -- [fmt] minutes
L.OPT_NOTE_CAP_FMT        = "A server with a temporary level cap (beta) is noticed when %d mobs in a row give no XP: the bar then looks like at max level, and goes back to normal by itself as soon as XP comes again."  -- [fmt] mobs
L.OPT_NOTE_READONLY       = "Read-only: your data was saved by a newer TruePlayed. Update the addon; nothing is recorded meanwhile."
L.OPT_VERSION_FMT         = "Version %s"  -- [fmt] version
L.SLIDER_PX_FMT           = "%d px"  -- [fmt] value
L.SLIDER_PCT_FMT          = "%d%%"  -- [fmt] value

-- Themes (display names: options dropdown, context menu, /tpl theme)
L.THEME_FUTURISTE         = "Futuristic"
L.THEME_ACTUEL            = "Classic"
L.THEME_HEROIC            = "Heroic fantasy"
L.THEME_PIXEL             = "Pixel (old school)"
L.THEME_CLASS             = "Class (automatic)"
L.THEME_WARRIOR           = "Warrior"
L.THEME_PALADIN           = "Paladin"
L.THEME_HUNTER            = "Hunter"
L.THEME_ROGUE             = "Rogue"
L.THEME_PRIEST            = "Priest"
L.THEME_SHAMAN            = "Shaman"
L.THEME_MAGE              = "Mage"
L.THEME_WARLOCK           = "Warlock"
L.THEME_DRUID             = "Druid"

-- Statistics window
L.WIN_TITLE               = "TruePlayed - statistics"
L.VIEW_ACCOUNT            = "Account (all characters)"
L.WIN_ERASE               = "Erase..."
L.WIN_FILTER_FMT          = "Times shown excl. %s"  -- [fmt] mask label
L.TAB_LEVELS              = "Levels"
L.TAB_ZONES               = "Zones"
L.TAB_SESSIONS            = "Sessions"
L.COL_LEVEL               = "Lv"
L.COL_TIME                = "Time"
L.COL_SERVER              = "Server"
L.COL_XPH                 = "XP/h"
L.COL_AFK                 = "AFK"
L.COL_INN                 = "Inn"
L.COL_CITY                = "City"
L.COL_INST                = "Inst."
L.COL_MAIN_ZONE           = "Main zone"
L.COL_REACHED             = "Reached"
L.COL_ZONE                = "Zone"
L.COL_RAW                 = "Raw"
L.COL_XP                  = "XP"
L.COL_DATE                = "Date"
L.COL_DURATION            = "Duration"
L.COL_LEVELS              = "Levels"
L.COL_DEATHS              = "Deaths"
L.COL_CHARS               = "Chars"
L.COL_AVG                 = "Average"
L.COL_DEAD                = "Dead"  -- time dead (deaths)
L.COL_ETA                 = "Est."  -- time to level estimated when the level began
L.ROW_IN_PROGRESS         = "in progress"
L.ROW_PARTIAL_TIP         = "Level started before TruePlayed was installed."
L.ROW_REC_TIP             = "Reached during a crash or while TruePlayed was off: time estimated from the server /played and your XP."
L.ROW_EST_TIP_FMT         = "Includes %s rebuilt after a crash (estimated split)."  -- [fmt] duration
L.ROW_GAP_TIP_FMT         = "Server time is %s longer than tracked time (not split)."  -- [fmt] duration
L.ROW_ZONES_FMT           = "Zones at level %d"  -- [fmt] level
L.ROW_ZONES_EMPTY         = "No zone recorded for this level."
L.LEVELS_HOVER_HINT       = "Hover a level to see its zones."
L.FOOTER_FMT              = "Average per level: %s · last %d levels: %s · total: %s"  -- [fmt] dur, count, dur, dur
L.FOOTER_ACCOUNT_FMT      = "Account average per level: %s (%d characters)"  -- [fmt] dur, count (2 or more)
L.FOOTER_ACCOUNT_ONE_FMT  = "Account average per level: %s (%d character)"  -- [fmt] dur, count (1)
L.FOOTER_ACCOUNT_NONE     = "Account average per level: not enough data yet"
L.CITIES_HEADER           = "Top capitals"
L.INSTANCES_HEADER        = "Most played instances"
L.INST_ROW_FMT            = "%s (%s)"  -- [fmt] instance name, KIND_*
L.KIND_DUNGEON            = "dungeon"
L.KIND_RAID               = "raid"
L.KIND_PVP                = "PvP"
L.FOOTER_INST_FMT         = "in instances: %s"  -- [fmt] duration
L.NO_DATA                 = "No data yet."
L.NO_SESSIONS_ACCOUNT     = "Sessions are listed per character."
L.CITY_MARK               = "(city)"
L.CHAR_FMT                = "%s - level %d"  -- [fmt] name, level
L.ZONE_UNKNOWN            = "Unknown zone"
L.ZONE_OTHER              = "Other zones"

-- FPS / latency graph (Graph.lua)
L.GRAPH_TITLE_FMT         = "FPS and latency over %s"  -- [fmt] GRAPH_WINDOW_*
L.GRAPH_WINDOW_30         = "30 s"
L.GRAPH_WINDOW_60         = "1 min"
L.GRAPH_WINDOW_300        = "5 min"
L.GRAPH_AGO_FMT           = "%s ago: %s · %s"  -- [fmt] age (GRAPH_AGE_*), FPS text, latency text
L.GRAPH_AGE_S_FMT         = "%d s"  -- [fmt] seconds (age below one minute)
L.GRAPH_AGE_MS_FMT        = "%d min %02d s"  -- [fmt] minutes, seconds
L.GRAPH_MIN_AVG_MAX_FMT   = "min %s · avg %s · max %s"  -- [fmt] values
L.GRAPH_LAT_NOTE          = "The game refreshes latency only about every 30 s: it is drawn as steps."
L.GRAPH_NO_DATA           = "Collecting samples..."

-- English copy for Core's language switch (frFR.lua may overwrite L on a French
-- client before the settings are known). Dropped by Core at PLAYER_LOGIN.
-- Keep this block LAST: a string defined below it would be missing from the copy.
do
  local en = {}
  for k, v in pairs(L) do en[k] = v end
  local reg = ns.LOCALES
  if type(reg) ~= "table" then
    reg = {}
    ns.LOCALES = reg
  end
  reg.enUS = en
end
