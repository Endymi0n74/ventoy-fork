# Ventoy — ventoy-fork

[![CI](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Endymi0n74/ventoy-fork)](https://github.com/Endymi0n74/ventoy-fork/releases/latest)

**Language / Langue:** English | [Français](README.fr.md)

A fork of [ventoy/Ventoy](https://github.com/ventoy/Ventoy) **v1.1.18** (`6116894a`)
that adds a focused improvement to boot-menu image sorting, and publishes ready-to-boot
Windows and Linux packages rebuilt from source. Upstream v1.1.18 was merged on
2026-10-09 and the packages are now rebuilt from the official **1.1.18** archive, see
[Known limits](#known-limits).

Ventoy itself is an open source tool to create bootable USB drives: copy ISO/WIM/IMG/
VHD(x)/EFI files onto a drive and pick one from a boot menu. Everything below about
Ventoy's own capabilities is upstream's; see [Upstream Ventoy](#upstream-ventoy).

## Latest release

**[v1.1.18-Fork](https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.18-Fork)**
— published 2026-10-09, annotated tag on commit `df404c9e`.

| Type | Asset | Contents |
|---|---|---|
| Source archive | [Ventoy-v1.1.18-Fork.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/Ventoy-v1.1.18-Fork.zip) | Full source tree; compile it yourself |
| Source archive | [Ventoy-v1.1.18-Fork.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/Ventoy-v1.1.18-Fork.tar.gz) | Full source tree; compile it yourself |
| Binary package (Windows) | [ventoy-1.1.18-Fork-windows.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/ventoy-1.1.18-Fork-windows.zip) | Ready-to-use; 45 files, 5 differ from official 1.1.18 |
| Binary package (Linux) | [ventoy-1.1.18-Fork-linux.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/ventoy-1.1.18-Fork-linux.tar.gz) | Ready-to-use; 137 files, 3 differ from official 1.1.18 |
| Checksums | [SHA256SUMS](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/SHA256SUMS) | Covers the two source archives |
| Checksums | [SHA256SUMS-Fork-windows.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/SHA256SUMS-Fork-windows.txt) | Covers the Windows zip + 10 build artifacts |
| Checksums | [SHA256SUMS-Fork-linux.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/SHA256SUMS-Fork-linux.txt) | Covers the Linux tar.gz + 8 build artifacts |

The first two are **source archives**, not installable builds. The two binary packages are
ready to copy to a USB drive.

### Verifying a download

Full SHA-256 of the four downloadable files, to compare against what
`sha256sum` (or `Get-FileHash`) reports:

- `Ventoy-v1.1.18-Fork.zip` — `18cef2d6c23c9a35abc80fe23837aaf41a6e0859159d23f62bd1456de314ebeb`
- `Ventoy-v1.1.18-Fork.tar.gz` — `7290719022cf69ae4d1876f216ac9a8cf12ec95d50894f5d1fbd78ae8d7be534`
- `ventoy-1.1.18-Fork-windows.zip` — `fccaf0b17c7de74d21c8c6f3a5527ad136baa203451d5d7dba72a01ef0933a4c`
- `ventoy-1.1.18-Fork-linux.tar.gz` — `474ace026a53300ac627da9a1458ced94d6f04a4fdc0106f4839b3b6a3b6ce60`

## Installing

1. Download the package for your platform above and verify its SHA-256.
2. On Windows, extract `ventoy-1.1.18-Fork-windows.zip`; on Linux, extract
   `ventoy-1.1.18-Fork-linux.tar.gz`.
3. Write the extracted folder to a USB drive, ideally a **GPT** partition with **exFAT**.
4. Boot from it and pick an image in the menu.

**Secure Boot.** The fork's loaders are signed with the fork's own MOK key, not
Microsoft's. Either disable Secure Boot, or enroll the certificate first or the boot is
refused (`Verification failed: (0x1A) Security Violation`). The certificate is
`ENROLL_THIS_KEY_IN_MOKMANAGER.cer` at the root of the `ventoy` partition — **not** a
loose `.cer` file in the package. Fingerprint:

    8A:78:E8:AC:D9:88:D6:1E:ED:FF:97:64:8A:82:0A:F1:87:E0:10:CA:83:E5:27:B9:FA:6C:E2:06:DF:25:AA:89

Full procedure: [`dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md`](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md).

## What this fork changes

### Boot-menu image sorting

`GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_cmd.c`:

- Replaces the O(n²) selection sort with a **stable O(n log n) merge sort**. Images with
  equal names keep their discovery order.
- **Bug fix included**: the first version of the split did not terminate the first half of
  the list, which made the merge re-consume nodes from `a` and could hang boot-menu
  construction from three images onward.
- **Consistency guard**: before sorting, the recorded image count is checked against the
  real list length; a mismatch is reported on the console and sorting continues.

Measured on 32 to 16384 images (30 seeds, QPC): ~1.4× at 32, ~8.7× at 512, ~22× at 2048,
~126× at 16384. Details: [PERF_FINDINGS.md](PERF_FINDINGS.md).

### Linux GUI version label

The upstream Linux interfaces are sized for a six-character version (`1.0.53`); the fork's
string reached 18 characters (`1.1.20-ventoy-sort`) and overflowed its frame, over `exFAT`
and `MBR`. Qt: window
441 → 660 px, version frames 205 → 315 px, and a runtime font size between 20 pt and a
9 pt floor. GTK: version labels 120 → 305 px. WebUI: `.vtoy_ver` uses intrinsic width,
boxes 250 → 430 px. `Ventoy2Disk.pro` also had absolute `/home/panda/...` include paths,
now relative, so the project builds outside its original author's machine.

**This is a source-level fix.** The published binary packages embed the official Ventoy
1.1.18 runtime, GUI binaries included — the Linux build deliberately keeps the official
ones (`GUI_REBUILD` off) — so the redrawn Qt window is **not** in them.

## Validating the change

A standalone regression harness — no Docker, WSL or VM, only **clang** and **Python 3**:

```
python build_sort_test.py           # regression suite (RC=0 expected)
python build_sort_test.py --perf    # + perf comparison against naive sort
```

End-to-end release check, one command: `dist\check_release.cmd` downloads the latest
assets, verifies `SHA256SUMS`, extracts the archive, runs the 30-seed perf sweep and the
harness from the extraction. Set `SKIP_SWEEP=1` to skip the sweep.

## Known limits

- **No real USB boot has been validated.** The modified GRUB has been exercised in QEMU
  and OVMF, not on physical hardware; a full boot ISO was deliberately not built.
- **The GUI fix ships as source only**, as explained above.
- The Windows package was reproduced byte-for-byte across two independent CI runs; the
  Linux package builds on a pinned `ubuntu-24.04` because the compiler version changes
  GRUB's output bytes (`dist/tests/test_linux_reproducibility.sh` builds it twice in
  isolated trees and compares the two).
- **The published packages are built from the official 1.1.18 archive**, pinned by
  SHA-256 in `build-package*.yml`, in `BASE_ZIP`/`BASE_LINUX` of the build scripts and
  in the `BASELINES` table of `dist/check_release_pkg.py`. The inventories are identical
  to 1.1.17 — 45 files on Windows, 137 on Linux — so the same 5 and 3 contents change.
  The 1.1.18 `grub.cfg` calls `vt_timeout_lock` / `vt_theme_lock` / `terminal_lock` /
  `lockfont`, which only exist in a GRUB built from 1.1.18 sources: that is what these
  packages ship.

## Documentation

| Document | What it covers |
|---|---|
| [docs/BUILD-PACKAGES.md](docs/BUILD-PACKAGES.md) | Building and publishing the binary packages, the three package checks |
| [docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md) | Upstream Ventoy 1.1.18: feature list, tested OS, plugins, Secure Boot, official docs |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | Release mechanics: tag, `MOVE_TAG=1`, preflight, test bench |
| [dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md) | Secure Boot MOK enrollment |
| [PERF_FINDINGS.md](PERF_FINDINGS.md) | Performance measurements |
| [DOC/BuildVentoyFromSource.txt](DOC/BuildVentoyFromSource.txt) | Upstream build instructions |

## Upstream Ventoy

The fork changes the boot-menu sort and the Linux GUI layout. Everything else is upstream
Ventoy 1.1.18, unchanged: the full feature list, the tested-OS tables, the plugins, Secure
Boot and the official documentation index are all kept in
[docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md), together with what upstream
v1.1.18 added.

Upstream site: <https://www.ventoy.net> · [FAQ](https://www.ventoy.net/en/faq.html)
· [Forum](https://forums.ventoy.net)
