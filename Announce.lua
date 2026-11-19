local ADDON, ns = ...
-- Announce.lua - the level-up message in the guild chat (guild.levelUp, off by default).
--
-- At a level-up (the Tracker's LEVEL_UP, sent once the level left is closed), the time
-- spent at the level left as the statistics window's Levels tab counts it (Stats.Sum under
-- the exclusions of the moment: AFK, inn, city, professions, dead) goes to the guild chat,
-- in TruePlayed's language (its Language option, else the client's): "Ding 42! Level 41 »
-- 42 in 3h 12m" (Announce.Text). Nothing outside a guild, in read-only mode (a newer
-- TruePlayed's data: nothing recorded), nor for a level whose time is not complete (begun
-- before TruePlayed was installed: partial; rebuilt from the server's /played: rec).
-- Several levels at once: one message when the game reports them together ("Level 40 »
-- 42"), else one for each (the next ones "in <1m").

local L, Fmt, Util = ns.L, ns.Fmt, ns.Util

local type, pcall = type, pcall
local format = string.format

local Announce = {}
ns.Announce = Announce

-- The message of a level-up from `old` to `new` after `sec` seconds at `old`.
function Announce.Text(new, old, sec)
  return format(L.GUILD_DING_FMT, new, old, new, Fmt.DurationLong(sec))
end

-- To the guild chat (C_ChatInfo's on the clients that moved it there). False when the
-- client has neither or refused it.
local function Send(text)
  local CI = C_ChatInfo
  local send = type(CI) == "table" and type(CI.SendChatMessage) == "function" and CI.SendChatMessage
    or SendChatMessage
  if type(send) ~= "function" then return false end
  return (pcall(send, text, "GUILD"))
end

local function OnLevelUp(_, new, old)
  local s = ns.settings
  local g = type(s) == "table" and s.guild or nil
  if not (type(g) == "table" and g.levelUp == true) or ns.readOnly then return end
  if type(new) ~= "number" or type(old) ~= "number" then return end
  local ok, inGuild = Util.SafeRead(IsInGuild)
  if not (ok and inGuild == true) then return end
  local char = ns.char
  local levels = type(char) == "table" and char.levels or nil
  local lb = type(levels) == "table" and levels[old] or nil
  if type(lb) ~= "table" or lb.partial or lb.rec then return end
  Send(Announce.Text(new, old, ns.Stats.Sum(lb, ns.GetMask())))
end

if ns.RegisterMessage then
  ns.RegisterMessage("LEVEL_UP", Announce, OnLevelUp)
end
