# =============================================================================
# App namespace as an AKS managed namespace (ARM resource)
#
# The pipeline identity has "AKS RBAC Writer", which can read but not create
# Namespace objects. Creating the namespace through ARM keeps Kubernetes
# rights least-privilege while the platform defines the namespace guardrails:
#   - Pod Security Admission "restricted" enforced
#   - default-deny ingress (manifests-online/networkpolicy.yaml allows only
#     the App Routing NGINX controller)
#   - resource quota
# =============================================================================

resource "azapi_resource" "ns_online_demo" {
  type      = "Microsoft.ContainerService/managedClusters/managedNamespaces@2025-10-01"
  name      = "online-demo"
  location  = local.location
  parent_id = module.aks.cluster_id
  tags      = local.tags

  body = {
    properties = {
      adoptionPolicy = "IfIdentical"
      deletePolicy   = "Delete"
      labels = {
        "pod-security.kubernetes.io/enforce"         = "restricted"
        "pod-security.kubernetes.io/enforce-version" = "latest"
      }
      defaultNetworkPolicy = {
        ingress = "DenyAll"
        egress  = "AllowAll"
      }
      defaultResourceQuota = {
        cpuRequest    = "1000m"
        cpuLimit      = "2000m"
        memoryRequest = "1Gi"
        memoryLimit   = "2Gi"
      }
    }
  }
}
