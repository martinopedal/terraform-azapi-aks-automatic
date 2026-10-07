// Pure AKS feature scan: no Copilot SDK dependency, so CI can run it with
// plain Node. The Copilot CLI extension (extension.mjs) reuses this logic.
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// AKS Automatic ARM properties that could be exposed as module variables.
// Each entry has the ARM path, a description, the Learn link, GA status, and regional availability.
export const AKS_FEATURES = [
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

export function checkModuleImplementation(dir) {
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

// CLI: node scan.mjs [moduleDir]  -> JSON summary on stdout, non-zero on error.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const dir = process.argv[2] || process.cwd();
  const results = checkModuleImplementation(dir);
  if (results.error) {
    console.error(results.error);
    process.exit(1);
  }
  console.log(JSON.stringify({
    implemented: results.implemented.length,
    preconfigured: results.preconfigured.length,
    not_wired: results.notImplemented.length,
    features_not_wired: results.notImplemented.map((f) => f.name),
  }, null, 2));
}
