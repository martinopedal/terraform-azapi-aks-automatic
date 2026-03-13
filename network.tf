# =============================================================================
# Module-created Virtual Network
#
# This file is used only when enable_byo_vnet = true AND no external subnet IDs
# are provided. In that standalone mode it creates:
#   • VNet with configurable address space
#   • Node subnet (with NSG and optional Route Table association)
#   • API server subnet (delegated to Microsoft.ContainerService/managedClusters)
#   • NSG (empty – AKS manages its own rules)
#   • Route Table resources when egress_type = userDefinedRouting
#
# In ALZ Corp vending mode, the spoke VNet, subnets, peering, UDR, and NSG are
# pre-provisioned externally, so none of the resources in this file are created.
# =============================================================================

# -----------------------------------------------------------------------------
# Network Security Group
# -----------------------------------------------------------------------------

resource "azapi_resource" "nsg" {
  count     = local.create_network ? 1 : 0
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-${var.cluster_name}-nodes"
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    properties = {
      # AKS automatically injects the required NSG rules at cluster creation.
      # Add custom rules here only if you need additional restrictions.
      securityRules = []
    }
  }
}

# -----------------------------------------------------------------------------
# Virtual Network
# -----------------------------------------------------------------------------

resource "azapi_resource" "vnet" {
  count     = local.create_network ? 1 : 0
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = var.vnet_name
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    properties = {
      addressSpace = {
        addressPrefixes = [var.vnet_address_space]
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Node Subnet
#
# Hosts the AKS worker nodes. Associated with the NSG and, for
# userDefinedRouting, a Route Table for forced-tunnelling via the hub firewall.
# -----------------------------------------------------------------------------

resource "azapi_resource" "node_subnet" {
  count     = local.create_network ? 1 : 0
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = var.node_subnet_name
  parent_id = azapi_resource.vnet[0].id

  body = {
    properties = {
      addressPrefix = var.node_subnet_address_prefix

      networkSecurityGroup = {
        id = azapi_resource.nsg[0].id
      }

      # Route Table association (egress_type = userDefinedRouting)
      routeTable = local.create_route_table ? {
        id = azapi_resource.route_table[0].id
      } : null
    }
  }

  depends_on = [
    azapi_resource.route_table,
  ]
}

# -----------------------------------------------------------------------------
# API Server Subnet
#
# Dedicated subnet for API Server VNet Integration. Requires delegation to
# Microsoft.ContainerService/managedClusters. Minimum size: /28.
# This subnet MUST NOT have a Route Table association.
# -----------------------------------------------------------------------------

resource "azapi_resource" "apiserver_subnet" {
  count     = local.create_network ? 1 : 0
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = var.apiserver_subnet_name
  parent_id = azapi_resource.vnet[0].id

  body = {
    properties = {
      addressPrefix = var.apiserver_subnet_address_prefix

      delegations = [
        {
          name = "aks-delegation"
          properties = {
            serviceName = "Microsoft.ContainerService/managedClusters"
          }
        }
      ]
    }
  }

  # Subnets in the same VNet must be created sequentially
  depends_on = [azapi_resource.node_subnet]
}

# =============================================================================
# Egress – User-Defined Routing (forced-tunnelling through hub Azure Firewall)
#
# ALZ Corp pattern: all spoke egress routes through the hub firewall via UDR.
# The firewall must whitelist AKS required outbound FQDNs:
#   https://learn.microsoft.com/azure/aks/outbound-rules-control-egress
#
# Set var.firewall_private_ip to the hub firewall's private IP.
# =============================================================================

resource "azapi_resource" "route_table" {
  count     = local.create_route_table ? 1 : 0
  type      = "Microsoft.Network/routeTables@2024-05-01"
  name      = "rt-${var.cluster_name}"
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    properties = {
      disableBgpRoutePropagation = false

      routes = [
        {
          name = "default-to-firewall"
          properties = {
            addressPrefix    = "0.0.0.0/0"
            nextHopType      = "VirtualAppliance"
            nextHopIpAddress = var.firewall_private_ip
          }
        }
      ]
    }
  }

  lifecycle {
    precondition {
      condition     = var.firewall_private_ip != null
      error_message = "firewall_private_ip is required when egress_type = userDefinedRouting."
    }
  }
}

