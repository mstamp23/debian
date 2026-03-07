#!/bin/bash
# 1. Test Network Connectivity
echo "Checking network status..."
ping -c 3 google.com || { echo "No internet. Use 'nmcli device connect' first."; exit 1; }

# 2. Install GUI, X11, and the Greeter
echo "Installing XFCE and Display Manager..."
dnf groupinstall -y "Xfce" "base-x"
dnf install -y lightdm lightdm-gtk-greeter mousepad

# 3. Configure Autologin for user 'm'
echo "Configuring autologin for user m..."
mkdir -p /etc/lightdm/lightdm.conf.d/
echo -e "[Seat:*]\nautologin-user=m\nautologin-user-timeout=0" > /etc/lightdm/lightdm.conf.d/01-autologin.conf

# 4. Set System Targets
echo "Setting graphical target..."
systemctl set-default graphical.target
systemctl enable lightdm

# 5. Final Log Check for Errors
echo "Installation complete. Checking logs for critical errors..."
journalctl -p 3 -xb --no-pager | tail -n 10

# 6. Start the GUI
echo "Starting GUI..."
systemctl start lightdm
