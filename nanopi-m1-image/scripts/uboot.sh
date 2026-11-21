#!/usr/bin/env bash
# Build mainline U-Boot for the NanoPi M1 (nanopi_m1_defconfig).
#
# The board config lives in upstream U-Boot since v2016.05 and is maintained;
# it produces u-boot-sunxi-with-spl.bin which goes to offset 8KiB of the card.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

# reuse the kernel project's cross toolchain
[ -f "$KERNEL_PROJECT/scripts/toolchain.sh" ] ||
	die "找不到 $KERNEL_PROJECT/scripts/toolchain.sh（本项目依赖 nanopi-m1-kernel）"
# shellcheck disable=SC1091
. "$KERNEL_PROJECT/scripts/toolchain.sh" >/dev/null

TARBALL=$CACHE/dl/u-boot-$UBOOT_VERSION.tar.gz
SRC=$CACHE/build/u-boot-$UBOOT_VERSION

if [ ! -d "$SRC" ]; then
	if [ ! -s "$TARBALL" ]; then
		urls=()
		[ -n "${UBOOT_URL:-}" ] && urls+=("$UBOOT_URL")
		urls+=(
			"https://gh-proxy.com/https://github.com/u-boot/u-boot/archive/refs/tags/v$UBOOT_VERSION.tar.gz"
			"https://github.com/u-boot/u-boot/archive/refs/tags/v$UBOOT_VERSION.tar.gz"
			"https://source.denx.de/u-boot/u-boot/-/archive/v$UBOOT_VERSION/u-boot-v$UBOOT_VERSION.tar.gz"
		)
		ok=0
		for u in "${urls[@]}"; do
			log "downloading $u"
			if curl -fL --retry 2 --connect-timeout 20 -o "$TARBALL.part" "$u"; then
				mv "$TARBALL.part" "$TARBALL"
				ok=1
				break
			fi
			warn "mirror failed: $u"
		done
		[ "$ok" = 1 ] || die "U-Boot 源码下载失败"
	fi
	log "extracting U-Boot $UBOOT_VERSION"
	mkdir -p "$SRC"
	tar -xzf "$TARBALL" -C "$SRC" --strip-components=1
fi

log "building U-Boot ($(nproc) jobs)"
make -C "$SRC" CROSS_COMPILE="$CROSS_COMPILE" nanopi_m1_defconfig >/dev/null
# host tool mkeficapsule needs gnutls headers; not needed on this board
"$SRC/scripts/config" --file "$SRC/.config" --disable TOOLS_MKEFICAPSULE
make -C "$SRC" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig >/dev/null
make -C "$SRC" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" >/dev/null

install -m 0644 "$SRC/u-boot-sunxi-with-spl.bin" "$OUT/u-boot-sunxi-with-spl.bin"
log "U-Boot: $OUT/u-boot-sunxi-with-spl.bin ($(stat -c%s "$OUT/u-boot-sunxi-with-spl.bin") bytes)"
