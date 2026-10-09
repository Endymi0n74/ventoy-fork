# Notes de version — v1.1.18-Fork

Release stable du fork **ventoy-fork**
(<https://github.com/Endymi0n74/ventoy-fork>), basée sur **Ventoy upstream
v1.1.18** (`6116894a`, « 1.1.18 release »), intégrée par le merge
`d6007cab`.

Tag annoté **`v1.1.18-Fork`**. Cette release inaugure le rebranding du fork :
la version, le tag, les paquets et les fichiers de sommes portent désormais
`1.1.18-Fork` au lieu de `1.1.20-ventoy-sort`, et la base suit l'amont au
lieu de rester figée à 1.1.17.

Release précédente : `v1.1.20-ventoy-sort` (2026-10-04), toujours
téléchargeable — son contenu détaillé est archivé dans
`RELEASE_NOTES-v1.1.20.md`, celui de `v1.1.19` dans
`RELEASE_NOTES-v1.1.19.md`.

## 1. Synchronisation amont : v1.1.18

Le tri fusion stable du fork tient dans un seul fichier de l'arbre GRUB —
`GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_cmd.c` (113 ajouts,
37 retraits) : c'est le **seul** écart entre notre `GRUB2/` et celui de
l'amont. Le reste du fork vit hors de l'arbre GRUB (`dist/`, `docs/`,
tests, workflows).

Ce que la synchro `7cbdc5cf` (1.1.17) → `6116894a` (1.1.18) apporte —
77 fichiers, +2 910 / −323 :

- **Nouvelles commandes GRUB** : `vt_timeout_lock`, `vt_theme_lock`,
  `terminal_lock`, `lockfont` (`ventoy_cmd.c`, `ventoy.c`,
  `commands/terminal.c`, `font/font_cmd.c`, `kern/corecmd.c`). Le
  `grub.cfg` officiel de 1.1.18 les appelle : un paquet reconstruit sur
  des sources 1.1.17 les ignorerait, et les verrous de thème, de terminal
  et de polices seraient de fait contournables.
- Nouveaux chargeurs et parseur : `efifwsetup`, `syslinux_parse`, loaders
  `i386`, `arm64`, `mips64`.
- Partition ISO : nom dm stable `/dev/mapper/VentoyPart`, montage hors
  produit sur les distros grand public, montage ISO amélioré (CloneZilla),
  support expérimental des images de récupération SteamOS, ISO à base
  Syslinux personnalisables.
- Correctifs : persistance intermittente sur Ubuntu 24.04 (#3718),
  vérification Secure Boot Windows/WinPE en cas de politique ByPass
  (certificat Windows CA2011 révoqué), boot Grml 2026.09 (#3751),
  répertoires de hooks dracut, processus udev, Plugson « Boot Conf
  Replace » plafonné à 2 entrées par mode (#3727), commandes VtoyTool.
- `vt_img_extra_initrd_append` détecte le suffixe des modules noyau
  (`.ko`, `.ko.xz`, `.ko.zst`, …) au lieu de le deviner.

Le merge `d6007cab` s'est fait **sans conflit**, suivi de la documentation
de la nouvelle base (`9eebc8a4`, `0e7fc66b`).

## 2. Baseline officielle ré-épinglée sur 1.1.18

URL + SHA-256 de l'archive officielle sont épinglés partout où elle sert de
référence :

| où | fichier |
|---|---|
| workflow de paquet Windows | `.github/workflows/build-package.yml` |
| workflow de paquet Linux | `.github/workflows/build-package-linux.yml` |
| scripts de build | `BASE_ZIP` / `BASE_LINUX` (+ `BASE_LINUX_URL`, `BASE_LINUX_PIN`) |
| contrôles de paquet | `dist/check_release_pkg.py` (table `BASELINES`) |

- `ventoy-1.1.18-windows.zip` → `082c478e8c432e1ac653899fcf50e3a4077a2851bc6112b5ddd30545962164a9`
- `ventoy-1.1.18-linux.tar.gz` → `d86ff9de63d94c8b8f1f6b14d23c55af4b88e8207bf2893890892a6a97b1ad54`

Les inventaires sont **identiques** à ceux de 1.1.17 — 45 fichiers pour le
zip Windows, 137 pour le tar.gz Linux, mêmes noms — donc les garde-fous ne
changent pas : 5 contenus modifiés côté Windows (`Ventoy2Disk.exe`,
`altexe/Ventoy2Disk_X64.exe`, `boot/core.img.xz`,
`ventoy/ventoy.disk.img.xz`, `ventoy/version`), 3 côté Linux (les trois
derniers), aucun ajout ni retrait.

GRUB étant recompilé depuis les sources fusionnées, les commandes de la
section 1 sont bien présentes dans `boot/core.img.xz` et
`ventoy/ventoy.disk.img.xz`.

## 3. Rebranding en `1.1.18-Fork`

| élément | avant | maintenant |
|---|---|---|
| version dans le paquet | `1.1.20-ventoy-sort` | `1.1.18-Fork` |
| tag de release | `v1.1.20-ventoy-sort` | `v1.1.18-Fork` |
| paquet Windows | `ventoy-1.1.20-ventoy-sort-windows.zip` | `ventoy-1.1.18-Fork-windows.zip` |
| paquet Linux | `ventoy-1.1.20-ventoy-sort-linux.tar.gz` | `ventoy-1.1.18-Fork-linux.tar.gz` |
| archives source | `Ventoy-v1.1.20-ventoy-sort.{zip,tar.gz}` | `Ventoy-v1.1.18-Fork.{zip,tar.gz}` |
| sommes | `SHA256SUMS-ventoy-sort-{windows,linux}.txt` | `SHA256SUMS-Fork-{windows,linux}.txt` |

Côté outillage :

- `git describe` accepte **les deux** motifs `v*-Fork` et `v*-ventoy-sort`,
  l'historique des tags du fork reste donc lisible ;
- `dist/check_release_pkg.py` accepte
  `\d+\.\d+\.\d+-(ventoy-sort|Fork)` pour `ventoy/version`, et refuse
  toujours les suffixes `-rcN` : une prerelease n'est pas construite par
  les workflows, par choix ;
- le menu GRUB annonce « Ventoy 1.1.18-Fork » ; les contrôles QEMU
  (`dist/ventoy-sort-build/_qemu/*.sh`) reconnaissent les deux graphies ;
- `dist/check_release.cmd` et `dist/make_release.cmd` visent `v1.1.18-Fork`
  par défaut.

## 4. Le tri fusion stable du fork (inchangé)

`ventoy_img_merge` / `ventoy_img_msort` remplacent le tri par sélection
O(n²) de `ventoy_cmd_list_img()` : stabilité sur les noms égaux (l'ordre de
découverte est préservé), complexité O(n log n), reconstruction des
pointeurs `prev` en une seule passe, et vérification de cohérence en fin de
liste. La correction de la première version du split (blocage du menu au
boot dès 3 images) est incluse et couverte par une régression permanente.

Mesures (30 seeds, QPC) : ×1,4 à n=32, ×8,7 à n=512, ×22 à n=2048,
×126 à n=16384 — soit une croissance conforme à n log n.

## 5. Chaîne de release (inchangé)

- `dist\make_release.cmd <tag>` : arbre propre + synchronisé, tag annoté,
  `git archive`, `SHA256SUMS`, release en draft → upload → publication.
  `DRY_RUN=1`, `PRERELEASE=1`, et `MOVE_TAG=1` (avec
  `CONFIRM_MOVE_TAG=<tag>`) pour repositionner un tag existant avec
  sauvegarde et rollback des assets.
- La publication d'une release déclenche les **deux** workflows de paquet
  (Windows : WSL + MSVC, ~45-50 min ; Linux : `ubuntu-24.04` épinglé,
  ~5 min) qui valident le paquet via `dist/check_release_pkg.py`
  (empreinte, marqueur du fork dans les trois chargeurs EFI, inventaire et
  contenus vs baseline) **avant** l'attachement de l'asset, plus le contrôle
  du certificat MOK embarqué contre le secret du dépôt.
- Préflight *move-tag* + job `release-e2e` + banc `MOVE_TAG` (offline,
  146 assertions) couvrent le chemin de déplacement de tag.
- `dist/check_readme_release.py` confronte les README à la release
  publiée ; au moment même de la publication il accepte avec
  `--allow-newer-release` que `/releases/latest` soit déjà plus récent que
  la release annoncée (les binaires ne sont attachés qu'ensuite), tous les
  autres contrôles restant stricts.

## Assets

| asset | taille | sha256 |
|---|---|---|
| `Ventoy-v1.1.18-Fork.zip` | 83 040 516 o | `18cef2d6c23c9a35abc80fe23837aaf41a6e0859159d23f62bd1456de314ebeb` |
| `Ventoy-v1.1.18-Fork.tar.gz` | 81 516 259 o | `7290719022cf69ae4d1876f216ac9a8cf12ec95d50894f5d1fbd78ae8d7be534` |
| `ventoy-1.1.18-Fork-windows.zip` | 17 281 942 o | `fccaf0b17c7de74d21c8c6f3a5527ad136baa203451d5d7dba72a01ef0933a4c` |
| `ventoy-1.1.18-Fork-linux.tar.gz` | 20 907 791 o | `474ace026a53300ac627da9a1458ced94d6f04a4fdc0106f4839b3b6a3b6ce60` |
| `SHA256SUMS` | 183 o | couvre les deux archives sources |
| `SHA256SUMS-Fork-windows.txt` | 1 070 o | couvre le zip Windows et 10 artefacts de build |
| `SHA256SUMS-Fork-linux.txt` | 868 o | couvre le tar.gz Linux et 8 artefacts de build |

Les deux premiers sont des **archives sources**, à compiler soi-même. Les deux
suivants sont les **paquets binaires**, prêts à copier sur une clé USB.

Paquet **Windows** — 45 fichiers, 5 contenus modifiés face à l’archive
officielle 1.1.18 (`Ventoy2Disk.exe`, `altexe/Ventoy2Disk_X64.exe`,
`boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun
ajouté ni manquant.

Paquet **Linux** — 137 fichiers, 3 contenus modifiés (`boot/core.img.xz`,
`ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun ajouté ni manquant.

Les deux paquets ont été construits par les workflows *Release package* et
*Release package (Linux)* à partir de la baseline officielle 1.1.18 épinglée,
puis contrôlés par `dist/check_release_pkg.py` (empreinte, marqueur du fork
dans les trois chargeurs EFI, inventaire et contenus vs baseline) **avant**
d’être attachés. Le certificat MOK embarqué est celui documenté plus bas.

## Certificat Secure Boot

Empreinte du certificat MOK embarqué (secret du dépôt, inchangé) :

    8A:78:E8:AC:D9:88:D6:1E:ED:FF:97:64:8A:82:0A:F1:87:E0:10:CA:83:E5:27:B9:FA:6C:E2:06:DF:25:AA:89

Le zip ne contient aucun fichier `.cer` : le certificat est à la racine de
la partition `ventoy/` de l'image disque, sous le nom
`ENROLL_THIS_KEY_IN_MOKMANAGER.cer` (836 o). Sans enrôlement, ou avec
Secure Boot actif et la clé absente du store, le démarrage est **refusé**
(`Verification failed: (0x1A) Security Violation`). Procédure complète :
`dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md`.

## Validation

- Harnais de tri autonome (`ventoy_sort_test.c` à la racine, 25
  régressions, `-Wall -Wextra -Werror`, sans Docker, WSL ni VM) :
  `python build_sort_test.py`.
- Mise en page de la version : `dist/tests/test_gui_version_layout.py`
  (largeur réelle du texte vs cadre déclaré, Qt/GTK/WebUI) et
  `dist/tests/test_gui_render.sh` (la vraie fenêtre Qt rendue hors écran,
  capture PNG).
- Reproductibilité du paquet Linux : `dist/tests/test_linux_reproducibility.sh`
  construit deux fois dans deux racines isolées et compare octet à octet.
- Publication de bout en bout : `dist\check_release.cmd` (téléchargement
  des assets, sommes, extraction, harnais, contrôles de paquet).
- CI : 8 jobs sur push, plus `preflight-release`, `release-e2e`,
  `readme-release` et `move-tag-bench` à la publication.

## Périmètre et limites

Validé : la logique du tri et sa parité structurelle avec le code de
production, l'inventaire et les contenus des paquets face à la baseline
officielle, la reproductibilité du build Linux.

Non validé : un boot réel sur clé USB avec ce code ; les tests QEMU
tournent des ISO factices (menu et tri) et Secure Boot n'est pas enrôlé
dans ces VM — la validité des signatures y est vérifiée par `sbverify`.
