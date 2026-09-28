#!/bin/sh
# Installateur d'Arcanes & Lames pour Linux (x86_64) et macOS (Intel et Apple Silicon), sans droits administrateur.
# Utilisation (Terminal) :
#   curl -fsSL __BASE__/install.sh | sh
# Télécharge le jeu en HTTPS, vérifie son empreinte SHA-256 et l'installe :
#   Linux : ~/.local/share/ArcanesEtLames + raccourci dans le menu des applications
#   macOS : ~/Applications/Arcanes & Lames.app (sans passer par l'avertissement Gatekeeper)
# Les mises à jour suivantes se font automatiquement depuis le jeu.
# Généré par tools/publish_update.py pour la version __VERSION__.
set -e

BASE='__BASE__'
VERSION='__VERSION__'

say() { printf '  %s\n' "$1"; }
fail() { printf '\n  ERREUR : %s\n  Vous pouvez aussi télécharger le jeu depuis %s\n\n' "$1" "$BASE" >&2; exit 1; }

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
    else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

fetch() {
    if command -v curl >/dev/null 2>&1; then curl -fL --progress-bar -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then wget -q --show-progress -O "$2" "$1"
    else fail "curl ou wget est nécessaire."; fi
}

printf '\n  ARCANES & LAMES - installation\n\n'
case "$(uname -s)" in
    Linux)
        [ "$(uname -m)" = "x86_64" ] || fail "seuls les processeurs x86_64 sont pris en charge sous Linux."
        FILE='__LINUX_FILE__'; SHA='__LINUX_SHA__'; OS=linux ;;
    Darwin)
        FILE='__MACOS_FILE__'; SHA='__MACOS_SHA__'; OS=macos ;;
    *) fail "système non pris en charge : $(uname -s). Sous Windows, utilisez la commande PowerShell." ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
say "Version $VERSION - téléchargement..."
fetch "$BASE/download/$FILE" "$TMP/$FILE" || fail "téléchargement impossible."
[ "$(sha256_of "$TMP/$FILE")" = "$SHA" ] || fail "fichier corrompu (empreinte SHA-256 inattendue)."

if [ "$OS" = linux ]; then
    DEST="${ARCANES_INSTALL_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/ArcanesEtLames}"
    pkill -x ArcanesEtLames.x86_64 2>/dev/null || true
    mkdir -p "$DEST"
    tar -xzf "$TMP/$FILE" -C "$TMP"
    cp -Rf "$TMP/ArcanesEtLames/." "$DEST/"
    chmod +x "$DEST/ArcanesEtLames.x86_64"
    if [ -z "$ARCANES_NO_SHORTCUTS" ]; then
        APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
        mkdir -p "$APPS"
        cat > "$APPS/arcanes-et-lames.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Arcanes & Lames
Comment=Jeu de cartes médiéval-fantastique en pixel art
Exec="$DEST/ArcanesEtLames.x86_64"
Path=$DEST
Icon=$DEST/icon.png
Terminal=false
Categories=Game;CardGame;
EOF
        # Désinstallation : supprime le dossier et le raccourci (les réglages restent dans ~/.local/share/godot).
        printf '#!/bin/sh\nrm -f "%s"\nrm -rf "%s"\n' "$APPS/arcanes-et-lames.desktop" "$DEST" > "$DEST/desinstaller.sh"
        chmod +x "$DEST/desinstaller.sh"
        command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" >/dev/null 2>&1 || true
    fi
    printf '\n'
    say "Installé dans $DEST"
    [ -n "$ARCANES_NO_SHORTCUTS" ] && exit 0
    say "Raccourci ajouté au menu des applications. Lancement du jeu..."
    (cd "$DEST" && nohup ./ArcanesEtLames.x86_64 >/dev/null 2>&1 &)
else
    DEST="${ARCANES_INSTALL_DIR:-$HOME/Applications}"
    APP="$DEST/Arcanes & Lames.app"
    pkill -x 'Arcanes & Lames' 2>/dev/null || true
    mkdir -p "$DEST"
    ditto -x -k "$TMP/$FILE" "$TMP/x"
    rm -rf "$APP"
    ditto "$TMP/x/Arcanes & Lames.app" "$APP"
    xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
    printf '\n'
    say "Installé dans $APP"
    [ -n "$ARCANES_NO_SHORTCUTS" ] && exit 0
    say "Lancement du jeu... (il apparaît aussi dans le Launchpad)"
    open "$APP"
fi
printf '\n'
