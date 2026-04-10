import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

// ---------------------------------------------------------------------------
// ArgoCD on AKS Automatic in ALZ Corp - architecture knowledge base
// ---------------------------------------------------------------------------

const ARGOCD_CHECKS = [
  // -- Networking & connectivity for private clusters --
  {
    id: "GIT-01",
    name: "Private cluster API server access",
    severity: "CRITICAL",
    category: "networking",
    description:
      "ArgoCD application controller must reach the Kubernetes API server. " +
      "In a private AKS Automatic cluster the API server is an internal load " +
      "balancer in the delegated subnet (VNet integration). ArgoCD runs " +
      "in-cluster, so API access works without extra configuration. " +
      "For multi-cluster setups where ArgoCD manages remote private clusters, " +
      "VNet peering or Private Link must be established between the management " +
      "cluster VNet and the target cluster VNet.",
    check: (files) => {
      const main = files["main.tf"] || "";
      return main.includes("apiServerAccessProfile") && main.includes("enableVnetIntegration");
    },
  },
  {
    id: "GIT-02",
    name: "Git repository egress through hub firewall",
    severity: "CRITICAL",
    category: "networking",
    description:
      "When egress_type = userDefinedRouting, all outbound traffic routes through " +
      "the hub Azure Firewall. The firewall must allow HTTPS (443) to the Git " +
      "hosting provider:\n" +
      "  - GitHub.com: github.com, *.github.com, *.githubusercontent.com\n" +
      "  - Azure DevOps: dev.azure.com, *.visualstudio.com, vstsagentpackage.azureedge.net\n" +
      "  - Self-hosted: the FQDN/IP of your Git server\n" +
      "Add these to the hub firewall application rules alongside the AKS " +
      "required FQDNs (AzureKubernetesService FQDN tag).",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("userDefinedRouting") && readme.includes("firewall");
    },
  },
  {
    id: "GIT-03",
    name: "Container image pull through firewall",
    severity: "HIGH",
    category: "networking",
    description:
      "ArgoCD container images (quay.io/argoproj/*) must be pullable. Options:\n" +
      "  1. Import images into the private ACR (recommended for Corp):\n" +
      "     az acr import --name <acr> --source quay.io/argoproj/argocd:v2.x\n" +
      "  2. Allow quay.io and ghcr.io through the hub firewall\n" +
      "Option 1 avoids external registry dependencies at runtime.",
    check: (files) => {
      const deps = files["dependencies.tf"] || "";
      return deps.includes("containerRegistries") || deps.includes("Microsoft.ContainerRegistry");
    },
  },
  {
    id: "GIT-04",
    name: "Helm chart registry access",
    severity: "HIGH",
    category: "networking",
    description:
      "ArgoCD Helm chart is hosted on ghcr.io (GitHub Container Registry). " +
      "For Corp private clusters, either:\n" +
      "  1. Import the Helm chart into ACR as an OCI artifact\n" +
      "  2. Use the ArgoCD Kustomize/YAML manifests directly from Git\n" +
      "  3. Allow ghcr.io through the hub firewall\n" +
      "Recommended: use plain YAML manifests committed to your GitOps repo.",
    check: () => true,
  },
  // -- Identity & RBAC --
  {
    id: "GIT-05",
    name: "ArgoCD RBAC with Azure RBAC integration",
    severity: "CRITICAL",
    category: "identity",
    description:
      "AKS Automatic enforces Azure RBAC for Kubernetes (local accounts disabled). " +
      "ArgoCD must authenticate via Entra ID. Configure:\n" +
      "  1. ArgoCD SSO with Entra ID (OIDC provider in argocd-cm ConfigMap)\n" +
      "  2. Map Entra groups to ArgoCD roles in argocd-rbac-cm\n" +
      "  3. ArgoCD application controller uses in-cluster ServiceAccount\n" +
      "     which maps to Azure RBAC via AKS Azure RBAC bindings\n" +
      "  4. Grant the ArgoCD SA 'Azure Kubernetes Service RBAC Writer' or\n" +
      "     a custom role at the cluster scope",
    check: (files) => {
      const main = files["main.tf"] || "";
      return main.includes("enableAzureRBAC") && main.includes("disableLocalAccounts");
    },
  },
  {
    id: "GIT-06",
    name: "Workload Identity for external secrets",
    severity: "HIGH",
    category: "identity",
    description:
      "ArgoCD may need to pull secrets from Azure Key Vault (TLS certs, Git " +
      "credentials). Use Workload Identity Federation:\n" +
      "  1. Create a Kubernetes ServiceAccount for ArgoCD with the annotation\n" +
      "     azure.workload.identity/client-id: <managed-identity-client-id>\n" +
      "  2. Federate the managed identity with the AKS OIDC issuer\n" +
      "  3. Grant the managed identity Key Vault Secrets User on the vault\n" +
      "This avoids storing any credentials in the cluster.",
    check: (files) => {
      const main = files["main.tf"] || "";
      return main.includes("workloadIdentity") && main.includes("oidcIssuerProfile");
    },
  },
  // -- Architecture patterns --
  {
    id: "GIT-07",
    name: "App-of-apps or ApplicationSet pattern",
    severity: "MEDIUM",
    category: "architecture",
    description:
      "For multi-environment deployments in ALZ Corp, use ArgoCD ApplicationSet:\n" +
      "  - Git generator: one Application per directory in the repo\n" +
      "  - List generator: explicit environment definitions (dev/staging/prod)\n" +
      "  - Matrix generator: combine clusters x environments\n" +
      "ApplicationSet controller runs in the management cluster and creates " +
      "Application CRs automatically. For Corp, prefer the Git generator with " +
      "directory structure: clusters/<env>/apps/<app>/",
    check: () => true,
  },
  {
    id: "GIT-08",
    name: "Namespace isolation with Cilium NetworkPolicy",
    severity: "HIGH",
    category: "security",
    description:
      "AKS Automatic uses Cilium for network policy. ArgoCD should run in a " +
      "dedicated namespace (argocd) with CiliumNetworkPolicy restricting:\n" +
      "  - Ingress: only from the internal LB (Application Routing) for the UI\n" +
      "  - Egress: API server (in-cluster), Git endpoints (via firewall), " +
      "    ACR (private endpoint), Key Vault (private endpoint)\n" +
      "  - Deny all other traffic\n" +
      "This aligns with ALZ Corp zero-trust network segmentation.",
    check: (files) => {
      const main = files["main.tf"] || "";
      return main.includes("networkDataplane") && main.includes("cilium");
    },
  },
  {
    id: "GIT-09",
    name: "ArgoCD UI access via Application Routing internal LB",
    severity: "HIGH",
    category: "ingress",
    description:
      "For Corp, expose the ArgoCD UI through Application Routing (managed NGINX) " +
      "with an internal load balancer. Create an Ingress resource:\n" +
      "  - ingressClassName: webapprouting.kubernetes.azure.com\n" +
      "  - annotation: nginx.ingress.kubernetes.io/backend-protocol: HTTPS\n" +
      "  - TLS cert from Key Vault via annotation:\n" +
      "    kubernetes.azure.com/tls-cert-keyvault-uri: <vault-uri>\n" +
      "  - Host: argocd.<private-dns-zone>\n" +
      "The private DNS zone must resolve from the hub VNet for platform team access.",
    check: (files) => {
      const main = files["main.tf"] || "";
      return main.includes("webAppRouting") || main.includes("ingressProfile");
    },
  },
  {
    id: "GIT-10",
    name: "Disaster recovery and state backup",
    severity: "MEDIUM",
    category: "operations",
    description:
      "ArgoCD is stateless by design (all state is in Git). However:\n" +
      "  - Back up argocd-cm, argocd-rbac-cm, argocd-secret ConfigMaps/Secrets\n" +
      "  - These contain SSO config, RBAC policies, and repository credentials\n" +
      "  - Use Velero or native AKS backup to snapshot the argocd namespace\n" +
      "  - For full DR, the GitOps repo itself IS the recovery source\n" +
      "  - Document the bootstrap procedure: install ArgoCD, apply app-of-apps",
    check: () => true,
  },
  // -- Private cluster specific --
  {
    id: "GIT-11",
    name: "Webhook delivery for private clusters",
    severity: "MEDIUM",
    category: "networking",
    description:
      "GitHub/Azure DevOps webhooks cannot reach a private cluster directly. Options:\n" +
      "  1. Polling: set ArgoCD repo refresh interval (default 3 min, configurable)\n" +
      "  2. Azure Event Grid + Service Bus: webhook to Event Grid, ArgoCD polls SB\n" +
      "  3. Self-hosted runner in the VNet that triggers argocd app sync\n" +
      "For Corp, polling (option 1) is simplest and sufficient for most workloads. " +
      "Reduce the interval to 30s for near-real-time sync if needed.",
    check: (files) => {
      const vars = files["variables.tf"] || "";
      return vars.includes("enable_private_cluster");
    },
  },
  {
    id: "GIT-12",
    name: "Git credential management",
    severity: "HIGH",
    category: "security",
    description:
      "For private Git repositories, ArgoCD needs credentials. In ALZ Corp:\n" +
      "  1. Store Git SSH keys or PATs in Azure Key Vault\n" +
      "  2. Use Workload Identity + External Secrets Operator to sync to K8s Secrets\n" +
      "  3. Reference in ArgoCD repository configuration\n" +
      "  4. Alternatively, use Azure DevOps with Managed Identity (if supported)\n" +
      "Never store Git credentials as plain Kubernetes Secrets without encryption.",
    check: (files) => {
      const deps = files["dependencies.tf"] || "";
      return deps.includes("Microsoft.KeyVault");
    },
  },
];

function runGitOpsReview(dir) {
  const fileNames = [
    "main.tf", "variables.tf", "locals.tf", "network.tf",
    "dependencies.tf", "outputs.tf", "README.md",
  ];
  const files = {};
  for (const name of fileNames) {
    try {
      files[name] = readFileSync(join(dir, name), "utf-8");
    } catch {
      files[name] = null;
    }
  }

  const results = { networking: [], identity: [], architecture: [], security: [], ingress: [], operations: [] };

  for (const check of ARGOCD_CHECKS) {
    const passed = check.check(files);
    const entry = { ...check, passed };
    if (results[check.category]) {
      results[check.category].push(entry);
    }
  }

  return results;
}

const session = await joinSession({
  tools: [
    {
      name: "gitops_review",
      description:
        "Reviews the AKS Automatic module for ArgoCD GitOps readiness in an ALZ Corp " +
        "private cluster setting. Checks networking (firewall egress, API access, " +
        "webhook delivery), identity (Azure RBAC, Workload Identity, SSO), architecture " +
        "(ApplicationSet patterns, namespace isolation), ingress (Application Routing " +
        "internal LB for ArgoCD UI), security (Cilium NetworkPolicy, credential " +
        "management), and operations (DR, backup). Each check includes implementation " +
        "guidance specific to private clusters behind a hub firewall.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Path to the module directory. Defaults to cwd.",
          },
        },
      },
      handler: async (args) => {
        const dir = args.path || process.cwd();
        const results = runGitOpsReview(dir);

        const lines = [];
        lines.push("## GitOps (ArgoCD) Readiness Review - ALZ Corp Private Cluster\n");

        let totalPassed = 0;
        let totalFailed = 0;

        for (const checks of Object.values(results)) {
          for (const c of checks) {
            if (c.passed) totalPassed++;
            else totalFailed++;
          }
        }

        lines.push(`| Result | Count |\n|---|---|\n| Ready | ${totalPassed} |\n| Needs attention | ${totalFailed} |\n`);

        const categoryLabels = {
          networking: "Networking & Connectivity",
          identity: "Identity & RBAC",
          architecture: "Architecture Patterns",
          security: "Security",
          ingress: "Ingress",
          operations: "Operations",
        };

        for (const [cat, label] of Object.entries(categoryLabels)) {
          const checks = results[cat];
          if (!checks || checks.length === 0) continue;

          lines.push(`### ${label}\n`);

          for (const c of checks) {
            const icon = c.passed ? "Ready" : "ACTION NEEDED";
            lines.push(`**[${c.severity}] ${c.id}: ${c.name}** - ${icon}\n`);
            lines.push(c.description);
            lines.push("");
          }
        }

        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
