#!/usr/bin/env bash
# =====================================================================================
#  build_ventoy_sort_windows.sh — fabrication reproductible, à partir de zéro, du
#                                 paquet Windows du fork « ventoy-sort ».
#
#  Ce que le script régénère (rien d'autre que BASE_ZIP n'est réutilisé) :
#    1. sources GRUB 2.04 (archive vtoytoolchain) + overlay GRUB2/MOD_SRC du fork
#    2. build i386-pc (BIOS), x86_64-efi (UEFI x64), i386-efi (UEFI x86 32 bits)
#       et arm64-efi (UEFI arm64, cross gcc-aarch64-linux-gnu)
#    3. boot/core.img.xz .......... core.img BIOS (contient ventoy.mod patché)
#    4. grubx64_real.efi .......... chargeur UEFI x64 (contient ventoy.mod patché)
#    4b. grubia32_real.efi ........ chargeur UEFI ia32 (idem : correctif tri fusion)
#    4c. BOOTAA64.EFI ............. chargeur UEFI arm64 (idem : correctif tri fusion)
#    5. Ventoy2Disk.exe / altexe/Ventoy2Disk_X64.exe ... recompilés depuis le dépôt
#    5b. signatures Secure Boot .... tous les PE x64/ia32/arm64 de l'image signés avec une
#                                   clé MOK locale (générée une fois) + procédure
#                                   d'enrôlement (PROCEDURE-SECURE-BOOT.md)
#    6. ventoy/ventoy.disk.img.xz . image disque officielle patchée
#                                   (grubx64_real.efi + grubia32_real.efi
#                                    + BOOTAA64.EFI + empreinte fbx64 + version grub.cfg)
#    7. ventoy-<version>-windows.zip + SHA256SUMS + manifeste de build
#
#  Entrée : l'archive Windows officielle de Ventoy (BASE_ZIP) ; tout le reste du
#  runtime (exes tiers, plugins, thèmes, boot.img, image 4K) en est repris tel quel.
#
#  Aucun périphérique n'est touché : le script n'écrit que dans ce dossier et ses
#  sous-dossiers. Rien n'est copié sur une clé USB.
#
#  Lancement :
#      Windows :  build_ventoy_sort_windows.cmd
#      WSL     :  wsl -d Ubuntu -- bash /mnt/d/Codex/ventoy/dist/ventoy-sort-build/build_ventoy_sort_windows.sh
#
#  Variables d'environnement (toutes optionnelles) :
#      BASE_ZIP        archive Windows officielle         (def. /mnt/d/Codex/dist/_dl/ventoy-1.1.17-windows.zip)
#      FORK_VERSION    version inscrite dans le paquet    (def. dernier tag « v*-ventoy-sort »)
#      GRUB_TARBALL    source grub-2.04.tar.xz            (def. <ce dossier>/grub-2.04.tar.xz, sinon téléchargée)
#      JOBS            parallélisme make                  (def. nproc)
#      KEEP=1          conserve les arbres de build       (défaut : tout refaire de zéro)
#      SKIP_EXES=1     réutilise les exes déjà présents   (paquet NON publiable)
#      MSVC_TOOLSET    toolset MSBuild                    (def. v143)
#
#  Prérequis WSL : gcc, gcc-aarch64-linux-gnu (cross arm64), make, python3,
#                  mtools (mcopy/mdir), xz, zip, unzip, sbsigntool, coreutils.
#  Prérequis Windows : Visual Studio Build Tools (MSBuild + toolset C++).
# =====================================================================================
set -Eeuo pipefail
export LC_ALL=C

# Arguments de la forme NAME=value : exportés avant lecture de la configuration
# (permet « build_ventoy_sort_windows.cmd BASE_ZIP=... KEEP=1 » depuis Windows).
for _arg in "$@"; do
    case "$_arg" in
        *=*) export "$_arg" ;;
        *)   printf 'argument non reconnu : %s (attendu NAME=value)\n' "$_arg" >&2; exit 2 ;;
    esac
done

# -------------------------------------------------------------------------------------
# Chemins et configuration
# -------------------------------------------------------------------------------------
SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
B=$(dirname "$SCRIPT_PATH")                 # .../ventoy/dist/ventoy-sort-build
REPO=$(cd -- "$B/../.." && pwd)             # .../ventoy

BASE_ZIP=${BASE_ZIP:-/mnt/d/Codex/dist/_dl/ventoy-1.1.17-windows.zip}
GRUB_TARBALL=${GRUB_TARBALL:-$B/grub-2.04.tar.xz}
GRUB_TARBALL_URL=${GRUB_TARBALL_URL:-https://github.com/ventoy/vtoytoolchain/releases/download/1.0/grub-2.04.tar.xz}
JOBS=${JOBS:-$(nproc)}
KEEP=${KEEP:-0}
SKIP_EXES=${SKIP_EXES:-0}
MSVC_TOOLSET=${MSVC_TOOLSET:-v143}

SRC_PARENT=$B/grub-source
SRC=$SRC_PARENT/grub-2.04
BUILD_BIOS=$SRC/build-bios
BUILD_EFI64=$SRC/build-efi64
BUILD_EFI32=$SRC/build-efi32
BUILD_ARM64=$SRC/build-arm64
GRUB_INSTALL=$B/grub-install
WORK=$B/work
IMG_WORK=$B/imgwork

MKIMAGE_BIOS_LOG=$B/log-mkimage-bios.txt
MKIMAGE_EFI64_LOG=$B/log-mkimage-efi64.txt
MKIMAGE_EFI32_LOG=$B/log-mkimage-efi32.txt
MKIMAGE_ARM64_LOG=$B/log-mkimage-arm64.txt
BUILD_BIOS_LOG=$B/log-build-bios.txt
BUILD_EFI64_LOG=$B/log-build-efi64.txt
BUILD_EFI32_LOG=$B/log-build-efi32.txt
BUILD_ARM64_LOG=$B/log-build-arm64.txt

# Secure Boot : clé MOK propre (générée une fois, jamais empaquetée — seul le
# certificat public parcourt l'image et le zip)
SB_DIR=$B/secureboot
SB_KEY=$SB_DIR/ventoy-sort-mok.key
SB_CRT=$SB_DIR/ventoy-sort-mok.crt
SB_CER=$SB_DIR/ventoy-sort-MOK.cer
SB_LOG=$B/log-sign.txt
SB_PROC=$B/PROCEDURE-SECURE-BOOT.md

# Temps figé pour sbsign (LD_PRELOAD) : la signingTime PKCS7 est la seule source
# de non-déterminisme de la signature Authenticode (la RSA PKCS#1 v1.5 l'est déjà).
# Sans ce shim, deux builds identiques diffèrent octet par octet dans chaque PE signé.
SB_FTIME_C=$SB_DIR/fixedtime.c
SB_FTIME_SO=$SB_DIR/fixedtime.so

# PE de l'image à re-signer avec la clé locale (x64+ia32+aa64 = sign_efi amont ;
# shims BOOT*/MokManager et chargeurs mips non touchés — BOOTAA64.EFI est
# REMPLACÉ par notre build GRUB arm64, signé directement à l'étape mkimage)
SB_IMAGE_TARGETS=(
    ::/ventoy/ventoy_x64.efi
    ::/ventoy/ventoy_ia32.efi
    ::/ventoy/iso9660_x64.efi
    ::/ventoy/iso9660_ia32.efi
    ::/ventoy/udf_x64.efi
    ::/ventoy/udf_ia32.efi
    ::/ventoy/vtoyutil_x64.efi
    ::/ventoy/vtoyutil_ia32.efi
    ::/ventoy/ventoy_aa64.efi
    ::/ventoy/iso9660_aa64.efi
    ::/ventoy/udf_aa64.efi
    ::/ventoy/vtoyutil_aa64.efi
    ::/ventoy/wimboot.x86_64.xz
    ::/ventoy/wimboot.i386.efi.xz
)

EXPECTED_DIFF_FILES="Ventoy2Disk.exe altexe/Ventoy2Disk_X64.exe boot/core.img.xz ventoy/ventoy.disk.img.xz ventoy/version"
FORK_MARKER='Ventoy img list count mismatch'

# GCC 15 refuse sans cela le code GRUB 2.04 : C23 fait de « false »/« true » des mots-clés
# (xzembed/xz.h) et plusieurs diagnostics sont devenus des erreurs.
# -Os est obligatoire côté cible : core.img doit tenir dans 2047 secteurs.
# HOST_CFLAGS concerne les outils (grub-mkimage...) ; TARGET_CFLAGS les modules GRUB.
GRUB_WARN_DOWNGRADES="-Wno-error=discarded-qualifiers -Wno-error=array-bounds \
-Wno-error=zero-length-bounds -Wno-error=misleading-indentation -Wno-error=maybe-uninitialized"
GRUB_HOST_CFLAGS=${GRUB_HOST_CFLAGS:-"-std=gnu17 $GRUB_WARN_DOWNGRADES"}
GRUB_TARGET_CFLAGS=${GRUB_TARGET_CFLAGS:-"-std=gnu17 -Os $GRUB_WARN_DOWNGRADES"}

# -------------------------------------------------------------------------------------
# Journalisation
# -------------------------------------------------------------------------------------
C_STEP=$'\033[1;36m'; C_OK=$'\033[1;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[1;31m'; C_OFF=$'\033[0m'
STEP_NO=0
log()  { printf '\n%s==> %s%s\n' "$C_STEP" "$*" "$C_OFF"; }
ok()   { printf '%s  [ok] %s%s\n' "$C_OK" "$*" "$C_OFF"; }
warn() { printf '%s  [!!] %s%s\n' "$C_WARN" "$*" "$C_OFF" >&2; }
die()  { printf '%s  [erreur] %s%s\n' "$C_ERR" "$*" "$C_OFF" >&2; exit 1; }
step() { STEP_NO=$((STEP_NO + 1)); log "$STEP_NO/$TOTAL_STEPS  $*"; }

on_error() {
    local rc=$? line=$1
    printf '%s  [erreur] ligne %s (code %s) — voir les journaux dans %s%s\n' \
        "$C_ERR" "$line" "$rc" "$B" "$C_OFF" >&2
    exit "$rc"
}
trap 'on_error $LINENO' ERR

sha256() { sha256sum "$1" | cut -d' ' -f1; }
size()   { stat -c %s "$1"; }

run_logged() {   # run_logged <logfile> <commande...>   (écrase le journal)
    local logfile=$1; shift
    if ! "$@" >"$logfile" 2>&1; then
        tail -n 40 "$logfile" >&2 || true
        die "échec de : $*  (journal : $logfile)"
    fi
}

run_logged_append() {   # idem, mais ajoute : configure + make + make install partagent le journal
    local logfile=$1; shift
    if ! "$@" >>"$logfile" 2>&1; then
        tail -n 40 "$logfile" >&2 || true
        die "échec de : $*  (journal : $logfile)"
    fi
}

# --- Secure Boot ---------------------------------------------------------------
strip_sig() {   # strip_sig <fichier PE> — supprime la table de certificats (Authenticode)
                # pour que sbsign produise UNE signature valide (et non un empilement
                # où l'ancienne signature Ventoy, devenue invalide, coexisterait).
    python3 - "$1" <<'PY'
import struct, sys
path = sys.argv[1]
d = bytearray(open(path, 'rb').read())
e = struct.unpack_from('<I', d, 0x3c)[0]
optsz = struct.unpack_from('<H', d, e + 20)[0]
opt = e + 24
magic = struct.unpack_from('<H', d, opt)[0]
dd = opt + (96 if magic == 0x10b else 112)
off = dd + 4 * 8
rva, sz = struct.unpack_from('<II', d, off)
if sz:
    struct.pack_into('<II', d, off, 0, 0)
    nsec = struct.unpack_from('<H', d, e + 6)[0]
    sect = e + 24 + optsz
    maxend = 0
    for i in range(nsec):
        s = sect + i * 40
        rsz, ro = struct.unpack_from('<II', d, s + 16)
        maxend = max(maxend, ro + rsz)
    if rva >= maxend and rva + sz >= len(d):
        del d[rva:]            # la table était en toute fin de fichier
    open(path, 'wb').write(d)
PY
}

sb_sign() {   # sb_sign <fichier PE> — strip + signature avec la clé MOK + vérification
    local f=$1
    [ -f "$f" ] || die "sb_sign : fichier absent : $f"
    [ -f "$SB_FTIME_SO" ] || die "shim fixedtime absent : $SB_FTIME_SO (ensure_sb_key non exécuté ?)"
    strip_sig "$f"
    # LD_PRELOAD ne s'applique qu'à sbsign : signingTime PKCS7 figée au
    # 2027-01-01T00:00:00Z → deux signatures successives sont binaires identiques.
    if ! LD_PRELOAD="$SB_FTIME_SO" sbsign --key "$SB_KEY" --cert "$SB_CRT" \
            --output "$f.signed" "$f" >> "$SB_LOG" 2>&1; then
        tail -n 20 "$SB_LOG" >&2 || true
        die "sbsign a échoué sur $f"
    fi
    mv -f "$f.signed" "$f"
    grep -aq '270101000000Z' "$f" \
        || die "signingTime non figée dans $f (LD_PRELOAD ignoré par sbsign ?) — build non reproductible"
    sbverify --cert "$SB_CRT" "$f" >> "$SB_LOG" 2>&1 \
        || die "signature invalide après sbsign : $f"
}

ensure_sb_key() {   # génère la clé MOK une seule fois (conservée entre les builds)
    : > "$SB_LOG"
    if [ -f "$SB_KEY" ] && [ -f "$SB_CRT" ] && [ -f "$SB_CER" ]; then
        :
    else
        mkdir -p "$SB_DIR"
        log "génération de la clé Secure Boot (MOK) — $SB_KEY"
        openssl req -newkey rsa:2048 -nodes -sha256 -keyout "$SB_KEY" -x509 -new -days 36500 \
            -subj "/CN=ventoy-sort fork MOK/" \
            -addext "basicConstraints=critical,CA:FALSE" \
            -addext "keyUsage=digitalSignature" \
            -addext "extendedKeyUsage=codeSigning" \
            -out "$SB_CRT" 2> "$SB_LOG" \
            || die "génération de la clé MOK échouée (voir $SB_LOG)"
        openssl x509 -in "$SB_CRT" -outform DER -out "$SB_CER" || die "export DER du certificat échoué"
        chmod 600 "$SB_KEY"
    fi
    cp -f "$SB_CER" "$B/ventoy-sort-MOK.cer"
    SB_FP=$(openssl x509 -in "$SB_CRT" -noout -fingerprint -sha256 | cut -d= -f2)
    [ -n "$SB_FP" ] || die "empreinte du certificat MOK absente"

    # Shim de temps figé : recompilé à chaque build (source de vérité = le .c ;
    # ni le .c ni le .so n'entrent dans le paquet).
    cat > "$SB_FTIME_C" <<'C'
/* Fige le temps réel à 2027-01-01 00:00:00 UTC (1798761600) — utilisé UNIQUEMENT
   en LD_PRELOAD sur le processus sbsign : la signingTime de la signature PKCS7
   est ainsi binaire constante. La signature RSA PKCS#1 v1.5 est déjà déterministe,
   seule l'horodatage faisait varier les builds d'un octet à l'autre. */
#include <time.h>
#include <sys/time.h>
#define FIXED 1798761600L
time_t time(time_t *t) { if (t) *t = FIXED; return FIXED; }
int gettimeofday(struct timeval *tv, void *tz) {
    (void)tz; if (tv) { tv->tv_sec = FIXED; tv->tv_usec = 0; } return 0; }
int clock_gettime(clockid_t id, struct timespec *ts) {
    (void)id; if (ts) { ts->tv_sec = FIXED; ts->tv_nsec = 0; } return 0; }
C
    gcc -shared -fPIC -O2 -o "$SB_FTIME_SO" "$SB_FTIME_C" \
        || die "compilation du shim fixedtime échouée ($SB_FTIME_C)"
    ok "temps figé pour sbsign : fixedtime.so (signingTime = 2027-01-01T00:00:00Z)"

    # Procédure d'enrôlement (contenu stable : empreinte + texte fixe)
    cat > "$SB_PROC" <<EOF
# Secure Boot — enrôlement de la clé MOK du fork ventoy-sort

## Ce que signe ce paquet

Clé locale générée par le build (empreinte SHA-256 du certificat) :

    $SB_FP

- recompilés puis signés : \`grubx64_real.efi\`, \`grubia32_real.efi\` et
  \`BOOTAA64.EFI\` (chargeur GRUB arm64 — pas de shim sur ce chemin en 1.1.17)
- re-signés après modification ou pour remplacer la signature Ventoy :
  \`fbx64.efi\` (empreinte sha256 du chargeur x64 mise à jour),
  \`grubia32.efi\`, \`ventoy_{x64,ia32,aa64}.efi\`, \`iso9660_{x64,ia32,aa64}.efi\`,
  \`udf_{x64,ia32,aa64}.efi\`, \`vtoyutil_{x64,ia32,aa64}.efi\`,
  \`wimboot.x86_64.xz\` et \`wimboot.i386.efi.xz\` (PE signés puis re-compressés)
- certificat public : \`ENROLL_THIS_KEY_IN_MOKMANAGER.cer\` à la racine de
  l'image Ventoy (copie locale : \`ventoy-sort-MOK.cer\`, à côté du zip)
- NON touchés : \`EFI/BOOT/BOOTX64.EFI\` et \`BOOTIA32.EFI\` (shims signés
  Microsoft), MokManager (\`mmx64.efi\`/\`mmia32.efi\`), chargeurs mips

## Enrôlement de la clé (une seule fois)

Depuis un Linux (live USB par ex.) :

\`\`\`
mokutil --import ventoy-sort-MOK.cer
# définir un mot de passe MOK, puis redémarrer
\`\`\`

Au redémarrage, l'écran bleu **MokManager** (fourni dans l'image) s'affiche :

1. « Enroll MOK » → « Yes »
2. saisir le mot de passe défini à \`mokutil --import\`
3. « Reboot »

Vérification :

\`\`\`
mokutil --list-enrolled | grep -i ventoy-sort
\`\`\`

Puis activer **Secure Boot** dans le firmware : le fork démarre.

## Enrôlement et validation VIRTUELS (QEMU, sans matériel) — validés

Pour prouver la chaîne sans toucher à une machine réelle, les stores de
variables OVMF/AAVMF se manipulent avec \`virt-fw-vars\` (paquet Debian/Ubuntu
\`python3-virt-firmware\`). Deux scénarios reproduisent l'enrôlement MokManager
(\`ventoy-sort-MOK.cer\` = le fichier du paquet, format DER) :

\`\`\`
GUID=\$(python3 -c 'import uuid; print(uuid.uuid4())')   # GUID libre d'enrôlement

# --- x64 : clés Microsoft conservées + MOK ajouté à db et MokList ---------
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd vars-x64-sb.fd
virt-fw-vars --inplace vars-x64-sb.fd \\
    --add-db "\$GUID" ventoy-sort-MOK.cer \\
    --add-mok "\$GUID" ventoy-sort-MOK.cer

# --- arm64 : PK/KEK/db entièrement établis sur le MOK ---------------------
# (aucun shim Microsoft n'existe sur ce chemin : BOOTAA64.EFI, notre build
#  signé, est vérifié directement par le db — valable pour le zip Windows
#  comme pour le tar Linux)
cp /usr/share/AAVMF/AAVMF_VARS.ms.fd vars-a64-sb.fd
virt-fw-vars --inplace vars-a64-sb.fd \\
    --set-pk "\$GUID" ventoy-sort-MOK.cer \\
    --add-kek "\$GUID" ventoy-sort-MOK.cer \\
    --add-db "\$GUID" ventoy-sort-MOK.cer
\`\`\`

Lancement avec le firmware secboot et ce store (harnais \`_qemu/\` du dépôt :
\`run_vm.sh uefi-sb 5592\` / \`run_vm_a64.sh 5594 sb\` ; \`build_test_disk.sh\`
construit le disque de test depuis le zip Windows, \`build_test_disk_a64.sh\`
depuis le tar Linux ou le zip ; l'AAVMF écrit ses variables sur \`EFIBOOT-*/\`,
l'OVMF dans la copie pflash du store) :

\`\`\`
# --- état réel du Secure Boot après boot (store relu) --------------------
# OVMF : SecureBootEnable : bool: ON   |   AAVMF : idem, lu après arrêt
virt-fw-vars -i vars-x64-sb-run.fd -p | grep SecureBoot
virt-fw-vars -i vars-a64-sb-run.fd -p | grep SecureBoot
\`\`\`

**Résultats validés (deux architectures)** :

| Test | Chargeur signé MOK | Même disque, clés MS seules (MOK absent) |
|---|---|---|
| UEFI x64 (OVMF secboot, disque construit depuis CE zip) | menu « Ventoy … UEFI » atteint, 12/12 ISO triés, 0 violation ; SecureBootEnable: ON post-boot | refus net : « Security Violation », aucun GRUB |
| UEFI arm64 (AAVMF ms, disque construit depuis CE zip) | menu « Ventoy … AA64 » atteint, 12/12 ISO triés, 0 violation ; SecureBootEnable: ON post-boot | refus net : « Access Denied », aucun GRUB |

Les contrôles **négatifs** (même firmware secboot, mêmes disques, seules les
clés changent) prouvent que Secure Boot est réellement appliqué : le chargeur
maison passe quand le MOK est dans le db et est rejeté quand il ne l'est pas.

### Révocation (dbx) — validée

Le firmware applique aussi la liste de révocation. Révocation par certificat
signant (le mécanisme fiable) :

\`\`\`
GUID=\$(python3 -c 'import uuid; print(uuid.uuid4())')
cp vars-x64-sb.fd vars-x64-dbx.fd
virt-fw-vars --inplace vars-x64-dbx.fd --add-dbx-cert "\$GUID" ventoy-sort-MOK.cer
# boot du même disque avec _qemu/run_vm.sh uefi-sb-dbx :
#   -> « Security Violation », aucun GRUB (chargeur signé par un certificat révoqué)
# miroir avec le store sans révocation (uefi-sb) : le menu démarre
\`\`\`

Deux limites documentées : (1) un **haché brut** (sha256 du fichier) mis dans
dbx ne bloque rien — la comparaison dbx du firmware porte sur des hachés de
structure PE ou des certificats ; (2) \`grubx64_real.efi\` est chargé
manuellement par \`fbx64.efi\` (VtoyShim) via son propre contrôle de haché
embarqué, hors vérification dbx du firmware — c'est le chargeur vérifié par le
firmware qui porte l'application de dbx. Test ré-exécutable :
\`_qemu/dbx_check.sh\`.

## Reproductibilité

La \`signingTime\` de chaque signature est figée à
2027-01-01T00:00:00Z pendant \`sbsign\` (shim \`secureboot/fixedtime.so\`),
de sorte que deux builds du même code produisent des paquets binaires
identiques. L'UEFI ne valide pas cette date : seule l'appartenance du
certificat à la MOK compte (validité du certificat : date de génération
→ +100 ans).

## Rotation de clé

Supprimer \`secureboot/\` puis relancer le build → nouvelle clé → refaire
l'enrôlement. L'ancienne clé reste dans MOK jusqu'à retrait
(\`mokutil --delete\`).

## AVERTISSEMENT

- Sauvegarder \`secureboot/ventoy-sort-mok.key\` : sans lui, les signatures
  ne peuvent plus être régénérées (et il faut ré-enrôler).
- La clé privée n'est JAMAIS incluse dans le paquet ni dans l'image.
- dbx/mises à jour shim peuvent révoquer les binaires → refaire un build.
EOF
    ok "clé MOK : $SB_FP (certificat public : ventoy-sort-MOK.cer, procédure : $(basename "$SB_PROC"))"
}

# -------------------------------------------------------------------------------------
# Étape 1 — préflight
# -------------------------------------------------------------------------------------
step_preflight() {
    [ "$(uname -s)" = Linux ] || die "ce script doit tourner sous WSL (bash Linux), pas sous Git Bash"

    local t
    for t in gcc make python3 autoreconf automake openssl mcopy mdir xz zip unzip tar truncate stat sha256sum; do
        command -v "$t" >/dev/null 2>&1 || die "outil manquant : $t"
    done
    command -v aarch64-linux-gnu-gcc >/dev/null 2>&1 \
        || die "cross-compilateur arm64 absent : apt install gcc-aarch64-linux-gnu"
    command -v sbsign >/dev/null 2>&1 && command -v sbverify >/dev/null 2>&1 \
        || die "sbsigntool absent : installer avec « apt install sbsigntool » (WSL Ubuntu)"
    ensure_sb_key
    command -v git >/dev/null 2>&1 || warn "git absent : FORK_VERSION devra être fourni explicitement"

    [ -f "$BASE_ZIP" ] || die "archive officielle introuvable : $BASE_ZIP (BASE_ZIP=...)"
    [ -f "$REPO/GRUB2/MOD_SRC/grub-2.04/install.sh" ] || die "dépôt inattendu : $REPO"
    [ -f "$REPO/Ventoy2Disk/Ventoy2Disk/Ventoy2Disk.vcxproj" ] || die "projet VC++ introuvable dans $REPO"

    case "$B" in
        *" "*) die "le chemin de build contient un espace ($B) : MSBuild/OutDir ne le supporte pas ici" ;;
    esac

    detect_fork_version
    detect_msbuild

    ok "source GRUB   : $( [ -f "$GRUB_TARBALL" ] && echo "$GRUB_TARBALL" || echo "à télécharger" )"
    ok "archive de base: $BASE_ZIP"
    ok "version paquet : $FORK_VERSION"
    ok "sortie         : $B/ventoy-$FORK_VERSION-windows.zip"
}

detect_fork_version() {
    if [ -n "${FORK_VERSION:-}" ]; then
        return
    fi
    command -v git >/dev/null 2>&1 || die "FORK_VERSION non fourni et git indisponible"
    local tag
    tag=$(git -C "$REPO" describe --tags --abbrev=0 --match 'v*-ventoy-sort' 2>/dev/null) \
        || die "aucun tag « v*-ventoy-sort » dans $REPO : fournir FORK_VERSION=..."
    FORK_VERSION=${tag#v}
    GIT_TAG=$tag
    GIT_COMMIT=$(git -C "$REPO" rev-parse --short HEAD)
    if ! git -C "$REPO" diff --quiet "$tag"..HEAD -- GRUB2/ 2>/dev/null; then
        warn "GRUB2/ a changé depuis le tag $tag : la charge utile vient de $GIT_COMMIT, pas du tag"
    fi
}

detect_msbuild() {
    MSBUILD=""
    if [ "$SKIP_EXES" = 1 ]; then
        warn "SKIP_EXES=1 : les exes existants seront réutilisés (paquet non publiable)"
        return
    fi
    local vswhere="/mnt/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    local winpath="" root=""
    if [ -x "$vswhere" ]; then
        winpath=$("$vswhere" -latest -products '*' -requires Microsoft.Component.MSBuild \
                  -property installationPath 2>/dev/null | tr -d '\r' | head -1)
    fi
    if [ -n "$winpath" ]; then
        root=$(wslpath -u "$winpath")
    else
        # repli : emplacements d'installation habituels de VS 2022
        local cand
        for cand in /mnt/c/Program\ Files*/Microsoft\ Visual\ Studio/2022/*/MSBuild/Current/Bin/MSBuild.exe; do
            if [ -x "$cand" ]; then root=$(dirname "$(dirname "$(dirname "$cand")")"); break; fi
        done
    fi
    [ -n "$root" ] || die "Visual Studio Build Tools introuvable : installer les outils C++ ou poser SKIP_EXES=1"
    MSBUILD="$root/MSBuild/Current/Bin/MSBuild.exe"
    [ -x "$MSBUILD" ] || die "MSBuild introuvable : $MSBUILD"
}

# -------------------------------------------------------------------------------------
# Étape 2 — sources GRUB + overlay du fork
# -------------------------------------------------------------------------------------
step_grub_source() {
    if [ ! -f "$GRUB_TARBALL" ]; then
        log "téléchargement de grub-2.04.tar.xz (vtoytoolchain)"
        if command -v gh >/dev/null 2>&1; then
            gh release download 1.0 --repo ventoy/vtoytoolchain --pattern grub-2.04.tar.xz \
               --dir "$(dirname "$GRUB_TARBALL")" --clobber || true
        fi
        [ -f "$GRUB_TARBALL" ] || curl -fL --retry 3 -o "$GRUB_TARBALL" "$GRUB_TARBALL_URL"
    fi
    tar -tf "$GRUB_TARBALL" >/dev/null 2>&1 || die "archive GRUB illisible : $GRUB_TARBALL"
    GRUB_TARBALL_SHA=$(sha256 "$GRUB_TARBALL")
    ok "archive GRUB : $(basename "$GRUB_TARBALL") ($(size "$GRUB_TARBALL") octets, sha256 ${GRUB_TARBALL_SHA:0:16}…)"

    if [ "$KEEP" != 1 ]; then
        rm -rf "$SRC_PARENT" "$GRUB_INSTALL"
    fi
    mkdir -p "$SRC_PARENT" "$WORK"
    if [ ! -d "$SRC" ]; then
        tar -xf "$GRUB_TARBALL" -C "$SRC_PARENT"
    fi
    [ -f "$SRC/configure" ] || die "extraction GRUB incomplète : $SRC/configure absent"

    # Overlay des fichiers modifiés par le fork (fichiers CRLF du checkout Windows : gcc les accepte)
    cp -a "$REPO/GRUB2/MOD_SRC/grub-2.04/." "$SRC/"

    # Les fichiers du fork portent les dates du checkout Windows (2026) alors que les fichiers
    # autotools livrés par l'archive datent de 2019 : sans quoi make tenterait de régénérer
    # aclocal.m4 et Makefile.util.am (aclocal-1.15 absent) au lieu de compiler. On force donc
    # deux dates fixes : sources en 2019-01-01, artefacts autotools livrés en 2019-01-02.
    find "$SRC" -exec touch -h -d '2019-01-01 00:00:00' {} +
    find "$SRC" \( -name '*.in' -o -name '*.am' -o -name 'aclocal.m4' -o -name 'configure' \) \
        -exec touch -h -d '2019-01-02 00:00:00' {} +

    # Les fichiers autotools livrés par l'archive sont PRISTINE : leurs règles
    # ignorent les .def du fork (aucune règle ventoy, pas de -I lib/zstd pour
    # squash4 → « zstd.h: No such file »). On régénère comme un bootstrap GRUB :
    # autogen.sh = gentpl.py (.def → Makefile.*.am) + autoreconf (→ configure,
    # Makefile.in). Ces sorties sont plus récentes que tout, donc make n'invoquera
    # ni aclocal-1.15 (absent) ni automake à l'exécution.
    if ! (cd "$SRC" && PYTHON=python3 bash ./autogen.sh) \
            > "$B/log-autogen.txt" 2>&1; then
        tail -n 40 "$B/log-autogen.txt" >&2 || true
        die "régénération autotools (autogen.sh) échouée — journal : $B/log-autogen.txt"
    fi
    local n_ventoy n_zstd
    n_ventoy=$(grep -c 'am_ventoy_module_OBJECTS = ' "$SRC/grub-core/Makefile.in" || true)
    n_zstd=$(grep -c 'lib/zstd' "$SRC/grub-core/Makefile.in" || true)
    [ "$n_ventoy" -ge 1 ] || die "Makefile.in régénéré sans règle pour le module ventoy (gentpl/Makefile.core.def ?)"
    [ "$n_zstd" -ge 1 ]   || die "Makefile.in régénéré sans -I lib/zstd pour squash4 (source du fork incomplet ?)"

    grep -q "ventoy_img_msort" "$SRC/grub-core/ventoy/ventoy_cmd.c" \
        || die "le tri fusion du fork est absent de ventoy_cmd.c"
    grep -q "$FORK_MARKER" "$SRC/grub-core/ventoy/ventoy_cmd.c" \
        || die "garde-fou du fork absent de ventoy_cmd.c"
    ok "sources GRUB + overlay du fork + autotools régénérés ($SRC)"
}

# -------------------------------------------------------------------------------------
# Étape 3 — build GRUB (arm64-efi, i386-pc, x86_64-efi, i386-efi)
# -------------------------------------------------------------------------------------
build_grub_platform() {   # build_grub_platform <arm64|bios|efi64|efi32>
    local what=$1 bdir log grubdir cfg_args=()
    case $what in
        arm64) bdir=$BUILD_ARM64; log=$BUILD_ARM64_LOG; grubdir=arm64-efi
               # Cross arm64 : options reprises à l'identique de GRUB2/buildgrub.sh
               # (branche « arm64 ») ; le triplet aarch64-linux-gnu-* est celui du
               # paquet Ubuntu gcc-aarch64-linux-gnu. Ce build passe en PREMIER
               # pour que le grub-mkimage hôte installé en dernier reste celui du
               # build efi32 (sorties x86 bit-à-bit identiques aux runs précédents).
               cfg_args=(--target=aarch64 --with-platform=efi
                         --host=x86_64-linux-gnu
                         HOST_CC=x86_64-linux-gnu-gcc BUILD_CC=gcc
                         TARGET_CC=aarch64-linux-gnu-gcc
                         TARGET_OBJCOPY=aarch64-linux-gnu-objcopy
                         TARGET_STRIP=aarch64-linux-gnu-strip
                         TARGET_NM=aarch64-linux-gnu-nm
                         TARGET_RANLIB=aarch64-linux-gnu-ranlib) ;;
        bios)  bdir=$BUILD_BIOS;  log=$BUILD_BIOS_LOG;  grubdir=i386-pc
               cfg_args=(--target=i386 --with-platform=pc) ;;
        efi64) bdir=$BUILD_EFI64; log=$BUILD_EFI64_LOG; grubdir=x86_64-efi
               cfg_args=(--with-platform=efi) ;;
        efi32) bdir=$BUILD_EFI32; log=$BUILD_EFI32_LOG; grubdir=i386-efi
               cfg_args=(--target=i386 --with-platform=efi) ;;
        *) die "plateforme inconnue : $what" ;;
    esac

    rm -rf "$bdir"; mkdir -p "$bdir"
    (
        cd "$bdir"
        HOST_CFLAGS="$GRUB_HOST_CFLAGS" TARGET_CFLAGS="$GRUB_TARGET_CFLAGS" \
            "$SRC/configure" "${cfg_args[@]}" --prefix="$GRUB_INSTALL/" \
            > "$log" 2>&1 || { tail -n 40 "$log" >&2; die "configure ($what) a échoué"; }
        # V=1 : journaliser les lignes gcc complètes (preuve des drapeaux dans le journal)
        run_logged_append "$log" make V=1 -j"$JOBS"
        run_logged_append "$log" make install
    )
    # preuve que les modules installés portent bien le correctif du fork
    local mod=$GRUB_INSTALL/lib/grub/$grubdir/ventoy.mod
    [ -f "$mod" ] || die "ventoy.mod absent après build ($what)"
    grep -a -q "$FORK_MARKER" "$mod" || die "ventoy.mod ($what) ne contient pas le correctif du fork"
    ok "build $what + make install terminés (ventoy.mod patché vérifié)"
}

step_build_grub() {
    build_grub_platform arm64
    build_grub_platform bios
    build_grub_platform efi64
    build_grub_platform efi32
}

# -------------------------------------------------------------------------------------
# Étape 4 — core.img (BIOS) et grubx64/grubia32_real/BOOTAA64 (UEFI x64 + ia32 + arm64)
# -------------------------------------------------------------------------------------
extract_module_list() {   # extract_module_list <nom_variable>  (depuis install.sh, source de vérité)
    tr -d '\r' < "$REPO/GRUB2/MOD_SRC/grub-2.04/install.sh" \
        | sed -n "s/^$1=\"\(.*\)\"[[:space:]]*$/\1/p" | head -1
}

step_mkimage() {
    local inst_sh=$REPO/GRUB2/MOD_SRC/grub-2.04/install.sh
    ALL_MODULES_LEGACY=$(extract_module_list all_modules_legacy)
    ALL_MODULES_UEFI=$(extract_module_list all_modules_uefi)
    ALL_MODULES_ARM64_UEFI=$(extract_module_list all_modules_arm64_uefi)
    [ -n "$ALL_MODULES_LEGACY" ] || die "all_modules_legacy introuvable dans $inst_sh"
    [ -n "$ALL_MODULES_UEFI" ] || die "all_modules_uefi introuvable dans $inst_sh"
    [ -n "$ALL_MODULES_ARM64_UEFI" ] || die "all_modules_arm64_uefi introuvable dans $inst_sh"
    ok "listes de modules relues dans install.sh (legacy: $(wc -w <<<"$ALL_MODULES_LEGACY") modules, uefi: $(wc -w <<<"$ALL_MODULES_UEFI"), arm64: $(wc -w <<<"$ALL_MODULES_ARM64_UEFI"))"

    local mki=$GRUB_INSTALL/bin/grub-mkimage
    [ -x "$mki" ] || die "grub-mkimage absent : $mki"

    # BIOS core.img — commande reprise à l'identique de install.sh (branche « else »)
    run_logged "$MKIMAGE_BIOS_LOG" "$mki" -v \
        --directory "$GRUB_INSTALL/lib/grub/i386-pc" \
        --prefix '(,2)/grub' --output "$WORK/core.img" \
        --format i386-pc --compression auto $ALL_MODULES_LEGACY fat part_msdos biosdisk
    grep -q "reading .*ventoy\.mod" "$MKIMAGE_BIOS_LOG" || die "grub-mkimage (BIOS) n'a pas lu ventoy.mod"

    # UEFI x64 grubx64_real.efi — commande reprise à l'identique de install.sh (branche « uefi »)
    run_logged "$MKIMAGE_EFI64_LOG" "$mki" -v \
        --directory "$GRUB_INSTALL/lib/grub/x86_64-efi" \
        --prefix '(,2)/grub' --output "$WORK/grubx64_real.efi" \
        --format x86_64-efi --compression auto $ALL_MODULES_UEFI
    grep -q "reading .*ventoy\.mod" "$MKIMAGE_EFI64_LOG" || die "grub-mkimage (UEFI) n'a pas lu ventoy.mod"

    # UEFI x86 32 bits grubia32_real.efi — commande reprise à l'identique de
    # install.sh (branche « i386efi », même liste de modules, même prefix)
    run_logged "$MKIMAGE_EFI32_LOG" "$mki" -v \
        --directory "$GRUB_INSTALL/lib/grub/i386-efi" \
        --prefix '(,2)/grub' --output "$WORK/grubia32_real.efi" \
        --format i386-efi --compression auto $ALL_MODULES_UEFI
    grep -q "reading .*ventoy\.mod" "$MKIMAGE_EFI32_LOG" || die "grub-mkimage (UEFI ia32) n'a pas lu ventoy.mod"

    # UEFI arm64 BOOTAA64.EFI — commande reprise à l'identique de install.sh
    # (branche « arm64 » : liste all_modules_arm64_uefi, même prefix, sortie
    # directe BOOTAA64.EFI — en 1.1.17 ce chargeur n'a ni shim ni haché embarqué,
    # grub.cfg le référence par nom). On utilise le grub-mkimage du build arm64
    # (même flux que l'amont) : le mkimage installé par les builds x86 reste
    # exactement celui des exécutions précédentes.
    local mki_arm=$BUILD_ARM64/grub-mkimage
    [ -x "$mki_arm" ] || mki_arm=$GRUB_INSTALL/bin/grub-mkimage
    [ -x "$mki_arm" ] || die "grub-mkimage (arm64) absent : $BUILD_ARM64/grub-mkimage"
    run_logged "$MKIMAGE_ARM64_LOG" "$mki_arm" -v \
        --directory "$GRUB_INSTALL/lib/grub/arm64-efi" \
        --prefix '(,2)/grub' --output "$WORK/BOOTAA64.EFI" \
        --format arm64-efi --compression auto $ALL_MODULES_ARM64_UEFI
    grep -q "reading .*ventoy\.mod" "$MKIMAGE_ARM64_LOG" || die "grub-mkimage (UEFI arm64) n'a pas lu ventoy.mod"

    # Secure Boot : les trois chargeurs recompilés sont signés avec la clé MOK
    # locale (tailles et hachages affichés ci-dessous = fichiers signés)
    sb_sign "$WORK/grubx64_real.efi"
    sb_sign "$WORK/grubia32_real.efi"
    sb_sign "$WORK/BOOTAA64.EFI"

    CORE_IMG_SIZE=$(size "$WORK/core.img")
    CORE_IMG_LIMIT=$((2047 * 512))
    [ "$CORE_IMG_SIZE" -le "$CORE_IMG_LIMIT" ] \
        || die "core.img trop gros : $CORE_IMG_SIZE > $CORE_IMG_LIMIT octets (2047 secteurs)"
    ok "core.img          : $CORE_IMG_SIZE octets (limite $CORE_IMG_LIMIT) — $(sha256 "$WORK/core.img" | cut -c1-16)…"
    ok "grubx64_real.efi  : $(size "$WORK/grubx64_real.efi") octets (signé MOK) — $(sha256 "$WORK/grubx64_real.efi" | cut -c1-16)…"
    ok "grubia32_real.efi : $(size "$WORK/grubia32_real.efi") octets (signé MOK) — $(sha256 "$WORK/grubia32_real.efi" | cut -c1-16)…"
    ok "BOOTAA64.EFI     : $(size "$WORK/BOOTAA64.EFI") octets (signé MOK) — $(sha256 "$WORK/BOOTAA64.EFI" | cut -c1-16)…"
}

# -------------------------------------------------------------------------------------
# Étape 5 — exes Ventoy2Disk (Release|Win32 et Release|x64)
# -------------------------------------------------------------------------------------
msbuild_exe() {   # msbuild_exe <Win32|x64> <IntDir> <log>
    local platform=$1 intdir=$2 log=$3
    local proj
    proj=$(wslpath -w "$REPO/Ventoy2Disk/Ventoy2Disk/Ventoy2Disk.vcxproj")
    local outdir
    outdir="$(wslpath -w "$B")\\"
    local indir
    indir="$(wslpath -w "$intdir")\\"
    rm -rf "$intdir"; mkdir -p "$intdir"
    run_logged "$log" "$MSBUILD" "$proj" /nologo /v:minimal /m \
        /p:Configuration=Release /p:Platform="$platform" /p:PlatformToolset="$MSVC_TOOLSET" \
        /p:WholeProgramOptimization=false \
        "/p:OutDir=$outdir" "/p:IntDir=$indir" \
        "/p:CustomAfterMicrosoftCommonTargets=$REPRO_TARGETS_WIN"
}

step_exes() {
    if [ "$SKIP_EXES" = 1 ]; then
        [ -f "$B/Ventoy2Disk.exe" ] && [ -f "$B/Ventoy2Disk_X64.exe" ] \
            || die "SKIP_EXES=1 mais les exes ne sont pas présents dans $B"
        ok "exes réutilisés (SKIP_EXES=1) : $(size "$B/Ventoy2Disk.exe") + $(size "$B/Ventoy2Disk_X64.exe") octets"
        return
    fi
    "$MSBUILD" -version 2>/dev/null | tr -d '\r' | tail -1 || true

    # Liens reproductibles : /Brepro remplace l'horodatage mur par une valeur
    # déterministe (en-tête COFF + répertoires de débogage). MSBuild ne l'accepte
    # pas en ligne de commande → on l'injecte par une cible d'extension.
    # WholeProgramOptimization=false (/GL + /LTCG) : la compilation à l'édition de
    # liens n'est PAS déterministe (2 octets de .text différents au gré des exécutions)
    # et tout le reste en découle (hachage /Brepro, GUID PDB).
    cat > "$B/repro-link.targets" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemDefinitionGroup>
    <Link>
      <AdditionalOptions>/Brepro %(AdditionalOptions)</AdditionalOptions>
    </Link>
  </ItemDefinitionGroup>
</Project>
XML
    REPRO_TARGETS_WIN=$(wslpath -w "$B/repro-link.targets")
    # sans cela, le PDB de l'exécution précédente reste dans OutDir et son « age »
    # s'incrémente à chaque lien (octet variable dans le CodeView RSDS)
    rm -f "$B/Ventoy2Disk.pdb" "$B/Ventoy2Disk_X64.pdb"

    msbuild_exe Win32 "$B/obj32" "$B/log-msbuild-win32.txt"
    msbuild_exe x64   "$B/obj"   "$B/log-msbuild-x64.txt"
    [ -f "$B/Ventoy2Disk.exe" ] || die "MSBuild Win32 n'a pas produit $B/Ventoy2Disk.exe"
    [ -f "$B/Ventoy2Disk_X64.exe" ] || die "MSBuild x64 n'a pas produit $B/Ventoy2Disk_X64.exe"

    # contrôle du type de binaire (PE machine) : exe principal 32 bits, variante 64 bits
    python3 - "$B/Ventoy2Disk.exe" "$B/Ventoy2Disk_X64.exe" <<'PY'
import struct, sys
def machine(path):
    d = open(path, 'rb').read()
    if d[:2] != b'MZ':
        sys.exit(f'{path}: pas un PE')
    off = struct.unpack_from('<I', d, 0x3c)[0]
    return struct.unpack_from('<H', d, off + 4)[0]
want = [(sys.argv[1], 0x14c, 'i386'), (sys.argv[2], 0x8664, 'x86_64')]
for path, expect, name in want:
    got = machine(path)
    if got != expect:
        sys.exit(f'{path}: machine 0x{got:x}, attendu 0x{expect:x} ({name})')
PY
    ok "Ventoy2Disk.exe $(size "$B/Ventoy2Disk.exe") octets (Win32) · Ventoy2Disk_X64.exe $(size "$B/Ventoy2Disk_X64.exe") octets (x64)"
}

# -------------------------------------------------------------------------------------
# Étape 6 — mise en place du paquet à partir de l'archive officielle
# -------------------------------------------------------------------------------------
step_stage_package() {
    local base_root
    base_root=$(python3 - "$BASE_ZIP" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
names = z.namelist()
print(names[0].split('/')[0])
PY
)
    [ -n "$base_root" ] || die "structure inattendue dans $BASE_ZIP"
    BASE_ROOT=$base_root
    BASE_ZIP_SHA=$(sha256 "$BASE_ZIP")

    rm -rf "$B/pkg"
    mkdir -p "$B/pkg/_base"
    run_logged "$B/log-unzip-base.txt" unzip -q -o "$BASE_ZIP" -d "$B/pkg/_base"
    mv "$B/pkg/_base/$base_root" "$B/pkg/ventoy-$FORK_VERSION"
    rmdir "$B/pkg/_base"
    PKG=$B/pkg/ventoy-$FORK_VERSION
    [ -d "$PKG" ] || die "paquet non extrait"

    # Horodatages officiels des 5 fichiers qui vont être remplacés : ils seront
    # restaurés avant le zip (étape 8) pour que le contenu du zip soit
    # déterministe d'une exécution à l'autre.
    OFF_MTIME_EXE32=$(stat -c %Y "$PKG/Ventoy2Disk.exe")
    OFF_MTIME_EXE64=$(stat -c %Y "$PKG/altexe/Ventoy2Disk_X64.exe")
    OFF_MTIME_CORE=$(stat -c %Y "$PKG/boot/core.img.xz")
    OFF_MTIME_IMG=$(stat -c %Y "$PKG/ventoy/ventoy.disk.img.xz")
    OFF_MTIME_VER=$(stat -c %Y "$PKG/ventoy/version")

    cp -f "$B/Ventoy2Disk.exe"     "$PKG/Ventoy2Disk.exe"
    cp -f "$B/Ventoy2Disk_X64.exe" "$PKG/altexe/Ventoy2Disk_X64.exe"
    printf '%s\n' "$FORK_VERSION" > "$PKG/ventoy/version"

    ok "paquet préparé : $PKG (base « $base_root »)"
}

# -------------------------------------------------------------------------------------
# Étape 7 — patch de l'image disque (grubx64 + grubia32 + BOOTAA64 + empreinte fbx64 + version)
# -------------------------------------------------------------------------------------
patch_disk_image() {
    local img=$IMG_WORK/ventoy.disk.img
    rm -rf "$IMG_WORK"; mkdir -p "$IMG_WORK"

    xz -dc "$PKG/ventoy/ventoy.disk.img.xz" > "$img"
    local img_size
    img_size=$(size "$img")
    [ "$img_size" -eq 33554432 ] || die "taille inattendue de l'image disque : $img_size (attendu 33554432)"
    cp -f "$img" "$IMG_WORK/ventoy.disk.img.orig"

    mcopy -n -i "$img" ::/EFI/BOOT/grubx64_real.efi "$IMG_WORK/grubx64_officiel.efi"
    mcopy -n -i "$img" ::/EFI/BOOT/grubia32_real.efi "$IMG_WORK/grubia32_officiel.efi"
    mcopy -n -i "$img" ::/EFI/BOOT/grubia32.efi     "$IMG_WORK/grubia32_loader_officiel.efi"
    mcopy -n -i "$img" ::/EFI/BOOT/BOOTAA64.EFI     "$IMG_WORK/BOOTAA64_officiel.efi"
    mcopy -n -i "$img" ::/EFI/BOOT/fbx64.efi        "$IMG_WORK/fbx64_officiel.efi"
    mcopy -n -i "$img" ::/grub/grub.cfg             "$IMG_WORK/grub.cfg.officiel"
    # payloads x64+ia32 à re-signer avec la clé locale (liste = sign_efi amont)
    mkdir -p "$IMG_WORK/sb"
    local p
    for p in "${SB_IMAGE_TARGETS[@]}"; do
        mcopy -n -i "$img" "$p" "$IMG_WORK/sb/$(basename "$p")" \
            || die "extraction impossible : $p"
    done

    python3 - "$IMG_WORK" "$WORK/grubx64_real.efi" "$FORK_VERSION" "$img" <<'PY'
import hashlib, re, sys, os
work, new_grub_path, version, img_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
read = lambda n: open(os.path.join(work, n), 'rb').read()
write = lambda n, d: open(os.path.join(work, n), 'wb').write(d)

# --- UEFI x86 32 bits : remplacement simple de grubia32_real.efi -----------------
# Dans l'image officielle, rien ne référence l'empreinte de grubia32_real.efi :
# fbia32.efi est absent du fichier et grubia32.efi charge le chargeur par nom.
# Contrôle d'avenir : si un jour un fichier embarque ce hachage (fbia32 du futur),
# le patch doit être étendu — sinon le boot échouerait à la vérification sans que
# le build ne le signale.
g32_off = read('grubia32_officiel.efi')
cnt32 = open(img_path, 'rb').read().count(hashlib.sha256(g32_off).digest())
if cnt32:
    raise SystemExit(f'ia32 : {cnt32} référence(s) hachée(s) de grubia32_real.efi dans l\'image — étendre le patch')
print('ia32 : aucune référence hachée dans l\'image officielle -> remplacement par nom uniquement')

# --- UEFI arm64 : remplacement de BOOTAA64.EFI -----------------------------------
# En 1.1.17, BOOTAA64.EFI EST le chargeur GRUB arm64 (pas de shim fbaa64) et rien
# ne référence son haché dans l'image ; contrôle d'avenir identique au ia32.
aa_off = read('BOOTAA64_officiel.efi')
cnt64 = open(img_path, 'rb').read().count(hashlib.sha256(aa_off).digest())
if cnt64:
    raise SystemExit(f'arm64 : {cnt64} référence(s) hachée(s) de BOOTAA64.EFI dans l\'image — étendre le patch')
print('arm64 : aucune référence hachée dans l\'image officielle -> remplacement par nom uniquement')

fbx = bytearray(read('fbx64_officiel.efi'))
old_digest = hashlib.sha256(read('grubx64_officiel.efi')).digest()
new_digest = hashlib.sha256(open(new_grub_path, 'rb').read()).digest()

slot = fbx.find(old_digest)
occurrences = fbx.count(old_digest)
if occurrences == 1:
    print(f'fbx64: empreinte officielle trouvée une fois à 0x{slot:x} -> remplacement')
    fbx[slot:slot + 32] = new_digest
else:
    magic = fbx.count(b'\x26' * 8)
    magic_off = fbx.find(b'\x26' * 8)
    if magic == 1:
        print(f'fbx64: emplacement magique vide à 0x{magic_off:x} -> injection de l\'empreinte')
        fbx[magic_off:magic_off + 32] = new_digest
    else:
        raise SystemExit(f'fbx64 inattendu : {occurrences} empreinte(s) officielle(s), {magic} bloc(s) magique(s)')
if fbx.count(new_digest) != 1:
    raise SystemExit('fbx64 : nouvelle empreinte absente ou ambiguë après écriture')
write('fbx64_patche.efi', bytes(fbx))

cfg = read('grub.cfg.officiel').decode('utf-8')
pattern = re.compile(r'(?m)^set VENTOY_VERSION=".*"$')
matches = pattern.findall(cfg)
if len(matches) != 1:
    raise SystemExit(f'grub.cfg : {len(matches)} ligne(s) VENTOY_VERSION, attendu exactement 1')
previous = matches[0]
cfg = pattern.sub(f'set VENTOY_VERSION="{version}"', cfg, count=1)
print(f'grub.cfg: {previous} -> set VENTOY_VERSION="{version}"')
write('grub.cfg.patche', cfg.encode('utf-8'))
PY

    # --- signatures Secure Boot (clé locale MOK) ---------------------------------
    # fbx64 (empreinte x64 mise à jour), chargeur ia32 officiel, payloads ventoy/*.
    # strip préalable : l'ancienne signature Ventoy, rendue invalide par nos
    # modifications, ne doit pas coexister avec la nôtre.
    sb_sign "$IMG_WORK/fbx64_patche.efi"
    sb_sign "$IMG_WORK/grubia32_loader_officiel.efi"
    local base
    for p in "${SB_IMAGE_TARGETS[@]}"; do
        base=$(basename "$p")
        if [ "${base##*.}" = xz ]; then
            # flux amont ventoy_pack.sh : décompresser → signer → re-compresser
            xz -dc "$IMG_WORK/sb/$base" > "$IMG_WORK/sb/${base%.xz}.pe"
            rm -f "$IMG_WORK/sb/$base"
            sb_sign "$IMG_WORK/sb/${base%.xz}.pe"
            xz --check=crc32 -c "$IMG_WORK/sb/${base%.xz}.pe" > "$IMG_WORK/sb/$base"
        else
            sb_sign "$IMG_WORK/sb/$base"
        fi
    done

    mcopy -i "$img" -D overwrite "$WORK/grubx64_real.efi"  ::/EFI/BOOT/grubx64_real.efi
    mcopy -i "$img" -D overwrite "$WORK/grubia32_real.efi" ::/EFI/BOOT/grubia32_real.efi
    mcopy -i "$img" -D overwrite "$WORK/BOOTAA64.EFI"      ::/EFI/BOOT/BOOTAA64.EFI
    mcopy -i "$img" -D overwrite "$IMG_WORK/fbx64_patche.efi" ::/EFI/BOOT/fbx64.efi
    mcopy -i "$img" -D overwrite "$IMG_WORK/grubia32_loader_officiel.efi" ::/EFI/BOOT/grubia32.efi
    mcopy -i "$img" -D overwrite "$IMG_WORK/grub.cfg.patche"  ::/grub/grub.cfg
    for p in "${SB_IMAGE_TARGETS[@]}"; do
        mcopy -i "$img" -D overwrite "$IMG_WORK/sb/$(basename "$p")" "$p"
    done
    # certificat public : remplace le certificat Ventoy enrôlé par défaut
    mcopy -i "$img" -D overwrite "$SB_CER" ::/ENROLL_THIS_KEY_IN_MOKMANAGER.cer

    # relecture depuis l'image : tout doit correspondre au build
    rm -rf "$IMG_WORK/verify"; mkdir -p "$IMG_WORK/verify"
    mcopy -n -i "$img" ::/EFI/BOOT/grubx64_real.efi  "$IMG_WORK/verify/grub.efi"
    mcopy -n -i "$img" ::/EFI/BOOT/grubia32_real.efi "$IMG_WORK/verify/grubia32.efi"
    mcopy -n -i "$img" ::/EFI/BOOT/BOOTAA64.EFI     "$IMG_WORK/verify/BOOTAA64.efi"
    mcopy -n -i "$img" ::/EFI/BOOT/fbx64.efi         "$IMG_WORK/verify/fbx64.efi"
    mcopy -n -i "$img" ::/grub/grub.cfg             "$IMG_WORK/verify/grub.cfg"
    python3 - "$IMG_WORK/verify" "$WORK/grubx64_real.efi" "$FORK_VERSION" "$WORK/grubia32_real.efi" "$WORK/BOOTAA64.EFI" <<'PY'
import hashlib, sys, os
vdir, built, version, built32, built_aa = sys.argv[1:6]
in_image = open(os.path.join(vdir, 'grub.efi'), 'rb').read()
built_data = open(built, 'rb').read()
d = hashlib.sha256(in_image).digest()
assert in_image == built_data, 'grubx64_real.efi de l\'image différent du build'
fbx = open(os.path.join(vdir, 'fbx64.efi'), 'rb').read()
assert fbx.count(d) == 1, 'empreinte grub absente de fbx64 dans l\'image'
in_image32 = open(os.path.join(vdir, 'grubia32.efi'), 'rb').read()
d32 = hashlib.sha256(in_image32).digest()
assert in_image32 == open(built32, 'rb').read(), 'grubia32_real.efi de l\'image différent du build'
in_image_aa = open(os.path.join(vdir, 'BOOTAA64.efi'), 'rb').read()
daa = hashlib.sha256(in_image_aa).digest()
assert in_image_aa == open(built_aa, 'rb').read(), 'BOOTAA64.EFI de l\'image différent du build'
cfg = open(os.path.join(vdir, 'grub.cfg'), 'rb').read().decode('utf-8')
line = f'set VENTOY_VERSION="{version}"'
assert line in cfg, f'version absente de grub.cfg ({line})'
print(f'image vérifiée : grubx64 sha256={d.hex()[:16]}… (empreinte fbx64 ok), '
      f'grubia32 sha256={d32.hex()[:16]}…, BOOTAA64 sha256={daa.hex()[:16]}…, {line}')
PY

    # signatures Secure Boot : relecture depuis l'image, vérification avec NOTRE clé,
    # et certificat public conforme au nôtre (c'est lui qu'il faudra enrôler)
    mcopy -n -i "$img" ::/EFI/BOOT/grubia32.efi  "$IMG_WORK/verify/grubia32_loader.efi"
    mcopy -n -i "$img" ::/ENROLL_THIS_KEY_IN_MOKMANAGER.cer "$IMG_WORK/verify/enroll.cer"
    local vf
    for vf in grub.efi grubia32.efi BOOTAA64.efi fbx64.efi grubia32_loader.efi; do
        sbverify --cert "$SB_CRT" "$IMG_WORK/verify/$vf" >> "$SB_LOG" 2>&1 \
            || die "signature MOK invalide dans l'image : $vf"
    done
    cmp -s "$IMG_WORK/verify/enroll.cer" "$SB_CER" \
        || die "ENROLL_THIS_KEY_IN_MOKMANAGER.cer != certificat local"

    # payloads ventoy/* (PE nus et wimboot*.xz) : relecture depuis l'image +
    # vérification de NOTRE signature — un payload oublié serait détecté ici
    # (les originaux portaient la signature Ventoy, retirée par le strip)
    local vp
    for p in "${SB_IMAGE_TARGETS[@]}"; do
        base=$(basename "$p")
        mcopy -n -i "$img" "$p" "$IMG_WORK/verify/$base" || die "relecture impossible : $p"
        if [ "${base##*.}" = xz ]; then
            xz -dc "$IMG_WORK/verify/$base" > "$IMG_WORK/verify/${base%.xz}.pe"
            vp="$IMG_WORK/verify/${base%.xz}.pe"
        else
            vp="$IMG_WORK/verify/$base"
        fi
        sbverify --cert "$SB_CRT" "$vp" >> "$SB_LOG" 2>&1 \
            || die "payload non signé par la clé MOK dans l'image : $p"
    done
    ok "signatures Secure Boot vérifiées dans l'image (chargeurs x64/ia32/arm64, fbx64, grubia32, payloads ventoy/* + wimboot*) + certificat MOK conforme"

    mdir -i "$img" ::/ 2>/dev/null | tail -2 || true

    # mcopy inscrit l'heure courante dans les champs FAT (création/accès/écriture)
    # des entrées remplacées : l'image ne serait alors pas reproductible à l'octet près.
    # On restaure les horodatages de l'image officielle (les noms 8.3 cherchés sont
    # uniques — vérifié — et le reste de l'image ne dépend que du contenu du build).
    # Dernière opération mtools → juste avant la recompression.
    python3 - "$IMG_WORK/ventoy.disk.img.orig" "$img" <<'PY'
import sys
orig = open(sys.argv[1], 'rb').read()
img = bytearray(open(sys.argv[2], 'rb').read())
def entry(buf, name, tag):
    idxs, i = [], buf.find(name)
    while i != -1:
        idxs.append(i)
        i = buf.find(name, i + 1)
    if len(idxs) != 1:
        raise SystemExit(f'{tag}: {len(idxs)} entrées {name!r}, attendu exactement 1')
    return idxs[0]
for name in (b'FBX64   EFI', b'GRUBX6~1EFI', b'GRUBIA~1EFI', b'GRUB    CFG',
             b'GRUBIA32EFI', b'BOOTAA64EFI', b'VENTOY~1EFI', b'VENTOY~2EFI',
             b'VENTOY~3EFI', b'VTOYUT~3EFI', b'ISO966~1EFI', b'UDF_AA64EFI',
             b'ISO966~2EFI', b'ISO966~3EFI', b'UDF_X64 EFI', b'UDF_IA32EFI',
             b'VTOYUT~1EFI', b'VTOYUT~2EFI', b'WIMBOO~2XZ', b'WIMBOO~1XZ',
             b'ENROLL~1CER'):
    o = entry(orig, name, 'officielle')
    n = entry(img, name, 'patchée')
    # 13-19 : dixièmes + création + accès ; 22-25 : écriture (hors cluster/taille)
    img[n + 13:n + 20] = orig[o + 13:o + 20]
    img[n + 22:n + 26] = orig[o + 22:o + 26]
    print(f'{name.decode(errors="replace").strip()}: horodatages FAT restaurés depuis l\'officiel')
open(sys.argv[2], 'wb').write(img)
PY

    xz --check=crc32 -c "$img" > "$PKG/ventoy/ventoy.disk.img.xz"
    ok "image patchée et recompressée : $(size "$PKG/ventoy/ventoy.disk.img.xz") octets (xz)"
}

# -------------------------------------------------------------------------------------
# Étape 8 — assemblage : core.img.xz, zip, SHA256SUMS, manifeste
# -------------------------------------------------------------------------------------
step_assemble() {
    local padded=$WORK/core.img.padded
    cp -f "$WORK/core.img" "$padded"
    truncate -s $((2047 * 512)) "$padded"
    xz --check=crc32 -c "$padded" > "$PKG/boot/core.img.xz"
    ok "boot/core.img.xz : $(size "$PKG/boot/core.img.xz") octets (core.img complété à 2047 secteurs)"

    # mtime des fichiers remplacés = horodatage officiel → entrées du zip identiques
    # d'une exécution à l'autre (unzip avait restauré ceux des fichiers conservés).
    touch -d "@$OFF_MTIME_EXE32" "$PKG/Ventoy2Disk.exe"
    touch -d "@$OFF_MTIME_EXE64" "$PKG/altexe/Ventoy2Disk_X64.exe"
    touch -d "@$OFF_MTIME_CORE"  "$PKG/boot/core.img.xz"
    touch -d "@$OFF_MTIME_IMG"   "$PKG/ventoy/ventoy.disk.img.xz"
    touch -d "@$OFF_MTIME_VER"   "$PKG/ventoy/version"

    ZIP=$B/ventoy-$FORK_VERSION-windows.zip
    rm -f "$ZIP"
    # -X : ne pas stocker les champs extra (UT/ux) — ils contiennent l'atime des
    # répertoires, lu au moment du zip → variable d'une exécution à l'autre.
    ( cd "$B/pkg" && run_logged "$B/log-zip.txt" zip -q -r -X "$ZIP" "ventoy-$FORK_VERSION" )
    [ -f "$ZIP" ] || die "zip non produit"
    ok "archive : $ZIP ($(size "$ZIP") octets)"
}

step_checksums() {
    CHECKSUMS=$B/SHA256SUMS-ventoy-sort-windows.txt
    ( cd "$B"
      {
        sha256sum -b "$(basename "$ZIP")"
        sha256sum -b "pkg/ventoy-$FORK_VERSION/Ventoy2Disk.exe"
        sha256sum -b "pkg/ventoy-$FORK_VERSION/altexe/Ventoy2Disk_X64.exe"
        sha256sum -b "pkg/ventoy-$FORK_VERSION/boot/core.img.xz"
        sha256sum -b "pkg/ventoy-$FORK_VERSION/ventoy/ventoy.disk.img.xz"
        sha256sum -b "pkg/ventoy-$FORK_VERSION/ventoy/version"
        sha256sum -b "work/core.img"
        sha256sum -b "work/grubx64_real.efi"
        sha256sum -b "work/grubia32_real.efi"
        sha256sum -b "work/BOOTAA64.EFI"
        sha256sum -b "ventoy-sort-MOK.cer"
      } > "$CHECKSUMS"
    )
    ok "empreintes : $CHECKSUMS"
}

step_manifest() {
    MANIFEST=$B/BUILD-MANIFEST-ventoy-$FORK_VERSION.txt
    {
        echo "Manifeste de build — paquet Windows du fork ventoy-sort"
        echo "date            : $(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
        echo "version paquet  : $FORK_VERSION"
        echo "dépôt           : $REPO"
        echo "commit          : ${GIT_COMMIT:-$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo inconnu)}"
        echo "tag de référence: ${GIT_TAG:-$FORK_VERSION}"
        echo "hôte            : $(uname -srm)"
        echo "gcc             : $(gcc --version | head -1)"
        echo "HOST_CFLAGS     : $GRUB_HOST_CFLAGS"
        echo "TARGET_CFLAGS   : $GRUB_TARGET_CFLAGS"
        echo "MSVC toolset    : $MSVC_TOOLSET"
        echo "clé MOK (SB)    : sha256=$SB_FP  (clé privée : secureboot/ventoy-sort-mok.key, hors paquet)"
        echo "archive de base : $(basename "$BASE_ZIP") sha256=$BASE_ZIP_SHA"
        echo "grub tarball    : $(basename "$GRUB_TARBALL") sha256=$GRUB_TARBALL_SHA"
        echo "core.img        : $(size "$WORK/core.img") octets sha256=$(sha256 "$WORK/core.img")"
        echo "grubx64_real.efi: $(size "$WORK/grubx64_real.efi") octets sha256=$(sha256 "$WORK/grubx64_real.efi")"
        echo "grubia32_real.efi: $(size "$WORK/grubia32_real.efi") octets sha256=$(sha256 "$WORK/grubia32_real.efi")"
        echo "BOOTAA64.EFI    : $(size "$WORK/BOOTAA64.EFI") octets sha256=$(sha256 "$WORK/BOOTAA64.EFI")"
        echo "Ventoy2Disk.exe : $(size "$PKG/Ventoy2Disk.exe") octets sha256=$(sha256 "$PKG/Ventoy2Disk.exe")"
        echo "Ventoy2Disk_X64 : $(size "$PKG/altexe/Ventoy2Disk_X64.exe") octets sha256=$(sha256 "$PKG/altexe/Ventoy2Disk_X64.exe")"
        echo "core.img.xz     : $(size "$PKG/boot/core.img.xz") octets sha256=$(sha256 "$PKG/boot/core.img.xz")"
        echo "disk.img.xz     : $(size "$PKG/ventoy/ventoy.disk.img.xz") octets sha256=$(sha256 "$PKG/ventoy/ventoy.disk.img.xz")"
        echo "zip             : $(basename "$ZIP") $(size "$ZIP") octets sha256=$(sha256 "$ZIP")"
        echo
        echo "Le correctif du fork ('$FORK_MARKER') est présent dans :"
        echo "  - $GRUB_INSTALL/lib/grub/i386-pc/ventoy.mod      (embarqué dans boot/core.img.xz)"
        echo "  - $GRUB_INSTALL/lib/grub/x86_64-efi/ventoy.mod   (embarqué dans grubx64_real.efi)"
        echo "  - $GRUB_INSTALL/lib/grub/i386-efi/ventoy.mod    (embarqué dans grubia32_real.efi)"
        echo "  - $GRUB_INSTALL/lib/grub/arm64-efi/ventoy.mod   (embarqué dans BOOTAA64.EFI)"
        echo "Signatures Secure Boot : tous les PE x64/ia32/arm64 de l'image sont signés avec la"
        echo "clé MOK locale (empreinte ci-dessus) — fbx64, grubia32, ventoy_*, iso9660_*,"
        echo "udf_*, vtoyutil_*, wimboot* re-signés, chargeurs recompilés signés (dont"
        echo "BOOTAA64.EFI, notre build GRUB arm64). BOOTX64/BOOTIA32 et MokManager restent"
        echo "signés Microsoft/Fedora (intacts)."
        echo "Horodatage       : signingTime PKCS7 figée au 2027-01-01T00:00:00Z (reproductibilité)"
        echo "Secure Boot : enrôlement de la clé requis — voir PROCEDURE-SECURE-BOOT.md."
        echo "Les charges utiles mips64el restent celles de l'archive officielle."
    } > "$MANIFEST"
    ok "manifeste : $MANIFEST"
}

# -------------------------------------------------------------------------------------
# Étape 9 — vérifications finales
# -------------------------------------------------------------------------------------
step_verify() {
    # a) correctif réellement embarqué dans les trois modules installés
    local d
    for d in i386-pc x86_64-efi i386-efi arm64-efi; do
        grep -a -q "$FORK_MARKER" "$GRUB_INSTALL/lib/grub/$d/ventoy.mod" \
            || die "correctif absent de ventoy.mod ($d)"
    done

    # a2) signatures Secure Boot : chargeurs recompilés vérifiés avec notre certificat
    sbverify --cert "$SB_CRT" "$WORK/grubx64_real.efi"  >> "$SB_LOG" 2>&1 \
        || die "grubx64_real.efi : signature MOK invalide"
    sbverify --cert "$SB_CRT" "$WORK/grubia32_real.efi" >> "$SB_LOG" 2>&1 \
        || die "grubia32_real.efi : signature MOK invalide"
    sbverify --cert "$SB_CRT" "$WORK/BOOTAA64.EFI"      >> "$SB_LOG" 2>&1 \
        || die "BOOTAA64.EFI : signature MOK invalide"
    ok "signatures Secure Boot valides (chargeurs x64 + ia32 + arm64, clé $SB_FP)"

    # b) xz et zip intègres
    xz -t "$PKG/boot/core.img.xz" || die "core.img.xz corrompu"
    xz -t "$PKG/ventoy/ventoy.disk.img.xz" || die "ventoy.disk.img.xz corrompu"
    unzip -tq "$ZIP" > "$B/log-unzip-test.txt" || die "zip corrompu"
    ok "archives xz et zip intègres"

    # c) contenu du zip vs archive officielle : mêmes fichiers, seules les 5 charges utiles diffèrent
    python3 - "$BASE_ZIP" "$ZIP" "$BASE_ROOT" "ventoy-$FORK_VERSION" "$EXPECTED_DIFF_FILES" <<'PY'
import hashlib, sys, zipfile
base_zip, new_zip, base_root, new_root, expected = sys.argv[1:6]
expected = set(expected.split())

def inventory(path, root):
    z = zipfile.ZipFile(path)
    inv = {}
    for name in z.namelist():
        rel = name[len(root):].lstrip('/')
        if not rel:
            continue
        info = z.getinfo(name)
        if info.is_dir():
            continue
        inv[rel] = hashlib.sha256(z.read(name)).hexdigest()
    return inv

base, new = inventory(base_zip, base_root), inventory(new_zip, new_root)
missing, extra = sorted(set(base) - set(new)), sorted(set(new) - set(base))
if missing or extra:
    sys.exit(f'contenu du zip incorrect — manquants={missing} superflus={extra}')
changed = {name for name in base if base[name] != new[name]}
mandatory = {'Ventoy2Disk.exe', 'altexe/Ventoy2Disk_X64.exe', 'boot/core.img.xz', 'ventoy/ventoy.disk.img.xz'}
if not mandatory <= changed:
    sys.exit(f'charges utiles non remplacées : {sorted(mandatory - changed)}')
if changed - expected:
    sys.exit(f'fichiers modifiés inattendus : {sorted(changed - expected)}')
print(f'zip comparé à l\'archive officielle : {len(new)} fichiers identiques en nom, '
      f'{len(changed)} contenu(s) modifié(s) -> {sorted(changed)}')
PY
    ok "contenu du zip conforme (aucun fichier manquant/superflu, 5 remplacements attendus)"
}

# -------------------------------------------------------------------------------------
# Pipeline
# -------------------------------------------------------------------------------------
TOTAL_STEPS=8
main() {
    printf '%s\n' "======================================================================"
    printf '%s\n' " Build reproductible — paquet Windows du fork ventoy-sort"
    printf '%s\n' "======================================================================"
    local t0=$SECONDS

    step_preflight
    step_grub_source
    step "build GRUB 2.04 (i386-pc, x86_64-efi, i386-efi, arm64-efi)";     step_build_grub
    step "charges utiles GRUB (core.img + grubx64 + grubia32 + BOOTAA64)"; step_mkimage
    step "exes Ventoy2Disk (Win32 + x64)";                   step_exes
    step "préparation du paquet depuis l'archive officielle"; step_stage_package
    step "patch de l'image disque + signatures Secure Boot"; patch_disk_image
    step "assemblage (core.img.xz, zip)";                    step_assemble
    step "empreintes + manifeste";                           step_checksums; step_manifest
    step "vérifications finales";                            step_verify

    printf '\n%s' "$C_OK"
    printf '%s\n' "======================================================================"
    printf '%s\n' " TERMINÉ en $((SECONDS - t0)) s"
    printf ' zip      : %s (%s octets)\n' "$(basename "$ZIP")" "$(size "$ZIP")"
    printf ' sha256   : %s\n' "$(sha256 "$ZIP")"
    printf ' dossier  : %s\n' "$PKG"
    printf ' manifeste: %s\n' "$(basename "$MANIFEST")"
    printf '%s' "$C_OFF"
    printf '%s\n' "======================================================================"
    printf '%s\n' " Secure Boot : binaires signés avec la clé MOK locale — enrôlement requis :"
    printf '%s\n' " voir $(basename "$SB_PROC") (clé privée : secureboot/, jamais dans le paquet)."
    printf '%s\n' " Aucune écriture n'a été faite sur un périphérique : tout reste dans ce dossier."
}

main
