-- tests/stub_ui.lua - UI extension stub (IMPL-4, SPEC-FINAL 9.3).
--
-- Returns an installer run at the end of every Stub.Reset(). By default it installs
-- NOTHING into _G (the frozen stub leaves Settings, MenuUtil, LibStub,
-- MinimalSliderWithSteppersMixin and AddonCompartmentFrame absent, and the other test
-- files rely on that). A test opts in, after Reset and before Stub.LoadAddon(), with:
--
--   Stub.InstallUI({ settings = true, menu = true, ldb = true, compartment = true,
--                    modern = true, colorPicker = true, reload = true })
--                                                           -- every field defaults to true
--
--   settings    : Settings.RegisterCanvasLayoutCategory / RegisterAddOnCategory /
--                 OpenToCategory (shows the canvas frame and runs its OnShow script)
--   menu        : MenuUtil.CreateContextMenu with a recording root description
--   ldb         : LibStub + a minimal LibDataBroker-1.1 (NewDataObject) whose objects
--                 count assignments to `text` (Stub.ui.ldbTextSets)
--   compartment : AddonCompartmentFrame (inert table)
--   modern      : templates WowStyle1DropdownTemplate + MinimalSliderWithSteppersTemplate
--                 declared in Stub.templates, and MinimalSliderWithSteppersMixin. Frames
--                 created from these templates get (through Stub.templateInit) working
--                 Init / SetValue / GetValue / RegisterCallback (slider) or SetupMenu /
--                 GenerateMenu (dropdown; the last generated root is `dropdown._root`).
--                 modern = false keeps both templates absent (fallback controls branch).
--   colorPicker : ColorPickerFrame with the 10.2.5+ API (SetupColorPickerAndShow, as on
--                 Forever: like the game it reports the start colour to swatchFunc);
--                 colorPicker = "legacy" installs the older API only (fields func /
--                 cancelFunc / previousValues, SetColorRGB calls func like the game's
--                 OnColorSelect); false leaves ColorPickerFrame absent.
--   reload      : ReloadUI, which only counts its calls (Stub.ui.reloads); false leaves
--                 it absent.
--   minimap     : OFF unless minimap = true (the other tests and tools/render_snapshot
--                 rely on no minimap): Minimap (a 140 x 140 frame at the top right of
--                 UIParent, centre 1790, 990), GetCursorPosition (Stub.ui.cursorX / cursorY,
--                 set with Stub.ui.Cursor(x, y); screen pixels, minimap scale 1) and, with
--                 minimapShape = "<shape>", GetMinimapShape returning it.
--
-- Helpers: Stub.ui.FindMenuItem(root, text), Stub.ui.ClickMenuItem(item),
-- Stub.ui.IsChecked(item), Stub.ui.CloseSettings(), Stub.ui.categories,
-- Stub.ui.PickColor(r, g, b) / Stub.ui.CancelColor() (the user drags the colour
-- picker, or presses Cancel), Stub.ui.pickerInfo (last SetupColorPickerAndShow info),
-- Stub.ui.pickerShows (times the picker was opened),
-- Stub.ui.opened (OpenToCategory calls), Stub.ui.menus / lastMenu / lastMenuOwner,
-- Stub.ui.ldbObjects[name], Stub.ui.ldbTextSets, Stub.ui.generateMenus (dropdown
-- GenerateMenu calls, SetupMenu included), Stub.ui.reloads (ReloadUI calls),
-- Stub.ui.Cursor(x, y) and Stub.ui.minimap (the Minimap frame, when installed).

local installedByUs = {}          -- global name -> value we installed (undone at Reset)

---------------------------------------------------------------------------
-- Menu descriptions (recording)
---------------------------------------------------------------------------

local Desc = {}
Desc.__index = Desc

local function NewDesc(kind, text)
  return setmetatable({ kind = kind, text = text, children = {} }, Desc)
end

local function Add(self, d)
  self.children[#self.children + 1] = d
  return d
end

function Desc:CreateTitle(text) return Add(self, NewDesc("title", text)) end
function Desc:CreateDivider() return Add(self, NewDesc("divider")) end
function Desc:CreateSpacer() return Add(self, NewDesc("spacer")) end
function Desc:CreateCheckbox(text, isSelected, setSelected, data)
  local d = NewDesc("checkbox", text)
  d.isSelected, d.setSelected, d.data = isSelected, setSelected, data
  return Add(self, d)
end
function Desc:CreateRadio(text, isSelected, setSelected, data)
  local d = NewDesc("radio", text)
  d.isSelected, d.setSelected, d.data = isSelected, setSelected, data
  return Add(self, d)
end
function Desc:CreateButton(text, callback, data)
  local d = NewDesc("button", text)
  d.callback, d.data = callback, data
  return Add(self, d)
end
function Desc:SetEnabled(v) self.enabled = v end
function Desc:SetTooltip(fn) self.tooltip = fn end

local function FindMenuItem(root, text)
  if type(root) ~= "table" then return nil end
  if root.text == text then return root end
  for i = 1, #(root.children or {}) do
    local found = FindMenuItem(root.children[i], text)
    if found then return found end
  end
  return nil
end

local function ClickMenuItem(item)
  if item.kind == "checkbox" or item.kind == "radio" then
    return item.setSelected(item.data)
  elseif item.kind == "button" and item.callback then
    return item.callback(item.data)
  end
end

local function IsChecked(item)
  return item.isSelected ~= nil and item.isSelected(item.data) == true
end

---------------------------------------------------------------------------
-- Template implementations (mixed into frames created from these templates)
---------------------------------------------------------------------------

local SliderMixin = {
  Event = { OnValueChanged = "OnValueChanged" },
  Label = { Left = 1, Right = 2, Top = 3, Min = 4, Max = 5 },
}

local SliderImpl = {}
function SliderImpl:Init(value, minValue, maxValue, steps, formatters)
  self._value, self._min, self._max, self._steps, self._formatters = value, minValue, maxValue, steps, formatters
end
function SliderImpl:RegisterCallback(event, fn, owner)
  self._callbacks = self._callbacks or {}
  self._callbacks[event] = { fn = fn, owner = owner }
end
function SliderImpl:SetValue(v)
  local changed = (v ~= self._value)
  self._value = v
  local cb = changed and self._callbacks and self._callbacks[SliderMixin.Event.OnValueChanged]
  if cb then
    if cb.owner ~= nil then cb.fn(cb.owner, v) else cb.fn(v) end
  end
end
function SliderImpl:GetValue() return self._value end
function SliderImpl:SetEnabled(v) self._enabled = v end
function SliderImpl:FormatValue(v)
  local f = self._formatters and self._formatters[SliderMixin.Label.Right]
  return f and f(v) or nil
end

local activeUI = nil              -- Stub.ui of the current test (GenerateMenu counter)

local DropdownImpl = {}
function DropdownImpl:SetupMenu(generator)
  self._generator = generator
  self:GenerateMenu()
end
function DropdownImpl:GenerateMenu()
  if activeUI then activeUI.generateMenus = activeUI.generateMenus + 1 end
  if self._generator then
    local root = NewDesc("root")
    self._generator(self, root)
    self._root = root
  end
end

local function MixInto(f, impl)
  for k, v in pairs(impl) do f[k] = v end
end

---------------------------------------------------------------------------
-- Colour picker (a plain table: the addon only calls its methods and, with the
-- older API, sets its callback fields)
---------------------------------------------------------------------------

local function NewColorPicker(ui, legacy)
  local p = { _r = 1, _g = 1, _b = 1, _shown = false }
  function p:GetColorRGB() return self._r, self._g, self._b end
  function p:Show()
    if not self._shown then ui.pickerShows = ui.pickerShows + 1 end
    self._shown = true
  end
  function p:Hide() self._shown = false end
  function p:IsShown() return self._shown end
  if legacy then
    function p:SetColorRGB(r, g, b)
      self._r, self._g, self._b = r, g, b
      if type(self.func) == "function" then self.func() end
    end
  else
    function p:SetupColorPickerAndShow(info)
      ui.pickerInfo = info
      self._r, self._g, self._b = info.r or 1, info.g or 1, info.b or 1
      if info.swatchFunc then info.swatchFunc() end   -- the game's OnColorSelect
      self:Show()
    end
  end
  return p
end

---------------------------------------------------------------------------
-- Installer
---------------------------------------------------------------------------

return function(Stub)
  -- Undo what a previous test installed (only values that are still ours).
  for name, value in pairs(installedByUs) do
    if rawget(_G, name) == value then rawset(_G, name, nil) end
    installedByUs[name] = nil
  end

  local ui = {
    opened = 0, openedID = nil, categories = {}, addonCategories = {},
    menus = 0, lastMenu = nil, lastMenuOwner = nil,
    ldbObjects = {}, ldbTextSets = 0, modern = false, generateMenus = 0,
    pickerInfo = nil, pickerShows = 0, pickerLegacy = false, reloads = 0,
    FindMenuItem = FindMenuItem, ClickMenuItem = ClickMenuItem, IsChecked = IsChecked,
  }
  Stub.ui = ui
  activeUI = ui

  -- Template initializers (CreateFrame only accepts a template declared in
  -- Stub.templates, which InstallUI({ modern = true }) does).
  local init = Stub.templateInit
  if type(init) == "table" then
    init.MinimalSliderWithSteppersTemplate = function(f) MixInto(f, SliderImpl) end
    init.WowStyle1DropdownTemplate = function(f) MixInto(f, DropdownImpl) end
  end

  local function Install(name, value)
    if rawget(_G, name) == nil then
      _G[name] = value            -- recorded by the frozen stub, removed at the next Reset
    else
      rawset(_G, name, value)
    end
    installedByUs[name] = value
  end

  -- The user moves the colour picker to r, g, b (the picker calls the addon back).
  function ui.PickColor(r, g, b)
    local p = rawget(_G, "ColorPickerFrame")
    if not p then return end
    if ui.pickerLegacy then
      p:SetColorRGB(r, g, b)
    else
      p._r, p._g, p._b = r, g, b
      local info = ui.pickerInfo
      if info and info.swatchFunc then info.swatchFunc() end
    end
  end

  -- The user presses Cancel: the picker calls cancelFunc with the previous values.
  function ui.CancelColor()
    local p = rawget(_G, "ColorPickerFrame")
    if not p then return end
    if ui.pickerLegacy then
      if type(p.cancelFunc) == "function" then p.cancelFunc(p.previousValues) end
    else
      local info = ui.pickerInfo
      if info and info.cancelFunc then info.cancelFunc({ r = info.r, g = info.g, b = info.b }) end
    end
    p:Hide()
  end

  -- The cursor moves to x, y (screen pixels, what GetCursorPosition returns).
  function ui.Cursor(x, y)
    ui.cursorX, ui.cursorY = x, y
  end

  -- Hides every registered canvas frame (the frozen Hide() runs its OnHide script).
  function ui.CloseSettings()
    for i = 1, #ui.categories do
      local f = ui.categories[i].frame
      if f then f:Hide() end
    end
  end

  function Stub.InstallUI(opts)
    opts = opts or {}
    local function want(k) return opts[k] ~= false end

    if want("settings") then
      Install("Settings", {
        RegisterCanvasLayoutCategory = function(frame, name)
          local cat = { ID = 1000 + #ui.categories, name = name, frame = frame }
          cat.GetID = function(self) return self.ID end
          ui.categories[#ui.categories + 1] = cat
          return cat
        end,
        RegisterAddOnCategory = function(cat)
          ui.addonCategories[#ui.addonCategories + 1] = cat
        end,
        OpenToCategory = function(id)
          ui.opened = ui.opened + 1
          ui.openedID = id
          for i = 1, #ui.categories do
            local cat = ui.categories[i]
            if cat.ID == id then
              cat.frame:Show()      -- the frozen Show() runs OnShow when it was hidden
            end
          end
        end,
      })
    end

    if want("menu") then
      Install("MenuUtil", {
        CreateContextMenu = function(owner, generator)
          local root = NewDesc("root")
          generator(owner, root)
          ui.menus = ui.menus + 1
          ui.lastMenu, ui.lastMenuOwner = root, owner
          return root
        end,
      })
    end

    if want("ldb") then
      local ldb = { objects = {} }
      function ldb:NewDataObject(name, dataobj)
        if self.objects[name] then return nil end
        local store = dataobj or {}
        local proxy = setmetatable({}, {
          __index = store,
          __newindex = function(_, k, v)
            if k == "text" then ui.ldbTextSets = ui.ldbTextSets + 1 end
            store[k] = v
          end,
        })
        self.objects[name] = proxy
        ui.ldbObjects[name] = proxy
        return proxy
      end
      local lib = { libs = { ["LibDataBroker-1.1"] = ldb } }
      function lib:GetLibrary(name, silent)
        local l = self.libs[name]
        if not l and not silent then error("Cannot find a library instance of " .. tostring(name), 2) end
        return l
      end
      setmetatable(lib, { __call = function(self, name, silent) return self:GetLibrary(name, silent) end })
      Install("LibStub", lib)
    end

    if want("compartment") then
      Install("AddonCompartmentFrame", { registeredAddons = {} })
    end

    if want("colorPicker") then
      ui.pickerLegacy = (opts.colorPicker == "legacy")
      Install("ColorPickerFrame", NewColorPicker(ui, ui.pickerLegacy))
    end

    if want("reload") then
      Install("ReloadUI", function() ui.reloads = ui.reloads + 1 end)
    end

    if opts.minimap == true then
      local parent = rawget(_G, "UIParent")
      local mm = CreateFrame("Frame", nil, parent)
      mm:SetSize(140, 140)
      mm:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -20)
      ui.minimap = mm
      ui.cursorX, ui.cursorY = 0, 0
      Install("Minimap", mm)
      Install("GetCursorPosition", function() return ui.cursorX, ui.cursorY end)
      if opts.minimapShape then
        local shape = opts.minimapShape
        Install("GetMinimapShape", function() return shape end)
      end
    end

    Stub.templates = Stub.templates or {}
    if want("modern") then
      ui.modern = true
      Stub.templates.WowStyle1DropdownTemplate = true
      Stub.templates.MinimalSliderWithSteppersTemplate = true
      Install("MinimalSliderWithSteppersMixin", SliderMixin)
    else
      ui.modern = false
      Stub.templates.WowStyle1DropdownTemplate = nil
      Stub.templates.MinimalSliderWithSteppersTemplate = nil
    end
  end
end
