# CIDR Allocation Plan

| Network | CIDR | Purpose |
|---|---|---|
| Spoke VNet | 10.10.0.0/16 | AKS spoke address space |
| Node subnet | 10.10.0.0/22 | AKS node pool subnet |
| API server subnet | 10.10.4.0/28 | Delegated API server subnet |
| PE subnet | 10.10.12.0/24 | Private endpoints (ACR, KV) |
| Pod CIDR (overlay) | 10.244.0.0/16 | CNI Overlay pod addresses |
| Service CIDR | 10.245.0.0/16 | Kubernetes service VIPs |

Coordinate with ALZ platform team before changing any ranges.
