import { type Connect, github, lookback } from "../activity"
import { Failure } from "../failure"
import type { JobSpec } from "./spec"
import { type Overview, type OverviewJob, OverviewResult, type Task } from "../schema"
import { readNote, repoActivity, repoSearch, Sources } from "../tools"
import { day, prefix } from "../text"

export const limits = { now: 3, next: 6, shelved: 6, title: 80, caption: 160 }
export const models = { anthropic: "claude-haiku-5-5", openai: "gpt-6-luna" }

export const system = `You keep a short, friendly overview of one project for the person who owns it.

The overview has three sections, most important first:
- now: what the owner is working on right now, at most ${limits.now} tasks, most recently updated first.
- next: what they will work on next, at most ${limits.next} tasks.
- shelved: work they have paused or set aside, at most ${limits.shelved} tasks.

A task is a piece of work: a theme that spans several branches and pull requests, or one large pull request on its own. Judge a pull request's size from its lines added and removed, files changed and commits. Group small pull requests and branches into the theme they belong to and never list one on its own. A large one can stand alone or anchor a theme.

The repository decides the status of code work:
- A task is in now while its branches or pull requests keep moving.
- It is done when all its work has merged and it has been idle for 2 days or more. Remove done tasks.
- A stale branch means its task is shelved, unless other work on the same task is still moving or has merged since.
Only work marked as the owner's counts. Another contributor's branches and pull requests are not the owner's tasks, and neither is reviewing them.

Notes supply intent. They decide what is next, what the owner explicitly shelved or cancelled, and the status of work that isn't code. A ticked box (- [x]) means done, even when the repository shows nothing. Remove cancelled tasks. An idea list is not a task until something says the owner is doing it, and neither are discussion, meeting chores or other people's plans. A release or testing checklist is one task, with its open items summed up in the caption. When a note disagrees with the repository about code, the repository wins.

The title names the task in a few words. The caption is one short sentence on where it stands. Never mention pull request numbers, commit hashes, branch names or file names. Set "updated" to the YYYY-MM-DD date of the latest note or owner activity about the task, or null when unknown. A release is not owner activity.

Start from the previous overview: keep what still holds and change only what the new material changes. The previous overview is a draft, not evidence; check its claims against the notes and repository, and let later material override earlier.

Read only what you need. You may read several notes at once. When a note continues past the page you read and the rest may settle a task, read on. When a repository is linked, read its branches and releases every time, and its commits and pull requests as needed, even if no note changed. If a source couldn't be read, do not describe it as having no activity. Leave out anything the material does not support.`

const stale = `Notes go stale: each says what was true when it was last edited, and nobody goes back to tidy old ones. An open item in a note that hasn't been edited for days is a claim to check, not proof the work is still open. Before keeping such an item in now or next, look for it with repo_search, and treat it as done when the owner's merged work covers it. A release or testing checklist belongs to one version. Once that version, or a later one on the same track, has shipped, the checklist is over: remove its task, even when boxes are still unticked. Use the repository's releases to tell which versions have shipped and which are still being tested, and name the version the owner is actually on.`

export function overview(job: OverviewJob, connect: Connect = github): JobSpec<OverviewResult> {
  const sources = new Sources()
  const today = day(job.cutoff)
  const since = job.previous ? new Date(job.previous.readAt) : new Date(new Date(job.cutoff).getTime() - lookback)
  const repository = job.repository && connect(job.repository, { since, until: new Date(job.cutoff) })
  return {
    system,
    prompt: prompt(job),
    tools: [
      readNote(job.notes, sources),
      ...(repository ? [repoActivity(repository, { owner: job.owner, cutoff: job.cutoff }, sources), repoSearch(repository, { owner: job.owner }, sources)] : []),
    ],
    result: OverviewResult,
    model: models,
    effort: "high",
    finish: result => {
      if (sources.unresolved.length) throw new Failure(`Couldn't read ${sources.unresolved.join(", ")}.`)
      return {
        now: tasks(result.now, limits.now, today),
        next: tasks(result.next, limits.next, today),
        shelved: tasks(result.shelved, limits.shelved, today),
      }
    },
  }
}

export function prompt(job: OverviewJob): string {
  const readAt = job.previous ? new Date(job.previous.readAt) : null
  const notes = [...job.notes]
    .sort((a, b) => b.date.localeCompare(a.date))
    .map(note => {
      const fresh = !readAt || new Date(note.changedAt) > readAt
      return `- ${note.id} · ${note.title} · meeting ${day(note.date)} · edited ${day(note.changedAt)}${fresh ? " · new since last read" : ""}`
    })
  return [
    `Project: ${job.project.name}`,
    `Owner: ${job.owner.name}`,
    `Today: ${day(job.cutoff)}`,
    `Material up to: ${job.cutoff}`,
    `Last read: ${job.previous?.readAt ?? "never"}`,
    `Previous overview:\n${job.previous ? describe(job.previous) : "None yet."}`,
    `Notes:\n${notes.length ? notes.join("\n") : "No notes."}`,
    job.repository ? `Repository: ${job.repository.slug}. Read its activity with repo_activity.\n\n${stale}` : "No repository is linked.",
  ].join("\n\n")
}

export function describe(overview: Pick<Overview, "now" | "next" | "shelved">): string {
  return (["now", "next", "shelved"] as const)
    .map(section => {
      const tasks = overview[section]
      if (!tasks.length) return `${section}: none`
      const lines = tasks.map(task => `- ${task.title} · ${task.updated ?? "unknown date"} · ${task.caption}`)
      return `${section}:\n${lines.join("\n")}`
    })
    .join("\n")
}

function tasks(items: Task[], limit: number, today: string): Task[] {
  return items
    .map(item => ({
      title: prefix(item.title.trim(), limits.title),
      caption: prefix(item.caption.trim(), limits.caption),
      updated: item.updated && isDay(item.updated) && item.updated <= today ? item.updated : null,
    }))
    .filter(task => task.title)
    .slice(0, limit)
}

function isDay(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) && !Number.isNaN(Date.parse(value))
}
