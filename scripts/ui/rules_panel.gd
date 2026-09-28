class_name RulesPanel
extends Control
## Fenêtre modale expliquant les règles du jeu.

const RULES := """[center][b][color=#f2c14e]BUT DU JEU[/color][/b][/center]
Réduisez les points de vie (PV) du héros adverse de [b]25[/b] à [b]0[/b].
Il n'y a [b]pas de maximum de PV[/b] : les soins peuvent faire dépasser les PV de départ (chiffre en [color=#7dff8a]vert[/color]).

[center][b][color=#f2c14e]QUI COMMENCE ?[/color][/b][/center]
Une pièce frappée de l'avatar de chaque joueur est lancée au début de la partie : la face qui tombe désigne le joueur qui commence.

[center][b][color=#f2c14e]L'ÉNERGIE[/color][/b][/center]
L'énergie ([color=#5ab4f0]gemme bleue[/color]) sert de points d'action. Au premier tour vous avez [b]1[/b] énergie maximum, puis [b]+1 à chaque tour[/b] jusqu'à [b]10[/b]. Elle est entièrement rechargée au début de votre tour.
Chaque carte coûte le nombre d'énergie indiqué en haut à gauche. L'énergie non utilisée est perdue en fin de tour.

[center][b][color=#f2c14e]DÉROULEMENT D'UN TOUR[/color][/b][/center]
1. [b]Pioche au choix[/b] : vous révélez les 3 cartes du dessus de votre deck, en gardez [b]une[/b] (clic ou touches 1 à 3) ; les 2 autres retournent au fond du deck. Tant que vous n'avez pas choisi, vous ne pouvez pas jouer. (S'il ne reste qu'une carte, vous la piochez directement.) Bouton [b]Voir le plateau[/b] (ou touche [b]Tab[/b] / [b]V[/b], qui bascule entre le choix et le plateau) pour regarder votre main et le plateau avant de choisir.
2. Vous jouez des cartes tant que vous avez de l'énergie. Vous pouvez aussi [b]défausser[/b] gratuitement une carte : survolez-la puis cliquez le petit [b]X[/b] rouge (deux clics pour confirmer).
3. Vos serviteurs attaquent (une fois chacun).
4. Vous terminez votre tour (bouton [b]Fin du tour[/b] ou touche [b]Espace[/b]).

[center][b][color=#f2c14e]LES DECKS[/color][/b][/center]
Vous et votre adversaire jouez [b]exactement le même deck de 100 cartes[/b] (59 cartes différentes, de 1 à 4 exemplaires chacune), mélangé différemment. Main de départ : 3 cartes (4 pour le joueur qui commence en second). Main maximum : 9 cartes (les cartes piochées en trop sont détruites). Plateau maximum : 6 serviteurs.
Si votre deck est vide, chaque pioche inflige des dégâts de [b]fatigue[/b] croissants (1, 2, 3...).

[center][b][color=#f2c14e]SERVITEURS[/color][/b][/center]
Un serviteur possède une [b]attaque[/b] (épée) et des [b]PV[/b] (cœur). Il ne peut pas attaquer le tour où il est joué (« Zzz »), sauf s'il a [b]Charge[/b].
Lors d'un combat entre deux serviteurs, chacun inflige ses dégâts à l'autre. Un héros attaqué ne riposte pas. Un serviteur à 0 PV meurt.
Certains serviteurs ont un [b]Effet continu[/b] : tant qu'ils sont en jeu, ils donnent un bonus à vos autres serviteurs ou agissent au début / à la fin de votre tour.

[center][b][color=#f2c14e]SORTS[/color][/b][/center]
Un sort produit un effet immédiat puis disparaît. Certains sorts demandent de choisir une cible.

[center][b][color=#c9a0ff]ENCHANTEMENTS[/color][/b][/center]
Un enchantement ([color=#c9a0ff]cadre violet[/color]) reste en jeu dans la zone située entre les héros ([b]2 au maximum[/b] par joueur). Il agit tant qu'il n'est pas détruit :
• effet [b]permanent[/b] (ex. « Vos serviteurs ont +1 attaque ») : le bonus disparaît si l'enchantement est détruit ;
• effet au [b]début[/b] ou à la [b]fin de votre tour[/b] (ex. « rend 2 PV à votre héros »).
Il n'a [b]pas de PV[/b] et ne peut pas être attaqué : seules les cartes de destruction le retirent (Dissipation, Purification, Briseur de sorts).

[center][b][color=#c9a0ff]CIMETIÈRE ET DECK[/color][/b][/center]
Les cartes mortes, jouées, détruites, défaussées ou retirées du deck vont au [b]cimetière[/b] de leur propriétaire. Certaines cartes s'en servent : Goule affamée, Fossoyeur, Résurrection, Pacte des tombes.
D'autres modifient les decks : [b]Tri des archives[/b] retire des cartes de coût 1 du vôtre (pour piocher plus fort ensuite), [b]Sabotage[/b] retire des cartes chères du deck adverse.

[center][b][color=#f2c14e]CONTRE L'IA[/color][/b][/center]
Quatre niveaux : [b]Apprenti[/b], [b]Chevalier[/b], [b]Seigneur de guerre[/b] (anticipe vos réponses) et [b]Challenger[/b] : il joue comme le Seigneur de guerre et commence avec [b]5 PV[/b] et [b]1 carte[/b] de plus. Plus le niveau est élevé, plus les récompenses sont importantes.
Chaque niveau battu est marqué d'une [b]coche verte[/b] dans le menu et débloque un titre, un contour d'avatar, un dos de cartes et un plateau.
[b]Inferno[/b] : l'IA la plus forte, avec des [b]PV infinis[/b]. Infligez-lui un maximum de dégâts avant de tomber : votre meilleur score entre dans l'onglet [b]Inferno[/b] du classement.
En partie, la case [b]Fin du tour automatique[/b] (sous la durée) termine votre tour dès que vous n'avez plus rien à jouer.

[center][b][color=#f2c14e]MULTIJOUEUR[/color][/b][/center]
Menu principal > [b]Multijoueur[/b] : [b]créez une partie[/b] (elle apparaît dans la liste pour tous les joueurs connectés) ou [b]rejoignez[/b] une partie ouverte de la liste. Vous pouvez aussi inviter un ami connecté. Tout passe par le serveur officiel : aucun port ni adresse IP à configurer.
Quitter une partie en cours compte comme un abandon.

[center][b][color=#f2c14e]PIÈCES D'OR, BOUTIQUE ET PASSE DE COMBAT[/color][/b][/center]
Chaque partie rapporte des [b]pièces d'or (PO)[/b] : davantage en cas de victoire, un peu en cas de défaite (d'autant plus que vous avez résisté longtemps), presque rien en cas d'abandon. Première victoire du jour : [b]+20 PO[/b]. Les parties de moins de 45 secondes ne rapportent rien.
La [b]Boutique[/b] vend des dos de cartes, plateaux et contours d'avatar ; ils s'équipent ensuite dans Personnalisation (depuis votre profil).
Une [b]saison[/b] dure un mois. Chaque partie fait progresser le [b]passe de combat[/b] (30 niveaux) : PO, dos de cartes, contours, plateau et titre sont obtenus automatiquement et restent à vous pour toujours. Tous les joueurs de la saison 1 recevront le titre [b]Pionnier[/b] à sa fin.

[center][b][color=#f2c14e]FAIR-PLAY[/color][/b][/center]
Le serveur tire la donne de chaque partie puis la rejoue entièrement pour la valider : victoires, PO, XP et statistiques ne sont accordés qu'aux parties vérifiées. Au-delà de 10 parties par jour contre le même adversaire, les parties ne sont plus comptées.

[center][b][color=#f2c14e]MOTS-CLÉS[/color][/b][/center]
%s
[center][b][color=#f2c14e]CONTRÔLES[/color][/b][/center]
• [b]Jouer une carte[/b] : un 1er clic la sélectionne (contour doré), un 2e clic la joue (si elle demande une cible, cliquez ensuite sur la cible). Clic droit ou Échap : désélectionner.
• [b]Ranger sa main[/b] (en bas à droite) : Manuel (glissez une carte pour la déplacer, sans la jouer), Coût, PV ou Attaque.
• [b]Durée[/b] de la partie : chrono sous le bouton Fin du tour.
• [b]Revanche[/b] en ligne : chacun des deux joueurs peut la proposer, l'autre l'accepte ou la refuse.
• [b]Clic sur un de vos serviteurs[/b] (bordure verte) puis sur un ennemi : attaquer.
• [b]Clic droit[/b] ou [b]Échap[/b] : annuler un ciblage.
• Survolez un serviteur pour voir sa carte complète.
• Sous chaque héros : [b]Deck[/b] (composition de votre bibliothèque restante, sans l'ordre de pioche) et [b]Cimetière[/b] (cartes mortes, jouées, détruites ou défaussées, des deux joueurs).
• [b]Échap[/b] : ferme la fenêtre ouverte, sinon ouvre les paramètres (volume, raccourcis, langue...), aussi accessibles par l'[b]engrenage[/b] en bas à gauche du menu principal. [b]Maj[/b] (maintenue) : accélérer les animations.
"""


static func rules_bbcode() -> String:
	var kw := ""
	for k in CardDB.KEYWORDS:
		kw += "• [b]%s[/b] : %s\n" % [Loc.t(CardDB.KEYWORDS[k][0]), Loc.t(CardDB.KEYWORDS[k][1])]
	return Loc.t(RULES) % kw


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("modal")   # Échap la ferme (voir PauseMenu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 640)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(UITheme.title_label(Loc.t("Règles du jeu"), 38))
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.custom_minimum_size = Vector2(780, 500)
	text.text = rules_bbcode()
	vb.add_child(text)
	var close := UITheme.button(Loc.t("Fermer"), 200)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(queue_free)
	vb.add_child(close)
