-- tests/check_encoding.lua - encoding checks for every .lua and .toc file (SPEC-FINAL 2.6, 9.5).
-- Usage (from anywhere): lua tests/check_encoding.lua
-- Runs on Lua 5.1 and 5.5 (no utf8 library). Exit code 0 = OK, 1 = problems found.
--
-- A file passes when it is valid UTF-8 without BOM, uses LF line endings only (no CR),
-- and every character decodes to a code point in U+0000..U+00FF (Latin-1 range: the
-- game font has no glyph above it). Control characters other than TAB and LF, and the
-- C1 range U+0080..U+009F (a sign of mojibake), are refused too.
-- Exception, and the only one: the locale files of NATIVE_LOCALES (the languages of
-- C.LANGUAGES_NATIVE_ONLY, offered and applied only on a client in that language, whose
-- font draws their script) may hold any valid UTF-8 character above U+00FF.
-- Problems are reported as file:line:column (column counted in characters).

local MAX_REPORTS_PER_FILE = 25

-- Locale files allowed to hold characters above U+00FF (exact repository paths).
local NATIVE_LOCALES = {
  ["Locales/ruRU.lua"] = true, ["Locales/koKR.lua"] = true,
  ["Locales/zhCN.lua"] = true, ["Locales/zhTW.lua"] = true,
}

-- Suggested ASCII / Latin-1 replacements for characters that often slip in.
local HINTS = {
  [0x2248] = "~",                 -- almost equal to
  [0x2026] = "...",               -- ellipsis
  [0x2014] = "-",                 -- em dash
  [0x2013] = "-",                 -- en dash
  [0x2212] = "-",                 -- minus sign
  [0x2018] = "'",
  [0x2019] = "'",
  [0x201C] = "\"",
  [0x201D] = "\"",
  [0x2192] = ">",                 -- right arrow
  [0x2190] = "<",
  [0x2022] = "\\194\\183 (middle dot)",
  [0x2009] = "a space",
  [0x202F] = "\\194\\160 (no-break space)",
  [0x0153] = "oe",
  [0x0152] = "OE",
  [0x20AC] = "EUR",
}

local function detectRoot()
  local a0 = (arg and arg[0]) or ""
  a0 = string.gsub(a0, "\\", "/")
  local base = string.match(a0, "^(.-)tests/[^/]+%.lua$")
  if base then
    if base == "" then
      return "./"
    end
    return base
  end
  local dir = string.match(a0, "^(.*/)[^/]*$")
  return (dir or "./") .. "../"
end

local function shellQuote(s)
  return "'" .. (string.gsub(s, "'", "'\\''")) .. "'"
end

-- Runs a shell command and feeds each output line to add(); false when nothing came out
-- (io.popen can exist but raise "popen not supported" on some Lua 5.1 builds).
local function popenLines(cmd, add)
  if not io.popen then
    return false
  end
  local ok, h = pcall(io.popen, cmd)
  if not ok or not h then
    return false
  end
  local got = false
  for line in h:lines() do
    got = true
    add(line)
  end
  h:close()
  return got
end

-- Last resort without git and find: the files listed by the .toc files and the test files
-- of SPEC 1.1.
local KNOWN_TESTS = { "run.lua", "wowstub.lua", "stub_engine.lua", "stub_stats.lua", "stub_ui.lua",
  "test_core.lua", "test_format.lua", "test_tracker.lua", "test_played.lua", "test_crash.lua",
  "test_rate_sim.lua", "test_stats.lua", "test_tokens.lua", "test_ui_smoke.lua",
  "check_toc.lua", "check_encoding.lua", "lint51.lua" }

local function fallbackFiles(root, add)
  local got = false
  for _, toc in ipairs({ "TruePlayed_Camelot.toc", "TruePlayed_Vanilla.toc" }) do
    local h = io.open(root .. toc, "rb")
    if h then
      got = true
      add(toc)
      for line in h:lines() do
        local entry = string.match(line, "^%s*([^#%s].-)%s*$")
        if entry then
          add((string.gsub(entry, "\\", "/")))
        end
      end
      h:close()
    end
  end
  for _, name in ipairs(KNOWN_TESTS) do
    local h = io.open(root .. "tests/" .. name, "rb")
    if h then
      h:close()
      got = true
      add("tests/" .. name)
    end
  end
  return got
end

-- Repository files: git (tracked + untracked, not ignored), else find. Paths inside
-- hidden folders (.git, .github, .release, .lua...) are skipped, and so is tests/baseline/
-- (the frozen pre-theme copy used by test_actuel_golden: never edited, never shipped).
local function listFiles(root)
  local files, set = {}, {}
  local function add(p)
    p = string.gsub(p, "^%./", "")
    if p == "" or set[p] then
      return
    end
    if string.find(p, "^%.") or string.find(p, "/%.") or string.find(p, "^tests/baseline/") then
      return
    end
    set[p] = true
    files[#files + 1] = p
  end
  local got = popenLines("cd " .. shellQuote(root)
    .. " && git -c core.quotepath=off ls-files --cached --others --exclude-standard 2>/dev/null", add)
  if not got then
    got = popenLines("cd " .. shellQuote(root) .. " && find . -type f 2>/dev/null", add)
  end
  if not got then
    got = fallbackFiles(root, add)
    if got then
      print("note: git and find are unavailable: checking the .toc files and the known test files only")
    end
  end
  table.sort(files)
  return files, got
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
end

local total = 0

-- Returns the number of problems found in `data` (the content of `rel`).
local function checkFile(rel, data)
  local native = NATIVE_LOCALES[rel] == true
  local problems = 0
  local function report(line, col, fmt, ...)
    problems = problems + 1
    if problems <= MAX_REPORTS_PER_FILE then
      print(string.format("%s:%d:%d: ", rel, line, col) .. string.format(fmt, ...))
    end
  end

  local len = #data
  local i, line, col = 1, 1, 0
  local crCount, crLine, crCol = 0, 0, 0

  if string.sub(data, 1, 3) == "\239\187\191" then
    report(1, 1, "UTF-8 BOM: save the file as UTF-8 without BOM")
    i = 4
  end

  while i <= len do
    -- Jump over a run of printable ASCII (and TAB), which is by far the common case.
    local s = string.find(data, "[^\9\32-\126]", i)
    if not s then
      break
    end
    col = col + (s - i)
    i = s
    local b = string.byte(data, i)
    if b == 10 then
      line = line + 1
      col = 0
      i = i + 1
    elseif b == 13 then
      col = col + 1
      crCount = crCount + 1
      if crCount == 1 then
        crLine, crCol = line, col
      end
      i = i + 1
    elseif b < 128 then
      col = col + 1
      report(line, col, "control character 0x%02X (only TAB and LF are allowed)", b)
      i = i + 1
    else
      col = col + 1
      local need, cp = 0, 0
      if b >= 0xC2 and b <= 0xDF then
        need, cp = 1, b - 0xC0
      elseif b >= 0xE0 and b <= 0xEF then
        need, cp = 2, b - 0xE0
      elseif b >= 0xF0 and b <= 0xF4 then
        need, cp = 3, b - 0xF0
      end
      if need == 0 then
        report(line, col, "invalid UTF-8 byte 0x%02X (is the file saved as UTF-8?)", b)
        i = i + 1
      else
        local ok = true
        for k = 1, need do
          local c = string.byte(data, i + k)
          if not c or c < 0x80 or c > 0xBF then
            ok = false
            break
          end
          cp = cp * 64 + (c - 0x80)
        end
        if ok and need == 2 and (cp < 0x800 or (cp >= 0xD800 and cp <= 0xDFFF)) then
          ok = false
        elseif ok and need == 3 and (cp < 0x10000 or cp > 0x10FFFF) then
          ok = false
        end
        if not ok then
          report(line, col, "invalid UTF-8 sequence starting with byte 0x%02X (is the file saved as UTF-8?)", b)
          i = i + 1
        else
          if cp > 0xFF then
            if not native then
              local hint = HINTS[cp]
              report(line, col, "U+%04X '%s' is outside the Latin-1 range%s", cp,
                string.sub(data, i, i + need),
                hint and (": use " .. hint .. " instead") or " (the game font cannot draw it)")
            end
          elseif cp < 0xA0 then
            report(line, col, "U+%04X is a C1 control character (mojibake?)", cp)
          end
          i = i + need + 1
        end
      end
    end
  end

  if crCount > 0 then
    report(crLine, crCol, "%d CR character(s): use LF line endings only", crCount)
  end
  if problems > MAX_REPORTS_PER_FILE then
    print(string.format("%s: ... %d more problem(s) not shown", rel, problems - MAX_REPORTS_PER_FILE))
  end
  return problems
end

local ROOT = detectRoot()
local files, listed = listFiles(ROOT)
if not listed then
  print("check_encoding: could not list the repository files (no git, no find)")
  os.exit(1)
end

local checked = 0
for _, rel in ipairs(files) do
  if string.find(rel, "%.lua$") or string.find(rel, "%.toc$") then
    local data = readFile(ROOT .. rel)
    if data then
      checked = checked + 1
      total = total + checkFile(rel, data)
    end
  end
end

if checked == 0 then
  print("check_encoding: no .lua or .toc file found under " .. ROOT)
  os.exit(1)
end

if total == 0 then
  print(string.format("check_encoding: OK - %d file(s) checked", checked))
else
  print(string.format("check_encoding: %d problem(s) in %d file(s) checked", total, checked))
end
os.exit(total == 0 and 0 or 1)
