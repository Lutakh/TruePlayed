-- tests/test_announce.lua - the level-up message in the guild chat (Announce.lua,
-- guild.levelUp): off by default; on, at a level-up in a guild, the time spent at the
-- level left under the exclusions of the moment, in TruePlayed's language; nothing
-- outside a guild, for the level begun before the install (partial), in read-only mode;
-- a double level-up in one message; the option, its help and its example.
local Stub, T = ...

-- IsInGuild and SendChatMessage as the game answers them: S.guild, S.sent ({ text, type }).
local function InstallChat(guild)
  local S = { guild = guild, sent = {} }
  _G.IsInGuild = function() return S.guild end
  _G.SendChatMessage = function(text, chatType) S.sent[#S.sent + 1] = { text, chatType } end
  return S
end

-- Loads the addon in a new world (opts.db: the saved table; opts.guild false: not in a
-- guild; opts.levelPlayed: the server's /played of the level at the login; opts.locale:
-- the client's).
local function Start(opts)
  opts = opts or {}
  Stub.Reset()
  Stub.locale = opts.locale or "enUS"
  if opts.levelPlayed then Stub.server.levelPlayed = opts.levelPlayed end
  Stub.InstallUI({ ldb = false })
  local S = InstallChat(opts.guild ~= false)
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns, S
end

-- To the next level (the XP it still needs).
local function LevelUp()
  local p = Stub.player
  Stub.GrantXP(p.max - p.xp)
end

T.test("guild: off by default; on, at a level-up, the time at the level left (not the level begun before the install)", function()
  local ns, S = Start()
  T.eq(ns.settings.guild.levelUp, false, "off by default")
  Stub.Advance(600)
  LevelUp()                                   -- 10 > 11
  Stub.Advance(3900)
  LevelUp()                                   -- 11 > 12, 1h 05m at 11
  T.eq(#S.sent, 0, "off: nothing")
  ns.Core.SetSetting("guild.levelUp", true)
  Stub.Advance(3900)
  LevelUp()                                   -- 12 > 13, 1h 05m at 12
  T.eq(S.sent, { { "Ding 13! Level 12 \194\187 13 in 1h 05m", "GUILD" } })
  -- the level begun before the install (2 h on the server's /played): its time is not complete
  ns, S = Start({ levelPlayed = 7200, db = { schema = 1, settings = { guild = { levelUp = true } } } })
  T.ok(ns.char.levels[10].partial, "the level of the first login")
  Stub.Advance(3900)
  LevelUp()
  T.eq(#S.sent, 0, "partial: nothing")
  Stub.Advance(60 * 47)
  LevelUp()
  T.eq(S.sent, { { "Ding 12! Level 11 \194\187 12 in 47m", "GUILD" } })
end)

T.test("guild: the exclusions of the moment apply; a double level-up, one message", function()
  local ns, S = Start({ db = { schema = 1, settings = { guild = { levelUp = true }, exclude = { afk = true } } } })
  LevelUp()                                   -- 10 > 11 (partial: nothing)
  Stub.Advance(3600)
  Stub.SetAFK(true)
  Stub.Advance(1800)                          -- excluded
  Stub.SetAFK(false)
  Stub.Advance(600)
  LevelUp()
  T.eq(S.sent[1], { "Ding 12! Level 11 \194\187 12 in 1h 10m", "GUILD" }, "the AFK half hour left out")
  ns.Core.SetSetting("exclude.afk", false)
  Stub.Advance(1200)
  local p = Stub.player
  Stub.GrantXP(p.max - p.xp + Stub.xpTable[13])  -- 12 > 13 > 14 at once
  T.eq(p.level, 14)
  T.eq(S.sent[2], { "Ding 14! Level 12 \194\187 14 in 20m", "GUILD" }, "the levels the game reports together")
  T.eq(#S.sent, 2)
end)

T.test("guild: nothing outside a guild nor in read-only mode", function()
  local _, S = Start({ guild = false, db = { schema = 1, settings = { guild = { levelUp = true } } } })
  LevelUp()
  Stub.Advance(600)
  LevelUp()
  T.eq(#S.sent, 0, "not in a guild")
  S.guild = true
  Stub.Advance(600)
  LevelUp()
  T.eq(#S.sent, 1, "in a guild again")
  -- a newer TruePlayed's data: read-only, nothing recorded (its level 10 as that version
  -- left it, complete), nothing sent
  local ns
  local guid = Stub.player.guid
  ns, S = Start({ db = { schema = 99, settings = { guild = { levelUp = true } },
                         chars = { [guid] = { guid = guid, levels = { [10] = { s = { w = 3600 } } } } } } })
  T.ok(ns.readOnly, "read-only")
  LevelUp()
  Stub.Advance(600)
  LevelUp()
  T.eq(#S.sent, 0, "read-only: nothing")
end)

T.test("guild: in TruePlayed's language, not the client's", function()
  local ns, S = Start({ locale = "enUS", db = { schema = 1, settings = { language = "frFR", guild = { levelUp = true } } } })
  LevelUp()
  Stub.Advance(3900)
  LevelUp()
  T.eq(S.sent, { { "Ding 12 ! Niveau 11 \194\187 12 en 1 h 05 min", "GUILD" } })
  T.eq(ns.Announce.Text(42, 41, 11520), "Ding 42 ! Niveau 41 \194\187 42 en 3 h 12 min")
end)

T.test("guild: the option in the Guild section, its help with the message as sent", function()
  local ns = Start()
  ns.Options.Open()
  local controls = rawget(Stub.ui.categories[1].frame, "controls")
  local rec = controls["guild.levelUp"]
  T.ok(rec ~= nil and rec.kind == "check", "a checkbox")
  T.eq(rec.label:GetText(), "Announce level-ups in guild chat")
  T.eq(controls["help.guildLevelUp"].index, rec.index + 1, "its \"?\"")
  T.no(rec.widget:GetChecked(), "unchecked")
  Stub.RunScript(rec.widget, "OnClick", "LeftButton")
  T.eq(ns.settings.guild.levelUp, true, "a click turns it on")
  local help = {}
  ns.Options.HelpLines.guildLevelUp(nil, function(_, s) help[#help + 1] = s end)
  T.eq(#help, 2)
  T.match(help[1], "guild chat")
  T.eq(help[2], "For example: Ding 42! Level 41 \194\187 42 in 3h 12m")
end)
