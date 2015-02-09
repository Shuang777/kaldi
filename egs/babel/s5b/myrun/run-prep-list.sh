#!/bin/bash

{
set -e
set -o pipefail


. ./lang.conf

for i in train dev10h eval; do
  outfile=$(eval echo \$${i}_data_list)
  dir=$(dirname $outfile)
  [ -d $dir ] || mkdir -p $dir
  eval ls \$${i}_data_dir/audio/ | tr '/.' ' ' | awk '{print $(NF-1)}' > $outfile
done

## eval part1
if [ -f "$evalp1_stm_file" ]; then
  grep -v '^;;' $evalp1_stm_file | awk '{print $1}' | uniq > $evalp1_data_list
fi

if [ ! -z $unsup_data_dir ]; then
  ls $unsup_data_dir/audio/ | tr '/.' ' ' | awk 'NR==FNR {a[$1]; next} !($(NF-1) in a) {print $(NF-1)}' $train_data_list /dev/stdin > $unsup_data_list
fi
}
