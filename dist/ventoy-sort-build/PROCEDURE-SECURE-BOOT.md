# Secure Boot — enrôlement de la clé MOK du fork ventoy-sort

## Ce que signe ce paquet

Clé locale générée par le build (empreinte SHA-256 du certificat) :

    8A:78:E8:AC:D9:88:D6:1E:ED:FF:97:64:8A:82:0A:F1:87:E0:10:CA:83:E5:27:B9:FA:6C:E2:06:DF:25:AA:89

- recompilés puis signés : `grubx64_real.efi`, `grubia32_real.efi` et
  `BOOTAA64.EFI` (chargeur GRUB arm64 — pas de shim sur ce chemin, 1.1.17 comme 1.1.18)
- re-signés après modification ou pour remplacer la signature Ventoy :
  `fbx64.efi` (empreinte sha256 du chargeur x64 mise à jour),
  `grubia32.efi`, `ventoy_{x64,ia32,aa64}.efi`, `iso9660_{x64,ia32,aa64}.efi`,
  `udf_{x64,ia32,aa64}.efi`, `vtoyutil_{x64,ia32,aa64}.efi`,
  `wimboot.x86_64.xz` et `wimboot.i386.efi.xz` (PE signés puis re-compressés)
- certificat public : `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` à la racine de
  l'image Ventoy (copie locale : `ventoy-sort-MOK.cer`, à côté du zip)
- NON touchés : `EFI/BOOT/BOOTX64.EFI` et `BOOTIA32.EFI` (shims signés
  Microsoft), MokManager (`mmx64.efi`/`mmia32.efi`), chargeurs mips

## Enrôlement de la clé (une seule fois)

Depuis un Linux (live USB par ex.) :

```
mokutil --import ventoy-sort-MOK.cer
# définir un mot de passe MOK, puis redémarrer
```

Au redémarrage, l'écran bleu **MokManager** (fourni dans l'image) s'affiche :

1. « Enroll MOK » → « Yes »
2. saisir le mot de passe défini à `mokutil --import`
3. « Reboot »

Vérification :

```
mokutil --list-enrolled | grep -i ventoy-sort
```

Puis activer **Secure Boot** dans le firmware : le fork démarre.

## Enrôlement et validation VIRTUELS (QEMU, sans matériel) — validés

Pour prouver la chaîne sans toucher à une machine réelle, les stores de
variables OVMF/AAVMF se manipulent avec `virt-fw-vars` (paquet Debian/Ubuntu
`python3-virt-firmware`). Deux scénarios reproduisent l'enrôlement MokManager
(`ventoy-sort-MOK.cer` = le fichier du paquet, format DER) :

```
GUID=$(python3 -c 'import uuid; print(uuid.uuid4())')   # GUID libre d'enrôlement

# --- x64 : clés Microsoft conservées + MOK ajouté à db et MokList ---------
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd vars-x64-sb.fd
virt-fw-vars --inplace vars-x64-sb.fd \
    --add-db "$GUID" ventoy-sort-MOK.cer \
    --add-mok "$GUID" ventoy-sort-MOK.cer

# --- arm64 : PK/KEK/db entièrement établis sur le MOK ---------------------
# (aucun shim Microsoft n'existe sur ce chemin : BOOTAA64.EFI, notre build
#  signé, est vérifié directement par le db — valable pour le zip Windows
#  comme pour le tar Linux)
cp /usr/share/AAVMF/AAVMF_VARS.ms.fd vars-a64-sb.fd
virt-fw-vars --inplace vars-a64-sb.fd \
    --set-pk "$GUID" ventoy-sort-MOK.cer \
    --add-kek "$GUID" ventoy-sort-MOK.cer \
    --add-db "$GUID" ventoy-sort-MOK.cer
```

Lancement avec le firmware secboot et ce store (harnais `_qemu/` du dépôt :
`run_vm.sh uefi-sb 5592` / `run_vm_a64.sh 5594 sb` ; `build_test_disk.sh`
construit le disque de test depuis le zip Windows, `build_test_disk_a64.sh`
depuis le tar Linux ou le zip ; l'AAVMF écrit ses variables sur `EFIBOOT-*/`,
l'OVMF dans la copie pflash du store) :

```
# --- état réel du Secure Boot après boot (store relu) --------------------
# OVMF : SecureBootEnable : bool: ON   |   AAVMF : idem, lu après arrêt
virt-fw-vars -i vars-x64-sb-run.fd -p | grep SecureBoot
virt-fw-vars -i vars-a64-sb-run.fd -p | grep SecureBoot
```

**Résultats validés (deux architectures)** :

| Test | Chargeur signé MOK | Même disque, clés MS seules (MOK absent) |
|---|---|---|
| UEFI x64 (OVMF secboot, disque construit depuis CE zip) | menu « Ventoy … UEFI » atteint, 12/12 ISO triés, 0 violation ; SecureBootEnable: ON post-boot | refus net : « Security Violation », aucun GRUB |
| UEFI arm64 (AAVMF ms, disque construit depuis CE zip) | menu « Ventoy … AA64 » atteint, 12/12 ISO triés, 0 violation ; SecureBootEnable: ON post-boot | refus net : « Access Denied », aucun GRUB |

Les contrôles **négatifs** (même firmware secboot, mêmes disques, seules les
clés changent) prouvent que Secure Boot est réellement appliqué : le chargeur
maison passe quand le MOK est dans le db et est rejeté quand il ne l'est pas.

### Révocation (dbx) — validée

Le firmware applique aussi la liste de révocation. Révocation par certificat
signant (le mécanisme fiable) :

```
GUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
cp vars-x64-sb.fd vars-x64-dbx.fd
virt-fw-vars --inplace vars-x64-dbx.fd --add-dbx-cert "$GUID" ventoy-sort-MOK.cer
# boot du même disque avec _qemu/run_vm.sh uefi-sb-dbx :
#   -> « Security Violation », aucun GRUB (chargeur signé par un certificat révoqué)
# miroir avec le store sans révocation (uefi-sb) : le menu démarre
```

Deux limites documentées : (1) un **haché brut** (sha256 du fichier) mis dans
dbx ne bloque rien — la comparaison dbx du firmware porte sur des hachés de
structure PE ou des certificats ; (2) `grubx64_real.efi` est chargé
manuellement par `fbx64.efi` (VtoyShim) via son propre contrôle de haché
embarqué, hors vérification dbx du firmware — c'est le chargeur vérifié par le
firmware qui porte l'application de dbx. Test ré-exécutable :
`_qemu/dbx_check.sh`.

## Reproductibilité

La `signingTime` de chaque signature est figée à
2027-01-01T00:00:00Z pendant `sbsign` (shim `secureboot/fixedtime.so`),
et les chemins de compilation sont projetés sur un préfixe constant
(`-ffile-prefix-map` / `-fmacro-prefix-map`, y compris via
`TARGET_CCASFLAGS` pour les `.S`). Ces deux mesures sont nécessaires :
sans elles, les modules GRUB embarquaient le chemin absolu de la racine
de build, et deux builds dans des répertoires différents divergeaient
(`boot/core.img.xz`, `ventoy/ventoy.disk.img.xz`).

Vérifié : deux builds complets dans deux racines isolées de longueurs
différentes produisent le même octet (`e8bf8179…`) — banc
`dist/tests/test_linux_reproducibility.sh`. Non vérifié : entre chaînes
d'outils différentes (autre GCC, autre binutils), qui produisent d'autres
octets.

L'UEFI ne valide pas cette date : seule l'appartenance du certificat à la
MOK compte (validité du certificat : date de génération → +100 ans).

## Rotation de clé

Supprimer `secureboot/` puis relancer le build → nouvelle clé → refaire
l'enrôlement. L'ancienne clé reste dans MOK jusqu'à retrait
(`mokutil --delete`).

## AVERTISSEMENT

- Sauvegarder `secureboot/ventoy-sort-mok.key` : sans lui, les signatures
  ne peuvent plus être régénérées (et il faut ré-enrôler).
- La clé privée n'est JAMAIS incluse dans le paquet ni dans l'image.
- dbx/mises à jour shim peuvent révoquer les binaires → refaire un build.
