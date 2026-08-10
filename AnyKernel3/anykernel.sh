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

# dump boot and extract ramdisk
dump_boot;

# install kernel Image and dtb into boot, dtbo.img into dtbo partition
write_boot;

## end install
