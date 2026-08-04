# android_vendor_gpd_xdplus

Proprietary blob set for the GPD XD+ (`xdplus`), LineageOS 18.1.

The XD+ runs a frozen **ALLDOCUBE U1005E Android 8.1** vendor: PowerVR DDK `1.9@4893595`, MediaTek `hwcomposer`, the MTK TrustZone client, widevine, and MT6630 Wi-Fi/BT firmware. None of it is compilable and none of it ever will be. **This repo owns the packaging, not the source** — the blobs live here as tracked files with their ownership, modes, capabilities and SELinux labels recorded alongside, and `build_vendor_image.sh` turns them back into the exact `vendor.img` that the device runs.

## Why this repo exists

`/vendor` on this device is the physical partition `mmcblk0p23`, mounted at `/system/vendor`. Before this tree, that partition could only be modified by `debugfs`-patching a 400 MB image by hand, and each patch produced a new image whose only provenance was a sentence in a document. Nobody, including us, could regenerate one from first principles. This tree removes that: the image is now a build product of tracked files, and changing a blob or a property is an edit plus a rebake.

## Contents

| Path | What |
|---|---|
| `proprietary/vendor/` | The vendor partition contents — 564 files, 153 symlinks, 31 directories. |
| `proprietary/etc/` | Five system-side files (Wi-Fi supplicant configs, `md32` DSP firmware) installed into `/system` by `xdplus-vendor.mk`. |
| `vendor_fs_config` | Per-path uid/gid/mode/file-capabilities, 748 entries. |
| `vendor_file_contexts` | Per-path SELinux label, 738 entries. |
| `vendor_unlabelled.txt` | The 10 paths carrying no `security.selinux` xattr. |
| `vendor_empty_dirs.txt` | Directories git cannot track: `lost+found` and the `protect_f` / `protect_s` / `nvdata` mountpoints. |
| `build_vendor_image.sh` | Bakes `vendor.img`. `--verify REF.img` checks the result against a reference. |
| `mke2fs.conf` | Filesystem feature set, matching the OEM image. **Not optional** — without it `mke2fs` reads the host's `/etc/mke2fs.conf`, and e2fsprogs 1.47+ enables features this device cannot read. |
| `capture_vendor_meta.py` | Regenerates `vendor_fs_config` + `vendor_file_contexts` from an image. |

Git stores only the exec bit, so **the metadata files are not optional bookkeeping** — they are the only record of ownership, setuid-class modes, the two file capabilities, and every SELinux label. A bake without them produces an image that boots into a very different device.

## Building the image

```sh
export XDROOT=/path/to/lineage-18.1   # to find the AOSP host tools
./build_vendor_image.sh -o vendor.img
```

Verify against a known-good image:

```sh
./build_vendor_image.sh -o /tmp/v.img --verify /path/to/vendor-...-mmcblk0p23.img
#   content: IDENTICAL
#   fs_config: IDENTICAL
#   file_contexts: IDENTICAL
```

`--verify` compares the **extracted trees and their metadata**, not the raw bytes. Everything that reaches the running system is identical, and the container matches the OEM image's feature set, reserved-block count, mount options and inode count. The raw bytes still differ for one reason: `mke2fs` only takes whole-megabyte journals and the OEM image carries a 6400 KB one.

The bake itself **is** byte-reproducible — two runs over the same tree produce identical images. Three things had to be pinned to get there, each of which silently defeated it: `E2FSPROGS_FAKE_TIME` for file timestamps, `s_hash_seed` (`mke2fs` randomises it per run, and 1.45.4 *silently ignores* `-E hash_seed=`, which only landed in 1.46), and the `lost+found` inode's ctime, which every `debugfs sif` stamps with the wall clock.

The image is not flashed by `mka bacon`, which writes system and boot only. It is injected into the flashable zip by `scripts/inject_vendor.sh` in the umbrella repo.

## Why the build does not install these

The build stages its own `/vendor` content — VNDK, HAL services, `vintf` manifests, sepolicy — into `out/.../system/vendor/`, and **all of it is shadowed at runtime** by the `mmcblk0p23` mount over `/system/vendor`. Installing the blobs there too would be equally shadowed, so `xdplus-vendor.mk` deliberately installs only the five system-side files. The vendor partition is written from the image, not from the system image.

For the same reason this tree must **never** set `TARGET_COPY_OUT_VENDOR` or any `BOARD_*VENDORIMAGE*` variable. AOSP's `build/make/core/board_config.mk` makes any vendor image a hard `$(error)` unless `TARGET_COPY_OUT_VENDOR` is exactly `vendor`, and that value makes `system/vendor` a symlink to `/vendor` — which on this legacy system-as-root device is itself a symlink into the system image, giving `/vendor -> /vendor`, a mount loop and a fastboot bounce. `BOARD_USES_VENDORIMAGE` is `.KATI_READONLY`, so it cannot be forced afterwards either. `build_vendor_image.sh` sidesteps all of it by driving `mkuserimg_mke2fs` directly and never touching the layout.

## Provenance

Extracted from the device's own `/vendor`, verified byte-identical to the running partition across all 564 files.

Deltas from the untouched stock dump, all deliberate:

- **108 camera files removed**, 0 added — the device has no camera.
- **`build.prop`** — fingerprint, date and security patch rewritten from ALLDOCUBE/U1005E to GPD/xdplus, with the release id pinned so it equals `ro.system.build.fingerprint`. A per-build value there fails `Build.isBuildConsistent()` and raises the "Internal problem with your device" dialog on every boot. Bump the release id only when vendor **content** changes, and rebake in the same operation.
- **`etc/mixer_paths.xml`** — wired-headset capture routed to the internal mic.
- **`lib64/hw/hwcomposer.mt8173.so`** — acqfd-patched, `31918bb7…` → `54b28199…`. The stock blob aborts on an unclosed acquire fd.

Cross-checked against `third_party/android_vendor_cube_u1005` (the ALLDOCUBE X tablet, same blob lineage): **318 of 339 overlapping files are byte-identical**. Cube's `hwcomposer.mt8173.so` is exactly the unpatched `31918bb7…`, confirming the lineage. The 21 that differ are genuine XD+ hardware deltas — MT6630 combo firmware and its `wmt_*` / `autobt` tools, `gatekeeper` / `keystore` (TEE-bound), `sensors`, the widevine pair, `MTKThermalManager.apk`, and `libsrv_um.so` on both ABIs (same `1.9@4893595` build string, different binary). A further 225 partition files have no cube counterpart at all. **Cube is the ABI reference for kernel-facing interfaces; it is not the blob source.**

### History

Until this tree was rebuilt, `proprietary/vendor/` held BlackSeraph's published LineageOS 15.1 `xds` vendor set — **DDK `1.7@4167538`, ELF "for Android 24"** — 317 of its 318 files byte-identical to his tree, camera-stripped, with one local `mixer_paths.xml` edit. It was labelled in its own commit message as an ALLDOCUBE 8.1 extraction, which it was not. Nothing installed it, so it never reached a device, but 1.7 user-mode blobs against the 1.9 kernel driver this port ships is precisely the mismatch that produces `PVRSRVConnectKM: Incompatible driver`. The ALLDOCUBE 1.9 import had been planned and was never executed; this tree is that import.
