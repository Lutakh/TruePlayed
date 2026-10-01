# SPEC-themes: visual themes for TruePlayed

Status: CONTRACT. Implementers work in parallel and do not talk to each other, so this file is
the only shared source of truth. When this SPEC is silent, choose the simplest reading that
keeps every existing test green. Report the choice in your final answer as `ASSUMPTION: ...`.
When you need a change in a file you do not own, report it as `REQUEST: <file>: <change>`.
Never edit that file yourself.

Language rules: code, comments, identifiers, test names and this SPEC are in English. The
user-facing strings live in `Locales/enUS.lua` and `Locales/frFR.lua` only.
`docs/TEST-EN-JEU-fr.md` stays in French.

## 0. Decisions, phases, glossary

### 0.1 User decisions (relayed request: "1. oui / 2. futuriste")
- D1. The new default theme is **futuriste** (`C.DEFAULTS.theme = "futuriste"`).
- D2. Existing users switch too. There is **no migration**: an absent `theme` setting means the
  default. Anyone who wants the old look picks "Classic" (`actuel`) in the options, in the
  context menu, or with `/tpl theme actuel`. See risk K1 for the one-line fallback if this
  reading turns out wrong.
- D3. The current look is kept, pixel-identical, as the theme `actuel` ("Classic"). A golden
  test enforces this (section 8.2).
- D4. 13 themes plus one automatic choice:
  - general themes: `futuriste`, `actuel`, `heroic`, `pixel`;
  - automatic: `class`, which resolves to the player's class theme;
  - class themes: `warrior`, `paladin`, `hunter`, `rogue`, `priest`, `shaman`, `mage`,
    `warlock`, `druid`.
- D5. Non-negotiables (unchanged from the addon SPEC):
  - CPU and memory must be exemplary.
  - No `OnUpdate` anywhere. The only repeating timer is Core's shared 1 s ticker (`TICK`).
  - Zero garbage per tick, measured as no more than 2 KB over 600 ticks, the existing
    threshold.
  - `SetText` only when the text changed. `GetStringWidth` only when the measured text or the
    layout changed. Textures, colours and fonts are touched only when something changed.
  - Per-character data isolation, persistence, crash recovery and localisation (enUS and frFR)
    stay as they are.

### 0.2 Phases
- **Phase 0 (orchestrator, BEFORE any implementer starts).** Run this exactly once from the
  addon root (`TruePlayed/`):
  ```sh
  mkdir -p tests/baseline/Locales && cp *.lua TruePlayed_Camelot.toc tests/baseline/ \
    && cp Locales/*.lua tests/baseline/Locales/
  ```
  - This is the pristine copy used by the golden test (8.2).
  - Nobody edits `tests/baseline/`.
  - The repo is not a git repository, so this copy is the only pre-refactor reference.
- **Phase 1 (parallel).** E1, E2, E3, E4 and T1..T7 work on their own files (section 7).
  - E2, E3 and E4 code against the API of section 3. That API is implemented by E1.
  - Until E1 has landed, an implementer's tests may fail for "missing ns.Themes". That is
    expected.
  - Each implementer finishes by running the commands in 8.6 on the merged tree, when it is
    available.
- **Phase 2 (orchestrator).**
  - Run the full suite: `lua tests/run.lua`, `check_toc`, `check_encoding`, `lint51`,
    `check_globals` and `check_media`, on Lua 5.1 and 5.5, plus `luacheck`.
  - Route the `REQUEST:` lines to the file owners.

### 0.3 Glossary
- **theme key**: one of the 13 lowercase keys. "class" is a setting value, not a theme key.
- **source theme**: the table a theme's source text returns (section 2; a test may register a
  builder function instead). It is written by theme authors.
- **compiled theme** (`th`): what engines read (section 2.8). It is produced by
  `Themes.Compile`.
- **fill state** `k`: 0 = normal XP, 1 = rested (the fill takes the rested colour, as the
  game's bar does), 2 = max level (full width, dimmed). These are the same values as the
  existing `fillKey` in Bar.lua.
- **track space**:
  - Pixel coordinates inside the progress track.
  - x runs from the track's left edge (0..W); y runs from the track's TOP edge downwards
    (0..H).
  - `W` = `lineW` and `H` = `lineH`.
  - `ox, oy` = the bottom-left corner of the track in frame coordinates. These are Bar.lua's
    existing `ox, oy`.

## 1. Settings

- S1. `C.DEFAULTS.theme = "futuriste"`. This is a top-level key, a sibling of `widget`. It is
  account-wide like every setting, saved sparse at logout (`SparseCopy`), and dropped when
  equal to the default.
- S2. `C.THEME_CHOICES` gives the order used by every menu:
  ```lua
  C.THEME_CHOICES = { "futuriste", "actuel", "heroic", "pixel", "class", "warrior", "paladin",
                      "hunter", "rogue", "priest", "shaman", "mage", "warlock", "druid" }
  C.CLASS_THEMES = { WARRIOR = "warrior", PALADIN = "paladin", HUNTER = "hunter", ROGUE = "rogue",
                     PRIEST = "priest", SHAMAN = "shaman", MAGE = "mage", WARLOCK = "warlock",
                     DRUID = "druid" }
  ```
- S3. `DefineSetting("theme", "theme")` adds a new `Normalize` kind, `"theme"`:
  - strict mode (`SetSetting`): the value must be one of `C.THEME_CHOICES`, otherwise it is
    `nil` (rejected);
  - repair mode (`RepairSettings`): any string matching `^[%a_]+$` with length 24 or less is
    KEPT. This preserves a key written by a newer version; resolution falls back at read time.
    Any other value is invalid and is removed, so the default applies.
- S4. `LEGACY_DEFAULTS` gains nothing. Records saved in full by 0.1.0-test predate themes.
- S5. Resolution (`Themes.Resolve(value, classFile)`, pure):
  1. if `value == "class"`: `key = C.CLASS_THEMES[classFile]`, or `"futuriste"` when the class
     is unknown or nil;
  2. otherwise `key = value`;
  3. if `key` is not registered: `"futuriste"`. If futuriste is not registered either:
     `"actuel"`. `actuel` is always registered (E1 owns it).
- S6. When resolution runs:
  - lazily, at the first `Themes.Active()` call after `DB_READY`. This is silent: no message.
  - at `SETTINGS_CHANGED("theme")`;
  - at `DB_SWAPPED`.
  - `classFile` comes from `select(2, UnitClass("player"))`.
  - A call to `Themes.Active()` before `DB_READY` must work. It resolves without a class and
    does not cache, so the next call resolves again.
- S7. Messages sent by Themes (E1), with handlers called as `fn(msgName, ...)`:
  - `THEME_CHANGED(key, prevKey, "theme")`: the resolved key changed. Sent once per change,
    never at `DB_READY`, and never when the setting changes but the resolved key does not
    (for example "class" to "mage" for a mage).
  - `THEME_CHANGED(key, key, "colors")`: the active theme was recoloured in place, after a
    change of `widget.xpColor` or `widget.restedColor` (any path starting with those
    strings).
- S8. Every module except Themes must IGNORE these paths in its `SETTINGS_CHANGED` handler:
  `"theme"`, `widget.xpColor*` and `widget.restedColor*`. Bar currently handles the colour
  paths itself (`BAR_COLOR_PATHS`). That moves to `THEME_CHANGED "colors"`.
  `widget.textColor*` stays handled by Bar as today.
- S9. There is no per-character theme. "class" gives per-character looks while the setting
  itself stays account-wide.

## 2. Theme data format

### 2.1 Files and registration
- One file per theme: `Themes/<key>.lua`, listed in the TOC (section 5.1).
- Each file only registers its source text (round 5, design/NEXT-LOT.md M3):
  ```lua
  -- Notes on the source text below (it carries no comment): its comments, keyed by the
  -- section and id they annotate.
  local ADDON, ns = ...
  ns.Themes.Register("<key>", [[
  return { ... }
  ]])
  ```
- The text is plain data: the source theme as one table constructor, with no comment, no
  function, no metatable and no reference to anything (a test checks that no `--` and no
  `function` appear in the 13 texts). Notes on the data stay in Lua comments above the
  `Register` call, keyed by section and layer / part id. `actuel` writes the `C.COLORS`
  literals out (the same decimal text, hence the same numbers; a test checks the equality).
- `Register` keeps the text compact: once, at registration, it removes the indentation and the
  blanks around `=`, `,`, `{` and `}` outside string literals (`Themes.CompactSource`; a test
  checks that the compact text evaluates to a table deep-equal to the full one, for the 13
  themes).
- The text is turned into its table only when the theme is compiled (activation, a theme
  switch, tests): `loadstring` then `setfenv(fn, {})` on Lua 5.1 (the game), `load(text,
  name, "t", {})` on 5.2+ (the offline tests), in an empty environment; the function and the
  table are dropped right after the compile (`Themes.Source`). Themes.lua is the only file
  allowed to read these loaders (`tests/lint51.lua`, `.luacheckrc`, `tests/check_globals.lua`).
- Memory at rest is therefore one compiled theme plus the 13 compact texts, about 64 KiB in
  all, and no builder function. Round 4 kept 13 builder closures instead: about 104 KB of
  table-constructor bytecode at rest on Lua 5.5 and 126 KB on the client's 5.1 (whose line info
  costs 4 bytes per instruction).
- `Register` also takes a builder function returning the source table (test fixtures).
  Builders must be pure: no WoW API, no settings, no `ns.char`.
- `Register` errors (a load-time developer error) on: an unknown key, a duplicate key, a key
  equal to `"class"`, or anything but a builder function or a text starting with `return {`.

### 2.2 Source theme: top level
| field | req | type | meaning |
|---|---|---|---|
| `name` | yes | string | locale key of the display name (`"THEME_FUTURISTE"`) |
| `fonts` | yes | table | `{ display = F, body = F, num = F? }`: names from `Themes.FONTS` (2.6) or `"game"`. `num` defaults to `body`. |
| `colors` | yes | table | named colours (2.3). Required names: `xp`, `rested`, `label`, `value`, `dim`, `accent`. Optional: `pause` (default `C.COLORS.pause`). |
| `media` | no | table | `{ <name> = { w, h, grey = bool? } }`: files `Media/Themes/<key>/<name>.tga` (section 6) |
| `bar` | yes | table | section 2.4 |
| `text` | no | table | section 2.5 (every field has a default equal to today's look) |
| `tooltip` | yes | table | section 4.2, or `{ native = true }` |
| `ui` | yes | table | Graph/Window roles: `bg, border, title, accent, label, value, dim` (colours; the alpha is ignored, because the modules keep their own alphas) |

Unknown fields produce a warning. Since round 5 the warnings come from the test-only validator
(`tests/theme_validate.lua`, design/NEXT-LOT.md M2): the shipped compiler falls back on the
defaults and says nothing. `test_theme_data` requires zero warnings.

### 2.3 Colours
A **colour** is one of the following:
- a string expression (grammar below);
- a numeric table `{ r, g, b [, a] }` with components in 0..1 (`a` defaults to 1);
- a "defaulted" table `{ <string expression>, def = <string expression or numeric table> }`.

Grammar:
```
expr   := source mods
source := "#" HEX6 | "#" HEX8 | name | "none"
name   := "xp" | "rested" | "base" | a key of `colors` ([%a_][%w_]*)
mods   := { ("+" | "-") num } [ "@" num ]          -- num: 0..1, e.g. ".35", "0.6", "1"
```
Semantics:
- The source gives the starting rgba:
  - HEX8: its last byte is the alpha.
  - Named colours resolve recursively (depth 4 or less, no cycles).
  - `"none"` is (0, 0, 0, 0).
- `+k` lightens: `c = c + (1 - c) * k` for r, g and b.
- `-k` darkens: `c = c * (1 - k)`.
- `@a` sets the alpha (absolute). It must come last.
- Modifiers apply left to right.
- Dynamic sources:
  - `xp` is the user's `widget.xpColor` when set (alpha 1), else `colors.xp`.
  - `rested` is the user's `widget.restedColor` when set (alpha 1), else `colors.rested`.
  - `base` is the fill-state colour: `xp` in states 0 and 2, `rested` in state 1. `base` is
    valid ONLY in `bar.layers`. Anywhere else it is a warning (white is used).
  - Entries of `colors` may use `xp` and `rested` but not `base`.
- `def`: when every dynamic source used by the expression comes from the THEME (the user
  setting is `false`), the colour is `def` instead of the expression. It exists so that
  `actuel` keeps its hand-tuned defaults (for example REST_FROM_0 = {0.35, 0.62, 1, 0.65}).
  For `base`, the user flag that applies is the one of the source that `base` stands for in
  that state.
- Parsing and evaluation happen at compile and recolour time only, never per tick.
- Recolouring (S7 "colors") rewrites the numbers inside the SAME compiled tables. Their
  identity is stable, so recolouring allocates nothing.

### 2.4 `bar` section
| field | default | meaning |
|---|---|---|
| `pad` | 8 | frame padding around rows and track (bar style) |
| `gap` | 3 | px between the track and each text row |
| `height` | `{ add = 0, min = 4 }` | track height `H = max(min, widget.height + add)` (bar style; box keeps `BOX_LINE` = 2) |
| `maxAlpha` | 0.35 | alpha factor in fill state 2 for layers of span `fill` / `fillEnd` (overridable per layer) |
| `layers` | required | list, drawn in list order (2.4.1) |
| `panel` | `"backdrop"` | the background shown when `widget.bgAlpha > 0`: `"backdrop"` (today's SetBackdrop path, colours `colors.bg`/`colors.border` falling back to `C.COLORS.bg`/`C.COLORS.border`, legacy border-alpha rule) or `{ parts = { ... } }` (2.4.2) |

Frame geometry in the bar style generalises today's `ApplyBarStyle`. With `fs = fontSize` and
`sz(e) = fs + text.size[e]` (after font snapping, 2.6):
```
topRow    = max(sz(s1), sz(s3)) + 2
bottomRow = max(sz(level), sz(xp), sz(s2), split and sz(levelValue) or 0, split and sz(xpLabel) or 0) + 2
trackY    = pad + bottomRow + gap          -- = oy
topY      = trackY + H + gap
frame     = (W + 2 * pad) x (pad + topRow + gap + H + gap + bottomRow + pad)
```
With the defaults this gives today's numbers exactly: topRow = fs + 4 and bottomRow = fs + 2.
The box style keeps its constants (`BOX_WIDTH`, `BOX_PAD`, `BOX_LINE`).

#### 2.4.1 Bar layers
Each layer is one texture or a small fixed group of textures.

| field | type / default | meaning |
|---|---|---|
| `id` | string, required, unique | test handle: `frame.tp.tex[id]`. Kinds `caps` and `three` create `id.."L"`, `id.."M"`, `id.."R"`; `nine` creates `tex[id]` = array of 9; `ticks` creates `tex[id]` = array |
| `span` | `"track"` | horizontal extent: range spans `track` [0, W], `fill` [0, px], `rested` [px, rpx]; anchor spans `fillEnd` (px), `restEnd` (rpx), `trackStart` (0), `trackEnd` (W) |
| `layer` | `"ARTWORK"` | `BACKGROUND`, `BORDER`, `ARTWORK`, `OVERLAY` |
| `sub` | 0 | sublevel, -8..7. Overlapping layers MUST use distinct (layer, sub) pairs |
| `file` | white | media reference (6.1); default `C.TEX_WHITE` |
| `rect`, `flipX`, `flipY`, `rot` | whole texture | texture coordinates (6.3) |
| `tile` | nil | `"H"`, `"V"` or `"HV"`: repeat the texture at 1 texel = 1 px (6.3) |
| `blend` | `"BLEND"` | or `"ADD"` |
| `color` | `"#ffffff"` | vertex colour |
| `grad` | nil | `{ "HORIZONTAL" or "VERTICAL", from, to }`: HORIZONTAL from = left, to = right; VERTICAL from = BOTTOM, to = TOP (the WoW min/max order) |
| `flat` | `from` | colour used when no gradient API works |
| `alpha` | 1 | constant factor on every colour of the layer |
| `maxAlpha` | `bar.maxAlpha` for spans `fill`/`fillEnd`, else 1 | factor in fill state 2 |
| `top`, `h`, `bottom` | 0, nil, 0 | vertical extent in track space: rows y0 = `top`, y1 = `top + h` when `h` is given, else `H - bottom`. Negative values reach outside the track |
| `band` | nil | `{ f0, f1 }` fractions of H from the top (overrides top/h/bottom): `y0 = floor(f0*H+0.5)`, `y1 = floor(f1*H+0.5)` |
| `pad` | `{ 0, 0 }` | range spans: px added outside on the left and on the right |
| `capInset` | false | range spans: when the `caps` of the same span are drawn, shrink by `floor(H/2)` on each side (legacy `fillHi`) |
| `w`, `align`, `dx` | -, `"center"`, 0 | anchor spans: width; the left edge is `anchor - floor(w/2)` (center), `anchor - w` (right) or `anchor` (left), plus `dx` |
| `caps` | false | kind `caps`: the legacy rounded ends (L/R squares H x H with the circle mask `C.TEX_CIRCLE_MASK`, `CLAMPTOBLACKADDITIVE`) when masks exist and the style is `bar`. White file only |
| `three` | nil | kind `three`: `{ file, capTexels, capPx }`, a horizontal 3-slice |
| `nine` | nil | kind `nine`: `{ file, cornerTexels, cornerPx }`, a 9-slice (6.3) |
| `ticks` | nil | kind `ticks`: `{ n = N, w = 1, clip = nil or "fill", mid = false }`. Ticks i = 1..N-1 at `x = floor(W*i/N + 0.5) - floor(w/2)`; with `mid = true`, N ticks i = 1..N at the middles of the N parts, `x = floor(W*(2i-1)/(2N) + 0.5) - floor(w/2)` (`tex[id]` then has N textures); with `clip = "fill"` a tick is shown only when `x < px` and `px > 0` |
| `when` | nil | `"bar"` or `"box"`: the layer exists only in that widget style |

Visibility and geometry rules (normative; E2 implements, E1's golden test checks them under
`actuel`):
- L1. Every bar texture has exactly one point, `SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",
  x, y)` (legacy `Place`). Here `x = ox + x0`, `y = oy + H - y1`, and the size is
  `(x1 - x0) x (y1 - y0)`.
- L2. A layer is hidden when its width or height is 0 or less.
  - `fill` layers are hidden when px is 0 or less.
  - `rested` layers and `restEnd` are hidden when rpx is px or less.
  - `fillEnd` is hidden when px is 0 or less, when px is W or more, or in state 2.
  - In state 2: px = W, rested hidden (legacy).
- L3. Kind `caps` reproduces legacy `DrawTrack`/`DrawFill` exactly:
  - When capsOn and the range width is H or more: L is H x H at a, R is H x H at b - H, and M
    runs from a + floor(H/2) to b - floor(H/2) (M is hidden when that width is 0 or less).
  - Otherwise L and R are hidden and M covers [a, b].
  - capsOn = (masks available) and style == "bar".
- L4. Kind `three` places:
  - L = capPx wide at x0, R = capPx wide at x1 - capPx, M in between.
  - When the width is less than 2 * capPx: L and R are each `floor(width/2)` wide and M is
    hidden.
- L5. Vertex colours and gradients are applied ONLY:
  - at Build, Recolor, or a fill-state change;
  - and, for gradients, lazily: the first time the layer is SHOWN after Build or Recolor, and
    again after a state change while shown if the gradient depends on `base`;
  - phase 2: a `three` / `nine` layer whose gradient runs across its cuts (any on `nine`, a
    horizontal one on `three`) gets it again when it is resized (one ramp, 2.4.2).
  - Never on steady ticks.
  - This exact laziness is required by the existing `test_bar.lua` rested tests: they count
    `SetGradient` calls installed after load.
- L6. Gradient application is `Themes.Gradient` (3.5): first the flat colour as the vertex
  colour (the `from` colour when the item has no flat), then `pcall SetGradient(dir, fromTbl,
  toTbl)` with `{ r=, g=, b=, a= }` tables, else `SetGradientAlpha` (9 arguments). A
  gradient drawn over the flat colour replaces it; a client that accepts the gradient call
  but draws nothing still shows the flat colour instead of the default opaque white
  (round 4). The gradient stays the last colour call, so the golden snapshot is unchanged.
- L7. Positions of static layers (span `track`, `trackStart`, `trackEnd`, unclipped ticks)
  are set only by layout. Dynamic layers are set only when `px`, `rpx` or the state changes.
  Clipped ticks are shown or hidden only when their visibility flips.
- L8. The unlocked veil (`tex.veil`) stays in Bar.lua code. Its colour is `colors.accent` at
  α 0.20.

#### 2.4.2 Panel parts (`bar.panel.parts`, also used by `tooltip.panel.parts`)
| field | default | meaning |
|---|---|---|
| `id` | required | handle `frame.tp.panel[id]` (bar) or `tf.tp.panel[id]` (tooltip) |
| `file` / `nine` / `rect` / `flipX` / `flipY` / `tile` / `blend` | white | as for layers |
| `color` / `grad` / `flat` | `"#ffffff"` | as for layers (no `base`) |
| `anchor` | `"FILL"` | `"FILL"` = whole frame inset by `inset = { l, r, t, b }` (default 0); or a point name (`"TOPLEFT"`...) with `x, y, w, h` |
| `alpha` | 1 | bar panel only: `"bg"` = `widget.bgAlpha`, `"line"` = `min(1, 2 * bgAlpha)`, or a number |
| `layer` / `sub` | `"BACKGROUND"` / -8 + index - 1 | draw layer |

- The bar panel is hidden as a whole when `bgAlpha == 0`.
- Each part's final alpha is colour α × its alpha factor.
- Box style (phase 2): the `FILL` insets of the bar panel parts are moved per side (l, r, t, b)
  so that the outermost `FILL` part (the smallest inset on that side) fits the box frame
  exactly; the other `FILL` parts keep their offsets relative to it. Bar-style insets are tuned
  to wrap bar-only ornaments (negative insets) or the track rows, which the box does not draw.
  Point-anchored parts are unchanged.
- A `grad` on a `nine` part (or a `three` / `nine` layer) is ONE ramp across the pieces
  (`Themes.GradientSliced`, 3.1): each piece gets the part of the ramp it covers, recomputed
  when the part or layer is resized (layout, never a steady tick).
- When the theme's panel is `"backdrop"`, Bar uses today's `ApplyBackground` unchanged. This
  is what actuel uses.

### 2.5 `text` section (bar texts)
Element names, a FIXED list: `s1, s2, s3` (slots), `level` (bottom-left; the level label in
split mode), `levelValue` (split only: % or cap tag), `xpLabel` (split only), `xp` (XP
numbers), `sep`, `marker` (the % following the fill), `hint` (unlocked hint).

| field | default (= today) | meaning |
|---|---|---|
| `font` | every element `"body"` | role per element: `display`, `body`, `num` or `game` |
| `size` | `s1=2, s2=0, s3=-1, level=0, levelValue=0, xpLabel=0, xp=0, sep=0, marker=-1, hint=-1` | delta added to `widget.fontSize`; `hint` total is at least 9 |
| `boxSize` | `s1=2, s2=-1, s3=-1` | box-style deltas |
| `split` | false | level and XP drawn as label + value (two FontStrings each) |
| `splitGap` | 4 | px between label and value |
| `levelFmt` | `"upper"` | `"upper"` = `L.LEVEL_SHORT_FMT` family; `"title"` = `L.LEVEL_TITLE_FMT` |
| `colors` | below | roles |
| `shadow` | `{ color = {0,0,0,0.8}, x = 1, y = -1 }` | applied when `widget.shadow` is on; off = offset (0,0) α 0 (legacy) |

Colour roles and their defaults (named colours of the theme):
- `label="label"`, `value="value"`, `levelLabel="label"`, `levelValue="value"`;
- `xpText="label"` (the XP text when not split, and the XP value when split);
- `sep="label"`, `marker="label"`, `hint="label"`, `slot2="value"`, `slot3="label"`,
  `dimmed="dim"`.
- Assignment, as today:
  - slot 1 uses `value`;
  - slot 2 uses `slot2` in the bar style (phase 2: the class boards colour the rate there;
    the default `value` keeps today's look) and `label` in the box;
  - slot 3 uses `slot3`;
  - a dimmed slot uses `dimmed`.
- A user `widget.textColor` overrides every role, as today (`customRGB` / customDim α 0.55).

Text composition:
- Not split, `levelFmt = "upper"`: legacy formats (`LEVEL_SHORT_FMT`, `LEVEL_PCT_FMT`,
  `LEVEL_CAP_FMT`, `XP_FMT`, `XP_BARE_FMT`), byte for byte.
- Not split, `levelFmt = "title"`:
  - `format(L.LEVEL_TITLE_FMT, lvl)`;
  - with the percentage: `.. L.SEP .. pct`;
  - at the cap: `.. L.SEP .. L.LEVEL_CAP_TAG_TITLE`.
  - The concatenation happens only when the level key changes.
- Split:
  - the level label is `LEVEL_SHORT_FMT` or `LEVEL_TITLE_FMT`;
  - the level value is the percent text (pctPos = "level"), `L.LEVEL_CAP_TAG` or
    `L.LEVEL_CAP_TAG_TITLE` (cap), or empty and hidden;
  - the XP label is `L.XP_LABEL`, with the value `format(L.XP_BARE_FMT, a, b)`;
  - the XP variants are: 1 = label + full numbers, 2 = label + compact, 3 = value only
    (label hidden);
  - the measured width of a split group = labelW + splitGap + valueW.
- Fonts with substitutions (2.6): the engine passes texts through `Themes.Subst(role, text)`
  before `SetText`, only when the text changed, and only when `Themes.HasSubst(role)`.

### 2.6 Fonts (`Themes.FONTS`, owned by E1; theme authors only reference names)
- File: `Interface\AddOns\<ns.ADDON>\Media\Fonts\<file>`.
- `cyr` = covers U+0410-U+044F.
- `subst` = plain-text replacements (Lua decimal escapes in the source).
- `min`, `max`, `snap` = size rules.
- `mono` = add `MONOCHROME`.

| name | file | cyr | extra |
|---|---|---|---|
| Orbitron | Orbitron-Bold.ttf | no | subst `"\194\183"`(·) to `"\226\128\162"`(•), `"\194\171"`(«) and `"\194\187"`(») to `"\""`. DISPLAY ONLY (no ^ Ð Ø Þ ð ø þ) |
| Rajdhani | Rajdhani-SemiBold.ttf | no | |
| Cinzel | Cinzel-Bold.ttf | no | |
| EBGaramond | EBGaramond-Medium.ttf | yes | lining figures by default (T2 measured; the K4 note was wrong) |
| PressStart2P | PressStart2P-Regular.ttf | yes | `min = 8, snap = 8, max = 16, mono = true` |
| PixelifySans | PixelifySans-Regular.ttf | no | |
| UncialAntiqua | UncialAntiqua-Regular.ttf | no | |
| AlegreyaSans | AlegreyaSans-Medium.ttf | yes | old-style figures (K4) |
| GrenzeGotisch | GrenzeGotisch-SemiBold.ttf | no | |
| BarlowCondensed | BarlowCondensed-Medium.ttf | no | |
| CormorantSC | CormorantSC-Bold.ttf | yes | |
| CormorantGaramond | CormorantGaramond-SemiBold.ttf | yes | old-style figures (K4) |
| GermaniaOne | GermaniaOne-Regular.ttf | no | |
| Signika | Signika-Medium.ttf | no | |
| IMFellEnglishSC | IMFellEnglishSC-Regular.ttf | no | |
| Barlow | Barlow-Medium.ttf | no | |
| Philosopher | Philosopher-Bold.ttf | yes | |
| Lora | Lora-Medium.ttf | yes | |
| Metamorphous | Metamorphous-Regular.ttf | no | |
| NunitoSans | NunitoSans-SemiBold.ttf | yes | |
| Macondo | Macondo-Regular.ttf | no | subst `"\194\160"` (NBSP) to `" "` |
| Spectral | Spectral-Medium.ttf | yes | |
| UnifrakturCook | UnifrakturCook-Bold.ttf | no | |

`"game"` = `STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"` (read at call time).

Role to font resolution (`Themes.Font(role, size)`), in order:
1. Take `th.fonts[role]`. `num` defaults to `body`; `game` is literal.
2. If `GetLocale()` is `koKR`, `zhCN` or `zhTW`: use `game`.
3. If `GetLocale()` is `ruRU` and the entry is not `cyr`: use `game`.
4. If the entry was marked missing by `Themes.FontFailed`: use `game`.
5. size = `floor(size + 0.5)`; then apply `min`, then `snap` (`max(snap, floor(size/snap+0.5)*snap)`),
   then `max`.

Bundled fonts are fixed to the 23 above (all have OFL licences in `Media/Fonts/LICENSES`).
Adding a font is an E1 change.

### 2.7 Per-theme briefs
- Boards: the mockups live on the design canvas, outside this repository (one `<Board>.dc.html` per theme).
- Read your board: it is HTML/CSS. The `data-props` block gives the default colours.
- If the board is gone, use this table. Use the fonts below exactly.

| key | board | display | body | colors.xp | colors.rested | owner |
|---|---|---|---|---|---|---|
| futuriste | Futuriste | Orbitron | Rajdhani | #ff2bd6 | #22d3ee | T1 |
| actuel | Main | game | game | C.COLORS.fill | C.COLORS.restedFill | E1 |
| heroic | HeroicFantasy | Cinzel | EBGaramond | #b3122e | #1f4fb8 | T2 |
| pixel | Pixel | PressStart2P | PixelifySans | #38b000 | #3fa9f5 | T2 |
| druid | Druide | UncialAntiqua | AlegreyaSans | #5f9e3a | #7fb2e5 | T3 |
| hunter | Chasseur | GermaniaOne | Signika | #7a9a2e | #5fa8d3 | T3 |
| warrior | Guerrier | GrenzeGotisch | BarlowCondensed | #b33a1f | #3f7fbf | T4 |
| paladin | Paladin | CormorantSC | CormorantGaramond | #d9a72b | #7ec8ff | T4 |
| rogue | Voleur | IMFellEnglishSC | Barlow | #6fdc3a | #8a7dff | T5 |
| priest | Pretre | Philosopher | Lora | #b8a1ff | #9ad0ff | T5 |
| shaman | Chaman | Metamorphous | NunitoSans | #1f8fff | #22d3a4 | T6 |
| mage | Mage | Macondo | Spectral | #a64dff | #3fc7eb | T6 |
| warlock | Demoniste | UnifrakturCook | AlegreyaSans | #3fbf3f | #8788ee | T7 |

Theme authors (T1..T7):
- Reproduce, within the features of this SPEC: the track, fill and rested look, the
  ornaments, the panel, the bar text roles and sizes, the tooltip panel, its separators and
  palette, and the `ui` roles.
- What cannot be expressed (multi-stop gradients beyond bands, blur, letter spacing, CSS
  masks) is approximated or dropped. See K5.
- Decorative layers should be `when = "bar"`. The box style (2 px line) keeps `track`,
  `fill` and `rested` only.
- Use `num = <a lining-figure font>` when the body font has old-style figures (K4).
- Pixel: every pixel-art layer uses integer sizes; `fonts.display = "PressStart2P"`
  (snapped).
- The full `futuriste` source is Appendix B and the full `actuel` source is Appendix A. Copy
  their structure.

### 2.8 Compiled theme (`th`): the engine contract
Engines read ONLY this form and never mutate it. E1 produces it. Since round 5 it is compact
(design/NEXT-LOT.md M1):
- Colours are plain `{ r, g, b, a }` arrays, alpha factors folded in. A static colour (it reads
  no user colour) is one array per value within a compile, shared by its uses; a dynamic colour
  (it reads `xp`, `rested` or `base`) has an array of its own, rewritten in place by every
  recolour (a shared array would recolour another use). No table is shared by two compiles
  (P5: only the active compiled theme stays alive).
- A field equal to its default is not stored. Every compiled record has a metatable whose
  `__index` holds its defaults (the values shown below), so readers index fields as usual:
  `L.layer` is `"ARTWORK"` for a layer that has none; `pairs` and `rawget` see the stored fields
  only.
- Texture specs, gradient pairs and small lists (band, pad, inset, slice, font slot) are one
  table per value within a compile.
```lua
th = {
  key = "futuriste", gen = 7,          -- gen: +1 on every compile and every recolour
  native = nil | true,                 -- tooltip uses the shared GameTooltip (actuel)
  fonts = { display = "Orbitron", body = "Rajdhani", num = <body> },   -- names (Themes.Font)
  colors = { xp, rested, label, value, dim, accent, pause, [bg, border] },  -- the theme's own
                                       -- colours BEFORE user override: Themes.DefaultColor (xp,
                                       -- rested), the classic backdrop (bg, border)
  accent = {r,g,b,a},                  -- veil colour source
  bar = {
    pad = 8, gap = 3, hAdd = 0, hMin = 4, maxAlpha = 0.35,
    panel = "backdrop" | { parts = { P1, ... } },
    layers = { Lc1, Lc2, ... },       -- source order; `when` kept, Bar filters by style
  },
  text = { font = { s1 = "body", ... }, size = { s1 = 2, s2 = 0, s3 = -1, level = 0,
           levelValue = 0, xpLabel = 0, xp = 0, sep = 0, marker = -1, hint = -1 },
           boxSize = { s1 = 2, s2 = -1, s3 = -1 }, split = false, splitGap = 4, levelFmt = "upper",
           shadow = { c = { 0, 0, 0, 0.8 }, x = 1, y = -1 },
           colors = { label, value, levelLabel, levelValue, xpText, sep, marker, hint, slot2,
                      slot3, dimmed } },                     -- every role stored
  tt = { native = true, colors = Themes.CLASSIC_TT }        -- native (every other field ignored)
     | { width = { 280, 440 }, pad = { 12, 12, 10, 10 }, gap = 8, lineGap = 3,
         fonts = { title = { role, size }, body = ..., value = <body>, note = ..., hint = ... },
         colors = { <the 12 roles of 4.3>, ccDim = "|cffrrggbb" },  -- every role stored
         panel = { parts = { P1, ... } },  -- none: the readers' plain dark panel
         titleIcon = nil | { tex, w, h, gap = 6 },
         sep = { header = S | nil, block = S | nil, footer = S | nil },
         leader = nil | { tex, h = 1, y = 3, min = 12, c | g / f },
         gauge = nil | { w = 176, h = 6, gap = 2, outline = nil | rgba, colors = { <8 keys> } } },
  ui = { bg, border, title, accent, label, value, dim },    -- every role stored
}
-- compiled layer (Lc), defaults shown:
{ id = "fill", kind = "tex" | "caps" | "three" | "nine" | "ticks", span = "track",
  layer = "ARTWORK", sub = 0, when = nil | "bar" | "box", tex = <the white 8 x 8 spec>,
  top = 0, bottom = 0, h = nil, band = nil | { f0, f1 }, pad = nil | { left, right },
  capInset = false, w = <stored for anchor spans>, align = "center", dx = 0,
  ticks = nil | { n = <stored>, w = 1, clip = nil | "fill", mid = nil | true },
  dyn = false,       -- true when a colour uses `base`
  c = { 1, 1, 1, 1 },  -- vertex colour (an item without gradient)
  g = nil,           -- gradient: one pair { from, to, dir = "HORIZONTAL" | "VERTICAL" }
  f = nil,           -- flat colour of the gradient (L6); none: its from colour
  m = nil,           -- state-2 alpha factor, stored when it is not the reader's default
}
-- panel part (P): { id, kind = "tex" | "nine", tex, layer = "BACKGROUND",
--   sub = -8 + n - 1 (n: its position in the compiled list), anchor = "FILL",
--   inset = nil | { l, r, t, b } (FILL), x = 0, y = 0, w, h (point anchors),
--   alpha = 1 | "bg" | "line" (bar panel), c | g / f }
-- separator (S): { h = 1, above = 6, below = 5, mirror = false, center = nil, tex, c | g / f }
-- texture spec: { path = <white>, w = 8, h = 8, blend = "BLEND", l = 0, r = 1, t = 0, b = 1
--   (the rect, unflipped), flipX, flipY, tile = nil | "H" | "V" | "HV", tc8 = nil | { 8 } (rot),
--   slice = nil | { texels, px } }: SetTex sets the wrap modes of a tiled spec, and the
--   coordinates of the rect (flipped) of a spec neither tiled nor sliced.
```
Fill states. A layer follows the fill state (BarSkin) when it is `dyn` or its span is `fill` or
`fillEnd`; every other item (other layers, panel parts, separators, leader) is drawn in state 0.
A colour entry (`c`, `f`: a colour; `g`: a pair) is one value for every state or a per-state
list `{ state 0, state 1 [, state 2] }` (readers tell them apart with `type(c[1]) == "table"`
and `type(g[1][1]) == "table"`):
- state 1 differs from state 0 only for `base`: a `dyn` layer has lists;
- state 2 is state 0 with its alpha times `m`: `L.m`, else `bar.maxAlpha` on a fill span, else
  1. A layer with an alpha of its own (besides maxAlpha) has its own state-2 entries instead,
  folded at compile time (`a * (alpha * maxAlpha)`): the drawn numbers are the round-4 ones bit
  for bit.

The colour program (`programs[th]`, weak-keyed, never referencing `th`): the dynamic colours
only, 5 entries each (out, node, def or false, fill state, alpha factor), the theme's xp and
rested nodes, the user colours of its last run, and the tooltip palette when its dim is
dynamic (ccDim follows). `SetGradient` takes tables with r, g, b, a fields: two scratch tables
of Themes carry the values, and no colour of a caller stays referenced after a call.

## 3. Engine (E1: `Themes.lua`; E2: `BarSkin.lua`)

### 3.1 Public API of `ns.Themes`
Everything here is implemented by E1 and frozen by this SPEC.
```lua
Themes.Register(key, source)            -- source text "return { ... }" (2.1) or builder function
Themes.Compile(key) -> th | nil, reason  -- pure: does not change the active theme; silent (round 5:
                                         -- the warnings come from tests/theme_validate.lua)
Themes.Source(key) -> true, src | false, err | nil   -- the source table, built afresh (2.1)
Themes.CompactSource(text) -> text       -- the compaction Register applies (tests)
Themes.IsRegistered(key) -> bool
Themes.Resolve(value, classFile) -> key  -- S5, pure
Themes.Active() -> th                    -- the compiled active theme (lazy, S6)
Themes.ActiveKey() -> key
Themes.Setting() -> string               -- raw setting ("class" stays "class")
Themes.DefaultColor(which) -> rgba       -- "xp" | "rested": theme default before user override (Options swatches)
Themes.Recolor()                         -- recolour in place + gen + THEME_CHANGED "colors" (called by the settings handler; public for tests)
Themes.Font(role, size) -> path, size, mono
Themes.SetFont(fs, role, size, outline) -> path   -- outline: "none" | "thin" | "thick" (widget.outline values)
Themes.FontFailed(path)
Themes.HasSubst(role) -> bool
Themes.Subst(role, text) -> text         -- returns the SAME string when nothing is replaced (no allocation)
Themes.SetTex(t, texSpec)                -- path (+ wrap modes when tiled), tex coords, blend mode; never colour
Themes.Tile(t, texSpec, w, h)            -- repeat coords for a tiled texture of w x h px
Themes.PlaceThree(texs, texSpec, rel, x, y, w, h)  -- texs = 3 caller-owned textures; BOTTOMLEFT of rel
Themes.PlaceNine(texs, texSpec, rel, x, y, w, h)   -- texs = 9 caller-owned textures
Themes.Gradient(t, g, flat) -> 1 | 2 | 3 -- SetGradient | SetGradientAlpha | flat (L6)
Themes.GradientSliced(texs, n, g, flat, k, w, h, p) -> 1 | 2 | 3  -- phase 2: one ramp over a
                                         -- 3-slice (n = 3) or 9-slice (n = 9) of w x h px, corners p px
Themes.CLASSIC_TT                        -- the classic tooltip palette (4.3)
Themes.FONTS, Themes.COMMON_MEDIA, Themes.DISPLAY_KEYS, Themes.GAME_FONT_FALLBACK
```

### 3.2 `Themes.SetFont` (the only way any module sets a themed font)
- It resolves `Themes.Font(role, size)`.
- flags = cached string for (outline, mono):
  - not mono: `""`, `"OUTLINE"`, `"THICKOUTLINE"`;
  - mono: `"MONOCHROME"`, `"MONOCHROME,OUTLINE"`, `"MONOCHROME,THICKOUTLINE"`.
- It keeps a per-FontString cache: three weak-keyed tables (path, size, flags). It skips the
  call when nothing changed. Zero allocation.
- Missing-file detection:
  - Probe once per session: the first call does `fs:SetFont(game, 12, "")`.
  - If that returns a true value, the client reports success, and a falsy return later means
    "missing".
  - Otherwise no failure can be detected.
  - On failure: `Themes.FontFailed(path)`, then retry with `game`.
- `FontFailed` marks the FONTS entry missing for the session and prints
  `format(L.THEME_FONT_MISSING, file)` once per session. Nothing else.

### 3.3 Settings handler and recolour (E1)
- At file load Themes registers `SETTINGS_CHANGED`, `DB_SWAPPED` and `DB_READY` (the latter
  only to mark "class known").
- `"theme"`, or `DB_SWAPPED`: resolve. When the key changed:
  - compile the new theme (dropping the old one);
  - `gen = gen + 1`;
  - send `THEME_CHANGED(key, prev, "theme")`.
- `widget.xpColor*` or `widget.restedColor*`: `Themes.Recolor()`. It re-evaluates every
  compiled colour in place, then sends `THEME_CHANGED(key, key, "colors")`.

### 3.4 Bar engine (E2: `BarSkin.lua`, used by Bar.lua)
- Bar.lua has 193 of 200 locals in its main chunk. New state goes into `BarSkin.lua` (module
  `ns.BarSkin`) or into tables. At most +3 new main-chunk locals in Bar.lua.
- E2 SHOULD delete the now-dead legacy code from Bar.lua: `ReadBarColors`,
  `ApplyFillColor`, `ApplyRestOverlay`, `DrawTrack`, `DrawFill`, `DrawRested`, `NewCap`, and
  `Bar.DEFAULT_*` (Options stops using them, 5.6).
- Required behaviour:
  - B1. Build happens at widget creation, on `THEME_CHANGED "theme"`, and on a style change
    (bar/box). Build assigns pooled regions to the layers of `th.bar.layers` for the current
    style, and hides unused pool entries.
    - Pools are per kind. `caps` textures keep their masks and are never reused for another
      kind.
    - A reused texture is reset: `ClearAllPoints`, `SetTexCoord(0,1,0,1)`,
      `SetBlendMode("BLEND")`, then `Themes.SetTex`.
    - After the first full cycle through all 13 themes, further cycles create ZERO regions.
  - B2. `frame.tp.tex` keeps its table identity. It is cleared and refilled by Build, and
    `tex.veil` survives.
    - Under `actuel` the handles are exactly today's: `trackL/M/R`, `rested`, `fillL/M/R`,
      `fillHi`, `restTick`, `veil`.
    - New handles: `frame.tp.panel` (part id to texture or 9-array); `frame.tp.blv` (level
      value FontString) and `frame.tp.xpl` (XP label FontString), created at the first split
      build, nil before.
  - B3. Layout (`Bar.ApplyLayout`) computes the geometry of 2.4. It positions the static
    layers and draws dynamic ones once (all caches set to -1, as today).
  - B4. `Bar.UpdateXP` calls the skin only when `px`, `rpx` or the state change:
    `SetState(k)` sets the vertex colours of the layers with `dyn` and those of every
    fill/fillEnd layer, for state k (2.8: per-state entries, state 2 scaled by maxAlpha into
    tables of the layer's record); `Draw(px, rpx)` places the dynamic spans.
    - Legacy counts must hold. For example, `tex.fillM:SetVertexColor` is called exactly once
      per state change; see the test_bar rested tests.
  - B5. `THEME_CHANGED "colors"`: Recolor re-applies `c`. Gradients are re-applied lazily (L5).
    No geometry work.
  - B6. Fonts: `Themes.SetFont(fs, th.text.font[e], fs + size[e], w.outline)` for every bar
    FontString and for each meter.
    - Meters (invisible measuring FontStrings) are pooled per (role, size). Each element is
      measured with the meter of its own role and size, generalising today's meterS/M/L.
    - Measurement happens only when the measured text or the layout changes.
  - B7. Panel: `"backdrop"` keeps `ApplyBackground` as it is. Parts are pooled like layers and
    recoloured on `widget.bgAlpha` change (a LAYOUT path today, so no new path needed).
- Performance (all modules):
  - P1. Nothing new runs on `TICK` in Bar except what already runs.
  - P2. No `SetFont`, `SetTexture`, `SetTexCoord`, `SetGradient` or `SetVertexColor` on a
    steady tick. `Stub.calls.SetFont` must not move over 60 steady ticks.
  - P3. No closure or table creation in `UpdateXP`, `Refresh` or `Draw`.
  - P4. Region creation happens at Build only (lazy pools).
  - P5. Only the active compiled theme is kept; switching themes produces garbage once.
    Nothing else may hold a table of the previous compiled theme: Themes clears its texture
    helper caches (`Tile`, `PlaceThree`, `PlaceNine`) whenever a theme is activated, and
    `Tooltip.Fill` clears its palette upvalue when it returns (test_round4_regress).
  - P6. `PlaceThree` / `PlaceNine` skip `SetTexCoord` only when EVERY piece already holds the
    coordinates of its own position for that spec: a pool may hand a layer's textures back
    in another order (a bar -> box -> bar round trip).

## 4. Tooltip (E3: `Tooltip.lua`, `TooltipFrame.lua`)

### 4.1 Targets
- `th.native` (actuel): `Tooltip.ShowFor` keeps the shared `GameTooltip`, with the classic
  palette. Output must be identical to today's: same `_lines`, same `_colors` (golden, 8.2).
- Otherwise: a private frame from `TooltipFrame.lua` (`ns.TooltipFrame`).
  - `TooltipFrame.Get()` creates it lazily, once: anonymous
    `CreateFrame("Frame", nil, UIParent)`, strata `"TOOLTIP"`, clamped to screen, no mouse.
  - It never writes fields on `GameTooltip`.
  - `TooltipFrame.frame` is nil until created.
- Broker keeps calling `Tooltip.Fill(tt, detailed)` with no palette, which means classic.
  Broker.lua needs no change.
- On `THEME_CHANGED` (either kind) Tooltip hides whatever it shows (`Tooltip.Hide()`). The
  next show uses the new theme.

### 4.2 `tooltip` source section (non-native)
| field | default | meaning |
|---|---|---|
| `native` | false | true = GameTooltip, every other field ignored (actuel only) |
| `width` | `{ 280, 440 }` | min / max outer width. The widest XP rows (the warm-up note, a days-long estimated ETA, a 6-digit estimated rate) must fit `width[2]` with 16 px to spare, measured with the real fonts in enUS and frFR (test_round4_regress) |
| `pad` | `{ 12, 12, 10, 10 }` | l, r, t, b |
| `gap` | 8 | min px between left and right texts (and around the leader) |
| `lineGap` | 3 | added to the font size for a row's height |
| `fonts` | required | `{ title = {role,size}, body = {role,size}, value = {role,size}?, note = {role,size}, hint = {role,size} }` (absolute px; value defaults to body) |
| `colors` | required | roles of 4.3 (colours; no `base`) |
| `panel` | required | `{ parts = { ... } }` (2.4.2, alpha numbers only) |
| `titleIcon` | nil | `{ file, w, h, gap = 6 }` left of the title |
| `sep` | nil | `{ header = Sep?, block = Sep?, footer = Sep? }`; a missing kind = blank space of `lineGap + 4` px |
| `leader` | nil | `{ file, tile = "H", h = 1, y = 3, color, min = 12 }`: between label and value of `pair` rows, `y` px above the row bottom |
| `gauge` | nil | `{ w, h, gap, outline = colour?, colors = { world, dungeon, raid, pvp, taxi, afk, inn, city } }` |

`Sep = { h = 1, above = 6, below = 5, file?, tile?, color?, grad?, mirror = false, center? }`.
With `mirror`, two halves are drawn: the left half uses `grad`, and the right half uses `grad`
with from and to swapped. With `center = c` (texels; needs a `file`; excludes `mirror`, `tile`
and `grad`), the middle c texels of the art (an ornament) are drawn at the art's own
proportions (their texel height maps to `h` px) and centred, while the two sides (lines)
stretch to fill the inner width; the side pieces stop half a texel before the cuts. The
pieces are `tp.seps[i].a` (left), `.c` (ornament, created at the first centred
configuration) and `.b` (right).

### 4.3 Palette roles (compiled `th.tt.colors`)
- Roles: `title`, `mode`, `label`, `value`, `dim`, `header`, `pause`, `hint`, `levelLabel`,
  `levelValue`, `levelValueRested`, `rested`, and `ccDim` (a `"|cffrrggbb"` string computed
  from `dim`).
- Defaults when omitted:
  - `title="accent"`, `mode="label"`, `label="label"`, `value="value"`, `dim="dim"`;
  - `header="accent"`, `pause="pause"`, `hint="dim"`;
  - `levelLabel="label"`, `levelValue="value"`, `levelValueRested="value"`, `rested="value"`.
- `Themes.CLASSIC_TT` is the same role table built from `C.COLORS`, with
  `ccDim = C.CC.dim` exactly.

### 4.4 `Tooltip.Fill(tt, detailed, hint, pal)`
- `pal` defaults to `Themes.CLASSIC_TT`.
- `ShowFor` passes `Themes.Active().tt.colors`. For native this is `CLASSIC_TT` itself.
- The content and line order are unchanged.
- The line helpers dispatch on `tt.TP_Row`:
  ```lua
  local P = Themes.CLASSIC_TT          -- set at the start of each Fill
  local function Pair(tt, left, right)
    if tt.TP_Row then tt:TP_Row("pair", left, right, P.label, P.value) return end
    tt:AddDoubleLine(left, right, P.label[1], P.label[2], P.label[3], P.value[1], P.value[2], P.value[3])
  end
  ```
- Row kinds and roles:

  | today's call | kind | colours |
  |---|---|---|
  | title line (+ exclusions) | `title` | `title` / `mode` |
  | pause, read-only, cap lines | `alert` | `pause` |
  | `Pair` | `pair` | `label` / `value` |
  | `PairDim` | `pair` | `label` / `dim` |
  | `Note` | `note` | `dim` |
  | `WrapNote` | `wrap` | `dim` |
  | `Header` | `header` | `header` |
  | max-level line | `line` | `value` |
  | breakdown continuation (left `" "`) | `cont` | `label` / `value` |
  | last line (hint) | `hint` | `hint` |
  | first XP row | `pair` | `levelLabel` / (`levelValueRested` when rested > 0, else `levelValue`) |
  | rested row value | `pair` | `label` / `rested` |
  | `Estimated()` | - | uses `P.ccDim` instead of `CC_DIM` |

- Separators: `Sep(tt, kind)`.
  - On a TP target: `tt:TP_Sep(kind)`.
  - On a native target: `"block"` becomes `tt:AddLine(" ")` (today's `Blank`), and `"header"`
    and `"footer"` add NOTHING.
  - Every `Blank(tt)` becomes `Sep(tt, "block")`.
  - `Sep(tt, "header")` comes after the title, pause and read-only lines.
  - `Sep(tt, "footer")` comes right before the hint. There is none on the early "no data"
    return.
- Gauge:
  - When `tt.TP_Gauge` exists and the theme has `gauge`, the breakdown label row becomes
    `tt:TP_Gauge(L.TT_BREAKDOWN, fracs, keys, n)`.
  - Every breakdown text row then becomes a `cont` row.
  - `Tooltip.BreakdownFracs(bd, fracs, keys) -> n` (new, reused output tables) follows the
    order and the 0 % filter of `BreakdownParts`. `keys` are `world, dungeon, raid, pvp, taxi,
    afk, inn, city`.

### 4.5 `TooltipFrame` object (duck-typed GameTooltip subset, plus extensions)
- Methods:
  - `SetOwner(owner, anchor)`, `GetOwner()`, `ClearLines()`;
  - `AddLine(text, r, g, b, wrap)` = `TP_Row("line" or "wrap", ...)`;
  - `AddDoubleLine(l, r, lr, lg, lb, rr, rg, rb)` = `TP_Row("pair", ...)`;
  - `NumLines()`, `Show()`, `Hide()`, `IsShown()`, `ClearAllPoints()`, `SetPoint(...)`;
  - extensions: `TP_Row(kind, left, right, lc, rc, wrap)`, `TP_Sep(kind)`,
    `TP_Gauge(label, fracs, keys, n)`.
- Rows are pooled: `{ left = FS, right = FS, leader = Texture }`. Pools only grow. Separators
  and gauge segments (8 maximum) are pooled too. No region is ever created by a show whose
  rows and separators fit the pools.
- Fonts by kind:
  - `title` uses `fonts.title` for its left text, and `fonts.body` for its right
    (exclusions) text;
  - `note`, `wrap` and `cont` use `fonts.note`, except `cont` uses `body`/`value`;
  - `hint` uses `fonts.hint` and is centred;
  - everything else uses `fonts.body`, and right texts use `fonts.value`.
  - The `titleIcon` is placed left of row 1.
- `Show()` lays out:
  - outer width = clamp(max natural width of non-wrap rows + pad l + pad r, width[1],
    width[2]);
  - `wrap` rows get `SetWidth(inner)`, and their height is `GetStringHeight()`;
  - pair rows: left at TOPLEFT (pad.l, -y), right at TOPRIGHT (-pad.r, -y); the leader width
    = inner - lw - rw - 2*gap, hidden when it is less than `min`;
  - the height = sum of rows + seps + pad.
- Change-only rules: `SetText` and `GetStringWidth` only when the row's text changed;
  re-anchoring only when y or kind changed. The tooltip refreshes on TICK while shown (today's
  behaviour), so steady values cost no FontString work.
- Anchoring is identical to native: `TOP` below the owner or `BOTTOM` above it, ±4
  (`IsUpperHalf`).
- `StillOurs()` checks: the TF is shown and its owner is `shownFor`.
- The client hides the GameTooltip together with its owner, not the private frame: each
  refresh (TICK, MODIFIER_STATE_CHANGED) of a private tooltip whose owner is no longer
  visible hides it (`Tooltip.Hide()`), e.g. an addon compartment entry hidden without
  OnLeave. `Tooltip.IsShownFor` does not check the owner (Bar's OnHide relies on it).
- The outer width is rounded UP (`ceil`): measured widths are fractional, and a frame
  narrower than its widest row by a fraction of a pixel would cut that row.
- The client's `GetStringWidth` is bounded by an explicit width. A row's left text that a
  previous layout cut (`SetWidth(room)`) is freed (`SetWidth(0)`) before it is measured
  again, whatever made it measured again (its text, or its font after a rebuild).
- Panel: the parts of `tooltip.panel` are built lazily at the first show after a theme change
  (compare `th.gen`).
- Test handles:
  - `tf.tp = { rows = <pool>, n = <rows used>, seps = <pool>, nSeps = <used>, gauge = <segments>,
    icon = <texture>, panel = <id to texture or 9-array> }`;
  - each row is `{ kind = , left = , right = , leader = }`.

### 4.6 Graph and Window (E3, light theming)
- The `ui` roles must not depend on the user's xp / rested colours (a validator warning,
  so test_theme_data refuses it). Graph and Window therefore ignore `THEME_CHANGED "colors"`
  and restyle at a theme switch only (round 4: a colour-picker step used to rebuild the
  shown statistics window).
- `Graph.ApplyTheme()` runs at panel creation and on `THEME_CHANGED "theme"` when the panel exists:
  - backdrop colours `ui.bg` (α 0.92) and `ui.border` (α 0.35);
  - the title font is the `display` role; other texts are `body`, via `Themes.SetFont(fs,
    role, size, "none")`, keeping today's sizes 11/10/9/10;
  - colours: title `ui.title`, labels `ui.label`, values and cursor `ui.value`, note `ui.dim`;
  - `CLASS_COLOR` (good/warn/bad) and the geometry are unchanged.
- `Window.ApplyTheme()` runs at creation and on `THEME_CHANGED "theme"` while the window exists:
  - backdrop `ui.bg` (α 0.95) and `ui.border`;
  - the title FontString uses the `display` role at today's size;
  - accent cells read `Themes.Active().ui.accent` at fill time, and label cells `ui.label`;
  - table cells keep the `GameFont*` objects.
- Under `actuel`, `ui` equals the classic colours, so both look exactly as today.

## 5. Integration points

### 5.1 TOC (E1) and packaging
- TOC file order after the current header:
  ```
  Locales\enUS.lua
  Locales\frFR.lua
  Core.lua
  Format.lua
  Stats.lua
  Tracker.lua
  Played.lua
  Tokens.lua
  Themes.lua
  Themes\actuel.lua
  Themes\futuriste.lua
  Themes\heroic.lua
  Themes\pixel.lua
  Themes\warrior.lua
  Themes\paladin.lua
  Themes\hunter.lua
  Themes\rogue.lua
  Themes\priest.lua
  Themes\shaman.lua
  Themes\mage.lua
  Themes\warlock.lua
  Themes\druid.lua
  Graph.lua
  TooltipFrame.lua
  Tooltip.lua
  BarSkin.lua
  Bar.lua
  Window.lua
  Options.lua
  Broker.lua
  ```
- `.pkgmeta` `ignore:` adds `tools`, `media-src` and `design`. `Media/` is packaged.
- `.luacheckrc` adds `exclude_files = { "tests/baseline/**" }`.
- No new global is read or written by any new code. `GetLocale`, `UnitClass` and
  `STANDARD_TEXT_FONT` are already allowed. Any other global is a `REQUEST:` to E1.

### 5.2 Core.lua (E1)
- S1 to S4: `C.THEME_CHOICES`, `C.CLASS_THEMES`, `C.DEFAULTS.theme`, the `"theme"` Normalize
  kind and `DefineSetting`.
- `C.COLORS` and `C.CC` stay as they are. They are the classic palette, read by `actuel`,
  `Themes.CLASSIC_TT` and `Format.lua`.
- Quality colours (good/warn/bad for FPS and latency) stay global in every theme. `Format.lua`
  and `Tokens.lua` are not modified.

### 5.3 Bar.lua (E2)
- Delegate drawing to BarSkin (3.4).
- Ignore the S8 paths.
- Register `THEME_CHANGED` in `Bar.Init`:
  - `"theme"`: `Bar.ApplyLayout()` (it rebuilds the skin);
  - `"colors"`: `BarSkin.Recolor()` then the fill state again.
- `ReadTextStyle` and `ApplyTextColors` read `th.text.colors`.
- `SetFontSize` becomes `Themes.SetFont`.
- `ApplyShadow` reads `th.text.shadow`.
- Fix the colour change detection: a cache keyed only on user colours misses theme switches,
  so use `th.gen` (risk K12).

### 5.4 Tooltip.lua (E3)
- Sections 4.3 and 4.4.
- `ShowFor` picks the target.
- Register `THEME_CHANGED` to hide.

### 5.5 Graph.lua and Window.lua (E3)
- Section 4.6.

### 5.6 Options.lua (E4)
- **Display section**: the FIRST control after `AddHeader(L.OPT_DISPLAY)` is
  `AddDropdown(L.OPT_THEME, "theme", THEME_CHOICES)`. It is followed by
  `AddNote(L.OPT_THEME_NOTE)` and `AddNote(L.OPT_THEME_RESTART_NOTE)`, then the existing
  controls.
  - The choices table is built with LITERAL keys, in `C.THEME_CHOICES` order:
    `{ value = "futuriste", label = L.THEME_FUTURISTE }, { value = "actuel", label =
    L.THEME_ACTUEL }, ...`.
  - The same table is used by the context menu.
- **Colour defaults**: `DefaultColor(path)` returns `Themes.DefaultColor("xp")` or
  `Themes.DefaultColor("rested")`. The swatches refresh on `THEME_CHANGED`.
  - While the panel is shown, its `SETTINGS_CHANGED` handler skips the `widget.xpColor*` and
    `widget.restedColor*` paths: Themes answers them with `THEME_CHANGED "colors"`, which
    refreshes the controls. One colour-picker step is then one refresh, not two.
  - The reset buttons keep their behaviour (set false); only their labels change (5.7).
- **Context menu**: after the Style submenu, add `root:CreateButton(L.MENU_THEME)` with one
  `CreateRadio` per choice (`IsTheme` / `SetThemeValue`).
- **Slash**:
  - `/tpl theme` prints `format(L.THEME_LIST_FMT, <label of the setting>, table.concat(C.THEME_CHOICES, ", "))`;
  - `/tpl theme <key>` with a valid key runs `SetSetting("theme", key)` and prints
    `format(L.THEME_SET_FMT, <label>)`;
  - anything else goes to `Unknown(msg)`;
  - `"HELP_THEME"` is inserted after `"HELP_STYLE"` in `PrintHelp`.

### 5.7 Locales (E4): new keys, with frFR in the Latin-1 range only
| key | enUS | frFR |
|---|---|---|
| THEME_FUTURISTE | Futuristic | Futuriste |
| THEME_ACTUEL | Classic | Classique |
| THEME_HEROIC | Heroic fantasy | Heroic fantasy |
| THEME_PIXEL | Pixel (old school) | Pixel rétro |
| THEME_CLASS | Class (automatic) | Classe (auto) |
| THEME_WARRIOR / PALADIN / HUNTER / ROGUE | Warrior / Paladin / Hunter / Rogue | Guerrier / Paladin / Chasseur / Voleur |
| THEME_PRIEST / SHAMAN / MAGE / WARLOCK / DRUID | Priest / Shaman / Mage / Warlock / Druid | Prêtre / Chaman / Mage / Démoniste / Druide |
| OPT_THEME, MENU_THEME | Theme | Thème |
| OPT_THEME_NOTE | Changes the look of the bar, its tooltip, the graph and the statistics window. Colours you pick below replace the theme's own. | Change l'apparence de la barre, de son infobulle, du graphique et de la fenêtre de statistiques. Les couleurs choisies plus bas remplacent celles du thème. |
| OPT_THEME_RESTART_NOTE | After installing or updating TruePlayed, restart the game (a /reload is not enough) so that the theme fonts and textures load. | Après avoir installé ou mis à jour TruePlayed, relancez le jeu (un /reload ne suffit pas) pour charger les polices et textures des thèmes. |
| HELP_THEME | /tpl theme [name] - show or change the theme | /tpl theme [nom] - affiche ou change le thème |
| THEME_SET_FMT | Theme: %s | Thème : %s |
| THEME_LIST_FMT | Theme: %s. Available: %s | Thème : %s. Disponibles : %s |
| LEVEL_TITLE_FMT | Level %d | Niveau %d |
| LEVEL_CAP_TAG | CAP | PLAFOND |
| LEVEL_CAP_TAG_TITLE | Cap | Plafond |
| XP_LABEL | XP: | XP : |
| THEME_FONT_MISSING | A theme font could not be loaded (%s); the game font is used instead. Restart the game after an update. | Une police du thème n'a pas pu être chargée (%s) ; la police du jeu la remplace. Relancez le jeu après une mise à jour. |

`THEME_FONT_MISSING` has no "TruePlayed:" prefix: `Util.Print` already adds the chat prefix.

Changed values:
- `OPT_TEXT_COLOR_RESET` and `OPT_BAR_COLORS_RESET` become "Theme colours" / "Couleurs du
  thème".
- `OPT_BAR_COLORS_NOTE`: replace "the game's purple / rested blue" wording with "the theme's
  colours".
- `OPT_TEXT_COLOR_NOTE`: unchanged.

## 6. Assets

### 6.1 Media references
- `"name"` means `Media/Themes/<key>/name.tga`. It MUST be declared in the theme's `media`
  table.
- `"common/name"` means `Media/Themes/common/name.tga`, declared in `Themes.COMMON_MEDIA` (E1).
- Paths are built as `"Interface\\AddOns\\" .. ns.ADDON .. "\\Media\\Themes\\<dir>\\<name>.tga"`
  with the extension included.
- File names are lowercase, `[a-z0-9_]`.
- E1 provides `common/glow.tga` (64 x 32, grey, a soft horizontal glow made for 3-slicing
  with 16-texel caps).

### 6.2 File rules (checked by `tests/check_media.lua`)
- Uncompressed TGA:
  - image type 2, no colour map, 32 bpp;
  - descriptor alpha bits = 8, bottom-left origin (descriptor `0x08`, what
    `tools/svg2tga.py` writes);
  - straight (non-premultiplied) alpha.
- Width and height are powers of two, 256 or less, and equal to the declared `{ w, h }`.
- `grey = true` (meant to be tinted by vertex colour): every pixel has R = G = B. Tinted art
  is drawn white and the theme colour comes from `color`/`grad`. Baked multi-colour art
  (`grey` absent) is drawn with vertex colour white.
- Colour bleed: no fully transparent texel (alpha 0) may be black next to bright visible
  art (luma above 128). The game filters straight alpha, so at a UI scale other than 1, or
  on minified art, a bright edge would blend with that black (a dark fringe). Alpha and
  visible texels are unchanged. `tools/svg2tga.py` bleeds the colour of the art into the
  transparent texels, ring by ring; `--bleed file.tga ...` fixes existing files in place.
- Budget: the sum of the `.tga` sizes in `Media/Themes/<key>/` is 96 KiB (98304 bytes) or
  less. No undeclared `.tga` file is allowed in the folder.
- Every `.tga` has its source `media-src/<key>/<name>.svg`, converted with
  `python3 tools/svg2tga.py src.svg dst.tga` (macOS `sips`).

### 6.3 Texture coordinates
- `rect = { x, y, w, h }` in texels, with (0, 0) the TOP-LEFT of the image as seen in an
  image viewer, whatever the TGA row order. It gives `l = x/W`, `r = (x+w)/W`, `t = y/H`,
  `b = (y+h)/H`.
- `flipX` swaps l and r. `flipY` swaps t and b.
- `rot` (clockwise) uses the 8-value form `SetTexCoord(ULx,ULy, LLx,LLy, URx,URy, LRx,LRy)`:
  - 90: UL=(l,b), LL=(r,b), UR=(l,t), LR=(r,t);
  - 180: UL=(r,b), LL=(r,t), UR=(l,b), LR=(l,t);
  - 270: UL=(r,t), LL=(l,t), UR=(r,b), LR=(l,b).
- `tile`: `SetTexture(path, wrapH, wrapV)` with `"REPEAT"` on each tiled axis (`"CLAMP"`
  otherwise), and `r = w/texW` (H) and/or `b = h/texH` (V). Recomputed by `Themes.Tile` only
  when the size changes.
- `nine = { file, c, p }`: c = corner size in texels, p = corner size in px.
  - Corner and edge pieces are cut at c texels and drawn at p px; edges and the centre
    stretch.
  - Phase 2: a stretched piece samples half a texel inside the cuts along its stretched axis
    (middle column: u from c + 0.5 to W - c - 0.5 texels; middle row likewise in v), so
    bilinear filtering never smears the corner texels over the stretched length. A middle of
    one texel samples that texel's centre. `three` does the same for its middle piece.
  - When w or h is less than 2p, p = `floor(min(w, h)/2)`.
  - `flipX`/`flipY` mirror the whole 9-slice.
  - `tile` is not supported with `nine`.
- `three = { file, c, p }`: the same, horizontally only. The full height is stretched.

## 7. File ownership
Nobody edits a file they do not own. `tests/baseline/` is frozen after Phase 0.

| owner | files (new files marked *) |
|---|---|
| E1 engine/core | `Themes.lua`*, `Themes/actuel.lua`*, `Core.lua`, `TruePlayed_Camelot.toc`, `.pkgmeta`, `.luacheckrc`, `.github/workflows/ci.yml` (add the `check_media` step), `tests/wowstub.lua`, `tests/stub_ui.lua`, `tests/run.lua`, `tests/lint51.lua`, `tests/check_globals.lua`, `tests/check_toc.lua`, `tests/check_encoding.lua`, `tests/check_media.lua`*, `tests/test_core.lua` (theme-setting additions only), `tests/test_theme.lua`*, `tests/test_theme_data.lua`*, `tests/test_actuel_golden.lua`*, `Media/Themes/common/*`*, `media-src/common/*`*, `tools/*` |
| E2 bar | `Bar.lua`, `BarSkin.lua`*, `tests/test_bar.lua`, `tests/test_bar_theme.lua`* |
| E3 tooltip/graph/window | `Tooltip.lua`, `TooltipFrame.lua`*, `Graph.lua`, `Window.lua`, `Broker.lua` (only if needed), `tests/test_graph.lua`, `tests/test_tooltip_theme.lua`* |
| E4 options/locales/docs | `Options.lua`, `Locales/enUS.lua`, `Locales/frFR.lua`, `tests/test_ui_smoke.lua`, `tests/test_options_theme.lua`*, `README.md`, `CHANGELOG.md`, `docs/TEST-EN-JEU-fr.md`, `docs/curseforge-en.md`, `docs/curseforge-fr.md` |
| T1 | `Themes/futuriste.lua`*, `Media/Themes/futuriste/*`*, `media-src/futuriste/*`* |
| T2 | `Themes/heroic.lua`*, `Themes/pixel.lua`* + their `Media/Themes/<key>/`, `media-src/<key>/` |
| T3 | druid, hunter (same pattern) |
| T4 | warrior, paladin |
| T5 | rogue, priest |
| T6 | shaman, mage |
| T7 | warlock |
| orchestrator | Phase 0 (`tests/baseline/`), Phase 2 |

Untouched by everyone: `Format.lua`, `Stats.lua`, `Tracker.lua`, `Played.lua`, `Tokens.lua`,
`Media/Fonts/*`, `tests/stub_engine.lua`, `tests/stub_stats.lua`, and every other existing test
file. A legacy test outside your files that breaks is a bug in your code: fix the code, never
the test.

## 8. Tests

### 8.1 Stub additions (E1, `tests/wowstub.lua`)
- `Stub.theme`:
  - It is set to `"actuel"` by `Stub.Reset()` when not `keepWorld`.
  - `Stub.LoadAddon` sets `ns.C.DEFAULTS.theme = Stub.theme` after loading every file, when
    it is non-nil.
  - The ~400 legacy tests therefore keep testing the classic look.
  - Theme tests set `Stub.theme = nil` (real default `futuriste`) or a key, after `Reset` and
    before `LoadAddon`.
- `Stub.created = { Texture = 0, MaskTexture = 0, FontString = 0, Frame = 0 }`. It is
  incremented in `NewObject` (every frame type counts as `Frame`) and reset by `Reset`.
- `Stub.calls.SetFont` and `Stub.calls.GetStringWidth` are incremented by those methods.
- `Stub.missingFonts = {}` (reset). `FontString:SetFont` returns `not Stub.missingFonts[path]`.
- `CreateTexture(name, layer, template, sub)` records `_subLayer = sub`.
- `SetTexCoord(...)` also records `_tc = { ... }`, keeping `_texCoordN`.
- `SetBlendMode(m)` records `_blend`.
- `SetTexture(path, wrapH, wrapV)` records `_wrapH` and `_wrapV`.
- `SetGradient(dir, a, b)` records `_grad = { dir, a.r, a.g, a.b, a.a, b.r, b.g, b.b, b.a }`.
  Tests that rawset it keep working.
- `SetGradientAlpha(...)` records `_gradA = { ... }`.
- `Stub.regions`: the list of every created region in creation order. It is reset by `Reset`
  and used by the golden snapshot.

### 8.2 Golden: `tests/test_actuel_golden.lua` (E1)
- If `tests/baseline/TruePlayed_Camelot.toc` is missing, `T.skip("no Phase 0 baseline")`.
- For each scenario:
  - set `Stub.ROOT = ROOT .. "tests/baseline/"`, load and play the scenario, take a snapshot;
    `Reset`;
  - restore `Stub.ROOT`, load the current tree with `Stub.theme = "actuel"`, play the same
    scenario, take a snapshot;
  - `T.eq(snapA, snapB)`.
- The bar snapshot is the sorted list of strings, one per VISIBLE region under
  `TruePlayedWidget` (the region and its ancestors are shown). Each string holds:
  - type, layer, sub, texture path, rect relative to the widget (via the stub's `Rect`), size;
  - vertex colour and alpha (rounded to 1e-4), `_grad`/`_gradA`, blend, mask present;
  - text, font path, size, flags, text colour, justify, shadow offset and colour.
  - It also includes the widget's size, scale, backdrop and backdrop colours.
- Scenarios:
  1. login defaults;
  2. rested (xp 2000, rest 3000);
  3. rest larger than the level;
  4. max level;
  5. server cap;
  6. box style;
  7. custom xp, rested and text colours;
  8. `bgAlpha 0.5` + outline thick + shadow off;
  9. `pctPos = level`, width 150, fontSize 16;
  10. unlocked (veil and hint).
- Tooltip golden: the `GameTooltip._lines`/`_colors` after `Tooltip.ShowFor(widget)` in
  scenarios 1, 2 and 4, short and Shift.

### 8.3 E1 tests
- **`test_theme.lua`**:
  - the default is futuriste; `SetSetting` accepts the 14 values and rejects `"foo"`;
  - repair keeps `"newtheme"` and drops `42` and `"bad-key!"`;
  - `Resolve`: class with MAGE gives mage; class with a nil/unknown class gives futuriste;
    an unregistered key gives futuriste;
  - `THEME_CHANGED`: exactly one per real change, none at `DB_READY`, none for
    "class" to "mage" as a mage;
  - xpColor changes give `"colors"`, gen+1, and the same table identities;
  - sparse save drops `"futuriste"` and keeps `"mage"`;
  - `Stub.theme` hook;
  - `Font()` with `Stub.locale = "ruRU"` (Rajdhani gives game, EBGaramond stays) and with
    `"zhCN"` (all game); PressStart2P snapping (11 gives 8, 13 gives 16);
  - `SetFont` cache: a second identical call does not move `Stub.calls.SetFont`;
  - missing font: fallback, and exactly one printed message per session;
  - `Subst` returns the same string when nothing matches; with `T.alloc` it allocates 0
    over 1000 calls.
- **`test_theme_data.lua`**: for every registered key:
  - the validator (`tests/theme_validate.lua`, installed on `Themes.Compile`) gives zero
    warnings;
  - every font name is in FONTS and every media reference is declared;
  - ids are unique, sub is in -8..7, bands are valid;
  - required colours and tooltip roles are present;
  - `base` is used only in layers;
  - Orbitron is never `body` or `num`;
  - the text elements that show arbitrary strings (`s1`, `s2`, `s3`, `xp`, `sep`,
    `levelValue`, and `hint`, a free locale sentence) use the `body`, `num` or `game` role,
    never `display`; likewise the tooltip fonts `body`, `value`, `note` and `hint` (only
    `title` may be `display`). The display role only renders `DISPLAY_KEYS` texts and
    percent/number texts.
  - All 13 keys are registered.
- **`tests/check_media.lua`** (standalone, CI step, exit code 1 on problems; Lua 5.1/5.5
  portable, `string.byte` parsing only, because lint51 forbids `string.unpack`):
  - TTF cmap (formats 4 and 12) coverage per theme:
    - `body` and `num` fonts cover BODY_SET: U+0020-U+007E, U+00A0, U+00AB, U+00B7, U+00BB,
      U+00C0-U+00FF minus U+00D7 and U+00F7, plus every character of
      `Locales/enUS.lua` and `Locales/frFR.lua`.
    - `display` fonts cover the characters of `Themes.DISPLAY_KEYS` in both locales, plus
      `"0123456789%.,:/-()~ "` and U+00A0.
    - Coverage is checked after `subst`.
    - `DISPLAY_KEYS = { "LEVEL_SHORT_FMT", "LEVEL_TITLE_FMT", "LEVEL_PCT_FMT",
      "LEVEL_CAP_FMT", "LEVEL_CAP_TAG", "LEVEL_CAP_TAG_TITLE", "XP_LABEL", "ADDON_TITLE",
      "WIN_TITLE", "GRAPH_TITLE_FMT", "GRAPH_WINDOW_30", "GRAPH_WINDOW_60",
      "GRAPH_WINDOW_300" }`.
  - FONTS `cyr` flags equal the real coverage.
  - Every font file and its `LICENSES/<Family>-OFL.txt` exist.
  - TGA rules of 6.2.
- **`check_globals.lua`**: a new scenario with `Stub.theme = nil`:
  - cycle through all 14 setting values;
  - show the tooltip, graph and window in each;
  - open the options and use `/tpl theme` with and without an argument.
  - No global write and no new field on WATCHED tables.
- **`lint51.lua`**: unchanged rules. The new files must pass them, including the 60-upvalue
  and 200-local limits.

### 8.4 E2: `tests/test_bar_theme.lua` (+ `test_bar.lua` stays green under actuel)
- For each of the 13 keys:
  - the widget builds without errors;
  - the handles of every layer of the current style exist in `tp.tex`;
  - 600 ticks allocate 2 KB or less (pattern of `test_bar.lua`);
  - over 60 steady ticks: `SetText` counts on slots/bl/brx/blv/xpl and `Stub.calls.SetFont`
    do not move;
  - `Stub.onUpdateCount == 0`.
- Region reuse: cycle through the 13 keys twice, plus the box style once. During the second
  cycle the `Stub.created` totals do not change.
- Futuriste geometry (default user settings):
  - H = 14 and the frame size follows the 2.4 formula (compute it in the test);
  - `tex.ticks` has 9 textures at `ox + floor(W*i/10 + 0.5)`;
  - with xp 2000/7600 and W = 360, `fillSegs` shows exactly the ticks with x < px;
  - `tex.marker` is at `ox + px - 1`, 2 px wide.
- Futuriste colours:
  - `tex.fill` is #ff2bd6 when not rested and #22d3ee when rested;
  - state 2 alpha is 0.35;
  - after `SetSetting("widget.xpColor", {0,1,0})`, `tex.fill` is green with no relayout
    (frame size unchanged, no new regions).
- Split texts:
  - `tp.bl:GetText() == format(L.LEVEL_SHORT_FMT, level)`;
  - `tp.xpl:GetText() == L.XP_LABEL`;
  - `tp.brx:GetText() == format(L.XP_BARE_FMT, Fmt.Number(xp), Fmt.Number(max))` on a wide
    bar.
- Panel: `bgAlpha 0` hides every `tp.panel` part; at 0.5, `panelFill` α = 0.5 × colour α and
  `panelLine` α = 1 × colour α.

### 8.5 E3 and E4 tests
- **`test_tooltip_theme.lua`** (E3):
  - with futuriste, `ShowFor(widget)` uses `ns.TooltipFrame.frame` and `GameTooltip` stays
    hidden with zero lines;
  - content parity: the TF row texts in order equal the native lines of the same state,
    minus the `" "` blank lines;
  - separators: header 1, footer 1, and blocks = the native blank count;
  - the gauge segment count = the breakdown parts;
  - the second show creates 0 regions;
  - 300 ticks while shown with steady values: no `SetText` on unchanged rows;
  - a theme change while shown hides it;
  - Broker `Fill` on a mock tooltip uses the classic colours while futuriste is active;
  - `actuel` uses `GameTooltip`.
- **`test_graph.lua`** (E3): the existing tests stay green, plus `ApplyTheme` colours under
  futuriste.
- **`test_ui_smoke.lua`** (E4): update the two reset-label assertions to "Theme colours" /
  "Couleurs du thème".
- **`test_options_theme.lua`** (E4):
  - the dropdown is the first Display control, with values in `C.THEME_CHOICES` order and
    non-empty labels in enUS and frFR;
  - selecting a value sets the setting and fires `THEME_CHANGED` once;
  - the swatch defaults follow `Themes.DefaultColor` after a switch;
  - context menu radios;
  - `/tpl theme` (prints the list), `/tpl theme mage`, `/tpl theme foo` (Unknown);
  - help contains `HELP_THEME`.

### 8.6 Commands (every implementer, before finishing)
```
lua tests/run.lua            # also: lua tests/run.lua <filter>
lua tests/check_toc.lua && lua tests/check_encoding.lua && lua tests/lint51.lua
lua tests/check_globals.lua && lua tests/check_media.lua
```
- Run them with both `lua5.1` and Lua 5.5 when available.
- `E1` also adds every new test file name to `FILES` in `tests/run.lua`:
  `test_theme`, `test_theme_data`, `test_actuel_golden`, `test_bar_theme`,
  `test_tooltip_theme`, `test_options_theme`, (round 4) `test_round4_regress` (with the
  helper `tests/fontmetrics.lua`: text widths from the real TTF advances, for truncation
  and overlap checks), and (phase 2) `test_theme_integration`: every
  setting value at run time across the bar (both styles), tooltip, graph and window; the
  box-style panel; sliced gradients; half-texel cuts; the slot 2 role; the user's own
  configuration at a server level cap; rebuild equivalence (after a theme or style switch,
  with the tooltip shown short / Shift / hidden under the previous theme, the bar, the
  private tooltip and the GameTooltip lines are identical to a fresh load in the new
  theme, two-point anchors resolved as the game does).

### 8.7 Memory pass (round 5, design/NEXT-LOT.md A)
- `tests/theme_validate.lua` (test-only): the round-4 compiler, moved out of Themes.lua
  unchanged (same parse, same fallbacks, the same warning texts). `TV.Install(ns)` makes
  `Themes.Compile(key)` return `th, warnings` and checks on every call that the compiled theme
  draws exactly what the round-4 compiler compiled (`TV.Canon`: the values the engines read,
  numbers compared with `==`). `TV.Color`, `TV.Pair`, `TV.Flat`, `TV.PartSub` read a compiled
  item as the engines do.
- `tests/test_theme_compact.lua`: plain rgba arrays (one per static value, one per dynamic
  colour), no stored default, equality with the round-4 compiler for the 13 themes with and
  without user colours, recolour in place, no table shared by two compiles, the silent
  fallback on bad data (the same values as round 4), the 13 compact source texts (no comment,
  no function, lossless compaction, an empty environment, `actuel` = `C.COLORS`).
- `tests/test_theme_memory.lua` (Lua 5.4 and 5.5 only): budgets of the compiled themes, the
  source texts (80 KB or less), Themes.lua and the addon after login; the method is written
  in its header.
- `tests/render_snapshot.lua` (a tool, not run by `tests/run.lua`): what the addon draws for
  the 13 themes in 8 scenarios (loaded and switched to), every view; two checkouts are
  compared with `diff` (the proof that the memory pass changed nothing on screen).

## 9. Docs (E4)
- **README.md**: a "Themes" section covering:
  - the list of themes with one line each;
  - "Class (automatic)";
  - the default (Futuristic);
  - how to switch: Options > Display > Theme, right-click menu > Theme, `/tpl theme <name>`;
  - custom colours override the theme;
  - restart the game after install or update;
  - the bundled fonts under the SIL OFL (list them, with the licence folder).
- **CHANGELOG.md**: an `[Unreleased]` entry:
  - themes added;
  - the default look is now Futuristic for everyone;
  - `/tpl theme actuel` (Classic) restores the previous look;
  - new fonts and textures need a full game restart.
- **docs/TEST-EN-JEU-fr.md** (French): an in-game checklist per theme:
  - no missing-glyph boxes (accents, « · », NBSP in numbers);
  - bar at width 150/360/600 and font size 9/16;
  - rested, max level, cap;
  - bgAlpha 0 / 0.5 / 1;
  - box style;
  - tooltip short and Shift;
  - graph, window;
  - switching themes in combat-free time;
  - memory (`/tpl` debug) before and after 10 switches;
  - restart versus /reload after an update.
- **docs/curseforge-en.md** and **docs/curseforge-fr.md**: add themes to the feature list.

## 10. Risks
- K1. "oui" was read as "existing users switch too". If the user meant otherwise, the
  fallback is one line in `RepairSettings` (E1): when the record has prior data and no
  `theme`, write `theme = "actuel"`. It is not implemented now.
- K2. Glyph gaps:
  - Orbitron lacks `^ « · » Ð Ø Þ ð ø þ`. It is display-only, with subst.
  - Macondo lacks NBSP (subst).
  - `check_media` enforces coverage.
- K3. Cyrillic and CJK clients (zone and class names come from the client): the per-role game
  font fallback gives a mixed look there.
- K4. Old-style figures (Cormorant Garamond, Cormorant SC, Alegreya Sans, Uncial Antiqua,
  IM Fell; EB Garamond, Lora and Spectral turned out to be lining) make numbers uneven.
  Authors set `num` to a lining font or `"game"` (druid, paladin, warlock).
- K5. Lost CSS effects:
  - letter spacing, text-transform (only via locale strings);
  - multi-layer text glow, blur and drop shadows;
  - only the bundled font weights;
  - clip-path shapes (baked into TGA);
  - radial gradients and masks;
  - gradients with 3 or more stops (approximated by bands).
  - The boards are targets, not pixel specs.
- K6. Media load only at client start. After an update, a `/reload` shows missing textures
  (not detectable) and fonts fall back (detected, message). This is documented in the
  options, README and CHANGELOG.
- K7. The `SetFont` return value differs between clients. The probe (3.2) disables detection
  when the game font itself does not report success.
- K8. `SetGradient` colour tables:
  - `CreateColor` is not allowed (luacheck/check_globals);
  - plain `{r,g,b,a}` tables are used under pcall, with the `SetGradientAlpha` and flat
    fallbacks, as today.
- K9. `SetTexture` wrap modes (`"REPEAT"`) may not exist on the WoW Forever client. Tiled art
  then stretches. Authors keep tiled layers low-alpha so that stretching stays acceptable.
- K10. Bar.lua is at 193 of 200 locals. Everything new goes into BarSkin.lua; lint51 fails
  otherwise.
- K11. Ornaments outside the track (glow, brackets) need `pad`. A larger frame shifts the
  visual position of saved anchors by a few px; `ClampedToScreen` may cut a glow at the screen
  edge.
- K12. Legacy colour caching:
  - change detection was keyed on user colours only, so a theme switch would not recolour
    (use `th.gen`);
  - tints were set only at texture creation, so they must be re-applied by every Build and
    Recolor.
- K13. Fixed geometry in Graph and the Window table vs wide fonts (Cinzel, UnifrakturCook,
  GrenzeGotisch): only titles and colours are themed there; titles may truncate.
- K14. Package size: +3.2 MB of fonts and up to 12 × 96 KiB of TGA. Client memory grows only
  by the fonts actually set.
- K15. A private tooltip frame is not skinned by tooltip-skinning addons (by design). Broker
  tooltips stay classic.
- K16. Parallel work: an API drift between E1 and E2/E3/E4 is caught only in Phase 2. This
  SPEC's sections 2.8 and 3.1 are frozen. Report any deviation as `ASSUMPTION:`.
- K17. If Phase 0 is skipped, the golden test skips and the actuel parity is unproven.
- K18. Interpretation of the boards' "rested" semantics: the whole fill takes the rested
  colour while rested (game behaviour, as today, as on the boards).

---

## Appendix A: `Themes/actuel.lua` (E1), complete
```lua
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
        layer = "ARTWORK", sub = 3, color = { 1, 1, 1, 0.10 }, when = "bar" },
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
```
Equivalence notes (E2 must preserve them):
- `fill` in state 2 = xp colour × 0.35.
- `fillHi` α 0.10 × 0.35 at max.
- `restTick` x = `ox + rpx - 1`.
- Caps only in the bar style with masks.
- Gradients are applied lazily (L5): one `SetGradient` the first time rested, none when
  rested again.

## Appendix B: `Themes/futuriste.lua` (T1), complete
The round-4 design source, kept as the reference the theme was built from (the shipped file
has since been tuned in game). It is written as a builder with comments inside, as round 4
registered it; since round 5 the file registers the same table as a source text without
comment (2.1), the comments moved to a notes block above the `Register` call.
```lua
-- Themes/futuriste.lua - "Futuristic" (default theme): neon HUD from the Futuriste board.
-- Orbitron (display, upper-case labels) + Rajdhani (numbers and text), magenta XP,
-- cyan rested, bevelled navy panels with cyan lines and purple accents.
local ADDON, ns = ...

ns.Themes.Register("futuriste", function()
  return {
    name = "THEME_FUTURISTE",
    fonts = { display = "Orbitron", body = "Rajdhani" },
    colors = {
      xp = "#ff2bd6", rested = "#22d3ee",                -- board defaults
      label = "#a3bfcf", value = "#f0fbff", dim = "#7f96a9", accent = "#22d3ee",
      pause = "#fbbf24",
      cyan = "#22d3ee", cyanHi = "#67e8f9", cyanPale = "#a5f3fc", ice = "#bae6fd",
      purple = "#a855f7", ink = "#01040b", navy = "#060c1a", mode = "#8ea6b8",
    },
    media = {
      panel       = { 64, 64, grey = true },  -- filled panel, TL and BR corners cut at 45 deg (14 px of 16)
      panel_line  = { 64, 64, grey = true },  -- 1 px outline of the same shape
      scan        = { 8, 8, grey = true },    -- 1 px opaque rows at y = 0 and 4, transparent elsewhere (tiled)
      track_frame = { 32, 32 },               -- baked: 3 px ink outline + 1 px #67e8f9 line, TL/BR bevel 7 px
      bracket     = { 8, 32 },                -- baked "[" : ink 3 px under cyan 1.5 px, open side right
      dash        = { 16, 2, grey = true },   -- 10 px on, 6 px off (tiled)
      dot         = { 4, 2, grey = true },    -- 1 px dot every 2 px on row 0 (tiled)
      diamond     = { 16, 16 },               -- baked title icon: cyan diamond outline + purple core
    },
    bar = {
      pad = 10, gap = 4,
      height = { add = 6, min = 10 },         -- default user height 8 -> 14 px track
      maxAlpha = 0.35,
      layers = {
        -- neon halo under the fill, outside the track
        { id = "glow", span = "fill", three = { "common/glow", 16, 8 }, pad = { 8, 8 }, top = -6, bottom = -6,
          layer = "BORDER", sub = -2, blend = "ADD", color = "base@.55", when = "bar" },
        -- track: dark navy body, a little lighter at the top, scan lines, 10 % graduations, 50 % mark
        { id = "track", span = "track", layer = "BORDER", sub = 0,
          grad = { "VERTICAL", "#03060e@.93", "#0c1426@.88" }, flat = "#070d1a@.9" },
        { id = "trackScan", span = "track", file = "scan", tile = "HV", layer = "BORDER", sub = 1,
          color = "ice@.05", when = "bar" },
        { id = "ticks", span = "track", ticks = { n = 10 }, layer = "BORDER", sub = 2,
          color = "cyanPale@.26", when = "bar" },
        { id = "mid", span = "track", ticks = { n = 2 }, layer = "BORDER", sub = 3,
          color = "cyanPale@.5", when = "bar" },
        -- rested part: lighter rested colour fading out to the right, with a sheen line
        { id = "rested", span = "rested", layer = "ARTWORK", sub = 1,
          grad = { "HORIZONTAL", "rested+.5@.62", "rested+.5@0" }, flat = "rested+.5@.35" },
        { id = "restSheen", span = "rested", top = 2, h = 1, layer = "ARTWORK", sub = 2,
          grad = { "HORIZONTAL", "rested+.85@.65", "rested+.85@0" }, flat = "rested+.85@.3", when = "bar" },
        -- fill: active colour, shaded light -> dark in four bands (board: +72 % / +12 % / -22 % / -58 %)
        { id = "fill", span = "fill", layer = "ARTWORK", sub = 3, color = "base" },
        { id = "fillTop", span = "fill", band = { 0, 0.28 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#ffffff@.12", "#ffffff@.72" }, when = "bar" },
        { id = "fillUpper", span = "fill", band = { 0.28, 0.43 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#ffffff@0", "#ffffff@.12" }, when = "bar" },
        { id = "fillLower", span = "fill", band = { 0.43, 0.70 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#000000@.22", "#000000@0" }, when = "bar" },
        { id = "fillBottom", span = "fill", band = { 0.70, 1 }, layer = "ARTWORK", sub = 4,
          grad = { "VERTICAL", "#000000@.58", "#000000@.22" }, when = "bar" },
        { id = "fillSheen", span = "fill", top = 2, h = 1, layer = "ARTWORK", sub = 5,
          color = "#ffffff@.6", when = "bar" },
        { id = "fillSegs", span = "track", ticks = { n = 10, clip = "fill" }, layer = "ARTWORK", sub = 6,
          color = "#020612@.5", when = "bar" },
        -- frame, HUD brackets, end-of-fill marker
        { id = "trackFrame", span = "track", nine = { "track_frame", 8, 8 }, pad = { 1, 1 }, top = -1, bottom = -1,
          layer = "ARTWORK", sub = 7, when = "bar" },
        { id = "bracketL", span = "trackStart", file = "bracket", w = 8, align = "right", dx = -2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 0, when = "bar" },
        { id = "bracketR", span = "trackEnd", file = "bracket", flipX = true, w = 8, align = "left", dx = 2,
          top = -6, bottom = -6, layer = "OVERLAY", sub = 0, when = "bar" },
        { id = "markerGlow", span = "fillEnd", file = "common/glow", w = 12, top = -6, bottom = -6,
          layer = "OVERLAY", sub = 1, blend = "ADD", color = "base+.85@.5", when = "bar" },
        { id = "marker", span = "fillEnd", w = 2, top = -4, bottom = -4,
          layer = "OVERLAY", sub = 2, color = "base+.85", when = "bar" },
      },
      panel = { parts = {
        { id = "panelFill", nine = { "panel", 16, 14 }, color = "navy", alpha = "bg", sub = -8 },
        { id = "panelScan", file = "scan", tile = "HV", inset = { 2, 2, 2, 2 }, color = "cyan@.05",
          alpha = "bg", sub = -7 },
        { id = "panelLine", nine = { "panel_line", 16, 14 }, color = "cyan@.55", alpha = "line", sub = -6 },
        { id = "accentTop", anchor = "TOPLEFT", x = 15, y = 0, w = 96, h = 2, color = "cyan",
          alpha = "line", sub = -5 },
        { id = "accentBottom", anchor = "BOTTOMRIGHT", x = -15, y = 0, w = 84, h = 2, color = "purple",
          alpha = "line", sub = -5 },
      } },
    },
    text = {
      font = { s1 = "body", s2 = "body", s3 = "body", level = "display", levelValue = "body",
               xpLabel = "display", xp = "body", sep = "body", marker = "display", hint = "body" },
      size = { s1 = 3, s2 = 3, s3 = 2, level = -1, levelValue = 5, xpLabel = -2, xp = 3,
               sep = 3, marker = -2, hint = 0 },
      boxSize = { s1 = 4, s2 = 2, s3 = 2 },
      split = true, splitGap = 5, levelFmt = "upper",
      colors = { label = "label", value = "value", levelLabel = "cyanPale", levelValue = "#ffffff",
                 xpText = "value", sep = "cyan", marker = "xp+.45", hint = "label", slot3 = "#e6f7ff",
                 dimmed = "dim" },
      shadow = { color = "ink@.85", x = 1, y = -1 },
    },
    tooltip = {
      width = { 300, 440 }, pad = { 14, 14, 10, 10 }, gap = 8, lineGap = 3,
      fonts = { title = { "display", 13 }, body = { "body", 15 }, value = { "body", 15 },
                note = { "body", 13 }, hint = { "body", 12 } },
      colors = { title = "cyanHi", mode = "mode", label = "label", value = "#eef8ff", dim = "dim",
                 header = "cyanHi", pause = "pause", hint = "dim", levelLabel = "#d9eef8",
                 levelValue = "xp+.45", levelValueRested = "rested+.45", rested = "rested+.45" },
      panel = { parts = {                   -- tooltip corners are cut top-right and bottom-left
        { id = "bg", nine = { "panel", 16, 16 }, flipX = true, color = "navy@.95", sub = -8 },
        { id = "scan", file = "scan", tile = "HV", inset = { 2, 2, 2, 2 }, color = "cyan@.035", sub = -7 },
        { id = "line", nine = { "panel_line", 16, 16 }, flipX = true, color = "cyan@.72", sub = -6 },
        { id = "accTop", anchor = "TOPLEFT", x = 0, y = 0, w = 160, h = 2,
          grad = { "HORIZONTAL", "cyanHi", "cyan@0" }, sub = -5 },
        { id = "accLeft", anchor = "TOPLEFT", x = 0, y = 0, w = 2, h = 26, color = "cyanHi", sub = -5 },
        { id = "accBottom", anchor = "BOTTOMRIGHT", x = 0, y = 0, w = 72, h = 2, color = "purple", sub = -5 },
        { id = "accRight", anchor = "BOTTOMRIGHT", x = 0, y = 0, w = 2, h = 22, color = "purple", sub = -5 },
      } },
      titleIcon = { "diamond", 12, 12, gap = 8 },
      sep = {
        header = { h = 1, above = 7, below = 6, grad = { "HORIZONTAL", "cyan@.6", "cyan@0" } },
        block  = { h = 1, above = 6, below = 5, file = "dash", tile = "H", color = "cyanHi@.3" },
        footer = { h = 1, above = 7, below = 6, mirror = true, grad = { "HORIZONTAL", "cyan@0", "cyan@.35" } },
      },
      leader = { file = "dot", tile = "H", h = 1, y = 4, color = "cyanHi@.24", min = 12 },
      gauge = { w = 176, h = 6, gap = 2, outline = "ink@.6",
                colors = { world = "cyan", dungeon = "purple", raid = "#818cf8", pvp = "#fb923c",
                           taxi = "#f472b6", afk = "#64748b", inn = "#fde68a", city = "#facc15" } },
    },
    ui = { bg = "navy", border = "cyan", title = "cyanHi", accent = "cyan",
           label = "label", value = "#eef8ff", dim = "dim" },
  }
end)
```
- Media budget: 2 × 16 KiB + about 4 KiB + 2 KiB + 1 KiB + small files, about 40 KiB
  (≤ 96 KiB).
- SVG sources go in `media-src/futuriste/`.
- T1 checks the result in game against the board (docs/TEST-EN-JEU-fr.md) and may tune
  numbers, but must not change the schema.
