# Apply store app manifests using Terraform kubernetes provider
# This runs on the same in-VNet runner as the main AKS deployment

terraform {
  required_version = "~> 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.18"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-sreagt-store-dmo-swc-001"
  resource_group_name = "rg-sreagt-dmo-swc-001"
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.aks.kube_config[0].host
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--server-id",
      "6dae42f8-4368-4678-94ff-3960e28e3630", # Azure Public Cloud AKS AAD Server App ID
      "--client-id",
      data.azurerm_client_config.current.client_id,
      "--tenant-id",
      data.azurerm_client_config.current.tenant_id,
      "--login",
      "azurecli"
    ]
  }
}

data "azurerm_client_config" "current" {}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

resource "kubernetes_namespace_v1" "store_app" {
  metadata {
    name = "store-app"
  }
}

resource "kubernetes_deployment_v1" "store_app" {
  metadata {
    name      = "store-app"
    namespace = kubernetes_namespace_v1.store_app.metadata[0].name
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "store-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "store-app"
        }
      }

      spec {
        container {
          name = "nginx"
          # Stable line, pinned by multi-arch index digest (reproducible, no :latest).
          image = "nginxinc/nginx-unprivileged:1.30.5-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3"

          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 20
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          # nginx-unprivileged writes its pid file and temp paths under /tmp.
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "64Mi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "store_app" {
  metadata {
    name      = "store-app"
    namespace = kubernetes_namespace_v1.store_app.metadata[0].name
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "store-app"
    }

    port {
      name        = "http"
      protocol    = "TCP"
      port        = 80
      target_port = "8080"
    }
  }
}

resource "kubernetes_manifest" "gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "store-app-gateway"
      namespace = kubernetes_namespace_v1.store_app.metadata[0].name
      annotations = {
        "alb.networking.azure.io/alb-id"       = "/subscriptions/${var.subscription_id}/resourceGroups/rg-sreagt-dmo-swc-001/providers/Microsoft.ServiceNetworking/trafficControllers/tc-sreagt-store-dmo-swc-001"
        "alb.networking.azure.io/alb-frontend" = "fe-public-001"
      }
    }
    spec = {
      gatewayClassName = "azure-alb-external"
      listeners = [
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80
          allowedRoutes = {
            namespaces = {
              from = "Same"
            }
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "httproute" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "store-app-route"
      namespace = kubernetes_namespace_v1.store_app.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name        = "store-app-gateway"
          sectionName = "http"
        }
      ]
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = "store-app"
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [kubernetes_manifest.gateway]
}

output "namespace" {
  value = kubernetes_namespace_v1.store_app.metadata[0].name
}

output "deployment_name" {
  value = kubernetes_deployment_v1.store_app.metadata[0].name
}

output "service_name" {
  value = kubernetes_service_v1.store_app.metadata[0].name
}
