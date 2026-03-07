#!/bin/bash
# 1. Test Network first
ping -c 3 google.com || { echo "No internet. Check nmcli."; exit 1; }

# 2. Install GUI and X11
dnf groupinstall -y "Xfce" "base-x"
dnf install -y lightdm lightdm-gtk-greeter

# 3. Set up the Environment
systemctl set-default graphical.target
systemctl enable lightdm

# 4. Final Log Check before starting
echo "Installation complete. Checking logs for errors..."
journalctl -p 3 -xb --no-pager

# 5. Start GUI
systemctl start lightdm
