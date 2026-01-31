#!/bin/bash
# Debian 13 "Locksmith" - With Emergency Reset & Dialogs

# 1. Hardware Fingerprint
D_MODEL=$(lsblk -d -n -o MODEL | head -n 1 | tr -dc '[:alnum:]')
G_MODEL=$(lspci | grep -i vga | awk '{print $5}' | head -n 1 | tr -dc '[:alnum:]')
HW_ID="${D_MODEL}_${G_MODEL}"
KEY_NAME="${HW_ID}.bin"

# 2. Identification
CRYPT_NAME=$(lsblk -rn -o NAME,TYPE | grep crypt | awk '{print $1}' | head -n 1)
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
USB_PART=$(lsblk -p -n -l -o NAME,RM,TYPE | grep " 1 part" | awk '{print $1}' | head -n 1)

if [ -z "$USB_PART" ]; then
    whiptail --title "Error" --msgbox "No USB detected. Please insert the flash drive." 8 45
    exit 1
fi

# 3. Menu System
CHOICE=$(whiptail --title "Universal Locksmith" --menu "Choose an action:" 15 60 2 \
"1" "ADD/UPDATE: Add this USB as a key (Safe)" \
"2" "RESET SECURITY: Wipe old keys and create new ones" 3>&1 1>&2 2>&3)

if [ "$CHOICE" = "2" ]; then
    if (whiptail --title "WARNING" --yesno "This will wipe ALL USB keys for this PC from the disk. Continue?" 8 60); then
        # This keeps slot 0 (usually your password) and wipes others
        echo "Wiping secondary LUKS slots..."
        sudo cryptsetup luksKillSlot "$LUKS_PART" 1 2>/dev/null
        sudo cryptsetup luksKillSlot "$LUKS_PART" 2 2>/dev/null
    else
        exit 1
    fi
fi

# 4. Provisioning
MNT_TEMP="/mnt/usb_key_setup"
sudo mkdir -p $MNT_TEMP
sudo mount "$USB_PART" $MNT_TEMP

# Force new key if Reset was chosen
if [ "$CHOICE" = "2" ] || [ ! -f "$MNT_TEMP/$KEY_NAME" ]; then
    sudo dd if=/dev/urandom of="$MNT_TEMP/$KEY_NAME" bs=512 count=1
fi

echo "Registering key to LUKS (Enter your PASSWORD)..."
sudo cryptsetup luksAddKey "$LUKS_PART" "$MNT_TEMP/$KEY_NAME"
sudo umount $MNT_TEMP

# 5. Boot Logic Generation (Fast Scan)
sudo tee /usr/local/sbin/usb-unlock << 'EOF'
#!/bin/sh
# Fast-Scan Boot Script
MNT="/tmp/u"
mkdir -p $MNT
D_ID=$(lsblk -d -n -o MODEL | head -n 1 | tr -dc '[:alnum:]')
G_ID=$(lspci | grep -i vga | awk '{print $5}' | head -n 1 | tr -dc '[:alnum:]')
MY_KEY="${D_ID}_${G_ID}.bin"

# 10 second timeout for USB detection
for i in 1 2 3 4 5 6 7 8 9 10; do
    # Only scan removable devices to save time
    for dev in $(lsblk -p -n -l -o NAME,RM | grep " 1$" | awk '{print $1}'); do
        mount -o ro "$dev" "$MNT" >/dev/null 2>&1
        if [ -f "$MNT/$MY_KEY" ]; then
            cat "$MNT/$MY_KEY"
            umount "$MNT"
            exit 0
        fi
        umount "$MNT" 2>/dev/null
    done
    sleep 1
done
# Fail-safe: Jump to manual password
/lib/cryptsetup/askpass "Key not found. Enter Password: "
EOF
sudo chmod +x /usr/local/sbin/usb-unlock

# 6. Finalize
sudo tee /etc/initramfs-tools/hooks/usb_unlock_hook << 'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0;; esac
. /usr/share/initramfs-tools/hook-functions
copy_exec /usr/local/sbin/usb-unlock /sbin
copy_exec /usr/bin/lspci /usr/bin
copy_exec /usr/bin/lsblk /usr/bin
copy_exec /usr/bin/grep /usr/bin
EOF
sudo chmod +x /etc/initramfs-tools/hooks/usb_unlock_hook

# Update crypttab only if missing
if ! grep -q "keyscript" /etc/crypttab; then
    sudo cp /etc/crypttab /etc/crypttab.bak
    echo "$CRYPT_NAME UUID=$(blkid -s UUID -o value $LUKS_PART) none luks,keyscript=/sbin/usb-unlock" | sudo tee /etc/crypttab
fi

sudo update-initramfs -u
whiptail --title "Success" --msgbox "System updated. Reboot to test." 8 45
