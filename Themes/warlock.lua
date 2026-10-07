-- Themes/warlock.lua - "Warlock" (class theme) from the Demoniste board: black riveted
-- iron, fel fire and soul shards. UnifrakturCook (display: level label, titles) + Alegreya
-- Sans (text). Alegreya Sans only has old-style figures and the board asks for lining ones
-- (font-variant-numeric: lining-nums), so the number role uses the game font.
-- Fel-green XP, soul-violet rested, violet soul gems, green fel glows.
-- Plain data only (SPEC-themes section 2): a source text, turned into its table only when the
-- theme is compiled (Themes.Register keeps it compact; M3).
-- Art: Media/Themes/warlock/*.tga, sources in media-src/warlock/*.svg.
-- Notes on the source text below (it carries no comment): its comments, keyed by the
-- section and id they annotate ("> id": the layers or parts from that one on).
--   colors.xp, rested: board defaults (data-props)
--   colors.ink: outlines, notches, text shadow
--   colors.soul: soul violet: level label, title, separators
--   colors.soulHi: % marker, tooltip percent
--   colors.soulPale: end-of-fill marker
--   colors.fel: fel glow at the track ends
--   colors.iron: rivet tint
--   colors.frost: top-row slot text (fps / latency)
--   colors.mist: "·" between the bar texts
--   colors.bright: tooltip values
--   colors.hintc: tooltip hint line
--   colors.dusk: background panel (board gradient top)
--   media.frame: track frame: ink outline + 3 px black iron (lit top), open centre
--   media.rivets: rivet column: one stud at the top, one at the bottom
--   media.cap: iron end cap: spike, two bolts, soul gem (used as rect 0, 4, 22, 24)
--   media.chain: chain links and a soul shard hanging under a cap
--   media.flame: fel flame with its green halo, standing on a cap
--   media.endglow: half-ellipse glow centred on the left edge
--   media.wisps: two soft soul wisps over the rested part
--   media.smoke: slanted smoke streaks on the fill (tiled)
--   media.tab: violet tab under the fill end (bottom 9 rows only)
--   media.panel: rounded panel body, 9-slice 6
--   media.line: 1 px rounded outline, 9-slice 6
--   media.soft: soft blob for shadows and halos, 9-slice 7
--   media.tt_frame: tooltip iron band (shaded) + inner border + inner shadow, 9-slice 15
--   media.tt_bg: tooltip inner panel: dusk radial gradient (stretched)
--   media.circle: summoning circle behind the tooltip title
--   media.corner_tl: iron bracket, soul gem roundel, chain and shard
--   media.corner_br: iron bracket, roundel with a fel-eyed skull
--   bar.pad, gap: the iron frame reaches 4 px outside the track
--   bar.height: default user height 8 -> 14 px track
--   bar.layers > aura: BORDER, back to front: violet aura, chains, iron frame, rivets, fel flames,
--     end caps (chains and flames tuck behind the caps), then the dark track.
--   bar.layers > track: track: near-black violet, lighter at 55 % (board: #08060d / #130f1b /
--     #0a0810), inner shadow along the top
--   bar.layers > rested: rested part: lighter rested colour fading out to the right, soul wisps,
--     top sheen
--   bar.layers > fill: fill: active colour from 30 % darker (left) to 22 % lighter (right), smoke
--     streaks, sheen on the top 40 %, shade on the bottom 45 % (board: three-stop hue + sheen)
--   bar.layers > notches: forged notches every 10 %, fel glow at both track ends
--   bar.layers > markerGlow: end-of-fill marker: pale violet 2 px line with ink edges and a violet
--     glow, and the violet tab hanging under the frame (drawn under the bar texts)
--   bar.panel: background (widget.bgAlpha): dark dusk rounded panel in the board's vertical
--     gradient (one ramp over the 9-slice) with a 1 px iron border and a soft drop shadow; it
--     reaches 14 px past the frame sides so that the end caps sit inside it, as on the board
--   text.colors: label: the board's soul-blue "XP :"
--   tooltip.panel: riveted iron frame around a dusk panel
--   tooltip.sep: soul-violet lines fading out from the centre
local ADDON, ns = ...

ns.Themes.Register("warlock", [[
return {
  name = "THEME_WARLOCK",
  fonts = { display = "UnifrakturCook", body = "AlegreyaSans", num = "game" },
  colors = {
    xp = "#3fbf3f", rested = "#8788ee",
    label = "#e2dcef", value = "#f7f3ff", dim = "#a8a2bb", accent = "#8788ee",
    ink = "#0c0a12",
    soul = "#8788ee",
    soulHi = "#a3a4f6",
    soulPale = "#d2d3ff",
    fel = "#6ef05a",
    iron = "#c2bfd0",
    frost = "#e6e0f0",
    mist = "#b8b0cc",
    bright = "#faf7ff",
    hintc = "#a39db3",
    dusk = "#1e182a",
  },
  media = {
    frame     = { 16, 16 },
    rivets    = { 4, 32, grey = true },
    cap       = { 32, 32 },
    chain     = { 8, 32 },
    flame     = { 16, 16 },
    endglow   = { 32, 16, grey = true },
    wisps     = { 32, 16, grey = true },
    smoke     = { 8, 16, grey = true },
    tab       = { 16, 32 },
    panel     = { 16, 16, grey = true },
    line      = { 16, 16, grey = true },
    soft      = { 16, 16, grey = true },
    tt_frame  = { 32, 32, grey = true },
    tt_bg     = { 32, 32 },
    circle    = { 64, 64 },
    corner_tl = { 64, 64 },
    corner_br = { 64, 64 },
  },
  bar = {
    pad = 10, gap = 6,
    height = { add = 6, min = 10 },
    maxAlpha = 0.35,
    layers = {
      { id = "aura", span = "track", three = { "common/glow", 16, 10 }, pad = { 10, 10 }, top = -10, bottom = -10,
        layer = "BORDER", sub = -8, color = "soul@.35" },
      { id = "chainL", span = "trackStart", file = "chain", w = 8, dx = -11, top = 12, h = 32,
        layer = "BORDER", sub = -7 },
      { id = "chainR", span = "trackEnd", file = "chain", flipX = true, w = 8, dx = 11, top = 12, h = 32,
        layer = "BORDER", sub = -6 },
      { id = "frame", span = "track", nine = { "frame", 6, 6 }, pad = { 4, 4 }, top = -4, bottom = -4,
        layer = "BORDER", sub = -5 },
      { id = "rivets", span = "track", file = "rivets", ticks = { n = 13, w = 2 }, top = -3, bottom = -3,
        layer = "BORDER", sub = -4, color = "iron" },
      { id = "flameL", span = "trackStart", file = "flame", w = 16, dx = -7, top = -20, h = 16,
        layer = "BORDER", sub = -3 },
      { id = "flameR", span = "trackEnd", file = "flame", flipX = true, w = 16, dx = 7, top = -20, h = 16,
        layer = "BORDER", sub = -2 },
      { id = "capL", span = "trackStart", file = "cap", rect = { 0, 4, 22, 24 }, w = 22, align = "right",
        top = -5, bottom = -5, layer = "BORDER", sub = -1 },
      { id = "capR", span = "trackEnd", file = "cap", rect = { 0, 4, 22, 24 }, flipX = true, w = 22,
        align = "left", top = -5, bottom = -5, layer = "BORDER", sub = 0 },
      { id = "track", span = "track", band = { 0, 0.55 }, layer = "BORDER", sub = 1,
        grad = { "VERTICAL", "#130f1b", "#08060d" } },
      { id = "trackLow", span = "track", band = { 0.55, 1 }, layer = "BORDER", sub = 2,
        grad = { "VERTICAL", "#0a0810", "#130f1b" } },
      { id = "trackShade", span = "track", top = 0, h = 3, layer = "BORDER", sub = 3,
        grad = { "VERTICAL", "#000000@0", "#000000@.7" } },
      { id = "rested", span = "rested", layer = "ARTWORK", sub = -8,
        grad = { "HORIZONTAL", "rested+.15@.8", "rested+.35@0" }, flat = "rested+.25@.45" },
      { id = "restWisps", span = "rested", file = "wisps", layer = "ARTWORK", sub = -7,
        color = "rested+.8" },
      { id = "restSheen", span = "rested", band = { 0, 0.5 }, layer = "ARTWORK", sub = -6,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.18" } },
      { id = "fill", span = "fill", layer = "ARTWORK", sub = -5,
        grad = { "HORIZONTAL", "base-.3", "base+.22" }, flat = "base" },
      { id = "fillSmoke", span = "fill", file = "smoke", tile = "HV", layer = "ARTWORK", sub = -4,
        color = "#ffffff@.06" },
      { id = "fillSheen", span = "fill", band = { 0, 0.4 }, layer = "ARTWORK", sub = -3,
        grad = { "VERTICAL", "#ffffff@.08", "#ffffff@.3" } },
      { id = "fillGlint", span = "fill", band = { 0.4, 0.55 }, layer = "ARTWORK", sub = -2,
        grad = { "VERTICAL", "#ffffff@0", "#ffffff@.08" } },
      { id = "fillShade", span = "fill", band = { 0.55, 1 }, layer = "ARTWORK", sub = -1,
        grad = { "VERTICAL", "#000000@.28", "#000000@0" } },
      { id = "notches", span = "track", ticks = { n = 10 }, layer = "ARTWORK", sub = 0,
        color = "ink@.6" },
      { id = "felL", span = "trackStart", file = "endglow", w = 16, align = "left",
        layer = "ARTWORK", sub = 1, color = "fel@.35" },
      { id = "felR", span = "trackEnd", file = "endglow", flipX = true, w = 20, align = "right",
        layer = "ARTWORK", sub = 2, color = "fel@.5" },
      { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 14,
        layer = "ARTWORK", sub = 3, color = "soul@.85" },
      { id = "markerEdge", span = "fillEnd", w = 4, layer = "ARTWORK", sub = 4, color = "ink" },
      { id = "marker", span = "fillEnd", w = 2, layer = "ARTWORK", sub = 5, color = "soulPale" },
      { id = "tab", span = "fillEnd", file = "tab", w = 16, top = 0, bottom = -10,
        layer = "ARTWORK", sub = 6 },
    },
    panel = { parts = {
      { id = "panelShadow", nine = { "soft", 7, 10 }, inset = { -21, -21, -4, -10 }, color = "#000000@.45",
        alpha = "bg", sub = -8 },
      { id = "panelFill", nine = { "panel", 6, 6 }, inset = { -14, -14, 0, 0 },
        grad = { "VERTICAL", "#0b0910", "dusk" }, flat = "dusk-.3", alpha = "bg", sub = -7 },
      { id = "panelLine", nine = { "line", 6, 6 }, inset = { -14, -14, 0, 0 }, color = "#4a4658@.65",
        alpha = "line", sub = -6 },
    } },
  },
  text = {
    font = { s1 = "body", s2 = "num", s3 = "body", level = "display", levelValue = "num",
             xpLabel = "body", xp = "num", sep = "body", marker = "num", hint = "body" },
    size = { s1 = 3, s2 = 2, s3 = 3, level = 5, levelValue = 2, xpLabel = 3, xp = 2,
             sep = 3, marker = 0, hint = 0 },
    split = true, splitGap = 5, levelFmt = "title",
    colors = { label = "soulHi", value = "value", levelLabel = "soul", levelValue = "value",
               xpText = "value", sep = "mist", marker = "soulHi", hint = "label", slot3 = "frost",
               dimmed = "dim", slot2 = "#a9ef7c" },
    shadow = { color = "ink@.9", x = 1, y = -1 },
  },
  tooltip = {
    width = { 300, 476 }, pad = { 21, 21, 16, 15 }, gap = 12, lineGap = 4,
    fonts = { title = { "display", 20 }, body = { "body", 15 }, value = { "num", 14 },
              note = { "body", 13 }, hint = { "body", 12 } },
    colors = { title = "soul", mode = "dim", label = "label", value = "bright", dim = "dim",
               header = "soulHi", pause = "pause", hint = "hintc", levelLabel = "label",
               levelValue = "soulHi", levelValueRested = "soulHi", rested = "rested+.2" },
    panel = { parts = {
      { id = "glow", nine = { "soft", 7, 12 }, inset = { -11, -11, -11, -11 }, color = "soul@.16", sub = -8 },
      { id = "shadow", nine = { "soft", 7, 14 }, inset = { -12, -12, -2, -22 }, color = "#000000@.6", sub = -7 },
      { id = "bg", file = "tt_bg", inset = { 4, 4, 4, 4 }, sub = -6 },
      { id = "circle", file = "circle", rect = { 0, 10, 64, 54 }, anchor = "TOPLEFT", x = 37, y = -5,
        w = 64, h = 54, color = "#ffffff@.55", sub = -5 },
      { id = "frame", nine = { "tt_frame", 15, 15 }, color = "#5a566c", sub = -4 },
      { id = "soulLine", nine = { "line", 6, 6 }, inset = { 6, 6, 6, 6 }, color = "soul@.2", sub = -3 },
      { id = "rivetTL", file = "rivets", rect = { 0, 0, 4, 4 }, anchor = "TOPLEFT", x = 80, y = -2,
        w = 3, h = 3, color = "iron", sub = -2 },
      { id = "rivetT", file = "rivets", rect = { 0, 0, 4, 4 }, anchor = "TOP", x = 0, y = -2,
        w = 3, h = 3, color = "iron", sub = -1 },
      { id = "rivetTR", file = "rivets", rect = { 0, 0, 4, 4 }, anchor = "TOPRIGHT", x = -80, y = -2,
        w = 3, h = 3, color = "iron", sub = 0 },
      { id = "rivetBL", file = "rivets", rect = { 0, 0, 4, 4 }, anchor = "BOTTOMLEFT", x = 80, y = 2,
        w = 3, h = 3, color = "iron", sub = 1 },
      { id = "rivetB", file = "rivets", rect = { 0, 0, 4, 4 }, anchor = "BOTTOM", x = 0, y = 2,
        w = 3, h = 3, color = "iron", sub = 2 },
      { id = "rivetBR", file = "rivets", rect = { 0, 0, 4, 4 }, anchor = "BOTTOMRIGHT", x = -80, y = 2,
        w = 3, h = 3, color = "iron", sub = 3 },
      { id = "cornerTL", file = "corner_tl", anchor = "TOPLEFT", x = -9, y = 9, w = 64, h = 64, sub = 4 },
      { id = "cornerBR", file = "corner_br", anchor = "BOTTOMRIGHT", x = 9, y = -9, w = 64, h = 64, sub = 5 },
    } },
    sep = {
      header = { h = 1, above = 5, below = 6, mirror = true, grad = { "HORIZONTAL", "soul@0", "soul@.85" } },
      block  = { h = 1, above = 6, below = 6, mirror = true, grad = { "HORIZONTAL", "soul@0", "soul@.85" } },
      footer = { h = 1, above = 9, below = 6, mirror = true, grad = { "HORIZONTAL", "soul@0", "soul@.5" } },
    },
    gauge = { w = 180, h = 7, gap = 0, outline = "#3a3845",
              colors = { world = "#4fbf45", dungeon = "soul", raid = "#b25ad9", pvp = "#d9483b",
                         taxi = "#74a9dc", afk = "#6b6680", inn = "#d9b26a", city = "#a39a8a",
                         prof = "#45b8a8", dead = "#7a1f2b" } },
  },
  ui = { bg = "#120d1a", border = "#8d899c", title = "soul", accent = "soul",
         label = "label", value = "bright", dim = "dim" },
}
]])
