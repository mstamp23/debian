#!/bin/bash
# Master-Lock: Windows-to-Debian Transition Final Version

echo "--- Step 1: Real-Hardware Detection ---"
# Detect NVMe/SSD Mapper Name (e.g., nvme0n1p3_crypt)
CRYPT_NAME=$(lsblk -rn -o NAME,TYPE | grep crypt | awk '{print $1}' | head -n 1)
# Detect the physical partition
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
LUKS_UUID=$(blkid -s UUID -o value $LUKS_PART)
# Detect USB (Looking for DEBIAN_KEY label)
USB_PART=$(lsblk -p -n -l -o NAME,LABEL | grep "DEBIAN_KEY" | awk '{print $1}')
USB_UUID=$(lsblk -no UUID $USB_PART)

# Generate Hardware Fingerprint
CPU_ID=$(cat /proc/cpuinfo | grep "model name" | head -n 1 | awk '{print $4$5}' | tr -d ' ')
DISK_SIZE=$(cat /sys/block/$(echo $LUKS_PART | cut -d'/' -f3 | sed 's/p[0-9]//')/size)
HW_ID="${CPU_ID}_${DISK_SIZE}"

if [ -z "$CRYPT_NAME" ] || [ -z "$USB_PART" ]; then
    echo "ERROR: USB 'DEBIAN_KEY' or LUKS partition not found."
    exit 1
fi

echo "PC: $HW_ID | Disk: $CRYPT_NAME | USB: $USB_PART"

# 2. Stealth Key Placement
echo "--- Step 2: Registering Stealth Key ---"
MNT_TEMP="/mnt/usb_setup"
sudo mkdir -p $MNT_TEMP
sudo mount $USB_PART $MNT_TEMP
KEYFILE="$MNT_TEMP/.$HW_ID.bin"

if [ ! -f "$KEYFILE" ]; then
    sudo dd if=/dev/urandom of="$KEYFILE" bs=512 count=1
    echo "Created new hidden key: .$HW_ID.bin"
fi

echo "Enter LUKS password to register this PC to the USB:"
sudo cryptsetup luksAddKey $LUKS_PART "$KEYFILE"
sudo umount $MNT_TEMP

# 3. The Unlock Logic (The Boot Script)
echo "--- Step 3: Writing Boot-time Unlocker ---"
sudo tee /usr/local/sbin/usb-unlock << EOF
#!/bin/sh
# Re-fingerprint at boot
CPU=\$(cat /proc/cpuinfo | grep "model name" | head -n 1 | awk '{print \$4\$5}' | tr -d ' ')
# Dynamic NVMe detection
D_SIZE=\$(cat /sys/block/\$(lsblk -p -n -l -o NAME,TYPE | grep "disk" | head -n 1 | cut -d'/' -f3)/size)
HW_ID="\${CPU}_\${D_SIZE}"

DEVICE="/dev/disk/by-uuid/$USB_UUID"
MNT="/tmp/usb-key"
mkdir -p \$MNT

for i in \$(seq 1 15); do
    if [ -b "\$DEVICE" ]; then
        if mount -t ext4 -o ro "\$DEVICE" \$MNT >/dev/null 2>&1; then
            if [ -f "\$MNT/.\${HW_ID}.bin" ]; then
                cat "\$MNT/.\${HW_ID}.bin"
                umount \$MNT
                exit 0
            fi
            umount \$MNT
        fi
    fi
    sleep 2
done
/lib/cryptsetup/askpass "Stealth Key Not Found (\${HW_ID}). Password: "
EOF
sudo chmod +x /usr/local/sbin/usb-unlock

# 4. Packing the "Suitcase" (Initramfs Hook)
echo "--- Step 4: Forcing Tools into Boot Image ---"
sudo tee /etc/initramfs-tools/hooks/usb-unlock << 'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case "$1" in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions

copy_exec /usr/local/sbin/usb-unlock /usr/local/sbin
copy_exec /bin/cat /bin
copy_exec /usr/bin/grep /bin
copy_exec /usr/bin/awk /bin
copy_exec /usr/bin/lsblk /bin
copy_exec /bin/mount /bin
copy_exec /bin/umount /bin
copy_exec /bin/sleep /bin
manual_add_modules ext4
manual_add_modules nvme
EOF
sudo chmod +x /etc/initramfs-tools/hooks/usb-unlock

# 5. Finalize Configuration
echo "--- Step 5: Updating System Config ---"
echo "$CRYPT_NAME UUID=$LUKS_UUID none luks,keyscript=/usr/local/sbin/usb-unlock" | sudo tee /etc/crypttab
sudo update-initramfs -u

echo "--- MASTER-LOCK COMPLETE ---"
echo "Reboot and watch the magic."
