#!/bin/bash
# Boot réel avec Secure Boot ACTIF — UEFI x64, paquet Windows (disk.img, mode serial).
# Preuves attendues : ligne « Secure Boot Enabled », GRUB -> menu trié.
# + contrôle négatif (clés MS sans notre MOK) : le menu ne doit PAS apparaître.
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
SERIAL="$Q/serial-uefi-sb.log"

echo "################ x64 : Secure Boot ACTIF (MOK enrôlé) ################"
rm -f "$SERIAL"
bash "$Q/run_vm.sh" uefi-sb 5592 || exit 1
ok=""
for i in $(seq 1 25); do
    grep -aqE "Ventoy [0-9][0-9.]*-ventoy-sort UEFI" "$SERIAL" 2>/dev/null && { ok=oui; break; }
    sleep 4
done
echo "menu affiché : ${ok:-NON}"
echo "--- ligne d'état Secure Boot ---"
grep -a -o "Secure Boot Enabled\|Secure Boot Disabled" "$SERIAL" | head -1
echo "--- erreurs de vérification (aucune attendue) ---"
grep -a -c -i "Security Violation\|verification.*fail\|Access Denied" "$SERIAL" || echo 0
if [ "${ok:-}" = oui ]; then
    tr -d '\033' < "$SERIAL" | sed 's/\[[0-9;]*[A-Za-z]//g' \
      | grep -ao 'dummy-[A-Za-z0-9-]*\.iso' | awk '!seen[$0]++'
fi
pkill -f "[q]emu-system-(i386|x86_64)" 2>/dev/null || true
sleep 1

echo
echo "################ x64 : contrôle négatif (clés MS, MOK ABSENT) ################"
rm -f "$Q/serial-uefi-sb-nomok.log"
bash "$Q/run_vm.sh" uefi-sb-nomok 5592 || exit 1
n=0
for i in $(seq 1 25); do
    grep -aq "GNU GRUB" "$Q/serial-uefi-sb-nomok.log" 2>/dev/null && { n=1; break; }
    sleep 4
done
if [ "$n" = 1 ]; then
    echo "GRUB a démarré : SECURE BOOT NON APPLIQUÉ (anomalie !)"
else
    echo "aucun GRUB : le firmware a refusé le chargeur non autorisé (SECURE BOOT APPLIQUÉ)"
    grep -a -o "Secure Boot Enabled\|Security Violation\|Access Denied" "$Q/serial-uefi-sb-nomok.log" | sort -u | head -4
fi
pkill -f "[q]emu-system-(i386|x86_64)" 2>/dev/null || true
echo "VM x64 arrêtées"
