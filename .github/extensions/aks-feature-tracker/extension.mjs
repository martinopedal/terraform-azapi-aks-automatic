import { joinSession } from "@github/copilot-sdk/extension";
import { checkModuleImplementation } from "./scan.mjs";

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
