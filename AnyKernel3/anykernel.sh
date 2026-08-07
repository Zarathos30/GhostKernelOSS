# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
# begin properties
properties() { '
kernel.string=GhostKernelOSS by Zarathos30
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
# GhostKernelOSS banner
ui_print ' ';
ui_print '   ___ _           _   _  __                 _  ___  ___ ___ ';
ui_print '  / __| |_  ___ __| |_| |/ /___ _ _ _ _  ___| |/ _ \/ __/ __|';
ui_print '| (_ | '\'' \/ _ (_-<  _| | '\'' </ -_) '\''_| '\'' \/ -_) | (_) \__ \__ \';
ui_print '  \___|_||_\___/__/\__|_|\_\___|_| |_||_\___|_|\___/|___/___/';
ui_print ' ';
ui_print 'GhostKernelOSS by Zarathos30 | POCO F7 (onyx) | SM8735';
ui_print ' ';

# dump boot and extract ramdisk
dump_boot;

# install kernel Image and dtb into boot, dtbo.img into dtbo partition
write_boot;

## end install
