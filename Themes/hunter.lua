-- Themes/hunter.lua - "Hunter" (class theme) from the Chasseur board: a stitched leather strap
-- with laced bindings and arrow fletchings around the bar, a dark leather tooltip in an oak
-- frame with stitched seams, riveted corners and a hanging feather. Germania One (display:
-- level label, tooltip title) + Signika (text and numbers; it has lining figures, so
-- num = body). Olive XP, sky-blue rested, hunter green (#aad372) accents.
-- Plain data only (SPEC-themes section 2); the builder runs when the theme is compiled.
-- Art: Media/Themes/hunter/*.tga, sources in media-src/hunter/*.svg.
local ADDON, ns = ...

ns.Themes.Register("hunter", function()
  return {
    name = "THEME_HUNTER",
    fonts = { display = "GermaniaOne", body = "Signika" },
    colors = {
      xp = "#7a9a2e", rested = "#5fa8d3",                -- board defaults (data-props)
      label = "#ebdfc3", value = "#fff6e2", dim = "#b3aa94", accent = "#aad372",
      green = "#aad372",                                 -- hunter class colour: labels, marker, title
      greenHi = "#bfe08a",                               -- % texts
      cream = "#f6ead0",                                 -- bar values
      creamSoft = "#efe4c9",                             -- top-row slot text (fps / latency)
      sand = "#d9c7a0",                                  -- separator dot between the bar texts
      parch = "#e8dcbd",                                 -- unlocked hint
      hintGrey = "#aea48e",                              -- tooltip hint line
      ink = "#1a1008",                                   -- outlines, notches, stitch shadow, text shadow
      thread = "#e2c894",                                -- saddle stitching
      strapLow = "#55351c",                              -- strap colour on the row under the track
      bark = "#1b140d",                                  -- track (board 55 % stop)
      leather = "#6a4122", oak = "#8f5e33",
      hide = "#1f1812", hideLo = "#15100b",
    },
    media = {
      strap       = { 32, 32 },               -- baked strap: 1 px ink outline + 4 px leather, 5 px radius
      stitch      = { 8, 2, grey = true },    -- 5 px thread, 3 px gap (tiled)
      fletch      = { 64, 32 },               -- baked arrow fletching (left end)
      binding     = { 16, 32 },               -- baked laced binding over a strap end
      barbs       = { 16, 16, grey = true },  -- "\" feather barbs, 2 px of 8 (tiled)
      trail       = { 16, 16, grey = true },  -- two prints, 8 px apart (tiled)
      mist        = { 32, 8, grey = true },   -- one soft mist wisp
      round       = { 16, 16, grey = true },  -- filled rounded rectangle, 6-texel corners
      panel_line  = { 16, 16, grey = true },  -- 1 px rounded outline, 7-texel corners
      inner_line  = { 16, 16, grey = true },  -- 1 px rounded outline, radius 5, 6-texel corners
      vignette    = { 32, 32, grey = true },  -- inner shadow, 14-texel falloff
      blob        = { 16, 16, grey = true },  -- soft round blob (wood knots, panel light)
      stitch_grid = { 8, 8, grey = true },    -- diagonal 4-on 4-off bands: dashed on every row and column
      tt_wood     = { 32, 32 },               -- baked tooltip oak frame, 10-texel corners
      tt_corner   = { 32, 32 },               -- baked stitched leather corner with a brass rivet
      tt_feather  = { 64, 128 },              -- baked feathers and beads hanging from the rivet
      sep_arrow   = { 256, 8, grey = true },  -- line - arrow - line separator
    },
    bar = {
      pad = 8, gap = 7,                       -- texts clear the 5 px strap by 2 px
      height = { add = 6, min = 10 },         -- default user height 8 -> 14 px track
      maxAlpha = 0.35,
      layers = {
        -- leather strap around the track (board: 5 px padding at x1.5, radius 6)
        { id = "strap", span = "track", nine = { "strap", 8, 8 }, pad = { 5, 5 }, top = -5, bottom = -5,
          layer = "BACKGROUND", sub = 0, when = "bar" },
        -- saddle stitching one row inside each long edge, its dark shadow 1 px right and down.
        -- Layers hang from the track top, so the bottom rows are tall dash columns reaching
        -- H + 1 (thread) and H + 2 (shadow), hidden above by the track and by a strap-coloured
        -- cover on row H.
        { id = "stitchShadowTop", span = "track", file = "stitch", tile = "H", pad = { -1, 1 }, top = -2, h = 1,
          layer = "BACKGROUND", sub = 1, color = "ink@.6", when = "bar" },
        { id = "stitchTop", span = "track", file = "stitch", tile = "H", top = -3, h = 1,
          layer = "BACKGROUND", sub = 2, color = "thread", when = "bar" },
        { id = "stitchShadowBottom", span = "track", file = "stitch", tile = "H", pad = { -1, 1 }, top = 0,
          bottom = -3, layer = "BACKGROUND", sub = 3, color = "ink@.6", when = "bar" },
        { id = "stitchBottom", span = "track", file = "stitch", tile = "H", top = 0, bottom = -2,
          layer = "BACKGROUND", sub = 4, color = "thread", when = "bar" },
        { id = "strapCover", span = "track", top = 0, bottom = -1, layer = "BACKGROUND", sub = 5,
          color = "strapLow", when = "bar" },
        -- track: dark earth, lightest at 55 % (two shaded bands), inner shadow under its top edge
        { id = "track", span = "track", layer = "BORDER", sub = 0, color = "bark" },
        { id = "trackTop", span = "track", band = { 0, 0.55 }, layer = "BORDER", sub = 1,
          grad = { "VERTICAL", "#000000@0", "#000000@.44" }, when = "bar" },
        { id = "trackLow", span = "track", band = { 0.55, 1 }, layer = "BORDER", sub = 1,
          grad = { "VERTICAL", "#000000@.37", "#000000@0" }, when = "bar" },
        { id = "trackShadow", span = "track", top = 0, h = 3, layer = "BORDER", sub = 2,
          grad = { "VERTICAL", "#000000@0", "#000000@.5" }, when = "bar" },
        -- rested part: a trail of prints in the morning mist, fading out to the right
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
          grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
        { id = "restSheen", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.18" }, when = "bar" },
        { id = "restMist", span = "rested", file = "mist", layer = "ARTWORK", sub = 2,
          color = "rested+.8@.35", when = "bar" },
        { id = "restTrail", span = "rested", file = "trail", tile = "H", layer = "ARTWORK", sub = 3,
          color = "rested+.8@.45", when = "bar" },
        -- fill: the active colour, 30 % darker on the left to 22 % lighter at the fill end,
        -- faint feather barbs, light from above and shade below (board sheen)
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 4,
          grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
        { id = "fillBarbs", span = "fill", file = "barbs", tile = "HV", layer = "ARTWORK", sub = 5,
          color = "#ffffff@.07", when = "bar" },
        { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 6,
          grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.3" }, when = "bar" },
        { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 6,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" }, when = "bar" },
        { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 6,
          grad = { "VERTICAL", "#000000@.28", "#000000@0" }, when = "bar" },
        -- notches every 10 %
        { id = "notches", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 7,
          color = "ink@.6", when = "bar" },
        -- arrow fletchings at both ends (board "empennage"), shafts running under the bindings
        { id = "fletchL", span = "trackStart", file = "fletch", w = 45, align = "right", top = -4, bottom = -4,
          layer = "OVERLAY", sub = 0, when = "bar" },
        { id = "fletchR", span = "trackEnd", file = "fletch", flipX = true, w = 45, align = "left",
          top = -4, bottom = -4, layer = "OVERLAY", sub = 0, when = "bar" },
        -- end-of-fill marker in hunter green with its glow
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10, top = -2, bottom = -2,
          layer = "OVERLAY", sub = 1, color = "green@.55", when = "bar" },
        { id = "marker", span = "fillEnd", w = 2, layer = "OVERLAY", sub = 2, color = "green", when = "bar" },
        -- laced bindings over the strap ends (board "ligatures lacees")
        { id = "bindL", span = "trackStart", file = "binding", w = 10, align = "right", dx = 2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 3, when = "bar" },
        { id = "bindR", span = "trackEnd", file = "binding", w = 10, align = "left", dx = -2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 3, when = "bar" },
      },
      -- background panel (widget.bgAlpha): dark hide in the board's faint vertical gradient
      -- (one ramp over the 9-slice), leather border; 43 px past the frame sides so that the
      -- arrow fletching sits on it, as on the board (the box style fits it to the box)
      panel = { parts = {
        { id = "panelFill", nine = { "round", 6, 7 }, inset = { -43, -43, 0, 0 },
          grad = { "VERTICAL", "hideLo", "#2b2218" }, flat = "hide", alpha = "bg", sub = -8 },
        { id = "panelLine", nine = { "panel_line", 7, 7 }, inset = { -43, -43, 0, 0 }, color = "leather",
          alpha = "bg", sub = -7 },
      } },
    },
    text = {
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
      -- board: Signika 15 px and Germania One 16 px (bar drawn x1.5); Signika is a large font
      size = { s1 = 2, s2 = 2, s3 = 2, level = 3, levelValue = 2, xpLabel = 2, xp = 2,
               sep = 2, marker = 0, hint = 0 },
      -- box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
      -- and 2-digit ones up to 14, as in Classic
      boxSize = { s1 = 2, s2 = -1, s3 = -1 },
      split = true, splitGap = 6, levelFmt = "upper",
      colors = { label = "green", value = "cream", levelLabel = "green", levelValue = "cream",
                 xpText = "cream", sep = "sand", marker = "greenHi", hint = "parch", slot3 = "creamSoft",
                 dimmed = "dim", slot2 = "#f0cf7a" },
      shadow = { color = "ink@.9", x = 1, y = -1 },
    },
    tooltip = {
      width = { 300, 440 }, pad = { 21, 21, 16, 15 }, gap = 12, lineGap = 4,
      fonts = { title = { "display", 21 }, body = { "body", 14 }, value = { "body", 14 },
                note = { "body", 13 }, hint = { "body", 12 } },
      colors = { title = "green", mode = "dim", label = "label", value = "value", dim = "dim",
                 header = "green", pause = "pause", hint = "hintGrey", levelLabel = "label",
                 levelValue = "greenHi", levelValueRested = "greenHi", rested = "rested+.2" },
      panel = { parts = {                   -- dark leather in a 5 px oak frame
        { id = "wood", nine = { "tt_wood", 10, 10 }, sub = -8 },
        { id = "knotTop", anchor = "TOPLEFT", x = 72, y = 0, w = 52, h = 7, file = "blob",
          color = "#3c220e@.7", sub = -7 },
        { id = "knotBottom", anchor = "BOTTOMRIGHT", x = -103, y = 0, w = 40, h = 7, file = "blob",
          color = "#3c220e@.65", sub = -7 },
        { id = "knotRight", anchor = "RIGHT", x = 0, y = 25, w = 7, h = 44, file = "blob",
          color = "#3c220e@.6", sub = -7 },
        -- flat leather band up to the seam (a gradient on a 9-slice repeats in each row);
        -- the gradient is on the plain cover inside the seam
        { id = "inner", nine = { "round", 6, 5 }, inset = { 5, 5, 5, 5 }, color = "hide", sub = -6 },
        -- stitched seam 4 px inside the leather: the dashed grid shows only on the 1 px ring
        -- left between the grid (inset 9) and the opaque cover (inset 10)
        { id = "stitchGrid", file = "stitch_grid", tile = "HV", inset = { 9, 9, 9, 9 },
          color = "thread@.42", sub = -5 },
        { id = "stitchCover", inset = { 10, 10, 10, 10 }, grad = { "VERTICAL", "hideLo", "#271f16" },
          flat = "hide", sub = -4 },
        { id = "light", anchor = "TOPLEFT", x = 12, y = -8, w = 220, h = 100, file = "blob",
          color = "#3a2d1f@.4", sub = -3 },
        { id = "vignette", nine = { "vignette", 14, 16 }, inset = { 5, 5, 5, 5 }, color = "#000000@.3", sub = -2 },
        { id = "innerLine", nine = { "inner_line", 6, 6 }, inset = { 5, 5, 5, 5 }, color = "ink", sub = -1 },
        -- feather hanging from the rivet of the top-left leather corner
        { id = "feather", anchor = "TOPLEFT", x = -39, y = 1, w = 64, h = 128, file = "tt_feather",
          layer = "BORDER", sub = 0 },
        { id = "cornerTL", anchor = "TOPLEFT", x = -1, y = 1, w = 32, h = 32, file = "tt_corner",
          layer = "BORDER", sub = 1 },
        { id = "cornerBR", anchor = "BOTTOMRIGHT", x = 1, y = -1, w = 32, h = 32, file = "tt_corner",
          flipX = true, flipY = true, layer = "BORDER", sub = 1 },
      } },
      sep = {                                -- center: the arrow keeps its shape, the lines stretch
        header = { h = 8, above = 4, below = 5, file = "sep_arrow", center = 48, color = "green" },
        block  = { h = 8, above = 5, below = 5, file = "sep_arrow", center = 48, color = "green" },
        footer = { h = 1, above = 10, below = 6, mirror = true, grad = { "HORIZONTAL", "green@0", "green@.5" } },
      },
      gauge = { w = 170, h = 7, gap = 0, outline = "ink",
                colors = { world = "green", dungeon = "#c86a2a", raid = "#8e6bbf", pvp = "#d0473a",
                           taxi = "#7aaed6", afk = "#8a8478", inn = "#e8c46a", city = "#b89c6c" } },
    },
    ui = { bg = "hide", border = "oak", title = "green", accent = "green",
           label = "label", value = "value", dim = "dim" },
  }
end)
