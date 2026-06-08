# =============================================================================
# Application Gateway for Containers (AGC)
#
# AGC is not an AKS managedCluster ingressProfile property. The AKS cluster only
# hosts the ALB Controller extension; the AGC data plane is a
# Microsoft.ServiceNetworking/trafficControllers resource plus a subnet
# association. Gateway/HTTPRoute Kubernetes resources are applied after cluster
# creation and reconciled by the ALB Controller.
# =============================================================================

resource "azapi_resource" "alb_controller_extension" {
  count     = var.enable_app_gateway_for_containers ? 1 : 0
  type      = "Microsoft.KubernetesConfiguration/extensions@2024-11-01"
  name      = "alb-controller"
  parent_id = azapi_resource.aks.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      extensionType           = "microsoft.albcontroller"
      autoUpgradeMinorVersion = true
      releaseTrain            = "Stable"
      scope = {
        cluster = {
          releaseNamespace = "kube-system"
        }
      }
    }
  }
}

resource "azapi_resource" "agc" {
  count     = var.enable_app_gateway_for_containers ? 1 : 0
  type      = "Microsoft.ServiceNetworking/trafficControllers@2025-03-01-preview"
  name      = local.agc_name
  location  = local.rg_location
  parent_id = local.rg_id
  tags      = local.tags

  body = {
    properties = {}
  }
}

resource "azapi_resource" "agc_frontend" {
  count     = var.enable_app_gateway_for_containers ? 1 : 0
  type      = "Microsoft.ServiceNetworking/trafficControllers/frontends@2025-03-01-preview"
  name      = var.app_gateway_for_containers_frontend_name
  location  = local.rg_location
  parent_id = azapi_resource.agc[0].id
  tags      = local.tags

  body = {
    properties = {}
  }
}

resource "azapi_resource" "agc_association" {
  count     = var.enable_app_gateway_for_containers && local.agc_subnet_id != null ? 1 : 0
  type      = "Microsoft.ServiceNetworking/trafficControllers/associations@2025-03-01-preview"
  name      = var.app_gateway_for_containers_association_name
  location  = local.rg_location
  parent_id = azapi_resource.agc[0].id
  tags      = local.tags

  body = {
    properties = {
      associationType = "subnets"
      subnet = {
        id = local.agc_subnet_id
      }
    }
  }
}

resource "azapi_resource" "role_agc_config_manager" {
  count     = var.enable_app_gateway_for_containers ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${azapi_resource.agc[0].id}-agc-config-manager")
  parent_id = local.rg_id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/fbc52c3f-28ad-4303-a892-8a056630b8f1"
      principalId      = azapi_resource.alb_controller_extension[0].identity[0].principal_id
      principalType    = "ServicePrincipal"
    }
  }
}

resource "azapi_resource" "role_agc_subnet_join" {
  count     = var.enable_app_gateway_for_containers && local.agc_subnet_id != null ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${local.agc_subnet_id}-agc-subnet-join")
  parent_id = local.agc_subnet_id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
      principalId      = azapi_resource.alb_controller_extension[0].identity[0].principal_id
      principalType    = "ServicePrincipal"
    }
  }
}

# =============================================================================
# WAF Policy (Optional)
#
# AGC WAF is preview and not available in all regions. As of 2026-06-08:
# - Verified NOT available in Sweden Central
# - Check regional availability before enabling
#
# If enabled in an unsupported region, Terraform will fail with a location error.
# =============================================================================

resource "azurerm_web_application_firewall_policy" "agc_waf" {
  count               = var.enable_app_gateway_for_containers && var.enable_agc_waf ? 1 : 0
  name                = "${local.agc_name}-waf"
  location            = local.rg_location
  resource_group_name = local.rg_name
  tags                = local.tags

  policy_settings {
    enabled                     = true
    mode                        = var.agc_waf_mode
    request_body_check          = true
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}
