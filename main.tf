# =============================================================================
# Resource Group
# =============================================================================

resource "azapi_resource" "rg" {
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = var.resource_group_name
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  tags      = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# AKS Automatic Cluster
#
# Key differentiators from AKS Standard:
#   - sku.name  = "Automatic"  (Standard uses "Base")
#   - sku.tier  = "Standard"   (always Standard tier with uptime SLA)
#   - nodeProvisioningProfile.mode = "Auto"  (Karpenter-based node autoprovisioning)
#
# Many features are preconfigured and cannot be changed (see README.md).
# The configuration below shows every tuneable knob.
# =============================================================================

resource "azapi_resource" "aks" {
  type      = "Microsoft.ContainerService/managedClusters@2025-05-01"
  name      = var.cluster_name
  location  = azapi_resource.rg.location
  parent_id = azapi_resource.rg.id
  tags      = local.tags

  # Identity type is determined by whether a custom private DNS zone is used.
  # Custom private DNS zones require UserAssigned identity; otherwise SystemAssigned.
  identity {
    type         = local.use_user_assigned_identity ? "UserAssigned" : "SystemAssigned"
    identity_ids = local.use_user_assigned_identity ? [var.user_assigned_identity_id] : null
  }

  body = {
    sku = {
      name = "Automatic"
      tier = "Standard"
    }

    properties = {

      # ----- Kubernetes version ------------------------------------------------
      kubernetesVersion = var.kubernetes_version

      # ----- Node provisioning (REQUIRED for Automatic) ------------------------
      nodeProvisioningProfile = {
        mode = "Auto"
      }

      # ----- Agent pool ---------------------------------------------------------
      # The system pool is auto-managed. When using BYO VNet the pool must
      # reference the node subnet so that worker nodes land in your network.
      agentPoolProfiles = [
        {
          name         = "systempool"
          mode         = "System"
          osType       = "Linux"
          osSKU        = "AzureLinux"
          vnetSubnetID = local.node_subnet_id # null → managed VNet
        }
      ]

      # ----- Networking ---------------------------------------------------------
      # Azure CNI Overlay + Cilium is preconfigured in Automatic.
      # Only the CIDRs and egress type can be tuned.
      networkProfile = {
        networkPlugin     = "azure"
        networkPluginMode = "overlay"
        networkDataplane  = "cilium"
        networkPolicy     = "cilium"
        loadBalancerSku   = "standard"
        outboundType      = local.outbound_type
        podCidr           = var.pod_cidr
        serviceCidr       = var.service_cidr
        dnsServiceIP      = var.dns_service_ip
        advancedNetworking = var.enable_acns ? {
          observability = {
            enabled = true
          }
        } : null
      }

      # ----- API server access --------------------------------------------------
      # AKS Automatic always uses VNet Integration. The API server is an ILB
      # in the delegated subnet, not a Private Link endpoint.
      # Private cluster mode disables public DNS and requires a
      # private.<region>.azmk8s.io DNS zone for out-of-cluster resolution.
      # When private_dns_zone_id = "none", the public FQDN must remain enabled.
      apiServerAccessProfile = {
        enableVnetIntegration          = true
        subnetId                       = local.apiserver_subnet_id
        enablePrivateCluster           = var.enable_private_cluster
        enablePrivateClusterPublicFQDN = var.enable_private_cluster && var.private_dns_zone_id == "none" ? true : (var.enable_private_cluster ? false : null)
        privateDNSZone                 = var.enable_private_cluster ? (var.private_dns_zone_id != null ? var.private_dns_zone_id : "system") : null
        authorizedIPRanges             = length(var.authorized_ip_ranges) > 0 ? var.authorized_ip_ranges : null
      }

      # ----- Ingress - Application Routing (managed NGINX) ----------------------
      # Preconfigured in Automatic. Optionally wire Azure DNS zones for
      # automatic DNS record management, and Azure Key Vault for TLS certs.
      ingressProfile = {
        webAppRouting = {
          enabled            = true
          dnsZoneResourceIds = local.dns_zone_ids
        }
      }

      # ----- Ingress - Istio service mesh (optional) ----------------------------
      serviceMeshProfile = var.enable_service_mesh ? {
        mode = "Istio"
        istio = {
          components = {
            ingressGateways = [
              {
                enabled = true
                mode    = "Internal"
              }
            ]
          }
        }
      } : null

      # ----- Security -----------------------------------------------------------
      # Image Cleaner defaults to a 7-day (168 hour) interval per AKS docs.
      securityProfile = {
        workloadIdentity = {
          enabled = true
        }
        imageCleaner = {
          enabled       = true
          intervalHours = var.image_cleaner_interval_hours
        }
        defender = var.enable_defender ? {
          logAnalyticsWorkspaceResourceId = var.log_analytics_workspace_id
          securityMonitoring = {
            enabled = true
          }
        } : null
        azureKeyVaultKms = var.enable_kms ? {
          enabled               = true
          keyId                 = var.kms_key_id
          keyVaultNetworkAccess = var.kms_key_vault_network_access
          keyVaultResourceId    = var.kms_key_vault_resource_id
        } : null
      }

      # ----- OIDC issuer --------------------------------------------------------
      oidcIssuerProfile = {
        enabled = true
      }

      # ----- Azure RBAC ---------------------------------------------------------
      aadProfile = {
        enableAzureRBAC = true
        managed         = true
      }
      enableRBAC           = true
      disableLocalAccounts = true

      # ----- Auto-upgrade -------------------------------------------------------
      autoUpgradeProfile = {
        upgradeChannel       = var.upgrade_channel
        nodeOSUpgradeChannel = var.node_os_upgrade_channel
      }

      # ----- Monitoring ---------------------------------------------------------
      azureMonitorProfile = {
        metrics = {
          enabled = var.enable_prometheus
        }
      }

      # ----- Container Insights -------------------------------------------------
      addonProfiles = var.enable_container_insights ? {
        omsagent = {
          enabled = true
          config = {
            logAnalyticsWorkspaceResourceID = var.log_analytics_workspace_id
            useAADAuth                      = true
          }
        }
      } : null

      # ----- Cost analysis ------------------------------------------------------
      metricsProfile = var.enable_cost_analysis ? {
        costAnalysis = {
          enabled = true
        }
      } : null

      # ----- HTTP proxy ---------------------------------------------------------
      # Configures proxy environment variables on all nodes and pods.
      # The trustedCa field injects a custom CA bundle for TLS-intercepting
      # proxies during node bootstrap.
      httpProxyConfig = var.http_proxy_config != null ? {
        httpProxy  = var.http_proxy_config.http_proxy
        httpsProxy = coalesce(var.http_proxy_config.https_proxy, var.http_proxy_config.http_proxy)
        noProxy    = length(var.http_proxy_config.no_proxy) > 0 ? var.http_proxy_config.no_proxy : null
        trustedCa  = var.http_proxy_config.trusted_ca
      } : null

      # ----- Workload autoscaler: KEDA + VPA ------------------------------------
      workloadAutoScalerProfile = {
        keda = {
          enabled = true
        }
        verticalPodAutoscaler = {
          enabled = true
        }
      }

      # ----- Storage CSI drivers ------------------------------------------------
      storageProfile = {
        diskCSIDriver = {
          enabled = true
        }
        fileCSIDriver = {
          enabled = true
        }
        blobCSIDriver = {
          enabled = false
        }
        snapshotController = {
          enabled = true
        }
      }

      # ----- Node resource group lockdown (preconfigured) -----------------------
      nodeResourceGroupProfile = {
        restrictionLevel = "ReadOnly"
      }
    }
  }

  response_export_values = [
    "properties.fqdn",
    "properties.privateFQDN",
    "properties.provisioningState",
    "properties.currentKubernetesVersion",
    "properties.nodeResourceGroup",
    "properties.oidcIssuerProfile.issuerURL",
    "properties.identityProfile.kubeletidentity.objectId",
    "properties.ingressProfile.webAppRouting.identity.objectId",
  ]

  lifecycle {
    prevent_destroy = true

    # AKS Automatic auto-upgrades the Kubernetes version. Without
    # ignore_changes, Terraform shows perpetual drift after each
    # auto-upgrade and may attempt an unintended version change.
    ignore_changes = [
      body.properties.kubernetesVersion,
    ]

    precondition {
      condition = (
        var.external_node_subnet_id == null && var.external_apiserver_subnet_id == null
        ) || (
        var.external_node_subnet_id != null && var.external_apiserver_subnet_id != null
      )
      error_message = "external_node_subnet_id and external_apiserver_subnet_id must both be set or both be null."
    }

    precondition {
      condition = !(
        var.enable_private_cluster &&
        var.private_dns_zone_id != null &&
        var.private_dns_zone_id != "system" &&
        var.private_dns_zone_id != "none" &&
        var.user_assigned_identity_id == null
      )
      error_message = "user_assigned_identity_id is required when private_dns_zone_id is a custom resource ID. Provide the resource ID of a UserAssigned managed identity with Private DNS Zone Contributor on the zone."
    }

    precondition {
      condition     = !var.enable_defender || var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id is required when enable_defender = true."
    }

    precondition {
      condition     = var.enable_byo_vnet || (var.external_node_subnet_id == null && var.external_apiserver_subnet_id == null && var.external_pe_subnet_id == null)
      error_message = "external_*_subnet_id variables cannot be set when enable_byo_vnet = false. External subnets require enable_byo_vnet = true."
    }

    precondition {
      condition = (
        var.http_proxy_config == null ||
        var.http_proxy_config.http_proxy != null ||
        var.http_proxy_config.https_proxy != null
      )
      error_message = "http_proxy_config requires at least one of http_proxy or https_proxy to be set."
    }

    precondition {
      condition     = !var.enable_container_insights || var.log_analytics_workspace_id != null
      error_message = "log_analytics_workspace_id is required when enable_container_insights = true."
    }

    precondition {
      condition     = !var.enable_kms || var.kms_key_id != null
      error_message = "kms_key_id is required when enable_kms = true."
    }

    precondition {
      condition     = !var.enable_kms || var.kms_key_vault_network_access != "Private" || var.kms_key_vault_resource_id != null
      error_message = "kms_key_vault_resource_id is required when enable_kms = true and kms_key_vault_network_access = Private."
    }
  }
}

# =============================================================================
# Maintenance Window Configuration
# =============================================================================

resource "azapi_resource" "maintenance_config" {
  count     = var.maintenance_window != null ? 1 : 0
  type      = "Microsoft.ContainerService/managedClusters/maintenanceConfigurations@2024-09-01"
  name      = "default"
  parent_id = azapi_resource.aks.id

  body = {
    properties = {
      maintenanceWindow = {
        schedule = {
          weekly = var.maintenance_window.day_of_week != null ? {
            dayOfWeek     = var.maintenance_window.day_of_week
            intervalWeeks = var.maintenance_window.interval_weeks
          } : null
        }
        durationHours   = var.maintenance_window.duration_hours
        startTime       = var.maintenance_window.start_time
        utcOffset       = var.maintenance_window.utc_offset
        notAllowedDates = var.maintenance_window.not_allowed_dates
      }
    }
  }
}
