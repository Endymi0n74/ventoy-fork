# Ventoy — fork ventoy-fork

**Langue / Language:** Français | [English](README.md)

[![CI](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/Endymi0n74/ventoy-fork/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Endymi0n74/ventoy-fork)](https://github.com/Endymi0n74/ventoy-fork/releases/latest)

- **Dernière version stable :** [v1.1.18-ventoy-sort](https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.18-ventoy-sort)
- **Version de test :** [v1.1.19-ventoy-sort-rc1](https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.19-ventoy-sort-rc1) — prerelease utilisée pour tester le workflow CI de publication ; ce n’est pas la version stable.

Ce fork est basé sur [ventoy/Ventoy](https://github.com/ventoy/Ventoy) **v1.1.17 upstream exact** (`7cbdc5cf`). Il apporte une amélioration ciblée au tri des images du menu Ventoy.

## Améliorations

- Remplace le tri par sélection **O(n²)** par un **tri fusion stable O(n log n)**. Les images dont les noms sont égaux conservent leur ordre de découverte.
- Vérifie que le nombre d’images enregistré correspond à la longueur réelle de la liste avant le tri ; en cas d’écart, un message est affiché et le traitement continue.
- Corrige un bug de découpage de liste qui pouvait bloquer la construction du menu de démarrage dès trois images.

## Validation

Le fork comprend un harnais autonome d’environ 30 tests : comparateurs, stabilité, intégrité des liens, cas limites et parité structurelle avec le code de production pour des listes de 1 à 64 éléments. Les compilations utilisent `-Wall -Wextra -Werror`.

À la racine du dépôt, lancer sous Windows :

```bat
python build_sort_test.py
python build_sort_test.py --perf
```

Le chemin de clang peut être défini par la variable d’environnement `CLANG`. Sinon, le script recherche `C:\Program Files\LLVM\bin\clang.exe`, puis `clang` dans le `PATH`.

Le workflow GitHub Actions exécute les tests normaux et le mode performance à chaque push sur `master`. À la publication d’une release, il télécharge les archives, vérifie `SHA256SUMS`, extrait le ZIP, lance un sweep de performance sur 30 seeds puis relance le harnais. Pour rejouer ce contrôle manuellement :

```bat
dist\check_release.cmd
```

Le sweep peut être omis pour une vérification rapide avec `set SKIP_SWEEP=1`.

Pour créer une nouvelle release : `dist\make_release.cmd <tag>` (dry-run avec `set DRY_RUN=1`). Pour mettre à jour une release **existante** après déplacement de son tag, prévisualiser avec `set DRY_RUN=1`, puis passer `MOVE_TAG=1` et confirmer le nom exact : `set MOVE_TAG=1` puis `set CONFIRM_MOVE_TAG=v1.1.18-ventoy-sort`, et lancer `dist\make_release.cmd v1.1.18-ventoy-sort`. Le mode vérifie le tag distant et la release GitHub, refuse les releases immuables, brouillonne une release publiée le temps de l’opération, déplace le tag annoté, recrée les archives sources et `SHA256SUMS`, remplace uniquement les deux archives sources et `SHA256SUMS` (les autres assets sont conservés), et actualise les notes en conservant stable/prerelease et l’état draft/publié. **Attention :** `gh release upload --clobber` supprime l’ancien asset avant d’envoyer le nouveau ; aussi les trois assets sont-ils d’abord sauvegardés dans `DIST_DIR\.asset-backup` : si un envoi échoue en cours de route, les anciens assets sont **restaurés automatiquement** (un échec de cette sauvegarde arrête le script avant toute modification ; le dossier est conservé pour réparation manuelle). Après déplacement du tag, la release reste en brouillon pour permettre la reprise ; si elle était publiée initialement, elle devra ensuite être republiée manuellement après vérification. Avant un déplacement réel, lancer le workflow GitHub *Preflight move-tag* (onglet Actions, ou `gh workflow run preflight-move-tag.yml -f tag=<tag>`, avec `-f commit_sha=<head attendu>` en option) : il échoue fermement si le tag n’existe pas, si aucune release n’y est attachée (drafts compris), si celle-ci est immuable ou si la cible annoncée ne correspond pas au head de la branche ; le même contrôle verrouille le job release-e2e à chaque publication de release. Toujours prévisualiser avec `DRY_RUN=1`.

**Prérequis : clang et Python 3 uniquement.** Docker, WSL et une machine virtuelle ne sont pas nécessaires.

## Build reproductible du paquet Windows

Le dépôt contient un script unique qui régénère de zéro le paquet Windows complet à partir du code du fork et de l’archive officielle 1.1.17 — charge utiles GRUB recompilées (BIOS + UEFI64 + UEFI32 + UEFI arm64), exes Ventoy2Disk, image disque patchée, signatures Secure Boot avec la clé MOK locale — puis prouve sa propre reproductibilité :

- `dist/ventoy-sort-build/build_ventoy_sort_windows.sh` — le script (exécuté sous WSL) ;
- `dist/ventoy-sort-build/build_ventoy_sort_windows.cmd` — le lanceur Windows (convertit le chemin et transmet les arguments `NOM=valeur`).

### Prérequis

- **Windows 10/11 + WSL2** avec la distribution **Ubuntu** (`wsl -d Ubuntu -- uname -a` doit répondre) ; le script refuse Git Bash.
- Paquets sous Ubuntu (WSL) :

  ```bash
  apt install -y build-essential autoconf automake libtool pkg-config \
      libfreetype-dev python3 openssl mtools xz-utils zip unzip git curl \
      sbsigntool gcc-aarch64-linux-gnu
  ```

  (`gh` est un substitut facultatif à `curl` pour le téléchargement du tarball GRUB.)
- **Windows : Visual Studio 2022** (BuildTools suffit) avec le composant **MSVC v143** — le script détecte MSBuild et impose `/Brepro`, `WholeProgramOptimization=false` et des répertoires de sortie dédiés.
- L’**archive officielle** `ventoy-1.1.17-windows.zip` (variable `BASE_ZIP=`, voir le lanceur).
- ~2 Go d’espace disque ; **aucun espace dans le chemin** du dépôt (contrainte `OutDir` de MSBuild).
- Réseau au premier build uniquement (tarball `grub-2.04.tar.xz` téléchargé puis conservé ; sinon passer `GRUB_TARBALL=`).
- Au premier lancement, une **clé MOK** est générée dans `secureboot/` et réutilisée ensuite pour tous les builds ; elle n’est jamais incluse dans le paquet.

### Étapes du pipeline

Préflight (outils, cross arm64, sbsigntool, clé MOK, shim de temps figé, détection MSBuild) et préparation des sources GRUB (tarball + overlay des fichiers patchés du fork + `autogen.sh`), puis huit étapes numérotées :

1. **build GRUB 2.04** en quatre plateformes — arm64-efi d’abord (cross `aarch64-linux-gnu-*`, options reprises à l’identique de `GRUB2/buildgrub.sh`), puis i386-pc, x86_64-efi, i386-efi ; le tri fusion y est embarqué ; le marqueur `Ventoy img list count mismatch` est recherché dans les quatre `ventoy.mod` installés.
2. **charges utiles GRUB** — `core.img`, `grubx64_real.efi`, `grubia32_real.efi`, `BOOTAA64.EFI` via les commandes `grub-mkimage` exactes de `install.sh` (listes `all_modules_legacy` / `all_modules_uefi` / `all_modules_arm64_uefi`), puis signature des trois chargeurs.
3. **exes Ventoy2Disk** (Win32 + x64) — MSBuild `/Brepro`.
4. **préparation du paquet** depuis l’archive officielle — les mtimes des cinq fichiers qui seront remplacés sont capturés.
5. **patch de l’image disque + signatures Secure Boot** — remplacement des chargeurs x64/ia32 et de `BOOTAA64.EFI` (en 1.1.17, ce dernier est le chargeur GRUB arm64 lui-même, sans shim), empreinte x64 dans `fbx64.efi`, version dans `grub.cfg`, re-signature de la liste x64+ia32+aa64 (décompresser → signer → re-compresser pour les `.xz`), certificat `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`, restaurations des horodatages FAT.
6. **assemblage** — `core.img.xz` rembourré, mtimes officielles restaurées, `zip -q -r -X`.
7. **empreintes + manifeste** — `SHA256SUMS-ventoy-sort-windows.txt` + `BUILD-MANIFEST-*.txt` (versions de la chaîne d’outils, empreintes).
8. **vérifications finales** (voir ci-dessous).

Le journal complet est écrit dans `run-full.log` (et `log-*.txt` par sous-composant). Variables utiles : `BASE_ZIP=`, `FORK_VERSION=`, `GRUB_TARBALL=`, `KEEP=1` (conserve les sources pour un rebuild plus rapide).

### Sorties

- `ventoy-<version>-windows.zip` — le paquet ;
- `SHA256SUMS-ventoy-sort-windows.txt` — empreintes du zip, des exes, des charges utiles, de l’image et du certificat ;
- `BUILD-MANIFEST-<version>.txt` — chaîne d’outils et empreintes détaillées ;
- `ventoy-sort-MOK.cer` + `PROCEDURE-SECURE-BOOT.md` — certificat public et procédure d’enrôlement MOK ;
- `pkg/` (paquet extrait) et `secureboot/` (clé privée — **jamais** empaquetée).

### Vérifications intégrées (échec = arrêt du build)

- marqueur du fork présent dans les `ventoy.mod` des **quatre** plateformes ;
- `sbverify --cert` sur les trois chargeurs (x64, ia32, arm64) avec la clé MOK locale ;
- `sbverify --cert` sur tout ce qui est relu depuis l’image finale — `fbx64.efi`, `grubia32.efi`, chargeurs recompilés, payloads `ventoy/*` + `wimboot*` — et certificat public conforme ;
- intégrité `xz -t` et `unzip -tq` ;
- comparaison au zip officiel : mêmes noms de fichiers, **exactement cinq contenus modifiés** (`Ventoy2Disk.exe`, `altexe/Ventoy2Disk_X64.exe`, `boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun fichier manquant ni superflu ;
- signingTime de chaque signature contrôlée figée à `2027-01-01T00:00:00Z` (sinon le build échoue).

### Procédure de vérification de la reproductibilité

Principe : **builder deux fois de suite** avec la même chaîne d’outils et comparer les empreintes — environ 25 minutes par build.

1. Premier build (depuis la racine du dépôt) :

   ```bat
   dist\ventoy-sort-build\build_ventoy_sort_windows.cmd
   ```

2. Conserver l’instantané de référence (sous WSL, dans `dist/ventoy-sort-build/`) :

   ```bash
   mkdir -p _ref
   cp -a ventoy-*-windows.zip SHA256SUMS-ventoy-sort-windows.txt _ref/
   ```

3. Relancer **la même commande** du build, puis comparer :

   ```bash
   diff _ref/SHA256SUMS-ventoy-sort-windows.txt SHA256SUMS-ventoy-sort-windows.txt
   sha256sum _ref/ventoy-*-windows.zip ventoy-*-windows.zip
   ```

**Critère de succès :** `diff` ne produit aucune ligne et les deux sha256 du zip sont identiques. `SHA256SUMS` couvrant le zip, les deux exes, `core.img.xz`, `ventoy.disk.img.xz`, `version`, `work/core.img`, les deux chargeurs et le certificat, son identité prouve l’identité octet à octet de l’ensemble.

Pour une comparaison plus poussée (artefacts bruts + chaque entrée du zip : CRC, taille, dates, offsets ; script figé sur la version `1.1.18-ventoy-sort`) :

```bash
cp -a work/core.img work/grubx64_real.efi work/grubia32_real.efi work/BOOTAA64.EFI \
      pkg/ventoy-1.1.18-ventoy-sort/Ventoy2Disk.exe \
      pkg/ventoy-1.1.18-ventoy-sort/altexe/Ventoy2Disk_X64.exe \
      pkg/ventoy-1.1.18-ventoy-sort/boot/core.img.xz \
      pkg/ventoy-1.1.18-ventoy-sort/ventoy/ventoy.disk.img.xz \
      pkg/ventoy-1.1.18-ventoy-sort/ventoy/version \
      SHA256SUMS-ventoy-sort-windows.txt PROCEDURE-SECURE-BOOT.md \
      ventoy-sort-MOK.cer _ref/
bash _cmp_runs.sh _ref    # tout doit afficher IDENTIQUE, aucune ligne DIFF
```

Référence sur la chaîne d’outils de référence (gcc 15.2, VS2022 v143, Ubuntu WSL, sbsigntool 0.9.4) :

```
dafb5c09942a780e34c71daf5a5f17bd48d52c8929be9298dfb006b6e3373818  ventoy-1.1.18-ventoy-sort-windows.zip
```

Avec le bras arm64 (remplacement et signature de `BOOTAA64.EFI` dans l’image), le zip de référence devient `cf50aa74d3b66e50e4aedcfeb7b5b2f2e543646d2aaf101ecf3d3eb934493501` ; l’empreinte ci-dessus reste celle du build **sans** bras arm64.

**Réserve observée (MSVC, honnête)** : sur deux builds complets consécutifs du même jour, `altexe/Ventoy2Disk_X64.exe` a différé une fois (le code généré s’écarte de quelques centaines d’octets dispersés malgré `/Brepro` — observé sous charge machine ; le relink isolé reproduit ensuite la référence). Chargeurs GRUB, image disque, `core.img` et exe Win32 restent reproductibles bit à bit (vérifiés sur trois runs). En cas d’écart sur ce fichier : relancer le build ; l’empreinte `SHA256SUMS` publiée fait foi pour l’archive publiée.

### Ce qui rend le build déterministe

- **MSVC** : `/Brepro`, `WholeProgramOptimization=false`, PDB supprimés avant l’édition de liens (âge CodeView).
- **GRUB** : tarball figé (sha256 consigné), dates normalisées 2019 (autotools), `-std=gnu17 -Os`.
- **Paquet** : mtimes officielles restaurées sur les cinq fichiers remplacés, horodatages FAT ré-écrits après `mcopy`, `zip -q -r -X` (pas de champs extra horodatés).
- **Signatures** : `strip` puis `sbsign` sous `LD_PRELOAD=fixedtime.so` (temps figé au 2027-01-01T00:00:00Z) — la RSA PKCS#1 v1.5 est déjà déterministe, seule la `signingTime` faisait varier les octets d’un build à l’autre. `sbverify --cert` suit chaque signature.
- **Hors périmètre** : `BUILD-MANIFEST-*.txt` contient la date de build — il diffère normalement d’un run à l’autre et n’est pas couvert par `SHA256SUMS`. Une **autre** chaîne d’outils (autre version gcc/MSVC) produit des octets différents : les versions sont consignées dans le manifeste.

Un harnais QEMU (`dist/ventoy-sort-build/_qemu/`) permet en complément de vérifier le démarrage BIOS et UEFI du paquet dans une machine virtuelle, sans clé USB physique.

## Build reproductible du paquet Linux

Le même principe existe pour le paquet Linux : un script unique régénère de zéro `ventoy-<version>-linux.tar.gz` à partir de l’archive officielle 1.1.17, couvrant **quatre** plateformes — BIOS (i386-pc), UEFI x64, UEFI ia32 **et UEFI arm64** — puis prouve sa propre reproductibilité :

- `dist/ventoy-sort-build/build_ventoy_sort_linux.sh` — le script (exécuté sous WSL) ;
- `dist/ventoy-sort-build/build_ventoy_sort_linux.cmd` — le lanceur Windows (convertit le chemin et transmet les arguments `NOM=valeur`).

Différence assumée avec le packaging amont (`INSTALL/ventoy_pack.sh`, qui reconstruit tout via `losetup`) : ce script ne monte rien et ne remplace que les charges utiles GRUB et les signatures — tous les binaires runtime de l’archive officielle (tools, GUI, WebUI, scripts) sont repris tels quels, même approche que le script Windows.

### Prérequis

- **WSL2 Ubuntu** (comme le build Windows ; le script refuse Git Bash). Pas de MSBuild ni de contrainte d’espace dans le chemin.
- Paquets sous Ubuntu (WSL) — ceux du build Windows **plus** le cross-compilateur arm64 :

  ```bash
  apt install -y build-essential autoconf automake libtool pkg-config \
      libfreetype-dev python3 openssl mtools xz-utils zip unzip git curl \
      sbsigntool gcc-aarch64-linux-gnu
  ```

- L’**archive officielle** `ventoy-1.1.17-linux.tar.gz` — téléchargée automatiquement et vérifiée contre un sha256 épinglé si absente (`BASE_LINUX=`/`BASE_LINUX_URL=`).
- ~25 minutes et ~2 Go d’espace disque ; la clé MOK de `secureboot/` est réutilisée (générée au premier build, jamais empaquetée).

### Étapes du pipeline

Préflight (outils, cross arm64, sbsigntool, clé MOK, shim de temps figé, téléchargement épinglé), puis sept étapes numérotées :

1. **build GRUB 2.04** en quatre plateformes — arm64-efi d’abord (cross `aarch64-linux-gnu-*`, options reprises à l’identique de `GRUB2/buildgrub.sh`), puis i386-pc, x86_64-efi, i386-efi ; le marqueur `Ventoy img list count mismatch` est vérifié dans les quatre `ventoy.mod` installés.
2. **charges utiles GRUB** — `core.img`, `grubx64_real.efi`, `grubia32_real.efi`, `BOOTAA64.EFI` via les commandes `grub-mkimage` exactes de `install.sh` (listes `all_modules_legacy` / `all_modules_uefi` / `all_modules_arm64_uefi`), puis signature des trois chargeurs.
3. **préparation du paquet** depuis l’archive officielle — les mtimes des trois fichiers à remplacer sont capturés.
4. **patch de l’image disque + signatures Secure Boot** — remplacement des chargeurs x64/ia32 et de `BOOTAA64.EFI` (en 1.1.17, ce dernier est le chargeur GRUB arm64 lui-même, sans shim), empreinte x64 dans `fbx64.efi`, version dans `grub.cfg`, re-signature de tous les PE x64/ia32/arm64 concernés (`ventoy_*`, `iso9660_*`, `udf_*`, `vtoyutil_*`, `wimboot*` via décompresser → signer → re-compresser), certificat `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`, restauration des horodatages FAT.
5. **assemblage** — `core.img.xz` rembourré à 2047 secteurs, mtimes officielles restaurées, tar déterministe (`--sort=name --owner=0 --format=gnu`, `gzip -n`).
6. **empreintes + manifeste** — `SHA256SUMS-ventoy-sort-linux.txt` + `BUILD-MANIFEST-*-linux.txt`.
7. **vérifications finales** (voir ci-dessous).

### Sorties

- `ventoy-<version>-linux.tar.gz` — le paquet ;
- `SHA256SUMS-ventoy-sort-linux.txt` — empreintes de l’archive, des trois payloads, de `core.img` et des trois chargeurs, du certificat ;
- `BUILD-MANIFEST-<version>-linux.txt` — chaîne d’outils et empreintes détaillées ;
- `pkg-linux/` (paquet extrait) et `secureboot/` (clé privée — **jamais** empaquetée).

### Vérifications intégrées (échec = arrêt du build)

- marqueur du fork présent dans les `ventoy.mod` des **quatre** plateformes ;
- `sbverify --cert` sur les trois chargeurs recompilés, sur `fbx64.efi`, `grubia32.efi` et les payloads `ventoy/*` + `wimboot*` relus depuis l’image, avec la clé MOK locale ;
- garde-fous : échec si un haché de `grubia32_real.efi` ou de `BOOTAA64.EFI` apparaissait déjà dans l’image officielle (extension du patch à prévoir), échec si le `signingTime` n’est pas figée ;
- intégrité `xz -t`, `gzip -t`, `tar -tzf` ;
- comparaison à l’archive officielle : mêmes noms de fichiers (137 fichiers), **exactement trois contenus modifiés** (`boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun manquant ni superflu.

### Reproductibilité prouvée

Deux runs complets sur la même chaîne d’outils (gcc 15.2, sbsigntool 0.9.4, WSL Ubuntu) : l’archive est **identique octet à octet** —

```
d23c014f1e272a2cb627b27e45d43227d7f0b1bc8e2e7e6ad03a3e140f4903ca  ventoy-1.1.18-ventoy-sort-linux.tar.gz
```

Les sorties x86 sont restées bit à bit identiques à celles des runs **sans** arm64 (`core.img` `e87ddc9f…`, `grubx64_real.efi` `f11050f6…`, `grubia32_real.efi` `5f143737…`) : le build croisé s’insère sans déplacer quoi que ce soit. Les mécanismes déterministes sont ceux du build Windows (dates 2019, mtimes officielles restaurées, horodatages FAT réécrits, `gzip -n`), moins MSVC et plus le tar trié ; `BUILD-MANIFEST-*-linux.txt` contient la date de build et diffère normalement d’un run à l’autre.

### Démarrage validé dans QEMU (sans clé USB)

Le harnais `dist/ventoy-sort-build/_qemu/` couvre les quatre chemins depuis une image disque brute construite avec la géométrie Ventoy officielle (p1 données FAT32 @LBA2048, p2 EFI 32 Mio) et douze ISO factices écrites en désordre :

| Chemin | Firmware | Commande | Résultat |
|---|---|---|---|
| BIOS | SeaBIOS | `build_test_disk.sh cli` + `run_vm.sh bios` | menu « Ventoy … BIOS », 12/12 triés, navigation VGA |
| UEFI x64 | OVMF 4M | `run_vm.sh uefi` | menu « … UEFI », 12/12 triés |
| UEFI ia32 | OVMF 32 bits | `_probe_ovmf32.sh` puis `run_vm.sh uefi32` | menu « … IA32 », 12/12 triés |
| UEFI arm64 | AAVMF | `build_test_disk_a64.sh` + `run_vm_a64.sh` (machine `virt`, virtio-blk, usb-kbd) | menu « … AA64 », 12/12 triés, navigation clavier vérifiée |

Aucun « Ventoy img list count mismatch » ni blocage dans les logs. Deux limites honnêtes : Secure Boot n’est pas enrôlé dans ces VM (la validité des signatures est vérifiée par `sbverify`, pas par un démarrage SB réel), et les tests roulent des ISO factices (menu et tri, pas de démarrage ISO complet). Le mode `serial_console` du harnais préfixe `grub.cfg` à des fins de lecture — le paquet livré reste inchangé.

## Vérification rapide d’un paquet

Trois contrôles manuels pour valider un paquet **reçu** (zip Windows ou tar.gz Linux) sans refaire de build — sous WSL Ubuntu avec `xz`, `mtools`, `sha256sum` et `diff` (déjà installés pour les builds). Les commandes se lancent depuis `dist/ventoy-sort-build/` ; le marqueur cherché est celui du correctif : `Ventoy img list count mismatch`.

Ces trois contrôles sont **automatisés** dans `dist/check_release_pkg.py` (Python standard, sans WSL ni mtools — lit directement zip/tar/FAT16), lui-même appelé par `dist/check_release.cmd` à l'étape 6 quand la release contient des paquets (ou via `PKG_DIR=`) :

```bat
python dist\check_release_pkg.py ventoy-1.1.18-ventoy-sort-windows.zip ventoy-…-linux.tar.gz
```

La baseline officielle 1.1.17 y est identifiée par sha256 épinglé (`--baseline-dir` pour changer de dossier).

### 1. Empreintes

```bash
# Archive seule (paquet téléchargé) : comparer au sha256 publié dans SHA256SUMS-…txt
sha256sum ventoy-1.1.18-ventoy-sort-windows.zip      # ou ventoy-…-linux.tar.gz

# Arborescence de build complète : tout le fichier doit passer
sha256sum -c SHA256SUMS-ventoy-sort-windows.txt      # ou SHA256SUMS-ventoy-sort-linux.txt
```

`SHA256SUMS` référence aussi `pkg*/` et `work/` : `sha256sum -c` ne passe en entier que dans l’arborescence de build. Sur un paquet seul, le contrôle utile est la première ligne (l’archive elle-même) ; le manifeste `BUILD-MANIFEST-*.txt` publié avec la release consigne les empreintes détaillées.

### 2. Marqueur du fork

```bash
mkdir -p /tmp/vcheck && cd /tmp/vcheck
# adapter le chemin si l’archive n’est pas dans le dossier courant :
unzip -q ventoy-1.1.18-ventoy-sort-windows.zip                    # ou tar -xzf ventoy-…-linux.tar.gz
P=ventoy-1.1.18-ventoy-sort

cat "$P/ventoy/version"                                              # 1.1.18-ventoy-sort

# BIOS : le marqueur n’est PAS cherchable dans core.img — grub-mkimage compresse
# les modules (xz) à l’intérieur du core BIOS, le texte n’y figure pas en clair.
# La preuve pour le BIOS passe par l’empreinte du fichier livré (le build étant
# déterministe, toute modification du module changerait ces octets) :
sha256sum "$P/boot/core.img.xz"
# à comparer à la ligne « …/boot/core.img.xz » de SHA256SUMS-ventoy-sort-….txt

# UEFI x64 / ia32 / arm64 : extraire les chargeurs de l’image disque
xz -dc "$P/ventoy/ventoy.disk.img.xz" > vtoy.img
for f in grubx64_real.efi grubia32_real.efi BOOTAA64.EFI; do
    mcopy -n -i vtoy.img ::/EFI/BOOT/"$f" "$f"
    grep -aq "Ventoy img list count mismatch" "$f" \
        && echo "$f : marqueur OK" || echo "$f : MARQUEUR ABSENT"
done
mtype -i vtoy.img ::/grub/grub.cfg | grep VENTOY_VERSION             # set VENTOY_VERSION="1.1.18-ventoy-sort"
```

**Critère de succès :** version `1.1.18-ventoy-sort`, la ligne `VENTOY_VERSION`, empreinte `core.img.xz` conforme à `SHA256SUMS`, et le marqueur dans **chaque chargeur EFI** (dans les PE, les modules GRUB ne sont pas compressés — contrairement au core BIOS — le texte y est donc cherchable tel quel). Deux réserves honnêtes : (a) le marqueur est **absent des payloads officiels** — c’est justement ce qui le distingue, mais le menu peut rester trié avec les payloads officiels (ils contiennent leur propre tri, moins prévisible) ; (b) les **zips Windows antérieurs à l’extension arm64** (par ex. l’archive empreintée `dafb5c09…`) contiennent encore le chargeur `BOOTAA64.EFI` officiel — pour ces archives-là, `MARQUEUR ABSENT` sur ce fichier est **attendu** ; les zip et tar.gz construits avec le bras arm64 le portent.

### 3. Comparaison à la baseline officielle 1.1.17

Extraire l’archive officielle à côté du paquet puis comparer les arborescences :

```bash
# côté officiel (adapter l’extraction à l’archive en votre possession)
unzip -q ventoy-1.1.17-windows.zip -d off && mv off/ventoy-1.1.17 off/fork
# ou, pour l’archive Linux : tar -xzf ventoy-1.1.17-linux.tar.gz -C off && mv off/ventoy-1.1.17 off/fork

# côté paquet à vérifier (déjà extrait à l’étape 2, on le renomme simplement)
mv "$P" fork
diff -rq off/fork fork
```

**Résultat attendu** — uniquement ces fichiers signalés « differ », aucun `Only in …` :

- zip Windows : `Ventoy2Disk.exe`, `altexe/Ventoy2Disk_X64.exe`, `boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version` ;
- tar.gz Linux : `boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`.

Toute autre ligne (fichier modifié en plus, manquant ou superflu) = paquet non conforme. Le script de build applique déjà ce contrôle en fin de pipeline (« vérifications finales ») ; la comparaison manuelle ci-dessus l’étend à un paquet déjà construit ou téléchargé.

## Limites connues

La validation couvre la logique du tri et sa parité structurelle avec le code de production. **Un démarrage réel depuis une clé USB avec le GRUB modifié n’a pas été validé**, et l’image ISO complète n’a pas été reconstruite. Le déploiement utilise les runtimes officiels v1.1.17, qui ne contiennent pas notre modification de GRUB.

Les résultats de performance détaillés et les notes de version sont disponibles dans [PERF_FINDINGS.md](PERF_FINDINGS.md) et [RELEASE_NOTES.md](RELEASE_NOTES.md).

## Documentation officielle de Ventoy

Pour l’installation et l’utilisation générales de Ventoy, consulter le [site officiel](https://www.ventoy.net/) et le [guide de démarrage](https://www.ventoy.net/en/doc_start.html).
