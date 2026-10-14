# Actual Shelf And EPUB Workflow Validation

Updated 2026-10-14. Current software scope is recorded in
[offline-alignment-status.md](offline-alignment-status.md); older milestone
descriptions are not the current implementation status.

## Implemented

The production shelf preserves original KOOBONE/kmoe names and paths, exposes
series/volumes/downloaded views, trusted file versions, full-catalog offline
snapshots and stable-ID cross-page selection. Downloads run in a serial,
persistent subprocess queue with pause/resume/cancel/retry and batch summaries.
Local deletion affects actual indexed files only, preserving sidecars and
unowned partial files. Download completion never triggers image processing.

The independent manual processing manager reuses the native shelf components.
Profiles freeze original/target dimensions, scaling/filter order, strength and
algorithm identity. PNG/JPEG and odd dimensions are handled by real codecs;
unrelated resources are copied unchanged. Parent-only commits recheck hashes,
paths and reader occupancy, then atomically replace the same EPUB. **No new
original backup or restoration UI exists.** Metadata backup for settings/plugin
updates is separate and does not restore processed comics.

Next updates isolate product/source, verify full packages, atomically exchange
plugin directories, preserve code/settings rollback and recover cold-start
load/init/transaction failures. Successful installation requires a restart;
old code cannot keep performing destructive operations after the switch.

## Reproducible Offline Checks

All commands are defined in `.github/workflows/ci.yml`, including 51 Lua specs,
Lua syntax, real EPUB/HTTP/fault/update integrations, UI matrices and actual
Bookshelf coexistence. The pinned official Linux runtime is v2026.07.1:
SHA-256 `299aadb28147a25e9432ced1214ea444a4184393b5ae97cf42402c8a61b1a1b0`.

```sh
make -C native/preprocess smoke
python3 spec/native_preprocess_spec.py
python3 spec/colorsoft_package_spec.py /path/to/kindlehf.tar.zst
python3 scripts/package_colorsoft.py --sdk-archive /path/to/kindlehf.tar.zst --output dist-colorsoft
```

Omit `--sdk-archive` to download the fixed official koxtoolchain 2026.08 asset.
The builder always checks its SHA before extraction/compilation. It packages
only Git-tracked plugin source, current ARM hard-float library, source licenses
and `native/build.json` provenance. Untracked settings/secrets are excluded.
The manifest records source commit/dirty state, build-input hashes, compiler,
SDK URL/SHA, ABI dependencies and static-QEMU status. Two builds with identical
inputs produce byte-identical ZIPs. No Release or stable manifest is published.

From the official runtime's `lib/koreader`, with an existing empty output dir:

```sh
./luajit /path/to/checkout/spec/koreader_epub_integration.lua /path/to/checkout /tmp/koocomic-epub-test
SDL_VIDEODRIVER=dummy KO_HOME=/tmp/koocomic-ui ./luajit /path/to/checkout/spec/koreader_ui_matrix_integration.lua /path/to/checkout 600 800
```

Fixtures are generated, not user comics. Native tests use real ZIP resources,
codecs, filtering, subprocesses and files. They cover no-backup replacement,
cancel/retry, interrupted commits, six commit faults, permission/space failure,
reaping and buffer/FD release. Some historical engine tests exercise legacy
restore support, but the production service does not create original backups.

## Colorsoft Gate

The experiment targets ARMv7 NEON hard-float with libc/libm dependencies.
ELF/symbol checks and static ARM algorithm smoke tests pass under QEMU. The SDK
glibc 2.20 dynamic loader failed before filtering with a `do-rel.h` assertion;
actual Kindle shared-library loading remains **unverified**. Build metadata
keeps `device_verified=false` and `dynamic_device_load_verified=false`.
Unsupported runtime interfaces disable processing and preserve downloads.

Before release, record the actual device KOReader version, ELF architecture,
dependency/load results and native file/ZIP interfaces. Use authorized local
comics for A/B/C on one device with fixed reading/refresh settings: A is original
with Derainbowify off; B is original with it on; C is processed with it off.
Retain original acceptance samples only in an ignored test directory, separate
from the product's no-backup replacement workflow. Do not compare a restored
product copy or repeatedly filter an already processed file.

Record fine text, lines, screentones, color and large-page results; first-open,
page-turn mean/P95, peak RSS, processing time, temporary disk space and thermal
behavior. Repeat input/cancel/restart/space pressure and physical power-loss
checks. Desktop logical night inversion is not physical Colorsoft evidence.
Do not deploy the experimental ZIP through the stable updater until these
gates pass. Real KOOBONE limits/signatures and trusted cross-file volume
relations also remain external acceptance evidence.
