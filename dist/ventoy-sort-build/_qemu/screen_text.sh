#!/bin/bash
# Lit le tampon texte VGA (0xb8000) via le moniteur QEMU et affiche l'écran80x25.
#   usage : screen_text.sh <port>
set -eu
python3 - "$1" <<'PY'
import re, socket, sys, time
port = int(sys.argv[1])
s = socket.create_connection(('127.0.0.1', port), timeout=5)
s.settimeout(4)
buf = b''
try:
    buf += s.recv(4096)
except socket.timeout:
    pass
s.sendall(b'xp /4000xb 0xb8000\n')
deadline = time.time() + 8
while time.time() < deadline:
    try:
        chunk = s.recv(65536)
    except socket.timeout:
        break
    if not chunk:
        break
    buf += chunk
    if buf.count(b'0x') >= 4000:
        break
s.close()
text = buf.decode(errors='replace')
vals = []
for m in re.finditer(r'^([0-9a-f]{8,16}):\s*((?:0x[0-9a-f]{2}[\s\r]+)+)', text, re.M):
    vals.extend(int(x, 16) for x in m.group(2).split())
if len(vals) < 4000:
    print('!! lecture courte: %d octets' % len(vals))
chars = vals[:4000]
print('=' * 80)
for row in range(25):
    line = bytes(chars[row * 160:row * 160 + 160:2]).decode('cp437', errors='replace')
    print(line.rstrip())
print('=' * 80)
PY
