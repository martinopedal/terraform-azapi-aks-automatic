# AGC Client Traffic Not Forwarded - two issues, live-validated 2026-06-14

> **RESOLUTION (2026-06-14, live-validated). Two SEPARATE issues - do not conflate them.**
>
> **(1) Unsupported install model - FIXED.** The ALB Controller was self-installed via Helm on an
> AKS Automatic cluster, which requires the managed Gateway API + ALB Controller add-on. Corrected:
> the managed add-on is now enabled (`az aks update --enable-gateway-api
> --enable-application-load-balancer`; the managed controller runs in `kube-system`, GatewayClass
> `azure-alb-external` is Valid, the HTTPRoute resolves to the backend on the Service port - note
> the backend ref must use the Service port 80, not the targetPort 8080).
>
> **(2) Client traffic not forwarded - NOT caused by (1), and it PERSISTS under the managed add-on.**
> Live-validated: with the managed controller correctly programmed (backend attached,
> `Programmed=True`, health probes 200), a clean public internet client (a throwaway ACI with no
> corporate filter and no force-tunnel) STILL gets no response (HTTP 000 / empty reply) from the AGC
> frontend. So it is neither the install model nor a test-client artifact.
>
> **Root cause of (2):** AGC has a **public frontend only** - there is no private/internal frontend
> yet (Microsoft Learn "components"; Azure/AKS#5739 - private frontend is on the roadmap, not GA).
> This cluster sits in a **private-by-default, force-tunneled ALZ that intentionally blocks public
> ingress** (the same reason the public LoadBalancer path is blocked here - see the runbook). AGC's
> public frontend hits that wall, so no client can reach the backend through it.
>
> **Conclusion:** AGC cannot provide working ingress in THIS private-by-default ALZ today, because
> its only frontend option is public and the ALZ blocks public ingress. The internal NGINX
> LoadBalancer (in-VNet, 10.16.0.199) remains the architecturally-correct ingress for this posture.
> "Replace nginx with AGC" becomes possible when AGC private/internal frontend reaches GA, or if
> public ingress is deliberately opened in the ALZ (which violates the private-by-default design).
> This is a frontend-type limitation intersecting the ALZ posture, not an AGC data-plane bug to
> escalate as a P2.

---

# Original investigation (2026-06-10) - Microsoft Support Report (superseded)

**Date**: 2026-06-10  
**Severity**: P2  
**Reporter**: Martin Opedal (@martinopedal), Azure Specialist Team  
**Cluster**: aks-sreagt-store-dmo-swc-001  
**Resource Group**: rg-sreagt-dmo-swc-001  
**Subscription**: 147f910d-d9c8-40ca-8455-2ea5219765e5 (ME-MngEnvMCAP464621-martinopedal-9)  
**Location**: swedencentral

---

## Summary

Application Gateway for Containers (AGC) in BYO mode with Gateway API v1 on AKS Automatic (Azure CNI Overlay) accepts TCP connections from internet clients but does not forward HTTP requests to healthy backends. Client requests never reach the backend pods despite Gateway/HTTPRoute status showing Programmed=True and AGC health probes successfully reaching the backends.

---

## Environment

### Cluster Configuration
- **Name**: aks-sreagt-store-dmo-swc-001
- **Type**: AKS Automatic
- **Kubernetes Version**: v1.34.8
- **Network Plugin**: Azure CNI Overlay
- **Pod CIDR**: 10.244.0.0/16
- **Service CIDR**: 10.245.0.0/16
- **Outbound Type**: userDefinedRouting (force-tunnel to hub firewall 10.0.0.4)
- **API Server**: Private (VNet Integration, reachable only from snet-aks-nodes 10.16.0.192/26)

### AGC Configuration
- **Name**: tc-sreagt-store-dmo-swc-001
- **Resource Group**: rg-sreagt-dmo-swc-001
- **Mode**: BYO (alb-id annotation on Gateway, not AGIC mode)
- **Subnet**: snet-agc (10.16.1.0/24), delegated to Microsoft.ServiceNetworking/trafficControllers
- **Association**: asso-snet-agc -> snet-agc (provisioningState: Succeeded)
- **Frontends**:
  - **BYO Frontend**: fe-public-001 (cyerdrc8htb8gdha.fz05.alb.azure.com / 20.6.16.125)
  - **Auto-created Frontend**: fe-a58bd144 (f4chb6c9czfgf0fe.fz16.alb.azure.com / 20.6.17.227)

### ALB Controller
- **Version**: 1.10.28
- **Namespace**: azure-alb-system
- **Identity**: uami-alb-sreagt-dmo (principalId: 9baec489-c99d-4320-866e-3b7eaea1055f)
- **RBAC Roles**:
  - AppGw for Containers Configuration Manager (on AGC tc-sreagt-store-dmo-swc-001)
  - Network Contributor (on snet-agc 10.16.1.0/24)
- **Federated Credential**: OIDC workload identity for azure-alb-system/alb-controller-sa

### Gateway API Resources
- **Gateway**: store-app-gateway (ns: store-app)
  - gatewayClassName: azure-alb-external
  - alb-id annotation: /subscriptions/.../tc-sreagt-store-dmo-swc-001
  - Listener: http (protocol: HTTP, port: 80)
  - Status: Accepted=True, Programmed=True, attachedRoutes=1
- **HTTPRoute**: store-app-route (ns: store-app)
  - parentRefs: store-app-gateway
  - backendRefs: store-app Service port 8080
  - Status: Accepted=True, ResolvedRefs=True, Programmed=True
  - Message: "Application Gateway for Containers resource has been successfully updated."

---

## Symptom

From an internet client (Windows 11, curl 8.18.0):

```
$ curl http://cyerdrc8htb8gdha.fz05.alb.azure.com -v
* Trying 20.6.16.125:80...
* Connected to cyerdrc8htb8gdha.fz05.alb.azure.com (20.6.16.125) port 80
> GET / HTTP/1.1
> Host: cyerdrc8htb8gdha.fz05.alb.azure.com
> User-Agent: curl/8.18.0
> Accept: */*
> 
* Request completely sent off
< (5 seconds timeout)
* Empty reply from server
* Closing connection 0
curl: (52) Empty reply from server
```

- **TCP connection succeeds** (client establishes connection to frontend IP)
- **Request is sent** (curl reports "Request completely sent off")
- **No HTTP response** (curl exit code 52, "Empty reply from server")
- **Client request NEVER reaches the backend pod** (pod access logs show ONLY AGC health probes from 10.16.1.4/.5, never the client request)

**Both frontends exhibit identical behavior**:
- BYO frontend fe-public-001 (cyerdrc8htb8gdha.fz05): Empty reply
- Auto-created frontend fe-a58bd144 (f4chb6c9czfgf0fe.fz16): Empty reply

---

## What Works

### 1. AGC Health Probes Reach Backend and Get HTTP 200

AGC health probe requests from snet-agc proxy IPs (10.16.1.4 / 10.16.1.5) successfully reach the backend pod on port 8080 and receive HTTP 200 responses:

```
$ kubectl logs -n store-app store-app-... --tail=50 | grep "10.16.1"
10.16.1.4 - - [10/Jun/2026:06:15:33 +0000] "GET / HTTP/1.1" 200 615 "-" "Microsoft-Azure-Application-LB/AGC" 79 0.001 200
10.16.1.5 - - [10/Jun/2026:06:15:35 +0000] "GET / HTTP/1.1" 200 615 "-" "Microsoft-Azure-Application-LB/AGC" 79 0.000 200
```

AGC backend health status: **Healthy**.

### 2. Direct Backend Access Works

From a VM on the same VNet (snet-aks-nodes):

```
$ curl http://10.16.0.198:8080/
HTTP/1.1 200 OK
Server: nginx/1.27.5
<!DOCTYPE html><html><head><title>Welcome to nginx!</title>...
```

Backend is reachable and functional.

### 3. Gateway/HTTPRoute Status Shows Success

```
$ kubectl get gateway -n store-app store-app-gateway -o yaml
status:
  conditions:
  - type: Accepted
    status: "True"
    reason: Accepted
  - type: Programmed
    status: "True"
    reason: Programmed
    message: "Application Gateway for Containers resource has been successfully updated."
  listeners:
  - name: http
    attachedRoutes: 1
    conditions:
    - type: Accepted
      status: "True"
    - type: Programmed
      status: "True"

$ kubectl get httproute -n store-app store-app-route -o yaml
status:
  parents:
  - conditions:
    - type: Accepted
      status: "True"
    - type: ResolvedRefs
      status: "True"
    - type: Programmed
      status: "True"
      message: "Application Gateway for Containers resource has been successfully updated."
```

No errors, no warnings, no Kubernetes events indicating problems.

### 4. ALB Controller Has Correct Identity and RBAC

```
$ kubectl get pod -n azure-alb-system alb-controller-...  -o yaml | grep serviceAccountName
serviceAccountName: alb-controller-sa

$ az role assignment list --assignee 9baec489-c99d-4320-866e-3b7eaea1055f --query "[].{Role:roleDefinitionName,Scope:scope}" -o table
Role                                           Scope
---------------------------------------------  ---------------------------------------------------
AppGw for Containers Configuration Manager     /subscriptions/.../tc-sreagt-store-dmo-swc-001
Network Contributor                            /subscriptions/.../snet-agc
```

Controller logs show no errors related to configuration or backend discovery.

### 5. NSG and AVNM Rules Allow All Relevant Traffic

**NSG Rules** (nsg-sre-agent-dnb-prod on snet-agc):
- AllowInternetToAgc (prio 300): Inbound TCP 80,443 from Internet -> 10.16.1.0/24
- AllowLbToAgc (prio 310): Inbound * from AzureLoadBalancer -> 10.16.1.0/24
- AllowAgcToBackends (prio 320): Inbound * from 10.16.1.0/24 -> *
- AllowVnetInbound (prio 250): Inbound * from VirtualNetwork -> VirtualNetwork
- AllowAgcOutToPods (prio 330): Outbound from 10.16.1.0/24 -> 10.244.0.0/16

**AVNM Rules** (sac-baseline / rc-deny-baseline-demos, committed 2026-06-10):
- allow-intra-virtual-network (1050, Inbound): VirtualNetwork -> VirtualNetwork
- allow-azure-load-balancer-inbound (1060, Inbound): AzureLoadBalancer -> VirtualNetwork
- allow-agc-dataplane-egress (1080, Outbound): 10.16.1.0/24 -> Internet

Health probes pass with these rules, confirming network connectivity.

---

## Five Backend Configurations Tested (ALL Failed)

To rule out backend reachability issues, five different backend configurations were tested. **All returned "Empty reply" identically**:

| Config | Backend Type | Endpoint IPs | Controller Status | Result |
|--------|--------------|--------------|-------------------|--------|
| 1 | ClusterIP Service | Overlay pod IPs (10.244.0.53, 10.244.0.96) | Programmed=True | Empty reply |
| 2 | LoadBalancer Service (internal) | Internal LB IP (10.16.0.198) | Programmed=True | Empty reply |
| 3 | ExternalName Service | nip.io FQDN (10-16-0-198.nip.io) | Programmed=True | Empty reply |
| 4 | Headless Service + manual Endpoint | LB IP (10.16.0.198) | Error: "no Pods found" | Empty reply |
| 5 | **hostNetwork pods + ClusterIP** | **Node IPs (10.16.0.196, 10.16.0.198)** | Programmed=True | **Empty reply** |

**Configuration #5 is critical**: 
- Pods run with `hostNetwork: true`, placing them on node IPs (10.16.0.x snet-aks-nodes)
- Node IPs are **VNET-routable** (not overlay pod IPs)
- This configuration **bypasses Azure CNI Overlay entirely**
- ALB controller discovers pods correctly (no errors)
- Service endpoints resolve to node IPs: `10.16.0.196:8080, 10.16.0.200:8080`
- Direct backend access from VNet returns HTTP 200: `curl http://10.16.0.196:8080/ -> 200 OK`
- Gateway/HTTPRoute status: Programmed=True
- **AGC still returns "Empty reply"**

This proves the issue is **not specific to Azure CNI Overlay pod IPs**. AGC data-plane fails to forward client HTTP traffic regardless of backend IP reachability.

---

## Evidence Summary

1. **Frontend accepts TCP connection**: Client establishes connection to AGC frontend IPs (20.6.16.125, 20.6.17.227)
2. **Client sends HTTP request**: curl reports "Request completely sent off"
3. **No HTTP response**: curl receives no data, exits with code 52 "Empty reply from server"
4. **Request never reaches backend**: Pod access logs show ONLY health probes from AGC (10.16.1.4/.5), never the client request
5. **Health probes work**: AGC health probes reach pod:8080 and get HTTP 200
6. **Direct backend access works**: VM on same VNet curls backend successfully (HTTP 200)
7. **Controller claims success**: Gateway/HTTPRoute status Programmed=True, "successfully updated"
8. **Network rules allow traffic**: NSG and AVNM rules open, health probes pass
9. **Five backend configs tested**: ClusterIP (overlay), LoadBalancer, ExternalName, Headless, hostNetwork (node IPs) - all fail identically
10. **Both frontends fail**: BYO frontend and auto-created frontend exhibit identical symptom

---

## Conclusion

AGC data-plane is **not forwarding client HTTP traffic to backends**, despite:
- Backends being healthy and VNET-reachable (health probes work, direct access works)
- Gateway/HTTPRoute showing Programmed=True (controller says config is applied)
- NSG/AVNM rules allowing all required traffic
- Backend endpoints being **VNET-routable node IPs (10.16.0.x)**, NOT overlay pod IPs
- Five different backend configurations tested, all failed identically
- Both frontends (BYO and auto-created) failing identically

This is a **fundamental AGC data-plane forwarding defect**, likely specific to:
- BYO mode (alb-id annotation, not AGIC mode)
- Gateway API v1 (networking.k8s.io/v1)
- AKS Automatic cluster
- ALB controller version 1.10.28

**UPDATE (2026-06-14): the above conclusion is WRONG. See the RESOLUTION at the top of this file.**
This is not a product defect. The asymmetry (AGC health probes reach the backend and get 200, but
client requests are never forwarded) is explained by the **unsupported install model**: a
self-installed Helm ALB Controller on AKS Automatic. AKS Automatic requires the managed Gateway API
+ ALB Controller add-on. The control plane reconciled (`Programmed=True`) but the managed data-plane
integration was absent. The five-backend matrix failing identically is consistent with this: the
backend type is irrelevant when the controller install model is unsupported. Fix: enable the
managed add-on (`az aks update --enable-gateway-api --enable-application-load-balancer`).

---

## Questions for Azure Support / Product Team

1. **Why does the AGC data-plane accept the client TCP connection but never forward the HTTP request to a healthy backend?**
2. **What configuration, permission, or product limitation in BYO mode + Gateway API v1 + AKS Automatic + ALB controller 1.10.28 causes this behavior?**
3. **Is this a known issue? Are there any workarounds or hotfixes available?**
4. **Does AGIC mode (not BYO) work correctly in this environment?**
5. **Does Azure CNI VNET mode (not Overlay) work with BYO AGC?**
6. **Can AGC diagnostic logs be enabled to see what the data-plane is doing when it receives client requests?**

---

## Reproduction Steps

1. **Provision AKS Automatic cluster** with Azure CNI Overlay, private API server, userDefinedRouting outbound.
2. **Deploy AGC** (tc-*) with public frontend, associate with snet-agc (10.16.1.0/24).
3. **Deploy ALB controller** v1.10.28 with workload identity and correct RBAC roles.
4. **Create Gateway** (gatewayClassName: azure-alb-external, alb-id annotation).
5. **Create HTTPRoute** pointing to a backend Service (ClusterIP, port 8080).
6. **Deploy backend pods** (nginx-unprivileged:1.22, port 8080, runAsUser 101).
7. **Open NSG and AVNM rules** for Internet -> snet-agc 80/443, AGC -> backends, egress to Internet.
8. **Wait for Gateway/HTTPRoute Programmed=True** (controller reconciles successfully).
9. **Verify health probes reach backend** (pod logs show AGC proxy IPs 10.16.1.4/.5 getting HTTP 200).
10. **Test from internet**: `curl http://<frontend-fqdn>/` -> **Empty reply from server** (exit 52).
11. **Check pod logs**: No client request appears, only health probes.

---

## Workaround

**NGINX Ingress** (manual deployment or AKS app-routing) works correctly on the same cluster with an internal Azure LoadBalancer. See runbook `docs/runbooks/store-app-ingress.md` for details.

---

## Related Resources

- **AGC Resource ID**: `/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-sreagt-dmo-swc-001/providers/Microsoft.ServiceNetworking/trafficControllers/tc-sreagt-store-dmo-swc-001`
- **Cluster Resource ID**: `/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-sreagt-dmo-swc-001/providers/Microsoft.ContainerService/managedClusters/aks-sreagt-store-dmo-swc-001`
- **ALB Controller Identity**: `/subscriptions/147f910d-d9c8-40ca-8455-2ea5219765e5/resourceGroups/rg-sreagt-dmo-swc-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/uami-alb-sreagt-dmo`
- **GitHub Issues**: https://github.com/Azure/application-gateway-kubernetes-ingress/issues

---

## Contact

Martin Opedal  
martin.opedal@microsoft.com  
Azure Specialist Team
