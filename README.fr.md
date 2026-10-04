# Ventoy — fork ventoy-fork

[![CI](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Endymi0n74/ventoy-fork)](https://github.com/Endymi0n74/ventoy-fork/releases/latest)

**Langue / Language:** Français | [English](README.md)

Fork de [ventoy/Ventoy](https://github.com/ventoy/Ventoy) **v1.1.17 upstream exact**
(`7cbdc5cf`) : une amélioration ciblée du tri des images du menu de démarrage, et des
paquets Windows et Linux prêts à l'emploi reconstruits depuis les sources.

Ventoy est un outil libre qui rend une clé USB amorçable : on y copie des images
ISO/WIM/IMG/VHD(x)/EFI et on choisit celle à démarrer. Tout ce qui suit à propos des
fonctions de Ventoy vient de l'amont ; voir [Ventoy amont](#ventoy-amont).

## Dernière version stable

**[v1.1.20-ventoy-sort](https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.20-ventoy-sort)**
— publiée le 2026-10-04, tag annoté sur le commit `da7af651`.

| Type | Asset | Contenu | SHA-256 |
|---|---|---|---|
| Archive source | [Ventoy-v1.1.20-ventoy-sort.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/Ventoy-v1.1.20-ventoy-sort.zip) | Sources complètes, à compiler soi-même | `6eb3e3aa03ae15c454fb6b9fe907e7a8e24a88cdd76d71cbb3221700da13d505` |
| Archive source | [Ventoy-v1.1.20-ventoy-sort.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/Ventoy-v1.1.20-ventoy-sort.tar.gz) | Sources complètes, à compiler soi-même | `0313f22d144911b9b0acb22952fdecc8c7b15308c14e4ba4b8b6b641dcdd3689` |
| Paquet binaire (Windows) | [ventoy-1.1.20-ventoy-sort-windows.zip](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/ventoy-1.1.20-ventoy-sort-windows.zip) | Prêt à l'emploi ; 45 fichiers, 5 diffèrent de l'officiel 1.1.17 | `a68944d7a49136f3c81b712be9c223e5130aec1aaaf2db5e988b416d136bbbdc` |
| Paquet binaire (Linux) | [ventoy-1.1.20-ventoy-sort-linux.tar.gz](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/ventoy-1.1.20-ventoy-sort-linux.tar.gz) | Prêt à l'emploi ; 137 fichiers, 3 diffèrent de l'officiel 1.1.17 | `f27e2b898dd7c0a42102bac85e54ee4cbecbc50706a20b058374f3ecbd58db20` |
| Sommes | [SHA256SUMS](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/SHA256SUMS) | Couvre les deux archives sources | — |
| Sommes | [SHA256SUMS-ventoy-sort-windows.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/SHA256SUMS-ventoy-sort-windows.txt) | Couvre le zip Windows + 10 artefacts de build | — |
| Sommes | [SHA256SUMS-ventoy-sort-linux.txt](https://github.com/Endymi0n74/ventoy-fork/releases/download/v1.1.20-ventoy-sort/SHA256SUMS-ventoy-sort-linux.txt) | Couvre le tar.gz Linux + 8 artefacts de build | — |

Les deux premiers sont des **archives sources**, pas des builds installables. Les deux
paquets binaires sont à copier sur une clé USB.

## Installation

1. Télécharger le paquet de sa plateforme et vérifier son SHA-256.
2. Sous Windows, extraire `ventoy-1.1.20-ventoy-sort-windows.zip` ; sous Linux, extraire
   `ventoy-1.1.20-ventoy-sort-linux.tar.gz`.
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
celle du fork en compte 17 et débordait de son cadre, par-dessus `exFAT` et `MBR`. Qt :
fenêtre 441 → 660 px, cadres de version 205 → 315 px, et une taille de police calculée à
l'exécution entre 20 pt et un plancher de 9 pt. GTK : libellés 120 → 305 px. WebUI :
`.vtoy_ver` en largeur intrinsèque, boîtes 250 → 430 px. `Ventoy2Disk.pro` avait aussi des
chemins d'inclusion absolus `/home/panda/...`, désormais relatifs.

**Il s'agit d'un correctif au niveau des sources.** Les paquets binaries publiés
embarquent le runtime officiel Ventoy 1.1.17 : la fenêtre Qt redessinée n'y est **pas**.

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
  indépendantes ; le paquet Linux a été construit une seule fois, sur un `ubuntu-24.04`
  épinglé, car la version du compilateur change les octets produits par GRUB.

## Documentation

| Document | Contenu |
|---|---|
| [docs/BUILD-PACKAGES.md](docs/BUILD-PACKAGES.md) | Construction et publication des paquets binaires, les trois contrôles package |
| [docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md) | Ventoy amont 1.1.17 : fonctions, plateformes éprouvées, greffons, Secure Boot, documentation officielle |
| [RELEASE_NOTES.md](RELEASE_NOTES.md) | Mécanique de publication : tag, `MOVE_TAG=1`, préflight, banc de test |
| [dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md) | Enrôlement de la clé MOK Secure Boot |
| [PERF_FINDINGS.md](PERF_FINDINGS.md) | Mesures de performance |
| [DOC/BuildVentoyFromSource.txt](DOC/BuildVentoyFromSource.txt) | Instructions de build amont |

## Ventoy amont

Le fork change le tri du menu de démarrage et la mise en page de la GUI Linux. Tout le
reste est Ventoy amont 1.1.17, inchangé : la liste complète des fonctions, les tables de
plateformes éprouvées, les greffons, Secure Boot et l'index de la documentation
officielle sont tous conservés dans
[docs/UPSTREAM-FEATURES.md](docs/UPSTREAM-FEATURES.md).

Site amont : <https://www.ventoy.net> · [FAQ](https://www.ventoy.net/en/faq.html)
· [Forum](https://forums.ventoy.net)
