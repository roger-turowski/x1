#!/bin/bash

# See https://github.com/walian0/bashscripts/blob/main/arch_plasma_auto.bash

success_color="\e[1;32m"
error_color="\e[1;31m"
no_color="\e[0m"

error_result() {
	echo -e "[  ${error_color}ERR{no_color} ] $1"
	exit 1
}

ok_result() {
	echo -e "[  ${success_color}OK${no_color} ] $1"
}

# Initialize variables
my_timezone=US/Michigan
my_root_mount="/mnt"

# Packages to install using pacstrap. Omit CPU firmware since we will detect the CPU type and add it later
pacstrap_pkgs=(
    base
    btrfs-progs
    cryptsetup
    dosfstools
    e2fsprogs
    git
    linux
    linux-firmware
    nano
    networkmanager
    sudo
    util-linux
    vim
)

# Detect the CPU type to install appropriate firmware
cat /proc/cpuinfo | grep -m 1 "GenuineIntel" && cpu_firmware="intel-ucode" || cpu_firmware="amd-ucode"

# Add the correct CPU firmware to the pacstrap_pkgs array
pacstrap_pkgs+=("$cpu_firmware")

gui_pkgs=(
    acpi
    acpi_call
    acpid
    alsa-utils
    avahi
    base-devel
    bash-completion
    bat
    bluez
    bluez-utils
    bridge-utils
    cups
    dialog
    dnsmasq
    dnsutils
    dosfstools
    edk2-ovmf
    efibootmgr
    eza
    fastfetch
    firewalld
    flatpak
    fzf
    grub
    gvfs
    gvfs-smb
    inetutils
    ipset
    linux-headers
    lvm2
    mc
    mtools
    network-manager-applet
    networkmanager
    nfs-utils
    nss-mdns
    ntfs-3g
    openbsd-netcat
    openssh
    os-prober
    pulseaudio
    reflector
    rsync
    sof-firmware
    terminus-font 
    tlp
    tmux
    tree
    vde2
    vifm
    wpa_supplicant
    xdg-user-dirs
    xdg-utils
)

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
timedatectl set-timezone $my_timezone \
  && ok_result " Time Zone set" \
  || error_result "Could not set the time zone"

# Configure ntp
timedatectl set-ntp true \
  && timedatectl status \
  || error_result "Could not set-ntp"

# Set-up the fastest Arch mirrors
# pacman --noconfirm -Sy reflector
reflector -c us -p https --age 6 --number 5 --latest 8 --sort rate --verbose --save /etc/pacman.d/mirrorlist

# Install tools useful during setup
pacman --noconfirm -S fastfetch git tree bat tldr tmux nano

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
lvcreate -l 30%FREE -n root system
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

mount /dev/mapper/system-root $my_root_mount

btrfs subvolume create $my_root_mount/@

mkdir $my_root_mount/.snapshots
btrfs subvolume create $my_root_mount/@/.snapshots

mkdir -p $my_root_mount/boot/grub2/i386-pc
btrfs subvolume create -p $my_root_mount/@/boot/grub2/i386-pc

mkdir -p $my_root_mount/boot/grub2/x86_64-efi
btrfs subvolume create -p $my_root_mount/@/boot/grub2/x86_64-efi

mkdir $my_root_mount/opt
btrfs subvolume create $my_root_mount/@/opt

mkdir $my_root_mount/root
btrfs subvolume create $my_root_mount/@/root

mkdir $my_root_mount/srv
btrfs subvolume create $my_root_mount/@/srv

mkdir $my_root_mount/tmp
btrfs subvolume create $my_root_mount/@/tmp

mkdir -p $my_root_mount/usr/local
btrfs subvolume create -p $my_root_mount/@/usr/local

mkdir $my_root_mount/var
btrfs subvolume create $my_root_mount/@/var
chattr +C $my_root_mount/@/var

umount $my_root_mount

# Options used for all mounts utilizing an SSD
MOUNTOPTS=noatime,ssd,space_cache=v2,compress=zstd,discard=async
mount /dev/mapper/system-root $my_root_mount -o subvol=@,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/.snapshots -o subvol=@/.snapshots,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/boot/grub2/i386-pc -o subvol=@/boot/grub2/i386-pc,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/boot/grub2/x86_64-efi -o subvol=@/boot/grub2/x86_64-efi,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/opt -o subvol=@/opt,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/root -o subvol=@/root,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/srv -o subvol=@/srv,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/tmp -o subvol=@/tmp,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/usr/local -o subvol=@/usr/local,$MOUNTOPTS
mount /dev/mapper/system-root $my_root_mount/var -o subvol=@/var,$MOUNTOPTS
MOUNTOPTS=

# Mount the EFI partition
mkdir -p $my_root_mount/boot/efi
mount /dev/sda1 $my_root_mount/boot/efi

# Mount the home partition
mkdir -p $my_root_mount/home
mount /dev/mapper/system-home $my_root_mount/home

# Install base packages. "-K" tells pacstrap to generate a new pacman master key
pacstrap $my_root_mount "${pacstrap_pkgs[@]}"

# Generate the File System TABle (fstab) using UUID numbers
genfstab -U $my_root_mount >> $my_root_mount/etc/fstab

# * * * Arch Chroot * * *
echo Entering arch-chroot. Exiting script.
echo $my_root_mount
exit
# * * * Arch Chroot * * *

# Proceed with the installation
arch-chroot $my_root_mount

# Set-up the Time Zone
ln -sf /usr/share/zoneinfo/America/Detroit /etc/localtime

# Sync the Sytem Clock to the Hardware Clock
hwclock --systohc

# Generate the locale
sed -i '171s/.//' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" >> /etc/locale.conf

# Configure keyboard mapping (Copied from OpenSUSE Tumbleweed)
{ echo "KEYMAP=us";
  echo "FONT=eurlatgr";
  echo "FONT_MAP=";
  echo "FONT_UNIMAP=";
  echo "XKBLAYOUT=us";
  echo "XKBMODEL=pc105+inet";
  echo "XKBOPTIONS=terminate:ctrl_alt_bksp";
 } >> /etc/vconsole.conf

# Configure the Host Name
{ echo -e "arch" >> /etc/hostname;
  echo -e "127.0.0.1\tlocalhost";
  echo -e "::1\t\tlocalhost";
  echo -e "127.0.1.1\tarch.localdomain\tarch"
} >> /etc/hosts

# Set a password for root
echo root:change-me | chpasswd

# Install the rest of the system packages
pacman -Sy "${gui_pkgs[@]}" --noconfirm --quiet

# Uncomment below to install graphics card drivers
# pacman -S --noconfirm xf86-video-amdgpu
# pacman -S --noconfirm nvidia nvidia-utils nvidia-settings

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# ToDo: Optimize this section
# Enable Services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable cups.service
systemctl enable sshd
systemctl enable avahi-daemon
systemctl enable tlp
systemctl enable reflector.timer
systemctl enable fstrim.timer
systemctl enable firewalld
systemctl enable acpid

# Make wheel group sudo enabled
# EDITOR=vim visudo
# Uncomment %wheel ALL=(ALL:ALL) ALL
# The code to update sudoers file below needs to be verified!
SUDOER_TMP=$(mktemp)
cat /etc/sudoers > $SUDOER_TMP
sed -i -e 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' $SUDOER_TMP
visudo -c -f $SUDOER_TMP && \ # this will fail if the syntax is incorrect
    cat $SUDOER_TMP > /etc/sudoers
rm $SUDOER_TMP

# Update mkinitcpio.conf
# vim /etc/mkinitcpio.conf
# MODULES=(btrfs)
# HOOKS=(... block lvm2 filesystems ...)
sed -i \
    -e 's/MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf \
    -e 's/block filesystems fsck/block lvm2 filesystems fsck grub-btrfs-overlayfs' \
    /etc/mkinitcpio.conf
mkinitcpio -p linux

# Add a user account
useradd -mG wheel roger
echo roger:change-me | chpasswd

# ToDo: Clean tis section up
# Install KDE Plasma and sddm
pacman -S --needed --noconfirm xorg sddm
pacman -S --needed --noconfirm plasma kde-applications
systemctl enable sddm

# Apply the Breeze theme to sddm
mkdir /etc/sddm.conf.d/ && sed 's/Current=/Current=breeze/;w /etc/sddm.conf.d/sddm.conf' /usr/lib/sddm/sddm.conf.d/default.conf

# Add some useful applications
pacman -S tree wireshark-qt ttf-0xproto-nerd ttf-cascadia-code-nerd ttf-cascadia-mono-nerd ttf-firacode-nerd ttf-hack-nerd ttf-jetbrains-mono-nerd ttf-sourcecodepro-nerd curl plocate btop htop fastfetch tmux tldr zellij git eza bat xrdp mc vifm tldr fzf

# Finish configuring snapper
pacman -S snapper snap-pac grub-btrfs inotify-tools
btrfs subvolume delete /.snapshots/
snapper -c root create-config /
snapper list-configs
snapper -c root set-config ALLOW_GROUPS="wheel" SYNC_ACL=yes
sed -i 's/PRUNENAMES = ".git .hg .svn"/PRUNENAMES = ".git .hg .svn .snapshots"/' /etc/updatedb.conf

# Configure GRUB for snapshot recovery
sed -i 's/GRUB_DISABLE_RECOVERY=true/GRUB_DISABLE_RECOVERY=false/' /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable grub-btrfsd
systemctl enable snapper-boot.timer

# /etc/updatedb.conf
# PRUNENAMES = ".snapshots"

# Finish and reboot
exit
umount -a
systemctl reboot



# Log on as a regular user

# Install an AUR helper
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay.git
pushd yay
makepkg -si
popd
yay -S brave-bin btrfs-assistant ttf-ms-fonts
