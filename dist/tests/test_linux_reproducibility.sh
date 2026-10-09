#!/usr/bin/env bash
# =============================================================================
# test_linux_reproducibility.sh - end-to-end reproducibility bench for the
#                                 Linux package of the ventoy-sort fork.
#
# What it proves, and why it cannot be replaced by running the build twice in
# the same directory: two builds at the SAME location were already byte
# identical before this bench existed, while two builds in two DIFFERENT
# directories were not. The package used to embed the absolute path of the
# build tree (through __FILE__, DWARF and the FILE symbol of the .S files), so
# its content depended on where the checkout happened to live. Only an
# isolated-root comparison catches that class of bug.
#
# The bench therefore:
#   1. prepares two throwaway roots whose paths have DIFFERENT LENGTHS
#      (a same-length pair could hide padding effects);
#   2. runs the real build script once per root, in parallel, with the same
#      inputs and the same Secure Boot key;
#   3. compares the two packages byte for byte, and names the entries that
#      differ when they do;
#   4. asserts that no build path survived inside boot/core.img.xz - the
#      regression this bench exists for.
#
# Nothing is written inside the repository: build_ventoy_sort_linux.sh writes
# into its own directory, so it is COPIED into each root together with
# GRUB2/MOD_SRC (the overlay it compiles) and the Secure Boot key. The real
# build folder, and the published package, are never touched.
#
# Cost: two full GRUB builds (4 platforms each). About 6 min wall clock on a
# 12-core machine, roughly twice that if the two builds cannot run in
# parallel. REPRO_DRY_RUN=1 checks the prerequisites and prints the plan
# without building anything.
#
# Usage:  bash dist/tests/test_linux_reproducibility.sh
#
# Environment:
#   REPRO_WORK        scratch directory (default: mktemp -d, removed on success)
#   REPRO_KEEP=1      keep the roots even when everything passed
#   REPRO_DRY_RUN=1   prerequisites + plan only, no build
#   REPRO_JOBS=       parallelism of EACH build (default: nproc/2, so that the
#                     two concurrent builds add up to about nproc)
#   REPRO_BASE_LINUX  pinned official Linux archive (default: the build
#                     script downloads it and verifies its sha256)
#   REPRO_GRUB_TARBALL  pinned grub-2.04.tar.xz (same default)
#   REPRO_FORK_VERSION  version to stamp (default: latest v*-Fork tag)
#
# Exit: 0 = packages identical, 1 = divergence or failed build, 2 = missing
#       prerequisite (nothing was built).
# =============================================================================
set -u

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd -- "$HERE/../.." && pwd)
BUILD_DIR=$ROOT/dist/ventoy-sort-build
SCRIPT=$BUILD_DIR/build_ventoy_sort_linux.sh

C_OK=$'\033[1;32m'; C_ERR=$'\033[1;31m'; C_WARN=$'\033[1;33m'; C_OFF=$'\033[0m'
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  %s[ok]%s   %s\n' "$C_OK" "$C_OFF" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  %s[FAIL]%s %s\n' "$C_ERR" "$C_OFF" "$1"; }
note() { printf '\n=== %s ===\n' "$1"; }
fatal() { printf '%sFATAL%s %s\n' "$C_ERR" "$C_OFF" "$1" >&2; exit 2; }

[ -f "$SCRIPT" ] || fatal "build script not found: $SCRIPT"
[ -d "$ROOT/GRUB2/MOD_SRC/grub-2.04" ] || fatal "fork overlay not found: $ROOT/GRUB2/MOD_SRC"
[ "$(uname -s)" = Linux ] || fatal "this bench needs Linux (WSL), not $(uname -s)"

note "prerequisites"
MISSING=
for t in gcc aarch64-linux-gnu-gcc make python3 autoreconf automake openssl \
         sbsign sbverify mcopy mdir xz gzip tar sha256sum cmp strings stat nproc; do
    command -v "$t" >/dev/null 2>&1 || MISSING="$MISSING $t"
done
[ -z "$MISSING" ] || fatal "missing tools:$MISSING"
ok "toolchain complete (gcc $(gcc -dumpversion), aarch64-linux-gnu-gcc, sbsigntool)"

FORK_VERSION=${REPRO_FORK_VERSION:-}
if [ -z "$FORK_VERSION" ] && command -v git >/dev/null 2>&1; then
    FORK_VERSION=$(git -C "$ROOT" describe --tags --abbrev=0 --match 'v*-Fork' --match 'v*-ventoy-sort' 2>/dev/null | sed 's/^v//')
fi
[ -n "$FORK_VERSION" ] || fatal "no FORK_VERSION: pass REPRO_FORK_VERSION=... (no v*-Fork tag found)"
ok "version under test: $FORK_VERSION"

# The base archive is pinned by the build script itself; when the caller hands
# us a local copy we check the pin here, because a build script fed an existing
# file skips its own download-time verification.
BASE_PIN=7fb4ed08cef6a6b4d39dd19260d8c80291a78dfdf9af7d461571e23cbbc43805
if [ -n "${REPRO_BASE_LINUX:-}" ] && [ -f "$REPRO_BASE_LINUX" ]; then
    got=$(sha256sum "$REPRO_BASE_LINUX" | cut -d' ' -f1)
    [ "$got" = "$BASE_PIN" ] \
        && ok "base archive matches its pin (${got:0:16}...)" \
        || bad "base archive sha256 $got != pinned $BASE_PIN"
fi

if [ "${REPRO_DRY_RUN:-0}" = 1 ]; then
    printf '\n%sDRY RUN%s - prerequisites OK, nothing built.\n' "$C_WARN" "$C_OFF"
    printf 'Would build %s twice in two isolated roots of different lengths and\n' "$FORK_VERSION"
    printf 'compare the packages byte for byte.\n'
    exit 0
fi

# --- two roots, deliberately of different lengths ---------------------------------
NPROC=$(nproc 2>/dev/null || echo 4)
JOBS=${REPRO_JOBS:-$(( NPROC / 2 ))}
[ "$JOBS" -ge 1 ] 2>/dev/null || JOBS=1

WORK=${REPRO_WORK:-$(mktemp -d)}
mkdir -p "$WORK" || fatal "cannot create work directory: $WORK"
ROOT_A=$WORK/a
ROOT_B=$WORK/b-root-deliberately-longer
if [ "${#ROOT_A}" -eq "${#ROOT_B}" ]; then
    bad "the two roots have the same path length (${#ROOT_A}) - padding effects could hide"
else
    ok "two roots of different lengths (${#ROOT_A} vs ${#ROOT_B} characters)"
fi

note "preparing the two roots"
for r in "$ROOT_A" "$ROOT_B"; do
    mkdir -p "$r/ventoy/dist/ventoy-sort-build" || fatal "cannot populate $r"
    cp -a "$ROOT/GRUB2" "$r/ventoy/GRUB2" || fatal "cannot copy GRUB2 into $r"
    cp -a "$SCRIPT" "$r/ventoy/dist/ventoy-sort-build/" || fatal "cannot copy the build script into $r"
done
cmp -s "$ROOT_A/ventoy/dist/ventoy-sort-build/build_ventoy_sort_linux.sh" \
       "$ROOT_B/ventoy/dist/ventoy-sort-build/build_ventoy_sort_linux.sh" \
    && ok "both roots run a byte-identical copy of the build script" \
    || bad "the two copies of the build script differ"

# Secure Boot key: identical in both roots, otherwise every PE would differ for
# a reason that has nothing to do with reproducibility. Reuse the fork's own key
# when the machine has one (that is the configuration being released), otherwise
# mint a single throwaway key and hand it to both builds through the environment.
SB=$BUILD_DIR/secureboot
if [ -f "$SB/ventoy-sort-mok.key" ] && [ -f "$SB/ventoy-sort-mok.crt" ]; then
    for r in "$ROOT_A" "$ROOT_B"; do
        cp -a "$SB" "$r/ventoy/dist/ventoy-sort-build/secureboot" || fatal "cannot copy the MOK key into $r"
    done
    ok "Secure Boot key: the fork's own (secureboot/) copied into both roots"
else
    MOK=$WORK/mok
    mkdir -p "$MOK"
    openssl req -newkey rsa:2048 -nodes -sha256 -keyout "$MOK/k.key" -x509 -new -days 2 \
        -subj "/CN=repro bench MOK/" -out "$MOK/k.crt" 2>/dev/null \
        || fatal "cannot generate a throwaway MOK key"
    export VENTOY_SORT_MOK_KEY VENTOY_SORT_MOK_CRT
    VENTOY_SORT_MOK_KEY=$(cat "$MOK/k.key")
    VENTOY_SORT_MOK_CRT=$(cat "$MOK/k.crt")
    ok "Secure Boot key: no local key, minted one throwaway key for both roots"
fi

# --- the two builds ----------------------------------------------------------------
note "building twice (parallelism $JOBS per build, this takes minutes)"
T0=$SECONDS
run_build() {   # run_build <root>
    local r=$1 log=$WORK/$(basename "$r").log
    env BASE_LINUX="${REPRO_BASE_LINUX:-}" \
        GRUB_TARBALL="${REPRO_GRUB_TARBALL:-}" \
        FORK_VERSION="$FORK_VERSION" \
        JOBS="$JOBS" \
        bash "$r/ventoy/dist/ventoy-sort-build/build_ventoy_sort_linux.sh" >"$log" 2>&1
}
run_build "$ROOT_A" & PID_A=$!
run_build "$ROOT_B" & PID_B=$!
RC_A=0; RC_B=0
wait "$PID_A" || RC_A=$?
wait "$PID_B" || RC_B=$?
DURATION=$(( SECONDS - T0 ))

if [ "$RC_A" -eq 0 ] && [ "$RC_B" -eq 0 ]; then
    ok "both builds succeeded (${DURATION}s)"
else
    bad "build failed: root A rc=$RC_A, root B rc=$RC_B (${DURATION}s)"
    for r in "$ROOT_A" "$ROOT_B"; do
        printf '\n--- last lines of %s ---\n' "$(basename "$r")"
        tail -n 15 "$WORK/$(basename "$r").log" | sed 's/^/    /'
    done
    printf '\n%sFAIL%s - roots kept for inspection: %s\n' "$C_ERR" "$C_OFF" "$WORK"
    exit 1
fi

PKG_A=$(ls "$ROOT_A/ventoy/dist/ventoy-sort-build"/ventoy-*-linux.tar.gz 2>/dev/null | head -1)
PKG_B=$(ls "$ROOT_B/ventoy/dist/ventoy-sort-build"/ventoy-*-linux.tar.gz 2>/dev/null | head -1)
[ -n "$PKG_A" ] && [ -n "$PKG_B" ] || { bad "a package is missing (A='$PKG_A' B='$PKG_B')"; printf 'roots kept: %s\n' "$WORK"; exit 1; }
ok "both roots produced $(basename "$PKG_A")"

# --- byte-for-byte comparison ------------------------------------------------------
note "comparing the two packages"
SHA_A=$(sha256sum "$PKG_A" | cut -d' ' -f1)
SHA_B=$(sha256sum "$PKG_B" | cut -d' ' -f1)
SZ_A=$(stat -c %s "$PKG_A"); SZ_B=$(stat -c %s "$PKG_B")
printf '  A  %s  %s octets  %s\n' "$SHA_A" "$SZ_A" "$PKG_A"
printf '  B  %s  %s octets  %s\n' "$SHA_B" "$SZ_B" "$PKG_B"
[ "$SZ_A" = "$SZ_B" ] && ok "same size" || bad "size differs: $SZ_A vs $SZ_B"

if cmp -s "$PKG_A" "$PKG_B"; then
    ok "cmp: the two packages are byte-for-byte identical"
else
    bad "cmp: the two packages DIFFER"
    printf '\n  entries that differ:\n'
    python3 - "$PKG_A" "$PKG_B" <<'PY' | sed 's/^/    /'
import hashlib, sys, tarfile
def inv(p):
    out = {}
    with tarfile.open(p, 'r:gz') as t:
        for m in t.getmembers():
            if m.isfile():
                out[m.name] = hashlib.sha256(t.extractfile(m).read()).hexdigest()
    return out
a, b = inv(sys.argv[1]), inv(sys.argv[2])
if set(a) != set(b):
    print('entry lists differ: only in A:', sorted(set(a) - set(b)),
          '| only in B:', sorted(set(b) - set(a)))
diff = sorted(n for n in set(a) & set(b) if a[n] != b[n])
print(f'{len(diff)} differing entries out of {len(a)}:')
for n in diff:
    print(f'  {n}\n    A {a[n]}\n    B {b[n]}')
PY
fi

# Per-entry inventory: catches a same-size, different-content package that a
# bare cmp already reports, but names the culprit files for the report.
INV=$(python3 - "$PKG_A" "$PKG_B" <<'PY'
import hashlib, sys, tarfile
def inv(p):
    out = {}
    with tarfile.open(p, 'r:gz') as t:
        for m in t.getmembers():
            if m.isfile():
                out[m.name] = hashlib.sha256(t.extractfile(m).read()).hexdigest()
    return out
a, b = inv(sys.argv[1]), inv(sys.argv[2])
same_list = set(a) == set(b)
ndiff = sum(1 for n in set(a) & set(b) if a[n] != b[n])
print(f'{len(a)} {same_list} {ndiff}')
PY
)
if [ -z "$INV" ]; then
    bad "could not inventory the entries of the two packages"
    N_ENTRIES=0; SAME_LIST=inconnu; N_DIFF=inconnu
else
    set -- $INV
    N_ENTRIES=$1; SAME_LIST=$2; N_DIFF=$3
    ok "$N_ENTRIES entries inventoried (identical file list: $SAME_LIST)"
fi
[ "$N_DIFF" = 0 ] && ok "0 entry differs in content" || bad "${N_DIFF} entries differ in content"
[ "$SHA_A" = "$SHA_B" ] && ok "sha256 equal: ${SHA_A:0:32}..." || bad "sha256 differ"

# --- the regression this bench guards against --------------------------------------
note "no build path left in the shipped payloads"
XZ_A=$WORK/core-a.xz
if tar -xzOf "$PKG_A" "./ventoy-$FORK_VERSION/boot/core.img.xz" > "$XZ_A" 2>/dev/null \
   || tar -xzOf "$PKG_A" "ventoy-$FORK_VERSION/boot/core.img.xz" > "$XZ_A" 2>/dev/null; then
    xz -dc "$XZ_A" > "$WORK/core-a.img" 2>/dev/null
    LEAKS=0
    for r in "$ROOT_A" "$ROOT_B" "$WORK"; do
        n=$(strings -a "$WORK/core-a.img" | grep -cF "$r" || true)
        [ "$n" = 0 ] || { bad "core.img still contains $n reference(s) to $r"; LEAKS=1; }
    done
    [ "$LEAKS" = 0 ] && ok "boot/core.img.xz embeds no build path (checked both roots and the scratch dir)"
else
    bad "cannot extract boot/core.img.xz from the package"
fi

V_A=$(tar -xzOf "$PKG_A" "./ventoy-$FORK_VERSION/ventoy/version" 2>/dev/null || tar -xzOf "$PKG_A" "ventoy-$FORK_VERSION/ventoy/version" 2>/dev/null)
[ "$V_A" = "$FORK_VERSION" ] \
    && ok "package stamped with version $V_A" \
    || bad "ventoy/version is '$V_A', expected '$FORK_VERSION'"

# --- verdict -----------------------------------------------------------------------
echo
if [ "$FAIL" -gt 0 ]; then
    printf '%sFAILED%s: %d assertion(s) failed, %d passed\n' "$C_ERR" "$C_OFF" "$FAIL" "$PASS"
    printf 'roots kept for inspection: %s\n' "$WORK"
    exit 1
fi
printf '%sPASSED%s: %d assertions, two isolated roots agree byte for byte (%ss)\n' \
    "$C_OK" "$C_OFF" "$PASS" "$DURATION"
if [ "${REPRO_KEEP:-0}" = 1 ]; then
    printf 'roots kept (REPRO_KEEP=1): %s\n' "$WORK"
else
    rm -rf "$WORK"
    printf 'scratch directory removed.\n'
fi
exit 0