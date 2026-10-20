import { systemPrompt, userPrompt } from "./prompt"
import { schema, type Bullet, type Input } from "./schema"
import { session } from "./session"

export async function listen(input: Input): Promise<Bullet[]> {
  const conversation = session(userPrompt(input), {
    model: "claude-sonnet-5-5",
    systemPrompt: systemPrompt(input.owner),
    outputFormat: { type: "json_schema", schema },
    tools: [],
  })
  for await (const message of conversation) {
    if (message.type !== "result") continue
    if (message.subtype !== "success") throw new Error(message.errors.join(" ") || `Listening failed (${message.subtype}).`)
    if (message.is_error) throw new Error(message.result)
    return (message.structured_output as { bullets: Bullet[] }).bullets
  }
  throw new Error("Listening ended without a result.")
}
