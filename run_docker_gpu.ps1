docker run --gpus all -it --rm -v ${pwd}:/mnt/input -w /mnt/input jwebmeister/kaldi_ag_training_gpu $args


# python3 convert_tsv_to_scp.py -l kaldi_model_daanzu_20200905_1ep-mediumlm-base/dict/lexicon.txt merged_audio/merged_audio.txt dataset --text_tab 1
# bash run.finetune.sh kaldi_model_daanzu_20200905_1ep-mediumlm-base dataset --num-utts-subset 1000 --gmm_align true
# python3 export_trained_model.py finetune



# ...librispeech...
# bash /opt/kaldi/egs/librispeech/s5/local/data_prep.sh ./LibriSpeech/train-clean-360/ ./LibriSpeech_prep/train-clean-360/
# librispeech_clean360_flac_to_wav.ps1  
# ...probably should have done this with flac in linux...
# ...manually reformat wav.scp to point to .wav files (instead of .flac)...
# python3 check_text_against_lexicon.py ./LibriSpeech_prep/train-clean-360 ./LibriSpeech_prep/train-clean-360-out
# ...copy lines into existing dataset...