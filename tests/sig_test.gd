extends Node
## Vérifie la signature des manifestes de mise à jour : --sig-file=manifestes.json (valide, altéré, non signé).


func _ready() -> void:
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sig-file="):
			path = a.substr(11)
	var list = JSON.parse_string(FileAccess.get_file_as_string(path))
	for m in list:
		print("SIG ", m.get("sha256"), " -> ", Updater._signature_ok(m))
	get_tree().quit()
