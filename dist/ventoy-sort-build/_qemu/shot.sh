#!/bin/bash
# Capture l'écran QEMU (screendump via le moniteur TCP) puis :
#   PPM -> PNG (pur python) -> screen.html (PNG en base64) pour visualisation.
#   usage : shot.sh <port> <sortie.png> <légende>
set -eu
PORT=$1
OUT=$2
CAPTION=${3:-}
python3 - "$PORT" "$OUT" "$CAPTION" <<'PY'
import base64, socket, struct, sys, time, zlib
port, out, caption = int(sys.argv[1]), sys.argv[2], sys.argv[3]

def mon(cmd, wait=0.6):
    s = socket.create_connection(('127.0.0.1', port), timeout=5)
    s.settimeout(3)
    try:
        s.recv(4096)
    except socket.timeout:
        pass
    s.sendall((cmd + '\n').encode())
    time.sleep(wait)
    try:
        s.recv(65536)
    except socket.timeout:
        pass
    s.close()

ppm = out + '.ppm'
try:
    import os
    os.remove(ppm)
except FileNotFoundError:
    pass
mon('screendump ' + ppm, wait=1.2)
data = open(ppm, 'rb').read()
parts = data.split(None, 4)
assert parts[0] == b'P6', 'pas un PPM: %r' % parts[0]
w, h, maxv = int(parts[1]), int(parts[2]), int(parts[3])
raw = parts[4][:w * h * 3]
rows = b''.join(b'\x00' + raw[y * w * 3:(y + 1) * w * 3] for y in range(h))

def chunk(tag, payload):
    return (struct.pack('>I', len(payload)) + tag + payload
            + struct.pack('>I', zlib.crc32(tag + payload) & 0xffffffff))

png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(rows, 6))
       + chunk(b'IEND', b''))
open(out, 'wb').write(png)

html = ('<!doctype html><meta charset="utf-8"><body style="margin:0;background:#111">'
        '<div style="color:#0f0;font:14px monospace;padding:6px">%s</div>'
        '<img src="data:image/png;base64,%s" style="width:100%%">'
        '</body>') % (caption.replace('<', '&lt;'), base64.b64encode(png).decode())
open('/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu/screen.html', 'w').write(html)
print('PNG %dx%d -> %s (%d o)' % (w, h, out, len(png)))
PY
