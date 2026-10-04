# Ventoy — ventoy-fork

[![CI](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Endymi0n74/ventoy-fork)](https://github.com/Endymi0n74/ventoy-fork/releases/latest)

**Language / Langue:** English | [Français](README.fr.md)

A fork of [ventoy/Ventoy](https://github.com/ventoy/Ventoy) **v1.1.17** (`7cbdc5cf`)
that adds a focused improvement to boot-menu image sorting, and publishes ready-to-boot
Windows and Linux packages rebuilt from source.

Ventoy itself is an open source tool to create bootable USB drives: copy ISO/WIM/IMG/
VHD(x)/EFI files onto a drive and pick one from a boot menu. Everything below about
Ventoy's own capabilities is upstream's; see [Upstream Ventoy](#upstream-ventoy).

## Latest release

**[v1.1.20-ventoy-sort](https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.20-ventoy-sort)**
— published 2026-10-04, annotated tag on commit `da7af651`.

| Type | Asset | Contents | SHA-256 |
|---|---|---|---|
| Source archive | [Ventoy-v1.1.20-ventoy-sort.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/Ventoy-v1.1.20-ventoy-sort.zip) | Full source tree; compile it yourself | `6eb3e3aa03ae15c454fb6b9fe907e7a8e24a88cdd76d71cbb3221700da13d505` |
| Source archive | [Ventoy-v1.1.20-ventoy-sort.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/Ventoy-v1.1.20-ventoy-sort.tar.gz) | Full source tree; compile it yourself | `0313f22d144911b9b0acb22952fdecc8c7b15308c14e4ba4b8b6b641dcdd3689` |
| Binary package (Windows) | [ventoy-1.1.20-ventoy-sort-windows.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/ventoy-1.1.20-ventoy-sort-windows.zip) | Ready-to-use; 45 files, 5 differ from official 1.1.17 | `a68944d7a49136f3c81b712be9c223e5130aec1aaaf2db5e988b416d136bbbdc` |
| Binary package (Linux) | [ventoy-1.1.20-ventoy-sort-linux.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/ventoy-1.1.20-ventoy-sort-linux.tar.gz) | Ready-to-use; 137 files, 3 differ from official 1.1.17 | `f27e2b898dd7c0a42102bac85e54ee4cbecbc50706a20b058374f3ecbd58db20` |
| Checksums | [SHA256SUMS](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/SHA256SUMS) | Covers the two source archives | — |
| Checksums | [SHA256SUMS-ventoy-sort-windows.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/SHA256SUMS-ventoy-sort-windows.txt) | Covers the Windows zip + 10 build artifacts | — |
| Checksums | [SHA256SUMS-ventoy-sort-linux.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/SHA256SUMS-ventoy-sort-linux.txt) | Covers the Linux tar.gz + 8 build artifacts | — |

The first two are **source archives**, not installable builds. The two binary packages are
ready to copy to a USB drive.

## Installing

1. Download the package for your platform above and verify its SHA-256.
2. On Windows, extract `ventoy-1.1.20-ventoy-sort-windows.zip`; on Linux, extract
   `ventoy-1.1.20-ventoy-sort-linux.tar.gz`.
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
string is 17 characters and overflowed its frame, over `exFAT` and `MBR`. Qt: window
441 → 660 px, version frames 205 → 315 px, and a runtime font size between 20 pt and a
9 pt floor. GTK: version labels 120 → 305 px. WebUI: `.vtoy_ver` uses intrinsic width,
boxes 250 → 430 px. `Ventoy2Disk.pro` also had absolute `/home/panda/...` include paths,
now relative, so the project builds outside its original author's machine.

**This is a source-level fix.** The published binary packages embed the official Ventoy
1.1.17 runtime, so the redrawn Qt window is **not** in them.

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
  Linux package was built once, on a pinned `ubuntu-24.04` because the compiler version
  changes GRUB's output bytes.

## Documentation

| Document | What it covers |
|---|---|
| [docs/BUILD-PACKAGES.md](docs/BUILD-PACKAGES.md) | Building and publishing the binary packages, the three package checks |
| [docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md) | Upstream Ventoy 1.1.17: feature list, tested OS, plugins, Secure Boot, official docs |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | Release mechanics: tag, `MOVE_TAG=1`, preflight, test bench |
| [dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md) | Secure Boot MOK enrollment |
| [PERF_FINDINGS.md](PERF_FINDINGS.md) | Performance measurements |
| [DOC/BuildVentoyFromSource.txt](DOC/BuildVentoyFromSource.txt) | Upstream build instructions |

## Upstream Ventoy

The fork changes the boot-menu sort and the Linux GUI layout. Everything else is upstream
Ventoy 1.1.17, unchanged: the full feature list, the tested-OS tables, the plugins, Secure
Boot and the official documentation index are all kept in
[docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md).

Upstream site: <https://www.ventoy.net> · [FAQ](https://www.ventoy.net/en/faq.html)
· [Forum](https://forums.ventoy.net)
