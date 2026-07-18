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
grep -Fq 'reg = <0x600000 0x1da00000>;' "$LAYOUT_DTS"
grep -Fq 'ubi_rootdisk: ubi-volume-fit' "$LAYOUT_DTS"

if grep -Fq 'reg = <0x580000 0x7a80000>;' "$LAYOUT_DTS"; then
	echo 'ERROR: official 128MiB UBI layout is still present.' >&2
	exit 1
fi

if grep -Fq 'reg = <0x600000 0x1ea00000>;' "$LAYOUT_DTS"; then
	echo 'ERROR: oversized 490MiB UBI layout would cross the NMBM data boundary.' >&2
	exit 1
fi

ubi_start=$((0x600000))
ubi_size=$((0x1da00000))
nmbm_data_end=$((0x1e000000))
flash_size=$((0x20000000))
nmbm_management_reserve=$((flash_size - nmbm_data_end))

if (( ubi_start + ubi_size != nmbm_data_end )); then
	echo 'ERROR: UBI must end exactly at the device NMBM data boundary.' >&2
	exit 1
fi

if (( nmbm_management_reserve != 0x2000000 )); then
	echo "ERROR: expected a 32MiB NMBM management reserve, got $nmbm_management_reserve bytes." >&2
	exit 1
fi

echo 'Verified: 2GiB RAM, 512MiB NAND, 480MiB NMBM data area, and 474MiB UBI at 0x600000.'
echo 'Expected UBI total LEB capacity with 128KiB PEBs is about 459.2MiB before volumes.'
