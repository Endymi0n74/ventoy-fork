# Notes de version — v1.1.17-ventoy-sort

Fork **ventoy-fork** (https://github.com/Endymi0n74/ventoy-fork), base
**v1.1.17 upstream exacte** (`7cbdc5cf`, « 1.1.17 release »).
Tag : `v1.1.17-ventoy-sort` → commit `2551c3b7`
(code : un commit de fork `ac114e58` sur la base upstream ; docs incluses).

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
- `2551c3b7` — mise à jour RELEASE_NOTES / README (renommage ventoy-fork,
  base v1.1.17 exacte) ; le tag `v1.1.17-ventoy-sort` pointe ici.
- `bbf4676f` — .gitignore : ignorer la config runtime INSTALL/Ventoy2Disk.ini.
