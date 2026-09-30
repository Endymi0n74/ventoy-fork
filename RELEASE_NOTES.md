# Notes de version — v1.1.17-ventoy-sort

Release locale basée sur **v1.1.17** upstream (`ca552e14`).
Tag : `v1.1.17-ventoy-sort` → commit `5ecb76a8` (merge de `perf/menu-build`).

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

## Fichiers de la release

| Chemin | Rôle |
|---|---|
| `GRUB2/.../ventoy_cmd.c` | tri fusion + garde-fou (seul fichier production) |
| `ventoy/ventoy_sort_test.c` | harnais de régressions + parité |
| `ventoy/build_sort_test.py`, `run_sort_test.cmd`, `Makefile` | pilotes de build/validation |
| `ventoy/PERF_FINDINGS.md` | mesures et méthodologie |
| `ventoy/sweep30_ext_*.txt` | logs bruts du sweep de référence |
| `ventoy/.gitignore` | artefacts locaux |

## Historique

Neuf commits + merge, poussés sur `origin` (Endymi0n74/Ventoy) :
harnais (`865f3dbe`) → régressions/seed (`513e2842`) → sweep+QPC
(`6f969b41`) → timing stabilisé (`c8a4b6b9`) → preuves (`d1463dc3`) →
**correction production (`736dada4`)** → sweep étendu (`87218cd8`) →
parité (`4a74ea90`) → gitignore (`e763d774`) → garde comptage
(`7006449a`).
