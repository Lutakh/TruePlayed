-- Themes/paladin.lua - "Paladin": white marble set in gold, holy light, from the Paladin board.
-- Cormorant SC (display: "LEVEL 20" and the tooltip title) + Cormorant Garamond (texts). Both
-- Cormorant fonts only have old-style figures while the board asks for lining ones, so numbers
-- (XP, percentages, tooltip values) use the game font (num = "game", SPEC K4). Golden XP, sky-blue
-- rested with motes of light, a pink end-of-fill marker in a golden halo, a marble-and-gold
-- track frame with a solar medallion at each end; the tooltip is a navy panel in a marble frame
-- with a radiant sun behind the title and a libram on two corners. Sources: media-src/paladin/*.svg.
-- Plain data only (SPEC-themes section 2): a source text, turned into its table only when the
-- theme is compiled (Themes.Register keeps it compact; M3).
-- Notes on the source text below (it carries no comment): its comments, keyed by the
-- section and id they annotate ("> id": the layers or parts from that one on).
--   colors.xp, rested: board defaults (data-props)
--   media.medallion: baked: 16-ray golden sun, pink gem, gold clasp (left form), top 64 x 56 used
--   media.frame: baked 9-slice (8): dark edge, gold, 2 px marble, gold track ring, hole
--   media.marble: thin crossing veins (tiled)
--   media.radiance: steep "/" light stripes, 2 on / 6 off (tiled)
--   media.motes: three soft sparks of light (tiled)
--   media.panel: filled rounded rectangle, radius 6 (9-slice 7)
--   media.panel_line: 1 px outline of the same shape
--   media.tt_frame: baked 9-slice (12): edge, gold, marble rim, gold + dark rings, inner shadow
--   media.libram: baked corner: gold rails with diamond ends and a purple libram
--   media.sunburst: 24 rays and a glow faded by an ellipse (sun centre at 43, 11)
--   media.halo: soft radial glow (the marker's golden halo)
--   bar.height: default user height 8 -> 13 px track
--   bar.layers > frameShadow: marble frame set in gold: soft drop shadow, frame, veins
--   bar.layers > track: track: night-blue groove, darker under its top edge and along its bottom
--   bar.layers > rested: rested part ("blessed light"): lighter rested colour fading out, top
--     gloss, motes of light
--   bar.layers > fill: fill: active colour from 32 % darker (left) to 25 % lighter (right), light
--     stripes, top sheen and bottom shade (board: white .42 / .12 / 0 at 0 / 38 / 52 %, black .26
--     at 100 %)
--   bar.layers > ticks: graduations every 10 %, over the fill
--   bar.layers > markerHalo: end-of-fill marker: pink bar, pink glow, golden halo
--   bar.layers > medalL: solar medallions clasped to both ends of the frame (about 26 px past the
--     track)
--   bar.panel: night-blue panel (the board's vertical gradient) with a gold outline, wide enough to
--     hold the medallions
--   text.size: Cormorant has a small x-height (0.4 em): its texts get +3; numbers use the game font
--   text.boxSize: box: slots 2 and 3 are 80 px wide; a 3-digit FPS and latency fit at font size 11
--     and 2-digit ones up to 14, as in Classic
local ADDON, ns = ...

ns.Themes.Register("paladin", [[
return {
  name = "THEME_PALADIN",
  fonts = { display = "CormorantSC", body = "CormorantGaramond", num = "game" },
  colors = {
    xp = "#d9a72b", rested = "#7ec8ff",
    label = "#f48cba", value = "#fdf6e3", dim = "#a9a6bd", accent = "#f48cba",
    pause = "#f0a050",
    pink = "#f48cba", pinkHi = "#f7a6ca", gold = "#e2bc5a", goldDeep = "#c9a04a",
    navy = "#181c3a", ink = "#1c1308", ivory = "#fdf6e3", text = "#ece4d2",
    parch = "#dccfae", cream = "#fffaf0", mode = "#b3b0c8", hint = "#aeaac4",
    sun = "#ffdc8c",
  },
  media = {
    medallion  = { 64, 64 },
    frame      = { 32, 32 },
    marble     = { 64, 16, grey = true },
    radiance   = { 8, 32, grey = true },
    motes      = { 32, 16, grey = true },
    panel      = { 16, 16, grey = true },
    panel_line = { 16, 16, grey = true },
    tt_frame   = { 32, 32 },
    libram     = { 64, 64 },
    sunburst   = { 128, 64, grey = true },
    halo       = { 32, 32, grey = true },
  },
  bar = {
    pad = 10, gap = 6,
    height = { add = 5, min = 9 },
    maxAlpha = 0.35,
    layers = {
      { id = "frameShadow", span = "track", three = { "common/glow", 16, 8 }, pad = { 7, 7 },
        top = -8, bottom = -11, layer = "BORDER", sub = -5, color = "#000000@.45", when = "bar" },
      { id = "frame", span = "track", nine = { "frame", 8, 8 }, pad = { 5, 5 }, top = -5, bottom = -5,
        layer = "BORDER", sub = -4, when = "bar" },
      { id = "frameVeins", span = "track", file = "marble", tile = "HV", pad = { 3, 3 }, top = -3, bottom = -3,
        layer = "BORDER", sub = -3, color = "#8f8676@.45", when = "bar" },
      { id = "track", span = "track", layer = "BORDER", sub = 0, color = "#1a1d3a" },
      { id = "trackShade", span = "track", band = { 0, 0.45 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@0", "#000000@.55" }, when = "bar" },
      { id = "trackLow", span = "track", band = { 0.6, 1 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@.4", "#000000@0" }, when = "bar" },
      { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
        grad = { "HORIZONTAL", "rested+.15@.8", "rested+.4@0" }, flat = "rested+.28@.5" },
      { id = "restGloss", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 1,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.22" }, when = "bar" },
      { id = "restMotes", span = "rested", file = "motes", tile = "H", layer = "ARTWORK", sub = 2,
        grad = { "HORIZONTAL", "#ffffff@.8", "#ffffff@.3" }, flat = "#ffffff@.55", when = "bar" },
      { id = "fill", span = "fill", layer = "ARTWORK", sub = 3,
        grad = { "HORIZONTAL", "base-.32", "base+.25" }, flat = "base" },
      { id = "fillRays", span = "fill", file = "radiance", tile = "HV", layer = "ARTWORK", sub = 4,
        color = "#ffffff@.07", when = "bar" },
      { id = "fillTop", span = "fill", band = { 0, 0.38 }, layer = "ARTWORK", sub = 5,
        grad = { "VERTICAL", "#ffffff@.12", "#ffffff@.42" }, when = "bar" },
      { id = "fillMid", span = "fill", band = { 0.38, 0.52 }, layer = "ARTWORK", sub = 5,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.12" }, when = "bar" },
      { id = "fillLow", span = "fill", band = { 0.52, 1 }, layer = "ARTWORK", sub = 5,
        grad = { "VERTICAL", "#000000@.26", "#000000@0" }, when = "bar" },
      { id = "ticks", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 6,
        color = "#281a08@.55", when = "bar" },
      { id = "markerHalo", span = "fillEnd", file = "halo", w = 38, top = -7, bottom = -7,
        layer = "OVERLAY", sub = 0, blend = "ADD", color = "#ffe8a0@.4", when = "bar" },
      { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10, top = -3, bottom = -3,
        layer = "OVERLAY", sub = 1, blend = "ADD", color = "pink@.8", when = "bar" },
      { id = "marker", span = "fillEnd", w = 2, layer = "OVERLAY", sub = 2, color = "pink", when = "bar" },
      { id = "medalL", span = "trackStart", file = "medallion", rect = { 0, 0, 64, 56 }, w = 27, align = "right",
        dx = 1, top = -5, h = 24, layer = "OVERLAY", sub = 3, when = "bar" },
      { id = "medalR", span = "trackEnd", file = "medallion", rect = { 0, 0, 64, 56 }, flipX = true, w = 27,
        align = "left", dx = -1, top = -5, h = 24, layer = "OVERLAY", sub = 3, when = "bar" },
    },
    panel = { parts = {
      { id = "panelFill", nine = { "panel", 7, 7 }, inset = { -22, -22, 0, 0 },
        grad = { "VERTICAL", "#0f1228", "#262a52" }, flat = "#171a36", alpha = "bg", sub = -8 },
      { id = "panelLine", nine = { "panel_line", 7, 7 }, inset = { -22, -22, 0, 0 },
        color = "goldDeep", alpha = "line", sub = -7 },
    } },
  },
  text = {
    font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "num",
             xpLabel = "body", xp = "num", sep = "body", marker = "num", hint = "body" },
    size = { s1 = 3, s2 = 3, s3 = 3, level = 3, levelValue = 1, xpLabel = 3, xp = 1,
             sep = 3, marker = 0, hint = 2 },
    boxSize = { s1 = 4, s2 = 1, s3 = 1 },
    split = true, splitGap = 5, levelFmt = "upper",
    colors = { label = "pink", value = "ivory", levelLabel = "pink", levelValue = "ivory",
               xpText = "ivory", sep = "parch", marker = "pinkHi", hint = "parch", slot3 = "#f3ecdc",
               dimmed = "dim", slot2 = "#c9e89a" },
    shadow = { color = "ink@.9", x = 1, y = -1 },
  },
  tooltip = {
    width = { 300, 440 }, pad = { 20, 20, 15, 14 }, gap = 12, lineGap = 5,
    fonts = { title = { "display", 23 }, body = { "body", 16 }, value = { "num", 13 },
              note = { "body", 14 }, hint = { "body", 13 } },
    colors = { title = "pink", mode = "mode", label = "text", value = "cream", dim = "mode",
               header = "pinkHi", pause = "pause", hint = "hint", levelLabel = "text",
               levelValue = "pinkHi", levelValueRested = "pinkHi", rested = "rested+.2" },
    panel = { parts = {
      { id = "bg", inset = { 8, 8, 8, 8 }, grad = { "VERTICAL", "#0f1228", "#262a52" }, flat = "navy",
        sub = -8 },
      { id = "sun", anchor = "TOPLEFT", x = 8, y = -8, w = 192, h = 96, file = "sunburst",
        color = "sun@.45", sub = -7 },
      { id = "frame", nine = { "tt_frame", 12, 12 }, sub = -6 },
      { id = "libramTL", anchor = "TOPLEFT", x = -12, y = 13, w = 73, h = 73, file = "libram", sub = -5 },
      { id = "libramBR", anchor = "BOTTOMRIGHT", x = 12, y = -13, w = 73, h = 73, file = "libram",
        flipX = true, flipY = true, sub = -5 },
    } },
    sep = {
      header = { h = 1, above = 8, below = 9, mirror = true, grad = { "HORIZONTAL", "pink@0", "pink@.85" } },
      block  = { h = 1, above = 9, below = 9, mirror = true, grad = { "HORIZONTAL", "pink@0", "pink@.85" } },
      footer = { h = 1, above = 12, below = 8, mirror = true, grad = { "HORIZONTAL", "pink@0", "pink@.5" } },
    },
    gauge = { w = 190, h = 7, gap = 0, outline = "#1a1206",
              colors = { world = "#d9ae4a", dungeon = "pink", raid = "#a98be6", pvp = "#e0664a",
                         taxi = "#7ec8ff", afk = "#8e8aa6", inn = "#f3d67c", city = "#e3dccd" } },
  },
  ui = { bg = "navy", border = "goldDeep", title = "pink", accent = "gold",
         label = "text", value = "cream", dim = "mode" },
}
]])
