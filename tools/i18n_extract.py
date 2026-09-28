"""Extrait les textes français à traduire -> data/i18n/_source.json (liste triée, sans doublons).

Sources : chaînes des scripts (textes affichés), cartes, règles, catalogue de personnalisation,
notes de mise à jour et messages du serveur. Usage : python tools/i18n_extract.py [--missing]
--missing : affiche seulement les textes absents d'au moins une traduction (data/i18n/<langue>.json).
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_FILES = ("match_check.gd", "verifier.gd")
STR_RE = re.compile(r'"""(.*?)"""|"((?:[^"\\\n]|\\.)*)"', re.S)
LANGS = ("en", "de", "es", "it", "pt")
LOC_RE = re.compile(r'Loc\.t\("((?:[^"\\\n]|\\.)*)"\)')


def unescape(t):
	return t.replace('\\"', '"').replace("\\n", "\n").replace("\\t", "\t").replace("\\\\", "\\")


def looks_like_text(t):
	if not re.search(r"[A-Za-zÀ-ÿ]{2,}", t):
		return False
	if t.startswith(("res://", "user://", "http", "#", "--")) or re.fullmatch(r"[a-z0-9_./:%-]+", t):
		return False
	if re.fullmatch(r"[A-Z][a-z]+(?:[A-Z][a-z0-9]*)+", t):   # nom de nœud (FrameRing...)
		return False
	return True


def from_scripts():
	out = set()
	for f in glob.glob(os.path.join(ROOT, "scripts", "**", "*.gd"), recursive=True):
		if os.path.basename(f) in SKIP_FILES:
			continue
		src = open(f, encoding="utf-8").read()
		# Lignes de débogage : print(...), push_warning(...)
		src = re.sub(r"^\s*(print|push_warning|push_error|printerr)\(.*$", "", src, flags=re.M)
		src = re.sub(r"^\s*#.*$", "", src, flags=re.M)
		for m in STR_RE.finditer(src):
			t = m.group(1) if m.group(1) is not None else unescape(m.group(2))
			if looks_like_text(t):
				out.add(t)
		# Tout texte passé à Loc.t() est à traduire, même un mot seul en minuscules (« vous »).
		for m in LOC_RE.finditer(src):
			t = unescape(m.group(1))
			if re.search(r"[A-Za-zÀ-ÿ]", t):
				out.add(t)
	return out


def from_data():
	out = set()
	cosm = json.load(open(os.path.join(ROOT, "data", "cosmetics.json"), encoding="utf-8"))
	for key, val in cosm.items():
		if isinstance(val, list):
			for it in val:
				if isinstance(it, dict):
					for k in ("name", "desc", "description"):
						if isinstance(it.get(k), str):
							out.add(it[k])
	for n in cosm.get("seasons", {}).get("names", {}).values():
		out.add(n)
	for entry in json.load(open(os.path.join(ROOT, "data", "patchnotes.json"), encoding="utf-8")):
		out.add(entry.get("title", ""))
		for title, lines in entry.get("sections", []):
			out.add(title)
			out.update(lines)
	return {t for t in out if t}


def from_server():
	src = open(os.path.join(ROOT, "server", "lobby_server.py"), encoding="utf-8").read()
	out = set()
	for m in re.finditer(r'\.t\(((?:"(?:[^"\\]|\\.)*"\s*)+)', src):
		parts = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
		out.add(unescape("".join(parts)))
	return out


def main():
	texts = sorted(from_scripts() | from_data() | from_server())
	if "--missing" in sys.argv:
		missing = set()
		for lang in LANGS:
			path = os.path.join(ROOT, "data", "i18n", f"{lang}.json")
			have = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
			missing |= {t for t in texts if t not in have}
		out = sorted(missing)
		json.dump(out, open(os.path.join(ROOT, "data", "i18n", "_missing.json"), "w", encoding="utf-8"),
				  ensure_ascii=False, indent=0)
		print(f"{len(out)} texte(s) à traduire -> data/i18n/_missing.json")
		return
	os.makedirs(os.path.join(ROOT, "data", "i18n"), exist_ok=True)
	json.dump(texts, open(os.path.join(ROOT, "data", "i18n", "_source.json"), "w", encoding="utf-8"),
			  ensure_ascii=False, indent=0)
	print(f"{len(texts)} textes -> data/i18n/_source.json ({sum(len(t) for t in texts)} caractères)")


if __name__ == "__main__":
	main()
