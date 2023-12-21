#!/bin/bash
set -e
set -x

pushd `dirname $0` &>/dev/null
MY_DIR=$(pwd)
popd &>/dev/null

patch=${1:-none}

export MARIAN_DIR=$MOZ_FETCHES_DIR/marian-source
export CUDA_DIR=$MOZ_FETCHES_DIR/cuda-toolkit

if [ "$patch" != "none" ]; then
  patch -d ${MARIAN_DIR} -p1 < ${MY_DIR}/${patch}
fi

# TODO: consider not calling out to this since it's such a simple script...
bash $VCS_PATH/pipeline/setup/compile-marian.sh "${MARIAN_DIR}/build" "$(nproc)"

cd $MARIAN_DIR/build
tar -cf $UPLOAD_DIR/marian.tar \
  "marian" \
  "marian-decoder" \
  "marian-scorer" \
  "marian-conv" \
  "marian-vocab" \
  "spm_train" \
  "spm_encode" \
  "spm_export_vocab"

if [ -f "${MARIAN_DIR}/scripts/alphas/extract_stats.py" ]; then
  cd "${MARIAN_DIR}/scripts/alphas"
  tar -rf $UPLOAD_DIR/marian.tar extract_stats.py
fi

zstd --rm $UPLOAD_DIR/marian.tar
