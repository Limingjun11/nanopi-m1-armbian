# 可选设备树 overlay

内核里已经编好了这些驱动（模块）：

| 模块 | 配置 |
| --- | --- |
| `ov2640.ko` | `CONFIG_VIDEO_OV2640=m` |
| `fbtft.ko` / `fb_st7735r.ko` | `CONFIG_FB_TFT=m`、`CONFIG_FB_TFT_ST7735R=m` |
| `spidev.ko` | `CONFIG_SPI_SPIDEV=m` |

但**驱动不会自己出现**：设备树里得有对应的节点，模块才会 probe。这里给的是模板，
引脚必须按你的实际接线改。

## 编译

```bash
sudo apt install device-tree-compiler
dtc -@ -I dts -O dtb -o st7735r.dtbo st7735r.dts
dtc -@ -I dts -O dtb -o ov2640.dtbo ov2640.dts
```

把 `.dtbo` 放到板子的 `/boot/overlays/`，然后在 `/boot/extlinux/extlinux.conf`
的 `label` 段里加一行（U-Boot 的 extlinux 支持）：

```
    fdtoverlays /boot/overlays/st7735r.dtbo
```

重启后：

```bash
dmesg | grep -iE "fbtft|st7735|ov2640|csi"
ls /dev/fb* /dev/video*
```

## 需要你确认的接线

- **ST7735**：接的是 SPI0（PC0–PC3）还是 SPI1（PA13–PA16）？CS / DC / RESET 分别接哪个 GPIO？
- **OV2640**：是 FriendlyElec 的 24pin DVP 摄像头，还是自己接的模块？SCCB 是否接在 PE12/PE13（i2c2）？

模板里的 `TODO` 就是这些位置。
