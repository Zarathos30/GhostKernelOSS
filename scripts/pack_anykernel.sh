#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 GhostKernelOSS
#
# GhostKernelOSS - AnyKernel3 packaging for POCO F7 (onyx)
#
# Packs the built kernel into a flashable AnyKernel3 zip:
#   Image         -> boot.img kernel (header v4; onyx boot.img has NO
#                    ramdisk - it lives in init_boot.img, dtb + vendor
#                    modules live in vendor_boot.img, so boot gets only
#                    the kernel and everything else stays stock)
#   dtb.img       -> tuna.dtb + tuna7.dtb [if built]; re-appended by
#                    anykernel.sh only if the stock kernel area contains
#                    an appended dtb (Image-dtb style)
#
# NOTE: no modules are staged into a ramdisk anymore: on onyx there is no
# boot ramdisk, and the stock modules in vendor_boot (same config, vermagic
# CRC ignores the version part) keep loading on the GhostKernelOSS kernel.
#
# Required environment:
#   OUT_DIR     build output dir (must contain build.env from build_kernel.sh)
#   AK3_DIR     AnyKernel3 template dir (default: this repo's AnyKernel3/)
#   ZIP_SUFFIX  extra suffix for the zip name (optional)

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$OUT_DIR/build.env" ] || { echo "ERROR: $OUT_DIR/build.env not found. Run build_kernel.sh first." >&2; exit 1; }
. "$OUT_DIR/build.env"

AK3_DIR=${AK3_DIR:-"$ROOT_DIR/AnyKernel3"}
ZIP_SUFFIX=${ZIP_SUFFIX:-}

[ -f "$IMAGE" ] || { echo "ERROR: kernel Image not found: $IMAGE" >&2; exit 1; }

STAGING_DIR="$OUT_DIR/ak3-staging"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -r "$AK3_DIR"/. "$STAGING_DIR"/

echo "==> Packaging kernel Image"
cp "$IMAGE" "$STAGING_DIR/Image"

if [ "${HAS_DTB:-0}" = "1" ]; then
  echo "==> Building dtb.img (tuna base dtbs)"
  rm -f "$STAGING_DIR/dtb.img"
  for dtb in "$DTB_TUNA" "$DTB_TUNA7"; do
    if [ -f "$dtb" ]; then
      cat "$dtb" >> "$STAGING_DIR/dtb.img"
      echo "  + $(basename "$dtb")"
    fi
  done
else
  echo "==> dtb.img skipped (not built; stock dtb in vendor_boot is kept by AnyKernel3)"
fi

# NOTE: no modules are staged into a boot ramdisk (rdtmp): onyx boot.img
# has no ramdisk (ramdisk is in init_boot, modules in vendor_boot) and the
# stock modules in vendor_boot are config-identical to our build, so they
# load on the GhostKernelOSS kernel as-is.

VERSION_TAG="${ZIP_SUFFIX:-}"
ZIP_NAME="GhostKernelOSS-onyx-${KERNEL_VERSION}${VERSION_TAG}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

echo "==> Creating $ZIP_NAME"
( cd "$STAGING_DIR" && zip -r9q "$ZIP_PATH" . )

echo "==> Flashable zip ready"
ls -lh "$ZIP_PATH"
sha256sum "$ZIP_PATH"
