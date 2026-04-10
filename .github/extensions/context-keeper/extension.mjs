import { joinSession } from "@github/copilot-sdk/extension";
import {
  readFileSync,
  readdirSync,
  writeFileSync,
  mkdirSync,
  existsSync,
} from "node:fs";
import { join, extname } from "node:path";

const CONTEXT_DIR_NAME = "docs/context";
const ALLOWED_EXTENSIONS = new Set([".md", ".json"]);

function getContextDir(baseDir) {
  return join(baseDir, CONTEXT_DIR_NAME);
}

function readContextFiles(contextDir) {
  if (!existsSync(contextDir)) {
    return [];
  }

  const entries = [];
  let files;
  try {
    files = readdirSync(contextDir);
  } catch {
    return entries;
  }

  for (const file of files) {
    if (!ALLOWED_EXTENSIONS.has(extname(file))) continue;

    const filePath = join(contextDir, file);
    let content;
    try {
      content = readFileSync(filePath, "utf-8");
    } catch {
      continue;
    }

    const previewLines = content.split("\n").slice(0, 5).join("\n");
    entries.push({ file, preview: previewLines, content });
  }

  return entries;
}

const session = await joinSession({
  tools: [
    {
      name: "recall_context",
      description:
        "Reads structured context files from docs/context/ and returns their contents. " +
        "Scans for .md and .json files. Returns a summary of all available context with " +
        "file names and a preview of each file.",
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
        const contextDir = getContextDir(dir);

        if (!existsSync(contextDir)) {
          return `No context directory found at ${CONTEXT_DIR_NAME}. Use store_context to create entries.`;
        }

        const entries = readContextFiles(contextDir);
        if (entries.length === 0) {
          return `Context directory ${CONTEXT_DIR_NAME} exists but contains no .md or .json files.`;
        }

        const results = [];
        results.push(`## Context files (${entries.length} found in ${CONTEXT_DIR_NAME})\n`);

        for (const entry of entries) {
          results.push(`### ${entry.file}`);
          results.push("```");
          results.push(entry.content);
          results.push("```\n");
        }

        return results.join("\n");
      },
    },
    {
      name: "store_context",
      description:
        "Writes a context entry to docs/context/. Accepts a filename and content string. " +
        "Creates the directory if it does not exist. Useful for storing ADRs, ALZ constraints, " +
        "CIDR plans, known limitations, and deployment history.",
      parameters: {
        type: "object",
        properties: {
          path: {
            type: "string",
            description: "Path to the module directory. Defaults to cwd.",
          },
          filename: {
            type: "string",
            description:
              "Name of the context file to create or overwrite (e.g. alz-constraints.md).",
          },
          content: {
            type: "string",
            description: "Content to write to the context file.",
          },
        },
        required: ["filename", "content"],
      },
      handler: async (args) => {
        const dir = args.path || process.cwd();
        const contextDir = getContextDir(dir);

        const ext = extname(args.filename);
        if (!ALLOWED_EXTENSIONS.has(ext)) {
          return `Error: Only .md and .json files are allowed. Got: ${ext}`;
        }

        if (!existsSync(contextDir)) {
          mkdirSync(contextDir, { recursive: true });
        }

        const filePath = join(contextDir, args.filename);
        try {
          writeFileSync(filePath, args.content, "utf-8");
        } catch (err) {
          return `Error writing file: ${err.message}`;
        }

        return `Context saved to ${CONTEXT_DIR_NAME}/${args.filename}`;
      },
    },
  ],
  hooks: {},
});
