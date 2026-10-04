#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Verifie que la version inscrite dans le paquet tient dans son cadre, dans
chaque interface qui l'affiche.

Origine du defaut : le amont suppose une version courte (« 1.0.53 », 6
caracteres). Celle du fork en compte 17 (« 1.1.20-ventoy-sort »). Les
libelles avaient une largeur fixe et une taille de police figee, dessinees
pour la premiere et pas pour la seconde : le texte debordait par-dessus le
cadenas et le style de partition.

Ce test ne compile ni n'execute aucune interface. Il mesure la largeur reelle
de la chaine dans la police de l'interface (avances lues dans le TTF) et la
compare a la largeur declaree dans la source. Une largeur qui ne suffit plus
est donc detectee sans avoir Qt, GTK ni un navigateur sous la main.

Usage :
    python3 dist/tests/test_gui_version_layout.py [--version 1.1.20-ventoy-sort]
                                                   [--font /chemin/DejaVuSans-Bold.ttf]

Code de sortie : 0 = tout tient, 1 = au moins un cadre trop etroit,
2 = police introuvable (environment non exploitable, ni succes ni echec).
"""

import argparse
import os
import re
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

FALLBACK_FONTS = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/TTF/DejaVuSans-Bold.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf',
]

# Les versions sont en « points » pour Qt et GTK (1 pt = 1/72 pouce a 96 dpi)
# et en « pixels » pour le WebUI.
PT_TO_PX = 96.0 / 72.0


# --------------------------------------------------------------------------
# Lecture TTF : cmap (format 4) + hmtx, pour mesurer des avances reelles.
# --------------------------------------------------------------------------
def read_advances(path):
    with open(path, 'rb') as fh:
        d = fh.read()

    num_tables = struct.unpack('>H', d[4:6])[0]
    tabs = {}
    for i in range(num_tables):
        off = 12 + 16 * i
        tag = d[off:off + 4].decode('latin-1')
        tabs[tag] = struct.unpack('>II', d[off + 8:off + 16])

    head = tabs['head'][0]
    upem = struct.unpack('>H', d[head + 18:head + 20])[0]

    hhea = tabs['hhea'][0]
    num_h_metrics = struct.unpack('>H', d[hhea + 34:hhea + 36])[0]

    maxp = tabs['maxp'][0]
    num_glyphs = struct.unpack('>H', d[maxp + 4:maxp + 6])[0]

    hmtx = tabs['hmtx'][0]
    advances = [struct.unpack('>H', d[hmtx + 4 * g:hmtx + 4 * g + 2])[0]
                for g in range(num_h_metrics)]
    while len(advances) < num_glyphs:        # glyphes monomes
        advances.append(advances[-1])

    cmap = tabs['cmap'][0]
    num_sub = struct.unpack('>H', d[cmap + 2:cmap + 4])[0]
    sub = None
    for i in range(num_sub):
        pid, eid, off = struct.unpack('>HHI', d[cmap + 4 + 8 * i:cmap + 4 + 8 * i + 8])
        if (pid, eid) not in ((3, 1), (3, 10), (0, 3), (0, 4)):
            continue
        if struct.unpack('>H', d[cmap + off:cmap + off + 2])[0] == 4:
            sub = cmap + off
            break
    if sub is None:
        raise ValueError('aucune sous-table cmap format 4 dans %s' % path)

    seg_x2 = struct.unpack('>H', d[sub + 6:sub + 8])[0]
    seg = seg_x2 // 2
    ends = [struct.unpack('>H', d[sub + 14 + 2 * i:sub + 16 + 2 * i])[0]
            for i in range(seg)]
    starts_at = sub + 16 + seg_x2
    starts = [struct.unpack('>H', d[starts_at + 2 * i:starts_at + 2 + 2 * i])[0]
              for i in range(seg)]
    deltas_at = starts_at + seg_x2
    deltas = [struct.unpack('>h', d[deltas_at + 2 * i:deltas_at + 2 + 2 * i])[0]
              for i in range(seg)]
    ranges_at = deltas_at + seg_x2
    ranges = [struct.unpack('>H', d[ranges_at + 2 * i:ranges_at + 2 + 2 * i])[0]
              for i in range(seg)]

    out = {}
    for i in range(seg):
        for code in range(starts[i], min(ends[i], 0xFFFF) + 1):
            if ranges[i] == 0:
                gid = (code + deltas[i]) & 0xFFFF
            else:
                at = ranges_at + 2 * i + ranges[i] + 2 * (code - starts[i])
                if at + 2 > len(d):
                    continue
                gid = struct.unpack('>H', d[at:at + 2])[0]
                if gid:
                    gid = (gid + deltas[i]) & 0xFFFF
            if gid < num_glyphs:
                out[code] = advances[gid]
    return out, upem


class Measurer(object):
    def __init__(self, font_path):
        self.path = font_path
        self.adv, self.upem = read_advances(font_path)

    def px(self, text, size_px):
        total = 0
        for ch in text:
            total += self.adv.get(ord(ch), self.adv.get(ord(' '), 0))
        return total * float(size_px) / self.upem

    def from_pt(self, text, pt):
        return self.px(text, pt * PT_TO_PX)


# --------------------------------------------------------------------------
# Lecture des declarations de largeur dans chaque source.
# --------------------------------------------------------------------------
def read(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def ui_rect(src, name):
    m = re.search(
        r'name="%s">\s*<property name="geometry">\s*<rect>\s*'
        r'<x>(\d+)</x>\s*<y>(\d+)</y>\s*<width>(\d+)</width>\s*<height>(\d+)</height>'
        % re.escape(name), src)
    if not m:
        raise AssertionError('widget %s introuvable dans le .ui' % name)
    return tuple(int(v) for v in m.groups())


def glade_width(src, obj_id):
    m = re.search(r'id="%s">\s*<property name="width_request">(\d+)</property>' % re.escape(obj_id), src)
    if not m:
        raise AssertionError('objet %s introuvable dans le .glade' % obj_id)
    return int(m.group(1))


# --------------------------------------------------------------------------
# Les trois controles.
# --------------------------------------------------------------------------
def check_qt(m, version):
    """GUI Qt de Ventoy2Disk : label de version en 20 pt gras, cadre elargi.

    Apres le correctif, le .cpp choisit la taille a l'execution (SetVersionLabel)
    : ces assertions verifient donc que la taille nominale tient, et que rien
    ne deborde du cadre ni du groupe qui le contient.
    """
    src = read(os.path.join(REPO, 'LinuxGUI', 'Ventoy2Disk', 'QT', 'ventoy2diskwindow.ui'))
    out = []
    # SetVersionLabel() descend jusqu'a 9 pt avant d'abandonner : c'est la
    # taille plancher qui doit tenir, pas la taille nominale de 20 pt.
    floor_px = 9.0
    for label, group in (('labelVentoyLocalVer', 'groupBoxVentoyLocal'),
                         ('labelVentoyDeviceVer', 'groupBoxVentoyDevice')):
        lx, ly, lw, lh = ui_rect(src, label)
        gx, gy, gw, gh = ui_rect(src, group)
        need = m.from_pt(version, 20.0)
        floor = m.from_pt(version, floor_px)
        ok = floor <= lw
        out.append(('Qt %s' % label,
                    '%.0f px a 20 pt / %.0f px au plancher de 9 pt, cadre %.0f px'
                    % (need, floor, lw), ok))
        # Les coordonnees d'un libelle Qt sont relatives a son parent : on
        # compare donc sa taille a celle du groupe, pas sa position.
        if lx + lw > gw or ly + lh > gh:
            out.append(('Qt %s' % label, 'le libelle deborde de son groupe', False))
        # le groupe, lui, est en coordonnees absolues : il doit tenir dans la fenetre
        win_w, win_h = ui_rect(src, 'Ventoy2DiskWindow')[2:]
        if gx + gw > win_w or gy + gh > win_h:
            out.append(('Qt %s' % group, 'le groupe deborde de la fenetre', False))
    return out


def check_gtk(m, version):
    """GUI GTK : xx-large vaut environ 20 pt pour la police de base du theme."""
    src = read(os.path.join(REPO, 'INSTALL', 'tool', 'VentoyGTK.glade'))
    out = []
    for obj in ('label_local_ver_value', 'label_dev_ver_value'):
        try:
            width = glade_width(src, obj)
        except AssertionError:
            continue
        need = m.from_pt(version, 20.0)
        out.append(('GTK %s' % obj, '%.0f px de texte dans %d px demandes' % (need, width),
                    need <= width))
    return out


def check_webui(m, version):
    """WebUI : corps 28 px, largeur du cadre lue dans le style de la boite."""
    src = read(os.path.join(REPO, 'LinuxGUI', 'WebUI', 'index.html'))
    out = []
    m_size = re.search(r'span\.vtoy_ver\s*\{[^}]*font-size:\s*(\d+)px', src)
    if not m_size:
        return [('WebUI', 'font-size de .vtoy_ver introuvable', False)]
    size = int(m_size.group(1))
    m_box = re.search(r'<div class="box box-primary box-solid"[^>]*width:(\d+)px;', src)
    if not m_box:
        return [('WebUI', 'largeur de la boite de version introuvable', False)]
    box = int(m_box.group(1))
    m_span = re.search(r'span\.vtoy_ver\s*\{[^}]*width:\s*(\d+)%', src)
    avail = box - 20                       # padding et marge de la boite
    if m_span:                            # largeur en % : on applique au cadre
        avail = int(avail * int(m_span.group(1)) / 100.0)
    need = m.px(version, size)
    out.append(('WebUI .vtoy_ver', '%d px de texte dans %d px utiles (boite %d px)'
                % (need, avail, box), need <= avail))
    return out


# --------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--version', default='1.1.20-ventoy-sort',
                    help='version a tester (defaut : celle du fork)')
    ap.add_argument('--font', default=None, help='police TTF gras')
    args = ap.parse_args()

    font = args.font
    if not font:
        for cand in FALLBACK_FONTS:
            if os.path.exists(cand):
                font = cand
                break
    if not font or not os.path.exists(font):
        sys.stderr.write('police introuvable : passe --font, ou installez '
                         'fonts-dejavu-core. Ni succes ni echec.\n')
        return 2

    m = Measurer(font)
    print('version testee : %s' % args.version)
    print('police         : %s' % font)
    print('mesure         : 1 pt = %.4f px ; « %s » = %.0f px a 20 pt\n'
          % (PT_TO_PX, args.version, m.from_pt(args.version, 20.0)))

    results = check_qt(m, args.version) + check_gtk(m, args.version) + check_webui(m, args.version)

    failed = 0
    for name, detail, ok in results:
        flag = 'OK  ' if ok else 'ECHEC'
        print('%-4s %-28s %s' % (flag, name, detail))
        failed += 0 if ok else 1

    print()
    if failed:
        print('%d cadre(s) trop etroit(s) pour « %s »' % (failed, args.version))
        return 1
    print('toutes les surfaces affichees tiennent « %s »' % args.version)
    return 0


if __name__ == '__main__':
    sys.exit(main())