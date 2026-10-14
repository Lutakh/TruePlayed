# Changelog

All notable changes to TruePlayed are listed here, newest first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
version numbers follow [Semantic Versioning](https://semver.org/).
Each version section becomes the release notes shown on CurseForge.

## [Unreleased]

**Quit the game and launch it again after updating** (a `/reload` is not enough): this
version adds seven files, and the game loads new files only at start.

### In short

- **Reputation under the XP bar**: hover it for reputation per hour and time to each standing.
- **Reputation as the main bar** if you prefer: your XP then takes the thin strip.
- **PvP honor and rank**: both per hour, the time to your next rank and to the honor cap.
- **PvP on the bar**: an honor or rank strip, or the whole bar; an alert at the honor cap.
- **The Levels tab is a histogram** of your journey: click a level for its detail sheet.
- **World PvP per level**, next to your battlegrounds, in the Levels tab.
- **Optional automatic reload**: saves your data at quiet moments (on WoW Forever, on your click).

### Added

- **The followed reputation under the bar**: a thin strip (3 px) appears under
  TruePlayed's XP bar, as wide as it: your progress inside the current standing of the
  followed faction, in the standing's colour (the game's: red, orange, yellow, green),
  full at Exalted. Hover the bar: one line after the XP block gives the faction, its
  standing and your points, e.g. "Friendly · 1,200 / 6,000 (20.0%)" (the standing alone
  at Exalted); a very long faction name is shortened with "...", never the numbers.
  Every theme places the strip its own way: in the Shaman theme it fits in the space
  under the track, elsewhere the bar grows by 4 to 10 px (the most where the bar's
  progress marker hangs below the track: the strip passes under it); nothing overlaps
  the texts or the marker. With no faction followed, or with **Show the followed
  reputation under the bar** unticked (on by default, for the whole account; a circled
  "?" explains it), the bar is exactly as before. It is updated only when your reputation
  changes. Renown and friendship factions (retail systems) show nothing; a paragon
  faction shows as Exalted.
- **Which faction**: by default the one you tick "Show as Experience Bar" for in the
  game's Reputation panel, followed at once when you change it. The new **Faction to
  follow** option picks another one for this character only (each character keeps its
  own): the game's factions, grouped by their headers, with their standing (a header
  is offered only when it has a reputation of its own). TruePlayed never changes the
  game's own choice; reading the list (each time you open the menu) opens the collapsed
  headers for an instant and closes them again, as you left them. If the chosen faction
  cannot be read, the game's is shown instead and the tooltip says so; the chosen one
  keeps its reputation per hour and session gain for when it can be read again.
- **The reputation's own tooltip**: hover the strip (the gap under the XP track) for the
  details: the faction and its points ("4,800 more to Honored"), the 8 standings (the
  ones reached dimmed, the current one marked with its percentage, the points and the
  estimated time to each one ahead), **reputation per hour**, the **time to the next
  standing** and what you gained this session. It opens above or below the bar like the
  bar's own tooltip, never over it. Clicks and drags there act on the bar. In the themed
  tooltips and in the Classic theme's game tooltip.
- **Reputation per hour and time to the next standing**, measured like the XP per hour:
  from the reputation you really gain between two reads (losses left out, chat messages
  never read), per character, kept across `/reload` and restarts, started over when the
  followed faction changes, about ten minutes of counted play before a full estimate,
  frozen (dimmed, with a `*`) after 20 minutes of play without a gain, and the AFK / inn
  / city time you exclude left out. `/tpl reset rate` and the options' reset button
  start it over. Two new bar infos, **Reputation per hour** and **Time to next
  standing**, fit any slot (at max level too).
- **Reputation as the main bar**: **Main bar** > **Reputation** swaps the two, at any
  level and for the whole account: the big track shows the followed reputation (the
  faction and its standing at the left, the points at the right, the percentage marker,
  the fill in the standing's colour, full and dimmed at Exalted) and the thin strip your
  XP (no strip at max level). The bar is then never hidden by "Hide at max level" while
  it shows a reputation; with no faction followed, it shows the XP as usual. In every
  theme.
- **A Reputation page in the options** (Options > TruePlayed > Reputation): show the
  strip, the main bar and the faction to follow, each with its circled "?", and a button
  that resets the reputation per hour. The strip's checkbox moves there from Display,
  which now points to the new page; with Reputation as the main bar it is greyed out, as
  the strip then shows your XP (a note says so). Where the game has no sub-pages, the
  same controls form a Reputation section right after Display.
- **PvP on WoW Forever: honor and rank.** TruePlayed reads your **honor** (the currency
  you spend, held up to a cap: 25,000 in the beta) and your **PvP rank** (rank points
  summed over a season, each week capping the rank you can reach) from the game, never
  from the chat or the scoreboard. A new **PvP** page in the options (Options >
  TruePlayed > PvP, each control with its circled "?"; a PvP section of the main page,
  right after the Reputation section, where the game has no sub-pages):
  - **Strip under the bar**: None (the default), **Honor** (your honor toward its cap:
    gold, orange from 90 %, red at the cap) or **PvP rank** (your points inside the
    current rank). It sits 1 px under the reputation's strip, as wide and as high, when
    both show (the bar grows by what it needs, the hover regions split between the two),
    else in its place. With PvP as the main bar it keeps its own PvP tooltip, and a
    strip that would show the same thing as the main bar (the rank under the rank, or
    the honor under the honor before the season starts) is not shown. In every theme.
  - **Main bar: PvP** (a third choice of the "Main bar" setting, on the Reputation page
    too): the big track shows your progress inside your rank in the rank's colour; the
    rank and its title in the game's language at the left ("Rank 7 ·
    Knight-Lieutenant", the number alone when the game has none), the rank points per
    hour and the time to the next rank at the right (saying when that rank is the
    week's cap: "rank 4 (week's cap) in 1h 35m"), "Weekly cap reached" or "Max rank"
    when they apply. Before the PvP season starts (the beta right now) it shows the
    honor toward its cap and "PvP season not started". The XP moves to the strip (none
    at max level), so below the max level the reputation's strip is not shown while the
    bar shows PvP; "Hide at max level" never hides a bar that shows PvP.
  - **PvP on the bar in battlegrounds** (off by default): in a battleground (not an
    arena) the main bar shows PvP, then goes back to your choice when you leave; the
    "Main bar" setting itself is never changed. Below the max level the XP then takes
    the strip, as above.
  - **Alert when the honor is capped** (on by default): a sound and a small window with
    an OK button when your honor reaches its cap (new honor is lost until you spend
    some), once the fight is over; once per reaching (not again after a `/reload`; in
    read-only mode, once per load: again after a `/reload`), and again only once you
    have spent some honor and reach the cap anew.
  - **Honor and rank per hour** reset button.
- **Honor per hour and rank points per hour**, measured like the XP per hour (warm-up,
  exclusions, kept per character across `/reload` and restarts) over your **PvP time**
  only: all your time in battlegrounds and arenas, and outside them the 15 minutes after
  each honor or rank gain. Past them, outside a battleground or an arena, both **pause**
  (their value kept, marked with a `*`) until your next gain. Spending honor never lowers
  them; at the honor cap, the week's cap or the max rank the matching rate is kept as it
  was. `/tpl reset rate` starts them over too. Every login and `/reload` takes your honor
  and rank as a new starting point, and a lower rank total read in passing (around a new
  rank) counts nothing.
- **PvP data read only when needed**: TruePlayed reads the rank, follows the
  battlegrounds and watches the reset countdowns only while something shows PvP (the
  strip, the PvP main bar or its battleground option, a PvP bar info), so the rank
  points per hour and the session's battlegrounds count only meanwhile (in between, the
  rank points per hour keep their value: they neither count nor fade). Your honor and
  today's honorable kills are always read when they change, as they measure the world
  PvP of each level (see below): the honor you gain counts in the session and in the
  honor per hour whatever is shown. The weekly reset (a new cap) and the daily reset
  (today's honorable kills) are noticed even when the game sends no event, and the PvP
  tooltip reads the rank and the kills again when it opens.
- **The PvP tooltip** (hover the PvP strip, or the main track in the PvP mode): honor and
  its cap, gained this session, per hour, the time to the cap or how long you have been
  at the cap (in red); the rank and its title, the points in the rank, the season's
  total, the week's cap and what is left of it (and, when the next rank is that cap, that
  it is the highest you can reach until the weekly reset), gained this session, per
  hour, the time to the next rank (or "blocked by the cap" until the weekly reset), the
  end of the season when known; honorable kills today, yesterday, this session, lifetime
  and the highest rank; the battlegrounds of the session (played, won - lost from the
  game's result against your side in the match, average honor and length, the one in
  progress; a battleground ends when you leave it, or when the next one starts from a
  queue that pops inside it; arenas count as PvP time, not as battlegrounds). In the
  themed tooltips and in the Classic theme's game tooltip.
- **Seven PvP bar infos**: honor, honor per hour, time to the honor cap, PvP rank, rank
  points per hour ("Rank pts 312/h"), time to the next rank, honorable kills today, for
  any slot of the bar (at max level too) and of the mini display. On Classic Era, which
  has no such honor or rank, they are not offered and the PvP page says PvP tracking is
  not available there.
- **The Levels tab, a histogram of your journey** (`/tpl stats`, the Levels tab of a
  character): one bar per level, from level 1 to the one before the max level, for the
  time spent at that level until the next one, under your exclusions. Each bar is
  stacked in the colours of the tooltip's breakdown: world, world PvP, dungeons, raids,
  battlegrounds, flight, professions, dead, city, inn, AFK, and the time before
  TruePlayed or not tracked. A level reached before TruePlayed was installed shows a
  small stub. On top, seven figures: **time played**, **server /played**, **average per
  level** (and over your last 5), **PvP** (battlegrounds and world PvP), **flight** (and
  its share of your time played, "<1%" when it is small), **deaths** (and the time spent
  dead or a ghost) and **"Level 60 in"**, the play time left to the max level at your
  current pace (at the max level: your time there; at a server level cap: the cap, for
  your other characters too; with your XP disabled: "XP disabled"; followed by a "+"
  when some levels ahead have no known XP size, as the time is then at least that).
  Hover the PvP figure for each battleground and the world PvP. **Flight includes the
  AFK during a flight** (a long flight often turns AFK on its own), as the tooltip's
  flight line does, unless you exclude AFK; the AFK of a battleground or a dungeon stays
  AFK.
  - **Filters** (All, World, Instances, PvP, Flight, Professions, Dead) keep one
    activity, to see at which levels it counted. The scale (in hours, in days for very
    long levels) and the title follow, e.g. "PvP time per level (BG + world)" with "3h
    12m in total · across 6 levels" ("No time recorded" when there is none).
  - **The levels still to play** show a faint bar of their estimated time, and the level
    in progress its estimated remaining part on top of its played part (shown with
    "All" only; "Hide upcoming levels" removes them). The estimate follows your pace over
    your last 5 completed levels, adjusted to the XP of each level (else your XP per
    hour), and is marked with a `~`.
  - **A line marks your average** over the completed levels shown.
  - **"Progress toward level 60"**, under the chart: the levels completed, the one in
    progress and about what is left, e.g. "~42% of the estimated total time · 18% of
    the XP".
  - **Hover a bar** for its time (`~` when partly estimated), its parts with their share,
    its deaths, its XP per hour and the date the next level was reached; under a filter,
    the first line gives that activity's time in the bar and its share of the level. An
    upcoming level shows its estimate and the XP to earn.
  - The bar of the level in progress, the seven figures (PvP, flight and deaths
    included) and the strip follow your play while the window is open. While the chart
    shows, the window is at least 1040 x 640, or just inside your screen when that is
    smaller (on a 4:3 screen the chart's columns get narrower); the size you saved is
    kept for the other tabs, and resizing the window on the chart saves only the width
    or the height you changed.
- **The detail sheet of a level**: click a bar (the level in progress is selected when
  the window opens) and a sheet on the right of the chart gives the whole level:
  - the date it was completed (or the share of its XP done, "Upcoming", "No data"), and
    why its time is partly an estimate (begun before the install, rebuilt after a crash,
    server time not split) or how long it went without any XP gain;
  - six figures: time played, server /played, **estimated at start** with how much more
    or less the level really took (said only under the exclusions the estimate was taken
    with; for the level in progress, the level's estimate and about how much is left),
    total since level 1, XP per hour, deaths with the time dead;
  - **"Time breakdown"**: a bar and one line per activity, longest first, with its
    share ("<1%" when it is small); **Flight** is always listed. Hover the **PvP** line
    for its split: each battleground, the world PvP, its definition and since when it is
    measured. For the level in progress, the lines, the bar, the shares and the deaths
    follow your play (a flight, a battleground, a death) while the window is open;
  - **"Experience"**: the XP from monsters, from quests and other sources, and the
    rested bonus, with their shares;
  - **"Zones and instances"** of the level, each with a small bar: its zones (8 at most)
    and its 5 longest instances; an instance is never listed as an open-world zone.

  An upcoming level shows its estimated duration (from your pace over your last levels,
  or from your current XP per hour while there are too few of them, as its line says),
  the XP to earn and about how much play is left until it is reached.
- **World PvP per level**: the open-world time between two PvP signals (an honor gain or
  an honorable kill, outside battlegrounds and arenas) less than 15 minutes apart,
  counted when the second one comes: a lone kill counts nothing, and neither do the 15
  minutes after your last fight. Today's kills count from the first count above 0 read
  after a login or a `/reload` (the game can give 0 before it has loaded them): that
  read is a starting point, never a kill. It is a part of the world time (never AFK,
  flight, city, inn or dead time), kept per level and per character, and shown in the
  Levels tab. Recorded from this version on: levels played before show it as not
  measured (or measured for part of the level), never as 0. Nothing is recorded in
  read-only mode; on Classic Era (no such honor) the tab says it is not measured on this
  client.
- **Automatic reload (optional, off by default)**: the game writes addon data only when
  you log out or reload the interface, so a game crash loses everything since the last
  save, which TruePlayed then has to rebuild from your /played as an estimate. Two new
  options (Options > Automatic reload) reload the interface at quiet moments:
  - **Reload in a capital or an inn**: in a capital or an inn you came back to from the
    world, once 60 minutes of play are unsaved (whether you arrive after them or are
    already there when they are reached), as soon as you stand still out of combat with
    no window open. A chat line warns 5 seconds before; moving cancels it. Staying in
    town after that (AFK for hours) never reloads again and again: it needs a new
    arrival.
  - **Also reload at regular intervals** (every 10 to 120 minutes, 30 by default):
    outside capitals and inns a small window asks first ("Reload now" / "Later", asked
    again 10 minutes later). With the option above ticked too, the interval leaves
    capitals and inns to it, so the two never double up there: a reload due in town waits
    until you are out of town, and the window hides if you walk into one. Without it,
    the interval also reloads in a capital or an inn once you stand still, even if you
    never left it (every interval while you stay in town). Never in an instance, on a
    flight, dead, while gathering or crafting, or in combat. The window hides if you
    enter an instance, take a flight, die or start a fight (it comes back a few seconds
    after the fight), and its "Reload now" waits, greyed and unclickable, while an XP
    gain or a level-up is still being read.

  It never reloads while a /played answer, a crash rebuild or an XP gain is still being
  read, while you cast, type or have a game window, the game menu or options or a popup
  open, or when WTFix would put old data back. **On WoW Forever an addon may reload the
  interface only after your click**: there TruePlayed never reloads by itself and always
  asks with the window, and "Reload now" reloads on your click (should the game still
  refuse it, even silently, within 5 seconds the chat tells you to type /reload). A
  circled "?" after each option explains it.
- **A note when a breakdown is mostly rebuilt**: when more than half of the time of a
  breakdown (this level's, or the character's with Shift) was rebuilt after a crash, a
  grey line under it says so, e.g. "62% rebuilt after a crash: estimated split".

### Changed

- **The Levels tab of a character is the histogram above** instead of a table of level
  rows. What the rows and their columns showed (Time, Est., Total, Server, XP/h, Inst.,
  AFK, Inn, City, Dead, Prof., main zone, Reached) and the zones of a row's tooltip are
  now in the bar's tooltip and in the detail sheet of the level. The account view of
  the tab keeps its table (each level's average time and XP per hour over your
  characters), and `/tpl stats levels` still opens the tab. The header's hint now reads
  "Click a bar to see the level's detail."
- **The tooltip is split in two, each part with its own title.** Hovering the bar shows
  **Current level** alone: the XP block, the session, the time at this level, the time
  in the current zone at this level (it used to be the character's whole time there) and
  the breakdown of this level's time (world, dungeons, AFK... of this level only). Hold
  **Shift** and a **second tooltip, Character total**, opens **beside it, on its right**:
  played time (with your exclusions), instance time, your whole time in the current
  zone, server /played, the average of your last 5 levels, the breakdown of the whole
  character, then the zones, continents, capitals, times and deaths as before.
  - **The two breakdowns face each other**: Character total is moved up or down so that
    its breakdown (and its bar) is at the same height as the level's, to compare them at
    a glance; each tooltip keeps its own width. They are labelled **"Level breakdown"**
    and **"Total breakdown"** (the one breakdown of 1.1.0 was "Breakdown"), in the
    tooltip of a Data Broker display too.
  - **Placement**: Current level stays centred on the bar, under it or above it as
    before (Character total usually starts a little lower than it). The two move together
    to stay on the screen, never one alone and never one over the other; taller than the
    whole screen, Current level stays whole and only the bottom of Character total goes
    off.
  - **Small screens**: when the two do not fit side by side (a small game window or a
    large interface scale), Character total goes under Current level instead, both as
    wide as the wider one (above the bar, they grow upward and Current level stays on
    top), moved as one piece to stay on the screen. This is checked again every second,
    so resizing the window switches between the two layouts.
  - The hint line (Shift, clicks) moves to the bottom of Character total. Each tooltip
    has its own breakdown bar. In the Heroic theme (no bar), the breakdown label now has
    a line of its own, its parts on the lines under it, as in the other themes (the
    longer labels no longer fit on the line of the parts).
  - **A breakdown bar in the Classic theme too** (it showed the parts as text only): in
    both tooltips, the breakdown label now has its line to itself, with a bar of its parts
    from the label to the tooltip's right edge, largest part first, in the colours of the
    Futuristic theme's bar, with a thin dark outline. The parts are written under it,
    right-aligned, as in the other themes. A tooltip too narrow for an 80 px bar is
    widened just enough (the game's tooltip gets its own width back for whatever you
    hover next). The tooltip of a Data Broker display has no bar, as before.
  - The same goes for the mini display, the minimap button and the addon compartment;
    the tooltip of a Data Broker display stays one tooltip with both parts. In the
    Classic theme, a tooltip addon that restyles only the game's own tooltip may leave
    the second one in the game's default look.
- **Time rebuilt after a crash follows your recent habits.** The missing time is now split
  between activities like your last levels (the level of your last save and the 5 before
  it), not like your whole history: a character that idled in town long ago no longer
  gets city time in each crash. Time rebuilt by an earlier crash is never taken as a
  habit (a level rebuilt by an earlier version, kept without its split, counts for its
  played part only, and not at all when it is mostly rebuilt). Your whole history is still
  used when those levels hold less than 10 minutes.
- **`/tpl help`** says what `/tpl reset rate` resets: every rate per hour (XP,
  reputation and PvP), not the XP per hour alone. The main page's button does the same
  and now says so: **Reset rates per hour** (its message lists the three); the
  Reputation and PvP pages' buttons reset their own rate only.

### Fixed

- **An instance is listed once.** The game often gives the first seconds in a
  battleground or a dungeon under the instance before its map is known, so the same
  place was saved under two names and listed twice, once with a few seconds ("Warsong
  Gulch (PvP) 1h 35m" then "Warsong Gulch (PvP) <1m"). The instances of the Zones tab
  and of a level's detail sheet now show it as one row with the total.
- **"incl. ... rebuilt after a crash" follows your exclusions.** With AFK excluded, the
  rebuilt AFK time was still counted in it, so it could be larger than "This level" above
  it (e.g. "This level 1h 21m" then "incl. 1h 46m rebuilt after a crash"). It now leaves
  out what you exclude and never exceeds the line above, in the tooltip, in the Levels tab
  (the `~` mark and the note of the level's detail sheet) and in `/tpl played`. For time
  rebuilt before this version, the excluded part is estimated from the level's own share
  of AFK, inn and city.

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
