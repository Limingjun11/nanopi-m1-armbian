#!/usr/bin/env bash
# Inspect a built image without mounting it (no root needed).
#
#   ./scripts/inspect.sh out/nanopi-m1-6.18.64.img

set -euo pipefail
IMG=${1:?用法: $0 <image>}
[ -f "$IMG" ] || { echo "找不到 $IMG" >&2; exit 1; }

echo "== 文件 =="
ls -lh "$IMG"
echo
echo "== 分区表 =="
sfdisk -d "$IMG"
echo
echo "== U-Boot @8KiB =="
dd if="$IMG" bs=1 skip=8192 count=8 status=none | od -An -tx1
echo
echo "== 根分区 =="
START=$(sfdisk -d "$IMG" | sed -n 's/.*start= *\([0-9]*\).*/\1/p' | head -1)
OFF=$((START * 512))
SIZE=$(sfdisk -d "$IMG" | sed -n 's/.*size= *\([0-9]*\).*/\1/p' | head -1)
TMP=$(mktemp)
dd if="$IMG" of="$TMP" bs=512 skip="$START" count="$SIZE" status=none
trap 'rm -f "$TMP"' EXIT

debugfs -R "ls -l /boot" "$TMP" 2>/dev/null | sed 's/^.*(\([0-9]*\)).* /\1 /' | head -12
echo
echo "== /boot/extlinux/extlinux.conf =="
debugfs -R "cat /boot/extlinux/extlinux.conf" "$TMP" 2>/dev/null
echo
echo "== 内核 release =="
debugfs -R "cat /lib/modules/$(debugfs -R 'ls /lib/modules' "$TMP" 2>/dev/null | tr -s ' ' '\n' | grep -v '^$' | tail -1)/modules.dep" "$TMP" >/dev/null 2>&1 &&
	echo "modules.dep 存在"
