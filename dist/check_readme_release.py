#!/usr/bin/env python3
# =====================================================================================
# check_readme_release.py — les sommes SHA-256 et les liens de release inscrits dans
# README.md / README.fr.md correspondent-ils encore à la VRAIE release GitHub ?
#
# Le README est le premier point de contact du fork : une empreinte fausse, un nom
# d'asset renommé ou un lien de tag périmé y sont immédiatement copiés par les
# lecteurs. Ce script confronte le README à l'API GitHub, sans télécharger les
# paquets (80 Mo) : les empreintes sont lues dans les petits fichiers SHA256SUMS*
# joints à la release, qui sont la référence publiée.
#
# Contrôles
#   1. COHÉRENCE : les deux README déclarent le même tag, les mêmes assets et les
#      mêmes empreintes
#   2. TAG       : la release annoncée existe, et /releases/latest pointe bien
#      dessus (échec dès qu'une release plus récente est publiée sans que les
#      README soient mis à jour)
#   3. ASSETS    : le tableau du README énumère exactement les assets de la release,
#      et chaque URL de téléchargement est celle annoncée par l'API
#   4. SOMMES    : tout fichier telechargeable annonce une empreinte, et chaque
#      SHA-256 inscrit au README — dans le tableau ou dans la liste « asset —
#      somme » qui le suit — est conforme aux fichiers SHA256SUMS* publiés
#      (jamais recalculé : on ne télécharge pas les paquets)
#   5. LIENS     : les liens externes (site amont, FAQ, badges…) répondent ; en
#      échec simple → avertissement, avec --strict-links → échec bloquant
#
# Usage :
#   python check_readme_release.py                # contrôles 1 à 5 (réseau)
#   python check_readme_release.py --offline      # contrôle 1 seul, sans réseau
#   python check_readme_release.py --strict-links # les liensexternes bloquent
#   python check_readme_release.py --repo AUTRE/FORK --tag v1.1.18-Fork
#
# Codes de retour : 0 = PASS, 1 = au moins un FAIL.
# Variables d'environnement : GH_TOKEN (ou GITHUB_TOKEN) pour élever le quota de
# l'API ; REPO pour le dépôt par défaut.
# =====================================================================================
import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

REPO_PAR_DEFAUT = os.environ.get("REPO", "Endymi0n74/ventoy-fork")
TIMEOUT = 25

# https://github.com/<prop>/<repo>/releases/download/<tag>/<asset>
RE_TELECHARGE = re.compile(
    r"https://github\.com/([^/\s]+)/([^/\s]+)/releases/download/([^/\s)]+)/([^)\s]+)")
# https://github.com/<prop>/<repo>/releases/tag/<tag>
RE_TAG = re.compile(r"https://github\.com/([^/\s]+)/([^/\s]+)/releases/tag/([^)\s]+)")
RE_LATEST = re.compile(r"https://github\.com/([^/\s]+)/([^/\s]+)/releases/latest")
RE_MD_LINK = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")
RE_SOMME = re.compile(r"\b([0-9a-f]{64})\b")
# Ligne de la liste des sommes : « - `asset.zip` — `6eb3...` ». Les sommes sont
# hors du tableau (une cellule de tableau ne peut pas se couper), donc on les lit
# aussi bien dans le tableau que dans cette liste.
RE_LIGNE_SOMME = re.compile(r"`([^`]+)`\s*[—–: -]\s*`([0-9a-f]{64})`")
STOP_URL = set(" \t\r\n()<>[]\"'`")

LISEURS = ("README.md", "README.fr.md")


# ------------------------------- utilitaires ----------------------------------------
def charger(chemin):
    """Lit un fichier et normalise les fins de ligne (README.md est en CRLF)."""
    with open(chemin, encoding="utf-8") as f:
        return f.read().replace("\r\n", "\n")


def urls_http(texte):
    """Toutes les URL http(s) du texte, sans Those des liens Markdown."""
    urls, out = set(), set()
    for m in re.finditer(r"https?://", texte):
        i = m.start()
        while i < len(texte) and texte[i] not in STOP_URL:
            i += 1
        out.add(texte[m.start():i].rstrip(".,;:!"))
    return out


def requete(url, token=None, entetes=None, max_octets=None):
    """GET HTTP. Retourne (code, octets). Le code est 0 si le réseau a échoué."""
    h = {"User-Agent": "check_readme_release"}
    if token:
        h["Authorization"] = "Bearer " + token
    if entetes:
        h.update(entetes)
    req = urllib.request.Request(url, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return r.status, r.read() if max_octets is None else r.read(max_octets)
    except urllib.error.HTTPError as e:
        return e.code, b""
    except Exception as e:                       # réseau coupé, DNS, TLS...
        return 0, str(e).encode("utf-8", "replace")


def api_chemin(token, *bits):
    return "https://api.github.com/repos/%s/%s" % (REPO_PAR_DEFAUT, "/".join(bits))


# ------------------------------ analyse du README ----------------------------------
class Declaration(object):
    """Ce qu'un README déclare sur une release."""

    def __init__(self, fichier, texte):
        self.fichier = fichier
        self.texte = texte
        self.tag = None               # tag annoncé comme « dernière version »
        self.assets = {}              # nom -> (url, somme ou None)
        self.tags_vus = set()         # tous les /releases/tag/... mentionnés
        self.utilise_latest = False
        self.analyser()

    def analyser(self):
        # Tag principal : celui qui suit le titre de section « dernière version ».
        for titre in ("## Latest release", "## Dernière version stable"):
            i = self.texte.find(titre)
            if i != -1:
                fin = self.texte.find("\n## ", i + 1)
                bloc = self.texte[i:fin if fin != -1 else len(self.texte)]
                m = RE_TAG.search(bloc)
                if m:
                    self.tag = m.group(3)
                break
        for m in RE_TAG.finditer(self.texte):
            self.tags_vus.add(m.group(3))
        self.utilise_latest = bool(RE_LATEST.search(self.texte))
        # Tableau des assets : une ligne = une cellule Type, une cellule lien de
        # téléchargement, puis la colonne SHA-256 éventuelle.
        for ligne in self.texte.split("\n"):
            if not ligne.startswith("|") or RE_TELECHARGE.search(ligne) is None:
                continue
            cellules = [c.strip() for c in ligne.strip().strip("|").split("|")]
            if len(cellules) < 2:
                continue
            m = RE_MD_LINK.search(cellules[1])
            if not m:
                continue
            nom, url = m.group(1), m.group(2)
            somme = RE_SOMME.search(ligne)
            self.assets[nom] = (url, somme.group(1) if somme else None)
        # Sommes listees sous le tableau, hors de toute cellule.
        for m in RE_LIGNE_SOMME.finditer(self.texte):
            nom, somme = m.group(1), m.group(2)
            if nom in self.assets and self.assets[nom][1] is None:
                self.assets[nom] = (self.assets[nom][0], somme)

    def resume(self):
        return "%s : tag %s, %d assets (%d avec somme)" % (
            self.fichier, self.tag, len(self.assets),
            sum(1 for _, s in self.assets.values() if s))


# ------------------------------- contrôles ------------------------------------------
def controler_coherence(decls, out):
    out("1. cohérence des deux README")
    ok = True
    fr = next((d for d in decls if d.fichier.endswith(".fr.md")), None)
    en = next((d for d in decls if not d.fichier.endswith(".fr.md")), None)
    if not en or not fr:
        out("   [FAIL] il faut README.md et README.fr.md")
        return False
    if en.tag != fr.tag:
        out("   [FAIL] tag différent : %s / %s" % (en.tag, fr.tag))
        ok = False
    else:
        out("   [ok] même tag : %s" % en.tag)
    if not en.tag:
        out("   [FAIL] aucun tag de release déclaré")
        return False
    if set(en.assets) != set(fr.assets):
        out("   [FAIL] assets différents :")
        out("         seulement EN : %s" % sorted(set(en.assets) - set(fr.assets)))
        out("         seulement FR : %s" % sorted(set(fr.assets) - set(en.assets)))
        ok = False
    else:
        out("   [ok] mêmes %d assets : %s" % (len(en.assets), ", ".join(sorted(en.assets))))
    for nom in sorted(set(en.assets) & set(fr.assets)):
        se, sf = en.assets[nom], fr.assets[nom]
        if se[1] != sf[1]:
            out("   [FAIL] somme différente pour %s :\n"
                "         EN %s\n         FR %s" % (nom, se[1], sf[1]))
            ok = False
        if se[0] != sf[0]:
            out("   [FAIL] URL différente pour %s" % nom)
            ok = False
    return ok


def controler_tag(decls, token, out, allow_newer=False):
    out("2. existence de la release annoncée")
    ok = True
    vus = sorted(set().union(*[d.tags_vus for d in decls]))
    for tag in vus:
        code, corps = requete(api_chemin(token, "releases", "tags", tag), token)
        if code == 200:
            out("   [ok] release %s existe (%s)" % (tag, json.loads(corps).get("tag_name")))
        else:
            out("   [FAIL] release %s introuvable (HTTP %s)" % (tag, code))
            ok = False
    if any(d.utilise_latest for d in decls):
        code, corps = requete(api_chemin(token, "releases", "latest"), token)
        if code == 200:
            latest = json.loads(corps).get("tag_name")
            attendu = decls[0].tag
            if latest == attendu:
                out("   [ok] /releases/latest pointe sur %s" % latest)
            elif allow_newer:
                out("   [ok] /releases/latest vaut %s, les README annoncent %s "
                    "(toléré : publication de release, README à jour au prochain push)"
                    % (latest, attendu))
            else:
                out("   [FAIL] /releases/latest vaut %s mais les README annoncent "
                    "%s — mettre à jour les README" % (latest, attendu))
                ok = False
        else:
            out("   [FAIL] /releases/latest illisible (HTTP %s)" % code)
            ok = False
    return ok


def controler_assets(decl, release, out):
    out("3. assets annoncés contre assets publiés")
    publies = {a["name"]: a for a in release.get("assets", [])}
    declares = decl.assets
    ok = True
    if set(publies) != set(declares):
        out("   [FAIL] l'inventaire ne correspond pas à la release")
        out("         publiés mais absents du README : %s" % sorted(set(publies) - set(declares)))
        out("         au README mais absents de la release : %s" % sorted(set(declares) - set(publies)))
        ok = False
    else:
        out("   [ok] les %d assets de la release sont tous au README" % len(publies))
    for nom in sorted(set(publies) & set(declares)):
        attendu = publies[nom]["browser_download_url"]
        if declares[nom][0] != attendu:
            out("   [FAIL] URL de %s\n         README : %s\n         release : %s"
                % (nom, declares[nom][0], attendu))
            ok = False
    if ok:
        out("   [ok] toutes les URL de téléchargement sont celles de l'API")
    return ok


def controler_sommes(decl, release, token, out):
    """Confronte les SHA-256 du README aux fichiers SHA256SUMS* de la release.

    On ne télécharge pas les paquets : les sommes publiées sont la référence, et
    ce sont elles que l'API expose comme assets (197 à 1 112 octets)."""
    out("4. sommes SHA-256 contre les SHA256SUMS publiés")
    wanted = {nom: somme for nom, (_, somme) in decl.assets.items() if somme}
    if not wanted:
        out("   [FAIL] aucune somme SHA-256 annoncée dans le README")
        return False
    # Tout fichier telechargeable doit declarer son empreinte : un asset sans
    # somme est inverifiable pour le lecteur. Les fichiers SHA256SUMS* sont
    # eux-memes des fichiers de sommes, pas des archives a verifier.
    sans_somme = sorted(nom for nom in decl.assets
                        if not nom.startswith("SHA256SUMS") and nom not in wanted)
    ok = not sans_somme
    if sans_somme:
        out("   [FAIL] %d asset(s) telechargeable(s) sans somme annoncee : %s"
            % (len(sans_somme), ", ".join(sans_somme)))
    publies = {a["name"]: a for a in release.get("assets", [])}
    reference = {}
    for nom in sorted(publies):
        if not nom.startswith("SHA256SUMS"):
            continue
        code, corps = requete(publies[nom]["browser_download_url"], token)
        if code != 200:
            out("   [FAIL] %s illisible (HTTP %s)" % (nom, code))
            return False
        for ligne in corps.decode("utf-8", "replace").splitlines():
            ligne = ligne.strip()
            if not ligne:
                continue
            parties = ligne.split(None, 1)
            if len(parties) == 2 and RE_SOMME.fullmatch(parties[0]):
                fichier = parties[1].strip().lstrip("*")
                reference[fichier] = parties[0].lower()
        out("   [ok] %s lu (%d lignes)" % (nom, len(corps)))
    for nom, somme in sorted(wanted.items()):
        publiee = reference.get(nom)
        if publiee is None:
            out("   [FAIL] %s : aucune somme publiée dans les SHA256SUMS*" % nom)
            ok = False
        elif publiee != somme:
            out("   [FAIL] %s :\n         README : %s\n         publié : %s" % (nom, somme, publiee))
            ok = False
        else:
            out("   [ok] %s : %s…" % (nom, somme[:16]))
    fichiers_sommes = sorted(nom for nom in decl.assets if nom.startswith("SHA256SUMS"))
    if fichiers_sommes:
        out("   [ok] %d fichiers de sommes (sans empreinte propre) : %s"
            % (len(fichiers_sommes), ", ".join(fichiers_sommes)))
    return ok


def controler_liens(decls, token, out, strict):
    """Sonde les liens externes. Les URL de téléchargement sont ignorées : leur
    existence et leur forme sont déjà contrôlées contre l'API (contrôles 2-4), et
    les sonderテルait faire télécharger 160 Mo."""
    out("5. liens externes")
    telechargements = set()
    for d in decls:
        for nom, (url, _) in d.assets.items():
            telechargements.add(url)
        for m in RE_TELECHARGE.finditer(d.texte):
            telechargements.add(m.group(0))
    a_tester = set()
    for d in decls:
        for u in urls_http(d.texte):
            if u not in telechargements:
                a_tester.add(u)
    ok, ko = True, 0
    for u in sorted(a_tester):
        code, _ = requete(u, token, max_octets=4096)
        if code == 0 or code >= 400:
            out("   %s %s (HTTP %s)" % ("[FAIL]" if strict else "[warn]", u, code))
            if strict:
                ok = False
            ko += 1
        else:
            out("   [ok] %s (HTTP %s)" % (u, code))
    if not ko:
        out("   [ok] %d liens externes, aucun en échec" % len(a_tester))
    elif not strict:
        out("   (%d lien(s) en échec — le site amont est hors de notre contrôle ; "
            "--strict-links pour bloquer)" % ko)
    return ok


# ---------------------------------- main -------------------------------------------
def main():
    global REPO_PAR_DEFAUT
    ap = argparse.ArgumentParser(
        description="Vérifie les sommes SHA-256 et liens de release des README "
                    "contre la vraie release GitHub")
    ap.add_argument("--offline", action="store_true",
                    help="contrôle de cohérence seul, aucun accès réseau")
    ap.add_argument("--strict-links", action="store_true",
                    help="un lien externe en échec fait échouer le contrôle")
    ap.add_argument("--repo", default=REPO_PAR_DEFAUT, help="propriétaire/dépôt")
    ap.add_argument("--tag", default=None, help="tag attendu (défaut : lu dans le README)")
    ap.add_argument("--readme", action="append", default=None,
                    help="fichier à contrôler (défaut : README.md et README.fr.md)")
    ap.add_argument("--allow-newer-release", action="store_true",
                    help="tolère que /releases/latest soit plus récent que la release "
                         "annoncée dans les README (cas d'un événement release : les "
                         "paquets binaires se attachent après coup)")
    args = ap.parse_args()

    REPO_PAR_DEFAUT = args.repo
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or None

    def out(ligne):
        print(ligne)

    fichiers = args.readme or list(LISEURS)
    decls = []
    for f in fichiers:
        try:
            decls.append(Declaration(f, charger(f)))
        except OSError as e:
            out("   [FAIL] %s illisible : %s" % (f, e))
    if not decls:
        print("RESULTAT : FAIL")
        return 1
    for d in decls:
        out(d.resume())

    tout_ok = controler_coherence(decls, out)

    if args.offline:
        out("2-5. contrôles réseau ignorés (--offline)")
    else:
        tag = args.tag or decls[0].tag
        code, corps = requete(api_chemin(token, "releases", "tags", tag), token)
        if code != 200:
            out("   [FAIL] release %s illisible via l'API (HTTP %s)" % (tag, code))
            tout_ok = False
        else:
            release = json.loads(corps)
            out("   [ok] release %s (%d assets, publiée le %s)"
                % (tag, len(release.get("assets", [])), release.get("published_at")))
            tout_ok &= controler_tag(decls, token, out, args.allow_newer_release)
            tout_ok &= controler_assets(decls[0], release, out)
            tout_ok &= controler_sommes(decls[0], release, token, out)
        tout_ok &= controler_liens(decls, token, out, args.strict_links)

    print("RESULTAT :", "PASS" if tout_ok else "FAIL")
    return 0 if tout_ok else 1


if __name__ == "__main__":
    sys.exit(main())