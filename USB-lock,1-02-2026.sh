#!/bin/bash
# DEBIAN LOCKSMITH MASTER - V7 (Advanced Mount + Visual Search)
set -e 

LUKS_PART="/dev/nvme0n1p3"
USB_LABEL="DEBIAN_KEY"
KEY_FILE="debian_boot_key.bin"
BOOT_SCRIPT="/lib/cryptsetup/scripts/usb-unlock"

echo "=========================================="
echo "      DEBIAN LOCKSMITH MANAGER           "
echo "=========================================="
echo "1) Sync/Create USB Lock (Standard/Repair)"
echo "2) EMERGENCY: USB Stolen (Rotate Key)"
echo "3) Cancel"
read -p "Select an option [1-3]: " CHOICE

if [ "$CHOICE" == "3" ] || [ -z "$CHOICE" ]; then
    echo "Exiting..."
    exit 0
fi

echo "--- 1. Checking USB ---"
# Find mount point or device
USB_PATH=$(lsblk -no MOUNTPOINT,LABEL | grep "$USB_LABEL" | awk '{print $1}' | head -n 1)

if [ -z "$USB_PATH" ] || [ "$USB_PATH" == " " ]; then
    echo "❌ ERROR: USB labeled '$USB_LABEL' not found!"
    echo "Please mount it in your file manager first."
    exit 1
fi

FULL_KEY_PATH="$USB_PATH/$KEY_FILE"
echo "✅ Found USB at: $USB_PATH"

echo "--- 2. Key Management ---"
sudo cryptsetup luksDump "$LUKS_PART" | grep -q "1: luks2" && HAS_SLOT=0 || HAS_SLOT=1

if [ "$CHOICE" == "2" ]; then
    echo "🚨 EMERGENCY: Creating NEW secret..."
    if [ "$HAS_SLOT" -eq 0 ]; then sudo cryptsetup luksKillSlot "$LUKS_PART" 1; fi
    sudo dd if=/dev/urandom of="$FULL_KEY_PATH" bs=512 count=1
    sudo cryptsetup luksAddKey "$LUKS_PART" "$FULL_KEY_PATH" --key-slot 1
else
    if [ ! -f "$FULL_KEY_PATH" ]; then
        echo "No key found. Generating..."
        sudo dd if=/dev/urandom of="$FULL_KEY_PATH" bs=512 count=1
        if [ "$HAS_SLOT" -eq 0 ]; then sudo cryptsetup luksKillSlot "$LUKS_PART" 1; fi
        sudo cryptsetup luksAddKey "$LUKS_PART" "$FULL_KEY_PATH" --key-slot 1
    elif [ "$HAS_SLOT" -ne 0 ]; then
        sudo cryptsetup luksAddKey "$LUKS_PART" "$FULL_KEY_PATH" --key-slot 1
    else
        echo "✅ Key linked. Refreshing config..."
    fi
fi

echo "--- 3. Dry Test ---"
sudo cryptsetup luksOpen --test-passphrase "$LUKS_PART" --key-file "$FULL_KEY_PATH"

echo "--- 4. Injecting Advanced Fail-Safe Script ---"
sudo mkdir -p /lib/cryptsetup/scripts/
sudo tee "$BOOT_SCRIPT" > /dev/null << 'INNEREOF'
#!/bin/sh
MNT="/tmp/u"
mkdir -p "$MNT"
TARGET="/dev/disk/by-label/DEBIAN_KEY"
KEY_FILE="debian_boot_key.bin"

# Visual Search Feedback
printf "Searching for USB Key [%s] " "$TARGET" >&2
for i in $(seq 1 15); do
    if [ -e "$TARGET" ]; then
        # Try multiple mount methods for maximum compatibility
        if mount -o ro "$TARGET" "$MNT" >/dev/null 2>&1 || \
           mount -t vfat -o ro "$TARGET" "$MNT" >/dev/null 2>&1 || \
           mount -t exfat -o ro "$TARGET" "$MNT" >/dev/null 2>&1; then
            
            if [ -f "$MNT/$KEY_FILE" ]; then
                printf " [FOUND!]\n" >&2
                cat "$MNT/$KEY_FILE"
                umount "$MNT"
                exit 0
            fi
            umount "$MNT"
        fi
    fi
    printf "." >&2
    sleep 1
done
printf " [NOT FOUND]\n" >&2
/lib/cryptsetup/askpass "Enter LUKS Password: "
INNEREOF

sudo chmod +x "$BOOT_SCRIPT"
sudo update-initramfs -u

echo "------------------------------------------------"
echo "🎉 DONE! Ready for Dry Run."
echo "------------------------------------------------"
