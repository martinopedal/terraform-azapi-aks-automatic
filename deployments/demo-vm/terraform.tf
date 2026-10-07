terraform {
  # Write-only arguments (azapi sensitive_body) need 1.11; ephemeral
  # variables need 1.10. Together they keep the VM admin password out of
  # both the plan file and the state.
  required_version = ">= 1.11"

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.12.0"
    }
  }

  # Partial config; values come from -backend-config in deploy-demo-vm.yml.
  backend "azurerm" {}
}

# Subscription, tenant, client and OIDC settings come from the ARM_* env
# vars set by the workflow.
provider "azapi" {}
