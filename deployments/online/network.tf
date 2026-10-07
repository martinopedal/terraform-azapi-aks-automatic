# =============================================================================
# Online spoke network, owned by this root (vending pattern)
#
# The landing zone enforces "Subnets must have a Network Security Group"
# (ALZ Deny-Subnet-Without-Nsg, Deny effect). An AKS-managed VNet creates
# subnets without NSGs and is rejected, so this root provisions the network
# and the module consumes it through external_*_subnet_id, the same split
# the Corp path uses. Egress is an explicit NAT Gateway on the node subnet;
# the module sets egress_type = "userAssignedNATGateway".
# =============================================================================

locals {
  location = "swedencentral"
  rg_id    = "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/rg-aks-online-demo"
  vnet_id  = "${local.rg_id}/providers/Microsoft.Network/virtualNetworks/vnet-aks-online-demo"

  tags = {
    Environment        = "Demo"
    Owner              = "martin.opedal@microsoft.com"
    DataClassification = "Internal"
    Workload           = "AKS-Automatic-Online"
    BusinessUnit       = "Azure-Specialist-Team"
    lifecycle          = "demo"
    purgeable          = "true"
    expiry             = "2026-10-31"
  }
}

data "azapi_client_config" "current" {}

resource "azapi_resource" "pip_nat" {
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  name      = "pip-natgw-aks-online-demo"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  response_export_values = ["properties.ipAddress"]

  body = {
    sku = { name = "Standard" }
    properties = {
      publicIPAllocationMethod = "Static"
      publicIPAddressVersion   = "IPv4"
    }
  }
}

resource "azapi_resource" "natgw" {
  type      = "Microsoft.Network/natGateways@2024-05-01"
  name      = "natgw-aks-online-demo"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    sku = { name = "Standard" }
    properties = {
      idleTimeoutInMinutes = 4
      publicIpAddresses    = [{ id = azapi_resource.pip_nat.id }]
    }
  }
}

# Nodes: allow only HTTP/HTTPS from the internet to the ingress load
# balancer. Management ports stay closed (ALZ Deny-MgmtPorts-Internet).
resource "azapi_resource" "nsg_nodes" {
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-aks-online-demo-nodes"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      securityRules = [
        {
          name = "Allow-Internet-HTTP-HTTPS-Inbound"
          properties = {
            priority                 = 100
            direction                = "Inbound"
            access                   = "Allow"
            protocol                 = "Tcp"
            sourceAddressPrefix      = "Internet"
            sourcePortRange          = "*"
            destinationAddressPrefix = "*"
            destinationPortRanges    = ["80", "443"]
          }
        }
      ]
    }
  }
}

# API server subnet: default rules only (VNet-internal traffic).
resource "azapi_resource" "nsg_apiserver" {
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-aks-online-demo-apiserver"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      securityRules = []
    }
  }
}

resource "azapi_resource" "vnet" {
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-aks-online-demo"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.20.0.0/16"] }
    }
  }
}

resource "azapi_resource" "snet_nodes" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "snet-aks-nodes"
  parent_id = azapi_resource.vnet.id

  body = {
    properties = {
      addressPrefix        = "10.20.0.0/22"
      networkSecurityGroup = { id = azapi_resource.nsg_nodes.id }
      natGateway           = { id = azapi_resource.natgw.id }
    }
  }
}

# Delegated, dedicated /28 for API Server VNet Integration. No route table.
resource "azapi_resource" "snet_apiserver" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "snet-aks-apiserver"
  parent_id = azapi_resource.vnet.id

  body = {
    properties = {
      addressPrefix        = "10.20.4.0/28"
      networkSecurityGroup = { id = azapi_resource.nsg_apiserver.id }
      delegations = [
        {
          name       = "aks-apiserver"
          properties = { serviceName = "Microsoft.ContainerService/managedClusters" }
        }
      ]
    }
  }

  # Subnet writes on the same VNet must not run concurrently.
  depends_on = [azapi_resource.snet_nodes]
}

# AKS Automatic managed system node pools (hostedSystemProfile): dedicated,
# at least /26, not delegated, separate from the node subnet. Same NSG
# (the ingress load balancer may target system nodes) and NAT Gateway.
resource "azapi_resource" "snet_system" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "snet-aks-system"
  parent_id = azapi_resource.vnet.id

  body = {
    properties = {
      addressPrefix        = "10.20.4.64/26"
      networkSecurityGroup = { id = azapi_resource.nsg_nodes.id }
      natGateway           = { id = azapi_resource.natgw.id }
    }
  }

  depends_on = [azapi_resource.snet_apiserver]
}
