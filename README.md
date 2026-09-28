# Arcanes & Lames

Jeu de cartes 2D au tour par tour inspiré de Hearthstone, dans un univers médiéval-fantastique
en pixel art 8-bit, avec des effets visuels 3D pour les capacités des cartes. Moteur : **Godot 4.7**.

## Lancer le jeu

Ouvrir le dossier dans Godot 4.7 puis **F5** (scène principale : `scenes/main_menu.tscn`).

## Contenu

| Écran | Description |
|---|---|
| Démarrage | Vérification de version, mise à jour automatique |
| Menu principal | Défier l'IA, Multijoueur, Collection, Classement, Amis, Règles, Paramètres, badge de profil |
| Collection | Toutes les cartes, filtres, explication détaillée, mots-clés, **aperçu de l'effet 3D** |
| Combat | Plateau, main (rangement manuel / coût / PV / attaque, jeu en 2 clics), ciblage à la souris, chrono, journal + discussion, effets 3D, revanche en ligne |
| Échap (partout) | Ferme la fenêtre ouverte ; sinon Profil (pseudo, avatar, personnalisation), Audio, Affichage, Jeu (difficulté, vitesse), Raccourcis, Règles |
| Multijoueur | Créer une partie ou rejoindre la liste des parties ouvertes (serveur officiel), invitations d'amis |
| Personnalisation | Titres, avatars, contours d'avatar, dos de cartes, plateaux à débloquer (`data/cosmetics.json`) ; accès par le badge de profil |
| Statistiques | Statistiques globales du jeu (toutes les parties enregistrées) : cartes les plus jouées, % de victoires, durée, IA |
| Profils et replays | Recherche dans le classement, profil public d'un joueur, historique et replays (« Revoir ») |
| Messages | Messagerie privée avec les amis connectés, historique conservé sur le serveur, notifications « Répondre » |

### Règles (résumé)
- 25 PV par héros au départ, **sans maximum** (les soins peuvent dépasser) ; une pièce aux avatars des joueurs désigne qui commence ; **énergie** : 1 au premier tour, +1 par tour (max 10), rechargée à chaque tour.
- Les deux camps jouent **le même deck de 100 cartes** (59 cartes différentes en 1 à 4 exemplaires, mélangé différemment).
- **Pioche au choix** : au début de son tour, on révèle 3 cartes, on en garde une, les 2 autres vont au fond du deck.
- **Enchantements** (2 max par joueur, sans PV) : effet permanent ou à chaque tour, retirés uniquement par les cartes de destruction.
- Serviteurs à **effet continu** (aura, début / fin de tour), cartes liées au **cimetière**, cartes qui retirent des cartes des decks.
- IA : Apprenti, Chevalier, Seigneur de guerre (difficile : simule ses coups et le tour adverse ; `tests/ai_bench.tscn`).
- **Défausse** gratuite pendant son tour (petit X sur la carte survolée).
- Mots-clés : Provocation, Charge, Bouclier divin, Cri de guerre, Râle d'agonie, Effet continu.
- Détail complet : menu principal > Règles du jeu, ou Échap > Règles.

## Multijoueur

### Serveur officiel (VPS) — par défaut
Le jeu se connecte automatiquement au serveur officiel **203.0.113.10** (VPS OVH). Il gère les
**comptes (pseudo unique + avatar)**, le **classement**, les **amis**, les **invitations**, et
**relaie toutes les parties** : les joueurs n'ont **aucun port à ouvrir** (pas de connexion de joueur à joueur).

1. Dans le jeu : **Échap > Profil** : choisir un pseudo + avatar (connexion automatique).
2. **Multijoueur** : **créer une partie** (nom facultatif) — elle apparaît dans la **liste des parties
   ouvertes** de tous les joueurs, mise à jour en direct — ou **rejoindre** une partie de la liste.
   L'hôte clique sur **Lancer la partie** quand l'adversaire est là.
3. **Amis** : ajouter un ami par son pseudo, puis l'inviter directement (notification *Rejoindre*).

Aucun port, aucune adresse IP : l'ancienne connexion directe a été retirée du jeu.

Page de téléchargement du jeu : **https://arcanes.example.com/**

Installation recommandée pour les joueurs (Windows + R, puis coller) :
`powershell -c "irm https://arcanes.example.com/install.ps1 | iex"`
Le jeu est téléchargé en HTTPS, son empreinte SHA-256 et sa signature sont vérifiées, puis il est installé
dans `%LOCALAPPDATA%\Programs\ArcanesEtLames` avec des raccourcis (aucun avertissement SmartScreen,
car un téléchargement fait par PowerShell ne porte pas la marque « provenant d'internet »).

### Signature de l'exécutable
L'exe est signé et horodaté à chaque publication avec le certificat auto-signé **« Arcanes & Lames »**
(empreinte `D2B812C2D48C282248BD97706AAE9610B66AC854`, valable jusqu'en 2036), stocké dans le magasin de
certificats Windows de ce PC. La sauvegarde de la clé privée est dans `%USERPROFILE%\.arcanes-codesign\`
(`.pfx` + mot de passe) : **à conserver précieusement**, car sans elle on ne pourrait plus signer avec
la même identité. L'installateur refuse tout exe dont la signature ne correspond pas à cette empreinte.
Un certificat auto-signé n'est pas reconnu par Windows : c'est l'installateur PowerShell qui évite
l'avertissement ; le zip manuel l'affiche toujours.

### Installation sur le VPS (déjà faite)
| Élément | Emplacement |
|---|---|
| Service systemd | `arcanes-lobby.service` (utilisateur système `arcanes`, isolé, 256 Mo max) |
| Code | `/opt/arcanes/lobby_server.py` |
| Comptes / classement | `/var/lib/arcanes/lobby_data.json` |
| Historique des parties | `/var/lib/arcanes/history.db` (SQLite, toutes les parties, sans limite) |
| Sauvegardes | quotidiennes dans `/var/backups/arcanes/`, toutes conservées |
| HTTPS | nginx : `/etc/nginx/sites-available/arcanes-vps-hostname.conf` (certificat Let's Encrypt renouvelé automatiquement) |
| Versions publiées | `/srv/arcanes/updates/` (latest.json, .pck, .zip) |
| Ports (pare-feu ufw) | TCP 7778 (jeu), TCP 7779 (HTTP), 443 via nginx (HTTPS) |

Il cohabite avec les autres projets du VPS (nginx, Apache, Docker, MySQL non modifiés).
Commandes utiles (`ssh arcanes-vps`) : `sudo systemctl restart arcanes-lobby`,
`sudo journalctl -u arcanes-lobby -f`. Pour mettre à jour le code du serveur :
`scp server/lobby_server.py arcanes-vps:/tmp/` puis
`sudo install -m 644 /tmp/lobby_server.py /opt/arcanes/ && sudo systemctl restart arcanes-lobby`.

Pour héberger votre propre serveur à la place : `server/lancer_serveur.bat` (Python 3.9+), ports TCP 7778
et 7779 ouverts, puis indiquer son adresse dans **Échap > Profil**.

### Architecture réseau
L'hôte fait autorité ; les deux machines exécutent la même simulation déterministe (`GameState`,
même graine aléatoire) et n'échangent que les actions (jouer, attaquer, fin de tour, abandon) plus le chat,
relayées par le serveur.

### Sécurité et anti-triche (1.8.0)
- **Parties vérifiées** : au début de chaque partie, le jeu demande un « ticket » au serveur (`match_start`),
  qui tire la graine et le premier joueur. En fin de partie, le serveur **rejoue** la partie avec le moteur du jeu
  (Godot sans affichage, scène `scenes/tools/verifier.tscn`, logique dans `scripts/core/match_check.gd`) :
  chaque action doit être légale, les coups de l'IA sont recalculés (IA déterministe, graine dérivée de celle
  de la partie) et le vainqueur, les tours et les statistiques sont calculés par le serveur. Victoires, PO, XP,
  statistiques et historique ne sont accordés qu'aux parties validées ; les refus sont notés dans le compte
  (`cheat_flags` de `lobby_data.json`). Durée mesurée par le serveur.
- **En ligne**, le serveur enregistre lui-même les actions relayées (demandes de l'invité, actions appliquées
  et refus de l'hôte) : une action de l'invité doit avoir été demandée, un refus doit être justifié. Le serveur
  impose la graine du ticket dans `_start` et remplace pseudo, avatar et personnalisation par ceux du compte.
  Quitter une partie en cours = abandon. Au-delà de 10 parties par jour contre le même adversaire, plus rien n'est compté.
- **Limites** : débit de messages par connexion, 3 comptes créés par IP et par heure, 8 connexions par IP.
- **TLS** : le jeu se connecte au serveur officiel en TLS sur le port **7780** (certificat Let's Encrypt du nom
  d'hôte vérifié). Le certificat est copié dans `/var/lib/arcanes/tls` par le hook
  `/etc/letsencrypt/renewal-hooks/deploy/arcanes-lobby-tls.sh` à chaque renouvellement. Le port 7778 (en clair)
  reste ouvert pour les serveurs de test et les anciennes versions.
- **Mises à jour signées** : `latest.json` est signé (RSA 3072, SHA-256) par `tools/publish_update.py` avec la clé
  `%USERPROFILE%\.arcanes-codesign\update_signing_key.pem` ; la clé publique est dans `scripts/autoload/updater.gd`.
  Le jeu refuse un manifeste non signé ou modifié venant du serveur officiel : même un serveur compromis ne
  peut pas diffuser de faux paquet. **Ne jamais perdre ni diffuser cette clé.**
- Vérificateur sur le VPS : `/opt/arcanes/godot/godot` (Godot 4.7.1 Linux officiel, somme SHA-512 vérifiée),
  qui charge le dernier paquet publié (`/srv/arcanes/updates/arcanes_X.pck`). Localement :
  `--verifier-godot <godot.exe> --verifier-project <dossier du projet>` ; sans vérificateur, le serveur
  (développement) fait confiance aux résultats déclarés.
- Limite connue : chaque client connaît la graine de la partie (simulation locale), un client modifié pourrait
  donc voir la main adverse. Seul un serveur qui simule la partie et n'envoie à chacun que ce qu'il voit
  l'empêcherait (le vérificateur en est la première brique).

## Langues
Français (texte source), anglais, allemand, espagnol, italien, portugais : **Paramètres > Langue**
(par défaut, la langue du système). Le texte français sert de clé ; traductions dans `data/i18n/<langue>.json`,
chargées par `scripts/core/loc.gd` (`Loc.t("...")` avant toute mise en forme ; les Label/Button se traduisent
seuls). Le serveur traduit aussi ses messages (langue envoyée dans `hello`, fichiers copiés en `/opt/arcanes/i18n/`).
Après ajout de textes : `python tools/i18n_extract.py --missing` liste ce qui manque (`data/i18n/_missing.json`),
`python tools/i18n_check.py <langue>` vérifie marqueurs `%s`/`{nom}` et balises BBCode.

## Notes de mise à jour
`data/patchnotes.json` (la plus récente en premier) : affichées dans l'encart « Nouveautés » du menu
principal, dans « Toutes les notes de mise à jour », et ouvertes automatiquement au premier lancement
d'une nouvelle version. **Ajouter l'entrée de la version avant de publier** (le script le vérifie).

## Personnalisation
Catalogue : `data/cosmetics.json`, **lu aussi par le serveur** (copié en `/opt/arcanes/cosmetics.json` sur le VPS :
à redéployer avec le serveur si on le modifie). Le serveur compte les statistiques de chaque compte
(calculées par le serveur en rejouant chaque partie : serviteurs / sorts / enchantements joués, mots-clés, dégâts au héros...),
calcule les déblocages et valide chaque choix. Le n°1 du classement reçoit automatiquement le contour Champion.
Visuels : `assets/cosmetics/` (dos `back_*.png`, plateaux `board_*.png`) et `assets/avatars/avatar_9..14.png`.

## Icône
`assets/ui/game_icon.png` / `.ico` (générée avec ComfyUI, `tools/raw/icon_2.png`). Posée dans l'exe à
chaque publication par `tools/bin/rcedit-x64.exe` (electron/rcedit, MIT), avec les informations de version.

## Mises à jour (tout le monde sur la dernière version)

Au lancement, l'écran de démarrage (`scenes/boot.tscn`) interroge le serveur
(`http://<serveur>:7779/version.json`) :
- **à jour**, ou serveur injoignable : on arrive au menu principal ;
- **version obsolète** : écran « Nouvelle version disponible » avec les nouveautés,
  bouton **Mettre à jour** (téléchargement du paquet `.pck`, vérification SHA-256, redémarrage
  automatique du jeu dessus) ou **Jouer hors ligne** (IA uniquement).

Le serveur **refuse la connexion** des clients plus anciens que la version publiée, et en connexion
directe l'hôte refuse un joueur dont la version diffère : impossible de jouer en ligne sans être à jour.
Le paquet téléchargé est rangé dans `user://updates/` ; aux lancements suivants, le jeu redémarre
directement dessus (`--main-pack`).

### Publier une nouvelle version
Double-cliquer `tools/publier_mise_a_jour.bat` (ou `python tools/publish_update.py 1.1.0 "Nouveautés..."`) :
1. met à jour `application/config/version` ;
2. exporte le jeu Windows (`build/ArcanesEtLames/`) — modèles d'export Windows 4.7.1 déjà installés ;
3. crée dans `dist/` le paquet de mise à jour `.pck`, le zip complet pour les nouveaux joueurs et `latest.json` ;
4. envoie le tout sur le VPS (bascule atomique, anciennes versions supprimées).

Le serveur n'a pas besoin d'être redémarré. Option `--local` : tout préparer sans rien envoyer.
Depuis l'éditeur Godot, une mise à jour se télécharge mais ne peut pas relancer le jeu.

## Assets générés avec ComfyUI

Tous les graphismes, musiques et effets sonores ont été générés via ComfyUI (connecté en MCP) :

| Type | Workflow (`tools/comfy_workflows/`) | Modèles |
|---|---|---|
| Illustrations, décors, textures d'interface | `pixel_art_image.json` | SDXL base 1.0 + LoRA pixel-art-xl |
| Icônes / sprites détourés | `pixel_art_sprite_nobg.json` | idem + BiRefNet |
| Musiques chiptune | `chiptune_music.json` | ACE-Step 1.5 turbo |
| Effets sonores 8-bit | `retro_sfx.json` | Stable Audio Open 1.0 + T5 base |

- Prompts, tailles et graines : `tools/assets_manifest.json`.
- `tools/postprocess_assets.py` : réduction en vrai pixel art (palette limitée) et composition des
  éléments d'interface (cadres de cartes, panneaux, boutons) depuis les textures générées.
- Polices : Pixelify Sans (textes) et Press Start 2P (chiffres), licence OFL (`assets/fonts/OFL.txt`).

## Effets 3D
`scripts/fx/fx_3d.gd` : un `SubViewport` 3D transparent superposé au jeu 2D, avec une caméra en
perspective calée sur l'écran. Boule de feu, éclair, soin, bénédiction, tempête de givre, flèche,
invocation, souffle du dragon, bouclier divin, cartes volantes, braises du menu, feu d'artifice.

## Tests
- `tests/sim_test.tscn` : 200 parties IA contre IA + vérification du déterminisme
  (`godot --headless --path . res://tests/sim_test.tscn`).
- Test réseau automatique (serveur lancé sur 7778), deux instances headless :
  ```
  godot --headless --path . -- --profile=a --name=Invite --autoplay --auto-accept --quit-after-game
  godot --headless --path . -- --profile=b --name=Hote --autoplay --auto-host=Invite --quit-after-game
  ```
- `--profile=X` permet aussi de lancer deux instances sur le même PC pour tester à la main.

## Structure
```
scenes/            boot (mises à jour), main_menu, battle, collection, multiplayer
scripts/autoload/  settings, updater, audio, card_db (cartes + deck), ui_theme, lobby (serveur), net, pause_menu
scripts/core/      game_state (règles), ai (adversaire)
scripts/ui/        card_view, minion_view, hero_view, rules/friends/leaderboard panels
scripts/fx/        fx_3d (effets 3D)
server/            serveur communautaire Python (déployé sur le VPS)
tools/             workflows ComfyUI, post-traitement, police, publication des versions
build/, dist/      générés par la publication (jeu exporté, paquets envoyés au VPS)
```
