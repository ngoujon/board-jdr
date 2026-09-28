class_name Loc
extends RefCounted
## Traductions du jeu. Le texte source est en français : il sert de clé. Les traductions sont chargées depuis
## data/i18n/<langue>.json ({texte français: traduction}) et enregistrées auprès du TranslationServer :
## les Label / Button traduisent donc automatiquement leur texte, et Loc.t() traduit un texte avant de le
## mettre en forme (ex. Loc.t("Niveau %d") % n) ou de l'ajouter à un RichTextLabel.

const LANGS := ["fr", "en", "de", "es", "it", "pt"]
const LANG_NAMES := {"fr": "Français", "en": "English", "de": "Deutsch", "es": "Español", "it": "Italiano", "pt": "Português"}

static var _loaded := false


## Texte traduit dans la langue choisie (le texte français s'il n'a pas de traduction).
static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


## Langue par défaut : le français (le joueur en choisit une autre dans Paramètres > Langue).
static func system_language() -> String:
	return "fr"


static func load_translations() -> void:
	if _loaded:
		return
	_loaded = true
	for lang in LANGS:
		if lang == "fr":
			continue
		var path := "res://data/i18n/%s.json" % lang
		if not FileAccess.file_exists(path):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not data is Dictionary:
			continue
		var tr := Translation.new()
		tr.locale = lang
		for k in data:
			if str(data[k]) != "":
				tr.add_message(k, data[k])
		TranslationServer.add_translation(tr)


static func set_language(lang: String) -> void:
	load_translations()
	# Le français est le texte source : aucune traduction, et surtout pas de repli sur l'anglais.
	ProjectSettings.set_setting("internationalization/locale/fallback", "fr")
	TranslationServer.set_locale(lang if lang in LANGS else "fr")
