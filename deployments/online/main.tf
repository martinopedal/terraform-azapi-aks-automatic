# =============================================================================
# Online landing zone deployment (root module)
#
# Thin root that consumes the AKS Automatic module exactly as a customer
# would. The module itself stays provider-free so it remains a reusable
# child module (see commit 2917adb); providers, backend and the spoke
# network live here (network.tf).
#
# Internet-facing demo workload, not Corp:
#   - BYO spoke from network.tf: NSG on every subnet (landing-zone policy),
#     explicit NAT Gateway for egress, delegated API server subnet.
#   - egress_type = "none": AKS uses the subnet's NAT Gateway for egress.
#   - enable_private_cluster = false: public API server (Entra RBAC only,
#     local accounts disabled). No hub peering in an Online subscription.
#   - enable_managed_nginx = true: AKS Application Routing add-on (managed
#     NGINX) is the ingress. AGC stays off for simplicity.
# Same module, same hardening defaults (Entra RBAC only, workload identity,
# OIDC issuer, prevent_destroy, image cleaner) as the Corp example.
# =============================================================================

module "aks" {
  source = "../.."

  location              = local.location
  resource_group_name   = "rg-aks-online-demo"
  create_resource_group = false
  cluster_name          = "aks-online-demo"
  system_node_vm_size   = "Standard_D2s_v5"

  enable_byo_vnet              = true
  external_node_subnet_id      = azapi_resource.snet_nodes.id
  external_apiserver_subnet_id = azapi_resource.snet_apiserver.id
  egress_type                  = "none"

  enable_app_gateway_for_containers = false
  enable_managed_nginx              = true

  enable_private_cluster = false

  create_acr      = false
  create_keyvault = false

  tags = local.tags
}
