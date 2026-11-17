import Anthropic from "@anthropic-ai/sdk"
import { betaZodOutputFormat } from "@anthropic-ai/sdk/helpers/beta/zod"
import type { BetaRunnableTool } from "@anthropic-ai/sdk/lib/tools/BetaRunnableTool"
import type { BetaMessage } from "@anthropic-ai/sdk/resources/beta"
import { apiFailure, Failure } from "../failure"
import type { Tool } from "../tools"
import { maxTurns, parseAnswer, type Provider, type Usage } from "./provider"

const title = "Claude"

export function anthropic(client = new Anthropic()): Provider {
  return {
    name: "anthropic",
    async run(request) {
      const runner = client.beta.messages.toolRunner({
        model: request.model,
        max_tokens: 64000,
        max_iterations: maxTurns,
        stream: true,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        system: [{ type: "text", text: request.system, cache_control: { type: "ephemeral" } }],
        messages: [{ role: "user", content: request.prompt }],
        output_config: { effort: request.effort, format: betaZodOutputFormat(request.result) },
        tools: request.tools.map(runnable),
      })
      const requests: Usage[] = []
      let last: BetaMessage | undefined
      try {
        for await (const stream of runner) {
          last = await stream.finalMessage()
          requests.push({
            input: last.usage.input_tokens,
            cacheRead: last.usage.cache_read_input_tokens ?? 0,
            cacheWrite: last.usage.cache_creation_input_tokens ?? 0,
            output: last.usage.output_tokens,
          })
        }
      } catch (error) {
        throw error instanceof Anthropic.APIError ? apiFailure(title, error) : error
      }
      if (!last) throw new Failure(`${title} returned nothing.`)
      if (last.stop_reason === "refusal") throw new Failure(`${title} declined to answer.`)
      if (last.stop_reason === "max_tokens") throw new Failure(`${title}'s answer was cut off.`)
      if (last.stop_reason === "tool_use") throw new Failure(`${title} used all its turns without answering.`)
      const text = last.content.flatMap(block => block.type === "text" ? [block.text] : []).join("")
      return { result: parseAnswer(title, text, request.result), model: last.model, requests }
    },
  }
}

function runnable(tool: Tool): BetaRunnableTool<unknown> {
  return {
    name: tool.name,
    description: tool.description,
    input_schema: { type: "object", ...tool.parameters },
    strict: true,
    parse: input => input,
    run: tool.run,
  }
}
