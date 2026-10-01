# Page CurseForge - français

Ce fichier contient les textes de la page du projet CurseForge (et Wago). Il n'est pas
inclus dans le zip de l'addon. Le guide `docs/PUBLISHING-fr.md` indique où va chaque texte.

CurseForge demande des noms et catégories en anglais : le nom et le résumé du projet
restent donc en anglais (voir `docs/curseforge-en.md`). La description ci-dessous peut
être ajoutée sous la description anglaise, ou servir pour une présentation en français.

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
  donjons, raids, monstres à tuer, graphique FPS, thèmes, thèmes de classe.
- **Signalements / code source** : https://github.com/Lutakh/TruePlayed

Tout ce qui suit le trait est la **description** (Markdown).

---

# TruePlayed pour WoW Forever - votre vrai /played

**Votre vrai /played : sans le temps AFK, en auberge ou en ville, à vous de choisir.**

Le `/played` du jeu compte tout : la pause café, la soirée à discuter à l'auberge, les
allers-retours à l'hôtel des ventes. TruePlayed enregistre chaque seconde de jeu, sait ce
que vous faisiez et vous laisse choisir ce qui compte. Il montre à quelle vitesse vous
progressez vraiment sur **WoW Forever** : **XP par heure**, **temps avant le prochain
niveau**, **monstres à tuer**, **temps par niveau**, **temps par zone** et, à tout
niveau, **votre temps en donjon, en raid et en JcJ**.

## Captures d'écran

**SECTION À SUPPRIMER AVANT DE COLLER (ou remplacez les lignes ci-dessous par de vraies images).**

<!-- Remplacer chaque ligne par une VRAIE capture prise en jeu (une image générée ou
     retouchée par IA doit porter une mention visible sur CurseForge). 3 à 5 images. -->

1. *La barre sous le personnage : temps avant le niveau et monstres à tuer, XP par heure,
   FPS et latence (thème Futuriste, puis reposé).*
2. *Les thèmes côte à côte : Futuriste, Classique, Heroic fantasy, Pixel rétro et les neuf
   thèmes de classe.*
3. *L'infobulle, normale et détaillée (touche Maj).*
4. *Le graphique des FPS et de la latence au survol.*
5. *La fenêtre de statistiques, onglet Zones avec les instances les plus jouées et les
   capitales.*
6. *Le panneau d'options avec le thème, les exclusions et la couleur du texte.*

## Fonctions

- **13 thèmes** : la barre, son infobulle, le graphique des FPS et la fenêtre de
  statistiques changent d'aspect ensemble. **Futuriste** (néon, par défaut),
  **Classique** (l'aspect d'origine), **Heroic fantasy**, **Pixel rétro**, et un thème par
  classe : **Guerrier**, **Paladin**, **Chasseur**, **Voleur**, **Prêtre**, **Chaman**,
  **Mage**, **Démoniste**, **Druide**, chacun avec son cadre, ses ornements, ses polices et
  son infobulle. **Classe (auto)** donne à chaque personnage le thème de sa classe.
  Changez de thème dans les options, le menu du clic droit ou avec `/tpl theme` ; vos
  propres couleurs restent prioritaires. Polices fournies sous licence SIL Open Font
  License.
- **XP par heure et temps avant le prochain niveau**, en tenant compte de l'XP de repos.
  Conservés par personnage : ils résistent au `/reload`, au redémarrage et aux plantages,
  et ne repartent pas de zéro à chaque connexion. Juste après l'installation, ils partent
  d'une estimation d'après votre /played (affichée avec un `~`) au lieu de rester vides.
  Après 20 minutes de jeu sans aucune XP, ils se figent (grisés, avec un `*`) au lieu de
  s'effondrer : pas de temps absurde avant le niveau après des heures bloqué.
- **Plafonds de niveau temporaires** (bêta de WoW Forever) : après 3 monstres de suite
  sans XP, la barre affiche « NIVEAU 20 · PLAFOND », l'infobulle l'explique, et tout
  redevient normal tout seul dès que l'XP revient.
- **Monstres à tuer** : combien de monstres comme vos 10 derniers (leur XP moyenne) il vous
  reste pour monter de niveau, en tenant compte de l'XP de repos (un monstre tué reposé
  rapporte le double) : « ~5 h 05 · 38 monstres » sur la barre, « Monstres à tuer : ~38
  (moyenne : 47 XP, dernier : 30 XP) » dans l'infobulle.
- **L'XP de repos comme sur la barre du jeu** : la barre prend la couleur du repos quand
  vous êtes reposé, avec une partie plus claire jusqu'où va votre XP de repos ;
  « Reposé : 11 600 XP (50 %) » dans l'infobulle.
- **Le temps en instance, une vraie statistique** : donjons, raids et JcJ (champs de
  bataille, arènes) comptés à part du monde, AFK compris. Lignes dans l'infobulle,
  **instances les plus jouées** dans l'onglet Zones (personnage ou compte), une colonne
  « Inst. » dans les onglets Niveaux et Sessions, totaux du compte et deux infos pour la
  barre. Pensé aussi pour les joueurs au niveau maximum.
- **Temps par niveau**, avec l'historique complet (temps, temps serveur, XP par heure, AFK,
  auberge, ville, instances, zone principale, date).
- **Temps moyen par niveau** : global, sur les 5 derniers niveaux et sur tout le compte.
- **Temps par zone** (Forêt d'Elwynn, Strangleronce...) : un onglet Zones avec chaque
  zone jouée (temps filtré, temps brut, AFK, XP), les **zones de chaque niveau** (survolez
  un niveau dans l'onglet Niveaux), votre **temps par continent** (Kalimdor, Royaumes de
  l'Est, instances) et le temps dans la zone actuelle dans l'infobulle. Les exclusions
  s'appliquent aussi aux zones.
- **Temps de jeu total et de session**, à côté du /played du serveur en direct.
- **Temps AFK**, toujours compté à part.
- **Temps en auberge / zone de repos et temps en ville**, toujours comptés à part.
- **Vos capitales les plus fréquentées**, avec la part AFK.
- **Exclure le temps AFK**, **exclure le temps en auberge**, **exclure le temps en ville** :
  un clic dans le menu du clic droit, les options ou une commande. Rien n'est effacé, tout
  est recalculé immédiatement, et désactiver l'exclusion rend les chiffres d'origine.
  Quand votre état actuel est exclu, les compteurs affichent un signe de pause.
- **Choisissez ce qu'affiche la barre** : trois infos parmi 19 (temps avant le niveau,
  monstres à tuer, XP par heure, % du niveau par heure, XP restante, XP de repos, temps sur
  ce niveau, session, total, /played du serveur, AFK de la session, moyenne par niveau,
  temps dans la zone, temps en instance, FPS, latence...). Taille, échelle, opacité du
  fond (0 % par défaut), masquage en combat, estompage, masquage au niveau maximum. Les
  textes ne se chevauchent jamais, même sur une barre étroite.
- **Des textes lisibles** : contour fin et ombre par défaut (contour aucun / fin / épais),
  et la couleur de texte de votre choix avec le sélecteur de couleur du jeu.
- **Couleurs de la barre** : la couleur de la barre d'XP et celle de l'XP de repos au
  choix, quel que soit le thème, avec un bouton « Couleurs du thème » pour revenir à
  celles du thème.
- **FPS et latence** sur la barre, mesurés seulement quand ils sont affichés, en vert /
  jaune / rouge (ou dans votre couleur de texte). **Survolez-les pour voir un graphique**
  des 30 dernières secondes, de la dernière minute ou des 5 dernières minutes, avec le
  minimum, la moyenne, le maximum et la valeur à l'instant pointé. Le jeu ne rafraîchit
  la latence qu'environ toutes les 30 secondes : le graphique la montre honnêtement en
  paliers.
- **Récupération après plantage** : le jeu n'enregistre les données des addons qu'à la
  déconnexion, un plantage faisait donc perdre la session. TruePlayed reprend le temps
  manquant du /played du serveur à la connexion suivante, le répartit entre les niveaux
  d'après l'XP exacte gagnée et entre les activités d'après vos habitudes, et le signale
  comme reconstitué.
- **Des données par personnage** (deux personnages du même nom ne se mélangent jamais),
  des réglages communs au compte, et une vue « compte » dans la fenêtre de statistiques.
- **Léger** : aucun code exécuté à chaque image, un seul minuteur d'une seconde, rien
  n'est construit avant d'être ouvert. `/tpl perf` affiche la mémoire (code plus données
  enregistrées de tous vos personnages) et le processeur utilisés.

## Commandes

| Commande | Effet |
|---|---|
| `/tpl` | Options |
| `/tpl stats` | Fenêtre de statistiques (`levels`, `zones`, `sessions`) |
| `/tpl lock` / `unlock` | Verrouiller ou déplacer la barre |
| `/tpl show` / `hide` | Afficher ou masquer la barre |
| `/tpl theme [nom]` | Afficher ou changer le thème (`futuriste`, `actuel`, `heroic`, `pixel`, `class`, `warrior`, `paladin`, `hunter`, `rogue`, `priest`, `shaman`, `mage`, `warlock`, `druid`) |
| `/tpl lang [valeur]` | Afficher ou choisir la langue de TruePlayed (`auto`, `fr`, `en`, `de`, `es`, `mx`, `it`, `pt`, plus `ru`, `ko`, `cn`, `tw` sur un client dans cette langue ; après `/reload`) |
| `/tpl afk` / `inn` / `city` `[on\|off]` | Exclusions (sans argument : bascule) |
| `/tpl citytoggle` | Compter la zone actuelle comme une ville (ou non) |
| `/tpl played` | Récapitulatif dans le chat |
| `/tpl sync` | Rafraîchir le /played du serveur |
| `/tpl reset pos` / `session` / `rate` / `char` | Réinitialisations (l'effacement d'un personnage demande confirmation) |
| `/tpl perf` | Mémoire et processeur utilisés |
| `/tpl help` | Toutes les commandes |

## Questions fréquentes

**Pourquoi le chiffre diffère-t-il du /played ?** Sans exclusion, c'est exactement le
/played du serveur. Avec des exclusions, c'est le /played du serveur moins le temps AFK,
en auberge ou en ville enregistré par TruePlayed.

**Et le temps joué avant l'installation ?** Il ne peut pas être découpé : il est affiché à
part (« Avant installation / non suivi ») et n'est jamais exclu. Les totaux et la moyenne
globale l'incluent quand même, et l'infobulle le précise.

**Comment retrouver l'ancien aspect ?** Choisissez le thème **Classique** (Options >
Affichage > Thème, clic droit sur la barre > Thème, ou `/tpl theme actuel`) : c'est
l'aspect de TruePlayed d'avant les thèmes, inchangé.

**Des textures ou des polices de thème manquent.** Relancez complètement le jeu après
une installation ou une mise à jour : le jeu ne charge les nouvelles polices et textures
qu'au démarrage, pas au `/reload`.

**Que signifie le `~` devant l'XP par heure ?** C'est une estimation d'après votre
/played, utilisée juste après l'installation, jusqu'à ce que TruePlayed ait mesuré une
dizaine de minutes de votre propre jeu. L'infobulle le précise.

**Comment sont comptés les monstres à tuer ?** D'après l'XP moyenne de vos 10 derniers
monstres tués (sans leur bonus de repos), l'XP qu'il vous reste et votre XP de repos.
L'XP de quête et d'exploration ne compte pas comme un monstre tué.

**Pourquoi mon ancien temps en donjon apparaît-il comme du monde ?** Les donjons, raids
et JcJ sont comptés à part depuis la version 1.0.0 ; le temps en instance
d'avant ne peut pas être distingué.

**Pourquoi quelques minutes AFK comptent-elles comme actives ?** Le jeu ne vous passe AFK
qu'après environ 5 minutes sans action ; ces minutes restent comptées comme actives.

**Un plantage me fait-il perdre du temps ?** Non : voir « Récupération après plantage ».
Il faut un /played du serveur à la connexion, que TruePlayed demande (les lignes
habituelles s'affichent une fois dans le chat) si aucun autre addon ne l'a fait. Vous
pouvez désactiver cette demande dans les options et taper `/tpl sync` à la place.

**Qu'est-ce qui compte comme ville ?** Toute la carte d'une capitale, pas seulement son
auberge. Un vol au-dessus d'une capitale compte comme vol. `/tpl citytoggle` ajoute ou
retire la zone actuelle.

**Compatible avec RXPGuides ?** Oui. RXPGuides demande le /played à la connexion et
TruePlayed se contente d'écouter. Un /played tapé dans les 3 secondes environ qui suivent
la demande de RXPGuides peut être masqué une fois par RXPGuides.

## Compatibilité

- **WoW Forever** 1.60.x (interface 16001).
- **Classic Era** : prévu.
- Fonctionne avec RXPGuides. Avec WTFix : ouvrez /wtfix et décochez TruePlayed (sinon
  WTFix remet une ancienne copie de ses données à chaque chargement).
- Flux Data Broker facultatif quand votre interface fournit déjà LibDataBroker, et bouton
  dans le menu des addons.

## Langues

Toutes les langues du jeu : français, English, Deutsch, Español (EU), Español (AL),
Italiano, Português (BR), Русский, 한국어, 简体中文, 繁體中文. TruePlayed suit la langue du
jeu ; pour en choisir une autre : Options > Affichage > Langue (Language) ou `/tpl lang de`,
`es`, `it`... (`/tpl lang` seul les liste), puis rechargez l'interface. Le russe, le coréen
et le chinois ne sont proposés que sur un client du jeu dans cette langue. Les noms
fournis par le jeu (zones, monstres) restent dans la langue du jeu. Les corrections de
joueurs natifs sont les bienvenues sur GitHub.

Le style « encadré compact » de la barre a disparu : la barre d'XP est le seul affichage
(un encadré enregistré par une version précédente s'affiche en barre).

## Problèmes et suggestions

Signalez les problèmes sur GitHub : https://github.com/Lutakh/TruePlayed/issues
(indiquez la version de l'addon, la langue du jeu et le texte de l'erreur Lua).
