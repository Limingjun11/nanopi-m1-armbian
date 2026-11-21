# NanoPi M1 内核编译项目

为 FriendlyARM **NanoPi M1**（Allwinner H3 / sun8i）编译**主线 LTS 内核**（默认 6.18，
即 "5.x LTS 及以上"），产物可直接用于自制镜像或替换现有系统的内核。

## 为什么不用友善的 4.14 BSP

友善的 4.14 是主线 4.14 + 板级补丁，早已 EOL；H3 在主线里支持非常完整。
本项目在 `sunxi_defconfig` 基础上补齐 lima（GPU）、cedrus（VPU 硬解）、
sun6i-csi（DVP 摄像头）、zram、overlayfs、常见 USB 网卡等驱动，
并用一个 dts 补丁打开 M1 主线设备树里**漏掉的模拟音频 codec**（3.5mm 耳机 + 板载麦）。

## 用法

```bash
make                 # 编译，产物在 out/
make KERNEL_VERSION=5.15.225   # 指定 5.x LTS 也可以
make clean           # 删 out/ 与解压出的源码
make distclean       # 连下载缓存一起删
```

产物：

```
out/zImage                              内核
out/dtb/sun8i-h3-nanopi-m1.dtb          设备树
out/modules/lib/modules/<ver>/          内核模块
out/config-<ver>  out/System.map-<ver>  配置与符号表
out/nanopi-m1-kernel-<ver>.tar.gz       打包（zImage + dtb + modules）
```

## 依赖

* 任一 Linux x86_64 主机，`make` `gcc` `bc` `flex` `bison` `libssl-dev` `xz`
* 交叉编译器：脚本按以下顺序自动解决，无需手工安装
  1. 已存在的 `arm-linux-gnueabihf-gcc`
  2. Ubuntu/Debian：`apt-get download` 交叉工具链并解包到 `.cache/`（国内快）
  3. Bootlin 官方工具链（其它发行版）

## 网络

默认从 `cdn.kernel.org` 下载内核源码。国内建议：

```bash
make KERNEL_MIRROR=https://mirrors.163.com/kernel/v6.x
```

可用镜像：`https://mirrors.163.com/kernel/v6.x`、`https://mirrors.aliyun.com/linux-kernel/v6.x`。

## 目录

```
configs/kernel.fragment   在 sunxi_defconfig 之上叠加的配置
patches/                  设备树补丁（模拟音频）
scripts/toolchain.sh      交叉工具链自动准备
scripts/build.sh          下载 -> 配置 -> 编译 -> 打包
```
