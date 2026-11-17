import { join } from "node:path"
import { parseArgs } from "node:util"
import { execute, history } from "../src/activity"
import type { Commit } from "../src/schema"
import { type PullRequest, Scenario } from "./scenario"

type Recorded = { commits: Commit[], pullRequests: PullRequest[] }

type Pull = Omit<PullRequest, "author" | "branch" | "commits"> & { author: { login: string } | null, headRefName: string, commits: { oid: string }[] }

export async function record(folder: string, slug: string, since: Date, until: Date, run = execute): Promise<Recorded> {
  const pulls: Pull[] = JSON.parse(await run([
    "gh", "pr", "list", "--repo", slug, "--state", "all", "--limit", "1000", "--search", `created:<=${iso(until)}`,
    "--json", "title,author,headRefName,createdAt,mergedAt,closedAt,additions,deletions,changedFiles,commits",
  ]))
  const heads = new Map(pulls.flatMap(pull => pull.commits.map(commit => [commit.oid, pull.headRefName] as const)))
  const commits = (await history(folder, { since, until }, run)).map(({ hash, commit }) => ({ ...commit, branch: heads.get(hash) ?? commit.branch }))
  const pullRequests = pulls
    .filter(pull => !pull.closedAt || new Date(pull.closedAt) >= since)
    .map(({ author, headRefName, commits: pushed, ...pull }) => ({ ...pull, author: author?.login ?? "unknown", branch: headRefName, commits: pushed.length }))
  return {
    commits: commits.toSorted((a, b) => Date.parse(a.date) - Date.parse(b.date)),
    pullRequests: pullRequests.toSorted((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt)),
  }
}

function iso(date: Date): string {
  return `${date.toISOString().slice(0, 19)}Z`
}

if (import.meta.main) {
  const { positionals } = parseArgs({ allowPositionals: true })
  const [folder, slug, since, until] = positionals
  if (!folder || !slug || !since || !until) {
    console.error("Usage: bun eval/record.ts <fixture folder> <owner/repo> <since> <until>")
    process.exit(2)
  }
  const file = Bun.file(join(folder, "scenario.json"))
  const existing = await file.exists() ? Scenario.parse(await file.json()) : null
  const recorded = await record(".", slug, new Date(since), new Date(until))
  const owner = existing?.owner ?? {
    name: (await execute(["git", "config", "user.name"])).trim(),
    emails: [(await execute(["git", "config", "user.email"])).trim()],
    login: (await execute(["gh", "api", "user", "--jq", ".login"])).trim(),
  }
  const scenario = Scenario.parse({
    project: existing?.project ?? slug.split("/").at(-1),
    owner,
    repository: existing?.repository ?? { folder: ".", slug },
    ...recorded,
    stages: existing?.stages ?? [],
  })
  await Bun.write(file, `${JSON.stringify(scenario, null, 2)}\n`)
  console.log(`${recorded.commits.length} commits and ${recorded.pullRequests.length} pull requests written to ${file.name}`)
}
