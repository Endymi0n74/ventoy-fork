#!/bin/bash
# Envoie une commande brute au moniteur QEMU.
#   usage : mon.sh <port> <commande...>
set -eu
PORT=$1
shift
python3 - "$PORT" "$*" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
cmd = sys.argv[2]
s = socket.create_connection(('127.0.0.1', port), timeout=5)
s.settimeout(3)
try:
    s.recv(4096)
except socket.timeout:
    pass
s.sendall((cmd + '\n').encode())
time.sleep(0.5)
try:
    out = s.recv(65536)
except socket.timeout:
    out = b''
s.close()
print(out.decode(errors='replace').strip() or '(ok)')
PY
