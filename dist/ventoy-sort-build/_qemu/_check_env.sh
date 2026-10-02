#!/bin/bash
# Vérifie l'outillage QEMU / OVMF nécessaire aux tests d'amorçage.
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
echo "=== binaires qemu ==="
for b in qemu-system-x86_64 qemu-system-i386 qemu-system-aarch64; do
    p=$(command -v "$b" 2>/dev/null)
    printf '  %-22s %s\n' "$b" "${p:-ABSENT}"
done

echo "=== firmwares OVMF x64 ==="
ls -la /usr/share/OVMF/ 2>/dev/null | grep -E '4M|_CODE|_VARS' || echo "  repertoire absent"

echo "=== virt-fw-vars (enrôlement MOK) ==="
p=$(command -v virt-fw-vars 2>/dev/null)
printf '  %s\n' "${p:-ABSENT}"
[ -n "$p" ] && virt-fw-vars --version 2>&1 | head -2

echo "=== mtools ==="
for t in mcopy mdir mtype mformat; do
    printf '  %-10s %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo ABSENT)"
done

echo "=== stores déjà enrôlés (sbtest/) ==="
ls -la "$Q/sbtest/" 2>/dev/null || echo "  sbtest/ absent -> _enroll.sh à lancer"

echo "=== paquets windows disponibles ==="
ls -la /mnt/d/Codex/ventoy/dist/ventoy-sort-build/ventoy-*ventoy-sort*.zip 2>/dev/null

echo "=== VM déjà en marche ? ==="
pgrep -a -f "qemu-system" || echo "  aucune"