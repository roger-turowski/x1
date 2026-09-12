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
  # iwctl station wlan0 connect <network_name>
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
  exfatprogs
  edk2-ovmf
  efibootmgr
  ethtool
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
  ntfsprogs
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
  xfsprogs
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
  distrobox # Works with Podman
  python-pip # Works with Distrobox
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
  sway                    # Sway Tiling Window Manager
  foot                    # Default terminal for Sway
  wofi                    # Program launcher for Sway
  waybar                  # Menu Bar for Sway
  mako                    # Notification app for Sway
  xdg-desktop-portal-gtk  # Used for Sway
  xdg-desktop-portal-wlr  # Used for Sway
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
readonly flatpak_apps=(
  dev.bragefuglseth.Keypunch
  net.cozic.joplin_desktop
  org.deluge_torrent.deluge
  com.github.sixpounder.GameOfLife
  io.github.giantpinkrobots.flatsweep
  io.github.shiftey.Desktop
  com.sweethome3d.Sweethome3d
  org.kicad.KiCad
  com.obsproject.Studio
  com.github.artemanufrij.regextester
  org.remmina.Remmina
  org.stellarium.Stellarium
  com.adrienplazas.Metronome
  io.github.nokse22.inspector
  dev.bragefuglseth.Fretboard
)
readonly aur_apps=(
  brave-bin
  btrfs-assistant
  oh-my-posh
  plymouth
  ttf-ms-fonts
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
  # Set-up the fastest Arch mirrors
  reflector --age 6 --country us --latest 8 --number 5 --protocol https --sort rate --verbose --save "${pacman_mirrorlist}"
  pacman --noconfirm --quiet -Sy archlinux-keyring
}
ask_install_de_native() {
  # Function: ask_install_de_native
  #
  # Brief:
  # This function is dedicated to prompting the user to install the DE (Desktop Environment) native libraries
  # for the intended application's optimal performance and extended functionality.
  #
  # Input:
  # None (typically user input would be used to make decisions)
  #
  # Output:
  # Institutes the installation of required native libraries for the DE (Desktop Environment)
  # with appropriate user prompts, permissions, and system checks.
  #
  # Note:
  # - This function should be part of a comprehensive script or application setup sequence.
  # - The function's implementation, error handling, and system requirements might vary widely
  #   depending on the specific DE, the platform, and the native libraries in question.
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
  # Function: ask_install_podman_pkgs
  #
  # Brief:
  # This routine is responsible for checking if the required packages for Podman are installed on the system. If not, it prompts the user to install them.
  #
  # Input:
  # None. It queries the system for the required packages. User input is necessary to confirm the installation.
  #
  # Output:
  # The routine might initiate the installation of one or more packages, depending on the user's confirmation.
  # A message is displayed to notify the user about successful installation or to inform about possible errors.
  #
  # Note:
  # - This script assumes the use of a package manager compatible with 'pacman'.
  # - The packages and their install commands may change based on the specific requirements of Podman and the systems it is intended to run on.
  # - Adapt this script with care as it may cause changes in system packages and services.
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
  # Function: teardown_existing_mappings
  #
  # Brief:
  # This function is responsible for identifying and removing any pre-existing
  # path or directory mappings (e.g., symlinks, bind mounts, or configured
  # path aliases) prior to establishing new ones. It ensures a clean state
  # so that subsequent mapping operations do not conflict with stale
  # references.
  #
  # Input:
  # None. The function discovers existing mappings by inspecting the
  # filesystem (e.g., /etc/fstab, symlink directories, or a known
  # configuration path).
  #
  # Output:
  # Removes or unmounts any previously created mappings and reports
  # which entries were cleaned up. May log warnings if a mapping
  # could not be removed (e.g., due to permissions or active usage).
  #
  # Note:
  # - Should be called before any mapping-creation routine to avoid
  #   duplicate or orphaned entries.
  # - Handles cases where a mapping is still in use by gracefully
  #   reporting the error rather than failing the entire script.
  # - No user interaction is expected; the function operates
  #   autonomously on the known target paths.
  local disk="$1"

  log_info "Tearing down existing mappings on ${disk}"

  swapoff -a 2>/dev/null || true

  # 1. Remove LVM volume groups on this disk
  local vg
  for vg in $(vgs --noheadings --separator ' ' 2>/dev/null | awk '{print $1}'); do
      if pvs --noheadings 2>/dev/null | grep -q "$disk"; then
          log_info "Removing volume group: ${vg}"
          lvremove -ff "$vg" 2>/dev/null || true
          vgremove -ff "$vg" 2>/dev/null || true
      fi
  done

  # 1b. Remove physical volumes on this disk
  local pv
  for pv in $(pvs --noheadings -o pv_name 2>/dev/null | tr -d ' '); do
      if [[ "$pv" == "$disk"* ]]; then
          log_info "Removing physical volume: ${pv}"
          pvremove -ff "$pv" 2>/dev/null || true
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
      umount -Rf "$mountpoint" 2>/dev/null || true
  done

  # 4. Clean up any remaining device-mapper nodes
  dmsetup remove_all 2>/dev/null || true

  log_info "Mapping teardown complete for ${disk}"
}
wipe_disk_signatures() {
  # Function: wipe_disk_signatures
  #
  # Brief:
  # This function removes or overwrites identifying signatures on a
  # target disk, including UUIDs, partition table signatures (e.g.,
  # MBR/GPT labels), volume serial numbers, and any vendor-specific
  # identifiers. This ensures the disk cannot be uniquely traced back
  # to a prior system or imaging source.
  #
  # Input:
  # - Target disk device (e.g., /dev/sdb) expected as a module-level
  #   variable or passed contextually.
  # - No direct user interaction; the function operates on the
  #   pre-selected device.
  #
  # Output:
  # - Overwrites or zeroes the signature fields in the disk's
  #   partition table, filesystem metadata, and device identifiers.
  # - Logs a confirmation message indicating which signatures were
  #   wiped and any fields that could not be cleared.
  #
  # Note:
  # - All data on the target signatures will be irreversibly altered;
  #   this is NOT a full disk wipe.
  # - Requires appropriate privileges (typically root) to modify
  #   block-level identifiers.
  # - Verify the target device externally before invoking to avoid
  #   accidental modification of the wrong disk.
  # - Should be called as part of a broader disk preparation or
  #   imaging sanitization workflow.

  # Now wipe the physical disk cleanly after teardown:
  local disk="$1"

  # Validate
  if [[ ! -b "$disk" ]]; then
    log_error "${disk} is not a block device"
  fi

  swapoff -a 2>/dev/null || true
  # Tear down existing LUKS/LVM layers first
  teardown_existing_mappings "$disk"
  dmsetup remove_all 2>/dev/null || true

  # NVMe-specific: secure erase before traditional wipe
  nvme_secure_erase "$disk"

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
    clear >&2
	printf "\nCurrent disk layout...\n\n" >&2
	lsblk -f >&2
	printf '\nList of disks available:\n' >&2
    lsblk -d -e 11 -e 7 -o name,size >&2
    printf "\n" >&2
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
get_partition_sizes() {
  local disk="$1"
  local -n out_root="$2"
  local -n out_swap="$3"
  local -n out_home="$4"
  local -n out_data="$5"
  local -n out_part_size="$6"

  local total_bytes

  total_bytes=$(lsblk -b -d -n -o SIZE "$disk" 2>/dev/null) || {
    log_error "Could not determine disk size for $disk"
  }

  total_bytes=$(echo "$total_bytes" | tr -dc '0-9')

  local total_gb=$((total_bytes / 1024 / 1024 / 1024))
  log_info "Total disk size: ${total_gb}GB"

  out_swap="4G"

  # Get root size
  local response
  while true; do
    read -rp "Root (/) size (e.g., '50%' or '80GB'): " response
    if [[ -z "$response" ]]; then
      echo "Input cannot be empty." >&2
      continue
    fi
    if [[ "$response" =~ ^([0-9]+)%$ ]]; then
      local pct="${BASH_REMATCH[1]}"
      if (( pct < 10 || pct > 100 )); then
        echo "Percentage must be between 10% and 100%." >&2
        continue
      fi
      local pct_bytes=$((total_bytes * pct / 100))
      out_root="$((pct_bytes / 1024 / 1024 / 1024))GB"
      break
    elif [[ "$response" =~ ^([0-9]+)(TB|GB)$ ]]; then
      local num="${BASH_REMATCH[1]}"
      local unit="${BASH_REMATCH[2]}"
      if (( num < 10 )); then
        echo "Minimum root size is 10GB." >&2
        continue
      fi
      if [[ "$unit" == "TB" ]]; then
        out_root="$((num * 1024))GB"
      else
        out_root="${num}GB"
      fi
      break
    else
      echo "Invalid format. Use '50%' or '100GB'." >&2
    fi
  done

  # Get home size
  while true; do
    read -rp "Home (/home) size (e.g., '30%' or '150GB'): " response
    if [[ -z "$response" ]]; then
      echo "Input cannot be empty." >&2
      continue
    fi
    if [[ "$response" =~ ^([0-9]+)%$ ]]; then
      local pct="${BASH_REMATCH[1]}"
      if (( pct < 5 || pct > 100 )); then
        echo "Percentage must be between 5% and 100%." >&2
        continue
      fi
      local pct_bytes=$((total_bytes * pct / 100))
      out_home="$((pct_bytes / 1024 / 1024 / 1024))GB"
      break
    elif [[ "$response" =~ ^([0-9]+)(TB|GB)$ ]]; then
      local num="${BASH_REMATCH[1]}"
      local unit="${BASH_REMATCH[2]}"
      if (( num < 10 )); then
        echo "Minimum home size is 10GB." >&2
        continue
      fi
      if [[ "$unit" == "TB" ]]; then
        out_home="$((num * 1024))GB"
      else
        out_home="${num}GB"
      fi
      break
    else
      echo "Invalid format. Use '30%' or '150GB'." >&2
    fi
  done

  # Get data size
  while true; do
    read -rp "Data (/data) size (e.g., '30%' or '150GB'): " response
    if [[ -z "$response" ]]; then
      echo "Input cannot be empty." >&2
      continue
    fi
    if [[ "$response" =~ ^([0-9]+)%$ ]]; then
      local pct="${BASH_REMATCH[1]}"
      if (( pct < 5 || pct > 100 )); then
        echo "Percentage must be between 5% and 100%." >&2
        continue
      fi
      local pct_bytes=$((total_bytes * pct / 100))
      out_data="$((pct_bytes / 1024 / 1024 / 1024))GB"
      break
    elif [[ "$response" =~ ^([0-9]+)(TB|GB)$ ]]; then
      local num="${BASH_REMATCH[1]}"
      local unit="${BASH_REMATCH[2]}"
      if (( num < 10 )); then
        echo "Minimum data size is 10GB." >&2
        continue
      fi
      if [[ "$unit" == "TB" ]]; then
        out_data="$((num * 1024))GB"
      else
        out_data="${num}GB"
      fi
      break
    else
      echo "Invalid format. Use '30%' or '150GB'." >&2
    fi
  done

  # Calculate total partition size (root + swap + home, numeric only)
  local root_gb="${out_root%GB}"
  local home_gb="${out_home%GB}"
  local data_gb="${out_data%GB}"
  local swap_gb="${out_swap%G}"
  out_part_size="$((root_gb + home_gb + data_gb +swap_gb))GB"

  log_info "Sizes: root=${out_root}, swap=${out_swap}, home=${out_home}, data=${out_data},  partition=${out_part_size}"
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
nvme_secure_erase() {
  local disk="$1"

  if [[ "$disk" =~ nvme ]]; then
    log_info "Performing NVMe secure erase on $disk"

    # Ensure nvme-cli is available
    pacman -Q nvme-cli &>/dev/null || pacman -Sy --noconfirm nvme-cli

    # Format the namespace — ses=1 zeros all user data
    nvme format "$disk" --ses=1 -f || log_error "NVMe secure erase failed on $disk"

    # Wait for completion and re-read partition table
    sleep 2
    partprobe "$disk"
    udevadm settle --timeout=10

    log_info "NVMe secure erase complete on $disk"
  fi
}
create_physical_partitions() {
  local disk="$1"
  local efi_size="$2"
  local root_size="$3"
  local efi_part="$4"
  local root_part="$5"

  log_info "Creating physical partitions on $disk"

  sgdisk \
    --new=1:0:+"${efi_size}"   --typecode=1:ef00 --change-name=1:EFI \
    --new=2:0:+"${root_size}"  --typecode=2:8e00 --change-name=2:root \
    "${disk}" || log_error "Failed to create physical partitions on $disk"

  partprobe "$disk"
  udevadm settle --timeout=10

  # Display a disk summary
  log_info "Disk summary for $my_disk: $(partprobe -s "$my_disk")"

  # CRITICAL: Wipe signatures on newly-created partitions before PV creation
  wipefs --all --force "$efi_part" || log_error "Failed to wipe EFI partition signature"
  wipefs --all --force "$root_part" || log_error "Failed to wipe root partition signature"

  log_info "Partition signatures wiped, ready for LVM"
}
create_volume_group() {
  local root_partition="$1"

  # Create a volume group named "system" using the root partition
  vgcreate system "$root_partition" || \
    log_error
}
create_physical_volumes() {
  local root_partition="$1"

  # Tear down any device-mapper mappings holding the partition
  swapoff -a 2>/dev/null || true
  vgchange -an 2>/dev/null || true
  dmsetup remove_all 2>/dev/null || true

  # Force unmount any auto-mounted filesystems
  log_info "Ensuring $root_partition is unmounted"
  umount -R "$root_partition" 2>/dev/null || true
  umount "$root_partition" 2>/dev/null || true

  # Wipe the physical partition — destroys signatures lurking in the
  # LVM header region that won't be covered by any LV
  wipefs --all --force "$root_partition" 2>/dev/null || true
  dd if=/dev/zero of="$root_partition" bs=1M count=10 || true
  
  log_info "Creating physical volume on $root_partition"
  # Create a physical volume to contain the volume group "system"
  pvcreate -ff "$root_partition" || \
    log_error "Failed to create physical volume on $root_partition"
}
create_logical_volumes() {
  local root_size="$1"
  local swap_size="$2"
  local home_size="$3"
  local data_size="$4"

  log_info "Creating logical volumes (root: $root_size, swap: $swap_size, home: $home_size, data: $data_size)"

  # Create the logical volumes for root, swap and home
  # lvcreate -l "${root_partition}FREE" -n root system || \
  #  log_error "Failed to create root logical volume"
  lvcreate -L "${root_size}" -n root system || \
    log_error "Failed to create root logical volume"

  lvcreate -L "${swap_size}" -n swap system || \
    log_error "Failed to create swap logical volume"
  
  # Check if enough space remains for the requested home size
  local free_pe
  free_pe=$(vgs --noheadings -o vg_free_count system) || \
    log_error "Failed to query free extents in volume group system"
  local free_mb=$((free_pe * 4))
  log_info "Remaining free space in VG: ${free_mb}MiB"

  # Allocate home — use 100%FREE so no rounding mismatch
  # but warn if it's significantly less than requested
  local requested_mb=$(((${home_size%GB} + ${data_size%GB}) * 1024))
  if (( free_mb < requested_mb )); then
    log_warn "Data will be ${free_mb}MiB — less than requested ${requested_mb}MiB due to PE rounding"
  fi

  lvcreate -L "${home_size}" -n home system || \
    log_error "Failed to create home logical volume"

  lvcreate -l 100%FREE -n data system || \
    log_error "Failed to create data logical volume"
}
format_the_partitions() {
  local my_partition_efi="$1"

  # Physically destroy all signatures on LVs — wipefs alone isn't enough
  # on recreated LVs mapped to extents with old filesystem data
  for lv in /dev/system/root /dev/system/home /dev/system/swap; do
    blkdiscard "$lv" 2>/dev/null || true
    dd if=/dev/zero of="$lv" bs=1M count=10 oflag=direct 2>/dev/null || true
  done

  # Wipe all signatures on every LV before formatting
  wipefs --all --force "$my_partition_efi" 2>/dev/null || true

  # Format the EFI partition
  mkfs.fat -n EFI -F32 "$my_partition_efi" || \
    log_error "Failed to format EFI partition $my_partition_efi"

  # Format the root volume with BTRFS
  mkfs.btrfs -f -L root /dev/system/root || \
    log_error "Failed to format root logical volume /dev/system/root"

  # Format the home volume with xfs
  mkfs.xfs -f -L home /dev/system/home || \
    log_error "Failed to format home logical volume /dev/system/home"

  # Format the data volume with xfs
  mkfs.xfs -f -L data /dev/system/data || \
    log_error "Failed to format data logical volume /dev/system/data"

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

  # Create the root @ subvolume
  btrfs subvolume create "$root_mount/@" || \
    log_error "Failed to create @ subvolume"

  # Create the subvolumes
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

  # Mount the root logical volume with BTRFS subvolume options (Probably don't need this, may duplicate mount on fstab)
  # mount -o subvol=@,$MOUNTOPTS /dev/system/root "$root_mount" || \
  #  log_error "Failed to mount root logical volume /dev/system/root to $root_mount"

  # Mount the EFI partition
  mkdir -p "$root_mount/boot/efi"
  mount "$partition_efi" "$root_mount/boot/efi" || \
    log_error "Failed to mount EFI partition $partition_efi to $root_mount/boot/efi"

  # Mount the home logical volume
  mkdir -p "$root_mount/home"
  mount /dev/system/home "$root_mount/home" || \
    log_error "Failed to mount home logical volume /dev/system/home to $root_mount/home"

  # Mount the data logical volume
  mkdir -p "$root_mount/data"
  mount /dev/system/data "$root_mount/data" || \
    log_error "Failed to mount data logical volume /dev/system/data to $root_mount/data"
}
get_hostname() {
  local default_host="${1:-arch}"
  local default_domain="${2:-localdomain}"
  local response response_domain

  while true; do
    read -r -p "Hostname for the new system [default: ${default_host}]: " response
    response="${response:-${default_host}}"

    if [[ ! "$response" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]]; then
      printf 'Invalid hostname: %s\nUse letters, digits and hyphens only.\n' "$response" >&2
      continue
    fi

    read -r -p "Domain for /etc/hosts entry [default: ${default_domain}]: " response_domain
    response_domain="${response_domain:-${default_domain}}"

    break
  done

  log_info "Hostname selected: ${response}.${response_domain}"
  printf '%s\n%s\n' "$response" "$response_domain"
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
configure_nic_fixes() {
  # Disable Energy-Efficient Ethernet globally at driver bind time.
  # Interface name agnostic: $name is resolved by udev per event.
  local root_mount="$1"

  mkdir -p "${root_mount}/etc/udev/rules.d"
  # shellcheck disable=SC2016  # $name is expanded by udev at event time, not by bash
  printf '%s\n' \
    'ACTION=="add", SUBSYSTEM=="net", KERNEL=="e*", RUN+="/usr/bin/ethtool --set-eee $name eee off"' \
    > "${root_mount}/etc/udev/rules.d/70-eee-off.rules"
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
  # Commented out to test new code at the end. Nvidia was not detected on Proxmox VM.
  # Detect GPU
  #     # Detect GPU
  #     local vendor_id
  #     local device
  #
  #     for device in /sys/bus/pci/devices/*/; do
  #         local class
  #         class=$(cat "${device}
  #     local vendor_id
  #     local device
  #
  #     for device in /sys/bus/pci/devices/*/; do
  #         local class
  #         class=$(cat "${device}class" 2>/dev/null)
  #         # 0x030000 = VGA, 0x030200 = 3D controller, 0x038000 = display
  #         if [[ "$class" == "0x030000" ]] || [[ "$class" == "0x030200" ]] || [[ "$class" == "0x038000" ]]; then
  #             vendor_id=$(cat "${device}vendor" 2>/dev/null | cut -c3-6)
  #             break
  #         fi
  #     done
  #
  #     case "$vendor_id" in
  #         10de) log_info "GPU detected: NVIDIA"; printf '%s\n' "NVIDIA" ;;
  #         1002) log_info "GPU detected: AMD";    printf '%s\n' "AMD" ;;
  #         8086) log_info "GPU detected: Intel";  printf '%s\n' "Intel" ;;
  #         *)    log_info "GPU detected: Unknown (vendor: ${vendor_id:-none})"; printf '%s\n' "Unknown" ;;
  #     esac
  local class
  local vid
  local vendor_id=""

  for device in /sys/bus/pci/devices/*/; do
    class=$(cat "${device}class" 2>/dev/null)
    # 0x030000 = VGA, 0x030200 = 3D controller, 0x038000 = display
    if [[ "$class" == "0x030000" || "$class" == "0x030200" || "$class" == "0x038000" ]]; then
      vid=$(cat "${device}vendor" 2>/dev/null | cut -c3-6)
      # 1234 = QEMU/Bochs emulated VGA (virt-manager/Proxmox virtual display)
      # 1af4 = Red Hat/VirtIO (virtio-gpu) — also virtual
      if [[ "$vid" == "1234" || "$vid" == "1af4" ]]; then
        vendor_id="$vid"
        continue   # virtual adapter, keep scanning
      fi
      vendor_id="$vid"
      break         # first *physical* display-class device
    fi
  done

  case "$vendor_id" in
    10de) log_info "GPU detected: NVIDIA"; printf '%s\n' "NVIDIA" ;;
    1002) log_info "GPU detected: AMD";    printf '%s\n' "AMD" ;;
    8086) log_info "GPU detected: Intel";  printf '%s\n' "Intel" ;;
    *)    log_info "GPU detected: Unknown (vendor: ${vendor_id:-none})"; printf '%s\n' "Unknown" ;;
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
            arch-chroot "$root_mount" pacman -S --noconfirm mesa xf86-video-amdgpu amdgpu_top amdsmi
            ;;
        Intel)
            log_info "Installing Intel drivers..."
            arch-chroot "$root_mount" pacman -S --noconfirm mesa lib32-mesa intel-media-driver intel-ucode
            ;;
        *)
            log_warn "Unknown GPU detected. Manual intervention may be required."
            ;;
    esac
    
    # Rebuild initramfs to ensure new modules are included
    arch-chroot "$root_mount" mkinitcpio -P
    
    log_info "Driver installation complete. Reboot required."
}
configure_grub_nvidia() {
    local grub_cfg="/etc/default/grub"
    local target_params="nvidia-drm.modeset=1"
    
    # Check if parameter already exists to avoid duplicates
    if ! grep -q "$target_params" "$grub_cfg"; then
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\1 $target_params\"/" "$grub_cfg"
        echo "Added kernel parameters for NVIDIA."
        
        # Regenerate GRUB config
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        echo "NVIDIA kernel parameters already present."
    fi
}
create_post_install_scripts_for_user() {
  local root_mount="$1"
  local user_id="$2"
  local script_path="${root_mount}/home/${user_id}/Scripts/enable_yay.sh"

  mkdir -p "${root_mount}/home/${user_id}/Scripts/" || \
    log_error "Failed to create the user Scripts directory"
  
  { 
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'git clone https://aur.archlinux.org/yay.git ~/Git/yay'
    echo 'pushd ~/Git/yay'
    echo 'makepkg -si'
    echo 'popd'
    local app
    for app in "${aur_apps[@]}"; do
      printf 'yay --noconfirm -S %q\n' "$app"
    done
  } > "$script_path" || \
    log_error "Failed to create $script_path"

  chmod +x "$script_path" || \
    log_error "Failed to make $script_path script executable"

  local script_path="${root_mount}/home/${user_id}/Scripts/snapshot_baseline.sh"
  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    echo 'sudo snapper -c root create --description "baseline"'
  } > "$script_path" || \
    log_error "Failed to create $script_path"
  
  chmod +x "$script_path" || \
    log_error "Failed to make $script_path script executable"
}
create_script_to_install_flatpack_apps() {
  local root_mount="$1"
  local user_id="$2"
  local script_path="${root_mount}/home/${user_id}/Scripts/install_flatpak_apps.sh"

  {
    echo '#!/usr/bin/env bash'
    echo 'set -euo pipefail'
    local app
    for app in "${flatpak_apps[@]}"; do
      printf 'flatpak install -y --noninteractive flathub %q\n' "$app"
    done
  } > "$script_path" || \
    log_error "Failed to create $script_path"

  chmod +x "$script_path" || \
    log_error "Failed to make $script_path script executable"
}
configure_grub_for_snapshot_recovery() {
  local root_mount="$1"
  # Configure GRUB for snapshot recovery
  arch-chroot "${root_mount}" sed -i 's/GRUB_DISABLE_RECOVERY=true/GRUB_DISABLE_RECOVERY=false/' /etc/default/grub
  arch-chroot "${root_mount}" grub-mkconfig -o /boot/grub/grub.cfg
  arch-chroot "${root_mount}" systemctl enable grub-btrfsd
  arch-chroot "${root_mount}" systemctl enable snapper-boot.timer
}
configure_snapper_first_boot() {
  local root_mount="$1"

  log_info "Creating snapper first-boot configuration unit"

  # Helper executed on the real system at first boot, where D-Bus exists
  cat > "${root_mount}/usr/local/sbin/snapper-initial-setup.sh" <<'SETUP_EOF'
#!/usr/bin/env bash
set -euo pipefail

umount /.snapshots
btrfs subvolume delete /.snapshots
snapper -c root create-config /
snapper -c root set-config ALLOW_GROUPS="wheel" SYNC_ACL=yes
sed -i '/^PRUNENAMES/ s/"$/.snapshots"/' /etc/updatedb.conf
mount /.snapshots
SETUP_EOF

  chmod 755 "${root_mount}/usr/local/sbin/snapper-initial-setup.sh" || \
    log_error "Failed to make snapper-initial-setup.sh executable"

  # Oneshot unit, self-disabling once the snapper config exists
  cat > "${root_mount}/etc/systemd/system/snapper-initial-setup.service" <<'UNIT_EOF'
[Unit]
Description=Initial snapper root configuration
ConditionPathExists=!/etc/snapper/configs/root
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/snapper-initial-setup.sh
ExecStart=/usr/bin/snapper -c root create --description=baseline
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT_EOF

  # systemctl enable works in chroot — it only creates symlinks, no D-Bus needed
  arch-chroot "${root_mount}" systemctl enable snapper-initial-setup.service || \
    log_error "Failed to enable snapper-initial-setup.service"

  log_info "Snapper first-boot unit created and enabled"
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
  local ROOT_SIZE=""
  local SWAP_SIZE=""
  local HOME_SIZE=""
  local DATA_SIZE=""
  local PARTITION_SIZE=""
  local cpu_firmware=""
  local hypervisor_pkgs=""
  local install_gui_apps
  local install_podman_pkgs
  local -r my_shell="/usr/bin/bash"
  local -r efi_partition_size="550M"
  local my_host_name_default="arch"
  local host_domain_default="localdomain"
  local my_host_name_dyn=""
  local host_domain_dyn=""
  readonly keyboard_layout="us"
  # endregion - main variables

  check_for_root
  configure_time_preinstallation "$my_timezone"
  configure_pacman_preinstallation "${pacman_conf}" "${pacman_parallel_downloads}" "${pacman_color_output}"
  install_preinstall_pkgs "${preinstall_pkgs[@]}"

  # Get root size (now interactive)
  #root_partition_size=$(get_root_partition_size "$my_disk")

  # install_gui_apps=$(ask_install_de_native)
  install_gui_apps=0
  ask_install_de_native || install_gui_apps=1
  log_info "install_gui_apps is ${install_gui_apps}"
  
  # install_podman_pkgs=$(ask_install_podman_pkgs)
  install_podman_pkgs=0
  ask_install_podman_pkgs || install_podman_pkgs=1
  log_info "install_podman_pkgs is ${install_podman_pkgs}"
  
  if ! install_disk=$(get_install_disk); then
    printf 'No disk selected. Exiting.\n' >&2
    exit 1
  fi

  if mountpoint -q "/dev/$install_disk" || mount | grep -q "$install_disk"; then
      log_error "$install_disk or its partitions are currently mounted. Unmount manually and rerun."
  fi

  build_partition_paths "$install_disk" my_disk my_partition_efi my_partition_root

  get_partition_sizes "$my_disk" ROOT_SIZE SWAP_SIZE HOME_SIZE DATA_SIZE PARTITION_SIZE

  log_info "Configuration:"
  log_info "  EFI: $efi_partition_size"
  log_info "  Root LV: $ROOT_SIZE"
  log_info "  Swap LV: $SWAP_SIZE"
  log_info "  Home LV: $HOME_SIZE"
  log_info "  Data LV: $DATA_SIZE"
  log_info "  Partition 2 (PV): $PARTITION_SIZE"

  # Ask for and set the host name
  {
    read -r my_host_name_dyn
    read -r host_domain_dyn
  } < <(get_hostname "${my_host_name_default}" "${host_domain_default}")
  log_info "  Hostname: ${my_host_name_dyn}.${host_domain_dyn}"

  read -rp "Proceed? [y/N]: " confirm
  case "$confirm" in
    y|Y) ;;
    *) log_error "Cancelled";;
  esac

  make_password_hash  my_password_hash
  cpu_firmware=$(determine_cpu_firmware)
  hypervisor_pkgs=$(determine_hypervisor_packages)

  # Configure keyboard
  localectl set-keymap ${keyboard_layout}

  wipe_disk_signatures "$my_disk"

  # Removes all active device mapper devices
  dmsetup remove_all

  # Stop RAID arrays (if any)
  command -v mdadm >/dev/null && mdadm --stop --scan

  # Prepare the disk for installation
  # create_physical_partitions "$my_disk" "$efi_partition_size" "$root_partition_size"
  # Create partitions with calculated size
  create_physical_partitions "$my_disk" "$efi_partition_size" "$PARTITION_SIZE" "$my_partition_efi" "$my_partition_root"

  create_physical_volumes "$my_partition_root"

  create_volume_group "$my_partition_root"

  # create_logical_volumes "${disk_size_root}" "$disk_size_swap" "${disk_pct_of_free_home}%"
  # Create logical volumes with individual sizes
  create_logical_volumes "$ROOT_SIZE" "$SWAP_SIZE" "$HOME_SIZE" "$DATA_SIZE"
  
  format_the_partitions "$my_partition_efi"

  create_btrfs_subvolumes "$my_root_mount"

  mount_subvolumes "$my_root_mount" "$MOUNTOPTS"

  mount_partitions "$my_root_mount" "$my_partition_efi"

  local -a all_pkgs=("${pacstrap_pkgs[@]}")
  [[ -n "$cpu_firmware" ]] && all_pkgs+=("$cpu_firmware")
  [[ -n "$hypervisor_pkgs" ]] && all_pkgs+=("$hypervisor_pkgs")
  pacstrap $my_root_mount "${all_pkgs[@]}" || \
    log_error "Failed to install base packages with pacstrap"

  genfstab -U $my_root_mount >> $my_root_mount/etc/fstab || \
    log_error "Failed to generate the File System TABle (fstab) using UUID numbers"

  install_gpu_drivers "$my_root_mount"
 
  configure_time_and_locale "$my_root_mount" "$my_timezone" "$my_host_name_dyn" "$host_domain_dyn"
 
  # Enable color output for pacman and specify the number of parallel downloads
  arch-chroot $my_root_mount sed -i 's/#Color/Color/;s/ParallelDownloads = 5/ParallelDownloads = 7/' "/etc/pacman.conf"

  configure_nic_fixes "$my_root_mount"

  install_and_configure_grub "$my_root_mount"

  enable_services "$my_root_mount" "${services_to_enable[@]}"

  sudo_enable_wheel_group "$my_root_mount"

  update_mkinitcpio "$my_root_mount"

  # Add a user account
  arch-chroot $my_root_mount useradd -c "$my_full_name" -mG wheel -s $my_shell -p "$my_password_hash" $my_user_id

  if [ "$install_podman_pkgs" -eq 0 ]; then
    log_info "Installing Podman packages"
    arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet "${podman_pkgs[@]}"
  fi

  if [ "$install_gui_apps" -eq 0 ]; then
    # Install KDE Plasma and sddm
    arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet xorg sddm plasma kde-applications
    
    # Enable SDDM display manager
    arch-chroot $my_root_mount systemctl enable sddm

    # Apply the Breeze theme to sddm
    mkdir -p $my_root_mount/etc/sddm.conf.d/
    arch-chroot $my_root_mount sed 's/Current=/Current=breeze/;w /etc/sddm.conf.d/sddm.conf' /usr/lib/sddm/sddm.conf.d/default.conf

    # Install the gui packages
    arch-chroot $my_root_mount pacman -Sy --needed --noconfirm --quiet "${gui_pkgs[@]}"
    if [ "$install_podman_pkgs" -eq 0 ]; then
      arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet podman-desktop
    fi
    
    # Add my ID to the wireshark group so I can view perform package captures
    arch-chroot $my_root_mount usermod -aG wireshark $my_user_id

  fi
  
  # Add my ID to the video group so I can view GPU performance counters
  arch-chroot $my_root_mount usermod -aG video $my_user_id
  
  # Install snapper
  arch-chroot $my_root_mount pacman -S --needed --noconfirm --quiet snapper snap-pac inotify-tools

  configure_snapper_first_boot "${my_root_mount}"
  
  configure_grub_for_snapshot_recovery "${my_root_mount}"

  # Allow root to have ssh access initially for troubleshooting while developing
  arch-chroot $my_root_mount sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

  create_post_install_scripts_for_user "${my_root_mount}" "${my_user_id}"

  # Enable oh-my-posh in zsh
  echo -e "\neval \"\$(oh-my-posh init zsh)\"" >> "$my_root_mount/home/$my_user_id/.zshrc";
  arch-chroot $my_root_mount chown $my_user_id:$my_user_id /home/$my_user_id/.zshrc

  create_script_to_install_flatpack_apps "${my_root_mount}" "${my_user_id}"

  arch-chroot $my_root_mount chown --recursive $my_user_id:$my_user_id /home/$my_user_id/Scripts

  # Copy this script to the root home directory
  mkdir -p "${my_root_mount}/root/Scripts"
  cp install.sh $my_root_mount/root/Scripts
  chmod -x $my_root_mount/root/Scripts/install.sh
  cp "$LOG_FILE" $my_root_mount/root/
  
  # Use the current mirrorlist in the final install, after /etc
  cp "${pacman_mirrorlist}" "${my_root_mount}${pacman_mirrorlist}"
  

  echo -e "${success_color}Please set a password for the new root account:${no_color}"
  arch-chroot $my_root_mount passwd root

  sync
  
  log_info "Script finished! Please reboot."
}
# endregion - Main Script Execution
# =============================================================================
trap 'log_error "Installation failed near line ${LINENO}. Check ${LOG_FILE}."' ERR
main "$@"
