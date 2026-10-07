# CurseForge page - English

This file holds the texts of the CurseForge (and Wago) project page. It is not shipped in
the addon zip. See `docs/PUBLISHING-fr.md` for where each text goes.

## Project settings (do not paste into the description)

- **Name**: TruePlayed (exactly this: CurseForge forbids game or version names in the
  project name, so "Forever" goes in the summary, the description and the logo).
- **Summary** (one sentence, "WoW Forever" first; the field takes at most 256 characters,
  this one has 137): paste only the line below.

  ```
  WoW Forever: your real /played - XP per hour, time to level, mobs to kill and time per zone, without AFK, inn or city time, in 13 themes.
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
  time per zone, instance time, dungeon time, raid time, mobs to kill, FPS graph, themes,
  class themes.
- **Issues / source**: https://github.com/Lutakh/TruePlayed

Everything below the line is the **Description** (Markdown editor). The images are the
PNG files of `media-src/curseforge/page/`, linked from the `main` branch on GitHub: they
show only once those files are on `main` (`media-src/curseforge/page/README.md` says how
to rebuild them). Links are written `[text](url)`: a bare address followed by text on the
next line is read as one broken link by CurseForge.

---

![TruePlayed: your real /played](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/hero.png)

Every second you play, counted and sorted: open world, dungeons, raids, PvP, AFK, inns,
cities, flights. Leave the AFK out with one click. Or don't.

### Know when you'll level.

XP per hour. Time to level. Mobs to kill. Rested XP included.

### Know where your time went.

Per level. Per zone. Per instance. Per character, or your whole account.

![13 themes. One click.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/themes.png)

Futuristic, Heroic, Pixel, Classic, and one for every class. The bar, the tooltip and the
statistics window change together.

![Hold Shift. See everything.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/detail.png)

Your pace, your last levels, your top zones, your deaths, your account total.

![Every level. Every zone.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/stats.png)

A full history in one window: `/tpl stats`.

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

**What does `~` mean?** An estimate from your server /played, used for the first ten
minutes after install.

**Textures or fonts missing?** Quit the game and launch it again: `/reload` is not enough
after installing or updating.

**WTFix?** Open `/wtfix` and untick TruePlayed. **RXPGuides?** Works with it.

## Feedback

[Report a bug](https://github.com/Lutakh/TruePlayed/issues/new) · [Suggest an idea](https://github.com/Lutakh/TruePlayed/issues/new) · [Source code](https://github.com/Lutakh/TruePlayed)

Translations were made without native speakers: corrections are very welcome.
