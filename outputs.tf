# =============================================================================
# Cluster
# =============================================================================

output "cluster_name" {
  description = "Name of the AKS Automatic cluster."
  value       = azapi_resource.aks.name
}

output "cluster_id" {
  description = "Azure Resource ID of the AKS cluster."
  value       = azapi_resource.aks.id
}

output "cluster_fqdn" {
  description = "FQDN of the AKS cluster API server (public)."
  value       = azapi_resource.aks.output.properties.fqdn
}

output "cluster_private_fqdn" {
  description = "Private FQDN of the API server (VNet-integrated private cluster only). Format: <cluster>.private.<region>.azmk8s.io"
  value       = try(azapi_resource.aks.output.properties.privateFQDN, null)
}

output "provisioning_state" {
  description = "Current provisioning state of the cluster."
  value       = azapi_resource.aks.output.properties.provisioningState
}

output "kubernetes_version" {
  description = "Kubernetes version running on the cluster."
  value       = azapi_resource.aks.output.properties.currentKubernetesVersion
}

output "node_resource_group" {
  description = "Auto-generated node resource group name."
  value       = azapi_resource.aks.output.properties.nodeResourceGroup
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for workload identity federation."
  value       = azapi_resource.aks.output.properties.oidcIssuerProfile.issuerURL
}

# =============================================================================
# Networking
# =============================================================================

output "vnet_id" {
  description = "Resource ID of the BYO VNet (null when using managed VNet)."
  value       = try(azapi_resource.vnet[0].id, null)
}

output "node_subnet_id" {
  description = "Resource ID of the node subnet (null when using managed VNet)."
  value       = local.node_subnet_id
}

output "apiserver_subnet_id" {
  description = "Resource ID of the API server subnet (null when using managed VNet)."
  value       = local.apiserver_subnet_id
}

output "nat_gateway_public_ip" {
  description = "Public IP address of the NAT Gateway (null when not using NAT GW egress)."
  value       = try(azapi_resource.nat_gateway_pip[0].id, null)
}

output "egress_type" {
  description = "The configured egress type."
  value       = local.outbound_type
}

# =============================================================================
# Resource Group
# =============================================================================

output "resource_group_name" {
  description = "Name of the resource group."
  value       = azapi_resource.rg.name
}

output "resource_group_id" {
  description = "Resource ID of the resource group."
  value       = azapi_resource.rg.id
}
