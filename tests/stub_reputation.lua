-- tests/stub_reputation.lua - stub extension for the watched reputation (Reputation.lua: the
-- strip under the bar and its tooltip line). Returns an installer run at the end of every
-- Stub.Reset(); by default NO faction is watched, so every other test, golden and snapshot
-- draws exactly what it drew before the strip existed.
--
-- Stub.rep (reset by every Reset):
--   watched   nil, or { name, reaction (1..8), min, max, value, factionID }: the watched
--             faction (min / max: the standing's thresholds, value: the current standing)
--   secret    true: GetWatchedFactionData / GetWatchedFactionInfo return Stub.SECRET
--   secretFields  { [field] = true }: those fields read as Stub.SECRET (FactionData names:
--             name, reaction, currentReactionThreshold, nextReactionThreshold,
--             currentStanding, factionID)
--   major     { [factionID] = true }: C_Reputation.IsMajorFaction (retail renown)
--   friends   { [factionID] = true }: C_GossipInfo.GetFriendshipReputation gives that ID
--   sex       UnitSex("player") (2 male, 3 female)
-- Stub.SetRepAPI(mode) installs the client's API, Reset installs "forever":
--   "forever"  C_Reputation (GetWatchedFactionData: a new table on every call, as the game;
--              IsMajorFaction, SetWatchedFactionByIndex / ByID), C_GossipInfo
--              (GetFriendshipReputation: a table, friendshipFactionID 0 unless in friends)
--   "era"      GetWatchedFactionInfo (name, standing, min, max, value, factionID; nothing
--              when none) and SetWatchedFactionIndex; no C_Reputation, no C_GossipInfo
--   "eraParagon"  "era" plus a C_Reputation that holds only paragon functions
--              (IsFactionParagon, GetFactionParagonInfo): no watched-faction reader, no setter
--   "none"     none of them
-- Always: FACTION_BAR_COLORS (8 entries with r, g, b fields, the classic values),
-- FACTION_STANDING_LABEL1..8 and their _FEMALE forms (enUS; the female form of 5 is
-- "Friendly (f)" so that tests can tell them apart), SHOW_FACTION_ON_MAINSCREEN, UnitSex.
-- Stub.SetRepGlobals(false) removes the colours, the labels and the checkbox label.
-- Stub.calls.GetWatchedFactionData / GetWatchedFactionInfo count the reads.
-- Helpers (events as the game sends them):
--   Stub.WatchFaction(t)  t = nil (none) or a watched table; UPDATE_FACTION. With
--                         { quiet = true } as 2nd argument: no event (the setter only)
--   Stub.GainRep(n)       n points (negative: a loss) across the standard thresholds;
--                         FACTION_STANDING_CHANGED (factionID, new reaction) on a new
--                         standing, then UPDATE_FACTION
--
-- The game's faction list (the options' picker, the faction chosen in TruePlayed):
--   Stub.rep.factions     the list as a tree (empty by default): headers { name, header =
--                         true, collapsed, child (a sub-header), factionID (a header with its
--                         own reputation, unless noRep), noRep (a header with an ID but no
--                         reputation: isHeaderWithRep false, Era's hasRep false), children =
--                         { ... } } and factions { name, factionID, value (absolute
--                         standing; reaction, min, max follow from the standard thresholds
--                         unless given) }. A collapsed header hides its children from the
--                         list, as the game. Headers without factionID read as ID 0 (two of
--                         them may share a name).
--   Stub.SetFactions(tree)   installs it (Stub.REP_TREE: a sample with a top header, a
--                         collapsed sub-header, a faction at the top level and a collapsed
--                         "Inactive" header)
--   Stub.GainRepID(id, n)    n points on faction id of the tree; UPDATE_FACTION
--   Stub.rep.missing      { [factionID] = true }: GetFactionDataByID / GetFactionInfoByID
--                         return nothing for it (a faction the client cannot read)
--   Stub.rep.visibleOnly  true: GetFactionDataByID / GetFactionInfoByID return nothing for
--                         a faction hidden under a collapsed header (as some clients may)
--   Stub.rep.async        true: ExpandFactionHeader / CollapseFactionHeader queue their
--                         UPDATE_FACTION (a client that sends the burst later) instead of
--                         firing it at once; Stub.FlushFactionEvents() fires the queued
--                         ones and returns how many
--   "forever": C_Reputation.GetNumFactions / GetFactionDataByIndex / GetFactionDataByID /
--   ExpandFactionHeader / CollapseFactionHeader (UPDATE_FACTION fired synchronously unless
--   async, as a burst the addon must ignore while it walks); "era": the globals
--   GetNumFactions / GetFactionInfo / GetFactionInfoByID / ExpandFactionHeader /
--   CollapseFactionHeader. Stub.calls.Expand / Collapse / ListReads count them.

-- The standard standings (Classic): [reaction] = { min, max }.
local THRESHOLDS = {
  { -42000, -6000 }, { -6000, -3000 }, { -3000, 0 }, { 0, 3000 }, { 3000, 9000 },
  { 9000, 21000 }, { 21000, 42000 }, { 42000, 42999 },
}

local COLORS = {
  { 0.8, 0.3, 0.22 }, { 0.8, 0.3, 0.22 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
  { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 },
}

-- Classic Era's list globals (installed by "era" / "eraParagon" only).
local ERA_LIST = { "GetNumFactions", "GetFactionInfo", "GetFactionInfoByID", "ExpandFactionHeader",
                   "CollapseFactionHeader" }

local LABELS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

-- A sample of the game's list: Classic (open) > Alliance (collapsed sub-header) >
-- Stormwind, Darnassus; Argent Dawn under Classic; Inactive (collapsed) > Booty Bay.
local function Tree()
  return {
    { name = "Classic", header = true, children = {
        { name = "Alliance", header = true, child = true, collapsed = true, children = {
            { name = "Stormwind", factionID = 72, value = 4234 },
            { name = "Darnassus", factionID = 69, value = 10000 },
        } },
        { name = "Argent Dawn", factionID = 529, value = 1500 },
    } },
    { name = "Inactive", header = true, collapsed = true, children = {
        { name = "Booty Bay", factionID = 21, value = 30000 },
    } },
  }
end

return function(Stub)
  Stub.rep = { watched = nil, secret = false, secretFields = {}, major = {}, friends = {}, sex = 2 }
  Stub.calls.GetWatchedFactionData = 0
  Stub.calls.GetWatchedFactionInfo = 0
  Stub.REP_THRESHOLDS = THRESHOLDS

  local function Field(name, v)
    if Stub.rep.secretFields[name] then return Stub.SECRET end
    return v
  end

  local function GetWatchedFactionData()
    Stub.calls.GetWatchedFactionData = Stub.calls.GetWatchedFactionData + 1
    local r = Stub.rep
    if r.secret then return Stub.SECRET end
    local w = r.watched
    if w == nil then return nil end
    return {
      factionID = Field("factionID", w.factionID or 0), name = Field("name", w.name or ""),
      description = "", reaction = Field("reaction", w.reaction or 4),
      currentReactionThreshold = Field("currentReactionThreshold", w.min or 0),
      nextReactionThreshold = Field("nextReactionThreshold", w.max or 0),
      currentStanding = Field("currentStanding", w.value or 0),
      atWarWith = false, canToggleAtWar = false, isChild = false, isHeader = false,
      isHeaderWithRep = false, isCollapsed = false, isWatched = true, hasBonusRepGain = false,
      canSetInactive = false, isAccountWide = false,
    }
  end

  local function GetWatchedFactionInfo()
    Stub.calls.GetWatchedFactionInfo = Stub.calls.GetWatchedFactionInfo + 1
    local r = Stub.rep
    if r.secret then return Stub.SECRET end
    local w = r.watched
    if w == nil then return nil end
    return Field("name", w.name), Field("reaction", w.reaction), Field("currentReactionThreshold", w.min),
      Field("nextReactionThreshold", w.max), Field("currentStanding", w.value), Field("factionID", w.factionID)
  end

  local function Setter() end   -- the game's setters (hooked by the addon)

  function Stub.SetRepAPI(mode)
    if mode == "forever" then
      rawset(_G, "C_Reputation", {
        GetWatchedFactionData = GetWatchedFactionData,
        IsMajorFaction = function(id) return Stub.rep.major[id] == true end,
        SetWatchedFactionByIndex = Setter, SetWatchedFactionByID = Setter,
        GetNumFactions = function() return Stub.repList.GetNumFactions() end,
        GetFactionDataByIndex = function(i) return Stub.repList.GetFactionDataByIndex(i) end,
        GetFactionDataByID = function(id) return Stub.repList.GetFactionDataByID(id) end,
        ExpandFactionHeader = function(i) return Stub.repList.ExpandFactionHeader(i) end,
        CollapseFactionHeader = function(i) return Stub.repList.CollapseFactionHeader(i) end,
      })
      for _, g in ipairs(ERA_LIST) do rawset(_G, g, nil) end
      rawset(_G, "C_GossipInfo", {
        GetFriendshipReputation = function(id)
          return { friendshipFactionID = Stub.rep.friends[id] and id or 0, standing = 0, maxRep = 0,
                   name = "", text = "", texture = 0, reaction = "", reactionThreshold = 0 }
        end,
      })
      rawset(_G, "GetWatchedFactionInfo", nil)
      rawset(_G, "SetWatchedFactionIndex", nil)
    elseif mode == "era" or mode == "eraParagon" then
      if mode == "eraParagon" then
        rawset(_G, "C_Reputation", {
          IsFactionParagon = function() return false end,
          GetFactionParagonInfo = function() return nil end,
        })
      else
        rawset(_G, "C_Reputation", nil)
      end
      rawset(_G, "C_GossipInfo", nil)
      rawset(_G, "GetWatchedFactionInfo", GetWatchedFactionInfo)
      rawset(_G, "SetWatchedFactionIndex", Setter)
      for _, g in ipairs(ERA_LIST) do
        rawset(_G, g, function(...) return Stub.repList[g](...) end)
      end
    else
      rawset(_G, "C_Reputation", nil)
      rawset(_G, "C_GossipInfo", nil)
      rawset(_G, "GetWatchedFactionInfo", nil)
      rawset(_G, "SetWatchedFactionIndex", nil)
      for _, g in ipairs(ERA_LIST) do rawset(_G, g, nil) end
    end
  end

  function Stub.SetRepGlobals(on)
    if on then
      local colors = {}
      for i, c in ipairs(COLORS) do colors[i] = { r = c[1], g = c[2], b = c[3] } end
      rawset(_G, "FACTION_BAR_COLORS", colors)
      rawset(_G, "SHOW_FACTION_ON_MAINSCREEN", "Show as Experience Bar")
    else
      rawset(_G, "FACTION_BAR_COLORS", nil)
      rawset(_G, "SHOW_FACTION_ON_MAINSCREEN", nil)
    end
    for i, label in ipairs(LABELS) do
      rawset(_G, "FACTION_STANDING_LABEL" .. i, on and label or nil)
      rawset(_G, "FACTION_STANDING_LABEL" .. i .. "_FEMALE", on and (i == 5 and "Friendly (f)" or label) or nil)
    end
  end

  rawset(_G, "UnitSex", function(unit)
    if unit == "player" then return Stub.rep.sex end
    return 1
  end)
  Stub.SetRepAPI("forever")
  Stub.SetRepGlobals(true)

  Stub.rep.factions = {}
  Stub.rep.missing = {}
  Stub.rep.visibleOnly, Stub.rep.async, Stub.rep.queued = false, false, 0
  Stub.calls.Expand, Stub.calls.Collapse, Stub.calls.ListReads = 0, 0, 0
  Stub.REP_TREE = Tree

  local function ReactionOf0(value)
    for i = #THRESHOLDS, 1, -1 do
      if value >= THRESHOLDS[i][1] then return i end
    end
    return 1
  end

  -- Fields of a faction node: reaction, min, max, value.
  local function Fields(n)
    local v = n.value or 0
    local r = n.reaction or ReactionOf0(v)
    local th = THRESHOLDS[r]
    return r, n.min or th[1], n.max or th[2], v
  end

  -- The visible rows (a collapsed header hides its children).
  local function Visible()
    local out = {}
    local function Walk(list)
      for _, n in ipairs(list) do
        out[#out + 1] = n
        if n.header and not n.collapsed and n.children then Walk(n.children) end
      end
    end
    Walk(Stub.rep.factions)
    return out
  end

  local function FindID(id, list)
    for _, n in ipairs(list or Stub.rep.factions) do
      if n.factionID == id then return n end
      if n.children then
        local f = FindID(id, n.children)
        if f then return f end
      end
    end
    return nil
  end
  Stub.FindFaction = FindID

  local function Data(n)
    local r, mn, mx, v = Fields(n)
    return {
      factionID = n.factionID or 0, name = n.name, description = "", reaction = r,
      currentReactionThreshold = mn, nextReactionThreshold = mx, currentStanding = v,
      atWarWith = false, canToggleAtWar = false, isChild = n.child == true, isHeader = n.header == true,
      isHeaderWithRep = n.header == true and n.factionID ~= nil and not n.noRep, isCollapsed = n.collapsed == true,
      isWatched = false, hasBonusRepGain = false, canSetInactive = false, isAccountWide = false,
    }
  end

  local function Info(n)
    local r, mn, mx, v = Fields(n)
    return n.name, "", r, mn, mx, v, false, false, n.header == true, n.collapsed == true,
      n.factionID ~= nil and not n.noRep, false, n.child == true, n.factionID
  end

  local function Toggle(i, collapsed)
    local n = Visible()[i]
    if n and n.header then
      n.collapsed = collapsed
      if collapsed then Stub.calls.Collapse = Stub.calls.Collapse + 1 else Stub.calls.Expand = Stub.calls.Expand + 1 end
      if Stub.rep.async then
        Stub.rep.queued = Stub.rep.queued + 1  -- sent later (Stub.FlushFactionEvents)
      else
        Stub.Fire("UPDATE_FACTION")          -- the game's burst (synchronous here)
      end
    end
  end

  function Stub.FlushFactionEvents()
    local n = Stub.rep.queued
    Stub.rep.queued = 0
    for _ = 1, n do Stub.Fire("UPDATE_FACTION") end
    return n
  end

  -- A faction of the tree hidden under a collapsed header (Stub.rep.visibleOnly).
  local function Hidden(id)
    if not Stub.rep.visibleOnly then return false end
    for _, n in ipairs(Visible()) do
      if n.factionID == id then return false end
    end
    return true
  end

  local list = {
    GetNumFactions = function()
      Stub.calls.ListReads = Stub.calls.ListReads + 1
      return #Visible()
    end,
    GetFactionDataByIndex = function(i)
      local n = Visible()[i]
      return n and Data(n) or nil
    end,
    GetFactionDataByID = function(id)
      if Stub.rep.missing[id] or Hidden(id) then return nil end
      local n = FindID(id)
      return n and Data(n) or nil
    end,
    ExpandFactionHeader = function(i) Toggle(i, false) end,
    CollapseFactionHeader = function(i) Toggle(i, true) end,
    GetFactionInfo = function(i)
      local n = Visible()[i]
      if n then return Info(n) end
      return nil
    end,
    GetFactionInfoByID = function(id)
      if Stub.rep.missing[id] or Hidden(id) then return nil end
      local n = FindID(id)
      if n then return Info(n) end
      return nil
    end,
  }
  Stub.repList = list

  function Stub.SetFactions(tree)
    Stub.rep.factions = tree or {}
  end

  function Stub.GainRepID(id, n)
    local f = FindID(id)
    if not f then return end
    local v = (f.value or 0) + n
    if v > 42999 then v = 42999 elseif v < -42000 then v = -42000 end
    f.value = v
    f.reaction, f.min, f.max = nil, nil, nil
    Stub.Fire("UPDATE_FACTION")
  end

  function Stub.WatchFaction(t, opts)
    Stub.rep.watched = t
    if not (opts and opts.quiet) then Stub.Fire("UPDATE_FACTION") end
  end

  local function ReactionOf(value)
    for i = #THRESHOLDS, 1, -1 do
      if value >= THRESHOLDS[i][1] then return i end
    end
    return 1
  end

  function Stub.GainRep(n)
    local w = Stub.rep.watched
    if not w then return end
    local v = w.value + n
    if v > 42999 then v = 42999 elseif v < -42000 then v = -42000 end
    w.value = v
    local r = ReactionOf(v)
    if r ~= w.reaction then
      w.reaction = r
      w.min, w.max = THRESHOLDS[r][1], THRESHOLDS[r][2]
      Stub.Fire("FACTION_STANDING_CHANGED", w.factionID, r)
    end
    Stub.Fire("UPDATE_FACTION")
  end
end
