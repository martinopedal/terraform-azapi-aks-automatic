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

  # The module derives count from whether these IDs are null, so they must
  # be known at plan time. Pass deterministic IDs and order explicitly
  # (module finding: prefer a boolean input over a null check on an ID).
  # The identity's VNet rights must exist before the cluster is created.
  depends_on = [
    azapi_resource.snet_nodes,
    azapi_resource.snet_apiserver,
    azapi_resource.snet_system,
    azapi_resource.ra_cluster_vnet,
  ]

  location              = local.location
  resource_group_name   = "rg-aks-online-demo"
  create_resource_group = false
  cluster_name          = "aks-online-demo"
  cluster_sku           = "Automatic"

  enable_byo_vnet                = true
  external_node_subnet_id        = local.node_subnet_id
  external_apiserver_subnet_id   = local.apiserver_subnet_id
  external_system_node_subnet_id = local.system_node_subnet_id
  egress_type                    = "userAssignedNATGateway"
  user_assigned_identity_id      = azapi_resource.uami_cluster.id

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
