class_name Cosmetics
extends RefCounted
## Catalogue de personnalisation (data/cosmetics.json, partagé avec le serveur) :
## titres, avatars, contours d'avatar, dos de cartes, plateaux, avec leurs conditions
## de déblocage (statistiques, boutique en PO, passe de combat de la saison, Pionnier...).

const PATH := "res://data/cosmetics.json"
const KINDS := ["title", "avatar", "border", "card_back", "board"]
const KIND_KEYS := {"title": "titles", "avatar": "avatars", "border": "borders", "card_back": "card_backs", "board": "boards"}
const KIND_NAMES := {"title": "Titres", "avatar": "Avatars", "border": "Contours", "card_back": "Dos de cartes", "board": "Plateaux"}
const DEFAULTS := {"title": "novice", "avatar": 1, "border": "none", "card_back": "default", "board": "default"}

## Couleurs des contours : [couleur principale, couleur secondaire, vitesse d'animation, étincelles].
const BORDER_STYLES := {
	"none": [Color("6b5a3c"), Color("3a2e1e"), 0.0, 0.0],
	"bronze": [Color("cd7f32"), Color("7a4418"), 0.0, 0.0],
	"argent": [Color("e6ecf2"), Color("8a97a6"), 0.3, 0.25],
	"or": [Color("ffd24a"), Color("b07a10"), 0.5, 0.5],
	"arcane": [Color("c58bff"), Color("4a1f8a"), 1.2, 0.6],
	"flammes": [Color("ffb030"), Color("d0300a"), 1.8, 0.7],
	"givre": [Color("bff0ff"), Color("3a8fd0"), 0.8, 0.6],
	"champion": [Color("fff2a0"), Color("ff9a1a"), 1.5, 1.0],
	"emeraude": [Color("7dffb0"), Color("0a7a44"), 0.4, 0.35],
	"rubis": [Color("ff7a8a"), Color("8a0a1e"), 0.4, 0.35],
	"obsidienne": [Color("7a6a9a"), Color("0a0612"), 0.9, 0.5],
	"aurore": [Color("ffb0e0"), Color("7ad0ff"), 1.0, 0.6],
	"eveil": [Color("fff8d0"), Color("ffb020"), 1.6, 0.9],
	# Saison 2 : Le Crépuscule
	"braises": [Color("ff8a2a"), Color("5a1a08"), 1.3, 0.8],
	"crepuscule": [Color("ffb060"), Color("5a2a9a"), 1.5, 1.0],
	"pionnier": [Color("9fe8ff"), Color("2a6aa0"), 0.8, 0.7],
	"tenace": [Color("c0c0c0"), Color("5a3a2a"), 0.3, 0.2],
	# Niveaux d'IA battus (2.0)
	"ia_apprenti": [Color("b8e07a"), Color("6a4a22"), 0.0, 0.0],
	"ia_chevalier": [Color("cfe2ff"), Color("4a6a9a"), 0.4, 0.3],
	"ia_seigneur": [Color("ff4a3a"), Color("2a0808"), 1.1, 0.6],
	"ia_challenger": [Color("e8d0ff"), Color("8a3aff"), 1.7, 1.0],
}

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed
	return _data


static func items(kind: String) -> Array:
	return data().get(KIND_KEYS[kind], [])


static func item(kind: String, id) -> Dictionary:
	for it in items(kind):
		if str(it.id) == str(id):
			return it
	return {}


static func item_name(kind: String, id) -> String:
	return Loc.t(_item_name(kind, id))


static func _item_name(kind: String, id) -> String:
	return str(item(kind, id).get("name", ""))


static func title_name(id) -> String:
	return item_name("title", id)


static func card_back_texture(id) -> Texture2D:
	if str(id) == "" or str(id) == "default":
		return CardDB.texture("res://assets/ui/card_back.png")
	return CardDB.texture("res://assets/cosmetics/back_%s.png" % id)


static func board_texture(id) -> Texture2D:
	if str(id) == "" or str(id) == "default":
		return CardDB.texture("res://assets/bg/board.png")
	return CardDB.texture("res://assets/cosmetics/board_%s.png" % id)


static func border_style(id) -> Array:
	return BORDER_STYLES.get(str(id), BORDER_STYLES["none"])


## Saison en cours calculée localement (même règle que le serveur : une saison par mois depuis « epoch », en UTC).
## Sert hors ligne : progression à zéro, récompenses lues dans cosmetics.json.
static func local_season(now := -1) -> Dictionary:
	var conf: Dictionary = data().get("seasons", {})
	if conf.is_empty():
		return {}
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	var ep := str(conf.get("epoch", "2026-09-26")).split("-")
	var y := int(ep[0])
	var m := int(ep[1])
	var d := int(ep[2])
	var n := 1
	while _month_start(y, m + n, d) <= now and n < 1200:
		n += 1
	var rewards: Array = conf.get("rewards", {}).get(str(n), conf.get("default_rewards", []))
	return {"n": n, "start": _month_start(y, m + n - 1, d), "end": _month_start(y, m + n, d), "xp": 0, "level": 0,
		"levels": int(conf.get("levels", 30)), "xp_per_level": int(conf.get("xp_per_level", 250)),
		"name": str(conf.get("names", {}).get(str(n), "")), "rewards": rewards, "games": 0, "offline": true}


static func _month_start(y: int, m: int, d: int) -> int:
	y += (m - 1) / 12
	m = (m - 1) % 12 + 1
	var days_in := [31, 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": mini(d, days_in[m - 1]), "hour": 0, "minute": 0, "second": 0})


## Prix en boutique (PO), 0 si l'objet n'est pas en vente.
static func price(kind: String, id) -> int:
	var rule = item(kind, id).get("rule")
	return int(rule.get("shop", 0)) if rule is Dictionary else 0


## Condition de déblocage lisible, ex. « 100 sorts joués ».
static func rule_text(rule) -> String:
	if not rule is Dictionary or rule.is_empty():
		return Loc.t("Débloqué d'office.")
	if rule.has("rank"):
		return Loc.t("Être n°1 du classement (tant que vous l'êtes).")
	if rule.has("shop"):
		return Loc.t("En vente dans la boutique : %d PO.") % int(rule.shop)
	if rule.has("pass"):
		return Loc.t("Passe de combat de la saison %d : niveau %d.") % [int(rule.get("season", 1)), int(rule.pass)]
	if rule.has("pioneer"):
		return Loc.t("Avoir joué pendant la saison 1 (attribué à la fin de la saison).")
	if str(rule.stat).begins_with("ai_beaten_"):
		var lvl := int(str(rule.stat).get_slice("_", 2))
		return Loc.t("Battre l'IA %s.") % Loc.t(["Apprenti", "Chevalier", "Seigneur de guerre", "Challenger"][clampi(lvl, 0, 3)])
	var label: String = data().get("stats", {}).get(rule.stat, rule.stat)
	return "%d %s." % [int(rule.min), Loc.t(label)]


## Progression [actuel, objectif] vers une condition (objectif 0 = pas de compteur).
static func progress(rule, stats: Dictionary) -> Array:
	if not rule is Dictionary or rule.is_empty() or not rule.has("stat"):
		return [0, 0]
	return [mini(int(stats.get(rule.stat, 0)), int(rule.min)), int(rule.min)]
