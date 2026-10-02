#!/usr/bin/env bash
# =============================================================================
# test_make_release_move_tag.sh - OFFLINE test bench for dist/make_release.cmd
#
# Validates the MOVE_TAG=1 mode (and the normal create path) without touching
# any remote: the script runs under cmd.exe against a throwaway git sandbox
# with a local bare "origin"; `gh` is shadowed by a Python mock that keeps a
# JSON release state.
#
# Instrumentation: git and gh are replaced by tiny .EXE shims (C#, compiled
# once with the Windows csc.exe) that append every invocation to a trace file
# and forward to the real binary. .cmd shims are NOT usable: cmd.exe replaces
# the calling batch file when it invokes another batch without `call`, which
# silently kills make_release.cmd after its first direct `git ...` call.
#
# Usage:  bash dist/tests/test_make_release_move_tag.sh [--check]
#         --check  après les scénarios, vérifie qu'aucun artefact du banc n'a
#                  fui hors du sandbox : marqueur NEW_FILE.txt dans le dépôt
#                  réel, Ventoy-vTEST.* dans le vrai DIST_DIR, et dossiers
#                  movetag./shimbuild. orphelins dans TMP (run crashée).
# Exit:   0 = all assertions passed, 1 = failures (sandbox kept for inspection)
# =============================================================================
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_UNDER_TEST="$HERE/../make_release.cmd"
[ -f "$SCRIPT_UNDER_TEST" ] || { echo "FATAL: $SCRIPT_UNDER_TEST not found"; exit 2; }
CHECK_UNDER_TEST="$HERE/../check_release.cmd"
[ -f "$CHECK_UNDER_TEST" ] || { echo "FATAL: $CHECK_UNDER_TEST not found"; exit 2; }
command -v cmd.exe  >/dev/null 2>&1 || { echo "FATAL: cmd.exe not found"; exit 2; }
command -v python   >/dev/null 2>&1 || { echo "FATAL: python not found"; exit 2; }
command -v git      >/dev/null 2>&1 || { echo "FATAL: git not found"; exit 2; }

CHECK_LEAKS=0
for _arg in "$@"; do
    case "$_arg" in
        --check) CHECK_LEAKS=1 ;;
        *) echo "FATAL: unknown argument: $_arg (usage: $0 [--check])"; exit 2 ;;
    esac
done

CSC="/c/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe"
[ -f "$CSC" ] || { echo "FATAL: csc.exe not found (needed to build the .exe shims)"; exit 2; }

# Real binaries the shims forward to.
GIT_REAL=""
for c in /mingw64/bin/git.exe /usr/bin/git.exe; do
    if [ -x "$c" ]; then GIT_REAL="$(cygpath -w "$c")"; break; fi
done
[ -n "$GIT_REAL" ] || { echo "FATAL: git.exe not found"; exit 2; }
GH_REAL="$(cygpath -w "$(command -v python)")"
export GIT_REAL GH_REAL PYTHONIOENCODING=utf-8

# --------------------------------------------------------------- shim build -
SHIM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shimbuild.XXXXXX")"
build_shims() {
    cat > "$SHIM_DIR/shim.cs" <<'CS_EOF'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class Shim
{
    private static string StripFirstToken(string cmdline)
    {
        int i = 0;
        if (i < cmdline.Length && cmdline[i] == '"')
        {
            i++;
            while (i < cmdline.Length && cmdline[i] != '"') i++;
            if (i < cmdline.Length) i++;
        }
        else
        {
            while (i < cmdline.Length && cmdline[i] != ' ') i++;
        }
        while (i < cmdline.Length && cmdline[i] == ' ') i++;
        return cmdline.Substring(i);
    }

    private static string Quote(string a)
    {
        bool need = a.Length == 0 || a.IndexOfAny(new[] { ' ', '\t', '"' }) >= 0;
        if (!need) return a;
        StringBuilder sb = new StringBuilder("\"");
        int bs = 0;
        foreach (char c in a)
        {
            if (c == '\\') { bs++; continue; }
            if (c == '"') { sb.Append('\\', bs * 2 + 1); sb.Append('"'); bs = 0; continue; }
            sb.Append('\\', bs); bs = 0; sb.Append(c);
        }
        sb.Append('\\', bs * 2);
        sb.Append('"');
        return sb.ToString();
    }

    private static int Main(string[] args)
    {
        string exe = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
        string trace = Environment.GetEnvironmentVariable("MOCK_TRACE");
        if (!string.IsNullOrEmpty(trace))
        {
            StringBuilder sb = new StringBuilder(exe);
            foreach (string a in args) sb.Append(' ').Append(a);
            try { File.AppendAllText(trace, sb.ToString() + "\r\n", new UTF8Encoding(false)); }
            catch { }
        }
        string real = Environment.GetEnvironmentVariable(exe.ToUpperInvariant() + "_REAL");
        if (string.IsNullOrEmpty(real)) return 127;
        string pre = Environment.GetEnvironmentVariable(exe.ToUpperInvariant() + "_PREARGS");
        string rest = StripFirstToken(Environment.CommandLine);
        string arguments = (string.IsNullOrEmpty(pre) ? "" : Quote(pre) + " ") + rest;
        ProcessStartInfo psi = new ProcessStartInfo
        {
            FileName = real,
            Arguments = arguments,
            UseShellExecute = false
        };
        try
        {
            Process p = Process.Start(psi);
            p.WaitForExit();
            return p.ExitCode;
        }
        catch { return 127; }
    }
}
CS_EOF
    local w
    w="$(cygpath -w "$SHIM_DIR")"
    MSYS2_ARG_CONV_EXCL='*' "$CSC" -nologo -optimize+ "-out:$w\\shim.exe" "$w\\shim.cs" \
        >/dev/null 2>&1 || { echo "FATAL: compiling shims with csc.exe failed"; exit 2; }
    [ -f "$SHIM_DIR/shim.exe" ] || { echo "FATAL: shim.exe was not produced"; exit 2; }
}
build_shims

# --------------------------------------------------------------- assertions -
PASS=0; FAIL=0; CUR=""; FAILED=()
LAST_SB=""

note_ok()  { PASS=$((PASS+1)); printf '    ok   %s\n' "$1"; }
note_bad() { FAIL=$((FAIL+1)); FAILED+=("$CUR :: $1"); printf '    FAIL %s\n' "$1"; }

chk_rc()     { if [ "$RC" -eq "$1" ]; then note_ok "rc=$RC"; else note_bad "rc: want $1, got $RC"; fi; }
chk_out_absent() { if grep -qE -- "$1" "$OUT"; then note_bad "output must NOT match /$1/"; else note_ok "output free of /$1/"; fi; }
has_out()    { if grep -qE -- "$1" "$OUT"; then note_ok "output matches /$1/"; else note_bad "output missing /$1/"; fi; }
cnt_trace()  { grep -cE -- "$1" "$TRACE"; }
chk_cnt()    { # pattern expected_count
    local n; n="$(cnt_trace "$1")"
    if [ "$n" -eq "$2" ]; then note_ok "trace /$1/ x$n"; else note_bad "trace /$1/: want x$2, got x$n"; fi
}
chk_order()  { # pattern1 pattern2 label
    local l1 l2
    l1="$(grep -nE -- "$1" "$TRACE" | head -1 | cut -d: -f1)"
    l2="$(grep -nE -- "$2" "$TRACE" | head -1 | cut -d: -f1)"
    if [ -n "${l1:-}" ] && [ -n "${l2:-}" ] && [ "$l1" -lt "$l2" ]; then
        note_ok "order: $3"
    else
        note_bad "order: $3 (l1=${l1:-none}, l2=${l2:-none})"
    fi
}
jval() { # key(''=whole release, 'assets/name' for one asset) tag -> json value
    python - "$STATE/releases.json" "$2" "$1" 2>/dev/null <<'PY'
import json, sys
rs = json.load(open(sys.argv[1]))
r = next(x for x in rs if x["tag"] == sys.argv[2])
v = r
for part in [p for p in sys.argv[3].split("/") if p]:
    v = v[part]
print(json.dumps(v))
PY
}
jcount() { python -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$STATE/releases.json" 2>/dev/null || echo -1; }

# ------------------------------------------------------------- sandbox setup -
setup_sandbox() { # $1 = "notag" (T01) | default: annotated tag vTEST at c1
    [ -n "$LAST_SB" ] && rm -rf "$LAST_SB"
    SB="$(mktemp -d "${TMPDIR:-/tmp}/movetag.XXXXXX")"
    LAST_SB="$SB"
    WIN_SB="$(cygpath -w "$SB")"
    case "$WIN_SB" in
        *" "*) echo "FATAL: sandbox path contains a space: $WIN_SB"; exit 2 ;;
    esac
    ORIGIN="$SB/origin.git"; REPO="$SB/repo"; MOCK="$SB/mock"; STATE="$SB/state"
    DIST="$SB/dist"; OUT="$SB/out.txt"
    mkdir -p "$REPO/dist" "$MOCK" "$STATE"
    TRACE="$STATE/trace.log"; : > "$TRACE"
    export MOCK_STATE="$STATE" MOCK_TRACE="$TRACE" \
           ORIGIN_GIT="$(cygpath -w "$ORIGIN")" FAIL_PUSH_FLAG="$STATE/FAIL_PUSH" \
           GH_PREARGS="$(cygpath -w "$MOCK/gh_mock.py")"

    git init -q -b master "$REPO"
    git -C "$REPO" config user.email test@test.local
    git -C "$REPO" config user.name  move-tag-bench
    printf 'release notes for vTEST\n' > "$REPO/RELEASE_NOTES.md"
    printf 'base content\n'           > "$REPO/base.txt"
    # Stand-in for the perf/sort harness: check_release.cmd only needs RC=0
    # from step 5 - the point here is archive compatibility, not the sweep.
    cat > "$REPO/build_sort_test.py" <<'STUB'
#!/usr/bin/env python3
import sys
sys.exit(0)
STUB
    # both scripts under test are TRACKED, like in the real repo: an
    # untracked file here would make make_release's clean-tree sanity fail.
    cp "$SCRIPT_UNDER_TEST" "$REPO/dist/make_release.cmd"
    cp "$CHECK_UNDER_TEST"  "$REPO/dist/check_release.cmd"
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "c1"
    git init -q --bare "$ORIGIN"
    git -C "$REPO" remote add origin "$(cygpath -w "$ORIGIN")"
    git -C "$REPO" push -q origin master

    if [ "${1:-}" = "notag" ]; then
        ORIG_TAG_SHA=""
    else
        git -C "$REPO" tag -a vTEST -m "Release ventoy-fork vTEST"
        git -C "$REPO" push -q origin "refs/tags/vTEST"
        ORIG_TAG_SHA="$(git -C "$REPO" rev-parse refs/tags/vTEST)"
    fi
    # HEAD moves one commit past the tag: archives must contain the marker.
    printf 'marker at HEAD\n' > "$REPO/NEW_FILE.txt"
    git -C "$REPO" add -A && git -C "$REPO" commit -qm "c2"
    git -C "$REPO" push -q origin master
    HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

    # Rival annotated tag object, pushed to origin: the race scenario points
    # vTEST at it between sanity checks and the force-push.
    git -C "$REPO" tag -a mt-rival -m rival HEAD~1
    RIVAL_SHA="$(git -C "$REPO" rev-parse refs/tags/mt-rival)"
    git -C "$REPO" push -q origin "refs/tags/mt-rival"
    git -C "$REPO" tag -d mt-rival >/dev/null

    # pre-receive hook: rejects pushes only while the scenario flag file exists.
    cat > "$ORIGIN/hooks/pre-receive" <<'HOOK'
#!/bin/sh
if [ -n "${FAIL_PUSH_FLAG:-}" ] && [ -f "$FAIL_PUSH_FLAG" ]; then exit 1; fi
exit 0
HOOK

    write_mocks
    seed_state published
}

write_mocks() {
    # .EXE shims (batch shims would abort the caller: see header)
    cp "$SHIM_DIR/shim.exe" "$MOCK/git.exe"
    cp "$SHIM_DIR/shim.exe" "$MOCK/gh.exe"

    cat > "$MOCK/gh_mock.py" <<'PY'
import hashlib, json, os, shutil, subprocess, sys, zlib

ST  = os.environ["MOCK_STATE"]
TR  = os.environ["MOCK_TRACE"]

# NOTE: invocation tracing is done by the .exe shims (single source of truth);
# the mock only applies side effects to the JSON release state.
def flag(n):  return os.path.exists(os.path.join(ST, n))
def load():
    p = os.path.join(ST, "releases.json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else []
def save(rs):
    with open(os.path.join(ST, "releases.json"), "w", encoding="utf-8") as f:
        json.dump(rs, f, indent=1)

def race_once():
    """Simulate a concurrent retag: move origin's tag while sanity runs."""
    if not flag("RACE") or flag("RACE_DONE"):
        return
    origin = os.environ.get("ORIGIN_GIT", "")
    with open(os.path.join(ST, "RACE"), encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) == 2:
                subprocess.run(
                    ["git", "--git-dir=" + origin, "update-ref",
                     "refs/tags/" + parts[0], parts[1]], check=False)
    open(os.path.join(ST, "RACE_DONE"), "w").close()

def asset_id(name):
    # stable fake GitHub asset id derived from the name
    return str(zlib.crc32(name.encode()))

def asset_name_by_id(rs, aid):
    for r in rs:
        for n in r.get("assets", {}):
            if asset_id(n) == str(aid):
                return n
    return None

def cmd_api(a):
    url = a[1] if len(a) > 1 else ""
    jq = a[a.index("--jq") + 1] if "--jq" in a else ""
    # binary asset download: repos/<o>/<r>/releases/assets/<asset_id>
    if "/releases/assets/" in url:
        if flag("ASSET_API_FAIL"):
            return 1
        name = asset_name_by_id(load(), url.rstrip("/").split("/")[-1])
        if name is None:
            return 1
        store = os.path.join(ST, "assets_store", name)
        if os.path.isfile(store):
            sys.stdout.buffer.write(open(store, "rb").read())
        else:
            # seed asset never uploaded through this mock: placeholder bytes
            sys.stdout.buffer.write(b"OLDASSET-" + name.encode())
        sys.stdout.buffer.flush()
        return 0
    # asset listing: repos/<o>/<r>/releases/<id>/assets
    if url.endswith("/assets"):
        if flag("ASSET_API_FAIL"):
            return 1
        rs = load()
        rel = next((r for r in rs if str(r["id"]) == url.split("/")[-2]), None)
        if rel is None:
            return 1
        names = list(rel.get("assets", {}).keys())
        if jq.strip() == "length":
            print(len(names))
            return 0
        out = ["%s\t%s" % (asset_id(n), n) for n in names]
        if out:
            print("\n".join(out))
        return 0
    if "--paginate" in a:
        if jq.strip() == "length":
            race_once()
            print(len(load()))
            return 0
        # listing: id<TAB>tag per release (drafts included, unlike get-by-tag)
        lines = ["%s\t%s" % (r["id"], r["tag"]) for r in load()]
        if lines:
            print("\n".join(lines))
        return 0
    # detail: repos/<o>/<r>/releases/<id>
    rid = a[1].rstrip("/").split("/")[-1]
    for r in load():
        if str(r["id"]) == rid:
            imm = r.get("immutable")
            print("\t".join([
                str(r.get("tag", "")),
                "true" if r.get("draft") else "false",
                "true" if r.get("prerelease") else "false",
                "null" if imm is None else ("true" if imm else "false"),
            ]))
            return 0
    return 1  # 404

def by_tag(rs, tag):
    return next((r for r in rs if r["tag"] == tag), None)

def cmd_edit(a):
    if flag("EDIT_FAIL"):
        return 1
    rs = load()
    rel = by_tag(rs, a[2])
    if rel is None:
        return 1
    for x in a:
        if x == "--draft=true":  rel["draft"] = True
        elif x == "--draft=false": rel["draft"] = False
        elif x == "--prerelease":  rel["prerelease"] = True
    save(rs)
    return 0

def cmd_upload(a):
    rs = load()
    rel = by_tag(rs, a[2])
    if rel is None:
        return 1
    # a = release upload <tag> [--repo <r>] [--clobber] <files...>
    files = []
    skip = False
    for x in a[3:]:
        if skip:
            skip = False
            continue
        if x == "--repo":
            skip = True
            continue
        if x.startswith("-"):
            continue
        files.append(x)
    # RESTORE_FAIL: the rollback pass re-uploads single files out of
    # DIST_DIR\.asset-backup; fail only the first one so ASSETS_RESTORED=0
    # while the two later ones still come back (manual-repair WARNING).
    if flag("RESTORE_FAIL") and not flag("RESTORE_DID_FAIL") \
            and any(".asset-backup" in f for f in files):
        open(os.path.join(ST, "RESTORE_DID_FAIL"), "w").close()
        return 1
    for i, f in enumerate(files):
        if not os.path.isfile(f):
            return 1
        if flag("UPLOAD_FAIL") and not flag("UPLOAD_DID_FAIL") and i >= 1:
            # real --clobber already deleted/replaced earlier assets; fail
            # only the first upload so the restore pass can succeed.
            open(os.path.join(ST, "UPLOAD_DID_FAIL"), "w").close()
            save(rs)
            return 1
        rel.setdefault("assets", {})[os.path.basename(f)] = \
            hashlib.sha256(open(f, "rb").read()).hexdigest()
        # keep the real bytes so `gh release download` can serve them later
        store = os.path.join(ST, "assets_store")
        os.makedirs(store, exist_ok=True)
        shutil.copy(f, os.path.join(store, os.path.basename(f)))
    save(rs)
    return 0

def cmd_create(a):
    rs = load()
    if by_tag(rs, a[2]) is not None:
        return 1
    rs.append({
        "id": max([r["id"] for r in rs], default=0) + 1,
        "tag": a[2],
        "draft": "--draft" in a,
        "prerelease": "--prerelease" in a,
        "immutable": False,
        "assets": {},
    })
    save(rs)
    return 0

def cmd_download(a):
    # gh release download <tag> --repo <r> --dir <d> [--pattern p ...]
    rs = load()
    rel = by_tag(rs, a[2])
    if rel is None:
        return 1
    outdir = None
    patterns = []
    i = 3
    while i < len(a):
        if a[i] == "--dir" and i + 1 < len(a):
            outdir = a[i + 1]; i += 2; continue
        if a[i] == "--pattern" and i + 1 < len(a):
            patterns.append(a[i + 1]); i += 2; continue
        i += 1
    if not outdir:
        return 1
    store = os.path.join(ST, "assets_store")
    names = list(rel.get("assets", {}).keys())
    if patterns:
        import fnmatch
        names = [n for n in names if any(fnmatch.fnmatch(n, p) for p in patterns)]
    if not names:
        print("no assets match", file=sys.stderr)
        return 1
    os.makedirs(outdir, exist_ok=True)
    copied = 0
    for n in names:
        src = os.path.join(store, n)
        if os.path.isfile(src):
            shutil.copy(src, os.path.join(outdir, n))
            copied += 1
    return 0 if copied else 1

def main():
    a = sys.argv[1:]
    if flag("API_FAIL"):
        return 1
    if not a:
        return 2
    if a[0] == "api":
        return cmd_api(a)
    if a[0] == "release" and len(a) >= 2:
        if   a[1] == "edit":   return cmd_edit(a)
        elif a[1] == "upload": return cmd_upload(a)
        elif a[1] == "create": return cmd_create(a)
        elif a[1] == "download": return cmd_download(a)
    return 2

sys.exit(main())
PY
}

seed_state() {
    case "$1" in
        published)   cat > "$STATE/releases.json" <<'JSON'
[{"id":1,"tag":"vTEST","draft":false,"prerelease":false,"immutable":false,
  "assets":{"Ventoy-vTEST.zip":"old-zip","Ventoy-vTEST.tar.gz":"old-tar",
            "SHA256SUMS":"old-sum","Ventoy-win11.vhd":"old-vhd"}}]
JSON
        ;;
        draft_pre)   cat > "$STATE/releases.json" <<'JSON'
[{"id":1,"tag":"vTEST","draft":true,"prerelease":true,"immutable":false,
  "assets":{"Ventoy-vTEST.zip":"old-zip","Ventoy-vTEST.tar.gz":"old-tar",
            "SHA256SUMS":"old-sum","Ventoy-win11.vhd":"old-vhd"}}]
JSON
        ;;
        immutable)   cat > "$STATE/releases.json" <<'JSON'
[{"id":1,"tag":"vTEST","draft":false,"prerelease":false,"immutable":true,
  "assets":{"Ventoy-vTEST.zip":"old-zip"}}]
JSON
        ;;
        unknown_imm) cat > "$STATE/releases.json" <<'JSON'
[{"id":1,"tag":"vTEST","draft":false,"prerelease":false,"immutable":null,
  "assets":{"Ventoy-vTEST.zip":"old-zip"}}]
JSON
        ;;
        decoy)       cat > "$STATE/releases.json" <<'JSON'
[{"id":2,"tag":"vOTHER","draft":false,"prerelease":false,"immutable":false,
  "assets":{}}]
JSON
        ;;
        empty)       printf '[]\n' > "$STATE/releases.json" ;;
    esac
}

# ------------------------------------------------------------- execution -
# run_env: scenarios export MOVE_TAG/DRY_RUN/CONFIRM_MOVE_TAG before calling it.
run_env() { # $1 = tag
    local tag="$1" win_repo
    win_repo="$(cygpath -w "$REPO")"
    PATH="$MOCK:$PATH" MSYS2_ARG_CONV_EXCL='*' \
        cmd.exe /d /c "$win_repo\\dist\\make_release.cmd $tag" \
        </dev/null >"$OUT" 2>&1
    RC=$?
    tr -d '\r' < "$OUT" > "$OUT.clean" && mv "$OUT.clean" "$OUT"
}

# run_check: e2e-validate the release exactly as dist/check_release.cmd does
# (CI job), against the mock: download -> checksums -> extract -> harness.
run_check() {
    local win_repo
    win_repo="$(cygpath -w "$REPO")"
    PATH="$MOCK:$PATH" MSYS2_ARG_CONV_EXCL='*' \
        cmd.exe /d /c "$win_repo\\dist\\check_release.cmd" \
        </dev/null >"$OUT" 2>&1
    RC=$?
    tr -d '\r' < "$OUT" > "$OUT.clean" && mv "$OUT.clean" "$OUT"
}

clear_env() {
    unset MOVE_TAG CONFIRM_MOVE_TAG DRY_RUN PRERELEASE DIST_DIR RELEASE_TITLE \
          TAG SKIP_SWEEP SWEEP_OUT PKG_DIR 2>/dev/null || true
    rm -f "$STATE/FAIL_PUSH" "$STATE/UPLOAD_FAIL" "$STATE/UPLOAD_DID_FAIL" \
          "$STATE/RACE" "$STATE/RACE_DONE" "$STATE/API_FAIL" "$STATE/EDIT_FAIL" \
          "$STATE/ASSET_API_FAIL" "$STATE/RESTORE_FAIL" \
          "$STATE/RESTORE_DID_FAIL" 2>/dev/null || true
}

scenario() { CUR="$1"; echo "== $1 : $2 =="; }

# =============================================================================
echo "bench: script under test = $SCRIPT_UNDER_TEST"
echo "bench: cmd.exe=$(MSYS2_ARG_CONV_EXCL='*' cmd.exe /d /c "echo %COMSPEC%" </dev/null 2>/dev/null | tr -d '\r')"

# ---------------------------------------------------------------- T01 --------
scenario "T01" "normal create flow (regression, no MOVE_TAG)"
setup_sandbox notag; clear_env
seed_state empty
run_env vTEST
chk_rc 0
has_out "PASS: vTEST tagged"
chk_cnt "gh release create vTEST" 1
chk_cnt "gh release edit vTEST .*--draft=false" 1
chk_cnt "gh release edit vTEST .*--draft=true" 0
chk_cnt "gh api" 0
chk_cnt "git .*push origin vTEST" 1
[ -f "$DIST/Ventoy-vTEST.zip" ] && note_ok "zip exported" || note_bad "zip missing"
[ "$(jcount)" -eq 1 ] && note_ok "release created" || note_bad "release count=$(jcount)"
[ "$(jval draft vTEST)" = "false" ] && note_ok "release ends published" || note_bad "draft state wrong"

# ---------------------------------------------------------------- T02 --------
scenario "T02" "MOVE_TAG happy path: published stable release"
setup_sandbox; clear_env
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 0
has_out "PASS: vTEST moved to HEAD"
has_out "force-pushed"
# tag moved to HEAD, local == remote
LOC="$(git -C "$REPO" rev-parse refs/tags/vTEST)"
REM="$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)"
[ "$LOC" = "$REM" ] && note_ok "local tag == origin tag" || note_bad "tag mismatch local=$LOC origin=$REM"
[ "$(git -C "$REPO" rev-parse 'refs/tags/vTEST^{commit}')" = "$HEAD_SHA" ] \
    && note_ok "tag points at HEAD" || note_bad "tag does not point at HEAD"
# ordering: hide -> move tag -> push -> upload -> republish
chk_order "gh release edit vTEST .*--draft=true" "git .*tag -fa" "hide draft before retag"
chk_order "git .*tag -fa"  "git .*push --force-with-lease" "retag before force-push"
chk_order "git .*push --force-with-lease" "gh release upload vTEST" "push before asset upload"
chk_order "gh release upload vTEST" "gh release edit vTEST .*--draft=false" "upload before republish"
chk_cnt "gh release edit vTEST .*--draft=true" 1
chk_cnt "gh release upload vTEST" 1
chk_cnt "gh release edit vTEST .*--draft=false" 1
# state preserved
[ "$(jval draft vTEST)" = "false" ] && note_ok "still published" || note_bad "draft=$(jval draft vTEST)"
[ "$(jval prerelease vTEST)" = "false" ] && note_ok "still stable" || note_bad "prerelease flipped"
# assets: the three named ones refreshed, other assets untouched
Z_SHA="$(sha256sum "$DIST/Ventoy-vTEST.zip" | cut -d' ' -f1)"
T_SHA="$(sha256sum "$DIST/Ventoy-vTEST.tar.gz" | cut -d' ' -f1)"
S_SHA="$(sha256sum "$DIST/SHA256SUMS" | cut -d' ' -f1)"
[ "$(jval assets/Ventoy-vTEST.zip vTEST | tr -d '"')" = "$Z_SHA" ] \
    && note_ok "zip asset refreshed" || note_bad "zip asset not updated"
[ "$(jval assets/Ventoy-vTEST.tar.gz vTEST | tr -d '"')" = "$T_SHA" ] \
    && note_ok "tar.gz asset refreshed" || note_bad "tar.gz asset not updated"
[ "$(jval assets/SHA256SUMS vTEST | tr -d '"')" = "$S_SHA" ] \
    && note_ok "SHA256SUMS asset refreshed" || note_bad "SHA256SUMS asset not updated"
[ "$(jval assets/Ventoy-win11.vhd vTEST)" = '"old-vhd"' ] \
    && note_ok "complementary asset untouched" || note_bad "complementary asset changed"
# archives really come from the moved tag (marker file at HEAD)
python -c "import sys,zipfile;sys.exit(0 if any('NEW_FILE.txt' in n for n in zipfile.ZipFile(sys.argv[1]).namelist()) else 1)" \
        "$DIST/Ventoy-vTEST.zip" \
    && note_ok "zip built from moved tag (contains NEW_FILE.txt)" \
    || note_bad "zip not built from moved tag"
( cd "$DIST" && sha256sum -c SHA256SUMS >/dev/null 2>&1 ) \
    && note_ok "SHA256SUMS verifies" || note_bad "SHA256SUMS mismatch"
has_out "WARNING: gh release upload --clobber"
chk_cnt "gh api .*releases/assets/.*octet-stream" 3
[ ! -d "$DIST/.asset-backup" ] && note_ok "backup cleaned after success" || note_bad "backup dir left behind"

# ---------------------------------------------------------------- T03 --------
scenario "T03" "MOVE_TAG: draft prerelease stays draft/prerelease"
setup_sandbox; clear_env
seed_state draft_pre
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 0
chk_cnt "gh release edit vTEST .*--draft=true" 0
chk_cnt "gh release edit vTEST .*--draft=false" 0
chk_cnt "gh release edit vTEST .*--prerelease" 1
[ "$(jval draft vTEST)" = "true" ] && note_ok "remains draft" || note_bad "draft=$(jval draft vTEST)"
[ "$(jval prerelease vTEST)" = "true" ] && note_ok "remains prerelease" || note_bad "prerelease lost"
has_out "PASS: vTEST moved"

# ---------------------------------------------------------------- T04 --------
scenario "T04" "MOVE_TAG refuses an immutable release"
setup_sandbox; clear_env
seed_state immutable
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "marks this release immutable"
chk_cnt "gh release edit vTEST" 0
chk_cnt "gh release upload" 0
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "origin tag untouched" || note_bad "origin tag moved!"
[ "$(jval draft vTEST)" = "false" ] && note_ok "release state untouched" || note_bad "release state changed"

# ---------------------------------------------------------------- T05 --------
scenario "T05" "MOVE_TAG fails closed when immutability is unknown"
setup_sandbox; clear_env
seed_state unknown_imm
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "could not confirm that the existing GitHub release is mutable"
chk_cnt "gh release edit vTEST" 0
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "origin tag untouched" || note_bad "origin tag moved!"

# ---------------------------------------------------------------- T06 --------
scenario "T06" "MOVE_TAG with no release for the tag"
setup_sandbox; clear_env
seed_state decoy
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "no GitHub release exists for tag vTEST"
chk_cnt "gh release edit" 0
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "origin tag untouched" || note_bad "origin tag moved!"

# ---------------------------------------------------------------- T07 --------
scenario "T07" "MOVE_TAG when the release listing is unreadable (empty)"
setup_sandbox; clear_env
seed_state empty
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "no accessible GitHub release was found"
chk_cnt "gh release edit" 0

# ---------------------------------------------------------------- T08 --------
scenario "T08" "DRY_RUN previews without side effects"
setup_sandbox; clear_env
export MOVE_TAG=1 DRY_RUN=1
run_env vTEST
chk_rc 0
has_out "DRY-RUN OK"
has_out "force-with-lease"
chk_cnt "gh release edit" 0
chk_cnt "gh release upload" 0
chk_cnt "gh release create" 0
chk_cnt "git .*tag -fa" 0
chk_cnt "git .*push --force-with-lease" 0
chk_cnt "git archive" 0
has_out "gh api repos/.*assets"
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "origin tag untouched" || note_bad "origin tag moved!"
[ ! -f "$DIST/Ventoy-vTEST.zip" ] && note_ok "no archives written" || note_bad "archives written in dry-run"

# ---------------------------------------------------------------- T09 --------
scenario "T09" "dry-run with a wrong CONFIRM_MOVE_TAG is rejected"
setup_sandbox; clear_env
export MOVE_TAG=1 DRY_RUN=1 CONFIRM_MOVE_TAG=vWRONG
run_env vTEST
chk_rc 1
has_out "CONFIRM_MOVE_TAG must match"
chk_cnt "gh " 0

# ---------------------------------------------------------------- T10 --------
scenario "T10" "missing CONFIRM_MOVE_TAG blocks a real move before anything runs"
setup_sandbox; clear_env
export MOVE_TAG=1
run_env vTEST
chk_rc 1
has_out "moving an existing release tag is destructive"
chk_cnt "gh " 0
chk_cnt "git .*tag -fa" 0
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "origin tag untouched" || note_bad "origin tag moved!"

# ---------------------------------------------------------------- T11 --------
scenario "T11" "push rejected by origin: local tag rolled back, release republished"
setup_sandbox; clear_env
touch "$STATE/FAIL_PUSH"
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "restoring the previous local tag and published release"
[ "$(git -C "$REPO" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "local tag rolled back" || note_bad "local tag NOT rolled back"
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "origin tag untouched" || note_bad "origin tag changed"
[ "$(jval draft vTEST)" = "false" ] && note_ok "release republished" || note_bad "release left draft"
chk_cnt "gh release upload" 0
chk_cnt "gh release edit vTEST .*--draft=true" 1
LAST_GH="$(grep -E 'gh release' "$TRACE" | tail -1)"
echo "$LAST_GH" | grep -qE "release edit vTEST .*--draft=false" \
    && note_ok "final gh action is republish" || note_bad "last gh action: $LAST_GH"

# ---------------------------------------------------------------- T12 --------
scenario "T12" "asset upload fails midway: release stays draft, zip already replaced"
setup_sandbox; clear_env
touch "$STATE/UPLOAD_FAIL"
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "remains draft for safety"
has_out "publish the repaired draft manually"
[ "$(jval draft vTEST)" = "true" ] && note_ok "release left as draft" || note_bad "release republished!"
# rollback: every asset must end up byte-identical to its backed-up copy
has_out "restoring the previous assets"
has_out "previous assets restored"
has_out "The previous assets are back in place"
for f in "Ventoy-vTEST.zip" "Ventoy-vTEST.tar.gz" "SHA256SUMS"; do
    BK="$DIST/.asset-backup/$f"
    if [ -f "$BK" ]; then
        BK_SHA="$(sha256sum "$BK" | cut -d' ' -f1)"
        [ "$(jval "assets/$f" vTEST | tr -d '"')" = "$BK_SHA" ] \
            && note_ok "$f restored from backup" \
            || note_bad "$f asset != backup content"
    else
        note_bad "$f backup file missing"
    fi
done
chk_cnt "gh api .*releases/assets/.*octet-stream" 3
chk_cnt "gh release upload vTEST" 4
[ -d "$DIST/.asset-backup" ] && note_ok "backup kept for manual repair" || note_bad "backup dir missing"
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$(git -C "$REPO" rev-parse refs/tags/vTEST)" ] \
    && note_ok "origin tag did move (push succeeded)" || note_bad "tag not moved"
chk_cnt "gh release edit vTEST .*--draft=false" 0

# ---------------------------------------------------------------- T13 --------
scenario "T13" "concurrent retag on origin: fail-closed on unknown remote state"
setup_sandbox; clear_env
printf 'vTEST %s\n' "$RIVAL_SHA" > "$STATE/RACE"
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "could not confirm whether the remote tag moved"
has_out "left as a draft for safety"
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$RIVAL_SHA" ] \
    && note_ok "origin holds the rival tag (lease protected)" || note_bad "origin tag was force-pushed!"
[ "$(jval draft vTEST)" = "true" ] && note_ok "release left as draft" || note_bad "release state wrong"
chk_cnt "gh release upload" 0

# ---------------------------------------------------------------- T14 --------
scenario "T14" "asset backup failure aborts before any change"
setup_sandbox; clear_env
touch "$STATE/ASSET_API_FAIL"
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "could not back up the existing release assets"
has_out "the release and the tag are unchanged"
chk_cnt "gh release edit" 0
chk_cnt "gh release upload" 0
chk_cnt "gh api .*octet-stream" 0
[ "$(git --git-dir="$ORIGIN" rev-parse refs/tags/vTEST)" = "$ORIG_TAG_SHA" ] \
    && note_ok "origin tag untouched" || note_bad "origin tag moved!"
[ "$(jval draft vTEST)" = "false" ] && note_ok "release never hidden" || note_bad "release was modified"
[ ! -d "$DIST/.asset-backup" ] && note_ok "partial backup removed" || note_bad "backup dir left behind"

# ---------------------------------------------------------------- T15 --------
scenario "T15" "check_release.cmd passes on archives regenerated by MOVE_TAG (offline)"
setup_sandbox; clear_env
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 0
has_out "PASS: vTEST moved to HEAD"
unset MOVE_TAG CONFIRM_MOVE_TAG
# The release now holds rebuilt assets; e2e-check them the way CI would.
export TAG=vTEST SKIP_SWEEP=1
run_check
chk_rc 0
has_out "all 2 checksum\\(s\\) OK"
has_out "3/6 extracting"
has_out "4/6 perf sweep skipped"
has_out "5/6 running the harness"
has_out "6/6 no ventoy-sort package"
has_out "PASS: download OK, checksums OK, harness RC=0"

# ---------------------------------------------------------------- T16 --------
scenario "T16" "rollback pass fails: manual-repair WARNING, backup kept"
setup_sandbox; clear_env
touch "$STATE/UPLOAD_FAIL" "$STATE/RESTORE_FAIL"
export MOVE_TAG=1 CONFIRM_MOVE_TAG=vTEST
run_env vTEST
chk_rc 1
has_out "upload failed - restoring the previous assets"
has_out "WARNING: some previous assets could NOT be restored"
has_out "reload them manually from"
has_out "The remote tag points to the moved object"
has_out "Fix the cause and rerun with MOVE_TAG=1"
has_out "publish the repaired draft manually"
# the success-side rollback messages must NOT be claimed
chk_out_absent "previous assets restored"
chk_out_absent "The previous assets are back in place"
chk_out_absent "PASS:"
[ "$(jval draft vTEST)" = "true" ] && note_ok "release left as draft" || note_bad "release republished!"
# first rollback upload (zip) failed: it still holds the rebuilt copy,
# while the two later ones came back byte-identical to their backups.
Z_SHA="$(sha256sum "$DIST/Ventoy-vTEST.zip" | cut -d' ' -f1)"
[ "$(jval assets/Ventoy-vTEST.zip vTEST | tr -d '\"')" = "$Z_SHA" ] \
    && note_ok "zip still holds the rebuilt copy (not restored)" \
    || note_bad "zip asset unexpected"
BK_Z_SHA="$(sha256sum "$DIST/.asset-backup/Ventoy-vTEST.zip" | cut -d' ' -f1)"
[ "$Z_SHA" != "$BK_Z_SHA" ] \
    && note_ok "zip differs from backup: manual reload required" \
    || note_bad "zip matches backup?!"
for f in "Ventoy-vTEST.tar.gz" "SHA256SUMS"; do
    BK="$DIST/.asset-backup/$f"
    BK_SHA="$(sha256sum "$BK" | cut -d' ' -f1)"
    [ "$(jval "assets/$f" vTEST | tr -d '\"')" = "$BK_SHA" ] \
        && note_ok "$f restored from backup" \
        || note_bad "$f asset != backup content"
done
# the backup must stay complete for the manual reload
for f in "Ventoy-vTEST.zip" "Ventoy-vTEST.tar.gz" "SHA256SUMS"; do
    [ -f "$DIST/.asset-backup/$f" ] && note_ok "$f backup kept" || note_bad "$f backup missing"
done
chk_cnt "gh release upload vTEST" 4
chk_cnt "gh release upload vTEST .*asset-backup" 3
chk_cnt "gh release edit vTEST .*--draft=false" 0
[ "$(git --git-dir "$ORIGIN" rev-parse refs/tags/vTEST)" = "$(git -C "$REPO" rev-parse refs/tags/vTEST)" ] \
    && note_ok "origin tag did move (push succeeded)" || note_bad "tag not moved"

# ------------------------------------------------------- leak check (--check) -
# Tout ce que le banc écrit vit sous $SB / $SHIM_DIR (TMP) ; --check assert
# que c'est encore vrai après les scénarios. Les dossiers de CE run sont
# exclus : le nettoyage ci-dessous les supprime juste après le rapport.
if [ "$CHECK_LEAKS" -eq 1 ]; then
    scenario "LK1" "no bench artifact leaked outside the sandbox"
    REAL_REPO="$(cd "$HERE/../.." && pwd)"
    REAL_DIST="$(dirname "$REAL_REPO")/dist"

    [ ! -e "$REAL_REPO/NEW_FILE.txt" ] \
        && note_ok "no NEW_FILE.txt marker in the real repo ($REAL_REPO)" \
        || note_bad "NEW_FILE.txt leaked into the real repo: $REAL_REPO"

    if [ ! -e "$REAL_DIST/Ventoy-vTEST.zip" ] && [ ! -e "$REAL_DIST/Ventoy-vTEST.tar.gz" ]; then
        note_ok "no Ventoy-vTEST.* in the real DIST_DIR ($REAL_DIST)"
    else
        note_bad "vTEST archives leaked into the real DIST_DIR: $REAL_DIST"
    fi

    STALE_SB=""
    for _d in "${TMPDIR:-/tmp}"/movetag.*; do
        [ -d "$_d" ] || continue
        [ "$_d" = "$SB" ] && continue
        STALE_SB="$STALE_SB $_d"
    done
    [ -z "$STALE_SB" ] \
        && note_ok "no stale movetag.* sandbox left in TMP" \
        || note_bad "stale sandbox(es) in TMP (crashed/failed run?):$STALE_SB"

    STALE_SHIM=""
    for _d in "${TMPDIR:-/tmp}"/shimbuild.*; do
        [ -d "$_d" ] || continue
        [ "$_d" = "$SHIM_DIR" ] && continue
        STALE_SHIM="$STALE_SHIM $_d"
    done
    [ -z "$STALE_SHIM" ] \
        && note_ok "no stale shimbuild.* left in TMP" \
        || note_bad "stale shim dir(s) in TMP (crashed run?):$STALE_SHIM"
fi

# ---------------------------------------------------------------- report -----
echo
echo "=============================================== $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    for f in "${FAILED[@]}"; do echo "  FAILED: $f"; done
    echo "sandbox kept: $LAST_SB"
    rm -rf "$SHIM_DIR"
    exit 1
fi
rm -rf "$LAST_SB" "$SHIM_DIR"
exit 0
