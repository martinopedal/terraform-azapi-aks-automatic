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
- ✅ Only use green checkmarks (✅) and red crosses (❌) in documentation lists and tables, no other emojis, no AI language, no em/en dashes
