#!/bin/bash
echo "Hello world!"

# Start here...
sgdisk --zap-all --clear /dev/sda
sgdisk --new=1:0:+550M --typecode=1:ef00 --change-name=1:EFI /dev/sda
sgdisk --new=2:0:0 --typecode=2:8300 --change-name=2:root /dev/sda
mkfs.fat -F 32 /dev/sda1
