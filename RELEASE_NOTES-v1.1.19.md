# Notes de version — v1.1.19-ventoy-sort

Fork **ventoy-fork** (https://github.com/Endymi0n74/ventoy-fork), base
**v1.1.17 upstream exacte** (`7cbdc5cf`, « 1.1.17 release »).
Release stable : `v1.1.19-ventoy-sort`.
Code : un commit de fork `ac114e58` sur la base upstream, suivi des
commits docs/tooling ci-dessous.

## Contenu

### Changement principal : tri fusion stable pour les images du menu

`GRUB2/MOD_SRC/grub-2.04/grub-core/ventoy/ventoy_cmd.c` :

- `ventoy_img_merge` / `ventoy_img_msort` remplacent le tri par
  sélection O(n²) de `ventoy_cmd_list_img()` : stabilité sur les noms
  égaux (l'ordre de découverte est préservé), complexité O(n log n),
  reconstruction des pointeurs `prev` en une seule passe.
- **Correction de bug incluse** : la première version du split ne
  terminait pas la première moitié de liste, ce qui faisait
  re-consommer les nœuds de `a` par la fusion — blocage du menu au
  boot dès 3 images. Corrigé (listes disjointes avant récursion) et
  couvert par une régression permanente.
- **Garde-fou de cohérence** : `ventoy_cmd_list_img()` vérifie que
  `g_ventoy_img_count` correspond à la longueur réelle de la liste
  avant de trier ; en cas d'écart, un message est affiché sur la
  console (le tri continue, sans risque prouvé par le harnais).

### La version du fork tient dans la fenêtre du Linux

`LinuxGUI/Ventoy2Disk`, `INSTALL/tool/VentoyGTK.glade` et
`LinuxGUI/WebUI/index.html` : les interfaces amont sont dimensionnées pour
une version de six caractères (`1.0.53`). La chaîne du fork en compte 17
(`1.1.19-ventoy-sort`) : elle débordait de son cadre, par-dessus `exFAT`
et `MBR`, et était rognée.

- Qt : fenêtre 441 → 660 px, cadres de version 205 → 315 px, libellés
  135 → 301 px, et `Ventoy2DiskWindow::SetVersionLabel()` qui ajuste la
  taille de police entre 20 pt et un plancher de 9 pt. `1.1.19-ventoy-sort`
  rend à 20 pt ; la variante `-rc1` rend à 16 pt dans les deux libellés Qt.
- GTK : libellés de version 120 → 305 px. WebUI : `.vtoy_ver` passe en
  largeur intrinsèque, boîtes 250 → 430 px.
- `Ventoy2Disk.pro` : les `INCLUDEPATH` absolus `/home/panda/...` deviennent
  relatifs à `$$PWD` — le fichier n’était construisible que sur la machine de
  son auteur.
- Reconstruction locale : `GUI_REBUILD=1` compile et rend le binaire Qt natif
  hors écran. Le paquet contient quatre architectures (x86_64, i386, aarch64,
  mips64el) ; seule la x86_64 peut être remplacée par cette compilation native.
  Avant substitution, le script compare les versions de symboles GLIBC et Qt
  aux exigences du runtime officiel. Le WSL Ubuntu 26.04 exige GLIBC_2.38 et
  Qt_5.15, contre GLIBC_2.14 et Qt_5.9 pour la baseline ; la substitution est
  donc refusée et le runtime livré reste intact. Un hôte compatible peut
  reconstruire puis remplacer la cible x86_64 seule.
- Non vérifié : la GUI **Windows** (`Ventoy2Disk.rc` / `WinDialog.c`) mesure
  150 px disponibles pour 136 px de texte en `Courier New` 10 — elle ne
  déborde pas aujourd’hui, mais un suffixe `-rc1` la ferait déborder. Ces
  fichiers sont laissés intacts.

### Tests de mise en page de la version

- `dist/tests/test_gui_version_layout.py` : largeur réelle du texte (lecteur
  TTF) comparée au cadre **déclaré** dans chaque source. Qt, GTK, WebUI.
  Sortie 0 / 1 / 2 (2 = police absente, ni succès ni échec).
- `dist/tests/test_gui_render.sh` + `dist/tests/gui_probe.cpp` : compile la
  GUI (Qt 5.15), instancie la vraie forme `.ui`, appelle le vrai
  `SetVersionLabel()`, compare la largeur du texte **rendu** au cadre et écrit
  une capture PNG dans `dist/tests/out/`. C’est le seul contrôle qui dise
  quelque chose de l’écran ; il sort en 1 sur un débordement réel.
### Harnais de validation autonome (sous `ventoy/`, hors arbre GRUB)

- `ventoy_sort_test.c` : ~30 régressions — comparateurs (modes casse,
  plugin-list, ordre parent/enfant, cas dir vide `dirlen=0`, noms
  longs > 64 octets), propriétés du tri (stabilité, intégrité des
  liens), **test de parité production** sur n=1..64 vérifié par
  mutation (retirer le « sever » échoue proprement à n=2 au lieu de
  bloquer), tolérance aux comptes erronés (sur/sous-comptés).
- `build_sort_test.py` / `run_sort_test.cmd` / `Makefile` :
  validation en une commande, `-Wall -Wextra -Werror`, options
  `--perf`, `--seed`, `--sweep <n>`, `--reps <k>`.
- `PERF_FINDINGS.md` + logs `sweep30_ext_*.txt` : mesures de référence.

### Outillage de release : `MOVE_TAG=1` et préflight GitHub

- `dist\make_release.cmd <tag>` accepte `MOVE_TAG=1` (avec
  `CONFIRM_MOVE_TAG=<tag>`) pour **repositionner un tag existant** et
  mettre sa release à jour : sauvegarde des 3 assets, mise en draft
  temporaire, force-push du tag annoté, régénération des archives et de
  `SHA256SUMS`, remplacement des seuls assets correspondants, republish
  (canal draft/prerelease préservé). Un échec d'envoi **restaure les
  assets précédents** ; si cette restauration échoue aussi, un avertissement
  indique le dossier de sauvegarde à recharger manuellement.
- Workflow GitHub **Preflight move-tag** : avant tout déplacement, il exige
  que le tag existe, qu'une release y soit attachée (drafts compris) et
  qu'elle ne soit pas immuable (fail-closed), refuse une cible annoncée qui
  n'est pas le head de la branche et publie un tableau récapitulatif dans son
  job summary. Il est aussi appelé en `workflow_call` comme porte devant le
  job `release-e2e` à chaque publication.
- Job CI `MOVE_TAG bench` : banc **offline** (git et `gh` mockés, origine
  bare locale) de 146 assertions sur le mode `MOVE_TAG` et son rollback ;
  l'option `--check` vérifie en fin de run qu'aucun artefact du banc n'a
  fui hors du sandbox.
- Les builds Windows et Linux ont des lanceurs `.cmd` supervisés côté Windows
  par `run_wsl_build.ps1` : `wsl.exe` reste au premier plan et le wrapper WSL
  écrit les marqueurs `started` puis `done:<code>`. Si WSL s'arrête avant le
  marqueur final (ou si le shell est interrompu par un signal), le superviseur
  relance le build complet, jusqu'à deux fois avec 15 s d'intervalle par défaut.
  Un échec normal du build est transmis sans nouvelle tentative. Les valeurs
  sont réglables avec `WSL_BUILD_RETRIES`, `WSL_RETRY_DELAY_SECONDS` et
  `WSL_DISTRO` ; sur le build Windows, les variables de clé MOK sont transmises
  à WSL via `WSLENV`. Le CI teste succès, échec sans retry et arrêt/reprise VM
  simulés (`dist/tests/test_wsl_build_supervisor.sh`).
- Banc de reproductibilité du paquet Linux :
  `dist/tests/test_linux_reproducibility.sh` construit le paquet **deux fois
  dans deux racines isolées** de longueurs différentes (copies jetables du
  script et de `GRUB2/MOD_SRC`, même clé MOK des deux côtés) puis compare les
  archives octet à octet, nomme les entrées divergentes et vérifie qu’aucun
  chemin de build n’a survécu dans `boot/core.img.xz`. ~7 minutes, sortie 0 =
  identiques. C’est ce banc qui a révélé que deux builds consécutifs au même
  emplacement étaient identiques alors que deux racines distinctes divergeaient.
- La prerelease `v1.1.19-ventoy-sort-rc1` a servi à éprouver cette chaîne
  (préflight → `release-e2e`), puis a été replacée sur le head de `master`.

### Mesures (30 seeds, QPC, répétitions internes, contrôle de restore)

| N | fusion | naïf | gain |
|---|---|---|---|
| 32 | 1,4 µs | 2,0 µs | ~1,4× |
| 512 | 55 µs | 477 µs | ~8,7× |
| 2048 | 0,35 ms | 7,7 ms | ~22× |
| 16384 | 4,3 ms | 547 ms | ~126× |

Scaling conforme à n log n (~5,4× par 4× de données en grand N) ;
profondeur de récursion log₂(n) — quelques Ko de pile, sûre dans le
budget pré-boot de GRUB. Conclusions reproductibles : une exécution
post-merge sur `master` a reproduit tous les ratios à ~5 % près.

## Validation

```
python ventoy/build_sort_test.py           # régressions (RC=0 attendu)
python ventoy/build_sort_test.py --perf    # + comparaison de perf
ventoy/_build_sort_test/ventoy_sort_test.exe --sweep 30
```

Les deux modes passent avec `-Wall -Wextra -Werror`, arbre propre.

Environnement requis : **clang** et **Python 3** — rien d'autre.
Pas de Docker, pas de WSL, pas de machine virtuelle. Le chemin de clang
est résolu ainsi : variable d'environnement `CLANG` si définie, puis
`C:\Program Files\LLVM\bin\clang.exe`, puis `clang` sur le `PATH`
(sur une autre machine, définir simplement `CLANG` ou mettre clang
dans le `PATH`).

## Périmètre de la validation (et limites)

Validé : la logique du tri et sa parité structurelle avec le code de
production (mêmes algorithmes, mêmes séquences de liaison).

Non validé : un boot réel sur clé USB avec ce code. Le build complet
de l'ISO (GRUB recompilé dans l'arbre 2.04) a été écarté — le déploiement
passe par les runtimes officiels v1.1.17.

Aucun conteneur requis : Docker a été abandonné et désinstallé. La
validation repose uniquement sur le harnais natif Windows (clang +
Python 3, `-Wall -Wextra -Werror`) — sans WSL ni machine virtuelle.

## Historique du fork

- `ac114e58` — commit fonctionnel sur la base upstream : harnais + tri
  fusion stable pour les images du menu.
- `2551c3b7` — RELEASE_NOTES / README : renommage ventoy-fork, base
  v1.1.17 exacte.
- `bbf4676f` — .gitignore : ignorer la config runtime
  INSTALL/Ventoy2Disk.ini.
- `d872c0be` — docs : prérequis du harnais (clang + Python, pas de
  Docker/WSL/VM).
- `61efabfa` — chemin clang configurable via `CLANG` (env → défaut →
  PATH) dans build_sort_test.py / Makefile.
- `b70db59a` — README : badge + lien vers la release GitHub.
- `0f7ebecc` — script e2e réutilisable `dist/check_release.cmd`
  (download des assets + vérification SHA256SUMS + extraction +
  harnais, exit 0 = PASS).
- `202aba17` — le e2e intègre le sweep perf `--sweep 30` (étape 4/5)
  et archive le log de référence : `sweep30_e2e_*.txt` + section
  « Release e2e reference run » dans PERF_FINDINGS.md.
- `0fa9fe8f` — script de publication `dist/make_release.cmd <tag>`
  (sanity, tag annoté, archives, SHA256SUMS, gh release create/upload)
  avec `DRY_RUN=1` ; README : lien release + procédures make/check.
- `4487890b` — workflow GitHub Actions `CI` : harnais sur push,
  job `release-e2e` à la publication d'une release.
- `b410a353` — vérification : après désactivation du workflow Gitee,
  seul `CI` se déclenche sur push.
- `b8964e67` — support des prereleases dans `make_release.cmd`
  (draft → upload → publish) et `GH_TOKEN` fourni au job `release-e2e`.
- `d342a011` / `bfc7b564` / `a9f3e749` — workflow `preflight-move-tag` :
  porte tag/release/mutabilité, correction du parsing TSV, contrôle
  optionnel de la cible annoncée (`commit_sha`).
- `ee1af752` — mode `MOVE_TAG=1` dans `make_release.cmd` (backup + rollback
  des assets) et banc de tests hors ligne dédié.
- `45762f2f` — exemples du job summary GO dans README.md / README.fr.md et
  correction de l'endpoint rulesets (404 → la ligne « tag rulesets »
  affichait `unreadable`).
- `2cdb8eb4` — banc : scénario « restauration des assets en échec »
  (avertissement de réparation manuelle, sauvegarde conservée).
- `48beb798` — `/Brepro` aussi à la compilation (`ClCompile`) : deux
  rebuilds à froid de l'exe x64 sont désormais identiques bit à bit.
- `6dfd8fbb` — la note « tag rulesets » est aussi écrite dans le log du
  préflight (lisible via `gh run view --log`).
- `1172be6a` — job CI `MOVE_TAG bench` (offline) et option `--check` de
  détection des fuites de workdir.
- Correctif de reproductibilité du build Linux : projection de la racine de
  build sur un préfixe constant (`-ffile-prefix-map`, `-fmacro-prefix-map`, et
  `TARGET_CCASFLAGS` pour les `.S` compilés par automake, qui ne recoivent pas
  les `TARGET_CFLAGS`), plus une sonde de préflight et un garde-fou qui font
  échouer le build si un chemin de build subsiste dans un `*.module` ou
  `kernel.img`. Avant, deux racines isolées divergeaient sur `core.img.xz` et
  `ventoy.disk.img.xz` (1 088 fichiers de `grub-install` sur 2 211) ; après,
  deux racines de longueurs différentes donnent le même octet. La même
  correction reste à appliquer au build Windows. `PROCEDURE-SECURE-BOOT.md` et
  son gabarit dans les deux scripts de build décrivent désormais le périmètre
  réel plutôt qu’une promesse.

## Publication

Release stable publiée le **2026-10-04** :
<https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.20-ventoy-sort>

| asset | sha256 |
|---|---|
| `Ventoy-v1.1.20-ventoy-sort.zip` | `6eb3e3aa03ae15c454fb6b9fe907e7a8e24a88cdd76d71cbb3221700da13d505` |
| `Ventoy-v1.1.20-ventoy-sort.tar.gz` | `0313f22d144911b9b0acb22952fdecc8c7b15308c14e4ba4b8b6b641dcdd3689` |
| `ventoy-1.1.20-ventoy-sort-windows.zip` | `a68944d7a49136f3c81b712be9c223e5130aec1aaaf2db5e988b416d136bbbdc` |
| `ventoy-1.1.20-ventoy-sort-linux.tar.gz` | `f27e2b898dd7c0a42102bac85e54ee4cbecbc50706a20b058374f3ecbd58db20` |

Le premier asset est l’**archive source zip**, le deuxième son équivalent
tar.gz. Les deux suivants sont les **paquets binaires**, prêts à copier sur
une clé USB.

Paquet **Windows** — 17 246 599 o, 45 fichiers, 5 contenus modifiés face à
l’archive officielle 1.1.17 (`Ventoy2Disk.exe`, `altexe/Ventoy2Disk_X64.exe`,
`boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun
ajouté ni manquant.

Paquet **Linux** — 20 873 340 o, 137 fichiers, 3 contenus modifiés
(`boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun
ajouté ni manquant. Construit par le workflow *Release package (Linux)* sur
`ubuntu-24.04`, runner volontairement figé : la version du compilateur change
les octets produits par GRUB et déplacerait silencieusement l’empreinte publiée.
`GUI_REBUILD` reste désactivé, le garde-fou ABI refusant la substitution sur
une toolchain récente ; le paquet embarque donc les binaires GUI officiels.

Empreinte du certificat MOK embarqué dans ce paquet (identique à celle
documentée plus bas pour la v1.1.19) :

    8A:78:E8:AC:D9:88:D6:1E:ED:FF:97:64:8A:82:0A:F1:87:E0:10:CA:83:E5:27:B9:FA:6C:E2:06:DF:25:AA:89

**Le zip ne contient aucun fichier `.cer`.** Le certificat est à la racine de la
partition `ventoy/` de l’image disque, sous le nom
`ENROLL_THIS_KEY_IN_MOKMANAGER.cer` (836 o) ; il se lit sur la clé USB après
copie du paquet, ou s’extrait ainsi :

```
xz -dc ventoy/ventoy.disk.img.xz > /tmp/disk.img
mtype -i /tmp/disk.img ::/ENROLL_THIS_KEY_IN_MOKMANAGER.cer > ventoy-sort-MOK.cer
```

Sans enrôlement, ou avec Secure Boot actif et la clé absente du store, le
démarrage est **refusé** (`Verification failed: (0x1A) Security Violation`).
La procédure complète reste dans `dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md`.

Tag annoté `da7af651`. Construit par le workflow *Release package* à partir de
la baseline officielle épinglée ; les trois contrôles de
`dist/check_release_pkg.py` (empreinte, marqueur du fork dans les trois
chargeurs EFI, inventaire et contenus vs baseline) et la comparaison du
certificat embarqué avec le secret du dépôt ont réussi **avant** l’attachement
de l’asset. Les deux exécutions déclenchées par la publication ont produit la
même empreinte `a68944d7…` : reproductibilité confirmée sur deux runners
indépendants.

Release stable précédente, publiée le **2026-10-02** :
<https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.19-ventoy-sort>

| asset | sha256 |
|---|---|
| `Ventoy-v1.1.19-ventoy-sort.zip` | `472eb71000f1843ccdfaf55f46d7116dcd4d96cbb68929b17bf4dc307b493c73` |
| `Ventoy-v1.1.19-ventoy-sort.tar.gz` | `0a980b41116dbbd3960363c4e8eedcea0b02cf1244658216d010d0e58fe9787d` |
| `ventoy-1.1.19-ventoy-sort-windows.zip` | `47469323aa33ba3fb034db3c22c22ef03b2619da91b637ba964785f563583efd` |
| `ventoy-1.1.19-ventoy-sort-linux.tar.gz` | `8eb882652b0f5f6744c3435f5b1b40d7fe9aff0e27c4a650288e382a4c13f0e3` |

Les deux premiers assets sont les **archives sources** (à compiler soi-même). Les
deux suivants sont les **paquets binaires**, prêts à copier sur une clé USB :

| paquet | taille | entrées | fichiers modifiés vs officiel 1.1.17 |
|---|---|---|---|
| `ventoy-1.1.19-ventoy-sort-windows.zip` | 17 413 440 o | 45 | 5 |
| `ventoy-1.1.19-ventoy-sort-linux.tar.gz` | 21 041 017 o | 137 | 3 |
**Statut de reproductibilité du paquet Linux publié.** L’empreinte ci-dessus
recense l’asset effectivement publié, construit **avant** une correction : les
modules GRUB embarquaient alors le chemin absolu de la racine de build, si bien
que le script actuel **ne reproduit pas** `8eb88265…`. Deux builds dans deux
racines isolées donnent aujourd’hui `e8bf8179…` de façon reproductible
(`dist/tests/test_linux_reproducibility.sh`) ; reproduire l’empreinte publiée
suppose donc de republier le paquet. Vérifié à chaîne d’outils identique
(gcc 15.2, binutils 2.46, sbsigntool 0.9.4, WSL Ubuntu) — une autre version du
compilateur produit d’autres octets. Le paquet **Windows** n’a pas reçu cette
correction : son résultat n’est connu qu’au chemin exact du build.


Ils sont construits de zéro, à partir de l’archive officielle 1.1.17
correspondante, par `dist/ventoy-sort-build/build_ventoy_sort_windows.sh` et
`build_ventoy_sort_linux.sh` : GRUB 2.04 recompilé sur les quatre cibles
(i386-pc, x86_64-efi, i386-efi, arm64-efi) avec le correctif de tri fusion,
`Ventoy2Disk` recompilé avec MSBuild (paquet Windows), PE signés avec la **même
clé MOK locale** dans les deux paquets (enrôlement requis, voir
`PROCEDURE-SECURE-BOOT.md`). Les deux images disque `ventoy.disk.img.xz` sont
**strictement identiques** (sha256 `bbed13f6…`, 14 199 908 octets) et embarquent
l’une comme l’autre le certificat du fork à la racine
(`ENROLL_THIS_KEY_IN_MOKMANAGER.cer`, 836 o, la même clé que celle qui signe les
chargeurs) : les deux paquets se vérifient donc avec la même procédure
d’enrôlement. Les archives diffèrent seulement par leur format et leur contenu
hors image (45 entrées en zip contre 137 en tar.gz). Empreintes des artefacts :
`SHA256SUMS-ventoy-sort-windows.txt` et `SHA256SUMS-ventoy-sort-linux.txt`.

Tag annoté `cf4912b4` sur le commit `6056a895`. Validation : `dist\check_release.cmd`
exécuté en local (checksums, sweep 30 seeds, harnais 26/26, 3 contrôles sur
chacun des deux paquets binaires) et workflow CI du run de
publication — préflight `tag rulesets: none` / verdict GO, puis jobs
`release-e2e` et harnais verts.

Le paquet Windows a en outre été **amorcé réellement** dans QEMU
(`dist/ventoy-sort-build/_qemu/boot_check.sh`), sur une image disque reconstruite
depuis le zip lui-même (MBR officiel, `core.img`, `ventoy.disk.img` patchée) avec
douze faux ISO écrits dans un ordre volontairement désordonné : menu « Ventoy
1.1.19-ventoy-sort » en **BIOS** et en **UEFI x64**, ordre de tri fusion exact
(`007, 01-first, 0c-num, 10-apple, 2-beta, aardvark, B, delta, KiLo, M, mango,
zeta`), aucune occurrence de « mismatch ». Les chargeurs signés sont **acceptés
par OVMF avec Secure Boot activé** une fois la clé MOK enrôlée, et **refusés**
(`Verification failed: (0x1A) Security Violation`) sur le contrôle négatif où la
clé du fork est absente du store — la signature est donc bien ce qui autorise le
démarrage, pas un contournement du firmware.

La prerelease `v1.1.19-ventoy-sort-rc1` (release #400353077) avait été
replacée sur le head de `master` avec `MOVE_TAG=1`, puis promue en stable ;
son tag pointe sur `1172be6a`.

Le tag `v1.1.19-ventoy-sort` est annoté sur le commit de release
(qui inclut cette mise à jour des notes) ; les archives
(`git archive`) et le `SHA256SUMS` publiés correspondent
exactement à ce commit. La publication déclenche le job `release-e2e`
(download, checksums, extraction, sweep 30 seeds et harnais), précédé par
le préflight `move-tag` ; la validation se rejoue localement avec :
`dist\check_release.cmd`.
