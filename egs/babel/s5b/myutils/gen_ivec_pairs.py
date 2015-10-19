#!/usr/bin/python
import sys
import itertools

spk2utt_file = sys.argv[1]
same_spk_file = sys.argv[2]
diff_spk_file = sys.argv[3]

same_spk_fh = open(same_spk_file, 'w')
diff_spk_fh = open(diff_spk_file, 'w')

last_utts = []
with open(spk2utt_file, 'r') as f:
  for line in f:
    fields = line.split()
    spk=fields[0]
    for utt in fields[1:]:
      same_spk_fh.write(utt + " " + utt + "\n")
    for subset in itertools.combinations(fields[1:], 2):
      same_spk_fh.write(subset[0] + " " + subset[1] + "\n")
    for pair in itertools.product(last_utts, fields[1:]):
      diff_spk_fh.write(pair[0] + " " + pair[1] + "\n")
    last_utts = fields[1:]

