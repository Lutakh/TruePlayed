-- Themes/actuel.lua - "Classic": the look of TruePlayed before themes, pixel-identical
-- (tests/test_actuel_golden.lua). Every colour comes from the classic palette C.COLORS.
local ADDON, ns = ...
local C = ns.C

ns.Themes.Register("actuel", function()
  local K = C.COLORS
  return {
    name = "THEME_ACTUEL",
    fonts = { display = "game", body = "game" },
    colors = {
      xp = K.fill, rested = K.restedFill,
      label = K.label, value = K.value, dim = K.dim, accent = K.accent, pause = K.pause,
      track = K.track, bg = K.bg, border = K.border,
    },
    bar = {
      pad = 8, gap = 3, height = { add = 0, min = 4 }, maxAlpha = 0.35,
      layers = {
        { id = "track", span = "track", caps = true, layer = "BORDER", sub = 0, color = "track" },
        -- rested part: the rested colour 35 % lighter, fading out to the right; the
        -- hand-tuned blue when the user kept the built-in rested colour
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 1,
          grad = { "HORIZONTAL",
                   { "rested+.35@.65", def = { 0.35, 0.62, 1.0, 0.65 } },
                   { "rested+.35@.20", def = { 0.35, 0.62, 1.0, 0.20 } } },
          flat = { "rested+.35@.40", def = { 0.35, 0.62, 1.0, 0.40 } } },
        { id = "fill", span = "fill", caps = true, layer = "ARTWORK", sub = 2, color = "base" },
        { id = "fillHi", span = "fill", capInset = true, top = 0, h = 1,
          layer = "ARTWORK", sub = 3, color = K.fillHi, when = "bar" },
        { id = "restTick", span = "restEnd", w = 1, align = "right",
          layer = "ARTWORK", sub = 4, color = { "rested+.6@.9", def = K.restTick } },
      },
      panel = "backdrop",
    },
    text = {},                                   -- every default: game font, legacy sizes and colours
    tooltip = { native = true },
    ui = { bg = "bg", border = "border", title = "value", accent = "accent",
           label = "label", value = "value", dim = "dim" },
  }
end)
