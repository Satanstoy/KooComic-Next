#!/usr/bin/env python3
"""Build the native de-moire filter for every supported colour platform.

Emits a native directory (one .so per target, plus licenses and build.json)
that package_release.sh merges into the single stable package, so a colour
device no longer has to pick a separate experimental download.
"""

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import native_targets as N


def _git(*args):
    return subprocess.check_output(["git", *args], cwd=N.ROOT, text=True).strip()


def resolve_archive(target, spec, sdk_dir, overrides, workspace):
    if target in overrides:
        return Path(overrides[target])
    if sdk_dir:
        candidate = Path(sdk_dir) / spec["sdk_asset"]
        if candidate.is_file():
            return candidate
    destination = workspace / spec["sdk_asset"]
    subprocess.run(
        [
            "curl",
            "--fail",
            "--location",
            "--retry",
            "3",
            spec["sdk_url"],
            "-o",
            str(destination),
        ],
        check=True,
    )
    return destination


def build(targets, output, sdk_dir=None, overrides=None, channel="stable"):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    (output / "licenses").mkdir(exist_ok=True)
    metadata = {
        "product_id": "koocomic-next",
        "channel": channel,
        "device_verified": False,
        "algorithm_source": N.ALGORITHM_SOURCE,
        "targets": {},
    }
    for target in targets:
        spec = N.TARGETS[target]
        with tempfile.TemporaryDirectory(prefix="koocomic-native-") as temporary:
            workspace = Path(temporary)
            archive = resolve_archive(target, spec, sdk_dir, overrides or {}, workspace)
            data, meta = N.build_target(target, archive, workspace)
            compiler = (
                workspace
                / "x-tools"
                / spec["prefix"]
                / "bin"
                / (spec["prefix"] + "-gcc")
            )
            meta.update(
                {
                    "output": spec["output"],
                    "sdk_url": spec["sdk_url"],
                    "sdk_sha256": spec["sdk_sha256"],
                    "compiler": subprocess.check_output(
                        [str(compiler), "-dumpfullversion"], text=True
                    ).strip(),
                }
            )
            metadata["targets"][target] = meta
            (output / spec["output"]).write_bytes(data)
    for name, data in N.license_bytes().items():
        (output / "licenses" / name).write_bytes(data)
    metadata["source_commit"] = _git("rev-parse", "HEAD")
    metadata["source_dirty"] = bool(
        _git("status", "--porcelain", "--untracked-files=all")
    )
    inputs = N.build_inputs() + [
        Path(__file__).resolve(),
        Path(__file__).resolve().parent / "native_targets.py",
    ]
    metadata["build_input_sha256"] = {
        str(path.relative_to(N.ROOT)): N.sha256_file(path) for path in inputs
    }
    digest = hashlib.sha256()
    for path in sorted(output.rglob("*")):
        if path.is_file() and path.name != "build.json":
            digest.update(
                str(path.relative_to(output)).encode()
                + b"\0"
                + hashlib.sha256(path.read_bytes()).digest()
            )
    metadata["source_tree_sha256"] = digest.hexdigest()
    (output / "build.json").write_text(
        json.dumps(metadata, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    print("Native targets built:", ", ".join(targets), "->", output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--targets", default=",".join(N.TARGET_ORDER))
    parser.add_argument("--sdk-dir", type=Path)
    parser.add_argument(
        "--sdk-archive", action="append", default=[], metavar="TARGET=PATH"
    )
    parser.add_argument("--channel", default="stable")
    arguments = parser.parse_args()
    overrides = {}
    for value in arguments.sdk_archive:
        target, _, path = value.partition("=")
        overrides[target] = path
    targets = [name for name in arguments.targets.split(",") if name]
    for name in targets:
        if name not in N.TARGETS:
            raise SystemExit("unknown target: " + name)
    build(
        targets,
        arguments.output,
        sdk_dir=arguments.sdk_dir,
        overrides=overrides,
        channel=arguments.channel,
    )


if __name__ == "__main__":
    main()
