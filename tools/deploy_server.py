"""Déploie le serveur communautaire sur le VPS SANS couper les parties en cours.

Usage : python tools/deploy_server.py [--dry-run]

1. sauvegarde le code, le catalogue, les traductions et les données actuels (/var/backups/arcanes/pre-deploy-<date>) ;
2. installe server/lobby_server.py, data/cosmetics.json et data/i18n/*.json dans /opt/arcanes ;
3. « systemctl reload arcanes-lobby » : le serveur en place (SIGUSR1) suspend les nouvelles parties en ligne,
   attend la fin de celles en cours et des validations, enregistre les parties contre l'IA en cours, puis
   s'arrête ; systemd le relance aussitôt avec le nouveau code. Les joueurs connectés sont reconnectés
   automatiquement (quelques secondes, sans message d'erreur) et leurs parties contre l'IA restent valables ;
4. attend le nouveau processus et affiche le journal, puis vérifie que les autres sites du VPS répondent.

Prérequis (une fois) : l'unité systemd doit contenir ExecReload=/bin/kill -USR1 $MAINPID et Restart=always.
"""
import os
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOST = os.environ.get("ARCANES_HOST", "arcanes-vps")
LANGS = ("en", "de", "es", "it", "pt")
OTHER_SITES = ("https://site-a.example", "https://site-b.example")   # autres projets du VPS : ne doivent pas être touchés


def ssh(cmd, check=True):
	r = subprocess.run(["ssh", "-o", "BatchMode=yes", HOST, cmd], capture_output=True, text=True, encoding="utf-8")
	if check and r.returncode != 0:
		sys.exit(f"ÉCHEC : {cmd}\n{r.stdout}{r.stderr}")
	return r.stdout.strip()


def main():
	dry = "--dry-run" in sys.argv
	unit = ssh("systemctl cat arcanes-lobby")
	if "ExecReload=" not in unit or "Restart=always" not in unit:
		sys.exit("L'unité arcanes-lobby n'a pas encore ExecReload/Restart=always : à ajouter une fois (voir l'en-tête).")
	files = [os.path.join(ROOT, "server", "lobby_server.py"), os.path.join(ROOT, "data", "cosmetics.json")]
	files += [os.path.join(ROOT, "data", "i18n", f"{l}.json") for l in LANGS]
	r = subprocess.run(["python", "-m", "py_compile", files[0]])
	if r.returncode != 0:
		sys.exit("lobby_server.py ne compile pas.")
	if dry:
		print("Simulation : fichiers prêts, unité compatible.")
		return
	r = subprocess.run(["scp", "-q"] + files + [f"{HOST}:/tmp/"])
	if r.returncode != 0:
		sys.exit("ÉCHEC de l'envoi.")
	old_pid = ssh("systemctl show -p MainPID --value arcanes-lobby")
	ts = time.strftime("%Y%m%d-%H%M%S")
	ssh(f"""set -e
B=/var/backups/arcanes/pre-deploy-{ts}; sudo mkdir -p $B
sudo cp -a /opt/arcanes/lobby_server.py /opt/arcanes/cosmetics.json /opt/arcanes/i18n $B/
sudo cp -a /var/lib/arcanes/lobby_data.json $B/
OWN=$(stat -c %U:%G /opt/arcanes/lobby_server.py)
sudo install -o ${{OWN%:*}} -g ${{OWN#*:}} -m 644 /tmp/lobby_server.py /opt/arcanes/lobby_server.py
sudo install -o ${{OWN%:*}} -g ${{OWN#*:}} -m 644 /tmp/cosmetics.json /opt/arcanes/cosmetics.json
for l in {' '.join(LANGS)}; do sudo install -o ${{OWN%:*}} -g ${{OWN#*:}} -m 644 /tmp/$l.json /opt/arcanes/i18n/$l.json; rm -f /tmp/$l.json; done
rm -f /tmp/lobby_server.py /tmp/cosmetics.json
sudo systemctl reload arcanes-lobby""")
	print(f"Code installé (sauvegarde pre-deploy-{ts}). Redémarrage en douceur demandé : attente de la fin des parties en ligne...")
	while True:
		pid = ssh("systemctl show -p MainPID --value arcanes-lobby", check=False)
		if pid and pid != "0" and pid != old_pid and ssh("systemctl is-active arcanes-lobby", check=False) == "active":
			break
		print("  " + (ssh("sudo journalctl -u arcanes-lobby -n 1 --no-pager -o cat", check=False) or "...")[:150])
		time.sleep(10)
	time.sleep(3)
	print(ssh("sudo journalctl -u arcanes-lobby -n 8 --no-pager -o cat", check=False))
	for url in OTHER_SITES:
		try:
			code = urllib.request.urlopen(url, timeout=15).status
		except Exception as e:
			code = e
		print(f"{url} : {code}")
	print("Serveur déployé.")


if __name__ == "__main__":
	main()
