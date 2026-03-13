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

No test framework is configured. Validate changes with `terraform validate`. Always run `terraform validate` after any code modification before committing.

## Architecture

The module has two modes controlled by `var.enable_byo_vnet`:

- **BYO VNet (`true`, default):** `network.tf` creates VNet, two subnets (node + API server with delegation), NSG, and egress resources. The egress path is selected by `var.egress_type` which conditionally creates a NAT Gateway + Public IP (`userAssignedNATGateway`), a Route Table (`userDefinedRouting`), or nothing extra (`loadBalancer`).
- **Managed VNet (`false`):** All networking resources in `network.tf` are skipped (count = 0). AKS creates its own VNet with a managed NAT Gateway. Subnet-related locals resolve to `null`, and azapi strips null values from the ARM body.

The conditional logic lives in `locals.tf` (`create_network`, `create_nat_gateway`, `create_route_table`). These booleans drive `count` on every resource in `network.tf` and feed into `main.tf` via `local.node_subnet_id`, `local.apiserver_subnet_id`, and `local.outbound_type`.

### Key resource: the AKS cluster (`main.tf`)

`azapi_resource.aks` sends a single ARM PUT to `Microsoft.ContainerService/managedClusters`. The critical settings that make this an Automatic cluster (vs Standard) are:

- `sku.name = "Automatic"` (not `"Base"`)
- `sku.tier = "Standard"`
- `nodeProvisioningProfile.mode = "Auto"`

Many properties in the body are **preconfigured by AKS Automatic** and cannot be changed (Azure RBAC, Cilium, CNI Overlay, workload identity, OIDC, image cleaner, deployment safeguards). They are set explicitly so the ARM payload is declarative and complete. See the README's "Preconfigured vs Fine-tunable" section for the full list.

---

## Ingress considerations

Application Routing (managed NGINX) is preconfigured and always enabled. Key points when modifying ingress configuration:

- `ingressProfile.webAppRouting.dnsZoneResourceIds` accepts both public (`Microsoft.Network/dnsZones`) and private (`Microsoft.Network/privateDnsZones`) zone IDs. When integrating with ALZ hub-spoke, use **private DNS zones hosted in the connectivity subscription** – pass their full resource IDs.
- The managed NGINX controller needs the AKS managed identity to have `DNS Zone Contributor` on the referenced DNS zones. This RBAC assignment is **not managed by this module** – it must be granted externally (e.g., by the ALZ platform team or a separate Terraform config).
- TLS certificates from Azure Key Vault are consumed via `kubernetes.azure.com/tls-cert-keyvault-uri` annotations on `Ingress` resources, not via the ARM body. The cluster's managed identity needs `Key Vault Secrets User` on the vault.
- Istio ingress gateway (`serviceMeshProfile`) creates an additional Azure Load Balancer. When using UDR egress, ensure the firewall allows return traffic to the LB frontend IP.

## Egress considerations

Egress type is the single most impactful networking decision. Caveats per option:

### NAT Gateway (`userAssignedNATGateway`)
- The NAT Gateway is associated to the **node subnet only**. The API server subnet must never have a NAT Gateway.
- Each public IP provides 64k SNAT ports. For clusters with heavy outbound connections, add extra public IPs post-deployment.
- The outbound IP is deterministic – useful for allowlisting on external services.

### User-Defined Routing / Firewall (`userDefinedRouting`)
- `var.firewall_private_ip` must be set. The module creates a route table with `0.0.0.0/0 → VirtualAppliance`.
- The firewall/NVA **must** whitelist all [AKS required outbound FQDNs](https://learn.microsoft.com/azure/aks/outbound-rules-control-egress). Azure Firewall can use the built-in `AzureKubernetesService` FQDN tag.
- Required outbound endpoints include: `*.hcp.<region>.azmk8s.io`, `mcr.microsoft.com`, `*.data.mcr.microsoft.com`, management.azure.com, `login.microsoftonline.com`, `packages.microsoft.com`, `acs-mirror.azurelinux.com`.
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

- In ALZ, the **connectivity subscription** typically owns the hub VNet and the platform team manages VNet peering. This module creates its own spoke VNet (`network.tf`). You must **peer this spoke VNet to the ALZ hub** externally — this module does not create peering resources.
- If the ALZ platform team pre-provisions spoke VNets, disable BYO VNet (`enable_byo_vnet = false`) and instead supply the pre-created subnet IDs directly. This would require modifying `locals.tf` to accept external subnet ID variables instead of referencing `azapi_resource.node_subnet[0].id`.

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
- For Application Routing DNS integration, the `dns_zone_resource_ids` variable must point to zones the platform team has pre-created. The AKS managed identity needs `DNS Zone Contributor` on those zones – this is a **cross-subscription RBAC assignment** that must be handled by the ALZ platform team or a separate Terraform state.

### Egress through hub firewall (UDR)

- The standard ALZ pattern routes all spoke egress through the hub Azure Firewall via UDR. Set `egress_type = "userDefinedRouting"` and `firewall_private_ip` to the hub firewall's private IP.
- The ALZ firewall policy must include rules for AKS required outbound FQDNs. The `AzureKubernetesService` FQDN tag on Azure Firewall covers most requirements, but additional rules may be needed for:
  - Container image registries (ACR, Docker Hub, etc.)
  - Helm chart repositories
  - External APIs consumed by workloads
  - OS package repositories for Azure Linux (`packages.microsoft.com`, `acs-mirror.azurelinux.com`)
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
  - `DNS Zone Contributor` on any DNS zones referenced in Application Routing.
  - `Key Vault Secrets User` on any Key Vault used for TLS certs.
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
| `network.tf` | All BYO VNet resources (conditionally created) |
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
count = local.create_nat_gateway ? 1 : 0
```

Reference these resources with `[0]` indexing inside ternaries guarded by the same boolean, or use `try(..., null)` in outputs.

### ARM body structure

The `body` block in `azapi_resource.aks` mirrors the ARM REST API structure exactly (`sku`, `properties.networkProfile`, etc.). Use **camelCase** for ARM property names inside `body`. Keep properties grouped by concern with `# -----` comment separators matching the README sections.

### Tags

All resources receive `local.tags`. Don't hardcode tags on individual resources — pass them through the local.
