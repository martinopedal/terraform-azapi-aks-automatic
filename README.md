# AKS Automatic – Deep Dive & Terraform (azapi) Example

## Table of Contents

- [What is AKS Automatic?](#what-is-aks-automatic)
- [How AKS Automatic Differs from AKS Standard](#how-aks-automatic-differs-from-aks-standard)
- [Components & Architecture](#components--architecture)
  - [SKU & Cluster Tier](#sku--cluster-tier)
  - [Node Provisioning (Karpenter)](#node-provisioning-karpenter)
  - [Networking](#networking)
  - [Ingress](#ingress)
  - [Egress](#egress)
  - [BYO VNet](#byo-vnet)
  - [Security](#security)
  - [Monitoring & Observability](#monitoring--observability)
  - [Auto-Upgrade & Maintenance](#auto-upgrade--maintenance)
  - [Scaling](#scaling)
  - [Storage](#storage)
  - [Policy Enforcement](#policy-enforcement)
- [What Is Preconfigured vs. What You Can Fine-Tune](#what-is-preconfigured-vs-what-you-can-fine-tune)
- [Terraform Project Structure](#terraform-project-structure)
- [Deployment Scenarios](#deployment-scenarios)
- [Regional Availability & Limitations](#regional-availability--limitations)
- [References](#references)

---

## What is AKS Automatic?

AKS Automatic is an opinionated, production-ready flavour of Azure Kubernetes Service. It takes care of cluster setup, node management, scaling, security, and networking – embedding **AKS Well-Architected best practices** by default. You get a fully managed Kubernetes experience while still retaining full access to the Kubernetes API and its ecosystem.

| Aspect | Benefit |
|---|---|
| **Production ready by default** | Preconfigured for optimal production use; fully managed node pools that auto-scale based on workload demand. |
| **Built-in best practices** | Hardened security defaults, automatic patching, deployment safeguards via Azure Policy. |
| **Code to Kubernetes in minutes** | Go from a container image to a deployed, best-practice application quickly. |

---

## How AKS Automatic Differs from AKS Standard

The fundamental ARM API difference is:

```json
{
  "sku": {
    "name": "Automatic",
    "tier": "Standard"
  },
  "properties": {
    "nodeProvisioningProfile": {
      "mode": "Auto"
    }
  }
}
```

In AKS Standard you would use `"sku": { "name": "Base", "tier": "Free|Standard|Premium" }` and `"nodeProvisioningProfile": { "mode": "Manual" }`.

Many features that are **optional** in Standard become **preconfigured** (always on, cannot be changed) or **default** (enabled for you but can be adjusted) in Automatic.

---

## Components & Architecture

### SKU & Cluster Tier

| Property | Value | Notes |
|---|---|---|
| `sku.name` | `Automatic` | Triggers the Automatic experience |
| `sku.tier` | `Standard` | Always Standard tier – includes uptime SLA (99.95%), up to 5,000 nodes |
| Support plan | `KubernetesOfficial` | LTS (`AKSLongTermSupport`) is available only on Premium tier (Standard SKU) |

### Node Provisioning (Karpenter)

AKS Automatic uses **Node Autoprovisioning (NAP)** powered by Karpenter. There are no manually managed node pools – the cluster creates and right-sizes nodes dynamically based on pending pod requests.

| Property | Path | Fine-tunable? | Notes |
|---|---|---|---|
| Mode | `nodeProvisioningProfile.mode` | **No** – must be `Auto` | Core differentiator |
| Default node pools | `nodeProvisioningProfile.defaultNodePools` | Yes (`None` / `Auto`) | Controls default Karpenter NodePool CRDs |
| System pool | `agentPoolProfiles[0]` | Partially | VM size is dynamically selected; influence via quota |
| Node OS | Always **Azure Linux** | **No** | Preconfigured |
| Node auto-repair | Always enabled | **No** | Preconfigured |
| Node resource group | **ReadOnly** | **No** | Locked to prevent accidental changes |

**Post-deployment tuning via Karpenter CRDs:**

- Create `NodePool` CRDs → influence VM families, spot vs. on-demand, taints, labels, topology spread
- Create `AKSNodeClass` CRDs → configure OS disk type/size, image version
- Set `.spec.limits` on NodePool → cap total vCPU/memory per pool

---

### Networking

AKS Automatic uses **Azure CNI Overlay powered by Cilium** – a high-performance, eBPF-based data plane with integrated network policy enforcement.

| Component | Setting | Fine-tunable? |
|---|---|---|
| Network plugin | `azure` (CNI Overlay) | **No** – preconfigured |
| Network plugin mode | `overlay` | **No** |
| Network dataplane | `cilium` | **No** |
| Network policy | `cilium` | **No** |
| Load balancer SKU | `standard` | **No** |
| API server VNet integration | Always enabled | **No** – preconfigured |
| Pod CIDR | Default `10.244.0.0/16` | **Yes** – `networkProfile.podCidr` |
| Service CIDR | Default `10.0.0.0/16` | **Yes** – `networkProfile.serviceCidr` |
| DNS service IP | Auto-assigned | **Yes** – `networkProfile.dnsServiceIP` |
| VNet | Managed (auto-created) | **Yes** – BYO VNet supported |
| Outbound type | `managedNATGateway` (managed VNet) | **Yes** – see [Egress](#egress) |
| ACNS | Optional | **Yes** – container network observability |
| Service mesh | Optional – Istio or BYO | **Yes** – `serviceMeshProfile` |

---

### Ingress

AKS Automatic supports multiple ingress patterns. In an ALZ Corp (private connectivity) scenario, **Application Gateway for Containers (AGC)** is the recommended L7 ingress, while **Application Routing (managed NGINX)** is preconfigured and always available. All options below can coexist on the same cluster.

> See [`docs/alz-corp-aks-automatic.drawio`](docs/alz-corp-aks-automatic.drawio) for a full architecture diagram showing traffic flows.

#### Option 1 – Application Gateway for Containers (recommended for Corp / ALZ)

AGC is the next-generation L7 load balancer for AKS. It replaces the legacy Application Gateway Ingress Controller (AGIC) and supports the **Kubernetes Gateway API** natively.

```
Corp User → ExpressRoute → VNet Peering → AGC Private Frontend (snet-agc) → ALB Controller → Pods
```

| Aspect | Detail |
|---|---|
| **AKS integration** | Deployed as an **AKS managed add-on** (required for AKS Automatic). No Helm install needed. |
| **Subnet** | Requires a dedicated subnet delegated to `Microsoft.ServiceNetworking/trafficControllers`. Minimum **/24**. |
| **Private ingress** | AGC frontends expose a private FQDN. In Corp scenarios, create a CNAME in the hub Private DNS Zone pointing to this FQDN. |
| **Gateway API** | Use `GatewayClass`, `Gateway`, and `HTTPRoute` CRDs. ALB Controller translates these to AGC configuration. |
| **Ingress API** | Also supports classic `Ingress` resources (useful for migration from AGIC). |
| **WAF** | Optional WAF policy can be attached to the AGC security policy resource. |
| **TLS termination** | SSL termination at the AGC frontend. Supports ECDSA + RSA certs, end-to-end SSL, and mTLS. |
| **Traffic splitting** | Weighted round-robin across backend services (canary / blue-green). |
| **Identity (RBAC)** | The `applicationloadbalancer-<cluster-name>` managed identity needs: `AppGw for Containers Configuration Manager` + `Network Contributor` + `Reader` on the MC resource group. The AKS add-on configures this automatically. |
| **Deployment modes** | **ALB-managed** (AGC lifecycle managed by ALB Controller via `ApplicationLoadBalancer` CRD) or **BYO** (AGC provisioned via Terraform/ARM, referenced in `Gateway` CRD). |

**Corp / Private connectivity considerations:**
- AGC private frontends do **not** require a public IP – traffic enters via ExpressRoute/VPN through hub and peering.
- DNS for the AGC frontend FQDN must resolve privately. Add a CNAME in the hub-linked **Private DNS Zone** pointing to the generated `*.appgw.azure.com` FQDN.
- The AGC association subnet must be in the **same VNet and region** as the AKS cluster.
- AGC operates **outside** the AKS data plane – it is a separate Azure resource in the spoke VNet.

#### Option 2 – Application Routing (managed NGINX) – preconfigured

```
Client → Azure Internal LB → managed NGINX Ingress Controller → K8s Services
```

| Feature | How to configure | Notes |
|---|---|---|
| **Basic ingress** | `Ingress` with `ingressClassName: webapprouting.kubernetes.azure.com` | Works out of the box, always enabled |
| **Automatic DNS** | `dns_zone_resource_ids` → `ingressProfile.webAppRouting.dnsZoneResourceIds` | Supports public + private DNS zones |
| **TLS certificates** | Annotate `Ingress` with `kubernetes.azure.com/tls-cert-keyvault-uri` | Fetches and rotates certs from Key Vault |
| **Internal-only** | Annotate the NGINX `Service` with `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` | Creates an internal LB for corp-only access |

**Corp considerations:** In private/corp deployments, configure the NGINX service as internal (no public LB). DNS records in the hub Private DNS Zone should point to the internal LB IP.

#### Option 3 – Istio Service Mesh Ingress Gateway (optional)

```
Client → Istio Ingress Gateway (Envoy) → VirtualService → K8s Services
```

| Component | Configuration |
|---|---|
| Enable | `serviceMeshProfile.mode = "Istio"` in the cluster body |
| Ingress gateway | `istio.components.ingressGateways[].enabled = true` |
| Gateway mode | `External` (public LB) or `Internal` (internal LB – use for Corp) |
| mTLS | `PeerAuthentication` CRDs post-deployment |
| Traffic management | `VirtualService`, `DestinationRule` CRDs |

**Corp considerations:** Set `mode: "Internal"` on the Istio ingress gateway for private-only access. When combined with UDR egress, ensure the hub firewall allows return traffic to the internal LB frontend.

#### Option 4 – BYO Ingress Controller (e.g., Traefik, HAProxy, Contour)

Deploy any ingress controller via Helm or manifests. AKS Automatic does not restrict third-party controllers. Ensure the controller's `Service` is annotated for an internal LB in corp scenarios.

#### Ingress Comparison

| | AGC | App Routing (NGINX) | Istio Gateway | BYO |
|---|---|---|---|---|
| **Preconfigured** | No (add-on) | **Yes** | No (opt-in) | No |
| **Gateway API** | ✅ native | ❌ | ✅ | Varies |
| **L7 features** | Full (WAF, mTLS, rewrites, splits) | Basic (host/path routing) | Advanced (traffic mgmt) | Varies |
| **Private frontend** | ✅ (private FQDN) | ✅ (internal LB annotation) | ✅ (internal mode) | ✅ |
| **ALZ Corp recommended** | **✅ Primary** | ✅ Simple workloads | ✅ Service mesh | ✅ |
| **Managed by** | Azure (AGC resource) | AKS (in-cluster) | AKS (in-cluster) | You |

---

### Egress

Egress (outbound connectivity) defines how pods reach the internet and external services. In an ALZ Corp deployment, the standard pattern is **UDR through the hub Azure Firewall**.

#### Managed VNet – Managed NAT Gateway (default, non-corp)

```
Pods → Node → Managed NAT Gateway (auto-created) → Internet
```

- **When:** `enable_byo_vnet = false`
- **Behaviour:** AKS creates and manages a NAT Gateway automatically.
- **Fine-tuning:** None – fully managed.
- **Not recommended for Corp** – egress is unfiltered, no centralised logging.

#### BYO VNet – User-Assigned NAT Gateway

```
Pods → Node (snet-aks-nodes) → NAT Gateway (your resource) → Public IP → Internet
```

- **When:** `enable_byo_vnet = true`, `egress_type = "userAssignedNATGateway"`
- **Resources created:** Public IP (`pip-natgw-*`) + NAT Gateway (`natgw-*`), associated to the node subnet.
- **Benefits:** Deterministic outbound IP, 64k SNAT ports per public IP, scalable (add more PIPs).
- **Fine-tuning:**
  - `nat_gateway_idle_timeout` – idle timeout (4–120 minutes)
  - Add additional public IPs post-deployment for more SNAT capacity
- **Corp note:** Provides static IPs for allowlisting but no centralised FQDN filtering. Combine with Cilium L7 policies or ACNS for in-cluster egress control.

#### BYO VNet – Load Balancer (dev/test only)

```
Pods → Node → AKS Standard Load Balancer (SNAT) → Internet
```

- **When:** `enable_byo_vnet = true`, `egress_type = "loadBalancer"`
- **Resources created:** None extra – AKS uses the Standard LB.
- **Trade-offs:** Fewer SNAT ports (~1k per node), no static outbound IP, risk of SNAT exhaustion under load.
- **Best for:** Dev/test environments only.

#### BYO VNet – User-Defined Routing / Forced Tunnelling (recommended for Corp / ALZ)

```
Pods → Node (snet-aks-nodes) → UDR (0.0.0.0/0 → 10.0.1.4) → Hub Azure Firewall → Internet
```

- **When:** `enable_byo_vnet = true`, `egress_type = "userDefinedRouting"`
- **Resources created:** Route Table (`rt-*`) with a default route to `firewall_private_ip`.
- **Requirements:**
  - An existing NVA/Azure Firewall with the [AKS required egress rules](https://learn.microsoft.com/azure/aks/outbound-rules-control-egress) whitelisted.
  - Set `var.firewall_private_ip` to the NVA's private IP.
- **Benefits:** Centralised egress filtering, compliance, DLP, full logging in Azure Firewall Diagnostics.

**Required outbound FQDNs (Azure Firewall `AzureKubernetesService` FQDN tag covers most):**

| FQDN / Endpoint | Port | Purpose |
|---|---|---|
| `*.hcp.<region>.azmk8s.io` | 443 | AKS API server communication |
| `mcr.microsoft.com` | 443 | Microsoft Container Registry (system images) |
| `*.data.mcr.microsoft.com` | 443 | MCR data endpoint |
| `management.azure.com` | 443 | Azure Resource Manager |
| `login.microsoftonline.com` | 443 | Entra ID authentication |
| `packages.microsoft.com` | 443 | OS packages (Azure Linux) |
| `acs-mirror.azurelinux.com` | 443 | Azure Linux package mirror |
| `dc.services.visualstudio.com` | 443 | Container Insights telemetry |
| `*.monitoring.azure.com` | 443 | Managed Prometheus metrics |
| `*.ods.opinsights.azure.com` | 443 | Log Analytics ingestion |
| `*.oms.opinsights.azure.com` | 443 | Log Analytics agent |

**Additional rules needed beyond the FQDN tag:**

| FQDN / Endpoint | Purpose |
|---|---|
| `<your-acr-name>.azurecr.io` | Application container images |
| Helm chart registries | Third-party charts |
| External APIs | Workload-specific outbound calls |
| `ghcr.io`, `docker.io` (if used) | Public registries |

**Azure Firewall sizing for AKS:**
- Minimum **20 frontend public IPs** in production to avoid SNAT port exhaustion.
- Use **Azure Firewall Premium** for TLS inspection if required by security policy.
- The route table is associated to the **node subnet only**. The API server subnet must **NOT** have a route table.

#### Egress Comparison

| | Managed NAT GW | User NAT GW | Load Balancer | UDR |
|---|---|---|---|---|
| **BYO VNet** | ❌ managed only | ✅ | ✅ | ✅ |
| **Static outbound IP** | ❌ | ✅ | ❌ | Via NVA |
| **SNAT ports** | High (auto) | 64k per PIP | Limited (~1k per node) | Via NVA |
| **Centralised filtering** | ❌ | ❌ | ❌ | ✅ |
| **Terraform variable** | (default) | `userAssignedNATGateway` | `loadBalancer` | `userDefinedRouting` |

---

### BYO VNet

Bring-Your-Own VNet gives you full control over the network topology, peering, DNS, and egress path.

#### Network Topology (Corp / ALZ)

> 📐 A detailed DrawIO diagram is available at [`docs/alz-corp-aks-automatic.drawio`](docs/alz-corp-aks-automatic.drawio)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Spoke VNet: 10.10.0.0/16   (peered to Hub VNet)                           │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  snet-aks-nodes: 10.10.0.0/22                                        │  │
│  │  ├── NSG (AKS manages rules)                                         │  │
│  │  ├── UDR → 10.0.1.4 (Hub Azure Firewall)                             │  │
│  │  │                                                                    │  │
│  │  │  ┌─ AKS Automatic ───────────────────────────────────────────┐     │  │
│  │  │  │  System Pool + Karpenter NodePools (Azure Linux)          │     │  │
│  │  │  │  App Routing (NGINX) | ALB Controller (AGC) | Istio       │     │  │
│  │  │  │  Pods (overlay: 10.244.0.0/16, svc: 10.245.0.0/16)      │     │  │
│  │  │  └───────────────────────────────────────────────────────────┘     │  │
│  │  │                                                                    │  │
│  │  Worker nodes placed here. Pod IPs from overlay, NOT this subnet.     │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  snet-aks-apiserver: 10.10.4.0/28                                     │  │
│  │  ├── Delegation: Microsoft.ContainerService/managedClusters           │  │
│  │  └── K8s API Server (private FQDN, VNet integrated)                   │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  snet-agc: 10.10.8.0/24                                               │  │
│  │  ├── Delegation: Microsoft.ServiceNetworking/trafficControllers       │  │
│  │  └── Application Gateway for Containers (private frontend)            │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │  snet-private-endpoints: 10.10.12.0/24                                │  │
│  │  └── Private Endpoints: ACR, Key Vault, Storage, SQL/CosmosDB         │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```
│  │  │                                                     │  │
│  │  API server VNet integration places the API server     │  │
│  │  endpoint in this subnet. Minimum /28.                 │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                             │
│  Overlay network (not visible in VNet):                     │
│    Pod CIDR:     10.244.0.0/16                              │
│    Service CIDR: 10.245.0.0/16                              │
│    DNS IP:       10.245.0.10                                │
└─────────────────────────────────────────────────────────────┘
```

#### Subnet Sizing Guidelines

| Subnet | Minimum | Recommended | Notes |
|---|---|---|---|
| **Node subnet** | /24 (254 nodes) | /22 (1,022 nodes) | One IP per node. Overlay means pods don't consume IPs here. |
| **API server subnet** | /28 (11 usable) | /28 | Only the API server endpoint lives here. /28 is sufficient. |
| **AGC subnet** | /24 (256 IPs) | /24 | Required by Application Gateway for Containers. Must be dedicated + delegated. |
| **Private endpoints subnet** | /24 | /24 | Hosts PEs for ACR, Key Vault, Storage, databases. |

#### Key Requirements

- The **API server subnet** MUST have a delegation to `Microsoft.ContainerService/managedClusters`.
- The **API server subnet** MUST NOT have a NAT Gateway or Route Table association.
- The **AGC subnet** MUST have a delegation to `Microsoft.ServiceNetworking/trafficControllers`.
- The **node subnet** SHOULD have an NSG (AKS injects required rules automatically) and a UDR (for Corp egress via hub firewall).
- All subnets must be in the same VNet and region as the AKS cluster.
- Ensure no CIDR overlaps between VNet address space, pod CIDR, service CIDR, hub VNet, and on-prem networks.

#### Switching Between Managed and BYO VNet

| Variable | Managed VNet | BYO VNet |
|---|---|---|
| `enable_byo_vnet` | `false` | `true` |
| `vnet_*`, `node_subnet_*`, `apiserver_subnet_*` | Ignored | Required |
| `egress_type` | Ignored (always `managedNATGateway`) | `userAssignedNATGateway` / `loadBalancer` / `userDefinedRouting` |
| `pod_cidr`, `service_cidr`, `dns_service_ip` | Optional | Recommended |

---

### Security

| Component | Setting | Fine-tunable? |
|---|---|---|
| Auth & authZ | Azure RBAC for Kubernetes | **No** – preconfigured, local accounts disabled |
| Workload Identity | Enabled (Entra Workload ID) | **No** – preconfigured |
| OIDC Issuer | Enabled | **No** – preconfigured |
| API server VNet integration | Enabled | **No** – preconfigured |
| Image Cleaner | Enabled (default 48h) | **Yes** – `image_cleaner_interval_hours` |
| Deployment Safeguards | Enabled via Azure Policy | **No** – preconfigured (Warning mode) |
| Defender for Containers | Optional | **Yes** – `securityProfile.defender` |
| Azure Key Vault KMS | Optional | **Yes** – `securityProfile.azureKeyVaultKms` |
| Custom CA trust certs | Optional (up to 10) | **Yes** – `securityProfile.customCATrustCertificates` |
| Private cluster | Optional | **Yes** – `enable_private_cluster` |
| Authorized IP ranges | Optional | **Yes** – `authorized_ip_ranges` |

### Monitoring & Observability

| Component | Default state | Fine-tunable? |
|---|---|---|
| Managed Prometheus | **Default** (enabled via CLI/Portal) | **Yes** – `enable_prometheus` |
| Container Insights | **Default** (enabled via CLI/Portal) | **Yes** – configurable |
| Azure Monitor Dashboards | Built-in via portal | **Yes** – link Managed Grafana |
| ACNS network observability | Optional | **Yes** – via `advancedNetworking` |
| Cost analysis | Optional | **Yes** – `metricsProfile.costAnalysis` |

### Auto-Upgrade & Maintenance

| Component | Setting | Fine-tunable? |
|---|---|---|
| Cluster auto-upgrade | **Preconfigured** – `stable` | **Yes** – `upgrade_channel` (`rapid`, `stable`, `patch`, `node-image`) |
| Node OS upgrade | **Preconfigured** – `NodeImage` | **Yes** – `node_os_upgrade_channel` (`NodeImage`, `SecurityPatch`, `Unmanaged`, `None`) |
| K8s API deprecation detection | Always on | **No** |
| Planned maintenance windows | **Default** – configurable | **Yes** – via `maintenanceConfigurations` |

### Scaling

| Component | Setting | Fine-tunable? |
|---|---|---|
| Node Autoprovisioning | Always on | **No** – core of Automatic |
| HPA | Enabled | **Yes** – per-deployment |
| KEDA | **Preconfigured** | **Yes** – `workloadAutoScalerProfile.keda` |
| VPA | **Preconfigured** | **Yes** – `workloadAutoScalerProfile.verticalPodAutoscaler` |
| Cluster autoscaler profile | Available | **Yes** – `autoScalerProfile.*` |

### Storage

| Component | Default | Fine-tunable? |
|---|---|---|
| Azure Disk CSI | Enabled | **Yes** – `storageProfile.diskCSIDriver` |
| Azure Files CSI | Enabled | **Yes** – `storageProfile.fileCSIDriver` |
| Azure Blob CSI | Disabled | **Yes** – `storageProfile.blobCSIDriver` |
| Snapshot controller | Enabled | **Yes** – `storageProfile.snapshotController` |

### Policy Enforcement

| Component | Setting | Fine-tunable? |
|---|---|---|
| Deployment Safeguards | **Preconfigured** – Warning mode | Severity changeable to `Enforcement` |
| Custom Azure Policies | Optional | **Yes** |
| Managed namespaces | Optional | **Yes** |

---

## What Is Preconfigured vs. What You Can Fine-Tune

### 🔒 Preconfigured (cannot be changed)

- Node Autoprovisioning mode = `Auto`
- Azure Linux node OS
- Azure CNI Overlay + Cilium networking stack
- Azure RBAC for Kubernetes authorization (local accounts disabled)
- Workload Identity + OIDC Issuer
- API server VNet integration
- Image Cleaner
- Deployment Safeguards (Azure Policy)
- Managed NAT Gateway (on managed VNet)
- Application Routing (managed NGINX)
- Node auto-repair
- Standard tier with uptime SLA
- ReadOnly node resource group lockdown
- K8s API deprecation detection on upgrade

### 🔧 Fine-tunable

| Category | What you can tune |
|---|---|
| **Kubernetes version** | `kubernetes_version` |
| **Upgrade channels** | `upgrade_channel`, `node_os_upgrade_channel` |
| **Maintenance windows** | Via `maintenanceConfigurations` |
| **Networking** | BYO VNet, pod/service CIDRs, DNS service IP |
| **Egress** | NAT Gateway, Load Balancer, or UDR (BYO VNet only) |
| **Ingress** | DNS zones for Application Routing, Istio service mesh |
| **Private cluster** | `enable_private_cluster`, `authorized_ip_ranges` |
| **Monitoring** | Prometheus, Container Insights, Managed Grafana |
| **Scaling** | KEDA, VPA, HPA, autoscaler profile |
| **Storage** | Disk/File/Blob CSI drivers, snapshot controller |
| **Security** | Defender, Key Vault KMS, CA trust certs, image cleaner interval |
| **Node customization** | Via Karpenter `NodePool` / `AKSNodeClass` CRDs post-deployment |

---

## Terraform Project Structure

```
aks-automatic-azapi/
├── terraform.tf              # Terraform block, required providers, provider config
├── data.tf                   # Data sources (client config, subscription)
├── locals.tf                 # Computed values, conditional logic
├── variables.tf              # All input variables (general, network, ingress, egress, security)
├── network.tf                # BYO VNet: VNet, subnets, NSG, NAT Gateway, route table
├── main.tf                   # Resource group + AKS Automatic cluster (azapi)
├── outputs.tf                # All outputs (cluster, networking, resource group)
├── terraform.tfvars.example  # Example variable values for common scenarios
└── README.md                 # This file
```

| File | Responsibility |
|---|---|
| `terraform.tf` | Terraform version constraint, `azapi` + `azurerm` provider declarations |
| `data.tf` | Read-only data sources for Azure context (subscription ID, tenant ID) |
| `locals.tf` | Derived values – network conditionals, subnet IDs, outbound type |
| `variables.tf` | All configurable inputs with descriptions, types, defaults, and validations |
| `network.tf` | All BYO VNet resources (conditionally created when `enable_byo_vnet = true`) |
| `main.tf` | Resource group (`azapi`) + AKS Automatic cluster (`azapi`) |
| `outputs.tf` | Exported values for downstream consumption (FQDN, OIDC URL, subnet IDs) |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` and customise for your environment |

### Why azapi?

The `azapi` provider talks directly to the Azure Resource Manager REST API:

- **Day-zero support** for new API versions and preview features
- No waiting for `azurerm` to add support for new AKS properties
- Full control over the JSON body sent to ARM
- Ideal for AKS Automatic which uses the newer `sku.name = "Automatic"` property

---

## Deployment Scenarios

### Prerequisites

- Terraform >= 1.9
- Azure CLI authenticated (`az login`)
- Subscription quota for ≥16 vCPUs of D-series VMs in the target region
- Target region must support [API Server VNet Integration](https://learn.microsoft.com/azure/aks/api-server-vnet-integration) (GA)
- Register `Microsoft.PolicyInsights` resource provider

### Quick Start

```bash
# Copy and customise variables
cp terraform.tfvars.example terraform.tfvars

# Initialise providers
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Deploy
terraform apply
```

### Scenario 1 – BYO VNet + NAT Gateway (production recommended)

```hcl
enable_byo_vnet = true
egress_type     = "userAssignedNATGateway"
```

### Scenario 2 – BYO VNet + UDR / Firewall (enterprise)

```hcl
enable_byo_vnet     = true
egress_type         = "userDefinedRouting"
firewall_private_ip = "10.10.8.4"
```

### Scenario 3 – Managed VNet (simplest)

```hcl
enable_byo_vnet = false
```

### Scenario 4 – Private cluster

```hcl
enable_byo_vnet        = true
enable_private_cluster = true
```

### Scenario 5 – Application Routing with Azure DNS

```hcl
dns_zone_resource_ids = [
  "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/dnsZones/example.com"
]
```

### Connect to the cluster

```bash
az aks get-credentials \
  --resource-group rg-aks-automatic \
  --name aks-automatic

kubectl get nodes
```

---

## Regional Availability & Limitations

- AKS Automatic requires regions with **≥3 availability zones**, **ephemeral OS disk** support, and **Azure Linux** support.
- Must be a region where **API Server VNet Integration** is GA.
- System node pool VM size is dynamically selected – ensure quota for at least one of: `Standard_D4lds_v5`, `Standard_D4ads_v5`, `Standard_D4ds_v5`, `Standard_D4d_v5`, `Standard_DS3_v2`.
- **Windows node pools** are not supported.
- The node resource group is always **ReadOnly**.

---

## References

- [What is AKS Automatic?](https://learn.microsoft.com/azure/aks/intro-aks-automatic)
- [Quickstart: Create an AKS Automatic cluster](https://learn.microsoft.com/azure/aks/learn/quick-kubernetes-automatic-deploy)
- [AKS Automatic with custom VNet](https://learn.microsoft.com/azure/aks/automatic/quick-automatic-custom-network)
- [AKS Automatic private cluster](https://learn.microsoft.com/azure/aks/automatic/quick-automatic-private-custom-network)
- [AKS REST API – Managed Clusters](https://learn.microsoft.com/rest/api/aks/managed-clusters/create-or-update)
- [azapi provider](https://registry.terraform.io/providers/azure/azapi/latest/docs)
- [Node Autoprovisioning](https://learn.microsoft.com/azure/aks/node-autoprovision)
- [Azure CNI Overlay with Cilium](https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium)
- [Application Routing add-on](https://learn.microsoft.com/azure/aks/app-routing)
- [AKS egress control](https://learn.microsoft.com/azure/aks/outbound-rules-control-egress)
- [API Server VNet Integration](https://learn.microsoft.com/azure/aks/api-server-vnet-integration)
