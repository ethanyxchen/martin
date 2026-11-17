import { describe, expect, test } from "bun:test"
import { $ } from "bun"
import { join } from "node:path"
import { type Activity, type Commit, github } from "../src/activity"
import { commitBatch, pageLength, pullRequestLimit, readNote, repoActivity, Sources } from "../src/tools"
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
  function recorded(commits: Commit[], fail = false): Activity {
    return {
      commits: async (skip, count) => {
        if (fail) throw new Error("git failed")
        return commits.slice(skip, skip + count)
      },
      pullRequests: async limit => Array.from({ length: Math.min(limit, 40) }, (_, index) => ({ updatedAt: "2026-11-10T10:00:00Z", state: "OPEN", title: `Change ${index}`, author: "priya" })),
    }
  }

  test("pages through every commit without gaps", async () => {
    const commits = Array.from({ length: commitBatch * 2 + 5 }, (_, index) => ({ date: "2026-11-10", author: "Ann <ann@example.com>", subject: `Commit ${index} ${"y".repeat(60)}` }))
    const tool = repoActivity(recorded(commits), new Sources())
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
    const tool = repoActivity(recorded([]), new Sources())
    expect(await tool.run({ source: "commits", cursor: "made-up" })).toContain("Unknown cursor made-up")
  })

  test("tells an empty window apart from a failed read", async () => {
    const sources = new Sources()
    expect(await repoActivity(recorded([]), sources).run({ source: "commits", cursor: null })).toBe("No commits in this window.")
    expect(sources.unresolved).toEqual([])
    expect(await repoActivity(recorded([], true), sources).run({ source: "commits", cursor: null })).toBe("The repository's commits couldn't be read.")
    expect(sources.unresolved).toEqual(["the repository's commits"])
  })

  test("says when the pull request cap was reached", async () => {
    const page = await repoActivity(recorded([]), new Sources()).run({ source: "pullRequests", cursor: null })
    expect(page).toContain("2026-11-10 open by priya: Change 0")
    expect(page).toContain(`The cap of ${pullRequestLimit} was reached`)
  })
})

describe("github activity", () => {
  test("reads commits from every branch inside the window", async () => {
    const repository = await folder()
    await $`git -C ${repository} init -q -b main && git -C ${repository} -c user.name=Ann -c user.email=ann@example.com commit -q --allow-empty -m first && git -C ${repository} switch -q -c side && git -C ${repository} -c user.name=Bo -c user.email=bo@example.com commit -q --allow-empty -m second`
    const activity = github({ folder: repository, slug: "ann/lumen" }, { since: new Date(Date.now() - 60_000), until: new Date(Date.now() + 60_000) })
    const commits = await activity.commits(0, 10)
    expect(commits.map(commit => commit.subject).sort()).toEqual(["first", "second"])
    expect(commits.find(commit => commit.subject === "second")?.author).toBe("Bo <bo@example.com>")
  })

  test("fails rather than returning nothing when git fails", async () => {
    const activity = github({ folder: join(await folder(), "missing"), slug: "ann/lumen" }, { since: new Date(0), until: new Date() })
    expect(activity.commits(0, 10)).rejects.toThrow()
  })
})
