import { expect, test } from "bun:test"
import { serve } from "../src/main"
import { cost } from "../src/prices"
import { fake, fakeUsage } from "../src/providers/fake"
import { folder, note, overviewJob } from "./support"

test("prints progress, then one result with its estimated cost, and exits 0", async () => {
  const kickoff = await note(await folder(), "kickoff", "We are building sharing next.")
  const answer = { now: [], next: [{ title: "Sharing", caption: "Planned after onboarding.", updated: "2026-11-01" }], shelved: [] }
  const lines: string[] = []
  const status = await serve(JSON.stringify(overviewJob({ notes: [kickoff] })), line => lines.push(line), () => fake({ calls: [[{ tool: "read_note", input: { id: "kickoff", offset: null } }]], answer }))
  expect(status).toBe(0)
  expect(lines.map(line => JSON.parse(line))).toEqual([
    { type: "progress", tool: "read_note", input: { id: "kickoff", offset: null } },
    { type: "result", result: answer, cost: cost("claude-haiku-5-5", [fakeUsage, fakeUsage]) },
  ])
})

test("leaves the cost out when the model has no price", async () => {
  const answer = { now: [], next: [], shelved: [] }
  const lines: string[] = []
  await serve(JSON.stringify(overviewJob({ provider: "openai" })), line => lines.push(line), () => fake({ calls: [], answer }, "openai"))
  expect(JSON.parse(lines[0]!)).toEqual({ type: "result", result: answer, cost: null })
})

test("prints one error and exits 1 for a malformed job", async () => {
  const lines: string[] = []
  expect(await serve('{"kind":"overview"}', line => lines.push(line))).toBe(1)
  expect(lines).toEqual([JSON.stringify({ type: "error", message: "The job was malformed." })])
})

test("prints the provider's failure as the error", async () => {
  const lines: string[] = []
  const previous = process.env.ANTHROPIC_API_KEY
  delete process.env.ANTHROPIC_API_KEY
  expect(await serve(JSON.stringify(overviewJob()), line => lines.push(line))).toBe(1)
  if (previous) process.env.ANTHROPIC_API_KEY = previous
  expect(lines).toEqual([JSON.stringify({ type: "error", message: "No Claude API key is set." })])
})
