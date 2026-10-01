local ADDON, ns = ...
local L, C = ns.L, ns.C

-- Broker.lua - optional LibDataBroker data source. Nothing is embedded: the object
-- exists only if another addon (EllesmereUI, WTFix, Myslot...) already loaded
-- LibStub + LibDataBroker-1.1. Its text is slot 1 and slot 2 joined by L.SEP; the
-- joined string is rebuilt, and assigned to the LDB object, only when one of the
-- two rendered token strings (or their dim state) changed.

local type, pcall = type, pcall
local IsShiftKeyDown = IsShiftKeyDown

local Broker = {}
ns.Broker = Broker
Broker.obj = nil

local EMPTY = ""
local inited = false
local last1, last2, lastDim1, lastDim2 = nil, nil, nil, nil
local lastText = nil

local function Decorate(text, dim)
  if dim and text ~= EMPTY then
    return C.CC.dim .. text .. C.CC.reset
  end
  return text
end

-- TICK path: allocation free unless a part changed.
local function Update()
  local obj = Broker.obj
  if not obj then return end
  local Tokens = ns.Tokens
  local t1, d1, p1 = Tokens.Render(Tokens.Resolve(1))
  local t2, d2, p2 = Tokens.Render(Tokens.Resolve(2))
  if t1 == nil then t1 = EMPTY end
  if t2 == nil then t2 = EMPTY end
  d1 = (d1 or p1) and true or false
  d2 = (d2 or p2) and true or false
  if t1 == last1 and t2 == last2 and d1 == lastDim1 and d2 == lastDim2 then return end
  last1, last2, lastDim1, lastDim2 = t1, t2, d1, d2
  local a, b = Decorate(t1, d1), Decorate(t2, d2)
  local text
  if a == EMPTY then
    text = b
  elseif b == EMPTY then
    text = a
  else
    text = a .. L.SEP .. b
  end
  if text ~= lastText then
    lastText = text
    obj.text = text
  end
end

local function OnMessage()
  Update()
end

local function OnClick(frame, button)
  if button == "RightButton" then
    if ns.Options then ns.Options.ShowContextMenu(frame) end
  else
    if ns.Window then ns.Window.Toggle() end
  end
end

local function OnTooltipShow(tt)
  if type(tt) ~= "table" or not ns.Tooltip then return end
  ns.Tooltip.Fill(tt, IsShiftKeyDown() and true or false)
end

function Broker.Init()
  if inited then return end
  inited = true
  if type(LibStub) ~= "table" or type(LibStub.GetLibrary) ~= "function" then return end
  local ok, ldb = pcall(LibStub.GetLibrary, LibStub, "LibDataBroker-1.1", true)
  if not ok or type(ldb) ~= "table" or type(ldb.NewDataObject) ~= "function" then return end
  local obj = ldb:NewDataObject(ns.ADDON or ADDON, {
    type = "data source",
    text = EMPTY,
    label = L.ADDON_TITLE,
    icon = C.ICON,
    OnClick = OnClick,
    OnTooltipShow = OnTooltipShow,
  })
  if not obj then return end             -- name already taken
  Broker.obj = obj
  ns.Tokens.Acquire("broker", 2)         -- also refreshes the token context
  ns.RegisterMessage("TICK", Broker, OnMessage)
  ns.RegisterMessage("SETTINGS_CHANGED", Broker, OnMessage)
  ns.RegisterMessage("DB_SWAPPED", Broker, OnMessage)
  Update()
end

function Broker.OnDBReady()
  Broker.Init()
end

if ns.RegisterMessage then
  ns.RegisterMessage("DB_READY", Broker, Broker.OnDBReady)
end
