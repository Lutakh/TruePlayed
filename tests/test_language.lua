-- tests/test_language.lua - the "language" setting (design/NEXT-LOT.md B): the locale
-- tables, the adoption order (ADDON_LOADED, a late table at PLAYER_LOGIN, no
-- SavedVariables, read-only, where a new language is refused), the fallbacks for unknown
-- values and for keys a locale lacks, the sparse save, no English left in French mode
-- (and the reverse), the options (dropdown, note, reload button), /tpl lang and its help
-- line, the locale recipe (the listing from C.LANGUAGES, one CODE per locale file), and
-- the locale tables dropped after login.
local Stub, T = ...

local format, find, concat = string.format, string.find, table.concat

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Raw strings of one locale file loaded alone (the legacy locale tests' pattern).
local function LocaleTable(file, locale)
  local saved = Stub.locale
  Stub.locale = locale
  local ns = {}
  if locale ~= "enUS" then ns.L = {} end
  assert(loadfile(Stub.ROOT .. file))("TruePlayed", ns)
  Stub.locale = saved
  local out = {}
  for k, v in pairs(ns.L) do out[k] = v end
  return out
end

local function EN() return LocaleTable("Locales/enUS.lua", "enUS") end
local function FR() return LocaleTable("Locales/frFR.lua", "frFR") end

-- The files of the TOC, in order, without the ones named in `skip`.
local function TocFiles(skip)
  local files = {}
  local toc = assert(io.open(Stub.ROOT .. "TruePlayed_Camelot.toc", "r"))
  for raw in toc:lines() do
    local line = raw:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      line = line:gsub("\\", "/")
      if not (skip and skip[line]) then files[#files + 1] = line end
    end
  end
  toc:close()
  return files
end

-- Every raw key of L holds the reference string, and L has no other raw key.
local function SameStrings(L, ref, msg)
  local n = 0
  for k, v in pairs(ref) do
    n = n + 1
    if rawget(L, k) ~= v then T.eq(rawget(L, k), v, msg .. ": " .. tostring(k)) end
  end
  for k in pairs(L) do
    if ref[k] == nil then T.ok(false, msg .. ": unexpected key " .. tostring(k)) end
  end
  T.ok(n > 300, msg .. ": reference table of " .. n .. " keys")
end

-- opts.locale (client, default enUS), opts.db (TruePlayedDB before the files load),
-- opts.ui (Stub.InstallUI options), opts.theme (Stub.theme; false = the shipped
-- default), opts.files (Stub.LoadAddon files).
local function Start(opts)
  opts = opts or {}
  if opts.theme == false then
    Stub.theme = nil
  elseif opts.theme then
    Stub.theme = opts.theme
  end
  Stub.InstallUI(opts.ui)
  Stub.locale = opts.locale or "enUS"
  if opts.db then rawset(_G, "TruePlayedDB", opts.db) end
  local ns = Stub.LoadAddon(opts.files and { files = opts.files } or nil)
  Stub.LoginSequence({ settle = 3 })
  return ns
end

local function Controls()
  return rawget(Stub.ui.categories[1].frame, "controls")
end

local function Printed(text, from)
  local lines = Stub.printed
  for i = from or 1, #lines do
    if find(lines[i], text, 1, true) then return true end
  end
  return false
end

local function TopY(widget)
  local _, _, _, _, y = widget:GetPoint(1)
  return y
end

local function FindRegion(text)
  local regions = rawget(Stub, "regions")
  for i = 1, #regions do
    local o = regions[i]
    if type(o) == "table" and rawget(o, "_text") == text then return o end
  end
  return nil
end

---------------------------------------------------------------------------
-- Locale tables
---------------------------------------------------------------------------

T.test("language: the locale files register their tables; ns.L is the client's at file load", function()
  local en, fr = EN(), FR()
  -- enUS client, files only (no event): English, both tables registered
  Stub.locale = "enUS"
  local ns = Stub.LoadAddon({ files = { "Locales/enUS.lua", "Locales/frFR.lua" } })
  SameStrings(ns.L, en, "enUS client at file load")
  T.eq(ns.L.SOME_MISSING_KEY, "SOME_MISSING_KEY", "fallback kept")
  T.eq(type(ns.LOCALES), "table")
  T.eq(ns.LOCALES.enUS, en, "English copy")
  T.eq(ns.LOCALES.frFR, fr, "French table")
  T.ok(ns.LOCALES.enUS ~= ns.L, "the English copy is not L")
  -- frFR client: French at file load, the English copy kept for a switch
  Stub.locale = "frFR"
  ns = Stub.LoadAddon({ files = { "Locales/enUS.lua", "Locales/frFR.lua" } })
  SameStrings(ns.L, fr, "frFR client at file load")
  T.eq(ns.LOCALES.enUS, en, "English copy on a French client")
  -- frFR.lua alone: fills ns.L only on a French client, registers its table anyway
  Stub.locale = "enUS"
  local alone = { L = {} }
  assert(loadfile(Stub.ROOT .. "Locales/frFR.lua"))("TruePlayed", alone)
  T.eq(alone.L, {}, "ns.L untouched on an enUS client")
  T.eq(alone.LOCALES.frFR, fr, "registered")
  -- every value is a string, the same keys in both tables (the switch writes every key)
  for k, v in pairs(en) do
    T.eq(type(v), "string", k)
    T.eq(type(fr[k]), "string", "frFR " .. k)
  end
  for k in pairs(fr) do T.ok(en[k] ~= nil, "frFR key unknown in enUS: " .. k) end
  -- the option's own strings
  T.eq(en.LANG_AUTO, "Auto")
  T.eq(en.LANG_ENUS, "English")
  T.eq(en.LANG_FRFR, "Fran\195\167ais")
  for _, k in ipairs({ "LANG_AUTO", "LANG_ENUS", "LANG_FRFR" }) do
    T.eq(fr[k], en[k], k .. " is written in its own language in both files")
  end
  T.eq(en.OPT_LANGUAGE, "Language (Langue)")
  T.eq(fr.OPT_LANGUAGE, "Langue (Language)")
end)

---------------------------------------------------------------------------
-- Adoption order
---------------------------------------------------------------------------

T.test("language: ADDON_LOADED applies the stored language, a late table at PLAYER_LOGIN wins", function()
  local en, fr = EN(), FR()
  -- frFR at ADDON_LOADED, then a late enUS table (WTFix) on an enUS client
  local first = { schema = 1, settings = { language = "frFR" } }
  rawset(_G, "TruePlayedDB", first)
  Stub.locale = "enUS"
  local ns = Stub.LoadAddon()
  local L = ns.L
  local mt = getmetatable(L)
  SameStrings(L, en, "before ADDON_LOADED")
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  T.ok(ns.db == first)
  T.eq(ns.settings, nil, "settings not adopted yet")
  SameStrings(L, fr, "frFR at ADDON_LOADED")
  T.ok(ns.LOCALES ~= nil, "the tables are kept until PLAYER_LOGIN")
  local late = { schema = 1, settings = { language = "enUS" } }
  rawset(_G, "TruePlayedDB", late)
  Stub.Fire("PLAYER_LOGIN")
  T.ok(ns.db == late, "the late table wins")
  T.eq(ns.Core.GetSetting("language"), "enUS")
  SameStrings(L, en, "enUS from the late table")
  T.ok(ns.L == L and getmetatable(L) == mt, "the same table, the same fallback")
  T.eq(L.SOME_MISSING_KEY, "SOME_MISSING_KEY")
  T.eq(ns.LOCALES, nil, "dropped")
  T.eq(first.settings.language, "frFR", "the first table is not touched")
  Stub.Fire("PLAYER_ENTERING_WORLD", true, false)
  Stub.Advance(3)

  -- the reverse: enUS at ADDON_LOADED, then a late frFR table
  Stub.Reset()
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { language = "enUS" } })
  ns = Stub.LoadAddon()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  SameStrings(ns.L, en, "enUS at ADDON_LOADED")
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { language = "frFR" } })
  Stub.Fire("PLAYER_LOGIN")
  SameStrings(ns.L, fr, "frFR from the late table")
  T.eq(ns.Core.GetSetting("language"), "frFR")
  T.eq(ns.LOCALES, nil)

  -- frFR client: English at ADDON_LOADED, then a late table without the setting (auto)
  Stub.Reset()
  Stub.locale = "frFR"
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { language = "enUS" } })
  ns = Stub.LoadAddon()
  SameStrings(ns.L, fr, "frFR client before ADDON_LOADED")
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  SameStrings(ns.L, en, "enUS on a frFR client at ADDON_LOADED")
  rawset(_G, "TruePlayedDB", { schema = 1, settings = {} })
  Stub.Fire("PLAYER_LOGIN")
  SameStrings(ns.L, fr, "auto on a frFR client: back to French")
  T.eq(ns.Core.GetSetting("language"), "auto")
  T.eq(ns.LOCALES, nil)
end)

T.test("language: a table only at ADDON_LOADED, none at all, or one only at PLAYER_LOGIN", function()
  local en, fr = EN(), FR()
  local db = { schema = 1, settings = { language = "frFR" } }
  local ns = Start({ db = db })
  T.ok(ns.db == db)
  SameStrings(ns.L, fr, "the ADDON_LOADED table")
  T.eq(ns.LOCALES, nil)

  -- no SavedVariables at all: auto, the client's language
  Stub.Reset()
  ns = Start()
  SameStrings(ns.L, en, "no SavedVariables, enUS client")
  T.eq(ns.settings.language, "auto")
  T.eq(ns.LOCALES, nil)
  Stub.Logout()
  T.eq(Stub.saved.settings.language, nil, "auto is not written")
  Stub.Reset()
  ns = Start({ locale = "frFR" })
  SameStrings(ns.L, fr, "no SavedVariables, frFR client")
  T.eq(ns.LOCALES, nil)

  -- nothing at ADDON_LOADED, a table at PLAYER_LOGIN
  Stub.Reset()
  ns = Stub.LoadAddon()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  T.eq(ns.db, nil)
  SameStrings(ns.L, en, "nothing adopted yet")
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { language = "frFR" } })
  Stub.Fire("PLAYER_LOGIN")
  SameStrings(ns.L, fr, "the PLAYER_LOGIN table")
  T.eq(ns.LOCALES, nil)
end)

T.test("language: read-only mode (newer schema) reads the language and writes nothing", function()
  local en, fr = EN(), FR()
  local sv = { schema = 99, settings = { language = "frFR", widget = { width = 300 } }, chars = {} }
  local snapshot = Stub.DeepCopy(sv)
  local ns = Start({ db = sv })
  T.ok(ns.readOnly)
  SameStrings(ns.L, fr, "read-only frFR")
  T.eq(ns.Core.GetSetting("language"), "frFR")
  T.eq(ns.LOCALES, nil)
  T.ok(Printed(fr.SCHEMA_NEWER), "the read-only warning in French")
  rawset(_G, "TruePlayedDB", sv)
  Stub.Fire("PLAYER_LOGOUT")
  T.eq(sv, snapshot, "nothing written")

  -- an invalid value in a read-only table: auto, and the table keeps it
  Stub.Reset()
  sv = { schema = 99, settings = { language = "xx" }, chars = {} }
  snapshot = Stub.DeepCopy(sv)
  ns = Start({ db = sv })
  T.ok(ns.readOnly)
  SameStrings(ns.L, en, "invalid value: auto (enUS client)")
  T.eq(ns.Core.GetSetting("language"), "auto", "repaired in memory")
  T.eq(sv, snapshot, "nothing written")
  -- the same on a frFR client: auto = French there (not the English fallback)
  Stub.Reset()
  sv = { schema = 99, settings = { language = "xx" }, chars = {} }
  snapshot = Stub.DeepCopy(sv)
  ns = Start({ locale = "frFR", db = sv })
  T.ok(ns.readOnly)
  SameStrings(ns.L, fr, "invalid value: auto (frFR client)")
  T.eq(ns.Core.GetSetting("language"), "auto", "repaired in memory (frFR client)")
  rawset(_G, "TruePlayedDB", sv)
  Stub.Fire("PLAYER_LOGOUT")
  T.eq(sv, snapshot, "nothing written (frFR client)")

  -- a read-only table arriving at PLAYER_LOGIN
  Stub.Reset()
  ns = Stub.LoadAddon()
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  sv = { schema = 99, settings = { language = "frFR" }, chars = {} }
  snapshot = Stub.DeepCopy(sv)
  rawset(_G, "TruePlayedDB", sv)
  Stub.Fire("PLAYER_LOGIN")
  T.ok(ns.readOnly and ns.db == sv)
  SameStrings(ns.L, fr, "late read-only table")
  T.eq(sv, snapshot, "nothing written")
end)

T.test("language: read-only mode refuses a new language (/tpl lang, the dropdown, the cycle button)", function()
  local sv = { schema = 99, settings = {}, chars = {} }
  local snapshot = Stub.DeepCopy(sv)
  local ns = Start({ db = sv, ui = { modern = true } })
  local L, ui = ns.L, Stub.ui
  T.ok(ns.readOnly)
  -- /tpl lang <value>: the read-only message, nothing else, the setting unchanged
  for _, cmd in ipairs({ "lang fr", "lang en", "lang auto", "lang FRFR", "lang enus" }) do
    local n = #Stub.printed
    Stub.RunSlash(cmd)
    T.eq(#Stub.printed, n + 1, cmd .. ": one line")
    T.ok(Printed(L.READONLY_ACTION, n + 1), cmd .. ": refused")
    T.eq(ns.Core.GetSetting("language"), "auto", cmd .. ": unchanged")
  end
  -- an unknown value is still unknown; the listing still works
  local n = #Stub.printed
  Stub.RunSlash("lang xx")
  T.ok(Printed(format(L.UNKNOWN_CMD_FMT, "lang xx"), n + 1), "unknown value")
  n = #Stub.printed
  Stub.RunSlash("lang")
  T.ok(Printed(format(L.LANG_LIST_FMT, "Auto", "auto, en, fr"), n + 1), "the listing")
  -- the dropdown: the same message, it keeps showing the setting
  ns.Options.Open()
  local controls = Controls()
  local rec = controls.language
  n = #Stub.printed
  ui.ClickMenuItem(ui.FindMenuItem(rawget(rec.widget, "_root"), "Fran\195\167ais"))
  T.eq(ns.Core.GetSetting("language"), "auto", "dropdown: unchanged")
  T.ok(Printed(L.READONLY_ACTION, n + 1), "dropdown: refused")
  local root = rawget(rec.widget, "_root")
  T.ok(ui.IsChecked(ui.FindMenuItem(root, "Auto")), "Auto still checked")
  T.no(ui.IsChecked(ui.FindMenuItem(root, "Fran\195\167ais")))
  -- only the language: the other dropdowns still change their setting for the session
  ui.ClickMenuItem(ui.FindMenuItem(rawget(controls["widget.style"].widget, "_root"), L.STYLE_BOX))
  T.eq(ns.Core.GetSetting("widget.style"), "box", "another dropdown still applies")
  -- Reload UI stays a plain reload (it writes nothing and promises nothing)
  Stub.RunScript(controls["language.reload"].widget, "OnClick", "LeftButton")
  T.eq(ui.reloads, 1)
  rawset(_G, "TruePlayedDB", sv)
  Stub.Fire("PLAYER_LOGOUT")
  T.eq(sv, snapshot, "nothing written")

  -- the fallback cycle button (no modern dropdown): refused both ways, still "Auto"
  Stub.Reset()
  ns = Start({ db = { schema = 99, settings = {}, chars = {} }, ui = { modern = false } })
  L = ns.L
  ns.Options.Open()
  local b = Controls().language.widget
  for _, button in ipairs({ "LeftButton", "RightButton" }) do
    n = #Stub.printed
    b:GetScript("OnClick")(b, button)
    T.eq(ns.Core.GetSetting("language"), "auto", button .. ": unchanged")
    T.ok(Printed(L.READONLY_ACTION, n + 1), button .. ": refused")
  end
  T.ok(FindRegion("Auto") ~= nil, "the button shows the setting")
  T.eq(FindRegion("English"), nil)
  T.eq(FindRegion("Fran\195\167ais"), nil)
end)

---------------------------------------------------------------------------
-- Unknown values and fallbacks
---------------------------------------------------------------------------

T.test("language: SetSetting refuses unknown values; a stored unknown value becomes auto", function()
  local en, fr = EN(), FR()
  local ns = Start()
  local Core = ns.Core
  T.eq(ns.C.LANGUAGES, { "auto", "enUS", "frFR" })
  T.eq(ns.C.DEFAULTS.language, "auto")
  for _, bad in ipairs({ "deDE", "fr", "FRFR", "en", "", 42, true, false, { "frFR" } }) do
    T.no(Core.SetSetting("language", bad), "refused: " .. T.repr(bad))
    T.eq(Core.GetSetting("language"), "auto", "unchanged after " .. T.repr(bad))
  end
  T.ok(Core.SetSetting("language", "frFR"))
  T.no(Core.SetSetting("language", "frFR"), "same value")
  T.eq(Core.GetSetting("language"), "frFR")
  SameStrings(ns.L, en, "no live switch: the language applies at the next UI load")
  T.ok(Core.SetSetting("language", "enUS"))
  T.ok(Core.SetSetting("language", "auto"))

  -- stored unknown values: repaired to auto, then not written (sparse)
  for _, stored in ipairs({ "xx", "deDE", 42, true, { "frFR" } }) do
    for _, client in ipairs({ "enUS", "frFR" }) do
      Stub.Reset()
      ns = Start({ locale = client, db = { schema = 1, settings = { language = stored } } })
      local what = T.repr(stored) .. " on a " .. client .. " client"
      T.eq(ns.Core.GetSetting("language"), "auto", what)
      SameStrings(ns.L, client == "frFR" and fr or en, what)
      Stub.Logout()
      T.eq(Stub.saved.settings.language, nil, what .. ": not saved")
    end
  end
end)

T.test("language: a language without a locale table falls back to English", function()
  local en = EN()
  -- auto on a client whose language has no table
  local ns = Start({ locale = "deDE" })
  SameStrings(ns.L, en, "auto on a deDE client")
  T.eq(ns.LOCALES, nil)
  -- frFR chosen on a build without Locales/frFR.lua
  local noFr = TocFiles({ ["Locales/frFR.lua"] = true })
  T.ok(#noFr > 10, "the TOC files")
  for _, client in ipairs({ "enUS", "frFR" }) do
    Stub.Reset()
    ns = Start({ locale = client, files = noFr, db = { schema = 1, settings = { language = "frFR" } } })
    T.eq(ns.Core.GetSetting("language"), "frFR", "a valid value of this version is kept")
    SameStrings(ns.L, en, "frFR without its file, " .. client .. " client")
    T.eq(ns.LOCALES, nil)
    T.ok(ns.ready and ns.Bar.frame ~= nil, "the UI is built")
    T.eq(#Stub.errors, 0, "no error")
  end
  -- auto on a frFR client without the file
  Stub.Reset()
  ns = Start({ locale = "frFR", files = noFr })
  SameStrings(ns.L, en, "auto, frFR client, no frFR file")
  T.eq(#Stub.errors, 0)
end)

-- ApplyLanguage writes English first: a key the chosen locale lacks is English, not the
-- client's language that ns.L held since file load (a partial locale of a later version).
T.test("language: a key the chosen locale lacks is English, not the client's language", function()
  local en, fr = EN(), FR()
  Stub.InstallUI()
  Stub.locale = "frFR"
  local ns = Stub.LoadAddon()
  SameStrings(ns.L, fr, "French at file load")
  ns.LOCALES.frFR = { ON = "x" }
  Stub.LoginSequence({ settle = 3 })
  T.eq(ns.L.ON, "x", "the locale's own key")
  local want = {}
  for k, v in pairs(en) do want[k] = v end
  want.ON = "x"
  SameStrings(ns.L, want, "every other key in English")
  T.eq(ns.L.SOME_MISSING_KEY, "SOME_MISSING_KEY", "the fallback kept")
  T.eq(#Stub.errors, 0)
end)

---------------------------------------------------------------------------
-- Sparse save
---------------------------------------------------------------------------

T.test("language: saved sparsely and kept across reloads", function()
  local en, fr = EN(), FR()
  local ns = Start()
  T.eq(ns.Core.GetSetting("language"), "auto")
  Stub.Logout()
  T.eq(Stub.saved.settings.language, nil, "auto is not written")
  T.ok(ns.Core.SetSetting("language", "frFR"))
  SameStrings(ns.L, en, "unchanged until the reload")
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.eq(Stub.saved.settings.language, "frFR", "frFR written")
  T.eq(ns.Core.GetSetting("language"), "frFR")
  SameStrings(ns.L, fr, "French after the reload on an enUS client")
  T.eq(ns.LOCALES, nil)
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.eq(Stub.saved.settings.language, "frFR", "kept by the next save")
  SameStrings(ns.L, fr, "still French")
  T.ok(ns.Core.SetSetting("language", "auto"))
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.eq(Stub.saved.settings.language, nil, "back to auto: removed from the file")
  SameStrings(ns.L, en, "English again")
  -- enUS chosen, then the game client switched to French: the saved choice applies
  ns.Core.SetSetting("language", "enUS")
  Stub.locale = "frFR"
  ns = Stub.Restart({ settle = 3 })
  T.eq(Stub.saved.settings.language, "enUS")
  SameStrings(ns.L, en, "enUS on a frFR client")
end)

---------------------------------------------------------------------------
-- No English left in French mode, and the reverse
---------------------------------------------------------------------------

-- Every text a user sees, in a fixed order: the bar, the tooltip (short and Shift, the
-- private frame or GameTooltip, and Tooltip.Fill), the graph, the statistics window (3
-- tabs and the account view), the options panel (every FontString and every dropdown
-- label), the context menu, the chat (login, /tpl help, theme, lang, played, lock,
-- unlock, an unknown command, sync twice and its /played answer), the erase popup (its
-- text and its buttons), the broker, every token (Tokens.Render, with its short form),
-- Tokens.PercentText, and the graph without data. On a frFR client the game's YES / NO
-- are French, as in the game (the stub's are English).
local function Snapshot(opts)
  Stub.Reset()
  local p = Stub.player
  if opts.max then
    p.level, p.xp, p.max, p.rest = 60, 0, 0, 0
  else
    p.level, p.xp, p.rest = 20, 10115, 3000
    p.max = Stub.xpTable[20]
  end
  local db
  if opts.language then db = { schema = 1, settings = { language = opts.language } } end
  if opts.client == "frFR" then
    rawset(_G, "YES", "Oui")
    rawset(_G, "NO", "Non")
  end
  local ns = Start({ locale = opts.client, db = db, theme = opts.theme, ui = { modern = true } })
  local out = {}
  local function add(tag, s)
    if type(s) == "string" and s ~= "" then out[#out + 1] = tag .. ": " .. s end
  end
  local function regions(tag)
    local list = rawget(Stub, "regions")
    for i = 1, #list do
      local o = list[i]
      if type(o) == "table" then add(tag .. " #" .. i, rawget(o, "_text")) end
    end
  end
  local function lines(tag, tt)
    local ls = rawget(tt, "_lines") or {}
    for i = 1, #ls do
      add(tag .. " " .. i .. "L", ls[i][1])
      add(tag .. " " .. i .. "R", ls[i][2])
    end
  end
  local function menu(tag, node)
    if type(node) ~= "table" then return end
    add(tag, node.text)
    for i = 1, #(node.children or {}) do menu(tag .. "." .. i, node.children[i]) end
  end

  if not opts.max then
    for _ = 1, 6 do
      Stub.Advance(30)
      Stub.Kill(171)
    end
  end
  Stub.Advance(2)
  local bar = ns.Bar.frame
  regions("bar")
  ns.Tooltip.ShowFor(bar)
  Stub.Advance(1)
  regions("tooltip")
  lines("GameTooltip", GameTooltip)
  Stub.SetShift(true)
  Stub.Advance(1)
  regions("tooltip shift")
  lines("GameTooltip shift", GameTooltip)
  Stub.SetShift(false)
  ns.Tooltip.Hide(bar)
  lines("Fill", (function() local tt = Stub.NewTooltip(); ns.Tooltip.Fill(tt, false); return tt end)())
  lines("Fill shift", (function() local tt = Stub.NewTooltip(); ns.Tooltip.Fill(tt, true); return tt end)())
  ns.Graph.ShowFor(bar)
  Stub.Advance(2)
  regions("graph")
  ns.Graph.Hide()
  ns.Window.Show("levels")
  Stub.Advance(1)
  regions("window levels")
  for _, tab in ipairs({ "zones", "sessions" }) do
    ns.Window.Toggle(tab)
    Stub.Advance(1)
    regions("window " .. tab)
  end
  ns.Window.SetView("account")
  Stub.Advance(1)
  regions("window account")
  ns.Window.Hide()
  ns.Options.Open()
  Stub.Advance(1)
  regions("options")
  local controls = Controls()
  local recs = {}
  for _, rec in pairs(controls) do recs[#recs + 1] = rec end
  table.sort(recs, function(a, b) return a.index < b.index end)
  for i = 1, #recs do
    local root = rawget(recs[i].widget, "_root")
    if root then menu("dropdown " .. recs[i].path, root) end
  end
  Stub.ui.CloseSettings()
  ns.Options.ShowContextMenu(bar)
  menu("context menu", Stub.ui.lastMenu)
  -- "lang auto" first: the listing names the setting, the same in both runs from there
  -- "sync" twice: requested, then throttled; the /played answer 0.1 s later: synced
  for _, cmd in ipairs({ "help", "theme", "lang auto", "lang", "played", "lock", "unlock", "nonsense",
                         "reset char", "sync", "sync" }) do
    Stub.RunSlash(cmd)
  end
  Stub.Advance(1)
  for i = 1, #Stub.printed do add("chat " .. i, Stub.printed[i]) end
  local dialogs = rawget(_G, "StaticPopupDialogs")
  for i = 1, #Stub.popups do
    local popup = Stub.popups[i]
    local d = dialogs[popup.which]
    add("popup " .. i, popup.text_arg1)
    add("popup " .. i .. " buttons", tostring(d.button1) .. " / " .. tostring(d.button2))
  end
  local obj = Stub.ui.ldbObjects.TruePlayed
  if obj then
    add("broker label", obj.label)
    add("broker text", obj.text)
    local tt = Stub.NewTooltip()
    obj.OnTooltipShow(tt)
    lines("broker tooltip", tt)
  end
  local Tokens = ns.Tokens
  for _, id in ipairs(Tokens.ORDER) do
    local text, _, _, alt = Tokens.Render(id)
    add("token " .. id, text)
    add("token " .. id .. " short", alt)
    add("token label " .. id, Tokens.Label(id))
  end
  for _, t in ipairs({ 0, 5, 423, 999, 1000 }) do add("percent " .. t, Tokens.PercentText(t)) end
  -- last, the graph without a sample in its window: the bar samples from login on, so
  -- it is hidden (nothing sampled) for longer than the window and the latency hold first
  ns.Core.SetSetting("widget.shown", false)
  Stub.Advance(ns.Core.GetSetting("graph.window") + 30)
  ns.Graph.ShowFor(bar)
  local tp = ns.Graph.frame.tp
  add("graph empty readout", tp.readout:GetText())
  add("graph empty fps", tp.fpsStats:GetText())
  add("graph empty latency", tp.latStats:GetText())
  ns.Graph.Hide()
  T.eq(Stub.errors, {}, "no error in the " .. opts.client .. " / " .. tostring(opts.language) .. " run")
  return out
end

-- The two runs show the same texts; the comparison is not empty and the runs differ
-- from the other language.
local function SameTexts(got, want, other, msg)
  T.ok(#want > 250, msg .. ": " .. #want .. " texts")
  T.eq(#got, #want, msg .. ": number of texts")
  for i = 1, math.max(#got, #want) do
    if got[i] ~= want[i] then
      T.eq(got[i], want[i], msg .. ": text " .. i)
    end
  end
  local differ = 0
  for i = 1, math.min(#want, #other) do
    if want[i] ~= other[i] then differ = differ + 1 end
  end
  T.ok(differ > 100, msg .. ": " .. differ .. " texts differ from the other language")
end

T.test("language: no English left in French mode (enUS client, language frFR = a frFR client)", function()
  for _, theme in ipairs({ false, "actuel" }) do
    local tag = theme and theme or "shipped default theme"
    local native = Snapshot({ client = "frFR", theme = theme })
    local chosen = Snapshot({ client = "enUS", language = "frFR", theme = theme })
    local english = Snapshot({ client = "enUS", theme = theme })
    SameTexts(chosen, native, english, "frFR mode, " .. tag)
    local all = concat(chosen, "\n")
    for _, s in ipairs({ "monstres", "Niveau", "Th\195\168me : ", "Langue : Auto", "Commandes :",
                         "Langue (Language)", "Recharger l'interface", "Collecte des mesures...",
                         "Demande du /played au serveur...", "Patientez quelques secondes",
                         "/played synchronis\195\169.", "buttons: Oui / Non" }) do
      T.ok(find(all, s, 1, true) ~= nil, tag .. ": shows " .. s)
    end
    for _, s in ipairs({ " mobs", "Level ", "XP to go", "Theme: ", "Commands:", "Reload UI",
                         "Collecting samples", "Asking the server", "Please wait", "/played synced",
                         "Yes / No" }) do
      T.ok(find(all, s, 1, true) == nil, tag .. ": no English " .. s)
    end
  end
  -- at max level (the XP tokens' max-level text)
  local native = Snapshot({ client = "frFR", max = true })
  local chosen = Snapshot({ client = "enUS", language = "frFR", max = true })
  local english = Snapshot({ client = "enUS", max = true })
  SameTexts(chosen, native, english, "frFR mode at max level")
end)

T.test("language: English mode on a frFR client = an enUS client", function()
  for _, theme in ipairs({ false, "actuel" }) do
    local tag = theme and theme or "shipped default theme"
    local native = Snapshot({ client = "enUS", theme = theme })
    local chosen = Snapshot({ client = "frFR", language = "enUS", theme = theme })
    local french = Snapshot({ client = "frFR", theme = theme })
    SameTexts(chosen, native, french, "enUS mode, " .. tag)
    local all = concat(chosen, "\n")
    for _, s in ipairs({ "monstres", "Niveau ", "XP restants", "Th\195\168me", "Commandes", "Recharger",
                         "Collecte", "Demande du", "Patientez", "synchronis", "Oui / Non" }) do
      T.ok(find(all, s, 1, true) == nil, tag .. ": no French " .. s)
    end
    for _, s in ipairs({ "Collecting samples...", "Asking the server for /played...", "Please wait a few seconds",
                         "/played synced.", "buttons: Yes / No" }) do
      T.ok(find(all, s, 1, true) ~= nil, tag .. ": shows " .. s)
    end
  end
end)

-- L.SEP is the same in both languages: a changed French separator shows that the bar
-- and the tokens read it after the language is applied (not at file load).
T.test("language: the separator is read after the language is applied", function()
  local p = Stub.player
  p.level, p.xp, p.rest = 20, 10115, 3000
  p.max = Stub.xpTable[20]
  Stub.InstallUI()
  rawset(_G, "TruePlayedDB", { schema = 1, settings = { language = "frFR" } })
  local ns = Stub.LoadAddon()
  T.eq(ns.L.SEP, " \194\183 ")
  ns.LOCALES.frFR.SEP = " / "
  Stub.LoginSequence({ settle = 3 })
  for _ = 1, 3 do
    Stub.Advance(30)
    Stub.Kill(171)
  end
  Stub.Advance(2)
  local slash, dot = FindRegion("/"), FindRegion("\194\183")
  T.ok(slash ~= nil and slash:IsShown(), "the bar's separator is the applied one")
  T.eq(dot, nil, "not the file-load one")
  local text = ns.Tokens.Render("eta_kills")
  T.ok(find(text, " / ", 1, true) ~= nil, "eta_kills joins with the applied separator: " .. text)
end)

T.test("language: French mode allocates nothing in steady ticks", function()
  local function Measure(client, language)
    Stub.Reset()
    local p = Stub.player
    p.level, p.xp, p.rest = 20, 10115, 3000
    p.max = Stub.xpTable[20]
    local db = language and { schema = 1, settings = { language = language } } or nil
    local ns = Start({ locale = client, db = db, theme = false })
    Stub.Advance(300)
    local kb = T.alloc(function() Stub.Advance(1) end, 600)
    T.eq(Stub.onUpdateCount, 0)
    return kb, ns
  end
  local kb, ns = Measure("enUS", "frFR")
  T.eq(ns.L.ON, "activ\195\169", "French applied")
  T.ok(kb <= 2, format("enUS client, frFR: %.2f KB over 600 ticks", kb))
  local en = Measure("enUS")
  T.ok(kb <= en + 0.5, format("no more than in English: %.2f vs %.2f KB", kb, en))
  kb = Measure("frFR", "enUS")
  T.ok(kb <= 2, format("frFR client, enUS: %.2f KB over 600 ticks", kb))
end)

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------

T.test("options: the language dropdown, its note and the reload button (modern controls)", function()
  local ns = Start({ ui = { modern = true } })
  local L, ui = ns.L, Stub.ui
  ns.Options.Open()
  local controls = Controls()
  local rec = controls.language
  T.ok(rec ~= nil and rec.kind == "dropdown", "language dropdown")
  T.eq(rec.label:GetText(), "Language (Langue)")
  -- in Display, after "Hide at max level"; the theme constraints hold
  T.eq(rec.index, controls["widget.hideAtMax"].index + 1, "right after Hide at max level")
  T.eq(controls.theme.index, controls["exclude.city"].index + 1, "theme still first in Display")
  T.eq(controls["widget.shown"].index, controls.theme.index + 1)
  T.ok(rec.index < controls["widget.textColor"].index, "before the Texts section")
  -- one radio per C.LANGUAGES value, each in its own language
  local root = rawget(rec.widget, "_root")
  local values, labels = {}, {}
  for i = 1, #root.children do
    local item = root.children[i]
    T.eq(item.kind, "radio")
    values[i], labels[i] = item.data.value, item.text
  end
  T.eq(values, { "auto", "enUS", "frFR" })
  T.eq(labels, { "Auto", "English", "Fran\195\167ais" })
  T.ok(ui.IsChecked(ui.FindMenuItem(root, "Auto")), "auto checked")
  T.no(ui.IsChecked(ui.FindMenuItem(root, "English")))
  -- the note, between the dropdown and the reload button
  local note = FindRegion(L.OPT_LANGUAGE_NOTE)
  T.ok(note ~= nil, "note shown")
  T.ok(find(L.OPT_LANGUAGE_NOTE, "reload", 1, true) ~= nil and find(L.OPT_LANGUAGE_NOTE, "zones", 1, true) ~= nil,
    "the note names the reload and the game's names")
  local reload = controls["language.reload"]
  T.ok(reload ~= nil and reload.kind == "button", "reload button registered under its own path")
  T.eq(reload.index, rec.index + 1)
  T.ok(FindRegion(L.OPT_RELOAD) ~= nil, "button text")
  local yDrop, yNote, yButton = TopY(rec.widget), TopY(note), TopY(reload.widget)
  T.ok(yDrop > yNote and yNote > yButton, "dropdown, note, button, top to bottom")
  T.ok(yButton > TopY(controls["widget.textColor"].widget), "above the Texts section")
  -- choosing only changes the setting: no reload, no live switch
  ui.ClickMenuItem(ui.FindMenuItem(root, "Fran\195\167ais"))
  T.eq(ns.settings.language, "frFR")
  T.eq(ui.reloads, 0, "choosing a language does not reload")
  T.eq(L.ON, "on", "no live switch")
  root = rawget(rec.widget, "_root")
  T.ok(ui.IsChecked(ui.FindMenuItem(root, "Fran\195\167ais")), "the dropdown follows the setting")
  T.no(ui.IsChecked(ui.FindMenuItem(root, "Auto")))
  ui.ClickMenuItem(ui.FindMenuItem(root, "English"))
  T.eq(ns.settings.language, "enUS")
  -- an outside change (/tpl lang) is followed while the panel is shown
  Stub.RunSlash("lang auto")
  root = rawget(rec.widget, "_root")
  T.ok(ui.IsChecked(ui.FindMenuItem(root, "Auto")))
  -- the reload button calls ReloadUI once per click
  Stub.RunScript(reload.widget, "OnClick", "LeftButton")
  T.eq(ui.reloads, 1, "ReloadUI called once")
  ns.Options.Refresh()
  T.eq(ui.reloads, 1, "a refresh does not reload")
  T.eq(Stub.onUpdateCount, 0)
end)

T.test("options: the language controls in French, with the fallback cycle button", function()
  local ns = Start({ ui = { modern = false }, locale = "frFR" })
  local L = ns.L
  ns.Options.Open()
  local controls = Controls()
  local rec = controls.language
  T.ok(rec ~= nil, "language control with the fallback controls")
  T.eq(rec.label:GetText(), "Langue (Language)")
  T.eq(rec.index, controls["widget.hideAtMax"].index + 1)
  for i, want in ipairs({ { "auto", "Auto" }, { "enUS", "English" }, { "frFR", "Fran\195\167ais" } }) do
    T.eq(rec.choices[i].value, want[1])
    T.eq(rec.choices[i].label, want[2], "label in its own language: " .. want[1])
  end
  T.eq(#rec.choices, 3)
  T.ok(FindRegion("Auto") ~= nil, "the button shows the setting")
  local b = rec.widget
  b:GetScript("OnClick")(b, "LeftButton")
  T.eq(ns.settings.language, "enUS")
  T.ok(FindRegion("English") ~= nil)
  b:GetScript("OnClick")(b, "LeftButton")
  T.eq(ns.settings.language, "frFR")
  b:GetScript("OnClick")(b, "LeftButton")
  T.eq(ns.settings.language, "auto", "wraps around")
  b:GetScript("OnClick")(b, "RightButton")
  T.eq(ns.settings.language, "frFR", "backwards")
  T.eq(Stub.ui.reloads, 0, "cycling does not reload")
  T.ok(FindRegion(L.OPT_LANGUAGE_NOTE) ~= nil, "French note")
  T.ok(find(L.OPT_LANGUAGE_NOTE, "zones", 1, true) ~= nil)
  local reload = controls["language.reload"]
  T.ok(FindRegion("Recharger l'interface") ~= nil, "French button text")
  Stub.RunScript(reload.widget, "OnClick", "LeftButton")
  T.eq(Stub.ui.reloads, 1)
end)

T.test("options: a stored unknown language shows as Auto; the reload button without ReloadUI", function()
  -- a value from a newer version is repaired to auto before the panel shows it
  local ns = Start({ ui = { modern = true, reload = false }, db = { schema = 1, settings = { language = "deDE" } } })
  ns.Options.Open()
  local rec = Controls().language
  local root = rawget(rec.widget, "_root")
  T.ok(Stub.ui.IsChecked(Stub.ui.FindMenuItem(root, "Auto")), "repaired to auto")
  T.eq(rawget(_G, "ReloadUI"), nil, "no ReloadUI")
  Stub.RunScript(Controls()["language.reload"].widget, "OnClick", "LeftButton")
  T.eq(#Stub.errors, 0, "nothing happens")
end)

---------------------------------------------------------------------------
-- /tpl lang
---------------------------------------------------------------------------

T.test("/tpl lang lists, /tpl lang <value> sets (case-insensitive), anything else is unknown", function()
  local ns = Start()
  local L = ns.L
  local n = #Stub.printed
  Stub.RunSlash("lang")
  T.ok(Printed(format(L.LANG_LIST_FMT, "Auto", "auto, en, fr"), n + 1), "current value and the choices")
  T.eq(ns.settings.language, "auto", "listing changes nothing")
  for _, case in ipairs({ { "lang fr", "frFR", "Fran\195\167ais" }, { "lang EN", "enUS", "English" },
                          { "lang FrFr", "frFR", "Fran\195\167ais" }, { "lang enus", "enUS", "English" },
                          { "lang Auto", "auto", "Auto" }, { "LANG frFR", "frFR", "Fran\195\167ais" } }) do
    n = #Stub.printed
    Stub.RunSlash(case[1])
    T.eq(ns.settings.language, case[2], case[1])
    T.ok(Printed(format(L.LANG_SET_FMT, case[3]), n + 1), case[1] .. ": confirmation")
  end
  T.ok(find(L.LANG_SET_FMT, "/reload", 1, true) ~= nil, "the confirmation says a /reload is needed")
  n = #Stub.printed
  Stub.RunSlash("lang fr")
  T.ok(Printed(format(L.LANG_SET_FMT, "Fran\195\167ais"), n + 1), "the same value again: still confirmed")
  n = #Stub.printed
  Stub.RunSlash("lang")
  T.ok(Printed(format(L.LANG_LIST_FMT, "Fran\195\167ais", "auto, en, fr"), n + 1), "the setting")
  for _, bad in ipairs({ "lang xx", "lang deDE", "lang french", "lang fr_FR", "lang 1" }) do
    n = #Stub.printed
    Stub.RunSlash(bad)
    T.ok(Printed(format(L.UNKNOWN_CMD_FMT, bad), n + 1), "unknown: " .. bad)
    T.eq(ns.settings.language, "frFR", "unchanged by " .. bad)
  end
  T.eq(L.ON, "on", "the strings change at the next UI load only")
  T.eq(Stub.ui.reloads, 0, "the command never reloads")
  -- help: the language line right after the theme line, the theme line after the style line
  n = #Stub.printed
  Stub.RunSlash("help")
  local styleAt, themeAt, langAt
  for i = n + 1, #Stub.printed do
    local line = Stub.printed[i]
    if find(line, L.HELP_STYLE, 1, true) then styleAt = i end
    if find(line, L.HELP_THEME, 1, true) then themeAt = i end
    if find(line, L.HELP_LANG, 1, true) then langAt = i end
  end
  T.ok(styleAt ~= nil and themeAt ~= nil and langAt ~= nil, "style, theme and lang lines")
  T.eq(themeAt, styleAt + 1, "HELP_THEME after HELP_STYLE")
  T.eq(langAt, themeAt + 1, "HELP_LANG after HELP_THEME")
  T.ok(find(L.HELP_LANG, "/tpl lang", 1, true) ~= nil)
end)

T.test("/tpl lang in French", function()
  local ns = Start({ locale = "frFR" })
  local n = #Stub.printed
  Stub.RunSlash("lang")
  T.ok(Printed("Langue : Auto. Disponibles : auto, en, fr.", n + 1))
  n = #Stub.printed
  Stub.RunSlash("lang en")
  T.eq(ns.settings.language, "enUS")
  T.ok(Printed("Langue : English. Tapez /reload pour l'appliquer.", n + 1), "said in the current language")
  n = #Stub.printed
  Stub.RunSlash("help")
  T.ok(Printed("/tpl lang [auto | en | fr] - affiche ou change la langue de TruePlayed (apr\195\168s /reload)", n + 1))
  -- the next UI load is in English
  ns = Stub.Restart({ reload = true, settle = 3 })
  T.eq(ns.L.ON, "on")
  n = #Stub.printed
  Stub.RunSlash("lang")
  T.ok(Printed("Language: English. Available: auto, en, fr.", n + 1))
end)

-- The recipe for a new locale (enUS.lua header): the listing is built from C.LANGUAGES
-- and the aliases, and a copy of frFR.lua needs one edit (its CODE line) to register
-- another language without touching French.
T.test("/tpl lang lists C.LANGUAGES; a copy of frFR.lua with another CODE registers that code", function()
  local ns = Start()
  local L = ns.L
  local codes = ns.C.LANGUAGES
  codes[#codes + 1] = "deDE"
  local n = #Stub.printed
  Stub.RunSlash("lang")
  T.ok(Printed(format(L.LANG_LIST_FMT, "Auto", "auto, en, fr, deDE"), n + 1),
    "a code without an alias is listed as its code")
  codes[#codes] = nil

  local f = assert(io.open(Stub.ROOT .. "Locales/frFR.lua", "rb"))
  local src = f:read("*a")
  f:close()
  local copy, count = src:gsub('\nlocal CODE = "frFR"\n', '\nlocal CODE = "deDE"\n')
  T.eq(count, 1, "one CODE line")
  local function Run(client)
    local done = false
    local chunk = assert(load(function()
      if done then return nil end
      done = true
      return copy
    end, "=Locales/deDE.lua"))
    local frTable = {}
    local cns = { L = {}, LOCALES = { frFR = frTable } }
    Stub.locale = client
    chunk("TruePlayed", cns)
    return cns, frTable
  end
  local fr = FR()
  local cns, frTable = Run("frFR")
  T.ok(cns.LOCALES.frFR == frTable, "the French table stays")
  T.eq(cns.LOCALES.deDE, fr, "the copy registers under its CODE")
  T.eq(cns.L, {}, "a French client's L is not filled by the copy")
  cns = Run("deDE")
  T.eq(cns.L, fr, "a client in the copy's language gets it at file load")
end)

---------------------------------------------------------------------------
-- Memory: the locale tables are dropped after login
---------------------------------------------------------------------------

T.test("language: the locale tables are dropped after login and collected", function()
  for _, case in ipairs({ { "enUS" }, { "enUS", "frFR" }, { "frFR" }, { "frFR", "enUS" } }) do
    Stub.Reset()
    Stub.InstallUI()
    Stub.locale = case[1]
    if case[2] then rawset(_G, "TruePlayedDB", { schema = 1, settings = { language = case[2] } }) end
    local ns = Stub.LoadAddon()
    local weak = setmetatable({}, { __mode = "v" })
    weak.fr, weak.en = ns.LOCALES.frFR, ns.LOCALES.enUS
    T.ok(weak.fr ~= nil and weak.en ~= nil, "registered at file load")
    Stub.LoginSequence({ settle = 3 })
    T.eq(ns.LOCALES, nil, "dropped")
    collectgarbage("collect")
    collectgarbage("collect")
    T.eq(weak.fr, nil, "frFR table collected (" .. concat(case, " / ") .. ")")
    T.eq(weak.en, nil, "English copy collected (" .. concat(case, " / ") .. ")")
    T.eq(type(ns.L.ON), "string", "ns.L stays")
  end
end)
