#!/bin/bash
# Debian 13 "The Twist" - Final Hardware-Aware Version

# 1. Detection Phase (Dynamic)
echo "--- Step 1: Detecting Hardware Names ---"
# This finds the actual mapper name (e.g., sda5_crypt) used by your system
CRYPT_NAME=$(lsblk -rn -o NAME,TYPE | grep crypt | awk '{print $1}' | head -n 1)
# This finds the physical partition (e.g., /dev/sda5)
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
LUKS_UUID=$(blkid -s UUID -o value $LUKS_PART)
# This finds the USB partition
USB_PART=$(lsblk -p -n -l -o NAME,RM,TYPE | grep " 1 part" | awk '{print $1}' | head -n 1)

if [ -z "$CRYPT_NAME" ] || [ -z "$LUKS_PART" ] || [ -z "$USB_PART" ]; then
    echo "ERROR: Detection failed. Ensure LUKS is open and USB is plugged in."
    exit 1
fi

echo "Using Mapper Name: $CRYPT_NAME"
echo "Using LUKS Device: $LUKS_PART"
echo "Using USB Device:  $USB_PART"

# 2. Formatting USB to ext4
echo "--- Step 2: Preparing USB Key (ext4) ---"
sudo umount $USB_PART 2>/dev/null
sudo mkfs.ext4 -F -L DEBIAN_KEY $USB_PART
USB_UUID=$(blkid -s UUID -o value $USB_PART)

# 3. Key Generation
echo "--- Step 3: Generating and Adding Key ---"
MNT_TEMP="/mnt/usb_setup"
sudo mkdir -p $MNT_TEMP
sudo mount $USB_PART $MNT_TEMP
sudo dd if=/dev/urandom of=$MNT_TEMP/mykey.bin bs=512 count=1
echo "AUTHENTICATION REQUIRED: Adding USB key to LUKS slot..."
sudo cryptsetup luksAddKey $LUKS_PART $MNT_TEMP/mykey.bin
sudo umount $MNT_TEMP

# 4. Creating the Unlock Logic
echo "--- Step 4: Writing Unlock Script ---"
sudo tee /usr/local/sbin/usb-unlock << EOF
#!/bin/sh
# Locksmith Logic for $CRYPT_NAME
DEVICE="/dev/disk/by-uuid/$USB_UUID"
MNT="/tmp/usb-key"
mkdir -p \$MNT

for i in \$(seq 1 15); do
    if [ -b "\$DEVICE" ]; then
        if mount -t ext4 -o ro "\$DEVICE" \$MNT >/dev/null 2>&1; then
            if [ -f "\$MNT/mykey.bin" ]; then
                cat "\$MNT/mykey.bin"
                umount \$MNT
                exit 0
            fi
            umount \$MNT
        fi
    fi
    sleep 2
done
/lib/cryptsetup/askpass "USB Key not found. Enter LUKS Password: "
EOF
sudo chmod +x /usr/local/sbin/usb-unlock

# 5. Configuring the System
echo "--- Step 5: Configuring Crypttab & Drivers ---"
# Set the crypttab with the dynamic name
echo "$CRYPT_NAME UUID=$LUKS_UUID none luks,keyscript=/usr/local/sbin/usb-unlock" | sudo tee /etc/crypttab

# Add ext4 and usb drivers to boot image
grep -qxF "ext4" /etc/initramfs-tools/modules || echo "ext4" | sudo tee -a /etc/initramfs-tools/modules
grep -qxF "usb_storage" /etc/initramfs-tools/modules || echo "usb_storage" | sudo tee -a /etc/initramfs-tools/modules

# 6. Final Boot Image Update
echo "--- Step 6: Baking changes into Boot Image ---"
sudo update-initramfs -u

# 7. The Locksmith's Final Check (Dry Run)
echo "--- Step 7: Final Security Verification ---"
echo "Testing script for $CRYPT_NAME..."
CHECK_KEY=$(sudo /usr/local/sbin/usb-unlock 2>/dev/null)

if [ ${#CHECK_KEY} -gt 10 ]; then
    echo "SUCCESS: Key detected and readable!"
else
    echo "WARNING: Key check failed. Check your USB connection."
fi

echo "--- ALL DONE ---"
echo "Ready for reboot."
