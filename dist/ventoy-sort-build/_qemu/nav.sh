#!/bin/bash
# Envoie N « sendkey down » au moniteur QEMU puis lit l'écran texte.
#   usage : nav.sh <port> <nb_down>
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
PORT=$1
N=${2:-1}
i=0
while [ "$i" -lt "$N" ]; do
    bash "$Q/mon.sh" "$PORT" "sendkey down" > /dev/null
    i=$((i + 1))
done
sleep 1
bash "$Q/screen_text.sh" "$PORT"
