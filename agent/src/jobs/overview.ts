import { type Connect, github } from "../activity"
import { Failure } from "../failure"
import type { JobSpec } from "./spec"
import { type Overview, type OverviewJob, OverviewResult, type Task } from "../schema"
import { readNote, repoActivity, Sources } from "../tools"
import { day, prefix } from "../text"

export const limits = { now: 3, next: 6, shelved: 6, title: 80, caption: 160 }
export const models = { anthropic: "claude-haiku-5-5", openai: "gpt-6-luna" }
const defaultWindow = 30 * 24 * 60 * 60 * 1000

export const system = `You keep a short, friendly overview of one project for the person who owns it.

The overview has three sections, most important first:
- now: what they are working on right now, at most ${limits.now} tasks, most recently updated first.
- next: what they will work on next, at most ${limits.next} tasks.
- shelved: work they have explicitly paused or set aside, at most ${limits.shelved} tasks. Never shelve a task only because nothing was said about it.

A task is a title and a caption. The title names the overall task in a few words. The caption is one short sentence on where it stands. Never mention pull request numbers, commit hashes or file names. Set "updated" to the YYYY-MM-DD date of the latest note or activity about the task, or null when unknown.

Start from the previous overview: keep what still holds and change only what the new material changes. The previous overview is a draft, not evidence; check its claims against the notes and repository. Remove tasks that were completed or cancelled. Move a task between sections when the material says its status changed, and let a later note override an earlier one.

Repository activity gives context about the project. Do not make another contributor's work the owner's task only because it appears in the activity.

Read only what you need. You may read several notes at once. When a note continues past the page you read and the rest may settle a task, read on. When a repository is linked, look at its activity even if no note changed. If a source couldn't be read, do not describe it as having no activity. Leave out anything the material does not support.`

export function overview(job: OverviewJob, connect: Connect = github): JobSpec<OverviewResult> {
  const sources = new Sources()
  const today = day(job.cutoff)
  const since = job.previous ? new Date(job.previous.readAt) : new Date(new Date(job.cutoff).getTime() - defaultWindow)
  const repository = job.repository && connect(job.repository, { since, until: new Date(job.cutoff) })
  return {
    system,
    prompt: prompt(job),
    tools: [readNote(job.notes, sources), ...(repository ? [repoActivity(repository, sources)] : [])],
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
    `Today: ${day(job.cutoff)}`,
    `Material up to: ${job.cutoff}`,
    `Last read: ${job.previous?.readAt ?? "never"}`,
    `Previous overview:\n${job.previous ? describe(job.previous) : "None yet."}`,
    `Notes:\n${notes.length ? notes.join("\n") : "No notes."}`,
    job.repository ? `Repository: ${job.repository.slug}. Read its activity with repo_activity.` : "No repository is linked.",
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
