-- Themes/warrior.lua - "Warrior": riveted steel and bronze, from the Guerrier board.
-- Grenze Gotisch (display: the "Level 20" title and the tooltip title) + Barlow Condensed
-- (every other text, lining figures), rust-red XP, steel-blue rested. The track sits in a
-- riveted steel-plate frame (plate seams, brushed streaks, rivets over the 10 % notches) with
-- a crest - a bronze shield over two crossed swords - at each end; the tooltip is a dark panel
-- in a steel frame with four bolted corner brackets. Media sources: media-src/warrior/*.svg.
local ADDON, ns = ...

ns.Themes.Register("warrior", function()
  return {
    name = "THEME_WARRIOR",
    fonts = { display = "GrenzeGotisch", body = "BarlowCondensed" },
    colors = {
      xp = "#b33a1f", rested = "#3f7fbf",                -- board defaults (data-props)
      label = "#c69b6d", value = "#fff5e8", dim = "#a7aeb5", accent = "#c69b6d",
      pause = "#f0a040",
      bronze = "#c69b6d", bronzeHi = "#d9b283", steel = "#788089", ink = "#110c09",
      text = "#e4dfd6", ash = "#ece6dc", sand = "#c9bfae", slate = "#1d1f23",
      cream = "#fff6ea", gold = "#f2c46b", mode = "#a7aeb5",
    },
    media = {
      crest      = { 64, 64 },              -- baked: shield over crossed swords, top 64 x 53 texels used
      frame      = { 32, 32 },              -- baked 9-slice (8): #110c09 outline + 3 px steel rail, end rivets, hole
      brush      = { 8, 8, grey = true },   -- brushed-steel streaks: light / dark columns (tiled)
      rivet      = { 4, 4 },                -- baked 3 x 3 rivet in the top-left corner
      seam       = { 2, 2 },                -- baked plate seam: dark groove + lit edge
      grain      = { 8, 8, grey = true },   -- "/" diagonal stripes, 3 on / 5 off (tiled)
      panel      = { 16, 16, grey = true }, -- filled rounded rectangle, radius 4 (9-slice 6)
      panel_line = { 16, 16, grey = true }, -- 1 px outline of the same shape
      tt_frame   = { 32, 32 },              -- baked 9-slice (12): outline, steel rim, inner ring, inner shadow
      tt_corner  = { 32, 32 },              -- baked bolted corner bracket, top-left 26 x 26 texels used
    },
    bar = {
      pad = 10, gap = 6,
      height = { add = 5, min = 9 },          -- default user height 8 -> 13 px track
      maxAlpha = 0.35,
      layers = {
        -- steel-plate frame: soft drop shadow, plates, brushed streaks, seams, rivets
        { id = "frameShadow", span = "track", three = { "common/glow", 16, 8 }, pad = { 6, 6 },
          top = -7, bottom = -10, layer = "BORDER", sub = -5, color = "#000000@.5", when = "bar" },
        { id = "frame", span = "track", nine = { "frame", 8, 8 }, pad = { 4, 4 }, top = -4, bottom = -4,
          layer = "BORDER", sub = -4, when = "bar" },
        { id = "frameBrush", span = "track", file = "brush", tile = "HV", pad = { 3, 3 }, top = -3, bottom = -3,
          layer = "BORDER", sub = -3, when = "bar" },
        { id = "seams", span = "track", ticks = { n = 3, w = 2 }, file = "seam", top = -3, bottom = -3,
          layer = "BORDER", sub = -2, when = "bar" },
        -- rivets along the top rail, over the 10 % notches (the frame art has one more near each
        -- end of both rails; a bottom-rail row cannot follow the track height, so there is none)
        { id = "rivets", span = "track", ticks = { n = 10, w = 3 }, file = "rivet", rect = { 0, 0, 3, 3 },
          top = -3, h = 3, layer = "BORDER", sub = -1, when = "bar" },
        -- track: near-black steel groove, darker under its top edge and along its bottom
        { id = "track", span = "track", layer = "BORDER", sub = 0, color = "#1a1c1f" },
        { id = "trackShade", span = "track", band = { 0, 0.45 }, layer = "BORDER", sub = 1,
          grad = { "VERTICAL", "#000000@0", "#000000@.6" }, when = "bar" },
        { id = "trackLow", span = "track", band = { 0.6, 1 }, layer = "BORDER", sub = 1,
          grad = { "VERTICAL", "#000000@.42", "#000000@0" }, when = "bar" },
        -- rested part ("tempered steel"): lighter rested colour fading out to the right, top gloss
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 0,
          grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.5" },
        { id = "restGloss", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = 1,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.2" }, when = "bar" },
        -- fill: active colour from 30 % darker (left) to 22 % lighter (right), diagonal grain,
        -- top sheen and bottom shade (board: white .32 / .08 / 0 at 0 / 40 / 55 %, black .3 at 100 %)
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 2,
          grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
        { id = "fillGrain", span = "fill", file = "grain", tile = "HV", layer = "ARTWORK", sub = 3,
          color = "#ffffff@.07", when = "bar" },
        { id = "fillTop", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.32" }, when = "bar" },
        { id = "fillMid", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" }, when = "bar" },
        { id = "fillLow", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#000000@.3", "#000000@0" }, when = "bar" },
        -- notches engraved every 10 %, over the fill
        { id = "notches", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 5,
          color = "ink@.65", when = "bar" },
        -- end-of-fill marker: bronze bar with its glow
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 10, top = -3, bottom = -3,
          layer = "OVERLAY", sub = 0, blend = "ADD", color = "bronze@.7", when = "bar" },
        { id = "marker", span = "fillEnd", w = 2, layer = "OVERLAY", sub = 1, color = "bronze", when = "bar" },
        -- crests over both ends of the frame (they reach about 33 px past the track)
        { id = "crestL", span = "trackStart", file = "crest", rect = { 0, 0, 64, 53 }, w = 35, align = "right",
          dx = 2, top = -8, h = 29, layer = "OVERLAY", sub = 2, when = "bar" },
        { id = "crestR", span = "trackEnd", file = "crest", rect = { 0, 0, 64, 53 }, w = 35, align = "left",
          dx = -2, top = -8, h = 29, layer = "OVERLAY", sub = 2, when = "bar" },
      },
      -- dark gunmetal panel (the board's vertical gradient) with a steel outline, wide
      -- enough to hold the crests
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
      boxSize = { s1 = 4, s2 = 2, s3 = 2 },
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
                           taxi = "#7fa6d9", afk = "#5d646b", inn = "gold", city = "#939aa2" } },
    },
    ui = { bg = "slate", border = "steel", title = "bronze", accent = "bronzeHi",
           label = "text", value = "cream", dim = "dim" },
  }
end)
