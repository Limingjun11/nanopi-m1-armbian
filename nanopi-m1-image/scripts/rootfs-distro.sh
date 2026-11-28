#!/usr/bin/env bash
# Build a full Debian or Ubuntu armhf rootfs with mmdebstrap.
#
#   DISTRO=debian  (default trixie)  -> http://mirrors.aliyun.com/debian
#   DISTRO=ubuntu  (default noble)   -> http://ports.ubuntu.com/ubuntu-ports
#
# Requires root (mmdebstrap needs chroot + binfmt_misc for the armhf binaries).
# On GitHub runners that is available through sudo; locally run it as root.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

DISTRO=${DISTRO:-debian}
case "$DISTRO" in
debian)
	SUITE=${SUITE:-trixie}
	MIRROR=${MIRROR:-http://mirrors.aliyun.com/debian}
	;;
ubuntu)
	SUITE=${SUITE:-noble}
	MIRROR=${MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
	;;
*)
	die "DISTRO 必须是 debian 或 ubuntu（当前: $DISTRO）"
	;;
esac

[ "$(id -u)" -eq 0 ] || die "这个脚本需要 root；请用 sudo 或 make rootfs-$DISTRO"
command -v mmdebstrap >/dev/null || die "需要 mmdebstrap"
[ -e /proc/sys/fs/binfmt_misc/qemu-arm ] || die "需要 qemu-user + binfmt（armhf 二进制无法执行）"

KREL=$(cat "$KERNEL_OUT/kernel-release" 2>/dev/null || true)
[ -n "$KREL" ] || die "先编译内核（make kernel）"

# ---------------------------------------------------------------- keyring ---
case "$DISTRO" in
debian)
	KEYRING=$CACHE/keyrings/usr/share/keyrings/debian-archive-keyring.pgp
	if [ ! -f "$KEYRING" ]; then
		mkdir -p "$CACHE/keyrings"
		curl -fsSL --retry 3 -o "$CACHE/keyrings/keyring.deb" \
			"$MIRROR/pool/main/d/debian-archive-keyring/debian-archive-keyring_2025.1_all.deb"
		dpkg-deb -x "$CACHE/keyrings/keyring.deb" "$CACHE/keyrings"
		rm -f "$CACHE/keyrings/keyring.deb"
	fi
	;;
ubuntu)
	KEYRING=/usr/share/keyrings/ubuntu-archive-keyring.gpg
	[ -f "$KEYRING" ] || die "缺少 $KEYRING（apt install ubuntu-keyring）"
	;;
esac

# ----------------------------------------------------------------- rootfs ---
if [ "${REBUILD_ROOTFS:-0}" = 1 ] || [ ! -x "$ROOTFS/usr/bin/bash" ]; then
	log "building $DISTRO $SUITE rootfs (mmdebstrap, armhf)"
	rm -rf "$ROOTFS"
	INCLUDE=$(grep -v '^#' "$PROJECT_DIR/configs/packages.txt" | grep -v '^$' | paste -sd, -)
	mmdebstrap \
		--mode=root --arch=armhf --variant=minbase --components=main \
		--keyring="$KEYRING" --include="$INCLUDE" \
		"$SUITE" "$ROOTFS" "$MIRROR"
fi

# -------------------------------------------------------------- customize ---
log "installing kernel, modules and board configuration"
install -d "$ROOTFS/boot/extlinux" "$ROOTFS/lib/modules" "$ROOTFS/etc/systemd/network"
install -m 0644 "$KERNEL_OUT/zImage" "$ROOTFS/boot/zImage"
install -m 0644 "$KERNEL_OUT/dtb/sun8i-h3-nanopi-m1.dtb" "$ROOTFS/boot/"
rm -rf "${ROOTFS:?}/lib/modules/"*
cp -a "$KERNEL_OUT/modules/lib/modules/." "$ROOTFS/lib/modules/"
rm -f "$ROOTFS/lib/modules/$KREL/build" "$ROOTFS/lib/modules/$KREL/source"

cat >"$ROOTFS/boot/extlinux/extlinux.conf" <<'EOF'
default nanopi-m1
label nanopi-m1
    kernel /boot/zImage
    devicetree /boot/sun8i-h3-nanopi-m1.dtb
    append root=/dev/mmcblk0p1 rootwait rw console=ttyS0,115200 console=tty1
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

enable_unit() {
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

# root password without chroot: write the hash straight into /etc/shadow
HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
if grep -q '^root:' "$ROOTFS/etc/shadow"; then
	sed -i "s|^root:[^:]*:|root:$HASH:|" "$ROOTFS/etc/shadow"
else
	printf 'root:%s:19000:0:99999:7:::\n' "$HASH" >>"$ROOTFS/etc/shadow"
fi

# ssh host keys (armhf ssh-keygen via binfmt)
chroot "$ROOTFS" /usr/bin/ssh-keygen -A >/dev/null 2>&1 || warn "ssh-keygen -A 失败"

log "$DISTRO rootfs ready: $ROOTFS ($(du -sh "$ROOTFS" | cut -f1))"
