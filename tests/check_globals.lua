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
-- theme). The other
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
do
  local f = io.open(ROOT .. "tests/stub_ui.lua", "r")
  if f then
    f:close()
    Stub.AddInstaller(dofile(ROOT .. "tests/stub_ui.lua"))
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
  "ReloadUI",                      -- "Reload UI" button under the language option (Options, on click only)
  -- max level, layered as EllesmereUI's XP bar (Core Util.IsMaxLevel; guarded, may be nil)
  "IsPlayerAtEffectiveMaxLevel", "IsLevelAtEffectiveMaxLevel", "GetMaxLevelForPlayerExpansion",
  -- server level cap detection: the target of a kill without XP (Tracker; guarded, read
  -- at combat start / end and on target changes only)
  "UnitExists", "UnitIsDead", "UnitCanAttack", "UnitIsPlayer", "UnitPlayerControlled",
  "UnitIsTapDenied", "UnitClassification", "UnitCreatureType",
  -- Lua standard library
  "assert", "error", "getmetatable", "ipairs", "next", "pairs", "pcall", "rawequal",
  "rawget", "rawset", "select", "setmetatable", "tonumber", "tostring", "type", "unpack",
  "xpcall", "math", "string", "table", "coroutine", "_VERSION",
})
for k in pairs(WRITE_OK) do READ_OK[k] = true end

-- Globals one file only may read: Themes.lua compiles the theme source texts in an empty
-- environment (loadstring + setfenv on Lua 5.1, the game; load with an environment on
-- 5.2+, design/NEXT-LOT.md M3). A read from any other file is reported.
local READ_OK_IN = {
  loadstring = "Themes.lua", setfenv = "Themes.lua", load = "Themes.lua",
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
  Stub.GrantXP(100); Stub.Advance(6)
  ns.Window.Hide()

  -- options: open, every control, every setting while shown
  ns.Options.Open()
  Stub.Advance(1)
  ApplyAllSettings(ns)
  if Stub.ui and Stub.ui.categories and Stub.ui.categories[1] then
    local panel = Stub.ui.categories[1].frame
    for _, rec in pairs(panel.controls or {}) do
      local w = rec.widget
      if rec.kind == "check" then
        Stub.RunScript(w, "OnClick", "LeftButton"); Stub.RunScript(w, "OnClick", "LeftButton")
      elseif rec.kind == "dropdown" and w._root then
        w:GenerateMenu(); ClickAll(w._root)
      elseif rec.kind == "slider" and w.SetValue then
        w:SetValue(rec.min); w:SetValue(rec.max)
      elseif rec.kind == "button" then
        Stub.RunScript(w, "OnClick", "LeftButton")    -- the bar colours reset, "Reload UI"
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
    Stub.ui.CloseSettings()
  end
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
  ns.Options.Open()
  local panel = Stub.ui.categories[1] and Stub.ui.categories[1].frame
  for _, rec in pairs(panel and panel.controls or {}) do
    local w = rec.widget
    if rec.kind == "dropdown" then
      Stub.RunScript(w, "OnClick", "LeftButton"); Stub.RunScript(w, "OnClick", "RightButton")
    elseif rec.kind == "slider" then
      Stub.RunScript(w, "OnValueChanged", rec.max); Stub.RunScript(w, "OnValueChanged", rec.min)
    elseif rec.kind == "check" then
      Stub.RunScript(w, "OnClick", "LeftButton")
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
