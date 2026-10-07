# Changelog

## Unreleased

- **Fixed `Invalid count argument`** when a caller creates the subnets in the same root: new optional `use_external_subnets` (bool). When set, the module's network `count` no longer depends on subnet IDs that are unknown at plan time; when null, behavior is unchanged (inferred). Regression test `tests/external_subnets.tftest.hcl` uses a caller fixture that reproduces the original error without the flag and passes with it. `deployments/online` now passes real subnet references.
- **Fixed a scanning blind spot:** Checkov's HCL parser rejected `main.tf` (bare `for` object keys in the Prometheus alert rules), so the cluster definition was never scanned. Keys are now quoted (`"for" = ...`); same semantics, and every `.tf` file parses with Checkov's parser.
- **Hardened the generic Corp example** (`manifests/`): unprivileged nginx on 8080 pinned by digest, UID/GID 10001, read-only root filesystem, resources and probes (Trivy: 8 findings to 1 documented, scoped exception). Removed a real resource ID from `gateway.yaml`.
- **Removed real environment data** from the public repo: `env/prod.tfvars` deleted (use `terraform.tfvars.example`), subscription ID removed from workflows. These are identifiers, not credentials; history is not rewritten.
- **Retired dead workflows** (`deploy.yml`, `apply-store-app.yml`, `apply-store-app-mi.yml`): they target runners and a registry that do not exist. Disabled, annotated, and `deploy.yml`'s missing `needs: plan` fixed.

## v0.5.0 (2026-10-06)

- `user_assigned_identity_id` is now honored whenever it is set. Previously the cluster used a SystemAssigned identity unless the cluster was private with a custom private DNS zone, so a BYO-VNet cluster with caller-created subnets failed with `OnlySupportedOnUserAssignedMSICluster`. Consumers that do not pass the variable are unaffected. Consumers that passed it without a custom private DNS zone will now get a UserAssigned identity (identity change).
- Added `tests/identity.tftest.hcl` (UserAssigned when supplied, SystemAssigned otherwise, `outboundType` pass-through for external subnets).
- `egress_type` now accepts `userAssignedNATGateway` for BYO subnets with a caller-attached NAT Gateway (documented AKS Automatic custom-VNet option). With current AKS API versions, `none` means a network-isolated cluster and requires `bootstrapProfile.artifactSource = "Cache"`; the description now says so.
- Fixed perpetual drift: `metricsProfile.costAnalysis.enabled` is now always sent. AKS returns `false` when disabled; sending `null` caused an in-place update on every apply (about 6 minutes each). Test added first.
- Fixed perpetual drift: `serviceMeshProfile.mode` is now always sent (`Disabled` when the mesh is off), for the same reason. Test added first.
- **New: `cluster_sku = "Automatic"` (opt-in).** Creates the AKS Automatic SKU with managed system node pools (`hostedSystemProfile`) on API `2026-04-01`, using the shape validated in the session's Corp module. Requires external BYO subnets, the new `external_system_node_subnet_id` (at least /26, not delegated), and `user_assigned_identity_id`. Keys AKS manages for Automatic (`agentPoolProfiles`, add-ons) are omitted rather than sent as null. Tests: `tests/automatic.tftest.hcl` (written first).
- **Default unchanged:** `cluster_sku = "Base"` keeps the original body and API version (`2025-10-01`): AKS Standard SKU with Automatic-style features. AKS does not support migrating a Base cluster to Automatic (an in-place attempt, #133, was rejected and reverted in #134); switching needs a new cluster.
- **Provider:** `azure/azapi` constraint `~> 2.4` to `~> 2.12.0` (locked 2.12.0, the version validated with `2026-04-01` in the Corp module; 2.9.0 has no `2026-04-01` schema). `hashicorp/azurerm` lock 4.68.0 to 4.81.0 (within `~> 4.2`).
- Added `deployments/online/`: a thin root that consumes the module for an ALZ Online subscription (BYO spoke with NSGs and NAT Gateway, user-assigned identity with subnet-scoped rights, API server authorized IPs, AKS managed namespace) and `.github/workflows/deploy-online.yml`.
- Known limitation: `count` in `network.tf` is keyed on `external_node_subnet_id != null`, which is unknown when the caller creates the subnet in the same root. Pass plan-time-known IDs (see `deployments/online/`). A boolean input is the planned fix.

## v0.3.0

- Fixed AGC wiring by removing invalid `managedClusters.properties.ingressProfile.gatewayAPI` / `applicationLoadBalancer` body fields.
- Added AzAPI-managed ALB Controller extension (`Microsoft.KubernetesConfiguration/extensions@2024-11-01`, `extensionType = "microsoft.albcontroller"`).
- Added AzAPI-managed AGC data-plane resources: `Microsoft.ServiceNetworking/trafficControllers@2025-03-01-preview`, `frontends`, and subnet `associations`.
- Added `app_gateway_for_containers_subnet_id` as the primary delegated `/24` AGC subnet input; `external_agc_subnet_id` remains a deprecated compatibility alias.
- Added AGC outputs and documented the as-built AGC runbook/cost posture.

## v0.2.0

- Made AGC the default ingress posture and managed NGINX opt-in.
- Added `enable_managed_nginx` and disabled `webAppRouting` when AGC is enabled.

## v0.1.0

- Initial consumable release with BYO resource group support, cheap `Standard_D2s_v5` default system node size, UDR support, and optional AGC documentation.
