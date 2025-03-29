#!/bin/bash
echo "Hello world!"

# Start here...


# Configure ntp (not on ISO)
# timedatectl set-ntp true

# Clear the disk
sgdisk --zap-all --clear /dev/sda

# PHYSICAL PARTITIONS

# Create the physical EFI partition
sgdisk --new=1:0:+1G --typecode=1:ef00 --change-name=1:EFI /dev/sda

# Create the physical partition for root, swap and home
### pvcreate /dev/sda (not working)
sgdisk --new=2:0:0 --typecode=2:8e00 --change-name=2:root /dev/sda

# PHYSICAL VOLUMES

# Create a physical volume to contain the volume group "system"
pvcreate /dev/sda2

# VOLUME GROUPS

# Create the volume group for root, swap and home
vgcreate system /dev/sda2

# LOGICAL VOLUMES 

# Create the logical volumes for root, swap and home
lvcreate -l 20%FREE -n root system
lvcreate -L 2G -n swap system
lvcreate -L 100%FREE -n home system

# FORMAT THE PARTITIONS

# Format the EFI partition
mkfs.fat -L EFI -F32 /dev/sda1

# Format the root volume with BTRFS
mkfs.btrfs -L root /dev/system/root

# Format the home volume with ext4
mkfs.ext4 -L home /dev/system/home

# Create swap space
mkswap -L swap /dev/system/swap

# BTRFS SUBVOLUMES

# Create separate BTRFS subvolumes that do not snapshot
mkdir /mnt/btrfsroot
mount /dev/syatem/root /mnt/btrfsroot
btrfs subvolume create /mnt/btrfsroot/@
# Below not yet validated. Need more information.
btrfs subvolume create /mnt/btrfsroot/@/var
btrfs subvolume create /mnt/btrfsroot/@/usr/local
btrfs subvolume create /mnt/btrfsroot/@/srv
btrfs subvolume create /mnt/btrfsroot/@/root
btrfs subvolume create /mnt/btrfsroot/@/opt
btrfs subvolume create /mnt/btrfsroot/@/boot/grub2/x86_64-efi
btrfs subvolume create /mnt/btrfsroot/@/boot/grub2/i386-pc
btrfs subvolume create /mnt/btrfsroot/@/.snapshots
