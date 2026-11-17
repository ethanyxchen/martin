import OpenAI from "openai"
import { zodTextFormat } from "openai/helpers/zod"
import type { Response, ResponseFunctionToolCall, ResponseInputItem } from "openai/resources/responses/responses"
import { z } from "zod"
import { apiFailure, Failure } from "../failure"
import type { Tool } from "../tools"
import { type Emit, maxTurns, noUsage, parseAnswer, type Provider, type Usage } from "./provider"

const name = "OpenAI"

export function openai(client = new OpenAI()): Provider {
  return {
    async run(spec, emit) {
      const usage = noUsage()
      const request = {
        model: spec.model.openai,
        instructions: spec.system,
        reasoning: { effort: spec.effort },
        text: { format: zodTextFormat(spec.result, "result") },
        tools: spec.tools.map(tool => ({ type: "function" as const, name: tool.name, description: tool.description, parameters: parameters(tool.input), strict: true })),
      }
      async function create(input: string | ResponseInputItem[], previous?: string): Promise<Response> {
        try {
          const response = await client.responses.create({ ...request, input, previous_response_id: previous })
          count(usage, response)
          return response
        } catch (error) {
          throw error instanceof OpenAI.APIError ? apiFailure(name, error) : error
        }
      }
      let response = await create(spec.prompt)
      for (let turn = 1; ; turn++) {
        const calls = response.output.filter((item): item is ResponseFunctionToolCall => item.type === "function_call")
        if (!calls.length) break
        if (turn >= maxTurns) throw new Failure(`${name} used all its turns without answering.`)
        const outputs = await Promise.all(calls.map(async call => ({
          type: "function_call_output" as const,
          call_id: call.call_id,
          output: await invoke(spec.tools, call, emit),
        })))
        response = await create(outputs, response.id)
      }
      if (response.status === "incomplete") throw new Failure(`${name}'s answer was cut off.`)
      const refused = response.output.some(item => item.type === "message" && item.content.some(part => part.type === "refusal"))
      if (refused) throw new Failure(`${name} declined to answer.`)
      return { result: parseAnswer(name, response.output_text, spec.result), usage, model: response.model }
    },
  }
}

function parameters(schema: z.ZodObject): Record<string, unknown> {
  const { $schema: _, ...rest } = z.toJSONSchema(schema)
  return rest
}

async function invoke(tools: Tool[], call: ResponseFunctionToolCall, emit: Emit): Promise<string> {
  const tool = tools.find(tool => tool.name === call.name)
  if (!tool) return `There is no tool named ${call.name}.`
  let input: unknown
  try {
    input = JSON.parse(call.arguments)
  } catch {
    return "The tool input wasn't valid JSON."
  }
  const parsed = tool.input.safeParse(input)
  if (!parsed.success) return `Invalid input: ${parsed.error.message}`
  emit({ type: "progress", tool: tool.name, input: parsed.data })
  return tool.run(parsed.data)
}

function count(usage: Usage, response: Response) {
  const cached = response.usage?.input_tokens_details?.cached_tokens ?? 0
  usage.requests += 1
  usage.input += (response.usage?.input_tokens ?? 0) - cached
  usage.cacheRead += cached
  usage.output += response.usage?.output_tokens ?? 0
}
