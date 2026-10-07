# Regression test for "Invalid count argument": a caller that creates the
# subnets in the same root passes subnet IDs that are unknown at plan time.
# With use_external_subnets = true the plan must succeed and the module
# must not create its own network.

mock_provider "azurerm" {}
mock_provider "azapi" {}

run "same_root_subnets_plan_with_explicit_flag" {
  command = plan

  module {
    source = "./tests/fixtures/caller"
  }

  variables {
    use_external_subnets = true
  }

  assert {
    condition     = output.module_vnet_id == null
    error_message = "With external subnets the module must not create its own network."
  }
}

run "explicit_flag_without_ids_is_rejected" {
  command = plan

  variables {
    enable_byo_vnet                   = true
    use_external_subnets              = true
    enable_app_gateway_for_containers = false
    create_resource_group             = false
  }

  expect_failures = [azapi_resource.aks]
}
