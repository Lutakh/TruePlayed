-- tests/wowstub.lua - offline simulation of the WoW API used by TruePlayed.
-- FROZEN API: SPEC-FINAL 9.2 (owned by IMPL-1). Other implementers extend it
-- only through tests/stub_<module>.lua installers (Stub.AddInstaller).
-- Runs on Lua 5.1 and 5.5. `dofile` returns the Stub table and installs globals.
--
-- Additions beyond the frozen list (additive, never changing frozen behaviour):
--   Stub.ROOT, Stub.FILES, Stub.build, Stub.calls (API call counters),
--   Stub.templateInit (per-template frame initializers), Stub.ns (last loaded ns),
--   Stub.NewTooltip(), Stub.RunScript(obj, script, ...), Stub.AcceptPopup(i),
--   Stub.CountRegistered(event), Stub.CountTimers(), Stub.DisplayTimePlayedOriginal,
--   Stub.Restart opts: files (passed to LoadAddon), online (seconds that pass with
--   the character still online: clocks AND server advance, e.g. a /reload),
--   settle (passed to LoginSequence).
--   C_Map.GetMapChildrenInfo(id, mapType, allDescendants), from Stub.maps.
--   Stub.Kill(base, opts) (kills with rest bonus and CHAT_MSG_COMBAT_XP_GAIN markers),
--   Stub.Discover(xp) (subzone discovery XP).
--   Round 3: the "target" unit (Stub.target; UnitExists, UnitIsDead, UnitCanAttack,
--   UnitIsPlayer, UnitPlayerControlled, UnitIsTapDenied, UnitClassification,
--   UnitCreatureType, UnitLevel("target"); Stub.secret.target makes them all secret),
--   Stub.SetTarget(t), Stub.KillNoXP(opts) (a kill that gives no XP: server level
--   cap), Stub.party (levels of party1..party4 for UnitLevel), and the max-level
--   helpers IsPlayerAtEffectiveMaxLevel (player.effMax, nil like on Forever),
--   IsLevelAtEffectiveMaxLevel (player.effMaxLevel) and GetMaxLevelForPlayerExpansion
--   (player.expMaxLevel, 60).
--   Themes (design/SPEC-themes.md 8.1): Stub.theme (set to "actuel" by Reset; LoadAddon
--   writes it into ns.C.DEFAULTS.theme, see Stub.ApplyThemeHook), Stub.created (regions
--   created since the last Reset, by type: Texture, MaskTexture, FontString, Frame for
--   every other type), Stub.regions (every object created since the last Reset, in
--   creation order), Stub.calls.SetFont / GetStringWidth, Stub.missingFonts (FontString
--   SetFont returns false for these paths and keeps its font), and the recorded texture
--   state: _subLayer (CreateTexture's 4th argument or SetDrawLayer), _tc (SetTexCoord
--   values), _blend, _wrapH / _wrapV (SetTexture), _grad (SetGradient: dir, from r g b a,
--   to r g b a), _gradA (SetGradientAlpha arguments). _vSeq / _gSeq / _gaSeq order the
--   colour calls of a texture (the last of SetVertexColor / SetGradient /
--   SetGradientAlpha is what the game draws).
local Stub = {}

local unpack = unpack or table.unpack
local floor = math.floor
local _G = _G
local EPS = 1e-9
local TIME_OFFSET = 1790000000 - 1000   -- time() = floor(GetTime() + TIME_OFFSET)

-- Lua 5.2+ passes extra arguments through xpcall; 5.1 does not.
local HAS_XPCALL_ARGS = select(2, xpcall(function(a) return a end, function() end, 42)) == 42

local function Traceback(msg)
  if type(msg) == "table" then return msg end
  return debug.traceback(tostring(msg), 2)
end

---------------------------------------------------------------------------
-- Paths
---------------------------------------------------------------------------
do
  local src = (debug and debug.getinfo and debug.getinfo(1, "S").source) or ""
  src = src:gsub("^@", ""):gsub("\\", "/")
  local root, n = src:gsub("tests/wowstub%.lua$", "")
  if n == 0 or root == "" then root = "./" end
  Stub.ROOT = root
end

Stub.FILES = {   -- SPEC-themes 5.1 load order (fallback when the TOC is missing)
  "Locales/enUS.lua", "Locales/frFR.lua", "Core.lua", "Format.lua", "Stats.lua",
  "Tracker.lua", "Played.lua", "Tokens.lua", "Themes.lua", "Themes/actuel.lua",
  "Themes/futuriste.lua", "Themes/heroic.lua", "Themes/pixel.lua", "Themes/warrior.lua",
  "Themes/paladin.lua", "Themes/hunter.lua", "Themes/rogue.lua", "Themes/priest.lua",
  "Themes/shaman.lua", "Themes/mage.lua", "Themes/warlock.lua", "Themes/druid.lua",
  "Graph.lua", "TooltipFrame.lua", "Tooltip.lua", "BarSkin.lua", "Bar.lua", "Window.lua",
  "Options.lua", "Broker.lua",
}

Stub.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

---------------------------------------------------------------------------
-- Global tracking: every global created while `recording` is on (addon files,
-- tests, installers) is removed by the next Reset, so each test starts clean.
-- Globals created by test files while they are being declared are kept.
---------------------------------------------------------------------------
local recording = false
local createdGlobals = {}
setmetatable(_G, { __newindex = function(t, k, v)
  if recording then createdGlobals[#createdGlobals + 1] = k end
  rawset(t, k, v)
end })

---------------------------------------------------------------------------
-- Clock and timers
---------------------------------------------------------------------------
local clock = { g = 1000.0 }
local timers = {}
local timerSeq = 0
local installers = {}

local function DefaultErrorHandler(msg)
  local e = Stub.errors
  e[#e + 1] = tostring(msg)
end
local errorHandler = DefaultErrorHandler

local function ReportError(err)
  errorHandler(err)
end

local TimerMethods = {}
local TimerMT = { __index = TimerMethods }

function TimerMethods:Cancel()
  if self._cancelled then return end
  self._cancelled = true
  for i = 1, #timers do
    if timers[i] == self then
      table.remove(timers, i)
      break
    end
  end
end

function TimerMethods:IsCancelled()
  return self._cancelled == true
end

local function AddTimer(sec, fn, interval, iterations, passSelf)
  if type(fn) ~= "function" then error("C_Timer: the callback must be a function", 3) end
  sec = tonumber(sec) or 0
  if sec < 0 then sec = 0 end
  timerSeq = timerSeq + 1
  local t = setmetatable({
    due = clock.g + sec, fn = fn, seq = timerSeq, interval = interval,
    iterations = iterations, count = 0, passSelf = passSelf,
  }, TimerMT)
  timers[#timers + 1] = t
  return t
end

local currentTimer
local function CallCurrentTimer()
  local t = currentTimer
  if t.passSelf then t.fn(t) else t.fn() end
end

-- Fires every due timer, earliest due time first, then creation order. A timer
-- scheduled for "now" by a callback runs in the same pass. Tickers that missed
-- several periods (large step = frozen client) fire once and resume.
local function RunDue()
  local guard = 0
  while true do
    local now = clock.g + EPS
    local best, bestIdx
    for i = 1, #timers do
      local t = timers[i]
      if t.due <= now and (best == nil or t.due < best.due or (t.due == best.due and t.seq < best.seq)) then
        best, bestIdx = t, i
      end
    end
    if not best then return end
    guard = guard + 1
    if guard > 100000 then error("wowstub: more than 100000 timer callbacks at one instant") end
    if best.interval then
      best.count = best.count + 1
      if best.iterations and best.count >= best.iterations then
        table.remove(timers, bestIdx)
        best._cancelled = true
      else
        local nd = best.due + best.interval
        if nd <= now then nd = clock.g + best.interval end
        best.due = nd
      end
    else
      table.remove(timers, bestIdx)
    end
    local prev = currentTimer
    currentTimer = best
    local ok, err = xpcall(CallCurrentTimer, Traceback)
    currentTimer = prev
    if not ok then ReportError(err) end
  end
end

-- Moves the clocks without running timers (between two client sessions).
local function MoveClock(sec, serverToo)
  sec = tonumber(sec) or 0
  if sec <= 0 then return end
  clock.g = clock.g + sec
  local srv = Stub.server
  if serverToo and not srv.frozen then
    srv.total = srv.total + sec
    srv.levelPlayed = srv.levelPlayed + sec
  end
end

---------------------------------------------------------------------------
-- Frames, regions and events
---------------------------------------------------------------------------
local eventFrames = {}   -- event -> { n, depth, dirty, [i] = frame | false }
local Methods = {}
local function Noop() end
-- Unknown methods (PascalCase) resolve to a no-op; unknown lowercase fields are nil.
setmetatable(Methods, { __index = function(_, k)
  if type(k) == "string" then
    local b = k:byte(1)
    if b and b >= 65 and b <= 90 then return Noop end
  end
  return nil
end })
local ObjMT = { __index = Methods }
local UIParentObj
local colorSeq = 0               -- orders the colour calls of textures (_vSeq / _gSeq / _gaSeq)
local CREATED_KEY = { Texture = "Texture", MaskTexture = "MaskTexture", FontString = "FontString" }

local function CallScript(obj, name, ...)
  local script = obj._scripts[name]
  if not script then return end
  local ok, err
  if HAS_XPCALL_ARGS then
    ok, err = xpcall(script, Traceback, obj, ...)
  else
    ok, err = pcall(script, obj, ...)
  end
  if not ok then ReportError(err) end
end

local function NewObject(objType, name, parent)
  local o = setmetatable({
    _type = objType, _parent = parent, _shown = true, _alpha = 1, _scale = 1,
    _width = 0, _height = 0, _points = {}, _scripts = {}, _events = {},
    _setTextCount = 0,
  }, ObjMT)
  if type(name) == "string" and name ~= "" then
    if parent and name:find("$parent", 1, true) then
      name = name:gsub("%$parent", parent._name or "")
    end
    o._name = name
    _G[name] = o   -- named frames are globals, as in the game
  end
  local created = Stub.created
  if created then
    local key = CREATED_KEY[objType] or "Frame"
    created[key] = (created[key] or 0) + 1
  end
  local regions = Stub.regions
  if regions then regions[#regions + 1] = o end
  return o
end

local function CompactFrames(list)
  local j = 0
  for i = 1, list.n do
    local f = list[i]
    if f then
      j = j + 1
      list[j] = f
    end
  end
  for i = j + 1, list.n do list[i] = nil end
  list.n = j
  list.dirty = false
end

-- events
function Methods:RegisterEvent(event)
  if type(event) ~= "string" then error("RegisterEvent: event name expected", 2) end
  if Stub.unknownEvents[event] then error('Attempt to register unknown event "' .. event .. '"', 2) end
  if self._events[event] then return true end
  self._events[event] = true
  local list = eventFrames[event]
  if not list then
    list = { n = 0, depth = 0, dirty = false }
    eventFrames[event] = list
  end
  list.n = list.n + 1
  list[list.n] = self
  return true
end

function Methods:RegisterUnitEvent(event)
  return Methods.RegisterEvent(self, event)
end

function Methods:UnregisterEvent(event)
  if not self._events[event] then return end
  self._events[event] = nil
  local list = eventFrames[event]
  if not list then return end
  for i = 1, list.n do
    if list[i] == self then
      list[i] = false
      list.dirty = true
      break
    end
  end
  if list.depth == 0 then CompactFrames(list) end
end

function Methods:IsEventRegistered(event)
  return self._events[event] == true
end

function Methods:UnregisterAllEvents()
  for event in pairs(self._events) do Methods.UnregisterEvent(self, event) end
end

-- scripts
function Methods:SetScript(name, fn)
  if name == "OnUpdate" and fn ~= nil then Stub.onUpdateCount = Stub.onUpdateCount + 1 end
  self._scripts[name] = fn
end

function Methods:GetScript(name)
  return self._scripts[name]
end

function Methods:HasScript()
  return true
end

function Methods:HookScript(name, fn)
  if name == "OnUpdate" and fn ~= nil then Stub.onUpdateCount = Stub.onUpdateCount + 1 end
  local prev = self._scripts[name]
  if prev then
    self._scripts[name] = function(...)
      prev(...)
      return fn(...)
    end
  else
    self._scripts[name] = fn
  end
end

-- visibility
function Methods:Show()
  if self._shown then return end
  self._shown = true
  CallScript(self, "OnShow")
end

function Methods:Hide()
  if not self._shown then return end
  self._shown = false
  CallScript(self, "OnHide")
end

function Methods:SetShown(v)
  if v then self:Show() else self:Hide() end
end

function Methods:IsShown()
  return self._shown == true
end

function Methods:IsVisible()
  local o, depth = self, 0
  while o and depth < 50 do
    if not o._shown then return false end
    o = o._parent
    depth = depth + 1
  end
  return true
end

-- anchors and geometry (UIParent is 1920 x 1080; scale is ignored)
local ANCHOR = {
  TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

function Methods:SetPoint(point, a, b, c, d)
  local rel, relPoint, x, y
  if type(a) == "number" then
    x, y = a, b                                   -- SetPoint(point, x, y)
  elseif a ~= nil then
    rel = a
    if type(rel) == "string" then rel = _G[rel] end
    if type(b) == "string" then
      relPoint, x, y = b, c, d                    -- SetPoint(point, rel, relPoint, x, y)
    else
      x, y = b, c                                 -- SetPoint(point, rel, x, y)
    end
  end
  local pts = self._points
  for i = 1, #pts do
    if pts[i].point == point then
      table.remove(pts, i)
      break
    end
  end
  pts[#pts + 1] = { point = point, rel = rel, relPoint = relPoint or point, x = x or 0, y = y or 0 }
  self._allPoints = nil
end

function Methods:ClearAllPoints()
  local pts = self._points
  for i = #pts, 1, -1 do pts[i] = nil end
  self._allPoints = nil
end

function Methods:SetAllPoints(rel)
  rel = rel or self._parent
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
  self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
  self._allPoints = rel
end

function Methods:GetPoint(i)
  local p = self._points[i or 1]
  if not p then return nil end
  return p.point, p.rel or self._parent, p.relPoint, p.x, p.y
end

function Methods:GetNumPoints()
  return #self._points
end

local function Rect(o, depth)
  if o == nil then return nil end
  if o._isUIParent then return 0, 0, o._width, o._height end
  depth = (depth or 0) + 1
  if depth > 30 then return nil end
  if o._allPoints then return Rect(o._allPoints, depth) end
  local p = o._points[1]
  if not p then return nil end
  local rl, rb, rw, rh = Rect(p.rel or o._parent or UIParentObj, depth)
  if not rl then return nil end
  local ra = ANCHOR[p.relPoint] or ANCHOR.CENTER
  local ax, ay = rl + rw * ra[1] + p.x, rb + rh * ra[2] + p.y
  local w, h = o:GetWidth(), o:GetHeight()
  local an = ANCHOR[p.point] or ANCHOR.CENTER
  return ax - w * an[1], ay - h * an[2], w, h
end

function Methods:GetRect() return Rect(self) end
function Methods:GetCenter()
  local l, b, w, h = Rect(self)
  if not l then return nil end
  return l + w / 2, b + h / 2
end
function Methods:GetLeft() local l = Rect(self); return l end
function Methods:GetBottom() local _, b = Rect(self); return b end
function Methods:GetRight()
  local l, _, w = Rect(self)
  if not l then return nil end
  return l + w
end
function Methods:GetTop()
  local _, b, _, h = Rect(self)
  if not b then return nil end
  return b + h
end

function Methods:SetSize(w, h) self._width, self._height = w or 0, h or 0 end
function Methods:SetWidth(w) self._width = w or 0 end
function Methods:SetHeight(h) self._height = h or 0 end
function Methods:GetWidth()
  if self._allPoints then return self._allPoints:GetWidth() end
  return self._width
end
function Methods:GetHeight()
  if self._allPoints then return self._allPoints:GetHeight() end
  return self._height
end
function Methods:GetSize() return self:GetWidth(), self:GetHeight() end

-- appearance and interaction state
function Methods:SetAlpha(a) self._alpha = a end
function Methods:GetAlpha() return self._alpha end
function Methods:GetEffectiveAlpha() return self._alpha end
function Methods:SetScale(s) self._scale = s end
function Methods:GetScale() return self._scale end
function Methods:GetEffectiveScale() return self._scale end
function Methods:EnableMouse(v) self._mouse = v and true or false end
function Methods:IsMouseEnabled() return self._mouse == true end
function Methods:SetMovable(v) self._movable = v and true or false end
function Methods:IsMovable() return self._movable == true end
function Methods:RegisterForDrag(...) self._drag = { ... } end
function Methods:RegisterForClicks(...) self._clicks = { ... } end
function Methods:SetClampedToScreen(v) self._clamped = v and true or false end
function Methods:IsClampedToScreen() return self._clamped == true end
function Methods:StartMoving() self._moving = true end
function Methods:StopMovingOrSizing() self._moving = false end
function Methods:SetFrameStrata(s) self._strata = s end
function Methods:GetFrameStrata() return self._strata or "MEDIUM" end
function Methods:SetFrameLevel(l) self._level = l end
function Methods:GetFrameLevel() return self._level or 1 end
function Methods:GetName() return self._name end
function Methods:GetParent() return self._parent end
function Methods:SetParent(p) self._parent = p end
function Methods:GetObjectType() return self._type end
function Methods:IsObjectType(t) return self._type == t end
function Methods:IsForbidden() return false end
function Methods:IsProtected() return false end
function Methods:IsMouseOver() return self._mouseOver == true end

-- children
function Methods:CreateTexture(name, layer, _, sub)
  local t = NewObject("Texture", name, self)
  t._layer = layer
  t._subLayer = sub
  return t
end

function Methods:CreateMaskTexture(name, layer)
  local t = NewObject("MaskTexture", name, self)
  t._layer = layer
  return t
end

function Methods:CreateFontString(name, layer, template)
  local fs = NewObject("FontString", name, self)
  fs._layer = layer
  fs._fontObject = template
  return fs
end

function Methods:CreateAnimationGroup(name)
  return NewObject("AnimationGroup", name, self)
end

-- backdrop (only frames created with BackdropTemplate have it, as in the game)
local function NeedBackdrop(self, method)
  if not self._backdropTemplate then
    error(method .. ": frame was not created with BackdropTemplate", 3)
  end
end
function Methods:SetBackdrop(b) NeedBackdrop(self, "SetBackdrop"); self._backdrop = b end
function Methods:GetBackdrop() return self._backdrop end
function Methods:SetBackdropColor(r, g, b, a)
  NeedBackdrop(self, "SetBackdropColor")
  self._bgR, self._bgG, self._bgB, self._bgA = r, g, b, a
end
function Methods:SetBackdropBorderColor(r, g, b, a)
  NeedBackdrop(self, "SetBackdropBorderColor")
  self._bdR, self._bdG, self._bdB, self._bdA = r, g, b, a
end

-- textures
function Methods:SetTexture(path, wrapH, wrapV)
  self._texture = path
  self._wrapH, self._wrapV = wrapH, wrapV
  return true
end
function Methods:GetTexture() return self._texture end
function Methods:SetColorTexture(r, g, b, a)
  self._texture = nil
  self._cR, self._cG, self._cB, self._cA = r, g, b, a
  colorSeq = colorSeq + 1
  self._vSeq = colorSeq
end
function Methods:SetVertexColor(r, g, b, a)
  self._vR, self._vG, self._vB, self._vA = r, g, b, a
  colorSeq = colorSeq + 1
  self._vSeq = colorSeq
end
function Methods:GetVertexColor() return self._vR, self._vG, self._vB, self._vA end
function Methods:AddMaskTexture(mask) self._mask = mask end
-- Records the arguments in _tc (the table is reused: no garbage after the first call).
function Methods:SetTexCoord(...)
  local n = select("#", ...)
  self._texCoordN = n
  local tc = rawget(self, "_tc")
  if not tc then
    tc = {}
    self._tc = tc
  end
  for i = 1, n do tc[i] = (select(i, ...)) end
  for i = #tc, n + 1, -1 do tc[i] = nil end
end
function Methods:SetBlendMode(mode) self._blend = mode end
function Methods:GetBlendMode() return self._blend or "BLEND" end
function Methods:SetDrawLayer(layer, sub) self._layer, self._subLayer = layer, sub end
function Methods:GetDrawLayer() return self._layer, self._subLayer or 0 end
-- 10.0+ form: colour tables with r, g, b, a fields (errors otherwise, like the game).
function Methods:SetGradient(dir, from, to)
  if type(from) ~= "table" or type(to) ~= "table" then
    error("SetGradient: colour tables expected", 2)
  end
  local g = rawget(self, "_grad")
  if not g then
    g = {}
    self._grad = g
  end
  g[1], g[2], g[3], g[4], g[5] = dir, from.r, from.g, from.b, from.a
  g[6], g[7], g[8], g[9] = to.r, to.g, to.b, to.a
  colorSeq = colorSeq + 1
  self._gSeq = colorSeq
end
function Methods:SetGradientAlpha(...)
  local g = rawget(self, "_gradA")
  if not g then
    g = {}
    self._gradA = g
  end
  local n = select("#", ...)
  for i = 1, n do g[i] = (select(i, ...)) end
  for i = #g, n + 1, -1 do g[i] = nil end
  colorSeq = colorSeq + 1
  self._gaSeq = colorSeq
end

-- font strings (and button text)
local function VisibleLength(text)
  if text == nil then return 0 end
  text = tostring(text)
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local n = 0
  for i = 1, #text do
    local b = text:byte(i)
    if b < 128 or b >= 192 then n = n + 1 end   -- count UTF-8 characters
  end
  return n
end

function Methods:SetText(text)
  self._text = text
  self._setTextCount = self._setTextCount + 1
end
function Methods:GetText() return self._text end
function Methods:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
function Methods:SetTextColor(r, g, b, a) self._tR, self._tG, self._tB, self._tA = r, g, b, a end
function Methods:GetTextColor() return self._tR, self._tG, self._tB, self._tA end
-- A path listed in Stub.missingFonts fails like a font file the client could not load:
-- false, and the FontString keeps its previous font.
function Methods:SetFont(path, size, flags)
  local c = Stub.calls
  c.SetFont = (c.SetFont or 0) + 1
  local missing = Stub.missingFonts
  if missing and missing[path] then return false end
  self._font, self._fontSize, self._fontFlags = path, size, flags
  return true
end
function Methods:GetFont() return self._font, self._fontSize, self._fontFlags end
function Methods:SetFontObject(obj) self._fontObject = obj end
function Methods:GetFontObject() return self._fontObject end
function Methods:SetJustifyH(j) self._justifyH = j end
function Methods:GetJustifyH() return self._justifyH end
function Methods:SetJustifyV(j) self._justifyV = j end
function Methods:SetShadowOffset(x, y) self._shadowX, self._shadowY = x, y end
function Methods:SetShadowColor(r, g, b, a) self._sR, self._sG, self._sB, self._sA = r, g, b, a end
function Methods:GetStringWidth()   -- 6 per character
  local c = Stub.calls
  c.GetStringWidth = (c.GetStringWidth or 0) + 1
  return 6 * VisibleLength(self._text)
end
function Methods:GetUnboundedStringWidth() return 6 * VisibleLength(self._text) end
function Methods:GetStringHeight() return self._fontSize or 12 end
function Methods:GetFontString()
  if not self._fs then self._fs = NewObject("FontString", nil, self) end
  return self._fs
end

-- buttons, check buttons, sliders, scroll frames
function Methods:Enable() self._enabled = true end
function Methods:Disable() self._enabled = false end
function Methods:SetEnabled(v) self._enabled = v and true or false end
function Methods:IsEnabled() return self._enabled ~= false end
function Methods:Click(button, down)
  if self._enabled == false then return end
  CallScript(self, "OnClick", button or "LeftButton", down or false)
end
function Methods:SetChecked(v) self._checked = v and true or false end
function Methods:GetChecked() return self._checked == true end
function Methods:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function Methods:GetMinMaxValues() return self._min or 0, self._max or 0 end
function Methods:SetValue(v)
  local old = self._value
  self._value = v
  if old ~= v then CallScript(self, "OnValueChanged", v, false) end
end
function Methods:GetValue() return self._value or 0 end
function Methods:SetValueStep(s) self._step = s end
function Methods:GetValueStep() return self._step or 0 end
function Methods:SetScrollChild(child) self._scrollChild = child end
function Methods:GetScrollChild() return self._scrollChild end
function Methods:SetVerticalScroll(v) self._vscroll = v end
function Methods:GetVerticalScroll() return self._vscroll or 0 end
function Methods:GetVerticalScrollRange() return 0 end

-- tooltips (GameTooltip mock: _lines = { { left, right }, ... })
local TooltipMethods = {}
function TooltipMethods:SetOwner(owner, anchor)
  self._owner = owner
  self._anchor = anchor
  self:ClearLines()
end
function TooltipMethods:GetOwner() return self._owner end
function TooltipMethods:IsOwned(frame) return self._owner == frame end
function TooltipMethods:ClearLines()
  local lines, colors = self._lines, self._colors
  for i = #lines, 1, -1 do lines[i] = nil end
  for i = #colors, 1, -1 do colors[i] = nil end
end
function TooltipMethods:AddLine(text, r, g, b)
  local n = #self._lines + 1
  self._lines[n] = { text }
  self._colors[n] = { r, g, b }
end
function TooltipMethods:AddDoubleLine(left, right, lr, lg, lb, rr, rg, rb)
  local n = #self._lines + 1
  self._lines[n] = { left, right }
  self._colors[n] = { lr, lg, lb, rr, rg, rb }
end
function TooltipMethods:SetText(text, r, g, b)
  self:ClearLines()
  self:AddLine(text, r, g, b)
end
function TooltipMethods:NumLines() return #self._lines end
function TooltipMethods:Hide()
  Methods.Hide(self)
  self._owner = nil
end

local function InitTooltip(tt)
  tt._lines, tt._colors = {}, {}
  tt._shown = false
  for k, fn in pairs(TooltipMethods) do rawset(tt, k, fn) end
end

-- default template initializers (Stub.templateInit can be extended by installers)
local function DefaultTemplateInit()
  return {
    BackdropTemplate = function(f) f._backdropTemplate = true end,
    UICheckButtonTemplate = function(f)
      f._checked = false
      local text = f:CreateFontString(nil, "ARTWORK")
      f.Text, f.text = text, text
    end,
    UIPanelScrollFrameTemplate = function(f)
      f.ScrollBar = NewObject("Slider", nil, f)
    end,
    UIPanelCloseButton = function() end,
  }
end

local function CreateFrameImpl(frameType, name, parent, template)
  if type(frameType) ~= "string" then error("CreateFrame: frame type expected", 2) end
  local list = {}
  if template ~= nil then
    for tpl in tostring(template):gmatch("[^,%s]+") do
      if not Stub.templates[tpl] then error("CreateFrame: unknown template '" .. tpl .. "'", 2) end
      list[#list + 1] = tpl
    end
  end
  local f = NewObject(frameType, name, parent)
  if frameType == "GameTooltip" then InitTooltip(f) end
  for i = 1, #list do
    local init = Stub.templateInit[list[i]]
    if init then init(f) end
  end
  return f
end

local function DispatchEvent(list, event, ...)
  list.depth = list.depth + 1
  for i = 1, list.n do
    local f = list[i]
    if f then CallScript(f, "OnEvent", event, ...) end
  end
  list.depth = list.depth - 1
  if list.dirty and list.depth == 0 then CompactFrames(list) end
end

---------------------------------------------------------------------------
-- WoW API (installed as globals by Reset)
---------------------------------------------------------------------------
local API = {}

local function Count(name)
  local c = Stub.calls
  c[name] = (c[name] or 0) + 1
end

-- player / unit
function API.UnitName(unit)
  if unit ~= "player" then return nil end
  local p = Stub.player
  return p.name, p.surname
end
function API.UnitGUID(unit)
  if unit ~= "player" then return nil end
  return Stub.player.guid
end
function API.UnitClass(unit)
  if unit ~= "player" then return nil end
  local p = Stub.player
  return p.classLocalized, p.class
end
function API.UnitFactionGroup(unit)
  if unit ~= "player" then return nil end
  return Stub.player.faction, Stub.player.faction
end
function API.UnitIsDeadOrGhost(unit)
  return unit == "player" and Stub.player.dead == true
end
function API.UnitLevel(unit)
  if unit == "target" then
    local t = Stub.target
    if not t then return 0 end
    if Stub.secret.target then return Stub.SECRET end
    return t.level
  end
  local n = type(unit) == "string" and tonumber(unit:match("^party(%d)$"))
  if n then return Stub.party[n] or 0 end   -- no such member: 0, as the client answers
  if unit ~= "player" then return 0 end
  return Stub.player.level
end

-- the "target" unit (Stub.target, nil = no target); Stub.secret.target: all secret
local function TargetField(unit, field)
  if unit ~= "target" then return nil end
  local t = Stub.target
  if not t then return nil end
  if Stub.secret.target then return Stub.SECRET end
  return t[field]
end
function API.UnitExists(unit)
  if unit == "player" then return true end
  if unit ~= "target" or not Stub.target then return nil end
  if Stub.secret.target then return Stub.SECRET end
  return true
end
function API.UnitIsDead(unit)
  if unit == "player" then return Stub.player.dead == true end
  return TargetField(unit, "dead")
end
function API.UnitCanAttack(unit, other)
  if unit ~= "player" then return nil end
  return TargetField(other, "canAttack")
end
function API.UnitIsPlayer(unit)
  if unit == "player" then return true end
  return TargetField(unit, "isPlayer")
end
function API.UnitPlayerControlled(unit)
  if unit == "player" then return true end
  return TargetField(unit, "playerControlled")
end
function API.UnitIsTapDenied(unit) return TargetField(unit, "tapDenied") end
function API.UnitClassification(unit)
  if unit == "player" then return "normal" end
  return TargetField(unit, "classification")
end
function API.UnitCreatureType(unit) return TargetField(unit, "creatureType") end
-- max-level helpers: nil by default, like on Forever (IsPlayerAtEffectiveMaxLevel returns
-- nothing there, GetMaxLevelForPlayerExpansion 60 while the beta caps at 20)
function API.IsPlayerAtEffectiveMaxLevel() return Stub.player.effMax end
function API.IsLevelAtEffectiveMaxLevel(level)
  local m = Stub.player.effMaxLevel
  if m == nil then return nil end
  return type(level) == "number" and level >= m
end
function API.GetMaxLevelForPlayerExpansion() return Stub.player.expMaxLevel end
function API.UnitXP()
  if Stub.secret.xp then return Stub.SECRET end
  return Stub.player.xp
end
function API.UnitXPMax()
  if Stub.secret.xp then return Stub.SECRET end
  return Stub.player.max
end
function API.GetXPExhaustion()   -- nil when there is no rest, like the game
  if Stub.secret.xp then return Stub.SECRET end
  local r = Stub.player.rest
  if not r or r <= 0 then return nil end
  return r
end
function API.IsXPUserDisabled() return Stub.player.xpDisabled == true end
function API.GetMaxPlayerLevel() return Stub.player.maxLevel end
function API.UnitIsAFK(unit)
  if Stub.secret.afk then return Stub.SECRET end
  return unit == "player" and Stub.player.afk == true
end
function API.IsResting()
  if Stub.secret.resting then return Stub.SECRET end
  return Stub.player.resting == true
end
function API.UnitOnTaxi()
  if Stub.secret.taxi then return Stub.SECRET end
  return Stub.player.taxi == true
end
function API.GetRealmName() return Stub.player.realm end

-- world
function API.IsInInstance()
  local p = Stub.player
  return p.inInstance == true, p.instanceType or "none"
end
function API.GetInstanceInfo()
  local p = Stub.player
  return p.instanceName or "", p.instanceType or "none", 0, "", 5, 0, false, p.instanceID or 0
end
function API.GetRealZoneText() return Stub.player.zoneText end

local function GetBestMapForUnit(unit)
  Count("GetBestMapForUnit")
  if unit ~= "player" then return nil end
  return Stub.player.mapID
end
local function GetMapInfo(id)
  Count("GetMapInfo")
  if type(id) ~= "number" then error("Usage: C_Map.GetMapInfo(uiMapID)", 2) end
  local m = Stub.maps[id]
  if not m then return nil end
  return { mapID = id, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID or 0 }
end
-- Children of a map in Stub.maps (optionally of one mapType; all descendants when
-- allDescendants), as the game: always a table, empty for a leaf map.
local function GetMapChildrenInfo(id, mapType, allDescendants)
  Count("GetMapChildrenInfo")
  if type(id) ~= "number" then error("Usage: C_Map.GetMapChildrenInfo(uiMapID [, mapType, allDescendants])", 2) end
  local out = {}
  for cid, m in pairs(Stub.maps) do
    local p, depth, below = m.parentMapID, 0, false
    while p and depth < 10 do
      if p == id then below = true break end
      if not allDescendants then break end
      local pm = Stub.maps[p]
      p = pm and pm.parentMapID
      depth = depth + 1
    end
    if below and (mapType == nil or m.mapType == mapType) then
      out[#out + 1] = { mapID = cid, name = m.name, mapType = m.mapType, parentMapID = m.parentMapID or 0 }
    end
  end
  table.sort(out, function(a, b) return a.mapID < b.mapID end)
  return out
end

-- client
function API.GetLocale() return Stub.locale end
function API.GetBuildInfo()
  local b = Stub.build
  return b.version, b.build, b.date, b.interface
end
function API.GetCVar(name) return Stub.cvars[name] end
function API.UpdateAddOnMemoryUsage() Count("UpdateAddOnMemoryUsage") end
function API.GetAddOnMemoryUsage() return Stub.memKB end
function API.UpdateAddOnCPUUsage() Count("UpdateAddOnCPUUsage") end
function API.GetAddOnCPUUsage() return Stub.cpuMS end
function API.debugprofilestop() return clock.g * 1000 end
function API.InCombatLockdown() return Stub.combat == true end
function API.IsShiftKeyDown() return Stub.shift == true end
function API.GetFramerate()
  Count("GetFramerate")
  return Stub.fps
end
function API.GetNetStats()
  Count("GetNetStats")
  return 0, 0, Stub.net.home, Stub.net.world
end
function API.issecretvalue(v) return rawequal(v, Stub.SECRET) end

-- time
function API.GetTime() return clock.g end
function API.time(t)
  if t ~= nil then return os.time(t) end
  return floor(clock.g + TIME_OFFSET)
end
API.date = os.date

-- /played
local function FirePlayed()
  local srv = Stub.server
  Stub.Fire("TIME_PLAYED_MSG", floor(srv.total), floor(srv.levelPlayed))
end
function API.RequestTimePlayed()
  Stub.requests = Stub.requests + 1
  Stub.requestLog[#Stub.requestLog + 1] = clock.g
  AddTimer(0.1, FirePlayed, nil, nil, false)
end
local function OriginalDisplayTimePlayed(_, total, level)
  Stub.displayed[#Stub.displayed + 1] = { total = total, level = level }
end
Stub.DisplayTimePlayedOriginal = OriginalDisplayTimePlayed

-- hooks: hooksecurefunc(name, fn) or hooksecurefunc(table, name, fn); fn runs after
function API.hooksecurefunc(a, b, c)
  local tbl, name, hook
  if type(a) == "table" then tbl, name, hook = a, b, c else tbl, name, hook = _G, a, b end
  local orig = tbl[name]
  if type(orig) ~= "function" then error("hooksecurefunc: '" .. tostring(name) .. "' is not a function", 2) end
  if type(hook) ~= "function" then error("hooksecurefunc: hook must be a function", 2) end
  tbl[name] = function(...)
    local n = select("#", ...)
    local args = { ... }
    local rets = { n = 0 }
    local function collect(...)
      rets.n = select("#", ...)
      for i = 1, rets.n do rets[i] = (select(i, ...)) end
    end
    collect(orig(...))
    hook(unpack(args, 1, n))
    return unpack(rets, 1, rets.n)
  end
end

-- UI
function API.StaticPopup_Show(which, a1, a2, data)
  local rec = { which = which, text_arg1 = a1, text_arg2 = a2, data = data }
  Stub.popups[#Stub.popups + 1] = rec
  return rec   -- doubles as the dialog: setting rec.data after the call is recorded
end
function API.StaticPopup_Hide(which)
  for i = 1, #Stub.popups do
    if Stub.popups[i].which == which then Stub.popups[i].hidden = true end
  end
end

-- utilities
local function SecureReturn(ok, ...)
  if not ok then
    errorHandler((...))
    return
  end
  return ...
end
function API.securecallfunction(fn, ...)
  if HAS_XPCALL_ARGS then return SecureReturn(xpcall(fn, Traceback, ...)) end
  return SecureReturn(pcall(fn, ...))
end
function API.geterrorhandler() return errorHandler end
function API.seterrorhandler(fn) if type(fn) == "function" then errorHandler = fn end end

local function EscapeSet(chars)
  return "[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]"
end
function API.strsplit(delim, str, pieces)
  local out = {}
  local set = EscapeSet(delim)
  local start = 1
  while true do
    if pieces and #out == pieces - 1 then
      out[#out + 1] = str:sub(start)
      break
    end
    local s, e = str:find(set, start)
    if not s then
      out[#out + 1] = str:sub(start)
      break
    end
    out[#out + 1] = str:sub(start, s - 1)
    start = e + 1
  end
  return unpack(out, 1, #out)
end
function API.strtrim(str, chars)
  if chars then
    local set = EscapeSet(chars)
    return (str:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
  end
  return (str:gsub("^%s+", ""):gsub("%s+$", ""))
end
function API.strjoin(sep, ...)
  return table.concat({ ... }, sep)
end
API.format = string.format
API.tinsert = table.insert
API.tremove = table.remove
function API.wipe(t)
  for k in pairs(t) do t[k] = nil end
  return t
end
function API.Mixin(obj, ...)
  for i = 1, select("#", ...) do
    local mixin = select(i, ...)
    for k, v in pairs(mixin) do obj[k] = v end
  end
  return obj
end
local function CopyTable(t)
  local out = {}
  for k, v in pairs(t) do
    if type(v) == "table" then out[k] = CopyTable(v) else out[k] = v end
  end
  return out
end
API.CopyTable = CopyTable

local ABSENT = {   -- nil by default unless an extension installs them
  "Settings", "InterfaceOptions_AddCategory", "MenuUtil", "LibStub", "AddonCompartmentFrame",
  "MinimalSliderWithSteppersMixin", "C_AddOnProfiler", "C_ChatInfo", "BackdropTemplateMixin",
  "GetAddOnMetadata",
}

---------------------------------------------------------------------------
-- Default world
---------------------------------------------------------------------------
local function NewPlayer()
  return {
    guid = "Player-4619-00A629CA", name = "Lutak", surname = "Ombrevent", realm = "Brisevent",
    class = "MAGE", classLocalized = "Mage", faction = "Horde", level = 10, xp = 0, max = 7600,
    rest = 0, afk = false, resting = false, taxi = false, dead = false, mapID = 1411,
    inInstance = false, instanceType = "none", instanceID = 0, instanceName = "",
    zoneText = "Durotar", xpDisabled = false, maxLevel = 60, expMaxLevel = 60,
  }
end

local function NewMaps()
  return {
    [947]   = { mapType = 1, parentMapID = nil,  name = "Azeroth" },
    [1414]  = { mapType = 2, parentMapID = 947,  name = "Kalimdor" },
    [1415]  = { mapType = 2, parentMapID = 947,  name = "Eastern Kingdoms" },
    [1411]  = { mapType = 3, parentMapID = 1414, name = "Durotar" },
    [1413]  = { mapType = 3, parentMapID = 1414, name = "The Barrens" },
    [1446]  = { mapType = 3, parentMapID = 1414, name = "Tanaris" },
    [1454]  = { mapType = 3, parentMapID = 1414, name = "Orgrimmar" },
    [1453]  = { mapType = 3, parentMapID = 1415, name = "Stormwind City" },
    [1458]  = { mapType = 3, parentMapID = 1415, name = "Undercity" },
    [90001] = { mapType = 4, parentMapID = 1454, name = "Ragefire Chasm" },
    [90002] = { mapType = 4, parentMapID = 1454, name = "Cleft of Shadow" },
    [90003] = { mapType = 5, parentMapID = 1454, name = "Valley of Strength" },
    [90004] = { mapType = 4, parentMapID = 1453, name = "The Stockade" },
    [2521]  = { mapType = 2, parentMapID = 947,  name = "Zephras" },
  }
end

local function NewXPTable()   -- Classic XP to reach the next level, levels 1..59
  return {
    400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
    8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
    25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
    95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
  }
end

-- Name of the nearest Zone/Dungeon ancestor (what GetRealZoneText would show).
local function ZoneTextFor(id)
  local depth = 0
  while id and depth < 10 do
    local m = Stub.maps[id]
    if not m then return nil end
    if m.mapType == 3 or m.mapType == 4 then return m.name end
    id = m.parentMapID
    depth = depth + 1
  end
  return nil
end

local function InstallGlobals()
  local function G(name, value) rawset(_G, name, value) end
  for name, fn in pairs(API) do G(name, fn) end
  G("C_Map", { GetBestMapForUnit = GetBestMapForUnit, GetMapInfo = GetMapInfo,
               GetMapChildrenInfo = GetMapChildrenInfo })
  G("Enum", { UIMapType = { Cosmic = 0, World = 1, Continent = 2, Zone = 3, Dungeon = 4, Micro = 5, Orphan = 6 } })
  G("C_AddOns", { GetAddOnMetadata = function(_, field) return Stub.meta[field] end })
  G("C_XMLUtil", { GetTemplateInfo = function(name)
    if Stub.templates[name] then return { type = "Frame", width = 0, height = 0 } end
    return nil
  end })
  G("C_Timer", {
    After = function(sec, fn) AddTimer(sec, fn, nil, nil, false) end,
    NewTimer = function(sec, fn) return AddTimer(sec, fn, nil, nil, true) end,
    NewTicker = function(sec, fn, iterations)
      local interval = tonumber(sec) or 0
      if interval < 0.001 then interval = 0.001 end
      return AddTimer(interval, fn, interval, iterations, true)
    end,
  })
  G("ChatFrameUtil", { DisplayTimePlayed = OriginalDisplayTimePlayed })
  G("CreateFrame", CreateFrameImpl)
  G("SlashCmdList", {})
  G("StaticPopupDialogs", {})
  G("UISpecialFrames", {})
  G("STANDARD_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
  G("YES", "Yes")
  G("NO", "No")
  for i = 1, #ABSENT do G(ABSENT[i], nil) end

  -- UIParent, chat frame, tooltip, font objects
  local ui = NewObject("Frame", "UIParent", nil)
  ui._isUIParent = true
  ui._width, ui._height = 1920, 1080
  UIParentObj = ui

  local chat = NewObject("ScrollingMessageFrame", "ChatFrame1", ui)
  rawset(chat, "AddMessage", function(_, text) Stub.printed[#Stub.printed + 1] = text end)
  chat:RegisterEvent("TIME_PLAYED_MSG")
  chat:SetScript("OnEvent", function(self, event, total, level)
    if event == "TIME_PLAYED_MSG" then
      _G.ChatFrameUtil.DisplayTimePlayed(self, total, level)   -- read at call time (may be wrapped)
    end
  end)
  G("DEFAULT_CHAT_FRAME", chat)

  local tt = CreateFrameImpl("GameTooltip", "GameTooltip", ui)
  tt._backdropTemplate = true

  local fonts = { "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisable" }
  for i = 1, #fonts do
    local fo = NewObject("Font", fonts[i], nil)
    fo._font, fo._fontSize, fo._fontFlags = "Fonts\\FRIZQT__.TTF", 12, ""
  end
end

---------------------------------------------------------------------------
-- Stub API (FROZEN, SPEC 9.2)
---------------------------------------------------------------------------
function Stub.AddInstaller(fn)
  if type(fn) ~= "function" then error("Stub.AddInstaller: function expected", 2) end
  installers[#installers + 1] = fn
end

function Stub.Reset(opts)
  local keep = opts and opts.keepWorld == true

  recording = false
  for i = #createdGlobals, 1, -1 do
    rawset(_G, createdGlobals[i], nil)
    createdGlobals[i] = nil
  end

  if not keep then
    clock.g = 1000.0
    Stub.player = NewPlayer()
    Stub.maps = NewMaps()
    Stub.server = { total = 360000, levelPlayed = 5000, frozen = false }
    Stub.saved = nil
    -- configuration (kept across a keepWorld restart: a restart does not change them)
    Stub.secret = { afk = false, resting = false, taxi = false, xp = false, target = false }
    Stub.locale = "enUS"
    Stub.fps = 60
    Stub.net = { home = 38, world = 42 }
    Stub.cvars = { scriptProfile = "0" }
    Stub.memKB, Stub.cpuMS = 123.4, 0
    Stub.meta = { Version = "@project-version@" }
    Stub.build = { version = "1.60.1", build = "70124", date = "Sep 2026", interface = 16001 }
    Stub.templates = {
      UICheckButtonTemplate = true, UIPanelScrollFrameTemplate = true,
      UIPanelCloseButton = true, BackdropTemplate = true,
    }
    Stub.xpTable = NewXPTable()
    Stub.unknownEvents = { UNKNOWN_TEST_EVENT = true }
    Stub.errors = {}   -- kept across a keepWorld restart so the runner still sees them
    Stub.theme = "actuel"          -- legacy tests keep testing the classic look (SPEC-themes 8.1)
    Stub.missingFonts = {}         -- font paths whose SetFont fails (kept across a restart)
  end

  Stub.combat, Stub.shift = false, false
  Stub.target = nil
  Stub.party = {}                -- levels of party1..party4 (nil: no such member)
  Stub.printed, Stub.displayed, Stub.popups = {}, {}, {}
  Stub.requests, Stub.requestLog = 0, {}
  Stub.onUpdateCount = 0
  Stub.calls = { GetMapInfo = 0, GetBestMapForUnit = 0, GetFramerate = 0, GetNetStats = 0,
                 UpdateAddOnMemoryUsage = 0, UpdateAddOnCPUUsage = 0, SetFont = 0, GetStringWidth = 0 }
  Stub.ns = nil

  eventFrames = {}
  timers = {}
  timerSeq = 0
  currentTimer = nil
  errorHandler = DefaultErrorHandler
  Stub.templateInit = DefaultTemplateInit()

  Stub.created, Stub.regions = nil, nil
  InstallGlobals()
  -- counted from here: what the addon and the test create (not UIParent, the chat frame,
  -- GameTooltip or the font objects)
  Stub.created = { Texture = 0, MaskTexture = 0, FontString = 0, Frame = 0 }
  Stub.regions = {}
  rawset(_G, "TruePlayedDB", nil)

  recording = true
  for i = 1, #installers do installers[i](Stub) end
end

local function ReadToc()
  local f = io.open(Stub.ROOT .. "TruePlayed_Camelot.toc", "r")
  if not f then return nil end
  local files = {}
  for raw in f:lines() do
    local line = raw:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      files[#files + 1] = (line:gsub("\\", "/"))
    end
  end
  f:close()
  if #files == 0 then return nil end
  return files
end

-- Stub.theme (SPEC-themes 8.1): written into ns.C.DEFAULTS.theme once every file is
-- loaded, before ADDON_LOADED (nil: the addon's own default). Loaders that replace
-- Stub.LoadAddon (check_globals) call it too.
function Stub.ApplyThemeHook(ns)
  local C = type(ns) == "table" and ns.C
  if Stub.theme ~= nil and type(C) == "table" and type(C.DEFAULTS) == "table" then
    C.DEFAULTS.theme = Stub.theme
  end
end

function Stub.LoadAddon(opts)
  local files = (opts and opts.files) or ReadToc() or Stub.FILES
  local ns = {}
  Stub.ns = ns
  for i = 1, #files do
    local path = Stub.ROOT .. files[i]
    local chunk, err = loadfile(path)
    if not chunk then error("Stub.LoadAddon: " .. tostring(err), 2) end
    chunk("TruePlayed", ns)
  end
  Stub.ApplyThemeHook(ns)
  return ns
end

function Stub.Fire(event, ...)
  local list = eventFrames[event]
  if list and list.n > 0 then DispatchEvent(list, event, ...) end
end

-- Advances GetTime / time() / server by sec, in steps of `step` (default 1.0);
-- due timers fire at the end of each step. Advance(0) runs the timers due now.
-- Allocation-free when only the ticker is due.
function Stub.Advance(sec, step)
  sec = tonumber(sec) or 0
  if sec < 0 then sec = 0 end
  step = tonumber(step) or 1.0
  if step <= 0 then step = 1.0 end
  local startG = clock.g
  local target = startG + sec
  local i = 0
  while true do
    i = i + 1
    local ng = startG + i * step
    if ng >= target - EPS then ng = target end
    local dt = ng - clock.g
    if dt > 0 then
      clock.g = ng
      local srv = Stub.server
      if not srv.frozen then
        srv.total = srv.total + dt
        srv.levelPlayed = srv.levelPlayed + dt
      end
    end
    RunDue()
    if ng == target then break end
  end
end

function Stub.Now()
  return clock.g
end

function Stub.LoginSequence(opts)
  local reload = opts and opts.reload == true
  Stub.Fire("ADDON_LOADED", "TruePlayed")
  Stub.Fire("PLAYER_LOGIN")
  Stub.Fire("PLAYER_ENTERING_WORLD", not reload, reload)
  Stub.Advance((opts and opts.settle) or 0)
end

-- What the game writes: only string/number/boolean keys and values and tables;
-- shared references become separate copies after a reload, as in the game.
local function SerializeCopy(v, depth)
  if type(v) ~= "table" then return v end
  if depth > 100 then error("SaveVariables: nesting too deep") end
  local out = {}
  for k, x in pairs(v) do
    local tk, tx = type(k), type(x)
    if (tk == "string" or tk == "number" or tk == "boolean")
      and (tx == "table" or tx == "string" or tx == "number" or tx == "boolean") then
      out[k] = SerializeCopy(x, depth + 1)
    end
  end
  return out
end

function Stub.SaveVariables()
  local db = rawget(_G, "TruePlayedDB")
  if db == nil then
    Stub.saved = nil
  else
    Stub.saved = SerializeCopy(db, 0)
  end
end

function Stub.Logout()
  Stub.Fire("PLAYER_LEAVING_WORLD")
  Stub.Fire("PLAYER_LOGOUT")
  Stub.SaveVariables()
end

-- Adds XP with level-ups (no events). Returns levels gained and the XP gained
-- after the last level-up. server.levelPlayed restarts at 0 on each level-up.
local function ApplyXP(amount)
  local p = Stub.player
  local gained, after = 0, 0
  local remaining = tonumber(amount) or 0
  while remaining > 0 do
    if p.level >= (p.maxLevel or 60) then
      p.xp = 0
      break
    end
    local need = p.max - p.xp
    if remaining >= need then
      remaining = remaining - need
      p.level = p.level + 1
      p.xp = 0
      p.max = Stub.xpTable[p.level] or p.max
      gained = gained + 1
      after = 0
      Stub.server.levelPlayed = 0
    else
      p.xp = p.xp + remaining
      after = after + remaining
      remaining = 0
    end
  end
  return gained, after
end

local function PlayElsewhere(pe)
  local sec = tonumber(pe.sec) or 0
  local xp = tonumber(pe.xp) or 0
  clock.g = clock.g + sec
  local srv = Stub.server
  srv.total = srv.total + sec
  local gained, after = ApplyXP(xp)
  if gained > 0 and xp > 0 then
    srv.levelPlayed = floor(sec * after / xp)   -- time after the last level-up, by XP share
  else
    srv.levelPlayed = srv.levelPlayed + sec
  end
end

function Stub.Restart(opts)
  opts = opts or {}
  if not opts.crash then Stub.Logout() end
  if opts.online then MoveClock(opts.online, true) end
  if opts.offline then MoveClock(opts.offline, false) end
  if opts.playElsewhere then PlayElsewhere(opts.playElsewhere) end
  Stub.Reset({ keepWorld = true })
  if Stub.saved ~= nil then _G.TruePlayedDB = Stub.DeepCopy(Stub.saved) end
  local ns = Stub.LoadAddon({ files = opts.files })
  Stub.LoginSequence({ reload = opts.reload, settle = opts.settle })
  return ns
end

function Stub.SetAFK(v)
  Stub.player.afk = v and true or false
  Stub.Fire("PLAYER_FLAGS_CHANGED", "player")
end

function Stub.SetResting(v)
  Stub.player.resting = v and true or false
  Stub.Fire("PLAYER_UPDATE_RESTING")
end

function Stub.SetTaxi(v)
  Stub.player.taxi = v and true or false
  Stub.Fire(v and "PLAYER_CONTROL_LOST" or "PLAYER_CONTROL_GAINED")
end

function Stub.SetMap(id)
  local p = Stub.player
  p.mapID = id
  local text = id and ZoneTextFor(id)
  if text then p.zoneText = text end
  Stub.Fire("ZONE_CHANGED_NEW_AREA")
end

function Stub.SetInstance(inInstance, instanceType, instanceID, mapID)
  local p = Stub.player
  p.inInstance = inInstance and true or false
  p.instanceType = instanceType or (inInstance and "party" or "none")
  p.instanceID = instanceID or 0
  p.mapID = mapID
  local m = mapID and Stub.maps[mapID]
  if inInstance then
    p.instanceName = (m and m.name) or ("Instance " .. tostring(p.instanceID))
    p.zoneText = p.instanceName
  else
    p.instanceName = ""
    local text = mapID and ZoneTextFor(mapID)
    if text then p.zoneText = text end
  end
  Stub.Fire("ZONE_CHANGED_NEW_AREA")
end

local questSeq = 0
function Stub.GrantXP(amount, opts)
  opts = opts or {}
  local p = Stub.player
  if opts.quest then
    questSeq = questSeq + 1
    Stub.Fire("QUEST_TURNED_IN", opts.questID or questSeq, opts.quest, 0)
  end
  if opts.restDrop then
    p.rest = (p.rest or 0) - opts.restDrop
    if p.rest < 0 then p.rest = 0 end
  end
  local oldLevel = p.level
  ApplyXP(amount)
  local newLevel = p.level
  local exhaustionFirst = opts.order == "exhaustionFirst"
  if opts.restDrop and exhaustionFirst then Stub.Fire("UPDATE_EXHAUSTION") end
  local levelEvents = newLevel > oldLevel and not opts.noLevelEvent
  if levelEvents and opts.levelEventFirst then
    for lvl = oldLevel + 1, newLevel do Stub.Fire("PLAYER_LEVEL_UP", lvl, 0, 0, 0, 0, 0, 0, 0, 0) end
  end
  Stub.Fire("PLAYER_XP_UPDATE", "player")
  if levelEvents and not opts.levelEventFirst then
    for lvl = oldLevel + 1, newLevel do Stub.Fire("PLAYER_LEVEL_UP", lvl, 0, 0, 0, 0, 0, 0, 0, 0) end
  end
  if opts.restDrop and not exhaustionFirst then Stub.Fire("UPDATE_EXHAUSTION") end
end

-- Kills `count` (default 1) mobs worth `base` XP each at once (area damage, or a
-- group share). With a rest pool, as the game: each kill gets a bonus of up to `base`
-- and drains twice its bonus from the pool (the last one partially). Fires one
-- CHAT_MSG_COMBAT_XP_GAIN per kill before the XP update (opts.marker = "after": after
-- it; false: none). The message text is secret inside an instance or with
-- opts.secretText (the addon must never read it). Returns the XP gained.
function Stub.Kill(base, opts)
  opts = opts or {}
  local p = Stub.player
  local count = opts.count or 1
  local gain, drop, pool = 0, 0, p.rest or 0
  for _ = 1, count do
    local d = pool < 2 * base and pool or 2 * base
    pool = pool - d
    drop = drop + d
    gain = gain + base + floor(d / 2 + 0.5)
  end
  local text = (opts.secretText or p.inInstance) and Stub.SECRET
    or ("Kobold dies, you gain " .. tostring(base) .. " experience.")
  local function Markers()
    for _ = 1, count do Stub.Fire("CHAT_MSG_COMBAT_XP_GAIN", text, "", "", "", "", "", 0, 0, "", 0, 0, "") end
  end
  if opts.marker == nil or opts.marker == true then Markers() end
  Stub.GrantXP(gain, { restDrop = drop > 0 and drop or nil })
  if opts.marker == "after" then Markers() end
  return gain
end

-- Discovers a subzone: its XP comes with a zone change and no kill marker (the game
-- prints it as a system message); a discovery never uses the rest pool.
function Stub.Discover(xp)
  Stub.Fire("ZONE_CHANGED")
  Stub.GrantXP(xp)
end

-- Targets a unit (nil: no target) and fires PLAYER_TARGET_CHANGED. Defaults: a live,
-- attackable level-10 beast NPC, tapped by nobody else.
function Stub.SetTarget(t)
  if t ~= nil then
    local d = { dead = false, canAttack = true, isPlayer = false, playerControlled = false,
                tapDenied = false, classification = "normal", creatureType = "Beast", level = 10 }
    for k, v in pairs(t) do d[k] = v end
    t = d
  end
  Stub.target = t
  Stub.Fire("PLAYER_TARGET_CHANGED")
end

-- A fight that ends with the target dead and no XP at all (no XP update, no kill
-- marker): what a server level cap gives. opts: target fields (default: a mob of the
-- player's level), fight (seconds in combat, default 10).
function Stub.KillNoXP(opts)
  opts = opts or {}
  local t = {}
  for k, v in pairs(opts) do if k ~= "fight" then t[k] = v end end
  if t.level == nil then t.level = Stub.player.level end
  Stub.SetTarget(t)
  Stub.EnterCombat()
  Stub.Advance(opts.fight or 10)
  Stub.target.dead = true
  Stub.LeaveCombat()
end

function Stub.SetShift(v)
  Stub.shift = v and true or false
  Stub.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", v and 1 or 0)
end

function Stub.EnterCombat()
  Stub.combat = true
  Stub.Fire("PLAYER_REGEN_DISABLED")
end

function Stub.LeaveCombat()
  Stub.combat = false
  Stub.Fire("PLAYER_REGEN_ENABLED")
end

function Stub.RunSlash(msg)
  local list = rawget(_G, "SlashCmdList")
  local fn = list and list.TRUEPLAYED
  if type(fn) ~= "function" then error("Stub.RunSlash: SlashCmdList.TRUEPLAYED is not defined", 2) end
  return fn(msg or "")
end

function Stub.DeepCopy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = Stub.DeepCopy(v) end
  return out
end

---------------------------------------------------------------------------
-- Additional helpers (non-frozen, additive)
---------------------------------------------------------------------------
function Stub.NewTooltip()
  return CreateFrameImpl("GameTooltip", nil, UIParentObj)
end

function Stub.RunScript(obj, script, ...)
  CallScript(obj, script, ...)
end

function Stub.AcceptPopup(i)
  local rec = Stub.popups[i or #Stub.popups]
  if not rec then error("Stub.AcceptPopup: no popup recorded", 2) end
  local dialogs = rawget(_G, "StaticPopupDialogs")
  local dialog = dialogs and dialogs[rec.which]
  if dialog and dialog.OnAccept then dialog.OnAccept(rec, rec.data, rec.data2) end
end

function Stub.CountRegistered(event)
  local list = eventFrames[event]
  if not list then return 0 end
  local n = 0
  for i = 1, list.n do
    if list[i] then n = n + 1 end
  end
  return n
end

function Stub.CountTimers()
  return #timers
end

-- Initial world. Recording stays off until the first per-test Reset, so globals
-- created while test files are declared are not removed.
Stub.Reset()
recording = false

return Stub
