# TruePlayed

**Your real /played, for WoW Forever.** XP per hour, time to next level, mobs to kill,
time per level, per zone and in instances, with AFK, inn and city time left out if you
want.

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
- **Rested XP like the game's XP bar**: the bar takes the rested colour while you are
  rested (the game's blue in the Classic theme), with a lighter part up to where your
  rested XP ends, and the tooltip shows "Rested: 11,600 XP (50%)". Both bar colours can
  be changed (see below).
- **Time per level** and a full level history (time, server time, XP per hour, AFK, inn,
  city, instances, main zone, date reached).
- **Average time per level**: overall, over your last 5 levels, and for the whole account.
- **Time per zone** (Elwynn Forest, Stranglethorn Vale...): a Zones tab with every zone
  you played in (filtered time, raw time, AFK, XP), the **zones of each level** (hover a
  level in the Levels tab), the time in your current zone in the tooltip, your **time per
  continent** (Kalimdor, Eastern Kingdoms, instances) and your **most visited capitals**.
  Exclusions apply to zones too.
- **Played and session totals**, with the live server `/played` next to them.
- **Instance time**: dungeons, raids and PvP (battlegrounds, arenas) are recorded apart
  from the open world, AFK included. The tooltip shows your instance time (and each kind
  with its AFK part when you hold Shift), the Zones tab lists your **most played
  instances** (per character or for the whole account), the Levels and Sessions tabs
  have an instance column, and two bar infos show the instance time of the session and
  in total. Useful at max level too. Instance time recorded before this version stays
  counted as open world.
- **AFK time, inn / rest area time, city time and flight time**, always recorded separately.
- **Exclude AFK, inn or city time** in one click. Exclusions are only a display filter:
  nothing is deleted, every number is recalculated instantly, and switching an exclusion
  off gives you the original numbers back. While your current state is excluded, the
  timers show pause marks and the tooltip says so.
- **Customisable XP bar**: pick three infos among 19 (time to level, time to level + mobs
  to kill, mobs to kill, XP per hour, % of level per hour, XP to go, rested XP, time this
  level, session, total, server /played, AFK this session, average per level, time in
  zone, instance time this session, total instance time, FPS, latency, FPS + latency).
  Bar or compact box style, width, height, scale, text size, background opacity (0 % by
  default: the bar alone), hide in combat, fade when the mouse is away, hide at max level
  (not at a temporary server level cap).
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
- **Tooltip** on the bar: level progress, rested XP, time to level, mobs to kill, XP per
  hour, session, this level, current zone, played, instance time, server /played,
  averages and a breakdown of your time (world, dungeons, raids, PvP, flight, AFK, inn,
  city; only what you did). Hold **Shift** for the details (rate details, top zones of
  the level, continents, top capitals, last levels, inn / city / dungeon / raid / PvP
  times with their AFK part, deaths, account).
- **Statistics window** (`/tpl stats` or left-click on the bar) with Levels, Zones and
  Sessions tabs, for the current character, another character or the whole account. The
  window header names the exclusions in use.
- **Crash recovery**: SavedVariables are only written at logout. After a crash (or a
  session played without TruePlayed), the missing time is taken back from the server
  `/played`, split between levels with the exact XP you gained, split between activities
  using your own habits, and marked as rebuilt.
- **One record per character** (by character GUID, so two characters with the same name
  never mix). Settings are shared by the whole account.
- Addon compartment button, and an optional Data Broker feed when another addon already
  provides LibDataBroker (no library is embedded).

## Themes

Each theme changes the bar (track, fill, rested part, ornaments, background panel,
fonts and text colours), its tooltip (panel, separators, palette), and the colours and
titles of the FPS graph and of the statistics window. The 13 themes:

| Theme | `/tpl theme` name | Look | Fonts |
|---|---|---|---|
| **Futuristic** (default) | `futuriste` | Neon HUD: magenta XP, cyan rested, bevelled navy panels, scan lines, HUD brackets | Orbitron, Rajdhani |
| **Classic** | `actuel` | TruePlayed's original look, pixel for pixel: purple bar, the game's rested blue, the game's tooltip | the game font |
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
get the previous look back, choose **Classic** (`/tpl theme actuel`): it is identical to
TruePlayed before themes.

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
| `/tpl style bar\|box` | Full XP bar or compact box |
| `/tpl theme [name]` | Show the theme and the theme names, or change the theme (see [Themes](#themes)) |
| `/tpl lang [en\|fr\|auto]` | Show or choose the language of TruePlayed (applies after `/reload`, see [Languages](#languages)) |
| `/tpl afk [on\|off]` | Exclude AFK time (no argument: toggle) |
| `/tpl inn [on\|off]` | Exclude inn / rest area time (no argument: toggle) |
| `/tpl city [on\|off]` | Exclude city time (no argument: toggle) |
| `/tpl citytoggle` | Count the current zone as a city, or stop counting it |
| `/tpl played` | Summary in the chat (no server request) |
| `/tpl sync` | Ask the server for a fresh /played |
| `/tpl reset pos\|session\|rate\|char` | Reset the bar position, the session, XP per hour, or erase this character's data (with confirmation) |
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

**The game crashed. Did I lose my time?**
No. The game writes addon data only at logout or `/reload`, so a crash loses the detail of
the session. At the next login TruePlayed compares its data with the server `/played`,
re-adds the missing time, splits it between levels using the server level time and your
exact XP, splits it between activities using your own habits, attributes it to your last
known zone, and marks it as rebuilt ("incl. 35m rebuilt after a crash"). This needs a
server `/played` at login: TruePlayed asks for one (the usual `/played` lines appear once
in the chat) unless another addon already did, or you can type `/tpl sync`. The same
happens if your computer sleeps or freezes for more than 15 minutes.

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

English and French. TruePlayed follows the game's language by default. To use another
one, choose it in Options > Display > **Language (Langue)** (Auto, English, Français) or
type `/tpl lang en`, `/tpl lang fr` or `/tpl lang auto`, then reload the interface (the
**Reload UI** button under the option, or `/reload`). Names that come from the game
(zones, mobs, instances, characters, the `/played` lines) stay in the game's language,
and so do the AddOns list texts.

Translations are welcome: copy `Locales/frFR.lua` to `Locales/<code>.lua` (for example
`deDE.lua`), set its `CODE` line to that code and translate the values (keep the keys and
the registration block at the end of the file). The header of `Locales/enUS.lua` lists the
few other places a new language goes (the TOC, `C.LANGUAGES` in `Core.lua`, the language
name and `/tpl lang` alias in `Options.lua`, the `/tpl lang` help line). Then open a pull
request.

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
lua tests/check_encoding.lua # UTF-8, Latin-1 range only, no BOM, no CR
lua tests/lint51.lua         # Lua 5.1 portability and SPEC rules
lua tests/check_globals.lua  # no accidental global read or write, at run time
lua tests/check_media.lua    # theme fonts (glyph coverage, licences) and textures
```

`tests/test_theme_memory.lua` (part of the unit tests, on Lua 5.4 and 5.5 only) holds the
memory budgets of the themes. `tests/render_snapshot.lua` writes everything the bar, its
tooltip, the graph, the statistics window and the options draw, for the 13 themes in 8
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
du serveur et réparti d'après vos habitudes.

Juste après l'installation, sur un personnage qui a déjà joué, l'XP par heure et le temps
avant le niveau partent d'une estimation d'après votre /played (affichée avec un `~` :
l'XP des niveaux terminés divisée par le temps qu'ils ont pris), puis suivent votre propre
rythme après une dizaine de minutes de jeu prises en compte. Après 20 minutes de jeu sans
aucune XP, ils se figent (grisés, avec un `*`) au lieu de s'effondrer, et repartent à
votre prochain gain d'XP.

Sur la bêta de WoW Forever, bloquée au niveau 20 pour l'instant, TruePlayed repère le
plafond après 3 monstres de suite sans XP : la barre affiche `NIVEAU 20 · PLAFOND` et son
aspect du niveau maximum, l'infobulle l'explique, et tout redevient normal tout seul dès
que le serveur redonne de l'XP.

Le temps par zone (Forêt d'Elwynn, Strangleronce...) est dans l'onglet Zones de la
fenêtre de statistiques, avec le temps par continent (Kalimdor, Royaumes de l'Est,
instances) ; survolez un niveau dans l'onglet Niveaux pour voir ses zones. La barre est
affichée sans fond par défaut (option « Opacité du fond »), avec des textes contournés et
ombrés pour rester lisibles, dans la couleur de votre choix. Comme la barre d'XP du jeu,
elle prend la couleur du repos quand vous êtes reposé ; ces deux couleurs se changent
aussi (Options > Couleurs de la barre, bouton « Couleurs du thème »). Survolez les FPS ou la latence pour voir leur
graphique (30 s, 1 min ou 5 min).
La barre affiche trois infos au choix parmi 19. Tapez `/tpl` pour les options,
`/tpl stats` pour la fenêtre de statistiques et `/tpl help` pour la liste des
commandes. L'addon est entièrement traduit en français et suit la langue du jeu ; pour en
choisir une autre : Options > Affichage > « Langue (Language) » ou `/tpl lang fr|en|auto`,
puis rechargez l'interface (bouton « Recharger l'interface » ou `/reload`). Les noms
fournis par le jeu (zones, monstres) restent dans la langue du jeu.

**Thèmes** : 13 thèmes changent l'aspect de la barre, de son infobulle, du graphique et
de la fenêtre de statistiques : Futuriste (par défaut, pour tout le monde), Classique
(l'aspect d'origine, à l'identique : `/tpl theme actuel`), Heroic fantasy, Pixel rétro
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
