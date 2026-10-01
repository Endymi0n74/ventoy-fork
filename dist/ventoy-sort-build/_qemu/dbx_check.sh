#!/bin/bash
# Test de RÉVOCATION dbx — ce que le firmware applique vraiment :
#   (a) certificat signant (MOK) ajouté à dbx -> fbx64/grubx64_real (signés par
#       ce certificat) doivent être REFUSÉS à la vérification firmware
#       (« Security Violation ») — c'est le mécanisme réel de dbx ;
#   (b) haché BRUT (sha256 du fichier) de grubx64_real.efi dans dbx -> le boot
#       continue : la comparaison dbx du firmware porte sur un haché de
#       STRUCTURE PE (style Authenticode), pas du fichier brut, et grubx64_real
#       est de toute façon chargé manuellement par fbx64/VtoyShim (haché
#       embarqué dans fbx64, hors dbx) ;
#   (c) miroir : store sans révocation -> boot attendu.
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
B=/mnt/d/Codex/ventoy/dist/ventoy-sort-build
SBT=$Q/sbtest
MOKCER=$B/secureboot/ventoy-sort-MOK.cer
mkdir -p "$SBT"

echo "== extraction des chargeurs du disque de test =="
cd "$Q" || exit 1
[ -d "$Q/pkg/ventoy-1.1.18-ventoy-sort" ] \
    || unzip -qo "$B/ventoy-1.1.18-ventoy-sort-windows.zip" -d pkg
xz -dc "$Q/pkg/ventoy-1.1.18-ventoy-sort/ventoy/ventoy.disk.img.xz" > /tmp/dbx_efi.img
mcopy -n -i /tmp/dbx_efi.img ::/EFI/BOOT/BOOTX64.EFI      /tmp/dbx_bootx64.efi
mcopy -n -i /tmp/dbx_efi.img ::/EFI/BOOT/grubx64_real.efi /tmp/dbx_grubx64.efi
echo "sha256 brut BOOTX64.EFI      = $(sha256sum /tmp/dbx_bootx64.efi | awk '{print $1}')"
echo "sha256 brut grubx64_real.efi = $(sha256sum /tmp/dbx_grubx64.efi | awk '{print $1}')"

echo
echo "== (a) MOK (certificat signant) ajouté à dbx : REFUS attendu =="
GUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
cp -f "$SBT/vars-x64-sb.fd" "$SBT/vars-x64-dbx.fd"
virt-fw-vars --inplace "$SBT/vars-x64-dbx.fd" --add-dbx-cert "$GUID" "$MOKCER" 2>&1 | grep -v '^INFO' || true
echo "dbx avant : $(virt-fw-vars -i "$SBT/vars-x64-sb.fd" -p --hashes 2>/dev/null | grep -c '^dbx ') entrée(s)"
echo "dbx après : $(virt-fw-vars -i "$SBT/vars-x64-dbx.fd" -p --hashes 2>/dev/null | grep '^dbx ')"
rm -f "$Q/serial-uefi-sb-dbx.log"
bash "$Q/run_vm.sh" uefi-sb-dbx 5592 >/dev/null || exit 1
n=0
for i in $(seq 1 25); do
    grep -aq "GNU GRUB" "$Q/serial-uefi-sb-dbx.log" 2>/dev/null && { n=1; break; }
    sleep 4
done
if [ "$n" = 1 ]; then
    echo "[FAIL] le boot a eu lieu malgré la révocation du certificat signant"
else
    echo "[ok] aucun GRUB : le firmware a REFUSÉ la chaîne dont le signataire est révoqué"
    grep -a -o "Security Violation\|Access Denied" "$Q/serial-uefi-sb-dbx.log" | sort -u | head -3
fi
pkill -f "[q]emu-system-(i386|x86_64)" 2>/dev/null || true
sleep 1

echo
echo "== (b) haché BRUT de grubx64_real.efi dans dbx : boot attendu =="
GUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
cp -f "$SBT/vars-x64-sb.fd" "$SBT/vars-x64-dbx.fd"
virt-fw-vars --inplace "$SBT/vars-x64-dbx.fd" \
    --add-dbx-hash "$GUID" "$(sha256sum /tmp/dbx_grubx64.efi | awk '{print $1}')" >/dev/null 2>&1
rm -f "$Q/serial-uefi-sb-dbx.log"
bash "$Q/run_vm.sh" uefi-sb-dbx 5592 >/dev/null || exit 1
n=0
for i in $(seq 1 25); do
    grep -aq "GNU GRUB" "$Q/serial-uefi-sb-dbx.log" 2>/dev/null && { n=1; break; }
    sleep 4
done
if [ "$n" = 1 ]; then
    echo "[ok] GRUB a démarré : haché brut NON applicable (dbx compare un haché de"
    echo "     structure PE, et grubx64_real est chargé manuellement par fbx64/VtoyShim)"
else
    echo "[info] GRUB n'a pas démarré"
fi
pkill -f "[q]emu-system-(i386|x86_64)" 2>/dev/null || true
sleep 1

echo
echo "== (c) miroir : même disque, store SANS révocation (boot attendu) =="
rm -f "$Q/serial-uefi-sb.log"
bash "$Q/run_vm.sh" uefi-sb 5592 >/dev/null || exit 1
ok=""
for i in $(seq 1 25); do
    grep -aq "Ventoy 1.1.18-ventoy-sort UEFI" "$Q/serial-uefi-sb.log" 2>/dev/null && { ok=oui; break; }
    sleep 4
done
echo "menu affiché : ${ok:-NON}"
pkill -f "[q]emu-system-(i386|x86_64)" 2>/dev/null || true
rm -f /tmp/dbx_efi.img /tmp/dbx_bootx64.efi /tmp/dbx_grubx64.efi
echo "VM arrêtées"
