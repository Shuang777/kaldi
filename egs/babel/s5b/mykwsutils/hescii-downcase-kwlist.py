#!/usr/bin/env python
#
# Quick and dirty script to convert a .kwlist.xml file to lowercase
# and hescii encode.
#
# Usage: hescii-downcase-kwlist.py infile.kwlist.xml > outfile.kwlist.xml
#
# Changes:
#
# March 12, 2013 Adam Janin
# Hyphens in keywords are not hesciied

import sys
import xml.etree.ElementTree as ET

import hescii

tree = ET.parse(sys.argv[1])
root = tree.getroot()

mixed = 0
for kwtext in root.iter('kwtext'):
    lc = kwtext.text.lower()
    if lc != kwtext.text:
        mixed = mixed + 1
    kwtext.text = '-'.join([hescii.dumps(x.encode('utf-8')) for x in lc.split('-')])

tree.write(sys.stdout)

sys.stderr.write('Mixed-case entries: %d\n'%(mixed))
