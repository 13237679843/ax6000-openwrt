#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_REPO="https://github.com/immortalwrt/immortalwrt.git"
SOURCE_COMMIT="6d9a475729f233d8d6e2d24027b49d041399610e"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_ROOT/work}"
SOURCE_DIR="$BUILD_ROOT/immortalwrt"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output/$(date -u +%Y%m%d-%H%M%S)}"
JOBS="${JOBS:-$(nproc)}"

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

mkdir -p "$SOURCE_DIR/files/etc"
cp "$PROJECT_ROOT/rootfs-overlay/etc/ax6000-build-info" "$SOURCE_DIR/files/etc/ax6000-build-info"

cd "$SOURCE_DIR"
./scripts/feeds update -a
./scripts/feeds install -a
cp "$PROJECT_ROOT/configs/ax6000-2g-512m.config" .config
make defconfig
make download -j"$JOBS"

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
	\( -name '*xiaomi_redmi-router-ax6000-ubootmod*' \
	-o -name 'config.buildinfo' \
	-o -name 'feeds.buildinfo' \
	-o -name 'version.buildinfo' \
	-o -name '*.manifest' \
	-o -name 'profiles.json' \) \
	-exec cp '{}' "$OUTPUT_DIR/" \;

(
	cd "$OUTPUT_DIR"
	sha256sum ./* > SHA256SUMS
)

echo "Build complete: $OUTPUT_DIR"
