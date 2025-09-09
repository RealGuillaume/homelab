#!/bin/bash

# Create symlinks from old storage location to new fast storage
echo "Creating symlinks for existing PVCs..."

for pvc_dir in $(ls /mnt/k3s-storage/pvc/); do
  echo "Creating symlink for $pvc_dir"
  
  # Backup original if it exists
  if [ -d "/var/lib/rancher/k3s/storage/$pvc_dir" ]; then
    echo "Backing up original $pvc_dir"
    sudo mv "/var/lib/rancher/k3s/storage/$pvc_dir" "/var/lib/rancher/k3s/storage/${pvc_dir}.backup"
  fi
  
  # Create symlink
  sudo ln -sf "/mnt/k3s-storage/pvc/$pvc_dir" "/var/lib/rancher/k3s/storage/$pvc_dir"
done

echo "Symlinks created successfully!"
echo "Listing symlinks:"
ls -la /var/lib/rancher/k3s/storage/ | grep "^l"