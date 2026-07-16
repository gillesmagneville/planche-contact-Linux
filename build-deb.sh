#!/bin/bash
set -euo pipefail

# ====================== CONFIGURATION ======================
PACKAGE_NAME="planche-contact"
MAINTAINER="Gilles MAGNEVILLE <gilles@magneville.fr>"
DESCRIPTION="Outil de génération de planches contact photographiques"
URL="https://github.com/gillesmagneville/planche-contact"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$HOME/deb-build/build"
VERSION_FILE="$PROJECT_DIR/VERSION"
# ===========================================================

show_help() {
    cat << EOF
Usage: ./build-deb.sh [version] [options]

Script de construction du paquet Debian pour Planche Contact.

OPTIONS :
  [version]       Force une version spécifique (ex: 1.0.3 ou 1.1.0)
                  Si aucune version n'est fournie, utilise celle du fichier VERSION.

  --clean         Nettoie le dossier de build et supprime tous les paquets .deb
                  existants dans le répertoire courant.

  --help, -h      Affiche cette aide.

EXEMPLES :
  ./build-deb.sh                  # Construit avec la version du fichier VERSION
  ./build-deb.sh 1.0.3            # Force la construction en version 1.0.3
  ./build-deb.sh --clean          # Nettoie le build et supprime les .deb
  ./build-deb.sh 1.1.0 --clean    # (non recommandé) Nettoie puis construit

EOF
}

CLEAN=false
NEW_VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean) CLEAN=true; shift ;;
        --help|-h) show_help; exit 0 ;;
        *) NEW_VERSION="$1"; shift ;;
    esac
done

# === Mode nettoyage ===
if [ "$CLEAN" = true ]; then
    echo ">>> Nettoyage du dossier de build..."
    rm -rf "$BUILD_DIR"

    echo ">>> Suppression des paquets .deb existants..."
    rm -f ./*.deb

    echo ">>> Nettoyage terminé."
    exit 0
fi

# Vérification de fpm
if ! command -v fpm &> /dev/null; then
    echo "Erreur: fpm n'est pas installé."
    echo "Installe-le avec : gem install --user-install fpm"
    exit 1
fi

# Détermination de la version
if [ -f "$VERSION_FILE" ]; then
    VERSION=$(cat "$VERSION_FILE")
else
    VERSION="1.0.0"
fi

if [ -n "$NEW_VERSION" ]; then
    VERSION="$NEW_VERSION"
fi

DEB_FILE="./${PACKAGE_NAME}_${VERSION}_amd64.deb"

echo "========================================"
echo " Construction du paquet $PACKAGE_NAME v$VERSION"
echo "========================================"

# Supprime l'ancien paquet avant reconstruction
if [ -f "$DEB_FILE" ]; then
    echo ">>> Suppression de l'ancien paquet..."
    rm -f "$DEB_FILE"
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo ">>> Création de l'arborescence..."
mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/share/$PACKAGE_NAME"
mkdir -p "$BUILD_DIR/usr/share/applications"
mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/128x128/apps"
mkdir -p "$BUILD_DIR/DEBIAN"

echo ">>> Création du virtualenv..."
python3 -m venv --system-site-packages "$BUILD_DIR/usr/share/$PACKAGE_NAME/venv"

echo ">>> Installation des dépendances Python..."
source "$BUILD_DIR/usr/share/$PACKAGE_NAME/venv/bin/activate"
pip install --upgrade pip --quiet
pip install Pillow reportlab --quiet
deactivate

echo ">>> Copie des fichiers du projet..."
cp "$PROJECT_DIR/planche-contact-gtk.py" "$BUILD_DIR/usr/share/$PACKAGE_NAME/"
cp -r "$PROJECT_DIR/portfolio" "$BUILD_DIR/usr/share/$PACKAGE_NAME/"

mkdir -p "$BUILD_DIR/usr/share/$PACKAGE_NAME/docs"
[ -f "$PROJECT_DIR/docs/planche-contact-manual.html" ] && cp "$PROJECT_DIR/docs/planche-contact-manual.html" "$BUILD_DIR/usr/share/$PACKAGE_NAME/docs/"
[ -f "$PROJECT_DIR/LICENSE" ] && cp "$PROJECT_DIR/LICENSE" "$BUILD_DIR/usr/share/$PACKAGE_NAME/"

if [ -f "$PROJECT_DIR/planche-contact.png" ]; then
    cp "$PROJECT_DIR/planche-contact.png" "$BUILD_DIR/usr/share/icons/hicolor/128x128/apps/planche-contact.png"
fi

echo ">>> Création des scripts d'exécution..."
cat > "$BUILD_DIR/usr/bin/planche-contact-gtk" << 'EOF'
#!/bin/bash
exec /usr/share/planche-contact/venv/bin/python3 /usr/share/planche-contact/planche-contact-gtk.py "$@"
EOF
chmod +x "$BUILD_DIR/usr/bin/planche-contact-gtk"

cat > "$BUILD_DIR/usr/bin/portfolio" << 'EOF'
#!/bin/bash
exec /usr/share/planche-contact/venv/bin/python3 /usr/share/planche-contact/portfolio/portfolio.py "$@"
EOF
chmod +x "$BUILD_DIR/usr/bin/portfolio"

echo ">>> Création du fichier .desktop..."
cat > "$BUILD_DIR/usr/share/applications/planche-contact.desktop" << EOF
[Desktop Entry]
Name=Planche Contact
Comment=Outil de génération de planches contact photographiques
Exec=planche-contact-gtk
Icon=planche-contact
Terminal=false
Type=Application
Categories=Graphics;Photography;
EOF

echo ">>> Copie des scripts Debian..."
cp debian/postinst "$BUILD_DIR/DEBIAN/"
cp debian/postrm "$BUILD_DIR/DEBIAN/"
chmod 755 "$BUILD_DIR/DEBIAN/postinst" "$BUILD_DIR/DEBIAN/postrm"

echo ">>> Création du paquet .deb..."
fpm -s dir -t deb \
    -n "$PACKAGE_NAME" \
    -v "$VERSION" \
    --license "GPL-3.0" \
    --maintainer "$MAINTAINER" \
    --description "$DESCRIPTION" \
    --url "$URL" \
    --depends python3 \
    --depends python3-gi \
    --depends gir1.2-gtk-4.0 \
    --depends libgtk-4-1 \
    -C "$BUILD_DIR" \
    usr/ DEBIAN/

echo "$VERSION" > "$VERSION_FILE"

echo ""
echo "✅ Paquet créé avec succès :"
echo "   $DEB_FILE"
