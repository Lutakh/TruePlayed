-- tests/test_rested.lua - the rested XP cap and the "rested XP full" alert (Rested.lua):
-- the cap (150 % of the level, raised by WoW Forever's Legacy perk Well Rested: its rank
-- read from C_Traits, checked against the perk's spell, found again when it moved, read
-- again after a trait event, not cached while the tree has no config), the tooltip rows
-- (the cap, "full", the perk's note with Shift), the logout save (char.rested) and its
-- repair (false: saved with nothing to watch), the saved data checked when read, another
-- character's estimate (an inn or a capital, elsewhere, the perk, its cap), the alert (off
-- by default; the bar's icon, kept on the screen and hoverable, the option's help and the
-- tooltip's line; this character too; older saves; the window; the max level, XP
-- disabled, a server cap) and no garbage on the tick.
local Stub, T = ...

local DAY = 86400

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- C_Traits as WoW Forever answers it for a character's Legacy config: the Adventure tree
-- (1188), Well Rested on node 110301 (entry 136855, definition 141618, spell 1225478, 5
-- ranks), Frequent Flier on 110300. opts.rank: Well Rested's rank; opts.config = false:
-- no config for the tree; opts.moved: the perk on node 110399, another perk on 110301;
-- opts.none: no Well Rested in the tree; opts.notIn: the config there but the tree's data
-- not in yet (every node answers ID 0). Returns the state (S.reads: GetConfigIDByTreeID
-- calls; S.perk: the perk's node, its rank and staged rank can be changed; S.notIn).
local function InstallTraits(opts)
  opts = opts or {}
  local S = { config = 7001, reads = 0, notIn = opts.notIn }
  if opts.config == false then S.config = nil end
  local perk = { entry = 136855, def = 141618, spell = 1225478, max = 5, rank = opts.rank or 0 }
  local nodes = { [110300] = { entry = 136853, def = 141616, spell = 1225490, max = 1, rank = 1 } }
  if opts.moved then
    nodes[110399] = perk
    nodes[110301] = { entry = 1, def = 2, spell = 999, max = 3, rank = 2 }
  elseif opts.none then
    nodes[110301] = { entry = 1, def = 2, spell = 999, max = 3, rank = 2 }
  else
    nodes[110301] = perk
  end
  S.perk, S.nodes = perk, nodes
  local function By(field, v)
    for _, n in pairs(nodes) do
      if n[field] == v then return n end
    end
    return nil
  end
  _G.C_Traits = {
    GetConfigIDByTreeID = function(tree)
      S.reads = S.reads + 1
      if tree == 1188 then return S.config end
      return nil
    end,
    GetNodeInfo = function(configID, id)
      local n = configID ~= nil and configID == S.config and not S.notIn and nodes[id] or nil
      if not n then return { ID = 0, maxRanks = 0, activeRank = 0, currentRank = 0, entryIDs = {} } end
      return { ID = id, maxRanks = n.max, activeRank = n.rank, currentRank = n.staged or n.rank,
               entryIDs = { n.entry }, activeEntry = n.rank > 0 and { entryID = n.entry, rank = n.rank } or nil }
    end,
    GetEntryInfo = function(_, entryID)
      local n = By("entry", entryID)
      return n and { definitionID = n.def, maxRanks = n.max } or nil
    end,
    GetDefinitionInfo = function(def)
      local n = By("def", def)
      return n and { spellID = n.spell } or nil
    end,
    GetTreeNodes = function(tree)
      local out = {}
      if tree == 1188 then
        for id in pairs(nodes) do out[#out + 1] = id end
      end
      table.sort(out)
      return out
    end,
  }
  return S
end

-- Loads the addon with the widget shown. opts.rest: the rest pool at login; opts.traits:
-- InstallTraits' options (nil: no C_Traits, like a client without Legacy perks).
local function Login(opts)
  opts = opts or {}
  Stub.InstallUI({ ldb = false })
  if opts.rest then Stub.player.rest = opts.rest end
  local S = opts.traits and InstallTraits(opts.traits) or nil
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, S
end

-- Logs out (saving), runs `before` (e.g. another character comes), lets `mutate` change
-- the saved table, lets `offline` seconds pass logged out (the server's /played frozen,
-- no addon loaded), then logs in again (the same world: Stub.player as it is then), with
-- C_Traits as InstallTraits(traits) makes it when given (else none). Returns ns, S.
local function Relog(mutate, offline, before, traits)
  Stub.Logout()
  if before then before() end
  if mutate then mutate(Stub.saved) end
  Stub.Reset({ keepWorld = true })
  if offline then
    Stub.server.frozen = true
    Stub.Advance(offline, offline)
    Stub.server.frozen = false
  end
  if Stub.saved ~= nil then _G.TruePlayedDB = Stub.DeepCopy(Stub.saved) end
  Stub.InstallUI({ ldb = false })
  local S = traits and InstallTraits(traits) or nil
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, S
end

-- GameTooltip lines as { left, right } after Tooltip.Fill.
local function Fill(ns, detailed)
  local tt = GameTooltip
  tt:ClearLines()
  ns.Tooltip.Fill(tt, detailed)
  local out = {}
  for i, l in ipairs(tt._lines or {}) do out[i] = { l[1] or l.left, l[2] or l.right } end
  return out
end

local function Find(lines, left)
  for i = 1, #lines do
    if lines[i][1] == left then return lines[i] end
  end
  return nil
end

-- The first line starting with `prefix` (a whole line: left text).
local function FindPrefix(lines, prefix)
  for i = 1, #lines do
    local l = lines[i][1]
    if type(l) == "string" and l:sub(1, #prefix) == prefix then return l end
  end
  return nil
end

local function Cap(ns)
  local row = Find(Fill(ns, false), "Rested cap")
  return row and row[2]
end

-- New rest pool, as the game reports it (UPDATE_EXHAUSTION, then the XP batch).
local function SetRest(amount)
  Stub.player.rest = amount
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)
end

local function Icon(ns)
  return ns.Bar.frame.tp.restIcon
end

-- Another character's record, as an older login left it.
local function Other(ns, key, name, rested, extra)
  local c = { guid = key, name = name, life = ns.Core.NewLife(), levels = {}, zones = {}, sessions = {},
              ema = ns.Core.NewEma(), rested = rested }
  for k, v in pairs(extra or {}) do c[k] = v end
  ns.db.chars[key] = c
  return c
end

---------------------------------------------------------------------------
-- The cap
---------------------------------------------------------------------------

T.test("rested cap: 150 % of the level on a client without Legacy perks, shown even with no rest", function()
  local ns = Login()
  T.eq(ns.Rested.Rank(), 0)
  T.eq(Cap(ns), "11,400 XP (150%)", "level 10: 7,600 XP x 1.5")
  T.eq(Find(Fill(ns, false), "Rested"), nil, "no rest: no Rested row, the cap row all the same")
  T.no(FindPrefix(Fill(ns, true), "150% of the level"), "no perk: no note with Shift")
end)

T.test("rested cap: Well Rested 3/5 raises it by 12 % (168 %); Shift says what the perk adds", function()
  local ns = Login({ rest = 3800, traits = { rank = 3 } })
  T.eq({ ns.Rested.Rank() }, { 3, 5, true })
  T.eq(Cap(ns), "12,768 XP (168%)", "7,600 x 1.5 x 1.12")
  local lines = Fill(ns, true)
  T.eq(Find(lines, "Rested")[2], "3,800 XP (50%)", "the Rested row is unchanged")
  T.ok(Find(lines, "150% of the level, raised by 12% (Well Rested 3/5)") ~= nil, "the perk's note (addon name)")
  T.eq(Find(Fill(ns, false), "150% of the level, raised by 12% (Well Rested 3/5)"), nil, "no note without Shift")
  -- the game's name of the perk when it gives one
  _G.C_Spell = { GetSpellName = function(id) return id == 1225478 and "Bien repos\195\169" or nil end }
  T.ok(Find(Fill(ns, true), "150% of the level, raised by 12% (Bien repos\195\169 3/5)") ~= nil, "the game's name")
  for r = 0, 5 do
    T.near(ns.Rested.CapFrac(r), 1.5 * (1 + 0.04 * r), 1e-12, "rank " .. r)
  end
  T.eq({ ns.Rested.Cap(95800, 3) }, { 160944, ns.Rested.CapFrac(3) }, "level 41: 160,944 XP")
end)

T.test("rested cap: the rank is cached until a trait event; a staged change does not count", function()
  local ns, S = Login({ traits = { rank = 3 } })
  T.eq(Cap(ns), "12,768 XP (168%)")
  local reads = S.reads
  Fill(ns, false)
  T.eq(S.reads, reads, "cached: no read at the next tooltip")
  S.perk.rank = 5
  T.eq(Cap(ns), "12,768 XP (168%)", "no event yet: still the cached rank")
  Stub.Fire("TRAIT_CONFIG_UPDATED", 7001)
  T.eq(Cap(ns), "13,680 XP (180%)", "read again after the event")
  S.perk.staged = 2                          -- currentRank: a change staged in the frame
  Stub.Fire("TRAIT_NODE_CHANGED", 110301)
  T.eq((ns.Rested.Rank()), 5, "activeRank counts, not the staged currentRank")
  Stub.Fire("PLAYER_ENTERING_WORLD", false, false)
  T.eq((ns.Rested.Rank()), 5)
end)

T.test("rested cap: no config for the tree reads rank 0, read again at the next ask", function()
  local ns, S = Login({ traits = { rank = 2, config = false } })
  T.eq(Cap(ns), "11,400 XP (150%)")
  local reads = S.reads
  Fill(ns, false)
  T.ok(S.reads > reads, "not cached while the tree has no config")
  S.config = 7001                            -- the config comes in, no event
  T.eq(Cap(ns), "12,312 XP (162%)", "rank 2 at the next ask")
  reads = S.reads
  Fill(ns, false)
  T.eq(S.reads, reads, "then cached")
end)

T.test("rested cap: a perk moved to another node is found by its spell; a tree without it reads 0", function()
  local ns = Login({ traits = { rank = 4, moved = true } })
  T.eq({ ns.Rested.Rank() }, { 4, 5, true }, "found on node 110399, not the other perk's rank 2 on 110301")
  T.eq(Cap(ns), "13,224 XP (174%)")
  local S = InstallTraits({ none = true })
  Stub.Fire("TRAIT_CONFIG_UPDATED", 7001)
  T.eq({ ns.Rested.Rank() }, { 0, 5, true }, "no Well Rested in the tree")
  local reads = S.reads
  ns.Rested.Rank()
  T.eq(S.reads, reads, "the tree read without it: cached")
end)

T.test("rested cap: a config whose tree's data is not in yet reads 0, read again at the next ask", function()
  local ns, S = Login({ traits = { rank = 3, notIn = true } })
  T.eq(Cap(ns), "11,400 XP (150%)", "no node answers yet")
  local reads = S.reads
  Fill(ns, false)
  T.ok(S.reads > reads, "not cached: not a tree without the perk")
  S.notIn = false                            -- the data comes in, no event
  T.eq(Cap(ns), "12,768 XP (168%)", "rank 3 at the next ask")
  reads = S.reads
  Fill(ns, false)
  T.eq(S.reads, reads, "then cached")
end)

T.test("rested cap: 'full' once the pool reaches the cap (within 0.1 %), in the tooltip", function()
  local ns = Login({ rest = 11400 })
  T.eq(Cap(ns), "11,400 XP (150%) \194\183 full")
  SetRest(11390)                             -- 0.999 x 11,400 = 11,388.6
  T.eq(Cap(ns), "11,400 XP (150%) \194\183 full", "within 0.1 % of the cap")
  SetRest(11380)
  T.eq(Cap(ns), "11,400 XP (150%)")
  T.no(ns.Rested.SelfFull(), "the alert's own flag stays off while the option is off")
end)

---------------------------------------------------------------------------
-- The logout save and its repair
---------------------------------------------------------------------------

T.test("logout: char.rested keeps the pool, the level's XP, the level, the time, the rest area, the rank", function()
  Login({ rest = 3800, traits = { rank = 3 } })
  Stub.SetResting(true)
  Stub.Advance(5)
  local guid = Stub.player.guid
  local at = time()
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested, { r = 3800, m = 7600, l = 10, at = at, inn = true, k = 3 })
  -- outside a rest area, without the perk: the same table, its inn and k cleared
  local ns = Relog()
  T.eq(ns.char.rested.k, 3, "the save came back")
  InstallTraits({ rank = 0 })
  Stub.Fire("TRAIT_CONFIG_UPDATED", 7001)
  Stub.SetResting(false)
  Stub.Advance(5)
  at = time()
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested, { r = 3800, m = 7600, l = 10, at = at }, "inn and k left out")
end)

-- The saved data of 2026-11-17: a character with Well Rested saved without it (k nil) at
-- a logout whose tree could not be read; the alts read it.
T.test("logout: a rank the tree does not give at the logout keeps the last one read (this session's, else the last save's)", function()
  local ns, S = Login({ rest = 3800, traits = { rank = 4 } })
  local guid = Stub.player.guid
  T.eq(ns.Rested.Rank(), 4, "read while playing")
  -- a trait event clears the cache, and the tree is not readable any more
  Stub.Fire("TRAIT_CONFIG_UPDATED", 7001)
  S.config = nil
  T.eq({ ns.Rested.Rank() }, { 4, 5, false }, "meanwhile: the last rank read, not read")
  T.eq(Find(Fill(ns, false), "Rested cap")[2], "13,224 XP (174%)", "the tooltip keeps it")
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested.k, 4, "saved: the session's last rank")
  -- a session that never reads it (no config from the login to the logout): the last save's
  ns = Relog(nil, nil, nil, { config = false })
  T.eq({ ns.Rested.Rank() }, { 0, 5, false }, "nothing read this session")
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested.k, 4, "saved: the last save's")
  -- read again: the tree's answer wins, rank 0 included (the perk gone)
  ns = Relog(nil, nil, nil, { rank = 0 })
  T.eq({ ns.Rested.Rank() }, { 0, 5, true })
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested.k, nil, "saved: none")
  -- a character without any Legacy perk (never a config): none
  Relog(nil, nil, nil, { config = false })
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested.k, nil, "still none")
end)

-- The in-game report of 2026-11-16: three characters logged out in Orgrimmar (last state
-- "c") were saved with no rest area: the game's IsResting answers false at PLAYER_LOGOUT.
T.test("logout: the rest area is the one seen while playing (the game's false at the logout does not count)", function()
  Login({ rest = 3800 })
  local guid = Stub.player.guid
  Stub.SetResting(true)
  Stub.Advance(5)
  Stub.player.resting = false               -- IsResting at PLAYER_LOGOUT on Forever (no event)
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested.inn, true, "in a capital: kept from the play")
  -- a flag the game clears while leaving the world, with its event: kept too
  local ns = Relog()
  T.eq(ns.char.rested.inn, true, "the save came back")
  Stub.SetResting(true)
  Stub.Advance(5)
  local f = CreateFrame("Frame")
  f:RegisterEvent("PLAYER_LEAVING_WORLD")
  f:SetScript("OnEvent", function()
    Stub.player.resting = false
    Stub.Fire("PLAYER_UPDATE_RESTING")
  end)
  Stub.Logout()
  f:UnregisterAllEvents()
  T.eq(Stub.saved.chars[guid].rested.inn, true, "cleared while leaving: the state before")
  -- left the rest area while playing: not resting at the logout
  Relog()
  Stub.SetResting(true)
  Stub.Advance(5)
  Stub.SetResting(false)
  Stub.Advance(5)
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested.inn, nil, "left it before the logout")
  -- a loading screen in between: read again once in the world
  Relog()
  Stub.Fire("PLAYER_LEAVING_WORLD")
  Stub.player.resting = true
  Stub.Fire("PLAYER_ENTERING_WORLD", false, false)
  Stub.Advance(5)
  Stub.player.resting = false               -- the game's false at the logout again
  Stub.Logout()
  T.eq(Stub.saved.chars[guid].rested.inn, true, "read again after the loading screen")
end)

T.test("logout: false at the max level (nothing to watch, the older snapshot not used), nothing in read-only mode", function()
  Login({ rest = 3800 })
  Stub.Logout()
  local guid = Stub.player.guid
  T.ok(type(Stub.saved.chars[guid].rested) == "table")
  Stub.player.xpDisabled = true              -- the client's max level (Util.IsMaxLevel)
  local ns = Relog()
  T.ok(ns.Tracker.IsMax(), "max level")
  Stub.Logout()
  local c = Stub.saved.chars[guid]
  T.eq(c.rested, false, "false at the max level, the older save replaced")
  -- false: the Tracker's snapshot of the same logout (a full pool) is not used either
  c = Stub.DeepCopy(c)
  c.xpSnap = { level = 10, xp = 0, max = 7600, rest = 11400, at = time() - 60 }
  c.last = { key = "I" }
  T.eq(ns.Rested.Saved(c, {}, c.realm), nil, "nothing to watch")
  c.rested = nil
  T.ok(ns.Rested.Saved(c, {}, c.realm) ~= nil, "without the marker, the older save's way")
  -- read-only: a newer TruePlayed's data is never written, nor the detached copy
  Stub.Reset()
  _G.TruePlayedDB = { schema = 99, settings = {}, chars = {} }
  ns = Login({ rest = 3800 })
  T.ok(ns.readOnly, "read-only")
  T.ok(type(ns.char) == "table", "the detached copy")
  Stub.Logout()
  T.eq(ns.char.rested, nil, "nothing written on the detached copy")
  c = Stub.saved and Stub.saved.chars and Stub.saved.chars[Stub.player.guid]
  T.eq(c and c.rested, nil, "nothing saved")
end)

T.test("repair: a bad char.rested is dropped; a bad rest area or rank alone; false kept", function()
  Login({ rest = 3800 })
  local guid = Stub.player.guid
  local ns = Relog(function(sv)
    sv.chars["Player-1-A"] = { guid = "Player-1-A", rested = { r = "x", m = 7600, l = 10, at = 1 } }
    sv.chars["Player-1-B"] = { guid = "Player-1-B", rested = { r = 10, m = 0, l = 10, at = 1 } }
    sv.chars["Player-1-C"] = { guid = "Player-1-C", rested = 5 }
    sv.chars["Player-1-D"] = { guid = "Player-1-D", rested = { r = 10, m = 7600, l = 10, at = 1, inn = "yes", k = 0 } }
    sv.chars["Player-1-E"] = { guid = "Player-1-E", rested = { r = 10, m = 7600, l = 10, at = 1, inn = true, k = 2.5 } }
    sv.chars["Player-1-F"] = { guid = "Player-1-F", rested = { r = 10, m = 7600, l = 10, at = 1, inn = true, k = 5 } }
    sv.chars["Player-1-G"] = { guid = "Player-1-G", rested = { r = 10, m = 7600, l = 10, at = 1, k = 7 } }
    sv.chars["Player-1-H"] = { guid = "Player-1-H", rested = false }
    sv.chars[guid].rested = { r = -1, m = 7600, l = 10, at = 1 }
  end)
  local chars = ns.db.chars
  T.eq(chars["Player-1-A"].rested, nil, "a pool that is not a number")
  T.eq(chars["Player-1-B"].rested, nil, "no level XP")
  T.eq(chars["Player-1-C"].rested, nil, "not a table")
  T.eq(chars["Player-1-D"].rested, { r = 10, m = 7600, l = 10, at = 1 }, "a bad inn and rank dropped alone")
  T.eq(chars["Player-1-E"].rested, { r = 10, m = 7600, l = 10, at = 1, inn = true }, "a rank that is not whole")
  T.eq(chars["Player-1-F"].rested, { r = 10, m = 7600, l = 10, at = 1, inn = true, k = 5 }, "kept")
  T.eq(chars["Player-1-G"].rested, { r = 10, m = 7600, l = 10, at = 1, k = 7 }, "a later build's rank kept")
  T.eq(chars["Player-1-H"].rested, false, "nothing to watch: kept")
  T.eq(chars[guid].rested, nil, "a negative pool")
end)

T.test("saved data: out of range or of another type is skipped when read (read-only data is not repaired)", function()
  local ns = Login()
  local Saved = ns.Rested.Saved
  local now = time()
  T.eq(Saved({ rested = { r = 10, m = 7600, at = now } }, {}), nil, "no level")
  T.eq(Saved({ rested = { r = 10, m = 7600, l = 0 / 0, at = now } }, {}), nil, "a NaN level")
  T.eq(Saved({ rested = { r = 10, m = 7600, l = 10, at = math.huge } }, {}), nil, "an endless time")
  T.eq(Saved({ rested = { r = 10, m = "7600", l = 10, at = now } }, {}), nil, "a string")
  local snap = { level = 10, xp = 0, max = 7600, rest = 10, at = now }
  T.eq(Saved({ realm = "R", xpSnap = snap }, {}, "R"), { r = 10, m = 7600, l = 10, at = now, k = 0, inn = false, old = true },
    "the snapshot of a character of this realm: an older save (its rank not known)")
  T.eq(Saved({ realm = "R", rested = 5, xpSnap = snap }, {}, "R"), nil, "not a table: neither the snapshot")
  T.eq(Saved({ rested = { r = 10, m = 7600, l = 10, at = now, k = "3", inn = 1 } }, {}),
    { r = 10, m = 7600, l = 10, at = now, k = 0, inn = false, old = false }, "a bad rank reads 0, a bad rest area false")
  T.eq(Saved({ realm = "R", xpSnap = { level = 10, xp = 0, max = 7600, at = now } }, {}, "R"), nil,
    "a snapshot without its pool")
  -- in the list: skipped, no Lua error (the reviewer's case: no level, the option on)
  ns.Core.SetSetting("widget.restAlert", true)
  Other(ns, "Player-1-X", "Xan", { r = 10, m = 7600, at = now })
  Other(ns, "Player-1-Y", "Yul", { r = 15150, m = 10100, l = 12, at = now - 60, inn = true })
  ns.Rested.Recompute()
  Stub.Advance(2)
  T.eq(ns.Rested.Count(), 1, "Yul only")
  T.eq(#Stub.errors, 0, "no Lua error")
end)

---------------------------------------------------------------------------
-- Another character's estimate
---------------------------------------------------------------------------

T.test("estimate: 5 % of the level per 8 h in a rest area, a quarter elsewhere, the perk's percent, up to the cap", function()
  local ns = Login()
  local R = ns.Rested
  local s = { r = 0, m = 10000, l = 12, at = 1000, inn = true, k = 0 }
  T.near((R.Estimate(s, 1000 + 8 * 3600)), 500, 1e-6, "inn: 5 % in 8 h")
  s.inn = false
  T.near((R.Estimate(s, 1000 + 8 * 3600)), 125, 1e-6, "elsewhere: a quarter")
  s.inn, s.k = true, 3
  T.near((R.Estimate(s, 1000 + 8 * 3600)), 560, 1e-6, "Well Rested 3/5: 12 % faster")
  local est, cap, fullAt = R.Estimate(s, 1000 + 30 * DAY)
  T.eq({ est, cap }, { 16800, 16800 }, "up to the perk's cap")
  -- from an empty pool the perk does not change the time to fill it (gain and cap alike)
  T.near(fullAt - 1000, 16800 * 0.999 / (10000 * 0.05 * 1.12 / 28800), 1e-3)
  s.k = 0
  local _, _, fullAt0 = R.Estimate(s, 1000)
  T.near(fullAt0 - 1000, 15000 * 0.999 / (10000 * 0.05 / 28800), 1e-3, "about 10 days")
  T.near(fullAt, fullAt0, 1e-3)
  s.r = 15000
  local _, _, fullNow = R.Estimate(s, 1000)
  T.eq(fullNow, 1000, "already full at the logout")
  T.near((R.Estimate(s, 500)), 15000, 1e-6, "a clock behind the logout: the saved pool")
end)

---------------------------------------------------------------------------
-- The alert
---------------------------------------------------------------------------

T.test("alert: off by default: no icon, no line, nobody counted", function()
  local ns = Login({ rest = 11400 })
  T.eq(ns.settings.widget.restAlert, false)
  Other(ns, "Player-1-A", "Alta", { r = 15150, m = 10100, l = 12, at = time() - 60, inn = true })
  ns.Rested.Recompute()
  T.eq(ns.Rested.Count(), 0)
  T.no(Icon(ns):IsShown(), "no icon")
  T.eq(FindPrefix(Fill(ns, false), "Rested XP full"), nil, "no line")
  local f = ns.Bar.frame
  T.eq({ f:GetClampRectInsets() }, { 0, 0, 0, 0 })
  ns.Core.SetSetting("widget.restAlert", true)
  T.eq(ns.Rested.Count(), 2, "on: this character and Alta")
  T.ok(Icon(ns):IsShown(), "the icon")
  T.eq({ f:GetClampRectInsets() }, { 0, 7, 7, 0 }, "the clamp rect takes the icon's outer half in")
  T.eq({ f:GetHitRectInsets() }, { 0, -7, -7, 0 }, "the hit rect too, while it shows")
  T.eq(FindPrefix(Fill(ns, false), "Rested XP full"), "Rested XP full: this character \194\183 Alta (12)")
  ns.Core.SetSetting("widget.restAlert", false)
  T.eq(ns.Rested.Count(), 0)
  T.no(Icon(ns):IsShown(), "off again: the icon goes")
  T.eq({ f:GetClampRectInsets() }, { 0, 0, 0, 0 }, "the clamp rect back")
  T.eq({ f:GetHitRectInsets() }, { 0, 0, 0, 0 }, "the hit rect back")
  -- the option's "?": what it shows, the estimate, and "Hide at max level"
  local help = {}
  ns.Options.HelpLines.restAlert(nil, function(_, s) help[#help + 1] = s end)
  T.eq(#help, 3)
  T.eq(help[3], "With \"Hide at max level\", the bar and its icon stay hidden at max level.")
end)

T.test("alert: with the bar against the screen's top right corner, the whole icon stays on the screen", function()
  local ns = Login({ rest = 11400 })
  local f = ns.Bar.frame
  f:ClearAllPoints()
  f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
  local _, _, fw, fh = f:GetRect()
  ns.Core.SetSetting("widget.restAlert", true)
  T.ok(Icon(ns):IsShown())
  local l, b, w, h = Icon(ns):GetRect()
  T.near(l + w, UIParent:GetWidth(), 1e-9, "its right edge on the screen's")
  T.near(b + h, UIParent:GetHeight(), 1e-9, "its top on the screen's")
  local fl, fb = f:GetRect()
  T.near(fl + fw, UIParent:GetWidth() - 7, 1e-9, "the bar 7 px in from the right")
  T.near(fb + fh, UIParent:GetHeight() - 7, 1e-9, "and from the top")
end)

T.test("alert: this character's pool reaches the cap in an inn, then is spent", function()
  local ns = Login({ rest = 11000 })
  ns.Core.SetSetting("widget.restAlert", true)
  T.eq(ns.Rested.Count(), 0)
  T.no(Icon(ns):IsShown())
  SetRest(11400)
  T.ok(ns.Rested.SelfFull())
  T.ok(Icon(ns):IsShown(), "full: the icon")
  T.eq(FindPrefix(Fill(ns, false), "Rested XP full"), "Rested XP full: this character")
  SetRest(9000)
  T.no(Icon(ns):IsShown(), "spent: the icon goes")
  T.eq({ ns.Bar.frame:GetHitRectInsets() }, { 0, 0, 0, 0 }, "the hit rect back without the icon")
  T.eq({ ns.Bar.frame:GetClampRectInsets() }, { 0, 7, 7, 0 }, "the clamp rect kept: the bar never moves")
  -- the cap follows the perk's rank
  InstallTraits({ rank = 3 })
  SetRest(11400)
  Stub.Fire("TRAIT_CONFIG_UPDATED", 7001)
  T.no(ns.Rested.SelfFull(), "168 %: 11,400 XP is no longer full")
  T.no(Icon(ns):IsShown())
end)

T.test("alert: another character fills up while you play this one (inn), its name and level in the tooltip", function()
  -- Alta, level 12, logs out empty in an inn
  Stub.player.guid, Stub.player.name, Stub.player.surname = "Player-4619-0000AAAA", "Alta", "Nuit"
  Stub.player.level, Stub.player.max, Stub.player.rest = 12, 10100, 0
  local ns = Login()
  ns.Core.SetSetting("widget.restAlert", true)
  Stub.SetResting(true)
  Stub.Advance(5)
  local alta = time()
  -- nine days later, Lutak logs in
  ns = Relog(nil, 9 * DAY, function()
    local p = Stub.player
    p.guid, p.name, p.surname = "Player-4619-0000BBBB", "Lutak", "Ombrevent"
    p.level, p.max, p.rest, p.resting = 20, 23200, 0, false
  end)
  T.eq(ns.char.name, "Lutak")
  T.ok(ns.db.chars["Player-4619-0000AAAA"].rested ~= nil, "Alta's save")
  T.ok(ns.settings.widget.restAlert, "the option is the account's")
  T.eq(ns.Rested.Count(), 0, "135 % after nine days")
  T.no(Icon(ns):IsShown())
  -- full after 0.999 x 150 % / 5 % x 8 h = 239.76 h
  local full = alta + math.ceil(15150 * 0.999 / (10100 * 0.05 / 28800))
  Stub.Advance(full - time() - 60, 600)
  T.eq(ns.Rested.Count(), 0, "a minute before")
  Stub.Advance(90, 30)
  T.eq(ns.Rested.Count(), 1, "full")
  T.ok(Icon(ns):IsShown(), "the icon")
  T.eq(FindPrefix(Fill(ns, false), "Rested XP full"), "Rested XP full: Alta Nuit (12)")
end)

T.test("alert: elsewhere, the perk, older saves, the window, the max level and this character's own save", function()
  local ns = Login()
  ns.Core.SetSetting("widget.restAlert", true)
  local now = time()
  -- full at its logout, in an inn
  Other(ns, "Player-1-A", "Alta", { r = 15150, m = 10100, l = 12, at = now - 60, inn = true })
  -- logged out elsewhere ten days ago, empty: a quarter of the gain, not full
  Other(ns, "Player-1-B", "Bram", { r = 0, m = 10100, l = 12, at = now - 10 * DAY })
  -- the same in an inn with Well Rested 3/5: full (the perk's cap, reached in ~10 days)
  Other(ns, "Player-1-C", "Cael", { r = 0, m = 10100, l = 13, at = now - 10 * DAY, inn = true, k = 3 })
  -- an older version's save of a character of this realm: xpSnap, in a capital
  -- (char.last), full
  local here = ns.char.realm
  Other(ns, "Player-1-D", "Dorn", nil, { xpSnap = { level = 20, xp = 100, max = 23200, rest = 34800, at = now - DAY },
                                          last = { key = "C" }, level = 20, realm = here })
  -- the same outside a rest area, at 135 % a day ago: 3.75 % more, not full (15 % in a
  -- rest area would fill it)
  Other(ns, "Player-1-E", "Eryn", nil, { xpSnap = { level = 20, xp = 100, max = 23200, rest = 31320, at = now - DAY },
                                          last = { key = "w" }, realm = here })
  -- full, but not played for 91 days
  Other(ns, "Player-1-F", "Fenn", { r = 15150, m = 10100, l = 12, at = now - 91 * DAY, inn = true })
  -- full, saved at the top level
  Other(ns, "Player-1-G", "Gale", { r = 15150, m = 10100, l = 60, at = now - 60, inn = true })
  -- logged out with XP disabled (false), its snapshot full: nothing to watch
  Other(ns, "Player-1-H", "Hale", false, { xpSnap = { level = 12, xp = 0, max = 10100, rest = 15150, at = now - 60 },
                                           last = { key = "I" }, level = 12 })
  -- older saves, full, but a server cap found at their level, or a level gained since
  Other(ns, "Player-1-I", "Ivo", nil, { xpSnap = { level = 20, xp = 58, max = 23200, rest = 34800, at = now - DAY },
                                        last = { key = "C" }, level = 20, capLevel = 20, realm = here })
  Other(ns, "Player-1-J", "Jory", nil, { xpSnap = { level = 59, xp = 0, max = 209800, rest = 314700, at = now - DAY },
                                         last = { key = "C" }, level = 60, realm = here })
  -- this character's own save says full: its live pool (empty) counts instead
  ns.char.rested = { r = 11400, m = 7600, l = 10, at = now - 60, inn = true }
  ns.Rested.Recompute()
  T.eq(ns.Rested.Count(), 3, "Alta, Cael, Dorn")
  T.no(ns.Rested.SelfFull())
  T.eq(ns.Rested.FullText(), "Dorn (20) \194\183 Cael (13) \194\183 Alta (12)", "level first")
  T.ok(Icon(ns):IsShown())
end)

-- The in-game report of 2026-11-16: records of the Forever beta's realms ("Classic Beta
-- PvP", never logged in again) were counted from their older saves.
T.test("alert: an older save counts for a character of this realm only (a beta realm's records do not)", function()
  local ns = Login()
  ns.Core.SetSetting("widget.restAlert", true)
  local now = time()
  local function Snap() return { level = 20, xp = 0, max = 23200, rest = 34800, at = now - DAY } end
  Other(ns, "Player-4619-00E3B465", "Hilarius", nil, { realm = "Classic Beta PvP", level = 20, xpSnap = Snap(),
                                                         last = { key = "w" } })
  Other(ns, "Player-1-A", "Alta", nil, { realm = ns.char.realm, level = 20, xpSnap = Snap(), last = { key = "w" } })
  Other(ns, "Player-1-B", "Bram", nil, { level = 20, xpSnap = Snap(), last = { key = "w" } })   -- no realm
  -- logged out with this version: counted whatever its realm
  Other(ns, "Player-2-C", "Cael", { r = 15150, m = 10100, l = 12, at = now - 60, inn = true }, { realm = "Elsewhere" })
  ns.Rested.Recompute()
  T.eq(ns.Rested.FullText(), "Alta (20) \194\183 Cael (12)")
end)

T.test("alert: past four characters, the first three and +N; this character first", function()
  local ns = Login({ rest = 11400 })
  ns.Core.SetSetting("widget.restAlert", true)
  local now = time()
  for i, name in ipairs({ "Ana", "Bo", "Cy", "Di", "Ed" }) do
    Other(ns, "Player-1-" .. i, name, { r = 15150, m = 10100, l = 10 + i, at = now - 60, inn = true })
  end
  ns.Rested.Recompute()
  T.eq(ns.Rested.Count(), 6)
  T.eq(ns.Rested.FullText(), "this character \194\183 Ed (15) \194\183 Di (14) +3")
end)

---------------------------------------------------------------------------
-- The alts' section (widget.restAlts)
---------------------------------------------------------------------------

-- The rows after the section's title: { left, right } until the next section or the hint.
local function AltRows(lines)
  local out, on = {}, false
  for i = 1, #lines do
    local l = lines[i][1]
    if on and (l == "Character total" or (type(l) == "string" and l:find("^Shift: "))) then break end
    if on and l ~= " " then out[#out + 1] = lines[i] end
    if l == "Alts' rested XP" then on = true end
  end
  return out
end

T.test("alts: off by default; on, every other character's pool over its cap, fullest first", function()
  local ns = Login({ rest = 3800 })
  local now = time()
  local here = ns.char.realm
  -- full at its logout, in an inn
  Other(ns, "Player-1-A", "Alta", { r = 15150, m = 10100, l = 12, at = now - 60, inn = true })
  -- full too (99.93 %, past the 99.9 % mark): the full ones in key order, whatever their share
  Other(ns, "Player-1-0", "Abe", { r = 15140, m = 10100, l = 12, at = now, inn = true })
  -- full with Well Rested 5/5: 180% of the level (1.5 x 1.2 is 1.7999999999999998)
  Other(ns, "Player-1-1", "Ansel", { r = 18180, m = 10100, l = 12, at = now, inn = true, k = 5 })
  -- Well Rested 3/5, 120% of its level in an inn: 168% to reach, 12% faster
  Other(ns, "Player-1-G", "Gwen", { r = 12120, m = 10100, l = 12, at = now, inn = true, k = 3 })
  -- half its cap, in an inn: 7,575 XP to go at 505 per 8 h
  Other(ns, "Player-1-B", "Bram", { r = 7575, m = 10100, l = 12, at = now, inn = true })
  -- an older save of this realm, outside a rest area: 90 % of its cap (31,320 of 34,800)
  Other(ns, "Player-1-C", "Cael", nil, { xpSnap = { level = 20, xp = 0, max = 23200, rest = 31320, at = now },
                                         last = { key = "w" }, level = 20, realm = here })
  -- left out: the max level, the window, a beta realm's older save, this character
  Other(ns, "Player-1-D", "Dorn", { r = 0, m = 10100, l = 60, at = now, inn = true })
  Other(ns, "Player-1-E", "Eryn", { r = 0, m = 10100, l = 12, at = now - 91 * DAY, inn = true })
  Other(ns, "Player-1-F", "Fenn", nil, { xpSnap = { level = 20, xp = 0, max = 23200, rest = 0, at = now },
                                         last = { key = "w" }, level = 20, realm = "Classic Beta PvP" })
  ns.char.rested = { r = 11400, m = 7600, l = 10, at = now, inn = true }
  T.eq(#AltRows(Fill(ns, false)), 0, "off by default: no section")
  T.eq(Find(Fill(ns, false), "Alts' rested XP"), nil)
  ns.Core.SetSetting("widget.restAlts", true)
  T.eq(ns.Rested.Count(), 0, "the alert's option stays off")
  -- the pool and the cap in % of the level. Bram: 7,559.85 XP to 99.9 % at 10,100 x 5 % /
  -- 8 h = 431,135 s; Gwen: 4,831.03 XP to 99.9 % of 16,968 at 12 % more = 245,993 s; Cael
  -- (an older save: no rank known, marked): 3,445.2 XP at a quarter of 23,200 x 5 % / 8 h
  -- = 342,145 s
  T.eq(AltRows(Fill(ns, false)), {
    { "Abe (12)", "150/150% \194\183 full" },
    { "Ansel (12)", "180/180% \194\183 full" },
    { "Alta (12)", "150/150% \194\183 full" },
    { "Cael (20)", "135/150%* \194\183 full in 3d 23h" },
    { "Gwen (12)", "120/168% \194\183 full in 2d 20h" },
    { "Bram (12)", "75/150% \194\183 full in 4d 23h" },
    { "* Not played since this version: Well Rested rank unknown" },
  }, "fullest first; the max level, the window, the beta realm and this character left out")
  T.ok(AltRows(Fill(ns, true))[1] ~= nil, "with Shift too")
  -- the time goes by: Bram's pool grows, floored (the cap only once full)
  Stub.Advance(431134, 3600)
  T.eq(Find(Fill(ns, false), "Bram (12)")[2], "149/150% \194\183 full in <1m")
  Stub.Advance(2)
  T.eq(Find(Fill(ns, false), "Bram (12)")[2], "150/150% \194\183 full")
  -- the option's "?"
  local help = {}
  ns.Options.HelpLines.restAlts(nil, function(_, s) help[#help + 1] = s end)
  T.eq(#help, 1)
  T.match(help[1], "rested XP over its cap")
  -- the checkbox: right under the alert's, above "Hide at max level"; a click turns it off
  ns.Options.Open()
  local controls = rawget(Stub.ui.categories[1].frame, "controls")
  local rec = controls["widget.restAlts"]
  T.ok(rec ~= nil and rec.kind == "check", "a checkbox")
  T.eq(rec.label:GetText(), "Show your alts' rested XP in the tooltip")
  T.eq(rec.index, controls["help.restAlert"].index + 1, "right under the alert's (and its \"?\")")
  T.eq(controls["help.restAlts"].index, rec.index + 1, "its own \"?\"")
  T.eq(controls["widget.hideAtMax"].index, rec.index + 2, "above Hide at max level")
  T.ok(rec.widget:GetChecked(), "checked: the setting is on")
  Stub.RunScript(rec.widget, "OnClick", "LeftButton")
  T.eq(ns.settings.widget.restAlts, false, "a click turns it off")
  T.eq(#AltRows(Fill(ns, false)), 0, "no section any more")
end)

T.test("alts: nobody to show, a note; past ten characters, the first nine and \"+N more\"", function()
  local ns = Login()
  ns.Core.SetSetting("widget.restAlts", true)
  T.eq(AltRows(Fill(ns, false)), { { "No other character to show" } })
  local now = time()
  for i = 1, 12 do
    Other(ns, ("Player-1-%02d"):format(i), "Alt" .. i, { r = 1000 * i, m = 10100, l = 12, at = now, inn = true })
  end
  local rows = AltRows(Fill(ns, false))
  T.eq(#rows, 10, "nine rows and the count")
  T.eq(rows[1][1], "Alt12 (12)", "fullest first")
  T.eq(rows[9][1], "Alt4 (12)")
  T.eq(rows[10][1], "+3 more")
  -- gone: the rows are cleared, nothing kept from them
  for i = 1, 12 do ns.db.chars[("Player-1-%02d"):format(i)] = nil end
  T.eq(ns.Rested.Alts(time()), 0)
  T.eq({ ns.Rested.Alt(1) }, {}, "row 1 empty")
end)

T.test("alert: no garbage and one compare per tick while on; the next fill is found on the tick", function()
  local ns = Login({ rest = 3800 })
  ns.Core.SetSetting("widget.restAlert", true)
  local now = time()
  Other(ns, "Player-1-A", "Alta", { r = 15000, m = 10100, l = 12, at = now, inn = true })
  ns.Rested.Recompute()
  T.eq(ns.Rested.Count(), 0)
  Stub.Advance(10)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 1, ("600 ticks allocated %.2f KB"):format(kb))
  -- 150 XP to go at 10,100 x 5 % / 8 h: about 2.4 h
  Stub.Advance(3 * 3600, 60)
  T.eq(ns.Rested.Count(), 1, "filled on the tick")
end)
