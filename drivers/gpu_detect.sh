#!/usr/bin/env bash

detect_gpu() {
    # Get PCI IDs. -nn shows numeric IDs. -k shows kernel driver in use.
    local pci_info=$(lspci -nn -k | grep -A 3 -E 'VGA|3D')
    
    # Extract Vendor ID (first 4 chars after [)
    # Example: [10de:1b80] -> 10de
    local vendor_id=$(echo "$pci_info" | grep -oP '\[\K[0-9a-f]{4}' | head -1)

    case "$vendor_id" in
        10de)
            echo "NVIDIA"
            ;;
        1002)
            echo "AMD"
            ;;
        8086)
            echo "Intel"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
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


install_gpu_drivers() {
    local gpu_type
    gpu_type=$(detect_gpu)
    
    echo "Detected GPU Vendor: $gpu_type"

    case "$gpu_type" in
        NVIDIA)
            echo "Installing NVIDIA proprietary drivers..."
            
            # Ensure DKMS and headers are present
            pacman -S --noconfirm linux-headers base-devel
            
            # Install nvidia-dkms (handles kernel updates automatically)
            pacman -S --noconfirm nvidia-dkms nvidia-utils libva-nvidia-driver
            
            # Configure GRUB
            configure_grub_nvidia
            ;;
        AMD)
            echo "Installing AMD drivers..."
            pacman -S --noconfirm mesa lib32-mesa xf86-video-amdgpu amd-ucode
            ;;
        Intel)
            echo "Installing Intel drivers..."
            pacman -S --noconfirm mesa lib32-mesa intel-media-driver intel-ucode
            ;;
        *)
            echo "WARNING: Unknown GPU detected. Manual intervention may be required."
            ;;
    esac
    
    # Rebuild initramfs to ensure new modules are included
    mkinitcpio -P
    
    echo "Driver installation complete. Reboot required."
}
