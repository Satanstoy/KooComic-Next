#!/usr/bin/env python3
"""Validate a built native directory and merge it into a plugin package tree."""

import json
from pathlib import Path
import sys


def merge(source, destination):
    source, destination = Path(source), Path(destination)
    metadata = json.loads((source / "build.json").read_text(encoding="utf-8"))
    if metadata.get("product_id") != "koocomic-next" or not isinstance(
        metadata.get("targets"), dict
    ):
        raise SystemExit("unrecognized native build.json")
    for target, info in metadata["targets"].items():
        output = info.get("output")
        if not isinstance(output, str) or not (source / output).is_file():
            raise SystemExit("native build is missing the " + str(target) + " output")
    target_dir = destination / "native"
    for path in sorted(source.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(source)
        if relative.suffix not in (".so", ".json") and relative.parts[0] != "licenses":
            raise SystemExit("unexpected native file: " + str(relative))
        written = target_dir / relative
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_bytes(path.read_bytes())
    print(
        "Merged native targets:",
        ", ".join(sorted(metadata["targets"])),
        "->",
        target_dir,
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: package_native_merge.py <native-dir> <plugin-dir>")
    merge(sys.argv[1], sys.argv[2])
