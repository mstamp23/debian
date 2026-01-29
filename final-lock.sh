#!/bin/bash
# Universal Locksmith - Hardware Fingerprint Version

echo "--- Step 1: Fingerprinting Hardware ---"
# Get CPU name (e.g., Corei7)
CPU_ID=$(lscpu | grep "Model name" | awk '{print $3$4}' | tr -d ' ')
# Get Disk Size (e.g., 500G)
DISK_SIZE=$(lsblk -bno SIZE /dev/sda | head -n 1 | awk '{print $1}')
# Combine them for a unique ID
HW_ID="${CPU_ID}_${DISK_SIZE}"

# Detect internal drive and name
CRYPT_NAME=$(lsblk -rn -o NAME,TYPE | grep crypt | awk '{print $1}' | head -n 1)
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
LUKS_UUID=$(blkid -s UUID -o value $LUKS_PART)
# Detect USB
USB_PART=$(lsblk -p -n -l -o NAME,RM,TYPE | grep " 1 part" | awk '{print $1}' | head -n 1)

if [ -z "$CRYPT_NAME" ] || [ -z "$USB_PART" ]; then
    echo "ERROR: Detection failed."
    exit 1
fi

echo "Hardware ID: $HW_ID"
echo "Mapper Name: $CRYPT_NAME"

# 2. USB Preparation (Safety Check)
echo "--- Step 2: Preparing USB ---"
USB_TYPE=$(lsblk -no FSTYPE $USB_PART)
if [ "$USB_TYPE" != "ext4" ]; then
    sudo umount $USB_PART 2>/dev/null
    sudo mkfs.ext4 -F -L "LOCKSMITH" $USB_PART
fi
USB_UUID=$(blkid -s UUID -o value $USB_PART)

# 3. Key Generation
echo "--- Step 3: Registering Key ---"
MNT_TEMP="/mnt/usb_setup"
sudo mkdir -p $MNT_TEMP
sudo mount $USB_PART $MNT_TEMP
# The key is named after the Hardware ID
KEYFILE="$MNT_TEMP/${HW_ID}.bin"

if [ ! -f "$KEYFILE" ]; then
    sudo dd if=/dev/urandom of="$KEYFILE" bs=512 count=1
fi

echo "Please enter LUKS password to register this hardware key:"
sudo cryptsetup luksAddKey $LUKS_PART "$KEYFILE"
sudo umount $MNT_TEMP

# 4. Writing the Boot Script
echo "--- Step 4: Writing Boot Script ---"
sudo tee /usr/local/sbin/usb-unlock << EOF
#!/bin/sh
# Re-detect fingerprint at boot
CPU=\$(lscpu | grep "Model name" | awk '{print \$3\$4}' | tr -d ' ')
D_SIZE=\$(lsblk -bno SIZE /dev/sda | head -n 1 | awk '{print \$1}')
HW_ID="\${CPU}_\${D_SIZE}"

DEVICE="/dev/disk/by-uuid/$USB_UUID"
MNT="/tmp/usb-key"
mkdir -p \$MNT

for i in \$(seq 1 15); do
    if [ -b "\$DEVICE" ]; then
        if mount -t ext4 -o ro "\$DEVICE" \$MNT >/dev/null 2>&1; then
            if [ -f "\$MNT/\${HW_ID}.bin" ]; then
                cat "\$MNT/\${HW_ID}.bin"
                umount \$MNT
                exit 0
            fi
            umount \$MNT
        fi
    fi
    sleep 2
done
/lib/cryptsetup/askpass "Key for \$HW_ID not found. Enter LUKS Password: "
EOF
sudo chmod +x /usr/local/sbin/usb-unlock

# 5. System Configuration
echo "--- Step 5: Finalizing ---"
echo "$CRYPT_NAME UUID=$LUKS_UUID none luks,keyscript=/usr/local/sbin/usb-unlock" | sudo tee /etc/crypttab
grep -qxF "ext4" /etc/initramfs-tools/modules || echo "ext4" | sudo tee -a /etc/initramfs-tools/modules
sudo update-initramfs -u

echo "--- SUCCESS ---"
echo "Key generated: ${HW_ID}.bin"
