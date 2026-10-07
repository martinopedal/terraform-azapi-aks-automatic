# =============================================================================
# Online landing zone deployment (root module)
#
# Thin root that consumes the AKS Automatic module exactly as a customer
# would. The module itself stays provider-free so it remains a reusable
# child module (see commit 2917adb); providers, backend and the spoke
# network live here (network.tf).
#
# Internet-facing demo workload, not Corp:
#   - cluster_sku = "Automatic": AKS Automatic SKU with managed system node
#     pools (hostedSystemProfile). Created new; AKS does not migrate Base
#     clusters to Automatic.
#   - BYO spoke from network.tf: NSG on every subnet (landing-zone policy),
#     explicit NAT Gateway for egress, delegated API server subnet, and a
#     dedicated system node subnet.
#   - egress_type = "userAssignedNATGateway": egress through the NAT Gateway
#     attached to the node subnet (static public IP).
#   - enable_private_cluster = false: public API server (Entra RBAC only,
#     local accounts disabled). No hub peering in an Online subscription.
#   - enable_managed_nginx = true: AKS Application Routing add-on (managed
#     NGINX) is the ingress. AGC stays off for simplicity.
# Same module, same hardening defaults (Entra RBAC only, workload identity,
# OIDC issuer, prevent_destroy, image cleaner) as the Corp example.
# =============================================================================

module "aks" {
  source = "../.."

  # use_external_subnets = true keeps the module's count known at plan time
  # while the subnets are created in this same root. Ordering is implicit
  # through the references (subnets, then the identity anchor created after
  # its VNet role assignment). No module-level depends_on: it would defer
  # the module's data sources and force a cluster replacement whenever a
  # dependency has a pending change.

  location              = local.location
  resource_group_name   = "rg-aks-online-demo"
  create_resource_group = false
  cluster_name          = "aks-online-demo"
  cluster_sku           = "Automatic"

  enable_byo_vnet                = true
  use_external_subnets           = true
  external_node_subnet_id        = azapi_resource.snet_nodes.id
  external_apiserver_subnet_id   = azapi_resource.snet_apiserver.id
  external_system_node_subnet_id = azapi_resource.snet_system.id
  egress_type                    = "userAssignedNATGateway"
  user_assigned_identity_id      = terraform_data.cluster_identity.output

  enable_app_gateway_for_containers = false
  enable_managed_nginx              = true

  # Public endpoint, but only reachable from the allow-listed egress IPs
  # (the deployment runner's static NAT IP). Value comes from the GitHub
  # environment, not from code.
  enable_private_cluster = false
  authorized_ip_ranges   = var.api_server_authorized_ip_ranges

  create_acr      = false
  create_keyvault = false

  tags = local.tags
}
