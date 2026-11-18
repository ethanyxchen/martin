import { z } from "zod"
import { type Activity, type PullRequest, type Release, searchDays } from "./activity"
import { idleDays, staleDays } from "./idle"
import type { Commit, Note, Owner } from "./schema"
import { characters, day, prefix } from "./text"

export type Tool = {
  name: string
  description: string
  parameters: Record<string, unknown>
  run: (input: unknown) => Promise<string>
}

export const pageLength = 4000
export const commitBatch = 100
export const pullRequestLimit = 30
export const releaseDepth = 6

function tool<Input extends z.ZodObject>({ name, description, input, run }: {
  name: string
  description: string
  input: Input
  run: (input: z.infer<Input>) => Promise<string>
}): Tool {
  const { $schema: _, ...parameters } = z.toJSONSchema(input)
  return {
    name,
    description,
    parameters,
    run: async raw => {
      const parsed = input.safeParse(raw)
      return parsed.success ? run(parsed.data) : `Invalid input: ${z.prettifyError(parsed.error)}`
    },
  }
}

export class Sources {
  #failures = new Map<string, string>()

  async read<T>(key: string, label: string, load: () => Promise<T>): Promise<T | undefined> {
    try {
      const value = await load()
      this.#failures.delete(key)
      return value
    } catch {
      this.#failures.set(key, label)
      return undefined
    }
  }

  get unresolved(): string[] {
    return [...this.#failures.values()]
  }
}

export function readNote(notes: Note[], sources: Sources): Tool {
  const texts = new Map<string, string[]>()
  const pages = new Set<string>()
  return tool({
    name: "read_note",
    description: `Read up to ${pageLength} characters of a note, starting at a character offset. Use offset null for the start, then the next offset it reports to continue.`,
    input: z.strictObject({ id: z.string(), offset: z.number().nullable() }),
    run: async ({ id, offset }) => {
      const note = notes.find(note => note.id === id)
      if (!note) return `There is no note with id ${id}.`
      const text = texts.get(id) ?? await sources.read(`note ${id}`, `note “${note.title}”`, async () => characters(await Bun.file(note.path).text()))
      if (!text) return `Note ${id} couldn't be read.`
      texts.set(id, text)
      const start = offset ?? 0
      if (!Number.isInteger(start) || start < 0) return "The offset must be a whole number of characters, at least 0."
      if (start > 0 && start >= text.length) return `Note ${id} has only ${text.length} characters.`
      const end = Math.min(start + pageLength, text.length)
      const range = `characters ${start}–${end} of ${text.length}`
      const tail = end < text.length ? `Next offset: ${end}.` : "End of note."
      const page = `${id}:${start}`
      if (pages.has(page)) return `You already read note ${id}, ${range}. ${tail}`
      pages.add(page)
      return `Note ${id}, “${note.title}”, ${range}:\n${text.slice(start, end).join("")}\n${tail}`
    },
  })
}

export type Context = { owner: Owner, cutoff: string }

export function ownership(owner: Owner) {
  const same = (a: string, b: string) => a.trim().toLowerCase() === b.trim().toLowerCase()
  return {
    commit: (commit: Pick<Commit, "author" | "email">) => same(commit.author, owner.name) || owner.emails.some(email => same(email, commit.email)),
    pull: (login: string) => same(login, owner.login),
  }
}

function describe(owner: Owner) {
  const owns = ownership(owner)
  const committer = (commit: Pick<Commit, "author" | "email">) => owns.commit(commit) ? "owner" : `${commit.author} <${commit.email}>`
  const size = (pull: PullRequest) => `+${pull.additions} −${pull.deletions} in ${pull.changedFiles} files, ${pull.commits} commits`
  return {
    owns,
    committer,
    size,
    commitLine: (commit: Commit) => `${day(commit.date)} on ${commit.branch}, ${committer(commit)}: ${commit.subject}`,
    pullLine: (pull: PullRequest) => `${day(pull.updatedAt)} ${pull.state.toLowerCase()} by ${owns.pull(pull.author) ? "owner" : pull.author}, branch ${pull.branch}, ${size(pull)}: ${pull.title}`,
  }
}

export function tracks(releases: Release[]): { track: string, versions: { version: string, date: string }[] }[] {
  const grouped = new Map<string, Map<string, string>>()
  for (const { name, date } of releases) {
    const match = name.match(/^(?<track>.*?)(?:(?<![a-z])v)?(?<version>\d+(?:\.\d+)+(?:-(?:rc|beta|alpha|preview|pre|canary|next|dev|nightly)[.-]?\d*)?)/i)
    if (!match?.groups) continue
    const track = match.groups.track!.replace(/[-_/.]+$/, "") || "versions"
    const version = match.groups.version!
    const versions = grouped.get(track) ?? new Map<string, string>()
    const seen = versions.get(version)
    if (!seen || Date.parse(date) < Date.parse(seen)) versions.set(version, date)
    grouped.set(track, versions)
  }
  return [...grouped]
    .map(([track, versions]) => ({ track, versions: [...versions].map(([version, date]) => ({ version, date })).toSorted((a, b) => Date.parse(b.date) - Date.parse(a.date)) }))
    .toSorted((a, b) => Date.parse(b.versions[0]!.date) - Date.parse(a.versions[0]!.date))
}

export function repoActivity(activity: Activity, { owner, cutoff }: Context, sources: Sources): Tool {
  const cursors = new Map<string, number>()
  const { owns, committer, size, commitLine, pullLine } = describe(owner)

  async function commits(cursor: string | null): Promise<string> {
    const skip = cursor === null ? 0 : cursors.get(cursor)
    if (skip === undefined) return `Unknown cursor ${cursor}. Use null to start, or a cursor this tool gave you.`
    const batch = await sources.read(`commits ${skip}`, "the repository's commits", () => activity.commits(skip, commitBatch))
    if (!batch) return "The repository's commits couldn't be read."
    if (!batch.length) return skip === 0 ? "No commits in this window." : "No more commits."
    const lines = fit(batch.map(commitLine))
    if (lines.length === batch.length && batch.length < commitBatch) return `${lines.join("\n")}\nEnd of commits.`
    const next = crypto.randomUUID().slice(0, 8)
    cursors.set(next, skip + lines.length)
    return `${lines.join("\n")}\nMore commits. Next cursor: ${next}.`
  }

  async function pullRequests(): Promise<string> {
    const pulls = await sources.read("pull requests", "the repository's pull requests", () => activity.pullRequests(pullRequestLimit))
    if (!pulls) return "The repository's pull requests couldn't be read."
    if (!pulls.length) return "No pull requests updated in this window."
    const lines = fit(pulls.map(pullLine))
    const hidden = pulls.length - lines.length
    const notes = [
      hidden > 0 ? `${hidden} more pull requests are not shown.` : null,
      pulls.length >= pullRequestLimit ? `The cap of ${pullRequestLimit} was reached; older updates in this window are not shown.` : null,
    ]
    return [...lines, ...notes.filter(Boolean)].join("\n")
  }

  async function branches(): Promise<string> {
    const listed = await sources.read("branches", "the repository's branches", () => activity.branches())
    if (!listed) return "The repository's branches couldn't be read."
    if (!listed.length) return "No branches other than main had commits in the last 30 days."
    const described = listed
      .toSorted((a, b) => Date.parse(b.lastCommit) - Date.parse(a.lastCommit))
      .map(branch => {
        const idle = idleDays(branch.lastCommit, cutoff)
        const pull = branch.pullRequest
        const mine = pull ? owns.pull(pull.author) : owns.commit(branch)
        const line = [
          mine ? branch.name : `${branch.name}, ${pull?.author ?? committer(branch)}`,
          `last commit ${day(branch.lastCommit)}`,
          `idle ${idle.toFixed(1)} days${!branch.merged && idle >= staleDays ? ", stale" : ""}`,
          branch.merged ? "merged" : `${branch.ahead} commits ahead of main, not merged`,
          pull ? `pull request ${pull.state.toLowerCase()}, ${size(pull)}: ${pull.title}` : "no pull request",
        ].join(" · ")
        return { mine, merged: branch.merged, line }
      })
    const sections = [
      { header: "The owner's unmerged branches:", branches: described.filter(branch => branch.mine && !branch.merged) },
      { header: "The owner's merged branches:", branches: described.filter(branch => branch.mine && branch.merged) },
      { header: "Other contributors' branches:", branches: described.filter(branch => !branch.mine) },
    ]
    const headers = sections.map(section => section.header)
    const shown = fit(sections.flatMap(({ header, branches }) => branches.length ? [header, ...branches.map(branch => branch.line)] : []))
    if (headers.includes(shown.at(-1)!)) shown.pop()
    const hidden = listed.length - shown.filter(line => !headers.includes(line)).length
    return [...shown, ...(hidden > 0 ? [`${hidden} more branches are not shown.`] : [])].join("\n")
  }

  async function releases(): Promise<string> {
    const listed = await sources.read("releases", "the repository's releases", () => activity.releases())
    if (!listed) return "The repository's releases couldn't be read."
    const found = tracks(listed)
    if (!found.length) return "No tag or release branch names a version."
    const lines = fit(found.map(({ track, versions }) => {
      const shown = versions.slice(0, releaseDepth).map(({ version, date }) => `${version} on ${day(date)}`)
      const older = versions.length - shown.length
      return `${track}: ${shown.join(", ")}${older > 0 ? `, and ${older} older` : ""}`
    }))
    const hidden = found.length - lines.length
    return [...lines, ...(hidden > 0 ? [`${hidden} older tracks are not shown.`] : [])].join("\n")
  }

  return tool({
    name: "repo_activity",
    description: [
      "Read the linked repository. Activity by the owner is marked “owner”.",
      "Source commits pages through commits since the last read on local branches, remote branches and tags, newest first, each with its branch and author; pass cursor null to start and the cursor it reports to continue.",
      "Source pullRequests lists pull requests updated since the last read with their state, author, branch and size.",
      `Source branches lists every branch other than main with a commit in the last 30 days, the owner's unmerged ones first, then the owner's merged ones, then other contributors': its last commit, how long it has been idle (weekend days count half), whether it is stale (idle ${staleDays} days or more and not merged), how far it is ahead of main, whether it has merged, and its pull request.`,
      "Source releases lists the release tracks found in tags and release branches, newest first, each with its latest versions and the day each appeared. A release branch, a candidate (rc, beta, alpha), or a nightly or latest build is still being tested; a stable or plain version has shipped.",
      "The cursor is ignored except for commits.",
    ].join(" "),
    input: z.strictObject({ source: z.enum(["commits", "pullRequests", "branches", "releases"]), cursor: z.string().nullable() }),
    run: ({ source, cursor }) => ({ commits: () => commits(cursor), pullRequests, branches, releases })[source](),
  })
}

export function repoSearch(activity: Activity, { owner }: Pick<Context, "owner">, sources: Sources): Tool {
  const { commitLine, pullLine } = describe(owner)
  return tool({
    name: "repo_search",
    description: `Search the linked repository's commit messages and pull requests from the last ${searchDays} days for every word in the query, ignoring case, to check whether work a note mentions was done. Use a few distinctive words. Activity by the owner is marked “owner”.`,
    input: z.strictObject({ query: z.string() }),
    run: async ({ query }) => {
      const words = query.split(/[\s"]+/).filter(Boolean)
      if (!words.length) return "Give at least one word to search for."
      const found = await sources.read(`search ${words.join(" ")}`, `the repository search for “${query}”`, () => activity.search(words))
      if (!found) return `The repository search for “${query}” couldn't be finished.`
      const commits = found.commits.length ? fit(found.commits.map(commitLine)).join("\n") : "No commits match."
      const pulls = found.pullRequests.length ? fit(found.pullRequests.map(pullLine)).join("\n") : "No pull requests match."
      return `Commits:\n${commits}\nPull requests:\n${pulls}`
    },
  })
}

function fit(lines: string[]): string[] {
  const fitted: string[] = []
  let length = 0
  for (const line of lines) {
    const size = characters(line).length + 1
    if (fitted.length && length + size > pageLength) break
    fitted.push(prefix(line, pageLength))
    length += size
  }
  return fitted
}
