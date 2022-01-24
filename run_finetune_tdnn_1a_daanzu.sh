# !/bin/bash

# Adapted from egs/aishell2/s5/local/nnet3/tuning/finetune_tdnn_1a.sh commit 42a673a5e7f201736dfbf2116e8eaa94745e5a5f
# Also see:
#   egs/rm/s5/local/chain/tuning/run_tdnn_wsj_rm_1b.sh
#   egs/rm/s5/local/chain/tuning/run_tdnn_wsj_rm_1c.sh

# This script uses weight transfer as a transfer learning method to transfer already trained neural net model to a finetune dataset.

# Usage: run_finetune_tdnn_1a_daanzu.sh --src-dir export/tdnn_f.1ep --num-epochs 5 --stage 1 --train-stage -10

# Required Inputs:
#   data/finetune (text wav.scp utt2spk)
#   src_dir
#   tree_dir (tree final.mdl ali.*.gz phones.txt)
#   lang_dir (oov.int L.fst words.txt phones.txt phones/disambig.int)
#   conf_dir (mfcc.conf mfcc_hires.conf)
#   extractor_dir (final.ie final.dubm final.mat global_cmvn.stats splice_opts online_cmvn.conf online_cmvn_iextractor?)
# Writes To:
#   data/finetune, data/finetune_hires, data/finetune_sp, data/finetune_sp_hires,
#   exp/make_mfcc_chain/finetune, exp/make_mfcc_chain/finetune_sp_hires, exp/make_mfcc_chain/finetune_hires,
#   exp/nnet3_chain/ivectors_finetune_hires, exp/finetune_lats, exp/nnet3_chain/finetune

set -e

data_set=finetune
data_dir=data/${data_set}
conf_dir=conf
lang_dir=data/lang  # FIXME: lang_chain?
extractor_dir=exp/nnet3_chain/extractor
# ali_dir=exp/${data_set}_ali
# lat_dir=exp/${data_set}_lats
src_dir=exp/nnet3_chain/tdnn_f
tree_dir=exp/nnet3_chain/tree_sp
# dir=${src_dir}_${data_set}
dir=exp/nnet3_chain/${data_set}

oov_word="<unk>"

train_affix=_sp_vp_hires
respect_speaker_info=false  # You may want false for one-to-one utt2spk
finetune_ivector_extractor=false
ivector_dim=100
finetune_phonelm=false
gmm_align=false
gmm_align_stage=0

num_gpus=1
num_epochs=5
initial_lrate=.00025  # 0.0005
final_lrate=.000025  # 0.00002
minibatch_size=128,64
primary_lr_factor=0.25  # learning-rate factor for all except last layer in transferred source model (last layer is 1.0)

xent_regularize=0.1
train_stage=-4  # Normally default -10, but here -4 to skip phone_LM and den.fst generation training stages.
get_egs_stage=-10
common_egs_dir=  # you can set this to use previously dumped egs.
num_utts_subset=300
egs_constrained=false  # false is newer, gives more freedom, is more e2e-like, may help: https://github.com/kaldi-asr/kaldi/pull/2383
egs_jobs_opts="--max-jobs-run 8 --max-shuffle-jobs-run 25"  # Standard default: --max-jobs-run 15 --max-shuffle-jobs-run 50
dropout_schedule='0,0@0.20,0.5@0.50,0'
frames_per_eg=140,100,160,50  # Standard default is 140,100,160 but try 140,100,160,50 for training with utterances of short commands
chain_left_tolerance=2
chain_right_tolerance=2

stage=1
nj=8

echo "$0 $@"  # Print the command line for logging
. ./path.sh
. ./cmd.sh
. ./utils/parse_options.sh

egs_opts="--num-utts-subset $num_utts_subset --constrained $egs_constrained $egs_jobs_opts"

if [ "$num_gpus" -eq 0 ]; then
  gpu_opt="no"
  num_gpus=1
else
  gpu_opt="wait"
fi

function write_params() {
  for v in $*; do
    echo "${v}=${!v}" >> params.txt
  done
}

function log_stage() {
  echo
  echo "# Stage $1"
  [ -n "$2" ] && echo "# $2"
  echo "# $(date)"
  echo
}

function compute_features() {
  # compute_features <conf_file> [input_data_dir_affix]
  rm -f ${data_dir}${2}/{cmvn.scp,feats.scp}
  steps/make_mfcc.sh \
    --cmd "$train_cmd" --nj $nj --mfcc-config ${1} \
    ${data_dir}${2} exp/make_mfcc_chain/${data_set}${2}.log exp/make_mfcc_chain
  steps/compute_cmvn_stats.sh ${data_dir}${2} exp/make_mfcc_chain/${data_set}${2}.log exp/make_mfcc_chain || exit 1;
  utils/fix_data_dir.sh ${data_dir}${2} || exit 1;
}

if [ $stage -le 1 ]; then
  log_stage 1 "Compute features (MFCC & CMVN stats) of the new dataset, including perturbing the data"
  # (Approximately 0.66min single-core compute time per core per 1hr audio data)
  utils/fix_data_dir.sh ${data_dir} || exit 1;

  # Standard lores training data
  compute_features $conf_dir/mfcc.conf

  rm -rf ${data_dir}_sp
  utils/data/perturb_data_dir_speed_3way.sh ${data_dir} ${data_dir}_sp || exit 1;
  compute_features $conf_dir/mfcc.conf _sp

  rm -rf ${data_dir}_sp_vp_hires
  utils/copy_data_dir.sh ${data_dir}_sp ${data_dir}_sp_vp_hires
  utils/data/perturb_data_dir_volume.sh ${data_dir}_sp_vp_hires || exit 1;
  compute_features $conf_dir/mfcc_hires.conf _sp_vp_hires

  rm -rf ${data_dir}_sp_novp_hires
  utils/copy_data_dir.sh ${data_dir}_sp ${data_dir}_sp_novp_hires
  compute_features $conf_dir/mfcc_hires.conf _sp_novp_hires

  rm -rf ${data_dir}_vp_hires
  utils/copy_data_dir.sh ${data_dir} ${data_dir}_vp_hires
  utils/data/perturb_data_dir_volume.sh ${data_dir}_vp_hires || exit 1;
  compute_features $conf_dir/mfcc_hires.conf _vp_hires

  rm -rf ${data_dir}_hires
  utils/copy_data_dir.sh ${data_dir} ${data_dir}_hires
  compute_features $conf_dir/mfcc_hires.conf _hires
fi

# train_affix=_hires
train_data_dir=${data_dir}${train_affix}
train_ivector_dir=exp/nnet3_chain/ivectors_${data_set}${train_affix}
lat_dir=exp/nnet3_chain/lats_${data_set}${train_affix}
# lores_train_data_dir=${data_dir}_sp
# extractor_dir=exp/nnet3_chain/extractor_${data_set}${train_affix}

if $finetune_ivector_extractor; then
  train_set=${data_set}
  temp_data_root=exp/nnet3_chain/diag_ubm

  if [ $stage -le 2 ]; then
    log_stage 2 "Finetune ivectors: Train diagonal UBM"

    echo "$0: computing a subset of data to train the diagonal UBM."
    # We'll use about a quarter of the data.
    mkdir -p $temp_data_root

    num_utts_total=$(wc -l <data/${train_set}${train_affix}/utt2spk)
    num_utts=$[$num_utts_total/4]
    utils/data/subset_data_dir.sh data/${train_set}${train_affix} \
       $num_utts ${temp_data_root}/${train_set}${train_affix}_subset

    echo "$0: computing a PCA transform from the hires data."
    steps/online/nnet2/get_pca_transform.sh --cmd "$train_cmd" \
        --splice-opts "--left-context=3 --right-context=3" \
        --max-utts 10000 --subsample 2 \
         ${temp_data_root}/${train_set}${train_affix}_subset \
         exp/nnet3_chain/pca_transform

    echo "$0: training the diagonal UBM."
    # Use 512 Gaussians in the UBM.
    steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj $nj \
      --num-frames 700000 \
      --num-threads 8 \
      ${temp_data_root}/${train_set}${train_affix}_subset 512 \
      exp/nnet3_chain/pca_transform $temp_data_root
  fi

  if [ $stage -le 3 ]; then
    log_stage 3 "Finetune ivectors: Train ivector extractor"
    # Train the iVector extractor.  Use all of the speed-perturbed data since iVector extractors
    # can be sensitive to the amount of data.  The script defaults to an iVector dimension of
    # 100.
    echo "$0: training the iVector extractor"
    steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj $nj \
       --ivector-dim $ivector_dim \
       data/${train_set}${train_affix} $temp_data_root \
       $extractor_dir || exit 1;
  fi

  if [ $stage -le 4 ]; then
    log_stage 4 "Finetune ivectors: Extract ivectors of the new dataset with newly-trained extractor"
    # We extract iVectors on the speed-perturbed training data after combining
    # short segments, which will be what we train the system on.  With
    # --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
    # each of these pairs as one speaker; this gives more diversity in iVectors..
    # Note that these are extracted 'online'.

    # note, we don't encode the 'max2' in the name of the ivectordir even though
    # that's the data we extract the ivectors from, as it's still going to be
    # valid for the non-'max2' data, the utterance list is the same.

    # having a larger number of speakers is helpful for generalization, and to
    # handle per-utterance decoding well (iVector starts at zero).
    ivectordir=${train_ivector_dir}
    modified_data_dir=${ivectordir}/data_${train_set}${train_affix}_max2
    utils/data/modify_speaker_info.sh --utts-per-spk-max 2 --respect-speaker-info $respect_speaker_info \
      data/${train_set}${train_affix} ${modified_data_dir}

    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nj \
      ${modified_data_dir} $extractor_dir $ivectordir
  fi

else
  if [ $stage -le 4 ] && ! $gmm_align; then
    log_stage 4 "Extract ivectors of the new dataset using source model's extractor"
    # (Approximately 0.066min single-core compute time per core per 1hr audio data)
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nj \
      $train_data_dir $extractor_dir $train_ivector_dir
  fi
fi

if [ $stage -le 5 ] && ! $gmm_align; then
  log_stage 5 "Align the new dataset with source NN"
  # (Approximately 0.085hr single-core compute time per core per 1hr audio data)

  steps/nnet3/align_lats.sh --cmd "$train_cmd" --nj $nj \
    --acoustic-scale 1.0 \
    --scale-opts '--transition-scale=1.0 --self-loop-scale=1.0' \
    --online-ivector-dir $train_ivector_dir \
    --generate_ali_from_lats true \
    --frames-per-chunk 150 \
    --beam 100 \
    $train_data_dir $lang_dir ${src_dir} ${lat_dir}
  rm $lat_dir/fsts.*.gz # save space
fi

# NOTE: We must use the same tree as was used to train the nnet model (need the same num_pdfs), so we can't finetune it.

if $finetune_phonelm; then
  if [ $stage -le 6 ]; then
    log_stage 6 "Copy data to allow building new finetuned phone_lm"
    # Requires: $tree_dir/{tree,final.mdl}
    cp $lat_dir/ali.*.gz $lat_dir/num_jobs $tree_dir
    # Note: actually do it by setting $train_stage <= -6
  fi
fi

if $gmm_align; then
  lat_dir=exp/chain/tri3_train_sp_lats
fi

if [ $stage -le 7 ] && $gmm_align; then
  if [ $gmm_align_stage -le 0 ]; then
    utils/prepare_lang.sh data/dict "$oov_word" data/lang_gmm_local data/lang_gmm
  fi

  if [ $gmm_align_stage -le 1 ]; then
    # utils/subset_data_dir.sh $data_dir 15000 data/train_15k
    steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
      $data_dir data/lang_gmm exp/mono_finetune
    steps/align_si.sh --nj $nj --cmd "$train_cmd" \
      $data_dir data/lang_gmm exp/mono_finetune exp/mono_finetune_ali
  fi

  if [ $gmm_align_stage -le 2 ]; then
    steps/train_deltas.sh --cmd "$train_cmd" \
      5000 80000 $data_dir data/lang_gmm exp/mono_finetune_ali exp/tri1_finetune
    steps/align_si.sh --nj $nj --cmd "$train_cmd" \
      $data_dir data/lang_gmm exp/tri1_finetune exp/tri1_finetune_ali
  fi

  if [ $gmm_align_stage -le 3 ]; then
    steps/train_lda_mllt.sh --cmd "$train_cmd" \
      --splice-opts "--left-context=3 --right-context=3" \
      5000 80000 $data_dir data/lang_gmm exp/tri1_finetune_ali exp/tri2_finetune
    steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
      $data_dir data/lang_gmm exp/tri2_finetune exp/tri2_finetune_ali
  fi

  if [ $gmm_align_stage -le 4 ]; then
    steps/train_sat.sh --cmd "$train_cmd" \
      5000 80000 $data_dir data/lang_gmm exp/tri2_finetune_ali exp/tri3_finetune
    steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
      $data_dir data/lang_gmm exp/tri3_finetune exp/tri3_finetune_ali
  fi

  if [ $gmm_align_stage -le 5 ]; then
    # We extract iVectors on the speed-perturbed training data after combining
    # short segments, which will be what we train the system on.  With
    # --utts-per-spk-max 2, the script pairs the utterances into twos, and treats
    # each of these pairs as one speaker; this gives more diversity in iVectors..
    # Note that these are extracted 'online'.

    # note, we don't encode the 'max2' in the name of the ivectordir even though
    # that's the data we extract the ivectors from, as it's still going to be
    # valid for the non-'max2' data, the utterance list is the same.

    # having a larger number of speakers is helpful for generalization, and to
    # handle per-utterance decoding well (iVector starts at zero).
    ivectordir=${train_ivector_dir}
    modified_data_dir=${ivectordir}/data_${data_set}${train_affix}_max2
    utils/data/modify_speaker_info.sh --utts-per-spk-max 2 --respect-speaker-info $respect_speaker_info \
      data/${data_set}${train_affix} ${modified_data_dir}

    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj $nj \
      ${modified_data_dir} $extractor_dir $ivectordir
  fi

  if [ $gmm_align_stage -le 6 ]; then
    steps/align_fmllr_lats.sh --nj $nj --cmd "$train_cmd" \
      --generate-ali-from-lats true \
      ${data_dir}_sp data/lang_gmm exp/tri3_finetune $lat_dir
    rm $lat_dir/fsts.*.gz
  fi

  if [ $gmm_align_stage -le 7 ]; then
    # Adapted from steps/nnet3/chain/make_weighted_den_fst.sh

    mkdir -p $dir/log
    for f in $lat_dir/ali.1.gz $lat_dir/final.mdl $lat_dir/tree; do
      [ ! -f $f ] && echo "$0: Expected file $f to exist" && exit 1;
    done
    utils/lang/check_phones_compatible.sh $src_dir/phones.txt $lat_dir/phones.txt || exit 1;

    cp $src_dir/tree $dir/ || exit 1

    # num_jobs=$(cat $lat_dir/num_jobs)
    # for j in $(seq $num_jobs); do gunzip -c $lat_dir/ali.$j.gz; done | \
    $train_cmd $dir/log/make_phone_lm_fst.log \
      gunzip -c $lat_dir/ali.*.gz \| \
      ali-to-phones $lat_dir/final.mdl ark:- ark:- \| \
      chain-est-phone-lm '--num-extra-lm-states=200' ark:- $dir/phone_lm.fst || exit 1;

    copy-transition-model $src_dir/final.mdl $dir/0.trans_mdl || exit 1;

    $train_cmd $dir/log/make_den_fst.log \
      chain-make-den-fst $dir/tree $dir/0.trans_mdl \
      $dir/phone_lm.fst \
      $dir/den.fst $dir/normalization.fst || exit 1
  fi
fi

if [ $stage -le 8 ]; then
  log_stage 8 "Copy source NN"
  if [ $primary_lr_factor = "1.0" ]; then
    $train_cmd $dir/log/generate_input_model.log \
      nnet3-am-copy --raw=true $src_dir/final.mdl $dir/input.raw || exit 1;
  else
    # Set the learning-rate-factor for all transferred layers but the last output layer to primary_lr_factor.
    $train_cmd $dir/log/generate_input_mdl.log \
      nnet3-am-copy --raw=true \
        --edits="set-learning-rate-factor name=* learning-rate-factor=$primary_lr_factor; set-learning-rate-factor name=output* learning-rate-factor=1.0" \
        $src_dir/final.mdl $dir/input.raw || exit 1;
  fi
fi

# echo "$0: sleeping..."
# sleep 600

if [ $stage -le 9 ]; then
  log_stage 9 "Train new fine-tuned NN"

  # Exclude phone_LM and den.fst generation training stages.
  # if [ $train_stage -lt -4 ]; then train_stage=-4 ; fi

  if [ $train_stage -le 0 ]; then rm $dir/log/compute_prob*.log ; fi

  chain_opts=()
  if ! $gmm_align; then
    # we use chain model from source to generate lats for target and the
    # tolerance used in chain egs generation using this lats should be 1 or 2 which is
    # (source_egs_tolerance/frame_subsampling_factor)
    # source_egs_tolerance = 5
    chain_opts=(--chain.alignment-subsampling-factor=1 --chain.left-tolerance=$chain_left_tolerance --chain.right-tolerance=$chain_right_tolerance)
  fi

  write_params chunk_width dropout_schedule xent_regularize initial_lrate final_lrate num_epochs num_gpu_jobs stage train_stage num_utts_subset

  steps/nnet3/chain/train.py --stage $train_stage ${chain_opts[@]} \
    --cmd "$decode_cmd" \
    --trainer.input-model $dir/input.raw \
    --feat.online-ivector-dir $train_ivector_dir \
    --feat.cmvn-opts "--norm-means=false --norm-vars=false" \
    --chain.xent-regularize $xent_regularize \
    --chain.leaky-hmm-coefficient 0.1 \
    --chain.l2-regularize 0.0 \
    --chain.apply-deriv-weights false \
    --chain.lm-opts="--num-extra-lm-states=2000" \
    --trainer.dropout-schedule $dropout_schedule \
    --trainer.add-option="--optimization.memory-compression-level=2" \
    --egs.dir "$common_egs_dir" \
    --egs.stage $get_egs_stage \
    --egs.opts "--frames-overlap-per-eg 0 $egs_opts" \
    --egs.chunk-width $frames_per_eg \
    --egs.nj $nj \
    --trainer.num-chunk-per-minibatch $minibatch_size \
    --trainer.frames-per-iter 3000000 \
    --trainer.num-epochs $num_epochs \
    --trainer.optimization.num-jobs-initial 1 \
    --trainer.optimization.num-jobs-final $num_gpus \
    --trainer.optimization.initial-effective-lrate $initial_lrate \
    --trainer.optimization.final-effective-lrate $final_lrate \
    --trainer.max-param-change 2.0 \
    --use-gpu $gpu_opt \
    --cleanup.remove-egs false \
    --feat-dir $train_data_dir \
    --tree-dir $tree_dir \
    --lat-dir $lat_dir \
    --dir $dir  || exit 1;
fi
