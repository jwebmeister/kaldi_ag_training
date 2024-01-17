#!/usr/bin/env python3

import argparse, os, re

parser = argparse.ArgumentParser(description='Check text file against lexicon')
parser.add_argument('directory', default='./LibriSpeech_prep/train-clean-360', help='Dataset containing scp files.')
parser.add_argument('output_dir', default='./LibriSpeech_prep/train-clean-360-out', help='Output directory')
parser.add_argument('-l', '--lexicon_file', default='kaldi_model_daanzu_20200905_1ep-mediumlm-base/dict/lexicon.txt', help='Filename of the lexicon file, for filtering out out-of-vocabulary utterances.')
args = parser.parse_args()

if not os.path.exists(args.directory):
    raise Exception('Directory does not exist: %s' % args.directory)
lexicon = set()
if args.lexicon_file:
    with open(args.lexicon_file, 'r', encoding='utf8') as f:
        for line in f:
            word = line.strip().split(None, 1)[0]
            lexicon.add(word)
else:
    print("WARNING: No lexicon file specified.")


text_filepath = os.path.join(args.directory, 'text')
utt2spk_filepath = os.path.join(args.directory, 'utt2spk')
wavscp_filepath = os.path.join(args.directory, 'wav.scp')
spk2gender_filepath = os.path.join(args.directory, 'spk2gender')

utt2spk_dict, wav_dict, text_dict, spk2gender_dict = {}, {}, {}, {}

num_entries, num_dropped_utt = 0, 0
dropped_utt_id = []
dropped_utt_text = []
with open(text_filepath, 'r', encoding='utf8') as f:
    for line in f:
        num_entries += 1
        fields = line.rstrip('\n').split(None, 1)
        text = fields[1]
        utt_id = fields[0]
        if lexicon and any([word not in lexicon for word in text.split()]):
            num_dropped_utt += 1
            dropped_utt_id.append(utt_id)
            dropped_utt_text.append(text)
            continue
        text_dict[utt_id] = text

def read_to_dict(dict_name, filepath, exclude_list=[]):
    dropped_values = []
    with open(filepath, 'r', encoding='utf8') as f:
        for line in f:
            fields = line.rstrip('\n').split(None, 1)
            value = fields[1]
            key = fields[0]
            if key in exclude_list:
                dropped_values.append(value)
                continue
            dict_name[key] = value
    return dropped_values

dropped_spk_id = read_to_dict(utt2spk_dict, utt2spk_filepath, dropped_utt_id)
read_to_dict(spk2gender_dict, spk2gender_filepath, dropped_spk_id)
read_to_dict(wav_dict, wavscp_filepath, dropped_utt_id)

os.mkdir(args.output_dir)

with open(os.path.join(args.output_dir, 'utt2spk'), 'w') as f:
    for (key, val) in utt2spk_dict.items():
        f.write('%s %s\n' % (key, val))
with open(os.path.join(args.output_dir, 'wav.scp'), 'w') as f:
    for (key, val) in wav_dict.items():
        f.write('%s %s\n' % (key, val))
with open(os.path.join(args.output_dir, 'text'), 'w') as f:
    for (key, val) in text_dict.items():
        f.write('%s %s\n' % (key, val))
with open(os.path.join(args.output_dir, 'spk2gender'), 'w') as f:
    for (key, val) in utt2spk_dict.items():
        f.write('%s %s\n' % (key, 'm'))


print(f"{dropped_utt_text}")
print(f"{num_dropped_utt} ({num_dropped_utt / num_entries * 100:.1f}%) utterances dropped because they contained out-of-lexicon words.")


