plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# azurerm plugin is not used - this module uses azapi exclusively.
# Do not add the azurerm ruleset; it would flag false positives on
# azapi_resource types it does not recognise.

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = false  # Root module, not a child module
}
