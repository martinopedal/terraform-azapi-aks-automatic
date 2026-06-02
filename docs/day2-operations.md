# Day-2 Operations

### Application Gateway for Containers Bootstrap

AGC is the default ingress installed by the Terraform module (`enable_app_gateway_for_containers = true`). Terraform enables the AKS managed ALB Controller and Gateway API add-ons; workloads still need Kubernetes resources to create the AGC data plane.

1. Confirm prerequisites:

   ```bash
   az feature show --namespace Microsoft.ContainerService --name ManagedGatewayAPIPreview --query properties.state -o tsv
   az feature show --namespace Microsoft.ContainerService --name ApplicationLoadBalancerPreview --query properties.state -o tsv
   kubectl get pods -n kube-system -l app=alb-controller
   kubectl get gatewayclass azure-alb-external
   ```

2. Confirm the AGC subnet is a dedicated `/24` delegated to `Microsoft.ServiceNetworking/trafficControllers` and reachable from the AKS node subnet.

3. Create the `ApplicationLoadBalancer` resource that binds AGC to the subnet:

   ```yaml
   apiVersion: v1
   kind: Namespace
   metadata:
     name: agc-infra
   ---
   apiVersion: alb.networking.azure.io/v1
   kind: ApplicationLoadBalancer
   metadata:
     name: agc-default
     namespace: agc-infra
   spec:
     associations:
     - /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<snet-agc>
   ```

4. Deploy `Gateway` and `HTTPRoute` resources using `gatewayClassName: azure-alb-external`.

5. Create DNS (usually CNAME) for the AGC-generated frontend FQDN. Private IP frontends are not available yet, so ALZ policy exceptions must acknowledge the public AGC frontend.

Gotchas:

- Managed NGINX is disabled by default when AGC is enabled. Do not use `webapprouting.kubernetes.azure.com` Ingress unless AGC is explicitly disabled and `enable_managed_nginx = true`.
- UDR/firewall rules must allow ARM and Entra ID endpoints because the ALB Controller configures AGC through Azure APIs.
- The AGC data-plane resource appears after the Kubernetes `ApplicationLoadBalancer` is applied, not immediately after Terraform creates the AKS cluster.

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

Two deployment options are available for ArgoCD on AKS Automatic:

#### Option 1: Managed ArgoCD Extension (recommended)

The [ArgoCD AKS extension](https://learn.microsoft.com/azure/azure-arc/kubernetes/tutorial-use-gitops-argocd) (public preview) is a managed add-on that deploys ArgoCD as an AKS cluster extension. This is the recommended option for enterprise deployments because it provides:

- **Entra ID SSO** built-in (no manual OIDC configuration needed)
- **Workload Identity federation** to ACR and Azure DevOps (no stored credentials)
- **Azure Linux hardened images** with reduced CVE surface
- **Automatic patch releases** (opt-in) for security fixes
- **HA mode** for production workloads
- **Hub-and-spoke** multi-cluster GitOps support

```bash
# Install the ArgoCD managed extension
az k8s-extension create \
  --cluster-name <cluster> \
  --resource-group <rg> \
  --cluster-type managedClusters \
  --extension-type microsoft.argocd \
  --name argocd \
  --configuration-settings \
    "controller.replicas=2" \
    "server.replicas=2"
```

For ALZ Corp private clusters:
- The extension images are pulled from Microsoft-managed registries (no ACR import needed)
- Entra ID SSO is configured automatically via the extension (no `argocd-cm` OIDC setup)
- Workload Identity for ACR/ADO access is managed by the extension
- You still need to configure CiliumNetworkPolicy for namespace isolation (see [ArgoCD bootstrap manifests](argocd/02-network-policy.yaml))
- Expose the UI via Application Routing with internal LB (see [ArgoCD bootstrap manifests](argocd/05-ingress.yaml))

**Terraform integration:** The extension can be deployed as an azapi child resource:

```hcl
resource "azapi_resource" "argocd_extension" {
  type      = "Microsoft.KubernetesConfiguration/extensions@2023-05-01"
  name      = "argocd"
  parent_id = azapi_resource.aks.id

  body = {
    properties = {
      extensionType            = "microsoft.argocd"
      autoUpgradeMinorVersion  = true
      configurationSettings = {
        "controller.replicas" = "2"
        "server.replicas"     = "2"
      }
    }
  }
}
```

#### Option 2: Self-managed ArgoCD (manual bootstrap)

For full control over the ArgoCD version, configuration, and lifecycle, deploy ArgoCD manually using the bootstrap manifests in [docs/argocd/](argocd/README.md). This approach requires:

- Manual image import into private ACR
- Manual Entra ID OIDC SSO configuration
- Manual Workload Identity setup for credential access
- Manual upgrade management

Use this option when you need specific ArgoCD versions, custom plugins, or configurations not supported by the managed extension.

**Self-managed considerations for ALZ Corp private clusters:**

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

### Azure Backup for AKS

AKS backup protects cluster state and application data. Configure backup after cluster deployment:

```bash
# Register the backup extension
az k8s-extension create --cluster-name <cluster> \
  --resource-group <rg> \
  --cluster-type managedClusters \
  --extension-type microsoft.dataprotection.kubernetes \
  --name backup-extension \
  --configuration-settings \
    blobContainer=<container> \
    storageAccount=<storage-account> \
    storageAccountResourceGroup=<storage-rg> \
    storageAccountSubscriptionId=<sub-id>

# Create a backup vault (if not provided by ALZ platform team)
az dataprotection backup-vault create \
  --vault-name <vault-name> \
  --resource-group <rg> \
  --storage-setting "[{type:LocallyRedundant,datastore-type:VaultStore}]"

# Create a backup policy
az dataprotection backup-policy create \
  --vault-name <vault-name> \
  --resource-group <rg> \
  --name aks-daily \
  --policy @backup-policy.json

# Configure backup instance
az dataprotection backup-instance create \
  --vault-name <vault-name> \
  --resource-group <rg> \
  --backup-instance @backup-instance.json
```

For ALZ Corp, the backup vault should be in the management subscription with cross-subscription access configured. See [AKS backup overview](https://learn.microsoft.com/azure/backup/azure-kubernetes-service-backup-overview).

### Alerting and Monitoring Rules

This module enables Managed Prometheus metrics and optionally Container Insights logs, but does not create alert rules. Configure alerts after deployment:

**Prometheus alert rules (via Azure Monitor workspace):**

| Alert | Query | Severity |
|---|---|---|
| Node not ready | ``kube_node_status_condition{condition="Ready",status="true"} == 0`` | Critical |
| Pod crash looping | ``increase(kube_pod_container_status_restarts_total[1h]) > 5`` | High |
| High CPU usage | ``avg(rate(container_cpu_usage_seconds_total[5m])) by (namespace) > 0.8`` | Medium |
| PVC nearly full | ``kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes > 0.9`` | High |
| API server latency | ``histogram_quantile(0.99, rate(apiserver_request_duration_seconds_bucket[5m])) > 1`` | High |

Create these as PrometheusRuleGroups in the Azure Monitor workspace, or use the AKS recommended alert rules via the Azure portal.

For ALZ Corp with Azure Monitor Baseline Alerts (AMBA), review whether AMBA's AKS rules are compatible with the Managed Prometheus data source.

### Cost Optimization with Reserved Instances

For predictable base workloads, Azure Reserved VM Instances can reduce compute costs by 30-72%:

1. **Analyze usage patterns**: Use AKS cost analysis (``enable_cost_analysis = true``) for 30+ days to identify steady-state VM families
2. **Purchase reservations**: Target the VM families that Karpenter/NAP consistently selects (check ``karpenter_nodes_allocatable`` Prometheus metric)
3. **Scope to subscription**: Scope reservations to the AKS spoke subscription for automatic application
4. **Combine with spot**: Use Karpenter ``NodePool`` CRDs with ``karpenter.azure.com/priority: spot`` for interruptible batch workloads

Note: NAP/Karpenter dynamically selects VM sizes. Reserved Instances work best when the workload has a predictable baseline that consistently uses the same VM family.

### Container Image Signing and Supply Chain Security

AKS Automatic secures the container supply chain through ACR with private endpoints and admin user disabled. For additional hardening:

1. **Image signing with Notation**: Sign container images using [Notation](https://notaryproject.dev/) and verify signatures with [Ratify](https://ratify.dev/) on AKS
2. **ACR Tasks for automated scanning**: Configure ACR Tasks to scan images on push using Microsoft Defender for Containers
3. **Admission control**: Use Azure Policy with the ``ContainerAllowedImages`` policy to restrict images to your private ACR only
4. **SBOM generation**: Generate Software Bill of Materials with ``syft`` or ``trivy`` and attach to images as OCI artifacts

```bash
# Sign an image with Notation (requires Azure Key Vault key)
notation sign --signature-format cose \
  ${ACR_SERVER}/myapp:v1.0 \
  --plugin azure-kv \
  --id https://<vault>.vault.azure.net/keys/<key>/<version>
```

For ALZ Corp, image signing keys should be stored in the module-created Key Vault (``create_keyvault = true``) with RBAC access for the CI/CD pipeline identity.

### Ingress Migration: Application Routing to AGC / Gateway API

This module uses Application Routing add-on (managed NGINX) with `Ingress` resources as the recommended Corp ingress. Two future changes will require a migration:

1. **Application Gateway for Containers (AGC)** becomes available on AKS Automatic with private IP frontends
2. **Gateway API** replaces the Kubernetes `Ingress` API as the long-term standard

**Current blockers (as of April 2026):**

| Blocker | Status | Tracking |
|---|---|---|
| AGC add-on not supported on AKS Automatic | Waiting on product team | [AGC ALB Controller add-on](https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-deploy-application-gateway-for-containers-alb-controller-addon) |
| AGC frontends are public-only (no private IP) | In development | [AGC Components](https://learn.microsoft.com/azure/application-gateway/for-containers/application-gateway-for-containers-components) |
| Application Routing uses Ingress API, not Gateway API | Migration planned by AKS team | [Application Routing](https://learn.microsoft.com/azure/aks/app-routing) |
| Ingress NGINX upstream maintenance ended March 2026 | Microsoft patches through Nov 2026 | AKS release notes |

**Readiness checklist (check before starting migration):**

- [ ] AGC add-on is GA on AKS Automatic (check AKS release notes)
- [ ] AGC supports private IP frontends (check AGC docs)
- [ ] AGC is available in your target region (Norway East: check [Products by Region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/))
- [ ] Gateway API CRDs (`GatewayClass`, `Gateway`, `HTTPRoute`) are supported by Application Routing or AGC

**Migration plan: Application Routing (NGINX) to AGC**

Phase 1 - Prepare (no downtime):
```bash
# 1. Create the AGC subnet (delegated to Microsoft.ServiceNetworking/trafficControllers)
#    Add to variables.tf or have the ALZ vending pipeline provision it
#    Recommended: /24 in the spoke VNet

# 2. Deploy AGC resource via Terraform (add to main.tf or a new agc.tf)
#    Resource type: Microsoft.ServiceNetworking/trafficControllers
#    Requires: AGC subnet, managed identity with Network Contributor on subnet

# 3. Install the ALB Controller add-on on AKS Automatic
#    This will be an azapi_resource property once supported:
#    properties.ingressProfile.applicationGatewayForContainers.enabled = true

# 4. Create a Gateway resource with private IP frontend
#    (once private IP is supported)
```

Phase 2 - Parallel run (validate before cutover):
```yaml
# Create a Gateway + HTTPRoute alongside the existing Ingress
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: agc-internal
  namespace: my-app
  annotations:
    alb.networking.azure.io/alb-id: <agc-resource-id>
spec:
  gatewayClassName: azure-alb-internal  # private IP class
  listeners:
    - name: https
      protocol: HTTPS
      port: 443
      tls:
        mode: Terminate
        certificateRefs:
          - name: agc-tls-cert
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-app
spec:
  parentRefs:
    - name: agc-internal
  hostnames:
    - "myapp.corp.contoso.com"
  rules:
    - backendRefs:
        - name: my-app-svc
          port: 80
```

Phase 3 - Cutover:
```bash
# 1. Update DNS to point to AGC internal IP instead of NGINX internal LB IP
# 2. Verify traffic flows through AGC
# 3. Remove the old Ingress resources
# 4. Disable Application Routing NGINX (if no longer needed):
#    Set ingressProfile.webAppRouting.enabled = false in main.tf
# 5. Delete the NginxIngressController CR (if using internal LB config)
```

Phase 4 - Cleanup:
```bash
# 1. Remove old Ingress manifests from GitOps repo
# 2. Update ArgoCD ingress (docs/argocd/05-ingress.yaml) to use Gateway API
# 3. Update CiliumNetworkPolicies to allow AGC traffic instead of app-routing-system
# 4. Update terraform.tfvars and documentation
```

**Terraform module changes needed at cutover:**

| File | Change |
|---|---|
| `main.tf` | Add `applicationGatewayForContainers` to `ingressProfile` |
| `variables.tf` | Add `enable_agc`, `agc_subnet_id` variables |
| `network.tf` | Add AGC subnet with delegation (if module-created VNet) |
| `dependencies.tf` | Add AGC resource (`Microsoft.ServiceNetworking/trafficControllers`) |
| `docs/argocd/05-ingress.yaml` | Replace `Ingress` with `Gateway` + `HTTPRoute` |

**Timeline guidance:**

- **Now:** Use Application Routing with internal LB (this module's default)
- **When AGC ships on Automatic + private IP:** Run Phase 1-2 in parallel, validate
- **Before Nov 2026:** Complete cutover (Microsoft NGINX patches end)
- **Long-term:** All ingress via Gateway API (AGC or other Gateway API controllers)
