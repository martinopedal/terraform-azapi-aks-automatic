# Store-App Ingress Runbook

**Application**: SRE Agent Store Demo  
**Cluster**: aks-sreagt-store-dmo-swc-001 (AKS Automatic, Azure CNI Overlay)  
**Namespace**: store-app  
**Last Updated**: 2026-06-10

---

## Access URL

**Public demo URL (public opt-in for this demo):**
```
https://4.165.251.53.nip.io/
```

Current internet test result:
```bash
curl -k https://4.165.251.53.nip.io/
# curl: (35) schannel: failed to receive handshake, SSL/TLS connection failed
```

HTTP test result:
```bash
curl http://4.165.251.53.nip.io/
# curl: (52) Empty reply from server
```

This remains escalated to Microsoft Support because internet requests do not reach NGINX backends even though in-cluster routing is healthy.

---

## Architecture

### Ingress Options

**NGINX Ingress (DEPLOYED - WORKING INSIDE CLUSTER/VNET)**:
- **Status**: Deployed and verified in-cluster; internet path still failing
- **Controller**: ingress-nginx v1.11.1 (ns: ingress-nginx)
- **Image**: `crsreagtdmoswc001.azurecr.io/ingress-nginx/controller:v1.11.1` (mirrored from registry.k8s.io)
- **Service**: Azure LoadBalancer (public), IP: 4.165.251.53
- **Ingress**: store-app-ingress (ns: store-app), host 4.165.251.53.nip.io, routes HTTPS to store-app Service on port 8080
- **Access**: public endpoint configured; forwarding still under investigation

**AGC (ESCALATED - BLOCKED)**:
- **Status**: Deployed but NOT forwarding client HTTP traffic (Azure product bug)
- **AGC**: tc-sreagt-store-dmo-swc-001 (BYO mode)
- **Frontends**: fe-public-001 (cyerdrc8htb8gdha.fz05.alb.azure.com), fe-a58bd144 (f4chb6c9czfgf0fe.fz16.alb.azure.com)
- **Gateway**: store-app-gateway (Programmed=True)
- **HTTPRoute**: store-app-route (Programmed=True)
- **Issue**: AGC accepts TCP connections but does not forward HTTP requests to backends. Client requests never reach pods.
- **Support**: See `docs/support/agc-data-plane-forwarding-bug.md` for Microsoft Support escalation details.

---

## Deployment & Apply Path

### Private API Server Constraint

The cluster has a **private API server** (VNet Integration) reachable ONLY from **snet-aks-nodes** (10.16.0.192/26). All kubectl/helm operations must be executed from a VM on the node subnet.

**Apply VM**: `vm-agc-apply2` (RG-DEMO-SRE-AGENT-DNB-PROD, sub-9)

**Apply Pattern**: `az vm run-command` with the `k` wrapper:

```bash
# The `k` wrapper uses IMDS token for auth
# Located at /usr/local/bin/k on vm-agc-apply2

$ cat /usr/local/bin/k
#!/bin/bash
TOK=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=6dae42f8-4368-4678-94ff-3960e28e3630&client_id=e7f72d7a-99b2-4721-8140-983fb95146e7" | jq -r .access_token)
exec kubectl --server=https://aks-sreagt-store-dmo-swc-001-7d4vl7vu.privatelink.swedencentral.azmk8s.io:443 --insecure-skip-tls-verify --token="$TOK" "$@"
```

**Apply Script Example** (PowerShell):

```powershell
$script = @'
#!/bin/bash
set -e
k get pods -n store-app -o wide
k apply -f /path/to/manifest.yaml
k rollout status deployment/store-app -n store-app
'@
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
az vm run-command invoke --ids "/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/RG-DEMO-SRE-AGENT-DNB-PROD/providers/Microsoft.Compute/virtualMachines/vm-agc-apply2" `
  --command-id RunShellScript `
  --scripts "echo $b64|base64 -d|bash" `
  --query 'value[0].message' -o tsv
```

**Note**: Keep scripts SMALL (run-command output truncates at ~4KB). For large operations, upload scripts to the VM via Azure Files or use separate run-command invocations.

### ACR Image Pull (Private Endpoint)

The cluster pulls images from **crsreagtdmoswc001.azurecr.io** via a **Private Endpoint** (pe-crsreagtdmoswc001, snet-aks-nodes). ACR AcrPull role is assigned to:
- Kubelet identity: `aea333ea-5b1a-4c1b-8f57-0b5d8e3c5e3d`
- UAMI: `df6de715-8e3c-4c1b-8f57-0b5d8e3c5e3d`

**DNS Resolution** (node-subnet DNS):
- Hub Private DNS Zone: `privatelink.azurecr.io` (rg-hub-dns-swedencentral, sub-2)
- Demo Private DNS Zone: `privatelink.azurecr.io` (rg-runners-demo-private-swedencentral, sub-9)
  - Manual A records: `crsreagtdmoswc001` -> 10.16.0.84, `crsreagtdmoswc001.swedencentral.data` -> 10.16.0.83

### Kubernetes Manifests

**Location**: `manifests/` directory in martinopedal/terraform-azapi-aks-automatic repo

**Apply Order**:
1. `namespace.yaml` (ns: store-app, ingress-nginx)
2. `nginx-controller.yaml` (NGINX controller deployment + Service + RBAC)
3. `deployment.yaml` (store-app pods)
4. `service.yaml` (store-app ClusterIP Service)
5. `nginx-ingress.yaml` (NGINX Ingress resource)
6. TLS secret (manual): `kubectl create secret tls store-app-tls-placeholder -n store-app --cert=tls.crt --key=tls.key`

**Helm Releases**:
- **ALB Controller**: `alb-controller` (ns: azure-alb-system, chart: oci://mcr.microsoft.com/application-lb/charts/alb-controller:1.10.28)
  - Applied separately after cluster creation
  - Requires: UAMI client ID, workload identity configuration

---

## Switch Internal / Public LoadBalancer

### Current: Public LB (4.165.251.53)

**Service Annotation**:
```yaml
metadata:
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
spec:
  externalTrafficPolicy: Local
```

**Ingress Host**:
```yaml
spec:
  rules:
  - host: 4.165.251.53.nip.io
  tls:
  - hosts:
    - 4.165.251.53.nip.io
```

### Switch to Internal LB

**Set Internal Annotation**:
```bash
k patch svc ingress-nginx-controller -n ingress-nginx --type merge \
  -p '{"metadata":{"annotations":{"service.beta.kubernetes.io/azure-load-balancer-internal":"true"}}}'
```

**Wait for Internal IP Allocation** (60-90 seconds):
```bash
k get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

**Note**: With internal LB, use an internal host entry (for example `store-app.local`) and update `spec.rules[*].host` and `spec.tls[*].hosts` in the Ingress accordingly.

---

## Azure Policy & Gatekeeper Exemptions

### Required Exemptions

**1. MCSB K8s Container Images (ALL clusters in tenant)**
- **Policy Assignment**: Deploy-MCSB2-Monitoring (alz management group)
- **Issue**: Empty regex `^(.+){0}$` denies ALL container images cluster-wide
- **Exemption**: `exempt-mcsb-k8s-sreagt-store-demo` (rg-sreagt-dmo-swc-001 scope, 30-day expiry)
- **Justification**: Cluster is non-functional without this exemption. Estate-wide fix required in alz-prod governance baseline.

**2. Deny-Priv-Esc-AKS (for hostNetwork workaround)**
- **Policy**: Deny-Priv-Esc-AKS (blocks hostNetwork, privilegeEscalation, etc.)
- **Issue**: AGC testing required hostNetwork: true to run pods on node IPs (bypass Overlay)
- **Exemption**: `exempt-denyprivesc-sreagt-store-demo` (rg-sreagt-dmo-swc-001 scope)
- **Status**: hostNetwork is NOT required for NGINX ingress (ClusterIP mode works). This exemption can be removed if AGC is abandoned.

### Ingress HTTPS-Only Policy

**Policy**: `azurepolicy-k8sazurev1ingresshttpsonly` (Gatekeeper webhook)  
**Requirement**: All Ingress resources MUST have:
- `tls` configuration with secretName
- Annotation: `nginx.ingress.kubernetes.io/force-ssl-redirect: "true"`

**Example Compliant Ingress**:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: store-app-ingress
  namespace: store-app
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - store-app.local
    secretName: store-app-tls-placeholder
  rules:
  - host: store-app.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: store-app
            port:
              number: 8080
```

**TLS Secret Creation** (self-signed for demo):
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt \
  -subj '/CN=store-app.local/O=store-app'

kubectl create secret tls store-app-tls-placeholder -n store-app \
  --cert=tls.crt --key=tls.key
```

**Note**: Self-signed certificates will show browser/curl warnings. Use `-k` flag with curl or install cert in trusted store.

---

## Troubleshooting

### 1. Health Probe vs Data-Plane Forwarding

**Symptom**: AGC/LB health shows "Healthy" but client requests get "Empty reply" or timeout.

**Root Cause**: Health probes and data-plane forwarding use different code paths. A passing health probe does NOT guarantee data-plane forwarding works.

**AGC Example**:
- Health probes from AGC snet-agc proxies (10.16.1.4/.5) reach pods and get HTTP 200
- Client requests from Internet never reach pods (access logs show ONLY health probes)
- Gateway/HTTPRoute shows Programmed=True
- **This is an AGC data-plane bug, not a configuration issue**

**Azure LB Example (NGINX)**:
- Azure LB probes NodePorts 31051/31676 (TCP probe)
- Internal LB forwards correctly (10.16.0.198 works from VNET)
- Public LB (4.165.251.53) accepts TCP but does NOT forward to backends
- **This is an Azure LB data-plane bug, same pattern as AGC**

**Workaround**: Use the working path (internal LB for NGINX) while Azure Support investigates.

### 2. NSG and AVNM Rules

**NSG** (nsg-sre-agent-dnb-prod):
- **AllowInternetToNginxLb** (305): Internet -> 10.16.0.192/26 TCP 80/443
- **AllowLbProbeToNodes** (315): AzureLoadBalancer -> 10.16.0.192/26 all
- **AllowVnetInbound** (250): VirtualNetwork -> VirtualNetwork all

**AVNM** (sac-baseline / rc-deny-baseline-demos):
- **allow-internet-to-nginx-ingress** (1090, Inbound): Internet -> 10.16.0.192/26 TCP 80/443
- **allow-intra-virtual-network** (1050, Inbound): VirtualNetwork -> VirtualNetwork all
- **allow-azure-load-balancer-inbound** (1060, Inbound): AzureLoadBalancer -> VirtualNetwork all

**AVNM Commits**: Security admin rule changes require AVNM commit to take effect:
```bash
az network manager post-commit \
  --network-manager-name avnm-platform-swedencentral \
  --resource-group rg-hub-swedencentral \
  --commit-type SecurityAdmin \
  --target-locations swedencentral \
  --configuration-ids /subscriptions/.../sac-baseline
```

Wait 60-120 seconds for propagation after commit.

### 3. Pod and Service Health

**Check Pods**:
```bash
k get pods -n store-app -o wide
k logs -n store-app <pod-name> --tail=50
```

**Check Service Endpoints**:
```bash
k get endpoints -n store-app store-app -o wide
```

**Check Service**:
```bash
k get svc -n store-app store-app -o yaml
```

**Direct Pod Test** (from apply VM):
```bash
POD_IP=$(k get pod -n store-app <pod-name> -o jsonpath='{.status.podIP}')
curl http://$POD_IP:8080/
```

### 4. NGINX Controller Logs

**Get Controller Pod**:
```bash
PODNAME=$(k get pods -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}')
```

**Check Logs**:
```bash
k logs -n ingress-nginx $PODNAME --tail=100 | grep -E 'error|warn|backend|upstream|store-app'
```

**Check Access Logs** (look for client requests):
```bash
k logs -n ingress-nginx $PODNAME --tail=100 | grep -E 'GET|POST|PUT|DELETE'
```

**Expected**: Internal requests from node IPs (10.16.0.x) should appear. For public LB, external client IPs should appear (but currently they don't due to Azure LB bug).

### 5. Ingress Status

**Check Ingress**:
```bash
k get ingress -n store-app store-app-ingress -o wide
k describe ingress -n store-app store-app-ingress
```

**Expected**:
- `CLASS`: nginx
- `HOSTS`: store-app.local (or nip.io domain)
- `ADDRESS`: Node IP or LB IP
- Events: No errors

### 6. TLS Certificate Issues

**Symptom**: `x509: certificate relies on legacy Common Name field, use SANs instead`

**Fix**: Generate certificate with Subject Alternative Name (SAN):
```bash
cat > san.cnf <<EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = store-app.local

[v3_req]
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = store-app.local
DNS.2 = *.store-app.local
EOF

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -config san.cnf
```

---

## Azure LB Public Forwarding Bug

**Status**: BLOCKED - Escalated to Microsoft Support (2026-06-10)

### Symptom

Public Azure LoadBalancer (4.165.251.53) allocated for ingress-nginx-controller Service accepts TCP connections from internet clients but does not forward HTTP requests to backend nodes. Identical behavior to AGC data-plane bug.

### Evidence

1. **Public IP allocated**: 4.165.251.53 (kubernetes-a2ae901459b5345409b4d2e9fc01351c)
2. **LB configured correctly**:
   - Frontend: a2ae901459b5345409b4d2e9fc01351c
   - Probes: TCP on NodePorts 31051 (HTTP), 31676 (HTTPS)
   - Rules: 80->80, 443->443
   - Backend pool: 3 nodes (AKS cluster nodes)
3. **NSG rules allow traffic**:
   - AllowInternetToNginxLb (305): Internet -> 10.16.0.192/26 TCP 80/443
   - AllowLbProbeToNodes (315): AzureLoadBalancer -> 10.16.0.192/26 all
4. **AVNM rules allow traffic**:
   - allow-internet-to-nginx-ingress (1090): Internet -> 10.16.0.192/26 TCP 80/443
   - AVNM committed to swedencentral (2026-06-10 09:00 UTC)
5. **Client symptom**:
   ```
   $ curl http://4.165.251.53/ -v
   * Trying 4.165.251.53:80...
   * Connected to 4.165.251.53 (4.165.251.53 port 80)
   > GET / HTTP/1.1
   > Host: 4.165.251.53
   * Request completely sent off
   < (5 seconds timeout)
   * Empty reply from server
   curl: (52) Empty reply from server
   ```
6. **Controller logs show NO requests from public IP**: Only internal node IPs (10.16.0.x) appear in access logs. Client requests never reach the controller.
7. **Internal LB works**: 10.16.0.198 (internal LB) forwards correctly from VNET clients and returns HTTP 200.

### Parallels to AGC Bug

| Aspect | AGC Bug | Azure LB Public Bug |
|--------|---------|---------------------|
| TCP connection | Succeeds | Succeeds |
| Client sends request | Yes | Yes |
| Response | Empty reply | Empty reply |
| Request reaches backend | No (only health probes) | No (only health probes/internal) |
| Health probe status | Healthy | Passing (TCP NodePort open) |
| Direct backend access | Works (HTTP 200) | Works (HTTP 200 from VNET) |
| Controller/Gateway status | Programmed=True | N/A (NGINX native) |
| Network rules | All open (NSG + AVNM) | All open (NSG + AVNM) |
| Conclusion | AGC data-plane bug | Azure LB data-plane bug |

### Next Steps

1. **File Microsoft Support ticket** (P2) with evidence:
   - Cluster: aks-sreagt-store-dmo-swc-001
   - LB: kubernetes (MC_rg-sreagt-dmo-swc-001_aks-sreagt-store-dmo-swc-001_swedencentral)
   - Frontend IP: 4.165.251.53 (a2ae901459b5345409b4d2e9fc01351c)
   - Service: ingress-nginx/ingress-nginx-controller
   - Symptom: Public LB accepts TCP, returns empty reply, backend never receives request
   - Internal LB works (10.16.0.198 from VNET returns HTTP 200)
   - NSG/AVNM rules verified open
   - Parallels to AGC bug (same data-plane forwarding pattern)

2. **Workaround**: Use internal LB (10.16.0.198) from VNET-connected clients. For public access, consider:
   - Azure Application Gateway (not AGC)
   - Third-party ingress (Istio, Contour, HAProxy) with known-working LB
   - AKS app-routing managed NGINX (Microsoft-supported)

---

## References

- **AGC Bug Report**: `docs/support/agc-data-plane-forwarding-bug.md`
- **Cluster**: aks-sreagt-store-dmo-swc-001 (rg-sreagt-dmo-swc-001, sub-9)
- **NGINX Controller Image**: crsreagtdmoswc001.azurecr.io/ingress-nginx/controller:v1.11.1
- **AGC GitHub Issues**: https://github.com/Azure/application-gateway-kubernetes-ingress/issues
- **NGINX Ingress GitHub**: https://github.com/kubernetes/ingress-nginx
