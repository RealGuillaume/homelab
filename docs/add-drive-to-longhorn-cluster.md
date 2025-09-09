# Complete Guide: Adding Drives to Longhorn Cluster

## Table of Contents
1. [Quick Start](#quick-start)
2. [Why Multiple Disks Instead of LVM](#why-multiple-disks-instead-of-lvm)
3. [Adding a New Drive to Existing Node](#adding-a-new-drive-to-existing-node)
4. [Drive Preparation Checklist](#drive-preparation-checklist)
5. [Advanced Disk Configuration](#advanced-disk-configuration)
6. [Disk Management Operations](#disk-management-operations)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Quick Start

**To add a new drive to any node in your Longhorn cluster:**

```bash
# 1. Identify the new drive
lsblk

# 2. Prepare and mount (assuming /dev/sdb)
sudo fdisk /dev/sdb  # Create partition (n, p, 1, Enter, Enter, w)
sudo mkfs.ext4 /dev/sdb1
sudo mkdir -p /var/lib/longhorn-disk2
UUID=$(sudo blkid -s UUID -o value /dev/sdb1)
echo "UUID=$UUID /var/lib/longhorn-disk2 ext4 defaults 0 2" | sudo tee -a /etc/fstab
sudo mount -a

# 3. Add to Longhorn
kubectl apply -f - <<EOF
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
EOF
```

---

## Why Multiple Disks Instead of LVM

### ✅ **RECOMMENDED: Multiple Disks Approach**

Longhorn is designed to manage multiple disks per node independently. This is the preferred approach.

#### Advantages:
1. **Failure Isolation** - One disk failure doesn't affect others
2. **Performance Optimization** - Can mix SSD/HDD with different policies
3. **Flexible Management** - Add/remove/drain disks independently
4. **Better Monitoring** - See exactly which disk has issues
5. **Native Longhorn Features** - Disk tags, scheduling policies, per-disk limits
6. **Simpler Troubleshooting** - Direct disk access without LVM layer

#### When It Makes Sense:
- Most home lab and production Kubernetes clusters
- When you want maximum flexibility
- When mixing different disk types (NVMe, SSD, HDD)
- When you need to frequently add/remove storage

### ❌ **NOT RECOMMENDED: LVM Approach**

Using LVM to combine disks adds unnecessary complexity for Longhorn.

#### Disadvantages:
1. **Single Point of Failure** - VG corruption affects all disks
2. **No Disk-Level Management** - Can't set policies per physical disk
3. **Performance Overhead** - Additional abstraction layer
4. **Complex Recovery** - Harder to recover from failures
5. **Lost Features** - Can't use Longhorn's disk tagging system

#### Only Consider LVM If:
- Corporate policy mandates LVM usage
- You need LVM-specific features unrelated to Longhorn
- Existing infrastructure heavily depends on LVM

---

## Adding a New Drive to Existing Node

### Step 1: Identify the New Drive

```bash
# List all block devices
lsblk -f

# Show disk details
sudo fdisk -l

# Check current Longhorn disks
kubectl get nodes.longhorn.io -n longhorn-system -o wide
```

### Step 2: Prepare the Drive

```bash
#!/bin/bash
# Script: prepare-longhorn-disk.sh

DISK_DEVICE=${1:-/dev/sdb}
MOUNT_PATH=${2:-/var/lib/longhorn-disk2}
DISK_NAME=${3:-disk2}

echo "=== Preparing disk $DISK_DEVICE for Longhorn ==="

# Create partition table
echo "Creating partition..."
sudo parted $DISK_DEVICE mklabel gpt
sudo parted $DISK_DEVICE mkpart primary ext4 0% 100%

# Format the partition
echo "Formatting ${DISK_DEVICE}1..."
sudo mkfs.ext4 -L "longhorn-$DISK_NAME" ${DISK_DEVICE}1

# Create mount point
echo "Creating mount point at $MOUNT_PATH..."
sudo mkdir -p $MOUNT_PATH

# Get UUID and add to fstab
UUID=$(sudo blkid -s UUID -o value ${DISK_DEVICE}1)
echo "Adding to /etc/fstab (UUID=$UUID)..."
echo "UUID=$UUID $MOUNT_PATH ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# Mount the drive
echo "Mounting..."
sudo mount -a

# Set permissions
sudo chmod 755 $MOUNT_PATH

# Verify
df -h $MOUNT_PATH
echo "=== Disk prepared successfully ==="
```

### Step 3: Add Disk to Longhorn

```bash
# Method 1: Using kubectl patch (for existing node)
kubectl patch nodes.longhorn.io $(hostname) -n longhorn-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/disks/disk-'$(date +%s)'",
    "value": {
      "path": "/var/lib/longhorn-disk2",
      "allowScheduling": true,
      "storageReserved": 10737418240,
      "tags": ["general"]
    }
  }
]'

# Method 2: Full node configuration
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: $(hostname)
  namespace: longhorn-system
spec:
  disks:
    default-disk:
      path: /var/lib/longhorn
      allowScheduling: true
      storageReserved: 10737418240  # 10GB reserved
      tags: ["default"]
    disk-2:
      path: /var/lib/longhorn-disk2
      allowScheduling: true
      storageReserved: 10737418240  # 10GB reserved
      tags: ["general"]
EOF
```

---

## Drive Preparation Checklist

### Pre-Installation
- [ ] Drive detected by system (`lsblk`)
- [ ] No existing data on drive (or backed up)
- [ ] Sufficient capacity (minimum 50GB recommended)
- [ ] Drive health checked (`sudo smartctl -a /dev/sdX`)

### Installation
- [ ] Partition created (GPT recommended)
- [ ] Filesystem formatted (ext4 recommended)
- [ ] Mount point created under `/var/lib/`
- [ ] Entry added to `/etc/fstab`
- [ ] Drive mounted successfully
- [ ] Permissions set correctly (755)

### Post-Installation
- [ ] Disk appears in Longhorn UI
- [ ] Disk shows as "Schedulable"
- [ ] Storage reserved configured
- [ ] Tags applied if needed
- [ ] Test volume created successfully

---

## Advanced Disk Configuration

### Disk Types and Tagging

```yaml
# Example: Multi-tier storage setup
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: worker-node-1
  namespace: longhorn-system
spec:
  disks:
    nvme-critical:
      path: /var/lib/longhorn-nvme
      allowScheduling: true
      storageReserved: 10Gi  # 10GB reserved for system
      tags: 
        - "nvme"
        - "critical"
        - "fast"
      
    ssd-general:
      path: /var/lib/longhorn-ssd
      allowScheduling: true
      storageReserved: 20Gi  # 20GB reserved
      tags:
        - "ssd"
        - "general"
        - "fast"
    
    hdd-bulk:
      path: /var/lib/longhorn-hdd
      allowScheduling: true
      storageReserved: 50Gi  # 50GB reserved
      tags:
        - "hdd"
        - "bulk"
        - "slow"
        - "archive"
    
    hdd-backup:
      path: /var/lib/longhorn-backup
      allowScheduling: false  # Used only for backups
      storageReserved: 100Gi
      tags:
        - "backup"
        - "no-schedule"
```

### Creating StorageClasses for Different Disk Types

```yaml
# StorageClass for fast NVMe storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-nvme
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "2"
  diskSelector: "nvme"
  nodeSelector: ""
  dataLocality: "best-effort"
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
---
# StorageClass for bulk HDD storage
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-bulk
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"
  diskSelector: "bulk,hdd"
  nodeSelector: ""
  dataLocality: "disabled"  # Not important for bulk storage
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
```

---

## Disk Management Operations

### Monitor Disk Usage

```bash
# Check all Longhorn disks
kubectl get nodes.longhorn.io -n longhorn-system -o yaml | grep -A 10 "disks:"

# Monitor disk usage
watch -n 5 'kubectl get nodes.longhorn.io -n longhorn-system -o custom-columns=\
NODE:.metadata.name,\
DISK:.spec.disks.*.path,\
AVAILABLE:.status.diskStatus.*.storageAvailable,\
TOTAL:.status.diskStatus.*.storageMaximum'

# Check disk health
for node in $(kubectl get nodes -o name | cut -d/ -f2); do
  echo "=== Node: $node ==="
  kubectl exec -n longhorn-system ds/longhorn-manager -- df -h | grep longhorn
done
```

### Drain a Disk Before Removal

```bash
#!/bin/bash
# Script: drain-longhorn-disk.sh

NODE_NAME=${1:-$(hostname)}
DISK_PATH=${2:-/var/lib/longhorn-disk2}

echo "Draining disk $DISK_PATH on node $NODE_NAME"

# 1. Disable scheduling on the disk
kubectl patch nodes.longhorn.io $NODE_NAME -n longhorn-system --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/disks/'$(echo $DISK_PATH | sed 's/\//-/g')'/allowScheduling",
    "value": false
  }
]'

# 2. Evict replicas from the disk
kubectl patch nodes.longhorn.io $NODE_NAME -n longhorn-system --type='json' -p='[
  {
    "op": "replace",
    "path": "/spec/disks/'$(echo $DISK_PATH | sed 's/\//-/g')'/evictionRequested",
    "value": true
  }
]'

# 3. Wait for replicas to move
echo "Waiting for replicas to evacuate..."
while kubectl get replicas.longhorn.io -n longhorn-system -o json | \
      jq -r '.items[].spec.nodeID' | grep -q $NODE_NAME; do
  echo "Replicas still present on $NODE_NAME, waiting..."
  sleep 10
done

echo "Disk drained successfully"
```

### Replace a Failed Disk

```bash
#!/bin/bash
# Script: replace-failed-disk.sh

OLD_DISK="/dev/sdb"
NEW_DISK="/dev/sdc"
MOUNT_PATH="/var/lib/longhorn-disk2"

echo "=== Replacing failed disk ==="

# 1. Remove old disk from Longhorn
kubectl patch nodes.longhorn.io $(hostname) -n longhorn-system --type='json' -p='[
  {
    "op": "remove",
    "path": "/spec/disks/disk-2"
  }
]'

# 2. Unmount old disk
sudo umount $MOUNT_PATH

# 3. Remove old fstab entry
sudo sed -i "\|$MOUNT_PATH|d" /etc/fstab

# 4. Prepare new disk
sudo parted $NEW_DISK mklabel gpt
sudo parted $NEW_DISK mkpart primary ext4 0% 100%
sudo mkfs.ext4 ${NEW_DISK}1

# 5. Mount new disk
UUID=$(sudo blkid -s UUID -o value ${NEW_DISK}1)
echo "UUID=$UUID $MOUNT_PATH ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
sudo mount -a

# 6. Add new disk to Longhorn
kubectl patch nodes.longhorn.io $(hostname) -n longhorn-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/disks/disk-2-new",
    "value": {
      "path": "'$MOUNT_PATH'",
      "allowScheduling": true,
      "storageReserved": 10737418240
    }
  }
]'

echo "=== Disk replaced successfully ==="
```

---

## Troubleshooting

### Common Issues and Solutions

#### Disk Not Showing in Longhorn

```bash
# Check if disk is mounted
mount | grep longhorn

# Check Longhorn manager logs
kubectl logs -n longhorn-system -l app=longhorn-manager --tail=50 | grep -i disk

# Verify disk permissions
ls -la /var/lib/longhorn*

# Restart Longhorn manager on node
kubectl delete pod -n longhorn-system -l app=longhorn-manager --field-selector spec.nodeName=$(hostname)
```

#### Disk Shows as Unschedulable

```bash
# Check disk status
kubectl describe nodes.longhorn.io $(hostname) -n longhorn-system

# Common fixes:
# 1. Ensure sufficient free space
df -h /var/lib/longhorn*

# 2. Check disk is not marked for eviction
kubectl get nodes.longhorn.io $(hostname) -n longhorn-system -o yaml | grep eviction

# 3. Verify disk conditions
kubectl get nodes.longhorn.io $(hostname) -n longhorn-system -o yaml | grep -A 20 conditions
```

#### Performance Issues

```bash
# Test disk performance
sudo dd if=/dev/zero of=/var/lib/longhorn-disk2/test bs=1G count=1 oflag=direct

# Check disk I/O stats
iostat -x 1 10

# Monitor Longhorn metrics
kubectl top pods -n longhorn-system
```

---

## Best Practices

### Capacity Planning

1. **Reserve Space**: Always reserve 10-20% for system overhead
2. **Growth Planning**: Add new disks before reaching 80% capacity
3. **Replica Consideration**: Account for replica storage (2-3x data size)

### Disk Selection

| Use Case | Disk Type | Mount Path | Tags |
|----------|-----------|------------|------|
| Critical databases | NVMe SSD | `/var/lib/longhorn-nvme` | `["nvme", "critical", "database"]` |
| General workloads | SATA SSD | `/var/lib/longhorn-ssd` | `["ssd", "general"]` |
| Media/Backups | HDD | `/var/lib/longhorn-hdd` | `["hdd", "bulk", "media"]` |
| Archive | HDD | `/var/lib/longhorn-archive` | `["hdd", "archive", "cold"]` |

### Naming Conventions

```bash
# Consistent mount paths
/var/lib/longhorn         # Default disk
/var/lib/longhorn-nvme    # NVMe disk
/var/lib/longhorn-ssd1    # First SSD
/var/lib/longhorn-ssd2    # Second SSD
/var/lib/longhorn-hdd1    # First HDD
/var/lib/longhorn-hdd2    # Second HDD

# Disk names in Longhorn
default-disk
nvme-primary
ssd-general-1
ssd-general-2
hdd-bulk-1
hdd-archive-1
```

### Monitoring Setup

```yaml
# Prometheus ServiceMonitor for Longhorn
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: longhorn-disk-metrics
  namespace: longhorn-system
spec:
  selector:
    matchLabels:
      app: longhorn-manager
  endpoints:
  - port: manager
    interval: 30s
    path: /metrics
```

### Backup Strategy

1. **Snapshot Schedule**: Daily snapshots, retain 7 days
2. **Backup Target**: Configure S3 or NFS backup target
3. **Test Restores**: Monthly restore tests
4. **Disk Redundancy**: Minimum 2 replicas, 3 for critical data

---

## Automation Scripts

### Complete Disk Addition Script

```bash
#!/bin/bash
# Script: add-disk-to-longhorn.sh
# Usage: ./add-disk-to-longhorn.sh /dev/sdb ssd general

set -e

DISK_DEVICE=${1:-/dev/sdb}
DISK_TYPE=${2:-hdd}  # nvme, ssd, or hdd
DISK_PURPOSE=${3:-general}  # general, bulk, archive, critical

# Generate unique disk name
DISK_NAME="${DISK_TYPE}-${DISK_PURPOSE}-$(date +%s)"
MOUNT_PATH="/var/lib/longhorn-${DISK_NAME}"

echo "=== Adding disk $DISK_DEVICE as $DISK_NAME ==="

# 1. Verify disk exists and is not in use
if ! lsblk $DISK_DEVICE > /dev/null 2>&1; then
    echo "Error: Disk $DISK_DEVICE not found"
    exit 1
fi

if mount | grep -q $DISK_DEVICE; then
    echo "Error: Disk $DISK_DEVICE is already mounted"
    exit 1
fi

# 2. Create partition
echo "Creating partition..."
sudo parted -s $DISK_DEVICE mklabel gpt
sudo parted -s $DISK_DEVICE mkpart primary ext4 0% 100%
sleep 2

# 3. Format partition
echo "Formatting ${DISK_DEVICE}1..."
sudo mkfs.ext4 -F -L "longhorn-$DISK_NAME" ${DISK_DEVICE}1

# 4. Create mount point and mount
echo "Mounting to $MOUNT_PATH..."
sudo mkdir -p $MOUNT_PATH
UUID=$(sudo blkid -s UUID -o value ${DISK_DEVICE}1)
echo "UUID=$UUID $MOUNT_PATH ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
sudo mount -a

# 5. Set permissions
sudo chmod 755 $MOUNT_PATH

# 6. Calculate storage reservation (10% of total)
TOTAL_SIZE=$(df -B1 $MOUNT_PATH | tail -1 | awk '{print $2}')
RESERVED_SIZE=$((TOTAL_SIZE / 10))

# 7. Add to Longhorn
echo "Adding to Longhorn..."
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Node
metadata:
  name: $(hostname)
  namespace: longhorn-system
spec:
  disks:
    ${DISK_NAME}:
      path: ${MOUNT_PATH}
      allowScheduling: true
      storageReserved: ${RESERVED_SIZE}
      tags:
        - "${DISK_TYPE}"
        - "${DISK_PURPOSE}"
EOF

# 8. Verify
echo "=== Verification ==="
df -h $MOUNT_PATH
kubectl get nodes.longhorn.io $(hostname) -n longhorn-system -o yaml | grep -A 5 "$DISK_NAME"

echo "=== Disk $DISK_NAME added successfully ==="
echo "Mount path: $MOUNT_PATH"
echo "Disk type: $DISK_TYPE"
echo "Purpose: $DISK_PURPOSE"
echo "Reserved: $((RESERVED_SIZE / 1073741824))GB"
```

### Health Check Script

```bash
#!/bin/bash
# Script: check-longhorn-disks.sh
# Regular health check for all Longhorn disks

echo "=== Longhorn Disk Health Check ==="
echo "Time: $(date)"
echo ""

# Check all nodes
for node in $(kubectl get nodes -o name | cut -d/ -f2); do
    echo "Node: $node"
    echo "-------------------"
    
    # Get disk info
    kubectl get nodes.longhorn.io $node -n longhorn-system -o json | \
    jq -r '.spec.disks | to_entries[] | "Disk: \(.key)\nPath: \(.value.path)\nScheduling: \(.value.allowScheduling)\nTags: \(.value.tags | join(", "))\n"'
    
    # Check disk usage
    kubectl exec -n longhorn-system ds/longhorn-manager -- df -h 2>/dev/null | grep longhorn || true
    
    echo ""
done

# Check for any issues
echo "=== Checking for Issues ==="
kubectl get replicas.longhorn.io -n longhorn-system -o json | \
jq -r '.items[] | select(.status.robustness != "healthy") | "Unhealthy replica: \(.metadata.name) on node \(.spec.nodeID)"'

echo "=== Check Complete ==="
```

---

## Summary

This guide provides everything needed to add and manage drives in your Longhorn cluster:

1. **Always use multiple disks** instead of LVM for better management
2. **Follow the naming conventions** for consistency
3. **Tag disks appropriately** for workload placement
4. **Monitor disk health** regularly
5. **Plan capacity** with replica overhead in mind
6. **Automate common tasks** with the provided scripts

With this approach, adding a new drive anywhere in your cluster becomes a simple, predictable operation that Longhorn handles gracefully.