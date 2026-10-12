# Actual shelf and EPUB workflow validation

## Implemented

The production shelf uses Bookshelf-style navigation and layout, with pinned,
attributed upstream helpers. Series cards enter a volume view; refresh resolves
the selected series again; back restores its view state. The original downloaded
filename and path remain unchanged.

Downloaded book details and the independent image-processing manager expose
explicit processing and restoration. Processing does not run after downloads
without a user command. The supported image resources are PNG and JPEG. Other
resources are copied unchanged. No target-display resizing is implemented yet.

A serial subprocess performs archive and image work. Scheduled 64 KiB reads
compute main-process fingerprints. A parent-only commit checks reader occupancy
and the source/output identities before replacing the file. Private original
backups, durable transaction journals and ownership claims support restoration,
interrupted-commit reconciliation and safe temporary-file cleanup. The worker
has an address-space growth limit; this is not a measured peak-RSS guarantee.

## Reproducible checks

Run each `spec/*_spec.lua` using Lua 5.1, syntax-check the plugin and specs, then:

```sh
make -C native/preprocess smoke
python3 spec/native_preprocess_spec.py
```

The pinned official Linux KOReader v2026.07.1 archive has SHA-256
`299aadb28147a25e9432ced1214ea444a4184393b5ae97cf42402c8a61b1a1b0`.
From its `lib/koreader` directory:

```sh
./luajit /path/to/checkout/spec/koreader_epub_integration.lua /path/to/checkout /tmp/koocomic-epub-test
SDL_VIDEODRIVER=dummy KO_HOME=/tmp/koocomic-render ./luajit /path/to/checkout/scripts/render_shelf.lua /path/to/checkout /tmp/series.png 600 800 series
```

Create the integration output directory first. The integration uses generated
EPUBs but real libarchive, PNG/JPEG codecs, native FFI filtering, subprocesses,
filesystem writes and SHA checks. It covers odd image dimensions and alpha,
byte-identical untouched documents, backup/restore, repeated process/restore,
symlink rejection, missed-completion reconciliation and cancel/cleanup/retry.
It is not a full fault-injection suite or a real user-library quality test.

## Colorsoft gate

The experimental binary targets official KindleHF ARM hard-float ABI. Static
ARM algorithm smoke tests pass under QEMU. The SDK dynamic-loader probe failed
before filter loading with a `do-rel.h` version assertion; actual Kindle shared
library loading remains unverified. Unsupported runtime interfaces disable the
processing controls and preserve downloads.

Before release, record the actual KOReader version from its About screen, test
the experimental package on Colorsoft, and compare original / processed /
restored files on fine text, line art, screentones, color and large real pages.
Verify reading, cancellation, restart, storage pressure, temperature, memory
and processing time. Do not use the upstream self-updater for this experiment:
its current manifest still refers to upstream KooComic.

Full catalog enumeration, offline startup, multi-selection/batch workflows and
all UI-01..24 requirements remain separate release gates. Passing these tests
does not mean the entire engineering spec is implemented.
