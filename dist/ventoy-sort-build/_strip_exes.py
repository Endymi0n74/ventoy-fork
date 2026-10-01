#!/usr/bin/env python3
"""Retire la section « exes Ventoy2Disk » (MSBuild) du script Linux."""
import sys

path = "/mnt/d/Codex/ventoy/dist/ventoy-sort-build/build_ventoy_sort_linux.sh"
with open(path, encoding="utf-8") as f:
    lines = f.readlines()

start = None
end = None
for i, line in enumerate(lines):
    if "Étape 5 — exes Ventoy2Disk" in line:
        start = i - 1  # séparateur '# ----...' au-dessus
    if "Étape 5 — mise en place du paquet" in line:
        end = i - 1    # séparateur au-dessus de ce titre
if start is None or end is None or end <= start:
    sys.exit(f"marqueurs introuvables ou mal ordonnés: start={start} end={end}")

removed = end - start
del lines[start:end]
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
print(f"{removed} lignes supprimées (exes MSBuild) — lignes restantes: {len(lines)}")
