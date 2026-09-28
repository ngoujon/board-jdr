"""Vérifie une traduction : python tools/i18n_check.py <langue> [source.json]

Chaque texte source doit être traduit, avec les mêmes marqueurs de mise en forme dans le même ordre
(%s %d %.1f %%, {nom}), les mêmes balises BBCode ([b], [color=...], [lb]...) et le même nombre de sauts de ligne.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FMT_RE = re.compile(r"%(?:[-+ 0#]*\d*(?:\.\d+)?[sdfxXc%])|\{[a-z_]+\}")
TAG_RE = re.compile(r"\[/?[a-z_]+(?:=[^\]]*)?\]")


def check(lang, source_path):
	src = json.load(open(source_path, encoding="utf-8"))
	path = os.path.join(ROOT, "data", "i18n", f"{lang}.json")
	tr = json.load(open(path, encoding="utf-8"))
	problems = []
	for s in src:
		t = tr.get(s)
		if not isinstance(t, str) or t.strip() == "":
			problems.append(("manquant", s))
			continue
		if FMT_RE.findall(s) != FMT_RE.findall(t):
			problems.append(("marqueurs %s/{} différents", s))
		elif sorted(TAG_RE.findall(s)) != sorted(TAG_RE.findall(t)):
			problems.append(("balises BBCode différentes", s))
		elif s.count("\n") != t.count("\n") and len(s) < 400:
			problems.append(("sauts de ligne différents", s))
	for kind, s in problems[:60]:
		print(f"[{kind}] {s[:100]!r}")
	print(f"{lang} : {len(src) - len(problems)}/{len(src)} textes corrects, {len(problems)} problème(s)")
	return not problems


if __name__ == "__main__":
	ok = check(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "data", "i18n", "_source.json"))
	sys.exit(0 if ok else 1)
