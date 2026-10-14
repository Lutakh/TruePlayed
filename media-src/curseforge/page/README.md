# CurseForge page images

Real renders of the addon, not mockups: `scene.lua` loads the addon in the offline stub
(`tests/wowstub.lua`, `tests/stub_ui.lua`, text widths from `tests/fontmetrics.lua`),
plays a leveling character (Lutak, level 1 to 18 over 9 days, two dungeons, a Warsong
Gulch match, three deaths, some fishing and tailoring, last session 1 h 40 in Duskwood),
and exports every texture and font string it draws. The PvP image plays another evening:
the same character at level 60 on WoW Forever, five battlegrounds in a PvP season.
`render-scene.js` draws that scene with the addon's own `.tga` art and bundled fonts.
`build-page.js` puts the renders on the brand background (logo-B colours, Orbitron
headlines, Barlow subheads).

## Regenerate

From the repository root (needs `lua`, Node.js and Playwright's Chromium):

    NODE_PATH=$(npm root -g) node media-src/curseforge/build-page.js

With the installed Google Chrome instead of Playwright's Chromium (`npm i -g playwright`
with `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`): add `PW_CHANNEL=chrome` before the command.

Only some images: add their names, e.g. `... build-page.js reputation pvp stats`. To keep
the intermediate scenes and renders: add `--keep`.

One scene by hand:

    TZ=UTC lua media-src/curseforge/scene.lua tip futuriste /tmp/tip.json
    NODE_PATH=$(npm root -g) node media-src/curseforge/render-scene.js /tmp/tip.json /tmp/tip.png --scale 3

Scenarios: `bar`, `tip`, `tipshift`, `tooltip`, `tooltipshift`, `hero`, `heroshift`,
`levels`, `zones`, `sessions`, `chart`, `chartzones`, `minih` (mini display, one line),
`miniv` (stacked, three infos and the level %), `minitip` (one line, hovered), `rep`,
`repmain`, `pvp`. The tooltip is block 1 (the current level) alone; the `shift` scenarios
add block 2 (the character total), the second frame to its right, moved up or down so that
its breakdown row ("Total breakdown") is level with block 1's ("Level breakdown"). The
scene's `info.bdLevel` / `info.bdTotal` give the centre y of those two rows. The scenes
are 1920 wide, so the pair always fits: the stacked fallback of a narrow screen is not
drawn. `levels` is the Levels tab of the character (the histogram): level 16 is selected
in the detail sheet, and its PvP row is hovered (a Warsong Gulch match and a few minutes
of world PvP: that scene, `chart`, `chartzones` and `pvp` load Forever's PvP API, the
others draw exactly what they drew before). `chart` and `chartzones` are the views of
`stats.png`: the Levels tab like `levels` with nothing hovered, the window 770 high so
that the detail sheet shows all of it, and the Zones tab, its window 4 px taller so that
its list ends on a whole row; in both, a quest gives the game's event its XP, so that the
detail sheet tells quests from monsters (the other scenes keep what they drew). `rep` is
the bar with the reputation's strip under the XP track, hovered: its tooltip. Stormwind
(Honored, 1,840 in) is the game's watched faction from the start of the last session, and
each Duskwood quest of that session gives 75 to 350 reputation, so the reputation per hour
and the times are the addon's own. `repmain` is the same with the reputation on the main
track and the XP in the strip under it, its infos the reputation's (the time to the next
standing top right, the reputation per hour after the points). `pvp`: week 7 of the season (this week's cap: rank
9), rank 7 (Knight-Lieutenant, the game's Alliance titles), five Warsong Gulch and Arathi
Basin matches (three won) queued from Stormwind; the bar (520 wide) shows the rank on its
main track and the honor in its strip, hovered: the PvP tooltip. Themes: the theme ids of
`Themes/*.lua`; the private tooltip frames are drawn by the non-native themes only
(`actuel`, Classic, uses the game's GameTooltips: its `tooltip` scenes are empty, and the
`levels` scene gives the PvP row's GameTooltip as `info.tip`, its lines and the row's
rectangle).

## Images

| File | Size | Content |
|---|---|---|
| `hero.png` | 1600 x 800 | "Your real /played." The Futuristic bar (600 wide, bottom of the screen) and its tooltip (the current level, without Shift). |
| `themes.png` | 1600 x 1330 | "13 themes. One click." The bar in each theme. |
| `detail.png` | 1600 x 1240 | "Hold Shift. See everything." The Shift view in Futuristic and Heroic fantasy (labelled), next to each other and zoomed to fit (about 1.0): two tooltips side by side, the current level on the left and the character total on the right. The four breakdown rows ("Level breakdown", "Total breakdown") are on one line. |
| `stats.png` | 1600 x 1838 | "Every level. Every zone." The statistics window (Futuristic, AFK excluded): the Levels tab (the summary cards, the time per level histogram, level 16 selected and its whole detail sheet: time, time breakdown with PvP, experience by source, zones and instances), and the Zones tab in front at the bottom left (continents, most played instances, capitals, zones), over the Levels window's progress strip and footer only. |
| `compact.png` | 1600 x 1021 | "Your bar. Or no bar." The mini display (Futuristic, Mage, Warlock; Heroic fantasy stacked) and its tooltip. The minimap button is not drawn: its icon and border are game art. |
| `reputation.png` | 1600 x 820 | "Your reputation, by the hour." The headline on the left, under it the reputation as the main bar (Heroic fantasy, labelled; the XP in the strip under it; Revered in ~10h, 892 reputation per hour); on the right the Futuristic bar with Stormwind's strip under the XP track, hovered: the reputation's tooltip (Honored 2,665 / 12,000, the 8 standings with the time to each one ahead, 892 reputation per hour, next standing in ~10h, +825 this session). |
| `pvp.png` | 1600 x 952 | "Honor and rank, by the hour." The headline on the left, under it the PvP bar in the Warrior theme (labelled, without its tooltip); on the right the Futuristic PvP bar (Rank 7 Knight-Lieutenant, 614 rank points per hour, rank 8 in ~58m; the honor in the strip under it), hovered: the PvP tooltip (honor 13,381 / 25,000, rank progress and this week's cap, honorable kills, five battlegrounds this session). |

## Approximations

- Game files that are not in the repository: game fonts (FRIZQT__) are drawn with the
  bundled Signika Medium (the width stand-in of the tests), Arial Narrow with Barlow
  Condensed; `WHITE8X8` and the tooltip background are white; the tooltip border of the
  statistics window is a thin rounded line; its close button and scroll bar (Blizzard art)
  are not drawn.
- `ADD` blending is exact over an opaque background; the UI is rendered on a transparent
  one, where it falls back to normal alpha blending (the difference is invisible over the
  dark backgrounds).
- Text outlines are a 1 px (`OUTLINE`) or 2 px (`THICKOUTLINE`) black stroke outside the
  glyphs; frame scale is not applied (every view is drawn at scale 1, then zoomed).
- FPS and latency are the stub's (60 fps, 38 / 42 ms).
