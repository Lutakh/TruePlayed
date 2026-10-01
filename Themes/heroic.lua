-- Themes/heroic.lua - "Heroic fantasy": forged gold and dark leather from the HeroicFantasy board.
-- Cinzel (display: level label, tooltip title) + EB Garamond (text and numbers: the bundled
-- EBGaramond-Medium.ttf draws lining figures by default, which is what the board asks for with
-- lining-nums, so `num` stays the body font), ruby XP, sapphire rested, a jewel fill in a gold
-- frame between two riveted clasps set with a gem of the fill colour.
-- The board's bar is drawn at 1.5x: sizes below are the board's divided by 1.5.
local ADDON, ns = ...

ns.Themes.Register("heroic", function()
  return {
    name = "THEME_HEROIC",
    fonts = { display = "Cinzel", body = "EBGaramond" },
    colors = {
      xp = "#b3122e", rested = "#1f4fb8",                -- board defaults (ruby / sapphire)
      label = "#e3d2a8", value = "#fff1cc", dim = "#bfa97c", accent = "#f0c75e",
      gold = "#c9a44c", goldHi = "#f0c75e", bronze = "#7a5c1e", ink = "#1c1007",
      parchment = "#f3e6c4", cream = "#fff1cc", mode = "#b8a47e", hintText = "#b09a70",
      leather = "#1d140b",
    },
    media = {
      frame      = { 32, 32 },               -- baked 9-slice (14 texels = 7 px): drop shadow, dark outline,
                                             -- gold band, dark + bronze filets, 2 clear gutter texels
      cap        = { 32, 64 },               -- baked left clasp (viewBox 26 x 36 stretched; drawn 18 x (H + 12))
      gem        = { 16, 16, grey = true },  -- clasp gem: white body, 48 % grey lower-left facet
      gem_hi     = { 16, 16 },               -- baked gem overlay: light facet, pale gold rim, specular dot
      pointer    = { 32, 32 },               -- baked 9-slice (14 texels = 7 px): gold diamond in the bottom row
      panel_line = { 16, 16 },               -- baked 9-slice (4 = 4 px): bronze border + faint gold inner line
      tt_bg      = { 32, 32 },               -- baked radial leather gradient + inner shadow (stretched)
      tt_frame   = { 32, 32 },               -- baked 9-slice (9 = 9 px): dark / bronze / dark / gold / dark / bronze
                                             -- rings (8 px) + 1 clear gutter texel
      tt_corner  = { 64, 64 },               -- baked corner filigree, drawn 36 x 36
      hourglass  = { 16, 32 },               -- baked title icon (viewBox 13 x 17 stretched; drawn 13 x 17)
      shadow     = { 32, 32, grey = true },  -- 9-slice (14 = 14 px) soft drop shadow, opaque core (tooltip)
    },
    bar = {
      pad = 16, gap = 8,                      -- room for the clasps (16 px left / right of the track)
      height = { add = 4, min = 8 },          -- default user height 8 -> 12 px track (board 18 px / 1.5)
      maxAlpha = 0.35,
      layers = {
        -- track: dark bronze-black, lightest at a third of its height
        { id = "trackTop", span = "track", band = { 0, 0.35 }, layer = "BORDER", sub = 0,
          grad = { "VERTICAL", "#262017", "#0f0b07" }, flat = "#1b150e" },
        { id = "trackBot", span = "track", band = { 0.35, 1 }, layer = "BORDER", sub = 1,
          grad = { "VERTICAL", "#0b0805", "#262017" }, flat = "#17120c" },
        -- rested part: lighter sapphire fading out to the right, glossy on top, shaded below
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
          grad = { "HORIZONTAL", "rested+.42@.8", "rested+.2@0" }, flat = "rested+.35@.45" },
        { id = "restGloss", span = "rested", band = { 0, 0.45 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.28" }, flat = "#ffffff@.14", when = "bar" },
        { id = "restShade", span = "rested", band = { 0.45, 1 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#000000@.18", "#000000@0" }, flat = "#000000@.09", when = "bar" },
        -- jewel fill: the board's 5-stop gradient (+62 % / +28 % / base / -28 % / -58 %) combined
        -- with its glass reflection (white .38 -> 0 at 52 %, black .22 at the bottom), as
        -- white / black overlays in four bands: +76 % / +46 % / 0 / -37 % / -67 %
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 2, color = "base" },
        { id = "fillTop", span = "fill", band = { 0, 0.18 }, layer = "ARTWORK", sub = 3,
          grad = { "VERTICAL", "#ffffff@.46", "#ffffff@.76" }, flat = "#ffffff@.6", when = "bar" },
        { id = "fillUpper", span = "fill", band = { 0.18, 0.5 }, layer = "ARTWORK", sub = 3,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.46" }, flat = "#ffffff@.22", when = "bar" },
        { id = "fillLower", span = "fill", band = { 0.5, 0.78 }, layer = "ARTWORK", sub = 3,
          grad = { "VERTICAL", "#000000@.37", "#000000@0" }, flat = "#000000@.18", when = "bar" },
        { id = "fillBottom", span = "fill", band = { 0.78, 1 }, layer = "ARTWORK", sub = 3,
          grad = { "VERTICAL", "#000000@.67", "#000000@.37" }, flat = "#000000@.52", when = "bar" },
        { id = "fillEdge", span = "fillEnd", w = 2, align = "right", layer = "ARTWORK", sub = 4,
          color = "base+.82", when = "bar" },
        -- 20 graduations over the whole track, then the inner shadow under the frame's top edge
        { id = "ticks", span = "track", ticks = { n = 20 }, layer = "ARTWORK", sub = 5,
          color = "#140c04@.55", when = "bar" },
        { id = "innerShadow", span = "track", top = 0, h = 3, layer = "ARTWORK", sub = 6,
          grad = { "VERTICAL", "#000000@0", "#000000@.6" }, flat = "#000000@.3", when = "bar" },
        -- forged frame around the track
        { id = "frame", span = "track", nine = { "frame", 14, 7 }, pad = { 6, 6 }, top = -6, bottom = -6,
          layer = "ARTWORK", sub = 7, when = "bar" },
        -- progress mark: glowing cream line with a dark edge, gold diamond pointer below the track
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10, top = -5, bottom = -5,
          layer = "OVERLAY", sub = 0, blend = "ADD", color = "#ffecaa@.5", when = "bar" },
        { id = "markerEdge", span = "fillEnd", w = 4, top = -4, bottom = -4,
          layer = "OVERLAY", sub = 1, color = "ink@.85", when = "bar" },
        { id = "marker", span = "fillEnd", w = 2, top = -3, bottom = -3,
          layer = "OVERLAY", sub = 2, color = "cream", when = "bar" },
        -- 9-slice whose only art is its bottom row: the 7 px diamond stays 1..8 px below the
        -- track whatever the track height (anchors are measured from the track top)
        { id = "pointer", span = "fillEnd", nine = { "pointer", 14, 7 }, w = 16, top = 0, bottom = -8,
          layer = "OVERLAY", sub = 3, when = "bar" },
        -- riveted clasps at both ends, each set with a gem of the fill colour
        { id = "capL", span = "trackStart", file = "cap", w = 18, align = "right", dx = 2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 4, when = "bar" },
        { id = "gemL", span = "trackStart", file = "gem", w = 10, align = "right", dx = -2,
          band = { 0.083, 0.917 }, layer = "OVERLAY", sub = 5, color = "base+.15", when = "bar" },
        { id = "gemHiL", span = "trackStart", file = "gem_hi", w = 10, align = "right", dx = -2,
          band = { 0.083, 0.917 }, layer = "OVERLAY", sub = 6, when = "bar" },
        { id = "capR", span = "trackEnd", file = "cap", flipX = true, w = 18, align = "left", dx = -2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 4, when = "bar" },
        { id = "gemR", span = "trackEnd", file = "gem", flipX = true, w = 10, align = "left", dx = 2,
          band = { 0.083, 0.917 }, layer = "OVERLAY", sub = 5, color = "base+.15", when = "bar" },
        { id = "gemHiR", span = "trackEnd", file = "gem_hi", flipX = true, w = 10, align = "left", dx = 2,
          band = { 0.083, 0.917 }, layer = "OVERLAY", sub = 6, when = "bar" },
      },
      -- dark leather panel with a bronze border, wider than the frame (its CSS drop shadow is
      -- left out: an opaque-core shadow would darken a translucent panel)
      panel = { parts = {
        { id = "panelFill", inset = { -1, -1, 9, 9 }, grad = { "VERTICAL", "#100b06@.97", "#22180e@.97" },
          flat = "#1a1209@.97", alpha = "bg", sub = -8 },
        { id = "panelLine", nine = { "panel_line", 4, 4 }, inset = { -2, -2, 8, 8 }, alpha = "bg", sub = -7 },
      } },
    },
    text = {
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
      -- EB Garamond has a small x-height: one size up keeps the board's proportions legible
      size = { s1 = 1, s2 = 1, s3 = 1, level = 0, levelValue = 2, xpLabel = 1, xp = 1,
               sep = 1, marker = 1, hint = 0 },
      boxSize = { s1 = 3, s2 = 0, s3 = 0 },
      split = true, splitGap = 6, levelFmt = "upper",
      colors = { label = "parchment", value = "parchment", levelLabel = "goldHi", levelValue = "parchment",
                 xpText = "parchment", sep = "parchment", marker = "cream", hint = "parchment",
                 slot3 = "parchment", dimmed = "dim" },
      shadow = { color = "#000000@.85", x = 1, y = -1 },
    },
    tooltip = {
      width = { 320, 484 }, pad = { 28, 28, 22, 18 }, gap = 14, lineGap = 5,
      fonts = { title = { "display", 19 }, body = { "body", 15 }, value = { "body", 15 },
                note = { "body", 14 }, hint = { "body", 13 } },
      colors = { title = "goldHi", mode = "mode", label = "label", value = "value", dim = "dim",
                 header = "goldHi", hint = "hintText", levelLabel = "goldHi", levelValue = "value",
                 levelValueRested = "value", rested = "rested+.55" },
      panel = { parts = {
        { id = "shadow", nine = { "shadow", 14, 14 }, inset = { -12, -12, -2, -18 }, color = "#000000@.65",
          sub = -8 },                         -- board: 0 8px 22px rgba(0, 0, 0, .75)
        { id = "bg", file = "tt_bg", inset = { 4, 4, 4, 4 }, sub = -7 },
        { id = "frame", nine = { "tt_frame", 9, 9 }, sub = -6 },
        -- corner filigree 1 px inside the frame: its straight strokes run along the gold band
        { id = "cornerTL", file = "tt_corner", anchor = "TOPLEFT", x = 1, y = -1, w = 36, h = 36, sub = -5 },
        { id = "cornerTR", file = "tt_corner", flipX = true, anchor = "TOPRIGHT", x = -1, y = -1, w = 36, h = 36,
          sub = -5 },
        { id = "cornerBL", file = "tt_corner", flipY = true, anchor = "BOTTOMLEFT", x = 1, y = 1, w = 36, h = 36,
          sub = -5 },
        { id = "cornerBR", file = "tt_corner", flipX = true, flipY = true, anchor = "BOTTOMRIGHT", x = -1, y = 1,
          w = 36, h = 36, sub = -5 },
      } },
      titleIcon = { "hourglass", 13, 17, gap = 7 },
      sep = {
        header = { h = 1, above = 7, below = 8, mirror = true, grad = { "HORIZONTAL", "gold@0", "gold" } },
        block  = { h = 1, above = 7, below = 8, mirror = true, grad = { "HORIZONTAL", "gold@0", "gold" } },
        footer = { h = 1, above = 9, below = 6, mirror = true, grad = { "HORIZONTAL", "gold@0", "gold@.55" } },
      },
    },
    ui = { bg = "leather", border = "gold", title = "goldHi", accent = "goldHi",
           label = "label", value = "value", dim = "dim" },
  }
end)
