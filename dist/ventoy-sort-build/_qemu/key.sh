#!/bin/bash
# Envoie une touche au moniteur QEMU, attend, lit l'écran texte.
#   usage : key.sh <port> <touche> [attente_s]
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
PORT=$1
KEY=$2
WAIT=${3:-3}
bash "$Q/mon.sh" "$PORT" "sendkey $KEY" > /dev/null
sleep "$WAIT"
bash "$Q/screen_text.sh" "$PORT"
