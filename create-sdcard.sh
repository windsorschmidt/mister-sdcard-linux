#!/bin/sh
set -euo pipefail


function usage(){
  echo """$0 - MiSTer SD Creator
    Full Documentation at https://github.com/windsorschmidt/mister-sdcard-linux
    $0 <mister-archive> <target-device>
  """
  exit 1
}


function msg(){
  echo "$(tput setaf 2)--- $1$(tput sgr0)"
}


function err(){
  echo "$(tput setaf 1)--- $1$(tput sgr0)"
  exit $2
}


# for testing: create a disk image and mount as loopback device
function loop_setup(){
    LOOPIMG="/tmp/mister.img" # final SD card image

    msg "creating fake disk image for loopback device"
    dd if=/dev/zero of=$LOOPIMG bs=1024 count=300000

    msg "using disk image with loopback device"
    losetup $BLKDEV $LOOPIMG
    losetup
}


function loop_teardown(){
    msg "detaching loopback device (image saved at: $LOOPIMG)"
    losetup -d $BLKDEV
}


function check_perm() {
  [[ $EUID -eq 0 ]] || err "Root privileges will be needed" 1
  [[ -b $BLKDEV ]] || err "'$BLKDEV' is not a block device. Something is wrong?!?!" 1
  [[ -r $RELARCH ]] || err "Cannot access '$RELARCH'. Check file location and permissions." 1
  [[ -w . ]] || err "Working directory '.' needs write permissions." 1
  [[ ! -e $FILESDIR ]] || err "Temporary directory '$FILESDIR' exists. Please move/remove." 1
}


function check_software() {
  for prog in unrar sfdisk partprobe; do
    command -v ${prog} > /dev/null 2>&1 || (msg "Executable '${prog}' not found in PATH."; exit 1)
  done
}


function error_cleanup() {
  msg "Cleaning up failed run"
  if [[ -d $FILESDIR ]]; then
    mountpoint $FILESDIR &>/dev/null && umount -f $FILESDIR
    rmdir $FILESDIR
  fi
}

##
# Main Logic
##

if [[ $# -ne 2 ]]; then
  usage
fi

RELARCH=$1 # MiSTer release archive
BLKDEV=$2 # target block device that ---WILL BE OVERWRITTEN!!!---
FILESDIR="files" # expect to find archive contents here
UBOOTIMG="files/linux/uboot.img" # U-Boot bootloader image
EXTRADIR="extra" # optional; contents copied to SD card root (e.g. cores)

#loop_setup

check_perm
check_software
trap error_cleanup ERR

msg "creating exFAT and U-Boot SPL partitions"
# use the entire disk:
# reserved (1M), exFAT partition, U-Boot (1M), reserved (1M)
SDSIZE=$((`sfdisk -s $BLKDEV` / 1024))
FATSIZE=$((SDSIZE - 3))
UBOOTSTART=$(($SDSIZE - 2))
sfdisk $BLKDEV <<EOF
1M,${FATSIZE}M,7
${UBOOTSTART}M,1M,a2
EOF
partprobe $BLKDEV

msg "formatting exFAT partition"
mkfs.exfat -n "MiSTer_Data" ${BLKDEV}p1

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
