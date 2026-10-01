-- tests/test_kills.lua - mobs to kill from the average of the last kills (NEXT-LOT C):
-- char.killRing written by the Tracker, repaired and migrated by Core.RepairChar, read by
-- Stats.KillsToLevel and the tooltip row; persistence, per-character isolation, the late
-- SavedVariables swap, resets, max level, read-only and allocations.
local Stub, T = ...

local format = string.format
local ALT_GUID = "Player-4619-0BADF00D"

-- Fresh addon on an optional SV table, logged in with a valid XP baseline.
local function KillLogin(db)
  if db then _G.TruePlayedDB = db end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(3)
  return ns
end

-- One kill per second, worth each listed base XP (opts passed to Stub.Kill).
local function Kills(list, opts)
  for i = 1, #list do
    Stub.Kill(list[i], opts)
    Stub.Advance(1)
  end
end

local function Seq(from, to, step)
  local t = {}
  for v = from, to, step or 1 do t[#t + 1] = v end
  return t
end

-- The three results of Stats.KillsToLevel as one table (nil holes kept as holes).
local function K3(Stats, char, xp, max, rested, isMax)
  local n, avg, last = Stats.KillsToLevel(char, xp, max, rested, isMax)
  return { n = n, avg = avg, last = last }
end

-- Kill by kill simulation of the engine's rest model (Stub.Kill): the reference count.
local function Sim(xp, max, E, base)
  local n = 0
  while xp < max do
    local d = E < 2 * base and E or 2 * base
    E = E - d
    xp = xp + base + d / 2
    n = n + 1
  end
  return n
end

---------------------------------------------------------------------------
-- Tracker: the ring
---------------------------------------------------------------------------

T.test("ring: 12 kills of 10..120 XP keep the last 10 in order; their average gives the count", function()
  local ns = KillLogin()
  T.eq(ns.char.killRing, nil, "no ring before the first kill")
  T.eq(ns.Tracker.loadKills, 0)
  Stub.Kill(10)
  Stub.Advance(1)
  local ring = ns.char.killRing
  T.eq(ring, { 10 }, "created at the first kill")
  Kills(Seq(20, 120, 10))
  T.ok(ns.char.killRing == ring, "the same table after the wrap")
  T.eq(ring, Seq(30, 120, 10), "oldest first, newest last: 10 and 20 shifted out")
  T.eq(#ring, ns.C.KILL_RING)
  T.eq(ns.C.KILL_RING, 10)
  T.eq(ns.char.lastKill, { xp = 120, level = 10, at = time() }, "lastKill: same shape, the last kill")
  T.eq(ns.Tracker.loadKills, 10, "kills of this load, capped at the ring size")
  T.eq(Stub.player.xp, 780)
  T.eq(K3(ns.Stats, ns.char, 780, 7600, 0), { n = 91, avg = 75, last = 120 }, "ceil(6820 / 75)")
  T.eq(K3(ns.Stats, ns.char, 780, 7600, 1000), { n = 85, avg = 75, last = 120 },
       "rested 1000: 6 full rested kills, a partial one, then 78")
  T.eq(Sim(780, 7600, 1000, 75), 85)
  T.eq((ns.Stats.KillsToLevel({ lastKill = { xp = 120 } }, 780, 7600, 0)), 57, "the last kill alone: 57")
  -- the tokens follow the average (the bar is a consumer)
  Stub.Advance(1)
  T.ok(ns.Tokens.IsActive())
  T.eq(ns.Tokens.ctx.kills, 91)
  T.eq(ns.Tokens.ctx.killXP, 75)
  -- a small mob moves the average by a tenth of the difference; the last kill alone
  -- would jump from 57 to 340 mobs
  Stub.Kill(20)
  Stub.Advance(1)
  local expect = Seq(40, 120, 10)
  expect[10] = 20
  T.eq(ring, expect)
  T.eq(K3(ns.Stats, ns.char, 800, 7600, 0), { n = 92, avg = 74, last = 20 }, "ceil(6800 / 74)")
  T.eq((ns.Stats.KillsToLevel({ lastKill = { xp = 20 } }, 800, 7600, 0)), 340)
end)

T.test("ring: a batch settled at once records one entry per mob (at most 10), a pending gain one", function()
  local ns = KillLogin()
  Stub.Kill(50)
  Stub.Advance(1)
  Stub.Kill(110, { count = 4 })            -- area damage: 440 XP, 4 markers, one XP update
  Stub.Advance(1)
  T.eq(ns.char.killRing, { 50, 110, 110, 110, 110 })
  T.eq(ns.char.lastKill.xp, 110)
  T.eq(ns.Tracker.loadKills, 5)
  T.eq(K3(ns.Stats, ns.char, 0, 7600, 0).avg, 98, "490 / 5, not (50 + 110) / 2")
  -- rested batch: the per-mob base XP, without the bonus
  Stub.player.rest = 300
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
  Stub.Kill(100, { count = 3 })            -- 200 + 150 + 100 XP
  Stub.Advance(1)
  T.eq(ns.char.killRing, { 50, 110, 110, 110, 110, 100, 100, 100 })
  -- an uneven split is rounded like lastKill
  for _ = 1, 3 do Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "x") end
  Stub.GrantXP(100)
  Stub.Advance(1)
  T.eq(ns.char.lastKill.xp, 33)
  T.eq(ns.char.killRing, { 110, 110, 110, 110, 100, 100, 100, 33, 33, 33 }, "1 + 4 + 3 + 3 > 10: the oldest out")
  -- a batch larger than the ring fills it with the per-mob value
  local ring = ns.char.killRing
  Stub.Kill(30, { count = 12 })
  Stub.Advance(1)
  T.ok(ns.char.killRing == ring, "same table")
  T.eq(ring, { 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 })
  T.eq(ns.Tracker.loadKills, 10)
  -- XP secret during a fight: the markers divide the XP read after combat, one entry each
  Stub.SetInstance(true, "party", 389, 90001)
  Stub.Advance(5)
  Stub.EnterCombat()
  Stub.secret.xp = true
  for _ = 1, 3 do
    Stub.Kill(130)
    Stub.Advance(4)
  end
  T.eq(ring[10], 30, "nothing read during the fight")
  Stub.secret.xp = false
  Stub.LeaveCombat()
  Stub.Advance(1)
  T.eq(ring, { 30, 30, 30, 30, 30, 30, 30, 130, 130, 130 })
  -- a gain accepted without its marker (inside an instance) after the window: one entry
  Stub.Kill(160, { marker = false })
  Stub.Advance(1)
  T.eq(ring[10], 130, "waits for a possible marker")
  Stub.Advance(4)
  T.eq(ring, { 30, 30, 30, 30, 30, 30, 130, 130, 130, 160 })
  T.eq(ns.char.lastKill.xp, 160)
  -- an unknown number of kills (secret fight without markers): nothing recorded
  Stub.EnterCombat()
  Stub.secret.xp = true
  Stub.Kill(150, { marker = false }); Stub.Advance(4)
  Stub.Kill(150, { marker = false }); Stub.Advance(4)
  Stub.secret.xp = false
  Stub.LeaveCombat()
  Stub.Advance(5)
  T.eq(ring, { 30, 30, 30, 30, 30, 30, 130, 130, 130, 160 })
end)

T.test("ring: a gain validated by its late marker records one entry", function()
  local ns = KillLogin()
  Stub.Kill(50)
  Stub.Advance(5)
  Stub.Kill(75, { marker = false })        -- the XP first, no marker yet: the gain waits
  Stub.Advance(0.5)
  T.eq(ns.char.killRing, { 50 }, "waits for its marker")
  T.eq(ns.Tracker.loadKills, 1)
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "late")
  T.eq(ns.char.killRing, { 50, 75 }, "the late marker commits it once")
  T.eq(ns.char.lastKill.xp, 75)
  T.eq(ns.Tracker.loadKills, 2)
  Stub.Advance(5)
  T.eq(ns.char.killRing, { 50, 75 }, "not committed again when the window ends")
end)

T.test("ring: quests, discoveries and grey mobs never enter it", function()
  local ns = KillLogin()
  Stub.Kill(80)
  Stub.Advance(5)
  Stub.GrantXP(400, { quest = 400 })
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 400 experience.")
  Stub.Advance(5)
  Stub.Discover(250)
  Stub.Advance(5)
  Stub.Kill(0, { marker = false })
  Stub.Advance(5)
  T.eq(ns.char.killRing, { 80 })
  -- a kill and a quest reward in one batch: the kill part only
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold dies, you gain 70 experience.")
  Stub.GrantXP(270, { quest = 200 })
  Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 200 experience.")
  Stub.Advance(1)
  T.eq(ns.char.killRing, { 80, 70 })
end)

T.test("ring: the kill that levels up stays in it (the last 10 kills, whatever their level)", function()
  Stub.player.xp = Stub.player.max - 100
  local ns = KillLogin()
  Stub.Kill(300)
  Stub.Advance(1)
  T.eq(Stub.player.level, 11)
  Stub.Kill(330)
  Stub.Advance(1)
  T.eq(ns.char.killRing, { 300, 330 })
  T.eq(ns.char.lastKill.level, 11)
  T.eq({ Stub.player.xp, Stub.player.max }, { 530, 8800 })
  T.eq(K3(ns.Stats, ns.char, 530, 8800, 0), { n = 27, avg = 315, last = 330 }, "ceil(8270 / 315)")
end)

---------------------------------------------------------------------------
-- Core: repair and migration
---------------------------------------------------------------------------

T.test("RepairChar validates the ring: junk dropped, compacted in order, rounded, 10 newest kept", function()
  local ns = Stub.LoadAddon()
  local C = ns.C
  local function R(ring, lastKill)
    local c = { killRing = ring, lastKill = lastKill }
    ns.Core.RepairChar(c)
    return c.killRing, c
  end
  local clean = { 10, 20, 30 }
  local got = R(clean)
  T.ok(got == clean, "a clean ring keeps its table")
  T.eq(got, { 10, 20, 30 })
  T.eq((R({ 10.4, 20.6, 0.5 })), { 10, 21, 1 }, "rounded")
  T.eq((R({ 10, "x", 30 })), { 10, 30 }, "a non-number dropped, the rest compacted")
  T.eq((R({ 10, 0 / 0, 30, -5, 0, math.huge, -math.huge, C.KILL_XP_MAX + 1, 0.4, true, {}, 40, C.KILL_XP_MAX })),
       { 10, 30, 40, C.KILL_XP_MAX }, "NaN, inf, <= 0, < 0.5 after rounding and > KILL_XP_MAX dropped")
  T.eq((R({ [1] = 10, [3] = 30, [7] = 70 })), { 10, 30, 70 }, "holes closed in key order")
  T.eq((R({ 10, 20, foo = 5, [0] = 3, [1.5] = 4, [-1] = 2, [true] = 9 })), { 10, 20 }, "non-array keys removed")
  T.eq((R(Seq(10, 150, 10))), Seq(60, 150, 10), "15 entries: the 10 newest kept")
  local long = Seq(10, 150, 10)
  long[14] = "bad"
  T.eq((R(long)), { 50, 60, 70, 80, 90, 100, 110, 120, 130, 150 }, "junk dropped before the newest 10 are kept")
  local holes = {}
  for i = 1, 30, 2 do holes[i] = i end
  T.eq((R(holes)), Seq(11, 29, 2), "sparse and long")
  T.eq((R({})), nil, "an empty ring is dropped")
  T.eq((R({ "a", -1 })), nil, "no valid entry: dropped")
  T.eq((R("x")), nil, "not a table")
  T.eq((R(5)), nil)
  T.eq((R(true)), nil)
  T.eq((R(nil)), nil)
  -- the last kill is not touched by the ring repair
  local ring, c = R({ 10, "x" }, { xp = 12, level = 10, at = 1 })
  T.eq(ring, { 10 })
  T.eq(c.lastKill, { xp = 12, level = 10, at = 1 })
  -- idempotent
  c = { killRing = { 5, 6.6, "z" } }
  ns.Core.RepairChar(c)
  ns.Core.RepairChar(c)
  T.eq(c.killRing, { 5, 7 })
end)

T.test("RepairChar migrates a record that only has lastKill: killRing = { lastKill.xp }", function()
  local ns = Stub.LoadAddon()
  local function R(c)
    ns.Core.RepairChar(c)
    return c.killRing, c
  end
  local ring, c = R({ lastKill = { xp = 312, level = 20, at = 1790800000 } })
  T.eq(ring, { 312 })
  T.eq(c.lastKill, { xp = 312, level = 20, at = 1790800000 }, "lastKill kept as it is")
  T.eq((R({ lastKill = { xp = 311.6 } })), { 312 }, "after lastKill's own validation (rounded)")
  T.eq((R({ lastKill = { xp = 0 } })), nil, "an invalid last kill gives no ring")
  T.eq((R({ lastKill = { xp = 0.3 } })), nil, "a last kill that rounds to 0 gives no ring")
  T.eq((R({ lastKill = "x" })), nil)
  T.eq((R({})), nil, "no kill: no ring")
  T.eq((R({ lastKill = { xp = 312 }, killRing = { 100, 200 } })), { 100, 200 }, "an existing ring is kept")
  T.eq((R({ lastKill = { xp = 312 }, killRing = {} })), { 312 }, "an empty ring is seeded too")
  T.eq((R({ lastKill = { xp = 312 }, killRing = { "junk" } })), { 312 }, "and a ring without a valid entry")
  T.eq((R({ lastKill = { xp = 312 }, killRing = "junk" })), { 312 })
end)

T.test("migration at load: every saved record with only lastKill gets its ring, schema unchanged", function()
  KillLogin()
  Stub.Kill(88)
  Stub.Advance(1)
  Stub.Logout()
  local saved = Stub.DeepCopy(Stub.saved)
  local rec = saved.chars[Stub.player.guid]
  T.eq(rec.killRing, { 88 }, "saved with the record")
  rec.killRing = nil                       -- as written by the previous version
  saved.chars[ALT_GUID] = { guid = ALT_GUID, name = "Alt", level = 30, lastKill = { xp = 400, level = 30, at = 1 } }
  saved.chars["Player-4619-0000BEEF"] = { guid = "Player-4619-0000BEEF", name = "NoKill", level = 5,
                                          killRing = { 7, "bad", 9 } }
  Stub.Reset({ keepWorld = true })
  local ns = KillLogin(saved)
  T.eq(ns.char.killRing, { 88 }, "the current character, seeded from lastKill")
  T.eq(ns.db.chars[ALT_GUID].killRing, { 400 }, "another character too")
  T.eq(ns.db.chars["Player-4619-0000BEEF"].killRing, { 7, 9 }, "a bad ring repaired at load")
  T.eq(ns.db.schema, 1, "no schema change")
  Stub.Kill(200)
  Stub.Advance(1)
  T.eq(ns.char.killRing, { 88, 200 })
  T.eq(K3(ns.Stats, ns.char, 0, 7600, 0).avg, 144)
  T.eq(ns.char.lastKill.xp, 200)
end)

---------------------------------------------------------------------------
-- Stats.KillsToLevel
---------------------------------------------------------------------------

T.test("KillsToLevel: the rounded ring average; n, avg, last; lastKill fallback; never writes", function()
  local Stats = Stub.LoadAddon().Stats
  -- the average is rounded to a whole XP: the count and the XP shown agree
  T.eq(K3(Stats, { killRing = { 47, 48 }, lastKill = { xp = 48 } }, 0, 7600, 0), { n = 159, avg = 48, last = 48 })
  T.eq(K3(Stats, { killRing = { 47, 47, 48 }, lastKill = { xp = 48 } }, 0, 7600, 0), { n = 162, avg = 47, last = 48 })
  T.eq(K3(Stats, { killRing = { 1, 2 } }, 0, 400, 0), { n = 200, avg = 2, last = 2 }, "1.5 rounds up")
  -- the spec's line: 1780 XP to go, average 47, last 30
  local char = { killRing = { 50, 55, 60, 50, 46, 50, 52, 40, 37, 30 }, lastKill = { xp = 30, level = 10, at = 1 } }
  T.eq(K3(Stats, char, 5820, 7600, 0), { n = 38, avg = 47, last = 30 })
  -- the rest-aware math is unchanged, with the average as the base
  T.eq((Stats.KillsToLevel({ killRing = { 50, 150 } }, 0, 2000, 5000)), 10)
  T.eq((Stats.KillsToLevel({ killRing = { 50, 150 } }, 0, 2050, 5000)), 11)
  T.eq((Stats.KillsToLevel({ killRing = { 50, 150 } }, 0, 2000, 600)), 17)
  T.eq((Stats.KillsToLevel({ killRing = { 50, 150 } }, 0, 2000, 650)), 17)
  T.eq((Stats.KillsToLevel({ killRing = { 50, 150 } }, 0, 650, 650)), 4)
  for _, c in ipairs({ { 0, 23200, 0, { 312, 300, 324 } }, { 58, 23200, 23200, { 310, 314 } },
                       { 0, 7600, 333, { 40, 45, 50 } }, { 7000, 7600, 90, Seq(41, 50) },
                       { 100, 209800, 150000, { 1400, 1500, 1450 } } }) do
    local sum = 0
    for _, v in ipairs(c[4]) do sum = sum + v end
    local avg = math.floor(sum / #c[4] + 0.5)
    local n = Stats.KillsToLevel({ killRing = c[4] }, c[1], c[2], c[3])
    T.eq(n, Sim(c[1], c[2], c[3], avg), format("xp %d max %d pool %d avg %d", c[1], c[2], c[3], avg))
  end
  -- lastKill alone (no ring, an empty one, or one without a valid entry): its XP is both
  T.eq(K3(Stats, { lastKill = { xp = 312 } }, 58, 23200, 0), { n = 75, avg = 312, last = 312 })
  T.eq(K3(Stats, { lastKill = { xp = 312 }, killRing = {} }, 58, 23200, 0), { n = 75, avg = 312, last = 312 })
  T.eq(K3(Stats, { lastKill = { xp = 312 }, killRing = { "x", 0 / 0, -1, 0, 0.2 } }, 58, 23200, 0),
       { n = 75, avg = 312, last = 312 })
  T.eq(K3(Stats, { lastKill = { xp = 312 }, killRing = "x" }, 58, 23200, 0), { n = 75, avg = 312, last = 312 })
  -- a ring without lastKill (or an invalid one): last = the newest valid entry
  T.eq(K3(Stats, { killRing = { 300, 324 } }, 58, 23200, 0), { n = 75, avg = 312, last = 324 })
  T.eq(K3(Stats, { killRing = { 300, 324, 0 / 0 } }, 58, 23200, 0), { n = 75, avg = 312, last = 324 })
  T.eq(K3(Stats, { killRing = { 300, 324 }, lastKill = { xp = 0 / 0 } }, 58, 23200, 0),
       { n = 75, avg = 312, last = 324 })
  T.eq(K3(Stats, { killRing = { 300, 324, math.huge } }, 58, 23200, 0), { n = 75, avg = 312, last = 324 }, "inf ignored")
  -- only the newest C.KILL_RING entries count
  T.eq(K3(Stats, { killRing = Seq(10, 150, 10) }, 0, 7600, 0), { n = 73, avg = 105, last = 150 })
  -- nil without a kill, at max level, with XP disabled; nil, avg, last without valid XP values
  T.eq(K3(Stats, { killRing = {} }, 0, 1000, 0), {})
  T.eq(K3(Stats, { killRing = { 0.2 } }, 0, 1000, 0), {}, "an entry below 1 XP is no kill")
  T.eq(K3(Stats, { killRing = { 50 } }, 0, 1000, 0, true), {})
  Stub.player.xpDisabled = true
  T.eq(K3(Stats, { killRing = { 50 } }, 0, 1000, 0), {})
  Stub.player.xpDisabled = false
  T.eq(K3(Stats, { killRing = { 40, 60 }, lastKill = { xp = 60 } }, nil, 1000, 0), { avg = 50, last = 60 })
  T.eq(K3(Stats, { killRing = { 40, 60 }, lastKill = { xp = 60 } }, 0, 0, 0), { avg = 50, last = 60 })
  T.eq(K3(Stats, { killRing = { 40, 60 }, lastKill = { xp = 60 } }, 1000, 1000, 0), { n = 0, avg = 50, last = 60 })
  -- never writes into the record
  local rec = { killRing = { 300, "x", 324, 0 / 0 }, lastKill = { xp = 324, level = 20, at = 5 } }
  local copy = Stub.DeepCopy(rec)
  Stats.KillsToLevel(rec, 58, 23200, 700)
  T.eq(rec.lastKill, copy.lastKill)
  T.eq({ rec.killRing[1], rec.killRing[2], rec.killRing[3], #rec.killRing }, { 300, "x", 324, 4 })
  T.ok(rec.killRing[4] ~= rec.killRing[4], "NaN left as it is")
end)

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------

local function TipLine(ns, left, detailed)
  GameTooltip:ClearLines()
  ns.Tooltip.Fill(GameTooltip, detailed)
  local lines = GameTooltip._lines or {}
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i][2] end
  end
  return nil
end

T.test("tooltip: '~38 (average: 47 XP, last: 30 XP)' in enUS, '~38 (moyenne : 47 XP, dernier : 30 XP)' in frFR", function()
  local want = {
    enUS = { "~38 (average: 47 XP, last: 30 XP)", "~33 (average: 52 XP, last: 100 XP)" },
    frFR = { "~38 (moyenne : 47 XP, dernier : 30 XP)", "~33 (moyenne : 52 XP, dernier : 100 XP)" },
  }
  for _, locale in ipairs({ "enUS", "frFR" }) do
    Stub.Reset()
    Stub.InstallUI({ ldb = false })
    Stub.locale = locale
    Stub.player.xp = 7600 - 1780 - 470       -- 1780 XP to go after the 10 kills below
    local ns = KillLogin()
    local L = ns.L
    T.eq(TipLine(ns, L.TT_KILLS), L.TT_KILLS_NODATA, locale .. ": no kill yet")
    Kills({ 50, 55, 60, 50, 46, 50, 52, 40, 37, 30 })   -- 470 XP: average 47, last 30
    T.eq(Stub.player.xp, 5820)
    T.eq(TipLine(ns, L.TT_KILLS), want[locale][1], locale)
    T.eq(TipLine(ns, L.TT_KILLS, true), want[locale][1], locale .. ": same line in the detailed view")
    -- the next kill (100 XP) replaces the oldest (50): average 52, 1680 XP to go
    Kills({ 100 })
    T.eq(TipLine(ns, L.TT_KILLS), want[locale][2], locale)
    -- the same line from the format, with the thousands separator
    local n, avg, last = ns.Stats.KillsToLevel(ns.char, Stub.player.xp, Stub.player.max, 0)
    T.eq(TipLine(ns, L.TT_KILLS), format(L.TT_KILLS_FMT, ns.Fmt.Number(n), ns.Fmt.Number(avg), ns.Fmt.Number(last)))
    ns.char.killRing = { 12345, 12344 }
    ns.char.lastKill.xp = 12344
    Stub.player.max = 2000000
    Stub.Fire("PLAYER_XP_UPDATE", "player")
    Stub.Advance(1)
    local sep = locale == "frFR" and "\194\160" or ","
    T.eq(TipLine(ns, L.TT_KILLS), format(L.TT_KILLS_FMT, "162", "12" .. sep .. "345", "12" .. sep .. "344"), locale)
  end
end)

T.test("tooltip: a ring is not needed: a record with only lastKill shows its XP as both", function()
  Stub.InstallUI({ ldb = false })
  Stub.player.xp = 58
  local ns = KillLogin()
  ns.char.lastKill = { xp = 610, level = 10, at = time() }   -- set live: no ring
  ns.char.killRing = nil
  T.eq(TipLine(ns, ns.L.TT_KILLS), "~13 (average: 610 XP, last: 610 XP)", "ceil(7542 / 610)")
end)

---------------------------------------------------------------------------
-- Persistence, isolation, late swap, resets
---------------------------------------------------------------------------

T.test("persistence: the ring survives a relog and a /reload and keeps filling", function()
  KillLogin()
  Kills({ 10, 20, 30 })
  local ns = Stub.Restart({ offline = 600, settle = 3 })
  T.eq(ns.char.killRing, { 10, 20, 30 })
  T.eq(ns.Tracker.loadKills, 0, "no kill in this load yet")
  Kills({ 40 })
  T.eq(ns.Tracker.loadKills, 1)
  ns = Stub.Restart({ reload = true, offline = 2, settle = 3 })
  T.eq(ns.char.killRing, { 10, 20, 30, 40 })
  T.eq(ns.Tracker.loadKills, 0)
  Kills(Seq(50, 120, 10))
  T.eq(ns.char.killRing, Seq(30, 120, 10))
  ns = Stub.Restart({ offline = 60, settle = 3 })
  T.eq(ns.char.killRing, Seq(30, 120, 10), "saved full, loaded full")
  T.eq(ns.char.lastKill.xp, 120)
  local r = K3(ns.Stats, ns.char, Stub.player.xp, Stub.player.max, 0)
  T.eq({ r.avg, r.last }, { 75, 120 })
  -- a crash keeps what the last save had, like the rest of the record
  Kills({ 130 })
  ns = Stub.Restart({ crash = true })
  T.eq(ns.char.killRing, Seq(30, 120, 10))
end)

T.test("isolation: each character has its own ring (two GUIDs, saved copies)", function()
  KillLogin()
  Kills({ 40, 60 })
  local first = Stub.player.guid
  Stub.Logout()
  local saved = Stub.DeepCopy(Stub.saved)
  Stub.Reset()
  local p = Stub.player
  p.guid, p.name, p.level, p.xp, p.max = ALT_GUID, "Alt", 30, 100, 47400
  local alt = KillLogin(saved)
  T.eq(alt.char.guid, ALT_GUID)
  T.eq(alt.char.killRing, nil, "the alt starts without a ring")
  T.eq(alt.Stats.KillsToLevel(alt.char, 100, 47400, 0), nil, "and without a count")
  Kills({ 400, 500, 600 })
  T.eq(alt.char.killRing, { 400, 500, 600 })
  T.eq(alt.db.chars[first].killRing, { 40, 60 }, "the first character's ring untouched")
  T.eq(K3(alt.Stats, alt.db.chars[first], 0, 7600, 0).avg, 50)
  T.eq(K3(alt.Stats, alt.char, 1600, 47400, 0).avg, 500)
  -- back on the first character: its own ring; the alt's kept
  Stub.Logout()
  saved = Stub.DeepCopy(Stub.saved)
  Stub.Reset()
  local ns = KillLogin(saved)
  T.eq(ns.char.guid, first)
  T.eq(ns.char.killRing, { 40, 60 })
  Kills({ 80 })
  T.eq(ns.char.killRing, { 40, 60, 80 })
  T.eq(ns.db.chars[ALT_GUID].killRing, { 400, 500, 600 })
  T.ok(ns.db.chars[ALT_GUID].killRing ~= ns.char.killRing)
end)

T.test("late SV swap: a fresh provisional record gives way to the saved ring plus this load's kills", function()
  KillLogin()
  Kills({ 10, 20, 30 })
  Stub.Logout()
  local real = Stub.DeepCopy(Stub.saved)
  Stub.Reset({ keepWorld = true })
  local ns = KillLogin()                   -- the SavedVariables arrive late (provisional record)
  T.eq(ns.char.killRing, nil)
  Kills({ 52, 54 })
  T.eq(ns.char.killRing, { 52, 54 })
  T.eq(ns.Tracker.loadKills, 2)
  _G.TruePlayedDB = real
  Stub.Advance(2)
  T.ok(ns.db == real, "swapped")
  T.eq(ns.char.killRing, { 10, 20, 30, 52, 54 }, "the saved history kept, this load's kills appended")
  T.eq(ns.char.lastKill.xp, 54)
  Kills({ 56 })
  T.eq(ns.char.killRing, { 10, 20, 30, 52, 54, 56 })
  -- after a relog the merged ring is what was saved
  ns = Stub.Restart({ offline = 60 })
  T.eq(ns.char.killRing, { 10, 20, 30, 52, 54, 56 })
end)

T.test("late SV swap: an older copy of the same record gets only this load's kills (no duplicates)", function()
  KillLogin()
  Kills({ 10, 20, 30 })
  Stub.Logout()
  local saved = Stub.saved
  local guid = Stub.player.guid
  Stub.Reset({ keepWorld = true })
  local ns = KillLogin(Stub.DeepCopy(saved))
  Kills({ 52, 54 })
  T.eq(ns.char.killRing, { 10, 20, 30, 52, 54 })
  -- the same file applied again later (WTFix): its ring predates this load
  local again = Stub.DeepCopy(saved)
  _G.TruePlayedDB = again
  Stub.Advance(2)
  T.ok(ns.db == again, "swapped")
  T.eq(ns.char.killRing, { 10, 20, 30, 52, 54 }, "no duplicate")
  -- a second swap in the same load: every kill of this load follows again
  Kills({ 56 })
  T.eq(ns.Tracker.loadKills, 3)
  local older = Stub.DeepCopy(saved)
  older.chars[guid].killRing = { 10 }     -- an even older copy
  _G.TruePlayedDB = older
  Stub.Advance(2)
  T.ok(ns.db == older)
  T.eq(ns.char.killRing, { 10, 52, 54, 56 })
  -- more than 10 kills in this load: the 10 newest replace the whole saved ring
  Kills(Seq(101, 112))
  T.eq(ns.Tracker.loadKills, 10)
  local full = Stub.DeepCopy(saved)
  full.chars[guid].killRing = Seq(1, 10)
  _G.TruePlayedDB = full
  Stub.Advance(2)
  T.ok(ns.db == full)
  T.eq(ns.char.killRing, Seq(103, 112))
  -- no kill in this load: a swap keeps the saved ring as it is
  Stub.Reset({ keepWorld = true })
  ns = KillLogin(Stub.DeepCopy(saved))
  local late = Stub.DeepCopy(saved)
  late.chars[guid].killRing = { 1, 2 }
  _G.TruePlayedDB = late
  Stub.Advance(2)
  T.ok(ns.db == late)
  T.eq(ns.char.killRing, { 1, 2 })
  -- a record saved by the previous version (lastKill only): seeded, then this load's kills
  Stub.Reset({ keepWorld = true })
  ns = KillLogin(Stub.DeepCopy(saved))
  Kills({ 61, 62 })
  local legacy = Stub.DeepCopy(saved)
  legacy.chars[guid].killRing = nil
  T.eq(legacy.chars[guid].lastKill.xp, 30)
  _G.TruePlayedDB = legacy
  Stub.Advance(2)
  T.ok(ns.db == legacy)
  T.eq(ns.char.killRing, { 30, 61, 62 })
  T.eq(ns.char.lastKill.xp, 62)
end)

T.test("ResetChar clears the ring; kills from before the reset never come back through a swap", function()
  KillLogin()
  Kills({ 10, 20 })
  Stub.Logout()
  local saved = Stub.saved
  Stub.Reset({ keepWorld = true })
  local ns = KillLogin(Stub.DeepCopy(saved))
  Kills({ 52 })
  T.eq(ns.char.killRing, { 10, 20, 52 })
  T.ok(ns.Core.ResetChar(Stub.player.guid))
  T.eq(ns.char.killRing, nil, "reset with the rest of the record")
  T.eq(ns.char.lastKill, nil)
  T.eq(ns.Tracker.loadKills, 0)
  T.eq(ns.Stats.KillsToLevel(ns.char, Stub.player.xp, Stub.player.max, 0), nil)
  Kills({ 60 })
  T.eq(ns.char.killRing, { 60 })
  local copy = Stub.DeepCopy(saved)
  _G.TruePlayedDB = copy
  Stub.Advance(2)
  T.ok(ns.db == copy)
  T.eq(ns.char.killRing, { 10, 20, 60 }, "the saved record plus the kill made after the reset only")
  -- /tpl reset rate keeps the kills (like lastKill)
  ns.Core.ResetRate()
  T.eq(ns.char.killRing, { 10, 20, 60 })
end)

T.test("max level and read-only: nothing recorded, nothing written", function()
  local P = Stub.player
  P.level, P.xp, P.max = 60, 0, 209800
  local ns = KillLogin()
  Stub.Kill(500)
  Stub.Advance(5)
  T.eq(ns.char.killRing, nil)
  T.eq(ns.char.lastKill, nil)
  T.eq(ns.Tracker.loadKills, 0)
  -- read-only (data from a newer TruePlayed)
  Stub.Reset()
  local guid = Stub.player.guid
  local stored = { guid = guid, name = "Lutak", level = 10, lastKill = { xp = 70, level = 10, at = 1 },
                   killRing = { 60, 70 } }
  local db = { schema = 99, chars = { [guid] = stored } }
  ns = KillLogin(db)
  T.ok(ns.readOnly)
  Stub.Kill(500)
  Stub.Advance(5)
  T.eq(stored.killRing, { 60, 70 }, "the real record untouched")
  T.eq(stored.lastKill, { xp = 70, level = 10, at = 1 })
  T.ok(ns.char ~= stored and ns.char.killRing ~= stored.killRing, "a detached copy")
  T.eq(ns.char.killRing, { 60, 70 }, "the copy is not written either")
  T.eq(ns.Tracker.loadKills, 0)
  T.eq(K3(ns.Stats, ns.char, 500, 7600, 0).avg, 65, "still read")
  -- read-only record with only lastKill: the migration touches the copy only
  Stub.Reset()
  stored = { guid = guid, name = "Lutak", level = 10, lastKill = { xp = 70, level = 10, at = 1 } }
  ns = KillLogin({ schema = 99, chars = { [guid] = stored } })
  T.ok(ns.readOnly)
  T.eq(stored.killRing, nil)
  T.eq(ns.char.killRing, { 70 })
end)

---------------------------------------------------------------------------
-- Allocations
---------------------------------------------------------------------------

T.test("allocation: a full ring, kills tokens on the bar, no garbage per steady tick", function()
  Stub.InstallUI({ ldb = false })
  local ns = KillLogin()
  Kills(Seq(10, 120, 10))
  local ring = ns.char.killRing
  T.eq(#ring, 10)
  ns.Core.SetSetting("widget.slots.2", "kills")    -- slot 1 is eta_kills by default
  T.eq({ ns.settings.widget.slots[1], ns.settings.widget.slots[2] }, { "eta_kills", "kills" })
  ns.Core.SetSetting("exclude.afk", true)
  Stub.SetAFK(true)                                 -- excluded time: nothing moves
  Stub.Advance(300)
  T.ok(ns.Tokens.IsActive())
  T.eq(ns.Tokens.ctx.kills, 91)
  T.eq((ns.Tokens.Render("kills")), "~91 mobs", "the kills token is visible")
  local tp = rawget(_G, "TruePlayedWidget").tp
  local shown = false
  for i = 1, 3 do
    if tp.slots[i]:IsShown() and (tp.slots[i]:GetText() or ""):find("91 mobs", 1, true) then shown = true end
  end
  T.ok(shown, "the bar shows the count")
  -- more kills: the same ring table (shifted in place)
  Stub.SetAFK(false)
  Kills({ 130, 140 })
  T.ok(ns.char.killRing == ring, "same table")
  T.eq(ring[10], 140)
  Stub.SetAFK(true)
  Stub.Advance(60)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 0.1, format("600 ticks allocated %.3f KB", kb))
  T.eq(Stub.onUpdateCount, 0)
end)
