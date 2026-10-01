#!/bin/bash
# Test boot UEFI 32 bits (OVMF IA32, qemu-system-i386) du paquet ventoy-sort.
# Le disque disk.img (mode serial) est déjà construit par build_test_disk.sh serial.
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
rm -f "$Q/serial-uefi32.log" "$Q/qemu-uefi32.log"
bash "$Q/run_vm.sh" uefi32 5593 || exit 1
sleep 40
echo "=== qemu-uefi32.log ==="
cat "$Q/qemu-uefi32.log" 2>/dev/null
echo
echo "=== serial-uefi32.log (début) ==="
head -c 2000 "$Q/serial-uefi32.log" 2>/dev/null | tr -d '\033' || echo "(vide)"
echo
echo "=== serial-uefi32.log (fin) ==="
tail -c 2500 "$Q/serial-uefi32.log" 2>/dev/null | tr -d '\033' | sed 's/\[[0-9;]*[A-Za-z]//g' | tail -25 || echo "(vide)"
echo
echo "=== VM encore vivante ? ==="
pgrep -a -f "qemu-system-(i386|x86_64) .*uefi32" || pgrep -a qemu-system-i386 || echo "(aucun process)"
