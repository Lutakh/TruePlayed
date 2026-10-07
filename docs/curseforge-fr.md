# Page CurseForge - français

Ce fichier contient les textes de la page du projet CurseForge (et Wago). Il n'est pas
inclus dans le zip de l'addon. Le guide `docs/PUBLISHING-fr.md` indique où va chaque texte.

**À ne pas coller sur CurseForge** : la page CurseForge est entièrement en anglais
(`docs/curseforge-en.md`). Ce fichier n'est que sa traduction, pour la relire en français
(ou pour une présentation en français ailleurs, par exemple sur Wago).

## Réglages du projet (à ne pas coller dans la description)

- **Nom** : TruePlayed (exactement : CurseForge interdit le nom du jeu ou d'une version
  dans le nom du projet ; « Forever » va dans le résumé, la description et le logo).
- **Résumé** (une phrase, « WoW Forever » en premier) : sur CurseForge, collez le résumé
  anglais de `docs/curseforge-en.md`. Version française (Wago, présentation) :
  WoW Forever : votre vrai /played - XP par heure, temps avant le prochain niveau, temps
  par niveau et par zone, sans le temps AFK, en auberge ou en ville si vous le souhaitez.
- **Version de jeu des fichiers** : Forever 1.60.1 (réglée par l'outil de publication
  d'après `## Interface: 16001` ; à choisir à la main seulement pour un envoi manuel).
- **Catégorie principale** : Quests & Leveling. **Catégorie supplémentaire** :
  Miscellaneous.
- **Licence** : MIT
- **Auteur** : Lutak
- **Logo** : 400 x 400 px, pas d'une seule couleur, sans image protégée (pas l'icône de
  montre du jeu), avec un petit badge « FOREVER ».
- **Mots-clés** : WoW Forever, Forever, played, /played, XP par heure, temps avant le
  niveau, montée en niveau, AFK, auberge, repos, temps par zone, temps en instance,
  donjons, raids, temps mort, temps de métiers, monstres à tuer, graphique FPS, thèmes,
  thèmes de classe.
- **Signalements / code source** : https://github.com/Lutakh/TruePlayed

Tout ce qui suit le trait est la **description** (Markdown), traduction de la description
anglaise : mêmes images (`media-src/curseforge/page/`, visibles une fois sur `main`).

---

![TruePlayed : votre vrai /played](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/hero.png)

Chaque seconde de jeu, comptée et triée : monde ouvert, donjons, raids, JcJ, AFK,
auberges, villes, vols, métiers, et même le temps passé mort. Retirez l'AFK d'un clic. Ou
pas.

### Sachez quand vous monterez.

XP par heure. Temps avant le niveau. Monstres à tuer. Repos compris.

### Sachez où passe votre temps.

Par niveau. Par zone. Par instance. Par personnage, ou pour tout le compte.

![13 thèmes. Un clic.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/themes.png)

Futuriste, Héroïque, Pixel, Classique, et un par classe. La barre, l'infobulle et la
fenêtre de statistiques changent ensemble.

![Maintenez Maj. Voyez tout.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/detail.png)

Votre rythme, vos zones, votre temps par continent, en donjon et en JcJ, vos morts et vos
métiers.

![Chaque niveau. Chaque zone.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/stats.png)

Tout l'historique dans une fenêtre, `/tpl stats` : le temps de chaque niveau à côté de
l'estimation faite à son début, le temps mis pour y arriver, les morts, les métiers. Une
colonne vous intrigue ? Survolez son en-tête.

![Votre barre, ou aucune.](https://raw.githubusercontent.com/Lutakh/TruePlayed/main/media-src/curseforge/page/compact.png)

Gardez votre barre d'XP : utilisez le bouton de la minicarte, ou un mini affichage dans un
coin de l'écran, avec seulement ce que vous choisissez.

### Léger. Fiable.

Aucun code à chaque image, un seul minuteur par seconde. Un plantage ne perd rien : le
temps manquant revient du serveur à la connexion suivante.

### Dans votre langue.

English, Français, Deutsch, Español, Italiano, Português, Русский, 한국어, 简体中文, 繁體中文.

---

## Pour commencer

1. Installez, puis **relancez le jeu** (les nouveaux fichiers ne se chargent qu'au
   démarrage).
2. Survolez la barre, le bouton de la minicarte ou le mini affichage.
3. Clic droit pour le menu. `/tpl` pour toutes les options.

| Commande | |
|---|---|
| `/tpl` | Options |
| `/tpl stats` | Statistiques |
| `/tpl theme` | Thèmes |
| `/tpl minimap` | Bouton de la minicarte oui / non |
| `/tpl mini` | Mini affichage oui / non |
| `/tpl afk` `inn` `city` | Retirer ce temps, ou le compter à nouveau |
| `/tpl help` | Toutes les commandes |

## FAQ

**Pourquoi un écart avec /played ?** Il n'y en a pas, tant que vous ne retirez rien.
Ensuite, c'est /played moins ce temps. Rien n'est jamais effacé : réactivez-le et les
chiffres reviennent.

**Que signifie `~` ?** Une estimation tirée de votre /played serveur, utilisée les dix
premières minutes après l'installation.

**Textures ou polices manquantes ?** Quittez et relancez le jeu : `/reload` ne suffit pas
après une installation ou une mise à jour.

**WTFix ?** Ouvrez `/wtfix` et décochez TruePlayed. **RXPGuides ?** Compatible.

## Contact

[Signaler un bug](https://github.com/Lutakh/TruePlayed/issues/new) · [Proposer une idée](https://github.com/Lutakh/TruePlayed/issues/new) ·
[Code source](https://github.com/Lutakh/TruePlayed)

Les traductions ont été faites sans locuteurs natifs : vos corrections sont les bienvenues.

TruePlayed a été développé avec l'aide de Claude (Anthropic), qui a aussi dessiné le logo.
