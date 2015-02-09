#!/usr/bin/env python
#
# Quick and dirty script to downcase and encode a slf with hescii.
#

import re
import sys
import hescii
from optparse import OptionParser

parser = OptionParser()
parser.add_option("--lower", type="string", dest="lower", default="true")
options, arguments = parser.parse_args()

for line in sys.stdin:
    dat = line.decode('utf-8').split()
    if options.lower == 'true':
        word = dat[0].lower().encode('utf-8')
    else:
        word = dat[0].encode('utf-8')
    if not (re.match(r'[<\[]\S+[>\]]', word) or re.match(r'^\!', word)):
        dat[0] = '-'.join([hescii.dumps(x) for x in word.split('-')])
    print " ".join(dat)
