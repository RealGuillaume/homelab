# Complete Guide: Adding Nodes and Storage to K3s Cluster with Longhorn

## Table of Contents
1. [Adding a Linux Node](#adding-a-linux-node)
2. [Adding a Windows Node (via WSL2)](#adding-a-windows-node-via-wsl2)
3. [Adding New Drives to Existing Nodes](#adding-new-drives-to-existing-nodes)
4. [Quick Reference Commands](#quick-reference-commands)

---

## Prerequisites for Any New Node

### Network Requirements
- Node must be on same network as master (or have network connectivity)
- Ports required:
  - 6443: Kubernetes API
  - 10250: Kubelet metrics
  - 10251: kube-scheduler
  - 8472: Flannel VXLAN (if using Flannel)
  - 2379-2380: etcd (if HA setup)

### Hardware Requirements
- Minimum 2GB RAM (4GB+ recommended)
- 2+ CPU cores
- 50GB+ storage for OS and Kubernetes
- Additional storage drive for Longhorn (500GB+ recommended)

---

## Adding a Linux Node

### Step 1: Prepare the Linux System

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget software-properties-common apt-transport-https ca-certificates

# Disable swap (required for Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Configure kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

### Step 2: Prepare Storage Drive

```bash
# List available disks
lsblk

# Assuming new disk is /dev/sdb
# Create partition (interactive)
sudo fdisk /dev/sdb
# Press: n (new partition)
# Press: p (primary)
# Press: 1 (partition number)
# Press: Enter (default first sector)
# Press: Enter (default last sector - use entire disk)
# Press: w (write changes)

# Format the partition
sudo mkfs.ext4 /dev/sdb1

# Create mount point for Longhorn
sudo mkdir -p /var/lib/longhorn

# Get UUID of the partition
UUID=$(sudo blkid -s UUID -o value /dev/sdb1)

# Add to fstab for permanent mounting
echo "UUID=$UUID /var/lib/longhorn ext4 defaults 0 2" | sudo tee -a /etc/fstab

# Mount the drive
sudo mount -a

# Verify mount
df -h /var/lib/longhorn
```

### Step 3: Get Join Information from Master Node

```bash
# On master node, get the token and CA cert hash
sudo cat /var/lib/rancher/k3s/server/node-token

# Get master node IP
hostname -I | awk '{print $1}'

# Note these values:
MASTER_IP=<master-ip>
NODE_TOKEN=<token-from-above>
```

### Step 4: Install K3s and Join Cluster

```bash
# On new node, install K3s as worker
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -

# Verify node joined
sudo k3s kubectl get nodes

# Label the node for Longhorn storage
sudo k3s kubectl label nodes $(hostname) node.longhorn.io/create-default-disk=true
```

### Step 5: Configure Longhorn on New Node

```bash
# Longhorn will automatically detect and use /var/lib/longhorn
# Verify in Longhorn UI or via kubectl
kubectl get nodes.longhorn.io -n longhorn-system
```

---

## Adding a Windows Node (via WSL2)

### Step 1: Enable WSL2 on Windows

```powershell
# Run in PowerShell as Administrator

# Enable WSL
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

# Enable Virtual Machine Platform
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Restart computer
Restart-Computer

# After restart, set WSL2 as default
wsl --set-default-version 2

# Install Ubuntu
wsl --install -d Ubuntu-22.04

# Set up Ubuntu user when prompted
```

### Step 2: Configure WSL2 Resources

Create `C:\Users\<YourUsername>\.wslconfig`:

```ini
[wsl2]
memory=8GB
processors=4
localhostForwarding=true
swap=0

[experimental]
sparseVhd=true
```

### Step 3: Prepare Physical Disk for WSL

```powershell
# In PowerShell as Administrator

# List available disks
wmic diskdrive list brief

# Note the disk number for your storage drive (e.g., \\.\PHYSICALDRIVE1)

# Create mount script: C:\Users\<YourUsername>\mount-wsl-storage.ps1
@'
# Mount physical drive to WSL
wsl --mount \\.\PHYSICALDRIVE1 --bare

# Mount in Ubuntu
wsl -d Ubuntu-22.04 -u root -e sh -c "mkdir -p /var/lib/longhorn && mount /dev/sdc1 /var/lib/longhorn"
'@ | Out-File -FilePath "$env:USERPROFILE\mount-wsl-storage.ps1"

# Run the script
& "$env:USERPROFILE\mount-wsl-storage.ps1"
```

### Step 4: Inside WSL2 Ubuntu

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Configure /etc/wsl.conf for auto-mounting
sudo tee /etc/wsl.conf <<EOF
[boot]
systemd=true
command = mount /dev/sdc1 /var/lib/longhorn 2>/dev/null || true

[automount]
enabled = true
mountFsTab = true
EOF

# Configure storage drive
sudo mkdir -p /var/lib/longhorn

# If drive needs formatting (be careful - this erases data!)
sudo mkfs.ext4 /dev/sdc1

# Mount the drive
sudo mount /dev/sdc1 /var/lib/longhorn

# Get join information from master
MASTER_IP=<your-master-ip>
NODE_TOKEN=<your-node-token>

# Install K3s
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -

# Verify
sudo k3s kubectl get nodes
```

### Step 5: Configure Windows Firewall

```powershell
# In PowerShell as Administrator

# Allow K3s ports through Windows Firewall
New-NetFirewallRule -DisplayName "K3s API" -Direction Inbound -Protocol TCP -LocalPort 6443 -Action Allow
New-NetFirewallRule -DisplayName "K3s Kubelet" -Direction Inbound -Protocol TCP -LocalPort 10250 -Action Allow
New-NetFirewallRule -DisplayName "K3s Flannel" -Direction Inbound -Protocol UDP -LocalPort 8472 -Action Allow
New-NetFirewallRule -DisplayName "Longhorn" -Direction Inbound -Protocol TCP -LocalPort 9500-9600 -Action Allow
```

### Step 6: Auto-start WSL2 on Windows Boot

Create scheduled task to start WSL2 and mount drives:

```powershell
# Create startup script: C:\Users\<YourUsername>\start-k3s-node.ps1
@'
# Start WSL2 and mount drives
wsl --mount \\.\PHYSICALDRIVE1 --bare
wsl -d Ubuntu-22.04 -u root -e sh -c "mount /dev/sdc1 /var/lib/longhorn && service k3s-agent start"
'@ | Out-File -FilePath "$env:USERPROFILE\start-k3s-node.ps1"

# Create scheduled task
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File $env:USERPROFILE\start-k3s-node.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERNAME" -RunLevel Highest
Register-ScheduledTask -TaskName "Start K3s Node" -Action $action -Trigger $trigger -Principal $principal
```

---

## Adding New Drives to Existing Nodes

### Method 1: Add Drive as Additional Longhorn Storage

```bash
# On the node with new drive

# 1. Prepare the new drive (assuming /dev/sdc)
sudo fdisk /dev/sdc  # Create partition
sudo mkfs.ext4 /dev/sdc1

# 2. Create mount point
sudo mkdir -p /var/lib/longhorn-disk2

# 3. Mount permanently
UUID=$(sudo blkid -s UUID -o value /dev/sdc1)
echo "UUID=$UUID /var/lib/longhorn-disk2 ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo mount -a

# 4. Add disk to Longhorn via UI or kubectl
cat <<EOF | kubectl apply -f -
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: $(hostname)
  namespace: longhorn-system
spec:
  disks:
    disk-2:
      path: /var/lib/longhorn-disk2
      allowScheduling: true
      evictionRequested: false
      storageReserved: 10737418240  # 10GB reserved
EOF
```

### Method 2: Expand Existing Storage with LVM

```bash
# Add new physical disk to LVM volume group

# 1. Create physical volume
sudo pvcreate /dev/sdc1

# 2. Extend volume group
sudo vgextend vg-longhorn /dev/sdc1

# 3. Extend logical volume
sudo lvextend -l +100%FREE /dev/vg-longhorn/lv-storage

# 4. Resize filesystem
sudo resize2fs /dev/vg-longhorn/lv-storage

# 5. Verify
df -h /var/lib/longhorn
```

---

## Quick Reference Commands

### Check Cluster Status
```bash
# On any node with kubectl access
kubectl get nodes -o wide
kubectl get pods -n longhorn-system
kubectl get volumes.longhorn.io -n longhorn-system
```

### Remove a Node from Cluster
```bash
# On master node
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
kubectl delete node <node-name>

# On the node being removed
sudo /usr/local/bin/k3s-agent-uninstall.sh  # For worker nodes
# or
sudo /usr/local/bin/k3s-uninstall.sh  # For master node
```

### Longhorn Storage Commands
```bash
# Check storage availability
kubectl get nodes.longhorn.io -n longhorn-system -o wide

# Check volume replicas
kubectl get replicas.longhorn.io -n longhorn-system

# Force replica rebuild
kubectl annotate volumes.longhorn.io/<volume-name> -n longhorn-system longhorn.io/rebuild-replica="true"
```

### Troubleshooting Commands
```bash
# Check K3s service status
sudo systemctl status k3s        # Master
sudo systemctl status k3s-agent  # Worker

# View K3s logs
sudo journalctl -u k3s -f        # Master
sudo journalctl -u k3s-agent -f  # Worker

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=100

# Test network connectivity
curl -k https://<master-ip>:6443/healthz

# Check disk space
df -h /var/lib/longhorn
```

---

## Storage Best Practices

### Disk Configuration
- **Dedicated disk** for Longhorn storage (don't use OS disk)
- **ext4 or XFS** filesystem (ext4 recommended)
- **No RAID** needed (Longhorn handles replication)
- **SSD preferred** for performance, HDD acceptable for capacity

### Capacity Planning
- **Reserve 25%** of disk space for overhead
- **Monitor usage** regularly via Longhorn UI
- **Set up alerts** for >80% usage
- **Plan for growth** - easier to add nodes than expand disks

### Network Considerations
- **Gigabit Ethernet minimum** for storage replication
- **Low latency** between nodes (<5ms recommended)
- **Dedicated network** for storage traffic if possible

### Backup Strategy
- **Regular snapshots** via Longhorn
- **External backup** to S3/NFS for disaster recovery
- **Test restore procedures** regularly

---

## Automation Scripts

### Script: add-node.sh
```bash
#!/bin/bash
# Automated node addition script

set -e

# Configuration
MASTER_IP=${1:-"192.168.1.100"}
NODE_TOKEN=${2:-""}
STORAGE_DISK=${3:-"/dev/sdb"}

echo "=== K3s Node Addition Script ==="
echo "Master IP: $MASTER_IP"
echo "Storage Disk: $STORAGE_DISK"

# Install K3s
echo "Installing K3s..."
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -

# Prepare storage
echo "Preparing storage..."
sudo mkdir -p /var/lib/longhorn

# Format disk if not formatted
if ! sudo blkid ${STORAGE_DISK}1 > /dev/null 2>&1; then
    echo "Creating partition..."
    echo -e "n\np\n1\n\n\nw" | sudo fdisk ${STORAGE_DISK}
    sudo mkfs.ext4 ${STORAGE_DISK}1
fi

# Mount storage
UUID=$(sudo blkid -s UUID -o value ${STORAGE_DISK}1)
echo "UUID=$UUID /var/lib/longhorn ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo mount -a

echo "=== Node successfully added to cluster ==="
sudo k3s kubectl get nodes
```

### Script: prepare-wsl-node.ps1
```powershell
# PowerShell script to prepare WSL2 as K3s node

param(
    [Parameter(Mandatory=$true)]
    [string]$MasterIP,
    
    [Parameter(Mandatory=$true)]
    [string]$NodeToken,
    
    [string]$PhysicalDrive = "\\.\PHYSICALDRIVE1"
)

Write-Host "=== Preparing WSL2 as K3s Node ===" -ForegroundColor Green

# Mount physical drive
Write-Host "Mounting physical drive..." -ForegroundColor Yellow
wsl --mount $PhysicalDrive --bare

# Install K3s in WSL
Write-Host "Installing K3s in WSL..." -ForegroundColor Yellow
$installCmd = @"
curl -sfL https://get.k3s.io | K3S_URL=https://${MasterIP}:6443 K3S_TOKEN=${NodeToken} sh -
mkdir -p /var/lib/longhorn
mount /dev/sdc1 /var/lib/longhorn
"@

wsl -d Ubuntu-22.04 -u root bash -c $installCmd

Write-Host "=== WSL2 Node Ready ===" -ForegroundColor Green
wsl -d Ubuntu-22.04 -u root k3s kubectl get nodes
```

---

## Summary

This guide provides everything needed to:
1. **Add Linux nodes** - straightforward K3s installation
2. **Add Windows nodes** - using WSL2 as a compatibility layer
3. **Add storage** - either new drives to existing nodes or new nodes with storage
4. **Automate** the process with provided scripts

With Longhorn managing the storage layer, adding/removing nodes becomes simple - the storage layer automatically handles data distribution and replication across all available nodes.