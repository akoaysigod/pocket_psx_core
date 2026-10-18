#!/usr/bin/env python3
"""Make an Analogue Pocket instance JSON for a PSX disc from its .cue file.

The Pocket core streams each track from its own data slot (track 1 = slot 16, track 2 = slot 17, ...), so the
disc must be a cue with one .bin file per track (Redump style): track 1 MODE2/2352 (or MODE1/2352) data, the
other tracks AUDIO with their 2 second pregap inside the file (INDEX 00 00:00:00, INDEX 01 00:02:00).

usage: cue2instance.py GAME.cue [OUT.json]
Copy OUT.json (default: GAME.json next to the cue) to /Assets/psx/akoaysigod.PSX/ on the SD card, and the .bin
files to /Assets/psx/common/<folder of the cue>/.
"""
import json
import os
import re
import sys

TRACK_ID_BASE = 16
MAX_TRACKS = 24


def parse_cue(path):
    files, tracks = [], []
    for raw in open(path, encoding='utf-8', errors='replace'):
        line = raw.strip()
        m = re.match(r'FILE\s+"(.*)"\s+(\S+)$', line) or re.match(r'FILE\s+(\S+)\s+(\S+)$', line)
        if m:
            if m.group(2).upper() != 'BINARY':
                sys.exit('unsupported FILE type: ' + line)
            files.append(m.group(1))
            continue
        m = re.match(r'TRACK\s+(\d+)\s+(\S+)', line)
        if m:
            tracks.append({'number': int(m.group(1)), 'type': m.group(2).upper(), 'file': len(files) - 1, 'index': {}})
            continue
        m = re.match(r'INDEX\s+(\d+)\s+(\d+):(\d+):(\d+)', line)
        if m and tracks:
            tracks[-1]['index'][int(m.group(1))] = (int(m.group(2)) * 60 + int(m.group(3))) * 75 + int(m.group(4))
            continue
        if line.startswith('PREGAP') or line.startswith('POSTGAP'):
            sys.exit('PREGAP/POSTGAP is not supported (use a Redump style cue with the pregap inside the files)')
    return files, tracks


def find_file(folder, name, number):
    if os.path.exists(os.path.join(folder, name)):
        return name
    # renamed dumps: match by "(Track N)"
    pat = re.compile(r'\(Track 0?%d\)\.bin$' % number, re.IGNORECASE)
    hits = [f for f in os.listdir(folder) if pat.search(f)]
    if len(hits) == 1:
        print('note: %s not found, using %s' % (name, hits[0]))
        return hits[0]
    sys.exit('file for track %d not found: %s' % (number, name))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cue = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(cue)[0] + '.json'
    folder = os.path.dirname(os.path.abspath(cue))
    files, tracks = parse_cue(cue)

    if len(files) != len(tracks):
        sys.exit('the cue needs one .bin file per track (found %d files for %d tracks)' % (len(files), len(tracks)))
    if len(tracks) > MAX_TRACKS:
        sys.exit('at most %d tracks are supported' % MAX_TRACKS)
    slots = []
    for i, t in enumerate(tracks):
        if t['number'] != i + 1 or t['file'] != i:
            sys.exit('tracks must be numbered 1.. in file order')
        if i == 0:
            if t['type'] not in ('MODE2/2352', 'MODE1/2352') or t['index'].get(1, 0) != 0:
                sys.exit('track 1 must be MODE2/2352 data starting at INDEX 01 00:00:00')
        else:
            if t['type'] != 'AUDIO' or t['index'].get(1) != 150 or t['index'].get(0, 0) != 0:
                sys.exit('track %d: expected AUDIO with INDEX 00 00:00:00 and INDEX 01 00:02:00' % t['number'])
        name = find_file(folder, files[i], t['number'])
        size = os.path.getsize(os.path.join(folder, name))
        if size % 2352:
            print('warning: %s is not a whole number of 2352-byte sectors' % name)
        slots.append({'id': TRACK_ID_BASE + i, 'filename': name})

    instance = {'instance': {'magic': 'APF_VER_1', 'data_path': os.path.basename(folder) + '/', 'data_slots': slots}}
    with open(out, 'w') as f:
        json.dump(instance, f, indent=4)
        f.write('\n')
    print('wrote %s (%d tracks)' % (out, len(slots)))


if __name__ == '__main__':
    main()
