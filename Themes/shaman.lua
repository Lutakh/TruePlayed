-- Themes/shaman.lua - "Shaman": carved stone and storm blue, from the Chaman board.
-- Metamorphous (display: level label, tooltip title) + Nunito Sans (numbers and text; it has
-- lining figures, so num = body). The track sits in a stone frame with incised lines, held by
-- a thunderbird totem at each end, with elemental stones set on top of the frame; the fill
-- is a glossy storm blue with a lightning-white end marker glowing blue; the tooltip is a
-- dark slate panel in a stone rim, with stone brackets and a feather on its corners.
-- Plain data only (SPEC-themes section 2); the builder runs when the theme is compiled.
-- Art: Media/Themes/shaman/*.tga, sources in media-src/shaman/*.svg.
local ADDON, ns = ...

ns.Themes.Register("shaman", function()
  return {
    name = "THEME_SHAMAN",
    fonts = { display = "Metamorphous", body = "NunitoSans" },
    colors = {
      xp = "#1f8fff", rested = "#22d3a4",                -- board defaults (data-props)
      label = "#dfe6ee", value = "#f4f8fc", dim = "#9aa6b3", accent = "#2d8cf0",
      blue = "#0070dd",                                  -- shaman class blue: glows, gauge
      blueHi = "#4aa3ff",                                -- percent texts, tooltip headers
      blueLbl = "#3d9af5",                               -- "XP:" label
      ink = "#0a0e14", stone = "#58626d", stoneHi = "#7c8792",
      slate = "#141b25", slateHi = "#1b2431", slateLo = "#0c1118",
      mist = "#aebacc",                                  -- separators
      frost = "#e6ecf2",                                 -- top-row slot text
      hint = "#a3aebb",                                  -- tooltip hint line
      spark = "#d6ecff",                                 -- end-of-fill marker
    },
    media = {
      rim       = { 16, 16 },              -- baked stone rim 9-slice (7-texel corners): ink outline, stone, light/shade
      stone_tex = { 16, 16 },              -- baked incised-stone tile: lines at +-63 deg, specks
      round     = { 16, 16, grey = true }, -- rounded rectangle, radius 6 (7-texel corners)
      ring      = { 16, 16, grey = true }, -- its 1 px outline (drawn 1:1)
      totem     = { 32, 64 },              -- baked thunderbird totem, cross-bar on the right edge
      stud      = { 32, 32 },              -- baked elemental stone (2x), centre at texel (16, 10)
      corner    = { 64, 64 },              -- baked tooltip corner: bracket + medallion, texel (10, 10) = corner
      feather   = { 16, 32 },              -- baked cord, two beads and a feather
      sep       = { 256, 8 },              -- baked tribal separator (blue lines, diamond)
      sep_elem  = { 256, 16 },             -- baked footer separator: earth, fire, water, air
    },
    bar = {
      pad = 12, gap = 10,                     -- gap clears the 4 px stone frame and the stones on it
                                              -- (art 9.5 px above the track; board: text 10 px above)
      height = { add = 5, min = 6 },          -- default user height 8 -> 13 px track (board: 20 px at 1.5x)
      maxAlpha = 0.35,
      layers = {
        -- stone frame around the track: 1 px ink outline + 3 px carved stone, incised lines
        { id = "frame", span = "track", nine = { "rim", 7, 7 }, pad = { 4, 4 }, top = -4, bottom = -4,
          layer = "BORDER", sub = -4, when = "bar" },
        { id = "frameTex", span = "track", file = "stone_tex", tile = "HV", pad = { 3, 3 }, top = -3, bottom = -3,
          layer = "BORDER", sub = -3, when = "bar" },
        -- track: dark slate, a little lighter below the middle (board: #0a0e14 / #141b25 / #0b1017)
        { id = "track", span = "track", band = { 0, 0.55 }, layer = "BORDER", sub = -2,
          grad = { "VERTICAL", "#141b25", "#0a0e14" }, flat = "#0f141c" },
        { id = "trackLow", span = "track", band = { 0.55, 1 }, layer = "BORDER", sub = -2,
          grad = { "VERTICAL", "#0b1017", "#141b25" }, flat = "#10151e" },
        -- rested part ("spirit breath"): lighter rested colour fading out to the right, top sheen
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 1,
          grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
        { id = "restedHi", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 2,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.18" }, when = "bar" },
        -- fill: active colour, darker on the left and brighter at its end (board: -30 % -> +22 %)
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 3,
          grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
        -- gloss: white 30 % -> 8 % on the upper 40 %, gone by 55 %, shade towards the bottom
        { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.3" }, when = "bar" },
        { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" }, when = "bar" },
        { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#000000@.28", "#000000@0" }, when = "bar" },
        -- notches cut every 10 %, across the whole track
        { id = "ticks", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 5,
          color = "#080c12@.6", when = "bar" },
        -- end-of-fill marker: lightning white with a blue glow (inside the track)
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 14, layer = "ARTWORK", sub = 6,
          blend = "ADD", color = "blue@.9", when = "bar" },
        { id = "marker", span = "fillEnd", w = 2, layer = "ARTWORK", sub = 7, color = "spark", when = "bar" },
        -- the four elemental stones set on the top of the frame, at the middles of the four
        -- quarters (12.5 / 37.5 / 62.5 / 87.5 %, as on the board)
        { id = "stones", span = "track", ticks = { n = 4, w = 16, mid = true }, file = "stud", top = -10, h = 16,
          layer = "OVERLAY", sub = 1, when = "bar" },
        -- thunderbird totems holding both ends: the cross-bar meets the frame at mid-height;
        -- they grow with the track height (44 px tall at the default 13 px track)
        { id = "totemL", span = "trackStart", file = "totem", w = 22, align = "right", dx = -3,
          top = -16, bottom = -15, layer = "OVERLAY", sub = 0, when = "bar" },
        { id = "totemR", span = "trackEnd", file = "totem", flipX = true, w = 22, align = "left", dx = 3,
          top = -16, bottom = -15, layer = "OVERLAY", sub = 0, when = "bar" },
      },
      -- background (widget.bgAlpha): rounded slate panel with a stone line, wide enough for
      -- the totems (board: 44 px beyond the bar at 1.5x)
      panel = { parts = {
        { id = "panelFill", nine = { "round", 7, 7 }, inset = { -20, -20, 0, 0 },
          grad = { "VERTICAL", "ink", "slateHi" }, flat = "#121822", alpha = "bg", sub = -8 },
        { id = "panelLine", nine = { "ring", 7, 7 }, inset = { -20, -20, 0, 0 },
          color = "stone", alpha = "bg", sub = -7 },
      } },
    },
    text = {
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
      -- board: top row 14 px, bottom row 15 px (at 1.5x); Nunito Sans reads like the game font
      -- one size up; the thin Metamorphous level label matches the bold numbers at the same size
      size = { s1 = 1, s2 = 2, s3 = 1, level = 2, levelValue = 2, xpLabel = 2, xp = 2,
               sep = 2, marker = -1, hint = 0 },
      -- box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
      -- and 2-digit ones up to 14, as in Classic
      boxSize = { s1 = 2, s2 = -2, s3 = -2 },
      split = true, splitGap = 5, levelFmt = "upper",
      colors = { label = "blueLbl", value = "value", levelLabel = "accent", levelValue = "value",
                 xpText = "value", sep = "mist", marker = "blueHi", hint = "label", slot3 = "frost",
                 dimmed = "dim", slot2 = "#a8e6a0" },
      shadow = { color = "ink@.85", x = 1, y = -1 },
    },
    tooltip = {
      -- max width: the widest French XP rows (estimate and warm-up notes) fit uncut
      width = { 320, 494 }, pad = { 19, 19, 14, 13 }, gap = 12, lineGap = 5,
      fonts = { title = { "display", 18 }, body = { "body", 14 }, value = { "body", 14 },
                note = { "body", 12 }, hint = { "body", 11 } },
      colors = { title = "accent", mode = "dim", label = "label", value = "value", dim = "dim",
                 header = "blueHi", hint = "hint", levelLabel = "label", levelValue = "blueHi",
                 levelValueRested = "blueHi", rested = "rested+.2" },  -- board: % stays blue
      panel = { parts = {
        -- stone rim (1 px ink outline + 3 px stone) with incised lines, dark slate inside
        { id = "rim", nine = { "rim", 7, 7 }, sub = -8 },
        { id = "rimTex", file = "stone_tex", tile = "HV", inset = { 1, 1, 1, 1 }, sub = -7 },
        { id = "bg", nine = { "round", 7, 7 }, inset = { 4, 4, 4, 4 },
          grad = { "VERTICAL", "slateLo", "slateHi" }, flat = "slate", sub = -6 },
        { id = "bgLine", nine = { "ring", 7, 7 }, inset = { 4, 4, 4, 4 }, color = "ink", sub = -5 },
        -- corner ornaments: feather under the top-left medallion, brackets on two corners
        { id = "feather", anchor = "TOPLEFT", x = -16, y = -4, w = 16, h = 32, file = "feather", sub = -4 },
        { id = "cornerTL", anchor = "TOPLEFT", x = -10, y = 10, w = 64, h = 64, file = "corner", sub = -3 },
        { id = "cornerBR", anchor = "BOTTOMRIGHT", x = 10, y = -10, w = 64, h = 64, file = "corner",
          flipX = true, flipY = true, sub = -3 },
      } },
      sep = {                                -- center: the stones keep their shape, the lines stretch
        header = { h = 8, above = 4, below = 5, file = "sep", center = 48 },
        block  = { h = 8, above = 5, below = 5, file = "sep", center = 48 },
        footer = { h = 16, above = 5, below = 2, file = "sep_elem", center = 80 },
      },
      gauge = { w = 190, h = 7, gap = 1, outline = "ink",
                colors = { world = "#86b255", dungeon = "blue", raid = "#d9a441", pvp = "#b8392b",
                           taxi = "#cdd8e5", afk = "#6b7885", inn = "#e8e2d4", city = "#c8733c" } },
    },
    ui = { bg = "slate", border = "stoneHi", title = "accent", accent = "blueHi",
           label = "label", value = "value", dim = "dim" },
  }
end)
