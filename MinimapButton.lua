local ADDON, ns = ...
local L, C, Util = ns.L, ns.C, ns.Util

-- MinimapButton.lua - the round button on the edge of the minimap (design/NEXT-LOT.md,
-- backlog 3). It gives every piece of information without the XP bar:
--   * hover: the bar's tooltip (Tooltip.ShowFor; Shift: detailed), its hint line naming
--     the left-click action;
--   * left click: the minimap.click action (C.MINIMAP_CLICKS): the statistics window
--     (default), the options, show / hide the XP bar, show / hide the mini display;
--   * right click: the bar's context menu (Options.ShowContextMenu), anchored to the button;
--   * left drag (unless minimap.locked): the button follows the cursor (the frame's own
--     StartMoving: no per-frame script), and on release it snaps back onto the minimap edge
--     at the angle of the cursor around the minimap centre (minimap.angle, degrees);
--   * minimap.shown (default on), /tpl minimap and the context menu show or hide it.
-- The position follows the minimap shape the way LibDBIcon does (GetMinimapShape, set by
-- minimap addons; round when absent). Nothing ticks here: the button is static, and the
-- tooltip refreshes itself while shown.
-- LibDBIcon: it only draws a button for an addon that registers its broker object with
-- it. TruePlayed never does (its broker object, Broker.lua, is a plain data source for
-- display addons), so this button is the only TruePlayed button on the minimap, with or
-- without LibDBIcon loaded. Minimap button collectors find it by its name, as a child of
-- the minimap. Without a Minimap frame (an interface that replaced it), no button.

local math_floor, math_max, math_min, math_sqrt = math.floor, math.max, math.min, math.sqrt
local math_cos, math_sin, math_rad, math_deg = math.cos, math.sin, math.rad, math.deg
local math_atan2 = math.atan2 or math.atan        -- Lua 5.1 (the game) / 5.3+ (offline tests)
local type, tonumber, pcall = type, tonumber, pcall
local CreateFrame = CreateFrame

local MinimapButton = {}
ns.MinimapButton = MinimapButton
MinimapButton.button = nil

local SIZE = 31
local RADIUS = 5                  -- the button's centre this far outside the minimap edge
local DEFAULT_ANGLE = 225
local TEX_BORDER = "Interface\\Minimap\\MiniMap-TrackingBorder"
local TEX_BACK = "Interface\\Minimap\\UI-Minimap-Background"
local TEX_HIGHLIGHT = "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"

-- Minimap shapes (GetMinimapShape): which quadrants are round (q = 1 + right/left + 2 *
-- bottom/top, as LibDBIcon); a square quadrant clamps the button onto its corner.
local SHAPES = {
  ROUND = { true, true, true, true },
  SQUARE = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true },
  ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
  ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true },
  ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true },
  ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true },
  ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
  ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button, minimap
local inited = false
local dragging = false            -- from OnDragStart until the drag ends
local dropped = false             -- a drag just ended: its mouse-up is not a click

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function Settings()
  local s = ns.settings
  return s and s.minimap
end

local function Angle()
  local m = Settings()
  local a = m and tonumber(m.angle)
  if a == nil or a ~= a then return DEFAULT_ANGLE end
  return a
end

-- The left-click action (a C.MINIMAP_CLICKS value; anything else: the statistics).
local function ClickAction()
  local m = Settings()
  local v = m and m.click
  if v == "options" or v == "bar" or v == "mini" then return v end
  return "stats"
end

-- Hint line of the tooltip (read from L at use time: the language is applied after load).
function MinimapButton.Hint(action)
  action = action or ClickAction()
  if action == "options" then return L.TT_HINT_MM_OPTIONS end
  if action == "bar" then return L.TT_HINT_MM_BAR end
  if action == "mini" then return L.TT_HINT_MM_MINI end
  return L.TT_HINT
end

---------------------------------------------------------------------------
-- Position on the minimap edge
---------------------------------------------------------------------------

local function Shape()
  local get = GetMinimapShape                     -- set by minimap addons (rare path)
  if type(get) ~= "function" then return SHAPES.ROUND end
  local ok, shape = pcall(get)
  return ok and SHAPES[shape] or SHAPES.ROUND
end

-- Offset of the button centre from the minimap centre at `angle` degrees.
function MinimapButton.Offset(angle, w, h, quad)
  local a = math_rad(angle)
  local x, y = math_cos(a), math_sin(a)
  local q = 1
  if x < 0 then q = q + 1 end
  if y > 0 then q = q + 2 end
  w, h = w / 2 + RADIUS, h / 2 + RADIUS
  if quad[q] then return x * w, y * h end
  local dw, dh = math_sqrt(2 * w * w) - 10, math_sqrt(2 * h * h) - 10
  return math_max(-w, math_min(x * dw, w)), math_max(-h, math_min(y * dh, h))
end

local function Place()
  if not button then return end
  local x, y = MinimapButton.Offset(Angle(), tonumber(minimap:GetWidth()) or 140,
    tonumber(minimap:GetHeight()) or 140, Shape())
  button:ClearAllPoints()
  button:SetPoint("CENTER", minimap, "CENTER", math_floor(x * 100 + 0.5) / 100, math_floor(y * 100 + 0.5) / 100)
end

-- Angle (degrees, 0..359) of the cursor (else of the button) around the minimap centre;
-- nil when a centre is unknown.
local function DropAngle()
  local mx, my = minimap:GetCenter()
  local px, py
  local cursor = GetCursorPosition
  if type(cursor) == "function" then
    local cx, cy = cursor()
    local s = minimap:GetEffectiveScale() or 1
    if type(cx) == "number" and type(cy) == "number" and s > 0 then px, py = cx / s, cy / s end
  end
  if px == nil then px, py = button:GetCenter() end
  if type(mx) ~= "number" or type(my) ~= "number" or type(px) ~= "number" or type(py) ~= "number" then
    return nil
  end
  local deg = math_floor(math_deg(math_atan2(py - my, px - mx)) + 0.5) % 360
  return deg
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Left click: the minimap.click action.
function MinimapButton.LeftClick()
  local action = ClickAction()
  if action == "options" then
    if ns.Options then ns.Options.Toggle() end
  elseif action == "bar" then
    local w = ns.settings and ns.settings.widget
    local shown = not (w and w.shown)
    ns.Bar.SetShown(shown)
    Util.Print(shown and L.WIDGET_SHOWN or L.WIDGET_HIDDEN)
  elseif action == "mini" then
    if ns.MiniDisplay then ns.MiniDisplay.Toggle() end
  else
    if ns.Window then ns.Window.Toggle() end
  end
end

---------------------------------------------------------------------------
-- Scripts (created once)
---------------------------------------------------------------------------

local function HideTooltip(self)
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.Hide then Tooltip.Hide(self) end
end

local function OnEnter(self)
  if dragging then return end
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.ShowFor then Tooltip.ShowFor(self, MinimapButton.Hint()) end
end

local function OnLeave(self)
  HideTooltip(self)
end

local function OnMouseDown()
  dragging, dropped = false, false
end

local function OnClick(self, mouseButton)
  if dropped then
    dropped = false             -- the release that ends a drag is not a click
    return
  end
  if mouseButton == "RightButton" then
    if ns.Options and ns.Options.ShowContextMenu then ns.Options.ShowContextMenu(self) end
  else
    MinimapButton.LeftClick()
  end
end

local function OnDragStart(self)
  local m = Settings()
  if m and m.locked then return end
  dragging = true
  HideTooltip(self)
  self:StartMoving()
end

local function OnDragStop(self)
  self:StopMovingOrSizing()
  if self.SetUserPlaced then self:SetUserPlaced(false) end   -- nothing kept in the layout cache
  if not dragging then return end
  dragging = false
  dropped = true
  local deg = DropAngle()
  if deg then ns.Core.SetSetting("minimap.angle", deg) end
  Place()                       -- back onto the edge (also when the angle did not change)
end

local function OnHide(self)
  dragging = false
  local Tooltip = ns.Tooltip
  if Tooltip and Tooltip.IsShownFor and Tooltip.IsShownFor(self) then Tooltip.Hide(self) end
end

---------------------------------------------------------------------------
-- Creation (lazy) and visibility
---------------------------------------------------------------------------

local function Create()
  local b = CreateFrame("Button", "TruePlayedMinimapButton", minimap)
  button = b
  MinimapButton.button = b
  b:SetSize(SIZE, SIZE)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:SetMovable(true)
  b:EnableMouse(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  if b.SetDontSavePosition then b:SetDontSavePosition(true) end
  b:SetHighlightTexture(TEX_HIGHLIGHT)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(53, 53)
  border:SetTexture(TEX_BORDER)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  local back = b:CreateTexture(nil, "BACKGROUND")
  back:SetSize(20, 20)
  back:SetTexture(TEX_BACK)
  back:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(17, 17)
  icon:SetTexture(C.ICON)
  icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -6)
  b:SetScript("OnEnter", OnEnter)
  b:SetScript("OnLeave", OnLeave)
  b:SetScript("OnMouseDown", OnMouseDown)
  b:SetScript("OnClick", OnClick)
  b:SetScript("OnDragStart", OnDragStart)
  b:SetScript("OnDragStop", OnDragStop)
  b:SetScript("OnHide", OnHide)
  b.tp = { icon = icon, border = border, back = back }      -- handles for the offline tests
  Place()
end

local function UpdateVisibility()
  minimap = minimap or Minimap                  -- read once it exists (rare path)
  local m = Settings()
  local want = (m == nil or m.shown ~= false) and minimap ~= nil
  if want and not button then Create() end
  if not button then return end
  if want then
    button:Show()
  else
    button:Hide()
  end
end

local function OnSettingsChanged(_, path)
  if path == "minimap.shown" then
    UpdateVisibility()
  elseif path == "minimap.angle" then
    Place()
  end
end

local function OnDBSwapped()
  UpdateVisibility()
  Place()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

function MinimapButton.Init()
  if inited then return end
  inited = true
  ns.RegisterMessage("SETTINGS_CHANGED", MinimapButton, OnSettingsChanged)
  ns.RegisterMessage("DB_SWAPPED", MinimapButton, OnDBSwapped)
  UpdateVisibility()
end

function MinimapButton.SetShown(shown)
  ns.Core.SetSetting("minimap.shown", shown and true or false)
  if inited then UpdateVisibility() end
end

-- /tpl minimap: shows or hides the button, and says how to bring it back.
function MinimapButton.Toggle()
  local m = Settings()
  local shown = not (m == nil or m.shown ~= false)
  MinimapButton.SetShown(shown)
  Util.Print(shown and L.MINIMAP_SHOWN or L.MINIMAP_HIDDEN)
end

function MinimapButton.IsShown()
  return button ~= nil and button:IsShown() and true or false
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", MinimapButton, MinimapButton.Init)
end
