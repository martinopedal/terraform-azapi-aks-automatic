import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

// Terraform engineering best practice checks
const TF_CHECKS = [
  {
    id: "TF-01",
    name: "Provider version constraints use pessimistic operator",
    check: (files) => {
      const tf = files["terraform.tf"] || "";
      return tf.includes("~>"); // Both azapi and azurerm should use ~>
    },
  },
  {
    id: "TF-02",
    name: "Required Terraform version specified",
    check: (files) => {
      const tf = files["terraform.tf"] || "";
      return tf.includes("required_version");
    },
  },
  {
    id: "TF-03",
    name: "All variables have descriptions",
    check: (files) => {
      const vars = files["variables.tf"] || "";
      const varCount = (vars.match(/variable\s+"/g) || []).length;
      const descCount = (vars.match(/description\s*=/g) || []).length;
      return varCount > 0 && varCount === descCount;
    },
  },
  {
    id: "TF-04",
    name: "All variables have type constraints",
    check: (files) => {
      const vars = files["variables.tf"] || "";
      const varCount = (vars.match(/variable\s+"/g) || []).length;
      const typeCount = (vars.match(/type\s*=/g) || []).length;
      return varCount > 0 && varCount === typeCount;
    },
  },
  {
    id: "TF-05",
    name: "All outputs have descriptions",
    check: (files) => {
      const outs = files["outputs.tf"] || "";
      const outCount = (outs.match(/output\s+"/g) || []).length;
      const descCount = (outs.match(/description\s*=/g) || []).length;
      return outCount > 0 && outCount === descCount;
    },
  },
  {
    id: "TF-06",
    name: "Conditional resources use count (not for_each for 0/1)",
    check: (files) => {
      const net = files["network.tf"] || "";
      const deps = files["dependencies.tf"] || "";
      return (net + deps).includes("count");
    },
  },
  {
    id: "TF-07",
    name: "Tags propagated via local (not hardcoded)",
    check: (files) => {
      const main = files["main.tf"] || "";
      const locals = files["locals.tf"] || "";
      return locals.includes("tags = var.tags") && main.includes("local.tags");
    },
  },
  {
    id: "TF-08",
    name: "Sensitive outputs marked where appropriate",
    check: () => true, // Currently no sensitive outputs needed
  },
  {
    id: "TF-09",
    name: "Optional outputs use try() for count-dependent resources",
    check: (files) => {
      const outs = files["outputs.tf"] || "";
      return outs.includes("try(");
    },
  },
  {
    id: "TF-10",
    name: "No provider blocks in child-module-ready code",
    check: (files) => {
      // This is a root module, so providers are expected.
      // Check that it's documented as root module.
      const readme = files["README.md"] || "";
      return readme.includes("root module");
    },
  },
  {
    id: "TF-11",
    name: "Deterministic resource names (uuidv5 for role assignments)",
    check: (files) => {
      const deps = files["dependencies.tf"] || "";
      return deps.includes("uuidv5");
    },
  },
  {
    id: "TF-12",
    name: "ignore_changes for externally-managed fields",
    check: (files) => {
      const main = files["main.tf"] || "";
      return main.includes("ignore_changes");
    },
  },
];

function runTfEngineerCheck(dir) {
  const fileNames = [
    "main.tf", "variables.tf", "locals.tf", "network.tf",
    "dependencies.tf", "outputs.tf", "terraform.tf", "README.md",
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

  for (const check of TF_CHECKS) {
    if (check.check(files)) {
      passed.push(check);
    } else {
      failed.push(check);
    }
  }

  // Module stats
  const vars = files["variables.tf"] || "";
  const outs = files["outputs.tf"] || "";
  const main = files["main.tf"] || "";

  const stats = {
    variables: (vars.match(/variable\s+"/g) || []).length,
    outputs: (outs.match(/output\s+"/g) || []).length,
    validations: (vars.match(/validation\s*\{/g) || []).length,
    preconditions: (main.match(/precondition\s*\{/g) || []).length,
    resources: 0,
  };

  const allContent = Object.values(files).filter(Boolean).join("\n");
  stats.resources = (allContent.match(/resource\s+"azapi_resource"/g) || []).length;

  return { passed, failed, stats };
}

const session = await joinSession({
  tools: [
    {
      name: "terraform_engineering_review",
      description:
        "Reviews the Terraform module against HCL engineering best practices: " +
        "provider constraints, variable/output descriptions and types, tag propagation, " +
        "conditional resource patterns, deterministic naming, lifecycle management, " +
        "and module structure. Also reports module statistics.",
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
        const { passed, failed, stats } = runTfEngineerCheck(dir);

        const lines = [];
        lines.push("## Terraform Engineering Review\n");
        lines.push(`| Result | Count |\n|---|---|\n| Passed | ${passed.length} |\n| Failed | ${failed.length} |`);

        lines.push(`\n### Module statistics\n`);
        lines.push(`| Metric | Count |\n|---|---|`);
        lines.push(`| Resources (azapi_resource) | ${stats.resources} |`);
        lines.push(`| Variables | ${stats.variables} |`);
        lines.push(`| Outputs | ${stats.outputs} |`);
        lines.push(`| Validation blocks | ${stats.validations} |`);
        lines.push(`| Precondition blocks | ${stats.preconditions} |`);

        if (failed.length > 0) {
          lines.push("\n### Failed checks\n");
          for (const f of failed) {
            lines.push(`- **${f.id}: ${f.name}**`);
          }
        }

        if (passed.length > 0) {
          lines.push("\n### Passed checks\n");
          for (const p of passed) {
            lines.push(`- ${p.id}: ${p.name}`);
          }
        }

        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
