#!/bin/bash

folders="GetDirections"
for i in $folders; do
  mkdir -p processed/$i
  for file in `ls audiofiles/$i`; do
    base=${file%.wav}
    sox audiofiles/$i/$file -r 16000 -t raw processed/$i/$base.raw
    sox audiofiles/$i/$file -r 8000 -t wav processed/$i/$base.8k.wav
    shout_segment -a processed/$i/$base.raw --am-segment /u/drspeech/opt/shout/shout.sad --meta-out processed/$i/$base.rttm
    myutils/segment.pl processed/$i/$base.rttm processed/$i/$base.8k.wav processed/$i/$base
  done
done
