"""Publie une version d'Arcanes & Lames sur le serveur officiel (VPS).

  python tools/publish_update.py 1.1.0 "Pioche au choix : 3 cartes, gardez-en une."
  python tools/publish_update.py 1.1.0 "..." --local     (sans envoi sur le VPS)

Étapes :
1. écrit la version dans project.godot (application/config/version) ;
2. exporte le jeu Windows complet (preset « Windows Desktop ») dans build/ArcanesEtLames/
   pose l'icône du jeu et les informations de version dans l'exe (tools/bin/rcedit-x64.exe),
   puis signe l'exe (certificat « Arcanes & Lames », voir tools/codesign.json) ;
3. crée dist/ :
     arcanes_<version>.pck                  paquet de mise à jour (téléchargé par les jeux déjà installés)
     ArcanesEtLames_<version>_windows.zip   jeu complet pour les nouveaux joueurs
     latest.json                            version, fichiers, sha256, taille, notes
     install.ps1                            installateur en une ligne (sans avertissement SmartScreen)
     arcanes_codesign.cer                   certificat public de signature
4. envoie le tout sur le VPS (scp, latest.json en dernier pour que la bascule soit atomique)
   et supprime les anciennes versions du serveur.

Le serveur sert ces fichiers sur http://<vps>:7779/ (page de téléchargement, /version.json, /files, /download)
et refuse les clients plus anciens que latest.json : tout le monde joue sur la même version.

Variables d'environnement :
  GODOT           chemin de Godot (console) ; sinon l'emplacement par défaut ci-dessous
  ARCANES_DEPLOY  destination scp (défaut : arcanes-vps:/srv/arcanes/updates, alias défini dans ~/.ssh/config)
"""

import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build", "ArcanesEtLames")
DIST = os.path.join(ROOT, "dist")
DEFAULT_GODOT = r"C:\Users\user\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
DEPLOY = os.environ.get("ARCANES_DEPLOY", "arcanes-vps:/srv/arcanes/updates")
CODESIGN = json.load(open(os.path.join(ROOT, "tools", "codesign.json"), encoding="utf-8"))
CERT_DIR = os.path.join(os.path.expanduser("~"), ".arcanes-codesign")


def run(cmd, **kw):
    print("  >", " ".join(cmd))
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)


def set_project_version(version):
    path = os.path.join(ROOT, "project.godot")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if re.search(r'^config/version=".*"$', text, re.M):
        text = re.sub(r'^config/version=".*"$', f'config/version="{version}"', text, flags=re.M)
    else:
        text = text.replace("[application]\n", f'[application]\n\nconfig/version="{version}"\n', 1)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


SIGNING_KEY = os.path.join(os.path.expanduser("~"), ".arcanes-codesign", "update_signing_key.pem")


def sign_manifest(latest):
    """Signe le manifeste (RSA PKCS#1 v1.5, SHA-256) : le jeu refuse une mise à jour non signée par cette clé."""
    import base64
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    if not os.path.isfile(SIGNING_KEY):
        sys.exit(f"Clé de signature des mises à jour introuvable : {SIGNING_KEY}")
    with open(SIGNING_KEY, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    text = f"arcanes-update|{latest['version']}|{latest['file']}|{latest['sha256'].lower()}|{int(latest['size'])}"
    latest["signature"] = base64.b64encode(key.sign(text.encode("utf-8"), padding.PKCS1v15(), hashes.SHA256())).decode()


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def vtuple(v):
    return tuple(int(x) for x in v.split("."))


def remote_version():
    """Version actuellement publiée sur le VPS (None si aucune)."""
    host, path = DEPLOY.split(":", 1)
    r = run(["ssh", "-o", "BatchMode=yes", host, f"cat {path}/latest.json 2>/dev/null || true"])
    try:
        return json.loads(r.stdout).get("version")
    except ValueError:
        return None


def export_game(godot, version):
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    os.makedirs(BUILD)
    gdignore = os.path.join(ROOT, "build", ".gdignore")
    open(gdignore, "a").close()   # Godot ne doit pas importer le dossier de build
    exe = os.path.join(BUILD, "ArcanesEtLames.exe")
    r = run([godot, "--headless", "--path", ROOT, "--export-release", "Windows Desktop", exe])
    pck = os.path.join(BUILD, "ArcanesEtLames.pck")
    if r.returncode != 0 or not os.path.isfile(exe) or not os.path.isfile(pck):
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit("ÉCHEC de l'export du jeu.")
    with open(os.path.join(BUILD, "LISEZMOI.txt"), "w", encoding="utf-8") as f:
        f.write(f"Arcanes & Lames {version}\n\n"
                "Lancez ArcanesEtLames.exe. Choisissez votre pseudo dans Paramètres > Profil.\n"
                "Le jeu se connecte automatiquement au serveur officiel et se met à jour tout seul.\n"
                "Si Windows affiche « Windows a protégé votre ordinateur » : Informations complémentaires > Exécuter quand même.\n")
    return exe, pck


def set_exe_resources(exe, version):
    """Icône du jeu + informations affichées par Windows (Propriétés > Détails) via rcedit (electron/rcedit)."""
    rcedit = os.path.join(ROOT, "tools", "bin", "rcedit-x64.exe")
    icon = os.path.join(ROOT, "assets", "ui", "game_icon.ico")
    v4 = ".".join((version.split(".") + ["0", "0", "0"])[:4])
    r = run([rcedit, exe, "--set-icon", icon,
             "--set-file-version", v4, "--set-product-version", v4,
             "--set-version-string", "ProductName", "Arcanes & Lames",
             "--set-version-string", "FileDescription", "Arcanes & Lames",
             "--set-version-string", "CompanyName", "Arcanes & Lames",
             "--set-version-string", "LegalCopyright", "Arcanes & Lames",
             "--set-version-string", "OriginalFilename", "ArcanesEtLames.exe",
             "--set-version-string", "InternalName", "ArcanesEtLames"])
    if r.returncode != 0:
        print(r.stdout, r.stderr)
        sys.exit("ÉCHEC de la pose de l'icône (rcedit).")
    print(f"  icône et version {v4} appliquées à l'exe")


def sign_exe(exe):
    """Signe l'exe avec le certificat du magasin Windows (Set-AuthenticodeSignature) + horodatage."""
    thumb = CODESIGN["thumbprint"]
    ps = (f"$c = Get-ChildItem Cert:\\CurrentUser\\My\\{thumb} -ErrorAction Stop; "
          f"$r = Set-AuthenticodeSignature -FilePath '{exe}' -Certificate $c -HashAlgorithm SHA256 "
          f"-TimestampServer '{CODESIGN['timestamp_server']}'; "
          f"$v = Get-AuthenticodeSignature '{exe}'; "
          f"Write-Output \"$($v.Status)|$($v.SignerCertificate.Thumbprint)|$($v.TimeStamperCertificate.Subject)\"")
    r = run(["powershell", "-NoProfile", "-Command", ps])
    parts = r.stdout.strip().split("|")
    if len(parts) < 3 or parts[1] != thumb or parts[0] in ("NotSigned", "HashMismatch"):
        print(r.stdout, r.stderr)
        sys.exit("ÉCHEC de la signature (certificat absent de ce PC ? voir tools/codesign.json).")
    print(f"  exe signé ({thumb[:12]}...), horodatage : {parts[2] or 'aucun'}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    local_only = "--local" in sys.argv
    if not args or not re.fullmatch(r"\d+(\.\d+){1,3}", args[0]):
        print(__doc__)
        sys.exit(1)
    version, notes = args[0], (args[1] if len(args) > 1 else "")
    # Notes de mise à jour affichées dans le jeu (data/patchnotes.json) : la version doit y figurer.
    with open(os.path.join(ROOT, "data", "patchnotes.json"), encoding="utf-8") as f:
        entry = next((e for e in json.load(f) if e.get("version") == version), None)
    if entry is None:
        sys.exit(f"Ajoutez d'abord la version {version} dans data/patchnotes.json (notes affichées dans le jeu).")
    if not notes:
        notes = entry.get("title", "")
    godot = os.environ.get("GODOT", DEFAULT_GODOT)

    if not local_only:
        prev = remote_version()
        print(f"Version publiée sur le serveur : {prev or 'aucune'}")
        if prev and vtuple(version) <= vtuple(prev):
            sys.exit(f"La version {version} doit être supérieure à la version publiée ({prev}).")

    set_project_version(version)
    print(f"Export du jeu {version}...")
    exe, pck = export_game(godot, version)
    set_exe_resources(exe, version)
    sign_exe(exe)

    if os.path.isdir(DIST):
        shutil.rmtree(DIST)
    os.makedirs(DIST)
    open(os.path.join(DIST, ".gdignore"), "a").close()
    pck_name = f"arcanes_{version}.pck"
    zip_name = f"ArcanesEtLames_{version}_windows.zip"
    shutil.copy2(pck, os.path.join(DIST, pck_name))
    print("Création de l'archive", zip_name)
    with zipfile.ZipFile(os.path.join(DIST, zip_name), "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for name in sorted(os.listdir(BUILD)):
            z.write(os.path.join(BUILD, name), f"ArcanesEtLames/{name}")
    with open(os.path.join(ROOT, "tools", "installer", "install.ps1"), encoding="utf-8") as f:
        installer = f.read().replace("__BASE__", CODESIGN["web_base"]).replace("__THUMBPRINT__", CODESIGN["thumbprint"])
    with open(os.path.join(DIST, "install.ps1"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(installer)
    shutil.copy2(os.path.join(CERT_DIR, "arcanes_codesign.cer"), os.path.join(DIST, "arcanes_codesign.cer"))
    shutil.copy2(os.path.join(ROOT, "assets", "ui", "game_icon.ico"), os.path.join(DIST, "favicon.ico"))
    latest = {
        "version": version,
        "file": pck_name,
        "sha256": sha256(os.path.join(DIST, pck_name)),
        "size": os.path.getsize(os.path.join(DIST, pck_name)),
        "download": zip_name,
        "download_size": os.path.getsize(os.path.join(DIST, zip_name)),
        "download_sha256": sha256(os.path.join(DIST, zip_name)),
        "codesign_thumbprint": CODESIGN["thumbprint"],
        "notes": notes,
    }
    sign_manifest(latest)
    with open(os.path.join(DIST, "latest.json"), "w", encoding="utf-8") as f:
        json.dump(latest, f, ensure_ascii=False, indent=2)
    print(f"Paquet {latest['size'] / 1048576:.1f} Mo, archive {latest['download_size'] / 1048576:.1f} Mo -> {DIST}")

    if local_only:
        print("Mode --local : rien n'a été envoyé sur le serveur.")
        return
    host, path = DEPLOY.split(":", 1)
    print("Envoi sur le serveur", DEPLOY)
    r = run(["scp", "-q", os.path.join(DIST, pck_name), os.path.join(DIST, zip_name),
             os.path.join(DIST, "install.ps1"), os.path.join(DIST, "arcanes_codesign.cer"),
             os.path.join(DIST, "favicon.ico"), f"{DEPLOY}/"])
    if r.returncode != 0:
        sys.exit("ÉCHEC de l'envoi : " + r.stderr)
    r = run(["scp", "-q", os.path.join(DIST, "latest.json"), f"{DEPLOY}/latest.json.tmp"])
    if r.returncode != 0:
        sys.exit("ÉCHEC de l'envoi de latest.json : " + r.stderr)
    # Bascule atomique puis ménage des anciennes versions. Les paquets précédents vont dans packs/ (non publié) :
    # le serveur s'en sert pour valider les parties commencées avant la mise à jour ; on garde les 5 derniers.
    cleanup = (f"cd {path} && mv -f latest.json.tmp latest.json && chmod 664 latest.json {pck_name} {zip_name} install.ps1 arcanes_codesign.cer favicon.ico && "
               f"mkdir -p packs && find . -maxdepth 1 \\( -name 'arcanes_*.pck' ! -name '{pck_name}' \\) -exec mv -f {{}} packs/ \\; && "
               f"(ls -1t packs/arcanes_*.pck 2>/dev/null | tail -n +6 | xargs -r rm -f) && "
               f"find . -maxdepth 1 \\( -name 'ArcanesEtLames_*_windows.zip' ! -name '{zip_name}' \\) -delete && ls -la")
    r = run(["ssh", "-o", "BatchMode=yes", host, cleanup])
    print(r.stdout, r.stderr)
    print(f"Version {version} publiée. Page de téléchargement : {CODESIGN['web_base']}/")


if __name__ == "__main__":
    main()
