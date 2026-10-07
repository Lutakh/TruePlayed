# Publier TruePlayed sur CurseForge : le guide pas à pas

Ce guide part de zéro. Suivez les étapes dans l'ordre. Chaque commande se tape dans
l'application **Terminal** du Mac. Une ligne qui commence par `#` est un commentaire :
inutile de la taper.

Votre copie de travail est le dépôt git cloné depuis GitHub, à la fois l'addon et le dépôt :
`~/Documents/claude/TruePlayed/TruePlayed_on_github` (le reste du guide utilise ce chemin).
Elle a été créée ainsi, une seule fois :

```
cd ~/Documents/claude/TruePlayed
gh repo clone Lutakh/TruePlayed TruePlayed_on_github
```

Pour récupérer les dernières modifications publiées sur GitHub, dans ce dossier :

```
cd ~/Documents/claude/TruePlayed/TruePlayed_on_github
git pull
```

Le dossier voisin `~/Documents/claude/TruePlayed/TruePlayed` est une ancienne copie sans git :
ne le modifiez plus (sauvegarde seulement).

---

## 1. Prérequis

1. Un compte GitHub : https://github.com/signup (gratuit).
2. Les outils `git` et `gh` (l'outil GitHub en ligne de commande), avec Homebrew :

   ```
   brew install git gh lua
   git --version
   gh --version
   lua -v
   ```

3. Connectez `gh` à votre compte. **Tapez cette commande vous-même** et suivez les
   questions (GitHub.com, HTTPS, « Login with a web browser ») :

   ```
   gh auth login
   ```

4. Donnez à git votre nom d'auteur, **Lutak**. Pour ne pas publier votre adresse e-mail,
   utilisez l'adresse « noreply » affichée sur https://github.com/settings/emails
   (copiez-la telle quelle : elle ressemble à `12345678+nom@users.noreply.github.com`) :

   ```
   git config --global user.name "Lutak"
   git config --global user.email "COLLEZ-ICI-L-ADRESSE-NOREPLY"
   ```

## 2. Remplacer `<ACCOUNT>` (déjà fait)

L'auteur (**Lutak**, ligne `## Author:` du `.toc` et fichier `LICENSE`) et le nom
d'utilisateur GitHub (**Lutakh**, dans `## X-Website:` du `.toc`, le README et les pages
CurseForge) sont en place. Il ne reste aucun repère `<ACCOUNT>` : la commande suivante ne
doit rien afficher (la publication, étape 9, refuse de partir sinon).

```
grep -n -e '<AUTHOR>' -e '<ACCOUNT>' TruePlayed_Camelot.toc LICENSE README.md docs/curseforge-*.md
```

## 3. Tester en jeu

### Tests hors jeu (à lancer avant chaque commit)

```
cd ~/Documents/claude/TruePlayed/TruePlayed_on_github
lua tests/run.lua
lua tests/check_toc.lua
lua tests/check_encoding.lua
lua tests/lint51.lua
lua tests/check_globals.lua
lua tests/check_media.lua
```

Chaque commande doit se terminer sans « FAIL ». La vérification automatique de GitHub
(CI) lance en plus `luacheck`, qui refuse le moindre avertissement.

### Installer l'addon dans le jeu

La méthode conseillée est de **copier** le dossier dans le jeu (et de recopier après
chaque modification). Vérifiez bien que `DEST` se termine par `/TruePlayed` : l'option
`--delete` supprime dans ce dossier les fichiers qui n'existent plus dans le dépôt.

```
cd ~/Documents/claude/TruePlayed/TruePlayed_on_github
DEST="/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/TruePlayed"
mkdir -p "$DEST"
rsync -a --delete --exclude '.*' --exclude 'tests' --exclude 'docs' --exclude 'design' \
  --exclude 'tools' --exclude 'media-src' ./ "$DEST/"
```

(`_classic_beta_` est le dossier du client WoW Forever sur votre Mac ; adaptez-le si le
vôtre est différent.)

Si vous préférez un lien symbolique (`ln -s`) au lieu d'une copie : le lanceur de
**WTFix** peut réécrire le fichier `.toc` et y ajouter une ligne `## X-WTFix-Managed`.
Avec un lien, cette modification arriverait dans votre dépôt git. Dans ce cas, lancez
toujours `git diff` avant un commit ; `lua tests/check_toc.lua` échoue si la ligne est
présente, et cette commande l'annule :

```
git checkout -- TruePlayed_Camelot.toc
```

### Dans le jeu

Pour le **tout premier essai**, suivez la fiche courte `docs/TEST-EN-JEU-fr.md` (installation,
redémarrage, ce qu'il faut regarder et comment signaler un problème). La liste ci-dessous
est la vérification complète à refaire avant chaque version.

1. Lancez WoW Forever. Dans la liste des addons, TruePlayed doit apparaître avec l'icône
   de montre à gousset, sans la mention « périmé ».
2. Activez l'affichage des erreurs Lua, puis rechargez l'interface :

   ```
   /console scriptErrors 1
   /reload
   ```

3. Vérifiez au minimum, avant chaque version :
   - premier lancement : message de placement, barre déverrouillée ; déplacez-la, clic
     droit > Verrouiller ; après `/reload`, elle reste à sa place ;
   - `/afk` avec « Exclure le temps AFK » : les infos s'assombrissent avec un signe de
     pause, l'infobulle indique « Chrono en pause » ; décochez : mêmes chiffres qu'avant ;
   - chaque exclusion depuis le menu du clic droit change immédiatement les temps,
     la moyenne, l'XP par heure et le temps avant le niveau ;
   - pierre de foyer et `/reload` : la session continue, l'XP par heure ne repart pas
     à « ... » ;
   - premier chargement sur un personnage qui a déjà joué (au moins 30 minutes) : l'XP
     par heure et le temps avant le niveau s'affichent tout de suite avec un `~`, même en
     ville avec les exclusions ; l'infobulle précise « estimation d'après votre /played » ;
   - barre en français à la largeur minimale, texte 16 : en bas à droite les nombres
     raccourcissent (`58 / 23,2k`) sans jamais toucher `NIVEAU 20` ; en haut, l'info 3 ne
     touche jamais l'info 1 ; le pourcentage a une décimale (`0,3 %`) ;
   - `/tpl stats zones` : bloc « Continents » au-dessus des capitales, aucun continent
     (Kalimdor, Royaumes de l'Est) dans la liste des zones ;
   - montée de niveau : nouvelle ligne dans l'historique (`/tpl stats`) ;
   - sans exclusion, « Temps de jeu » dans l'infobulle = le `/played` à 1 minute près ;
   - plantage simulé : quittez le jeu de force (Moniteur d'activité) après 20 minutes,
     reconnectez-vous et attendez 10 secondes : le total égale le `/played`, le chat
     annonce le temps récupéré et l'infobulle indique « dont reconstitué après un
     plantage : X min » ;
   - donjon : passez AFK à l'intérieur, aucune erreur Lua ; avec l'option expérimentale
     « Masquer les lignes du /played » cochée, recevez un chuchotement dans le donjon puis
     tapez `/played` : aucune erreur dans le chat ;
   - combat avec « Masquer en combat » : la barre disparaît puis revient ;
   - donjon, raid ou champ de bataille : l'infobulle affiche « En instance » et la
     répartition cite « Donjons », « Raids » ou « JcJ » ; `/tpl stats zones` montre le
     bloc « Instances les plus jouées » avec le type après le nom ;
   - un monstre tué (aussi dans un donjon) : « Monstres à tuer : ~N (moyenne : M XP,
     dernier : X XP) » dans l'infobulle (M = moyenne des 10 derniers) et
     `~temps · N monstres` en haut à droite ; une quête rendue ne change ni « moyenne » ni
     « dernier » ;
   - personnage reposé : barre bleue avec une partie bleu clair, ligne « Reposé » ; le
     repos consommé, la barre redevient violette ;
   - survol des FPS ou de la latence : le graphique s'affiche, le survol d'un point donne
     sa valeur (« il y a 23 s : ... »), il disparaît quand la souris s'en va ; refaites
     `/tpl perf` en gardant la souris sur le graphique : la ligne « Tic » reste basse ;
   - Options > Textes : couleur du texte (« Annuler » puis « Couleurs d'origine »),
     contour Aucun / Fin / Épais, opacité du fond de 0 à 100 % ;
   - accents, `·`, `«`, `»` et `~` s'affichent sans carrés ;
   - Options > Affichage > « Langue (Language) » : choisissez English, cliquez
     « Recharger l'interface » : tous les textes de TruePlayed (barre, infobulle, fenêtre,
     options, menu du clic droit, chat) sont en anglais, les noms de zones restent en
     français ; `/tpl lang auto` puis `/reload` ramène le français ;
   - `/tpl perf` : notez la ligne « Mémoire », rejouez une heure, retapez `/tpl perf` : le
     chiffre doit rester **stable** (il compte le code de l'addon, environ 0,5 Mo, plus les
     données de tous vos personnages : il grandit avec le nombre de personnages, ce n'est
     pas une fuite). Aucune baisse de FPS.

   Vérifiez aussi ces hypothèses du code, **en notant les résultats** :
   - dans chaque capitale, tapez `/dump C_Map.GetBestMapForUnit("player")` : le numéro
     doit être entre 1453 et 1458 (notez tout autre numéro, par exemple pour une capitale
     propre à Forever) ;
   - près d'un feu de camp, `/dump IsResting()` : notez `true` ou `false` ;
   - `/tpl debug`, puis tuez un monstre en étant reposé : notez la ligne
     « XP gain ... dRest ... r ... » ; `dRest` doit valoir environ -2 fois le `r` de la même
     ligne (sinon les réglages `REST_BONUS` / `REST_DRAIN` de `Core.lua` sont à corriger) ;
     retapez `/tpl debug` pour couper les messages ;
   - vol au-dessus d'Orgrimmar ou de Hurlevent : notez dans l'infobulle détaillée (Maj) les
     lignes « Ville » et « En vol » avant et après le vol ; seule « En vol » doit augmenter ;
   - largeur minimale, taille de texte 16, info 3 à gauche puis
     au centre, pourcentage « Suit la barre » : aucun texte ne se chevauche ;
   - Échap > Options > AddOns > TruePlayed ouvre les options ; `/tpl` ouvre la même page ;
     le bouton TruePlayed du menu des addons (clic gauche : options, clic droit :
     statistiques) fonctionne ; `/tpl` en combat s'ouvre après le combat ;
   - un autre personnage portant le même prénom : données séparées ; dans la fenêtre de
     statistiques, les flèches < > montrent chaque personnage et le bouton « Effacer... »
     demande confirmation ;
   - WTFix : TruePlayed coché dans `/wtfix`, un avertissement WTFix s'affiche une seule
     fois par chargement ; décochez-le, jouez 5 minutes puis `/reload` : les données
     restent et aucun « Temps de jeu récupéré » n'apparaît ;
   - `/tpl citytoggle` dans un donjon : « Les instances ne comptent jamais comme des
     villes. » s'affiche et rien ne change ;
   - dans un donjon, un raid et un champ de bataille, tapez `/dump IsInInstance()` :
     notez le second résultat (`party`, `raid`, `pvp`...), qui décide du type compté.
4. Envoyez les numéros et résultats notés, avec une capture d'écran de chaque écran
   vérifié. En cas d'erreur, envoyez le texte complet de l'erreur, ou le fichier le plus
   récent du dossier `/Applications/World of Warcraft/_classic_beta_/Errors/`.

Les données enregistrées par l'addon se trouvent dans
`/Applications/World of Warcraft/_classic_beta_/WTF/Account/<VOTRE_COMPTE>/SavedVariables/TruePlayed.lua`
(copiez ce fichier si vous voulez en garder une sauvegarde).

## 4. Le dépôt GitHub (déjà fait) et la branche `main`

Le dépôt public existe : https://github.com/Lutakh/TruePlayed, et sa vérification
automatique (CI : tests en Lua 5.1 et 5.5, vérifications et luacheck) tourne à chaque
envoi. Les évolutions arrivent sur des branches de travail : **la version publiée part
toujours de `main`**. Avant de publier :

1. Fusionnez la branche de travail dans `main` par une *pull request* sur GitHub (bouton
   **Merge**), une fois sa CI verte.
2. Récupérez `main` sur le Mac et vérifiez que sa CI est verte :

   ```
   cd ~/Documents/claude/TruePlayed/TruePlayed_on_github
   git checkout main
   git pull
   gh run list --branch main --limit 3
   ```

La ligne « CI » la plus récente doit être `completed success`. Si elle est rouge, voir
l'étape 13.

## 5. Créer le projet CurseForge

### Avant : captures d'écran et logo

- **Captures d'écran** (3 à 5, prises en jeu) : la barre, l'infobulle normale et avec Maj,
  la fenêtre de statistiques (onglet Niveaux avec les zones d'un niveau au survol, onglet
  Zones), les options. Pour capturer : la touche de capture d'écran du jeu (cherchez
  « Capture d'écran » dans Échap > Options > Raccourcis) enregistre l'image dans
  `/Applications/World of Warcraft/_classic_beta_/Screenshots/` ; ou, sur le Mac,
  `Cmd + Maj + 4` puis la barre d'espace et un clic sur la fenêtre du jeu (l'image arrive
  sur le Bureau). Pas d'image générée ou retouchée par IA sans mention visible.
- **Logo** : une image carrée de 400 x 400 pixels, pas d'une seule couleur. N'utilisez
  **pas** l'icône de montre à gousset du jeu : c'est une image Blizzard protégée. Une image
  simple suffit : le mot « TruePlayed » en blanc sur fond violet `#8B5CF6` (la couleur de
  l'addon), avec dans un coin un petit badge « FOREVER » pour que les joueurs de WoW
  Forever reconnaissent tout de suite l'addon.

### Le projet

Le nom reste exactement **TruePlayed** : CurseForge interdit le nom du jeu ou d'une
version dans le nom d'un projet (pas de « TruePlayed Forever »). « WoW Forever » va donc en
tête du résumé, dans la description, les mots-clés et le badge du logo.

1. Allez sur https://authors.curseforge.com et connectez-vous (le bouton GitHub convient).
2. Cliquez sur **Create A Project**, puis choisissez **World of Warcraft**.
3. Remplissez les champs avec le contenu de `docs/curseforge-en.md` :
   - **Name** : `TruePlayed` ;
   - **Summary** : la phrase « Summary » du fichier, qui commence par « WoW Forever » ;
   - **Description** : tout ce qui suit le premier trait `---` du fichier (éditeur
     Markdown), tel quel. Ses images (`media-src/curseforge/page/*.png`) sont lues sur la
     branche `main` de GitHub : elles n'apparaissent qu'une fois ces fichiers sur `main`.
     Les captures du jeu, elles, vont dans l'onglet **Images** du projet ;
   - **Class** : Addons ; **catégorie principale** : Quests & Leveling ; **catégorie
     supplémentaire** : Miscellaneous ;
   - **License** : MIT ;
   - **Logo** : l'image préparée ci-dessus.
4. Enregistrez le projet. Notez son numéro : **Project ID**, dans l'encadré
   « About Project » de la page du projet.
5. Envoyez les captures dans l'onglet **Images** du projet.

**Version de jeu « Forever ».** CurseForge range les fichiers WoW par version de jeu ; WoW
Forever a sa propre famille, « Forever », en version **1.60.1**. L'outil de publication la
choisit tout seul d'après la ligne `## Interface: 16001` du `.toc`. Après la première
publication (étape 10), vérifiez dans l'onglet **Files** que le fichier porte bien
« Forever 1.60.1 ». Si un jour vous envoyez un fichier à la main, cochez cette version-là
(et elle seule).

## 6. Clé d'API CurseForge

1. Sur https://authors.curseforge.com, ouvrez les réglages de votre compte, rubrique
   **API tokens**, et créez un jeton (nom : `GitHub TruePlayed`). Copiez-le.
2. Enregistrez-le comme secret du dépôt GitHub. La commande marche depuis n'importe quel
   dossier (`--repo` désigne le dépôt) ; elle demande la valeur : collez-la à l'invite et
   validez. Elle n'apparaît ni à l'écran, ni dans un fichier, ni dans l'historique.

   ```
   gh auth status
   gh secret set CF_API_KEY --repo Lutakh/TruePlayed
   gh secret list --repo Lutakh/TruePlayed
   ```

   Ou sur le site : https://github.com/Lutakh/TruePlayed/settings/secrets/actions, bouton
   **New repository secret**, nom `CF_API_KEY`, valeur : le jeton.

Ne collez jamais cette clé dans un fichier, un message ou une conversation.

## 7. Le numéro du projet dans le `.toc` (déjà fait)

Le projet CurseForge porte le numéro **1721055** (il figure dans l'adresse du portail auteur,
`authors.curseforge.com/#/projects/1721055/...`, et dans l'encadré « About Project » de la
page publique). La ligne `## X-Curse-Project-ID: 1721055` est dans le `.toc`, juste après
`## X-Website:` ; `lua tests/check_toc.lua` vérifie que c'est bien un nombre.

Ne la changez jamais pour un autre numéro : l'outil de publication s'en sert pour envoyer le
fichier.

## 8. Wago (facultatif)

Wago est utilisé par des gestionnaires d'addons comme WowUp. La prise en charge de
Forever par Wago n'est pas encore confirmée : sans clé Wago, cette plateforme est
simplement ignorée.

1. Créez le projet sur https://addons.wago.io/developers et notez son identifiant à
   8 caractères.
2. Ajoutez-le au `.toc` (remplacez `AbCd1234`) :

   ```
   perl -0pi -e 's/(## X-Website: [^\n]*\n)/$1## X-Wago-ID: AbCd1234\n/' TruePlayed_Camelot.toc
   ```

3. Créez une clé sur https://addons.wago.io/account/apikeys, puis :

   ```
   gh secret set WAGO_API_TOKEN --repo Lutakh/TruePlayed
   git commit -am "Add the Wago project ID"
   git push
   ```

## 9. Publier la version 1.0.0

1. **Aperçu du zip (conseillé)** : sur GitHub, onglet **Actions** > **Package preview** >
   **Run workflow**, branche `main`. En une minute ou deux, la page du run propose en bas
   (« Artifacts ») le fichier `TruePlayed-....zip` : c'est exactement le zip que recevra
   CurseForge, mais rien n'est publié. Ou depuis le Terminal :

   ```
   gh workflow run package-preview.yml --ref main
   sleep 5; gh run watch
   RUN=$(gh run list --workflow package-preview.yml --limit 1 --json databaseId --jq '.[0].databaseId')
   gh run download "$RUN" --dir ~/Downloads/tp-preview
   ```

   Pour l'essayer en jeu : jeu fermé, mettez de côté votre dossier
   `Interface/AddOns/TruePlayed`, décompressez le zip dans `Interface/AddOns` (il contient
   le dossier `TruePlayed`), lancez le jeu et faites un tour rapide (barre, infobulle,
   `/tpl stats`, `/tpl perf`, aucune erreur Lua). Le zip ne contient ni `tests`, ni `docs`,
   ni `design`, ni `tools`, ni `media-src`.
2. Sur `main` (étape 4), ouvrez `CHANGELOG.md` : le titre `## [1.0.0] - 2026-10-01` porte
   la date de préparation ; si vous publiez un autre jour, mettez la date du jour. Relisez la
   section entière : c'est le texte que verront les joueurs sur CurseForge. L'étiquette
   `v1.0.0`, sans suffixe, publie un fichier de type **Release** (proposé à tous les joueurs).
3. Lancez les tests hors jeu (étape 3), puis :

   ```
   cd ~/Documents/claude/TruePlayed/TruePlayed_on_github
   git checkout main
   git commit -am "Release 1.0.0"      # seulement si vous avez changé la date
   git push
   git tag v1.0.0 && git push origin v1.0.0
   ```

L'étiquette (tag) déclenche la publication : tests, contrôle des repères, notes de
version tirées du CHANGELOG, puis création du zip et envoi vers CurseForge, Wago (si la
clé existe) et GitHub Releases.

## 10. Suivre la publication

```
gh run watch
```

(ou l'onglet **Actions** du dépôt). Une plateforme sans clé est sautée **sans message
d'erreur** : dans le journal de l'étape « BigWigsMods/packager », vérifiez qu'une ligne
parle bien de l'envoi vers CurseForge.

Ensuite, CurseForge vérifie chaque fichier : de quelques minutes à 3 jours ouvrés. Le
fichier apparaît dans l'onglet « Files » du projet, d'abord « Under review ».

## 11. Les versions suivantes

- Numérotation SemVer (depuis la 1.0.0) :
  - `1.0.1` : correctif ;
  - `1.1.0` : nouvelle fonction ;
  - `2.0.0` : changement incompatible des données ou des options.
- Le type de fichier dépend de l'étiquette : `v1.1.0-beta.1` donne une Beta, une
  étiquette contenant `alpha` une Alpha, `v1.1.0` une Release. **Attention : `-rc.1`
  part en Release.**
- Ne réutilisez jamais une étiquette : en cas d'erreur, passez au numéro suivant
  (`v1.0.1`).
- Pour chaque version, ajoutez dans `CHANGELOG.md` une section `## [x.y.z] - AAAA-MM-JJ`
  écrite pour les joueurs (la publication refuse de partir sans elle).
- Quand WoW Forever change de version, `/dump select(4, GetBuildInfo())` donne le nouveau
  numéro : mettez à jour la ligne `## Interface:` du `.toc` (et `EXPECTED_INTERFACE` en
  haut de `tests/check_toc.lua`), puis publiez une nouvelle version.

## 12. Règles à respecter

- Aucune clé d'API dans un fichier du dépôt (elles vivent dans les secrets GitHub).
- Des captures d'écran **réelles**, prises en jeu. Une image générée ou retouchée par IA
  doit porter une mention visible sur CurseForge.
- Aucune demande de dons dans le jeu. Un lien de don n'est permis qu'en bas de la page
  CurseForge.
- Le code reste lisible par tous (règle de Blizzard) : pas de code caché ni brouillé.
- Répondez aux commentaires CurseForge et aux « issues » GitHub.
- Restez sur GitHub (Codeberg refuse les projets écrits surtout par une IA). Le README
  indique que l'addon a été développé avec l'aide de Claude.

## 13. En cas de problème

### Disponibilité dans le client CurseForge — retour confirmé le 2026-10-02

La 1.0.0 était approuvée, de type Release et marquée Forever 1.60.1, mais
n'apparaissait pas dans la recherche du client CurseForge. Elle ne contenait que
`TruePlayed_Camelot.toc`. La 1.0.1 ajoute `TruePlayed.toc`, une copie identique du TOC
Forever ; après publication, l'auteur a confirmé que l'addon était visible dans le
client. Conserver cette structure pour les prochaines versions, même si le suffixe
`_Camelot` est valide pour le jeu. Ce retour confirme le résultat pour TruePlayed,
sans prouver à lui seul le fonctionnement interne de l'indexation CurseForge.

- Le ZIP doit contenir un seul dossier racine `TruePlayed/`, avec directement
  `TruePlayed.toc` et `TruePlayed_Camelot.toc`.
- Modifier **les deux TOC ensemble** : ils doivent rester strictement identiques
  (métadonnées, interface, identifiant CurseForge, fichiers et ordre de chargement).
  `lua tests/check_toc.lua` vérifie cette égalité.
- Garder `## X-Curse-Project-ID: 1721055` et publier un tag sans suffixe beta/alpha
  pour obtenir une Release, avec la version de jeu Forever appropriée.
- Vérifier le paquet généré, puis le succès de l'envoi à CurseForge dans le journal
  du workflow Release ; attendre l'approbation du fichier avant de vérifier sa
  présence dans le client, sur l'instance **Forever**.
- Au moment du correctif, le client installé était en `1.60.1.70170` et utilisait
  toujours l'interface `16001`. Un nouveau numéro de build ne signifie pas forcément
  une nouvelle interface : vérifier avec `/dump select(4, GetBuildInfo())`, puis
  mettre à jour les deux TOC et `EXPECTED_INTERFACE` seulement si nécessaire.


- **L'Action est rouge** : cliquez sur l'étape en échec pour lire le message.
  - « Unit tests », « TOC check », « Encoding check », « Lua 5.1 portability lint » :
    relancez la même commande en local (étape 3) pour voir le détail.
  - « Luacheck » : le message donne le fichier, la ligne et le code de l'avertissement
    (par exemple `211` = variable locale inutilisée).
  - « Refuse placeholders » : il reste `<ACCOUNT>` (étape 2).
  - « Release notes from CHANGELOG » : il manque la section `## [x.y.z] - date` de cette
    version, ou la date est encore `YYYY-MM-DD` (étape 9).
- **« Ambiguous addon name »** dans le journal du packager : la ligne
  `package-as: TruePlayed` manque dans `.pkgmeta`.
- **Tout est vert mais rien n'arrive sur CurseForge** : vérifiez `gh secret list`
  (le secret doit s'appeler exactement `CF_API_KEY`) et la ligne
  `## X-Curse-Project-ID` du `.toc`.
- **Fichier bloqué en « Under review »** : c'est la vérification de CurseForge ; attendez
  (jusqu'à 3 jours ouvrés) et surveillez vos e-mails.
- **L'addon est « périmé » (out of date) en jeu** : le numéro `## Interface` est plus
  ancien que celui du jeu. Voir l'étape 11 ; en attendant, les joueurs peuvent cocher
  « Charger les addons périmés ».
- **`check_toc` signale `X-WTFix-Managed`** : `git checkout -- TruePlayed_Camelot.toc`,
  puis préférez la copie au lien symbolique (étape 3).
- **`gh: command not found`** : `brew install gh`, puis `gh auth login`.
