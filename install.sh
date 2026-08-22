#!/usr/bin/env bash
# region - Notes
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

# Set-up Wi-Fi connection example:
  # iwctl adapter list
  # iwctl station wlan0 get-networks
  # iwbtl station wlan0 connect <network_name>
  # ip a
  # ping -c 4 archlinux.org

# endregion
set -euo pipefail
# =============================================================================
# region - Variables
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
# readonly error_color="\e[1;31m"
# readonly warning_color="\e[1;33m"
# readonly info_color="\e[1;34m"
readonly no_color="\e[0m"
# Mount options for BTRFS subvolumes
readonly MOUNTOPTS="noatime,ssd,space_cache=v2,compress=zstd,discard=async"
# Options for pacman 
readonly pacman_conf="/etc/pacman.conf"
readonly pacman_mirrorlist="/etc/pacman.d/mirrorlist"
readonly pacman_parallel_downloads=7
readonly pacman_color_output=true
# readonly reflector_conf="/etc/xdg/reflector/reflector.conf"
# Application configuration files
# readonly snapper_conf="/etc/snapper/configs/root" 
# readonly updatedb_conf="/etc/updatedb.conf"
# Packages to install
readonly preinstall_pkgs=(
  # Packages to install before the main installation
  whois
)
readonly pacstrap_pkgs=(
  # Packages to install using pacstrap. Must not be readonly.
  # Omit CPU firmware since we will detect the CPU type and add it later.
  acpi
  acpi_call
  acpid
  alsa-firmware
  alsa-utils
  avahi
  base
  base-devel
  bash-completion
  bat
  bluez
  bluez-utils
  btop
  btrfs-progs
  cmatrix
  cowsay
  cryptsetup
  cups
  dialog
  dnsmasq
  dnsutils
  dosfstools
  e2fsprogs
  edk2-ovmf
  efibootmgr
  eza
  fastfetch
  firewalld
  flatpak
  fzf
  git
  grub
  grub-btrfs
  htop
  inetutils
  ipset
  linux
  linux-firmware
  linux-headers
  linux-lts
  linux-lts-headers
  lvm2
  mc
  mtools
  nano
  networkmanager
  nfs-utils
  nss-mdns
  ntfs-3g
  nmap
  nvim
  openbsd-netcat
  openssh
  os-prober
  plocate
  reflector
  rsync
  sof-firmware
  sudo
  terminus-font
  thin-provisioning-tools
  tlp
  tmux
  util-linux
  vde2
  vifm
  vim
  whois
  wpa_supplicant
  xdg-utils
  zellij
  zsh
  zsh-completions
)
readonly podman_pkgs=(
  # Podman related packages
  podman
  buildah 
  fuse-overlayfs # For podman rootless containers
  podman-docker
  podlet # For podman 
  podman-compose
  skopeo # image building and transferring
)
readonly gui_pkgs=(
  # Packages to install for the GUI environment
  alacritty
  archlinux-wallpaper
  calibre
  code
  gimp
  gvfs
  gvfs-smb
  inkscape
  kitty
  libreoffice-fresh
  meld
  network-manager-applet
  pulseaudio
  scribus
  strawberry
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
  vlc
  wireshark-qt
  xdg-user-dirs
)
readonly services_to_enable=(
  # Services to enable after installation
  NetworkManager
  bluetooth
  cups.service
  sshd
  avahi-daemon
  tlp
  reflector.timer
  fstrim.timer
  firewalld
  acpid
)
#endregion - Variables
# =============================================================================
# region - Function Definitions
# =============================================================================
check_for_root() {
  # Ensure the script is being run by root
  if [[ "$UID" -ne 0 ]]; then
    log_error  "This script must be run as root!"
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
log_info()  {
  _log "INFO"  "$@"; 
}
log_warn()  {
  _log "WARN"  "$@";
}
log_error() {
   _log "ERROR" "$@"
   exit 1
}
log_debug() {
    [[ "$VERBOSE" == "true" ]] || return 0
    _log "DEBUG" "$@"
}
configure_pacman_preinstallation() {
  # =============================================================================
  # configure_pacman_preinstallation
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
    log_error "Pacman configuration file not found: pacman_conf_local"
  fi

  if [[ ! -w "$pacman_conf_local" ]]; then
    log_error "Pacman configuration file is not writable: $pacman_conf_local"
  fi

  if [[ "$enable_color" == true ]]; then
    sed -i 's/#Color/Color/' "$pacman_conf_local"
  else
    sed -i 's/Color/#Color/' "$pacman_conf_local"
  fi

  sed -i "s/ParallelDownloads = [0-9]\+/ParallelDownloads = $parallel_downloads/" "$pacman_conf_local"

  log_info "Pacman pre-install configuration updated successfully."
}
ask_install_de_native() {
  PS3="Select an option: "
  options=("Yes, install Desktop Environment" "No, skip Desktop Environment")
  
  select opt in "${options[@]}"; do
    case $opt in
      "Yes, install Desktop Environment")
        return 0
        ;;
      "No, skip Desktop Environment")
        return 1
        ;;
      *) 
        echo "Invalid option $REPLY";;
    esac
  done
}
ask_install_podman_pkgs() {
  PS3="Select an option: "
  options=("Yes, install Podman packages" "No, skip Podman packages")
  
  select opt in "${options[@]}"; do
    case $opt in
      "Yes, install Podman packages")
        return 0
        ;;
      "No, skip Podman packages")
        return 1
        ;;
      *) 
        echo "Invalid option $REPLY";;
    esac
  done
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
install_preinstall_pkgs() {
  local pkgs=("$@")
  log_info "Installing required preinstall packages"
  pacman --needed --noconfirm -Sy "${pkgs[@]}" || {
    log_error "Failed to install required preinstall packages: $*"
  }
  log_info "Required preinstall packages installed successfully"
}
get_install_disk() {
  local disk_confirmation
  local response
  while true; do
    printf 'List of disks available:\n' >&2
    lsblk -d -e 11 -e 7 -o name,size >&2
    read -r -p "Disk to install to: " response

    if [[ -z "$response" ]]; then
      printf 'Input cannot be empty\n' >&2
      continue
    fi

    if [ ! -b "/dev/$response" ]; then
      printf 'Error: Disk %s does not exist\n' "$response" >&2
      continue
    else
      printf 'Disk %s exists\n' "$response" >&2
    fi

    break
  done

  read -r -p "Proceed with installation to $response? [yes/no] " disk_confirmation
  case $disk_confirmation in
    yes ) log_info "Proceeding...";;
    no )  log_error "Cancelled by user to preserve the current disk layout.";;
    * )   log_error "Unable to proceed due to an invalid response";;
  esac
  printf 'Install disk selected is: %s\n' "${response}" >&2
  printf '%s\n' "$response"
}
build_partition_paths() {
  local disk="$1"
  local -n out_disk="$2"
  local -n out_efi="$3"
  local -n out_root="$4"

  # Normalize disk path
  [[ "$disk" != /dev/* ]] && disk="/dev/${disk}"

  # NVMe uses 'p' before partition number: /dev/nvme0n1p1
  # SATA/SCSI does not: /dev/sda1
  local prefix="$disk"
  [[ "$disk" =~ nvme ]] || [[ "$disk" =~ mmc ]] && prefix="${disk}p"

  out_disk="$disk"
  out_efi="${prefix}1"
  out_root="${prefix}2"
  printf 'Partition paths built:\nDisk: %s\nEFI:  %s\nRoot: %s\n' "$out_disk" "$out_efi" "$out_root" >&2
}
make_password_hash() {
  # Make a password hash here with mkpasswd and assign to my_password_hash at runtime
  # Generate a salt for the password hash
  # my_salt=$(tr -dc '0-9a-zA-Z' < /dev/urandom | head -c 16)
  local my_salt
  
  my_salt=$(tr -dc '0-9a-zA-Z' </dev/urandom | head -c16 || true)

  echo "Create a password for $my_user_id"
  my_password_hash=$(mkpasswd -m sha-512 --salt="$my_salt")

  echo "Enter the password again to confirm"
  my_password_hash_confirmed=$(mkpasswd -m sha-512 --salt="$my_salt")

  case $my_password_hash in
    "$my_password_hash_confirmed")
      log_info  "Password confirmed"
      ;;
    *)
     log_error "Password not confirmed"
      ;;
  esac
  printf 'Password hash generated: %s for user %s\n' "$my_password_hash" "$my_user_id" >&2
}
determine_cpu_firmware() {
  # Detect the CPU type to install appropriate firmware
  if (grep -m 1 "GenuineIntel" "/proc/cpuinfo" >&2); then
    log_info "Intel CPU was found"
    printf '%s\n' "intel-ucode"
  elif (grep -m 1 "AuthenticAMD" "/proc/cpuinfo" >&2); then
    log_info "AMD CPU was found"
    printf '%s\n' "amd-ucode"
  else
    log_error "No CPU micro-code is available for this CPU."
  fi
}
determine_hypervisor_packages() {
  # Detect if running on a hypervisor and install the correct additions
  
  local my_hypervisor_manufacturer
  local my_hypervisor_product
  
  if (grep -q "^flags.* hypervisor" "/proc/cpuinfo"); then
    log_info "Hypervisor is detected"
    my_hypervisor_manufacturer=$(dmidecode -t system | grep 'Manufacturer' | cut -c 16-)
    my_hypervisor_product=$(dmidecode -t system | grep 'Product' | cut -c 16-)
    log_info "Hypervisor Manufacturer is: $my_hypervisor_manufacturer"
    log_info "Hypervisor Product is: $my_hypervisor_product"
    case "$my_hypervisor_product" in
      "VirtualBox")
        log_info "Running on VirtualBox"
        printf '%s\n' "virtualbox-guest-utils"
        ;;
      "VMware Virtual Platform")
        log_info "Running on VMware"
        printf '%s\n' "open-vm-tools"
        ;;
      *)
        case "$my_hypervisor_manufacturer" in
          "VMware, Inc.")
            log_info "Running on VMware"
            printf '%s\n' "open-vm-tools"
            ;;
          "QEMU")
            log_info "Running on QEMU"
            printf '%s\n' "qemu-guest-agent"
            ;;
          *)
            log_error "Running on unknown hypervisor"
            ;;
        esac
    esac
  fi
}
configure_time_preinstallation() {
  # Configure the time zone and enable NTP
  local timezone="$1"

  timedatectl set-timezone "$timezone"
  timedatectl set-ntp true
  log_info "Time zone set to $timezone and NTP enabled"
}
create_physical_partitions() {
  local disk="$1"
  local efi_size="$2"
  local root_size="$3"

  log_info "Creating physical partitions on $disk"

  sgdisk \
    --new=1:0:+"${efi_size}"   --typecode=1:ef00 --change-name=1:EFI \
    --new=2:0:+"${root_size}"  --typecode=2:8e00 --change-name=2:root \
    "${disk}" || log_error "Failed to create physical partitions on $disk"

  partprobe "$disk"
  udevadm settle --timeout=10

  # Display a disk summary
  log_info "Disk summary for $my_disk: $(partprobe -s "$my_disk")"
}
create_volume_group() {
  local root_partition="$1"

  # Create a volume group named "system" using the root partition
  vgcreate system "$root_partition" || \
    log_error
}
create_physical_volumes() {
  local root_partition="$1"

  log_info "Creating physical volume on $root_partition"
  # Create a physical volume to contain the volume group "system"
  pvcreate -ff "$root_partition" || \
    log_error "Failed to create physical volume on $root_partition"
}
create_logical_volumes() {
  local root_size="$1"
  local swap_size="$2"
  local home_size="$3"

  log_info "Creating logical volumes on $root_size"

  # Create the logical volumes for root, swap and home
  # lvcreate -l "${root_partition}FREE" -n root system || \
  #  log_error "Failed to create root logical volume"
  lvcreate -L "${root_size}" -n root system || \
    log_error "Failed to create root logical volume"

  lvcreate -L "${swap_size}" -n swap system || \
    log_error "Failed to create swap logical volume"
  
  lvcreate -l "${home_size}FREE" -n home system || \
    log_error "Failed to create home logical volume"
}
format_the_partitions() {
  local my_partition_efi="$1"

  # Format the EFI partition
  mkfs.fat -n EFI -F32 "$my_partition_efi" || \
    log_error "Failed to format EFI partition $my_partition_efi"

  # Format the root volume with BTRFS
  mkfs.btrfs -f -L root /dev/system/root || \
    log_error "Failed to format root logical volume /dev/system/root"

  # Format the home volume with xfs
  mkfs.xfs -f -L home /dev/system/home || \
    log_error "Failed to format home logical volume /dev/system/home"

  # Create swap space
  wipefs --all --force /dev/system/swap || \
    log_error "Failed to wipe swap logical volume /dev/system/swap"
  
  mkswap -L swap /dev/system/swap || \
    log_error "Failed to create swap space on /dev/system/swap"
  
  swapon /dev/system/swap || \
    log_error "Failed to enable swap on /dev/system/swap"
}
create_btrfs_subvolumes() {
  local root_mount="$1"

  log_info "Creating BTRFS subvolumes on $root_mount"

  # Mount the root logical volume
  mount /dev/system/root "${root_mount}" || \
    log_error "Failed to mount root logical volume /dev/system/root to $root_mount"

  # 1. Create the root @ subvolume
  btrfs subvolume create "$root_mount/@" || \
    log_error "Failed to create @ subvolume"

  # 2. Create parent directories for nested subvolumes
  # We only create the PARENTS, not the target subvolume directories themselves.
  # btrfs subvolume create requires the parent directory to exist.
  mkdir "$root_mount/.snapshots" || \
    log_error "Failed to create .snapshots directory in $root_mount"
  mkdir -p "$root_mount/boot/grub2/i386-pc" || \
    log_error "Failed to create boot/grub2/i386-pc directory in $root_mount"
  mkdir -p "$root_mount/boot/grub2/x86_64-efi" || \
    log_error "Failed to create boot/grub2/x86_64-efi directory in $root_mount"
  mkdir "$root_mount/opt" || \
    log_error "Failed to create opt directory in $root_mount"
  mkdir "$root_mount/root" || \
    log_error "Failed to create root directory in $root_mount"
  mkdir "$root_mount/srv" || \
    log_error "Failed to create srv directory in $root_mount"
  mkdir "$root_mount/tmp" || \
    log_error "Failed to create tmp directory in $root_mount"
  mkdir -p "$root_mount/usr/local" || \
    log_error "Failed to create usr/local directory in $root_mount"
  mkdir "$root_mount/var" || \
    log_error "Failed to create var directory in $root_mount"

  # 3. Create the subvolumes
  # Note: The parent directories now exist, so these will succeed.
  btrfs subvolume create "$root_mount/@/.snapshots"
  btrfs subvolume create -p "$root_mount/@/boot/grub2/i386-pc"
  btrfs subvolume create -p "$root_mount/@/boot/grub2/x86_64-efi"
  btrfs subvolume create "$root_mount/@/opt"
  btrfs subvolume create "$root_mount/@/root"
  btrfs subvolume create "$root_mount/@/srv"
  btrfs subvolume create "$root_mount/@/tmp"
  btrfs subvolume create -p "$root_mount/@/usr/local"
  btrfs subvolume create "$root_mount/@/var"

  # Set the No_COW attribute for /var
  chattr +C "$root_mount/@/var" || \
    log_error "Failed to set No_COW attribute on $root_mount/@/var"

  # Unmount the root logical volume
  umount "$root_mount" || \
    log_error "Failed to unmount root logical volume from $root_mount"
}
mount_subvolumes() {
  local root_mount="$1"
  local mount_opts="$2"

  # Options used for all mounts utilizing an SSD
  mount /dev/mapper/system-root "$root_mount" -o subvol=@,"${mount_opts}" || \
    log_error "Failed to mount subvolume @ to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/.snapshots" -o subvol=@/.snapshots,"${mount_opts}" || \
    log_error "Failed to mount subvolume .snapshots to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/boot/grub2/i386-pc" -o subvol=@/boot/grub2/i386-pc,"${mount_opts}" || \
    log_error "Failed to mount subvolume @/boot/grub2/i386-pc to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/boot/grub2/x86_64-efi" -o subvol=@/boot/grub2/x86_64-efi,"${mount_opts}" || \
    log_error "Failed to mount subvolume @/boot/grub2/x86_64-efi to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/opt" -o subvol=@/opt,"${mount_opts}" || \
    log_error "Failed to mount subvolume @/opt to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/root" -o subvol=@/root,"${mount_opts}"|| \
    log_error "Failed to mount subvolume @/root to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/srv" -o subvol=@/srv,"${mount_opts}"|| \
    log_error "Failed to mount subvolume @/srv to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/tmp" -o subvol=@/tmp,"${mount_opts}"|| \
    log_error "Failed to mount subvolume @/tmp to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/usr/local" -o subvol=@/usr/local,"${mount_opts}"|| \
    log_error "Failed to mount subvolume @/usr/local to $my_root_mount"
  mount /dev/mapper/system-root "$root_mount/var" -o subvol=@/var,"${mount_opts}"|| \
    log_error "Failed to mount subvolume @/var to $my_root_mount"
}
mount_partitions() {
  local root_mount="$1"
  local partition_efi="$2"

  log_info "Mounting partitions to $root_mount"

  # Mount the root logical volume with BTRFS subvolume options
  mount -o subvol=@,$MOUNTOPTS /dev/system/root "$root_mount" || \
    log_error "Failed to mount root logical volume /dev/system/root to $root_mount"

  # Mount the EFI partition
  mkdir -p "$root_mount/boot/efi"
  mount "$partition_efi" "$root_mount/boot/efi" || \
    log_error "Failed to mount EFI partition $partition_efi to $root_mount/boot/efi"

  # Mount the home logical volume
  mkdir -p "$root_mount/home"
  mount /dev/system/home "$root_mount/home" || \
    log_error "Failed to mount home logical volume /dev/system/home to $root_mount/home"
}
configure_time_and_locale() {
  local root_mount="$1"
  local timezone="$2"
  local hostname="$3"
  local host_domain="$4"

  arch-chroot "$root_mount" /usr/bin/env bash -s "$timezone" "$hostname" << CHROOT_EOF
    export LANG=C
    set -e

    # Lightweight logging inside chroot
    log_info()  { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; exit 1; }

    timezone="$1"
    hostname="$2"

    log_info "Configuring time and locale in chroot environment"

    # Set the time zone
    ln -sf "/usr/share/zoneinfo/${timezone}" /etc/localtime || \
      log_error "Failed to set time zone to ${timezone} in chroot"

    # Sync the system clock to the hardware clock
    hwclock --systohc || \
      log_error "Failed to sync system clock to hardware clock in chroot"

    # Generate the locale
    sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen || \
      log_error "Failed to uncomment en_US.UTF-8 in /etc/locale.gen in chroot"

    locale-gen || \
      log_error "Failed to generate locale in chroot"

    echo "LANG=en_US.UTF-8" > "/etc/locale.conf" || \
      log_error "Failed to write LANG=en_US.UTF-8 to /etc/locale.conf in chroot"

    # Configure keyboard mapping (Copied from OpenSUSE Tumbleweed)
    { echo 'KEYMAP=us';
      echo 'FONT=eurlatgr';
      echo 'FONT_MAP=';
      echo 'FONT_UNIMAP=';
      echo 'XKBLAYOUT=us';
      echo 'XKBMODEL=pc105+inet';
      echo 'XKBOPTIONS=terminate:ctrl_alt_bksp';
    } > /etc/vconsole.conf

    # Configure the Host Name
    echo "${hostname}" > /etc/hostname

    # Build the hosts file
    { echo -e '127.0.0.1\tlocalhost';
      echo -e '::1\t\tlocalhost';
      echo -e "127.0.1.1\t${hostname}.${host_domain}\t${hostname}";
    } > /etc/hosts

    # Enable color output for pacman and specify the number of parallel downloads
    sed -i 's/#Color/Color/;s/ParallelDownloads = 5/ParallelDownloads = 7/' "/etc/pacman.conf"

    log_info "Time and locale configuration complete"
CHROOT_EOF
}
enable_services() {
  local root_mount="$1"
  shift
  local services=("$@")

  log_info "Enabling services in chroot environment"

  for service in "${services[@]}"; do
    arch-chroot "$root_mount" systemctl enable "$service" || \
      log_error "Failed to enable service: $service in chroot"
  done

  log_info "All specified services enabled successfully"
}
install_and_configure_grub() {
  # Install and configure GRUB for normal and LTS kernels
  local root_mount="$1"
  log_info "Installing and configuring GRUB"
  
  arch-chroot "$root_mount" /usr/bin/env bash << 'CHROOT_EOF'
    export LANG=C
    set -e

    log_info()  { echo "[INFO] $*"; }
    log_error() { echo "[ERROR] $*" >&2; exit 1; }

    log_info "Installing and configuring GRUB bootloader"

    # Install GRUB for UEFI systems
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB || \
      log_error "Failed to install GRUB bootloader"

    # Configure GRUB the first time to ensure entries are created for both the normal and LTS kernels
    grub-mkconfig -o /boot/grub/grub.cfg || \
      log_error "Failed to generate GRUB configuration file"

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
  log_info "GRUB installation and configuration complete"
}
pause() {
  # Pause the script and wait for user input
  read -rp "Press Enter to continue..."
}
sudo_enable_wheel_group() {
  # Make wheel group sudo enabled
  local root_mount="$1"

  log_info "Enabling sudo for wheel group in chroot environment"

  # Make wheel group sudo enabled
  SUDOER_TMP=$(mktemp)
  cat "$root_mount/etc/sudoers" > "$SUDOER_TMP"
  sed -i -e 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' "$SUDOER_TMP" || \
    log_error "Failed to enable sudo for wheel group in $root_mount/etc/sudoers"
  visudo -c -f "$SUDOER_TMP" && cat "$SUDOER_TMP" > "$root_mount/etc/sudoers"
  rm "$SUDOER_TMP" || log_error "Failed to remove temporary sudoers file $SUDOER_TMP"

  log_info "Wheel group sudo enabled successfully"
}
update_mkinitcpio() {
  # Update mkinitcpio.conf
  local root_mount="$1"

  log_info "Updating mkinitcpio configuration in chroot environment"

  arch-chroot "$root_mount" sed -i \
    -e 's/MODULES=()/MODULES=(btrfs)/' /etc/mkinitcpio.conf \
    -e 's/block filesystems fsck/block lvm2 filesystems fsck grub-btrfs-overlayfs/' \
    /etc/mkinitcpio.conf || \
    log_error "Failed to update mkinitcpio.conf in chroot"

  arch-chroot "$root_mount" mkinitcpio -p linux || \
    log_error "Failed to regenerate initramfs in chroot"

  log_info "mkinitcpio configuration updated successfully"
}
detect_gpu() {
    # Get PCI IDs. -nn shows numeric IDs. -k shows kernel driver in use.
    local pci_info
    local vendor_id

    pci_info=$(lspci -nn -k | grep -A 3 -E 'VGA|3D')
    
    # Extract Vendor ID (first 4 chars after [)
    # Example: [10de:1b80] -> 10de
    vendor_id=$(echo "$pci_info" | grep -oP '\[\K[0-9a-f]{4}' | head -1)
    
    case "$vendor_id" in
      10de)
        log_info "GPI detected: NVIDIA"
        printf '%s\n' "NVIDIA"
          ;;
      1002)
        log_info "GPU detected: AMD"
        printf '%s\n' "AMD"
        ;;
      8086)
        log_info "GPU detected: Intel"
        printf '%s\n' "Intel"
        ;;
      *)
        log_info "GPU detected: Unknown"
        printf '%s\n' "Unknown"
        ;;
    esac
}
install_gpu_drivers() {
    local root_mount="$1"
    local gpu_type
    
    gpu_type=$(detect_gpu)

    log_info "Detected GPU Vendor: $gpu_type"

    case "$gpu_type" in
        NVIDIA)
            log_info "Installing NVIDIA proprietary drivers..."
            
            # Ensure DKMS and headers are present
            arch-chroot "$root_mount" pacman -S --noconfirm linux-headers base-devel
            
            # Install nvidia-dkms (handles kernel updates automatically)
            arch-chroot "$root_mount" pacman -S --noconfirm nvidia-dkms nvidia-utils libva-nvidia-driver
            
            # Configure GRUB
            configure_grub_nvidia
            ;;
        AMD)
            log_info "Installing AMD drivers..."
            arch-chroot "$root_mount" pacman -S --noconfirm mesa lib32-mesa xf86-video-amdgpu amd-ucode
            ;;
        Intel)
            log_info "Installing Intel drivers..."
            arch-chroot "$root_mount" pacman -S --noconfirm mesa lib32-mesa intel-media-driver intel-ucode
            ;;
        *)
            log_warning "Unknown GPU detected. Manual intervention may be required."
            ;;
    esac
    
    # Rebuild initramfs to ensure new modules are included
    arch-chroot "$root_mount" mkinitcpio -P
    
    log_info "Driver installation complete. Reboot required."
}
create_post_install_scripts_for_root() {
  # Create post install scripts for root
  local root_mount="$1"

  mkdir "${root_mount}/root/Scripts"
  arch-chroot "${root_mount}" touch /root/Scripts/enable_snapper_snapshots.sh
  arch-chroot "${root_mount}" chmod +x /root/Scripts/enable_snapper_snapshots.sh
  { echo -e '#!/usr/bin/bash';
    echo -e 'btrfs subvolume delete /.snapshots/';
    echo -e 'snapper -c root create-config /';
    echo -e 'snapper -c root set-config ALLOW_GROUPS="wheel" SYNC_ACL=yes';
    echo -e "sed -i 's/PRUNENAMES = \".git .hg .svn\"/PRUNENAMES = \".git .hg .svn .snapshots\"/' /etc/updatedb.conf";
    echo -e 'snapper list-configs';
  } >> "${root_mount}/root/Scripts/enable_snapper_snapshots.sh"
}
create_post_install_scripts_for_user() {
  local root_mount="$1"
  local user_id="$2"
  arch-chroot "${root_mount}" mkdir "/home/${user_id}/Scripts/"
  arch-chroot "${root_mount}" touch "/home/${user_id}/Scripts/enable_yay.sh"
  arch-chroot "${root_mount}" chmod +x "/home/${user_id}/Scripts/enable_yay.sh"
  { echo -e '#!/usr/bin/bash';
    echo -e 'git clone https://aur.archlinux.org/yay.git';
    echo -e 'pushd yay';
    echo -e 'makepkg -si';
    echo -e 'popd';
    echo -e 'yay --noconfirm -S brave-bin btrfs-assistant oh-my-posh plymouth ttf-ms-fonts';
  } >> "${root_mount}/home/${user_id}/Scripts/enable_y"
}
create_script_to_install_flatpack_apps(){
  local root_mount="$1"
  local user_id="$2"

    # Create script to install FlatPack apps
  arch-chroot "${root_mount}" touch "/home/${user_id}/Scripts/install_flatpak_apps.sh"
  arch-chroot "${root_mount}" chmod +x "/home/${user_id}/Scripts/install_flatpak_apps.sh"
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
  } >> "${root_mount}/home/${user_id}/Scripts/install_flatpak_apps.sh"
}
configure_grub_for_snapshot_recovery() {
  local root_mount="$1"
  # Configure GRUB for snapshot recovery
  arch-chroot "${root_mount}" sed -i 's/GRUB_DISABLE_RECOVERY=true/GRUB_DISABLE_RECOVERY=false/' /etc/default/grub
  arch-chroot "${root_mount}" grub-mkconfig -o /boot/grub/grub.cfg
  arch-chroot "${root_mount}" systemctl enable grub-btrfsd
  arch-chroot "${root_mount}" systemctl enable snapper-boot.timer
}
# endregion - Function Definitions
# =============================================================================
# region - Main Script Execution
# =============================================================================
main() {
  # region - main variables
  local my_disk=""
  local my_partition_efi=""
  local my_partition_root=""
  local my_password_hash=""
  local cpu_firmware=""
  local hypervisor_pkgs=""
  local install_gui_apps
  local install_podman_pkgs
  local -r my_shell="/usr/bin/bash"
  local -r host_domain="vienna.ad"
  local -r efi_partition_size="550M"
  local -r root_partition_size="0" # Use all remaining space for root
  readonly keyboard_layout="us"
  readonly disk_size_root=80G
  # readonly disk_pct_of_free_root=40
  readonly disk_size_swap=4G
  readonly disk_pct_of_free_home=100

  # endregion - main variables
  # region - completed function calls
  check_for_root
  configure_time_preinstallation "$my_timezone"
  configure_pacman_preinstallation "${pacman_conf}" "${pacman_parallel_downloads}" "${pacman_color_output}"
  install_preinstall_pkgs "${preinstall_pkgs[@]}"

  # install_gui_apps=$(ask_install_de_native)
  ask_install_de_native
  install_gui_apps=$?
  log_info "install_gui_apps is ${install_gui_apps}"
  
  # install_podman_pkgs=$(ask_install_podman_pkgs)
  ask_install_podman_pkgs
  install_podman_pkgs=$?
  log_info "install_podman_pkgs is ${install_podman_pkgs}"
  
  if ! install_disk=$(get_install_disk); then
    printf 'No disk selected. Exiting.\n' >&2
    exit 1
  fi

  build_partition_paths "$install_disk" my_disk my_partition_efi my_partition_root
  make_password_hash  my_password_hash
  cpu_firmware=$(determine_cpu_firmware)
  hypervisor_pkgs=$(determine_hypervisor_packages)

  # Configure keyboard
  localectl set-keymap ${keyboard_layout}

  # Set-up the fastest Arch mirrors
  reflector -c us -p https --age 6 --country us --number 5 --latest 8 --sort rate --verbose --save "${pacman_mirrorlist}"

  wipe_disk_signatures "$my_disk"

  # Removes all active device mapper devices
  dmsetup remove_all

  # Stop RAID arrays (if any)
  mdadm --stop --scan

  # Prepare the disk for installation
  create_physical_partitions "$my_disk" "$efi_partition_size" "$root_partition_size"

  create_physical_volumes "$my_partition_root"

  create_volume_group "$my_partition_root"

  create_logical_volumes "${disk_size_root}" "$disk_size_swap" "${disk_pct_of_free_home}%"

  format_the_partitions "$my_partition_efi"

  create_btrfs_subvolumes "$my_root_mount"

  mount_subvolumes "$my_root_mount" "$MOUNTOPTS"

  mount_partitions "$my_root_mount" "$my_partition_efi"

  # Install base packages
  pacstrap $my_root_mount "${pacstrap_pkgs[@]}" "$cpu_firmware" "$hypervisor_pkgs"

  # Generate the File System TABle (fstab) using UUID numbers
  genfstab -U $my_root_mount >> $my_root_mount/etc/fstab

  # Begin arch-chroot operations
  install_gpu_drivers "$my_root_mount"
 
  configure_time_and_locale "$my_root_mount" "$my_timezone" "$my_host_name" "$host_domain"
 
  # Enable color output for pacman and specify the number of parallel downloads
  arch-chroot $my_root_mount sed -i 's/#Color/Color/;s/ParallelDownloads = 5/ParallelDownloads = 7/' "/etc/pacman.conf"

  install_and_configure_grub "$my_root_mount"

  enable_services "$my_root_mount" "${services_to_enable[@]}"

  sudo_enable_wheel_group "$my_root_mount"

  update_mkinitcpio "$my_root_mount"

  # Add a user account
  arch-chroot $my_root_mount useradd -c "$my_full_name" -mG wheel -s $my_shell -p "$my_password_hash" $my_user_id

  if [ "$install_podman_pkgs" -eq 0 ]; then
    set -x
    log_info "Installing Podman packages"
    arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet "${podman_pkgs[@]}"
    set +x
    pause
  fi

  if [ "$install_gui_apps" -eq 0 ]; then
    # Install KDE Plasma and sddm
    arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet xorg sddm plasma kde-applications
    
    # Enable SDDM display manager
    arch-chroot $my_root_mount systemctl enable sddm

    # Apply the Breeze theme to sddm
    mkdir $my_root_mount/etc/sddm.conf.d/
    arch-chroot $my_root_mount sed 's/Current=/Current=breeze/;w /etc/sddm.conf.d/sddm.conf' /usr/lib/sddm/sddm.conf.d/default.conf

    # Install the gui packages
    arch-chroot $my_root_mount pacman -Sy --needed --noconfirm --quiet "${gui_pkgs[@]}"
    if [ "$install_podman_pkgs" -eq 0 ]; then
      arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet podman-desktop
    fi
  fi
  
  # Install snapper
  arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet snapper snap-pac inotify-tools

  # # Configure GRUB for snapshot recovery
  # arch-chroot $my_root_mount sed -i 's/GRUB_DISABLE_RECOVERY=true/GRUB_DISABLE_RECOVERY=false/' /etc/default/grub
  # arch-chroot $my_root_mount grub-mkconfig -o /boot/grub/grub.cfg
  # arch-chroot $my_root_mount systemctl enable grub-btrfsd
  # arch-chroot $my_root_mount systemctl enable snapper-boot.timer
  configure_grub_for_snapshot_recovery "${my_root_mount}"

  # Allow root to have ssh access initially for troubleshooting while developing
  arch-chroot $my_root_mount sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

  # # Create post install scripts for root
  # mkdir $my_root_mount/root/Scripts
  # arch-chroot $my_root_mount touch /root/Scripts/enable_snapper_snapshots.sh
  # arch-chroot $my_root_mount chmod +x /root/Scripts/enable_snapper_snapshots.sh
  # { echo -e '#!/usr/bin/bash';
  #   echo -e 'btrfs subvolume delete /.snapshots/';
  #   echo -e 'snapper -c root create-config /';
  #   echo -e 'snapper -c root set-config ALLOW_GROUPS="wheel" SYNC_ACL=yes';
  #   echo -e "sed -i 's/PRUNENAMES = \".git .hg .svn\"/PRUNENAMES = \".git .hg .svn .snapshots\"/' /etc/updatedb.conf";
  #   echo -e 'snapper list-configs';
  # } >> $my_root_mount/root/Scripts/enable_snapper_snapshots.sh

  create_post_install_scripts_for_root "${my_root_mount}"

  # # Create post install scripts for $my_user_id
  # arch-chroot $my_root_mount mkdir /home/$my_user_id/Scripts/
  # arch-chroot $my_root_mount touch /home/$my_user_id/Scripts/enable_yay.sh
  # arch-chroot $my_root_mount chmod +x /home/$my_user_id/Scripts/enable_yay.sh
  # { echo -e '#!/usr/bin/bash';
  #   echo -e 'git clone https://aur.archlinux.org/yay.git';
  #   echo -e 'pushd yay';
  #   echo -e 'makepkg -si';
  #   echo -e 'popd';
  #   echo -e 'yay --noconfirm -S brave-bin btrfs-assistant oh-my-posh plymouth ttf-ms-fonts';
  # } >> $my_root_mount/home/$my_user_id/Scripts/enable_yay.sh

  create_post_install_scripts_for_user "${my_root_mount}" "${my_user_id}"

  # endregion - completed function calls

  # Enable oh-my-posh in zsh
  echo -e "\neval \"\$(oh-my-posh init zsh)\"" >> "$my_root_mount/home/$my_user_id/.zshrc";
  arch-chroot $my_root_mount chown $my_user_id:$my_user_id /home/$my_user_id/.zshrc

  create_script_to_install_flatpack_apps "${my_root_mount}" "${my_user_id}"

  arch-chroot $my_root_mount chown --recursive $my_user_id:$my_user_id /home/$my_user_id/Scripts

  # Create a directory for AppImages
  arch-chroot $my_root_mount mkdir /home/$my_user_id/AppImages/
  
  # Copy this script to the root home directory
  cp install.sh $my_root_mount/root/Scripts
  chmod -x $my_root_mount/root/Scripts/install.sh
  cp "$LOG_FILE" $my_root_mount/root/

  # (I want to retain the past results for debugging) clear

  echo -e "${success_color}Please set a password for the new root account:${no_color}"
  arch-chroot $my_root_mount passwd root

  sync
  
  # (Does not work) umount $my_root_mount || log_error "Failed to unmount root mount point $my_root_mount"

  swapoff /dev/system/swap || log_error "Failed to disable swap on /dev"

  log_info "Script finished! Please reboot."
}
# endregion - Main Script Execution
# =============================================================================
main "$@" || {
  log_error "Installation failed. Please check the logs for details."
}
