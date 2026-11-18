import { describe, expect, test } from "bun:test"
import { $ } from "bun"
import { join } from "node:path"
import { execute } from "../src/activity"
import { overview } from "../src/jobs/overview"
import { serve } from "../src/main"
import { fake } from "../src/providers/fake"
import type { Provider } from "../src/providers/provider"
import type { OverviewResult } from "../src/schema"
import { invariants, items, judge, material, scored } from "../eval/judge"
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
    tags: [{ name: "v1.0.0", date: "2026-11-03T12:00:00Z" }, { name: "v1.1.0", date: "2026-11-06T12:00:00Z" }],
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

  test("the agent sees the releases tagged by the cutoff and searches every word in titles and subjects", async () => {
    const activity = connect({ ...scenario, project: "P", owner: { name: "Ada", emails: [], login: "ada" }, repository: null, stages: [] })(
      { folder: ".", slug: "a/b" },
      { since: new Date("2026-11-05T00:00:00Z"), until: new Date("2026-11-05T12:00:00Z") },
    )
    expect(await activity.releases()).toEqual([{ name: "v1.0.0", date: "2026-11-03T12:00:00Z" }])
    const found = await activity.search(["DROPPED"])
    expect([found.commits, found.pullRequests.map(pull => pull.title)]).toEqual([[], ["Dropped"]])
    expect((await activity.search(["work"])).commits).toHaveLength(4)
    expect((await activity.search(["work", "missing"])).commits).toEqual([])
  })

  test("the agent's search reaches back past its window but not past the search lookback", async () => {
    const activity = connect({ ...scenario, project: "P", owner: { name: "Ada", emails: [], login: "ada" }, repository: null, stages: [] })
    const window = (until: string) => ({ since: new Date(until), until: new Date(until) })
    expect((await activity({ folder: ".", slug: "a/b" }, window("2026-12-20T00:00:00Z")).search(["work"])).commits).toHaveLength(5)
    expect((await activity({ folder: ".", slug: "a/b" }, window("2027-01-31T09:00:00Z")).search(["work"])).commits).toHaveLength(4)
  })

  test("the agent's branches leave out those idle for longer than the lookback", async () => {
    const activity = connect({ ...scenario, project: "P", owner: { name: "Ada", emails: [], login: "ada" }, repository: null, stages: [] })(
      { folder: ".", slug: "a/b" },
      { since: new Date("2026-12-01T12:00:00Z"), until: new Date("2026-12-04T12:00:00Z") },
    )
    expect((await activity.branches()).map(branch => branch.name)).toEqual(["feature"])
  })
})

test("every project's notes exist and no commit comes from a checkpoint ref", async () => {
  for (const project of await projects(fixtures)) {
    for (const stage of project.stages) for (const note of stage.notes) expect(await Bun.file(note.path).exists()).toBe(true)
    expect(project.scenario.commits.filter(commit => commit.branch.startsWith("refs/"))).toEqual([])
  }
})

describe("Tandem", () => {
  test("once 2.4 has shipped, the releases show it and only a search reaches the 2.3 fix", async () => {
    const tandem = await load(join(fixtures, "tandem"))
    const stage = tandem.stages.at(-1)!
    const job = { kind: "overview" as const, provider: "anthropic" as const, project: { name: "Tandem" }, owner: tandem.scenario.owner, cutoff: stage.cutoff, previous: null, notes: stage.notes, repository: tandem.scenario.repository }
    const tools = overview(job, connect(tandem.scenario)).tools
    const run = (name: string, input: unknown) => tools.find(tool => tool.name === name)!.run(input)
    expect(await run("repo_activity", { source: "releases", cursor: null })).toBe("versions: 2.4.1 on 2026-11-20, 2.4.0 on 2026-11-18, 2.4.0-rc.2 on 2026-11-13, 2.4.0-rc.1 on 2026-11-12, 2.3.1 on 2026-10-29, 2.3.0 on 2026-10-21")
    expect(await run("repo_activity", { source: "commits", cursor: null })).not.toContain("typed during the call")
    expect(await run("repo_search", { query: "typed notes" })).toContain("merged by owner, branch maya/summary-typed-notes")
  })
})

describe("Lumen", () => {
  test("the shelving update sits past the first page", async () => {
    const retro = await Bun.file(join(fixtures, "lumen", "notes", "retro.md")).text()
    expect(Array.from(retro).join("").indexOf("The home screen widget: I'm pausing")).toBeGreaterThan(4000)
  })

  test("is found by folder or project name", async () => {
    expect((await projects(fixtures, "Lumen")).map(project => project.id)).toEqual(["lumen"])
    expect((await projects(fixtures)).map(project => project.id).toSorted()).toEqual(["interviews", "lumen", "martin", "tandem"])
  })

  test("recorded activity follows each stage's window", async () => {
    const lumen = await load(join(fixtures, "lumen"))
    const stage = lumen.stages[1]!
    const previous = { now: [], next: [], shelved: [], readAt: lumen.stages[0]!.cutoff }
    const job = { kind: "overview" as const, provider: "anthropic" as const, project: { name: "Lumen" }, owner: lumen.scenario.owner, cutoff: stage.cutoff, previous, notes: stage.notes, repository: lumen.scenario.repository }
    const activity = overview(job, connect(lumen.scenario)).tools.find(tool => tool.name === "repo_activity")!
    const commits = await activity.run({ source: "commits", cursor: null })
    expect(commits).toContain("Prototype album invite links")
    expect(commits).not.toContain("Album feed")
    const branches = await activity.run({ source: "branches", cursor: null })
    expect(branches).toContain("shared-albums, owner · last commit 2026-10-08 · idle 0.2 days · 1 commits ahead of main, not merged")
    expect(branches).toContain("priya/payments-provider, praman · last commit 2026-10-07 · idle 1.3 days · merged")
  })

  test("the judge's material has the notes and the state at the cutoff", async () => {
    const lumen = await load(join(fixtures, "lumen"))
    const text = await material(lumen, lumen.stages[1]!)
    expect(text).toContain("Shared albums: invite links first, then the album feed.")
    expect(text).toContain("open by nbrennan")
    expect(text).toContain("shared-albums: last commit 2026-10-08T14:00:00-07:00, 1 ahead of main, not merged")
    expect(text).not.toContain("Accept an album invite")
  })

  test("the judge's material lists the releases tagged by the cutoff", async () => {
    const tandem = await load(join(fixtures, "tandem"))
    const text = await material(tandem, tandem.stages.at(-1)!)
    expect(text).toContain("Releases:\n- v2.3.0: 2026-10-21T16:00:00Z")
    expect(text).toContain("- v2.4.1: 2026-11-20T14:00:00Z")
    expect(await material(tandem, tandem.stages[0]!)).not.toContain("v2.4.0")
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
  test("are left out of the score", () => {
    const verdict = (kind: "section" | "invariant", pass: boolean) => ({ item: kind, kind, pass, reason: "" })
    const verdicts = [verdict("section", true), verdict("section", false), verdict("invariant", true), verdict("invariant", true)]
    expect(scored(verdicts).map(item => [item.kind, item.pass])).toEqual([["section", true], ["section", false]])
  })

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
    additions: 5, deletions: 1, changedFiles: 2, commits: 1, oids: [pushed],
  }, {
    title: "Later", author: { login: "ada" }, headRefName: "ada/later", createdAt: new Date(Date.now() + 3_600_000).toISOString(), mergedAt: null, closedAt: null,
    additions: 1, deletions: 0, changedFiles: 1, commits: 1, oids: [],
  }]
  const run = async (argv: string[]) => argv[0] === "gh" ? pulls.map(pull => JSON.stringify(pull)).join("\n") : execute(argv)
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
