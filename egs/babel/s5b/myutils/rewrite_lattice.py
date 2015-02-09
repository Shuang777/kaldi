#!/usr/bin/env python
# Convert utterance ID format from Kaldi/Radical to Swordfish-style
# ids, e.g. BABEL_BP_101_10470_20111118_172644_inLine_0005747_0005997
#
# Also downcase and hesciify it.

import sys
import os
import gzip
import re
import hescii

segments, feat_frame_digits, feat_frame_rate, hescii_lattice_dir = sys.argv[1:]

template = "%%s_%%0%sd_%%0%sd" % (feat_frame_digits, feat_frame_digits)

radical2swordfish = {}
for line in open(segments):
    radical_id, swordfish_id, start, end = line.strip().split()
    start = int(float(start) * int(feat_frame_rate))
    end = int(float(end) * int(feat_frame_rate))
    radical2swordfish[radical_id] = template % (swordfish_id, start, end)

buff = ''
swordfish_id = None
for line in sys.stdin:
    match = re.match(r'UTTERANCE=(\S+)\b', line)
    if match:
        radical_id = match.group(1)
        if radical_id in radical2swordfish:
            swordfish_id = radical2swordfish[radical_id]
            buff += 'UTTERANCE=' + swordfish_id + '\n'
        else:
            sys.stderr.write('Could not map Radical ID: ' + radical_id + '\n')
            sys.exit(1)
    else:
        # Modified from hescii-downcase-lattice.py
        dat = line.split()
        if len(dat) == 7 and dat[3].startswith('W='):
            word = dat[3].split('=')[1].lower()
            if word[0] == '<' and word[-1] == '>':
                buff += line
            else:
                dat[3] = 'W=' + '-'.join([hescii.dumps(x) for x in word.split('-')])
                buff += "\t".join(dat) + '\n'
        else:
            buff += line

if swordfish_id is None:
    sys.stderr.write('Could not find Radical ID mapping in: ' + segments + '\n') 
    sys.exit(1)

with gzip.open(os.path.join(hescii_lattice_dir, swordfish_id + '.slf.gz'), 'w') as f:
    f.write(buff)
