import { joinSession } from "@github/copilot-sdk/extension";
import { execFile } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

async function runCommand(cmd, args, cwd) {
  try {
    const { stdout, stderr } = await execFileAsync(cmd, args, {
      cwd,
      timeout: 60000,
    });
    return { success: true, stdout: stdout.trim(), stderr: stderr.trim() };
  } catch (err) {
    return {
      success: false,
      stdout: err.stdout?.trim() || "",
      stderr: err.stderr?.trim() || err.message,
    };
  }
}

function findVariablesWithoutValidation(dir) {
  const varsFile = join(dir, "variables.tf");
  let content;
  try {
    content = readFileSync(varsFile, "utf-8");
  } catch {
    return ["Could not read variables.tf"];
  }

  // Split on variable declarations instead of regex to handle nested braces correctly
  const varSections = content.split(/\n(?=variable\s+")/);
  const missing = [];

  for (const section of varSections) {
    const nameMatch = section.match(/variable\s+"([^"]+)"/);
    if (!nameMatch) continue;
    const name = nameMatch[1];

    // Skip booleans, maps, lists, and objects (validation is less applicable)
    if (/type\s*=\s*(bool|map|list|object)/.test(section)) continue;

    if (!section.includes("validation {")) {
      missing.push(name);
    }
  }

  return missing;
}

function findResourcesWithoutLifecycle(dir) {
  const missing = [];
  const criticalResources = ["azapi_resource.aks", "azapi_resource.rg"];
  const files = readdirSync(dir).filter((f) => f.endsWith(".tf"));

  for (const file of files) {
    const content = readFileSync(join(dir, file), "utf-8");
    for (const res of criticalResources) {
      const [type, name] = res.split(".");
      const pattern = new RegExp(`resource\\s+"${type}"\\s+"${name}"\\s+\\{`);
      if (pattern.test(content) && !content.includes("prevent_destroy")) {
        missing.push(`${file}: ${res} missing prevent_destroy lifecycle`);
      }
    }
  }

  return missing;
}

const session = await joinSession({
  tools: [
    {
      name: "terraform_validate_full",
      description:
        "Runs terraform validate, fmt check, and inspects variables.tf for missing validation blocks " +
        "and critical resources for missing lifecycle blocks. Returns a structured report.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Path to the Terraform module directory. Defaults to cwd.",
          },
        },
      },
      handler: async (args) => {
        const dir = args.path || process.cwd();
        const results = [];

        // terraform validate
        const validate = await runCommand("terraform", ["validate"], dir);
        results.push(
          `## terraform validate\n${validate.success ? "PASSED" : "FAILED"}\n${validate.stdout}\n${validate.stderr}`
        );

        // terraform fmt check
        const fmt = await runCommand(
          "terraform",
          ["fmt", "-check", "-recursive"],
          dir
        );
        if (fmt.success) {
          results.push("## terraform fmt\nPASSED (all files formatted correctly)");
        } else {
          results.push(
            `## terraform fmt\nFAILED (unformatted files):\n${fmt.stdout}`
          );
        }

        // Variable validation coverage
        const missingValidation = findVariablesWithoutValidation(dir);
        if (missingValidation.length === 0) {
          results.push(
            "## Variable validation coverage\nAll string/number variables have validation blocks."
          );
        } else {
          results.push(
            `## Variable validation coverage\nVariables without validation blocks:\n- ${missingValidation.join("\n- ")}`
          );
        }

        // Lifecycle coverage
        const missingLifecycle = findResourcesWithoutLifecycle(dir);
        if (missingLifecycle.length === 0) {
          results.push(
            "## Lifecycle coverage\nAll critical resources have prevent_destroy."
          );
        } else {
          results.push(
            `## Lifecycle coverage\nMissing lifecycle blocks:\n- ${missingLifecycle.join("\n- ")}`
          );
        }

        return results.join("\n\n");
      },
    },
  ],
  hooks: {},
});
