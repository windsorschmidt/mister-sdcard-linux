#!/bin/sh
set -euo pipefail

RELARCH=$1 # MiSTer release archive
BLKDEV=$2 # target block device that ---WILL BE OVERWRITTEN!!!---
FILESDIR="files" # expect to find archive contents here
UBOOTIMG="files/linux/uboot.img" # U-Boot bootloader image
EXTRADIR="extra" # optional; contents copied to SD card root (e.g. cores)

msg(){ echo "$(tput setaf 2)--- $1$(tput sgr0)"; }

# for testing: create a disk image and mount as loopback device
loop_setup(){    
    LOOPIMG="/tmp/mister.img" # final SD card image

    msg "creating fake disk image for loopback device"
    dd if=/dev/zero of=$LOOPIMG bs=1024 count=300000

    msg "using disk image with loopback device"
    losetup $BLKDEV $LOOPIMG
    losetup
}

loop_teardown(){
    msg "detaching loopback device (image saved at: $LOOPIMG)"
    losetup -d $BLKDEV
}


function error_cleanup() {
  msg "Cleaning up failed run"
  if [[ -d $FILESDIR ]]; then
    mountpoint $FILESDIR &>/dev/null && umount -f $FILESDIR
    rmdir $FILESDIR
  fi
}

#loop_setup

trap error_cleanup ERR

msg "creating exFAT and U-Boot SPL partitions"
# use the entire disk:
# reserved (1M), exFAT partition, U-Boot (1M), reserved (1M)
SDSIZE=$((`sfdisk -s $BLKDEV` / 1024))
FATSIZE=$((SDSIZE - 3))
UBOOTSTART=$(($SDSIZE - 2))
echo -e "1M,${FATSIZE}M,7\n${UBOOTSTART}M,1M,a2" | sfdisk $BLKDEV
partprobe $BLKDEV

msg "formatting exFAT partition"
mkfs.exfat ${BLKDEV}p1

msg "mounting exFAT partition"
mkdir -p $FILESDIR
mount ${BLKDEV}p1 $FILESDIR

msg "unpacking MiSTer release archive"
unrar x -y -x*.exe $RELARCH

msg "copying extra files"
cp -Rfv $EXTRADIR/* $FILESDIR

msg "copying U-Boot to bootloader partition"
dd if=$UBOOTIMG of=${BLKDEV}p2

msg "unmounting exFAT partition (may take a minute)"
umount $FILESDIR
rmdir $FILESDIR

#loop_teardown

msg "done"
