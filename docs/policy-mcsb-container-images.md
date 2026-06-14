# Azure Policy MCSB Container Image Blocker - Known Issue & Exemption

## Overview

The **Deploy-MCSB2-Monitoring** Azure Policy assignment (Microsoft Cloud Security Benchmark initiative) at the `alz` management group includes the **"allowed container images"** policy definition (`febd0533-8e55-448f-b837-bd0e06f16469`) with an **empty regex pattern** `^(.+){0}$` that matches **nothing**, effectively **denying ALL container images** across every AKS cluster in the ALZ estate.

This document explains the estate-wide root cause, the interim demo-scoped exemption codified in this module, and the required governance fix in `alz-avm-tf-demo/alz-prod`.

---

## Root Cause (Estate-Wide)

### Policy Assignment

**Scope:** `/providers/Microsoft.Management/managementGroups/alz`  
**Assignment ID:** `Deploy-MCSB2-Monitoring`  
**Initiative:** Microsoft Cloud Security Benchmark (MCSB)  
**Policy Definition:** `febd0533-8e55-448f-b837-bd0e06f16469` (allowed container images)  

### Parameter Value (Broken)

The policy is parameterized with `allowedContainerImagesRegex`, currently set to:

```json
{
  "allowedContainerImagesRegex": {
    "value": "^(.+){0}$"
  }
}
```

**Regex breakdown:**
- `^` = Start of string
- `(.+){0}` = "One or more characters" repeated **zero times** (matches nothing)
- `$` = End of string

**Result:** No image name can match this regex → all images are **denied** by the policy.

### Impact

Every AKS cluster in the ALZ estate that is:
- Under the `alz` management group hierarchy (all landing zone subscriptions)
- Attempting to deploy a pod with a container image

…will be **blocked** by Azure Policy with an error similar to:

```
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request:
[azurepolicy-k8sazurev3allowedcontainerimagesregex-<hash>] Container image <image_name> is not allowed. Allowed images regex: ^(.+){0}$
```

This breaks:
- All CI/CD pipelines deploying workloads to AKS
- Manual `kubectl apply` of any deployment/pod
- Helm chart installations
- ArgoCD/Flux GitOps sync operations

**Estate-wide severity:** **CRITICAL** – Blocks all AKS workload deployments.

---

## Observed on SRE Agent Demo Cluster

**Cluster:** `aks-sreagt-store-dmo-swc-001`  
**Resource Group:** `rg-sreagt-dmo-swc-001`  
**Subscription:** `147f910d-d9c8-40ca-8455-2ea5219765e5` (sub-9, landing zone)

When attempting to apply the store-app manifests:

```bash
kubectl apply -k manifests/
```

**Error:**
```
Error from server (Forbidden): error when creating "manifests/deployment.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [azurepolicy-k8sazurev3allowedcontainerimagesregex-<hash>] Container image crsreagtdmoswc001.azurecr.io/store-nginx:1.22 is not allowed. Allowed images regex: ^(.+){0}$
```

The policy blocks the `store-nginx` image (and any other image) from being scheduled on the cluster.

---

## Interim Workaround: Demo-Scoped Policy Exemption

This module codifies a **resource group-scoped policy exemption** to allow the SRE Agent demo to deploy its manifests while the estate-wide fix is pending in `alz-prod`.

### Exemption Details

**File:** `policy-exemptions.tf`

**Resource:**
```hcl
resource "azapi_resource" "policy_exemption_mcsb_k8s" {
  count     = var.enable_policy_exemption_mcsb_k8s ? 1 : 0
  type      = "Microsoft.Authorization/policyExemptions@2022-07-01-preview"
  name      = "exempt-mcsb-k8s-sreagt-store-demo"
  parent_id = local.rg_id

  body = {
    properties = {
      policyAssignmentId = "/providers/Microsoft.Management/managementGroups/alz/providers/Microsoft.Authorization/policyAssignments/Deploy-MCSB2-Monitoring"
      exemptionCategory  = "Waiver"
      displayName        = "MCSB K8s Container Image Policy - SRE Agent Demo Exemption"
      description        = "..."
      expiresOn          = timeadd(timestamp(), "720h") # 30 days
      policyDefinitionReferenceIds = [
        "ensureAllowedContainerImagesInKubernetesCluster",
        "kubernetesClustersShouldBeAccessibleOnlyOverHTTPSMonitoringEffect",
        "allowedServicePortsInKubernetesCluster"
      ]
    }
  }

  lifecycle {
    precondition {
      condition     = var.resource_group_name == "rg-sreagt-dmo-swc-001"
      error_message = "This policy exemption is demo-scoped and must only be applied to rg-sreagt-dmo-swc-001."
    }
  }
}
```

**Scope:** `rg-sreagt-dmo-swc-001` only (enforced in lifecycle precondition)  
**Expiry:** 30 days from `terraform apply`  
**Category:** Waiver (explicitly acknowledging the policy requirement but choosing to exempt)

### Exempted Policy Definition References

The exemption targets three policy definition reference IDs from the MCSB initiative:

1. **`ensureAllowedContainerImagesInKubernetesCluster`**  
   The deny-all regex policy blocking all images.

2. **`kubernetesClustersShouldBeAccessibleOnlyOverHTTPSMonitoringEffect`**  
   Ensures Kubernetes API server is HTTPS-only (already enforced by AKS, included for consistency).

3. **`allowedServicePortsInKubernetesCluster`**  
   Restricts service port ranges (may conflict with AGC or demo services, included to avoid secondary blocks).

### Deployment

**Enable the exemption:**

In `terraform.tfvars`:
```hcl
enable_policy_exemption_mcsb_k8s = true
```

**Verify after apply:**
```bash
az policy exemption show \
  --name exempt-mcsb-k8s-sreagt-store-demo \
  --scope /subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-sreagt-dmo-swc-001
```

**Check expiry:**
```bash
az policy exemption show \
  --name exempt-mcsb-k8s-sreagt-store-demo \
  --scope /subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-sreagt-dmo-swc-001 \
  --query "expiresOn"
```

---

## Permanent Fix: Correct the Regex at `alz` Management Group

The **correct** fix is to update the MCSB policy assignment at the `alz` management group to use a permissive regex (or remove the parameter to use the policy's default).

### Recommended Regex

```json
{
  "allowedContainerImagesRegex": {
    "value": ".*"
  }
}
```

**Or** (more restrictive, allow Azure Container Registry and major public registries):

```json
{
  "allowedContainerImagesRegex": {
    "value": "^(.*\\.azurecr\\.io|mcr\\.microsoft\\.com|docker\\.io|ghcr\\.io|quay\\.io)/.*$"
  }
}
```

### Implementation Location

**Repo:** `alz-avm-tf-demo/alz-prod`  
**File:** `main.management.tf` or `policy-assignments.tf` (wherever MCSB is assigned)  
**Module:** Likely using the AVM ALZ Management pattern module (`Azure/avm-ptn-alz-management`)

**Action Required:**
1. Locate the MCSB initiative assignment parameter block in `alz-prod`
2. Update `allowedContainerImagesRegex` from `^(.+){0}$` to `.*` (or the ACR-only regex above)
3. Run `terraform plan` to verify the change
4. Apply the change via the ALZ deployment pipeline
5. Wait for Azure Policy propagation (~15-30 minutes)
6. Verify with a test pod deployment in a non-exempted AKS cluster

### Post-Fix Cleanup

Once the `alz` management group policy assignment is corrected:

1. Remove the demo-scoped exemption from this module:
   ```hcl
   enable_policy_exemption_mcsb_k8s = false
   ```
2. Run `terraform apply` to delete the exemption resource
3. Verify that the store-app manifests can still be applied (the corrected regex at the mgmt group now allows them)

---

## Why Not Fix It Here?

This module **cannot** modify the management group policy assignment because:

1. **RBAC scope:** This module runs with contributor/owner on the landing zone subscription (`sub-9`). Management group policy assignments require **Policy Contributor** or **Owner** at the management group scope, which is a platform-team permission.

2. **Blast radius:** The MCSB assignment affects **all** landing zone subscriptions under the `alz` management group. Changing it is a **platform governance decision**, not a workload-specific decision.

3. **Separation of concerns:** Landing zone workloads (this AKS cluster) should not modify platform-level guardrails. The policy assignment belongs in `alz-prod` alongside other ALZ baseline policies (Defender, networking, tagging, etc.).

---

## Detection: How to Find This on Other Clusters

Run this query to check if any AKS cluster in a subscription is blocked by the same policy:

```bash
az policy state list \
  --subscription <subscription_id> \
  --filter "policyDefinitionReferenceId eq 'ensureAllowedContainerImagesInKubernetesCluster' and complianceState eq 'NonCompliant'" \
  --query "[].{cluster: resourceId, state: complianceState, message: policyDefinitionAction}"
```

Or check Gatekeeper constraint violations on the cluster:

```bash
kubectl get constraints -A
kubectl describe k8sazurev3allowedcontainerimagesregex <constraint_name>
```

Look for events showing denied image names.

---

## Governance Recommendation

**ALZ Platform Team Action Items:**

1. **Audit all MCSB policy parameters** at the `alz` management group for deny-all or overly-restrictive patterns.
2. **Update the default MCSB parameter file** in `alz-prod` to use permissive or registry-scoped regex values.
3. **Test the updated policy assignment** on a canary landing zone subscription before rolling out estate-wide.
4. **Document approved container registries** in the ALZ governance runbook (e.g., *.azurecr.io, mcr.microsoft.com, docker.io for OSS base images).
5. **Notify landing zone teams** that policy exemptions are temporary and will expire; workloads must comply with the corrected regex once deployed.

---

## References

- [Azure Policy for Kubernetes](https://learn.microsoft.com/azure/governance/policy/concepts/policy-for-kubernetes)
- [MCSB Initiative](https://learn.microsoft.com/security/benchmark/azure/mcsb-kubernetes)
- [Policy Exemptions](https://learn.microsoft.com/azure/governance/policy/concepts/exemption-structure)
- ALZ Corp decision ledger: `.squad/decisions.md` in `alz-avm-tf-demo/alz-prod`

---

## Changelog

- **2026-06-09**: Initial documentation after discovering the deny-all regex on `aks-sreagt-store-dmo-swc-001` and codifying the demo-scoped exemption.
