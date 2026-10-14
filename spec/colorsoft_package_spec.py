"""Offline colour experimental package contract; no release publication."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts/package_colorsoft.py"
assert BUILDER.is_file(), "reproducible colour package builder is missing"
KINDLEHF_SHA = "8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0"
KOBO_SHA = "326dd2a2a5ca371073c4ebc783d578f93f4122d83c46b84ec85b9e3ed5ff2305"
TARGETS = {
    "kindlehf": ("moire-kindlehf.so", KINDLEHF_SHA),
    "kobo": ("moire-kobo.so", KOBO_SHA),
}


def archive_args():
    args = []
    if len(sys.argv) > 1:
        args += ["--sdk-archive", "kindlehf=" + sys.argv[1]]
    if len(sys.argv) > 2:
        args += ["--sdk-archive", "kobo=" + sys.argv[2]]
    return args


with tempfile.TemporaryDirectory(prefix="koocomic-package-test-") as temporary:
    directory = Path(temporary)
    invalid = directory / "invalid-sdk.tar.zst"
    invalid.write_bytes(b"untrusted SDK")
    rejected = subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--sdk-archive",
            "kindlehf=" + str(invalid),
            "--output",
            str(directory / "rejected"),
        ],
        capture_output=True,
        text=True,
    )
    assert rejected.returncode != 0 and "SDK checksum mismatch" in rejected.stderr
    assert not list(directory.rglob("*.zip")), (
        "unverified SDK must never produce a package"
    )
    command = [
        sys.executable,
        str(BUILDER),
        "--output",
        str(directory / "package"),
    ] + archive_args()
    with tempfile.TemporaryDirectory(
        prefix=".package-private-fixture-", dir=ROOT / "koocomic.koplugin"
    ) as private:
        private = Path(private)
        (private / ".env").write_text("PRIVATE_PACKAGE_FIXTURE=must-not-ship\n")
        (private / "credentials.json").write_text('{"fixture":"must-not-ship"}')
        (private / "settings.lua.bak").write_text("return {fixture='must-not-ship'}")
        subprocess.run(command, check=True)
        first = (
            directory / "package/koocomic-next-colorsoft-experimental.zip"
        ).read_bytes()
        subprocess.run(command, check=True)
        assert (
            directory / "package/koocomic-next-colorsoft-experimental.zip"
        ).read_bytes() == first, "same source/SDK must produce byte-identical packages"
    archive = directory / "package/koocomic-next-colorsoft-experimental.zip"
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    assert (archive.parent / (archive.name + ".sha256")).read_text().split()[
        0
    ] == digest
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None
        names = package.namelist()
        assert not any(".package-private-fixture-" in name for name in names), (
            "untracked private files entered package"
        )
        assert all(
            name.startswith("koocomic.koplugin/") and ".." not in Path(name).parts
            for name in names
        )
        assert not any(name.endswith((".epub", ".part", ".log")) for name in names)
        assert "koocomic.koplugin/koobone/native/moire-kindlehf.so" not in names
        metadata = json.loads(package.read("koocomic.koplugin/native/build.json"))
        assert (
            metadata["channel"] == "experimental"
            and metadata["device_verified"] is False
        )
        assert (
            metadata["source_commit"]
            == subprocess.check_output(
                ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
            ).strip()
        )
        assert type(metadata["source_dirty"]) is bool
        assert set(metadata["targets"]) == set(TARGETS)
        for target, (name, sdk_sha) in TARGETS.items():
            info = metadata["targets"][target]
            native = package.read("koocomic.koplugin/native/" + name)
            assert native[:6] == b"\x7fELF\x01\x01"
            assert info["native_sha256"] == hashlib.sha256(native).hexdigest()
            assert info["sdk_sha256"] == sdk_sha
            assert info["dependencies"] == ["libc.so.6", "libm.so.6"]
            assert info["qemu_static_smoke"] is True
            assert info["dynamic_device_load_verified"] is False
        for name, expected in metadata["build_input_sha256"].items():
            assert expected == hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        assert package.read("koocomic.koplugin/native/licenses/DERAINBOWIFY_LICENSE")
        assert package.read("koocomic.koplugin/native/licenses/KISSFFT_COPYING")
    print("Colour package (kindle + kobo, provenance, reproducibility): OK")
