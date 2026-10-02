#!/bin/bash
# Image disque brute "clé Ventoy" à partir du ZIP livré — géométrie OFFICIELLE
# (prouvée par la table de partitions emboutie dans boot.img officiel) :
#   p1 @LBA2048  type 07 : partition DONNÉES (FAT32 neuf, /ISO + /ventoy)
#   p2 juste après type EF : partition EFI (ventoy.disk.img = FAT16 VTOYEFI 32 Mio)
#   prefix GRUB (,2)/grub -> grub.cfg sur p2, d'où l'ordre.
# Usage : build_test_disk.sh <cli|serial>
#   cli   -> prepends "set vtoy_display_mode=CLI"        (menu texte VGA, lisible via 0xb8000)
#   serial -> prepends serial_console + param            (menu sur port série, lisible via -serial file)
set -euo pipefail
B=/mnt/d/Codex/ventoy/dist/ventoy-sort-build
Q=$B/_qemu
# ZIP : le paquet Windows à tester. Par défaut le plus récent ventoy-*-windows.zip
# du dossier de build (ZIP=... pour en choisir un explicitement).
Z=${ZIP:-$(ls -t "$B"/ventoy-*-ventoy-sort-windows.zip | head -1)}
echo "paquet testé : $(basename "$Z")"
MODE=${1:-cli}

rm -rf "$Q/pkg"
mkdir -p "$Q"
cd "$Q"
unzip -q "$Z" -d pkg
# racine INTERNE du zip (« ventoy-<version> », sans le suffixe -windows du nom de fichier)
P=$Q/pkg/$(unzip -Z1 "$Z" | head -1 | cut -d/ -f1)
echo "racine du zip  : $(basename "$P")"
[ -f "$P/Ventoy2Disk.exe" ] && [ -f "$P/boot/boot.img" ] || { echo "ZIP_INCOMPLET"; exit 1; }

# --- efi.img : image officielle FAT16 "VTOYEFI" (contenu de la partition 2) ---
xz -dc "$P/ventoy/ventoy.disk.img.xz" > efi.img
EFISZ=$(stat -c %s efi.img)
[ "$EFISZ" -eq 33554432 ] || { echo "taille EFI inattendue: $EFISZ"; exit 1; }

# --- injection des lignes de test en TÊTE de grub.cfg (harnais : le menu lui-même
#     et son tri restent strictement ceux du zip livré) ---
mtype -i efi.img ::/grub/grub.cfg > grub.cfg.orig
case "$MODE" in
    cli)    printf 'set vtoy_display_mode=CLI\n' > grub.cfg.head ;;
    serial) printf 'set vtoy_display_mode=serial_console\nset vtoy_serial_param="--unit=0 --speed=115200"\n' > grub.cfg.head ;;
    *) echo "mode inconnu: $MODE (cli|serial)"; exit 1 ;;
esac
cat grub.cfg.head grub.cfg.orig > grub.cfg.new
mcopy -o -i efi.img grub.cfg.new ::/grub/grub.cfg
echo "grub.cfg préfixé ($MODE) : $(head -1 grub.cfg.head)"

# --- data.img : partition données FAT32 + ISO factices en ordre DÉSORDRE ---
DATASZ=$((96 * 1024 * 1024))
truncate -s "$DATASZ" data.img
mformat -i data.img -F :: > /dev/null
mmd -i data.img ::/ISO ::/ventoy
mcopy -i data.img "$P/ventoy/version" ::/ventoy/version
# ordre d'écriture volontairement non trié : l'ordre affiché prouvera le tri
# >=32768 o exigé par ventoy (VTOY_FILT_MIN_FILE_SIZE) pour être listé
for n in zeta 10-apple B aardvark 2-beta M 01-first mango 007 KiLo delta 0c-num; do
    { printf 'FAKE-ISO pour test tri fusion — nom: %s\n' "$n"; head -c 65536 /dev/zero; } > "dummy-$n.iso"
    mcopy -i data.img "dummy-$n.iso" ::/ISO/
done

# --- géométrie officielle ---
DATAOFF=2048                                   # 1 Mio
DATASECT=$((DATASZ / 512))
EFIOFF=$((DATAOFF + DATASECT))                 # contigu, comme le template officiel
EFISECT=$((EFISZ / 512))
TOTAL=$((EFIOFF + EFISECT))

# --- MBR : code boot.img + table officielle (p1 data 07 active, p2 EFI EF) ---
xz -dc "$P/boot/core.img.xz" > core.img
CORESZ=$(stat -c %s core.img)
[ "$CORESZ" -le $((2047 * 512)) ] || { echo "core.img TROP GRAND: $CORESZ"; exit 1; }

python3 - "$P/boot/boot.img" mbr.bin "$DATAOFF" "$DATASECT" "$EFIOFF" "$EFISECT" <<'PY'
import struct, sys
boot = bytearray(open(sys.argv[1], 'rb').read())
dataoff, datasect, efioff, efisect = map(int, sys.argv[3:7])
assert len(boot) == 512 and boot[510:512] == b'\x55\xaa', 'boot.img invalide'
def entry(status, typ, start, count):
    chs = b'\xfe\xff\xff'
    return struct.pack('<B3sB3sII', status, chs, typ, chs, start, count)
# template officiel : p1=données(07, active), p2=EFI(EF)
table = entry(0x80, 0x07, dataoff, datasect) + entry(0x00, 0xef, efioff, efisect) + b'\x00' * 32
mbr = bytes(boot[:446]) + table + b'\x55\xaa'
assert len(mbr) == 512
open(sys.argv[2], 'wb').write(mbr)
print('MBR: p1=données 07 @%d..%d  p2=EFI EF @%d..%d (secteurs)'
      % (dataoff, dataoff + datasect - 1, efioff, efioff + efisect - 1))
PY

# --- assemblage ---
python3 - "$Q/disk.img" "$TOTAL" mbr.bin core.img data.img efi.img "$DATAOFF" "$EFIOFF" <<'PY'
import sys
out, total = sys.argv[1], int(sys.argv[2])
mbr, core, data, efi = sys.argv[3:7]
dataoff, efioff = int(sys.argv[7]), int(sys.argv[8])
def put(dst, path, off):
    with open(path, 'rb') as s:
        dst.seek(off * 512)
        while True:
            b = s.read(1 << 20)
            if not b:
                break
            dst.write(b)
with open(out, 'wb') as d:
    d.truncate(total * 512)
    put(d, mbr, 0)
    put(d, core, 1)
    put(d, data, dataoff)
    put(d, efi, efioff)
print('disk.img = %d octets (%.1f Mio)' % (total * 512, total * 512 / 1048576))
PY

# --- inventaires ---
{
    echo "== p1 (données) /ISO =="
    mdir -i data.img ::/ISO || true
    echo "== p1 (données) /ventoy =="
    mdir -i data.img ::/ventoy || true
    echo "== p2 (EFI) racine =="
    mdir -i efi.img :: || true
    echo "== p2 (EFI) /EFI/BOOT =="
    mdir -i efi.img ::/EFI/BOOT || true
    echo "== tête de grub.cfg =="
    head -3 grub.cfg.new
} > inventaire.txt
echo "OK: $Q/disk.img (mode=$MODE)"
