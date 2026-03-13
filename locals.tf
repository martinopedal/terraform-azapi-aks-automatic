locals {
  # --- Networking mode ---
  # Two BYO VNet paths (enable_byo_vnet = true in both):
  #   1. external_node_subnet_id = null  -> this module creates VNet + subnets (network.tf)
  #   2. external_node_subnet_id set     -> vending/AVNM pre-provisioned subnets (network.tf skipped)
  # Third path (enable_byo_vnet = false): AKS managed VNet (not suitable for ALZ Corp)
  use_external_subnets = var.external_node_subnet_id != null

  create_network     = var.enable_byo_vnet && !local.use_external_subnets
  create_route_table = local.create_network && var.egress_type == "userDefinedRouting"
  create_pe_subnet   = local.create_network && (var.create_acr || var.create_keyvault)

  # Egress type: BYO VNet (either path) uses var.egress_type; managed VNet uses managedNATGateway
  outbound_type = var.enable_byo_vnet ? var.egress_type : "managedNATGateway"

  # Subnet IDs — resolved from module-created, externally-provided, or null (managed VNet)
  node_subnet_id = (
    local.create_network ? azapi_resource.node_subnet[0].id :
    local.use_external_subnets ? var.external_node_subnet_id :
    null
  )
  apiserver_subnet_id = (
    local.create_network ? azapi_resource.apiserver_subnet[0].id :
    local.use_external_subnets ? var.external_apiserver_subnet_id :
    null
  )
  pe_subnet_id = (
    local.create_pe_subnet ? azapi_resource.pe_subnet[0].id :
    local.use_external_subnets ? var.external_pe_subnet_id :
    null
  )

  # --- Ingress ---
  dns_zone_ids = length(var.dns_zone_resource_ids) > 0 ? var.dns_zone_resource_ids : null

  # --- Tags ---
  tags = var.tags
}
