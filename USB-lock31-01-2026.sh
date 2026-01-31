#!/bin/bash
# Debian 13 "Locksmith" - V3 Robust Version

# 1. Setup
USB_PART=$(lsblk -p -n -l -o NAME,RM,TYPE | grep " 1 part" | awk '{print $1}' | head -n 1)
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
KEY_NAME="debian_boot_key.bin"

# 2. Menu
CHOICE=$(whiptail --title "Universal Locksmith" --menu "Select Action:" 15 60 2 \
"1" "REFRESH: Update the key file on USB" \
"2" "RESET: Clear all USB slots & start fresh" 3>&1 1>&2 2>&3)

if [ "$CHOICE" = "2" ]; then
    if (whiptail --title "SECURITY RESET" --yesno "Wipe ALL USB keys from disk? (Password stays safe)" 8 60); then
        for slot in $(seq 1 7); do sudo cryptsetup luksKillSlot "$LUKS_PART" $slot 2>/dev/null; done
    else
        exit 1
    fi
fi

# 3. Provisioning
MNT_TEMP="/mnt/usb_key_setup"
sudo mkdir -p $MNT_TEMP
sudo mount "$USB_PART" $MNT_TEMP

# Create new key if Reset was chosen or file is missing
if [ "$CHOICE" = "2" ] || [ ! -f "$MNT_TEMP/$KEY_NAME" ]; then
    # Remove any old .bin files to prevent confusion
    sudo rm -f $MNT_TEMP/*.bin
    sudo dd if=/dev/urandom of="$MNT_TEMP/$KEY_NAME" bs=512 count=1
    echo "Registering new key to LUKS..."
    sudo cryptsetup luksAddKey "$LUKS_PART" "$MNT_TEMP/$KEY_NAME" --key-slot 1
fi
sudo umount $MNT_TEMP

# 4. The 9-Second Boot Script
sudo mkdir -p /lib/cryptsetup/scripts
sudo tee /lib/cryptsetup/scripts/usb-unlock > /dev/null << 'EOF'
#!/bin/sh
MNT="/tmp/u"
mkdir -p $MNT

# Pulse for 9 seconds (90 * 0.1s)
i=0
while [ $i -lt 90 ]; do
    for dev in $(lsblk -p -n -l -o NAME,RM,TYPE | grep " 1 part" | awk '{print $1}'); do
        if mount -o ro "$dev" "$MNT" >/dev/null 2>&1; then
            FOUND_KEY=$(ls $MNT/*.bin 2>/dev/null | head -n 1)
            if [ -f "$FOUND_KEY" ]; then
                cat "$FOUND_KEY"
                umount "$MNT"
                exit 0
            fi
            umount "$MNT" 2>/dev/null
        fi
    done
    i=$((i+1))
    sleep 0.1
done
/lib/cryptsetup/askpass "USB Key not found. Enter Password: "
EOF
sudo chmod +x /lib/cryptsetup/scripts/usb-unlock

# 5. Finalize
sudo update-initramfs -u
whiptail --title "Success" --msgbox "Configuration Updated!\n\nTimeout: 9 Seconds\nKey: $KEY_NAME\n\nReady for another test." 10 50
