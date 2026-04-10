import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

function findVariableValidations(dir) {
  const varsFile = join(dir, "variables.tf");
  let content;
  try {
    content = readFileSync(varsFile, "utf-8");
  } catch {
    return [];
  }

  const results = [];
  const varSections = content.split(/\n(?=variable\s+")/);

  for (const section of varSections) {
    const nameMatch = section.match(/variable\s+"([^"]+)"/);
    if (!nameMatch) continue;
    const name = nameMatch[1];

    // Find all validation blocks within this variable
    const validationBlocks = [];
    const validationRegex = /validation\s*\{[^}]*condition\s*=\s*([^\n]+)/g;
    let match;
    while ((match = validationRegex.exec(section)) !== null) {
      validationBlocks.push(match[1].trim());
    }

    // Extract type and default for stub generation
    const typeMatch = section.match(/type\s*=\s*(\S+)/);
    const defaultMatch = section.match(/default\s*=\s*([^\n]+)/);
    const type = typeMatch ? typeMatch[1] : "string";
    const defaultVal = defaultMatch ? defaultMatch[1].trim() : null;

    results.push({
      name,
      type,
      default: defaultVal,
      validations: validationBlocks,
      hasValidation: validationBlocks.length > 0,
    });
  }

  return results;
}

function findPreconditions(dir) {
  const results = [];
  let files;
  try {
    files = readdirSync(dir).filter((f) => f.endsWith(".tf"));
  } catch {
    return results;
  }

  for (const file of files) {
    const content = readFileSync(join(dir, file), "utf-8");
    const resourceRegex = /resource\s+"([^"]+)"\s+"([^"]+)"/g;
    let resMatch;

    while ((resMatch = resourceRegex.exec(content)) !== null) {
      const resType = resMatch[1];
      const resName = resMatch[2];
      const resStart = resMatch.index;

      // Find the block boundaries for this resource
      let braceDepth = 0;
      let blockStarted = false;
      let blockEnd = content.length;
      for (let i = resStart; i < content.length; i++) {
        if (content[i] === "{") {
          braceDepth++;
          blockStarted = true;
        } else if (content[i] === "}") {
          braceDepth--;
          if (blockStarted && braceDepth === 0) {
            blockEnd = i;
            break;
          }
        }
      }

      const block = content.substring(resStart, blockEnd);
      const preRegex = /precondition\s*\{[^}]*condition\s*=\s*([^\n]+)/g;
      let preMatch;
      while ((preMatch = preRegex.exec(block)) !== null) {
        // Extract the error_message if present
        const errMatch = block.substring(preMatch.index).match(
          /error_message\s*=\s*"([^"]+)"/
        );
        results.push({
          resource: `${resType}.${resName}`,
          file,
          condition: preMatch[1].trim(),
          errorMessage: errMatch ? errMatch[1] : "",
        });
      }
    }
  }

  return results;
}

function findExistingTests(dir) {
  const testFiles = new Set();
  try {
    const files = readdirSync(dir).filter((f) => f.endsWith(".tftest.hcl"));
    for (const file of files) {
      testFiles.add(file);
    }
  } catch {
    // no test files
  }

  // Also check a tests/ subdirectory
  try {
    const testsDir = join(dir, "tests");
    const files = readdirSync(testsDir).filter((f) => f.endsWith(".tftest.hcl"));
    for (const file of files) {
      testFiles.add(`tests/${file}`);
    }
  } catch {
    // no tests directory
  }

  return testFiles;
}

function generateTestStub(varInfo) {
  const lines = [];
  lines.push(`run "validate_${varInfo.name}_invalid" {`);
  lines.push(`  command = plan`);
  lines.push(`  expect_failures = [var.${varInfo.name}]`);
  lines.push(``);
  lines.push(`  variables {`);
  lines.push(`    ${varInfo.name} = "INVALID_VALUE" # Replace with a value that should fail validation`);
  lines.push(`  }`);
  lines.push(`}`);
  return lines.join("\n");
}

function generatePreconditionTestStub(pre) {
  const safeName = pre.resource.replace(/\./g, "_");
  const lines = [];
  lines.push(`run "precondition_${safeName}" {`);
  lines.push(`  command = plan`);
  lines.push(`  expect_failures = [${pre.resource}]`);
  lines.push(``);
  lines.push(`  # Condition: ${pre.condition}`);
  if (pre.errorMessage) {
    lines.push(`  # Expected error: ${pre.errorMessage}`);
  }
  lines.push(``);
  lines.push(`  variables {`);
  lines.push(`    # Set variables that trigger this precondition failure`);
  lines.push(`  }`);
  lines.push(`}`);
  return lines.join("\n");
}

const session = await joinSession({
  tools: [
    {
      name: "generate_test_stubs",
      description:
        "Generates Terraform native test (.tftest.hcl) stubs from variable validations and " +
        "resource preconditions. Scans variables.tf for validation blocks and all .tf files for " +
        "precondition blocks, then produces test case stubs for each. Reports coverage status.",
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
        const results = [];

        const variables = findVariableValidations(dir);
        const preconditions = findPreconditions(dir);
        const existingTests = findExistingTests(dir);

        // Coverage summary
        const varsWithValidation = variables.filter((v) => v.hasValidation);
        const varsWithout = variables.filter((v) => !v.hasValidation);

        results.push("## Variable validation coverage");
        results.push(
          `Found ${varsWithValidation.length} variable(s) with validation blocks, ` +
          `${varsWithout.length} without.`
        );

        if (varsWithValidation.length > 0) {
          results.push("\nVariables WITH validation:");
          for (const v of varsWithValidation) {
            results.push(`  - ${v.name} (${v.validations.length} validation block(s))`);
          }
        }

        if (varsWithout.length > 0) {
          results.push("\nVariables WITHOUT validation:");
          for (const v of varsWithout) {
            results.push(`  - ${v.name} (type: ${v.type})`);
          }
        }

        results.push("\n## Preconditions");
        results.push(`Found ${preconditions.length} precondition(s) across .tf files.`);
        for (const pre of preconditions) {
          results.push(`  - ${pre.resource} in ${pre.file}: ${pre.errorMessage || pre.condition}`);
        }

        results.push("\n## Existing test files");
        if (existingTests.size > 0) {
          for (const t of existingTests) {
            results.push(`  - ${t}`);
          }
        } else {
          results.push("  No .tftest.hcl files found.");
        }

        // Generate stubs
        results.push("\n## Generated test stubs");
        results.push("Copy the blocks below into a .tftest.hcl file.\n");

        if (varsWithValidation.length > 0) {
          results.push("### Variable validation tests\n");
          for (const v of varsWithValidation) {
            results.push(generateTestStub(v));
            results.push("");
          }
        }

        if (preconditions.length > 0) {
          results.push("### Precondition tests\n");
          for (const pre of preconditions) {
            results.push(generatePreconditionTestStub(pre));
            results.push("");
          }
        }

        if (varsWithValidation.length === 0 && preconditions.length === 0) {
          results.push("No validations or preconditions found to generate stubs for.");
        }

        return results.join("\n");
      },
    },
  ],
  hooks: {},
});
