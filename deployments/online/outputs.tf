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
