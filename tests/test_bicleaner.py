import os
import tarfile
from subprocess import CompletedProcess

import pytest
import sh
import yaml
from fixtures import DataDir
from pytest import fixture

from pipeline.bicleaner import download_pack
from pipeline.bicleaner.download_pack import main as download_model


@pytest.fixture(scope="function")
def data_dir():
    return DataDir("test_bicleaner")


@fixture(scope="session")
def init():
    def _fake_download(src, trg, dir):
        pair = f"{src}-{trg}"
        if pair not in ["en-pt", "en-xx"]:
            return CompletedProcess(
                [], returncode=1, stderr=b"Error: language pack does not exist."
            )

        pack_dir = os.path.join(dir, pair)
        os.makedirs(pack_dir, exist_ok=True)
        with open(os.path.join(pack_dir, "metadata.yaml"), "w") as f:
            f.writelines([f"source_lang: {src}", "\n", f"target_lang: {trg}"])

        return CompletedProcess([], returncode=0)

    download_pack._run_download = _fake_download


def decompress(path):
    sh.zstd("-d", path)
    with tarfile.open(path[:-4]) as tar:
        tar.extractall(os.path.dirname(path))


@pytest.mark.parametrize(
    "params",
    [
        ("en", "pt", "en", "pt"),
        ("pt", "en", "en", "pt"),
        ("ru", "en", "en", "xx"),
        ("en", "ru", "en", "xx"),
    ],
)
def test_model_download(params, init, data_dir):
    src, trg, model_src, model_trg = params
    target_path = data_dir.join(f"bicleaner-ai-{src}-{trg}.tar.zst")
    decompressed_path = data_dir.join(f"bicleaner-ai-{src}-{trg}")
    meta_path = os.path.join(decompressed_path, "metadata.yaml")

    download_model([f"--src={src}", f"--trg={trg}", "--compression_cmd=zstd", target_path])

    assert os.path.isfile(target_path)
    decompress(target_path)
    assert os.path.isdir(decompressed_path)
    with open(meta_path) as f:
        metadata = yaml.safe_load(f)
    assert metadata["source_lang"] == model_src
    assert metadata["target_lang"] == model_trg
