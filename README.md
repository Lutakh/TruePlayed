# TruePlayed

**Your real /played, for WoW Forever.** XP per hour, time to next level, mobs to kill,
time per level, per zone and in instances, with AFK, inn and city time left out if you
want. Plus your reputation, honor and PvP rank points per hour, at max level too.

The game's `/played` counts everything: the ten minutes you were away making coffee, the
evening spent chatting at the inn, the auction house trips in Orgrimmar. TruePlayed
records every played second, knows what you were doing, and lets you decide what counts.

> Screenshots: coming soon (real in-game captures of the bar, the tooltip, the
> statistics window and the options).

## Features

- **13 visual themes** for the bar, its tooltip, the FPS graph and the statistics
  window: Futuristic (the default), Classic (the original look), Heroic fantasy, Pixel,
  and one per class, with "Class (automatic)" to give each character the theme of its
  class. See [Themes](#themes).
- **XP per hour and time to next level**, aware of your rested XP. The estimate is kept
  per character and survives `/reload`, restarts and game crashes: it does not start
  again from zero every time you log in. Right after installing, on a character that
  has already played, both start from an estimate based on your server `/played`
  (shown with a `~`: the XP of your completed levels divided by the time they took),
  then follow your own measured pace after about ten minutes of counted play. When you
  gain no XP for a while (a level cap, a long break in town), they freeze instead of
  drifting away: shown dimmed with a `*`, the time without XP left out, and back to
  normal with your next XP gain: no "3 days to next level" after hours spent at a cap.
- **Temporary level caps** (the WoW Forever beta stops characters at level 20 for now):
  after 3 mobs in a row that give no XP at your level, TruePlayed knows the server holds
  you there. The bar takes its max-level look ("LEVEL 20 · CAP"), the tooltip says
  "Level 20: current server level cap (no XP from the last 3 mobs)", and everything goes
  back to normal by itself as soon as the server gives XP again.
- **Mobs to kill**: how many mobs like your last 10 kills (their average XP) you still
  need to level up, aware of your rested XP (rested kills give double XP). In the tooltip
  under the time to next level ("~38 (average: 47 XP, last: 30 XP)"), and on the bar
  ("~5h 05m · 38 mobs", the default top right info).
- **Followed reputation under the bar**: a thin strip under the XP bar, as wide as it:
  your progress inside the current standing, in the standing's colour, full at Exalted.
  By default TruePlayed follows the faction you tick "Show as Experience Bar" for in the
  game's Reputation panel (character window, Reputation tab); Options > TruePlayed >
  **Reputation** > "Faction to follow" picks another one for this character instead (the
  game's factions, by header; the game's own choice is left untouched). The general
  tooltip has one line for it after the XP block, e.g. "Stormwind   Friendly · 1,200 /
  6,000 (20.0%)", and **hovering the strip** opens the reputation's own tooltip: the
  faction and its points ("4,800 more to Honored"), the 8 standings (the ones reached
  dimmed, the current one marked with its percentage, the points and the estimated time
  to each one ahead), **reputation per hour**, the **time to the next standing** and the
  reputation gained this session. The rate works like the XP per hour: measured from the
  reputation you really gain (never read from chat messages), kept per character across
  `/reload` and restarts, started over when you follow another faction, frozen (dimmed,
  with a `*`) after 20 minutes of play without a gain, and leaving out the AFK / inn /
  city time you exclude from the XP per hour. TruePlayed updates on reputation events
  only. Each theme places the strip its own way (the bar grows by a few pixels, or not at
  all where it fits under the track); with no faction followed, or with "Show the
  followed reputation under the bar" unticked (on by default), the bar is exactly as
  before. Renown and friendship factions show nothing; a paragon faction shows as
  Exalted.
- **Reputation as the main bar**: Options > TruePlayed > Reputation > "Main bar" >
  **Reputation** swaps the two bars, at any level: the big track shows the followed
  reputation (the faction and its standing at the left, the points at the right, the
  percentage marker, the fill in the standing's colour, full and dimmed at Exalted) and
  the thin strip under it shows your XP (no strip at max level). Hover the track for the
  reputation's tooltip. While it shows a reputation the bar is never hidden by "Hide at
  max level"; with no faction followed it shows the XP as usual.
- **PvP: honor and rank** (WoW Forever; see [PvP](#pvp)): a second thin strip, under
  the reputation's one, shows your **honor** toward its cap (gold, orange from 90 %, red
  at the cap) or your progress inside your **PvP rank**; or the whole bar shows your rank
  (Options > TruePlayed > **PvP** > "Main bar" > **PvP**), saying when the next rank is
  the week's cap, and can switch to it by itself in battlegrounds only. Hover either for
  the PvP tooltip: honor per hour, time to the honor cap, rank points per hour, time to
  the next rank, the week's cap, honorable kills, battlegrounds won and lost. An alert (a
  sound and a small window, after the fight) tells you when your honor reaches its cap.
- **Rested XP like the game's XP bar**: the bar takes the rested colour while you are
  rested (the game's blue in the Classic theme), with a lighter part up to where your
  rested XP ends, and the tooltip shows "Rested: 11,600 XP (50%)". Both bar colours can
  be changed (see below).
- **Time per level**, as a histogram of your journey (the Levels tab of the statistics
  window): one bar per level ("Level 19 » 20" is the time it took from 19 to 20),
  stacked by activity (world, world PvP, dungeons, raids, battlegrounds, flight,
  professions, dead, city, inn, AFK), with filters that keep one activity (All, World,
  Instances, PvP, Flight, Professions, Dead), faint bars for the levels still to play
  (their estimated time at your pace), a line at your average and your **progress
  toward the max level**. Seven figures above it: time played, server /played, average
  per level, **PvP** (battlegrounds and world PvP: hover it for each battleground),
  **flight** (the AFK during a flight included, unless you exclude AFK), deaths, and
  the time left to the max level at your current pace. **Click
  a bar** for the level's detail sheet: the time it took, the server time, the time to
  level estimated when it began (and how much more or less it really took), the **total
  time from level 1**, XP per hour, deaths and time dead, its time breakdown (hover its
  PvP line for each battleground and the world PvP), its XP from monsters, quests and
  the rested bonus, and its zones and instances. See
  [How do I read the Levels tab?](#faq).
- **Average time per level**: over your last 5 levels in the tooltip; overall, over your
  last 5 levels and for the whole account at the bottom of the statistics window.
- **Time per zone** (Elwynn Forest, Stranglethorn Vale...): a Zones tab with every zone
  you played in (filtered time, raw time, AFK, XP), the **zones of each level** (click a
  level in the Levels tab), the time in your current zone in the tooltip, your **time per
  continent** (Kalimdor, Eastern Kingdoms, then dungeons, raids and PvP apart; a continent
  with less than a minute is not listed) and your **most visited capitals**. Exclusions apply to zones too.
- **Played and session totals**, with the live server `/played` next to them.
- **Instance time**: dungeons, raids and PvP (battlegrounds, arenas) are recorded apart
  from the open world, AFK included. Hold Shift and the second tooltip (Character total)
  shows your instance time and each kind with its AFK part (on hover, the current level's
  breakdown names dungeons, raids and PvP), the Zones tab lists your **most played
  instances** (per character or for the whole account), the Levels tab has an Instances
  filter and lists each level's instances in its detail sheet, the Sessions tab has an
  instance column, and two bar infos show the instance time of the session and in total.
  Useful at max level too. Instance time recorded before this version stays counted as
  open world.
- **AFK time, inn / rest area time, city time and flight time**, always recorded separately.
- **Time spent dead** (from your death until you are back on your feet, the ghost run
  included) and **professions time** (gathering, fishing, first aid, crafting,
  disenchanting, lockpicking), recorded apart from the places, per level, session, zone,
  character and account. See [Dead and professions time](#dead-and-professions-time).
- **Exclude AFK, inn or city time** in one click. Exclusions are only a display filter:
  nothing is deleted, every number is recalculated instantly, and switching an exclusion
  off gives you the original numbers back. While your current state is excluded, the
  timers show pause marks and the tooltip says so.
- **Customisable XP bar**: pick three infos among 28 (time to level, time to level + mobs
  to kill, mobs to kill, XP per hour, % of level per hour, XP to go, rested XP, time this
  level, session, total, server /played, AFK this session, average per level, time in
  zone, instance time this session, total instance time, reputation per hour, time to
  the next standing, honor, honor per hour, time to the honor cap, PvP rank, rank points
  per hour, time to the next rank, honorable kills today, FPS, latency, FPS + latency;
  the seven PvP infos are not offered on Classic Era).
  Width, height, scale, text size, background opacity (0 % by default: the bar alone),
  hide in combat, fade when the mouse is away, hide at max level (not at a temporary
  server level cap).
  The level percentage has one decimal, like the tooltip. Texts never overlap, even on a
  narrow bar: numbers get shorter first, then the least useful text makes room. At max
  level the XP infos are replaced by the ones you choose.
- **Readable texts**: a thin outline and a shadow by default, so the texts stay readable
  without a background (outline none / thin / thick, shadow on or off), and the **text
  colour** of your choice through the game's colour picker (one click brings the theme's
  colours back).
- **Bar colours**: the XP bar colour and the rested colour (the bar while you are rested,
  and the lighter part showing how far your rested XP goes) through the same colour
  picker, in Options > Bar colours. Until you pick them, the bar uses the theme's colours;
  "Theme colours" brings them back.
- **FPS and latency**, measured only while they are displayed, in green / yellow / red
  (or in your text colour). **Hover them for a graph** of the last 30 s, 1 min or 5 min
  with min / average / max; hover the graph to read the value at a given moment. The game
  refreshes latency only about every 30 seconds, so the graph draws it as steps.
- **Tooltip** on the bar, in two tooltips with their own titles. On hover, **Current
  level** alone: level progress, rested XP, time to level, mobs to kill, XP per hour,
  the followed reputation (when a faction is followed), session, time at this level (and,
  while you exclude something, the level's server /played with nothing left out), time
  in the current zone at this level, the level's XP by source ("Level XP": monsters,
  quests and other, rested bonus, with its bar) and the breakdown of this level's time
  ("Level breakdown"), largest part first (world, dungeons, raids, PvP, flight,
  professions, dead, AFK, inn, city; only what you did). Hold **Shift** for
  the rate details and a **second tooltip, Character total**, **beside the first, on its
  right**: played, instance time, your whole time in the current zone, server /played,
  the average of your last 5 levels, the character's breakdown ("Total breakdown"), then
  your top 3 zones, continents, top capitals, inn / city / dungeon / raid / PvP times
  with their AFK part, professions, deaths with the time spent dead, FPS and latency.
  Each breakdown, and the level's XP, has its label with a coloured bar of its parts
  beside it, and the parts written out under it, right-aligned (in every theme but Heroic
  fantasy, which has no bar). The two breakdowns face each other at the same height, so you can compare the
  level with the whole character at a glance; each tooltip keeps its own width, and the
  hint line is at the bottom of Character total. Current level stays centred on the bar
  (under it, or above it for a bar at the bottom of the screen); the two move together
  to stay on the screen, never one over the other. On a screen too narrow for the two
  side by side (a small window or a large interface scale), Character total goes under
  Current level instead, both as wide as the wider one, Current level on top. In the
  Classic theme both are game tooltips (a tooltip addon that restyles only the game's own
  tooltip may leave the second one in the default look); each breakdown bar goes from its
  label to the tooltip's right edge (the level's XP bar starts and ends with the level
  breakdown's), and a tooltip too narrow for an 80 px bar is widened
  a little (the game's tooltip gets its own width back for whatever you hover next). The
  level history, the overall averages and the account totals are in the statistics
  window.
- **Statistics window** (`/tpl stats` or left-click on the bar) with Levels, Zones and
  Sessions tabs, for the current character, another character or the whole account
  (account total and account instance time at the bottom). The Levels tab of a
  character is the histogram and detail sheet above; for the whole account it is a
  table of each level's average over your characters. The window header names the
  exclusions in use. It is as wide as its columns need (at least 1040 x 640 while the
  histogram shows, or just inside a smaller screen); drag its bottom-right corner to
  make it larger (the size is kept; on the histogram, only the width or the height you
  changed).
  Dates show the year, hours and minutes in the format you choose (Options > Statistics
  window: the format of your language, DD/MM/YYYY, MM/DD/YYYY or YYYY-MM-DD, and a
  24-hour or 12-hour clock). Hover a column header of a table (the small "?" next to it)
  to read what the column shows.
- **Crash recovery**: SavedVariables are only written at logout. After a crash (or a
  session played without TruePlayed), the missing time is taken back from the server
  `/played`, split between levels with the exact XP you gained, split between activities
  using your recent habits (your last levels), and marked as rebuilt.
- **Automatic reload (optional, off by default)**: to lose less in a crash, TruePlayed
  can reload the interface (which saves its data) when you come back to a capital or an
  inn after an hour of unsaved play, and / or at regular intervals (a window asks first
  outside town; with both on, the interval leaves capitals and inns to the first option).
  See [the FAQ](#faq). On WoW Forever it always asks with a button.
- **One record per character** (by character GUID, so two characters with the same name
  never mix). Settings are shared by the whole account.
- **No XP bar needed**: every piece of information is also one hover away on the
  **minimap button** and on the optional **mini display** (see
  [Without the XP bar](#without-the-xp-bar)).
- Addon compartment button, and an optional Data Broker feed when another addon already
  provides LibDataBroker (no library is embedded). The tooltip of a Data Broker display
  stays one tooltip, Character total under Current level when you hold Shift (with the
  same "Level breakdown" and "Total breakdown" labels, as text: each label and its first
  parts on one line, no bar).

## Without the XP bar

Hide the bar (Options > Display > "Show the bar", `/tpl hide`, or the right-click menu)
and keep everything else:

- **Minimap button** (on by default): hover it for the bar's tooltip (Shift: the second
  tooltip, Character total),
  click it for the statistics window, right-click it for the bar's menu (exclusions,
  theme, statistics, options...), drag it around the minimap. In Options > "Minimap
  button and mini display": show / lock it, and choose what its left click does
  (statistics, options, show / hide the XP bar, show / hide the mini display).
  `/tpl minimap` shows or hides it. TruePlayed draws its own button and never registers
  with LibDBIcon, so there is never a second TruePlayed button on the minimap.
- **Mini display** (off by default: `/tpl mini` or Options): a small frame for a corner
  of the screen with 1 to 3 infos from the bar's list (time to level + mobs to kill and
  XP per hour by default), on one line or stacked, with the level percentage and / or a
  thin XP bar. It follows the bar's theme, text colour, outline and shadow, with its own
  background opacity, scale, lock, fade and hide in combat. Drag it to move it, hover it
  for the tooltip, click it for the statistics, right-click it for the menu.
- The right-click menu of the bar, the button and the mini display has a **Show**
  submenu to turn each of the three on or off; its **Hide** hides the one you clicked.

## Themes

Each theme changes the bar (track, fill, rested part, ornaments, background panel, the
place of the reputation strip, fonts and text colours), its tooltip (panel, separators,
palette), and the colours and titles of the FPS graph and of the statistics window. The
13 themes:

| Theme | `/tpl theme` name | Look | Fonts |
|---|---|---|---|
| **Futuristic** (default) | `futuriste` | Neon HUD: magenta XP, cyan rested, bevelled navy panels, scan lines, HUD brackets | Orbitron, Rajdhani |
| **Classic** | `actuel` | TruePlayed's original look: purple bar (pixel for pixel), the game's rested blue, the game's tooltip with a breakdown bar | the game font |
| **Heroic fantasy** | `heroic` | Forged gold frame, jewel-red XP, sapphire rested | Cinzel, EB Garamond |
| **Pixel (old school)** | `pixel` | Chunky pixel art, green XP, a JRPG-style tooltip window | Press Start 2P, Pixelify Sans |
| **Warrior** | `warrior` | Riveted steel plates, blood-red XP | Grenze Gotisch, Barlow Condensed |
| **Paladin** | `paladin` | White marble set in gold, golden XP | Cormorant SC, Cormorant Garamond |
| **Hunter** | `hunter` | Stitched leather strap, fletching, olive-green XP | Germania One, Signika |
| **Rogue** | `rogue` | Leather sheath with steel trim, poison-green XP | IM Fell English SC, Barlow |
| **Priest** | `priest` | Pearly ivory and silver, holy light, lilac XP | Philosopher, Lora |
| **Shaman** | `shaman` | Carved stone with tribal patterns, the four elements, deep-blue XP | Metamorphous, Nunito Sans |
| **Mage** | `mage` | Runic crystal and frost, arcane-purple XP | Macondo, Spectral |
| **Warlock** | `warlock` | Black riveted iron, fel flames, fel-green XP | UnifrakturCook, Alegreya Sans |
| **Druid** | `druid` | Carved wood and vines, leaf-green XP | Uncial Antiqua, Alegreya Sans |

**Class (automatic)** (`class`) picks the theme of the character you play: your warrior
gets Warrior, your mage gets Mage. The setting is shared by the whole account, so this is
the way to give each character its own look.

**Futuristic is the default theme for everyone**, existing installations included. To
get the previous look back, choose **Classic** (`/tpl theme actuel`): the bar and the
statistics window look exactly as in TruePlayed before themes, and the tooltip keeps the
game's own look, with a bar beside each breakdown as in the other themes.

**Switching**: Options > Display > **Theme** (the first setting), right-click the bar >
**Theme**, or `/tpl theme <name>` with a name from the table (`/tpl theme` alone shows
the current theme and the names). The change is immediate, no `/reload` needed.

**Your colours win**: the XP bar colour, the rested colour and the text colour you pick in
the options replace the theme's own, whatever the theme. The **Theme colours** buttons
bring the theme's colours back.

**Restart the game after installing or updating**: the game loads fonts and textures only
when it starts. After a `/reload` alone, theme textures can be missing and the theme fonts
are replaced by the game font (TruePlayed says so once in the chat); quitting and
restarting the game fixes it.

On Russian clients, the fonts without Cyrillic letters are replaced by the game font; on
Korean and Chinese clients every theme uses the game font.

### Fonts

The themes use 23 fonts bundled in `Media/Fonts`, all under the
[SIL Open Font License 1.1](https://scripts.sil.org/OFL). Their licence texts, with each
copyright notice, are in `Media/Fonts/LICENSES` and ship with the addon.

| Font | Copyright |
|---|---|
| Alegreya Sans | The Alegreya Sans Project Authors |
| Barlow, Barlow Condensed | The Barlow Project Authors |
| Cinzel | The Cinzel Project Authors |
| Cormorant Garamond, Cormorant SC | The Cormorant Project Authors |
| EB Garamond | The EB Garamond Project Authors |
| Germania One | John Vargas Beltrán |
| Grenze Gotisch | The Grenze Gotisch Project Authors |
| IM Fell English SC | Igino Marini |
| Lora | The Lora Project Authors |
| Macondo | John Vargas Beltrán |
| Metamorphous | Sorkin Type Co |
| Nunito Sans | The Nunito Sans Project Authors |
| Orbitron | The Orbitron Project Authors |
| Philosopher | The Philosopher Project Authors |
| Pixelify Sans | The Pixelify Sans Project Authors |
| Press Start 2P | The Press Start 2P Project Authors |
| Rajdhani | Indian Type Foundry |
| Signika | The Signika Project Authors |
| Spectral | The Spectral Project Authors |
| Uncial Antiqua | Brian J. Bonislawsky (Astigmatic) |
| UnifrakturCook | j. 'mach' wust |

The fonts keep their own licence; the MIT licence of TruePlayed does not apply to them.

## Dead and professions time

Every second of play gets one state. Two activities win over the place you are in, in
this order:

**dead > AFK > professions > flight > dungeon / raid / PvP > city > inn > world**

AFK during a flight is recorded as AFK, yet a long flight often turns AFK on its own and
is still a flight: the tooltip's Flight line includes it, and so does the Levels tab's
flight (its figure, filter and sheet line) unless you exclude AFK. The AFK of a
battleground or a dungeon stays AFK.

- **Dead**: from the moment you die until you are alive again, the ghost run included
  (it is not world time). AFK while dead is dead; a hunter's Feign Death is not. Dead time
  is never excluded. Each level keeps its deaths and its time dead.
- **Professions**: TruePlayed has no way to ask the game "is the player doing a
  profession?", so it uses a heuristic:
  - casting or channelling a profession spell: Herb Gathering, Mining, Skinning, Fishing,
    First Aid (bandages), Disenchant, Pick Lock. Spells are recognised by ID and by their
    name in your game's language, so every rank and every language works;
  - the 5 seconds after a gathering, fishing, disenchanting or lockpicking cast ends
    (looting);
  - a profession window open (any trade skill, and the Enchanting window; the hunter's
    Beast Training window is not a profession) while you stand still out of combat: a
    window left open while you run around or fight does not count;
  - a cast started from such a window, and the next casts of the same recipe after the
    window was closed ("Create all").

  Crafting in a capital counts as professions, not city. AFK wins: crafting while flagged
  AFK is AFK time. Professions time is never excluded.

  Limits: crafting done by an addon without the game's windows, a gathering spell that
  is not in the list above (opening a chest is not a profession), and a fishing cast that
  ends without a catch (its 5 seconds of grace still count) are not told apart. Moving and
  combat are read once per second, so the edges can be off by a second.
- Time recorded before this version has no dead or professions time: it stays where it
  was counted. After a crash, the time rebuilt from the server `/played` is split over the
  places only (never dead or professions time: the addon did not see it).

## PvP

WoW Forever has two PvP measures: the **honor** (a currency you spend, held up to a cap:
25,000 in the beta) and the **PvP rank** (rank points earned in battlegrounds, summed over
a season; each week of the season caps the rank you can reach). TruePlayed reads both
from the game (never from the chat, never from the battleground's scoreboard), in
Options > TruePlayed > **PvP** (each option has its "?" help):

- **Strip under the bar**: None (the default), **Honor** (your honor toward its cap:
  gold, orange from 90 %, red at the cap) or **PvP rank** (your points inside the current
  rank, full at the max rank). It sits 1 pixel under the reputation's strip when both
  show, as wide and as high, else in its place; hover it for the PvP tooltip (with PvP
  as the main bar too). A strip that would show what the PvP main bar already shows
  (the rank under the rank, or the honor under the honor before a season) is not shown.
- **Main bar** > **PvP** (the same setting as on the Reputation page): the big track shows
  your progress inside your rank, in the rank's colour; at the left the rank and its
  title in your game's language ("Rank 7 · Knight-Lieutenant", or the number alone when
  the game has no title), at the right the rank points per hour and the time to the
  next rank, saying when that rank is the week's cap ("rank 4 (week's cap) in 1h 35m":
  the highest you can reach until the weekly reset), "Weekly cap reached" when the
  week's cap stops you, "Max rank" at the top. Before the season starts (the beta right
  now) it shows your honor toward its cap and "PvP season not started". Your XP goes to
  the strip under it (none at max level): below the max level your reputation's strip
  is then not shown (the same with Reputation as the main bar). "Hide at max level"
  never hides a bar that shows PvP.
- **PvP on the bar in battlegrounds** (off by default): in a battleground (not an arena)
  the main bar shows PvP, and goes back to your choice when you leave. Your "Main bar"
  setting itself never changes. Below the max level the XP then takes the strip, so
  your reputation's strip is not shown in battlegrounds.
- **Alert when the honor is capped** (on by default): when your honor reaches its cap, a
  sound and a small window (OK button) tell you that new honor is lost until you spend
  some. It waits for the end of the fight, comes once per reaching (not again after a
  `/reload`; in read-only mode, once per load: again after a `/reload`), and again only
  after the honor was read below the cap and went back to it.
- **Honor and rank per hour**: the **Reset** button starts both over (`/tpl reset rate`
  resets every rate: XP, reputation and PvP).

**Honor per hour and rank points per hour** work like the XP per hour (the same warm-up,
dimmed at first, the same exclusions of AFK, inn and city time, kept per character
across `/reload` and restarts), over your **PvP time** only: all your time in a
battleground or an arena, and outside them the 15 minutes after each honor or rank gain.
Past those 15 minutes outside a battleground or an arena the two rates **pause**: they
keep their value, shown with a `*`, and resume with your next gain (an evening of
questing after a battleground does not drag them down). Spending honor never lowers
them; at the honor cap the honor rate stays as it was (the gains are lost), and so does
the rank rate at the week's cap or the max rank. Each login and `/reload` takes your
honor and rank as a new starting point (a read before the game has loaded them counts
nothing), and a lower rank total read in passing (around a new rank, in the same week
and season) counts nothing.

**World PvP per level** (the Levels tab of the statistics window): the open-world time
between two PvP signals less than 15 minutes apart. A signal is an honor gain or an
honorable kill (still counted at the honor cap), outside battlegrounds and arenas.
The time is counted when the second signal comes: a lone kill counts nothing, and
neither do the 15 minutes after your last fight. Today's kills count from the first
count above 0 read after a login or a `/reload` (the game can give 0 before it has
loaded them): that read is a starting point, never a kill. Only open-world time counts (not AFK,
a flight, a capital, an inn or time dead), at the level you were then (a level-up
between two signals splits it); it is a part of your world time. TruePlayed records it
from this version on: a level played before shows it as not measured (or measured for
part of the level), never as 0, and Classic Era has no such honor. Hover the PvP figure
of the Levels tab, or the PvP line of a level's detail sheet, for each battleground and
the world PvP.

**What is read, and when.** TruePlayed reads your rank and follows the battlegrounds only
while something shows PvP: the PvP strip, the PvP main bar or its battleground option, or
a PvP bar info. Your honor and today's honorable kills are always read when they change,
as they measure your world PvP (above). The rank points per hour and the session's
battlegrounds count only while something shows PvP (in between, the rank points per hour
keep their value: they neither count nor fade).
The weekly reset (a new cap) and the daily reset (today's honorable
kills) are noticed even when the game sends no event, and the PvP tooltip reads the rank
and the kills again when it opens. A battleground ends when you leave it, or when the
next one starts (a queue that pops inside one); its result compares the winner with your
side in the match. Arenas count as PvP time for the rates, not as battlegrounds.

**The PvP tooltip** (hover the PvP strip, or the main track in the PvP mode): your honor
and its cap with the percentage, the honor gained this session, per hour, the time to the
cap or, in red, how long you have been at the cap; your rank and its title, the points in
the rank, the season's total, the week's cap (rank and points) and what is left of it
this week (and, when the next rank is that cap, that it is the highest you can reach
until the weekly reset), the rank points gained this session and per hour, the time to
the next rank
(or "blocked by the cap" with the time to the weekly reset), the end of the season when
the game knows it; your **honorable kills** today, yesterday, this session, lifetime and
your highest rank ever; the **battlegrounds of the session**: played, won - lost (from the
game's result at the end of the match), average honor and average length, and the one in
progress. Seven bar infos (honor, honor per hour, time to the honor cap, PvP rank, rank
points per hour, time to the next rank, honorable kills today) go in any slot of the
bar (at max level too) and of the mini display.

On Classic Era (no honor currency or PvP rank of this kind) the PvP page only says that
PvP tracking is not available on this client, and nothing else changes.

## Installation

- **CurseForge app**: search for "TruePlayed" with the WoW Forever game version.
- **Manually**: download the zip from CurseForge or from the GitHub Releases page and
  extract the `TruePlayed` folder into the `Interface/AddOns` folder of your WoW Forever
  client, then restart the game completely. After an update, restart the game too: a
  `/reload` does not load new files, fonts or textures (see [Themes](#themes)).

On the first login the bar is unlocked: drag it where you like, then right-click it and
choose **Lock**.

## Commands

`/tpl` and `/trueplayed` are the same command. Sub-commands are case-insensitive.

| Command | What it does |
|---|---|
| `/tpl` | Open the options |
| `/tpl help` | List the commands |
| `/tpl stats [levels\|zones\|sessions]` | Open or close the statistics window |
| `/tpl lock` / `/tpl unlock` | Lock the bar, or unlock it to move it |
| `/tpl show` / `/tpl hide` | Show or hide the bar |
| `/tpl minimap` | Show or hide the minimap button |
| `/tpl mini` | Show or hide the mini display |
| `/tpl theme [name]` | Show the theme and the theme names, or change the theme (see [Themes](#themes)) |
| `/tpl lang [value]` | Show or choose the language of TruePlayed: `auto`, `en`, `fr`, `de`, `es`, `mx`, `it`, `pt` (and `ru`, `ko`, `cn`, `tw` on a client in that language); applies after `/reload`, see [Languages](#languages) |
| `/tpl afk [on\|off]` | Exclude AFK time (no argument: toggle) |
| `/tpl inn [on\|off]` | Exclude inn / rest area time (no argument: toggle) |
| `/tpl city [on\|off]` | Exclude city time (no argument: toggle) |
| `/tpl citytoggle` | Count the current zone as a city, or stop counting it |
| `/tpl played` | Summary in the chat (no server request) |
| `/tpl sync` | Ask the server for a fresh /played |
| `/tpl reset pos\|session\|rate\|char` | Reset the bar position, the session, the rates per hour (XP, reputation, honor and rank points), or erase this character's data (with confirmation) |
| `/tpl debug` | Debug messages on or off |
| `/tpl perf` | Memory and CPU used by TruePlayed |

`/played` itself is never changed.

## FAQ

**Why is my filtered time different from `/played`?**
Without exclusion, TruePlayed shows exactly the server `/played`. With exclusions it shows
the server `/played` minus the AFK, inn or city time it recorded.

**What about the time I played before installing TruePlayed?**
It cannot be split: TruePlayed only knows the total. It is shown as "Before install /
untracked" and is never excluded. Filtered totals and the overall average per level still
include it, and the tooltip says so ("incl. X before install, unfiltered").

**What does the `~` before XP per hour mean?**
It is an estimate. Right after installing, TruePlayed has not measured your pace yet, so it
starts from your server `/played` (the XP of your completed levels divided by the time
they took: the time spent on the current level, often idle or capped, is left out) and
says so in the tooltip ("estimate from your /played"). After about ten minutes of counted
play your own measured pace takes over and the `~` goes away. A brand-new character shows
`...` until it has played a few minutes; the tooltip says how long.

**What does the `*` after XP per hour mean?**
No XP came for more than 20 minutes of counted play (AFK time is never counted). Rather
than sinking a little more every minute, XP per hour and the time to next level stay at
their last value, dimmed, with a `*`; the tooltip says for how long no XP came. That time
is left out of the rate, and the numbers move again with your next XP gain.

**The bar says "LEVEL 20 · CAP".**
The server does not give you XP at this level for now (the WoW Forever beta caps
characters): 3 mobs in a row that should have given XP gave none. The bar shows the
infos you chose for max level, and returns to normal by itself at your next XP gain, for
example when the cap is raised. "Hide at max level" does not hide the bar at such a cap.

**How is "mobs to kill" counted?**
From the average XP of your last 10 kills (without their rested bonus), your XP to go and
your rested XP: while you are rested a kill gives double XP, so fewer mobs are needed.
The average keeps the number steady when the mobs around you are not all of the same
level; the tooltip also shows the XP of the last kill. Quest, exploration and discovery
XP are not kills. The number shows after your first kill, and each character keeps its
own last 10 kills.

**My old dungeon time shows as open world.**
Dungeons, raids and PvP are recorded apart from this version on. Time spent in instances
before it cannot be told apart and stays counted as open world.

**Why do a few minutes of AFK still count as active?**
The game only sets the AFK flag after about 5 minutes without input. Those minutes count
as active play.

**Why does a continent with a few seconds not show?**
A continent with less than a minute of time (often a few seconds on a loading screen or
right after creating a character) is not listed in the tooltip and the Zones tab. Its
time is kept and still counts in every total. The same goes for the time the game does
not place on any continent (mostly flights where it only gives the continent).

**How do I read the Levels tab?**
For a character it is a histogram: the bar above level 19 is the time you spent at level
19, until you reached 20 ("Level 19 » 20"), with your exclusions left out. Its colours
are the activities, in the colours of the tooltip's breakdown; a filter (World,
Instances, PvP, Flight, Professions, Dead) keeps one of them and rescales the chart (a
bar's tooltip then starts with that activity's time and its share of the level). The
bar of your current level grows while you play, with a faint part on top for the time
it should still take; the faint bars after it are the levels still to play, estimated
from your pace over your last 5 levels and the XP of each level ("Hide upcoming levels"
removes them). A small stub marks a level reached before TruePlayed was installed, and
the line across the chart is your average over the completed levels. Hover a bar for a
summary (it ends with the time from level 1 to the end of that level; for an upcoming
level, its estimate with a `~`); click it for the level's detail sheet on the right:
"Completed on" is the date you reached 20, "Total since level 1" the time from level 1
to that moment ("level 1 » 20": your whole /played up to that level-up, the time before
TruePlayed included; for the level in progress, "level 1 » 20, in progress": up to
now), then its time breakdown, its XP and its zones and instances. The strip under the
chart adds up the levels completed, the one in progress and the estimate of what is left
to the max level. The two level boxes in its title ("Progress: level 1 » 60") choose
another range, saved for each character, e.g. 10 » 20: the strip then counts the levels
from 10 until you reach 20 (a range already behind you shows complete, "level 20
reached"; a range still ahead shows its estimated time), and the chart's background
marks those levels; "Default: level 1 » 60" at the top of their menu brings the strip
back. A range over levels reached before you installed TruePlayed has no time for them
(`...`, its share of the XP only). The figures with a `~` are estimates. The account view of the tab is a table: for each
level, the characters that completed it, their average time and XP per hour.

**What is "Estimated at start" in a level's detail sheet?**
The time to the next level TruePlayed showed when the level began (right after the
level-up, or at the first XP per hour of the level while it was at most 5 % done; for
the level you installed TruePlayed at, the first measured estimate). The line under it
says how much more or less the level really took, when your exclusions (AFK, inn, city)
are the ones the estimate was taken under (an estimate recorded by 1.1.0 is always
compared). Levels reached before 1.1.0, or begun
without any XP per hour yet, have none. For the level in progress, once TruePlayed can
estimate it, the sheet shows instead the level's estimate (its time so far plus what is
left) and about how much is left.

**The game crashed. Did I lose my time?**
No. The game writes addon data only at logout or `/reload`, so a crash loses the detail of
the session. At the next login TruePlayed compares its data with the server `/played`,
re-adds the missing time, splits it between levels using the server level time and your
exact XP, splits it between activities using your recent habits (the level of your last
save and the 5 before it, without any time rebuilt earlier, a level mostly rebuilt by an
older version left out; your whole history when they hold less than 10 minutes),
attributes it to your last known zone, and marks it as
rebuilt ("incl. 35m rebuilt after a crash"). That line follows your exclusions like the
line above it: with AFK excluded, the rebuilt AFK time is left out (time rebuilt by an
older version, kept without its split, is valued with the level's own share of AFK).
When more than half of a breakdown is rebuilt time, a grey line under it says so ("62%
rebuilt after a crash: estimated split"): its split is then mostly an estimate. This
needs a server `/played` at login: TruePlayed asks for one (the usual `/played` lines
appear once in the chat) unless another addon already did, or you can type `/tpl sync`.
The same happens if your computer sleeps or freezes for more than 15 minutes.
To lose less in a crash, turn on the automatic reload (next question).

**What does the automatic reload do?**
Each reload of the interface saves TruePlayed's data, so a crash then loses only what
came after it. Options > Automatic reload (both off by default; hover the "?" after each
one):
- **Reload in a capital or an inn**: in a capital or an inn you came back to (from the
  world, a dungeon or a flight) since the last load, once 60 minutes of play are unsaved,
  whether you arrive after them or are already there when they are reached: as soon as
  you have stood still 10 seconds out of combat with no window open, a chat line warns
  you and the interface reloads 5 seconds later; moving cancels it (asked again 10
  minutes later). Staying in town after that, even AFK for hours, does not reload again:
  it needs a new arrival.
- **Also reload at regular intervals** (10 to 120 minutes, 30 by default): anywhere but a
  capital or an inn, a small window at the top of the screen asks first: "Reload now", or
  "Later" (asked again 10 minutes later). In a capital or an inn, it depends on the
  option above: ticked too, the interval leaves capitals and inns to it (no double
  reload there: a reload due in town waits until you are out of town, and the window
  hides if you walk into one); not ticked, the interval reloads there too, once you stand
  still, even if you never left it (so every interval while you stay in town). Never in
  an instance, on a flight, dead, while gathering or crafting, or in combat: it waits.
  The window hides if you enter an instance, take a flight, die or start a fight (it
  comes back a few seconds after the fight), and its "Reload now" waits, greyed and
  unclickable, for a second or two after an XP gain (longer after a level-up) while
  TruePlayed reads it.

It waits while you cast, type, have a game window, menu, options or popup open, or right
after a load or a level-up, and never reloads while TruePlayed is still reading a
`/played` answer, an XP gain or rebuilding a crash, nor when WTFix protects TruePlayed
(it would put old data back). The loading screen of a reload counts in the state you
were in (city or inn time, which you can exclude). **On WoW Forever an addon may reload
the interface only after your click**: there TruePlayed never reloads by itself, it
always asks with the window, and its "Reload now" reloads on your click (should the
game still refuse it, the chat tells you to type `/reload`).

**How is "city" decided?**
By map: the whole capital counts as city (Stormwind, Ironforge, Darnassus, Orgrimmar,
Thunder Bluff, Undercity), not only its inn. A flight over a capital counts as flight.
`/tpl citytoggle` adds or removes the zone you are in (not inside an instance: dungeons
never count as cities). Any other rest area counts as inn.

**The /played lines appear in my chat at login.**
That is TruePlayed's single login request, sent only when no other addon asked within
10 seconds. You can turn it off in the options (crash recovery then waits until you type
`/played` or `/tpl sync`). An experimental option hides the lines of TruePlayed's own
requests; it may disturb the chat in dungeons, so it is off by default.

**I use RXPGuides.**
RXPGuides already asks for `/played` at login and hides it; TruePlayed simply listens.
A `/played` you type within about 3 seconds of RXPGuides' request may be hidden by
RXPGuides once.

## Compatibility

- **WoW Forever** 1.60.x (interface 16001), loaded through `TruePlayed_Camelot.toc`.
- **Classic Era**: planned once tested.
- Works with RXPGuides.
- With **WTFix**, open `/wtfix` and untick TruePlayed: WTFix restores protected addons from
  an older copy at every load, which would roll back your play history (TruePlayed warns
  you in chat).
- Uses only its own frames; the experimental "hide /played lines" option, off by default,
  briefly wraps `ChatFrameUtil.DisplayTimePlayed`.

## Languages

Every language of the game: English, Français, Deutsch, Español (EU), Español (AL),
Italiano, Português (BR), Русский, 한국어, 简体中文 and 繁體中文 (English game clients in
Britain report `enUS`). TruePlayed follows the game's language by default. To use
another one, choose it in Options > Display > **Language** or type `/tpl lang` with its
short name (`auto`, `en`, `fr`, `de`, `es`, `mx`, `it`, `pt`, `ru`, `ko`, `cn`, `tw`;
`/tpl lang` alone lists the ones you can pick), then reload the interface (the **Reload
UI** button under the option, or `/reload`). Russian, Korean and Chinese are offered only
on a game client in that language: the fonts of the other clients cannot draw their
letters. Names that come from the game (zones, mobs, instances, characters, the
`/played` lines) stay in the game's language, and so do the AddOns list texts.

The translations other than French were not reviewed by native speakers yet:
corrections are welcome (open an issue or a pull request with the line and your
wording). Keep the words short: the offline tests measure every text of the bar, the
tooltips, the options panel, the statistics window and the graph with the real fonts,
in every language and theme, and fail when one does not fit.

Translator recipe (the header of `Locales/enUS.lua` has the details):

1. Copy `Locales/frFR.lua` to `Locales/<code>.lua` (a `GetLocale()` code, for example
   `plPL`), set its `CODE` line to that code and translate every value. Keep the keys,
   the format arguments (`%s`, `%d`, `%02d`) in the same order, `%%` for a percent sign,
   and the registration block at the end of the file. Use the words of the game in that
   language (XP, rested, level, dungeon, raid...), and phrasings that need no plural
   form when the language has several (`Мобов: %s`).
2. Add the file to `TruePlayed_Camelot.toc` after the other locales, with a `Notes-<code>`
   and a `Category-<code>` line.
3. Append `<code>` to `C.LANGUAGES` in `Core.lua`; if its script is not Latin (Cyrillic,
   Hangul, Han), add it to `C.LANGUAGES_NATIVE_ONLY` too and to `NATIVE_LOCALES` in
   `tests/check_encoding.lua`.
4. Add its `LANG_<CODE>` name, written in that language, to every locale file, and a line
   for it in `LanguageLabel` and an alias in `LANG_ALIAS` (`Options.lua`).
5. Run the tests (see [Development](#development)) and open a pull request.

## Performance

TruePlayed is built to be invisible in your frame rate:

- no per-frame (`OnUpdate`) code at all; a single 1-second timer does the time accounting;
- almost nothing is allocated on that timer; a displayed FPS value that changes costs at
  most one short string, and texts are only redrawn when they change;
- the statistics window, the options and the tooltip content are only built when you open
  them, and hidden parts stop listening to events;
- FPS and latency are measured only while you display them;
- saved data is bounded (30 sessions, pruned small zones, top 10 zones per level);
- only the active theme is kept in memory, in a compact form (about 11 to 55 KB in the
  game, Futuristic about 52 KB); the 13 themes
  wait as short texts (66 KB in all) that are turned into a theme only when one is
  applied; its textures, colours and fonts are set once when it is applied, never on the
  timer, and the bar's textures are reused from one theme to the next (once every theme
  has been shown, switching creates none).
- memory grows with the number of characters tracked (about 0.1-0.3 MB each); use
  "Erase this character's data" in the options (or `/tpl reset char`) for abandoned alts.

Type `/tpl perf` to see the memory used, the CPU time (when `scriptProfile` is on) and a
60-second measurement of the timer cost. The memory figure is the one addon managers show:
the addon's code (about half a megabyte) **plus the saved data of all your characters**,
so it grows with the number of characters you play. What matters is that it stays stable
over a long session.

## Reporting a problem

Please open an issue: https://github.com/Lutakh/TruePlayed/issues
Include the TruePlayed version, your game language, the Lua error text (turn errors on
with `/console scriptErrors 1`) and, for performance questions, the `/tpl perf` output.

## Development

The addon folder is the git repository. Offline tests run with a stock Lua interpreter
(5.1 like the game, or 5.5):

```
lua tests/run.lua            # unit tests (add a filter, e.g. "lua tests/run.lua tracker")
lua tests/check_toc.lua      # TOC file list and required lines
lua tests/check_encoding.lua # UTF-8, no BOM, no CR; Latin-1 range only (but ru/ko/zh locales)
lua tests/lint51.lua         # Lua 5.1 portability and SPEC rules
lua tests/check_globals.lua  # no accidental global read or write, at run time
lua tests/check_media.lua    # theme fonts (glyph coverage, licences) and textures
```

`tests/test_theme_memory.lua` (part of the unit tests, on Lua 5.4 and 5.5 only) holds the
memory budgets of the themes. `tests/render_snapshot.lua` writes everything the bar, its
tooltip, the graph, the statistics window and the options draw, for the 13 themes in 7
situations; run it on two versions and compare the files to prove that a change draws
exactly the same thing:

```
TZ=UTC lua tests/render_snapshot.lua /tmp/new.txt                 # this checkout
TZ=UTC lua tests/render_snapshot.lua /tmp/old.txt ../old-checkout/ # the addon files of another one
diff /tmp/old.txt /tmp/new.txt
```

GitHub Actions runs them on Lua 5.1 and 5.5, plus luacheck, on every push. Pushing a tag
`vX.Y.Z` publishes the release with the BigWigs packager.

TruePlayed was developed with the help of Claude (Anthropic).

## License

MIT, see [LICENSE](LICENSE). Author: Lutak.

---

## En français

**TruePlayed, votre vrai /played.** L'addon compte chaque seconde de jeu et la range
selon ce que vous faisiez : monde, donjons, raids, JcJ, AFK, auberge ou zone de repos,
capitale, vol. Il affiche l'XP par heure et le temps avant le prochain niveau (qui ne
repartent pas de zéro après un `/reload`, un redémarrage ou un plantage), le nombre de
monstres à tuer (d'après la moyenne de vos 10 derniers monstres tués, en tenant compte du
repos), le temps par
niveau, par zone et en instance (« Instances les plus jouées » dans l'onglet Zones), les
moyennes par niveau, le temps de session et le /played du serveur.

Vous pouvez exclure le temps AFK, en auberge ou en ville à tout moment (clic droit sur
la barre, options, ou `/tpl afk`, `/tpl inn`, `/tpl city`) : rien n'est effacé et tout
est recalculé immédiatement. Après un plantage, le temps manquant est repris du /played
du serveur et réparti d'après vos habitudes récentes (vos derniers niveaux) ; la ligne
« dont reconstitué après un plantage » suit vos exclusions, et une ligne grisée prévient
quand plus de la moitié d'une répartition est reconstituée (« 62 % reconstitué après un
plantage : répartition estimée »).

**Rechargement automatique** (facultatif, désactivé par défaut) : le jeu n'enregistre
les données des addons qu'à la déconnexion ou au `/reload`, donc un plantage perd tout
depuis la dernière sauvegarde. Options > Rechargement automatique (survolez le « ? » après
chaque option) :
- **Recharger en capitale ou à l'auberge** : dans une capitale ou une auberge où vous êtes
  revenu (du monde, d'un donjon ou d'un vol) depuis le dernier chargement, une fois
  60 minutes de jeu non enregistrées, que vous y arriviez après ou que vous y soyez déjà
  quand elles sont atteintes : dès que vous êtes resté immobile 10 secondes hors combat
  sans fenêtre ouverte, une ligne du chat prévient et l'interface se recharge 5 secondes
  plus tard ; bouger annule (nouvelle tentative 10 minutes après). Rester ensuite en
  ville, même AFK pendant des heures, ne recharge pas en boucle : il faut une nouvelle
  arrivée.
- **Recharger aussi à intervalle régulier** (10 à 120 minutes, 30 par défaut) : hors des
  capitales et des auberges, une petite fenêtre en haut de l'écran demande d'abord :
  « Recharger maintenant » ou « Plus tard » (redemande 10 minutes après). En capitale ou
  à l'auberge, cela dépend de l'option précédente : cochée aussi, l'intervalle lui laisse
  les capitales et les auberges (pas de doublon : un rechargement dû en ville attend que
  vous en soyez sorti, et la fenêtre se cache si vous y entrez) ; non cochée, l'intervalle
  recharge aussi là, dès que vous y restez immobile, même sans en être sorti (donc à
  chaque intervalle tant que vous restez en ville). Jamais en instance, en vol, mort,
  pendant une récolte ou un artisanat, ni en combat : il attend. La fenêtre se cache si
  vous entrez en instance, prenez un vol, mourez ou engagez un combat (elle revient
  quelques secondes après le combat), et son bouton « Recharger maintenant » attend, grisé
  et sans effet, une ou deux secondes après un gain d'XP (plus longtemps après une montée
  de niveau) le temps que TruePlayed le lise.

Il attend aussi pendant un sort, une saisie, une fenêtre, le menu, les options ou une
boîte de dialogue du jeu, ou juste après un chargement ou une montée de niveau, et ne
recharge jamais tant que TruePlayed lit encore une réponse /played, un gain d'XP ou
reconstitue un plantage, ni quand WTFix protège TruePlayed. **Sur WoW Forever, un addon
ne peut recharger l'interface qu'après votre clic** : TruePlayed n'y recharge jamais
tout seul, il demande toujours avec la fenêtre, et « Recharger maintenant » recharge à
votre clic (si le jeu le refuse quand même, le chat vous dit de taper `/reload`).

Juste après l'installation, sur un personnage qui a déjà joué, l'XP par heure et le temps
avant le niveau partent d'une estimation d'après votre /played (affichée avec un `~` :
l'XP des niveaux terminés divisée par le temps qu'ils ont pris), puis suivent votre propre
rythme après une dizaine de minutes de jeu prises en compte. Après 20 minutes de jeu sans
aucune XP, ils se figent (grisés, avec un `*`) au lieu de s'effondrer, et repartent à
votre prochain gain d'XP.

**Réputation suivie** : une fine bande sous la barre d'XP, de la même largeur, montre
votre progression dans le rang actuel, de la couleur du rang, pleine au rang Exalté. Par
défaut, TruePlayed suit la faction cochée « Barre de réputation » dans le panneau
Réputation du jeu (fenêtre du personnage, onglet Réputation) ; Options >
TruePlayed > **Réputation** > « Faction à suivre » en choisit une autre pour ce
personnage (les factions du jeu, par catégorie ; le choix fait dans le jeu n'est pas
touché). L'infobulle générale lui consacre une ligne après le bloc XP, par exemple
« Hurlevent   Amical · 1 200 / 6 000 (20,0 %) », et **le survol de la bande** ouvre
l'infobulle de la réputation : la faction et ses points (« encore 4 800 avant Honoré »),
les 8 rangs (ceux atteints grisés, l'actuel marqué avec son pourcentage, les points et
le temps estimé avant chacun des suivants), la **réputation par heure**, le **temps avant
le rang suivant** et le gain de la session. Ce rythme fonctionne comme l'XP par heure :
mesuré sur la réputation réellement gagnée (jamais lu dans les messages du chat), gardé
par personnage après un `/reload` ou un redémarrage, remis à zéro quand vous suivez une
autre faction, figé (grisé, avec un `*`) après 20 minutes de jeu sans gain, et sans le
temps AFK / auberge / ville que vous excluez de l'XP par heure. TruePlayed ne se met à
jour que sur les événements de réputation. Chaque thème place la bande à sa façon (la
barre grandit de quelques pixels, ou pas du tout quand la bande tient sous la piste).
Sans faction suivie, ou avec « Afficher la réputation suivie sous la barre » décochée
(cochée par défaut), la barre est exactement comme avant. Les factions à renom et les
amitiés n'affichent rien ; une faction parangon s'affiche comme Exalté.

**La réputation en barre principale** : Options > TruePlayed > Réputation > « Barre
principale » > **Réputation** inverse les deux barres, à tout niveau : la grande barre
montre la réputation suivie (la faction et son rang à gauche, les points à droite, le
repère de pourcentage, le remplissage de la couleur du rang, plein et atténué au rang
Exalté) et la fine bande dessous votre XP (pas de bande au niveau maximum). Survolez la
barre pour l'infobulle de la réputation. Tant qu'elle montre une réputation, la barre
n'est jamais masquée par « Masquer au niveau max » ; sans faction suivie, elle montre
l'XP comme d'habitude. Deux infos de la barre, « Réputation par heure » et « Temps avant
le rang de réputation », se placent dans n'importe quel emplacement (aussi au niveau
max).

**JcJ : honneur et rang** (WoW Forever) : TruePlayed suit vos **points d'honneur** (une
monnaie que vous dépensez, plafonnée : 25 000 sur la bêta) et votre **rang JcJ** (des
points de rang gagnés en champ de bataille, cumulés sur une saison ; chaque semaine de la
saison plafonne le rang atteignable). Tout est lu dans le jeu, jamais dans le chat ni dans
le tableau des scores. Options > TruePlayed > **JcJ** (chaque option a son « ? ») :
- **Bande sous la barre** : Aucune (par défaut), **Honneur** (votre honneur par rapport
  au plafond : doré, orange dès 90 %, rouge au plafond) ou **Rang JcJ** (vos points dans
  le rang actuel, pleine au rang max). Elle se place 1 pixel sous celle de la réputation
  quand les deux sont affichées, de même largeur et de même hauteur, sinon à sa place ;
  survolez-la pour l'infobulle JcJ (aussi avec le JcJ en barre principale). Une bande qui
  montrerait ce que la barre principale JcJ montre déjà (le rang sous le rang, ou
  l'honneur sous l'honneur avant la saison) n'est pas affichée.
- **Barre principale** > **JcJ** (le même réglage que sur la page Réputation) : la
  grande barre montre votre progression dans votre rang, de la couleur du rang ; à
  gauche le rang et son titre dans la langue du jeu (« Rang 7 · Chevalier-lieutenant »,
  ou le numéro seul si le jeu n'a pas de titre), à droite les points de rang par heure
  et le temps avant le rang suivant, en précisant quand ce rang est le plafond de la
  semaine (« rang 4 (plafond hebdo) dans 1 h 35 » : le plus haut que vous pouvez
  atteindre avant le reset hebdomadaire), « Plafond de la semaine atteint » quand le
  plafond vous bloque, « Rang max » au sommet. Avant le début de la saison (le cas de la
  bêta en ce moment), elle montre votre honneur par rapport au plafond et « Saison JcJ
  non commencée ». Votre XP passe dans la bande dessous (aucune au niveau max) : sous le
  niveau max, la bande de réputation n'est donc pas affichée (de même avec la Réputation
  en barre principale). « Masquer au niveau max » ne masque jamais une barre qui montre
  le JcJ.
- **JcJ sur la barre en champ de bataille** (décochée par défaut) : en champ de bataille
  (pas en arène), la barre principale affiche le JcJ, puis revient à votre choix à la
  sortie. Le réglage « Barre principale » lui-même ne change jamais. Sous le niveau max,
  l'XP prend alors la bande du dessous : la bande de réputation n'est pas affichée en
  champ de bataille.
- **Alerte au plafond d'honneur** (cochée par défaut) : quand votre honneur atteint le
  plafond, un son et une petite fenêtre (bouton OK) vous préviennent que l'honneur gagné
  est perdu tant que vous n'en dépensez pas. Elle attend la fin du combat, ne vient
  qu'une fois par plafond atteint (pas de nouveau après un `/reload` ; en lecture seule,
  une fois par chargement : de nouveau après un `/reload`), et revient seulement après
  une lecture sous le plafond puis un nouveau passage au plafond.
- **Honneur et rang par heure** : le bouton **Réinitialiser** remet les deux à zéro
  (`/tpl reset rate` remet à zéro tous les taux : XP, réputation et JcJ).

**L'honneur par heure et les points de rang par heure** fonctionnent comme l'XP par
heure (même mise en route, grisés au début, mêmes exclusions AFK / auberge / ville,
gardés par personnage après un `/reload` ou un redémarrage), mais sur votre **temps
JcJ** seulement : tout votre temps en champ de bataille ou en arène, et en dehors les 15
minutes qui suivent chaque gain d'honneur ou de points de rang. Passé ces 15 minutes
hors champ de bataille ou d'arène, les deux taux se mettent **en pause** : ils gardent
leur valeur, marquée d'un `*`, et reprennent au prochain gain (une soirée de quêtes
après un champ de bataille ne les fait pas chuter). Dépenser de l'honneur ne les fait
jamais baisser ; au plafond d'honneur, l'honneur par heure reste tel quel (les gains
sont perdus), de même que les points de rang par heure au plafond de la semaine ou au
rang max. Chaque connexion et chaque `/reload` reprennent votre honneur et votre rang
comme nouveau point de départ (une lecture faite avant que le jeu les ait chargés ne
compte rien), et un total de rang plus bas lu au passage (autour d'un nouveau rang, dans
la même semaine et la même saison) ne compte rien.

**JcJ sauvage par niveau** (onglet Niveaux de la fenêtre des statistiques) : le temps
passé en monde ouvert entre deux signaux JcJ espacés de moins de 15 minutes. Un signal
est un gain d'honneur ou une victoire honorable (comptée aussi au plafond d'honneur),
hors champs de bataille et arènes. Le temps est compté à l'arrivée du second signal :
une victoire isolée ne compte rien, ni les 15 minutes qui suivent votre dernier combat.
Les victoires du jour comptent à partir de la première valeur au-dessus de 0 lue après
une connexion ou un `/reload` (le jeu peut d'abord donner 0) : cette lecture est un
point de départ, jamais une victoire.
Seul le temps en monde ouvert compte (pas l'AFK, un vol, une capitale, une auberge ni le
temps mort), au niveau que vous aviez alors (une montée de niveau entre deux signaux le
partage) ; il fait partie de votre temps « Monde ». TruePlayed le mesure à partir de
cette version : un niveau joué avant l'indique comme non mesuré (ou mesuré sur une
partie du niveau), jamais comme 0, et Classic Era n'a pas cet honneur. Survolez le
chiffre JcJ de l'onglet Niveaux, ou la ligne JcJ de la fiche d'un niveau, pour voir
chaque champ de bataille et le JcJ sauvage.

**Ce qui est lu, et quand.** TruePlayed ne lit votre rang et ne suit les champs de
bataille que si quelque chose affiche le JcJ : la bande JcJ, la barre principale JcJ ou
son option en champ de bataille, ou une info JcJ de la barre. Votre honneur et vos
victoires honorables du jour sont toujours lus quand ils changent, puisqu'ils mesurent
votre JcJ sauvage (ci-dessus). Sans affichage JcJ, les points de rang par heure et les
champs de bataille de la session ne comptent pas (les points de rang par heure gardent
leur valeur : ils ne baissent pas). Le
reset hebdomadaire (un nouveau plafond) et le reset quotidien (les victoires honorables
du jour) sont pris en compte même sans événement du jeu, et l'infobulle JcJ relit le
rang et les victoires à son ouverture. Un champ de bataille se termine quand vous le
quittez, ou quand le suivant commence (une file qui s'ouvre pendant la partie) ; son
résultat compare le vainqueur à votre camp dans la partie. Les arènes comptent comme
temps JcJ pour les taux, pas comme champs de bataille.

**L'infobulle JcJ** (survol de la bande JcJ, ou de la grande barre en mode JcJ) : votre
honneur et son plafond avec le pourcentage, l'honneur gagné pendant la session, par
heure, le temps avant le plafond ou, en rouge, depuis combien de temps vous y êtes ;
votre rang et son titre, les points dans le rang, le total de la saison, le plafond de
la semaine (rang et points) et ce qu'il en reste cette semaine (et, quand le rang
suivant est ce plafond, que c'est le plus haut que vous pouvez atteindre avant le reset
hebdomadaire), les points de rang gagnés pendant la session et par heure, le temps avant le rang suivant (ou « bloqué par le
plafond » avec le temps avant la réinitialisation hebdomadaire), la fin de la saison
quand le jeu la connaît ; vos **victoires honorables** du jour, de la veille, de la
session, de toute la vie du personnage et votre meilleur rang ; les **champs de bataille
de la session** : joués, gagnés - perdus (d'après le résultat donné par le jeu en fin de
partie), honneur moyen et durée moyenne, et celui en cours. Sept infos de la barre
(honneur, honneur par heure, temps avant le plafond d'honneur, rang JcJ, points de rang
par heure, temps avant le rang JcJ suivant, victoires honorables du jour) se placent dans
n'importe quel emplacement de la barre (aussi au niveau max) et du mini-affichage. Sur
Classic Era (pas de monnaie d'honneur ni de rang de ce type), la page JcJ indique
seulement que le suivi JcJ n'est pas disponible sur ce client, et rien d'autre ne change.

Sur la bêta de WoW Forever, bloquée au niveau 20 pour l'instant, TruePlayed repère le
plafond après 3 monstres de suite sans XP : la barre affiche `NIVEAU 20 · PLAFOND` et son
aspect du niveau maximum, l'infobulle l'explique, et tout redevient normal tout seul dès
que le serveur redonne de l'XP.

Le temps passé mort (de la mort jusqu'au retour à la vie, course du fantôme comprise)
et le temps de métiers (cueillette, minage, dépeçage, pêche, secourisme, artisanat dans
une fenêtre de métier, désenchantement, crochetage) sont comptés à part, par niveau,
session, zone, personnage et compte, et ne sont jamais exclus. Ordre de priorité :
mort > AFK > métiers > vol > instance > ville > auberge > monde. L'AFK pendant un vol
est enregistré comme AFK, mais un long vol passe souvent AFK tout seul et reste un vol :
la ligne « En vol » de l'infobulle le compte, et le vol de l'onglet Niveaux (chiffre,
filtre et ligne de la fiche) aussi, sauf si vous excluez l'AFK ; l'AFK d'un champ de
bataille ou d'un donjon reste de l'AFK. La fiche de chaque niveau (onglet Niveaux)
montre ses morts, son temps mort et le temps estimé à son début.

**Onglet Niveaux** (`/tpl stats`) : pour un personnage, un histogramme de votre
parcours, une barre par niveau (celle du niveau 19 : le temps passé au niveau 19 jusqu'au
20), sans ce que vous excluez, empilée par activité dans les couleurs de la répartition
de l'infobulle : monde, JcJ sauvage, donjons, raids, champs de bataille, vol, métiers,
mort, ville, auberge, AFK. Au-dessus, sept chiffres : temps joué, /played serveur,
moyenne par niveau (et sur les 5 derniers), **JcJ** (champs de bataille et JcJ sauvage ;
survolez-le pour le détail par champ de bataille), **vol** (l'AFK pendant un vol
compris, sauf si vous excluez l'AFK), morts et le temps avant le niveau max au rythme
actuel. Les filtres (Tout, Monde, Instances, JcJ, Vol, Métiers,
Mort) ne gardent qu'une activité, pour voir à quels niveaux elle a compté. Les niveaux à
venir apparaissent en barres estompées de leur durée estimée d'après votre rythme sur
vos derniers niveaux (« Masquer les niveaux à venir » les retire), une ligne marque
votre moyenne, et la bande « Progression : niveau 1 » 60 » en bas additionne les
niveaux terminés, celui en cours et ce qu'il reste. Ses deux cases de niveau choisissent
une autre plage, gardée pour chaque personnage, par exemple 10 » 20 : la bande compte
alors les niveaux de 10 jusqu'à atteindre le 20 (une plage déjà derrière vous est
complète, « niveau 20 atteint » ; une plage encore devant, son temps estimé), et le fond
du graphique marque ces niveaux ; « Par défaut : niveau 1 » 60 », en haut de leur menu,
remet la bande d'origine. Une plage sur des niveaux atteints avant l'installation de
TruePlayed n'a pas de temps pour eux (`...`, seulement sa part de l'XP). Survolez une barre pour son résumé (jusqu'au cumul depuis le
niveau 1 à la fin de ce niveau ; pour un niveau à venir, son estimation avec un `~`) ;
**cliquez dessus** pour la fiche du niveau, à droite : la date où il a été terminé, le
temps joué, le /played serveur, le temps estimé à son début (et l'écart réel, sous les
exclusions de l'estimation), le cumul
depuis le niveau 1 (« niveau 1 » 20 » : jusqu'au passage au 20 ; « niveau 1 » 20, en
cours » pour le niveau en cours : jusqu'à maintenant), l'XP par heure, les morts, la répartition du temps (survolez la
ligne JcJ pour chaque champ de bataille et le JcJ sauvage ; le vol est toujours
indiqué), l'XP gagnée sur les monstres, les quêtes et le bonus de repos, et ses zones et
instances. La barre du niveau en cours, les chiffres et la répartition de sa fiche
suivent votre jeu tant que la fenêtre est ouverte ; sur cet onglet, elle fait au moins
1040 x 640 (ou un peu moins que l'écran s'il est plus petit). Pour tout le compte,
l'onglet reste un tableau : pour chaque niveau, les personnages qui l'ont terminé, leur
temps moyen et leur XP par heure.

**Infobulle** : survolez la barre (ou le bouton de la minicarte, le mini-affichage) pour
l'infobulle « Niveau en cours » : XP, repos, temps avant le niveau, monstres à tuer, XP
par heure, réputation suivie (quand une faction est suivie), session, temps à ce niveau
(et, quand vous excluez quelque chose, le /played serveur du niveau, sans rien d'exclu),
temps dans la zone à ce niveau, l'XP du niveau par source (« XP du niveau » : monstres,
quêtes et autres, bonus de repos, avec sa barre) et répartition de ce niveau
(« Répartition du niveau »).
Maintenez **Maj** : le détail du rythme s'y
ajoute, et une **deuxième infobulle, « Total du personnage »**, s'ouvre **à côté, à
droite** : temps de jeu, temps en instance, tout votre temps dans la zone, /played du
serveur, moyenne des 5 derniers niveaux, répartition du personnage (« Répartition
totale »), puis zones, continents, capitales, temps et morts. Chaque répartition, et l'XP
du niveau, a son libellé, avec à sa droite une barre colorée de ses parts, et les parts écrites en
dessous, alignées à droite (dans tous les thèmes sauf Heroic fantasy, qui n'a pas de
barre). Les deux répartitions sont face à face, à la même hauteur, pour comparer d'un
coup d'œil le niveau et tout le personnage ; chaque infobulle garde sa largeur, et la
ligne d'aide (Maj, clics) est en bas de « Total du personnage ». « Niveau en cours » reste
centrée sur la barre (dessous, ou dessus pour une barre en bas de l'écran) ; les deux se
déplacent ensemble pour rester dans l'écran, sans jamais se chevaucher. Sur un écran trop
étroit pour les mettre côte à côte (petite fenêtre ou grande échelle d'interface),
« Total du personnage » passe sous « Niveau en cours », les deux à la largeur de la plus
large, « Niveau en cours » en haut. Avec le thème Classique, ce sont deux infobulles du
jeu (un addon qui ne retouche que l'infobulle du jeu peut laisser la deuxième à l'aspect
d'origine) ; chaque barre de répartition va de son libellé jusqu'au bord droit de
l'infobulle (la barre de l'XP du niveau commence et finit avec celle de la répartition du
niveau), et une infobulle trop étroite pour une barre de 80 pixels s'élargit un peu
(l'infobulle du jeu reprend sa largeur pour ce que vous survolez ensuite). L'infobulle
d'un affichage Data Broker reste une seule infobulle, avec les mêmes libellés, en texte
seul (chaque libellé et ses premières parts sur une ligne, sans barre).

Le temps par zone (Forêt d'Elwynn, Strangleronce...) est dans l'onglet Zones de la
fenêtre de statistiques, avec le temps par continent (Kalimdor, Royaumes de l'Est,
instances) ; cliquez sur un niveau dans l'onglet Niveaux pour voir ses zones. La barre est
affichée sans fond par défaut (option « Opacité du fond »), avec des textes contournés et
ombrés pour rester lisibles, dans la couleur de votre choix. Comme la barre d'XP du jeu,
elle prend la couleur du repos quand vous êtes reposé ; ces deux couleurs se changent
aussi (Options > Couleurs de la barre, bouton « Couleurs du thème »). Survolez les FPS ou la latence pour voir leur
graphique (30 s, 1 min ou 5 min).
La barre affiche trois infos au choix parmi 28 (21 sur Classic Era). Tapez `/tpl` pour les options,
`/tpl stats` pour la fenêtre de statistiques et `/tpl help` pour la liste des
commandes. L'addon est traduit dans toutes les langues du jeu (français, anglais, allemand,
espagnol, italien, portugais, russe, coréen, chinois) et suit la langue du jeu ; pour en
choisir une autre : Options > Affichage > « Langue (Language) » ou `/tpl lang` suivi du
nom court (`fr`, `en`, `de`, `es`, `mx`, `it`, `pt`, `auto`...), puis rechargez l'interface
(bouton « Recharger l'interface » ou `/reload`). Le russe, le coréen et le chinois ne sont
proposés que sur un client du jeu dans cette langue. Les noms fournis par le jeu (zones,
monstres) restent dans la langue du jeu.

**Thèmes** : 13 thèmes changent l'aspect de la barre, de son infobulle, du graphique et
de la fenêtre de statistiques : Futuriste (par défaut, pour tout le monde), Classique
(l'aspect d'origine : barre et fenêtre à l'identique, infobulle du jeu avec une barre de
répartition ; `/tpl theme actuel`), Heroic fantasy, Pixel rétro
et un thème par classe (Guerrier, Paladin, Chasseur, Voleur, Prêtre, Chaman, Mage,
Démoniste, Druide), plus « Classe (auto) » qui donne à chaque personnage le thème de sa
classe. Choisissez-le dans Options > Affichage > Thème, par clic droit sur la barre >
Thème, ou avec `/tpl theme <nom>`. Les couleurs que vous choisissez remplacent celles du
thème (bouton « Couleurs du thème » pour revenir). Après une installation ou une mise à
jour, relancez complètement le jeu : un `/reload` ne charge pas les polices et les
textures. Les 23 polices fournies sont sous licence SIL Open Font License 1.1 (textes
dans `Media/Fonts/LICENSES`).

Avec WTFix, ouvrez `/wtfix` et décochez TruePlayed : sinon WTFix remet une ancienne
copie de ses données à chaque chargement (TruePlayed vous prévient dans le chat).
