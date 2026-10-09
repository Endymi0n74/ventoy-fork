#!/bin/bash
# Validation croisée UEFI x64 + ia32 : navigation, captures, recherche de mismatch.
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
cd "$Q" || exit 1

echo "################ UEFI IA32 (VM déjà lancée, port 5593) ################"
bash "$Q/mon.sh" 5593 "sendkey down" > /dev/null
bash "$Q/mon.sh" 5593 "sendkey down" > /dev/null
sleep 2
echo "--- queue série après 2x flèche bas (le * doit être passé sur dummy-0c-num) ---"
tail -c 1200 "$Q/serial-uefi32.log" | tr -d '\033' | sed 's/\[[0-9;]*[A-Za-z]//g' | tr -s ' ' | grep -a '\*' | tail -3
bash "$Q/shot.sh" 5593 "$Q/uefi32_menu.png" "UEFI OVMF ia32 — menu Ventoy 1.1.18-Fork IA32"
echo "--- mismatch / erreurs dans la série ia32 ---"
grep -a -c "mismatch" "$Q/serial-uefi32.log" || echo "0 occurrence de 'mismatch'"
grep -a -c -i "error" "$Q/serial-uefi32.log" || echo "0 occurrence de 'error'"

echo
echo "################ UEFI X64 (relance express, port 5592) ################"
rm -f "$Q/serial-uefi.log"
bash "$Q/run_vm.sh" uefi 5592
sleep 40
echo "--- titre du menu x64 ---"
grep -a -o "Ventoy 1.1.18-Fork UEFI" "$Q/serial-uefi.log" | head -1
bash "$Q/mon.sh" 5592 "sendkey down" > /dev/null
bash "$Q/mon.sh" 5592 "sendkey down" > /dev/null
sleep 2
echo "--- premieres entrees x64 (ordre attendu : 007, 01-first, 0c-num, 10-apple, 2-beta) ---"
tr -d '\033' < "$Q/serial-uefi.log" | sed 's/\[[0-9;]*[A-Za-z]//g' | grep -a -o "dummy-[A-Za-z0-9-]*\.iso" | awk '!seen[$0]++' | head -12
bash "$Q/shot.sh" 5592 "$Q/uefi_menu_x64.png" "UEFI OVMF x64 — menu Ventoy 1.1.18-Fork UEFI"
echo "--- mismatch / erreurs dans la série x64 ---"
grep -a -c "mismatch" "$Q/serial-uefi.log" || echo "0 occurrence de 'mismatch'"
grep -a -c -i "error" "$Q/serial-uefi.log" || echo "0 occurrence de 'error'"

echo
echo "################ arrêt des VM ################"
pkill -f "[q]emu-system-(i386|x86_64)"
sleep 1
pgrep -a -f "qemu-system-(i386|x86_64)" || echo "VM eteintes"
ls -la "$Q"/uefi32_menu.png "$Q"/uefi_menu_x64.png 2>/dev/null
