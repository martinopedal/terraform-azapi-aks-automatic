# =============================================================================
# Cluster control-plane identity
#
# AKS requires a user-assigned identity when the cluster uses a custom VNet
# (OnlySupportedOnUserAssignedMSICluster, and the AKS Automatic custom-VNet
# prerequisites). Creating it here lets the root grant rights BEFORE the
# cluster exists. Microsoft Learn requires Network Contributor on the
# virtual network for Node Auto-Provisioning and on the API server subnet;
# the VNet scope covers both. The pipeline identity may assign only this
# role (ABAC-constrained RBAC Administrator on the resource group).
# =============================================================================

resource "azapi_resource" "uami_cluster" {
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31"
  name      = "id-aks-online-demo"
  location  = local.location
  parent_id = local.rg_id
  tags      = local.tags

  response_export_values = ["properties.principalId"]
}

resource "azapi_resource" "ra_cluster_vnet" {
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${local.vnet_id}-id-aks-online-demo-net-contrib")
  parent_id = local.vnet_id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azapi_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
      principalId      = azapi_resource.uami_cluster.output.properties.principalId
      principalType    = "ServicePrincipal"
    }
  }

  depends_on = [azapi_resource.vnet]
}
