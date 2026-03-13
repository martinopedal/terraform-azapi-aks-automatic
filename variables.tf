# =============================================================================
# General
# =============================================================================

variable "location" {
  description = "Azure region. Must support AKS Automatic (API Server VNet Integration GA, ≥3 AZs)."
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
    When true, a VNet, subnets, NSG, and egress resources are created and the
    AKS cluster is deployed into the custom network. When false, AKS creates
    and manages its own VNet with a managed NAT Gateway.
  EOT
  type        = bool
  default     = true
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
}

# =============================================================================
# Egress
# =============================================================================

variable "egress_type" {
  description = <<-EOT
    Outbound (egress) type for BYO VNet deployments:
      - "userAssignedNATGateway" : Recommended. Creates a NAT Gateway + Public IP.
      - "loadBalancer"           : Uses the AKS Standard Load Balancer for SNAT.
      - "userDefinedRouting"     : Routes 0.0.0.0/0 to an NVA/Firewall via UDR.
    Ignored when enable_byo_vnet = false (managed VNet always uses managedNATGateway).
  EOT
  type        = string
  default     = "userAssignedNATGateway"

  validation {
    condition     = contains(["userAssignedNATGateway", "loadBalancer", "userDefinedRouting"], var.egress_type)
    error_message = "egress_type must be one of: userAssignedNATGateway, loadBalancer, userDefinedRouting."
  }
}

variable "nat_gateway_idle_timeout" {
  description = "Idle timeout in minutes for the NAT Gateway (4–120)."
  type        = number
  default     = 4
}

variable "firewall_private_ip" {
  description = "Private IP of the NVA/Firewall for UDR egress. Required when egress_type = userDefinedRouting."
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
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services."
  type        = string
  default     = "10.245.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for the Kubernetes DNS service. Must be within service_cidr."
  type        = string
  default     = "10.245.0.10"
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
  description = "When true, the API server is accessible only via the VNet-integrated ILB private IP. Public DNS entries are removed."
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = <<-EOT
    Resource ID of a pre-created private DNS zone for the private API server FQDN.
    Only used when enable_private_cluster = true. Custom zones require a UserAssigned managed identity on the AKS cluster.
      - null (default) : AKS creates a private.<region>.azmk8s.io zone in the node resource group (privateDNSZone = "system").
      - "<resource-id>": Use a pre-created zone, e.g. in the ALZ connectivity subscription. Format: private.<region>.azmk8s.io.
      - "none"         : No private DNS zone. API server reachable only if public access is also enabled.
  EOT
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

# =============================================================================
# Security
# =============================================================================

variable "image_cleaner_interval_hours" {
  description = "Interval (hours) for the Image Cleaner to scan and remove unused vulnerable images. Default 168 hours (7 days)."
  type        = number
  default     = 168
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
