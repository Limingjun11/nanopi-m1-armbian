#!/usr/bin/env python3
"""Boot the built image in QEMU (Allwinner H3 "orangepi-pc" machine) and log in.

This is not a substitute for real hardware (no HDMI, no real PHY), but it
verifies that U-Boot's payload layout, the kernel, the DT and the rootfs all
fit together: the kernel mounts /dev/mmcblk0p1 and BusyBox init starts.

  ./scripts/qemu-boot-test.py out/nanopi-m1-6.18.64.img
"""

import os
import pty
import re
import select
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
ROOT = os.path.dirname(PROJECT)

IMAGE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(PROJECT, "out", "nanopi-m1-6.18.64.img")
KERNEL = os.path.join(ROOT, "nanopi-m1-kernel", "out", "zImage")
DTB = os.path.join(ROOT, "nanopi-m1-kernel", "out", "dtb", "sun8i-h3-nanopi-m1.dtb")
PASSWORD = os.environ.get("ROOT_PASSWORD", "nanopi")


def main():
    for f in (IMAGE, KERNEL, DTB):
        if not os.path.exists(f):
            sys.exit(f"missing {f}")

    cmd = [
        "qemu-system-arm", "-M", "orangepi-pc", "-m", "1024", "-smp", "4",
        "-kernel", KERNEL, "-dtb", DTB,
        "-drive", f"file={IMAGE},format=raw,if=sd",
        "-append", "root=/dev/mmcblk0p1 rootwait rw console=ttyS0,115200",
        "-nographic", "-no-reboot",
    ]
    master, slave = pty.openpty()
    proc = subprocess.Popen(cmd, stdin=slave, stdout=slave, stderr=slave, close_fds=True)
    os.close(slave)

    buf = b""

    def drain(seconds):
        nonlocal buf
        end = time.time() + seconds
        while time.time() < end:
            r, _, _ = select.select([master], [], [], 0.2)
            if master in r:
                try:
                    data = os.read(master, 4096)
                except OSError:
                    return
                if not data:
                    return
                buf += data

    BOOT_TIMEOUT = int(os.environ.get("BOOT_TIMEOUT", "90"))

    def read_until(pattern, timeout=60):
        nonlocal buf
        end = time.time() + timeout
        rx = re.compile(pattern)
        while time.time() < end:
            r, _, _ = select.select([master], [], [], 0.2)
            if master in r:
                try:
                    data = os.read(master, 4096)
                except OSError:
                    return False
                if not data:
                    return False
                buf += data
                if rx.search(buf.decode(errors="replace")):
                    return True
        return False

    try:
        if not read_until(r"login:", BOOT_TIMEOUT):
            print("FAIL: no login prompt")
            print(buf.decode(errors="replace")[-3000:])
            return 1
        os.write(master, b"root\n")
        read_until(r"Password:", 10)
        os.write(master, (PASSWORD + "\n").encode())
        if not read_until(r"# ", 15):
            print("FAIL: login failed")
            print(buf.decode(errors="replace")[-2000:])
            return 1
        print("OK: booted, logged in")

        for c in ("uname -r", "cat /proc/device-tree/model; echo", "ls /boot",
                  "cat /sys/class/thermal/thermal_zone0/temp", "ip -o addr show eth0"):
            os.write(master, (c + "\n").encode())
            drain(2.5)
        drain(1.5)
        out = buf.decode(errors="replace")
        start = out.rfind("login[")
        print("-" * 60)
        print(out[max(0, start):][-1800:])
        return 0
    finally:
        proc.kill()
        try:
            os.close(master)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
