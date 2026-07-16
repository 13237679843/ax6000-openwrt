#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-.}"
COMMON_DTS="$SOURCE_DIR/target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dtsi"
LAYOUT_DTS="$SOURCE_DIR/target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-ubootmod.dts"

grep -Fq 'reg = <0 0x40000000 0 0x80000000>;' "$COMMON_DTS"
grep -Fq 'mediatek,nmbm;' "$LAYOUT_DTS"
grep -Fq 'reg = <0x600000 0x1ea00000>;' "$LAYOUT_DTS"

if grep -Fq 'reg = <0x600000 0x6e00000>;' "$LAYOUT_DTS"; then
	echo 'ERROR: 110MiB layout is still present.' >&2
	exit 1
fi

echo 'Verified: 2GiB RAM, NMBM enabled, 490MiB UBI at 0x600000.'
