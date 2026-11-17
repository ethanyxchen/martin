import { join } from "node:path"
import { parseArgs } from "node:util"
import { execute } from "../src/activity"
import { type Commit, main, type PullRequest, Scenario } from "./scenario"

const separator = "\u001f"

type Recorded = { commits: Commit[], pullRequests: PullRequest[] }

type Pull = Omit<PullRequest, "author" | "branch"> & { author: { login: string } | null, headRefName: string, oids: string[] }

const query = `query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequests(first: 50, after: $endCursor) {
      pageInfo { hasNextPage endCursor }
      nodes { title author { login } headRefName createdAt mergedAt closedAt additions deletions changedFiles commits(first: 100) { totalCount nodes { commit { oid } } } }
    }
  }
}`

export async function record(folder: string, slug: string, since: Date, until: Date, run = execute): Promise<Recorded> {
  const [owner = "", name = ""] = slug.split("/")
  const listed = await run([
    "gh", "api", "graphql", "--paginate", "-F", `owner=${owner}`, "-F", `name=${name}`, "-f", `query=${query}`,
    "--jq", ".data.repository.pullRequests.nodes[] | .oids = [.commits.nodes[].commit.oid] | .commits = .commits.totalCount",
  ])
  const pulls = listed.split("\n").filter(Boolean).map(line => JSON.parse(line) as Pull).filter(pull => new Date(pull.createdAt) <= until)
  const heads = new Map(pulls.flatMap(pull => pull.oids.map(oid => [oid, pull.headRefName] as const)))
  const log = await run([
    "git", "-C", folder, "log", "--branches", "--exclude=*/HEAD", "--remotes", "--tags", "--source",
    `--since=${iso(since)}`, `--until=${iso(until)}`, `--pretty=format:%H${separator}%aI${separator}%an${separator}%ae${separator}%s${separator}%S`,
  ])
  const trunk = new Set((await run(["git", "-C", folder, "rev-list", `--branches=${main}`, `--remotes=*/${main}`, `--since=${iso(since)}`])).split("\n"))
  const remotes = (await run(["git", "-C", folder, "remote"])).split("\n").filter(Boolean)
  const commits = log.split("\n").filter(Boolean).map(line => {
    const [hash = "", date = "", author = "", email = "", subject = "", ref = ""] = line.split(separator)
    return { date, author, email, subject, branch: heads.get(hash) ?? (trunk.has(hash) ? main : branch(ref, remotes)) }
  })
  const pullRequests = pulls
    .filter(pull => !pull.closedAt || new Date(pull.closedAt) >= since)
    .map(({ author, headRefName, oids: _, ...pull }) => ({ ...pull, author: author?.login ?? "unknown", branch: headRefName }))
  return {
    commits: commits.toSorted((a, b) => Date.parse(a.date) - Date.parse(b.date)),
    pullRequests: pullRequests.toSorted((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt)),
  }
}

function branch(ref: string, remotes: string[]): string {
  const short = ref.replace(/^refs\/(heads|tags|remotes)\//, "")
  const remote = remotes.find(name => short.startsWith(`${name}/`))
  return remote ? short.slice(remote.length + 1) : short
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
