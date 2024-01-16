# docker build --build-arg=base=nvidia/cuda:12.3.1-devel-ubuntu22.04 --build-arg=cuda=yes -t jwebmeister/kaldi_ag_training_gpu .


ARG base
ARG cuda=

FROM $base
LABEL maintainer="jwebmeister@gmail.com"
ARG cuda

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        g++ \
        make \
        automake \
        autoconf \
        bzip2 \
        unzip \
        wget \
        sox \
        libtool \
        git \
        subversion \
        python2.7 \
        python3 \
        python3-pip \
        python3-venv \
        zlib1g-dev \
        ca-certificates \
        gfortran \
        patch \
        ffmpeg \
	    vim && \
    rm -rf /var/lib/apt/lists/*

RUN ln -s /usr/bin/python2.7 /usr/bin/python

RUN git clone --single-branch --branch CUDA12 --depth 1 https://github.com/jwebmeister/kaldi-fork-active-grammar /opt/kaldi && \
    cd /opt/kaldi/tools && \
    ./extras/install_mkl.sh && \
    make -j $(nproc) && \
    cd /opt/kaldi/src && \
    ./configure --shared ${cuda:+--use-cuda} && \
    make depend -j $(nproc) && \
    make -j $(nproc) && \
    find /opt/kaldi -type f \( -name "*.o" -o -name "*.la" -o -name "*.a" \) -exec rm {} \; && \
    find /opt/intel -type f -name "*.a" -exec rm {} \; && \
    find /opt/intel -type f -regex '.*\(_mic\|_thread\|_ilp64\)\.so' -exec rm {} \; && \
    rm -rf /opt/kaldi/.git

# _mc included for pre-AVX CPUs

WORKDIR /opt/kaldi/
