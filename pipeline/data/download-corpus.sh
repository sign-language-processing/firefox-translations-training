#!/bin/bash
##
# Downloads parallel dataset
#

set -x
set -euo pipefail

[[ -z "${SRC}" ]] && echo "SRC is empty"
[[ -z "${TRG}" ]] && echo "TRG is empty"


dataset=$1
output_prefix=$2

echo "###### Downloading dataset ${dataset}"

cd "$(dirname "${0}")"

dir=$(dirname "${output_prefix}")
mkdir -p "${dir}"

name=${dataset#*_}
type=${dataset%%_*}
bash "importers/corpus/${type}.sh" "${SRC}" "${TRG}" "${output_prefix}" "${name}"

echo "###### Done: Downloading dataset ${dataset}"
