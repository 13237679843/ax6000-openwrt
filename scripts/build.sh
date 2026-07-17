#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REPO="https://github.com/openwrt/openwrt.git"
SOURCE_COMMIT="f0a60eee2fe051741c643ea6118718aae1ef17fb"
FEEDS_CONFIG="$PROJECT_ROOT/configs/openwrt-25.12.5.feeds.conf"
INSTALLER_CONFIG="$PROJECT_ROOT/configs/ax6000-2g-512m-installer.config"
FULL_CONFIG="$PROJECT_ROOT/configs/ax6000-2g-512m.config"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/work}"
SOURCE_DIR="$BUILD_ROOT/openwrt"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output/$(date -u +%Y%m%d-%H%M%S)}"
JOBS="${JOBS:-$(nproc)}"
MAX_INSTALLER_BYTES="${MAX_INSTALLER_BYTES:-25165824}"

require_config_option() {
	local config_file="$1"
	local option="$2"

	if ! grep -Eq "^${option}=y$" "$config_file"; then
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

fetch_package() {
	local repo="$1"
	local commit="$2"
	local destination="$3"

	git init "$destination"
	git -C "$destination" remote add origin "$repo"
	git -C "$destination" fetch --depth=1 origin "$commit"
	git -C "$destination" checkout --detach FETCH_HEAD
}

copy_single_match() {
	local search_dir="$1"
	local filename_pattern="$2"
	local destination="$3"
	local description="$4"
	local matches=()

	shopt -s nullglob
	matches=("$search_dir"/$filename_pattern)
	shopt -u nullglob

	if [[ "${#matches[@]}" -ne 1 ]]; then
		echo "ERROR: expected one $description, found ${#matches[@]}." >&2
		exit 1
	fi

	cp "${matches[0]}" "$destination"
}

build_firmware() {
	if ! make -j"$JOBS"; then
		echo 'Parallel build failed; retrying serially with verbose output.' >&2
		make -j1 V=s
	fi
}

if [[ -e "$SOURCE_DIR" ]]; then
	echo "ERROR: build source already exists: $SOURCE_DIR" >&2
	echo 'Choose a new BUILD_ROOT so an earlier tree is not overwritten.' >&2
	exit 1
fi

if [[ -e "$OUTPUT_DIR" ]]; then
	if [[ ! -d "$OUTPUT_DIR" ]] \
		|| [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
		echo "ERROR: output path must be a new or empty directory: $OUTPUT_DIR" >&2
		exit 1
	fi
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

mkdir -p package/custom
fetch_package \
	"https://github.com/immortalwrt/homeproxy.git" \
	"7826c263609cf413c355eea6fd8cc1255b85f5c7" \
	"package/custom/luci-app-homeproxy"
fetch_package \
	"https://github.com/jerrykuku/luci-theme-argon.git" \
	"f92905520f8fcb60b7f0c4776e9ff8dd77a6d49f" \
	"package/custom/luci-theme-argon"
fetch_package \
	"https://github.com/jerrykuku/luci-app-argon-config.git" \
	"3e099a37c3f71d0de677f1b6b0f4bffd57d91dac" \
	"package/custom/luci-app-argon-config"

echo 'Building the small U-Boot installer image.'
cp "$INSTALLER_CONFIG" .config
make defconfig

installer_required_options=(
	CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod
	CONFIG_TARGET_ROOTFS_SQUASHFS
	CONFIG_TARGET_ROOTFS_INITRAMFS
	CONFIG_PACKAGE_dropbear
	CONFIG_PACKAGE_openssh-sftp-server
)

for option in "${installer_required_options[@]}"; do
	require_config_option .config "$option"
done

installer_forbidden_options=(
	CONFIG_PACKAGE_luci-app-passwall
	CONFIG_PACKAGE_luci-app-openclash
	CONFIG_PACKAGE_luci-app-homeproxy
	CONFIG_PACKAGE_tailscale
)

for option in "${installer_forbidden_options[@]}"; do
	if grep -Eq "^${option}=(y|m)$" .config; then
		echo "ERROR: heavy package must not be included in installer: $option" >&2
		exit 1
	fi
done

run_make_stage download

echo 'Preparing the official OpenWrt toolchain and validating the patched device tree.'
run_make_stage tools/install
run_make_stage toolchain/install
run_make_stage target/linux/dtb
"$PROJECT_ROOT/scripts/verify-layout.sh" "$SOURCE_DIR"

build_firmware

TARGET_DIR="$SOURCE_DIR/bin/targets/mediatek/filogic"
if [[ ! -d "$TARGET_DIR" ]]; then
	echo "ERROR: expected output directory not found: $TARGET_DIR" >&2
	exit 1
fi

copy_single_match \
	"$TARGET_DIR" \
	"*xiaomi_redmi-router-ax6000-ubootmod-initramfs-factory.ubi" \
	"$OUTPUT_DIR/" \
	"installer initramfs-factory.ubi"
copy_single_match \
	"$TARGET_DIR" \
	"*xiaomi_redmi-router-ax6000-ubootmod-initramfs-recovery.itb" \
	"$OUTPUT_DIR/" \
	"installer initramfs-recovery.itb"
copy_single_match \
	"$TARGET_DIR" \
	"*xiaomi_redmi-router-ax6000-ubootmod.manifest" \
	"$OUTPUT_DIR/installer.manifest" \
	"installer manifest"

cp "$TARGET_DIR/config.buildinfo" "$OUTPUT_DIR/installer.config.buildinfo"
cp "$TARGET_DIR/feeds.buildinfo" "$OUTPUT_DIR/installer.feeds.buildinfo"
cp "$TARGET_DIR/version.buildinfo" "$OUTPUT_DIR/installer.version.buildinfo"

shopt -s nullglob
installer_images=(
	"$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-initramfs-factory.ubi
	"$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-initramfs-recovery.itb
)
shopt -u nullglob

for image in "${installer_images[@]}"; do
	image_size="$(stat -c '%s' "$image")"
	if (( image_size > MAX_INSTALLER_BYTES )); then
		echo "ERROR: installer image exceeds $MAX_INSTALLER_BYTES bytes: $image ($image_size bytes)" >&2
		exit 1
	fi
done

if grep -Eq '^(luci-app-(passwall|openclash|homeproxy)|tailscale) ' \
	"$OUTPUT_DIR/installer.manifest"; then
	echo 'ERROR: installer manifest contains a heavy runtime package.' >&2
	exit 1
fi

for package in dropbear openssh-sftp-server; do
	if ! grep -Eq "^${package} " "$OUTPUT_DIR/installer.manifest"; then
		echo "ERROR: installer manifest is missing $package." >&2
		exit 1
	fi
done

# The installer build also emits a minimal sysupgrade image. Remove it and
# its metadata so the second build cannot accidentally publish stale output.
rm -f \
	"$TARGET_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-squashfs-sysupgrade.itb \
	"$TARGET_DIR"/*xiaomi_redmi-router-ax6000-ubootmod.manifest \
	"$TARGET_DIR/config.buildinfo" \
	"$TARGET_DIR/profiles.json"

echo 'Building the permanent full-featured sysupgrade image.'
cp "$FULL_CONFIG" .config
make defconfig

if grep -Eq '^CONFIG_TARGET_ROOTFS_INITRAMFS=(y|m)$' .config; then
	echo 'ERROR: the full firmware config must not build another initramfs.' >&2
	exit 1
fi

full_required_options=(
	CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_redmi-router-ax6000-ubootmod
	CONFIG_TARGET_ROOTFS_SQUASHFS
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

for option in "${full_required_options[@]}"; do
	require_config_option .config "$option"
done

run_make_stage download
build_firmware

find "$TARGET_DIR" -maxdepth 1 -type f \
	\( -name '*xiaomi_redmi-router-ax6000-ubootmod-squashfs-sysupgrade.itb' \
	-o -name 'config.buildinfo' \
	-o -name 'feeds.buildinfo' \
	-o -name 'version.buildinfo' \
	-o -name '*.manifest' \
	-o -name 'profiles.json' \) \
	-exec cp '{}' "$OUTPUT_DIR/" \;

shopt -s nullglob
initramfs_images=("$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-initramfs-factory.ubi)
recovery_images=("$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-initramfs-recovery.itb)
sysupgrade_images=("$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod-squashfs-sysupgrade.itb)
shopt -u nullglob

if [[ "${#initramfs_images[@]}" -ne 1 ]]; then
	echo "ERROR: expected one initramfs-factory.ubi, found ${#initramfs_images[@]}." >&2
	exit 1
fi

if [[ "${#recovery_images[@]}" -ne 1 ]]; then
	echo "ERROR: expected one initramfs-recovery.itb, found ${#recovery_images[@]}." >&2
	exit 1
fi

if [[ "${#sysupgrade_images[@]}" -ne 1 ]]; then
	echo "ERROR: expected one squashfs-sysupgrade.itb, found ${#sysupgrade_images[@]}." >&2
	exit 1
fi

shopt -s nullglob
full_manifest=("$OUTPUT_DIR"/*xiaomi_redmi-router-ax6000-ubootmod.manifest)
shopt -u nullglob
if [[ "${#full_manifest[@]}" -ne 1 ]]; then
	echo "ERROR: expected one full firmware manifest, found ${#full_manifest[@]}." >&2
	exit 1
fi

for package in \
	luci-app-firewall \
	luci-app-argon-config \
	luci-app-homeproxy \
	luci-app-openclash \
	luci-app-package-manager \
	luci-app-passwall \
	luci-app-ttyd \
	luci-i18n-argon-config-zh-cn \
	luci-i18n-firewall-zh-cn \
	luci-i18n-homeproxy-zh-cn \
	luci-i18n-package-manager-zh-cn \
	luci-i18n-passwall-zh-cn \
	luci-i18n-ttyd-zh-cn \
	luci-ssl-openssl \
	luci-theme-argon \
	tailscale; do
	if ! grep -Eq "^${package} " "${full_manifest[0]}"; then
		echo "ERROR: full firmware manifest is missing $package." >&2
		exit 1
	fi
done

cat > "$OUTPUT_DIR/BUILD-SUMMARY.txt" <<EOF
Device: Xiaomi Redmi Router AX6000 (OpenWrt U-Boot layout)
Hardware: 2GiB RAM / 512MiB SPI-NAND
U-Boot layout: NMBM 512rom-490m
Default LAN IP: 192.168.6.1
Source: official OpenWrt 25.12.5
Source commit: $SOURCE_COMMIT
Installer: minimal initramfs with SSH/SFTP only
Permanent firmware: full squashfs sysupgrade with LuCI and requested packages
Installer size limit: $MAX_INSTALLER_BYTES bytes
Factory installer size: $(stat -c '%s' "${initramfs_images[0]}") bytes
Recovery image size: $(stat -c '%s' "${recovery_images[0]}") bytes
Full sysupgrade size: $(stat -c '%s' "${sysupgrade_images[0]}") bytes
EOF

cat > "$OUTPUT_DIR/FLASH-INSTRUCTIONS.txt" <<'EOF'
1. In the U-Boot web page, select only the 512rom-490m layout.
2. Upload *-initramfs-factory.ubi. Do not upload recovery.itb or sysupgrade.itb there.
3. After the temporary installer boots, connect to 192.168.6.1.
   If DHCP is unavailable, set the PC to 192.168.6.2/24.
4. Log in with: ssh root@192.168.6.1
5. Verify before permanent installation:
     grep MemTotal /proc/meminfo
     dmesg | grep -Ei 'spi-nand|nmbm'
     cat /proc/mtd
     ubinfo -a
6. Copy the full image:
     scp openwrt-*-squashfs-sysupgrade.itb root@192.168.6.1:/tmp/firmware.itb
7. Install without preserving old settings:
     sysupgrade -n /tmp/firmware.itb
8. The permanent system also uses 192.168.6.1.
EOF

rm -f "$OUTPUT_DIR/SHA256SUMS"
(
	cd "$OUTPUT_DIR"
	sha256sum ./* > SHA256SUMS
)

echo "Build complete: $OUTPUT_DIR"
