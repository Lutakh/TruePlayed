local ADDON, ns = ...
-- AutoReload.lua - optional automatic reload of the interface (settings autoReload.*, both
-- off by default). The game writes addon data (SavedVariables) only at logout or /reload:
-- a crash loses everything since the last load, which the Tracker then rebuilds from the
-- server /played as an estimate. Reloading at quiet moments keeps that loss small.
--   * rest mode (autoReload.rest): in a capital or an inn (state key in C.IS_CITY or
--     C.IS_INN: never professions, dead, a flight or an instance), once
--     C.AUTORELOAD_REST_MIN seconds are unsaved and the player has stood there
--     C.AUTORELOAD_SETTLE seconds; only after an arrival: C.AUTORELOAD_SETTLE seconds in a
--     row outside (the open world, an instance, a flight; not crafting, not dead) since
--     this load, so a player who stays in town (AFK for hours) is not reloaded again and
--     again;
--   * timer mode (autoReload.timer): once autoReload.minutes are unsaved; outside a capital
--     or an inn a prompt asks first; in a capital or an inn it acts as above (no arrival
--     needed) only while the rest mode is off: with both on, the timer leaves capitals and
--     inns to the rest mode (its arrival and C.AUTORELOAD_REST_MIN; no double trigger
--     there): a timer due in town waits until the player is out of it, and a prompt it
--     showed outside hides when the player enters one where the rest mode is not due
--     (asked again once out); never in an instance, on a flight, dead, during professions
--     (which hide the place) or in combat (it waits).
-- Unsaved = GetTime() - Tracker.loadStartG (this load started at the last save).
-- Two ways to reload:
--   * direct (every client but WoW Forever): a chat warning C.AUTORELOAD_WARN seconds
--     before, every check again on each of those ticks (moving, combat, a window, typing
--     cancel it: asked again C.AUTORELOAD_SNOOZE later), then ReloadUI(), at most once per
--     load;
--   * prompt (WoW Forever, which allows ReloadUI() from addon code only inside the
--     player's click - measured in game: a button's OnClick reloads, a timer does not -
--     and any client once ADDON_ACTION_BLOCKED / _FORBIDDEN named this addon): the
--     addon's own small frame, top centre, "Reload now" / "Later" ("Later": asked again
--     C.AUTORELOAD_SNOOZE later). "Reload now" is a plain button whose OnClick calls
--     ReloadUI(); there nothing ever reloads without that click (should the game refuse
--     the click's call, with ADDON_ACTION_BLOCKED or silently, the chat says to type
--     /reload). The prompt is not shown in combat and hides at PLAYER_REGEN_DISABLED (no
--     moment to ask, and a stray click would reload mid-fight), then asks again
--     C.AUTORELOAD_RETRY seconds after. A shown prompt is watched on each tick: hidden in
--     an instance, on a flight or dead (asked again later), and its "Reload now" waits,
--     greyed and disabled, while the addon's own data is not ready (an XP gain, a
--     level-up or a /played answer still being read; the click checks again).
-- Safety (AutoReload.Blocker, cheapest first, evaluated only at the due moment; a failed
-- check waits C.AUTORELOAD_RETRY seconds): ready and not read-only, TruePlayedDB adopted
-- (FOREVER-2), WTFix not protecting the addon (Core.IsWTFixProtected), no reconcile or gap
-- XP pending, no /played request pending, a server sync, the XP reading settled
-- (Tracker.IsSettled), the load and the last level-up old enough, then the game: combat,
-- dead, casting, typing, a Blizzard popup or panel (the game menu and options included), a
-- cinematic, a ready check, something on the cursor; the direct path also needs the
-- statistics window and the options closed.
-- Every global of the game is type-checked (some clients lack some of them).
-- Cost: armed (TICK subscription) only while an option is on, never in read-only mode.
-- A tick reads the state key (Tracker.GetState) and compares a few numbers; the checks
-- run at the due moment only (their data part on each tick of a shown prompt); nothing is
-- allocated per tick. No OnUpdate, no timer.

local L, C, Util, Fmt = ns.L, ns.C, ns.Util, ns.Fmt

local type, tonumber = type, tonumber
local math_floor, math_max, math_huge = math.floor, math.max, math.huge
local string_format = string.format
local GetTime, CreateFrame, UIParent = GetTime, CreateFrame, UIParent
local InCombatLockdown = InCombatLockdown

local IS_CITY, IS_INN, IS_INSTANCE, IS_ACTIVITY = C.IS_CITY, C.IS_INN, C.IS_INSTANCE, C.IS_ACTIVITY
local IS_TAXI = { t = true, T = true }
local Tracker = ns.Tracker

local AutoReload = {}
ns.AutoReload = AutoReload

local PANEL_AREAS = { "left", "center", "right", "doublewide", "fullscreen" }
local ACT, ASK = 1, 2                  -- what is due: act (direct or prompt), ask (prompt)
local PROMPT_W, TEXT_W, BTN_H, BTN_MIN_W = 340, 310, 22, 100
local BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local BTN_BACKDROP = { bgFile = C.TEX_WHITE, edgeFile = C.TEX_WHITE, edgeSize = 1 }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local armed = false
local restOn, timerOn, minutes = false, false, 30
local direct = not ns.isForever       -- ReloadUI() works here without the player's click
local autoCalled = false              -- the automatic path called ReloadUI() in this load
local clickG = nil                    -- GetTime of the last "Reload now" click's ReloadUI()
local dueG = math_huge                -- nothing can be due before this (unsaved thresholds)
local waitUntil = 0                   -- no check before this ("Later", a failed check)
local restSince, outsideSince = nil, nil   -- GetTime the current rest / outside stretch began
local arrived = false                 -- C.AUTORELOAD_SETTLE s in a row outside since this load
local countdownEnd = nil              -- direct path: ReloadUI() at this GetTime
local prompt, promptShown = nil, false
local nowReady = true                 -- the prompt's "Reload now" acts (else greyed, waiting)

---------------------------------------------------------------------------
-- Game state (globals read at call time, each one type-checked)
---------------------------------------------------------------------------

local function Shown(f)
  return type(f) == "table" and type(f.IsShown) == "function" and f:IsShown() and true or false
end

local function Moving()
  local f = IsPlayerMoving
  if type(f) == "function" then return f() and true or false end
  f = GetUnitSpeed
  if type(f) == "function" then
    local speed = f("player")
    return type(speed) == "number" and speed > 0
  end
  return false
end

-- The rest mode's own rule is met: an arrival since this load, C.AUTORELOAD_REST_MIN s
-- unsaved (in a capital or an inn: the caller checks the place).
local function RestDue(unsaved)
  return restOn and arrived and unsaved >= C.AUTORELOAD_REST_MIN
end

-- In an instance, on a flight or dead: no prompt there, and a shown one hides. Professions
-- ("f") hide the place in the state key: then the game says whether this is an instance.
local function Away(key)
  if IS_INSTANCE[key] or IS_TAXI[key] or key == "x" then return true end
  if key == "f" then
    local f = IsInInstance
    return type(f) == "function" and f() and true or false
  end
  return false
end

-- Why the addon's own data forbids a reload now (a constant string), or nil: what a
-- reload would lose or roll back (also checked on each tick of a shown prompt).
local function DataBlocker(now)
  if not ns.ready then return "ready" end
  if ns.readOnly then return "readonly" end
  if TruePlayedDB ~= ns.db then return "db" end
  local Core, Played = ns.Core, ns.Played
  if Core.IsWTFixProtected() then return "wtfix" end
  if Tracker.pendingReconcile or Tracker.gapXPPending then return "reconcile" end
  if Played and Played.IsPending() then return "played" end
  if not Tracker.GetSync() then return "sync" end
  if not Tracker.IsSettled() then return "xp" end
  local start = Tracker.loadStartG
  if type(start) ~= "number" or now - start < C.AUTORELOAD_LOAD_MIN then return "load" end
  local lu = Tracker.GetLevelUpG()
  if type(lu) == "number" and now - lu < C.AUTORELOAD_LEVELUP_WAIT then return "levelup" end
  return nil
end

-- Why nothing may happen now (a constant string), or nil. forDirect: a reload without a
-- click (the addon's own windows must be closed too). Cheapest first.
function AutoReload.Blocker(forDirect, now)
  now = now or GetTime()
  local why = DataBlocker(now)
  if why then return why end
  if InCombatLockdown() then return "combat" end
  local f = UnitAffectingCombat
  if type(f) == "function" and f("player") then return "combat" end
  f = UnitIsDeadOrGhost
  if type(f) == "function" and f("player") then return "dead" end
  f = UnitCastingInfo
  if type(f) == "function" and f("player") then return "cast" end
  f = UnitChannelInfo
  if type(f) == "function" and f("player") then return "cast" end
  f = GetCurrentKeyBoardFocus
  if type(f) == "function" and f() then return "typing" end
  f = StaticPopup_IsAnyDialogShown
  if type(f) == "function" and f() then return "popup" end
  f = GetUIPanel
  if type(f) == "function" then
    for i = 1, #PANEL_AREAS do
      if f(PANEL_AREAS[i]) then return "panel" end
    end
  end
  -- the game's menu and options (key bindings, graphics to apply...): no UI panel area,
  -- GetUIPanel never returns them (InterfaceOptionsFrame: clients before SettingsPanel)
  if Shown(SettingsPanel) or Shown(GameMenuFrame) or Shown(KeyBindingFrame) or Shown(InterfaceOptionsFrame) then
    return "panel"
  end
  f = InCinematic
  if (type(f) == "function" and f()) or Shown(MovieFrame) then return "cinematic" end
  if Shown(ReadyCheckFrame) then return "readycheck" end
  f = CursorHasItem
  if type(f) == "function" and f() then return "cursor" end
  f = SpellIsTargeting
  if type(f) == "function" and f() then return "cursor" end
  if forDirect then
    local Window, Options = ns.Window, ns.Options
    if (Window and Window.IsShown and Window.IsShown()) or (Options and Options.IsShown and Options.IsShown()) then
      return "window"
    end
  end
  return nil
end

---------------------------------------------------------------------------
-- Reload: without a click (the automatic path) or inside the player's click
---------------------------------------------------------------------------

-- ReloadUI() without a click: never on a client that refuses it (WoW Forever, a block).
local function CallReload()
  local f = ReloadUI
  if not direct or type(f) ~= "function" then return false end
  f()
  return true
end

-- ReloadUI() inside the player's click ("Reload now"): every client allows it. Should the
-- game still block it (ADDON_ACTION_BLOCKED right after: OnBlocked), ignore it (still
-- running C.AUTORELOAD_RETRY s later: OnTick), or lack it, the chat says to type /reload.
local function ClickReload()
  local f = ReloadUI
  if type(f) ~= "function" then
    Util.Print(L.RELOAD_BY_HAND)
    return
  end
  clickG = GetTime()
  f()
end

-- The automatic path reloads without a click on this client (else it asks: the prompt).
function AutoReload.IsDirect()
  return direct
end

---------------------------------------------------------------------------
-- Prompt
---------------------------------------------------------------------------

local function ThemeUI()
  local Themes = ns.Themes
  local th = Themes and Themes.Active and Themes.Active()
  local ui = type(th) == "table" and th.ui
  if type(ui) == "table" then return ui end
  return nil
end

local function UIColor(ui, role)
  local c = ui and ui[role]
  if type(c) == "table" then return c end
  return C.COLORS[role] or C.COLORS.value
end

-- A flat button (the statistics window's look), sized to its text.
local function MakeButton(parent, text, onClick)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  if b.SetBackdrop then b:SetBackdrop(BTN_BACKDROP) end
  local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("CENTER", b, "CENTER", 0, 0)
  fs:SetText(text)
  local w = fs:GetStringWidth()
  if type(w) ~= "number" then w = 0 end
  b:SetSize(math_floor(w + 24 > BTN_MIN_W and w + 24 or BTN_MIN_W), BTN_H)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetTexture(C.TEX_WHITE)
  hl:SetVertexColor(1, 1, 1, 0.08)
  b:SetScript("OnClick", onClick)
  b.tpText = fs
  return b
end

local function HidePrompt()
  if not promptShown then return end
  promptShown = false
  prompt:Hide()
  ns.UnregisterEvent("PLAYER_REGEN_DISABLED", AutoReload)
end

local function OnLaterClick()
  HidePrompt()
  waitUntil = GetTime() + C.AUTORELOAD_SNOOZE
end

-- "Reload now" acts out of a pending reading only: the tick greys it, and the click checks
-- again (an XP gain read since the last tick).
local SetNowReady
local function OnNowClick()
  if not nowReady then return end
  if DataBlocker(GetTime()) then
    SetNowReady(false)
    return
  end
  ClickReload()
end

-- A fight is no moment to ask, and a stray click would reload in the middle of it: hidden
-- at once, asked again shortly after.
local function OnCombatStart()
  HidePrompt()
  waitUntil = GetTime() + C.AUTORELOAD_RETRY
end

local function BuildPrompt()
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:Hide()
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetPoint("TOP", UIParent, "TOP", 0, -140)
  if f.SetBackdrop then f:SetBackdrop(BACKDROP) end
  local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  title:SetPoint("TOP", f, "TOP", 0, -12)
  title:SetText(L.ADDON_TITLE)
  local text = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOP", title, "BOTTOM", 0, -8)
  text:SetWidth(TEXT_W)
  text:SetJustifyH("CENTER")
  local now = MakeButton(f, L.RELOAD_NOW, OnNowClick)
  local later = MakeButton(f, L.RELOAD_LATER, OnLaterClick)
  now:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 12)
  later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 12)
  local w = 2 * math_max(now:GetWidth(), later:GetWidth()) + 40
  f:SetWidth(w > PROMPT_W and w or PROMPT_W)
  -- read-only handles for the offline tests (our own frame)
  f.tp = { title = title, text = text, now = now, later = later }
  prompt = f
  return f
end

local function StyleButton(b, track, border, text)
  if b.SetBackdrop then
    b:SetBackdropColor(track[1], track[2], track[3], 1)
    b:SetBackdropBorderColor(border[1], border[2], border[3], C.COLORS.border[4])
  end
  b.tpText:SetTextColor(text[1], text[2], text[3])
end

-- Theme colours, read at each show (a prompt is rare): panel, title, text, buttons.
local function ApplyLook(f)
  local ui = ThemeUI()
  local tp = f.tp
  if f.SetBackdrop then
    local bg, bd = UIColor(ui, "bg"), UIColor(ui, "border")
    f:SetBackdropColor(bg[1], bg[2], bg[3], 0.95)
    f:SetBackdropBorderColor(bd[1], bd[2], bd[3], C.COLORS.border[4])
  end
  local ac, vc = UIColor(ui, "accent"), UIColor(ui, "value")
  tp.title:SetTextColor(ac[1], ac[2], ac[3])
  tp.text:SetTextColor(vc[1], vc[2], vc[3])
  local bd = UIColor(ui, "border")
  StyleButton(tp.now, C.COLORS.track, bd, vc)
  StyleButton(tp.later, C.COLORS.track, bd, vc)
end

-- "Reload now" acts (enabled, the text in the value colour) or waits (disabled, dim text;
-- its OnClick checks nowReady too).
function SetNowReady(on)
  if on == nowReady then return end
  nowReady = on
  local b = prompt.tp.now
  if on then b:Enable() else b:Disable() end
  local c = UIColor(ThemeUI(), on and "value" or "dim")
  b.tpText:SetTextColor(c[1], c[2], c[3])
end

local function ShowPrompt(unsaved)
  local f = prompt or BuildPrompt()
  ApplyLook(f)
  local tp = f.tp
  tp.text:SetText(string_format(L.RELOAD_PROMPT_FMT, Fmt.Duration(unsaved)))
  local h = tp.text:GetStringHeight()
  if type(h) ~= "number" or h <= 0 then h = 14 end
  f:SetHeight(math_floor(12 + 14 + 8 + h + 12 + BTN_H + 12 + 0.5))
  nowReady = true                       -- the checks just passed; ApplyLook gave the value colour
  tp.now:Enable()
  promptShown = true
  ns.RegisterEvent("PLAYER_REGEN_DISABLED", AutoReload, OnCombatStart)
  f:Show()
end

---------------------------------------------------------------------------
-- Countdown (direct path)
---------------------------------------------------------------------------

local function CancelCountdown(now, say)
  countdownEnd = nil
  waitUntil = now + C.AUTORELOAD_SNOOZE
  if say then Util.Print(L.RELOAD_CANCELLED) end
end

local function Countdown(now, key)
  if not (IS_CITY[key] or IS_INN[key]) or Moving() or AutoReload.Blocker(true, now) then
    CancelCountdown(now, true)
    return
  end
  if now < countdownEnd - 0.001 then return end
  countdownEnd = nil
  waitUntil = now + C.AUTORELOAD_RETRY
  if autoCalled then return end         -- never twice in one load
  autoCalled = true
  CallReload()
end

-- A shown prompt, on each tick: hidden once the player is in an instance, on a flight or
-- dead, or in a capital or an inn while the rest mode is on and not due (the timer's
-- prompt, shown outside: the timer leaves those places to the rest mode); asked again
-- C.AUTORELOAD_RETRY s later, out of there. "Reload now" waits while the addon still reads
-- an XP gain, a level-up or a /played answer (DataBlocker), greyed rather than hidden: an
-- XP gain out of combat (a quest, a discovery) does not make the prompt come and go (a
-- fight hides it anyway: OnCombatStart, and it comes back once that gain is read).
local function WatchPrompt(now, key)
  local restPlace = restOn and (IS_CITY[key] or IS_INN[key])
  if Away(key) or (restPlace and not RestDue(now - (Tracker.loadStartG or now))) then
    HidePrompt()
    waitUntil = now + C.AUTORELOAD_RETRY
    return
  end
  SetNowReady(DataBlocker(now) == nil)
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------

local function OnTick(_, now)
  if clickG and now - clickG >= C.AUTORELOAD_RETRY then
    -- still running C.AUTORELOAD_RETRY seconds after the click's ReloadUI(): refused
    -- without an event
    clickG = nil
    Util.Print(L.RELOAD_BY_HAND)
  end
  local key = Tracker.GetState()
  if IS_CITY[key] or IS_INN[key] then
    if not restSince then restSince = now end
    outsideSince = nil
  else
    restSince = nil
    if IS_ACTIVITY[key] then
      outsideSince = nil
    else
      if not outsideSince then outsideSince = now end
      if not arrived and now - outsideSince >= C.AUTORELOAD_SETTLE then arrived = true end
    end
  end
  if countdownEnd then
    Countdown(now, key)
    return
  end
  if promptShown then
    WatchPrompt(now, key)
    return
  end
  if now < dueG or now < waitUntil then return end
  if autoCalled then
    -- still running C.AUTORELOAD_RETRY seconds after ReloadUI(): the call did nothing
    -- (blocked without an event); the prompt from now on
    direct = false
  end

  local start = Tracker.loadStartG or now
  local unsaved = now - start
  local timerDue = timerOn and unsaved >= minutes * 60
  local want
  if restSince then
    -- a capital or an inn: the rest mode's rule; the timer only while the rest mode is off
    -- (else it leaves these places to it: it acts once the player is out of town)
    if not (RestDue(unsaved) or (timerDue and not restOn)) then return end
    if Moving() then
      restSince = now                   -- walking around town: settled once standing still
      return
    end
    if now - restSince < C.AUTORELOAD_SETTLE then return end
    want = ACT
  elseif timerDue and not (IS_INSTANCE[key] or IS_TAXI[key] or IS_ACTIVITY[key]) then
    -- dead or professions (which hide the place, an instance's too): wait for the end
    want = ASK
  end
  if not want then return end

  local toDirect = (want == ACT) and direct
  local why = AutoReload.Blocker(toDirect, now)
  if why then
    waitUntil = now + C.AUTORELOAD_RETRY
    Util.Debug("auto reload: waiting (%s)", why)
    return
  end
  if toDirect then
    countdownEnd = now + C.AUTORELOAD_WARN
    Util.Print(L.RELOAD_SOON_FMT, C.AUTORELOAD_WARN)
  else
    ShowPrompt(unsaved)
  end
end

---------------------------------------------------------------------------
-- Arming
---------------------------------------------------------------------------

local function Evaluate()
  local s = ns.settings
  local ar = type(s) == "table" and s.autoReload
  if type(ar) ~= "table" then ar = nil end
  restOn = ar ~= nil and ar.rest == true
  timerOn = ar ~= nil and ar.timer == true
  minutes = ar and tonumber(ar.minutes) or 30
  local want = ns.ready and not ns.readOnly and (restOn or timerOn)
  if want and not armed then
    armed = true
    ns.RegisterMessage("TICK", AutoReload, OnTick)
  elseif not want and armed then
    armed = false
    ns.UnregisterMessage("TICK", AutoReload)
    HidePrompt()
  end
  countdownEnd = nil                    -- re-decided at the next tick
  local start = Tracker.loadStartG or GetTime()
  local due = math_huge
  if restOn then due = start + C.AUTORELOAD_REST_MIN end
  if timerOn and start + minutes * 60 < due then due = start + minutes * 60 end
  dueG = due
end

-- ADDON_ACTION_BLOCKED / _FORBIDDEN naming this addon (a safety net): ReloadUI() without a
-- click does not work here. Never called that way again in this load; the automatic path
-- asks with the prompt from now on. Right after a "Reload now" click (its ReloadUI()
-- blocked too): the chat says to type /reload.
local function OnBlocked(_, addon)
  if addon ~= ns.ADDON then return end
  if clickG and GetTime() - clickG <= 1 then
    clickG = nil
    Util.Print(L.RELOAD_BY_HAND)
  end
  if not direct then return end
  direct = false
  countdownEnd = nil
  if autoCalled then waitUntil = 0 end  -- our own automatic call: ask at the next tick
end

local function OnSettingsChanged(_, path)
  if type(path) == "string" and path:find("autoReload.", 1, true) == 1 then Evaluate() end
end

-- Test and /tpl debug hook: armed, and the state the next tick starts from.
function AutoReload.GetState()
  return armed, direct, arrived, countdownEnd, promptShown, waitUntil, dueG
end

function AutoReload.GetPrompt()
  return prompt
end

function AutoReload.Init()
  ns.RegisterEvent("ADDON_ACTION_BLOCKED", AutoReload, OnBlocked)
  ns.RegisterEvent("ADDON_ACTION_FORBIDDEN", AutoReload, OnBlocked)
  ns.RegisterMessage("SETTINGS_CHANGED", AutoReload, OnSettingsChanged)
  ns.RegisterMessage("DB_SWAPPED", AutoReload, Evaluate)
  Evaluate()
end

ns.RegisterMessage("DB_READY", AutoReload, AutoReload.Init)
