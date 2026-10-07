local ADDON, ns = ...
-- Activity.lua - the activity states that win over the place of a second (lot 8, A1 and
-- A2): dead or a ghost (state key "x") and professions ("f"). Tracker.ComputeState asks
-- Activity.Override for every state computation (the 1 s TICK and the events) and keeps
-- the place key when it answers nil.
--
-- Precedence: dead > AFK > professions > flight > instance > city > inn > world.
--  * Dead: from PLAYER_DEAD (UnitIsDeadOrGhost("player")) until the resurrection, the
--    ghost run included (not world time). AFK while dead is dead; a hunter's Feign
--    Death is not. Dead time is never excluded (no option).
--  * Professions (a heuristic, see README), when the player is not AFK:
--    1. casting or channelling a profession spell: Herb Gathering, Mining, Skinning,
--       Fishing (channel), First Aid (bandage channel), Disenchant, Pick Lock. Spells are
--       known by ID (every rank listed) and by their localized name (one ID per spell,
--       resolved at login with GetSpellInfo: every rank, every language);
--    2. a few seconds after a gathering, fishing, disenchanting or lockpicking cast ends
--       (C.PROF_GRACE: looting), checked on the tick;
--    3. a trade skill window (TRADE_SKILL_SHOW / CLOSE) or a craft window (CRAFT_SHOW /
--       CLOSE: Enchanting; the hunter's Beast Training is not a profession) is open while
--       the player stands still out of combat (a window left open while running around
--       is not professions time);
--    4. a cast started while such a window is open (crafting), and the next casts of the
--       same spell after it was closed (a "Create all" queue).
--    Professions in a city count as professions, not city.
-- Limits: other ways of crafting (an addon that crafts without the game's windows), a
-- gathering cast not in the list (e.g. "Opening" a chest is not a profession), and the
-- loot of a fishing channel that stopped without a catch (the grace applies) are not
-- told apart. A cast whose end event never came is dropped after C.PROF_CAST_MAX s.
-- CPU / memory: events only (no OnUpdate); Override allocates nothing (the steady tick).
-- The spell names are read once per spell ID (cache), never on the tick.

local C, Util = ns.C, ns.Util
local type, pcall = type, pcall
local GetTime, CreateFrame = GetTime, CreateFrame
local UnitIsDeadOrGhost, UnitIsFeignDeath = UnitIsDeadOrGhost, UnitIsFeignDeath   -- the latter may be nil
local InCombatLockdown, GetUnitSpeed = InCombatLockdown, GetUnitSpeed            -- idem (guarded)
local SafeRead, IsSecret = Util.SafeRead, Util.IsSecret

local Activity = {}
ns.Activity = Activity

local DEAD, PROF = "x", "f"
local GRACE, PLAIN, CRAFT = 1, 2, 3          -- kinds of profession casts

-- Profession spells, every rank (Classic Era IDs): kind. GRACE: the looting that
-- follows keeps the state C.PROF_GRACE s more.
local SPELLS = {
  [2366] = GRACE, [2368] = GRACE, [3570] = GRACE, [11993] = GRACE,    -- Herb Gathering
  [2575] = GRACE, [2576] = GRACE, [3564] = GRACE, [10248] = GRACE,    -- Mining
  [8613] = GRACE, [8617] = GRACE, [8618] = GRACE, [10768] = GRACE,    -- Skinning
  [7620] = GRACE, [7731] = GRACE, [7732] = GRACE, [18248] = GRACE,    -- Fishing (channel)
  [13262] = GRACE,                                                    -- Disenchant
  [1804] = GRACE,                                                     -- Pick Lock
  [746] = PLAIN, [1159] = PLAIN, [3267] = PLAIN, [3268] = PLAIN,      -- First Aid (bandages)
  [7926] = PLAIN, [7927] = PLAIN, [10838] = PLAIN, [10839] = PLAIN,
  [18608] = PLAIN, [18610] = PLAIN,
}
-- One ID per spell name: the localized names (every rank shares its name).
local NAME_IDS = { 2366, 2575, 8613, 7620, 13262, 1804, 746 }
local BEAST_TRAINING = 5149                  -- the hunter's craft window: not a profession

local byName = {}            -- localized name -> kind (built by ResolveNames)
local namesDone = false
local kindOf = {}            -- spellID -> kind or false (cache of Classify)
local beastName = nil        -- localized "Beast Training"

-- State (fields only, no allocation after load)
local st = {
  dead = false,              -- last known UnitIsDeadOrGhost("player") (a failed read keeps it)
  trade = false,             -- a trade skill window is open
  craft = false,             -- a craft window (not Beast Training) is open
  cast = 0, castID = nil, castUntil = 0,     -- profession cast in progress (kind, spell, stale guard)
  chan = 0, chanUntil = 0,                   -- profession channel in progress (kind, stale guard)
  queueID = nil,             -- spell of the last cast started with a window open (craft queue)
  graceUntil = 0,            -- GetTime until which a finished gathering cast still counts
}
Activity.st = st             -- read-only handle for the tests

-- Localized name of a spell ID (guarded; nil when unknown or secret). Events only.
local function SpellName(id)
  local CS = C_Spell
  local fn = CS and CS.GetSpellName
  local ok, name
  if fn then
    ok, name = pcall(fn, id)
  elseif GetSpellInfo then
    ok, name = pcall(GetSpellInfo, id)
  end
  if not ok or IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
  return name
end

local function ResolveNames()
  local all = true
  for i = 1, #NAME_IDS do
    local id = NAME_IDS[i]
    local name = SpellName(id)
    if name then byName[name] = SPELLS[id] else all = false end
  end
  beastName = SpellName(BEAST_TRAINING) or beastName
  namesDone = all and beastName ~= nil
end

-- Kind of a spell cast by the player: GRACE, PLAIN, or nil (not a profession spell).
local function Classify(id)
  if type(id) ~= "number" or IsSecret(id) then return nil end
  local k = kindOf[id]
  if k ~= nil then return k or nil end
  k = SPELLS[id]
  if not k then
    if not namesDone then ResolveNames() end
    local name = SpellName(id)
    k = name and byName[name]
  end
  if k or namesDone then kindOf[id] = k or false end   -- a miss is final once every name is known
  return k or nil
end
Activity._Classify = Classify   -- tests

local function Reeval()
  local T = ns.Tracker
  if T and T.Reevaluate then T.Reevaluate("activity") end
end

local function WindowOpen()
  return st.trade or st.craft
end

-- True while the professions state holds (allocation free: the steady tick).
local function ProfActive(now)
  if st.chan ~= 0 then
    if now <= st.chanUntil then return true end
    st.chan = 0                                  -- its stop event never came
  end
  if st.cast ~= 0 then
    if now <= st.castUntil then return true end
    st.cast = 0
  end
  if now < st.graceUntil then return true end
  if not WindowOpen() then return false end
  -- a window open: only while standing still out of combat
  if InCombatLockdown and InCombatLockdown() then return false end
  if GetUnitSpeed then
    local ok, speed = pcall(GetUnitSpeed, "player")
    if ok and type(speed) == "number" and not IsSecret(speed) and speed > 0 then return false end
  end
  return true
end

-- The activity key that replaces the place key of this second, or nil.
-- afk: the player is AFK (it wins over professions, not over death).
function Activity.Override(afk, now)
  local ok, v = SafeRead(UnitIsDeadOrGhost, "player")
  if ok then
    local dead = v == true
    if dead and UnitIsFeignDeath then
      local okf, fd = SafeRead(UnitIsFeignDeath, "player")
      if okf and fd == true then dead = false end
    end
    st.dead = dead
  end
  if st.dead then return DEAD end
  if afk then return nil end
  if ProfActive(now or GetTime()) then return PROF end
  return nil
end

function Activity.IsDead()
  return st.dead
end

function Activity.IsProf(now)
  return ProfActive(now or GetTime())
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local function OnTradeShow()
  st.trade = true
  Reeval()
end

local function OnTradeClose()
  st.trade = false
  Reeval()
end

-- The craft window of Classic is Enchanting, or the hunter's Beast Training.
local function OnCraftShow()
  local name
  if GetCraftName then
    local ok, v = pcall(GetCraftName)
    if ok and type(v) == "string" and not IsSecret(v) then name = v end
  end
  if beastName == nil then beastName = SpellName(BEAST_TRAINING) end
  st.craft = not (name ~= nil and name == beastName)
  if st.craft then Reeval() end
end

local function OnCraftClose()
  if st.craft then
    st.craft = false
    Reeval()
  end
end

-- A loading screen closes every window and stops every cast.
local function OnEnteringWorld()
  st.trade, st.craft, st.cast, st.chan, st.graceUntil = false, false, 0, 0, 0
  st.castID, st.queueID = nil, nil
end

local function OnDeadOrAlive()
  Reeval()
end

-- Kind of a cast or channel that starts: a profession spell, else a craft when a
-- window is open (or the next item of the craft queue started with it).
local function StartKind(id)
  local k = Classify(id)
  if k then return k end
  if type(id) ~= "number" or IsSecret(id) then return nil end
  if WindowOpen() then
    st.queueID = id
    return CRAFT
  end
  if id == st.queueID then return CRAFT end
  st.queueID = nil
  return nil
end

local function OnCastStart(id)
  local k = StartKind(id)
  if k then
    st.cast, st.castID, st.castUntil = k, id, GetTime() + C.PROF_CAST_MAX
    Reeval()
  else
    st.cast, st.castID = 0, nil
  end
end

local function OnChannelStart(id)
  local k = StartKind(id)
  if k then
    st.chan, st.chanUntil = k, GetTime() + C.PROF_CAST_MAX
    Reeval()
  else
    st.chan = 0
  end
end

local function Grace()
  st.graceUntil = GetTime() + C.PROF_GRACE
end

-- SUCCEEDED (also sent when a channel starts, and for instant casts): a finished
-- gathering cast starts the grace.
local function OnCastSucceeded(id)
  local k
  if st.cast ~= 0 and id == st.castID then
    k = st.cast
    st.cast, st.castID = 0, nil
  else
    k = Classify(id)
  end
  if k == GRACE then Grace() end
  Reeval()
end

-- STOP (after SUCCEEDED, or alone): the cast is over, without grace.
local function OnCastStop(id)
  if st.cast ~= 0 and (id == nil or id == st.castID) then
    st.cast, st.castID = 0, nil
    Reeval()
  end
end

-- INTERRUPTED / FAILED: the cast is over, without grace (a failed gathering attempt).
local function OnCastFailed(id)
  if st.cast ~= 0 and id == st.castID then
    st.cast, st.castID = 0, nil
    Reeval()
  end
end

-- The end of a channel (a fish caught, a bandage applied, or cancelled): grace after
-- Fishing (looting the catch).
local function OnChannelStop()
  if st.chan == 0 then return end
  if st.chan == GRACE then Grace() end
  st.chan = 0
  Reeval()
end

-- Unit events of the player only, on our own frame (RegisterUnitEvent: the game does
-- not dispatch the casts of the other units to it).
local SPELL_EVENTS = {
  UNIT_SPELLCAST_START = OnCastStart,
  UNIT_SPELLCAST_CHANNEL_START = OnChannelStart,
  UNIT_SPELLCAST_SUCCEEDED = OnCastSucceeded,
  UNIT_SPELLCAST_STOP = OnCastStop,
  UNIT_SPELLCAST_INTERRUPTED = OnCastFailed,
  UNIT_SPELLCAST_FAILED = OnCastFailed,
  UNIT_SPELLCAST_CHANNEL_STOP = OnChannelStop,
}
-- unit, castGUID, spellID (Classic Era 1.13+ and later clients)
local function OnSpellEvent(_, event, unit, _castGUID, spellID)
  if unit ~= "player" then return end
  local fn = SPELL_EVENTS[event]
  if fn then fn(spellID) end
end

local BUS_EVENTS = {
  TRADE_SKILL_SHOW = OnTradeShow, TRADE_SKILL_CLOSE = OnTradeClose,
  CRAFT_SHOW = OnCraftShow, CRAFT_CLOSE = OnCraftClose,
  PLAYER_ALIVE = OnDeadOrAlive, PLAYER_UNGHOST = OnDeadOrAlive,
  PLAYER_ENTERING_WORLD = OnEnteringWorld,
}
local BUS_ORDER = { "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "CRAFT_SHOW", "CRAFT_CLOSE", "PLAYER_ALIVE",
                    "PLAYER_UNGHOST", "PLAYER_ENTERING_WORLD" }
local SPELL_ORDER = { "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
                      "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_FAILED",
                      "UNIT_SPELLCAST_CHANNEL_STOP" }

local frame = nil

-- Called by Tracker.Start (each login of the UI). Idempotent.
function Activity.Start()
  ResolveNames()
  for i = 1, #BUS_ORDER do
    local ev = BUS_ORDER[i]
    ns.RegisterEvent(ev, Activity, BUS_EVENTS[ev])
  end
  if frame == nil then
    frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", OnSpellEvent)
    for i = 1, #SPELL_ORDER do
      local ev = SPELL_ORDER[i]
      local ok = frame.RegisterUnitEvent and pcall(frame.RegisterUnitEvent, frame, ev, "player")
      if not ok then pcall(frame.RegisterEvent, frame, ev) end
    end
  end
end
