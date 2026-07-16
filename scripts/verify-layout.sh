#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-.}"
COMMON_DTS="$SOURCE_DIR/target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000.dtsi"
LAYOUT_DTS="$SOURCE_DIR/target/linux/mediatek/dts/mt7986a-xiaomi-redmi-router-ax6000-ubootmod.dts"

grep -Fq 'reg = <0 0x40000000 0 0x80000000>;' "$COMMON_DTS"
grep -Fq 'mediatek,nmbm;' "$LAYOUT_DTS"
grep -Fq 'mediatek,bmt-max-ratio = <1>;' "$LAYOUT_DTS"
grep -Fq 'mediatek,bmt-max-reserved-blocks = <64>;' "$LAYOUT_DTS"
grep -Fq 'reg = <0x580000 0x40000>;' "$LAYOUT_DTS"
grep -Fq 'reg = <0x5c0000 0x40000>;' "$LAYOUT_DTS"
grep -Fq 'compatible = "linux,ubi";' "$LAYOUT_DTS"
grep -Fq 'reg = <0x600000 0x1ea00000>;' "$LAYOUT_DTS"
grep -Fq 'ubi_rootdisk: ubi-volume-fit' "$LAYOUT_DTS"

if grep -Fq 'reg = <0x580000 0x7a80000>;' "$LAYOUT_DTS"; then
	echo 'ERROR: official 128MiB UBI layout is still present.' >&2
	exit 1
fi

echo 'Verified: official OpenWrt profile, 2GiB RAM, NMBM, and 490MiB UBI at 0x600000.'
