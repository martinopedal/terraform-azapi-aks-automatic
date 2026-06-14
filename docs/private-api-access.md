# Private API Server Access Constraint

## Overview

AKS Automatic clusters deployed with **private API Server VNet Integration** have a critical access constraint: the Kubernetes API server is **only reachable from the node subnet** (`snet-aks-nodes`). Consumption-based compute (Azure Container Apps runners, Azure Container Instances, non-node-subnet VMs) **cannot** reach the API and will experience connection timeouts on all `kubectl` commands.

This document explains the architecture, demonstrates the live constraint from the SRE Agent demo cluster, and provides remediation options for CI/CD pipelines and operational tooling.

---

## Architecture

### Private API Server VNet Integration (AKS Automatic)

AKS Automatic clusters always use **VNet Integration** for the API server. When `enable_private_cluster = true`, the cluster API is:

- Deployed as an **Internal Load Balancer (ILB)** on the API server subnet (`snet-apiserver`)
- Assigned a private IP address (e.g., `10.16.0.132` in the SRE Agent demo cluster `aks-sreagt-store-dmo-swc-001`)
- Accessible **only** from the **node subnet** (`snet-aks-nodes`, `10.16.0.192/26` in the demo)

This is **not** a Private Link endpoint (standard private cluster model). VNet Integration uses a delegated subnet (`Microsoft.ContainerService/managedClusters`) and the API server ILB binds to that subnet, but Azure restricts network reachability to the node subnet for security isolation.

### Network Topology (SRE Agent Demo)

```
VNet: vnet-sre-agent-dnb-prod (10.16.0.0/24)
├── snet-apiserver (10.16.0.0/28, delegated to AKS)
│   └── API Server ILB: 10.16.0.132
├── snet-aks-nodes (10.16.0.192/26)
│   └── AKS worker nodes → CAN reach 10.16.0.132 ✅
├── snet-agc (10.16.0.128/26, delegated to AGC Traffic Controller)
└── Other subnets (PE, etc.)
    └── Consumption ACA runners, ACI, VMs → CANNOT reach 10.16.0.132 ❌
```

**Key finding**: Even though the Consumption ACA runner pool `[self-hosted, linux, demo-private, sub9]` is in the same subscription and uses a private VNet integration, it does **not** connect to `snet-aks-nodes` and therefore cannot reach the private API server at `10.16.0.132`.

---

## Live Validation (SRE Agent Demo)

**Cluster:** `aks-sreagt-store-dmo-swc-001`  
**Resource Group:** `rg-sreagt-dmo-swc-001`  
**API Server Private IP:** `10.16.0.132`

### Test 1: From Consumption ACA Runner (FAILS)

The `.github/workflows/deploy.yml` `apply-manifests` job runs on:

```yaml
runs-on: [self-hosted, linux, demo-private, sub9]
```

When this job attempts `kubectl cluster-info`, it **times out** because the runner cannot reach `10.16.0.132`. The AGC frontend returns `ERR_EMPTY_RESPONSE` because the Gateway/HTTPRoute Kubernetes resources were never applied (the `apply-manifests` step fails before applying them).

### Test 2: From Node Subnet (SUCCESS)

When kubectl commands are executed from:
- An AKS node pod (e.g., via `kubectl debug node/<node-name> -it --image=ubuntu`)
- A VM deployed into `snet-aks-nodes`
- An in-cluster Kubernetes Job (which runs on a node, therefore in `snet-aks-nodes`)

…the API server responds normally at `10.16.0.132` and all kubectl operations succeed.

---

## Implications for CI/CD Pipelines

### Current State (Broken)

The `deploy.yml` workflow:

1. **`plan` and `apply` jobs** run Terraform on the Consumption ACA runner → **Work fine** (only interact with ARM control plane, not the cluster API)
2. **`apply-manifests` job** runs kubectl on the same runner → **Fails** (cannot reach private API)

Result: The AKS cluster and AGC infrastructure deploy successfully, but the store-app manifests (namespace, deployment, service, gateway, httproute) are **never applied**, leaving the AGC frontend with no backend routes → `ERR_EMPTY_RESPONSE`.

### Required Fix

In-cluster kubectl steps must run from **node-subnet compute**. Choose one of the following options:

---

## Remediation Options

### Option A: Self-Hosted Runner in Node Subnet (Recommended for production)

Deploy a dedicated self-hosted GitHub Actions runner (VM or VMSS) with a NIC in `snet-aks-nodes`.

**Pros:**
- Native kubectl access (no kubeconfig conversion complexity)
- Can run pre/post apply validation
- Suitable for multi-repo pipelines (alz-firewall-ops, alz-prod, etc.)

**Cons:**
- Additional infrastructure cost (VM always-on or VMSS scale-to-zero)
- Requires RBAC (Azure Kubernetes Service Cluster User + Kubernetes RBAC role)

**Implementation:**
1. Provision a VM or VMSS in `snet-aks-nodes` with GitHub Actions runner installed
2. Register the runner with labels like `[self-hosted, linux, aks-node-subnet, sub9]`
3. Update `deploy.yml`:
   ```yaml
   apply-manifests:
     runs-on: [self-hosted, linux, aks-node-subnet, sub9]
   ```

**Security:** Runner should use Workload Identity (federated credential) for Azure auth, not secrets.

---

### Option B: In-Cluster Kubernetes Job

Deploy manifests via a Kubernetes Job that runs **inside the cluster** (on a node, therefore in `snet-aks-nodes` by definition).

**Pros:**
- No external infrastructure (the cluster is the compute)
- Kubernetes-native pattern

**Cons:**
- Requires a bootstrap path (the first Job must be applied by someone with kubectl access)
- Chicken-and-egg for the workflow dispatch (who triggers the Job?)
- Less suitable for ad-hoc `kubectl` debugging

**Implementation:**
1. Create a Kubernetes ServiceAccount with RBAC permissions for namespace/deployment/gateway operations
2. Deploy a Job manifest that:
   - Mounts the manifests via ConfigMap or pulls from Git
   - Runs `kubectl apply -k manifests/`
3. Workflow triggers the Job via `kubectl create job --from=cronjob/manifest-applier`

**Example Job manifest:**
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: apply-store-app
  namespace: azure-alb-system
spec:
  template:
    spec:
      serviceAccountName: manifest-applier
      containers:
      - name: kubectl
        image: bitnami/kubectl:latest
        command: ["kubectl", "apply", "-k", "/manifests"]
        volumeMounts:
        - name: manifests
          mountPath: /manifests
      volumes:
      - name: manifests
        configMap:
          name: store-app-manifests
      restartPolicy: OnFailure
```

**Workflow step:**
```yaml
- name: Apply manifests via in-cluster Job
  run: |
    kubectl create job --from=cronjob/manifest-applier manifest-applier-${{ github.run_id }}
    kubectl wait --for=condition=complete --timeout=300s job/manifest-applier-${{ github.run_id }}
```

---

### Option C: Azure Container Instances with VNet Integration

Deploy an ACI container group with VNet integration on `snet-aks-nodes` to run kubectl commands.

**Pros:**
- Ephemeral (pay only when running)
- No persistent VM to manage

**Cons:**
- ACI VNet integration requires a dedicated subnet (cannot share `snet-aks-nodes` with AKS nodes)
- Adds network complexity (need a second subnet in node address space)
- Less mature than VM-based runners for GitHub Actions

**Implementation:** Requires rearchitecting the VNet subnets to carve out a `/28` for ACI from the `/26` node subnet CIDR, which would require cluster re-creation. **Not recommended** unless the VNet is being redesigned anyway.

---

### Option D: Azure Bastion + Jump Box (Development/Debugging Only)

For ad-hoc kubectl access during development:

1. Deploy a jump box VM in `snet-aks-nodes`
2. Connect via Azure Bastion or SSH
3. Run kubectl from the jump box

**Not suitable for automated CI/CD pipelines.**

---

## Estate-Wide Implications

This constraint affects **all private AKS Automatic clusters** in the ALZ estate. When designing CI/CD for AKS workloads:

1. **Terraform apply** (control plane only) → Can run on any runner with ARM access
2. **kubectl / helm apply** (data plane) → **Must** run from node-subnet compute or in-cluster

**Recommendation for ALZ governance:**
- Document this constraint in the AKS subscription vending runbook
- Provide a reference runner VMSS module for node-subnet self-hosted runners
- Consider an ALZ-central "kubectl jump box" pattern for low-frequency operations

---

## References

- [AKS API Server VNet Integration](https://learn.microsoft.com/azure/aks/api-server-vnet-integration)
- [AKS Private Cluster](https://learn.microsoft.com/azure/aks/private-clusters)
- ALZ Corp repo decision ledger: `.squad/decisions.md` → ADR on private AKS clusters

---

## Changelog

- **2026-06-09**: Initial documentation after discovering node-subnet constraint on `aks-sreagt-store-dmo-swc-001`
