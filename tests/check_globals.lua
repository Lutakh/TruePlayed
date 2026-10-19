-- tests/check_globals.lua - run-time check of the addon's global accesses (SPEC 2.2, 2.3).
-- Usage (from anywhere): lua tests/check_globals.lua [-v]
-- Runs on Lua 5.1 and 5.5. Exit code 0 = OK, 1 = problems found.
--
-- lint51.lua checks global names statically; this script checks what really happens.
-- Every file of the TOC is loaded inside the offline stub with a private environment:
--   * a WRITE to a global outside the SPEC 2.2 whitelist raises at once (file:line) and
--     is reported, even when the addon catches the error;
--   * every global READ is recorded and must be in the SPEC 2.3 allowlist (plus the
--     Lua standard library and the whitelisted names);
--   * the Blizzard tables the addon may touch (SlashCmdList, StaticPopupDialogs,
--     UISpecialFrames, ChatFrameUtil) only gain the whitelisted entries, and a few
--     shared tables and frames (GameTooltip, UIParent, the chat frame, Enum, C_Map,
--     C_Timer, string, table, math) gain no field at all.
-- Scenarios walk through most code paths: login, XP and level-ups, every state, the
-- widget, tooltips (short and Shift), the statistics window (every tab
-- and view), the options panel (Settings + modern controls, and the standalone
-- fallback), the context menu, every slash command, the broker, the compartment
-- functions, the experimental /played hide, combat hide, crash and /reload restarts,
-- a late SavedVariables swap, a WTFix-style late table, a table applied at logout,
-- read-only mode, frFR and max level, the server level cap of the Forever beta and a frozen
-- rate (round 3), the language option (French chosen on an enUS client, English on a
-- frFR client through a late table), and every theme (design/SPEC-themes.md 8.3: the 14
-- setting values with the tooltip, graph and window shown in each, the options, /tpl
-- theme), the automatic reload (direct countdown, the prompt and its "Reload now"
-- click, a blocked ReloadUI(), a busy player), and the watched reputation (the strip and
-- its tooltip line in every theme, the Forever and Classic Era APIs). The other
-- scenarios keep the stub's default theme (Stub.theme = "actuel"). Any error reported
-- through geterrorhandler also fails the check.

local ROOT
do
  local script = ((arg and arg[0]) or "tests/check_globals.lua"):gsub("\\", "/")
  local root, n = script:gsub("tests/check_globals%.lua$", "")
  if n == 0 then
    local r2, n2 = script:gsub("check_globals%.lua$", "")
    if n2 > 0 then root = r2 .. "../" else root = "./" end
  end
  if root == "" then root = "./" end
  ROOT = root
end

local verbose = false
for i = 1, (arg and #arg or 0) do
  if arg[i] == "-v" then verbose = true end
end

local Stub = dofile(ROOT .. "tests/wowstub.lua")
Stub.ROOT = ROOT
for _, name in ipairs({ "stub_ui", "stub_activity", "stub_reputation", "stub_pvp" }) do
  local f = io.open(ROOT .. "tests/" .. name .. ".lua", "r")
  if f then
    f:close()
    Stub.AddInstaller(dofile(ROOT .. "tests/" .. name .. ".lua"))
  end
end

---------------------------------------------------------------------------
-- Allowed names
---------------------------------------------------------------------------

local function Set(list)
  local t = {}
  for i = 1, #list do t[list[i]] = true end
  return t
end

-- SPEC 2.2: the only global names the addon may assign.
local WRITE_OK = Set({
  "TruePlayedDB", "SLASH_TRUEPLAYED1", "SLASH_TRUEPLAYED2",
  "TruePlayed_OnAddonCompartmentClick", "TruePlayed_OnAddonCompartmentEnter",
  "TruePlayed_OnAddonCompartmentLeave",
})

-- SPEC 2.3 allowlist + Lua standard library (no os, io, debug, load*, print...).
local READ_OK = Set({
  "GetTime", "time", "date", "format", "strsplit", "strtrim", "strjoin", "wipe", "tinsert",
  "tremove", "Mixin", "GetBuildInfo", "GetLocale", "C_AddOns", "GetAddOnMetadata", "C_Timer",
  "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "ChatFrameUtil",
  "RequestTimePlayed", "hooksecurefunc", "securecallfunction", "geterrorhandler",
  "issecretvalue", "UnitName", "UnitGUID", "UnitClass", "UnitFactionGroup",
  "UnitIsDeadOrGhost", "UnitLevel", "UnitXP", "UnitXPMax", "GetXPExhaustion",
  "IsXPUserDisabled", "GetMaxPlayerLevel", "UnitIsAFK", "IsResting", "UnitOnTaxi",
  "GetRealmName", "IsInInstance", "GetInstanceInfo", "GetRealZoneText", "C_Map", "Enum",
  "InCombatLockdown", "IsShiftKeyDown", "GetFramerate", "GetNetStats", "GetCVar",
  "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "UpdateAddOnCPUUsage",
  "GetAddOnCPUUsage", "C_AddOnProfiler", "debugprofilestop", "C_XMLUtil", "Settings",
  "InterfaceOptions_AddCategory", "MenuUtil", "MinimalSliderWithSteppersMixin", "LibStub",
  "StaticPopup_Show", "StaticPopup_Hide", "StaticPopupDialogs", "SlashCmdList",
  "UISpecialFrames", "STANDARD_TEXT_FONT", "YES", "NO", "GameFontNormal",
  "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "BackdropTemplateMixin",
  "AddonCompartmentFrame",
  "WTFIX_BOOTSTRAP", "WTFIX_DB",   -- read only: WTFix protection warning (Core)
  "ColorPickerFrame",              -- text colour picker (Options; SetupColorPickerAndShow, as TinyTooltip)
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
  -- watched reputation (Reputation.lua, on events only; guarded, any may be nil): the modern
  -- and the Classic Era reads, the retail-only kinds (renown, friendships), the standing
  -- colours; the player's sex for the standing name (Tooltip.lua, which reads the
  -- FACTION_STANDING_LABEL<n> strings through _G); the game's label of the watch checkbox
  -- (Options.lua, the option's help)
  "C_Reputation", "GetWatchedFactionInfo", "C_GossipInfo", "FACTION_BAR_COLORS", "UnitSex",
  "SHOW_FACTION_ON_MAINSCREEN",
  -- the faction chosen in the options and the picker's list (Reputation.lua, Classic Era's
  -- globals; the options' menu only, guarded)
  "GetFactionInfoByID", "GetNumFactions", "GetFactionInfo", "ExpandFactionHeader",
  "CollapseFactionHeader",
  -- PvP (Pvp.lua, on events only; guarded, any may be nil, absent on Classic Era): the
  -- honor currency, the PvP rank (major faction 2800), the week and season, the weekly
  -- and daily resets, the honorable kills, a battleground's winner (after the match); the
  -- cap alert's sound. Tooltip.lua reads the rank titles (PVP_RANK_<n>_<faction>) through _G.
  "C_CurrencyInfo", "C_MajorFactions", "C_SeasonInfo", "C_DateAndTime",
  "GetPVPSessionStats", "GetPVPYesterdayStats", "GetPVPLifetimeStats", "GetBattlefieldWinner",
  "PlaySound", "SOUNDKIT",
  -- the player's side in a match (the winner is compared with it) and the PvP season's
  -- number (a lower season total without a new season is a transient read)
  "GetBattlefieldArenaFaction", "GetCurrentArenaSeason",
  -- Lua standard library
  "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal",
  "rawget", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "unpack",
  "xpcall", "math", "string", "table", "coroutine", "_VERSION",
})
for k in pairs(WRITE_OK) do READ_OK[k] = true end

-- Globals one file only may read: Themes.lua compiles the theme source texts in an empty
-- environment (loadstring + setfenv on Lua 5.1, the game; load with an environment on
-- 5.2+, design/NEXT-LOT.md M3). A read from any other file is reported.
-- Tooltip.lua reads _G for the client's own line texts of its GameTooltips
-- ("<name>TextLeft<i>", looked up once per line), to line up the two blocks' breakdown
-- lines side by side in the native themes.
local READ_OK_IN = {
  loadstring = "Themes.lua", setfenv = "Themes.lua", load = "Themes.lua",
  _G = "Tooltip.lua",
}

---------------------------------------------------------------------------
-- The addon environment
---------------------------------------------------------------------------

local problems, seen = {}, {}
local function Problem(msg)
  local n = seen[msg]
  if n then
    seen[msg] = n + 1                 -- the same finding again: counted, printed once
    return
  end
  seen[msg] = 1
  problems[#problems + 1] = msg
end

local reads, readWhere = {}, {}
local readOutside = {}   -- [name] = where a file other than its READ_OK_IN file read it
local badWrites = {}

local function Where(level)
  local info = debug.getinfo(level, "Sl")
  if not info then return "?" end
  return (info.short_src or "?") .. ":" .. tostring(info.currentline or 0)
end

local function FileOf(where)
  return (where:gsub(":%d+$", ""):gsub("\\", "/"):match("([^/]+)$")) or where
end

local env = setmetatable({}, {
  __index = function(_, k)
    if not reads[k] then
      reads[k] = true
      readWhere[k] = Where(3)
    end
    local only = READ_OK_IN[k]
    if only and not readOutside[k] then
      local where = Where(3)
      if FileOf(where) ~= only then readOutside[k] = where end
    end
    return _G[k]
  end,
  __newindex = function(_, k, v)
    if not WRITE_OK[k] then
      local where = Where(3)
      if not badWrites[k] then
        badWrites[k] = where
        Problem(string.format("%s: assigns the global '%s' (not in the SPEC 2.2 whitelist)", where, tostring(k)))
      end
      error(string.format("check_globals: unexpected global write '%s'", tostring(k)), 2)
    end
    _G[k] = v
  end,
})

local SETFENV = rawget(_G, "setfenv")   -- Lua 5.1 only

local function TocFiles()
  local f = io.open(ROOT .. "TruePlayed_Camelot.toc", "r")
  if not f then return Stub.FILES end
  local files = {}
  for raw in f:lines() do
    local line = raw:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then files[#files + 1] = (line:gsub("\\", "/")) end
  end
  f:close()
  return files
end
local FILES = TocFiles()

-- Replaces Stub.LoadAddon (Stub.Restart calls it too): same files, private environment.
local function StrictLoadAddon(opts)
  local files = (opts and opts.files) or FILES
  local ns = {}
  Stub.ns = ns
  for i = 1, #files do
    local path = ROOT .. files[i]
    local chunk, err = loadfile(path, "t", env)   -- 5.1 ignores the extra arguments
    if not chunk then error("check_globals: " .. tostring(err), 2) end
    if SETFENV then SETFENV(chunk, env) end
    chunk("TruePlayed", ns)
  end
  if Stub.ApplyThemeHook then Stub.ApplyThemeHook(ns) end   -- Stub.theme, as Stub.LoadAddon
  return ns
end
Stub.LoadAddon = StrictLoadAddon

---------------------------------------------------------------------------
-- Shared tables: key snapshots
---------------------------------------------------------------------------

local WATCHED = {   -- global name -> allowed new keys (true = any "_"-prefixed stub field)
  SlashCmdList = { TRUEPLAYED = true },
  StaticPopupDialogs = { TRUEPLAYED_ERASE_CHAR = true },
  ChatFrameUtil = {},
  GameTooltip = { stubFields = true },
  UIParent = { stubFields = true },
  DEFAULT_CHAT_FRAME = { stubFields = true },
  Enum = {}, C_Map = {}, C_Timer = {}, C_AddOns = {}, string = {}, table = {}, math = {},
}

local function Snapshot()
  local snap = {}
  for name in pairs(WATCHED) do
    local t = rawget(_G, name)
    if type(t) == "table" then
      local keys = {}
      for k, v in pairs(t) do keys[k] = v end
      snap[name] = { tbl = t, keys = keys }
    end
  end
  local usf = rawget(_G, "UISpecialFrames")
  snap.UISpecialFrames = type(usf) == "table" and #usf or 0
  return snap
end

local function CompareSnapshot(label, snap)
  for name, rec in pairs(snap) do
    if name ~= "UISpecialFrames" and rawget(_G, name) == rec.tbl then
      local allowed = WATCHED[name]
      for k, v in pairs(rec.tbl) do
        local stubField = allowed.stubFields and type(k) == "string" and k:sub(1, 1) == "_"
        if rec.keys[k] == nil and not allowed[k] and not stubField then
          Problem(string.format("%s: new field %s.%s", label, name, tostring(k)))
        elseif name == "ChatFrameUtil" and rec.keys[k] ~= nil and rec.keys[k] ~= v then
          Problem(string.format("%s: ChatFrameUtil.%s not restored", label, tostring(k)))
        end
      end
    end
  end
  local usf = rawget(_G, "UISpecialFrames")
  if type(usf) == "table" then
    for i = snap.UISpecialFrames + 1, #usf do
      if usf[i] ~= "TruePlayedStatsFrame" then
        Problem(string.format("%s: UISpecialFrames gained %s", label, tostring(usf[i])))
      end
    end
  end
end

---------------------------------------------------------------------------
-- Scenario helpers
---------------------------------------------------------------------------

local OTHER_GUID = "Player-4619-0BADF00D"

local function OtherRecord()
  return {
    guid = OTHER_GUID, name = "Tamar", realm = "Brisevent", class = "WARRIOR", faction = "Horde",
    level = 30, firstSeen = 1789000000, lastSeen = 1789500000,
    base = { at = 1789000000, total = 100, level = 1 },
    life = { s = { w = 90000, C = 400, c = 900 }, xp = 500000, xa = 500000, xr = 0, xq = 0, d = 3, est = 0 },
    levels = {
      [29] = { s = { w = 8000 }, z = { [1446] = { s = { w = 8000 }, xp = 2000 } },
               xp = 2000, xa = 2000, xr = 0, xq = 0, d = 0, t0 = 1789300000, t1 = 1789400000 },
      [30] = { s = { w = 4000 }, z = { [1446] = { s = { w = 4000 }, xp = 1000 } },
               xp = 1000, xa = 1000, xr = 0, xq = 0, d = 0, t0 = 1789400000 },
    },
    zones = { [1446] = { s = { w = 90000 }, xp = 500000, name = "Tanaris" },
              [1454] = { s = { c = 900, C = 400 }, xp = 0, name = "Orgrimmar" } },
    sessions = { { t0 = 1789300000, t1 = 1789310000, l0 = 29, p0 = 0.1, l1 = 29, p1 = 0.9,
                   s = { w = 10000 }, xp = 2000, d = 0 } },
  }
end

local function Sync()
  Stub.Fire("TIME_PLAYED_MSG", math.floor(Stub.server.total), math.floor(Stub.server.levelPlayed))
end

-- Clicks every item of a recorded menu description (depth first).
local function ClickAll(root, skip)
  if type(root) ~= "table" then return end
  local ui = Stub.ui
  for i = 1, #(root.children or {}) do
    local item = root.children[i]
    if not (skip and skip[item.text]) then
      if item.isSelected then item.isSelected(item.data) end
      if item.kind == "checkbox" or item.kind == "radio" or item.kind == "button" then
        ui.ClickMenuItem(item)
      end
    end
    ClickAll(item, skip)
  end
end

local SETTINGS = {
  { "exclude.afk", true }, { "exclude.inn", true }, { "exclude.city", true },
  { "widget.scale", 1.25 },
  { "widget.width", 420 }, { "widget.height", 12 }, { "widget.fontSize", 13 },
  { "widget.bgAlpha", 0.5 }, { "widget.bgAlpha", 0 }, { "widget.bgAlpha", 1 },
  { "widget.textColor", { 1, 0.82, 0 } }, { "widget.textColor", { r = 0.2, g = 0.9, b = 0.4 } },
  { "widget.outline", "none" }, { "widget.outline", "thick" }, { "widget.outline", "thin" },
  { "widget.shadow", false }, { "widget.shadow", true },
  { "widget.qualityColors", false }, { "widget.qualityColors", true },
  { "graph.window", 30 }, { "graph.window", 300 }, { "graph.window", 60 },
  { "widget.slots.1", "kills" }, { "widget.slots.2", "instance_session" },
  { "widget.slots.3", "instance_total" }, { "widget.maxSlots.1", "instance_total" },
  { "widget.maxSlots.2", "instance_session" }, { "widget.slots.1", "eta_kills" },
  { "widget.slots.1", "played" }, { "widget.slots.2", "fps" }, { "widget.slots.3", "latency" },
  { "widget.slots.1", "pcth" }, { "widget.slots.2", "xpleft" }, { "widget.slots.3", "rested" },
  { "widget.slots.1", "level_time" }, { "widget.slots.2", "session" },
  { "widget.slots.3", "played_server" }, { "widget.slots.1", "afk_session" },
  { "widget.slots.2", "avg_level" }, { "widget.slots.3", "zone_time" },
  { "widget.slots.1", "none" }, { "widget.slots.2", "fps_latency" },
  { "widget.maxSlots.1", "zone_time" }, { "widget.maxSlots.2", "none" }, { "widget.maxSlots.3", "fps" },
  { "widget.slot3Pos", "left" }, { "widget.pctPos", "level" },
  { "widget.slot3Pos", "center" }, { "widget.pctPos", "follow" },
  { "widget.point", { "TOPLEFT", "TOPLEFT", 12.4, -80.6 } },
  { "widget.locked", true }, { "widget.combatHide", true }, { "widget.fade", true },
  { "widget.hideAtMax", true }, { "rateTau", 1200 }, { "rateTau", 5400 },
  { "requestPlayedAtLogin", false }, { "requestPlayedAtLogin", true },
  { "debug", true }, { "firstRunDone", true },
  { "exclude.afk", false }, { "exclude.inn", false }, { "exclude.city", false },
  { "widget.textColor", false },
  { "widget.xpColor", { 1, 0.5, 0 } }, { "widget.restedColor", { r = 0, g = 0.8, b = 0.2 } },
  { "widget.xpColor", false }, { "widget.restedColor", false },
  { "widget.slots.1", "eta_kills" }, { "widget.slots.2", "xph" }, { "widget.slots.3", "fps_latency" },
  { "language", "frFR" }, { "language", "enUS" }, { "language", "auto" },
}

local function ApplyAllSettings(ns)
  for i = 1, #SETTINGS do ns.Core.SetSetting(SETTINGS[i][1], SETTINGS[i][2]) end
  ns.Core.SetSetting("debug", false)
end

local SLASH = {
  "", "help", "stats", "stats zones", "stats sessions", "stats sessions", "lock", "unlock",
  "hide", "show", "afk on", "afk off", "afk",
  "afk", "inn", "inn", "city on", "city off", "citytoggle", "citytoggle", "played",
  "sync", "reset pos", "reset session", "reset rate", "reset nothing", "debug", "played",
  "debug", "perf", "bogus command",
  "lang", "lang fr", "lang FR", "lang en", "lang enus", "lang frfr", "lang", "lang xx", "lang auto",
}

local function RunAllSlash()
  for i = 1, #SLASH do
    Stub.RunSlash(SLASH[i])
    Stub.Advance(1)
  end
end

local function Exercise(ns)
  local bar = ns.Bar.frame
  -- XP, quests, rest, every state and zone kind
  for _ = 1, 8 do
    Stub.Advance(30)
    Stub.GrantXP(250)
  end
  Stub.GrantXP(400, { quest = 400 })
  Stub.player.rest = 3000
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
  Stub.GrantXP(200, { restDrop = 200 })
  Stub.GrantXP(200, { restDrop = 200, order = "exhaustionFirst" })
  Stub.SetAFK(true); Stub.Advance(40); Stub.SetAFK(false)
  Stub.SetMap(1454); Stub.Advance(40)
  Stub.SetMap(90003); Stub.Advance(10)
  Stub.SetMap(1411); Stub.SetResting(true); Stub.Advance(30); Stub.SetResting(false)
  Stub.SetTaxi(true); Stub.Advance(30); Stub.SetTaxi(false); Stub.Advance(1)
  Stub.SetInstance(true, "party", 389, 90001); Stub.Advance(20)
  Stub.Kill(120); Stub.Kill(60, { count = 3 }); Stub.Advance(1)
  Stub.SetAFK(true); Stub.Advance(10); Stub.SetAFK(false)
  Stub.SetInstance(true, "party", 777, nil); Stub.Advance(5)
  Stub.Kill(90, { marker = false }); Stub.Advance(5)
  Stub.SetInstance(true, "raid", 409, nil); Stub.Advance(10)
  Stub.SetInstance(true, "scenario", 1001, nil); Stub.Advance(5)
  Stub.SetInstance(true, "pvp", 30, nil); Stub.Advance(10)
  Stub.SetInstance(true, "arena", 562, nil); Stub.SetAFK(true); Stub.Advance(5); Stub.SetAFK(false)
  Stub.SetInstance(false, nil, 0, 1411)
  Stub.Advance(5)
  Stub.Kill(80); Stub.Kill(70, { marker = "after" }); Stub.Advance(1)
  Stub.Kill(75, { marker = false }); Stub.Advance(0.5)
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "late message"); Stub.Advance(1)
  Stub.Discover(150); Stub.Advance(5)
  Stub.SetMap(nil); Stub.Advance(5); Stub.SetMap(2521); Stub.Advance(5); Stub.SetMap(1411)
  Stub.Fire("PLAYER_DEAD")
  Stub.GrantXP(Stub.player.max, { levelEventFirst = true })
  Stub.GrantXP(Stub.player.max, { noLevelEvent = true }); Stub.Advance(2)
  Stub.Fire("PLAYER_LEVEL_UP", Stub.player.level)
  Stub.Advance(8)

  -- widget scripts and tooltips
  if bar then
    Stub.RunScript(bar, "OnEnter")
    Stub.SetShift(true); Stub.Advance(2); Stub.SetShift(false); Stub.Advance(1)
    Stub.RunScript(bar, "OnLeave")
    Stub.RunScript(bar, "OnMouseDown", "LeftButton")
    Stub.RunScript(bar, "OnMouseUp", "LeftButton")
    Stub.RunScript(bar, "OnMouseDown", "RightButton")
    Stub.RunScript(bar, "OnMouseUp", "RightButton")
    ns.Core.SetSetting("widget.locked", false)
    Stub.RunScript(bar, "OnMouseDown", "LeftButton")
    Stub.RunScript(bar, "OnDragStart", "LeftButton")
    Stub.RunScript(bar, "OnDragStop")
    Stub.RunScript(bar, "OnMouseUp", "LeftButton")      -- ends the drag (not a click)
  end
  ns.Tooltip.Fill(Stub.NewTooltip(), true)
  ns.Tooltip.Fill(Stub.NewTooltip(), false)

  -- FPS / latency history graph (Graph.lua): shown, refreshed by a few ticks, hidden
  -- (directly, then through the hover regions the bar puts over FPS / latency texts)
  local Graph = ns.Graph
  if bar then
    for _, win in ipairs({ 30, 300, 60 }) do
      ns.Core.SetSetting("graph.window", win)
      Graph.ShowFor(bar)
      Stub.Advance(3)
      Graph.Hide()
      Stub.Advance(1)
    end
    for _, hit in pairs(bar.tp.hits) do
      Stub.RunScript(hit, "OnEnter")
      Stub.Advance(2)
      local cols = Graph.frame and Graph.frame.tp.cols
      if cols then
        Stub.RunScript(cols[30], "OnEnter")
        Stub.RunScript(cols[30], "OnLeave")
      end
      Stub.RunScript(hit, "OnLeave")
      Stub.Advance(1)
    end
  end

  -- statistics window: every tab and view
  ns.Window.Show()
  for _, tab in ipairs({ "levels", "zones", "sessions" }) do
    ns.Window.Toggle(tab)
    ns.Window.SetView("account")
    ns.Window.SetView(OTHER_GUID)
    ns.Window.SetView(nil)
    Stub.Advance(6)
  end
  local wf = rawget(_G, "TruePlayedStatsFrame")
  if wf and wf.tp then
    for _, row in ipairs(wf.tp.rows) do
      Stub.RunScript(row, "OnEnter")
      Stub.RunScript(row, "OnLeave")
    end
    for _, b in ipairs({ wf.tp.prev, wf.tp.next, wf.tp.next }) do Stub.RunScript(b, "OnClick", "LeftButton") end
    Stub.RunScript(wf.tp.erase, "OnClick", "LeftButton")
    for _, b in pairs(wf.tp.tabs) do Stub.RunScript(b, "OnClick", "LeftButton") end
  end
  -- the Levels chart (LevelChart, LevelDetail): every bar hovered and clicked under every
  -- filter, the hide-upcoming toggle, the PvP chip, the detail sheet's PvP row (a
  -- battleground and world PvP added to the viewed level), the current and another
  -- character, then the account view
  for _, view in ipairs({ "current", OTHER_GUID }) do
    ns.Window.Show("levels", view)
    local ch = wf and wf.tp.chart
    if ch then
      for f = 1, #ch.filters do
        Stub.RunScript(ch.filters[f].btn, "OnClick", "LeftButton")
        for k = 1, ch.state.nCols do
          local hit = ch.cols[k].hit
          Stub.RunScript(hit, "OnEnter")
          Stub.RunScript(hit, "OnClick", "LeftButton")
          Stub.RunScript(hit, "OnLeave")
        end
      end
      Stub.RunScript(ch.filters[1].btn, "OnClick", "LeftButton")
      Stub.RunScript(ch.toggle, "OnClick", "LeftButton")
      Stub.RunScript(ch.toggle, "OnClick", "LeftButton")
      -- the progress strip's range pickers: hovered, clicked (their menu's every entry, or
      -- without MenuUtil a step each way), then back to the default range
      for i = 1, 2 do
        local pk = ch.strip.picks[i]
        Stub.RunScript(pk, "OnEnter")
        Stub.RunScript(pk, "OnLeave")
        local menus = Stub.ui and Stub.ui.menus or 0
        Stub.RunScript(pk, "OnClick", "LeftButton")
        if Stub.ui and Stub.ui.menus > menus then
          ClickAll(Stub.ui.lastMenu)
        else
          Stub.RunScript(pk, "OnClick", "RightButton")
        end
      end
      ch.state.char.lvRange = nil
      ns.Window.Refresh()
      Stub.RunScript(ch.chips[4].frame, "OnEnter")
      Stub.RunScript(ch.chips[4].frame, "OnLeave")
      local k = math.min(ch.state.level, ch.state.nCols)     -- at max level: the last bar
      local lb = ch.state.char and ch.state.char.levels[k]
      if type(lb) == "table" then
        lb.s = lb.s or {}
        lb.s.p, lb.s.w, lb.pw = (lb.s.p or 0) + 600, (lb.s.w or 0) + 300, 120
        lb.z = lb.z or {}
        lb.z.i489 = { s = { p = 600 } }
        ns.Window.Refresh()
        Stub.RunScript(ch.cols[k].hit, "OnClick", "LeftButton")
        local dt = wf.tp.detail
        if not (dt and dt.pvpHit and dt.pvpHit:IsShown()) then error("the detail sheet has no PvP row") end
        Stub.RunScript(dt.pvpHit, "OnEnter")
        Stub.RunScript(dt.pvpHit, "OnLeave")
      end
      Stub.Advance(6)
    end
  end
  ns.Window.SetView("account")
  Stub.GrantXP(100); Stub.Advance(6)
  ns.Window.Hide()

  -- options: open, every control, every setting while shown
  ns.Options.Open()
  Stub.Advance(1)
  ApplyAllSettings(ns)
  -- the main page, then the Reputation page (a subcategory, built when first shown)
  local pages = {}
  if Stub.ui and Stub.ui.categories and Stub.ui.categories[1] then pages[1] = Stub.ui.categories[1] end
  if Stub.ui and Stub.ui.subcategories and Stub.ui.subcategories[1] then pages[2] = Stub.ui.subcategories[1] end
  for pi, cat in ipairs(pages) do
    if pi > 1 then Settings.OpenToCategory(cat.ID); Stub.Advance(1) end
    local panel = cat.frame
    for _, rec in pairs(panel.controls or {}) do
      local w = rec.widget
      if rec.kind == "check" then
        Stub.RunScript(w, "OnClick", "LeftButton"); Stub.RunScript(w, "OnClick", "LeftButton")
      elseif (rec.kind == "dropdown" or rec.kind == "faction") and w._root then
        w:GenerateMenu(); ClickAll(w._root)
      elseif rec.kind == "slider" and w.SetValue then
        w:SetValue(rec.min); w:SetValue(rec.max)
      elseif rec.kind == "button" then
        Stub.RunScript(w, "OnClick", "LeftButton")    -- the bar colours reset, "Reload UI"
      elseif rec.kind == "help" then
        Stub.RunScript(w, "OnEnter"); Stub.RunScript(w, "OnLeave")   -- auto reload help icons
      elseif rec.kind == "color" then
        -- the game's colour picker: open, move, cancel, open, move, reset
        local ui = Stub.ui
        Stub.RunScript(w, "OnClick", "LeftButton")
        ui.PickColor(0.2, 0.8, 0.4)
        ui.CancelColor()
        Stub.RunScript(w, "OnClick", "LeftButton")
        ui.PickColor(1, 0.5, 0)
        Stub.RunScript(rec.reset, "OnClick", "LeftButton")
      end
    end
    ApplyAllSettings(ns)
  end
  if #pages > 0 then Stub.ui.CloseSettings() end
  ns.Options.Toggle()
  ns.Options.Toggle()

  -- context menu (every item except "hide", done by the slash commands)
  ns.Options.ShowContextMenu(bar)
  if Stub.ui and Stub.ui.lastMenu then ClickAll(Stub.ui.lastMenu, { [ns.L.MENU_HIDE] = true }) end
  if Stub.ui and Stub.ui.CloseSettings then Stub.ui.CloseSettings() end
  ns.Window.Hide()

  -- slash commands, compartment, broker
  RunAllSlash()
  TruePlayed_OnAddonCompartmentClick("TruePlayed", "LeftButton", bar)
  TruePlayed_OnAddonCompartmentClick("TruePlayed", "RightButton", bar)
  TruePlayed_OnAddonCompartmentEnter("TruePlayed", bar)
  Stub.Advance(2)
  TruePlayed_OnAddonCompartmentLeave("TruePlayed", bar)
  TruePlayed_OnAddonCompartmentEnter("TruePlayed", nil)
  TruePlayed_OnAddonCompartmentLeave("TruePlayed", nil)
  local obj = Stub.ui and Stub.ui.ldbObjects and Stub.ui.ldbObjects.TruePlayed
  if obj then
    obj.OnTooltipShow(Stub.NewTooltip())
    obj.OnClick(bar, "LeftButton")
    obj.OnClick(bar, "RightButton")
    ns.Window.Hide()
  end

  -- experimental /played hide: our request hidden, a user /played while pending shown
  ns.Core.SetSetting("hidePlayedMsg", true)
  Stub.Advance(3)
  Stub.RunSlash("sync")
  RequestTimePlayed()
  Stub.Advance(1)
  Stub.Advance(3)
  Stub.RunSlash("sync")
  Stub.Advance(7)
  ns.Core.SetSetting("hidePlayedMsg", false)

  -- combat hide, options deferred in combat
  ns.Core.SetSetting("widget.combatHide", true)
  Stub.EnterCombat()
  ns.Options.Open()
  Stub.Advance(2)
  Stub.LeaveCombat()
  Stub.Advance(1)
  if Stub.ui and Stub.ui.CloseSettings then Stub.ui.CloseSettings() end
  ns.Core.SetSetting("widget.combatHide", false)

  -- erase another record, then the current one (confirmation popups; none in
  -- read-only mode or when there is no other record)
  local np = #Stub.popups
  ns.Options.ConfirmErase(OTHER_GUID)
  if #Stub.popups > np then Stub.AcceptPopup() end
  np = #Stub.popups
  Stub.RunSlash("reset char")
  if #Stub.popups > np then Stub.AcceptPopup() end
  Stub.Advance(15)
end

---------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------

local scenarios = {}
local function Scenario(name, fn) scenarios[#scenarios + 1] = { name = name, fn = fn } end

Scenario("full UI (Settings, MenuUtil, LDB, modern controls), enUS", function()
  Stub.InstallUI()
  _G.TruePlayedDB = { schema = 1, chars = { [OTHER_GUID] = OtherRecord() } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  Exercise(ns)
  Stub.Restart({ crash = true })
  Sync()                                  -- an answer before the XP baseline (RXPGuides)
  Stub.Advance(15)
  Stub.Restart({ reload = true, settle = 3 })
  Stub.Advance(5)
  Stub.Restart({ playElsewhere = { sec = 4000, xp = 20000 } })
  Stub.Advance(15)
  Stub.Logout()
end)

Scenario("fallback controls (no Settings, no MenuUtil, no LDB), standalone options", function()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  ns.Options.Open()
  ns.Options.Open()
  Stub.Advance(1)
  ApplyAllSettings(ns)
  Exercise(ns)
  Stub.Logout()
end)

Scenario("fallback option controls clicked one by one", function()
  Stub.InstallUI({ modern = false })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(12)
  Stub.SetFactions(Stub.REP_TREE())
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 })
  ns.Options.Open()
  for pi, cat in ipairs({ Stub.ui.categories[1], Stub.ui.subcategories[1] }) do
    if pi > 1 then Settings.OpenToCategory(cat.ID) end
    local panel = cat.frame
    for _, rec in pairs(panel and panel.controls or {}) do
      local w = rec.widget
      if rec.kind == "dropdown" or rec.kind == "faction" then
        -- the faction button cycles through the game's list (twice forwards, once back)
        Stub.RunScript(w, "OnClick", "LeftButton"); Stub.RunScript(w, "OnClick", "RightButton")
        if rec.kind == "faction" then Stub.RunScript(w, "OnClick", "LeftButton") end
      elseif rec.kind == "slider" then
        Stub.RunScript(w, "OnValueChanged", rec.max); Stub.RunScript(w, "OnValueChanged", rec.min)
      elseif rec.kind == "check" then
        Stub.RunScript(w, "OnClick", "LeftButton")
      elseif rec.kind == "help" then
        Stub.RunScript(w, "OnEnter"); Stub.RunScript(w, "OnLeave")
      end
    end
  end
  Stub.Advance(3)
  Stub.Logout()
end)

Scenario("late SavedVariables swap and WTFix-style table at PLAYER_LOGIN", function()
  Stub.InstallUI()
  Stub.LoadAddon()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  _G.TruePlayedDB = { schema = 1, chars = { [OTHER_GUID] = OtherRecord() } }
  Stub.Fire("PLAYER_LOGIN")
  Stub.Fire("PLAYER_ENTERING_WORLD", true, false)
  Stub.Advance(15)
  Stub.Logout()
  local saved = Stub.DeepCopy(Stub.saved)
  Stub.Reset({ keepWorld = true })
  Stub.InstallUI()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  ns.Window.Show()
  _G.TruePlayedDB = saved
  Stub.Advance(3)
  _G.TruePlayedDB = nil
  Stub.Advance(2)
  ns.Window.Hide()
  Stub.Logout()
end)

Scenario("SavedVariables applied between the last tick and PLAYER_LOGOUT", function()
  Stub.InstallUI()
  Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  Stub.Logout()                           -- the private table is published here
  local saved = Stub.DeepCopy(Stub.saved)
  Stub.Reset({ keepWorld = true })
  Stub.InstallUI()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  ns.Window.Show()
  _G.TruePlayedDB = saved                 -- adopted by Core at PLAYER_LOGOUT
  Stub.Logout()
end)

-- The read-only table keeps a compact box style (removed after 1.0.x): read, never used.
Scenario("read-only (newer schema), frFR", function()
  Stub.InstallUI()
  Stub.locale = "frFR"
  _G.TruePlayedDB = { schema = 99, settings = { widget = { style = "box" } },
                      chars = { [OTHER_GUID] = OtherRecord() } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  Exercise(ns)
  Stub.Logout()
end)

Scenario("max level, frFR, bar hidden at max, then shown", function()
  Stub.InstallUI()
  Stub.locale = "frFR"
  Stub.player.level = 60
  Stub.player.max = 0
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  ns.Core.SetSetting("widget.hideAtMax", true)
  Stub.Advance(2)
  ns.Core.SetSetting("widget.hideAtMax", false)
  Exercise(ns)
  Stub.Logout()
end)

-- Round 3: the server level cap of the Forever beta (kills without XP, read at the end of
-- each fight: target and party APIs), the frozen rate (no XP for 20 min), custom bar
-- colours, frFR; then the cap raised and the stall ended by XP.
Scenario("server level cap, frozen rate and bar colours, frFR", function()
  Stub.InstallUI()
  Stub.locale = "frFR"
  local p = Stub.player
  p.level, p.xp, p.max, p.rest = 20, 58, Stub.xpTable[20], 4000
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  ns.Core.SetSetting("widget.xpColor", { 0.9, 0.3, 0.1 })
  ns.Core.SetSetting("widget.restedColor", { 0.1, 0.7, 0.9 })
  Stub.Kill(145); Stub.Advance(5)
  -- kills that never count (critter, totem, secret target), then the cap in a party
  Stub.KillNoXP({ creatureType = "Bestiole" }); Stub.Advance(5)
  Stub.KillNoXP({ creatureType = "Totem" }); Stub.Advance(5)
  Stub.secret.target = true
  Stub.KillNoXP(); Stub.Advance(5)
  Stub.secret.target = false
  Stub.party[1] = 22
  for _ = 1, 3 do Stub.KillNoXP({ level = 20 }); Stub.Advance(30) end
  if not ns.Tracker.IsMax() then error("the server cap was not detected") end
  local bar = ns.Bar.frame
  if bar then Stub.RunScript(bar, "OnEnter"); Stub.Advance(2); Stub.RunScript(bar, "OnLeave") end
  ns.Tooltip.Fill(Stub.NewTooltip(), true)
  ns.Tooltip.Fill(Stub.NewTooltip(), false)
  Stub.RunSlash("played")
  ns.Core.SetSetting("widget.hideAtMax", true); Stub.Advance(2)
  ns.Core.SetSetting("widget.hideAtMax", false)
  ns = Stub.Restart({ reload = true, settle = 3 })
  Stub.Advance(5)
  if not ns.Tracker.IsMax() then error("the server cap was not kept across /reload") end
  ns.Tooltip.Fill(Stub.NewTooltip(), false)
  -- the cap is raised: XP again, then 25 min without XP (frozen rate)
  Stub.Kill(145); Stub.Advance(30); Stub.Kill(145); Stub.Advance(1500)
  if ns.Tracker.IsMax() or not ns.Tracker.GetStall() then error("cap not over, or no stall") end
  ns.Tooltip.Fill(Stub.NewTooltip(), true)
  Stub.RunSlash("played")
  ns.Window.Show(); ns.Window.Toggle("levels"); Stub.Advance(6); ns.Window.Hide()
  Stub.Kill(145); Stub.Advance(5)
  ns.Options.Open(); Stub.Advance(1)
  Stub.Logout()
end)

-- Language option (design/NEXT-LOT.md B): French chosen on an enUS client (applied at
-- ADDON_LOADED), then English chosen on a frFR client through a late table (WTFix) and
-- a reload, with everything exercised.
Scenario("language option: frFR on an enUS client, enUS on a frFR client", function()
  Stub.InstallUI()
  _G.TruePlayedDB = { schema = 1, settings = { language = "frFR" },
                      chars = { [OTHER_GUID] = OtherRecord() } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(15)
  if ns.L.ON ~= "activ\195\169" or ns.LOCALES ~= nil then error("frFR not applied, or tables kept") end
  Exercise(ns)
  Stub.Logout()
  Stub.Reset({ keepWorld = true })
  Stub.InstallUI()
  Stub.locale = "frFR"
  ns = Stub.LoadAddon()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  _G.TruePlayedDB = { schema = 1, settings = { language = "enUS" } }
  Stub.Fire("PLAYER_LOGIN")
  Stub.Fire("PLAYER_ENTERING_WORLD", true, false)
  Stub.Advance(15)
  if ns.L.ON ~= "on" then error("enUS not applied on the frFR client") end
  Exercise(ns)
  ns = Stub.Restart({ reload = true, settle = 3 })
  Stub.Advance(5)
  -- Exercise ends on "auto" (its settings and slash lists): French again on this client
  if ns.L.ON ~= "activ\195\169" then error("auto not applied after the reload") end
  Stub.Logout()
end)

-- Themes (SPEC-themes 8.3): the shipped default (no Stub.theme hook), then every setting
-- value, each with the tooltip (short and Shift), the graph and the window; custom bar
-- colours and a recolour while shown; the options and /tpl theme.
local function ShowEverything(ns)
  local bar = ns.Bar.frame
  if bar then
    Stub.RunScript(bar, "OnEnter")
    Stub.Advance(1)
    Stub.SetShift(true); Stub.Advance(1); Stub.SetShift(false); Stub.Advance(1)
    Stub.RunScript(bar, "OnLeave")
    ns.Graph.ShowFor(bar)
    Stub.Advance(2)
    ns.Graph.Hide()
  end
  ns.Tooltip.Fill(Stub.NewTooltip(), true)
  ns.Tooltip.Fill(Stub.NewTooltip(), false)
  ns.Window.Show()
  for _, tab in ipairs({ "levels", "zones", "sessions" }) do
    ns.Window.Toggle(tab)
    Stub.Advance(1)
  end
  ns.Window.Hide()
end

Scenario("every theme (setting values, tooltip, graph, window, options, /tpl theme)", function()
  Stub.InstallUI()
  Stub.theme = nil
  Stub.player.rest = 3000
  _G.TruePlayedDB = { schema = 1, chars = { [OTHER_GUID] = OtherRecord() } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(10)
  ShowEverything(ns)
  if ns.Themes.ActiveKey() ~= "futuriste" then error("the shipped default is not futuriste") end
  for _, key in ipairs(ns.C.THEME_CHOICES) do
    ns.Core.SetSetting("theme", key)
    Stub.Advance(1)
    local active = ns.Themes.ActiveKey()
    if ns.settings.theme ~= key or not ns.Themes.IsRegistered(active) or (key ~= "class" and active ~= key) then
      error("theme " .. key .. " not applied (active " .. tostring(active) .. ")")
    end
    ShowEverything(ns)
    Stub.GrantXP(300)
    Stub.Advance(2)
  end
  for _, key in ipairs({ "futuriste", "pixel", "warlock", "druid", "actuel", "class" }) do
    ns.Core.SetSetting("theme", key)
    Stub.Advance(2)
    ShowEverything(ns)
    ns.Core.SetSetting("widget.xpColor", { 1, 0.5, 0 })
    ns.Core.SetSetting("widget.restedColor", { 0.1, 0.8, 0.3 })
    Stub.Advance(2)
    ns.Core.SetSetting("widget.xpColor", false)
    ns.Core.SetSetting("widget.restedColor", false)
    Stub.Advance(1)
  end
  ns.Options.Open()
  Stub.Advance(1)
  for _, key in ipairs({ "mage", "heroic", "class" }) do
    ns.Core.SetSetting("theme", key)
    Stub.Advance(1)
  end
  if Stub.ui and Stub.ui.CloseSettings then Stub.ui.CloseSettings() end
  for _, cmd in ipairs({ "theme", "theme pixel", "theme class", "theme bogus", "theme actuel", "theme" }) do
    Stub.RunSlash(cmd)
    Stub.Advance(1)
    if cmd == "theme pixel" and ns.settings.theme ~= "pixel" then error("/tpl theme pixel had no effect") end
  end
  ns = Stub.Restart({ reload = true, settle = 3 })
  Stub.Advance(3)
  ShowEverything(ns)
  Stub.Logout()
end)

-- Activity states (lot 8): a death and a ghost run, a craft in the trade skill window,
-- the craft window (Beast Training, then Enchanting), gathering with its grace, a fishing
-- and a bandage channel, a non-profession cast, the Shift tooltip, the Levels tab with
-- its dead and estimate columns, a level-up (level-start estimate) and a logout.
Scenario("dead and ghost run, professions, Shift tooltip, Levels tab, level-up", function()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  for _ = 1, 4 do Stub.Advance(30); Stub.Kill(150) end
  Stub.Die(); Stub.Advance(20); Stub.ReleaseSpirit(); Stub.Advance(40); Stub.Resurrect(true); Stub.Advance(5)
  Stub.OpenTradeSkill(); Stub.Advance(3); Stub.Cast(2657, 2); Stub.CloseTradeSkill(); Stub.Advance(2)
  Stub.OpenCraft("Beast Training"); Stub.Advance(2); Stub.CloseCraft()
  Stub.OpenCraft("Enchanting"); Stub.Advance(2); Stub.CloseCraft()
  Stub.Cast(2366, 3); Stub.Advance(6)
  Stub.Spell("CHANNEL_START", 7620); Stub.Advance(10); Stub.Spell("CHANNEL_STOP", 7620); Stub.Advance(6)
  Stub.Spell("CHANNEL_START", 746); Stub.Advance(8); Stub.Spell("CHANNEL_STOP", 746)
  Stub.Spell("START", 133); Stub.Spell("INTERRUPTED", 133); Stub.Advance(2)
  local w = rawget(_G, "TruePlayedWidget")
  Stub.RunScript(w, "OnEnter"); Stub.SetShift(true); Stub.Advance(2); Stub.SetShift(false)
  Stub.RunScript(w, "OnLeave")
  ns.Window.Show("levels"); Stub.Advance(6)
  ns.Window.Toggle("zones"); ns.Window.Toggle("sessions"); ns.Window.Hide()
  Stub.GrantXP(Stub.player.max); Stub.Advance(3)
  ns.Window.Show("levels"); Stub.Advance(2); ns.Window.Hide()
  Stub.Logout()
end)

Scenario("widget hidden from the start (no consumer, bar never created)", function()
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false } } }
  Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(60)
  Stub.RunSlash("played")
  Stub.RunSlash("show")
  Stub.Advance(3)
  Stub.Logout()
end)

-- Minimap button and mini display (design/NEXT-LOT.md backlog 3 and 4), the bar hidden:
-- hover, every left-click action, the menu (Hide from each), drag, every mini setting and
-- layout, every theme, combat hide, a SavedVariables swap, the slash commands.
Scenario("minimap button and mini display, bar hidden, every theme", function()
  Stub.InstallUI({ minimap = true, minimapShape = "SQUARE" })
  _G.TruePlayedDB = { schema = 1, settings = { widget = { shown = false },
    mini = { shown = true, infos = { "eta_kills", "fps_latency", "session" }, xp = "both" } } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  for _ = 1, 4 do Stub.Advance(30); Stub.Kill(150) end
  local b, f = ns.MinimapButton.button, ns.MiniDisplay.frame
  local Core = ns.Core
  for _, action in ipairs({ "stats", "options", "bar", "mini", "mini", "bar", "stats" }) do
    Core.SetSetting("minimap.click", action)
    Stub.RunScript(b, "OnEnter")
    Stub.SetShift(true); Stub.Advance(1); Stub.SetShift(false)
    Stub.RunScript(b, "OnMouseDown", "LeftButton")
    Stub.RunScript(b, "OnClick", "LeftButton")
    Stub.RunScript(b, "OnLeave")
    Stub.Advance(1)
  end
  if Stub.ui.CloseSettings then Stub.ui.CloseSettings() end
  Stub.ui.Cursor(1700, 1000)
  Stub.RunScript(b, "OnMouseDown", "LeftButton")
  Stub.RunScript(b, "OnDragStart", "LeftButton")
  Stub.RunScript(b, "OnDragStop")
  Stub.RunScript(b, "OnClick", "LeftButton")
  Stub.RunScript(f, "OnEnter"); Stub.Advance(2); Stub.RunScript(f, "OnLeave")
  Stub.RunScript(f, "OnMouseDown", "LeftButton")
  Stub.RunScript(f, "OnDragStart", "LeftButton")
  Stub.RunScript(f, "OnDragStop")
  Stub.RunScript(f, "OnMouseUp", "LeftButton")
  Stub.RunScript(f, "OnMouseDown", "LeftButton")
  Stub.RunScript(f, "OnMouseUp", "LeftButton")
  ns.Window.Hide()
  for _, kv in ipairs({ { "mini.layout", "vertical" }, { "mini.xp", "pct" }, { "mini.xp", "none" },
      { "mini.xp", "line" }, { "mini.scale", 1.5 }, { "mini.bgAlpha", 0 }, { "mini.bgAlpha", 0.8 },
      { "mini.fade", true }, { "mini.locked", true }, { "mini.infos.1", "kills" }, { "mini.infos.2", "none" },
      { "mini.infos.3", "fps" }, { "widget.textColor", { 1, 0.5, 0 } }, { "widget.outline", "thick" },
      { "widget.shadow", false }, { "widget.qualityColors", false }, { "widget.xpColor", { 0, 1, 0 } },
      { "minimap.angle", 10 }, { "minimap.locked", true }, { "mini.layout", "horizontal" } }) do
    Core.SetSetting(kv[1], kv[2])
    Stub.Advance(1)
  end
  for _, key in ipairs({ "futuriste", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue", "priest",
      "shaman", "mage", "warlock", "druid", "class", "actuel" }) do
    Core.SetSetting("theme", key)
    Stub.Advance(1)
  end
  Core.SetSetting("mini.combatHide", true)
  Stub.EnterCombat(); Stub.Advance(2); Stub.LeaveCombat(); Stub.Advance(1)
  for _, owner in ipairs({ b, f }) do
    ns.Options.ShowContextMenu(owner)
    if Stub.ui.lastMenu then ClickAll(Stub.ui.lastMenu) end
    if Stub.ui.CloseSettings then Stub.ui.CloseSettings() end
    ns.Window.Hide()
    Stub.Advance(1)
  end
  for _, cmd in ipairs({ "minimap", "minimap", "mini", "mini", "help", "show", "hide" }) do
    Stub.RunSlash(cmd)
    Stub.Advance(1)
  end
  ns.Options.Open()
  Stub.Advance(1)
  if Stub.ui.CloseSettings then Stub.ui.CloseSettings() end
  _G.TruePlayedDB = { schema = 1, settings = { mini = { shown = true, layout = "vertical" },
    minimap = { angle = 90 } } }
  Stub.Advance(3)
  Stub.Logout()
end)

-- Automatic reload (AutoReload.lua): on a client that allows ReloadUI() from addon code,
-- the timer prompt outside, the capital left by the timer to the rest mode, the rest
-- mode's countdown there, cancelled by moving, then the reload and a block; on WoW Forever (the stub's client), the prompt, combat, Later, a
-- click on "Reload now", the shown prompt watched; a busy player (the game's
-- menu and options too) at the due moment.
Scenario("automatic reload: direct countdown, prompt and its click, block, busy player", function()
  Stub.InstallUI()
  Stub.build.interface = 11508
  _G.TruePlayedDB = { schema = 1, settings = { autoReload = { rest = true, timer = true, minutes = 10 } } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(620)
  local AR = ns.AutoReload
  local f = AR.GetPrompt()
  if f then
    Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
    Stub.RunScript(f.tp.later, "OnClick", "LeftButton")
  end
  Stub.SetMap(1454); Stub.Advance(12)                 -- the timer leaves the capital to the rest mode
  Stub.Advance(ns.Tracker.loadStartG + ns.C.AUTORELOAD_REST_MIN + 2 - Stub.Now())   -- its countdown
  Stub.player.moving = true; Stub.Advance(2); Stub.player.moving = false
  Stub.Advance(650)
  Stub.Fire("ADDON_ACTION_BLOCKED", "TruePlayed", "UNKNOWN()")
  Stub.Advance(10)
  ns.Options.Open()
  Stub.Advance(1)
  Stub.ui.CloseSettings()
  Stub.Logout()

  Stub.Reset()
  Stub.InstallUI()
  _G.TruePlayedDB = { schema = 1, settings = { autoReload = { rest = true } } }
  ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN + 20)
  Stub.busy.casting, Stub.busy.keyFocus, Stub.busy.popup = "Hearthstone", {}, true
  Stub.busy.panels.center = {}
  MovieFrame:Show(); ReadyCheckFrame:Show()
  SettingsPanel:Show(); GameMenuFrame:Show(); KeyBindingFrame:Show(); InterfaceOptionsFrame:Show()
  Stub.SetMap(1454); Stub.Advance(30)
  Stub.busy.casting, Stub.busy.keyFocus, Stub.busy.popup, Stub.busy.panels.center = nil, nil, nil, nil
  MovieFrame:Hide(); ReadyCheckFrame:Hide()
  SettingsPanel:Hide(); GameMenuFrame:Hide(); KeyBindingFrame:Hide(); InterfaceOptionsFrame:Hide()
  Stub.Advance(10)
  AR = ns.AutoReload
  f = AR.GetPrompt()
  if f then
    Stub.EnterCombat(); Stub.Advance(3); Stub.LeaveCombat(); Stub.Advance(6)
    Stub.RunScript(f.tp.later, "OnClick", "LeftButton")
    Stub.Advance(601)
    Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
    -- the shown prompt watched: an XP gain greys "Reload now", professions in a dungeon
    -- (the place read from the game) hide it
    Stub.GrantXP(50); Stub.Advance(1)
    Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
    Stub.Advance(4)
    Stub.Spell("START", 8613); Stub.SetInstance(true, "party", 389, nil); Stub.Advance(1)
    Stub.Spell("STOP", 8613); Stub.Advance(8)
  end
  for _, name in ipairs({ "UnitCastingInfo", "GetUIPanel", "MovieFrame", "IsPlayerMoving" }) do rawset(_G, name, nil) end
  AR.Blocker(true)
  Stub.Logout()
end)

-- The controls of the options' Reputation page (a subcategory, built when first shown).
local function RepPage()
  local sub = Stub.ui.subcategories and Stub.ui.subcategories[1]
  if not sub then return nil end
  Settings.OpenToCategory(sub.ID)
  return rawget(sub.frame, "controls")
end

-- The watched reputation: a faction watched in every theme (the strip, the tooltip line,
-- Shift; a female character), standings gained up to Exalted, the help icon, the option off
-- and on, a secret read and no faction.
Scenario("watched reputation: strip and tooltip line, every theme, option, secret", function()
  Stub.InstallUI()
  Stub.rep.sex = 3
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 })
  Stub.Advance(2)
  local w = rawget(_G, "TruePlayedWidget")
  for _, key in ipairs(ns.C.THEME_CHOICES) do
    ns.Core.SetSetting("theme", key)
    Stub.Advance(1)
    Stub.RunScript(w, "OnEnter"); Stub.SetShift(true); Stub.Advance(1); Stub.SetShift(false)
    Stub.RunScript(w, "OnLeave")
  end
  Stub.GainRep(6000); Stub.Advance(1)
  Stub.GainRep(40000); Stub.Advance(1)
  Stub.RunScript(w, "OnEnter"); Stub.Advance(1); Stub.RunScript(w, "OnLeave")
  ns.Options.Open()
  local controls = RepPage()
  local help = controls and controls["help.rep"]
  if help then
    help.widget:GetScript("OnEnter")(help.widget)
    help.widget:GetScript("OnLeave")(help.widget)
  end
  ns.Core.SetSetting("widget.rep", false); Stub.Advance(1)
  ns.Core.SetSetting("widget.rep", true); Stub.Advance(1)
  Stub.rep.secret = true; Stub.Fire("UPDATE_FACTION"); Stub.Advance(1)
  Stub.rep.secret = false
  Stub.WatchFaction(nil); Stub.Advance(1)
  Stub.Logout()
end)

-- Classic Era's reputation API (GetWatchedFactionInfo), without the game's colours, standing
-- names and checkbox label (the addon's own).
Scenario("watched reputation: Classic Era API, no FACTION_BAR_COLORS nor standing names", function()
  Stub.InstallUI()
  Stub.SetRepAPI("era")
  Stub.SetRepGlobals(false)
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.WatchFaction({ name = "Stormwind", factionID = 72, reaction = 4, min = 0, max = 3000, value = 1500 })
  Stub.Advance(1)
  local w = rawget(_G, "TruePlayedWidget")
  Stub.RunScript(w, "OnEnter"); Stub.Advance(1); Stub.RunScript(w, "OnLeave")
  ns.Options.Open()
  local controls = RepPage()
  for _, key in ipairs({ "help.rep", "help.repMain", "help.repFaction" }) do
    local help = controls and controls[key]
    if help then
      help.widget:GetScript("OnEnter")(help.widget)
      help.widget:GetScript("OnLeave")(help.widget)
    end
  end
  Stub.Logout()
end)

-- The reputation's second lot: the faction picker's walk of the game's list (both APIs),
-- a chosen faction (then unreadable: the fallback), the rate (gains, a stall, a reset), the
-- detailed tooltip on the hover region, the main bar mode in every theme (a new standing,
-- Exalted, max level, hideAtMax, no faction), the tokens, a reload, read-only mode.
for _, api in ipairs({ "forever", "era" }) do
  Scenario("reputation (" .. api .. "): picker walk, chosen faction, rate, detailed tooltip, main mode", function()
    Stub.InstallUI()
    Stub.SetRepAPI(api)
    Stub.SetFactions(Stub.REP_TREE())
    local ns = Stub.LoadAddon()
    Stub.LoginSequence({ settle = 3 })
    Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 4, min = 0, max = 3000, value = 2500 })
    Stub.Advance(2)
    local Rep, Core = ns.Rep, ns.Core
    Rep.ListFactions()
    Rep.SetChosen(529)
    Stub.GainRepID(529, 40); Stub.Advance(1)
    Stub.rep.missing[529] = true; Stub.Fire("UPDATE_FACTION"); Stub.Advance(1)
    Stub.rep.missing[529] = nil
    Rep.SetChosen(nil)
    for _ = 1, 12 do Stub.Advance(60); Stub.GainRep(50) end
    Core.SetSetting("widget.slots.1", "reph")
    Core.SetSetting("widget.slots.3", "rep_eta")
    local f = ns.Bar.frame
    local hit = f.tp.repHit
    for _, key in ipairs(ns.C.THEME_CHOICES) do
      Core.SetSetting("theme", key)
      for _, mode in ipairs(ns.C.MAIN_MODES) do
        Core.SetSetting("widget.main", mode)
        Stub.Advance(1)
        hit = f.tp.repHit or hit
        if hit then
          Stub.RunScript(hit, "OnEnter"); Stub.Advance(1)
          Stub.RunScript(hit, "OnMouseDown", "LeftButton"); Stub.RunScript(hit, "OnDragStart")
          Stub.RunScript(hit, "OnDragStop"); Stub.RunScript(hit, "OnMouseUp", "LeftButton")
          Stub.RunScript(hit, "OnLeave")
        end
      end
    end
    ns.Window.Hide()
    Stub.Advance(ns.C.XP_STALL + 60)
    if hit then Stub.RunScript(hit, "OnEnter"); Stub.Advance(1); Stub.RunScript(hit, "OnLeave") end
    Stub.GainRep(800); Stub.Advance(1)                -- Neutral -> Friendly: a new colour
    Stub.GainRep(45000); Stub.Advance(1)              -- Exalted
    if hit then Stub.RunScript(hit, "OnEnter"); Stub.Advance(1); Stub.RunScript(hit, "OnLeave") end
    Core.SetSetting("widget.hideAtMax", true)
    Stub.GrantXP(Stub.player.max * 80); Stub.Advance(2)
    Stub.WatchFaction(nil); Stub.Advance(1)
    Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 })
    Core.ResetRate()
    Core.SetSetting("widget.main", "xp")
    ns = Stub.Restart({ settle = 3 })
    Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4300 })
    Stub.Advance(2)
    ns.Core.ResetChar()
    Stub.Advance(2)
    Stub.Logout()
  end)
end

Scenario("reputation: read-only mode (a newer schema), the Reputation page refusing", function()
  Stub.InstallUI()
  Stub.SetFactions(Stub.REP_TREE())
  rawset(_G, "TruePlayedDB", { schema = 99, settings = { firstRunDone = true }, chars = {} })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 })
  Stub.Advance(60); Stub.GainRep(100); Stub.Advance(1)
  ns.Options.Open()
  local controls = RepPage()
  for _, rec in pairs(controls or {}) do
    local w = rec.widget
    if rec.kind == "faction" and w._root then
      w:GenerateMenu(); ClickAll(w._root)
    elseif rec.kind == "button" then
      Stub.RunScript(w, "OnClick", "LeftButton")
    end
  end
  Stub.Advance(1)
  Stub.Logout()
end)

-- PvP on WoW Forever (Pvp.lua): the strip (honor, rank) under the reputation's, the main
-- bar's PvP mode in every theme and the battleground override, gains in and out of a
-- battleground (the pause), the honor cap and its alert after a fight, the weekly cap, the
-- max rank, a match's result (and its fallback), the detailed tooltip (themed and
-- native), the tokens, the options' PvP page (every control, help and the reset), a
-- reload, ResetChar, no season, secret reads.
local function PvpPage()
  local sub = Stub.ui.subcategories and Stub.ui.subcategories[2]
  if not sub then return nil end
  Settings.OpenToCategory(sub.ID)
  return rawget(sub.frame, "controls")
end

local function HoverPvp(ns)
  local hit = ns.Bar.frame and ns.Bar.frame.tp.pvpHit
  if hit and hit:IsShown() then
    Stub.RunScript(hit, "OnEnter"); Stub.Advance(1)
    Stub.RunScript(hit, "OnMouseDown", "LeftButton"); Stub.RunScript(hit, "OnDragStart")
    Stub.RunScript(hit, "OnDragStop"); Stub.RunScript(hit, "OnMouseUp", "LeftButton")
    Stub.RunScript(hit, "OnLeave")
  end
end

Scenario("PvP (forever): strips, main mode in every theme, override, gains, pause, caps, alert, tooltip", function()
  Stub.InstallUI()
  Stub.SetPvpAPI("forever")
  Stub.SetWeek(2, 3, 1, { quiet = true })
  Stub.pvp.total = 2000
  Stub.pvp.q = 24000
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 })
  local Core = ns.Core
  Core.SetSetting("widget.pvp", "honor")
  Core.SetSetting("widget.pvpAuto", true)
  for i, id in ipairs({ "honor", "honor_h", "honor_eta" }) do Core.SetSetting("widget.slots." .. i, id) end
  Stub.EnterBG({ loading = true })
  for _ = 1, 6 do Stub.Advance(60); Stub.GainHonor(100); Stub.GainRankPoints(30); Stub.HK(1) end
  for _, key in ipairs(ns.C.THEME_CHOICES) do
    Core.SetSetting("theme", key)
    for _, mode in ipairs(ns.C.MAIN_MODES) do
      Core.SetSetting("widget.main", mode)
      for _, strip in ipairs(ns.C.PVP_STRIPS) do
        Core.SetSetting("widget.pvp", strip)
        Stub.Advance(1)
        HoverPvp(ns)
      end
    end
  end
  ns.Window.Hide()
  for i, id in ipairs({ "rank", "rank_h", "rank_eta" }) do Core.SetSetting("widget.slots." .. i, id) end
  Core.SetSetting("widget.maxSlots.1", "hk_today")
  Core.SetSetting("widget.pvp", "rank")
  Stub.MatchComplete(0, 900)
  Stub.pvp.team = 1                                   -- the side the battleground gives
  Stub.ChainBG()                                      -- the next battleground, the same map
  Stub.Advance(2)
  Stub.MatchComplete(1, 600)
  Stub.pvp.team = nil
  Stub.LeaveBG({ loading = true })
  Stub.EnterBG({ arena = true, loading = true })      -- an arena: not a battleground
  Stub.Advance(2)
  Stub.LeaveBG({ loading = true })
  Stub.Advance(ns.C.PVP_IDLE + 30)                    -- paused
  HoverPvp(ns)
  Stub.EnterBG()
  Stub.pvp.winner = 1
  Stub.Fire("UPDATE_BATTLEFIELD_STATUS", 1)
  Stub.EnterCombat()
  Stub.GainHonor(5000)                                -- the cap, in a fight: the alert waits
  Stub.Advance(5)
  Stub.LeaveCombat()
  local alert = ns.Pvp.GetAlert()
  if alert then Stub.RunScript(alert.tp.ok, "OnClick") end
  Stub.GainRankPoints(5000)                           -- the week's cap
  HoverPvp(ns)
  Stub.LeaveBG()
  Stub.WeeklyReset(); Stub.DailyReset()               -- the countdowns jump: re-read
  Stub.Advance(35)
  Stub.SetWeek(10, 14, 13)
  Stub.GainRankPoints(30000)                          -- the max rank
  Core.SetSetting("widget.main", "pvp")
  HoverPvp(ns)
  Core.SetSetting("theme", "actuel")
  HoverPvp(ns)                                        -- the native tooltip
  Stub.SpendHonor(3000)
  Core.SetSetting("widget.hideAtMax", true)
  Stub.GrantXP(Stub.player.max * 80); Stub.Advance(2)
  ns.Options.Open()
  local controls = PvpPage()
  for _, rec in pairs(controls or {}) do
    local w = rec.widget
    if rec.kind == "help" then
      w:GetScript("OnEnter")(w); w:GetScript("OnLeave")(w)
    elseif rec.kind == "dropdown" and w._root then
      w:GenerateMenu(); ClickAll(w._root)
    elseif rec.kind == "check" then
      Stub.RunScript(w, "OnClick", "LeftButton"); Stub.RunScript(w, "OnClick", "LeftButton")
    elseif rec.kind == "button" then
      Stub.RunScript(w, "OnClick", "LeftButton")
    end
  end
  Stub.ui.CloseSettings()
  Stub.RunSlash("reset rate")
  ns = Stub.Restart({ reload = true, settle = 3 })
  Stub.GainHonor(10); Stub.Advance(2)
  ns.Core.ResetChar()
  Stub.Advance(2)
  Stub.SetWeek(-1, 0, 0, { quiet = true })            -- no season
  Stub.pvp.total = 0
  Stub.Fire("UPDATE_FACTION"); Stub.Advance(1)
  HoverPvp(ns)
  Stub.pvp.secret = { info = true, hk = true }
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792); Stub.Fire("UPDATE_FACTION")
  Stub.Fire("PLAYER_PVP_KILLS_CHANGED", "player"); Stub.Advance(1)
  Stub.pvp.secret = {}
  Stub.Logout()
end)

-- Classic Era: the PvP module dormant, its page's note, the PvP choices absent.
Scenario("PvP (era): dormant, the page's note, a PvP main mode left from elsewhere", function()
  Stub.InstallUI()
  Stub.SetPvpAPI("era")
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { firstRunDone = true,
    widget = { main = "pvp", pvp = "honor", pvpAuto = true, slots = { "honor", "rank_eta", "hk_today" } } } })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  Stub.EnterBG(); Stub.Advance(2)
  Stub.MatchComplete(0, 60); Stub.LeaveBG(); Stub.Advance(2)
  Stub.Fire("CURRENCY_DISPLAY_UPDATE", 1792, 5, 5); Stub.Advance(1)
  ns.Options.Open()
  PvpPage()
  Stub.ui.CloseSettings()
  local tt = Stub.NewTooltip()
  ns.Tooltip.FillPvp(tt)
  Stub.Logout()
end)

Scenario("PvP: read-only mode (a newer schema), the PvP page refusing", function()
  Stub.InstallUI()
  Stub.SetPvpAPI("forever")
  rawset(_G, "TruePlayedDB", { schema = 99, settings = { firstRunDone = true }, chars = {} })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  ns.Core.SetSetting("widget.pvp", "rank")
  Stub.EnterBG()
  Stub.Advance(60); Stub.GainHonor(100); Stub.GainRankPoints(20); Stub.Advance(1)
  Stub.MatchComplete(1, 60); Stub.LeaveBG()
  HoverPvp(ns)
  ns.Options.Open()
  local controls = PvpPage()
  for _, rec in pairs(controls or {}) do
    if rec.kind == "button" then Stub.RunScript(rec.widget, "OnClick", "LeftButton") end
  end
  Stub.Advance(1)
  Stub.Logout()
end)

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

local function Traceback(e) return debug.traceback(tostring(e), 2) end

for _, sc in ipairs(scenarios) do
  Stub.Reset()
  local snap = Snapshot()
  local ok, err = xpcall(sc.fn, Traceback)
  if not ok then
    Problem(string.format("scenario '%s' raised: %s", sc.name, verbose and tostring(err)
      or (tostring(err):match("^[^\n]*"))))
  end
  if #Stub.errors > 0 then
    for i = 1, #Stub.errors do
      Problem(string.format("scenario '%s': error reported through geterrorhandler: %s", sc.name,
        verbose and Stub.errors[i] or (Stub.errors[i]:match("^[^\n]*"))))
    end
  end
  if Stub.onUpdateCount ~= 0 then
    Problem(string.format("scenario '%s': %d OnUpdate script(s) set", sc.name, Stub.onUpdateCount))
  end
  CompareSnapshot(sc.name, snap)
  if verbose then print("ran: " .. sc.name) end
end

local names = {}
for k in pairs(reads) do names[#names + 1] = tostring(k) end
table.sort(names)
local nRead = #names
for i = 1, nRead do
  local k = names[i]
  if READ_OK_IN[k] then
    if readOutside[k] then
      Problem(string.format("%s: reads the global '%s' (allowed in %s only)", readOutside[k], k, READ_OK_IN[k]))
    end
  elseif not READ_OK[k] then
    Problem(string.format("%s: reads the global '%s' (not in the SPEC 2.3 allowlist)", readWhere[k] or "?", k))
  end
end
if verbose then print("globals read: " .. table.concat(names, " ")) end

if #problems > 0 then
  for i = 1, #problems do
    local msg = problems[i]
    local n = seen[msg]
    print("FAIL  " .. msg .. (n > 1 and string.format(" (x%d)", n) or ""))
  end
  print(string.format("check_globals: %d problem(s)", #problems))
  os.exit(1)
end
print(string.format("check_globals: OK - %d scenario(s), %d file(s), %d global name(s) read",
  #scenarios, #FILES, nRead))
