#!/bin/bash
# 1. Test Network and Auto-Connect if needed
echo "Checking network connectivity..."
if ! ping -c 3 google.com > /dev/null 2>&1; then
    echo "No internet detected. Attempting to bring up interface via nmcli..."
    # Finds the first physical device that isn't the loopback 'lo'
    INTERFACE=$(nmcli -t -f DEVICE device | grep -v "^lo$" | head -n 1)
    if [ -n "$INTERFACE" ]; then
        nmcli device connect "$INTERFACE"
        sleep 2
    else
        echo "Error: No network interface found."
        exit 1
    fi
fi

# Re-verify after attempt
ping -c 3 google.com || { echo "Still no internet. Check your cable/WiFi."; exit 1; }

# 2. Install GUI and X11
echo "Installing Xfce and X11..."
dnf groupinstall -y "Xfce" "base-x"
dnf install -y lightdm lightdm-gtk-greeter

# 3. Set up the Environment
echo "Configuring system targets..."
systemctl set-default graphical.target
systemctl enable lightdm

# 4. Final Log Check before starting
echo "Installation complete. Checking logs for errors..."
journalctl -p 3 -xb --no-pager | tail -n 10

# 5. Start GUI
echo "Launching GUI..."
systemctl start lightdm
