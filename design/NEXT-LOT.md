# Next lot (round 5): memory pass, language option, kill average

State at the time of writing:
- The themes of round 4 (`design/SPEC-themes.md`) are implemented and validated in game by the author.
- 526 tests pass, and every check is green.
- Work in English (code, comments, tests). User-facing text lives only in `Locales/enUS.lua` and
  `Locales/frFR.lua`.

## Non-negotiables (unchanged)
- **CPU and memory must be exemplary.**
  - No `OnUpdate`. The only repeating timer is Core's shared 1 s `TICK`.
  - Zero garbage per steady tick.
  - `SetText`, `SetFont`, `SetTexture`, `SetVertexColor` and `GetStringWidth` run only on
    change.
  - Regions are created once and pooled.
- Per-character isolation, persistence, crash recovery and localisation.
- The game runs Lua 5.1. `tests/lint51.lua` enforces the limits: 200 locals per chunk, 60
  upvalues, no `string.unpack` in addon code.
- Never weaken a legacy test or `tests/test_actuel_golden.lua`. `tests/baseline/` is the frozen
  pre-theme copy that the golden test uses: never edit it.

## Commands
```sh
lua tests/run.lua
lua tests/check_toc.lua && lua tests/check_encoding.lua && lua tests/lint51.lua
lua tests/check_globals.lua && lua tests/check_media.lua
```
- The suite was developed on Lua 5.5. CI also runs Lua 5.1 and luacheck
  (`.github/workflows/ci.yml`).
- Texture conversion (`tools/svg2tga.py`) relies on macOS `sips`, so it is not available on
  Linux. This lot needs no new texture.

## A. Memory pass
Measured in the test stub (Lua 5.5, after login, full GC):
- before themes: about 800 KB;
- theme `actuel`: about 1250 KB;
- theme `futuriste` (default): about 1440 KB.

Causes:
1. The compiled theme takes 77 to 113 KB for the 12 non-`actuel` themes, about 4.5 KB per
   layer. The reasons: mixed colour tables (`r,g,b,a` plus `[1..4]`), per-state copies, and
   gradient and flat tables for every layer.
2. The 13 theme builders stay resident as bytecode: about 240 KB in total, and more on
   Lua 5.1, where line info costs 4 bytes per instruction. Their source text is about 135 KB.
3. `Themes.lua` is 112 KB of bytecode, part of it compile-time validation that only tests need.

Targets and approach:
- **M1. Compact compiled form, 25 KB or less per theme.**
  - Use plain 4-number colour arrays, interning the static ones only, so that an in-place
    recolour never corrupts a shared array.
  - Do not keep per-state copies when a colour does not depend on the fill state.
  - Use two module-level scratch `{r,g,b,a}` tables for `SetGradient`.
  - Materialise no default field.
- **M2. Validation in test-only code.** Move the warnings-only validation into a test-only
  module, for example `tests/theme_validate.lua`. The shipped compiler stays robust and falls
  back on bad data.
- **M3. Theme sources resident as compact text, 80 KB or less in total.**
  - Each `Themes/<key>.lua` registers a long-bracket string holding `return { ... }`, with no
    comments inside. Comments stay outside the string.
  - The string is compiled on demand with `loadstring` (Lua 5.1) or `load`, in an empty
    environment (`setfenv` on 5.1), and the function is dropped right after.
  - Leading indentation is stripped once at registration.
  - Add a test: no `--` and no `function` inside the sources.
- **Proof of render identity.** Snapshot every visible region of the widget, the private
  tooltip (short and Shift), the graph and the window:
  - for the 13 themes;
  - in these scenarios: defaults, rested, max level, server cap, box style, custom colours,
    `bgAlpha` 0.5 + thick outline + no shadow, unlocked.
  - Compare against a checkout of the commit taken before the pass. The diff must be EMPTY.
- Add `tests/test_theme_memory.lua` with the size thresholds. It runs only on Lua 5.4 and 5.5.

## B. Language option
- New setting `language`:
  - values: `"auto"` (default, follows `GetLocale()`), `"enUS"`, `"frFR"`, plus later every
    translated locale;
  - account-wide, saved sparse.
- SavedVariables arrive after the files run. Therefore:
  - keep the frFR strings in their own table at file load (today `frFR.lua` patches `ns.L`
    directly when the client is French);
  - apply the chosen locale into `ns.L` when settings are adopted (`ADDON_LOADED`, re-run at
    `PLAYER_LOGIN` for WTFix), before any UI is built;
  - then drop the unused locale tables.
- Audit every module-level cache of an `L.*` value, because it would capture English. Read
  such values at use time instead.
- Options:
  - a dropdown "Langue (Language)" in the Display section;
  - each choice written in its own language: "Auto", "English", "Français";
  - a note saying a UI reload is needed, and that game-provided names (zones, mobs) stay in
    the client language;
  - a "Reload" button calling `ReloadUI()`.
- Slash command `/tpl lang en|fr|auto`, plus a help line.
- Tests: adoption order, fallback for an unknown value, no English left in frFR mode, sparse
  save, options and slash command.

## C. Mobs to kill: average of the last 10 kills
- Today `Stats.KillsToLevel` uses only `char.lastKill.xp`, the base XP of the last XP-giving
  kill, so the number jumps with every mob level.
- Replace it with the average base XP of the last 10 XP-giving kills (base XP, without the
  rested bonus):
  - keep a small per-character ring of 10 numbers, persisted and bounded;
  - keep `lastKill` for display;
  - the rest-aware math stays as it is.
- Tooltip: `~38 (average: 47 XP, last: 30 XP)` / `~38 (moyenne : 47 XP, dernier : 30 XP)`.
- Tests: ring wrap, migration from a record that only has `lastKill`, per-character isolation,
  no garbage per tick.

## Delivery
- Run the full suite and every check twice.
- Update `CHANGELOG.md`, `README.md` and `docs/TEST-EN-JEU-fr.md` (French).
- The author installs into the game locally. New files need a full game restart; Lua changes
  in existing files only need a `/reload`.

## Outcome (implementation notes, 2026-10-01)
- **A. Memory pass**: done, with one open point.
  - Render identity: `tests/render_snapshot.lua` (13 themes x 8 scenarios: bar, private
    tooltip short and Shift, GameTooltip, graph, window 3 tabs, options; fresh load and theme
    switch) gives an empty diff against f427da9 on Lua 5.5, 5.4 and 5.1. The only later
    difference is the options panel, where part B adds the language controls.
  - M2, M3: met (silent shipped compiler, the round-4 compiler kept as `tests/theme_validate.lua`;
    13 source texts, 65.6 KB, no builder resident).
  - **M1 not met**: compiled themes went down by 68 to 70 % but stay above 25 KB except
    actuel, pixel and shaman. Lua 5.5: actuel 7.3, pixel 23.0, shaman 24.7, futuriste 34.0,
    warlock 35.7 KB (5.4: +8 to 12 %; 5.1: futuriste 51.6 KB). With named-field records the
    floor is about 28 KB for warlock; packed positional records would save about 3 KB on 5.5
    and nothing on 5.4. `tests/test_theme_memory.lua` holds per-theme budgets of the measured
    sizes. **Decision (author, 2026-10-01): the measured sizes are accepted as the target**;
    the per-theme budgets (measured + about 10 %) guard them.
  - After login (offline, Lua 5.5): futuriste 1410 -> 1201 KB, actuel 1222 -> 1073 KB.
- **B. Language option**: done (setting `language`, applied at ADDON_LOADED and again at
  PLAYER_LOGIN, locale tables dropped after login, options dropdown + Reload UI button,
  `/tpl lang`). A SavedVariables swap later in the session applies its language at the next
  reload.
- **C. Kill average**: done (`char.killRing`, 10 entries, seeded from `lastKill`). The exact
  French tooltip string is wider than the old one: `tooltip.width[2]` of 10 themes grew by 4 to
  36 px so that the widest row still fits; normal tooltips do not change.

## Backlog (author, 2026-10-01)
Goal: as much choice and customisation as possible for players who do not want the XP bar.
1. **Translations** into every locale the game supports (short words: no cut text). Next lot.
2. **Remove the compact box style** of the bar (nobody would use it: players pick the XP bar,
   the minimap button or the mini display). Next lot, with 1.
3. **Minimap button**: left click shows the information (the bar's tooltip), right click
   opens a menu (options, statistics, ...).
4. **Mini display**: a small movable frame for a screen corner, showing 2 or 3 compact infos
   chosen by the player; on hover, the same tooltip as the bar; it follows the theme chosen
   for the bar.

## Outcome of backlog 1 and 2 (round 6)
- **2. Compact box removed**: setting `widget.style`, its option, menu entry, `/tpl style`,
  every box code path (Bar, BarSkin, Themes: `when`, `text.boxSize`) and the box-only theme
  data are gone. A stored `"box"` is dropped by the settings repair (the bar shows, the key
  leaves the sparse file). Render identity: `tests/render_snapshot.lua` on this tree and on
  the 1.0.1 tree differs only in the options panel (the style dropdown), on Lua 5.5, 5.4
  and 5.1. `tests/test_actuel_golden.lua` (frozen) still has a "6. box style" scenario,
  which now fails by design: the author decides (delete the scenario or its box stages).
- **1. Translations**: `Locales/deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW`.
  `C.LANGUAGES_NATIVE_ONLY` (ruRU, koKR, zhCN, zhTW): offered and applied only on a
  client in that language. `tests/test_locales.lua` checks the keys and format arguments,
  the languages offered and applied, every view in every language, and the widths with
  the real fonts (tooltips, bar, options, window, graph; Cyrillic with the `cyr` fonts or
  a stand-in, Hangul / Han at one em per character). `check_encoding` allows UTF-8 in the
  four native locale files only; `check_media` checks every Latin-1 locale against every
  theme font and ruRU against the `cyr` fonts.

## Outcome of backlog 3 and 4 (round 7)
- **3. Minimap button** (`MinimapButton.lua`, frame `TruePlayedMinimapButton`): settings
  `minimap.shown` (true), `minimap.locked` (false), `minimap.angle` (225, degrees),
  `minimap.click` (`"stats"` | `"options"` | `"bar"` | `"mini"`). Hover = `Tooltip.ShowFor`
  with the hint of the left-click action, right click = `Options.ShowContextMenu`, drag =
  the frame's own `StartMoving` (no OnUpdate), snapped back onto the edge at the cursor
  angle on release (LibDBIcon's shape table, `GetMinimapShape`). Not registered with
  LibDBIcon (no duplicate button). `/tpl minimap`.
- **4. Mini display** (`MiniDisplay.lua`, frame `TruePlayedMiniDisplay`): settings under
  `mini` (`shown` false, `locked`, `point`, `infos` = eta_kills, xph, none, `layout`
  horizontal | vertical, `xp` none | pct | line | both (line), `scale`, `bgAlpha` 0.6,
  `combatHide`, `fade`). Tokens consumer `"mini"` with its own resolver
  (`Tokens.Acquire(owner, n, resolve)`), texts measured on meters on change only, the
  frame sized to its texts; the bar's theme fonts / colours / panel parts, widget text
  options and XP colours. `/tpl mini`.
- Context menu: "Show" submenu (bar, mini display, minimap button); "Hide" hides the
  menu's owner. Options: section "Minimap button and mini display".
- Render identity: `tests/render_snapshot.lua` against the tree before this lot differs
  only in the options views (Lua 5.5 and 5.1); the stub's Minimap is opt-in
  (`Stub.InstallUI({ minimap = true })`).
