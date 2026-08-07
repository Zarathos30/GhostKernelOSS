#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 GhostKernelOSS
#
# GhostKernelOSS - AnyKernel3 packaging for POCO F7 (onyx)
#
# Packs the built kernel into a flashable AnyKernel3 zip:
#   Image         -> boot.img kernel (header v4, stock ramdisk/modules preserved)
#   dtb.img       -> boot.img dtb section (tuna.dtb + tuna7.dtb)   [if built]
#   dtbo.img      -> dtbo partition (onyx-sm8735-overlay.dtbo)     [if built]
#
# Required environment:
#   OUT_DIR     build output dir (must contain build.env from build_kernel.sh)
#   AK3_DIR     AnyKernel3 template dir (default: this repo's AnyKernel3/)
#   MKDTBOIMG   mkdtboimg binary (optional; dtbo skipped if missing)
#   ZIP_SUFFIX  extra suffix for the zip name (optional)

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$OUT_DIR/build.env" ] || { echo "ERROR: $OUT_DIR/build.env not found. Run build_kernel.sh first." >&2; exit 1; }
. "$OUT_DIR/build.env"

AK3_DIR=${AK3_DIR:-"$ROOT_DIR/AnyKernel3"}
MKDTBOIMG=${MKDTBOIMG:-}
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

  echo "==> Building dtbo.img (onyx overlay)"
  if [ -n "$MKDTBOIMG" ] && [ -f "$DTBO_ONYX" ]; then
    "$MKDTBOIMG" create "$STAGING_DIR/dtbo.img" --page_size=4096 "$DTBO_ONYX"
    echo "  + onyx-sm8735-overlay.dtbo"
  fi
else
  echo "==> dtb/dtbo skipped (not built; stock dtb/dtbo in boot/dtbo are kept by AnyKernel3)"
fi

VERSION_TAG="${ZIP_SUFFIX:-}"
ZIP_NAME="GhostKernelOSS-onyx-${KERNEL_VERSION}${VERSION_TAG}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

echo "==> Creating $ZIP_NAME"
( cd "$STAGING_DIR" && zip -r9q "$ZIP_PATH" . )

echo "==> Flashable zip ready"
ls -lh "$ZIP_PATH"
sha256sum "$ZIP_PATH"
