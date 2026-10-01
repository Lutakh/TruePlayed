-- Themes/rogue.lua - "Rogue" class theme, from the Voleur board: a stitched leather sheath
-- with a steel edge, two poisoned daggers pointing outwards, a smoky poison-green fill with
-- bubbles, a gold needle with a hanging tab at the end of the fill; the tooltip is a dark
-- smoky plate in a steel frame with crossed lockpicks, a stack of gold coins and poison drips.
-- IM Fell English SC (display: level, XP label, titles) + Barlow (text and lining figures).
-- Plain data only (SPEC-themes section 2); the builder runs when the theme is compiled.
-- Art: Media/Themes/rogue/*.tga, sources in media-src/rogue/*.svg.
local ADDON, ns = ...

ns.Themes.Register("rogue", function()
  return {
    name = "THEME_ROGUE",
    fonts = { display = "IMFellEnglishSC", body = "Barlow" },   -- Barlow has lining figures: num = body
    colors = {
      xp = "#6fdc3a", rested = "#8a7dff",                 -- board defaults (data-props)
      label = "#e4dfea", value = "#f7f3fb", dim = "#a59fb2", accent = "#fff468",
      gold = "#fff468",                                   -- rogue class colour: labels, needle, coins
      ink = "#0b0a0f",                                    -- outlines and text shadow
      steel = "#7d8592", stitch = "#cebe96", poison = "#6fdc3a",
      lilac = "#e9e4f0",                                  -- top-row slot text
      seam = "#b3acc0",                                   -- middle-dot separators (sep)
      bright = "#fbf8ff",                                 -- tooltip values
      plate = "#0e0b13",                                  -- tooltip plate (darkest)
    },
    media = {
      sheath     = { 64, 32 },               -- baked leather sheath + steel ring, 9-slice 12 texels = 6 px
      track_bed  = { 16, 16 },               -- baked dark track, 2 px radius, inner shadow, 9-slice 6 texels = 3 px
      stitch     = { 16, 16, grey = true },  -- dashes on rows 0 and 15 (tiled H, stretched over the rim)
      mist       = { 32, 8, grey = true },   -- two soft smoke wisps (stretched over the rested part)
      smoke      = { 8, 8, grey = true },    -- 3 px diagonal stripes every 8 px (tiled)
      bubbles    = { 64, 16, grey = true },  -- small soft bubbles (tiled)
      marker     = { 32, 32 },               -- baked gold needle + hanging tab, 9-slice 12 texels = 6 px
      dagger     = { 64, 32 },               -- baked poisoned dagger, point to the left
      panel_rim  = { 16, 16, grey = true },  -- 2 px rim of a 5 px rounded panel, 9-slice 6 texels
      panel_line = { 16, 16, grey = true },  -- 1 px outline of the same shape
      tt_frame   = { 32, 32 },               -- baked steel tooltip frame (rings + 3 px steel), 9-slice 10 texels
      vignette   = { 32, 32, grey = true },  -- inner shadow of the plate, 9-slice 14 texels
      tt_glow    = { 16, 16 },               -- baked soft lighter smoke at 30 % / 18 % of the plate
      stitch_h   = { 8, 256, grey = true },  -- row 0: 4 px on / 4 px off (tiled H, stretched V)
      stitch_v   = { 256, 8, grey = true },  -- column 0: 4 px on / 4 px off (tiled V, stretched H)
      lockpicks  = { 64, 64 },               -- baked crossed lockpicks + coin (top-left corner)
      coins      = { 32, 32 },               -- baked stack of gold coins (bottom-right corner)
      drip       = { 16, 32, grey = true },  -- poison drip with a falling drop, black outline
    },
    bar = {
      pad = 8, gap = 7,                       -- the gap holds the sheath rim and the needle's tab
      height = { add = 5, min = 9 },          -- default user height 8 -> 13 px track (board 20 px at x1.5)
      maxAlpha = 0.35,
      layers = {
        -- leather sheath with its steel edge, saddle stitches on the rims, dark track bed
        { id = "sheath", span = "track", nine = { "sheath", 12, 6 }, pad = { 5, 5 }, top = -5, bottom = -5,
          layer = "BORDER", sub = -4, when = "bar" },
        { id = "stitch", span = "track", file = "stitch", tile = "H", pad = { -2, -2 }, top = -2, bottom = -2,
          layer = "BORDER", sub = -3, color = "stitch@.5", when = "bar" },
        { id = "track", span = "track", layer = "BORDER", sub = 0, color = "#141018", when = "box" },
        { id = "trackBed", span = "track", nine = { "track_bed", 6, 3 }, layer = "BORDER", sub = 0, when = "bar" },
        -- rested part ("shadow smoke"): lighter rested colour fading out, a sheen, two wisps
        { id = "rested", span = "rested", layer = "ARTWORK", sub = -3,
          grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
        { id = "restSheen", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = -2,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.18" }, flat = "#ffffff@.09", when = "bar" },
        { id = "restMist", span = "rested", file = "mist", layer = "ARTWORK", sub = -1,
          color = "rested+.8@.45", when = "bar" },
        -- fill: dark -> active colour -> light (board 0 % / 62 % / 100 %), sheen bands, poison
        -- smoke stripes and bubbles
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 0,
          grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
        { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.3" }, flat = "#ffffff@.18", when = "bar" },
        { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" }, flat = "#ffffff@.04", when = "bar" },
        { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#000000@.3", "#000000@0" }, flat = "#000000@.15", when = "bar" },
        { id = "fillSmoke", span = "fill", file = "smoke", tile = "HV", layer = "ARTWORK", sub = 2,
          color = "#ffffff@.05", when = "bar" },
        { id = "fillBubbles", span = "fill", file = "bubbles", tile = "HV", layer = "ARTWORK", sub = 3,
          color = "#ffffff@.4", when = "bar" },
        -- 10 % graduations over everything in the track
        { id = "ticks", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 4,
          color = "ink@.6", when = "bar" },
        -- poisoned daggers, points outwards, pommels on the sheath ends
        { id = "daggerL", span = "trackStart", file = "dagger", w = 34, align = "right",
          top = -2, bottom = -2, layer = "OVERLAY", sub = 0, when = "bar" },
        { id = "daggerR", span = "trackEnd", file = "dagger", flipX = true, w = 34, align = "left",
          top = -2, bottom = -2, layer = "OVERLAY", sub = 0, when = "bar" },
        -- end of the fill: gold glow, gold needle with its tab hanging under the sheath
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10,
          layer = "OVERLAY", sub = 1, color = "gold@.5", when = "bar" },
        { id = "marker", span = "fillEnd", nine = { "marker", 12, 6 }, w = 12, bottom = -10,
          layer = "OVERLAY", sub = 2, when = "bar" },
      },
      -- background panel (widget.bgAlpha): rounded dark violet plate, 29 px past the frame
      -- sides so that it wraps the daggers, as on the board (the box style fits it to the box)
      panel = { parts = {
        { id = "panelRim", nine = { "panel_rim", 6, 6 }, inset = { -29, -29, 0, 0 }, color = "#18121e",
          alpha = "bg", sub = -8 },
        { id = "panelFill", inset = { -27, -27, 2, 2 }, grad = { "VERTICAL", "#0c0a10", "#241c2c" },
          flat = "#18121e", alpha = "bg", sub = -7 },
        { id = "panelLine", nine = { "panel_line", 6, 6 }, inset = { -29, -29, 0, 0 }, color = "#5c506c@.7",
          alpha = "line", sub = -6 },
      } },
    },
    text = {
      -- display (IM Fell English SC) only on DISPLAY_KEYS texts: the level label
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
      size = { s1 = 1, s2 = 1, s3 = 0, level = 2, levelValue = 1, xpLabel = 1, xp = 1,
               sep = 1, marker = 0, hint = 0 },
      -- box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
      -- and 2-digit ones up to 14, as in Classic
      boxSize = { s1 = 2, s2 = -1, s3 = -1 },
      split = true, splitGap = 4, levelFmt = "upper",
      colors = { label = "gold", value = "value", levelLabel = "gold", levelValue = "value",
                 xpText = "value", sep = "seam", marker = "gold", hint = "lilac", slot3 = "lilac",
                 dimmed = "dim", slot2 = "#a6e87a" },
      shadow = { color = "ink@.85", x = 1, y = -1 },
    },
    tooltip = {
      width = { 300, 440 }, pad = { 20, 20, 15, 14 }, gap = 12, lineGap = 4,
      fonts = { title = { "display", 20 }, body = { "body", 14 }, value = { "body", 14 },
                note = { "body", 13 }, hint = { "body", 12 } },
      colors = { title = "gold", mode = "dim", label = "label", value = "bright", dim = "dim",
                 header = "gold", pause = "pause", hint = "dim", levelLabel = "label",
                 levelValue = "gold", levelValueRested = "gold", rested = "rested+.2" },
      panel = { parts = {
        -- smoky plate: dark base, lighter smoke near the top-left, saddle stitches 4 px inside
        -- the plate (one dashed row / column at the edge of each stretched box), inner shadow,
        -- steel frame
        { id = "plate", inset = { 4, 4, 4, 4 }, grad = { "VERTICAL", "plate", "#16111c" }, flat = "plate", sub = -8 },
        { id = "smoke", file = "tt_glow", inset = { 5, 5, 5, 5 }, sub = -7 },
        { id = "stitchTop", file = "stitch_h", tile = "H", inset = { 12, 12, 8, 8 }, color = "stitch@.32", sub = -6 },
        { id = "stitchBottom", file = "stitch_h", tile = "H", flipY = true, inset = { 12, 12, 8, 8 },
          color = "stitch@.32", sub = -6 },
        { id = "stitchLeft", file = "stitch_v", tile = "V", inset = { 8, 8, 12, 12 }, color = "stitch@.32", sub = -5 },
        { id = "stitchRight", file = "stitch_v", tile = "V", flipX = true, inset = { 8, 8, 12, 12 },
          color = "stitch@.32", sub = -5 },
        { id = "shade", nine = { "vignette", 14, 14 }, inset = { 5, 5, 5, 5 }, color = "#000000@.3", sub = -4 },
        { id = "frame", nine = { "tt_frame", 10, 10 }, sub = -3 },
        -- ornaments: crossed lockpicks and a coin on the top-left corner, coins at the
        -- bottom-right corner, poison dripping from the bottom edge
        { id = "lockpicks", file = "lockpicks", anchor = "TOPLEFT", x = -10, y = 12, w = 64, h = 64, sub = -2 },
        { id = "coins", file = "coins", anchor = "BOTTOMRIGHT", x = 15, y = -12, w = 32, h = 32, sub = -2 },
        { id = "drip", file = "drip", anchor = "BOTTOMLEFT", x = 96, y = -17, w = 9, h = 18,
          color = "poison", sub = -1 },
        { id = "dripSmall", file = "drip", rect = { 0, 0, 16, 18 }, anchor = "BOTTOMLEFT", x = 268, y = -7,
          w = 7, h = 8, color = "poison", sub = -1 },
      } },
      sep = {
        header = { h = 1, above = 7, below = 7, mirror = true, grad = { "HORIZONTAL", "gold@0", "gold@.8" },
                   flat = "gold@.4" },
        block  = { h = 1, above = 7, below = 7, mirror = true, grad = { "HORIZONTAL", "gold@0", "gold@.8" },
                   flat = "gold@.4" },
        footer = { h = 1, above = 9, below = 5, mirror = true, grad = { "HORIZONTAL", "gold@0", "gold@.45" },
                   flat = "gold@.22" },
      },
      gauge = { w = 180, h = 7, gap = 0, outline = "ink",
                colors = { world = "#7d9a6a", dungeon = "gold", raid = "#b48ee0", pvp = "#d0603a",
                           taxi = "#8a9ad8", afk = "#6a6474", inn = "#d9a66b", city = "#9a8878" } },
    },
    ui = { bg = "#19141f", border = "steel", title = "gold", accent = "gold",
           label = "label", value = "bright", dim = "dim" },
  }
end)
