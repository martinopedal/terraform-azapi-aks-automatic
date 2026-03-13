# =============================================================================
# Data sources – current Azure context
# =============================================================================

data "azurerm_client_config" "current" {}

data "azurerm_subscription" "current" {}
