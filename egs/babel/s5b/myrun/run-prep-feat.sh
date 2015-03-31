#!/bin/bash

{
set -e
set -o pipefail

function die () {
  echo -e "ERROR: $1\n"
  exit 1
}

echo "$0 $@"

# Begin configuration
type=train      # train, dev10h, eval, trainall, dev10h, unsup
feattype=plp    # plp, swd, mfcc, flow, msgpp, rastapp, bn, tandem
srctype=
srctype2=
bnnet=
cmd=./cmd.sh
segmode=uem     # uem, pem, unseg, seg
segfile=
# End configuration

. ./path.sh
. parse_options.sh
. $cmd
. ./lang.conf

[ $type == "trainall" ] && type=train && typeext=all || typeext=''
[[ $feattype =~ "bn" ]] && [ -z $bnnet ] && die "Please provide bnnet for bn feature"
[[ $feattype =~ "bn" ]] && [ -z $srctype ] && die "Please provide srctype for bn feature"
[[ $feattype == "fmllr" ]] && [ -z $srctype ] && die "Please provide srctype for fmllr feature"

tandemmode=false
[ $feattype == "tandem" ] && [ -z $srctype ] && die "Please provide srctype for tandem feature"
[ $feattype == "tandem" ] && [ -z $srctype2 ] && die "Please provide srctype2 for tandem feature"

nj=$(eval echo "\$${type}_nj")
datadir=$(eval echo "\$${type}_data_dir")
datalist=$(eval echo "\$${type}_data_list")
featscp=$(eval echo "\$${feattype}_${type}_featscp")
#swdfeatscp=$(eval echo "\$swd_${type}_featscp")

[ "$srctype" == "plp" ] && srcext=plp_pitch || srcext=$srctype
[ "$srctype2" == "plp" ] && srcext2=plp_pitch || srcext2=$srctype2
[ "$feattype" == "plp" ] && featext=plp_pitch || featext=$feattype
[ "$feattype" == "tandem" ] && featext=${srcext}_${srcext2} && tandemmode=true

[[ "$type" == "train" ]] && cmd=$train_cmd || cmd=$decode_cmd
[[ "$type" == "train" ]] && objdata=${type}${typeext}_${featext} || objdata=${type}${typeext}_${segmode}_${featext}

[[ $feattype =~ "bn" && "$type" == "train" ]] && srcdata=${type}_${srcext}
[[ $feattype =~ "bn" && "$type" != "train" ]] && srcdata=${type}_${segmode}_${srcext}

[[ $feattype == "fmllr" && "$type" == "train" ]] && srcdata=${type}_${srcext}
[[ $feattype == "fmllr" && "$type" != "train" ]] && srcdata=${type}_${segmode}_${srcext}

[ $feattype == "tandem" ] && [[ "$type" == "train" ]] && srcdata=${type}_${srcext} && srcdata2=${type}_${srcext2}
[ $feattype == "tandem" ] && [[ "$type" != "train" ]] && srcdata=${type}_${segmode}_${srcext} && srcdata2=${type}_${segmode}_${srcext2}

echo objdata $objdata

if [ ! -f data/$objdata/.done ]; then
  cp -rfT data/${type} data/${objdata}
  # all non-plp feature requires a swd.feats.scp
  if [ "$feattype" != "mfcc" ] && [ "$feattype" != "plp" ] && [[ ! "$feattype" =~ "bn" ]] && [ "$feattype" != "fmllr" ] && [ $tandemmode ] ; then
    [ -f "$featscp" ] || die "no featscp file $featscp"
    cp $featscp data/$objdata/swd.feats.scp
  fi
  # on the other hand, all non traindata requires segmentation, uem mode use segmentation based on swd feature, pem mode use segfile
  if [[ "$type" != "train" ]]; then
    if [ $segmode == "uem" ] ; then
      echo "$segmode mode: preparing segments using $swdfeatscp"
      mylocal/scp2cmudb.py < $swdfeatscp > data/$objdata/cmudb
      mylocal/cmu_uem2kaldi_dir.sh --filelist $datalist data/$objdata/cmudb $datadir data/$objdata
    elif [ $segmode == "pem" ]; then
      [ ! -f $segfile ] && die "no segmentation file $segfile provided"
      echo "$segmode mode: preparing segments using $segfile"
      mylocal/kaldiseg_posprocess.sh --filelist $datalist $segfile $datadir data/$objdata
    elif [ $segmode == "unseg" ]; then
      rm -rf data/${objdata}/* && cp data/${type}/wav.scp data/${objdata}
      cat data/${objdata}/wav.scp | awk '{print $1, $1, "1";}' > data/${objdata}/reco2file_and_channel
      cat data/${objdata}/wav.scp | awk '{print $1, $1;}' > data/${objdata}/utt2spk
      utils/utt2spk_to_spk2utt.pl data/${objdata}/utt2spk > data/${objdata}/spk2utt
    elif [ $segmode != "seg" ]; then
      die "unknown segmode $segmode"
    fi
    if [ "$feattype" != "mfcc" ] && [ "$feattype" != "plp" ] && [[ ! "$feattype" =~ "bn" ]] && [[ "$feattype" != "fmllr" ]] && [ ! $tandemmode ]; then  
      # update swd.feats.scp based on the new segments
      echo "fix swd.feats.scp using segments from $swdfeatscp"
      mv data/$objdata/swd.feats.scp data/$objdata/swd.feats.scp.old
      mylocal/fixscp.sh data/$objdata/swd.feats.scp.old data/$objdata/segments > data/$objdata/swd.feats.scp
    fi 
  fi

  if [ "$feattype" == "swd" ]; then
    mylocal/make_swordfish_feat.sh --cmd $cmd --nj $nj --swd-feat-range ':14,45:' data/$objdata exp/make_${featext}/$objdata feature/swd
  elif [ "$feattype" == "mfcc" ]; then
    steps/make_mfcc_pitch.sh --cmd $cmd --nj $nj data/$objdata exp/make_${featext}/$objdata feature/$featext
  elif [ "$feattype" == "flow" ]; then
    mylocal/make_swordfish_feat.sh --cmd $cmd --nj $nj --swd-feat-range ':17' data/$objdata exp/make_${featext}/$objdata feature/$featext
  elif [ "$feattype" == "msgpp" ]; then
    mylocal/make_swordfish_feat.sh --cmd $cmd --nj $nj --swd-feat-range ':29' data/$objdata exp/make_${featext}/$objdata feature/$featext
  elif [ "$feattype" == "rastapp" ]; then
    mylocal/make_swordfish_feat.sh --cmd $cmd --nj $nj --swd-feat-range ':14' data/$objdata exp/make_${featext}/$objdata feature/$featext
  elif [ "$feattype" == "krylovnn" ] ; then
    mylocal/make_swordfish_feat.sh --cmd $cmd --nj $nj --swd-feat-range ':29' data/$objdata exp/make_${featext}/$objdata feature/$featext
  elif [ "$feattype" == "plp" ]; then
    steps/make_plp_pitch.sh --cmd $cmd --nj $nj data/$objdata exp/make_${featext}/$objdata feature/$featext
  elif [[ "$feattype" =~ "bn" ]]; then
    # traps feature?
    #steps/make_bn_feats.sh --cmd $cmd --nj $nj data/$objdata data/$srcdata exp/$bnnet exp/make_${featext}/$objdata feature/$featext
    # fmllr feature
    if [[ $type == "train" ]]; then
      transform_dir=exp/${srcdata}_tri5_ali
    else
      transform_dir=exp/train_${srcext}_tri5/decode_${srcdata}
    fi
    mysteps/make_bn_feats.sh --cmd $cmd --nj $nj --feat-type lda --transform-dir $transform_dir data/$objdata data/$srcdata exp/$bnnet exp/make_${featext}/$objdata feature/$featext
  elif [ "$feattype" == "fmllr" ]; then
    if [[ $type == "train" ]]; then
      transform_dir=exp/${srcdata}_tri5_ali
    else
      transform_dir=exp/train_${srcext}_tri5/decode_${srcdata}
    fi
    steps/nnet/make_fmllr_feats.sh --cmd $cmd --nj $nj --transform-dir $transform_dir data/$objdata data/$srcdata exp/train_${srcext}_tri5 exp/make_${featext}/$objdata feature/$featext
  elif [ $tandemmode ]; then
    mysteps/append_feats.sh --cmd $cmd --nj $nj data/$srcdata data/$srcdata2 data/$objdata exp/make_${featext}/$objdata feature/$featext
  else
    die "unknown status feattype=$feattype tandemmode=$tandemmode";
  fi

  utils/fix_data_dir.sh data/$objdata
  steps/compute_cmvn_stats.sh data/$objdata exp/make_${featext}/$objdata feature/$featext
  utils/fix_data_dir.sh data/$objdata
  touch data/$objdata/.done
fi
}
