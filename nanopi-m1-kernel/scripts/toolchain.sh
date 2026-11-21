#!/usr/bin/env bash
# Prepare an arm-linux-gnueabihf cross toolchain without root.
#
# Order of preference:
#   1. NANOPI_M1_CROSS_COMPILE (e.g. /opt/tc/bin/arm-linux-gnueabihf-)
#   2. a system-wide arm-linux-gnueabihf-gcc
#   3. Ubuntu/Debian: download the cross packages with apt-get download and
#      unpack them into the cache (fast on Chinese mirrors)
#   4. Bootlin prebuilt toolchain (works on any x86_64 glibc distro)
#
# Writes $CACHE/toolchain.env and prints it to stdout.

set -euo pipefail
__tc_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$__tc_dir/lib.sh"

write_env() { # $1 = cross prefix, $2 = extra path, $3 = extra ld path
	local cross=$1 extra_path=${2:-} extra_ld=${3:-}
	{
		echo "export CROSS_COMPILE='$cross'"
		echo "export PATH=\"${extra_path}:\$PATH\""
		[ -n "$extra_ld" ] && echo "export LD_LIBRARY_PATH='$extra_ld'"
	} >"$TOOLCHAIN_ENV"
	# shellcheck disable=SC1090
	. "$TOOLCHAIN_ENV"
}

ok() { command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; }

# 1. explicit override
if [ -n "${NANOPI_M1_CROSS_COMPILE:-}" ]; then
	CROSS_COMPILE=${NANOPI_M1_CROSS_COMPILE%/}-
	write_env "$CROSS_COMPILE"
	ok || die "NANOPI_M1_CROSS_COMPILE 指向的工具链不可用: $CROSS_COMPILE"
	log "toolchain: $(${CROSS_COMPILE}gcc --version | head -1)"
	return 0
fi

# 2. system toolchain
if command -v arm-linux-gnueabihf-gcc >/dev/null 2>&1; then
	write_env "arm-linux-gnueabihf-"
	log "toolchain: system $(arm-linux-gnueabihf-gcc --version | head -1)"
	return 0
fi

# 3. apt-get download (no root needed)
if command -v apt-get >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1; then
	TC=$CACHE/toolchain-apt
	if [ ! -x "$TC/root/usr/bin/arm-linux-gnueabihf-gcc-11" ]; then
		mkdir -p "$TC/debs" "$TC/root"
		if ! ls "$TC"/debs/*.deb >/dev/null 2>&1; then
			log "downloading cross toolchain via apt-get download (no root)"
			(
				cd "$TC/debs" || exit 1
				apt-get download \
					binutils-arm-linux-gnueabihf \
					cpp-11-arm-linux-gnueabihf \
					gcc-11-arm-linux-gnueabihf \
					libc6-armhf-cross \
					libc6-dev-armhf-cross \
					libgcc-11-dev-armhf-cross \
					libgcc-s1-armhf-cross \
					linux-libc-dev-armhf-cross
			) || warn "apt-get download 失败"
		fi
		if ls "$TC"/debs/*.deb >/dev/null 2>&1; then
			log "unpacking cross toolchain"
			for d in "$TC"/debs/*.deb; do dpkg-deb -x "$d" "$TC/root"; done
		fi
	fi
	if [ -x "$TC/root/usr/bin/arm-linux-gnueabihf-gcc-11" ]; then
		# apt 的交叉包没有把 alternatives 软链带出来，这里补一个稳定的入口
		[ -e "$TC/root/usr/bin/arm-linux-gnueabihf-gcc" ] ||
			ln -s arm-linux-gnueabihf-gcc-11 "$TC/root/usr/bin/arm-linux-gnueabihf-gcc"
		write_env "$TC/root/usr/bin/arm-linux-gnueabihf-" \
			"$TC/root/usr/bin" \
			"$TC/root/usr/lib/x86_64-linux-gnu:$TC/root/usr/lib"
		if ok; then
			log "toolchain: apt $(${CROSS_COMPILE}gcc --version | head -1)"
			return 0
		fi
	fi
fi

# 4. Bootlin
TC=$CACHE/toolchain-bootlin
BOOTLIN_TAR=$CACHE/dl/toolchain-bootlin.tar.xz
BOOTLIN_URL=${BOOTLIN_URL:-https://toolchains.bootlin.com/downloads/releases/toolchains/armv7-eabihf/tarballs/armv7-eabihf--glibc--stable-2026.08-1.tar.xz}
if [ ! -x "$TC/bin/arm-linux-gnueabihf-gcc" ]; then
	log "downloading Bootlin toolchain"
	mkdir -p "$TC"
	curl -fL --retry 3 -o "$BOOTLIN_TAR" "$BOOTLIN_URL" || die "工具链下载失败，请设置 NANOPI_M1_CROSS_COMPILE"
	tar -xJf "$BOOTLIN_TAR" -C "$TC" --strip-components=1
fi
write_env "$TC/bin/arm-linux-gnueabihf-"
ok || die "工具链不可用"
log "toolchain: bootlin $(${CROSS_COMPILE}gcc --version | head -1)"
