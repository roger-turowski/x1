#!/usr/bin/bash

# See https://github.com/walian0/bashscripts/blob/main/arch_plasma_auto.bash

# General Notes
# =============
# This build script currently only supports UEFI systems
# The script creates a BTRFS root partition with multiple subvolumes
# A separate home partition is created using xfs
# Snapper is installed but not enabled by default. A post-install script is created to enable it.
# The script creates a user account and a post-install script to install yay and AUR packages.
# The script creates a post-install script to install Flatpak applications.
# The script installs KDE Plasma as the desktop environment with SDDM as the display manager.
# The script detects if running on a hypervisor and installs the appropriate guest additions.
# The script detects Intel and AMD CPUs and installs the appropriate micro-code firmware.

# To-do:
# - Add logging of all commands to evaluate after installation
# - Add network configuration steps (Wi-Fi, static IP, etc.)
# - Add CPU micro-code installation for ARM CPUs
# - Add graphics driver installation based on detected GPU
# - Add option to select desktop environment during installation
# - Add LUKS encryption support
# - Clean-up and optimize the script
# - Add more comments to explain each section
# - Add error handling for each major step
# - Test on real hardware and different VM platforms
# - Add support for other desktop environments
# - Add support for different filesystems (XFS, ext4, etc.) 
# - Add support for different partition schemes (MBR, etc.)



# Virtualbox Guest Notes
# ======================
# Create a disk image at least 128GB in size.
# Enable EFI.
# Assign a VBoxSVGA video adapter to use Wayland, else a black screen will appear.
# Use a Bridged network adapter so ssh can be used for installation and troubleshooting.
# Set a root password immediately to enable connecting via ssh


set -euo pipefail

# =============================================================================
# Initialize "constants" for the script"
# =============================================================================
# Logging
readonly LOG_FILE="/var/log/arch-install.log"
readonly VERBOSE="${VERBOSE:-false}"
# User and locale
readonly my_timezone="US/Michigan"
readonly my_root_mount="/mnt"
readonly my_host_name="arch"
readonly my_user_id="roger"
readonly my_full_name="Roger Turowski"
# Colors for console output
readonly success_color="\e[1;32m"
readonly error_color="\e[1;31m"
readonly warning_color="\e[1;33m"
readonly info_color="\e[1;34m"
readonly no_color="\e[0m"
# Mount options for BTRFS subvolumes
readonly MOUNTOPTS="noatime,ssd,space_cache=v2,compress=zstd,discard=async"
# Options for pacman 
readonly pacman_conf="/etc/pacman.conf"
readonly pacman_mirrorlist="/etc/pacman.d/mirrorlist"
readonly pacman_parallel_downloads=7
readonly pacman_color_output=true
readonly reflector_conf="/etc/xdg/reflector/reflector.conf"
# Application configuration files
readonly snapper_conf="/etc/snapper/configs/root" 
readonly updatedb_conf="/etc/updatedb.conf"
# Packages to install
pacstrap_pkgs=(
  # Packages to install using pacstrap. Omit CPU firmware since we will detect the CPU type and add it later
  base
  base-devel
  bash-completion
  bat
  btop
  btrfs-progs
  cmatrix
  cowsay
  cryptsetup
  dnsmasq
  dosfstools
  e2fsprogs
  eza
  fastfetch
  fzf
  git
  grub-btrfs
  htop
  inetutils
  ipset
  linux
  linux-firmware
  linux-headers
  linux-lts
  linux-lts-headers
  mc
  nano
  networkmanager
  nmap
  nvim
  openbsd-netcat
  openssh
  os-prober
  plocate
  reflector
  rsync
  sudo
  tmux
  util-linux
  vifm
  vim
  whois
  zellij
  zsh
  zsh-completions
)
readonly gui_pkgs=(
  # Packages to install for the GUI environment
  acpi
  acpi_call
  acpid
  alacritty
  alsa-firmware
  alsa-utils
  archlinux-wallpaper
  avahi
  bluez
  bluez-utils
  calibre
  code
  cups
  dialog
  dnsutils
  edk2-ovmf
  efibootmgr
  firewalld
  flatpak
  gimp
  gvfs
  gvfs-smb
  inkscape
  kitty
  libreoffice-fresh
  lvm2
  meld
  mtools
  network-manager-applet
  nfs-utils
  nss-mdns
  ntfs-3g
  pulseaudio
  scribus
  sof-firmware
  strawberry
  terminus-font
  tlp
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
  vlc
  wireshark-qt
  wpa_supplicant
  xdg-user-dirs
  xdg-utils
)
# =============================================================================
# Function Definitions
# =============================================================================
error_result() {
	# [   OK   ]
  # [  ERR   ]
  # [  WARN  ]
  # [  INFO  ]
  echo -e "[   ${error_color}ERR${no_color}    ] $1"
	exit 1
}
ok_result() {
	echo -e "[    ${success_color}OK${no_color}    ] $1"
}
warning_result() {
	echo -e "[  ${warning_color}WARN${no_color}   ] $1"
  read -p -r "Press the Enter key to continue"
}
info_result() {
	echo -e "[   ${info_color}INFO${no_color}   ] $1"
}
check_for_root() {
  # Ensure the script is being run by root
  if [[ "$UID" -ne 0 ]]; then
    error_result "This script must be run as root!"
  fi
}
_log() {
  # =============================================================================
  # _log
  # -----------------------------------------------------------------------------
  # Writes timestamped log messages to stderr and optionally to a log file.
  #
  # Arguments:
  #   $1 - Log level (INFO, WARN, ERROR, DEBUG)
  #   $2 - Message text
  #
  # Environment:
  #   LOG_FILE - If set, messages are also appended to this file
  # =============================================================================
  local level="$1"
  shift
  local msg="$*"
  local timestamp
  timestamp="$(date -u +%FT%TZ)"

  local line="${timestamp} [${level}] ${msg}"

  echo "$line" >&2

  if [[ -n "${LOG_FILE:-}" ]]; then
      echo "$line" >> "$LOG_FILE"
  fi
}
log_info()  { _log "INFO"  "$@"; }
log_warn()  { _log "WARN"  "$@"; }
log_error() { _log "ERROR" "$@"; }
log_debug() {
    [[ "$VERBOSE" == "true" ]] || return 0
    _log "DEBUG" "$@"
}
configure_pacman_preinstall() {
  # =============================================================================
  # configure_pacman_preinstall
  # -----------------------------------------------------------------------------
  # Configure color output for pacman and specify number of parallel downloads
  #
  # Arguments:
  #   $1 - Path to the pacman.conf file (default: /etc/pacman.conf)
  #   $2 - Number of parallel downloads (default: 7)
  #   $3 - Enable color output (default: true)
  #
  # Output:
  #   None (stdout is silent on success)
  #
  # Returns:
  #   0 - Success
  #   1 - Error (if the pacman.conf file does not exist or is not writable)
  #==============================================================================
  local pacman_conf_local="${1:-/etc/pacman.conf}"
  local parallel_downloads="${2:-7}"
  local enable_color="${3:-true}"

  if [[ ! -f "$pacman_conf_local" ]]; then
    error_result "Pacman configuration file not found: $pacman_conf"
  fi

  if [[ ! -w "$pacman_conf_local" ]]; then
    error_result "Pacman configuration file is not writable: $pacman_conf"
  fi

  if [[ "$enable_color" == true ]]; then
    sed -i 's/#Color/Color/' "$pacman_conf_local"
  else
    sed -i 's/Color/#Color/' "$pacman_conf"
  fi

  sed -i "s/ParallelDownloads = [0-9]\+/ParallelDownloads = $parallel_downloads/" "$pacman_conf_local"

  ok_result "Pacman pre-install configuration updated successfully."
}
teardown_existing_mappings() {
    # Mapper devices are stacked—close the top layer first, then the bottom
    local disk="$1"

    log_info "Tearing down existing mappings on ${disk}"

    # 1. Deactivate LVM volume groups on this disk
    #    vgchange deactivates all LVs in a VG, closing the /dev/mapper entries
    local vg
    for vg in $(vgs --noheadings --separator ' ' 2>/dev/null | awk '{print $1}'); do
        # Check if this VG lives on the target disk
        if pvs --noheadings 2>/dev/null | grep -q "$disk"; then
            log_info "Deactivating volume group: ${vg}"
            vgchange -an "$vg" || return 1
        fi
    done

    # 2. Close LUKS containers on this disk
    local luks_dev
    for luks_dev in $(lsblk -ln -o NAME,TYPE "$disk" 2>/dev/null | awk '$2 == "crypt" {print $1}'); do
        log_info "Closing LUKS container: ${luks_dev}"
        cryptsetup close "$luks_dev" || return 1
    done

    # 3. Unmount anything still hanging on
    local mountpoint
    for mountpoint in $(lsblk -ln -o MOUNTPOINT "$disk" 2>/dev/null | grep -v '^$'); do
        log_info "Unmounting ${mountpoint}"
        umount -R "$mountpoint" 2>/dev/null || true
    done

    log_info "Mapping teardown complete for ${disk}"
}
wipe_disk_signatures() {
  # Now wipe the physical disk cleanly after teardown:
  local disk="$1"

  # Validate
  if [[ ! -b "$disk" ]]; then
    log_error "${disk} is not a block device"
    return 1
  fi

  # Tear down existing LUKS/LVM layers first
  teardown_existing_mappings "$disk"

  # Wipe each partition
  local partition
  for partition in "${disk}"?*; do
    [[ -b "$partition" ]] || continue
    log_info "Wiping ${partition}"
    wipefs --all --force "$partition" || return 1
  done

  # Wipe the main device (partition table + GPT/MBR headers)
  log_info "Wiping ${disk}"
  wipefs --all --force "$disk" || return 1

  # Zap the MBR/GPT entirely for a truly clean slate
  sgdisk --zap-all "$disk" 2>/dev/null || true

  log_info "Disk ${disk} wiped clean"
}

# =============================================================================
# main script execution starts here
# =============================================================================
check_for_root
configure_pacman_preinstall "${pacman_conf}" "${pacman_parallel_downloads}" "${pacman_color_output}"

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
  no ) error_result "Cancelled by user to preserve the current disk layout.";;
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
  echo "my_disk: $my_disk"
  echo "my_partition_efi: $my_partition_efi"
  echo "my_partition_root: $my_partition_root"
else
  error_result "Invalid disk was selected: $install_disk"
fi

# Make a password hash here with mkpasswd and assign to my_password_hash at runtime
# Generate a salt for the password hash
# my_salt=$(tr -dc '0-9a-zA-Z' < /dev/urandom | head -c 16)
my_salt=$(tr -dc '0-9a-zA-Z' </dev/urandom | head -c16 || true)

echo "Create a password for $my_user_id"
my_password_hash=$(mkpasswd -m sha-512 --salt="$my_salt")

echo "Enter the password again to confirm"
my_password_hash_confirmed=$(mkpasswd -m sha-512 --salt="$my_salt")

case $my_password_hash in
	"$my_password_hash_confirmed")
		ok_result "Password confirmed"
		;;
	*)
		error_result "Password not confirmed"
		;;
esac

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

# Detect if running on a hypervisor and install the correct additions
if (grep -q "^flags.* hypervisor" "/proc/cpuinfo"); then
  info_result "Hypervisor is detected"
  my_hypervisor_manufacturer=$(dmidecode -t system | grep 'Manufacturer' | cut -c 16-)
  my_hypervisor_product=$(dmidecode -t system | grep 'Product' | cut -c 16-)
  info_result "Hypervisor Manufacturer is: $my_hypervisor_manufacturer"
  info_result "Hypervisor Product is: $my_hypervisor_product"
  case "$my_hypervisor_product" in
    "VirtualBox")
      echo "Running on VirtualBox"
      pacstrap_pkgs+=("virtualbox-guest-utils")
      ;;
    "VMware Virtual Platform")
      echo "Running on VMware"
      pacstrap_pkgs+=("open-vm-tools")
      ;;
    *)
      case "$my_hypervisor_manufacturer" in
        "VMware, Inc.")
          echo "Running on VMware"
          pacstrap_pkgs+=("open-vm-tools")
          ;;
        "QEMU")
          echo "Running on QEMU"
          pacstrap_pkgs+=("qemu-guest-agent")
          ;;
        *)
          echo "Running on unknown hypervisor"
          ;;
      esac
  esac
fi

# Configure keyboard
localectl set-keymap us

# Set-up Wi-Fi connection example:
# iwctl adapter list
# iwctl station wlan0 get-networks
# iwbtl station wlan0 connect <network_name>
# ip a
# ping -c 4 archlinux.org

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
# Deactivate ALL volume groups
# vgchange -an

teardown_existing_mappings "$my_disk"

# Removes all active device mapper devices
dmsetup remove_all

# Stop RAID arrays (if any)
mdadm --stop --scan

# 1. Aggressively wipe all signatures (filesystem, raid, partition table)
# wipefs --all --force "$my_disk"
wipe_disk_signatures "$my_disk"

# 2. Destroy GPT headers (Primary AND Backup) explicitly
# sgdisk --zap-all "$my_disk"

# 3. Force the kernel to drop the device and re-scan
# This simulates unplugging/replugging the drive without rebooting
# echo 1 > /sys/block/sda/device/delete
# echo "- - -" > /sys/class/scsi_host/host0/scan 
# NOTE: Replace 'host0' with your actual host number found via: ls /sys/class/scsi_host/

# Clean the ssd disk using blkdiscard
# Found blkdiscard fails on VMware guest disks
#blkdiscard "$my_disk"

# Inform the OS of partition table changes
partprobe "$my_disk"

# PHYSICAL PARTITIONS

# Create the physical EFI partition
sgdisk --new=1:0:+4G --typecode=1:ef00 --change-name=1:EFI "$my_disk"

# Create the physical partition for root, swap and home
sgdisk --new=2:0:0 --typecode=2:8e00 --change-name=2:root "$my_disk"

# Display a disk summary
partprobe -s "$my_disk"

# PHYSICAL VOLUMES

# Create a physical volume to contain the volume group "system"
pvcreate -ff "$my_partition_root"

# VOLUME GROUPS

# Create the volume group for root, swap and home
vgcreate system "$my_partition_root"

# LOGICAL VOLUMES 

# Create the logical volumes for root, swap and home
lvcreate -l 40%FREE -n root system
lvcreate -L 8G -n swap system
lvcreate -l 100%FREE -n home system

# FORMAT THE PARTITIONS

# Format the EFI partition
mkfs.fat -n EFI -F32 "$my_partition_efi"

# Format the root volume with BTRFS
mkfs.btrfs -f -L root /dev/system/root

# Format the home volume with xfs
mkfs.xfs -f -L home /dev/system/home

# Create swap space
wipefs --all --force /dev/system/swap
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
arch-chroot $my_root_mount sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
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

# Enable color output for pacman and specify the number of parallel downloads
arch-chroot $my_root_mount sed -i 's/#Color/Color/;s/ParallelDownloads = 5/ParallelDownloads = 7/' "/etc/pacman.conf"

# Install the gui packages
arch-chroot $my_root_mount pacman -Sy "${gui_pkgs[@]}" --noconfirm --quiet

# Install and configure GRUB for normal and LTS kernels
arch-chroot /mnt /usr/bin/env bash << 'CHROOT_EOF'
  export LANG=C
  set -e

  # Install GRUB
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

  # Configure GRUB the first time to ensure entries are created for both the normal and LTS kernels
  grub-mkconfig -o /boot/grub/grub.cfg

  # Extract submenu and entry IDs (sed-based, no PCRE needed)
  SUBMENU_ID=$(grep "^submenu" /boot/grub/grub.cfg | head -1 | sed -n "s/.*menuentry_id_option '\([^']*\)'.*/\1/p")
  ENTRY_ID=$(grep "menuentry .*with Linux linux'" /boot/grub/grub.cfg | head -1 | sed -n "s/.*menuentry_id_option '\([^']*\)'.*/\1/p")

  # Apply GRUB_DEFAULT
  sed -i "s/^GRUB_DEFAULT=.*/GRUB_DEFAULT=\"${SUBMENU_ID}>${ENTRY_ID}\"/" /etc/default/grub
  
  # Configure custom GRUB colors
  sed -i 's/^#GRUB_COLOR_NORMAL=.*/GRUB_COLOR_NORMAL="cyan\/blue"/' /etc/default/grub
  sed -i 's/^#GRUB_COLOR_HIGHLIGHT=.*/GRUB_COLOR_HIGHLIGHT="light-cyan\/black"/' /etc/default/grub 
  
  # Rebuild GRUB configuration to apply the new default entry
  grub-mkconfig -o /boot/grub/grub.cfg

  echo "Done. GRUB_DEFAULT=${SUBMENU_ID}>${ENTRY_ID}"
CHROOT_EOF

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
  acpid

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
arch-chroot $my_root_mount useradd -c "$my_full_name" -mG wheel -s /usr/bin/zsh -p "$my_password_hash" $my_user_id

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
  echo -e 'yay --noconfirm -S brave-bin btrfs-assistant oh-my-posh plymouth ttf-ms-fonts';
} >> $my_root_mount/home/$my_user_id/Scripts/enable_yay.sh

# Enable oh-my-posh in zsh
echo -e "\neval \"\$(oh-my-posh init zsh)\"" >> "$my_root_mount/home/$my_user_id/.zshrc";
arch-chroot $my_root_mount chown $my_user_id:$my_user_id /home/$my_user_id/.zshrc

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

sync
umount $my_root_mount

echo Script finished! Please reboot.
