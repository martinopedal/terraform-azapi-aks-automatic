# Networking: Azure CNI Powered by Cilium vs Cilium Enterprise

AKS Automatic uses **Azure CNI Overlay powered by Cilium** (open-source). This is the preconfigured and immutable networking stack. For environments that require additional capabilities, **Isovalent Cilium Enterprise** is available through the Azure Marketplace as a separately licensed product.

| Capability | Azure CNI + Cilium (AKS Automatic) | Isovalent Cilium Enterprise |
|---|---|---|
| eBPF data plane | ✅ | ✅ |
| Network policy (L3/L4) | ✅ | ✅ |
| Network policy (L7, application-aware) | Via ACNS (paid add-on) | ✅ built-in |
| FQDN-based egress control | Via ACNS | ✅ with compliance controls |
| Hubble observability | ✅ basic | ✅ Enterprise + Timescape (historical) |
| WireGuard transparent encryption | ✅ (Preview via ACNS) | ✅ with compliance options |
| eBPF Host Routing | ✅ (Preview via ACNS) | ✅ |
| Audit trails and forensics | Limited | ✅ |
| Multi-cluster mesh | Not available | ✅ |
| Commercial SLA | Azure support | Azure + Isovalent support |
| Windows node support | ❌ | ❌ (roadmap) |
| Upgrade from OSS | N/A | One-click via Marketplace |

**When to consider Cilium Enterprise:**
- Regulated industries requiring L7 policy enforcement, audit trails, and advanced forensics
- Multi-cluster service mesh requirements
- Need for historical traffic flow analysis (Timescape)
- Commercial support SLA from Isovalent in addition to Azure support

**For most AKS Automatic deployments**, the built-in Azure CNI + Cilium stack combined with ACNS (Advanced Container Networking Services) provides sufficient networking capabilities. ACNS is a paid add-on that extends the open-source Cilium with container network observability, FQDN filtering, and WireGuard encryption.
