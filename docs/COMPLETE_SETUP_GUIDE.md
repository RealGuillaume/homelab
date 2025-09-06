# 🏠 Complete Homelab Setup Guide

This is the definitive guide to recreate the entire homelab setup from scratch, documenting everything we configured during our deployment session.

## 📋 Table of Contents
- [Service Access Information](#service-access-information)
- [Account Setup Requirements](#account-setup-requirements)
- [Step-by-Step Setup Process](#step-by-step-setup-process)
- [Troubleshooting & Solutions](#troubleshooting--solutions)
- [Configuration Locations](#configuration-locations)

---

## 🌐 Service Access Information

### Internal (LAN) Access
**Base Domain:** `.home.lab`  
**Access Method:** Through Traefik reverse proxy

| Service | Internal URL | Default Port | Purpose |
|---------|--------------|--------------|---------|
| **Plex** | `http://plex.home.lab` | 32400 | Media streaming server |
| **Overseerr** | `http://overseerr.home.lab` | 5055 | Media request management |
| **Radarr** | `http://radarr.home.lab` | 7878 | Movie management |
| **Sonarr** | `http://sonarr.home.lab` | 8989 | TV show management |
| **Prowlarr** | `http://prowlarr.home.lab` | 9696 | Indexer management |
| **qBittorrent** | `http://qbittorrent.home.lab` | 8080 | Torrent client (VPN protected) |
| **Home Assistant** | `http://hass.home.lab` | 8123 | Smart home automation |
| **NextCloud** | `http://nextcloud.home.lab` | 80 | Personal cloud storage |
| **Immich** | `http://immich.home.lab` | 2283 | Photo management |
| **Mealie** | `http://mealie.home.lab` | 9000 | Recipe management |
| **Grocy** | `http://grocy.home.lab` | 9283 | Household inventory |
| **Traefik Dashboard** | `http://traefik.home.lab:8080` | 8080 | Reverse proxy admin |

### External (Internet) Access
**Domain:** `guidelajunglehomelab.casa`  
**Method:** Cloudflare Tunnel with optional Access authentication

| Service | External URL | Security |
|---------|--------------|----------|
| **Plex** | `https://plex.guidelajunglehomelab.casa` | Plex built-in auth (recommended) |
| **Overseerr** | `https://overseerr.guidelajunglehomelab.casa` | Cloudflare Access |
| **Home Assistant** | `https://hass.guidelajunglehomelab.casa` | Cloudflare Access (CRITICAL) |
| **NextCloud** | `https://nextcloud.guidelajunglehomelab.casa` | Built-in auth + optional Cloudflare Access |
| **Immich** | `https://immich.guidelajunglehomelab.casa` | Cloudflare Access (CRITICAL) |
| **Mealie** | `https://mealie.guidelajunglehomelab.casa` | Cloudflare Access (optional) |

**⚠️ Note:** Admin services (Radarr, Sonarr, Prowlarr, qBittorrent) are deliberately NOT exposed externally for security.

### LoadBalancer IPs (MetalLB Pool)
**IP Range:** `172.23.25.240-172.23.25.250`  
**Network:** WSL2 subnet (172.23.25.x)

---

## 🔐 Account Setup Requirements

### 1. Cloudflare Account
**Purpose:** Tunnel for external access + optional authentication  
**Setup URL:** https://cloudflare.com  
**Cost:** FREE

**Steps:**
1. Create account at cloudflare.com
2. Go to Zero Trust dashboard: https://one.dash.cloudflare.com
3. Choose team name (e.g., "homelab")
4. Select FREE plan

### 2. Domain Name
**Our Choice:** `guidelajunglehomelab.casa`  
**Registrar:** Any domain registrar  
**Cost:** ~$1-15/year depending on TLD

**Alternatives:**
- Buy cheap domain (.xyz, .top, .club for $1-2/year)
- Use free DuckDNS subdomain (limited functionality with Cloudflare)

### 3. VPN Provider (for qBittorrent)
**Our Choice:** AirVPN  
**Alternative:** Any WireGuard-compatible VPN  
**Required Features:**
- WireGuard support
- Port forwarding capability
- Custom configuration export

**⚠️ Important:** Mullvad removed port forwarding in July 2023 - don't use for torrenting

### 4. Cloudflare Tunnel Token
**Location:** Zero Trust → Networks → Tunnels  
**Our tunnel name:** homelab  
**Token format:** `eyJhIjoiOGVmYjU3OTg0...` (long string)

---

## 🚀 Step-by-Step Setup Process

### Phase 1: Infrastructure Setup

#### 1.1 Server Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y git curl ansible

# Clone repository
git clone https://github.com/RealGuillaume/homelab.git
cd homelab
```

#### 1.2 Configure Inventory
```bash
# Edit inventory file
nano inventories/home/hosts.ini

# Set your server details:
[k3s_server]
your-server-ip ansible_user=your-username
```

#### 1.3 Configure Variables
```bash
# Copy example secrets
cp examples/secrets.example.yml inventories/home/group_vars/vault.yml

# Edit with your actual values
nano inventories/home/group_vars/vault.yml

# Update these key values:
metallb_ip_range: 172.23.25.240-172.23.25.250  # Adjust to your network
cluster_domain: home.lab
timezone: America/Toronto  # Your timezone
```

### Phase 2: Kubernetes Cluster Deployment

#### 2.1 Deploy K3s
```bash
ansible-playbook -i inventories/home/hosts.ini playbooks/k3s-cluster.yml --ask-become-pass
```

#### 2.2 Deploy Networking (MetalLB, cert-manager)
```bash
ansible-playbook -i inventories/home/hosts.ini playbooks/networking.yml --ask-become-pass
```

#### 2.3 Deploy Core Services
```bash
# Deploy all services
ansible-playbook -i inventories/home/hosts.ini playbooks/homelab/all-homelab.yml --ask-become-pass

# Or deploy by category:
ansible-playbook -i inventories/home/hosts.ini playbooks/homelab/media-stack.yml --ask-become-pass
ansible-playbook -i inventories/home/hosts.ini playbooks/homelab/cloud-services.yml --ask-become-pass
ansible-playbook -i inventories/home/hosts.ini playbooks/homelab/home-automation.yml --ask-become-pass
```

### Phase 3: VPN Configuration (qBittorrent)

#### 3.1 Get VPN Configuration
**AirVPN Steps:**
1. Login to AirVPN client area
2. Go to Config Generator
3. Select WireGuard
4. Choose a server
5. Generate config
6. Note down port forwarding port

#### 3.2 Configure VPN Secret
```bash
# Create VPN configuration
cp examples/qbittorrent-vpn.yaml.example k8s/homelab/media/qbittorrent-vpn.yaml

# Edit with your VPN details:
nano k8s/homelab/media/qbittorrent-vpn.yaml

# Update these values:
WIREGUARD_PRIVATE_KEY: "your-private-key"
WIREGUARD_ADDRESSES: "your-vpn-ip/32" 
WIREGUARD_PUBLIC_KEY: "server-public-key"
WIREGUARD_PRESHARED_KEY: "preshared-key"
WIREGUARD_ENDPOINT_IP: "server-ip"
WIREGUARD_ENDPOINT_PORT: "server-port"
FIREWALL_VPN_INPUT_PORTS: "your-forwarded-port"

# In qBittorrent container env:
QBT_TORRENTING_PORT: "your-forwarded-port"
```

#### 3.3 Deploy VPN-enabled qBittorrent
```bash
kubectl apply -f k8s/homelab/media/qbittorrent-vpn.yaml
```

### Phase 4: External Access Setup

#### 4.1 Domain Configuration
1. **Purchase domain** (e.g., guidelajunglehomelab.casa)
2. **Add to Cloudflare:**
   - Go to Cloudflare dashboard
   - Add site → Enter your domain
   - Choose FREE plan
   - Copy nameservers

3. **Update registrar:**
   - Login to domain registrar
   - Change nameservers to Cloudflare's
   - Wait for propagation (5-30 minutes)

#### 4.2 Cloudflare Tunnel Setup
```bash
# Create tunnel configuration
cp examples/cloudflared.yaml.example k8s/cloudflare/cloudflared.yaml

# Add your tunnel token
nano k8s/cloudflare/cloudflared.yaml
# Replace: YOUR_CLOUDFLARE_TUNNEL_TOKEN_HERE

# Deploy tunnel
ansible-playbook -i inventories/home/hosts.ini playbooks/cloudflare-tunnel.yml --ask-become-pass
```

#### 4.3 Configure Tunnel Routes
**In Cloudflare Zero Trust dashboard:**

1. Go to **Networks → Tunnels → homelab → Configure**
2. Add these public hostnames:

| Subdomain | Domain | Service URL | HTTP Host Header |
|-----------|---------|-------------|------------------|
| plex | guidelajunglehomelab.casa | `http://172.23.25.244:32400` | (remove) |
| overseerr | guidelajunglehomelab.casa | `http://traefik.kube-system:80` | `overseerr.home.lab` |
| hass | guidelajunglehomelab.casa | `http://traefik.kube-system:80` | `hass.home.lab` |
| mealie | guidelajunglehomelab.casa | `http://traefik.kube-system:80` | `mealie.home.lab` |
| nextcloud | guidelajunglehomelab.casa | `http://traefik.kube-system:80` | `nextcloud.home.lab` |
| immich | guidelajunglehomelab.casa | `http://traefik.kube-system:80` | `immich.home.lab` |

#### 4.4 Security: Cloudflare Access
**For critical services (Home Assistant, Immich):**

1. Go to **Zero Trust → Access → Applications**
2. Create application for each service
3. Set authentication rules (email, Google, etc.)
4. Configure policies (family emails, admin access)

### Phase 5: Service Configuration

#### 5.1 Prowlarr Integration
1. Access Prowlarr: `http://prowlarr.home.lab`
2. Go to **Settings → Apps**
3. Add Radarr:
   - Server: `radarr.media.svc.cluster.local:7878`
   - API Key: Get from Radarr settings
4. Add Sonarr similarly
5. **Never add Prowlarr as indexer in Radarr/Sonarr!**

#### 5.2 NextCloud Domain Configuration
**If redirecting to .home.lab:**
```bash
# Fix trusted domains
kubectl exec -it -n cloud-services deployment/nextcloud -- su -s /bin/bash www-data -c "php occ config:system:set trusted_domains 1 --value=nextcloud.guidelajunglehomelab.casa"
kubectl exec -it -n cloud-services deployment/nextcloud -- su -s /bin/bash www-data -c "php occ config:system:set overwritehost --value=nextcloud.guidelajunglehomelab.casa"
kubectl exec -it -n cloud-services deployment/nextcloud -- su -s /bin/bash www-data -c "php occ config:system:set overwriteprotocol --value=https"
```

#### 5.3 qBittorrent Access
**Get temporary password:**
```bash
kubectl exec -it -n media deployment/qbittorrent-vpn -- cat /config/qBittorrent/config/qBittorrent.conf | grep "WebUI\Password_PBKDF2"
```

Default username: `admin`

---

## 🔧 Troubleshooting & Solutions

### Common Issues We Encountered

#### Issue 1: Prowlarr 406 NotAcceptable Error
**Problem:** Trying to add Prowlarr as indexer in Radarr/Sonarr  
**Solution:** Configure from Prowlarr side (Apps settings), not from Radarr/Sonarr

#### Issue 2: qBittorrent Unauthorized Access
**Problem:** No login page, just "Unauthorized"  
**Solution:** 
```bash
kubectl port-forward -n media svc/qbittorrent 8080:8080
# Access via http://localhost:8080
```

#### Issue 3: VPN Port Forwarding Issues
**Problem:** Torrents not downloading, no connectivity  
**Solutions:**
- Ensure VPN provider supports port forwarding
- Set `VPN_PORT_FORWARDING: "off"` for custom providers
- Match `QBT_TORRENTING_PORT` with `FIREWALL_VPN_INPUT_PORTS`

#### Issue 4: Cloudflared Tunnel Crashing
**Problem:** `CrashLoopBackOff` with exit code 137  
**Solution:** Remove health check probes (port 2000 doesn't exist in newer versions)

#### Issue 5: MetalLB Services Stuck in Pending
**Problem:** LoadBalancer external IPs show `<pending>`  
**Solutions:**
- Check IP pool matches your network subnet
- Verify MetalLB speaker pods are running
- Ensure sufficient IPs in pool

#### Issue 6: WSL2 Network Isolation
**Problem:** Services not accessible from phone/other devices  
**Solution:** Use Cloudflare Tunnel or Windows port forwarding:
```powershell
# Windows PowerShell (as Admin)
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=80 connectaddress=172.23.25.249 connectport=80
netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=443 connectaddress=172.23.25.249 connectport=443
```

### Diagnostic Commands

#### Check Cluster Health
```bash
# Check all pods
kubectl get pods -A

# Check services
kubectl get svc -A

# Check nodes
kubectl get nodes -o wide

# Check LoadBalancer IPs
kubectl get svc -A | grep LoadBalancer
```

#### Check Specific Services
```bash
# Check logs
kubectl logs -n media plex-xxxxx
kubectl logs -n cloudflare cloudflared-xxxxx

# Check service details
kubectl describe svc -n media plex

# Check pod details
kubectl describe pod -n media plex-xxxxx
```

#### Network Troubleshooting
```bash
# Test internal connectivity
curl -I http://traefik.kube-system:80

# Check MetalLB
kubectl get pods -n metallb-system
kubectl logs -n metallb-system speaker-xxxxx

# Check DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup plex.media.svc.cluster.local
```

---

## 📁 Configuration Locations

### Default Credentials
| Service | Username | Default Password | Location |
|---------|----------|------------------|----------|
| **NextCloud** | admin | adminpassword123 | Update in YAML |
| **qBittorrent** | admin | (temporary) | Get from logs |
| **Home Assistant** | (none) | Create on first run | Web interface |
| **Immich** | (none) | Create on first run | Web interface |

### Data Persistence
All services use Kubernetes PersistentVolumes with `local-path` storage:
- **Location:** `/var/lib/rancher/k3s/storage/`
- **Backup:** Regular backups of this directory recommended

### Configuration Files
```
homelab/
├── inventories/home/group_vars/all.yml    # Main configuration
├── k8s/homelab/                           # Service manifests
│   ├── media/                             # Plex, Radarr, etc.
│   ├── cloud-services/                    # NextCloud, Immich
│   └── home-automation/                   # Home Assistant
├── roles/                                 # Ansible automation
└── examples/                              # Template files
```

### Secret Management
- **Ansible Vault:** `inventories/home/group_vars/vault.yml`
- **Kubernetes Secrets:** Created by Ansible playbooks
- **Never commit:** Real passwords, API keys, VPN credentials

---

## 🚀 Quick Recovery Commands

### Complete Rebuild
```bash
# 1. Fresh server
git clone https://github.com/RealGuillaume/homelab.git
cd homelab

# 2. Configure secrets
cp examples/secrets.example.yml inventories/home/group_vars/vault.yml
# Edit with your values

# 3. Deploy everything
ansible-playbook -i inventories/home/hosts.ini playbooks/k3s-cluster.yml --ask-become-pass
ansible-playbook -i inventories/home/hosts.ini playbooks/networking.yml --ask-become-pass
ansible-playbook -i inventories/home/hosts.ini playbooks/homelab/all-homelab.yml --ask-become-pass

# 4. Configure VPN and tunnel (using examples)
cp examples/qbittorrent-vpn.yaml.example k8s/homelab/media/qbittorrent-vpn.yaml
cp examples/cloudflared.yaml.example k8s/cloudflare/cloudflared.yaml
# Edit with your credentials

# 5. Deploy additional components
kubectl apply -f k8s/homelab/media/qbittorrent-vpn.yaml
ansible-playbook -i inventories/home/hosts.ini playbooks/cloudflare-tunnel.yml --ask-become-pass
```

### Service Recovery
```bash
# Restart specific service
kubectl rollout restart deployment/plex -n media

# Force pod recreation
kubectl delete pod -n media -l app=plex

# Reapply configuration
kubectl apply -f k8s/homelab/media/plex.yaml
```

---

## 📞 Support Resources

### Documentation
- **K3s:** https://k3s.io/
- **Traefik:** https://doc.traefik.io/traefik/
- **Cloudflare Tunnel:** https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/

### Community
- **r/kubernetes:** https://reddit.com/r/kubernetes
- **r/homelab:** https://reddit.com/r/homelab
- **r/selfhosted:** https://reddit.com/r/selfhosted

---

**📝 This guide represents the complete setup as deployed and configured. Keep this document updated as you make changes to your homelab environment.**

*Last updated: [Current Date]*  
*Setup completed with Claude Code assistance*