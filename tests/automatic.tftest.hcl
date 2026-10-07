# AKS Automatic SKU contract tests (plan-only, mocked providers).
#
# Microsoft Learn (AKS Automatic custom VNet quickstart, limitations):
#   - "You can't create AKS Automatic clusters without managed system node
#     pools in any region." -> hostedSystemProfile with a system node subnet.
#   - "Migration from AKS base SKU to automatic SKU isn't supported."
# The Base path must stay unchanged for existing consumers.

mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  enable_byo_vnet                   = true
  external_node_subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-nodes"
  external_apiserver_subnet_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-apiserver"
  egress_type                       = "userAssignedNATGateway"
  user_assigned_identity_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"
  enable_private_cluster            = false
  enable_app_gateway_for_containers = false
  enable_managed_nginx              = true
  create_resource_group             = false
  create_acr                        = false
  create_keyvault                   = false
}

run "automatic_sku_uses_hosted_system_profile_and_no_system_pool" {
  command = plan

  variables {
    cluster_sku                    = "Automatic"
    external_system_node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-system"
  }

  assert {
    condition     = azapi_resource.aks.body.sku.name == "Automatic" && azapi_resource.aks.body.sku.tier == "Standard"
    error_message = "cluster_sku = Automatic must send sku Automatic/Standard."
  }

  assert {
    condition     = azapi_resource.aks.type == "Microsoft.ContainerService/managedClusters@2026-04-01"
    error_message = "The Automatic path must use an API version that supports hostedSystemProfile."
  }

  assert {
    condition     = azapi_resource.aks.body.properties.hostedSystemProfile.enabled == true
    error_message = "Automatic clusters require managed system node pools (hostedSystemProfile.enabled)."
  }

  assert {
    condition     = azapi_resource.aks.body.properties.hostedSystemProfile.systemNodeSubnetID == var.external_system_node_subnet_id && azapi_resource.aks.body.properties.hostedSystemProfile.nodeSubnetID == var.external_node_subnet_id
    error_message = "hostedSystemProfile must reference the system node subnet and the user node subnet."
  }

  assert {
    condition     = !contains(keys(azapi_resource.aks.body.properties), "agentPoolProfiles") && !contains(keys(azapi_resource.aks.body.properties), "addonProfiles")
    error_message = "The Automatic path must omit agentPoolProfiles and addonProfiles (AKS manages them; sending them causes rejection or drift)."
  }
}

run "base_sku_is_the_default_and_unchanged" {
  command = plan

  assert {
    condition     = azapi_resource.aks.body.sku.name == "Base" && azapi_resource.aks.type == "Microsoft.ContainerService/managedClusters@2025-10-01"
    error_message = "The default must remain the Base SKU on the existing API version."
  }

  assert {
    condition     = length(azapi_resource.aks.body.properties.agentPoolProfiles) == 1 && contains(keys(azapi_resource.aks.body.properties), "addonProfiles") && !contains(keys(azapi_resource.aks.body.properties), "hostedSystemProfile")
    error_message = "The Base body must keep its system pool and addonProfiles key, and must not send hostedSystemProfile."
  }
}

run "automatic_requires_system_node_subnet" {
  command = plan

  variables {
    cluster_sku = "Automatic"
  }

  expect_failures = [azapi_resource.aks]
}

run "automatic_requires_user_assigned_identity" {
  command = plan

  variables {
    cluster_sku                    = "Automatic"
    external_system_node_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-system"
    user_assigned_identity_id      = null
  }

  expect_failures = [azapi_resource.aks]
}

run "cluster_sku_rejects_unknown_value" {
  command = plan

  variables {
    cluster_sku = "Premium"
  }

  expect_failures = [var.cluster_sku]
}
