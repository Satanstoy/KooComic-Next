#!/usr/bin/env python3
"""Build an unpublished colour package with every supported native filter."""

import argparse
import json
from pathlib import Path
import shutil
import tempfile
import zipfile

import native_targets as N
import package_native as Native
from package_source import plugin_files

ROOT = Path(__file__).resolve().parents[1]


def build(archives, destination, workspace):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    native = Path(workspace) / "native"
    Native.build(N.TARGET_ORDER, native, overrides=archives, channel="experimental")
    members = {}
    plugin = ROOT / "koocomic.koplugin"
    for path in plugin_files(ROOT):
        members["koocomic.koplugin/" + str(path.relative_to(plugin))] = (
            path.read_bytes()
        )
    base = "koocomic.koplugin/native/"
    for path in sorted(native.rglob("*")):
        if path.is_file():
            members[base + str(path.relative_to(native))] = path.read_bytes()
    package = destination / "koocomic-next-colorsoft-experimental.zip"
    temporary = Path(workspace) / package.name
    with zipfile.ZipFile(
        temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=9
    ) as zipped:
        for name, data in sorted(members.items()):
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.external_attr = 0o100644 << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            zipped.writestr(info, data)
    shutil.copyfile(temporary, package)
    (destination / (package.name + ".sha256")).write_text(
        N.sha256_file(package) + "  " + package.name + "\n"
    )
    (destination / "build.json").write_bytes((native / "build.json").read_bytes())
    print("Created", package, "SHA-256", N.sha256_file(package))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--sdk-archive", action="append", default=[], metavar="TARGET=PATH"
    )
    parser.add_argument("--sdk-dir", type=Path)
    arguments = parser.parse_args()
    overrides = {}
    for value in arguments.sdk_archive:
        target, _, path = value.partition("=")
        overrides[target or "kindlehf"] = path
    with tempfile.TemporaryDirectory(prefix="koocomic-colorsoft-build-") as temporary:
        build(overrides, arguments.output, temporary)


if __name__ == "__main__":
    main()
