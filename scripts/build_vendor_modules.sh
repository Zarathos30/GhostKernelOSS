#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 GhostKernelOSS
#
# GhostKernelOSS - best-effort out-of-tree vendor module build (POCO F7 / onyx)
#
# Builds the Qualcomm/Xiaomi vendor modules from MODULES_DIR (sources) using
# the classic Kbuild out-of-tree flow:
#   make -C <kernel> O=<out> M=<module dir> modules
# in dependency order (modules referenced via KBUILD_EXTRA_SYMBOLS first, so
# their Module.symvers exist). The sun/tuna platform is selected automatically
# from CONFIG_ARCH_SUN in the kernel .config. Built .ko are installed into
# MODULES_STAGE so pack_anykernel.sh can add them to the flashable zip.
# A failing module is logged and skipped - never fatal.
#
# Required environment:
#   KERNEL_DIR    kernel source tree
#   OUT_DIR       build output dir (must contain .config from build_kernel.sh)
#   MODULES_DIR   vendor module sources (containing qcom/opensource)
#   CLANG_DIR     AOSP clang prebuilt root (containing bin/clang; optional)
#   JOBS          make parallelism (default: nproc)
#   MODULES_STAGE module staging dir (default: $OUT_DIR/modules_stage)

set -uo pipefail

KERNEL_DIR=${KERNEL_DIR:-}
OUT_DIR=${OUT_DIR:-}
MODULES_DIR=${MODULES_DIR:-}
CLANG_DIR=${CLANG_DIR:-}
JOBS=${JOBS:-$(nproc)}
MODULES_STAGE=${MODULES_STAGE:-"$OUT_DIR/modules_stage"}

[ -n "$KERNEL_DIR" ] || { echo "ERROR: KERNEL_DIR required" >&2; exit 1; }
[ -n "$OUT_DIR" ] || { echo "ERROR: OUT_DIR required" >&2; exit 1; }
[ -d "$MODULES_DIR/qcom/opensource" ] || { echo "ERROR: MODULES_DIR/qcom/opensource not found: $MODULES_DIR" >&2; exit 1; }
[ -f "$OUT_DIR/.config" ] || { echo "ERROR: $OUT_DIR/.config not found. Run build_kernel.sh first." >&2; exit 1; }

if [ -n "$CLANG_DIR" ]; then
  export PATH="$CLANG_DIR/bin:$PATH"
fi

export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KCFLAGS="-D__ANDROID_COMMON_KERNEL__"

CCACHE_ARGS=()
if [ "${CCACHE:-0}" = "1" ] && command -v ccache >/dev/null 2>&1; then
  CCACHE_ARGS=(CC="ccache clang" HOSTCC="ccache clang" CXX="ccache clang++" HOSTCXX="ccache clang++")
  echo "==> ccache enabled"
fi

# Entries: "relative path under MODULES_DIR|make variable overrides"
# Order matters: KBUILD_EXTRA_SYMBOLS dependencies must build first.
MODULES=(
  "qcom/opensource/mm-drivers/hw_fence|"
  "qcom/opensource/mmrm-driver|"
  "qcom/opensource/securemsm-kernel|"
  "qcom/opensource/synx-kernel|"
  "qcom/opensource/mm-drivers/msm_ext_display|"
  "qcom/opensource/dsp-kernel|"
  "qcom/opensource/audio-kernel|CONFIG_SND_SOC_SUN=m"
  "qcom/opensource/graphics-kernel|CONFIG_QCOM_KGSL=m"
  "qcom/opensource/video-driver|"
  "qcom/opensource/eva-kernel|"
  "qcom/opensource/display-drivers|"
  "qcom/opensource/touch-drivers|CONFIG_MSM_TOUCH=m"
  "qcom/opensource/wlan/platform|"
  "qcom/opensource/wlan/fw-api|"
  "qcom/opensource/wlan/qca-wifi-host-cmn|"
  "qcom/opensource/wlan/qcacld-3.0|CONFIG_QCA_CLD_WLAN=m"
  "qcom/opensource/bt-kernel|CONFIG_MSM_BT_POWER=m CONFIG_BTFM_SLIM=m CONFIG_I2C_RTC6226_QCA=m CONFIG_BTFM_CODEC=m CONFIG_SLIM_BTFM_CODEC=m CONFIG_BTFM_SWR=m"
  "qcom/opensource/camera-kernel|"
  "qcom/opensource/dataipa|"
  "qcom/opensource/datarmnet|"
  "qcom/opensource/spu-kernel|CONFIG_MSM_SPCOM=m CONFIG_MSM_SPSS_UTILS=m"
  "nxp/opensource/driver|"
)

LOG_DIR="$OUT_DIR/vendor-module-logs"
mkdir -p "$LOG_DIR" "$MODULES_STAGE"

built=0
failed=0
skipped=0

for entry in "${MODULES[@]}"; do
  rel="${entry%%|*}"
  makevars="${entry#*|}"
  moddir="$MODULES_DIR/$rel"
  log="$LOG_DIR/$(basename "$rel").log"

  if [ ! -f "$moddir/Makefile" ] && [ ! -f "$moddir/Kbuild" ]; then
    echo "SKIP  $rel (no Makefile/Kbuild)"
    skipped=$((skipped+1))
    continue
  fi

  echo "==> Building $rel ..."
  if ! ( cd "$KERNEL_DIR"
    make -C "$moddir" KERNEL_SRC="$KERNEL_DIR" O="$OUT_DIR" M="$moddir" "${CCACHE_ARGS[@]}" $makevars modules \
      && make -C "$moddir" KERNEL_SRC="$KERNEL_DIR" O="$OUT_DIR" M="$moddir" "${CCACHE_ARGS[@]}" $makevars \
         INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$MODULES_STAGE" modules_install
  ) > "$log" 2>&1; then
    echo "FAIL  $rel (log: $log)"
    tail -30 "$log" | sed 's/^/      /'
    failed=$((failed+1))
    continue
  fi
  kos=$(find "$moddir" -name "*.ko" 2>/dev/null | wc -l)
  echo "OK    $rel ($kos .ko)"
  built=$((built+1))
done

echo
echo "==> Vendor modules summary: $built built, $failed failed, $skipped skipped"
staged=$(find "$MODULES_STAGE/lib/modules" -name "*.ko" 2>/dev/null | wc -l)
echo "    total .ko staged: $staged"
[ "$failed" -gt 0 ] && echo "    failed module logs in $LOG_DIR"
