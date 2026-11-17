import type { Commit, Repository } from "./schema"

export type PullRequest = {
  updatedAt: string
  state: string
  title: string
  author: string
  branch: string
  additions: number
  deletions: number
  changedFiles: number
  commits: number
}
export type Branch = { name: string, lastCommit: string, author: string, email: string, ahead: number, merged: boolean, pullRequest: PullRequest | null }

export type Activity = {
  commits: (skip: number, count: number) => Promise<Commit[]>
  pullRequests: (limit: number) => Promise<PullRequest[]>
  branches: () => Promise<Branch[]>
}

export type Window = { since: Date, until: Date }

export type Connect = (repository: Repository, window: Window) => Activity

export const main = "main"
export const lookback = 30 * 24 * 60 * 60 * 1000

const branchPullLimit = 40
const timeout = 30_000
const separator = "\u001f"
const trunk = [`--branches=${exactly(main)}`, `--remotes=*/${exactly(main)}`]

export async function execute(argv: string[]): Promise<string> {
  const child = Bun.spawn(argv, { stdout: "pipe", stderr: "ignore", timeout })
  const [output, status] = await Promise.all([new Response(child.stdout).text(), child.exited])
  if (status !== 0) throw new Error(`${argv[0]} exited with status ${status}`)
  return output
}

export async function history(folder: string, window: Window, run = execute, page: string[] = []): Promise<{ hash: string, commit: Commit }[]> {
  const [log, mainline, remotes] = await Promise.all([
    run([
      "git", "-C", folder, "log", "--branches", "--exclude=*/HEAD", "--remotes", "--tags", "--source",
      `--since=${seconds(window.since)}`, `--until=${seconds(window.until)}`,
      `--pretty=format:%H${separator}%aI${separator}%an${separator}%ae${separator}%s${separator}%S`, ...page,
    ]),
    run(["git", "-C", folder, "rev-list", ...trunk, `--since=${seconds(window.since)}`]),
    run(["git", "-C", folder, "remote"]),
  ])
  const onMain = new Set(mainline.split("\n"))
  return log.split("\n").filter(Boolean).map(line => {
    const [hash = "", date = "", author = "", email = "", subject = "", ref = ""] = line.split(separator)
    return { hash, commit: { date, author, email, subject, branch: onMain.has(hash) ? main : branchName(ref, remotes) } }
  })
}

export function github(repository: Repository, window: Window, run = execute): Activity {
  const { folder, slug } = repository
  const until = window.until
  const pulls = async (since: Date, limit: number) => {
    const output = await run([
      "gh", "pr", "list", "--repo", slug, "--state", "all", "--limit", `${limit}`, "--search", `updated:>=${seconds(since)}`,
      "--json", "title,state,updatedAt,mergedAt,author,headRefName,additions,deletions,changedFiles,commits",
    ])
    const listed: (Omit<PullRequest, "author" | "branch" | "commits"> & { mergedAt: string | null, author: { login: string } | null, headRefName: string, commits: unknown[] })[] = JSON.parse(output)
    return listed
      .filter(pull => new Date(pull.updatedAt) <= until)
      .map(({ mergedAt, author, headRefName, commits, ...pull }) => ({
        mergedAt,
        pull: { ...pull, author: author?.login ?? "unknown", branch: headRefName, commits: commits.length },
      }))
  }
  return {
    commits: async (skip, count) => (await history(folder, window, run, [`--skip=${skip}`, "-n", `${count}`])).map(({ commit }) => commit),
    pullRequests: async limit => (await pulls(window.since, limit)).map(({ pull }) => pull),
    branches: async () => {
      const start = new Date(until.getTime() - lookback)
      const [refs, remotes, recent] = await Promise.all([
        run(["git", "-C", folder, "for-each-ref", `--format=%(refname)${separator}%(authordate:iso-strict)${separator}%(authorname)${separator}%(authoremail)`, "refs/heads", "refs/remotes"]),
        run(["git", "-C", folder, "remote"]),
        pulls(start, branchPullLimit),
      ])
      const tips = refs.split("\n").filter(Boolean).flatMap(line => {
        const [ref = "", lastCommit = "", author = "", email = ""] = line.split(separator)
        const name = branchName(ref, remotes)
        const date = new Date(lastCommit)
        return name !== main && name !== "HEAD" && date >= start && date <= until ? [{ ref, name, lastCommit, author, email: email.replace(/^<|>$/g, "") }] : []
      })
      const newest = new Map<string, (typeof tips)[number]>()
      for (const tip of tips) {
        const seen = newest.get(tip.name)
        if (!seen || Date.parse(tip.lastCommit) > Date.parse(seen.lastCommit)) newest.set(tip.name, tip)
      }
      return Promise.all([...newest.values()].map(async ({ ref, ...tip }) => {
        const ahead = Number((await run(["git", "-C", folder, "rev-list", "--count", ref, "--not", ...trunk])).trim())
        const found = recent.find(({ pull }) => pull.branch === tip.name)
        const merged = ahead === 0 || (!!found?.mergedAt && Date.parse(found.mergedAt) >= Date.parse(tip.lastCommit))
        return { ...tip, ahead: merged ? 0 : ahead, merged, pullRequest: found?.pull ?? null }
      }))
    },
  }
}

function branchName(ref: string, remotes: string): string {
  const name = ref.replace(/^refs\/(heads|tags|remotes)\//, "")
  const remote = remotes.split("\n").find(remote => remote && name.startsWith(`${remote}/`))
  return remote ? name.slice(remote.length + 1) : name
}

function exactly(name: string): string {
  return `[${name[0]}]${name.slice(1)}`
}

function seconds(date: Date): string {
  return `${date.toISOString().slice(0, 19)}Z`
}
