# =============================================================================
# General
# =============================================================================

variable "location" {
  description = "Azure region. Must support AKS Automatic (API Server VNet Integration GA, >= 3 AZs)."
  type        = string
  default     = "swedencentral"
}

variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
  default     = "rg-aks-automatic"
}

variable "cluster_name" {
  description = "Name of the AKS Automatic cluster."
  type        = string
  default     = "aks-automatic"
}

variable "kubernetes_version" {
  description = "Kubernetes version. Leave null to use the latest default."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    environment = "demo"
    managedBy   = "terraform"
  }
}

# =============================================================================
# BYO VNet
# =============================================================================

variable "enable_byo_vnet" {
  description = <<-EOT
    When true (default), the AKS cluster is deployed into a custom VNet (BYO VNet).
    This is always true for ALZ Corp. The distinction is who creates the networking:
      - true + external subnet IDs set     : ALZ Corp vending mode. The platform pipeline
        pre-provisions the spoke VNet, subnets, NSG, UDR, and peering via AVNM IPAM.
        This module consumes the subnet IDs without creating networking resources.
      - true + no external subnet IDs set  : Standalone mode. This module creates the spoke
        VNet, subnets, NSG, and route table in network.tf.
      - false                              : AKS-managed VNet. AKS creates its own network.
        Not suitable for ALZ Corp.
  EOT
  type        = bool
  default     = true
}

# =============================================================================
# External Subnet IDs (subscription vending / AVNM IPAM mode)
#
# When the platform team pre-provisions spoke VNets via the ALZ subscription
# vending module with AVNM IPAM, set these variables to the resource IDs of
# the pre-created subnets. The module will skip all network.tf resources and
# use these IDs directly. Subnet delegations, NSG, and UDR must be configured
# in the vending pipeline.
# =============================================================================

variable "external_node_subnet_id" {
  description = "Resource ID of a pre-provisioned node subnet. When set, network.tf resources are skipped."
  type        = string
  default     = null
}

variable "external_apiserver_subnet_id" {
  description = "Resource ID of a pre-provisioned API server subnet (must be delegated to Microsoft.ContainerService/managedClusters)."
  type        = string
  default     = null
}

variable "external_pe_subnet_id" {
  description = "Resource ID of a pre-provisioned private endpoint subnet. When set, PE subnet creation is skipped but PEs for ACR/KV are still created in this subnet."
  type        = string
  default     = null
}

variable "vnet_name" {
  description = "Name of the virtual network (BYO VNet)."
  type        = string
  default     = "vnet-aks-automatic"
}

variable "vnet_address_space" {
  description = "Address space for the VNet."
  type        = string
  default     = "10.10.0.0/16"

  validation {
    condition     = can(cidrhost(var.vnet_address_space, 0))
    error_message = "vnet_address_space must be a valid CIDR block (e.g. 10.10.0.0/16)."
  }
}

variable "node_subnet_name" {
  description = "Name of the node subnet."
  type        = string
  default     = "snet-aks-nodes"
}

variable "node_subnet_address_prefix" {
  description = "Address prefix for the node subnet. Size depends on expected node count."
  type        = string
  default     = "10.10.0.0/22" # 1,022 usable IPs

  validation {
    condition     = can(cidrhost(var.node_subnet_address_prefix, 0))
    error_message = "node_subnet_address_prefix must be a valid CIDR block (e.g. 10.10.0.0/22)."
  }
}

variable "apiserver_subnet_name" {
  description = "Name of the API server VNet integration subnet. Minimum /28."
  type        = string
  default     = "snet-aks-apiserver"
}

variable "apiserver_subnet_address_prefix" {
  description = "Address prefix for the API server subnet. Minimum /28."
  type        = string
  default     = "10.10.4.0/28"

  validation {
    condition     = can(cidrhost(var.apiserver_subnet_address_prefix, 0))
    error_message = "apiserver_subnet_address_prefix must be a valid CIDR block (e.g. 10.10.4.0/28)."
  }

  validation {
    condition     = tonumber(split("/", var.apiserver_subnet_address_prefix)[1]) <= 28
    error_message = "apiserver_subnet_address_prefix must be /28 or larger (smaller prefix number)."
  }
}

variable "pe_subnet_name" {
  description = "Name of the private endpoint subnet."
  type        = string
  default     = "snet-private-endpoints"
}

variable "pe_subnet_address_prefix" {
  description = "Address prefix for the private endpoint subnet."
  type        = string
  default     = "10.10.12.0/24"

  validation {
    condition     = can(cidrhost(var.pe_subnet_address_prefix, 0))
    error_message = "pe_subnet_address_prefix must be a valid CIDR block (e.g. 10.10.12.0/24)."
  }
}

# =============================================================================
# Supporting Services (ACR, Key Vault)
#
# In ALZ Corp, these services are accessed exclusively via Private Endpoints.
# Public access is disabled. The Private DNS Zones (privatelink.azurecr.io,
# privatelink.vaultcore.azure.net) must be pre-created in the connectivity
# subscription by the platform team.
# =============================================================================

variable "create_acr" {
  description = "When true, creates a Premium ACR with private endpoint, DNS zone group, and AcrPull role assignment. Requires a PE subnet (BYO VNet or external)."
  type        = bool
  default     = false
}

variable "acr_name" {
  description = "Name of the Azure Container Registry. Must be globally unique, 5-50 alphanumeric characters."
  type        = string
  default     = null

  validation {
    condition     = var.acr_name == null || can(regex("^[a-z0-9]{5,50}$", var.acr_name))
    error_message = "acr_name must be 5-50 lowercase letters and numbers only (no hyphens or uppercase)."
  }
}

variable "acr_private_dns_zone_id" {
  description = <<-EOT
    Resource ID of the privatelink.azurecr.io Private DNS Zone in the connectivity subscription.
    Required for Private Endpoint DNS registration. Set to null to skip DNS zone group creation
    (PE will still be created but DNS records must be managed manually).
  EOT
  type        = string
  default     = null
}

variable "create_keyvault" {
  description = "When true, creates a Key Vault with RBAC auth, private endpoint, DNS zone group, and Certificate User role assignment for App Routing TLS. Requires a PE subnet (BYO VNet or external)."
  type        = bool
  default     = false
}

variable "keyvault_name" {
  description = "Name of the Azure Key Vault. Must be globally unique, 3-24 alphanumeric characters and hyphens."
  type        = string
  default     = null

  validation {
    condition     = var.keyvault_name == null || can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.keyvault_name))
    error_message = "keyvault_name must be 3-24 characters: start with a letter, alphanumeric and hyphens only, end with alphanumeric."
  }
}

variable "kv_private_dns_zone_id" {
  description = <<-EOT
    Resource ID of the privatelink.vaultcore.azure.net Private DNS Zone in the connectivity subscription.
    Required for Private Endpoint DNS registration. Set to null to skip DNS zone group creation.
  EOT
  type        = string
  default     = null
}

# =============================================================================
# Egress
# =============================================================================

variable "egress_type" {
  description = <<-EOT
    Outbound (egress) type for BYO VNet or external subnet deployments:
      - "userDefinedRouting"     : Default for Corp. Routes 0.0.0.0/0 to the hub Azure Firewall via UDR.
      - "loadBalancer"           : Uses the AKS Standard Load Balancer for SNAT. Dev/test only.
    Ignored when using managed VNet (always managedNATGateway).
    NAT Gateway is not offered as an option because ALZ Corp requires centralised
    egress control through the hub firewall.
  EOT
  type        = string
  default     = "userDefinedRouting"

  validation {
    condition     = contains(["userDefinedRouting", "loadBalancer"], var.egress_type)
    error_message = "egress_type must be one of: userDefinedRouting, loadBalancer."
  }
}

variable "firewall_private_ip" {
  description = "Private IP of the hub NVA/Azure Firewall for UDR egress. Required when egress_type = userDefinedRouting (the default)."
  type        = string
  default     = null
}

# =============================================================================
# Network CIDRs (Overlay)
# =============================================================================

variable "pod_cidr" {
  description = "CIDR for the pod overlay network."
  type        = string
  default     = "10.244.0.0/16"

  validation {
    condition     = can(cidrhost(var.pod_cidr, 0))
    error_message = "pod_cidr must be a valid CIDR block (e.g. 10.244.0.0/16)."
  }
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services."
  type        = string
  default     = "10.245.0.0/16"

  validation {
    condition     = can(cidrhost(var.service_cidr, 0))
    error_message = "service_cidr must be a valid CIDR block (e.g. 10.245.0.0/16)."
  }
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service. Must be within service_cidr."
  type        = string
  default     = "10.245.0.10"

  validation {
    condition     = can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.dns_service_ip))
    error_message = "dns_service_ip must be a valid IPv4 address without a CIDR mask."
  }
}

# =============================================================================
# Ingress
# =============================================================================

variable "dns_zone_resource_ids" {
  description = <<-EOT
    List of Azure DNS zone resource IDs for automatic DNS record management
    with Application Routing (managed NGINX). Supports both public and private zones.
    Example: ["/subscriptions/.../providers/Microsoft.Network/dnsZones/example.com"]
  EOT
  type        = list(string)
  default     = []
}

variable "enable_service_mesh" {
  description = "Enable the Istio-based service mesh add-on (includes Istio ingress gateway)."
  type        = bool
  default     = false
}

# =============================================================================
# Private Cluster
# =============================================================================

variable "enable_private_cluster" {
  description = "When true (default for Corp), the API server is accessible only via the VNet-integrated ILB private IP. Public DNS entries are removed."
  type        = bool
  default     = true
}

variable "private_dns_zone_id" {
  description = <<-EOT
    Resource ID of a pre-created private DNS zone for the private API server FQDN.
    Only used when enable_private_cluster = true.
      - null (default) : AKS creates a private.<region>.azmk8s.io zone in the node resource group (privateDNSZone = "system").
      - "<resource-id>": Use a pre-created zone, e.g. in the ALZ connectivity subscription.
        Format: private.<region>.azmk8s.io.
        Requires user_assigned_identity_id to be set.
      - "none"         : No private DNS zone. The module automatically enables the
        public FQDN in this case so the API server remains reachable.
  EOT
  type        = string
  default     = null
}

variable "user_assigned_identity_id" {
  description = "Resource ID of a pre-created UserAssigned managed identity. Required when private_dns_zone_id is a custom resource ID. The identity must have Private DNS Zone Contributor on the referenced zone."
  type        = string
  default     = null
}

variable "authorized_ip_ranges" {
  description = "CIDR ranges authorised to access the API server. Only applies to the public endpoint; ignored when private cluster is enabled."
  type        = list(string)
  default     = []
}

# =============================================================================
# Monitoring
# =============================================================================

variable "enable_prometheus" {
  description = "Enable Azure Managed Prometheus metrics collection."
  type        = bool
  default     = true
}

variable "enable_container_insights" {
  description = "Enable Container Insights for log collection via azureMonitorProfile. Requires log_analytics_workspace_id."
  type        = bool
  default     = false
}

# =============================================================================
# Security
# =============================================================================

variable "image_cleaner_interval_hours" {
  description = "Interval (hours) for the Image Cleaner to scan and remove unused vulnerable images. Default 168 hours (7 days)."
  type        = number
  default     = 168

  validation {
    condition     = var.image_cleaner_interval_hours >= 24
    error_message = "image_cleaner_interval_hours must be >= 24."
  }
}

# =============================================================================
# Upgrades
# =============================================================================

variable "upgrade_channel" {
  description = "Cluster auto-upgrade channel: rapid, stable, patch, node-image."
  type        = string
  default     = "stable"

  validation {
    condition     = contains(["rapid", "stable", "patch", "node-image"], var.upgrade_channel)
    error_message = "upgrade_channel must be one of: rapid, stable, patch, node-image."
  }
}

variable "node_os_upgrade_channel" {
  description = "Node OS upgrade channel: NodeImage, SecurityPatch, Unmanaged, None."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["NodeImage", "SecurityPatch", "Unmanaged", "None"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be one of: NodeImage, SecurityPatch, Unmanaged, None."
  }
}

variable "maintenance_window" {
  description = <<-EOT
    Maintenance window configuration for the AKS cluster. Controls when
    auto-upgrades and node OS updates are applied. Set to null (default)
    to let AKS choose the maintenance window.
  EOT
  type = object({
    day_of_week    = optional(string, "Wednesday")
    interval_weeks = optional(number, 1)
    duration_hours = optional(number, 4)
    start_time     = optional(string, "03:00")
    utc_offset     = optional(string, "+00:00")
    not_allowed_dates = optional(list(object({
      start = string
      end   = string
    })), [])
  })
  default = null
}

# =============================================================================
# HTTP Proxy
# =============================================================================

variable "http_proxy_config" {
  description = <<-EOT
    HTTP proxy configuration for the AKS cluster. When set, both nodes and pods
    are configured with the proxy environment variables. The trustedCa field
    accepts a base64-encoded PEM CA certificate bundle for TLS-intercepting
    proxies. Set to null (default) to disable HTTP proxy.
  EOT
  type = object({
    http_proxy  = optional(string)
    https_proxy = optional(string)
    no_proxy    = optional(list(string), [])
    trusted_ca  = optional(string)
  })
  default = null
}

# =============================================================================
# Security (optional features)
# =============================================================================

variable "enable_defender" {
  description = "Enable Microsoft Defender for Containers for runtime threat detection and vulnerability scanning."
  type        = bool
  default     = false
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace for Defender for Containers and diagnostic settings. Required when enable_defender = true."
  type        = string
  default     = null
}

variable "enable_cost_analysis" {
  description = "Enable AKS cost analysis for per-namespace and per-workload cost breakdown in Azure Cost Management."
  type        = bool
  default     = false
}

variable "enable_purge_protection" {
  description = "Enable purge protection on the Key Vault. When true, the vault cannot be permanently deleted during the soft-delete retention period. This setting is irreversible."
  type        = bool
  default     = true
}

# =============================================================================
# Azure Key Vault KMS (etcd encryption)
# =============================================================================

variable "enable_kms" {
  description = "Enable Azure Key Vault KMS for customer-managed key encryption of etcd. Requires a Key Vault with a key and appropriate RBAC."
  type        = bool
  default     = false
}

variable "kms_key_id" {
  description = "Full URI of the Key Vault key to use for KMS etcd encryption (e.g. https://<vault>.vault.azure.net/keys/<key>/<version>). Required when enable_kms = true."
  type        = string
  default     = null
}

variable "kms_key_vault_network_access" {
  description = "Network access mode for the KMS Key Vault: Private or Public."
  type        = string
  default     = "Private"

  validation {
    condition     = contains(["Private", "Public"], var.kms_key_vault_network_access)
    error_message = "kms_key_vault_network_access must be Private or Public."
  }
}

variable "kms_key_vault_resource_id" {
  description = "Resource ID of the Key Vault containing the KMS key. Required when enable_kms = true and kms_key_vault_network_access = Private."
  type        = string
  default     = null
}

variable "acr_zone_redundancy_enabled" {
  description = "Enable zone redundancy for ACR. Requires Premium SKU and a region with availability zones."
  type        = bool
  default     = true
}
