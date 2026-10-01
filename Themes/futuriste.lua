-- Themes/futuriste.lua - "Futuristic" (default theme): neon HUD from the Futuriste board.
-- Orbitron (display: level and XP labels, % marker, titles) + Rajdhani (numbers and text),
-- magenta XP, cyan rested, bevelled navy panels with cyan lines and purple accents.
-- Plain data only (SPEC-themes section 2); the builder runs when the theme is compiled.
-- Art: Media/Themes/futuriste/*.tga, sources in media-src/futuriste/*.svg.
local ADDON, ns = ...

ns.Themes.Register("futuriste", function()
  return {
    name = "THEME_FUTURISTE",
    fonts = { display = "Orbitron", body = "Rajdhani" },   -- Rajdhani has lining figures: num = body
    colors = {
      xp = "#ff2bd6", rested = "#22d3ee",                -- board defaults (data-props)
      label = "#a3bfcf", value = "#f0fbff", dim = "#7f96a9", accent = "#22d3ee",
      pause = "#fbbf24",
      cyan = "#22d3ee", cyanHi = "#67e8f9", cyanPale = "#a5f3fc", ice = "#bae6fd",
      purple = "#a855f7", ink = "#01040b", navy = "#060c1a", mode = "#8ea6b8",
      frost = "#e6f7ff",                                 -- top-row slot text
      note = "#93abbd",                                  -- tooltip secondary values
      head = "#d9eef8",                                  -- tooltip "Level x > y" label
      bright = "#eef8ff",                                -- tooltip values
    },
    media = {
      panel       = { 32, 32, grey = true },  -- filled panel, TL and BR corners cut at 45 deg (14 of 15 texels)
      panel_line  = { 32, 32, grey = true },  -- 1 px outline of the same shape
      scan        = { 8, 8, grey = true },    -- 1 px rows at y = 0 and 4 (tiled)
      hatch       = { 4, 4, grey = true },    -- 1 px column every 4 px (tiled)
      grid        = { 32, 32, grey = true },  -- 1 px row 0 + column 0: HUD grid (tiled)
      dash        = { 16, 2, grey = true },   -- 5 px on, 3 px off (tiled)
      dot         = { 4, 2, grey = true },    -- 1 px dot every 2 px (tiled)
      glow_tl     = { 32, 32, grey = true },  -- quarter radial glow from the top-left corner
      glow_bar    = { 32, 16, grey = true },  -- soft glow around a 2 px accent line
      track_frame = { 32, 32 },               -- baked: 3 px ink + 1 px #67e8f9 line, TL/BR bevel 5 px, ink corners
      bracket     = { 8, 32 },                -- baked "[": ink 3.4 px under cyan 1.5 px, open side right
      diamond     = { 16, 16 },               -- baked title icon: cyan diamond outline + purple core
    },
    bar = {
      pad = 10, gap = 4,
      height = { add = 6, min = 10 },         -- default user height 8 -> 14 px track
      maxAlpha = 0.35,
      layers = {
        -- neon halo around the fill, outside the track (board: box-shadow 10 px and 22 px);
        -- 9 px above and below: the 32-texel glow is drawn 1:1 at the default 14 px track
        { id = "glow", span = "fill", three = { "common/glow", 16, 10 }, pad = { 10, 10 }, top = -9, bottom = -9,
          layer = "BORDER", sub = -2, blend = "ADD", color = "base@.6", when = "bar" },
        -- track: dark navy body, a little lighter at the top, scan lines, 10 % graduations, 50 % mark
        { id = "track", span = "track", layer = "BORDER", sub = 0,
          grad = { "VERTICAL", "#03060e@.93", "#0c1426@.88" }, flat = "#070d1a@.9" },
        { id = "trackScan", span = "track", file = "scan", tile = "HV", layer = "BORDER", sub = 1,
          color = "ice@.05", when = "bar" },
        { id = "ticks", span = "track", ticks = { n = 10 }, layer = "BORDER", sub = 2,
          color = "cyanPale@.26", when = "bar" },
        { id = "mid", span = "track", ticks = { n = 2 }, layer = "BORDER", sub = 3,
          color = "cyanPale@.5", when = "bar" },
        -- rested part (board overlay): lighter rested colour fading out to the right, a darker
        -- lower half, a 1 px hatch every 4 px and a sheen line, all fading the same way. The
        -- board's mask holds 80 % up to 40 % of the width; the linear fades start higher to
        -- keep the same average opacity.
        { id = "rested", span = "rested", layer = "ARTWORK", sub = -4,
          grad = { "HORIZONTAL", "rested+.4@.72", "rested+.4@0" }, flat = "rested+.4@.4" },
        { id = "restShade", span = "rested", band = { 0.5, 1 }, layer = "ARTWORK", sub = -3,
          grad = { "HORIZONTAL", "#000000@.3", "#000000@0" }, flat = "#000000@.15", when = "bar" },
        { id = "restHatch", span = "rested", file = "hatch", tile = "H", layer = "ARTWORK", sub = -2,
          grad = { "HORIZONTAL", "rested+.85@.5", "rested+.85@0" }, flat = "rested+.85@.25", when = "bar" },
        { id = "restSheen", span = "rested", top = 2, h = 1, layer = "ARTWORK", sub = -1,
          grad = { "HORIZONTAL", "rested+.85@.78", "rested+.85@0" }, flat = "rested+.85@.4", when = "bar" },
        -- fill: active colour, shaded light -> dark in four bands (board: +72 % / +12 % / -22 % / -58 %)
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 0, color = "base" },
        { id = "fillTop", span = "fill", band = { 0, 0.28 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#ffffff@.12", "#ffffff@.72" }, flat = "#ffffff@.42", when = "bar" },
        { id = "fillUpper", span = "fill", band = { 0.28, 0.43 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.12" }, flat = "#ffffff@.06", when = "bar" },
        { id = "fillLower", span = "fill", band = { 0.43, 0.70 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#000000@.22", "#000000@0" }, flat = "#000000@.11", when = "bar" },
        { id = "fillBottom", span = "fill", band = { 0.70, 1 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#000000@.58", "#000000@.22" }, flat = "#000000@.4", when = "bar" },
        { id = "fillSheen", span = "fill", top = 2, h = 1, layer = "ARTWORK", sub = 2,
          color = "#ffffff@.6", when = "bar" },
        { id = "fillSegs", span = "track", ticks = { n = 10, clip = "fill" }, layer = "ARTWORK", sub = 3,
          color = "#020612@.5", when = "bar" },
        -- frame (its ink corners hide the track and fill past the bevels), HUD brackets
        { id = "trackFrame", span = "track", nine = { "track_frame", 8, 8 }, pad = { 1, 1 }, top = -1, bottom = -1,
          layer = "ARTWORK", sub = 7, when = "bar" },
        { id = "bracketL", span = "trackStart", file = "bracket", w = 8, align = "right", dx = -2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 0, when = "bar" },
        { id = "bracketR", span = "trackEnd", file = "bracket", flipX = true, w = 8, align = "left", dx = 2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 0, when = "bar" },
        -- end-of-fill marker: glow, 1 px ink ring, bright line
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 12, top = -6, bottom = -6,
          layer = "OVERLAY", sub = 1, blend = "ADD", color = "base+.85@.5", when = "bar" },
        { id = "markerInk", span = "fillEnd", w = 4, top = -5, bottom = -5,
          layer = "OVERLAY", sub = 2, color = "ink@.8", when = "bar" },
        { id = "marker", span = "fillEnd", w = 2, top = -4, bottom = -4,
          layer = "OVERLAY", sub = 3, color = "base+.85", when = "bar" },
      },
      -- background panel (widget.bgAlpha): bevelled navy plate, scan lines, cyan outline,
      -- cyan accent top-left and purple accent bottom-right
      panel = { parts = {
        { id = "panelFill", nine = { "panel", 15, 15 }, color = "navy", alpha = "bg", sub = -8 },
        { id = "panelScan", file = "scan", tile = "HV", inset = { 2, 2, 2, 2 }, color = "cyan@.05",
          alpha = "bg", sub = -7 },
        { id = "panelLine", nine = { "panel_line", 15, 15 }, color = "cyan@.55", alpha = "line", sub = -6 },
        { id = "accentTop", anchor = "TOPLEFT", x = 15, y = 0, w = 96, h = 2, color = "cyan",
          alpha = "line", sub = -5 },
        { id = "accentBottom", anchor = "BOTTOMRIGHT", x = -15, y = 0, w = 84, h = 2, color = "purple",
          alpha = "line", sub = -5 },
      } },
    },
    text = {
      -- display (Orbitron) only on DISPLAY_KEYS texts (level, XP label) and the % marker
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "display", xp = "body", sep = "body", marker = "display", hint = "body" },
      size = { s1 = 3, s2 = 3, s3 = 3, level = 0, levelValue = 5, xpLabel = -1, xp = 3,
               sep = 3, marker = 0, hint = 1 },
      -- box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
      -- and 2-digit ones up to 14, as in Classic
      boxSize = { s1 = 4, s2 = -1, s3 = -1 },
      split = true, splitGap = 5, levelFmt = "upper",
      colors = { label = "cyanPale", value = "value", levelLabel = "cyanPale", levelValue = "#ffffff",
                 xpText = "value", sep = "cyan", marker = "xp+.45", hint = "label", slot3 = "frost",
                 dimmed = "dim" },
      shadow = { color = "ink@.85", x = 1, y = -1 },
    },
    tooltip = {
      width = { 300, 454 }, pad = { 18, 18, 11, 11 }, gap = 8, lineGap = 4,   -- 19 px rows (board 21)
      fonts = { title = { "display", 14 }, body = { "body", 15 }, value = { "body", 15 },
                note = { "body", 14 }, hint = { "body", 13 } },
      colors = { title = "cyanHi", mode = "mode", label = "label", value = "bright", dim = "note",
                 header = "cyanHi", pause = "pause", hint = "dim", levelLabel = "head",
                 levelValue = "xp+.45", levelValueRested = "rested+.45", rested = "rested+.45" },
      panel = { parts = {                   -- tooltip corners are cut top-right and bottom-left
        { id = "bg", nine = { "panel", 15, 15 }, flipX = true, color = "navy@.92", sub = -8 },
        { id = "glowTL", file = "glow_tl", anchor = "TOPLEFT", x = 0, y = 0, w = 256, h = 128,
          color = "cyan@.1", sub = -7 },
        { id = "scan", file = "scan", tile = "HV", inset = { 2, 2, 2, 2 }, color = "cyan@.035", sub = -6 },
        { id = "grid", file = "grid", tile = "HV", inset = { 2, 2, 2, 2 }, color = "cyan@.05", sub = -5 },
        { id = "line", nine = { "panel_line", 15, 15 }, flipX = true, color = "cyan@.72", sub = -4 },
        { id = "accTopGlow", file = "glow_bar", anchor = "TOPLEFT", x = -6, y = 7, w = 172, h = 16,
          blend = "ADD", color = "cyan@.45", sub = -3 },
        { id = "accBottomGlow", file = "glow_bar", anchor = "BOTTOMRIGHT", x = 6, y = -7, w = 84, h = 16,
          blend = "ADD", color = "purple@.45", sub = -3 },
        { id = "accTop", anchor = "TOPLEFT", x = 0, y = 0, w = 160, h = 2,
          grad = { "HORIZONTAL", "cyanHi", "cyan@0" }, flat = "cyanHi@.6", sub = -2 },
        { id = "accLeft", anchor = "TOPLEFT", x = 0, y = 0, w = 2, h = 26, color = "cyanHi", sub = -1 },
        { id = "accBottom", anchor = "BOTTOMRIGHT", x = 0, y = 0, w = 72, h = 2, color = "purple", sub = -2 },
        { id = "accRight", anchor = "BOTTOMRIGHT", x = 0, y = 0, w = 2, h = 22, color = "purple", sub = -1 },
      } },
      titleIcon = { "diamond", 16, 16, gap = 6 },   -- 12 px diamond + 2 px margin: 8 px to the title
      sep = {
        header = { h = 1, above = 7, below = 6, grad = { "HORIZONTAL", "cyan@.6", "cyan@0" } },
        block  = { h = 1, above = 6, below = 5, file = "dash", tile = "H", color = "cyanHi@.3" },
        footer = { h = 1, above = 7, below = 6, mirror = true, grad = { "HORIZONTAL", "cyan@0", "cyan@.35" } },
      },
      leader = { file = "dot", tile = "H", h = 1, y = 7, color = "cyanHi@.24", min = 12 },  -- just above the baseline
      gauge = { w = 176, h = 6, gap = 2, outline = "ink@.6",
                colors = { world = "cyan", dungeon = "purple", raid = "#818cf8", pvp = "#fb923c",
                           taxi = "#f472b6", afk = "#64748b", inn = "#fde68a", city = "#facc15" } },
    },
    ui = { bg = "navy", border = "cyan", title = "cyanHi", accent = "cyan",
           label = "label", value = "bright", dim = "dim" },
  }
end)
