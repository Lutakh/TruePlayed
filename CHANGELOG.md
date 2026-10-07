# Changelog

All notable changes to TruePlayed are listed here, newest first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
version numbers follow [Semantic Versioning](https://semver.org/).
Each version section becomes the release notes shown on CurseForge.

## [1.1.0] - 2026-10-07

**Quit the game and launch it again after updating** (a `/reload` is not enough): this
version adds four files, and the game loads new files only at start.

### Added

- **Time spent dead**: from your death until you are back on your feet (the ghost run
  included) is recorded apart, per level, session, zone, character and account. It is
  never counted as world, dungeon or any other place, and never excluded. The breakdown
  shows it ("Dead 2%", with its own colour in every theme), the Shift tooltip line reads
  "Deaths 3 (12m)", and the Levels and Sessions tabs have a "Dead" column (once there is
  something to show): the time dead and the deaths of each level or session, e.g.
  "5m (2)".
- **Professions time**: gathering (herbs, mining, skinning), fishing, first aid
  (bandages), crafting in a profession window (also Enchanting), disenchanting and
  lockpicking are recorded apart ("Prof." in the breakdown, "Professions" in the Shift
  tooltip, a "Prof." column in the Levels and Sessions tabs). Crafting in a capital counts as professions, not city; AFK still wins. See
  the README for how it is told apart and its limits.
- **Estimated time at the start of each level**: when a level begins, the time to level
  shown at that moment is kept with the level, to compare with the time it really took
  (Levels tab, "Est." column, right next to the time it took). Levels reached before this
  version have none.
- **Total time to each level** (Levels tab, "Total" column): the time from level 1 to each
  level-up, so you can see how long it took to reach level 10, 20... (your whole /played
  up to then, the time before TruePlayed included).
- **Date format of your choice** (Options > Statistics window): the format of your
  language, DD/MM/YYYY, MM/DD/YYYY or YYYY-MM-DD, with a 24-hour or 12-hour ("2:05 PM")
  clock. Every date of the statistics window ("Reached", Sessions) now has the year, the
  hours and the minutes.
- **Resizable statistics window**: drag its bottom-right corner; the size is kept. The
  window is always at least as wide as its columns need, in every language.
- **Minimap button**: a round TruePlayed button on the edge of the minimap. Hover it for
  the same tooltip as the bar (hold Shift for the details), right-click it for the bar's
  menu, drag it around the minimap. Its left click opens the statistics by default; it
  can open the options or show / hide the XP bar or the mini display instead. It can be
  locked or hidden (Options, the menu, `/tpl minimap`), and it works with the XP bar
  hidden.
- **Mini display** (off by default): a small movable frame with 1 to 3 infos of your
  choice from the bar's list (by default time to level + mobs to kill, and XP per hour),
  on one line or stacked, with the level percentage and / or a thin XP bar if you like.
  It uses the theme, text colour, outline and shadow of the XP bar, with its own
  background opacity, scale, lock, fade and hide in combat. Hover it for the tooltip,
  click it for the statistics, right-click it for the menu. `/tpl mini` or Options turn it
  on, with or without the XP bar.
- **Help on every column** of the statistics window: a small circled "?" next to each
  column header; hover the header to read what the column shows and how it is counted
  (for instance "Server" is the game's own /played for that level, which counts
  everything, while "Time" leaves out what you exclude).
- Options: a "Minimap button and mini display" section with all their settings.
- Right-click menu: a "Show" submenu turns the XP bar, the mini display and the minimap
  button on or off, from any of them; "Hide" hides the one you right-clicked.

### Changed

- **Levels tab**: each row is now a level step, "19 » 20" for the time spent at level 19
  until 20 (the level in progress reads "20 » 21"), the header says "Level", and
  "Reached" is the date the next level was reached. The same labels in the account view
  and in the hover tooltip of a row.
- **Statistics window**: a column that is empty for every row of the view (instances while
  leveling, inn, city, AFK, dead, professions, estimate...) is no longer shown, and the
  others are laid out again; the main zone column takes the room left.
- **Tooltip breakdown**: the parts are sorted from the largest to the smallest, in the
  legend and in the gauge.
- **Shift tooltip**: "Top zones" lists your top 3 zones over the whole character (it was
  the current level only). The overall average per level, the last levels, the account
  lines and the "rebuilt after crashes" total left the tooltip: the averages and the
  account totals (with the account instance time) are at the bottom of the statistics
  window, the level history in its Levels tab, and the rebuilt part stays as the note
  under the played time. The short tooltip keeps the average of your last 5 levels.
- Continents with less than a minute of time (a few seconds on a loading screen) are no
  longer listed in the tooltip and the Zones tab; their time is kept.
- Continents (tooltip and Zones tab): the "Instances" row is split into "Dungeons",
  "Raids" and "PvP", the names of the breakdown; each instance counts under its main kind.
- The "Other" continent row is gone (tooltip and Zones tab): it held the time the game
  did not place on a continent (mostly flights where it only gives the continent). That
  time still counts in every total and in its zone rows.
- The breakdown in the tooltip shows at most 4 parts per line once professions or dead
  time appear, so that the longer names fit.

### Fixed

- Zones tab, "Top capitals": the Time column was empty with the city excluded. It now
  shows the capital's time counted under your exclusions, like its row in the zone list
  (with the city excluded: the time spent there in flight, crafting or dead), and Raw its
  whole time.
- A theme font that fails to load while the game starts (seen at the first launch after
  an update, the file being fine) is no longer given up at once: the game font is used
  meanwhile, the font is tried again a few seconds after entering the world, and the
  theme fonts are applied again when it loads. Only a font that still fails is reported,
  once, in one chat line naming every file that failed.
- Zones tab, "Most played instances": a capital or a zone could be listed as a dungeon
  (e.g. "Undercity (dungeon)", with the XP of the whole city) because the game reports the
  instance a second before the map when you zone in. That second now goes to the
  instance, and a zone with only a few seconds of instance time is no longer listed.
- Instance names are shown in the language of your game client: they kept the language
  the game had when you played them.
- Time rebuilt after a crash or a disconnection no longer puts a few seconds in your most
  played dungeon at levels where you never entered it ("< 1m" in the Levels tab's
  "Inst." column): instance time is rebuilt only when you were last seen inside that
  instance. The seconds already recorded this way are moved to the level's main zone at
  the next login (only at levels where your sessions show no instance time).

## [1.0.1] - 2026-10-02

**Quit the game and launch it again after updating** (a `/reload` is not enough): this
version adds files (the new languages), and the game loads new files only at start.

### Added

- **TruePlayed speaks every language of the game**: Deutsch, Español (EU), Español (AL),
  Italiano, Português (BR), Русский, 한국어, 简体中文 and 繁體中文, besides English and
  Français. It follows your game's language by default; Options > Display > Language (or
  `/tpl lang de`, `es`, `mx`, `it`, `pt`...) picks another one, after a reload of the
  interface. Russian, Korean and Chinese are offered on a game client in that language
  only (the other clients' fonts cannot draw them). Corrections from native speakers are
  welcome.

### Changed

- French: the slot info "Temps avant le niveau + monstres à tuer" is now "Temps avant le
  niveau + monstres", so that it fits the options dropdown.

### Removed

- The **compact box** style of the bar (option, right-click menu entry and `/tpl style`):
  the XP bar is the only look. If you used the box, TruePlayed now shows the bar, with
  your other settings unchanged.

### Fixed

- Added a generic TruePlayed.toc alongside the Forever TOC to improve addon manager
  discovery. Both contain the same metadata and load order (interface 16001).

- The confirmation window of "Erase this character's data" now shows its buttons in the
  language of TruePlayed (they stayed in the game's language).
- When your saved data is read-only (written by a newer version of TruePlayed),
  `/tpl lang` and the language option now say the change cannot be saved, instead of
  confirming a language that would never apply.
- Mobs to kill: after WTFix (or another addon) restores an older copy of the saved data
  during a session, the average and the last kill now come from the same kills.

## [1.0.0] - 2026-10-01

First public release, for WoW Forever.

**Install it with the game closed, or restart the game completely after installing**
(quit and launch it again): the game loads new fonts, textures and files only at start.
After a `/reload` alone, theme textures can be missing and the theme fonts are replaced
by the game font (TruePlayed says so once in the chat).

### Added

- **Your real /played**: every played second is counted and split between the open
  world, dungeons, raids, PvP (battlegrounds and arenas), AFK, inns / rest areas, capital
  cities and flights, per level and per zone.
- **Instance time as a real statistic**, for levelers and max-level players alike: time
  in the tooltip (plus dungeons, raids and PvP each with their AFK part when you hold
  Shift, and the account total), a "Most played instances" block in the Zones tab (for
  the character or the whole account, each instance marked dungeon, raid or PvP), an
  instance column in the Levels and Sessions tabs, and two bar infos: instance time this
  session and in total. Time spent in instances before this version stays counted as
  open world.
- **13 themes** for the bar, its tooltip, the FPS graph and the statistics window, each
  with its own track, fill, ornaments, background panel, fonts, tooltip panel and
  palette: **Futuristic** (the default), **Classic**, **Heroic fantasy**, **Pixel (old
  school)**, and one per class: **Warrior**, **Paladin**, **Hunter**, **Rogue**,
  **Priest**, **Shaman**, **Mage**, **Warlock**, **Druid**. **Class (automatic)** gives
  each character the theme of its class. Choose it in Options > Display > **Theme** (the
  first setting), right-click the bar > **Theme**, or `/tpl theme <name>` (`/tpl theme`
  alone shows the current theme and the names); the change is immediate. 23 bundled fonts
  under the SIL Open Font License 1.1, with their licences in `Media/Fonts/LICENSES`
  (credits in the README).
- **Mobs to kill**: how many mobs like your last 10 kills (their average XP, without the
  rested bonus) you still need to level up, aware of your rested XP (rested kills give
  double XP). The average keeps the number steady when the mobs around you are not all
  of the same level. In the tooltip under the time to next level ("Mobs to kill: ~38
  (average: 47 XP, last: 30 XP)"), and on the bar: the top right info reads
  "~5h 05m · 38 mobs" by default (only the time when the bar is too narrow).
- **Rested XP like the game's XP bar**: the bar takes the rested colour while you are
  rested (the game's blue in the Classic theme), with a lighter part showing how far your
  rested XP goes; the tooltip shows "Rested: 11,600 XP (50%)".
- **Bar colours of your choice**: the XP bar colour and the rested colour (the bar while
  rested, and the lighter part showing your rested XP) through the game's colour picker,
  in Options > Bar colours, over any theme, with a "Theme colours" button back to the
  colours of the active theme.
- **Leave out AFK, inn or city time** whenever you like (right-click menu, options or
  `/tpl afk`, `/tpl inn`, `/tpl city`). Nothing is deleted: totals, level times,
  averages, XP per hour and time to level are recalculated instantly, and switching the
  option off brings the original numbers back.
- **XP per hour and time to next level**, aware of your rested XP. They survive
  `/reload`, a restart and even a game crash: no more "..." every time you log in.
  Right after installing, on a character that has already played, they start from an
  estimate based on your server /played (shown with a `~`, and named in the tooltip),
  then follow your own measured pace after about ten minutes of counted play.
- **No absurd numbers after hours without XP**: after 20 minutes of counted play without
  any XP (a level cap, a long break in town), XP per hour and the time to next level
  freeze at their last value, dimmed and marked with a `*`; the tooltip says for how long
  no XP came ("XP per hour frozen: no XP gained for 3h 05m of play"). That time is left
  out of the rate, and they move again with your next XP gain.
- **Temporary server level caps** (the WoW Forever beta stops characters at level 20 for
  now, and the game client does not know it): after 3 mobs in a row that should have
  given XP and gave none, the bar takes its max-level look and reads "LEVEL 20 · CAP", the
  tooltip says "Level 20: current server level cap (no XP from the last 3 mobs)", and
  `/tpl played` says so too. Everything goes back to normal by itself with the next XP
  gain, for example when the cap is raised. "Hide at max level" does not hide the bar at
  such a cap.
- **Time per level** with a full level history, and **average time per level** (overall,
  last 5 levels, and an account-wide average).
- **Time per zone** (Elwynn Forest, Stranglethorn Vale...): Zones tab, zones of each level
  (hover a level in the Levels tab), time in the current zone in the tooltip, your
  **time per continent** (Kalimdor, Eastern Kingdoms, instances: Zones tab and detailed
  tooltip) and your **most visited capitals**. Exclusions apply to zones too.
- **Session time**, total played time (filtered or not) and the live server /played.
- **A customisable XP bar**: three info slots to choose from 19 (time to level, mobs to
  kill, XP per hour, % of level per hour, XP to go, rested XP, level / session / total /
  zone / instance time, AFK time, average per level, FPS, latency...), bar or compact box
  style, size, scale, background opacity (0 % by default: the bar alone), hide in combat,
  fade, hide at max level. The level percentage shows one decimal, like the tooltip
  (never 100 % before the level-up). The texts never overlap, even on a narrow bar: the
  numbers get shorter first ("58 / 23.2k"), then the least useful text makes room.
- **Readable texts without a background**: a thin outline and a shadow by default
  (outline none / thin / thick and shadow in the options), and a **text colour** of your
  choice through the game's colour picker, with a "Theme colours" button back to the
  theme's.
- **FPS and latency** display, measured only while it is visible, in green / yellow / red
  (or in your text colour, option). **Hover it for a graph** of the last 30 s, 1 min or
  5 min (option) with min / average / max, and hover the graph to read the value at any
  moment. The game refreshes latency only about every 30 seconds, so it is drawn as steps.
- **Detailed tooltip** (hold Shift): rate details, top zones of the level, top capitals,
  last levels, inn / city / dungeon / raid / PvP / AFK / flight totals, deaths, account
  total. The breakdown line lists world, dungeons, raids, PvP, flight, AFK, inn and city,
  leaving out what you never did.
- **Statistics window** (`/tpl stats`): levels, zones and sessions tabs, per character or
  for the whole account; the header names the exclusions in use.
- **Crash recovery**: time lost in a crash (or played without the addon) is taken back
  from the server /played at the next login, split with your own habits, and marked as
  rebuilt. Its city share goes to your most visited capital, and XP per hour stays right
  after a `/reload` or sessions without a server sync.
- **Works with RXPGuides** (its /played answers are reused: no second /played line at
  level-up) and warns you once per load when WTFix would roll TruePlayed's data back.
- Each character has its own data; settings are shared by the whole account.
- **Light on your frame rate**: no per-frame code, a single 1-second timer, and only the
  active theme kept in memory, in a compact form. `/tpl perf` shows the memory (code plus
  the saved data of all characters) and CPU used by TruePlayed.
- **English and French**, following the game's language. To use the other one: Options >
  Display > **Language (Langue)** (Auto, English, Français), or `/tpl lang en|fr|auto`,
  then reload the interface (the **Reload UI** button under the option, or `/reload`).
  Names that come from the game (zones, mobs, instances, characters) stay in the game's
  language.

### Changed since the test build (0.1.0-test)

- XP per hour and time to next level no longer show "..." on a character installed with
  play time behind it: they start from the estimate described above, even while the
  timer is paused by an exclusion.
- The bottom right of the bar reads "XP: 58 / 23,200 · ~4.5k/h" (a separator, and the
  pause mark no longer runs into the XP text); the top right and top centre infos keep
  apart too.
- The bar percentage has one decimal ("0.3%"), like the tooltip.
- No dark background by default. Settings saved by the test build still had the old
  default: they switch to the new one (the background opacity is in Options > Texts).
- Fixed: a continent (Kalimdor, Eastern Kingdoms) was recorded as a zone for the first
  seconds after login or a loading screen; those seconds now go to the real zone.
- New: time per continent in the detailed tooltip and the Zones tab.
- New: instance time (dungeons, raids, PvP), mobs to kill, rested XP drawn like the game's
  bar, the FPS / latency graph, text colour, outline and shadow.
- The top right info is now "time to level + mobs to kill" for everyone who kept the
  default.
- The "Dark background" checkbox became a "Background opacity" slider; a background you
  had turned on keeps its look (85 %).
- The tooltip breakdown line now names the open world, dungeons, raids, PvP and flight
  instead of a single "Active" share, and leaves out the parts you never did.
- Fixed: after moving the bar, its tooltip only came back after a click.
- The pre-install estimate now uses your completed levels only (their XP divided by the
  time they took): the time spent on the current level, often idle or held by a level
  cap, no longer drags it down (e.g. ~5.7k/h instead of ~4.5k/h on a character that
  waited hours at level 20). An estimate saved by the test build is recomputed once.
- New: XP per hour and time to level freeze (`*`) instead of drifting after 20 minutes
  without XP; the beta's level 20 cap is detected and shown ("LEVEL 20 · CAP"); XP bar
  and rested colours in the options.
- New: the 13 themes. **The default look is now Futuristic**, settings saved by the test
  build included; **`/tpl theme actuel`** (or "Classic" in the options or the right-click
  menu) brings back the look of the test build, unchanged. The colour reset buttons are
  now called **Theme colours** and bring back the colours of the active theme.
- New: the language option.
- Mobs to kill now comes from the average of your last 10 kills instead of the last kill
  alone; the last kill saved by the test build starts the average.
- Updating from the test build adds files and folders (`Graph.lua`, `Media`, `Themes`):
  quit and restart the game after copying the new version (a `/reload` is not enough).
