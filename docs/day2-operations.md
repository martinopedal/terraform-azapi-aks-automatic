# Day-2 Operations

### Karpenter NodePool and AKSNodeClass Configuration

After cluster deployment, customise node provisioning behaviour by creating Karpenter CRDs. These are not managed by Terraform. They are Kubernetes-native resources applied via `kubectl`.

```yaml
# Example: GPU-optimised NodePool for AI/ML workloads
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu-workloads
spec:
  template:
    spec:
      requirements:
        - key: "karpenter.azure.com/sku-family"
          operator: In
          values: ["N"]          # N-series GPU VMs
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ["on-demand"]  # or "spot" for cost savings
      nodeClassRef:
        group: karpenter.azure.com
        kind: AKSNodeClass
        name: gpu-class
  limits:
    cpu: "64"
    memory: "256Gi"
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s
---
apiVersion: karpenter.azure.com/v1beta1
kind: AKSNodeClass
metadata:
  name: gpu-class
spec:
  osDiskSizeGB: 128
```

Key Karpenter selectors for AKS:

| Selector | Description | Example values |
|---|---|---|
| `karpenter.azure.com/sku-family` | VM SKU family | D, F, L, N (GPU), E (memory) |
| `karpenter.azure.com/sku-name` | Specific SKU | Standard_NC24ads_A100_v4 |
| `karpenter.sh/capacity-type` | Spot or on-demand | spot, on-demand |
| `karpenter.azure.com/sku-gpu-name` | GPU model | A100, T4, V100 |
| `karpenter.azure.com/sku-gpu-count` | GPU count per VM | 1, 2, 4, 8 |
| `karpenter.azure.com/sku-cpu` | vCPU count | 4, 8, 16, 64 |
| `karpenter.azure.com/sku-memory` | Memory in MiB | 16384, 65536 |
| `karpenter.azure.com/sku-networking-accelerated` | Accelerated networking | true, false |

### CI/CD Access to Private Clusters

When `enable_private_cluster = true`, the API server is not reachable from the public internet. CI/CD pipelines require private network connectivity.

**GitHub Actions options:**

- **GitHub-hosted VNet-integrated runners** (GitHub Enterprise Cloud): runners execute inside your Azure VNet with no public exposure. See [martinopedal/ghec-vnet-runners-azure](https://github.com/martinopedal/ghec-vnet-runners-azure) for a Terraform module that deploys this pattern.
- **Self-hosted runners on Azure Container Apps**: runners deployed in the spoke VNet or a peered VNet with UDR egress through the hub firewall. See [martinopedal/terraform-azurerm-github-runners-alz-corp](https://github.com/martinopedal/terraform-azurerm-github-runners-alz-corp) for an ALZ Corp-optimised module.
- **AVM CI/CD Agents and Runners pattern module**: the official AVM module for self-hosted agents supports both Azure DevOps and GitHub Actions on Azure Container Apps/Instances. See [martinopedal/terraform-azurerm-avm-ptn-cicd-agents-and-runners](https://github.com/martinopedal/terraform-azurerm-avm-ptn-cicd-agents-and-runners).

**Azure DevOps options:**

- Self-hosted agents on Container Apps or VMs in the spoke VNet or a peered VNet.
- The AVM CI/CD pattern module listed above supports Azure DevOps agents.

**Other access methods:**

- `az aks command invoke` for one-off commands without direct network access (requires Azure CLI auth, not kubectl).
- Azure Bastion for interactive kubectl sessions via the hub.
- Microsoft-hosted agents (both Azure DevOps and GitHub Actions) do **not** work with private clusters.

### Backup and Disaster Recovery

AKS Automatic does not provide built-in backup. Consider:

- **Azure Backup for AKS** (managed offering) for scheduled backup of cluster resources and persistent volumes
- **Velero** (open-source) with Azure Blob Storage as the backup target, using Workload Identity for auth
- **GitOps** (Flux/ArgoCD) for declarative cluster state recovery. Workload manifests are redeployable from Git
- Persistent volume snapshots via the Disk CSI Snapshot Controller (enabled by default)
- For multi-region DR: deploy a second AKS Automatic cluster in a paired region. Use Azure Front Door or Traffic Manager for failover. Container images should be replicated via ACR geo-replication.

### Cost Management

**Platform-level costs:**

- AKS Automatic always runs at Standard tier. Uptime SLA charges apply.
- Clusters cannot be stopped or deallocated. Compute charges are continuous.
- Karpenter optimises cost through bin packing and consolidation, but idle clusters still incur node charges.
- Use Spot VMs via Karpenter NodePool (`karpenter.sh/capacity-type: spot`) for fault-tolerant workloads.

**Azure-native cost visibility:**

- Enable `metricsProfile.costAnalysis` on the cluster for per-namespace and per-workload cost breakdown in Azure Cost Management.
- Azure Cost Management provides cost allocation by resource group, tags, and AKS namespaces when cost analysis is enabled.
- Azure Advisor generates right-sizing and reservation recommendations for AKS node VMs.

**In-cluster cost management tools:**

| Tool | Type | Integration |
|---|---|---|
| [AKS Cost Analysis](https://learn.microsoft.com/azure/aks/cost-analysis) | Azure-native | Built into Azure portal. Requires `metricsProfile.costAnalysis` enabled on the cluster. Shows cost by namespace, controller, and node pool. |
| [OpenCost](https://www.opencost.io/) | Open-source (CNCF) | Deploys as a pod. Allocates real cluster cost to namespaces and workloads. Integrates with Prometheus. No license cost. |
| [Kubecost](https://www.kubecost.com/) | Commercial (free tier available) | Extends OpenCost with savings recommendations, alerting, and governance. Available via Azure Marketplace. |

For ALZ Corp deployments, AKS Cost Analysis is the recommended starting point as it requires no in-cluster components and integrates with Azure Cost Management for cross-resource reporting.

### Workload Identity Federation

AKS Automatic preconfigures Workload Identity and OIDC Issuer. To allow a pod to authenticate to Azure services (ACR, Key Vault, Storage, SQL) without secrets, create a federated identity credential:

```bash
# 1. Create a user-assigned managed identity for the workload
az identity create --name mi-my-app --resource-group rg-aks-automatic --location swedencentral

# 2. Create a Kubernetes service account annotated with the identity client ID
kubectl create serviceaccount my-app-sa --namespace my-app
kubectl annotate serviceaccount my-app-sa --namespace my-app \
  azure.workload.identity/client-id="<managed-identity-client-id>"

# 3. Create the federated identity credential linking K8s SA to Entra ID
az identity federated-credential create \
  --name fic-my-app \
  --identity-name mi-my-app \
  --resource-group rg-aks-automatic \
  --issuer "$(terraform output -raw oidc_issuer_url)" \
  --subject "system:serviceaccount:my-app:my-app-sa" \
  --audiences "api://AzureADTokenExchange"

# 4. Grant the managed identity access to target resources
az role assignment create --role "Storage Blob Data Reader" \
  --assignee "<managed-identity-client-id>" \
  --scope "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<sa>"
```

Pods using this service account with the `azure.workload.identity/use: "true"` label will automatically receive an Entra ID token without any secrets in the cluster.

### GitOps with Flux

AKS supports the [Flux v2 GitOps extension](https://learn.microsoft.com/azure/azure-arc/kubernetes/conceptual-gitops-flux2) as a managed add-on. Deploy it after cluster creation:

```bash
az k8s-extension create --cluster-name aks-automatic-corp \
  --resource-group rg-aks-automatic \
  --cluster-type managedClusters \
  --extension-type microsoft.flux \
  --name flux

# Create a Flux configuration pointing to your Git repository
az k8s-configuration flux create \
  --cluster-name aks-automatic-corp \
  --resource-group rg-aks-automatic \
  --cluster-type managedClusters \
  --name cluster-config \
  --namespace flux-system \
  --scope cluster \
  --url "https://github.com/<org>/<repo>" \
  --branch main \
  --kustomization name=infra path=./clusters/corp prune=true
```

For private clusters, the Flux extension communicates with the Azure API (not the Git server directly from the cluster). If the Git repository is private (GitHub Enterprise, Azure DevOps), configure an SSH deploy key or PAT via `--ssh-private-key-file` or `--https-user`/`--https-key`.

### ArgoCD on AKS Automatic (ALZ Corp)

ArgoCD is an alternative GitOps controller that runs entirely in-cluster. For ALZ Corp private clusters, the following considerations apply:

**Networking:**
- ArgoCD runs in-cluster, so API server access works without extra configuration (VNet-integrated ILB)
- Git repository egress (GitHub, Azure DevOps) must be allowed through the hub Azure Firewall
- Import ArgoCD container images into the private ACR to avoid external registry dependencies:
  ```bash
  az acr import --name <acr> --source quay.io/argoproj/argocd:v2.13.0
  ```
- Webhook delivery from GitHub/Azure DevOps cannot reach private clusters directly. Use polling (default 3-minute interval, configurable)

**Identity and RBAC:**
- AKS Automatic enforces Azure RBAC (local accounts disabled). Configure ArgoCD SSO with Entra ID via OIDC in the `argocd-cm` ConfigMap
- Map Entra ID groups to ArgoCD roles in `argocd-rbac-cm`
- Use Workload Identity Federation for ArgoCD to access Key Vault secrets (Git credentials, TLS certs)

**Ingress (ArgoCD UI):**
- Expose via Application Routing with an internal load balancer:
  ```yaml
  apiVersion: networking.k8s.io/v1
  kind: Ingress
  metadata:
    name: argocd-server
    namespace: argocd
    annotations:
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
      kubernetes.azure.com/tls-cert-keyvault-uri: "https://<vault>.vault.azure.net/certificates/<cert>"
  spec:
    ingressClassName: webapprouting.kubernetes.azure.com
    rules:
      - host: argocd.<private-dns-zone>
        http:
          paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: argocd-server
                  port:
                    number: 443
  ```

**Multi-environment pattern:**
- Use ArgoCD ApplicationSet with a Git generator for directory-based environments:
  ```
  clusters/
    dev/apps/<app>/
    staging/apps/<app>/
    prod/apps/<app>/
  ```

**Security:**
- Run ArgoCD in a dedicated `argocd` namespace with CiliumNetworkPolicy restricting egress to API server, Git endpoints (via firewall), ACR and Key Vault (via private endpoints)
- Store Git credentials in Key Vault, synced via Workload Identity + External Secrets Operator

Run `gitops_review` from the squad extensions for a full readiness assessment.

### Cilium Network Policy Operations

AKS Automatic uses Cilium as the network policy engine. Standard Kubernetes `NetworkPolicy` resources work out of the box. For advanced L3/L4/L7 control, use `CiliumNetworkPolicy` CRDs:

```yaml
# Example: restrict egress from the app namespace to only ACR and Key Vault
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: restrict-egress
  namespace: my-app
spec:
  endpointSelector: {}
  egress:
    - toFQDNs:
        - matchPattern: "*.azurecr.io"
        - matchPattern: "*.vaultcore.azure.net"
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
    - toEntities:
        - kube-apiserver
    - toCIDR:
        - 10.245.0.0/16   # K8s services
```

FQDN-based egress filtering requires ACNS (Advanced Container Networking Services) to be enabled. Standard Cilium network policies (L3/L4 only) work without ACNS.

### Azure Policy Exemptions

AKS Automatic enables Deployment Safeguards via Azure Policy. ALZ may assign additional policies at the management group level. When policies conflict with AKS system pods (e.g. privilege escalation restrictions on kube-system pods), create exemptions:

```bash
# List policy assignments on the AKS subscription
az policy assignment list --scope /subscriptions/<sub-id> --query "[].{name:name, displayName:displayName}" -o table

# Create an exemption for a specific assignment on the AKS resource
az policy exemption create \
  --name "aks-system-pods" \
  --policy-assignment "<assignment-id>" \
  --exemption-category "Mitigated" \
  --scope "/subscriptions/<sub>/resourceGroups/rg-aks-automatic/providers/Microsoft.ContainerService/managedClusters/aks-automatic-corp" \
  --description "AKS system pods require privileges not permitted by this policy"
```

Common exemptions needed for AKS Automatic:
- `Kubernetes clusters should not allow container privilege escalation` (kube-system components)
- `Kubernetes cluster should not allow privileged containers` (system DaemonSets)
- NSG rule policies that conflict with AKS-injected rules

### Planned Maintenance Windows

AKS Automatic clusters auto-upgrade. Control the timing via maintenance configurations:

```bash
# Set a weekly maintenance window for cluster upgrades (Sunday 02:00-06:00 UTC)
az aks maintenanceconfiguration add \
  --cluster-name aks-automatic-corp \
  --resource-group rg-aks-automatic \
  --name aksManagedAutoUpgradeSchedule \
  --schedule-type Weekly \
  --day-of-week Sunday \
  --start-time 02:00 \
  --duration 4

# Set a separate window for node OS upgrades
az aks maintenanceconfiguration add \
  --cluster-name aks-automatic-corp \
  --resource-group rg-aks-automatic \
  --name aksManagedNodeOSUpgradeSchedule \
  --schedule-type Weekly \
  --day-of-week Saturday \
  --start-time 02:00 \
  --duration 4
```

Allow at least 30 minutes between creating a maintenance configuration and the scheduled start time for AKS to reconcile.

### Certificate and Credential Rotation

- **TLS certificates (App Routing):** When using Key Vault integration, certificates are automatically rotated by the App Routing add-on. Upload the renewed certificate to Key Vault and the add-on picks it up.
- **Workload Identity tokens:** Automatically managed by the Entra ID federated credential mechanism. No manual rotation needed.
- **Cluster certificates:** AKS manages internal cluster certificate rotation. No operator action required.
- **ACR tokens:** When using AcrPull via managed identity, no credentials to rotate. If using image pull secrets (not recommended), rotate them via Key Vault or external secret management.
