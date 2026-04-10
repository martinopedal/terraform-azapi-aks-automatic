# ALZ Corp Constraints

- All PaaS public endpoints must be disabled (Deny-PublicEndpoints policy)
- Egress routes through hub Azure Firewall via UDR
- Private DNS Zones hosted in connectivity subscription
- Tags required by Require-Tag-* policies
- Azure RBAC enforced, local accounts disabled
- Cross-subscription RBAC managed by platform team
