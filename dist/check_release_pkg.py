#!/usr/bin/env python3
# =====================================================================================
# check_release_pkg.py — les 3 contrôles du guide « Vérification rapide d'un paquet »
# (README.fr.md) appliqués aux PAQUETS publiés (ventoy-*-ventoy-sort-windows.zip /
# ventoy-*-ventoy-sort-linux.tar.gz), sans WSL ni mtools (analyse directe des
# structures zip/tar/FAT16 en Python standard) :
#
#   1. EMPREINTE   : sha256 de chaque archive, affiché et confronté à
#                    SHA256SUMS-ventoy-sort-*.txt si présent à côté de l'archive
#   2. MARQUEUR    : « Ventoy img list count mismatch » cherché dans
#                    boot/core.img.xz (décompressé, marqueur NON visible : le
#                    core BIOS compresse ses modules -> preuve par empreinte)
#                    et dans les chargeurs EFI grubx64_real.efi / grubia32_real.efi /
#                    BOOTAA64.EFI extraits de ventoy/ventoy.disk.img.xz
#   3. BASELINE    : inventaire des contenus vs l'archive OFFICIELLE 1.1.17
#                    (sha256 épinglés ici) : mêmes noms, exactement les fichiers
#                    attendus modifiés, aucun manquant/superflu
#
# Usage :
#   python check_release_pkg.py <archive-du-paquet...> [--baseline-dir D]
#     --baseline-dir : dossier des baselines officielles (défaut : ../_dl relatif
#                      au script, sinon D:\Codex\dist\_dl)
#   Optionnel : SHA256SUMS-ventoy-sort-windows.txt / SHA256SUMS-ventoy-sort-linux.txt
#   à côté de l'archive => contrôle automatique de la ligne de l'archive.
#
# Codes de retour : 0 = tous les contrôles PASS, 1 = au moins un FAIL.
# =====================================================================================
import argparse
import hashlib
import io
import os
import re
import struct
import sys
import tarfile
import zipfile

MARKER = b"Ventoy img list count mismatch"

# Baselines officielles 1.1.17 (téléchargées une fois dans D:\Codex\dist\_dl).
# Windows : zip ; Linux : tar.gz avec préfixe « ./ ».
BASELINES = {
    "windows": {
        "name": "ventoy-1.1.17-windows.zip",
        "sha256": "d250e97a7595fdac4f97debc630d7a8da942319274a76cb32384596b659dbaeb",
    },
    "linux": {
        "name": "ventoy-1.1.17-linux.tar.gz",
        "sha256": "7fb4ed08cef6a6b4d39dd19260d8c80291a78dfdf9af7d461571e23cbbc43805",
    },
}

# Fichiers autorisés à différer, par plateforme (guide, section 3).
EXPECTED_DIFF = {
    "windows": {
        "Ventoy2Disk.exe",
        "altexe/Ventoy2Disk_X64.exe",
        "boot/core.img.xz",
        "ventoy/ventoy.disk.img.xz",
        "ventoy/version",
    },
    "linux": {
        "boot/core.img.xz",
        "ventoy/ventoy.disk.img.xz",
        "ventoy/version",
    },
}

# Chargeurs EFI attendus dans l'image FAT16 (le marqueur doit y être en clair :
# dans les PE, les modules GRUB ne sont pas compressés — contrairement au core BIOS).
EFI_LOADERS = ("grubx64_real.efi", "grubia32_real.efi", "BOOTAA64.EFI")

# Chargeurs dont l'absence de marqueur est TOLÉRÉE, par plateforme :
# depuis l'extension arm64 du script Windows, BOOTAA64.EFI des DEUX paquets est
# notre build GRUB (marqueur obligatoire partout). (Les zips antérieurs à cette
# extension — empreinte dafb5c09… — gardaient le chargeur officiel : pour
# contrôler ces archives historiques, réintégrer "BOOTAA64.EFI" dans
# l'ensemble « windows » ci-dessous.)
MARKER_OPTIONAL = {"windows": set(), "linux": set()}

def find_data(blob, needle):
    return blob.find(needle) != -1


def marker_ok(label, data):
    if find_data(data, MARKER):
        print(f"    [ok] {label} : marqueur présent")
        return True
    print(f"    [FAIL] {label} : MARQUEUR ABSENT")
    return False


def marker_absent_ok(label, data):
    """Cas du core BIOS : le marqueur ne doit PAS être visible en clair
    (modules compressés par grub-mkimage) — sa présence serait d'ailleurs
    suspecte. La preuve du correctif BIOS passe par l'empreinte (contrôle 3)."""
    if find_data(data, MARKER):
        print(f"    [FAIL] {label} : marqueur visible en clair — inattendu "
              f"(les modules BIOS sont compressés)")
        return False
    print(f"    [ok] {label} : marqueur non visible (attendu — modules compressés), "
          f"preuve par empreinte au contrôle 3")
    return True


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(1 << 20)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def read_member(archive, name):
    """Retourne les octets du membre `name` d'un zip OU d'un tar.gz."""
    if archive.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            names = {n.replace("\\", "/"): n for n in z.namelist()}
            for k, orig in names.items():
                if k == name or k.endswith("/" + name):
                    return z.read(orig)
    else:
        with tarfile.open(archive, "r:gz") as t:
            for m in t.getmembers():
                if not m.isfile():
                    continue
                k = m.name[2:] if m.name.startswith("./") else m.name
                if k == name or k.endswith("/" + name):
                    return t.extractfile(m).read()
    return None


def xz_decompress(blob):
    import lzma
    return lzma.LZMADecompressor(format=lzma.FORMAT_XZ).decompress(blob)


def inventory_zip(path):
    inv = {}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            if info.is_dir():
                continue
            rel = info.filename.replace("\\", "/")
            rel = rel.split("/", 1)[1] if "/" in rel else rel
            inv[rel] = hashlib.sha256(z.read(info)).hexdigest()
    return inv


def inventory_tgz(path):
    inv = {}
    with tarfile.open(path, "r:gz") as t:
        for m in t.getmembers():
            if not m.isfile():
                continue
            k = m.name[2:] if m.name.startswith("./") else m.name
            rel = k.split("/", 1)[1] if "/" in k else k
            inv[rel] = hashlib.sha256(t.extractfile(m).read()).hexdigest()
    return inv


# ---------------------------- FAT16 lecture seule ---------------------------------
def fat16_ctx(img):
    """Géométrie FAT16 : retourne les fonctions de lecture (chaîne de clusters,
    entrées d'un répertoire, résolution de chemin)."""
    bps = struct.unpack_from("<H", img, 11)[0]
    spc = img[13]
    resv = struct.unpack_from("<H", img, 14)[0]
    nfats = img[16]
    rootents = struct.unpack_from("<H", img, 17)[0]
    fatsz = struct.unpack_from("<H", img, 22)[0]
    root_off = (resv + nfats * fatsz) * bps
    root_sz = rootents * 32
    data_off = root_off + root_sz
    fat = img[resv * bps:resv * bps + fatsz * bps]

    def chain(first, size=None):
        out = bytearray()
        cluster = first
        while 2 <= cluster < 0xFFF8:
            out += img[data_off + (cluster - 2) * spc * bps:
                       data_off + (cluster - 1) * spc * bps]
            cluster = struct.unpack_from("<H", fat, cluster * 2)[0]
            if size is not None and len(out) >= size + 1048576:
                break
        return bytes(out[:size] if size is not None else out)

    def dir_entries(first=None):
        """Entrées du répertoire racine (first=None) ou d'un sous-répertoire."""
        data = img[root_off:root_off + root_sz] if first is None else chain(first)
        entries, lfn_parts = [], {}
        for off in range(0, len(data) - 31, 32):
            e = data[off:off + 32]
            if e[0] == 0x00:
                break
            if e[0] == 0xE5:
                lfn_parts = {}
                continue
            if e[11] == 0x0F:
                lfn_parts[e[0] & 0x3F] = e[1:11] + e[14:26] + e[28:32]
                continue
            if lfn_parts:
                lfn = b"".join(lfn_parts[i] for i in sorted(lfn_parts)) \
                    .decode("utf-16le", "ignore").split("\x00", 1)[0]
                lfn_parts = {}
            else:
                lfn = None
            name83 = (e[0:8].decode("ascii", "replace").rstrip()
                      + "." + e[8:11].decode("ascii", "replace").rstrip()).rstrip(".")
            entries.append({
                "lfn": lfn, "name83": name83, "attr": e[11],
                "first": struct.unpack_from("<H", e, 26)[0],
                "size": struct.unpack_from("<I", e, 28)[0],
            })
        return entries

    def resolve(path):
        """Résout « EFI/BOOT/grubx64_real.efi » -> octets, ou None."""
        parts = path.split("/")
        entries = dir_entries()          # racine
        for i, name in enumerate(parts):
            hit = None
            for ent in entries:
                if name.lower() in (ent["lfn"].lower() if ent["lfn"] else None,
                                    ent["name83"].lower()):
                    hit = ent
                    break
            if hit is None:
                return None
            last = i == len(parts) - 1
            if last:
                if hit["attr"] & 0x10:
                    return None          # un répertoire, pas un fichier
                return chain(hit["first"], hit["size"])
            if not hit["attr"] & 0x10:
                return None
            entries = dir_entries(hit["first"])
        return None

    return resolve


def read_disk_image(img):
    """Décompresse ventoy.disk.img.xz et retourne (img_bytes, {loader: bytes})."""
    raw = xz_decompress(img)
    read = fat16_ctx(raw)
    return raw, {ldr: read("EFI/BOOT/" + ldr) for ldr in EFI_LOADERS}


# =====================================================================================
def check_baseline(pkg, kind, base_dir):
    print(f"  3. comparaison à la baseline officielle ({kind})")
    bl = BASELINES[kind]
    blpath = os.path.join(base_dir, bl["name"])
    if not os.path.isfile(blpath):
        print(f"    [skip] baseline absente : {blpath}")
        print("           (télécharger l'archive officielle 1.1.17 pour ce contrôle)")
        return True
    got = sha256_file(blpath)
    if got != bl["sha256"]:
        print(f"    [FAIL] baseline corrompue : sha256 {got[:16]}… != {bl['sha256'][:16]}…")
        return False
    print(f"    [ok] baseline {bl['name']} (sha256 {got[:16]}… vérifié)")

    inv_new = inventory_zip(pkg) if kind == "windows" else inventory_tgz(pkg)
    inv_base = inventory_zip(blpath) if kind == "windows" else inventory_tgz(blpath)
    missing = sorted(set(inv_base) - set(inv_new))
    extra = sorted(set(inv_new) - set(inv_base))
    changed = sorted(n for n in inv_base if n in inv_new and inv_base[n] != inv_new[n])
    expected = EXPECTED_DIFF[kind]
    # A locally rebuilt x86_64 Qt frontend is an optional, ABI-gated package
    # variant. The other three architecture-specific GUI binaries stay official.
    accepted = [expected]
    if kind == "linux":
        accepted.append(expected | {"tool/x86_64/Ventoy2Disk.qt5"})
    ok = True
    if missing or extra:
        print(f"    [FAIL] manquants={missing} superflus={extra}")
        ok = False
    if set(changed) not in accepted:
        print(f"    [FAIL] fichiers modifiés : {changed}")
        print(f"           attendu : l'une des listes {sorted(sorted(x) for x in accepted)}")
        ok = False
    if ok:
        print(f"    [ok] {len(inv_new)} fichiers identiques en nom, "
              f"{len(changed)} modifiés = exactement la liste attendue")
    return ok


def check_marker(pkg, kind):
    print("  2. marqueur du fork dans les chargeurs")
    ok = True
    core = read_member(pkg, "boot/core.img.xz")
    if core is None:
        print("    [FAIL] boot/core.img.xz absent")
        return False
    core_img = xz_decompress(core)
    ok &= marker_absent_ok("boot/core.img (décompressé)", core_img)

    disk_xz = read_member(pkg, "ventoy/ventoy.disk.img.xz")
    if disk_xz is None:
        print("    [FAIL] ventoy/ventoy.disk.img.xz absent")
        return False
    _, loaders = read_disk_image(disk_xz)
    optional = MARKER_OPTIONAL[kind]
    for name in EFI_LOADERS:
        data = loaders.get(name)
        if data is None:
            print(f"    [FAIL] {name} : introuvable dans l'image FAT16 (EFI/BOOT)")
            ok = False
            continue
        if find_data(data, MARKER):
            print(f"    [ok] {name} : marqueur présent")
        elif name in optional:
            print(f"    [warn] {name} : marqueur absent — toléré par la configuration "
                  f"« {kind} » de ce script")
        else:
            print(f"    [FAIL] {name} : MARQUEUR ABSENT")
            ok = False
    version = read_member(pkg, "ventoy/version")
    if version is None:
        print("    [FAIL] ventoy/version absent")
        return False
    ver = version.decode("ascii", "replace").strip()
    if re.fullmatch(r"\d+\.\d+\.\d+-ventoy-sort", ver):
        print(f"    [ok] ventoy/version : {ver}")
    else:
        print(f"    [FAIL] ventoy/version inattendu : {ver!r}")
        ok = False
    return ok


def check_fingerprint(archives):
    print("  1. empreintes")
    ok = True
    for a in archives:
        got = sha256_file(a)
        print(f"    {got}  {os.path.basename(a)}")
        side = None
        kind = "linux" if a.endswith(".tar.gz") else "windows"
        cand = os.path.join(os.path.dirname(os.path.abspath(a)),
                            f"SHA256SUMS-ventoy-sort-{kind}.txt")
        if os.path.isfile(cand):
            want = None
            for line in open(cand, encoding="utf-8", errors="replace"):
                h, _, n = line.partition(" ")
                n = n.strip().lstrip("*")
                if n == os.path.basename(a):
                    want = h.strip().lower()
                    break
            if want is None:
                print(f"    [warn] {os.path.basename(cand)} ne référence pas cette archive")
            elif want == got:
                print(f"    [ok] empreinte conforme à {os.path.basename(cand)}")
            else:
                print(f"    [FAIL] empreinte != {os.path.basename(cand)} ({want[:16]}…)")
                ok = False
        else:
            print("    (pas de SHA256SUMS-ventoy-sort-*.txt à côté : empreinte affichée "
                  "pour comparaison manuelle)")
    return ok


def main():
    ap = argparse.ArgumentParser(
        description="3 contrôles du guide (empreinte, marqueur, baseline) "
                    "sur les paquets ventoy-sort publiés")
    ap.add_argument("archives", nargs="+")
    ap.add_argument("--baseline-dir", default=None)
    args = ap.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    base_dir = args.baseline_dir
    if base_dir is None:
        for cand in (os.path.join(os.path.dirname(script_dir), "_dl"),
                     r"D:\Codex\dist\_dl"):
            if os.path.isdir(cand):
                base_dir = cand
                break
        base_dir = base_dir or "."

    allok = True
    for a in args.archives:
        kind = "linux" if a.endswith(".tar.gz") else "windows"
        print(f"=== {os.path.basename(a)} [{kind}] ===")
        allok &= check_fingerprint([a])
        allok &= check_marker(a, kind)
        allok &= check_baseline(a, kind, base_dir)
        print()
    print("RESULTAT :", "PASS" if allok else "FAIL")
    return 0 if allok else 1


if __name__ == "__main__":
    sys.exit(main())
