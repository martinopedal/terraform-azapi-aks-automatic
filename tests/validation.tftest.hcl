# Validation-only tests: these check variable validation blocks
# and do not require Azure credentials. They use expect_failures
# which triggers before the provider is called.
#
# Mock providers are required because terraform test initialises
# all providers even for validation-only runs.

mock_provider "azurerm" {}
mock_provider "azapi" {}

run "egress_type_rejects_invalid_value" {
  command = plan

  variables {
    egress_type     = "natGateway"
    enable_byo_vnet = false
  }

  expect_failures = [
    var.egress_type
  ]
}

run "upgrade_channel_rejects_invalid_value" {
  command = plan

  variables {
    upgrade_channel = "latest"
    enable_byo_vnet = false
    egress_type     = "loadBalancer"
  }

  expect_failures = [
    var.upgrade_channel
  ]
}

run "node_os_upgrade_channel_rejects_invalid_value" {
  command = plan

  variables {
    node_os_upgrade_channel = "Automatic"
    enable_byo_vnet         = false
    egress_type             = "loadBalancer"
  }

  expect_failures = [
    var.node_os_upgrade_channel
  ]
}

run "kms_key_vault_network_access_rejects_invalid_value" {
  command = plan

  variables {
    kms_key_vault_network_access = "Restricted"
    enable_byo_vnet              = false
    egress_type                  = "loadBalancer"
  }

  expect_failures = [
    var.kms_key_vault_network_access
  ]
}

run "image_cleaner_interval_hours_rejects_below_24" {
  command = plan

  variables {
    image_cleaner_interval_hours = 12
    enable_byo_vnet              = false
    egress_type                  = "loadBalancer"
  }

  expect_failures = [
    var.image_cleaner_interval_hours
  ]
}

run "defender_requires_workspace" {
  command = plan

  variables {
    enable_defender = true
    enable_byo_vnet = false
    egress_type     = "loadBalancer"
  }

  expect_failures = [
    azapi_resource.aks
  ]
}

run "container_insights_requires_workspace" {
  command = plan

  variables {
    enable_container_insights = true
    enable_byo_vnet           = false
    egress_type               = "loadBalancer"
  }

  expect_failures = [
    azapi_resource.aks
  ]
}

run "kms_requires_key_id" {
  command = plan

  variables {
    enable_kms      = true
    enable_byo_vnet = false
    egress_type     = "loadBalancer"
  }

  expect_failures = [
    azapi_resource.aks
  ]
}

run "prometheus_alerts_require_workspace" {
  command = plan

  variables {
    enable_prometheus_alerts = true
    enable_byo_vnet          = false
    egress_type              = "loadBalancer"
  }

  expect_failures = [
    azapi_resource.prometheus_alerts
  ]
}

run "dns_service_ip_outside_service_cidr_fails" {
  command = plan

  variables {
    service_cidr    = "10.245.0.0/24"
    dns_service_ip  = "10.245.1.10"
    enable_byo_vnet = false
    egress_type     = "loadBalancer"
  }

  expect_failures = [
    azapi_resource.aks
  ]
}
