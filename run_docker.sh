docker run -it --rm -v $(pwd):/mnt/input -w /mnt/input --user "$(id -u):$(id -g)" \
    jwebmeister/kaldi_ag_training \
    $*
