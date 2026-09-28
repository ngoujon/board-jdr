"""Exporte le projet Xcode iOS d'Arcanes & Lames (à compiler ensuite sur un Mac avec Xcode).

  python tools/export_ios.py <TEAM_ID>

TEAM_ID : identifiant d'équipe Apple (10 caractères), visible dans Xcode > Settings > Accounts
(un compte Apple gratuit suffit pour installer le jeu sur ses propres appareils, pour 7 jours).
Résultat : dist/ArcanesEtLames_<version>_ios_xcode.zip, à décompresser sur le Mac. Voir docs/IOS.md.
"""
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GODOT = os.environ.get("GODOT", r"C:\Users\user\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe")


def main():
    if len(sys.argv) < 2 or not re.fullmatch(r"[A-Z0-9]{10}", sys.argv[1]):
        print(__doc__)
        sys.exit(1)
    team = sys.argv[1]
    presets = os.path.join(ROOT, "export_presets.cfg")
    with open(presets, encoding="utf-8") as f:
        original = f.read()
    version = re.search(r'^config/version="(.*)"$', open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read(), re.M).group(1)
    out = os.path.join(ROOT, "build", "ios")
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    # L'identifiant d'équipe n'est pas gardé dans le dépôt : on le pose le temps de l'export.
    with open(presets, "w", encoding="utf-8", newline="\n") as f:
        f.write(original.replace('application/app_store_team_id=""', f'application/app_store_team_id="{team}"'))
    try:
        r = subprocess.run([GODOT, "--headless", "--path", ROOT, "--export-release", "iOS", os.path.join(out, "ArcanesEtLames.ipa")],
                           capture_output=True, text=True, encoding="utf-8", errors="replace")
    finally:
        with open(presets, "w", encoding="utf-8", newline="\n") as f:
            f.write(original)
    if not os.path.isfile(os.path.join(out, "ArcanesEtLames.pck")):
        print((r.stdout + r.stderr)[-3000:])
        sys.exit("ÉCHEC de l'export iOS.")
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    dest = os.path.join(ROOT, "dist", f"ArcanesEtLames_{version}_ios_xcode.zip")
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for base, _, files in os.walk(out):
            for name in files:
                full = os.path.join(base, name)
                z.write(full, os.path.join("ArcanesEtLames_iOS", os.path.relpath(full, out)))
    print(f"Projet Xcode : {dest} ({os.path.getsize(dest) / 1048576:.0f} Mo). Suite sur le Mac : docs/IOS.md")


if __name__ == "__main__":
    main()
