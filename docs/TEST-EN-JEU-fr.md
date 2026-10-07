# Premier test en jeu de TruePlayed (WoW Forever)

Une petite fiche pour votre premier essai, dans l'ordre. Comptez une heure de jeu normal.
Notez ce qui vous surprend : il n'y a pas de mauvaise remarque.

## Lot 8 (partie A) : temps mort, temps de métiers, estimation par niveau

Cette mise à jour **ajoute 1 fichier** (`Activity.lua`) : recopiez le dossier, puis
**quittez et relancez complètement le jeu** (un `/reload` ne charge pas les nouveaux
fichiers ; sans redémarrage, le temps mort et les métiers ne seraient pas comptés).
L'affichage est minimal pour l'instant (une refonte de l'infobulle et de la fenêtre
suivra) : on vérifie surtout que les chiffres sont justes.

### Le temps mort

1. Notez l'heure, puis faites-vous tuer (un monstre trop fort, ou une chute).
2. Restez mort une minute, libérez l'esprit, courez en fantôme jusqu'au corps (au moins
   deux minutes, si possible en traversant une autre zone), puis ressuscitez. Recommencez
   une deuxième fois, en ressuscitant cette fois auprès d'un guide spirituel ou par un
   sort de résurrection si vous en avez l'occasion.
3. Survolez la barre : la ligne « Répartition » contient « Mort x % » (avec sa propre
   couleur dans la jauge des thèmes qui en ont une).
4. Maj : la ligne « Morts » donne le nombre et le temps sur une seule ligne, par exemple
   « Morts 2 (6 min) ». Le temps doit correspondre à ce que vous avez chronométré (de la
   mort jusqu'au retour à la vie, course du fantôme comprise).
5. Avec les exclusions AFK, auberge et ville activées, le temps mort reste compté
   (jamais en pause). Mettez-vous AFK pendant que vous êtes mort : ça reste du temps mort.
6. Fenêtre de statistiques, onglet Niveaux : la fenêtre s'élargit et une colonne
   « Mort » montre, pour le niveau en cours, « 6 min (2) » (temps, nombre de morts).
   Aucune colonne ne doit en chevaucher une autre. Les niveaux plus anciens montrent « - »
   (ou seulement « (n) » s'ils avaient des morts comptées par une version précédente).
7. Chasseurs : la Feinte de mort ne doit **pas** compter comme du temps mort.

### Le temps de métiers

1. **Artisanat** : ouvrez une fenêtre de métier (cuisine, forge, couture, secourisme...)
   et restez immobile une minute, puis fabriquez quelques objets (« Tout créer ») ; fermez
   la fenêtre pendant la file d'attente : la suite de la file compte encore.
   Maj sur la barre : la ligne « Métiers » apparaît avec ce temps, et « Métiers x % »
   dans la répartition.
2. Ouvrez la fenêtre et **courez** avec elle ouverte, ou **combattez** : ce temps ne doit
   pas compter en métiers (il revient au monde, à la ville...).
3. **Enchantement** : la fenêtre d'enchantement compte ; chasseurs, la fenêtre de
   dressage des familiers (« Dressage des bêtes ») ne compte **pas**.
4. **Récolte** : cueillez une herbe, minez un filon, dépecez une bête : l'incantation puis
   environ 5 secondes (le butin) comptent en métiers. Une récolte interrompue (vous
   bougez) ne compte que l'incantation.
5. **Pêche** : pêchez quelques minutes : tout le temps de pêche compte, plus 5 secondes
   après chaque prise.
6. **Secourisme** : appliquez un bandage : les 8 secondes comptent, sans délai après.
7. **Désenchantement** et **crochetage** (voleurs) : comptent aussi, avec les 5 secondes.
8. En capitale, l'artisanat compte en métiers et non en ville (« Ville » ne doit pas
   augmenter pendant ce temps). Si vous passez AFK avec la fenêtre ouverte, c'est de
   l'AFK.
9. Un sort ordinaire (boule de feu, pierre de foyer) ne doit jamais compter en métiers.
10. Tout cela fonctionne dans la langue du jeu (les sorts sont reconnus par leur nom
    traduit) : si vous jouez en français, vérifiez la cueillette (« Cueillette ») et la
    pêche.

### Estimation au début de chaque niveau

1. Passez un niveau en tuant des monstres (avec au moins une dizaine de minutes de jeu
   avant, pour que l'XP par heure soit mesurée).
2. Juste après le passage de niveau, notez le temps « Prochain niveau » de l'infobulle.
3. Onglet Niveaux : la colonne « Estim. » du nouveau niveau montre ce même temps. Les
   niveaux atteints avant cette mise à jour n'en ont pas (« - »).

### Continents de moins d'une minute

1. Maj sur la barre, et onglet Zones : un continent avec quelques secondes seulement
   (« Autres < 1 min », souvent dû à un écran de chargement) n'apparaît plus. Le temps reste
   compté dans les totaux.

### À surveiller

- `/tpl perf` : la mémoire ne doit pas grimper pendant que vous êtes mort, en fantôme,
  en train de pêcher ou avec une fenêtre de métier ouverte.
- Notez tout écart entre votre chronomètre et les temps affichés (mort, métiers), et
  toute erreur Lua.

## Mise à jour suivante (lot 7) : bouton de la minicarte et mini-affichage

Cette mise à jour **ajoute 2 fichiers** (`MinimapButton.lua`, `MiniDisplay.lua`) : recopiez
le dossier, puis **quittez et relancez complètement le jeu** (un `/reload` ne charge pas
les nouveaux fichiers ; sans redémarrage, `/tpl minimap` répondrait par une erreur Lua).

### Le bouton de la minicarte

1. Au chargement, un bouton rond avec la montre de poche de TruePlayed apparaît au bord
   de la minicarte, en bas à gauche.
2. Survolez-le : la même infobulle que la barre ; Maj pour les détails. La dernière ligne
   dit « Clic : statistiques ».
3. Clic gauche : la fenêtre des statistiques s'ouvre ; un deuxième clic la ferme.
4. Clic droit : le menu de la barre, ouvert sur le bouton (exclusions, Thème, Verrouiller,
   Afficher, Statistiques, Masquer, Options).
5. Glissez-le (clic gauche maintenu) : il suit la souris ; relâchez-le, il se recolle au
   bord de la minicarte à l'endroit visé. Faites un `/reload` : il reste à sa place. Le
   relâchement ne doit pas ouvrir les statistiques.
6. Options > « Bouton de la minicarte et mini-affichage » : cochez « Verrouiller le
   bouton de la minicarte » : il ne se déplace plus. Changez « Clic gauche du bouton » :
   Options, « Basculer la barre d'XP », « Basculer le mini-affichage » ; la dernière ligne
   de l'infobulle suit le choix, et le clic fait ce qu'elle annonce.
7. `/tpl minimap` le masque (le chat dit comment le retrouver), `/tpl minimap` le réaffiche.
   Le « Masquer » de son menu masque le bouton, pas la barre.
8. Si vous avez un addon de minicarte carrée ou un addon qui range les boutons : notez où
   se place le bouton et s'il est rangé avec les autres.

### Le mini-affichage

1. `/tpl mini` (ou Options, ou clic droit > Afficher > Mini-affichage) : un petit cadre
   apparaît en haut au centre de l'écran, avec « temps avant le niveau · monstres » et
   l'XP par heure, et une fine barre d'XP en dessous.
2. Glissez-le dans un coin ; `/reload` : il y reste. Cochez « Verrouiller la position » :
   il ne bouge plus.
3. Survol : l'infobulle de la barre ; clic : les statistiques ; clic droit : le menu, dont
   « Masquer » masque le mini-affichage seulement.
4. Options : Info 1 / 2 / 3 (la même liste que la barre ; « Rien » pour 2 et 3),
   Disposition (« Sur une ligne » / « Empilée »), Progression d'XP (Aucune, Pourcentage,
   Barre fine, Pourcentage + barre), Échelle, Opacité du fond, Masquer en combat, Estomper hors survol.
   **Aucun texte ne doit en chevaucher un autre ni dépasser du cadre**, quelles que soient
   les infos (essayez « FPS + latence », « Temps de jeu (filtré) », « Temps dans la zone actuelle »).
5. Changez de thème : le cadre prend les polices, les couleurs et le fond du thème.
   Couleur du texte, contour et ombre (section Textes) s'appliquent aussi au cadre.
6. Masquez la barre (`/tpl hide`) : bouton et mini-affichage continuent de tout donner
   (infobulle, statistiques, menu), et leurs chiffres avancent chaque seconde.
7. Au niveau maximum, une seule info dit « Niveau max », les autres infos d'XP
   disparaissent.
8. `/tpl perf` avant / après avoir activé le mini-affichage : la mémoire ne doit pas
   grimper au fil des minutes.

## Lot 6 : toutes les langues du jeu, fin de l'encadré compact

Cette mise à jour **ajoute 9 fichiers** (`Locales/deDE.lua` ... `Locales/zhTW.lua`) :
recopiez le dossier, puis **redémarrez complètement le jeu** (un `/reload` ne charge pas
les nouveaux fichiers).

### Les nouvelles langues, sans les parler

Le but n'est pas de juger les traductions, mais de vérifier que rien ne casse et que rien
n'est coupé. Pour chaque langue :

1. Options > Affichage > « Langue (Language) » : la liste propose « Auto », « English »,
   « Français », « Deutsch », « Español (EU) », « Español (AL) », « Italiano » et
   « Português (BR) ». Le russe, le coréen et le chinois n'apparaissent pas sur un client
   français : c'est voulu (la police du jeu ne sait pas les afficher).
2. Choisissez la langue, cliquez « Recharger l'interface » (le bouton change de nom avec
   la langue, il reste à la même place sous la liste).
3. Regardez, sans rien lire : la barre (en haut et en bas), l'infobulle (survol simple
   puis Maj), le graphique (survol des FPS), la fenêtre `/tpl stats` (les trois onglets et
   la vue « compte » avec les flèches), les options (tout le défilement) et le menu du clic
   droit. **Aucun texte ne doit être coupé** (pas de « ... » en fin de ligne, sauf un nom
   de zone très long dans la fenêtre, comme avant), **aucun texte ne doit en chevaucher un
   autre**, et **aucune erreur Lua** ne doit apparaître.
4. Tapez `/tpl help` et `/tpl lang` : le chat répond dans la langue choisie ; la liste
   donnée par `/tpl lang` est `auto, en, fr, de, es, mx, it, pt`.
5. Testez aussi une barre étroite (Largeur 150) avec une taille de texte de 16 : rien ne
   dépasse de la barre.
6. Revenez avec `/tpl lang fr` puis `/reload` (ou choisissez « Français » dans la liste).

Faites-le au moins en Deutsch (les mots les plus longs), puis rapidement dans les autres.
Notez la langue, le thème et une capture d'écran de tout texte coupé : il sera raccourci.
Sans client russe, coréen ou chinois, ces trois langues ne peuvent pas être vues en jeu :
elles sont vérifiées par les tests hors jeu (largeurs mesurées avec une marge).

### L'encadré compact a disparu

- Options > Affichage : plus de liste « Style » sous « Afficher la barre ».
- Clic droit sur la barre : plus d'entrée « Style » ; « Thème » vient juste après les
  exclusions.
- `/tpl style box` répond « Commande inconnue » ; `/tpl help` n'a plus de ligne
  `/tpl style`.
- Si vous utilisiez l'encadré compact, la barre d'XP s'affiche à sa place, avec vos autres
  réglages (infos, position, couleurs), sans erreur Lua.

## Mise à jour du 1er octobre (lot 5) : langue, moyenne des monstres, mémoire

Cette mise à jour n'ajoute aucun fichier : recopiez le dossier comme d'habitude, puis un
`/reload` suffit. Si vous n'aviez pas encore la version avec les thèmes, faites d'abord la
section « Thèmes » plus bas (redémarrage complet du jeu).

### La langue de TruePlayed

- **L'option** : Options > Affichage, juste après « Masquer au niveau max », une liste
  « Langue (Language) » avec « Auto », « English » et « Français » (chaque langue écrite
  dans sa propre langue), une note, puis un bouton « Recharger l'interface ». « Auto »
  est coché : TruePlayed suit la langue du jeu, comme avant.
- **Passer en anglais** : choisissez « English ». Rien ne change tout de suite, c'est
  normal. Cliquez « Recharger l'interface » : la barre (`LEVEL 20`, `XP:`), l'infobulle
  (survol simple et Maj), la fenêtre `/tpl stats` (les trois onglets), les options, le
  menu du clic droit et les messages du chat (`/tpl help`, `/tpl played`) sont en
  anglais. Les noms de zones et d'instances restent en français : ils viennent du jeu.
  Notez tout texte resté en français qui ne vient pas du jeu.
- **Revenir** : `/tpl lang fr` (le chat dit qu'il faut recharger), puis `/reload` : tout
  est de nouveau en français. `/tpl lang auto` fait de même en suivant la langue du jeu ;
  `/tpl lang` seul affiche le choix en cours ; `/tpl lang xx` répond « Commande
  inconnue ». `/tpl help` affiche la ligne de `/tpl lang`.
- **Mémorisé** : en anglais, déconnectez-vous puis reconnectez-vous (et changez de
  personnage) : l'anglais est gardé, pour tous vos personnages.
- **Infobulle jamais coupée en anglais** : en English, survolez la barre (simple et Maj)
  dans quelques thèmes (Futuriste, Pixel rétro, Démoniste) : aucune ligne ne finit par
  « ... ».

### Monstres à tuer : la moyenne des 10 derniers

- **La ligne de l'infobulle** devient `Monstres à tuer : ~38 (moyenne : 47 XP, dernier :
  30 XP)`. Juste après la mise à jour, la moyenne part de votre dernier monstre connu
  (moyenne = dernier).
- **Le nombre bouge moins** : tuez des monstres de niveaux différents (un plus bas, un
  plus haut). « dernier » suit chaque monstre ; « moyenne » ne bouge que d'un dixième de
  l'écart, et le nombre de monstres (infobulle et `~5 h 05 · 38 monstres` sur la barre)
  saute beaucoup moins qu'avant.
- **Plusieurs monstres d'un coup** (dégâts de zone, ou en groupe) : chacun compte dans la
  moyenne.
- **Quêtes et découvertes** : rendre une quête ou découvrir un lieu ne change ni
  « moyenne » ni « dernier ».
- **Gardé par personnage** : `/reload`, puis déconnexion et reconnexion : mêmes moyenne et
  dernier. Sur un autre personnage, sa propre moyenne (ou « calculé dès votre prochain
  monstre tué » s'il n'a encore rien tué).
- **Reposé** : avec de l'XP de repos, le nombre reste plus petit qu'hors repos, comme
  avant.
- **Jamais coupée** : en français, dans chaque thème, la ligne « Monstres à tuer » tient
  en entier (l'infobulle peut s'élargir de quelques pixels si les nombres sont très
  grands).

### Mémoire

- **Avant de mettre à jour**, si vous le pouvez : `/tpl perf` avec le thème Futuriste et
  notez la ligne « Mémoire ». **Après la mise à jour** et un `/reload`, même personnage,
  même thème : `/tpl perf` doit afficher environ 0,15 à 0,2 Mo de moins.
- **Aucun changement visible** : la mémoire gagnée ne change rien à l'aspect. Passez par
  les 14 choix du clic droit > Thème : chaque thème est exactement comme avant (barre,
  infobulle simple et Maj, graphique des FPS, fenêtre). Classique reste identique à
  l'ancien aspect.
- **Changer de thème** : 10 changements de suite, attendez une minute, `/tpl perf` : la
  mémoire ne grimpe pas d'une série à l'autre, et la ligne « Tic » reste sous 0,05 ms.
- Aucune erreur Lua au chargement ni en changeant de thème.

## Thèmes : la nouvelle mise à jour, à tester en premier

TruePlayed a maintenant 13 thèmes : ils changent la barre, son infobulle, le graphique des
FPS et la fenêtre de statistiques. **Futuriste** est le thème par défaut, pour tout le
monde. **Classique** est l'aspect d'avant, à l'identique.

**Les sections 0 à 5 plus bas décrivent l'aspect Classique** (barre violette, infobulle
du jeu). Pour les refaire telles quelles, passez d'abord en Classique : `/tpl theme actuel`.
Les boutons « Couleurs d'origine » s'appellent maintenant « Couleurs du thème ».

### Installer : redémarrage complet obligatoire

Cette mise à jour ajoute des dossiers (`Media`, `Themes`) et des fichiers. Recopiez le
dossier, en laissant de côté ce qui ne sert qu'au développement :

```
cd ~/Documents/claude/TruePlayed/TruePlayed_on_github
git pull
DEST="/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/TruePlayed"
mkdir -p "$DEST"
rsync -a --delete --exclude '.*' --exclude 'tests' --exclude 'docs' --exclude 'design' \
  --exclude 'tools' --exclude 'media-src' ./ "$DEST/"
```

Vérifiez que `AddOns/TruePlayed/Media/Fonts` contient les polices (`.ttf`) et le dossier
`LICENSES`, et que `AddOns/TruePlayed/Media/Themes` existe. Puis **quittez complètement le
jeu et relancez-le** : un `/reload` ne charge ni les nouveaux fichiers, ni les polices, ni
les textures.

### Premier coup d'œil

- **Futuriste par défaut** : en vous connectant, la barre est néon (XP magenta, repos cyan,
  crochets aux deux bouts, graduations tous les 10 %), `NIVEAU 20` en lettres carrées
  (Orbitron), les nombres en Rajdhani. Vos réglages (largeur, infos, exclusions, position)
  n'ont pas bougé ; la barre peut sembler décalée de quelques pixels, car le cadre du
  thème est un peu plus grand.
- **Classique = l'ancien aspect, à l'identique** : `/tpl theme actuel`. Comparez avec une
  capture d'écran prise avant la mise à jour (même largeur, même taille de texte) : la
  barre, ses textes et l'infobulle doivent être exactement les mêmes, au pixel près.
- **Les trois façons de changer** :
  - Options (`/tpl`) > Affichage > **Thème** : c'est le premier réglage de la section,
    suivi de deux notes (ce que change le thème, et le redémarrage après une mise à jour).
  - Clic droit sur la barre > **Thème**, juste sous les exclusions : les 14 choix, celui en
    cours coché.
  - `/tpl theme` : le chat affiche `Thème : Futuriste. Disponibles : futuriste, actuel,
    heroic, ...`. `/tpl theme mage` passe en Mage et affiche `Thème : Mage`.
    `/tpl theme truc` répond « Commande inconnue ». `/tpl help` a une ligne
    `/tpl theme [nom] - affiche ou change le thème`.
  - Le changement est immédiat, sans `/reload` ; une infobulle ouverte se ferme.
- **Classe (auto)** : sur votre druide, « Classe (auto) » donne le thème Druide. Sur un
  personnage d'une autre classe, son propre thème de classe, sans rien changer : le
  réglage est commun au compte, le thème suit le personnage.

### La fiche à faire pour chaque thème

Les 13 thèmes : Futuriste, Classique, Heroic fantasy, Pixel rétro, Guerrier, Paladin,
Chasseur, Voleur, Prêtre, Chaman, Mage, Démoniste, Druide (plus « Classe (auto) »). Pour
chacun, prenez une capture de la barre et de l'infobulle (Maj enfoncée) et comparez avec
sa planche de maquettes : les couleurs, les polices, le cadre et les ornements doivent y
ressembler (les flous, ombres multiples et espacements de lettres des maquettes ne
peuvent pas être reproduits en jeu : c'est normal).

1. **Aucun carré vide à la place d'une lettre** : regardez les accents (é è ê à ç), les
   guillemets « », le point médian `·` (`NIVEAU 20 · PLAFOND`, `XP : 58 / 23 200 · ~5,7k/h`)
   et l'espace insécable des nombres (`23 200`), sur la barre, dans l'infobulle (zone,
   répartition), dans le titre du graphique et dans la fenêtre `/tpl stats`.
2. **Largeur et taille du texte** : Options > Largeur à 150, 360 puis 600 px, et Taille du
   texte à 9 puis 16. Aucun texte ne chevauche un autre ou un ornement, les ornements
   restent collés aux bouts de la barre, rien n'est coupé.
3. **Reposé, niveau maximum, plafond** : reposé (déconnexion à l'auberge), la barre prend
   la couleur du repos du thème, avec la partie plus claire jusqu'à la fin du repos. Au
   plafond de la bêta (3 monstres sans XP, voir section 0), la barre est pleine et
   atténuée, avec `PLAFOND` (ou `Plafond` selon le thème) après le niveau.
4. **Opacité du fond** à 0 %, 50 % puis 100 % (Options > Textes) : à 0 % la barre seule ;
   à 50 % et 100 %, le panneau du thème apparaît derrière (cadre, coins, filets) et
   s'opacifie.
5. **Infobulle** : survol simple puis Maj enfoncée. Classique utilise l'infobulle du jeu ;
   les autres thèmes ont leur propre cadre (titre, séparateurs et, selon le thème, une
   jauge de répartition en couleurs et des pointillés entre libellés et valeurs). Le
   contenu est le même que dans l'infobulle classique, dans le même ordre ; rien ne
   déborde du cadre.
6. **Graphique et fenêtre** : survolez les FPS (graphique) puis ouvrez `/tpl stats` :
   le titre prend la police du thème, les couleurs suivent le thème. Les tableaux gardent
   la police du jeu (c'est voulu). Notez si un titre est coupé.

### Changer de thème, couleurs, mémoire

- **Changer souvent, hors combat** : passez par les 14 choix du clic droit l'un après
  l'autre, deux fois. Aucune erreur Lua, la barre reste à sa place, les textes à jour.
- **Vos couleurs gagnent** : Options > Couleurs de la barre. Les carrés de couleur
  montrent les couleurs du thème en cours et changent quand vous changez de thème.
  Choisissez une couleur d'XP : elle reste la même quel que soit le thème. « Couleurs du
  thème » remet celles du thème (même chose pour la couleur du texte).
- **La mémoire** : `/tpl perf` et notez la ligne « Mémoire ». Changez 10 fois de thème,
  attendez une minute, puis `/tpl perf` à nouveau : la mémoire peut avoir un peu monté
  juste après les changements, mais elle ne doit pas grimper à chaque nouvelle série de 10
  changements. Pendant la minute de mesure, la ligne « Tic » reste sous 0,05 ms en
  moyenne, quel que soit le thème.

### Points ajoutés après la quatrième vérification

Ces points ne peuvent être confirmés qu'en jeu. Faites-les en plus de la fiche ci-dessus.

- **Infobulle du menu des addons** (thème autre que Classique) : ouvrez le menu des addons
  de la minicarte, survolez TruePlayed, puis fermez le menu par un clic ailleurs ou par
  Échap, sans survoler autre chose. L'infobulle disparaît en une seconde au plus.
- **Infobulle jamais coupée**, en français et en anglais, survol simple puis Maj enfoncée,
  surtout en Pixel rétro, Prêtre, Mage, Chaman et Futuriste, et juste après la connexion,
  quand la ligne « XP par heure » affiche « disponible après ~... de jeu pris en compte »
  (la ligne la plus longue). Aucune ligne ne finit par « ... » et aucune ne touche le
  bord. Changez une couleur ou de thème, puis rouvrez l'infobulle : elle a la même
  largeur qu'avant.
- **Chaman** : 4 pierres sur la barre, à 12,5 %, 37,5 %, 62,5 % et 87,5 % de la
  longueur. Aucune ne touche le texte du haut, avec une taille de texte de 11, de 14 ou
  de 16.
- **Séparateurs de l'infobulle** (Druide, Chasseur, Mage et Chaman) : l'ornement du
  milieu (feuille, flèche, rune, symbole) garde ses proportions à toutes les largeurs.
  Seuls les filets de part et d'autre s'allongent.
- **Démoniste** : le libellé de l'XP est violet clair (`#a3a4f6`), comme sur la planche.
- **Fond à 60 %**, en Druide, Chasseur, Voleur et Prêtre : les ornements des
  deux bouts restent sur le panneau, sans dépasser à gauche ni à droite.
- **Bords des textures** : aucun liseré noir ou sombre autour des ornements, des cadres
  et des lueurs, surtout avec une grande barre.
- **Couleurs** : choisir une couleur d'XP dans les Options change la barre aussitôt et ne
  fait clignoter ni la fenêtre `/tpl stats` ni le graphique. En Classique, la partie
  « reposé » reste bleue et ne devient jamais blanche.
- **Près du bord de l'écran** : placez la barre contre le bord droit puis contre le bord
  du bas, et survolez-la. L'infobulle, plus large dans certains thèmes, reste entièrement
  à l'écran.

### Redémarrage ou /reload après une mise à jour

À faire une fois, lors d'une prochaine mise à jour de l'addon : recopiez le dossier puis
faites seulement `/reload`. Les textures nouvelles peuvent manquer (cadre ou ornements
absents, ou remplacés par des carrés unis) et, si une police manque, un seul message
s'affiche dans le chat :
« TruePlayed : Une police du thème n'a pas pu être chargée (...) ; la police du jeu la
remplace. Relancez le jeu après une mise à jour. » Quittez et relancez le jeu : tout est
en place et le message ne revient pas.

Ce que seul le jeu peut confirmer (dites-moi si l'un de ces points ne se passe pas comme
décrit) :

- **Les dégradés et les motifs répétés** (lignes de balayage, pointillés) : s'ils sont
  remplacés par une couleur unie ou étirés, notez le thème.
- **Les polices pixel** (Pixel rétro) : nettes, sans flou, à toutes les tailles de texte.
- **Classique** strictement identique à l'ancien aspect.

## 0. Mise à jour du 1er octobre (soir) : plafond du niveau 20, XP/h figée, couleurs

Pas de nouveau fichier cette fois : recopiez le dossier, puis un `/reload` suffit. Si vous
n'aviez pas encore installé la mise à jour du matin (celle qui ajoute `Graph.lua`),
redémarrez complètement le jeu.

Sur votre druide, toujours bloqué au niveau 20 par la bêta :

- **Le plafond de la bêta** : tuez 3 monstres de votre niveau (pas gris), l'un après
  l'autre, en gardant chacun en cible jusqu'à la fin du combat. Ils ne rapportent pas
  d'XP : après le troisième combat, la barre devient pleine et atténuée, et affiche en bas
  à gauche `NIVEAU 20 · PLAFOND` ; les autres infos deviennent celles choisies pour le
  niveau maximum (par défaut la session et le temps total). Survolez la barre : en orange
  `Niveau 20 : plafond actuel du serveur (aucune XP sur les 3 derniers monstres)`, puis
  `XP  58 / 23 200` et « Le suivi de l'XP reprend tout seul dès que le serveur redonne de
  l'XP. ». `/tpl played` le dit aussi. Après un `/reload`, le plafond est gardé. Ne
  comptent pas : un monstre gris, un monstre déjà tapé par un autre joueur, une bestiole,
  un totem, un joueur, un combat fini sans que la cible soit morte, et, en groupe, un
  monstre gris pour le membre de plus haut niveau (en Classic, personne n'a d'XP alors).
- **« Masquer au niveau max »** (Options > Affichage) : même coché, la barre reste
  affichée au plafond de la bêta (il est temporaire, et l'infobulle l'explique).
- **Quand le plafond sera relevé** (niveau 30) : au premier monstre qui rapporte de l'XP,
  la barre redevient normale toute seule (`XP : ...` en bas à droite, la couleur
  habituelle), sans rien toucher.
- **L'XP par heure figée** : à un moment où vous pouvez gagner de l'XP, jouez 20 minutes
  sans en gagner (hors AFK ; par exemple en ville, l'exclusion « ville » décochée). L'XP
  par heure et le temps avant le niveau se grisent et prennent un `*` (par exemple
  `8,2k/h*`), et l'infobulle dit `* XP/h figée : aucun gain d'XP depuis 25 min de jeu`.
  Pendant les 20 premières minutes les chiffres baissent un peu (TruePlayed ne peut pas
  encore distinguer une pause d'un monstre plus long à tuer), puis ils ne bougent plus.
  Tuez un monstre : le `*` disparaît et les chiffres repartent de la valeur figée, au lieu
  d'avoir fondu pendant toute l'attente.
- **L'estimation de départ** : avant les 3 monstres (ou si le plafond est levé), l'XP par
  heure estimée affiche environ `~5,7k/h` au lieu de `~4,5k/h` : elle ne compte plus que
  les niveaux 1 à 19 (le temps passé au niveau 20, surtout bloqué, n'y entre plus).
- **Les couleurs de la barre** : Options > Couleurs de la barre. Cliquez sur le carré de
  « Couleur de la barre d'XP » : la barre change pendant que vous choisissez (même au
  plafond : la barre pleine prend cette couleur, atténuée) ; « Annuler » remet la couleur
  d'avant. « Couleur de l'XP de repos » se voit quand vous êtes reposé : la barre prend
  cette couleur et la zone après elle en prend une teinte plus claire. « Couleurs
  d'origine » remet le violet et le bleu du jeu (le bouton est grisé tant que vous n'avez
  rien changé). La couleur du texte garde son propre bouton.

Ce que seul le jeu peut confirmer (dites-moi si l'un de ces points ne se passe pas comme
décrit) :

- **Le plafond est bien repéré après 3 monstres** : si rien ne change, notez si les
  monstres étaient gris, si vous les aviez en cible à leur mort, et si un message d'XP
  était apparu dans le chat.
- **Aucun faux plafond** : en dessous du niveau 20 (ou une fois le plafond levé), tuer des
  monstres ne doit jamais afficher `PLAFOND`.

## 0 bis. Mise à jour du 1er octobre (matin)

**Important : cette mise à jour ajoute un fichier (`Graph.lua`).** Recopiez le dossier
comme à l'étape 1, puis **quittez complètement le jeu et relancez-le** : un `/reload` ne
charge pas les nouveaux fichiers (sans redémarrage, le graphique des FPS ne s'affichera
pas). Vos données et vos réglages sont conservés.

Sur votre druide (barre en haut de l'écran, trois exclusions activées) :

- **Monstres à tuer** : tuez un monstre. En haut à droite, la barre affiche maintenant le
  temps avant le niveau **et** le nombre de monstres, par exemple `~5 h 05 · 38 monstres`
  (si la barre est trop étroite, seulement le temps). L'infobulle a une ligne
  `Monstres à tuer : ~38 (moyenne : 610 XP, dernier : 610 XP)` juste sous « Prochain
  niveau » (depuis le lot 5 : moyenne des 10 derniers monstres). Avant le premier monstre
  tué, elle indique « calculé dès votre prochain monstre tué ». Rendre une quête ne change
  ni la « moyenne » ni le « dernier ». Quand vous êtes reposé, le nombre est plus petit
  (chaque monstre rapporte le double).
- **L'XP de repos, comme la barre du jeu** : après une déconnexion à l'auberge, la barre est
  **bleue**, avec une partie bleu clair jusqu'à la fin de votre XP de repos. L'infobulle
  affiche `Reposé : 11 600 XP (50 %)`. Une fois le repos consommé, la barre redevient
  violette.
- **Le temps en instance** : faites un donjon (par exemple les Cavernes des lamentations)
  ou un champ de bataille. Dans l'infobulle : une ligne `En instance`, et « Répartition »
  cite `Donjons` (ou `JcJ`). Maj enfoncée : `Donjons | 45 min (dont AFK 2 min)`. Dans
  `/tpl stats zones`, un bloc « Instances les plus jouées » avec `(donjon)`, `(raid)` ou
  `(JcJ)` après le nom ; dans l'onglet Niveaux et l'onglet Sessions, une colonne `Inst.`.
  Le temps passé en instance **avant** cette mise à jour reste compté comme « Monde » :
  c'est normal.
- **La répartition** : seules les parties que vous avez vraiment jouées apparaissent, dans
  l'ordre Monde, Donjons, Raids, JcJ, En vol, AFK, Auberge, Ville (sur deux lignes s'il y
  en a plus de cinq).
- **Le graphique des FPS et de la latence** : passez la souris sur les FPS ou la latence
  (en haut au centre de la barre). Un graphique apparaît : les FPS en haut, la latence en
  dessous, avec le minimum, la moyenne et le maximum. Déplacez la souris sur le graphique :
  une ligne indique la valeur à ce moment-là, par exemple `il y a 23 s : 58 fps · 112 ms`.
  La latence dessine des marches : le jeu ne la rafraîchit qu'environ toutes les 30
  secondes. Le graphique disparaît quand la souris quitte le texte et le graphique. Dans
  Options > FPS et latence, « Durée du graphique » : 30 s, 1 min ou 5 min.
- **Des textes lisibles sans fond** : les textes de la barre ont un fin contour et une
  ombre. Dans Options > Textes : « Contour du texte » (Aucun, Fin, Épais), « Ombre du
  texte », et « Opacité du fond » de 0 à 100 % (0 % = la barre seule, comme maintenant).
- **La couleur du texte** : Options > Textes > « Couleur du texte », cliquez sur le carré de
  couleur. Les textes de la barre changent pendant que vous choisissez ; « Annuler » remet
  les couleurs d'avant, le bouton « Couleurs d'origine » aussi. La barre elle-même ne
  change pas de couleur (ses couleurs ont leurs propres réglages depuis la mise à jour du
  soir, voir section 0). Les FPS et la latence restent vert / jaune / rouge ; décochez
  « Couleurs de qualité » (Options > FPS et latence) pour qu'ils prennent votre couleur.
- **Les performances** : `/tpl perf`, gardez la souris sur le graphique pendant la minute
  de mesure : la ligne « Tic » doit rester sous 0,05 ms en moyenne.

Quelques points que seul le jeu peut confirmer (dites-moi simplement si l'un d'eux ne se
passe pas comme décrit) :

- **Le bout du bleu clair ne bouge pas** : reposé, tuez un monstre. La partie bleue avance,
  mais la fin de la zone bleu clair reste à la même place (chaque monstre consomme autant
  de repos qu'il rapporte en plus). Si elle avance ou recule, notez de combien.
- **Le dégradé** : la zone bleu clair s'estompe vers la droite. Si elle est d'un bleu uni,
  ce n'est pas grave, mais signalez-le.
- **Les découvertes et les quêtes** : découvrir un lieu (message jaune et XP) ou rendre une
  quête ne change ni la « moyenne » ni le « dernier » de la ligne « Monstres à tuer ».
- **En donjon** : après quelques monstres, la ligne « Monstres à tuer » se met à jour
  (« dernier » = l'XP du dernier monstre tué, « moyenne » = celle des 10 derniers, sans
  le bonus de repos).
- **Le survol** : passer la souris des FPS au graphique ne le ferme pas ; le quitter le
  ferme. Après avoir déplacé la barre (déverrouillée), son infobulle revient au survol
  sans avoir à cliquer.

## 0 ter. Rappel des retours du 30 septembre

Ce que vous deviez déjà voir depuis la mise à jour précédente, sur le druide
(niveau 20, 58 / 23 200 XP), toujours aux Pitons-du-Tonnerre avec les trois exclusions
(les chiffres ci-dessous sont ceux du premier test ; ils bougent un peu si le druide a
gagné de l'XP depuis) :

- **XP par heure et temps avant le niveau** : plus de « ... ». Dès le `/reload`, la barre
  affiche en haut à droite le temps avant le niveau et en bas à droite `~5,7k/h` (c'était
  `~4,5k/h` avant la mise à jour du soir, voir section 0), même en ville avec les
  exclusions activées (grisés, avec le signe de pause, puisque le chrono est en pause).
  Le `~` veut dire « estimation » : TruePlayed n'a encore rien mesuré lui-même, alors il
  part de votre /played d'avant l'installation (l'XP des niveaux 1 à 19 divisée par le
  temps qu'ils ont pris, environ 1 j 5 h). L'infobulle l'écrit en clair : `~5,7k/h
  (estimation d'après votre /played)`. C'est une moyenne de toute la carrière du
  personnage, donc approximative. Après une dizaine de minutes de jeu prises en
  compte (hors AFK, auberge et ville tant que ces exclusions sont cochées), l'estimation
  s'efface peu à peu : le `~` disparaît de l'XP par heure et la mention « estimation »
  quitte l'infobulle. C'est alors votre propre rythme. Le temps avant le niveau garde
  toujours son `~` : c'est une prévision.
- **En bas à droite** : `XP : 58 / 23 200 · ~5,7k/h`, avec un point de séparation, le signe
  de pause devant `~5,7k/h`, sans texte collé ni coupé. Réduisez la largeur dans les
  options : les nombres raccourcissent (`XP : 58 / 23,2k`, puis `58 / 23,2k`), puis l'info
  la moins utile laisse la place, sans jamais chevaucher `NIVEAU 20`.
- **Le pourcentage** : une décimale, comme dans l'infobulle (`0,3 %`).
- **Pas de fond sombre** : la barre seule, même si le premier test l'avait enregistré.
  Le réglage « Opacité du fond » (Options > Textes) le remet si vous le souhaitez, et ce
  choix est alors gardé.
- **Continents** : Maj enfoncée sur la barre, une section « Continents » apparaît. Avec les
  trois exclusions, en ville, elle affiche `Kalimdor  < 1 min` et `Autres  < 1 min` : tout
  votre temps suivi jusqu'ici l'a été en ville ou en auberge, donc exclu. Décochez l'exclusion « ville » pour voir le temps
  réel. Dans `/tpl stats zones`, un bloc « Continents » est au-dessus des capitales :
  Kalimdor et « Autres » (colonne du temps compté : `-` tant que tout est exclu, colonne
  brute : le vrai temps).
- **Kalimdor n'est plus une zone** : il ne doit plus apparaître parmi les **zones** (ni dans
  « Zones principales », ni dans la liste de `/tpl stats zones`). Les 2 secondes enregistrées
  là au premier test sont rangées dans « Autres zones ». Faites aussi un `/reload` ou un
  écran de chargement : les premières secondes vont désormais à la vraie zone.

## 1. Installer l'addon

L'addon est le dossier `TruePlayed`. Il doit arriver dans le dossier des addons du jeu :
`/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/TruePlayed`.

Le plus simple, dans le Terminal (depuis le dossier de l'addon, voir `PUBLISHING-fr.md`) :

```
cd ~/Documents/claude/TruePlayed/TruePlayed_on_github
git pull
DEST="/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/TruePlayed"
mkdir -p "$DEST"
rsync -a --delete --exclude '.*' --exclude 'tests' --exclude 'docs' --exclude 'design' \
  --exclude 'tools' --exclude 'media-src' ./ "$DEST/"
```

Vérifiez que le fichier `TruePlayed_Camelot.toc` se trouve **directement** dans
`AddOns/TruePlayed/` (pas dans `AddOns/TruePlayed/TruePlayed/`).

## 2. Redémarrer complètement le jeu

Un **nouvel** addon, ou un nouveau fichier dans un addon (comme `Graph.lua` dans cette
mise à jour), n'est vu qu'au démarrage du jeu : quittez WoW Forever (pas seulement
`/reload`) et relancez-le. Sur l'écran des personnages, bouton **AddOns** : TruePlayed
doit être coché, avec l'icône de montre, sans la mention « périmé ».

## 3. Afficher les erreurs

Une fois en jeu, tapez dans le chat :

```
/console scriptErrors 1
/reload
```

Une fenêtre s'ouvrira alors à chaque erreur Lua, au lieu de rester silencieuse.

## 4. Ce qu'il faut regarder

**La barre** (comparez avec la maquette) :
- une barre d'XP violette aux bouts arrondis (bleue quand vous êtes reposé), sans fond
  (option « Opacité du fond ») ;
- en bas à gauche `NIVEAU 42`, en bas à droite `XP : 12 340 / 45 800 · 8,2k/h` (XP puis
  XP par heure, séparés par un point) ;
- en haut à droite le temps avant le prochain niveau et les monstres à tuer
  (`~1 h 25 · 38 monstres`), au centre au-dessus les FPS et la latence ;
- le pourcentage (`27,3 %`) suit le bout de la barre violette sans chevaucher les textes.

Au premier lancement, un message s'affiche dans le chat et la barre est déverrouillée
(voile violet) : faites-la glisser, puis clic droit > **Verrouiller**. Barre invisible ?
Tapez `/tpl show`.

**L'infobulle** : passez la souris sur la barre. Vous devez voir le niveau, l'XP, le
temps avant le niveau, la session, **la zone actuelle avec son temps** (par exemple
`Zone : Forêt d'Elwynn | 12 min`), le temps de jeu et le /played du serveur. Gardez **Maj**
enfoncée : les détails apparaissent (zones du niveau, continents, capitales, totaux...).

**Les options** : tapez `/tpl`. La page TruePlayed s'ouvre. `/tpl help` liste les commandes.

**Les exclusions** : clic droit sur la barre > **Exclure le temps AFK**, puis tapez
`/afk` et attendez une minute. Les infos de la barre s'assombrissent avec un signe de
pause, l'infobulle indique « Chrono en pause ». Décochez l'exclusion : les chiffres
reviennent exactement à leurs valeurs d'avant. Faites de même avec l'auberge et la ville :
temps de jeu, moyenne, XP par heure et temps avant le niveau changent tout de suite.

**Les zones** : tapez `/tpl stats zones`. Les continents sont en haut, puis les
capitales les plus fréquentées, puis chaque zone jouée avec son temps. Avec une exclusion active, l'en-tête de la
fenêtre l'indique (« Temps affichés hors AFK ») et les temps changent.

**Les zones par niveau** : onglet **Niveaux**, passez la souris sur une ligne : la liste
des zones de ce niveau s'affiche, avec leur temps.

**La mémoire de l'XP par heure** : notez l'XP par heure, tapez `/reload`. Après le
rechargement, elle doit être à peu près la même, **pas** « ... ». Idem après avoir quitté
et relancé le jeu.

**Un autre personnage** : connectez un reroll. La barre et l'infobulle ne montrent que
ses propres chiffres. S'il a déjà joué avant l'installation, l'XP par heure part d'une
estimation (avec un `~`) ; sur un personnage tout neuf, « ... » au début est normal et
l'infobulle indique combien de minutes de jeu il faut encore. Dans
`/tpl stats`, les flèches `<` `>` passent d'un personnage à l'autre, puis au compte.

**WTFix** (si vous l'utilisez) : tant que TruePlayed est coché dans `/wtfix`, un
avertissement WTFix doit s'afficher **une seule fois** dans le chat à chaque connexion ou
`/reload`. Tapez `/wtfix`, décochez TruePlayed, jouez 5 minutes puis faites `/reload` :
vos chiffres doivent rester (temps de jeu, XP par heure), l'avertissement ne revient plus,
et aucun message « Temps de jeu récupéré » ne doit apparaître.
Ensuite, toujours sans WTFix, **quittez complètement le jeu** (pas seulement `/reload`)
et relancez-le comme d'habitude. Vos chiffres doivent toujours être là (temps de jeu, XP
par heure, onglet **Niveaux** de `/tpl stats`), sans message « Temps de jeu récupéré ».
S'ils ont disparu, dites-le-nous : cela voudrait dire que Forever ne relit pas la
sauvegarde sans WTFix, et nous changerons le conseil.

**Une ville dans un donjon** : entrez dans un donjon (par exemple le Gouffre de Ragefeu
sous Orgrimmar) et tapez `/tpl citytoggle`. Le chat doit afficher « Les instances ne
comptent jamais comme des villes. » et rien ne change (vérifiez avec
`/tpl stats zones`).

## 5. Les performances : `/tpl perf`

Tapez `/tpl perf`, jouez, et attendez la ligne « Tic » (une minute plus tard).

- **Tic** : la moyenne doit rester **sous 0,05 ms** et le maximum **sous 0,2 ms**.
- **Mémoire** : le chiffre compte le code de l'addon (environ 0,5 Mo) plus les données de
  tous vos personnages. Retapez `/tpl perf` après une heure : il doit rester **stable**.
- **Processeur** : pour le mesurer, `/console scriptProfile 1` puis `/reload` ; cela
  ralentit le jeu, remettez `0` ensuite.
- Aucune baisse de FPS visible par rapport au jeu sans l'addon.

## 6. Signaler un problème

- **Une erreur Lua** : dans la fenêtre d'erreur, sélectionnez tout le texte, copiez-le
  (`Cmd + C`) et envoyez-le tel quel. Sinon, envoyez le fichier le plus récent du
  dossier `/Applications/World of Warcraft/_classic_beta_/Errors/`.
- **Un affichage bizarre** : une capture d'écran (`Cmd + Maj + 4`, espace, clic sur la
  fenêtre du jeu) et une phrase : ce que vous faisiez, ce que vous attendiez.
- **Des performances** : copiez les lignes de `/tpl perf`.
- Précisez toujours la langue du jeu et le niveau du personnage.

Pour la vérification complète avant chaque version, voir l'étape 3 de `PUBLISHING-fr.md`.
