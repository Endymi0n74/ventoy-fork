# Construction et publication des paquets binaires

Document de référence pour les mainteneurs du fork **ventoy-fork**
(<https://github.com/Endymi0n74/ventoy-fork>) : comment les paquets binaires
`ventoy-<version>-windows.zip` et `ventoy-<version>-linux.tar.gz` sont
construits depuis les sources, vérifiés, puis attachés à une release GitHub.

La mécanique de publication elle-même (tag, `MOVE_TAG=1`, préflight, banc de
test) est décrite dans [RELEASE_NOTES.md](../RELEASE_NOTES.md). L’enrôlement de
la clé Secure Boot est détaillé dans
[`PROCEDURE-SECURE-BOOT.md`](../dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md).

## Vue d’ensemble

| | Windows | Linux |
|---|---|---|
| Workflow | `build-package.yml` | `build-package-linux.yml` |
| Runner | `windows-2022` + Ubuntu sous WSL | `ubuntu-24.04` (épinglé) |
| Outillage | MSVC, superviseur PowerShell/WSL | GCC natif + cross `aarch64-linux-gnu` |
| Script | `build_ventoy_sort_windows.sh` | `build_ventoy_sort_linux.sh` |
| Sortie | `ventoy-<version>-windows.zip` | `ventoy-<version>-linux.tar.gz` |
| Fichiers modifiés vs 1.1.17 | 5 sur 45 | 3 sur 137 |
| Certificat MOK embarqué | `8A:78:E8:AC:…:25:AA:89` | identique |

Le runner Linux est figé sur `ubuntu-24.04` et non `ubuntu-latest` : la version
du compilateur change les octets produits par GRUB et déplacerait
silencieusement l’empreinte publiée d’une release à l’autre.

`GUI_REBUILD` reste désactivé des deux côtés : le garde-fou d’ABI refuse la
substitution sur une toolchain récente, et les paquets embarquent donc les
binaires GUI officiels.

## Publier les paquets binaires

Les deux workflows partagent les mêmes garde-fous : échec sans les secrets MOK,
baseline officielle épinglée par SHA-256, aucun envoi tant que les trois
contrôles et la comparaison du certificat n’ont pas réussi, et asset déjà
publié laissé intact sauf `clobber`.

### 1. Configurer la clé Secure Boot (une seule fois)

Dans le dépôt GitHub, ouvrir **Settings → Secrets and variables → Actions** et créer ces deux *repository secrets* :

- `ventoy_sort_mok_key` : clé privée MOK en PEM, non chiffrée ;
- `ventoy_sort_mok_crt` : certificat X.509 correspondant, en PEM.

Depuis WSL Ubuntu, à la racine du dépôt, utiliser pour un build local existant les fichiers sous `dist/ventoy-sort-build/secureboot/` (`ventoy-sort-mok.key` et `ventoy-sort-mok.crt`). Sinon, créer la paire aux chemins attendus par le build local, puis copier leur contenu dans les deux secrets GitHub :

```bash
mkdir -p dist/ventoy-sort-build/secureboot
openssl req -newkey rsa:2048 -nodes -sha256 \
  -keyout dist/ventoy-sort-build/secureboot/ventoy-sort-mok.key \
  -x509 -new -days 36500 -subj "/CN=ventoy-sort fork MOK/" \
  -out dist/ventoy-sort-build/secureboot/ventoy-sort-mok.crt
```

Ils doivent former une paire valide. Ainsi, les builds locaux et le CI utilisent le même certificat. La clé privée ne doit jamais être ajoutée au dépôt, imprimée dans les logs ni envoyée comme argument de commande. Le workflow la transmet à WSL via `WSLENV`, vérifie la paire et compare le certificat embarqué dans l’image du paquet au certificat secret avant tout envoi. En cas de secret absent ou invalide, le job échoue sans publier. Ne pas renouveler cette clé à la légère : les utilisateurs devraient enrôler le nouveau certificat Secure Boot.

### 2. Déclenchement automatique à la publication

Publier une release stable avec la procédure habituelle, par exemple `dist\make_release.cmd <tag>`. Une fois la release publiée, GitHub Actions lance *Release package* sur un runner `windows-2022` ; celui-ci installe Ubuntu 24.04 dans WSL et reconstruit le zip depuis zéro, avec GRUB recompilé pour quatre cibles, exécutables MSVC et signatures Secure Boot. Le workflow ne s’exécute pas sur un simple push et ignore les prereleases. La version du paquet doit respecter le format stable `X.Y.Z-ventoy-sort`. Pour que le déclenchement automatique soit disponible, le workflow `.github/workflows/build-package.yml` doit être présent sur la branche par défaut du dépôt et le commit du tag doit contenir les scripts de build requis. Pour un ancien tag qui ne les contient pas, utiliser le déclenchement manuel ci-dessous avec `--ref master`.

Le job télécharge et vérifie la baseline officielle 1.1.17 épinglée par SHA-256, exécute le banc d’import MOK, construit le paquet, puis lance les trois contrôles de `dist/check_release_pkg.py` : empreinte, marqueur du fork dans les chargeurs EFI et comparaison de l’inventaire/contenu à la baseline. Il vérifie aussi que le certificat MOK secret est bien celui embarqué dans l’image disque. **L’upload n’a lieu qu’après la réussite de toutes ces étapes.** Compter environ 45 à 50 minutes ; suivre le job *Windows binary package (WSL + MSVC) and upload* dans l’onglet **Actions**.

### 3. Déclenchement manuel ou remplacement volontaire

Pour construire ou relancer le paquet d’une release existante, installer et authentifier GitHub CLI (`gh auth login`), puis exécuter depuis un terminal :

```bash
gh workflow run build-package.yml --repo Endymi0n74/ventoy-fork --ref master -f tag=v1.2.0-ventoy-sort
```

Remplacer `v1.2.0-ventoy-sort` par le tag stable voulu. Une release associée à ce tag doit déjà exister. `--ref master` sélectionne la branche contenant le workflow et les scripts ; vérifier qu’elle comprend les changements à publier. Les prereleases ne sont pas prises en charge, car leur suffixe échoue au contrôle de version du paquet.

Par défaut, si `ventoy-<version>-windows.zip` est déjà présent, le workflow n’envoie rien et conserve les assets existants tels quels — cela protège les références des notes de version. La présence du zip déclenche ce comportement même si le fichier de sommes est absent. Pour envoyer ou réparer les deux assets ensemble, ou **remplacer délibérément** le paquet après un changement du build, passer `clobber=true` :

```bash
gh workflow run build-package.yml --repo Endymi0n74/ventoy-fork --ref master -f tag=v1.2.0-ventoy-sort -f clobber=true
```

Le remplacement utilise `gh release upload --clobber` pour le zip et `SHA256SUMS-ventoy-sort-windows.txt`. Ne l’utiliser que si cette modification d’empreinte est voulue et que les notes de release seront mises à jour en conséquence.

### 4. Vérifier les assets publiés

Après le succès du job, la release doit contenir `ventoy-<version>-windows.zip` et `SHA256SUMS-ventoy-sort-windows.txt`. Depuis la racine du dépôt, vérifier toute la release et appliquer les trois contrôles package à l’asset téléchargé :

```bat
set "TAG=v1.2.0-ventoy-sort"
set "SKIP_SWEEP=1"
dist\check_release.cmd
```

`SKIP_SWEEP=1` omet seulement le sweep de performance ; l’étape 6 continue de contrôler chaque paquet présent. Les journaux de l’action donnent aussi le résultat des contrôles, l’égalité des empreintes du certificat (`embedded` / `supplied`) et la liste finale des assets.

Pour créer une nouvelle release : `dist\make_release.cmd <tag>` (dry-run avec `set DRY_RUN=1`). Pour mettre à jour une release **existante** après déplacement de son tag, prévisualiser avec `set DRY_RUN=1`, puis passer `MOVE_TAG=1` et confirmer le nom exact : `set MOVE_TAG=1` puis `set CONFIRM_MOVE_TAG=v1.1.18-ventoy-sort`, et lancer `dist\make_release.cmd v1.1.18-ventoy-sort`. Le mode vérifie le tag distant et la release GitHub, refuse les releases immuables, brouillonne une release publiée le temps de l’opération, déplace le tag annoté, recrée les archives sources et `SHA256SUMS`, remplace uniquement les deux archives sources et `SHA256SUMS` (les autres assets sont conservés), et actualise les notes en conservant stable/prerelease et l’état draft/publié. **Attention :** `gh release upload --clobber` supprime l’ancien asset avant d’envoyer le nouveau ; aussi les trois assets sont-ils d’abord sauvegardés dans `DIST_DIR\.asset-backup` : si un envoi échoue en cours de route, les anciens assets sont **restaurés automatiquement** (un échec de cette sauvegarde arrête le script avant toute modification ; le dossier est conservé pour réparation manuelle). Après déplacement du tag, la release reste en brouillon pour permettre la reprise ; si elle était publiée initialement, elle devra ensuite être republiée manuellement après vérification. Avant un déplacement réel, lancer le workflow GitHub *Preflight move-tag* (onglet Actions, ou `gh workflow run preflight-move-tag.yml -f tag=<tag>`, avec `-f commit_sha=<head attendu>` en option) : il échoue fermement si le tag n’existe pas, si aucune release n’y est attachée (drafts compris), si celle-ci est immuable ou si la cible annoncée ne correspond pas au head de la branche ; le même contrôle verrouille le job release-e2e à chaque publication de release. Toujours prévisualiser avec `DRY_RUN=1`.

Exemple de job summary GO pour `v1.1.18-ventoy-sort` :

**Prérequis : clang et Python 3 uniquement.** Docker, WSL et une machine virtuelle ne sont pas nécessaires.

## Vérifier un paquet publié

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

## Build reproductible du paquet Windows

La procédure de build repose sur un superviseur PowerShell commun aux lanceurs Windows/Linux, qui évite de dépendre d’un `sleep infinity` externe et relance le build en cas d’arrêt brutal de WSL. Les détails, réglages et test CI sont consignés dans les [notes de version](../RELEASE_NOTES.md).

Le dépôt contient un script unique qui régénère de zéro le paquet Windows complet à partir du code du fork et de l’archive officielle 1.1.17 — charge utiles GRUB recompilées (BIOS + UEFI64 + UEFI32 + UEFI arm64), exes Ventoy2Disk, image disque patchée, signatures Secure Boot avec la clé MOK locale — puis prouve sa propre reproductibilité :

- `dist/ventoy-sort-build/build_ventoy_sort_windows.sh` — le script (exécuté sous WSL) ;
- `dist/ventoy-sort-build/build_ventoy_sort_windows.cmd` — le lanceur Windows, protégé par le superviseur WSL commun ; détails et réglages dans les [notes de version](../RELEASE_NOTES.md).

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

> **Ce que cette procédure prouve, et sa limite.** Rejouer le build dans le **même** dossier montre seulement que le build est *idempotent* à cet emplacement : c’est ce qui était vérifié jusqu’ici, et cela ne détecte pas un paquet qui dépend du chemin du checkout. C’est exactement le défaut qui affectait le paquet Linux (chemins absolus gravés dans les modules GRUB) : deux runs consécutifs étaient identiques, deux racines isolées ne l’étaient pas. Pour une preuve qui couvre le lieu du build, utiliser deux racines isolées — c’est ce que fait `dist/tests/test_linux_reproducibility.sh` pour le paquet Linux. Le paquet **Windows** n’est pas couvert par ce banc : `build_ventoy_sort_windows.sh` ne projette pas encore les chemins de compilation de GRUB, donc son résultat est connu seulement au chemin exact du build.

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

Le script `dist/ventoy-sort-build/_cmp_runs.sh`, qui automatisait cette comparaison plus poussée (artefacts bruts, puis chaque entrée du zip : CRC, taille, dates, offsets), a été **retiré**. Il était figé sur la version `1.1.18-ventoy-sort` et lisait un instantané d'arborescence (`work/`, `pkg/`, `_run5/`) que les scripts de build ne produisent plus : il ne pouvait plus aboutir. La méthode manuelle ci-dessus reste valable ; pour une vérification reproductible de bout en bout, le banc `bash dist/tests/test_linux_reproducibility.sh` rejoue le build dans deux racines isolées et compare les paquets qu'il obtient.

```bash
cp -a work/core.img work/grubx64_real.efi work/grubia32_real.efi work/BOOTAA64.EFI \
      pkg/ventoy-1.1.18-ventoy-sort/Ventoy2Disk.exe \
      pkg/ventoy-1.1.18-ventoy-sort/altexe/Ventoy2Disk_X64.exe \
      pkg/ventoy-1.1.18-ventoy-sort/boot/core.img.xz \
      pkg/ventoy-1.1.18-ventoy-sort/ventoy/ventoy.disk.img.xz \
      pkg/ventoy-1.1.18-ventoy-sort/ventoy/version \
      SHA256SUMS-ventoy-sort-windows.txt PROCEDURE-SECURE-BOOT.md \
      ventoy-sort-MOK.cer _ref/
```

Référence sur la chaîne d’outils de référence (gcc 15.2, VS2022 v143, Ubuntu WSL, sbsigntool 0.9.4) :

```
dafb5c09942a780e34c71daf5a5f17bd48d52c8929be9298dfb006b6e3373818  ventoy-1.1.18-ventoy-sort-windows.zip
```

Avec le bras arm64 (remplacement et signature de `BOOTAA64.EFI` dans l’image), le zip de référence devient `cf50aa74d3b66e50e4aedcfeb7b5b2f2e543646d2aaf101ecf3d3eb934493501` ; l’empreinte ci-dessus reste celle du build **sans** bras arm64.

**Reproductibilité MSVC x64 vérifiée** : `/Brepro` est appliqué à la compilation (`ClCompile`) **et** au linker (`Link`). Le flag linker seul rendait les `.obj` variables (timestamp COFF de l’heure courante), ce qui propageait les écarts dans `.text`/`.rdata`/`.pdata` de l’EXE. Avec `/Brepro` aux deux étapes, deux rebuilds à froid au chemin exact du script donnent les 29 `.obj` et `Ventoy2Disk_X64.exe` identiques bit à bit ; aucun besoin de supprimer `/m` ni d’ajouter `/d1trimfile`. L’EXE retombe sur le hash publié `2243af58…`.

### Ce qui rend le build déterministe

- **MSVC** : `/Brepro` sur compilation et lien (stabilise aussi les timestamps COFF des `.obj`), `WholeProgramOptimization=false`, PDB supprimés avant l’édition de liens (âge CodeView).
- **GRUB** : tarball figé (sha256 consigné), dates normalisées 2019 (autotools), `-std=gnu17 -Os`, et — build Linux seulement — projection de la racine de build sur un préfixe constant (`-ffile-prefix-map`, `-fmacro-prefix-map`, et `TARGET_CCASFLAGS` pour les `.S`) : sans cela, les modules embarquaient le chemin absolu du checkout et le paquet dépendait de l’emplacement du build. Un garde-fou échoue le build si un chemin réapparaît dans un `*.module` ou `kernel.img`.
- **Paquet** : mtimes officielles restaurées sur les cinq fichiers remplacés, horodatages FAT ré-écrits après `mcopy`, `zip -q -r -X` (pas de champs extra horodatés).
- **Signatures** : `strip` puis `sbsign` sous `LD_PRELOAD=fixedtime.so` (temps figé au 2027-01-01T00:00:00Z) — la RSA PKCS#1 v1.5 est déjà déterministe, seule la `signingTime` faisait varier les octets d’un build à l’autre. `sbverify --cert` suit chaque signature.
- **Hors périmètre** : `BUILD-MANIFEST-*.txt` contient la date de build — il diffère normalement d’un run à l’autre et n’est pas couvert par `SHA256SUMS`. Une **autre** chaîne d’outils (autre version gcc/MSVC) produit des octets différents : les versions sont consignées dans le manifeste.

Un harnais QEMU (`dist/ventoy-sort-build/_qemu/`) permet en complément de vérifier le démarrage BIOS et UEFI du paquet dans une machine virtuelle, sans clé USB physique.

## Build reproductible du paquet Linux

Le même principe existe pour le paquet Linux : le lanceur `.cmd` utilise le même superviseur PowerShell et bénéficie des mêmes reprises WSL. Un script unique régénère de zéro `ventoy-<version>-linux.tar.gz` à partir de l’archive officielle 1.1.17, couvrant **quatre** plateformes — BIOS (i386-pc), UEFI x64, UEFI ia32 **et UEFI arm64** — puis prouve sa propre reproductibilité :

- `dist/ventoy-sort-build/build_ventoy_sort_linux.sh` — le script (exécuté sous WSL) ;
- `dist/ventoy-sort-build/build_ventoy_sort_linux.cmd` — le lanceur Windows, protégé par le même superviseur WSL.

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

Préflight (outils, cross arm64, sbsigntool, clé MOK, shim de temps figé, téléchargement épinglé), puis étapes numérotées :

1. **build GRUB 2.04** en quatre plateformes — arm64-efi d’abord (cross `aarch64-linux-gnu-*`, options reprises à l’identique de `GRUB2/buildgrub.sh`), puis i386-pc, x86_64-efi, i386-efi ; le marqueur `Ventoy img list count mismatch` est vérifié dans les quatre `ventoy.mod` installés.
2. **charges utiles GRUB** — `core.img`, `grubx64_real.efi`, `grubia32_real.efi`, `BOOTAA64.EFI` via les commandes `grub-mkimage` exactes de `install.sh` (listes `all_modules_legacy` / `all_modules_uefi` / `all_modules_arm64_uefi`), puis signature des trois chargeurs.
3. **préparation du paquet** depuis l’archive officielle — les mtimes des trois fichiers à remplacer sont capturés.
4. **reconstruction optionnelle de la GUI Qt** (`GUI_REBUILD=1`) — ABI x86_64 validée contre la baseline, remplacement refusé si les symboles glibc/Qt requis sont plus récents.
5. **patch de l’image disque + signatures Secure Boot** — remplacement des chargeurs x64/ia32 et de `BOOTAA64.EFI` (en 1.1.17, ce dernier est le chargeur GRUB arm64 lui-même, sans shim), empreinte x64 dans `fbx64.efi`, version dans `grub.cfg`, re-signature de tous les PE x64/ia32/arm64 concernés (`ventoy_*`, `iso9660_*`, `udf_*`, `vtoyutil_*`, `wimboot*` via décompresser → signer → re-compresser), certificat `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`, restauration des horodatages FAT.
6. **assemblage** — `core.img.xz` rembourré à 2047 secteurs, mtimes officielles restaurées, tar déterministe (`--sort=name --owner=0 --format=gnu`, `gzip -n`).
7. **empreintes + manifeste** — `SHA256SUMS-ventoy-sort-linux.txt` + `BUILD-MANIFEST-*-linux.txt`.
8. **vérifications finales** (voir ci-dessous).

### La GUI Linux dans le paquet

Par défaut, le paquet reprend **tel quel** le runtime de l’archive officielle, GUI comprise : les corrections de mise en page ci-dessus ne deviennent visibles qu’après reconstruction. `GUI_REBUILD=1` compile la GUI Qt x86_64 et compare ses exigences de symboles GLIBC et Qt à la baseline officielle. Le WSL Ubuntu 26.04 utilisé ici exige GLIBC_2.38 et Qt_5.15, contre GLIBC_2.14 et Qt_5.9 pour la GUI officielle : le script refuse cette substitution et laisse le paquet intact. Le paquet comporte aussi des GUI i386, aarch64 et mips64el ; elles ne sont jamais remplacées par le binaire natif x86_64.

```bash
apt install -y qtbase5-dev qtbase5-dev-tools qt5-qmake   # prérequis de cette étape
GUI_REBUILD=1 bash dist/ventoy-sort-build/build_ventoy_sort_linux.sh
```

Elle est désactivée par défaut parce que la compilation est native x86_64 alors que le paquet contient aussi des GUI i386, aarch64 et mips64el. Seul le binaire x86_64 peut être remplacé et seulement si ses prérequis GLIBC et Qt ne dépassent pas ceux de la GUI officielle. Avec la toolchain présente ici, le garde-fou ABI interrompt donc le build avant la substitution. Deux pièges ont été rencontrés et sont consignés dans l’en-tête du script : le `.pro` amont pointait sur des chemins absolus `/home/panda/...` (désormais relatifs à `$$PWD`), et `qmake` doit être lancé depuis la **racine** du projet `Ventoy2Disk`, pas depuis `QT/`.

Deux tests gardent cette mise en page honnête :

```bash
python3 dist/tests/test_gui_version_layout.py   # cadres déclarés vs largeur réelle du texte
bash    dist/tests/test_gui_render.sh           # compile la GUI et REND la fenêtre hors écran (PNG)
```

Le second est le seul qui dise quelque chose de l’écran : il instancie la vraie forme `.ui`, appelle le vrai `Ventoy2DiskWindow::SetVersionLabel()` et compare la largeur du texte **rendu** au cadre. Il sort en 0 si le texte tient, 1 s’il déborde, 2 si Qt5 est absent. La capture est écrite dans `dist/tests/out/`. Le paquet local déjà assemblé conserve les binaires Qt officiels ; sa GUI ne bénéficie donc pas encore du nouveau layout.

### Sorties

- `ventoy-<version>-linux.tar.gz` — le paquet ;
- `SHA256SUMS-ventoy-sort-linux.txt` — empreintes de l’archive, des trois payloads, de `core.img` et des trois chargeurs, du certificat ;
- `BUILD-MANIFEST-<version>-linux.txt` — chaîne d’outils et empreintes détaillées ;
- `pkg-linux/` (paquet extrait) et `secureboot/` (clé privée — **jamais** empaquetée).

### Vérifications intégrées (échec = arrêt du build)

- marqueur du fork présent dans les `ventoy.mod` des **quatre** plateformes ;
- `sbverify --cert` sur les trois chargeurs recompilés, sur `fbx64.efi`, `grubia32.efi` et les payloads `ventoy/*` + `wimboot*` relus depuis l’image, avec la clé MOK locale ;
- garde-fous : échec si un haché de `grubia32_real.efi` ou de `BOOTAA64.EFI` apparaissait déjà dans l’image officielle (extension du patch à prévoir), échec si le `signingTime` n’est pas figée ;
- **reproductibilité** : sonde de préflight — le build échoue si le compilateur natif ou le cross arm64 refuse `-ffile-prefix-map`/`-fmacro-prefix-map` ; puis, après chaque `make install`, échec si un `*.module` ou un `kernel.img` contient encore le chemin de la racine de build (c’est la régression qui faisait diverger deux racines distinctes) ;
- intégrité `xz -t`, `gzip -t`, `tar -tzf` ;
- comparaison à l’archive officielle : mêmes noms de fichiers (137 fichiers), trois contenus de base modifiés (`boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun manquant ni superflu. Si `GUI_REBUILD=1` et que l’ABI passe, le remplacement x86_64 de la GUI est également autorisé.

### Reproductibilité : ce qui est vérifié, et jusqu’où

**Vérifié.** Deux builds complets, lancés dans deux racines isolées de longueurs différentes (gcc 15.2, binutils 2.46, sbsigntool 0.9.4, WSL Ubuntu), donnent le même octet :

```
e8bf8179317df0c03219366d80177136c3f6a50cb35ca777b3a30aaef66071c2  ventoy-1.1.19-ventoy-sort-linux.tar.gz
```

Le banc est rejouable et fait partie du dépôt :

```bash
bash dist/tests/test_linux_reproducibility.sh      # deux builds isolés + comparaison
REPRO_DRY_RUN=1 bash dist/tests/test_linux_reproducibility.sh   # prérequis seuls
```

Il prépare deux racines jetables, copie le script et `GRUB2/MOD_SRC` dans chacune (le script n'écrit jamais dans le dépôt), impose la **même** clé MOK des deux côtés, compare les archives octet à octet, nomme les entrées divergentes en cas d'échec, et vérifie qu'aucun chemin de build n'a survécu dans `boot/core.img.xz`. Compter ~7 minutes. Sortie 0 = identiques, 1 = divergence.

**Ce qui avait été corrigé pour y arriver.** Deux builds consécutifs au **même** emplacement étaient déjà identiques avant ce correctif — cette vérification ne prouve donc rien sur le lieu du build. En réalité, gcc grave le chemin absolu de la racine dans ce qu'il produit : `__FILE__` (assert de `minilzo.c`), le DWARF, et le symbole `FILE` du dossier de compilation pour les quelques fichiers `.S` de GRUB. Ces chaînes se retrouvent dans les `.module`, donc dans `core.img` et les chargeurs UEFI ; deux racines différentes divergeaient alors sur `boot/core.img.xz` et `ventoy/ventoy.disk.img.xz` (1 088 fichiers de `grub-install` sur 2 211). Le script projette maintenant la racine sur un préfixe constant via `-ffile-prefix-map` et `-fmacro-prefix-map`, y compris dans `TARGET_CCASFLAGS` — sans quoi les `.S` compilés par automake continuaient de fuiter — et un garde-fou fait échouer le build si un chemin subsiste dans un artefact livré. `SOURCE_DATE_EPOCH` ne traitait ni l'un ni l'autre.

**Ce qui n'est pas vérifié.**

- Entre **chaînes d'outils différentes** (autre GCC, autre binutils) : les octets changent. La reproductibilité est vérifiée à outilchain identique, pas d'un environnement à l'autre.
- Le paquet **publié** `8eb88265…` a été construit **avant** ce correctif : le script actuel ne le reproduit pas, et le reconstruire donne `e8bf8179…`. Republier le paquet Linux est nécessaire pour que l'empreinte publiée soit reproductible.
- Le build **Windows** n'a pas reçu le correctif : `build_ventoy_sort_windows.sh` ne projette pas les chemins de GRUB, donc son paquet dépend de l'emplacement du checkout. Seul le build au chemin exact du script a été vérifié.

`BUILD-MANIFEST-*-linux.txt` contient la date de build et diffère normalement d'un run à l'autre ; il n'est pas couvert par `SHA256SUMS`.

### Démarrage validé dans QEMU (sans clé USB)

Le harnais `dist/ventoy-sort-build/_qemu/` couvre les quatre chemins depuis une image disque brute construite avec la géométrie Ventoy officielle (p1 données FAT32 @LBA2048, p2 EFI 32 Mio) et douze ISO factices écrites en désordre :

| Chemin | Firmware | Commande | Résultat |
|---|---|---|---|
| BIOS | SeaBIOS | `build_test_disk.sh cli` + `run_vm.sh bios` | menu « Ventoy … BIOS », 12/12 triés, navigation VGA |
| UEFI x64 | OVMF 4M | `run_vm.sh uefi` | menu « … UEFI », 12/12 triés |
| UEFI ia32 | OVMF 32 bits | `_probe_ovmf32.sh` puis `run_vm.sh uefi32` | menu « … IA32 », 12/12 triés |
| UEFI arm64 | AAVMF | `build_test_disk_a64.sh` + `run_vm_a64.sh` (machine `virt`, virtio-blk, usb-kbd) | menu « … AA64 », 12/12 triés, navigation clavier vérifiée |

Aucun « Ventoy img list count mismatch » ni blocage dans les logs. Deux limites honnêtes : Secure Boot n’est pas enrôlé dans ces VM (la validité des signatures est vérifiée par `sbverify`, pas par un démarrage SB réel), et les tests roulent des ISO factices (menu et tri, pas de démarrage ISO complet). Le mode `serial_console` du harnais préfixe `grub.cfg` à des fins de lecture — le paquet livré reste inchangé.

## Limites connues

La validation couvre la logique du tri et sa parité structurelle avec le code de production. **Un démarrage réel depuis une clé USB avec le GRUB modifié n’a pas été validé**, et l’image ISO complète n’a pas été reconstruite. Le déploiement utilise les runtimes officiels v1.1.17, qui ne contiennent pas notre modification de GRUB.

Les résultats de performance détaillés et les notes de version sont disponibles dans [PERF_FINDINGS.md](../PERF_FINDINGS.md) et [RELEASE_NOTES.md](../RELEASE_NOTES.md).

## Garder le README honnête

Publier une release sans mettre à jour les README laisse des sommes fausses et
des liens périmés que les lecteurs recopient. Le contrôle est automatisé :

```bash
python dist/check_readme_release.py            # contrôles 1 à 5 (réseau)
python dist/check_readme_release.py --offline  # cohérence EN/FR seule, hors-ligne
```

Cinq contrôles, sortie `RESULTAT : PASS|FAIL` et code de retour 0/1 :

1. **cohérence** — les deux README déclarent le même tag, les mêmes assets et les
   mêmes sommes ;
2. **tag** — chaque release annoncée existe, et `/releases/latest` pointe bien sur
   celle annoncée : une release plus récente publiée sans mise à jour fait
   échouer le contrôle ;
3. **assets** — le tableau énumère exactement les assets publiés, et chaque URL de
   téléchargement est celle renvoyée par l’API ;
4. **sommes** — tout fichier téléchargeable annonce une empreinte, et chaque
   SHA-256 est conforme aux fichiers `SHA256SUMS*` joints à la release ;
5. **liens externes** — site amont, FAQ, badges : un échec donne un avertissement,
   sauf si `--strict-links` est passé.

Les paquets ne sont jamais téléchargés : les sommes sont lues dans les
`SHA256SUMS*` publiés (197 à 1 112 octets). Le contrôle 4 compare donc le README
à la référence **publiée** ; recalculer l’empreinte d’un paquet de 80 Mo reste le
travail de `check_release_pkg.py`.

Les sommes sont lues **où qu’elles soient** : dans le tableau des assets, ou
dans la liste « `asset` — `somme` » qui le suit. Cette liste n’est pas un détail
cosétique : GitHub rend les tables en `display:block; overflow-x:auto` avec une
largeur `max-content`, donc une colonne d’empreintes de 64 caractères imposait un
défilement horizontal même sur grand écran. Les sommes sont sorties du tableau
pour cette raison, et restent complètes et vérifiables — une puce peut se couper,
une cellule non.

Le job CI **`README vs published release`** (`ci.yml`) le lance à chaque push sur
`master` et à chaque publication de release. `GH_TOKEN` y lève le quota de l’API,
qui est de 60 requêtes/h en anonyme et partagé entre les runners.

> Le contrôle 2 a déjà payé : les README annonçaient une release
> « précédente » en `v1.1.19-ventoy-sort`. Le tag Git existe, mais aucune release
> ne lui est attachée — l’API répond 404 alors que la page HTML répond 200. Un
> simple test HTTP ne l’aurait pas vu. C’est aussi pourquoi le dépôt n’a qu’une
> seule release pour l’instant, et pourquoi les README n’en citent aucune autre.

## Ce qui reste à faire à la main

Les workflows couvrent le build et l’attachement. Restent manuels :

- la **clé MOK**, provisionnée une fois dans les secrets du dépôt. Ne pas la
  renouveler sans raison : les utilisateurs devraient ré-enrôler un nouveau
  certificat ;
- les **notes de release**, rédigées dans `RELEASE_NOTES.md` puis
  `RELEASE_NOTES-<version>.md` ; le corps publié doit annoncer les empreintes
  réellement attachées ;
- la lecture du rapport du job : contrôles, comparaison du certificat
  (`embedded` / `supplied`) et liste finale des assets.
