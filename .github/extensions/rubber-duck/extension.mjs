import { joinSession } from "@github/copilot-sdk/extension";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// All models available for rubber-duck critique
const AVAILABLE_MODELS = [
  { id: "claude-sonnet-4.6", name: "Claude Sonnet 4.6", tier: "standard" },
  { id: "claude-sonnet-4.5", name: "Claude Sonnet 4.5", tier: "standard" },
  { id: "claude-haiku-4.5", name: "Claude Haiku 4.5", tier: "fast" },
  { id: "claude-opus-4.6", name: "Claude Opus 4.6", tier: "premium" },
  { id: "claude-opus-4.6-1m", name: "Claude Opus 4.6 (1M)", tier: "premium" },
  { id: "claude-opus-4.5", name: "Claude Opus 4.5", tier: "premium" },
  { id: "claude-sonnet-4", name: "Claude Sonnet 4", tier: "standard" },
  { id: "goldeneye", name: "Goldeneye", tier: "standard" },
  { id: "gpt-5.4", name: "GPT-5.4", tier: "standard" },
  { id: "gpt-5.3-codex", name: "GPT-5.3 Codex", tier: "standard" },
  { id: "gpt-5.2-codex", name: "GPT-5.2 Codex", tier: "standard" },
  { id: "gpt-5.2", name: "GPT-5.2", tier: "standard" },
  { id: "gpt-5.1", name: "GPT-5.1", tier: "standard" },
  { id: "gpt-5.4-mini", name: "GPT-5.4 mini", tier: "fast" },
  { id: "gpt-5-mini", name: "GPT-5 mini", tier: "fast" },
  { id: "gpt-4.1", name: "GPT-4.1", tier: "fast" },
];

// Default: ALL models for maximum consensus coverage
const DEFAULT_MODELS = AVAILABLE_MODELS.map((m) => m.id);

function gatherContext(dir) {
  const files = {};
  const tfFiles = ["main.tf", "variables.tf", "locals.tf", "network.tf",
    "dependencies.tf", "outputs.tf", "terraform.tf", "data.tf"];
  for (const name of tfFiles) {
    try {
      files[name] = readFileSync(join(dir, name), "utf-8");
    } catch {
      // file not present
    }
  }
  return files;
}

function buildContextSummary(files) {
  const lines = [];
  for (const [name, content] of Object.entries(files)) {
    const lineCount = content.split("\n").length;
    lines.push(`${name}: ${lineCount} lines`);
  }
  return lines.join(", ");
}

const session = await joinSession({
  tools: [
    {
      name: "rubber_duck_review",
      description:
        "Launches rubber-duck critique agents across multiple AI models in parallel. " +
        "Each model independently reviews the provided plan, code change, or implementation " +
        "for bugs, logic errors, security issues, and design flaws. Returns a consolidated " +
        "report showing where models agree (high confidence findings) and disagree " +
        "(areas needing human judgment). Use this for non-trivial changes that benefit " +
        "from diverse independent review perspectives.",
      parameters: {
        type: "object",
        properties: {
          topic: {
            type: "string",
            description:
              "What to review: a plan description, code change summary, or specific concern. " +
              "Be specific about what you want critiqued.",
          },
          path: {
            type: "string",
            description: "Path to the module directory for context gathering. Defaults to cwd.",
          },
          models: {
            type: "array",
            items: { type: "string" },
            description:
              "Model IDs to use for review. Defaults to a diverse set of 5 models " +
              "across Claude and GPT families. Pass 'all' as first element to use all 15 models.",
          },
          focus: {
            type: "string",
            description:
              "Optional focus area: 'security', 'correctness', 'architecture', 'performance', " +
              "'alz-compliance', or 'general' (default).",
          },
        },
        required: ["topic"],
      },
      handler: async (args) => {
        const dir = args.path || process.cwd();
        const files = gatherContext(dir);
        const contextSummary = buildContextSummary(files);

        let selectedModels = DEFAULT_MODELS;
        if (args.models && args.models.length > 0) {
          if (args.models[0] === "all") {
            selectedModels = AVAILABLE_MODELS.map((m) => m.id);
          } else {
            selectedModels = args.models;
          }
        }

        const focus = args.focus || "general";

        const lines = [];
        lines.push("## Rubber Duck Multi-Model Review\n");
        lines.push(`**Topic:** ${args.topic}\n`);
        lines.push(`**Focus:** ${focus}\n`);
        lines.push(`**Module context:** ${contextSummary}\n`);
        lines.push(`**Models to invoke:** ${selectedModels.length}\n`);

        lines.push("| Model | Tier | Status |");
        lines.push("|---|---|---|");

        for (const modelId of selectedModels) {
          const model = AVAILABLE_MODELS.find((m) => m.id === modelId);
          const name = model ? model.name : modelId;
          const tier = model ? model.tier : "unknown";
          lines.push(`| ${name} | ${tier} | Ready to invoke |`);
        }

        lines.push("\n### Invocation instructions\n");
        lines.push("Launch a **rubber-duck** agent for each model listed above using the `task` tool:");
        lines.push("```");
        lines.push("agent_type: rubber-duck");
        lines.push(`model: <model-id>`);
        lines.push("mode: background");
        lines.push("```\n");
        lines.push("**Prompt template for each agent:**\n");
        lines.push("```");
        lines.push(`Review the following for the AKS Automatic Terraform module (azapi provider).`);
        lines.push(`Focus: ${focus}`);
        lines.push(`Topic: ${args.topic}`);
        lines.push("");
        lines.push("Key files to examine: " + Object.keys(files).join(", "));
        lines.push("```\n");
        lines.push("After all agents complete, consolidate findings:");
        lines.push("- **Consensus findings** (2+ models agree) = high confidence, act on these");
        lines.push("- **Single-model findings** = review with judgment, may be false positives");
        lines.push("- **Contradictions** = flag for human decision");

        return lines.join("\n");
      },
    },
    {
      name: "list_review_models",
      description:
        "Lists all available AI models that can be used for rubber-duck multi-model review. " +
        "Shows model ID, display name, and tier (premium/standard/fast).",
      parameters: {
        type: "object",
        properties: {},
      },
      handler: async () => {
        const lines = [];
        lines.push("## Available Review Models\n");
        lines.push("| Model ID | Name | Tier |");
        lines.push("|---|---|---|");

        for (const m of AVAILABLE_MODELS) {
          lines.push(`| \`${m.id}\` | ${m.name} | ${m.tier} |`);
        }

        lines.push(`\n**Total:** ${AVAILABLE_MODELS.length} models`);
        lines.push("\n**Default:** All models are used by default for maximum consensus coverage.");

        return lines.join("\n");
      },
    },
  ],
  hooks: {},
});
