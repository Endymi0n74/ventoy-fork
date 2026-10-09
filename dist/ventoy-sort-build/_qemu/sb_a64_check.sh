#!/bin/bash
# Boot réel avec Secure Boot ACTIF — UEFI arm64 (AAVMF secboot, MOK = PK/KEK/db).
# Preuves : (1) menu Ventoy atteint, (2) variable SecureBoot lue dans le store de
# run APRÈS le boot (état réel du firmware), (3) contrôle négatif sans MOK -> refus.
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
SERIAL="$Q/serial-aa64-sb.log"

echo "################ arm64 : Secure Boot ACTIF (MOK = PK/KEK/db) ################"
rm -f "$SERIAL"
bash "$Q/run_vm_a64.sh" 5594 sb || exit 1
ok=""
for i in $(seq 1 40); do
    grep -aq "Ventoy 1.1.18-Fork AA64" "$SERIAL" 2>/dev/null && { ok=oui; break; }
    sleep 5
done
echo "menu affiché : ${ok:-NON}"
if [ "${ok:-}" = oui ]; then
    echo "--- ordre des entrées (première occurrence de chaque nom) ---"
    tr -d '\033' < "$SERIAL" | sed 's/\[[0-9;]*[A-Za-z]//g' \
      | grep -ao 'dummy-[A-Za-z0-9-]*\.iso' | awk '!seen[$0]++'
    echo "--- erreurs de vérification (aucune attendue) ---"
    grep -a -c -i "Security Violation\|Access Denied" "$SERIAL" || echo 0
fi
pkill -f "[q]emu-system-aarch64" 2>/dev/null || true
sleep 1
echo "--- variable SecureBoot après boot (store de run, lu par virt-fw-vars) ---"
virt-fw-vars -i "$Q/vars-a64-sb-run.fd" -p 2>/dev/null | grep -E 'SecureBoot|SetupMode|VendorKeys' \
    || echo "(variables runtime absentes du dump)"

echo
echo "################ arm64 : contrôle négatif (clés MS, MOK ABSENT) ################"
rm -f "$Q/serial-aa64-sb-nomok.log"
bash "$Q/run_vm_a64.sh" 5594 sb-nomok || exit 1
n=0
for i in $(seq 1 30); do
    grep -aq "GNU GRUB" "$Q/serial-aa64-sb-nomok.log" 2>/dev/null && { n=1; break; }
    sleep 5
done
if [ "$n" = 1 ]; then
    echo "GRUB a démarré : SECURE BOOT NON APPLIQUÉ (anomalie !)"
else
    echo "aucun GRUB : le firmware a refusé le chargeur (SECURE BOOT APPLIQUÉ)"
    grep -a -o "Security Violation\|Access Denied" "$Q/serial-aa64-sb-nomok.log" | sort -u | head -3
fi
pkill -f "[q]emu-system-aarch64" 2>/dev/null || true
echo "VM arm64 arrêtées"
