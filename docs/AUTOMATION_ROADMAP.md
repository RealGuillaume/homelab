# 🤖 Homelab Automation Roadmap

## Executive Summary

This document maps all manual configuration steps in the homelab setup and provides a comprehensive automation strategy using APIs, Infrastructure as Code (IaC), and configuration management tools.

**Current State**: ~70% manual configuration required
**Target State**: 95% automated with single-command deployment
**Estimated Implementation**: 40-60 hours of development

---

## 📊 Manual Steps Analysis & Automation Potential

### 🔴 High Priority - Quick Wins (2-4 hours each)

#### 1. **AirVPN Configuration Automation**
**Current Manual Process:**
1. Login to AirVPN website
2. Navigate to Config Generator
3. Select WireGuard, choose server
4. Download config, extract keys
5. Manually copy to YAML

**Automation Solution:**
```bash
# AirVPN API Script (airvpn-setup.sh)
# https://airvpn.org/apisettings/ to get api key
#!/bin/bash
AIRVPN_API_KEY="${AIRVPN_API_KEY}"
SERVER_COUNTRY="ca"  # Canada

# Get best server
SERVER=$(curl -s "https://airvpn.org/api/servers" \
  -H "API-Key: ${AIRVPN_API_KEY}" | \
  jq -r ".servers[] | select(.country==\"${SERVER_COUNTRY}\") | .name" | head -1)

# Generate WireGuard config
CONFIG=$(curl -s "https://airvpn.org/api/generator" \
  -H "API-Key: ${AIRVPN_API_KEY}" \
  -d "system=linux&protocol=wireguard&server=${SERVER}&port=1637")

# Extract and create Kubernetes secret
echo "$CONFIG" | python3 extract_wireguard.py | \
  kubectl create secret generic airvpn-config --from-file=-
```

**APIs Required:**
- AirVPN REST API (https://airvpn.org/api/)
- Authentication: API Key from account

#### 2. **qBittorrent Initial Configuration**
**Current Manual Process:**
1. Access WebUI with temporary password
2. Set permanent password
3. Configure network interface binding
4. Set download paths
5. Configure connection limits

**Automation Solution:**
```python
# qbittorrent_setup.py
import qbittorrentapi

qbt = qbittorrentapi.Client(
    host='localhost', port=8080,
    username='admin', password='temporary_password'
)

# Set configuration
qbt.app_set_preferences({
    'web_ui_password': 'secure_password_here',
    'listen_port': 23059,
    'upnp': False,
    'dht': True,
    'pex': True,
    'lsd': True,
    'encryption': 2,  # Require encryption
    'anonymous_mode': False,
    'max_connec': 200,
    'max_uploads': 10,
    'max_active_downloads': 5,
    'max_active_torrents': 10,
    'save_path': '/downloads',
    'temp_path': '/downloads/temp',
    'preallocate_all': True,
    'incomplete_files_ext': True,
    'auto_delete_mode': 1,
    'web_ui_address': '*',
    'web_ui_port': 8080,
    'bypass_local_auth': False,
    'bypass_auth_subnet_whitelist': '10.42.0.0/16',
    'bypass_auth_subnet_whitelist_enabled': True,
    'use_interface': 'tun0',  # Force VPN interface
    'use_interface_name': 'tun0'
})
```

**APIs Required:**
- qBittorrent Web API v2.8+
- Python client: `pip install qbittorrent-api`

#### 3. **Arr Stack Integration**
**Current Manual Process:**
1. Get API keys from each service
2. Configure Prowlarr apps manually
3. Add indexers
4. Configure download clients

**Automation Solution:**
```yaml
# ansible-playbook arr-stack-config.yml
---
- name: Configure Arr Stack Integration
  hosts: localhost
  vars:
    prowlarr_url: "http://prowlarr.media.svc.cluster.local:9696"
    radarr_url: "http://radarr.media.svc.cluster.local:7878"
    sonarr_url: "http://sonarr.media.svc.cluster.local:8989"
    
  tasks:
    - name: Get Radarr API Key
      kubernetes.core.k8s_exec:
        namespace: media
        pod: radarr-xxxxx
        command: cat /config/config.xml | grep ApiKey
      register: radarr_key

    - name: Configure Prowlarr → Radarr
      uri:
        url: "{{ prowlarr_url }}/api/v1/applications"
        method: POST
        headers:
          X-Api-Key: "{{ prowlarr_api_key }}"
        body_format: json
        body:
          name: "Radarr"
          implementation: "Radarr"
          configContract: "RadarrSettings"
          fields:
            - name: "baseUrl"
              value: "{{ radarr_url }}"
            - name: "apiKey"
              value: "{{ radarr_key.stdout }}"
            - name: "syncCategories"
              value: [2000, 2010, 2020, 2030, 2040, 2050]
```

---

### 🟡 Medium Priority - Infrastructure Automation (8-16 hours each)

#### 4. **Cloudflare Complete Automation**
**Current Manual Process:**
1. Create account (still manual)
2. Add domain
3. Create Zero Trust team
4. Create tunnel
5. Configure routes
6. Setup Access applications

**Automation Solution with Terraform:**
```hcl
# cloudflare.tf
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Add domain to Cloudflare
resource "cloudflare_zone" "homelab" {
  account_id = var.cloudflare_account_id
  zone       = "guidelajunglehomelab.casa"
  plan       = "free"
}

# Create Tunnel
resource "cloudflare_tunnel" "homelab" {
  account_id = var.cloudflare_account_id
  name       = "homelab-k8s"
  secret     = random_id.tunnel_secret.b64_std
}

# Configure Tunnel Routes
resource "cloudflare_tunnel_config" "homelab" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.homelab.id

  config {
    ingress_rule {
      hostname = "plex.${cloudflare_zone.homelab.zone}"
      service  = "http://172.23.25.244:32400"
    }
    ingress_rule {
      hostname = "overseerr.${cloudflare_zone.homelab.zone}"
      service  = "http://traefik.kube-system:80"
      origin_request {
        http_host_header = "overseerr.home.lab"
      }
    }
    # ... more routes
    
    # Catch-all
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Create Access Application
resource "cloudflare_access_application" "home_assistant" {
  zone_id                   = cloudflare_zone.homelab.id
  name                      = "Home Assistant"
  domain                    = "hass.${cloudflare_zone.homelab.zone}"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
}

# Access Policy
resource "cloudflare_access_policy" "family" {
  application_id = cloudflare_access_application.home_assistant.id
  zone_id        = cloudflare_zone.homelab.id
  name           = "Family Access"
  precedence     = 1
  decision       = "allow"

  include {
    email = ["user@gmail.com", "family@gmail.com"]
  }
}

# Output tunnel token for Kubernetes
output "tunnel_token" {
  value     = cloudflare_tunnel.homelab.tunnel_token
  sensitive = true
}
```

**Alternative with Ansible:**
```yaml
# cloudflare-setup.yml
- name: Setup Cloudflare
  hosts: localhost
  vars:
    cf_api_token: "{{ vault_cloudflare_api_token }}"
    cf_account_id: "{{ vault_cloudflare_account_id }}"
    domain: "guidelajunglehomelab.casa"
    
  tasks:
    - name: Create Cloudflare Tunnel
      uri:
        url: "https://api.cloudflare.com/client/v4/accounts/{{ cf_account_id }}/tunnels"
        method: POST
        headers:
          Authorization: "Bearer {{ cf_api_token }}"
        body_format: json
        body:
          name: "homelab-k8s"
          tunnel_secret: "{{ lookup('password', '/dev/null length=32') | b64encode }}"
      register: tunnel_result

    - name: Store tunnel credentials
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: v1
          kind: Secret
          metadata:
            name: cloudflare-tunnel
            namespace: cloudflare
          data:
            token: "{{ tunnel_result.json.result.token | b64encode }}"
```

#### 5. **Domain Purchase & DNS Automation**
**Automation with Namecheap API:**
```python
# domain_setup.py
import requests

NAMECHEAP_API_KEY = "your_api_key"
NAMECHEAP_USER = "your_username"

def purchase_domain(domain_name):
    """Purchase domain via Namecheap API"""
    response = requests.post(
        "https://api.namecheap.com/xml.response",
        params={
            "ApiUser": NAMECHEAP_USER,
            "ApiKey": NAMECHEAP_API_KEY,
            "Command": "namecheap.domains.create",
            "DomainName": domain_name,
            "Years": 1
        }
    )
    return response

def set_cloudflare_nameservers(domain_name):
    """Update nameservers to Cloudflare"""
    nameservers = [
        "cody.ns.cloudflare.com",
        "dina.ns.cloudflare.com"
    ]
    
    response = requests.post(
        "https://api.namecheap.com/xml.response",
        params={
            "ApiUser": NAMECHEAP_USER,
            "ApiKey": NAMECHEAP_API_KEY,
            "Command": "namecheap.domains.dns.setCustom",
            "DomainName": domain_name,
            "Nameservers": ",".join(nameservers)
        }
    )
    return response
```

---

### 🟢 Low Priority - Nice to Have (4-8 hours each)

#### 6. **Service Health Monitoring**
```yaml
# monitoring-setup.yml
apiVersion: v1
kind: ConfigMap
metadata:
  name: health-checker
  namespace: default
data:
  check.sh: |
    #!/bin/bash
    # Check all services and auto-fix common issues
    
    # Check VPN connection
    if ! kubectl exec -n media deployment/qbittorrent-vpn -c gluetun -- \
         wget -qO- ipinfo.io | grep -q "AirVPN"; then
      echo "VPN down, restarting..."
      kubectl rollout restart deployment/qbittorrent-vpn -n media
    fi
    
    # Check Cloudflare tunnel
    if kubectl get pod -n cloudflare -l app=cloudflared | grep -q "0/1"; then
      echo "Cloudflare tunnel down, restarting..."
      kubectl rollout restart deployment/cloudflared -n cloudflare
    fi
    
    # Check service connectivity
    for service in plex radarr sonarr prowlarr; do
      if ! curl -s "http://${service}.media.svc.cluster.local" > /dev/null; then
        echo "${service} not responding, restarting..."
        kubectl rollout restart deployment/${service} -n media
      fi
    done
```

#### 7. **Backup Automation**
```bash
#!/bin/bash
# backup-automation.sh

# Backup all PVCs
for pvc in $(kubectl get pvc -A -o json | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name)"'); do
  namespace=$(echo $pvc | cut -d/ -f1)
  name=$(echo $pvc | cut -d/ -f2)
  
  # Create backup job
  kubectl create job backup-${name}-$(date +%s) \
    --from=cronjob/backup-template \
    -n ${namespace} \
    -- restic backup /data \
      --repo s3:s3.amazonaws.com/homelab-backups/${namespace}/${name}
done
```

---

## 🚀 Implementation Roadmap

### Phase 1: Foundation (Week 1)
1. **Create automation repository**
   ```bash
   homelab-automation/
   ├── terraform/           # IaC for cloud providers
   ├── ansible/            # Configuration management
   ├── scripts/            # Automation scripts
   ├── apis/              # API integrations
   └── secrets/           # Encrypted credentials
   ```

2. **Setup secrets management**
   - Use Ansible Vault for sensitive data
   - Or integrate with HashiCorp Vault
   - Store API keys securely

### Phase 2: Quick Wins (Week 2)
1. Implement AirVPN automation
2. Automate qBittorrent setup
3. Create Arr stack integration scripts
4. Test end-to-end

### Phase 3: Infrastructure (Week 3-4)
1. Terraform for Cloudflare
2. Ansible playbooks for K8s resources
3. Domain automation (if using API-friendly registrar)
4. Create CI/CD pipeline

### Phase 4: Advanced Features (Week 5-6)
1. Monitoring and alerting
2. Automatic backups
3. Self-healing capabilities
4. GitOps with FluxCD or ArgoCD

---

## 🔑 API Keys Required

| Service | API Documentation | Authentication | Cost |
|---------|------------------|----------------|------|
| **Cloudflare** | [API v4](https://api.cloudflare.com/) | API Token (scoped) | FREE |
| **AirVPN** | [API Docs](https://airvpn.org/api/) | API Key | Included |
| **Namecheap** | [API](https://www.namecheap.com/support/api/) | API Key + Whitelist IP | FREE |
| **qBittorrent** | [Web API](https://github.com/qbittorrent/qBittorrent/wiki/WebUI-API) | Session cookie | N/A |
| **Radarr** | [API v3](https://radarr.video/docs/api/) | API Key | N/A |
| **Sonarr** | [API v3](https://github.com/Sonarr/Sonarr/wiki/API) | API Key | N/A |
| **Prowlarr** | [API](https://wiki.servarr.com/prowlarr/api) | API Key | N/A |
| **Plex** | [API](https://github.com/Arcanemagus/plex-api/wiki) | Auth Token | N/A |

---

## 🎯 Complete Automation Script

### One-Command Deployment Goal
```bash
# deploy-homelab.sh
#!/bin/bash

# Check prerequisites
command -v terraform >/dev/null 2>&1 || { echo "Install terraform"; exit 1; }
command -v ansible >/dev/null 2>&1 || { echo "Install ansible"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Install kubectl"; exit 1; }

# Load configuration
source .env

# Step 1: Setup infrastructure
echo "🏗️ Setting up infrastructure..."
terraform -chdir=terraform init
terraform -chdir=terraform apply -auto-approve

# Step 2: Deploy Kubernetes
echo "☸️ Deploying Kubernetes..."
ansible-playbook -i inventories/home/hosts.ini playbooks/k3s-cluster.yml

# Step 3: Configure networking
echo "🌐 Configuring networking..."
ansible-playbook -i inventories/home/hosts.ini playbooks/networking.yml

# Step 4: Setup Cloudflare
echo "☁️ Configuring Cloudflare..."
export TUNNEL_TOKEN=$(terraform -chdir=terraform output -raw tunnel_token)
envsubst < k8s/cloudflare/cloudflared.yaml | kubectl apply -f -

# Step 5: Get VPN config
echo "🔐 Setting up VPN..."
./scripts/airvpn-setup.sh

# Step 6: Deploy services
echo "🚀 Deploying services..."
ansible-playbook -i inventories/home/hosts.ini playbooks/homelab/all-homelab.yml

# Step 7: Configure services
echo "⚙️ Configuring services..."
./scripts/configure-arr-stack.sh
./scripts/configure-qbittorrent.sh

# Step 8: Setup monitoring
echo "📊 Setting up monitoring..."
kubectl apply -f k8s/monitoring/

echo "✅ Homelab deployment complete!"
echo "Access at: https://overseerr.${DOMAIN}"
```

---

## 🔒 Security Considerations

### API Key Management
```yaml
# secrets.yml (encrypted with ansible-vault)
cloudflare_api_token: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  66383439383437366...

airvpn_api_key: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  35663836643966306...
```

### Kubernetes Secrets
```bash
# Create sealed secrets for GitOps
kubectl create secret generic api-keys \
  --from-literal=cloudflare="${CF_TOKEN}" \
  --from-literal=airvpn="${AIRVPN_KEY}" \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-secrets.yaml
```

### Access Control
- Use RBAC for Kubernetes service accounts
- Scope API tokens minimally
- Rotate credentials regularly
- Audit API usage

---

## 📈 Metrics & Success Criteria

### Current State
- **Setup Time**: 4-6 hours manual work
- **Error Rate**: ~30% (manual mistakes)
- **Reproducibility**: Low
- **Documentation Drift**: High

### Target State (Post-Automation)
- **Setup Time**: 15 minutes
- **Error Rate**: <5%
- **Reproducibility**: 100%
- **Documentation**: Auto-generated

### ROI Calculation
- **Time Saved Per Deployment**: 3.5-5.5 hours
- **Deployments Per Year**: ~10 (rebuilds, testing, friends)
- **Annual Time Saved**: 35-55 hours
- **Break-even**: After 2nd deployment

---

## 🎬 Next Steps

1. **Prioritize** based on your pain points
2. **Start small** with AirVPN and qBittorrent automation
3. **Test thoroughly** in a dev environment
4. **Document** any manual steps that remain
5. **Iterate** and improve based on usage

### Quick Start Commands
```bash
# Clone automation repo
git clone https://github.com/yourusername/homelab-automation
cd homelab-automation

# Install dependencies
pip install -r requirements.txt
ansible-galaxy install -r requirements.yml

# Configure environment
cp .env.example .env
# Edit .env with your API keys

# Run first automation
./scripts/quick-setup.sh
```

---

## 📚 Resources & References

### Official Documentation
- [Terraform Cloudflare Provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [Ansible Kubernetes Collection](https://docs.ansible.com/ansible/latest/collections/kubernetes/core/)
- [Kubernetes Python Client](https://github.com/kubernetes-client/python)

### Community Tools
- [Boilerplates for Arr Stack](https://github.com/TRaSH-/Guides)
- [Cloudflare Tunnel Operator](https://github.com/adyanth/cloudflare-operator)
- [k8s-at-home Charts](https://github.com/k8s-at-home/charts)

### Monitoring & Observability
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [Uptime Kuma](https://github.com/louislam/uptime-kuma)

---

*This roadmap is a living document. Update it as you implement automation and discover new opportunities.*

**Last Updated**: 2025-09-06
**Version**: 1.0.0
**Maintainer**: Homelab Team