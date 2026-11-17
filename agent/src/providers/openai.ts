import OpenAI from "openai"
import { zodTextFormat } from "openai/helpers/zod"
import type { Response, ResponseFunctionToolCall, ResponseInputItem } from "openai/resources/responses/responses"
import { apiFailure, Failure } from "../failure"
import type { Tool } from "../tools"
import { maxTurns, parseAnswer, type Provider, type Usage } from "./provider"

const title = "OpenAI"

export function openai(client = new OpenAI()): Provider {
  return {
    name: "openai",
    async run(request) {
      const requests: Usage[] = []
      const parameters = {
        model: request.model,
        instructions: request.system,
        reasoning: { effort: request.effort },
        text: { format: zodTextFormat(request.result, "result") },
        tools: request.tools.map(tool => ({ type: "function" as const, name: tool.name, description: tool.description, parameters: tool.parameters, strict: true })),
      }
      async function create(input: string | ResponseInputItem[], previous?: string): Promise<Response> {
        try {
          const response = await client.responses.create({ ...parameters, input, previous_response_id: previous })
          requests.push(usage(response))
          return response
        } catch (error) {
          throw error instanceof OpenAI.APIError ? apiFailure(title, error) : error
        }
      }
      let response = await create(request.prompt)
      for (let turn = 1; ; turn++) {
        const calls = response.output.filter((item): item is ResponseFunctionToolCall => item.type === "function_call")
        if (!calls.length) break
        if (turn >= maxTurns) throw new Failure(`${title} used all its turns without answering.`)
        const outputs = await Promise.all(calls.map(async call => ({
          type: "function_call_output" as const,
          call_id: call.call_id,
          output: await invoke(request.tools, call),
        })))
        response = await create(outputs, response.id)
      }
      if (response.status === "incomplete") throw new Failure(`${title}'s answer was cut off.`)
      const refused = response.output.some(item => item.type === "message" && item.content.some(part => part.type === "refusal"))
      if (refused) throw new Failure(`${title} declined to answer.`)
      return { result: parseAnswer(title, response.output_text, request.result), model: response.model, requests }
    },
  }
}

async function invoke(tools: Tool[], call: ResponseFunctionToolCall): Promise<string> {
  const tool = tools.find(tool => tool.name === call.name)
  if (!tool) return `There is no tool named ${call.name}.`
  let input: unknown
  try {
    input = JSON.parse(call.arguments)
  } catch {
    return "The tool input wasn't valid JSON."
  }
  return tool.run(input)
}

function usage(response: Response): Usage {
  const cached = response.usage?.input_tokens_details?.cached_tokens ?? 0
  return {
    input: (response.usage?.input_tokens ?? 0) - cached,
    cacheRead: cached,
    cacheWrite: 0,
    output: response.usage?.output_tokens ?? 0,
  }
}
