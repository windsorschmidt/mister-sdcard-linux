# About

A Linux shell script to prepare an SD card for use with MiSTer. Based on https://github.com/alanswx/SD-installer_MiSTer

# Dependencies

- exfat-utils
- unrar

# Usage

```
create-sdcard.sh <mister-archive> <target-device>
```

Where `<mister-archive>` is a release archive from the [MiSTer repository](https://github.com/MiSTer-devel/SD-Installer-Win64_MiSTer/tree/master/), and `<target-device>` is the name of the SD card block device.

This script will **DESTROY** the contents of the block device passed to it; it does **not** check or confirm the device name you choose. Be careful. Must be run as root.

Example:

```
sudo ./create-sdcard.sh release_20190302.rar /dev/mmcblk0
```

Note: Please wait until the script completes before removing the card, as flushing the disk cache may take some time.
