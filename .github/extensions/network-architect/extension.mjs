import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// Network architecture checks for AKS Automatic in ALZ Corp
const NETWORK_CHECKS = [
  {
    id: "NET-01",
    name: "API server subnet has delegation",
    check: (files) =>
      files["network.tf"]?.includes("Microsoft.ContainerService/managedClusters") ?? false,
    severity: "CRITICAL",
    reference: "https://learn.microsoft.com/azure/aks/api-server-vnet-integration",
  },
  {
    id: "NET-02",
    name: "API server subnet has no route table",
    check: (files) => {
      const net = files["network.tf"] || "";
      const apiSubnet = net.match(/resource\s+"azapi_resource"\s+"apiserver_subnet"[\s\S]*?^}/m);
      return apiSubnet ? !apiSubnet[0].includes("routeTable") : true;
    },
    severity: "CRITICAL",
    reference: "https://learn.microsoft.com/azure/aks/api-server-vnet-integration#limitations",
  },
  {
    id: "NET-03",
    name: "UDR route table has default route to firewall",
    check: (files) =>
      files["network.tf"]?.includes("0.0.0.0/0") &&
      files["network.tf"]?.includes("VirtualAppliance"),
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/aks/outbound-rules-control-egress",
  },
  {
    id: "NET-04",
    name: "Node subnet has NSG association",
    check: (files) =>
      files["network.tf"]?.includes("networkSecurityGroup"),
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/aks/concepts-network#network-security-groups",
  },
  {
    id: "NET-05",
    name: "Pod CIDR uses overlay (non-routable)",
    check: (files) => {
      const vars = files["variables.tf"] || "";
      return vars.includes("10.244.0.0/16") || vars.includes("pod_cidr");
    },
    severity: "MEDIUM",
    reference: "https://learn.microsoft.com/azure/aks/azure-cni-overlay",
  },
  {
    id: "NET-06",
    name: "CNI Overlay + Cilium configured",
    check: (files) =>
      files["main.tf"]?.includes('"overlay"') && files["main.tf"]?.includes('"cilium"'),
    severity: "CRITICAL",
    reference: "https://learn.microsoft.com/azure/aks/azure-cni-powered-by-cilium",
  },
  {
    id: "NET-07",
    name: "Private endpoints for PaaS services",
    check: (files) =>
      files["dependencies.tf"]?.includes("privateEndpoints") ||
      files["dependencies.tf"]?.includes("privateLinkServiceConnections"),
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/private-link/private-endpoint-overview",
  },
  {
    id: "NET-08",
    name: "Private DNS zone groups for PE DNS registration",
    check: (files) =>
      files["dependencies.tf"]?.includes("privateDnsZoneGroups"),
    severity: "HIGH",
    reference: "https://learn.microsoft.com/azure/private-link/private-endpoint-dns",
  },
  {
    id: "NET-09",
    name: "VNet integration for API server",
    check: (files) =>
      files["main.tf"]?.includes("enableVnetIntegration") &&
      files["main.tf"]?.includes("true"),
    severity: "CRITICAL",
    reference: "https://learn.microsoft.com/azure/aks/api-server-vnet-integration",
  },
  {
    id: "NET-10",
    name: "External subnet IDs validated (all-or-none)",
    check: (files) =>
      files["main.tf"]?.includes("external_node_subnet_id") &&
      files["main.tf"]?.includes("external_apiserver_subnet_id") &&
      files["main.tf"]?.includes("must both be set or both be null"),
    severity: "HIGH",
    reference: "N/A (Terraform guardrail)",
  },
  {
    id: "NET-11",
    name: "HTTP proxy support available",
    check: (files) =>
      files["main.tf"]?.includes("httpProxyConfig") &&
      files["variables.tf"]?.includes("http_proxy_config"),
    severity: "MEDIUM",
    reference: "https://learn.microsoft.com/azure/aks/http-proxy",
  },
  {
    id: "NET-12",
    name: "CIDR variables have format validation",
    check: (files) => {
      const vars = files["variables.tf"] || "";
      return vars.includes("cidrhost") && vars.includes("pod_cidr");
    },
    severity: "MEDIUM",
    reference: "N/A (Terraform guardrail)",
  },
];

function runNetworkReview(dir) {
  const fileNames = [
    "main.tf", "variables.tf", "locals.tf", "network.tf",
    "dependencies.tf", "outputs.tf",
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

  for (const check of NETWORK_CHECKS) {
    if (check.check(files)) {
      passed.push(check);
    } else {
      failed.push(check);
    }
  }

  // CIDR analysis from variables.tf
  const cidrInfo = [];
  const vars = files["variables.tf"] || "";
  const cidrVars = [
    { name: "vnet_address_space", pattern: /default\s*=\s*"([^"]+)"/ },
    { name: "node_subnet_address_prefix", pattern: /default\s*=\s*"([^"]+)"/ },
    { name: "apiserver_subnet_address_prefix", pattern: /default\s*=\s*"([^"]+)"/ },
    { name: "pe_subnet_address_prefix", pattern: /default\s*=\s*"([^"]+)"/ },
    { name: "pod_cidr", pattern: /default\s*=\s*"([^"]+)"/ },
    { name: "service_cidr", pattern: /default\s*=\s*"([^"]+)"/ },
  ];

  for (const cv of cidrVars) {
    const varBlock = vars.split(`variable "${cv.name}"`)[1]?.split("variable ")[0] || "";
    const match = varBlock.match(cv.pattern);
    if (match) {
      cidrInfo.push({ name: cv.name, value: match[1] });
    }
  }

  return { passed, failed, cidrInfo };
}

const session = await joinSession({
  tools: [
    {
      name: "network_review",
      description:
        "Reviews the AKS Automatic module network architecture against ALZ Corp best practices. " +
        "Checks subnet delegation, NSG associations, UDR configuration, CNI Overlay + Cilium, " +
        "private endpoints, DNS zone groups, VNet integration, CIDR validation, and HTTP proxy support. " +
        "Also extracts default CIDR allocations for review.",
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
        const { passed, failed, cidrInfo } = runNetworkReview(dir);

        const lines = [];
        lines.push("## Network Architecture Review\n");
        lines.push(`| Result | Count |\n|---|---|\n| Passed | ${passed.length} |\n| Failed | ${failed.length} |`);

        if (failed.length > 0) {
          lines.push("\n### Failed checks\n");
          for (const f of failed) {
            lines.push(`- **[${f.severity}] ${f.id}: ${f.name}**\n  [Reference](${f.reference})`);
          }
        }

        if (passed.length > 0) {
          lines.push("\n### Passed checks\n");
          for (const p of passed) {
            lines.push(`- [${p.severity}] ${p.id}: ${p.name}`);
          }
        }

        if (cidrInfo.length > 0) {
          lines.push("\n### Default CIDR allocations\n");
          lines.push("| Variable | Default CIDR |\n|---|---|");
          for (const c of cidrInfo) {
            lines.push(`| \`${c.name}\` | \`${c.value}\` |`);
          }
          lines.push(
            "\nVerify these do not overlap with hub VNet, other spokes, or on-premises address space."
          );
        }

        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
