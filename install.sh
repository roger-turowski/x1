#!/bin/bash

# Configure keyboard
localectl set-keymap us

# Set-up Wi-Fi connection example
# iwctl adapter list
# iwctl station wlan0 get-networks
# iwbtl station wlan0 connect <network_name>
# ip a
# ping -c 4 archlinux.org

# Set a password so we can connect via ssh
# passwd

# Set the time zone
timedatectl set-timezone US/Michigan

# Configure ntp
timedatectl set-ntp true
timedatectl status

# Set-up the fastest Arch mirrors
pacman -Sy reflector
reflector -c us -p https --age 24 --number 5 --latest 150 --sort rate --verbose --save /etc/pacman.d/mirrorlist

# Install useful tools for setup
pacman -Sy fastfetch git

# Clear the disk
sgdisk --zap-all --clear /dev/sda

# PHYSICAL PARTITIONS

# Create the physical EFI partition
sgdisk --new=1:0:+4G --typecode=1:ef00 --change-name=1:EFI /dev/sda

# Create the physical partition for root, swap and home
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
lvcreate -l 100%FREE -n home system

# FORMAT THE PARTITIONS

# Format the EFI partition
mkfs.fat -n EFI -F32 /dev/sda1

# Format the root volume with BTRFS
mkfs.btrfs -L root /dev/system/root

# Format the home volume with ext4
mkfs.ext4 -L home /dev/system/home

# Create swap space
mkswap -L swap /dev/system/swap
swapon

# BTRFS SUBVOLUMES
# Notes:
# Format, then mount, create subvolumes, unmount, create subvolume directories (Correct?)

# Create separate BTRFS subvolumes that do not snapshot

mount /dev/mapper/system-root /mnt

btrfs subvolume create /mnt/@

mkdir /mnt/.snapshots
btrfs subvolume create /mnt/@/.snapshots

mkdir -p /mnt/boot/grub2/i386-pc
btrfs subvolume create -p /mnt/@/boot/grub2/i386-pc

mkdir -p /mnt/boot/grub2/x86_64-efi
btrfs subvolume create -p /mnt/@/boot/grub2/x86_64-efi

mkdir /mnt/opt
btrfs subvolume create /mnt/@/opt

mkdir /mnt/root
btrfs subvolume create /mnt/@/root

mkdir /mnt/srv
btrfs subvolume create /mnt/@/srv

mkdir /mnt/tmp
btrfs subvolume create /mnt/@/tmp

mkdir -p /mnt/usr/local
btrfs subvolume create -p /mnt/@/usr/local

mkdir /mnt/var
btrfs subvolume create /mnt/@/var
chattr +C /mnt/@/var

umount /mnt

# Options used for all mounts utilizing an SSD
MOUNTOPTS=noatime,ssd,space_cache=v2,compress=zstd,discard=async

mount /dev/mapper/system-root /mnt -o subvol=@,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/.snapshots -o subvol=@/.snapshots,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/boot/grub2/i386-pc -o subvol=@/boot/grub2/i386-pc,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/boot/grub2/x86_64-efi -o subvol=@/boot/grub2/x86_64-efi,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/opt -o subvol=@/opt,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/root -o subvol=@/root,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/srv -o subvol=@/srv,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/tmp -o subvol=@/tmp,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/usr/local -o subvol=@/usr/local,$MOUNTOPTS
mount /dev/mapper/system-root /mnt/var -o subvol=@/var,$MOUNTOPTS

# Options no longer needed
MOUNTOPTS=
