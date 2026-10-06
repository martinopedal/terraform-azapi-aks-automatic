output "cluster_name" {
  value = module.aks.cluster_name
}

output "resource_group_name" {
  value = module.aks.resource_group_name
}

output "cluster_fqdn" {
  value = module.aks.cluster_fqdn
}

output "egress_type" {
  value = module.aks.egress_type
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "nat_gateway_public_ip" {
  description = "Stable egress IP for allow-listing downstream services."
  value       = azapi_resource.pip_nat.output.properties.ipAddress
}
