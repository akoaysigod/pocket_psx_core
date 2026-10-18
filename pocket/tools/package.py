#!/usr/bin/env python3
"""Assemble the SD card folders for the Pocket PSX core.

usage: package.py --rbf ap_core.rbf_r (--out SDROOT | --zip FILE.zip) [--bios scph1001.bin] [--game GAME.cue [--copy-bins]] ...

Creates the SD card layout: everything in pocket/dist (Cores/akoaysigod.PSX JSON files, Platforms/psx.json, the
"BIOS (no disc)" entry in Assets/psx/akoaysigod.PSX), the bitstream and LICENSE.txt in
Cores/akoaysigod.PSX, and the empty folders the copyrighted files go in: Assets/psx/common (the BIOS, scph1001.bin)
and Assets/psx/common/<game folder> (the game's .bin files). Optionally --bios copies the BIOS in, --game
writes the entry for another .cue (with --copy-bins also its .bin files). Copy SDROOT's contents to the SD card.
With --zip the same layout goes into a zip file instead (or as well, with --out): unzip it at the SD card's root.
"""
import argparse
import json
import os
import shutil
import sys
import tempfile
import zipfile

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import cue2instance  # noqa: E402

CORE = 'akoaysigod.PSX'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rbf', required=True, help='bit-reversed bitstream (.rbf_r)')
    ap.add_argument('--out', help='folder to assemble the SD card layout in')
    ap.add_argument('--zip', help='zip file to write the SD card layout to')
    ap.add_argument('--bios')
    ap.add_argument('--game', action='append', default=[])
    ap.add_argument('--copy-bins', action='store_true')
    a = ap.parse_args()
    if not a.out and not a.zip:
        ap.error('give --out and/or --zip')
    tmp = None
    if not a.out:
        tmp = a.out = tempfile.mkdtemp(prefix='psxpocket_')

    dist = os.path.join(here, '..', 'dist')
    core_dir = os.path.join(a.out, 'Cores', CORE)
    shutil.copytree(os.path.join(dist, 'Cores', CORE), core_dir, dirs_exist_ok=True)
    shutil.copyfile(a.rbf, os.path.join(core_dir, 'bitstream.rbf_r'))
    lic = os.path.join(here, '..', '..', 'LICENSE')     # GPL: goes with every copy of the core
    if os.path.isfile(lic):
        shutil.copyfile(lic, os.path.join(core_dir, 'LICENSE.txt'))
    shutil.copytree(os.path.join(dist, 'Platforms'), os.path.join(a.out, 'Platforms'), dirs_exist_ok=True)
    # game entries ("BIOS (no disc)" boots the BIOS menu without a disc)
    shutil.copytree(os.path.join(dist, 'Assets'), os.path.join(a.out, 'Assets'), dirs_exist_ok=True)
    common = os.path.join(a.out, 'Assets', 'psx', 'common')       # the BIOS goes here
    os.makedirs(common, exist_ok=True)
    if a.bios:
        shutil.copyfile(a.bios, os.path.join(common, 'scph1001.bin'))
    for cue in a.game:
        d = os.path.join(a.out, 'Assets', 'psx', CORE)
        os.makedirs(d, exist_ok=True)
        name = os.path.splitext(os.path.basename(cue))[0]
        sys.argv = ['cue2instance.py', cue, os.path.join(d, name + '.json')]
        cue2instance.main()
        if a.copy_bins:
            inst = json.load(open(os.path.join(d, name + '.json')))['instance']
            gdir = os.path.join(common, inst['data_path'])
            os.makedirs(gdir, exist_ok=True)
            for s in inst['data_slots']:
                src = os.path.join(os.path.dirname(os.path.abspath(cue)), s['filename'])
                print('copying', s['filename'])
                shutil.copyfile(src, os.path.join(gdir, s['filename']))
    # each game entry's folder, for its .bin files (the track slots are platform-common)
    d = os.path.join(a.out, 'Assets', 'psx', CORE)
    for name in os.listdir(d):
        if name.endswith('.json'):
            path = json.load(open(os.path.join(d, name)))['instance'].get('data_path', '')
            if path:
                os.makedirs(os.path.join(common, path), exist_ok=True)
    if a.zip:
        write_zip(a.out, a.zip)
        print('wrote', a.zip)
    if tmp:
        shutil.rmtree(tmp)
    else:
        print('done:', a.out)


def write_zip(root, path):
    """The folder's files and folders (empty ones too) with paths relative to it; .bin files (BIOS, game tracks)
    stored, the rest deflated."""
    d = os.path.dirname(os.path.abspath(path))
    os.makedirs(d, exist_ok=True)
    with zipfile.ZipFile(path, 'w') as z:
        for top, dirs, files in os.walk(root):
            dirs.sort()
            if top != root:
                z.write(top, os.path.relpath(top, root).replace(os.sep, '/') + '/')
            for name in sorted(files):
                if name == '.DS_Store':
                    continue
                full = os.path.join(top, name)
                arc = os.path.relpath(full, root).replace(os.sep, '/')
                comp = zipfile.ZIP_STORED if name.lower().endswith('.bin') else zipfile.ZIP_DEFLATED
                z.write(full, arc, compress_type=comp)


if __name__ == '__main__':
    main()
