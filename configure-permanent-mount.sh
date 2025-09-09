#!/bin/bash

echo "Configuring permanent mount for k3s storage..."

# Add to /etc/fstab if not already present
if ! grep -q "/mnt/k3s-storage" /etc/fstab; then
    echo "Adding mount to /etc/fstab..."
    echo "/dev/sde1 /mnt/k3s-storage ext4 defaults,nofail 0 0" | sudo tee -a /etc/fstab
else
    echo "Mount already in /etc/fstab"
fi

# Create WSL config for auto-mount
echo "Creating WSL configuration..."
sudo tee /etc/wsl.conf << 'EOF'
[boot]
systemd=true
command = mount -a

[automount]
enabled = true
options = "metadata"
EOF

echo "Configuration complete!"
echo ""
echo "For Windows auto-mount on boot, create this batch file:"
echo "C:\Users\[YourUsername]\mount-wsl-storage.bat"
echo "----------------------------------------"
echo "@echo off"
echo "wsl --mount \\.\PHYSICALDRIVE0 --bare"
echo 'wsl -d Ubuntu -u root -e sh -c "mount /dev/sde1 /mnt/k3s-storage 2>/dev/null || true"'
echo "----------------------------------------"
echo ""
echo "Add it to Windows Task Scheduler to run at startup with admin privileges."