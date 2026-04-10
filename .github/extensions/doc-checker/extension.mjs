import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

function extractReadmeFeatureClaims(readmePath) {
  let content;
  try {
    content = readFileSync(readmePath, "utf-8");
  } catch {
    return { error: "Could not read README.md" };
  }

  const claims = [];

  // Find "Configurable" column entries that say "Yes" or reference ARM paths
  const tableRows = content.match(/\|[^|]+\|[^|]+\|[^|]+\|/g) || [];
  for (const row of tableRows) {
    if (/Yes\s*-\s*`[^`]+`/.test(row) || /not yet wired/.test(row)) {
      const cells = row.split("|").filter((c) => c.trim());
      if (cells.length >= 2) {
        claims.push({
          feature: cells[0].trim(),
          configurable: cells[cells.length - 1].trim(),
        });
      }
    }
  }

  return { claims };
}

function extractCodeVariables(dir) {
  const varsFile = join(dir, "variables.tf");
  let content;
  try {
    content = readFileSync(varsFile, "utf-8");
  } catch {
    return [];
  }

  const vars = [];
  const matches = content.matchAll(/variable\s+"([^"]+)"/g);
  for (const m of matches) {
    vars.push(m[1]);
  }
  return vars;
}

function extractLearnLinks(readmePath) {
  let content;
  try {
    content = readFileSync(readmePath, "utf-8");
  } catch {
    return [];
  }

  const links = [];
  const matches = content.matchAll(/\(https:\/\/learn\.microsoft\.com\/[^)]+\)/g);
  for (const m of matches) {
    links.push(m[0].slice(1, -1));
  }
  return [...new Set(links)];
}

function checkProjectStructure(dir, readmePath) {
  let content;
  try {
    content = readFileSync(readmePath, "utf-8");
  } catch {
    return ["Could not read README.md"];
  }

  const issues = [];
  const actualFiles = readdirSync(dir).filter((f) => !f.startsWith(".") || f === ".github" || f === ".gitignore");

  // Check files mentioned in project structure tree
  const treeMatch = content.match(/```\n[\s\S]*?```/g);
  if (treeMatch) {
    for (const tree of treeMatch) {
      // Check for .tf files referenced
      const tfRefs = tree.match(/[a-z_]+\.tf/g) || [];
      for (const ref of tfRefs) {
        if (!existsSync(join(dir, ref))) {
          issues.push(`Project structure references ${ref} but file does not exist`);
        }
      }
    }
  }

  // Check actual .tf files exist in project structure
  const tfFiles = actualFiles.filter((f) => f.endsWith(".tf"));
  for (const tf of tfFiles) {
    if (!content.includes(tf)) {
      issues.push(`${tf} exists on disk but is not in README project structure`);
    }
  }

  return issues;
}

const session = await joinSession({
  tools: [
    {
      name: "doc_check",
      description:
        "Cross-references README.md feature claims against actual code (variables, resources), " +
        "checks project structure listing matches files on disk, and lists all Microsoft Learn links " +
        "found in the documentation.",
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
        const readmePath = join(dir, "README.md");
        const results = [];

        // Feature claims vs variables
        const { claims, error } = extractReadmeFeatureClaims(readmePath);
        if (error) return error;
        const vars = extractCodeVariables(dir);

        results.push(`## Feature claims in README\nFound ${claims.length} configurable feature entries.`);

        const notWired = claims.filter((c) => c.configurable.includes("not yet wired"));
        if (notWired.length > 0) {
          results.push(
            `### Documented as not yet wired:\n${notWired.map((c) => `- ${c.feature}: ${c.configurable}`).join("\n")}`
          );
        }

        // Project structure
        const structureIssues = checkProjectStructure(dir, readmePath);
        if (structureIssues.length === 0) {
          results.push("## Project structure\nPASSED: all files match.");
        } else {
          results.push(
            `## Project structure\n${structureIssues.length} issue(s):\n${structureIssues.map((i) => `- ${i}`).join("\n")}`
          );
        }

        // Learn links
        const links = extractLearnLinks(readmePath);
        results.push(
          `## Microsoft Learn links\nFound ${links.length} unique Learn links:\n${links.map((l) => `- ${l}`).join("\n")}`
        );

        // Variable count
        results.push(`## Variables\n${vars.length} variables defined in variables.tf.`);

        return results.join("\n\n");
      },
    },
  ],
  hooks: {},
});
