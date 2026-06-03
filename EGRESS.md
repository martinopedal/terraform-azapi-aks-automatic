# Network egress requirements

These egress FQDNs must be opened at the hub Azure Firewall for force-tunneled spokes; canonical source: alz-firewall-ops/FIREWALL-EGRESS-IMPLEMENTED.md.

Scope: AKS Automatic/Base + Node Auto Provisioning clusters using `egress_type = "userDefinedRouting"` with `0.0.0.0/0` routed to the hub firewall. If the firewall/NVA cannot use Azure Firewall's `AzureKubernetesService` FQDN tag, open the explicit FQDNs below.

| FQDN | Port/proto | Why | Originally missed? |
|---|---|---|---|
| `*.hcp.<region>.azmk8s.io` | TCP 443 | AKS regional API server/control-plane endpoint. In this estate, use `*.hcp.swedencentral.azmk8s.io`. | No |
| `*.tun.<region>.azmk8s.io` | TCP 443, TCP 9000, UDP 1194 | AKS konnectivity/tunnel path. In this estate, use `*.tun.swedencentral.azmk8s.io`. | No |
| `packages.aks.azure.com` | TCP 443 | AKS node packages and bootstrap dependencies. | Yes |
| `acs-mirror.azureedge.net` | TCP 443 | AKS component image/package mirror. | Yes |
| `mcr.microsoft.com` | TCP 443 | Microsoft Container Registry for system container images. | Yes |
| `*.data.mcr.microsoft.com` | TCP 443 | MCR image layer/data endpoint. | Yes |
| `*.cdn.mscr.io` | TCP 443 | MCR legacy CDN edge. | Yes |
| `mcr-0001.mcr-msedge.net` | TCP 443 | MCR Edge CDN used by AKS node bootstrap. | Yes |
| `*.azurecr.io` | TCP 443 | Azure Container Registry image pulls for workload and platform images. | No |
| `*.data.azurecr.io` | TCP 443 | ACR image layer/data endpoint. | No |
| `packages.microsoft.com` | TCP 443 | Microsoft Linux packages used during node/tool bootstrap. | Yes |
| `archive.ubuntu.com` | TCP 80, TCP 443 | Ubuntu apt repository for node/tool package install paths. | Yes |
| `security.ubuntu.com` | TCP 80, TCP 443 | Ubuntu security update repository. | Yes |
| `azure.archive.ubuntu.com` | TCP 80, TCP 443 | Azure-hosted Ubuntu package mirror. | Yes |
| `*.ubuntu.com` | TCP 80, TCP 443 | Ubuntu subdomains used by package/changelog/NTP paths. | Yes |
| `management.azure.com` | TCP 443 | Azure Resource Manager control-plane calls from AKS integrations and automation. | No |
| `login.microsoftonline.com` | TCP 443 | Entra ID authentication and managed identity token acquisition. | No |
| `*.login.microsoftonline.com` | TCP 443 | Regional Entra ID endpoints. | No |
| `graph.microsoft.com` | TCP 443 | Microsoft Graph identity/group lookups used by automation and providers. | No |
| `registry.k8s.io` | TCP 443 | Kubernetes container images for add-ons and tooling. | No |
| `charts.jetstack.io` | TCP 443 | cert-manager Helm chart repository, when deployed. | No |
| `prometheus-community.github.io` | TCP 443 | Prometheus Helm chart repository, when deployed. | No |
| `grafana.github.io` | TCP 443 | Grafana Helm chart repository, when deployed. | No |
| `kubernetes.github.io` | TCP 443 | Kubernetes project Helm chart repository, when deployed. | No |
| `get.helm.sh` | TCP 443 | Helm binary installer. | No |
| `*.helm.sh` | TCP 443 | Helm subdomains. | No |
| `*` | UDP 123 | NTP time sync for AKS nodes. Firewall implementation uses a UDP/123 network rule rather than FQDN filtering. | Yes |

## Notes

- Azure Firewall's `AzureKubernetesService` FQDN tag covers most AKS system egress, but this estate still needed explicit MCR, AKS package, package mirror, ARM/login/Graph, and NTP openings for force-tunneled spokes.
- Private clusters do not require public API server access from clients, but nodes still need AKS management, image registry, package, and time-sync egress during provisioning and scale-out.
