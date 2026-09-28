extends Node
## Base de données des cartes. Le deck (DECK_LIST) est identique pour le joueur et l'IA.
##
## Effets (dictionnaires) :
##   kind   : "damage" | "heal" | "buff" | "draw" | "summon" | "shield"
##   target : "chosen"            -> la cible choisie par le joueur (voir "target_rule")
##            "random_enemy"      -> un ennemi aléatoire (héros ou serviteur)
##            "enemy_hero" / "own_hero"
##            "all_enemy_minions" / "all_other_minions" / "all_minions"
##            "all_enemies"       -> héros adverse + ses serviteurs
##            "own_minions"       -> vos serviteurs (hors la source)
##   count  : (summon) nombre d'exemplaires invoqués
##   fx     : effet visuel 3D à jouer (voir scripts/fx/fx_3d.gd)

const HERO_HEALTH := 25
const MAX_ENERGY := 10
const MAX_BOARD := 6
const MAX_ENCHANTS := 2
const MAX_HAND := 9
const START_HAND := 3

const KEYWORDS := {
	"taunt": ["Provocation", "Les ennemis doivent attaquer ce serviteur avant de pouvoir cibler vos autres serviteurs ou votre héros."],
	"charge": ["Charge", "Ce serviteur peut attaquer dès le tour où il est joué (pas de « mal d'invocation »)."],
	"divine_shield": ["Bouclier divin", "La première fois que ce serviteur devrait subir des dégâts, le bouclier se brise à la place et il ne perd aucun PV."],
	"battlecry": ["Cri de guerre", "Effet déclenché une seule fois, au moment où vous jouez la carte depuis votre main."],
	"deathrattle": ["Râle d'agonie", "Effet déclenché lorsque ce serviteur meurt."],
	"ongoing": ["Effet continu", "Tant que ce serviteur est en jeu, son effet s'applique (bonus à vos autres serviteurs, ou effet au début / à la fin de votre tour). Il s'arrête quand le serviteur meurt."],
}

const CARDS := {
	"ecuyer": {
		"name": "Écuyer", "type": "minion", "cost": 1, "attack": 1, "health": 2,
		"text": "Aucun effet spécial.", "flavor": "Il rêve d'être chevalier. En attendant, il porte les bagages.",
	},
	"archer": {
		"name": "Archère de la garde", "type": "minion", "cost": 1, "attack": 1, "health": 1,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "damage", "amount": 1, "target": "random_enemy", "fx": "arrow"},
		"text": "Cri de guerre : 1 dégât à un ennemi au hasard.",
		"flavor": "Elle ne rate jamais sa cible. Enfin, presque jamais.",
	},
	"loup": {
		"name": "Loup des bois", "type": "minion", "cost": 2, "attack": 2, "health": 1,
		"keywords": ["charge"],
		"text": "Charge : attaque dès le tour où il est joué.", "flavor": "Il a senti votre peur à trois lieues.",
	},
	"gardien": {
		"name": "Gardien du pont", "type": "minion", "cost": 2, "attack": 1, "health": 4,
		"keywords": ["taunt"],
		"text": "Provocation : doit être attaqué en premier.", "flavor": "« Vous ne passerez pas... sans payer le péage. »",
	},
	"chevalier": {
		"name": "Chevalier errant", "type": "minion", "cost": 3, "attack": 3, "health": 2,
		"keywords": ["divine_shield"],
		"text": "Bouclier divin : ignore les 1ers dégâts subis.", "flavor": "Sa foi est son armure. Son armure est aussi son armure.",
	},
	"pretresse": {
		"name": "Prêtresse de l'aube", "type": "minion", "cost": 3, "attack": 2, "health": 3,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "heal", "amount": 4, "target": "own_hero", "fx": "heal"},
		"text": "Cri de guerre : rend 4 PV à votre héros.",
		"flavor": "Chaque matin, elle bénit le soleil. Chaque soir, elle panse les héros.",
	},
	"necromancien": {
		"name": "Nécromancien", "type": "minion", "cost": 3, "attack": 2, "health": 2,
		"keywords": ["deathrattle"],
		"deathrattle": {"kind": "summon", "card": "squelette", "fx": "summon"},
		"text": "Râle d'agonie : invoque un Squelette 2/1.",
		"flavor": "La mort n'est qu'un léger contretemps.",
	},
	"squelette": {
		"name": "Squelette", "type": "minion", "cost": 1, "attack": 2, "health": 1, "token": true,
		"text": "Jeton invoqué par le Nécromancien.",
		"flavor": "Ses os craquent, mais son épée aussi.",
	},
	"ogre": {
		"name": "Ogre des collines", "type": "minion", "cost": 4, "attack": 5, "health": 4,
		"text": "Aucun effet spécial.", "flavor": "Il sait compter jusqu'à cinq. C'est aussi le nombre de dégâts qu'il inflige.",
	},
	"templier": {
		"name": "Templier", "type": "minion", "cost": 4, "attack": 3, "health": 5,
		"keywords": ["taunt"],
		"text": "Provocation : doit être attaqué en premier.", "flavor": "Un mur de foi et d'acier.",
	},
	"griffon": {
		"name": "Chevaucheur de griffon", "type": "minion", "cost": 5, "attack": 4, "health": 4,
		"keywords": ["charge"],
		"text": "Charge : attaque dès le tour où il est joué.", "flavor": "Il fond sur ses ennemis depuis les nuages.",
	},
	"golem": {
		"name": "Golem runique", "type": "minion", "cost": 6, "attack": 5, "health": 7,
		"keywords": ["taunt"],
		"text": "Provocation : doit être attaqué en premier.", "flavor": "Des runes anciennes animent cette montagne de pierre.",
	},
	"dragon": {
		"name": "Dragon ancien", "type": "minion", "cost": 7, "attack": 6, "health": 6,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "damage", "amount": 2, "target": "all_other_minions", "fx": "dragon_fire"},
		"text": "Cri de guerre : 2 dégâts aux autres serviteurs.",
		"flavor": "Le ciel s'embrase quand il déploie ses ailes.",
	},
	"eclair": {
		"name": "Éclair arcanique", "type": "spell", "cost": 1,
		"spell": {"kind": "damage", "amount": 2, "target": "chosen", "target_rule": "any", "fx": "lightning"},
		"text": "Inflige 2 dégâts à un héros ou serviteur.",
		"flavor": "Simple, rapide, électrisant.",
	},
	"potion": {
		"name": "Potion de soin", "type": "spell", "cost": 1,
		"spell": {"kind": "heal", "amount": 5, "target": "chosen", "target_rule": "any", "fx": "heal"},
		"text": "Rend 5 PV à un héros ou serviteur.",
		"flavor": "Goût fraise. Enfin, c'est ce que dit l'étiquette.",
	},
	"benediction": {
		"name": "Bénédiction", "type": "spell", "cost": 2,
		"spell": {"kind": "buff", "attack": 2, "health": 2, "target": "chosen", "target_rule": "friendly_minion", "fx": "buff"},
		"text": "+2 attaque et +2 PV à un de vos serviteurs.",
		"flavor": "La lumière guide votre lame.",
	},
	"grimoire": {
		"name": "Grimoire ancien", "type": "spell", "cost": 3,
		"spell": {"kind": "draw", "amount": 2, "fx": "draw"},
		"text": "Piochez 2 cartes (sans choix).",
		"flavor": "Les pages se tournent toutes seules. C'est normal. Probablement.",
	},
	"boule_feu": {
		"name": "Boule de feu", "type": "spell", "cost": 4,
		"spell": {"kind": "damage", "amount": 5, "target": "chosen", "target_rule": "any", "fx": "fireball"},
		"text": "Inflige 5 dégâts à un héros ou serviteur.",
		"flavor": "Le sort préféré de tous les mages. Et de tous les incendiaires.",
	},
	"blizzard": {
		"name": "Tempête de givre", "type": "spell", "cost": 5,
		"spell": {"kind": "damage", "amount": 2, "target": "all_enemy_minions", "fx": "frost"},
		"text": "2 dégâts à tous les serviteurs adverses.",
		"flavor": "L'hiver arrive. Très vite.",
	},
	# ---------------------------------------------------------------- extension 1.3
	"milicien": {
		"name": "Milicien du village", "type": "minion", "cost": 1, "attack": 2, "health": 1,
		"text": "Aucun effet spécial.", "flavor": "Sa fourche a déjà vaincu trois bottes de foin.",
	},
	"herboriste": {
		"name": "Herboriste", "type": "minion", "cost": 2, "attack": 2, "health": 2,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "heal", "amount": 3, "target": "own_hero", "fx": "heal"},
		"text": "Cri de guerre : rend 3 PV à votre héros.",
		"flavor": "Une tisane pour chaque blessure.",
	},
	"porte_bouclier": {
		"name": "Porte-bouclier", "type": "minion", "cost": 3, "attack": 2, "health": 5,
		"keywords": ["taunt"],
		"text": "Provocation : doit être attaqué en premier.", "flavor": "Derrière lui, personne ne craint rien.",
	},
	"voleur": {
		"name": "Voleur des ombres", "type": "minion", "cost": 3, "attack": 3, "health": 2,
		"keywords": ["charge"],
		"text": "Charge : attaque dès le tour où il est joué.", "flavor": "Vous ne l'avez pas vu venir. Personne ne le voit venir.",
	},
	"alchimiste": {
		"name": "Alchimiste fou", "type": "minion", "cost": 3, "attack": 2, "health": 3,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "damage", "amount": 1, "target": "all_enemy_minions", "fx": "dragon_fire"},
		"text": "Cri de guerre : 1 dégât aux serviteurs adverses.",
		"flavor": "« Et si je mélangeais le rouge ET le vert ? »",
	},
	"barde": {
		"name": "Barde itinérant", "type": "minion", "cost": 3, "attack": 2, "health": 3,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "draw", "amount": 1, "fx": "draw"},
		"text": "Cri de guerre : piochez 1 carte.",
		"flavor": "Il connaît une chanson sur chacun de vos exploits. Même ceux que vous n'avez pas faits.",
	},
	"paladine": {
		"name": "Paladine sacrée", "type": "minion", "cost": 3, "attack": 2, "health": 2,
		"keywords": ["taunt", "divine_shield"],
		"text": "Provocation. Bouclier divin.", "flavor": "Sa foi est un rempart, son épée une promesse.",
	},
	"capitaine": {
		"name": "Capitaine de la garde", "type": "minion", "cost": 4, "attack": 3, "health": 3,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "buff", "attack": 1, "health": 1, "target": "own_minions", "fx": "buff"},
		"text": "Cri de guerre : +1/+1 à vos autres serviteurs.",
		"flavor": "« Tenez la ligne ! »",
	},
	"pyromancienne": {
		"name": "Pyromancienne", "type": "minion", "cost": 4, "attack": 3, "health": 3,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "damage", "amount": 2, "target": "random_enemy", "fx": "fireball"},
		"text": "Cri de guerre : 2 dégâts à un ennemi au hasard.",
		"flavor": "Elle vise rarement. Elle rate encore plus rarement.",
	},
	"troll": {
		"name": "Troll des marais", "type": "minion", "cost": 5, "attack": 5, "health": 6,
		"text": "Aucun effet spécial.", "flavor": "Il sent la vase, le vieux fromage et la victoire.",
	},
	"liche": {
		"name": "Liche", "type": "minion", "cost": 5, "attack": 4, "health": 4,
		"keywords": ["deathrattle"],
		"deathrattle": {"kind": "summon", "card": "squelette", "count": 2, "fx": "summon"},
		"text": "Râle d'agonie : invoque deux Squelettes 2/1.",
		"flavor": "La mort n'est qu'un léger contretemps.",
	},
	"chevalier_noir": {
		"name": "Chevalier noir", "type": "minion", "cost": 6, "attack": 6, "health": 5,
		"keywords": ["charge"],
		"text": "Charge : attaque dès le tour où il est joué.", "flavor": "Son destrier ne connaît pas la peur. Ni les freins.",
	},
	"archimage": {
		"name": "Archimage", "type": "minion", "cost": 6, "attack": 4, "health": 6,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "draw", "amount": 2, "fx": "draw"},
		"text": "Cri de guerre : piochez 2 cartes.",
		"flavor": "Il a lu tous les livres de la bibliothèque. Deux fois.",
	},
	"hydre": {
		"name": "Hydre des abysses", "type": "minion", "cost": 8, "attack": 7, "health": 9,
		"keywords": ["taunt"],
		"text": "Provocation : doit être attaqué en premier.", "flavor": "Coupez une tête, il en repousse deux. Coupez-les toutes, elle se vexe.",
	},
	"tir_precis": {
		"name": "Tir précis", "type": "spell", "cost": 2,
		"spell": {"kind": "damage", "amount": 3, "target": "chosen", "target_rule": "any", "fx": "arrow"},
		"text": "Inflige 3 dégâts à un héros ou serviteur.",
		"flavor": "Entre les deux yeux. Ou presque.",
	},
	"cri_ralliement": {
		"name": "Cri de ralliement", "type": "spell", "cost": 2,
		"spell": {"kind": "buff", "attack": 1, "health": 1, "target": "own_minions", "fx": "buff"},
		"text": "+1/+1 à tous vos serviteurs.",
		"flavor": "Pour le royaume !",
	},
	"pluie_fleches": {
		"name": "Pluie de flèches", "type": "spell", "cost": 3,
		"spell": {"kind": "damage", "amount": 1, "target": "all_enemies", "fx": "arrow"},
		"text": "1 dégât à tous les ennemis, héros compris.",
		"flavor": "Le ciel s'obscurcit. Ce ne sont pas des nuages.",
	},
	"renforts": {
		"name": "Renforts", "type": "spell", "cost": 3,
		"spell": {"kind": "summon", "card": "ecuyer", "count": 2, "fx": "summon"},
		"text": "Invoque deux Écuyers 1/2.",
		"flavor": "Ils sont jeunes, mais ils sont motivés.",
	},
	"lumiere": {
		"name": "Lumière sacrée", "type": "spell", "cost": 3,
		"spell": {"kind": "heal", "amount": 8, "target": "own_hero", "fx": "heal"},
		"text": "Rend 8 PV à votre héros.",
		"flavor": "Une chaleur douce, comme un matin d'été.",
	},
	"meteores": {
		"name": "Pluie de météores", "type": "spell", "cost": 7,
		"spell": {"kind": "damage", "amount": 4, "target": "all_minions", "fx": "dragon_fire"},
		"text": "4 dégâts à tous les serviteurs.",
		"flavor": "Pour faire place nette. Très, très nette.",
	},
	# ---------------------------------------------------------------- extension 1.4 : enchantements
	"etendard": {
		"name": "Étendard royal", "type": "enchantment", "cost": 3,
		"aura": {"attack": 1, "health": 0},
		"text": "Vos serviteurs ont +1 attaque.",
		"flavor": "Sous cette bannière, même l'écuyer se sent chevalier.",
	},
	"autel_vie": {
		"name": "Autel de vie", "type": "enchantment", "cost": 2,
		"turn_start": {"kind": "heal", "amount": 2, "target": "own_hero", "fx": "heal"},
		"text": "Début de votre tour : rend 2 PV à votre héros.",
		"flavor": "Une source claire qui ne tarit jamais.",
	},
	"forge": {
		"name": "Forge runique", "type": "enchantment", "cost": 5,
		"aura": {"attack": 1, "health": 1},
		"text": "Vos serviteurs ont +1/+1.",
		"flavor": "Chaque coup de marteau grave une rune de puissance.",
	},
	"tour_mage": {
		"name": "Tour des mages", "type": "enchantment", "cost": 3,
		"turn_end": {"kind": "damage", "amount": 1, "target": "random_enemy", "fx": "lightning"},
		"text": "Fin de tour : 1 dégât à un ennemi au hasard.",
		"flavor": "Les apprentis s'entraînent. Sur vous.",
	},
	"cimetiere": {
		"name": "Cimetière maudit", "type": "enchantment", "cost": 4,
		"turn_end": {"kind": "summon", "card": "squelette", "fx": "summon"},
		"text": "Fin de votre tour : invoque un Squelette 2/1.",
		"flavor": "Ici, personne ne repose en paix.",
	},
	"bibliotheque": {
		"name": "Bibliothèque ancienne", "type": "enchantment", "cost": 6,
		"turn_start": {"kind": "draw", "amount": 1, "fx": "draw"},
		"text": "Début de votre tour : piochez 1 carte.",
		"flavor": "Silence ! On lit.",
	},
	"dissipation": {
		"name": "Dissipation", "type": "spell", "cost": 1,
		"spell": {"kind": "destroy", "target": "chosen", "target_rule": "enemy_enchant", "fx": "lightning"},
		"text": "Détruit un enchantement adverse.",
		"flavor": "Pouf. Plus de magie.",
	},
	"purification": {
		"name": "Purification", "type": "spell", "cost": 3,
		"spell": {"kind": "destroy", "target": "all_enemy_enchants", "fx": "heal"},
		"text": "Détruit tous les enchantements adverses.",
		"flavor": "La lumière chasse toutes les illusions.",
	},
	"sapeur": {
		"name": "Sapeur nain", "type": "minion", "cost": 2, "attack": 2, "health": 2,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "damage", "amount": 1, "target": "random_enemy", "fx": "fireball"},
		"text": "Cri de guerre : 1 dégât à un ennemi au hasard.",
		"flavor": "Donnez-lui une pioche et il vous creuse sous n'importe quel mur.",
	},
	"catapulte": {
		"name": "Catapulte de siège", "type": "minion", "cost": 4, "attack": 4, "health": 3,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "damage", "amount": 2, "target": "enemy_hero", "fx": "fireball"},
		"text": "Cri de guerre : 2 dégâts au héros adverse.",
		"flavor": "Portée : loin. Précision : approximative.",
	},
	"briseur_sorts": {
		"name": "Briseur de sorts", "type": "minion", "cost": 3, "attack": 3, "health": 2,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "destroy", "target": "random_enemy_enchant", "fx": "lightning"},
		"text": "Cri de guerre : détruit un enchantement adverse.",
		"flavor": "Il déteste la magie. Toute la magie. Surtout la vôtre.",
	},
	# ---------------------------------------------------------------- extension 1.5
	"porte_etendard": {
		"name": "Porte-étendard", "type": "minion", "cost": 3, "attack": 2, "health": 3,
		"keywords": ["ongoing"],
		"aura": {"attack": 1, "health": 0},
		"text": "En jeu : vos autres serviteurs ont +1 attaque.",
		"flavor": "Tant que le drapeau flotte, personne ne recule.",
	},
	"guerisseuse": {
		"name": "Guérisseuse du temple", "type": "minion", "cost": 3, "attack": 1, "health": 4,
		"keywords": ["ongoing"],
		"turn_end": {"kind": "heal", "amount": 2, "target": "own_hero", "fx": "heal"},
		"text": "Fin de votre tour : rend 2 PV à votre héros.",
		"flavor": "Ses prières ne connaissent pas de pause déjeuner.",
	},
	"tourmenteur": {
		"name": "Diablotin tourmenteur", "type": "minion", "cost": 2, "attack": 1, "health": 3,
		"keywords": ["ongoing"],
		"turn_end": {"kind": "damage", "amount": 1, "target": "enemy_hero", "fx": "fireball"},
		"text": "Fin de votre tour : 1 dégât au héros adverse.",
		"flavor": "Petit, pénible, et très, très patient.",
	},
	"gardien_cryptes": {
		"name": "Gardien des cryptes", "type": "minion", "cost": 6, "attack": 4, "health": 5,
		"keywords": ["ongoing"],
		"turn_end": {"kind": "summon", "card": "squelette", "fx": "summon"},
		"text": "Fin de votre tour : invoque un Squelette 2/1.",
		"flavor": "Il garde les morts. Parfois, il les fait sortir.",
	},
	"goule": {
		"name": "Goule affamée", "type": "minion", "cost": 3, "attack": 2, "health": 2,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "grave_buff", "per": 4, "fx": "buff"},
		"text": "Cri de guerre : +1/+1 par 4 cartes au cimetière.",
		"flavor": "Plus le cimetière est rempli, plus elle a d'appétit.",
	},
	"fossoyeur": {
		"name": "Fossoyeur", "type": "minion", "cost": 3, "attack": 2, "health": 3,
		"keywords": ["battlecry"],
		"battlecry": {"kind": "recall_spell", "fx": "draw"},
		"text": "Cri de guerre : reprend votre dernier sort joué.",
		"flavor": "Ce qui est enterré n'est jamais perdu.",
	},
	"resurrection": {
		"name": "Résurrection", "type": "spell", "cost": 5,
		"spell": {"kind": "resurrect", "max_cost": 5, "fx": "heal"},
		"text": "Invoque un serviteur de coût 5 max du cimetière.",
		"flavor": "Debout ! On n'a pas fini.",
	},
	"pacte_tombes": {
		"name": "Pacte des tombes", "type": "spell", "cost": 2,
		"spell": {"kind": "draw", "amount": 1, "bonus_grave": {"min": 8, "amount": 1}, "fx": "draw"},
		"text": "Piochez 1 carte (2 si 8+ cartes au cimetière).",
		"flavor": "Les morts connaissent bien des secrets.",
	},
	"tri_archives": {
		"name": "Tri des archives", "type": "spell", "cost": 1,
		"spell": {"kind": "purge_deck", "side": "own", "max_cost": 1, "count": 3, "fx": "draw"},
		"text": "Votre deck perd 3 cartes de coût 1 (cimetière).",
		"flavor": "Les vieux parchemins, direction la cave.",
	},
	"sabotage": {
		"name": "Sabotage", "type": "spell", "cost": 3,
		"spell": {"kind": "purge_deck", "side": "enemy", "min_cost": 6, "count": 2, "fx": "lightning"},
		"text": "Le deck adverse perd 2 cartes de coût 6 ou plus.",
		"flavor": "Quelqu'un a mis du sable dans les rouages du dragon.",
	},
}

## Deck de 100 cartes, identique pour les deux joueurs (mélangé différemment).
## Les cartes les plus simples / courantes sont en 3-4 exemplaires, les plus puissantes en 2.
const DECK_LIST := {
	# coût 1
	"ecuyer": 3, "archer": 3, "milicien": 4, "eclair": 4, "potion": 1, "dissipation": 2, "tri_archives": 2,
	# coût 2
	"loup": 3, "gardien": 2, "herboriste": 2, "benediction": 2, "tir_precis": 2, "cri_ralliement": 1,
	"sapeur": 2, "autel_vie": 1, "tourmenteur": 2, "pacte_tombes": 2,
	# coût 3
	"chevalier": 2, "pretresse": 2, "necromancien": 2, "porte_bouclier": 2, "voleur": 2, "alchimiste": 1,
	"barde": 2, "paladine": 1, "grimoire": 1, "pluie_fleches": 1, "renforts": 1, "lumiere": 1,
	"briseur_sorts": 2, "etendard": 1, "tour_mage": 1, "purification": 1, "porte_etendard": 2,
	"guerisseuse": 1, "goule": 2, "fossoyeur": 2, "sabotage": 1,
	# coût 4
	"ogre": 3, "templier": 2, "capitaine": 1, "pyromancienne": 2, "boule_feu": 2, "catapulte": 1,
	"cimetiere": 1,
	# coût 5
	"griffon": 2, "troll": 3, "liche": 2, "blizzard": 1, "forge": 1, "resurrection": 1,
	# coût 6 et plus
	"golem": 2, "chevalier_noir": 1, "archimage": 1, "dragon": 1, "meteores": 1, "hydre": 1, "gardien_cryptes": 1,
	"bibliotheque": 1,
}

## Ordre d'affichage dans la collection.
const COLLECTION_ORDER := [
	"ecuyer", "archer", "milicien", "loup", "gardien", "herboriste", "sapeur", "tourmenteur",
	"chevalier", "pretresse", "necromancien", "porte_bouclier", "voleur", "alchimiste", "barde", "paladine",
	"briseur_sorts", "porte_etendard", "guerisseuse", "goule", "fossoyeur",
	"ogre", "templier", "capitaine", "pyromancienne", "catapulte", "griffon", "troll", "liche",
	"golem", "chevalier_noir", "archimage", "gardien_cryptes", "dragon", "hydre", "squelette",
	"eclair", "potion", "dissipation", "tri_archives", "benediction", "tir_precis", "cri_ralliement", "pacte_tombes",
	"grimoire", "pluie_fleches", "renforts", "lumiere", "purification", "sabotage", "boule_feu", "blizzard",
	"resurrection", "meteores",
	"autel_vie", "etendard", "tour_mage", "cimetiere", "forge", "bibliotheque",
]

const HEROES := [
	{"name": "Sire Aldric", "title": "Roi-Paladin", "portrait": "hero_joueur"},
	{"name": "Morgrath", "title": "Seigneur des Ombres", "portrait": "hero_ia"},
]

var _tex_cache := {}
var _placeholder: Texture2D


var _localized := {}   # cartes avec nom, texte et citation traduits dans la langue du jeu


func _ready() -> void:
	localize()


## Reconstruit les cartes traduites (au lancement et quand la langue change).
func localize() -> void:
	_localized.clear()
	for id in CARDS:
		var c: Dictionary = CARDS[id].duplicate()
		for k in ["name", "text", "flavor"]:
			if c.has(k):
				c[k] = Loc.t(str(c[k]))
		_localized[id] = c


func get_card(id: String) -> Dictionary:
	return _localized.get(id, CARDS.get(id, {}))


func build_deck() -> Array[String]:
	var deck: Array[String] = []
	for id in DECK_LIST:
		for i in DECK_LIST[id]:
			deck.append(id)
	return deck


func deck_size() -> int:
	var n := 0
	for id in DECK_LIST:
		n += DECK_LIST[id]
	return n


const TARGET_TEXT := {
	"random_enemy": "un ennemi au hasard (le héros adverse ou l'un de ses serviteurs)",
	"enemy_hero": "le héros adverse",
	"own_hero": "votre héros",
	"all_enemy_minions": "tous les serviteurs adverses",
	"all_other_minions": "tous les autres serviteurs du plateau, les vôtres compris",
	"all_enemies": "tous les ennemis (le héros adverse et tous ses serviteurs)",
	"all_enemy_enchants": "tous les enchantements adverses",
	"random_enemy_enchant": "un enchantement adverse au hasard (s'il y en a un)",
	"own_minions": "vos autres serviteurs sur le plateau",
	"all_minions": "tous les serviteurs du plateau, les vôtres compris",
}


## Phrase décrivant un effet (cri de guerre, râle d'agonie ou sort).
func effect_text(eff: Dictionary) -> String:
	var target: String = TARGET_TEXT.get(eff.get("target", ""), "")
	if target != "":
		target = Loc.t(target)
	if eff.get("target", "") == "chosen":
		if eff.get("target_rule", "any") == "friendly_minion":
			target = Loc.t("un de vos serviteurs, au choix")
		elif eff.get("target_rule", "any") == "enemy_enchant":
			target = Loc.t("un enchantement adverse, au choix")
		else:
			target = Loc.t("la cible de votre choix : n'importe quel héros ou serviteur, allié ou ennemi")
	match eff.get("kind", ""):
		"damage":
			# Singulier / pluriel en deux textes distincts (chaque langue accorde à sa façon).
			var n: int = eff.amount
			return (Loc.t("inflige %d dégâts à %s.") if n > 1 else Loc.t("inflige %d dégât à %s.")) % [n, target]
		"heal":
			return Loc.t("rend %d PV à %s (peut dépasser les PV de départ : il n'y a pas de maximum).") % [eff.amount, target]
		"buff":
			return Loc.t("donne +%d attaque et +%d PV (maximum augmenté) à %s, de façon permanente.") % [eff.attack, eff.health, target]
		"draw":
			var n: int = eff.amount
			var txt: String = (Loc.t("vous piochez %d cartes du dessus de votre deck (sans choix)") if n > 1
				else Loc.t("vous piochez %d carte du dessus de votre deck (sans choix)")) % n
			var bonus: Dictionary = eff.get("bonus_grave", {})
			if not bonus.is_empty():
				txt += Loc.t(", +%d si votre cimetière contient au moins %d cartes") % [int(bonus.amount), int(bonus.min)]
			return txt + "."
		"grave_buff":
			if int(eff.get("max", 0)) > 0:
				return Loc.t("ce serviteur gagne +1/+1 par tranche de %d cartes dans votre cimetière (au plus +%d/+%d).") % [int(eff.per), int(eff.max), int(eff.max)]
			return Loc.t("ce serviteur gagne +1/+1 par tranche de %d cartes dans votre cimetière, sans limite.") % int(eff.per)
		"resurrect":
			return Loc.t("invoque au hasard un serviteur de votre cimetière coûtant %d ou moins (il quitte le cimetière).") % int(eff.max_cost)
		"recall_spell":
			return Loc.t("remet dans votre main le dernier sort de votre cimetière (s'il y en a un).")
		"purge_deck":
			var cond := (Loc.t("%d ou moins") % int(eff.max_cost)) if eff.has("max_cost") else (Loc.t("%d ou plus") % int(eff.get("min_cost", 0)))
			var whose := Loc.t("de votre deck") if eff.get("side", "own") == "own" else Loc.t("du deck adverse")
			return Loc.t("retire au hasard jusqu'à %d cartes de coût %s %s ; elles vont dans le cimetière de leur propriétaire.") % [int(eff.count), cond, whose]
		"destroy":
			return Loc.t("détruit %s.") % target
		"summon":
			var t := get_card(eff.card)
			var n: int = eff.get("count", 1)
			if n > 1:
				return Loc.t("invoque %d %s %d/%d sur votre plateau (s'il reste de la place).") % [n, t.name, t.attack, t.health]
			return Loc.t("invoque un %s %d/%d sur votre plateau (s'il reste de la place).") % [t.name, t.attack, t.health]
	return ""


## Infobulles détaillées d'une carte : [[titre, description], ...].
func tips(id: String) -> Array:
	var c := get_card(id)
	var out: Array = []
	if c.type == "minion":
		out.append([Loc.t("Serviteur %d/%d  ·  coût %d") % [c.attack, c.health, c.cost],
			Loc.t("Épée = attaque (dégâts qu'il inflige), cœur = points de vie. Une fois posé, il attaque une fois par tour à partir de votre tour suivant. Quand ses PV tombent à 0, il meurt.")])
	elif c.type == "enchantment":
		out.append([Loc.t("Enchantement  ·  coût %d") % c.cost,
			Loc.t("Reste en jeu à côté de votre héros (%d au maximum) et agit tant qu'il n'est pas détruit. Il n'a pas de PV : seules les cartes de destruction le retirent (Dissipation, Purification, Briseur de sorts).") % MAX_ENCHANTS])
		if c.has("aura"):
			out.append([Loc.t("Effet permanent"), Loc.t("Tant qu'il est en jeu : %s S'il est détruit, le bonus disparaît.") % c.text])
		for when in ["turn_start", "turn_end"]:
			if c.has(when):
				var fx_text := effect_text(c[when])
				out.append([Loc.t("Début de votre tour") if when == "turn_start" else Loc.t("Fin de votre tour"),
					fx_text.substr(0, 1).to_upper() + fx_text.substr(1)])
	else:
		out.append([Loc.t("Sort  ·  coût %d") % c.cost,
			Loc.t("Se joue depuis la main en dépensant l'énergie indiquée : l'effet s'applique tout de suite, puis la carte est défaussée.")])
		var sp: Dictionary = c.spell
		var fx_text := effect_text(sp)
		out.append([Loc.t("Effet"), fx_text.substr(0, 1).to_upper() + fx_text.substr(1)])
		if sp.get("target", "") == "chosen":
			out.append([Loc.t("Ciblage"), Loc.t("Après avoir cliqué la carte, cliquez sa cible. Clic droit ou clic dans le vide pour annuler.")])
	for kw in card_keywords(id):
		var info: Array = KEYWORDS[kw]
		var desc: String = Loc.t(info[1])
		if c.has(kw):   # cri de guerre / râle d'agonie : on détaille l'effet de cette carte
			desc += "\n[color=#9fd8ff]" + Loc.t("Ici : ") + effect_text(c[kw]) + "[/color]"
		elif kw == "ongoing":
			if c.has("aura"):
				desc += "\n[color=#9fd8ff]" + Loc.t("Ici : vos autres serviteurs ont +%d attaque et +%d PV.") % [int(c.aura.get("attack", 0)), int(c.aura.get("health", 0))] + "[/color]"
			for when in ["turn_start", "turn_end"]:
				if c.has(when):
					desc += "\n[color=#9fd8ff]" + Loc.t("Ici, %s : %s") % [Loc.t("au début de votre tour") if when == "turn_start" else Loc.t("à la fin de votre tour"), effect_text(c[when])] + "[/color]"
		out.append([Loc.t(info[0]), desc])
	if c.get("token", false):
		out.append([Loc.t("Jeton"), Loc.t("Carte créée par un effet : elle ne fait pas partie du deck et ne peut pas être piochée.")])
	return out


func card_keywords(id: String) -> Array:
	return get_card(id).get("keywords", [])


func card_art(id: String) -> Texture2D:
	return texture("res://assets/art/%s.png" % id)


const AVATAR_COUNT := 15   # 1 à 8 et 15 : au choix ; 9 à 14 : à débloquer (data/cosmetics.json)
const BASE_AVATARS: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 15]
const AVATAR_NAMES := {1: "Chevalier", 2: "Mage", 3: "Rôdeuse", 4: "Nain", 5: "Voleur", 6: "Prêtresse", 7: "Orc",
	8: "Sorcière", 15: "Aventurier"}


func avatar(n: int) -> Texture2D:
	return texture("res://assets/avatars/avatar_%d.png" % clampi(n, 1, AVATAR_COUNT))


func texture(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		tex = _get_placeholder()
	_tex_cache[path] = tex
	return tex


func _get_placeholder() -> Texture2D:
	if _placeholder == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		for x in 8:
			for y in 8:
				img.set_pixel(x, y, Color(0.35, 0.2, 0.45) if (x + y) % 2 == 0 else Color(0.2, 0.1, 0.3))
		_placeholder = ImageTexture.create_from_image(img)
	return _placeholder


## Texte d'aide détaillé (utilisé par la collection).
func explain(id: String) -> String:
	var c := get_card(id)
	var lines: PackedStringArray = []
	if c.type == "minion":
		lines.append(Loc.t("Serviteur — coût %d énergie, %d attaque / %d PV.") % [c.cost, c.attack, c.health])
		lines.append(Loc.t("Une fois posé sur le plateau, il peut attaquer une fois par tour à partir du tour suivant."))
	elif c.type == "enchantment":
		lines.append(Loc.t("Enchantement — coût %d énergie. Reste en jeu jusqu'à sa destruction par une carte.") % c.cost)
	else:
		lines.append(Loc.t("Sort — coût %d énergie. Son effet se résout immédiatement puis la carte est défaussée.") % c.cost)
		var sp: Dictionary = c.spell
		if sp.get("target", "") == "chosen":
			var rule: String = sp.get("target_rule", "any")
			if rule == "friendly_minion":
				lines.append(Loc.t("Cible : un de vos serviteurs."))
			else:
				lines.append(Loc.t("Cible : n'importe quel héros ou serviteur (allié ou ennemi)."))
	for kw in card_keywords(id):
		lines.append("[b]%s[/b] : %s" % [Loc.t(KEYWORDS[kw][0]), Loc.t(KEYWORDS[kw][1])])
	return "\n".join(lines)
