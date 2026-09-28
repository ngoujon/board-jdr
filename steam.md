# Publier Arcanes & Lames sur Steam — notes

> Notes informatives rédigées le 26/09/2026. Les montants, délais et règles peuvent évoluer :
> à vérifier sur https://partner.steamgames.com avant de se lancer.

**En résumé :** techniquement et administrativement, c'est assez accessible. La vraie difficulté est
de se faire remarquer une fois le jeu sorti.

## Les étapes (Steam Direct)

1. **Compte Steamworks** : vérification d'identité, coordonnées bancaires et questionnaire fiscal
   (formulaire W-8BEN pour un résident français, pour éviter la retenue d'impôt américaine).
   Quelques jours de validation.
2. **Frais** : 100 $ par jeu, remboursés dès que le jeu a rapporté 1 000 $.
3. **Délai d'environ 30 jours** entre le paiement des frais et la sortie.
4. **Page du magasin** : visuels (dont les vignettes de présentation), au moins 5 captures d'écran,
   description, bande-annonce (fortement conseillée).
   - Valve vérifie la page en quelques jours.
   - Elle doit ensuite rester **« Bientôt disponible » au moins 2 semaines** avant la sortie.
5. **Vérification du jeu** : envoi du jeu avec SteamCMD, test rapide par Valve (démarrage,
   conformité à la page), puis choix de la date de sortie.
6. **Commission** : Steam prend **30 %** des ventes (moins au-delà de très gros chiffres
   d'affaires). Le jeu peut aussi être gratuit.

**Durée réaliste** : 1 à 2 mois entre l'inscription et la sortie. La plupart des développeurs laissent
la page « Bientôt disponible » plusieurs mois pour accumuler des listes de souhaits.

## Ce que ça changerait pour Arcanes & Lames

| Sujet | Impact |
|---|---|
| **Contenu généré par IA** | Déclaration **obligatoire** dans le questionnaire de contenu de Steam. Les graphismes, musiques et sons générés avec ComfyUI sont concernés. C'est accepté, mais il faut le déclarer et s'assurer d'avoir les droits sur ce que les modèles ont produit. La page du magasin l'affichera. |
| **Inspiration Hearthstone** | Pas de problème : les règles d'un jeu ne sont pas protégées. Il ne faut rien reprendre de Blizzard (noms, visuels, logos), et c'est déjà le cas. |
| **Mises à jour** | Steam les gère lui-même. Il faut désactiver notre système de mise à jour automatique (`Updater`) dans la version Steam. Le serveur peut continuer à imposer la dernière version pour le jeu en ligne. |
| **Signature / SmartScreen** | Deviennent inutiles : un jeu lancé depuis Steam ne déclenche pas l'avertissement de Windows. |
| **Serveur (VPS)** | Peut rester tel quel. En option, on peut utiliser les comptes Steam à la place des pseudos (connexion automatique, liste d'amis Steam) grâce au module **GodotSteam**, qui s'intègre à Godot. |
| **Licences** | Godot (licence MIT) et les polices Pixelify Sans et Press Start 2P (licence OFL) sont compatibles avec une vente, avec une mention dans les crédits. |
| **Steam Deck** | Le jeu tournerait probablement tel quel via Proton (couche de compatibilité Windows de Valve). Une version Linux native est aussi possible avec Godot. |

## Le vrai défi : la visibilité

- Des dizaines de jeux sortent chaque jour sur Steam : sans communication (page soignée, bande-annonce,
  réseaux sociaux, festivals Steam Next Fest), un jeu passe facilement inaperçu.
- **Risque propre au multijoueur** : si peu de monde joue en même temps, la liste des parties
  ouvertes est vide. La partie contre l'IA et l'invitation d'amis comptent beaucoup pour que le jeu
  reste intéressant avec peu de joueurs.

## Travail technique à prévoir si on se lance

- [ ] Version « Steam » du jeu : mise à jour automatique désactivée, pas d'écran de mise à jour au lancement.
- [ ] Intégration de GodotSteam (connexion avec le compte Steam, amis, invitations Steam, succès éventuels).
- [ ] Configuration de l'envoi sur Steam (SteamCMD + fichiers de configuration du build).
- [ ] Visuels du magasin (vignettes aux différents formats, captures, bande-annonce).
- [ ] Déclaration du contenu généré par IA et questionnaire de classification par âge.
