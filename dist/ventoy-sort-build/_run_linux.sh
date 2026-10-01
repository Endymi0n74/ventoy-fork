#!/bin/bash
# Lance le build du paquet Linux en process détaché (survit à la session wsl.exe).
B=/mnt/d/Codex/ventoy/dist/ventoy-sort-build
LOG=$B/run-full-linux.log
: > "$LOG"
setsid bash "$B/build_ventoy_sort_linux.sh" < /dev/null >> "$LOG" 2>&1 &
echo "STARTED pid=$! log=$LOG"
sleep 2
tail -5 "$LOG" 2>/dev/null || true
