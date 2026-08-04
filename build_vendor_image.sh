#!/bin/bash
# Bake vendor.img for the GPD XD+ from the tracked blob set in proprietary/vendor.
#
# WHY THIS IS A SCRIPT AND NOT A BOARD_*VENDORIMAGE* VARIABLE: this device is
# legacy system-as-root, so TARGET_COPY_OUT_VENDOR is system/vendor. AOSP's
# build/make/core/board_config.mk makes ANY vendor image a hard $(error) unless
# TARGET_COPY_OUT_VENDOR is exactly 'vendor' -- and that value turns system/vendor
# into a symlink to /vendor, which on this device is itself a symlink into the
# system image, i.e. /vendor -> /vendor: a mount loop and a fastboot bounce.
# BOARD_USES_VENDORIMAGE is .KATI_READONLY, so it cannot be forced afterwards.
# We therefore never set either variable, and drive mke2fs + e2fsdroid directly.
# Layout is untouched, so this carries no bounce risk: the failure mode is a bad
# image caught here, not a dead device.
#
# The bake is reproducible: two runs over the same tree are byte-identical.
# Against the OEM image it reproduces CONTENT and METADATA exactly (modes, uid/gid,
# file capabilities, SELinux labels), and matches its feature set, reserved-block
# count, mount options and inode count. The containers still differ in raw bytes
# because mke2fs only takes whole-MB journals and the OEM image carries a 6400 KB
# one, so --verify compares the extracted trees and their metadata, not the bytes.
#
# Usage: build_vendor_image.sh [-o OUT.img] [--verify REFERENCE.img]
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/proprietary/vendor"
FS_CONFIG="$HERE/vendor_fs_config"
FILE_CONTEXTS="$HERE/vendor_file_contexts"
UNLABELLED="$HERE/vendor_unlabelled.txt"

# Partition geometry of mmcblk0p23, taken from the OEM image. Inode count and
# inode size are matched exactly so the result lands on the same inode layout.
PART_SIZE=419430400   # 102400 blocks x 4096
INODES=25600
INODE_SIZE=256
JOURNAL_MB=6
FS_UUID=6d16bab1-58d9-3c5d-8f14-f608f924affd
LABEL=vendor
# mke2fs randomises s_hash_seed on every run even with dir_index off, and that is
# the only thing that stops two bakes of identical input being byte-identical.
# mke2fs 1.45.4 SILENTLY IGNORES -E hash_seed= (it landed in 1.46), so the field is
# zeroed afterwards instead -- which is also what the OEM image carries. Safe to
# poke directly: metadata_csum is off, so the superblock has no checksum to break.
SB_HASH_SEED_OFF=236   # offsetof(struct ext2_super_block, s_hash_seed)
# Fixed timestamp: the OEM image's mtime epoch, so repeated bakes are identical.
TIMESTAMP=1605968000

OUT="$HERE/vendor.img"
VERIFY=""
while [ $# -gt 0 ]; do
	case "$1" in
		-o|--out)   OUT="$2"; shift 2;;
		--verify)   VERIFY="$2"; shift 2;;
		*) echo "unknown arg: $1" >&2; exit 2;;
	esac
done

# AOSP host tools. Prefer an explicit $XDROOT/out, else whatever is on PATH.
if [ -n "${XDROOT:-}" ] && [ -d "$XDROOT/out/host/linux-x86/bin" ]; then
	PATH="$XDROOT/out/host/linux-x86/bin:$PATH"
fi
for t in e2fsdroid mke2fs debugfs e2fsck; do
	command -v "$t" >/dev/null || { echo "ERROR: $t not found (build the host tools, or set XDROOT)" >&2; exit 2; }
done
for f in "$SRC" "$FS_CONFIG" "$FILE_CONTEXTS" "$UNLABELLED"; do
	[ -e "$f" ] || { echo "ERROR: missing $f" >&2; exit 2; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# git cannot track empty directories, and four of them are real: lost+found plus
# the protect_f / protect_s / nvdata mountpoints. Recreate any directory that
# vendor_fs_config names but the checkout does not carry.
STAGE="$WORK/vendor"
cp -a "$SRC" "$STAGE"
while read -r d; do
	[ -n "$d" ] || continue
	mkdir -p "$STAGE/$d"
done < "$HERE/vendor_empty_dirs.txt"

# e2fsdroid aborts if a path matches no file_contexts entry, but 10 paths carry no
# security.selinux xattr in the OEM image at all (verified present in the untouched
# stock dump too -- this is ALLDOCUBE's original state, not damage from our
# debugfs edits). Bake with a catch-all so e2fsdroid is satisfied, then strip the
# label back off those 10 so the result reproduces the OEM image exactly.
cp "$FILE_CONTEXTS" "$WORK/fc"
echo '/vendor(/.*)? u:object_r:vendor_file:s0' >> "$WORK/fc"

rm -f "$OUT"
echo "baking $OUT from $SRC ..."
# mke2fs + e2fsdroid are driven directly rather than through mkuserimg_mke2fs,
# which offers no way to set the feature set. See mke2fs.conf for why that matters.
# E2FSPROGS_FAKE_TIME pins every timestamp so repeated bakes are byte-identical.
MKE2FS_CONFIG="$HERE/mke2fs.conf" E2FSPROGS_FAKE_TIME="$TIMESTAMP" \
	mke2fs -F -t ext4 -b 4096 \
		-N "$INODES" -I "$INODE_SIZE" -m 0 \
		-J "size=$JOURNAL_MB" -L "$LABEL" -M /vendor -U "$FS_UUID" \
		"$OUT" $((PART_SIZE / 4096)) >"$WORK/bake.log" 2>&1 \
	|| { echo "ERROR: mke2fs failed:" >&2; tail -20 "$WORK/bake.log" >&2; exit 3; }

E2FSPROGS_FAKE_TIME="$TIMESTAMP" \
	e2fsdroid -e -T "$TIMESTAMP" -C "$FS_CONFIG" -S "$WORK/fc" \
		-f "$STAGE" -a /vendor "$OUT" >>"$WORK/bake.log" 2>&1 \
	|| { echo "ERROR: e2fsdroid failed:" >&2; tail -20 "$WORK/bake.log" >&2; exit 3; }

# Zero s_hash_seed in the primary superblock (byte 1024) and every backup.
for sb in 1024 $(dumpe2fs "$OUT" 2>/dev/null | sed -n 's/.*Backup superblock at \([0-9]*\).*/\1/p' | awk '{print $1 * 4096}'); do
	dd if=/dev/zero of="$OUT" bs=1 seek=$((sb + SB_HASH_SEED_OFF)) count=16 conv=notrunc status=none
done

{
	while read -r p; do [ -n "$p" ] && echo "ea_rm $p security.selinux"; done < "$UNLABELLED"
	# mke2fs creates lost+found itself and e2fsdroid leaves its ownership alone.
	echo "sif /lost+found uid 0"
	echo "sif /lost+found gid 2000"
	# ...and every sif stamps the inode's ctime with the wall clock, which was the
	# last byte keeping two bakes from being identical. Pin it back.
	echo "sif /lost+found ctime @$TIMESTAMP"
	echo "sif /lost+found atime @$TIMESTAMP"
	echo "sif /lost+found mtime @$TIMESTAMP"
} | debugfs -w "$OUT" >/dev/null 2>&1

e2fsck -fn "$OUT" >"$WORK/fsck.log" 2>&1 || { echo "ERROR: e2fsck failed:" >&2; cat "$WORK/fsck.log" >&2; exit 3; }
echo "OK -> $OUT ($(stat -c%s "$OUT") bytes)"
grep -o 'Created filesystem with .*' "$WORK/bake.log" || true

if [ -n "$VERIFY" ]; then
	[ -f "$VERIFY" ] || { echo "ERROR: reference image not found: $VERIFY" >&2; exit 2; }
	echo "verifying against $VERIFY ..."
	mkdir -p "$WORK/a" "$WORK/b"
	debugfs -R "rdump / $WORK/a" "$OUT"    >/dev/null 2>&1
	debugfs -R "rdump / $WORK/b" "$VERIFY" >/dev/null 2>&1
	rc=0
	diff -r --no-dereference "$WORK/b" "$WORK/a" >"$WORK/content.diff" 2>&1 \
		&& echo "  content: IDENTICAL" || { echo "  content: DIFFERS"; head -20 "$WORK/content.diff"; rc=1; }
	"$HERE/capture_vendor_meta.py" "$OUT"    "$WORK/a" "$WORK/a.fsconf" "$WORK/a.fcon" >/dev/null
	"$HERE/capture_vendor_meta.py" "$VERIFY" "$WORK/b" "$WORK/b.fsconf" "$WORK/b.fcon" >/dev/null
	diff -q "$WORK/b.fsconf" "$WORK/a.fsconf" >/dev/null \
		&& echo "  fs_config: IDENTICAL" || { echo "  fs_config: DIFFERS"; diff "$WORK/b.fsconf" "$WORK/a.fsconf" | head -10; rc=1; }
	diff -q "$WORK/b.fcon" "$WORK/a.fcon" >/dev/null \
		&& echo "  file_contexts: IDENTICAL" || { echo "  file_contexts: DIFFERS"; diff "$WORK/b.fcon" "$WORK/a.fcon" | head -10; rc=1; }
	exit $rc
fi
