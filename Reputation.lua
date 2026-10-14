local ADDON, ns = ...
local C, Util = ns.C, ns.Util

-- Reputation.lua - the followed faction: its standing for the bar (the strip under the XP
-- track, or the whole main bar when widget.main = "rep": Bar.lua, BarSkin.lua), its tooltip
-- line and its detailed tooltip (Tooltip.lua), the faction picker of the options
-- (RepOptions.lua) and the reputation rate (gains per hour, time to the next standing:
-- Tokens.lua, Tooltip.lua).
--
-- The faction: the one chosen in TruePlayed's options for this character (char.rep.id),
-- else the one the game watches (the player ticks "Show as Experience Bar" in the game's
-- Reputation panel; that is the default, char.rep.id nil). TruePlayed never changes the
-- game's watched faction: the choice is TruePlayed's own. A chosen faction that cannot be
-- read falls back on the game's watched one, and Rep.Detail says so (the tooltip tells);
-- that one is shown without a rate (not measured: the chosen one's rate and session gain
-- wait for it to read again).
--
-- Data: C_Reputation.GetFactionDataByID (chosen) / GetWatchedFactionData (WoW Forever and
-- the modern engine: a table, nil or factionID 0 or name "" when no faction is watched),
-- else GetFactionInfoByID / GetWatchedFactionInfo (Classic Era). Every value is
-- type-checked and tested with Util.IsSecret before any comparison; a failed, secret or
-- incomplete read shows nothing. Exalted (reaction 8, MAX_REACTION) is a full bar without
-- numbers; below it, thresholds that leave no room (max <= min) show nothing. Retail-only
-- systems show nothing (renown / major factions, friendships: their support belongs to the
-- retail branch); a paragon faction is Exalted (full).
--
-- Reads: on events only, while something shows the reputation (widget.rep: the strip and
-- the tooltip line; widget.main = "rep": the main bar; a reputation token in a slot of the
-- bar, of the max-level slots or of the shown mini display): UPDATE_FACTION,
-- FACTION_STANDING_CHANGED (registered through the bus, which tolerates a client without
-- it) and PLAYER_ENTERING_WORLD, plus a post-hook on the game's own watched-faction setters.
-- A read keeps the API's numbers and name string only and sends REP_CHANGED when anything
-- shown changed. Nothing runs on TICK but the rate's clock (Rep.Advance); no OnUpdate.
--
-- The rate (XP parity, Tracker.lua / Stats.lua): a gain is a positive difference of the
-- absolute standing (currentStanding) of the measured faction between two reads; a loss
-- does not count, the chat text (CHAT_MSG_COMBAT_FACTION_CHANGE) is never read (secret in
-- instances on 12.x, parsing it is not allowed: SPEC 2.3), and the first read of a load (or
-- after the reads were off) only takes a new base. Another faction takes a new base and
-- starts the rate over. One EMA per exclusion mask (char.rep.e[mask + 1] = { a, d }: points,
-- counted seconds), decayed like the XP one by Tracker's AdvanceRate (Rep.Advance, the time
-- of state k) with settings.rateTau; past C.XP_STALL counted non-AFK seconds without a gain
-- (char.rep.n) the rate is frozen (status "stalled": neither decays nor grows) until the next
-- gain; a value from C.WARMUP_MIN counted seconds ("warming"), "ok" from C.WARMUP_FULL.
-- Persisted per character in char.rep = { id, f, v, e, n, s, t } (chosen faction, measured
-- faction, last absolute standing, EMAs, seconds without a gain, gain of the session t0 =
-- t), created at the first measure, repaired by Core.RepairChar; nothing is written in
-- read-only mode. Rep.Advance and the getters allocate nothing (TICK path).
--
-- The faction list of the picker (Rep.ListFactions, when the menu opens): every collapsed
-- header of the game's list is expanded, the list read, then those headers are collapsed
-- again, last first, found again by their ID (or name) and rank: the game's panel comes
-- back as the player left it. One read follows the walk. Our own UPDATE_FACTION burst is
-- ignored while we walk (busy) when the client sends it at once; a client that queues it
-- gets it after the walk as plain reads (cheap: nothing changed, no REP_CHANGED, no new
-- base).

local type, pcall, math_floor, math_exp = type, pcall, math.floor, math.exp

local Rep = {}
ns.Rep = Rep

local MAX_REACTION = 8
Rep.MAX_REACTION = MAX_REACTION

-- The classic standings: the first point of each (1 Hated .. 8 Exalted, absolute values of
-- currentStanding) and the last point of Exalted. The API gives the current standing's
-- thresholds only; the later ones are these when the current one matches them.
local STARTS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }
Rep.STARTS = STARTS
Rep.CAP = 42999

-- The classic standing colours: the game's FACTION_BAR_COLORS where it lacks it (or an
-- entry), by reaction (1 Hated .. 8 Exalted).
local COLORS = {
  { 0.8, 0.3, 0.22 }, { 0.8, 0.3, 0.22 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
  { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 },
}
Rep.COLORS = COLORS

local STALL = C.XP_STALL
local WARMUP_MIN, WARMUP_FULL = C.WARMUP_MIN, C.WARMUP_FULL
local INCLUDED, IS_AFK = C.INCLUDED, C.IS_AFK
local REP_TOKENS = { reph = true, rep_eta = true }

-- What is shown (Rep.Has / Rep.Get / Rep.Detail): numbers, the API's name string and two
-- constant strings.
local has, shown = false, false   -- a faction with valid data; and widget.rep or the main bar
local cName, cId, cReact = nil, 0, 0
local cValue, cSpan = 0, 0         -- points inside the standing, points of the standing
local cFull = false                -- Exalted: a full bar, no numbers
local cAbs, cMin, cMax = nil, nil, nil   -- absolute standing and thresholds (nil: unknown)
local cSrc, cFallback = "game", false    -- whose faction: "game" or "chosen"; chosen unreadable
local cStd = false                 -- the current standing has the classic thresholds

local enabled = false              -- events registered (something shows the reputation)
local hooked = false               -- watched-faction setters hooked (once, never undone)
local busy = false                 -- the picker walks the game's list (our own events)
local based = nil                  -- char record whose base the reads took in this load
local friendId, friendOut = false, false   -- last faction looked up for retail systems

-- Scratch of one read.
local rName, rId, rReact, rMin, rMax, rVal

local IsSecret = Util.IsSecret

-- v when it can be read; false when it is secret (never a valid field: the checks below
-- refuse it), nil when absent. The secret test comes first (Util.SafeRead's rule).
local function Plain(v)
  if IsSecret(v) then return false end
  return v
end

local function IsNum(v)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function ClearRead()
  rName, rId, rReact, rMin, rMax, rVal = nil, nil, nil, nil, nil, nil
end

-- Fields of a FactionData table (pcall'd: a protected table raises on index).
local function FromData(d)
  rName, rId, rReact = Plain(d.name), Plain(d.factionID), Plain(d.reaction)
  rMin, rMax = Plain(d.currentReactionThreshold), Plain(d.nextReactionThreshold)
  rVal = Plain(d.currentStanding)
end

-- A FactionData from fn(arg) (pcall'd), into the scratch.
local function ReadData(fn, arg)
  local ok, d = pcall(fn, arg)
  if not ok or IsSecret(d) or type(d) ~= "table" then return false end
  if not pcall(FromData, d) then
    ClearRead()
    return false
  end
  return true
end

local function ReadEra(fn)
  local ok, name, standing, mn, mx, value, id = pcall(fn)
  if not ok then return false end
  rName, rReact, rMin, rMax, rVal, rId = Plain(name), Plain(standing), Plain(mn), Plain(mx), Plain(value), Plain(id)
  return true
end

-- Classic Era's GetFactionInfoByID: name, description, standing, min, max, value, ...,
-- factionID (14th).
local function ReadEraByID(fn, id)
  local ok, name, _, standing, mn, mx, value, _, _, _, _, _, _, _, fid = pcall(fn, id)
  if not ok then return false end
  rName, rReact, rMin, rMax, rVal = Plain(name), Plain(standing), Plain(mn), Plain(mx), Plain(value)
  rId = Plain(fid)
  if rId == nil then rId = id end
  return true
end

-- friendshipFactionID of a C_GossipInfo.GetFriendshipReputation table (pcall'd).
local function FriendshipId(t)
  return Plain(t.friendshipFactionID)
end

-- Renown (a major faction) or a friendship: retail systems, not drawn here. Looked up
-- once per faction (a faction keeps its kind).
local function RetailOnly(api, id)
  if id == friendId then return friendOut end
  local out = false
  local f = type(api) == "table" and api.IsMajorFaction
  if type(f) == "function" then
    local ok, v = pcall(f, id)
    if ok and not IsSecret(v) and v == true then out = true end
  end
  if not out then
    local G = C_GossipInfo
    local g = type(G) == "table" and G.GetFriendshipReputation
    if type(g) == "function" then
      local ok, t = pcall(g, id)
      if ok and type(t) == "table" and not IsSecret(t) then
        local okf, fid = pcall(FriendshipId, t)
        if okf and IsNum(fid) and fid > 0 then out = true end
      end
    end
  end
  friendId, friendOut = id, out
  return out
end

-- The faction of the scratch: shown, name, id, reaction, value, span, full, then the
-- absolute standing and thresholds when they are numbers (nil otherwise).
local function Evaluate(api)
  local name = rName
  if type(name) ~= "string" or name == "" then return false end
  local id = rId
  if id ~= nil then
    if not IsNum(id) or id == 0 then return false end     -- 0: nothing watched (modern); secret
  else
    id = 0                                                 -- older Era clients: no ID
  end
  local r = rReact
  if not IsNum(r) then return false end
  r = math_floor(r)
  if r < 1 or r > MAX_REACTION then return false end
  if id ~= 0 and RetailOnly(api, id) then return false end
  local mn, mx, v = rMin, rMax, rVal
  local nums = IsNum(mn) and IsNum(mx) and IsNum(v)
  local abs = nums and math_floor(v + 0.5) or nil
  if r == MAX_REACTION then
    if nums then return true, name, id, r, 0, 0, true, abs, math_floor(mn + 0.5), math_floor(mx + 0.5) end
    return true, name, id, r, 0, 0, true
  end
  if not nums or mx <= mn then return false end
  local span = math_floor(mx - mn + 0.5)
  if span <= 0 then return false end
  local lo = math_floor(mn + 0.5)
  v = math_floor(v - mn + 0.5)
  if v < 0 then v = 0 elseif v > span then v = span end
  return true, name, id, r, v, span, false, abs, lo, lo + span
end

---------------------------------------------------------------------------
-- The character's record (char.rep) and the rate
---------------------------------------------------------------------------

local function Settings()
  local s = ns.settings
  return type(s) == "table" and s or nil
end

-- The chosen faction ID of the current character (nil: the game's watched faction).
local function ChosenId()
  local char = ns.char
  local r = type(char) == "table" and char.rep or nil
  local id = type(r) == "table" and r.id or nil
  if IsNum(id) and id >= 1 then return id end
  return nil
end

local function NewEma()
  local e = {}
  for m = 1, 8 do e[m] = { a = 0, d = 0 } end
  return e
end

-- char.rep, created (with its EMAs) when missing. Events and the options only.
local function Record(char)
  local r = char.rep
  if type(r) ~= "table" then
    r = {}
    char.rep = r
  end
  if type(r.e) ~= "table" then r.e = NewEma() end
  return r
end

-- The record when it measures the faction shown, else nil (no rate for another one).
local function Measured()
  if not has or cId == 0 then return nil end
  local char = ns.char
  local r = type(char) == "table" and char.rep or nil
  if type(r) ~= "table" or r.f ~= cId or type(r.e) ~= "table" then return nil end
  return r
end

local function SessionT0()
  local s = ns.session
  return type(s) == "table" and s.t0 or nil
end

-- A gain of d points: the stall is over (an EMA that remembers less than this gain held
-- nothing but time without a gain: it restarts, as the XP one), the numerator of every
-- mask grows, and the session's gain.
local function Gain(r, d)
  local e = r.e
  local n = r.n
  if type(n) == "number" and n > STALL then
    for m = 1, 8 do
      local x = e[m]
      if x.a < d then x.a, x.d = 0, 0 end
    end
  end
  r.n = 0
  for m = 1, 8 do
    local x = e[m]
    x.a = x.a + d
  end
  local t0 = SessionT0()
  if r.t ~= t0 then r.t, r.s = t0, 0 end
  r.s = (type(r.s) == "number" and r.s or 0) + d
end

-- The absolute standing `abs` of faction `fid` was just read.
local function Measure(fid, abs)
  if ns.readOnly or not IsNum(abs) or not IsNum(fid) or fid <= 0 then return end
  local char = ns.char
  if type(char) ~= "table" then return end
  local r = Record(char)
  if r.f ~= fid then
    -- another faction (or the first one): a new base, the rate starts over
    r.f, r.v, r.n = fid, abs, 0
    for m = 1, 8 do
      local x = r.e[m]
      x.a, x.d = 0, 0
    end
    r.s, r.t = 0, SessionT0()
    based = char
    return
  end
  local prev = r.v
  r.v = abs
  if based ~= char then
    based = char                                -- first read of this load: a new base only
    return
  end
  if IsNum(prev) and abs > prev then Gain(r, abs - prev) end   -- a loss does not count
end

-- Decays the EMA of every mask that includes state k over dt seconds (Tracker's DecayEma).
local function Decay(e, dt, k)
  local s = Settings()
  local tau = s and s.rateTau
  if type(tau) ~= "number" or tau < 60 then tau = 3600 end
  local f = math_exp(-dt / tau)
  local g = tau * (1 - f)
  for m = 0, 7 do
    if INCLUDED[m][k] then
      local x = e[m + 1]
      x.a = x.a * f
      x.d = x.d * f + g
    end
  end
end

---------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------

-- The chosen faction into the scratch (modern: GetFactionDataByID; Era: GetFactionInfoByID).
local function ReadChosen(api, modern, id)
  if modern then
    local fn = api.GetFactionDataByID
    return type(fn) == "function" and ReadData(fn, id)
  end
  local fn = GetFactionInfoByID
  return type(fn) == "function" and ReadEraByID(fn, id)
end

-- Reads the followed faction (when on), measures it, and sends REP_CHANGED when anything
-- shown changed.
local function Update()
  if busy then return end
  local on = false
  local name, id, r, v, span, full, abs, mn, mx
  local src, fb = "game", false
  if enabled then
    local api = C_Reputation
    local modern = type(api) == "table" and type(api.GetWatchedFactionData) == "function"
    local chosen = ChosenId()
    if chosen then
      ClearRead()
      if ReadChosen(api, modern, chosen) then
        on, name, id, r, v, span, full, abs, mn, mx = Evaluate(modern and api or nil)
      end
      if on then src = "chosen" else fb = true end
    end
    if not on then
      ClearRead()
      if modern then
        if ReadData(api.GetWatchedFactionData) then
          on, name, id, r, v, span, full, abs, mn, mx = Evaluate(api)
        end
      else
        local fn = GetWatchedFactionInfo
        if type(fn) == "function" and ReadEra(fn) then
          on, name, id, r, v, span, full, abs, mn, mx = Evaluate(nil)
        end
      end
    end
    ClearRead()
  end
  if not on then name, id, r, v, span, full, abs, mn, mx, src = nil, 0, 0, 0, 0, false, nil, nil, nil, "game" end
  local s = Settings()
  local w = s and s.widget
  local sh = on and type(w) == "table" and (w.rep == true or w.main == "rep") or false
  local std = on and mn ~= nil and mn == STARTS[r] and (r == MAX_REACTION or mx == STARTS[r + 1]) or false
  -- the game's faction shown in place of an unreadable chosen one is not measured: the
  -- chosen one keeps its base, rate and session gain until it reads again
  if on and not fb then Measure(id, abs) end
  if on ~= has or sh ~= shown or name ~= cName or id ~= cId or r ~= cReact or v ~= cValue or span ~= cSpan
      or full ~= cFull or abs ~= cAbs or src ~= cSrc or fb ~= cFallback then
    has, shown, cName, cId, cReact, cValue, cSpan, cFull = on, sh, name, id, r, v, span, full
    cAbs, cMin, cMax, cSrc, cFallback, cStd = abs, mn, mx, src, fb, std
    ns.SendMessage("REP_CHANGED")
  else
    cMin, cMax, cStd = mn, mx, std
  end
end

local function OnEvent()
  Update()
end

-- Post-hook of the game's watched-faction setters (the Reputation panel's checkbox).
local function OnWatchSet()
  if enabled then Update() end
end

-- Each setter the client has is hooked on its own, whatever else exists (a C_Reputation
-- table may hold only paragon functions next to Classic Era's global setter).
local function Hook()
  if hooked or type(hooksecurefunc) ~= "function" then return end
  hooked = true
  local api = C_Reputation
  if type(api) == "table" then
    if type(api.SetWatchedFactionByIndex) == "function" then
      pcall(hooksecurefunc, api, "SetWatchedFactionByIndex", OnWatchSet)
    end
    if type(api.SetWatchedFactionByID) == "function" then
      pcall(hooksecurefunc, api, "SetWatchedFactionByID", OnWatchSet)
    end
  end
  -- Classic Era's global setter, by name (no global read): absent, hooksecurefunc raises
  -- and pcall keeps it quiet
  pcall(hooksecurefunc, "SetWatchedFactionIndex", OnWatchSet)
end

local function SetEnabled(on)
  if on == enabled then return end
  enabled = on
  based = nil                                   -- reads were off: the next one is a new base
  if on then
    ns.RegisterEvent("UPDATE_FACTION", Rep, OnEvent)
    ns.RegisterEvent("FACTION_STANDING_CHANGED", Rep, OnEvent)
    ns.RegisterEvent("PLAYER_ENTERING_WORLD", Rep, OnEvent)
    Hook()
  else
    ns.UnregisterEvent("UPDATE_FACTION", Rep)
    ns.UnregisterEvent("FACTION_STANDING_CHANGED", Rep)
    ns.UnregisterEvent("PLAYER_ENTERING_WORLD", Rep)
  end
end

-- A reputation token in list t (slots of the bar or infos of the mini display)?
local function UsesToken(t)
  if type(t) ~= "table" then return false end
  return REP_TOKENS[t[1]] == true or REP_TOKENS[t[2]] == true or REP_TOKENS[t[3]] == true
end

-- Something shows the reputation: the strip and the tooltip line, the main bar, a token.
local function Wanted()
  local s = Settings()
  if not s then return false end
  local w = s.widget
  if type(w) == "table" and (w.rep == true or w.main == "rep" or UsesToken(w.slots) or UsesToken(w.maxSlots)) then
    return true
  end
  local m = s.mini
  return type(m) == "table" and m.shown == true and UsesToken(m.infos)
end

---------------------------------------------------------------------------
-- The faction list (the options' picker)
---------------------------------------------------------------------------

-- One row of the game's list: name, factionID, reaction, isHeader, isCollapsed, isChild,
-- isHeaderWithRep (a header with a reputation of its own).
local function RowFields(d)
  return Plain(d.name), Plain(d.factionID), Plain(d.reaction), Plain(d.isHeader), Plain(d.isCollapsed),
    Plain(d.isChild), Plain(d.isHeaderWithRep)
end

local function RowModern(api, i)
  local ok, d = pcall(api.GetFactionDataByIndex, i)
  if not ok or IsSecret(d) or type(d) ~= "table" then return nil end
  local okf, name, id, react, header, collapsed, child, withRep = pcall(RowFields, d)
  if not okf then return nil end
  return name, id, react, header, collapsed, child, withRep
end

-- Classic Era's GetFactionInfo: ..., isHeader (9th), isCollapsed, hasRep (11th), ...,
-- isChild (13th), factionID (14th).
local function RowEra(i)
  local ok, name, _, standing, _, _, _, _, _, header, collapsed, hasRep, _, child, id = pcall(GetFactionInfo, i)
  if not ok then return nil end
  return Plain(name), Plain(id), Plain(standing), Plain(header), Plain(collapsed), Plain(child), Plain(hasRep)
end

local LIST_MAX = 500                            -- rows read at most (a sane bound)

-- Walks the game's list (see the header). Returns the groups { name = header (nil before
-- the first header), items = { { id, name, reaction }, ... } } of the selectable factions:
-- an ID, and not a top-level header (the game's rule; a sub-header with a reputation of its
-- own is one: isHeaderWithRep, Era's hasRep; one without is not). A header is found again
-- by its key (ID, else name) and its rank among the headers of that key (two headers of
-- one name without an ID): the rows above it are already open when it is expanded, and
-- still are when it is collapsed again (last first), so that rank does not move.
-- Allocates: menu time only.
local function Walk(modern, api)
  local count = modern and api.GetNumFactions or GetNumFactions
  local expand = modern and api.ExpandFactionHeader or ExpandFactionHeader
  local collapse = modern and api.CollapseFactionHeader or CollapseFactionHeader
  local function N()
    local ok, n = pcall(count)
    if ok and IsNum(n) then
      if n > LIST_MAX then return LIST_MAX end
      return n
    end
    return 0
  end
  local function Row(i)
    if modern then return RowModern(api, i) end
    return RowEra(i)
  end
  local function Key(id, name)
    if IsNum(id) and id > 0 then return id end
    return name
  end
  -- 1. every collapsed header expanded (the count is read again: the indices shift), kept
  -- as its key and its rank among the headers of that key
  local opened, ranks = {}, {}
  if type(expand) == "function" then
    local i = 1
    while i <= N() do
      local name, id, _, header, collapsed = Row(i)
      if header == true then
        local key = Key(id, name)
        if key ~= nil then
          local rank = (ranks[key] or 0) + 1
          ranks[key] = rank
          if collapsed == true then
            opened[#opened + 1] = { key, rank }
            pcall(expand, i)
          end
        end
      end
      i = i + 1
    end
  end
  -- 2. the list
  local groups, cur = {}, nil
  for i = 1, N() do
    local name, id, react, header, _, child, withRep = Row(i)
    if type(name) == "string" and name ~= "" then
      if header == true and child ~= true then
        cur = { name = name, items = {} }
        groups[#groups + 1] = cur
      elseif IsNum(id) and id > 0 and (header ~= true or withRep == true) then
        if not cur then
          cur = { items = {} }
          groups[#groups + 1] = cur
        end
        if not IsNum(react) or react < 1 or react > MAX_REACTION then react = nil end
        cur.items[#cur.items + 1] = { id = id, name = name, reaction = react and math_floor(react) or nil }
      end
    end
  end
  -- 3. the headers we expanded collapsed again, last first, found again by their key and
  -- rank
  if type(collapse) == "function" then
    for j = #opened, 1, -1 do
      local key, rank = opened[j][1], opened[j][2]
      local seen = 0
      for i = 1, N() do
        local name, id, _, header, collapsed = Row(i)
        if header == true and Key(id, name) == key then
          seen = seen + 1
          if seen == rank then
            if collapsed ~= true then pcall(collapse, i) end
            break
          end
        end
      end
    end
  end
  local out = {}
  for g = 1, #groups do
    if #groups[g].items > 0 then out[#out + 1] = groups[g] end
  end
  return out
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- The settings (or the whole table) changed: events follow, then a read.
function Rep.Refresh()
  SetEnabled(Wanted())
  Update()
end

-- True while the reputation is on the bar (the strip with widget.rep, or the main bar) and
-- its tooltip line shown.
function Rep.Shown()
  return shown
end

-- True while a faction is read (whatever shows it).
function Rep.Has()
  return has
end

-- name, reaction (1..8), points inside the standing, points of the standing (> 0 unless
-- full), full (Exalted); nil when no faction is read.
function Rep.Get()
  if not has then return nil end
  return cName, cReact, cValue, cSpan, cFull
end

-- absolute standing, its standing's first point, its last (nil when unknown), reaction,
-- factionID (0: unknown), whose ("game" | "chosen"), the chosen faction unreadable (the
-- game's shown instead), classic thresholds. nil when no faction is read.
function Rep.Detail()
  if not has then return nil end
  return cAbs, cMin, cMax, cReact, cId, cSrc, cFallback, cStd
end

-- Points still needed to reach the first point of standing `target` (above the current
-- one): the next one from the API's threshold, later ones from the classic table when the
-- current standing has the classic thresholds; nil when unknown.
function Rep.Needed(target)
  if not has or cFull or not IsNum(target) or target <= cReact or target > MAX_REACTION then return nil end
  local left = cSpan - cValue
  if target == cReact + 1 then return left end
  if not cStd or cAbs == nil then return nil end
  local n = STARTS[target] - cAbs
  if n < left then n = left end
  return n
end

-- Colour of a standing: the game's FACTION_BAR_COLORS entry, else the classic one.
-- Three numbers, nothing allocated.
function Rep.Color(reaction)
  local t = FACTION_BAR_COLORS
  local c = type(t) == "table" and t[reaction]
  if type(c) == "table" then
    local r, g, b = Plain(c.r), Plain(c.g), Plain(c.b)
    if IsNum(r) and IsNum(g) and IsNum(b) then return r, g, b end
  end
  c = COLORS[reaction] or COLORS[5]
  return c[1], c[2], c[3]
end

-- The same as an { r, g, b, 1 } array (tooltip rows): one table per standing, refreshed in
-- place (created at its first use).
local rgba = {}
function Rep.ColorArray(reaction)
  local i = (IsNum(reaction) and reaction >= 1 and reaction <= MAX_REACTION) and reaction or 5
  local t = rgba[i]
  if not t then
    t = { 1, 1, 1, 1 }
    rgba[i] = t
  end
  t[1], t[2], t[3] = Rep.Color(i)
  return t
end

-- Rate of the faction shown under `mask`: points per hour (nil: none yet), status
-- ("nodata" | "warming" | "ok" | "stalled"), counted seconds still needed before it is
-- "ok" (0 while no gain was measured: it takes a gain, not time), counted seconds without
-- a gain, points per counted second. No allocation.
function Rep.Rate(mask)
  local r = Measured()
  if not r then return nil, "nodata", 0, 0, nil end
  local x = r.e[(mask or 0) + 1]
  if type(x) ~= "table" then return nil, "nodata", 0, 0, nil end
  local a, d = x.a, x.d
  if not IsNum(a) or not IsNum(d) then return nil, "nodata", 0, 0, nil end
  local left = WARMUP_FULL - d
  if left < 0 then left = 0 end
  local status
  if a > 0 and d >= WARMUP_FULL then
    status = "ok"
  elseif a > 0 and d >= WARMUP_MIN then
    status = "warming"
  else
    -- no gain yet: time alone will not do
    if not (a > 0) then left = 0 end   -- luacheck: ignore 581 (NaN fails too)
    return nil, "nodata", left, 0, nil
  end
  local n = r.n
  if type(n) ~= "number" then n = 0 end
  if n > STALL then status = "stalled" end
  local ps = a / d
  return 3600 * ps, status, left, n, ps
end

-- Counted seconds to the next standing at the current rate (nil: no rate, or Exalted),
-- the rate's status, and the next standing (nil at Exalted).
function Rep.Eta(mask)
  if not has or cFull or cReact >= MAX_REACTION then return nil, "max", nil end
  local _, status, _, _, ps = Rep.Rate(mask)
  if not ps or ps <= 0 then return nil, status, cReact + 1 end
  return (cSpan - cValue) / ps, status, cReact + 1
end

-- Points gained with the faction shown during this session (0 when none).
function Rep.SessionGain()
  local r = Measured()
  if not r or r.t ~= SessionT0() then return 0 end
  local s = r.s
  if not IsNum(s) or s < 0 then return 0 end
  return s
end

-- dt counted seconds of state k (Tracker's AdvanceRate, every Flush; never in read-only
-- mode): the EMA decays, except while frozen (past C.XP_STALL non-AFK seconds without a
-- gain, counted here). Allocation free.
function Rep.Advance(dt, k)
  if not enabled or ns.readOnly or type(dt) ~= "number" or dt <= 0 then return end
  local char = ns.char
  local r = type(char) == "table" and char.rep or nil
  local e = type(r) == "table" and r.e or nil
  if type(e) ~= "table" or r.f == nil then return end
  local n = r.n
  if type(n) ~= "number" then n = 0 end
  local wh = 0
  if n > STALL then wh = dt end
  if k ~= "u" and not IS_AFK[k] then           -- non-AFK time counts as time without a gain
    local nn = n + dt
    r.n = nn
    if wh == 0 and nn > STALL then
      wh = nn - STALL                           -- the stall starts inside this segment
      if wh > dt then wh = dt end
    end
  end
  if wh < dt then Decay(e, dt - wh, k) end
end

-- The rate starts over (the options' button, Core.ResetRate). False in read-only mode.
function Rep.ResetRate()
  if ns.readOnly then return false end
  local char = ns.char
  local r = type(char) == "table" and char.rep or nil
  if type(r) == "table" then
    r.e = NewEma()
    r.n = 0
  end
  return true
end

-- The faction chosen in TruePlayed for this character (nil: the game's watched one).
function Rep.Chosen()
  return ChosenId()
end

-- Chooses faction `id` (nil: the game's watched one again) for this character, then reads
-- it. False in read-only mode or for an invalid ID. Never touches the game's choice.
function Rep.SetChosen(id)
  if ns.readOnly then return false end
  local char = ns.char
  if type(char) ~= "table" then return false end
  if id ~= nil and not (IsNum(id) and id >= 1 and id % 1 == 0) then return false end
  local r = char.rep
  if id == nil then
    if type(r) == "table" then r.id = nil end   -- no record created only to say "the game's"
  else
    Record(char).id = id
  end
  Update()
  return true
end

-- The game's factions for the picker (see Walk), or an empty list on a client without the
-- list functions. One read follows the walk.
function Rep.ListFactions()
  local api = C_Reputation
  local modern = type(api) == "table" and type(api.GetNumFactions) == "function"
    and type(api.GetFactionDataByIndex) == "function"
  if not modern and (type(GetNumFactions) ~= "function" or type(GetFactionInfo) ~= "function") then return {} end
  busy = true
  local ok, out = pcall(Walk, modern, api)
  busy = false
  Update()
  if not ok or type(out) ~= "table" then return {} end
  return out
end

-- True while the picker walks the game's list (tests).
function Rep.IsBusy()
  return busy
end

local function OnSettingsChanged(_, path)
  if type(path) ~= "string" then return end
  if path == "widget.rep" or path == "widget.main" or path == "mini.shown"
      or path:find("widget.slots.", 1, true) == 1 or path:find("widget.maxSlots.", 1, true) == 1
      or path:find("mini.infos.", 1, true) == 1 then
    Rep.Refresh()
  end
end

-- Another record (a late SavedVariables table) or this one rebuilt: a new base.
local function OnRecord()
  based = nil
  Rep.Refresh()
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", Rep, Rep.Refresh)
  ns.RegisterMessage("DB_SWAPPED", Rep, OnRecord)
  ns.RegisterMessage("CHAR_RESET", Rep, OnRecord)
  ns.RegisterMessage("SETTINGS_CHANGED", Rep, OnSettingsChanged)
end
