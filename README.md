# Redmi AX6000 2GB RAM / 512MB NAND 固件构建

本项目用于构建以下硬件和引导布局的固件：

- Redmi AX6000 / MT7986A
- 2GB RAM（系统实测 `MemTotal: 2038132 kB`）
- 512MB SPI-NAND
- 定制多布局 U-Boot，当前布局必须为 `512rom-490m`
- NMBM UBI 分区：起点 `0x600000`，长度 `0x1ea00000`（490MiB）

## 固定源码基线

源码固定为 ImmortalWrt 提交：

`6d9a475729f233d8d6e2d24027b49d041399610e`

它对应原路由器界面显示的：

`ImmortalWrt 24.10-SNAPSHOT r33349-6d9a475729 / Linux 6.6.95`

该提交中的 AX6000 U-Boot layout 已启用 NMBM，并使用 `0x600000 + 0x6e00000` 的 110MiB custom 布局。本项目只进行两项硬件容量修改：

1. RAM：`0x20000000`（512MiB）改为 `0x80000000`（2GiB）。
2. UBI：`0x6e00000`（110MiB）改为 `0x1ea00000`（490MiB）。

不会生成或刷写新的 BL2、FIP、Factory、Bdata 或无线校准数据。

## GitHub Actions 构建

推送到 `main` 分支时会自动开始构建，也可以在 Actions 页面手动运行。

1. 将本目录作为一个 GitHub 仓库上传。
2. 打开仓库的 **Actions** 页面。
3. 选择 **Build Redmi AX6000 2G-512M firmware**。
4. 点击 **Run workflow**。
5. 构建成功后下载 `ax6000-2g-512m-firmware` artifact。

构建通常需要较长时间。工作流固定源码提交，并在编译前自动验证 RAM、NMBM 和 UBI 布局。

## 本地 Linux 构建

需要 Debian/Ubuntu、至少 4GB RAM 和约 30GB 可用磁盘空间：

```sh
chmod +x scripts/build.sh scripts/verify-layout.sh
./scripts/build.sh
```

也可以指定目录和并行数：

```sh
BUILD_ROOT=/path/to/build OUTPUT_DIR=/path/to/output JOBS=4 ./scripts/build.sh
```

## 固件文件与刷写顺序

构建结果中最重要的是：

- `*-initramfs-factory.ubi`：在 U-Boot 网页中首次上传，用于启动临时恢复系统。
- `*-squashfs-sysupgrade.bin`：进入临时系统后，通过 LuCI 或 `sysupgrade` 安装正式系统。

安全顺序：

1. U-Boot 网页中确认当前布局仍为 `512rom-490m`。
2. 上传 `*-initramfs-factory.ubi`，不要在此步骤上传 sysupgrade 文件。
3. 等待路由器启动临时系统，访问 `http://192.168.1.1/`。
4. 在 LuCI 的备份/升级页面上传 `*-squashfs-sysupgrade.bin`。
5. 不保留旧配置，执行升级并等待重启。

不要刷写名称含 `preloader`、`bl31`、`uboot` 或 `fip` 的文件。当前引导器已经正确初始化 2GB RAM 和 512MB NAND。

首次启动后建议检查：

```sh
grep MemTotal /proc/meminfo
cat /proc/mtd
ubinfo -a
```

预期 `MemTotal` 约为 `2038132 kB`，UBI/overlay 可用容量会略小于 490MiB，因为需要扣除坏块、UBI 元数据和固件自身占用。

## 默认软件

基础配置包含 LuCI、HTTPS、中文界面、curl、SFTP、htop 和 nano。代理、Docker、AdGuard Home 等大型软件包应在基础固件成功启动后再加入配置并重新构建。
