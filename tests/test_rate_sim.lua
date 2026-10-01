-- tests/test_rate_sim.lua - off-line levelling simulation (SPEC 5.10, 9.4).
-- Park-Miller seed 42; mobs every 30-60 s, 2-4 quest turn-ins every 15-25 min,
-- travel without XP, 2 h sessions, 40 runs. Checks that the normalized EMA
-- (tau = 3600) predicts the time to level far better than a 10-min sliding
-- window, and that a clean restart (persisted EMA) does not change the result.
local Stub, T = ...

local floor, exp = math.floor, math.exp

local TAU = 3600
local WINDOW = 600
local SESSION = 7200          -- 2 h sessions
local SESSIONS_PER_RUN = 3
local RUNS = 40
local START_LEVEL = 10
local EVAL_STEP = 60
local MIN_REMAINING = 900     -- only remaining times >= 15 min are scored

local function Need(level)
  return Stub.xpTable[level]
end

local function MobXP(level, rng)
  local base = 45 + 5 * level
  return floor(base * (0.8 + 0.4 * rng()))
end

local function QuestXP(level, rng)
  local base = 45 + 5 * level
  return floor(base * (6 + 4 * rng()))
end

-- One run: events { t, xp, q } in play-time seconds, plus the level-up times.
local function GenRun(rng, playTime)
  local events, levelUps = {}, {}
  local level, xp, t = START_LEVEL, 0, 0
  local nextQuest = 900 + floor(rng() * 601)
  local function Gain(at, amount, quest)
    events[#events + 1] = { t = at, xp = amount, q = quest, level = level }
    xp = xp + amount
    while xp >= Need(level) do
      xp = xp - Need(level)
      levelUps[level] = at        -- time at which `level` was completed
      level = level + 1
    end
  end
  while true do
    t = t + 30 + floor(rng() * 31)                  -- next mob in 30-60 s
    if t >= playTime then break end
    if t >= nextQuest then
      local n = 2 + floor(rng() * 3)                -- 2-4 turn-ins
      for i = 1, n do Gain(t + (i - 1) * 5, QuestXP(level, rng), true) end
      t = t + (n - 1) * 5 + 120 + floor(rng() * 241) -- then 2-6 min of travel
      nextQuest = t + 900 + floor(rng() * 601)
    else
      Gain(t, MobXP(level, rng), false)
    end
  end
  return events, levelUps
end

local function Median(list)
  table.sort(list)
  local n = #list
  if n == 0 then return nil end
  return list[floor((n + 1) / 2)]
end

-- Pure model of the Tracker's EMA (mask 0, no rest) and of a sliding window.
-- Returns the list of relative ETA errors of each estimator.
local function Score(events, levelUps, playTime, emaErr, winErr)
  local a, d, tLast = 0, 0, 0
  local level, xp = START_LEVEL, 0
  local i = 1
  local winStart = 1
  for tEval = EVAL_STEP, playTime - EVAL_STEP, EVAL_STEP do
    while events[i] and events[i].t <= tEval do
      local ev = events[i]
      local dt = ev.t - tLast
      local f = exp(-dt / TAU)
      a = a * f
      d = d * f + TAU * (1 - f)
      tLast = ev.t
      a = a + ev.xp
      xp = xp + ev.xp
      while xp >= Need(level) do
        xp = xp - Need(level)
        level = level + 1
      end
      i = i + 1
    end
    local dt = tEval - tLast
    local f = exp(-dt / TAU)
    a = a * f
    d = d * f + TAU * (1 - f)
    tLast = tEval
    local tUp = levelUps[level]
    if tEval >= WINDOW and tUp then
      local actual = tUp - tEval
      if actual >= MIN_REMAINING then
        local remaining = Need(level) - xp
        emaErr[#emaErr + 1] = math.abs(remaining / (a / d) - actual) / actual
        while events[winStart] and events[winStart].t <= tEval - WINDOW do winStart = winStart + 1 end
        local wxp = 0
        for j = winStart, i - 1 do wxp = wxp + events[j].xp end
        local est = wxp > 0 and remaining / (wxp / WINDOW) or math.huge
        winErr[#winErr + 1] = math.abs(est - actual) / actual
      end
    end
  end
  return a, d
end

local function Checksum(cs, v)
  return (cs * 31 + v) % 1000000007
end

T.test("40 runs: EMA (tau 1 h) median ETA error <= 30 %, 10-min window at least 1.5x worse", function()
  local rng = T.rng(42)
  local emaErr, winErr = {}, {}
  local cs = 0
  local playTime = SESSION * SESSIONS_PER_RUN
  for _ = 1, RUNS do
    local events, levelUps = GenRun(rng, playTime)
    for _, ev in ipairs(events) do
      cs = Checksum(Checksum(cs, ev.t), ev.xp)
    end
    Score(events, levelUps, playTime, emaErr, winErr)
  end
  local mEma, mWin = Median(emaErr), Median(winErr)
  print(("  rate_sim: checksum %d, %d points, median error EMA %.1f %%, window %.1f %%")
    :format(cs, #emaErr, 100 * mEma, 100 * mWin))
  T.ok(#emaErr > 1000, "enough scored points")
  T.ok(mEma <= 0.30, ("EMA median error %.3f"):format(mEma))
  T.ok(mWin >= 1.5 * mEma, ("window median error %.3f vs EMA %.3f"):format(mWin, mEma))
end)

-- Drives the real addon through one 4 h run. With restartAt, a clean logout /
-- login happens at that play time (EMA persisted in the SavedVariables).
local function AddonRun(events, levelUps, playTime, restartAt)
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  local t0 = Stub.Now()
  local errs = {}
  local i = 1
  local level, xp = START_LEVEL, 0
  for tEval = EVAL_STEP, playTime - EVAL_STEP, EVAL_STEP do
    while events[i] and events[i].t < tEval do
      local ev = events[i]
      Stub.Advance(t0 + ev.t - Stub.Now())
      if ev.q then Stub.GrantXP(ev.xp, { quest = ev.xp }) else Stub.GrantXP(ev.xp) end
      xp = xp + ev.xp
      while xp >= Need(level) do
        xp = xp - Need(level)
        level = level + 1
      end
      i = i + 1
    end
    Stub.Advance(t0 + tEval - Stub.Now())
    if restartAt and tEval == restartAt then ns = Stub.Restart({}) end
    local e = ns.char.ema[1]
    local tUp = levelUps[level]
    if tEval >= WINDOW and tUp and tUp - tEval >= MIN_REMAINING and e.d > 0 then
      local rate = (e.a + e.r + e.q) / e.d
      local actual = tUp - tEval
      errs[#errs + 1] = math.abs((Need(level) - xp) / rate - actual) / actual
    end
  end
  return Median(errs), ns
end

T.test("through the addon: EMA matches the model; a clean restart keeps the error within 2 points", function()
  local rng = T.rng(4242)
  local playTime = 2 * SESSION
  local events, levelUps = GenRun(rng, playTime)
  -- restart at a minute boundary near 2 h with no XP event in the next 3 s
  local restartAt = SESSION
  local function busy(at)
    for _, ev in ipairs(events) do
      if ev.t >= at and ev.t <= at + 3 then return true end
    end
    return false
  end
  while busy(restartAt) do restartAt = restartAt + EVAL_STEP end

  local mAddon, ns = AddonRun(events, levelUps, playTime)
  local emaErr, winErr = {}, {}
  local a, d = Score(events, levelUps, playTime, emaErr, winErr)
  local e = ns.char.ema[1]
  T.near((e.a + e.r + e.q) / e.d, a / d, 0.01 * a / d, "addon EMA == model EMA")
  T.near(mAddon, Median(emaErr), 0.02, "addon error == model error")

  Stub.Reset()
  local mSplit = AddonRun(events, levelUps, playTime, restartAt)
  T.near(mSplit, mAddon, 0.02, "clean restart: same accuracy")
end)

---------------------------------------------------------------------------
-- Round 3 (R1, R2): days without XP at a server level cap, then the cap is raised
---------------------------------------------------------------------------

-- A druid at level 20 (58 XP) with the user's exclusions (AFK, inn, city).
local function CapWorld()
  local P = Stub.player
  P.level, P.xp, P.max, P.rest = 20, 58, 23200, 0
  Stub.server.total, Stub.server.levelPlayed = 135243, 30329
  _G.TruePlayedDB = { schema = 1, sparseSettings = true,
                      settings = { exclude = { afk = true, inn = true, city = true }, widget = { shown = false } } }
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(12)                                  -- XP baseline, login /played
  return ns
end

-- Levelling: a mob of 90-130 XP every 30-60 s (with its kill marker) for `secs`.
local function Level(rng, secs)
  local t = 0
  while t < secs do
    local dt = 30 + floor(rng() * 31)
    Stub.Advance(dt)
    Stub.Kill(90 + floor(rng() * 41))
    t = t + dt
  end
  Stub.Advance(1)
end

-- One 8 h session at the cap: kills without XP, a city visit, an AFK break, travel.
local function CappedSession(rng)
  for _ = 1, 8 do
    for _ = 1, 20 do
      Stub.KillNoXP({ level = 20, fight = 8 + floor(rng() * 8) })
      Stub.Advance(20 + floor(rng() * 30), 10)
    end
    Stub.SetMap(1454)                               -- a city
    Stub.Advance(900, 30)
    Stub.SetMap(1411)
    Stub.SetAFK(true)                               -- a break
    Stub.Advance(600, 30)
    Stub.SetAFK(false)
    Stub.Advance(600, 30)                           -- travel, gathering
  end
end

local function Eta(ns, m)
  local P = Stub.player
  return ns.Stats.ETA(ns.char, m, P.xp, P.max, P.rest, false)
end

T.test("3 days at a server level cap, then the cap is raised: the ETA stays within 20 % of the pre-cap one", function()
  local rng = T.rng(2026)
  local ns = CapWorld()
  Level(rng, 5400)                                  -- 1 h 30 of levelling at level 20
  local P = Stub.player
  T.eq(P.level, 20)
  local pre, preRate = {}, {}
  for _, m in ipairs({ 0, 7 }) do
    pre[m] = Eta(ns, m)
    preRate[m] = ns.Stats.Rate(ns.char, m)
    T.ok(pre[m] and pre[m] > 0)
  end
  local remaining0 = P.max - P.xp
  local included = 0
  -- the server cap: detected after three kills without XP
  for s = 1, 3 do
    if s > 1 then ns = Stub.Restart({ offline = 16 * 3600 }); Stub.Advance(15) end
    local before = ns.Stats.Sum(ns.char.life, 0)
    CappedSession(rng)
    included = included + ns.Stats.Sum(ns.char.life, 0) - before
    T.ok(ns.Tracker.IsMax(), "capped (session " .. s .. ")")
    T.eq(select(2, ns.Tracker.GetCapInfo()), true)
    T.eq(P.xp, 58 + (23200 - remaining0 - 58), "no XP at the cap")
  end
  -- without the guard the mask-0 EMA would have decayed by exp(-included / tau)
  T.ok(included > 20 * 3600, ("%.1f h of counted time without XP"):format(included / 3600))
  -- a few days later the server raises the cap: XP again, same pace
  ns = Stub.Restart({ offline = 16 * 3600 })
  Stub.Advance(15)
  T.ok(ns.Tracker.IsMax(), "still shown at the cap until XP comes")
  Stub.Advance(40)
  Stub.Kill(110)
  Stub.Advance(1)
  T.no(ns.Tracker.IsMax(), "the cap is over by itself")
  for _, m in ipairs({ 0, 7 }) do
    local sec, status = Eta(ns, m)
    T.ok(status == "ok", "mask " .. m .. ": " .. tostring(status))
    T.ok(math.abs(sec / pre[m] - 1) <= 0.2,
      ("mask %d: ETA %.2f h after the cap, %.2f h before"):format(m, sec / 3600, pre[m] / 3600))
  end
  -- and while levelling resumes (every kill for 30 min): the rate stays near the pre-cap one
  local t = 0
  while t < 1800 do
    local dt = 30 + floor(rng() * 31)
    Stub.Advance(dt)
    Stub.Kill(90 + floor(rng() * 41))
    Stub.Advance(1)
    t = t + dt + 1
    for _, m in ipairs({ 0, 7 }) do
      local r = ns.Stats.Rate(ns.char, m)
      T.ok(math.abs(r / preRate[m] - 1) <= 0.2, ("mask %d at +%d s: %.0f XP/h, %.0f before"):format(m, t, r, preRate[m]))
    end
  end
  T.eq(#Stub.errors, 0)
end)

T.test("3 days without XP and no kill to detect a cap (stall only): the ETA stays bounded", function()
  local rng = T.rng(7)
  local ns = CapWorld()
  Level(rng, 5400)
  local pre = Eta(ns, 0)
  local preRate = ns.Stats.Rate(ns.char, 0)
  -- the EMA decays over the first C.XP_STALL seconds without XP (f), then freezes: the
  -- rate can drop by f * d0 / (d0 * f + tau * (1 - f)) at most, whatever comes after
  local d0 = ns.char.ema[1].d
  local f = math.exp(-ns.C.XP_STALL / 3600)
  local bound = (d0 * f + 3600 * (1 - f)) / (d0 * f)
  T.ok(bound < 1.6, ("bound %.2f"):format(bound))
  -- three 8 h sessions of play without any XP and without killing (gathering, travel)
  for s = 1, 3 do
    if s > 1 then ns = Stub.Restart({ offline = 16 * 3600 }); Stub.Advance(15) end
    Stub.Advance(8 * 3600, 30)
    T.ok((ns.Tracker.GetStall()), "stalled")
    T.no(ns.Tracker.IsMax(), "no kill: no cap detected")
  end
  ns = Stub.Restart({ offline = 16 * 3600 })
  Stub.Advance(15)
  Stub.Kill(110)
  Stub.Advance(1)
  -- 24 h of counted time without XP cost 20 min of decay only (never days to level)
  local sec = Eta(ns, 0)
  T.ok(sec <= pre * bound, ("ETA %.2f h, %.2f h before (bound x%.2f)"):format(sec / 3600, pre / 3600, bound))
  T.ok(ns.Stats.Rate(ns.char, 0) >= preRate / bound)
end)
