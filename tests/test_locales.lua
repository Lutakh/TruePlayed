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
  COL_XP = true, COL_XPH = true, COL_INST = true, COL_ZONE = true, COL_CHARS = true,
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
  -- automatic reload: the minutes of its interval slider, as SLIDER_PX_FMT
  SLIDER_MIN_FMT = true,
  -- watched reputation: its tooltip row (standing, numbers, percent), the standings spelled
  -- as in English ("Hostile" in French, "Neutral" in German and Spanish)
  TT_REP_FMT = true, REP_STANDING_2 = true, REP_STANDING_4 = true,
  -- the reputation's detailed tooltip, tokens and picker: a mark, a sign, punctuation and
  -- the short "Rep." of the Romance languages
  TT_REP_CURRENT_FMT = true, TT_REP_GAIN_FMT = true, REP_ETA_FMT = true, OPT_REP_FACTION_FMT = true,
  PFX_REPH_FMT = true,
  -- PvP: the international word (German, Italian, Russian, Korean, Chinese), "Honor"
  -- (Spanish), HK (the players' abbreviation), OK, and the patterns made of numbers and
  -- punctuation only
  TT_SECTION_PVP = true, PVP_LABEL = true, REP_MAIN_PVP = true, OPT_PVP_PAGE = true, TT_PVP_HONOR = true,
  TOKEN_HONOR = true, PVP_STRIP_HONOR = true, PFX_HONOR_FMT = true, PFX_HONOR_ONLY_FMT = true,
  PFX_HONORH_FMT = true, PFX_HK_FMT = true, PVP_ALERT_OK = true, PVP_MAIN_RATE_FMT = true, TT_PVP_OF_FMT = true,
  TT_PVP_WL_FMT = true,
  -- the Levels tab (LevelChart): the "Instances" filter (the French word too), the
  -- "duration · percent" pattern of a bar part and the "<1%" of a share under 1 %
  -- (punctuation only)
  LV_F_INST = true, LV_PART_FMT = true, LV_LT_FMT = true,
  -- its detail sheet (LevelDetail): "<gained> / <size> XP" (numbers and the game's word)
  LD_XP_FMT = true,
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

-- The breakdown rows of the two tooltip blocks have their own labels (block 1: the
-- level's, block 2 and the character section: the total), in every language; the one
-- tooltip of Fill (Broker) shows both, the level's first. Their widths beside the gauge
-- (or the parts) are checked with the tooltip rows below.
T.test("locales: the two breakdown labels (the level's, the total) in every language, Broker's tooltip too", function()
  local fr = { "R\195\169partition du niveau", "R\195\169partition totale" }
  for _, code in ipairs(ALL) do
    local L = LocaleTable(code)
    local lv, tot = L.TT_BREAKDOWN_LEVEL, L.TT_BREAKDOWN_TOTAL
    T.ok(type(lv) == "string" and lv ~= "" and type(tot) == "string" and tot ~= "", code .. ": both labels")
    T.ok(lv ~= tot, code .. ": two different labels")
    T.eq(L.TT_BREAKDOWN, nil, code .. ": no single label left")
    if code == "frFR" then T.eq({ lv, tot }, fr, "frFR: the agreed texts") end
    if code ~= "enUS" then
      local en = LocaleTable("enUS")
      T.ok(lv ~= en.TT_BREAKDOWN_LEVEL and tot ~= en.TT_BREAKDOWN_TOTAL, code .. ": translated")
    end
    -- the one tooltip of Fill (Broker, Shift): the level's label, then the total
    Stub.Reset()
    local ns = StartIn(code, { ui = { ldb = false } })
    Stub.Advance(60)
    local tt = Stub.NewTooltip()
    ns.Tooltip.Fill(tt, true)
    local labels = {}
    for _, l in ipairs(tt._lines) do
      if l[1] == ns.L.TT_BREAKDOWN_LEVEL or l[1] == ns.L.TT_BREAKDOWN_TOTAL then labels[#labels + 1] = l[1] end
    end
    T.eq(labels, { lv, tot }, code .. ": Fill shows the level's breakdown, then the total")
    T.eq(#Stub.errors, 0, code .. ": no Lua error")
  end
end)

-- The detail sheet's stall note (LevelDetail, LD_STALL_FMT): the level's seconds without an
-- XP gain, never to be read as "the player is stuck": no aside in brackets (the old
-- "(stalled)" and its translations, the CJK full-width ones), one duration; the agreed
-- French text.
T.test("locales: the detail sheet's stall note is time without an XP gain, no 'stalled' aside", function()
  for _, code in ipairs(ALL) do
    local s = LocaleTable(code).LD_STALL_FMT
    T.eq(Specs(s), { "%s" }, code .. ": one duration")
    T.no(find(s, "(", 1, true) or find(s, "\239\188\136", 1, true), code .. ": no aside in brackets: " .. s)
  end
  T.eq(LocaleTable("frFR").LD_STALL_FMT, "Dont %s sans gain d'XP.", "frFR: the agreed text")
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
      -- the statistics window's and tooltip's times to the minute (Fmt.DurationFull)
      { L.DUR_D_H_M, { 12, 23, 59 }, 16 },
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
-- "kills" = 8 kills in 4 min (the widest values; on WoW Forever's PvP API, a season
-- running, honor and rank points gained and 12 honorable kills: the PvP tokens show
-- values), "none" = no kill yet, "long" = an hour
-- of kills, "stall" = frozen rate, "cap" = a server level cap, "crash" = an hour lost in
-- a crash and rebuilt (most of the level and of the character).
local function StartPlay(theme, code, play)
  Stub.InstallUI({ ldb = false })
  Stub.theme = theme
  Stub.locale = code
  local p = Stub.player
  p.level, p.xp, p.rest = 20, 10115, 0
  p.max = Stub.xpTable[20] or 23200
  if play == "kills" then
    Stub.SetPvpAPI("forever")
    Stub.SetWeek(2, 5, 3, { quiet = true })
    Stub.pvp.total = 2000
  end
  local ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  ns.Core.SetSetting("widget.locked", true)
  Stub.Advance(1)
  if play == "kills" then
    ns.Core.SetSetting("widget.pvpAuto", true)   -- PvP shown somewhere: its events registered
    Stub.GainHonor(12250)
    Stub.GainRankPoints(450)
    Stub.HK(12)
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
  elseif play == "crash" then
    -- crash review A2: 10 min of kills saved, then an hour the save never got (a crash),
    -- rebuilt from the login /played: the rebuilt sub-lines under "This level" and
    -- "Played", and the "mostly rebuilt" notes under both breakdowns
    for _ = 1, 10 do Stub.Advance(60); Stub.Kill(171) end
    Stub.Logout()
    Stub.Reset({ keepWorld = true })      -- drops the UI stubs: installed again below
    Stub.Advance(3600)
    Stub.InstallUI({ ldb = false })
    _G.TruePlayedDB = Stub.DeepCopy(Stub.saved)
    ns = Stub.LoadAddon()
    Stub.LoginSequence({ settle = 15 })   -- the login /played request (+10 s)
  end
  Stub.Advance(2)
  return ns, ns.Bar.frame
end

-- The shown blocks of the private tooltip: block 1, and block 2 while Shift is held.
local function Shown(ns)
  local TF = ns.TooltipFrame
  local out = { TF.frame }
  if TF.frame2 and TF.frame2:IsShown() then out[2] = TF.frame2 end
  return out
end

-- Rows of the shown private tooltip (both blocks) that are outputs of the format `fmt`
-- (its %s / %d matched lazily): the crash play checks that its notes are drawn, hence
-- measured.
local function RowsOf(ns, fmt)
  local p = fmt:gsub("%%[sd]", "@@@"):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"):gsub("@@@", ".-")
  local n = 0
  for _, tf in ipairs(Shown(ns)) do
    for i = 1, tf.tp.n do
      local row = tf.tp.rows[i]
      if row.left:IsShown() and tostring(row.left:GetText()):find("^" .. p .. "$") then n = n + 1 end
    end
  end
  return n
end

-- Rows of the shown private tooltip (both blocks) that do not fit
-- (tests/test_round4_regress.lua).
local function CutRows(ns)
  local tt = ns.Themes.Active().tt
  local out = {}
  for b, tf in ipairs(Shown(ns)) do
    local inner = tf:GetWidth() - tt.pad[1] - tt.pad[2]
    for i = 1, tf.tp.n do
      local row = tf.tp.rows[i]
      if not row.wrap and row.left:IsShown() then
        local lw = row.left:GetUnboundedStringWidth()
        local need = lw
        if row.right:IsShown() and row.kind ~= "title" then
          need = lw + tt.gap + row.right:GetUnboundedStringWidth()
        elseif row.kind == "gauge" then
          need = lw + tt.gap + tt.gauge.w + 1           -- the label clear of its gauge
        end
        if (rawget(row.left, "_width") or 0) > 0 or need > inner + 0.5 then
          out[#out + 1] = format("block %d: %q %.0f > %.0f", b, tostring(row.left:GetText()), need, inner)
        end
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
          for _, play in ipairs({ "kills", "none", "long", "stall", "cap", "activity", "crash" }) do
            Stub.Reset()
            local ns, frame = StartPlay(key, code, play)
            for _, shift in ipairs({ false, true }) do
              Stub.SetShift(shift)
              ns.Tooltip.ShowFor(frame)
              Stub.Advance(1)
              for _, s in ipairs(CutRows(ns)) do
                bad[#bad + 1] = format("%s %s %s %s: %s", key, code, play, shift and "Shift" or "short", s)
              end
              if play == "crash" then
                local L, want = ns.L, shift and 2 or 1
                if RowsOf(ns, L.TT_EST_FMT) ~= want or RowsOf(ns, L.TT_EST_MOST_FMT) ~= want then
                  bad[#bad + 1] = format("%s %s crash %s: the rebuilt notes are missing", key, code,
                                         shift and "Shift" or "short")
                end
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

-- The reputation's detailed tooltip (Tooltip.FillRep, shown over the strip or the main
-- track): no row cut in any theme or language, without a rate, with one, frozen (its
-- notes), at Exalted and with the chosen faction unreadable (the fallback note).
T.test("widths: no row of the reputation tooltip is cut (every theme and language, every state)", function()
  RealWidths(function()
    local bad = {}
    for _, key in ipairs(KEYS) do
      if key ~= "actuel" then
        for _, code in ipairs(ALL) do
          Stub.Reset()
          local ns = StartPlay(key, code, "none")
          Stub.SetFactions(Stub.REP_TREE())
          Stub.WatchFaction({ name = "Darnassus", factionID = 69, reaction = 5, min = 3000, max = 9000, value = 4200 })
          local hit = ns.Bar.frame.tp.repHit
          local function Check(state)
            Stub.RunScript(hit, "OnEnter")
            Stub.Advance(1)
            if not ns.Tooltip.IsShownFor(hit) then bad[#bad + 1] = format("%s %s %s: not shown", key, code, state) end
            for _, s in ipairs(CutRows(ns)) do bad[#bad + 1] = format("%s %s %s: %s", key, code, state, s) end
            Stub.RunScript(hit, "OnLeave")
          end
          Check("no rate")
          for _ = 1, 12 do Stub.Advance(60); Stub.GainRep(50) end
          Check("rate")
          Stub.Advance(ns.C.XP_STALL + 60)
          Check("frozen")
          Stub.GainRep(40000)
          Check("exalted")
          ns.Rep.SetChosen(529)
          Stub.rep.missing[529] = true
          Stub.Fire("UPDATE_FACTION")
          Check("fallback")
          if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
        end
      end
    end
    Report(bad, "cut reputation tooltip rows")
  end)
end)

-- The PvP detailed tooltip (Tooltip.FillPvp, shown over the PvP strip or the main track in
-- the PvP mode): no row cut in any theme or language, before any rate, with rates in a
-- battleground (one in progress), paused after it (its note, one battleground played), at
-- the honor cap and the week's cap (blocked until the reset), at the max rank, without a
-- season.
T.test("widths: no row of the PvP tooltip is cut (every theme and language, every state)", function()
  RealWidths(function()
    local bad = {}
    for _, key in ipairs(KEYS) do
      if key ~= "actuel" then
        for _, code in ipairs(ALL) do
          Stub.Reset()
          Stub.SetPvpAPI("forever")
          Stub.SetWeek(2, 3, 1, { quiet = true })
          Stub.pvp.total = 2000
          local ns = StartPlay(key, code, "none")
          ns.Core.SetSetting("widget.pvp", "rank")
          ns.Core.SetSetting("pvp.capAlert", false)
          Stub.pvp.seasonEnd = 86400 * 40
          local hit = ns.Bar.frame.tp.pvpHit
          local function Check(state)
            Stub.RunScript(hit, "OnEnter")
            Stub.Advance(1)
            if not ns.Tooltip.IsShownFor(hit) then bad[#bad + 1] = format("%s %s %s: not shown", key, code, state) end
            for _, s in ipairs(CutRows(ns)) do bad[#bad + 1] = format("%s %s %s: %s", key, code, state, s) end
            Stub.RunScript(hit, "OnLeave")
          end
          Check("no rate")
          Stub.EnterBG()
          for _ = 1, 12 do
            Stub.Advance(60)
            Stub.GainHonor(1234)
            Stub.GainRankPoints(20)
            Stub.HK(3)
          end
          Check("battleground")
          Stub.MatchComplete(0, 1500)
          Stub.LeaveBG()
          Stub.Advance(ns.C.PVP_IDLE + 60)
          Check("paused")
          Stub.GainHonor(30000)
          Stub.GainRankPoints(5000)
          Stub.pvp.hkHigh = 18
          Check("capped")
          Stub.SetWeek(10, 14, 13)
          Stub.GainRankPoints(30000)
          Check("max rank")
          Stub.SetWeek(-1, 0, 0, { quiet = true })
          Stub.pvp.total = 0
          Stub.Fire("UPDATE_FACTION")
          ns.Core.SetSetting("widget.pvp", "honor")
          Check("no season")
          if #Stub.errors > 0 then bad[#bad + 1] = key .. " " .. code .. ": " .. tostring(Stub.errors[1]) end
        end
      end
    end
    Report(bad, "cut PvP tooltip rows")
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
      -- the level's times to the minute (12d 23h 59m), the server's estimated
      { L.TT_THIS_LEVEL, Fmt.DurationFull(12 * 86400 + 86399) },
      { L.TT_THIS_LEVEL_SERVER, ns.Tokens.Approx(Fmt.DurationFull(12 * 86400 + 86399)) },
    }
    -- the level's XP row: its parts two a line on continuation rows (a blank label), any
    -- two of them (three parts: monsters and quests, then the rested bonus alone)
    local xpParts = { format(L.BD_PART_FMT, L.LD_XP_MOBS, Fmt.Percent(0.33, 0)),
      format(L.BD_PART_FMT, L.LD_XP_QUESTS, Fmt.Percent(0.33, 0)),
      format(L.BD_PART_FMT, L.LD_XP_RESTED, Fmt.Percent(0.34, 0)) }
    for a = 1, 2 do
      for b = a + 1, 3 do rows[#rows + 1] = { " ", xpParts[a] .. L.SEP .. xpParts[b] } end
    end
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
      Stub.SetPvpAPI("forever")                   -- the PvP page's controls and tokens
      local ns = StartIn(code, { ui = { modern = true } })
      ns.Options.Open()
      local GAME = nil
      local function Check(what, text, size, limit)
        local w = Width(GAME, size, text)
        if w > limit then bad[#bad + 1] = format("%s %s: %q %.0f > %d", code, what, text, w, limit) end
      end
      -- the main page, then the Reputation page (a subcategory; its faction picker shows
      -- the game's names, only its "automatic" entry is ours), then the PvP page
      local sub = Stub.ui.subcategories[1]
      T.ok(sub ~= nil, code .. ": the Reputation page")
      T.ok(Stub.ui.subcategories[2] ~= nil, code .. ": the PvP page")
      Check("rep.faction entry", ns.L.OPT_REP_FACTION_AUTO, 12, 190)
      for page = 1, 3 do
        local cat = page == 1 and Stub.ui.categories[1] or Stub.ui.subcategories[page - 1]
        if page >= 2 then Settings.OpenToCategory(cat.ID) end
        local panel = cat.frame
        local controls = rawget(panel, "controls")
        T.ok(type(controls) == "table", code .. ": page " .. page .. " built")
        for path, rec in pairs(controls) do
          local label = rec.label and rawget(rec.label, "_text")
          if label then
            -- a checkbox followed by a help icon leaves it rec.helpRoom
            if rec.kind == "check" then Check(path, label, 12, 520 - (rec.helpRoom or 0)) else Check(path, label, 12, 218) end
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

-- The Levels chart (LevelChart.lua) at its minimum size (1040 x 640; and 1004 x 640 on a
-- 4:3 screen, the default and the pixel themes), in every language and theme, with the
-- widest values its texts can take (formatted here: 125d 23h, 12d 23h, 9h 59m, level 59 /
-- 60, 100 %, a 12-hour date): every chip text fits its chip (a sub line as the module shows it for the widest values of another character at level 60: in full,
-- else with its durations by their largest unit, LevelChart SubFit, which measures the
-- unbounded width; FM.Install bounds GetStringWidth as the client does), the filter
-- pills take two rows at most and each fits beside the hide-upcoming toggle, every chart
-- title fits with the summary on its row, the axis labels fit the axis room, the average
-- label half the plot, the strip's title with its share and its legend fit the strip, the
-- detail sheet's texts fit their places (LevelDetail.lua: title and status, the figure
-- cards' label / value / sub within a card, each section's title with its right text, a
-- breakdown row's label (the PvP row with its hover hint) left of its value column, the
-- value and percent columns, the XP columns, the zone times, the upcoming level's box and
-- lines: a level's widest durations are 2d 23h and 9h 59m, 2d 23h 59m and 23h 59m to the
-- minute (Fmt.DurationFull: every measured one), the total since level 1 and the time
-- until a level is reached the chart's), and no row of the bar, PvP chip or
-- detail PvP row tooltips is cut (the private tooltip; the classic GameTooltip grows;
-- wrapped notes and the no-record line wrap). The Levels hint
-- (332 px) is checked by "widths: the statistics window" above (the chart is the Levels
-- tab of a character).
T.test("widths: the Levels chart (chips, filters, titles, axis, strip, detail, tooltips) in every language and theme", function()
  RealWidths(function(Width)
    local bad = {}
    -- every theme on a 16:9 screen (the 1040 x 640 minimum), the default and the widest
    -- font (pixel) on a 4:3 screen at UI scale 1 (UIParent 1024 x 768: a 1004 px window,
    -- LevelChart.MinSize; the chart column 74 px narrower)
    local RUNS = { { "actuel" }, { "futuriste" }, { "pixel" }, { "warlock" }, { "actuel", 1024 }, { "pixel", 1024 } }
    for _, code in ipairs(ALL) do
      for _, run in ipairs(RUNS) do
        local key, screenW = run[1], run[2]
        Stub.Reset()
        local ns = StartPlay(key, code, "activity")
        ns.Core.SetSetting("window.dateFmt", "mdy")
        ns.Core.SetSetting("window.clock", "12")
        if screenW then UIParent:SetSize(screenW, 768) end
        ns.Window.Show("levels")
        Stub.Advance(1)
        local L, Fmt = ns.L, ns.Fmt
        local tp = rawget(_G, "TruePlayedStatsFrame").tp
        local ch = tp.chart
        local geo = ch.geo
        local where = key .. " " .. code .. (screenW and " 4:3" or "")
        if screenW then T.eq(rawget(_G, "TruePlayedStatsFrame"):GetWidth(), screenW - 20, where .. ": the window") end
        -- the widest of `texts` in the font of fs must fit `limit`
        local function Widest(fs, texts)
          local w, which = 0, ""
          for _, s in ipairs(texts) do
            local x = FSWidth(Width, fs, s)
            if x > w then w, which = x, s end
          end
          return w, which
        end
        local function Need(what, need, limit, text)
          if need > limit then bad[#bad + 1] = format("%s %s: %q %.0f > %d", where, what, tostring(text), need, limit) end
        end
        local function Fits(what, fs, limit, texts)
          local w, which = Widest(fs, texts)
          Need(what, w, limit, which)
        end
        -- formats of one wide duration (D; F: a measured one, to the minute) or a pair of them
        local SECS = { 125 * 86400 + 23 * 3600, 12 * 86400 + 23 * 3600, 9 * 3600 + 59 * 60 }
        local D, F = {}, {}
        for i, v in ipairs(SECS) do D[i] = Fmt.Duration(v) end
        for i, v in ipairs({ 125 * 86400 + 23 * 3600 + 59 * 60, 12 * 86400 + 23 * 3600 + 59 * 60, 23 * 3600 + 59 * 60 }) do
          F[i] = Fmt.DurationFull(v)
        end
        local function Over(list, fmt, args)
          local out = {}
          for _, d in ipairs(list) do
            local a = {}
            for i, v in ipairs(args) do a[i] = (v == "D") and d or v end
            out[#out + 1] = format(fmt, (unpack or table.unpack)(a))
          end
          return out
        end
        local function With(fmt, ...) return Over(D, fmt, { ... }) end
        local function WithF(fmt, ...) return Over(F, fmt, { ... }) end
        -- the chips' label, value and fixed sub lines (the duration sub lines: below)
        local inner = geo.chipW - 16
        local serverSub = { L.LV_SERVER_SUB, Fmt.Ago(7200), Fmt.Ago(86400 * 45) }
        local texts = {
          { { L.LV_PLAYED }, F, { format(L.LV_PLAYED_SUB_FMT, 59), L.LV_PLAYED_SUB_ONE } },
          { { L.TT_SERVER }, F, serverSub },
          { { L.LV_AVG }, F, {} },
          { { L.BD_PVP }, F, {} },
          { { L.LV_FLIGHT }, F, { format(L.LV_FLIGHT_SUB_FMT, Fmt.Percent(0.123)),
            format(L.LV_FLIGHT_SUB_FMT, format(L.LV_LT_FMT, Fmt.Percent(0.01))) } },
          { { L.TT_DEATHS }, { Fmt.Number(1234) }, {} },
          { { format(L.LV_TOP_IN_FMT, 60), L.MAX_LEVEL, L.CAP_SHORT, L.LV_XP_OFF },
            { Fmt.ETA(SECS[1]), Fmt.ETA(SECS[2]), Fmt.ETA(SECS[1]) .. "+", "60", format(L.LV_CAP_LEVEL_FMT, 60) },
            { L.LV_TOP_SUB } },
        }
        for i = 1, 7 do
          local c = ch.chips[i]
          T.eq(rawget(c.label, "_width"), inner, "chip text width")
          Fits("chip " .. i .. " label", c.label, inner, texts[i][1])
          Fits("chip " .. i .. " value", c.value, inner, texts[i][2])
          Fits("chip " .. i .. " sub", c.sub, inner, texts[i][3])
        end
        -- filter pills and the toggle
        if geo.pillRows > 2 then bad[#bad + 1] = format("%s: %d rows of filter pills", where, geo.pillRows) end
        local tw = rawget(ch.toggle, "_width") or 0
        for f, p in ipairs(ch.filters) do
          Need("pill " .. f .. " beside the toggle", (rawget(p.btn, "_width") or 0) + 10 + tw, geo.colW,
            rawget(p.fs, "_text"))
        end
        -- every chart title with the summary on its row
        local titles = { "LV_T_ALL", "LV_T_WORLD", "LV_T_INST", "LV_T_PVP", "LV_T_FLIGHT", "LV_T_PROF", "LV_T_DEAD" }
        for f, tkey in ipairs(titles) do
          local sums = WithF(f == 1 and L.LV_SUM_FMT or L.LV_SUM_FILTER_FMT, "D", 59)
          sums[#sums + 1] = L.LV_SUM_NONE                     -- no level to count
          for _, s in ipairs(WithF(L.LD_TOTAL_FMT, "D")) do sums[#sums + 1] = s end   -- seconds alone
          local sw, stext = Widest(ch.summary, sums)
          Need("title " .. tkey .. " + summary", FSWidth(Width, ch.title, L[tkey]) + 12 + sw, geo.colW,
            L[tkey] .. " | " .. stext)
        end
        -- the axis labels (LevelChart AxisText: whole days, whole hours, else a duration; its
        -- steps to 10 days, then 20, 50... days) left of the plot, the average label
        local labels = {}
        for _, step in ipairs({ 600, 1800, 3600, 7200, 14400, 28800, 86400, 172800, 432000, 864000, 1728000,
                                4320000, 8640000, 17280000, 43200000, 86400000 }) do
          for j = 1, 5 do
            local v = step * j
            if v % 86400 == 0 then
              labels[#labels + 1] = format(L.LV_DAYS_FMT, math.floor(v / 86400))
            elseif v % 3600 == 0 then
              labels[#labels + 1] = format(L.DUR_H, math.floor(v / 3600))
            else
              labels[#labels + 1] = Fmt.Duration(v)
            end
          end
        end
        Fits("axis label", ch.grid[1].label, rawget(ch.plot, "_points")[1].x - 6, labels)
        Fits("average label", ch.avg.label, math.floor(geo.plotW / 2), WithF(L.LV_AVG_FMT, "D"))
        -- the strip: its title (the prefix, the two range pickers at their widest number with
        -- their padding, the arrow between them: "Progress: level [59] » [60]") and share on
        -- one row, its legend on one row
        local st = ch.strip
        local sW = (rawget(st.frame, "_width") or 0) - 20
        local shareW, shareT = Widest(st.share, { format(L.LV_SHARE_FMT, 100, 100), format(L.LV_XP_SHARE_FMT, 100),
          L.TT_MAX_LEVEL, format(L.LV_CAP_FMT, 60), format(L.LV_XP_OFF_FMT, 60),
          format(L.LV_RANGE_REACHED_FMT, Fmt.PercentInt(100), 60) })
        local nums = {}
        for n = 1, 60 do nums[n] = tostring(n) end
        local pick = math.max(16, math.ceil(Widest(st.pickFS[1], nums)) + 10)
        T.eq(rawget(st.picks[2], "_width"), math.max(16, math.ceil(FSWidth(Width, st.pickFS[2], "60")) + 10),
          where .. ": the picker's width")
        local titleW = FSWidth(Width, st.title, L.LV_RANGE_TITLE) + 4 + pick + 3 + FSWidth(Width, st.arrow, "\194\187")
          + 3 + pick
        Need("strip title + pickers + share", titleW + 20 + shareW, sW, L.LV_RANGE_TITLE .. " [59] [60] | " .. shareT)
        local lefts = {}                                     -- the chip's ETA text, "+" when partial
        for i, v in ipairs(SECS) do lefts[i] = format(L.LV_LEFT_FMT, Fmt.ETA(v) .. "+") end
        local w3, t3 = Widest(st.fs3, lefts)
        -- a range ahead: its estimated time alone ("+": levels without an XP size in it)
        local ahead = {}
        for i, v in ipairs(SECS) do ahead[i] = format(L.LV_UPCOMING_FMT, Fmt.ETA(v) .. "+") end
        Fits("strip: a range ahead", st.fs3, sW - 12, ahead)
        -- the legend to the minute, else (LevelChart FitLegend) without the minutes past 10 h;
        -- its complete levels from level 1 or from a later one (a range: "Level 10 » 59")
        local function Legend(fmtOf)
          local done = fmtOf(L.LV_DONE_SPAN_FMT, 1, 59, "D")
          for _, t in ipairs(fmtOf(L.LV_DONE_SPAN_FMT, 10, 59, "D")) do done[#done + 1] = t end
          local w1, t1 = Widest(st.fs1, done)
          local w2, t2 = Widest(st.fs2, fmtOf(L.LV_CUR_FMT, 59, "D"))
          return 3 * (8 + 4) + w1 + 14 + w2 + 14 + w3, t1 .. " | " .. t2 .. " | " .. t3
        end
        local lw, lt = Legend(WithF)
        if lw > sW then lw, lt = Legend(With) end
        Need("strip legend", lw, sW, lt)
        -- the detail sheet: its title and status
        local hit = ch.cols[ch.state.level].hit
        hit:GetScript("OnClick")(hit, "LeftButton")
        local det = tp.detail
        local dW = det.width - 28 - 24
        Fits("detail title", det.title, dW, { format(L.LEVEL_SPAN_FMT, 59, 60) })
        Fits("detail status", det.status, dW, { format(L.LD_DONE_FMT, Fmt.DateTime(1798718400 + 86340)),
          format(L.LD_CUR_FMT, Fmt.Percent(0.999)), L.LD_UPCOMING, L.LD_NODATA })
        -- the detail sheet's sections (inner width 348 px, cards of 170 px with 8 px each side)
        local IW, CARD_IN = 348, 170 - 16
        local DL = { Fmt.Duration(2 * 86400 + 23 * 3600), Fmt.Duration(9 * 3600 + 59 * 60) }
        local FL = { Fmt.DurationFull(2 * 86400 + 23 * 3600 + 59 * 60), Fmt.DurationFull(23 * 3600 + 59 * 60) }
        local function WithL(fmt, list)
          local out = {}
          for i, d in ipairs(list or DL) do out[i] = format(fmt, d) end
          return out
        end
        local cards = det.cards
        Fits("detail card label", cards.played.label, CARD_IN,
          { L.LV_PLAYED, L.TT_SERVER, L.LD_ETA, L.LD_ETA_CUR, L.LD_CUM, L.TT_XPH, L.TT_DEATHS })
        local values = { L.DOTS, Fmt.Rate(250000), Fmt.Number(1234), Fmt.ETA(SECS[1]), Fmt.ETA(SECS[2]) }
        for _, d in ipairs(D) do values[#values + 1] = d end          -- Estimated at start
        for _, d in ipairs(F) do values[#values + 1] = "~" .. d end   -- Played, Server /played, Total
        Fits("detail card value", cards.played.value, CARD_IN, values)
        local subs = { format(L.TT_EXCL_FMT, ns.Stats.MaskLabel(7)), L.LV_SERVER_SUB, format(L.LD_CUM_SUB_FMT, 60),
                       format(L.LD_CUM_SUB_CUR_FMT, 60), L.LD_NONE }
        for _, f in ipairs({ L.LD_MORE_FMT, L.LD_LESS_FMT, L.LD_LEFT_FMT }) do
          for _, t in ipairs(WithL(f)) do subs[#subs + 1] = t end
        end
        for _, t in ipairs(WithL(L.LV_DEAD_SUB_FMT, FL)) do subs[#subs + 1] = t end
        Fits("detail card sub", cards.played.sub, CARD_IN, subs)
        local tm, dxp = det.time, det.xp
        local function Head(what, sec, head, rights)
          local rw, rt = Widest(sec.right, rights)
          Need(what, FSWidth(Width, sec.title, head) + 12 + rw, IW, head .. " | " .. tostring(rt))
        end
        Head("detail time title", tm, L.LD_TIME, WithL(L.LD_TOTAL_FMT, FL))
        Head("detail XP title", dxp, L.LD_XP, { format(L.LD_XP_FMT, Fmt.Number(999999), Fmt.Number(999999)) })
        Fits("detail zones title", det.zonesTitle, IW, { L.LD_ZONES })
        Fits("detail no zone", det.zonesEmpty, IW, { L.ROW_ZONES_EMPTY })
        local row = tm.rows[1]
        for _, k in ipairs({ "BD_WORLD", "BD_DUNGEON", "BD_RAID", "BD_PVP", "LV_FLIGHT", "TT_PROF", "BD_DEAD", "BD_CITY",
                             "BD_INN", "BD_AFK", "TT_UNTRACKED" }) do
          local w = FSWidth(Width, row.label, L[k])
          if k == "BD_PVP" then w = w + 4 + FSWidth(Width, row.hint, L.LD_HOVER) end
          Need("detail row label", w, 244 - 28 - 4, L[k])        -- the value column starts at 244
        end
        -- a value column (LevelDetail DurFit): the minutes when they fit, else without them
        local FLS = { 2 * 86400 + 23 * 3600 + 59 * 60, 23 * 3600 + 59 * 60 }
        local function FitsDur(what, fs)
          for _, v in ipairs(FLS) do
            local t = Fmt.DurationFull(v)
            if FSWidth(Width, fs, t) > 64 then t = Fmt.Duration(v) end
            Need(what, FSWidth(Width, fs, t), 64, t)
          end
        end
        FitsDur("detail row value", row.value)
        Fits("detail row percent", row.pct, 52, { Fmt.Percent(0.999), Fmt.Percent(0.123),
          format(L.LV_LT_FMT, Fmt.PercentInt(1)) })                -- a share that rounds to 0
        local xcol = math.floor((IW - 16) / 3)
        local col = dxp.cols[1]
        Fits("detail XP label", col.label, xcol - 12, { L.LD_XP_MOBS, L.LD_XP_QUESTS, L.LD_XP_RESTED })
        Fits("detail XP value", col.value, xcol, { Fmt.Number(999999) })
        Fits("detail XP percent", col.pct, xcol, { Fmt.Percent(0.999) })
        if det.zones[1] then FitsDur("detail zone time", det.zones[1].time) end
        hit = ch.cols[ch.state.level + 1].hit
        hit:GetScript("OnClick")(hit, "LeftButton")
        local up = det.up
        T.ok(up.frame ~= nil, where .. ": the upcoming level's sheet")
        if up.frame then
          Fits("detail estimate label", up.label, IW - 20, { L.LD_EST_DUR })
          Fits("detail estimate value", up.value, IW - 20, { Fmt.ETA(SECS[2]), Fmt.ETA(SECS[3]), L.DOTS })
          Fits("detail estimate sub", up.sub, IW - 20, { L.LD_EST_SUB, L.LD_EST_SUB_RATE })   -- recent / rate
          Fits("detail XP to earn", up.xp, IW, { format(L.LV_XP_EARN_FMT, Fmt.Number(999999)) })
          Fits("detail reached in", up.reach, IW, With(L.LD_REACH_FMT, "D"))
        end
        -- the tooltips of the chart (the private tooltip of the non-classic themes)
        if key ~= "actuel" then
          local function Hover(what, frame)
            frame:GetScript("OnEnter")(frame)
            for _, s in ipairs(CutRows(ns)) do bad[#bad + 1] = format("%s %s: %s", where, what, s) end
            frame:GetScript("OnLeave")(frame)
          end
          for _, k in ipairs({ ch.state.level, ch.state.level + 1, 5 }) do Hover("bar " .. k, ch.cols[k].hit) end
          -- the range pickers' tooltips, with the game's menus and without (the cycle hint)
          Hover("range picker", ch.strip.picks[1])
          local mu = rawget(_G, "MenuUtil")
          rawset(_G, "MenuUtil", nil)
          Hover("range picker (no menu)", ch.strip.picks[2])
          rawset(_G, "MenuUtil", mu)
          ch.filters[4].btn:Click("LeftButton")
          Hover("bar (PvP filter)", ch.cols[ch.state.level].hit)
          Hover("PvP chip", ch.chips[4].frame)
          -- the detail sheet's PvP row (a battleground and world PvP at the current level)
          local lb = ns.char.levels[ch.state.level]
          lb.s.p = (lb.s.p or 0) + 9 * 3600 + 59 * 60
          lb.pw = 3600
          lb.z = lb.z or {}
          lb.z.i489 = { s = { p = 9 * 3600 + 59 * 60 } }
          ns.char.zones.i489 = { s = { p = 9 * 3600 + 59 * 60 }, name = ns.Stats.ZoneName("i489", nil) }
          ch.filters[1].btn:Click("LeftButton")
          hit = ch.cols[ch.state.level].hit
          hit:GetScript("OnClick")(hit, "LeftButton")
          T.ok(det.pvpHit ~= nil and det.pvpHit:IsShown(), where .. ": the PvP row")
          if det.pvpHit then Hover("detail PvP row", det.pvpHit) end
        end
        -- the chips' duration sub lines as LevelChart shows them (review chartrt-1: read, not
        -- recomputed), for the widest values: another character at level 60 (its time at the
        -- max level), its last five levels (the recent average), battlegrounds, world PvP
        -- (measured: the PvP API on for this pass) and dead time
        local alt = Stub.DeepCopy(ns.char)
        alt.guid, alt.name, alt.level, alt.levels, alt.zones = "Player-4619-0A1D1DE0", "Wide", 60, {}, {}
        alt.pvp = { w0 = 1700000000 }
        ns.db.chars[alt.guid] = alt
        Stub.SetPvpAPI("forever")
        for _, a in ipairs(SECS) do
          for _, b in ipairs(SECS) do
            for l = 55, 60 do alt.levels[l] = { s = { w = a }, d = 0, xp = 0 } end
            alt.life = { s = { w = 6 * a + b, p = a, x = a }, pw = b, d = 3 }
            ns.Window.Show("levels", alt.guid)
            T.eq(ch.state.char, alt)
            for _, i in ipairs({ 3, 4, 6, 7 }) do
              local sub = ch.chips[i].sub
              Need("chip " .. i .. " sub", FSWidth(Width, sub), inner, rawget(sub, "_text"))
            end
          end
        end
        Stub.SetPvpAPI("none")
        ns.Window.Hide()
        if #Stub.errors > 0 then bad[#bad + 1] = where .. ": " .. tostring(Stub.errors[1]) end
      end
    end
    Report(bad, "Levels chart texts")
  end)
end)

-- Statistics window, lot 8: with every column in use (deaths, professions, AFK, the
-- 12-hour clock: the widest values) every visible header and cell text fits its column (the
-- flexible zone column aside: a long zone name may be cut), the columns do not overlap and
-- end inside the window, in every language. The Levels tab of a character is the chart: no
-- column (its layout's n is 0; its texts: "widths: the Levels chart..." above); the view is
-- still opened in every language and clock (no Lua error).
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
            if view == "current" and tab == "levels" then
              T.eq({ lay == tp.layouts.chart, lay.n }, { true, 0 }, where .. ": the chart, no column")
            end
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
-- headers above. The Levels tab rework removed the Levels table of a character
-- (LAYOUTS.levels, 14 columns and 9 tooltip keys of its own: the chart has no column; its
-- width tests are "widths: the Levels chart..." below): 18 columns in 3 layouts, 17 keys.
local LAYOUT_NAMES = { "account", "zones", "sessions" }
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
  T.eq(n, 18 * #ALL, "18 columns in 3 layouts")
  local keys = 0
  for _ in pairs(tips) do keys = keys + 1 end
  T.eq(keys, 17, "tooltip keys (one per meaning)")
  T.eq(#layouts.none.all, 0, "the account view of the Sessions tab has no column")
  T.eq(#layouts.chart.all, 0, "the Levels tab of a character (the chart) has no column")
  T.eq(layouts.levels, nil, "no Levels table of a character any more")
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
