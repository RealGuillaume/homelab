# Longhorn Complete Disaster Recovery Guide

## Table of Contents
1. [Disaster Scenarios Overview](#disaster-scenarios-overview)
2. [Backup Strategies](#backup-strategies)
3. [Recovery Protocols](#recovery-protocols)
4. [Backup Target Options](#backup-target-options)
5. [Automated Backup Configuration](#automated-backup-configuration)
6. [Complete Recovery Procedures](#complete-recovery-procedures)
7. [Testing and Validation](#testing-and-validation)

---

## Disaster Scenarios Overview

### Disaster Types and Recovery Methods

```mermaid
graph TD
    A[Disaster Type] --> B[Single Volume Corruption]
    A --> C[Node Failure]
    A --> D[Multiple Node Failure]
    A --> E[Complete Cluster Loss]
    A --> F[Datacenter Disaster]
    
    B --> B1[Restore from Snapshot]
    C --> C1[Automatic Replica Rebuild]
    D --> D1[Restore from Remaining Replicas]
    E --> E1[Restore from S3/NFS Backup]
    F --> F1[Rebuild Cluster + Restore from Offsite]
    
    style E fill:#ff9999
    style F fill:#ff6666
```

### Recovery Time Objectives (RTO)

| Disaster Level | Data Loss | Recovery Time | Recovery Method |
|---------------|-----------|---------------|-----------------|
| **Volume Corruption** | None | < 5 minutes | Local snapshot |
| **Single Node Failure** | None | < 10 minutes | Automatic failover |
| **Multi-Node Failure** | None | < 30 minutes | Replica rebuild |
| **Complete Cluster Loss** | Up to last backup | 2-4 hours | S3/NFS restore |
| **Site Disaster** | Up to last offsite backup | 4-8 hours | Full rebuild |

---

## Backup Strategies

### 3-2-1-1-0 Backup Rule for Kubernetes

```mermaid
graph LR
    subgraph "3 Copies"
        A[Original Data]
        B[Longhorn Replica 1]
        C[Longhorn Replica 2]
    end
    
    subgraph "2 Different Media"
        D[Local Disk]
        E[S3/NFS]
    end
    
    subgraph "1 Offsite"
        F[Cloud Backup]
    end
    
    subgraph "1 Offline"
        G[Cold Storage]
    end
    
    subgraph "0 Errors"
        H[Verified Backups]
    end
    
    A --> B
    A --> C
    B --> D
    C --> E
    E --> F
    F --> G
    G --> H
```

### Backup Frequency Matrix

| Data Type | Snapshot Frequency | S3 Backup | Retention | Priority |
|-----------|-------------------|-----------|-----------|----------|
| **Critical Configs** | Every 1h | Daily | 30 days | P1 |
| **Databases** | Every 6h | Twice daily | 14 days | P1 |
| **Personal Files** | Daily | Daily | 90 days | P2 |
| **Application Data** | Every 12h | Weekly | 30 days | P3 |
| **Media Libraries** | Weekly | Never | 7 days | P4 |
| **Temporary/Downloads** | Never | Never | None | P5 |

---

## Recovery Protocols

### Protocol 1: Single Volume Recovery

```mermaid
sequenceDiagram
    participant User
    participant Kubectl
    participant Longhorn
    participant Snapshot
    participant S3
    
    User->>Kubectl: Detect corrupted volume
    Kubectl->>Longhorn: List available snapshots
    
    alt Local Snapshot Available
        Longhorn->>Snapshot: Restore from snapshot
        Snapshot-->>Kubectl: Volume restored
    else No Local Snapshot
        Longhorn->>S3: List backups
        S3-->>Longhorn: Download backup
        Longhorn-->>Kubectl: Volume restored
    end
    
    Kubectl-->>User: Service restored
```

**Recovery Commands:**
```bash
# Option 1: Restore from local snapshot
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: restored-pvc
  namespace: original-namespace
spec:
  storageClassName: longhorn
  dataSource:
    name: snapshot-name
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Option 2: Restore from S3 backup
kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Volume
metadata:
  name: restore-from-s3
  namespace: longhorn-system
spec:
  fromBackup: "s3://longhorn-backups@us-east-1/backups/backup-xyz"
  dataSource: pvc-original
EOF
```

### Protocol 2: Complete Cluster Loss Recovery

```mermaid
graph TD
    A[Cluster Lost] --> B{Backup Available?}
    
    B -->|Yes| C[Provision New Cluster]
    B -->|No| Z[Data Lost]
    
    C --> D[Install K3s]
    D --> E[Install Longhorn]
    E --> F[Configure S3 Backup Target]
    F --> G[List Available Backups]
    
    G --> H[Create Priority Groups]
    H --> I[P1: Critical Configs]
    H --> J[P2: Databases]
    H --> K[P3: User Data]
    
    I --> L[Restore P1 Volumes]
    L --> M[Verify Core Services]
    M --> N[Restore P2 Volumes]
    N --> O[Verify Databases]
    O --> P[Restore P3 Volumes]
    P --> Q[Full Service Restoration]
    
    style A fill:#ff9999
    style Z fill:#ff0000
    style Q fill:#90EE90
```

**Recovery Script:**
```bash
#!/bin/bash
# disaster-recovery.sh - Complete cluster recovery from S3

# Step 1: Install fresh K3s cluster
curl -sfL https://get.k3s.io | sh -

# Step 2: Install Longhorn
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

# Step 3: Wait for Longhorn
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

# Step 4: Configure S3 backup target
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: s3-backup-secret
  namespace: longhorn-system
stringData:
  AWS_ACCESS_KEY_ID: "${AWS_ACCESS_KEY_ID}"
  AWS_SECRET_ACCESS_KEY: "${AWS_SECRET_ACCESS_KEY}"
EOF

kubectl patch settings.longhorn.io backup-target -n longhorn-system --type='merge' -p \
  '{"value":"s3://disaster-recovery@us-east-1/"}'

kubectl patch settings.longhorn.io backup-target-credential-secret -n longhorn-system --type='merge' -p \
  '{"value":"s3-backup-secret"}'

# Step 5: List and restore backups
echo "Fetching backup list..."
kubectl get backups.longhorn.io -n longhorn-system

# Step 6: Restore critical volumes first
for backup in $(kubectl get backups.longhorn.io -n longhorn-system -o json | jq -r '.items[] | select(.metadata.labels.priority=="P1") | .metadata.name'); do
  echo "Restoring P1 backup: $backup"
  kubectl apply -f - <<EOF
apiVersion: longhorn.io/v1beta1
kind: Volume
metadata:
  name: restored-${backup}
  namespace: longhorn-system
spec:
  fromBackup: "${backup}"
  numberOfReplicas: 3
EOF
done
```

### Protocol 3: Site Disaster Recovery (Multi-Region)

```mermaid
graph TB
    subgraph "Primary Site"
        A[Production Cluster]
        B[Longhorn Storage]
        C[Local Backups]
    end
    
    subgraph "Backup Pipeline"
        D[Continuous Sync]
        E[S3 Primary Region]
        F[S3 Cross-Region Replication]
    end
    
    subgraph "DR Site"
        G[Standby Cluster]
        H[S3 DR Region]
        I[Restored Services]
    end
    
    A --> B
    B --> C
    C --> D
    D --> E
    E --> F
    F --> H
    
    H --> G
    G --> I
    
    style A fill:#90EE90
    style I fill:#87CEEB
```

---

## Backup Target Options

### Option 1: AWS S3

```yaml
# S3 Configuration
apiVersion: v1
kind: Secret
metadata:
  name: s3-backup-secret
  namespace: longhorn-system
stringData:
  AWS_ACCESS_KEY_ID: "your-access-key"
  AWS_SECRET_ACCESS_KEY: "your-secret-key"
  AWS_DEFAULT_REGION: "us-east-1"
---
# Longhorn Settings
backup-target: "s3://longhorn-backups@us-east-1/"
backup-target-credential-secret: "s3-backup-secret"

# Cost Optimization with Lifecycle
# Use S3 Glacier for old backups
aws s3api put-bucket-lifecycle-configuration --bucket longhorn-backups \
  --lifecycle-configuration file://lifecycle.json

# lifecycle.json:
{
  "Rules": [{
    "Id": "ArchiveOldBackups",
    "Status": "Enabled",
    "Transitions": [{
      "Days": 30,
      "StorageClass": "GLACIER"
    }]
  }]
}
```

### Option 2: MinIO (Self-Hosted S3)

```yaml
# Deploy MinIO for on-premise S3
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: backup-system
spec:
  template:
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args:
        - server
        - /data
        - --console-address
        - ":9001"
        env:
        - name: MINIO_ROOT_USER
          value: "admin"
        - name: MINIO_ROOT_PASSWORD
          value: "changeme123"
        volumeMounts:
        - name: storage
          mountPath: /data
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: minio-storage
---
# Configure Longhorn to use MinIO
backup-target: "s3://longhorn-backups@minio-service.backup-system.svc.cluster.local:9000/"
```

### Option 3: NFS Backup Target

```yaml
# NFS Server Setup
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nfs-server
  namespace: backup-system
spec:
  template:
    spec:
      containers:
      - name: nfs-server
        image: itsthenetwork/nfs-server-alpine:latest
        env:
        - name: SHARED_DIRECTORY
          value: "/exports"
        securityContext:
          privileged: true
        volumeMounts:
        - name: storage
          mountPath: /exports
      volumes:
      - name: storage
        persistentVolumeClaim:
          claimName: nfs-backup-storage
---
# Configure Longhorn for NFS
backup-target: "nfs://nfs-server.backup-system.svc.cluster.local:/exports"
```

### Option 4: Backblaze B2 (S3-Compatible)

```bash
# Backblaze B2 Configuration
export B2_ACCOUNT_ID="your-account-id"
export B2_APPLICATION_KEY="your-app-key"
export B2_BUCKET="longhorn-backups"
export B2_ENDPOINT="s3.us-west-001.backblazeb2.com"

# Create secret
kubectl create secret generic b2-backup-secret \
  -n longhorn-system \
  --from-literal=AWS_ACCESS_KEY_ID="${B2_ACCOUNT_ID}" \
  --from-literal=AWS_SECRET_ACCESS_KEY="${B2_APPLICATION_KEY}" \
  --from-literal=AWS_ENDPOINTS="${B2_ENDPOINT}"

# Configure Longhorn
backup-target: "s3://${B2_BUCKET}@${B2_ENDPOINT}/"
```

### Option 5: Hybrid Multi-Target Backup

```mermaid
graph LR
    A[Longhorn Volume] --> B{Backup Controller}
    
    B --> C[Fast Tier: Local NFS]
    B --> D[Medium Tier: MinIO]
    B --> E[Archive Tier: S3 Glacier]
    
    C --> C1[Hourly Snapshots]
    D --> D1[Daily Backups]
    E --> E1[Weekly Archives]
    
    style C fill:#90EE90
    style D fill:#87CEEB
    style E fill:#DDA0DD
```

---

## Automated Backup Configuration

### Recurring Backup Jobs

```yaml
# Critical Config Backup Job
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: backup-critical-hourly
  namespace: longhorn-system
spec:
  cron: "0 * * * *"  # Every hour
  task: "backup"
  groups:
  - "critical"
  retain: 24  # Keep 24 hourly backups
  concurrency: 2
  labels:
    priority: "P1"
    type: "config"
---
# Database Backup Job
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: backup-database-6h
  namespace: longhorn-system
spec:
  cron: "0 */6 * * *"  # Every 6 hours
  task: "backup"
  groups:
  - "database"
  retain: 8  # Keep 2 days worth
  concurrency: 1
  labels:
    priority: "P1"
    type: "database"
---
# User Data Backup Job
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: backup-userdata-daily
  namespace: longhorn-system
spec:
  cron: "0 2 * * *"  # 2 AM daily
  task: "backup"
  groups:
  - "userdata"
  retain: 30  # Keep 30 days
  concurrency: 3
  labels:
    priority: "P2"
    type: "personal"
---
# Snapshot Cleanup Job
apiVersion: longhorn.io/v1beta1
kind: RecurringJob
metadata:
  name: snapshot-cleanup-weekly
  namespace: longhorn-system
spec:
  cron: "0 3 * * 0"  # Sunday 3 AM
  task: "snapshot-cleanup"
  retain: 5
  concurrency: 1
```

### Volume Labeling for Automatic Backups

```yaml
# Label volumes for automatic backup
apiVersion: longhorn.io/v1beta1
kind: Volume
metadata:
  name: home-assistant-config
  namespace: longhorn-system
  labels:
    recurring-job.longhorn.io/backup-critical-hourly: "enabled"
    recurring-job-group.longhorn.io/critical: "enabled"
    backup-priority: "P1"
spec:
  numberOfReplicas: 3
---
# PVC with backup annotations
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-data
  annotations:
    longhorn.io/recurring-job-selector: |
      [
        {
          "name": "backup-userdata-daily",
          "isGroup": false
        }
      ]
spec:
  storageClassName: longhorn
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
```

---

## Complete Recovery Procedures

### Procedure 1: Test Environment Recovery

```mermaid
sequenceDiagram
    participant Admin
    participant TestCluster
    participant Longhorn
    participant S3
    participant Validation
    
    Admin->>TestCluster: Deploy test K3s
    TestCluster->>Longhorn: Install Longhorn
    Longhorn->>S3: Connect to backup target
    
    Admin->>Longhorn: List production backups
    Longhorn-->>Admin: Backup list
    
    Admin->>Longhorn: Restore selected backups
    Longhorn->>S3: Download backups
    S3-->>Longhorn: Backup data
    Longhorn-->>TestCluster: Volumes restored
    
    Admin->>Validation: Run test suite
    Validation-->>Admin: Recovery validated
```

**Test Recovery Script:**
```bash
#!/bin/bash
# test-recovery.sh - Validate backup recovery process

# Create test namespace
kubectl create namespace recovery-test

# Restore a test backup
LATEST_BACKUP=$(kubectl get backups.longhorn.io -n longhorn-system \
  -o json | jq -r '.items[0].metadata.name')

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-restore
  namespace: recovery-test
spec:
  storageClassName: longhorn
  dataSource:
    name: ${LATEST_BACKUP}
    kind: VolumeBackup
    apiGroup: longhorn.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF

# Deploy test pod to validate data
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: validate-restore
  namespace: recovery-test
spec:
  containers:
  - name: validator
    image: busybox
    command: ['sh', '-c', 'ls -la /data && md5sum /data/* && sleep 3600']
    volumeMounts:
    - name: restored-data
      mountPath: /data
  volumes:
  - name: restored-data
    persistentVolumeClaim:
      claimName: test-restore
EOF

# Check restoration
kubectl logs -n recovery-test validate-restore
```

### Procedure 2: Incremental Recovery

```mermaid
graph TD
    A[Start Recovery] --> B{Assess Damage}
    
    B -->|Partial Loss| C[Identify Missing Volumes]
    B -->|Complete Loss| D[Full Recovery Mode]
    
    C --> E[List Available Backups]
    E --> F[Match Backups to Missing Volumes]
    F --> G[Restore in Priority Order]
    
    D --> H[Rebuild Infrastructure]
    H --> I[Restore System Volumes]
    I --> J[Restore Application Volumes]
    J --> K[Restore User Data]
    
    G --> L[Verify Services]
    K --> L
    
    L --> M{All Services OK?}
    M -->|No| N[Troubleshoot]
    M -->|Yes| O[Recovery Complete]
    
    N --> P[Check Logs]
    P --> Q[Fix Issues]
    Q --> L
    
    style O fill:#90EE90
```

### Procedure 3: Point-in-Time Recovery

```bash
#!/bin/bash
# point-in-time-recovery.sh - Restore to specific timestamp

TARGET_TIME="2024-01-15T10:30:00Z"
NAMESPACE="production"

# Find backups before target time
kubectl get backups.longhorn.io -n longhorn-system -o json | \
  jq -r --arg time "$TARGET_TIME" \
  '.items[] | select(.metadata.creationTimestamp < $time) | .metadata.name' | \
  sort -r | head -1

# Restore each volume to that point
for volume in $(kubectl get pvc -n $NAMESPACE -o name); do
  VOLUME_NAME=$(echo $volume | cut -d/ -f2)
  
  # Find matching backup
  BACKUP=$(kubectl get backups.longhorn.io -n longhorn-system \
    -l volume=$VOLUME_NAME \
    -o json | jq -r --arg time "$TARGET_TIME" \
    '.items[] | select(.metadata.creationTimestamp < $time) | .metadata.name' | \
    sort -r | head -1)
  
  if [ ! -z "$BACKUP" ]; then
    echo "Restoring $VOLUME_NAME from backup $BACKUP"
    kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${VOLUME_NAME}-pit-restore
  namespace: ${NAMESPACE}
spec:
  storageClassName: longhorn
  dataSource:
    name: ${BACKUP}
    kind: VolumeBackup
    apiGroup: longhorn.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $(kubectl get pvc $VOLUME_NAME -n $NAMESPACE -o jsonpath='{.spec.resources.requests.storage}')
EOF
  fi
done
```

---

## Testing and Validation

### Disaster Recovery Testing Schedule

```mermaid
gantt
    title DR Testing Calendar
    dateFormat  YYYY-MM-DD
    section Monthly Tests
    Snapshot Recovery       :done, 2024-01-05, 1d
    Single Volume Recovery  :done, 2024-01-15, 1d
    Snapshot Recovery       :active, 2024-02-05, 1d
    Single Volume Recovery  :2024-02-15, 1d
    
    section Quarterly Tests
    Node Failure Simulation :done, 2024-01-20, 2d
    S3 Restore Test        :2024-04-20, 2d
    
    section Annual Tests
    Complete Cluster Recovery :2024-06-01, 5d
    Site Failover Test       :2024-12-01, 7d
```

### Automated DR Testing

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: dr-test-monthly
  namespace: longhorn-system
spec:
  schedule: "0 2 1 * *"  # First day of month, 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: dr-test
            image: dr-test:latest
            command:
            - /bin/sh
            - -c
            - |
              # Test snapshot recovery
              kubectl apply -f /tests/snapshot-recovery.yaml
              sleep 60
              kubectl wait --for=condition=ready pod/test-recovery -n test
              
              # Validate data integrity
              kubectl exec test-recovery -n test -- md5sum /data/test-file
              
              # Test S3 backup
              kubectl create backup test-backup-$(date +%s) \
                --volume test-volume -n longhorn-system
              
              # Report results
              curl -X POST $SLACK_WEBHOOK -d \
                '{"text":"DR Test Complete: All systems recoverable"}'
          restartPolicy: OnFailure
```

### Recovery Metrics Dashboard

```yaml
# Grafana Dashboard JSON
{
  "dashboard": {
    "title": "Disaster Recovery Metrics",
    "panels": [
      {
        "title": "Backup Success Rate",
        "targets": [{
          "expr": "rate(longhorn_backup_success_total[24h])"
        }]
      },
      {
        "title": "Time Since Last Backup",
        "targets": [{
          "expr": "time() - longhorn_backup_last_timestamp"
        }]
      },
      {
        "title": "Recovery Time (RTO)",
        "targets": [{
          "expr": "histogram_quantile(0.95, longhorn_restore_duration_seconds)"
        }]
      },
      {
        "title": "Backup Storage Usage",
        "targets": [{
          "expr": "longhorn_backup_target_usage_bytes"
        }]
      }
    ]
  }
}
```

---

## Recovery Checklist

### Pre-Disaster Preparation
- [ ] S3/NFS backup target configured
- [ ] Recurring backup jobs active
- [ ] Backup encryption enabled
- [ ] Off-site backup copy exists
- [ ] Recovery scripts tested
- [ ] Team trained on procedures
- [ ] Contact list updated

### During Disaster
- [ ] Assess damage scope
- [ ] Activate incident response team
- [ ] Communicate with stakeholders
- [ ] Document timeline of events
- [ ] Preserve evidence if needed

### Post-Recovery
- [ ] Verify all services operational
- [ ] Check data integrity
- [ ] Review backup gaps
- [ ] Update disaster recovery plan
- [ ] Conduct post-mortem
- [ ] Test backups again

---

## Summary

This comprehensive disaster recovery guide ensures:

1. **Multiple Backup Targets** - S3, MinIO, NFS, Backblaze B2
2. **Automated Backups** - Recurring jobs based on data criticality
3. **Clear Recovery Protocols** - Step-by-step for each disaster type
4. **Testing Procedures** - Regular validation of backups
5. **Complete Recovery Scripts** - From single volume to entire cluster

With this setup, you can recover from:
- **Corrupted volumes** in minutes using snapshots
- **Failed nodes** automatically with replicas
- **Complete cluster loss** in hours from S3
- **Site disasters** using off-site backups

The key is regular testing and maintaining multiple backup copies across different media and locations.