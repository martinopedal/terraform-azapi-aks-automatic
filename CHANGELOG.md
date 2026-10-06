# Changelog

## Unreleased

- `user_assigned_identity_id` is now honored whenever it is set. Previously the cluster used a SystemAssigned identity unless the cluster was private with a custom private DNS zone, so a BYO-VNet cluster with caller-created subnets failed with `OnlySupportedOnUserAssignedMSICluster`. Consumers that do not pass the variable are unaffected. Consumers that passed it without a custom private DNS zone will now get a UserAssigned identity (identity change).
- Added `tests/identity.tftest.hcl` (UserAssigned when supplied, SystemAssigned otherwise, `outboundType = none` with external subnets).
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
