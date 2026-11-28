#!/usr/bin/env bash
# Build the Debian armhf rootfs for the NanoPi M1 and install the kernel in it.
#
# No root required: mmdebstrap runs in "proot" mode with qemu-arm, and all
# post-install configuration is done by writing files (plus a little proot
# for ssh-keygen/chpasswd).

set -euo pipefail
. "$(dirname "$0")/lib.sh"

# ------------------------------------------------------------- kernel ------
KREL=$(cat "$KERNEL_OUT/kernel-release" 2>/dev/null || true)
if [ -z "$KREL" ] || [ ! -f "$KERNEL_OUT/zImage" ]; then
	log "内核产物不存在，先编译内核"
	PROJECT_DIR="$KERNEL_PROJECT" CACHE="$CACHE" OUT="$KERNEL_OUT" \
		make -C "$KERNEL_PROJECT" build
	KREL=$(cat "$KERNEL_OUT/kernel-release")
fi
[ -f "$KERNEL_OUT/dtb/sun8i-h3-nanopi-m1.dtb" ] || die "缺少 M1 设备树"
log "kernel: $KREL"

# -------------------------------------------------------------- proot ------
PROOT=$CACHE/bin/proot
if [ ! -x "$PROOT" ]; then
	log "downloading static proot"
	mkdir -p "$CACHE/bin"
	curl -fL --retry 3 -o "$PROOT.part" \
		"https://gh-proxy.com/https://github.com/proot-me/proot/releases/download/v5.5.0/proot" ||
		curl -fL --retry 3 -o "$PROOT.part" \
			"https://github.com/proot-me/proot/releases/download/v5.5.0/proot" ||
		die "proot 下载失败"
	mv "$PROOT.part" "$PROOT"
	chmod +x "$PROOT"
fi

# mmdebstrap calls "proot"; wrap it so foreign binaries go through qemu-arm.
mkdir -p "$CACHE/bin-qemu"
cat >"$CACHE/bin-qemu/proot" <<EOF
#!/bin/sh
exec $PROOT -q qemu-arm "\$@"
EOF
chmod +x "$CACHE/bin-qemu/proot"

command -v mmdebstrap >/dev/null || die "需要 mmdebstrap（apt install mmdebstrap）"
mmdebstrap --help 2>&1 | grep -q 'proot' ||
	die "当前 mmdebstrap 不支持 proot 模式（需要 <= 0.8.x，Ubuntu 22.04 自带即可）"
command -v qemu-arm >/dev/null || die "需要 qemu-user（apt install qemu-user）"

# Debian archive keyring (host usually only ships the Ubuntu one)
KEYRING=$CACHE/keyrings/usr/share/keyrings/debian-archive-keyring.pgp
if [ ! -f "$KEYRING" ]; then
	log "downloading debian-archive-keyring"
	KDIR=$CACHE/keyrings
	mkdir -p "$KDIR"
	curl -fL --retry 3 -o "$KDIR/keyring.deb" \
		"$MIRROR/pool/main/d/debian-archive-keyring/debian-archive-keyring_2025.1_all.deb" ||
		die "debian-archive-keyring 下载失败"
	dpkg-deb -x "$KDIR/keyring.deb" "$KDIR"
	rm -f "$KDIR/keyring.deb"
fi

# --------------------------------------------------------------- rootfs ----
if [ "${REBUILD_ROOTFS:-0}" = 1 ] || [ ! -x "$ROOTFS/usr/bin/bash" ]; then
	log "building rootfs ($SUITE/armhf) with mmdebstrap --mode=proot"
	rm -rf "$ROOTFS"
	INCLUDE=$(grep -v '^#' "$PROJECT_DIR/configs/packages.txt" | grep -v '^$' | paste -sd, -)
	PATH="$CACHE/bin-qemu:$CACHE/bin:$PATH" \
		mmdebstrap \
		--mode=proot --arch=armhf --variant=minbase --components=main \
		--keyring="$KEYRING" \
		--include="$INCLUDE" \
		"$SUITE" "$ROOTFS" "$MIRROR"
fi

# ------------------------------------------------------------ customize ----
log "installing kernel, modules and board configuration"

install -d "$ROOTFS/boot/extlinux" "$ROOTFS/lib/modules" "$ROOTFS/etc/systemd/network"
install -m 0644 "$KERNEL_OUT/zImage" "$ROOTFS/boot/zImage"
install -m 0644 "$KERNEL_OUT/dtb/sun8i-h3-nanopi-m1.dtb" "$ROOTFS/boot/"
rm -rf "$ROOTFS/lib/modules/"*
cp -a "$KERNEL_OUT/modules/lib/modules/." "$ROOTFS/lib/modules/"
rm -f "$ROOTFS/lib/modules/$KREL/build" "$ROOTFS/lib/modules/$KREL/source"

cat >"$ROOTFS/boot/extlinux/extlinux.conf" <<EOF
default nanopi-m1
label nanopi-m1
    kernel /boot/zImage
    devicetree /boot/sun8i-h3-nanopi-m1.dtb
    append root=/dev/mmcblk0p1 rootwait rw cma=64M console=ttyS0,115200 console=tty1
EOF

cat >"$ROOTFS/etc/fstab" <<'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
/dev/mmcblk0p1	/	ext4	defaults,noatime	0 1
EOF

cat >"$ROOTFS/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

printf '%s\n' "nanopi-m1" >"$ROOTFS/etc/hostname"
cat >"$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	nanopi-m1
::1		localhost ip6-localhost ip6-loopback
EOF

: >"$ROOTFS/etc/machine-id"
chmod 0444 "$ROOTFS/etc/machine-id"
rm -f "$ROOTFS/etc/resolv.conf"
cat >"$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 223.5.5.5
nameserver 1.1.1.1
EOF

# enable the services we want on a headless board
enable_unit() { # $1 = unit, $2 = target.wants
	[ -e "$ROOTFS/lib/systemd/system/$1" ] || return 0
	install -d "$ROOTFS/etc/systemd/system/$2"
	ln -sfn "/lib/systemd/system/$1" "$ROOTFS/etc/systemd/system/$2/$1"
}
enable_unit ssh.service multi-user.target.wants
enable_unit systemd-networkd.service multi-user.target.wants
enable_unit systemd-networkd.socket sockets.target.wants
enable_unit systemd-resolved.service multi-user.target.wants

install -d "$ROOTFS/etc/ssh/sshd_config.d"
cat >"$ROOTFS/etc/ssh/sshd_config.d/10-root-login.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
EOF

# root password + ssh host keys: run the real armhf tools through proot
if command -v qemu-arm >/dev/null 2>&1; then
	printf 'root:%s\n' "$ROOT_PASSWORD" |
		"$PROOT" -0 -q qemu-arm -r "$ROOTFS" -b /proc -b /dev -b /sys -w / \
			/usr/sbin/chpasswd 2>/dev/null ||
		warn "chpasswd 失败，稍后用串口单用户模式改密码"
	"$PROOT" -0 -q qemu-arm -r "$ROOTFS" -b /proc -b /dev -b /sys -w / \
		/usr/bin/ssh-keygen -A >/dev/null 2>&1 || warn "ssh-keygen -A 失败"
else
	warn "没有 qemu-arm，root 密码保持锁定"
fi

log "rootfs ready: $ROOTFS"
