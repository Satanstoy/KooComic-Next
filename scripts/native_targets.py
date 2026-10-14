"""Shared cross-compile definitions for the native de-moire filter.

Every colour e-ink ARM platform we support gets its own prebuilt shared object
because Kindle and Kobo share the armv7 hard-float ABI but not the libc
sysroot. Keeping the target table here lets both the experimental colour
package and the single stable release bundle build from one place.
"""

from pathlib import Path
import hashlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]

TARGETS = {
    "kindlehf": {
        "sdk_asset": "kindlehf.tar.zst",
        "sdk_url": "https://github.com/koreader/koxtoolchain/releases/download/2026.08/kindlehf.tar.zst",
        "sdk_sha256": "8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0",
        "prefix": "arm-kindlehf-linux-gnueabihf",
        "output": "moire-kindlehf.so",
    },
    "kobo": {
        "sdk_asset": "kobo.tar.zst",
        "sdk_url": "https://github.com/koreader/koxtoolchain/releases/download/2026.08/kobo.tar.zst",
        # Pinned after the first verified download (see package_native.py --print-sha).
        "sdk_sha256": "326dd2a2a5ca371073c4ebc783d578f93f4122d83c46b84ec85b9e3ed5ff2305",
        "prefix": "arm-kobo-linux-gnueabihf",
        "output": "moire-kobo.so",
    },
}
TARGET_ORDER = ["kindlehf", "kobo"]

FLAGS = [
    "-O2",
    "-Wall",
    "-Wextra",
    "-std=c99",
    "-march=armv7-a",
    "-mfpu=neon",
    "-mfloat-abi=hard",
]
SOURCES = ["filter.c", "vendor/kissfft/kiss_fft.c", "vendor/kissfft/kiss_fftnd.c"]
LICENSES = {
    "DERAINBOWIFY_LICENSE": "vendor/DERAINBOWIFY_LICENSE",
    "KISSFFT_COPYING": "vendor/kissfft/COPYING",
}
EXPECTED_DEPENDENCIES = ["libc.so.6", "libm.so.6"]
ALGORITHM_SOURCE = (
    "Euphoriyy/derainbowify.koplugin@f2892a219da65bd765d34ae2140a5dd706dfc42b"
)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha256_file(path):
    with Path(path).open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def _output(command, **kwargs):
    return subprocess.check_output(
        [str(value) for value in command], text=True, **kwargs
    ).strip()


def build_target(target, archive, workspace):
    """Cross-compile one target. Returns (so_bytes, metadata) or raises."""
    spec = TARGETS[target]
    archive = Path(archive)
    if sha256_file(archive) != spec["sdk_sha256"]:
        raise SystemExit("SDK checksum mismatch for " + target)
    subprocess.run(
        ["tar", "--zstd", "-xf", str(archive), "-C", str(workspace)], check=True
    )
    prefix = spec["prefix"]
    compiler = workspace / "x-tools" / prefix / "bin" / (prefix + "-gcc")
    readelf = compiler.with_name(prefix + "-readelf")
    native = workspace / spec["output"]
    include = ["-I" + str(ROOT / "native/preprocess/vendor/kissfft")]
    sources = [ROOT / "native/preprocess" / name for name in SOURCES]
    subprocess.run(
        [
            str(compiler),
            *FLAGS,
            "-fPIC",
            "-shared",
            "-fvisibility=hidden",
            *include,
            *map(str, sources),
            "-lm",
            "-o",
            str(native),
        ],
        check=True,
    )
    header = _output([readelf, "-h", native])
    attributes = _output([readelf, "-A", native])
    symbols = _output([readelf, "--dyn-syms", "--wide", native])
    dependencies = sorted(
        re.findall(r"Shared library: \[(.*?)\]", _output([readelf, "-d", native]))
    )
    assert "ELF32" in header and "ARM" in header and "hard-float ABI" in header
    assert "Tag_ABI_VFP_args: VFP registers" in attributes, (
        "filter must use VFP register arguments on " + target
    )
    assert re.search(r"GLOBAL\s+DEFAULT\s+\d+\s+koocomic_filter\b", symbols)
    assert dependencies == EXPECTED_DEPENDENCIES, (
        "unexpected ABI dependencies for " + target + ": " + repr(dependencies)
    )
    smoke = workspace / (spec["output"] + ".smoke")
    subprocess.run(
        [
            str(compiler),
            *FLAGS,
            "-DSTATIC_FILTER",
            "-static",
            *include,
            str(ROOT / "spec/native_preprocess_smoke.c"),
            *map(str, sources),
            "-lm",
            "-o",
            str(smoke),
        ],
        check=True,
    )
    subprocess.run(["qemu-arm", str(smoke)], check=True)
    return native.read_bytes(), {
        "target": prefix,
        "flags": list(FLAGS),
        "dependencies": dependencies,
        "native_sha256": sha256_file(native),
        "qemu_static_smoke": True,
        "dynamic_device_load_verified": False,
    }


def build_inputs():
    inputs = [
        *[ROOT / "native/preprocess" / name for name in SOURCES],
        ROOT / "native/preprocess/vendor/moire_filter_kissfft.c",
        ROOT / "spec/native_preprocess_smoke.c",
        ROOT / "scripts/native_targets.py",
    ]
    inputs += sorted((ROOT / "native/preprocess/vendor/kissfft").glob("*.h"))
    return inputs


def license_bytes():
    return {
        name: (ROOT / "native/preprocess" / relative).read_bytes()
        for name, relative in LICENSES.items()
    }


if __name__ == "__main__":
    import sys

    if len(sys.argv) == 3 and sys.argv[1] == "--print-sha":
        print(sha256_file(sys.argv[2]))
    else:
        raise SystemExit("usage: native_targets.py --print-sha <archive>")
