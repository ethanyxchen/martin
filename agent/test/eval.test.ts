import { expect, test } from "bun:test"
import { join } from "node:path"
import { check, fixtures, local } from "../eval/stages"
import { overview } from "../src/jobs/overview"
import { serve } from "../src/main"
import { fake } from "../src/providers/fake"

const tracking = join(import.meta.dir, "..", "fixtures", "tracking")

test("every tracking stage's notes exist and the completion update sits past the first page", async () => {
  const suite = await fixtures(tracking)
  for (const stage of suite.stages) for (const note of stage.notes) expect(await Bun.file(note.path).exists()).toBe(true)
  const retro = await Bun.file(join(tracking, "notes", "retro.md")).text()
  expect(Array.from(retro).join("").indexOf("Onboarding redesign shipped")).toBeGreaterThan(4000)
})

test("recorded activity follows each stage's window", async () => {
  const suite = await fixtures(tracking)
  const stage = suite.stages[1]!
  const previous = { now: [], next: [], shelved: [], readAt: suite.stages[0]!.cutoff }
  const job = { kind: "overview" as const, provider: "anthropic" as const, project: { name: suite.project }, cutoff: stage.cutoff, previous, notes: stage.notes, repository: suite.repository }
  const activity = overview(job, suite.connect).tools.find(tool => tool.name === "repo_activity")!
  const commits = await activity.run({ source: "commits", cursor: null })
  expect(commits).toContain("Prototype album invite links")
  expect(commits).not.toContain("Ship the new photo permissions prompt")
})

test("checks match titles by section and treat missing tasks as absent", () => {
  const result = { now: [{ title: "Shared albums", caption: "", updated: null }], next: [], shelved: [{ title: "Home widget", caption: "", updated: null }] }
  const checks = check(result, [
    { task: "albums", pattern: "album", in: "now" },
    { task: "widget", pattern: "widget", in: "now" },
    { task: "onboarding", pattern: "onboard", in: "absent" },
  ])
  expect(checks.map(item => [item.found, item.pass])).toEqual([["now", true], ["shelved", false], ["absent", true]])
})

test("formats local timestamps with their offset", () => {
  expect(local(new Date("2026-11-18T04:00:00Z"))).toMatch(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/)
})

test("the sample job is valid", async () => {
  const lines: string[] = []
  const job = await Bun.file(join(import.meta.dir, "..", "fixtures", "sample", "job.json")).text()
  expect(await serve(job, line => lines.push(line), () => fake({ calls: [], answer: { now: [], next: [], shelved: [] } }))).toBe(0)
})
