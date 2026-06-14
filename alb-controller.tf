# =============================================================================
# ALB Ingress Controller (Helm-based deployment with Workload Identity)
#
# The Application Gateway for Containers (AGC) requires the ALB Controller
# to reconcile Gateway/HTTPRoute Kubernetes resources. This file implements
# the controller using:
#   - User-assigned managed identity (uami-alb-*)
#   - Federated credential for workload identity (OIDC)
#   - RBAC assignments (AppGw for Containers Configuration Manager on AGC, 
#     Network Contributor on AGC subnet)
#   - Helm release from mcr.microsoft.com/application-lb/charts/alb-controller
#
# The controller creates a ServiceAccount azure-alb-system/alb-controller-sa
# which the federated credential trusts via the AKS OIDC issuer URL.
# =============================================================================

# -----------------------------------------------------------------------------
# Managed Identity for ALB Controller
# -----------------------------------------------------------------------------

resource "azapi_resource" "alb_controller_identity" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller ? 1 : 0
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview"
  name      = local.alb_controller_identity_name
  location  = local.rg_location
  parent_id = local.rg_id
  tags      = local.tags

  body = {}
}

# -----------------------------------------------------------------------------
# Federated Identity Credential (Workload Identity OIDC)
# -----------------------------------------------------------------------------

resource "azapi_resource" "alb_controller_federated_credential" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller ? 1 : 0
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-07-31-preview"
  name      = "alb-controller-fedcred"
  parent_id = azapi_resource.alb_controller_identity[0].id

  body = {
    properties = {
      audiences = ["api://AzureADTokenExchange"]
      issuer    = azapi_resource.aks.output.properties.oidcIssuerProfile.issuerURL
      subject   = "system:serviceaccount:azure-alb-system:alb-controller-sa"
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC - AppGw for Containers Configuration Manager on AGC
# -----------------------------------------------------------------------------

resource "azapi_resource" "role_alb_agc_config_manager" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${azapi_resource.agc[0].id}-alb-config-manager")
  parent_id = azapi_resource.agc[0].id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/fbc52c3f-28ad-4303-a892-8a056630b8f1"
      principalId      = azapi_resource.alb_controller_identity[0].output.properties.principalId
      principalType    = "ServicePrincipal"
    }
  }
}

# -----------------------------------------------------------------------------
# RBAC - Network Contributor on AGC Subnet
# -----------------------------------------------------------------------------

resource "azapi_resource" "role_alb_subnet_network_contributor" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller && local.agc_subnet_id != null ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${local.agc_subnet_id}-alb-network-contributor")
  parent_id = local.agc_subnet_id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
      principalId      = azapi_resource.alb_controller_identity[0].output.properties.principalId
      principalType    = "ServicePrincipal"
    }
  }
}
