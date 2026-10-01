-- Themes/actuel.lua - "Classic": the look of TruePlayed before themes, pixel-identical
-- (tests/test_actuel_golden.lua). Every colour is the classic palette C.COLORS (Core.lua),
-- written out with the same decimal literals, hence the same numbers (the source text is
-- compiled in an empty environment: it cannot read ns.C; a test checks the equality).
-- Plain data only (SPEC-themes section 2): a source text, turned into its table only when the
-- theme is compiled (Themes.Register keeps it compact; M3).
-- Notes on the source text below (it carries no comment): its comments, keyed by the
-- section and id they annotate ("> id": the layers or parts from that one on).
--   colors: C.COLORS fill, restedFill, label, value, dim, accent, pause, track, bg, border.
--   bar.layers > rested: rested part: the rested colour 35 % lighter, fading out to the right;
--     the hand-tuned blue when the user kept the built-in rested colour.
--   bar.layers > fillHi: color = C.COLORS.fillHi.
--   bar.layers > restTick: def = C.COLORS.restTick.
--   text: every default: game font, legacy sizes and colours.
local ADDON, ns = ...

ns.Themes.Register("actuel", [[
return {
  name = "THEME_ACTUEL",
  fonts = { display = "game", body = "game" },
  colors = {
    xp = { 0.545, 0.361, 0.965, 1 }, rested = { 0.0, 0.39, 0.88, 1 },
    label = { 0.6, 0.6, 0.6 }, value = { 1, 1, 1 }, dim = { 0.5, 0.5, 0.55 },
    accent = { 0.545, 0.361, 0.965 }, pause = { 1, 0.6, 0.2 },
    track = { 0.106, 0.118, 0.141, 1 }, bg = { 0.059, 0.067, 0.082, 0.85 }, border = { 1, 1, 1, 0.10 },
  },
  bar = {
    pad = 8, gap = 3, height = { add = 0, min = 4 }, maxAlpha = 0.35,
    layers = {
      { id = "track", span = "track", caps = true, layer = "BORDER", sub = 0, color = "track" },
      { id = "rested", span = "rested", layer = "ARTWORK", sub = 1,
        grad = { "HORIZONTAL",
                 { "rested+.35@.65", def = { 0.35, 0.62, 1.0, 0.65 } },
                 { "rested+.35@.20", def = { 0.35, 0.62, 1.0, 0.20 } } },
        flat = { "rested+.35@.40", def = { 0.35, 0.62, 1.0, 0.40 } } },
      { id = "fill", span = "fill", caps = true, layer = "ARTWORK", sub = 2, color = "base" },
      { id = "fillHi", span = "fill", capInset = true, top = 0, h = 1,
        layer = "ARTWORK", sub = 3, color = { 1, 1, 1, 0.10 } },
      { id = "restTick", span = "restEnd", w = 1, align = "right",
        layer = "ARTWORK", sub = 4, color = { "rested+.6@.9", def = { 0.6, 0.75, 1, 0.9 } } },
    },
    panel = "backdrop",
  },
  text = {},
  tooltip = { native = true },
  ui = { bg = "bg", border = "border", title = "value", accent = "accent",
         label = "label", value = "value", dim = "dim" },
}
]])
