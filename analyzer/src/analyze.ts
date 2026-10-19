import { gate, readOnlyTools } from "./access"
import { systemPrompt, userPrompt } from "./prompt"
import { schema, type Input, type Item } from "./schema"
import { session } from "./session"

export async function analyze(input: Input): Promise<Item[]> {
  let tools: Promise<Set<string>> | undefined
  const conversation = session(userPrompt(input), {
    model: "claude-opus-5-5",
    systemPrompt: systemPrompt(input.owner),
    outputFormat: { type: "json_schema", schema },
    tools: ["Bash"],
    permissionMode: "dontAsk",
    hooks: { PreToolUse: [{ hooks: [gate(() => (tools ??= conversation.mcpServerStatus().then(readOnlyTools)))] }] },
  })
  for await (const message of conversation) {
    if (message.type !== "result") continue
    if (message.subtype !== "success") throw new Error(message.errors.join(" ") || `Analysis failed (${message.subtype}).`)
    if (message.is_error) throw new Error(message.result)
    return (message.structured_output as { items: Item[] }).items
  }
  throw new Error("Analysis ended without a result.")
}
