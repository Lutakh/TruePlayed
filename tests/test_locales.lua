-- tests/test_locales.lua - the translations (design/NEXT-LOT.md, backlog 1): every locale
-- file has the keys of enUS.lua with the same format arguments in the same order, its own
-- number and date formats and its short duration units; the language names; the
-- languages offered (options dropdown, /tpl lang, its help line) and applied on each
-- client (ruRU, koKR, zhCN and zhTW only on a client in that language); every locale
-- loads and shows every view without a Lua error; and the texts fit, measured with the
-- real fonts (tests/fontmetrics.lua): the tooltip rows of every theme (short and Shift,
-- the widest XP rows with a margin), the bar (every slot token, the narrowest bar at text
-- size 16, nothing dropped or cut that English keeps at the default size), the options
-- panel (labels, dropdown entries, buttons), the statistics window (column headers, tabs,
-- buttons, hint, footers) and the graph. Cyrillic is measured with the Cyrillic-capable
-- theme fonts or a stand-in of the Cyrillic game font, Hangul and Han one em per
-- character (no metrics of those game fonts in the repository: conservative).
-- enUS and frFR are part of every check below except the tooltip ones, which
-- tests/test_round4_regress.lua (F1-fidelity) runs for them.
-- This file is Latin-1 like every test: non-Latin texts are decimal escapes.
local Stub, T = ...

local format, find, concat = string.format, string.find, table.concat
local unpack = unpack or table.unpack
local FM = dofile(Stub.ROOT .. "tests/fontmetrics.lua")

local ALL = { "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local NEW = { "deDE", "esES", "esMX", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
local NATIVE = { ruRU = true, koKR = true, zhCN = true, zhTW = true }
local LATIN_VALUES = { "auto", "enUS", "frFR", "deDE", "esES", "esMX", "itIT", "ptBR" }
local ALIAS = { auto = "auto", enUS = "en", frFR = "fr", deDE = "de", esES = "es", esMX = "mx", itIT = "it",
                ptBR = "pt", ruRU = "ru", koKR = "ko", zhCN = "cn", zhTW = "tw" }
-- The language names, each in its own language, the same in every locale file.
local NAMES = {
  LANG_ENUS = "English", LANG_FRFR = "Fran\195\167ais", LANG_DEDE = "Deutsch",
  LANG_ESES = "Espa\195\177ol (EU)", LANG_ESMX = "Espa\195\177ol (AL)", LANG_ITIT = "Italiano",
  LANG_PTBR = "Portugu\195\170s (BR)",
  LANG_RURU = "\208\160\209\131\209\129\209\129\208\186\208\184\208\185",
  LANG_KOKR = "\237\149\156\234\181\173\236\150\180",
  LANG_ZHCN = "\231\174\128\228\189\147\228\184\173\230\150\135",
  LANG_ZHTW = "\231\185\129\233\171\148\228\184\173\230\150\135",
}
local LANG_KEY = { enUS = "LANG_ENUS", frFR = "LANG_FRFR", deDE = "LANG_DEDE", esES = "LANG_ESES", esMX = "LANG_ESMX",
                   itIT = "LANG_ITIT", ptBR = "LANG_PTBR", ruRU = "LANG_RURU", koKR = "LANG_KOKR", zhCN = "LANG_ZHCN",
                   zhTW = "LANG_ZHTW" }
-- Keys that may keep the English text: names, symbols, numbers and the international
-- words of the game (FPS, PvP, AFK, XP...). Any other key equal to English is untranslated.
local SAME_OK = {
  ADDON_TITLE = true, CHAT_PREFIX = true, EXCL_STATE_FMT = true, ETA_FMT = true, NUM_K = true, NUM_M = true,
  PERCENT_FMT = true, PER_HOUR = true, FPS_FMT = true, MS_FMT = true, DOTS = true, SEP = true, RANGE_FMT = true,
  DECIMAL_SEP = true, THOUSANDS_SEP = true, DATE_FMT = true, TIME_FMT = true, DUR_LT_1M = true, ETA_LT_1M = true,
  DUR_H = true, DUR_M = true, DUR_LONG_M = true, DUR_LONG_HM = true,
  TOKEN_FPS = true, PFX_SERVER_FMT = true, PFX_AFK_FMT = true, PFX_ZONE_FMT = true, PFX_INST_SESSION_FMT = true,
  PFX_PLAYED_FMT = true, PFX_INST_TOTAL_FMT = true, PFX_SESSION_FMT = true, XP_BARE_FMT = true, STALL_MARK = true,
  TT_XP = true, TT_RESTED_FMT = true, TT_SERVER_AGE_FMT = true, BD_PART_FMT = true, BD_PVP = true, BD_AFK = true,
  MASK_AFK = true, TT_AFK = true, TT_NET_FMT = true, INST_ROW_FMT = true, KIND_PVP = true, COL_AFK = true,
  COL_XP = true, COL_XPH = true, COL_SERVER = true, COL_INST = true, COL_ZONE = true, COL_CHARS = true,
  GRAPH_WINDOW_30 = true, GRAPH_WINDOW_60 = true, GRAPH_WINDOW_300 = true, GRAPH_AGE_S_FMT = true,
  GRAPH_AGE_MS_FMT = true, SLIDER_PX_FMT = true, SLIDER_PCT_FMT = true, OPT_SLOT2 = true, OPT_SLOT3 = true,
  OPT_VERSION_FMT = true, TT_SESSION = true, TAB_ZONES = true, TAB_SESSIONS = true, TT_ZONE_FMT = true,
  THEME_PALADIN = true, THEME_MAGE = true, LANG_AUTO = true, MENU_OPTIONS = true, REACT_NORMAL = true,
  ERASE_NO = true, OPT_EXCLUSIONS = true, PCTH_FMT = true, COL_DATE = true, DATE_AUTO_FMT = true,
  -- cognates (frFR since 1.0)
  BD_RAID = true, HELP_OPTIONS = true, KIND_RAID = true, SECTION_CONTINENTS = true,
  THEME_HEROIC = true, BD_DUNGEON = true, TT_OF_WHICH_AFK_FMT = true, XP_FMT = true, XP_LABEL = true,
  -- minimap button and mini display (backlog 3 and 4): "Info %d" as OPT_SLOT2, "Options" (fr)
  OPT_MINI_INFO_FMT = true, CLICK_OPTIONS = true,
}
for name in pairs(NAMES) do SAME_OK[name] = true end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

-- Raw strings of one locale file loaded alone, on a client in that language.
local function LocaleTable(code, client)
  local saved = Stub.locale
  Stub.locale = client or code
  local ns = {}
  if code ~= "enUS" then ns.L = {} end
  assert(loadfile(Stub.ROOT .. "Locales/" .. code .. ".lua"))("TruePlayed", ns)
  Stub.locale = saved
  local out = {}
  if code == "enUS" then
    for k, v in pairs(ns.L) do out[k] = v end
  else
    for k, v in pairs(ns.LOCALES[code]) do out[k] = v end
  end
  return out, ns
end

local function ReadFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Format arguments of a pattern, in order (literal percents "%%" left out).
local function Specs(s)
  local out = {}
  for spec in s:gsub("%%%%", ""):gmatch("%%[%d%.%-]*[sd]") do out[#out + 1] = spec end
  return out
end

-- A pattern of the format keys: a "%" that is neither "%%" nor an argument.
local function StrayPercent(s)
  return s:gsub("%%%%", ""):gsub("%%[%d%.%-]*[sd]", ""):find("%%") ~= nil
end

-- Characters (UTF-8 code points) of s, colour codes left out.
local function Chars(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 128 or b >= 192 then n = n + 1 end
  end
  return n
end

local function IsLatin1(s)
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    if b < 0x80 then
      i = i + 1
    elseif b == 0xC2 or b == 0xC3 then
      i = i + 2
    else
      return false
    end
  end
  return true
end

local function Printed(text, from)
  local lines = Stub.printed
  for i = from or 1, #lines do
    if find(lines[i], text, 1, true) then return true end
  end
  return false
end

-- A session: client `client`, language setting `language` (nil = auto), theme `theme`
-- (nil: the stub's classic; false: the shipped default).
local function Start(client, language, opts)
  opts = opts or {}
  Stub.InstallUI(opts.ui or { modern = true })
  Stub.locale = client
  if opts.theme == false then Stub.theme = nil elseif opts.theme then Stub.theme = opts.theme end
  local settings = { firstRunDone = true }
  if language then settings.language = language end
  for k, v in pairs(opts.settings or {}) do settings[k] = v end
  rawset(_G, "TruePlayedDB", { schema = 1, settings = settings })
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  return ns
end

-- Client and setting that show language `code`: its own client, auto.
local function StartIn(code, opts)
  return Start(code, nil, opts)
end

local function Controls()
  return rawget(Stub.ui.categories[1].frame, "controls")
end

---------------------------------------------------------------------------
-- The locale files
---------------------------------------------------------------------------

T.test("locales: every file has the keys of enUS with the same format arguments, in the same order", function()
  local en = LocaleTable("enUS")
  local n = 0
  for _ in pairs(en) do n = n + 1 end
  T.ok(n > 380, "enUS keys: " .. n)
  for _, code in ipairs(ALL) do
    if code ~= "enUS" then
      local L = LocaleTable(code)
      for k, v in pairs(en) do
        local t = L[k]
        if type(t) ~= "string" then
          T.ok(false, code .. " misses " .. k)
        elseif k ~= "DATE_FMT" and k ~= "TIME_FMT" then
          T.eq(Specs(t), Specs(v), code .. " " .. k .. ": format arguments")
          local isFormat = #Specs(v) > 0 or find(v, "%%", 1, true) ~= nil
          if isFormat then
            T.no(StrayPercent(t), code .. " " .. k .. ": a literal percent is written %%")
            local args = {}
            for i, spec in ipairs(Specs(v)) do args[i] = spec:sub(-1) == "d" and 7 or "x" end
            T.ok(pcall(format, t, unpack(args)), code .. " " .. k .. ": formats")
          end
        end
      end
      for k in pairs(L) do T.ok(en[k] ~= nil, code .. " has a key enUS lacks: " .. tostring(k)) end
    end
  end
end)

T.test("locales: dates, numbers and short duration units of each language", function()
  for _, code in ipairs(ALL) do
    local L = LocaleTable(code)
    for _, k in ipairs({ "DATE_FMT", "TIME_FMT" }) do
      local ok, s = pcall(os.date, L[k], 1790799275)
      T.ok(ok and type(s) == "string" and not find(s, "%", 1, true), code .. " " .. k .. ": " .. tostring(s))
    end
    T.ok(L.DECIMAL_SEP ~= L.THOUSANDS_SEP and L.DECIMAL_SEP ~= "", code .. ": separators")
    T.ok(find(L.CHAT_PREFIX, "|cff8b5cf6TruePlayed|r", 1, true) == 1, code .. ": chat prefix")
    -- short units: the bar shows them next to other infos
    local cases = {
      { L.DUR_D_H, { 12, 23 }, 11 }, { L.DUR_H_M, { 9, 55 }, 11 }, { L.DUR_H, { 23 }, 6 },
      { L.DUR_M, { 59 }, 6 }, { L.DUR_LT_1M, {}, 7 }, { L.ETA_LT_1M, {}, 7 },
      { L.PFX_AVG_FMT, { "9h 55m" }, 18 }, { L.KILLS_FMT, { "1,234" }, 14 }, { L.PCTH_FMT, { "12.5" }, 9 },
    }
    for _, c in ipairs(cases) do
      local s = format(c[1], unpack(c[2]))
      T.ok(Chars(s) <= c[3], format("%s: %q is short (%d characters at most)", code, s, c[3]))
    end
  end
end)

T.test("locales: the language names, CODE, the registration and the client's language at file load", function()
  local en = LocaleTable("enUS")
  for _, code in ipairs(ALL) do
    local L = LocaleTable(code)
    for k, want in pairs(NAMES) do T.eq(L[k], want, code .. " " .. k .. ": the name in its own language") end
    if code ~= "enUS" then
      local src = ReadFile(Stub.ROOT .. "Locales/" .. code .. ".lua")
      local _, count = src:gsub('\nlocal CODE = "' .. code .. '"\n', "")
      T.eq(count, 1, code .. ": one CODE line naming the file")
      -- registers its table on any client; fills ns.L only on a client in its language
      local _, foreign = LocaleTable(code, code == "deDE" and "frFR" or "deDE")
      T.eq(foreign.L, {}, code .. ": ns.L untouched on another client")
      local _, own = LocaleTable(code, code)
      T.eq(own.L, L, code .. ": ns.L filled on its own client")
      -- not English (keys allowed to keep the English text aside)
      local same = {}
      for k, v in pairs(en) do
        if L[k] == v and not SAME_OK[k] then same[#same + 1] = k end
      end
      table.sort(same)
      T.eq(same, {}, code .. ": keys still in English")
    end
    -- Latin-1 files: Latin-1 values (the native-only language names aside)
    for k, v in pairs(L) do
      if not NATIVE[code] and not NAMES[k] then T.ok(IsLatin1(v), code .. " " .. k .. ": Latin-1") end
    end
  end
end)

T.test("locales: the TOC lists every locale file, with the Notes and Category of the Latin-1 ones", function()
  local toc = ReadFile(Stub.ROOT .. "TruePlayed_Camelot.toc")
  local prev = toc:find("Locales\\frFR.lua", 1, true)
  T.ok(prev ~= nil, "frFR listed")
  for _, code in ipairs(NEW) do
    local at = toc:find("Locales\\" .. code .. ".lua", 1, true)
    T.ok(at ~= nil and at > prev, code .. ": listed after the previous locale")
    prev = at or prev
    if not NATIVE[code] then
      T.ok(toc:find("\n## Notes-" .. code .. ": ", 1, true) ~= nil, code .. ": Notes")
      T.ok(toc:find("\n## Category-" .. code .. ": ", 1, true) ~= nil, code .. ": Category")
    end
  end
  T.ok(toc:find("Locales\\zhTW.lua", 1, true) < toc:find("\nCore.lua", 1, true), "locales before Core.lua")
end)

---------------------------------------------------------------------------
-- The languages offered and applied
---------------------------------------------------------------------------

local function DropdownValues(ns)
  ns.Options.Open()
  local rec = Controls().language
  local root = rawget(rec.widget, "_root")
  local values, labels, checked = {}, {}, nil
  for i = 1, #root.children do
    local item = root.children[i]
    values[i], labels[i] = item.data.value, item.text
    if Stub.ui.IsChecked(item) then checked = item.data.value end
  end
  Stub.ui.CloseSettings()
  return values, labels, checked
end

local function Aliases(values)
  local out = {}
  for i = 1, #values do out[i] = ALIAS[values[i]] end
  return out
end

T.test("languages: every Latin-script language everywhere, a native-only one on its own client only", function()
  for _, client in ipairs(ALL) do
    Stub.Reset()
    local ns = Start(client, nil)
    local L = LocaleTable(client)
    local want = {}
    for i, v in ipairs(LATIN_VALUES) do want[i] = v end
    if NATIVE[client] then want[#want + 1] = client end
    local values, labels, checked = DropdownValues(ns)
    T.eq(values, want, client .. " client: the dropdown")
    T.eq(checked, "auto", client .. ": auto")
    T.eq(labels[1], L.LANG_AUTO, client .. ": Auto in the client's language")
    for i = 2, #values do T.eq(labels[i], NAMES[LANG_KEY[values[i]]], client .. ": " .. values[i]) end
    -- /tpl lang: the same values; the help line lists them
    local n = #Stub.printed
    Stub.RunSlash("lang")
    T.ok(Printed(format(L.LANG_LIST_FMT, L.LANG_AUTO, concat(Aliases(want), ", ")), n + 1), client .. ": listing")
    n = #Stub.printed
    Stub.RunSlash("help")
    T.ok(Printed(format(L.HELP_LANG, concat(Aliases(want), " | ")), n + 1), client .. ": help line")
    -- a native-only language of another client is not offered
    for code in pairs(NATIVE) do
      if code ~= client then
        n = #Stub.printed
        Stub.RunSlash("lang " .. ALIAS[code])
        T.ok(Printed(format(L.UNKNOWN_CMD_FMT, "lang " .. ALIAS[code]), n + 1), client .. ": " .. code .. " refused")
        Stub.RunSlash("lang " .. code:lower())
        T.eq(ns.settings.language, "auto", client .. ": " .. code .. " not set")
      end
    end
    -- each offered value is set by its alias
    for _, v in ipairs(want) do
      n = #Stub.printed
      Stub.RunSlash("lang " .. ALIAS[v])
      T.eq(ns.settings.language, v, client .. ": /tpl lang " .. ALIAS[v])
      T.ok(Printed(format(L.LANG_SET_FMT, v == "auto" and L.LANG_AUTO or NAMES[LANG_KEY[v]]), n + 1),
        client .. ": confirmation of " .. v)
    end
    T.eq(#Stub.errors, 0, client .. ": no error")
  end
end)

T.test("languages: each language applies at login; a native-only one only on its own client", function()
  local tables = {}
  for _, code in ipairs(ALL) do tables[code] = LocaleTable(code) end
  local en = tables.enUS
  local function Same(L, want, msg)
    local bad = 0
    for k, v in pairs(want) do
      if rawget(L, k) ~= v then bad = bad + 1 end
    end
    T.eq(bad, 0, msg)
  end
  -- a Latin-script language on any client
  for _, code in ipairs(LATIN_VALUES) do
    if code ~= "auto" then
      for _, client in ipairs({ "enUS", "frFR", "ruRU", "koKR", "zhCN" }) do
        Stub.Reset()
        local ns = Start(client, code)
        Same(ns.L, tables[code], code .. " on a " .. client .. " client")
        T.eq(ns.LOCALES, nil)
      end
    end
  end
  -- a native-only language: on its client (auto or chosen); elsewhere the client's language
  for code in pairs(NATIVE) do
    for _, language in ipairs({ "auto", code }) do
      Stub.Reset()
      local ns = Start(code, language)
      Same(ns.L, tables[code], code .. " client, " .. language)
    end
    for _, client in ipairs({ "enUS", "deDE", "frFR", code == "zhCN" and "zhTW" or "zhCN" }) do
      Stub.Reset()
      local ns = Start(client, code)
      T.eq(ns.Core.GetSetting("language"), code, "the stored value is kept")
      Same(ns.L, tables[client], code .. " stored on a " .. client .. " client: the client's language")
      -- still offered (selected), named by its code (its script would not draw)
      local values, labels, checked = DropdownValues(ns)
      T.eq(checked, code, code .. " on " .. client .. ": selected")
      local at
      for i = 1, #values do
        if values[i] == code then at = i end
      end
      T.ok(at ~= nil and labels[at] == code, code .. " on " .. client .. ": offered, named by its code")
      local n = #Stub.printed
      Stub.RunSlash("lang")
      T.ok(Printed(format(tables[client].LANG_LIST_FMT, code, concat(Aliases(values), ", ")), n + 1),
        code .. " on " .. client .. ": the listing names the code and offers it")
      Stub.Logout()
      T.eq(Stub.saved.settings.language, code, "kept in the file")
    end
  end
  T.eq(en.LANG_AUTO, "Auto")
end)

T.test("languages: every locale table is dropped after login and collected", function()
  for _, client in ipairs({ "enUS", "deDE", "ruRU", "zhTW" }) do
    Stub.Reset()
    Stub.InstallUI()
    Stub.locale = client
    local ns = Stub.LoadAddon()
    local weak = setmetatable({}, { __mode = "v" })
    for _, code in ipairs(ALL) do
      weak[code] = ns.LOCALES[code]
      T.ok(weak[code] ~= nil, client .. ": " .. code .. " registered at file load")
    end
    Stub.LoginSequence({ settle = 3 })
    T.eq(ns.LOCALES, nil, "dropped")
    collectgarbage("collect")
    collectgarbage("collect")
    for _, code in ipairs(ALL) do T.eq(weak[code], nil, client .. ": " .. code .. " collected") end
    T.eq(type(ns.L.ON), "string")
  end
end)

-- Every locale on its own client, every view: no Lua error, and the texts of the run
-- differ from the English run (nothing left untranslated in the drawn texts).
T.test("locales: every view in every language, no Lua error, no English text left", function()
  local function Texts(client, language)
    Stub.Reset()
    local p = Stub.player
    p.level, p.xp, p.rest = 20, 10115, 3000
    p.max = Stub.xpTable[20]
    local ns = Start(client, language, { theme = false })
    for _ = 1, 6 do
      Stub.Advance(30)
      Stub.Kill(171)
    end
    Stub.Advance(2)
    local bar = ns.Bar.frame
    ns.Tooltip.ShowFor(bar)
    Stub.Advance(1)
    Stub.SetShift(true)
    Stub.Advance(1)
    Stub.SetShift(false)
    ns.Tooltip.Hide(bar)
    ns.Graph.ShowFor(bar)
    Stub.Advance(2)
    ns.Graph.Hide()
    ns.Window.Show("levels")
    for _, tab in ipairs({ "zones", "sessions" }) do
      ns.Window.Toggle(tab)
      Stub.Advance(1)
    end
    ns.Window.SetView("account")
    Stub.Advance(1)
    ns.Window.Hide()
    ns.Options.Open()
    Stub.Advance(1)
    Stub.ui.CloseSettings()
    ns.Options.ShowContextMenu(bar)
    for _, cmd in ipairs({ "help", "theme", "lang", "played", "perf", "sync", "nonsense", "reset char" }) do
      Stub.RunSlash(cmd)
    end
    Stub.Advance(65)
    local out = {}
    for i = 1, #Stub.regions do
      local t = rawget(Stub.regions[i], "_text")
      if type(t) == "string" and t ~= "" then out[#out + 1] = t end
    end
    for i = 1, #Stub.printed do out[#out + 1] = Stub.printed[i] end
    for _, id in ipairs(ns.Tokens.ORDER) do
      out[#out + 1] = ns.Tokens.Render(id) or ""
      out[#out + 1] = ns.Tokens.Label(id)
    end
    T.eq(Stub.errors, {}, client .. " / " .. tostring(language) .. ": no Lua error")
    return out
  end
  local english = Texts("enUS")
  local englishSet = {}
  for _, s in ipairs(english) do englishSet[s] = true end
  for _, code in ipairs(NEW) do
    local own = Texts(code)
    local differ = 0
    for _, s in ipairs(own) do
      if not englishSet[s] then differ = differ + 1 end
    end
    T.ok(#own > 200 and differ > 0.6 * #own, format("%s: %d of %d texts differ from English", code, differ, #own))
    if not NATIVE[code] then
      local chosen = Texts("enUS", code)
      T.eq(#chosen, #own, code .. ": chosen on an enUS client = its own client (count)")
    end
  end
end)

---------------------------------------------------------------------------
-- Widths with the real fonts (tests/fontmetrics.lua)
---------------------------------------------------------------------------

local KEYS = { "futuriste", "actuel", "heroic", "pixel", "warrior", "paladin", "hunter", "rogue",
               "priest", "shaman", "mage", "warlock", "druid" }
-- Font sizes of the game's font objects used by the options panel and the window.
local OBJECT_SIZE = { GameFontNormal = 12, GameFontHighlight = 12, GameFontHighlightSmall = 10, GameFontDisable = 12 }

-- TP_LIST_WIDTHS=1 lua tests/run.lua locales: every text that does not fit is printed
-- (the assertions show the first ones only).
local LIST = os.getenv and os.getenv("TP_LIST_WIDTHS")
local function Report(bad, msg)
  if LIST then
    for i = 1, #bad do print("  " .. msg .. ": " .. bad[i]) end
  end
  T.eq(bad, {}, msg)
end

local fontWidth
local function RealWidths(body)
  fontWidth = fontWidth or FM.New(Stub.ROOT)
  local restore = FM.Install(Stub, fontWidth)
  local ok, err = pcall(body, fontWidth)
  restore()
  if not ok then error(err, 0) end
end

local function L_TEXT(fs) return tostring(rawget(fs, "_text")) end

-- Drawn width of a FontString (its font, or the size of its game font object).
local function FSWidth(Width, fs, text)
  local size = rawget(fs, "_fontSize") or OBJECT_SIZE[rawget(fs, "_fontObject")] or 12
  return Width(rawget(fs, "_font"), size, text or rawget(fs, "_text"))
end

-- A level-20 character after some play in theme `theme`, the language of client `code`:
-- "kills" = 8 kills in 4 min (the widest values), "none" = no kill yet, "long" = an hour
-- of kills, "stall" = frozen rate, "cap" = a server level cap.
local function StartPlay(theme, code, play)
  Stub.InstallUI({ ldb = false })
  Stub.theme = theme
  Stub.locale = code
  local p = Stub.player
  p.level, p.xp, p.rest = 20, 10115, 0
  p.max = Stub.xpTable[20] or 23200
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  ns.Core.SetSetting("widget.locked", true)
  Stub.Advance(1)
  if play == "kills" then
    for _ = 1, 8 do Stub.Advance(30); Stub.Kill(171) end
  elseif play == "long" then
    for _ = 1, 60 do Stub.Advance(60); Stub.Kill(171) end
  elseif play == "stall" then
    for _ = 1, 8 do Stub.Advance(30); Stub.Kill(171) end
    Stub.Advance(900)
  elseif play == "activity" then
    -- lot 8: every breakdown part but the instances, 12 deaths and 1 h 05 dead, crafting
    for _ = 1, 20 do Stub.Advance(60); Stub.Kill(171) end
    for _ = 1, 12 do Stub.Die(); Stub.Advance(65); Stub.ReleaseSpirit(); Stub.Advance(260); Stub.Resurrect(true) end
    Stub.OpenTradeSkill(); Stub.Advance(1500); Stub.CloseTradeSkill()
    Stub.SetAFK(true); Stub.Advance(900); Stub.SetAFK(false)
    Stub.SetTaxi(true); Stub.Advance(600); Stub.SetTaxi(false)
    Stub.SetMap(1454); Stub.Advance(600); Stub.SetMap(1411)
    Stub.SetResting(true); Stub.Advance(600); Stub.SetResting(false)
  elseif play == "cap" then
    for _ = 1, 3 do Stub.KillNoXP() end
  end
  Stub.Advance(2)
  return ns, ns.Bar.frame
end

-- Rows of the shown private tooltip that do not fit (tests/test_round4_regress.lua).
local function CutRows(ns)
  local tf = ns.TooltipFrame.frame
  local tt = ns.Themes.Active().tt
  local inner = tf:GetWidth() - tt.pad[1] - tt.pad[2]
  local out = {}
  for i = 1, tf.tp.n do
    local row = tf.tp.rows[i]
    if not row.wrap and row.left:IsShown() then
      local lw = row.left:GetUnboundedStringWidth()
      local need = lw
      if row.right:IsShown() and row.kind ~= "title" then
        need = lw + tt.gap + row.right:GetUnboundedStringWidth()
      end
      if (rawget(row.left, "_width") or 0) > 0 or need > inner + 0.5 then
        out[#out + 1] = format("%q %.0f > %.0f", tostring(row.left:GetText()), need, inner)
      end
    end
  end
  return out
end

-- F1-fidelity of tests/test_round4_regress.lua for the new locales.
T.test("widths: no tooltip row is cut (every theme, every new locale, short / Shift)", function()
  RealWidths(function()
    local bad = {}
    for _, key in ipairs(KEYS) do
      if key ~= "actuel" then
        for _, code in ipairs(NEW) do
          for _, play in ipairs({ "kills", "none", "long", "stall", "cap", "activity" }) do
            Stub.Reset()
            local ns, frame = StartPlay(key, code, play)
            for _, shift in ipairs({ false, true }) do
              Stub.SetShift(shift)
              ns.Tooltip.ShowFor(frame)
              Stub.Advance(1)
              for _, s in ipairs(CutRows(ns)) do
                bad[#bad + 1] = format("%s %s %s %s: %s", key, code, play, shift and "Shift" or "short", s)
              end
              ns.Tooltip.Hide()
            end
            Stub.SetShift(false)
            if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
          end
        end
      end
    end
    Report(bad, "cut tooltip rows")
  end)
end)

-- The minimap button's tooltip is the bar's with another hint line (its left-click
-- action, MinimapButton.Hint): every hint fits every theme's tooltip, in every language.
T.test("widths: the minimap button's hint lines fit every theme's tooltip (every language)", function()
  RealWidths(function()
    local bad = {}
    for _, key in ipairs(KEYS) do
      if key ~= "actuel" then
        for _, code in ipairs(ALL) do
          Stub.Reset()
          local ns, frame = StartPlay(key, code, "kills")
          for _, action in ipairs({ "stats", "options", "bar", "mini" }) do
            ns.Tooltip.ShowFor(frame, ns.MinimapButton.Hint(action))
            Stub.Advance(1)
            for _, s in ipairs(CutRows(ns)) do bad[#bad + 1] = format("%s %s %s: %s", key, code, action, s) end
            ns.Tooltip.Hide()
          end
          if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
        end
      end
    end
    Report(bad, "cut minimap hints")
  end)
end)

-- The widest values the XP block can take beside their labels fit the widest tooltip of
-- every theme with MARGIN px to spare (tests/test_round4_regress.lua, F1-fidelity).
local MARGIN = 16

T.test("widths: the widest XP rows fit every theme's widest tooltip with a margin (every new locale)", function()
  fontWidth = fontWidth or FM.New(Stub.ROOT)
  local Width = fontWidth
  local bad = {}
  for _, code in ipairs(NEW) do
    Stub.Reset()
    local ns = StartIn(code, { ui = { ldb = false } })
    local L, Fmt = ns.L, ns.Fmt
    local function Estimated(text)
      return format("%s %s(%s)%s", ns.Tokens.Approx(text), "|cff999999", L.RATE_ESTIMATE, "|r")
    end
    local rows = {
      { L.TT_XPH, format(L.TT_NODATA_FMT, Fmt.Duration(ns.C.WARMUP_FULL)) },
      { L.TT_NEXT_LEVEL, Estimated(Fmt.ETA(2 * 86400 + 5 * 3600)) },
      { L.TT_XPH, Estimated(Fmt.Rate(123456)) },
      { L.TT_KILLS, L.TT_KILLS_NODATA },
      { L.TT_KILLS, format(L.TT_KILLS_FMT, Fmt.Number(1234), Fmt.Number(12345), Fmt.Number(12345)) },
      { L.TT_NEXT_LEVEL, format(L.TT_WARMING_FMT, Fmt.Duration(ns.C.WARMUP_FULL)) },
      { L.TT_RESTED, format(L.TT_RESTED_FMT, Fmt.Number(123456), Fmt.Percent(1.5, 1)) },
      { L.TT_PLAYED_EXCL_FMT:format(ns.Stats.MaskLabel(7)), Fmt.Duration(123 * 86400) },
    }
    for _, key in ipairs(KEYS) do
      if key ~= "actuel" then
        ns.Core.SetSetting("theme", key)
        local tt = ns.Themes.Active().tt
        local bp, bs = ns.Themes.Font(tt.fonts.body[1], tt.fonts.body[2])
        local vf = tt.fonts.value or tt.fonts.body
        local vp, vs = ns.Themes.Font(vf[1], vf[2])
        for _, r in ipairs(rows) do
          local need = Width(bp, bs, r[1]) + tt.gap + Width(vp, vs, r[2]) + tt.pad[1] + tt.pad[2]
          if need + MARGIN > tt.width[2] then
            bad[#bad + 1] = format("%s %s: %q + %q needs %.0f + %d > %d", key, code, r[1], r[2], need, MARGIN,
              tt.width[2])
          end
        end
      end
    end
  end
  Report(bad, "XP rows wider than the tooltip")
end)

-- Horizontal extents (frame coordinates) of every drawn element of the bar's rows
-- (tests/test_ui_smoke.lua, with the theme's padding).
local function Drawn(fs) return fs:IsShown() and (fs:GetText() or "") ~= "" end

local function RowItems(tp, pad)
  local bottom, top = {}, {}
  local function Add(items, name, l, r) items[#items + 1] = { name = name, l = l, r = r } end
  local blw = tp.bl:GetStringWidth()
  if tp.blv and tp.blv:IsShown() then
    local _, _, _, x = tp.blv:GetPoint(1)
    blw = x + tp.blv:GetStringWidth() - pad
  end
  Add(bottom, "level", pad, pad + blw)
  if tp.marker:IsShown() then
    local _, _, _, x = tp.marker:GetPoint(1)
    Add(bottom, "marker", x, x + tp.marker:GetStringWidth())
  end
  if Drawn(tp.brx) then
    local _, _, _, x = tp.brx:GetPoint(1)
    local l = x - tp.brx:GetStringWidth()
    if tp.xpl and tp.xpl:IsShown() then
      local _, _, _, lx = tp.xpl:GetPoint(1)
      l = lx - tp.xpl:GetStringWidth()
    end
    Add(bottom, "xp", l, x)
  end
  if Drawn(tp.sep) then
    local _, _, _, x = tp.sep:GetPoint(1)
    Add(bottom, "sep", x - tp.sep:GetStringWidth(), x)
  end
  local s2 = tp.slots[2]
  if Drawn(s2) then
    local _, _, _, x = s2:GetPoint(1)
    local l = x - s2:GetStringWidth()
    Add(bottom, "slot2", l, x)
    if tp.marks[2]:IsShown() then Add(bottom, "mark2", l - 10, l - 3) end
  end
  local s1, s3 = tp.slots[1], tp.slots[3]
  if Drawn(s1) then
    local _, _, _, x = s1:GetPoint(1)
    local w = s1:GetStringWidth()
    Add(top, "slot1", x - w, x)
    if tp.marks[1]:IsShown() then Add(top, "mark1", x - w - 10, x - w - 3) end
  end
  if Drawn(s3) then
    local point, _, _, x = s3:GetPoint(1)
    local w = s3:GetStringWidth()
    if point == "BOTTOM" then
      Add(top, "slot3", x - w / 2, x + w / 2)
      if tp.marks[3]:IsShown() then Add(top, "mark3", x - w / 2 - 10, x - w / 2 - 3) end
    else
      Add(top, "slot3", x, x + w)
      if tp.marks[3]:IsShown() then Add(top, "mark3", x + w + 3, x + w + 10) end
    end
  end
  return bottom, top
end

-- Every item inside [pad, pad + W], items apart by >= 3 px (6 after the level text).
local function CheckRow(items, pad, W, what, bad)
  table.sort(items, function(a, b) return a.l < b.l end)
  for i = 1, #items do
    local it = items[i]
    if it.l < pad - 0.5 or it.r > pad + W + 0.5 then
      bad[#bad + 1] = format("%s: %s [%.1f, %.1f] outside [%d, %d]", what, it.name, it.l, it.r, pad, pad + W)
    end
    if i > 1 then
      local prev = items[i - 1]
      local gap = (prev.name == "level") and 6 or 3
      if it.l < prev.r + gap - 0.5 then
        bad[#bad + 1] = format("%s: %s (%.1f) closer than %d px to %s (%.1f)", what, it.name, it.l, gap, prev.name,
          prev.r)
      end
    end
  end
end

local DEFAULT_SLOTS = { "eta_kills", "xph", "fps_latency" }

-- The bar, every theme and language, every token in each slot: at the default size
-- (width 360, text size 11) a slot English draws whole is drawn whole (not left out, not
-- cut with "..."); at the narrowest bar with the biggest text (width 150, size 16, pause
-- marks on), every text stays inside the bar and clear of the others.
T.test("widths: the bar, every theme and language, every slot token (default and narrowest at size 16)", function()
  RealWidths(function()
    local bad = {}
    local english = {}
    for _, code in ipairs(ALL) do
      for _, key in ipairs(KEYS) do
        Stub.Reset()
        local ns = StartPlay(key, code, "kills")
        Stub.fps = 144
        local tp = ns.Bar.frame.tp
        local pad = ns.Themes.Active().bar.pad or 8
        local ORDER = ns.Tokens.ORDER
        local Set = ns.Core.SetSetting
        english[key] = english[key] or {}
        for slot = 1, 3 do
          for _, id in ipairs(ORDER) do
            Set("widget.slots." .. slot, id)
            Stub.Advance(1)
            local s = tp.slots[slot]
            local bound = rawget(s, "_width") or 0
            local whole = Drawn(s) and not (bound > 0 and s:GetUnboundedStringWidth() > bound + 0.5)
            local tag = slot .. " " .. id
            if code == "enUS" then
              english[key][tag] = whole
            elseif english[key][tag] and not whole then
              bad[#bad + 1] = format("%s %s slot %s: %q left out or cut (English draws it whole)", key, code, tag,
                tostring(s:GetText()))
            end
          end
          Set("widget.slots." .. slot, DEFAULT_SLOTS[slot])
        end
        Set("widget.width", 150)
        Set("widget.fontSize", 16)
        Set("exclude.afk", true)
        Stub.SetAFK(true)
        for slot = 1, 3 do
          for _, id in ipairs(ORDER) do
            Set("widget.slots." .. slot, id)
            Stub.Advance(1)
            local bottom, top = RowItems(tp, pad)
            local what = format("%s %s W=150 size=16 slot %d %s", key, code, slot, id)
            CheckRow(bottom, pad, 150, what .. " bottom", bad)
            CheckRow(top, pad, 150, what .. " top", bad)
          end
          Set("widget.slots." .. slot, DEFAULT_SLOTS[slot])
        end
        if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
      end
    end
    Report(bad, "bar texts")
  end)
end)

local function Under(o, root)
  local p, d = rawget(o, "_parent"), 0
  while p ~= nil and d < 40 do
    if p == root then return true end
    p, d = rawget(p, "_parent"), d + 1
  end
  return false
end

-- The text FontString of a plain button (Options / Window MakeButton).
local function ButtonText(b)
  for _, o in ipairs(Stub.regions) do
    if rawget(o, "_type") == "FontString" and rawget(o, "_parent") == b then return o end
  end
  return nil
end

-- Options panel (the game's font objects; UIPanelButtonTemplate buttons draw their text
-- in GameFontNormal with about 8 px of inset on each side): a control label fits its
-- 218 px column on one line, a checkbox label the panel, a dropdown entry the 220 px
-- dropdown (its arrow aside), a button text its button.
T.test("widths: the options panel in every language (labels, dropdown entries, buttons, headers)", function()
  RealWidths(function(Width)
    local bad = {}
    for _, code in ipairs(ALL) do
      Stub.Reset()
      local ns = StartIn(code, { ui = { modern = true } })
      ns.Options.Open()
      local panel = Stub.ui.categories[1].frame
      local controls = Controls()
      local GAME = nil
      local function Check(what, text, size, limit)
        local w = Width(GAME, size, text)
        if w > limit then bad[#bad + 1] = format("%s %s: %q %.0f > %d", code, what, text, w, limit) end
      end
      for path, rec in pairs(controls) do
        local label = rec.label and rawget(rec.label, "_text")
        if label then
          if rec.kind == "check" then Check(path, label, 12, 520) else Check(path, label, 12, 218) end
        end
        for _, ch in ipairs(rec.choices or {}) do Check(path .. " entry", ch.label, 12, 190) end
      end
      for _, o in ipairs(Stub.regions) do
        if Under(o, panel) then
          local ty, text = rawget(o, "_type"), rawget(o, "_text")
          if ty == "FontString" and type(text) == "string" and text ~= "" then
            local parent = rawget(o, "_parent")
            if rawget(parent, "_type") == "Button" then
              Check("button", text, 12, (rawget(parent, "_width") or 0) - 16)
            elseif rawget(o, "_fontObject") == "GameFontNormal" then
              Check("header", text, 12, 560)
            end
          end
        end
      end
      Stub.ui.CloseSettings()
      T.eq(Stub.errors, {}, code .. ": no Lua error")
    end
    Report(bad, "options texts")
  end)
end)

-- Statistics window (700 px): every column header fits its column, a tab or button
-- text its button, the view name its 300 px, the hint the room right of the tabs, the
-- footers and the title with the exclusions the window.
T.test("widths: the statistics window in every language and theme", function()
  RealWidths(function(Width)
    local bad = {}
    for _, code in ipairs(ALL) do
      for _, key in ipairs({ "actuel", "futuriste", "pixel", "warlock" }) do
        Stub.Reset()
        local ns = StartPlay(key, code, "long")
        ns.Core.SetSetting("exclude.afk", true)
        ns.Core.SetSetting("exclude.inn", true)
        ns.Core.SetSetting("exclude.city", true)
        local function Check(what, fs, limit, text)
          text = text or rawget(fs, "_text")
          if type(text) ~= "string" or text == "" then return end
          local w = FSWidth(Width, fs, text)
          if w > limit then
            bad[#bad + 1] = format("%s %s %s: %q %.0f > %d", key, code, what, text, w, limit)
          end
        end
        local function Views(view)
          for _, tab in ipairs({ "levels", "zones", "sessions" }) do
            ns.Window.Show(tab)
            Stub.Advance(1)
            local tp = rawget(_G, "TruePlayedStatsFrame").tp
            for c, fs in ipairs(tp.header) do
              if fs:IsShown() then Check(view .. " " .. tab .. " header " .. c, fs, (rawget(fs, "_width") or 0) - 1) end
            end
            for id, b in pairs(tp.tabs) do Check("tab " .. id, ButtonText(b), (rawget(b, "_width") or 0) - 8) end
            Check("erase", ButtonText(tp.erase), (rawget(tp.erase, "_width") or 0) - 8)
            Check("view", tp.viewText, 300)
            if tp.hint:IsShown() then Check("hint", tp.hint, 700 - 36 - (12 + 3 * 104) - 8) end
            Check("footer 1", tp.footer1, 700 - 32)
            Check("footer 2", tp.footer2, 700 - 32)
            local title = FSWidth(Width, tp.title)
            local filter = FSWidth(Width, tp.filter)
            if title + 12 + filter > 700 - 14 - 32 then
              bad[#bad + 1] = format("%s %s: title %q + filter %q %.0f > %d", key, code, tostring(rawget(tp.title, "_text")),
                tostring(rawget(tp.filter, "_text")), title + 12 + filter, 700 - 46)
            end
          end
        end
        Views("character")
        ns.Window.SetView("account")
        Views("account")
        ns.Window.Hide()
        if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
      end
    end
    Report(bad, "window texts")
  end)
end)

-- Statistics window, lot 8: with every column in use (deaths, professions, AFK, inn, city,
-- an estimate, the 12-hour clock: the widest values) every visible header and cell text
-- fits its column (the flexible zone column aside: a long zone name may be cut), the
-- columns do not overlap and end inside the window, in every language.
T.test("widths: every column of the statistics window (headers and values), no overlap, every language", function()
  RealWidths(function(Width)
    local bad = {}
    for _, code in ipairs(ALL) do
      Stub.Reset()
      local ns = StartPlay("actuel", code, "activity")
      Stub.GrantXP(Stub.player.max - Stub.player.xp + 10)
      Stub.Advance(2)
      for _, fmt in ipairs({ { "mdy", "12" }, { "auto", "auto" } }) do
        ns.Core.SetSetting("window.dateFmt", fmt[1])
        ns.Core.SetSetting("window.clock", fmt[2])
        for _, view in ipairs({ "current", "account" }) do
          for _, tab in ipairs({ "levels", "zones", "sessions" }) do
            ns.Window.Show(tab, view)
            Stub.Advance(1)
            local f = rawget(_G, "TruePlayedStatsFrame")
            local tp = f.tp
            local lay = tp.layout
            local where = format("%s %s %s %s", code, fmt[2], view, tab)
            local prevEnd = -1
            for c = 1, lay.n do
              local col = lay.cols[c]
              if col.x < prevEnd then bad[#bad + 1] = where .. ": column " .. col.id .. " overlaps" end
              prevEnd = col.x + col.cw
              local hw = FSWidth(Width, tp.header[c])
              if hw > col.cw - 1 then
                bad[#bad + 1] = format("%s header %s: %q %.0f > %d", where, col.id, L_TEXT(tp.header[c]), hw, col.cw - 1)
              end
              if not col.flex then
                for _, row in ipairs(tp.rows) do
                  local fs = row:IsShown() and tp.cells[row][c]
                  if fs and fs:IsShown() and rawget(tp.rows[1], "_parent") then
                    local w = FSWidth(Width, fs)
                    if w > col.cw - 1 then
                      bad[#bad + 1] = format("%s cell %s: %q %.0f > %d", where, col.id, L_TEXT(fs), w, col.cw - 1)
                    end
                  end
                end
              end
            end
            if prevEnd > f:GetWidth() - 50 then bad[#bad + 1] = where .. ": columns end outside the window" end
          end
        end
      end
      ns.Window.Hide()
      if #Stub.errors > 0 then bad[#bad + 1] = code .. ": " .. tostring(Stub.errors[1]) end
    end
    Report(bad, "window columns")
  end)
end)

-- Column help (Window.lua): the columns of every layout (tp.layouts, shown or not), each
-- with its header and header tooltip texts in every language; a tooltip text is short (a
-- few wrapped tooltip lines), and every column header followed by its help icon fits the
-- column's minimum width (the widest that layout can be narrowed to), measured like the
-- headers above.
local LAYOUT_NAMES = { "levels", "account", "zones", "sessions" }
local TIP_MAX = 150            -- characters of a header tooltip text

local function WindowLayouts()
  Stub.Reset()
  local ns = StartIn("enUS")
  ns.Window.Show("levels")
  local tp = rawget(_G, "TruePlayedStatsFrame").tp
  ns.Window.Hide()
  return tp.layouts, tp.iconRoom, OBJECT_SIZE[rawget(tp.header[1], "_fontObject")]
end

T.test("locales: every column of the statistics window has its header tooltip text in every language", function()
  local layouts = WindowLayouts()
  local n, tips = 0, {}
  for _, code in ipairs(ALL) do
    local L = LocaleTable(code)
    for _, name in ipairs(LAYOUT_NAMES) do
      local all = layouts[name].all
      T.ok(#all > 0, name .. ": columns")
      for _, col in ipairs(all) do
        local where = format("%s %s %s", code, name, col.id)
        local tip = L[col.tip]
        T.ok(type(L[col.key]) == "string" and L[col.key] ~= "", where .. ": header text")
        T.ok(type(tip) == "string" and tip ~= "", where .. ": tooltip text " .. col.tip)
        if type(tip) == "string" then
          T.ok(Chars(tip) <= TIP_MAX, format("%s: %d characters, %d at most", where, Chars(tip), TIP_MAX))
        end
        tips[col.tip] = true
        n = n + 1
      end
    end
  end
  T.eq(n, 32 * #ALL, "32 columns in 4 layouts")
  local keys = 0
  for _ in pairs(tips) do keys = keys + 1 end
  T.eq(keys, 26, "tooltip keys (one per meaning)")
  T.eq(#layouts.none.all, 0, "the account view of the Sessions tab has no column")
end)

T.test("widths: every column header and its help icon fit the column in every language", function()
  RealWidths(function(Width)
    local layouts, room, size = WindowLayouts()
    T.eq(size, 10, "headers in GameFontHighlightSmall")
    T.ok(room >= 10, "icon room " .. tostring(room))
    local bad = {}
    for _, code in ipairs(ALL) do
      local L = LocaleTable(code)
      for _, name in ipairs(LAYOUT_NAMES) do
        for _, col in ipairs(layouts[name].all) do
          local w = Width(nil, size, L[col.key]) + room
          if w > col.w - 1 then
            bad[#bad + 1] = format("%s %s %s: %q + icon %.0f > %d", code, name, col.id, L[col.key], w, col.w - 1)
          end
        end
      end
    end
    Report(bad, "headers with their help icon")
  end)
end)

-- FPS / latency graph (240 px plot): the title, each header row (label and the widest
-- min / avg / max text) and the widest readout fit the plot width.
T.test("widths: the graph in every language and theme", function()
  RealWidths(function(Width)
    local bad = {}
    for _, code in ipairs(ALL) do
      for _, key in ipairs(KEYS) do
        Stub.Reset()
        local ns, bar = StartPlay(key, code, "none")
        local L, Fmt = ns.L, ns.Fmt
        ns.Graph.ShowFor(bar)
        Stub.Advance(2)
        local tp = ns.Graph.frame.tp
        local function Need(what, need)
          if need > 240 then bad[#bad + 1] = format("%s %s %s: %.0f > 240", key, code, what, need) end
        end
        for _, w in ipairs({ "GRAPH_WINDOW_30", "GRAPH_WINDOW_60", "GRAPH_WINDOW_300" }) do
          Need("title " .. w, FSWidth(Width, tp.title, format(L.GRAPH_TITLE_FMT, L[w])))
        end
        Need("FPS row", FSWidth(Width, tp.fpsLabel, L.TOKEN_FPS) + 8
          + FSWidth(Width, tp.fpsStats, format(L.GRAPH_MIN_AVG_MAX_FMT, "144", "144", "144")))
        Need("latency row", FSWidth(Width, tp.latLabel, L.TOKEN_LATENCY) + 8
          + FSWidth(Width, tp.latStats, format(L.GRAPH_MIN_AVG_MAX_FMT, "1234", "1234", "1234")))
        Need("readout", FSWidth(Width, tp.readout,
          format(L.GRAPH_AGO_FMT, format(L.GRAPH_AGE_MS_FMT, 4, 59), Fmt.FPS(144), Fmt.Latency(1234))))
        Need("no data", FSWidth(Width, tp.readout, L.GRAPH_NO_DATA))
        ns.Graph.Hide()
        if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
      end
    end
    Report(bad, "graph texts")
  end)
end)
