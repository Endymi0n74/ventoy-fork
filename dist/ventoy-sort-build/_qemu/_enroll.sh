#!/bin/bash
# Construit les stores de variables "enrôlés" pour les boots Secure Boot réels.
#   x64   : OVMF_VARS_4M.ms.fd (PK/KEK/db/dbx Microsoft) + MOK ajouté dans db et MokList
#   arm64 : AAVMF_VARS.ms.fd   + PK/KEK/db entièrement remplacés par la clé MOK du fork
# La clé MOK est celle du paquet : secureboot/ventoy-sort-mok.crt / ventoy-sort-MOK.cer
set -euo pipefail
Q=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/_qemu
SB=/mnt/d/Codex/ventoy/dist/ventoy-sort-build/secureboot
MOKCER=$SB/ventoy-sort-MOK.cer      # DER, c'est le fichier du paquet
MOKCRT=$SB/ventoy-sort-mok.crt      # PEM
SBT_DIR=$Q/sbtest
mkdir -p "$SBT_DIR"; cd "$SBT_DIR"

GUID=$(python3 -c 'import uuid; print(uuid.uuid4())')
echo "GUID d enrôlement MOK : $GUID"

echo "== x64 : PK/KEK/db Microsoft + MOK (db + MokList) =="
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd vars-x64-sb.fd
virt-fw-vars --inplace vars-x64-sb.fd \
    --add-db "$GUID" "$MOKCER" \
    --add-mok "$GUID" "$MOKCER"
virt-fw-vars -i vars-x64-sb.fd -p --hashes | grep -E '^db |^dbx |^MokList' || true

echo
echo "== arm64 : PK/KEK/db = MOK =="
cp /usr/share/AAVMF/AAVMF_VARS.ms.fd vars-a64-sb.fd
virt-fw-vars --inplace vars-a64-sb.fd \
    --set-pk "$GUID" "$MOKCER" --add-kek "$GUID" "$MOKCER" \
    --add-db "$GUID" "$MOKCER"
virt-fw-vars -i vars-a64-sb.fd -p --hashes | grep -E '^db |^dbx |^MokList|^PK |^KEK ' || true
