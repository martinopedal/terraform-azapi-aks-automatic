locals {
  # --- Networking conditionals ---
  create_network     = var.enable_byo_vnet
  create_nat_gateway = var.enable_byo_vnet && var.egress_type == "userAssignedNATGateway"
  create_route_table = var.enable_byo_vnet && var.egress_type == "userDefinedRouting"

  outbound_type = var.enable_byo_vnet ? var.egress_type : "managedNATGateway"

  # Subnet IDs – null when using managed VNet (AKS creates its own)
  node_subnet_id      = var.enable_byo_vnet ? azapi_resource.node_subnet[0].id : null
  apiserver_subnet_id = var.enable_byo_vnet ? azapi_resource.apiserver_subnet[0].id : null

  # --- Ingress ---
  dns_zone_ids = length(var.dns_zone_resource_ids) > 0 ? var.dns_zone_resource_ids : null

  # --- Tags ---
  tags = var.tags
}
