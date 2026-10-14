"""Offline experimental package contract; no release publication."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "scripts/package_colorsoft.py"
assert BUILDER.is_file(), "reproducible Colorsoft experimental builder is missing"
with tempfile.TemporaryDirectory(prefix="koocomic-package-test-") as temporary:
    directory = Path(temporary)
    invalid = directory / "invalid-sdk.tar.zst"
    invalid.write_bytes(b"untrusted SDK")
    rejected = subprocess.run([sys.executable, str(BUILDER), "--sdk-archive", str(invalid),
                               "--output", str(directory / "rejected")], capture_output=True, text=True)
    assert rejected.returncode != 0 and "SDK checksum mismatch" in rejected.stderr
    assert not list(directory.rglob("*.zip")), "unverified SDK must never produce a package"
    command = [sys.executable, str(BUILDER), "--output", str(directory / "package")]
    if len(sys.argv) > 1:
        command += ["--sdk-archive", sys.argv[1]]
    with tempfile.TemporaryDirectory(prefix=".package-private-fixture-", dir=ROOT / "koocomic.koplugin") as private:
        private = Path(private)
        (private / ".env").write_text("PRIVATE_PACKAGE_FIXTURE=must-not-ship\n")
        (private / "credentials.json").write_text('{"fixture":"must-not-ship"}')
        (private / "settings.lua.bak").write_text("return {fixture='must-not-ship'}")
        subprocess.run(command, check=True)
        first = (directory / "package/koocomic-next-colorsoft-experimental.zip").read_bytes()
        subprocess.run(command, check=True)
        assert (directory / "package/koocomic-next-colorsoft-experimental.zip").read_bytes() == first, "same source/SDK must produce byte-identical packages"
    archive = directory / "package/koocomic-next-colorsoft-experimental.zip"
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    assert (archive.parent / (archive.name + ".sha256")).read_text().split()[0] == digest
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None
        names = package.namelist()
        assert not any(".package-private-fixture-" in name for name in names), "untracked private files entered package"
        assert all(name.startswith("koocomic.koplugin/") and ".." not in Path(name).parts for name in names)
        assert not any(name.endswith((".epub", ".part", ".log")) for name in names)
        assert "koocomic.koplugin/koobone/native/moire-kindlehf.so" not in names
        native = package.read("koocomic.koplugin/native/moire-kindlehf.so")
        assert native[:6] == b"\x7fELF\x01\x01"
        metadata = json.loads(package.read("koocomic.koplugin/native/build.json"))
        assert metadata["channel"] == "experimental" and metadata["device_verified"] is False
        assert metadata["native_sha256"] == hashlib.sha256(native).hexdigest()
        assert metadata["source_commit"] == subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        assert type(metadata["source_dirty"]) is bool
        assert metadata["sdk_sha256"] == "8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0"
        assert metadata["dependencies"] == ["libc.so.6", "libm.so.6"]
        assert metadata["qemu_static_smoke"] is True
        assert metadata["dynamic_device_load_verified"] is False
        for name, expected in metadata["build_input_sha256"].items():
            assert expected == hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
        assert package.read("koocomic.koplugin/native/licenses/DERAINBOWIFY_LICENSE")
        assert package.read("koocomic.koplugin/native/licenses/KISSFFT_COPYING")
    print("Colorsoft SDK rejection, ARM static smoke, package provenance/licenses: OK")
