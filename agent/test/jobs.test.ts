import { describe, expect, test } from "bun:test"
import { overview, prompt as overviewPrompt, system } from "../src/jobs/overview"
import { prompt as lookupPrompt, repositoryLookup } from "../src/jobs/repositoryLookup"
import type { LookupJob } from "../src/schema"
import { folder, note, overviewJob } from "./support"

const task = (title: string, updated: string | null = null) => ({ title, caption: "Where it stands.", updated })

describe("overview job", () => {
  test("takes today from the cutoff's own offset", () => {
    expect(overviewPrompt(overviewJob({ cutoff: "2026-11-17T20:00:00-08:00" }))).toContain("Today: 2026-11-17")
  })

  test("lists the previous overview and marks older notes edited since it", async () => {
    const directory = await folder()
    const old = await note(directory, "old", "", { changedAt: "2026-11-15T10:00:00-08:00" })
    const untouched = await note(directory, "untouched", "")
    const previous = { now: [task("Launch beta", "2026-11-09")], next: [], shelved: [], readAt: "2026-11-10T10:00:00-08:00" }
    const text = overviewPrompt(overviewJob({ previous, notes: [old, untouched] }))
    expect(text).toContain("- Launch beta · 2026-11-09 · Where it stands.")
    expect(text).toContain("- old · Note old · meeting 2026-11-01 · edited 2026-11-15 · new since last read")
    expect(text).toContain("- untouched · Note untouched · meeting 2026-11-01 · edited 2026-11-01\n")
  })

  test("keeps the system prompt identical across jobs so it can be cached", () => {
    expect(overview(overviewJob({ cutoff: "2026-11-01T09:00:00Z" })).system).toBe(system)
    expect(overview(overviewJob({ cutoff: "2026-12-01T09:00:00Z", project: { name: "Other" } })).system).toBe(system)
  })

  test("trims, caps and drops future or invalid dates", () => {
    const spec = overview(overviewJob())
    const result = spec.finish({
      now: [task(" " + "t".repeat(100)), task("Two", "2026-11-18"), task("Three", "2026-11-17"), task("Four")],
      next: [task("  "), task("Five", "soon")],
      shelved: [],
    })
    expect(result.now.map(item => item.title)).toEqual(["t".repeat(80), "Two", "Three"])
    expect(result.now.map(item => item.updated)).toEqual([null, null, "2026-11-17"])
    expect(result.next).toEqual([task("Five")])
  })

  test("fails instead of finishing when a source stayed unreadable", async () => {
    const missing = { ...(await note(await folder(), "a", "")), path: "/nonexistent/a.md" }
    const spec = overview(overviewJob({ notes: [missing] }))
    await spec.tools[0]?.run({ id: "a", offset: null })
    expect(() => spec.finish({ now: [], next: [], shelved: [] })).toThrow("Couldn't read note “Note a”.")
  })

  test("offers repository activity only when a repository is linked", () => {
    expect(overview(overviewJob()).tools.map(tool => tool.name)).toEqual(["read_note"])
    expect(overview(overviewJob({ repository: { folder: "/tmp", slug: "ann/lumen" } })).tools.map(tool => tool.name)).toEqual(["read_note", "repo_activity"])
  })
})

describe("repository lookup job", () => {
  const job = (notes: LookupJob["notes"]): LookupJob => ({
    kind: "repositoryLookup",
    provider: "anthropic",
    project: { name: "Lumen" },
    notes,
    candidates: [{ slug: "ann/lumen", summary: "A photo app" }, { slug: "ann/dots", summary: null }],
  })

  test("cuts note excerpts and lists candidates", async () => {
    const directory = await folder()
    const long = await note(directory, "a", "z".repeat(700))
    const spec = await repositoryLookup(job([{ title: "Kickoff", path: long.path }]))
    expect(spec.prompt).toContain(`# Kickoff\n${"z".repeat(600)}\n`)
    expect(spec.prompt).toContain("Repositories:\nann/lumen: A photo app\nann/dots")
  })

  test("says there are no notes", () => {
    expect(lookupPrompt(job([]), [])).toContain("Notes:\nNo notes yet.")
  })

  test("lowercases slugs and treats more than three as no answer", async () => {
    const spec = await repositoryLookup(job([]))
    expect(spec.finish({ evidence: "", slugs: ["Ann/Lumen"] }).slugs).toEqual(["ann/lumen"])
    expect(spec.finish({ evidence: "", slugs: ["a/a", "b/b", "c/c", "d/d"] }).slugs).toEqual([])
  })
})
