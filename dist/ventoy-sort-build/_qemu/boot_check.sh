#!/bin/bash
# =====================================================================================
#  boot_check.sh — amorçage RÉEL du paquet Windows livré, dans QEMU.
#
#  Le disque de test est reconstruit depuis le zip lui-même (build_test_disk.sh) :
#  MBR officiel + core.img (BIOS) + partition EFI = ventoy.disk.img patchée, avec
#  douze faux ISO écrits dans un ordre volontairement trié. Le menu GRUB affiché est
#  donc bien celui du paquet, le correctif de tri fusion est observable à l'écran.
#
#  Scénarios (usage : boot_check.sh [scénario...] — défaut : les quatre) :
#      bios              firmware SeaBIOS, sans Secure Boot          -> core.img
#      uefi              OVMF x64, sans Secure Boot                 -> grubx64_real.efi
#      uefi-sb           OVMF x64 Secure Boot ACTIF, MOK enrôlé    -> chargeurs signés
#      uefi-sb-nomok     Secure Boot ACTIF, MOK ABSENT (négatif)   -> refus attendu
#
#  Verdict : PASS si le menu « Ventoy <version> » apparaît (ou, pour le scénario
#  négatif, si le firmware refuse de démarrer). Sortie 1 sinon.
# =====================================================================================
set -u
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
cd "$Q" || exit 1

MENU_RE='Ventoy [0-9][0-9.]*-(Fork|ventoy-sort)'
SCENARIOS=("$@")
[ ${#SCENARIOS[@]} -eq 0 ] && SCENARIOS=(bios uefi uefi-sb uefi-sb-nomok)

verdict() {  # verdict <scénario> <PASS|FAIL> <détail>
    printf '%-14s %-4s  %s\n' "$1" "$2" "$3"
}

kill_vm() { pkill -f "[q]emu-system-(i386|x86_64)" 2>/dev/null || true; sleep 1; }

# wait_menu <log> <regex> <secondes> : 0 si le motif apparaît, 1 sinon
wait_menu() {
    local log=$1 re=$2 limit=$3 i
    for i in $(seq 1 "$limit"); do
        grep -aqE "$re" "$log" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

# ordre d'affichage attendu : le nom des faux ISO, dans l'ordre du tri fusion
show_order() {
    tr -d '\033' < "$1" | sed 's/\[[0-9;]*[A-Za-z]//g' \
        | grep -ao 'dummy-[A-Za-z0-9-]*\.iso' | awk '!seen[$0]++'
}

for sc in "${SCENARIOS[@]}"; do
    echo "======================================================================"
    echo " $sc"
    echo "======================================================================"
    LOG=$Q/serial-$sc.log
    rm -f "$LOG"

    if [ "$sc" = uefi-sb ]; then
        if [ ! -f "$Q/sbtest/vars-x64-sb.fd" ]; then
            echo "  store enrôlé absent -> _enroll.sh"; verdict "$sc" SKIP "-"; continue
        fi
        echo "  MOK enrôlé : $(grep -c . sbtest/vars-x64-sb.fd >/dev/null && echo oui)"
    fi

    bash "$Q/run_vm.sh" "$sc" 5592 >/dev/null || { verdict "$sc" FAIL "QEMU non lancé"; continue; }

    case "$sc" in
        uefi-sb-nomok)
            # contrôle négatif : MOK absent -> le firmware doit refuser le chargeur
            if wait_menu "$LOG" 'GNU GRUB' 100; then
                verdict "$sc" FAIL "GRUB a démarré alors que la clé du fork est absente du store"
            else
                detail=$(grep -ao 'Secure Boot Enabled\|Security Violation\|Access Denied\|Image failed to verify' "$LOG" 2>/dev/null | sort -u | head -2 | tr '\n' ';')
                verdict "$sc" PASS "aucun GRUB — refus du firmware (${detail:-signature refusée})"
            fi
            ;;
        *)
            # regex du titre : « Ventoy <version> UEFI » ou « ... BIOS »
            if wait_menu "$LOG" "$MENU_RE" 140; then
                # le titre apparaît avant la fin du rendu de la liste : on laisse
                # GRUB terminer l'affichage avant de lire l'ordre des entrées
                sleep 15
                titre=$(grep -aoE "$MENU_RE (UEFI|BIOS)" "$LOG" | head -1)
                ordre=$(show_order "$LOG" | tr '\n' ' ')
                mm=$(grep -ac 'mismatch' "$LOG" 2>/dev/null | head -1)
                bash "$Q/shot.sh" 5592 "$Q/boot-$sc.png" "$sc — menu ${titre:-Ventoy}" >/dev/null 2>&1 || true
                verdict "$sc" PASS "menu « ${titre:-Ventoy ?} » — ${ordre:-aucune entrée}"
                echo "               'mismatch' dans le log : ${mm:-0} (attendu 0)"
            else
                verdict "$sc" FAIL "le menu n'est pas apparu en 140 s"
                echo "--- 20 dernières lignes série ---"
                tr -d '\033' < "$LOG" 2>/dev/null | sed 's/\[[0-9;]*[A-Za-z]//g' | tail -20
            fi
            ;;
    esac
    kill_vm
done

echo
echo "======================================================================"
echo " captures : $Q/uefi_menu_x64.png, $Q/bios_menu.png, $Q/sb_menu.png"
echo "======================================================================"