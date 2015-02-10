#!/bin/bash
{
set -e
set -o pipefail

if [ $# -ne 2 ]; then 
  echo "Usage: prepare working directory for different languages"
  echo " e.g.: prepworkdir.sh 102flp thisdir"
  exit 1
fi

taskname=$1
workdir=$2

WORK_ROOT=$(cd $(dirname $0) && pwd)
source $WORK_ROOT/path.sh

function getlangconf ()
{
  langid=${taskname:0:3}
  langtype=${taskname:3:3}
  langname=`babelname -lang $langid | tr "[:upper:]" "[:lower:]" | cut -d '_' -f 1`
  
  if [ $langtype == "flp" ]; then
    langtypeexp='fullLP'
  elif [ $langtype == "llp" ]; then
    langtypeexp='limitedLP'
  else
    echo "langtype $langtype not recognized!"; exit 1
  fi
  langconf=${langid}-${langname}-${langtypeexp}.official.conf
}

if [[ $taskname =~ "multi" ]]; then
  echo "please link your own lang.conf"
else
  getlangconf
fi

mkdir -p $workdir
{
  cd $workdir
  for file in steps utils local mysteps myutils mylocal; do
    ln -s $WORK_ROOT/$file $file
  done

  for file in `ls $WORK_ROOT/myrun`; do
    ln -s $WORK_ROOT/myrun/$file $file
  done

  for file in path.sh cmd_slurm.sh; do
    ln -s $WORK_ROOT/$file $file
  done

  ln -s cmd_slurm.sh cmd.sh
  ln -s $WORK_ROOT/myconf conf
  ln -s conf/lang/$langconf lang.conf

  mkdir log
}

echo "prepare done task $taskname in $workdir done"
exit 0
}
