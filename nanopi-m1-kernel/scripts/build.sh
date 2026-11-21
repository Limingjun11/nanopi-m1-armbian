#!/usr/bin/env bash
# Fetch, configure, build and package a mainline LTS kernel for the NanoPi M1.
#
# Tunables (env or `make VAR=...`):
#   KERNEL_VERSION=6.18.64        kernel version to build
#   KERNEL_MIRROR=<base url>      first download mirror
#   JOBS=<n>                      parallel build jobs
#   CACHE/OUT                     directories

set -euo pipefail
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/toolchain.sh"

FRAGMENT=$PROJECT_DIR/configs/kernel.fragment
PATCHES=$PROJECT_DIR/patches

# ---------------------------------------------------------------- source ----
series=${KERNEL_VERSION%%.*}.x
fetch_kernel() {
	[ -s "$TARBALL" ] && return 0
	local name=linux-$KERNEL_VERSION.tar.xz
	local urls=(
		"$KERNEL_MIRROR/$name"
		"https://mirrors.163.com/kernel/v$series/$name"
		"https://mirrors.aliyun.com/linux-kernel/v$series/$name"
		"https://cdn.kernel.org/pub/linux/kernel/v$series/$name"
	)
	local u
	for u in "${urls[@]}"; do
		log "downloading $u"
		if curl -fL --retry 2 --connect-timeout 20 -o "$TARBALL.part" "$u"; then
			mv "$TARBALL.part" "$TARBALL"
			return 0
		fi
		warn "mirror failed: $u"
	done
	die "无法下载 linux-$KERNEL_VERSION.tar.xz，请用 KERNEL_MIRROR=... 指定镜像"
}

if [ ! -d "$SRC" ]; then
	fetch_kernel
	log "extracting linux-$KERNEL_VERSION"
	tar -xJf "$TARBALL" -C "$CACHE/build"
fi

# ----------------------------------------------------------------- patch ----
DTS=$SRC/arch/arm/boot/dts/allwinner/sun8i-h3-nanopi-m1.dts
if [ -d "$PATCHES" ]; then
	for p in "$PATCHES"/*.patch; do
		[ -e "$p" ] || continue
		if patch -d "$SRC" -p1 -N -s --dry-run <"$p" >/dev/null 2>&1; then
			log "applying $(basename "$p")"
			patch -d "$SRC" -p1 -N -s <"$p"
		elif grep -q 'allwinner,audio-routing' "$DTS" 2>/dev/null; then
			log "patch already applied: $(basename "$p")"
		else
			die "补丁无法应用: $p"
		fi
	done
fi

# ---------------------------------------------------------------- config ----
log "configuring (sunxi_defconfig + kernel.fragment)"
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" sunxi_defconfig >/dev/null

apply_fragment() {
	local line sym val
	while IFS= read -r line; do
		case $line in
		'' | '#'*) continue ;;
		esac
		sym=${line%%=*}
		val=${line#*=}
		case $val in
		y) "$SRC/scripts/config" --file "$SRC/.config" --enable "$sym" ;;
		m) "$SRC/scripts/config" --file "$SRC/.config" --module "$sym" ;;
		n) "$SRC/scripts/config" --file "$SRC/.config" --disable "$sym" ;;
		*) "$SRC/scripts/config" --file "$SRC/.config" --set-val "$sym" "$val" ;;
		esac
	done <"$FRAGMENT"
}
apply_fragment
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" olddefconfig >/dev/null

verify_fragment() {
	local line sym want got bad=0
	while IFS= read -r line; do
		case $line in
		'' | '#'*) continue ;;
		esac
		sym=${line%%=*}
		want=${line#*=}
		got=$(sed -n "s/^$sym=//p" "$SRC/.config" | head -1)
		if [ "$got" != "$want" ]; then
			warn "配置未生效: $sym 期望 $want 实际 ${got:-(未设置)}"
			bad=1
		fi
	done <"$FRAGMENT"
	[ "$bad" -eq 0 ] || die "内核配置校验失败（依赖不满足？）"
}
verify_fragment

# ----------------------------------------------------------------- build ----
log "building zImage + modules + dtbs (jobs=$JOBS)"
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" zImage modules dtbs

KREL=$(make -s -C "$SRC" ARCH=arm kernelrelease)
log "kernel release: $KREL"

# --------------------------------------------------------------- package ----
log "installing modules into out/"
rm -rf "$OUT/modules"
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" \
	INSTALL_MOD_PATH="$OUT/modules" INSTALL_MOD_STRIP=1 modules_install >/dev/null

mkdir -p "$OUT/dtb"
rm -f "$OUT/zImage" "$OUT/dtb"/*.dtb
cp "$SRC/arch/arm/boot/zImage" "$OUT/zImage"
cp "$SRC/arch/arm/boot/dts/allwinner/sun8i-h3-nanopi-m1.dtb" "$OUT/dtb/"
cp "$SRC/.config" "$OUT/config-$KREL"
cp "$SRC/System.map" "$OUT/System.map-$KREL"
printf '%s\n' "$KREL" >"$OUT/kernel-release"

tarball=$OUT/nanopi-m1-kernel-$KREL.tar.gz
tar -czf "$tarball" -C "$OUT" \
	zImage dtb modules config-"$KREL" System.map-"$KREL" kernel-release

log "done"
printf '  kernel : %s\n  dtb    : %s\n  modules: %s\n  tarball: %s\n' \
	"$OUT/zImage" "$OUT/dtb/sun8i-h3-nanopi-m1.dtb" "$OUT/modules" "$tarball"
