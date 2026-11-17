import { noUsage, type Provider } from "./provider"

export type Script = { calls: { tool: string, input: unknown }[][], answer: unknown }

export function fake(script: Script): Provider {
  return {
    async run(spec, emit) {
      for (const round of script.calls) {
        await Promise.all(round.map(call => {
          const tool = spec.tools.find(tool => tool.name === call.tool)
          if (!tool) throw new Error(`No tool ${call.tool}`)
          const input = tool.input.parse(call.input)
          emit({ type: "progress", tool: tool.name, input })
          return tool.run(input)
        }))
      }
      return { result: spec.result.parse(script.answer), usage: { ...noUsage(), requests: script.calls.length + 1 }, model: "fake" }
    },
  }
}
