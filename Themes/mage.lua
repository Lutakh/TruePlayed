-- Themes/mage.lua - "Mage": runic indigo crystal and arcane frost, from the Mage board.
-- Macondo (display: level label, tooltip title) + Spectral (numbers and text; it has lining
-- figures, so num = body). The track sits in a crystal frame with engraved runes and a cyan
-- aura, capped by frost crystals at both ends; the fill is faceted (crystal lattice), arcane
-- dust drifts over the rested part, the end marker is frost white with a cyan and violet
-- glow; the tooltip is a night-blue panel in a crystal rim, with a fading arcane seal behind
-- its header and frost crystals on two corners.
-- Plain data only (SPEC-themes section 2); the builder runs when the theme is compiled.
-- Art: Media/Themes/mage/*.tga, sources in media-src/mage/*.svg.
local ADDON, ns = ...

ns.Themes.Register("mage", function()
  return {
    name = "THEME_MAGE",
    fonts = { display = "Macondo", body = "Spectral" },
    colors = {
      xp = "#a64dff", rested = "#3fc7eb",                -- board defaults (data-props)
      label = "#dfe6f5", value = "#f2f6ff", dim = "#9aa6c4", accent = "#3fc7eb",
      cyanHi = "#5fd3f0",                                -- percent texts, tooltip headers
      ice = "#e8fbff",                                   -- end-of-fill marker
      violet = "#a64dff",                                -- mage class violet: marker halo
      ink = "#07061a", night = "#0a0a22", deep = "#131236", dusk = "#1d1a4c",
      mist = "#b3bdd6",                                  -- separators
      frost = "#e6ecfa",                                 -- top-row slot text
      hint = "#a3acc6",                                  -- tooltip hint line
      bright = "#f4f8ff",                                -- tooltip values
    },
    media = {
      frame      = { 16, 16 },              -- baked crystal rim 9-slice (6-texel corners): outline, sheen, cyan ring
      round      = { 16, 16, grey = true }, -- rounded rectangle, radius 4 (5-texel corners)
      ring       = { 16, 16, grey = true }, -- its 1 px outline (drawn 1:1)
      halo       = { 16, 16, grey = true }, -- soft glow 9-slice (7-texel corners)
      runes      = { 16, 2 },               -- baked rune dashes, cyan and violet (tiled)
      lattice    = { 16, 16, grey = true }, -- crystal lattice lines at +-63 deg (tiled)
      dust       = { 32, 16, grey = true }, -- two sparkles per 32 px (tiled)
      crystal    = { 32, 32 },              -- baked frost crystals + frame cap, texel (28, 8) = track top-left
      corner     = { 64, 64 },              -- baked tooltip corner: rail + crystals, texel (16, 16) = corner
      seal       = { 64, 64 },              -- baked LEFT half of the arcane seal (flipX for the right)
      sep        = { 256, 8 },              -- baked runic separator (cyan lines, diamond)
      sep_school = { 256, 16 },             -- baked footer separator: arcane, fire, frost
    },
    bar = {
      pad = 12, gap = 7,                      -- gap clears the 4 px crystal frame and its aura
      height = { add = 5, min = 6 },          -- default user height 8 -> 13 px track (board: 20 px at 1.5x)
      maxAlpha = 0.35,
      layers = {
        -- cyan aura around the crystal frame
        { id = "aura", span = "track", three = { "common/glow", 16, 10 }, pad = { 8, 8 }, top = -9, bottom = -9,
          layer = "BORDER", sub = -6, blend = "ADD", color = "accent@.3", when = "bar" },
        -- crystal frame: 1 px ink outline, indigo lit from above, cyan inner ring, rune row
        { id = "frame", span = "track", nine = { "frame", 6, 6 }, pad = { 4, 4 }, top = -4, bottom = -4,
          layer = "BORDER", sub = -4, when = "bar" },
        { id = "runes", span = "track", file = "runes", tile = "H", pad = { -6, -6 }, top = -2, h = 1,
          layer = "BORDER", sub = -3, when = "bar" },
        -- track: deep night blue, a little lighter below the middle (board: #05061a / #0c0f2e / #06071c)
        { id = "track", span = "track", band = { 0, 0.55 }, layer = "BORDER", sub = -2,
          grad = { "VERTICAL", "#0c0f2e", "#05061a" }, flat = "#090b24" },
        { id = "trackLow", span = "track", band = { 0.55, 1 }, layer = "BORDER", sub = -2,
          grad = { "VERTICAL", "#06071c", "#0c0f2e" }, flat = "#090b25" },
        -- rested part ("arcane dust"): lighter rested colour fading out, top sheen, sparkles
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 1,
          grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
        { id = "restedHi", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 2,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.18" }, when = "bar" },
        { id = "restedDust", span = "rested", file = "dust", tile = "H", layer = "ARTWORK", sub = 3,
          grad = { "HORIZONTAL", "rested+.8@.8", "rested+.8@.3" }, flat = "rested+.8@.55", when = "bar" },
        -- fill: active colour, darker on the left and brighter at its end (board: -30 % -> +22 %)
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 4,
          grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
        -- gloss: white 30 % -> 8 % on the upper 40 %, gone by 55 %, shade towards the bottom
        { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 5,
          grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.3" }, when = "bar" },
        { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 5,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" }, when = "bar" },
        { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 5,
          grad = { "VERTICAL", "#000000@.28", "#000000@0" }, when = "bar" },
        -- crystal lattice over the fill (board: two white line sets at 7 % and 5 %)
        { id = "fillLattice", span = "fill", file = "lattice", tile = "HV", layer = "ARTWORK", sub = 6,
          color = "#ffffff@.08", when = "bar" },
        -- facets every 10 %, across the whole track
        { id = "ticks", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 7,
          color = "#07061a@.6", when = "bar" },
        -- end-of-fill marker: frost white, cyan glow inside a violet halo (inside the track)
        { id = "markerHalo", span = "fillEnd", file = "common/glow", w = 24, layer = "OVERLAY", sub = 1,
          blend = "ADD", color = "violet@.5", when = "bar" },
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 12, layer = "OVERLAY", sub = 2,
          blend = "ADD", color = "accent@.85", when = "bar" },
        { id = "marker", span = "fillEnd", w = 2, layer = "OVERLAY", sub = 3, color = "ice", when = "bar" },
        -- frost crystals capping both ends of the frame; they grow with the track height
        -- (32 px tall at the default 13 px track)
        { id = "crystalL", span = "trackStart", file = "crystal", w = 32, align = "right", dx = 4,
          top = -8, bottom = -11, layer = "OVERLAY", sub = 0, when = "bar" },
        { id = "crystalR", span = "trackEnd", file = "crystal", flipX = true, w = 32, align = "left", dx = -4,
          top = -8, bottom = -11, layer = "OVERLAY", sub = 0, when = "bar" },
      },
      -- background (widget.bgAlpha): rounded night panel with a cyan line (0.7 x bgAlpha as on
      -- the board), wide enough for the crystals
      panel = { parts = {
        { id = "panelFill", nine = { "round", 5, 5 }, inset = { -20, -20, 0, 0 },
          grad = { "VERTICAL", "night", "#1c1a48" }, flat = "deep", alpha = "bg", sub = -8 },
        { id = "panelLine", nine = { "ring", 5, 5 }, inset = { -20, -20, 0, 0 },
          color = "accent@.7", alpha = "bg", sub = -7 },
      } },
    },
    text = {
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
      -- board: top row 14 px, bottom row 15 px (at 1.5x); Spectral has a small x-height, so it
      -- runs two sizes above the game font
      size = { s1 = 2, s2 = 3, s3 = 2, level = 2, levelValue = 3, xpLabel = 3, xp = 3,
               sep = 3, marker = 0, hint = 1 },
      -- box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
      -- and 2-digit ones up to 14, as in Classic
      boxSize = { s1 = 3, s2 = -1, s3 = -1 },
      split = true, splitGap = 5, levelFmt = "upper",
      colors = { label = "accent", value = "value", levelLabel = "accent", levelValue = "value",
                 xpText = "value", sep = "mist", marker = "cyanHi", hint = "label", slot3 = "frost",
                 dimmed = "dim", slot2 = "#d6b8ff" },
      shadow = { color = "ink@.85", x = 1, y = -1 },
    },
    tooltip = {
      -- max width: the widest French XP rows (estimate and warm-up notes) fit uncut
      width = { 320, 480 }, pad = { 19, 19, 14, 13 }, gap = 12, lineGap = 5,
      fonts = { title = { "display", 19 }, body = { "body", 14 }, value = { "body", 14 },
                note = { "body", 13 }, hint = { "body", 12 } },
      colors = { title = "accent", mode = "dim", label = "label", value = "bright", dim = "dim",
                 header = "cyanHi", hint = "hint", levelLabel = "label", levelValue = "cyanHi",
                 levelValueRested = "cyanHi", rested = "rested+.2" },  -- board: % stays cyan
      panel = { parts = {
        -- cyan aura, crystal rim (outline + 3 px indigo), cyan line, night-blue panel
        { id = "aura", nine = { "halo", 7, 10 }, inset = { -10, -10, -10, -10 }, color = "accent@.25", sub = -8 },
        { id = "rim", nine = { "frame", 6, 6 }, sub = -7 },
        { id = "rimLine", nine = { "ring", 5, 5 }, inset = { 3, 3, 3, 3 }, color = "accent@.45", sub = -6 },
        { id = "bg", nine = { "round", 5, 5 }, inset = { 4, 4, 4, 4 },
          grad = { "VERTICAL", "night", "dusk" }, flat = "deep", sub = -5 },
        { id = "bgLine", nine = { "ring", 5, 5 }, inset = { 4, 4, 4, 4 }, color = "ink", sub = -4 },
        -- glow and arcane seal behind the header (the seal fades out downwards)
        { id = "glow", anchor = "TOP", x = 0, y = -4, w = 260, h = 56, file = "common/glow", blend = "ADD",
          color = "accent@.14", sub = -3 },
        { id = "sealL", anchor = "TOP", x = -32, y = -4, w = 64, h = 64, file = "seal",
          grad = { "VERTICAL", "#ffffff@.15", "#ffffff@1" }, sub = -2 },
        { id = "sealR", anchor = "TOP", x = 32, y = -4, w = 64, h = 64, file = "seal", flipX = true,
          grad = { "VERTICAL", "#ffffff@.15", "#ffffff@1" }, sub = -2 },
        -- frost crystals and runic rails on two corners
        { id = "cornerTL", anchor = "TOPLEFT", x = -16, y = 16, w = 64, h = 64, file = "corner", sub = -1 },
        { id = "cornerBR", anchor = "BOTTOMRIGHT", x = 16, y = -16, w = 64, h = 64, file = "corner",
          flipX = true, flipY = true, sub = -1 },
      } },
      sep = {                                -- center: the runes keep their shape, the lines stretch
        header = { h = 8, above = 4, below = 5, file = "sep", center = 48 },
        block  = { h = 8, above = 5, below = 5, file = "sep", center = 48 },
        footer = { h = 16, above = 5, below = 2, file = "sep_school", center = 72 },
      },
      gauge = { w = 190, h = 7, gap = 1, outline = "ink",
                colors = { world = "#8272f5", dungeon = "accent", raid = "#c77dff", pvp = "#ff6b35",
                           taxi = "#e8b370", afk = "#5a6380", inn = "#ffd6a5", city = "#98a1b8" } },
    },
    ui = { bg = "deep", border = "accent", title = "accent", accent = "cyanHi",
           label = "label", value = "value", dim = "dim" },
  }
end)
