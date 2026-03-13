# =============================================================================
# Resource Group
# =============================================================================

resource "azapi_resource" "rg" {
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = var.resource_group_name
  location  = var.location
  parent_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  tags      = local.tags
}

# =============================================================================
# AKS Automatic Cluster
#
# Key differentiators from AKS Standard:
#   • sku.name  = "Automatic"  (Standard uses "Base")
#   • sku.tier  = "Standard"   (always Standard tier with uptime SLA)
#   • nodeProvisioningProfile.mode = "Auto"  (Karpenter-based node autoprovisioning)
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

  identity {
    type = "SystemAssigned"
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
          count        = 3
          vmSize       = "Standard_DS4_v2"
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
      }

      # ----- API server access --------------------------------------------------
      # AKS Automatic always uses VNet Integration. The API server is an ILB
      # in the delegated subnet, not a Private Link endpoint.
      # Private cluster mode disables public DNS and requires a
      # private.<region>.azmk8s.io DNS zone for out-of-cluster resolution.
      apiServerAccessProfile = {
        enableVnetIntegration          = true
        subnetId                       = local.apiserver_subnet_id # null -> managed VNet
        enablePrivateCluster           = var.enable_private_cluster
        enablePrivateClusterPublicFQDN = var.enable_private_cluster ? false : null
        privateDNSZone                 = var.enable_private_cluster ? (var.private_dns_zone_id != null ? var.private_dns_zone_id : "system") : null
        authorizedIPRanges             = length(var.authorized_ip_ranges) > 0 ? var.authorized_ip_ranges : null
      }

      # ----- Ingress – Application Routing (managed NGINX) ----------------------
      # Preconfigured in Automatic. Optionally wire Azure DNS zones for
      # automatic DNS record management, and Azure Key Vault for TLS certs.
      ingressProfile = {
        webAppRouting = {
          enabled            = true
          dnsZoneResourceIds = local.dns_zone_ids
        }
      }

      # ----- Ingress – Istio service mesh (optional) ----------------------------
      serviceMeshProfile = var.enable_service_mesh ? {
        mode = "Istio"
        istio = {
          components = {
            ingressGateways = [
              {
                enabled = true
                mode    = "External"
              }
            ]
          }
        }
      } : null

      # ----- Security -----------------------------------------------------------
      securityProfile = {
        workloadIdentity = {
          enabled = true
        }
        imageCleaner = {
          enabled       = true
          intervalHours = var.image_cleaner_interval_hours
        }
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
  ]
}
