-- tests/check_toc.lua - standalone TOC checks for TruePlayed (SPEC-FINAL 1.2, 9.5).
-- Usage (from anywhere): lua tests/check_toc.lua
-- Runs on Lua 5.1 and 5.5. Exit code 0 = OK, 1 = at least one FAIL.
--
-- Checks:
--   * TruePlayed_Camelot.toc and the identical generic TruePlayed.toc exist;
--   * required lines (Interface in the Forever range, SavedVariables, LoadSavedVariablesFirst,
--     OptionalDeps: WTFix, the three AddonCompartment functions, Title, Version);
--   * FAIL on "## X-WTFix-Managed" (injected by the WTFix launcher into symlinked addons);
--   * WARN on the <AUTHOR> / <ACCOUNT> placeholders;
--   * every listed file exists (exact case) and is not a test file; no duplicates;
--   * every addon .lua/.xml outside tests/ is listed;
--   * load order: Locales/enUS.lua first, Core.lua before the other modules (SPEC 1.3);
--   * themes (SPEC-themes 5.1): Themes.lua, then Themes/actuel.lua and the other theme files
--     in one block, then the modules that use them (BarSkin before Bar, TooltipFrame before
--     Tooltip);
--   * any other TruePlayed_<Flavor>.toc (e.g. _Vanilla) is identical except its Interface line.

-- Update together with the "## Interface:" line when WoW Forever changes build.
local EXPECTED_INTERFACE = "16001"
local ADDON = "TruePlayed"
local MAIN_TOC = "TruePlayed_Camelot.toc"

local REQUIRED_EXACT = {
  { "SavedVariables", "TruePlayedDB" },
  { "LoadSavedVariablesFirst", "1" },
  { "AddonCompartmentFunc", "TruePlayed_OnAddonCompartmentClick" },
  { "AddonCompartmentFuncOnEnter", "TruePlayed_OnAddonCompartmentEnter" },
  { "AddonCompartmentFuncOnLeave", "TruePlayed_OnAddonCompartmentLeave" },
}

local errors, warnings = 0, 0

local function fail(fmt, ...)
  errors = errors + 1
  print("FAIL  " .. string.format(fmt, ...))
end

local function warn(fmt, ...)
  warnings = warnings + 1
  print("WARN  " .. string.format(fmt, ...))
end

-- Repository root, derived from the script path (arg[0]).
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

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read("*a")
  f:close()
  return data
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

-- Repository files: git (tracked + untracked, not ignored), else find. Paths inside
-- hidden folders (.git, .github, .release, .lua...) are skipped.
local function listFiles(root)
  local files, set = {}, {}
  local function add(p)
    p = string.gsub(p, "^%./", "")
    if p == "" or set[p] then
      return
    end
    if string.find(p, "^%.") or string.find(p, "/%.") then
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
  table.sort(files)
  return files, set, got
end

local function trim(s)
  return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function parseToc(text)
  local toc = { meta = {}, metaLower = {}, metaLine = {}, files = {}, fileLine = {}, lines = {} }
  local n = 0
  for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
    n = n + 1
    local line = string.gsub(raw, "\r$", "")
    toc.lines[n] = line
    local key, value = string.match(line, "^##%s*([^:]-)%s*:%s*(.-)%s*$")
    if key then
      local lower = string.lower(key)
      if toc.metaLower[lower] ~= nil then
        toc.duplicate = toc.duplicate or {}
        toc.duplicate[#toc.duplicate + 1] = { key, n }
      end
      toc.meta[key] = value
      toc.metaLower[lower] = value
      toc.metaLine[lower] = n
    elseif string.sub(line, 1, 1) ~= "#" then
      local entry = trim(line)
      if entry ~= "" then
        entry = string.gsub(entry, "\\", "/")
        toc.files[#toc.files + 1] = entry
        toc.fileLine[#toc.files] = n
      end
    end
  end
  return toc
end

local ROOT = detectRoot()
local files, fileSet, listed = listFiles(ROOT)
local lowerSet = {}
for _, p in ipairs(files) do
  lowerSet[string.lower(p)] = p
end

local function exists(rel)
  local f = io.open(ROOT .. rel, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

-- 1. Which TOC files exist?
local tocs = {}
for _, p in ipairs(files) do
  if string.find(p, "^[^/]+%.toc$") then
    tocs[#tocs + 1] = p
  end
end
if not listed then
  -- No git and no find: fall back to the known names.
  for _, name in ipairs({ MAIN_TOC, ADDON .. ".toc", ADDON .. "_Vanilla.toc" }) do
    if exists(name) then
      tocs[#tocs + 1] = name
      fileSet[name] = true
    end
  end
  warn("could not list the repository files (no git, no find): partial checks only")
end

if readFile(ROOT .. ADDON .. ".toc") ~= readFile(ROOT .. MAIN_TOC) then
  fail("%s.toc must exist and match %s for addon manager discovery", ADDON, MAIN_TOC)
end

local mainText = readFile(ROOT .. MAIN_TOC)
if not mainText then
  fail("%s is missing", MAIN_TOC)
  print(string.format("check_toc: %d error(s), %d warning(s)", errors, warnings))
  os.exit(1)
end

local main = parseToc(mainText)

-- 2. Lines that must never / should not appear, in every TOC.
for _, name in ipairs(tocs) do
  local text = (name == MAIN_TOC) and mainText or readFile(ROOT .. name)
  if text then
    local ln = 0
    for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
      ln = ln + 1
      if string.find(string.lower(raw), "x%-wtfix%-managed") then
        fail("%s:%d: '## X-WTFix-Managed' was injected by the WTFix launcher; restore the file with"
          .. " 'git checkout -- %s' and copy the addon instead of symlinking it", name, ln, name)
      end
      for _, ph in ipairs({ "<AUTHOR>", "<ACCOUNT>" }) do
        if string.find(raw, ph, 1, true) then
          warn("%s:%d: placeholder %s still present (release.yml refuses to publish;"
            .. " see docs/PUBLISHING-fr.md step 2)", name, ln, ph)
        end
      end
    end
    if name ~= MAIN_TOC and name ~= ADDON .. ".toc" and not string.find(name, "^" .. ADDON .. "_%a+%.toc$") then
      warn("%s: unexpected TOC file name", name)
    end
  end
end

-- 3. Required metadata of the main TOC.
if main.duplicate then
  for _, d in ipairs(main.duplicate) do
    fail("%s:%d: duplicate '## %s' line", MAIN_TOC, d[2], d[1])
  end
end

local interface = main.metaLower["interface"]
if not interface then
  fail("%s: missing '## Interface:' line", MAIN_TOC)
else
  local count = 0
  for v in string.gmatch(interface, "[^,%s]+") do
    count = count + 1
    local num = tonumber(v)
    if not num or num < 16000 or num > 19999 then
      fail("%s: Interface '%s' is not a WoW Forever interface (16000-19999)", MAIN_TOC, v)
    end
  end
  if count == 0 then
    fail("%s: empty Interface line", MAIN_TOC)
  elseif interface ~= EXPECTED_INTERFACE then
    warn("%s: Interface is '%s', expected '%s' (update EXPECTED_INTERFACE in tests/check_toc.lua"
      .. " when Forever changes build)", MAIN_TOC, interface, EXPECTED_INTERFACE)
  end
end

if not main.metaLower["title"] or main.metaLower["title"] == "" then
  fail("%s: missing '## Title:' line", MAIN_TOC)
end
if not main.metaLower["version"] or main.metaLower["version"] == "" then
  fail("%s: missing '## Version:' line (use @project-version@)", MAIN_TOC)
end

for _, req in ipairs(REQUIRED_EXACT) do
  local value = main.metaLower[string.lower(req[1])]
  if value == nil then
    fail("%s: missing '## %s: %s'", MAIN_TOC, req[1], req[2])
  elseif value ~= req[2] then
    fail("%s: '## %s' is '%s', expected '%s'", MAIN_TOC, req[1], value, req[2])
  end
end

local deps = main.metaLower["optionaldeps"]
local hasWTFix = false
if deps then
  for dep in string.gmatch(deps, "[^,%s]+") do
    if dep == "WTFix" then
      hasWTFix = true
    end
  end
end
if not hasWTFix then
  fail("%s: missing '## OptionalDeps: WTFix' (WTFix must rewrite the SavedVariables first)", MAIN_TOC)
end

local curseId = main.metaLower["x-curse-project-id"]
if curseId and not string.find(curseId, "^%d+$") then
  fail("%s: X-Curse-Project-ID '%s' is not a number (never put a placeholder there)", MAIN_TOC, curseId)
end
local wagoId = main.metaLower["x-wago-id"]
if wagoId and not string.find(wagoId, "^%w+$") then
  fail("%s: X-Wago-ID '%s' is not a Wago project id (never put a placeholder there)", MAIN_TOC, wagoId)
end

-- 4. Listed files.
local listedSet = {}
for i, entry in ipairs(main.files) do
  local ln = main.fileLine[i]
  if listedSet[entry] then
    fail("%s:%d: '%s' is listed twice", MAIN_TOC, ln, entry)
  end
  listedSet[entry] = true
  if not (string.find(entry, "%.lua$") or string.find(entry, "%.xml$")) then
    fail("%s:%d: '%s' is neither a .lua nor a .xml file", MAIN_TOC, ln, entry)
  end
  if string.find(entry, "^tests/") then
    fail("%s:%d: '%s' is a test file; the game must never load it", MAIN_TOC, ln, entry)
  end
  if listed then
    if not fileSet[entry] then
      local other = lowerSet[string.lower(entry)]
      if other then
        fail("%s:%d: '%s' differs in case from the file '%s' (Linux and the packager are case-sensitive)",
          MAIN_TOC, ln, entry, other)
      else
        fail("%s:%d: listed file '%s' does not exist", MAIN_TOC, ln, entry)
      end
    end
  elseif not exists(entry) then
    fail("%s:%d: listed file '%s' does not exist", MAIN_TOC, ln, entry)
  end
end

if #main.files == 0 then
  fail("%s: lists no file", MAIN_TOC)
end

-- 5. Every addon source file outside tests/ and media-src/ (offline tools, not packaged:
-- .pkgmeta ignores media-src) is listed.
for _, p in ipairs(files) do
  if (string.find(p, "%.lua$") or string.find(p, "%.xml$")) and not string.find(p, "^tests/")
    and not string.find(p, "^media%-src/")
    and exists(p) and not listedSet[p] then
    fail("'%s' is an addon file but %s does not list it", p, MAIN_TOC)
  end
end

-- 6. Load order (SPEC 1.3): the locale base first, Core before every other module.
if main.files[1] and main.files[1] ~= "Locales/enUS.lua" then
  fail("%s: the first file must be Locales/enUS.lua (it creates ns.L), found '%s'", MAIN_TOC, main.files[1])
end
local seenModule = nil
for _, entry in ipairs(main.files) do
  if entry == "Core.lua" then
    if seenModule then
      fail("%s: Core.lua must be loaded before '%s' (it creates ns.C, ns.Util and the bus)", MAIN_TOC, seenModule)
    end
    break
  elseif not string.find(entry, "^Locales/") then
    seenModule = seenModule or entry
  end
end
if not listedSet["Core.lua"] then
  fail("%s: Core.lua is not listed", MAIN_TOC)
end

-- 6b. Themes (design/SPEC-themes.md 5.1): Themes.lua, then the theme files in one block
-- starting with the classic fallback (actuel), then the modules that draw with a theme;
-- each engine before its user (BarSkin before Bar, TooltipFrame before Tooltip).
do
  local pos = {}
  for i, entry in ipairs(main.files) do pos[entry] = i end
  local first, last
  for i, entry in ipairs(main.files) do
    if string.find(entry, "^Themes/[^/]+%.lua$") then
      first = first or i
      last = i
    end
  end
  local engine = pos["Themes.lua"]
  if first and not engine then
    fail("%s: Themes/*.lua files are listed but Themes.lua is not", MAIN_TOC)
  elseif engine then
    if not first then
      fail("%s: Themes.lua is listed without any Themes/*.lua file", MAIN_TOC)
    else
      if first ~= engine + 1 then
        fail("%s: the Themes/*.lua files must follow Themes.lua directly", MAIN_TOC)
      end
      if main.files[engine + 1] ~= "Themes/actuel.lua" then
        fail("%s: Themes/actuel.lua (the fallback theme) must be the first theme file", MAIN_TOC)
      end
      for i = first, last do
        if not string.find(main.files[i], "^Themes/[^/]+%.lua$") then
          fail("%s: '%s' sits between theme files (keep Themes/*.lua in one block)", MAIN_TOC, main.files[i])
        end
      end
    end
    for _, user in ipairs({ "Graph.lua", "TooltipFrame.lua", "Tooltip.lua", "BarSkin.lua", "Bar.lua",
                            "Window.lua", "Options.lua", "Broker.lua" }) do
      if pos[user] and pos[user] < (last or engine) then
        fail("%s: '%s' must be loaded after Themes.lua and the theme files", MAIN_TOC, user)
      end
    end
    for _, pair in ipairs({ { "BarSkin.lua", "Bar.lua" }, { "TooltipFrame.lua", "Tooltip.lua" } }) do
      if pos[pair[1]] and pos[pair[2]] and pos[pair[1]] > pos[pair[2]] then
        fail("%s: '%s' must be loaded before '%s'", MAIN_TOC, pair[1], pair[2])
      end
    end
    for _, dep in ipairs({ "Core.lua", "Locales/enUS.lua" }) do
      if pos[dep] and pos[dep] > engine then
        fail("%s: '%s' must be loaded before Themes.lua", MAIN_TOC, dep)
      end
    end
  end
end

-- 7. Other flavours (e.g. TruePlayed_Vanilla.toc): identical except the Interface line.
local function significantLines(toc)
  local out = {}
  for _, line in ipairs(toc.lines) do
    local t = trim(line)
    if t ~= "" and not string.find(string.lower(t), "^##%s*interface%s*:") then
      out[#out + 1] = t
    end
  end
  return out
end

local mainLines = significantLines(main)
for _, name in ipairs(tocs) do
  if name ~= MAIN_TOC and name ~= ADDON .. ".toc" then
    local text = readFile(ROOT .. name)
    if text then
      local other = parseToc(text)
      if not other.metaLower["interface"] then
        fail("%s: missing '## Interface:' line", name)
      elseif other.metaLower["interface"] == interface then
        warn("%s: same Interface as %s", name, MAIN_TOC)
      end
      local otherLines = significantLines(other)
      local count = math.max(#mainLines, #otherLines)
      for i = 1, count do
        if mainLines[i] ~= otherLines[i] then
          fail("%s differs from %s beyond the Interface line: '%s' vs '%s'",
            name, MAIN_TOC, otherLines[i] or "<end of file>", mainLines[i] or "<end of file>")
          break
        end
      end
    end
  end
end

if errors == 0 then
  print(string.format("check_toc: OK - %d TOC file(s), %d file(s) listed, %d warning(s)",
    #tocs, #main.files, warnings))
else
  print(string.format("check_toc: %d error(s), %d warning(s)", errors, warnings))
end
os.exit(errors == 0 and 0 or 1)
