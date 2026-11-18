import { describe, expect, test } from "bun:test"
import { $ } from "bun"
import { join } from "node:path"
import { type Activity, type Branch, execute, github, type PullRequest, type Release } from "../src/activity"
import type { Commit } from "../src/schema"
import { commitBatch, ownership, pageLength, pullRequestLimit, readNote, repoActivity, repoSearch, Sources, tracks } from "../src/tools"
import { folder, note } from "./support"

describe("read_note", () => {
  test("refuses ids that are not in the job", async () => {
    const tool = readNote([await note(await folder(), "a", "text")], new Sources())
    expect(await tool.run({ id: "b", offset: null })).toBe("There is no note with id b.")
  })

  test("pages long notes and reaches text past the first page", async () => {
    const text = "x".repeat(pageLength) + "Shipped onboarding."
    const tool = readNote([await note(await folder(), "a", text)], new Sources())
    const first = await tool.run({ id: "a", offset: null })
    expect(first).toContain(`characters 0–${pageLength} of ${pageLength + 19}`)
    expect(first).toContain(`Next offset: ${pageLength}.`)
    expect(first).not.toContain("Shipped")
    const second = await tool.run({ id: "a", offset: pageLength })
    expect(second).toContain("Shipped onboarding.")
    expect(second).toContain("End of note.")
  })

  test("counts offsets by code point", async () => {
    const text = "🙂".repeat(pageLength + 1)
    const tool = readNote([await note(await folder(), "a", text)], new Sources())
    const first = await tool.run({ id: "a", offset: 0 })
    expect(first).toContain(`of ${pageLength + 1}`)
    expect(await tool.run({ id: "a", offset: pageLength })).toContain(`characters ${pageLength}–${pageLength + 1}`)
  })

  test("validates its own input and describes what was wrong", async () => {
    const tool = readNote([await note(await folder(), "a", "text")], new Sources())
    expect(await tool.run({ id: 3 })).toStartWith("Invalid input:")
    expect(tool.parameters).toMatchObject({ type: "object", required: ["id", "offset"], additionalProperties: false })
  })

  test("refuses offsets that are not whole, nonnegative numbers", async () => {
    const tool = readNote([await note(await folder(), "a", "text")], new Sources())
    expect(await tool.run({ id: "a", offset: -1 })).toBe("The offset must be a whole number of characters, at least 0.")
    expect(await tool.run({ id: "a", offset: 1.5 })).toBe("The offset must be a whole number of characters, at least 0.")
  })

  test("reports a page it already returned", async () => {
    const tool = readNote([await note(await folder(), "a", "short")], new Sources())
    await tool.run({ id: "a", offset: null })
    expect(await tool.run({ id: "a", offset: 0 })).toBe("You already read note a, characters 0–5 of 5. End of note.")
  })

  test("records an unreadable note as unresolved", async () => {
    const sources = new Sources()
    const missing = { ...(await note(await folder(), "a", "")), path: "/nonexistent/a.md" }
    const tool = readNote([missing], sources)
    expect(await tool.run({ id: "a", offset: null })).toBe("Note a couldn't be read.")
    expect(sources.unresolved).toEqual(["note “Note a”"])
  })
})

describe("repo_activity", () => {
  const owner = { name: "Ada Park", emails: ["ada@work.com", "ada@home.com"], login: "ada" }
  const context = { owner, cutoff: "2026-11-16T18:00:00-08:00" }
  const pull = (fields: Partial<PullRequest> = {}): PullRequest => ({
    updatedAt: "2026-11-10T10:00:00Z", state: "OPEN", title: "Change", author: "ada", branch: "change", additions: 900, deletions: 40, changedFiles: 12, commits: 5, ...fields,
  })

  function recorded(commits: Commit[], fail = false, branches: Branch[] = [], releases: Release[] = []): Activity {
    return {
      commits: async (skip, count) => {
        if (fail) throw new Error("git failed")
        return commits.slice(skip, skip + count)
      },
      pullRequests: async limit => Array.from({ length: Math.min(limit, 40) }, (_, index) => pull({ title: `Change ${index}`, author: "priya" })),
      branches: async () => {
        if (fail) throw new Error("git failed")
        return branches
      },
      releases: async () => {
        if (fail) throw new Error("git failed")
        return releases
      },
      search: async words => {
        if (fail) throw new Error("gh failed")
        const match = (text: string) => words.every(word => text.toLowerCase().includes(word.toLowerCase()))
        return { commits: commits.filter(commit => match(commit.subject)), pullRequests: [pull({ state: "MERGED", title: "Typed notes in summaries" })].filter(pull => match(pull.title)) }
      },
    }
  }

  test("pages through every commit without gaps", async () => {
    const commits = Array.from({ length: commitBatch * 2 + 5 }, (_, index) => ({ date: "2026-11-10T10:00:00Z", author: "Ann", email: "ann@example.com", subject: `Commit ${index} ${"y".repeat(60)}`, branch: "main" }))
    const tool = repoActivity(recorded(commits), context, new Sources())
    const seen: string[] = []
    let cursor: string | null = null
    for (;;) {
      const page: string = await tool.run({ source: "commits", cursor })
      seen.push(...page.split("\n").filter(line => line.startsWith("2026")))
      const next = page.match(/Next cursor: (\w+)\./)
      if (!next) break
      cursor = next[1] ?? null
    }
    expect(seen.length).toBe(commits.length)
    expect(seen.at(-1)).toContain(`Commit ${commits.length - 1} `)
  })

  test("refuses cursors it did not issue", async () => {
    const tool = repoActivity(recorded([]), context, new Sources())
    expect(await tool.run({ source: "commits", cursor: "made-up" })).toContain("Unknown cursor made-up")
  })

  test("tells an empty window apart from a failed read", async () => {
    const sources = new Sources()
    expect(await repoActivity(recorded([]), context, sources).run({ source: "commits", cursor: null })).toBe("No commits in this window.")
    expect(sources.unresolved).toEqual([])
    expect(await repoActivity(recorded([], true), context, sources).run({ source: "commits", cursor: null })).toBe("The repository's commits couldn't be read.")
    expect(sources.unresolved).toEqual(["the repository's commits"])
  })

  test("says when the pull request cap was reached", async () => {
    const page = await repoActivity(recorded([]), context, new Sources()).run({ source: "pullRequests", cursor: null })
    expect(page).toContain("2026-11-10 open by priya, branch change, +900 −40 in 12 files, 5 commits: Change 0")
    expect(page).toContain(`The cap of ${pullRequestLimit} was reached`)
  })

  test("marks the owner's commits by name or email and names each commit's branch", async () => {
    const commits = [
      { date: "2026-11-10T10:00:00Z", author: "ada park", email: "ada@ci.com", subject: "By name", branch: "main" },
      { date: "2026-11-09T10:00:00Z", author: "A. Park", email: "Ada@Home.com", subject: "By email", branch: "ada/editor" },
      { date: "2026-11-08T10:00:00Z", author: "Priya", email: "priya@work.com", subject: "Someone else", branch: "priya/billing" },
    ]
    expect(await repoActivity(recorded(commits), context, new Sources()).run({ source: "commits", cursor: null })).toBe([
      "2026-11-10 on main, owner: By name",
      "2026-11-09 on ada/editor, owner: By email",
      "2026-11-08 on priya/billing, Priya <priya@work.com>: Someone else",
      "End of commits.",
    ].join("\n"))
  })

  test("lists branches newest first with idle days, staleness, merge state and pull request", async () => {
    const branch = (fields: Partial<Branch>): Branch => ({ name: "b", lastCommit: "2026-11-16T09:00:00-08:00", author: "Ada Park", email: "ada@work.com", ahead: 3, merged: false, pullRequest: null, ...fields })
    const branches = [
      branch({ name: "ada/old-idea", lastCommit: "2026-11-13T18:00:00-08:00" }),
      branch({ name: "ada/editor", pullRequest: pull({ branch: "ada/editor", title: "Rebuild the editor" }) }),
      branch({ name: "ada/shipped", lastCommit: "2026-11-02T10:00:00-08:00", ahead: 0, merged: true, pullRequest: pull({ state: "MERGED", title: "Ship it" }) }),
      branch({ name: "priya/billing", lastCommit: "2026-11-15T12:00:00-08:00", author: "Priya", email: "priya@work.com", pullRequest: pull({ author: "priya", title: "Billing" }) }),
    ]
    expect(await repoActivity(recorded([], false, branches), context, new Sources()).run({ source: "branches", cursor: null })).toBe([
      "ada/editor, owner · last commit 2026-11-16 · idle 0.4 days · 3 commits ahead of main, not merged · pull request open, +900 −40 in 12 files, 5 commits: Rebuild the editor",
      "priya/billing, priya · last commit 2026-11-15 · idle 1.0 days · 3 commits ahead of main, not merged · pull request open, +900 −40 in 12 files, 5 commits: Billing",
      "ada/old-idea, owner · last commit 2026-11-13 · idle 2.0 days, stale · 3 commits ahead of main, not merged · no pull request",
      "ada/shipped, owner · last commit 2026-11-02 · idle 12.3 days · merged · pull request merged, +900 −40 in 12 files, 5 commits: Ship it",
    ].join("\n"))
  })

  test("groups versions into release tracks, newest first, each version dated by its first ref", async () => {
    const releases = [
      { name: "desktop-stable-1.0.40", date: "2026-11-11T10:00:00Z" },
      { name: "desktop-stable-1.0.42", date: "2026-11-17T10:00:00Z" },
      { name: "desktop-latest-1.0.42-t20261113091246.latest", date: "2026-11-13T09:12:00Z" },
      { name: "desktop-latest-1.0.42-t20261116091246.latest", date: "2026-11-16T09:12:00Z" },
      { name: "release/desktop/1.0.44", date: "2026-11-18T08:00:00Z" },
      { name: "v2.4.0-rc.1", date: "2026-11-12T17:00:00Z" },
      { name: "nemotron-apple", date: "2026-11-18T09:00:00Z" },
    ]
    expect(tracks(releases)).toEqual([
      { track: "release/desktop", versions: [{ version: "1.0.44", date: "2026-11-18T08:00:00Z" }] },
      { track: "desktop-stable", versions: [{ version: "1.0.42", date: "2026-11-17T10:00:00Z" }, { version: "1.0.40", date: "2026-11-11T10:00:00Z" }] },
      { track: "desktop-latest", versions: [{ version: "1.0.42", date: "2026-11-13T09:12:00Z" }] },
      { track: "versions", versions: [{ version: "2.4.0-rc.1", date: "2026-11-12T17:00:00Z" }] },
    ])
  })

  test("lists each release track's latest versions and counts the older ones", async () => {
    const releases = Array.from({ length: 8 }, (_, index) => ({ name: `v1.${index}.0`, date: `2026-11-0${index + 1}T10:00:00Z` }))
    expect(await repoActivity(recorded([], false, [], releases), context, new Sources()).run({ source: "releases", cursor: null }))
      .toBe("versions: 1.7.0 on 2026-11-08, 1.6.0 on 2026-11-07, 1.5.0 on 2026-11-06, 1.4.0 on 2026-11-05, 1.3.0 on 2026-11-04, 1.2.0 on 2026-11-03, and 2 older")
    expect(await repoActivity(recorded([]), context, new Sources()).run({ source: "releases", cursor: null })).toBe("No tag or release branch names a version.")
  })

  test("records unreadable releases as unresolved", async () => {
    const sources = new Sources()
    expect(await repoActivity(recorded([], true), context, sources).run({ source: "releases", cursor: null })).toBe("The repository's releases couldn't be read.")
    expect(sources.unresolved).toEqual(["the repository's releases"])
  })

  test("records unreadable branches as unresolved", async () => {
    const sources = new Sources()
    expect(await repoActivity(recorded([], true), context, sources).run({ source: "branches", cursor: null })).toBe("The repository's branches couldn't be read.")
    expect(sources.unresolved).toEqual(["the repository's branches"])
  })
})

describe("repo_search", () => {
  const owner = { name: "Ada Park", emails: ["ada@work.com"], login: "ada" }
  const commits = [
    { date: "2026-10-22T10:00:00Z", author: "Ada Park", email: "ada@work.com", subject: "Include typed notes in the summary", branch: "ada/typed-notes" },
    { date: "2026-10-23T10:00:00Z", author: "Priya", email: "priya@work.com", subject: "Typed rooms", branch: "main" },
  ]
  const activity = (fail = false): Activity => ({
    commits: async () => commits,
    pullRequests: async () => [],
    branches: async () => [],
    releases: async () => [],
    search: async words => {
      if (fail) throw new Error("gh failed")
      const match = (text: string) => words.every(word => text.toLowerCase().includes(word.toLowerCase()))
      const pulls: PullRequest[] = [{ updatedAt: "2026-10-22T14:00:00Z", state: "MERGED", title: "Typed notes in summaries", author: "ada", branch: "ada/typed-notes", additions: 64, deletions: 12, changedFiles: 4, commits: 1 }]
      return { commits: commits.filter(commit => match(commit.subject)), pullRequests: pulls.filter(pull => match(pull.title)) }
    },
  })

  test("finds the owner's commits and pull requests that hold every word", async () => {
    expect(await repoSearch(activity(), { owner }, new Sources()).run({ query: " typed  NOTES " })).toBe([
      "Commits:",
      "2026-10-22 on ada/typed-notes, owner: Include typed notes in the summary",
      "Pull requests:",
      "2026-10-22 merged by owner, branch ada/typed-notes, +64 −12 in 4 files, 1 commits: Typed notes in summaries",
    ].join("\n"))
    expect(await repoSearch(activity(), { owner }, new Sources()).run({ query: "rooms" })).toBe("Commits:\n2026-10-23 on main, Priya <priya@work.com>: Typed rooms\nPull requests:\nNo pull requests match.")
  })

  test("refuses an empty query", async () => {
    expect(await repoSearch(activity(), { owner }, new Sources()).run({ query: "  " })).toBe("Give at least one word to search for.")
  })

  test("records a failed search as unresolved", async () => {
    const sources = new Sources()
    expect(await repoSearch(activity(true), { owner }, sources).run({ query: "typed" })).toBe("The repository search for “typed” couldn't be finished.")
    expect(sources.unresolved).toEqual(["the repository search for “typed”"])
  })
})

describe("ownership", () => {
  const owns = ownership({ name: "Ada Park", emails: ["ada@work.com", "ada@home.com"], login: "AdaP" })

  test("a commit is the owner's when its name or any of their emails matches, ignoring case", () => {
    expect(owns.commit({ author: "Ada Park", email: "bot@ci.com" })).toBe(true)
    expect(owns.commit({ author: "A. Park", email: "ADA@home.com" })).toBe(true)
    expect(owns.commit({ author: "Ada", email: "ada@other.com" })).toBe(false)
  })

  test("a pull request is the owner's when its login matches", () => {
    expect(owns.pull("adap")).toBe(true)
    expect(owns.pull("ada")).toBe(false)
  })
})

describe("github activity", () => {
  test("reads commits from every branch inside the window", async () => {
    const repository = await folder()
    const commit = (author: string, subject: string) => $`git -C ${repository} -c user.name=Martin -c user.email=martin@example.com commit -q --allow-empty --author=${author} -m ${subject}`
    await $`git -C ${repository} init -q -b main`
    await commit("Ann <ann@example.com>", "first")
    await $`git -C ${repository} switch -q -c side`
    await commit("Bo <bo@example.com>", "second")
    const activity = github({ folder: repository, slug: "ann/lumen" }, { since: new Date(Date.now() - 60_000), until: new Date(Date.now() + 60_000) })
    const commits = await activity.commits(0, 10)
    expect(commits.map(commit => commit.subject).sort()).toEqual(["first", "second"])
    expect(commits.find(commit => commit.subject === "second")).toMatchObject({ author: "Bo", email: "bo@example.com", branch: "side" })
  })

  test("reads branches and tags but skips other refs", async () => {
    const repository = await folder()
    const git = (...args: string[]) => $`git -C ${repository} -c user.name=Ann -c user.email=ann@example.com ${args}`.text()
    const detached = async (subject: string) => (await git("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", subject)).trim()
    await git("init", "-q", "-b", "main")
    await git("commit", "-q", "--allow-empty", "-m", "branch")
    await git("tag", "release", await detached("tagged"))
    await git("update-ref", "refs/supaterm/checkpoints/x", await detached("checkpoint"))
    const activity = github({ folder: repository, slug: "ann/lumen" }, { since: new Date(Date.now() - 60_000), until: new Date(Date.now() + 60_000) })
    const commits = await activity.commits(0, 10)
    expect(commits.map(commit => commit.subject).sort()).toEqual(["branch", "tagged"])
  })

  test("fails rather than returning nothing when git fails", async () => {
    const activity = github({ folder: join(await folder(), "missing"), slug: "ann/lumen" }, { since: new Date(0), until: new Date() })
    expect(activity.commits(0, 10)).rejects.toThrow()
  })
})

describe("github branches", () => {
  test("lists recent branches with their last commit, distance from main, merge state and pull request", async () => {
    const repository = await folder()
    const git = (date: string, ...args: string[]) => $`git -C ${repository} ${args}`
      .env({ ...process.env, GIT_AUTHOR_NAME: "Ada", GIT_AUTHOR_EMAIL: "ada@example.com", GIT_COMMITTER_NAME: "Ada", GIT_COMMITTER_EMAIL: "ada@example.com", GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date })
      .quiet()
    const commit = (date: string, subject: string) => git(date, "commit", "-q", "--allow-empty", "-m", subject)
    await git("2026-11-01T10:00:00Z", "init", "-q", "-b", "main")
    await git("2026-11-01T10:00:00Z", "remote", "add", "origin", "https://example.com/ada/lumen.git")
    await commit("2026-09-01T10:00:00Z", "Start")
    await git("2026-09-01T10:00:00Z", "branch", "ancient")
    await git("2026-11-02T10:00:00Z", "switch", "-q", "-c", "shipped")
    await commit("2026-11-02T10:00:00Z", "Shipped work")
    await git("2026-11-03T10:00:00Z", "switch", "-q", "main")
    await git("2026-11-03T10:00:00Z", "merge", "-q", "--no-ff", "shipped", "-m", "Merge shipped")
    await git("2026-11-05T10:00:00Z", "switch", "-q", "-c", "squashed")
    await commit("2026-11-05T10:00:00Z", "Squashed work")
    await git("2026-11-06T10:00:00Z", "switch", "-q", "main")
    await git("2026-11-06T10:00:00Z", "switch", "-q", "-c", "editor")
    await commit("2026-11-06T10:00:00Z", "Editor one")
    await commit("2026-11-07T10:00:00Z", "Editor two")
    await git("2026-11-07T10:00:00Z", "update-ref", "refs/remotes/origin/editor", "HEAD~1")
    await git("2026-11-07T10:00:00Z", "symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/editor")
    const pulls = [
      { title: "Editor", state: "OPEN", updatedAt: "2026-11-07T10:00:00Z", mergedAt: null, author: { login: "ada" }, headRefName: "editor", additions: 900, deletions: 10, changedFiles: 9, commits: [{}, {}] },
      { title: "Squashed", state: "MERGED", updatedAt: "2026-11-06T09:00:00Z", mergedAt: "2026-11-06T09:00:00Z", author: { login: "ada" }, headRefName: "squashed", additions: 5, deletions: 1, changedFiles: 1, commits: [{}] },
    ]
    const run = async (argv: string[]) => argv[0] === "gh" ? JSON.stringify(pulls) : execute(argv)
    const activity = github({ folder: repository, slug: "ada/lumen" }, { since: new Date("2026-11-05T00:00:00Z"), until: new Date("2026-11-08T00:00:00Z") }, run)
    const branches = (await activity.branches()).map(({ pullRequest, lastCommit, ...branch }) => ({ ...branch, lastCommit: Date.parse(lastCommit), pull: pullRequest?.title ?? null }))
    expect(branches.toSorted((a, b) => a.name.localeCompare(b.name))).toEqual([
      { name: "editor", lastCommit: Date.parse("2026-11-07T10:00:00Z"), author: "Ada", email: "ada@example.com", ahead: 2, merged: false, pull: "Editor" },
      { name: "shipped", lastCommit: Date.parse("2026-11-02T10:00:00Z"), author: "Ada", email: "ada@example.com", ahead: 0, merged: true, pull: null },
      { name: "squashed", lastCommit: Date.parse("2026-11-05T10:00:00Z"), author: "Ada", email: "ada@example.com", ahead: 0, merged: true, pull: "Squashed" },
    ])
    const commits = await activity.commits(0, 10)
    expect(commits.map(commit => [commit.subject, commit.branch])).toEqual([["Editor two", "editor"], ["Editor one", "editor"], ["Squashed work", "squashed"]])
  })
})

describe("github releases and search", () => {
  async function repository() {
    const folder_ = await folder()
    const git = (date: string, ...args: string[]) => $`git -C ${folder_} ${args}`
      .env({ ...process.env, GIT_AUTHOR_NAME: "Ada", GIT_AUTHOR_EMAIL: "ada@example.com", GIT_COMMITTER_NAME: "Ada", GIT_COMMITTER_EMAIL: "ada@example.com", GIT_AUTHOR_DATE: date, GIT_COMMITTER_DATE: date })
      .quiet()
    await git("2026-07-01T10:00:00Z", "init", "-q", "-b", "main")
    await git("2026-07-01T10:00:00Z", "commit", "-q", "--allow-empty", "-m", "Typed notes, long ago")
    await git("2026-10-22T10:00:00Z", "commit", "-q", "--allow-empty", "-m", "Include TYPED notes in the summary")
    await git("2026-10-22T10:00:00Z", "tag", "v2.3.0")
    await git("2026-10-23T10:00:00Z", "commit", "-q", "--allow-empty", "-m", "Typed rooms")
    await git("2026-10-23T10:00:00Z", "branch", "release/2.4")
    await git("2026-10-23T10:00:00Z", "branch", "feature")
    await git("2026-11-20T10:00:00Z", "commit", "-q", "--allow-empty", "-m", "Typed notes after the cutoff")
    await git("2026-11-20T10:00:00Z", "tag", "v2.4.0")
    return folder_
  }

  test("reads versioned tags and release branches up to the cutoff", async () => {
    const activity = github({ folder: await repository(), slug: "ada/lumen" }, { since: new Date("2026-11-01T00:00:00Z"), until: new Date("2026-11-10T00:00:00Z") })
    const releases = (await activity.releases()).map(({ name, date }) => [name, Date.parse(date)])
    expect(releases.toSorted()).toEqual([["release/2.4", Date.parse("2026-10-23T10:00:00Z")], ["v2.3.0", Date.parse("2026-10-22T10:00:00Z")]])
  })

  test("searches commit messages for every word, ignoring case, within the search lookback, and asks gh with the same words", async () => {
    const searches: string[] = []
    const run = async (argv: string[]) => {
      if (argv[0] !== "gh") return execute(argv)
      searches.push(argv[argv.indexOf("--search") + 1]!)
      return "[]"
    }
    const activity = github({ folder: await repository(), slug: "ada/lumen" }, { since: new Date("2026-11-01T00:00:00Z"), until: new Date("2026-11-10T00:00:00Z") }, run)
    const found = await activity.search(["typed", "notes"])
    expect(found.commits.map(commit => commit.subject)).toEqual(["Include TYPED notes in the summary"])
    expect(searches).toEqual(["typed notes updated:>=2026-08-12T00:00:00Z"])
  })
})
