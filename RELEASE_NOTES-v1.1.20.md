# Notes de version — v1.1.20-ventoy-sort

Release stable du fork **ventoy-fork**
(<https://github.com/Endymi0n74/ventoy-fork>), basée sur Ventoy upstream
v1.1.17. Publiée le **2026-10-04**, tag annoté sur le commit `da7af651`.

## Assets

| asset | taille | sha256 |
|---|---|---|
| `Ventoy-v1.1.20-ventoy-sort.zip` | 83 024 989 o | `6eb3e3aa03ae15c454fb6b9fe907e7a8e24a88cdd76d71cbb3221700da13d505` |
| `Ventoy-v1.1.20-ventoy-sort.tar.gz` | 81 471 876 o | `0313f22d144911b9b0acb22952fdecc8c7b15308c14e4ba4b8b6b641dcdd3689` |
| `ventoy-1.1.20-ventoy-sort-windows.zip` | 17 246 599 o | `a68944d7a49136f3c81b712be9c223e5130aec1aaaf2db5e988b416d136bbbdc` |
| `ventoy-1.1.20-ventoy-sort-linux.tar.gz` | 20 873 340 o | `f27e2b898dd7c0a42102bac85e54ee4cbecbc50706a20b058374f3ecbd58db20` |
| `SHA256SUMS` | 197 o | couvre les deux archives sources |
| `SHA256SUMS-ventoy-sort-windows.txt` | 1 112 o | couvre le zip Windows et 10 artefacts de build |
| `SHA256SUMS-ventoy-sort-linux.txt` | 896 o | couvre le tar.gz Linux et 8 artefacts de build |

Les deux premiers sont des **archives sources**, à compiler soi-même. Les deux
suivants sont les **paquets binaires**, prêts à copier sur une clé USB.

Paquet **Windows** — 45 fichiers, 5 contenus modifiés face à l’archive
officielle 1.1.17 (`Ventoy2Disk.exe`, `altexe/Ventoy2Disk_X64.exe`,
`boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun
ajouté ni manquant.

Paquet **Linux** — 137 fichiers, 3 contenus modifiés (`boot/core.img.xz`,
`ventoy/ventoy.disk.img.xz`, `ventoy/version`), aucun ajouté ni manquant.

Les deux paquets ont été construits par les workflows *Release package* et
*Release package (Linux)* à partir de la baseline officielle épinglée, puis
contrôlés par `dist/check_release_pkg.py` (empreinte, marqueur du fork dans
les trois chargeurs EFI, inventaire et contenus vs baseline) **avant** d’être
attachés. Le build Windows a produit la même empreinte lors de deux exécutions
indépendantes : il est reproductible.

Le paquet a été construit par le workflow *Release package* à partir de la
baseline officielle épinglée, puis contrôlé par `dist/check_release_pkg.py`
(empreinte, marqueur du fork dans les trois chargeurs EFI, inventaire et
contenus vs baseline) **avant** d'être attaché. Deux exécutions indépendantes
ont produit la même empreinte `a68944d7…` : le build est reproductible.

## Secure Boot — enrôlement de la clé MOK

Les chargeurs de ce paquet sont signés avec la clé MOK du fork, et non avec
celle de Microsoft. **Secure Boot doit être désactivé, ou la clé enrôlée, sinon
le démarrage est refusé** (`Verification failed: (0x1A) Security Violation`).

Empreinte SHA-256 du certificat public :

    8A:78:E8:AC:D9:88:D6:1E:ED:FF:97:64:8A:82:0A:F1:87:E0:10:CA:83:E5:27:B9:FA:6C:E2:06:DF:25:AA:89

**Où trouver le certificat.** Il n'est **pas** dans le zip : le paquet ne
contient aucun fichier `.cer`. Il est embarqué dans l'image disque, à la racine
de la partition `ventoy/`, sous le nom `ENROLL_THIS_KEY_IN_MOKMANAGER.cer`
(836 octets). Deux façons de l'obtenir :

- après avoir copié le paquet sur la clé USB, le lire directement sur la
  partition `ventoy` de la clé ;
- ou l'extraire de l'image sans monter la clé :

  ```
  xz -dc ventoy/ventoy.disk.img.xz > /tmp/disk.img
  mtype -i /tmp/disk.img ::/ENROLL_THIS_KEY_IN_MOKMANAGER.cer > ventoy-sort-MOK.cer
  ```

Procédure complète et rejouable : [`PROCEDURE-SECURE-BOOT.md`](dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md).

Enrôlement, une seule fois par machine, depuis un Linux :

```
mokutil --import ventoy-sort-MOK.cer   # définir un mot de passe MOK, puis redémarrer
```

Au redémarrage, l'écran **MokManager** s'affiche : « Enroll MOK » → « Yes » →
saisir le mot de passe → « Reboot ». Réactiver ensuite Secure Boot dans le
firmware ; le fork démarre. Contrôle : `mokutil --list-enrolled | grep -i ventoy-sort`.

La clé est celle des builds locaux et du CI : ne la renouvelez pas sans
raison, sinon les utilisateurs devront ré-enrôler un nouveau certificat.

## Correctifs et validation

- Corrige le débordement de `1.1.20-ventoy-sort` dans la GUI **Linux** :
  fenêtre Qt élargie (441 → 660 px) et taille de police ajustée au texte
  (20 pt, plancher 9 pt), cadres GTK élargis, version WebUI non coupée.
- Rend le projet Qt construisible hors de la machine d'origine en remplaçant
  les chemins d'inclusion absolus par des chemins relatifs.
- Vérifie les dimensions déclarées pour Qt, GTK et WebUI, puis compile la vraie
  fenêtre Qt, la rend hors écran et mesure ses libellés de version.

**Portée.** Ces correctifs portent sur les sources Linux. Le paquet Windows
embarque le runtime officiel 1.1.17 : la fenêtre Qt redessinée n'y est pas,
ce correctif est dans les sources et non dans un binaire Windows.