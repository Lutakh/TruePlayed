-- Themes/druid.lua - "Druid" (class theme) from the Druide board: a carved wood rim with
-- living vines around the bar, a moss-green tooltip framed in wood. Uncial Antiqua (display:
-- level label, tooltip title) + Alegreya Sans (text). Both fonts only have old-style figures
-- while the board asks for lining ones (font-variant-numeric: lining-nums), so the number role
-- uses the game font (SPEC K4). Moss XP, moon-blue rested, druid orange (#ff7c0a) accents.
-- Plain data only (SPEC-themes section 2): a source text, turned into its table only when the
-- theme is compiled (Themes.Register keeps it compact; M3).
-- Art: Media/Themes/druid/*.tga, sources in media-src/druid/*.svg.
-- Notes on the source text below (it carries no comment): its comments, keyed by the
-- section and id they annotate ("> id": the layers or parts from that one on).
--   colors.xp, rested: board defaults (data-props)
--   colors.pause: amber: apart from the orange title
--   colors.orange: druid class colour: labels, marker, title
--   colors.orangeHi: % texts
--   colors.cream: bar values
--   colors.creamSoft: top-row slot text (fps / latency)
--   colors.sand: separator dot between the bar texts
--   colors.parch: unlocked hint
--   colors.hintGrey: tooltip hint line
--   colors.ink: outlines, notches, text shadow
--   colors.bark: track (board 55 % stop)
--   media.bar_wood: baked rim: 1 px ink outline + 3 px grained wood, 6 px radius
--   media.vine: baked curling vine, 3 leaves, orange berry (left end)
--   media.veins: "/" leaf veins, 3 px of 8 (tiled)
--   media.mist: two soft mist wisps
--   media.round: filled rounded rectangle, 6-texel corners
--   media.panel_line: 1 px rounded outline, 7-texel corners
--   media.inner_line: 1 px rounded outline, radius 5, 6-texel corners
--   media.vignette: inner shadow, 14-texel falloff
--   media.blob: soft round blob (wood knots, panel light)
--   media.tt_wood: baked tooltip wood frame, 10-texel corners
--   media.tt_vine: baked corner vine with berries (top-left)
--   media.sep_leaf: line - leaf - line separator
--   bar.pad, gap: texts clear the 4 px rim by 2 px
--   bar.height: default user height 8 -> 14 px track
--   bar.layers > wood: carved wood rim around the track (board: 4 px padding at x1.5, radius 7)
--   bar.layers > track: track: dark bark, lightest at 55 % (the board's 3-stop gradient as two
--     shaded bands), with an inner shadow under its top edge
--   bar.layers > rested: rested part: moon mist, the rested colour lightened and fading out to the
--     right
--   bar.layers > fill: fill: the active colour, 30 % darker on the left to 22 % lighter at the fill
--     end, faint leaf veins, light from above and shade below (board sheen)
--   bar.layers > notches: carved notches every 10 %
--   bar.layers > markerGlow: end-of-fill marker in druid orange with its glow
--   bar.layers > vineL: vines curling from the top corners of the rim (board "vigne gauche /
--     droite")
--   bar.panel: background panel (widget.bgAlpha): moss in the board's faint vertical gradient (one
--     ramp over the 9-slice), wood-brown border; 29 px past the frame sides so that the vines sit
--     on it, as on the board
--   text.size: board: 15 px bottom row, 14 px top row (bar drawn x1.5); Uncial keeps the board's
--     size ratio to the text; the game font (numbers) looks larger, so it gets 1 px less
--   tooltip.panel: moss panel in a 4 px wood frame, vines on two corners
--   tooltip.panel.parts > inner: moss panel: a flat rounded 9-slice, its vertical gradient on a
--     plain rectangle that leaves out the corner rows (a gradient on a 9-slice repeats in each row)
--   tooltip.sep: center: the leaf keeps its shape, the lines stretch
local ADDON, ns = ...

ns.Themes.Register("druid", [[
return {
  name = "THEME_DRUID",
  fonts = { display = "UncialAntiqua", body = "AlegreyaSans", num = "game" },
  colors = {
    xp = "#5f9e3a", rested = "#7fb2e5",
    label = "#e6dabd", value = "#fff6e2", dim = "#adb7c1", accent = "#ff7c0a",
    pause = "#f2c14e",
    orange = "#ff7c0a",
    orangeHi = "#ff8a24",
    cream = "#f6ead0",
    creamSoft = "#efe4c9",
    sand = "#d9c7a0",
    parch = "#e8dcbd",
    hintGrey = "#a9b3bd",
    ink = "#1a1008",
    bark = "#1e150c",
    wood = "#5a4029", woodHi = "#8a6a44",
    moss = "#172113", mossMid = "#161d11", mossLo = "#0f140c",
  },
  media = {
    bar_wood   = { 32, 32 },
    vine       = { 64, 64 },
    veins      = { 16, 16, grey = true },
    mist       = { 32, 8, grey = true },
    round      = { 16, 16, grey = true },
    panel_line = { 16, 16, grey = true },
    inner_line = { 16, 16, grey = true },
    vignette   = { 32, 32, grey = true },
    blob       = { 16, 16, grey = true },
    tt_wood    = { 32, 32 },
    tt_vine    = { 64, 64 },
    sep_leaf   = { 256, 8, grey = true },
  },
  bar = {
    pad = 8, gap = 6,
    height = { add = 6, min = 10 },
    maxAlpha = 0.35,
    layers = {
      { id = "wood", span = "track", nine = { "bar_wood", 8, 8 }, pad = { 4, 4 }, top = -4, bottom = -4,
        layer = "BACKGROUND", sub = 0 },
      { id = "track", span = "track", layer = "BORDER", sub = 0, color = "bark" },
      { id = "trackTop", span = "track", band = { 0, 0.55 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@0", "#000000@.43" } },
      { id = "trackLow", span = "track", band = { 0.55, 1 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@.37", "#000000@0" } },
      { id = "trackShadow", span = "track", top = 0, h = 3, layer = "BORDER", sub = 2,
        grad = { "VERTICAL", "#000000@0", "#000000@.5" } },
      { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
        grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
      { id = "restSheen", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 1,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.18" } },
      { id = "restMist", span = "rested", file = "mist", layer = "ARTWORK", sub = 2,
        color = "rested+.8@.45" },
      { id = "fill", span = "fill", layer = "ARTWORK", sub = 3,
        grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
      { id = "fillVeins", span = "fill", file = "veins", tile = "HV", layer = "ARTWORK", sub = 4,
        color = "#ffffff@.06" },
      { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 5,
        grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.3" } },
      { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 5,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" } },
      { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 5,
        grad = { "VERTICAL", "#000000@.28", "#000000@0" } },
      { id = "notches", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 6,
        color = "ink@.6" },
      { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10, top = -2, bottom = -2,
        layer = "OVERLAY", sub = 0, color = "orange@.55" },
      { id = "marker", span = "fillEnd", w = 2, layer = "OVERLAY", sub = 1, color = "orange" },
      { id = "vineL", span = "trackStart", file = "vine", w = 44, align = "left", dx = -36,
        top = -13, h = 44, layer = "OVERLAY", sub = 2 },
      { id = "vineR", span = "trackEnd", file = "vine", flipX = true, w = 44, align = "right", dx = 36,
        top = -13, h = 44, layer = "OVERLAY", sub = 2 },
    },
    panel = { parts = {
      { id = "panelFill", nine = { "round", 6, 7 }, inset = { -29, -29, 0, 0 },
        grad = { "VERTICAL", "#0d130a", "#1f2a1a" }, flat = "moss", alpha = "bg", sub = -8 },
      { id = "panelLine", nine = { "panel_line", 7, 7 }, inset = { -29, -29, 0, 0 }, color = "wood",
        alpha = "bg", sub = -7 },
    } },
  },
  text = {
    font = { s1 = "body", s2 = "num", s3 = "body", level = "display", levelValue = "num",
             xpLabel = "body", xp = "num", sep = "body", marker = "num", hint = "body" },
    size = { s1 = 2, s2 = 2, s3 = 2, level = 3, levelValue = 2, xpLabel = 3, xp = 2,
             sep = 3, marker = 0, hint = 0 },
    split = true, splitGap = 6, levelFmt = "upper",
    colors = { label = "orange", value = "cream", levelLabel = "orange", levelValue = "cream",
               xpText = "cream", sep = "sand", marker = "orangeHi", hint = "parch", slot3 = "creamSoft",
               dimmed = "dim", slot2 = "#c3e38e" },
    shadow = { color = "ink@.9", x = 1, y = -1 },
  },
  tooltip = {
    width = { 300, 444 }, pad = { 20, 20, 15, 14 }, gap = 12, lineGap = 4,
    fonts = { title = { "display", 19 }, body = { "body", 14 }, value = { "num", 13 },
              note = { "body", 13 }, hint = { "body", 12 } },
    colors = { title = "orange", mode = "dim", label = "label", value = "value", dim = "dim",
               header = "orange", pause = "pause", hint = "hintGrey", levelLabel = "label",
               levelValue = "orangeHi", levelValueRested = "orangeHi", rested = "rested+.2" },
    panel = { parts = {
      { id = "wood", nine = { "tt_wood", 10, 10 }, sub = -8 },
      { id = "knotTop", anchor = "TOPLEFT", x = 77, y = 0, w = 44, h = 6, file = "blob",
        color = "#1e140b@.75", sub = -7 },
      { id = "knotBottom", anchor = "BOTTOMRIGHT", x = -72, y = 0, w = 36, h = 6, file = "blob",
        color = "#1e140b@.7", sub = -7 },
      { id = "inner", nine = { "round", 6, 5 }, inset = { 4, 4, 4, 4 }, color = "mossMid", sub = -6 },
      { id = "innerShade", inset = { 4, 4, 9, 9 }, grad = { "VERTICAL", "mossLo", "#1c2717" },
        flat = "mossMid", sub = -5 },
      { id = "light", anchor = "TOPLEFT", x = 10, y = -6, w = 230, h = 110, file = "blob",
        color = "#2c3b23@.4", sub = -4 },
      { id = "vignette", nine = { "vignette", 14, 16 }, inset = { 4, 4, 4, 4 }, color = "#000000@.3", sub = -3 },
      { id = "innerLine", nine = { "inner_line", 6, 6 }, inset = { 4, 4, 4, 4 }, color = "ink", sub = -2 },
      { id = "vineTL", anchor = "TOPLEFT", x = -14, y = 9, w = 64, h = 64, file = "tt_vine",
        layer = "BORDER", sub = 0 },
      { id = "vineBR", anchor = "BOTTOMRIGHT", x = 14, y = -9, w = 64, h = 64, file = "tt_vine",
        flipX = true, flipY = true, layer = "BORDER", sub = 0 },
    } },
    sep = {
      header = { h = 8, above = 4, below = 5, file = "sep_leaf", center = 48, color = "orange" },
      block  = { h = 8, above = 5, below = 5, file = "sep_leaf", center = 48, color = "orange" },
      footer = { h = 1, above = 10, below = 6, mirror = true, grad = { "HORIZONTAL", "orange@0", "orange@.5" } },
    },
    gauge = { w = 170, h = 7, gap = 0, outline = "ink",
              colors = { world = "#7fa345", dungeon = "orange", raid = "#9a7bd1", pvp = "#d0563f",
                         taxi = "#7fa6d9", afk = "#7d8790", inn = "#e2c46a", city = "#b08a5e",
                         prof = "#4fb3a9", dead = "#8c2f39" } },
  },
  ui = { bg = "moss", border = "woodHi", title = "orange", accent = "orange",
         label = "label", value = "value", dim = "dim" },
}
]])
