# Fonctions de Ventoy amont — v1.1.18

Ce document recense ce que fait [Ventoy](https://github.com/ventoy/Ventoy) **en amont**,
repris depuis le README du projet pour la version **v1.1.18** (commit `6116894a`, tag
`v1.1.18`, publié le 2026-10-09). Il
existe parce que la surface fonctionnelle de Ventoy est bien plus large que ce que ce
fork touche : le fork ne change que le **tri des images du menu** et la **mise en page de
la version dans la GUI Linux** (voir le [README](../README.md) et le
[README français](../README.fr.md)). Tout ce qui est décrit ici est donc inchangé par le
fork.

La rédaction est française ; les noms de distributions, les intitulés de la documentation
officielle et les versions sont repris tels quels. Le README amont en anglais reste la
référence : <https://github.com/ventoy/Ventoy>.

> **À lire avant d'installer un paquet du fork** : les chargeurs publiés sont signés avec
> la clé MOK du fork, pas celle de Microsoft. Voir
> [Secure Boot](#secure-boot) plus bas et la procédure d'enrôlement dans
> [`dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md`](../dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md).

## Synchronisation amont : v1.1.17 → v1.1.18

Le 2026-10-09, `upstream/master` (tag `v1.1.18`, commit `6116894a`) a été fusionné dans
`master` du fork : 19 commits après `7cbdc5cf` (« 1.1.17 release »). **Le merge n'a posé
aucun conflit** — `ventoy_cmd.c` est le seul fichier modifié des deux côtés, et leurs
hunks sont disjoints (le tri fusion du fork occupe les lignes ~2852-3121, upstream touche
les commandes `ventoy_cmd_check_mode`, `ventoy_cmd_need_secondary_menu`,
`ventoy_cmd_timeout_lock`/`theme_lock` et le tableau `ventoy_cmds[]`). Le harnais de
régression passe en mode normal **et** en `--perf`.

### Nouveautés officielles de v1.1.18 (changelog GitHub)

- Support **expérimental des images de récupération SteamOS** (#3712, #2875, #1815).
- **Partition ISO montable « ready to use »** sur les distributions de bureau courantes,
  nom dm stable `/dev/mapper/VentoyPart`, et montabilité depuis CloneZilla (#3274).
- Suppression des icônes de disque en double dans la barre latérale sous Linux.
- Correctif de boot **Fedora 45 beta**.
- Correctif du contrôle **Secure Boot Windows/WinPE** (certificat Windows CA2011 révoqué,
  avec le mode ByPass Ventoy et un BIOS à jour).
- Correctif de la **persistance intermittente sous Ubuntu 24.04** (#3718).
- Correctif de boot **Grml 2026.09** (#3751).
- **Support des ISO Syslinux personnalisées** (`syslinux.cfg` à la racine, #3760).
- Améliorations pour la dernière version de **LinuxConsole** (#3745).
- **Plugson** : contrôle des entrées *Boot Conf Replace*, limitées à 2 par mode
  (#3727, #3593).

### Également fusionné (au-delà du changelog)

- **GRUB** : nouvelles commandes `vt_timeout_lock` et `vt_theme_lock` (verrouillage de
  la variable `timeout` et de la variable `theme` par hooks d'environnement), mode
  `vtcompat`, commandes `terminal_lock`, `lockfont`, `efifwsetup`, `terminal`, `font` ;
  loaders linux i386 / arm64 / mips64 et `syslinux_parse` améliorés ; une nouvelle
  fonction `ventoy_cfg_theme_lock` dans `grub.cfg`.
- `vt_img_extra_initrd_append` détecte automatiquement le suffixe des modules noyau
  (`.ko`, `.ko.xz`, `.ko.zst`, …).
- **Hooks d'amorçage** : chemin des hooks dracut rendu variable (#3753), optimisation du
  processus udev, et nouveaux hooks « uauto » pour arch, blackPanther, deepin, gobo,
  hyperbola, kaos, lunar, mageia, manjaro, openEuler, rhel7, suse ; boucle dédiée
  SteamOS (`IMG/cpio/ventoy/loop/steamos/`).
- **VtoyTool** : nouveau module `vtoygpt.c`, `vtoydm.c` étendu (nom dm stable), nouvelles
  commandes, `biso_9660.h` revu.
- `Ventoy2Disk/build.bat` (toolchain MSVC), VtoyShim EDK2, aide et menu **pt_BR**
  corrigés, `DOC/BuildVentoyFromSource.txt` mis à jour.

### Portée pour ce fork

- Le merge n'est plus resté au niveau source : la baseline officielle épinglée par
  SHA-256 est maintenant **1.1.18** (`.github/workflows/build-package*.yml`,
  `BASE_ZIP`/`BASE_LINUX` des scripts de build, `BASELINES` de
  `dist/check_release_pkg.py`). Les paquets publiés embarquent donc `grub.cfg`, hooks
  du cpio et outils de 1.1.18, et les chargeurs GRUB recompilés contiennent le code
  de 1.1.18. C'est nécessaire : un `grub.cfg` de 1.1.18 appelle `vt_timeout_lock`,
  `vt_theme_lock`, `terminal_lock` et `lockfont`, qui n'existent que dans un GRUB
  compilé depuis 1.1.18.
- Les inventaires ne bougent pas pour autant : 45 fichiers dans le zip Windows et 137
  dans le tar.gz Linux, les mêmes noms qu'en 1.1.17. Cinq contenus changent donc côté
  Windows et trois côté Linux, exactement la liste attendue par
  `dist/check_release_pkg.py`.
- Les 25 tests du harnais et le mode `--perf` passent, la CI revalide au push, et
  chaque paquet est contrôlé par la CI (empreinte, marqueur du fork dans les trois
  chargeurs EFI, inventaire et contenus vs baseline) **avant** d'être attaché à la
  release.
- Le **tri fusion reste le seul changement de production du fork** : le merge n'a pas
  touché `ventoy_cmd_list_img()` ni ses tests.

## Ce qu'est Ventoy

Ventoy est un outil libre qui rend une clé USB amorçable pour les fichiers
ISO/WIM/IMG/VHD(x)/EFI. Il ne faut pas reformater le disque sans cesse : on copie les
images sur la clé et on les démarre. On peut copier beaucoup d'images à la fois, Ventoy
propose alors un menu pour choisir celle à démarrer. Ventoy sait aussi parcourir les
fichiers ISO/WIM/IMG/VHD(x)/EFI présents sur les disques locaux et les démarrer.

BIOS x86 Legacy, UEFI IA32, UEFI x86_64, UEFI ARM64 et UEFI MIPS64EL sont pris en charge de
la même façon, ainsi que les deux styles de partition MBR et GPT. La plupart des OS
fonctionnent (Windows/WinPE/Linux/Unix/ChromeOS/VMware/Xen…). Plus de 1300 fichiers ISO
ont été testés ([liste](https://www.ventoy.net/en/isolist.html)) et plus de 90 % des
distributions de [distrowatch.com](https://distrowatch.com/) sont couvertes
([détails](https://www.ventoy.net/en/distrowatch.html)).

Site officiel : <https://www.ventoy.net>

## Plateformes éprouvées

### Windows
Windows 7, Windows 8, Windows 8.1, Windows 10, Windows 11, Windows Server 2012, Windows Server 2012 R2, Windows Server 2016, Windows Server 2019, Windows Server 2022, Windows Server 2025, WinPE

### Linux
Debian, Ubuntu, CentOS(6/7/8/9/10), RHEL(6/7/8/9/10), Deepin, Fedora, Rocky Linux, AlmaLinux, EuroLinux(6/7/8/9), openEuler, OpenAnolis, SLES, openSUSE, MX Linux, Manjaro, Linux Mint, Endless OS, Elementary OS, Solus, Linx, Zorin, antiX, PClinuxOS, Arch, ArcoLinux, ArchLabs, BlackArch, Obarun, Artix Linux, Puppy Linux, Tails, Slax, Kali, Mageia, Slackware, Q4OS, Archman, Gentoo, Pentoo, NixOS, Kylin, openKylin, Ubuntu Kylin, KylinSec, Lubuntu, Xubuntu, Kubuntu, Ubuntu MATE, Ubuntu Budgie, Ubuntu Studio, Bluestar, OpenMandriva, ExTiX, Netrunner, ALT Linux, Nitrux, Peppermint, KDE neon, Linux Lite, Parrot OS, Qubes, Pop OS, ROSA, Void Linux, Star Linux, EndeavourOS, MakuluLinux, Voyager, Feren, ArchBang, LXLE, Knoppix, Calculate Linux, Clear Linux, Pure OS, Oracle Linux, Trident, Septor, Porteus, Devuan, GoboLinux, 4MLinux, Simplicity Linux, Zeroshell, Android-x86, netboot.xyz, Slitaz, SuperGrub2Disk, Proxmox VE, Kaspersky Rescue, SystemRescueCD, MemTest86, MemTest86+, MiniTool Partition Wizard, Parted Magic, veket, Sabayon, Scientific, alpine, ClearOS, CloneZilla, Berry Linux, Trisquel, Ataraxia Linux, Minimal Linux Live, BackBox Linux, Emmabuntüs, ESET SysRescue Live,Nova Linux, AV Linux, RoboLinux, NuTyX, IPFire, SELKS, ZStack, Enso Linux, Security Onion, Network Security Toolkit, Absolute Linux, TinyCore, Springdale Linux, Frost Linux, Shark Linux, LinuxFX, Snail Linux, Astra Linux, Namib Linux, Resilient Linux, Virage Linux, Blackweb Security OS, R-DriveImage, O-O.DiskImage, Macrium, ToOpPy LINUX, GNU Guix, YunoHost, foxclone, siduction, Adelie Linux, Elive, Pardus, CDlinux, AcademiX, Austrumi, Zenwalk, Anarchy, DuZeru, BigLinux, OpenMediaVault, Ubuntu DP, Exe GNU/Linux, 3CX Phone System, KANOTIX, Grml, Karoshi, PrimTux, ArchStrike, CAELinux, Cucumber, Fatdog, ForLEx, Hanthana, Kwort, MiniNo, Redcore, Runtu, Asianux, Clu Linux Live, Uruk, OB2D, BlueOnyx, Finnix, HamoniKR, Parabola, LinHES, LinuxConsole, BEE free, Untangle, Pearl, Thinstation, TurnKey, tuxtrans, Neptune, HefftorLinux, GeckoLinux, Mabox Linux, Zentyal, Maui, Reborn OS, SereneLinux , SkyWave Linux, Kaisen Linux, Regata OS, TROM-Jaro, DRBL Linux, Chalet OS, Chapeau, Desa OS, BlankOn, OpenMamba, Frugalware, Kibojoe Linux, Revenge OS, Tsurugi Linux, Drauger OS, Hash Linux, gNewSense, Ikki Boot, SteamOS, Hyperbola, VyOS, EasyNAS, SuperGamer, Live Raizo, Swift Linux, RebeccaBlackOS, Daphile, CRUX, Univention, Ufficio Zero, Rescuezilla, Phoenix OS, Garuda Linux, Mll, NethServer, OSGeoLive, Easy OS, Volumio, FreedomBox, paldo, UBOS, Recalbox, batocera, Lakka, LibreELEC, Pardus Topluluk, Pinguy, KolibriOS, Elastix, Arya, Omoikane, Omarine, Endian Firewall, Hamara, Rocks Cluster, MorpheusArch, Redo, Slackel, SME Server, APODIO, Smoothwall, Dragora, Linspire, Secure-K OS, Peach OSI, Photon, Plamo, SuperX, Bicom, Ploplinux, HP SPP, LliureX, Freespire, DietPi, BOSS, Webconverger, Lunar, TENS, Source Mage, RancherOS, T2, Vine, Pisi, blackPanther, mAid, Acronis, Active.Boot, AOMEI, Boot.Repair, CAINE, DaRT, EasyUEFI, R-Drive, PrimeOS, Avira Rescue System, bitdefender, Checkra1n Linux, Lenovo Diagnostics, Clover, Bliss-OS, Lenovo BIOS Update, Arcabit Rescue Disk, MiyoLinux, TeLOS, Kerio Control, RED OS, OpenWrt, MocaccinoOS, EasyStartup, Pyabr, Refracta, Eset SysRescue, Linpack Xtreme, Archcraft, NHVBOOT, pearOS, SeaTools, Easy Recovery Essentional, iKuai, StorageCraft SCRE, ZFSBootMenu, TROMjaro, BunsenLabs, Todo en Uno, ChallengerOS, Nobara, Holo, CachyOS, Peux OS, Vanilla OS, ShredOS, paladin, Palen1x, dban, ReviOS, HelenOS, XeroLinux, Tiny 11, chimera linux, CuteFish, DragonOs, Rhino Linux, vanilladpup, crystal, IGELOS, MiniOS, gnoppix, PikaOS, UwUntu, Noble, PocketHandyBox, DiskGenius, Commodore, Talos, Shebang Linux, hrmpf, Bazzite, ManualLinux, nyarchlinux, ultramarine, TempleOS, bluefin, Damn Small Linux, Kicksecure, SerentiyOS, AerynOS, ......

### Unix
DragonFly, FreeBSD, pfSense, OPNsense, GhostBSD, FreeNAS, TrueNAS, XigmaNAS, FuryBSD, HardenedBSD, MidnightBSD, ClonOS, EmergencyBootKit, helloSystem

### ChromeOS
FydeOS, CloudReady, ChromeOS Flex, ThoriumOS

### Autres
VMware ESXi, Citrix XenServer, Xen XCP-ng

Pour signaler une image qui démarre correctement, amont demande un retour sous forme
d'issue : <https://github.com/ventoy/Ventoy/issues/1195>.

## Mode navigateur de fichiers locaux

Ventoy sait parcourir les fichiers ISO/WIM/IMG/VHD(x)/EFI présents sur les disques locaux
et les démarrer. Voir les [notes amont](https://www.ventoy.net/en/doc_browser.html).

## Greffons et configurateur graphique

Ventoy propose un framework de greffons et un configurateur graphique de ces greffons,
VentoyPlugson : <https://www.ventoy.net/en/plugin_plugson.html>.

## Fonctions

* 100 % open source
* Simple d'utilisation
* Rapide (limité uniquement par la vitesse de copie du fichier ISO)
* Peut être installé sur clé USB, disque local, SSD, NVMe ou carte SD
* Démarrage direct depuis des fichiers ISO/WIM/IMG/VHD(x)/EFI, sans extraction
* Navigation et démarrage de fichiers ISO/WIM/IMG/VHD(x)/EFI présents sur les disques locaux
* Pas besoin que les fichiers ISO/WIM/IMG/VHD(x)/EFI soient contigus sur le disque
* Styles de partition MBR et GPT pris en charge (1.0.15+)
* BIOS x86 Legacy, UEFI IA32, UEFI x86_64, UEFI ARM64 et UEFI MIPS64EL pris en charge
* Secure Boot UEFI IA32/x86_64 pris en charge (1.0.07+)
* Persistance Linux prise en charge (1.0.11+)
* Auto-installation Windows prise en charge (1.0.09+)
* Auto-installation Linux prise en charge (1.0.09+)
* Expansion de variables prise en charge dans les scripts d'auto-installation Windows/Linux
* FAT32/exFAT/NTFS/UDF/XFS/Btrfs/Ext2(3)(4) pris en charge pour la partition principale
* Fichiers ISO de plus de 4 Go pris en charge
* Alias de menu et messages d'aide au menu pris en charge
* Protection par mot de passe prise en charge
* Style de menu natif pour Legacy et UEFI
* La plupart des types d'OS sont pris en charge, 1300+ fichiers ISO testés
* Démarrage de vDisk Linux pris en charge
* Ne fait pas que démarrer, mais aussi tout le processus d'installation
* Menu basculable dynamiquement entre les modes Liste et Arborescence
* Concept « Ventoy Compatible »
* Framework de greffons et configurateur graphique de greffons
* Injection de fichiers dans l'environnement d'exécution
* Remplacement dynamique du fichier de configuration de démarrage
* Thèmes et menus hautement personnalisables
* Prise en charge du disque USB protégé en écriture
* L'usage normal du disque USB n'est pas affecté
* Données non destructives lors d'une mise à jour de version
* Pas besoin de mettre Ventoy à jour quand une nouvelle distribution sort

![avatar](https://www.ventoy.net/static/img/screen/screen_uefi.png)

## Secure Boot

Le Secure Boot UEFI IA32 et x86_64 est pris en charge depuis la version 1.0.07 : c'est le
mécanisme décrit par la [documentation officielle amont](https://www.ventoy.net/en/doc_secure.html).

**Ce qui change dans ce fork.** Les paquets publiés ici n'emploient pas la clé Microsoft
mais la clé MOK propre au fork. Sans enrôlement, le démarrage est refusé avec
`Verification failed: (0x1A) Security Violation`. Il faut donc soit désactiver Secure
Boot, soit enrôler le certificat `ENROLL_THIS_KEY_IN_MOKMANAGER.cer` — qui se trouve à la
racine de la partition `ventoy` de l'image disque, **pas** dans le paquet téléchargé.
Procédure complète :
[`dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md`](../dist/ventoy-sort-build/PROCEDURE-SECURE-BOOT.md).

## Documentation officielle

| Titre | Lien |
|---|---|
| **Install & Update** | [https://www.ventoy.net/en/doc_start.html](https://www.ventoy.net/en/doc_start.html) |
| **Browse/Boot Files In Local Disk** | [https://www.ventoy.net/en/doc_browser.html](https://www.ventoy.net/en/doc_browser.html) |
| **Secure Boot** | [https://www.ventoy.net/en/doc_secure.html](https://www.ventoy.net/en/doc_secure.html) |
| **Customize Theme** | [https://www.ventoy.net/en/plugin_theme.html](https://www.ventoy.net/en/plugin_theme.html) |
| **Global Control** | [https://www.ventoy.net/en/plugin_control.html](https://www.ventoy.net/en/plugin_control.html) |
| **Image List** | [https://www.ventoy.net/en/plugin_imagelist.html](https://www.ventoy.net/en/plugin_imagelist.html) |
| **Auto Installation** | [https://www.ventoy.net/en/plugin_autoinstall.html](https://www.ventoy.net/en/plugin_autoinstall.html) |
| **Injection Plugin** | [https://www.ventoy.net/en/plugin_injection.html](https://www.ventoy.net/en/plugin_injection.html) |
| **Persistence Support** | [https://www.ventoy.net/en/plugin_persistence.html](https://www.ventoy.net/en/plugin_persistence.html) |
| **Boot WIM file** | [https://www.ventoy.net/en/plugin_wimboot.html](https://www.ventoy.net/en/plugin_wimboot.html) |
| **Windows VHD Boot** | [https://www.ventoy.net/en/plugin_vhdboot.html](https://www.ventoy.net/en/plugin_vhdboot.html) |
| **Linux vDisk Boot** | [https://www.ventoy.net/en/plugin_vtoyboot.html](https://www.ventoy.net/en/plugin_vtoyboot.html) |
| **DUD Plugin** | [https://www.ventoy.net/en/plugin_dud.html](https://www.ventoy.net/en/plugin_dud.html) |
| **Password Plugin** | [https://www.ventoy.net/en/plugin_password.html](https://www.ventoy.net/en/plugin_password.html) |
| **Conf Replace Plugin** | [https://www.ventoy.net/en/plugin_bootconf_replace.html](https://www.ventoy.net/en/plugin_bootconf_replace.html) |
| **Menu Class** | [https://www.ventoy.net/en/plugin_menuclass.html](https://www.ventoy.net/en/plugin_menuclass.html) |
| **Menu Alias** | [https://www.ventoy.net/en/plugin_menualias.html](https://www.ventoy.net/en/plugin_menualias.html) |
| **Menu Extension** | [https://www.ventoy.net/en/plugin_grubmenu.html](https://www.ventoy.net/en/plugin_grubmenu.html) |
| **Memdisk Mode** | [https://www.ventoy.net/en/doc_memdisk.html](https://www.ventoy.net/en/doc_memdisk.html) |
| **TreeView Mode** | [https://www.ventoy.net/en/doc_treeview.html](https://www.ventoy.net/en/doc_treeview.html) |
| **Disk Layout MBR** | [https://www.ventoy.net/en/doc_disk_layout.html](https://www.ventoy.net/en/doc_disk_layout.html) |
| **Disk Layout GPT** | [https://www.ventoy.net/en/doc_disk_layout_gpt.html](https://www.ventoy.net/en/doc_disk_layout_gpt.html) |
| **Search Configuration** | [https://www.ventoy.net/en/doc_search_path.html](https://www.ventoy.net/en/doc_search_path.html) |

## Installation et compilation

L'installation détaillée est documentée par l'amont :
<https://www.ventoy.net/en/doc_start.html>.

Pour compiler Ventoy depuis les sources, voir
[`DOC/BuildVentoyFromSource.txt`](../DOC/BuildVentoyFromSource.txt). Le fork n'y touche
pas.

## FAQ, forum et dons

FAQ amont : <https://www.ventoy.net/en/faq.html>.
Forum : <https://forums.ventoy.net>.

Les dons pour soutenir le travail amont passent par le site officiel
<https://www.ventoy.net> ; ils ne concernent que le projet
[ventoy/Ventoy](https://github.com/ventoy/Ventoy), pas ce fork.
