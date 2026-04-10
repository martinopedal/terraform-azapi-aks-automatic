import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// Label-to-squad-tool mapping (mirrors squad-dispatch.yml)
const SQUAD_MAP = {
  security: { extension: "security-reviewer", tool: "security_scan" },
  networking: { extension: "network-architect", tool: "network_review" },
  alz: { extension: "alz-checker", tool: "alz_alignment_check" },
  testing: { extension: "terraform-engineer", tool: "terraform_engineering_review" },
  "feature-tracking": { extension: "aks-feature-tracker", tool: "aks_feature_scan" },
  "ci-cd": { extension: "terraform-validator", tool: "terraform_validate_full" },
  documentation: { extension: "doc-checker", tool: "doc_check" },
  enhancement: { extension: "style-guard", tool: "style_check" },
  gitops: { extension: "gitops-architect", tool: "gitops_review" },
};

// All available squad tools in execution order
const ALL_TOOLS = [
  "style_check",
  "terraform_validate_full",
  "security_scan",
  "network_review",
  "alz_alignment_check",
  "aks_feature_scan",
  "terraform_engineering_review",
  "doc_check",
  "gitops_review",
];

function getSquadMd(dir) {
  try {
    return readFileSync(join(dir, "SQUAD.md"), "utf-8");
  } catch {
    return null;
  }
}

function resolveTools(labels) {
  if (!labels || labels.length === 0) return ALL_TOOLS;

  const tools = new Set();
  let hasSpecific = false;

  for (const label of labels) {
    const entry = SQUAD_MAP[label];
    if (entry) {
      tools.add(entry.tool);
      hasSpecific = true;
    }
  }

  // Generic "squad" label with no specific domain label -> style + doc
  if (!hasSpecific && labels.includes("squad")) {
    tools.add("style_check");
    tools.add("doc_check");
  }

  return Array.from(tools);
}

const session = await joinSession({
  tools: [
    {
      name: "squad_dispatch",
      description:
        "Routes an issue to the correct squad tools based on labels. " +
        "Accepts a list of labels and returns the squad tools to run, " +
        "their extensions, and execution instructions. Use this to " +
        "determine which squad agents should work on a given issue.",
      parameters: {
        type: "object",
        properties: {
          labels: {
            type: "array",
            items: { type: "string" },
            description:
              "GitHub issue labels (e.g. ['security', 'networking', 'squad']). " +
              "Omit or pass empty array to get all squad tools.",
          },
        },
      },
      handler: async (args) => {
        const labels = args.labels || [];
        const tools = resolveTools(labels);

        const lines = [];
        lines.push("## Squad Dispatch\n");

        if (labels.length > 0) {
          lines.push(`**Labels:** ${labels.map((l) => "`" + l + "`").join(", ")}\n`);
        }

        lines.push("**Assigned tools:**\n");
        lines.push("| Tool | Extension | Run command |");
        lines.push("|---|---|---|");

        for (const tool of tools) {
          const entry = Object.values(SQUAD_MAP).find((e) => e.tool === tool);
          if (entry) {
            lines.push(`| \`${tool}\` | \`${entry.extension}\` | Run \`${tool}\` |`);
          }
        }

        lines.push("\nCall each tool listed above to execute the squad review.");
        return lines.join("\n");
      },
    },
    {
      name: "squad_status",
      description:
        "Returns the full squad roster with all 8 extensions and their tools. " +
        "Shows the label-to-tool mapping used by the squad dispatcher workflow.",
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
        const squadMd = getSquadMd(dir);

        const lines = [];
        lines.push("## Squad Roster\n");
        lines.push("| Label | Extension | Tool |");
        lines.push("|---|---|---|");

        for (const [label, entry] of Object.entries(SQUAD_MAP)) {
          lines.push(`| \`${label}\` | \`${entry.extension}\` | \`${entry.tool}\` |`);
        }

        lines.push("\n**Total agents:** 8");
        lines.push(`**SQUAD.md:** ${squadMd ? "present" : "missing"}`);

        return lines.join("\n");
      },
    },
    {
      name: "squad_run_all",
      description:
        "Returns the full list of all 8 squad tools to run, in recommended " +
        "execution order. Call each tool in sequence to perform a complete " +
        "squad review of the module.",
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
        const lines = [];
        lines.push("## Full Squad Run\n");
        lines.push("Execute all 8 squad tools in this order:\n");

        for (let i = 0; i < ALL_TOOLS.length; i++) {
          const tool = ALL_TOOLS[i];
          const entry = Object.values(SQUAD_MAP).find((e) => e.tool === tool);
          lines.push(`${i + 1}. \`${tool}\` (${entry ? entry.extension : "unknown"})`);
        }

        lines.push("\nCall each tool above to perform a complete module review.");
        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
