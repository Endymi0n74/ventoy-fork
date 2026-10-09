#!/usr/bin/env bash
# =============================================================================
# test_mok_import.sh - test bench for the MOK key import of the package builds
#
# dist/ventoy-sort-build/build_ventoy_sort_{windows,linux}.sh normally mint
# their Secure Boot key once and keep it on disk. A CI runner has no key, so
# ensure_sb_key() grew a branch that imports VENTOY_SORT_MOK_KEY / _CRT (and
# optionally _CER) from the environment. That branch is the one tested here:
# it is what keeps a package built in CI signed with the SAME key as one built
# locally, which is what makes PROCEDURE-SECURE-BOOT.md apply to both.
#
# Nothing outside a throwaway mktemp directory is written, and the real key of
# the fork (secureboot/ventoy-sort-MOK.cer) is checked for being untouched.
#
# Cases:
#   1. KEY+CRT imported, CER derived from the CRT   -> must succeed
#   2. KEY+CRT+CER imported (CER base64-encoded)    -> must succeed
#   3. KEY and CRT that are not a pair              -> must fail
#   4. CRT that is not a PEM certificate            -> must fail
#   5. no environment, no files on disk             -> must fall back to
#                                                      generating a fresh key
#   6. sbsign/sbverify round-trip with the imported key -> must verify
#      (skipped when no built PE is available, i.e. on a fresh checkout)
#
# Usage: bash dist/tests/test_mok_import.sh
# Exit 0 when every case behaves as expected, 1 otherwise.
# =============================================================================
set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
B=$(cd -- "$SCRIPT_DIR/../ventoy-sort-build" && pwd)
SCRIPT=$B/build_ventoy_sort_windows.sh
REAL_SB=$B/secureboot/ventoy-sort-MOK.cer     # pinned before B is reassigned
PE=$(ls "$B"/pkg/ventoy-*-Fork/Ventoy2Disk.exe 2>/dev/null | head -1)

FAIL=0
skip_count=0
ok()   { printf '  [ok]   %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf '  [skip] %s\n' "$1"; skip_count=$((skip_count + 1)); }

for tool in openssl base64 cmp sed sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool"; exit 1; }
done
HAVE_SBSIGN=0
command -v sbsign >/dev/null 2>&1 && command -v sbverify >/dev/null 2>&1 && HAVE_SBSIGN=1
[ -f "$SCRIPT" ] || { echo "build script not found: $SCRIPT"; exit 1; }
REAL_EXISTS=0
if [ -f "$REAL_SB" ]; then REAL_EXISTS=1; REAL_FPM=$(sha256sum "$REAL_SB" | cut -d' ' -f1); fi
# "the fork's own key is untouched" only means something where that key exists:
# a fresh clone has none (secureboot/ is not tracked), and the CI runner is
# exactly that case.
[ -f "$REAL_SB" ] || { echo "note: no local fork key ($REAL_SB) - fresh clone"; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
LIB=$T/lib.sh
# Sanity check: the script must end with its `main` call, otherwise stripping
# the last line would leave an invocation behind and sourcing would build.
tail -1 "$SCRIPT" | grep -qx 'main' \
    || { echo "$SCRIPT does not end with its main call - not stripping"; exit 1; }
sed '$ d' "$SCRIPT" > "$LIB"
tail -1 "$LIB" | grep -qx 'main' \
    && { echo "the main call survived the strip - not sourcing"; exit 1; }

# Sources the build script, then points everything it touches at $T.
load_lib() {
    # shellcheck disable=SC1090
    . "$LIB"
    # The script imposes `set -Eeuo pipefail` while sourcing; drop errexit so
    # the bench survives the cases that are supposed to fail.
    set +E; set +e; set +u
    SB_DIR=$T/secureboot
    SB_KEY=$SB_DIR/ventoy-sort-mok.key
    SB_CRT=$SB_DIR/ventoy-sort-mok.crt
    SB_CER=$SB_DIR/ventoy-sort-MOK.cer
    SB_LOG=$T/log-sign.txt
    SB_FTIME_C=$SB_DIR/fixedtime.c
    SB_FTIME_SO=$SB_DIR/fixedtime.so
    B=$T                       # the copy published next to the zip goes to $T too
    rm -rf "$SB_DIR"; mkdir -p "$SB_DIR"
    unset VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT VENTOY_SORT_MOK_CER 2>/dev/null || true
}

# Reference keys of our own, never the fork's.
openssl req -newkey rsa:2048 -nodes -sha256 -keyout "$T/a.key" -x509 -new -days 2 \
    -subj "/CN=test key A/" -out "$T/a.crt" 2>/dev/null
openssl req -newkey rsa:2048 -nodes -sha256 -keyout "$T/b.key" -x509 -new -days 2 \
    -subj "/CN=test key B/" -out "$T/b.crt" 2>/dev/null
echo "not-a-certificate" > "$T/garbage.crt"
CER_B64=$(openssl x509 -in "$T/a.crt" -outform DER | base64 -w0)

echo "=== 1. KEY+CRT imported, CER derived from the CRT ==="
load_lib
export VENTOY_SORT_MOK_KEY="$(cat "$T/a.key")"
export VENTOY_SORT_MOK_CRT="$(cat "$T/a.crt")"
if ( ensure_sb_key ) >/dev/null 2>&1; then
    fp=$(openssl x509 -in "$SB_CRT" -noout -fingerprint -sha256 | cut -d= -f2)
    if [ -f "$SB_KEY" ] && [ -f "$SB_CRT" ] && [ -f "$SB_CER" ] && [ -f "$T/ventoy-sort-MOK.cer" ]; then
        ok "key, certificate and .cer written, fingerprint $fp"
        cmp -s "$SB_CER" "$T/ventoy-sort-MOK.cer" \
            && ok "ventoy-sort-MOK.cer is a copy of SB_CER" \
            || bad "ventoy-sort-MOK.cer differs from SB_CER"
    else
        bad "a file is missing after the import"
    fi
    if [ "$REAL_EXISTS" = 1 ]; then
        [ "$(sha256sum "$REAL_SB" | cut -d' ' -f1)" = "$REAL_FPM" ] \
            && ok "the fork's own key is untouched" || bad "the fork's own key was MODIFIED"
    else
        skip "no local fork key to protect (fresh clone)"
    fi
else
    bad "the import failed"
fi
unset VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT

echo "=== 2. KEY+CRT+CER imported (CER base64) ==="
load_lib
export VENTOY_SORT_MOK_KEY="$(cat "$T/a.key")"
export VENTOY_SORT_MOK_CRT="$(cat "$T/a.crt")"
export VENTOY_SORT_MOK_CER="$CER_B64"
if ( ensure_sb_key ) >/dev/null 2>&1; then
    cmp -s "$SB_CER" <(openssl x509 -in "$T/a.crt" -outform DER) \
        && ok "the supplied CER was accepted and matches the CRT" \
        || bad "the supplied CER differs from the CRT"
else
    bad "importing an explicit CER failed"
fi
unset VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT VENTOY_SORT_MOK_CER

echo "=== 3. KEY and CRT from different origins ==="
load_lib
export VENTOY_SORT_MOK_KEY="$(cat "$T/a.key")"
export VENTOY_SORT_MOK_CRT="$(cat "$T/b.crt")"
if out=$( (ensure_sb_key) 2>&1 ); then
    bad "a mismatched key/certificate pair was accepted"
else
    printf '%s' "$out" | grep -q "ne forment pas une paire" \
        && ok "rejected: mismatched key/certificate pair detected" \
        || bad "failed, but with an unexpected message: $(printf '%s' "$out" | tail -1)"
fi
unset VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT

echo "=== 4. CRT that is not a certificate ==="
load_lib
export VENTOY_SORT_MOK_KEY="$(cat "$T/a.key")"
export VENTOY_SORT_MOK_CRT="$(cat "$T/garbage.crt")"
if out=$( (ensure_sb_key) 2>&1 ); then
    bad "an unreadable CRT was accepted"
else
    printf '%s' "$out" | grep -q "illisible" \
        && ok "rejected with an explicit message" \
        || bad "failed, but with an unusable message: $(printf '%s' "$out" | tail -1)"
fi
unset VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT

echo "=== 5. no environment: falls back to generating a key ==="
load_lib
if ( ensure_sb_key ) >/dev/null 2>&1; then
    [ -f "$SB_KEY" ] && [ -f "$SB_CRT" ] \
        && ok "a key was generated, the original behaviour is preserved" \
        || bad "no key was generated"
else
    bad "key generation failed"
fi

echo "=== 6. sbsign/sbverify round-trip with the imported key ==="
if [ -z "$PE" ]; then
    skip "no built PE to sign (run after a package build for full coverage)"
elif [ "$HAVE_SBSIGN" != 1 ]; then
    skip "sbsigntool not installed"
else
    load_lib
    export VENTOY_SORT_MOK_KEY="$(cat "$T/a.key")"
    export VENTOY_SORT_MOK_CRT="$(cat "$T/a.crt")"
    if ( ensure_sb_key ) >/dev/null 2>&1; then
        cp -f "$PE" "$T/f.efi"
        if sbsign --key "$SB_KEY" --cert "$SB_CRT" --output "$T/f-signed.efi" "$T/f.efi" >/dev/null 2>&1 \
           && sbverify --cert "$SB_CRT" "$T/f-signed.efi" >/dev/null 2>&1; then
            ok "signs and verifies with the imported pair"
        else
            bad "sbsign/sbverify failed with the imported pair"
        fi
    else
        bad "import failed, cannot round-trip"
    fi
    unset VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT
fi

echo
if [ "$FAIL" -gt 0 ]; then
    echo "FAILED: $FAIL case(s)"
    exit 1
fi
echo "PASSED (0 failures, $skip_count skipped)"
exit 0