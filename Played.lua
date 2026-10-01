local ADDON, ns = ...
-- Played.lua - the ONLY owner of /played scheduling (SPEC 5.12, 5.13).
-- Listens passively to every TIME_PLAYED_MSG (whoever asked) and forwards it to
-- Tracker.ReconcileServer. Requests are one-shot (login, level-up, manual,
-- reset), never on a repeating timer. The experimental hide of our own output
-- is default OFF and touches nothing while it is off.

local L, C, Util = ns.L, ns.C, ns.Util

local type, pcall = type, pcall
local GetTime = GetTime
local C_Timer = C_Timer
-- RequestTimePlayed and ChatFrameUtil are NEVER cached (SPEC 2.4): other addons
-- wrap them and we hook them.

local Played = {}
ns.Played = Played

local lastRequestG      -- GetTime of our last request
local pendingReason     -- reason of our request awaiting its answer
local lastMsgG          -- GetTime of the last TIME_PLAYED_MSG (any origin)
local levelUpG          -- GetTime of the last LEVEL_UP message
local loginCheckScheduled = false

-- experimental hide state (5.13)
local selfCall = false        -- true only while we call RequestTimePlayed
local pendingOwn = false      -- our own answer is expected: swallow its display
local hookInstalled = false   -- hooksecurefunc("RequestTimePlayed") done (once)
local lastForeignG            -- GetTime of the last request we did not make
local origDisplay             -- ChatFrameUtil.DisplayTimePlayed we wrapped
local wrapperInChain = false  -- our wrapper is (still) in the call chain
local hideDeadline = 0

---------------------------------------------------------------------------
-- Experimental hide of OUR OWN /played output
---------------------------------------------------------------------------

local function Wrapper(...)
  if pendingOwn then return end
  local f = origDisplay
  if f then return f(...) end
end

local function ClearPending()
  pendingOwn = false
  local cfu = ChatFrameUtil
  if wrapperInChain and type(cfu) == "table" and cfu.DisplayTimePlayed == Wrapper then
    cfu.DisplayTimePlayed = origDisplay
    wrapperInChain = false
    origDisplay = nil
  end
  -- otherwise someone wrapped on top of us: stay in the chain, pass-through
end

-- Safety timeout: only clears when the latest request's deadline has passed.
local function TimeoutClear()
  if GetTime() >= hideDeadline - 0.001 then ClearPending() end
end

-- Post-hook of RequestTimePlayed: a request we did not make (user /played,
-- another addon) is never hidden. It runs at request time, outside any
-- display dispatch, so the wrapper can be removed right away.
local function OnAnyRequest()
  if selfCall then return end
  lastForeignG = GetTime()
  ClearPending()
end

function Played.CanHide()
  return type(ChatFrameUtil) == "table" and type(ChatFrameUtil.DisplayTimePlayed) == "function"
end

local function HideWanted()
  local s = ns.settings
  return s ~= nil and s.hidePlayedMsg == true and Played.CanHide()
end

local function InstallHook()
  if hookInstalled then return end
  if type(hooksecurefunc) ~= "function" or type(RequestTimePlayed) ~= "function" then return end
  hookInstalled = true
  hooksecurefunc("RequestTimePlayed", OnAnyRequest)
end

-- Installs the hook as soon as the option is on, so that a foreign request made
-- before our first one is known.
local function CheckHook()
  if HideWanted() then InstallHook() end
end

local function PrepareHide(now)
  InstallHook()
  if lastForeignG and now - lastForeignG < C.PLAYED_FOREIGN_WINDOW then return end
  local cfu = ChatFrameUtil
  if not wrapperInChain then
    local cur = cfu.DisplayTimePlayed
    if cur == Wrapper then
      wrapperInChain = true
    else
      origDisplay = cur
      cfu.DisplayTimePlayed = Wrapper
      wrapperInChain = true
    end
  end
  pendingOwn = true
  hideDeadline = now + C.PLAYED_HIDE_TIMEOUT
  C_Timer.After(C.PLAYED_HIDE_TIMEOUT, TimeoutClear)
end

---------------------------------------------------------------------------
-- Requests (5.12)
---------------------------------------------------------------------------

-- reason: "login", "levelup" (automatic), "manual", "reset". Returns true when
-- a request was sent.
function Played.Request(reason)
  local now = GetTime()
  local manual = reason == "manual" or reason == "reset"
  if lastRequestG then
    local minGap = manual and C.PLAYED_MANUAL_MIN or C.PLAYED_MIN_INTERVAL
    if now - lastRequestG < minGap then
      if reason == "manual" then Util.Print(L.SYNC_THROTTLED) end
      return false
    end
  end
  if type(RequestTimePlayed) ~= "function" then return false end
  if reason == "manual" then Util.Print(L.SYNC_REQUESTED) end
  if HideWanted() then PrepareHide(now) end
  selfCall = true
  local ok, err = pcall(RequestTimePlayed)
  selfCall = false
  if not ok then
    pendingOwn = false
    local handler = geterrorhandler and geterrorhandler()
    if handler then handler(err) end
    return false
  end
  lastRequestG = now
  pendingReason = reason
  return true
end

-- Our request awaits its answer (given up after C.PLAYED_MIN_INTERVAL).
function Played.IsPending()
  if pendingReason == nil then return false end
  if lastRequestG and GetTime() - lastRequestG > C.PLAYED_MIN_INTERVAL then
    pendingReason = nil
    return false
  end
  return true
end

function Played.GetLastMessageG()
  return lastMsgG
end

-- GetTime of our last request (used by the Tracker's level race check).
function Played.GetLastRequestG()
  return lastRequestG
end

---------------------------------------------------------------------------
-- Events and messages
---------------------------------------------------------------------------

local function OnTimePlayed(_, total, levelPlayed)
  lastMsgG = GetTime()
  local T = ns.Tracker
  if T and T.ReconcileServer then ns.SafeCall(T.ReconcileServer, total, levelPlayed) end
  if pendingReason == "manual" then Util.Print(L.SYNCED) end
  pendingReason = nil
  -- restore after the current event dispatch, so every chat frame showing this
  -- event went through the wrapper
  if pendingOwn or wrapperInChain then C_Timer.After(0, ClearPending) end
end

local function LoginCheck()
  loginCheckScheduled = false
  if lastMsgG then return end   -- someone (RXPGuides, the user) already asked
  Played.Request("login")
end

local function OnEnteringWorld(_, isInitialLogin, isReloadingUi)
  if not (isInitialLogin or isReloadingUi) then return end
  local T = ns.Tracker
  if T and T.GetSync and T.GetSync() then return end   -- restored after a /reload
  local s = ns.settings
  if not (s and s.requestPlayedAtLogin) then return end
  if loginCheckScheduled then return end
  loginCheckScheduled = true
  C_Timer.After(C.PLAYED_LOGIN_WAIT, LoginCheck)
end

local function LevelCheck()
  local T = ns.Tracker
  local g = T and T.GetLastLevelSyncG and T.GetLastLevelSyncG()
  if type(g) ~= "number" then g = -1 end
  if levelUpG and g < levelUpG then Played.Request("levelup") end
end

local function OnLevelUp()
  levelUpG = GetTime()
  C_Timer.After(C.PLAYED_LEVELUP_WAIT, LevelCheck)
end

local function OnSettingsChanged(_, path)
  if path == "hidePlayedMsg" then CheckHook() end
end

function Played.Init()
  ns.RegisterEvent("PLAYER_ENTERING_WORLD", Played, OnEnteringWorld)
  ns.RegisterEvent("TIME_PLAYED_MSG", Played, OnTimePlayed)
  ns.RegisterMessage("LEVEL_UP", Played, OnLevelUp)
  ns.RegisterMessage("SETTINGS_CHANGED", Played, OnSettingsChanged)
  ns.RegisterMessage("DB_SWAPPED", Played, CheckHook)
  CheckHook()
end
