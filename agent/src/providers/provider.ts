import type { z } from "zod"
import { Failure } from "../failure"
import type { ProviderName } from "../schema"
import type { Tool } from "../tools"

export type Effort = "low" | "medium" | "high" | "xhigh"

export type Request<Result> = {
  system: string
  prompt: string
  tools: Tool[]
  result: z.ZodType<Result>
  model: string
  effort: Effort
}

export type Usage = { input: number, cacheRead: number, cacheWrite: number, output: number }

export type Outcome<Result> = { result: Result, model: string, requests: Usage[] }

export interface Provider {
  name: ProviderName
  run<Result>(request: Request<Result>): Promise<Outcome<Result>>
}

export const maxTurns = 12

export function parseAnswer<Result>(provider: string, text: string, schema: z.ZodType<Result>): Result {
  try {
    return schema.parse(JSON.parse(text))
  } catch {
    throw new Failure(`${provider}'s answer didn't have the expected shape.`)
  }
}
