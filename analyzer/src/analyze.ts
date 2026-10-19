import { query, type McpServerConfig } from "@anthropic-ai/claude-agent-sdk"
import { extractFromBunfs } from "@anthropic-ai/claude-agent-sdk/extract"
import claude from "@anthropic-ai/claude-agent-sdk-darwin-arm64/claude" with { type: "file" }
import { systemPrompt, userPrompt } from "./prompt"
import { headers, schema, type Connector, type Input, type Item } from "./schema"

export const slug = (name: string) =>
  name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")

export function servers(connectors: Connector[]): Record<string, McpServerConfig> {
  return Object.fromEntries(
    connectors.map((connector) => [
      slug(connector.name),
      { type: "http", url: connector.url, headers: headers(connector), alwaysLoad: true },
    ]),
  )
}

export async function analyze(input: Input): Promise<Item[]> {
  const mcpServers = servers(input.connectors)
  const session = query({
    prompt: userPrompt(input),
    options: {
      model: "claude-opus-5-5",
      systemPrompt: systemPrompt(input.owner, input.connectors),
      outputFormat: { type: "json_schema", schema },
      settingSources: [],
      strictMcpConfig: true,
      mcpServers,
      tools: [],
      allowedTools: Object.keys(mcpServers).map((name) => `mcp__${name}__*`),
      permissionMode: "dontAsk",
      persistSession: false,
      pathToClaudeCodeExecutable: extractFromBunfs(claude),
    },
  })
  for await (const message of session) {
    if (message.type !== "result") continue
    if (message.subtype !== "success") throw new Error(message.errors.join(" ") || `Analysis failed (${message.subtype}).`)
    if (message.is_error) throw new Error(message.result)
    return (message.structured_output as { items: Item[] }).items
  }
  throw new Error("Analysis ended without a result.")
}
