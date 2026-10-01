-- tests/fontmetrics.lua - text widths from the real fonts, for the tests that check
-- truncation and overlaps (the stub measures 6 px per character). Lua 5.1 / 5.5,
-- string.byte parsing only (lint51 forbids string.unpack).
--
--   local FM = dofile(ROOT .. "tests/fontmetrics.lua")
--   local Width = FM.New(ROOT)        -- Width(fontPath, size, text) -> px
--   FM.Install(Stub, Width)           -- FontString:GetStringWidth / GetUnboundedStringWidth
--                                     -- measure with it (bounded by an explicit width, as the
--                                     -- client does); returns a function restoring the stub
--
-- Width = sum of the advance widths (hmtx) of the code points (cmap formats 4 and 12) x
-- size / unitsPerEm, colour codes left out, no kerning. Fonts of Media/Fonts are read from
-- their files; any other path (the game font, not shipped) and any character a bundled
-- font lacks is measured with a stand-in of the game font of the client that draws it:
--   * Latin and the rest: Signika x 1.04, about the same width as FRIZQT__;
--   * Cyrillic (U+0400-U+052F, FRIZQT___CYR on a ruRU client): Nunito Sans, scaled so that
--     its Latin alphabet is as wide as the Latin stand-in's, + 5 % (no metrics of the
--     Cyrillic game font in the repository);
--   * Hangul, CJK ideographs, kana and full-width forms (the koKR / zhCN / zhTW game
--     fonts): one em (the font size) per character, the widest such glyphs (conservative).
local FM = {}

local floor = math.floor

local function U16(s, o) local a, b = s:byte(o + 1, o + 2) return a * 256 + b end
local function S16(s, o) local v = U16(s, o) if v >= 32768 then v = v - 65536 end return v end
local function U32(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

local function ReadFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- A font file -> { upm = , adv = function(cp) -> advance in font units }.
local function LoadFont(path)
  local s = ReadFile(path)
  if not s then return nil end
  local tables = {}
  for i = 0, U16(s, 4) - 1 do
    local rec = 12 + 16 * i
    tables[s:sub(rec + 1, rec + 4)] = U32(s, rec + 8)
  end
  local head, hhea, hmtx, cmap = tables.head, tables.hhea, tables.hmtx, tables.cmap
  if not (head and hhea and hmtx and cmap) then return nil end
  local upm = U16(s, head + 18)
  local nHM = U16(s, hhea + 34)
  local subs = {}
  for i = 0, U16(s, cmap + 2) - 1 do
    local st = cmap + U32(s, cmap + 4 + 8 * i + 4)
    local fmt = U16(s, st)
    if fmt == 4 then
      local seg = U16(s, st + 6) / 2
      subs[#subs + 1] = { fmt = 4, seg = seg, ends = st + 14, starts = st + 16 + 2 * seg,
                          deltas = st + 16 + 4 * seg, ros = st + 16 + 6 * seg }
    elseif fmt == 12 then
      subs[#subs + 1] = { fmt = 12, st = st, n = U32(s, st + 12) }
    end
  end

  local function Glyph4(t, cp)
    if cp > 0xFFFF then return 0 end
    local lo, hi = 0, t.seg - 1
    while lo < hi do
      local mid = floor((lo + hi) / 2)
      if U16(s, t.ends + 2 * mid) < cp then lo = mid + 1 else hi = mid end
    end
    if U16(s, t.ends + 2 * lo) < cp then return 0 end
    local start = U16(s, t.starts + 2 * lo)
    if cp < start then return 0 end
    local delta, ro = S16(s, t.deltas + 2 * lo), U16(s, t.ros + 2 * lo)
    if ro == 0 then return (cp + delta) % 65536 end
    local g = U16(s, t.ros + 2 * lo + ro + 2 * (cp - start))
    if g ~= 0 then g = (g + delta) % 65536 end
    return g
  end

  local function Glyph12(t, cp)
    local lo, hi = 0, t.n - 1
    while lo <= hi do
      local mid = floor((lo + hi) / 2)
      local g = t.st + 16 + 12 * mid
      local a, b = U32(s, g), U32(s, g + 4)
      if cp < a then hi = mid - 1 elseif cp > b then lo = mid + 1 else return U32(s, g + 8) + (cp - a) end
    end
    return 0
  end

  local cache = {}
  local function Glyph(cp)
    local g = 0
    for i = 1, #subs do
      local t = subs[i]
      g = (t.fmt == 4) and Glyph4(t, cp) or Glyph12(t, cp)
      if g ~= 0 then break end
    end
    return g
  end
  local function Adv(cp)
    local v = cache[cp]
    if v then return v end
    local g = Glyph(cp)
    if g >= nHM then g = nHM - 1 end
    v = U16(s, hmtx + 4 * g)
    cache[cp] = v
    return v
  end
  local function Has(cp) return Glyph(cp) ~= 0 end
  return { upm = upm, adv = Adv, has = Has }
end

-- Scripts drawn by another game font than FRIZQT__ (see the header).
local function IsWide(cp)
  return (cp >= 0x1100 and cp <= 0x11FF) or (cp >= 0x2E80 and cp <= 0x9FFF) or (cp >= 0xAC00 and cp <= 0xD7AF)
    or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFE30 and cp <= 0xFE4F) or (cp >= 0xFF00 and cp <= 0xFFEF)
end
local function IsCyrillic(cp) return cp >= 0x0400 and cp <= 0x052F end
local LATIN_SAMPLE = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- UTF-8 code points of `text` into `out` (reused); returns the count.
local function CodePoints(text, out)
  local n, i, len = 0, 1, #text
  while i <= len do
    local c = text:byte(i)
    local cp, k = c, 1
    if c >= 0xF0 then cp, k = c % 8, 4 elseif c >= 0xE0 then cp, k = c % 16, 3 elseif c >= 0xC0 then cp, k = c % 32, 2 end
    for j = 1, k - 1 do cp = cp * 64 + (text:byte(i + j) or 128) % 64 end
    n = n + 1
    out[n] = cp
    i = i + k
  end
  return n
end

function FM.New(root)
  local fonts = {}
  local cps = {}
  local function Load(file)
    local f = fonts[file]
    if f == nil then
      f = LoadFont(root .. "Media/Fonts/" .. file) or false
      fonts[file] = f
    end
    return f
  end
  -- A bundled font, or false for the game font (any other path).
  local function Font(path)
    local file = type(path) == "string" and path:match("([^\\/]+)$") or nil
    if not file or file:lower():find("^frizqt") then return false end
    return Load(file)
  end
  local latin, cyr = Load("Signika-Medium.ttf"), Load("NunitoSans-SemiBold.ttf")
  local LATIN_K, CYR_K = 1.04, 1
  local function Sum(f, s)
    local n, total = CodePoints(s, cps), 0
    for i = 1, n do total = total + f.adv(cps[i]) end
    return total / f.upm
  end
  if latin and cyr then CYR_K = Sum(latin, LATIN_SAMPLE) * LATIN_K / Sum(cyr, LATIN_SAMPLE) * 1.05 end
  -- Width of code point cp in the game font stand-ins, in ems.
  local function GameEm(cp)
    if IsWide(cp) then return 1 end
    if IsCyrillic(cp) and cyr then return cyr.adv(cp) / cyr.upm * CYR_K end
    if latin then return latin.adv(cp) / latin.upm * LATIN_K end
    return 0.5
  end
  return function(path, size, text)
    if text == nil then return 0 end
    text = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local f = Font(path)
    local n = CodePoints(text, cps)
    local sum = 0
    for i = 1, n do
      local cp = cps[i]
      if f and f.has(cp) then sum = sum + f.adv(cp) / f.upm else sum = sum + GameEm(cp) end
    end
    return sum * (size or 12)
  end
end

-- Stub FontStrings measure with Width; an explicit width bounds GetStringWidth.
function FM.Install(Stub, Width)
  local M = getmetatable(UIParent).__index
  local gsw, guw = rawget(M, "GetStringWidth"), rawget(M, "GetUnboundedStringWidth")
  local function Unbounded(self)
    return Width(rawget(self, "_font"), rawget(self, "_fontSize") or 12, rawget(self, "_text"))
  end
  rawset(M, "GetUnboundedStringWidth", Unbounded)
  rawset(M, "GetStringWidth", function(self)
    local c = Stub.calls
    c.GetStringWidth = (c.GetStringWidth or 0) + 1
    local w = Unbounded(self)
    local b = rawget(self, "_width") or 0
    if b > 0 and w > b then return b end
    return w
  end)
  return function()
    rawset(M, "GetStringWidth", gsw)
    rawset(M, "GetUnboundedStringWidth", guw)
  end
end

return FM
