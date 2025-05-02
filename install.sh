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
my_timezone="US/Michigan"
my_root_mount="/mnt"
my_host_name="arch"
my_user_id="roger"
my_password_hash="\$6\$1LOK.XIjsfKmOi/e\$U.zBYQYBdVLY.eUb2Y42/dzoNxPorbn1.aJ7VKQk/qBt7pzp6B1uGDSQCl63g83bk/zSZb9cHu4jKtC5Q0a1c."

# Packages to install using pacstrap. Omit CPU firmware since we will detect the CPU type and add it later
pacstrap_pkgs=(
    base
    btrfs-progs
    cryptsetup
    dosfstools
    e2fsprogs
    git
    grub-btrfs
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
    plocate
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
timedatectl set-timezone $my_timezone

# Configure ntp
timedatectl set-ntp true
timedatectl status

# Set-up the fastest Arch mirrors
# pacman --noconfirm -Sy reflector
reflector -c us -p https --age 6 --number 5 --latest 8 --sort rate --verbose --save /etc/pacman.d/mirrorlist

# Install tools useful during setup
pacman --noconfirm -Sy fastfetch git tree bat tldr tmux nano

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
# echo Entering arch-chroot. Exiting script.
# echo $my_root_mount
# exit
# * * * Arch Chroot * * *

# Proceed with the installation
# arch-chroot $my_root_mount

# Set-up the Time Zone
arch-chroot $my_root_mount ln -sf /usr/share/zoneinfo/America/Detroit /etc/localtime

# Sync the Sytem Clock to the Hardware Clock
arch-chroot $my_root_mount hwclock --systohc

# Generate the locale
arch-chroot $my_root_mount sed -i '171s/.//' /etc/locale.gen
arch-chroot $my_root_mount locale-gen
echo "LANG=en_US.UTF-8" >> $my_root_mount/etc/locale.conf

# Configure keyboard mapping (Copied from OpenSUSE Tumbleweed)
{ echo 'KEYMAP=us';
  echo 'FONT=eurlatgr';
  echo 'FONT_MAP=';
  echo 'FONT_UNIMAP=';
  echo 'XKBLAYOUT=us';
  echo 'XKBMODEL=pc105+inet';
  echo 'XKBOPTIONS=terminate:ctrl_alt_bksp';
} >> $my_root_mount/etc/vconsole.conf

# Configure the Host Name
echo -e $my_host_name >> $my_root_mount/etc/hostname

# Build the hosts file
{ echo -e '127.0.0.1\tlocalhost';
  echo -e '::1\t\tlocalhost';
  echo -e '127.0.1.1\tarch.localdomain\tarch'
} >> $my_root_mount/etc/hosts

# Set a password for root
arch-chroot $my_root_mount echo root:change-me | chpasswd

# Install the rest of the system packages
arch-chroot $my_root_mount pacman -Sy "${gui_pkgs[@]}" --noconfirm --quiet

# Uncomment below to install graphics card drivers
# pacman -S --noconfirm xf86-video-amdgpu
# pacman -S --noconfirm nvidia nvidia-utils nvidia-settings

# Install GRUB
arch-chroot $my_root_mount grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
arch-chroot $my_root_mount grub-mkconfig -o /boot/grub/grub.cfg

# ToDo: Optimize this section
# Enable Services
arch-chroot $my_root_mount systemctl enable NetworkManager \
    bluetooth \
    cups.service \
    sshd \
    avahi-daemon \
    tlp \
    reflector.timer \
    fstrim.timer \
    firewalld \
    acpid \

# Make wheel group sudo enabled
# EDITOR=vim visudo
# Uncomment %wheel ALL=(ALL:ALL) ALL
# The code to update sudoers file below needs to be verified!
#arch-chroot $my_root_mount SUDOER_TMP=$(mktemp)
#arch-chroot $my_root_mount cat /etc/sudoers > $SUDOER_TMP
#arch-chroot $my_root_mount sed -i -e 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' $SUDOER_TMP
#arch-chroot $my_root_mount visudo -c -f $SUDOER_TMP
#arch-chroot $my_root_mount cat $SUDOER_TMP > /etc/sudoers
#arch-chroot $my_root_mount rm $SUDOER_TMP

# Update mkinitcpio.conf
# vim /etc/mkinitcpio.conf
# MODULES=(btrfs)
# HOOKS=(... block lvm2 filesystems ...)
arch-chroot $my_root_mount sed -i \
    -e 's/MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf \
    -e 's/block filesystems fsck/block lvm2 filesystems fsck grub-btrfs-overlayfs/' \
    /etc/mkinitcpio.conf
arch-chroot $my_root_mount mkinitcpio -p linux

# Add a user account
arch-chroot $my_root_mount useradd -mG wheel -p $my_password_hash $my_user_id

# ToDo: Clean this section up
# Install KDE Plasma and sddm
arch-chroot $my_root_mount pacman -S --needed --noconfirm xorg sddm
arch-chroot $my_root_mount pacman -S --needed --noconfirm plasma kde-applications
arch-chroot $my_root_mount systemctl enable sddm

# Apply the Breeze theme to sddm
arch-chroot $my_root_mount mkdir /etc/sddm.conf.d/
arch-chroot $my_root_mount  sed 's/Current=/Current=breeze/;w /etc/sddm.conf.d/sddm.conf' /usr/lib/sddm/sddm.conf.d/default.conf

# Add some useful applications
arch-chroot $my_root_mount pacman -S --noconfirm tree wireshark-qt ttf-0xproto-nerd ttf-cascadia-code-nerd ttf-cascadia-mono-nerd ttf-firacode-nerd ttf-hack-nerd ttf-jetbrains-mono-nerd ttf-sourcecodepro-nerd curl plocate btop htop fastfetch tmux tldr zellij git eza bat xrdp mc vifm tldr fzf

# Finish configuring snapper
arch-chroot $my_root_mount pacman -S --noconfirm snapper snap-pac inotify-tools
#arch-chroot $my_root_mount btrfs subvolume delete /.snapshots/
#arch-chroot $my_root_mount snapper -c root create-config /
#arch-chroot $my_root_mount snapper list-configs
#arch-chroot $my_root_mount snapper -c root set-config ALLOW_GROUPS="wheel" SYNC_ACL=yes
#arch-chroot $my_root_mount sed -i 's/PRUNENAMES = ".git .hg .svn"/PRUNENAMES = ".git .hg .svn .snapshots"/' /etc/updatedb.conf

# Configure GRUB for snapshot recovery
arch-chroot $my_root_mount sed -i 's/GRUB_DISABLE_RECOVERY=true/GRUB_DISABLE_RECOVERY=false/' /etc/default/grub
arch-chroot $my_root_mount grub-mkconfig -o /boot/grub/grub.cfg
arch-chroot $my_root_mount systemctl enable grub-btrfsd
arch-chroot $my_root_mount systemctl enable snapper-boot.timer

# /etc/updatedb.conf
# PRUNENAMES = ".snapshots"

# Finish and reboot
# exit
# umount -a
# systemctl reboot
echo Script finished! Please use arch-chroot to set a root password, unmount all and reboot.


# Log on as a regular user

# Install an AUR helper
# sudo pacman -S --needed base-devel git
# git clone https://aur.archlinux.org/yay.git
# pushd yay
# makepkg -si
# popd
# yay -S brave-bin btrfs-assistant ttf-ms-fonts
