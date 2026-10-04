#!/usr/bin/env bash
# Verifie par RENDU REEL hors ecran que la version de la fenetre Qt tient dans
# son libelle, et produit une capture PNG.
#
# Le test statique dist/tests/test_gui_version_layout.py compare des largeurs
# calculees a partir des sources ; celui-ci compile la GUI (qmake + make),
# appelle le vrai Ventoy2DiskWindow::SetVersionLabel() sur la vraie forme .ui
# et mesure le texte reellement rendu.
#
#   dist/tests/test_gui_render.sh [version] [sortie.png]
#
# Sortie : 0 = le texte tient dans les deux libelles
#          1 = debordement detecte
#          2 = test non executable (Qt5 absent, compilation impossible)

set -u

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$HERE/../.." && pwd)

VER=${1:-1.1.20-ventoy-sort}
OUT=${2:-$HERE/out/ventoy2disk-render.png}

die() { printf 'test_gui_render: %s\n' "$1" >&2; exit "${2:-1}"; }

QMAKE=
for c in qmake-qt5 qmake-qt5.15 qmake; do
    if command -v "$c" >/dev/null 2>&1; then QMAKE=$c; break; fi
done
if [ -z "$QMAKE" ]; then
    printf 'test_gui_render: ignore (aucune toolchain Qt5).\n'
    printf '  apt-get install -y qtbase5-dev qtbase5-dev-tools qt5-qmake g++ pkg-config\n'
    exit 2
fi
for c in make g++ pkg-config; do
    command -v "$c" >/dev/null 2>&1 || { printf 'test_gui_render: ignore (%s absent).\n' "$c"; exit 2; }
done
pkg-config --exists Qt5Widgets 2>/dev/null || { printf 'test_gui_render: ignore (Qt5Widgets.pc absent).\n'; exit 2; }

SRC=$REPO/LinuxGUI/Ventoy2Disk
[ -f "$SRC/QT/Ventoy2Disk.pro" ] || die "$SRC/QT/Ventoy2Disk.pro introuvable"
[ -f "$HERE/gui_probe.cpp" ] || die "$HERE/gui_probe.cpp introuvable"

if [ -n "${GUI_RENDER_BUILD_DIR:-}" ]; then
    BUILD=$GUI_RENDER_BUILD_DIR
    OWNED=0
else
    BUILD=$(mktemp -d "${TMPDIR:-/tmp}/ventoy-gui-render.XXXXXX")
    OWNED=1
fi
cleanup() { if [ "$OWNED" = 1 ]; then rm -rf "$BUILD"; fi; return 0; }
trap cleanup EXIT

printf 'test_gui_render: construction de la GUI dans %s\n' "$BUILD"
mkdir -p "$BUILD"
cp -r "$SRC/." "$BUILD/"

# qmake doit etre lance depuis la racine du projet : les chemins de SOURCES
# (Core/, Lib/, Web/) y sont relatifs, ceux de QT/ ne le sont pas.
(
    cd "$BUILD" || exit 1
    "$QMAKE" QT/Ventoy2Disk.pro || exit 1
    make -j"$(nproc 2>/dev/null || echo 1)" || exit 1
) > "$BUILD/build.log" 2>&1 || die "qmake/make a echoue - voir $BUILD/build.log" 2

OBJS=()
for o in "$BUILD"/*.o; do
    case $(basename "$o") in
        main.o|gui_probe.o) continue ;;
    esac
    OBJS+=("$o")
done
[ "${#OBJS[@]}" -gt 0 ] || die "aucun objet compile - voir $BUILD/build.log" 2

g++ -std=c++11 -fPIC \
    $(pkg-config --cflags Qt5Widgets) \
    -I"$BUILD" -I"$BUILD/QT" -I"$BUILD/Core" -I"$BUILD/Include" -I"$BUILD/Web" \
    "$HERE/gui_probe.cpp" \
    "${OBJS[@]}" \
    $(pkg-config --libs Qt5Widgets) -lGL -lpthread \
    -o "$BUILD/gui_probe" || die "edition de liens de gui_probe impossible" 2

mkdir -p "$(dirname -- "$OUT")"
printf 'test_gui_render: version rendue : %s\n' "$VER"
QT_QPA_PLATFORM=offscreen "$BUILD/gui_probe" "$VER" "$OUT"
rc=$?
printf 'test_gui_render: capture dans %s\n' "$OUT"
exit $rc
