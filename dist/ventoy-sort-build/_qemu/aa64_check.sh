#!/bin/bash
# Validation finale UEFI arm64 : boot AAVMF -> menu Ventoy -> navigation -> arrêt.
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
rm -f "$Q/serial-aa64.log"
bash "$Q/run_vm_a64.sh" 5594 || exit 1

# attente du menu GRUB (TCG lent : jusqu'à 300 s)
menu=""
for i in $(seq 1 30); do
    if tr -d '\033' < "$Q/serial-aa64.log" 2>/dev/null | grep -aq "Ventoy 1.1.18-Fork AA64"; then
        menu="oui (après ~$((i * 10)) s)"
        break
    fi
    sleep 10
done
echo "menu Ventoy affiché : ${menu:-NON (timeout 300 s)}"

if [ -n "$menu" ]; then
    # navigation : 2x flèche bas via le moniteur QEMU (le '*' doit passer de
    # dummy-007.iso à dummy-0c-num.iso), preuve d'interactivité
    python3 - <<'PY'
import socket, time
s = socket.create_connection(('127.0.0.1', 5594), timeout=5)
s.settimeout(2)
try: s.recv(4096)
except socket.timeout: pass
for _ in range(2):
    s.sendall(b'sendkey down\n')
    time.sleep(0.6)
s.close()
PY
    sleep 3
    echo "--- ordre des entrées (première occurrence de chaque nom) ---"
    tr -d '\033' < "$Q/serial-aa64.log" | sed 's/\[[0-9;]*[A-Za-z]//g' \
      | grep -ao 'dummy-[A-Za-z0-9-]*\.iso' | awk '!seen[$0]++'
    echo "--- la sélection (ligne avec '*') après navigation ---"
    tr -d '\033' < "$Q/serial-aa64.log" | sed 's/\[[0-9;]*[A-Za-z]//g' \
      | grep -a '\*' | tail -3
    echo "--- erreurs / mismatch ---"
    echo "mismatch : $(grep -ac 'mismatch' "$Q/serial-aa64.log" || true)"
    echo "error    : $(grep -ac -i 'error' "$Q/serial-aa64.log" || true)"
fi

pkill -f "[q]emu-system-aarch64" 2>/dev/null || true
echo "VM aa64 arrêtée"
