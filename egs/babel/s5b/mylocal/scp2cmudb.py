#!/usr/bin/env python
# $Id: scp2cmudb.py 795 2014-01-30 22:39:53Z arlo $
#
# Convert Swordfish's HTK-formatted SCP file to extract the
# segmentations and write in Radical's UEM format
#

import sys
import os
import re

for line in sys.stdin:
    match = re.match(r'.+=(\S+)\[(\d+),(\d+)\]', line)
    if match:
        fn, start, end = match.groups()
        uid = os.path.basename(fn)
        print "{%s} {FROM %.3f} {TO %.3f}" % (uid, float(start)/100, float(end)/100)
    else:
        sys.stderr.write('Could not parse SCP file\n')
        sys.exit(1)


