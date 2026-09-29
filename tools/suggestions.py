"""Affiche le forum des suggestions des joueurs (menu Suggestions du jeu) : sujets et réponses.

Usage :
  python tools/suggestions.py                  derniers sujets (activité la plus récente d'abord)
  python tools/suggestions.py --kind bug       seulement les bugs (buff | nerf | bug | autre)
  python tools/suggestions.py --card goule     sujets qui visent une carte
  python tools/suggestions.py --player NOM     sujets d'un joueur
  python tools/suggestions.py --id 12          un sujet et tout son fil de réponses

Lecture seule de /var/lib/arcanes/history.db sur le VPS (via ssh arcanes-vps).
"""
import argparse
import json
import os
import subprocess
import sys
import time

HOST = os.environ.get("ARCANES_HOST", "arcanes-vps")
DB = "/var/lib/arcanes/history.db"

REMOTE = r'''
import json, sqlite3, sys
a = json.loads(sys.argv[1])
db = sqlite3.connect("file:%s?mode=ro" % a["db"], uri=True)
out = {"topics": [], "replies": []}
try:
    q = "SELECT id, ts, name, cards, kind, text, game_version, COALESCE(replies, 0), COALESCE(last_ts, ts) FROM suggestions WHERE 1=1"
    args = []
    if a["id"]:
        q += " AND id=?"
        args.append(a["id"])
    if a["kind"]:
        q += " AND kind=?"
        args.append(a["kind"])
    if a["card"]:
        q += " AND (',' || cards || ',') LIKE ?"
        args.append("%%,%s,%%" % a["card"])
    if a["player"]:
        q += " AND name LIKE ?"
        args.append(a["player"])
    q += " ORDER BY COALESCE(last_ts, ts) DESC LIMIT ?"
    args.append(a["limit"])
    out["topics"] = db.execute(q, args).fetchall()
    if a["id"]:
        out["replies"] = db.execute("SELECT ts, name, text FROM suggestion_replies WHERE sugg_id=? ORDER BY id", (a["id"],)).fetchall()
except sqlite3.OperationalError:
    pass   # tables pas encore créées (serveur antérieur à la 2.0.8)
print(json.dumps(out, ensure_ascii=False))
'''


def fmt(ts):
	return time.strftime("%d/%m/%Y %H:%M", time.localtime(ts))


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--limit", type=int, default=100)
	ap.add_argument("--kind", default="", choices=["", "buff", "nerf", "bug", "autre"])
	ap.add_argument("--card", default="", help="identifiant d'une carte (ex. goule)")
	ap.add_argument("--player", default="", help="pseudo du joueur")
	ap.add_argument("--id", type=int, default=0, help="numéro d'un sujet : affiche tout le fil")
	a = ap.parse_args()
	params = json.dumps({"db": DB, "limit": a.limit, "kind": a.kind, "card": a.card, "player": a.player, "id": a.id})
	r = subprocess.run(["ssh", "-o", "BatchMode=yes", HOST, "sudo python3 - '" + params.replace("'", "") + "'"],
					   input=REMOTE, capture_output=True, text=True, encoding="utf-8")
	if r.returncode != 0:
		sys.exit(r.stderr)
	data = json.loads(r.stdout or "{}")
	topics = data.get("topics", [])
	if not topics:
		print("Aucun sujet.")
		return
	for sid, ts, name, cards, kind, text, version, replies, last_ts in topics:
		print(f"#{sid}  {fmt(ts)}  {name:<16} {kind.upper():<5} [{cards}]  v{version or '?'}  "
			  f"{replies} réponse(s), dernière activité {fmt(last_ts)}\n    {text}")
	for ts, name, text in data.get("replies", []):
		print(f"    ↳ {fmt(ts)}  {name} : {text}")
	print(f"\n{len(topics)} sujet(s).")


if __name__ == "__main__":
	if hasattr(sys.stdout, "reconfigure"):
		sys.stdout.reconfigure(encoding="utf-8")
	main()
