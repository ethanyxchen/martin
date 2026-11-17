import type { z } from "zod"
import { Failure } from "../failure"
import type { Event } from "../schema"
import type { Tool } from "../tools"

export type Effort = "low" | "medium" | "high" | "xhigh"

export type Model = { anthropic: string, openai: string }

export type JobSpec<Result> = {
  system: string
  prompt: string
  tools: Tool[]
  result: z.ZodType<Result>
  model: Model
  effort: Effort
  finish: (result: Result) => Result
}

export type Usage = { requests: number, input: number, cacheRead: number, cacheWrite: number, output: number }

export type Outcome<Result> = { result: Result, usage: Usage, model: string }

export type Emit = (event: Event) => void

export interface Provider {
  run<Result>(spec: JobSpec<Result>, emit: Emit): Promise<Outcome<Result>>
}

export const maxTurns = 12

export function noUsage(): Usage {
  return { requests: 0, input: 0, cacheRead: 0, cacheWrite: 0, output: 0 }
}

export function parseAnswer<Result>(provider: string, text: string, schema: z.ZodType<Result>): Result {
  try {
    return schema.parse(JSON.parse(text))
  } catch {
    throw new Failure(`${provider}'s answer didn't have the expected shape.`)
  }
}
