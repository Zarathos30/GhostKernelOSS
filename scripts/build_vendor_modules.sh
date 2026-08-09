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

# Entries: "relative path under MODULES_DIR|make variable overrides|target"
#   target: all     -> run the module's own Makefile (default for wrappers)
#           direct  -> run make -C kernel M=<mod> directly (Kbuild-style dirs)
# Order matters: KBUILD_EXTRA_SYMBOLS dependencies must build first.
MODULES=(
  "qcom/opensource/mm-drivers/hw_fence||all"
  "qcom/opensource/mmrm-driver||all"
  "qcom/opensource/securemsm-kernel|CONFIG_HDCP_QSEECOM=m|all"
  "qcom/opensource/synx-kernel||all"
  "qcom/opensource/mm-drivers/msm_ext_display||all"
  "qcom/opensource/dsp-kernel||all"
  "qcom/opensource/audio-kernel|CONFIG_SND_SOC_SUN=m|all"
  "qcom/opensource/graphics-kernel|CONFIG_QCOM_KGSL=m|all"
  "qcom/opensource/video-driver||all"
  "qcom/opensource/eva-kernel||all"
  "qcom/opensource/display-drivers|CONFIG_DRM_MSM=m DISPLAY_ROOT=$MODULES_DIR/qcom/opensource/display-drivers KBUILD_EXTRA_SYMBOLS=vendor-modules/qcom/opensource/securemsm-kernel/Module.symvers|all"
  "qcom/opensource/touch-drivers|CONFIG_MSM_TOUCH=m|all"
  "qcom/opensource/data-kernel/drivers/smem-mailbox||all"
  "qcom/opensource/wlan/platform||all"
  "qcom/opensource/datarmnet-ext/mem||all"
  "qcom/opensource/dataipa|KBUILD_EXTRA_SYMBOLS=vendor-modules/qcom/opensource/datarmnet-ext/mem/Module.symvers|direct"
  "qcom/opensource/wlan/fw-api||all"
  "qcom/opensource/wlan/qca-wifi-host-cmn||all"
  "qcom/opensource/wlan/qcacld-3.0|CONFIG_QCA_CLD_WLAN=m|all"
  "qcom/opensource/bt-kernel|CONFIG_MSM_BT_POWER=m CONFIG_BTFM_CODEC=m CONFIG_BTFM_SWR=m CONFIG_SLIM_BTFM_CODEC=m|all"
  "qcom/opensource/camera-kernel||all"
  "qcom/opensource/datarmnet||all"
  "qcom/opensource/spu-kernel|CONFIG_MSM_SPCOM=m CONFIG_MSM_SPSS_UTILS=m|all"
  "nxp/opensource/driver||all"
)

# The module Makefiles build roots like $(KERNEL_SRC)/$(M), so they expect M
# relative to the kernel source tree, while kbuild resolves a relative M from
# the object tree. An absolute symlink inside both trees makes both resolve.
echo "==> Linking vendor modules tree (relative M)"
ln -sfn "$MODULES_DIR" "$KERNEL_DIR/vendor-modules"
ln -sfn "$MODULES_DIR" "$OUT_DIR/vendor-modules"

LOG_DIR="$OUT_DIR/vendor-module-logs"
mkdir -p "$LOG_DIR" "$MODULES_STAGE"

built=0
failed=0
skipped=0

for entry in "${MODULES[@]}"; do
  IFS='|' read -r rel makevars tgt <<< "$entry"
  moddir="$MODULES_DIR/$rel"
  M="vendor-modules/$rel"
  log="$LOG_DIR/$(basename "$rel").log"

  if [ ! -f "$moddir/Makefile" ] && [ ! -f "$moddir/Kbuild" ]; then
    echo "SKIP  $rel (no Makefile/Kbuild)"
    skipped=$((skipped+1))
    continue
  fi

  echo "==> Building $rel ..."
  if [ "$tgt" = "direct" ]; then
    if ! ( cd "$KERNEL_DIR"
      make -j"$JOBS" O="$OUT_DIR" "${CCACHE_ARGS[@]}" M="$M" $makevars modules \
        && make -j"$JOBS" O="$OUT_DIR" "${CCACHE_ARGS[@]}" M="$M" $makevars \
           INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$MODULES_STAGE" modules_install
    ) > "$log" 2>&1; then
      echo "FAIL  $rel (log: $log)"
      tail -30 "$log" | sed 's/^/      /'
      failed=$((failed+1))
      continue
    fi
  else
    if ! ( cd "$KERNEL_DIR"
      make -C "$moddir" KERNEL_SRC="$KERNEL_DIR" O="$OUT_DIR" M="$M" "${CCACHE_ARGS[@]}" $makevars "$tgt" \
        && make -C "$moddir" KERNEL_SRC="$KERNEL_DIR" O="$OUT_DIR" M="$M" "${CCACHE_ARGS[@]}" $makevars \
           INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="$MODULES_STAGE" modules_install
    ) > "$log" 2>&1; then
      echo "FAIL  $rel (log: $log)"
      tail -30 "$log" | sed 's/^/      /'
      failed=$((failed+1))
      continue
    fi
  fi
  kos=$(find "$moddir" -name "*.ko" 2>/dev/null | wc -l)
  echo "OK    $rel ($kos .ko)"
  # Modules that build nothing (e.g. display-drivers with CONFIG_DRM_MSM=y
  # built-in) produce no Module.symvers, but downstream modules modpost
  # against that path; an empty file lets them resolve the symbols from the
  # kernel's own Module.symvers instead.
  [ -f "$moddir/Module.symvers" ] || touch "$moddir/Module.symvers"
  if [ "$rel" = "qcom/opensource/display-drivers" ]; then
    mkdir -p "$moddir/msm"
    cp -f "$moddir/Module.symvers" "$moddir/msm/Module.symvers"
  fi
  # dataipa's modules build under drivers/platform/msm/ but modpost writes
  # its symvers at the module root; qcacld expects the msm/ path - mirror it
  if [ "$rel" = "qcom/opensource/dataipa" ]; then
    mkdir -p "$moddir/drivers/platform/msm"
    cp -f "$moddir/Module.symvers" "$moddir/drivers/platform/msm/Module.symvers"
  fi
  built=$((built+1))
done

echo
echo "==> Vendor modules summary: $built built, $failed failed, $skipped skipped"
staged=$(find "$MODULES_STAGE/lib/modules" -name "*.ko" 2>/dev/null | wc -l)
echo "    total .ko staged: $staged"
[ "$failed" -gt 0 ] && echo "    failed module logs in $LOG_DIR"
