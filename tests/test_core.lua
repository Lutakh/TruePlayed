-- tests/test_core.lua - Core.lua, the locale files and the test stub itself
-- (SPEC-FINAL 3.1-3.6, 4.6, 5.1, 5.16, 5.18, 5.20, 8, 9.2, 9.4 "test_core").
-- Most tests load only the foundation files; tests named "integration (all
-- modules)" load the whole addon from the TOC and need every module.
local Stub, T = ...

local FILES = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Format.lua" }
local GUID = "Player-4619-00A629CA"

local function Load(locale)
  Stub.locale = locale or "enUS"
  return Stub.LoadAddon({ files = FILES })
end

local function LastPrinted()
  return Stub.printed[#Stub.printed]
end

local function CountPrinted(text)
  local n = 0
  for _, line in ipairs(Stub.printed) do
    if line:find(text, 1, true) then n = n + 1 end
  end
  return n
end

-- Replaces the engine modules by spies (Core reaches them as ns.X at run time).
local function SpyModules(ns, sync)
  local spy = { replay = {}, invalidate = 0, reset = 0, reconcile = {} }
  ns.Tracker = {
    ReplayDelta = function(newChar) spy.replay[#spy.replay + 1] = newChar end,
    InvalidateZoneCache = function() spy.invalidate = spy.invalidate + 1 end,
    GetSync = function() return sync end,
    GetState = function() return "w", 1411, 10 end,
    ReconcileServer = function(total, levelPlayed) spy.reconcile[#spy.reconcile + 1] = { total, levelPlayed } end,
  }
  ns.Stats = { ResetCaches = function() spy.reset = spy.reset + 1 end }
  return spy
end

local function IsLatin1(s)
  if type(s) ~= "string" then return false end
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    if b < 0x80 then
      i = i + 1
    elseif b == 0xC2 or b == 0xC3 then
      local b2 = s:byte(i + 1)
      if not b2 or b2 < 0x80 or b2 > 0xBF then return false end
      i = i + 2
    else
      return false
    end
  end
  return true
end

---------------------------------------------------------------------------
-- SavedVariables lifecycle
---------------------------------------------------------------------------
T.test("no SV: nothing created at ADDON_LOADED, a private table at PLAYER_LOGIN", function()
  local ns = Load()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  T.eq(rawget(_G, "TruePlayedDB"), nil, "no SV at ADDON_LOADED")
  T.eq(ns.db, nil)
  T.no(ns.ready)
  Stub.Fire("PLAYER_LOGIN")
  T.eq(rawget(_G, "TruePlayedDB"), nil, "not published before PLAYER_LOGOUT (FOREVER-2)")
  local db = ns.db
  T.eq(type(db), "table")
  T.eq(db.schema, 1)
  T.eq(db.settings, ns.C.DEFAULTS)
  T.ok(ns.settings == db.settings)
  T.eq(db.cities, {})
  T.eq(db.xpMax, {})
  T.eq(type(db.createdAt), "number")
  local char = db.chars[GUID]
  T.ok(char ~= nil and ns.char == char, "record keyed by GUID")
  T.eq(char.guid, GUID)
  T.eq(char.name, "Lutak")
  T.eq(char.surname, "Ombrevent")
  T.eq(char.realm, "Brisevent")
  T.eq(char.class, "MAGE")
  T.eq(char.faction, "Horde")
  T.eq(char.level, 10)
  T.eq(char.life, ns.Core.NewLife())
  T.eq(char.ema, ns.Core.NewEma())
  T.eq(char.base, nil, "never synced")
  T.ok(ns.ready)
  T.ok(ns.Core.IsReady())
  T.eq(ns.GetMask(), 0)
end)

T.test("DB_READY is sent once, after the character is known", function()
  local ns = Load()
  local seen = 0
  ns.RegisterMessage("DB_READY", "test", function()
    seen = seen + 1
    T.ok(ns.char ~= nil and ns.ready, "state ready inside DB_READY")
  end)
  Stub.LoginSequence()
  T.eq(seen, 1)
  Stub.Fire("PLAYER_LOGIN")
  T.eq(seen, 1, "a second PLAYER_LOGIN is ignored")
end)

T.test("ADDON_LOADED of another addon is ignored", function()
  _G.TruePlayedDB = { settings = {} }
  local ns = Load()
  Stub.Fire("ADDON_LOADED", "SomethingElse")
  T.eq(ns.db, nil)
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  T.ok(ns.db == _G.TruePlayedDB)
end)

T.test("existing SV adopted, migrated and completed without overwriting", function()
  local sv = {
    settings = {
      exclude = { afk = true },
      widget = { width = 400, slots = { "played", "none", "fps" } },
      rateTau = 1200,
    },
    chars = { [GUID] = { name = "Lutak", level = 12, life = { s = { w = 500 }, xp = 1000 } } },
  }
  _G.TruePlayedDB = sv
  local ns = Load()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  T.ok(ns.db == sv, "adopted, not copied")
  T.eq(sv.schema, 1)
  T.eq(sv.settings.exclude, { afk = true, inn = false, city = false })
  T.eq(sv.settings.widget.width, 400)
  T.eq(sv.settings.widget.slots, { "played", "none", "fps" })
  T.eq(sv.settings.widget.height, 8)
  T.eq(sv.settings.widget.maxSlots, { "session", "played", "fps_latency" })
  T.eq(sv.settings.widget.point, { "CENTER", "CENTER", 0, -220 })
  T.eq(sv.settings.rateTau, 1200)
  T.eq(sv.settings.requestPlayedAtLogin, true)
  T.eq(sv.cities, {})
  T.eq(sv.xpMax, {})
  local rec = sv.chars[GUID]
  T.eq(rec.life, { s = { w = 500 }, xp = 1000, xa = 0, xr = 0, xq = 0, d = 0, est = 0 })
  T.eq(#rec.ema, 8)
  Stub.Fire("PLAYER_LOGIN")
  T.ok(ns.char == rec)
  T.eq(ns.GetMask(), 1)
  T.eq(rec.level, 12, "Core never writes the level (Tracker.Start does)")
end)

T.test("Migrate runs MIGRATIONS in order up to C.SCHEMA; newer schema refused", function()
  local ns = Load()
  local C, Core = ns.C, ns.Core
  local calls = {}
  C.SCHEMA = 3
  Core.MIGRATIONS[2] = function(db) calls[#calls + 1] = 2; db.two = true end
  Core.MIGRATIONS[3] = function() calls[#calls + 1] = 3 end
  local db = { schema = 1 }
  T.ok(Core.Migrate(db))
  T.eq(calls, { 2, 3 })
  T.eq(db.schema, 3)
  T.ok(db.two)
  T.eq(type(db.settings), "table", "repaired after migration")
  T.no(Core.Migrate({ schema = 4 }))
  local noSchema = { chars = {} }
  T.ok(Core.Migrate(noSchema))
  T.eq(calls, { 2, 3, 2, 3 }, "schema nil is treated as 1")
end)

T.test("WTFix: a table applied late is re-read at PLAYER_LOGIN and wins", function()
  local first = { settings = { rateTau = 1200 } }
  _G.TruePlayedDB = first
  local ns = Load()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  T.ok(ns.db == first)
  local late = { settings = { rateTau = 5400, exclude = { city = true } } }
  _G.TruePlayedDB = late
  Stub.Fire("PLAYER_LOGIN")
  T.ok(ns.db == late)
  T.ok(ns.settings == late.settings)
  T.eq(late.schema, 1)
  T.eq(ns.settings.rateTau, 5400)
  T.eq(ns.GetMask(), 4)
  T.ok(late.chars[GUID] ~= nil)
  T.eq(first.chars[GUID], nil, "the first table got no record")
end)

T.test("WTFix protecting TruePlayed: one warning at login; none when unprotected or absent", function()
  local function Run(boot, wdb)
    Stub.Reset()
    _G.WTFIX_BOOTSTRAP, _G.WTFIX_DB = boot, wdb
    local ns = Load()
    Stub.LoginSequence()
    Stub.Advance(2)
    return CountPrinted(ns.L.WTFIX_PROTECTED)
  end
  local function Target()
    return { targets = { TruePlayed = { account = { "TruePlayedDB" }, character = {} } } }
  end
  T.eq(Run(Target(), { protectedAddons = {} }), 1, "protected by default: one warning")
  T.eq(Run(Target(), nil), 1, "WTFix settings not loaded: protected by default")
  T.eq(Run(Target(), { protectedAddons = { TruePlayed = false } }), 0, "unchecked in /wtfix")
  T.eq(Run({ targets = { OtherAddon = {} } }, { protectedAddons = {} }), 0, "not a WTFix target")
  T.eq(Run(nil, nil), 0, "no WTFix")
  T.eq(Run("junk", 42), 0, "unexpected shapes are ignored")
end)

T.test("newer schema: readOnly, one message, nothing written, settings not durable", function()
  local sv = { schema = 99, settings = { widget = { width = 300 } }, chars = {}, future = { x = 1 } }
  local snapshot = Stub.DeepCopy(sv)
  _G.TruePlayedDB = sv
  local ns = Load()
  Stub.LoginSequence()
  T.ok(ns.readOnly)
  T.ok(ns.db == sv)
  T.ok(ns.ready)
  T.eq(CountPrinted(ns.L.SCHEMA_NEWER), 1)
  T.eq(sv, snapshot, "nothing migrated, repaired or completed")
  T.eq(sv.chars[GUID], nil, "no record created")
  T.eq(ns.char.guid, GUID)
  T.ok(ns.settings ~= sv.settings, "in-memory settings")
  T.eq(ns.settings.widget.width, 300)
  T.eq(ns.settings.exclude.afk, false, "completed in memory")
  T.ok(ns.Core.SetSetting("widget.width", 500))
  T.eq(ns.settings.widget.width, 500)
  T.eq(sv.settings.widget.width, 300, "SetSetting is not durable")
  T.no(ns.Core.ResetChar(GUID))
  T.no(ns.Core.ResetRate())
  T.eq(ns.Core.EnsureChar(sv, GUID).guid, GUID)
  T.eq(sv.chars[GUID], nil, "EnsureChar never creates in readOnly")
  _G.TruePlayedDB = { chars = {} }
  Stub.Advance(3)
  T.ok(ns.db == sv, "CheckSwap disabled")
  _G.TruePlayedDB = sv
  Stub.Fire("PLAYER_LOGOUT")
  T.eq(sv, snapshot, "PLAYER_LOGOUT writes nothing, not even lastVersion")
  T.eq(CountPrinted(ns.L.SCHEMA_NEWER), 1, "printed once")
end)

T.test("readOnly: the character record is a detached, repaired copy", function()
  local sv = { schema = 5, chars = { [GUID] = { name = "Lutak", level = 42, life = { s = { w = 10 } } } } }
  local snapshot = Stub.DeepCopy(sv)
  _G.TruePlayedDB = sv
  local ns = Load()
  Stub.LoginSequence()
  T.ok(ns.readOnly)
  T.eq(ns.char.level, 42)
  T.eq(ns.char.life.s.w, 10)
  T.eq(ns.char.life.xp, 0, "repaired in memory")
  T.ok(ns.char ~= sv.chars[GUID])
  ns.char.life.s.w = 99
  T.eq(sv, snapshot)
end)

T.test("two characters with the same name get two records by GUID", function()
  Load()
  Stub.LoginSequence()
  Stub.Advance(5)
  Stub.Logout()
  T.eq(Stub.saved.lastVersion, "dev", "lastVersion written at logout")
  Stub.Reset({ keepWorld = true })
  Stub.player.guid = "Player-4619-00BBBBBB"
  _G.TruePlayedDB = Stub.DeepCopy(Stub.saved)
  local ns = Load()
  Stub.LoginSequence()
  local n = 0
  for _, rec in pairs(ns.db.chars) do
    n = n + 1
    T.eq(rec.name, "Lutak")
  end
  T.eq(n, 2)
  T.eq(ns.char.guid, "Player-4619-00BBBBBB")
  T.ok(ns.db.chars[GUID] ~= ns.char)
end)

T.test("PLAYER_LOGIN without a player GUID retries every second", function()
  local ns = Load()
  Stub.player.guid = nil
  Stub.LoginSequence()
  T.no(ns.ready)
  Stub.Advance(2)
  T.no(ns.ready)
  Stub.player.guid = GUID
  Stub.Advance(1)
  T.ok(ns.ready)
  T.ok(ns.char == ns.db.chars[GUID])
end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
T.test("SetSetting: SETTINGS_CHANGED only on change, clamping, cached mask", function()
  local ns = Load()
  Stub.LoginSequence()
  local Core, w = ns.Core, ns.settings.widget
  local got = {}
  ns.RegisterMessage("SETTINGS_CHANGED", "test", function(_, path, value) got[#got + 1] = { path, value } end)

  T.ok(Core.SetSetting("exclude.afk", true))
  T.eq(got, { { "exclude.afk", true } })
  T.eq(ns.GetMask(), 1)
  T.no(Core.SetSetting("exclude.afk", true), "unchanged")
  T.eq(#got, 1)
  T.ok(Core.SetSetting("exclude.city", true))
  T.eq(ns.GetMask(), 5)
  T.ok(Core.SetSetting("exclude.inn", true))
  T.eq(ns.GetMask(), 7)
  T.ok(Core.SetSetting("exclude.afk", false))
  T.eq(ns.GetMask(), 6)

  Core.SetSetting("widget.width", 1000); T.eq(w.width, 600)
  Core.SetSetting("widget.width", 155); T.eq(w.width, 160, "step 10")
  Core.SetSetting("widget.width", 20); T.eq(w.width, 150)
  Core.SetSetting("widget.scale", 0.1); T.eq(w.scale, 0.5)
  Core.SetSetting("widget.scale", 1.234); T.eq(w.scale, 1.25, "step 0.05")
  Core.SetSetting("widget.scale", 1.05); T.eq(w.scale, 1.05)
  Core.SetSetting("widget.height", 3); T.eq(w.height, 4)
  Core.SetSetting("widget.height", 99); T.eq(w.height, 16)
  Core.SetSetting("widget.fontSize", 20); T.eq(w.fontSize, 16)
  Core.SetSetting("widget.fontSize", 8.6); T.eq(w.fontSize, 9)

  local before = #got
  T.no(Core.SetSetting("widget.slot3Pos", "round"))
  T.no(Core.SetSetting("widget.style", "box"), "the compact box style was removed")
  T.no(Core.SetSetting("rateTau", 1234))
  T.no(Core.SetSetting("widget.slots.2", "bogus"))
  T.no(Core.SetSetting("widget.shown", "yes"))
  T.no(Core.SetSetting("widget.width", "wide"))
  T.no(Core.SetSetting("widget.width", 0 / 0))
  T.no(Core.SetSetting("no.such.path", 1))
  T.no(Core.SetSetting("widget.slots.4", "eta"))
  T.no(Core.SetSetting("widget.point", { "NOWHERE", "TOPLEFT", 1, 1 }))
  T.no(Core.SetSetting("exclude.afk", nil))
  T.eq(#got, before, "no message for ignored values")

  T.ok(Core.SetSetting("widget.slot3Pos", "left"))
  T.ok(Core.SetSetting("rateTau", 1200))
  T.ok(Core.SetSetting("widget.slots.2", "fps"))
  T.eq(w.slots, { "eta_kills", "fps", "fps_latency" })
  T.ok(Core.SetSetting("widget.maxSlots.3", "none"))
  T.ok(Core.SetSetting("widget.point", { "TOPLEFT", "TOPLEFT", 10.4, -20.6 }))
  T.eq(w.point, { "TOPLEFT", "TOPLEFT", 10, -21 }, "x, y rounded")
  T.no(Core.SetSetting("widget.point", { "TOPLEFT", "TOPLEFT", 10, -21 }), "same point")
  T.eq(got[#got][1], "widget.point")
  T.ok(got[#got][2] == w.point, "payload is the stored value")

  T.eq(Core.GetSetting("widget.slot3Pos"), "left")
  T.eq(Core.GetSetting("widget.style"), nil)
  T.eq(Core.GetSetting("widget.slots.2"), "fps")
  T.eq(Core.GetSetting("rateTau"), 1200)
  T.eq(Core.GetSetting("widget.nothing"), nil)
  T.eq(Core.GetSetting("widget"), w)
  T.eq(#Stub.errors, 0)
end)

T.test("RepairDB clamps or resets invalid settings and keeps valid ones", function()
  _G.TruePlayedDB = {
    settings = {
      widget = { width = 9999, scale = "big", slots = { "eta", 5, "future_token" }, point = { "NOWHERE" }, style = "box" },
      rateTau = 42, exclude = "yes", debug = "no",
    },
  }
  local ns = Load()
  Stub.LoginSequence()
  local s = ns.settings
  T.eq(s.widget.width, 600)
  T.eq(s.widget.scale, 1.0)
  T.eq(s.widget.slots, { "eta", "xph", "future_token" }, "unknown ids from newer versions are kept")
  T.eq(s.widget.point, { "CENTER", "CENTER", 0, -220 })
  T.eq(s.widget.style, nil, "the removed style setting (a stored box) is dropped: the bar")
  T.eq(s.rateTau, 3600)
  T.eq(s.exclude, { afk = false, inn = false, city = false })
  T.eq(s.debug, false)
  Stub.Logout()
  T.eq(Stub.saved.settings.widget.style, nil, "the removed style setting leaves the file")
  T.eq(#Stub.errors, 0)
end)

---------------------------------------------------------------------------
-- Theme setting (design/SPEC-themes.md 1, S1-S4)
---------------------------------------------------------------------------
T.test("theme setting: futuriste by default, 14 choices, the 9 classes mapped", function()
  Stub.theme = nil                       -- no test hook: the shipped default
  local ns = Load()
  local C = ns.C
  T.eq(C.DEFAULTS.theme, "futuriste")
  T.eq(#C.THEME_CHOICES, 14)
  T.eq(C.THEME_CHOICES[1], "futuriste", "the default comes first")
  local seen = {}
  for _, k in ipairs(C.THEME_CHOICES) do
    T.no(seen[k], "unique " .. k)
    seen[k] = true
  end
  T.ok(seen.actuel and seen.class, "actuel and class are choices")
  local n = 0
  for classFile, key in pairs(C.CLASS_THEMES) do
    n = n + 1
    T.ok(seen[key], classFile .. " maps to a choice")
    T.eq(key, classFile:lower())
  end
  T.eq(n, 9)
  Stub.LoginSequence()
  T.eq(ns.settings.theme, "futuriste")
  -- the test hook (SPEC-themes 8.1): legacy tests run with the classic look
  Stub.Reset()
  local ns2 = Load()
  T.eq(ns2.C.DEFAULTS.theme, "actuel")
end)

T.test("theme setting: RepairDB keeps valid and well-formed unknown keys, resets the rest", function()
  local cases = {
    { "mage", "mage" }, { "class", "class" }, { "actuel", "actuel" },
    { "newtheme", "newtheme" },                         -- a key from a newer version is kept
    { string.rep("a", 24), string.rep("a", 24) },
    { string.rep("a", 25), "futuriste" }, { 42, "futuriste" }, { "bad-key!", "futuriste" },
    { "", "futuriste" }, { { "mage" }, "futuriste" }, { true, "futuriste" },
  }
  for _, case in ipairs(cases) do
    Stub.Reset()
    Stub.theme = nil
    _G.TruePlayedDB = { settings = { theme = case[1] } }
    local ns = Load()
    Stub.LoginSequence()
    T.eq(ns.settings.theme, case[2], "repair of " .. T.repr(case[1]))
  end
end)

T.test("theme setting: SetSetting accepts the 14 choices only, one SETTINGS_CHANGED per change", function()
  Stub.theme = nil
  local ns = Load()
  Stub.LoginSequence()
  local got = {}
  ns.RegisterMessage("SETTINGS_CHANGED", "test", function(_, path) got[#got + 1] = path end)
  for _, k in ipairs(ns.C.THEME_CHOICES) do
    T.eq(ns.Core.SetSetting("theme", k), k ~= "futuriste", "SetSetting(theme, " .. k .. ") reports a change")
    T.eq(ns.settings.theme, k)
  end
  T.eq(#got, 13, "futuriste -> futuriste is not a change")
  for _, bad in ipairs({ "foo", "newtheme", 42, "" }) do
    T.no(ns.Core.SetSetting("theme", bad), "SetSetting returns false for " .. T.repr(bad))
    T.eq(ns.settings.theme, "druid", "refused " .. T.repr(bad))
  end
  T.eq(#got, 13)
end)

---------------------------------------------------------------------------
-- Repair of truncated data
---------------------------------------------------------------------------
T.test("RepairDB fixes a truncated / corrupted table", function()
  local sv = {
    settings = "garbage",
    cities = { [1454] = false, [1] = "x", foo = true },
    xpMax = { [10] = 7600, [11] = -1, [12] = "x" },
    chars = {
      bad = 7,
      [GUID] = {
        life = { s = { w = 10, W = "x" } },
        levels = { [5] = "junk", [6] = { s = { w = 3 }, max = "x", t0 = 5 }, foo = {} },
        zones = { [1411] = { xp = "x" }, [1413] = 4 },
        ema = { { a = 1, r = 0 / 0, q = -5 }, "bad", [9] = {} },
        sessions = { [1] = "x", [2] = { s = {} }, [4] = { xp = 5 } },
        cur = 5, srv = { total = "x" }, xpSnap = { level = 10 }, base = { total = 100, at = 1 },
        level = "ten",
      },
    },
  }
  _G.TruePlayedDB = sv
  local ns = Load()
  Stub.LoginSequence()
  T.no(ns.readOnly)
  T.eq(sv.settings, ns.C.DEFAULTS)
  T.eq(sv.cities, { [1454] = false })
  T.eq(sv.xpMax, { [10] = 7600 })
  T.eq(sv.chars.bad, nil)
  local c = sv.chars[GUID]
  T.eq(c.life, { s = { w = 10 }, xp = 0, xa = 0, xr = 0, xq = 0, d = 0, est = 0 })
  T.eq(c.levels[5], nil)
  T.eq(c.levels.foo, nil)
  T.eq(c.levels[6], { s = { w = 3 }, z = {}, xp = 0, xa = 0, xr = 0, xq = 0, d = 0, t0 = 5 })
  T.eq(c.zones, { [1411] = { s = {}, xp = 0 } })
  T.eq(#c.ema, 8)
  T.eq(c.ema[1], { a = 1, r = 0, q = 0, d = 0 })
  T.eq(c.ema[2], { a = 0, r = 0, q = 0, d = 0 })
  T.eq(c.ema[9], nil)
  T.eq(c.sessions, { { s = {}, xp = 0, d = 0 }, { s = {}, xp = 5, d = 0 } })
  T.eq(c.cur, nil)
  T.eq(c.srv, nil)
  T.eq(c.xpSnap, nil)
  T.eq(c.base, { total = 100, at = 1 })
  T.eq(c.level, nil)
  T.eq(c.guid, GUID)
  T.eq(c.name, "Lutak", "identity refreshed")
  T.ok(ns.char == c)
end)

T.test("RepairChar keeps the newest C.SESSION_RING sessions", function()
  local ns = Load()
  local char = { sessions = {} }
  for i = 1, 35 do char.sessions[i] = { s = {}, xp = i, d = 0 } end
  ns.Core.RepairChar(char)
  T.eq(#char.sessions, ns.C.SESSION_RING)
  T.eq(char.sessions[1].xp, 6)
  T.eq(char.sessions[30].xp, 35)
end)

---------------------------------------------------------------------------
-- Late swap (5.16)
---------------------------------------------------------------------------
T.test("CheckSwap: a late table replaces ns.db, replays once, sends DB_SWAPPED", function()
  local ns = Load()
  Stub.LoginSequence()
  local old = ns.db
  old.xpMax[10], old.xpMax[11] = 7600, 9000
  local spy = SpyModules(ns, nil)
  local swapped = 0
  ns.RegisterMessage("DB_SWAPPED", "test", function()
    swapped = swapped + 1
    T.ok(ns.db == _G.TruePlayedDB, "DB_SWAPPED sent after the pointers moved")
  end)
  local real = {
    settings = { exclude = { afk = true } },
    xpMax = { [11] = 8800, [12] = 10100 },
    chars = { [GUID] = { name = "Lutak", level = 10, life = { s = { w = 50 } } } },
  }
  _G.TruePlayedDB = real
  ns.Core.CheckSwap()
  T.eq(#spy.replay, 1)
  T.ok(spy.replay[1] == real.chars[GUID], "ReplayDelta gets the new record")
  T.ok(ns.db == real)
  T.ok(ns.settings == real.settings)
  T.ok(ns.char == real.chars[GUID])
  T.eq(ns.GetMask(), 1, "mask recomputed")
  T.eq(swapped, 1)
  T.eq(spy.invalidate, 1)
  T.eq(spy.reset, 1)
  T.eq(real.xpMax, { [10] = 7600, [11] = 9000, [12] = 10100 }, "xpMax merged, larger wins")
  T.eq(real.schema, 1)
  T.eq(real.chars[GUID].life.s.w, 50)
  T.eq(#spy.reconcile, 0, "no sync: nothing re-applied")
  ns.Core.CheckSwap()
  Stub.Advance(3)
  T.eq(#spy.replay, 1, "same table: no second swap")
  _G.TruePlayedDB = nil
  ns.Core.CheckSwap()
  T.eq(rawget(_G, "TruePlayedDB"), nil, "a nil global is left alone during play")
  T.ok(ns.db == real)
  T.eq(#spy.replay, 1)
  T.eq(swapped, 1)
  Stub.Fire("PLAYER_LOGOUT")
  T.ok(_G.TruePlayedDB == real, "published again at PLAYER_LOGOUT")
end)

T.test("CheckSwap: a live sync is re-applied to the new table, projected to now", function()
  local ns = Load()
  Stub.LoginSequence()
  local sync = { valid = true, restored = false, total = 400000, levelPlayed = 1000, level = 10,
                 levelValid = true, g = Stub.Now() - 10 }
  local spy = SpyModules(ns, sync)
  _G.TruePlayedDB = { chars = {} }
  ns.Core.CheckSwap()
  T.eq(spy.reconcile, { { 400010, 1010 } })
  sync.level = 9   -- a level-up since the sync: the level part is stale
  _G.TruePlayedDB = { chars = {} }
  ns.Core.CheckSwap()
  T.eq(spy.reconcile[2], { 400010 })
  sync.restored = true   -- restored after /reload: display only
  _G.TruePlayedDB = { chars = {} }
  ns.Core.CheckSwap()
  T.eq(#spy.reconcile, 2)
  T.eq(#spy.replay, 3)
end)

T.test("CheckSwap: a newer schema appearing late switches to readOnly", function()
  local ns = Load()
  Stub.LoginSequence()
  local spy = SpyModules(ns, nil)
  local swapped = 0
  ns.RegisterMessage("DB_SWAPPED", "test", function() swapped = swapped + 1 end)
  local newer = { schema = 7, settings = { exclude = { inn = true } }, chars = {} }
  local snapshot = Stub.DeepCopy(newer)
  _G.TruePlayedDB = newer
  ns.Core.CheckSwap()
  T.ok(ns.readOnly)
  T.ok(ns.db == newer)
  T.eq(swapped, 1)
  T.eq(#spy.replay, 0)
  T.eq(ns.GetMask(), 2)
  T.eq(ns.char.guid, GUID)
  T.eq(newer, snapshot, "the newer table is never written")
  T.eq(CountPrinted(ns.L.SCHEMA_NEWER), 1)
  _G.TruePlayedDB = { chars = {} }
  ns.Core.CheckSwap()
  T.ok(ns.db == newer, "CheckSwap disabled in readOnly")
end)

T.test("CheckSwap: a table whose swap fails is reported once, not every tick", function()
  local ns = Load()
  Stub.LoginSequence()
  ns.Tracker = { ReplayDelta = function() end }
  ns.Stats = { ResetCaches = function() end }
  local bad = setmetatable({}, { __index = function() error("broken table") end })
  _G.TruePlayedDB = bad
  ns.Core.CheckSwap()
  Stub.Advance(5)
  T.eq(#Stub.errors, 1)
  T.allowErrors()
end)

---------------------------------------------------------------------------
-- Ticker
---------------------------------------------------------------------------
T.test("Core.Tick ignores its argument; the ticker drives TICK every second", function()
  local ns = Load()
  local ticks = {}
  ns.RegisterMessage("TICK", "test", function(_, now) ticks[#ticks + 1] = now end)
  Stub.LoginSequence()
  Stub.Advance(3)
  T.eq(ticks, { 1001.0, 1002.0, 1003.0 })
  ns.Core.Tick("not a number")
  ns.Core.Tick({})
  T.eq(#ticks, 5)
  T.eq(ticks[5], Stub.Now())
  T.eq(#Stub.errors, 0)
end)

T.test("Core.Tick calls Tracker.Tick(now), then Tokens.UpdateContext only when active", function()
  local ns = Load()
  local log = {}
  local active = false
  ns.Tracker = { Tick = function(now) log[#log + 1] = "tracker@" .. now end }
  ns.Tokens = {
    IsActive = function() return active end,
    UpdateContext = function() log[#log + 1] = "tokens" end,
  }
  ns.RegisterMessage("TICK", "test", function() log[#log + 1] = "tick" end)
  Stub.LoginSequence()
  Stub.Advance(1)
  T.eq(log, { "tracker@" .. 1001.0, "tick" })
  active = true
  Stub.Advance(1)
  T.eq(log, { "tracker@" .. 1001.0, "tick", "tracker@" .. 1002.0, "tokens", "tick" })
end)

T.test("StartTickProfile prints PERF_TICK_FMT after n ticks, then disarms", function()
  local ns = Load()
  Stub.LoginSequence()
  ns.Core.StartTickProfile(3)
  Stub.Advance(2)
  local n = #Stub.printed
  Stub.Advance(1)
  T.eq(#Stub.printed, n + 1)
  T.ok(LastPrinted():find("Tick: 0.000 ms on average, 0.000 ms max over 3 ticks", 1, true), LastPrinted())
  Stub.Advance(5)
  T.eq(#Stub.printed, n + 1, "disarmed")
end)

---------------------------------------------------------------------------
-- Resets
---------------------------------------------------------------------------
T.test("ResetChar(current) rebuilds the record in place and keeps identity", function()
  local ns = Load()
  Stub.LoginSequence()
  local char = ns.char
  char.life.s.w = 1000
  char.levels[10] = ns.Core.NewLevel()
  char.base = { at = 1, total = 5, level = 3 }
  char.ema[1].a = 50
  local calls = {}
  ns.Tracker = { OnCharReset = function() calls[#calls + 1] = "tracker" end }
  ns.Played = { Request = function(reason) calls[#calls + 1] = reason end }
  local got
  ns.RegisterMessage("CHAR_RESET", "test", function(_, guid) got = guid end)
  Stub.Advance(10)
  T.ok(ns.Core.ResetChar(GUID))
  T.ok(ns.char == char, "same table")
  T.ok(ns.db.chars[GUID] == char)
  T.eq(char.life, ns.Core.NewLife())
  T.eq(char.levels, {})
  T.eq(char.base, nil)
  T.eq(char.ema[1].a, 0)
  T.eq(char.guid, GUID)
  T.eq(char.name, "Lutak")
  T.eq(char.surname, "Ombrevent")
  T.eq(char.class, "MAGE")
  T.eq(char.firstSeen, time())
  T.eq(calls, { "tracker", "reset" })
  T.eq(got, GUID)
  T.eq(LastPrinted(), ns.L.CHAT_PREFIX .. string.format(ns.L.RESET_CHAR_DONE_FMT, "Lutak Ombrevent"))
end)

T.test("ResetChar(other guid) deletes that record only", function()
  local ns = Load()
  Stub.LoginSequence()
  ns.db.chars["Player-1-OTHER"] = { guid = "Player-1-OTHER", name = "Alt", life = ns.Core.NewLife() }
  local got
  ns.RegisterMessage("CHAR_RESET", "test", function(_, guid) got = guid end)
  T.ok(ns.Core.ResetChar("Player-1-OTHER"))
  T.eq(ns.db.chars["Player-1-OTHER"], nil)
  T.ok(ns.db.chars[GUID] == ns.char)
  T.eq(got, "Player-1-OTHER")
  T.ok(LastPrinted():find("Alt", 1, true))
  T.no(ns.Core.ResetChar("Player-1-NOBODY"))
end)

T.test("ResetRate replaces the EMA and sends XP_CHANGED", function()
  local ns = Load()
  Stub.LoginSequence()
  ns.char.ema[1].a = 99
  ns.char.ema[8].d = 500
  local n = 0
  ns.RegisterMessage("XP_CHANGED", "test", function() n = n + 1 end)
  T.ok(ns.Core.ResetRate())
  T.eq(ns.char.ema, ns.Core.NewEma())
  T.eq(n, 1)
end)

T.test("EnsureChar creates or completes a record and refreshes identity", function()
  local ns = Load()
  Stub.LoginSequence()
  Stub.player.surname = nil
  Stub.player.faction = "Alliance"
  local rec = ns.Core.EnsureChar(ns.db, GUID)
  T.ok(rec == ns.char)
  T.eq(rec.surname, nil)
  T.eq(rec.faction, "Alliance")
  local other = ns.Core.EnsureChar(ns.db, "Player-9-X")
  T.eq(other.guid, "Player-9-X")
  T.eq(other.name, nil, "identity only for the logged-in player")
  T.ok(ns.db.chars["Player-9-X"] == other)
  T.eq(#other.ema, 8)
end)

---------------------------------------------------------------------------
-- Constructors, constants
---------------------------------------------------------------------------
T.test("constructors return the frozen shapes", function()
  local ns = Load()
  local Core, C = ns.Core, ns.C
  T.eq(Core.NewBucket(), { s = {}, xp = 0, d = 0 })
  T.eq(Core.NewLife(), { s = {}, xp = 0, xa = 0, xr = 0, xq = 0, d = 0, est = 0 })
  T.eq(Core.NewLevel(), { s = {}, z = {}, xp = 0, xa = 0, xr = 0, xq = 0, d = 0 })
  T.eq(Core.NewZone(), { s = {}, xp = 0 })
  local e = Core.NewEma()
  T.eq(#e, 8)
  T.eq(e[3], { a = 0, r = 0, q = 0, d = 0 })
  T.ok(e[1] ~= e[2])
  local s = Core.NewSession()
  T.eq(s.l0, 10)
  T.eq(s.p0, nil)
  T.eq(s.t0, time())
  T.eq(s.at, time())
  T.eq(s.g, Stub.Now())
  T.eq(s.s, {})
  local db = Core.NewDB()
  T.eq(db.schema, C.SCHEMA)
  T.eq(db.settings, C.DEFAULTS)
  T.ok(db.settings ~= C.DEFAULTS, "a copy")
  T.eq(db.chars, {})
end)

T.test("C.INCLUDED matches the exclusion-mask arithmetic", function()
  local C = Load().C
  for m = 0, 7 do
    local afk, inn, city = m % 2 == 1, math.floor(m / 2) % 2 == 1, math.floor(m / 4) % 2 == 1
    local row = C.INCLUDED[m]
    T.eq(row.u, true)
    T.eq(row.w, true)
    T.eq(row.t, true)
    T.eq(row.W, not afk)
    T.eq(row.T, not afk)
    T.eq(row.i, not inn)
    T.eq(row.I, not (afk or inn))
    T.eq(row.c, not city)
    T.eq(row.C, not (afk or city))
    -- instance keys behave like w / W: only the AFK exclusion removes their AFK part
    for _, k in ipairs({ "d", "r", "p" }) do T.eq(row[k], true, k) end
    for _, k in ipairs({ "D", "R", "P" }) do T.eq(row[k], not afk, k) end
    -- dead and professions: never excluded
    T.eq(row.x, true); T.eq(row.f, true)
    local n = 0
    for _ in pairs(row) do n = n + 1 end
    T.eq(n, #C.STATE_KEYS, "one entry per state key")
  end
  T.eq(C.KEY.c[true], "C")
  T.eq(C.KEY.t[false], "t")
  T.eq(C.KEY.d[false], "d"); T.eq(C.KEY.d[true], "D")
  T.eq(C.KEY.r[true], "R"); T.eq(C.KEY.p[true], "P")
end)

T.test("state key lists: 17 keys, instance keys, active, AFK and activity partitions", function()
  local C = Load().C
  T.eq(C.STATE_KEYS, { "w", "W", "d", "D", "r", "R", "p", "P", "i", "I", "c", "C", "t", "T", "x", "f", "u" })
  T.eq(C.TRACKED_KEYS, { "w", "W", "d", "D", "r", "R", "p", "P", "i", "I", "c", "C", "t", "T", "x", "f" })
  T.eq(C.DEAD_KEYS, { "x" }); T.eq(C.PROF_KEYS, { "f" })
  T.eq(C.IS_ACTIVITY, { x = true, f = true })
  T.eq(C.ACTIVE_KEYS, { "w", "d", "r", "p", "t" })
  T.eq(C.AFK_KEYS, { "W", "D", "R", "P", "I", "C", "T" })
  T.eq(C.INSTANCE_KEYS, { "d", "D", "r", "R", "p", "P" })
  for _, k in ipairs(C.AFK_KEYS) do T.eq(C.IS_AFK[k], true, k) end
  T.eq(C.INSTANCE_KIND, { party = "d", scenario = "d", raid = "r", pvp = "p", arena = "p" })
  T.eq(C.IS_INSTANCE.D, "d"); T.eq(C.IS_INSTANCE.r, "r"); T.eq(C.IS_INSTANCE.P, "p")
  T.eq(C.IS_INSTANCE.w, nil)
  -- every tracked key is exactly one of: active, AFK, inn (active), city (active), dead,
  -- professions
  for _, k in ipairs(C.TRACKED_KEYS) do
    local n = 0
    for _, list in ipairs({ C.ACTIVE_KEYS, C.AFK_KEYS, { "i" }, { "c" }, C.DEAD_KEYS, C.PROF_KEYS }) do
      for _, x in ipairs(list) do if x == k then n = n + 1 end end
    end
    T.eq(n, 1, "partition " .. k)
  end
end)

T.test("VERSION is 'dev' when unpackaged; client detection", function()
  local ns = Load()
  T.eq(ns.ADDON, "TruePlayed")
  T.eq(ns.VERSION, "dev")
  T.eq(ns.interface, 16001)
  T.ok(ns.isForever)
  T.no(ns.isEra)
  T.no(ns.readOnly)
  Stub.meta.Version = "0.1.0-beta.1"
  Stub.build.interface = 11508
  ns = Load()
  T.eq(ns.VERSION, "0.1.0-beta.1")
  T.no(ns.isForever)
  T.ok(ns.isEra)
end)

---------------------------------------------------------------------------
-- Util
---------------------------------------------------------------------------
T.test("Util: Bump, AddInto, CopyDefaults, DeepCopy", function()
  local U = Load().Util
  local t = {}
  U.Bump(t, "w", 5)
  U.Bump(t, "w", 2)
  T.eq(t, { w = 7 })
  local dst = { s = { w = 1 }, xp = 10, name = "x" }
  U.AddInto(dst, { s = { w = 2, W = 3 }, xp = 5, z = { [1411] = { s = { c = 1 } } }, name = "ignored", flag = true })
  T.eq(dst, { s = { w = 3, W = 3 }, xp = 15, z = { [1411] = { s = { c = 1 } } }, name = "x" })
  local d = { a = 1, list = { "x" }, sub = { k = false } }
  local defaults = { a = 2, b = 3, list = { "d1", "d2" }, sub = { k = true, j = 4 }, newList = { "n" } }
  T.ok(U.CopyDefaults(d, defaults) == d)
  T.eq(d, { a = 1, b = 3, list = { "x" }, sub = { k = false, j = 4 }, newList = { "n" } })
  T.ok(d.newList ~= defaults.newList, "copied, not shared")
  local src = { a = { b = { c = 1 } } }
  local copy = U.DeepCopy(src)
  copy.a.b.c = 2
  T.eq(src.a.b.c, 1)
end)

T.test("Util: IsSecret and SafeRead test secrecy before anything else", function()
  local U = Load().Util
  T.ok(U.IsSecret(Stub.SECRET))
  T.no(U.IsSecret(true))
  T.no(U.IsSecret(nil))
  Stub.secret.afk = true
  local ok, v, why = U.SafeRead(UnitIsAFK, "player")
  T.no(ok)
  T.eq(v, nil)
  T.eq(why, "secret")
  Stub.secret.afk = false
  ok, v = U.SafeRead(UnitIsAFK, "player")
  T.ok(ok)
  T.eq(v, false)
  Stub.player.afk = true
  ok, v = U.SafeRead(UnitIsAFK, "player")
  T.ok(ok)
  T.eq(v, true)
  ok, _, why = U.SafeRead(function() error("x") end)
  T.no(ok)
  T.eq(why, "error")
  ok, _, why = U.SafeRead(GetXPExhaustion)
  T.no(ok)
  T.eq(why, "nil")
  Stub.player.rest = 500
  ok, v = U.SafeRead(GetXPExhaustion)
  T.ok(ok)
  T.eq(v, 500)
  T.no(U.SafeRead(nil))
end)

T.test("Util: IsMaxLevel, CharName, Round, Clamp, Words", function()
  local U = Load().Util
  T.no(U.IsMaxLevel())
  Stub.player.level = 60
  T.ok(U.IsMaxLevel())
  Stub.player.level, Stub.player.maxLevel = 30, 30
  T.ok(U.IsMaxLevel(), "follows GetMaxPlayerLevel, never a hard-coded 60")
  Stub.player.maxLevel = 60
  Stub.player.xpDisabled = true
  T.ok(U.IsMaxLevel())
  T.eq(U.CharName({ name = "Lutak", surname = "Ombrevent" }), "Lutak Ombrevent")
  T.eq(U.CharName({ name = "Lutak" }), "Lutak")
  T.eq(U.CharName({ name = "Lutak", surname = "" }), "Lutak")
  T.eq(U.Round(2.5), 3)
  T.eq(U.Round(2.49), 2)
  T.eq(U.Round(-2.5), -2)
  T.eq(U.Clamp(5, 1, 3), 3)
  T.eq(U.Clamp(0, 1, 3), 1)
  T.eq(U.Clamp(2, 1, 3), 2)
  local a, b, c = U.Words("  Stats   ZONES extra more ")
  T.eq({ a, b, c }, { "stats", "zones", "extra" })
  a, b, c = U.Words("")
  T.eq(a, "")
  T.eq(b, nil)
  T.eq(c, nil)
  a, b = U.Words("AFK")
  T.eq(a, "afk")
  T.eq(b, nil)
  T.eq(U.Words(nil), "")
end)

T.test("Util: Print uses the chat prefix; Debug is silent and allocation-free when off", function()
  local ns = Load()
  Stub.LoginSequence()
  local U, P = ns.Util, ns.L.CHAT_PREFIX
  U.Print("hello")
  T.eq(LastPrinted(), P .. "hello")
  U.Print("%d%% done", 50)
  T.eq(LastPrinted(), P .. "50% done")
  U.Print("100%")
  T.eq(LastPrinted(), P .. "100%", "verbatim without arguments")
  local n = #Stub.printed
  U.Debug("gain=%d", 5)
  T.eq(#Stub.printed, n)
  local kb = T.alloc(function(i) U.Debug("gain=%d dRest=%d", i, -i) end, 1000)
  T.ok(kb <= 0.5, "disabled Debug allocated " .. kb .. " KB")
  ns.Core.SetSetting("debug", true)
  U.Debug("gain=%d dRest=%d", 5, -10)
  T.ok(LastPrinted():find("gain=5 dRest=-10", 1, true))
  U.Debug("value %s", nil)
  U.Debug("float %d", 1.5)
  T.eq(#Stub.printed, n + 3)
end)

T.test("SafeCall returns values and routes errors to the error handler", function()
  local ns = Load()
  T.eq(ns.SafeCall(function(a, b) return a + b end, 1, 2), 3)
  ns.SafeCall(function() error("kaboom") end)
  T.eq(#Stub.errors, 1)
  T.match(Stub.errors[1], "kaboom")
  T.allowErrors()
end)

---------------------------------------------------------------------------
-- Bus (3.4)
---------------------------------------------------------------------------
T.test("bus: registration order, replace in place, name passed first", function()
  local ns = Load()
  local log = {}
  ns.RegisterMessage("M", "a", function(_, x) log[#log + 1] = "a" .. x end)
  ns.RegisterMessage("M", "b", function(_, x) log[#log + 1] = "b" .. x end)
  ns.RegisterMessage("M", "c", function(_, x) log[#log + 1] = "c" .. x end)
  ns.SendMessage("M", 1)
  T.eq(log, { "a1", "b1", "c1" })
  ns.RegisterMessage("M", "b", function(_, x) log[#log + 1] = "B" .. x end)
  ns.SendMessage("M", 2)
  T.eq(log, { "a1", "b1", "c1", "a2", "B2", "c2" })
  local name
  ns.RegisterMessage("N", "x", function(m) name = m end)
  ns.SendMessage("N")
  T.eq(name, "N")
  ns.SendMessage("NOBODY_LISTENS", 1)
end)

T.test("bus: a handler removed during dispatch is not called", function()
  local ns = Load()
  local log = {}
  ns.RegisterMessage("M", "a", function() log[#log + 1] = "a"; ns.UnregisterMessage("M", "c") end)
  ns.RegisterMessage("M", "b", function() log[#log + 1] = "b"; ns.UnregisterMessage("M", "b") end)
  ns.RegisterMessage("M", "c", function() log[#log + 1] = "c" end)
  ns.SendMessage("M")
  T.eq(log, { "a", "b" })
  ns.SendMessage("M")
  T.eq(log, { "a", "b", "a" })
end)

T.test("bus: a handler added during dispatch runs from the next dispatch", function()
  local ns = Load()
  local log = {}
  local added = false
  ns.RegisterMessage("M", "a", function()
    log[#log + 1] = "a"
    if not added then
      added = true
      ns.RegisterMessage("M", "d", function() log[#log + 1] = "d" end)
    end
  end)
  ns.RegisterMessage("M", "b", function() log[#log + 1] = "b" end)
  ns.SendMessage("M")
  T.eq(log, { "a", "b" })
  ns.SendMessage("M")
  T.eq(log, { "a", "b", "a", "b", "d" })
  -- removed and re-registered during the same dispatch: called once per dispatch
  local count = 0
  local function selfRenew()
    count = count + 1
    ns.UnregisterMessage("R", "x")
    ns.RegisterMessage("R", "x", selfRenew)
  end
  ns.RegisterMessage("R", "x", selfRenew)
  ns.SendMessage("R")
  ns.SendMessage("R")
  T.eq(count, 2)
end)

T.test("bus: a failing handler does not stop the others", function()
  local ns = Load()
  local called = false
  ns.RegisterMessage("M", "bad", function() error("boom") end)
  ns.RegisterMessage("M", "good", function() called = true end)
  ns.SendMessage("M")
  T.ok(called)
  T.eq(#Stub.errors, 1)
  T.match(Stub.errors[1], "boom")
  T.allowErrors()
end)

T.test("bus: game events reach handlers through one frame, unregistered with the last handler", function()
  local ns = Load()
  local base = Stub.CountRegistered("PLAYER_DEAD")
  local got = {}
  T.ok(ns.RegisterEvent("PLAYER_DEAD", "a", function(event, x) got[#got + 1] = event .. ":" .. tostring(x) end))
  T.ok(ns.RegisterEvent("PLAYER_DEAD", "b", function() got[#got + 1] = "b" end))
  T.eq(Stub.CountRegistered("PLAYER_DEAD"), base + 1, "one frame for all handlers")
  Stub.Fire("PLAYER_DEAD", 7)
  T.eq(got, { "PLAYER_DEAD:7", "b" })
  ns.UnregisterEvent("PLAYER_DEAD", "a")
  T.eq(Stub.CountRegistered("PLAYER_DEAD"), base + 1)
  ns.UnregisterEvent("PLAYER_DEAD", "b")
  T.eq(Stub.CountRegistered("PLAYER_DEAD"), base, "frame unregistered with the last handler")
  Stub.Fire("PLAYER_DEAD", 8)
  T.eq(#got, 2)
  T.ok(ns.RegisterEvent("PLAYER_DEAD", "a", function() got[#got + 1] = "again" end))
  Stub.Fire("PLAYER_DEAD")
  T.eq(got[3], "again")
end)

T.test("bus: an unknown event is refused without error", function()
  local ns = Load()
  T.no(ns.RegisterEvent("UNKNOWN_TEST_EVENT", "test", function() end))
  T.eq(Stub.CountRegistered("UNKNOWN_TEST_EVENT"), 0)
  T.ok(ns.RegisterEvent("PLAYER_DEAD", "test", function() end))
  T.eq(#Stub.errors, 0)
end)

T.test("bus: 1000 SendMessage(TICK) with 3 handlers allocate nothing", function()
  local ns = Load()
  local n = 0
  local function h1() n = n + 1 end
  local function h2(_, now) if now > 0 then n = n + 1 end end
  local function h3() end
  ns.RegisterMessage("TICK", "h1", h1)
  ns.RegisterMessage("TICK", "h2", h2)
  ns.RegisterMessage("TICK", "h3", h3)
  local function send() ns.SendMessage("TICK", 1000.5) end
  send()
  local kb = T.alloc(send, 1000)
  T.ok(kb <= 0.5, "allocated " .. kb .. " KB")
  T.eq(n, 2002)
end)

---------------------------------------------------------------------------
-- Performance helpers (6.6)
---------------------------------------------------------------------------
T.test("GetMemoryKB and GetCPU (scriptProfile and C_AddOnProfiler)", function()
  local ns = Load()
  Stub.LoginSequence()
  local Core = ns.Core
  T.eq(Core.GetMemoryKB(), 123.4)
  T.eq(Stub.calls.UpdateAddOnMemoryUsage, 1)
  local total, perMin, avg, peak = Core.GetCPU()
  T.eq({ total, perMin, avg, peak }, {})
  Stub.cvars.scriptProfile = "1"
  Stub.cpuMS = 600
  Stub.Advance(120)
  total, perMin = Core.GetCPU()
  T.eq(total, 600)
  T.near(perMin, 300, 1e-6, "600 ms over 2 minutes")
  C_AddOnProfiler = {
    IsEnabled = function() return true end,
    GetAddOnMetric = function(_, metric) return metric == 1 and 0.02 or 0.5 end,
  }
  Enum.AddOnProfilerMetric = { RecentAverageTime = 1, PeakTime = 2 }
  local _, _, a, p = Core.GetCPU()
  T.eq(a, 0.02)
  T.eq(p, 0.5)
end)

---------------------------------------------------------------------------
-- Locales (8)
---------------------------------------------------------------------------
local function RawKeys(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local function LoadLocaleTables()
  local enNs = {}
  assert(loadfile(Stub.ROOT .. "Locales/enUS.lua"))("TruePlayed", enNs)
  Stub.locale = "frFR"
  local frNs = { L = {} }
  assert(loadfile(Stub.ROOT .. "Locales/frFR.lua"))("TruePlayed", frNs)
  return RawKeys(enNs.L), frNs.L
end

local function Specs(s)
  local out = {}
  for spec in s:gsub("%%%%", ""):gmatch("%%[%d%.%-]*[sd]") do out[#out + 1] = spec end
  return out
end

T.test("locale: frFR fills only when GetLocale() == frFR; a missing key returns its name", function()
  local en = Load("enUS")
  T.eq(en.L.ON, "on")
  T.eq(en.L.THOUSANDS_SEP, ",")
  T.eq(en.L.SOME_MISSING_KEY, "SOME_MISSING_KEY")
  local fr = Load("frFR")
  T.eq(fr.L.ON, "activé")
  T.eq(fr.L.THOUSANDS_SEP, "\194\160")
  T.eq(fr.L.SOME_MISSING_KEY, "SOME_MISSING_KEY")
end)

T.test("locale: every enUS key has a frFR value and vice versa", function()
  local en, fr = LoadLocaleTables()
  local missing, extra, n = {}, {}, 0
  for k in pairs(en) do
    n = n + 1
    if fr[k] == nil then missing[#missing + 1] = k end
  end
  for k in pairs(fr) do
    if en[k] == nil then extra[#extra + 1] = k end
  end
  table.sort(missing)
  table.sort(extra)
  T.eq(missing, {}, "keys missing in frFR")
  T.eq(extra, {}, "keys only in frFR")
  T.ok(n >= 272, "the frozen 8.2 table has 272 keys, got " .. n)
end)

-- The names of the languages offered only on a client in that language (Cyrillic,
-- Hangul, Han: C.LANGUAGES_NATIVE_ONLY) are the one exception to Latin-1: they are shown
-- only where the client's font draws them (tests/test_locales.lua checks their values).
local NATIVE_NAMES = { LANG_RURU = true, LANG_KOKR = true, LANG_ZHCN = true, LANG_ZHTW = true }

T.test("locale: Latin-1 only, same format specifiers in enUS and frFR", function()
  local en, fr = LoadLocaleTables()
  for k, v in pairs(en) do
    T.eq(type(v), "string", k)
    T.ok(IsLatin1(v) or NATIVE_NAMES[k], "enUS " .. k)
    T.ok(IsLatin1(fr[k]) or NATIVE_NAMES[k], "frFR " .. k)
    if k ~= "DATE_FMT" and k ~= "TIME_FMT" then
      T.eq(Specs(fr[k]), Specs(v), "format specifiers of " .. k)
    end
  end
end)

---------------------------------------------------------------------------
-- The stub itself (9.2): the other test files rely on these behaviours
---------------------------------------------------------------------------
T.test("stub: timers fire by due time then creation order; tickers receive themselves", function()
  local log = {}
  C_Timer.After(0.5, function() log[#log + 1] = "b" end)
  C_Timer.After(0.2, function() log[#log + 1] = "a" end)
  C_Timer.After(0.5, function() log[#log + 1] = "c" end)
  local tk
  tk = C_Timer.NewTicker(1, function(self) log[#log + 1] = (self == tk) and "tick" or "bad" end)
  Stub.Advance(1)
  T.eq(log, { "a", "b", "c", "tick" })
  Stub.Advance(1, 0.25)
  T.eq(log[5], "tick")
  tk:Cancel()
  T.ok(tk:IsCancelled())
  Stub.Advance(3)
  T.eq(#log, 5)
  local n = 0
  C_Timer.NewTicker(1, function() n = n + 1 end)
  Stub.Advance(1000, 1000)
  T.eq(n, 1, "a frozen client fires a late ticker once")
  Stub.Advance(1)
  T.eq(n, 2)
end)

T.test("stub: Advance with only a ticker allocates nothing", function()
  local n = 0
  C_Timer.NewTicker(1, function() n = n + 1 end)
  Stub.Advance(5)
  local kb = T.alloc(function() Stub.Advance(1) end, 600)
  T.ok(kb <= 0.5, "allocated " .. kb .. " KB")
  T.eq(n, 605)
end)

T.test("stub: clocks and server advance together; /played answers 0.1 s later", function()
  T.eq(GetTime(), 1000.0)
  T.eq(time(), 1790000000)
  Stub.Advance(10)
  T.eq(time(), 1790000010)
  T.eq(Stub.server.total, 360010)
  local got
  local f = CreateFrame("Frame")
  f:RegisterEvent("TIME_PLAYED_MSG")
  f:SetScript("OnEvent", function(_, _, total, level) got = { total, level } end)
  RequestTimePlayed()
  T.eq(Stub.requests, 1)
  T.eq(got, nil)
  Stub.Advance(0.1)
  T.eq(got, { 360010, 5010 })
  T.eq(#Stub.displayed, 1, "ChatFrame1 shows it through ChatFrameUtil.DisplayTimePlayed")
  local seen
  hooksecurefunc("RequestTimePlayed", function() seen = Stub.requests end)
  RequestTimePlayed()
  T.eq(seen, 2)
  Stub.server.frozen = true
  Stub.Advance(5)
  T.eq(math.floor(Stub.server.total), 360010)
end)

T.test("stub: GrantXP levels up, restarts server.levelPlayed, fires events in order", function()
  local log = {}
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "UPDATE_EXHAUSTION" }) do
    f:RegisterEvent(e)
  end
  f:SetScript("OnEvent", function(_, e, a) log[#log + 1] = (e == "PLAYER_LEVEL_UP") and (e .. a) or e end)
  local p = Stub.player
  p.rest = 1000
  Stub.GrantXP(7600 + 8800 + 100, { quest = 300, restDrop = 200 })
  T.eq({ p.level, p.xp, p.max, p.rest }, { 12, 100, Stub.xpTable[12], 800 })
  T.eq(Stub.server.levelPlayed, 0)
  T.eq(log, { "QUEST_TURNED_IN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP11", "PLAYER_LEVEL_UP12", "UPDATE_EXHAUSTION" })
  Stub.GrantXP(10, { restDrop = 10, order = "exhaustionFirst" })
  T.eq(log[6], "UPDATE_EXHAUSTION")
  T.eq(log[7], "PLAYER_XP_UPDATE")
  Stub.GrantXP(p.max, { levelEventFirst = true })
  T.eq(log[8], "PLAYER_LEVEL_UP13")
  T.eq(log[9], "PLAYER_XP_UPDATE")
  Stub.GrantXP(p.max, { noLevelEvent = true })
  T.eq(#log, 10)
  T.eq(p.level, 14)
end)

T.test("stub: Restart keeps the world; crash reloads the last save; playElsewhere", function()
  _G.TruePlayedDB = { v = 1 }
  Stub.SaveVariables()
  _G.TruePlayedDB.v = 2
  Stub.player.level = 20
  Stub.Restart({ crash = true, offline = 60, files = {} })
  T.eq(_G.TruePlayedDB, { v = 1 }, "the unsaved change is lost")
  T.eq(Stub.Now(), 1060.0)
  T.eq(Stub.server.total, 360000, "offline: the server does not advance")
  T.eq(Stub.player.level, 20)
  Stub.player.level, Stub.player.xp, Stub.player.max = 10, 0, 7600
  Stub.Restart({ crash = true, playElsewhere = { sec = 3600, xp = 5000 }, files = {} })
  T.eq(Stub.server.total, 363600)
  T.eq(Stub.server.levelPlayed, 8600)
  T.eq(Stub.player.xp, 5000)
  -- 5000 + 9600 XP: level 11 reached after 2600, 7000 XP into level 11
  Stub.Restart({ crash = true, playElsewhere = { sec = 1000, xp = 9600 }, files = {} })
  T.eq(Stub.player.level, 11)
  T.eq(Stub.player.xp, 7000)
  T.eq(Stub.server.levelPlayed, math.floor(1000 * 7000 / 9600), "time after the level-up, by XP share")
  Stub.Restart({ reload = true, online = 4, files = {} })
  T.eq(Stub.server.total, 364604, "online: the server keeps counting")
end)

T.test("stub: SaveVariables drops functions and splits shared tables", function()
  local shared = { x = 1 }
  _G.TruePlayedDB = { a = shared, b = shared, f = function() end }
  Stub.SaveVariables()
  T.eq(Stub.saved, { a = { x = 1 }, b = { x = 1 } })
  T.ok(Stub.saved.a ~= Stub.saved.b)
end)

T.test("stub: Reset removes globals created during a test", function()
  SOME_TEST_GLOBAL = 1
  local f = CreateFrame("Frame", "TruePlayedTestFrame")
  T.ok(_G.TruePlayedTestFrame == f)
  Stub.Reset()
  T.eq(rawget(_G, "SOME_TEST_GLOBAL"), nil)
  T.eq(rawget(_G, "TruePlayedTestFrame"), nil)
  T.ok(rawget(_G, "UIParent") ~= nil)
  T.ok(rawget(_G, "GameTooltip") ~= nil)
end)

T.test("stub: frames, templates, font strings, tooltip mock, secret values", function()
  T.raises(function() CreateFrame("Frame", nil, UIParent, "NoSuchTemplate") end)
  T.raises(function() CreateFrame("Frame"):SetBackdrop({}) end)
  local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  f:SetBackdrop({})
  f:SetScript("OnUpdate", function() end)
  T.eq(Stub.onUpdateCount, 1)
  local fs = f:CreateFontString()
  fs:SetText("|cffffffffab|r")
  T.eq(fs:GetStringWidth(), 12)
  T.eq(fs._setTextCount, 1)
  f:SetSize(100, 20)
  f:SetPoint("TOP", UIParent, "TOP", 0, -10)
  local x, y = f:GetCenter()
  T.eq({ x, y }, { 960, 1060 })
  f:SomeUnknownMethod()
  T.eq(f.someField, nil)
  local cb = CreateFrame("CheckButton", nil, UIParent, "UICheckButtonTemplate")
  cb:SetChecked(true)
  T.ok(cb:GetChecked())
  T.ok(cb.Text ~= nil)
  GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  GameTooltip:AddLine("a")
  GameTooltip:AddDoubleLine("b", "c")
  T.eq(GameTooltip._lines, { { "a" }, { "b", "c" } })
  T.eq(GameTooltip:NumLines(), 2)
  T.ok(GameTooltip:GetOwner() == UIParent)
  GameTooltip:Show()
  T.ok(GameTooltip:IsShown())
  GameTooltip:Hide()
  T.eq(GameTooltip:GetOwner(), nil)
  Stub.secret.afk = true
  T.ok(issecretvalue(UnitIsAFK("player")))
  T.no(issecretvalue(true))
  T.raises(function() C_Map.GetMapInfo("i123") end)
  T.eq(C_Map.GetMapInfo(1454).parentMapID, 1414)
end)

---------------------------------------------------------------------------
-- Integration (all modules, loaded from the TOC)
---------------------------------------------------------------------------
T.test("integration (all modules): fresh login, play, logout and restart", function()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(120)
  T.ok(ns.ready)
  T.ok(ns.char == ns.db.chars[GUID])
  Stub.Logout()
  T.eq(Stub.saved.lastVersion, "dev")
  ns = Stub.Restart()
  T.ok(ns.ready)
  T.ok(ns.char == ns.db.chars[GUID])
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("integration (all modules): a readOnly session saves exactly what was loaded", function()
  local sv = { schema = 99, settings = { widget = { shown = false } }, chars = {} }
  local snapshot = Stub.DeepCopy(sv)
  _G.TruePlayedDB = sv
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  T.ok(ns.readOnly)
  Stub.Advance(30)
  Stub.GrantXP(500)
  Stub.SetAFK(true)
  Stub.Advance(15)
  Stub.Logout()
  T.eq(Stub.saved, snapshot)
end)

---------------------------------------------------------------------------
-- The global is published only at PLAYER_LOGOUT (FOREVER-2, SPEC 5.1, 5.16):
-- Forever may apply the SavedVariables file late and skips it when the global
-- already exists, so an early publication would overwrite the whole history.
---------------------------------------------------------------------------

-- Counts the ticks that saw the global differ from box.want. TICK is sent after
-- CheckSwap, where a nil global used to be published.
local function WatchDB(ns)
  local box = { want = nil, bad = 0 }
  ns.RegisterMessage("TICK", "test-watch-db", function()
    if rawget(_G, "TruePlayedDB") ~= box.want then box.bad = box.bad + 1 end
  end)
  return box
end

-- The file saved by a first session (fresh install, 120 s played); the world
-- is kept for the next session.
local function SavedHistory()
  Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(120)
  Stub.Logout()
  local real = Stub.DeepCopy(Stub.saved)
  Stub.Reset({ keepWorld = true })
  return real
end

T.test("integration (all modules): fresh install, the global stays nil until PLAYER_LOGOUT", function()
  local ns = Stub.LoadAddon()
  local watch = WatchDB(ns)
  Stub.LoginSequence()
  T.eq(rawget(_G, "TruePlayedDB"), nil, "not published at PLAYER_LOGIN")
  Stub.Advance(120)
  Stub.GrantXP(500)
  Stub.Advance(5)
  T.eq(rawget(_G, "TruePlayedDB"), nil, "not published during play")
  T.eq(watch.bad, 0, "nil at every tick")
  local db, char = ns.db, ns.char
  T.ok(char == db.chars[GUID] and char.life.s.w >= 120, "tracking in the private table")
  T.ok(char.life.xp > 0)
  Stub.Logout()
  T.ok(rawget(_G, "TruePlayedDB") == db, "published at PLAYER_LOGOUT")
  local saved = Stub.saved
  T.eq(saved.lastVersion, "dev")
  T.eq(saved.chars[GUID].life, char.life, "the saved content is the tracked data")
  T.eq(saved.chars[GUID].last.g, Stub.Now(), "with the Tracker's logout save")
end)

T.test("integration (all modules): a table applied 5 s after PLAYER_LOGIN is adopted, never overwritten", function()
  local real = SavedHistory()
  local realW, createdAt = real.chars[GUID].life.s.w, real.createdAt
  local ns = Stub.LoadAddon()
  local watch = WatchDB(ns)
  Stub.LoginSequence()
  Stub.Advance(5)
  T.eq(rawget(_G, "TruePlayedDB"), nil)
  T.ok(ns.db ~= nil and ns.db.chars[GUID] == ns.char, "tracking in a private table meanwhile")
  _G.TruePlayedDB = real                   -- Forever applies the file at +5 s
  watch.want = real
  Stub.Advance(1)                          -- adopted at the next tick
  T.ok(ns.db == real and ns.char == real.chars[GUID], "adopted")
  local ch = ns.char
  T.eq(ch.life.s.w, realW + ns.Tracker.GetDelta().life.s.w, "history kept, this load's seconds added once")
  T.eq(#ch.sessions, 1, "the saved session closed into the ring")
  T.ok(ch.cur == ns.session)
  Stub.Advance(30)
  T.eq(watch.bad, 0, "the global was never written before PLAYER_LOGOUT")
  Stub.Logout()
  T.ok(rawget(_G, "TruePlayedDB") == real)
  T.eq(Stub.saved.createdAt, createdAt, "the saved file is the real history")
  T.eq(Stub.saved.chars[GUID].life.s.w, realW + ns.Tracker.GetDelta().life.s.w)
end)

T.test("integration (all modules): a table applied between the last tick and PLAYER_LOGOUT is adopted", function()
  local real = SavedHistory()
  local realW, createdAt = real.chars[GUID].life.s.w, real.createdAt
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(30)
  _G.TruePlayedDB = real                   -- applied after the last tick
  Stub.Logout()
  T.ok(ns.db == real and rawget(_G, "TruePlayedDB") == real, "adopted, not replaced by the private table")
  local saved = Stub.saved
  T.eq(saved.createdAt, createdAt)
  T.eq(saved.lastVersion, "dev")
  local rec = saved.chars[GUID]
  T.eq(rec.life.s.w, realW + ns.Tracker.GetDelta().life.s.w, "this load's seconds merged")
  T.eq(#rec.sessions, 1, "the saved session closed into the ring")
  T.eq(rec.last.g, Stub.Now(), "Core's handler ran first: the Tracker saved into the adopted table")
end)

T.test("integration (all modules): lastVersion is written into the table adopted at PLAYER_LOGOUT", function()
  local real = SavedHistory()
  real.lastVersion = "old"                 -- saved by an older TruePlayed
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(30)
  T.ok(ns.VERSION ~= "old")
  _G.TruePlayedDB = real                   -- applied after the last tick
  Stub.Logout()
  T.ok(ns.db == real and rawget(_G, "TruePlayedDB") == real, "adopted at PLAYER_LOGOUT")
  T.eq(real.lastVersion, ns.VERSION, "written after the swap, into the adopted table")
  T.eq(Stub.saved.lastVersion, ns.VERSION, "the saved file carries this version")
end)

T.test("integration (all modules): a late table whose swap fails is saved as applied, never replaced", function()
  local function Run(atLogout)
    Stub.Reset()
    local real = SavedHistory()
    local snapshot = Stub.DeepCopy(real)
    local ns = Stub.LoadAddon()
    Stub.LoginSequence()
    local migrate, tries = ns.Core.Migrate, 0
    ns.Core.Migrate = function(db)
      if db == real then
        tries = tries + 1
        error("migration failed")
      end
      return migrate(db)
    end
    Stub.Advance(5)
    if not atLogout then _G.TruePlayedDB = real end
    Stub.Advance(30)
    if atLogout then _G.TruePlayedDB = real end   -- after the last tick
    local own = ns.db
    Stub.Logout()
    T.eq(tries, 1, "tried once: not every tick, not again at PLAYER_LOGOUT")
    T.eq(#Stub.errors, 1, "reported once")
    T.match(Stub.errors[1], "migration failed")
    T.ok(ns.db == own and own ~= real, "the session kept its private table")
    T.ok(rawget(_G, "TruePlayedDB") == real, "the applied table is not replaced by the private one")
    T.eq(Stub.saved, snapshot, "the history is saved exactly as applied")
  end
  T.allowErrors()
  Run(false)
  Run(true)
end)

T.test("integration (all modules): a non-table global is replaced by the tracked data at PLAYER_LOGOUT", function()
  _G.TruePlayedDB = "garbage"              -- a corrupted file: not a table
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  T.ok(type(ns.db) == "table" and not ns.readOnly, "tracking in a private table")
  Stub.Advance(60)
  T.eq(rawget(_G, "TruePlayedDB"), "garbage", "left alone during play")
  local db, char = ns.db, ns.char
  T.ok(char == db.chars[GUID] and char.life.s.w >= 60, "the character is tracked")
  Stub.Logout()
  T.ok(rawget(_G, "TruePlayedDB") == db, "published at PLAYER_LOGOUT")
  local saved = Stub.saved
  T.eq(type(saved), "table", "a table is saved, not the garbage")
  T.eq(saved.lastVersion, ns.VERSION)
  T.eq(saved.chars[GUID].life, char.life, "with the tracked character")
end)

T.test("integration (all modules): a WTFix-style global set before ADDON_LOADED is adopted as before", function()
  local real = SavedHistory()
  local realW = real.chars[GUID].life.s.w
  _G.TruePlayedDB = real                   -- WTFix's ADDON_LOADED runs before ours (OptionalDeps)
  local ns = Stub.LoadAddon()
  local watch = WatchDB(ns)
  watch.want = real
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  T.ok(ns.db == real, "adopted at ADDON_LOADED")
  Stub.Fire("PLAYER_LOGIN")
  Stub.Fire("PLAYER_ENTERING_WORLD", true, false)
  Stub.Advance(30)
  T.ok(ns.char == real.chars[GUID])
  T.eq(watch.bad, 0)
  Stub.Logout()
  T.ok(rawget(_G, "TruePlayedDB") == real)
  T.eq(Stub.saved.chars[GUID].life.s.w, realW + ns.Tracker.GetDelta().life.s.w)
end)

T.test("integration (all modules): fresh install then /reload keeps the data", function()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(60)
  local w, createdAt, t0 = ns.char.life.s.w, ns.db.createdAt, ns.session.t0
  ns = Stub.Restart({ reload = true })     -- PLAYER_LOGOUT publishes, the game saves, the UI reloads
  T.ok(Stub.saved ~= nil, "saved at the /reload")
  T.ok(ns.db == _G.TruePlayedDB, "the file is adopted at ADDON_LOADED")
  T.eq(ns.db.createdAt, createdAt)
  T.eq(ns.char.life.s.w, w, "history kept")
  T.eq(ns.session.t0, t0, "same session after a /reload")
  Stub.Advance(10)
  Stub.Logout()
  T.eq(Stub.saved.chars[GUID].life.s.w, w + 10)
end)

T.test("integration (all modules): readOnly never writes the global, even when entered late", function()
  local function Run(atLogout)
    Stub.Reset()
    local newer = { schema = 99, settings = {}, chars = {} }
    local snapshot = Stub.DeepCopy(newer)
    local ns = Stub.LoadAddon()
    Stub.LoginSequence()
    Stub.Advance(5)
    if not atLogout then _G.TruePlayedDB = newer end
    Stub.Advance(30)
    if atLogout then _G.TruePlayedDB = newer end   -- after the last tick
    Stub.Logout()
    T.ok(ns.readOnly)
    T.ok(rawget(_G, "TruePlayedDB") == newer, "the newer table is never replaced")
    T.eq(Stub.saved, snapshot, "saved exactly as applied")
  end
  Run(false)
  Run(true)
end)

T.test("integration (all modules): /tpl reset char works while the global is unpublished", function()
  local ns = Stub.LoadAddon()
  Stub.LoginSequence()
  Stub.Advance(60)
  Stub.RunSlash("reset char")
  Stub.AcceptPopup()
  T.eq(rawget(_G, "TruePlayedDB"), nil)
  T.eq(ns.char.life.s.w or 0, 0, "record reset")
  Stub.Advance(10)
  Stub.Logout()
  T.ok(rawget(_G, "TruePlayedDB") == ns.db)
  T.eq(Stub.saved.chars[GUID].life.s.w, 10, "the reset record is what gets saved")
end)

---------------------------------------------------------------------------
-- Changed defaults and sparse settings (feedback F2)
---------------------------------------------------------------------------

T.test("defaults: no dark background, readable text, eta + mobs in slot 1", function()
  local ns = Load()
  local w = ns.C.DEFAULTS.widget
  T.eq(w.background, nil, "the on/off background is gone")
  T.eq(w.bgAlpha, 0)
  T.eq(w.textColor, false)
  T.eq(w.outline, "thin")
  T.eq(w.shadow, true)
  T.eq(w.qualityColors, true)
  T.eq(w.slots, { "eta_kills", "xph", "fps_latency" })
  T.eq(ns.C.DEFAULTS.graph, { window = 60 })
  Stub.LoginSequence()
  T.eq(ns.settings.widget.bgAlpha, 0)
  T.eq(ns.settings.widget.background, nil)
  T.eq(ns.settings.graph.window, 60)
end)

T.test("SetSetting: text colour, outline, shadow, background opacity, quality colours, graph window", function()
  local ns = Load()
  Stub.LoginSequence()
  local Core, w = ns.Core, ns.settings.widget
  local got = {}
  ns.RegisterMessage("SETTINGS_CHANGED", "test", function(_, path, value) got[#got + 1] = { path, value } end)
  -- colour: an array or an { r, g, b } table, clamped to 0..1, 3 decimals; false = built-in
  T.ok(Core.SetSetting("widget.textColor", { 1, 0.5, 0.25 }))
  T.eq(w.textColor, { 1, 0.5, 0.25 })
  T.eq(got[#got][1], "widget.textColor")
  T.ok(got[#got][2] == w.textColor, "payload is the stored value")
  T.no(Core.SetSetting("widget.textColor", { r = 1, g = 0.5, b = 0.25 }), "same colour")
  T.ok(Core.SetSetting("widget.textColor", { r = 0.123456, g = 2, b = -1 }))
  T.eq(w.textColor, { 0.123, 1, 0 })
  T.no(Core.SetSetting("widget.textColor", { 1, "x", 0 }))
  T.no(Core.SetSetting("widget.textColor", { 0 / 0, 0, 0 }))
  T.no(Core.SetSetting("widget.textColor", "red"))
  T.no(Core.SetSetting("widget.textColor", true))
  T.ok(Core.SetSetting("widget.textColor", false), "reset to the built-in colours")
  T.eq(w.textColor, false)
  T.eq(Core.GetSetting("widget.textColor"), false)
  -- outline, shadow, quality colours
  T.ok(Core.SetSetting("widget.outline", "thick")); T.eq(w.outline, "thick")
  T.ok(Core.SetSetting("widget.outline", "none")); T.eq(w.outline, "none")
  T.no(Core.SetSetting("widget.outline", "fat")); T.eq(w.outline, "none")
  T.ok(Core.SetSetting("widget.shadow", false)); T.eq(w.shadow, false)
  T.no(Core.SetSetting("widget.shadow", "no"))
  T.ok(Core.SetSetting("widget.qualityColors", false)); T.eq(w.qualityColors, false)
  -- background opacity: 0..1, step 0.05
  T.ok(Core.SetSetting("widget.bgAlpha", 0.5)); T.eq(w.bgAlpha, 0.5)
  T.ok(Core.SetSetting("widget.bgAlpha", 0.33)); T.eq(w.bgAlpha, 0.35)
  T.ok(Core.SetSetting("widget.bgAlpha", 7)); T.eq(w.bgAlpha, 1)
  T.ok(Core.SetSetting("widget.bgAlpha", -1)); T.eq(w.bgAlpha, 0)
  T.no(Core.SetSetting("widget.bgAlpha", "dark"))
  -- the old on/off background is not a setting any more
  T.no(Core.SetSetting("widget.background", true))
  T.eq(w.background, nil)
  -- graph history: 30 s, 1 min, 5 min
  T.ok(Core.SetSetting("graph.window", 300)); T.eq(ns.settings.graph.window, 300)
  T.eq(got[#got], { "graph.window", 300 })
  T.ok(Core.SetSetting("graph.window", 30))
  T.no(Core.SetSetting("graph.window", 45))
  T.no(Core.SetSetting("graph.window", "60"))
  T.eq(Core.GetSetting("graph.window"), 30)
  -- a missing parent table is rebuilt from the defaults
  ns.settings.graph = nil
  T.ok(Core.SetSetting("graph.window", 300))
  T.eq(ns.settings.graph, { window = 300 })
  -- new token ids are known without Tokens.lua (the foundation files only)
  for _, id in ipairs({ "kills", "eta_kills", "instance_session", "instance_total" }) do
    Core.SetSetting("widget.slots.3", "none")
    T.ok(Core.SetSetting("widget.slots.3", id), id)
  end
  T.eq(#Stub.errors, 0)
end)

T.test("RepairDB: invalid colour, outline, opacity and graph values give way to the defaults", function()
  _G.TruePlayedDB = {
    sparseSettings = true,
    settings = {
      widget = { textColor = "red", outline = "fat", shadow = "yes", bgAlpha = 3, qualityColors = 0 },
      graph = "x",
    },
  }
  local ns = Load()
  Stub.LoginSequence()
  local w = ns.settings.widget
  T.eq(w.textColor, false)
  T.eq(w.outline, "thin")
  T.eq(w.shadow, true)
  T.eq(w.bgAlpha, 1, "clamped")
  T.eq(w.qualityColors, true)
  T.eq(ns.settings.graph, { window = 60 })
  local function Colour(v)
    Stub.Reset()
    _G.TruePlayedDB = { sparseSettings = true, settings = { widget = { textColor = v }, graph = { window = 45 } } }
    local n2 = Load()
    Stub.LoginSequence()
    T.eq(n2.settings.graph.window, 60)
    return n2.settings.widget.textColor
  end
  T.eq(Colour({ 0.2, 0.4, 0.6 }), { 0.2, 0.4, 0.6 }, "a stored colour survives the type repair")
  T.eq(Colour({ 2, -1, 0.5 }), { 1, 0, 0.5 })
  T.eq(Colour({ r = 0.1, g = 0.2, b = 0.3 }), { 0.1, 0.2, 0.3 })
  T.eq(Colour({ 1, "x" }), false)
  T.eq(Colour({}), false)
  T.eq(Colour(false), false)
end)

T.test("settings are saved sparsely: the file keeps only what the user changed", function()
  local ns = Load()
  Stub.LoginSequence()
  local Core = ns.Core
  T.ok(Core.SetSetting("widget.width", 400))
  T.ok(Core.SetSetting("exclude.city", true))
  T.ok(Core.SetSetting("widget.slots.1", "played"))
  T.ok(Core.SetSetting("widget.bgAlpha", 0.6))
  T.ok(Core.SetSetting("widget.textColor", { 0.9, 0.8, 0.1 }))
  T.ok(Core.SetSetting("widget.outline", "thick"))
  T.ok(Core.SetSetting("graph.window", 300))
  T.ok(Core.SetSetting("firstRunDone", true))
  T.no(Core.SetSetting("widget.point", { "CENTER", "CENTER", 0, -220 }), "equal to the default")
  ns.settings.futureOption = { x = 1 }     -- written by a newer version: kept as is
  Stub.Logout()
  T.eq(Stub.saved.settings, {
    exclude = { city = true },
    widget = { width = 400, slots = { "played", "xph", "fps_latency" }, bgAlpha = 0.6,
               textColor = { 0.9, 0.8, 0.1 }, outline = "thick" },
    graph = { window = 300 },
    firstRunDone = true,
    futureOption = { x = 1 },
  })
  T.eq(Stub.saved.sparseSettings, true)
  T.eq(Stub.saved.settings.rateTau, nil, "an untouched value follows the defaults of the next version")
  -- the live table stays complete for the logout handlers that run after Core's
  T.eq(ns.settings.rateTau, 3600)
  T.eq(ns.settings.widget.height, 8)
  T.eq(ns.settings.exclude.afk, false)
  T.eq(ns.settings.widget.shadow, true)
  -- next session: completed from the defaults, the user's values kept
  ns = Stub.Restart({ files = FILES })
  local s = ns.settings
  T.eq(s.widget.width, 400)
  T.eq(s.widget.bgAlpha, 0.6, "a chosen value is kept")
  T.eq(s.widget.textColor, { 0.9, 0.8, 0.1 }, "a nested colour table is kept")
  T.eq(s.widget.outline, "thick")
  T.eq(s.widget.shadow, true)
  T.eq(s.graph, { window = 300 })
  T.eq(s.widget.slots, { "played", "xph", "fps_latency" })
  T.eq(s.widget.point, { "CENTER", "CENTER", 0, -220 })
  T.eq(s.exclude, { afk = false, inn = false, city = true })
  T.eq(s.rateTau, 3600)
  T.eq(s.futureOption, { x = 1 })
  T.eq(ns.GetMask(), 4)
  -- back to the defaults: nothing left in the file
  Core = ns.Core
  Core.SetSetting("widget.width", 360); Core.SetSetting("exclude.city", false)
  Core.SetSetting("widget.slots.1", "eta_kills"); Core.SetSetting("widget.bgAlpha", 0)
  Core.SetSetting("widget.textColor", false); Core.SetSetting("widget.outline", "thin")
  Core.SetSetting("graph.window", 60)
  Core.SetSetting("firstRunDone", false)
  ns.settings.futureOption = nil
  Stub.Logout()
  T.eq(Stub.saved.settings, {})
end)

T.test("a background chosen in 0.1.0-beta (sparse file) becomes the opacity it had", function()
  _G.TruePlayedDB = { schema = 1, sparseSettings = true, chars = {},
                      settings = { widget = { background = true, width = 400 } } }
  local ns = Load()
  Stub.LoginSequence()
  local w = ns.settings.widget
  T.eq(w.bgAlpha, ns.C.LEGACY_BG_ALPHA)
  T.eq(ns.C.LEGACY_BG_ALPHA, ns.C.COLORS.bg[4], "the alpha of the old dark background")
  T.eq(w.background, nil, "removed")
  T.eq(w.width, 400)
  Stub.Logout()
  T.eq(Stub.saved.settings, { widget = { width = 400, bgAlpha = 0.85 } })
  -- a background that was off is simply removed; an opacity already set wins
  Stub.Reset()
  _G.TruePlayedDB = { schema = 1, sparseSettings = true, chars = {},
                      settings = { widget = { background = false } } }
  ns = Load()
  Stub.LoginSequence()
  T.eq(ns.settings.widget.bgAlpha, 0)
  T.eq(ns.settings.widget.background, nil)
  Stub.Reset()
  _G.TruePlayedDB = { schema = 1, sparseSettings = true, chars = {},
                      settings = { widget = { background = true, bgAlpha = 0.3 } } }
  ns = Load()
  Stub.LoginSequence()
  T.eq(ns.settings.widget.bgAlpha, 0.3)
  -- read-only mode converts its in-memory copy only
  Stub.Reset()
  local ro = { schema = 99, chars = {}, settings = { widget = { background = true } } }
  _G.TruePlayedDB = ro
  ns = Load()
  Stub.LoginSequence()
  T.eq(ns.settings.widget.bgAlpha, 0.85)
  T.eq(ro.settings.widget.background, true, "the real table is untouched")
  T.eq(ro.settings.widget.bgAlpha, nil)
end)

-- Settings as saved in full by 0.1.0-test: background = true and slots eta / xp/h /
-- FPS were the defaults then.
local function LegacySettings()
  return {
    rateTau = 3600, debug = false, exclude = { inn = false, afk = false, city = false },
    hidePlayedMsg = false, firstRunDone = true, requestPlayedAtLogin = true,
    widget = { scale = 1, fontSize = 11, point = { "CENTER", "CENTER", 0, -220 }, style = "bar",
               shown = true, background = true, slots = { "eta", "xph", "fps_latency" }, fade = false,
               locked = false, combatHide = false, hideAtMax = false,
               maxSlots = { "session", "played", "fps_latency" }, height = 8, slot3Pos = "center",
               pctPos = "follow", width = 360 },
  }
end

T.test("a settings table saved in full by 0.1.0-test: the old defaults give way", function()
  local legacy = { schema = 1, lastVersion = "0.1.0-test", settings = LegacySettings(), chars = {} }
  legacy.settings.widget.width = 420
  legacy.settings.exclude.afk = true
  _G.TruePlayedDB = legacy
  local ns = Load()
  Stub.LoginSequence()
  T.eq(ns.settings.widget.bgAlpha, 0, "the old default was not a choice: no background")
  T.eq(ns.settings.widget.background, nil)
  T.eq(ns.settings.widget.slots, { "eta_kills", "xph", "fps_latency" }, "the new default slots")
  T.eq(ns.settings.widget.width, 420, "real choices kept")
  T.eq(ns.settings.exclude.afk, true)
  Stub.Logout()
  T.eq(Stub.saved.settings, { widget = { width = 420 }, exclude = { afk = true }, firstRunDone = true })
  -- marked sparse from now on: values chosen later are kept
  ns = Stub.Restart({ files = FILES })
  T.ok(ns.Core.SetSetting("widget.bgAlpha", 0.85))
  T.ok(ns.Core.SetSetting("widget.slots.1", "eta"))
  ns = Stub.Restart({ files = FILES })
  T.eq(ns.settings.widget.bgAlpha, 0.85)
  T.eq(ns.settings.widget.slots, { "eta", "xph", "fps_latency" }, "chosen again: kept")
  -- slots that differ from the old default were a choice: kept
  Stub.Reset()
  local chosen = { schema = 1, settings = LegacySettings(), chars = {} }
  chosen.settings.widget.slots = { "eta", "played", "fps" }
  _G.TruePlayedDB = chosen
  ns = Load()
  Stub.LoginSequence()
  T.eq(ns.settings.widget.slots, { "eta", "played", "fps" })
  -- a late-applied legacy table (CheckSwap) is converted the same way
  T.eq(#Stub.errors, 0, "no Lua error so far")
  Stub.Reset()
  ns = Load()
  Stub.LoginSequence()
  _G.TruePlayedDB = { schema = 1, settings = LegacySettings(), chars = {} }
  Stub.Advance(2)
  T.ok(ns.db == _G.TruePlayedDB)
  T.eq(ns.settings.widget.bgAlpha, 0)
  T.eq(ns.settings.widget.background, nil)
  T.eq(ns.settings.widget.slots[1], "eta_kills")
end)

-- The user's file before this version (0.1.0-test, saved in full): druid level 20,
-- exclusions on, bar at the top, width 370, font 14, height 15, background off.
local function UserRound2Settings()
  return {
    rateTau = 3600, debug = false, exclude = { inn = true, afk = true, city = true },
    firstRunDone = true, hidePlayedMsg = false, requestPlayedAtLogin = true,
    widget = { width = 370, fontSize = 14, point = { "TOP", "TOP", -3, -33 }, hideAtMax = false,
               scale = 1, slot3Pos = "center", slots = { "eta", "xph", "fps_latency" }, fade = false,
               height = 15, combatHide = false, style = "bar",
               maxSlots = { "session", "played", "fps_latency" }, locked = true, background = false,
               pctPos = "follow", shown = true },
  }
end

T.test("user's file: choices kept, background off stays off, new defaults filled", function()
  _G.TruePlayedDB = { schema = 1, lastVersion = "0.1.0-test", createdAt = 1790799275, cities = {},
                      xpMax = { [20] = 23200 }, settings = UserRound2Settings(), chars = {} }
  local ns = Load()
  Stub.LoginSequence()
  local w = ns.settings.widget
  T.eq(ns.GetMask(), 7, "AFK, inn and city excluded")
  T.eq(w.width, 370); T.eq(w.fontSize, 14); T.eq(w.height, 15)
  T.eq(w.point, { "TOP", "TOP", -3, -33 }); T.eq(w.locked, true)
  T.eq(w.bgAlpha, 0); T.eq(w.background, nil)
  T.eq(w.slots, { "eta_kills", "xph", "fps_latency" }, "time to level + mobs to kill")
  T.eq(w.textColor, false); T.eq(w.outline, "thin"); T.eq(w.shadow, true); T.eq(w.qualityColors, true)
  T.eq(ns.settings.graph, { window = 60 })
  Stub.Logout()
  T.eq(Stub.saved.sparseSettings, true)
  T.eq(Stub.saved.settings, {
    exclude = { inn = true, afk = true, city = true }, firstRunDone = true,
    widget = { width = 370, fontSize = 14, point = { "TOP", "TOP", -3, -33 }, height = 15, locked = true },
  })
end)

T.test("RepairChar validates the optional pre-install estimate (char.prior)", function()
  local ns = Load()
  local function R(prior)
    local c = { prior = prior }
    ns.Core.RepairChar(c)
    return c.prior
  end
  T.eq(R({ xph = 4452.25, at = 5 }), { xph = 4452.25, at = 5 })
  T.eq(R({ xph = 4452.25, at = "x" }), { xph = 4452.25 })
  T.eq(R({ xph = 0 }), nil)
  T.eq(R({ xph = -1 }), nil)
  T.eq(R({ xph = 0 / 0 }), nil)
  T.eq(R({ xph = math.huge }), nil)
  T.eq(R({ xph = 1e12 }), nil)
  T.eq(R({ xph = "4452" }), nil)
  T.eq(R({}), nil)
  T.eq(R("x"), nil)
  T.eq(R(nil), nil)
end)

T.test("RepairChar validates the last kill (char.lastKill)", function()
  local ns = Load()
  local function R(lk)
    local c = { lastKill = lk }
    ns.Core.RepairChar(c)
    return c.lastKill
  end
  T.eq(R({ xp = 312, level = 20, at = 1790800000 }), { xp = 312, level = 20, at = 1790800000 })
  T.eq(R({ xp = 311.6, level = 20 }), { xp = 312, level = 20 }, "rounded")
  T.eq(R({ xp = 312, level = "x", at = "y" }), { xp = 312 }, "bad optional fields dropped")
  T.eq(R({ xp = 312, level = 0 }), { xp = 312 })
  T.eq(R({ xp = 0, level = 20 }), nil, "no XP: not a kill")
  T.eq(R({ xp = -5 }), nil)
  T.eq(R({ xp = 0 / 0 }), nil)
  T.eq(R({ xp = math.huge }), nil)
  T.eq(R({ xp = ns.C.KILL_XP_MAX + 1 }), nil)
  T.eq(R({ xp = "312" }), nil)
  T.eq(R({}), nil)
  T.eq(R(true), nil)
  T.eq(R(nil), nil)
end)

T.test("the Classic XP table matches the stub world and RXPGuides' Forever values", function()
  local C = Load().C
  T.eq(#C.CLASSIC_XP, 59)
  for l = 1, 59 do T.eq(C.CLASSIC_XP[l], Stub.xpTable[l], "level " .. l) end
  T.eq(C.CLASSIC_XP[20], 23200, "UnitXPMax seen in game at level 20")
  T.eq(C.CLASSIC_XP[57], 195000); T.eq(C.CLASSIC_XP[58], 202300); T.eq(C.CLASSIC_XP[59], 209800)
end)

---------------------------------------------------------------------------
-- Round 3: bar colours (C4), round 3 record fields, layered max level
---------------------------------------------------------------------------

T.test("C4: XP and rested colours - defaults, validation, reset, repair, sparse save and reload", function()
  local ns = Load()
  local d = ns.C.DEFAULTS.widget
  T.eq(d.xpColor, false, "built-in purple by default")
  T.eq(d.restedColor, false, "built-in blue by default")
  Stub.LoginSequence()
  local Core, w = ns.Core, ns.settings.widget
  T.eq(w.xpColor, false); T.eq(w.restedColor, false)
  local got = {}
  ns.RegisterMessage("SETTINGS_CHANGED", "test", function(_, path, value) got[#got + 1] = { path, value } end)
  for _, path in ipairs({ "widget.xpColor", "widget.restedColor" }) do
    local leaf = path:match("%.(%w+)$")
    T.ok(Core.SetSetting(path, { 0.2, 0.9, 0.3 }), path)
    T.eq(w[leaf], { 0.2, 0.9, 0.3 })
    T.eq(got[#got][1], path)
    T.ok(got[#got][2] == w[leaf], "payload is the stored value")
    T.no(Core.SetSetting(path, { r = 0.2, g = 0.9, b = 0.3 }), "same colour")
    T.ok(Core.SetSetting(path, { r = 0.123456, g = 2, b = -1 }))
    T.eq(w[leaf], { 0.123, 1, 0 }, "clamped, 3 decimals")
    T.no(Core.SetSetting(path, { 1, "x", 0 }))
    T.no(Core.SetSetting(path, { 0 / 0, 0, 0 }))
    T.no(Core.SetSetting(path, "purple"))
    T.no(Core.SetSetting(path, true))
    T.eq(w[leaf], { 0.123, 1, 0 }, "unchanged by invalid values")
    T.ok(Core.SetSetting(path, false), "reset to the original colours")
    T.eq(Core.GetSetting(path), false)
  end
  -- sparse save: only a chosen colour reaches the file, and comes back after a reload
  T.ok(Core.SetSetting("widget.restedColor", { 0.1, 0.2, 0.9 }))
  Stub.Logout()
  T.eq(Stub.saved.settings.widget.restedColor, { 0.1, 0.2, 0.9 })
  T.eq(Stub.saved.settings.widget.xpColor, nil, "a default colour is not saved")
  ns = Stub.Restart({ crash = true, files = FILES })
  T.eq(ns.settings.widget.restedColor, { 0.1, 0.2, 0.9 })
  T.eq(ns.settings.widget.xpColor, false)
  -- repair: bad stored values give way to the defaults; good ones survive the type repair
  local function Stored(xp, rested)
    Stub.Reset()
    _G.TruePlayedDB = { sparseSettings = true, settings = { widget = { xpColor = xp, restedColor = rested } } }
    local n2 = Load()
    Stub.LoginSequence()
    return n2.settings.widget.xpColor, n2.settings.widget.restedColor
  end
  local x, r = Stored("red", { 2, -1, 0.5 })
  T.eq(x, false); T.eq(r, { 1, 0, 0.5 })
  x, r = Stored({ r = 0.5, g = 0.25, b = 1 }, {})
  T.eq(x, { 0.5, 0.25, 1 }); T.eq(r, false)
  x, r = Stored(true, { 1, "x" })
  T.eq(x, false); T.eq(r, false)
  T.eq(#Stub.errors, 0)
end)

T.test("RepairChar validates the round 3 fields (noXP, capLevel, stalled maps, prior v, base.lp)", function()
  local ns = Load()
  local function R(c)
    ns.Core.RepairChar(c)
    return c
  end
  -- noXP: counted seconds since the last XP gain
  T.eq(R({ noXP = 1234.5 }).noXP, 1234.5)
  T.eq(R({ noXP = 0 }).noXP, 0)
  for _, bad in ipairs({ -1, 0 / 0, math.huge, "5", {} }) do
    T.eq(R({ noXP = bad }).noXP, nil, "noXP " .. T.repr(bad))
  end
  -- capLevel: a level (integer >= 1)
  T.eq(R({ capLevel = 20 }).capLevel, 20)
  for _, bad in ipairs({ 0, -3, 20.5, 0 / 0, "20", true }) do
    T.eq(R({ capLevel = bad }).capLevel, nil, "capLevel " .. T.repr(bad))
  end
  -- stalled maps: tables of non-negative numbers by state key, never created
  local c = R({ life = { s = { w = 50 }, xs = { w = 40, W = -1, c = "x", [3] = 5, i = 0 / 0 } },
                levels = { [5] = { s = { w = 9 }, xs = { w = 9 } }, [6] = { s = {}, xs = "junk" },
                           [7] = { s = {} } } })
  T.eq(c.life.xs, { w = 40 })
  T.eq(c.levels[5].xs, { w = 9 })
  T.eq(c.levels[6].xs, nil)
  T.eq(c.levels[7].xs, nil, "not created")
  T.eq(R({ life = { s = {}, xs = 7 } }).life.xs, nil)
  T.eq(R({}).life.xs, nil)
  -- prior: v = 2 kept, anything else dropped (the estimate is kept and recomputed)
  T.eq(R({ prior = { xph = 5737.3, at = 5, v = 2 } }).prior, { xph = 5737.3, at = 5, v = 2 })
  T.eq(R({ prior = { xph = 5737.3, v = 1 } }).prior, { xph = 5737.3 })
  T.eq(R({ prior = { xph = 5737.3, v = "2" } }).prior, { xph = 5737.3 })
  -- base.lp: the level time at the install, within the install total
  T.eq(R({ base = { total = 1000, at = 1, level = 5, lp = 300 } }).base.lp, 300)
  for _, bad in ipairs({ -1, 1001, 0 / 0, "300" }) do
    T.eq(R({ base = { total = 1000, at = 1, level = 5, lp = bad } }).base.lp, nil, "lp " .. T.repr(bad))
  end
end)

T.test("Util.IsMaxLevel: layered checks as EllesmereUI, every read guarded, never a hard-coded 60", function()
  local P = Stub.player
  -- the Forever beta: every API says 60 (IsPlayerAtEffectiveMaxLevel answers nothing)
  local U = Load().Util
  P.level = 20
  T.no(U.IsMaxLevel(), "level 20 of 60")
  P.effMax = true
  T.ok(U.IsMaxLevel(), "IsPlayerAtEffectiveMaxLevel")
  P.effMax = false
  T.no(U.IsMaxLevel())
  P.effMax = Stub.SECRET
  T.no(U.IsMaxLevel(), "a secret answer decides nothing")
  P.effMax = nil
  P.effMaxLevel = 20
  T.ok(U.IsMaxLevel(), "IsLevelAtEffectiveMaxLevel(level)")
  P.effMaxLevel = nil
  P.expMaxLevel = 20
  T.ok(U.IsMaxLevel(), "GetMaxLevelForPlayerExpansion")
  P.expMaxLevel = 60
  P.maxLevel = 20
  T.ok(U.IsMaxLevel(), "then GetMaxPlayerLevel")
  P.maxLevel = 60
  T.no(U.IsMaxLevel())
  -- missing or failing APIs: skipped
  Stub.Reset()
  _G.IsPlayerAtEffectiveMaxLevel = nil
  _G.IsLevelAtEffectiveMaxLevel = function() error("API change") end
  _G.GetMaxLevelForPlayerExpansion = nil
  U = Load().Util
  P = Stub.player
  P.level, P.maxLevel = 30, 30
  T.ok(U.IsMaxLevel(), "GetMaxPlayerLevel alone")
  P.maxLevel = 60
  T.no(U.IsMaxLevel())
  P.xpDisabled = true
  T.ok(U.IsMaxLevel(), "XP disabled")
  T.eq(#Stub.errors, 0)
end)
