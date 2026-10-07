-- Themes/warrior.lua - "Warrior": riveted steel and bronze, from the Guerrier board.
-- Grenze Gotisch (display: the "Level 20" title and the tooltip title) + Barlow Condensed
-- (every other text, lining figures), rust-red XP, steel-blue rested. The track sits in a
-- riveted steel-plate frame (plate seams, brushed streaks, rivets over the 10 % notches) with
-- a crest - a bronze shield over two crossed swords - at each end; the tooltip is a dark panel
-- in a steel frame with four bolted corner brackets. Media sources: media-src/warrior/*.svg.
-- Plain data only (SPEC-themes section 2): a source text, turned into its table only when the
-- theme is compiled (Themes.Register keeps it compact; M3).
-- Notes on the source text below (it carries no comment): its comments, keyed by the
-- section and id they annotate ("> id": the layers or parts from that one on).
--   colors.xp, rested: board defaults (data-props)
--   media.crest: baked: shield over crossed swords, top 64 x 53 texels used
--   media.frame: baked 9-slice (8): #110c09 outline + 3 px steel rail, end rivets, hole
--   media.brush: brushed-steel streaks: light / dark columns (tiled)
--   media.rivet: baked 3 x 3 rivet in the top-left corner
--   media.seam: baked plate seam: dark groove + lit edge
--   media.grain: "/" diagonal stripes, 3 on / 5 off (tiled)
--   media.panel: filled rounded rectangle, radius 4 (9-slice 6)
--   media.panel_line: 1 px outline of the same shape
--   media.tt_frame: baked 9-slice (12): outline, steel rim, inner ring, inner shadow
--   media.tt_corner: baked bolted corner bracket, top-left 26 x 26 texels used
--   bar.height: default user height 8 -> 13 px track
--   bar.layers > frameShadow: steel-plate frame: soft drop shadow, plates, brushed streaks, seams,
--     rivets
--   bar.layers > rivets: rivets along the top rail, over the 10 % notches (the frame art has one
--     more near each end of both rails; a bottom-rail row cannot follow the track height, so there
--     is none)
--   bar.layers > track: track: near-black steel groove, darker under its top edge and along its
--     bottom
--   bar.layers > rested: rested part ("tempered steel"): lighter rested colour fading out to the
--     right, top gloss
--   bar.layers > fill: fill: active colour from 30 % darker (left) to 22 % lighter (right),
--     diagonal grain, top sheen and bottom shade (board: white .32 / .08 / 0 at 0 / 40 / 55 %,
--     black .3 at 100 %)
--   bar.layers > notches: notches engraved every 10 %, over the fill
--   bar.layers > markerGlow: end-of-fill marker: bronze bar with its glow
--   bar.layers > crestL: crests over both ends of the frame (they reach about 33 px past the track)
--   bar.panel: dark gunmetal panel (the board's vertical gradient) with a steel outline, wide
--     enough to hold the crests
local ADDON, ns = ...

ns.Themes.Register("warrior", [[
return {
  name = "THEME_WARRIOR",
  fonts = { display = "GrenzeGotisch", body = "BarlowCondensed" },
  colors = {
    xp = "#b33a1f", rested = "#3f7fbf",
    label = "#c69b6d", value = "#fff5e8", dim = "#a7aeb5", accent = "#c69b6d",
    pause = "#f0a040",
    bronze = "#c69b6d", bronzeHi = "#d9b283", steel = "#788089", ink = "#110c09",
    text = "#e4dfd6", ash = "#ece6dc", sand = "#c9bfae", slate = "#1d1f23",
    cream = "#fff6ea", gold = "#f2c46b", mode = "#a7aeb5",
  },
  media = {
    crest      = { 64, 64 },
    frame      = { 32, 32 },
    brush      = { 8, 8, grey = true },
    rivet      = { 4, 4 },
    seam       = { 2, 2 },
    grain      = { 8, 8, grey = true },
    panel      = { 16, 16, grey = true },
    panel_line = { 16, 16, grey = true },
    tt_frame   = { 32, 32 },
    tt_corner  = { 32, 32 },
  },
  bar = {
    pad = 10, gap = 6,
    height = { add = 5, min = 9 },
    maxAlpha = 0.35,
    layers = {
      { id = "frameShadow", span = "track", three = { "common/glow", 16, 8 }, pad = { 6, 6 },
        top = -7, bottom = -10, layer = "BORDER", sub = -5, color = "#000000@.5" },
      { id = "frame", span = "track", nine = { "frame", 8, 8 }, pad = { 4, 4 }, top = -4, bottom = -4,
        layer = "BORDER", sub = -4 },
      { id = "frameBrush", span = "track", file = "brush", tile = "HV", pad = { 3, 3 }, top = -3, bottom = -3,
        layer = "BORDER", sub = -3 },
      { id = "seams", span = "track", ticks = { n = 3, w = 2 }, file = "seam", top = -3, bottom = -3,
        layer = "BORDER", sub = -2 },
      { id = "rivets", span = "track", ticks = { n = 10, w = 3 }, file = "rivet", rect = { 0, 0, 3, 3 },
        top = -3, h = 3, layer = "BORDER", sub = -1 },
      { id = "track", span = "track", layer = "BORDER", sub = 0, color = "#1a1c1f" },
      { id = "trackShade", span = "track", band = { 0, 0.45 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@0", "#000000@.6" } },
      { id = "trackLow", span = "track", band = { 0.6, 1 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#000000@.42", "#000000@0" } },
      { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
        grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.5" },
      { id = "restGloss", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 1,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.2" } },
      { id = "fill", span = "fill", layer = "ARTWORK", sub = 2,
        grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
      { id = "fillGrain", span = "fill", file = "grain", tile = "HV", layer = "ARTWORK", sub = 3,
        color = "#ffffff@.07" },
      { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 4,
        grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.32" } },
      { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 4,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" } },
      { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 4,
        grad = { "VERTICAL", "#000000@.3", "#000000@0" } },
      { id = "notches", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 5,
        color = "ink@.65" },
      { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10, top = -3, bottom = -3,
        layer = "OVERLAY", sub = 0, blend = "ADD", color = "bronze@.7" },
      { id = "marker", span = "fillEnd", w = 2, layer = "OVERLAY", sub = 1, color = "bronze" },
      { id = "crestL", span = "trackStart", file = "crest", rect = { 0, 0, 64, 53 }, w = 35, align = "right",
        dx = 2, top = -8, h = 29, layer = "OVERLAY", sub = 2 },
      { id = "crestR", span = "trackEnd", file = "crest", rect = { 0, 0, 64, 53 }, w = 35, align = "left",
        dx = -2, top = -8, h = 29, layer = "OVERLAY", sub = 2 },
    },
    panel = { parts = {
      { id = "panelFill", nine = { "panel", 6, 6 }, inset = { -24, -24, 0, 0 },
        grad = { "VERTICAL", "#0e0f11", "#222529" }, flat = "#191b1e", alpha = "bg", sub = -8 },
      { id = "panelLine", nine = { "panel_line", 6, 6 }, inset = { -24, -24, 0, 0 },
        color = "steel", alpha = "line", sub = -7 },
    } },
  },
  text = {
    font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
             xpLabel = "body", xp = "body", sep = "body", marker = "body", hint = "body" },
    size = { s1 = 2, s2 = 2, s3 = 2, level = 3, levelValue = 2, xpLabel = 2, xp = 2,
             sep = 2, marker = 1, hint = 0 },
    split = true, splitGap = 5, levelFmt = "title",
    colors = { label = "bronze", value = "#fff5e8", levelLabel = "bronze", levelValue = "#fff5e8",
               xpText = "#fff5e8", sep = "sand", marker = "bronzeHi", hint = "sand", slot3 = "ash",
               dimmed = "dim", slot2 = "#f2c46b" },
    shadow = { color = "ink@.9", x = 1, y = -1 },
  },
  tooltip = {
    width = { 300, 440 }, pad = { 20, 20, 15, 14 }, gap = 12, lineGap = 5,
    fonts = { title = { "display", 22 }, body = { "body", 15 }, value = { "body", 15 },
              note = { "body", 14 }, hint = { "body", 13 } },
    colors = { title = "bronze", mode = "mode", label = "text", value = "cream", dim = "dim",
               header = "bronzeHi", pause = "pause", hint = "dim", levelLabel = "text",
               levelValue = "bronzeHi", levelValueRested = "bronzeHi", rested = "rested+.2" },
    panel = { parts = {
      { id = "bg", inset = { 6, 6, 6, 6 }, grad = { "VERTICAL", "#121316", "#26292e" }, flat = "slate",
        sub = -8 },
      { id = "frame", nine = { "tt_frame", 12, 12 }, sub = -7 },
      { id = "cornerTL", anchor = "TOPLEFT", x = -4, y = 4, w = 26, h = 26, file = "tt_corner",
        rect = { 0, 0, 26, 26 }, sub = -6 },
      { id = "cornerTR", anchor = "TOPRIGHT", x = 4, y = 4, w = 26, h = 26, file = "tt_corner",
        rect = { 0, 0, 26, 26 }, flipX = true, sub = -6 },
      { id = "cornerBR", anchor = "BOTTOMRIGHT", x = 4, y = -4, w = 26, h = 26, file = "tt_corner",
        rect = { 0, 0, 26, 26 }, flipX = true, flipY = true, sub = -6 },
      { id = "cornerBL", anchor = "BOTTOMLEFT", x = -4, y = -4, w = 26, h = 26, file = "tt_corner",
        rect = { 0, 0, 26, 26 }, flipY = true, sub = -6 },
    } },
    sep = {
      header = { h = 1, above = 8, below = 9, mirror = true, grad = { "HORIZONTAL", "bronze@0", "bronze@.85" } },
      block  = { h = 1, above = 9, below = 9, mirror = true, grad = { "HORIZONTAL", "bronze@0", "bronze@.85" } },
      footer = { h = 1, above = 12, below = 8, mirror = true, grad = { "HORIZONTAL", "bronze@0", "bronze@.5" } },
    },
    gauge = { w = 190, h = 7, gap = 0, outline = "ink",
              colors = { world = "#82a24c", dungeon = "bronze", raid = "#b5523a", pvp = "#d98a3a",
                         taxi = "#7fa6d9", afk = "#5d646b", inn = "gold", city = "#939aa2",
                         prof = "#5aa89a", dead = "#7d1f24" } },
  },
  ui = { bg = "slate", border = "steel", title = "bronze", accent = "bronzeHi",
         label = "text", value = "cream", dim = "dim" },
}
]])
