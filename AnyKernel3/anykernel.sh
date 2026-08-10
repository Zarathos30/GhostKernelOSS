### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=GhostKernelOSS by Zarathos30
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=onyx
device.name2=onyx_in
device.name3=onyx_global
device.name4=aliothin
device.name5=
supported.versions=16
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

ui_print " "
ui_print "GhostKernelOSS by Zarathos30 | POCO F7 (onyx) | SM8735"
ui_print " "

# onyx (Android 16, boot header v4): boot.img contains ONLY the kernel
# (ramdisk_size=0). The ramdisk lives in init_boot.img, the dtb and the
# vendor modules (lib/modules/*.ko + modules.load) live in vendor_boot.img.
# So we only replace the kernel in boot.img; init_boot/vendor_boot/dtbo
# are left untouched (stock config is identical, so the stock modules in
# vendor_boot keep loading on the GhostKernelOSS kernel).
#
# NOTE: no dump_boot/repack_ramdisk/write_boot here - with ramdisk_size=0
# unpack_ramdisk() would abort with "No ramdisk found to unpack".

# dump boot image and split it (magiskboot unpack; extracts kernel, and a
# dtb only if the stock image actually contains one)
split_boot;

# dtb handling for the kernel-only boot (hdr v4, no dtb size field):
# - if magiskboot extracted a separate dtb from the stock image
#   (split_img/dtb), flash_boot replaces it with our dtb.img as-is
# - if the stock kernel had a dtb appended inside its kernel area
#   (Image-dtb style), re-append our dtb.img to the new kernel the same way
# - otherwise (stock boot has no dtb, like the OTA: dtb lives in
#   vendor_boot.img) drop dtb.img so boot stays kernel-only
if [ -f dtb.img ]; then
  if [ -f "$split_img/dtb" ]; then
    ui_print " " "Stock boot had dtb section; replacing with dtb.img";
  elif [ "$(tail -c 8388608 "$split_img/kernel" | od -An -v -tx1 | tr -d ' \n' | grep -c d00dfeed)" != "0" ]; then
    ui_print " " "Stock kernel had appended dtb; re-appending dtb.img";
    cat dtb.img >> "$home/Image";
    rm -f dtb.img;
  else
    ui_print " " "Stock boot has no dtb (dtb in vendor_boot); kernel-only flash";
    rm -f dtb.img;
  fi;
fi;

# repack (hdr v4, no ramdisk) and flash boot
flash_boot;

## end install
