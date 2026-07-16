#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REPO="https://github.com/openwrt/openwrt.git"
SOURCE_COMMIT="f0a60eee2fe051741c643ea6118718aae1ef17fb"
FEEDS_CONFIG="$PROJECT_ROOT/configs/openwrt-25.12.5.feeds.conf"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/work}"
SOURCE_DIR="$BUILD_ROOT/openwrt"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output/$(date -u +%Y%m%d-%H%M%S)}"
JOBS="${JOBS:-$(nproc)}"

require_config_option() {
	local config_file="$1"
	local option="$2"

	if ! grep -Eq "^${option}=(y|m)$" "$config_file"; then
		echo "ERROR: required option is missing from $config_file: $option" >&2
		exit 1
	fi
}

run_make_stage() {
	local target="$1"

	if ! make -j"$JOBS" "$target"; then
		echo "Parallel build failed for $target; retrying serially with verbose output." >&2
		make -j1 V=s "$target"
	fi
}

if [[ -e "$SOURCE_DIR" ]]; then
	echo "ERROR: build source already exists: $SOURCE_DIR" >&2
	echo 'Choose a new BUILD_ROOT so an earlier tree is not overwritten.' >&2
	exit 1
fi

mkdir -p "$BUILD_ROOT" "$OUTPUT_DIR"

git init "$SOURCE_DIR"
git -C "$SOURCE_DIR" remote add origin "$SOURCE_REPO"
git -C "$SOURCE_DIR" fetch --depth=1 origin "$SOURCE_COMMIT"
git -C "$SOURCE_DIR" checkout --detach FETCH_HEAD

git -C "$SOURCE_DIR" apply --check "$PROJECT_ROOT/patches/100-ax6000-2g-512m.patch"
git -C "$SOURCE_DIR" apply "$PROJECT_ROOT/patches/100-ax6000-2g-512m.patch"
"$PROJECT_ROOT/scripts/verify-layout.sh" "$SOURCE_DIR"

mkdir -p "$SOURCE_DIR/files"
cp -a "$PROJECT_ROOT/rootfs-overlay/." "$SOURCE_DIR/files/"
cp "$FEEDS_CONFIG" "$SOURCE_DIR/feeds.conf"

cd "$SOURCE_DIR"
./scripts/feeds update -a
./scripts/feeds install -a
cp "$PROJECT_ROOT/configs/ax6000-2g-512m.config" .config
make defconfig

required_options=(
	CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod
	CONFIG_TARGET_ROOTFS_INITRAMFS
	CONFIG_LUCI_LANG_zh_Hans
	CONFIG_PACKAGE_luci-ssl-openssl
	CONFIG_PACKAGE_luci-i18n-firewall-zh-cn
	CONFIG_PACKAGE_luci-app-package-manager
	CONFIG_PACKAGE_luci-i18n-package-manager-zh-cn
	CONFIG_PACKAGE_luci-theme-argon
	CONFIG_PACKAGE_luci-app-argon-config
	CONFIG_PACKAGE_luci-i18n-argon-config-zh-cn
	CONFIG_PACKAGE_luci-app-ttyd
	CONFIG_PACKAGE_luci-i18n-ttyd-zh-cn
	CONFIG_PACKAGE_luci-app-passwall
	CONFIG_PACKAGE_luci-i18n-passwall-zh-cn
	CONFIG_PACKAGE_luci-app-openclash
	CONFIG_PACKAGE_luci-app-homeproxy
	CONFIG_PACKAGE_luci-i18n-homeproxy-zh-cn
	CONFIG_PACKAGE_tailscale
)

for option in "${required_options[@]}"; do
	require_config_option .config "$option"
done

run_make_stage download

echo 'Preparing the official OpenWrt toolchain and validating the patched device tree.'
run_make_stage tools/install
run_make_stage toolchain/install
run_make_stage target/linux/dtb
"$PROJECT_ROOT/scripts/verify-layout.sh" "$SOURCE_DIR"

if ! make -j"$JOBS"; then
	echo 'Parallel build failed; retrying serially with verbose output.' >&2
	make -j1 V=s
fi

TARGET_DIR="$SOURCE_DIR/bin/targets/mediatek/filogic"
if [[ ! -d "$TARGET_DIR" ]]; then
	echo "ERROR: expected output directory not found: $TARGET_DIR" >&2
	exit 1
fi

find "$TARGET_DIR" -maxdepth 1 -type f \
	\( -name '*xiaomi_redmi-router-ax6000-ubootmod-initramfs-factory.ubi' \
	-o -name '*xiaomi_redmi-router-ax6000-ubootmod-initramfs-recovery.itb' \
	-o -name '*xiaomi_redmi-router-ax6000-ubootmod-squashfs-sysupgrade.itb' \
	-o -name 'config.buildinfo' \
	-o -name 'feeds.buildinfo' \
	-o -name 'version.buildinfo' \
	-o -name '*.manifest' \
	-o -name 'profiles.json' \) \
	-exec cp '{}' "$OUTPUT_DIR/" \;

shopt -s nullglob
initramfs_images=("$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-initramfs-factory.ubi)
sysupgrade_images=("$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-squashfs-sysupgrade.itb)
shopt -u nullglob

if [[ "${#initramfs_images[@]}" -ne 1 ]]; then
	echo "ERROR: expected one initramfs-factory.ubi, found ${#initramfs_images[@]}." >&2
	exit 1
fi

if [[ "${#sysupgrade_images[@]}" -ne 1 ]]; then
	echo "ERROR: expected one squashfs-sysupgrade.itb, found ${#sysupgrade_images[@]}." >&2
	exit 1
fi

(
	cd "$OUTPUT_DIR"
	sha256sum ./* > SHA256SUMS
)

echo "Build complete: $OUTPUT_DIR"
