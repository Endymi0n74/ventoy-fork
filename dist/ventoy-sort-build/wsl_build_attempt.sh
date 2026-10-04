#!/usr/bin/env bash
# One WSL attempt called by run_wsl_build.ps1. The Windows-visible status file
# is initialized before the long-running build and changed only after it exits.
# If WSL shuts down, "started" remains and the Windows supervisor retries.
set -u
status_file=$1
build_script=$2
shift 2

status_tmp="${status_file}.tmp.$$"
printf '%s\n' 'started' > "$status_tmp"
mv -f -- "$status_tmp" "$status_file"
rc=0
bash "$build_script" "$@" || rc=$?
printf 'done:%s\n' "$rc" > "$status_tmp"
mv -f -- "$status_tmp" "$status_file"
exit "$rc"
