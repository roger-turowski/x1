#!/bin/bash
echo "Hello world!"

# Start here...


# Configure ntp (not on ISO)
# timedatectl set-ntp true

# Clear the disk
sgdisk --zap-all --clear /dev/sda

# Create the EFI partition
sgdisk --new=1:0:+550M --typecode=1:ef00 --change-name=1:EFI /dev/sda

# Format the EFI partition
mkfs.fat -F 32 /dev/sda1

# Create the physical partition for root, swap and home
### pvcreate /dev/sda (not working)
sgdisk --new=2:0:0 --typecode=2:8503 --change-name=2:root /dev/sda

# Create the volume group for root, swap and home
vgcreate system /dev/sda

# Create the logical volumes for root, swap and home
lvcreate -L 20%FREE -n root system
lvcreate -L 2G -n swap system
lvcreate -L 100%FREE -n home system

# Format the root volume with BTRFS
mkfs.btrfs /dev/system/root

# Format the home volume with ext4
mkfs.ext4 /dev/system/home
