-- tests/check_media.lua - standalone checks of the theme media (design/SPEC-themes.md 2.6,
-- 6.1, 6.2, 8.3). Usage (from anywhere): lua tests/check_media.lua [-v]
-- Runs on Lua 5.1 and 5.5 (string.byte parsing only). Exit code 0 = OK, 1 = at least one FAIL.
--
-- Checks:
--   * fonts: every Themes.FONTS file and its Media/Fonts/LICENSES/<Family>-OFL.txt exist;
--     the `cyr` flag equals the real coverage of U+0410-U+044F (TTF cmap formats 4 and 12);
--   * glyph coverage per theme, after the font's `subst`:
--       - body and num fonts: BODY_SET (U+0020-U+007E, U+00A0, U+00AB, U+00B7, U+00BB,
--         U+00C0-U+00FF minus U+00D7 and U+00F7) plus every character of Locales/enUS.lua and
--         Locales/frFR.lua (file text and string values);
--       - display fonts: the texts of Themes.DISPLAY_KEYS in both locales (format specifiers
--         and colour codes removed), plus "0123456789%.,:/-()~ " and U+00A0;
--   * TGA files (6.2): uncompressed type 2, no colour map, 32 bpp, descriptor 0x08, straight
--     alpha (judged on grey media), power-of-two sizes up to 256 equal to the declared { w, h }, R = G = B for
--     grey media; every declared media exists, no undeclared .tga, lowercase [a-z0-9_]
--     names, at most 96 KiB per folder, a media-src/<key>/<name>.svg source for every .tga,
--     no black transparent texel next to bright art (colour bleed, tools/svg2tga.py);
--     Media/Themes holds only theme folders and common/.

local VERBOSE = false
for i = 1, (arg and #arg or 0) do
  if arg[i] == "-v" then VERBOSE = true end
end

local errors, warnings = 0, 0

local function fail(fmt, ...)
  errors = errors + 1
  print("FAIL  " .. string.format(fmt, ...))
end

local function warn(fmt, ...)
  warnings = warnings + 1
  print("WARN  " .. string.format(fmt, ...))
end

local function detectRoot()
  local a0 = (arg and arg[0]) or ""
  a0 = string.gsub(a0, "\\", "/")
  local base = string.match(a0, "^(.-)tests/[^/]+%.lua$")
  if base then
    if base == "" then return "./" end
    return base
  end
  local dir = string.match(a0, "^(.*/)[^/]*$")
  return (dir or "./") .. "../"
end

local ROOT = detectRoot()

local function shellQuote(s)
  return "'" .. (string.gsub(s, "'", "'\\''")) .. "'"
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

-- Names in a directory (hidden entries skipped), sorted; nil when it cannot be listed.
local function listDir(dir)
  if not io.popen then return nil end
  local ok, h = pcall(io.popen, "ls -1A " .. shellQuote(dir) .. " 2>/dev/null")
  if not ok or not h then return nil end
  local names = {}
  for line in h:lines() do
    if line ~= "" and line:sub(1, 1) ~= "." then names[#names + 1] = line end
  end
  h:close()
  table.sort(names)
  return names
end

---------------------------------------------------------------------------
-- Addon data: Themes.FONTS / DISPLAY_KEYS / COMMON_MEDIA, theme sources, locales
---------------------------------------------------------------------------
local Stub = dofile(ROOT .. "tests/wowstub.lua")
Stub.ROOT = ROOT

local BASE = { "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Themes.lua" }

local function tocThemeFiles()
  local list = {}
  local toc = readFile(ROOT .. "TruePlayed_Camelot.toc") or ""
  for raw in (toc .. "\n"):gmatch("([^\n]*)\n") do
    local key = raw:gsub("\r$", ""):match("^%s*Themes\\([%w_]+)%.lua%s*$")
    if key then list[#list + 1] = key end
  end
  return list
end

Stub.Reset()
Stub.theme = nil
local ns = Stub.LoadAddon({ files = BASE })
local Themes = ns.Themes
local sources = {}
do
  local register = Themes.Register
  Themes.Register = function(key, builder)
    register(key, builder)
    local ok, src = pcall(builder)
    if ok and type(src) == "table" then sources[key] = src
    else fail("theme %s: builder failed: %s", tostring(key), tostring(src)) end
  end
  for _, key in ipairs(tocThemeFiles()) do
    local path = ROOT .. "Themes/" .. key .. ".lua"
    if exists(path) then
      local chunk, err = loadfile(path)
      if not chunk then fail("%s", tostring(err))
      else
        local ok, err2 = pcall(chunk, "TruePlayed", ns)
        if not ok then fail("Themes/%s.lua: %s", key, tostring(err2)) end
      end
    else
      fail("Themes/%s.lua is listed in the TOC but missing", key)
    end
  end
  Themes.Register = register
end
for _, key in ipairs(Themes.KEYS) do
  if not sources[key] then fail("theme %s is not registered", key) end
end

-- String values of the locale tables (enUS, then frFR on a French client).
local function localeTable(locale)
  Stub.Reset()
  Stub.locale = locale
  local lns = Stub.LoadAddon({ files = { "Locales/enUS.lua", "Locales/frFR.lua" } })
  local out = {}
  for k, v in pairs(lns.L) do
    if type(k) == "string" and type(v) == "string" then out[k] = v end
  end
  return out
end
local LOCALES = { enUS = localeTable("enUS"), frFR = localeTable("frFR") }

---------------------------------------------------------------------------
-- UTF-8
---------------------------------------------------------------------------
local function utf8Char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

-- Adds the code points of s (UTF-8; a stray byte counts as Latin-1) to set; controls skipped.
local function addCodepoints(s, set)
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local cp, len = b, 1
    if b >= 0xF0 and i + 3 <= n then
      cp = (b - 0xF0) * 262144 + (s:byte(i + 1) - 0x80) * 4096 + (s:byte(i + 2) - 0x80) * 64 + (s:byte(i + 3) - 0x80)
      len = 4
    elseif b >= 0xE0 and i + 2 <= n then
      cp = (b - 0xE0) * 4096 + (s:byte(i + 1) - 0x80) * 64 + (s:byte(i + 2) - 0x80)
      len = 3
    elseif b >= 0xC0 and i + 1 <= n then
      cp = (b - 0xC0) * 64 + (s:byte(i + 1) - 0x80)
      len = 2
    end
    if cp >= 0x20 and cp ~= 0x7F then set[cp] = true end
    i = i + len
  end
end

local function cpName(cp)
  local ch = cp >= 0x20 and utf8Char(cp) or "?"
  return string.format("U+%04X %s", cp, ch)
end

-- A text as rendered: colour codes and format specifiers removed, %% -> %.
local function rendered(s)
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("%%%%", "\1"):gsub("%%[%-%+ #0]*%d*%.?%d*[sdifgxXc]", ""):gsub("\1", "%%")
  return s
end

---------------------------------------------------------------------------
-- TTF cmap (formats 4 and 12), string.byte only
---------------------------------------------------------------------------
local function U16(s, o) local a, b = s:byte(o + 1, o + 2) return a * 256 + b end
local function S16(s, o) local v = U16(s, o) if v >= 32768 then v = v - 65536 end return v end
local function LE16(s, o) local a, b = s:byte(o + 1, o + 2) return a + b * 256 end
local function U32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

-- Returns a function cp -> covered (true/false), or nil + error.
local function loadCmap(path)
  local s = readFile(path)
  if not s then return nil, "missing file" end
  if #s < 12 then return nil, "not a TTF" end
  local tag = s:sub(1, 4)
  if tag ~= "\0\1\0\0" and tag ~= "true" and tag ~= "OTTO" then return nil, "not a TTF/OTF file" end
  local numTables = U16(s, 4)
  local cmapOff
  for i = 0, numTables - 1 do
    local rec = 12 + 16 * i
    if s:sub(rec + 1, rec + 4) == "cmap" then cmapOff = U32(s, rec + 8) end
  end
  if not cmapOff then return nil, "no cmap table" end
  local subs = {}
  local nt = U16(s, cmapOff + 2)
  for i = 0, nt - 1 do
    local st = cmapOff + U32(s, cmapOff + 4 + 8 * i + 4)
    local fmt = U16(s, st)
    if fmt == 4 then
      local seg = U16(s, st + 6) / 2
      subs[#subs + 1] = { fmt = 4, st = st, seg = seg, ends = st + 14, starts = st + 16 + 2 * seg,
                          deltas = st + 16 + 4 * seg, ros = st + 16 + 6 * seg }
    elseif fmt == 12 then
      subs[#subs + 1] = { fmt = 12, st = st, n = U32(s, st + 12) }
    end
  end
  if #subs == 0 then return nil, "no cmap subtable of format 4 or 12" end

  local function has4(t, cp)
    if cp > 0xFFFF then return false end
    local lo, hi = 0, t.seg - 1
    while lo < hi do                                -- first segment whose end >= cp
      local mid = math.floor((lo + hi) / 2)
      if U16(s, t.ends + 2 * mid) < cp then lo = mid + 1 else hi = mid end
    end
    local k = lo
    if U16(s, t.ends + 2 * k) < cp then return false end
    local start = U16(s, t.starts + 2 * k)
    if cp < start or cp == 0xFFFF then return false end
    local delta = S16(s, t.deltas + 2 * k)
    local ro = U16(s, t.ros + 2 * k)
    local g
    if ro == 0 then
      g = (cp + delta) % 65536
    else
      local addr = t.ros + 2 * k + ro + 2 * (cp - start)
      if addr + 2 > #s then return false end
      g = U16(s, addr)
      if g ~= 0 then g = (g + delta) % 65536 end
    end
    return g ~= 0
  end

  local function has12(t, cp)
    local lo, hi = 0, t.n - 1
    while lo <= hi do
      local mid = math.floor((lo + hi) / 2)
      local g = t.st + 16 + 12 * mid
      local a, b = U32(s, g), U32(s, g + 4)
      if cp < a then hi = mid - 1
      elseif cp > b then lo = mid + 1
      else return U32(s, g + 8) + (cp - a) ~= 0 end
    end
    return false
  end

  return function(cp)
    for i = 1, #subs do
      local t = subs[i]
      if t.fmt == 4 then
        if has4(t, cp) then return true end
      elseif has12(t, cp) then
        return true
      end
    end
    return false
  end
end

---------------------------------------------------------------------------
-- Fonts: files, licences, cyr flags
---------------------------------------------------------------------------
local FONT_DIR = ROOT .. "Media/Fonts/"
local cmaps = {}
local fontNames = {}
for name in pairs(Themes.FONTS) do fontNames[#fontNames + 1] = name end
table.sort(fontNames)

for _, name in ipairs(fontNames) do
  local e = Themes.FONTS[name]
  local has, err = loadCmap(FONT_DIR .. e.file)
  if not has then
    fail("font %s: Media/Fonts/%s: %s", name, e.file, err)
  else
    cmaps[name] = has
    local cyr = true
    for cp = 0x0410, 0x044F do
      if not has(cp) then cyr = false break end
    end
    if cyr ~= (e.cyr == true) then
      fail("font %s: cyr = %s but the file %s U+0410-U+044F", name, tostring(e.cyr),
        cyr and "covers" or "does not cover")
    end
  end
  if not exists(FONT_DIR .. "LICENSES/" .. name .. "-OFL.txt") then
    fail("font %s: Media/Fonts/LICENSES/%s-OFL.txt is missing", name, name)
  end
end
do
  local listed = {}
  for _, name in ipairs(fontNames) do listed[Themes.FONTS[name].file] = true end
  for _, f in ipairs(listDir(FONT_DIR) or {}) do
    if f:find("%.[tToO][tT][fF]$") and not listed[f] then warn("Media/Fonts/%s is not in Themes.FONTS", f) end
  end
end

---------------------------------------------------------------------------
-- Glyph coverage per theme
---------------------------------------------------------------------------
local BODY_TEXTS, DISPLAY_TEXTS = {}, {}
do
  local function addRange(a, b)
    for cp = a, b do BODY_TEXTS[#BODY_TEXTS + 1] = utf8Char(cp) end
  end
  addRange(0x20, 0x7E)
  for _, cp in ipairs({ 0xA0, 0xAB, 0xB7, 0xBB }) do addRange(cp, cp) end
  for cp = 0xC0, 0xFF do
    if cp ~= 0xD7 and cp ~= 0xF7 then addRange(cp, cp) end
  end
  for _, file in ipairs({ "Locales/enUS.lua", "Locales/frFR.lua" }) do
    local text = readFile(ROOT .. file)
    if text then BODY_TEXTS[#BODY_TEXTS + 1] = text else fail("%s is missing", file) end
  end
  for _, loc in ipairs({ "enUS", "frFR" }) do
    local L = LOCALES[loc]
    local keys = {}
    for k in pairs(L) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do BODY_TEXTS[#BODY_TEXTS + 1] = rendered(L[k]) end
    for _, k in ipairs(Themes.DISPLAY_KEYS) do
      if L[k] then DISPLAY_TEXTS[#DISPLAY_TEXTS + 1] = rendered(L[k])
      else fail("display key %s is missing from the %s strings", k, loc) end
    end
  end
  DISPLAY_TEXTS[#DISPLAY_TEXTS + 1] = "0123456789%.,:/-()~ "
  DISPLAY_TEXTS[#DISPLAY_TEXTS + 1] = "\194\160"
end

-- Code points of texts after the font's substitutions.
local function needed(texts, entry)
  local set = {}
  local subst = entry and entry.subst
  for i = 1, #texts do
    local s = texts[i]
    if subst then
      for j = 1, #subst do s = s:gsub(subst[j][3], subst[j][4]) end
    end
    addCodepoints(s, set)
  end
  return set
end

local coverageCache = {}
local function checkCoverage(key, role, name, texts, kind)
  if name == nil or name == "game" then return end
  local e = Themes.FONTS[name]
  if not e then
    fail("theme %s: fonts.%s = %s is not in Themes.FONTS", key, role, tostring(name))
    return
  end
  local has = cmaps[name]
  if not has then return end
  local cacheKey = name .. "/" .. kind
  local missing = coverageCache[cacheKey]
  if not missing then
    missing = {}
    local set = needed(texts, e)
    local cps = {}
    for cp in pairs(set) do cps[#cps + 1] = cp end
    table.sort(cps)
    for _, cp in ipairs(cps) do
      if not has(cp) then missing[#missing + 1] = cpName(cp) end
    end
    coverageCache[cacheKey] = missing
  end
  if #missing > 0 then
    local shown = {}
    for i = 1, math.min(#missing, 16) do shown[i] = missing[i] end
    fail("theme %s: %s font %s lacks %d character(s): %s%s", key, role, name, #missing,
      table.concat(shown, ", "), #missing > 16 and ", ..." or "")
  elseif VERBOSE then
    print(string.format("ok    theme %s: %s font %s covers the %s set", key, role, name, kind))
  end
end

local themeKeys = {}
for key in pairs(sources) do themeKeys[#themeKeys + 1] = key end
table.sort(themeKeys)

for _, key in ipairs(themeKeys) do
  local fonts = type(sources[key].fonts) == "table" and sources[key].fonts or {}
  local body = fonts.body
  local num = fonts.num
  if num == nil then num = body end
  checkCoverage(key, "display", fonts.display, DISPLAY_TEXTS, "display")
  checkCoverage(key, "body", body, BODY_TEXTS, "body")
  if num ~= body then checkCoverage(key, "num", num, BODY_TEXTS, "body") end
end

---------------------------------------------------------------------------
-- TGA files
---------------------------------------------------------------------------
local BUDGET = 98304
local MEDIA_DIR = ROOT .. "Media/Themes/"
local SRC_DIR = ROOT .. "media-src/"

local function isPow2(n)
  if type(n) ~= "number" or n < 1 or n > 256 or n % 1 ~= 0 then return false end
  while n > 1 do
    if n % 2 ~= 0 then return false end
    n = n / 2
  end
  return true
end

local textures, totalBytes = 0, 0

-- Checks one TGA against its declaration; returns its size in bytes.
local function checkTga(where, path, decl)
  local s = readFile(path)
  if not s then
    fail("%s: file missing", where)
    return 0
  end
  textures = textures + 1
  if #s < 18 then
    fail("%s: not a TGA file", where)
    return #s
  end
  local idLen, cmapType, imgType = s:byte(1), s:byte(2), s:byte(3)
  local w, h = LE16(s, 12), LE16(s, 14)
  local bpp, desc = s:byte(17), s:byte(18)
  local ok = true
  if cmapType ~= 0 then fail("%s: has a colour map", where) ok = false end
  if imgType ~= 2 then fail("%s: image type %d, expected 2 (uncompressed true colour)", where, imgType) ok = false end
  if bpp ~= 32 then fail("%s: %d bpp, expected 32", where, bpp) ok = false end
  if desc ~= 0x08 then fail("%s: descriptor 0x%02X, expected 0x08 (8 alpha bits, bottom-left origin)", where, desc) ok = false end
  if not isPow2(w) or not isPow2(h) then fail("%s: %dx%d is not power-of-two up to 256", where, w, h) ok = false end
  if decl and (w ~= decl[1] or h ~= decl[2]) then
    fail("%s: %dx%d, declared %sx%s", where, w, h, tostring(decl[1]), tostring(decl[2]))
  end
  local data0 = 18 + idLen
  if ok and #s < data0 + w * h * 4 then
    fail("%s: truncated pixel data", where)
    ok = false
  end
  if not ok then return #s end
  -- pixels: B, G, R, A
  local notGrey, semi, over, lit, equal = 0, 0, 0, 0, 0
  local grey = decl and decl.grey == true
  for i = data0 + 1, data0 + w * h * 4, 4 do
    local b, g, r, a = s:byte(i, i + 3)
    if grey and (r ~= g or g ~= b) then notGrey = notGrey + 1 end
    if a > 0 and a < 255 then
      semi = semi + 1
      local m = r
      if g > m then m = g end
      if b > m then m = b end
      if m > a then over = over + 1 end
      if m >= 16 then
        lit = lit + 1
        if m - a <= 1 and a - m <= 1 then equal = equal + 1 end
      end
    end
  end
  if notGrey > 0 then fail("%s: declared grey but %d pixel(s) have R, G, B not all equal", where, notGrey) end
  -- Premultiplied alpha never stores a channel above alpha, and premultiplied white art
  -- stores channel = alpha. Grey media are white art tinted by vertex colour, so that
  -- signature (no channel above alpha, and most lit semi-transparent pixels with
  -- channel = alpha) means the converter premultiplied. Baked media can be legitimately
  -- darker than their alpha everywhere (ink composited under a line), so they are not
  -- judged: tools/svg2tga.py keeps the straight alpha that sips writes.
  if grey and semi >= 16 and over == 0 and lit >= 8 and equal * 5 >= lit * 4 then
    fail("%s: looks premultiplied (semi-transparent pixels store channel = alpha)", where)
  end
  -- Colour bleed: a transparent texel next to bright art must not be black. The game
  -- filters straight alpha, so at a UI scale other than 1 (or on minified art) the edge
  -- of a bright line is blended with that black: a dark fringe. tools/svg2tga.py bleeds
  -- the art's colour into the transparent texels (--bleed fixes an existing file).
  local fringe = 0
  local function bright(x, y)
    if x < 0 or x >= w or y < 0 or y >= h then return false end
    local j = data0 + (y * w + x) * 4 + 1
    local b2, g2, r2, a2 = s:byte(j, j + 3)
    return a2 > 0 and 0.299 * r2 + 0.587 * g2 + 0.114 * b2 > 128
  end
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local i = data0 + (y * w + x) * 4 + 1
      local b, g, r, a = s:byte(i, i + 3)
      if a == 0 and r == 0 and g == 0 and b == 0
          and (bright(x - 1, y) or bright(x + 1, y) or bright(x, y - 1) or bright(x, y + 1)) then
        fringe = fringe + 1
      end
    end
  end
  if fringe > 0 then
    fail("%s: %d transparent texel(s) are black next to bright art (dark fringes when filtered): "
      .. "python3 tools/svg2tga.py --bleed <file>", where, fringe)
  end
  return #s
end

local mediaDirs = listDir(MEDIA_DIR)
if not mediaDirs then
  fail("cannot list Media/Themes (io.popen unavailable or folder missing)")
  mediaDirs = {}
end
local knownDir = { common = true }
for _, key in ipairs(Themes.KEYS) do knownDir[key] = true end
for _, d in ipairs(mediaDirs) do
  if not knownDir[d] then fail("Media/Themes/%s is not a theme folder", d) end
end

local function checkFolder(dir, declared, needSources)
  local where0 = "Media/Themes/" .. dir .. "/"
  local names = listDir(MEDIA_DIR .. dir) or {}
  local present, bytes = {}, 0
  for _, f in ipairs(names) do
    local name = f:match("^(.*)%.tga$")
    if not name then
      fail("%s%s: only .tga files belong here", where0, f)
    elseif not name:find("^[a-z0-9_]+$") then
      fail("%s%s: file names are lowercase [a-z0-9_]", where0, f)
    else
      present[name] = true
      if not declared[name] then fail("%s%s is not declared in the theme's media", where0, f) end
    end
  end
  local declNames = {}
  for name in pairs(declared) do declNames[#declNames + 1] = name end
  table.sort(declNames)
  for _, name in ipairs(declNames) do
    local d = declared[name]
    local where = where0 .. name .. ".tga"
    if type(d) ~= "table" then
      fail("%s: declaration is not { w, h, grey = bool? }", where)
    elseif not present[name] then
      fail("%s: declared but missing", where)
    else
      bytes = bytes + checkTga(where, MEDIA_DIR .. dir .. "/" .. name .. ".tga", d)
      if needSources and not exists(SRC_DIR .. dir .. "/" .. name .. ".svg") then
        fail("%s: source media-src/%s/%s.svg is missing", where, dir, name)
      end
    end
  end
  if bytes > BUDGET then fail("%s: %d bytes of .tga, budget %d", where0, bytes, BUDGET) end
  for _, f in ipairs(listDir(SRC_DIR .. dir) or {}) do
    local name = f:match("^(.*)%.svg$")
    if name and not declared[name] then warn("media-src/%s/%s has no declared media", dir, f) end
  end
  totalBytes = totalBytes + bytes
  if VERBOSE then print(string.format("ok    %s: %d bytes", where0, bytes)) end
end

checkFolder("common", Themes.COMMON_MEDIA, true)
for _, key in ipairs(themeKeys) do
  local media = sources[key].media
  if media == nil then media = {} end
  if type(media) ~= "table" then
    fail("theme %s: media is not a table", key)
  else
    local hasFolder = false
    for _, d in ipairs(mediaDirs) do if d == key then hasFolder = true end end
    if next(media) ~= nil or hasFolder then checkFolder(key, media, true) end
  end
end

print(string.format("check_media: %d fonts, %d themes, %d textures (%.1f KiB), %d FAIL, %d WARN",
  #fontNames, #themeKeys, textures, totalBytes / 1024, errors, warnings))
os.exit(errors == 0 and 0 or 1)
