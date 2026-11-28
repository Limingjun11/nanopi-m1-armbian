#!/usr/bin/env bash
# Build a small self-contained rootfs (BusyBox, statically linked) for the M1.
#
# Everything here is compiled from source with the same cross toolchain as the
# kernel, so it works without root and without a package manager on the host.
# The result boots to a serial/HDMI console with DHCP networking.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

BB_VERSION=${BB_VERSION:-1.36.1}
BB_URL=${BB_URL:-https://busybox.net/downloads/busybox-$BB_VERSION.tar.bz2}

# ------------------------------------------------------------ toolchain ----
[ -f "$KERNEL_PROJECT/scripts/toolchain.sh" ] || die "需要 nanopi-m1-kernel/scripts/toolchain.sh"
# shellcheck disable=SC1091
. "$KERNEL_PROJECT/scripts/toolchain.sh" >/dev/null

KREL=$(cat "$KERNEL_OUT/kernel-release" 2>/dev/null || true)
[ -n "$KREL" ] || die "先编译内核（make kernel）"

# -------------------------------------------------------------- busybox ----
TAR=$CACHE/dl/busybox-$BB_VERSION.tar.bz2
SRC=$CACHE/build/busybox-$BB_VERSION
if [ ! -d "$SRC" ]; then
	if [ ! -s "$TAR" ]; then
		for u in "$BB_URL" \
			"https://mirrors.edge.kernel.org/pub/linux/utils/busybox/busybox-$BB_VERSION.tar.bz2"; do
			log "downloading $u"
			if curl -fsSL --retry 2 --connect-timeout 20 -o "$TAR.part" "$u"; then
				mv "$TAR.part" "$TAR"
				break
			fi
			warn "mirror failed: $u"
		done
	fi
	[ -s "$TAR" ] || die "BusyBox 源码下载失败"
	mkdir -p "$SRC"
	tar -xjf "$TAR" -C "$SRC" --strip-components=1
fi

log "building BusyBox $BB_VERSION (static)"
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" defconfig >/dev/null
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' "$SRC/.config"
grep -q '^CONFIG_STATIC=y' "$SRC/.config" || echo 'CONFIG_STATIC=y' >>"$SRC/.config"
# BusyBox 1.36's tc applet does not build against Linux >= 6.8 UAPI headers
# (the CBQ qdisc was removed from the kernel). We do not need traffic control.
sed -i 's/^CONFIG_TC=y/# CONFIG_TC is not set/' "$SRC/.config"
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" oldconfig </dev/null >/dev/null
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" >/dev/null

# --------------------------------------------------------------- rootfs ----
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"/{bin,sbin,etc/init.d,etc/profile.d,dev,proc,sys,tmp,run,root,var/log,boot,lib/modules,usr/bin,usr/sbin,usr/share/udhcpc}
chmod 1777 "$ROOTFS/tmp"
make -C "$SRC" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" CONFIG_PREFIX="$ROOTFS" install >/dev/null

# kernel + modules + dtb
install -m 0644 "$KERNEL_OUT/zImage" "$ROOTFS/boot/zImage"
install -m 0644 "$KERNEL_OUT/dtb/sun8i-h3-nanopi-m1.dtb" "$ROOTFS/boot/"
cp -a "$KERNEL_OUT/modules/lib/modules/." "$ROOTFS/lib/modules/"
rm -f "$ROOTFS/lib/modules/$KREL/build" "$ROOTFS/lib/modules/$KREL/source"

install -d "$ROOTFS/boot/extlinux"
cat >"$ROOTFS/boot/extlinux/extlinux.conf" <<'EOF'
default nanopi-m1
label nanopi-m1
    kernel /boot/zImage
    devicetree /boot/sun8i-h3-nanopi-m1.dtb
    append root=/dev/mmcblk0p1 rootwait rw cma=64M console=ttyS0,115200 console=tty1
EOF

cat >"$ROOTFS/etc/inittab" <<'EOF'
::sysinit:/etc/init.d/rcS
::respawn:/sbin/getty -L ttyS0 115200 vt100
::respawn:/sbin/getty -L tty1 38400 vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
EOF

cat >"$ROOTFS/etc/init.d/rcS" <<'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev 2>/dev/null
mount -t tmpfs tmpfs /run
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts 2>/dev/null
hostname -F /etc/hostname
ifconfig lo up
for i in /lib/modules/*/modules.dep; do modprobe -a lima sun4i_drm 2>/dev/null; break; done
ifconfig eth0 up
udhcpc -i eth0 -b -q -s /usr/share/udhcpc/default.script
EOF
chmod +x "$ROOTFS/etc/init.d/rcS"

cat >"$ROOTFS/usr/share/udhcpc/default.script" <<'EOF'
#!/bin/sh
case "$1" in
bound|renew)
	case "${mask:-255.255.255.0}" in
	255.0.0.0) p=8 ;;
	255.255.0.0) p=16 ;;
	255.255.255.0) p=24 ;;
	*) p=24 ;;
	esac
	ip link set "$interface" up
	ip addr flush dev "$interface"
	ip addr add "$ip/$p" dev "$interface"
	[ -n "$router" ] && ip route add default via "$router" dev "$interface" 2>/dev/null
	[ -n "$dns" ] && echo "nameserver $dns" >/etc/resolv.conf
	;;
esac
EOF
chmod +x "$ROOTFS/usr/share/udhcpc/default.script"

printf 'nanopi-m1\n' >"$ROOTFS/etc/hostname"
cat >"$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	nanopi-m1
EOF
printf 'nameserver 223.5.5.5\nnameserver 1.1.1.1\n' >"$ROOTFS/etc/resolv.conf"
cat >"$ROOTFS/etc/fstab" <<'EOF'
/dev/mmcblk0p1	/	ext4	defaults,noatime	0 1
EOF

cat >"$ROOTFS/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/sh
EOF
cat >"$ROOTFS/etc/group" <<'EOF'
root:x:0:
EOF
HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
cat >"$ROOTFS/etc/shadow" <<EOF
root:$HASH:19000:0:99999:7:::
EOF
chmod 0640 "$ROOTFS/etc/shadow"

cat >"$ROOTFS/etc/profile" <<'EOF'
export PATH=/sbin:/usr/sbin:/bin:/usr/bin
export PS1='\u@\h:\w\$ '
EOF

cat >"$ROOTFS/etc/motd" <<'EOF'

  NanoPi M1 (Allwinner H3) - mainline kernel
  root / nanopi

EOF

log "busybox rootfs ready: $ROOTFS ($(du -sh "$ROOTFS" | cut -f1))"
