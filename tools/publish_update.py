"""Publie une version d'Arcanes & Lames sur le serveur officiel (VPS).

  python tools/publish_update.py 1.1.0 "Pioche au choix : 3 cartes, gardez-en une."
  python tools/publish_update.py 1.1.0 "..." --local     (sans envoi sur le VPS)
  python tools/publish_update.py --site-only             (page d'accueil seule, pour la version déjà publiée)

Étapes :
1. écrit la version dans project.godot (application/config/version) ;
2. exporte le jeu Windows complet (preset « Windows Desktop ») dans build/ArcanesEtLames/
   pose l'icône du jeu et les informations de version dans l'exe (tools/bin/rcedit-x64.exe),
   puis signe l'exe (certificat « Arcanes & Lames », voir tools/codesign.json) ;
   exporte aussi les versions Linux (build/linux/) et macOS (build/macos/, application universelle signée ad hoc) ;
3. crée dist/ :
     arcanes_<version>.pck                  paquet de mise à jour Windows (téléchargé par les jeux déjà installés)
     arcanes_<version>_linux.pck / _macos.pck   paquets Linux et macOS, seulement s'ils diffèrent de celui de Windows
     ArcanesEtLames_<version>_windows.zip   jeu complet pour les nouveaux joueurs
     ArcanesEtLames_<version>_linux.tar.gz / _macos.zip
     latest.json                            version, fichiers, sha256, taille, notes (+ "platforms", "downloads")
     install.ps1                            installateur en une ligne (sans avertissement SmartScreen)
     install.sh                             installateur en une ligne pour Linux et macOS (curl | sh)
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
BUILD_LINUX = os.path.join(ROOT, "build", "linux")
BUILD_MACOS = os.path.join(ROOT, "build", "macos")
MAC_APP = "Arcanes & Lames.app"   # nom de l'application produite par l'export macOS (nom du projet)
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


def sign_manifest(latest, version=None):
    """Signe le manifeste (RSA PKCS#1 v1.5, SHA-256) : le jeu refuse une mise à jour non signée par cette clé.
    Sert aussi pour les entrées de "platforms" (version passée à part)."""
    import base64
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding
    if not os.path.isfile(SIGNING_KEY):
        sys.exit(f"Clé de signature des mises à jour introuvable : {SIGNING_KEY}")
    with open(SIGNING_KEY, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    text = f"arcanes-update|{version or latest['version']}|{latest['file']}|{latest['sha256'].lower()}|{int(latest['size'])}"
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


def export_linux(godot, version):
    """Jeu Linux x86_64 (binaire + .pck + icône du raccourci) : renvoie (dossier, pck)."""
    out = os.path.join(BUILD_LINUX, "ArcanesEtLames")
    if os.path.isdir(BUILD_LINUX):
        shutil.rmtree(BUILD_LINUX)
    os.makedirs(out)
    binary = os.path.join(out, "ArcanesEtLames.x86_64")
    r = run([godot, "--headless", "--path", ROOT, "--export-release", "Linux", binary])
    pck = os.path.join(out, "ArcanesEtLames.pck")
    if r.returncode != 0 or not os.path.isfile(binary) or not os.path.isfile(pck):
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit("ÉCHEC de l'export Linux.")
    shutil.copy2(os.path.join(ROOT, "assets", "ui", "game_icon.png"), os.path.join(out, "icon.png"))
    with open(os.path.join(out, "LISEZMOI.txt"), "w", encoding="utf-8") as f:
        f.write(f"Arcanes & Lames {version}\n\n"
                "Lancez ArcanesEtLames.x86_64. Choisissez votre pseudo dans Paramètres > Profil.\n"
                "Le jeu se connecte automatiquement au serveur officiel et se met à jour tout seul.\n")
    return out, pck


def export_macos(godot):
    """Application macOS universelle (zip produit par Godot) : renvoie (zip, pck extrait de l'application)."""
    if os.path.isdir(BUILD_MACOS):
        shutil.rmtree(BUILD_MACOS)
    os.makedirs(BUILD_MACOS)
    zpath = os.path.join(BUILD_MACOS, "ArcanesEtLames.zip")
    r = run([godot, "--headless", "--path", ROOT, "--export-release", "macOS", zpath])
    member = f"{MAC_APP}/Contents/Resources/{MAC_APP[:-4]}.pck"
    pck = os.path.join(BUILD_MACOS, "ArcanesEtLames.pck")
    try:
        with zipfile.ZipFile(zpath) as z, z.open(member) as src, open(pck, "wb") as dst:
            shutil.copyfileobj(src, dst)
    except (OSError, KeyError, zipfile.BadZipFile):
        print(r.stdout[-3000:], r.stderr[-3000:])
        sys.exit("ÉCHEC de l'export macOS.")
    return zpath, pck


def make_tar_gz(folder, dest):
    """Archive Linux : garde les droits d'exécution du binaire (un zip fait sous Windows les perd)."""
    import tarfile

    def fix(info):
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mode = 0o755 if info.isdir() or info.name.endswith(".x86_64") else 0o644
        return info
    with tarfile.open(dest, "w:gz", compresslevel=6) as t:
        t.add(folder, "ArcanesEtLames", filter=fix)


SITE_SRC = os.path.join(ROOT, "tools", "site")
# Illustrations et polices du jeu utilisées par la page d'accueil (servies par le serveur sous /site/).
SITE_ASSETS = ["assets/bg/menu.png", "assets/ui/game_icon.png", "assets/fonts/ArcanesPixel.ttf", "assets/fonts/PixelifySans.ttf"] + [
    f"assets/art/{n}.png" for n in ("dragon", "liche", "boule_feu", "paladine", "chevalier", "necromancien", "griffon",
                                    "forge", "archer", "pretresse", "hydre", "meteores", "golem")]


def build_site(latest, dest):
    """Page d'accueil (tools/site/index.html + captures + illustrations du jeu) remplie avec la version publiée."""
    import html
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    os.makedirs(dest)
    for name in os.listdir(SITE_SRC):
        if name != "index.html":
            shutil.copy2(os.path.join(SITE_SRC, name), dest)
    for rel in SITE_ASSETS:
        shutil.copy2(os.path.join(ROOT, rel), dest)
    with open(os.path.join(ROOT, "data", "patchnotes.json"), encoding="utf-8") as f:
        entry = next((e for e in json.load(f) if e.get("version") == latest["version"]), None)
    news = ""
    if entry:
        news = (f'<div class="scroll reveal"><h3>Version {html.escape(entry["version"])} : {html.escape(entry.get("title", ""))}</h3>'
                f'<p class="date">{html.escape(entry.get("date", ""))}</p>')
        for title, items in entry.get("sections", []):
            news += f"<h4>{html.escape(title)}</h4><ul>" + "".join(f"<li>{html.escape(i)}</li>" for i in items) + "</ul>"
        news += "</div>"
    downloads = latest.get("downloads") or {"windows": {"file": latest.get("download", ""), "size": latest.get("download_size", 0)}}
    values = {
        "VERSION": html.escape(latest["version"]),
        "THUMBPRINT": html.escape(str(latest.get("codesign_thumbprint", ""))),
        "INSTALL_PS": html.escape(f'powershell -c "irm {CODESIGN["web_base"]}/install.ps1 | iex"', quote=False),
        "INSTALL_SH": html.escape(f"curl -fsSL {CODESIGN['web_base']}/install.sh | sh", quote=False),
        "NEWS": news,
    }
    for key in ("windows", "macos", "linux"):
        d = downloads.get(key) or {}
        values[f"DL_{key.upper()}"] = html.escape(str(d.get("file", "")))
        values[f"SIZE_{key.upper()}"] = f"{int(d.get('size', 0)) / 1048576:.0f}"
    with open(os.path.join(SITE_SRC, "index.html"), encoding="utf-8") as f:
        page = f.read()
    for k, v in values.items():
        page = page.replace("{{" + k + "}}", v)
    left = re.findall(r"\{\{[A-Z_]+\}\}", page)
    if left:
        sys.exit(f"Page d'accueil : champs non remplis {left}")
    with open(os.path.join(dest, "index.html"), "w", encoding="utf-8", newline="\n") as f:
        f.write(page)


def upload_site(site_dir):
    """Envoie le site dans <updates>/site (dossier temporaire puis bascule, sans page à moitié envoyée)."""
    host, path = DEPLOY.split(":", 1)
    r = run(["ssh", "-o", "BatchMode=yes", host, f"rm -rf {path}/site.tmp"])
    r = run(["scp", "-q", "-r", site_dir, f"{DEPLOY}/site.tmp"])
    if r.returncode != 0:
        sys.exit("ÉCHEC de l'envoi du site : " + r.stderr)
    r = run(["ssh", "-o", "BatchMode=yes", host,
             f"cd {path} && chmod -R a+rX site.tmp && rm -rf site.old && (mv site site.old 2>/dev/null; true) && mv site.tmp site && rm -rf site.old"])
    if r.returncode != 0:
        sys.exit("ÉCHEC de la bascule du site : " + r.stderr)
    print("  page d'accueil mise à jour")


def site_only():
    """--site-only : régénère et envoie la page d'accueil pour la version déjà publiée (sans nouvel export)."""
    host, path = DEPLOY.split(":", 1)
    r = run(["ssh", "-o", "BatchMode=yes", host, f"cat {path}/latest.json"])
    try:
        latest = json.loads(r.stdout)
    except ValueError:
        sys.exit("latest.json introuvable sur le serveur.")
    site = os.path.join(ROOT, "build", "site")
    build_site(latest, site)
    if "--local" not in sys.argv:
        upload_site(site)
    print(f"Page d'accueil ({latest['version']}) : {CODESIGN['web_base']}/")


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
    if "--site-only" in sys.argv:
        return site_only()
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
    print("Export Linux et macOS...")
    linux_dir, linux_pck = export_linux(godot, version)
    mac_zip, mac_pck = export_macos(godot)

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
    # Linux et macOS : un paquet de mise à jour et une archive complète chacun.
    others = {
        "linux": (linux_pck, f"arcanes_{version}_linux.pck", f"ArcanesEtLames_{version}_linux.tar.gz"),
        "macos": (mac_pck, f"arcanes_{version}_macos.pck", f"ArcanesEtLames_{version}_macos.zip"),
    }
    print("Création des archives Linux et macOS")
    make_tar_gz(linux_dir, os.path.join(DIST, others["linux"][2]))
    shutil.copy2(mac_zip, os.path.join(DIST, others["macos"][2]))
    # Paquet identique à celui de Windows (cas habituel) : on réutilise ce dernier au lieu d'une copie.
    platforms, downloads, extra_pcks = {}, {}, []
    main_sha = sha256(os.path.join(DIST, pck_name))
    for key, (src, pname, _) in others.items():
        if sha256(src) == main_sha:
            pname = pck_name
        else:
            shutil.copy2(src, os.path.join(DIST, pname))
            extra_pcks.append(pname)
        platforms[key] = {"file": pname, "sha256": sha256(os.path.join(DIST, pname)),
                          "size": os.path.getsize(os.path.join(DIST, pname))}
        sign_manifest(platforms[key], version)
    for key, name in (("windows", zip_name), ("linux", others["linux"][2]), ("macos", others["macos"][2])):
        downloads[key] = {"file": name, "size": os.path.getsize(os.path.join(DIST, name)),
                          "sha256": sha256(os.path.join(DIST, name))}

    with open(os.path.join(ROOT, "tools", "installer", "install.ps1"), encoding="utf-8") as f:
        installer = f.read().replace("__BASE__", CODESIGN["web_base"]).replace("__THUMBPRINT__", CODESIGN["thumbprint"])
    with open(os.path.join(DIST, "install.ps1"), "w", encoding="utf-8", newline="\r\n") as f:
        f.write(installer)
    with open(os.path.join(ROOT, "tools", "installer", "install.sh"), encoding="utf-8") as f:
        installer = f.read()
    for k, v in {"__BASE__": CODESIGN["web_base"], "__VERSION__": version,
                 "__LINUX_FILE__": downloads["linux"]["file"], "__LINUX_SHA__": downloads["linux"]["sha256"],
                 "__MACOS_FILE__": downloads["macos"]["file"], "__MACOS_SHA__": downloads["macos"]["sha256"]}.items():
        installer = installer.replace(k, v)
    with open(os.path.join(DIST, "install.sh"), "w", encoding="utf-8", newline="\n") as f:
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
        "platforms": platforms,
        "downloads": downloads,
    }
    sign_manifest(latest)
    with open(os.path.join(DIST, "latest.json"), "w", encoding="utf-8") as f:
        json.dump(latest, f, ensure_ascii=False, indent=2)
    print(f"Paquet {latest['size'] / 1048576:.1f} Mo, archive {latest['download_size'] / 1048576:.1f} Mo -> {DIST}")
    build_site(latest, os.path.join(DIST, "site"))

    if local_only:
        print("Mode --local : rien n'a été envoyé sur le serveur.")
        return
    host, path = DEPLOY.split(":", 1)
    print("Envoi sur le serveur", DEPLOY)
    files = [pck_name, zip_name, "install.ps1", "install.sh", "arcanes_codesign.cer", "favicon.ico"] + extra_pcks
    files += [aname for _, _, aname in others.values()]
    r = run(["scp", "-q"] + [os.path.join(DIST, n) for n in files] + [f"{DEPLOY}/"])
    if r.returncode != 0:
        sys.exit("ÉCHEC de l'envoi : " + r.stderr)
    r = run(["scp", "-q", os.path.join(DIST, "latest.json"), f"{DEPLOY}/latest.json.tmp"])
    if r.returncode != 0:
        sys.exit("ÉCHEC de l'envoi de latest.json : " + r.stderr)
    # Bascule atomique puis ménage des anciennes versions. Les paquets précédents vont dans packs/ (non publié) :
    # le serveur s'en sert pour valider les parties commencées avant la mise à jour ; on garde les 5 derniers.
    # Seuls les paquets Windows servent à la validation ; les anciens paquets Linux/macOS sont supprimés.
    keep = " ".join(f"! -name '{n}'" for n in files)
    quoted = " ".join(f"'{n}'" for n in files)
    cleanup = (f"cd {path} && mv -f latest.json.tmp latest.json && chmod 664 latest.json {quoted} && "
               f"find . -maxdepth 1 \\( \\( -name 'arcanes_*_linux.pck' -o -name 'arcanes_*_macos.pck' \\) {keep} \\) -delete && "
               f"mkdir -p packs && find . -maxdepth 1 \\( -name 'arcanes_*.pck' {keep} \\) -exec mv -f {{}} packs/ \\; && "
               f"(ls -1t packs/arcanes_*.pck 2>/dev/null | tail -n +6 | xargs -r rm -f) && "
               f"find . -maxdepth 1 \\( -name 'ArcanesEtLames_*' {keep} \\) -delete && ls -la")
    r = run(["ssh", "-o", "BatchMode=yes", host, cleanup])
    print(r.stdout, r.stderr)
    upload_site(os.path.join(DIST, "site"))
    print(f"Version {version} publiée. Page de téléchargement : {CODESIGN['web_base']}/")


if __name__ == "__main__":
    main()
