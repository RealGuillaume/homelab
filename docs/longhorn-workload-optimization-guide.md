# Longhorn Workload-Specific Optimization Guide

## Table of Contents
1. [Workload Categories and Requirements](#workload-categories-and-requirements)
2. [Storage Classes for Different Workloads](#storage-classes-for-different-workloads)
3. [Disk Tagging and Selection Strategy](#disk-tagging-and-selection-strategy)
4. [Application-Specific Configurations](#application-specific-configurations)
5. [Automated Storage Assignment](#automated-storage-assignment)
6. [Migration and Optimization Scripts](#migration-and-optimization-scripts)

---

## Workload Categories and Requirements

### Understanding Different Data Types

| Workload Type | Example Apps | Characteristics | Storage Needs | Replica Strategy |
|--------------|--------------|-----------------|---------------|------------------|
| **Critical Configs** | Home Assistant, Grocy | Small, frequently updated, irreplaceable | Fast SSD, High durability | 3 replicas, encrypted |
| **Databases** | PostgreSQL, MySQL, Redis | Random I/O, consistency critical | NVMe/SSD only | 3 replicas, frequent backups |
| **Media Libraries** | Plex, Jellyfin media | Large, sequential reads, replaceable | HDD acceptable, capacity focused | 1-2 replicas |
| **Active Downloads** | qBittorrent, SABnzbd | High write, temporary | Fast disk, local to downloader | 1 replica, no backup |
| **Personal Files** | Nextcloud, Immich photos | Irreplaceable user data | Any disk, high durability | 3 replicas, encrypted, backed up |
| **Application Code** | Container images, configs | Small, read-heavy | SSD preferred | 2-3 replicas |
| **Logs/Metrics** | Prometheus, Loki | Write-heavy, time-series | Fast disk, can be pruned | 2 replicas, short retention |
| **Backup Staging** | Restic, Duplicati | Temporary, large | HDD fine, capacity focused | 1 replica |

---

## Storage Classes for Different Workloads

### 1. Critical Configuration Storage (Home Assistant)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-critical-config
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    description: "For Home Assistant, authentication, and critical configs"
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"                    # Maximum redundancy
  staleReplicaTimeout: "30"                # Quick failover (30 minutes)
  fromBackup: ""
  fsType: "ext4"
  diskSelector: "ssd,nvme"                 # Fast disks only
  nodeSelector: ""
  recurringJobSelector: |
    [
      {
        "name": "backup-critical-daily",
        "isGroup": false
      },
      {
        "name": "snapshot-hourly",
        "isGroup": false
      }
    ]
  dataLocality: "best-effort"              # Balance between speed and availability
  replicaAutoBalance: "least-effort"       # Stable placement
  encrypted: "true"                        # Encryption for sensitive data
  unmapMarkSnapChainRemoved: "true"        # SSD optimization
reclaimPolicy: Retain                      # Never auto-delete
volumeBindingMode: Immediate
allowVolumeExpansion: true

---
# Example PVC for Home Assistant
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: home-assistant-config
  namespace: home-automation
  labels:
    app: home-assistant
    data-type: critical-config
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-critical-config
  resources:
    requests:
      storage: 10Gi
```

### 2. Media Library Storage (Plex/Jellyfin)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-media-library
  annotations:
    description: "For Plex/Jellyfin media libraries - optimized for capacity"
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "1"                    # Media can be re-downloaded
  staleReplicaTimeout: "2880"              # 48 hours (media is static)
  fromBackup: ""
  fsType: "ext4"
  diskSelector: "hdd,media,bulk"           # Cheap storage is fine
  nodeSelector: ""
  recurringJobSelector: ""                 # No backups needed
  dataLocality: "strict-local"             # Keep on same node as Plex
  replicaAutoBalance: "disabled"           # Don't move large media files
  encrypted: "false"                       # No encryption needed
  unmapMarkSnapChainRemoved: "false"       # HDD optimization
reclaimPolicy: Delete                      # Can delete if needed
volumeBindingMode: WaitForFirstConsumer    # Bind to node with Plex
allowVolumeExpansion: true

---
# Example PVC for Plex Media
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: plex-media
  namespace: media
  labels:
    app: plex
    data-type: media-library
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-media-library
  resources:
    requests:
      storage: 500Gi                       # Large capacity needed
```

### 3. Active Downloads Storage (qBittorrent)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-downloads
  annotations:
    description: "For active torrents and downloads - optimized for writes"
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "1"                    # Temporary data
  staleReplicaTimeout: "720"               # 12 hours
  fromBackup: ""
  fsType: "xfs"                            # Better for large files
  diskSelector: "ssd,downloads"            # Fast disk for active I/O
  nodeSelector: ""
  recurringJobSelector: ""                 # No backups
  dataLocality: "strict-local"             # Must be on same node
  replicaAutoBalance: "disabled"           # Don't move active downloads
  encrypted: "false"
  unmapMarkSnapChainRemoved: "true"        # Aggressive space reclamation
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true

---
# Example PVC for qBittorrent
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: qbittorrent-downloads
  namespace: media
  labels:
    app: qbittorrent
    data-type: active-downloads
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-downloads
  resources:
    requests:
      storage: 100Gi
```

### 4. Personal Files Storage (Nextcloud/Immich)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-personal-files
  annotations:
    description: "For irreplaceable personal files - maximum protection"
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"                    # Maximum redundancy
  staleReplicaTimeout: "30"                # Quick failover
  fromBackup: ""
  fsType: "ext4"
  diskSelector: "ssd,hdd"                  # Any reliable disk
  nodeSelector: ""
  recurringJobSelector: |
    [
      {
        "name": "backup-to-s3-daily",
        "isGroup": false
      },
      {
        "name": "snapshot-daily",
        "isGroup": false
      }
    ]
  dataLocality: "disabled"                 # Availability over performance
  replicaAutoBalance: "best-effort"        # Maintain distribution
  encrypted: "true"                        # Always encrypted
  unmapMarkSnapChainRemoved: "true"
reclaimPolicy: Retain                      # Never auto-delete
volumeBindingMode: Immediate
allowVolumeExpansion: true

---
# Example PVC for Nextcloud
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-data
  namespace: cloud-services
  labels:
    app: nextcloud
    data-type: personal-files
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn-personal-files
  resources:
    requests:
      storage: 100Gi
```

### 5. Database Storage

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: longhorn-database
  annotations:
    description: "For PostgreSQL/MySQL - optimized for random I/O"
provisioner: driver.longhorn.io
parameters:
  numberOfReplicas: "3"                    # High redundancy
  staleReplicaTimeout: "10"                # Very quick failover (10 min)
  fromBackup: ""
  fsType: "xfs"                            # Better for databases
  diskSelector: "nvme,ssd,database"        # Fastest disks only
  nodeSelector: ""
  recurringJobSelector: |
    [
      {
        "name": "backup-database-6h",
        "isGroup": false
      }
    ]
  dataLocality: "best-effort"              # Balance speed and availability
  replicaAutoBalance: "least-effort"       # Stable placement
  encrypted: "false"                       # DB handles encryption
  unmapMarkSnapChainRemoved: "true"        # SSD optimization
reclaimPolicy: Retain
volumeBindingMode: Immediate
allowVolumeExpansion: true
```

---

## Disk Tagging and Selection Strategy

### Setting Up Disk Tags When Adding Drives

```bash
#!/bin/bash
# Script: tag-and-add-disk.sh
# Usage: ./tag-and-add-disk.sh /dev/sdb ssd general

DEVICE=$1
DISK_TYPE=$2  # nvme, ssd, hdd
PURPOSE=$3    # database, media, downloads, general

# Determine mount path based on type and purpose
MOUNT_PATH="/var/lib/longhorn-${DISK_TYPE}-${PURPOSE}"

# Prepare and mount the disk
sudo mkdir -p $MOUNT_PATH
sudo mkfs.ext4 ${DEVICE}1
UUID=$(sudo blkid -s UUID -o value ${DEVICE}1)
echo "UUID=$UUID $MOUNT_PATH ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab
sudo mount -a

# Add to Longhorn with appropriate tags
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: $(hostname)
  namespace: longhorn-system
spec:
  disks:
    ${DISK_TYPE}-${PURPOSE}-$(date +%s):
      path: ${MOUNT_PATH}
      allowScheduling: true
      storageReserved: 10737418240  # 10GB reserved
      tags:
        - "${DISK_TYPE}"
        - "${PURPOSE}"
        - "$(date +%Y%m)"  # Month added for rotation tracking
EOF

echo "Disk added with tags: ${DISK_TYPE}, ${PURPOSE}"
```

### Disk Configuration Examples

```yaml
# Example: Multi-tier storage on a single node
apiVersion: longhorn.io/v1beta2
kind: Node
metadata:
  name: worker-1
  namespace: longhorn-system
spec:
  disks:
    nvme-database:
      path: /var/lib/longhorn-nvme-database
      allowScheduling: true
      storageReserved: 10Gi
      tags: ["nvme", "database", "critical"]
      
    ssd-general-1:
      path: /var/lib/longhorn-ssd-general
      allowScheduling: true
      storageReserved: 20Gi
      tags: ["ssd", "general", "configs"]
      
    ssd-downloads:
      path: /var/lib/longhorn-ssd-downloads
      allowScheduling: true
      storageReserved: 10Gi
      tags: ["ssd", "downloads", "temporary"]
      
    hdd-media-1:
      path: /var/lib/longhorn-hdd-media-1
      allowScheduling: true
      storageReserved: 50Gi
      tags: ["hdd", "media", "bulk", "plex"]
      
    hdd-backup:
      path: /var/lib/longhorn-hdd-backup
      allowScheduling: false  # Manual scheduling only
      storageReserved: 100Gi
      tags: ["hdd", "backup", "archive"]
```

---

## Application-Specific Configurations

### Home Assistant Optimization

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: home-assistant
  namespace: home-automation
spec:
  template:
    spec:
      # Node affinity to keep on specific hardware
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            preference:
              matchExpressions:
              - key: node-type
                operator: In
                values: ["primary", "stable"]
      
      containers:
      - name: home-assistant
        volumeMounts:
        - name: config
          mountPath: /config
        - name: cache  # Separate cache volume
          mountPath: /config/.cache
          
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: home-assistant-config  # Uses critical-config storage class
      - name: cache
        emptyDir:
          sizeLimit: 5Gi  # Ephemeral cache
```

### Plex Media Server Optimization

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: plex
  namespace: media
spec:
  template:
    spec:
      # Keep Plex on same node as media storage
      affinity:
        podAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: plex
            topologyKey: kubernetes.io/hostname
      
      containers:
      - name: plex
        volumeMounts:
        - name: config
          mountPath: /config
        - name: media
          mountPath: /media
        - name: transcode
          mountPath: /transcode
          
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: plex-config  # Uses critical-config class (3 replicas)
      - name: media
        persistentVolumeClaim:
          claimName: plex-media    # Uses media-library class (1 replica)
      - name: transcode
        emptyDir:                  # RAM disk for transcoding
          medium: Memory
          sizeLimit: 10Gi
```

### qBittorrent with VPN Optimization

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: qbittorrent-vpn
  namespace: media
spec:
  template:
    spec:
      containers:
      - name: qbittorrent
        volumeMounts:
        - name: config
          mountPath: /config
        - name: downloads
          mountPath: /downloads
        - name: incomplete
          mountPath: /incomplete
          
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: qbittorrent-config  # Small, replicated
      - name: downloads
        persistentVolumeClaim:
          claimName: qbittorrent-downloads  # Large, 1 replica, SSD
      - name: incomplete
        emptyDir:                          # Temporary incomplete files
          sizeLimit: 50Gi
```

### Nextcloud with Multiple Storage Tiers

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud
  namespace: cloud-services
spec:
  template:
    spec:
      initContainers:
      # Set up external storage mounts
      - name: setup-storage
        image: busybox
        command: ['sh', '-c', 'mkdir -p /var/www/html/data/media']
        
      containers:
      - name: nextcloud
        volumeMounts:
        - name: nextcloud-app
          mountPath: /var/www/html
        - name: nextcloud-data
          mountPath: /var/www/html/data
        - name: media-library
          mountPath: /var/www/html/data/media
          readOnly: true  # Read-only media mount
          
      volumes:
      - name: nextcloud-app
        persistentVolumeClaim:
          claimName: nextcloud-app  # App files, 2 replicas
      - name: nextcloud-data
        persistentVolumeClaim:
          claimName: nextcloud-data  # User files, 3 replicas, encrypted
      - name: media-library
        persistentVolumeClaim:
          claimName: plex-media  # Shared media, 1 replica
```

---

## Automated Storage Assignment

### Webhook for Automatic Storage Class Selection

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: storage-class-selector
  namespace: kube-system
data:
  rules.yaml: |
    rules:
      # Database workloads
      - match:
          labels:
            app-type: database
        storageClass: longhorn-database
        
      # Media servers
      - match:
          labels:
            app-type: media-server
        storageClass: longhorn-media-library
        
      # Download clients
      - match:
          labels:
            app-type: downloader
        storageClass: longhorn-downloads
        
      # Personal cloud storage
      - match:
          labels:
            app-type: cloud-storage
        storageClass: longhorn-personal-files
        
      # Home automation
      - match:
          labels:
            app-type: home-automation
        storageClass: longhorn-critical-config
        
      # Default
      - match:
          labels: {}
        storageClass: longhorn-general
```

### Helm Values for Automated Storage

```yaml
# values-storage.yaml for Helm charts
global:
  storageClass:
    # Automatically select based on app type
    selector:
      database: longhorn-database
      media: longhorn-media-library
      config: longhorn-critical-config
      downloads: longhorn-downloads
      personal: longhorn-personal-files

# Per-app overrides
plex:
  persistence:
    config:
      storageClass: longhorn-critical-config
      size: 10Gi
    media:
      storageClass: longhorn-media-library
      size: 1Ti
    transcode:
      enabled: false  # Use emptyDir instead

home-assistant:
  persistence:
    config:
      storageClass: longhorn-critical-config
      size: 10Gi
      retain: true  # Never delete

qbittorrent:
  persistence:
    config:
      storageClass: longhorn-critical-config
      size: 1Gi
    downloads:
      storageClass: longhorn-downloads
      size: 100Gi
```

---

## Migration and Optimization Scripts

### Script: Optimize Existing Volumes

```bash
#!/bin/bash
# optimize-volumes.sh - Migrate volumes to appropriate storage classes

# Function to migrate a PVC to new storage class
migrate_pvc() {
  NAMESPACE=$1
  OLD_PVC=$2
  NEW_STORAGE_CLASS=$3
  
  echo "Migrating $NAMESPACE/$OLD_PVC to $NEW_STORAGE_CLASS"
  
  # Create new PVC with correct storage class
  kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${OLD_PVC}-optimized
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${NEW_STORAGE_CLASS}
  resources:
    requests:
      storage: $(kubectl get pvc $OLD_PVC -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
EOF
  
  # Copy data (using a job)
  kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate-${OLD_PVC}
  namespace: ${NAMESPACE}
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: alpine
        command: ['sh', '-c', 'apk add rsync && rsync -av /old/ /new/']
        volumeMounts:
        - name: old
          mountPath: /old
        - name: new
          mountPath: /new
      volumes:
      - name: old
        persistentVolumeClaim:
          claimName: ${OLD_PVC}
      - name: new
        persistentVolumeClaim:
          claimName: ${OLD_PVC}-optimized
      restartPolicy: Never
EOF
  
  # Wait for migration
  kubectl wait --for=condition=complete job/migrate-${OLD_PVC} -n ${NAMESPACE} --timeout=1h
  
  echo "Migration complete for $OLD_PVC"
}

# Migrate Home Assistant to critical storage
migrate_pvc home-automation home-assistant-config longhorn-critical-config

# Migrate Plex media to bulk storage
migrate_pvc media plex-media longhorn-media-library

# Migrate downloads to fast temporary storage
migrate_pvc media qbittorrent-downloads longhorn-downloads
```

### Script: Auto-assign Storage on Deploy

```bash
#!/bin/bash
# deploy-with-storage.sh - Deploy app with automatic storage selection

APP_NAME=$1
APP_TYPE=$2  # database, media, config, downloads, personal

# Select storage class based on type
case $APP_TYPE in
  database)
    STORAGE_CLASS="longhorn-database"
    REPLICAS="3"
    ;;
  media)
    STORAGE_CLASS="longhorn-media-library"
    REPLICAS="1"
    ;;
  config)
    STORAGE_CLASS="longhorn-critical-config"
    REPLICAS="3"
    ;;
  downloads)
    STORAGE_CLASS="longhorn-downloads"
    REPLICAS="1"
    ;;
  personal)
    STORAGE_CLASS="longhorn-personal-files"
    REPLICAS="3"
    ;;
  *)
    STORAGE_CLASS="longhorn-general"
    REPLICAS="2"
    ;;
esac

echo "Deploying $APP_NAME with storage class: $STORAGE_CLASS (${REPLICAS} replicas)"

# Deploy with appropriate storage
helm install $APP_NAME ./charts/$APP_NAME \
  --set persistence.storageClass=$STORAGE_CLASS \
  --set-string app.labels.app-type=$APP_TYPE
```

---

## Best Practices Summary

### Storage Class Selection Matrix

| If your app... | Use this storage class | Because... |
|----------------|------------------------|------------|
| Stores irreplaceable configs | `longhorn-critical-config` | 3 replicas, encrypted, backed up |
| Is a database | `longhorn-database` | Fast disks, 3 replicas, consistent |
| Serves media files | `longhorn-media-library` | 1 replica, cheap storage, local |
| Downloads files | `longhorn-downloads` | 1 replica, fast disk, temporary |
| Stores user photos/docs | `longhorn-personal-files` | 3 replicas, encrypted, backed up |
| Needs general storage | `longhorn-general` | 2 replicas, balanced |

### Disk Addition Decision Tree

```
New Disk Available
├── Is it SSD/NVMe?
│   ├── Yes → Tag as "ssd" or "nvme"
│   │   ├── High capacity? → Add "general" tag
│   │   └── Small but fast? → Add "database" tag
│   └── No (HDD) → Tag as "hdd"
│       ├── Large capacity? → Add "media" tag
│       └── For backups? → Add "backup" tag, set allowScheduling=false
│
└── Add to Longhorn with tags → Storage classes automatically use it
```

### Quick Commands

```bash
# Check which storage class each PVC uses
kubectl get pvc -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
CLASS:.spec.storageClassName,\
SIZE:.spec.resources.requests.storage

# See disk usage by tag
kubectl get nodes.longhorn.io -n longhorn-system -o yaml | \
grep -A5 "tags:" | grep -E "ssd|hdd|nvme"

# Force volume to use specific disk type
kubectl annotate pvc my-pvc \
  longhorn.io/selected-node-disk-tags="ssd,general"
```

---

## Conclusion

By properly categorizing your workloads and using appropriate storage classes:

1. **Critical configs** get maximum protection (3 replicas, SSD, encrypted)
2. **Media files** use cheap storage efficiently (1 replica, HDD)
3. **Downloads** stay fast without wasting redundancy (1 replica, SSD)
4. **Personal files** are safe and backed up (3 replicas, encrypted, S3)
5. **Databases** get the performance they need (3 replicas, NVMe/SSD)

This approach ensures each workload gets exactly what it needs - no more, no less - maximizing both performance and storage efficiency in your home lab.