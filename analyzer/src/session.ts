import { query, type Options } from "@anthropic-ai/claude-agent-sdk"
import { extractFromBunfs } from "@anthropic-ai/claude-agent-sdk/extract"
import claude from "@anthropic-ai/claude-agent-sdk-darwin-arm64/claude" with { type: "file" }

export const session = (prompt: Parameters<typeof query>[0]["prompt"], options: Options = {}) =>
  query({
    prompt,
    options: {
      settingSources: [],
      persistSession: false,
      pathToClaudeCodeExecutable: extractFromBunfs(claude),
      ...options,
    },
  })
