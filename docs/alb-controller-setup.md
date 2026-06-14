# Application Gateway for Containers - ALB Controller Setup

## Overview

Application Gateway for Containers (AGC) requires the **ALB Controller** to reconcile Kubernetes Gateway API resources (Gateway, HTTPRoute) into AGC data plane configuration. This document explains the full wiring required for the controller, including managed identity, workload identity federation, RBAC assignments, and Helm installation.

This module implements **Option 2: Helm-based ALB Controller with Workload Identity** (canonical for production) rather than the AKS-managed extension.

---

## Architecture

### Components

1. **User-Assigned Managed Identity** (`uami-alb-<cluster_name>`)
   - Created in the AKS resource group
   - Used by the ALB Controller ServiceAccount via Workload Identity

2. **Federated Identity Credential**
   - Links the managed identity to the Kubernetes ServiceAccount `azure-alb-system/alb-controller-sa`
   - Uses the AKS cluster's OIDC issuer URL
   - Audience: `api://AzureADTokenExchange`

3. **RBAC Role Assignments**
   - **AppGw for Containers Configuration Manager** (role GUID `fbc52c3f-28ad-4303-a892-8a056630b8f1`) on the AGC Traffic Controller
   - **Network Contributor** (role GUID `4d97b98b-1d4f-4787-a291-c67834d212e7`) on the AGC subnet (`snet-agc`)

4. **Helm Release** (managed outside Terraform)
   - Chart: `oci://mcr.microsoft.com/application-lb/charts/alb-controller`
   - Namespace: `azure-alb-system`
   - Values:
     ```yaml
     albController:
       namespace: azure-alb-system
       podIdentity:
         clientID: <uami_client_id>
     ```

---

## Live Deployment Example (SRE Agent Demo)

**Cluster:** `aks-sreagt-store-dmo-swc-001`  
**Resource Group:** `rg-sreagt-dmo-swc-001`  
**Managed Identity:** `uami-alb-sreagt-dmo`

### 1. Managed Identity

```bash
az identity show \
  --name uami-alb-sreagt-dmo \
  --resource-group rg-sreagt-dmo-swc-001 \
  --query "{clientId: clientId, principalId: principalId}"
```

**Output:**
```json
{
  "clientId": "4aeeeffa-d69b-4dd9-bff3-5ace69da27ca",
  "principalId": "9baec489-c99d-4320-866e-3b7eaea1055f"
}
```

### 2. Federated Credential

**Issuer URL:**
```
https://swedencentral.oic.prod-aks.azure.com/500bedc4-517a-4594-95f9-ff240f25bb12/e3d29b0c-8c61-4d2a-a717-24f244839ce6/
```

**Subject:** `system:serviceaccount:azure-alb-system:alb-controller-sa`

**Audience:** `["api://AzureADTokenExchange"]`

Verified via:
```bash
az rest --method GET \
  --url "https://graph.microsoft.com/beta/applications/<app-object-id>/federatedIdentityCredentials"
```

### 3. RBAC Assignments

#### On AGC Traffic Controller

```bash
az role assignment list \
  --assignee 9baec489-c99d-4320-866e-3b7eaea1055f \
  --scope /subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-sreagt-dmo-swc-001/providers/Microsoft.ServiceNetworking/trafficControllers/tc-sreagt-store-dmo-swc-001
```

**Role:** AppGw for Containers Configuration Manager (`fbc52c3f-28ad-4303-a892-8a056630b8f1`)

#### On AGC Subnet

```bash
az role assignment list \
  --assignee 9baec489-c99d-4320-866e-3b7eaea1055f \
  --scope /subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-demo-sre-agent-dnb-prod/providers/Microsoft.Network/virtualNetworks/vnet-sre-agent-dnb-prod/subnets/snet-agc
```

**Role:** Network Contributor (`4d97b98b-1d4f-4787-a291-c67834d212e7`)

### 4. Helm Installation (Manual - Not Yet in Terraform)

**⚠️ CURRENT STATE:** The Terraform module provisions the managed identity, federated credential, and RBAC assignments, but the **Helm release is not yet codified**. The controller was installed manually via:

```bash
helm install alb-controller \
  oci://mcr.microsoft.com/application-lb/charts/alb-controller \
  --namespace azure-alb-system \
  --create-namespace \
  --set albController.namespace=azure-alb-system \
  --set albController.podIdentity.clientID=4aeeeffa-d69b-4dd9-bff3-5ace69da27ca
```

**TODO:** Add a `helm_release` resource to `alb-controller.tf` or create a separate `helm.tf` file with the Helm provider configured. Requires:
- Helm provider block in `terraform.tf`
- AKS cluster kubeconfig data source
- `kubelogin` exec block for Azure RBAC auth

---

## Terraform Implementation

### File Structure

- **`alb-controller.tf`**: Managed identity, federated credential, RBAC assignments
- **`agc.tf`**: AGC Traffic Controller, frontend, subnet association, and AKS-managed extension (alternative to Helm)
- **`variables.tf`**: `enable_alb_helm_controller`, `alb_controller_identity_name`
- **`locals.tf`**: `alb_controller_identity_name` default (`uami-alb-<cluster_name>`)

### Variables

```hcl
variable "enable_alb_helm_controller" {
  description = "Enable the ALB Controller via Helm with dedicated managed identity and workload identity. Default: true."
  type        = bool
  default     = true
}

variable "alb_controller_identity_name" {
  description = "Name of the user-assigned managed identity for the ALB Controller. Defaults to uami-alb-<cluster_name>."
  type        = string
  default     = null
}
```

### Resources

**1. Managed Identity** (`alb-controller.tf`):

```hcl
resource "azapi_resource" "alb_controller_identity" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller ? 1 : 0
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview"
  name      = local.alb_controller_identity_name
  location  = local.rg_location
  parent_id = local.rg_id
  tags      = local.tags

  body = {}
}
```

**2. Federated Credential**:

```hcl
resource "azapi_resource" "alb_controller_federated_credential" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller ? 1 : 0
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-07-31-preview"
  name      = "alb-controller-fedcred"
  parent_id = azapi_resource.alb_controller_identity[0].id

  body = {
    properties = {
      audiences = ["api://AzureADTokenExchange"]
      issuer    = azapi_resource.aks.output.properties.oidcIssuerProfile.issuerURL
      subject   = "system:serviceaccount:azure-alb-system:alb-controller-sa"
    }
  }
}
```

**3. RBAC - AppGw for Containers Configuration Manager** on AGC:

```hcl
resource "azapi_resource" "role_alb_agc_config_manager" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${azapi_resource.agc[0].id}-alb-config-manager")
  parent_id = azapi_resource.agc[0].id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/fbc52c3f-28ad-4303-a892-8a056630b8f1"
      principalId      = azapi_resource.alb_controller_identity[0].output.properties.principalId
      principalType    = "ServicePrincipal"
    }
  }
}
```

**4. RBAC - Network Contributor** on AGC subnet:

```hcl
resource "azapi_resource" "role_alb_subnet_network_contributor" {
  count     = var.enable_app_gateway_for_containers && var.enable_alb_helm_controller && local.agc_subnet_id != null ? 1 : 0
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  name      = uuidv5("dns", "${local.agc_subnet_id}-alb-network-contributor")
  parent_id = local.agc_subnet_id

  body = {
    properties = {
      roleDefinitionId = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/4d97b98b-1d4f-4787-a291-c67834d212e7"
      principalId      = azapi_resource.alb_controller_identity[0].output.properties.principalId
      principalType    = "ServicePrincipal"
    }
  }
}
```

---

## Alternative: AKS-Managed Extension

The module also provisions the AKS-managed ALB Controller extension in `agc.tf`:

```hcl
resource "azapi_resource" "alb_controller_extension" {
  count     = var.enable_app_gateway_for_containers ? 1 : 0
  type      = "Microsoft.KubernetesConfiguration/extensions@2024-11-01"
  name      = "alb-controller"
  parent_id = azapi_resource.aks.id

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      extensionType           = "microsoft.albcontroller"
      autoUpgradeMinorVersion = true
      releaseTrain            = "Stable"
      scope = {
        cluster = {
          releaseNamespace = "kube-system"
        }
      }
    }
  }
}
```

**Difference:**
- **Extension**: System-assigned identity, automatically wired by AKS RP, no Helm release needed
- **Helm**: User-assigned identity + federated credential, explicit RBAC, Helm chart version control

The module provisions **both** for flexibility. In practice:
- Use **extension** for quick proof-of-concept (fewer moving parts)
- Use **Helm** for production (explicit RBAC, version pinning, multi-cluster consistency)

Set `enable_alb_helm_controller = false` to use only the extension.

---

## Verification

### 1. Check Managed Identity

```bash
az identity show \
  --name uami-alb-<cluster_name> \
  --resource-group <rg_name> \
  --query "{clientId: clientId, principalId: principalId}"
```

### 2. Check Federated Credential

```bash
az rest --method GET \
  --url "https://graph.microsoft.com/beta/applications/<app-object-id>/federatedIdentityCredentials" \
  | jq '.value[] | select(.subject | contains("alb-controller-sa"))'
```

### 3. Check RBAC on AGC

```bash
az role assignment list \
  --assignee <principal_id> \
  --scope <agc_resource_id> \
  --query "[].{role: roleDefinitionName, scope: scope}"
```

### 4. Check RBAC on Subnet

```bash
az role assignment list \
  --assignee <principal_id> \
  --scope <subnet_id> \
  --query "[].{role: roleDefinitionName, scope: scope}"
```

### 5. Check ALB Controller Pods

```bash
kubectl get pods -n azure-alb-system
kubectl logs -n azure-alb-system -l app=alb-controller --tail=50
```

### 6. Check Gateway API CRDs

```bash
kubectl get crd | grep gateway.networking.k8s.io
```

Expected:
```
gatewayclasses.gateway.networking.k8s.io
gateways.gateway.networking.k8s.io
httproutes.gateway.networking.k8s.io
```

### 7. Check GatewayClass

```bash
kubectl get gatewayclass azure-alb-external -o yaml
```

Expected `status.conditions`:
```yaml
status:
  conditions:
  - type: Accepted
    status: "True"
```

---

## Troubleshooting

### Gateway Not Getting an Address

**Symptom:** Gateway status shows no `addresses` field after 5+ minutes.

**Check:**
1. ALB Controller logs: `kubectl logs -n azure-alb-system -l app=alb-controller`
2. Gateway events: `kubectl describe gateway <gateway_name> -n <namespace>`
3. RBAC on AGC: `az role assignment list --assignee <principal_id> --scope <agc_id>`
4. Federated credential subject matches the ServiceAccount: `system:serviceaccount:azure-alb-system:alb-controller-sa`

### Pod Identity Token Errors

**Symptom:** ALB Controller logs show `failed to acquire token` or `AADSTS700016: invalid issuer`.

**Fix:**
1. Verify OIDC issuer URL matches the federated credential: `az aks show --name <cluster> --resource-group <rg> --query "oidcIssuerProfile.issuerUrl"`
2. Ensure audience is `api://AzureADTokenExchange`
3. Confirm the ServiceAccount exists: `kubectl get sa alb-controller-sa -n azure-alb-system`
4. Check ServiceAccount annotations:
   ```bash
   kubectl get sa alb-controller-sa -n azure-alb-system -o yaml
   ```
   Expected:
   ```yaml
   metadata:
     annotations:
       azure.workload.identity/client-id: <uami_client_id>
   ```

---

## References

- [Application Gateway for Containers Documentation](https://learn.microsoft.com/azure/application-gateway/for-containers/)
- [ALB Controller Helm Chart](https://learn.microsoft.com/azure/application-gateway/for-containers/quickstart-deploy-application-gateway-for-containers-alb-controller)
- [Workload Identity for AKS](https://learn.microsoft.com/azure/aks/workload-identity-overview)

---

## Changelog

- **2026-06-09**: Initial documentation after codifying ALB Controller setup in `alb-controller.tf`
