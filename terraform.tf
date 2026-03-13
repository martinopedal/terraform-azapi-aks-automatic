terraform {
  required_version = ">= 1.9"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.4"
    }
    # azurerm is used only for data sources (client config / subscription context).
    # All Azure resources are created with azapi.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.2"
    }
  }
}

provider "azapi" {}

provider "azurerm" {
  features {}
}
