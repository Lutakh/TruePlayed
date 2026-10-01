-- tests/test_played.lua - /played request policy, passive listening, level
-- race, manual sync and the experimental hide (SPEC 5.12 - 5.14, 9.4).
local Stub, T = ...

local floor = math.floor

local function Login(db)
  if db then _G.TruePlayedDB = db end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  return ns
end

local function NoLoginRequest(extra)
  local settings = { requestPlayedAtLogin = false }
  for k, v in pairs(extra or {}) do settings[k] = v end
  return { schema = 1, settings = settings }
end

-- Number of chat lines containing `text` (plain search).
local function Printed(text)
  local n = 0
  for _, line in ipairs(Stub.printed) do
    if line:find(text, 1, true) then n = n + 1 end
  end
  return n
end

local function ServerMessage()
  Stub.Fire("TIME_PLAYED_MSG", floor(Stub.server.total), floor(Stub.server.levelPlayed))
end

---------------------------------------------------------------------------
-- login / reload policy
---------------------------------------------------------------------------

T.test("login with nothing received: exactly one visible request at +10 s", function()
  local ns = Login()
  Stub.Advance(9.5)
  T.eq(Stub.requests, 0, "nothing before 10 s")
  Stub.Advance(1)
  T.eq(Stub.requests, 1, "one request at +10 s")
  Stub.Advance(1)
  T.eq(#Stub.displayed, 1, "the usual /played lines are visible")
  T.ok(ns.Tracker.GetSync(), "answer reconciled")
  T.ok(ns.Played.GetLastMessageG() ~= nil)
  Stub.Advance(120)
  T.eq(Stub.requests, 1, "never repeated")
end)

T.test("a message received first (another addon asked) means no request", function()
  local ns = Login()
  Stub.Advance(3)
  ServerMessage()                           -- e.g. RXPGuides asks at every PLAYER_ENTERING_WORLD
  T.ok(ns.Tracker.GetSync())
  Stub.Advance(20)
  T.eq(Stub.requests, 0)
end)

T.test("option off: no request at login", function()
  local ns = Login(NoLoginRequest())
  Stub.Advance(30)
  T.eq(Stub.requests, 0)
  T.eq(ns.Tracker.GetSync(), nil)
end)

T.test("reload with a restorable sync: no request; without one: a request", function()
  Login()
  Stub.Advance(20)
  T.eq(Stub.requests, 1)
  local ns = Stub.Restart({ reload = true, offline = 2 })
  Stub.Advance(20)
  T.eq(Stub.requests, 0, "restored sync: nothing asked")
  T.ok(ns.Tracker.GetSync())
  ns = Stub.Restart({ reload = true, offline = 400 })   -- too long ago to restore
  T.eq(ns.Tracker.GetSync(), nil)
  Stub.Advance(11)
  T.eq(Stub.requests, 1)
end)

---------------------------------------------------------------------------
-- level-up policy and the level race (critique #5)
---------------------------------------------------------------------------

T.test("level-up without a valid message within 5 s: request, level boundary exact", function()
  local ns = Login()
  Stub.Advance(40)
  T.eq(Stub.requests, 1)
  local levelUpTotal = floor(Stub.server.total)
  Stub.GrantXP(Stub.xpTable[10])            -- level 11
  Stub.Advance(4.5)
  T.eq(Stub.requests, 1)
  Stub.Advance(1)
  T.eq(Stub.requests, 2, "request 5 s after the level-up")
  Stub.Advance(1)
  local l10, l11 = ns.char.levels[10], ns.char.levels[11]
  T.near(l11.srvStart, levelUpTotal, 1, "srvStart from our own post-level-up answer")
  T.eq(l11.srvStartEst, nil)
  T.eq(l10.srvEnd, l11.srvStart)
  T.eq(l10.srvEndEst, nil)
  local sync = ns.Tracker.GetSync()
  T.ok(sync.levelValid and sync.level == 11)
end)

T.test("a stale message after a level-up: level part ignored, request still sent", function()
  local ns = Login()
  Stub.Advance(40)
  local oldLevelPlayed = floor(Stub.server.levelPlayed)
  Stub.GrantXP(Stub.xpTable[10])            -- level 11; server level time restarts at 0
  Stub.Advance(1)
  -- requested before the level-up, received after it: carries level 10's time
  Stub.Fire("TIME_PLAYED_MSG", floor(Stub.server.total), oldLevelPlayed + 1)
  local lb = ns.char.levels[11]
  T.eq(lb.s.u, nil, "no u added to the new level")
  T.ok(lb.srvStartEst, "srvStart still the local estimate")
  T.no(ns.Tracker.GetSync().levelValid)
  T.near(ns.char.life.s.u + ns.char.life.s.w, floor(Stub.server.total), 1, "the total part is still used")
  Stub.Advance(4.5)
  T.eq(Stub.requests, 2, "the level-up request still goes out")
  Stub.Advance(1)
  T.eq(lb.srvStartEst, nil, "fixed by the answer to our request")
end)

T.test("another addon's /played at the level-up is valid for the new level: no second request", function()
  local ns = Login()
  Stub.Advance(40)
  T.eq(Stub.requests, 1)
  local levelUpTotal = floor(Stub.server.total)
  Stub.GrantXP(Stub.xpTable[10])            -- level 11; server level time restarts at 0
  RequestTimePlayed()                       -- RXPGuides asks at PLAYER_LEVEL_UP
  Stub.Advance(1)
  local sync = ns.Tracker.GetSync()
  T.ok(sync.levelValid and sync.level == 11, "fresh level part accepted")
  local l10, l11 = ns.char.levels[10], ns.char.levels[11]
  T.near(l11.srvStart, levelUpTotal, 1)
  T.eq(l11.srvStartEst, nil)
  T.eq(l10.srvEnd, l11.srvStart)
  Stub.Advance(10)
  T.eq(Stub.requests, 2, "no visible request of ours on top of the other addon's")
end)

T.test("automatic requests keep 30 s apart", function()
  local ns = Login()
  Stub.Advance(12)
  T.eq(Stub.requests, 1)
  Stub.GrantXP(Stub.xpTable[10])            -- level-up 2 s after the login request
  Stub.Advance(10)
  T.eq(Stub.requests, 1, "level-up request refused (min interval)")
  T.no(ns.Played.Request("levelup"))
  T.no(ns.Played.Request("login"))
  Stub.Advance(20)
  T.ok(ns.Played.Request("login"), "allowed again after 30 s")
end)

---------------------------------------------------------------------------
-- manual sync
---------------------------------------------------------------------------

T.test("/tpl sync: request, then SYNCED; a second one within 2 s is throttled", function()
  local ns = Login(NoLoginRequest())
  Stub.Advance(5)
  T.ok(ns.Played.Request("manual"))
  T.ok(ns.Played.IsPending())
  T.eq(Printed(ns.L.SYNC_REQUESTED), 1)
  T.no(ns.Played.Request("manual"), "throttled")
  T.eq(Printed(ns.L.SYNC_THROTTLED), 1)
  T.eq(Stub.requests, 1)
  Stub.Advance(1)
  T.no(ns.Played.IsPending())
  T.eq(Printed(ns.L.SYNCED), 1)
  T.ok(ns.Tracker.GetSync())
  Stub.Advance(3)
  Stub.RunSlash("sync")
  Stub.Advance(1)
  T.eq(Stub.requests, 2, "the slash command asks too")
  T.eq(Printed(ns.L.SYNCED), 2)
end)

---------------------------------------------------------------------------
-- experimental hide (5.13)
---------------------------------------------------------------------------

T.test("hide ON: our answer hidden, original restored, user /played shown, foreign window", function()
  local orig = ChatFrameUtil.DisplayTimePlayed
  local ns = Login(NoLoginRequest({ hidePlayedMsg = true }))
  T.ok(ns.Played.CanHide())
  Stub.Advance(5)
  T.ok(ns.Played.Request("manual"))
  T.ok(ChatFrameUtil.DisplayTimePlayed ~= orig, "wrapped while our request is pending")
  Stub.Advance(1)
  T.eq(#Stub.displayed, 0, "our own answer is not displayed")
  T.ok(rawequal(ChatFrameUtil.DisplayTimePlayed, orig), "original restored")
  T.ok(ns.Tracker.GetSync(), "the answer is still used")

  -- the user types /played while our request is pending: both are shown
  Stub.Advance(3)
  T.ok(ns.Played.Request("manual"))
  RequestTimePlayed()
  T.ok(rawequal(ChatFrameUtil.DisplayTimePlayed, orig), "unwrapped at once")
  Stub.Advance(1)
  T.eq(#Stub.displayed, 2)

  -- a foreign request 1 s before ours disables the hide for ours
  Stub.Advance(10)
  RequestTimePlayed()
  Stub.Advance(1)
  local shown = #Stub.displayed
  T.ok(ns.Played.Request("manual"))
  T.ok(rawequal(ChatFrameUtil.DisplayTimePlayed, orig), "not wrapped")
  Stub.Advance(1)
  T.eq(#Stub.displayed, shown + 1)
end)

T.test("hide ON: the safety timeout restores the original without an answer", function()
  local orig = ChatFrameUtil.DisplayTimePlayed
  local ns = Login(NoLoginRequest({ hidePlayedMsg = true }))
  Stub.Advance(3)
  Stub.server.frozen = true
  local realRequest = RequestTimePlayed
  _G.RequestTimePlayed = function() Stub.requests = Stub.requests + 1 end   -- answer lost
  T.ok(ns.Played.Request("manual"))
  _G.RequestTimePlayed = realRequest
  T.ok(ChatFrameUtil.DisplayTimePlayed ~= orig)
  Stub.Advance(6)
  T.ok(rawequal(ChatFrameUtil.DisplayTimePlayed, orig), "restored by the timeout")
end)

T.test("hide OFF: the chat field is never replaced and nothing is hooked", function()
  local origRequest, origDisplay = RequestTimePlayed, ChatFrameUtil.DisplayTimePlayed
  local ns = Login()
  Stub.Advance(12)                          -- login request
  Stub.Advance(5)
  T.ok(ns.Played.Request("manual"))
  Stub.Advance(1)
  T.ok(rawequal(RequestTimePlayed, origRequest), "no hooksecurefunc")
  T.ok(rawequal(ChatFrameUtil.DisplayTimePlayed, origDisplay), "field untouched")
  T.eq(#Stub.displayed, 2, "every answer displayed")
  ns.Core.SetSetting("hidePlayedMsg", true)
  T.ok(not rawequal(RequestTimePlayed, origRequest), "turning the option on installs the hook")
end)
