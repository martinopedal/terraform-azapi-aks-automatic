# =============================================================================
# Supporting Services (not managed by AKS Automatic)
#
# In an ALZ Corp deployment, all PaaS services are accessed via Private
# Endpoints only. Public access is disabled. The Private DNS Zones for
# these services (privatelink.azurecr.io, privatelink.vaultcore.azure.net)
# are owned by the connectivity subscription and must be pre-created by the
# platform team. This module creates only the Private Endpoints and the
# DNS Zone Groups that auto-register A records in the linked zones.
#
# Resources created here:
#   - Azure Container Registry (Premium, public access disabled)
#   - Azure Key Vault (RBAC-based, public access disabled)
#   - Private Endpoints for ACR and Key Vault in the PE subnet
#   - Private DNS Zone Groups (link PE to existing Private DNS Zones)
#   - RBAC role assignments for the AKS managed identity
# =============================================================================

# -----------------------------------------------------------------------------
# Private Endpoint Subnet (BYO VNet only)
# Hosts Private Endpoints for ACR, Key Vault, and any other PaaS services.
# No delegation required. No NSG or Route Table needed.
# -----------------------------------------------------------------------------

resource "azapi_resource" "pe_subnet" {
  count     = local.create_pe_subnet ? 1 : 0
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = var.pe_subnet_name
  parent_id = azapi_resource.vnet[0].id

  body = {
    properties = {
      addressPrefix = var.pe_subnet_address_prefix
    }
  }

  depends_on = [azapi_resource.apiserver_subnet]
}

# =============================================================================
# Azure Container Registry
# =============================================================================

resource "azapi_resource" "acr" {
  count     = var.create_acr ? 1 : 0
  type      = "Microsoft.ContainerRegistry/registries@2023-07-01"
  name      = var.acr_name
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    sku = {
      name = "Premium"
    }
    properties = {
      adminUserEnabled         = false
      publicNetworkAccess      = "Disabled"
      networkRuleBypassOptions = "AzureServices"
    }
  }

  lifecycle {
    precondition {
      condition     = local.pe_subnet_id != null
      error_message = "ACR is configured with public access disabled but no PE subnet is available. Set external_pe_subnet_id (vending mode) or enable BYO VNet (standalone mode) to provide a subnet for the private endpoint."
    }
  }
}

# ACR Private Endpoint
resource "azapi_resource" "acr_pe" {
  count     = var.create_acr && local.pe_subnet_id != null ? 1 : 0
  type      = "Microsoft.Network/privateEndpoints@2024-05-01"
  name      = "pe-${var.acr_name}"
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    properties = {
      subnet = {
        id = local.pe_subnet_id
      }
      privateLinkServiceConnections = [
        {
          name = "acr"
          properties = {
            privateLinkServiceId = azapi_resource.acr[0].id
            groupIds             = ["registry"]
          }
        }
      ]
    }
  }

  depends_on = [azapi_resource.pe_subnet]
}

# ACR Private DNS Zone Group
# Links the PE to the privatelink.azurecr.io zone in the connectivity
# subscription. The zone must be pre-created and linked to the hub + spoke
# VNets by the platform team.
resource "azapi_resource" "acr_pe_dns" {
  count     = var.create_acr && local.pe_subnet_id != null && var.acr_private_dns_zone_id != null ? 1 : 0
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = azapi_resource.acr_pe[0].id

  body = {
    properties = {
      privateDnsZoneConfigs = [
        {
          name = "privatelink-azurecr-io"
          properties = {
            privateDnsZoneId = var.acr_private_dns_zone_id
          }
        }
      ]
    }
  }
}

# =============================================================================
# Azure Key Vault
# =============================================================================

resource "azapi_resource" "keyvault" {
  count     = var.create_keyvault ? 1 : 0
  type      = "Microsoft.KeyVault/vaults@2023-07-01"
  name      = var.keyvault_name
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    properties = {
      tenantId                  = data.azurerm_client_config.current.tenant_id
      sku                       = { family = "A", name = "standard" }
      enableRbacAuthorization   = true
      enableSoftDelete          = true
      softDeleteRetentionInDays = 90
      publicNetworkAccess       = "Disabled"
      networkAcls = {
        defaultAction = "Deny"
        bypass        = "AzureServices"
      }
    }
  }

  lifecycle {
    precondition {
      condition     = local.pe_subnet_id != null
      error_message = "Key Vault is configured with public access disabled but no PE subnet is available. Set external_pe_subnet_id (vending mode) or enable BYO VNet (standalone mode) to provide a subnet for the private endpoint."
    }
  }
}

# Key Vault Private Endpoint
resource "azapi_resource" "kv_pe" {
  count     = var.create_keyvault && local.pe_subnet_id != null ? 1 : 0
  type      = "Microsoft.Network/privateEndpoints@2024-05-01"
  name      = "pe-${var.keyvault_name}"
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    properties = {
      subnet = {
        id = local.pe_subnet_id
      }
      privateLinkServiceConnections = [
        {
          name = "keyvault"
          properties = {
            privateLinkServiceId = azapi_resource.keyvault[0].id
            groupIds             = ["vault"]
          }
        }
      ]
    }
  }

  depends_on = [azapi_resource.pe_subnet]
}

# Key Vault Private DNS Zone Group
resource "azapi_resource" "kv_pe_dns" {
  count     = var.create_keyvault && local.pe_subnet_id != null && var.kv_private_dns_zone_id != null ? 1 : 0
  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = azapi_resource.kv_pe[0].id

  body = {
    properties = {
      privateDnsZoneConfigs = [
        {
          name = "privatelink-vaultcore-azure-net"
          properties = {
            privateDnsZoneId = var.kv_private_dns_zone_id
          }
        }
      ]
    }
  }
}

# =============================================================================
# RBAC Role Assignments
#
# AKS Automatic's SystemAssigned managed identity requires access to external
# resources. These are NOT created by AKS itself. In ALZ Corp, some of these
# may be cross-subscription assignments managed by the platform team.
# =============================================================================

# AcrPull — the KUBELET identity pulls container images, not the cluster identity.
# The kubelet identity objectId is exported from the AKS response.
resource "azapi_resource" "role_acr_pull" {
  count     = var.create_acr ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${azapi_resource.aks.id}-acr-pull")
  parent_id = azapi_resource.acr[0].id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
      principalId      = azapi_resource.aks.output.properties.identityProfile.kubeletidentity.objectId
      principalType    = "ServicePrincipal"
    }
  }
}

# Key Vault Certificate User — the APP ROUTING add-on identity fetches TLS
# certificates, not the cluster control-plane identity. The add-on identity
# objectId is exported from the AKS response.
resource "azapi_resource" "role_kv_cert_user" {
  count     = var.create_keyvault ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${azapi_resource.aks.id}-kv-cert")
  parent_id = azapi_resource.keyvault[0].id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/db79e9a7-68ee-4b58-9aeb-b90e7c24fcba"
      principalId      = azapi_resource.aks.output.properties.ingressProfile.webAppRouting.identity.objectId
      principalType    = "ServicePrincipal"
    }
  }
}

# Network Contributor on the module-created spoke VNet — NAP provisions nodes in BYO subnets.
# In vending mode, this assignment is granted by the vending pipeline on the
# pre-provisioned subnets instead of by this module. The SystemAssigned identity
# dependency is resolved by Terraform because the AKS cluster and VNet are in the
# same state.
resource "azapi_resource" "role_network_contributor" {
  count     = local.create_network ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${azapi_resource.aks.id}-net-contrib")
  parent_id = azapi_resource.vnet[0].id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
      principalId      = azapi_resource.aks.identity[0].principal_id
      principalType    = "ServicePrincipal"
    }
  }
}
