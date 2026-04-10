# ArgoCD Bootstrap for AKS Automatic (ALZ Corp)

This directory contains Kubernetes manifests to bootstrap ArgoCD on an AKS Automatic private cluster deployed with this module.

## Prerequisites

Before applying these manifests:

1. AKS cluster deployed via `terraform apply` with this module
2. `kubectl` access configured: `az aks get-credentials --resource-group <rg> --name <cluster>`
3. ArgoCD container images imported into the private ACR:
   ```bash
   ACR_NAME=$(terraform output -raw acr_login_server | cut -d. -f1)
   az acr import --name $ACR_NAME --source quay.io/argoproj/argocd:v2.13.2
   az acr import --name $ACR_NAME --source ghcr.io/dexidp/dex:v2.41.1
   az acr import --name $ACR_NAME --source redis:7.4-alpine
   ```
4. Entra ID app registration for SSO (see `03-entra-sso.yaml`)
5. TLS certificate in Key Vault for the ArgoCD UI (see `05-ingress.yaml`)

## Apply order

```bash
# 1. Create namespace and network policy
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-network-policy.yaml

# 2. Install ArgoCD (CRDs must exist before ApplicationSet)
curl -sL https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml > argocd-install.yaml

# Patch image references to use private ACR
ACR_SERVER=$(terraform output -raw acr_login_server)
sed -i "s|quay.io/argoproj/argocd|${ACR_SERVER}/argoproj/argocd|g" argocd-install.yaml
sed -i "s|ghcr.io/dexidp/dex|${ACR_SERVER}/dexidp/dex|g" argocd-install.yaml
sed -i "s|redis:7.4-alpine|${ACR_SERVER}/redis:7.4-alpine|g" argocd-install.yaml

kubectl apply -n argocd -f argocd-install.yaml
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=120s

# 3. Populate OIDC client secret (from Key Vault or manually)
kubectl patch secret argocd-secret -n argocd --type merge \
  -p '{"stringData":{"oidc.entra.clientSecret":"<YOUR_OIDC_CLIENT_SECRET>"}}'

# 4. Configure SSO, RBAC, and ingress
kubectl apply -f 03-entra-sso.yaml
kubectl apply -f 04-rbac.yaml
kubectl apply -f 05-ingress.yaml

# 5. Verify SSO works before deploying apps
# Browse to https://<ARGOCD_FQDN> and log in with Entra ID
# Once confirmed, disable admin account:
#   kubectl patch configmap argocd-cm -n argocd --type merge \
#     -p '{"data":{"admin.enabled":"false"}}'

# 6. Deploy the app-of-apps pattern
kubectl apply -f 06-app-of-apps.yaml
```

## File reference

| File | Purpose |
|---|---|
| `01-namespace.yaml` | ArgoCD namespace with Workload Identity labels |
| `02-network-policy.yaml` | CiliumNetworkPolicy for zero-trust namespace isolation |
| `03-entra-sso.yaml` | Entra ID OIDC SSO configuration (argocd-cm patch) |
| `04-rbac.yaml` | ArgoCD RBAC mapped to Entra ID groups (argocd-rbac-cm patch) |
| `05-ingress.yaml` | Application Routing Ingress with internal LB and Key Vault TLS |
| `06-app-of-apps.yaml` | ApplicationSet for multi-environment GitOps pattern |
