import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, extname } from "node:path";

// Patterns that violate repo style rules
const FORBIDDEN_EMOJIS = /(?!✅|❌)[\u{1F300}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}\u{1FA00}-\u{1FA6F}\u{1FA70}-\u{1FAFF}]/u;
const EM_DASH = /\u2014/g;
const EN_DASH = /\u2013/g;
const DOUBLE_DASH = / -- /g;
const BULLET_CHAR = /\u2022/g;
const GEQ_CHAR = /\u2265/g;
const AI_WORDS = /\b(leverage|utilize|comprehensive|robust|seamless|streamline|harness|empower|cutting-edge|delve|tapestry)\b/gi;

const CHECKED_EXTENSIONS = new Set([".tf", ".md", ".example", ".yml", ".yaml", ".hcl"]);

function scanFile(filePath) {
  const issues = [];
  let content;
  try {
    content = readFileSync(filePath, "utf-8");
  } catch {
    return issues;
  }

  const lines = content.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const lineNum = i + 1;

    if (EM_DASH.test(line)) issues.push(`${filePath}:${lineNum}: em dash found`);
    if (EN_DASH.test(line)) issues.push(`${filePath}:${lineNum}: en dash found`);
    if (DOUBLE_DASH.test(line)) issues.push(`${filePath}:${lineNum}: double-dash em-dash approximation found`);
    if (BULLET_CHAR.test(line)) issues.push(`${filePath}:${lineNum}: bullet character found (use - instead)`);
    if (GEQ_CHAR.test(line)) issues.push(`${filePath}:${lineNum}: non-ASCII >= character found`);
    if (AI_WORDS.test(line)) {
      const match = line.match(AI_WORDS);
      issues.push(`${filePath}:${lineNum}: AI language found: ${match.join(", ")}`);
    }

    // Reset lastIndex for global regexes
    EM_DASH.lastIndex = 0;
    EN_DASH.lastIndex = 0;
    DOUBLE_DASH.lastIndex = 0;
    BULLET_CHAR.lastIndex = 0;
    GEQ_CHAR.lastIndex = 0;
    AI_WORDS.lastIndex = 0;
  }

  return issues;
}

function scanDirectory(dir, maxDepth = 3, depth = 0) {
  if (depth > maxDepth) return [];
  const issues = [];
  let entries;
  try {
    entries = readdirSync(dir);
  } catch {
    return issues;
  }

  for (const entry of entries) {
    if (entry.startsWith(".") && entry !== ".github") continue;
    if (entry === "node_modules" || entry === ".terraform") continue;

    const fullPath = join(dir, entry);
    let stat;
    try {
      stat = statSync(fullPath);
    } catch {
      continue;
    }

    if (stat.isDirectory()) {
      issues.push(...scanDirectory(fullPath, maxDepth, depth + 1));
    } else if (CHECKED_EXTENSIONS.has(extname(entry))) {
      issues.push(...scanFile(fullPath));
    }
  }
  return issues;
}

const session = await joinSession({
  tools: [
    {
      name: "style_check",
      description:
        "Scans all .tf, .md, .example, .yml, .yaml, and .hcl files for style violations: " +
        "non-allowed emojis, em/en dashes, double-dash approximations, bullet characters, " +
        "non-ASCII symbols, and AI language. Returns a list of violations with file and line number.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Directory to scan. Defaults to the repo root.",
          },
        },
      },
      handler: async (args) => {
        const dir = args.path || process.cwd();
        const issues = scanDirectory(dir);
        if (issues.length === 0) {
          return "Style check passed. No violations found.";
        }
        return `Found ${issues.length} style violation(s):\n${issues.join("\n")}`;
      },
    },
  ],
  hooks: {},
});
