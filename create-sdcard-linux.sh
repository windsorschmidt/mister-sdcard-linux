#!/bin/sh
#
# create-sdcard-linux.sh
#
# A Linux shell script to prepare an SD card for use with MiSTer. Based on
# https://github.com/alanswx/SD-installer_MiSTer
#
# MIT License
#
# Copyright (c) 2019 Windsor Schmidt
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -euo pipefail


function usage(){
  echo """$0 - MiSTer SD Creator
    $0 <mister-archive> <target-device>

    Where \`<mister-archive>\` is a release archive from the MiSTer repository
    (https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer), and 
    \`<target-device>\` is the name of the SD card block device.

    This script will **DESTROY** the contents of the block device passed to it;
    it does **not** check or confirm the device name you choose. Be careful.
    Must be run as root.

    Script requires exfat-utils and unrar.

    Example:
      sudo ./$0 release_20190302.rar /dev/mmcblk0

    Note:
      Please wait until the script completes before removing the card, as
      flushing the disk cache may take some time.
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
  for prog in unrar sfdisk partprobe curl; do
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
UPDATESCRIPT="https://github.com/MiSTer-devel/Updater_script_MiSTer/raw/master/update.sh"

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

msg "adding update script"
mkdir -p "$FILESDIR/#Scripts"
curl -L $UPDATESCRIPT >"$FILESDIR/#Scripts/update.sh"

if [[ -d $EXTRADIR ]]; then
  msg "copying extra files"
  cp -Rfv $EXTRADIR/* $FILESDIR
fi

msg "copying U-Boot to bootloader partition"
dd if=$UBOOTIMG of=${BLKDEV}p2

msg "unmounting exFAT partition (may take a minute)"
umount $FILESDIR
rmdir $FILESDIR

#loop_teardown

msg "done"
