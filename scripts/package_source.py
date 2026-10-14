"""Controlled source inventory shared by stable and experimental packages."""
from pathlib import Path
import shutil
import subprocess
import sys


def plugin_files(root):
    root = Path(root).resolve()
    names = subprocess.check_output(["git", "ls-files", "-z", "--", "koocomic.koplugin"], cwd=root).decode().split("\0")
    names = sorted(name for name in names if name)
    required = {"koocomic.koplugin/" + name for name in
                ("main.lua", "_meta.lua", "koobone/plugin.lua", "koobone/plugin_version.lua", "LICENSE", "NOTICE")}
    if not required.issubset(names):
        raise SystemExit("Required plugin sources are not tracked")
    result = []
    for name in names:
        path = root / name
        if any((root / Path(*Path(name).parts[:count])).is_symlink() for count in range(1, len(Path(name).parts) + 1)):
            raise SystemExit("Plugin source symlink refused: " + name)
        if not path.is_file():
            raise SystemExit("Tracked plugin source is missing: " + name)
        if path.name not in {"LICENSE", "NOTICE"} and path.suffix.lower() not in {".lua", ".md", ".png", ".jpg", ".jpeg", ".svg", ".ttf", ".otf"}:
            raise SystemExit("Unapproved plugin source type: " + name)
        if path.name in {"koobone.lua", "koocomic.lua"}:
            raise SystemExit("Runtime settings cannot enter plugin package")
        result.append(path)
    return result


if __name__ == "__main__":
    root, destination = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    sources = plugin_files(root)
    for source in sources:
        target = destination / source.relative_to(root / "koocomic.koplugin")
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
