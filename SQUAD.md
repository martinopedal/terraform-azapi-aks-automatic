# Squad - Automated Module Governance

This repo includes a squad of specialized Copilot CLI extensions and GitHub Actions workflows for automated governance of the AKS Automatic Terraform module.

## Squad Extensions

Eight extensions in `.github/extensions/` provide domain-specific static analysis tools. They auto-load when you open Copilot CLI from the repo root.

| Extension | Tool | Domain |
|---|---|---|
| `style-guard` | `style_check` | Style enforcement (emojis, dashes, AI language) |
| `terraform-validator` | `terraform_validate_full` | Terraform validate + fmt + validation coverage |
| `doc-checker` | `doc_check` | README vs code accuracy, Learn links, project structure |
| `aks-feature-tracker` | `aks_feature_scan` | AKS Automatic ARM API feature coverage with GA status and regional availability |
| `security-reviewer` | `security_scan` | Azure Security Benchmark controls (Key Vault, ACR, AKS hardening) |
| `network-architect` | `network_review` | Subnet topology, CIDR, UDR, CNI Overlay, private endpoints |
| `alz-checker` | `alz_alignment_check` | ALZ Corp policy alignment (public endpoints, tags, diagnostics) |
| `terraform-engineer` | `terraform_engineering_review` | HCL quality (provider pinning, types, descriptions, patterns) |
| `gitops-architect` | `gitops_review` | ArgoCD readiness for ALZ Corp private clusters (networking, identity, ingress) |
| `squad-coordinator` | `squad_dispatch`, `squad_status`, `squad_run_all` | Routes issues to squad tools, roster, full scan orchestration |
| `rubber-duck` | `rubber_duck_review`, `list_review_models` | Multi-model critique across 15 AI models (Claude + GPT families) |

### Local usage (Copilot CLI)

```bash
cd terraform-azapi-aks-automatic
# Extensions auto-load. Call any tool by name:
# "Run style_check" or "Run security_scan on this module"
```

### GitHub.com usage (Copilot coding agent)

1. Open any issue in this repo
2. Assign Copilot to the issue (the coding agent uses `copilot-setup-steps.yml` for its environment)
3. The coding agent has access to all squad extensions

## CI/CD Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `validate.yml` | PR to main | Terraform validate, fmt check, style enforcement |
| `copilot-setup-steps.yml` | Manual / push | Configures Copilot coding agent environment (Terraform + Node.js) |
| `squad-dispatch.yml` | Issue opened/labeled | Routes issues to recommended squad tools based on labels |

### Squad dispatch

When an issue is opened or labeled, the dispatcher workflow automatically comments with the recommended squad tool based on labels:

| Label | Squad tool |
|---|---|
| `security` | `security_scan` |
| `networking` | `network_review` |
| `alz` | `alz_alignment_check` |
| `testing` | `terraform_engineering_review` |
| `feature-tracking` | `aks_feature_scan` |
| `ci-cd` | `terraform_validate_full` |
| `documentation` | `doc_check` |
| `enhancement` | `style_check` |
| `gitops` | `gitops_review` |
| `squad` (generic) | `style_check` + `doc_check` |

## Issue Templates

Five issue templates are available when creating new issues. Each template recommends the correct squad agent:

- **Security review** - routes to `security-reviewer`
- **Networking change** - routes to `network-architect`
- **ALZ alignment** - routes to `alz-checker`
- **AKS feature request** - routes to `aks-feature-tracker`
- **Terraform engineering** - routes to `terraform-engineer` + `terraform-validator`

## Extension development

Extensions are Node.js ES modules using `@github/copilot-sdk/extension`. Each lives in `.github/extensions/<name>/extension.mjs`. See [AGENTS.md](AGENTS.md) for the full tool listing and the [Copilot CLI extension docs](https://docs.github.com/en/copilot/customizing-copilot/extending-copilot-cli) for authoring guidance.
