#!/usr/bin/python
import sys
import itertools
import random
import argparse

parser = argparse.ArgumentParser(description="Generate pairs.")
parser.add_argument('--pairs-per-spk', type=int, default=10, dest='fake_pairs')
parser.add_argument('--random-seed', type=int, default=0, dest='random_seed')
parser.add_argument('spk2utt_file')
parser.add_argument('wav_file')
parser.add_argument('same_spk_file')
parser.add_argument('diff_spk_file')
args = parser.parse_args()

fake_pairs=args.fake_pairs
random.seed(args.random_seed)

spk2utt_file = args.spk2utt_file
wav_file = args.wav_file
same_spk_file = args.same_spk_file
diff_spk_file = args.diff_spk_file

same_spk_fh = open(same_spk_file, 'w')
diff_spk_fh = open(diff_spk_file, 'w')

utt2wav = {}
with open(wav_file, 'r') as f:
  for line in f:
    fields = line.split()
    utt = fields[0]
    wav = fields[-2]
    if (fields[5] == "-c"):
      wav = wav + "_" + fields[6]
    utt2wav[utt] = wav

spk2utts = {}
paired = {}      # we want make sure speakers are paired only once
with open(spk2utt_file, 'r') as f:
  for line in f:
    fields = line.split()
    spk = fields[0]
    spk2utts[spk] = fields[1:]
    paired[spk+" "+spk] = True
    for subset in itertools.combinations(fields[1:], 2):
      if len(subset) != 0:
        same_spk_fh.write(subset[0] + " " + subset[1] + "\n")

for spk in spk2utts:
  utts = spk2utts[spk]
  for i in range(0,fake_pairs):
    count = 0
    while count < 10:
      count += count+1
      other_spk = random.choice(list(spk2utts.keys()))
      if (other_spk == spk):
        continue;
      elif (spk+" "+other_spk in paired):
        continue;
      else:
        other_utts = spk2utts[other_spk]
        break_same = False
        for utt in utts:
          if break_same:
            break
          for other_utt in other_utts:
            if (utt2wav[utt] == utt2wav[other_utt]):    # two speakers have same utterance
              print (spk + " vs " + other_spk + " have utts " + utt + " and " + other_utt + " that share same wav " + utt2wav[utt])
              print ("adding this to same spk")
              break_same = True
              break
        if break_same: # add to match list
          paired[spk+" "+other_spk] = True
          paired[other_spk+" "+spk] = True
          total_utts = list(set(utts + other_utts))
          for subset in itertools.combinations(total_utts, 2):
            if len(subset) != 0:
              same_spk_fh.write(subset[0] + " " + subset[1] + "\n")
          continue
        else:
          break;
    if break_same == False:
      paired[spk+" "+other_spk] = True
      paired[other_spk+" "+spk] = True
      for utt in utts:
        for other_utt in other_utts:
          diff_spk_fh.write(utt + " " + other_utt + "\n")

same_spk_fh.close()
diff_spk_fh.close()
