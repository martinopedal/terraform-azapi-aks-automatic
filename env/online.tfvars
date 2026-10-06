# =============================================================================
# Online landing zone, simplified example
#
# Internet-facing demo workload, not Corp. Deliberately avoids BYO VNet, the
# hub firewall, and private DNS so the footprint stays small:
#   - enable_byo_vnet = false -> AKS-managed VNet. outboundType resolves to
#     managedNATGateway automatically (see locals.tf), so no route table,
#     firewall, or manual NAT Gateway resource is needed.
#   - enable_private_cluster = false -> public API server, appropriate for an
#     Online subscription with no hub peering.
#   - enable_managed_nginx = true -> the AKS Application Routing add-on
#     (managed NGINX) is the ingress. AGC needs a dedicated delegated subnet,
#     which managed-VNet mode does not expose, so AGC stays off here; the
#     Corp example (terraform.tfvars.example) still shows AGC for BYO VNet.
# Same module, same hardening defaults (AAD RBAC only, workload identity,
# OIDC issuer, prevent_destroy, image cleaner) as the Corp example.
# =============================================================================

location              = "swedencentral"
resource_group_name   = "rg-aks-online-demo"
create_resource_group = false
cluster_name          = "aks-online-demo"
system_node_vm_size   = "Standard_D2s_v5"

enable_byo_vnet = false

enable_app_gateway_for_containers = false
enable_managed_nginx              = true

enable_private_cluster = false

create_acr      = false
create_keyvault = false

tags = {
  Environment        = "Demo"
  Owner              = "martin.opedal@microsoft.com"
  DataClassification = "Internal"
  Workload           = "AKS-Automatic-Online"
  BusinessUnit       = "Azure-Specialist-Team"
  lifecycle          = "demo"
  purgeable          = "true"
  expiry             = "2026-10-31"
}
