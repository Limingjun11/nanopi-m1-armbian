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

## 三种 rootfs

**`busybox`（默认，推荐）**
用同一套交叉工具链从源码编译静态 BusyBox，组装最小系统：init、getty（ttyS0/tty1）、
udhcpc 自动 DHCP、内核模块、extlinux 启动项。整个流程不需要 root，
也不需要包管理器，产物约 1.5MB 用户态。

**`debian` / `ubuntu`（可选，需要 root）**
`mmdebstrap` 拉 Debian trixie 或 Ubuntu noble 的 armhf 最小系统（systemd、sshd、
systemd-networkd），装进 `/boot`、`/lib/modules` 和上面的启动配置。

```bash
sudo make rootfs-debian      # Debian trixie, 镜像约 2G / 压缩后 ~300MB
sudo make rootfs-ubuntu      # Ubuntu noble, 同上
sudo make DISTRO=debian image
```

本地需要 root + `qemu-user` 的 armhf binfmt（`update-binfmts --enable qemu-arm`）；
GitHub runner 上 `image-distro.yml` 已经处理好了。

**`armbian`（归档用户态 + 我们的内核）**
Armbian 的构建框架里 `nanopim1` 已是 `eos`，无法重建；但归档里还留着最后一个官方镜像
`21.08.1`（Debian bullseye，kernel 5.10.60）。这个变体把它的 rootfs 解出来，
保留 armbian-config / armbian-firstrun 等，再换成我们的 6.18 内核、模块、dtb 和
U-Boot，启动方式改为 extlinux。

```bash
make rootfs-armbian          # 下载 348MB 镜像并解包（不需要 root）
make DISTRO=armbian image
```

首次启动向导（armbian-firstrun）会被禁用，root 密码固定为 `nanopi`，eth0 走 DHCP。

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
