local ADDON, ns = ...
local L, C, Fmt = ns.L, ns.C, ns.Fmt

-- Graph.lua - FPS / latency history, shown while the FPS / latency text of the widget
-- is hovered; hovering a column of the graph reads the values of that moment.
--
-- Performance contract (SPEC 6):
--   * samples come from the existing tick path only: Tokens.UpdateContext calls
--     Graph.Sample while a visible slot shows FPS or latency. FPS is kept at most once
--     per tick; latency only when it was re-read (every C.NET_INTERVAL s; the game
--     itself refreshes it only about every 30 s, so it is drawn as steps). Both go into
--     ring buffers of C.GRAPH_RING entries with their timestamps, preallocated at the
--     first sample: nothing is allocated per sample;
--   * the panel is created on the first hover (lazy). Its textures and the per-column
--     hover frames are created once and reused with fixed anchors: bars and latency
--     steps move with SetHeight only (a step sits on an invisible stalk of its
--     height), and a draw call happens only when the integer pixel value (or the
--     colour class) of a column changed;
--   * while shown the panel listens to TICK (one refresh per tick) and nothing else. The
--     readout "23 s ago: 58 fps · 112 ms" follows the hovered column through the OnEnter
--     scripts of the columns (no per-frame script). Texts are set only when their values
--     change, and the readout and min / avg / max strings are memoized by their integer
--     key (capped tables, wiped when full): no garbage per tick once warm, hidden or
--     shown, even when the FPS changes every second;
--   * the panel hides as soon as the mouse is over neither the hovered text nor the
--     panel (OnLeave scripts + IsMouseOver checks).
--
-- Themes (SPEC-themes 4.6): Graph.ApplyTheme sets the backdrop colours, the fonts (the
-- display role for the title, the body role for the other texts, same sizes) and the
-- text colours from the `ui` roles of the active theme, at panel creation and on
-- THEME_CHANGED "theme" (the `ui` roles never follow the user's XP / rested colours, so
-- a recolour changes nothing here). The quality colours (good / warn / bad) and the
-- geometry stay.

local math_floor, math_ceil = math.floor, math.ceil
local type, tonumber = type, tonumber
local format = string.format
local CreateFrame, UIParent, GetTime, wipe = CreateFrame, UIParent, GetTime, wipe

local Graph = {}
ns.Graph = Graph
Graph.frame = nil

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------

local CAP          = C.GRAPH_RING or 300   -- samples kept per series (5 min at 1 Hz)
local NCOL         = 60     -- columns: 1 per sample at 1 min, 2 per sample at 30 s, 5 samples per column at 5 min
local COL_W        = 4      -- column width (px)
local PLOT_W       = NCOL * COL_W
local FPS_H        = 40     -- FPS chart height (px)
local LAT_H        = 28     -- latency chart height (px)
local PAD          = 8
local ROW_GAP      = 4
local FPS_SPACING  = 0.9    -- one FPS sample per tick at most (UpdateContext also runs on messages)
local GAP_SLACK    = 2      -- an FPS sample still fills an empty column this long after it (s)
local LAT_HOLD     = (C.NET_INTERVAL or 5) * 2 + 2   -- a latency value holds this long at most (s)
local FPS_ALPHA    = 0.85
local EPS          = 1e-6
local DEFAULT_WINDOW = 60
local DEFAULT_FONT = "Fonts\\FRIZQT__.TTF"
local WINDOW_KEYS  = { [30] = "GRAPH_WINDOW_30", [60] = "GRAPH_WINDOW_60", [300] = "GRAPH_WINDOW_300" }
local MEMO_MAX     = 256    -- strings kept per memo table (readout, FPS stats, latency stats)

local BACKDROP = {
  bgFile = C.TEX_TT_BG, edgeFile = C.TEX_TT_BORDER,
  tile = true, tileSize = 16, edgeSize = 12,
  insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Quality classes, the same thresholds as Fmt.FPS / Fmt.Latency (on rounded values).
local CLASS_COLOR = { C.COLORS.good, C.COLORS.warn, C.COLORS.bad }

local function Round(v)
  return math_floor(v + 0.5)
end

local function FpsClass(v)
  local n = Round(v)
  if n >= 60 then return 1 end
  if n >= 30 then return 2 end
  return 3
end

local function LatClass(v)
  local n = Round(v)
  if n <= 100 then return 1 end
  if n <= 250 then return 2 end
  return 3
end

---------------------------------------------------------------------------
-- Ring buffers (chronological; created at the first sample, never grown)
---------------------------------------------------------------------------

local fpsT, fpsV, latT, latV
local fpsHead, fpsN, latHead, latN = 0, 0, 0, 0

local function NewRing()
  local t = {}
  for i = 1, CAP do t[i] = 0 end
  return t
end

-- now = GetTime() of the tick; fps = the value read this tick (or nil); latHome /
-- latWorld = the latency values when they were re-read this tick (else nil). The
-- latency kept is max(home, world), as the latency token shows.
function Graph.Sample(now, fps, latHome, latWorld)
  if type(now) ~= "number" or now ~= now then return end
  if not fpsT then
    fpsT, fpsV, latT, latV = NewRing(), NewRing(), NewRing(), NewRing()
  end
  if type(fps) == "number" and fps == fps then
    if fpsN == 0 or now - fpsT[fpsHead] >= FPS_SPACING then
      fpsHead = fpsHead % CAP + 1
      fpsT[fpsHead] = now
      fpsV[fpsHead] = (fps > 0) and fps or 0
      if fpsN < CAP then fpsN = fpsN + 1 end
    end
  end
  local home, world = tonumber(latHome), tonumber(latWorld)
  if home or world then
    local ms = home or 0
    if world and world > ms then ms = world end
    if ms ~= ms or ms < 0 then ms = 0 end
    if latN == 0 or now >= latT[latHead] then
      latHead = latHead % CAP + 1
      latT[latHead] = now
      latV[latHead] = ms
      if latN < CAP then latN = latN + 1 end
    end
  end
end

-- Number of FPS and latency samples kept (tests, /tpl perf).
function Graph.SampleCount()
  return fpsN, latN
end

---------------------------------------------------------------------------
-- Panel state (created on the first ShowFor)
---------------------------------------------------------------------------

local panel, fpsBg, latBg, cursor
local titleFS, fpsStats, latStats, readFS, noteFS
local noteY = 0                    -- y of the note row (the rows below follow its height)
local styled = {}                  -- themed texts: FontString, font role, size, ui colour role (x4)
local bars, stalks, segs, riseL, riseR, cols = {}, {}, {}, {}, {}, {}
local barH, barQ, segY, segQ, riseLH, riseRH = {}, {}, {}, {}, {}, {}
local colF, colL = {}, {}          -- column values, -1 = no data
local shown = false
local anchor = nil                 -- the hovered text region the panel belongs to
local hoverCol = nil               -- hovered column, nil = the newest one with data
local newestCol = nil
local window, colDur = 0, 1
local ageTexts = {}                -- [window][k] = age text of column k (built once per window)
local fpsKey, latKey, readKey = -2, -2, -2
local fMin, fMax, fSum, fCnt = 0, 0, 0, 0
local lMin, lMax, lSum, lCnt = 0, 0, 0, 0
-- memoized texts by integer key (the readout memo is wiped when the window changes)
local readMemo, fpsMemo, latMemo = {}, {}, {}
local readMemoN, fpsMemoN, latMemoN = 0, 0, 0

local function CurrentWindow()
  local s = ns.settings
  local g = s and s.graph
  local w = g and tonumber(g.window)
  if w and WINDOW_KEYS[w] then return w end
  return DEFAULT_WINDOW
end

-- "23 s" / "4 min 35 s" (integer seconds).
local function AgeText(age)
  if age < 60 then return format(L.GRAPH_AGE_S_FMT, age) end
  local m = math_floor(age / 60)
  return format(L.GRAPH_AGE_MS_FMT, m, age - m * 60)
end

-- New history length: column duration, title and the age of each column (the start
-- of the column, rounded up: the newest column of the 1 min graph is "1 s ago").
local function SetWindow(w)
  window = w
  colDur = w / NCOL
  local list = ageTexts[w]
  if not list then
    list = {}
    for k = 1, NCOL do
      list[k] = AgeText(math_ceil((NCOL - k + 1) * colDur - EPS))
    end
    ageTexts[w] = list
  end
  titleFS:SetText(format(L.GRAPH_TITLE_FMT, L[WINDOW_KEYS[w]]))
  fpsKey, latKey, readKey = -2, -2, -2
  wipe(readMemo)                   -- its keys hold a column index, not an age
  readMemoN = 0
end

---------------------------------------------------------------------------
-- Column values (allocation free)
---------------------------------------------------------------------------

-- Column k covers (now - (NCOL - k + 1) * colDur, now - (NCOL - k) * colDur]. FPS: the
-- average of its samples, else the last earlier sample when it is recent enough (30 s
-- graph: two columns per sample); latency: the last value read before the column end
-- (a step line). Also the min / avg / max of the samples (FPS) or columns (latency,
-- i.e. time-weighted) of the window.
local function ComputeColumns(now)
  local dur = colDur
  newestCol = nil

  local n, i = fpsN, 0
  if n > 0 then i = (fpsHead - n) % CAP + 1 end
  local lastV, lastT = 0, nil
  local winStart = now - window
  local hold = dur + GAP_SLACK
  local mn, mx, sum, cnt = 1e9, -1, 0, 0
  for k = 1, NCOL do
    local colEnd = now - (NCOL - k) * dur
    local colStart = colEnd - dur
    local s, c = 0, 0
    while n > 0 and fpsT[i] <= colEnd + EPS do
      local t, v = fpsT[i], fpsV[i]
      if t > colStart + EPS then
        s = s + v
        c = c + 1
      end
      if t > winStart + EPS then
        if v < mn then mn = v end
        if v > mx then mx = v end
        sum = sum + v
        cnt = cnt + 1
      end
      lastV, lastT = v, t
      i = i % CAP + 1
      n = n - 1
    end
    if c > 0 then
      colF[k] = s / c
    elseif lastT ~= nil and colEnd - lastT <= hold then
      colF[k] = lastV
    else
      colF[k] = -1
    end
  end
  fMin, fMax, fSum, fCnt = mn, mx, sum, cnt

  n = latN
  if n > 0 then i = (latHead - n) % CAP + 1 end
  local lv, lt = 0, nil
  local lhold = LAT_HOLD + dur
  mn, mx, sum, cnt = 1e9, -1, 0, 0
  for k = 1, NCOL do
    local colEnd = now - (NCOL - k) * dur
    while n > 0 and latT[i] <= colEnd + EPS do
      lv, lt = latV[i], latT[i]
      i = i % CAP + 1
      n = n - 1
    end
    if lt ~= nil and colEnd - lt <= lhold then
      colL[k] = lv
      if lv < mn then mn = lv end
      if lv > mx then mx = lv end
      sum = sum + lv
      cnt = cnt + 1
    else
      colL[k] = -1
    end
    if colF[k] >= 0 or colL[k] >= 0 then newestCol = k end
  end
  lMin, lMax, lSum, lCnt = mn, mx, sum, cnt
end

---------------------------------------------------------------------------
-- Drawing (every call skipped when the pixel value / class did not change)
---------------------------------------------------------------------------

local function SetClassColor(t, q, alpha)
  local c = CLASS_COLOR[q]
  t:SetVertexColor(c[1], c[2], c[3], alpha)
end

local function DrawColumns()
  -- scales: at least 60 fps (next multiple of 30 above), at least 100 ms (multiple of 50)
  local top, ltop = 60, 100
  for k = 1, NCOL do
    if colF[k] > top then top = colF[k] end
    if colL[k] > ltop then ltop = colL[k] end
  end
  top = math_ceil(top / 30 - EPS) * 30
  ltop = math_ceil(ltop / 50 - EPS) * 50

  for k = 1, NCOL do
    -- FPS: one bar per column
    local v = colF[k]
    local h = -1
    if v >= 0 then
      h = Round(v / top * FPS_H)
      if h < 1 and v > 0 then h = 1 end
      if h > FPS_H then h = FPS_H end
    end
    local b = bars[k]
    if h ~= barH[k] then
      if h <= 0 then
        b:Hide()
      else
        b:SetHeight(h)
        if barH[k] <= 0 then b:Show() end
      end
      barH[k] = h
    end
    if h > 0 then
      local q = FpsClass(v)
      if q ~= barQ[k] then
        barQ[k] = q
        SetClassColor(b, q, FPS_ALPHA)
      end
    end

    -- latency: a 2 px step per column, on an invisible stalk of its height
    local lv = colL[k]
    local y = -1
    if lv >= 0 then
      y = Round(lv / ltop * LAT_H) - 1
      if y < 0 then y = 0 elseif y > LAT_H - 2 then y = LAT_H - 2 end
    end
    if y ~= segY[k] then
      local seg = segs[k]
      if y < 0 then
        seg:Hide()
      else
        stalks[k]:SetHeight(y + 1)
        if segY[k] < 0 then seg:Show() end
      end
      segY[k] = y
    end
    if y >= 0 then
      local q = LatClass(lv)
      if q ~= segQ[k] then
        segQ[k] = q
        SetClassColor(segs[k], q, 1)
        SetClassColor(riseL[k], q, 1)
        SetClassColor(riseR[k], q, 1)
      end
    end
  end

  -- risers: drawn by the lower of two neighbouring columns, from its step up to the
  -- other one (at its left edge when the previous column is higher, at its right
  -- edge when the next one is): only Show / Hide / SetHeight
  for k = 1, NCOL do
    local y = segY[k]
    local prev = (k > 1) and segY[k - 1] or -1
    local nxt = (k < NCOL) and segY[k + 1] or -1
    local hl = (y >= 0 and prev > y) and (prev - y + 2) or 0
    local hr = (y >= 0 and nxt > y) and (nxt - y + 2) or 0
    if hl ~= riseLH[k] then
      local r = riseL[k]
      if hl == 0 then
        r:Hide()
      else
        r:SetHeight(hl)
        if riseLH[k] == 0 then r:Show() end
      end
      riseLH[k] = hl
    end
    if hr ~= riseRH[k] then
      local r = riseR[k]
      if hr == 0 then
        r:Hide()
      else
        r:SetHeight(hr)
        if riseRH[k] == 0 then r:Show() end
      end
      riseRH[k] = hr
    end
  end
end

local function IntText(n)
  return format("%d", n)
end

-- "min 58 · avg 60 · max 62" per chart, formatted only when a value changed.
local function UpdateStats()
  local key, a, b, c = -1, 0, 0, 0
  if fCnt > 0 then
    a, b, c = Round(fMin), Round(fSum / fCnt), Round(fMax)
    if c > 999 then c = 999 end
    if b > c then b = c end
    if a > b then a = b end
    key = (a * 1000 + b) * 1000 + c
  end
  if key ~= fpsKey then
    fpsKey = key
    if key < 0 then
      fpsStats:SetText(L.DOTS)
    else
      local s = fpsMemo[key]
      if not s then
        if fpsMemoN >= MEMO_MAX then wipe(fpsMemo); fpsMemoN = 0 end
        s = format(L.GRAPH_MIN_AVG_MAX_FMT, IntText(a), IntText(b), IntText(c))
        fpsMemo[key] = s
        fpsMemoN = fpsMemoN + 1
      end
      fpsStats:SetText(s)
    end
  end
  key = -1
  if lCnt > 0 then
    a, b, c = Round(lMin), Round(lSum / lCnt), Round(lMax)
    if c > 9999 then c = 9999 end
    if b > c then b = c end
    if a > b then a = b end
    key = (a * 10000 + b) * 10000 + c
  end
  if key ~= latKey then
    latKey = key
    if key < 0 then
      latStats:SetText(L.DOTS)
    else
      local s = latMemo[key]
      if not s then
        if latMemoN >= MEMO_MAX then wipe(latMemo); latMemoN = 0 end
        s = format(L.GRAPH_MIN_AVG_MAX_FMT, IntText(a), IntText(b), IntText(c))
        latMemo[key] = s
        latMemoN = latMemoN + 1
      end
      latStats:SetText(s)
    end
  end
end

-- "23 s ago: 58 fps · 112 ms" for the hovered column (else the newest one with data).
local function UpdateReadout()
  if not readFS then return end
  local k = hoverCol or newestCol
  local key, fi, li = 0, -1, -1
  if k ~= nil then
    local f, l = colF[k], colL[k]
    if f >= 0 then
      fi = Round(f)
      if fi > 999 then fi = 999 end
    end
    if l >= 0 then
      li = Round(l)
      if li > 9999 then li = 9999 end
    end
    key = ((k * 1001) + fi + 1) * 10001 + li + 1
  end
  if key == readKey then return end
  readKey = key
  if k == nil then
    readFS:SetText(L.GRAPH_NO_DATA)
    return
  end
  local s = readMemo[key]
  if not s then
    if readMemoN >= MEMO_MAX then wipe(readMemo); readMemoN = 0 end
    local DOTS = L.DOTS
    s = format(L.GRAPH_AGO_FMT, ageTexts[window][k],
      (fi >= 0) and Fmt.FPS(fi) or DOTS, (li >= 0) and Fmt.Latency(li) or DOTS)
    readMemo[key] = s
    readMemoN = readMemoN + 1
  end
  readFS:SetText(s)
end

local function Refresh(now)
  local w = CurrentWindow()
  if w ~= window then SetWindow(w) end
  ComputeColumns(now)
  DrawColumns()
  UpdateStats()
  UpdateReadout()
end

---------------------------------------------------------------------------
-- Scripts (created once) and visibility
---------------------------------------------------------------------------

local function Detach()
  shown = false
  anchor = nil
  hoverCol = nil
  if cursor then cursor:Hide() end
  ns.UnregisterMessage("TICK", Graph)
end

local function OnTick(_, now)
  if shown then Refresh(now or GetTime()) end
end

local function MouseInside()
  if panel and panel:IsMouseOver() then return true end
  return anchor ~= nil and anchor.IsMouseOver ~= nil and anchor:IsMouseOver() == true
end

local function OnPanelLeave()
  if shown and not MouseInside() then Graph.Hide() end
end

local function OnPanelHide()
  if shown then Detach() end
end

local function OnColEnter(self)
  local k = self.tpCol
  hoverCol = k
  cursor:ClearAllPoints()
  cursor:SetPoint("TOPLEFT", fpsBg, "TOPLEFT", (k - 1) * COL_W + math_floor(COL_W / 2), 0)
  cursor:Show()
  UpdateReadout()
end

local function OnColLeave(self)
  if hoverCol == self.tpCol then
    hoverCol = nil
    cursor:Hide()
    UpdateReadout()
  end
  OnPanelLeave()
end

-- Below the text when it sits in the upper half of the screen, above it otherwise; the
-- panel touches the text so the mouse can move into it.
local function IsUpperHalf(owner)
  if not owner.GetCenter then return false end
  local _, cy = owner:GetCenter()
  if not cy then return false end
  local scale = owner.GetEffectiveScale and owner:GetEffectiveScale() or 1
  local height = UIParent and UIParent.GetHeight and UIParent:GetHeight() or 768
  local parentScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  return cy * scale > height * parentScale / 2
end

local function Place(owner)
  panel:ClearAllPoints()
  if IsUpperHalf(owner) then
    panel:SetPoint("TOP", owner, "BOTTOM", 0, 0)
  else
    panel:SetPoint("BOTTOM", owner, "TOP", 0, 0)
  end
end

local function NewText(justify)
  local fs = panel:CreateFontString(nil, "OVERLAY")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.8)
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

-- A text whose font and colour follow the theme (ApplyStyle).
local function StyledText(role, size, uiRole, justify)
  local fs = NewText(justify)
  local n = #styled
  styled[n + 1], styled[n + 2], styled[n + 3], styled[n + 4] = fs, role, size, uiRole
  return fs
end

local function NewTex(layer, sublevel, color, alpha)
  local t = panel:CreateTexture(nil, layer, nil, sublevel)
  t:SetTexture(C.TEX_WHITE)
  t:SetVertexColor(color[1], color[2], color[3], alpha)
  return t
end

-- `ui` colours of the active theme (the classic ones without Themes).
local CLASSIC_UI
local function ActiveUI()
  local Themes = ns.Themes
  local th = Themes and Themes.Active()
  local ui = th and th.ui
  if type(ui) == "table" then return ui end
  if not CLASSIC_UI then
    local K = C.COLORS
    CLASSIC_UI = { bg = K.bg, border = K.border, title = K.value, accent = K.accent,
                   label = K.label, value = K.value, dim = K.dim }
  end
  return CLASSIC_UI
end

-- Backdrop, fonts and text colours (the module keeps its own alphas).
local function ApplyStyle()
  local ui = ActiveUI()
  if panel.SetBackdrop then
    local bg, bd = ui.bg, ui.border
    panel:SetBackdropColor(bg[1], bg[2], bg[3], 0.92)
    panel:SetBackdropBorderColor(bd[1], bd[2], bd[3], 0.35)
  end
  local Themes = ns.Themes
  for i = 1, #styled, 4 do
    local fs, role, size = styled[i], styled[i + 1], styled[i + 2]
    if Themes and Themes.SetFont then
      Themes.SetFont(fs, role, size, "none")
    else
      fs:SetFont(STANDARD_TEXT_FONT or DEFAULT_FONT, size, "")
    end
    local c = ui[styled[i + 3]]
    fs:SetTextColor(c[1], c[2], c[3])
  end
  local v = ui.value
  cursor:SetVertexColor(v[1], v[2], v[3], 0.4)
end

-- Rows below the note: they follow its height (it wraps, and the font may change).
local function LayoutBelowNote()
  local nh = tonumber(noteFS:GetStringHeight()) or 10
  if nh < 10 then nh = 10 end
  local y = noteY - math_ceil(nh) - ROW_GAP
  readFS:ClearAllPoints()
  readFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
  y = y - 13
  panel:SetSize(PLOT_W + 2 * PAD, PAD - y)
end

local function CreatePanel()
  local COLORS = C.COLORS
  panel = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  Graph.frame = panel
  panel:SetFrameStrata("TOOLTIP")
  panel:SetClampedToScreen(true)
  panel:EnableMouse(true)
  if panel.SetBackdrop then panel:SetBackdrop(BACKDROP) end

  -- rows, from the top: title, FPS header + chart, latency header + chart, note, readout
  local y = -PAD
  titleFS = StyledText("display", 11, "title")
  titleFS:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
  y = y - 14 - ROW_GAP
  local fpsLabel = StyledText("body", 10, "label")
  fpsLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
  fpsStats = StyledText("body", 10, "value", "RIGHT")
  fpsStats:SetPoint("TOPRIGHT", panel, "TOPLEFT", PAD + PLOT_W, y)
  y = y - 12 - 2
  fpsBg = NewTex("BACKGROUND", 1, COLORS.track, 0.8)
  fpsBg:SetSize(PLOT_W, FPS_H)
  fpsBg:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
  local plotTop = y
  y = y - FPS_H - ROW_GAP - 2
  local latLabel = StyledText("body", 10, "label")
  latLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
  latStats = StyledText("body", 10, "value", "RIGHT")
  latStats:SetPoint("TOPRIGHT", panel, "TOPLEFT", PAD + PLOT_W, y)
  y = y - 12 - 2
  latBg = NewTex("BACKGROUND", 1, COLORS.track, 0.8)
  latBg:SetSize(PLOT_W, LAT_H)
  latBg:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
  y = y - LAT_H
  local hoverH = plotTop - y
  y = y - ROW_GAP
  local note = StyledText("body", 9, "dim")
  noteFS, noteY = note, y
  note:SetWordWrap(true)
  note:SetWidth(PLOT_W)
  note:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
  readFS = StyledText("body", 10, "value")
  readFS:SetWidth(PLOT_W)

  -- pooled column visuals and hover frames
  local good = COLORS.good
  for k = 1, NCOL do
    local x = (k - 1) * COL_W
    local b = NewTex("ARTWORK", 1, good, FPS_ALPHA)
    b:SetWidth(COL_W - 1)
    b:SetPoint("BOTTOMLEFT", fpsBg, "BOTTOMLEFT", x, 0)
    b:Hide()
    bars[k], barH[k], barQ[k] = b, -1, 1
    -- latency step: an invisible stalk (never hidden: an anchor) sized to the level,
    -- the 2 px step on its top, a riser at each edge going up from the step
    local st = NewTex("BACKGROUND", 2, good, 0)
    st:SetSize(1, 1)
    st:SetPoint("BOTTOMLEFT", latBg, "BOTTOMLEFT", x, 0)
    stalks[k] = st
    local seg = NewTex("ARTWORK", 2, good, 1)
    seg:SetSize(COL_W, 2)
    seg:SetPoint("BOTTOMLEFT", st, "TOPLEFT", 0, -1)
    seg:Hide()
    segs[k], segY[k], segQ[k] = seg, -1, 1
    local rl = NewTex("ARTWORK", 2, good, 1)
    rl:SetWidth(2)
    rl:SetPoint("BOTTOMLEFT", st, "TOPLEFT", 0, -1)
    rl:Hide()
    local rr = NewTex("ARTWORK", 2, good, 1)
    rr:SetWidth(2)
    rr:SetPoint("BOTTOMLEFT", st, "TOPLEFT", COL_W - 2, -1)
    rr:Hide()
    riseL[k], riseR[k], riseLH[k], riseRH[k] = rl, rr, 0, 0
    colF[k], colL[k] = -1, -1
    local col = CreateFrame("Frame", nil, panel)
    col:SetSize(COL_W, hoverH)
    col:SetPoint("TOPLEFT", fpsBg, "TOPLEFT", x, 0)
    col:EnableMouse(true)
    col.tpCol = k
    col:SetScript("OnEnter", OnColEnter)
    col:SetScript("OnLeave", OnColLeave)
    cols[k] = col
  end
  cursor = NewTex("OVERLAY", 1, COLORS.value, 0.4)
  cursor:SetSize(1, hoverH)
  cursor:Hide()

  -- theme (fonts first: a text is set only once its font is), then the static texts and
  -- the rows that follow the note height
  ApplyStyle()
  fpsLabel:SetText(L.TOKEN_FPS)
  latLabel:SetText(L.TOKEN_LATENCY)
  note:SetText(L.GRAPH_LAT_NOTE)
  LayoutBelowNote()

  panel:Hide()
  panel:SetScript("OnLeave", OnPanelLeave)
  panel:SetScript("OnHide", OnPanelHide)

  -- Read-only handles for the offline tests (our own frame).
  panel.tp = { bars = bars, stalks = stalks, segs = segs, riseL = riseL, riseR = riseR, cols = cols,
               colF = colF, colL = colL,
               title = titleFS, fpsStats = fpsStats, latStats = latStats, readout = readFS,
               note = note, cursor = cursor, fpsBg = fpsBg, latBg = latBg,
               fpsLabel = fpsLabel, latLabel = latLabel }
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

-- Shows the panel next to `owner` (the hovered FPS / latency text region).
function Graph.ShowFor(owner)
  if owner == nil then return end
  if not panel then CreatePanel() end
  if owner ~= anchor or not shown then
    anchor = owner
    Place(owner)
  end
  hoverCol = nil
  cursor:Hide()
  readKey = -2
  if not shown then
    shown = true
    panel:Show()
    ns.RegisterMessage("TICK", Graph, OnTick)
  end
  Refresh(GetTime())
end

-- Hides the panel; with `owner`, only when it is shown for that region.
function Graph.Hide(owner)
  if not shown then return end
  if owner ~= nil and owner ~= anchor then return end
  Detach()
  panel:Hide()
end

-- The mouse left the text region: the panel stays while the mouse is over it.
function Graph.LeaveAnchor(owner)
  if not shown or owner ~= anchor then return end
  if panel:IsMouseOver() then return end
  Graph.Hide()
end

function Graph.IsShown()
  return shown
end

function Graph.GetAnchor()
  return anchor
end

-- Theme of the panel (SPEC-themes 4.6): backdrop, fonts and colours of the active theme.
-- Nothing before the panel exists (it takes the theme when it is created).
function Graph.ApplyTheme()
  if not panel then return end
  ApplyStyle()
  LayoutBelowNote()
end

-- A theme switch while the panel exists ("colors": the `ui` roles do not follow the user
-- colours, Themes warns at compile time when a theme makes them).
local function OnThemeChanged(_, _, _, kind)
  if panel and kind ~= "colors" then Graph.ApplyTheme() end
end

if ns.RegisterMessage then
  ns.RegisterMessage("THEME_CHANGED", Graph, OnThemeChanged)
end
