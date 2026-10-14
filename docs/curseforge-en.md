# CurseForge page - English

This file holds the texts of the CurseForge (and Wago) project page. It is not shipped in
the addon zip. See `docs/PUBLISHING-fr.md` for where each text goes.

## Project settings (do not paste into the description)

- **Name**: TruePlayed (exactly this: CurseForge forbids game or version names in the
  project name, so "Forever" goes in the summary, the description and the logo).
- **Summary** (one sentence, "WoW Forever" first; the field takes at most 256 characters,
  this one has 189): paste only the line below.

  ```
  WoW Forever: your real /played - XP per hour, time to level, mobs to kill and time per zone without AFK, inn or city time, plus reputation, honor and PvP rank points per hour, in 13 themes.
  ```

- **Game version of the files**: Forever 1.60.1 (set by the packager from
  `## Interface: 16001`; choose it by hand only for a manual upload).
- **Main category**: Quests & Leveling. **Additional category**: Miscellaneous.
- **License**: MIT
- **Author**: Lutak
- **Logo**: 400 x 400 px, not a single colour, no protected artwork (not the in-game
  pocket-watch icon), with a small "FOREVER" badge.
- **Keywords** (put them naturally in the summary and description): WoW Forever, Forever,
  played, /played, XP per hour, time to level, leveling, AFK, inn, rested, zone time,
  time per zone, instance time, dungeon time, raid time, death time, professions time,
  mobs to kill, reputation, reputation per hour, time to next standing, honor, honor per
  hour, honor cap, PvP, PvP rank, rank points, rank points per hour, battlegrounds, world
  PvP, honorable kills, FPS graph, themes, class themes.
- **Issues / source**: https://github.com/Lutakh/TruePlayed

Everything below the line is the **Description** (Markdown editor). The images are the
PNG files of `media-src/curseforge/page/`, linked from the `main` branch on GitHub: they
show only once those files are on `main` (`media-src/curseforge/page/README.md` says how
to rebuild them). Links are written `[text](url)`: a bare address followed by text on the
next line is read as one broken link by CurseForge.

**Which file to paste.** CurseForge's description editor is visual: Markdown pasted into it
is not converted (that is what broke the old issues link and layout). Paste instead
`docs/curseforge-en.html` (the same description in HTML, made by
`python3 media-src/curseforge/description-html.py docs/curseforge-en.md > docs/curseforge-en.html`)
into the editor's source-code view (the `<>` button), replacing everything there.

---

![TruePlayed: your real /played](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/hero.png)

Every second you play, counted and sorted: open world, dungeons, raids, PvP, AFK, inns,
cities, flights, professions, even the time spent dead. Leave the AFK out with one click.
Or don't.

### Know when you'll level.

XP per hour. Time to level. Mobs to kill. Rested XP included.

### Know where your time went.

Per level. Per zone. Per instance. Per character, or your whole account.

### Max level? Keep going.

Reputation per hour. Honor per hour. Rank points per hour. Time to your next standing and
to your next PvP rank.

![13 themes. One click.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/themes.png)

Futuristic, Heroic, Pixel, Classic, and one for every class. The bar, the tooltip and the
statistics window change together.

![Hold Shift. See everything.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/detail.png)

Hover for the level you are on. Hold Shift and a second tooltip opens beside it for your
whole character, the two breakdowns face to face: your pace, your top zones, your time
per continent, in dungeons and in PvP, your deaths and your professions.

![Every level. Every zone.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/stats.png)

Your whole journey in one window, `/tpl stats`: a bar for every level, split by what you
did there (open world, dungeons, battlegrounds and world PvP, flights, professions,
deaths, cities and inns), the levels still ahead, and when you will reach 60 at your
pace. Click a level for everything about it: its estimate when it began, its PvP, its XP,
its zones. Every zone and every session in the next tabs.

![Your reputation, by the hour.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/reputation.png)

Follow the faction of your choice: a thin strip under your XP bar, or the whole bar. Hover
it for every standing ahead, your reputation per hour and the time to the next one. At
max level too.

![Honor and rank, by the hour.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/pvp.png)

Your honor toward its cap, your PvP rank and the week's cap: honor and rank points per
hour, time to the next rank, battlegrounds won and lost. On a strip, or on the whole bar,
by itself in battlegrounds if you like. And an alert when your honor is capped.

![Your bar, or no bar.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/compact.png)

Keep your own XP bar: use the minimap button, or a tiny display in a corner of the screen
that shows only what you pick.

### Light. Safe.

No per-frame code, one timer per second. A crash loses nothing: the missing time comes
back from the server at the next login.

### In your language.

English, Français, Deutsch, Español, Italiano, Português, Русский, 한국어, 简体中文, 繁體中文.

---

## Get started

1. Install, then **restart the game** (new files load only at start).
2. Hover the bar, the minimap button or the mini display.
3. Right-click for the menu. `/tpl` for every option.

| Command | |
|---|---|
| `/tpl` | Options |
| `/tpl stats` | Statistics |
| `/tpl theme` | Themes |
| `/tpl minimap` | Minimap button on / off |
| `/tpl mini` | Mini display on / off |
| `/tpl afk` `inn` `city` | Leave that time out, or count it again |
| `/tpl help` | Every command |

## FAQ

**Why is it different from /played?** It isn't, until you leave something out. Then it is
/played minus that time. Nothing is ever deleted: switch it back on and the numbers come
back.

**What does `~` mean?** An estimate: a time still to come (to the next level, standing or
rank, to the honor cap, to the max level), the mobs to kill and, for the first ten minutes
after install, a pace taken from your server /played.

**Textures or fonts missing?** Quit the game and launch it again: `/reload` is not enough
after installing or updating.

**Reputation? PvP?** The reputation strip follows the faction you tick "Show as Experience
Bar" for in the game's Reputation panel, or the one you pick in Options > TruePlayed >
Reputation. Honor and rank show once you pick a strip or the whole bar in Options >
TruePlayed > PvP.

**WTFix?** Open `/wtfix` and untick TruePlayed. **RXPGuides?** Works with it.

## Feedback

[Report a bug](https://github.com/Lutakh/TruePlayed/issues/new) · [Suggest an idea](https://github.com/Lutakh/TruePlayed/issues/new) · [Source code](https://github.com/Lutakh/TruePlayed)

Translations were made without native speakers: corrections are very welcome.

TruePlayed was developed with the help of Claude (Anthropic), who also drew the logo.
