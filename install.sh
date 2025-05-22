#!/usr/bin/bash

# See https://github.com/walian0/bashscripts/blob/main/arch_plasma_auto.bash

# General Notes
# =============
# This build script currently only supports UEFI systems

# Virtualbox Guest Notes
# ======================
# Enable EFI.
# Assign a VBoxSVGA video adapter to use Wayland, else a black screen will appear.
# Use a Bridged network adapter so ssh can be used for installation and troubleshooting.
# Set a root password to enable connecting via ssh

# Error handling

set -eu

success_color="\e[1;32m"
error_color="\e[1;31m"
warning_color="\e[1;33m"
info_color="\e[1;34m"
no_color="\e[0m"

error_result() {
	# [     OK     ]
  # [   ERROR    ]
  # [  WARNING   ]
  # [    INFO    ]
  echo -e "[   ${error_color}ERR$${no_color}    ] $1"
	exit 1
}

ok_result() {
	echo -e "[     ${success_color}OK${no_color}     ] $1"
}

warning_result() {
	echo -e "[  ${warning_color}WARN${no_color}   ] $1"
  read -p -r "Press the Enter key to continue"
}

info_result() {
	echo -e "[    ${info_color}INFO${no_color}   ] $1"
}

# Ensure the script is being run by root
if [[ "$UID" -ne 0 ]]; then
  error_result "This script must be run as root!"
fi

# Initialize variables
my_timezone="US/Michigan"
my_root_mount="/mnt"
my_host_name="arch"
my_user_id="roger"
my_full_name="Roger Turowski"

# Enable color output for pacman and increase number of parallel downloads
sed -i 's/#Color/Color/;s/ParallelDownloads = 5/ParallelDownloads = 8/' "/etc/pacman.conf"

command -v mkpasswd >/dev/null 2>&1 || {
   echo >&2 "Installing mkpasswd (part of the whois package.)";
   pacman --noconfirm -S whois; 
}

echo "List of disks available:"
lsblk -d -e 11 -e 7 -o name,size
read -r -p "Disk to install to: " install_disk

if [ -e "/dev/$install_disk" ]; then
    info_result "Disk $install_disk exists."
else
    error_result "Disk does not exist: $install_disk"
fi

read -r -p "Proceed with installation to $install_disk? [yes/no] " disk_confirmation
case $disk_confirmation in
    yes ) echo Proceeding...;;
    no ) error_result "Cancelled by user.";;
    * ) error_result "Unable to proceed due to an invalid response";;
esac

if [[ "$install_disk" =~ ^nvme[0-3]n[0-3]$ ]]; then
  echo "Installing to nvme disk $install_disk"
  my_disk="/dev/$install_disk"
  my_partition_efi="/dev/${install_disk}p1"
  my_partition_root="/dev/${install_disk}p2"
elif [[ "$install_disk" =~ ^sd[a-z]$ ]]; then
  echo "Installing to SATA disk $install_disk"
  my_disk="/dev/$install_disk"
  my_partition_efi="/dev/${install_disk}1"
  my_partition_root="/dev/${install_disk}2"
else
  error_result "Invalid disk was selected: $install_disk"
fi

# Make a password hash here with mkpasswd and assign to my_password_hash at runtime
echo "Create a password for $my_user_id"
my_password_hash=$(mkpasswd -m sha-512)

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
if (grep -m 1 "GenuineIntel" "/proc/cpuinfo"); then
  cpu_firmware="intel-ucode"
  ok_result "Intel CPU was found"
  pacstrap_pkgs+=("$cpu_firmware")
elif (grep -m 1 "AuthenticAMD" "/proc/cpuinfo"); then
  cpu_firmware="amd-ucode"
  ok_result "AMD CPU was found"
  pacstrap_pkgs+=("$cpu_firmware")
else
  info_result "No CPU micro-code is available for this CPU."
fi

gui_pkgs=(
  acpi
  acpi_call
  acpid
  alacritty
  alsa-utils
  archlinux-wallpaper
  avahi
  base-devel
  bash-completion
  bat
  bluez
  bluez-utils
  bridge-utils
  btop
  calibre
  cmatrix
  code
  cowsay
  cups
   dialog
  dnsmasq
  dnsutils
   edk2-ovmf
  efibootmgr
  eza
  fastfetch
  firewalld
  flatpak
  fzf
  gimp
  gvfs
  gvfs-smb
  htop
  inkscape
  inetutils
  ipset
  kitty
  libreoffice-fresh
  linux-headers
  lvm2
  mc
  meld
  mtools
  network-manager-applet
  nfs-utils
  nmap
  nss-mdns
  ntfs-3g
  nvim
  openbsd-netcat
  openssh
  os-prober
  plocate
  pulseaudio
  reflector
  rsync
  scribus
  sof-firmware
  strawberry
  terminus-font
  tldr
  tlp
  tmux
  tree
  ttf-0xproto-nerd
  ttf-cascadia-code-nerd
  ttf-cascadia-mono-nerd
  ttf-firacode-nerd
  ttf-hack-nerd
  ttf-jetbrains-mono-nerd
  ttf-liberation-mono-nerd
  ttf-meslo-nerd
  ttf-mononoki-nerd
  ttf-nerd-fonts-symbols-mono
  ttf-noto-nerd
  ttf-roboto-mono-nerd
  ttf-sourcecodepro-nerd
  ttf-terminus-nerd
  ttf-ubuntu-mono-nerd
  vde2
  vifm
  vlc
  whois
  wireshark-qt
  wpa_supplicant
  xdg-user-dirs
  xdg-utils
  zellij
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
reflector -c us -p https --age 6 --number 5 --latest 8 --sort rate --verbose --save /etc/pacman.d/mirrorlist

# Install tools useful during setup
pacman --noconfirm -Sy fastfetch git tree bat tldr tmux nano

# Clear the disk
sgdisk --zap-all --clear "$my_disk"

# PHYSICAL PARTITIONS

# Create the physical EFI partition
sgdisk --new=1:0:+4G --typecode=1:ef00 --change-name=1:EFI "$my_disk"

# Create the physical partition for root, swap and home
sgdisk --new=2:0:0 --typecode=2:8e00 --change-name=2:root "$my_disk"

# Display a disk summary
partprobe -s "$my_disk"

# PHYSICAL VOLUMES

# Create a physical volume to contain the volume group "system"
pvcreate "$my_partition_root"

# VOLUME GROUPS

# Create the volume group for root, swap and home
vgcreate system "$my_partition_root"

# LOGICAL VOLUMES 

# Create the logical volumes for root, swap and home
lvcreate -l 30%FREE -n root system
lvcreate -L 2G -n swap system
lvcreate -l 100%FREE -n home system

# FORMAT THE PARTITIONS

# Format the EFI partition
mkfs.fat -n EFI -F32 "$my_partition_efi"

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
mount "$my_partition_efi" "$my_root_mount/boot/efi"

# Mount the home partition
mkdir -p $my_root_mount/home
mount /dev/mapper/system-home $my_root_mount/home

# Install base packages. "-K" tells pacstrap to generate a new pacman master key
pacstrap $my_root_mount "${pacstrap_pkgs[@]}"

# Generate the File System TABle (fstab) using UUID numbers
genfstab -U $my_root_mount >> $my_root_mount/etc/fstab

# Begin arch-chroot operations

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
# arch-chroot $my_root_mount echo root:change-me | chpasswd

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
SUDOER_TMP=$(mktemp)
cat $my_root_mount/etc/sudoers > "$SUDOER_TMP"
sed -i -e 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$SUDOER_TMP"
visudo -c -f "$SUDOER_TMP" && cat "$SUDOER_TMP" > "$my_root_mount/etc/sudoers"
rm "$SUDOER_TMP"

# Update mkinitcpio.conf
arch-chroot $my_root_mount sed -i \
    -e 's/MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf \
    -e 's/block filesystems fsck/block lvm2 filesystems fsck grub-btrfs-overlayfs/' \
    /etc/mkinitcpio.conf
arch-chroot $my_root_mount mkinitcpio -p linux

# Add a user account
arch-chroot $my_root_mount useradd -c "$my_full_name" -mG wheel -p "$my_password_hash" $my_user_id

# ToDo: Clean this section up
# Install KDE Plasma and sddm
arch-chroot $my_root_mount pacman -S --needed --noconfirm xorg sddm
arch-chroot $my_root_mount pacman -S --needed --noconfirm plasma kde-applications
arch-chroot $my_root_mount systemctl enable sddm

# Apply the Breeze theme to sddm
mkdir $my_root_mount/etc/sddm.conf.d/
arch-chroot $my_root_mount sed 's/Current=/Current=breeze/;w /etc/sddm.conf.d/sddm.conf' /usr/lib/sddm/sddm.conf.d/default.conf

# Install snapper
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

# Allow root to have ssh access initially for troubleshooting while developing
arch-chroot $my_root_mount sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Create post-install scripts for root
mkdir $my_root_mount/root/Scripts
arch-chroot $my_root_mount touch /root/Scripts/enable_snapper_snapshots.sh
arch-chroot $my_root_mount chmod +x /root/Scripts/enable_snapper_snapshots.sh
{ echo -e '#!/usr/bin/bash';
  echo -e 'btrfs subvolume delete /.snapshots/';
  echo -e 'snapper -c root create-config /';
  echo -e 'snapper -c root set-config ALLOW_GROUPS="wheel" SYNC_ACL=yes';
  echo -e "sed -i 's/PRUNENAMES = \".git .hg .svn\"/PRUNENAMES = \".git .hg .svn .snapshots\"/' /etc/updatedb.conf";
  echo -e 'snapper list-configs';
} >> $my_root_mount/root/Scripts/enable_snapper_snapshots.sh

# Create post install scripts for $my_user_id
arch-chroot $my_root_mount mkdir /home/$my_user_id/Scripts/
arch-chroot $my_root_mount touch /home/$my_user_id/Scripts/enable_yay.sh
arch-chroot $my_root_mount chmod +x /home/$my_user_id/Scripts/enable_yay.sh
{ echo -e '#!/usr/bin/bash';
  echo -e 'git clone https://aur.archlinux.org/yay.git';
  echo -e 'pushd yay';
  echo -e 'makepkg -si';
  echo -e 'popd';
  echo -e 'yay -S brave-bin btrfs-assistant plymouth ttf-ms-fonts';
} >> $my_root_mount/home/$my_user_id/Scripts/enable_yay.sh

arch-chroot $my_root_mount touch /home/$my_user_id/Scripts/install_flatpak_apps.sh
arch-chroot $my_root_mount chmod +x /home/$my_user_id/Scripts/install_flatpak_apps.sh
{ echo -e flatpak install -y --noninteractive flathub dev.bragefuglseth.Keypunch
  echo -e flatpak install -y --noninteractive flathub net.cozic.joplin_desktop
  echo -e flatpak install -y --noninteractive flathub org.deluge_torrent.deluge
  echo -e flatpak install -y --noninteractive flathub com.github.sixpounder.GameOfLife
  echo -e flatpak install -y --noninteractive flathub io.github.giantpinkrobots.flatsweep
  echo -e flatpak install -y --noninteractive flathub io.github.shiftey.Desktop
  echo -e flatpak install -y --noninteractive flathub com.sweethome3d.Sweethome3d
  echo -e flatpak install -y --noninteractive flathub org.kicad.KiCad
  echo -e flatpak install -y --noninteractive flathub com.obsproject.Studio
  echo -e flatpak install -y --noninteractive flathub com.github.artemanufrij.regextester
  echo -e flatpak install -y --noninteractive flathub org.remmina.Remmina
  echo -e flatpak install -y --noninteractive flathub org.stellarium.Stellarium
  echo -e flatpak install -y --noninteractive flathub com.adrienplazas.Metronome
  echo -e flatpak install -y --noninteractive flathub io.github.nokse22.inspector
  echo -e flatpak install -y --noninteractive flathub dev.bragefuglseth.Fretboard
} >> $my_root_mount/home/$my_user_id/Scripts/install_flatpak_apps.sh

arch-chroot $my_root_mount chown --recursive $my_user_id:$my_user_id /home/$my_user_id/Scripts

# Create a directory for AppImages
arch-chroot $my_root_mount mkdir /home/$my_user_id/AppImages/

clear
# Copy this script to the root home directory
cp install.sh $my_root_mount/root/Scripts

echo -e "${success_color}Please set a password for the new root account:${no_color}"
arch-chroot $my_root_mount passwd root
echo Script finished! Please unmount all and reboot.

sync