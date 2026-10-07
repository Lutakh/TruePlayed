-- media-src/curseforge/scene.lua - exports what the addon DRAWS as a JSON scene, for the
-- CurseForge images (render-scene.js turns a scene into a PNG). Not a test: it loads the
-- addon in the offline stub (tests/wowstub.lua + tests/stub_ui.lua, real text widths from
-- tests/fontmetrics.lua), plays a believable leveling character from level 1 (see
-- Simulate below), then writes every shown texture and font string of the asked view.
--
-- Usage (from the root of the checkout):
--   TZ=UTC lua media-src/curseforge/scene.lua <scenario> <theme> <out.json>
-- scenario: bar | tip | tipshift | tooltip | tooltipshift | hero | heroshift | levels |
--           zones | sessions
--   bar       the XP bar alone
--   tip       the bar + its short tooltip (shift: the detailed one)
--   tooltip   the tooltip alone (the private frame of the themed tooltips)
--   hero      like tip, the bar 600 wide at the bottom of the screen
--   levels / zones / sessions   the statistics window on that tab
-- theme: futuriste | actuel | heroic | pixel | warrior | paladin | hunter | rogue |
--        priest | shaman | mage | warlock | druid
--
-- The scene: coordinates in WoW UI units (UIParent 1920 x 1080), origin top-left, y down.
-- items[] are in drawing order (strata, frame level, frame, draw layer, sublayer, creation).

local ROOT
do
  local script = ((arg and arg[0]) or "media-src/curseforge/scene.lua"):gsub("\\", "/")
  local root, n = script:gsub("media%-src/curseforge/scene%.lua$", "")
  if n == 0 or root == "" then root = "./" end
  ROOT = root
end

local SCENARIO, THEME, OUT = arg[1], arg[2], arg[3]
if not (SCENARIO and THEME and OUT) then
  io.stderr:write("usage: lua media-src/curseforge/scene.lua <scenario> <theme> <out.json>\n")
  os.exit(2)
end

local Stub = dofile(ROOT .. "tests/wowstub.lua")
Stub.ROOT = ROOT
Stub.AddInstaller(dofile(ROOT .. "tests/stub_ui.lua"))
local FM = dofile(ROOT .. "tests/fontmetrics.lua")
local Width = FM.New(ROOT)

local format, concat, floor = string.format, table.concat, math.floor
local UIParentObj = rawget(_G, "UIParent")

---------------------------------------------------------------------------
-- Set* methods the stub answers with a no-op (SetWordWrap...): recorded (last arguments)
---------------------------------------------------------------------------
do
  local methods = getmetatable(UIParentObj).__index
  local mt = getmetatable(methods)
  local baseIndex = mt.__index
  local recorders = {}
  mt.__index = function(t, k)
    local f = baseIndex(t, k)
    if f and type(k) == "string" and k:sub(1, 3) == "Set" then
      local rec = recorders[k]
      if not rec then
        rec = function(self, ...)
          local u = rawget(self, "_unk")
          if not u then
            u = {}
            rawset(self, "_unk", u)
          end
          u[k] = { ... }
          u[k].n = select("#", ...)
        end
        recorders[k] = rec
      end
      return rec
    end
    return f
  end
end

---------------------------------------------------------------------------
-- World: Alliance zones of a level 1-18 route (Classic uiMapIDs) and instances
---------------------------------------------------------------------------
local EK = 1415
local MAPS = {
  [1429] = { mapType = 3, parentMapID = EK, name = "Elwynn Forest" },
  [1426] = { mapType = 3, parentMapID = EK, name = "Dun Morogh" },
  [1436] = { mapType = 3, parentMapID = EK, name = "Westfall" },
  [1432] = { mapType = 3, parentMapID = EK, name = "Loch Modan" },
  [1433] = { mapType = 3, parentMapID = EK, name = "Redridge Mountains" },
  [1431] = { mapType = 3, parentMapID = EK, name = "Duskwood" },
  [1421] = { mapType = 3, parentMapID = EK, name = "Silverpine Forest" },
  [1455] = { mapType = 3, parentMapID = EK, name = "Ironforge" },
  [291]  = { mapType = 4, parentMapID = 1436, name = "The Deadmines" },
  [310]  = { mapType = 4, parentMapID = 1421, name = "Shadowfang Keep" },
}
local ZONE = { elwynn = 1429, westfall = 1436, loch = 1432, redridge = 1433, duskwood = 1431,
               stormwind = 1453, ironforge = 1455 }
local INST = { deadmines = { 36, 291 }, sfk = { 33, 310 } }

---------------------------------------------------------------------------
-- Simulation helpers
---------------------------------------------------------------------------
local ns
local rng = 12345
local function Rand()            -- deterministic (Park-Miller, exact in doubles), 0..1
  rng = (rng * 16807) % 2147483647
  return rng / 2147483647
end

local function Go(zone)
  Stub.SetMap(ZONE[zone] or zone)
  Stub.Advance(1)
end

local function Afk(sec)
  Stub.SetAFK(true)
  Stub.Advance(sec, 5)
  Stub.SetAFK(false)
  Stub.Advance(1)
end

local function MobXP(lvl, diff)
  return floor((5 * lvl + 45) * (1 + 0.05 * diff) + 0.5)
end

-- Plays `sec` seconds in the current place: a kill every `every` seconds (mob levels
-- `diffLo`..`diffHi` above the player), a quest every `qEvery` seconds worth `qXP`
-- (a fraction of the level when < 1), stopping early at `untilLevel`.
local sinceKill, killGap = 0, nil   -- the kill rhythm carries over between Play calls
local function Play(sec, o)
  o = o or {}
  local every, qEvery = o.every or 90, o.qEvery or 0
  if not killGap or killGap > every * 1.5 then killGap = every * (0.6 + 0.8 * Rand()) end
  local t, nextQuest = 0, qEvery > 0 and qEvery or math.huge
  while t < sec do
    local nextKill = t + math.max(0, killGap - sinceKill)
    local stop = math.min(nextKill, nextQuest, sec)
    local step = stop - t
    if step > 0 then
      Stub.Advance(step, 2)
      t = t + step
      sinceKill = sinceKill + step
    end
    if o.untilLevel and Stub.player.level >= o.untilLevel then return t end
    if sinceKill >= killGap - 1e-6 then
      local lvl = Stub.player.level
      local d = (o.diffLo or 0) + floor(Rand() * ((o.diffHi or 2) - (o.diffLo or 0) + 1))
      Stub.Kill(MobXP(lvl, d))
      sinceKill, killGap = 0, every * (0.6 + 0.8 * Rand())
    end
    if t >= nextQuest then
      local q = o.qXP or 0.08
      if q < 1 then q = floor(Stub.player.max * q / 5) * 5 end
      Stub.GrantXP(q, { quest = "Quest" })
      nextQuest = t + qEvery
    end
    if o.untilLevel and Stub.player.level >= o.untilLevel then return t end
  end
  return t
end

-- Plays until the next level, with roughly `minutes` of active play for it.
local function Level(minutes, o)
  o = o or {}
  local p = Stub.player
  local target = p.level + 1
  local need = p.max - p.xp
  local sec = minutes * 60
  local avgMob = MobXP(p.level, ((o.diffLo or 0) + (o.diffHi or 2)) / 2)
  local qShare = o.qShare or 0.45
  local every = sec * avgMob / (need * (1 - qShare)) * (o.restK or 1)
  local qEvery = o.qEvery or 600
  local qXP = floor(need * qShare / (sec / qEvery) / 5) * 5
  local guard = 0
  while p.level < target and guard < 50 do
    Play(sec, { every = every, qEvery = qEvery, qXP = qXP, diffLo = o.diffLo, diffHi = o.diffHi,
                untilLevel = target })
    guard = guard + 1
  end
end

local function Inn(sec, afkSec)
  Stub.SetResting(true)
  Stub.Advance(sec, 5)
  if afkSec and afkSec > 0 then Afk(afkSec) end
  Stub.SetResting(false)
  Stub.Advance(1)
end

local function City(zone, sec, afkSec)
  Go(zone)
  Stub.SetResting(true)
  Stub.Advance(sec, 5)
  if afkSec and afkSec > 0 then Afk(afkSec) end
  Stub.SetResting(false)
end

local function Taxi(sec)
  Stub.SetTaxi(true)
  Stub.Advance(sec, 5)
  Stub.SetTaxi(false)
  Stub.Advance(1)
end

local function Dungeon(key, minutes, kills, back)
  local id, map = INST[key][1], INST[key][2]
  Stub.SetInstance(true, "party", id, map)
  Stub.Advance(1)
  local per = minutes * 60 / kills
  for i = 1, kills do
    Stub.Advance(per, 2)
    local lvl = Stub.player.level
    Stub.Kill(MobXP(lvl, 2 + (i % 3)))
  end
  Stub.SetInstance(false, "none", 0, ZONE[back])
  Stub.Advance(1)
end

-- Logs out and back in `offline` seconds later; the rest pool grows as in the game
-- (5 % of the level per 8 h in an inn, 1/4 of it outside, capped at 1.5 levels).
local TRACE = os.getenv("SCENE_TRACE")
local function Trace(label)
  if not TRACE then return end
  local p = Stub.player
  io.stderr:write(format("%-10s lvl %2d %5.1f%% rest %6d played %7.0f\n", label, p.level,
    100 * p.xp / p.max, floor(p.rest or 0), Stub.server.total))
end

local function Relog(offline, inInn)
  Trace("logout")
  local p = Stub.player
  local gain = p.max * 0.05 * (offline / 28800) * (inInn and 1 or 0.25)
  p.rest = math.min((p.rest or 0) + floor(gain), floor(p.max * 1.5))
  ns = Stub.Restart({ offline = offline, settle = 3 })
  Stub.Advance(2)
end

---------------------------------------------------------------------------
-- The character: Lutak, Alliance mage, levels 1 to 18 over 10 days. The last session
-- (1 h 40) is in Duskwood: level 17 -> 18, then 42 % into 18 with a big rest pool.
---------------------------------------------------------------------------
local TARGET_PLAYED = 2 * 86400 + 4 * 3600 + 7 * 60   -- 2d 4h 7m at the end
local LAST_SESSION = 6000

local function Simulate(theme)
  Stub.Reset()
  Stub.InstallUI({ ldb = false })
  for id, m in pairs(MAPS) do Stub.maps[id] = m end
  Stub.theme = theme
  local p = Stub.player
  p.faction, p.class, p.classLocalized = "Alliance", "MAGE", "Mage"
  p.level, p.xp, p.max, p.rest = 1, 0, Stub.xpTable[1], 0
  p.mapID, p.zoneText = ZONE.elwynn, "Elwynn Forest"
  Stub.server.total, Stub.server.levelPlayed = 0, 0
  ns = Stub.LoadAddon()
  Stub.LoginSequence({ settle = 3 })
  ns.Core.SetSetting("widget.locked", true)
  Stub.Advance(1)

  local K = 2.35                   -- minutes of active play per planned minute (a casual pace)
  local function Lv(minutes, o) Level(minutes * K, o) end

  -- Day 1: Northshire and Elwynn, levels 1-5
  Go("elwynn")
  Lv(10); Lv(15); Afk(6 * 60); Lv(20); Lv(26)
  Inn(5 * 60, 25 * 60)
  Relog(20 * 3600, true)

  -- Day 2: Elwynn, levels 5-8, Stormwind (training, auction house)
  Go("elwynn"); Lv(32); Afk(18 * 60); Lv(40)
  Taxi(3 * 60); City("stormwind", 22 * 60, 12 * 60)
  Go("elwynn"); Lv(46)
  Inn(4 * 60, 40 * 60)
  Relog(22 * 3600, true)

  -- Day 3: Elwynn then Westfall, levels 8-10
  Go("elwynn"); Lv(52); Afk(25 * 60)
  Go("westfall"); Lv(58, { diffHi = 1 })
  Inn(6 * 60, 30 * 60)
  Relog(26 * 3600, true)

  -- Day 4: Westfall, levels 10-12
  Go("westfall"); Lv(64, { diffHi = 1 }); Afk(20 * 60); Lv(70)
  Taxi(4 * 60); City("stormwind", 15 * 60, 20 * 60)
  Relog(30 * 3600, true)

  -- Day 5: Loch Modan and Ironforge, levels 12-13
  Taxi(6 * 60); City("ironforge", 12 * 60)
  Go("loch"); Lv(76); Afk(30 * 60)
  Inn(5 * 60, 35 * 60)
  Relog(20 * 3600, true)

  -- Day 6: Westfall, level 13-14, The Deadmines at 14
  Go("westfall"); Lv(82, { diffHi = 1 })
  Dungeon("deadmines", 72, 40, "westfall")
  Taxi(3 * 60); City("stormwind", 35 * 60, 45 * 60)
  Relog(40 * 3600, true)

  -- Day 7: Redridge, levels 14-16
  Go("redridge"); Lv(90); Afk(40 * 60); Lv(100)
  Inn(8 * 60, 50 * 60)
  Relog(20 * 3600, true)

  -- Day 8: Shadowfang Keep at 16, Redridge, level 17
  Taxi(9 * 60)
  Dungeon("sfk", 64, 34, "duskwood")
  Go("redridge"); Lv(110); Afk(35 * 60)
  Taxi(3 * 60); City("stormwind", 28 * 60, 25 * 60)
  Relog(18 * 3600, true)

  -- Day 9: level 17 in Duskwood until 8 900 / 17 700, then a long break in Darkshire's inn
  -- (the rest pool fills)
  Go("duskwood")
  while p.xp < 7950 do Play(300, { every = 120, qEvery = 700, qXP = 500, diffLo = 2, diffHi = 4 }) end
  -- idle in the inn so that the account reaches the target /played after the last session
  local idle = TARGET_PLAYED - Stub.server.total - LAST_SESSION - 120
  if TRACE then io.stderr:write(format("idle in the inn: %.0f s\n", idle)) end
  Inn(60, math.max(0, idle - 60))
  p.rest = 0
  Relog(7 * 86400, true)
  p.rest = 26550
  Stub.Fire("UPDATE_EXHAUSTION")
  Stub.Advance(1)

  -- Last session: 1 h 40 in Duskwood (a kill every ~2 min, a quest every ~10 min, a short
  -- AFK), level 17 -> 18, ending 42 % into 18 (the last quest of the session tops it up).
  Go("duskwood")
  local GOAL = floor(Stub.xpTable[18] * 0.42 / 5) * 5
  local x0 = p.xp
  local total = (Stub.xpTable[17] - x0) + GOAL
  local function Gained()
    if p.level >= 18 then return Stub.xpTable[17] - x0 + p.xp end
    return p.xp - x0
  end
  local t, qx, afkDone = 0, 0, false
  while t < LAST_SESSION - 120 do
    Play(120, { every = 108, diffLo = 3, diffHi = 5 })
    t, qx = t + 120, qx + 120
    if qx >= 480 and Gained() + 500 < total * t / LAST_SESSION then
      Stub.GrantXP(floor(p.max * 0.03 / 5) * 5, { quest = "Quest" })
      qx = 0
    end
    if not afkDone and t >= 2700 then
      Afk(5 * 60)
      t, afkDone = t + 300, true
    end
  end
  Trace("pre-end")
  if p.level == 18 and p.xp < GOAL then Stub.GrantXP(GOAL - p.xp, { quest = "Quest" }) end
  if t < LAST_SESSION then Stub.Advance(LAST_SESSION - t, 2) end
  Stub.Advance(1)
  Trace("end")
  return ns
end

---------------------------------------------------------------------------
-- Geometry: anchors solved as the game does (two opposite anchors set the size);
-- font strings without a size take the size of their text (real font widths).
---------------------------------------------------------------------------
local AN = { TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 }, LEFT = { 0, 0.5 },
             CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 }, BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 },
             BOTTOMRIGHT = { 1, 0 } }

local FONT_OBJECTS = {
  GameFontNormal = { "Fonts\\FRIZQT__.TTF", 12, "", { 1, 0.82, 0, 1 } },
  GameFontNormalSmall = { "Fonts\\FRIZQT__.TTF", 10, "", { 1, 0.82, 0, 1 } },
  GameFontHighlight = { "Fonts\\FRIZQT__.TTF", 12, "", { 1, 1, 1, 1 } },
  GameFontHighlightSmall = { "Fonts\\FRIZQT__.TTF", 10, "", { 1, 1, 1, 1 } },
  GameFontDisable = { "Fonts\\FRIZQT__.TTF", 12, "", { 0.5, 0.5, 0.5, 1 } },
}

local function FontOf(o)
  local fo = rawget(o, "_fontObject")
  local foName = type(fo) == "table" and rawget(fo, "_name") or fo
  local def = FONT_OBJECTS[foName]
  local font, size, flags = rawget(o, "_font"), rawget(o, "_fontSize"), rawget(o, "_fontFlags")
  if not font then
    if def then font, size, flags = def[1], def[2], def[3] else font, size, flags = "Fonts\\FRIZQT__.TTF", 12, "" end
  end
  return font, size or 12, flags or "", def
end

local function PlainText(s)
  return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Lines(text)
  local out = {}
  for line in (PlainText(text) .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = line end
  return out
end

local function Unk(o, k)
  local u = rawget(o, "_unk")
  return u and u[k]
end

local function WordWrap(o)
  local w = Unk(o, "SetWordWrap")
  if w then return w[1] and true or false end
  return true
end

local function Solve(list, size)
  local lo, hi = list[1], list[1]
  for i = 2, #list do
    local e = list[i]
    if e[1] < lo[1] then lo = e end
    if e[1] > hi[1] then hi = e end
  end
  if hi[1] > lo[1] then
    local s = (hi[2] - lo[2]) / (hi[1] - lo[1])
    return lo[2] - s * lo[1], s, true
  end
  return lo[2] - size * lo[1], size, false
end

local scrollParent = {}          -- [scroll child] = scroll frame
local rectCache = {}

local TrueRect
local function NaturalSize(o, wFixed)
  local font, size = FontOf(o)
  local lines = Lines(rawget(o, "_text"))
  local w = 0
  for i = 1, #lines do
    local lw = Width(font, size, lines[i])
    if lw > w then w = lw end
  end
  local n = #lines
  local bound = wFixed or (rawget(o, "_width") or 0)
  if bound > 0 and w > bound + 0.5 and WordWrap(o) then
    n = 0
    for i = 1, #lines do n = n + math.max(1, math.ceil(Width(font, size, lines[i]) / bound)) end
  end
  return w, n * size + (n - 1) * 2
end

TrueRect = function(o, depth)
  depth = (depth or 0) + 1
  if depth > 40 or o == nil then return nil end
  if rawget(o, "_isUIParent") then return 0, 0, rawget(o, "_width"), rawget(o, "_height") end
  local c = rectCache[o]
  if c then return c[1], c[2], c[3], c[4] end
  local sp = scrollParent[o]
  if sp then
    local l, b, _, h = TrueRect(sp, depth)
    if not l then return nil end
    local v = rawget(sp, "_vscroll") or 0
    local cw, ch = rawget(o, "_width") or 0, rawget(o, "_height") or 0
    local r = { l, b + h - ch + v, cw, ch }
    rectCache[o] = r
    return r[1], r[2], r[3], r[4]
  end
  local pts = rawget(o, "_points")
  if not pts or #pts == 0 then return nil end
  local xs, ys = {}, {}
  for _, p in ipairs(pts) do
    local rl, rb, rw, rh = TrueRect(p.rel or rawget(o, "_parent") or UIParentObj, depth)
    if not rl then return nil end
    local ra, an = AN[p.relPoint] or AN.CENTER, AN[p.point] or AN.CENTER
    xs[#xs + 1] = { an[1], rl + rw * ra[1] + p.x }
    ys[#ys + 1] = { an[2], rb + rh * ra[2] + p.y }
  end
  local ow, oh = rawget(o, "_width") or 0, rawget(o, "_height") or 0
  local l, w, fixedW = Solve(xs, ow)
  local isFS = rawget(o, "_type") == "FontString"
  local bounded = fixedW or ow > 0
  if isFS and not fixedW and ow <= 0 then
    local nw = NaturalSize(o)
    l, w = Solve(xs, nw)
  end
  local b, h, fixedH = Solve(ys, oh)
  if isFS and not fixedH and oh <= 0 then
    local _, nh = NaturalSize(o, w)
    b, h = Solve(ys, nh)
  end
  rectCache[o] = { l, b, w, h, bounded = bounded }
  return l, b, w, h
end

local function EffAlpha(o)
  local a, d = 1, 0
  while o and d < 60 do
    a = a * (rawget(o, "_alpha") or 1)
    o, d = rawget(o, "_parent"), d + 1
  end
  return a
end

local function Under(o, root)
  if o == root then return true end
  local p, d = rawget(o, "_parent"), 0
  while p ~= nil and d < 60 do
    if p == root then return true end
    p, d = rawget(p, "_parent"), d + 1
  end
  return false
end

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6,
                 FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function Strata(f)
  local d = 0
  while f and d < 60 do
    local s = rawget(f, "_strata")
    if s then return s end
    f, d = rawget(f, "_parent"), d + 1
  end
  return "MEDIUM"
end

local function FrameLevel(f)
  if f == nil or rawget(f, "_isUIParent") then return 0 end
  local l = rawget(f, "_level")
  if l then return l end
  return FrameLevel(rawget(f, "_parent")) + 1
end

-- Clip rectangle: the nearest ScrollFrame ancestor (it clips its scroll child).
local function ClipOf(o)
  local d = 0
  local cur = o
  while cur and d < 60 do
    local sp = scrollParent[cur]
    if sp then return sp end
    cur, d = rawget(cur, "_parent"), d + 1
  end
  return nil
end

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------
local function JNum(x)
  if x ~= x or x == math.huge or x == -math.huge then return "0" end
  if x == floor(x) and math.abs(x) < 1e15 then return format("%d", x) end
  return format("%.6g", x)
end

local function JStr(s)
  s = tostring(s)
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    if c == "\t" then return "\\t" end
    return format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

local function J(v)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then return JNum(v) end
  if t == "string" then return JStr(v) end
  if t == "table" then
    if v[1] ~= nil or next(v) == nil then
      local o = {}
      for i = 1, #v do o[i] = J(v[i]) end
      return "[" .. concat(o, ",") .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys)
    local o = {}
    for i, k in ipairs(keys) do o[i] = JStr(k) .. ":" .. J(v[k]) end
    return "{" .. concat(o, ",") .. "}"
  end
  return "null"
end

---------------------------------------------------------------------------
-- Export
---------------------------------------------------------------------------
local H = 1080

local function MediaPath(path)
  if type(path) ~= "string" then return nil end
  local p = path:gsub("\\", "/")
  local rel = p:match("^Interface/AddOns/[^/]+/(.*)$")
  if rel then
    if not rel:lower():match("%.tga$") and not rel:lower():match("%.blp$") then rel = rel .. ".tga" end
    return rel
  end
  return "game:" .. p
end

local function Color4(r, g, b, a)
  return { r or 1, g or 1, b or 1, a == nil and 1 or a }
end

local function TexColor(o)
  local v, g, ga = rawget(o, "_vSeq") or 0, rawget(o, "_gSeq") or 0, rawget(o, "_gaSeq") or 0
  if g > v and g >= ga then
    local q = rawget(o, "_grad")
    return nil, { dir = q[1], from = Color4(q[2], q[3], q[4], q[5]), to = Color4(q[6], q[7], q[8], q[9]) }
  end
  if ga > v and ga > g then
    local q = rawget(o, "_gradA")
    return nil, { dir = q[1], from = Color4(q[2], q[3], q[4], q[5]), to = Color4(q[6], q[7], q[8], q[9]) }
  end
  if rawget(o, "_vR") == nil then return { 1, 1, 1, 1 }, nil end
  return Color4(rawget(o, "_vR"), rawget(o, "_vG"), rawget(o, "_vB"), rawget(o, "_vA")), nil
end

local function TexCoords(o)
  local tc = rawget(o, "_tc")
  if type(tc) ~= "table" or #tc == 0 then return { 0, 0, 0, 1, 1, 0, 1, 1 } end
  if #tc == 4 then
    local l, r, t, b = tc[1], tc[2], tc[3], tc[4]
    return { l, t, l, b, r, t, r, b }
  end
  return { tc[1], tc[2], tc[3], tc[4], tc[5], tc[6], tc[7], tc[8] }
end

local function RectTL(o)
  local l, b, w, h = TrueRect(o)
  if not l then return nil end
  return { l, H - (b + h), w, h }
end

local function Export(roots, extra)
  rectCache = {}
  scrollParent = {}
  local index = {}
  for i, o in ipairs(Stub.regions) do
    index[o] = i
    local sc = rawget(o, "_scrollChild")
    if sc then scrollParent[sc] = o end
  end
  local entries = {}
  local function Add(o, item, frame, layer, sub)
    item.strata = Strata(frame)
    item.level = FrameLevel(frame)
    item.layer = layer
    item.sub = sub
    item.created = index[o] or 0
    item.frameIdx = index[frame] or 0
    local clip = ClipOf(o)
    if clip then item.clip = RectTL(clip) end
    entries[#entries + 1] = item
  end
  local function InRoots(o)
    for _, r in ipairs(roots) do
      if Under(o, r) then return true end
    end
    return false
  end
  for _, o in ipairs(Stub.regions) do
    local ty = rawget(o, "_type")
    if InRoots(o) and o:IsVisible() and EffAlpha(o) > 0 then
      local alpha = EffAlpha(o)
      if ty == "Texture" then
        local layer = rawget(o, "_layer") or "ARTWORK"
        local rect = RectTL(o)
        if layer ~= "HIGHLIGHT" and rect and rect[3] > 0 and rect[4] > 0 then
          local vc, grad = TexColor(o)
          local mask = rawget(o, "_mask")
          local item = { kind = "tex", rect = rect, alpha = alpha, vertex = vc, grad = grad,
                         file = MediaPath(rawget(o, "_texture")), tc = TexCoords(o),
                         wrapH = rawget(o, "_wrapH") or "CLAMP", wrapV = rawget(o, "_wrapV") or "CLAMP",
                         blend = rawget(o, "_blend") or "BLEND" }
          if rawget(o, "_texture") == nil and rawget(o, "_cR") ~= nil then
            item.solid = Color4(rawget(o, "_cR"), rawget(o, "_cG"), rawget(o, "_cB"), rawget(o, "_cA"))
          end
          if mask then
            item.mask = { file = MediaPath(rawget(mask, "_texture")), rect = RectTL(mask) or rect }
          end
          Add(o, item, rawget(o, "_parent"), layer, rawget(o, "_subLayer") or 0)
        end
      elseif ty == "FontString" then
        local text = rawget(o, "_text")
        local layer = rawget(o, "_layer") or "ARTWORK"
        local rect = RectTL(o)
        if text ~= nil and text ~= "" and layer ~= "HIGHLIGHT" and rect then
          local font, size, flags, def = FontOf(o)
          local tc
          if rawget(o, "_tR") ~= nil then
            tc = Color4(rawget(o, "_tR"), rawget(o, "_tG"), rawget(o, "_tB"), rawget(o, "_tA"))
          else
            tc = def and def[4] or { 1, 1, 1, 1 }
          end
          local shadow
          local sx, sy = rawget(o, "_shadowX"), rawget(o, "_shadowY")
          if sx ~= nil then
            if sx ~= 0 or sy ~= 0 then
              shadow = { x = sx, y = sy, color = Color4(rawget(o, "_sR") or 0, rawget(o, "_sG") or 0,
                                                       rawget(o, "_sB") or 0, rawget(o, "_sA")) }
            end
          elseif def then
            shadow = { x = 1, y = -1, color = { 0, 0, 0, 1 } }
          end
          local fpath = tostring(font):gsub("\\", "/")
          local rel = fpath:match("^Interface/AddOns/[^/]+/(.*)$")
          local natW = NaturalSize(o)
          local rc = rectCache[o]
          local item = { kind = "text", rect = rect, alpha = alpha, text = text,
                         font = rel or ("game:" .. fpath), size = size, flags = flags,
                         color = tc, shadow = shadow, natW = natW,
                         justifyH = rawget(o, "_justifyH") or "CENTER",
                         justifyV = rawget(o, "_justifyV") or "MIDDLE",
                         wrap = WordWrap(o), bounded = rc and rc.bounded or false }
          Add(o, item, rawget(o, "_parent"), layer, 0)
        end
      elseif rawget(o, "_backdrop") then
        local bd = rawget(o, "_backdrop")
        local rect = RectTL(o)
        if rect then
          local ins = type(bd.insets) == "table" and bd.insets or {}
          local item = { kind = "backdrop", rect = rect, alpha = alpha,
                         bgFile = MediaPath(bd.bgFile), edgeFile = MediaPath(bd.edgeFile),
                         edgeSize = bd.edgeSize or 0,
                         insets = { ins.left or 0, ins.right or 0, ins.top or 0, ins.bottom or 0 },
                         bg = Color4(rawget(o, "_bgR"), rawget(o, "_bgG"), rawget(o, "_bgB"), rawget(o, "_bgA")),
                         border = Color4(rawget(o, "_bdR"), rawget(o, "_bdG"), rawget(o, "_bdB"), rawget(o, "_bdA")) }
          Add(o, item, o, "BACKGROUND", -9)
        end
      end
    end
  end
  table.sort(entries, function(a, b)
    local sa, sb = STRATA[a.strata] or 3, STRATA[b.strata] or 3
    if sa ~= sb then return sa < sb end
    if a.level ~= b.level then return a.level < b.level end
    if a.frameIdx ~= b.frameIdx then return a.frameIdx < b.frameIdx end
    local la, lb = LAYERS[a.layer] or 3, LAYERS[b.layer] or 3
    if la ~= lb then return la < lb end
    if a.sub ~= b.sub then return a.sub < b.sub end
    return a.created < b.created
  end)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, e in ipairs(entries) do
    local r = e.rect
    if r[1] < x0 then x0 = r[1] end
    if r[2] < y0 then y0 = r[2] end
    if r[1] + r[3] > x1 then x1 = r[1] + r[3] end
    if r[2] + r[4] > y1 then y1 = r[2] + r[4] end
  end
  local scene = { ui = { w = 1920, h = H }, scenario = SCENARIO, theme = THEME,
                  bounds = { x0, y0, x1 - x0, y1 - y0 }, items = entries, info = extra }
  return scene
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
local function Main()
  -- real text widths for the addon's layout (the hook patches the stub's shared method
  -- table, which Stub.Reset keeps)
  FM.Install(Stub, Width)
  local nsx = Simulate(THEME)
  local Core = nsx.Core
  local w = rawget(_G, "TruePlayedWidget")
  local roots = { w }
  if SCENARIO == "hero" or SCENARIO == "heroshift" then
    Core.SetSetting("widget.width", 600)
    Core.SetSetting("widget.point", { "BOTTOM", "BOTTOM", 0, 90 })
    Stub.Advance(1)
  else
    Core.SetSetting("widget.point", { "CENTER", "CENTER", 0, -220 })
    Stub.Advance(1)
  end
  local TIP = { tip = 1, tipshift = 1, hero = 1, heroshift = 1, tooltip = 1, tooltipshift = 1 }
  if TIP[SCENARIO] then
    Stub.SetShift(false)
    Stub.RunScript(w, "OnEnter")
    Stub.Advance(1)
    if SCENARIO:find("shift$") then
      Stub.SetShift(true)
      Stub.Advance(1)
    end
    local tf = nsx.TooltipFrame and nsx.TooltipFrame.frame
    if tf and tf:IsShown() then roots[#roots + 1] = tf end
    if SCENARIO:find("^tooltip") then roots = { tf } end
  elseif SCENARIO == "levels" or SCENARIO == "zones" or SCENARIO == "sessions" then
    nsx.Window.Show(SCENARIO)
    Stub.Advance(1)
    roots = { rawget(_G, "TruePlayedStatsFrame") }
  elseif SCENARIO ~= "bar" then
    error("unknown scenario " .. SCENARIO)
  end
  local p = Stub.player
  local info = { level = p.level, xp = p.xp, max = p.max, rest = p.rest,
                 played = Stub.server.total, zone = p.zoneText }
  local scene = Export(roots, info)
  local f = assert(io.open(OUT, "w"))
  f:write(J(scene), "\n")
  f:close()
  local errs = Stub.errors or {}
  for i = 1, #errs do io.stderr:write("addon error: ", tostring(errs[i]):match("^[^\n]*"), "\n") end
  io.stderr:write(format("%s %s: %d items, level %d %.1f%%, rest %d, played %.0f s\n", SCENARIO, THEME,
    #scene.items, p.level, 100 * p.xp / p.max, floor(p.rest or 0), Stub.server.total))
end

Main()
