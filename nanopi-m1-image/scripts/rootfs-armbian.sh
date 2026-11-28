#!/usr/bin/env bash
# Build a rootfs from the archived Armbian NanoPi M1 image and swap in our
# mainline 6.18 kernel.
#
# Armbian marked this board EOS, so the official build framework can no longer
# produce an image. The last release (21.08.1, kernel 5.10.60) is still in the
# archive; we keep its userland (armbian-config, armbian-firstrun, ...) and
# replace kernel, modules, device tree and the boot loader.
#
# Works without root when run as the build user (debugfs rdump); as root it
# preserves ownership directly.

set -euo pipefail
. "$(dirname "$0")/lib.sh"

ARMBIAN_URL=${ARMBIAN_URL:-https://archive.armbian.com/nanopim1/archive/Armbian_21.08.1_Nanopim1_bullseye_current_5.10.60.img.xz}
RAW=${ARMBIAN_IMAGE:-$CACHE/dl/armbian-nanopim1.img}
XZ=$CACHE/dl/armbian-nanopim1.img.xz

KREL=$(cat "$KERNEL_OUT/kernel-release" 2>/dev/null || true)
[ -n "$KREL" ] || die "先编译内核（make kernel）"

# ------------------------------------------------------------- download -----
if [ -z "${ARMBIAN_IMAGE:-}" ]; then
	if [ ! -s "$RAW" ]; then
		if [ ! -s "$XZ" ]; then
			log "downloading Armbian 21.08.1 nanopim1 (348 MB)"
			curl -fL --retry 3 -o "$XZ.part" "$ARMBIAN_URL"
			mv "$XZ.part" "$XZ"
		fi
		log "decompressing"
		xz -dc "$XZ" >"$RAW.part"
		mv "$RAW.part" "$RAW"
	fi
fi
[ -s "$RAW" ] || die "找不到 Armbian 镜像: $RAW"

# ---------------------------------------------------------- extract fs ------
log "locating rootfs partition"
START=$(sfdisk -d "$RAW" | sed -n 's/.*start= *\([0-9]*\).*/\1/p' | head -1)
SIZE=$(sfdisk -d "$RAW" | sed -n 's/.*size= *\([0-9]*\).*/\1/p' | head -1)
[ -n "$START" ] && [ -n "$SIZE" ] || die "无法解析分区表"

PART=$CACHE/work-image/armbian.part
mkdir -p "$CACHE/work-image"
log "extracting partition ($((SIZE / 2048)) MiB)"
rm -f "$PART"
dd if="$RAW" of="$PART" bs=512 skip="$START" count="$SIZE" status=none

log "unpacking rootfs (debugfs rdump)"
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
debugfs -R "rdump / $ROOTFS" "$PART" >/dev/null 2>&1 || warn "debugfs rdump 有告警"
rm -f "$PART"

[ -x "$ROOTFS/bin/sh" ] || [ -x "$ROOTFS/usr/bin/bash" ] || die "rootfs 提取失败"

# ---------------------------------------------------------- customize ------
log "swapping kernel / boot loader"
rm -rf "$ROOTFS/boot"
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

# Armbian's own boot chain (boot.scr + armbianEnv) is not used any more
rm -f "$ROOTFS/boot/boot.scr" "$ROOTFS/boot/armbianEnv.txt"

cat >"$ROOTFS/etc/fstab" <<'EOF'
# <file system> <mount point> <type> <options> <dump> <pass>
/dev/mmcblk0p1	/	ext4	defaults,noatime	0 1
EOF

printf '%s\n' "nanopi-m1" >"$ROOTFS/etc/hostname"
cat >"$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1	localhost
127.0.1.1	nanopi-m1
::1		localhost ip6-localhost ip6-loopback
EOF
# Armbian bullseye uses ifupdown/dhclient, not systemd-resolved: a symlink to
# /run/systemd/resolve/stub-resolv.conf would dangle and break DNS until DHCP
# rewrites the file. Ship a real file instead; dhclient replaces it on lease.
rm -f "$ROOTFS/etc/resolv.conf"
cat >"$ROOTFS/etc/resolv.conf" <<'EOF'
nameserver 223.5.5.5
nameserver 1.1.1.1
EOF

# keep DHCP from replacing the hard-coded DNS on lease renewal
install -d "$ROOTFS/etc/dhcp"
printf '\nsupersede domain-name-servers 223.5.5.5, 1.1.1.1;\n' \
	>>"$ROOTFS/etc/dhcp/dhclient.conf"

# Armbian first-boot wizard and the ramlog/zram helpers expect Armbian's own
# boot environment (armbianEnv.txt, /var/log.hdd); they either fail or stall
# for 15-90s here, so mask them and boot straight to a login prompt.
install -d "$ROOTFS/etc/systemd/system"
for unit in \
	armbian-firstrun.service \
	armbian-ramlog.service \
	armbian-zram-config.service \
	armbian-hardware-optimization.service \
	armbian-hardware-monitor.service \
	armbian-resize-filesystem.service \
	systemd-networkd-wait-online.service \
	ifupdown-wait-online.service \
	NetworkManager-wait-online.service; do
	ln -sfn /dev/null "$ROOTFS/etc/systemd/system/$unit"
done

# make sure the serial console getty comes up on ttyS0
if [ -e "$ROOTFS/lib/systemd/system/serial-getty@.service" ]; then
	install -d "$ROOTFS/etc/systemd/system/getty.target.wants"
	ln -sfn /lib/systemd/system/serial-getty@.service \
		"$ROOTFS/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
fi

# keep eth0 on DHCP even if NetworkManager is present
cat >"$ROOTFS/etc/systemd/network/20-wired.network" <<'EOF'
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

install -d "$ROOTFS/etc/ssh/sshd_config.d"
cat >"$ROOTFS/etc/ssh/sshd_config.d/10-root-login.conf" <<'EOF'
PermitRootLogin yes
PasswordAuthentication yes
EOF

# known root password instead of Armbian's forced first-login change
HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
if grep -q '^root:' "$ROOTFS/etc/shadow"; then
	sed -i "s|^root:[^:]*:|root:$HASH:|" "$ROOTFS/etc/shadow"
fi
rm -f "$ROOTFS/root/.not_logged_in_yet"

log "armbian rootfs ready: $ROOTFS ($(du -sh "$ROOTFS" | cut -f1))"
