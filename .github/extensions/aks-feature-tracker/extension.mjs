import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// AKS Automatic ARM properties that could be exposed as module variables.
// Each entry has the ARM path, a description, the Learn link, GA status, and regional availability.
const AKS_FEATURES = [
  {
    name: "Defender for Containers",
    armPath: "securityProfile.defender",
    learnUrl: "https://learn.microsoft.com/azure/defender-for-cloud/defender-for-containers-introduction",
    variableName: "enable_defender",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Azure Key Vault KMS",
    armPath: "securityProfile.azureKeyVaultKms",
    learnUrl: "https://learn.microsoft.com/azure/aks/use-kms-etcd-encryption",
    variableName: null,
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Custom CA Trust Certificates",
    armPath: "securityProfile.customCATrustCertificates",
    learnUrl: "https://learn.microsoft.com/azure/aks/custom-certificate-authority",
    variableName: null,
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Advanced Container Networking Services (ACNS)",
    armPath: "networkProfile.advancedNetworking",
    learnUrl: "https://learn.microsoft.com/azure/aks/advanced-container-networking-services-overview",
    variableName: null,
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Cost Analysis",
    armPath: "metricsProfile.costAnalysis",
    learnUrl: "https://learn.microsoft.com/azure/aks/cost-analysis",
    variableName: "enable_cost_analysis",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Maintenance Configurations",
    armPath: "maintenanceConfigurations (child resource)",
    learnUrl: "https://learn.microsoft.com/azure/aks/planned-maintenance",
    variableName: null,
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "HTTP Proxy",
    armPath: "httpProxyConfig",
    learnUrl: "https://learn.microsoft.com/azure/aks/http-proxy",
    variableName: "http_proxy_config",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Managed Prometheus",
    armPath: "azureMonitorProfile.metrics",
    learnUrl: "https://learn.microsoft.com/azure/azure-monitor/essentials/prometheus-metrics-overview",
    variableName: "enable_prometheus",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Container Insights (OMS Agent)",
    armPath: "addonProfiles.omsAgent",
    learnUrl: "https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-overview",
    variableName: null,
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Workload Identity",
    armPath: "securityProfile.workloadIdentity",
    learnUrl: "https://learn.microsoft.com/azure/aks/workload-identity-overview",
    variableName: null,
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Image Cleaner",
    armPath: "securityProfile.imageCleaner",
    learnUrl: "https://learn.microsoft.com/azure/aks/image-cleaner",
    variableName: "image_cleaner_interval_hours",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Istio Service Mesh",
    armPath: "serviceMeshProfile",
    learnUrl: "https://learn.microsoft.com/azure/aks/istio-about",
    variableName: "enable_service_mesh",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Application Gateway for Containers",
    armPath: "N/A (separate resource + AKS add-on)",
    learnUrl: "https://learn.microsoft.com/azure/application-gateway/for-containers/overview",
    variableName: null,
    ga: true,
    norwayEast: true,
    swedenCentral: false,
    note: "AGC add-on not yet supported on AKS Automatic clusters",
  },
  {
    name: "Node OS Auto-Upgrade",
    armPath: "autoUpgradeProfile.nodeOSUpgradeChannel",
    learnUrl: "https://learn.microsoft.com/azure/aks/auto-upgrade-node-os-image",
    variableName: "node_os_upgrade_channel",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Cluster Auto-Upgrade",
    armPath: "autoUpgradeProfile.upgradeChannel",
    learnUrl: "https://learn.microsoft.com/azure/aks/auto-upgrade-cluster",
    variableName: "upgrade_channel",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
  {
    name: "Application Routing (Web App Routing)",
    armPath: "ingressProfile.webAppRouting",
    learnUrl: "https://learn.microsoft.com/azure/aks/app-routing",
    variableName: "dns_zone_resource_ids",
    ga: true,
    norwayEast: true,
    swedenCentral: true,
  },
];

function checkModuleImplementation(dir) {
  const results = { implemented: [], notImplemented: [], preconfigured: [] };

  let mainContent = "";
  let varsContent = "";
  try {
    mainContent = readFileSync(join(dir, "main.tf"), "utf-8");
    varsContent = readFileSync(join(dir, "variables.tf"), "utf-8");
  } catch {
    return { error: "Could not read main.tf or variables.tf" };
  }

  for (const feature of AKS_FEATURES) {
    const hasVariable = feature.variableName && varsContent.includes(`"${feature.variableName}"`);
    const hasArmPath = mainContent.includes(feature.armPath.split(".").pop());

    if (feature.variableName === null && hasArmPath) {
      results.preconfigured.push(feature);
    } else if (hasVariable || hasArmPath) {
      results.implemented.push(feature);
    } else {
      results.notImplemented.push(feature);
    }
  }

  return results;
}

const session = await joinSession({
  tools: [
    {
      name: "aks_feature_scan",
      description:
        "Scans the AKS Automatic Terraform module against a known list of AKS Automatic ARM API " +
        "properties. Reports which features are implemented (have variables), preconfigured (hardcoded), " +
        "or not yet wired. Each feature includes a Microsoft Learn link for reference.",
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
        const results = checkModuleImplementation(dir);

        if (results.error) return results.error;

        const lines = [];

        lines.push(`## AKS Automatic Feature Coverage\n`);
        lines.push(
          `| Status | Count |\n|---|---|\n| Implemented (variable exposed) | ${results.implemented.length} |\n| Preconfigured (hardcoded) | ${results.preconfigured.length} |\n| Not yet wired | ${results.notImplemented.length} |`
        );

        if (results.implemented.length > 0) {
          lines.push(`\n### Implemented features\n`);
          for (const f of results.implemented) {
            lines.push(
              `- **${f.name}** (\`${f.variableName || f.armPath}\`) - [docs](${f.learnUrl})`
            );
          }
        }

        if (results.preconfigured.length > 0) {
          lines.push(`\n### Preconfigured (always enabled, no variable)\n`);
          for (const f of results.preconfigured) {
            lines.push(`- **${f.name}** (\`${f.armPath}\`) - [docs](${f.learnUrl})`);
          }
        }

        if (results.notImplemented.length > 0) {
          lines.push(`\n### Not yet wired (candidates for future implementation)\n`);
          for (const f of results.notImplemented) {
            lines.push(
              `- **${f.name}** (\`${f.armPath}\`) - [docs](${f.learnUrl})`
            );
          }
        }

        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
