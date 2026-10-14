#!/usr/bin/env bash
# Mount a real FAT-family filesystem over a loop device and run the atomic
# commit paths there. This is the "test defense" for the runtime-only class of
# bug where renameat2 works on the ext4 build machine but is rejected on the
# Kindle userstore.
#
# Usage: verify_atomic_filesystem.sh <koreader-lib-dir> <repo-root> [fstype] [size-mb]
set -euo pipefail

KOREADER_LIB="${1:?koreader lib directory (containing luajit) required}"
REPO_ROOT="${2:?repository root required}"
FSTYPE="${3:-vfat}"
SIZE_MB="${4:-24}"

case "$FSTYPE" in
    vfat) MKFS=(mkfs.vfat) ;;
    exfat) MKFS=(mkfs.exfat) ;;
    msdos) MKFS=(mkfs.msdos) ;;
    *) echo "unsupported filesystem: $FSTYPE" >&2; exit 2 ;;
esac

LUAIIT="$KOREADER_LIB/luajit"
if [[ ! -x "$LUAIIT" ]]; then echo "luajit not found at $LUAIIT" >&2; exit 2; fi

SUDO=""
if [[ "$(id -u)" != "0" ]]; then
    if command -v sudo >/dev/null 2>&1; then SUDO="sudo"; else echo "root or sudo required to mount" >&2; exit 3; fi
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/koocomic-fs-XXXXXX")"
IMAGE="$WORK/atomic.img"
MOUNT="$WORK/mnt"
mkdir -p "$MOUNT"

cleanup() {
    if mountpoint -q "$MOUNT"; then $SUDO umount "$MOUNT" || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

truncate -s "${SIZE_MB}M" "$IMAGE"
"${MKFS[@]}" "$IMAGE" >/dev/null
$SUDO mount -o loop,umask=0000 "$IMAGE" "$MOUNT"
mountpoint -q "$MOUNT" || { echo "failed to mount $FSTYPE loopback" >&2; exit 4; }

echo "Running atomic commit integration on $FSTYPE at $MOUNT"
cd "$KOREADER_LIB"
./luajit "$REPO_ROOT/spec/koreader_atomic_vfat_integration.lua" "$REPO_ROOT" "$MOUNT"
