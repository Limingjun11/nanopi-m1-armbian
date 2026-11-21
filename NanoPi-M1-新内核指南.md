# NanoPi M1 跑新内核：现状、路线与实操

> 结论先说：官方只停在 4.14，是友善不再维护 H3 这条产品线，**不是 Linux 没驱动**。
> H3（sun8i）是 sunxi 主线支持得最完整的 SoC 之一。今天完全可以在 NanoPi M1 上跑
> 6.18 LTS 主线内核，功能覆盖比官方 4.14 更全。

---

## 1. 我实测到的现状（2026-11）

我下载并解包了 DietPi 目前为 NanoPi M1 提供的最新镜像（2026-10-22 构建），里面的组件是：

| 组件 | 版本 |
| --- | --- |
| U-Boot | 2026.07（Armbian 构建） |
| 内核 | 6.18.54-current-sunxi（主线 LTS） |
| 设备树 | `sun8i-h3-nanopi-m1.dtb` |
| 发行版 | Debian 13 trixie (armhf) |

内核配置里确认打开的驱动（节选，来自镜像内 `/boot/config-6.18.54-current-sunxi`）：

```
CONFIG_DRM_LIMA=m                  # Mali-400 GPU（lima）
CONFIG_VIDEO_SUNXI_CEDRUS=m        # VPU 硬解（cedrus）
CONFIG_VIDEO_SUN6I_CSI=m           # DVP 并口摄像头
CONFIG_VIDEO_OV5640=m
CONFIG_SND_SUN8I_CODEC=y           # H3 模拟音频 codec
CONFIG_SND_SUN8I_CODEC_ANALOG=y
CONFIG_DRM_SUN4I=y                 # 显示 / HDMI
CONFIG_SUN8I_THERMAL=m
CONFIG_CPUFREQ_DT=m
```

镜像还自带一整套 H3 设备树 overlay（`/boot/dtb-6.18.54-current-sunxi/overlay/`）：

```
sun8i-h3-analog-codec.dtbo        sun8i-h3-cir.dtbo
sun8i-h3-tve.dtbo                 sun8i-h3-spdif-out.dtbo
sun8i-h3-i2c0/1/2.dtbo            sun8i-h3-spi-*.dtbo
sun8i-h3-uart1/2/3.dtbo           sun8i-h3-w1-gpio.dtbo
sun8i-h3-usbhost0-3.dtbo          sun8i-h3-cpu-clock-1.2GHz-1.3v.dtbo
```

也就是说：**主线不是"驱动不全"，而是"默认没给你全打开"**，缺的部分基本都能用
overlay 或一行 dts 补上。

---

## 2. 为什么会有"5.x 驱动不全"的印象

- 5.x 时代 H3 确实有几个拖了很久的坑：HDMI 音频、CSI 摄像头、thermal zone、
  模拟 codec，都是 5.x 后期到 6.x 才补齐的。你看到的"不全"多半是那个阶段的结论。
- 友善的 4.14 BSP 本身就是主线 4.14 加板级补丁；他们 wiki 的原话是：
  需要 VPU/GPU 功能只能用 Linux-3.4。**所以官方 4.14 也没有硬解和 GPU 加速**。
- 真正的差距不是"主线缺驱动"，而是"全志 BSP 的 VPU 硬编解码 + Mali 闭源驱动"
  这套私有栈，主线用另一条路（cedrus + lima）替代，功能对得上，但不是同一个实现。

---

## 3. 功能对照表

| 功能 | 官方 3.4 BSP | 官方 4.14 BSP | 主线 6.18（实测镜像） |
| --- | --- | --- | --- |
| 100M 以太网 | ✅ | ✅ | ✅ |
| USB 2.0 ×3 | ✅ | ✅ | ✅ |
| HDMI 1080p 显示 | ✅ | ✅ | ✅ |
| HDMI 音频 | ✅ | ✅ | ✅ |
| 3.5mm 耳机 / 板载麦克风 | ✅ | ✅ | ⚠️ 默认 dts 没开 codec，加 overlay 即可 |
| 红外遥控 | ✅ | ✅ | ✅ |
| GPIO / I2C / SPI / UART / PWM | ✅ | ✅ | ✅ |
| 温度 / 调频 | ✅ | ✅ | ✅（可 overlay 上 1.2/1.368GHz） |
| Mali-400 GPU | ✅ 闭源 | ❌ | ✅ lima + Mesa（GLES2） |
| VPU 视频硬解 | ✅ 全志 BSP | ❌ | ⚠️ cedrus 支持 H.264，需 mpv/ffmpeg 的 v4l2request 路径 |
| VPU 视频硬编 | ✅ | ❌ | ❌ 主线没有编码器 |
| DVP 摄像头 CAM500B | ✅ | ✅ | ✅ sun6i-csi + ov5640（需 media-ctl 配 pipeline） |
| CVBS 输出 | ✅ | ⚠️ | ⚠️ tve overlay，实验性 |
| 板载 Wi-Fi | — | — | —（M1 本来就没有；USB 网卡看芯片） |

一句话：**除了"全志 BSP 的硬编"和"闭源 Mali"，主线全面不差，日常使用更好。**

---

## 4. 路线一：直接烧 DietPi（推荐，半小时内能跑起来）

这是目前**唯一还在持续维护**的 NanoPi M1 发行版镜像（Armbian 官方已把这块板子标为
End of Support，只剩归档）。DietPi 的内核和 U-Boot 来自 Armbian 构建，是纯主线。

1. 下载（按需要选 Debian 版本，Trixie = Debian 13）：

   ```
   https://dietpi.com/downloads/images/DietPi_NanoPiM1-ARMv7-Trixie.img.xz
   https://dietpi.com/downloads/images/DietPi_NanoPiM1-ARMv7-Bookworm.img.xz
   ```

2. 烧卡（Linux 下）：

   ```bash
   xz -dc DietPi_NanoPiM1-ARMv7-Trixie.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
   ```

3. 插卡上电（5V/2A 供电，HDMI + 键盘，或串口 115200 8N1 登录）。
   默认账号 `root` / `dietpi`。

4. 进系统先确认：

   ```bash
   uname -r                 # 6.18.54-current-sunxi
   cat /proc/device-tree/model   # FriendlyArm NanoPi M1
   ```

5. 用 `dietpi-config` 调时区、静态 IP、CPU governor、swap/zram（512MB 内存建议开 zram）。

> 提示：DietPi 的启动脚本是 `/boot/boot.scr`，参数在 `/boot/dietpiEnv.txt`，
> 支持 `overlays=` 机制（第 6 节会用到）。

---

## 5. 路线二：自己搭「主线 U-Boot + 6.18 LTS + Debian armhf」

适合要做产品、要定制内核、或者就是不想用第三方镜像的人。工作量主要在 rootfs，
内核和 U-Boot 部分其实很简单。

### 5.1 准备

```bash
sudo apt install build-essential bison flex swig python3-dev libssl-dev \
                 gcc-arm-linux-gnueabihf device-tree-compiler bc rsync
```

### 5.2 编译 U-Boot（板级配置是现成的）

```bash
git clone --depth 1 -b v2026.07 https://source.denx.de/u-boot/u-boot.git
make -C u-boot CROSS_COMPILE=arm-linux-gnueabihf- nanopi_m1_defconfig
make -C u-boot CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc)
# 产物：u-boot/u-boot-sunxi-with-spl.bin
```

主线的 `nanopi_m1_defconfig` 一直有人维护，DT 就是 `sun8i-h3-nanopi-m1`。

### 5.3 编译内核

```bash
git clone --depth 1 -b v6.18.54 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
# 先按 6.1 节给 dts 打补丁，再：
make -C linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- sunxi_defconfig
make -C linux ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc) zImage modules dtbs
```

要 lima / cedrus / csi，`sunxi_defconfig` 里可能没开，用 `scripts/config` 补：

```bash
scripts/config --module DRM_LIMA --module VIDEO_SUNXI_CEDRUS \
               --module VIDEO_SUN6I_CSI --module VIDEO_OV5640
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- olddefconfig
```

### 5.4 写卡与分区

```bash
# U-Boot SPL 固定在 8KiB 偏移
sudo dd if=u-boot/u-boot-sunxi-with-spl.bin of=/dev/sdX bs=1k seek=8 conv=notrunc

# 第一个分区从 4MiB 开始，ext4，放 /boot + rootfs
sudo parted /dev/sdX -- mklabel msdos mkpart primary ext4 4MiB 100% set 1 boot on
```

### 5.5 rootfs

两种做法：

- **最省事**：用 Debian 官方 armhf 安装镜像装到这张卡上，再用主线 U-Boot 覆盖
  （U-Boot 在 8KiB 偏移，不会破坏分区）；Debian `linux-image-armmp` 自带
  `sun8i-h3-nanopi-m1.dtb`。
- **可定制**：`mmdebstrap --arch=armhf trixie rootfs.tar`（需要 qemu-user-static），
  自己装内核、写 `/boot/extlinux/extlinux.conf`。

自定义启动配置示例（U-Boot distro boot 会读它）：

```
label linux
    kernel /zImage
    devicetree /sun8i-h3-nanopi-m1.dtb
    append root=/dev/mmcblk0p1 rootwait console=ttyS0,115200
```

---

## 6. 两个必须知道的坑

### 6.1 模拟音频默认不出声（3.5mm 耳机 + 板载麦克风）

原因：主线 `sun8i-h3-nanopi-m1.dts` 里**没有打开 codec 节点**。我核对过当前主线的
dts（截至 2026-11 仍是如此），`&codec` 在 SoC 的 `sunxi-h3-h5.dtsi` 里是
`status = "disabled"`，而 M1 的板级 dts 没有去 enable 它；对比橙色派 PC 等同类 H3 板，
它们都有一小段 `&codec { ... }`。

**修法 A：用 DietPi 自带 overlay（不用重编内核）**

编辑 `/boot/dietpiEnv.txt`，加入（若已有 `overlay_prefix` 就不要重复）：

```
overlay_prefix=sun8i-h3
overlays=analog-codec
```

多个 overlay 用逗号分隔，例如顺便超频到 1.2GHz（**必须加散热片**）：

```
overlays=analog-codec,cpu-clock-1.2GHz-1.3v
```

重启后验证：

```bash
dmesg | grep -i -E "codec|sun8i"
aplay -l          # 应出现 sun8i-h3-codec 的 Line Out
alsamixer         # 选对应声卡，调高 Line Out / Mic 音量并取消静音
speaker-test -c 2 -t sine -l 1
```

**修法 B：自己编 dtb 时在 dts 里加**

```dts
&codec {
	allwinner,audio-routing =
		"Line Out", "LINEOUT",
		"MIC1", "Mic",
		"Mic",  "MBIAS";
	status = "okay";
};
```

### 6.2 GPU 与 VPU

- **GPU（lima）**：内核模块 `lima` + Mesa 的 `lima_dri.so`。装 `mesa-utils glmark2-es2`
  后直接 `glmark2-es2` 就能跑 GLES2。512MB 内存下帧率一般，但比官方 4.14 的"完全没 GPU"
  强，比 3.4 的闭源驱动也不差多少（且没有 blob 依赖）。
- **VPU（cedrus）**：只做**解码**，H.264 可用（H3 没有 HEVC 硬解）。用法：
  `mpv --hwdec=v4l2request`，或 ffmpeg 7+ 的 `-hwaccel v4l2request`。
  需要内核 `CONFIG_VIDEO_SUNXI_CEDRUS`，设备节点是 `/dev/video*`（`v4l2-ctl --list-devices`）。
  这条路能省 CPU，但配起来比 BSP 的 `cedrus264` 麻烦，且**没有硬编码**。

---

## 7. 其他实用提示

- **串口**：UART0，115200 8N1，GND/TX/RX 三根线足够，调试必备。
- **供电**：5V/2A，MicroUSB 或排针 5V；供电不足会随机重启/掉卡。
- **SD 卡**：A1/U3、Class10 以上；这块板对卡很挑，杂牌卡容易起不来。
- **512MB 内存**：headless 用 DietPi 很轻松；要跑桌面/编译就开 zram 并接受慢。
- **4 个 USB**：M1 是 3 个 A 口 + 1 个 MicroUSB OTG；OTG 口可做 gadget。
- **官方 4.14 已 EOL**（2024-01 停止维护），新用户态（systemd 等）对老内核越来越吃力，
  不建议新项目再用。

---

## 8. 参考

- 友善官方 Wiki（NanoPi M1）：https://wiki.friendlyelec.com/wiki/index.php/NanoPi_M1/zh
- DietPi 支持列表（含 NanoPi M1 镜像）：https://dietpi.com/docs/hardware/#nanopi-series-friendlyelec
- 主线 M1 设备树：https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/arch/arm/boot/dts/allwinner/sun8i-h3-nanopi-m1.dts
- 主线 U-Boot 板级配置：https://source.denx.de/u-boot/u-boot/-/blob/master/configs/nanopi_m1_defconfig
- Armbian 对该板的支持状态（End of Support）：https://www.armbian.com/nanopi-m1/
- 内核版本与 LTS 状态：https://www.kernel.org/releases.json
