extends Node
## Vérificateur de parties (anti-triche), lancé par le serveur communautaire en mode sans affichage :
##   godot --headless --main-pack arcanes_X.pck res://scenes/tools/verifier.tscn -- --verifier --job=partie.json
## Le fichier décrit la partie (voir MatchCheck.verify_ai / verify_pvp) ; le résultat est écrit sur la sortie
## standard, sur une ligne préfixée par « @@RESULT ».


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--job="):
			path = a.substr(6)
	var out := {"ok": false, "error": "aucune partie à vérifier"}
	if path != "" and FileAccess.file_exists(path):
		var job = JSON.parse_string(FileAccess.get_file_as_string(path))
		if job is Dictionary:
			out = MatchCheck.verify_pvp(job) if str(job.get("mode", "")) == "pvp" else MatchCheck.verify_ai(job)
		else:
			out = {"ok": false, "error": "fichier illisible"}
	out["version"] = Updater.current_version()
	print("@@RESULT " + JSON.stringify(out))
	get_tree().quit()
