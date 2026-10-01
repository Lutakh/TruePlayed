-- tests/run.lua - offline test runner for TruePlayed (Lua 5.1 and 5.5).
-- Usage (from anywhere): lua tests/run.lua [filter] [-v]
--   filter  substring of a test file name (e.g. "core", "format")
--   -v      print every test and full tracebacks
-- See SPEC-FINAL 9.1 for the conventions.

---------------------------------------------------------------------------
-- Root and arguments
---------------------------------------------------------------------------
local ROOT
do
  local script = ((arg and arg[0]) or "tests/run.lua"):gsub("\\", "/")
  local root, n = script:gsub("tests/run%.lua$", "")
  if n == 0 then
    local r2, n2 = script:gsub("run%.lua$", "")
    if n2 > 0 then root = r2 .. "../" else root = "./" end
  end
  if root == "" then root = "./" end
  ROOT = root
end

local filter, verbose
for i = 1, (arg and #arg or 0) do
  local a = arg[i]
  if a == "-v" or a == "--verbose" then
    verbose = true
  elseif not filter then
    filter = a
  end
end

---------------------------------------------------------------------------
-- Stub and extensions
---------------------------------------------------------------------------
local Stub = dofile(ROOT .. "tests/wowstub.lua")
Stub.ROOT = ROOT

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

for _, name in ipairs({ "stub_engine", "stub_stats", "stub_ui" }) do
  local path = ROOT .. "tests/" .. name .. ".lua"
  if exists(path) then
    local installer = dofile(path)
    if type(installer) == "function" then Stub.AddInstaller(installer) end
  end
end

---------------------------------------------------------------------------
-- T API (FROZEN)
---------------------------------------------------------------------------
local T = {}
local tests = {}
local currentFile = "?"
local currentTest

local function repr(v, depth)
  depth = depth or 0
  local tv = type(v)
  if tv == "string" then return string.format("%q", v) end
  if tv ~= "table" then return tostring(v) end
  if depth > 2 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "number" or ta == "string" then return a < b end
    return tostring(a) < tostring(b)
  end)
  local parts = {}
  for i, k in ipairs(keys) do
    if i > 12 then
      parts[#parts + 1] = "..."
      break
    end
    parts[#parts + 1] = "[" .. repr(k, depth + 1) .. "]=" .. repr(v[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end
T.repr = repr

-- Returns true, or false + path + the two differing values.
local function deepEq(a, b, path)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false, path, a, b end
  for k, v in pairs(a) do
    local ok, p, x, y = deepEq(v, b[k], path .. "[" .. repr(k) .. "]")
    if not ok then return false, p, x, y end
  end
  for k, v in pairs(b) do
    if a[k] == nil then return false, path .. "[" .. repr(k) .. "]", nil, v end
  end
  return true
end

local function fail(msg)
  error(msg, 3)   -- points at the line of the test that called the assertion
end

function T.test(name, fn)
  tests[#tests + 1] = { file = currentFile, name = name, fn = fn }
end

function T.eq(actual, expected, msg)
  local ok, path, x, y = deepEq(actual, expected, "")
  if not ok then
    local where = ""
    if path ~= "" then where = string.format(" (at %s: expected %s, got %s)", path, repr(y), repr(x)) end
    fail(string.format("%s: expected %s, got %s%s", msg or "eq", repr(expected), repr(actual), where))
  end
end

function T.near(actual, expected, tol, msg)
  tol = tol or 1e-9
  if type(actual) ~= "number" or type(expected) ~= "number" or math.abs(actual - expected) > tol then
    fail(string.format("%s: expected %s +- %s, got %s", msg or "near", repr(expected), repr(tol), repr(actual)))
  end
end

function T.ok(value, msg)
  if not value then fail(string.format("%s: expected a true value, got %s", msg or "ok", repr(value))) end
end

function T.no(value, msg)
  if value then fail(string.format("%s: expected a false value, got %s", msg or "no", repr(value))) end
end

function T.match(str, pattern, msg)
  if type(str) ~= "string" or not str:find(pattern) then
    fail(string.format("%s: %s does not match %s", msg or "match", repr(str), repr(pattern)))
  end
end

function T.raises(fn, msg)
  local ok = pcall(fn)
  if ok then fail((msg or "raises") .. ": expected an error") end
end

function T.allowErrors()
  if currentTest then currentTest.allowErrors = true end
end

function T.skip(reason)
  error({ skip = true, reason = reason or "skipped" }, 0)
end

-- Grows the Lua stack and the call-info list before a measure. The full collect
-- below shrinks both (Lua 5.1 halves them, 5.4+ trims them to twice the part in
-- use), and the first deep call of the measured loop would otherwise count their
-- regrowth (about 1 KB on 5.5, possibly several KB on 5.1) as if the code under
-- test had allocated. Not a tail call: every level keeps its frame.
local function WarmStack(depth)
  if depth <= 0 then return 0 end
  local a, b, c, d, e, f, g, h = depth, depth, depth, depth, depth, depth, depth, depth
  return WarmStack(depth - 1) + a + b + c + d + e + f + g + h
end

-- KB allocated by `for i = 1, n do fn(i) end` with the collector stopped.
function T.alloc(fn, n)
  collectgarbage("collect")
  collectgarbage("stop")
  WarmStack(200)
  local before = collectgarbage("count")
  for i = 1, n do fn(i) end
  local after = collectgarbage("count")
  collectgarbage("restart")
  return after - before
end

-- Park-Miller minimal standard generator: identical sequences on 5.1 and 5.5.
function T.rng(seed)
  seed = math.floor(tonumber(seed) or 1) % 2147483647
  if seed <= 0 then seed = 1 end
  return function()
    seed = seed * 16807 % 2147483647
    return seed / 2147483647
  end
end

---------------------------------------------------------------------------
-- Declare
---------------------------------------------------------------------------
local FILES = {
  "test_format", "test_core", "test_tracker", "test_played", "test_crash",
  "test_rate_sim", "test_stats", "test_tokens", "test_ui_smoke",
  "test_graph", "test_bar",
  -- themes (design/SPEC-themes.md 8.6)
  "test_theme", "test_theme_data", "test_actuel_golden", "test_bar_theme",
  "test_tooltip_theme", "test_options_theme", "test_theme_integration",
  "test_round4_regress",
}

local passed, failed, skipped = 0, 0, 0

local function firstLine(s)
  s = tostring(s)
  return (s:match("^[^\n]*"))
end

local function report(file, name, msg)
  failed = failed + 1
  print(string.format("FAIL %s :: %s :: %s", file, name, firstLine(msg)))
  if verbose then print("  " .. tostring(msg):gsub("\n", "\n  ")) end
end

print("TruePlayed tests - " .. _VERSION .. (filter and (" - filter: " .. filter) or ""))

for _, base in ipairs(FILES) do
  if not filter or base:find(filter, 1, true) then
    local path = ROOT .. "tests/" .. base .. ".lua"
    if not exists(path) then
      report(base, "(file)", "MISSING " .. path)
    else
      local chunk, err = loadfile(path)
      if not chunk then
        report(base, "(load)", err)
      else
        currentFile = base
        local ok, err2 = xpcall(function() chunk(Stub, T) end, debug.traceback)
        if not ok then report(base, "(declare)", err2) end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
local function handler(e)
  if type(e) == "table" and e.skip then return e end
  return debug.traceback(tostring(e), 2)
end

for _, t in ipairs(tests) do
  Stub.Reset()
  currentTest = { allowErrors = false }
  local ok, err = xpcall(t.fn, handler)
  collectgarbage("restart")   -- a failed T.alloc must not leave the collector stopped
  if not ok then
    if type(err) == "table" and err.skip then
      skipped = skipped + 1
      if verbose then print(string.format("SKIP %s :: %s :: %s", t.file, t.name, tostring(err.reason))) end
    else
      report(t.file, t.name, err)
    end
  elseif #Stub.errors > 0 and not currentTest.allowErrors then
    report(t.file, t.name, "error(s) reported through geterrorhandler: " .. table.concat(Stub.errors, "\n"))
  else
    passed = passed + 1
    if verbose then print(string.format("ok   %s :: %s", t.file, t.name)) end
  end
  currentTest = nil
end

print(string.format("%d passed, %d failed, %d skipped", passed, failed, skipped))
os.exit(failed == 0 and 0 or 1)
