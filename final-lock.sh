#!/bin/bash
# Universal Locksmith - Stable Stealth Version
# Run this on any new PC to add it to your USB

echo "--- Step 1: Stable Fingerprinting ---"
# Only use CPU name - most reliable for boot-time
CPU_ID=$(cat /proc/cpuinfo | grep "model name" | head -n 1 | awk '{print $4$5}' | tr -d ' ')
HW_ID="${CPU_ID}"

# Detect internal drive and mapper name
CRYPT_NAME=$(lsblk -rn -o NAME,TYPE | grep crypt | awk '{print $1}' | head -n 1)
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
USB_PART=$(lsblk -p -n -l -o NAME,LABEL | grep "DEBIAN_KEY" | awk '{print $1}')

if [ -z "$CRYPT_NAME" ] || [ -z "$USB_PART" ]; then
    echo "ERROR: Detection failed. Is the USB plugged in?"
    exit 1
fi

echo "PC Fingerprint: $HW_ID"

# 2. Key Generation
echo "--- Step 2: Creating Hidden Key ---"
MNT_TEMP="/mnt/usb_setup"
sudo mkdir -p $MNT_TEMP
sudo mount $USB_PART $MNT_TEMP
KEYFILE="$MNT_TEMP/.$HW_ID.bin"

if [ ! -f "$KEYFILE" ]; then
    sudo dd if=/dev/urandom of="$KEYFILE" bs=512 count=1
    echo "New hidden key created: .$HW_ID.bin"
else
    echo "Existing key found for this CPU type. Using it..."
fi

echo "Registering key to this PC's hard drive..."
sudo cryptsetup luksAddKey $LUKS_PART "$KEYFILE"
sudo umount $MNT_TEMP

echo "--- SUCCESS ---"
echo "This PC is now registered to the USB under the ID: $HW_ID"
