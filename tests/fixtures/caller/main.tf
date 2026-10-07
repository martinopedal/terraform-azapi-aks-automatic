# Test fixture: a caller that creates the subnets in the same root and
# passes their IDs to the module. The IDs are unknown at plan time, which
# reproduces the "Invalid count argument" failure seen in a real consumer.
terraform {
  required_version = ">= 1.9"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.12.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }
}

variable "use_external_subnets" {
  type    = bool
  default = null
}

locals {
  vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test"
}

resource "azapi_resource" "node" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "snet-nodes"
  parent_id = local.vnet_id
  body      = { properties = { addressPrefix = "10.0.0.0/24" } }
}

resource "azapi_resource" "apiserver" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "snet-apiserver"
  parent_id = local.vnet_id
  body      = { properties = { addressPrefix = "10.0.1.0/28" } }
}

module "aks" {
  source = "../../.."

  location                          = "swedencentral"
  resource_group_name               = "rg-test"
  create_resource_group             = false
  cluster_name                      = "aks-test"
  enable_byo_vnet                   = true
  use_external_subnets              = var.use_external_subnets
  external_node_subnet_id           = azapi_resource.node.id
  external_apiserver_subnet_id      = azapi_resource.apiserver.id
  egress_type                       = "userAssignedNATGateway"
  user_assigned_identity_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-test"
  enable_private_cluster            = false
  enable_app_gateway_for_containers = false
  enable_managed_nginx              = true
  create_acr                        = false
  create_keyvault                   = false
}

output "module_vnet_id" {
  value = module.aks.vnet_id
}
