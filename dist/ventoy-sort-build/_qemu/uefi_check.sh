#!/bin/bash
# Contrôle final UEFI : relance la VM, capture le menu en PNG, prouve la réception
# des touches (2x flèche bas sur le port série), puis éteint les VM.
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
rm -f "$Q/serial-uefi.log"
bash "$Q/run_vm.sh" uefi 5592 || exit 1
sleep 34
bash "$Q/shot.sh" 5592 "$Q/uefi_menu.png" "UEFI OVMF — menu Ventoy 1.1.18-ventoy-sort"
bash "$Q/mon.sh" 5592 "sendkey down" > /dev/null
bash "$Q/mon.sh" 5592 "sendkey down" > /dev/null
sleep 2
echo "=== queue de la série après 2x flèche bas ==="
tail -c 1400 "$Q/serial-uefi.log" | tr -d '\033' | sed 's/\[[0-9;]*[A-Za-z]//g' | tail -8
echo
pkill -f "[q]emu-system-(i386|x86_64)"
echo "VM eteintes"
