#!/usr/bin/env bash
# Exercise the PowerShell supervisor using a fake wsl.exe implemented in
# PowerShell. No WSL VM or Ventoy build is started.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD_DIR=$ROOT/dist/ventoy-sort-build
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"

cat > "$T/bin/fake_wsl.ps1" <<'FAKE_WSL'
$ErrorActionPreference = 'Stop'
if ($args[3] -eq 'wslpath') {
    Write-Output $args[5]
    exit 0
}
if ($args[3] -eq 'bash') {
    $status = $args[5]
    if ($env:FAKE_WSL_CAPTURE) {
        Set-Content -LiteralPath $env:FAKE_WSL_CAPTURE -Value $env:WSLENV
    }
    if ($env:FAKE_WSL_MODE -eq 'interrupt-once' -and -not (Test-Path $env:FAKE_WSL_STATE)) {
        Set-Content -LiteralPath $env:FAKE_WSL_STATE -Value 'interrupted'
        Set-Content -LiteralPath $status -Value 'started'
        exit 0
    }
    if ($env:FAKE_WSL_MODE -eq 'failure') {
        Set-Content -LiteralPath $status -Value 'done:7'
        exit 7
    }
    Set-Content -LiteralPath $status -Value 'done:0'
    exit 0
}
Write-Error "unexpected fake wsl.exe args: $args"
exit 2
FAKE_WSL

export TEMP="$(cygpath -w "$T")"
export WSL_RETRY_DELAY_SECONDS=0
export WSL_BUILD_RETRIES=1
export FAKE_WSL_STATE="$(cygpath -w "$T/interrupted-once")"
export VENTOY_WSL_EXE="$(cygpath -w "$T/bin/fake_wsl.ps1")"

run_ps() {
    export FAKE_WSL_MODE=$1
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass \
        -File "$(cygpath -w "$BUILD_DIR/run_wsl_build.ps1")" -Kind windows
}

run_cmd() {
    local launcher_win
    launcher_win=$(cygpath -w "$BUILD_DIR/$1")
    export FAKE_WSL_MODE=$2
    cmd.exe //d //c "call $launcher_win"
}

echo '=== Windows launchers: both .cmd entry points reach the supervisor ==='
run_cmd build_ventoy_sort_windows.cmd success
run_cmd build_ventoy_sort_linux.cmd success

echo '=== success: one attempt, exit 0 ==='
run_ps success

echo '=== Secure Boot key names are forwarded through WSLENV ==='
export VENTOY_SORT_MOK_KEY='test-private-key'
export VENTOY_SORT_MOK_CRT='test-public-cert'
export WSLENV='KEEP_THIS/u'
export FAKE_WSL_CAPTURE="$(cygpath -w "$T/wsl-env-capture")"
run_ps success
capture=$(tr -d '\r' < "$T/wsl-env-capture")
grep -q 'VENTOY_SORT_MOK_KEY/u' <<< "$capture"
grep -q 'VENTOY_SORT_MOK_CRT/u' <<< "$capture"
grep -q 'KEEP_THIS/u' <<< "$capture"
unset VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT FAKE_WSL_CAPTURE WSLENV

echo '=== normal build failure: exit 7, no retry ==='
if run_ps failure; then
    echo 'FAIL: normal build failure was reported as success' >&2
    exit 1
else
    rc=$?
    [[ $rc -eq 7 ]] || { echo "FAIL: expected exit 7, got $rc" >&2; exit 1; }
fi

rm -f "$FAKE_WSL_STATE"
echo '=== VM interruption: retry once, then succeed ==='
run_ps interrupt-once
test -f "$FAKE_WSL_STATE"

echo 'PASS: supervisor behavior'
