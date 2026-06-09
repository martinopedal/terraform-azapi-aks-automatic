# =============================================================================
# General
# =============================================================================

variable "location" {
  description = "Azure region. Must support AKS Automatic (API Server VNet Integration GA, >= 3 AZs)."
  type        = string
  default     = "swedencentral"

  validation {
    condition     = length(var.location) > 0
    error_message = "location must not be empty."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group."
  type        = string
  default     = "rg-aks-automatic"

  validation {
    condition     = can(regex("^[a-zA-Z0-9._()-]{1,90}$", var.resource_group_name))
    error_message = "resource_group_name must be 1-90 characters, alphanumeric, periods, underscores, hyphens, and parentheses."
  }
}

variable "create_resource_group" {
  description = "When true, create the resource group. When false, deploy into an existing resource group with resource_group_name in the current subscription."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the AKS Automatic cluster. Must be 2-63 characters, alphanumeric and hyphens only, start and end with alphanumeric."
  type        = string
  default     = "aks-automatic"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,61}[a-zA-Z0-9]$", var.cluster_name))
    error_message = "cluster_name must be 2-63 characters, start and end with alphanumeric, contain only alphanumeric characters and hyphens."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version. Leave null to use the latest default."
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^\\d+\\.\\d+(\\.\\d+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must be in format X.Y or X.Y.Z (e.g. 1.30 or 1.30.1)."
  }
}

variable "system_node_vm_size" {
  description = "VM size for the AKS Automatic system pool. Default uses the smallest reliable D-series size for NAP default pools; B-series is intentionally not the default."
  type        = string
  default     = "Standard_D2s_v5"

  validation {
    condition     = can(regex("^Standard_[A-Za-z0-9]+[A-Za-z0-9_]*$", var.system_node_vm_size))
    error_message = "system_node_vm_size must be an Azure VM SKU name such as Standard_D2s_v5."
  }
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

  validation {
    condition     = var.external_node_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.external_node_subnet_id))
    error_message = "external_node_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "external_apiserver_subnet_id" {
  description = "Resource ID of a pre-provisioned API server subnet. MUST be delegated to Microsoft.ContainerService/managedClusters, MUST be dedicated (minimum /28), and MUST NOT have a Route Table attached. Required when external_node_subnet_id is set."
  type        = string
  default     = null

  validation {
    condition     = var.external_apiserver_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.external_apiserver_subnet_id))
    error_message = "external_apiserver_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "external_pe_subnet_id" {
  description = "Resource ID of a pre-provisioned private endpoint subnet. When set, PE subnet creation is skipped but PEs for ACR/KV are still created in this subnet."
  type        = string
  default     = null

  validation {
    condition     = var.external_pe_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.external_pe_subnet_id))
    error_message = "external_pe_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "external_agc_subnet_id" {
  description = "Deprecated alias for app_gateway_for_containers_subnet_id. Resource ID of a pre-provisioned AGC subnet delegated to Microsoft.ServiceNetworking/trafficControllers."
  type        = string
  default     = null

  validation {
    condition     = var.external_agc_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.external_agc_subnet_id))
    error_message = "external_agc_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "app_gateway_for_containers_subnet_id" {
  description = "Resource ID of the dedicated /24 Application Gateway for Containers association subnet delegated to Microsoft.ServiceNetworking/trafficControllers. Required when AGC is enabled in external-subnet/BYO-RG mode."
  type        = string
  default     = null

  validation {
    condition     = var.app_gateway_for_containers_subnet_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.app_gateway_for_containers_subnet_id))
    error_message = "app_gateway_for_containers_subnet_id must be a valid Azure subnet resource ID."
  }
}

variable "vnet_name" {
  description = "Name of the virtual network (BYO VNet)."
  type        = string
  default     = "vnet-aks-automatic"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}[a-zA-Z0-9_]$", var.vnet_name))
    error_message = "vnet_name must be 2-64 characters, alphanumeric, periods, underscores, and hyphens."
  }
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

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_]$", var.node_subnet_name))
    error_message = "node_subnet_name must be 2-80 characters, alphanumeric, periods, underscores, and hyphens."
  }
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

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_]$", var.apiserver_subnet_name))
    error_message = "apiserver_subnet_name must be 2-80 characters, alphanumeric, periods, underscores, and hyphens."
  }
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

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_]$", var.pe_subnet_name))
    error_message = "pe_subnet_name must be 2-80 characters, alphanumeric, periods, underscores, and hyphens."
  }
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

variable "agc_subnet_name" {
  description = "Name of the Application Gateway for Containers subnet created in standalone network mode."
  type        = string
  default     = "snet-agc"

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_]$", var.agc_subnet_name))
    error_message = "agc_subnet_name must be 2-80 characters, alphanumeric, periods, underscores, and hyphens."
  }
}

variable "agc_subnet_address_prefix" {
  description = "Address prefix for the Application Gateway for Containers subnet. AGC with CNI Overlay requires exactly /24."
  type        = string
  default     = "10.10.8.0/24"

  validation {
    condition     = can(cidrhost(var.agc_subnet_address_prefix, 0))
    error_message = "agc_subnet_address_prefix must be a valid CIDR block (e.g. 10.10.8.0/24)."
  }

  validation {
    condition     = tonumber(split("/", var.agc_subnet_address_prefix)[1]) == 24
    error_message = "agc_subnet_address_prefix must be exactly /24 for Application Gateway for Containers with CNI Overlay."
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

  validation {
    condition     = var.acr_private_dns_zone_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/[^/]+$", var.acr_private_dns_zone_id))
    error_message = "acr_private_dns_zone_id must be a valid Azure Private DNS Zone resource ID."
  }
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

  validation {
    condition     = var.kv_private_dns_zone_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/[^/]+$", var.kv_private_dns_zone_id))
    error_message = "kv_private_dns_zone_id must be a valid Azure Private DNS Zone resource ID."
  }
}

# =============================================================================
# Egress
# =============================================================================

variable "egress_type" {
  description = <<-EOT
    Outbound (egress) type for BYO VNet or external subnet deployments:
      - "none"                   : Cluster does not configure egress; relies on pre-existing UDR/NAT on the subnet.
                                   Required for AKS Automatic (sku=Automatic) with BYO VNet, because the AKS RP
                                   does not support userDefinedRouting with Node Auto-Provisioning.
      - "userDefinedRouting"     : Routes 0.0.0.0/0 to the hub Azure Firewall via UDR. Standard/Base SKU only.
      - "loadBalancer"           : Uses the AKS Standard Load Balancer for SNAT. Dev/test only.
    Ignored when using managed VNet (always managedNATGateway).
    NAT Gateway is not offered as an option because ALZ Corp requires centralised
    egress control through the hub firewall.
  EOT
  type        = string
  default     = "userDefinedRouting"

  validation {
    condition     = contains(["none", "userDefinedRouting", "loadBalancer"], var.egress_type)
    error_message = "egress_type must be one of: none, userDefinedRouting, loadBalancer."
  }
}

variable "firewall_private_ip" {
  description = "Private IP of the hub NVA/Azure Firewall for UDR egress. Required when egress_type = userDefinedRouting and the module manages the network (create_network path)."
  type        = string
  default     = null

  validation {
    condition     = var.firewall_private_ip == null || can(regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$", var.firewall_private_ip))
    error_message = "firewall_private_ip must be a valid IPv4 address."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "bootstrap_acr_id" {
  description = <<-EOT
    Resource ID of a pre-existing ACR for bootstrap artifact caching. Required
    when egress_type = "none" with BYO VNet (AKS-managed ACR only works with
    AKS-managed VNet). The ACR should be reachable from the node subnet (via PE
    or hub firewall rule).
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.bootstrap_acr_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ContainerRegistry/registries/[^/]+$", var.bootstrap_acr_id))
    error_message = "bootstrap_acr_id must be a valid ACR resource ID."
  }
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
    condition     = can(cidrhost("${var.dns_service_ip}/32", 0))
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

variable "enable_app_gateway_for_containers" {
  description = "Enable Application Gateway for Containers ingress: installs the ALB Controller extension and creates the Traffic Controller plus subnet association. AGC is the canonical/default ingress posture."
  type        = bool
  default     = true
}

variable "app_gateway_for_containers_name" {
  description = "Name of the Microsoft.ServiceNetworking/trafficControllers resource. Defaults to <cluster_name>-agc."
  type        = string
  default     = null

  validation {
    condition     = var.app_gateway_for_containers_name == null || can(regex("^[A-Za-z0-9]([A-Za-z0-9-_.]{0,62}[A-Za-z0-9])?$", var.app_gateway_for_containers_name))
    error_message = "app_gateway_for_containers_name must be 1-64 characters and match the trafficControllers name rules."
  }
}

variable "app_gateway_for_containers_frontend_name" {
  description = "Name of the AGC frontend child resource. Defaults to frontend."
  type        = string
  default     = "frontend"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-_.]{0,62}[A-Za-z0-9])?$", var.app_gateway_for_containers_frontend_name))
    error_message = "app_gateway_for_containers_frontend_name must be 1-64 characters and match the trafficControllers/frontend name rules."
  }
}

variable "app_gateway_for_containers_association_name" {
  description = "Name of the AGC subnet association child resource. Defaults to association."
  type        = string
  default     = "association"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9-_.]{0,62}[A-Za-z0-9])?$", var.app_gateway_for_containers_association_name))
    error_message = "app_gateway_for_containers_association_name must be 1-64 characters and match the trafficControllers/associations name rules."
  }
}

variable "enable_agc_waf" {
  description = <<-EOT
    Enable Azure WAF Policy for AGC (OWASP managed ruleset).
    
    **Regional availability**: AGC WAF is preview and not available in all regions.
    Verified as NOT available in Sweden Central as of 2026-06-08.
    
    If enabled in an unsupported region, Terraform will fail with a region error.
    Check availability: az provider show -n Microsoft.Network --query "resourceTypes[?resourceType=='ApplicationGatewayWebApplicationFirewallPolicies'].locations"
  EOT
  type        = bool
  default     = false
}

variable "agc_waf_mode" {
  description = "WAF mode: Prevention (blocks malicious requests) or Detection (logs only). Ignored when enable_agc_waf = false."
  type        = string
  default     = "Prevention"

  validation {
    condition     = contains(["Prevention", "Detection"], var.agc_waf_mode)
    error_message = "agc_waf_mode must be 'Prevention' or 'Detection'."
  }
}

variable "enable_managed_nginx" {
  description = "Enable the AKS managed NGINX Application Routing add-on. Ignored when enable_app_gateway_for_containers = true so AGC remains primary."
  type        = bool
  default     = false
}

variable "enable_service_mesh" {
  description = "Enable the Istio-based service mesh add-on (includes Istio ingress gateway)."
  type        = bool
  default     = false
}

variable "enable_acns" {
  description = "Enable Advanced Container Networking Services (ACNS). Provides container network observability, FQDN-based network policies, and multi-network support. Paid add-on."
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

  validation {
    condition     = var.private_dns_zone_id == null || var.private_dns_zone_id == "system" || var.private_dns_zone_id == "none" || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/privateDnsZones/[^/]+$", var.private_dns_zone_id))
    error_message = "private_dns_zone_id must be null, 'system', 'none', or a valid Azure Private DNS Zone resource ID."
  }
}

variable "user_assigned_identity_id" {
  description = "Resource ID of a pre-created UserAssigned managed identity. Required when private_dns_zone_id is a custom resource ID. The identity must have Private DNS Zone Contributor on the referenced zone."
  type        = string
  default     = null

  validation {
    condition     = var.user_assigned_identity_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.ManagedIdentity/userAssignedIdentities/[^/]+$", var.user_assigned_identity_id))
    error_message = "user_assigned_identity_id must be a valid Azure UserAssigned managed identity resource ID."
  }
}

variable "authorized_ip_ranges" {
  description = "CIDR ranges authorised to access the API server. Only applies to the public endpoint; ignored when private cluster is enabled."
  type        = list(string)
  default     = []
}

variable "cluster_admin_object_ids" {
  description = "Microsoft Entra group object IDs granted AKS cluster-admin through aadProfile.adminGroupObjectIDs. Leave empty to manage Azure RBAC role assignments externally."
  type        = list(string)
  default     = []
}

# =============================================================================
# Monitoring
# =============================================================================

variable "enable_prometheus" {
  description = "Enable Azure Managed Prometheus metrics collection. Disabled by default to keep the cheapest cluster footprint."
  type        = bool
  default     = false
}

variable "enable_container_insights" {
  description = "Enable Container Insights for log collection via azureMonitorProfile. Requires log_analytics_workspace_id."
  type        = bool
  default     = false
}

variable "azure_monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor workspace for Prometheus metrics and alert rules. Required when enable_prometheus_alerts = true."
  type        = string
  default     = null

  validation {
    condition     = var.azure_monitor_workspace_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", var.azure_monitor_workspace_id))
    error_message = "azure_monitor_workspace_id must be a valid Azure resource ID."
  }
}

variable "enable_prometheus_alerts" {
  description = "Create recommended Prometheus alert rules for AKS cluster health monitoring. Requires azure_monitor_workspace_id."
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

  validation {
    condition     = var.log_analytics_workspace_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.OperationalInsights/workspaces/[^/]+$", var.log_analytics_workspace_id))
    error_message = "log_analytics_workspace_id must be a valid Log Analytics workspace resource ID."
  }
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

  validation {
    condition     = var.kms_key_id == null || can(regex("^https://[^/]+\\.vault\\.azure\\.net/keys/[^/]+/[a-z0-9]+$", var.kms_key_id))
    error_message = "kms_key_id must be a valid Key Vault key URI (e.g. https://<vault>.vault.azure.net/keys/<key>/<version>)."
  }
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

  validation {
    condition     = var.kms_key_vault_resource_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.KeyVault/vaults/[^/]+$", var.kms_key_vault_resource_id))
    error_message = "kms_key_vault_resource_id must be a valid Azure Key Vault resource ID."
  }
}

variable "acr_zone_redundancy_enabled" {
  description = "Enable zone redundancy for ACR. Requires Premium SKU and a region with availability zones."
  type        = bool
  default     = true
}

# =============================================================================
# ALB Ingress Controller (Helm-based with Workload Identity)
# =============================================================================

variable "enable_alb_helm_controller" {
  description = <<-EOT
    Enable the ALB Controller via Helm (oci://mcr.microsoft.com/application-lb/charts/alb-controller)
    with a dedicated user-assigned managed identity and federated credential for workload identity.
    
    When true:
      - Creates uami-alb-* managed identity
      - Creates federated credential for azure-alb-system/alb-controller-sa ServiceAccount
      - Assigns "AppGw for Containers Configuration Manager" role on the AGC Traffic Controller
      - Assigns "Network Contributor" role on the AGC subnet
    
    This is the canonical approach for AGC + Workload Identity. The alternative is the
    AKS-managed extension (azapi_resource.alb_controller_extension in agc.tf), which uses
    a system-assigned identity automatically wired by the AKS RP. Both work; Helm gives
    more control over version and configuration.
  EOT
  type        = bool
  default     = true
}

variable "alb_controller_identity_name" {
  description = "Name of the user-assigned managed identity for the ALB Controller. Defaults to uami-alb-<cluster_name>."
  type        = string
  default     = null

  validation {
    condition     = var.alb_controller_identity_name == null || can(regex("^[a-zA-Z0-9-_]{3,128}$", var.alb_controller_identity_name))
    error_message = "alb_controller_identity_name must be 3-128 characters, alphanumeric, hyphens, and underscores only."
  }
}

# =============================================================================
# Policy Exemptions
# =============================================================================

variable "enable_policy_exemption_mcsb_k8s" {
  description = <<-EOT
    Enable policy exemption for Deploy-MCSB2-Monitoring (Microsoft Cloud Security Benchmark)
    on the resource group. The MCSB initiative includes the "allowed container images" policy
    with an empty regex ^(.+){0}$ that denies ALL images cluster-wide.
    
    This exemption is demo-scoped (enforced to rg-sreagt-dmo-swc-001 in the resource lifecycle)
    and expires in 30 days. The estate-wide fix (correcting the regex at the alz management
    group) is tracked in alz-avm-tf-demo/alz-prod governance baseline.
  EOT
  type        = bool
  default     = false
}
