-- tests/test_autoreload.lua - the automatic reload (AutoReload.lua, settings autoReload.*):
-- off by default and unsubscribed from the tick; rest mode (a capital or an inn, after an
-- arrival and an hour of unsaved play, settled) and timer mode (a prompt outside, never in
-- an instance, on a flight or dead; in a capital or an inn only while the rest mode is
-- off: with both on it leaves them to the rest mode, its prompt hiding there); the direct path (chat warning, cancelled by moving, combat, a window, typing) on a
-- client that allows ReloadUI() without a click; the prompt on WoW Forever (the stub's
-- client: ReloadUI() only inside the click on its plain "Reload now" button, no secure
-- frame), "Later", combat; a shown prompt watched (hidden in an instance, on a flight or
-- dead; "Reload now" greyed and inert while XP is read); professions in a dungeon;
-- ADDON_ACTION_BLOCKED; every safety check; the options section (help icons and their
-- tooltips, the interval slider), the options' plain Reload UI button; zero garbage per
-- tick; read-only mode.
local Stub, T = ...

local format, find = string.format, string.find

local ORGRIMMAR, DUROTAR = 1454, 1411
local ERA = 11508                 -- a client that allows ReloadUI() from addon code
local AREAS = { "left", "center", "right", "doublewide", "fullscreen" }
local GAME_OPTIONS = { "SettingsPanel", "GameMenuFrame", "KeyBindingFrame", "InterfaceOptionsFrame" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- opts.interface (default: the stub's WoW Forever), opts.auto (the autoReload settings),
-- opts.settings (other settings), opts.map (start map), opts.db (TruePlayedDB instead),
-- opts.ui (Stub.InstallUI options), opts.beforeLogin(ns) (after the files load).
-- Ends 12 s after the login: the login /played answer gave a server sync.
local function Start(opts)
  opts = opts or {}
  if opts.interface then Stub.build.interface = opts.interface end
  Stub.InstallUI(opts.ui or { modern = true })
  if opts.map then Stub.SetMap(opts.map) end
  local settings = { firstRunDone = true, autoReload = opts.auto }
  for k, v in pairs(opts.settings or {}) do settings[k] = v end
  rawset(_G, "TruePlayedDB", opts.db or { schema = 1, settings = settings })
  local ns = Stub.LoadAddon()
  if opts.beforeLogin then opts.beforeLogin(ns) end
  Stub.LoginSequence({ settle = 3 })
  Stub.Advance(12)
  return ns
end

-- Counts the TICK subscriptions of AutoReload (installed before DB_READY).
local function SpyTick(ns)
  local spy = { n = 0, on = false }
  local reg, unreg = ns.RegisterMessage, ns.UnregisterMessage
  ns.RegisterMessage = function(msg, owner, fn)
    if msg == "TICK" and owner == ns.AutoReload then
      spy.n = spy.n + 1
      spy.on = true
    end
    return reg(msg, owner, fn)
  end
  ns.UnregisterMessage = function(msg, owner)
    if msg == "TICK" and owner == ns.AutoReload then spy.on = false end
    return unreg(msg, owner)
  end
  return spy
end

local function Count(text, from)
  local n = 0
  for i = from or 1, #Stub.printed do
    if find(Stub.printed[i], text, 1, true) then n = n + 1 end
  end
  return n
end

local function Printed(text, from)
  return Count(text, from) > 0
end

local function State(ns)
  local armed, direct, arrived, countdown, shown = ns.AutoReload.GetState()
  return { armed = armed, direct = direct, arrived = arrived, countdown = countdown ~= nil, shown = shown }
end

local function Warning(ns)
  return format(ns.L.RELOAD_SOON_FMT, ns.C.AUTORELOAD_WARN)
end

local function Prompt(ns)
  local f = ns.AutoReload.GetPrompt()
  return f and f:IsShown() and f or nil
end

local function Controls()
  return rawget(Stub.ui.categories[1].frame, "controls")
end

local function C3(c) return { c[1], c[2], c[3] } end
local function VColor(t) local r, g, b = t:GetVertexColor() return { r, g, b } end

---------------------------------------------------------------------------
-- Arming
---------------------------------------------------------------------------

T.test("autoreload: off by default and unsubscribed from the tick; the settings arm and disarm it", function()
  local spy
  local ns = Start({ interface = ERA, beforeLogin = function(n) spy = SpyTick(n) end })
  local Core = ns.Core
  T.eq(ns.settings.autoReload, { rest = false, timer = false, minutes = 30 }, "defaults: both off, 30 min")
  T.eq(spy.n, 0, "no TICK subscription")
  T.no(State(ns).armed)
  Stub.SetMap(DUROTAR); Stub.Advance(20); Stub.SetMap(ORGRIMMAR); Stub.Advance(3600)
  T.eq(Stub.ui.reloads, 0, "never reloads")
  T.eq(ns.AutoReload.GetPrompt(), nil, "no prompt built")
  Core.SetSetting("autoReload.rest", true)
  T.eq(spy.n, 1, "rest on: subscribed")
  T.ok(spy.on and State(ns).armed)
  Core.SetSetting("autoReload.timer", true)
  T.eq(spy.n, 1, "subscribed once")
  Core.SetSetting("autoReload.rest", false)
  T.ok(spy.on, "the timer keeps it armed")
  Core.SetSetting("autoReload.timer", false)
  T.no(spy.on, "both off: unsubscribed")
  T.no(State(ns).armed)
  -- the interval: 10 to 120 minutes by 5
  T.ok(Core.SetSetting("autoReload.minutes", 33))
  T.eq(ns.settings.autoReload.minutes, 35)
  Core.SetSetting("autoReload.minutes", 1)
  T.eq(ns.settings.autoReload.minutes, 10)
  Core.SetSetting("autoReload.minutes", 500)
  T.eq(ns.settings.autoReload.minutes, 120)
  T.no(Core.SetSetting("autoReload.rest", "yes"), "a boolean only")
  -- saved sparse: only what differs from the defaults
  Stub.Logout()
  T.eq(Stub.saved.settings.autoReload, { minutes = 120 })
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("autoreload: never armed in read-only mode (data of a newer TruePlayed)", function()
  local spy
  local ns = Start({ interface = ERA, map = ORGRIMMAR,
                     db = { schema = 99, settings = { autoReload = { rest = true, timer = true, minutes = 10 } } },
                     beforeLogin = function(n) spy = SpyTick(n) end })
  T.ok(ns.readOnly)
  T.eq(ns.settings.autoReload.rest, true, "the settings are read")
  T.eq(spy.n, 0, "not armed")
  ns.Core.SetSetting("autoReload.timer", false)
  ns.Core.SetSetting("autoReload.timer", true)
  T.eq(spy.n, 0, "a change does not arm it either")
  Stub.SetMap(DUROTAR); Stub.Advance(30); Stub.SetMap(ORGRIMMAR); Stub.Advance(3600)
  T.eq(Stub.ui.reloads, 0)
  T.eq(ns.AutoReload.GetPrompt(), nil)
  T.eq(ns.AutoReload.Blocker(true), "readonly")
end)

---------------------------------------------------------------------------
-- Rest mode, direct path
---------------------------------------------------------------------------

T.test("autoreload: rest mode reloads in a capital only after an arrival, settled, after a chat warning", function()
  local ns = Start({ interface = ERA, map = ORGRIMMAR, auto = { rest = true } })
  local C, warn = ns.C, Warning(ns)
  T.ok(ns.AutoReload.IsDirect(), "a client that allows ReloadUI()")
  -- logged in town and staying there (AFK for hours): never
  Stub.SetAFK(true); Stub.Advance(7200); Stub.SetAFK(false)
  Stub.Advance(60)
  T.eq(Count(warn), 0, "no arrival: no warning")
  T.eq(Stub.ui.reloads, 0)
  -- a few seconds out (less than C.AUTORELOAD_SETTLE) is no arrival
  Stub.SetMap(DUROTAR); Stub.Advance(C.AUTORELOAD_SETTLE - 3); Stub.SetMap(ORGRIMMAR)
  Stub.Advance(120)
  T.no(State(ns).arrived, "too short a trip")
  T.eq(Count(warn), 0)
  -- professions in town are not "outside" either
  Stub.Spell("CHANNEL_START", 7620); Stub.Advance(30)
  T.eq((ns.Tracker.GetState()), "f", "fishing")
  Stub.Spell("CHANNEL_STOP", 7620)
  Stub.Advance(60)
  T.no(State(ns).arrived, "fishing in town is no arrival")
  -- out in the world, then back: C.AUTORELOAD_SETTLE s still, the warning, C.AUTORELOAD_WARN s, the reload
  Stub.SetMap(DUROTAR); Stub.Advance(C.AUTORELOAD_SETTLE + 2)
  T.ok(State(ns).arrived, "arrived")
  T.eq(Count(warn), 0, "nothing outside")
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE - 1)
  T.eq(Count(warn), 0, "not settled yet")
  Stub.Advance(2)
  T.eq(Count(warn), 1, "the chat warning")
  T.eq(Stub.ui.reloads, 0, "not yet")
  Stub.Advance(C.AUTORELOAD_WARN - 1)
  T.eq(Stub.ui.reloads, 0, "the warning's seconds first")
  Stub.Advance(1)
  T.eq(Stub.ui.reloads, 1, "ReloadUI()")
  Stub.Advance(30)
  T.eq(Stub.ui.reloads, 1, "never twice in one load")
  -- the next load (the reload): staying in town does not reload again
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.ok(State(ns).armed, "armed again")
  Stub.Advance(7200)
  T.eq(Count(Warning(ns)), 0, "no new warning while staying in town")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("autoreload: rest mode waits for C.AUTORELOAD_REST_MIN of unsaved play; an inn counts, a flight does not", function()
  local ns = Start({ interface = ERA, auto = { rest = true } })
  local C, warn = ns.C, Warning(ns)
  Stub.Advance(20)                       -- in Durotar: an arrival
  T.ok(State(ns).arrived)
  Stub.SetResting(true)                  -- an inn (rest area) in the world: "i"
  T.eq((ns.Tracker.GetState()), "i")
  Stub.Advance(120)
  T.eq(Count(warn), 0, "about 2 min unsaved")
  local due = ns.Tracker.loadStartG + C.AUTORELOAD_REST_MIN
  Stub.Advance(due - Stub.Now() - 1)
  T.eq(Count(warn), 0, "a second before C.AUTORELOAD_REST_MIN")
  Stub.Advance(2)
  T.eq(Count(warn), 1, "due: warning in the inn")
  Stub.Advance(C.AUTORELOAD_WARN)
  T.eq(Stub.ui.reloads, 1)
  -- a flight over a capital is never a rest place
  Stub.Reset()
  ns = Start({ interface = ERA, auto = { rest = true } })
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN + 100)
  Stub.SetTaxi(true); Stub.SetMap(ORGRIMMAR); Stub.Advance(120)
  T.eq((ns.Tracker.GetState()), "t")
  T.eq(Count(Warning(ns)), 0, "never on a flight")
  Stub.SetTaxi(false); Stub.Advance(ns.C.AUTORELOAD_SETTLE + 1)
  T.eq(Count(Warning(ns)), 1, "landed in the capital")
end)

T.test("autoreload: a capital or an inn reloads once an hour of play is unsaved, also after an earlier arrival (idle in town)", function()
  local ns = Start({ interface = ERA, auto = { rest = true } })
  local C, warn = ns.C, Warning(ns)
  T.eq(C.AUTORELOAD_REST_MIN, 3600, "an hour")
  Stub.Advance(20)                       -- in Durotar: an arrival
  T.ok(State(ns).arrived)
  Stub.SetMap(ORGRIMMAR)
  local start = ns.Tracker.loadStartG
  Stub.Advance(start + 10 * 60 + 30 - Stub.Now())
  T.eq(Count(warn), 0, "10 minutes in town: nothing")
  Stub.Advance(start + 59 * 60 - Stub.Now())
  T.eq(Count(warn), 0, "59 minutes: still nothing")
  Stub.Advance(start + 60 * 60 + 1 - Stub.Now())
  T.eq(Count(warn), 1, "an hour: the chat warning")
  Stub.Advance(C.AUTORELOAD_WARN)
  T.eq(Stub.ui.reloads, 1)
  -- came back at 40 minutes and stayed idle: the hour is reached in town
  Stub.Reset()
  ns = Start({ interface = ERA, auto = { rest = true } })
  warn = Warning(ns)
  start = ns.Tracker.loadStartG
  Stub.Advance(start + 40 * 60 - Stub.Now())   -- in Durotar
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(start + 59 * 60 - Stub.Now())
  T.eq(Count(warn), 0, "back in town at 40 minutes: nothing before the hour")
  Stub.Advance(start + 60 * 60 + 1 - Stub.Now())
  T.eq(Count(warn), 1, "the hour reached while idle in town: the chat warning")
  -- WoW Forever, an inn: its prompt after an hour too
  Stub.Reset()
  ns = Start({ auto = { rest = true } })
  Stub.Advance(20)
  Stub.SetResting(true)
  start = ns.Tracker.loadStartG
  Stub.Advance(start + 30 * 60 - Stub.Now())
  T.eq(ns.AutoReload.GetPrompt(), nil, "30 minutes in the inn: no prompt")
  Stub.Advance(start + 59 * 60 - Stub.Now())
  T.eq(ns.AutoReload.GetPrompt(), nil, "59 minutes: no prompt")
  Stub.Advance(start + 60 * 60 + 1 - Stub.Now())
  T.ok(Prompt(ns) ~= nil, "an hour: the prompt")
  T.eq(Stub.ui.reloads, 0)
end)

T.test("autoreload: moving, combat, a window, typing or leaving town cancel the countdown (asked again 10 min later)", function()
  local CANCELS = {
    { "moving", function() Stub.player.moving = true end, function() Stub.player.moving = false end },
    { "combat", function() Stub.EnterCombat() end, function() Stub.LeaveCombat() end },
    { "the statistics window", function(ns) ns.Window.Show() end, function(ns) ns.Window.Hide() end },
    { "the options", function(ns) ns.Options.Open() end, function() Stub.ui.CloseSettings() end },
    { "the game's settings", function() SettingsPanel:Show() end, function() SettingsPanel:Hide() end },
    { "typing", function() Stub.busy.keyFocus = {} end, function() Stub.busy.keyFocus = nil end },
    { "leaving town", function() Stub.SetMap(DUROTAR) end, function() Stub.SetMap(ORGRIMMAR) end },
  }
  for _, c in ipairs(CANCELS) do
    Stub.Reset()
    local ns = Start({ interface = ERA, auto = { rest = true } })
    local C, L, warn, what = ns.C, ns.L, Warning(ns), c[1]
    Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
    Stub.SetMap(ORGRIMMAR)
    Stub.Advance(C.AUTORELOAD_SETTLE + 1)
    T.eq(Count(warn), 1, what .. ": warning")
    Stub.Advance(2)
    c[2](ns)
    Stub.Advance(1)
    T.eq(Count(L.RELOAD_CANCELLED), 1, what .. ": cancelled in chat")
    T.no(State(ns).countdown, what .. ": no countdown")
    Stub.Advance(10)
    T.eq(Stub.ui.reloads, 0, what .. ": no reload")
    c[3](ns)
    Stub.Advance(C.AUTORELOAD_SNOOZE - 30)
    T.eq(Count(warn), 1, what .. ": not asked again before C.AUTORELOAD_SNOOZE")
    Stub.Advance(40)
    T.eq(Count(warn), 2, what .. ": asked again")
    Stub.Advance(C.AUTORELOAD_WARN)
    T.eq(Stub.ui.reloads, 1, what .. ": then reloads")
  end
end)

T.test("autoreload: not still at the due moment: settles again; blocked: checked again C.AUTORELOAD_RETRY s later", function()
  local ns = Start({ interface = ERA, auto = { rest = true } })
  local C, warn = ns.C, Warning(ns)
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.player.moving = true
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(60)
  T.eq(Count(warn), 0, "walking around town: never settled")
  Stub.player.moving = false
  Stub.Advance(C.AUTORELOAD_SETTLE - 2)
  T.eq(Count(warn), 0, "settling again")
  Stub.Advance(3)
  T.eq(Count(warn), 1, "settled")
  Stub.Advance(C.AUTORELOAD_WARN)
  T.eq(Stub.ui.reloads, 1)
  -- a Blizzard panel open at the due moment: nothing, then the retry
  Stub.Reset()
  ns = Start({ interface = ERA, auto = { rest = true } })
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.busy.panels.left = {}
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE + 30)
  T.eq(Count(Warning(ns)), 0, "a panel open: waits")
  Stub.busy.panels.left = nil
  Stub.Advance(C.AUTORELOAD_RETRY + 1)
  T.eq(Count(Warning(ns)), 1, "closed: within C.AUTORELOAD_RETRY s")
end)

---------------------------------------------------------------------------
-- Safety checks
---------------------------------------------------------------------------

T.test("autoreload: every safety condition blocks; the game functions a client lacks are skipped", function()
  local ns = Start({ interface = ERA, auto = { rest = true } })
  Stub.Advance(120)
  local AR, Tr = ns.AutoReload, ns.Tracker
  T.eq(AR.Blocker(true), nil, "nothing blocks")
  T.eq(AR.Blocker(false), nil)
  local function Check(why, on, off, directOnly)
    on()
    T.eq(AR.Blocker(true), why, why .. ": blocks a reload without a click")
    T.eq(AR.Blocker(false), (not directOnly) and why or nil, why .. ": the prompt")
    off()
    T.eq(AR.Blocker(true), nil, why .. ": cleared")
  end
  Check("ready", function() ns.ready = false end, function() ns.ready = true end)
  Check("readonly", function() ns.readOnly = true end, function() ns.readOnly = false end)
  local db = rawget(_G, "TruePlayedDB")
  Check("db", function() rawset(_G, "TruePlayedDB", nil) end, function() rawset(_G, "TruePlayedDB", db) end)
  Check("db", function() rawset(_G, "TruePlayedDB", { schema = 1 }) end, function() rawset(_G, "TruePlayedDB", db) end)
  Check("wtfix", function() rawset(_G, "WTFIX_BOOTSTRAP", { targets = { TruePlayed = true } }) end,
    function() rawset(_G, "WTFIX_DB", { protectedAddons = { TruePlayed = false } }) end)
  rawset(_G, "WTFIX_BOOTSTRAP", nil)
  rawset(_G, "WTFIX_DB", nil)
  Check("reconcile", function() Tr.pendingReconcile = true end, function() Tr.pendingReconcile = false end)
  Check("reconcile", function() Tr.gapXPPending = true end, function() Tr.gapXPPending = false end)
  Check("played", function() T.ok(ns.Played.Request("manual")) end, function() Stub.Advance(1) end)
  Check("sync", function() Tr.sync.valid = false end, function() Tr.sync.valid = true end)
  Check("xp", function() Stub.GrantXP(100) end, function() Stub.Advance(5) end)   -- a kill waits C.DISCOVERY_WINDOW
  local start = Tr.loadStartG
  Check("load", function() Tr.loadStartG = Stub.Now() - 30 end, function() Tr.loadStartG = start end)
  Check("levelup", function() Tr.levelUpG = Stub.Now() - 10 end, function() Tr.levelUpG = Stub.Now() - 41 end)
  Check("combat", function() Stub.combat = true end, function() Stub.combat = false end)
  Check("combat", function() Stub.busy.combat = true end, function() Stub.busy.combat = nil end)
  Check("combat", function() Stub.busy.lockdown = true end, function() Stub.busy.lockdown = nil end)
  Check("dead", function() Stub.player.dead = true end, function() Stub.player.dead = false end)
  Check("cast", function() Stub.busy.casting = "Hearthstone" end, function() Stub.busy.casting = nil end)
  Check("cast", function() Stub.busy.channel = "Fishing" end, function() Stub.busy.channel = nil end)
  Check("typing", function() Stub.busy.keyFocus = {} end, function() Stub.busy.keyFocus = nil end)
  Check("popup", function() Stub.busy.popup = true end, function() Stub.busy.popup = nil end)
  for _, area in ipairs(AREAS) do
    Check("panel", function() Stub.busy.panels[area] = {} end, function() Stub.busy.panels[area] = nil end)
  end
  -- the game's menu and options: no UI panel area (GetUIPanel never returns them)
  for _, name in ipairs(GAME_OPTIONS) do
    Check("panel", function() _G[name]:Show() end, function() _G[name]:Hide() end)
  end
  Check("cinematic", function() Stub.busy.cinematic = true end, function() Stub.busy.cinematic = nil end)
  Check("cinematic", function() MovieFrame:Show() end, function() MovieFrame:Hide() end)
  Check("readycheck", function() ReadyCheckFrame:Show() end, function() ReadyCheckFrame:Hide() end)
  Check("cursor", function() Stub.busy.cursor = true end, function() Stub.busy.cursor = nil end)
  Check("cursor", function() Stub.busy.targeting = true end, function() Stub.busy.targeting = nil end)
  Check("window", function() ns.Window.Show() end, function() ns.Window.Hide() end, true)
  Check("window", function() ns.Options.Open() end, function() Stub.ui.CloseSettings() end, true)
  -- a client without some of these functions or frames: skipped, no error
  for _, name in ipairs({ "UnitAffectingCombat", "UnitCastingInfo", "UnitChannelInfo", "GetCurrentKeyBoardFocus",
                          "StaticPopup_IsAnyDialogShown", "GetUIPanel", "InCinematic", "MovieFrame",
                          "ReadyCheckFrame", "CursorHasItem", "SpellIsTargeting", "IsPlayerMoving",
                          "SettingsPanel", "GameMenuFrame", "KeyBindingFrame", "InterfaceOptionsFrame" }) do
    rawset(_G, name, nil)
  end
  T.eq(AR.Blocker(true), nil, "nothing to read: not blocked")
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  T.eq(Stub.ui.reloads, 1, "and it still works")
  T.eq(Stub.errors, {})
end)

T.test("autoreload: a pending crash reconcile or WTFix protection never reloads", function()
  local ns = Start({ interface = ERA, auto = { rest = true, timer = true, minutes = 10 } })
  rawset(_G, "WTFIX_BOOTSTRAP", { targets = { TruePlayed = true } })
  Stub.SetMap(DUROTAR); Stub.Advance(30); Stub.SetMap(ORGRIMMAR)
  Stub.Advance(3600)
  T.eq(Count(Warning(ns)), 0, "WTFix would roll the data back")
  T.eq(ns.AutoReload.GetPrompt(), nil)
  rawset(_G, "WTFIX_BOOTSTRAP", nil)
  ns.Tracker.gapXPPending = true
  Stub.SetMap(DUROTAR); Stub.Advance(30)
  T.eq(ns.AutoReload.GetPrompt(), nil, "timer mode outside: no prompt either")
  ns.Tracker.gapXPPending = false
  Stub.Advance(ns.C.AUTORELOAD_RETRY + 1)
  T.ok(Prompt(ns) ~= nil, "cleared: the prompt")
end)

---------------------------------------------------------------------------
-- The prompt (WoW Forever, the stub's client)
---------------------------------------------------------------------------

-- Frames the stub created on top of `button` (a secure overlay would be one).
local function ChildFrames(button)
  local n = 0
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_parent") == button and o._type ~= "FontString" and o._type ~= "Texture" then n = n + 1 end
  end
  return n
end

T.test("autoreload: on WoW Forever a prompt asks; its plain Reload now calls ReloadUI() on click only", function()
  local ns = Start({ auto = { rest = true } })
  local C, L, AR = ns.C, ns.L, ns.AutoReload
  T.no(AR.IsDirect(), "Forever reloads only inside a click")
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE - 1)
  T.eq(Prompt(ns), nil, "not settled yet")
  Stub.Advance(2)
  local f = Prompt(ns)
  T.ok(f ~= nil, "the prompt")
  T.eq(Count(Warning(ns)), 0, "no countdown on Forever")
  -- top centre, above the game's frames, the addon's look
  local p = rawget(f, "_points")[1]
  T.eq({ p.point, p.relPoint }, { "TOP", "TOP" })
  T.ok(p.rel == UIParent, "on UIParent")
  T.eq(f:GetFrameStrata(), "DIALOG")
  local tp = f.tp
  T.eq(tp.title:GetText(), L.ADDON_TITLE)
  local unsaved = Stub.Now() - ns.Tracker.loadStartG
  T.eq(tp.text:GetText(), format(L.RELOAD_PROMPT_FMT, ns.Fmt.Duration(unsaved)))
  T.eq(rawget(tp.now.tpText, "_text"), L.RELOAD_NOW)
  T.eq(rawget(tp.later.tpText, "_text"), L.RELOAD_LATER)
  for _, b in ipairs({ tp.now, tp.later }) do
    T.ok(b:GetWidth() >= tp.now.tpText:GetStringWidth() + 16 and b:GetWidth() >= b.tpText:GetStringWidth() + 16,
      "the button fits its text")
  end
  local ui = ns.Themes.Active().ui
  T.eq({ rawget(f, "_bgR"), rawget(f, "_bgG"), rawget(f, "_bgB") }, C3(ui.bg), "the theme's background")
  T.eq({ tp.title:GetTextColor() }, { ui.accent[1], ui.accent[2], ui.accent[3] }, "title in the accent colour")
  -- "Reload now": a plain, enabled button, nothing on top of it (no secure frame)
  T.eq(tp.now:GetObjectType(), "Button")
  T.ok(tp.now:IsEnabled(), "enabled")
  T.eq(ChildFrames(tp.now), 0, "no overlay")
  T.eq(f:IsProtected(), false)
  -- shown until a click; no second prompt; never a reload without the click
  Stub.Advance(1800)
  T.ok(Prompt(ns) == f, "still the one prompt")
  T.eq(Stub.ui.reloads, 0, "no reload without a click on Forever")
  -- the player's click: ReloadUI() inside it, nothing said
  local n = #Stub.printed
  Stub.RunScript(tp.now, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1, "reloaded by the click")
  T.eq(#Stub.printed, n, "no hint")
  T.eq(Stub.errors, {})
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("autoreload: Later hides the prompt and asks again C.AUTORELOAD_SNOOZE s later", function()
  local ns = Start({ auto = { rest = true } })
  local C = ns.C
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE + 1)
  local f = Prompt(ns)
  T.ok(f ~= nil)
  Stub.RunScript(f.tp.later, "OnClick", "LeftButton")
  T.no(f:IsShown(), "hidden")
  T.no(State(ns).shown)
  Stub.Advance(C.AUTORELOAD_SNOOZE - 2)
  T.eq(Prompt(ns), nil, "not before the snooze")
  Stub.Advance(3)
  T.ok(Prompt(ns) == f, "asked again (the same frame)")
  T.eq(Stub.ui.reloads, 0, "Later never reloads")
  -- the same frame and buttons for the frame's life
  local now = f.tp.now
  Stub.RunScript(f.tp.later, "OnClick", "LeftButton")
  Stub.Advance(C.AUTORELOAD_SNOOZE + 1)
  T.ok(Prompt(ns) == f and f.tp.now == now, "the same button")
  T.eq(ChildFrames(now), 0, "still nothing on top of it")
end)

T.test("autoreload: combat hides the prompt at once; asked again after the fight, never during it", function()
  local ns = Start({ auto = { rest = true } })
  local C = ns.C
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE + 1)
  local f = Prompt(ns)
  T.ok(f ~= nil)
  Stub.EnterCombat()
  T.no(f:IsShown(), "hidden at PLAYER_REGEN_DISABLED")
  T.no(State(ns).shown)
  Stub.Advance(120)
  T.no(f:IsShown(), "never shown in combat")
  Stub.LeaveCombat()
  Stub.Advance(C.AUTORELOAD_RETRY + 1)
  T.ok(f:IsShown(), "asked again after the fight")
  T.eq(Stub.ui.reloads, 0)
  -- due during a fight: nothing built, asked after it
  Stub.Reset()
  ns = Start({ auto = { rest = true } })
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.SetMap(ORGRIMMAR)
  Stub.EnterCombat()
  Stub.Advance(60)
  T.eq(ns.AutoReload.GetPrompt(), nil, "nothing built in combat")
  Stub.LeaveCombat()
  Stub.Advance(C.AUTORELOAD_RETRY + C.AUTORELOAD_SETTLE + 1)
  T.ok(Prompt(ns) ~= nil, "after combat: the prompt")
  -- turned off during a lockdown without PLAYER_REGEN_DISABLED (a pet's fight): a plain
  -- frame, hidden at once
  Stub.busy.lockdown = true
  Stub.Advance(1)
  T.ok(Prompt(ns) ~= nil, "the player is not fighting: still shown")
  ns.Core.SetSetting("autoReload.rest", false)
  T.eq(Prompt(ns), nil, "both off: hidden, even during the lockdown")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Timer mode
---------------------------------------------------------------------------

T.test("autoreload: timer mode asks outside, waits in an instance, on a flight or dead; acts in town without an arrival", function()
  local ns = Start({ interface = ERA, auto = { timer = true, minutes = 10 } })
  local C, L = ns.C, ns.L
  local due = ns.Tracker.loadStartG + 600
  -- in an instance at the due moment: waits
  Stub.SetInstance(true, "party", 389, nil)
  Stub.Advance(due - Stub.Now() + 60)
  T.eq(ns.AutoReload.GetPrompt(), nil, "never in an instance")
  Stub.SetTaxi(true)
  Stub.SetInstance(false, nil, 0, DUROTAR)
  Stub.Advance(60)
  T.eq(ns.AutoReload.GetPrompt(), nil, "never on a flight")
  Stub.SetTaxi(false)
  Stub.Die()
  Stub.Advance(60)
  T.eq(ns.AutoReload.GetPrompt(), nil, "never dead")
  Stub.Resurrect(false)
  Stub.Advance(2)
  local f = Prompt(ns)
  T.ok(f ~= nil, "in the open world: the prompt, even on a client that could reload directly")
  T.eq(Count(Warning(ns)), 0, "no reload without a click outside town")
  T.eq(Stub.ui.reloads, 0)
  Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1, "Reload now: ReloadUI()")
  -- in town, without an arrival (logged in there): the timer acts like the rest mode
  Stub.Reset()
  ns = Start({ interface = ERA, map = ORGRIMMAR, auto = { timer = true, minutes = 15 } })
  Stub.Advance(ns.Tracker.loadStartG + 15 * 60 - Stub.Now() - 1)
  T.eq(Count(Warning(ns)), 0, "a second early")
  Stub.Advance(2)
  T.eq(Count(Warning(ns)), 1, "due in town: the warning")
  Stub.Advance(C.AUTORELOAD_WARN)
  T.eq(Stub.ui.reloads, 1)
  T.eq(ns.AutoReload.GetPrompt(), nil, "no prompt")
  -- the interval follows the setting
  T.no(Printed(L.RELOAD_CANCELLED))
end)

T.test("autoreload: a longer interval moves the due time; turning the options off hides the prompt", function()
  local ns = Start({ auto = { timer = true, minutes = 10 } })
  ns.Core.SetSetting("autoReload.minutes", 30)
  Stub.Advance(ns.Tracker.loadStartG + 30 * 60 - Stub.Now() - 1)
  T.eq(ns.AutoReload.GetPrompt(), nil, "not at 10 min")
  Stub.Advance(2)
  local f = Prompt(ns)
  T.ok(f ~= nil, "at 30 min")
  ns.Core.SetSetting("autoReload.timer", false)
  T.no(f:IsShown(), "both off: hidden")
  T.no(State(ns).armed)
end)

T.test("autoreload: timer mode never asks in an instance, even while gathering there; waits for the end of a gathering", function()
  local ns = Start({ auto = { timer = true, minutes = 10 } })
  local C = ns.C
  Stub.SetInstance(true, "party", 389, nil)
  Stub.Advance(ns.Tracker.loadStartG + 600 - Stub.Now() + 30)
  T.eq(ns.AutoReload.GetPrompt(), nil, "due in a dungeon: waits")
  -- skinning in the dungeon: professions hide the place in the state key
  Stub.Spell("START", 8613); Stub.Advance(1); Stub.Spell("SUCCEEDED", 8613); Stub.Spell("STOP", 8613)
  Stub.Advance(2)
  T.eq((ns.Tracker.GetState()), "f", "professions")
  T.eq(ns.AutoReload.GetPrompt(), nil, "professions in a dungeon: no prompt")
  Stub.Advance(C.PROF_GRACE + 2)
  T.eq((ns.Tracker.GetState()), "d")
  T.eq(ns.AutoReload.GetPrompt(), nil, "still in the dungeon")
  -- herbs in the open world: not in the middle of it, asked once it is over
  Stub.SetInstance(false, nil, 0, DUROTAR)
  Stub.Spell("START", 2366)
  Stub.Advance(2)
  T.eq((ns.Tracker.GetState()), "f")
  T.eq(ns.AutoReload.GetPrompt(), nil, "not while gathering")
  Stub.Spell("SUCCEEDED", 2366); Stub.Spell("STOP", 2366)
  Stub.Advance(C.PROF_GRACE + 2)
  T.eq((ns.Tracker.GetState()), "w")
  T.ok(Prompt(ns) ~= nil, "gathering over: the prompt")
end)

T.test("autoreload: a shown prompt hides in an instance, on a flight or dead, and asks again once out", function()
  local ns = Start({ map = DUROTAR, auto = { timer = true, minutes = 10 } })
  local C = ns.C
  Stub.Advance(ns.Tracker.loadStartG + 600 - Stub.Now() + 1)
  local f = Prompt(ns)
  T.ok(f ~= nil, "the prompt in the open world")
  local AWAY = {
    { "a dungeon", function() Stub.SetInstance(true, "party", 389, nil) end,
                   function() Stub.SetInstance(false, nil, 0, DUROTAR) end },
    { "a flight", function() Stub.SetTaxi(true) end, function() Stub.SetTaxi(false) end },
    { "dead", function() Stub.Die() end, function() Stub.Resurrect(false) end },
  }
  for _, a in ipairs(AWAY) do
    a[2]()
    Stub.Advance(1)
    T.no(f:IsShown(), a[1] .. ": hidden at the next tick")
    T.no(State(ns).shown, a[1])
    Stub.Advance(120)
    T.no(f:IsShown(), a[1] .. ": never shown there")
    a[3]()
    Stub.Advance(C.AUTORELOAD_RETRY + 1)
    T.ok(f:IsShown(), a[1] .. ": out of it, asked again")
  end
  -- professions inside a dungeon (the key "f") hide it too; outside they do not
  Stub.Spell("START", 2366); Stub.Advance(1)
  T.eq((ns.Tracker.GetState()), "f")
  T.ok(f:IsShown(), "gathering in the open world: still shown")
  Stub.Spell("SUCCEEDED", 2366); Stub.Spell("STOP", 2366)
  Stub.SetInstance(true, "party", 389, nil)
  Stub.Spell("START", 8613)
  Stub.Advance(1)
  T.eq((ns.Tracker.GetState()), "f")
  T.no(f:IsShown(), "professions in a dungeon: hidden")
  T.eq(Stub.ui.reloads, 0)
  T.eq(Stub.errors, {})
end)

T.test("autoreload: Reload now waits, greyed and inert, while an XP gain or a level-up is still read (the prompt stays)", function()
  local ns = Start({ map = DUROTAR, auto = { timer = true, minutes = 10 } })
  local C, L = ns.C, ns.L
  Stub.Advance(ns.Tracker.loadStartG + 600 - Stub.Now() + 1)
  local f = Prompt(ns)
  T.ok(f ~= nil)
  local ui = ns.Themes.Active().ui
  local now = f.tp.now
  T.ok(now:IsEnabled(), "ready: enabled")
  T.eq({ now.tpText:GetTextColor() }, C3(ui.value))
  -- greyed, disabled, and its click does nothing (the game would not even send it)
  local function Waits(what)
    T.ok(f:IsShown(), what .. ": the prompt stays")
    T.no(now:IsEnabled(), what .. ": disabled")
    T.eq({ now.tpText:GetTextColor() }, C3(ui.dim), what .. ": greyed")
    local n = #Stub.printed
    Stub.RunScript(now, "OnClick", "LeftButton")
    T.eq(#Stub.printed, n, what .. ": nothing said")
    T.eq(Stub.ui.reloads, 0, what .. ": no reload")
  end
  -- a kill's XP: read within C.DISCOVERY_WINDOW s
  Stub.GrantXP(100)
  Stub.Advance(1)
  T.eq(ns.AutoReload.Blocker(false), "xp")
  Waits("an XP gain")
  Stub.Advance(C.DISCOVERY_WINDOW + 1)
  T.ok(now:IsEnabled(), "read: ready again")
  T.eq({ now.tpText:GetTextColor() }, C3(ui.value))
  -- a click between the XP and the next tick: the click checks again, greys, no reload
  Stub.GrantXP(100)
  T.ok(now:IsEnabled(), "the tick has not seen it yet")
  Stub.RunScript(now, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 0, "the click checks again: no reload")
  Waits("after a click before the tick")
  Stub.Advance(C.DISCOVERY_WINDOW + 2)    -- the XP came between two ticks
  T.ok(now:IsEnabled(), "ready again")
  -- greyed, then hidden (a dungeon) and asked again later: enabled again
  Stub.GrantXP(100)
  Stub.Advance(1)
  T.no(now:IsEnabled(), "greyed")
  Stub.SetInstance(true, "party", 389, nil)
  Stub.Advance(1)
  T.no(f:IsShown(), "hidden in the dungeon")
  Stub.SetInstance(false, nil, 0, DUROTAR)
  Stub.Advance(C.AUTORELOAD_RETRY + 1)
  T.ok(f:IsShown() and now:IsEnabled(), "asked again: enabled")
  T.eq({ now.tpText:GetTextColor() }, C3(ui.value))
  -- a level-up: C.AUTORELOAD_LEVELUP_WAIT s (its /played check)
  Stub.GrantXP(Stub.player.max - Stub.player.xp, { quest = Stub.player.max - Stub.player.xp })
  Stub.Advance(C.DISCOVERY_WINDOW + 1)
  T.eq(ns.AutoReload.Blocker(false), "levelup")
  Waits("a level-up")
  Stub.Advance(C.AUTORELOAD_LEVELUP_WAIT)
  T.eq(ns.AutoReload.Blocker(false), nil)
  T.ok(f:IsShown() and now:IsEnabled(), "ready again, the same prompt")
  Stub.RunScript(now, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1, "then the click reloads")
  -- a direct client: its button calls ReloadUI() only when ready
  Stub.Reset()
  ns = Start({ interface = ERA, map = DUROTAR, auto = { timer = true, minutes = 10 } })
  Stub.Advance(ns.Tracker.loadStartG + 600 - Stub.Now() + 1)
  f = Prompt(ns)
  T.ok(f ~= nil)
  Stub.GrantXP(100)
  Stub.Advance(1)
  Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 0, "direct client: waits too")
  Stub.Advance(C.DISCOVERY_WINDOW + 1)
  Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1, "ready: ReloadUI()")
  T.no(find(table.concat(Stub.printed, "\n"), L.RELOAD_BY_HAND, 1, true), "never the hint")
end)

---------------------------------------------------------------------------
-- Both options: the timer leaves capitals and inns to the rest mode
---------------------------------------------------------------------------

T.test("autoreload: with both options on, the timer never acts in a capital or an inn, only outside; the rest mode keeps its hour", function()
  local ns = Start({ interface = ERA, map = ORGRIMMAR, auto = { rest = true, timer = true, minutes = 10 } })
  local C, warn = ns.C, Warning(ns)
  local start = ns.Tracker.loadStartG
  -- logged in town: the timer due there does nothing, however long the player stays
  Stub.Advance(start + 10 * 60 + 60 - Stub.Now())
  T.eq(Count(warn), 0, "the timer due in town: no reload there")
  T.eq(ns.AutoReload.GetPrompt(), nil, "nor a prompt")
  Stub.Advance(600)
  T.eq(Count(warn), 0, "still nothing while staying in town")
  -- out of town: never in an instance; in the open world the timer's prompt (as before)
  Stub.SetInstance(true, "party", 389, nil)
  Stub.Advance(30)
  T.eq(ns.AutoReload.GetPrompt(), nil, "never in an instance")
  Stub.SetInstance(false, nil, 0, DUROTAR)
  Stub.Advance(2)
  local f = Prompt(ns)
  T.ok(f ~= nil, "out of town: the timer asks")
  T.eq(Count(warn), 0, "outside: a prompt, no countdown")
  -- back in town, the prompt shown: hidden at the next tick (the rest mode's hour not reached)
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(1)
  T.no(f:IsShown(), "entering the capital hides the timer's prompt")
  T.no(State(ns).shown)
  Stub.Advance(120)
  T.no(f:IsShown(), "never shown in town before the rest mode's hour")
  T.eq(Count(warn), 0)
  -- an inn in the world: the same
  Stub.SetMap(DUROTAR)
  Stub.Advance(C.AUTORELOAD_RETRY + 1)
  T.ok(f:IsShown(), "out again: asked again")
  Stub.SetResting(true)
  Stub.Advance(1)
  T.no(f:IsShown(), "an inn hides it too")
  Stub.SetResting(false)
  Stub.Advance(C.AUTORELOAD_RETRY + 1)
  T.ok(f:IsShown(), "out of the inn: asked again")
  -- Later, then into town: the snooze ends there, still nothing in town
  Stub.RunScript(f.tp.later, "OnClick", "LeftButton")
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SNOOZE + 30)
  T.eq(Prompt(ns), nil, "the snooze over in town: nothing")
  T.eq(Count(warn), 0)
  -- the rest mode keeps its own rule: an arrival (made above) and an hour of unsaved play
  Stub.Advance(start + C.AUTORELOAD_REST_MIN - Stub.Now() - 1)
  T.eq(Count(warn), 0, "a second before the hour")
  Stub.Advance(2)
  T.eq(Count(warn), 1, "the hour: the rest mode's warning in town")
  Stub.Advance(C.AUTORELOAD_WARN)
  T.eq(Stub.ui.reloads, 1)
  -- the next load (the reload), still in town: the timer due again does nothing there
  local from = #Stub.printed + 1
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.ok(State(ns).armed, "armed again")
  start = ns.Tracker.loadStartG
  Stub.Advance(start + 10 * 60 + 60 - Stub.Now())
  T.eq(Count(Warning(ns), from), 0, "after the reload: no warning in town")
  T.eq(ns.AutoReload.GetPrompt(), nil, "nor a prompt")
  Stub.SetMap(DUROTAR)
  Stub.Advance(2)
  T.ok(Prompt(ns) ~= nil, "out of town: the timer asks")
  T.eq(Stub.errors, {})
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("autoreload: on WoW Forever too, the timer's prompt never shows in town with the rest option on, only outside", function()
  local ns = Start({ map = ORGRIMMAR, auto = { rest = true, timer = true, minutes = 10 } })
  local C = ns.C
  Stub.Advance(ns.Tracker.loadStartG + 10 * 60 + 60 - Stub.Now())
  T.eq(ns.AutoReload.GetPrompt(), nil, "due in town: no prompt there")
  Stub.SetMap(DUROTAR)
  Stub.Advance(2)
  local f = Prompt(ns)
  T.ok(f ~= nil, "outside: the prompt")
  Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1, "its click reloads")
  -- the rest mode's own prompt in town (an arrival, an hour) stays when the player walks
  Stub.Reset()
  ns = Start({ auto = { rest = true, timer = true, minutes = 10 } })
  Stub.Advance(ns.Tracker.loadStartG + C.AUTORELOAD_REST_MIN - Stub.Now() - 30)
  f = Prompt(ns)
  T.ok(f ~= nil, "the timer's prompt outside")
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(1)
  T.no(f:IsShown(), "into town before the hour: hidden")
  Stub.Advance(60)
  T.ok(f:IsShown(), "the hour reached in town, after an arrival: the rest mode asks")
  Stub.Advance(120)
  T.ok(f:IsShown(), "and its prompt stays in town")
  T.eq(Stub.ui.reloads, 0)
end)

T.test("autoreload: with the rest option off the timer still acts in a capital or an inn; ticking it leaves them to it", function()
  -- WoW Forever: the timer's prompt in town without an arrival, as before
  local ns = Start({ map = ORGRIMMAR, auto = { timer = true, minutes = 10 } })
  local C, Core = ns.C, ns.Core
  Stub.Advance(ns.Tracker.loadStartG + 600 - Stub.Now() + 1)
  local f = Prompt(ns)
  T.ok(f ~= nil, "rest off: the timer asks in town")
  -- the rest option ticked: hidden at the next tick, nothing in town since
  Core.SetSetting("autoReload.rest", true)
  Stub.Advance(1)
  T.no(f:IsShown(), "rest on: the capital is left to it")
  Stub.Advance(1200)
  T.no(f:IsShown(), "not asked again in town")
  -- unticked: the timer asks in town again
  Core.SetSetting("autoReload.rest", false)
  Stub.Advance(C.AUTORELOAD_RETRY + 1)
  T.ok(f:IsShown(), "rest off again: asked in town")
  -- a direct client in an inn: no countdown with the rest option on, the timer's without
  Stub.Reset()
  ns = Start({ interface = ERA, auto = { rest = true, timer = true, minutes = 10 } })
  local warn = Warning(ns)
  Stub.SetResting(true)
  Stub.Advance(ns.Tracker.loadStartG + 600 - Stub.Now() + 60)
  T.eq(Count(warn), 0, "rest on: no countdown in the inn")
  ns.Core.SetSetting("autoReload.rest", false)
  Stub.Advance(2)
  T.eq(Count(warn), 1, "rest off: the timer's countdown in the inn")
  Stub.Advance(ns.C.AUTORELOAD_WARN)
  T.eq(Stub.ui.reloads, 1)
end)

---------------------------------------------------------------------------
-- A blocked reload
---------------------------------------------------------------------------

T.test("autoreload: ADDON_ACTION_BLOCKED for this addon switches to the prompt; ReloadUI() never again without a click", function()
  local ns = Start({ interface = ERA, auto = { rest = true } })
  local C, L = ns.C, ns.L
  local calls = 0
  rawset(_G, "ReloadUI", function()
    calls = calls + 1
    Stub.Fire("ADDON_ACTION_BLOCKED", "TruePlayed", "UNKNOWN()")
  end)
  -- another addon's block changes nothing
  Stub.Fire("ADDON_ACTION_BLOCKED", "SomeOtherAddon", "UNKNOWN()")
  T.ok(ns.AutoReload.IsDirect())
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE + 1 + C.AUTORELOAD_WARN)
  T.eq(calls, 1, "one call, blocked")
  T.no(ns.AutoReload.IsDirect(), "the prompt from now on")
  Stub.Advance(1)
  local f = Prompt(ns)
  T.ok(f ~= nil, "asked at once with the prompt")
  T.eq(Count(L.RELOAD_BY_HAND), 0, "the automatic call's block: no hint, the prompt asks")
  -- "Reload now": ReloadUI() inside the click; blocked too here, so the chat says /reload
  Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
  T.eq(calls, 2, "the click calls ReloadUI()")
  T.eq(Count(L.RELOAD_BY_HAND), 1, "blocked click: type /reload")
  Stub.RunScript(f.tp.later, "OnClick", "LeftButton")
  Stub.Advance(3 * C.AUTORELOAD_SNOOZE)
  T.eq(calls, 2, "never again without a click")
  -- the options' Reload UI button stays a plain ReloadUI() on click (no hint of its own)
  ns.Options.Open()
  local rec = Controls()["language.reload"]
  T.eq(ChildFrames(rec.widget), 0, "nothing on top of it")
  Stub.RunScript(rec.widget, "OnClick", "LeftButton")
  T.eq(calls, 3, "its click calls ReloadUI()")
  T.eq(Count(L.RELOAD_BY_HAND), 1)
end)

T.test("autoreload: ADDON_ACTION_FORBIDDEN, or a ReloadUI() that does nothing, also switches to the prompt", function()
  local ns = Start({ interface = ERA, auto = { rest = true } })
  local C = ns.C
  local calls = 0
  rawset(_G, "ReloadUI", function()
    calls = calls + 1
    Stub.Fire("ADDON_ACTION_FORBIDDEN", "TruePlayed", "ReloadUI()")
  end)
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE + 2 + C.AUTORELOAD_WARN)
  T.eq(calls, 1)
  T.ok(Prompt(ns) ~= nil, "forbidden: the prompt")
  -- silently ignored: still running C.AUTORELOAD_RETRY s later
  Stub.Reset()
  ns = Start({ interface = ERA, auto = { rest = true } })
  calls = 0
  rawset(_G, "ReloadUI", function() calls = calls + 1 end)
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  Stub.SetMap(ORGRIMMAR)
  Stub.Advance(C.AUTORELOAD_SETTLE + 1 + C.AUTORELOAD_WARN)
  T.eq(calls, 1)
  T.eq(Prompt(ns), nil, "not at once")
  Stub.Advance(C.AUTORELOAD_RETRY + 1)
  T.no(ns.AutoReload.IsDirect(), "no reload happened: not direct")
  local f = Prompt(ns)
  T.ok(f ~= nil, "the prompt")
  Stub.Advance(3600)
  T.eq(calls, 1, "never called again")
  -- "Reload now" silently ignored too (no event): the chat says /reload once, a few
  -- seconds later (the UI still running)
  local L = ns.L
  T.eq(Count(L.RELOAD_BY_HAND), 0)
  Stub.RunScript(f.tp.now, "OnClick", "LeftButton")
  T.eq(calls, 2, "the click calls ReloadUI()")
  Stub.Advance(C.AUTORELOAD_RETRY - 1)
  T.eq(Count(L.RELOAD_BY_HAND), 0, "not before C.AUTORELOAD_RETRY s")
  Stub.Advance(2)
  T.eq(Count(L.RELOAD_BY_HAND), 1, "ignored click: type /reload")
  Stub.Advance(60)
  T.eq(Count(L.RELOAD_BY_HAND), 1, "said once")
end)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

-- The help icon of a checkbox: after its label (stub GetStringWidth: 6 px a character),
-- dim, a tooltip with the label as a white title and gold wrapped lines, accent on hover.
local function CheckHelp(ns, check, help, lines, what)
  local ui = ns.Themes.Active().ui
  local f, icon = help.widget, help.icon
  T.ok(f:IsMouseEnabled(), what .. ": takes the mouse")
  T.match(icon:GetTexture(), "\\Media\\Themes\\common\\help%.tga$", what .. ": the addon's help icon")
  T.eq(icon:GetTexture(), ns.C.TEX_HELP)
  local p = rawget(f, "_points")[1]
  T.ok(p.rel == check.label and p.point == "LEFT" and p.relPoint == "LEFT", what .. ": after the label")
  local label = check.label:GetText()
  T.eq(p.x + 2, 6 * #label + 4, what .. ": the icon right after the text")
  T.eq(check.helpRoom, 18, what .. ": room left for the icon")
  T.eq(VColor(icon), C3(ui.dim), what .. ": dim")
  f:GetScript("OnEnter")(f)
  T.ok(GameTooltip:GetOwner() == f and GameTooltip:IsShown(), what .. ": tooltip")
  local got = GameTooltip._lines
  T.eq(#got, #lines + 1, what .. ": title and lines")
  T.eq(got[1][1], label, what .. ": the label as title")
  T.eq(GameTooltip._colors[1], { 1, 1, 1 }, what .. ": white title")
  for i, text in ipairs(lines) do
    T.eq(got[i + 1][1], text, what .. ": line " .. i)
    T.eq(GameTooltip._colors[i + 1], { 1, 0.82, 0 }, what .. ": gold")
  end
  T.eq(VColor(icon), C3(ui.accent), what .. ": accent while hovered")
  f:GetScript("OnLeave")(f)
  T.no(GameTooltip:IsShown(), what .. ": hidden")
  T.eq(VColor(icon), C3(ui.dim), what .. ": dim again")
end

local function TopY(widget)
  local _, _, _, _, y = widget:GetPoint(1)
  return y
end

local function FindRegion(text)
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_text") == text then return o end
  end
  return nil
end

T.test("autoreload: the options section (after Calculation), its help icons and tooltips, the interval slider", function()
  local ns = Start()
  local L, C = ns.L, ns.C
  ns.Options.Open()
  local controls = Controls()
  local rest, timer, mins = controls["autoReload.rest"], controls["autoReload.timer"], controls["autoReload.minutes"]
  local hRest, hTimer = controls["help.rest"], controls["help.timer"]
  T.ok(rest and rest.kind == "check" and timer and timer.kind == "check", "two checkboxes")
  T.ok(mins and mins.kind == "slider", "the interval slider")
  T.ok(hRest and hRest.kind == "help" and hTimer and hTimer.kind == "help", "two help records")
  T.eq(rest.label:GetText(), L.OPT_AUTORELOAD_REST)
  T.eq(timer.label:GetText(), L.OPT_AUTORELOAD_TIMER)
  T.eq(mins.label:GetText(), L.OPT_AUTORELOAD_MINUTES)
  -- order: Calculation, then this section, then Cities
  local hide = controls.hidePlayedMsg
  T.eq({ rest.index, hRest.index, timer.index, hTimer.index, mins.index },
       { hide.index + 1, hide.index + 2, hide.index + 3, hide.index + 4, hide.index + 5 })
  local header, cities = FindRegion(L.OPT_AUTORELOAD), FindRegion(L.OPT_CITIES)
  T.ok(header ~= nil and rawget(header, "_fontObject") == "GameFontNormal", "section header")
  T.ok(TopY(hide.widget) > TopY(header) and TopY(header) > TopY(rest.widget), "after Calculation")
  T.ok(TopY(mins.widget) > TopY(cities), "before Cities")
  -- Forever: no chat countdown there and no reload without a click, in town too (the
  -- "how" of the prompt for both options); both tooltips end with the line about the click
  local why = L.OPT_AUTORELOAD_REST_WHY
  local ask = format(L.OPT_AUTORELOAD_REST_ASK_FMT, 60)   -- an hour of unsaved play
  local task = format(L.OPT_AUTORELOAD_TIMER_ASK_FMT, 30, 10)
  CheckHelp(ns, rest, hRest, { why, ask, L.OPT_AUTORELOAD_CLICK }, "rest")
  T.no(find(ask, format("%d", C.AUTORELOAD_WARN), 1, true), "no warning seconds on Forever")
  -- the timer's: its "how", then the capitals and inns it leaves to the rest option
  CheckHelp(ns, timer, hTimer, { task, L.OPT_AUTORELOAD_TIMER_REST, L.OPT_AUTORELOAD_CLICK }, "timer")
  T.ok(L.OPT_AUTORELOAD_TIMER_ASK_FMT ~= L.OPT_AUTORELOAD_TIMER_HOW_FMT, "its own text on Forever")
  -- the slider: minutes, 10 to 120 by 5, greyed out while the timer is off
  T.eq({ mins.min, mins.max, mins.step }, { 10, 120, 5 })
  T.eq(mins.formatter(45), "45 min")
  T.eq(rawget(mins.widget, "_enabled"), false, "greyed out: timer off")
  T.eq({ mins.label:GetTextColor() }, C3(C.COLORS.dim))
  Stub.RunScript(timer.widget, "OnClick", "LeftButton")
  T.eq(ns.settings.autoReload.timer, true)
  T.eq(rawget(mins.widget, "_enabled"), true, "enabled with the timer")
  T.eq({ mins.label:GetTextColor() }, C3(C.COLORS.value))
  mins.widget:SetValue(45)
  T.eq(ns.settings.autoReload.minutes, 45)
  T.ok(State(ns).armed, "the checkbox armed it")
  -- the timer tooltip follows the interval
  hTimer.widget:GetScript("OnEnter")(hTimer.widget)
  T.eq(GameTooltip._lines[2][1], format(L.OPT_AUTORELOAD_TIMER_ASK_FMT, 45, 10))
  hTimer.widget:GetScript("OnLeave")(hTimer.widget)
  Stub.RunScript(rest.widget, "OnClick", "LeftButton")
  T.eq(ns.settings.autoReload.rest, true)
  -- a theme change recolours the icons (the same textures)
  local icon = hRest.icon
  ns.Core.SetSetting("theme", "pixel")
  T.ok(Controls()["help.rest"].icon == icon, "the same icon")
  T.eq(VColor(icon), C3(ns.Themes.Active().ui.dim), "the new theme's dim")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("autoreload: on a direct client the tooltips have no click line, the fallback slider greys out too", function()
  local ns = Start({ interface = ERA, ui = { modern = false } })
  local L = ns.L
  ns.Options.Open()
  local controls = Controls()
  CheckHelp(ns, controls["autoReload.rest"], controls["help.rest"],
    { L.OPT_AUTORELOAD_REST_WHY, format(L.OPT_AUTORELOAD_REST_HOW_FMT, 60, 5) }, "rest")
  CheckHelp(ns, controls["autoReload.timer"], controls["help.timer"],
    { format(L.OPT_AUTORELOAD_TIMER_HOW_FMT, 30, 10), L.OPT_AUTORELOAD_TIMER_REST }, "timer")
  local mins = controls["autoReload.minutes"]
  T.no(mins.modern)
  T.eq(rawget(mins.widget, "_enabled"), false, "fallback slider disabled")
  T.eq(rawget(mins.valueText, "_text"), "30 min")
  ns.Core.SetSetting("autoReload.timer", true)
  T.eq(rawget(mins.widget, "_enabled"), true)
  -- the options' Reload UI button: its click is ReloadUI()
  local reload = controls["language.reload"]
  T.eq(ChildFrames(reload.widget), 0, "a plain button")
  Stub.RunScript(reload.widget, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1)
end)

T.test("autoreload: the options' Reload UI button on WoW Forever: a plain ReloadUI() on click, built in combat too", function()
  -- the panel built during combat (Settings opened): the same plain button, nothing
  -- attached later, one ReloadUI() per click
  local ns = Start({ ui = { modern = true } })
  Stub.combat = true
  Stub.ui.categories[1].frame:Show()
  Stub.combat = false
  local rec = Controls()["language.reload"]
  T.eq(rec.overlay, nil)
  T.eq(ChildFrames(rec.widget), 0, "a plain button")
  local n = #Stub.printed
  Stub.RunScript(rec.widget, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1, "ReloadUI() inside the click")
  T.eq(#Stub.printed, n, "nothing said")
  ns.Options.Refresh()
  T.eq(ChildFrames(rec.widget), 0, "a refresh attaches nothing")
  T.eq(Stub.ui.reloads, 1, "a refresh does not reload")
  T.eq(Stub.errors, {})
end)

---------------------------------------------------------------------------
-- Cost
---------------------------------------------------------------------------

T.test("autoreload: zero garbage per tick while armed (before due, waiting in town, blocked, timer left to rest mode, prompt shown)", function()
  local hidden = { widget = { shown = false } }
  local ns = Start({ interface = ERA, map = ORGRIMMAR, settings = hidden,
                     auto = { rest = true, timer = true, minutes = 120 } })
  Stub.Advance(60)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks before due allocated %.2f KB"):format(kb))
  -- rest mode due, in town without an arrival: decided every tick, nothing to do
  Stub.Advance(ns.C.AUTORELOAD_REST_MIN)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks waiting for an arrival allocated %.2f KB"):format(kb))
  T.ok(State(ns).armed)
  -- due, a Blizzard popup open: the checks every C.AUTORELOAD_RETRY s
  Stub.busy.popup = true
  Stub.SetMap(DUROTAR); Stub.Advance(20); Stub.SetMap(ORGRIMMAR); Stub.Advance(20)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 blocked ticks allocated %.2f KB"):format(kb))
  T.eq(Count(Warning(ns)), 0)
  -- both on, the timer due in town before the rest mode's hour: left to it, every tick
  Stub.Reset()
  ns = Start({ interface = ERA, map = ORGRIMMAR, settings = hidden, auto = { rest = true, timer = true, minutes = 10 } })
  Stub.Advance(620)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks with the timer due in town allocated %.2f KB"):format(kb))
  T.eq(Count(Warning(ns)), 0)
  T.eq(ns.AutoReload.GetPrompt(), nil)
  -- Forever: the prompt shown
  Stub.Reset()
  ns = Start({ map = DUROTAR, settings = hidden, auto = { timer = true, minutes = 10 } })
  Stub.Advance(620)
  T.ok(Prompt(ns) ~= nil)
  kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks with the prompt shown allocated %.2f KB"):format(kb))
  T.eq(Stub.onUpdateCount, 0)
end)
