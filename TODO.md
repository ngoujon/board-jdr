# TODO — Arcanes & Lames

## Déjà fait (26/09/2026)
- [x] Serveur officiel installé, service `arcanes-lobby`, isolé des autres projets.
- [x] Pare-feu : ports TCP 7778 (jeu) et 7779 (mises à jour + page de téléchargement) ouverts.
- [x] Toutes les parties passent par le serveur : aucun port à ouvrir chez les joueurs.
- [x] Le jeu se connecte au serveur officiel par défaut.
- [x] Modèles d'export Windows installés, version **1.0.0 publiée**.
- [x] Comptes, classement et historique de TOUTES les parties conservés sur le VPS, sans limite (SQLite).
- [x] Sauvegardes quotidiennes sur le VPS (`/var/backups/arcanes`), toutes conservées.
- [x] HTTPS (Let's Encrypt, renouvellement automatique).
- [x] Exe signé (certificat « Arcanes & Lames ») + installateur en une ligne, sans avertissement SmartScreen.
- [x] Lobby multijoueur : créer une partie / rejoindre depuis la liste (plus de port ni d'IP).
- [x] Notes de mise à jour dans le menu principal (`data/patchnotes.json`).
- [x] Icône du jeu dans l'exe, les raccourcis et la fenêtre.
- [x] Version **1.2.0** publiée.
- [x] Version **1.3.0** publiée : deck de 100 cartes (20 nouvelles cartes), « Voir le plateau » pendant la pioche,
      proposition de mise à jour en fin de partie, nouveau bouclier divin, cristal d'énergie déplacé.
- [x] Version **1.4.0** : enchantements (+ Sape et cartes de destruction), défausse, personnalisation
      (titres, avatars, contours, dos de cartes, plateaux), contour Champion pour le n°1.
- [x] Version **1.4.1** : consultation de la bibliothèque (Deck) et du cimetière ; mise à jour automatique réparée
      (le nouveau .pck remplace l'ancien à côté de l'exe, puis le jeu se relance).
- [x] Version **1.5.0** : messagerie entre amis (historique sur le serveur), pile ou face aux avatars,
      IA difficile, 10 nouvelles cartes (cimetière, effets continus, decks), enchantements sans PV (2 max),
      Sape supprimée, PV sans maximum, Échap ferme les fenêtres, Tab pendant la pioche.
- [x] Version **1.6.0** : menu Statistiques (toutes les parties), recherche et profils dans le classement,
      replays des parties (graine + actions enregistrées sur le serveur, table `match_cards` pour les cartes).
- [x] Version **1.7.0** : rangement de la main (manuel / coût / PV / attaque), jeu en deux clics, revanche
      proposée par l'un ou l'autre joueur, chrono, Bibliothèque ancienne à 6, correctifs du salon et du menu.

- [x] Version **1.8.0** : saison 1 et passe de combat, pièces d'or et boutique, cadres de cartes, titres de séries
      de défaites, IA Challenger, 6 langues, icônes du menu ; sécurité : parties rejouées et vérifiées par le serveur,
      connexion TLS (port 7780), mises à jour signées, limites anti-abus.

## À faire de ton côté
- [ ] **Sauvegarder aussi** `%USERPROFILE%\.arcanes-codesign\update_signing_key.pem` (clé de signature des mises à jour) :
      sans elle, impossible de publier une mise à jour acceptée par le jeu.
- [ ] Avant le 26/10 : prévoir les récompenses de la **saison 2** dans `data/cosmetics.json` (`seasons.rewards["2"]`,
      sinon seules des PO sont proposées) et redéployer `cosmetics.json` sur le serveur.
- [ ] **Sauvegarder** `%USERPROFILE%\.arcanes-codesign\` (clé de signature + mot de passe) sur une clé USB
      ou un cloud perso : sans elle, impossible de signer les prochaines versions avec la même identité.
- [ ] Envoyer aux joueurs la page de téléchargement (commande d'installation à copier).
- [ ] Les joueurs en 1.2, 1.3 ou 1.4.0 qui ont cliqué « Mettre à jour » voient leur jeu se fermer :
      ils doivent **réinstaller une fois** depuis la page de téléchargement (la 1.4.1 corrige le problème).

## À chaque nouvelle version
1. Modifier le jeu dans l'éditeur.
1b. Ajouter la nouvelle version en tête de `data/patchnotes.json` (nouveautés, améliorations, corrections).
2. Double-cliquer `tools/publier_mise_a_jour.bat`, puis saisir un numéro **supérieur** (ex. `1.0.1`) et les nouveautés.
3. C'est tout : au lancement suivant, les joueurs sont invités à se mettre à jour
   (ceux qui sont en pleine partie le sont à la fin de leur partie).
   Le zip de la page de téléchargement est lui aussi mis à jour.
4. Si `data/cosmetics.json` ou `server/lobby_server.py` ont changé : redéployer aussi le serveur.

## Améliorations possibles (facultatif)
- [ ] Nom de domaine personnalisé pour le serveur officiel.
- [ ] (Optionnel) Certificat reconnu par Windows (payant) pour que le zip manuel n'affiche plus d'avertissement.
- [ ] Nouveaux decks et héros.
- [ ] Messages hors ligne (aujourd'hui, seuls les amis connectés reçoivent les messages).
