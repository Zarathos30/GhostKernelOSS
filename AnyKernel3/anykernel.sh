# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
# begin properties
properties() { '
kernel.string=GhostKernelOSS for POCO F7 (onyx) | Snapdragon 8s Gen 4 (SM8735 / Tuna LE) | 6.6.82
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=1
device.name1=onyx
device.name2=onyx_in
device.name3=onyx_global
device.name4=aliothin
device.name5=
supported.versions=16
supported.patchlevels=
'; } # end properties

# shell variables
block=/dev/block/bootdevice/by-name/boot;
dtbo_block=/dev/block/bootdevice/by-name/dtbo;
is_slot_device=auto;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;
no_block_display=1;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

## AnyKernel functions
# dump boot and extract ramdisk
dump_boot;

# install kernel Image and dtb into boot, dtbo.img into dtbo partition
write_boot;

## end install
