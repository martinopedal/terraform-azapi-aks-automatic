terraform {
  required_version = ">= 1.9"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.12.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.2"
    }
  }

  # Partial config; values come from -backend-config in deploy-online.yml.
  backend "azurerm" {}
}

# Subscription, tenant, client and OIDC settings come from the ARM_* env
# vars set by the workflow, so nothing environment-specific lives here.
provider "azapi" {}

provider "azurerm" {
  features {}

  # The pipeline identity is Contributor on the resource group only, so it
  # cannot register resource providers at subscription scope.
  resource_provider_registrations = "none"
}
