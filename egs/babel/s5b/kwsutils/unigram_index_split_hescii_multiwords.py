#!/usr/bin/env python
#
# Given a unigram index file (e.g. as output by lattice tool) in
# hescii encoding, produce a new unigram index file where multiwords
# are split into their own lines. The time for each multiword is just
# the time of the original divided by the number of words. The score
# is copied.
#
# Example
#
# Before:
#
# BABEL_BP_107_41661_20120329_022249_inLine 0.10 0.20 0.005725 x63c3a1635f5f7468e1bba9
#
# After:
#
# BABEL_BP_107_41661_20120329_022249_inLine 0.10 0.15 0.005725 x63c3a163
# BABEL_BP_107_41661_20120329_022249_inLine 0.15 0.20 0.005725 x7468e1bba9

import sys
import gzip
import bz2
import string
import re

import hescii

inpath, outpath = sys.argv[1:]

if inpath.endswith('.bz') or inpath.endswith('.bz2'):
    infile = bz2.BZ2File(inpath, 'rb')
elif inpath.endswith('.gz'):
    infile = gzip.GzipFile(inpath, 'rb')
else:
    infile = open(inpath, 'r')

if outpath.endswith('.bz') or outpath.endswith('.bz2'):
    outfile = bz2.BZ2File(outpath, 'wb')
elif outpath.endswith('.gz'):
    outfile = gzip.GzipFile(outpath, 'wb')
else:
    outfile = open(outpath, 'w')

for line in infile:
    if len(line.strip()) == 0: # ignore blank lines
        continue
    (name, start, end, score, hesciiword) = string.split(line)
    words = string.split(unicode(hescii.loads(hesciiword), 
                                 'UTF-8', 
                                 'strict'), 
                         '__')
    if len(words) == 1:
        outfile.write(line)
    elif len(words) > 1:
        startf = float(start)
        endf = float(end)
        durf = endf - startf
        worddur = durf/len(words)
        for ii in range(0, len(words)):
            st = startf + ii*worddur
            et = st + worddur
            outfile.write("%s %f %f %s %s\n" % (name, st, et, score,
                                                hescii.dumps(words[ii].encode('UTF-8', 'strict'))))

sys.exit(0)
