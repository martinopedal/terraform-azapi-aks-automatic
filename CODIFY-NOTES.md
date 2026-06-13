# Codify Notes - SRE Agent AGC Demo

## Infrastructure External to This Module

The following infrastructure was provisioned manually or belongs in other repos
and is NOT codified in this module:

### 1. DNS A Records (External - Platform Team Managed)

**Hub Private DNS Zone** (`privatelink.azurecr.io` in `rg-hub-dns-swedencentral`, sub-2):
- The PE DNS Zone Group auto-creates the A record when the ACR PE is deployed.
- The hub zone is pre-created by the platform team and linked to hub + spoke VNets.
- **Action**: None required - this module creates the PE DNS Zone Group.

**Demo Private DNS Zone** (`privatelink.azurecr.io` in `rg-runners-demo-private-swedencentral`, sub-9):
- Manual A records were added for AKS nodes resolving via Azure-default DNS (168.63.129.16):
  - `crsreagtdmoswc001` → 10.16.0.84
  - `crsreagtdmoswc001.swedencentral.data` → 10.16.0.83
- **Action**: These are workarounds for AKS nodes not using hub DNS (10.0.0.4). Evaluate
  making AKS nodes use vnet DNS so only the hub zone is needed. As-is works but is
  not the ALZ canonical pattern.

### 2. AVNM Egress Rule (External - ALZ Governance Baseline)

**AVNM Rule** (`allow-agc-dataplane-egress` in `avnm-platform-swedencentral` / `sac-baseline`):
- Security admin config: `sac-baseline`
- Rule collection: `rc-deny-baseline-demos`
- Network group: `ng-alz-demos`
- Rule: Outbound Allow, priority 1080, src 10.16.1.0/24 → Internet
- **Action**: Codify in `alz-avm-tf-demo/alz-prod` or `alz-avm-tf-demo/avnm-platform` repo,
  NOT here. This module does not manage AVNM configs.

### 3. NSG Rules (ALZ Corp Vending Mode)

**Shared NSG** (`nsg-sre-agent-dnb-prod` in `rg-demo-sre-agent-dnb-prod`, sub-9):
- In ALZ Corp vending mode, the NSG is pre-provisioned by the platform team.
- Manual rules added for AGC ingress (2026-06-10):
  - `AllowInternetToAgc` (prio 300, Inbound TCP 80,443 from Internet → 10.16.1.0/24)
  - `AllowLbToAgc` (prio 310, Inbound * from AzureLoadBalancer → 10.16.1.0/24)
  - `AllowAgcToBackends` (prio 320, Inbound * from 10.16.1.0/24 → *)
  - `AllowVnetInbound` (prio 400, Inbound * from VirtualNetwork → VirtualNetwork)
- **Action**: Document these requirements in the vending pipeline or platform team runbook.
  This module creates an `nsg_agc` resource with these rules for standalone mode only.

### 4. ALB Controller Helm Release (Applied Separately)

The ALB controller deployment is defined in `alb-controller.tf` (UAMI + FIC + roles),
but the **Helm release** is applied separately after cluster creation:

```bash
helm install alb-controller \
  oci://mcr.microsoft.com/application-lb/charts/alb-controller \
  --version 1.10.28 \
  --namespace azure-alb-system \
  --create-namespace \
  --set identity.clientID=<uami-client-id> \
  --set workload.identity.clientID=<uami-client-id>
```

**Action**: This is intentionally separate from Terraform to avoid Helm provider
dependency. Document in deployment runbook or CI/CD pipeline.

### 5. Kubernetes Manifests (Applied Separately)

The manifests in `manifests/` (Gateway, HTTPRoute, Service, Deployment) are applied
via `kubectl` after cluster creation and ALB controller installation.

**Action**: Document apply order in deployment runbook or CI/CD pipeline.

---

## Known Issues

### AGC Data-Plane Forwarding Bug (2026-06-10)

**Symptom**: Internet clients TCP-connect to AGC frontends but receive "Empty reply
from server" (HTTP 000). Health probes work, direct backend access works, both
frontends fail identically.

**Root Cause**: AGC (BYO mode + Gateway API v1 + AKS Automatic + ALB controller 1.10.28)
has a data-plane forwarding defect. The HTTPRoute shows Programmed=True, but AGC
does not forward client HTTP traffic to backends.

**Status**: AGC configs remain codified for Microsoft Support escalation. **NGINX Ingress
is deployed as the WORKING alternative** (see section below).

**Evidence**: See `.squad/decisions/inbox/drake-agc-rootcause.md` in `alz-avm-tf-demo/alz-prod`.

---

## NGINX Ingress (Working Alternative - 2026-06-10)

While AGC data-plane forwarding is blocked at the Azure product level, **NGINX Ingress
is deployed as the working ingress** for the SRE store-app demo.

### Deployment

**Controller**: `manifests/nginx-controller.yaml`
- Namespace: `ingress-nginx`
- Image: `crsreagtdmoswc001.azurecr.io/ingress-nginx/controller:v1.11.1` (mirrored from `registry.k8s.io`)
- Service: Internal Azure LoadBalancer (private-by-default)
- LB IP: 10.16.0.198 (private, VNET-accessible only)

**Ingress**: `manifests/nginx-ingress.yaml`
- Routes HTTPS traffic (Host: `store-app.local`) to `store-app` Service on port 8080
- Requires TLS secret `store-app-tls-placeholder` (created manually with self-signed cert for policy compliance)

### Verification (2026-06-10)

From node-subnet VM (vm-agc-apply2):
```
$ curl -k https://10.16.0.198/ -H "Host: store-app.local"
HTTP/1.1 200 OK
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

**HTTP 200 ACHIEVED** via NGINX ingress (internal access from VNET).

### TLS Secret Creation (Manual)

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj '/CN=store-app.local/O=store-app'
kubectl create secret tls store-app-tls-placeholder -n store-app --cert=tls.crt --key=tls.key
```

### ACR Image Import (Manual)

```bash
az acr import --name crsreagtdmoswc001 \
  --source registry.k8s.io/ingress-nginx/controller:v1.11.1 \
  --image ingress-nginx/controller:v1.11.1
```

### Notes

- **Internal LB**: The NGINX controller Service uses an internal Azure LB (10.16.0.198)
  per private-by-default directive. For internet-facing demos, change the Service annotation
  to remove `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` and the LB
  will get a public IP.
- **Policy**: The ingress requires `force-ssl-redirect: "true"` annotation + TLS config
  to satisfy the Azure Policy "Ingress should allow https only" (Gatekeeper webhook).
- **hostNetwork**: The store-app deployment can remain with `hostNetwork: true` (current)
  or revert to normal ClusterIP mode - NGINX works with both. hostNetwork was added for
  AGC testing and is not required for NGINX.

---

## Codify Completion Checklist

### AGC Infrastructure (Codified for MS Support Escalation)
- [x] ACR Private Endpoint (`dependencies.tf`)
- [x] ACR PE DNS Zone Group (`dependencies.tf`)
- [x] ALB Controller UAMI + FIC + roles (`alb-controller.tf`)
- [x] AGC Traffic Controller + Frontend + Association (`agc.tf`)
- [x] NSG for AGC Subnet (standalone mode) (`network.tf`)
- [x] Policy Exemption: MCSB K8s Images (`policy-exemptions.tf`)
- [x] Policy Exemption: Deny-Priv-Esc-AKS (`policy-exemptions.tf`)
- [x] ACR AcrPull role (kubelet identity) (`dependencies.tf`)
- [x] Manifests (Gateway, HTTPRoute, Service, Deployment) (`manifests/`)

### NGINX Ingress (Working Alternative)
- [x] NGINX Controller manifest (`manifests/nginx-controller.yaml`)
- [x] NGINX Ingress manifest (`manifests/nginx-ingress.yaml`)
- [x] ACR image import (manual: `az acr import`)
- [x] TLS secret creation (manual: `kubectl create secret tls`)
- [x] HTTP 200 verified from VNET (2026-06-10)

### External Infrastructure (Not in This Module)
- [ ] DNS A records (external - platform team / manual)
- [ ] AVNM egress rule (external - alz-prod governance baseline)
- [ ] Helm release for ALB controller (applied separately - not in Terraform)
- [ ] Manifest apply (applied separately - not in Terraform)

---

## References

- **AGC Issue**: `.squad/decisions/inbox/drake-agc-rootcause.md` (alz-prod)
- **AGC GitHub**: https://github.com/Azure/application-gateway-kubernetes-ingress/issues
- **AVNM Platform**: `alz-avm-tf-demo/avnm-platform` repo
- **ALZ Governance**: `alz-avm-tf-demo/alz-prod` repo
