import type { ProviderName } from "../schema"
import type { Provider } from "./provider"

export type Script = { calls: { tool: string, input: unknown }[][], answer: unknown }

export const fakeUsage = { input: 1000, cacheRead: 0, cacheWrite: 0, output: 100 }

export function fake(script: Script, name: ProviderName = "anthropic"): Provider {
  return {
    name,
    async run(request) {
      for (const round of script.calls) {
        await Promise.all(round.map(call => {
          const tool = request.tools.find(tool => tool.name === call.tool)
          if (!tool) throw new Error(`No tool ${call.tool}`)
          return tool.run(call.input)
        }))
      }
      const requests = Array.from({ length: script.calls.length + 1 }, () => fakeUsage)
      return { result: request.result.parse(script.answer), model: request.model, requests }
    },
  }
}
