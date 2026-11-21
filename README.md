# NanoPi M1 主线内核 + 镜像构建

为 FriendlyARM **NanoPi M1**（Allwinner H3）准备的两个独立项目：

| 项目 | 作用 | 产物 |
| --- | --- | --- |
| [`nanopi-m1-kernel`](nanopi-m1-kernel) | 编译主线 LTS 内核（默认 6.18.64，即 "5.x LTS 及以上"） | `zImage`、`sun8i-h3-nanopi-m1.dtb`、内核模块、配置与符号表 |
| [`nanopi-m1-image`](nanopi-m1-image) | 在上一项基础上编 U-Boot、做 Debian armhf rootfs、组装可烧录镜像 | `nanopi-m1-<ver>.img.xz` |

两个项目共享 `../.cache` 中的下载缓存与交叉工具链，互不重复下载。

## CI（GitHub Actions）

`.github/workflows/` 下两个工作流，推到 GitHub 即可用：

| 工作流 | 触发 | 做什么 | 产物 |
| --- | --- | --- | --- |
| `kernel.yml` | 改 `nanopi-m1-kernel/**`、手动 | 只编内核（可输入版本号） | 内核 tar.gz、zImage、dtb |
| `image.yml` | push/PR、**每周一 02:00**、打 `v*` tag、手动 | 编 U-Boot + 内核 + rootfs + 镜像，并在 QEMU 里启动验证 | `.img.xz`、U-Boot、manifest；打 tag 时自动发 Release |

手动运行时可指定 `kernel_version`（如 `5.15.225`）和 `img_size`（`512M`/`1G`/`2G`）。
下载缓存通过 `actions/cache` 复用，重复构建只需重编内核。

### 定时构建

`image.yml` 每周一 02:00（北京时间）自动跑一次，产物在 Actions 该次 run 的
Artifacts 里保留 30 天；镜像和内核 tar.gz 一起产出。cron 用的是 UTC
（`0 18 * * 0` = 周日 18:00 UTC = 周一 02:00 CST），改时间就改这一行。

注意两点：

* GitHub 对 **60 天无提交** 的仓库会自动暂停定时任务，有新的 push 后恢复；
* 定时任务只在默认分支上跑，且高峰期可能延迟几分钟到几十分钟。

每次定时构建会发布一个 **prerelease**，tag 形如 `weekly-20261123`，附带
`.img.xz`、U-Boot、内核 tar.gz 和 manifest；只保留最近 8 个 weekly 发布，旧的自动删除。
手动 Run workflow 也会走同样的 weekly 发布流程（方便先验证）。

本地推到 GitHub：

```bash
git init && git add . && git commit -m "NanoPi M1 mainline kernel + image"
git branch -M main
git remote add origin git@github.com:<you>/<repo>.git
git push -u origin main
git tag v6.18.64 && git push origin v6.18.64   # 触发 Release
```

## 快速开始

```bash
cd nanopi-m1-kernel && make -j$(nproc)     # 编内核
cd ../nanopi-m1-image && make              # 出镜像（会自动补编缺的部分）
```

烧写：

```bash
xz -dc out/nanopi-m1-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

## 本次构建结果（2026-11-21）

| 产物 | 大小 | 说明 |
| --- | --- | --- |
| `nanopi-m1-kernel/out/zImage` | 5.9 MB | Linux 6.18.64（`sun8i-h3-nanopi-m1`） |
| `nanopi-m1-kernel/out/nanopi-m1-kernel-6.18.64.tar.gz` | 7.5 MB | 内核 + dtb + 模块 |
| `nanopi-m1-image/out/u-boot-sunxi-with-spl.bin` | 540 KB | U-Boot 2026.07 |
| `nanopi-m1-image/out/nanopi-m1-6.18.64.img.xz` | 7.6 MB | 512 MB SD 卡镜像 |

QEMU（同款 H3 的 `orangepi-pc` 机型）实测启动结果：

```
uname -r                      -> 6.18.64
/proc/device-tree/model       -> FriendlyArm NanoPi M1
ls /boot                      -> extlinux  sun8i-h3-nanopi-m1.dtb  zImage
eth0                          -> 10.0.2.15/24 (DHCP)
ALSA                          -> #0: H3 Audio Codec   (dts 补丁生效)
```

## 设计要点

* **不需要 root**：内核和 U-Boot 用交叉工具链正常编译；rootfs 用
  `mmdebstrap --mode=proot` + `qemu-arm` 在用户态构建；镜像用
  `mke2fs -d` + `fakeroot` 直接从目录生成，不需要 loop 设备。
* **不需要友善 BSP**：U-Boot 用上游 `nanopi_m1_defconfig`，内核用
  `sunxi_defconfig` + 一份带校验的 fragment，设备树只加了一个补丁
  （打开 M1 主线 dts 漏掉的模拟音频 codec）。
* **国内网络可用**：内核默认从 `mirrors.163.com` 拉，rootfs 走
  `mirrors.aliyun.com`，U-Boot 走 GitHub 代理，都可用环境变量替换。

## 已验证的能力（内核配置层面）

`CONFIG_DRM_LIMA`（Mali-400 GPU）、`CONFIG_VIDEO_SUNXI_CEDRUS`（VPU 硬解）、
`CONFIG_VIDEO_SUN6I_CSI` + `CONFIG_VIDEO_OV5640`（DVP 摄像头）、
`CONFIG_SND_SUN8I_CODEC`（3.5mm + 板载麦）、`CONFIG_ZRAM`、
`CONFIG_OVERLAY_FS`/`CONFIG_VETH`/`CONFIG_NF_NAT`（容器）、常见 USB 无线网卡。

## 镜像默认值

* BusyBox 1.36.1（静态，源码编译），root 密码 `nanopi`（`ROOT_PASSWORD=` 可改）
* 单 ext4 分区，U-Boot 位于 8KiB，`/boot/extlinux/extlinux.conf` 引导
* eth0 用 udhcpc 自动 DHCP
* 串口 `ttyS0 115200 8N1`，HDMI 控制台 `tty1`
* Debian rootfs 作为可选路径保留（`make ROOTFS_KIND=debian rootfs`，需要 root）
