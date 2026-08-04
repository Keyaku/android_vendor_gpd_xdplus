#!/usr/bin/env python3
"""Capture per-path ext4 metadata (mode/uid/gid/fscaps/selabel) from a vendor
partition image, in the formats e2fsdroid consumes: an fs_config table and a
file_contexts table. Content comes from `debugfs rdump`; this fills in the
ownership and labelling that a non-root extraction loses."""
import re
import subprocess
import sys

img, tree, out_fsconf, out_fcon = sys.argv[1:5]

# Walk the extracted tree to get the path list (rdump preserves names, modes and
# symlink targets faithfully; it is uid/gid/xattrs that need to come from debugfs).
paths = subprocess.run(
	["find", ".", "-mindepth", "1", "-printf", "%P\n"],
	cwd=tree, capture_output=True, text=True, check=True,
).stdout.split("\n")
paths = sorted(p for p in paths if p)

cmds = "".join(f"stat /{p}\nea_list /{p}\n" for p in ["" ] + paths)
proc = subprocess.run(["debugfs", img], input=cmds, capture_output=True, text=True)
blocks = proc.stdout.split("Inode: ")

meta = {}
cur = None
for blk in proc.stdout.split("debugfs:  stat ")[1:]:
	path = blk.split("\n", 1)[0].strip().lstrip("/")
	m_mode = re.search(r"Mode:\s+0?(\d+)", blk)
	m_own = re.search(r"User:\s*(\d+)\s+Group:\s*(\d+)", blk)
	if not (m_mode and m_own):
		continue
	mode = m_mode.group(1)
	uid, gid = m_own.group(1), m_own.group(2)
	sel = re.search(r'security\.selinux \(\d+\) = "([^"\\]+)', blk)
	cap = re.search(r"security\.capability \(\d+\) = ([0-9a-fA-F ]+)", blk)
	capval = 0
	if cap:
		# VFS_CAP format, little-endian: magic+revision then permitted/inheritable
		by = [int(x, 16) for x in cap.group(1).split()]
		if len(by) >= 12:
			capval = int.from_bytes(bytes(by[4:8]), "little")
			if len(by) >= 20:
				capval |= int.from_bytes(bytes(by[12:16]), "little") << 32
	meta[path] = (mode, uid, gid, capval, sel.group(1) if sel else None)

with open(out_fsconf, "w") as f:
	for p in [""] + paths:
		if p not in meta:
			continue
		mode, uid, gid, capval, _ = meta[p]
		# canned_fs_config marks the image root as a line starting "/ " (empty path)
		name = f"vendor/{p}" if p else "/"
		f.write(f"{name} {uid} {gid} {mode} capabilities=0x{capval:x}\n")

with open(out_fcon, "w") as f:
	for p in [""] + paths:
		if p not in meta or meta[p][4] is None:
			continue
		esc = re.sub(r"([.\[\]{}()*+?^$|\\])", r"\\\1", "/vendor" + ("/" + p if p else ""))
		f.write(f"{esc} {meta[p][4]}\n")

print(f"paths={len(paths)} captured={len(meta)}")
missing = [p for p in paths if p not in meta]
if missing:
	print(f"MISSING METADATA ({len(missing)}): {missing[:10]}", file=sys.stderr)
