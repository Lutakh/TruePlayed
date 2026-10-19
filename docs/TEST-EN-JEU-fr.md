# Premier test en jeu de TruePlayed (WoW Forever)

Une petite fiche pour votre premier essai, dans l'ordre. Comptez une heure de jeu normal.
Notez ce qui vous surprend : il n'y a pas de mauvaise remarque.

## À vérifier en premier (nouveau) : les minutes au-delà de 10 h, le /played serveur du niveau, l'XP par source, le cumul depuis le niveau 1, la plage de progression

Cette mise à jour n'ajoute aucun fichier : après l'avoir recopiée, un `/reload` suffit.

### Le cumul depuis le niveau 1 et la plage de progression (demandes du 17/10)

- [ ] **La fiche d'un niveau terminé** (`/tpl stats levels`, clic sur la barre du
  niveau 18 par exemple, titre « Niveau 18 » 19 ») : l'encadré « Cumul depuis le
  niveau 1 » porte en dessous « niveau 1 » 19 » (le temps jusqu'au passage au 19), et non
  plus « niveaux 1 à 18 ». L'encadré « Temps joué » tout en haut garde « niveaux 1 à N »
  (il compte le niveau en cours).
- [ ] **La fiche du niveau en cours** : « niveau 1 » N+1, en cours » sous le cumul, dont la
  valeur est celle de l'encadré « Temps joué » du haut et avance avec lui.
- [ ] **L'infobulle d'une barre** : après « Atteint le », une ligne « Cumul depuis le
  niveau 1 », à la minute, la même valeur que l'encadré de la fiche de ce niveau (cliquez
  la barre pour comparer, aussi avec l'AFK exclu). Sur la barre du niveau en cours :
  la même valeur que « Temps joué » en haut au moment du survol (l'infobulle ne bouge
  pas tant que la souris reste dessus : survolez de nouveau pour la voir avancer). Sur
  une barre estompée (niveau à venir) : une estimation avec « ~ » (« ~3 j 15 h »). Sur la
  souche d'un niveau d'avant l'installation : pas de ligne.
- [ ] **La bande du bas** se lit « Progression : niveau [1] » [60] » (deux petites cases
  encadrées). Dessous : « Niveau 1 » C : ... », C étant votre niveau actuel, soit le
  temps jusqu'à l'atteindre, le niveau C−1 » C compris (avant : « Niveaux 1 à C−1 »,
  qui semblait laisser de côté ce dernier niveau), puis « Niveau C en cours : ... »,
  « Reste ~... » et les deux pourcentages à droite comme avant.
- [ ] **Choisir une plage** : clic sur la case [1] : un menu « Du niveau » avec les
  niveaux 1 à 59 (il défile) ; choisissez 10. Clic sur [60] : « Jusqu'au niveau », de 11
  à 60 ; choisissez 20 (prenez une plage qui contient votre niveau). La bande montre
  « Niveau 10 » C : ... », le niveau en cours, « Reste ~... » pour atteindre le 20, les
  pourcentages de la plage ; les deux cases prennent un cadre de couleur ; derrière les
  barres 10 à 19, un fond légèrement teinté. Rien ne chevauche les pourcentages à droite.
- [ ] **Une plage derrière vous** (par exemple 5 » 15 si vous avez dépassé le 15) : bande
  pleine, « 100 % · niveau 15 atteint », ni « en cours » ni « Reste ». **Une plage
  devant** (par exemple 30 » 40) : bande vide, « ~0 % du temps total estimé · 0 % de
  l'XP », « À venir : ~... estimé ».
- [ ] **Une plage sur des niveaux d'avant l'installation** (si TruePlayed a été installé
  en cours de montée : par exemple 1 » 5 ou 2 » 10 quand les barres 1 à 9 montrent la
  souche « Pas de données ») : la bande écrit « ... » à la place du temps de ces niveaux
  (jamais « <1m » ni le temps d'avant l'installation donné au niveau 1), ou « ~ » devant
  si un seul niveau n'a été que partiellement enregistré ; à droite, seulement « N % de
  l'XP ». La plage par défaut 1 » 60 garde son temps exact.
- [ ] **Survol d'une case, placement** : l'infobulle s'ouvre sous la case, un peu plus
  bas (la barre de progression reste visible) ; aucun ornement du cadre (plume du thème
  Chasseur, cristal du thème Mage...) ne cache la case survolée ni le titre.
- [ ] **« Du niveau » au-dessus de « Jusqu'au »** (plage 10 » 20, puis « Du niveau » 25) :
  la plage devient 25 » 60.
- [ ] **Gardée par personnage** : `/reload`, rouvrez l'onglet : la même plage. Passez à un
  autre personnage (flèches de l'en-tête) : il a la sienne (1 » 60 par défaut) ; changez
  la sienne, revenez : la vôtre n'a pas bougé.
- [ ] **Revenir par défaut** : en haut du menu (seulement quand la plage n'est pas 1 » 60),
  « Par défaut : niveau 1 » 60 » : la bande redevient exactement celle d'avant, le fond
  teinté disparaît.
- [ ] **Survol d'une case** : une infobulle « Du niveau » (ou « Jusqu'au niveau ») et
  « Clic : choisir un niveau ». Dans le thème Classique et dans un autre thème.
- [ ] **Pas d'erreur ni de blocage** : après avoir choisi une plage, entrez en combat et
  utilisez vos sorts et barres d'action : aucun message « action bloquée par un addon »,
  aucune erreur Lua (`/console scriptErrors 1`).

### Les minutes, le /played serveur du niveau, l'XP par source

- [ ] **Les minutes au-delà de 10 h** (`/tpl stats levels`, un personnage qui a plus de
  10 h sur un niveau ou au total) : « 10 h 23 » au lieu de « 10 h », « 1 j 19 h 05 » au
  lieu de « 1 j 19 h » dans les encadrés du haut (Temps joué, /played serveur, Moyenne
  par niveau), le résumé à droite du titre, la bande de progression, les infobulles des
  barres, la fiche du niveau (encadrés, répartition du temps, zones d'un niveau terminé)
  et le pied de la fenêtre. Les estimations avec « ~ » (Niveau 60 dans, Estimé au départ)
  et les graduations de l'axe ne changent pas. Les zones et les notes du niveau en cours
  gardent « 10 h » : elles ne se mettent à jour qu'au prochain gain d'XP, et des minutes
  y prendraient du retard.
- [ ] **Pied de la vue « Compte »** (flèches de l'en-tête jusqu'à « Compte (tous les
  personnages) ») : laissez la fenêtre ouverte deux ou trois minutes sans gagner d'XP. Le
  total du compte avance à la minute, comme celui du personnage.
- [ ] **Sessions** : la colonne Durée est à la minute jusqu'à un jour (« 23 h 59 »), puis
  en jours et heures comme avant (« 2 j 03 h ») ; celle de la session en cours avance à
  la minute. Les autres colonnes (AFK, Inst., Mort, Métiers) et l'onglet **Zones** restent
  comme avant (« 10 h » sans les minutes au-delà de 10 h) : ces cellules ne se mettent
  pas à jour en direct.
- [ ] **Dans une langue longue** (`/tpl lang de`, puis `es` et `pt`, `/reload` à chaque
  fois) : rien ne déborde ; un texte qui ne tient pas (deuxième ligne d'un encadré,
  colonne des valeurs de la fiche) perd ses minutes au-delà de 10 h au lieu de déborder.
  Revenez ensuite au français (`/tpl lang fr`). Le russe n'est pas proposé sur un client
  français : ses largeurs sont vérifiées par les tests.
- [ ] **Infobulle de la barre, /played serveur du niveau** : choisissez « Exclure le temps
  AFK » (clic droit sur la barre), tapez `/afk`, attendez deux minutes, retapez `/afk`,
  puis survolez la barre. Sous « Ce niveau » (le temps filtré, à la minute), la ligne
  « Ce niveau (/played serveur) » donne le temps du niveau sans aucun filtre : plus grand
  que « Ce niveau » de vos minutes AFK (à une minute près : les deux temps sont arrondis à
  la minute inférieure), et le même que l'encadré « /played serveur » de la fiche du
  niveau en cours. Sans exclusion, la ligne n'apparaît pas. Juste après la connexion,
  elle attend la réponse du /played (quelques secondes).
- [ ] **Infobulle de la barre, XP du niveau** : juste au-dessus de « Répartition du
  niveau », la ligne « XP du niveau » avec une petite jauge, et dessous, sur une ligne, la
  part des monstres, des quêtes et autres et du bonus de repos (« Monstres 80 % · Quêtes
  et autres 10 % · Bonus de repos 10 % » ; sur deux lignes dans le thème Classique et
  dans les langues où une ligne ne tiendrait pas), dans les couleurs de la barre
  « Expérience » de la fiche. Dans plusieurs thèmes, Classique compris : dans Classique,
  la jauge de l'XP et celle de la répartition commencent et finissent au même endroit ;
  avec Maj, les deux répartitions restent face à face. Rien au niveau maximum.
- [ ] **Vos couleurs** (options, « Couleurs de la barre ») : choisissez une autre
  « Couleur de la barre d'XP » et « Couleur de l'XP de repos » : la jauge « XP du niveau »
  de l'infobulle et la barre « Expérience » de la fiche (fenêtre ouverte) prennent les
  mêmes couleurs que la barre. « Couleurs du thème » les remet.

## À vérifier en premier (nouveau) : l'onglet Niveaux en histogramme

**Quittez complètement le jeu et relancez-le d'abord** : cette version ajoute deux
fichiers de plus (`LevelChart.lua` et `LevelDetail.lua`), et un `/reload` ne charge pas
les nouveaux fichiers. Activez les erreurs Lua (`/console scriptErrors 1`) pour toute
cette partie. Cochez chaque point vérifié ; s'il ne se passe pas ce qui est écrit, notez
ce que vous voyez (une capture d'écran aide beaucoup ici : c'est une nouvelle page, que
les tests hors du jeu dessinent sans la voir). Le JcJ sauvage ne se mesure qu'à partir de
cette version : les niveaux déjà terminés l'indiquent comme non mesuré, c'est normal.

### Ouvrir l'onglet, la taille de la fenêtre

- [ ] **`/tpl stats levels`** (ou clic gauche sur la barre, onglet **Niveaux**) : la
  fenêtre montre, sous les onglets, une rangée de sept encadrés, le titre « Temps joué
  par niveau » avec à droite un résumé (« 1 j 04 h sur 17 niveaux »), les filtres, le
  graphique en barres, la bande « Progression : niveau 1 » 60 » en bas, et à droite la
  **fiche** du niveau en cours. Plus de tableau de niveaux, plus d'en-têtes de colonnes.
- [ ] **L'aide de l'en-tête** dit « Cliquez sur une barre pour voir le détail du niveau. »
  (entière, rien de coupé).
- [ ] **La taille** : la fenêtre fait au moins 1040 x 640 sur cet onglet, même si vous
  l'aviez réduite. Passez sur **Zones** ou **Sessions** : elle reprend votre taille
  enregistrée. Revenez sur Niveaux et tirez le coin en bas à droite : elle s'agrandit,
  mais ne descend pas sous 1040 x 640 ; la taille choisie est gardée après un `/reload`.
- [ ] **La poignée sur Niveaux ne garde que ce que vous changez** : sur Niveaux, un simple
  clic sur le coin en bas à droite (sans tirer), puis Zones : la taille de Zones n'a
  pas changé (pas 1040 x 640). Sur Niveaux, tirez le coin **vers le bas seulement**,
  puis Zones : la hauteur est la nouvelle, la largeur celle d'avant.
- [ ] **Petit écran ou grande échelle d'interface** (nouveau) : la fenêtre doit tenir à
  l'écran, un peu plus étroite que lui s'il fait moins de 1040 de large (écran 4:3,
  ou échelle d'interface au maximum) : les barres sont plus étroites, la fiche garde sa
  largeur, rien ne sort de la fenêtre ni de l'écran, les encadrés du haut ne débordent
  pas. Dites-moi votre résolution et votre échelle si quelque chose déborde.

### Les sept chiffres du haut

- [ ] **Temps joué** (« niveaux 1 à N ») : le même que « Temps de jeu » dans l'infobulle
  (Maj), avec vos exclusions.
- [ ] **/played serveur** (« tout compris ») : le même que la commande `/played`.
- [ ] **Moyenne par niveau**, avec « 5 derniers : … » dessous.
- [ ] **JcJ** (« BG … · sauvage … ») : **survolez-le** : une infobulle donne chaque champ
  de bataille avec son temps, le JcJ sauvage, sa définition, et « JcJ sauvage mesuré
  depuis le … » (la date de cette mise à jour).
- [ ] **Vol** (« … du temps joué ») : votre temps en vol de taxi, **AFK en vol compris**
  (sauf si vous excluez l'AFK) ; « < 1 % du temps joué » pour un tout petit vol, jamais
  « 0 % » s'il y a eu du vol.
- [ ] **Morts** (« … mort ou fantôme ») : le nombre de morts et le temps passé mort.
- [ ] **Niveau 60 dans** (« au rythme actuel ») : un temps avec `~`. **Au plafond du
  serveur** (niveau 20 sur la bêta), l'encadré dit « Plafond serveur » / « niveau 20 » à
  la place, et la bande du bas « Plafond du serveur : niveau 20 » ; pareil quand vous
  regardez un **autre personnage** resté au plafond (flèches de l'en-tête).
- [ ] **XP désactivée** (si vous avez un personnage à l'XP bloquée chez le PNJ, sous le
  niveau max) : l'encadré dit « XP désactivée » / « niveau N » et la bande du bas « XP
  désactivée au niveau N », jamais « Niveau max » ni « Niveau maximum atteint ».
- [ ] **Dans une langue longue** (`/tpl lang de`, puis `es`, `pt` ; `/reload` à chaque
  fois, puis `/tpl lang auto`) : rien ne déborde des encadrés ; un sous-titre trop long
  passe en jours ou en heures entières (en allemand « BG 12 T · Welt 3 T »), c'est
  voulu.

### Les filtres et les barres

- [ ] **Une barre par niveau**, empilée par couleur (monde, JcJ sauvage, donjons, raids,
  champs de bataille, vol, métiers, mort, ville, auberge, AFK, et en gris le temps avant
  l'installation ou non suivi), dans l'ordre de bas en haut, aux couleurs de la
  répartition de l'infobulle.
- [ ] **Les axes** : à gauche des durées rondes (« 1 h », « 2 h »… ou « 30 min »), en bas
  les numéros de niveau 1, 5, 10…
- [ ] **Les filtres** (Tout, Monde, Instances, JcJ, Vol, Métiers, Mort) : un clic ne garde
  que cette activité, le filtre choisi est mis en évidence, l'échelle se recalcule, le
  titre change (« Temps JcJ par niveau (BG + sauvage) », « Temps de vol par niveau »,
  « Temps mort ou fantôme par niveau »…) et le résumé de droite dit « … au total · N
  niveaux concernés », ou « Aucun temps enregistré » pour une activité jamais faite
  (jamais « 0 niveaux »). **Tout** revient à l'affichage complet.
- [ ] **Survol d'une barre sous un filtre** (nouveau) : sous un filtre, survolez une
  barre. Juste sous le titre, une ligne donne l'activité du filtre, sa durée dans cette
  barre et sa part du niveau ; dessous, les lignes habituelles du niveau entier. Avec
  **Tout**, pas de cette ligne. La partie vol s'y appelle « Vol », comme l'encadré.
  - Une seule activité a du temps dans la barre (toujours le cas sous Monde, Vol, Métiers,
    Mort ; sous Instances quand il n'y a que des donjons, sous JcJ quand il n'y a que des
    champs de bataille) : la ligne porte le nom de cette activité dans sa couleur et la
    valeur en couleur d'accent (« Mort  5 min · 4 % »), et cette activité n'apparaît
    **qu'une fois** (plus de « Mort » en bleu puis en rouge).
  - Deux activités ont du temps (donjons et raid, ou champs de bataille et JcJ sauvage) :
    la ligne est en couleur d'accent avec le nom du filtre (« JcJ  12 min · 15 % »), puis
    chaque activité dans la liste. Un tiret si rien.
  - Une part non nulle de moins d'un demi pour cent se lit « < 1 % », jamais « 0 % »,
    comme sur la fiche du niveau.
  - Thème **futuriste** : le titre se lit « Niveau 30 > 31 » (« Level 30 > 31 » en
    anglais), sans carré entre les deux nombres.
- [ ] **Les niveaux à venir** (avec Tout) : après le niveau en cours, des barres estompées
  jusqu'au niveau 59, de leur durée estimée ; le niveau en cours a sa partie jouée, un
  trait de couleur en haut, puis une partie estompée pour ce qui reste. **« Masquer les
  niveaux à venir »** les retire (le bouton devient « Afficher les niveaux à venir ») ;
  ce choix est gardé à la réouverture de la fenêtre, pas le filtre.
- [ ] **La moyenne** : une ligne horizontale « moyenne … » à la hauteur de la moyenne des
  niveaux terminés.
- [ ] **Un niveau sans données** (atteint avant l'installation de TruePlayed) : un tout
  petit trait gris au lieu d'une barre.
- [ ] **Survol d'une barre** : une infobulle titrée `Niveau 12 » 13`, avec le temps joué (`~`
  s'il est en partie estimé), chaque activité avec sa durée et sa part, les morts, l'XP
  par heure, « Atteint le » avec la date (ou « en cours »), et « Clic : détail du
  niveau ». Sur une barre à venir : « À venir : ~… estimé » et l'XP à gagner. Sur un
  niveau sans données : la phrase qui l'explique.
- [ ] **La bande du bas** « Progression : niveau 1 » 60 » : la partie terminée, la
  partie du niveau en cours, le reste estimé ; à droite « ~P % du temps total estimé ·
  Q % de l'XP » ; dessous « Niveau 1 » C : … · Niveau C en cours : … · Reste ~… », ce
  dernier temps écrit exactement comme dans l'encadré « Niveau 60 dans ». Un « + » après
  ce temps (« ~6 j 22 h+ ») dit qu'une partie des niveaux à venir n'a pas de taille d'XP
  connue : le temps est alors un minimum.
- [ ] **Les axes d'un très long niveau** : sur un niveau de plusieurs jours de jeu (un
  personnage resté longtemps au plafond), l'axe de gauche compte en jours entiers
  (« 1 j », « 2 j »…, ou « 20 j », « 40 j »… pour un niveau de deux mois), jamais
  « 24 h » ; ses lignes restent dans le graphique, la plus haute au sommet.

### La fiche d'un niveau (clic sur une barre)

- [ ] **À l'ouverture**, la fiche montre le niveau en cours, dont la barre est entourée.
  **Cliquez** sur une autre barre : le cadre passe dessus et la fiche change.
- [ ] **L'en-tête** : `Niveau 12 » 13`, puis « Terminé le » avec la date (au format de
  vos options), ou « En cours : P % de l'XP du niveau », « À venir », « Pas de
  données ». Pour un niveau commencé avant l'installation, reconstitué après un
  plantage ou resté longtemps sans XP, une note grise l'explique.
- [ ] **Les six encadrés** : Temps joué, /played serveur, **Estimé au départ** (avec
  « X de plus que prévu » en jaune ou « X de moins que prévu » en vert), Cumul depuis le
  niveau 1 (« niveau 1 » sur un personnage de niveau 1, pas « niveaux 1 à 1 »), XP par
  heure, Morts (avec le temps mort, ou « aucune »). Pour le niveau en cours :
  « Estimation du niveau » et « reste environ … ».
- [ ] **L'écart à l'estimation suit vos exclusions** (nouveau) : sur un niveau commencé
  et terminé avec cette version, notez « X de plus / de moins que prévu », puis changez
  une exclusion (Options : exclure l'AFK) : l'écart disparaît (l'estimation a été prise
  sans cette exclusion), la valeur estimée reste. Remettez le réglage : il revient.
- [ ] **« Répartition du temps »** : une barre de couleurs et une ligne par activité, de
  la plus longue à la plus courte, avec la durée et le pourcentage (« < 1 % » pour une
  toute petite part, jamais « 0 % »). La ligne **Vol** est toujours là (un tiret quand
  il n'y a pas eu de vol).
- [ ] **La ligne JcJ** (sur un niveau où vous avez fait un champ de bataille) porte
  « (survoler) » : **survolez-la** : « Temps JcJ à ce niveau : … », chaque champ de
  bataille avec son temps, « JcJ sauvage (monde ouvert) », la définition du JcJ sauvage,
  et pour un niveau terminé avant cette version « JcJ sauvage non mesuré à ce niveau
  (avant cette version). » (pour le niveau en cours au moment de la mise à jour :
  « … seulement sur une partie de ce niveau. »).
- [ ] **« Expérience »** : « xp / XP du niveau », puis Monstres, Quêtes et autres, Bonus de
  repos, chacun avec sa valeur et son pourcentage, et une barre en trois couleurs.
- [ ] **« Zones et instances »** : les zones du niveau avec leur temps et une petite
  barre, une capitale marquée « (ville) », puis les donjons, raids et champs de bataille
  avec leur type (5 au plus). Sur un niveau où vous avez fait plus de 5 instances, la
  6e et les suivantes ne sont pas listées du tout, jamais comme des zones du monde.
- [ ] **Un niveau à venir** : « Durée estimée » (~…), « D'après votre rythme sur les
  derniers niveaux » (ou, juste après l'installation, tant que vous n'avez pas assez de
  niveaux terminés, « D'après votre XP par heure actuelle »), l'XP à gagner et « Atteint
  dans environ … de jeu ».
- [ ] **Le défilement** : si la fiche est plus haute que la fenêtre, la barre de
  défilement apparaît à droite et ne cache aucun texte ; changer de niveau remonte en
  haut de la fiche.

### En jouant, fenêtre ouverte

- [ ] **Le niveau en cours grandit** : laissez la fenêtre ouverte en jouant quelques
  minutes : sa barre monte, le « Temps joué », le « /played serveur », « Niveau 60 dans »
  et la bande du bas suivent, sans à-coup ni ralentissement (FPS stables, voir
  `/tpl perf`).
- [ ] **La fiche du niveau en cours** suit aussi (Temps joué, Cumul, /played serveur, la
  répartition : son total, ses lignes, leur ordre et leurs pourcentages, sa barre, et
  l'encadré Morts) ; les zones, les notes et l'XP se mettent à jour après votre
  prochain gain d'XP.
- [ ] **En direct pendant un vol, un champ de bataille, une mort** (nouveau), fenêtre
  ouverte sur le niveau en cours : pendant un vol de taxi, l'encadré **Vol** et la ligne
  Vol de la fiche avancent (la ligne remonte dans l'ordre quand elle dépasse une autre) ;
  dans un champ de bataille, l'encadré **JcJ** (« BG … ») et une ligne JcJ qui apparaît
  dans la fiche ; après une mort, l'encadré **Morts** (« 1 », puis le temps mort qui
  avance) et la ligne Mort de la fiche. Tout cela sans gain d'XP, sans à-coup.
- [ ] **Un long vol qui passe AFK** (nouveau) : prenez un vol de plus de 5 minutes sans
  toucher au clavier (le jeu vous met AFK) : à l'arrivée, l'encadré **Vol** et la ligne
  Vol de la fiche comptent tout le vol, AFK compris, comme la ligne « En vol » de
  l'infobulle (Maj) ; la ligne AFK de la fiche ne le compte pas. Avec l'AFK exclu, le
  vol ne garde que la partie non AFK.
- [ ] **Une montée de niveau** fenêtre ouverte : la barre du niveau terminé devient
  pleine, le nouveau niveau en cours prend le trait de couleur et sa partie estompée, la
  fiche reste sur le niveau choisi (qui affiche alors « Terminé le … »), aucune erreur.

### Autre personnage, vue du compte, thèmes

- [ ] **Un autre personnage** (flèches de l'en-tête) : son histogramme et sa fiche, sans
  rien qui bouge en direct ; la sélection revient sur son niveau en cours.
- [ ] **La vue du compte** : l'onglet Niveaux y reste un **tableau** (un niveau par
  ligne, avec les personnages qui l'ont terminé, leur temps moyen et leur XP par heure),
  comme avant.
- [ ] **Les thèmes** : `/tpl theme futuriste`, `pixel`, `actuel` (Classique), `warlock`
  et un ou deux autres, fenêtre ouverte : les couleurs suivent le thème (barres aux
  couleurs de la répartition, cadres et titres du thème), rien ne se chevauche, les
  infobulles des barres et de la ligne JcJ prennent l'aspect du thème (en Classique :
  l'infobulle du jeu). Changer la couleur de la barre d'XP dans les options ne change
  pas la fenêtre.

### Le JcJ sauvage

À faire une fois, en monde ouvert (pas en champ de bataille ni en arène), avec deux
victoires honorables ou deux gains d'honneur.

- [ ] **Deux victoires à moins de 15 minutes d'écart** : tuez un joueur de l'autre faction,
  restez en monde ouvert (sans être AFK, en vol, en ville ni à l'auberge), puis tuez-en
  un autre moins de 15 minutes plus tard. Ouvrez `/tpl stats levels`, cliquez sur votre
  niveau en cours et survolez la ligne JcJ : « JcJ sauvage (monde ouvert) » vaut à peu
  près le temps entre les deux victoires. Le filtre **JcJ** montre ce temps sur la barre
  du niveau, et l'encadré JcJ du haut l'ajoute au « sauvage ».
- [ ] **Une victoire isolée ne compte rien** : après une seule victoire, rien ne s'ajoute,
  même 15 minutes plus tard ; le temps passé après la dernière victoire ne compte jamais.
- [ ] **Une reconnexion ne compte pas comme une victoire** (nouveau) : un jour où vous
  avez déjà des victoires honorables, déconnectez-vous et reconnectez-vous (puis un
  `/reload`), restez 10 minutes en monde ouvert et faites une seule victoire : le JcJ
  sauvage du niveau ne bouge pas (le premier nombre de victoires lu à la connexion est
  un point de départ, même si le jeu donne d'abord 0).
- [ ] **Avec le JcJ masqué** (bande JcJ sur « Aucune », aucune info JcJ) : le JcJ sauvage
  se mesure quand même.

## À vérifier ensuite : le JcJ (honneur, rang, bande, barre principale, alerte au plafond)

**Quittez complètement le jeu et relancez-le d'abord** : cette version ajoute deux
fichiers de plus (`Pvp.lua` et `PvpOptions.lua`), et un `/reload` ne charge pas les
nouveaux fichiers. Activez les erreurs Lua (`/console scriptErrors 1`) pour toute cette
partie. Cochez chaque point vérifié ; s'il ne se passe pas ce qui est écrit, notez ce que
vous voyez (une capture d'écran aide). La bêta n'a pas de saison JcJ en ce moment : tout
ce qui touche au rang (points, plafond de la semaine, rang suivant) ne pourra se vérifier
qu'une fois la saison ouverte ; l'honneur, les victoires honorables et les champs de
bataille se vérifient dès maintenant.

### Ce que le jeu renvoie (à faire une fois, en copiant le résultat)

TruePlayed ne lit que ces fonctions ; leurs valeurs réelles confirment ce que les tests
hors du jeu supposent. Tapez chaque ligne dans le chat et notez le résultat :

- [ ] `/dump C_CurrencyInfo.GetCurrencyInfo(1792)` : `quantity` (votre honneur) et
  `maxQuantity` (le plafond, 25000 le 12 octobre).
- [ ] `/dump C_MajorFactions.GetMajorFactionProgressionInfo(2800)` : `renownLevel` (le
  rang), `renownReputationEarned`, `renownLevelThreshold`, `weekNumber` (-1 : pas de
  saison), `currentWeekProgressiveMaxLevel` (le plafond de la semaine).
- [ ] `/dump C_DateAndTime.GetSecondsUntilWeeklyReset()` et
  `/dump C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd()` : des secondes (0 pour la fin
  de saison tant qu'il n'y en a pas).
- [ ] `/dump GetPVPSessionStats()`, `/dump GetPVPYesterdayStats()`,
  `/dump GetPVPLifetimeStats()` : les victoires honorables du jour, de la veille, de
  toujours (et votre meilleur rang). Refaites le dernier **juste après une connexion** :
  s'il renvoie 0 un instant, TruePlayed l'ignore (le total ne recule jamais).
- [ ] `/dump PVP_RANK_11_0, PVP_RANK_11_1, PVP_RANK_11_0_FEMALE` : les titres du rang 7
  (Horde, Alliance, féminin). S'ils renvoient `nil`, la barre affiche « Rang 7 » sans
  titre : dites-le-moi.
- [ ] `/dump GetCurrentArenaSeason()` (le numéro de la saison JcJ, 36 sur la bêta) et
  `/dump C_DateAndTime.GetSecondsUntilDailyReset()` (des secondes).
- [ ] **Ce que le jeu renvoie au tout début de la connexion** (`PLAYER_LOGIN`, avant la
  fin de l'écran de chargement) : tapez `/tpl debug` (le chat confirme le mode
  débogage), puis **déconnectez-vous et reconnectez-vous**. Deux lignes `[debug]`
  apparaissent : `PvP read: honor … / … (base …), rank …` (la lecture de `PLAYER_LOGIN`)
  puis `PvP world: …` (celle de l'entrée dans le monde). Notez-les, refaites la même
  chose avec un `/reload`, puis `/tpl debug` pour éteindre. Si la première ligne montre
  `honor 0 / 0` (ou un rang 0 avec `max rank 0`) alors que vous avez de l'honneur ou des
  points de rang, c'est le cas prévu : elle doit dire `base 0` (TruePlayed ne prend pas
  cette lecture vide comme point de départ, sinon tout votre honneur compterait comme
  gagné), et la ligne `PvP world` doit donner vos vraies valeurs avec `base 1`. Dans
  tous les cas, « Gagné cette session » doit rester à 0 juste après la connexion.

### La page « JcJ » des options

- [ ] **La page existe** : Options > AddOns > TruePlayed : une sous-page **JcJ** apparaît
  sous **Réputation**. Elle contient, dans l'ordre : « Bande sous la barre » (Aucune /
  Honneur / Rang JcJ), « Barre principale » (Expérience / Réputation / **JcJ**), « JcJ sur
  la barre en champ de bataille », « Alerte au plafond d'honneur », puis « Honneur et
  rang par heure » avec son bouton « Réinitialiser » ; chacun avec son « ? ».
- [ ] **Les « ? »** : survolez chacun ; le texte est clair et entier (rien de coupé).
- [ ] **« Barre principale » est le même réglage** que sur la page Réputation : changez-le
  sur une page, l'autre suit (la page Réputation propose aussi **JcJ**).
- [ ] **La page principale** (`/tpl`) : dans les choix des infos de la barre, sept infos
  JcJ apparaissent : Honneur, Honneur par heure, Temps avant le plafond d'honneur, Rang
  JcJ, Points de rang par heure, Temps avant le rang JcJ suivant, Victoires honorables
  du jour.

### La bande JcJ sous la barre

- [ ] **Honneur** : « Bande sous la barre » > **Honneur**. Une fine bande dorée apparaît
  sous la barre, remplie selon votre honneur / le plafond (1 024 sur 25 000 : un tout
  petit bout). Elle passe en **orange dès 90 %** et en **rouge au plafond** (si vous y
  arrivez).
- [ ] **Sous la bande de réputation** : avec une faction suivie, la bande JcJ se place
  **1 pixel sous** celle de la réputation, de même largeur et de même hauteur ; la barre
  grandit juste de ce qu'il faut. Sans faction suivie (ou réputation décochée), elle
  prend la place de la bande de réputation.
- [ ] **Dans les 13 thèmes** (`/tpl theme futuriste`, `actuel`, `heroic`, `pixel`, puis
  les classes) : les deux bandes empilées, rien ne chevauche les textes ni le repère de
  la barre, aucune erreur.
- [ ] **Le survol** : la bande de réputation ouvre l'infobulle de la réputation, la bande
  JcJ l'**infobulle JcJ** (titre « JcJ »). Un clic ou un glisser sur les bandes agit sur
  la barre comme avant.
- [ ] **Rang JcJ** : « Bande sous la barre » > **Rang JcJ** : la bande montre vos points
  dans le rang (vide sans saison). **Aucune** : la barre redevient exactement comme avant.
- [ ] **Sous la barre principale JcJ** (« Barre principale » > **JcJ**) : une bande qui
  répéterait la grande barre n'apparaît pas (la bande **Rang JcJ** sous le rang ; avant
  la saison, la bande **Honneur** sous l'honneur). L'autre bande reste, et son survol
  ouvre bien l'**infobulle JcJ** (pas l'infobulle générale).

### La barre principale en mode JcJ

- [ ] **Basculer** : « Barre principale » > **JcJ**. Sans saison (le cas actuel), la
  grande barre montre votre **honneur** par rapport au plafond, et la mention « Saison
  JcJ non commencée ». Votre XP passe dans la fine bande dessous (aucune au niveau max).
- [ ] **Avec une saison** (plus tard) : à gauche « Rang N » et le titre du rang dans la
  langue du jeu, à droite les points de rang par heure et le temps avant le rang suivant ;
  quand le rang suivant est le **plafond de la semaine**, le texte de droite le dit
  (« rang 4 (plafond hebdo) dans 1 h 35 ») et l'infobulle aussi (« Le rang 4 est le
  plafond de la semaine… ») ; « Plafond de la semaine atteint » quand il vous bloque,
  « Rang max » au rang 14.
- [ ] **Sous le niveau max**, avec le JcJ en barre principale (ou en champ de bataille
  avec l'option automatique) : la fine bande montre votre **XP**, et la bande de
  réputation n'est **pas** affichée ; elle revient avec « Expérience ». Les « ? » de
  « Barre principale » et de « JcJ sur la barre en champ de bataille » le disent.
- [ ] **Au niveau max** avec « Masquer au niveau max » coché : la barre reste affichée
  tant qu'elle montre le JcJ.
- [ ] **Dans les 13 thèmes**, sans erreur ; revenez sur « Expérience » : la barre
  redevient exactement comme avant.

### Le JcJ automatique en champ de bataille

- [ ] Cochez **« JcJ sur la barre en champ de bataille »**, laissez « Barre principale »
  sur Expérience, entrez dans un **champ de bataille** : la barre passe en JcJ dès
  l'arrivée.
- [ ] **À la sortie** : la barre revient sur l'XP, et la page des options affiche toujours
  **Expérience** (le réglage n'a pas été touché). Même essai avec « Réputation » : retour
  sur la réputation.
- [ ] **En arène** (si vous en faites une) : la barre ne change pas (les arènes comptent
  dans le temps JcJ, mais pas pour ce mode automatique), et l'arène ne s'ajoute pas aux
  « Champs de bataille (session) » de l'infobulle.

### Honneur par heure, pause après 15 minutes

- [ ] **En champ de bataille** : survolez la bande JcJ. « Honneur par heure » dit d'abord
  « après votre premier gain », puis une valeur grisée, puis normale après une dizaine de
  minutes. Tout le temps du champ de bataille compte, avec ou sans gain.
- [ ] **Les points réalistes** : comparez l'honneur gagné pendant la session (ligne
  « Gagné cette session ») avec ce que vous avez vu en jeu.
- [ ] **La pause** : sortez du champ de bataille et faites autre chose (quêtes, ville)
  **plus de 15 minutes** sans gagner d'honneur : la valeur garde son chiffre, avec un `*`,
  et une note dans l'infobulle explique la pause ; elle reprend à votre prochain gain
  d'honneur. Avant 15 minutes, elle continue normalement.
- [ ] **Dépenser** de l'honneur chez un vendeur JcJ ne fait **pas** baisser l'honneur par
  heure ni « Gagné cette session ».
- [ ] **Après un `/reload`** ou une reconnexion : l'honneur par heure reprend où il en
  était (pas de remise à zéro), et les compteurs de la session continuent.
- [ ] **Réinitialiser** (page JcJ) puis `/tpl reset rate` : l'honneur par heure repart de
  zéro. Le bouton de la page JcJ ne touche ni l'XP par heure ni la réputation par heure.
- [ ] **L'info « Points de rang par heure »** dans un emplacement de la barre s'affiche
  « Pts de rang 312/h » (et non « Rang 312/h », qu'on lirait comme un numéro de rang).
- [ ] **Le rang et les champs de bataille ne sont suivis que si quelque chose montre le
  JcJ** : bande sur « Aucune », barre principale sur Expérience, option automatique
  décochée, aucune info JcJ, alerte décochée ; faites un champ de bataille, puis remettez
  la bande « Honneur » : ce champ de bataille n'apparaît pas dans « Champs de bataille
  (session) » de l'infobulle (c'est voulu). Son honneur, lui, compte bien dans « Gagné
  cette session » : depuis l'onglet Niveaux en histogramme, l'honneur et les victoires
  honorables sont toujours lus, car ils mesurent le JcJ sauvage de chaque niveau.

### L'alerte au plafond d'honneur

Seulement si vous approchez du plafond (25 000).

- [ ] **Au plafond, en combat** : rien tout de suite. **À la fin du combat** : un son et
  une petite fenêtre en haut de l'écran (même aspect que celle du rechargement
  automatique) disent que votre honneur est au plafond et que l'honneur gagné est perdu ;
  « OK » la ferme.
- [ ] **Une seule fois** : d'autres gains au plafond, un `/reload`, une reconnexion : pas
  de nouvelle alerte. Dépensez de l'honneur puis revenez au plafond : l'alerte revient.
- [ ] **Au plafond**, l'infobulle JcJ dit en rouge depuis combien de temps vous y êtes, et
  l'honneur par heure ne bouge plus.
- [ ] **Décochée** (« Alerte au plafond d'honneur ») : plus de son ni de fenêtre.

### L'infobulle JcJ

- [ ] **Honneur** : votre honneur / le plafond (pourcentage), gagné cette session, par
  heure, temps avant le plafond.
- [ ] **Rang** : sans saison, « Saison JcJ non commencée » et rien de divisé par zéro ;
  avec une saison, le rang et son titre, les points dans le rang, le total de la saison,
  le plafond de la semaine N (rang et points), ce qu'il reste cette semaine, les points
  par heure, le temps avant le rang suivant (ou « bloqué par le plafond » avec le temps
  avant la réinitialisation hebdomadaire), la fin de la saison.
- [ ] **Victoires honorables** : aujourd'hui, hier, cette session, au total, meilleur
  rang. Comparez avec le panneau JcJ du jeu (touche H). Tuez un joueur : « Aujourd'hui »
  et « Cette session » montent de 1.
- [ ] **Champs de bataille (session)** : pendant une partie, « Un en cours : compté à la
  sortie ». Après la sortie : « Joués » 1, « Victoires - défaites » correct (**vérifiez bien qui a
  gagné**), honneur moyen, durée moyenne. Une deuxième partie met les moyennes à jour.
- [ ] **Deux champs de bataille à la suite** : restez inscrit dans la file pendant une
  partie ; à la fin, quand la file s'ouvre, entrez **directement** dans le suivant sans
  repasser par le monde (le même champ de bataille ou un autre). Après la sortie du
  second : « Joués » doit avoir pris **2**, et « Victoires - défaites » les deux
  résultats. Un `/reload` pendant une partie ne doit **pas** la compter deux fois.
- [ ] **Les victoires honorables du jour après minuit** (la remise à zéro quotidienne,
  si vous êtes connecté à ce moment-là) : sans tuer personne, l'info « VH » de la barre
  et la ligne « Aujourd'hui » de l'infobulle passent à 0 dans la minute ; « Hier » prend
  l'ancien chiffre.
- [ ] **Thème Classique** (`/tpl theme actuel`) : la même infobulle, dans l'infobulle du
  jeu. Rien n'est coupé, dans tous les thèmes.

### Pour aller plus loin (facultatif, `/etrace`)

- [ ] **Un gain d'honneur** : `/etrace` filtré sur `CURRENCY` : notez ce que porte
  `CURRENCY_DISPLAY_UPDATE` (l'id 1792, la quantité, et surtout `quantityChange`). **Au
  plafond**, gagnez encore de l'honneur : dites-moi si l'événement arrive et ce que vaut
  `quantityChange` (TruePlayed ne compte jamais plus que la hausse réelle).
- [ ] **Un gain de points de rang** (avec une saison) : filtrez sur `FACTION` : arrive-t-il
  `UPDATE_FACTION`, `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` (au changement de rang), ou
  autre chose ?
- [ ] **Le passage à un nouveau rang** (avec une saison) : avec `/etrace` filtré sur
  `FACTION`, notez **l'ordre** de `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` et
  d'`UPDATE_FACTION`, et faites `/dump C_MajorFactions.GetMajorFactionProgressionInfo(2800)`
  juste après : le rang et les points vont-ils ensemble ? TruePlayed ne compte les gains
  qu'à `UPDATE_FACTION` (la lecture de l'autre événement peut mélanger l'ancien rang et
  les nouveaux points) : « Gagné cette session » (section Rang) doit monter des seuls
  points gagnés, pas d'un rang entier.
- [ ] **Le reset hebdomadaire** (avec une saison, en restant connecté au moment du reset
  et en étant au plafond de la semaine) : avec `/etrace` filtré sur `FACTION`, un
  événement arrive-t-il au reset ? Sans rien faire, dans la minute qui suit, la barre ne
  doit plus dire « Plafond de la semaine atteint » et l'infobulle doit montrer le
  nouveau plafond (TruePlayed relit le rang quand le compte à rebours du reset repart,
  et à chaque ouverture de l'infobulle).
- [ ] **La fin d'une partie** : filtrez sur `PVP` : notez la valeur `winner` de
  `PVP_MATCH_COMPLETE` (0 Horde, 1 Alliance attendu) et, **avant de sortir**,
  `/dump GetBattlefieldWinner()` et `/dump GetBattlefieldArenaFaction()` (votre camp
  dans la partie, comparé au vainqueur). Dites-moi votre faction et qui a gagné.

## À vérifier ensuite : la page Réputation, la faction à suivre, l'infobulle de la réputation, la réputation par heure, la réputation en barre principale

**Quittez complètement le jeu et relancez-le d'abord** : cette version ajoute un fichier
de plus (`RepOptions.lua`, en plus de `AutoReload.lua` et `Reputation.lua`), et un
`/reload` ne charge pas les nouveaux fichiers. Activez les erreurs Lua
(`/console scriptErrors 1`) pour toute cette partie. Cochez chaque point vérifié ; s'il
ne se passe pas ce qui est écrit, notez ce que vous voyez (une capture d'écran aide).

### La page « Réputation » des options (vos demandes du 12 octobre)

- [ ] **La page existe** : Options > AddOns > TruePlayed : sous TruePlayed, une
  sous-page **Réputation** apparaît (cliquez la petite flèche à gauche de TruePlayed si
  elle est repliée). Elle contient, dans l'ordre : « Afficher la réputation suivie sous la
  barre » (avec son « ? »), « Barre principale » (Expérience / Réputation, avec son « ? »),
  « Faction à suivre » (avec son « ? »), une note, puis le bouton « Réinitialiser la
  réputation/h ».
- [ ] **Le renvoi** : dans la page principale, section Affichage, la case de la réputation
  a disparu ; à sa place une note dit que la réputation a sa propre page.
- [ ] **Les « ? »** : survolez chacun. Celui de la case dit quelle case cocher dans le
  panneau Réputation du jeu (avec le libellé de votre jeu) ; celui de « Barre
  principale » explique l'inversion et cite « Masquer au niveau max » ; celui de
  « Faction à suivre » explique le mode auto, le choix par personnage et la remise à zéro
  du rythme.
- [ ] **`/tpl` ouvre toujours la page principale** ; passer d'une page à l'autre ne
  donne aucune erreur, et ce qui change ailleurs (par exemple `/tpl theme druid` tapé
  avec la page Réputation ouverte) n'en casse rien.

### La faction à suivre

- [ ] **Auto par défaut** : « Faction à suivre » affiche « Suivie par le jeu (auto) » :
  la bande suit la faction cochée dans le panneau Réputation du jeu, comme avant.
- [ ] **La liste** : ouvrez la liste. Les factions du jeu y sont rangées par catégorie
  (Classique, Alliance ou Horde, Inactives...), chacune avec son rang entre parenthèses.
  Comparez avec le panneau Réputation du jeu : rien ne manque, surtout pas les factions
  rangées sous une catégorie **repliée** dans le panneau.
- [ ] **Le panneau du jeu n'a pas bougé** : après avoir ouvert la liste, ouvrez le
  panneau Réputation du jeu (fenêtre du personnage) : les catégories que vous aviez
  repliées le sont toujours, celles dépliées aussi. Refaites l'essai **avec le panneau
  Réputation ouvert** pendant que vous ouvrez la liste (si l'interface le permet), puis
  **en combat** : aucun message « action bloquée » (`ADDON_ACTION_BLOCKED`), aucune
  erreur.
- [ ] **Choisir une autre faction** : prenez-en une autre que celle cochée dans le jeu.
  La bande passe aussitôt à cette faction (longueur, couleur), et la faction cochée
  dans le jeu **reste cochée** (la barre de réputation du jeu, si vous l'affichez, ne
  change pas).
- [ ] **Par personnage** : reconnectez-vous (ou `/reload`) : le choix est gardé. Sur un
  autre personnage, la page affiche « auto » (chaque personnage a le sien).
- [ ] **Revenir au jeu** : reprenez « Suivie par le jeu (auto) » : la bande revient à la
  faction cochée dans le jeu.
- [ ] **Une faction jamais rencontrée** (si vous en trouvez une dans la liste sans
  points) : la choisir ne donne pas d'erreur. Si la bande montre alors la faction du jeu
  à la place, l'infobulle de la réputation doit le dire (« La faction choisie dans les
  options n'a pas pu être lue... »). Notez ce que vous voyez : c'est un point que les
  tests hors du jeu ne peuvent pas confirmer.
- [ ] **Une faction choisie rangée sous une catégorie repliée** : choisissez une faction,
  gagnez un peu de réputation avec elle, puis repliez sa catégorie dans le panneau
  Réputation du jeu. Si la barre passe alors à la faction du jeu (l'infobulle le dit),
  dépliez la catégorie : la faction choisie revient avec **sa réputation par heure et
  son gain de la session intacts**. Notez si la barre a changé de faction au repliage :
  c'est un point que les tests hors du jeu ne peuvent pas confirmer.
- [ ] **Les sous-catégories** : dans la liste, une sous-catégorie (Alliance, Horde,
  Forces de l'Alliance...) n'apparaît comme choix que si elle a sa propre barre de
  réputation dans le panneau du jeu.

### L'infobulle de la réputation (survol de la bande)

- [ ] **Le survol** : passez la souris sur la fine bande sous la barre d'XP (la zone
  entre la piste et les textes du bas). Une infobulle « **Réputation** » s'ouvre à la
  place de l'infobulle générale : la faction en en-tête, la ligne « Amical · 1 200 /
  6 000 (20,0 %) » de la couleur du rang, puis « encore 4 800 avant Honoré ». Dites si la
  zone est **assez facile à viser** (elle fait quelques pixels de haut), dans plusieurs
  thèmes (Futuriste, Druide, Pixel, Chaman, Classique).
- [ ] **Sa place** : l'infobulle s'ouvre **au-dessus de la barre** (en dessous si la
  barre est dans la moitié haute de l'écran), comme l'infobulle générale, **jamais
  par-dessus la barre** (la piste et ses textes restent visibles). Même chose en mode
  Réputation (survol de la grande barre) et pour la bande JcJ.
- [ ] **Les 8 rangs** : sous « Rangs », de Haï à Exalté : ceux déjà atteints grisés
  avec « atteint », le rang actuel marqué « » Amical » avec son pourcentage, et pour
  chacun des suivants les points restants (« encore 16 800 »), puis le temps estimé dès
  que le rythme est connu. Les seuils doivent correspondre au jeu (Neutre 0 → 3 000,
  Amical 3 000 → 9 000, Honoré 9 000 → 21 000, Révéré 21 000 → 42 000, Exalté au-delà).
  Pour un personnage féminin, les libellés du jeu au féminin (« Amicale »...) si votre
  jeu les a.
- [ ] **Exalté** : avec une faction Exaltée, la ligne du rang dit « rang maximal », il
  n'y a pas de ligne « Rang suivant ». Si vous pouvez voir les points d'une faction tout
  juste Exaltée, notez-les (le jeu compte-t-il jusqu'à 42 999 ou 43 000 ?).
- [ ] **Clics et glisser** : sur la bande, un clic ouvre les statistiques, un clic
  droit le menu de la barre, comme sur la barre elle-même ; barre déverrouillée, faire
  glisser depuis la bande déplace la barre (et l'infobulle se ferme pendant ce temps).
- [ ] **Thème Classique** (`/tpl theme actuel`) : la même infobulle, dans l'infobulle du
  jeu.

### La réputation par heure et le temps avant le rang suivant

- [ ] **Au départ** : « Réputation par heure » dit « après votre premier gain » (grisé).
- [ ] **Après quelques gains** (quêtes ou monstres qui donnent de la réputation pendant
  une dizaine de minutes) : une valeur par heure, puis le temps avant le rang suivant.
  Dites si les chiffres vous paraissent **réalistes** (comparez avec les gains affichés
  dans le chat).
- [ ] **Les pertes ne comptent pas** : une perte de réputation (tuer un monstre d'une
  faction amie de celle-ci, par exemple) ne fait pas baisser la réputation par heure.
- [ ] **Le gel** : restez 20 minutes de jeu sans gain de réputation (hors AFK) : la valeur
  passe en grisé avec un `*` et une note explique pourquoi ; elle reprend à votre
  prochain gain.
- [ ] **Changer de faction** remet le rythme à zéro ; « Réinitialiser la réputation/h »
  (page Réputation) aussi, sans toucher l'XP par heure. « Réinitialiser les taux/h »
  (page principale, section Données) et `/tpl reset rate` remettent à zéro **tous** les
  taux (XP, réputation, JcJ), et le message le dit.
- [ ] **Les deux infos de la barre** : Options > Barre, choisissez « Réputation par
  heure » puis « Temps avant le rang de réputation » dans un emplacement :
  « Rép. 312/h », « Honoré : 2h 10m ». Au niveau maximum, elles se choisissent aussi
  dans les infos du niveau max.

### La réputation en barre principale

- [ ] **Basculer** : page Réputation > « Barre principale » > **Réputation**. La grande
  barre montre la réputation : à gauche la faction et son rang, à droite les points, le
  repère de pourcentage au bout du remplissage, le remplissage **de la couleur du rang**.
  La fine bande dessous montre maintenant **votre XP** (couleur d'XP du thème, ou la
  vôtre). Rien ne se chevauche.
- [ ] **Dans les 13 thèmes** : passez de thème en thème (`/tpl theme ...`) en mode
  Réputation : la couleur du rang, les graduations ou segments du thème, la bande d'XP
  dessous, sans erreur. Revenez sur « Expérience » : la barre redevient exactement
  comme avant.
- [ ] **Un changement de rang** pendant que l'infobulle est ouverte : la couleur change
  sans fermer l'infobulle.
- [ ] **Exalté** : remplissage plein et atténué, pas de points ni de repère.
- [ ] **Niveau maximum** (ou un personnage au niveau max) : plus de bande d'XP. Avec
  « Masquer au niveau max » coché, la barre **reste affichée** tant qu'elle montre une
  réputation ; sans faction suivie, elle se masque comme avant.
- [ ] **Sans faction suivie** (auto, rien coché dans le jeu) : la barre montre l'XP
  comme d'habitude, même en mode Réputation.
- [ ] **La case de la bande** : en mode Réputation, « Afficher la réputation suivie sous
  la barre » est **grisée**, avec une note dessous (la bande montre alors l'XP) ; en
  mode JcJ la case reste active et la note s'affiche aussi ; en mode Expérience, pas de
  note.
- [ ] **Le repère de pourcentage en Futuriste** : en mode Réputation (ou JcJ), il prend
  une teinte claire de la couleur du remplissage (vert clair pour Amical), et non plus
  le violet de l'XP.
- [ ] **Réapparition au niveau max** : personnage au niveau max, mode Réputation,
  « Masquer au niveau max » coché. Décochez la faction dans le jeu (la barre se masque),
  puis décochez « Masquer au niveau max » : la barre revient avec **NIVEAU 60** aux
  couleurs de l'XP, pas avec l'ancienne faction.

### Pour aller plus loin (facultatif, `/etrace`)

- [ ] Avec `/etrace` ouvert et filtré sur `FACTION`, gagnez de la réputation :
  `UPDATE_FACTION` arrive après chaque gain ; notez ce que porte
  `FACTION_STANDING_CHANGED` quand vous changez de rang. Ouvrez la liste « Faction à
  suivre » : une rafale d'`UPDATE_FACTION` (dépliage, repliage), sans effet visible sur
  la barre. Notez si la rafale arrive **pendant** l'ouverture de la liste (juste avant
  ou au moment où elle s'affiche) ou **après** (une fraction de seconde plus tard) : les
  deux cas sont prévus et sans effet visible, mais c'est ce que les tests hors du jeu ne
  peuvent pas savoir.

## À vérifier en premier : la réputation sous la barre, la barre en Classique, les deux infobulles, « Recharger maintenant », ville et intervalle

**Quittez complètement le jeu et relancez-le d'abord** : cette version ajoute deux
fichiers (`AutoReload.lua` et `Reputation.lua`), et un `/reload` ne charge pas les
nouveaux fichiers. Cochez chaque point vérifié ; s'il ne se passe pas ce qui est écrit,
notez ce que vous voyez (une capture d'écran aide).

### La réputation suivie sous la barre (votre demande du 9 octobre)

Votre demande : la réputation à suivre, au choix, quelque chose de discret sous la barre
d'expérience. Par défaut, TruePlayed suit la faction que vous choisissez **dans le jeu**
(ou celle choisie dans sa page Réputation, voir plus haut) et l'affiche en une fine bande
de 3 pixels sous sa barre d'XP.

- [ ] **Sans faction suivie** : rien ne change, la barre est exactement comme avant
  (même hauteur, textes à la même place). Survolez-la : pas de ligne de réputation dans
  l'infobulle.
- [ ] **Choisir une faction** : ouvrez la fenêtre du personnage, onglet Réputation,
  cliquez une faction (Hurlevent, Orgrimmar...) et cochez la case qui l'affiche comme
  barre d'expérience (« Barre de réputation » sur un client français : c'est le libellé
  du jeu). **La bande apparaît aussitôt** sous la barre d'XP de TruePlayed,
  sans attendre un gain de réputation. Si elle ne vient qu'après un monstre tué ou une
  quête rendue, notez-le : c'est le point que les tests hors du jeu ne peuvent pas
  confirmer.
- [ ] **L'aspect** : la bande est aussi large que la barre d'XP, juste en dessous, sans
  toucher les textes du dessous (`NIVEAU 18`, le pourcentage, `XP : ...`). Elle se
  remplit selon votre progression **dans le rang actuel**, sur un fond sombre discret.
  Dites si elle vous paraît assez discrète, ou trop, et si 3 pixels de haut vous
  conviennent.
- [ ] **La couleur du rang** : rouge (Haï, Hostile), orange (Inamical), jaune
  (Neutre), vert (Amical et au-dessus), les couleurs de la barre de réputation du jeu.
  Une faction à Exalté donne une bande **pleine**.
- [ ] **La bande avance** : gagnez un peu de réputation avec cette faction (une quête de
  la faction, ou un monstre qui en donne) : la bande avance un peu, sans clignoter. Si
  vous changez de rang, elle repart du début, à la couleur du nouveau rang.
- [ ] **Changer de faction** : cochez la case pour une autre faction : la bande change
  aussitôt (longueur et couleur). Décochez la case dans le jeu (plus aucune faction
  suivie) : la bande disparaît et la barre revient exactement à son état d'avant.
- [ ] **L'infobulle** : survolez la barre. Dans « Niveau en cours », juste après le bloc
  XP, une ligne avec **le nom de la faction à gauche** et, à droite, le rang et vos
  points, par exemple « Amical · 1 200 / 6 000 (20,0 %) » (à Exalté : « Exalté » seul).
  Les chiffres doivent correspondre à ceux du panneau Réputation du jeu. Rien n'est
  coupé ; seul un nom de faction très long pourrait être raccourci par « ... », jamais
  les chiffres. Même chose en thème Classique (`/tpl theme actuel`), sur le bouton de la
  minicarte et sur le mini-affichage (qui, lui, n'a pas de bande).
- [ ] **L'option** : Options > TruePlayed > Réputation (elle était dans Affichage) :
  « **Afficher la réputation suivie sous la barre** », cochée par défaut. Survolez son « ? » : la
  bulle dit quelle case cocher dans le panneau Réputation (avec le libellé de votre jeu),
  ce que montre la bande, et que le détail est dans l'infobulle. **Décochez-la** : la
  bande et la ligne de l'infobulle disparaissent, la barre revient exactement à son état
  d'avant. Recochez : elles reviennent aussitôt.
- [ ] **Les thèmes** : changez de thème (`/tpl theme futuriste`, `druid`, `pixel`,
  `heroic`, `priest`, `actuel`...) avec la bande affichée : elle suit chaque thème, sous
  la piste, sans chevaucher les ornements du cadre ni les textes. Selon le thème la barre
  grandit de 4 à 10 pixels, ou pas du tout (Chaman, où la bande tient dans l'espace sous
  la piste). Le repère qui marque le bout de la progression d'XP (flèche, aiguille,
  onglet) ne descend jamais sur la bande : en Pixel, Prêtre, Voleur, Démoniste et
  Futuriste, la bande passe juste sous lui, d'où une barre un peu plus haute. Vérifiez-le
  en particulier dans ces thèmes.
- [ ] **Aucune erreur Lua** pendant tout cela (`/console scriptErrors 1`), y compris en
  changeant de faction ou de thème plusieurs fois de suite.

### La barre de répartition en thème Classique (votre retour du 9 octobre)

Votre remarque : en thème Classique, la répartition n'avait que les valeurs, sans barre.
Elle a maintenant sa barre, comme dans les autres thèmes. Passez en thème Classique
(`/tpl theme actuel`) pour toute cette partie.

- [ ] **Sans Maj** : survolez la barre d'XP. Dans « Niveau en cours », le libellé
  « **Répartition du niveau** » est **seul à gauche de sa ligne**, et **à sa droite une
  barre colorée** commence juste après lui (environ 8 pixels) et va **jusqu'au bord
  droit du texte** de l'infobulle (là où finissent les valeurs des lignes du dessus).
  Les parts (« Monde x % · AFK x % ... ») sont **sur la ligne d'en dessous** (et la
  suivante s'il y en a beaucoup), **alignées à droite**, comme en Futuriste.
- [ ] **La barre vient tout de suite** : elle apparaît en même temps que l'infobulle,
  pas une seconde après. Survolez la barre d'XP une dizaine de fois de suite : jamais
  d'infobulle d'abord sans barre, jamais de barre trop courte qui s'allonge ensuite.
  C'est le point que les tests hors du jeu ne peuvent pas confirmer : s'il y a un
  retard, notez-le.
- [ ] **L'aspect** : la barre est centrée sur la ligne du libellé, sans déborder sur les
  lignes voisines ; la plus grande part est à gauche ; un fin contour sombre l'entoure.
  Les couleurs sont celles de la jauge du thème Futuriste (monde cyan, donjon violet,
  AFK gris...) : dites si elles vous conviennent sur l'infobulle du jeu, ainsi que la
  hauteur de la barre (6 pixels plus le contour) et le contour sombre.
- [ ] **Maj enfoncée** : « Total du personnage » s'ouvre à droite avec **sa propre
  barre**, à côté de « **Répartition totale** », jusqu'à son bord droit, les parts
  dessous. **Les deux barres sont exactement à la même hauteur** : s'il y a un décalage,
  notez de combien de pixels et laquelle est la plus haute (une capture d'écran aide).
  Relâchez Maj : la barre de droite disparaît avec son infobulle, celle de gauche reste
  à côté de son libellé. Appuyez et relâchez plusieurs fois : rien ne clignote.
- [ ] **Aucune barre ne reste** : survolez la barre d'XP, puis passez **vite** la souris
  sur un objet de votre sac, un bouton de vos barres d'action, un personnage, la
  minicarte : la barre de répartition disparaît **tout de suite** et ne se dessine
  jamais sur l'infobulle d'autre chose. Même chose avec Maj enfoncée, et en fermant
  d'un clic le menu du compartiment d'addons après avoir survolé l'entrée TruePlayed.
  Si une barre reste un instant (au plus une seconde) sur une autre infobulle, notez
  laquelle et ce que vous avez survolé.
- [ ] **Largeur** : l'infobulle d'objet que vous survolez ensuite a sa largeur normale.
  La barre fait toujours au moins 80 pixels : si « Niveau en cours » est trop étroite
  pour elle, l'infobulle s'élargit juste ce qu'il faut (cela devrait être rare : en
  général le libellé et la barre tiennent dans la largeur des autres lignes).
- [ ] **Infobulle mise à l'échelle** : si un addon change la taille des infobulles
  (TipTac, ElvUI...), la barre suit (même hauteur que le libellé, jusqu'au bord droit),
  avec Maj aussi. Sans un tel addon, simulez-le : tapez
  `/run GameTooltip:SetScale(1.5)`, survolez la barre d'XP sans puis avec Maj : les
  deux infobulles sont plus grandes, leurs barres aussi, toujours à leur place et à la
  même hauteur. Tapez ensuite `/reload` pour revenir à la taille normale.
- [ ] **Écran étroit** : `/run UIParent:SetScale(UIParent:GetScale() * 2)` (deux fois sur
  un écran très large), puis survolez la barre d'XP avec Maj : les deux infobulles
  empilées, chacune avec sa barre à côté de son libellé, rien qui déborde, aucune barre
  sur l'autre infobulle. `/reload` pour revenir à l'échelle normale.
- [ ] **Les autres affichages** : sur le bouton de la minicarte, le mini-affichage
  (`/tpl mini`) et l'entrée du compartiment d'addons, la même barre. Un affichage Data
  Broker (Titan Panel, ChocolateBar...), si vous en avez un, garde le texte seul : chaque
  libellé et ses premières parts sur la même ligne, pas de barre.

### Les deux infobulles côte à côte (touche Maj)

- [ ] **Barre en haut de l'écran, sans Maj** : survolez la barre. Une seule infobulle,
  « Niveau en cours », sous la barre, placée comme avant. Sa répartition s'appelle
  maintenant « **Répartition du niveau** ».
- [ ] **Maj enfoncée, thème Futuriste** (`/tpl theme futuriste`) : une **deuxième
  infobulle**, « Total du personnage », s'ouvre **à droite** de la première, avec un petit
  écart (environ 4 pixels). La première reste centrée sur la barre, à sa place, et gagne
  le détail du rythme (XP/h). Chaque infobulle garde sa propre largeur.
- [ ] **Les deux jauges face à face** : la jauge « Répartition du niveau » (à gauche) et
  la jauge « **Répartition totale** » (à droite) sont **exactement à la même hauteur**.
  La deuxième infobulle commence donc en général un peu plus bas que la première. S'il y
  a un décalage, notez de combien de pixels et laquelle est la plus haute.
- [ ] **Thème Classique** (`/tpl theme actuel`), Maj enfoncée : deux infobulles du jeu
  côte à côte, et les lignes « Répartition du niveau » et « Répartition totale » (et
  leurs barres, voir la partie précédente) **à la même hauteur**. C'est le point que les tests hors du jeu ne peuvent pas confirmer :
  s'il y a un décalage, notez de combien de pixels et laquelle est la plus haute (une
  capture d'écran aide). Relâchez et réappuyez Maj plusieurs fois : l'alignement est le
  même à chaque fois. Ensuite, survolez un objet de votre sac : son infobulle a sa
  largeur normale. Avec un addon qui change l'aspect des infobulles, la deuxième peut
  garder l'aspect d'origine du jeu : notez-le seulement.
- [ ] **Les libellés** : « Répartition du niveau » et « Répartition totale », avec leurs
  accents, rien de coupé, en Futuriste, Classique, Pixel et un thème de classe. Un
  libellé ne touche jamais sa jauge (ni sa barre en Classique).
- [ ] **Thème Héroïque** (`/tpl theme heroic`, le seul sans jauge) : « Répartition du
  niveau » (et, avec Maj, « Répartition totale ») est **seul sur sa ligne** ; les parts
  (« Monde x % · ... ») sont sur les lignes en dessous, rien n'est coupé.
- [ ] **Maj relâchée** : la deuxième disparaît, la première reste où elle est. Appuyez et
  relâchez plusieurs fois : rien ne saute ni ne clignote.
- [ ] **La ligne d'aide** (« Maj : détails · Clic : statistiques · Clic droit : menu ») est
  en bas de « Niveau en cours » sans Maj, et en bas de « Total du personnage » (à droite)
  avec Maj, plus du tout dans la première.
- [ ] **Barre en bas de l'écran** (déplacez-la dans la moitié basse) : l'infobulle s'ouvre
  au-dessus de la barre. Avec Maj, les deux sont côte à côte au-dessus de la barre, les
  jauges toujours face à face : le bas de la plus basse (en général « Total du
  personnage ») est juste au-dessus de la barre, si bien que « Niveau en cours » monte un
  peu quand vous appuyez sur Maj.
- [ ] **Barre au bord droit de l'écran** (déplacez-la tout à droite, puis survolez-la avec
  Maj) : « Total du personnage » ne sort pas de l'écran. Les **deux infobulles se
  décalent ensemble** vers la gauche, jamais une seule, sans se chevaucher, et les jauges
  restent face à face. Même chose au bord gauche (elles se décalent ensemble vers la
  droite).
- [ ] **Pas de place dessous ou dessus** (avec Maj, thème Futuriste ou Pixel, barre à sa
  place par défaut ou bouton de la minicarte en haut à droite) : c'est plus rare
  maintenant qu'elles sont côte à côte, mais si les deux ne tiennent pas de leur côté de
  la barre (ou du bouton), elles se décalent **ensemble** et recouvrent la barre (ou le
  bouton), sans jamais se chevaucher, et rien ne sort de l'écran. Si l'ensemble est plus
  haut que tout l'écran, « Niveau en cours » reste entière et seul le bas de « Total du
  personnage » sort de l'écran.
- [ ] **Petit écran ou grande échelle d'interface** : quand les deux ne tiennent pas côte à
  côte en largeur, « Total du personnage » passe **sous** « Niveau en cours », les deux
  **de la même largeur**, 4 pixels d'écart, « Niveau en cours » en haut (au-dessus de la
  barre, l'ensemble monte et « Niveau en cours » reste en haut). Pour l'essayer sur un
  grand écran, doublez l'échelle de l'interface avec
  `/run UIParent:SetScale(UIParent:GetScale() * 2)` (si elles restent côte à côte, sur
  un écran très large, tapez la commande une deuxième fois), puis survolez la barre avec
  Maj. À cette échelle, l'ensemble peut être plus haut que l'écran : « Niveau en cours »
  reste alors entière en haut et seul le bas de « Total du personnage » sort de l'écran.
  Tapez ensuite `/reload` pour revenir à l'échelle normale : les deux infobulles
  reviennent côte à côte. Faites-le aussi en thème Classique : les deux infobulles du jeu
  empilées ont exactement la même largeur (s'il y a un écart, notez de combien de pixels
  et laquelle est la plus large). Et sur votre petit écran (celui de la capture où « Total du
  personnage » était coupé en bas) : notez si elles sont côte à côte ou empilées, et si
  quelque chose sort de l'écran.
- [ ] **Maj tenue une dizaine de secondes** : les chiffres des deux infobulles se mettent à
  jour chaque seconde, sans que rien ne bouge (ni les infobulles, ni l'alignement des
  jauges).
- [ ] **Quittez le survol** en gardant Maj : les deux infobulles disparaissent ensemble.
- [ ] **Changement de thème pendant le survol** : le clic droit cache l'infobulle avant
  d'ouvrir le menu, le changement se fait donc avec un délai. Tapez
  `/run C_Timer.After(5, function() SlashCmdList.TRUEPLAYED("theme heroic") end)`, puis
  dans les 5 secondes survolez la barre en gardant Maj enfoncée : quand le thème change,
  les deux infobulles disparaissent ensemble, aucune ne reste à l'écran. Repassez ensuite
  au thème de votre choix (`/tpl theme futuriste` par exemple).
- [ ] **Même chose ailleurs** : sur le bouton de la minicarte, sur le mini-affichage
  (`/tpl mini`) et sur l'entrée TruePlayed du compartiment d'addons (le bouton des addons
  près de la minicarte) : deux infobulles côte à côte avec Maj, jauges face à face, la
  ligne d'aide en bas de « Total du personnage ». Près du bord droit de l'écran (le bouton
  de la minicarte), elles se décalent ensemble vers la gauche. En thème Classique, après
  avoir survolé l'entrée du compartiment d'addons avec Maj puis fermé ce menu d'un clic,
  survolez aussitôt un bouton de vos barres d'action : son infobulle a sa largeur
  normale.
- [ ] **Un affichage Data Broker** (Titan Panel, ChocolateBar, Bazooka...), si vous en avez
  un : son infobulle TruePlayed reste **une seule** infobulle ; avec Maj enfoncée au
  moment du survol, « Total du personnage » vient sous « Niveau en cours », dans la même
  infobulle, avec « Répartition du niveau » puis « Répartition totale ».

### Le bouton « Recharger maintenant » sur Forever

Sur WoW Forever, un addon ne peut recharger l'interface qu'après un clic du joueur :
TruePlayed ne recharge jamais tout seul, il le demande avec une petite fenêtre. Pour la
faire venir vite : Options > « Rechargement automatique », cochez « Recharger aussi à
intervalle régulier », mettez l'intervalle à 10 min, puis jouez 10 minutes dans le monde,
**hors des capitales et des auberges** (si « Recharger en capitale ou à l'auberge » est
cochée aussi, l'intervalle ne demande jamais en ville : voir ci-dessous).

- [ ] La fenêtre « TruePlayed » apparaît en haut de l'écran. Un clic sur **« Recharger
  maintenant » recharge l'interface**, sans message rouge « Interface action failed
  because of an AddOn » ni fenêtre « TruePlayed a été bloqué ».
- [ ] **Juste après un gain d'XP hors combat** (rendez une quête ou découvrez un lieu),
  fenêtre affichée : « Recharger maintenant » reste **grisé une ou deux secondes**, ne
  s'éclaire pas au survol, et un clic ne fait rien ; puis il redevient normal et recharge
  au clic. Si cette quête vous fait monter de niveau, il reste grisé environ 40 secondes.
- [ ] **Engagez un combat** (un monstre à tuer), fenêtre affichée : elle disparaît dès le
  début du combat et revient quelques secondes après la fin, bouton **actif** (environ
  40 secondes après la fin si le monstre vous a fait monter de niveau) : elle attend que
  le gain d'XP du combat soit lu pour revenir, le bouton grisé ne se voit donc pas ici.
- [ ] Si un clic sur « Recharger maintenant » non grisé ne recharge pas, le chat doit
  dire, au plus 5 secondes après, « Pas de rechargement depuis ce bouton pour
  l'instant : tapez /reload. » Cela ne devrait pas arriver : notez-le si vous le voyez.
- [ ] Le bouton « Recharger l'interface » des options (Options > Affichage, sous
  « Langue ») recharge toujours au clic.
- [ ] Pour finir, décochez la case (réglage par défaut), surtout avant la partie sur le
  plantage simulé plus bas.

### En ville après 60 minutes, l'intervalle hors des villes (vos retours du 9 octobre)

Deux changements demandés après votre premier essai : la ville (ou l'auberge) attend
maintenant **60 minutes** de jeu non enregistrées au lieu de 10, et quand les deux cases
sont cochées, l'intervalle **laisse les capitales et les auberges** à la case ville (plus
de doublon). Détail des étapes dans la partie suivante (points 2, 3 et 6) ; l'essentiel :

- [ ] **Bulles** : le « ? » de la case ville dit « après 60 minutes de jeu non
  enregistrées » ; celui de la case intervalle a une ligne de plus : « Si la case
  « Recharger en capitale ou à l'auberge » est cochée aussi, l'intervalle lui laisse les
  capitales et les auberges et n'agit qu'ailleurs. »
- [ ] **Case ville seule** : 15 à 20 minutes après le dernier chargement, sortez au moins
  10 secondes puis entrez en ville et restez-y immobile une minute : **rien ne vient**.
  Après 60 minutes de jeu depuis le dernier chargement, la fenêtre vient en ville comme
  avant (point 3).
- [ ] **Les deux cases, intervalle à 10 min** : faites un `/reload` en ville et restez-y
  plus de 10 minutes : **rien ne vient en ville**. Sortez dans le monde : la fenêtre
  demande quelques secondes après. Rentrez en ville sans répondre : elle **disparaît**
  aussitôt ; ressortez : elle revient quelques secondes après (point 6).

## Rechargement automatique (nouvelle option) et bouton « Recharger l'interface »

**Cette partie ajoute un fichier (`AutoReload.lua`) : quittez complètement le jeu et
relancez-le** (un `/reload` ne charge pas les nouveaux fichiers). Cela vaut pour toute
cette version, parties suivantes comprises.

Sur WoW Forever, le jeu n'accepte un rechargement demandé par un addon qu'après un clic :
TruePlayed ne recharge donc **jamais tout seul**, il demande toujours avec une petite
fenêtre, dont le bouton « Recharger maintenant » recharge à votre clic. Le décompte de
5 secondes dans le chat (« bougez pour annuler ») ne concerne que les autres clients
(Classic Era, retail) : vous ne le verrez pas sur Forever.

1. **Le bouton « Recharger l'interface »** (Options > Affichage, sous « Langue ») : un
   clic recharge l'interface. Aucune fenêtre « TruePlayed a été bloqué » ni message rouge
   « Interface action failed because of an AddOn ».
2. **Les options** : Options > « Rechargement automatique », juste après « Calcul » et
   avant « Villes » : deux cases décochées par défaut, chacune suivie d'un petit « ? »
   cerclé (le même que dans `/tpl stats`), puis le curseur « Intervalle de rechargement »
   (30 min), grisé tant que « Recharger aussi à intervalle régulier » est décochée.
   Survolez chaque « ? » : une bulle avec le nom de l'option en blanc puis les explications
   en doré ; le « ? » prend la couleur d'accent du thème. Case ville : « Pourquoi : … »,
   « Comment : … », puis la ligne « Sur ce client du jeu, un addon ne peut recharger
   l'interface qu'après votre clic : TruePlayed vous le demande donc avec un bouton. ».
   Case intervalle : « Comment : … », puis « Si la case « Recharger en capitale ou à
   l'auberge » est cochée aussi, l'intervalle lui laisse les capitales et les auberges et
   n'agit qu'ailleurs. », puis la même ligne du clic (pas de « Pourquoi », c'est voulu).
   Sur Forever, le « comment » de la case ville dit « après 60 minutes de jeu non
   enregistrées » et qu'« une petite fenêtre propose de recharger », et ne parle **ni**
   d'avertissement dans le chat **ni** de mouvement qui annule. Celui de la case
   intervalle dit qu'une petite fenêtre propose de recharger en ville (« même sans en être
   sorti ») **comme partout ailleurs**, et que « rien ne se recharge sans votre clic » : il
   ne dit plus que la ville recharge d'elle-même.
   Rien ne déborde, en français et en anglais, et le « ? » suit le thème quand vous en
   changez.
3. **En ville (comptez une heure)** : cochez « Recharger en capitale ou à l'auberge » et
   décochez « Recharger aussi à intervalle régulier ».
   - **Avant 60 minutes** : 15 à 20 minutes après le dernier chargement, sortez dans le
     monde au moins 10 secondes, entrez dans une capitale et restez-y immobile une
     minute : **rien ne vient** (on peut rester longtemps en ville sans rien faire).
   - **Après 60 minutes** de jeu depuis le dernier chargement, entrez dans une capitale
     (ou une auberge) en venant du monde et restez immobile 10 secondes, hors combat, sans
     fenêtre ouverte. Une petite fenêtre « TruePlayed » apparaît en haut de l'écran, aux
     couleurs du thème : « Temps de jeu pas encore enregistré : 1 h … », boutons
     « Recharger maintenant » et « Plus tard ».
   - Pour voir qu'elle attend : entrez en ville et, dans les 10 secondes, ouvrez Échap >
     Options ; restez-y 30 secondes : rien ne vient ; fermez : elle arrive quelques
     secondes après. Elle attend de même tant qu'une fenêtre du jeu est ouverte
     (personnage, sorts, marchand, banque, courrier…), pendant une saisie dans le chat, un
     sort en cours ou un craft à l'hôtel des ventes (le temps de métiers n'est pas « en
     ville ») ; « Plus tard » (ci-dessous) donne une nouvelle occasion 10 minutes après.
   - « Plus tard » la ferme ; elle revient 10 minutes après si vous êtes toujours en
     ville, immobile.
   - Le survol de « Recharger maintenant » l'éclaire ; un clic recharge l'interface, sans
     message d'erreur ni fenêtre de blocage. Après le chargement, la session continue (même
     temps de session) et aucune nouvelle ligne /played n'apparaît dans le chat.
   - Si jamais un clic ne recharge pas, le chat dit de taper `/reload`, au plus
     5 secondes après (cela ne devrait pas arriver : notez-le).
   - Facultatif (long) : restez ensuite en ville plus d'une heure (AFK compris) : la
     fenêtre ne revient pas tant que vous n'êtes pas ressorti au moins 10 secondes.
4. **Combat** : la fenêtre affichée (le plus simple : celle de l'intervalle dans le monde,
   point 5), engagez un monstre. Elle disparaît dès le début du combat et revient quelques
   secondes après la fin ; elle n'apparaît jamais en combat.
5. **Intervalle** : cochez « Recharger aussi à intervalle régulier », mettez l'intervalle
   à 10 min et décochez l'option de ville. Dans le monde, 10 minutes après le dernier
   chargement, la fenêtre demande. En donjon, en vol ou mort, elle attend que vous en
   sortiez ; pendant une cueillette, un minage ou un dépeçage aussi (même dans un donjon,
   elle ne vient jamais). Elle ne vient pas non plus pendant une invitation ou une
   proposition. Le texte de la bulle du « ? » suit l'intervalle choisi. Case ville décochée, l'intervalle demande aussi **en ville**
   (même sans en être sorti), comme avant.
   - **Fenêtre déjà affichée** : entrez dans un donjon (ou prenez un vol, ou mourez) sans
     répondre : elle disparaît aussitôt, et revient quelques secondes après votre sortie.
   - Toujours affichée dans le monde, gagnez de l'XP **hors combat** (rendez une quête,
     découvrez un lieu) : la fenêtre **reste**, mais « Recharger maintenant » se grise une
     ou deux secondes (il ne s'éclaire plus au survol et un clic ne fait rien), puis
     redevient normal. Si la quête vous fait monter de niveau, il reste grisé environ
     40 secondes.
   - Toujours affichée, tuez un monstre : le combat la cache (point 4) ; elle revient
     quelques secondes après, bouton actif (environ 40 secondes après si vous avez pris
     un niveau).
6. **Les deux cases cochées** (intervalle à 10 min) : l'intervalle laisse les capitales et
   les auberges à la case ville, pour ne pas faire doublon.
   - Faites un `/reload` dans une capitale et restez-y plus de 10 minutes : **rien ne
     vient en ville**.
   - Sortez dans le monde : la fenêtre demande quelques secondes après. Rentrez en ville
     sans répondre : elle **disparaît** aussitôt (et ne revient pas tant que vous y
     restez) ; ressortez : elle revient quelques secondes après. Pareil en entrant dans
     une auberge.
   - « Plus tard » dans le monde, puis rentrez en ville : même après 10 minutes, rien en
     ville ; elle redemande une fois ressorti.
   - Décochez la case ville en restant en ville, puis fermez les options : la fenêtre
     demande quelques secondes après, en ville (l'intervalle y agit de nouveau).
     Recochez-la, fenêtre affichée : elle disparaît dans la seconde.
   - La case ville garde sa propre règle. Pour que la fenêtre de l'intervalle ne brouille
     pas ce contrôle (affichée dehors, elle resterait en entrant en ville ; un « Plus
     tard » repousserait aussi la case ville, et « Recharger maintenant » remettrait
     l'heure à zéro), mettez d'abord l'intervalle à 120 min (le maximum : il n'est alors
     dû qu'après l'heure de la case ville), puis faites un `/reload`. Après 60 minutes de
     jeu depuis ce chargement, en revenant du monde, la fenêtre vient en ville (point 3).
7. **Aucun effet de bord** : après quelques rechargements par la fenêtre, pas d'erreur Lua,
   pas de fenêtre « TruePlayed a été bloqué » (qui proposerait de désactiver l'addon), et
   les réglages des autres addons et du jeu sont toujours là.
8. Avec WTFix qui protège encore TruePlayed (le message du chat au chargement), la fenêtre
   ne vient jamais : c'est voulu (un rechargement remettrait d'anciennes données).
9. **Pour finir, décochez les deux cases** (réglage par défaut) : la partie suivante simule
   un plantage, et un rechargement en cours de route le fausserait.

## Temps reconstitué après un plantage : exclusions, habitudes récentes, avertissement

Avec la partie ci-dessus, relancez le jeu une fois (nouveau fichier) ; ensuite un
`/reload` suffit pour ces vérifications.

1. **Le cas signalé, sur vos données actuelles** : excluez l'AFK (`/tpl afk`) et survolez
   la barre. Sous « Ce niveau », la ligne « dont reconstitué après un plantage : … » ne
   dépasse **jamais** « Ce niveau » (avant : « Ce niveau 1 h 21 min » puis « dont
   reconstitué… : 1 h 46 min »). Ce temps ayant été reconstitué par l'ancienne version,
   sa part AFK est estimée d'après la part d'AFK du niveau. Même règle avec Maj sous
   « Temps de jeu », dans `/tpl played`, et dans l'onglet Niveaux de `/tpl stats` (le `~`
   devant le temps et la ligne « Dont reconstitué… » de la bulle de la ligne). Réactivez
   l'AFK (`/tpl afk`) : la ligne revient à sa valeur complète.
2. **L'avertissement** : sous la répartition du niveau, une ligne grisée « NN %
   reconstitué après un plantage : répartition estimée » apparaît quand plus de la moitié
   du temps de ce niveau a été reconstitué (c'est sans doute le cas du niveau où vous
   avez vu une répartition identique à celle du personnage). Avec Maj, la même ligne sous
   la répartition du personnage, seulement si plus de la moitié de **tout** son temps est
   reconstituée (rare). Elle revient à la ligne proprement, en français et en anglais,
   dans plusieurs thèmes.
3. **Un plantage simulé** : vérifiez que les deux cases du rechargement automatique sont
   décochées (sinon répondez « Plus tard » à sa fenêtre : un rechargement sauvegarderait
   la session et il n'y aurait presque plus rien à reconstituer). Faites un `/reload`
   (sauvegarde), jouez une vingtaine de minutes dans le monde dont une dizaine AFK
   (`/afk`), puis quittez le jeu de force (Moniteur d'activité, « Forcer à quitter »).
   Relancez et attendez 10 secondes : le chat annonce le temps récupéré. Dans
   l'infobulle :
   - « dont reconstitué après un plantage » sous « Ce niveau » ; avec l'AFK exclu, elle
     perd exactement sa part AFK (environ la part AFK de vos derniers niveaux) ;
   - la répartition du niveau ressemble à celle de **vos derniers niveaux** (le niveau en
     cours et les 5 d'avant), et non plus à celle de tout le personnage : un passé
     lointain en ville ou en auberge ne donne plus de part de ville ou d'auberge si vos
     derniers niveaux n'en ont pas. Un niveau surtout reconstitué par l'ancienne version
     (celui où vous aviez vu la répartition du personnage) ne compte plus comme
     habitude ;
   - si le temps reconstitué fait plus de la moitié du niveau, la ligne grisée du point 2.
4. Le temps reconstitué **avant** cette version garde sa répartition (on ne peut pas la
   refaire) ; seules la ligne « dont reconstitué » (avec exclusions) et l'avertissement
   changent pour lui.

## Infobulle en deux parties : « Niveau en cours » et « Total du personnage »

Le contenu de chaque partie ; leur affichage en deux infobulles côte à côte est dans la
liste en tête de fiche.

1. **Survol simple** de la barre : un titre « Niveau en cours » sous le nom, puis
   uniquement le niveau : XP, repos, temps restant, monstres à tuer, XP/h, session,
   « Ce niveau », « Zone : … » (le temps passé dans cette zone **pendant ce niveau**,
   jamais plus que « Ce niveau », même juste après une réponse /played du serveur) et la
   **répartition de ce niveau**, « Répartition du niveau » (sa jauge avec les thèmes à
   jauge). Plus de « Temps de
   jeu », d'« En instance », de /played du serveur ni de « Moyenne des 5 derniers ».
2. **Passez un niveau** : juste après, « Ce niveau », la ligne « Zone » et la
   répartition au survol repartent de zéro (quelques secondes, « Monde 100 % » par
   exemple), alors que la répartition de Maj (Total du personnage) garde tout
   l'historique.
3. **Maj enfoncée** : l'infobulle « Niveau en cours » reste à sa place (avec le détail du
   rythme XP/h), et une **deuxième infobulle** s'ouvre à sa droite (placement et
   alignement : voir la liste en tête de fiche), titrée « **Total du personnage** » :
   temps de jeu (avec vos exclusions), « En instance », « Zone : … » (tout le temps du
   personnage dans cette zone), /played du serveur, moyenne des 5 derniers niveaux, la
   **répartition du personnage**, « Répartition totale » (sa propre jauge, face à celle
   du niveau), puis zones, continents, capitales, temps et morts comme avant.
4. Les deux titres se distinguent bien du reste dans chaque thème (Futuriste, Classique,
   Héroïque, Pixel et un thème de classe), sans rien de coupé, en français et en anglais.
5. Au niveau maximum (ou au plafond de la bêta), « Niveau en cours » montre la ligne du
   niveau maximum et le temps passé à ce niveau.

## Retours du 7 octobre : aide des colonnes, instances, « Other »

Cette partie **ajoute un fichier** (l'icône `Media/Themes/common/help.tga`) : quittez et
relancez le jeu.

### L'aide des colonnes

1. `/tpl stats` : chaque en-tête de colonne a un petit « ? » cerclé juste après son nom,
   dans les onglets Niveaux, Zones, Sessions et dans la vue du compte.
2. Survolez un en-tête : une bulle donne le nom de la colonne puis son explication (par
   exemple « Server » : le /played du jeu pour ce niveau, qui compte tout). Le « ? » survolé
   prend la couleur d'accent du thème.
3. Changez de thème : les « ? » suivent les couleurs du thème. Vérifiez que le texte des
   bulles revient à la ligne proprement et qu'aucun « ? » ne touche la colonne suivante, en
   anglais et en français.

### Instances et « Other »

1. **Onglet Zones** : la ligne « Other » (« Autres ») des continents n'apparaît plus, et
   « Instances » devient « Donjons » (« Dungeons » en anglais), le nom du breakdown. Une
   ligne « Raids » ou « JcJ » (« PvP ») apparaît dès que vous avez du temps en raid ou en
   champ de bataille. Même chose dans l'infobulle avec Maj.
2. « Instances les plus jouées » : « Undercity (dungeon) » a disparu ; « Ruines de
   Lordaeron » et « Gouffre de Ragefeu » restent, **avec leur nom anglais** si le jeu est en
   anglais (Ruins of Lordaeron, Ragefire Chasm).
3. **Onglet Niveaux** : les niveaux 25 et 26 n'ont plus de « < 1m » dans « Inst. » (ces
   secondes, estimées après une déconnexion, sont passées dans la zone principale du
   niveau). Les niveaux 18 et 23 gardent leur temps de donjon.
4. Entrez dans un donjon depuis une capitale, puis ressortez : la capitale ne doit jamais
   apparaître dans « Instances les plus jouées ».

## Lot 8 (partie B) : infobulle et fenêtre de statistiques revues

Cette partie **n'ajoute aucun fichier** : recopiez le dossier ; un `/reload` suffit si la
partie A est déjà installée (sinon, quittez et relancez le jeu pour `Activity.lua`).

### L'infobulle

1. Survolez la barre : la ligne « Répartition du niveau » liste les parts **de la plus
   grande à la plus petite** (par exemple « Monde 62 % · AFK 20 % · Ville 10 % · ... »),
   et la jauge des thèmes qui en ont une est dans le même ordre.
2. L'infobulle courte ne montre plus « Moyenne par niveau » ; « Moyenne des 5 derniers
   niveaux » reste dès qu'il y a assez de niveaux.
3. Maj enfoncée : « Zones principales » liste vos **3 zones les plus jouées sur tout le
   personnage** (plus seulement le niveau en cours), selon les exclusions (une capitale
   dont tout le temps est exclu n'y figure pas).
4. Maj : plus de bloc « Derniers niveaux », plus de lignes « Compte (...) » ni « Compte,
   en instance », plus de ligne « Reconstitué après plantage » en bas (la sous-ligne « dont
   reconstitué après un plantage » sous « Temps de jeu » reste).
5. Maj : « Morts » tient sur une ligne, par exemple « Morts 3 (12 min) ».

### La fenêtre de statistiques (`/tpl stats`)

1. **Onglet Niveaux** : la première colonne s'appelle « Niveau » et chaque ligne se lit
   « 19 » 20 » : c'est le temps passé au niveau 19 jusqu'au niveau 20. La ligne du niveau
   en cours se lit « 20 » 21 » avec « en cours » dans « Atteint le ».
2. « Atteint le » est la date du passage au niveau suivant (pour « 19 » 20 », le jour et
   l'heure où vous avez atteint 20). Vérifiez avec un passage de niveau récent.
3. Colonne **« Cumul »** : le temps total depuis le niveau 1 jusqu'à ce passage de niveau
   (tout votre /played de l'époque, temps d'avant TruePlayed compris). Sur la ligne en
   cours, il avance avec le temps de jeu. La différence entre deux lignes voisines est le
   temps du niveau.
4. Colonne **« Estim. »** juste à côté de « Temps » : l'estimation affichée au début du
   niveau, à comparer au temps réel (seulement s'il y en a au moins une).
5. **Colonnes vides masquées** : un personnage qui n'a jamais fait d'instance n'a pas de
   colonne « Inst. » ; de même « Auberge », « Ville », « AFK », « Mort », « Métiers »,
   « Estim. » n'apparaissent que si une ligne a une valeur. Faites un peu d'AFK ou de
   métier puis rouvrez la fenêtre : la colonne apparaît et les autres se décalent sans se
   chevaucher. Même chose dans les onglets Sessions et Zones.
6. Survolez une ligne : le titre de la bulle est « Niveau 19 » 20 », puis les zones de ce
   niveau.
7. **Vue du compte** (flèches `<` `>` jusqu'à « Compte ») : les lignes se lisent aussi
   « 19 » 20 », et le bas de la fenêtre donne le total du compte et le temps en instance du
   compte. Pour un personnage, le bas donne la moyenne par niveau et celle des 5 derniers.
8. **Taille** : la fenêtre est assez large pour toutes ses colonnes, dans chaque langue.
   Tirez le coin en bas à droite pour l'agrandir (largeur et hauteur) ; la zone principale
   prend la place gagnée. Fermez et rouvrez, puis `/reload` : la taille est gardée. On ne
   peut pas la rendre plus étroite que ses colonnes.
9. **Onglet Zones, « Capitales les plus fréquentées »** : la colonne « Temps » est remplie.
   Avec l'exclusion de la ville, elle montre le temps passé dans la capitale hors ville
   (vol, métiers, mort), ou « - » s'il n'y en a pas ; « Brut » garde tout le temps passé.

### Format des dates

1. Options > **Fenêtre des statistiques** : « Format des dates » propose « Auto
   (31/12/2026) », « 31/12/2026 », « 12/31/2026 », « 2026-12-31 », et la case
   « Horloge sur 24 heures » (cochée en français).
2. Changez de format pendant que la fenêtre est ouverte : « Atteint le » (onglet Niveaux)
   et les dates de l'onglet Sessions changent tout de suite, toujours avec l'année, les
   heures et les minutes (« 07/10/2026 14h05 » en Auto).
3. Décochez la case : les heures passent en « 2:05 PM ». Recochez-la : « 14:05 ».
4. `/reload` : le choix est gardé.

### Police du thème (thème Druide)

1. Après la mise à jour, lancez le jeu avec le thème Druide : si une police n'est pas
   chargée tout de suite, la barre montre la police du jeu une ou deux secondes, puis la
   police du thème (Alegreya Sans pour les textes, Uncial Antiqua pour les titres).
2. Le message « Police du thème non chargée (...) » ne doit plus s'afficher. S'il
   s'affiche quand même, il nomme **toutes** les polices qui ont échoué, séparées par des
   virgules : recopiez la ligne exacte dans votre retour.

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
3. Survolez la barre : la ligne « Répartition du niveau » contient « Mort x % » (avec sa
   propre couleur dans la jauge des thèmes qui en ont une).
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
  ou un champ de bataille. Au survol, « Répartition du niveau » cite `Donjons` (ou `JcJ`).
  Maj enfoncée, dans « Total du personnage » : une ligne `En instance`, « Répartition
  totale » cite aussi `Donjons`, et `Donjons | 45 min (dont AFK 2 min)`. Dans
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
