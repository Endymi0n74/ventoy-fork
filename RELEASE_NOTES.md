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

## Publication

Release stable publiée le **2026-10-02** :
<https://github.com/Endymi0n74/ventoy-fork/releases/tag/v1.1.19-ventoy-sort>

| asset | sha256 |
|---|---|
| `Ventoy-v1.1.19-ventoy-sort.zip` | `472eb71000f1843ccdfaf55f46d7116dcd4d96cbb68929b17bf4dc307b493c73` |
| `Ventoy-v1.1.19-ventoy-sort.tar.gz` | `0a980b41116dbbd3960363c4e8eedcea0b02cf1244658216d010d0e58fe9787d` |

Tag annoté `cf4912b4` sur le commit `6056a895`. Validation : `dist\check_release.cmd`
exécuté en local (checksums, sweep 30 seeds, harnais 26/26) et workflow CI du
run de publication — préflight `tag rulesets: none` / verdict GO, puis jobs
`release-e2e` et harnais verts.

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
