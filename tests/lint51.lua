-- tests/lint51.lua - Lua 5.1 portability and SPEC rules linter for TruePlayed (SPEC-FINAL 2.4, 9.5).
-- Usage (from anywhere): lua tests/lint51.lua
-- Runs on Lua 5.1 and 5.5. Exit code 0 = OK, 1 = problems found (printed as file:line: reason).
--
-- The game runs Lua 5.1; local tests run Lua 5.5. Code must behave the same in both, and
-- `luac -p` on 5.5 does not catch what 5.1 refuses. Every .lua file of the repository is
-- tokenized (comments dropped, strings kept as single tokens) and checked for:
--   * 5.2+ syntax: goto, ::labels::, //, & | ~ << >> (bitwise), <const>/<close>, the
--     5.5 `global` declaration, hexadecimal floats;
--   * string escapes other than the ones shared by 5.1 and 5.5 (\x.., \z, \u{..}, unknown
--     escapes, decimal escapes above 255) - checked inside string literals only;
--   * nested [[ inside a [[...]] string or comment (an error in Lua 5.1);
--   * 5.1-only syntax limits: `break` not last in its block, empty statements (`;;`),
--     a line starting with `(` right after an expression ("ambiguous syntax" in 5.1),
--     more than 60 upvalues in one function;
--   * API differences: table.unpack (outside `unpack or table.unpack`), table.pack,
--     table.move, math.type, math.tointeger, math.pow, math.mod, math.log with a base,
--     string.pack, string.gfind, utf8, bit32, bit, _ENV, rawlen, loadstring, setfenv,
--     getfenv, bare unpack, load() with a string, select() with a negative index,
--     os.exit(true|false), metamethods 5.1 ignores (__len, __pairs, __gc...),
--     math.random (tests must be deterministic);
--   * assignments to a for-loop control variable (read-only in Lua 5.5);
-- and, in addon files only (everything outside tests/):
--   * xpcall with extra arguments (5.1 does not pass them);
--   * a function declared with `...` that never uses `...` (5.1 builds an `arg` table);
--   * globals: reads outside the SPEC 2.3 allowlist, writes outside the SPEC 2.2 whitelist
--     (a missing `local` is the classic addon bug), os/io/print/load/setfenv...;
--   * "OnUpdate" scripts, forbidden templates, C_Timer.NewTicker outside Core.lua.
-- One explicit exception: Themes.lua reads loadstring, setfenv and load (LOADERS_OK below),
-- to compile the theme source texts in an empty environment (design/NEXT-LOT.md M3).
--
-- A finding on a line that carries the comment `lint51-ignore` is suppressed.

local MAX_UPVALUES = 60

local byte, sub, find, match = string.byte, string.sub, string.find, string.match

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

local KEYWORDS = {}
for _, w in ipairs({ "and", "break", "do", "else", "elseif", "end", "false", "for",
  "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return",
  "then", "true", "until", "while" }) do
  KEYWORDS[w] = true
end

local TWO_OPS = {
  ["=="] = true, ["~="] = true, ["<="] = true, [">="] = true, [".."] = true,
  ["//"] = true, ["::"] = true, ["<<"] = true, [">>"] = true,
}

local ONE_OPS = {}
for c in string.gmatch("+-*/%^#&~|<>=(){}[];:,.", ".") do
  ONE_OPS[c] = true
end

local BITWISE = "bitwise operators need Lua 5.3+: use arithmetic (e.g. m % 2 == 1)"
local OPS_52 = {
  ["//"] = "integer division '//' needs Lua 5.3+: use math.floor(a / b)",
  ["&"] = BITWISE, ["|"] = BITWISE, ["~"] = BITWISE, ["<<"] = BITWISE, [">>"] = BITWISE,
  ["::"] = "labels '::name::' need Lua 5.2+",
}

-- Escapes understood identically by Lua 5.1 and 5.5: \a \b \f \n \r \t \v \\ \" \'
local SIMPLE_ESC = { [97] = true, [98] = true, [102] = true, [110] = true, [114] = true,
  [116] = true, [118] = true, [92] = true, [34] = true, [39] = true }

local METAMETHODS = {
  ["__len"] = "__len is ignored for tables by Lua 5.1",
  ["__pairs"] = "__pairs is ignored by Lua 5.1",
  ["__ipairs"] = "__ipairs is ignored by Lua 5.1",
  ["__gc"] = "__gc is ignored for tables by Lua 5.1",
  ["__close"] = "__close needs Lua 5.4+",
  ["__idiv"] = "__idiv needs Lua 5.3+",
  ["__band"] = "bitwise metamethods need Lua 5.3+",
  ["__bor"] = "bitwise metamethods need Lua 5.3+",
  ["__bxor"] = "bitwise metamethods need Lua 5.3+",
  ["__shl"] = "bitwise metamethods need Lua 5.3+",
  ["__shr"] = "bitwise metamethods need Lua 5.3+",
  ["__bnot"] = "bitwise metamethods need Lua 5.3+",
}

local NEW = "does not exist in Lua 5.1 (the game)"
local GONE = "does not exist in Lua 5.5 (the local tests)"

-- Library fields, checked even through a local alias of the library.
local COMPAT_FIELDS = {
  table = {
    unpack = "does not exist in Lua 5.1: only allowed as 'unpack or table.unpack'",
    pack = NEW, move = NEW,
    getn = GONE .. ": use #t", setn = GONE, maxn = GONE, foreach = GONE, foreachi = GONE,
  },
  math = {
    type = NEW, tointeger = NEW, ult = NEW, maxinteger = NEW, mininteger = NEW,
    pow = GONE .. ": use x ^ y", mod = GONE .. ": use math.fmod or %",
    log10 = GONE .. ": use math.log(x) / math.log(10)",
    ldexp = GONE, frexp = GONE, cosh = GONE, sinh = GONE, tanh = GONE,
    random = "is not deterministic: tests use T.rng (Park-Miller, SPEC 2.4); the addon needs no randomness",
    randomseed = "is not deterministic: tests use T.rng (Park-Miller, SPEC 2.4)",
  },
  string = { pack = NEW, unpack = NEW, packsize = NEW, gfind = GONE .. ": use string.gmatch" },
  coroutine = { isyieldable = NEW, close = NEW },
}

-- Globals (only when the name is not a local).
local COMPAT_GLOBALS = {
  unpack = GONE .. ": use 'local unpack = unpack or table.unpack' or explicit indexes",
  loadstring = GONE, setfenv = GONE, getfenv = GONE, gcinfo = GONE, newproxy = GONE,
  module = GONE,
  rawlen = NEW, utf8 = NEW, _ENV = NEW,
  bit32 = "exists only in Lua 5.2: use arithmetic",
}

-- Addon files only.
local ADDON_BANNED = {
  print = "print() is not allowed in addon code: use Util.Print or Util.Debug (SPEC 2.2)",
  os = "the os library is not available to addons: use time(), date(), GetTime() (SPEC 2.3)",
  io = "the io library is not available to addons",
  debug = "the debug library is not available to addons (use debugprofilestop)",
  dofile = "dofile is not available to addons",
  loadfile = "loadfile is not available to addons",
  require = "require is not available to addons: files are listed in the .toc",
  package = "package is not available to addons",
  module = "module() is not available to addons",
  load = "load() is forbidden in addon code (SPEC 2.3)",
  loadstring = "loadstring() is forbidden in addon code (SPEC 2.3)",
  setfenv = "setfenv() is forbidden in addon code (SPEC 2.3)",
  getfenv = "getfenv() is forbidden in addon code (SPEC 2.3)",
}

-- Addon files allowed to read some of the banned globals: Themes.lua compiles the theme
-- source texts in an empty environment (loadstring + setfenv on Lua 5.1, the game; load
-- with an environment on 5.2+, the offline tests).
local LOADERS_OK = {
  ["Themes.lua"] = { loadstring = true, setfenv = true, load = true },
}

local FORBIDDEN_WOW = {
  WOW_PROJECT_ID = "WOW_PROJECT_ID reports Mainline on Forever: use ns.isForever / ns.isEra (SPEC 2.5)",
  MAX_PLAYER_LEVEL_TABLE = "MAX_PLAYER_LEVEL_TABLE is forbidden: use Util.IsMaxLevel() (SPEC 2.3)",
  EasyMenu = "EasyMenu is forbidden: use MenuUtil (SPEC 2.3)",
  C_ChatInfo = "C_ChatInfo is forbidden: chat lockdown covers every dungeon map (SPEC 5.4)",
  BreakUpLargeNumbers = "BreakUpLargeNumbers is forbidden: use Fmt.Number (SPEC 3.7)",
  GetZoneText = "GetZoneText is forbidden: zone keys come from C_Map (SPEC 4.3)",
  CopyTable = "CopyTable is not in the allowlist: use Util.DeepCopy",
}

local FORBIDDEN_STRINGS = {
  OnUpdate = "\"OnUpdate\" scripts are forbidden: use events or the 1 s ticker (SPEC 6.1)",
  OptionsSliderTemplate = "OptionsSliderTemplate is forbidden (SPEC 2.3)",
  InterfaceOptionsCheckButtonTemplate = "InterfaceOptionsCheckButtonTemplate is forbidden (SPEC 2.3)",
  UIDropDownMenuTemplate = "UIDropDownMenu templates are forbidden: use MenuUtil (SPEC 2.3)",
}

-- SPEC 2.3 allowlist, plus the Lua standard library functions the game provides.
local ALLOWED_READ = {}
for _, name in ipairs({
  "assert", "error", "ipairs", "next", "pairs", "pcall", "xpcall", "rawequal", "rawget",
  "rawset", "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type",
  "unpack", "collectgarbage", "math", "string", "table", "coroutine", "_G", "_VERSION",
  "GetTime", "time", "date", "format", "strsplit", "strtrim", "strjoin", "wipe", "tinsert",
  "tremove", "Mixin", "GetBuildInfo", "GetLocale", "C_AddOns", "GetAddOnMetadata",
  "C_Timer", "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME",
  "ChatFrameUtil", "RequestTimePlayed", "hooksecurefunc", "securecallfunction",
  "geterrorhandler", "issecretvalue", "UnitName", "UnitGUID", "UnitClass",
  "UnitFactionGroup", "UnitIsDeadOrGhost", "UnitLevel", "UnitXP", "UnitXPMax",
  "GetXPExhaustion", "IsXPUserDisabled", "GetMaxPlayerLevel", "UnitIsAFK", "IsResting",
  "UnitOnTaxi", "GetRealmName", "IsInInstance", "GetInstanceInfo", "GetRealZoneText",
  "C_Map", "Enum", "InCombatLockdown", "IsShiftKeyDown", "GetFramerate", "GetNetStats",
  "GetCVar", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "UpdateAddOnCPUUsage",
  "GetAddOnCPUUsage", "C_AddOnProfiler", "debugprofilestop", "C_XMLUtil", "Settings",
  "InterfaceOptions_AddCategory", "MenuUtil", "MinimalSliderWithSteppersMixin", "LibStub",
  "StaticPopup_Show", "StaticPopup_Hide", "StaticPopupDialogs", "SlashCmdList",
  "UISpecialFrames", "STANDARD_TEXT_FONT", "YES", "NO", "GameFontNormal",
  "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable", "BackdropTemplateMixin",
  "AddonCompartmentFrame",
  "WTFIX_BOOTSTRAP", "WTFIX_DB",   -- read only: WTFix protection warning (Core)
  "ColorPickerFrame",              -- text colour picker (Options; SetupColorPickerAndShow, as TinyTooltip)
  "ReloadUI",                      -- "Reload UI" button under the language option (Options, on click only)
  -- max level, layered as EllesmereUI's XP bar (Core Util.IsMaxLevel; guarded, may be nil)
  "IsPlayerAtEffectiveMaxLevel", "IsLevelAtEffectiveMaxLevel", "GetMaxLevelForPlayerExpansion",
  -- server level cap detection: the target of a kill without XP (Tracker; guarded, read
  -- at combat start / end and on target changes only)
  "UnitExists", "UnitIsDead", "UnitCanAttack", "UnitIsPlayer", "UnitPlayerControlled",
  "UnitIsTapDenied", "UnitClassification", "UnitCreatureType",
}) do
  ALLOWED_READ[name] = true
end

-- SPEC 2.2: the only global writes.
local WRITE_OK = {}
for _, name in ipairs({ "TruePlayedDB", "SLASH_TRUEPLAYED1", "SLASH_TRUEPLAYED2",
  "TruePlayed_OnAddonCompartmentClick", "TruePlayed_OnAddonCompartmentEnter",
  "TruePlayed_OnAddonCompartmentLeave", "TruePlayedWidget", "TruePlayedStatsFrame" }) do
  WRITE_OK[name] = true
end

local FIELD_WRITE_OK = { "SlashCmdList.TRUEPLAYED", "StaticPopupDialogs.TRUEPLAYED_ERASE_CHAR",
  "ChatFrameUtil.DisplayTimePlayed", "_G.TruePlayedDB" }

local function fieldWriteAllowed(path)
  for k = 1, #FIELD_WRITE_OK do
    local ok = FIELD_WRITE_OK[k]
    if path == ok or sub(path, 1, #ok + 1) == ok .. "." then
      return true
    end
  end
  return false
end

-- Keywords after which a `repeat ... until` condition is over (see `lingering`).
local STATEMENT_KW = { ["local"] = true, ["function"] = true, ["if"] = true, ["for"] = true,
  ["while"] = true, ["do"] = true, ["repeat"] = true, ["return"] = true, ["break"] = true,
  ["end"] = true, ["until"] = true, ["else"] = true, ["elseif"] = true, ["goto"] = true }

local EXPR_END_KW = { ["end"] = true, ["nil"] = true, ["true"] = true, ["false"] = true }

-- ---------------------------------------------------------------------------
-- Lexer: returns parallel arrays typ/val/lin ("kw", "name", "number", "string", "op", "eof")
-- ---------------------------------------------------------------------------

local function lex(src, report, ignoreLines)
  local typ, val, lin = {}, {}, {}
  local n = 0
  local pos, len, line = 1, #src, 1

  local function push(t, v, l)
    n = n + 1
    typ[n] = t
    val[n] = v
    lin[n] = l
  end

  local function countNewlines(s)
    local c = 0
    for _ in string.gmatch(s, "\n") do
      c = c + 1
    end
    return c
  end

  -- Long bracket at `p` ("[" "="* "["). Returns the position after it and its content.
  local function readLong(p, what)
    local eq = match(src, "^%[(=*)%[", p)
    local first = p + #eq + 2
    local closing = "]" .. eq .. "]"
    local s, e = find(src, closing, first, true)
    local startLine = line
    if not s then
      report(startLine, "unfinished long " .. what)
      line = line + countNewlines(sub(src, first))
      return len + 1, sub(src, first)
    end
    local content = sub(src, first, s - 1)
    if eq == "" then
      local q = find(content, "[[", 1, true)
      if q then
        report(startLine + countNewlines(sub(content, 1, q)),
          "nested '[[' inside a [[...]] " .. what .. " is an error in Lua 5.1: use [=[ ... ]=]")
      end
    end
    line = line + countNewlines(content)
    return e + 1, content
  end

  if sub(src, 1, 1) == "#" then          -- shebang line
    pos = find(src, "\n", 1, true) or (len + 1)
  end

  local badCharLine = -1
  while pos <= len do
    local c = byte(src, pos)
    if c == 10 then
      line = line + 1
      pos = pos + 1
    elseif c == 32 or c == 9 or c == 13 or c == 11 or c == 12 then
      pos = pos + 1
    elseif c == 45 and byte(src, pos + 1) == 45 then                  -- comment
      local p2 = pos + 2
      if match(src, "^%[=*%[", p2) then
        local startLine = line
        local np, content = readLong(p2, "comment")
        if find(content, "lint51-ignore", 1, true) then
          ignoreLines[startLine] = true
        end
        pos = np
      else
        local e = find(src, "\n", p2, true) or (len + 1)
        if find(sub(src, p2, e - 1), "lint51-ignore", 1, true) then
          ignoreLines[line] = true
        end
        pos = e
      end
    elseif c == 91 and match(src, "^%[=*%[", pos) then                -- long string
      local startLine = line
      local np, content = readLong(pos, "string")
      push("string", content, startLine)
      pos = np
    elseif c == 34 or c == 39 then                                     -- short string
      local startLine = line
      local p = pos + 1
      local closed = false
      while p <= len do
        local b = byte(src, p)
        if b == c then
          closed = true
          break
        elseif b == 10 then
          break
        elseif b == 92 then
          local e = byte(src, p + 1)
          if e == 10 then
            line = line + 1
            p = p + 2
          elseif e == 13 then
            p = p + 2
            if byte(src, p) == 10 then
              line = line + 1
              p = p + 1
            end
          elseif e and SIMPLE_ESC[e] then
            p = p + 2
          elseif e and e >= 48 and e <= 57 then
            local digits = match(src, "^%d%d?%d?", p + 1)
            if tonumber(digits) > 255 then
              report(line, "decimal escape \\" .. digits .. " is above 255")
            end
            p = p + 1 + #digits
          elseif e == 120 then
            report(line, "'\\x' hex escape needs Lua 5.2+ (Lua 5.1 reads it as 'x'): use decimal escapes like \\194\\160")
            p = p + 2
          elseif e == 122 then
            report(line, "'\\z' escape needs Lua 5.2+")
            p = p + 2
          elseif e == 117 then
            report(line, "'\\u{...}' escape needs Lua 5.3+: write the UTF-8 bytes as decimal escapes")
            p = p + 2
          elseif e then
            report(line, "invalid escape '\\" .. string.char(e) .. "' (Lua 5.1 drops the backslash, Lua 5.5 refuses it)")
            p = p + 2
          else
            p = p + 1
          end
        else
          p = p + 1
        end
      end
      push("string", sub(src, pos + 1, p - 1), startLine)
      if closed then
        pos = p + 1
      else
        report(startLine, "unfinished string")
        pos = p
      end
    elseif (c >= 48 and c <= 57) or (c == 46 and match(src, "^%.%d", pos)) then   -- number
      local e
      if match(src, "^0[xX]", pos) then
        local _, e1 = find(src, "^0[xX][%x%.]*", pos)
        e = e1
        if match(src, "^[pP]", e + 1) then
          local _, e2 = find(src, "^[pP][%+%-]?%x*", e + 1)
          e = e2
        end
        if find(sub(src, pos + 2, e), "[%.pP]") then
          report(line, "hexadecimal float '" .. sub(src, pos, e) .. "' needs Lua 5.2+")
        end
      else
        local _, e1 = find(src, "^%d*%.?%d*", pos)
        e = e1
        if match(src, "^[eE]", e + 1) then
          local _, e2 = find(src, "^[eE][%+%-]?%d*", e + 1)
          e = e2
        end
      end
      local _, e3 = find(src, "^[%w_]*", e + 1)       -- malformed tails (luac reports them)
      if e3 and e3 > e then
        e = e3
      end
      push("number", sub(src, pos, e), line)
      pos = e + 1
    elseif (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 then        -- name
      local _, e = find(src, "^[%w_]*", pos + 1)
      local word = sub(src, pos, e)
      push(KEYWORDS[word] and "kw" or "name", word, line)
      pos = e + 1
    else                                                                             -- operator
      local three = sub(src, pos, pos + 2)
      local two = sub(src, pos, pos + 1)
      if three == "..." then
        push("op", "...", line)
        pos = pos + 3
      elseif TWO_OPS[two] then
        push("op", two, line)
        pos = pos + 2
      else
        local ch = sub(src, pos, pos)
        push("op", ch, line)
        if not ONE_OPS[ch] and badCharLine ~= line then
          badCharLine = line
          report(line, string.format("unexpected character (byte %d) outside a string", c))
        end
        pos = pos + 1
      end
    end
  end
  push("eof", "", line)
  return { typ = typ, val = val, lin = lin, n = n }
end

-- ---------------------------------------------------------------------------
-- Analysis: scopes, functions, statements
-- ---------------------------------------------------------------------------

local function analyze(T, isAddon, report, tickers, rel)
  local typ, val, lin, n = T.typ, T.val, T.lin, T.n

  local mainFn = { line = 1, vararg = true, used = true, nUp = 0, upvals = {}, bracketBase = 0 }
  local blocks = { { kind = "main", fn = mainFn, vars = {} } }
  local nb = 1
  local brackets, nbr = {}, 0
  local pending, np = {}, 0              -- for/while headers waiting for their `do`
  local activations = {}                 -- locals that become visible after their expression list
  local lingering = nil                  -- vars of a closed repeat block, visible in `until`
  local curFn = mainFn
  local paramClose = {}
  local reportedGlobal = {}

  local function isOp(j, v)
    return typ[j] == "op" and val[j] == v
  end

  local function isKw(j, v)
    return typ[j] == "kw" and val[j] == v
  end

  local function declareIn(blk, name, line, isControl)
    blk.vars[name] = { name = name, fn = blk.fn, control = isControl, line = line }
  end

  local function resolve(name)
    if lingering and lingering[name] then
      return lingering[name]
    end
    for k = nb, 1, -1 do
      local d = blocks[k].vars[name]
      if d then
        return d
      end
    end
    return nil
  end

  local function useUpvalue(d)
    local f = curFn
    while f and f ~= d.fn do
      if not f.upvals[d] then
        f.upvals[d] = true
        f.nUp = f.nUp + 1
      end
      f = f.parent
    end
  end

  -- Index just after the bracket group opened at j.
  local function skipBalanced(j)
    local depth = 0
    while j <= n do
      local t, v = typ[j], val[j]
      if t == "eof" then
        return j
      end
      if t == "op" then
        if v == "(" or v == "[" or v == "{" then
          depth = depth + 1
        elseif v == ")" or v == "]" or v == "}" then
          depth = depth - 1
          if depth == 0 then
            return j + 1
          end
        end
      end
      j = j + 1
    end
    return j
  end

  -- Index of the `end` matching the `function` keyword at j.
  local function skipFunctionBody(j)
    local depth = 0
    while j <= n do
      local t, v = typ[j], val[j]
      if t == "eof" then
        return j
      end
      if t == "kw" then
        if v == "function" or v == "do" or v == "if" or v == "repeat" then
          depth = depth + 1
        elseif v == "end" or v == "until" then
          depth = depth - 1
          if depth == 0 then
            return j
          end
        end
      end
      j = j + 1
    end
    return j
  end

  -- Number of top-level arguments of the call whose "(" is at index j.
  local function countArgs(j)
    local depth, commas, any, k = 1, 0, false, j + 1
    while k <= n do
      local t, v = typ[k], val[k]
      if t == "eof" then
        break
      end
      if t == "kw" and v == "function" then
        any = true
        k = skipFunctionBody(k)
      elseif t == "op" and (v == "(" or v == "[" or v == "{") then
        any = true
        depth = depth + 1
      elseif t == "op" and (v == ")" or v == "]" or v == "}") then
        depth = depth - 1
        if depth == 0 then
          break
        end
      else
        any = true
        if depth == 1 and t == "op" and v == "," then
          commas = commas + 1
        end
      end
      k = k + 1
    end
    if not any then
      return 0
    end
    return commas + 1
  end

  -- First token after the expression list starting at j (start of the next statement).
  local function findExprListEnd(j)
    local k = j
    while k <= n do
      local t, v = typ[k], val[k]
      if t == "eof" then
        return k
      end
      if k > j then
        local pt, pv = typ[k - 1], val[k - 1]
        local prevEnds = pt == "name" or pt == "number" or pt == "string"
          or (pt == "op" and (pv == ")" or pv == "]" or pv == "}" or pv == "..."))
          or (pt == "kw" and EXPR_END_KW[pv])
        if prevEnds and (t == "name" or t == "number" or (t == "kw" and v ~= "and" and v ~= "or")) then
          return k
        end
      end
      if t == "op" and v == ";" then
        return k
      end
      if t == "kw" and STATEMENT_KW[v] and v ~= "function" then
        return k
      end
      if t == "kw" and v == "function" then
        k = skipFunctionBody(k) + 1
      elseif t == "op" and (v == "(" or v == "[" or v == "{") then
        k = skipBalanced(k)
      else
        k = k + 1
      end
    end
    return k
  end

  -- Is the name at index i the target of an assignment (`i = ...` or `a, i, b.c = ...`)?
  local function isAssignTarget(i)
    if nbr > curFn.bracketBase then
      return false
    end
    local j = i + 1
    while true do
      if isOp(j, "=") then
        return true
      end
      if not isOp(j, ",") or typ[j + 1] ~= "name" then
        return false
      end
      j = j + 2
      while true do
        if isOp(j, ".") and typ[j + 1] == "name" then
          j = j + 2
        elseif isOp(j, "[") then
          j = skipBalanced(j)
        else
          break
        end
      end
    end
  end

  local function controlMessage(name)
    return "assignment to the for-loop control variable '" .. name
      .. "' (read-only in Lua 5.5): copy it into a local first"
  end

  local function checkAddonGlobal(i)
    local v = val[i]
    local line = lin[i]
    if isAssignTarget(i) then
      if not WRITE_OK[v] then
        report(line, "assigns the global '" .. v .. "': missing 'local'? (only the globals of SPEC 2.2 may be written)")
      end
      return
    end
    -- Field writes through a global: G.a.b = ... / G["a"] = ...
    local path, j = v, i + 1
    while true do
      if isOp(j, ".") and typ[j + 1] == "name" then
        path = path .. "." .. val[j + 1]
        j = j + 2
      elseif isOp(j, "[") and typ[j + 1] == "string" and isOp(j + 2, "]") then
        path = path .. "." .. val[j + 1]
        j = j + 3
      else
        break
      end
    end
    if j > i + 1 and isOp(j, "=") and nbr <= curFn.bracketBase and not fieldWriteAllowed(path) then
      report(line, "assigns '" .. path .. "': only the fields listed in SPEC 2.2 may be written")
    end
    if reportedGlobal[v] then
      return
    end
    local msg = ADDON_BANNED[v] or FORBIDDEN_WOW[v]
    if not msg and find(v, "^UIDropDownMenu") then
      msg = "UIDropDownMenu is forbidden for new code: use MenuUtil (SPEC 2.3)"
    end
    if not msg and not ALLOWED_READ[v] and not WRITE_OK[v] then
      msg = "global '" .. v .. "' is not in the SPEC 2.3 allowlist (typo, missing 'local', or a local declared further down?)"
    end
    if msg then
      reportedGlobal[v] = true
      report(line, msg)
    end
  end

  local loadersOk = isAddon and LOADERS_OK[rel] or nil

  local function checkGlobal(i)
    local v = val[i]
    local line = lin[i]
    if loadersOk and loadersOk[v] and not isAssignTarget(i) then
      return                              -- read only (an assignment is still reported)
    end
    if v == "global" then
      local nt, nv = typ[i + 1], val[i + 1]
      if nt == "name" or (nt == "kw" and nv == "function") or (nt == "op" and (nv == "*" or nv == "<")) then
        report(line, "'global' declarations need Lua 5.5")
        return
      end
    end
    local compat = COMPAT_GLOBALS[v]
    if compat and not (isAddon and ADDON_BANNED[v]) then
      local idiom = v == "unpack" and isKw(i + 1, "or") and val[i + 2] == "table"
        and isOp(i + 3, ".") and val[i + 4] == "unpack"
      if not idiom and (v ~= "module" or isOp(i + 1, "(")) then
        report(line, "'" .. v .. "' " .. compat)
      end
    end
    if v == "load" and (typ[i + 1] == "string" or (isOp(i + 1, "(") and typ[i + 2] == "string")) then
      report(line, "load() with a string needs Lua 5.2+ (it is loadstring in 5.1)")
    end
    -- Addon code only: test helpers may feature-detect extra xpcall arguments at run time.
    if isAddon and v == "xpcall" and isOp(i + 1, "(") and countArgs(i + 1) > 2 then
      report(line, "xpcall(f, handler, args...): Lua 5.1 does not pass the extra arguments; wrap the call in a function")
    end
    if v == "select" and isOp(i + 1, "(") and isOp(i + 2, "-") then
      report(line, "select() with a negative index needs Lua 5.2+")
    end
    if isAddon then
      checkAddonGlobal(i)
    end
  end

  local function handleName(i)
    local v = val[i]
    local line = lin[i]
    if METAMETHODS[v] then
      report(line, METAMETHODS[v])
    end
    local pt, pv = typ[i - 1], val[i - 1]
    if pt == "op" and (pv == "." or pv == ":") then
      return                                              -- field or method name
    end
    if isOp(i + 1, "=") and nbr > curFn.bracketBase and brackets[nbr] == "{"
      and pt == "op" and (pv == "{" or pv == "," or pv == ";") then
      return                                              -- key of a table constructor
    end
    if isOp(i + 1, ".") and typ[i + 2] == "name" then
      local field = val[i + 2]
      local lib = COMPAT_FIELDS[v]
      local msg = lib and lib[field]
      if msg and not (v == "table" and field == "unpack" and isKw(i - 1, "or")
        and typ[i - 2] == "name" and val[i - 2] == "unpack") then
        report(line, v .. "." .. field .. " " .. msg)
      end
      if v == "math" and field == "log" and isOp(i + 3, "(") and countArgs(i + 3) >= 2 then
        report(line, "math.log(x, base): Lua 5.1 ignores the base; use math.log(x) / math.log(base)")
      elseif v == "os" and field == "exit" and isOp(i + 3, "(") and (isKw(i + 4, "true") or isKw(i + 4, "false")) then
        report(line, "os.exit(true|false) raises an error in Lua 5.1: pass 0 or 1")
      elseif v == "bit" then
        report(line, "the 'bit' library is missing in the tests: use arithmetic (SPEC 2.4)")
      elseif isAddon and v == "C_Timer" and field == "NewTicker" then
        tickers[#tickers + 1] = { rel = rel, line = line }
      end
    end
    local d = resolve(v)
    if d then
      if d.fn ~= curFn then
        useUpvalue(d)
      end
      if d.control and isAssignTarget(i) then
        report(line, controlMessage(v))
      end
      return
    end
    checkGlobal(i)
  end

  local function handleOp(i)
    local v = val[i]
    if v == "(" or v == "[" or v == "{" then
      if v == "(" and i > 1 and lin[i] ~= lin[i - 1] then
        local pt, pv = typ[i - 1], val[i - 1]
        if pt == "name" or (pt == "op" and (pv == ")" or pv == "]")) then
          report(lin[i], "a line starting with '(' continues the previous expression: Lua 5.1 stops"
            .. " with 'ambiguous syntax', Lua 5.5 silently makes a call; join the lines or add ';'")
        end
      end
      nbr = nbr + 1
      brackets[nbr] = v
    elseif v == ")" or v == "]" or v == "}" then
      if nbr > curFn.bracketBase then
        brackets[nbr] = nil
        nbr = nbr - 1
      end
    elseif v == "..." then
      curFn.used = true
    elseif v == ";" then
      local pt, pv = typ[i - 1], val[i - 1]
      if i == 1 or paramClose[i - 1] or (pt == "op" and pv == ";")
        or (pt == "kw" and (pv == "do" or pv == "then" or pv == "else" or pv == "repeat")) then
        report(lin[i], "empty statement ';' is a syntax error in Lua 5.1")
      end
    elseif OPS_52[v] then
      report(lin[i], OPS_52[v])
    elseif v == "<" and typ[i + 1] == "name" and (val[i + 1] == "const" or val[i + 1] == "close")
      and isOp(i + 2, ">") then
      report(lin[i], "'<" .. val[i + 1] .. ">' attribute needs Lua 5.4+")
    end
  end

  -- `function` keyword at i (statement or expression). Returns the next index to scan.
  local function parseFunction(i, isLocal)
    local j = i + 1
    local isMethod = false
    if typ[j] == "name" then
      if isLocal then
        j = j + 1
      else
        local first = j
        local path = val[j]
        j = j + 1
        while (isOp(j, ".") or isOp(j, ":")) and typ[j + 1] == "name" do
          if val[j] == ":" then
            isMethod = true
          end
          path = path .. "." .. val[j + 1]
          j = j + 2
        end
        local d = resolve(val[first])
        if d then
          if d.fn ~= curFn then
            useUpvalue(d)
          end
          if d.control and j == first + 1 then
            report(lin[first], controlMessage(val[first]))
          end
        elseif isAddon then
          local base = val[first]
          if j == first + 1 then
            if not WRITE_OK[base] then
              report(lin[first], "defines the global function '" .. base .. "': missing 'local'? (SPEC 2.2)")
            end
          elseif not fieldWriteAllowed(path) then
            if ALLOWED_READ[base] or WRITE_OK[base] then
              report(lin[first], "defines '" .. path .. "': only the fields listed in SPEC 2.2 may be written")
            else
              report(lin[first], "'" .. base .. "' is not a local: 'function " .. path .. "' writes into a global")
            end
          end
        end
      end
    end
    local fn = { line = lin[i], vararg = false, used = false, nUp = 0, upvals = {},
      bracketBase = nbr, parent = curFn }
    local params = {}
    if isOp(j, "(") then
      j = j + 1
      while typ[j] ~= "eof" and not isOp(j, ")") do
        if typ[j] == "name" then
          params[#params + 1] = j
        elseif isOp(j, "...") then
          fn.vararg = true
        end
        j = j + 1
      end
      paramClose[j] = true
      j = j + 1
    end
    nb = nb + 1
    local blk = { kind = "function", fn = fn, vars = {} }
    blocks[nb] = blk
    curFn = fn
    if isMethod then
      declareIn(blk, "self", lin[i], false)
    end
    for k = 1, #params do
      local pj = params[k]
      declareIn(blk, val[pj], lin[pj], false)
    end
    return j
  end

  local function closeBlock(line, word)
    if nb <= 1 then
      report(line, "'" .. word .. "' without an open block")
      return
    end
    local b = blocks[nb]
    blocks[nb] = nil
    nb = nb - 1
    if b.kind == "function" then
      local fn = b.fn
      if isAddon and fn.vararg and not fn.used then
        report(fn.line, "function declared with '...' never uses it: Lua 5.1 builds an 'arg' table"
          .. " on every call (SPEC 2.1)")
      end
      if fn.nUp > MAX_UPVALUES then
        report(fn.line, string.format("function uses %d upvalues; Lua 5.1 allows at most %d"
          .. " (group state in a table)", fn.nUp, MAX_UPVALUES))
      end
      while nbr > fn.bracketBase do
        brackets[nbr] = nil
        nbr = nbr - 1
      end
      curFn = fn.parent
    elseif b.kind == "repeat" and word == "until" then
      lingering = b.vars
    end
    while np > 0 and pending[np].depth > nb do
      pending[np] = nil
      np = np - 1
    end
  end

  local i = 1
  while i <= n do
    local acts = activations[i]
    if acts then
      activations[i] = nil
      for a = 1, #acts do
        local act = acts[a]
        for k = 1, #act.names do
          local nj = act.names[k]
          declareIn(act.blk, val[nj], lin[nj], false)
        end
      end
    end
    local t, v = typ[i], val[i]
    if t == "eof" then
      break
    end
    if lingering and ((t == "kw" and STATEMENT_KW[v]) or (t == "op" and v == ";")) then
      lingering = nil
    end
    if t == "kw" then
      if v == "function" then
        i = parseFunction(i, false)
      elseif v == "local" then
        if isKw(i + 1, "function") then
          if typ[i + 2] == "name" then
            declareIn(blocks[nb], val[i + 2], lin[i + 2], false)
          end
          i = parseFunction(i + 1, true)
        else
          local names, j = {}, i + 1
          while typ[j] == "name" do
            names[#names + 1] = j
            j = j + 1
            if isOp(j, "<") and typ[j + 1] == "name" and isOp(j + 2, ">") then
              report(lin[j], "'<" .. val[j + 1] .. ">' attribute needs Lua 5.4+")
              j = j + 3
            end
            if isOp(j, ",") then
              j = j + 1
            else
              break
            end
          end
          if isOp(j, "=") then
            -- The new locals are visible only after their expression list.
            local at = findExprListEnd(j + 1)
            local queued = activations[at]
            if not queued then
              queued = {}
              activations[at] = queued
            end
            queued[#queued + 1] = { blk = blocks[nb], names = names }
          else
            for k = 1, #names do
              local nj = names[k]
              declareIn(blocks[nb], val[nj], lin[nj], false)
            end
          end
          i = j
        end
      elseif v == "for" then
        local names, j = {}, i + 1
        while typ[j] == "name" do
          names[#names + 1] = j
          j = j + 1
          if isOp(j, ",") then
            j = j + 1
          else
            break
          end
        end
        np = np + 1
        pending[np] = { names = names, depth = nb, br = nbr }
        i = j
      elseif v == "while" then
        np = np + 1
        pending[np] = { names = false, depth = nb, br = nbr }
        i = i + 1
      elseif v == "do" then
        local p = pending[np]
        local blk
        if p and p.depth == nb and p.br == nbr then
          pending[np] = nil
          np = np - 1
          blk = { kind = "loop", fn = curFn, vars = {} }
          if p.names then
            for k = 1, #p.names do
              local nj = p.names[k]
              declareIn(blk, val[nj], lin[nj], k == 1)
            end
          end
        else
          blk = { kind = "do", fn = curFn, vars = {} }
        end
        nb = nb + 1
        blocks[nb] = blk
        i = i + 1
      elseif v == "if" or v == "repeat" then
        nb = nb + 1
        blocks[nb] = { kind = v, fn = curFn, vars = {} }
        i = i + 1
      elseif v == "then" or v == "else" or v == "elseif" then
        local b = blocks[nb]
        if b.kind == "if" then
          b.vars = {}                  -- each branch is a new scope
        end
        i = i + 1
      elseif v == "end" or v == "until" then
        closeBlock(lin[i], v)
        i = i + 1
      elseif v == "break" then
        local j = i + 1
        while isOp(j, ";") do
          j = j + 1
        end
        local nt, nv = typ[j], val[j]
        if not (nt == "eof" or (nt == "kw" and (nv == "end" or nv == "else" or nv == "elseif" or nv == "until"))) then
          report(lin[i], "'break' must be the last statement of its block in Lua 5.1: write 'do break end'")
        end
        i = i + 1
      elseif v == "goto" then
        report(lin[i], "'goto' needs Lua 5.2+")
        i = i + 1
      else
        i = i + 1
      end
    elseif t == "name" then
      handleName(i)
      i = i + 1
    elseif t == "op" then
      handleOp(i)
      i = i + 1
    else
      if t == "string" and isAddon and FORBIDDEN_STRINGS[v] then
        report(lin[i], FORBIDDEN_STRINGS[v])
      end
      i = i + 1
    end
  end
  if nb > 1 then
    report(lin[n] or 1, "unclosed block: missing 'end'")
  end
end

-- ---------------------------------------------------------------------------
-- Files
-- ---------------------------------------------------------------------------

local function detectRoot()
  local a0 = (arg and arg[0]) or ""
  a0 = string.gsub(a0, "\\", "/")
  local base = match(a0, "^(.-)tests/[^/]+%.lua$")
  if base then
    if base == "" then
      return "./"
    end
    return base
  end
  local dir = match(a0, "^(.*/)[^/]*$")
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
    if find(p, "^%.") or find(p, "/%.") or find(p, "^tests/baseline/") then
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

local ROOT = detectRoot()
local files, listed = listFiles(ROOT)
if not listed then
  print("lint51: could not list the repository files (no git, no find)")
  os.exit(1)
end

local total, bad, checked = 0, 0, 0
local tickers = {}

local function printFindings(rel, findings)
  table.sort(findings, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.seq < b.seq
  end)
  for k = 1, #findings do
    local f = findings[k]
    print(string.format("%s:%d: %s", rel, f.line, f.msg))
  end
end

for _, rel in ipairs(files) do
  if find(rel, "%.lua$") then
    local src = readFile(ROOT .. rel)
    if src then
      checked = checked + 1
      local raw, seen = {}, {}
      local function report(line, msg)
        local key = line .. ":" .. msg
        if not seen[key] then
          seen[key] = true
          raw[#raw + 1] = { line = line, msg = msg, seq = #raw + 1 }
        end
      end
      local ignoreLines = {}
      local T = lex(src, report, ignoreLines)
      analyze(T, not find(rel, "^tests/"), report, tickers, rel)
      local findings = {}
      for k = 1, #raw do
        if not ignoreLines[raw[k].line] then
          findings[#findings + 1] = raw[k]
        end
      end
      if #findings > 0 then
        bad = bad + 1
        total = total + #findings
        printFindings(rel, findings)
      end
    end
  end
end

-- SPEC 6.1: exactly one repeating timer, created by Core.lua.
for k = 1, #tickers do
  local tk = tickers[k]
  if tk.rel ~= "Core.lua" or k > 1 then
    total = total + 1
    print(string.format("%s:%d: C_Timer.NewTicker: the 1 s ticker of Core.lua is the only repeating"
      .. " timer allowed (SPEC 6.1)", tk.rel, tk.line))
  end
end

if checked == 0 then
  print("lint51: no .lua file found under " .. ROOT)
  os.exit(1)
end

if total == 0 then
  print(string.format("lint51: OK - %d file(s) checked", checked))
else
  print(string.format("lint51: %d problem(s) in %d file(s), %d file(s) checked", total, bad, checked))
end
os.exit(total == 0 and 0 or 1)
