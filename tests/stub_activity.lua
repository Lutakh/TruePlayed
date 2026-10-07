-- tests/stub_activity.lua - stub extension for the activity states (Activity.lua, lot 8:
-- dead or a ghost, professions). Returns an installer run at the end of every
-- Stub.Reset(); it installs, always:
--   GetSpellInfo(id)      -> Stub.spellNames[id] (nil for an unknown ID); C_Spell stays absent
--   GetUnitSpeed("player")-> Stub.act.speed (0: standing still)
--   GetCraftName()        -> Stub.act.craftName (the open craft window: "Enchanting" or
--                            "Beast Training")
--   UnitIsFeignDeath(u)   -> Stub.act.feign for "player"
-- UnitIsDeadOrGhost (frozen stub) reads Stub.player.dead.
-- Helpers (events as the game sends them; spell events: unit, castGUID, spellID):
--   Stub.Die()            dead (PLAYER_DEAD)
--   Stub.ReleaseSpirit()  a ghost (still dead; PLAYER_ALIVE, as the game sends it)
--   Stub.Resurrect(ghost) alive again (PLAYER_UNGHOST when ghost, else PLAYER_ALIVE)
--   Stub.Spell(what, id)  fires UNIT_SPELLCAST_<what> for "player" (what = "START",
--                         "STOP", "SUCCEEDED", "INTERRUPTED", "FAILED", "CHANNEL_START",
--                         "CHANNEL_STOP"); Stub.Spell(what, id, unit) for another unit
--   Stub.Cast(id, secs)   START, `secs` seconds, then SUCCEEDED and STOP (a full cast)
--   Stub.OpenTradeSkill() / Stub.CloseTradeSkill()  TRADE_SKILL_SHOW / _CLOSE
--   Stub.OpenCraft(name) / Stub.CloseCraft()        CRAFT_SHOW (craft name) / CRAFT_CLOSE

-- Classic Era names of the spells the tests use (enUS).
local function SpellNames()
  local t = {}
  local function Set(name, ...)
    for _, id in ipairs({ ... }) do t[id] = name end
  end
  Set("Herb Gathering", 2366, 2368, 3570, 11993)
  Set("Mining", 2575, 2576, 3564, 10248)
  Set("Skinning", 8613, 8617, 8618, 10768)
  Set("Fishing", 7620, 7731, 7732, 18248)
  Set("Disenchant", 13262)
  Set("Pick Lock", 1804)
  Set("First Aid", 746, 1159, 3267, 3268, 7926, 7927, 10838, 10839, 18608, 18610, 3273)
  Set("Beast Training", 5149)
  Set("Fireball", 133)
  Set("Hearthstone", 8690)
  Set("Copper Bar", 2657)                -- Smelting: a craft of the trade skill window
  Set("Enchant Bracer - Minor Health", 7418)
  Set("Linen Bandage", 3275)             -- First Aid craft (the item, not the channel)
  Set("Herb Gathering", 99001)           -- a rank the addon does not list (name match)
  return t
end

return function(Stub)
  Stub.spellNames = SpellNames()
  Stub.act = { speed = 0, craftName = "Enchanting", feign = false, guid = 0 }

  rawset(_G, "GetSpellInfo", function(id)
    local name = Stub.spellNames[id]
    if name == nil then return nil end
    return name, nil, 136243, 0, 0, 0, id
  end)
  rawset(_G, "GetUnitSpeed", function(unit)
    if unit ~= "player" then return 0 end
    return Stub.act.speed
  end)
  rawset(_G, "GetCraftName", function() return Stub.act.craftName end)
  rawset(_G, "UnitIsFeignDeath", function(unit)
    return unit == "player" and Stub.act.feign == true
  end)

  function Stub.Die()
    Stub.player.dead = true
    Stub.Fire("PLAYER_DEAD")
  end

  function Stub.ReleaseSpirit()
    Stub.player.dead = true                -- a ghost is still dead (UnitIsDeadOrGhost)
    Stub.Fire("PLAYER_ALIVE")
  end

  function Stub.Resurrect(ghost)
    Stub.player.dead = false
    Stub.Fire(ghost and "PLAYER_UNGHOST" or "PLAYER_ALIVE")
  end

  function Stub.Spell(what, id, unit)
    local act = Stub.act
    act.guid = act.guid + 1
    Stub.Fire("UNIT_SPELLCAST_" .. what, unit or "player", "Cast-3-0-0-0-" .. act.guid, id)
  end

  function Stub.Cast(id, secs)
    Stub.Spell("START", id)
    Stub.Advance(secs or 1.5)
    Stub.Spell("SUCCEEDED", id)
    Stub.Spell("STOP", id)
  end

  function Stub.OpenTradeSkill() Stub.Fire("TRADE_SKILL_SHOW") end
  function Stub.CloseTradeSkill() Stub.Fire("TRADE_SKILL_CLOSE") end
  function Stub.OpenCraft(name)
    if name ~= nil then Stub.act.craftName = name end
    Stub.Fire("CRAFT_SHOW")
  end
  function Stub.CloseCraft() Stub.Fire("CRAFT_CLOSE") end
end
