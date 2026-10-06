# Store App via Terraform Kubernetes Provider (alternative to kubectl apply)

This is a self-contained, standalone Terraform root module. It is an
alternative to the `kubectl apply -k manifests/` approach used by
`apply-store-app.yml` / `apply-store-app-mi.yml` for deploying the same
store-app demo workload, using the Terraform `kubernetes` provider instead.

It intentionally lives in its own directory, not the repository root,
because it declares its own `terraform {}`, `provider "azurerm" {}`, and
`data "azurerm_client_config" "current"` blocks that collide with the main
AKS Automatic root module (`terraform.tf`, `backend.tf`, `data.tf`) if
present in the same directory.

Not wired to a CI workflow. Run manually if you want this approach:

```bash
cd terraform-store-app-alt
terraform init \
  -backend-config="resource_group_name=<tfstate-rg>" \
  -backend-config="storage_account_name=<tfstate-sa>" \
  -backend-config="container_name=<tfstate-container>" \
  -backend-config="key=store-app-tf.tfstate"
terraform apply -var="subscription_id=<target-subscription-id>"
```

History: originally added as `manifests.tf` at the repository root
(2026-06-09), which broke `terraform validate`/`terraform init` for the
main root module ever since (duplicate backend, provider, and data source
declarations). Relocated here, content unchanged, so both root modules
validate independently.
