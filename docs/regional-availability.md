# Regional Availability and Limitations

### Region Requirements

AKS Automatic clusters require all of the following in the target region:

- 3 or more availability zones
- Ephemeral OS disk support
- Azure Linux OS support
- API Server VNet Integration at GA

API Server VNet Integration is GA in all public cloud regions except `qatarcentral`. Both **Norway East** and **Sweden Central** meet the core AKS Automatic requirements.

### Feature and Dependency Availability Matrix (Norway East / Sweden Central)

The table below covers AKS Automatic and all its dependencies referenced in this module. Status is based on official Microsoft documentation as of March 2026. Verify current availability at the [Azure Products by Region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/) page before deployment.

| Feature / Dependency | Norway East | Sweden Central | Status | Notes |
|---|---|---|---|---|
| **AKS (general)** | ✅ | ✅ | GA | |
| **AKS Automatic (SKU)** | ✅ | ✅ | GA | Requires 3 AZs + VNet integration |
| **API Server VNet Integration** | ✅ | ✅ | GA | GA in all public regions except qatarcentral |
| **Availability Zones (3+)** | ✅ | ✅ | GA | Both regions have 3 AZs |
| **Azure CNI Overlay + Cilium** | ✅ | ✅ | GA | Preconfigured in Automatic |
| **Node Autoprovisioning (NAP/Karpenter)** | ✅ | ✅ | GA | Preconfigured in Automatic |
| **Application Routing add-on (NGINX)** | ✅ | ✅ | GA | Preconfigured in Automatic |
| **Application Gateway for Containers** | ✅ | ❌ | GA (limited regions) | [AGC region list](https://learn.microsoft.com/azure/application-gateway/for-containers/overview#supported-regions) includes Norway East but not Sweden Central |
| **AGC AKS add-on on Automatic** | ❌ | ❌ | Not yet supported | Add-on not available on AKS Automatic clusters |
| **AGC private IP frontend** | ❌ | ❌ | Not yet supported | Public FQDN only. Private IP in development |
| **Istio service mesh add-on** | ✅ | ✅ | GA | Available in all AKS regions |
| **Managed Prometheus (Azure Monitor workspace)** | ✅ | ✅ | GA | [Workspace regions](https://learn.microsoft.com/azure/azure-monitor/essentials/prometheus-metrics-overview) include both |
| **Container Insights** | ✅ | ✅ | GA | |
| **Azure Monitor Dashboards (built-in Grafana)** | ✅ | ✅ | GA | Portal-embedded, no separate resource |
| **Managed Grafana** | Verify | Verify | GA (expanding) | Check [Products by Region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/). Can be deployed in a different region from the cluster if needed. |
| **ACNS (Container Network Observability)** | ✅ | ✅ | GA | Works with Cilium dataplane |
| **ACNS (WireGuard encryption)** | ✅ | ✅ | Preview | |
| **ACNS (eBPF Host Routing)** | ✅ | ✅ | Preview | |
| **Azure Firewall** | ✅ | ✅ | GA | Required for UDR egress pattern |
| **NAT Gateway** | ✅ | ✅ | GA | |
| **Azure Key Vault** | ✅ | ✅ | GA | TLS certs for App Routing |
| **Azure Container Registry** | ✅ | ✅ | GA | |
| **Azure Private DNS Zones** | ✅ | ✅ | GA | |
| **AVNM IPAM** | ✅ | ✅ | GA | [AVNM region list](https://learn.microsoft.com/azure/virtual-network-manager/overview) |
| **Workload Identity (Entra Workload ID)** | ✅ | ✅ | GA | Preconfigured in Automatic |
| **Defender for Containers** | ✅ | ✅ | GA | Optional |
| **Azure Policy (Deployment Safeguards)** | ✅ | ✅ | GA | Preconfigured in Automatic |

**Key takeaway for Sweden Central:** Application Gateway for Containers is not available in Sweden Central. If AGC is required (once private IP ships and the Automatic add-on becomes available), deploy in Norway East or another supported region. All other AKS Automatic dependencies are available in both regions.

### Operational Limitations (NAP/Karpenter)

These limitations apply to all AKS Automatic clusters because NAP (Node Autoprovisioning) is mandatory:

| Limitation | Impact | Source |
|---|---|---|
| **Cannot stop/deallocate the cluster** | `az aks stop` is not supported. The cluster always incurs compute charges. No pause capability for dev/test cost savings. | [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning#limitations-and-unsupported-features) |
| **Cannot change egress outbound type after creation** | The egress strategy (NAT GW, UDR, LB) must be decided at deployment time. No migration path between egress types post-creation. | [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning#limitations-and-unsupported-features) |
| **Windows node pools not supported** | Linux-only (Azure Linux). No Windows container workloads. | [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning#limitations-and-unsupported-features) |
| **IPv6 not supported** | Dual-stack and IPv6-only clusters are not available. | [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning#limitations-and-unsupported-features) |
| **Service principals not supported** | Only managed identities (system-assigned or user-assigned). Legacy SP-based authentication will not work. | [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning#limitations-and-unsupported-features) |
| **Cluster autoscaler cannot coexist** | NAP replaces the cluster autoscaler. Manual node pools with CAS cannot be added alongside NAP. | [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning#limitations-and-unsupported-features) |
| **Standard Load Balancer required** | Basic LB is not supported with NAP. This is already enforced by AKS Automatic configuration. | [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning#limitations-and-unsupported-features) |
| **VNet Encryption not supported** | API Server VNet Integration is incompatible with VNet Encryption on v4+ node SKUs. | [VNet Integration limitations](https://learn.microsoft.com/azure/aks/api-server-vnet-integration#limitations) |
| **Node resource group is ReadOnly** | Cannot create or modify resources in the MC_ resource group. | Preconfigured in AKS Automatic |

### Azure Linux 2.0 Deprecation

AKS no longer provides security updates for Azure Linux 2.0 since November 30, 2025. Node images will be removed on March 31, 2026. AKS Automatic clusters must run a Kubernetes version that uses AzureLinux3. Verify your cluster's node image version and upgrade if necessary. See [AKS release notes](https://github.com/Azure/AKS/releases).

### Monitoring Considerations

AKS Automatic configures the following monitoring stack by default (when created via CLI or Portal):

| Component | Default behaviour | Notes |
|---|---|---|
| Managed Prometheus | Enabled | Metrics collection for cluster and workload health |
| Container Insights | Enabled | Log collection to Log Analytics |
| Azure Monitor Dashboards with Grafana | Built-in (portal) | Pre-built Grafana-style dashboards embedded in the Azure portal. This is **not** a full Managed Grafana workspace. |
| Managed Grafana | **Optional** (not default) | Requires separate provisioning. Enables custom dashboards, alerting rules, and data source integration beyond the built-in portal views. |

**AMBA (Azure Monitor Baseline Alerts) considerations:**

- AMBA alert templates target classic Azure Monitor metric and log alerts. AKS Automatic uses Managed Prometheus, which uses **Prometheus-style recording and alerting rules**, not Azure Monitor metric alerts. AMBA templates may not align directly with the Prometheus-based metrics pipeline.
- If the ALZ platform deploys AMBA, review whether the AKS alert rules in AMBA are compatible with the Managed Prometheus data source. You may need to supplement or replace AMBA rules with Prometheus alert rules (PrometheusRuleGroups) configured in the Azure Monitor workspace.
- Data Collection Rules (DCRs) for Prometheus must be regionally co-located with the Azure Monitor workspace. Multi-region deployments require separate DCRs per region.
- The built-in Azure Monitor Dashboards provide baseline visibility without requiring Managed Grafana. For ALZ environments that standardise on Managed Grafana for observability, provision a Managed Grafana workspace separately and link it to the Managed Prometheus and Log Analytics data sources.

### VM Quota

AKS Automatic dynamically selects the system node pool VM size. Ensure the subscription has quota for at least 16 vCPUs of one of the following in the target region: `Standard_D4lds_v5`, `Standard_D4ads_v5`, `Standard_D4ds_v5`, `Standard_D4d_v5`, `Standard_DS3_v2`.
