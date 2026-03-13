# AI Agent Instructions

## Repository Purpose

This module deploys AKS Automatic clusters using the azapi provider, with ALZ Corp integration, BYO VNet support, and multiple ingress/egress options.

## Module Usage

- ✅ All infrastructure is Terraform (HCL) using the azapi provider
- ✅ AKS Automatic with ALZ Corp landing zone integration
- ✅ Supports BYO VNet with subnet delegation
- ✅ Ingress options: AGC, NGINX, Istio
- ✅ Egress options: NAT Gateway, UDR, Load Balancer

## Code Quality

- ✅ Run `terraform fmt -check -recursive` before committing
- ✅ Run `terraform validate` before committing
- ✅ Follow existing file naming conventions
- ✅ Only use checkmarks in documentation lists, no AI language or em dashes
