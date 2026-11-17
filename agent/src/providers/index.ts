import { Failure } from "../failure"
import type { ProviderName } from "../schema"
import { anthropic } from "./anthropic"
import { openai } from "./openai"
import type { Provider } from "./provider"

const keys = { anthropic: ["ANTHROPIC_API_KEY", "Claude"], openai: ["OPENAI_API_KEY", "OpenAI"] } as const

export function provider(name: ProviderName): Provider {
  const [variable, title] = keys[name]
  if (!process.env[variable]) throw new Failure(`No ${title} API key is set.`)
  return name === "anthropic" ? anthropic() : openai()
}
