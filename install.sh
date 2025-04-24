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
pacman --noconfirm -Sy reflector
reflector -c us -p https --age 24 --number 5 --latest 150 --sort rate --verbose --save /etc/pacman.d/mirrorlist

# Install useful tools for setup
pacman --noconfirm -S fastfetch git tree bat tldr

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
swapon /dev/system/swap

# BTRFS SUBVOLUMES
# Notes:
# Format, then mount, create subvolumes, unmount, create subvolume
# directories, create subvolumes, unmount, re-mount with options (Correct?)

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

# Mount the EFI partition
mkdir -p /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi

# Mount the home partition
mkdir -p /mnt/home
mount /dev/mapper/system-home /mnt/home

# Install base packages
pacstrap /mnt base linux linux-firmware git vim intel-ucode btrfs-progs

# Generate the File System TABle (fstab) using UUID numbers
genfstab -U /mnt >> /mnt/etc/fstab

# Proceed with the installation
arch-chroot /mnt

# Set-up the Time Zone
ln -sf /usr/share/zoneinfo/America/Detroit /etc/localtime

# Sync the Sytem Clock to the Hardware Clock
hwclock --systohc

# Generate the locale
sed -i '171s/.//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

# Configure keyboard mapping (Copied from OpenSUSE Tumbleweed)
echo "KEYMAP=us" >> /etc/vconsole.conf
echo "FONT=eurlatgr.psfu" >> /etc/vconsole.conf
echo "FONT_MAP=" >> /etc/vconsole.conf
echo "FONT_UNIMAP=" >> /etc/vconsole.conf
echo "XKBLAYOUT=us" >> /etc/vconsole.conf
echo "XKBMODEL=pc105+inet" >> /etc/vconsole.conf
echo "XKBOPTIONS=terminate:ctrl_alt_bksp" >> /etc/vconsole.conf

# Configure the Host Name
echo "arch" >> /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1       localhost" >> /etc/hosts
echo "127.0.1.1 arch.localdomain arch" >> /etc/hosts

# Set a password for root
echo root:change-me | chpasswd

# Install the rest of the system packages
pacman -S --noconfirm grub efibootmgr networkmanager network-manager-applet dialog wpa_supplicant mtools dosfstools reflector base-devel linux-headers avahi xdg-user-dirs xdg-utils gvfs gvfs-smb nfs-utils inetutils dnsutils bluez bluez-utils cups alsa-utils pulseaudio bash-completion openssh rsync reflector acpi acpi_call tlp edk2-ovmf bridge-utils dnsmasq vde2 openbsd-netcat ipset firewalld flatpak sof-firmware nss-mdns acpid os-prober ntfs-3g terminus-font 

# Uncomment below to install graphics card drivers
# pacman -S --noconfirm xf86-video-amdgpu
# pacman -S --noconfirm nvidia nvidia-utils nvidia-settings

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable Services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable cups.service
systemctl enable sshd
systemctl enable avahi-daemon
systemctl enable tlp
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable libvirtd
systemctl enable firewalld
systemctl enable acpid

# Add a user account
useradd -m roger

# Update mkinitcpio.conf
vim /etc/mkinitcpio.conf
# MODULES=(btrfs)
# HOOKS=(... block lvm2 filesystems ...)
mkinitcpio -p linux

# RESULT: Not booting. "No compatible bootloader found."