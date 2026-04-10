import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

// ALZ Corp policy alignment checks
const ALZ_CHECKS = [
  {
    id: "ALZ-01",
    name: "PaaS public endpoints disabled (Deny-PublicEndpoints compliance)",
    check: (files) => {
      const deps = files["dependencies.tf"] || "";
      const acrDisabled = /publicNetworkAccess.*Disabled/.test(deps);
      const kvDisabled = deps.includes("publicNetworkAccess") && deps.includes('"Disabled"');
      return acrDisabled && kvDisabled;
    },
    severity: "CRITICAL",
    policy: "Deny-PublicEndpoints",
    reference: "https://azure.github.io/Azure-Landing-Zones/policy/",
  },
  {
    id: "ALZ-02",
    name: "Diagnostic settings strategy documented",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("Deploy-Diag-LogsCat") || readme.includes("diagnostic settings");
    },
    severity: "HIGH",
    policy: "Deploy-Diag-LogsCat (DeployIfNotExists)",
    reference: "https://azure.github.io/Azure-Landing-Zones/policy/",
  },
  {
    id: "ALZ-03",
    name: "Tags variable exposed for policy compliance",
    check: (files) => {
      const vars = files["variables.tf"] || "";
      const main = files["main.tf"] || "";
      return vars.includes('"tags"') && main.includes("local.tags");
    },
    severity: "MEDIUM",
    policy: "Require-Tag-* policies",
    reference: "https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies#tags",
  },
  {
    id: "ALZ-04",
    name: "Private cluster option available (Deny-PublicIP compliance)",
    check: (files) => {
      const vars = files["variables.tf"] || "";
      return vars.includes("enable_private_cluster");
    },
    severity: "CRITICAL",
    policy: "Deny-PublicIP",
    reference: "https://learn.microsoft.com/azure/aks/private-clusters",
  },
  {
    id: "ALZ-05",
    name: "Azure RBAC enforced (no local accounts)",
    check: (files) => {
      const main = files["main.tf"] || "";
      return main.includes("disableLocalAccounts") && main.includes("enableAzureRBAC");
    },
    severity: "CRITICAL",
    policy: "AKS Azure RBAC policy",
    reference: "https://learn.microsoft.com/azure/aks/manage-azure-rbac",
  },
  {
    id: "ALZ-06",
    name: "Deployment Safeguards active (Azure Policy integration)",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("Deployment Safeguards") && readme.includes("Azure Policy");
    },
    severity: "HIGH",
    policy: "AKS Deployment Safeguards",
    reference: "https://learn.microsoft.com/azure/aks/deployment-safeguards",
  },
  {
    id: "ALZ-07",
    name: "Hub firewall egress documented (UDR pattern)",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("userDefinedRouting") && readme.includes("hub") && readme.includes("firewall");
    },
    severity: "HIGH",
    policy: "Corp egress pattern",
    reference: "https://learn.microsoft.com/azure/aks/outbound-rules-control-egress",
  },
  {
    id: "ALZ-08",
    name: "Cross-subscription RBAC requirements documented",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("cross-subscription") && readme.includes("RBAC");
    },
    severity: "MEDIUM",
    policy: "Identity and access management",
    reference: "https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/identity-access",
  },
  {
    id: "ALZ-09",
    name: "Private DNS zone pattern documented",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("private.<region>.azmk8s.io") && readme.includes("connectivity subscription");
    },
    severity: "HIGH",
    policy: "DNS zone management",
    reference: "https://learn.microsoft.com/azure/aks/private-clusters",
  },
  {
    id: "ALZ-10",
    name: "Policy conflict documentation present",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("Policy Conflicts") && readme.includes("exemption");
    },
    severity: "HIGH",
    policy: "ALZ policy assignment conflicts",
    reference: "https://learn.microsoft.com/azure/governance/policy/concepts/exemption-structure",
  },
  {
    id: "ALZ-11",
    name: "Subscription vending integration documented",
    check: (files) => {
      const readme = files["README.md"] || "";
      return readme.includes("subscription vending") || readme.includes("AVNM IPAM");
    },
    severity: "MEDIUM",
    policy: "ALZ subscription vending",
    reference: "https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-subscriptions",
  },
];

function runAlzCheck(dir) {
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

  const passed = [];
  const failed = [];

  for (const check of ALZ_CHECKS) {
    if (check.check(files)) {
      passed.push(check);
    } else {
      failed.push(check);
    }
  }

  return { passed, failed };
}

const session = await joinSession({
  tools: [
    {
      name: "alz_alignment_check",
      description:
        "Checks the AKS Automatic module against Azure Landing Zone Corp governance requirements. " +
        "Validates public endpoint denial compliance, diagnostic settings strategy, tag exposure, " +
        "private cluster support, RBAC enforcement, policy conflict documentation, hub firewall " +
        "egress patterns, DNS zone management, and subscription vending integration.",
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
        const { passed, failed } = runAlzCheck(dir);

        const lines = [];
        lines.push("## ALZ Corp Alignment Report\n");
        lines.push(`| Result | Count |\n|---|---|\n| Passed | ${passed.length} |\n| Failed | ${failed.length} |`);

        if (failed.length > 0) {
          lines.push("\n### Non-compliant areas\n");
          for (const f of failed) {
            lines.push(
              `- **[${f.severity}] ${f.id}: ${f.name}**\n  Policy: ${f.policy}\n  [Reference](${f.reference})`
            );
          }
        }

        if (passed.length > 0) {
          lines.push("\n### Compliant areas\n");
          for (const p of passed) {
            lines.push(`- [${p.severity}] ${p.id}: ${p.name} (${p.policy})`);
          }
        }

        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
