# Changelog

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
