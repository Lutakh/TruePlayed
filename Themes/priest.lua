-- Themes/priest.lua - "Priest" class theme, from the Pretre board: light and shadow. A
-- pearly ivory frame with a silver edge, a halo of light on the left and a shadow eclipse
-- on the right, a lavender fill with soft light rays, a white needle with a hanging tab;
-- the tooltip is a dark violet plate in a pearl frame with stained-glass corners (light at
-- the top-left, shadow at the bottom-right).
-- Philosopher (display: level, titles) + Lora (text; lining figures, so num = body).
-- Plain data only (SPEC-themes section 2): a source text, turned into its table only when the
-- theme is compiled (Themes.Register keeps it compact; M3).
-- Art: Media/Themes/priest/*.tga, sources in media-src/priest/*.svg.
-- Notes on the source text below (it carries no comment): its comments, keyed by the
-- section and id they annotate ("> id": the layers or parts from that one on).
--   colors.xp, rested: board defaults (data-props)
--   colors.ink: outlines and text shadow
--   colors.haze: top-row slot text, hints
--   colors.seam: middle-dot separators (sep)
--   colors.bright: tooltip values
--   media.frame: baked ivory frame + silver ring, 9-slice 14 texels = 7 px
--   media.track_bed: baked dark track, 3 px radius, inner shadow, 9-slice 6 texels = 3 px
--   media.groove: 1 px column every 16 px (tiled H, stretched over the rim)
--   media.rays: slanted light rays (tiled H)
--   media.sparkle: three soft sparkles (tiled)
--   media.glow: one soft light patch (stretched over the rested part)
--   media.marker: baked white needle + hanging tab, 9-slice 12 texels = 6 px
--   media.halo: baked halo of light (left of the bar)
--   media.eclipse: baked shadow eclipse (right of the bar)
--   media.panel_rim: 3 px rim of a 7 px rounded panel, 9-slice 7 texels
--   media.panel_line: 1 px outline of the same shape
--   media.tt_frame: baked pearl tooltip frame (135 deg ivory -> violet), 9-slice 10 texels
--   media.vignette: inner shadow of the plate, 9-slice 14 texels
--   media.tt_glow: baked warm light top-left, violet shade bottom-right
--   media.rose_light: baked stained-glass rose (light colours)
--   media.rose_shadow: baked stained-glass rose (shadow colours)
--   media.strip_light: baked leaded strip, light panes (horizontal)
--   media.strip_shadow: baked leaded strip, shadow panes (horizontal)
--   media.lead_light: baked leaded strip, light panes (vertical)
--   media.lead_shadow: baked leaded strip, shadow panes (vertical)
--   media.sep: baked separator: white fading in, lavender fading out
--   bar.pad, gap: the gap holds the frame rim and the needle's tab
--   bar.height: default user height 8 -> 13 px track (board 20 px at x1.5)
--   bar.layers > frame: pearly ivory frame with a silver edge, panel grooves on the rims, dark
--     track bed
--   bar.layers > rested: rested part ("holy glow"): lighter rested colour fading out, a sheen, a
--     light patch, sparkles
--   bar.layers > fill: fill: dark -> active colour -> light (board 0 % / 62 % / 100 %), sheen
--     bands, rays
--   bar.layers > ticks: 10 % graduations over everything in the track
--   bar.layers > halo: halo of light (left) and shadow eclipse (right), centred on the frame ends
--   bar.layers > markerGlow: end of the fill: white and lavender glow, white needle with its tab
--     under the frame
--   bar.panel: background panel (widget.bgAlpha): rounded dark violet plate with a pale edge, 20 px
--     past the frame sides so that it wraps the halo and the eclipse, as on the board (the box
--     style fits it to the box)
--   text.font: display (Philosopher) only on DISPLAY_KEYS texts: the level label
--   text.boxSize: box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
--     and 2-digit ones up to 14, as in Classic
--   tooltip.width: max width: the widest French XP rows (estimate and warm-up notes) fit uncut
--   tooltip.panel.parts > plate: dark violet plate: warm light at the top-left, violet shade at the
--     bottom-right, inner shadow, pearl frame
--   tooltip.panel.parts > leadTop: stained glass: light at the top-left corner, shadow at the
--     bottom-right (turned 180)
local ADDON, ns = ...

ns.Themes.Register("priest", [[
return {
  name = "THEME_PRIEST",
  fonts = { display = "Philosopher", body = "Lora" },
  colors = {
    xp = "#b8a1ff", rested = "#9ad0ff",
    label = "#d6d0e3", value = "#f7f3ea", dim = "#a9a4ba", accent = "#b8a1ff",
    ink = "#16121f",
    silver = "#c3c0d0", violet = "#6c3fb5",
    haze = "#eeeaf5",
    seam = "#cfc9dc",
    bright = "#f5f1e6",
    plate = "#191724",
  },
  media = {
    frame        = { 64, 32 },
    track_bed    = { 16, 16 },
    groove       = { 16, 8, grey = true },
    rays         = { 8, 16, grey = true },
    sparkle      = { 64, 16, grey = true },
    glow         = { 64, 16, grey = true },
    marker       = { 32, 32 },
    halo         = { 32, 32 },
    eclipse      = { 32, 32 },
    panel_rim    = { 16, 16, grey = true },
    panel_line   = { 16, 16, grey = true },
    tt_frame     = { 32, 32 },
    vignette     = { 32, 32, grey = true },
    tt_glow      = { 32, 32 },
    rose_light   = { 32, 32 },
    rose_shadow  = { 32, 32 },
    strip_light  = { 64, 8 },
    strip_shadow = { 64, 8 },
    lead_light   = { 8, 64 },
    lead_shadow  = { 8, 64 },
    sep          = { 64, 2 },
  },
  bar = {
    pad = 8, gap = 8,
    height = { add = 5, min = 9 },
    maxAlpha = 0.35,
    layers = {
      { id = "frame", span = "track", nine = { "frame", 14, 7 }, pad = { 6, 6 }, top = -6, bottom = -6,
        layer = "BORDER", sub = -4, when = "bar" },
      { id = "groove", span = "track", file = "groove", tile = "H", pad = { 3, 3 }, top = -3, bottom = -3,
        layer = "BORDER", sub = -3, color = "#786c96@.28", when = "bar" },
      { id = "track", span = "track", layer = "BORDER", sub = 0, color = "#17122a", when = "box" },
      { id = "trackBed", span = "track", nine = { "track_bed", 6, 3 }, layer = "BORDER", sub = 0, when = "bar" },
      { id = "rested", span = "rested", layer = "ARTWORK", sub = -4,
        grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
      { id = "restSheen", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = -3,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.2" }, flat = "#ffffff@.1", when = "bar" },
      { id = "restGlow", span = "rested", file = "glow", layer = "ARTWORK", sub = -2,
        color = "rested+.85@.42", when = "bar" },
      { id = "restSparkle", span = "rested", file = "sparkle", tile = "HV", layer = "ARTWORK", sub = -1,
        color = "#ffffff@.85", when = "bar" },
      { id = "fill", span = "fill", layer = "ARTWORK", sub = 0,
        grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
      { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 1,
        grad = { "VERTICAL", "#ffffff@.1", "#ffffff@.34" }, flat = "#ffffff@.2", when = "bar" },
      { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 1,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.1" }, flat = "#ffffff@.05", when = "bar" },
      { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 1,
        grad = { "VERTICAL", "#000000@.26", "#000000@0" }, flat = "#000000@.13", when = "bar" },
      { id = "fillRays", span = "fill", file = "rays", tile = "H", layer = "ARTWORK", sub = 2,
        color = "#ffffff@.07", when = "bar" },
      { id = "ticks", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 3,
        color = "ink@.55", when = "bar" },
      { id = "halo", span = "trackStart", file = "halo", w = 29, align = "right", dx = 5,
        top = -8, bottom = -8, layer = "OVERLAY", sub = 0, when = "bar" },
      { id = "eclipse", span = "trackEnd", file = "eclipse", w = 29, align = "left", dx = -5,
        top = -8, bottom = -8, layer = "OVERLAY", sub = 0, when = "bar" },
      { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 14,
        layer = "OVERLAY", sub = 1, blend = "ADD", color = "#d8ccff@.55", when = "bar" },
      { id = "marker", span = "fillEnd", nine = { "marker", 12, 6 }, w = 12, bottom = -11,
        layer = "OVERLAY", sub = 2, when = "bar" },
    },
    panel = { parts = {
      { id = "panelRim", nine = { "panel_rim", 7, 7 }, inset = { -20, -20, 0, 0 }, color = "#1b1729",
        alpha = "bg", sub = -8 },
      { id = "panelFill", inset = { -17, -17, 3, 3 }, grad = { "VERTICAL", "#120e1e", "#242034" },
        flat = "#1b1729", alpha = "bg", sub = -7 },
      { id = "panelLine", nine = { "panel_line", 7, 7 }, inset = { -20, -20, 0, 0 }, color = "#dcd6e8@.55",
        alpha = "line", sub = -6 },
    } },
  },
  text = {
    font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
             xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
    size = { s1 = 1, s2 = 1, s3 = 0, level = 2, levelValue = 1, xpLabel = 1, xp = 1,
             sep = 1, marker = 0, hint = 0 },
    boxSize = { s1 = 2, s2 = -2, s3 = -2 },
    split = true, splitGap = 4, levelFmt = "upper",
    colors = { label = "#ffffff", value = "value", levelLabel = "#ffffff", levelValue = "value",
               xpText = "value", sep = "seam", marker = "#ffffff", hint = "haze", slot3 = "haze",
               dimmed = "dim", slot2 = "#f2d88a" },
    shadow = { color = "ink@.85", x = 1, y = -1 },
  },
  tooltip = {
    width = { 300, 488 }, pad = { 20, 20, 15, 14 }, gap = 12, lineGap = 4,
    fonts = { title = { "display", 20 }, body = { "body", 14 }, value = { "body", 14 },
              note = { "body", 13 }, hint = { "body", 12 } },
    colors = { title = "#ffffff", mode = "dim", label = "label", value = "bright", dim = "dim",
               header = "#e6deff", pause = "pause", hint = "dim", levelLabel = "label",
               levelValue = "#ffffff", levelValueRested = "#ffffff", rested = "rested+.2" },
    panel = { parts = {
      { id = "plate", inset = { 4, 4, 4, 4 }, grad = { "VERTICAL", "#140f20", "#22202f" }, flat = "plate", sub = -8 },
      { id = "light", file = "tt_glow", inset = { 5, 5, 5, 5 }, sub = -7 },
      { id = "shade", nine = { "vignette", 14, 14 }, inset = { 5, 5, 5, 5 }, color = "#000000@.5", sub = -6 },
      { id = "frame", nine = { "tt_frame", 10, 10 }, sub = -5 },
      { id = "leadTop", file = "strip_light", anchor = "TOPLEFT", x = 9, y = 4, w = 64, h = 8, sub = -4 },
      { id = "leadLeft", file = "lead_light", anchor = "TOPLEFT", x = -4, y = -9, w = 8, h = 64, sub = -4 },
      { id = "roseLight", file = "rose_light", anchor = "TOPLEFT", x = -16, y = 16, w = 32, h = 32, sub = -3 },
      { id = "leadBottom", file = "strip_shadow", flipX = true, flipY = true, anchor = "BOTTOMRIGHT",
        x = -9, y = -4, w = 64, h = 8, sub = -4 },
      { id = "leadRight", file = "lead_shadow", flipX = true, flipY = true, anchor = "BOTTOMRIGHT",
        x = 4, y = 9, w = 8, h = 64, sub = -4 },
      { id = "roseShadow", file = "rose_shadow", flipX = true, flipY = true, anchor = "BOTTOMRIGHT",
        x = 16, y = -16, w = 32, h = 32, sub = -3 },
    } },
    sep = {
      header = { h = 1, above = 7, below = 7, file = "sep" },
      block  = { h = 1, above = 7, below = 7, file = "sep" },
      footer = { h = 1, above = 9, below = 5, file = "sep", color = "#ffffff@.62" },
    },
    gauge = { w = 180, h = 7, gap = 0, outline = "ink",
              colors = { world = "#9481d8", dungeon = "#f1ece0", raid = "#c9b6ff", pvp = "#d9707a",
                         taxi = "#8cc0ee", afk = "#7d7890", inn = "#e8c872", city = "#deba64" } },
  },
  ui = { bg = "plate", border = "silver", title = "#ffffff", accent = "accent",
         label = "label", value = "bright", dim = "dim" },
}
]])
