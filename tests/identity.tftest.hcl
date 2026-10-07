# Identity contract tests (plan-only, mocked providers, no Azure access).
#
# AKS rejects a system-assigned identity when the cluster uses a BYO VNet
# ("OnlySupportedOnUserAssignedMSICluster"), so a supplied
# user_assigned_identity_id must be used whenever it is set, not only for
# private clusters with a custom private DNS zone.

mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  enable_byo_vnet                   = true
  external_node_subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-nodes"
  external_apiserver_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-apiserver"
  egress_type                       = "none"
  enable_private_cluster            = false
  enable_app_gateway_for_containers = false
  enable_managed_nginx              = true
  create_resource_group             = false
  create_acr                        = false
  create_keyvault                   = false
}

run "byo_vnet_public_cluster_uses_supplied_user_assigned_identity" {
  command = plan

  variables {
    user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"
  }

  assert {
    condition     = azapi_resource.aks.identity[0].type == "UserAssigned"
    error_message = "A supplied user_assigned_identity_id must produce a UserAssigned cluster identity."
  }

  assert {
    condition     = contains(azapi_resource.aks.identity[0].identity_ids, var.user_assigned_identity_id)
    error_message = "The cluster identity must reference the supplied user-assigned identity."
  }

  assert {
    condition     = azapi_resource.aks.body.properties.networkProfile.outboundType == "none"
    error_message = "External subnets with egress_type = none must pass outboundType none."
  }
}

run "byo_vnet_accepts_user_assigned_nat_gateway_egress" {
  command = plan

  variables {
    egress_type               = "userAssignedNATGateway"
    user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"
  }

  assert {
    condition     = azapi_resource.aks.body.properties.networkProfile.outboundType == "userAssignedNATGateway"
    error_message = "egress_type = userAssignedNATGateway must pass through as outboundType for BYO subnets with a NAT Gateway."
  }
}

run "no_identity_supplied_keeps_system_assigned" {
  command = plan

  assert {
    condition     = azapi_resource.aks.identity[0].type == "SystemAssigned"
    error_message = "Without user_assigned_identity_id the cluster must keep a SystemAssigned identity."
  }
}

# AKS returns costAnalysis.enabled = false when disabled. Sending null made
# every plan show an in-place update (observed: a 6-minute no-op apply).
run "cost_analysis_disabled_is_sent_explicitly_to_avoid_drift" {
  command = plan

  assert {
    condition     = azapi_resource.aks.body.properties.metricsProfile.costAnalysis.enabled == false
    error_message = "metricsProfile.costAnalysis.enabled must be sent as false (the API's shape), not omitted, to avoid perpetual drift."
  }

  # AKS returns serviceMeshProfile = { mode = "Disabled", istio = null }.
  assert {
    condition     = azapi_resource.aks.body.properties.serviceMeshProfile.mode == "Disabled"
    error_message = "serviceMeshProfile.mode must be sent as Disabled when the mesh is off, to avoid perpetual drift."
  }
}

# The default SKU stays "Base" (AKS Standard SKU with Automatic-style
# features) for existing consumers. The Automatic SKU is opt-in through
# cluster_sku = "Automatic" (tests/automatic.tftest.hcl); AKS does not
# migrate an existing Base cluster to Automatic, so switching needs a new
# cluster.
run "sku_stays_base_until_automatic_redesign" {
  command = plan

  assert {
    condition     = azapi_resource.aks.body.sku.name == "Base" && azapi_resource.aks.body.sku.tier == "Standard"
    error_message = "The default cluster_sku must remain Base; Automatic is opt-in and requires a new cluster."
  }
}
