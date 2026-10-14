#!/usr/bin/env python3
"""Build an unpublished experimental package with a pinned KOReader SDK."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile
from package_source import plugin_files

ROOT = Path(__file__).resolve().parents[1]
SDK_URL = "https://github.com/koreader/koxtoolchain/releases/download/2026.08/kindlehf.tar.zst"
SDK_SHA256 = "8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0"
PREFIX = "arm-kindlehf-linux-gnueabihf"
FLAGS = ["-O2", "-Wall", "-Wextra", "-std=c99", "-march=armv7-a", "-mfpu=neon", "-mfloat-abi=hard"]


def sha256(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def output(command, **kwargs):
    return subprocess.check_output([str(value) for value in command], text=True, **kwargs).strip()


def build(archive, destination, workspace):
    if sha256(archive) != SDK_SHA256:
        raise SystemExit("SDK checksum mismatch")
    subprocess.run(["tar", "--zstd", "-xf", str(archive), "-C", str(workspace)], check=True)
    compiler = workspace / "x-tools" / PREFIX / "bin" / (PREFIX + "-gcc")
    readelf = compiler.with_name(PREFIX + "-readelf")
    native = workspace / "moire-kindlehf.so"
    sources = [ROOT / "native/preprocess" / name for name in
               ("filter.c", "vendor/kissfft/kiss_fft.c", "vendor/kissfft/kiss_fftnd.c")]
    includes = ["-I" + str(ROOT / "native/preprocess/vendor/kissfft")]
    subprocess.run([str(compiler), *FLAGS, "-fPIC", "-shared", "-fvisibility=hidden", *includes,
                    *map(str, sources), "-lm", "-o", str(native)], check=True)
    header = output([readelf, "-h", native])
    attributes = output([readelf, "-A", native])
    symbols = output([readelf, "--dyn-syms", "--wide", native])
    dependencies = sorted(re.findall(r"Shared library: \[(.*?)\]", output([readelf, "-d", native])))
    assert "ELF32" in header and "ARM" in header and "hard-float ABI" in header
    assert "Tag_ABI_VFP_args: VFP registers" in attributes
    assert re.search(r"GLOBAL\s+DEFAULT\s+\d+\s+koocomic_filter\b", symbols)
    assert dependencies == ["libc.so.6", "libm.so.6"]
    smoke = workspace / "native-smoke"
    subprocess.run([str(compiler), *FLAGS, "-DSTATIC_FILTER", "-static", *includes,
                    str(ROOT / "spec/native_preprocess_smoke.c"), *map(str, sources),
                    "-lm", "-o", str(smoke)], check=True)
    subprocess.run(["qemu-arm", str(smoke)], check=True)
    commit = output(["git", "rev-parse", "HEAD"], cwd=ROOT)
    dirty = bool(output(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT))
    metadata = {"product_id": "koocomic-next", "channel": "experimental", "device_verified": False,
                "source_commit": commit, "source_dirty": dirty, "sdk_url": SDK_URL,
                "sdk_sha256": SDK_SHA256, "compiler": output([compiler, "-dumpfullversion"]),
                "target": PREFIX, "flags": FLAGS, "dependencies": dependencies,
                "native_sha256": sha256(native), "qemu_static_smoke": True,
                "dynamic_device_load_verified": False,
                "algorithm_source": "Euphoriyy/derainbowify.koplugin@f2892a219da65bd765d34ae2140a5dd706dfc42b"}
    inputs = [*sources, ROOT / "native/preprocess/vendor/moire_filter_kissfft.c",
              ROOT / "spec/native_preprocess_smoke.c", Path(__file__).resolve(), ROOT / "scripts/package_source.py"]
    inputs += sorted((ROOT / "native/preprocess/vendor/kissfft").glob("*.h"))
    metadata["build_input_sha256"] = {str(path.relative_to(ROOT)): sha256(path) for path in inputs}
    members = {}
    plugin = ROOT / "koocomic.koplugin"
    for path in plugin_files(ROOT):
        members["koocomic.koplugin/" + str(path.relative_to(plugin))] = path.read_bytes()
    base = "koocomic.koplugin/native/"
    members[base + "moire-kindlehf.so"] = native.read_bytes()
    members[base + "licenses/DERAINBOWIFY_LICENSE"] = (ROOT / "native/preprocess/vendor/DERAINBOWIFY_LICENSE").read_bytes()
    members[base + "licenses/KISSFFT_COPYING"] = (ROOT / "native/preprocess/vendor/kissfft/COPYING").read_bytes()
    metadata["source_tree_sha256"] = hashlib.sha256(b"".join(
        name.encode() + b"\0" + hashlib.sha256(data).digest() for name, data in sorted(members.items()))).hexdigest()
    members[base + "build.json"] = (json.dumps(metadata, sort_keys=True, indent=2) + "\n").encode()
    destination.mkdir(parents=True, exist_ok=True)
    package = destination / "koocomic-next-colorsoft-experimental.zip"
    temporary = workspace / package.name
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for name, data in sorted(members.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zipped.writestr(info, data)
    shutil.copyfile(temporary, package)
    (destination / (package.name + ".sha256")).write_text(sha256(package) + "  " + package.name + "\n")
    (destination / "build.json").write_bytes(members[base + "build.json"])
    print("Created", package, "SHA-256", sha256(package))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-archive", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="koocomic-colorsoft-build-") as temporary:
        workspace = Path(temporary)
        archive = arguments.sdk_archive
        if archive is None:
            archive = workspace / "kindlehf.tar.zst"
            subprocess.run(["curl", "--fail", "--location", "--retry", "3", SDK_URL, "-o", str(archive)], check=True)
        build(archive, arguments.output, workspace)


if __name__ == "__main__":
    main()
