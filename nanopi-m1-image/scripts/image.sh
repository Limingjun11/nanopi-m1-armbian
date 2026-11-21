#!/usr/bin/env bash
# Assemble the bootable SD card image from U-Boot + rootfs.
#
# Layout (MBR):
#   0..8KiB      partition table
#   8KiB         u-boot-sunxi-with-spl.bin (SPL + U-Boot proper + dtb)
#   4MiB..end    single ext4 partition with the rootfs
#
# No root and no loop device needed:
#   * mke2fs -d builds the filesystem straight from the rootfs directory
#   * file ownership is fixed up inside the image with a debugfs batch
#     (chown(2) cannot be used: the build user is not root)

set -euo pipefail
. "$(dirname "$0")/lib.sh"

[ -f "$OUT/u-boot-sunxi-with-spl.bin" ] || die "缺少 U-Boot，先 make uboot"
[ -x "$ROOTFS/bin/sh" ] || [ -x "$ROOTFS/usr/bin/bash" ] || die "缺少 rootfs，先 make rootfs"

KREL=$(cat "$KERNEL_OUT/kernel-release" 2>/dev/null || echo unknown)
DISTRO=${DISTRO:-busybox}
if [ "$DISTRO" = busybox ]; then
	IMG=$OUT/nanopi-m1-$KREL.img
else
	IMG=$OUT/nanopi-m1-$KREL-$DISTRO.img
fi
OFFSET=$((4 * 1024 * 1024)) # 4MiB
START_SEC=$((OFFSET / 512))

IMG_BYTES=$(numfmt --from=iec "$IMG_SIZE")
PART_BYTES=$((IMG_BYTES - OFFSET))
PART=$WORK/part.img

log "building ext4 filesystem ($((PART_BYTES / 1024 / 1024)) MiB) from $ROOTFS"
rm -f "$PART"
truncate -s "$PART_BYTES" "$PART"
mke2fs -q -F -t ext4 -L rootfs -d "$ROOTFS" "$PART"

if [ "$(stat -c %u "$ROOTFS")" = 0 ]; then
	log "rootfs already owned by root, skipping ownership fix"
else
log "normalising ownership to root"
CMDS=$WORK/debugfs.cmds
(
	cd "$ROOTFS"
	find . -mindepth 1 -printf '/%P\n'
) | while IFS= read -r p; do
	printf 'sif "%s" uid 0\nsif "%s" gid 0\n' "$p" "$p"
done >"$CMDS"
debugfs -w -f "$CMDS" "$PART" >/dev/null 2>&1 || warn "debugfs 调整属主时有告警"
rm -f "$CMDS"
fi

log "creating $IMG ($IMG_SIZE)"
rm -f "$IMG"
truncate -s "$IMG_BYTES" "$IMG"
TOTAL_SEC=$((IMG_BYTES / 512))
sfdisk -q "$IMG" >/dev/null <<EOF
label: dos
label-id: 0x4e504931
start=$START_SEC, size=$((TOTAL_SEC - START_SEC)), type=83, bootable
EOF

log "copying filesystem into partition"
dd if="$PART" of="$IMG" bs=1M seek=4 conv=notrunc status=none
rm -f "$PART"

log "writing U-Boot at 8KiB"
dd if="$OUT/u-boot-sunxi-with-spl.bin" of="$IMG" bs=1024 seek=8 conv=notrunc status=none

log "compressing (xz -T0 -6)"
xz -T0 -6 -c "$IMG" >"$IMG.xz"

{
	echo "kernel:      $KREL"
	echo "rootfs:      $DISTRO"
	echo "image:       $(basename "$IMG")"
	echo "image size:  $(stat -c%s "$IMG") bytes"
	echo "compressed:  $(stat -c%s "$IMG.xz") bytes"
	echo "sha256:      $(sha256sum "$IMG.xz" | cut -d' ' -f1)"
} | tee "$OUT/manifest.txt"

log "done"
