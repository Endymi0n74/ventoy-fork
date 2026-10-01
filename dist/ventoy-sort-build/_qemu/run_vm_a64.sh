#!/bin/bash
# Lance la VM UEFI ARM64 (qemu-system-aarch64, machine virt, firmware AAVMF).
#   usage : run_vm_a64.sh [port-moniteur] [plain|sb|sb-nomok]   (défaut 5594 plain)
#   sb       : firmware AAVMF secboot + store enrôlé par _enroll.sh (Secure Boot réel)
#   sb-nomok : contrôle négatif — clés Microsoft seules, MOK absent (refus attendu)
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
PORT=${1:-5594}
MODE=${2:-plain}
cd "$Q" || exit 1
pkill -f "[q]emu-system-aarch64" 2>/dev/null || true
sleep 1

if [ "$MODE" = sb ]; then
    [ -f "$Q/sbtest/vars-a64-sb.fd" ] || { echo "store enrôlé absent — lancez _enroll.sh"; exit 1; }
    cp -f "$Q/sbtest/vars-a64-sb.fd" "$Q/vars-a64-sb-run.fd"
    CODE=/usr/share/AAVMF/AAVMF_CODE.ms.fd
    VARS=$Q/vars-a64-sb-run.fd
    SERIAL=serial-aa64-sb.log
elif [ "$MODE" = sb-nomok ]; then
    # contrôle négatif : clés Microsoft seules (MOK absent) -> refus attendu
    cp -f /usr/share/AAVMF/AAVMF_VARS.ms.fd "$Q/vars-a64-nomok.fd"
    CODE=/usr/share/AAVMF/AAVMF_CODE.ms.fd
    VARS=$Q/vars-a64-nomok.fd
    SERIAL=serial-aa64-sb-nomok.log
else
    cp -f /usr/share/AAVMF/AAVMF_VARS.fd "$Q/vars-a64.fd"
    CODE=/usr/share/AAVMF/AAVMF_CODE.fd
    VARS=$Q/vars-a64.fd
    SERIAL=serial-aa64.log
fi

setsid qemu-system-aarch64 \
    -machine virt -cpu cortex-a57 -m 512 \
    -drive if=pflash,format=raw,readonly=on,file=$CODE \
    -drive if=pflash,format=raw,file=$VARS \
    -drive "file=$Q/disk-a64.img,format=raw,if=none,id=hd0" \
    -device virtio-blk-device,drive=hd0 \
    -device qemu-xhci -device usb-kbd \
    -nic none -display none -no-reboot \
    -serial "file:$Q/$SERIAL" \
    -monitor "tcp:127.0.0.1:$PORT,server=on,wait=off" \
    > "$Q/qemu-aa64.log" 2>&1 < /dev/null &
echo "STARTED aa64 moniteur=127.0.0.1:$PORT pid=$!"
