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

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity (used for AcrPull, storage access)."
  value       = azapi_resource.aks.output.properties.identityProfile.kubeletidentity.objectId
}

output "app_routing_identity_object_id" {
  description = "Object ID of the App Routing add-on managed identity (used for Key Vault Certificate User, DNS Zone Contributor)."
  value       = try(azapi_resource.aks.output.properties.ingressProfile.webAppRouting.identity.objectId, null)
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

output "egress_type" {
  description = "The resolved outbound type sent to AKS."
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

# =============================================================================
# Supporting Services
# =============================================================================

output "acr_id" {
  description = "Resource ID of the Azure Container Registry (null when create_acr = false)."
  value       = try(azapi_resource.acr[0].id, null)
}

output "acr_login_server" {
  description = "Login server hostname for the ACR (e.g. myacr.azurecr.io)."
  value       = var.create_acr ? "${var.acr_name}.azurecr.io" : null
}

output "keyvault_id" {
  description = "Resource ID of the Azure Key Vault (null when create_keyvault = false)."
  value       = try(azapi_resource.keyvault[0].id, null)
}

output "pe_subnet_id" {
  description = "Resource ID of the private endpoint subnet (module-created or external; null when not used)."
  value       = local.pe_subnet_id
}
