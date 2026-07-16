# Redmi AX6000 2GB RAM / 512MB NAND 官方 OpenWrt 固件

本项目为已经升级到 2GiB RAM、512MiB SPI-NAND，并使用自定义 U-Boot
`512rom-490m` 布局的 Redmi AX6000 构建固件。

## 固定版本

- 官方源码：`openwrt/openwrt`
- 发行版：OpenWrt 25.12.5
- 源码提交：`f0a60eee2fe051741c643ea6118718aae1ef17fb`
- 目标：`mediatek/filogic`
- 设备：`xiaomi_redmi-router-ax6000-ubootmod`

官方 feeds 和所有第三方插件均固定到明确提交，具体版本见
[`configs/openwrt-25.12.5.feeds.conf`](configs/openwrt-25.12.5.feeds.conf)。

## 硬件布局修改

项目只修改设备树中的硬件容量描述：

1. RAM 从 `0x20000000`（512MiB）改为 `0x80000000`（2GiB）。
2. 为 SPI-NAND 启用 NMBM，保留 `crash` 和 `crash_log`。
3. UBI 使用 `0x600000 + 0x1ea00000`，对应 U-Boot 的 `512rom-490m` 布局。

不会生成或发布 BL2、FIP、U-Boot、Factory、Bdata 或无线校准分区镜像。

## 预装软件

- LuCI HTTPS（OpenSSL）和简体中文界面
- 防火墙中文翻译
- 官方 LuCI 软件包管理器及中文翻译
- Argon 主题、Argon 设置及中文翻译
- ttyd 网页终端及中文翻译
- PassWall、中文翻译、Sing-box、Xray 和 nftables 透明代理支持
- OpenClash
- HomeProxy 及中文翻译
- Tailscale
- curl、SFTP、htop、nano

OpenWrt 25.12 使用 `apk` 代替 `opkg`，因此旧包名
`luci-i18n-opkg-zh-cn` 替换为官方等价包
`luci-i18n-package-manager-zh-cn`。

OpenClash、PassWall、HomeProxy 和 Argon 是第三方项目，不属于 OpenWrt 官方软件包；
系统核心、内核和官方 feeds 均来自 OpenWrt 官方固定版本。

## GitHub Actions 构建

推送到 `main` 或 `agent/ax6000-2g-512m-build` 会自动构建。也可以在
Actions 页面手动运行 `Build official OpenWrt for Redmi AX6000 2G-512M`。

成功后下载 artifact：

`openwrt-25.12.5-ax6000-2g-512m-firmware`

## 本地 Linux 构建

建议使用 Ubuntu 24.04、至少 8GB RAM 和 50GB 可用磁盘空间：

```sh
chmod +x scripts/build.sh scripts/verify-layout.sh
./scripts/build.sh
```

也可以指定目录和并行数：

```sh
BUILD_ROOT=/path/to/build OUTPUT_DIR=/path/to/output JOBS=4 ./scripts/build.sh
```

## 固件文件和安全刷写顺序

最重要的两个文件：

- `*-initramfs-factory.ubi`：在 U-Boot 网页中首次上传，仅用于临时启动和验证。
- `*-squashfs-sysupgrade.itb`：临时系统验证通过后用于安装正式系统。

安全顺序：

1. 在 U-Boot 网页确认布局为 `512rom-490m`。
2. 上传 `*-initramfs-factory.ubi`，不要先上传 sysupgrade 文件。
3. 临时系统启动后通过 SSH 检查：

   ```sh
   grep MemTotal /proc/meminfo
   dmesg | grep -Ei 'spi-nand|nmbm'
   cat /proc/mtd
   ubinfo -a
   ```

4. 只有确认约 2GB RAM、512MiB NAND、NMBM 和接近 490MiB 的 UBI 后，
   才上传 `*-squashfs-sysupgrade.itb`。
5. 首次安装不要保留旧配置。

不要刷写名称包含 `preloader`、`bl31`、`uboot` 或 `fip` 的文件。本项目的
artifact 不会包含这些危险文件。
