# Third-Party Notices

This module is built with reference to the [Azure Verified Modules (AVM)](https://aka.ms/avm)
specification and depends on the Terraform providers listed below. It does not source any
AVM registry modules directly — all Azure resources are provisioned via the `azapi` provider.

---

## Azure Verified Modules (AVM)

- **Specification & Guidelines:** https://aka.ms/avm
- **Registry:** https://registry.terraform.io/namespaces/Azure

This module does not source AVM registry modules directly. It follows AVM naming and
structural conventions and is designed to complement AVM-based landing zone deployments.

---

## HashiCorp Terraform Providers

- **azapi provider:** https://github.com/Azure/terraform-provider-azapi — MPL-2.0
- **azurerm provider:** https://github.com/hashicorp/terraform-provider-azurerm — MPL-2.0 *(data sources only)*
- **Providers are downloaded at `terraform init` time and are not bundled in this repository.**

> **Note on MPL-2.0:** The Mozilla Public License 2.0 is a weak copyleft license that applies
> only to the provider source files themselves, not to Terraform configurations that use the
> provider. Using these providers in your Terraform code does not impose any license requirements
> on your own configuration code.

---

## AVM Specification

- **Source:** https://azure.github.io/Azure-Verified-Modules/
- **Copyright:** Copyright (c) Microsoft Corporation
- **License:** MIT License