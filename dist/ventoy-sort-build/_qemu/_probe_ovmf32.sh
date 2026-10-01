#!/bin/bash
# Extraction du firmware OVMF IA32 (32 bits) dans le harnais, SANS installation système.
# Le paquet Ubuntu "ovmf-ia32" n'existe pas ; on prend le .deb Debian équivalent
# et on l'extrait avec dpkg-deb -x (aucune modification du système).
set -uo pipefail
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
mkdir -p "$Q/ovmf-ia32"
cd "$Q/ovmf-ia32" || exit 1

DEB=ovmf-ia32_2022.11-6+deb12u2_all.deb
URL="https://deb.debian.org/debian/pool/main/e/edk2/$DEB"

echo "== telechargement $DEB =="
if [ -f "$DEB" ]; then
    echo "deja present ($(stat -c %s "$DEB") octets)"
else
    curl -fsSL -o "$DEB" "$URL" && echo "OK $(stat -c %s "$DEB") octets" || { echo "ECHEC_DL"; exit 1; }
fi

echo "== extraction (dpkg-deb -x, système intact) =="
rm -rf root
dpkg-deb -x "$DEB" root && echo OK

echo "== firmwares .fd disponibles =="
find root -name '*.fd' -printf '%s\t%p\n' | sort -k2

echo "== qemu-system-i386 =="
if command -v qemu-system-i386 >/dev/null 2>&1; then
    echo "present : $(command -v qemu-system-i386)"
    qemu-system-i386 -machine help 2>/dev/null | grep -E "^(q35|pc) " || true
else
    echo "ABSENT (le harnais retombera sur qemu-system-x86_64, qui exécute aussi du firmware 32 bits)"
fi
