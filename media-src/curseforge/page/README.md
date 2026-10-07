# CurseForge page images

Real renders of the addon, not mockups: `scene.lua` loads the addon in the offline stub
(`tests/wowstub.lua`, `tests/stub_ui.lua`, text widths from `tests/fontmetrics.lua`), plays
a leveling character (Lutak, level 1 to 18 over 9 days, two dungeons, a Warsong Gulch
match, four deaths, some fishing and tailoring, last session 1 h 40 in Duskwood), and
exports every texture and font string it draws. `render-scene.js` draws that scene
with the addon's own `.tga` art and bundled fonts. `build-page.js` puts the renders on the
brand background (logo-B colours, Orbitron headlines, Barlow subheads).

## Regenerate

From the repository root (needs `lua`, Node.js and Playwright's Chromium):

    NODE_PATH=$(npm root -g) node media-src/curseforge/build-page.js

With the installed Google Chrome instead of Playwright's Chromium (`npm i -g playwright`
with `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`): add `PW_CHANNEL=chrome` before the command.

Only some images: add their names, e.g. `... build-page.js hero stats`. To keep the
intermediate scenes and renders: add `--keep`.

One scene by hand:

    TZ=UTC lua media-src/curseforge/scene.lua tip futuriste /tmp/tip.json
    NODE_PATH=$(npm root -g) node media-src/curseforge/render-scene.js /tmp/tip.json /tmp/tip.png --scale 3

Scenarios: `bar`, `tip`, `tipshift`, `tooltip`, `tooltipshift`, `hero`, `levels`,
`zones`, `sessions`, `minih` (mini display, one line), `miniv` (stacked, three infos and
the level %), `minitip` (one line, hovered). Themes: the theme ids of `Themes/*.lua`.

## Images

| File | Size | Content |
|---|---|---|
| `hero.png` | 1600 x 800 | "Your real /played." The Futuristic bar (600 wide, bottom of the screen) and its tooltip. |
| `themes.png` | 1600 x 1330 | "13 themes. One click." The bar in each theme. |
| `detail.png` | 1600 x 1328 | "Hold Shift. See everything." The detailed tooltip, Futuristic and Heroic fantasy. |
| `stats.png` | 1600 x 1228 | "Every level. Every zone." The statistics window (Futuristic, AFK excluded): the Levels tab with the help tooltip of its Server column, and the Zones tab (continents, dungeons, PvP). |
| `compact.png` | 1600 x 1021 | "Your bar. Or no bar." The mini display (Futuristic, Mage, Warlock; Heroic fantasy stacked) and its tooltip. The minimap button is not drawn: its icon and border are game art. |

## Approximations

- Game files that are not in the repository: game fonts (FRIZQT__) are drawn with the
  bundled Signika Medium (the width stand-in of the tests), Arial Narrow with Barlow
  Condensed; `WHITE8X8` and the tooltip background are white; the tooltip border of the
  statistics window is a thin rounded line; its close button and scroll bar (Blizzard art)
  are not drawn. The help tooltip of a column header (a GameTooltip) is drawn by
  `build-page.js` in the game's tooltip style, with the text and place the scene exports.
- `ADD` blending is exact over an opaque background; the UI is rendered on a transparent
  one, where it falls back to normal alpha blending (the difference is invisible over the
  dark backgrounds).
- Text outlines are a 1 px (`OUTLINE`) or 2 px (`THICKOUTLINE`) black stroke outside the
  glyphs; frame scale is not applied (every view is drawn at scale 1, then zoomed).
- FPS and latency are the stub's (60 fps, 38 / 42 ms).
