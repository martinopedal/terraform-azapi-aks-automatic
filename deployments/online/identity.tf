# =============================================================================
# Cluster control-plane identity
#
# AKS requires a user-assigned identity when the cluster uses subnets it did
# not create (OnlySupportedOnUserAssignedMSICluster). Creating it here lets
# the root grant least-privilege rights BEFORE the cluster exists:
# Network Contributor on the two AKS subnets only, not the whole VNet.
# The pipeline identity may assign only this role (ABAC-constrained RBAC
# Administrator on the resource group).
# =============================================================================

resource "azapi_resource" "uami_cluster" {
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31"
  name      = "id-aks-online-demo"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  response_export_values = ["properties.principalId"]
}

locals {
  network_contributor_role_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
  cluster_subnets = {
    nodes     = local.node_subnet_id
    apiserver = local.apiserver_subnet_id
  }
}

resource "azapi_resource" "ra_cluster_subnet" {
  for_each = local.cluster_subnets

  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${each.value}-id-aks-online-demo-net-contrib")
  parent_id = each.value

  body = {
    properties = {
      roleDefinitionId = local.network_contributor_role_id
      principalId      = azapi_resource.uami_cluster.output.properties.principalId
      principalType    = "ServicePrincipal"
    }
  }

  depends_on = [azapi_resource.snet_nodes, azapi_resource.snet_apiserver]
}
