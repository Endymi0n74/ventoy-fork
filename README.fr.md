# Ventoy — fork ventoy-fork

[![CI](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Endymi0n74/ventoy-fork)](https://github.com/Endymi0n74/ventoy-fork/releases/latest)

**Langue / Language:** Français | [English](README.md)

Fork de [ventoy/Ventoy](https://github.com/ventoy/Ventoy) **v1.1.18 upstream**
(`6116894a`) : une amélioration ciblée du tri des images du menu de démarrage, et des
paquets Windows et Linux prêts à l'emploi reconstruits depuis les sources. Le merge
amont v1.1.18 a été fait le 2026-10-09 ; les paquets sont désormais reconstruits à
partir de l'archive officielle **1.1.18**, voir [Limites connues](#limites-connues).

Ventoy est un outil libre qui rend une clé USB amorçable : on y copie des images
ISO/WIM/IMG/VHD(x)/EFI et on choisit celle à démarrer. Tout ce qui suit à propos des
fonctions de Ventoy vient de l'amont ; voir [Ventoy amont](#ventoy-amont).

## Dernière version stable

**[v1.1.18-Fork](https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.18-Fork)**
— publiée le 2026-10-09, tag annoté sur le commit `df404c9e`.

| Type | Asset | Contenu |
|---|---|---|
| Archive source | [Ventoy-v1.1.18-Fork.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/Ventoy-v1.1.18-Fork.zip) | Sources complètes, à compiler soi-même |
| Archive source | [Ventoy-v1.1.18-Fork.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/Ventoy-v1.1.18-Fork.tar.gz) | Sources complètes, à compiler soi-même |
| Paquet binaire (Windows) | [ventoy-1.1.18-Fork-windows.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/ventoy-1.1.18-Fork-windows.zip) | Prêt à l'emploi ; 45 fichiers, 5 diffèrent de l'officiel 1.1.18 |
| Paquet binaire (Linux) | [ventoy-1.1.18-Fork-linux.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/ventoy-1.1.18-Fork-linux.tar.gz) | Prêt à l'emploi ; 137 fichiers, 3 diffèrent de l'officiel 1.1.18 |
| Sommes | [SHA256SUMS](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/SHA256SUMS) | Couvre les deux archives sources |
| Sommes | [SHA256SUMS-Fork-windows.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/SHA256SUMS-Fork-windows.txt) | Couvre le zip Windows + 10 artefacts de build |
| Sommes | [SHA256SUMS-Fork-linux.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.18-Fork/SHA256SUMS-Fork-linux.txt) | Couvre le tar.gz Linux + 8 artefacts de build |

Les deux premiers sont des **archives sources**, pas des builds installables. Les deux
paquets binaires sont à copier sur une clé USB.

### Vérifier un téléchargement

Empreinte SHA-256 complète des quatre fichiers téléchargeables, à confronter à ce que
donne `sha256sum` (ou `Get-FileHash`) :

- `Ventoy-v1.1.18-Fork.zip` — `18cef2d6c23c9a35abc80fe23837aaf41a6e0859159d23f62bd1456de314ebeb`
- `Ventoy-v1.1.18-Fork.tar.gz` — `7290719022cf69ae4d1876f216ac9a8cf12ec95d50894f5d1fbd78ae8d7be534`
- `ventoy-1.1.18-Fork-windows.zip` — `fccaf0b17c7de74d21c8c6f3a5527ad136baa203451d5d7dba72a01ef0933a4c`
- `ventoy-1.1.18-Fork-linux.tar.gz` — `474ace026a53300ac627da9a1458ced94d6f04a4fdc0106f4839b3b6a3b6ce60`

## Installation

1. Télécharger le paquet de sa plateforme et vérifier son SHA-256.
2. Sous Windows, extraire `ventoy-1.1.18-Fork-windows.zip` ; sous Linux, extraire
   `ventoy-1.1.18-Fork-linux.tar.gz`.
3. Écrire le dossier obtenu sur une clé USB, idéalement en **GPT** avec une partition
   **exFAT**.
4. Démarrer dessus et choisir une image dans le menu.

**Secure Boot.** Les chargeurs du fork sont signés avec sa propre clé MOK, pas celle de
Microsoft. Il faut soit désactiver Secure Boot, soit enrôler le certificat : sinon le
démarrage est refusé (`Verification failed: (0x1A) Security Violation`). Le certificat est
`ENROLL_THIS_KEY_IN_MOKMANAGER.cer` à la racine de la partition `ventoy` — ce **n'est pas**
un fichier `.cer` livré à côté du paquet. Empreinte :

    8A:78:E8:AC:D9:88:D6:1E:ED:FF:97:64:8A:82:0A:F1:87:E0:10:CA:83:E5:27:B9:FA:6C:E2:06:DF:25:AA:89

Procédure complète :
[`dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md`](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md).

## Ce que change ce fork

### Tri des images du menu

`GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_cmd.c` :

- Remplace le tri par sélection O(n²) par un **tri fusion stable O(n log n)**. Les images
  de noms égaux conservent leur ordre de découverte.
- **Correction de bug incluse** : la première version du split ne terminait pas la
  première moitié de liste, la fusion ré-consommait alors des nœuds et pouvait bloquer la
  construction du menu dès trois images.
- **Garde-fou de cohérence** : avant de trier, le nombre d'images enregistré est comparé à
  la longueur réelle ; un écart est signalé sur la console et le tri continue.

Mesuré de 32 à 16384 images (30 seeds, QPC) : ~1,4× à 32, ~8,7× à 512, ~22× à 2048,
~126× à 16384. Détails : [PERF_FINDINGS.md](PERF_FINDINGS.md).

### Version affichée dans la GUI Linux

Les interfaces amont sont dimensionnées pour une version de six caractères (`1.0.53`) ;
celle du fork en a compté 18 (`1.1.20-ventoy-sort`) et débordait de son cadre,
par-dessus `exFAT` et `MBR`. Qt :
fenêtre 441 → 660 px, cadres de version 205 → 315 px, et une taille de police calculée à
l'exécution entre 20 pt et un plancher de 9 pt. GTK : libellés 120 → 305 px. WebUI :
`.vtoy_ver` en largeur intrinsèque, boîtes 250 → 430 px. `Ventoy2Disk.pro` avait aussi des
chemins d'inclusion absolus `/home/panda/...`, désormais relatifs.

**Il s'agit d'un correctif au niveau des sources.** Les paquets binaires publiés
embarquent le runtime officiel Ventoy 1.1.18, GUI comprise — le build Linux conserve
volontairement les binaires officiels (`GUI_REBUILD` désactivé) — : la fenêtre Qt
redessinée n'y est **pas**.

## Valider le changement

Harnais de régression autonome — ni Docker, ni WSL, ni machine virtuelle, seulement
**clang** et **Python 3** :

```
python build_sort_test.py           # régressions (RC=0 attendu)
python build_sort_test.py --perf    # + comparaison de perf contre le tri naïf
```

Contrôle de release de bout en bout : `dist\check_release.cmd` télécharge les derniers
assets, vérifie `SHA256SUMS`, extrait l'archive, lance le sweep de 30 seeds puis le
harnais. `SKIP_SWEEP=1` saute le sweep.

## Limites connues

- **Aucun démarrage réel depuis une clé USB n'a été validé.** Le GRUB modifié a été
  éprouvé sous QEMU et OVMF, pas sur du matériel ; la construction d'une ISO de boot
  complète a été volontairement abandonnée.
- **Le correctif de GUI n'est livré qu'en source**, comme expliqué plus haut.
- Le paquet Windows a été reproduit à l'octet près lors de deux exécutions CI
  indépendantes ; le paquet Linux se construit sur un `ubuntu-24.04` épinglé, car la
  version du compilateur change les octets produits par GRUB
  (`dist/tests/test_linux_reproducibility.sh` le construit deux fois dans des arbres
  isolés et compare les deux).
- **Les paquets publiés sont construits à partir de l'archive officielle 1.1.18**,
  épinglée par SHA-256 dans `build-package*.yml`, dans `BASE_ZIP`/`BASE_LINUX` des
  scripts de build et dans la table `BASELINES` de `dist/check_release_pkg.py`. Les
  inventaires sont identiques à ceux de 1.1.17 — 45 fichiers sous Windows, 137 sous
  Linux — donc les mêmes 5 et 3 contenus changent. Le `grub.cfg` de 1.1.18 appelle
  `vt_timeout_lock` / `vt_theme_lock` / `terminal_lock` / `lockfont`, qui n'existent
  que dans un GRUB compilé à partir des sources 1.1.18 : c'est ce que livrent ces
  paquets.

## Documentation

| Document | Contenu |
|---|---|
| [docs/BUILD-PACKAGES.md](docs/BUILD-PACKAGES.md) | Construction et publication des paquets binaires, les trois contrôles package |
| [docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md) | Ventoy amont 1.1.18 : fonctions, plateformes éprouvées, greffons, Secure Boot, documentation officielle |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | Mécanique de publication : tag, `MOVE_TAG=1`, préflight, banc de test |
| [dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md) | Enrôlement de la clé MOK Secure Boot |
| [PERF_FINDINGS.md](PERF_FINDINGS.md) | Mesures de performance |
| [DOC/BuildVentoyFromSource.txt](DOC/BuildVentoyFromSource.txt) | Instructions de build amont |

## Ventoy amont

Le fork change le tri du menu de démarrage et la mise en page de la GUI Linux. Tout le
reste est Ventoy amont 1.1.18, inchangé : la liste complète des fonctions, les tables de
plateformes éprouvées, les greffons, Secure Boot et l'index de la documentation
officielle sont tous conservés dans
[docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md), avec ce que la version 1.1.18
apporte.

Site amont : <https://www.ventoy.net> · [FAQ](https://www.ventoy.net/en/faq.html)
· [Forum](https://forums.ventoy.net)
