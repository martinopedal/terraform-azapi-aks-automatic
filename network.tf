# =============================================================================
# BYO Virtual Network
#
# When enable_byo_vnet = true this file creates:
#   • VNet with configurable address space
#   • Node subnet (with NSG, optional NAT Gateway / Route Table association)
#   • API server subnet (delegated to Microsoft.ContainerService/managedClusters)
#   • NSG (empty – AKS manages its own rules)
#   • Egress resources depending on egress_type:
#       - userAssignedNATGateway → Public IP + NAT Gateway
#       - userDefinedRouting     → Route Table with 0.0.0.0/0 → NVA/Firewall
#       - loadBalancer           → nothing extra (AKS uses the Standard LB)
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
# Hosts the AKS worker nodes. Associated with the NSG, and optionally with
# a NAT Gateway (recommended) or a Route Table (forced-tunnelling via NVA).
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

      # NAT Gateway association (egress_type = userAssignedNATGateway)
      natGateway = local.create_nat_gateway ? {
        id = azapi_resource.nat_gateway[0].id
      } : null

      # Route Table association (egress_type = userDefinedRouting)
      routeTable = local.create_route_table ? {
        id = azapi_resource.route_table[0].id
      } : null
    }
  }

  depends_on = [
    azapi_resource.nat_gateway,
    azapi_resource.route_table,
  ]
}

# -----------------------------------------------------------------------------
# API Server Subnet
#
# Dedicated subnet for API Server VNet Integration. Requires delegation to
# Microsoft.ContainerService/managedClusters. Minimum size: /28.
# This subnet MUST NOT have a NAT Gateway or Route Table association.
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
# Egress Option 1 – NAT Gateway  (recommended for production BYO VNet)
#
# Provides deterministic, high-throughput outbound connectivity with a static
# public IP. Each NAT Gateway supports up to 64k SNAT ports per IP address.
# =============================================================================

resource "azapi_resource" "nat_gateway_pip" {
  count     = local.create_nat_gateway ? 1 : 0
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  name      = "pip-natgw-${var.cluster_name}"
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    sku = {
      name = "Standard"
      tier = "Regional"
    }
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
  }
}

resource "azapi_resource" "nat_gateway" {
  count     = local.create_nat_gateway ? 1 : 0
  type      = "Microsoft.Network/natGateways@2024-05-01"
  name      = "natgw-${var.cluster_name}"
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  body = {
    sku = {
      name = "Standard"
    }
    properties = {
      idleTimeoutInMinutes = var.nat_gateway_idle_timeout
      publicIpAddresses = [
        { id = azapi_resource.nat_gateway_pip[0].id }
      ]
    }
  }
}

# =============================================================================
# Egress Option 2 – User-Defined Routing  (forced-tunnelling through NVA)
#
# All outbound traffic (0.0.0.0/0) is routed to a firewall / NVA. The NVA
# must whitelist the AKS required egress endpoints:
#   https://learn.microsoft.com/azure/aks/outbound-rules-control-egress
#
# Set var.egress_type = "userDefinedRouting" and provide var.firewall_private_ip.
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

# =============================================================================
# Egress Option 3 – Load Balancer
#
# No extra resources needed. AKS uses the Standard Load Balancer for SNAT.
# This is the simplest option but offers fewer SNAT ports and no static
# outbound IP. Suitable for dev/test scenarios.
# =============================================================================
