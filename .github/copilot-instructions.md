# Copilot Instructions – AKS Automatic (azapi)

## What this repo is

A Terraform root module that deploys an **AKS Automatic** cluster using the **azapi provider** exclusively for all Azure resources. The azurerm provider is present only for data sources (`data.azurerm_client_config`, `data.azurerm_subscription`).

## Commands

```bash
terraform init              # Download providers
terraform validate          # Syntax + type check (run after every change)
terraform fmt -recursive    # Format all .tf files
terraform plan              # Preview changes (requires Azure auth)
terraform apply             # Deploy (requires Azure auth)
```

## Documentation Sources

Always fetch the latest documentation from official sources before making claims about AKS Automatic features, limitations, or regional availability. Do not rely on training data or cached knowledge.

Key sources to validate against:
- [AKS Automatic overview](https://learn.microsoft.com/azure/aks/intro-aks-automatic)
- [API Server VNet Integration](https://learn.microsoft.com/azure/aks/api-server-vnet-integration)
- [Private AKS clusters](https://learn.microsoft.com/azure/aks/private-clusters)
- [NAP limitations](https://learn.microsoft.com/azure/aks/node-auto-provisioning)
- [AKS outbound rules](https://learn.microsoft.com/azure/aks/outbound-rules-control-egress)
- [AGC components](https://learn.microsoft.com/azure/application-gateway/for-containers/application-gateway-for-containers-components)
- [Application Routing add-on](https://learn.microsoft.com/azure/aks/app-routing)
- [Azure Products by Region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/)

Use the `azure-mcp-documentation` MCP tool with `microsoft_docs_fetch` to retrieve current page content when validating claims.

No test framework is configured. Validate changes with `terraform validate`. Always run `terraform validate` after any code modification before committing.

## Architecture

The module supports three networking modes controlled by `var.enable_byo_vnet` and the external subnet ID variables:

- **External subnets (`enable_byo_vnet = false` with external subnet IDs, default / recommended for Corp):** the ALZ vending pipeline pre-provisions the spoke VNet, subnets, peering, NSG, and UDR. `network.tf` is skipped, `dependencies.tf` creates ACR/Key Vault/private endpoints/RBAC, and `main.tf` passes the supplied subnet IDs to AKS.
- **Module-created VNet (`enable_byo_vnet = true` without external subnet IDs):** `network.tf` creates the spoke VNet, node subnet, API server subnet, optional PE subnet, NSG, and UDR resources needed by the cluster.
- **AKS-managed networking (`enable_byo_vnet = false` without external subnet IDs):** all resources in `network.tf` and the PE subnet are skipped, and AKS manages its own virtual network resources.

The conditional logic lives in `locals.tf` (`create_network`, `create_route_table`, `create_pe_subnet`). These booleans drive `count` on the resources in `network.tf` and `dependencies.tf`, and feed into `main.tf` via `local.node_subnet_id`, `local.apiserver_subnet_id`, `local.pe_subnet_id`, and `local.outbound_type`.

### Key resource: the AKS cluster (`main.tf`)

`azapi_resource.aks` sends a single ARM PUT to `Microsoft.ContainerService/managedClusters`. The critical settings that make this an Automatic cluster (vs Standard) are:

- `sku.name = "Automatic"` (not `"Base"`)
- `sku.tier = "Standard"`
- `nodeProvisioningProfile.mode = "Auto"`

Many properties in the body are **preconfigured by AKS Automatic** and cannot be changed (Azure RBAC, Cilium, CNI Overlay, workload identity, OIDC, image cleaner, deployment safeguards). They are set explicitly so the ARM payload is declarative and complete. See the README's "Preconfigured vs Fine-tunable" section for the full list.

---

## Ingress considerations

Application Routing (managed NGINX) is preconfigured and always enabled. It currently uses Kubernetes `Ingress` resources with `ingressClassName: webapprouting.kubernetes.azure.com`. Upstream Ingress NGINX maintenance ended in March 2026, and Microsoft provides security fixes for the AKS add-on through November 2026 while AKS migrates toward Gateway API-aligned ingress. Key points when modifying ingress configuration:

- `ingressProfile.webAppRouting.dnsZoneResourceIds` accepts both public (`Microsoft.Network/dnsZones`) and private (`Microsoft.Network/privateDnsZones`) zone IDs. When integrating with ALZ hub-spoke, use **private DNS zones hosted in the connectivity subscription** – pass their full resource IDs.
- The managed NGINX controller needs the AKS managed identity to have `Private DNS Zone Contributor` on referenced private zones and `DNS Zone Contributor` on referenced public zones. This RBAC assignment is **not managed by this module** – it must be granted externally (e.g., by the ALZ platform team or a separate Terraform config).
- TLS certificates from Azure Key Vault are consumed via `kubernetes.azure.com/tls-cert-keyvault-uri` annotations on `Ingress` resources, not via the ARM body. The cluster's managed identity needs `Key Vault Certificate User` on the vault.
- Istio ingress gateway (`serviceMeshProfile`) creates an additional Azure Load Balancer. When using UDR egress, ensure the firewall allows return traffic to the LB frontend IP.

## Egress considerations

Egress type is the single most impactful networking decision. Caveats per option:

### User-Defined Routing / Firewall (`userDefinedRouting`)
- `var.firewall_private_ip` must be set. The module creates a route table with `0.0.0.0/0 → VirtualAppliance` when it owns the VNet; in vending mode the UDR is expected to be pre-associated to the node subnet.
- The firewall/NVA **must** whitelist all [AKS required outbound FQDNs](https://learn.microsoft.com/azure/aks/outbound-rules-control-egress). Azure Firewall can use the built-in `AzureKubernetesService` FQDN tag.
- Required outbound endpoints include: `mcr.microsoft.com`, `*.data.mcr.microsoft.com`, `mcr-0001.mcr-msedge.net`, management.azure.com, `login.microsoftonline.com`, `packages.microsoft.com`, `acs-mirror.azureedge.net`. Add `*.hcp.<region>.azmk8s.io` only for non-private clusters; private clusters do not require it.
- For Azure Firewall: use a minimum of **20 frontend IPs** in production to avoid SNAT port exhaustion.
- The route table is associated to the node subnet only. The API server subnet must **not** have a route table.
- When Istio ingress is enabled alongside UDR, ensure the firewall allows inbound return traffic to the Istio LB frontend.

### Load Balancer (`loadBalancer`)
- No additional resources are created. AKS uses the Standard LB for SNAT.
- Offers fewer SNAT ports (~1k per node) and no static outbound IP.
- Suitable for dev/test only. Not recommended when the cluster runs workloads making many concurrent outbound connections.

---

## Azure Landing Zone (ALZ) integration – caveats and considerations

This module is designed to deploy into a **spoke subscription** within an Azure Landing Zone that uses [Azure Verified Modules (AVM) for Platform Landing Zones](https://aka.ms/alz/acc/tf). The following caveats apply:

### VNet and subnet ownership

- In ALZ, the **connectivity subscription** typically owns the hub VNet and the platform team manages VNet peering. For Corp, the recommended pattern is to consume spoke subnets pre-provisioned by the vending pipeline: set `enable_byo_vnet = false` and pass `external_node_subnet_id`, `external_apiserver_subnet_id`, and `external_pe_subnet_id`.
- If you are not using vending, set `enable_byo_vnet = true` so `network.tf` creates the spoke VNet and required subnets in this state. This module does not create hub peering resources.

### CIDR coordination with the ALZ IP plan

- ALZ enforces a central IP address management (IPAM) plan. The VNet address space (`10.10.0.0/16`), pod CIDR (`10.244.0.0/16`), and service CIDR (`10.245.0.0/16`) **must not overlap** with:
  - The hub VNet CIDR (typically `10.0.0.0/16` or similar)
  - Other spoke VNets
  - On-premises networks connected via ExpressRoute/VPN
  - Other AKS clusters' overlay CIDRs if they share DNS or service mesh
- Always coordinate CIDR ranges with the ALZ platform team before deployment. Update `variables.tf` defaults to match the allocated ranges.

### DNS – Private DNS zones

- AKS Automatic always uses API Server VNet Integration. The API server is an ILB in the delegated subnet, not a Private Endpoint. When `enable_private_cluster = true`, the FQDN becomes `<cluster>-<hash>.private.<region>.azmk8s.io` (note: `private.`, not `privatelink.` -- the `privatelink.` zone is the legacy non-VNet-integrated model). This requires a `private.<region>.azmk8s.io` Private DNS Zone linked to the hub VNet. Without private cluster, no Private DNS Zone is needed for API server access.
- In ALZ, Private DNS Zones are typically hosted in the **connectivity subscription** and managed by the platform team. Do **not** create duplicate Private DNS Zones in the spoke.
- For Application Routing DNS integration, the `dns_zone_resource_ids` variable must point to zones the platform team has pre-created. The AKS managed identity needs `Private DNS Zone Contributor` on private zones and `DNS Zone Contributor` on public zones – this is a **cross-subscription RBAC assignment** that must be handled by the ALZ platform team or a separate Terraform state.

### Egress through hub firewall (UDR)

- The standard ALZ pattern routes all spoke egress through the hub Azure Firewall via UDR. Set `egress_type = "userDefinedRouting"` and `firewall_private_ip` to the hub firewall's private IP.
- The ALZ firewall policy must include rules for AKS required outbound FQDNs. The `AzureKubernetesService` FQDN tag on Azure Firewall covers most requirements, but additional rules may be needed for:
  - Container image registries (ACR, Docker Hub, etc.)
  - Helm chart repositories
  - External APIs consumed by workloads
  - OS package repositories for Azure Linux (`packages.microsoft.com`, `acs-mirror.azureedge.net`, `mcr-0001.mcr-msedge.net`)
- If the ALZ uses **NVA** instead of Azure Firewall, the `AzureKubernetesService` FQDN tag is not available — you must whitelist each FQDN individually.

### Policy conflicts

- ALZ assigns Azure Policies at the management group level. AKS Automatic **preconfigures Deployment Safeguards** which internally uses Azure Policy. If the ALZ assigns conflicting policies (e.g., requiring a different network plugin, denying public IPs, or mandating specific tags), the cluster creation may fail.
- Common conflicts:
  - `Kubernetes clusters should not allow container privilege escalation` — may conflict with system components.
  - `Kubernetes cluster should not allow privileged containers` — AKS system pods may need privileges.
  - `Network policies should be enforced on AKS clusters` — already enforced by Cilium, but the policy may not recognise this.
  - Policies enforcing specific NSG rules on subnets — AKS injects its own NSG rules which may violate strict NSG policies.
- Audit the ALZ policy assignments **before** deploying. Use `az policy assignment list --scope /subscriptions/<id>` or the ALZ management group scope.

### azapi vs AVM module compatibility

- This module uses `azapi_resource` for all Azure resources. [AVM modules](https://registry.terraform.io/namespaces/Azure) use `azurerm_*` resources. Do **not** mix `azapi_resource` and `azurerm_*` for the **same resource** (e.g., don't create the AKS cluster with azapi and then try to manage it with `azurerm_kubernetes_cluster` in another config) — this causes state conflicts and drift.
- If integrating with AVM-managed resources (e.g., an AVM-provisioned VNet or Key Vault), reference them via **data sources** or **resource IDs passed as variables**, never by importing them into this state.
- When the ALZ platform team uses the [AVM Platform Landing Zone module](https://registry.terraform.io/modules/Azure/avm-ptn-alz/azurerm/latest), coordinate output values: the hub firewall IP, VNet peering resource IDs, Private DNS zone IDs, and Log Analytics workspace ID are typically exposed as outputs from that module.

### Monitoring integration

- ALZ typically deploys a central **Log Analytics workspace** in the management subscription. To send AKS Container Insights and Prometheus data to the central workspace, you must add the workspace resource ID to the cluster's `azureMonitorProfile` or `addonProfiles` — this is not yet wired in this module. Extend `main.tf` if centralised logging is required.

### RBAC and identity

- AKS Automatic enforces Azure RBAC for Kubernetes (`aadProfile.enableAzureRBAC = true`, local accounts disabled). In ALZ, Kubernetes RBAC role assignments should be managed through the ALZ **identity subscription** or via PIM-eligible role assignments.
- The AKS cluster's SystemAssigned managed identity needs:
  - `Network Contributor` on the BYO VNet/subnets (for node provisioning).
  - `Private DNS Zone Contributor` on any private DNS zones referenced in Application Routing.
  - `DNS Zone Contributor` on any public DNS zones referenced in Application Routing.
  - `Key Vault Certificate User` on any Key Vault used for TLS certs.
- These cross-subscription RBAC assignments are **not created by this module** and must be managed separately.

---

## Conventions

### azapi-only resources

All Azure resources use `azapi_resource`. Do **not** introduce `azurerm_*` resources. When adding new Azure resources:

1. Find the ARM resource type and latest stable API version.
2. Use `azapi_resource` with HCL `body = { ... }` syntax (not `jsonencode`).
3. Use `null` for optional properties that should be omitted — azapi strips nulls automatically.

### File layout

| File | Contains |
|---|---|
| `terraform.tf` | `terraform {}` block, provider declarations |
| `data.tf` | Data sources only |
| `locals.tf` | All computed/derived values |
| `variables.tf` | All input variables, grouped by section with `# ====` headers |
| `network.tf` | Module-created VNet resources (only when `enable_byo_vnet = true` and no external subnet IDs are supplied) |
| `dependencies.tf` | ACR, Key Vault, private endpoints, private DNS zone groups, and RBAC |
| `main.tf` | Resource group + AKS cluster |
| `outputs.tf` | All outputs |

New resources go in the file matching their category. Don't create new `.tf` files unless adding a genuinely separate concern (e.g., a monitoring workspace).

### Variable style

- Every variable has `description`, `type`, and `default`.
- Use `validation {}` blocks for enums (see `egress_type`, `upgrade_channel`).
- Nullable variables (e.g., `firewall_private_ip`) use `default = null`.
- Use `lifecycle.precondition` for cross-variable constraints that Terraform's `validation` blocks can't express.

### Conditional resource creation

All conditional resources use `count` (not `for_each`) with boolean locals from `locals.tf`. The pattern is:

```hcl
count = local.create_route_table ? 1 : 0
```

Reference these resources with `[0]` indexing inside ternaries guarded by the same boolean, or use `try(..., null)` in outputs.

### ARM body structure

The `body` block in `azapi_resource.aks` mirrors the ARM REST API structure exactly (`sku`, `properties.networkProfile`, etc.). Use **camelCase** for ARM property names inside `body`. Keep properties grouped by concern with `# -----` comment separators matching the README sections.

### Tags

All resources receive `local.tags`. Don't hardcode tags on individual resources — pass them through the local.

## Validation Checklist

Before committing changes, run the following:

1. `terraform init && terraform validate` — all code changes must pass
2. `terraform fmt -check -recursive` — formatting must be consistent
3. Verify Mermaid diagram in README.md renders correctly on GitHub (no stale AGC flows, correct DNS zone format, Corp ingress via App Routing internal LB)
4. Verify DrawIO source (`docs/alz-corp-aks-automatic.drawio`) and SVG (`docs/alz-corp-aks-automatic.drawio.svg`) are consistent with README content
5. Validate all claims against current Microsoft Learn documentation using the azure-mcp-documentation tool — do not rely on cached knowledge for AKS Automatic features, limitations, or regional availability
6. Check that RBAC role assignments use the correct identity (kubelet for AcrPull, App Routing add-on for Key Vault Certificate User, cluster identity for Network Contributor)
7. Confirm Private DNS Zone format is `private.<region>.azmk8s.io` for VNet-integrated clusters (not `privatelink.`)
8. Ensure no NAT Gateway resources or variables remain in the Terraform code (Corp = hub firewall egress only)
9. Verify egress FQDN list matches current AKS outbound rules documentation
10. Cross-check the regional availability matrix against the Azure Products by Region page
