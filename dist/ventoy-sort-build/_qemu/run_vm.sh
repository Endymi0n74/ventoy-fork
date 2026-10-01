#!/bin/bash
# Lance QEMU en arrière-plan (setsid, survit à la session wsl.exe) avec moniteur TCP.
#   usage : run_vm.sh <bios|uefi|uefi32> <port-moniteur>
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
MODE=${1:-bios}
PORT=${2:-5591}
cd "$Q" || exit 1
pkill -f "qemu-system-(i386|x86_64) .*disk.img" 2>/dev/null || true
sleep 1

COMMON=(-machine q35 -m 512
        -drive "file=$Q/disk.img,format=raw,if=ide"
        -nic none -display none -vga std -no-reboot
        -serial "file:$Q/serial-$MODE.log"
        -monitor "tcp:127.0.0.1:$PORT,server=on,wait=off")

BIN=qemu-system-x86_64
FW=()
if [ "$MODE" = uefi ]; then
    cp -f /usr/share/OVMF/OVMF_VARS_4M.fd "$Q/vars.fd"
    FW=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd
        -drive if=pflash,format=raw,file="$Q/vars.fd")
elif [ "$MODE" = uefi-sb ]; then
    # Secure Boot réel : firmware secboot + store enrôlé par _enroll.sh
    # (copie fraîche à chaque lancement : le firmware écrit dans la copie)
    [ -f "$Q/sbtest/vars-x64-sb.fd" ] || { echo "store enrôlé absent — lancez _enroll.sh"; exit 1; }
    cp -f "$Q/sbtest/vars-x64-sb.fd" "$Q/vars-x64-sb-run.fd"
    FW=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
        -drive if=pflash,format=raw,file="$Q/vars-x64-sb-run.fd")
elif [ "$MODE" = uefi-sb-nomok ]; then
    # contrôle négatif : clés Microsoft seules, MOK absent → le menu ne doit pas apparaître
    cp -f /usr/share/OVMF/OVMF_VARS_4M.ms.fd "$Q/vars-x64-nomok.fd"
    FW=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
        -drive if=pflash,format=raw,file="$Q/vars-x64-nomok.fd")
elif [ "$MODE" = uefi-sb-dbx ]; then
    # test de révocation : store enrôlé + haché du chargeur ajouté à dbx
    # (construit par _dbx_check.sh) → le firmware doit refuser malgré la signature valide
    [ -f "$Q/sbtest/vars-x64-dbx.fd" ] || { echo "store dbx absent — lancez _dbx_check.sh"; exit 1; }
    cp -f "$Q/sbtest/vars-x64-dbx.fd" "$Q/vars-x64-dbx-run.fd"
    FW=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
        -drive if=pflash,format=raw,file="$Q/vars-x64-dbx-run.fd")
elif [ "$MODE" = uefi32 ]; then
    # firmware UEFI 32 bits : deb Debian ovmf-ia32 extrait par _probe_ovmf32.sh
    D=$Q/ovmf-ia32/root/usr/share/OVMF
    [ -f "$D/OVMF32_CODE_4M.secboot.fd" ] || { echo "firmware IA32 absent — lancez d'abord _probe_ovmf32.sh"; exit 1; }
    CODE=$D/OVMF32_CODE_4M.secboot.fd
    cp -f "$D/OVMF32_VARS_4M.fd" "$Q/vars32.fd"
    FW=(-drive if=pflash,format=raw,readonly=on,file="$CODE"
        -drive if=pflash,format=raw,file="$Q/vars32.fd")
    command -v qemu-system-i386 >/dev/null 2>&1 && BIN=qemu-system-i386
fi

setsid "$BIN" "${FW[@]}" "${COMMON[@]}" > "$Q/qemu-$MODE.log" 2>&1 < /dev/null &
echo "STARTED $MODE bin=$BIN moniteur=127.0.0.1:$PORT pid=$!"
