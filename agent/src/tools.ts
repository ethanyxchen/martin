import { z } from "zod"
import type { Activity } from "./activity"
import type { Note } from "./schema"
import { characters, prefix } from "./text"

export type Tool = {
  name: string
  description: string
  input: z.ZodObject
  run: (input: any) => Promise<string>
}

export const pageLength = 4000
export const commitBatch = 100
export const pullRequestLimit = 30

function tool<Input extends z.ZodObject>(definition: {
  name: string
  description: string
  input: Input
  run: (input: z.infer<Input>) => Promise<string>
}): Tool {
  return definition
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

export function repoActivity(activity: Activity, sources: Sources): Tool {
  const cursors = new Map<string, number>()

  async function commits(cursor: string | null): Promise<string> {
    const skip = cursor === null ? 0 : cursors.get(cursor)
    if (skip === undefined) return `Unknown cursor ${cursor}. Use null to start, or a cursor this tool gave you.`
    const batch = await sources.read(`commits ${skip}`, "the repository's commits", () => activity.commits(skip, commitBatch))
    if (!batch) return "The repository's commits couldn't be read."
    if (!batch.length) return skip === 0 ? "No commits in this window." : "No more commits."
    const lines = fit(batch.map(commit => `${commit.date} ${commit.author}: ${commit.subject}`))
    if (lines.length === batch.length && batch.length < commitBatch) return `${lines.join("\n")}\nEnd of commits.`
    const next = crypto.randomUUID().slice(0, 8)
    cursors.set(next, skip + lines.length)
    return `${lines.join("\n")}\nMore commits. Next cursor: ${next}.`
  }

  async function pullRequests(): Promise<string> {
    const pulls = await sources.read("pull requests", "the repository's pull requests", () => activity.pullRequests(pullRequestLimit))
    if (!pulls) return "The repository's pull requests couldn't be read."
    if (!pulls.length) return "No pull requests updated in this window."
    const lines = fit(pulls.map(pull => `${pull.updatedAt.slice(0, 10)} ${pull.state.toLowerCase()} by ${pull.author}: ${pull.title}`))
    const hidden = pulls.length - lines.length
    const notes = [
      hidden > 0 ? `${hidden} more pull requests are not shown.` : null,
      pulls.length >= pullRequestLimit ? `The cap of ${pullRequestLimit} was reached; older updates in this window are not shown.` : null,
    ]
    return [...lines, ...notes.filter(Boolean)].join("\n")
  }

  return tool({
    name: "repo_activity",
    description: "Read the linked repository's activity since the last read. Source commits pages through every branch's commits with dates and authors; pass cursor null to start and the cursor it reports to continue. Source pullRequests lists recently updated pull requests with their current state and author; its cursor is ignored.",
    input: z.strictObject({ source: z.enum(["commits", "pullRequests"]), cursor: z.string().nullable() }),
    run: ({ source, cursor }) => source === "commits" ? commits(cursor) : pullRequests(),
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
