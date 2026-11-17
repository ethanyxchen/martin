import { describe, expect, test } from "bun:test"
import { $ } from "bun"
import { join } from "node:path"
import { execute } from "../src/activity"
import { overview } from "../src/jobs/overview"
import { serve } from "../src/main"
import { fake } from "../src/providers/fake"
import type { Provider } from "../src/providers/provider"
import type { OverviewResult } from "../src/schema"
import { invariants, items, judge, material } from "../eval/judge"
import { record } from "../eval/record"
import type { Commit } from "../src/schema"
import { connect, load, projects, type PullRequest, type Rubric, state } from "../eval/scenario"
import { folder } from "./support"

const fixtures = join(import.meta.dir, "..", "fixtures")

const commit = (date: string, branch: string, subject = "Work"): Commit => ({ date, author: "Ada", email: "ada@example.com", subject, branch })
const pull = (fields: Partial<PullRequest>): PullRequest => ({
  title: "Feature", author: "ada", branch: "feature", createdAt: "2026-11-02T10:00:00Z", mergedAt: null, closedAt: null,
  additions: 10, deletions: 2, changedFiles: 1, commits: 2, ...fields,
})

describe("fixture state", () => {
  const scenario = {
    commits: [
      commit("2026-11-01T09:00:00Z", "main"),
      commit("2026-11-02T09:00:00Z", "feature"),
      commit("2026-11-03T09:00:00Z", "feature"),
      commit("2026-11-06T09:00:00Z", "feature"),
      commit("2026-11-04T09:00:00Z", "dropped"),
    ],
    pullRequests: [
      pull({ mergedAt: "2026-11-05T09:00:00Z", closedAt: "2026-11-05T09:00:00Z" }),
      pull({ title: "Dropped", branch: "dropped", createdAt: "2026-11-04T10:00:00Z", closedAt: "2026-11-05T10:00:00Z" }),
    ],
  }

  test("hides what happens after the cutoff and works out each pull request's state then", () => {
    const before = state(scenario, new Date("2026-11-03T12:00:00Z"))
    expect(before.commits).toHaveLength(3)
    expect(before.pullRequests.map(pull => [pull.title, pull.state, pull.updatedAt])).toEqual([["Feature", "OPEN", "2026-11-03T09:00:00Z"]])
    const after = state(scenario, new Date("2026-11-05T12:00:00Z"))
    expect(after.pullRequests.map(pull => [pull.title, pull.state, pull.updatedAt])).toEqual([
      ["Feature", "MERGED", "2026-11-05T09:00:00Z"],
      ["Dropped", "CLOSED", "2026-11-05T10:00:00Z"],
    ])
  })

  test("derives each branch's last commit, how far it is ahead of main, whether it merged and its pull request", () => {
    const branches = (at: string) => state(scenario, new Date(at)).branches.map(({ pullRequest, ...branch }) => ({ ...branch, pull: pullRequest && [pullRequest.title, pullRequest.state] }))
    const ada = { author: "Ada", email: "ada@example.com" }
    expect(branches("2026-11-04T12:00:00Z")).toEqual([
      { name: "feature", lastCommit: "2026-11-03T09:00:00Z", ...ada, ahead: 2, merged: false, pull: ["Feature", "OPEN"] },
      { name: "dropped", lastCommit: "2026-11-04T09:00:00Z", ...ada, ahead: 1, merged: false, pull: ["Dropped", "OPEN"] },
    ])
    expect(branches("2026-11-05T12:00:00Z")[0]).toEqual({ name: "feature", lastCommit: "2026-11-03T09:00:00Z", ...ada, ahead: 0, merged: true, pull: ["Feature", "MERGED"] })
    expect(branches("2026-11-07T12:00:00Z")[0]).toEqual({ name: "feature", lastCommit: "2026-11-06T09:00:00Z", ...ada, ahead: 1, merged: false, pull: ["Feature", "MERGED"] })
  })

  test("the agent sees only activity inside its window, in the shape git and gh give it", async () => {
    const activity = connect({ ...scenario, project: "P", owner: { name: "Ada", emails: [], login: "ada" }, repository: null, stages: [] })(
      { folder: ".", slug: "a/b" },
      { since: new Date("2026-11-02T12:00:00Z"), until: new Date("2026-11-04T12:00:00Z") },
    )
    expect(await activity.commits(0, 10)).toEqual([commit("2026-11-04T09:00:00Z", "dropped"), commit("2026-11-03T09:00:00Z", "feature")])
    const size = { additions: 10, deletions: 2, changedFiles: 1, commits: 2 }
    expect(await activity.pullRequests(10)).toEqual([
      { updatedAt: "2026-11-04T10:00:00Z", state: "OPEN", title: "Dropped", author: "ada", branch: "dropped", ...size },
      { updatedAt: "2026-11-03T09:00:00Z", state: "OPEN", title: "Feature", author: "ada", branch: "feature", ...size },
    ])
    expect((await activity.branches()).map(branch => [branch.name, branch.pullRequest?.title])).toEqual([["feature", "Feature"], ["dropped", "Dropped"]])
  })

  test("the agent's branches leave out those idle for longer than the lookback", async () => {
    const activity = connect({ ...scenario, project: "P", owner: { name: "Ada", emails: [], login: "ada" }, repository: null, stages: [] })(
      { folder: ".", slug: "a/b" },
      { since: new Date("2026-12-01T12:00:00Z"), until: new Date("2026-12-04T12:00:00Z") },
    )
    expect((await activity.branches()).map(branch => branch.name)).toEqual(["feature"])
  })
})

describe("Lumen", () => {
  test("every stage's notes exist and the completion update sits past the first page", async () => {
    const lumen = await load(join(fixtures, "lumen"))
    for (const stage of lumen.stages) for (const note of stage.notes) expect(await Bun.file(note.path).exists()).toBe(true)
    const retro = await Bun.file(join(fixtures, "lumen", "notes", "retro.md")).text()
    expect(Array.from(retro).join("").indexOf("Onboarding redesign shipped")).toBeGreaterThan(4000)
  })

  test("is found by folder or project name", async () => {
    expect((await projects(fixtures, "Lumen")).map(project => project.id)).toEqual(["lumen"])
    expect((await projects(fixtures)).map(project => project.id)).toEqual(["lumen"])
  })

  test("recorded activity follows each stage's window", async () => {
    const lumen = await load(join(fixtures, "lumen"))
    const stage = lumen.stages[1]!
    const previous = { now: [], next: [], shelved: [], readAt: lumen.stages[0]!.cutoff }
    const job = { kind: "overview" as const, provider: "anthropic" as const, project: { name: "Lumen" }, owner: lumen.scenario.owner, cutoff: stage.cutoff, previous, notes: stage.notes, repository: lumen.scenario.repository }
    const activity = overview(job, connect(lumen.scenario)).tools.find(tool => tool.name === "repo_activity")!
    const commits = await activity.run({ source: "commits", cursor: null })
    expect(commits).toContain("Prototype album invite links")
    expect(commits).not.toContain("Ship the new photo permissions prompt")
    const branches = await activity.run({ source: "branches", cursor: null })
    expect(branches).toContain("shared-albums, owner · last commit 2026-10-08 · idle 0.2 days · 1 commits ahead of main, not merged · pull request open")
  })

  test("the judge's material has the notes and the state at the cutoff", async () => {
    const lumen = await load(join(fixtures, "lumen"))
    const text = await material(lumen, lumen.stages[1]!)
    expect(text).toContain("I started on shared albums.")
    expect(text).toContain("open by me")
    expect(text).toContain("shared-albums: last commit 2026-10-08T14:00:00-07:00, 1 ahead of main, not merged")
    expect(text).not.toContain("Album feed and invite acceptance")
  })
})

const rubric: Rubric = {
  tasks: [
    { id: "albums", section: "now", caption: "invite links work", updated: "2026-10-08" },
    { id: "widget", section: "shelved", updated: "any" },
    { id: "billing", section: "absent" },
  ],
  tolerated: ["Dark mode in Next"],
  order: ["albums"],
}

const result: OverviewResult = { now: [{ title: "Shared albums", caption: "Invite links work.", updated: "2026-10-08" }], next: [], shelved: [] }

function answer(pass: (key: string) => boolean) {
  return Object.fromEntries(items(rubric).map(item => [item.key, { pass: pass(item.key), reason: `about ${item.key}` }]))
}

function counting(provider: Provider): Provider & { runs: number } {
  const counted = { ...provider, runs: 0, run: request => {
    counted.runs++
    return provider.run(request)
  } } satisfies Provider & { runs: number }
  return counted
}

describe("judge", () => {
  test("turns each rubric task into section, caption and date items, then order and precision", () => {
    expect(items(rubric).map(item => [item.key, item.kind])).toEqual([
      ["albums · section", "section"],
      ["albums · caption", "caption"],
      ["albums · date", "date"],
      ["widget · section", "section"],
      ["widget · date", "date"],
      ["billing · section", "section"],
      ["order", "order"],
      ["precision", "precision"],
    ])
    expect(items(rubric).at(-1)!.expect).toContain("- Dark mode in Next")
  })

  test("returns a verdict for every item, labelled with its kind", async () => {
    const provider = counting(fake({ calls: [], answer: answer(key => key !== "widget · section") }))
    const judgement = await judge(rubric, result, "material", provider, await folder())
    expect(provider.runs).toBe(1)
    expect(judgement.cached).toBe(false)
    expect(judgement.verdicts.filter(verdict => !verdict.pass)).toEqual([{ item: "widget · section", kind: "section", pass: false, reason: "about widget · section" }])
  })

  test("reuses a cached verdict for the same rubric and overview, and asks again when either changes", async () => {
    const cache = await folder()
    const provider = counting(fake({ calls: [], answer: answer(() => true) }))
    await judge(rubric, result, "material", provider, cache)
    const again = await judge(rubric, result, "other material", provider, cache)
    expect([provider.runs, again.cached, again.cost]).toEqual([1, true, 0])
    await judge(rubric, { ...result, next: [{ title: "Dark mode", caption: "", updated: null }] }, "material", provider, cache)
    await judge({ ...rubric, tolerated: [] }, result, "material", provider, cache)
    expect(provider.runs).toBe(3)
  })

  test("rejects an answer that skips an item", async () => {
    const { precision: _, ...partial } = answer(() => true)
    await expect(judge(rubric, result, "material", fake({ calls: [], answer: partial }), await folder())).rejects.toThrow()
  })
})

describe("invariants", () => {
  test("pass a clean overview", () => {
    expect(invariants(result, "2026-10-08T18:00:00-07:00").every(verdict => verdict.pass)).toBe(true)
  })

  test("catch sections over their limit, bad dates and references to pull requests, commits and files", () => {
    const task = (title: string, caption = "", updated: string | null = null) => ({ title, caption, updated })
    const verdicts = invariants({
      now: [task("A"), task("B"), task("C"), task("D")],
      next: [task("Albums", "Merged in #12", "2026-10-09"), task("Fix", "Reverted 3f9a2c1"), task("Editor", "Rewrote Editor.swift", "2026-13-01")],
      shelved: [],
    }, "2026-10-08T18:00:00-07:00")
    expect(verdicts.map(verdict => [verdict.item, verdict.pass])).toEqual([["section limits", false], ["valid dates", false], ["no references", false]])
    expect(verdicts[1]!.reason).toBe("“Albums” is dated 2026-10-09; “Editor” is dated 2026-13-01")
    expect(verdicts[2]!.reason).toBe("pull request number in “Albums”; commit hash in “Fix”; file name in “Editor”")
  })
})

test("record reads branches, remotes and tags, names each commit's branch and skips checkpoint refs", async () => {
  const repo = await folder()
  const author = { GIT_AUTHOR_NAME: "Ada", GIT_AUTHOR_EMAIL: "ada@example.com", GIT_COMMITTER_NAME: "Ada", GIT_COMMITTER_EMAIL: "ada@example.com" }
  const git = (...args: string[]) => $`git -C ${repo} ${args}`.env({ ...process.env, ...author }).quiet()
  await git("init", "-q", "-b", "main")
  await git("commit", "-q", "--allow-empty", "-m", "Start")
  await git("checkout", "-q", "-b", "feature")
  await git("commit", "-q", "--allow-empty", "-m", "Feature work")
  const pushed = (await git("rev-parse", "HEAD")).text().trim()
  await git("checkout", "-q", "-b", "local-idea")
  await git("commit", "-q", "--allow-empty", "-m", "Local idea")
  await git("checkout", "-q", "main")
  await git("commit", "-q", "--allow-empty", "-m", "Checkpoint")
  await git("update-ref", "refs/supaterm/checkpoint", "HEAD")
  await git("reset", "-q", "--hard", "HEAD~1")
  const pulls = [{
    title: "Feature", author: { login: "ada" }, headRefName: "ada/feature", createdAt: "2026-11-01T10:00:00Z", mergedAt: null, closedAt: null,
    additions: 5, deletions: 1, changedFiles: 2, commits: [{ oid: pushed }],
  }]
  const run = async (argv: string[]) => argv[0] === "gh" ? JSON.stringify(pulls) : execute(argv)
  const recorded = await record(repo, "a/b", new Date("2000-01-01T00:00:00Z"), new Date(Date.now() + 60_000), run)
  expect(recorded.commits.map(commit => [commit.subject, commit.branch, commit.author, commit.email]).toSorted()).toEqual([
    ["Feature work", "ada/feature", "Ada", "ada@example.com"],
    ["Local idea", "local-idea", "Ada", "ada@example.com"],
    ["Start", "main", "Ada", "ada@example.com"],
  ])
  expect(recorded.pullRequests).toEqual([{ title: "Feature", createdAt: "2026-11-01T10:00:00Z", mergedAt: null, closedAt: null, additions: 5, deletions: 1, changedFiles: 2, author: "ada", branch: "ada/feature", commits: 1 }])
})

test("the sample job is valid", async () => {
  const lines: string[] = []
  const job = await Bun.file(join(fixtures, "sample", "job.json")).text()
  expect(await serve(job, line => lines.push(line), () => fake({ calls: [], answer: { now: [], next: [], shelved: [] } }))).toBe(0)
})
