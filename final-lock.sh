#!/bin/bash
# Universal Locksmith for Multiple PCs

echo "--- Step 1: Hardware Detection ---"
# Detect internal drive and name
CRYPT_NAME=$(lsblk -rn -o NAME,TYPE | grep crypt | awk '{print $1}' | head -n 1)
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
LUKS_UUID=$(blkid -s UUID -o value $LUKS_PART)
# Detect USB
USB_PART=$(lsblk -p -n -l -o NAME,RM,TYPE | grep " 1 part" | awk '{print $1}' | head -n 1)
MY_NAME=$(hostname)

if [ -z "$CRYPT_NAME" ] || [ -z "$USB_PART" ]; then
    echo "ERROR: USB not found or LUKS not detected."
    exit 1
fi

echo "PC Name: $MY_NAME | Internal: $CRYPT_NAME | USB: $USB_PART"

# 2. USB Preparation (Smart Check)
echo "--- Step 2: Preparing USB Keychain ---"
USB_TYPE=$(lsblk -no FSTYPE $USB_PART)

if [ "$USB_TYPE" != "ext4" ]; then
    echo "New USB detected. Formatting to ext4..."
    sudo umount $USB_PART 2>/dev/null
    sudo mkfs.ext4 -F -L "LOCKSMITH" $USB_PART
else
    echo "Existing Locksmith USB detected. Keeping data..."
fi

USB_UUID=$(blkid -s UUID -o value $USB_PART)

# 3. Key Generation
echo "--- Step 3: Creating Key for $MY_NAME ---"
MNT_TEMP="/mnt/usb_setup"
sudo mkdir -p $MNT_TEMP
sudo mount $USB_PART $MNT_TEMP
KEYFILE="$MNT_TEMP/${MY_NAME}_key.bin"

# Create a unique key for this specific machine if it doesn't exist
if [ ! -f "$KEYFILE" ]; then
    sudo dd if=/dev/urandom of="$KEYFILE" bs=512 count=1
fi

echo "Please enter your LUKS password to register this PC's key:"
sudo cryptsetup luksAddKey $LUKS_PART "$KEYFILE"
sudo umount $MNT_TEMP

# 4. Writing the Boot Script
echo "--- Step 4: Writing Boot Script ---"
sudo tee /usr/local/sbin/usb-unlock << EOF
#!/bin/sh
MY_NAME=\$(hostname)
DEVICE="/dev/disk/by-uuid/$USB_UUID"
MNT="/tmp/usb-key"
mkdir -p \$MNT
for i in \$(seq 1 15); do
    if [ -b "\$DEVICE" ]; then
        if mount -t ext4 -o ro "\$DEVICE" \$MNT >/dev/null 2>&1; then
            if [ -f "\$MNT/\${MY_NAME}_key.bin" ]; then
                cat "\$MNT/\${MY_NAME}_key.bin"
                umount \$MNT
                exit 0
            fi
            umount \$MNT
        fi
    fi
    sleep 2
done
/lib/cryptsetup/askpass "Key for \$MY_NAME not found. Enter LUKS Password: "
EOF
sudo chmod +x /usr/local/sbin/usb-unlock

# 5. System Configuration
echo "--- Step 5: Configuring Crypttab & Initramfs ---"
echo "$CRYPT_NAME UUID=$LUKS_UUID none luks,keyscript=/usr/local/sbin/usb-unlock" | sudo tee /etc/crypttab
grep -qxF "ext4" /etc/initramfs-tools/modules || echo "ext4" | sudo tee -a /etc/initramfs-tools/modules
sudo update-initramfs -u

echo "--- SUCCESS ---"
echo "You can now reboot manually. The USB will unlock this PC automatically."
