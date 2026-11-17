import Anthropic from "@anthropic-ai/sdk"
import { betaZodOutputFormat, betaZodTool } from "@anthropic-ai/sdk/helpers/beta/zod"
import type { BetaMessage } from "@anthropic-ai/sdk/resources/beta"
import { apiFailure, Failure } from "../failure"
import { maxTurns, noUsage, parseAnswer, type Provider } from "./provider"

const name = "Claude"

export function anthropic(client = new Anthropic()): Provider {
  return {
    async run(spec, emit) {
      const runner = client.beta.messages.toolRunner({
        model: spec.model.anthropic,
        max_tokens: 64000,
        max_iterations: maxTurns,
        stream: true,
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        system: [{ type: "text", text: spec.system, cache_control: { type: "ephemeral" } }],
        messages: [{ role: "user", content: spec.prompt }],
        output_config: { effort: spec.effort, format: betaZodOutputFormat(spec.result) },
        tools: spec.tools.map(tool => betaZodTool({
          name: tool.name,
          description: tool.description,
          inputSchema: tool.input,
          strict: true,
          run: input => {
            emit({ type: "progress", tool: tool.name, input })
            return tool.run(input)
          },
        })),
      })
      const usage = noUsage()
      let last: BetaMessage | undefined
      try {
        for await (const stream of runner) {
          last = await stream.finalMessage()
          usage.requests += 1
          usage.input += last.usage.input_tokens
          usage.cacheRead += last.usage.cache_read_input_tokens ?? 0
          usage.cacheWrite += last.usage.cache_creation_input_tokens ?? 0
          usage.output += last.usage.output_tokens
        }
      } catch (error) {
        throw error instanceof Anthropic.APIError ? apiFailure(name, error) : error
      }
      if (!last) throw new Failure(`${name} returned nothing.`)
      if (last.stop_reason === "refusal") throw new Failure(`${name} declined to answer.`)
      if (last.stop_reason === "max_tokens") throw new Failure(`${name}'s answer was cut off.`)
      if (last.stop_reason === "tool_use") throw new Failure(`${name} used all its turns without answering.`)
      const text = last.content.flatMap(block => block.type === "text" ? [block.text] : []).join("")
      return { result: parseAnswer(name, text, spec.result), usage, model: last.model }
    },
  }
}
