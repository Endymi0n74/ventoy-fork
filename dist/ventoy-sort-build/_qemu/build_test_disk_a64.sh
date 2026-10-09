#!/bin/bash
# Image disque brute "clé Ventoy" pour le test UEFI ARM64 — géométrie officielle
# (p1 données FAT32 @LBA2048, p2 EFI FAT16 32 Mio), construite depuis le PAQUET
# LINUX ventoy-sort (celui qui contient notre BOOTAA64.EFI patché + signé).
#   usage : build_test_disk_a64.sh [chemin-tar.gz|chemin-zip] [dossier de travail]
#          (défaut : le tar Linux du build ; un zip Windows marche aussi —
#           BOOTAA64.EFI y est notre build depuis l'extension arm64 ; le dossier
#           de travail évite de toucher aux artefacts QEMU existants)
set -euo pipefail
B=/mnt/d/Codex/ventoy/dist/ventoy-sort-build
Q=$B/_qemu
SRC=${1:-$B/ventoy-1.1.19-ventoy-sort-linux.tar.gz}
[ -f "$SRC" ] || { echo "paquet absent : $SRC"; exit 1; }
Q=${2:-$Q}
case "$Q" in /*) ;; *) Q=$(realpath -m "$Q") ;; esac
mkdir -p "$Q/pkga64"
cd "$Q"
case "$SRC" in
    *.zip) unzip -q "$SRC" -d pkga64 ;;
    *)     tar -xzf "$SRC" -C pkga64 ;;
esac
P=$(echo pkga64/ventoy-*)
[ -f "$P/boot/boot.img" ] || { echo "PAQUET_INCOMPLET"; exit 1; }
echo "paquet de test : $P"

# --- efi.img : contenu de la partition 2 (avec NOTRE BOOTAA64.EFI) ---
xz -dc "$P/ventoy/ventoy.disk.img.xz" > efi.img
EFISZ=$(stat -c %s efi.img)
[ "$EFISZ" -eq 33554432 ] || { echo "taille EFI inattendue: $EFISZ"; exit 1; }
mdir -i efi.img ::/EFI/BOOT | grep -i aa64 || true

# --- injection des lignes de test en TÊTE de grub.cfg (mode série) ---
mtype -i efi.img ::/grub/grub.cfg > grub.cfg.orig
printf 'set vtoy_display_mode=serial_console\nset vtoy_serial_param="--unit=0 --speed=115200"\n' > grub.cfg.head
cat grub.cfg.head grub.cfg.orig > grub.cfg.new
mcopy -o -i efi.img grub.cfg.new ::/grub/grub.cfg
echo "grub.cfg préfixé (serial) : $(head -1 grub.cfg.head)"

# --- data.img : partition données FAT32 + ISO factices en DÉSORDRE ---
DATASZ=$((96 * 1024 * 1024))
truncate -s "$DATASZ" data.img
mformat -i data.img -F :: > /dev/null
mmd -i data.img ::/ISO ::/ventoy
mcopy -i data.img "$P/ventoy/version" ::/ventoy/version
for n in zeta 10-apple B aardvark 2-beta M 01-first mango 007 KiLo delta 0c-num; do
    { printf 'FAKE-ISO pour test tri fusion — nom: %s\n' "$n"; head -c 65536 /dev/zero; } > "dummy-$n.iso"
    mcopy -i data.img "dummy-$n.iso" ::/ISO/
done

# --- géométrie officielle + MBR ---
DATAOFF=2048
DATASECT=$((DATASZ / 512))
EFIOFF=$((DATAOFF + DATASECT))
EFISECT=$((EFISZ / 512))
TOTAL=$((EFIOFF + EFISECT))

python3 - "$P/boot/boot.img" mbr.bin "$DATAOFF" "$DATASECT" "$EFIOFF" "$EFISECT" <<'PY'
import struct, sys
boot = bytearray(open(sys.argv[1], 'rb').read())
dataoff, datasect, efioff, efisect = map(int, sys.argv[3:7])
assert len(boot) == 512 and boot[510:512] == b'\x55\xaa', 'boot.img invalide'
def entry(status, typ, start, count):
    chs = b'\xfe\xff\xff'
    return struct.pack('<B3sB3sII', status, chs, typ, chs, start, count)
table = entry(0x80, 0x07, dataoff, datasect) + entry(0x00, 0xef, efioff, efisect) + b'\x00' * 32
mbr = bytes(boot[:446]) + table + b'\x55\xaa'
assert len(mbr) == 512
open(sys.argv[2], 'wb').write(mbr)
print('MBR: p1=données 07 @%d  p2=EFI EF @%d' % (dataoff, efioff))
PY

python3 - "$Q/disk-a64.img" "$TOTAL" mbr.bin data.img efi.img "$DATAOFF" "$EFIOFF" <<'PY'
import sys
out, total = sys.argv[1], int(sys.argv[2])
mbr, data, efi = sys.argv[3:6]
dataoff, efioff = int(sys.argv[6]), int(sys.argv[7])
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
    put(d, data, dataoff)
    put(d, efi, efioff)
print('disk-a64.img = %d octets (%.1f Mio)' % (total * 512, total * 512 / 1048576))
PY

echo "OK: $Q/disk-a64.img"
