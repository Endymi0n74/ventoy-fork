#!/bin/bash
# Lance le build en process détaché pour qu'il survive à la fin de la session wsl.exe.
B=/mnt/d/Codex/ventoy/dist/ventoy-sort-build
LOG=$B/run-full.log
: > "$LOG"
setsid bash "$B/build_ventoy_sort_windows.sh" < /dev/null >> "$LOG" 2>&1 &
echo "STARTED pid=$! log=$LOG"
sleep 2
tail -5 "$LOG" 2>/dev/null || true
