#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 GhostKernelOSS
#
# GhostKernelOSS - build script for Xiaomi POCO F7 (onyx)
# SoC: SM8735 (Snapdragon 8s Gen 4, Qualcomm "Tuna"), Kernel Platform LE (non-GKI)
#
# Builds the kernel Image (and device trees when the vendor module sources are
# available) from the merged device config:
#   generic_le_defconfig + vendor/sun_le.config + vendor/onyx_perf.config
#
# Required environment:
#   KERNEL_DIR   kernel source tree (default: <repo>/xiaomi/sm8735)
#   CLANG_DIR    AOSP clang prebuilt root (containing bin/clang)
#   OUT_DIR      build output directory (default: $KERNEL_DIR/out)
#   JOBS         make parallelism (default: nproc)
#   MODULES_DIR  vendor module sources providing dt-bindings headers
#                (default: <parent of KERNEL_DIR>/sm8735-modules; dtbs
#                are skipped when unavailable)

set -euo pipefail

KERNEL_DIR=${KERNEL_DIR:-$(cd "$(dirname "$0")/../xiaomi/sm8735" && pwd)}
CLANG_DIR=${CLANG_DIR:-}
OUT_DIR=${OUT_DIR:-"$KERNEL_DIR/out"}
JOBS=${JOBS:-$(nproc)}
MODULES_DIR=${MODULES_DIR:-"$(dirname "$KERNEL_DIR")/sm8735-modules"}

export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KCFLAGS="-D__ANDROID_COMMON_KERNEL__"
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-ghost}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-GhostKernelOSS}

if [ -n "$CLANG_DIR" ]; then
  export PATH="$CLANG_DIR/bin:$PATH"
fi

if ! command -v clang >/dev/null 2>&1; then
  echo "ERROR: clang not found. Set CLANG_DIR to an AOSP clang prebuilt." >&2
  exit 1
fi

# ccache (optional): set CCACHE=1 to wrap the compiler
CCACHE_ARGS=()
if [ "${CCACHE:-0}" = "1" ] && command -v ccache >/dev/null 2>&1; then
  CCACHE_ARGS=(CC="ccache clang" HOSTCC="ccache clang" CXX="ccache clang++" HOSTCXX="ccache clang++")
  echo "==> ccache enabled"
fi

MERGE_CONFIG="$KERNEL_DIR/scripts/kconfig/merge_config.sh"
BASE_DEFCONFIG="arch/arm64/configs/generic_le_defconfig"
FRAGMENTS=(
  "arch/arm64/configs/vendor/sun_le.config"
  "arch/arm64/configs/vendor/onyx_perf.config"
)

echo "==> GhostKernelOSS build for POCO F7 (onyx) / SM8735 Tuna"
echo "    Kernel dir : $KERNEL_DIR"
echo "    Output dir : $OUT_DIR"
echo "    Jobs       : $JOBS"
clang --version | head -n1

mkdir -p "$OUT_DIR"

echo "==> Generating merged defconfig (generic_le_defconfig + fragments)"
( cd "$KERNEL_DIR"
  make -j"$JOBS" O="$OUT_DIR" "${CCACHE_ARGS[@]}" generic_le_defconfig
  "$MERGE_CONFIG" -m -r -y -O "$OUT_DIR" "$BASE_DEFCONFIG" "${FRAGMENTS[@]}"
  make -j"$JOBS" O="$OUT_DIR" "${CCACHE_ARGS[@]}" olddefconfig
)

grep -q "CONFIG_ARCH_TUNA=y" "$OUT_DIR/.config" \
  || { echo "ERROR: CONFIG_ARCH_TUNA not enabled in merged config" >&2; exit 1; }

# Device trees require dt-bindings headers shipped in the out-of-tree vendor
# module sources (camera/audio/synx); build dtbs only when they are available.
HAS_DTB=0
if [ -d "$MODULES_DIR/qcom/opensource" ]; then
  DTC_INCLUDE_DIRS=""
  for inc in camera-kernel audio-kernel/include synx-kernel; do
    [ -d "$MODULES_DIR/qcom/opensource/$inc" ] && DTC_INCLUDE_DIRS="$DTC_INCLUDE_DIRS $MODULES_DIR/qcom/opensource/$inc"
  done
  [ -n "$DTC_INCLUDE_DIRS" ] && export KBUILD_DTC_INCLUDE="$DTC_INCLUDE_DIRS"
  HAS_DTB=1
fi

if [ "$HAS_DTB" = "1" ]; then
  echo "==> Building Image and dtbs"
  MAKE_GOALS="Image dtbs"
else
  echo "==> Building Image (dtbs skipped: vendor module headers not found at $MODULES_DIR)"
  MAKE_GOALS="Image"
fi
( cd "$KERNEL_DIR"
  make -j"$JOBS" O="$OUT_DIR" "${CCACHE_ARGS[@]}" $MAKE_GOALS
)

IMAGE="$OUT_DIR/arch/arm64/boot/Image"
[ -f "$IMAGE" ] || { echo "ERROR: kernel Image not built" >&2; exit 1; }

echo "==> Build complete"
ls -lh "$IMAGE"

KV=$(grep -E '^VERSION\s*=|^PATCHLEVEL\s*=|^SUBLEVEL\s*=' "$KERNEL_DIR/Makefile" | awk '{print $3}' | paste -sd.)
cat > "$OUT_DIR/build.env" <<EOF
KERNEL_DIR=$KERNEL_DIR
OUT_DIR=$OUT_DIR
IMAGE=$IMAGE
HAS_DTB=$HAS_DTB
DTB_TUNA=$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/tuna.dtb
DTB_TUNA7=$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/tuna7.dtb
DTBO_ONYX=$OUT_DIR/arch/arm64/boot/dts/vendor/qcom/onyx-sm8735-overlay.dtbo
KERNEL_VERSION=$KV
EOF
