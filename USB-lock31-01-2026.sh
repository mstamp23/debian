#!/bin/sh
# Debian 13 "Locksmith" - Full Features - Strict SH Mode

echo "--------------------------------------"
echo "   DEBIAN 13 USB LOCKSMITH V5"
echo "--------------------------------------"

# 1. Hardware Detection
USB_PART=$(lsblk -p -n -l -o NAME,RM,TYPE | grep " 1 part" | awk '{print $1}' | head -n 1)
LUKS_PART=$(lsblk -f | grep crypto_LUKS | awk '{print "/dev/"$1}' | head -n 1 | sed 's/[^a-zA-Z0-9/]//g')
KEY_NAME="debian_boot_key.bin"

if [ -z "$USB_PART" ]; then
    echo "❌ ERROR: No USB partition found! Plug it in first."
    exit 1
fi

# 2. Correct Dialog Menu
echo "1) REFRESH: Use existing key or update"
echo "2) RESET: Wipe slots 1-7 and start fresh"
echo "3) CANCEL: Exit script"
printf "Select an option [1-3]: "
read CHOICE

case "$CHOICE" in
    2)
        echo "🧹 Wiping old keyslots (1-7)..."
        for slot in 1 2 3 4 5 6 7; do 
            sudo cryptsetup luksKillSlot "$LUKS_PART" $slot 2>/dev/null
        done
        ;;
    3)
        echo "Exiting..."
        exit 0
        ;;
    *)
        echo "Continuing with Refresh/Update..."
        ;;
esac

# 3. Provision USB
MNT_TEMP="/mnt/usb_key_setup"
sudo mkdir -p "$MNT_TEMP"
sudo mount "$USB_PART" "$MNT_TEMP"

if [ "$CHOICE" = "2" ] || [ ! -f "$MNT_TEMP/$KEY_NAME" ]; then
    echo "📝 Generating new key file on $USB_PART..."
    sudo rm -f "$MNT_TEMP"/*.bin
    sudo dd if=/dev/urandom of="$MNT_TEMP/$KEY_NAME" bs=512 count=1
    sudo cryptsetup luksAddKey "$LUKS_PART" "$MNT_TEMP/$KEY_NAME" --key-slot 1
else
    echo "✅ Key already exists. Ensuring it is registered in Slot 1..."
    sudo cryptsetup luksAddKey "$LUKS_PART" "$MNT_TEMP/$KEY_NAME" --key-slot 1 2>/dev/null
fi
sudo umount "$MNT_TEMP"

# 4. Write the Aggressive Boot Script
echo "⚙️ Installing Boot Script to /lib/cryptsetup/scripts/..."
sudo tee /lib/cryptsetup/scripts/usb-unlock > /dev/null << 'INNEREOF'
#!/bin/sh
MNT="/tmp/u"
mkdir -p "$MNT"
sleep 5
i=0
while [ "$i" -lt 150 ]; do
    for dev in /dev/sd[a-z][0-9] /dev/nvme[0-9]n[0-9]p[0-9]; do
        if [ -b "$dev" ]; then
            if mount -o ro "$dev" "$MNT" >/dev/null 2>&1; then
                FOUND_KEY=$(ls "$MNT"/*.bin 2>/dev/null | head -n 1)
                if [ -f "$FOUND_KEY" ]; then
                    cat "$FOUND_KEY"
                    umount "$MNT"
                    exit 0
                fi
                umount "$MNT" 2>/dev/null
            fi
        fi
    done
    i=$((i + 1))
    sleep 0.1
done
/lib/cryptsetup/askpass "USB Key not found. Enter Password: "
INNEREOF

sudo chmod +x /lib/cryptsetup/scripts/usb-unlock
echo "📦 Rebuilding Boot Image (Initramfs)..."
sudo update-initramfs -u
echo "✅ ALL DONE! Script is ready."
