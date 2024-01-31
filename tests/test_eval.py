"""
Tests evaluations
"""

import json
import os

import pytest
from fixtures import DataDir, en_sample, ru_sample

en_fake_translated = "\n".join([line.upper() for line in ru_sample.split("\n")])
ru_fake_translated = "\n".join([line.upper() for line in en_sample.split("\n")])

current_folder = os.path.dirname(os.path.abspath(__file__))
fixtures_path = os.path.join(current_folder, "fixtures")
root_path = os.path.abspath(os.path.join(current_folder, ".."))


def get_base_marian_args(data_dir: DataDir, model_name: str):
    return [
        "--config", data_dir.join("final.model.npz.best-chrf.npz.decoder.yml"),
        "--quiet",
        "--quiet-translation",
        "--log", data_dir.join("artifacts/wmt09.log"),
        '--workspace', '12000',
        '--devices', '4',
        "--models", data_dir.join(model_name),
    ]  # fmt: skip


def get_quantized_marian_args(data_dir: DataDir, model_name: str):
    return [
        "--config", os.path.join(root_path, "pipeline/quantize/decoder.yml"),
        "--quiet",
        "--quiet-translation",
        "--log", data_dir.join("artifacts/wmt09.log"),
        "--models", data_dir.join(model_name),
        '--vocabs', data_dir.join("vocab.spm"), data_dir.join("vocab.spm"),
        '--shortlist', data_dir.join("lex.s2t.pruned"), 'false',
        '--int8shiftAlphaAll',
    ]  # fmt: skip


test_data = [
    # task_name                                                   model_type   model_name
    ("evaluate-backward-sacrebleu-wmt09-en-ru",                   "base",      "final.model.npz.best-chrf.npz"),
    ("evaluate-finetuned-student-sacrebleu-wmt09-en-ru",          "base",      "final.model.npz.best-chrf.npz"),
    ("evaluate-student-sacrebleu-wmt09-en-ru",                    "base",      "final.model.npz.best-chrf.npz"),
    ("evaluate-teacher-ensemble-sacrebleu-sacrebleu_wmt09-en-ru", "base",      "model*/*.npz"),
    ("evaluate-quantized-sacrebleu-wmt09-en-ru",                  "quantized", "model.intgemm.alphas.bin")
]  # fmt:skip


@pytest.mark.parametrize("params", test_data, ids=[d[0] for d in test_data])
def test_evaluate(params) -> None:
    (task_name, model_type, model_name) = params

    data_dir = DataDir("test_eval")
    data_dir.create_zst("wmt09.en.zst", en_sample)
    data_dir.create_zst("wmt09.ru.zst", ru_sample)

    bleu = 0.4
    chrf = 0.6

    if model_type == "base":
        expected_marian_args = get_base_marian_args(data_dir, model_name)
        env = {
            # This is where the marian_decoder_args will get stored.
            "TEST_ARTIFACTS": data_dir.path,
            # Replace marian with the one in the fixtures path.
            "MARIAN": fixtures_path,
            # This is included via the poetry install
            "COMPRESSION_CMD": "zstd",
            "GPUS": "4",
        }
    elif model_type == "quantized":
        expected_marian_args = get_quantized_marian_args(data_dir, model_name)
        env = {
            # This is where the marian_decoder_args will get stored.
            "TEST_ARTIFACTS": data_dir.path,
            # Replace marian with the one in the fixtures path.
            "BMT_MARIAN": fixtures_path,
            # This is included via the poetry install
            "COMPRESSION_CMD": "zstd",
        }

    # Run the evaluation.
    data_dir.run_task(
        task_name,
        env=env,
    )

    # Test that the data files are properly written out.
    if "backward" in task_name:
        # Backwards evaluation.
        assert data_dir.load("artifacts/wmt09.ru") == ru_sample
        assert data_dir.load("artifacts/wmt09.en.ref") == en_sample
        assert data_dir.load("artifacts/wmt09.en") == en_fake_translated
    else:
        # Forwards evaluation.
        assert data_dir.load("artifacts/wmt09.en") == en_sample
        assert data_dir.load("artifacts/wmt09.ru.ref") == ru_sample
        assert data_dir.load("artifacts/wmt09.ru") == ru_fake_translated

    # Test that text metrics get properly generated.
    assert f"{bleu}\n{chrf}\n" in data_dir.load("artifacts/wmt09.metrics")

    # Test that marian is given the proper arguments.
    marian_decoder_args = json.loads(data_dir.load("marian-decoder.args.txt"))
    assert marian_decoder_args == expected_marian_args, "The marian arguments matched."
