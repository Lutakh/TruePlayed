-- Themes/pixel.lua - "Pixel (old school)": 16-bit JRPG look from the Pixel board.
-- Press Start 2P (display: level label, tooltip title; snapped to 8 / 16 px, monochrome) +
-- Pixelify Sans (text and numbers), green XP, sky-blue rested, a segmented 20-block bar in a
-- black / white / black pixel frame, a dithered rested part and a pixel arrow under the fill end.
-- The board's bar is drawn at 1.5x and its art pixel is 2 board px: in game one art pixel is
-- 1 px, and every layer below has integer sizes and offsets (pixel art is drawn at 1:1, the
-- title icon at 2:1; only the tooltip's colour steps are stretched).
local ADDON, ns = ...

ns.Themes.Register("pixel", function()
  return {
    name = "THEME_PIXEL",
    fonts = { display = "PressStart2P", body = "PixelifySans" },
    colors = {
      xp = "#38b000", rested = "#3fa9f5",                -- board defaults
      label = "#c9d0ff", value = "#ffffff", dim = "#a3abea", accent = "#ffd84a",
      yellow = "#ffd84a", lavender = "#d9dcff", ink = "#000000", snow = "#eef0ff",
      navy = "#101442", deep = "#1f236c", dashHi = "#7c84e6", dashLo = "#4d55b8",
      blockLo = "#1c2160", blockMid = "#14184a", blockHi = "#04051a",
    },
    media = {
      frame    = { 16, 16 },                -- baked 9-slice (4 = 4 px): black / #eef0ff / black, outer corner
                                            -- cut, 1 clear gutter texel (lies over the framed area)
      checker  = { 8, 8, grey = true },     -- one pixel in two (tiled dither)
      arrow    = { 16, 16 },                -- baked 9-slice (7 = 7 px): 7 x 5 arrow in the bottom row
      tt_bg    = { 8, 256 },                -- baked six-step window gradient (stretched)
      tt_frame = { 16, 16 },                -- baked 9-slice (7 = 7 px): black (notched) / #f2f3ff / #0a0c2c,
                                            -- 2 px each, + 1 clear gutter texel
      notch    = { 8, 8, grey = true },     -- 9-slice (3 = 3 px) box with 2 x 2 corners cut: hard shadow
      icon     = { 8, 8 },                  -- baked 7 x 7 star, drawn 16 x 16 (2x)
      dash     = { 8, 2, grey = true },     -- 4 px on, 4 px off (tiled)
      dot      = { 8, 2, grey = true },     -- 2 px on, 6 px off (tiled)
    },
    bar = {
      pad = 10, gap = 8,                      -- gap: room for the frame (3 px) and the arrow (5 px)
      height = { add = 4, min = 8 },          -- default user height 8 -> 12 px blocks (board 18 px / 1.5)
      maxAlpha = 0.35,
      layers = {
        -- pixel frame around the track (the black inner ring is the gap colour of the blocks)
        { id = "frame", span = "track", nine = { "frame", 4, 4 }, pad = { 3, 3 }, top = -3, bottom = -3,
          layer = "BORDER", sub = -1, when = "bar" },
        -- empty blocks: 2 px dark top, navy body, 2 px lighter bottom
        { id = "track", span = "track", layer = "BORDER", sub = 0, color = "blockLo" },
        { id = "trackMid", span = "track", top = 0, bottom = 2, layer = "BORDER", sub = 1,
          color = "blockMid", when = "bar" },
        { id = "trackTop", span = "track", top = 0, h = 2, layer = "BORDER", sub = 2,
          color = "blockHi", when = "bar" },
        -- rested part: dithered rested+.25 / rested+.55 body, rested+.8 top line, rested bottom
        -- line, the whole part fading from opaque to 20 % towards its end (board block opacity)
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
          grad = { "HORIZONTAL", "rested+.25", "rested+.25@.2" }, flat = "rested+.25@.6", when = "box" },
        { id = "restBody", span = "rested", top = 1, bottom = 1, layer = "ARTWORK", sub = 0,
          grad = { "HORIZONTAL", "rested+.25", "rested+.25@.2" }, flat = "rested+.25@.6", when = "bar" },
        { id = "restDither", span = "rested", file = "checker", tile = "HV", top = 1, bottom = 1,
          layer = "ARTWORK", sub = 1, grad = { "HORIZONTAL", "rested+.55", "rested+.55@.2" },
          flat = "rested+.55@.6", when = "bar" },
        { id = "restTop", span = "rested", top = 0, h = 1, layer = "ARTWORK", sub = 2,
          grad = { "HORIZONTAL", "rested+.8", "rested+.8@.2" }, flat = "rested+.8@.6", when = "bar" },
        { id = "restLow", span = "rested", band = { 0.92, 1 }, layer = "ARTWORK", sub = 2,   -- 1 px up to H = 18
          grad = { "HORIZONTAL", "rested", "rested@.2" }, flat = "rested@.6", when = "bar" },
        -- fill: 2 px highlight (+45 %), body, 3 px shade (-35 %), stacked opaque layers so that
        -- each band keeps its pixel height whatever the track height
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 3, color = "base", when = "box" },
        { id = "fillLow", span = "fill", layer = "ARTWORK", sub = 3, color = "base-.35", when = "bar" },
        { id = "fillMid", span = "fill", top = 0, bottom = 3, layer = "ARTWORK", sub = 4,
          color = "base", when = "bar" },
        { id = "fillHi", span = "fill", top = 0, h = 2, layer = "ARTWORK", sub = 5,
          color = "base+.45", when = "bar" },
        -- 20 blocks of 5 % (1 px black gaps over everything), white cursor line at the fill end
        { id = "blocks", span = "track", ticks = { n = 20 }, layer = "ARTWORK", sub = 6,
          color = "ink", when = "bar" },
        { id = "marker", span = "fillEnd", w = 1, align = "right", layer = "ARTWORK", sub = 7,
          color = "#ffffff", when = "bar" },
        -- 7 x 5 arrow 3 px under the track, centred on the cursor line: a 9-slice whose only art
        -- is its bottom row, 15 px wide (7 + 1 + 7), so it keeps its pixels at any track height
        { id = "arrow", span = "fillEnd", nine = { "arrow", 7, 7 }, w = 15, dx = -1, top = 0, bottom = -8,
          layer = "OVERLAY", sub = 0, when = "bar" },
      },
      -- navy window behind the bar, framed like the track (board: 14 px wider than the track
      -- on each side, lines at 1.5 x the body opacity)
      panel = { parts = {
        { id = "panelFill", inset = { -1, -1, 5, 6 }, color = "navy", alpha = "bg", sub = -8 },
        { id = "panelLine", nine = { "frame", 4, 4 }, inset = { -4, -4, 2, 3 }, alpha = "line", sub = -7 },
      } },
    },
    text = {
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
      -- level: Press Start 2P snaps to 8 px up to a font size of 14 and to 16 px above
      size = { s1 = 1, s2 = 1, s3 = 1, level = -3, levelValue = 1, xpLabel = 1, xp = 1,
               sep = 1, marker = 1, hint = 0 },
      -- box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
      -- and 2-digit ones up to 14, as in Classic
      boxSize = { s1 = 2, s2 = -2, s3 = -2 },
      split = true, splitGap = 6, levelFmt = "upper",
      colors = { label = "yellow", value = "value", levelLabel = "yellow", levelValue = "value",
                 xpText = "value", sep = "lavender", marker = "value", hint = "lavender",
                 slot3 = "value", dimmed = "dim" },
      shadow = { color = "ink", x = 1, y = -1 },     -- hard pixel drop shadow
    },
    tooltip = {
      -- max width: the widest French XP rows (estimate and warm-up notes) fit uncut
      width = { 340, 560 }, pad = { 22, 22, 17, 16 }, gap = 12, lineGap = 6,
      fonts = { title = { "display", 8 }, body = { "body", 16 }, value = { "body", 16 },
                note = { "body", 14 }, hint = { "body", 12 } },
      colors = { title = "yellow", mode = "dim", label = "label", value = "value", dim = "dim",
                 header = "yellow", hint = "dim", levelLabel = "label", levelValue = "yellow",
                 levelValueRested = "yellow", rested = "rested+.4" },
      panel = { parts = {                     -- JRPG window: hard offset shadow, stepped body, 3 rings
        { id = "shadow", nine = { "notch", 3, 3 }, inset = { 6, -6, 6, -6 }, color = "ink@.45", sub = -8 },
        { id = "bg", file = "tt_bg", inset = { 6, 6, 6, 6 }, sub = -7 },
        { id = "frame", nine = { "tt_frame", 7, 7 }, sub = -6 },
      } },
      titleIcon = { "icon", 16, 16, gap = 6 },
      sep = {
        header = { h = 2, above = 6, below = 5, file = "dash", tile = "H", color = "dashHi" },
        block  = { h = 2, above = 7, below = 5, file = "dot", tile = "H", color = "dashLo" },
        footer = { h = 2, above = 9, below = 6, file = "dash", tile = "H", color = "dashHi" },
      },
      gauge = { w = 176, h = 8, gap = 2, outline = "ink",
                colors = { world = "#56c85a", dungeon = "#e8544a", raid = "#a25cf0", pvp = "#ff8a3d",
                           taxi = "#5ab8ff", afk = "#8a90b8", inn = "#f6757a", city = "#ffd84a" } },
    },
    ui = { bg = "deep", border = "snow", title = "yellow", accent = "yellow",
           label = "label", value = "value", dim = "dim" },
  }
end)
