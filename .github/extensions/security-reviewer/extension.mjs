import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

// Azure Security Benchmark and CIS checks relevant to AKS Automatic + supporting services
const SECURITY_CHECKS = [
  {
    id: "SEC-01",
    name: "Key Vault purge protection",
    check: (content) => content.includes("enablePurgeProtection"),
    file: "dependencies.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/key-vault/general/soft-delete-overview#purge-protection",
  },
  {
    id: "SEC-02",
    name: "Key Vault soft delete enabled",
    check: (content) => content.includes("enableSoftDelete"),
    file: "dependencies.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/key-vault/general/soft-delete-overview",
  },
  {
    id: "SEC-03",
    name: "Key Vault public access disabled",
    check: (content) => content.includes('"Disabled"') && content.includes("publicNetworkAccess"),
    file: "dependencies.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/key-vault/general/network-security",
  },
  {
    id: "SEC-04",
    name: "Key Vault RBAC authorization enabled",
    check: (content) => content.includes("enableRbacAuthorization"),
    file: "dependencies.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/key-vault/general/rbac-guide",
  },
  {
    id: "SEC-05",
    name: "ACR admin user disabled",
    check: (content) => content.includes("adminUserEnabled") && content.includes("false"),
    file: "dependencies.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/container-registry/container-registry-authentication",
  },
  {
    id: "SEC-06",
    name: "ACR public access disabled",
    check: (content) => /publicNetworkAccess.*Disabled/.test(content),
    file: "dependencies.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/container-registry/container-registry-access-selected-networks",
  },
  {
    id: "SEC-07",
    name: "AKS local accounts disabled",
    check: (content) => content.includes("disableLocalAccounts") && content.includes("true"),
    file: "main.tf",
    severity: "CRITICAL",
    reference: "https://learn.microsoft.com/azure/aks/manage-local-accounts-managed-azure-ad",
  },
  {
    id: "SEC-08",
    name: "AKS Azure RBAC enabled",
    check: (content) => content.includes("enableAzureRBAC") && content.includes("true"),
    file: "main.tf",
    severity: "CRITICAL",
    reference: "https://learn.microsoft.com/azure/aks/manage-azure-rbac",
  },
  {
    id: "SEC-09",
    name: "AKS Workload Identity enabled",
    check: (content) => /workloadIdentity[\s\S]*?enabled[\s\S]*?true/.test(content),
    file: "main.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/aks/workload-identity-overview",
  },
  {
    id: "SEC-10",
    name: "AKS Image Cleaner enabled",
    check: (content) => /imageCleaner[\s\S]*?enabled[\s\S]*?true/.test(content),
    file: "main.tf",
    severity: "MEDIUM",
    reference: "https://learn.microsoft.com/azure/aks/image-cleaner",
  },
  {
    id: "SEC-11",
    name: "AKS node resource group locked (ReadOnly)",
    check: (content) => content.includes("ReadOnly") && content.includes("restrictionLevel"),
    file: "main.tf",
    severity: "MEDIUM",
    reference: "https://learn.microsoft.com/azure/aks/cluster-configuration#node-resource-group-lockdown",
  },
  {
    id: "SEC-12",
    name: "Lifecycle prevent_destroy on AKS cluster",
    check: (content) => content.includes("prevent_destroy"),
    file: "main.tf",
    severity: "HIGH",
    reference: "https://developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#prevent_destroy",
  },
  {
    id: "SEC-13",
    name: "Private cluster enabled (Corp default)",
    check: (content) => content.includes("enablePrivateCluster"),
    file: "main.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/aks/private-clusters",
  },
  {
    id: "SEC-14",
    name: "RBAC role assignments use correct identity principals",
    check: (content) =>
      content.includes("kubeletidentity") && content.includes("webAppRouting.identity"),
    file: "dependencies.tf",
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/aks/use-managed-identity",
  },
  {
    id: "SEC-15",
    name: "ACR zone redundancy enabled",
    check: (content) => content.includes("zoneRedundancy"),
    file: "dependencies.tf",
    severity: "MEDIUM",
    reference: "https://learn.microsoft.com/azure/container-registry/zone-redundancy",
  },
];

function runSecurityScan(dir) {
  const results = { passed: [], failed: [] };

  for (const check of SECURITY_CHECKS) {
    const filePath = join(dir, check.file);
    let content;
    try {
      content = readFileSync(filePath, "utf-8");
    } catch {
      results.failed.push({ ...check, reason: `Could not read ${check.file}` });
      continue;
    }

    if (check.check(content)) {
      results.passed.push(check);
    } else {
      results.failed.push({ ...check, reason: "Check not satisfied" });
    }
  }

  return results;
}

const session = await joinSession({
  tools: [
    {
      name: "security_scan",
      description:
        "Scans the AKS Automatic module against Azure Security Benchmark and CIS controls. " +
        "Checks Key Vault hardening, ACR security, AKS RBAC/identity, private cluster, " +
        "lifecycle protection, and RBAC role assignment correctness. Each check includes " +
        "a Microsoft Learn reference link.",
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
        const { passed, failed } = runSecurityScan(dir);

        const lines = [];
        lines.push(`## Security Scan Results\n`);
        lines.push(`| Result | Count |\n|---|---|\n| Passed | ${passed.length} |\n| Failed | ${failed.length} |`);

        if (failed.length > 0) {
          lines.push(`\n### Failed checks\n`);
          for (const f of failed) {
            lines.push(`- **[${f.severity}] ${f.id}: ${f.name}** - ${f.reason}\n  [Reference](${f.reference})`);
          }
        }

        if (passed.length > 0) {
          lines.push(`\n### Passed checks\n`);
          for (const p of passed) {
            lines.push(`- [${p.severity}] ${p.id}: ${p.name}`);
          }
        }

        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
