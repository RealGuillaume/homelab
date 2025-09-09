# Longhorn Deep Dive: Complete Guide for Home Lab Kubernetes Storage

## Table of Contents
1. [What is Longhorn](#what-is-longhorn)
2. [How Longhorn Handles Failures](#how-longhorn-handles-failures)
3. [Advanced Features for Home Labs](#advanced-features-for-home-labs)
4. [Limitations and Workarounds](#limitations-and-workarounds)
5. [Performance Optimization](#performance-optimization)
6. [Backup and Disaster Recovery](#backup-and-disaster-recovery)
7. [Monitoring and Alerting](#monitoring-and-alerting)
8. [Real-World Scenarios](#real-world-scenarios)

---

## What is Longhorn

Longhorn is a **distributed block storage system** for Kubernetes that turns your cluster's local storage into a resilient, self-healing storage pool. Think of it as "RAID for Kubernetes" but much smarter.

### Key Concepts

```
Traditional Setup (Your Current Pain):
┌──────────────┐
│ Single Node  │ ← If this fails, ALL data lost
│ Local Path   │ ← Manual PVC management
│ No Replicas  │ ← No redundancy
└──────────────┘

Longhorn Setup (Your Future):
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Node 1     │────►│   Node 2     │────►│   Node 3     │
│ Replica 1    │     │ Replica 2    │     │ Replica 3    │
│ Auto-sync    │     │ Auto-sync    │     │ Auto-sync    │
└──────────────┘     └──────────────┘     └──────────────┘
       ▲                    ▲                    ▲
       └────────────────────┴────────────────────┘
              Automatic Replication & Healing
```

### How It Works

1. **Volume Creation**: When you create a PVC, Longhorn creates a volume with multiple replicas
2. **Data Distribution**: Each replica lives on a different node
3. **Synchronous Replication**: All writes go to all replicas simultaneously
4. **Read Optimization**: Reads come from the closest/fastest replica
5. **Automatic Recovery**: Failed replicas are rebuilt automatically

---

## How Longhorn Handles Failures

### Scenario 1: Node Failure (Complete Node Loss)

**What Happens:**
```yaml
# Before failure: 3 nodes, 3 replicas
Node1: [Replica-A1] [Replica-B2] [Replica-C3]
Node2: [Replica-A2] [Replica-B3] [Replica-C1]  ← This node fails
Node3: [Replica-A3] [Replica-B1] [Replica-C2]

# Immediately after failure (within seconds):
- Longhorn detects Node2 is down
- Marks all replicas on Node2 as failed
- Volumes remain available (still have 2 replicas each)
- Starts rebuilding missing replicas on surviving nodes

# After auto-healing (minutes):
Node1: [Replica-A1] [Replica-B2] [Replica-C3] [Replica-C1-rebuilt]
Node3: [Replica-A3] [Replica-B1] [Replica-C2] [Replica-A2-rebuilt] [Replica-B3-rebuilt]
```

**Your Applications:**
- **Zero downtime** - Pods continue running
- **Zero data loss** - Other replicas serve data
- **Automatic recovery** - No manual intervention needed

**Commands to Monitor:**
```bash
# Watch replica rebuilding
watch kubectl get replicas.longhorn.io -n longhorn-system

# Check volume health
kubectl get volumes.longhorn.io -n longhorn-system -o wide

# See rebuilding progress
kubectl describe volume <volume-name> -n longhorn-system
```

### Scenario 2: Drive Failure (Single Disk Loss)

**What Happens:**
```yaml
# Node with multiple disks, one fails
Node1:
  /var/lib/longhorn-ssd     ← Healthy (contains Replica-A1, B1)
  /var/lib/longhorn-hdd1    ← FAILED (contained Replica-C1, D1)
  /var/lib/longhorn-hdd2    ← Healthy (contains Replica-E1)

# Longhorn's response:
1. Marks disk as failed
2. Evicts all replicas from failed disk
3. Rebuilds replicas on other disks/nodes
4. Continues serving data from other replicas
```

**Recovery Process:**
```bash
# Remove failed disk from Longhorn
kubectl patch nodes.longhorn.io <node-name> -n longhorn-system --type='json' -p='[
  {"op": "remove", "path": "/spec/disks/failed-disk"}
]'

# After replacing physical disk, add it back
kubectl patch nodes.longhorn.io <node-name> -n longhorn-system --type='json' -p='[
  {"op": "add", "path": "/spec/disks/new-disk", "value": {
    "path": "/var/lib/longhorn-hdd1",
    "allowScheduling": true
  }}
]'
```

### Scenario 3: Network Partition (Split Brain Prevention)

**What Happens:**
```
Network Split:
[Node1] ←X→ [Node2, Node3]

Longhorn's Response:
- Minority partition (Node1): Volumes become read-only
- Majority partition (Node2+3): Volumes remain read-write
- Prevents data divergence (split-brain)
- Auto-recovers when network heals
```

### Scenario 4: Corrupted Replica

**What Happens:**
```bash
# Longhorn detects checksum mismatch
# Automatically:
1. Marks corrupted replica as failed
2. Serves data from healthy replicas
3. Rebuilds corrupted replica from healthy ones
4. Validates new replica before marking healthy

# Manual intervention if needed:
kubectl delete replica <replica-name> -n longhorn-system
# Longhorn auto-creates new replica
```

---

## Advanced Features for Home Labs

### 1. Snapshot and Cloning

**Instant Snapshots:**
```yaml
apiVersion: longhorn.io/v1beta1
kind: Snapshot
metadata:
  name: plex-config-snapshot-20240108
  namespace: longhorn-system
spec:
  volume: plex-config
  labels:
    backup: "daily"
    app: "plex"
```

**Use Cases:**
- Before upgrades: Snapshot → Upgrade → Rollback if needed
- Testing: Clone production data for test environment
- Fast provisioning: Clone template volumes

**Space Efficiency:**
- Copy-on-Write (CoW) - Snapshots only store changes
- 100GB volume with 1GB changes = 1GB snapshot size

### 2. Backup to S3/NFS

**Configure Backup Target:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: s3-backup-secret
  namespace: longhorn-system
data:
  AWS_ACCESS_KEY_ID: <base64-encoded>
  AWS_SECRET_ACCESS_KEY: <base64-encoded>
---
# In Longhorn settings:
backup-target: s3://longhorn-backups@us-east-1/
backup-target-credential-secret: s3-backup-secret
```

**Automated Backup Policy:**
```yaml
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: daily-backup
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"  # 2 AM daily
  task: "backup"
  groups:
    - "critical"
  retain: 7  # Keep 7 backups
```

### 3. Volume Encryption

**At-Rest Encryption:**
```yaml
apiVersion: v1
kind: StorageClass
metadata:
  name: longhorn-encrypted
provisioner: driver.longhorn.io
parameters:
  encrypted: "true"
  # Uses LUKS encryption
  # Keys stored in Kubernetes secrets
```

**Use Cases:**
- Nextcloud data (personal files)
- Home Assistant configs (contains secrets)
- Database volumes (sensitive data)

### 4. Data Locality

**Pin Data to Specific Nodes:**
```yaml
apiVersion: longhorn.io/v1beta1
kind: Volume
metadata:
  name: plex-media
spec:
  dataLocality: "strict-local"  # Keep primary replica on same node as pod
  nodeSelector:
    - "media-node"  # Pin to specific node
```

**Benefits for Home Lab:**
- Plex transcoding: Keep media on same node as Plex
- Databases: Reduce network latency
- Large files: Minimize network traffic

### 5. Recurring Jobs

**Automated Maintenance:**
```yaml
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: maintenance-tasks
spec:
  cron: "0 3 * * 0"  # Sunday 3 AM
  task: "snapshot-cleanup"  # Clean old snapshots
  retain: 5
---
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: filesystem-trim
spec:
  cron: "0 4 * * 0"  # Sunday 4 AM
  task: "filesystem-trim"  # Reclaim space
```

### 6. Priority Classes

**Critical vs Non-Critical Data:**
```yaml
# High priority for critical services
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-critical
parameters:
  replicaCount: "3"
  replicaAutoBalance: "least-effort"
  diskSelector: "ssd"
  priority: "high"
---
# Lower priority for replaceable data
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-bulk
parameters:
  replicaCount: "2"
  diskSelector: "hdd"
  priority: "low"
```

### 7. Space Reclamation

**Automatic TRIM/UNMAP:**
```bash
# Enable for SSDs
kubectl patch storageclass longhorn -p \
  '{"parameters":{"unmapMarkSnapChainRemoved":"true"}}'

# Manual space reclamation
kubectl annotate volume <volume-name> \
  longhorn.io/requested-data-engine-filesystem-trim="true"
```

---

## Limitations and Workarounds

### Limitation 1: No Multi-Writer (RWX) by Default

**Problem:** Can't mount same volume on multiple nodes as read-write

**Workaround:** Use NFS provisioner on top of Longhorn
```yaml
# Deploy NFS provisioner using Longhorn as backing storage
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-provisioner
spec:
  template:
    spec:
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: nfs-backing-store  # Longhorn RWO volume
```

### Limitation 2: Performance Overhead

**Problem:** ~10-20% performance penalty vs local disk

**Workarounds:**
```yaml
# 1. Use data locality
dataLocality: "strict-local"

# 2. Use faster network (10Gbe if possible)

# 3. Dedicated network for storage traffic
# 4. Use NVMe/SSD for replicas

# 5. Tune replica count for non-critical data
numberOfReplicas: "2"  # Instead of 3
```

### Limitation 3: Minimum 3 Nodes for True HA

**Problem:** Need 3+ nodes for quorum

**Workaround for 2-Node Setup:**
```yaml
# Use 2 replicas with careful planning
numberOfReplicas: "2"
replicaAutoBalance: "disabled"  # Manually control placement

# Add tiebreaker node (can be small)
# Raspberry Pi or VM just for quorum
```

### Limitation 4: Memory Usage

**Problem:** Each volume uses ~30-50MB RAM

**Workarounds:**
```bash
# Consolidate small volumes
# Instead of 10x 1GB volumes, use 1x 10GB volume with subdirectories

# Tune engine settings
kubectl edit configmap longhorn-default-setting -n longhorn-system
# Reduce: guaranteed-engine-manager-cpu
# Reduce: guaranteed-replica-manager-cpu
```

---

## Performance Optimization

### For Your Media Server (Plex/Jellyfin)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: plex-media-optimized
spec:
  storageClassName: longhorn-media
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 500Gi
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-media
parameters:
  numberOfReplicas: "2"  # Media can be re-downloaded
  dataLocality: "strict-local"  # Keep on same node as Plex
  diskSelector: "hdd"  # HDDs fine for sequential reads
  staleReplicaTimeout: "2880"  # 48 hours (media is static)
```

### For Databases (PostgreSQL/MySQL)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-database
parameters:
  numberOfReplicas: "3"  # Maximum redundancy
  dataLocality: "best-effort"  # Balance performance and availability
  diskSelector: "ssd,nvme"  # Fast disks only
  fsType: "xfs"  # Better for databases than ext4
  recurringJobSelector: '[{"name":"backup-database","isGroup":false}]'
```

### For Nextcloud/Immich

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-cloud-storage
parameters:
  numberOfReplicas: "3"  # Important personal data
  dataLocality: "disabled"  # Availability over performance
  diskSelector: "ssd,hdd"  # Mixed is fine
  encrypted: "true"  # Encryption for personal files
  recurringJobSelector: '[{"name":"backup-to-s3","isGroup":false}]'
```

---

## Backup and Disaster Recovery

### 3-2-1 Backup Strategy with Longhorn

```
3 Copies: Original + 2 Longhorn replicas
2 Different Media: Different nodes/disks
1 Offsite: S3 or NFS backup

Implementation:
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│   Node 1     │     │   Node 2     │     │   Node 3     │
│  Primary     │────►│  Replica 1   │────►│  Replica 2   │
└──────────────┘     └──────────────┘     └──────────────┘
                              │
                              ▼
                     ┌──────────────┐
                     │   S3/NFS     │
                     │   Backup     │
                     └──────────────┘
```

### Disaster Recovery Plan

```bash
#!/bin/bash
# disaster-recovery.sh

# 1. Complete cluster failure - Restore from S3
longhorn backup restore \
  --backup-url s3://backups/volume-backup-latest \
  --pvc-name recovered-volume

# 2. Corrupted volume - Restore from snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: recovered-from-snapshot
spec:
  dataSource:
    name: snapshot-20240108
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  storageClassName: longhorn
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
EOF

# 3. Accidental deletion - Restore from backup
kubectl create -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Volume
metadata:
  name: restore-from-backup
spec:
  fromBackup: "s3://backup-target?backup=backup-xyz&volume=original-volume"
EOF
```

---

## Monitoring and Alerting

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Longhorn Storage Health",
    "panels": [
      {
        "title": "Volume Health",
        "targets": [{
          "expr": "longhorn_volume_robustness"
        }]
      },
      {
        "title": "Space Usage",
        "targets": [{
          "expr": "longhorn_node_storage_usage_bytes / longhorn_node_storage_capacity_bytes"
        }]
      },
      {
        "title": "Replica Status",
        "targets": [{
          "expr": "longhorn_volume_replica_count"
        }]
      }
    ]
  }
}
```

### AlertManager Rules

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: longhorn-alerts
data:
  alerts.yaml: |
    groups:
    - name: longhorn
      rules:
      - alert: VolumeSpaceLow
        expr: longhorn_volume_usage_bytes / longhorn_volume_capacity_bytes > 0.9
        annotations:
          summary: "Volume {{ $labels.volume }} is 90% full"
      
      - alert: NodeStorageLow
        expr: longhorn_node_storage_usage_bytes / longhorn_node_storage_capacity_bytes > 0.85
        annotations:
          summary: "Node {{ $labels.node }} storage is 85% full"
      
      - alert: VolumeDegraded
        expr: longhorn_volume_robustness == 2  # degraded
        annotations:
          summary: "Volume {{ $labels.volume }} is degraded"
      
      - alert: ReplicaCountLow
        expr: longhorn_volume_replica_count < 2
        annotations:
          summary: "Volume {{ $labels.volume }} has less than 2 replicas"
```

---

## Real-World Scenarios

### Scenario: "Unplugging a Node for Maintenance"

```bash
# 1. Cordon the node (prevent new pods)
kubectl cordon node2

# 2. Drain workloads
kubectl drain node2 --ignore-daemonsets --delete-emptydir-data

# 3. Disable Longhorn scheduling
kubectl patch nodes.longhorn.io node2 -n longhorn-system \
  --type='merge' -p '{"spec":{"allowScheduling":false}}'

# 4. Wait for replica migration
watch kubectl get replicas.longhorn.io -n longhorn-system \
  --field-selector spec.nodeID=node2

# 5. Safe to power off
sudo shutdown -h now

# After maintenance, reverse:
kubectl uncordon node2
kubectl patch nodes.longhorn.io node2 -n longhorn-system \
  --type='merge' -p '{"spec":{"allowScheduling":true}}'
```

### Scenario: "Growing Storage Gradually"

```bash
# Month 1: Start with what you have
Node1: 500GB SSD
→ Install Longhorn, numberOfReplicas: "1"

# Month 2: Add redundancy
Node2: 1TB HDD (old computer)
→ Join cluster, increase replicas to 2

# Month 3: True HA
Node3: 500GB SSD (another old PC)
→ Join cluster, increase replicas to 3

# Month 4: Expand capacity
Node2: Add 2TB HDD
→ Add as second disk to Longhorn

# Result: 4TB usable (with 3x replication = 1.3TB effective)
```

### Scenario: "Migrating from Current Setup"

```bash
# Your current local-path PVCs:
# 298GB across ~20 PVCs

# Migration approach:
# 1. Install Longhorn alongside local-path
# 2. Migrate one namespace at a time:

for pvc in $(kubectl get pvc -n media -o name); do
  # Create Longhorn PVC
  # Copy data using job
  # Switch deployment to new PVC
  # Delete old PVC
done

# 3. Start with less critical (media) 
# 4. Move to critical (nextcloud, databases)
# 5. Finally remove local-path
```

---

## Cost-Benefit Analysis for Your Setup

### Current Pain Points Solved

| Your Current Pain | Longhorn Solution |
|-------------------|-------------------|
| Manual PVC ID mapping | Automatic PVC management |
| Single point of failure | Multi-node redundancy |
| Manual backup process | Automated S3/NFS backups |
| Storage expansion difficulty | Just add nodes/disks |
| No disaster recovery | Snapshots + backups + replicas |
| Permission nightmares | Consistent CSI permissions |

### Resource Investment

```
Minimum Viable Setup:
- 3 nodes (can be old PCs/laptops)
- 500GB+ storage per node
- 4GB+ RAM per node
- Gigabit network

Your 298GB data with 2x replication = 596GB needed
With 3x replication = 894GB needed
With growth room = 1.5TB recommended across cluster
```

### ROI Timeline

```
Week 1: Setup overhead (learning curve)
Week 2: Migration effort
Week 3: Stable operation
Week 4+: Time saved on:
  - No manual PVC management
  - No backup scripting
  - No data loss recovery
  - No permission fixes
  
Break-even: ~1 month
Long-term: Hours saved per week
```

---

## Summary

Longhorn transforms your fragile single-node storage into an enterprise-grade distributed storage system that:

1. **Survives failures** - Node, disk, network, or replica corruption
2. **Self-heals** - Automatic replica rebuilding and rebalancing
3. **Scales effortlessly** - Just add nodes or disks
4. **Protects data** - Snapshots, backups, encryption
5. **Optimizes performance** - Data locality, disk selection, caching
6. **Simplifies operations** - No more manual PVC directory management

For your home lab with media servers, personal cloud storage, and home automation, Longhorn provides the storage resilience of enterprise solutions at zero licensing cost, turning your collection of old computers into a robust storage cluster.