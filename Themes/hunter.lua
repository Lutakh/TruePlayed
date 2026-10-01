-- Themes/hunter.lua - "Hunter" (class theme) from the Chasseur board: a stitched leather strap
-- with laced bindings and arrow fletchings around the bar, a dark leather tooltip in an oak
-- frame with stitched seams, riveted corners and a hanging feather. Germania One (display:
-- level label, tooltip title) + Signika (text and numbers; it has lining figures, so
-- num = body). Olive XP, sky-blue rested, hunter green (#aad372) accents.
-- Plain data only (SPEC-themes section 2): a source text, turned into its table only when the
-- theme is compiled (Themes.Register keeps it compact; M3).
-- Art: Media/Themes/hunter/*.tga, sources in media-src/hunter/*.svg.
-- Notes on the source text below (it carries no comment): its comments, keyed by the
-- section and id they annotate ("> id": the layers or parts from that one on).
--   colors.xp, rested: board defaults (data-props)
--   colors.green: hunter class colour: labels, marker, title
--   colors.greenHi: % texts
--   colors.cream: bar values
--   colors.creamSoft: top-row slot text (fps / latency)
--   colors.sand: separator dot between the bar texts
--   colors.parch: unlocked hint
--   colors.hintGrey: tooltip hint line
--   colors.ink: outlines, notches, stitch shadow, text shadow
--   colors.thread: saddle stitching
--   colors.strapLow: strap colour on the row under the track
--   colors.bark: track (board 55 % stop)
--   media.strap: baked strap: 1 px ink outline + 4 px leather, 5 px radius
--   media.stitch: 5 px thread, 3 px gap (tiled)
--   media.fletch: baked arrow fletching (left end)
--   media.binding: baked laced binding over a strap end
--   media.barbs: "\" feather barbs, 2 px of 8 (tiled)
--   media.trail: two prints, 8 px apart (tiled)
--   media.mist: one soft mist wisp
--   media.round: filled rounded rectangle, 6-texel corners
--   media.panel_line: 1 px rounded outline, 7-texel corners
--   media.inner_line: 1 px rounded outline, radius 5, 6-texel corners
--   media.vignette: inner shadow, 14-texel falloff
--   media.blob: soft round blob (wood knots, panel light)
--   media.stitch_grid: diagonal 4-on 4-off bands: dashed on every row and column
--   media.tt_wood: baked tooltip oak frame, 10-texel corners
--   media.tt_corner: baked stitched leather corner with a brass rivet
--   media.tt_feather: baked feathers and beads hanging from the rivet
--   media.sep_arrow: line - arrow - line separator
--   bar.pad, gap: texts clear the 5 px strap by 2 px
--   bar.height: default user height 8 -> 14 px track
--   bar.layers > strap: leather strap around the track (board: 5 px padding at x1.5, radius 6)
--   bar.layers > stitchShadowTop: saddle stitching one row inside each long edge, its dark shadow 1
--     px right and down. Layers hang from the track top, so the bottom rows are tall dash columns
--     reaching H + 1 (thread) and H + 2 (shadow), hidden above by the track and by a strap-coloured
--     cover on row H.
--   bar.layers > track: track: dark earth, lightest at 55 % (two shaded bands), inner shadow under
--     its top edge
--   bar.layers > rested: rested part: a trail of prints in the morning mist, fading out to the
--     right
--   bar.layers > fill: fill: the active colour, 30 % darker on the left to 22 % lighter at the fill
--     end, faint feather barbs, light from above and shade below (board sheen)
--   bar.layers > notches: notches every 10 %
--   bar.layers > fletchL: arrow fletchings at both ends (board "empennage"), shafts running under
--     the bindings
--   bar.layers > markerGlow: end-of-fill marker in hunter green with its glow
--   bar.layers > bindL: laced bindings over the strap ends (board "ligatures lacees")
--   bar.panel: background panel (widget.bgAlpha): dark hide in the board's faint vertical gradient
--     (one ramp over the 9-slice), leather border; 43 px past the frame sides so that the arrow
--     fletching sits on it, as on the board
--   text.size: board: Signika 15 px and Germania One 16 px (bar drawn x1.5); Signika is a large
--     font
--   tooltip.panel: dark leather in a 5 px oak frame
--   tooltip.panel.parts > inner: flat leather band up to the seam (a gradient on a 9-slice repeats
--     in each row); the gradient is on the plain cover inside the seam
--   tooltip.panel.parts > stitchGrid: stitched seam 4 px inside the leather: the dashed grid shows
--     only on the 1 px ring left between the grid (inset 9) and the opaque cover (inset 10)
--   tooltip.panel.parts > feather: feather hanging from the rivet of the top-left leather corner
--   tooltip.sep: center: the arrow keeps its shape, the lines stretch
local ADDON, ns = ...

ns.Themes.Register("hunter", [[
return {
  name = "THEME_HUNTER",
  fonts = { display = "GermaniaOne", body = "Signika" },
  colors = {
    xp = "#7a9a2e", rested = "#5fa8d3",
    label = "#ebdfc3", value = "#fff6e2", dim = "#b3aa94", accent = "#aad372",
    green = "#aad372",
    greenHi = "#bfe08a",
    cream = "#f6ead0",
    creamSoft = "#efe4c9",
    sand = "#d9c7a0",
    parch = "#e8dcbd",
    hintGrey = "#aea48e",
    ink = "#1a1008",
    thread = "#e2c894",
    strapLow = "#55351c",
    bark = "#1b140d",
    leather = "#6a4122", oak = "#8f5e33",
    hide = "#1f1812", hideLo = "#15100b",
  },
  media = {
    strap       = { 32, 32 },
    stitch      = { 8, 2, grey = true },
    fletch      = { 64, 32 },
    binding     = { 16, 32 },
    barbs       = { 16, 16, grey = true },
    trail       = { 16, 16, grey = true },
    mist        = { 32, 8, grey = true },
    round       = { 16, 16, grey = true },
    panel_line  = { 16, 16, grey = true },
    inner_line  = { 16, 16, grey = true },
    vignette    = { 32, 32, grey = true },
    blob        = { 16, 16, grey = true },
    stitch_grid = { 8, 8, grey = true },
    tt_wood     = { 32, 32 },
    tt_corner   = { 32, 32 },
    tt_feather  = { 64, 128 },
    sep_arrow   = { 256, 8, grey = true },
  },
  bar = {
    pad = 8, gap = 7,
    height = { add = 6, min = 10 },
    maxAlpha = 0.35,
    layers = {
      { id = "strap", span = "track", nine = { "strap", 8, 8 }, pad = { 5, 5 }, top = -5, bottom = -5,
        layer = "BACKGROUND", sub = 0 },
      { id = "stitchShadowTop", span = "track", file = "stitch", tile = "H", pad = { -1, 1 }, top = -2, h = 1,
        layer = "BACKGROUND", sub = 1, color = "ink@.6" },
      { id = "stitchTop", span = "track", file = "stitch", tile = "H", top = -3, h = 1,
        layer = "BACKGROUND", sub = 2, color = "thread" },
      { id = "stitchShadowBottom", span = "track", file = "stitch", tile = "H", pad = { -1, 1 }, top = 0,
        bottom = -3, layer = "BACKGROUND", sub = 3, color = "ink@.6" },
      { id = "stitchBottom", span = "track", file = "stitch", tile = "H", top = 0, bottom = -2,
        layer = "BACKGROUND", sub = 4, color = "thread" },
      { id = "strapCover", span = "track", top = 0, bottom = -1, layer = "BACKGROUND", sub = 5,
        color = "strapLow" },
      { id = "track", span = "track", layer = "BORDER", sub = 0, color = "bark" },
      { id = "trackTop", span = "track", band = { 0, 0.55 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@0", "#000000@.44" } },
      { id = "trackLow", span = "track", band = { 0.55, 1 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@.37", "#000000@0" } },
      { id = "trackShadow", span = "track", top = 0, h = 3, layer = "BORDER", sub = 2,
        grad = { "VERTICAL", "#000000@0", "#000000@.5" } },
      { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
        grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
      { id = "restSheen", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 1,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.18" } },
      { id = "restMist", span = "rested", file = "mist", layer = "ARTWORK", sub = 2,
        color = "rested+.8@.35" },
      { id = "restTrail", span = "rested", file = "trail", tile = "H", layer = "ARTWORK", sub = 3,
        color = "rested+.8@.45" },
      { id = "fill", span = "fill", layer = "ARTWORK", sub = 4,
        grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
      { id = "fillBarbs", span = "fill", file = "barbs", tile = "HV", layer = "ARTWORK", sub = 5,
        color = "#ffffff@.07" },
      { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 6,
        grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.3" } },
      { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 6,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" } },
      { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 6,
        grad = { "VERTICAL", "#000000@.28", "#000000@0" } },
      { id = "notches", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 7,
        color = "ink@.6" },
      { id = "fletchL", span = "trackStart", file = "fletch", w = 45, align = "right", top = -4, bottom = -4,
        layer = "OVERLAY", sub = 0 },
      { id = "fletchR", span = "trackEnd", file = "fletch", flipX = true, w = 45, align = "left",
        top = -4, bottom = -4, layer = "OVERLAY", sub = 0 },
      { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10, top = -2, bottom = -2,
        layer = "OVERLAY", sub = 1, color = "green@.55" },
      { id = "marker", span = "fillEnd", w = 2, layer = "OVERLAY", sub = 2, color = "green" },
      { id = "bindL", span = "trackStart", file = "binding", w = 10, align = "right", dx = 2,
        top = -6, bottom = -6, layer = "OVERLAY", sub = 3 },
      { id = "bindR", span = "trackEnd", file = "binding", w = 10, align = "left", dx = -2,
        top = -6, bottom = -6, layer = "OVERLAY", sub = 3 },
    },
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
    size = { s1 = 2, s2 = 2, s3 = 2, level = 3, levelValue = 2, xpLabel = 2, xp = 2,
             sep = 2, marker = 0, hint = 0 },
    split = true, splitGap = 6, levelFmt = "upper",
    colors = { label = "green", value = "cream", levelLabel = "green", levelValue = "cream",
               xpText = "cream", sep = "sand", marker = "greenHi", hint = "parch", slot3 = "creamSoft",
               dimmed = "dim", slot2 = "#f0cf7a" },
    shadow = { color = "ink@.9", x = 1, y = -1 },
  },
  tooltip = {
    width = { 300, 466 }, pad = { 21, 21, 16, 15 }, gap = 12, lineGap = 4,
    fonts = { title = { "display", 21 }, body = { "body", 14 }, value = { "body", 14 },
              note = { "body", 13 }, hint = { "body", 12 } },
    colors = { title = "green", mode = "dim", label = "label", value = "value", dim = "dim",
               header = "green", pause = "pause", hint = "hintGrey", levelLabel = "label",
               levelValue = "greenHi", levelValueRested = "greenHi", rested = "rested+.2" },
    panel = { parts = {
      { id = "wood", nine = { "tt_wood", 10, 10 }, sub = -8 },
      { id = "knotTop", anchor = "TOPLEFT", x = 72, y = 0, w = 52, h = 7, file = "blob",
        color = "#3c220e@.7", sub = -7 },
      { id = "knotBottom", anchor = "BOTTOMRIGHT", x = -103, y = 0, w = 40, h = 7, file = "blob",
        color = "#3c220e@.65", sub = -7 },
      { id = "knotRight", anchor = "RIGHT", x = 0, y = 25, w = 7, h = 44, file = "blob",
        color = "#3c220e@.6", sub = -7 },
      { id = "inner", nine = { "round", 6, 5 }, inset = { 5, 5, 5, 5 }, color = "hide", sub = -6 },
      { id = "stitchGrid", file = "stitch_grid", tile = "HV", inset = { 9, 9, 9, 9 },
        color = "thread@.42", sub = -5 },
      { id = "stitchCover", inset = { 10, 10, 10, 10 }, grad = { "VERTICAL", "hideLo", "#271f16" },
        flat = "hide", sub = -4 },
      { id = "light", anchor = "TOPLEFT", x = 12, y = -8, w = 220, h = 100, file = "blob",
        color = "#3a2d1f@.4", sub = -3 },
      { id = "vignette", nine = { "vignette", 14, 16 }, inset = { 5, 5, 5, 5 }, color = "#000000@.3", sub = -2 },
      { id = "innerLine", nine = { "inner_line", 6, 6 }, inset = { 5, 5, 5, 5 }, color = "ink", sub = -1 },
      { id = "feather", anchor = "TOPLEFT", x = -39, y = 1, w = 64, h = 128, file = "tt_feather",
        layer = "BORDER", sub = 0 },
      { id = "cornerTL", anchor = "TOPLEFT", x = -1, y = 1, w = 32, h = 32, file = "tt_corner",
        layer = "BORDER", sub = 1 },
      { id = "cornerBR", anchor = "BOTTOMRIGHT", x = 1, y = -1, w = 32, h = 32, file = "tt_corner",
        flipX = true, flipY = true, layer = "BORDER", sub = 1 },
    } },
    sep = {
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
]])
