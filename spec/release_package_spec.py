"""Stable packages must use a controlled, complete source inventory."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="koocomic-release-spec-") as temporary:
    directory = Path(temporary)
    shutil.copytree(root / "koocomic.koplugin", directory / "koocomic.koplugin")
    shutil.copytree(root / "release-notes", directory / "release-notes")
    (directory / "scripts").mkdir()
    for name in ("package_release.sh", "package_source.py"):
        if (root / "scripts" / name).exists():
            shutil.copy2(root / "scripts" / name, directory / "scripts" / name)
    subprocess.run(["git", "init", "-q", str(directory)], check=True)
    subprocess.run(["git", "add", "koocomic.koplugin"], cwd=directory, check=True)
    plugin = directory / "koocomic.koplugin"
    for name in (".env", "credentials.json", "settings.lua.bak"):
        (plugin / name).write_text("synthetic private fixture, not real credentials")
    command = ["bash", str(directory / "scripts/package_release.sh"), "v0.4.1", "Satanstoy/KooComic-Next", str(directory / "dist")]
    subprocess.run(command, check=True, capture_output=True)
    with zipfile.ZipFile(directory / "dist/release/koocomic.koplugin-v0.4.1.zip") as zipped:
        names = zipped.namelist()
        assert not any(name.endswith((".env", "credentials.json", "settings.lua.bak")) for name in names), "private local files entered stable ZIP"
    (plugin / "koobone/plugin.lua").unlink()
    rejected = subprocess.run(command, capture_output=True, text=True)
    assert rejected.returncode != 0, "missing tracked production module must reject package"
    shutil.copy2(root / "koocomic.koplugin/koobone/plugin.lua", plugin / "koobone/plugin.lua")
    subprocess.run(["git", "add", "koocomic.koplugin/credentials.json"], cwd=directory, check=True)
    assert subprocess.run(command, capture_output=True).returncode != 0, "even tracked private files must be rejected"
print("Stable source inventory, privacy and completeness: OK")
