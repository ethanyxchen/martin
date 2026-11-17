import type { Repository } from "./schema"

export type Commit = { date: string, author: string, subject: string }
export type PullRequest = { updatedAt: string, state: string, title: string, author: string }

export type Activity = {
  commits: (skip: number, count: number) => Promise<Commit[]>
  pullRequests: (limit: number) => Promise<PullRequest[]>
}

export type Window = { since: Date, until: Date }

export type Connect = (repository: Repository, window: Window) => Activity

const timeout = 30_000
const separator = "\u001f"

export async function execute(argv: string[]): Promise<string> {
  const child = Bun.spawn(argv, { stdout: "pipe", stderr: "ignore", timeout })
  const [output, status] = await Promise.all([new Response(child.stdout).text(), child.exited])
  if (status !== 0) throw new Error(`${argv[0]} exited with status ${status}`)
  return output
}

export function github(repository: Repository, window: Window, run = execute): Activity {
  const since = seconds(window.since)
  const until = seconds(window.until)
  return {
    commits: async (skip, count) => {
      const output = await run([
        "git", "-C", repository.folder, "log", "--branches", "--remotes", "--tags", `--since=${since}`, `--until=${until}`, "--date=short",
        `--pretty=format:%ad${separator}%an <%ae>${separator}%s`, `--skip=${skip}`, "-n", `${count}`,
      ])
      return output.split("\n").filter(Boolean).map(line => {
        const [date = "", author = "", subject = ""] = line.split(separator)
        return { date, author, subject }
      })
    },
    pullRequests: async limit => {
      const output = await run([
        "gh", "pr", "list", "--repo", repository.slug, "--state", "all", "--limit", `${limit}`,
        "--search", `updated:>=${since}`, "--json", "title,state,updatedAt,author",
      ])
      const pulls: { title: string, state: string, updatedAt: string, author: { login: string } | null }[] = JSON.parse(output)
      return pulls
        .filter(pull => new Date(pull.updatedAt) <= window.until)
        .map(pull => ({ updatedAt: pull.updatedAt, state: pull.state, title: pull.title, author: pull.author?.login ?? "unknown" }))
    },
  }
}

function seconds(date: Date): string {
  return `${date.toISOString().slice(0, 19)}Z`
}
