# AI Agent Instructions

## Repository Purpose

This module deploys AKS Automatic clusters using the azapi provider, with ALZ Corp integration, BYO VNet support, and multiple ingress/egress options.

## Module Usage

- ✅ All infrastructure is Terraform (HCL) using the azapi provider
- ✅ AKS Automatic with ALZ Corp landing zone integration
- ✅ Supports BYO VNet with subnet delegation
- ✅ Ingress options: Application Routing (NGINX, preconfigured), Istio (optional). AGC documented but not yet supported on AKS Automatic.
- ✅ Egress options: UDR (hub firewall), Load Balancer. Managed NAT Gateway applies only with AKS-managed VNet.

## Code Quality

- ✅ Run `terraform fmt -check -recursive` before committing
- ✅ Run `terraform validate` before committing
- ✅ Follow existing file naming conventions
- ✅ Only use green checkmarks and red crosses in documentation lists and tables, no other emojis, no AI language, no em/en dashes

## Squad Extensions

This repo includes specialized Copilot CLI tools in `.github/extensions/`. Use these tools when working on changes in the corresponding domain.

| Extension | Tool | Purpose |
|---|---|---|
| `style-guard` | `style_check` | Enforces style rules: no non-allowed emojis, no em/en dashes, no AI language |
| `terraform-validator` | `terraform_validate_full` | Runs terraform validate + fmt, checks variable validation and lifecycle coverage |
| `doc-checker` | `doc_check` | Cross-references README claims vs code, verifies Learn links and project structure |
| `aks-feature-tracker` | `aks_feature_scan` | Scans AKS Automatic ARM API features with GA status and regional availability |
| `security-reviewer` | `security_scan` | Checks Azure Security Benchmark controls (Key Vault, ACR, AKS hardening) |
| `network-architect` | `network_review` | Validates subnet topology, CIDR, UDR, CNI Overlay, private endpoints |
| `alz-checker` | `alz_alignment_check` | Validates ALZ Corp policy alignment (public endpoints, tags, diagnostics) |
| `terraform-engineer` | `terraform_engineering_review` | Reviews HCL quality: provider pinning, types, descriptions, patterns |

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `validate.yml` | PR to main | Terraform validate, fmt check, style enforcement |
| `copilot-setup-steps.yml` | Manual / push | Configures Copilot coding agent environment (Terraform + Node.js) |
| `squad-dispatch.yml` | Issue opened/labeled | Routes issues to recommended squad tools based on labels |
