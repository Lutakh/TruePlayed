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
- The game runs Lua 5.1. `tests/lint51.lua` enforces 5.1 portability: at most 60 upvalues
  per function, no `string.unpack` in addon code. It does **not** count locals: the
  200-active-locals limit per function (a file's main chunk included) is enforced only by
  the compiler, of Lua 5.1 in the game and CI and of Lua 5.5 here (same limit: loading
  the file in `lua tests/run.lua` fails with "too many local variables"). A file near the
  limit (Tracker.lua: 198) takes new code as field functions (`M.X = function`).
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

## Outcome of lot 8 part A (data: dead, professions, per-level additions)
- **State keys** (`C.STATE_KEYS`, `C.TRACKED_KEYS`): `x` = dead or a ghost, `f` = professions,
  one key each (no AFK variant), never excluded by a mask (`C.INCLUDED[m].x/f` always true),
  not part of `Breakdown.active`. Precedence (Tracker `Compute` + `Activity.Override`):
  dead > AFK > professions > flight > instance > city > inn > world. New file `Activity.lua`
  (`ns.Activity`: `Override(afk, now)`, `IsDead()`, `IsProf(now)`, `Start()`); the heuristic
  and its limits are in its header and in the README.
- **Saved data** (sparse, no schema bump): `s.x` / `s.f` in every seconds map (life, levels,
  level zones, zones, sessions); `levels[L].d` (deaths, already there); `levels[L].eta`
  (seconds, the time to level shown when the level began) and `levels[L].etaP` (XP fraction
  then). Repair drops non-numbers, a negative `x` / `f`, `eta <= 0` or inf, `etaP` outside
  0..1. A crash gap rebuilt from the server /played gives no share to `x` / `f`.
- **Stats API for the UI**: `Breakdown(...).dead / .prof`; `LevelHistory` rows `dead`, `prof`,
  `eta`, `etaP`, `cum` (+ `deaths`); `SessionHistory` rows `dead`, `prof`;
  `Stats.LevelActivity(char, L)` -> deaths, deadSecs, profSecs, eta, etaP;
  `Stats.CumulativeTime(char, L, mask, sync, now)` -> seconds from level 1 to the end of L
  (the played total, pre-install time included, minus the filtered level times above L);
  `Stats.AccountActivity(db)` -> deadSecs, profSecs, deaths.
- **Display (minimum)**: breakdown parts "Prof." and "Dead" (gauge colours `prof`, `dead` in
  the 11 gauge themes; at most 4 parts a line once one of them shows), Shift lines
  "Professions" (> 0 only) and "Deaths  n (time)"; Levels tab columns "Dead" ("5m (2)") and
  "Est.", shown with a 830 px window only when a level has deaths, dead time or an estimate
  (the Classic window stays identical to the baseline copy otherwise); continents under
  `C.CONT_MIN_SECS` (60 s) hidden in the tooltip and the Zones tab.
- `tests/test_actuel_golden.lua`: its tooltips are now taken after one more minute of play
  (the baseline lists a 5 s continent the current tree hides); both trees still get the
  same inputs.

## Outcome of lot 8 part B (UI: tooltip and statistics window)
- **Tooltip**: breakdown parts largest first (legend and gauge, `SortedParts`, allocation
  free). Short view: the overall average per level is gone, the last-5-levels average stays.
  Shift view: "Top zones" = top 3 of `char.zones` under the mask (zones whose time is all
  excluded are skipped); the overall average, the last levels, the account lines and the
  "rebuilt after crashes" total are gone (window footer / Levels tab / the sub-line under
  /played). `tests/test_actuel_golden.lua`: the inputs are unchanged; `Intended()` drops
  those baseline lines and renames "Top zones this level" before the comparison.
- **Window**: per-tab column catalogs (`LAYOUTS`, `Col(id, key, w, opt, flex)`); the
  builders `Put` texts by column id, `EndRows` shows the optional columns that have a value,
  lays them out (the flexible column takes the room left) and fills the cells (`SetText` /
  `SetTextColor` on change only). New columns: Levels `cum` (Total), `prof`; Sessions `dead`,
  `prof`. Level rows "L » L+1" (`L.RANGE_FMT`), Reached = `row.endAt` (Stats: `lb.t1`, else
  the next record's `t0`). Size: `window.width` (700..1800) / `window.height` (300..1200),
  the frame never narrower than its columns (+50), a resize grip saves the size on release.
  Capitals: Time = `Stats.Sum(bucket, mask)`, Raw = `SumAll`, AFK = AFK keys.
- **Dates**: `window.dateFmt` (`auto` = `L.DATE_FMT`, `dmy`, `mdy`, `ymd`) and `window.clock`
  (`auto` = `L.TIME_FMT`, "%I" in it = 12 h; `24`; `12`), `Fmt.DateTime` (always the year,
  hours and minutes). `L.DATETIME_FMT` became `L.TIME_FMT`.
- **Fonts**: a failed `SetFont` makes the entry pending (game font meanwhile, no repeated
  failing call); retries on a private probe FontString 2 and 10 ticks after
  PLAYER_ENTERING_WORLD (TICK listened to only while due); a retry that loads it sends
  THEME_CHANGED "theme" (same key) so every consumer applies its fonts again; after the
  last retry the remaining entries are missing and one chat line names every file.

## Crash review, part A (rebuilt time under the exclusions, recent habits)
Reported: a level breakdown identical to the character's, and "This level 1h 21m / incl.
1h 46m rebuilt after a crash" with AFK excluded (the rebuilt part was gross).
- **Saved data** (sparse, no schema bump): `life.es` and `levels[L].es` = rebuilt seconds per
  state key, shaped like `s`, written by `Tracker.EstimateGap` (step 0, dropped segments:
  exact key; step 4, the split) beside the gross `est` totals, which stay as they were. Both
  maps are created on their first write only (never by the constructors, the repair or the
  delta); no `es` per zone. On new data `sum(es) == est` and `es[k] <= s[k]`. Repair
  (`RepairES`, the `RepairXS` rules): a non-table is dropped, bad or negative values are
  dropped. `RepairEstimatedInstances` moves `es` along with the instance seconds it moves
  (at most what `es` holds for that key).
- **Stats**: `Stats.EstTime(bucket, mask)` -> filtered, gross. Filtered = masked sum of `es`
  + the part saved without keys (`est - sum(es)`, older versions) scaled by the bucket's
  masked / unmasked place time (u, x, f left out), capped to the masked tracked seconds;
  gross = `max(est, sum(es))`. `LevelHistory` rows: `estF` (at most `filtered`); `est` stays
  gross. Allocation-free.
- **Display**: the tooltip notes under "This level" and "Played" use `EstTime` (capped to the
  line above, shown only when > 0), the Levels tab `~` mark and `ROW_EST_TIP_FMT` use
  `estF`, `/tpl played` too. Under a breakdown whose gross rebuilt share of its tracked time
  exceeds `C.EST_MOST` (0.5), a wrapping dim note `L.TT_EST_MOST_FMT` (the share, at most
  100 %): the level's in the short view, the character's under its breakdown with Shift.
- **Split of a gap** (`EstimateGap` step 2): the state proportions come from the levels L0
  (the level of the last sync or save) down to `L0 - C.RECENT_LEVELS`, `rec` levels left out,
  each as `s - es` (an earlier estimate is never split again); a bucket with time rebuilt
  by an older version (`est - sum(es)`, no keys; valued like the bucket, as `EstTime`)
  counts for its real time only (`s - es` scaled by `1 - legacy / places`, places = s
  without u, x, f, less es) and not at all when that part is over `C.EST_MOST` of its places
  (a level split like the whole character by an older version is no habit); same zeroing
  as before (x, f, other instance kinds, negatives); under `C.EST_MIN_HISTORY` the whole
  life (`life.s - life.es`, same rule), then everything to `w`.
- **Tests**: `test_crash` 23-25b (recent levels, fallback to the life and a second gap,
  `rec` and `es` left out, older estimates scaled or skipped) and es checks in 1, 2, 8, 19; `test_stats` (EstTime, `estF`);
  `test_core` (RepairES, es moved by the instance repair); `test_tokens` (the sub-lines
  under the exclusions, the note both ways); a "crash" play in the tooltip width tests
  (`test_round4_regress`, `test_locales`).

## Crash review, part B (automatic reload; plain "Reload now" click since part R)
The game writes SavedVariables only at logout or /reload, so a crash loses the whole load.
- **Settings** (sparse, off by default): `autoReload.rest` (bool), `autoReload.timer` (bool),
  `autoReload.minutes` (10 to 120, step 5, default 30). Options section "Automatic reload"
  after "Hide /played": two checkboxes, each with a "?" help icon (`C.TEX_HELP`, the
  statistics window's icon, tinted with the theme's ui colours; tooltip: why (the rest
  option only) and how, on clients without a direct reload the "how" of the prompt
  instead (`OPT_AUTORELOAD_REST_ASK_FMT`, `OPT_AUTORELOAD_TIMER_ASK_FMT`: no chat warning,
  no move to cancel, the window in a capital or an inn too) and the click line), and the
  interval slider, greyed while the timer is off.
- **AutoReload.lua** (new file, after Played.lua in both .toc): armed (TICK subscription)
  only while an option is on, ns.ready and not read-only; re-evaluated on
  `SETTINGS_CHANGED` (autoReload.*) and `DB_SWAPPED`. Due moment `dueG = loadStartG +
  min(C.AUTORELOAD_REST_MIN, minutes * 60)`; before it a tick compares two numbers.
  - Rest mode: state key in `C.IS_CITY` / `C.IS_INN`, at least `C.AUTORELOAD_REST_MIN`
    (3600 s since part U, 600 s before) unsaved, standing still `C.AUTORELOAD_SETTLE`
    (10 s), and only after an arrival (10 s in a row outside since this load; crafting `f`
    and dead `x` are not outside), so a player AFK in town is not reloaded again and again.
  - Timer mode: `minutes` unsaved; elsewhere than a capital or an inn the prompt; in a
    capital or an inn as above without an arrival, but only while the rest mode is off
    (part U: with both on, the timer leaves those places to the rest mode); never in an
    instance, on a flight, dead or during professions (`f` hides the place, an
    instance's too) (it waits).
- **Two paths**. Direct (every client but Forever): chat warning `C.AUTORELOAD_WARN` (5 s)
  before, every check again on each tick of it (moving, the key leaving rest, any blocker
  cancels: `L.RELOAD_CANCELLED`, asked again `C.AUTORELOAD_SNOOZE` later), then
  `ReloadUI()` at most once per load; still alive `C.AUTORELOAD_RETRY` s later means it
  was ignored: switch to the prompt. Prompt (Forever, or after `ADDON_ACTION_BLOCKED` /
  `_FORBIDDEN` naming the addon): the addon's own frame (BackdropTemplate on UIParent,
  strata DIALOG, top centre at -140, theme colours at each show, flat buttons sized from
  their text), not StaticPopup. "Reload now" is a plain button whose OnClick calls
  `ReloadUI()` on every client (part R below); on Forever nothing ever reloads without
  that click. The click checks the data part of the blockers again (an XP gain between
  two ticks); should the game still block it (`ADDON_ACTION_BLOCKED` naming the addon
  within a second of the click), ignore it (the UI still running `C.AUTORELOAD_RETRY` s
  after the click: the tick), or `ReloadUI` be missing, the chat prints
  `L.RELOAD_BY_HAND` ("type /reload") once. The prompt is never shown in combat and hides at
  `PLAYER_REGEN_DISABLED` (comfort, and no stray click reloads mid-fight), asked again
  `C.AUTORELOAD_RETRY` s later. A shown prompt is watched on each tick: hidden in an
  instance (the key, or `IsInInstance()` while `f`), on a flight or dead (asked again
  `C.AUTORELOAD_RETRY` s later); "Reload now" waits, greyed and disabled (no highlight,
  no click), while the data part of the checks fails (an XP gain, a level-up, a /played
  answer) out of combat (a quest, a discovery: no flicker; a fight hides the prompt, which
  comes back enabled once its XP is read); it is enabled again when the prompt shows again.
  Turning both options off hides a shown prompt, in combat lockdown too. The options'
  "Reload UI" button keeps its plain `ReloadUI()` in OnClick (it always worked on
  Forever).
- **Safety** (`AutoReload.Blocker`, at the due moment only, cheapest first, a constant
  reason string; a failure waits `C.AUTORELOAD_RETRY` s): ready, read-only, TruePlayedDB
  adopted, WTFix (`Core.IsWTFixProtected`, factored out of `CheckWTFix`), reconcile or gap
  XP pending, `/played` pending, no server sync, XP not settled (`Tracker.IsSettled`), load
  younger than `C.AUTORELOAD_LOAD_MIN`, level-up younger than `C.AUTORELOAD_LEVELUP_WAIT`,
  then combat, dead, casting or channelling, typing, a popup, a UI panel, the game menu or
  options (`SettingsPanel`, `GameMenuFrame`, `KeyBindingFrame`, `InterfaceOptionsFrame`:
  no panel area, `GetUIPanel` misses them), a cinematic, a ready check, the cursor; the
  direct path also needs the statistics window and the options closed. Every game global
  is read at call time and type-checked (16 new globals in the three whitelists).
- **Memory**: about 26 KB of resident code on Lua 5.5 (30 KB before part R removed the
  overlay); `test_theme_memory` after-login budgets raised by 40 KB (the file run alone was
  already over before this part).
- **Tests**: `test_autoreload` (22, 26 since part U: modes, arrival, countdown and its cancels, every
  blocker, the prompt and its plain button (a reload on the click only, nothing created on
  top of it), combat (hidden at its start; options turned off hide it, in lockdown too),
  the shown prompt watched (instance, flight, dead; greyed and disabled while XP or a
  level-up is read, a click before the next tick included; enabled again when it comes
  back), the "type /reload" hint after a blocked or ignored click, professions in a dungeon, blocked
  / forbidden / ignored reload, the options section and help icons, the options' plain
  "Reload UI" button (built in combat too), zero allocation); `test_language` clicks that
  button and expects `ReloadUI`; `test_locales` (new keys, checkbox width less the help
  icon); a `check_globals` scenario "prompt and its click" (direct countdown, the prompt
  and its click, block, busy player, the game's options).

## Part R: "Reload now" is a plain button on WoW Forever (2026-10-09)
Measured in game by the author on Forever 1.60.1: the options' "Reload UI" button (a plain
`ReloadUI()` in its OnClick) reloads, so `ReloadUI()` from addon code inside a hardware
click works there (EllesmereUI's "blocked even inside a click" is wrong for this build);
`/run C_Timer.After(3, ReloadUI)` does not reload (no click: refused).
- Removed: the secure overlay of the first version of part B (`InsecureActionButtonTemplate`
  with a /reload macro), the code that built and managed it, `AutoReload.AttachReload`,
  `AutoReload.ReloadClick`, and the protected-frame workarounds (combat lockdown checks
  before showing, watching or hiding the prompt). The options' "Reload UI" is back to its
  original plain call.
- Kept: the automatic path on Era and retail; the `ADDON_ACTION_BLOCKED` / `_FORBIDDEN`
  safety net (no call without a click for the rest of the load, the prompt takes over);
  the per-tick watch of a shown prompt.
- Help text: only `OPT_AUTORELOAD_CLICK` changed, in the 11 locales (enUS "On this game
  client an addon may reload the interface only after your click, so TruePlayed asks you
  with a button.").
- Stub: `InsecureActionButtonTemplate`, `SetAttribute` / `GetAttribute`, `Stub.macros` and
  `Stub.secureReloads` are gone (creating that template now raises an error); the
  whitelists only had their `ReloadUI` comment changed (`C_XMLUtil` was there before).
- Mutations: 7 of 8 caught; the survivor (the disabled state alone) is covered by the
  click's own check (a disabled button gets no click).

## Part T: two tooltips side by side (user's choice "B", then side by side, 2026-10-09)
The two section titles did not tell the level in progress from the character total well
enough: with Shift, the character total is now its own tooltip (SPEC-themes 4.1, 4.4, 4.5).
It was first stacked under the level's; after the author's in-game feedback (Forever,
druid theme, a small screen: the stack was too tall, the end of "Character total" cut at
the bottom of the screen) the two are side by side, their breakdowns face to face, and
the stack is only the fallback of a screen too narrow for the pair. After the author's
check of side by side in game (fine in the druid and Classic themes, "but the classic
theme has no breakdown bar, only the values"), the Classic theme got a breakdown bar too.
- **Blocks**: block 1 (always): the title (+ exclusions), the pause and read-only lines,
  then "Current level" as before (with the rate details while Shift is held). Block 2
  (Shift, and only when the character has data): "Character total" and everything under
  it. The footer hint is at the bottom of the last shown block. Each block has its own
  gauge.
- **Fill**: `Tooltip.Fill(tt, detailed, hint, pal, part)`; `part` nil or 0 = one tooltip
  with both sections (Broker, `/tpl`, the offline tools: unchanged), 1 = block 1 (the hint
  only without Shift), 2 = block 2 (reuses the token context block 1 updated in the same
  refresh; no "block" separator before its section). It returns false without character
  data (no block 2 then), and the line number of its breakdown row (see below).
- **Frames**: non-native themes: `TooltipFrame.Get(1)` and `Get(2)`. The former
  module-level state of TooltipFrame.lua (pools, caches, methods) is built by `NewFrame()`,
  once per frame; frame 2 at the first Shift. Pools only grow and the theme parts are
  applied once per theme change, per frame; the normalized theme section is shared and
  dropped on THEME_CHANGED (only the active theme stays referenced). `TP_Measure()` (the
  width the fill would take; measures changed texts only, no table) and `TP_MinWidth(w)`
  give both one width when stacked; `TP_RowY(i)` (the centre of row `i` down from the
  frame's top, from the last layout, no work) lines up the breakdown rows side by side.
  Test handles: `TF.frame`, `TF.frame2`. Native theme (Classic):
  block 2 is `CreateFrame("GameTooltip", "TruePlayedCharTooltip", UIParent,
  "GameTooltipTemplate")`, created once at the first Shift, at GameTooltip's scale (a
  tooltip addon may scale it); when stacked, one width by showing both at their own
  width, then the narrower again with `SetMinimumWidth` (whether the client counts the
  padding in it is learned at the first use and taken off); the minimum width set on the
  shared GameTooltip goes when it hides (an `OnHide` hook, set once: the client hides it
  with its owner without our Hide) or when the pair hides, never under another owner's
  shown tooltip. `TruePlayedCharTooltip` is whitelisted (`.luacheckrc`, `lint51`).
- **Labels**: `L.TT_BREAKDOWN` ("Breakdown") is replaced by `L.TT_BREAKDOWN_LEVEL` and
  `L.TT_BREAKDOWN_TOTAL` in the 11 locales (enUS "Level breakdown" / "Total breakdown",
  frFR "Répartition du niveau" / "Répartition totale", deDE "Stufenaufteilung" /
  "Gesamtaufteilung", esES and esMX "Reparto del nivel" / "Reparto total", itIT
  "Ripartizione del livello" / "Ripartizione totale", ptBR "Divisão do nível" / "Divisão
  total", ruRU "Распределение уровня" / "Общее распределение", koKR "레벨 분류" / "전체
  분류", zhCN "本级分布" / "总分布", zhTW "本級分布" / "總分布"), in Broker's tooltip too
  (through `Tooltip.Fill`, Broker.lua unchanged). On the private frames the label now
  always has a row of its own (the gauge row, or the label alone in Heroic, the theme
  without a gauge), the parts on the rows under it: the longer labels no longer fit
  beside the parts (frFR in Heroic: 448 px for 428). Broker keeps the label and the
  first parts on one line (the Classic theme did too until its bars, below). Worst
  margin between a label and its gauge: 31 px (warrior theme, ruRU).
- **Breakdown rows**: `Tooltip.Fill` also returns the line number of the fill's first
  breakdown row (the gauge or label row on a private frame, the label's own line on a
  native block since its bars, the label-and-parts line on another GameTooltip), 0
  without one (no tracked time). The row's centre, down from its block's top: `TP_RowY`
  on a private frame; on a GameTooltip, the centre of the client's
  `<name>TextLeft<i>` line text against the tooltip's top, that FontString looked up once
  per line through `_G` and cached. `tests/check_globals.lua` allows the `_G` read in
  `Tooltip.lua` only (`READ_OK_IN`); the stub creates the named GameTooltips' line texts
  (`<name>TextLeft<i>`, positioned, not counted as the addon's regions). A GameTooltip's
  lines have positions only once it is anchored: the shift is read again after placing,
  and the pair placed again when it changed.
- **Placement side by side** (Shift, the pair fits the screen's width): block 1 on the
  left, block 2 4 px to its right, each at its own natural width (no common width). Block
  2 is moved so that its breakdown row has the same centre as block 1's (`d`, how far
  block 1's top sits above block 2's; tops aligned when a block has no breakdown row).
  Block 2 is anchored to the owner, block 1 to block 2. The box around both hangs 4 px
  below the owner when it is in the upper half of the screen, else stands 4 px on it (the
  7.6 rule), block 1 centred on the owner as when alone. Block 2's clamp rect covers the
  box (`SetClampRectInsets`), so the screen clamp moves both together, never one alone;
  the shared GameTooltip's clamp is never changed. A box taller than the screen: the
  clamp rect keeps the screen's height from the box's top, moved down if needed to keep
  block 1 whole (rare: block 2 starting higher than block 1), so the bottom of block 2
  goes off.
- **Fallback: the stack** (the pair wider than the screen: a small window, a large UI
  scale; chosen again at each refresh, so a resize switches within a second): block 1 on
  top, block 2 under it, both at the larger natural width, 4 px apart; owner in the lower
  half, block 2 4 px over the owner and block 1 on it. Block 2 is the one anchored to the
  owner (below: lower by block 1's height + 8) and block 1 hangs on block 2's `TOP`;
  block 2's clamp rect reaches over block 1, so a stack that does not fit on its side
  moves as one piece (covering the owner) instead of the screen clamp pushing one block
  onto the other (review fix: each frame was clamped alone). Taller than the whole
  screen: the clamp rect leaves out the excess at block 2's bottom, so block 1 stays whole
  at the top.
- **Anchors**: without Shift, block 1 alone is placed as before. The anchors are set
  after the blocks are shown, and again only when block 2 comes or goes, the owner or the
  layout changes, or (side by side) block 1's width, a height or `d` changes, (stacked) a
  height changes; both cleared first (no circular anchor). No OnUpdate; measured: 0.0 KB
  over 500 refreshes, side by side and stacked, both kinds of theme.
- **Lifecycle**: `MODIFIER_STATE_CHANGED` and TICK redraw both; whatever hides block 1
  (leaving, the owner gone, a theme change, the GameTooltip taken by another owner) hides
  block 2. Every owner of `Tooltip.ShowFor` gets the pair (bar, mini display, minimap
  button, addon compartment); Broker.lua is unchanged (one tooltip, both labels).
- **Cost**: a refresh of both creates no frame, font or table and sets no unchanged text;
  about 3 KB more resident on Lua 5.5.
- **Breakdown bars in the Classic theme** (SPEC-themes 4.1, 4.3, 4.4, 4.5): each native
  block's breakdown line carries the label alone (its right text a space), every part on
  the continuation lines under it, right-aligned, as many a line as before; a bar stands
  beside the label, from 8 px right of its text to the line's right text edge (the
  client's `<name>TextRight<i>`, looked up and cached like the left texts), read from the
  two texts' positions right after placing. `Tooltip.Fill` takes a 6th argument, `bar`,
  passed only by `ShowFor`'s native blocks (Broker, `/tpl` and the private frames: text as
  before, no bar). The bars are `TooltipFrame.lua`'s: `TF.Bar(i, parent)` (bar 1 an
  anonymous frame of `UIParent` over the shared GameTooltip, at its scale; bar 2 a child
  of `TruePlayedCharTooltip`; strata TOOLTIP, frame level the block's + 2, mouse off,
  created once), `TF.PlaceBar` and `TF.HideBar`; a dark outline filling the frame and up
  to 8 segments 1 px inside, placed by the same `PlaceSegs` as the frames' gauges (largest
  first, 0 % parts absent, cumulative rounding, change-only). Look: `Themes.CLASSIC_GAUGE`
  (min 80 px, h 6, gap 1, outline the classic background colour, the segment colours
  Futuriste's: the spec gave none for Classic; to be confirmed by the author). A bar
  under 80 px widens its block (`SetMinimumWidth`, padding learned as for the stack;
  block 1's minimum dropped like the stack's), the pair then shown and placed once more in
  that redraw. Nothing is added to the shared GameTooltip (no region, child, field or
  script); its one hook stays `OnHide`, now `OnBlock1Hide` (the minimum width and bar 1),
  set once at the first minimum width or bar. Bar 1 also hides when the pair hides, when a
  refresh finds another owner, on a theme change and on a fill without breakdown; bar 2
  with block 2. GameTooltip hidden by its own OnShow during our show (the client in
  gamepad mode, a tooltip addon hiding it in combat; found in review): block 1 is not
  widened, block 2 not shown and the bars not placed, so bar 1 never stays alone on the
  screen and no minimum width is left for the next owner; the next refresh lets go. The side-by-side shift still uses the label's line. No OnUpdate, no new
  global; measured 0.000 KB over 500 refreshes (side by side and stacked, both kinds of
  theme), the bars untouched on steady refreshes. The stub lays out the right texts of a
  named GameTooltip's double lines (`<name>TextRight<i>`, right-aligned 10 px in, not
  counted as the addon's regions).
- **Tests, first version (stacked)**: `test_tooltip_theme` (9 new: block 2 with Shift
  only, one width, stacked below and above for both kinds of theme, Shift press and
  release without re-anchoring on each tick, the footer on the last block (the minimap button's hint too), block 1 the wider,
  the native minimum width with and without padding, hiding hides both, the per-tick
  refresh of both without frame, font or allocation, a theme change re-skins both, Broker
  unchanged, the native second GameTooltip created once); content parity (block 1 + block
  2 = the one tooltip minus the blank line that opened the character section), fonts and
  the theme cycle cover block 2; `test_tokens`, `test_actuel_golden` (block 1 then block 2
  lines, the stack anchored on the bar), `test_round4_regress` (cuts, crash notes and
  separators on both blocks), `test_locales`, `test_theme_integration`, `test_minimap`;
  `render_snapshot` writes block 2 too. Review fixes: a stack that does not fit moves as
  one piece (futuriste, pixel, Classic; the default bar too), one taller than the screen
  keeps block 1 whole on top, a block that changes height places the stack again, the
  native minimum width goes with GameTooltip's hide and is never reset under another
  owner. The stub knows `GameTooltipTemplate`, sizes a GameTooltip from its lines at
  `Show`, has `SetMinimumWidth` / `GetMinimumWidth`, and clamps to the screen the frames
  that ask for it (every GameTooltip), with `SetClampRectInsets`, the frames anchored to
  them following.
  Mutations: 13 of 14 caught; the survivor drops the re-anchoring after a change of block
  2's owner, a real-client safety the stub cannot reproduce.
- **Tests, side by side** (757 in all, 0 failed, 0 skipped on Lua 5.5): `test_tooltip_theme`
  35 (7 new: side by side below and above the owner for both kinds of theme; the right
  and left edges and no room below or above move both blocks; a pair taller than the
  screen; a block that changes height (the read-only line, the pre-install note); block 1
  ending lower than block 2, block 2 starting higher (block 1 kept whole); a block
  without a breakdown aligns the tops; a screen too narrow stacks, then switches back as
  it widens; no allocation on the refresh, side by side and stacked, both kinds of theme).
  The earlier stack tests run on a 600 px wide screen; the 13-theme cycle checks the
  breakdown rows face each other. `test_locales` 19 (1 new: both labels in the 11
  locales, distinct and translated, the exact frFR text, both in Broker's tooltip); the
  cut checks of `test_locales` and `test_round4_regress` also check that a label does
  not touch its gauge. `test_tokens`, `test_dead`, `test_prof`, `test_ui_smoke`,
  `test_window_cols` and `test_actuel_golden` follow the new keys. Mutations: 15 of 16
  caught; the survivor drops the line-text cache, which Lua 5.5 cannot measure (it
  reuses known strings).
- **Tests, native bars** (765 in all, 0 failed, 0 skipped on Lua 5.5; `check_toc`,
  `check_encoding`, `lint51`, `check_globals` (121 globals read, unchanged) and
  `check_media` green): `test_tooltip_theme` 43 (8 new: the bars on both blocks (line
  layout, segments' order, colours, widths and 1 px inset, position, strata, level,
  parent, scale, no region at the second show); shown only with our tooltip (the client's
  hide, leaving, a foreign owner with or without a hide, no breakdown, Shift, a theme
  change; the bar follows the pair at the screen's right edge); nothing added to the
  shared GameTooltip (one OnHide hook, no script, field or region); the widening for a
  bar (block 1 and block 2), released like the stack's, alignment still exact; the same
  with `SetMinimumWidth` counting the padding or not; fractional client sizes, one pass a
  refresh; GameTooltip hidden by its own OnShow, side by side, stacked and alone; a
  breakdown of 10 parts: 8 segments filling the native bar and a frame theme's gauge).
  Adapted: "actuel uses GameTooltip" and "native: block 2" (new line layout),
  Broker (each label with its parts, no bar), the allocation test (both bars shown and
  untouched over 500 refreshes). `test_actuel_golden` merges the "Total breakdown" label
  line and its first continuation row back into the baseline's "Breakdown" line.
  Mutations: 19 of 20 caught; the survivor drops the half-pixel tolerance, which only
  avoids a needless widening. The review's fixes: 5 more mutations (the three OnShow
  checks, the 8-segment caps of the native bar and of the frames' gauge), all caught. The CurseForge scene generator still runs (Classic and
  Futuristic); no CurseForge image shows the Classic tooltip (its tooltip scenes are
  empty), so none was regenerated.
- **Known**: a tooltip addon that skins only `GameTooltip` leaves `TruePlayedCharTooltip`
  in the game's default look (Classic theme), and skins neither bar. Not checked in game
  yet: in the Classic theme, the line positions read right after placing (the stub
  cannot confirm the client gives them at once), hence the two breakdown lines at the
  same height and the bars' width (read late, a bar would first show at the next
  refresh, 1 s at most); an addon taking the shared GameTooltip over without hiding it
  leaves bar 1 until our next refresh (1 s at most; at once when the client hides it on
  the owner change; nothing faster is allowed: no OnUpdate, no second hook); the one
  width of the stacked GameTooltips on Forever. luacheck and Lua 5.1 run in CI only.

## Part U: an hour in town, the timer leaves capitals and inns to the rest mode (2026-10-09)
The author's in-game feedback on part B: "10 minutes in town is too quick, one can stay in
town a long time doing nothing: make it 60 minutes", and "with the capital or inn option
ticked, the regular interval should leave towns and inns out, else the two double up".
- **Threshold**: `C.AUTORELOAD_REST_MIN` = 3600 (was 600). The help texts take the
  minutes from it (`OPT_AUTORELOAD_REST_HOW_FMT` / `_ASK_FMT`: "after 60 minutes").
- **Timer with the rest option on** (`AutoReload.lua`): in a capital or an inn the tick
  acts only on the rest mode's own rule (`RestDue`: an arrival since this load and
  `C.AUTORELOAD_REST_MIN` unsaved), never on the timer; outside, the timer's prompt as
  before (direct clients too: outside a rest place the timer always asks). A shown prompt
  is also hidden at the tick the player enters a capital or an inn while the rest mode is
  on and not due there (the timer's prompt carried into town), asked again
  `C.AUTORELOAD_RETRY` s after, out of town; a prompt shown or kept there by the rest mode
  (due) stays. With the rest option off, nothing changed: the timer acts in town too.
- **Scheduling**: `dueG` unchanged (`loadStartG + min(REST_MIN, minutes * 60)`, both
  armed); once past it, a tick in town with only the timer due returns before any check
  (no `waitUntil`, no allocation), so the timer acts at the first tick outside; "Later"
  snoozes both modes as before; a settings change re-evaluates at once (ticking the rest
  option hides a timer prompt shown in town at the next tick, unticking it lets the timer
  act there again); a reload starts a new load (new `loadStartG`, no arrival), so the
  rule applies again from scratch, no loop. A player who logs in and stays in town is
  never reloaded with both on (no arrival, timer left to the rest mode): intended.
- **Help**: a new tooltip line after the timer's "how", `OPT_AUTORELOAD_TIMER_REST` (11
  locales; enUS "If the capital or inn option above is ticked too, the interval leaves
  capitals and inns to it and only acts elsewhere."), always shown.
- **Docs**: README (EN, FR), CHANGELOG [Unreleased], `docs/TEST-EN-JEU-fr.md` (a "first"
  subsection, the city step rebuilt around the hour, a new step "both options"),
  `docs/PUBLISHING-fr.md` (60 minutes).
- **Tests**: `test_autoreload` 26 (4 new: the hour in a capital and an inn, on both
  paths; both options on a direct client: nothing in town however long, the prompt
  outside and not in an instance, hidden entering a capital or an inn, Later then town,
  the rest mode's hour, the next load; the same on Forever, with the rest mode's prompt
  staying in town; rest off the timer still acts in town and ticking it hides the
  prompt, a direct client's inn countdown; plus an allocation phase "timer due in town"),
  each failing on the code before; the help line in both tooltip tests;
  `check_globals` reaches the rest mode's countdown after the hour. Mutations: 4 of 4
  caught (the hide in `WatchPrompt`, the timer gate in town, the arrival in `RestDue`,
  the hide of a due rest prompt).

## Part V: the watched reputation under the bar (user request, 2026-10-09)
The author's request: "add the reputation bar to follow (or not, the user's choice); it
needs something discreet under the experience bar".
- **Faction**: the game's watched one, the faction the player marks "Show as Experience
  Bar" in the game's Reputation panel. TruePlayed has no faction picker of its own.
- **Strip** (SPEC-themes 2.4, 2.8, 3.4 B8): 3 px high, as wide as the XP track, under it:
  the progress inside the current standing, in the standing's colour (the game's
  `FACTION_BAR_COLORS`, else a copy of the classic colours, `Rep.COLORS`), on a dim
  background (the theme's `ink` at 70 %, the track colour in actuel). Exalted: full, no
  numbers. No watched faction, or the option off: nothing at all, the layout of before
  to the pixel. Each theme places it with `bar.rep` (`off`, `h`, `clear`, `color`): the
  frame grows by `max(0, off + h + clear - gap)` (0 in shaman, 4 to 10 px elsewhere),
  the text row under the bar keeps its place against the frame's bottom. Nothing
  overlaps it but the soft halos under it and the ornaments at the track's ends: in
  pixel, priest, rogue, warlock and futuriste the strip passes under the fill-end marker
  (arrow, needle tab, tab, marker ink), whose bottom it never crosses, hence their 5 to
  10 px.
  The mini display has no strip (out of scope).
- **Data** (`Reputation.lua`, `ns.Rep`): `C_Reputation.GetWatchedFactionData()` (Forever
  and the modern engine) when it exists, else `GetWatchedFactionInfo()` (Classic Era).
  Every value is type-checked and tested with `Util.IsSecret`; a failed, secret or
  incomplete read, or thresholds that leave no room below Exalted, show nothing.
  Exalted is full even with unreadable thresholds. Renown (major factions) and
  friendships show nothing, without an error; a paragon faction is Exalted (full).
- **Updates**: events only, registered while `widget.rep` is on: `UPDATE_FACTION`,
  `FACTION_STANDING_CHANGED` (through the bus, which tolerates a client without it),
  `PLAYER_ENTERING_WORLD`, plus a post-hook (`hooksecurefunc`, once) on the game's
  watched-faction setters (`C_Reputation.SetWatchedFactionByIndex` / `ByID`, Era's
  `SetWatchedFactionIndex`; each one the client has, on its own: a `C_Reputation` with
  paragon functions only does not stop the hook on Era's global) for a change of faction
  in the panel. `REP_CHANGED` is sent
  only when something shown changed; Bar redraws the fill, or lays out again when the
  strip appears or goes. Nothing on `TICK`, no `OnUpdate`.
- **Option**: `widget.rep` (bool, account-wide, on by default: it shows only once the
  player watches a faction in the game), Options > Display, right after "Show the bar",
  with the circled "?" (SPEC-themes 5.6).
- **Tooltip** (SPEC-themes 4.4): one row in block 1 after the XP block, the faction's name
  as the label and "Friendly · 1,200 / 6,000 (20.0%)" as the value (the standing alone
  at Exalted). The spec's "Reputation" label was dropped: with it the row was too wide.
  A very long name is cut with "..." on the private frames; the value is never cut.
- **Locales**: 6 keys (`OPT_REP`, `OPT_REP_GAME_CHECK`, `OPT_REP_HELP_WHERE_FMT`,
  `OPT_REP_HELP_STRIP`, `OPT_REP_HELP_TIP`, `TT_REP_FMT`) and the 8 standings
  (`REP_STANDING_1..8`, used only when the client lacks `FACTION_STANDING_LABEL<n>`), in
  the 11 files.
- **Tests**: 785 pass (765 before, 20 new in `tests/test_reputation.lua`: no faction,
  progress and colour per standing, Exalted, invalid or secret data, retail kinds, the
  Era API (also next to a `C_Reputation` that holds only paragon functions: Era's setter
  still hooked), neither API, events and the hooked setters, a client without
  `FACTION_STANDING_CHANGED`, the option (default, repair), the options checkbox and its
  help, the place in all 13 themes (clear of the frame, of the fill-end marker and of the
  text row), the room per theme, a theme switch (and one while the strip is hidden:
  nothing of the old theme kept), bar style changes, the tooltip row (themed and
  Classic, Shift, Broker), the tick (no read, no draw, nothing allocated), and the row's
  widths in 12 themes x 11 languages x 7 standings). New stub `tests/stub_reputation.lua`
  (SPEC-themes 8.1); `check_globals` has a reputation scenario and allows the new
  globals; `test_theme_memory`'s after-login budgets rose by 25 KB (`Reputation.lua` is
  about 17 KB resident on 5.5). check_toc, check_encoding, lint51, check_globals and
  check_media pass; luacheck and Lua 5.1 run in CI only.
- **Previews**: `media-src/curseforge/scene.lua` takes `SCENE_REP=<reaction>[:<fraction>]`
  (and `SCENE_REP_NAME`) for previews only; without them it draws what it drew before,
  and no CurseForge image was regenerated.
- **Known**: `lua tests/run.lua theme_memory` run alone already failed before this part;
  it passes in the full suite.
- **Not checked in game yet**: the strip's look in each theme on the real client; that
  ticking or unticking "Show as Experience Bar" (or picking another faction) in the
  game's panel goes through the hooked setters on Forever, so the strip follows at once
  (otherwise it would follow only at the next reputation event); the client's
  `FACTION_STANDING_LABEL<n>` and `FACTION_BAR_COLORS` on Forever.
- **Retail branch (to do there)**: full support of the retail systems, today hidden or
  approximated here: renown (major factions: `C_MajorFactions`, the renown level and the
  progress inside it), friendships (`C_GossipInfo.GetFriendshipReputation`: its own ranks,
  thresholds and rank names) and paragon (`C_Reputation.IsFactionParagon` /
  `GetFactionParagonInfo`: the progress towards the next paragon reward instead of a full
  strip).

## Part V2: the reputation's details, rate, main bar mode and options page (user request, 2026-10-12)
The author's requests: hovering the reputation strip shows its details (the faction, its
value and maximum, every standing: reached, current, ahead); a reputation per hour and a
time to the next standing like the XP's; an option to swap the XP bar and the reputation
bar (at max level or not); a "Reputation" options category (show the strip, swap, the
faction to follow). Decisions taken with him (research of 2026-10-12): the faction is
chosen inside TruePlayed, per character, never through the game's setters; the swap is
account-wide, a mode (`widget.main`, `C.MAIN_MODES = { "xp", "rep" }`, room for PvP
later); `hideAtMax` never hides a bar that shows a reputation; the main track takes the
standing's colour; two bar tokens.
- **Faction** (`Reputation.lua`): `char.rep.id` (nil: the game's watched faction, the
  default "auto"); read with `C_Reputation.GetFactionDataByID` (Era:
  `GetFactionInfoByID`); unreadable: the game's watched faction instead, and the detailed
  tooltip says so (`TT_REP_FALLBACK`). The picker's list (`Rep.ListFactions()`) walks the
  game's list once per opening: collapsed headers expanded, read, collapsed again (as
  the player left them), inside `pcall`, the `UPDATE_FACTION` burst it causes ignored
  (busy flag), one read after it. `C_Reputation.SetWatchedFaction*` and the game's
  status bars are never touched.
- **Rate** (`Reputation.lua`, `char.rep = { id, f, v, e, n, s, t }`): the XP rate's rules
  (SPEC-FINAL): gains only (a positive change of the same faction's value between two
  reads; losses move the base, never counted; chat never parsed), the first read of a
  login is a base, another faction starts over (EMA zeroed, session gain 0), one EMA per
  exclusion mask (8) advanced by `Tracker`'s `AdvanceRate` (`Rep.Advance(dt, k)`,
  allocation-free), frozen past `C.XP_STALL` counted seconds without a gain (the AFK time
  not counted), `WARMUP_MIN` / `WARMUP_FULL` statuses, `Core.RepairChar` repairs the
  record, `ResetChar` keeps only `id`, `/tpl reset rate` and the options' button zero it,
  nothing is written in read-only mode.
- **Detailed tooltip** (SPEC-themes 4.x): on a hover region over the strip's gap (or
  over the track in the main mode), themed and Classic: the faction, the points to the
  next standing, the 8 standings (reached dimmed, current marked with its percent, ahead
  with their points and estimated time), reputation per hour, time to the next standing,
  the session's gain, the bar's hint (its clicks and drags act on the bar).
- **Main bar mode** (SPEC-themes 2.3, 2.4, B9): the track shows the reputation in the
  standing's colour (`Themes.SetFillOverride`, no `THEME_CHANGED`), the texts the faction,
  standing, points and percent, the strip under it the XP (none at max level); every
  theme; no faction: the XP bar.
- **Tokens**: `reph` ("Rep. 312/h", dimmed with `*` when frozen) and `rep_eta`
  ("Honored: 2h 10m", the standing dimmed at Exalted), not XP tokens (shown at max level).
- **Options** (`RepOptions.lua`, SPEC-themes 5.6): a "Reputation" subcategory (or a
  section of the main page without subcategories) with the strip checkbox (moved from
  Display, which keeps a pointer note), the main bar dropdown, the faction picker (a menu
  of the game's factions by header, scrolling; a cycling button without MenuUtil), a note
  and the rate's reset button, each control with its "?".
- **Locales**: 42 new keys in the 11 files; `OPT_REP_HELP_WHERE_FMT` and
  `OPT_REP_HELP_TIP` rewritten in the 11, `OPT_REP` in enUS ("followed"); the tooltip's
  marks are Latin-1 (`»`, `·`), CJK files use `>`.
- **Tests**: 812 pass (785 before: 26 new in `tests/test_rep_detail.lua`, 1 in
  `tests/test_locales.lua`: no row of the reputation tooltip cut, every theme and
  language and state; `test_reputation`'s options test follows the checkbox to the new
  page; `test_tokens` covers the two tokens, its allocation bound rose from 8 to 12 KB
  for 22 tokens; the options' widths test covers the new page). `check_globals` clicks
  every control of both pages and plays the picker, the rate, the tooltip and the main
  mode in every theme on both APIs, plus read-only mode. `test_theme_memory`'s
  after-login budgets rose by 85 KB (measured in the full suite: 1255.0 / 1379.7 KB on
  5.5).
- **Not checked in game yet**: `UPDATE_FACTION` after a gain and after the walk's
  expand / collapse; `GetFactionDataByID` for a faction under a collapsed header or never
  met; the game's panel left as it was (open, in combat, no `ADDON_ACTION_BLOCKED`); the
  values at Exalted (42 999 or 43 000) and the female standing labels in frFR; the
  subcategory under TruePlayed; how easy the strip is to hover; the main mode in the 13
  themes on the real client; the rate's realism (docs/TEST-EN-JEU-fr.md).

## Part W: PvP tracking on WoW Forever (user request, 2026-10-12)
The author's requests (scratchpad spec of 2026-10-12, his `/dump`s of the beta 1.60.1):
follow the honor (currency 1792: `quantity` / `maxQuantity`, 25 000 in the beta) and the
PvP rank (major faction 2800: `renownLevel` 0..14, points inside the rank and its
threshold, `weekNumber`, `currentWeekProgressiveMaxLevel`; no season in the beta:
`weekNumber` -1); a thin PvP strip the user fills with the honor or the rank, stacked under
the reputation's; a PvP main bar mode, with an automatic override in battlegrounds; honor
and rank points per hour over "PvP time" with a 15-minute pause; an alert at the honor
cap after the fight; a detailed PvP tooltip; seven tokens; a "PvP" options page; Classic
Era dormant. Only the two ids are constants (`C.PVP_HONOR_ID`, `C.PVP_RANK_FACTION`);
the cap, thresholds, rank count and week are read.
- **Data** (`Pvp.lua`, `ns.Pvp`): `C_CurrencyInfo.GetCurrencyInfo(1792)`,
  `C_MajorFactions.GetMajorFactionProgressionInfo(2800)` and
  `GetTotalReputationForRenownLevel` (season totals: the rank's total + its points; the
  week cap's total), `C_DateAndTime.GetSecondsUntilWeeklyReset`,
  `C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd`, `GetPVPSessionStats` /
  `GetPVPYesterdayStats` / `GetPVPLifetimeStats`, `IsInInstance`, `PVP_MATCH_COMPLETE`
  (winner against `UnitFactionGroup`: Horde 0, Alliance 1, anything else a draw) and
  `GetBattlefieldWinner` on `UPDATE_BATTLEFIELD_STATUS` as a fallback. Every read in
  `pcall`, every field through `Util.IsSecret` and a finite-number test. `C_PvP`'s score
  functions are never called (secret during a match), the chat is never parsed. Events
  (registered only where both APIs exist): `CURRENCY_DISPLAY_UPDATE`, `UPDATE_FACTION`,
  `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`,
  `PLAYER_PVP_KILLS_CHANGED`, `PVP_MATCH_COMPLETE`, `UPDATE_BATTLEFIELD_STATUS`.
- **Gains**: honor: `min(quantityChange, the quantity's rise)` (the payload when it is a
  number; an amount lost at the cap or an event sent twice never counts); rank: a rise of
  the season total. Spending, a lower total (new season) and the first read of a load
  take a new base. "No season": `weekNumber < 1`, or a weekly cap of 0 with no point:
  shown as such, nothing divided by it.
- **PvP time and the pause** (the author's 15-minute rule): `char.pvp.g` is the `time()`
  of the last honor or rank gain (so a reload or a logout keeps it). `Pvp.Advance(dt, k)`
  (Tracker's `AdvanceRate`, allocation-free) counts every second in a battleground or an
  arena, and in the open world only the part of `dt` before `g + C.PVP_IDLE` (900 s).
  Past it, outside a battleground: no decay, status `"paused"` (the bar's `STALL_MARK`,
  the tooltip's note), until the next gain. One EMA per exclusion mask for the honor
  (`he`) and one for the rank (`ke`), `settings.rateTau`, `WARMUP_MIN` / `WARMUP_FULL`
  like the XP. At the honor cap the honor rate is held (`"capped"`), the rank rate at the
  week's cap or the max rank. `/tpl reset rate` (`Core.ResetRate`) and the page's button
  (`Pvp.ResetRate`) zero both.
- **Record** (`char.pvp`, repaired field by field in `Core.RepairChar`, nothing written
  in read-only mode, wiped by `ResetChar`): `h` / `k` the bases, `g`, `c` (at the cap
  since), `a` (alert given for this reaching), `hk` (the last lifetime count), `he` /
  `ke` (8 masks each), `s` (the session's counters keyed to the session's `t0`: honor and
  rank points gained, the lifetime kills at its start, battlegrounds played, won and lost,
  their honor and seconds), `b` (the battleground in progress: its entry time, the
  session's honor then, its result; kept across a reload,
  dropped when it was left while logged out). The session counters start only once the
  session is known (`PLAYER_ENTERING_WORLD`), so a reload continues them.
- **Cap alert** (`pvp.capAlert`, default on): at the reaching, out of combat at once, else
  `PLAYER_REGEN_ENABLED` registered only while one is pending; `PlaySound(SOUNDKIT.
  RAID_WARNING or 8959, "Master")` and the addon's own small frame (the automatic reload's
  look, `PVP_ALERT_FMT`, OK). Once per reaching (`char.pvp.a`, so not again after a
  reload), armed again below the cap; the option off drops a pending one.
- **Bar** (SPEC-themes 2.4, B10): the PvP strip (`widget.pvp`, default `"off"`) in the
  reputation strip's geometry, 1 px under it when both show; the main mode
  (`widget.main = "pvp"`, `C.MAIN_MODES` gains `"pvp"`; `widget.pvpAuto`: battlegrounds
  only, never written to `widget.main`); the week cap's 2 px mark; split hover regions.
  `hideAtMax` never hides a bar that shows PvP.
- **Tooltip** (SPEC-themes 4.x, `Tooltip.FillPvp`): honor, rank, honorable kills,
  battlegrounds of the session; rank titles from the game's `PVP_RANK_<4+rank>_<0|1>`
  (`_FEMALE`), else "Rank N".
- **Tokens**: `honor`, `honor_h`, `honor_eta`, `rank`, `rank_h`, `rank_eta`, `hk_today`
  (`DEF.pvp`: not offered by the options where `Pvp.Available()` is false; dots there),
  not XP tokens (offered at max level).
- **Options** (`PvpOptions.lua`): a "PvP" subcategory after the reputation's (or a
  section after it on the single panel): `widget.pvp`, `widget.main` (the reputation
  page's dropdown offers PvP too), `widget.pvpAuto`, `pvp.capAlert`, the reset button,
  each with its "?"; Classic Era: `OPT_PVP_UNAVAILABLE` alone.
- **Locales**: 86 new keys in the 11 files (French: JcJ, Honneur, Rang, Victoires
  honorables, Plafond hebdo); `HELP_RESET` rewritten in the 11 (`/tpl reset rate` resets
  the XP, reputation and PvP rates).
- **Tests**: 851 pass (812 before: 22 new in `tests/test_pvp.lua`, the engine; 16 in
  `tests/test_pvp_ui.lua`, the bar, tooltip, tokens and page in every theme; 1 in
  `tests/test_locales.lua`: no row of the PvP tooltip cut, every theme, language and
  state; `test_tokens`, `test_mini` and the options' widths test cover the PvP tokens and
  page). New stub `tests/stub_pvp.lua` (the currency, major faction, season, weekly
  reset, kills and match APIs, battleground enter / leave, Era and none modes, `C_PvP`'s
  score functions erroring). `check_globals` plays three PvP scenarios (Forever's full
  flow, Era, read-only): 22 scenarios, 142 globals read. `test_theme_memory`'s
  after-login budgets rose by 110 KB (measured in the full suite: 1360.8 / 1485.4 KB on
  5.5; `Pvp.lua` is about 68 KB of compiled code, `PvpOptions.lua` 14 KB).
- **Known limits**: the cap mark shows only when the week's cap falls strictly inside the
  current rank (caps on a rank's start, the usual case, show none: removed in W2, it could
  never show with the game's whole-rank caps); a flush segment that
  holds a gain may count a few seconds before it; `RESET_RATE_DONE` / `OPT_RESET_RATE`
  (main page) still name the XP rate alone; retail honor levels are out of scope; in the
  PvP main mode the XP strip's part of the band keeps the general tooltip.
- **Not checked in game yet**: `quantityChange` at the cap; whether rank points send
  `UPDATE_FACTION` or `MAJOR_FACTION_RENOWN_LEVEL_CHANGED`; `PVP_MATCH_COMPLETE`'s
  `winner` values and `GetBattlefieldWinner` on Forever; the `PVP_RANK_*` global strings;
  `GetPVPLifetimeStats` right after a login; the two strips stacked in the 13 themes on
  the real client; the alert's sound and frame; the rank part once a season opens
  (docs/TEST-EN-JEU-fr.md).

## Part W2: the PvP review's findings (2026-10-12)

The review of part W (18 findings, 9 test gaps; `tests/test_pvp_review.lua` holds one test
per proved case, each failing before its fix) and the author's decisions:

- **Already fixed by the reputation review's pass** (shared code): the bar redrawn after a
  `PVP_CHANGED` that came while it was hidden (finding 1), the PvP tooltip hanging off the
  bar's frame (2), the texts derived from the XP colour following the fill (12), the
  CHANGELOG's place of the PvP section (17). Tests: "pvp review 1", "pvp hover regions",
  "pvp main mode: hidden by hideAtMax...", "pvp main mode, futuriste...".
- **Reads** (`Pvp.lua`): an empty read (honor 0 / 0 or not discovered; rank 0, no point,
  `maxLevel` 0) is no base and leaves an earlier read shown; `PLAYER_ENTERING_WORLD` at a
  login or a reload takes both bases again (3); `/tpl debug` prints both reads of a
  login (`PvP read`, `PvP world`, with `base 0|1`). Gains are the quantity's own rise,
  the event's `quantityChange` is no longer read (6). A new rank's event
  (`MAJOR_FACTION_RENOWN_LEVEL_CHANGED`) is shown only, `UPDATE_FACTION` counts; a lower
  season total in the same `weekNumber` and `GetCurrentArenaSeason()` is a transient read,
  ignored (5). "No season" only without any point (13).
- **Battlegrounds**: `p.b.i` keeps the instance id (`GetInstanceInfo`'s 8th value); a new
  id, or a loading screen inside a battleground once its match is over (not a login nor
  a reload), closes the game in progress and opens the next one (4). The result compares
  the winner with `GetBattlefieldArenaFaction()` (else the player's faction); arenas are
  PvP time, not battlegrounds of the session (15). The session's kills: the first real
  lifetime count less today's kills since the session began (test gap 9).
- **Resets**: on `TICK`, while something shows PvP, the weekly and daily countdowns
  (`C_DateAndTime`): a rise of more than an hour reads the rank again (once more 30 s
  later) or today's kills (9, 14); the PvP tooltip reads both when it opens
  (`Pvp.ReadAgain`). Two API calls a tick, nothing allocated.
- **Cap alert**: armed again only by a valid read below the cap (cap > 0); in read-only
  mode the alert shown stays in memory for the load (10).
- **Events** (16): the rank, place, kills and match events and `TICK` only while
  something shows PvP (the strip, `widget.main = "pvp"`, `widget.pvpAuto`, a PvP token in
  the bar's slots or the shown mini display's infos); `CURRENCY_DISPLAY_UPDATE` also
  while the cap alert is on. Turned on, the reads take new bases. Choice: an
  `UPDATE_FACTION` comes with every reputation gain; with nothing PvP shown the rates and
  the session's battlegrounds simply do not count.
- **Bar**: the dead cap mark is gone (`Pvp.CapFrac`, `BarSkin.CapMark`, `pvp.markX`: the
  game's caps are whole ranks); `Pvp.Week()`'s 6th value says the next rank is the week's
  cap, said by the main bar's right text (`PVP_NEXT_CAP_FMT`) and the tooltip
  (`TT_PVP_LAST_FMT`) (8). The PvP strip has its own region in the PvP main mode (7); a
  strip that would repeat the track is not drawn (11).
- **Wording**: `PFX_RANKH_FMT` "Rank pts %s" / "Pts de rang %s" (11 locales: never read
  as a rank number), French `TT_PVP_WEEK_CAP_FMT` "Plafond de la semaine %d" (18); the
  options' helps say the strip rule and that the XP takes the strip below the max level
  in the PvP (and reputation) main mode, in battlegrounds too (11); the weekly cap
  "marked" promise left README, CHANGELOG, `OPT_PVP_MAIN_HELP_WHAT` and the in-game sheet.
- **Not checked in game yet**: what the currency and the rank read at `PLAYER_LOGIN`;
  the order and values of the rank events at a new rank; whether the weekly reset sends
  an event; a battleground entered straight from another; `GetBattlefieldArenaFaction()`
  on Forever (docs/TEST-EN-JEU-fr.md, top section).

## Part X: the Levels tab as a histogram of the journey (user request, 2026-10-12)
The author's request: PvP time in the statistics, with a tooltip splitting battlegrounds
and world PvP; the flight time; and a rework of the Levels page ("60 levels at most: the
basics of every level at a glance, and a click shows everything about one level"). He
chose variant B of the mockups ("histogram of the journey") with the shared detail sheet
(scratchpad spec `spec-levels-chart.md`; mockup sources `Histogramme.dc.html`,
`LevelDetail.dc.html`).

**Scope (final).** The Levels tab of a **character** (current or another one) is the
histogram + detail sheet; the per-character levels table is gone (`BuildLevels`,
`LAYOUTS.levels`, the level row tooltip, the live level cells). The **account** view keeps
its table (`LAYOUTS.account`, `Stats.AccountLevelAverages`). Zones and Sessions are
unchanged. The tab id stays `levels` (`/tpl stats levels`, `STATS_TABS`, `HELP_STATS`).
The bar of level L is the time spent AT L, for L = 1 .. top - 1 with
`top = Util.MaxLevel()` (the time at the max level is a chip). Heights follow the user's
exclusion mask. Filters and the selection are module state, not settings: every
`Window.Show` selects the viewed character's current level and the filter "all"
(the "hide upcoming levels" toggle is kept for the load). While the chart shows, the
window is at least 1040 x 640 (`C.DEFAULTS.window` unchanged; review fix chartrt-4: at
most the screen less 20 px, never below 700 x 300).

### Data
- **World PvP per level** (`Pvp.lua`): open-world time BETWEEN two world PvP signals less
  than `C.PVP_IDLE` (900 s) apart, counted afterwards (a lone kill counts 0, the tail
  after the last fight never counts). A signal: a rise of the honor quantity, or of
  today's honorable kills (`GetPVPSessionStats`: it goes on at the honor cap), read while
  not in a battleground or an arena (`IsInInstance` read again on the event). State in
  `char.pvp`: `wg` (time() of the last signal), `wp` (`{ [level] = seconds }` pending,
  created by `Record()` and `RepairPvp`, reused with `wipe`), `w0` (when measuring began
  for this character, set once by `Pvp.Refresh`). `Pvp.Advance(dt, k, lvl)` (Tracker's
  `AdvanceRate` passes `seg.level`; `ReleaseHold` goes through it) adds the part of the
  segment clipped to `[wg, wg + IDLE]` to `wp[lvl]` when `k == "w"`, and drops `wp` once
  `wg` is IDLE old. A signal less than IDLE after `wg` commits `wp` (rounded per level)
  through `Tracker.AddLevelStat("pw", n, level)`. `CURRENCY_DISPLAY_UPDATE` and
  `PLAYER_PVP_KILLS_CHANGED` are now registered whenever the APIs exist (`WORLD_EVENTS`),
  whatever the bar shows; with nothing shown and the alert off they read, take bases,
  count the gains and signal, but send no `PVP_CHANGED` (`subCur`). The rank, place and
  match events and `TICK` still need `Wanted()`.
- **`Tracker.AddLevelStat(f, n, lvl)`** (a field function: Tracker.lua stays at 198
  main-chunk locals): adds `n` to `life[f]`, `levels[lvl][f]` and the same fields of the
  delta (`ReplayDelta` replays them through `Util.AddInto`). Nothing before Start, in
  read-only mode, without a char / life / delta, or when `n` is not a finite number > 0.
- **Core.lua**: `Util.MaxLevel()` (`GetMaxLevelForPlayerExpansion`, else
  `GetMaxPlayerLevel`, both guarded and >= 1, else `#C.CLASSIC_XP + 1`; floored; no other
  hard-coded 60). `RepairPW` keeps `pw` on life and levels only as a finite number >= 0
  (no default: `LEVEL_FIELDS` / `LIFE_FIELDS` and the NewLevel / NewLife deep-equality
  tests unchanged). `RepairPvp`: `wg`, `w0` numbers >= 0 or nil; `wp` a table of whole
  levels >= 1 to finite seconds >= 0 (recreated when missing).
- **Stats.lua** (pure, field functions): `LevelSegments(bucket, mask, out)` (no alloc;
  world = w - pw', wpvp = pw' = min(pw, s.w), dungeon, raid, bg, taxi (t, plus T when the
  mask includes it: review fix, AFK on a taxi is flight), prof, dead, city, inn, afk = the
  other uppercase keys included by the mask, untracked, total; the parts sum to
  `Stats.Sum` under every mask; a level record or `char.life`);
  `LevelBattlegrounds(char, L, mask, out)` / `LifeBattlegrounds(char, mask, out)` (alloc:
  rows `{ key, name, secs }` merged by name, sorted by secs then name, and `other` = the
  battleground part less the rows); `WorldPvpState(char, L)` ("yes" / "partial" / "no");
  `XPOf(char, db, l)` (the level's size, else `db.xpMax`, else `C.CLASSIC_XP` scaled by
  the mean ratio of the known sizes that contradict it); `FutureLevels(char, db, mask,
  info, out)` (no alloc once warm: status "ok" / "estimate" / "nodata" / "max" / "cap",
  `src`, `cur`, `out[l]`, `total`, `top`, `n`, `missing`; K = sum(time_l) /
  sum(XPOf(l) / (45 + 5 l)) over the last `C.RECENT_LEVELS` complete levels, at least 2
  samples, else the XP rate fallback); `LevelHistory` rows gain `pw`, `xa`, `xq`, `xr`,
  `max`, `stall`.

### UI
- **`LevelChart.lua`** (`ns.LevelChart`, new, listed in both TOCs right after Window.lua,
  and in `tests/check_toc.lua`'s after-the-themes order): seven chips across the whole
  root (Played, Server /played, Average per level, PvP with its tooltip, Flight, Deaths,
  "Level <top> in" / max level / server cap), the title and summary, seven filter pills
  (a second row when a language needs it) and the hide-upcoming toggle, the plot (y axis
  in `AXIS_W` = 58 px, level numbers, one column per level with its stacked segments,
  ghosts, 2 px stubs, the selection frame, the current level's accent top line, the
  average line on a Graph-style stalk), one hit Button per column (bar tooltip, click
  selects), the progress strip. Lazy and pooled; a second Build creates nothing; live
  growth is SetHeight only; Live is allocation-free (keys from `Fmt.DurationKey` /
  `ETAKey`). It also owns the one-shot tooltip helper shared with LevelDetail
  (`TipBegin` / `TipRow` / `TipSep` / `TipShow` / `TipHide` / `Owns`: TooltipFrame frame 1
  under a non-native theme, else the GameTooltip; nothing of the palette kept after
  TipShow, P5).
- **`LevelDetail.lua`** (`ns.LevelDetail`, new, after LevelChart.lua): the 400 px sheet
  (BackdropTemplate panel, `UIPanelScrollFrameTemplate`, one content frame): header,
  status and approximation notes, six figure cards (2 x 3), "Time breakdown" (10 px bar
  chained by cumulative rounding, rows longest first, Flight always listed, the PvP row's
  hover tooltip through LevelChart's helper), "Experience" (mobs / quests and other /
  rested), "Zones and instances", the upcoming-level box, the no-record line. Every
  region has one cached TOPLEFT anchor: a rebuild of the same sheet makes no SetPoint.
  Live updates the Played, Server, Total and estimate cards and the breakdown's total of
  the current level only (review fix detailrt-2: the breakdown's rows, bar and percents
  and the Deaths card too; the notes, the XP split and the zones at the next rebuild).
- **`Window.lua`**: `LAYOUTS.chart = Layout({})` with its minimum size; `LayOut` honours
  `layout.minW` / `minH` (frame size and resize bounds, bounds key = width * 100000 +
  height); Refresh's chart path (scroll hidden, `LevelChart.Build`), every other tab or
  view `scroll:Show()` + `LevelChart.Hide()`; `UpdateLiveCells` -> `LevelChart.Live`;
  `ApplyTheme` -> both `ApplyTheme`; `Show` -> `LevelChart.Reset`; `Deactivate` and
  `OnThemeChanged` hide the chart's tooltip ("colors" does no window work). Removed:
  `APPROX`, `TIP_ZONES`, `rowTip`, `tipZoneRows`, `liveCumKey` and the `liveLevel*`
  state, `TimeText`, `BuildLevels`, `OnRowEnter` / `OnRowLeave` (table rows no longer
  take the mouse). Window.lua went from 1417 to 1320 lines and from 195 to 181 active
  main-chunk locals (`luac -l -l`); LevelChart.lua has 176, LevelDetail.lua 165.
- **Locales** (11 files, real translations): 80 keys `LV_*` (chart) and `LD_*` (sheet);
  16 unused keys removed (`COL_ETA`, `COL_CUM`, `COL_SERVER`, `COL_INN`, `COL_CITY`,
  `COL_MAIN_ZONE`, their `_TIP`, `COL_TIME_TIP`, `COL_XPH_TIP`, `COL_REACHED_TIP`,
  `ROW_ZONES_FMT`); `LEVELS_HOVER_HINT` is now "Click a bar to see the level's detail."
  (630 -> 694 keys per file; 700 after the review fixes). Shortened after the real-font width tests: `LV_DEAD_SUB_FMT`
  in ru / it / es / esMX / pt, deDE `LD_XP_QUESTS` ("Quests und mehr"), itIT
  `TT_UNTRACKED` ("Pre-installazione / non tracciato", shared with the main tooltip),
  ptBR `LD_MORE_FMT` / `LD_LESS_FMT` ("%s acima / abaixo do previsto").

### Decisions beyond the spec (from the three implementation reports)
- **Pvp**: the world part is clipped to `[wg, wg + IDLE]`, not only before `wg + IDLE`
  (a reload hold or the last second before the signal is not between two signals);
  `WorldSignal` checks `t - wg < IDLE` again (a frozen client drops segments, so seconds
  may stay pending past the window); no `Tracker.Flush()` on a signal (time() has 1 s
  resolution); the kills signal takes the first read above 0 of a load as a base (`hkBased`;
  a 0 read is no base) and a drop (daily reset) as a new base; `PVP_CHANGED` on an honor event only while the
  honor is shown or the alert is on.
- **Stats**: a numeric battleground zone is kept only when (p + P) x 2 >= its whole time
  less x (an open-world zone or a capital that got a tick of "p" while zoning goes to
  `other`); a merged row keeps the key of its larger part; `WorldPvpState` says "no" for a
  rebuilt (`rec`) level and an end equal to w0, "partial" for an unknown t0; `FutureLevels`
  samples [level - 5, level - 1], checks the cap before the max, accepts `info.isMax`,
  `info.sync` / `info.now`, counts levels without an XP size in `out.missing`;
  `row.pw` / `wpvp` are 0 when pw is absent: "not measured" comes from `WorldPvpState`
  and `ns.Pvp.Available()`, never from `pw == 0`.
- **Chart**: the chips span the whole root width; pills wrap; the title uses the body
  font (Orbitron substitutes the "»" of `LEVEL_SPAN_FMT`); ghost top line in `ui.dim`
  (alpha 0.9; `ui.border` is near invisible on dark themes); at max level the default
  selection is the last bar; the current bar's server excess (`Stats.LevelTime` less the
  local parts) goes to "untracked"; `COL_REACHED` / `ROW_IN_PROGRESS` reused; two keys
  not in the spec (`LV_WPVP_NONE`, no w0 yet; `LV_PVP_TIP_FMT`); `AXIS_W` 58 instead of
  40 ("2 h 30 min", ruRU, koKR); a chip sub line that does not fit shows its durations by
  their largest unit (`SubFit` / `Compact`, `LV_DAYS_FMT`), measured only on a rebuild or
  a key change; instance AFK (D, R) is in the AFK part, so the Instances filter shows
  dungeon + raid without their AFK; Live rebuilds the chart when the projection class
  changes; `Stub.FILES` (tests/wowstub.lua) not edited, the TOCs are read; the PvP chip's
  battleground rows are read with AFK left out (`C.MASK_AFK` set), like the sheet's.
- **Sheet**: body font for the title too (`Themes.DISPLAY_KEYS`); notes in `ui.dim`;
  the XP split in the theme's XP colour (not the user's), the gauge city colour and the
  theme's rested colour; more / less than expected in `C.COLORS.warn` / `good`, shown
  from 60 s and only for a level neither partial nor rebuilt; the level in progress with
  a projection shows "Level estimate" instead of its own `row.eta`; "~" on Played for
  partial, rec, estF > 0 or gap > 0 (a stall is a note only); rows of at least 1 s,
  longest first, stable on ties; Flight always listed (a dash); battleground rows without
  AFK, beyond 10 folded into "Other battlegrounds" (from 60 s); zones without instance
  keys (8 at most), then `TopInstances` (5 at most); "Reached in" = the time left in the
  current level plus the estimates up to the selected one; the scroll goes back to the
  top only when the level, character or kind changes; `WrapHeight` =
  max(GetStringHeight, ceil(unbounded width / 348) x (size + 2)).

### Tests
- New: `tests/test_world_pvp.lua` (16), `tests/test_levels_data.lua` (13),
  `tests/test_level_chart.lua` (20, with an ASCII rasteriser golden of a small fixed
  data set), `tests/test_level_detail.lua` (15), all registered in `tests/run.lua`; a
  width test in `tests/test_locales.lua` ("widths: the Levels chart (chips, filters,
  titles, axis, strip, detail, tooltips) in every language and theme": 11 languages x
  actuel, futuriste, pixel, warlock, real fonts). Every new data test was
  mutation-checked.
- `tests/check_globals.lua`: the window scenario hovers and clicks every bar under every
  filter, toggles hide-upcoming twice, hovers the PvP chip, adds a battleground and world
  PvP to the viewed level and hovers the sheet's PvP row, for the current and another
  character, then shows the account view.
- Totals (Lua 5.5): 884 before the lot, 952 after (68 more), 981 after the review fixes
  (29 more), 0 failed, 0 skipped.
- `tests/test_theme_memory.lua`: the after-login budgets rose by 190 KB: data +30, then
  the chart, the sheet and the review fixes +160 together (measured +93.2, +56.6 and
  +8.9). Lua 5.5 1380 -> 1570 (actuel) and 1510 -> 1700 (futuriste), measured 1548.4 /
  1673.3 KB in the full suite, the margin of the earlier lots (about 20 / 25 KB; review
  finding tests-memory-budget: a first setting of 1580 / 1710 left about twice that);
  Lua 5.4 1480 -> 1670 and 1620 -> 1810 (not measured: no 5.4 here).

### Legacy tests ported or adapted (none weakened, none removed)
A test of the removed table is ported to the new view with the same intent.
1. `test_pvp.lua` "pvp record: kept across a reload (new bases), repaired, reset with
   every rate, wiped by ResetChar": the three deep-compares of `rec.pvp` after
   `Core.RepairChar` also expect `wp = {}` (RepairPvp recreates the pending map; stricter).
2. `test_pvp_review.lua` "pvp review 16", block "nothing shows PvP, no alert": it asserted
   that neither the rank nor the honor is read. Now (the statistics window always shows
   world PvP): the rank is not read (no `UPDATE_FACTION`), the honor is read exactly
   once by its own event, today's kills by theirs, the place is not followed (`InBG`
   false inside the battleground, asserted before `LeaveBG`: review fix
   tests-pvp-review16-inbg), no session battleground, no PvP work on `TICK` (a counter
   on `GetSecondsUntilWeeklyReset`: 0 calls over 60 ticks), no `PVP_CHANGED` (a message
   counter). Argued comment in the test; the rest of it unchanged.
3. `test_window_cols.lua` "a column empty for every row of the view is not shown...":
   Levels has no table column or header cell; the parts appear in the bar tooltip only
   once used, in the chart's order, still no instance part; Sessions and Zones unchanged.
4. `test_window_cols.lua` "level rows read 'L » L+1'...", renamed "level bars read 'Level
   L » L+1', Reached = the next level, Total = time from level 1": the bar tooltip
   titles (12, 11, 10), Reached = the next level's t0 or "in progress", the bar's own
   time; Total became the strip legend `LV_DONE_FMT(11, CumulativeTime(11))` and the
   Played chip (live after 240 s); account rows unchanged.
5. `test_window_cols.lua` "the Est. column sits next to the time it took", renamed "the
   Est. card sits next to the time it took": the "Estimated at start" card sits in the
   Played card's column right below it (same x, one card height + 8 px lower), label
   `LD_ETA`, `tp.detail.eta` = Duration(levels[11].eta), Played = the level's time; one
   more level-up (level 11 was the level in progress, which now shows its projection).
6. `test_window_cols.lua` "dates follow window.dateFmt and window.clock": the Reached date
   of the bar tooltip and the sheet's "Completed on <date>" follow the settings, and the
   shown sheet refreshes; the Sessions part unchanged.
7. `test_window_cols.lua` "resized with the grip...": the table checks run on Zones (its
   zone column takes the room); added: the chart minimum 1040 x 640 with the setting
   unchanged, a save from the chart (1100 x 700, the root follows), clamping by the
   settings (700 x 300) while the frame stays 1040 x 640, Zones back to the saved size.
8. `test_window_cols.lua` "every column header has a help icon...": the chart has no
   header (0 icons); the optional columns are checked on Sessions (xp, xph, afk, dead,
   prof); the `COL_XPH_TIP` / `COL_TIME_TIP` asserts dropped with their keys.
9. `test_window_cols.lua` "a hovered header follows its column...": starts on Sessions;
   the last Sessions header goes when the chart shows; a header's leave does not hide a
   bar tooltip, the bar's own leave does. "the help icons follow the theme": on Zones.
10. `test_ui_smoke.lua` "live cells update while shown, nothing while hidden": the strip's
    "Level N in progress" text is refreshed (counted) and the Played chip is current;
    nothing refreshed while hidden.
11. `test_ui_smoke.lua` "a level's rebuilt mark and tooltip line follow the exclusions":
    the "~" of the bar tooltip's Played line: ~8000, then 6000 without a mark with AFK
    excluded, then ~6000 for an older record. New "a level's rebuilt note in the detail
    sheet follows the exclusions" (the row tooltip's `ROW_EST_TIP_FMT` line became a note
    of the sheet): bar 29 clicked, the note reads 2000, nothing with AFK excluded, 1500
    for an older record; the Played card's "~" follows too.
12. `test_ui_smoke.lua` "hovering a level row lists that level's zones...": the hint's new
    text, the bar title and the click hint, no zone list in the bar tooltip, a click
    shows the sheet's title, no hint in the account view or on Zones, account rows have
    no OnEnter. New "the detail sheet lists the selected level's zones, exclusions
    applied": Tanaris 8000, "Orgrimmar (city)" 700, a dash and last with `exclude.city`;
    rows read as `zones[1..nZones]`, each checked shown (the pool keeps the texts of
    hidden rows); the current view shows at least one zone and none of the other record.
13. `test_ui_smoke.lua` "Levels and Sessions tabs have an instance column, under the
    exclusions": the bar tooltip's Dungeon part 3000 and AFK part 300; the Instances
    filter totals 3000 for level 29 and 0 for 30, unchanged by excluding AFK, while the
    "All" bar loses the 300 s (instance AFK is in the AFK part); Sessions and account
    unchanged; the old main-zone and "3300, 3000 without AFK" checks live in the sheet:
    Tanaris first, "Ragefire Chasm (dungeon)" 3000 with AFK excluded, 3300 included.
14. `test_levels_extra.lua` "Dead (time and deaths) and Est. columns...": the bar
    tooltip's Dead part 310 s with its share, deaths "2", nothing at 11; bars side by side
    in the plot; a character without deaths: width 1040, no Dead part, Zones 700; the
    Deaths card: "2" with `LV_DEAD_SUB_FMT(Duration(310))` at 10, "0" with "none" at 11.
    New "the detail sheet shows the estimate made when the level began": `tp.detail.eta`
    = Eta(10) (the install level's first estimate) and Eta(11), dots without an estimate;
    one more level-up (see 5).
15. `test_levels_extra.lua` "deaths recorded before this version... count alone": the bar
    tooltip shows deaths "3" and no Dead part; the Deaths card "3" with an empty sub; the
    "no Est. column" assert dropped (there is no column).
16. `test_tooltip_theme.lua` 2405 "Window: futuriste backdrop, title font and cell
    colours; a switch while shown": the chip label and value roles, the chart title
    (accent) and the current-level marker (accent); headers and cells on Sessions;
    Classic repaints the chart, futuriste comes back.
17. `test_tooltip_theme.lua` 2448 "Window: under Classic the window is exactly the
    pre-theme one": `Snapshot(chrome)` leaves out, with an argued comment, the chart
    subtree, the table scroll's shown flag, the hint's text and the frame height (the
    content frame found through the scroll child when no row exists yet); checked apart:
    heights (baseline 440, levels 640, zones and sessions equal to the baseline), the
    hint's text, the scroll hidden on Levels and shown elsewhere (no hint, no chart), and
    the chart and sheet under Classic: body font on every text, every colour from the
    `C.COLORS` roles, the classic gauge colours (the world PvP mix), the theme's XP and
    rested colours (the XP split) and `C.COLORS.good` / `warn`, over more than 20 texts
    and 20 textures.
18. `test_locales.lua`: `LAYOUT_NAMES = { account, zones, sessions }`: 18 columns in 3
    layouts and 17 tooltip keys (were 32 in 4 and 26); asserts that `layouts.chart` has no
    column and `layouts.levels` is nil; `SAME_OK` + `LV_F_INST`, `LV_PART_FMT`,
    `LD_XP_FMT`, - `COL_SERVER`. The 332 px hint stays covered by "widths: the
    statistics window...".
19. `test_theme_memory.lua` "memory: the addon after login...": budgets raised (see
    Tests), with a header note per step.
20. Unchanged and passing: `test_round4_regress`, `test_language`, `test_tokens`,
    `test_actuel_golden` (`tests/baseline/` untouched).

### Docs and tools
- README: EN (features "Time per level", "Time per zone", "Instance time", "Statistics
  window"; a "World PvP per level" paragraph in the PvP section; the FAQ "How do I read the
  Levels tab?" rewritten, "What is 'Estimated at start' in a level's detail sheet?"
  replaces the Est. column's) and FR (an "Onglet Niveaux" paragraph, "JcJ sauvage par
  niveau").
- CHANGELOG [Unreleased]: the histogram, the detail sheet, PvP and flight at a glance,
  world PvP per level (Added), the Levels tab of a character (Changed), the PvP reads
  (the honor and today's kills always read), the rebuilt note now in the sheet (Fixed);
  "adds seven files" (since 1.1.0: AutoReload, Reputation, RepOptions, Pvp, PvpOptions,
  LevelChart, LevelDetail).
- docs/TEST-EN-JEU-fr.md: a new top section (the chart, the sheet, live growth, the
  window size, themes, world PvP with two kills less than 15 min apart); the PvP section
  became "À vérifier ensuite", its "nothing read" item says the honor is now always read.
- SPEC-themes 4.6 (the chart's and the sheet's theming) and 5.1 (the TOC list, with the
  [Unreleased] files).
- docs/curseforge-en.md / -fr.md (the statistics paragraph) and the regenerated
  `docs/curseforge-en.html` (`description-html.py`).
- `media-src/curseforge/scene.lua levels` now draws the chart: Forever's PvP API for that
  scene only, five kills in a row at level 16 that also kill a player (world PvP), level 16
  selected and its PvP row hovered (the themed tooltip frame exported; under `actuel` the
  GameTooltip's lines, right texts included, in `info.tip`). Every other scene's JSON is
  byte-identical to before (checked for the 13 scenarios in futuriste, actuel and heroic).
  **The PNG images were not regenerated**: `stats.png` still shows the 1.1.0 table, and
  `build-page.js stats` (Node + Playwright) needs a layout pass for the 1040 x 640 window
  before it is rebuilt (`media-src/curseforge/page/README.md` says so).

### Review fixes (2026-10-13)

The review of part X (7 lenses, 41 findings, each checked again by a verifier) and the
author's decisions. Every fix has a test that fails without it (mutation-checked in a
copy), except the luacheck ones (behaviour-neutral). Where the verifier corrected the
reviewer, the verifier's fix was applied.

- In-game report (2026-10-13): a battleground listed twice in "Zones and instances" of a
  level's sheet (its first seconds under the instance key "i<id>" before the map is known,
  the rest under its map). `Stats.TopInstances(zoneMap, mask, n, out, merge)`: with
  `merge`, the 2n longest rows are merged by name and kind (sums of secs, raw, afk, xp;
  the key of the longest part), sorted again, then the n longest kept; rows always carry
  `afk` and `xp`. Used by the sheet's instances and the Zones tab's instances block
  (Window.BuildInstances now reads r.raw / r.afk / r.xp); the sheet's "every instance key"
  set stays unmerged so that no key of an instance can be listed as a zone. Tests:
  test_stats "TopInstances: merge...", test_ui_smoke "window: the keys of one instance are
  one row...", test_level_detail "detail: a battleground under two keys..." (mutation:
  merge disabled -> all three fail).
- In-game report (2026-10-13), a Levels tab bar's tooltip under the Dead filter, theme
  futuriste: a missing glyph between "Level 30" and "31", and "Dead 5m · 4%" twice (the
  filter's accent line, then the part's row). Fixes, reviewed again (3 lenses, 5 findings
  confirmed, all fixed):
  - `TooltipFrame.lua`: `Shown(slot, s)` applies `Themes.Subst(slot[1], s)` to every row's
    left and right text (`row.lt` / `row.rt` keep the raw text, the cache key);
    `ApplyRowFonts` resets them so that a theme switch sets the texts again. Test
    (`test_tooltip_theme`) "themed frame: rows show their font's glyph replacements, set
    again after a theme switch".
  - `Themes.lua`: Orbitron replaces » with ">" and « with "<" (the addon's arrow, never a
    quote); `DISPLAY_KEYS` += `LEVEL_SPAN_FMT`, `LV_PVP_TIP_FMT`, `LD_PVP_TIP_FMT`. Tests
    (`test_theme`) "Subst: Orbitron and Macondo replacements..." and "FONTS: the 23 bundled
    fonts..." (22 keys). `check_media` checks the window's and the graph's titles
    (`WIN_TITLE`, `GRAPH_TITLE_FMT`, `GRAPH_WINDOW_*`) without `subst`, since they are drawn
    without it (a frFR "30\194\160s" now fails on Macondo).
  - `LevelChart.lua` OnColEnter: when only one of the filter's parts has time on the bar
    (`OnlyPart`: always so for world, flight, professions, dead; instances with dungeons
    only, PvP with battlegrounds only), the line under the title carries that part's label
    in its colour and the value in accent, and the part is not listed again; with two
    parts, the accent line and both rows. A non-zero share that rounds to 0 % reads "<1%"
    (`Share`, the sheet's rule). Tests (`test_level_chart`) "chart: a one-part filter's row
    moves under the title instead of coming twice" and "chart: a share under half a percent
    reads <1%, never 0%" (mutations: several parts taken as one, the empty part not
    skipped, "<1%" removed -> each fails).
- **World PvP and rates (`Pvp.lua`)**
  - pvpdata-1: `UpdateKills` takes today's kills as a base at the first read above 0
    of a load (a 0 read is no base): a 0 read at the login then the real count no
    longer opens a world window, nor commits the pending seconds of a quick relog. The
    header's "a lone signal commits nothing" and the known limit below are rewritten.
    Tests (`test_world_pvp`): "0 read at the login, then the real count...", "a quick
    relog with seconds pending...", "at 0 kills today the first kill is a base only...".
  - pvpdata-2: `Advance` decays the rank EMA (`p.ke`) only while rank gains are counted
    (`subUse`); the honor EMA is unchanged. Test (`test_pvp`) "pvp rates: nothing shows
    PvP: the rank EMA neither counts nor decays; shown, its real rate".
- **Data (`Stats.lua`, `Tracker.lua`, `Core.lua`)**
  - stats-afk-place-dropped-from-totals (the author's decision: AFK on a taxi is
    flight): `Stats.LevelSegments` taxi = t + T when the mask includes T, and T leaves
    the AFK part; the AFK of battlegrounds, dungeons and raids stays AFK; the parts still
    sum to `Stats.Sum` (masks 0..7). The chart's Flight chip, share and filter and the
    sheet's Flight and AFK rows follow with no code change. Tests (`test_levels_data`):
    "LevelSegments: a flight turned AFK is flight...", "LevelSegments: the parts sum..."
    (expectations updated).
  - stats-eta-verdict-mask-mismatch, and the mask part of detailrt-3 (its eta / (1 - p)
    correction was refuted and is not applied): `Tracker.CaptureLevelEta` stores
    `lb.etaM = ns.GetMask()` (a field write: Tracker.lua stays at 198 main-chunk
    locals), the late-swap merge of `ReplayDelta` carries it, `Core.RepairChar` keeps a
    whole number 0..7 (`LEVEL_OPTIONAL`, no default), `Stats.LevelHistory` rows carry
    `etaM`; `LevelDetail` `FillEta` gives the more / less verdict only when `etaM` is nil
    (an older record) or equals the current mask. Tests: `test_levels_extra` "eta: the
    mask it was taken under is stored (etaM)...", `test_level_detail` "detail: the
    estimate's verdict only under the exclusions it was taken with (etaM)".
- **Chart (`LevelChart.lua`, `Window.lua`)**
  - chartrt-1: `SubFit` measures with `GetUnboundedStringWidth` (else
    `GetStringWidth`). `tests/stub_ui.lua` gains an opt-in `boundedText` that bounds
    `GetStringWidth` as the client does (`tests/wowstub.lua` untouched); the width test
    reads the chips' sub lines from the module. Tests: "a chip's sub line too wide...",
    "widths: the Levels chart...".
  - chartrt-2: `Rescale` goes on beyond `STEPS` (20, 50, 100... days, at most
    `GRID_MAX` lines); `AxisText` writes whole days (`LV_DAYS_FMT`). Test "a level of 60
    days: steps in days beyond 10 days...".
  - chartrt-3: `OnGripUp` saves a dimension only when it changed since `OnGripDown`.
    Test "the grip saves only a dimension the user changed, never the chart's minimum".
  - chartrt-4: `LevelChart.MinSize()`: 1040 x 640 within `UIParent` less 20, never below
    700 x 300, read at every Refresh; the plot narrows, the sheet stays 400 px. Tests
    "on a 4:3 or 5:4 screen the window fits the screen..." and the width test's 4:3 runs.
  - ux-1 (chart part): `FillActivity` keeps the PvP, Flight and Deaths chips live
    (strings only on a key change, nothing allocated in steady state). Test "the PvP,
    Flight and Deaths chips follow live; nothing allocated while no key changes".
  - ux-2: under a filter, the bar tooltip's first line is the filter's label, the bar's
    value and its share of the level, in the accent colour. Test "under a filter the bar
    tooltip first gives the bar's value and its share of the level".
  - ux-3: the strip's "left" uses the chip's `Fmt.ETA` text and key (`LV_LEFT_FMT` lost
    its "about" in the 11 locales). The strip test checks both.
  - ux-4: an empty summary reads `LV_SUM_NONE` ("No time recorded"), a few seconds
    alone `LD_TOTAL_FMT`. Test "an empty summary reads 'No time recorded'...".
  - ux-5: `LV_PLAYED_SUB_ONE` ("level 1") on the Played chip and the sheet's cumulative
    card. Test "a level-1 character reads 'level 1'...".
  - ux-7 / stats-flight-share-rounds-to-zero: a share above 0 and under 1 % reads "<1%"
    (`LV_LT_FMT`), on the Flight chip and on the sheet's rows. Tests "a flight share
    under 1 % reads '<1%', never '0%'", "detail: a breakdown row under 0.5 %...".
  - ux-9: the XP disabled below the top level (`S.xpOff`): chip `LV_XP_OFF`, strip
    `LV_XP_OFF_FMT`, no projection; Live rebuilds on a change of status. Test "XP
    disabled below the top level reads 'XP disabled', never 'max level'".
  - stats-capped-alt-projection: another character's `capLevel` (equal to its level)
    shows the cap. Test "another character at a recorded server cap shows the cap...".
  - stats-missing-xp-levels-dropped: with `FutureLevels`' `missing` > 0 the projection is
    a lower bound ("+") and the strip shows no share. Test "levels without an XP size
    make the projection a lower bound ('+'), no share".
  - ux-6 (refuted as a defect, taken as an improvement): the `LV_T_*` titles read as a
    time in the 11 locales ("Temps de vol par niveau", "Time dead or a ghost per
    level"); `SEG_LABEL[6]` is `LV_FLIGHT`, one flight label in the view. Test "the bar
    tooltip's flight part has the chip's label (frFR: Vol)".
  - static-5, static-7: see luacheck below.
- **Sheet (`LevelDetail.lua`)**
  - detailrt-1: every instance of the level is set aside before the zone list
    (`TopInstances(zmap, 0, ..., allInst)`); the 5 longest instances are listed, the
    others not at all (no "other instances" line). Test "detail: seven instances in a
    level: none listed as an open-world zone...".
  - detailrt-2 and ux-1 (sheet part): `DrawTime(total, force)` redraws the breakdown's
    total, rows (fixed slots), percents and bar from keys; `Lay` lays the sheet out
    again when a row appears or goes; the Deaths card is live (`DeathsCard`). Test
    "detail: the level in progress follows a flight, a battleground and a death live,
    as a rebuild" (nothing allocated while no key changes).
  - ux-8 / stats-upcoming-basis-text: `LD_EST_SUB_RATE` ("Based on your current XP per
    hour") when `FutureLevels`' `src` is "rate". Test "detail: an upcoming level's
    basis...".
  - `LD_STALL_FMT` without "(stalled)" / "(bloqué)" in the 11 locales: `test_locales`
    "the detail sheet's stall note is time without an XP gain...".
  - static-6: see luacheck below.
- **Test gaps**: tests-live-mask ("detail: live under exclusions (mask 7)...": the chart
  and the sheet, filtered and server times, the projection and a cap found live),
  tests-untracked-excess ("the current level's server time above its parts goes to
  untracked" on the chart, "... to the untracked row" on the sheet), tests-alt-no-w0
  ("another character without w0..."), tests-sel-reset-char ("switching to another
  character selects its current level"), tests-locales-vacuous-levels (the character
  Levels view asserts `layouts.chart` with n == 0; the header no longer lists inn, city
  and estimate columns), tests-pvp-review16-inbg (the "place not followed" assertion
  inside the battleground, before `LeaveBG`: a mutant that follows the place fails it
  now), tests-memory-budget (the budgets above: a resident mutant of 24 KB fails them,
  it passed 1580 / 1710).
- **luacheck** (CI fails on any warning; luacheck is not installed here, so the files
  were checked with an emulator calibrated on CI runs): static-1, -2, -3 (W581 in
  `PvpWorldOf`, `FutureLevels`, `AddLevelStat`: `-- luacheck: ignore 581 (NaN fails
  too)`, the repo's form, NaN behaviour unchanged), static-4 (W421, `today` in
  `UpdateKills`), static-5 (W311, `key` in `DrawStrip`), static-6 (W212, `FillCards`
  without `char`), static-7 and static-8 (tests), static-9 (8 sites from earlier lots:
  `Pvp.Rate`, `Reputation.lua`, `test_tooltip_theme`, `test_pvp_review`), static-10
  (`Bar.lua`, `Reputation.lua`, `test_pvp_review`). No trailing whitespace left.
- **Docs**: CHANGELOG [Unreleased] and README EN / FR (flight includes the AFK on a
  taxi unless AFK is excluded; today's kills from the first read above 0; the rank rate
  kept while nothing shows PvP; the live figures and sheet; the filter line of a bar's
  tooltip; the window within the screen; the estimate's verdict under its own
  exclusions; the upcoming level's basis); docs/TEST-EN-JEU-fr.md (new checks: the
  grip, a small screen, XP disabled, another character at the cap, the filter line,
  "No time recorded", "<1%", the strip's "+", the axis in days, the verdict and the
  exclusions, the 6th instance, the upcoming basis, the chips and the sheet live during
  a flight, a battleground and a death, a long flight turning AFK, a relog without a
  false world PvP signal).
- **Totals**: 952 -> 981 tests (Lua 5.5), 0 failed; 694 -> 700 locale keys
  (`LV_PLAYED_SUB_ONE`, `LV_LT_FMT`, `LV_XP_OFF`, `LV_XP_OFF_FMT`, `LV_SUM_NONE`,
  `LD_EST_SUB_RATE`; `LV_LEFT_FMT`, the `LV_T_*` titles and `LD_STALL_FMT` changed).

### Known limits, not checked in game yet
- Today's kills are based on the first read above 0 of a load (review fix pvpdata-1): a
  count of 0 read before the data is loaded, then the real count, is a base, not a signal
  (it used to open a world window at the login, and commit the pending seconds of a quick
  relog). The price: the first kill of the day of a character really at 0 is a base only
  (its honor is still a signal, unless capped). With nothing shown, `TICK` is not
  registered, so a daily reset without an event is noticed at the next kills event only
  (the first kill of a new day may then not be a signal; the honor still is, unless
  capped).
- A 5:4 screen (`UIParent` 960 wide, a 940 px window): the chart fits, but a probe of
  the real-font width test found a few extreme texts 1 to 7 px too wide, mostly in the
  pixel theme (de "125 T tot oder als Geist", fr "BG 125 j · sauvage 125 j"); 4:3 fits
  and is in the suite. Fitting 5:4 too would need two chip rows or a narrower sheet.
- The sheet's notes (the stall note), XP split and zones follow at the next rebuild (an
  XP gain), not live; an instance with no time under the current mask (only AFK, AFK
  excluded) is no longer listed at all.
- In game only: the window at 1040 x 640 on small screens and large UI scales; the
  sheet's scroll bar room (`SCROLL_W` 28 assumed for `UIPanelScrollFrameTemplate`); the
  wrapped heights of the notes and the no-record line; the PvP row's highlight and its
  tooltip anchor; the body font on the titles; the world PvP signals on Forever's real
  events (docs/TEST-EN-JEU-fr.md, top section).
- The 9 non-French translations of the 80 new keys were not reviewed by native speakers.
