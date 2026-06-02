locals {
  # --- Networking mode ---
  # Two BYO VNet paths (enable_byo_vnet = true in both):
  #   1. external_node_subnet_id = null  -> this module creates VNet + subnets (network.tf)
  #   2. external_node_subnet_id set     -> vending/AVNM pre-provisioned subnets (network.tf skipped)
  # Third path (enable_byo_vnet = false): AKS managed VNet (not suitable for ALZ Corp)
  use_external_subnets = var.external_node_subnet_id != null

  create_network      = var.enable_byo_vnet && !local.use_external_subnets
  create_route_table  = local.create_network && var.egress_type == "userDefinedRouting"
  create_pe_subnet    = local.create_network && (var.create_acr || var.create_keyvault)
  agc_input_subnet_id = var.app_gateway_for_containers_subnet_id != null ? var.app_gateway_for_containers_subnet_id : var.external_agc_subnet_id
  create_agc_subnet   = local.create_network && var.create_resource_group && var.enable_app_gateway_for_containers && local.agc_input_subnet_id == null

  # Resource group resolution: either module-created or existing in current subscription.
  rg_id       = var.create_resource_group ? azapi_resource.rg[0].id : "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
  rg_location = var.location

  # Egress type: BYO VNet (either path) uses var.egress_type; managed VNet uses managedNATGateway
  outbound_type = var.enable_byo_vnet ? var.egress_type : "managedNATGateway"

  # Subnet IDs: resolved from module-created, externally-provided, or null (managed VNet)
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
  agc_subnet_id = (
    local.create_agc_subnet ? azapi_resource.agc_subnet[0].id :
    local.agc_input_subnet_id
  )

  agc_name = coalesce(var.app_gateway_for_containers_name, "${var.cluster_name}-agc")

  # --- Ingress ---
  # AGC is canonical. Managed NGINX is opt-in and suppressed when AGC is enabled.
  enable_web_app_routing = var.enable_managed_nginx && !var.enable_app_gateway_for_containers
  dns_zone_ids           = local.enable_web_app_routing && length(var.dns_zone_resource_ids) > 0 ? var.dns_zone_resource_ids : null

  # --- Identity ---
  # Custom private DNS zones require UserAssigned identity
  use_user_assigned_identity = (
    var.enable_private_cluster &&
    var.private_dns_zone_id != null &&
    var.private_dns_zone_id != "system" &&
    var.private_dns_zone_id != "none"
  )

  # --- Tags ---
  tags = var.tags
}
