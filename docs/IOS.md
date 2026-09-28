# Arcanes & Lames sur iPhone et iPad

Apple n'autorise la compilation d'une application iOS que sur un Mac avec Xcode.
Le projet Xcode est préparé depuis Windows ; la compilation et l'installation se font sur le Mac.

## Ce qu'il faut

- un Mac récent avec **Xcode** (gratuit, App Store) ;
- un **compte Apple** (l'identifiant Apple habituel suffit pour tester) ;
- l'iPhone ou l'iPad relié au Mac par câble, avec le **mode développeur** activé
  (Réglages > Confidentialité et sécurité > Mode développeur, après le premier essai d'installation).

| Compte | Ce qui est possible |
|---|---|
| Gratuit | Installer le jeu sur **vos propres appareils** uniquement ; l'application expire au bout de **7 jours** (il suffit de la réinstaller depuis Xcode). |
| Apple Developer (99 $/an) | Distribution par **TestFlight** (lien d'invitation, jusqu'à 10 000 testeurs), puis App Store si souhaité. |

## 1. Identifiant d'équipe

Dans Xcode : **Xcode > Settings > Accounts**, ajoutez votre identifiant Apple.
L'équipe « (Personal Team) » apparaît ; son identifiant fait 10 caractères
(visible aussi dans le trousseau : certificat « Apple Development », champ « Unité d'organisation »).

## 2. Export du projet Xcode (sur le PC Windows)

```
python tools/export_ios.py <TEAM_ID>
```

Produit `dist/ArcanesEtLames_<version>_ios_xcode.zip` (environ 100 Mo). L'identifiant n'est pas enregistré dans le dépôt.

## 3. Compilation et installation (sur le Mac)

1. Copiez le zip sur le Mac et décompressez-le.
2. Ouvrez `ArcanesEtLames_iOS/ArcanesEtLames.xcodeproj` dans Xcode.
3. Cible **ArcanesEtLames** > onglet **Signing & Capabilities** : cochez *Automatically manage signing*
   et choisissez votre équipe. Avec un compte gratuit, si Xcode refuse l'identifiant
   `net.ovh.arcanes-et-lames`, ajoutez-lui un suffixe (ex. `net.ovh.arcanes-et-lames.nicolas`).
4. Choisissez l'appareil branché en haut de la fenêtre, puis **Product > Run** (⌘R).
5. Première fois : sur l'appareil, **Réglages > Général > VPN et gestion de l'appareil**,
   faites confiance à votre profil de développeur, puis relancez.

## Mises à jour

Sur iOS, le jeu ne peut pas remplacer son propre contenu. Quand une nouvelle version sort,
le jeu l'annonce et renvoie vers le site ; il faut alors refaire les étapes 2 et 3 avec la nouvelle version.
Avec TestFlight (compte payant), les testeurs reçoivent les nouvelles versions automatiquement.

## Distribution par TestFlight (compte payant)

Dans Xcode : **Product > Archive**, puis **Distribute App > TestFlight & App Store**.
Dans App Store Connect, créez l'application (même identifiant), ajoutez des testeurs externes
et partagez le lien public TestFlight : il peut être ajouté à la page de téléchargement du site.
