#!/bin/bash
##
# Merges datasets with shuffling.
#
# Kinds:
#   taskcluster/kinds/merge-translated/kind.yml

set -x
set -euo pipefail

test -v BIN

# https://stackoverflow.com/questions/41962359/shuffling-numbers-in-bash-using-seed
# Deterministic shuffling
get_seeded_random()
{
  seed="$1"
  openssl enc -aes-256-ctr -pass pass:"$seed" -nosalt \
    </dev/zero 2>/dev/null
}


echo "###### Merging datasets"

src1=$1
src2=$2
trg1=$3
trg2=$4
res_src=$5
res_trg=$6

COMPRESSION_CMD="${COMPRESSION_CMD:-pigz}"
ARTIFACT_EXT="${ARTIFACT_EXT:-gz}"

tmp_dir="$(dirname "${res_src}")/tmp"
mkdir -p "${tmp_dir}"

cat <(${COMPRESSION_CMD} -dc "${src1}") <(${COMPRESSION_CMD} -dc "${src2}") | ${COMPRESSION_CMD} >"${tmp_dir}/original.src.${ARTIFACT_EXT}"
cat <(${COMPRESSION_CMD} -dc "${trg1}") <(${COMPRESSION_CMD} -dc "${trg2}") | ${COMPRESSION_CMD} >"${tmp_dir}/original.trg.${ARTIFACT_EXT}"

# De-duplicating uses dedupe from: https://github.com/kpu/preprocess
#
# This utility deduplicates based on the 64-bit hash of the entire sentence pair, or
# on one side of the sentence pair. The first encountered line is kept, duplicates later
# on are removed.
#
#  Deduplication settings:
#    -f [ --fields ] arg (=1-) Fields to use for key like cut -f
#    -d [ --delim ] arg (=	)   Field delimiter
#    -p [ --parallel ] arg     Filter parallel data using four files: in_en in_fr
#                              out_en out_fr
#  Deduplicate lines in a file: ./dedupe <in >out
#  Deduplicate parallel data, removing if either side is non-unique ./bin/dedupe -p in_en in_fr out_en out_fr

echo "#### Deduplicating"
paste <(${COMPRESSION_CMD} -dc "${tmp_dir}/original.src.${ARTIFACT_EXT}") <(${COMPRESSION_CMD} -dc "${tmp_dir}/original.trg.${ARTIFACT_EXT}") |
  shuf --random-source=<(get_seeded_random 42) |
  ${BIN}/dedupe |
  ${COMPRESSION_CMD} > "${tmp_dir}/all.${ARTIFACT_EXT}"

${COMPRESSION_CMD} -dc "${tmp_dir}/all.${ARTIFACT_EXT}" | cut -f1 | ${COMPRESSION_CMD} > "${res_src}"
${COMPRESSION_CMD} -dc "${tmp_dir}/all.${ARTIFACT_EXT}" | cut -f2 | ${COMPRESSION_CMD} > "${res_trg}"

src_len=$(${COMPRESSION_CMD} -dc "${res_src}" | wc -l)
trg_len=$(${COMPRESSION_CMD} -dc "${res_trg}" | wc -l)
if [ "${src_len}" != "${trg_len}" ]; then
  echo "Error: length of ${res_src} ${src_len} is different from ${res_trg} ${trg_len}"
  exit 1
fi

rm -rf "${tmp_dir}"

echo "###### Done: Merging datasets"
