# Home Cluster MVP - Single Node K3s Setup

A production-ready single-node Kubernetes cluster for home lab environments with MetalLB load balancing, cert-manager for TLS, and a demo code-server application.

## Architecture Overview

- **Single Node**: One Debian/Ubuntu host serving as K3s server, compute, and storage
- **Load Balancing**: MetalLB for bare-metal LoadBalancer services
- **TLS Management**: cert-manager with internal CA
- **Storage**: K3s local-path provisioner (default)
- **Ingress**: Traefik (K3s default)
- **Demo App**: VS Code Server accessible via browser

## Prerequisites

- Debian/Ubuntu host with:
  - SSH access via key authentication
  - Sudo privileges for the SSH user
  - At least 4GB RAM and 20GB disk space
  - Static IP address
- Ansible control machine with:
  - Ansible 2.9+ installed
  - SSH key configured for target host
  - Python 3.6+

## Quick Start

### 1. Configure Inventory

Edit `inventories/home/hosts.ini` to match your environment:

```ini
[k3s_server]
mypc ansible_host=192.168.1.10 ansible_user=ubuntu
```

Update `inventories/home/group_vars/all.yml` if needed:
- `metallb_ip_range`: IP range for LoadBalancer services (default: 192.168.1.240-192.168.1.250)
- `cluster_domain`: Internal domain suffix (default: home.lab)
- `timezone`: Your timezone (default: America/Toronto)

### 2. Run Playbooks

Execute playbooks in order:

```bash
# Bootstrap cluster (install K3s, cert-manager, CA)
ansible-playbook -i inventories/home/hosts.ini playbooks/bootstrap.yml

# Configure networking (install MetalLB)
ansible-playbook -i inventories/home/hosts.ini playbooks/networking.yml

# Deploy demo application (code-server)
ansible-playbook -i inventories/home/hosts.ini playbooks/demo.yml
```

### 3. Trust Internal CA Certificate

The internal CA certificate is automatically fetched to `~/home-cluster-ca/ca.crt` on your Ansible control machine.

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/home-cluster-ca/ca.crt
```

**Linux:**
```bash
sudo cp ~/home-cluster-ca/ca.crt /usr/local/share/ca-certificates/home-cluster-ca.crt
sudo update-ca-certificates
```

**Windows:**
1. Double-click `ca.crt`
2. Click "Install Certificate"
3. Select "Local Machine" → "Place all certificates in: Trusted Root Certification Authorities"

**Firefox:** Settings → Privacy & Security → Certificates → View Certificates → Import

### 4. Configure DNS or /etc/hosts

Get the MetalLB IP for code-server:
```bash
ssh ubuntu@192.168.1.10 "kubectl get svc -n demo code-server"
```

Add to `/etc/hosts` (replace with actual IP):
```
192.168.1.241 code.home.lab
```

Or configure your DNS server to resolve `*.home.lab` to the MetalLB IP range.

### 5. Access Demo Application

Open browser to: https://code.home.lab

Default password: `changeme123!` (configured in `k8s/demo/code-server.yaml`)

## Verification Commands

SSH to the K3s server and run:

```bash
# Check cluster status
kubectl get nodes
kubectl get pods -A

# Check cert-manager
kubectl get deploy,svc,pods -n cert-manager
kubectl get clusterissuer

# Check MetalLB
kubectl get pods -n metallb-system
kubectl get ipaddresspool,l2advertisement -n metallb-system

# Check demo app
kubectl get all -n demo
kubectl get ingress -n demo

# Get LoadBalancer IPs
kubectl get svc -A | grep LoadBalancer
```

## Directory Structure

```
home-cluster-mvp/
├── ansible.cfg              # Ansible configuration
├── inventories/
│   └── home/
│       ├── hosts.ini       # Inventory file
│       ├── group_vars/     # Group variables
│       └── host_vars/      # Host-specific variables
├── playbooks/
│   ├── bootstrap.yml       # Initial cluster setup
│   ├── networking.yml      # MetalLB configuration
│   └── demo.yml           # Demo app deployment
├── roles/
│   ├── common/            # Base system configuration
│   ├── k3s/              # K3s installation
│   ├── metallb/          # MetalLB setup
│   ├── ca_trust/         # Internal CA generation
│   └── cert_manager/     # cert-manager installation
└── k8s/
    └── demo/
        └── code-server.yaml  # Demo application manifest
```

## Component Details

### K3s Configuration
- Version: v1.31.3+k3s1
- ServiceLB disabled (using MetalLB instead)
- Kubeconfig mode: 644 (readable by non-root)
- Node labels: role=server, role=compute, role=storage

### MetalLB Configuration
- Version: v0.14.9
- L2 mode (no BGP)
- IP Pool: 192.168.1.240-192.168.1.250

### cert-manager Configuration
- Version: v1.14.10
- ClusterIssuer: ca-issuer (using internal CA)
- Automatic TLS certificate generation for Ingress resources

### Internal CA
- RSA 4096-bit key
- Valid for 10 years
- Stored in `/root/ca/` on K3s server
- Secret `ca-key-pair` in cert-manager namespace

## Troubleshooting

### Cannot reach code.home.lab
1. Check MetalLB assigned IP: `kubectl get svc -n demo code-server`
2. Verify /etc/hosts entry or DNS resolution
3. Check ingress: `kubectl describe ingress -n demo code-server`
4. Check certificate: `kubectl get certificate -n demo`

### cert-manager not issuing certificates
1. Check ClusterIssuer: `kubectl describe clusterissuer ca-issuer`
2. Check CA secret: `kubectl get secret -n cert-manager ca-key-pair`
3. Check cert-manager logs: `kubectl logs -n cert-manager deploy/cert-manager`

### MetalLB not assigning IPs
1. Check speaker pods: `kubectl get pods -n metallb-system`
2. Check IP pool: `kubectl describe ipaddresspool -n metallb-system`
3. Check for conflicts with K3s ServiceLB (should be disabled)

## Security Considerations

1. **Change default passwords**: Update the code-server password in `k8s/demo/code-server.yaml`
2. **Firewall rules**: Restrict access to K3s API (6443) and MetalLB range
3. **SSH hardening**: Use key-only authentication, disable root login
4. **Network segmentation**: Consider VLAN isolation for cluster network
5. **Regular updates**: Keep K3s, MetalLB, and cert-manager updated

## Next Steps

- Add monitoring (Prometheus + Grafana)
- Configure persistent storage (NFS, Longhorn, or Rook-Ceph)
- Set up GitOps with ArgoCD or Flux
- Add backup solution (Velero)
- Implement network policies
- Add additional nodes for HA

## License

MIT