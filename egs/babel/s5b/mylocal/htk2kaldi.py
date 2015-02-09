#!/usr/bin/env python
# $Id: htk2kaldi.py 795 2014-01-30 22:39:53Z arlo $
#
# Convert an HTK-formatted SCP feature file (including pseudo-aliased
# segmentation) into a Kaldi text-formatted feature file
#
# This requires feacat to be in the path.  It's all kind of a big
# hack, matching Swordfish IDs to encompassing Kaldi segments

import sys
import os
import re
import subprocess

segments_file = sys.argv[1]
scp_file = sys.argv[2]
feat_range = sys.argv[3]
frame_rate = 100
use_segmentation = False

# Load Kaldi segments
segments = {}
for line in open(segments_file):
    kaldi_id, basename, start_time, end_time = line.strip().split()
    start_frame = int(float(start_time) * frame_rate)
    end_frame = int(float(end_time) * frame_rate + 0.5)
    if basename not in segments:
        segments[basename] = []
    segments[basename].append((kaldi_id, start_frame, end_frame))

# Scan HTK scp file
for line in open(scp_file):
    match = re.match(r'(\S+)=(\S+)\[(\d+),(\d+)\]\B', line)
    if not match:
        # TODO: support simple filenames, without segmentation
        sys.stderr.write("SORRY: for now we only support pseudo-aliased SCP files\n")
        sys.exit(1)
    else:
        # Match to Kaldi segments
        uid, featfile, start_frame, end_frame = match.groups()
        start_frame = int(start_frame)
        end_frame = int(end_frame)
        basename = os.path.splitext(os.path.basename(featfile))[0]
        if basename not in segments:
            sys.stderr.write('WARNING: did not find %s in segments\n' % basename)
            continue
        matched_segment = None
        for segment in segments[basename]:
            if start_frame >= segment[1] and end_frame <= segment[2]:
                matched_segment = segment
                break
        if matched_segment is None:
            sys.stderr.write('WARNING: could not match %s in segments\n' % uid)
            continue
        
        if not use_segmentation:
            # Use the segmentation in dir
            start_frame = matched_segment[1]
            end_frame = matched_segment[2]

        # Print out Kaldi text feature format, using feacat (must be in PATH)
        print segment[0], '['
        stdout = subprocess.check_output(['feacat', 
                                          '-ip', 'htk', '-i', featfile,
                                          '-op', 'ascii', '-o', '-',
                                          '-fr', feat_range,
                                          '-pr', "%d:%d" % (start_frame, end_frame)])
        for line in stdout.split('\n'):
            print ' '.join(line.split()[2:])
        print ']'
