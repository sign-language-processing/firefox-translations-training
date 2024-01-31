import gzip
import os

import pytest
from fixtures import DataDir, get_mocked_downloads

SRC = "ru"
TRG = "en"
ARTIFACT_EXT = "gz"
COMPRESSION_CMD = "pigz"
CURRENT_FOLDER = os.path.dirname(os.path.abspath(__file__))

os.environ["ARTIFACT_EXT"] = ARTIFACT_EXT
os.environ["COMPRESSION_CMD"] = COMPRESSION_CMD
os.environ["SRC"] = SRC
os.environ["TRG"] = TRG


from pipeline.data.dataset_importer import run_import

# the augmentation is probabilistic, here is a range for 0.1 probability
AUG_MAX_RATE = 0.3
AUG_MIN_RATE = 0.01


def read_lines(path):
    with gzip.open(path, "rt") as f:
        return f.readlines()


def is_title_case(text):
    return all((word[0].isupper() or not word.isalpha()) for word in text.split())


def is_upper_case(text):
    return all((word.isupper() or not word.isalpha()) for word in text.split())


def get_aug_rate(file, check_func):
    lines = read_lines(file)
    aug_num = len([l for l in lines if check_func(l)])
    rate = aug_num / len(lines)
    print(f"augmentation rate for {file}: {rate}")
    return rate


@pytest.fixture(scope="function")
def data_dir():
    return DataDir("test_data_importer")


@pytest.mark.parametrize(
    "importer,dataset",
    [
        ("mtdata", "Neulab-tedtalks_test-1-eng-rus"),
        ("opus", "ELRC-3075-wikipedia_health_v1"),
        ("flores", "dev"),
        ("sacrebleu", "wmt19"),
    ],
)
def test_basic_corpus_import(importer, dataset, data_dir):
    data_dir.run_task(
        f"dataset-{importer}-{dataset}-en-ru",
        env={
            "COMPRESSION_CMD": COMPRESSION_CMD,
            "ARTIFACT_EXT": ARTIFACT_EXT,
            "WGET": os.path.join(CURRENT_FOLDER, "fixtures/wget"),
            "MOCKED_DOWNLOADS": get_mocked_downloads(),
        },
    )

    prefix = data_dir.join(f"artifacts/{dataset}")
    output_src = f"{prefix}.ru.gz"
    output_trg = f"{prefix}.en.gz"

    assert os.path.exists(output_src)
    assert os.path.exists(output_trg)
    assert len(read_lines(output_src)) > 0
    assert len(read_lines(output_trg)) > 0


augmentation_params = [
    ("sacrebleu_aug-upper_wmt19", is_upper_case, AUG_MIN_RATE, AUG_MAX_RATE),
    ("sacrebleu_aug-upper-strict_wmt19", is_upper_case, 1.0, 1.0),
    ("sacrebleu_aug-title_wmt19", is_title_case, AUG_MIN_RATE, AUG_MAX_RATE),
    ("sacrebleu_aug-title-strict_wmt19", is_title_case, 1.0, 1.0),
]


@pytest.mark.parametrize("params", augmentation_params, ids=[d[0] for d in augmentation_params])
def test_specific_augmentation(params, data_dir):
    dataset, check_func, min_rate, max_rate = params
    prefix = data_dir.join(dataset)
    output_src = f"{prefix}.{SRC}.{ARTIFACT_EXT}"
    output_trg = f"{prefix}.{TRG}.{ARTIFACT_EXT}"

    run_import("corpus", dataset, prefix)

    assert os.path.exists(output_src)
    assert os.path.exists(output_trg)

    for file in (output_src, output_trg):
        rate = get_aug_rate(file, check_func)
        assert rate >= min_rate
        assert rate <= max_rate


def test_augmentation_mix(data_dir):
    dataset = "sacrebleu_aug-mix_wmt19"
    prefix = data_dir.join(dataset)
    output_src = f"{prefix}.{SRC}.{ARTIFACT_EXT}"
    output_trg = f"{prefix}.{TRG}.{ARTIFACT_EXT}"

    run_import("corpus", dataset, prefix)

    assert os.path.exists(output_src)
    assert os.path.exists(output_trg)

    for file in (output_src, output_trg):
        for check_func in (is_upper_case, is_title_case):
            rate = get_aug_rate(file, check_func)
            assert rate <= AUG_MAX_RATE
            assert rate >= AUG_MIN_RATE
