#!/bin/bash
# Compare les sorties sauvegardées (_run5/, baseline figée) et les fichiers
# courants (dernière exécution du script) — vérification de reproductibilité :
#   1. lancer build_ventoy_sort_windows.sh
#   2. cp -a ventoy-*-windows.zip _run5/  (et artefacts si souhaité)
#   3. relancer le script, puis exécuter ce script : tout doit être IDENTIQUE
set -u
B=/mnt/d/Codex/ventoy/dist/ventoy-sort-build
cd "$B" || exit 1
SNAP=${1:-_run5}

echo "=== 1. artefacts bruts ==="
for pair in \
    "work/core.img:$SNAP/core.img" \
    "work/grubx64_real.efi:$SNAP/grubx64_real.efi" \
    "work/grubia32_real.efi:$SNAP/grubia32_real.efi" \
    "work/BOOTAA64.EFI:$SNAP/BOOTAA64.EFI" \
    "pkg/ventoy-1.1.18-ventoy-sort/Ventoy2Disk.exe:$SNAP/Ventoy2Disk.exe" \
    "pkg/ventoy-1.1.18-ventoy-sort/altexe/Ventoy2Disk_X64.exe:$SNAP/Ventoy2Disk_X64.exe" \
    "pkg/ventoy-1.1.18-ventoy-sort/boot/core.img.xz:$SNAP/core.img.xz" \
    "pkg/ventoy-1.1.18-ventoy-sort/ventoy/ventoy.disk.img.xz:$SNAP/ventoy.disk.img.xz" \
    "pkg/ventoy-1.1.18-ventoy-sort/ventoy/version:$SNAP/version" \
    "SHA256SUMS-ventoy-sort-windows.txt:$SNAP/SHA256SUMS-ventoy-sort-windows.txt" \
    "PROCEDURE-SECURE-BOOT.md:$SNAP/PROCEDURE-SECURE-BOOT.md" \
    "ventoy-sort-MOK.cer:$SNAP/ventoy-sort-MOK.cer" ; do
    a=${pair%%:*}; b=${pair##*:}
    ha=$(sha256sum "$a" | cut -c1-16); hb=$(sha256sum "$b" | cut -c1-16)
    if [ "$ha" = "$hb" ]; then echo "IDENTIQUE  $a ($ha)"; else echo "DIFFERE    $a  $ha vs $hb"; fi
done

echo
echo "=== 2. extraction + diff -r des deux zips ==="
rm -rf _cmp/z3 _cmp/z4; mkdir -p _cmp/z3 _cmp/z4
unzip -q $SNAP/ventoy-1.1.18-ventoy-sort-windows.zip -d _cmp/z3
unzip -q ventoy-1.1.18-ventoy-sort-windows.zip -d _cmp/z4
diff -r _cmp/z3 _cmp/z4 && echo "contenus extraits identiques"

echo
echo "=== 3. comparaison entrée par entrée (zipfile) ==="
python3 - $SNAP/ventoy-1.1.18-ventoy-sort-windows.zip ventoy-1.1.18-ventoy-sort-windows.zip <<'PY'
import zipfile, sys
z3 = zipfile.ZipFile(sys.argv[1]); z4 = zipfile.ZipFile(sys.argv[2])
n3, n4 = z3.namelist(), z4.namelist()
print('même ordre:', n3 == n4, '| nb:', len(n3), len(n4))
for n in n3:
    i3, i4 = z3.getinfo(n), z4.getinfo(n)
    d = []
    if i3.CRC != i4.CRC: d.append(f'CRC {i3.CRC:08x}->{i4.CRC:08x}')
    if i3.file_size != i4.file_size: d.append(f'taille {i3.file_size}->{i4.file_size}')
    if i3.date_time != i4.date_time: d.append(f'date {i3.date_time}->{i4.date_time}')
    if i3.external_attr != i4.external_attr: d.append(f'attr {i3.external_attr:#x}->{i4.external_attr:#x}')
    if i3.extra != i4.extra: d.append(f'extra {i3.extra.hex()}->{i4.extra.hex()}')
    if i3.header_offset != i4.header_offset: d.append(f'offset {i3.header_offset}->{i4.header_offset}')
    if d:
        print('DIFF', n, '|', '; '.join(d))
PY

echo
echo "=== 4. mtimes des répertoires du paquet ==="
find pkg/ventoy-1.1.18-ventoy-sort -type d -printf '%T@ %p\n' | sort | head -20
