# NanoPi M1 镜像构建项目

把「主线 U-Boot + 主线 LTS 内核 + 根文件系统」装进一张可直接烧录的 SD 卡镜像。

与 [`nanopi-m1-kernel`](../nanopi-m1-kernel) 配套：内核产物直接复用它的 `out/`，
不存在时自动调用它编译（所以第一次构建会顺带把内核编出来）。

## 产物

```
out/nanopi-m1-<ver>.img.xz     可直接 dd / balenaEtcher 烧到 TF 卡
out/nanopi-m1-<ver>.img        未压缩镜像
out/u-boot-sunxi-with-spl.bin  引导
out/manifest.txt               版本 / 大小 / sha256
```

烧写：

```bash
xz -dc out/nanopi-m1-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

首次启动：串口 `115200 8N1` 或 HDMI；root 密码默认 `nanopi`（`ROOT_PASSWORD=` 可改）。

## 用法

```bash
make                  # 缺什么编什么，最后出 .img.xz
make kernel           # 只编内核（调用 ../nanopi-m1-kernel）
make uboot            # 只编 U-Boot
make rootfs           # 只做 rootfs（默认 busybox）
make image            # 用现有 rootfs 组装镜像
make clean            # 删 out/
```

常用变量：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `ROOTFS_KIND` | `busybox` | `busybox`（全源码、无需 root）或 `debian` |
| `KERNEL_VERSION` | `6.18.64` | 需与内核项目一致 |
| `IMG_SIZE` | `512M` | 镜像大小 |
| `ROOT_PASSWORD` | `nanopi` | root 密码 |
| `BB_VERSION` | `1.36.1` | BusyBox 版本 |
| `MIRROR` | aliyun | 仅 Debian rootfs 用 |

## 两种 rootfs

**`busybox`（默认，推荐）**
用同一套交叉工具链从源码编译静态 BusyBox，组装最小系统：init、getty（ttyS0/tty1）、
udhcpc 自动 DHCP、内核模块、extlinux 启动项。整个流程不需要 root，
也不需要包管理器，产物约 1.5MB 用户态。

**`debian`（可选）**
`mmdebstrap` 拉 Debian armhf（systemd + sshd）。这一步需要**本机有 root 或多 uid 映射**
（普通用户直接跑会因为无法 chown 到系统用户而失败；用 `sudo make rootfs-debian`）。

## 镜像布局

```
偏移 8KiB    U-Boot SPL + U-Boot（u-boot-sunxi-with-spl.bin）
4MiB 起      单个 ext4 分区（bootable）
  /boot/zImage
  /boot/sun8i-h3-nanopi-m1.dtb
  /boot/extlinux/extlinux.conf      U-Boot distro boot 读它
  /lib/modules/<ver>/
```

## 为什么不用 root

* `mke2fs -d` 直接从一个目录生成 ext4，不需要 loop 设备；
* `fakeroot` 负责把文件伪造成 root 所有；
* BusyBox 用交叉工具链静态编译，直接装进目录即可。

这样在普通用户账号下就能产出完整镜像，适合 CI 和容器环境。

## 检查镜像

```bash
make test                        # QEMU 里真启动、登录、跑命令（无需硬件）
./scripts/inspect.sh out/nanopi-m1-6.18.64.img
```

`make test` 用 QEMU 的 `orangepi-pc`（同款 H3）直接以 `-kernel` 方式启动，
验证内核、设备树、ext4 rootfs、init、DHCP 是否配套；它不经过 U-Boot 的
bootrom 路径，所以 U-Boot 本身无法在 QEMU 里验证。
