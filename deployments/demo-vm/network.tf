# =============================================================================
# Demo VM network
#
# - No public IP on the VM. Access only through Azure Bastion (Standard SKU,
#   native client tunneling). The landing zone denies management ports from
#   the internet (Deny-MgmtPorts-Internet) and subnets without an NSG
#   (Deny-Subnet-Without-Nsg); both are met here, not exempted.
# - The VM subnet has default outbound access disabled; a NAT Gateway gives
#   it explicit egress so winget can download Copilot CLI and Squad.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  location = "swedencentral"
  rg_id    = "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/rg-demo-vm-online"
  name     = "demo-copilot"

  bastion_prefix = "10.30.0.0/26"
  vm_prefix      = "10.30.0.64/27"

  tags = {
    Environment        = "Demo"
    Owner              = "martin.opedal@microsoft.com"
    DataClassification = "Internal"
    Workload           = "Copilot-Squad-Demo-VM"
    lifecycle          = "demo"
    purgeable          = "true"
    expiry             = "2026-10-31"
  }
}

resource "azapi_resource" "vnet" {
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-${local.name}"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      addressSpace = { addressPrefixes = ["10.30.0.0/24"] }
    }
  }
}

# Required Bastion NSG rules (learn.microsoft.com/azure/bastion/bastion-nsg).
resource "azapi_resource" "nsg_bastion" {
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-${local.name}-bastion"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      securityRules = [
        { name = "AllowHttpsInbound", properties = { priority = 120, direction = "Inbound", access = "Allow", protocol = "Tcp", sourceAddressPrefix = "Internet", sourcePortRange = "*", destinationAddressPrefix = "*", destinationPortRange = "443" } },
        { name = "AllowGatewayManagerInbound", properties = { priority = 130, direction = "Inbound", access = "Allow", protocol = "Tcp", sourceAddressPrefix = "GatewayManager", sourcePortRange = "*", destinationAddressPrefix = "*", destinationPortRange = "443" } },
        { name = "AllowAzureLoadBalancerInbound", properties = { priority = 140, direction = "Inbound", access = "Allow", protocol = "Tcp", sourceAddressPrefix = "AzureLoadBalancer", sourcePortRange = "*", destinationAddressPrefix = "*", destinationPortRange = "443" } },
        { name = "AllowBastionHostCommunication", properties = { priority = 150, direction = "Inbound", access = "Allow", protocol = "*", sourceAddressPrefix = "VirtualNetwork", sourcePortRange = "*", destinationAddressPrefix = "VirtualNetwork", destinationPortRanges = ["8080", "5701"] } },
        { name = "AllowSshRdpOutbound", properties = { priority = 100, direction = "Outbound", access = "Allow", protocol = "*", sourceAddressPrefix = "*", sourcePortRange = "*", destinationAddressPrefix = "VirtualNetwork", destinationPortRanges = ["22", "3389"] } },
        { name = "AllowAzureCloudOutbound", properties = { priority = 110, direction = "Outbound", access = "Allow", protocol = "Tcp", sourceAddressPrefix = "*", sourcePortRange = "*", destinationAddressPrefix = "AzureCloud", destinationPortRange = "443" } },
        { name = "AllowBastionCommunication", properties = { priority = 120, direction = "Outbound", access = "Allow", protocol = "*", sourceAddressPrefix = "VirtualNetwork", sourcePortRange = "*", destinationAddressPrefix = "VirtualNetwork", destinationPortRanges = ["8080", "5701"] } },
        { name = "AllowHttpOutbound", properties = { priority = 130, direction = "Outbound", access = "Allow", protocol = "*", sourceAddressPrefix = "*", sourcePortRange = "*", destinationAddressPrefix = "Internet", destinationPortRange = "80" } },
      ]
    }
  }
}

# VM subnet: RDP only from the Bastion subnet; everything else inbound is
# denied explicitly (above the default VirtualNetwork allow rule).
resource "azapi_resource" "nsg_vm" {
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-${local.name}-vm"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {
      securityRules = [
        { name = "Allow-Bastion-RDP", properties = { priority = 100, direction = "Inbound", access = "Allow", protocol = "Tcp", sourceAddressPrefix = local.bastion_prefix, sourcePortRange = "*", destinationAddressPrefix = "*", destinationPortRange = "3389" } },
        { name = "Deny-All-Other-Inbound", properties = { priority = 4000, direction = "Inbound", access = "Deny", protocol = "*", sourceAddressPrefix = "*", sourcePortRange = "*", destinationAddressPrefix = "*", destinationPortRange = "*" } },
      ]
    }
  }
}

resource "azapi_resource" "pip_nat" {
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  name      = "pip-${local.name}-natgw"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  response_export_values = ["properties.ipAddress"]

  body = {
    sku        = { name = "Standard" }
    properties = { publicIPAllocationMethod = "Static", publicIPAddressVersion = "IPv4" }
  }
}

resource "azapi_resource" "natgw" {
  type      = "Microsoft.Network/natGateways@2024-05-01"
  name      = "natgw-${local.name}"
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

resource "azapi_resource" "snet_bastion" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "AzureBastionSubnet"
  parent_id = azapi_resource.vnet.id

  body = {
    properties = {
      addressPrefix        = local.bastion_prefix
      networkSecurityGroup = { id = azapi_resource.nsg_bastion.id }
    }
  }
}

resource "azapi_resource" "snet_vm" {
  type      = "Microsoft.Network/virtualNetworks/subnets@2024-05-01"
  name      = "snet-vm"
  parent_id = azapi_resource.vnet.id

  body = {
    properties = {
      addressPrefix         = local.vm_prefix
      defaultOutboundAccess = false
      networkSecurityGroup  = { id = azapi_resource.nsg_vm.id }
      natGateway            = { id = azapi_resource.natgw.id }
    }
  }

  # Subnet writes on the same VNet must not run concurrently.
  depends_on = [azapi_resource.snet_bastion]
}

resource "azapi_resource" "pip_bastion" {
  type      = "Microsoft.Network/publicIPAddresses@2024-05-01"
  name      = "pip-${local.name}-bastion"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    sku        = { name = "Standard" }
    properties = { publicIPAllocationMethod = "Static", publicIPAddressVersion = "IPv4" }
  }
}

# Standard SKU for native-client RDP (az network bastion rdp), which gives a
# full-screen RDP session that is comfortable to present.
resource "azapi_resource" "bastion" {
  type      = "Microsoft.Network/bastionHosts@2024-05-01"
  name      = "bas-${local.name}"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    sku = { name = "Standard" }
    properties = {
      enableTunneling     = true
      disableCopyPaste    = false
      enableFileCopy      = false
      enableIpConnect     = false
      enableShareableLink = false
      ipConfigurations = [{
        name = "ipconfig"
        properties = {
          subnet          = { id = azapi_resource.snet_bastion.id }
          publicIPAddress = { id = azapi_resource.pip_bastion.id }
        }
      }]
    }
  }

  timeouts {
    create = "45m"
    delete = "45m"
  }

  # Serialize VNet writes: Bastion updates AzureBastionSubnet, so it must not
  # run while snet-vm is still being written (AnotherOperationInProgress).
  depends_on = [azapi_resource.snet_vm]

  retry = {
    error_message_regex  = ["AnotherOperationInProgress", "RetryableError", "ReferencedResourceNotProvisioned"]
    interval_seconds     = 20
    max_interval_seconds = 120
  }
}
