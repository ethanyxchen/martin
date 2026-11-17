import { readdir } from "node:fs/promises"
import { join, resolve } from "node:path"
import type { Commit, Connect, PullRequest } from "../src/activity"
import type { Note, OverviewResult, Repository } from "../src/schema"

export type Section = "now" | "next" | "shelved" | "absent"
export type Expectation = { task: string, pattern: string, in: Section }
export type Stage = { name: string, cutoff: string, notes: Note[], expect: Expectation[] }
export type Suite = { kind: "fixtures" | "retrospective", project: string, repository: Repository | null, connect?: Connect, stages: Stage[] }
export type Check = Expectation & { found: Section, pass: boolean }

type Scenario = {
  project: string
  repository: Repository | null
  commits: Commit[]
  pullRequests: PullRequest[]
  stages: (Omit<Stage, "notes"> & { notes: (Omit<Note, "path"> & { file: string })[] })[]
}

export async function fixtures(folder: string): Promise<Suite> {
  const scenario: Scenario = await Bun.file(join(folder, "scenario.json")).json()
  return {
    kind: "fixtures",
    project: scenario.project,
    repository: scenario.repository,
    connect: (_, window) => ({
      commits: async (skip, count) => scenario.commits
        .filter(commit => within(new Date(`${commit.date}T12:00:00Z`), window))
        .toSorted((a, b) => b.date.localeCompare(a.date))
        .slice(skip, skip + count),
      pullRequests: async limit => scenario.pullRequests
        .filter(pull => within(new Date(pull.updatedAt), window))
        .slice(0, limit),
    }),
    stages: scenario.stages.map(stage => ({
      ...stage,
      notes: stage.notes.map(({ file, ...note }) => ({ ...note, path: resolve(folder, file) })),
    })),
  }
}

function within(date: Date, window: { since: Date, until: Date }): boolean {
  return date >= window.since && date <= window.until
}

type Meeting = { id: string, startedAt: string, scheduledAt?: string, title?: string, occurrence?: unknown, project?: string }

export async function library(folder: string, project: string, snapshots: string[]): Promise<Suite> {
  const projects: { id: string, name: string }[] = await Bun.file(join(folder, "projects.json")).json()
  const match = projects.find(candidate => candidate.name.toLowerCase() === project.toLowerCase())
  if (!match) throw new Error(`No project named ${project}. Projects: ${projects.map(candidate => candidate.name).join(", ")}`)
  const meetingsFolder = join(folder, "meetings")
  const meetings: Meeting[] = await Promise.all((await readdir(meetingsFolder)).map(id => Bun.file(join(meetingsFolder, id, "meeting.json")).json()))
  const notes = meetings
    .filter(meeting => meeting.project === match.id)
    .map(meeting => {
      const date = local(new Date(meeting.scheduledAt ?? meeting.startedAt))
      return { id: meeting.id, title: meeting.title ?? (meeting.occurrence ? "Meeting" : "Quick note"), date, changedAt: date, path: join(meetingsFolder, meeting.id, "note.md") }
    })
  return {
    kind: "retrospective",
    project: match.name,
    repository: null,
    stages: snapshots.map(snapshot => {
      const cutoff = local(new Date(`${snapshot}T23:59:59`))
      return { name: snapshot, cutoff, notes: notes.filter(note => new Date(note.date) <= new Date(cutoff)), expect: [] }
    }),
  }
}

export function local(date: Date): string {
  const offset = -date.getTimezoneOffset()
  const pad = (value: number) => `${Math.floor(Math.abs(value))}`.padStart(2, "0")
  const shifted = new Date(date.getTime() + offset * 60_000).toISOString().slice(0, 19)
  return `${shifted}${offset >= 0 ? "+" : "-"}${pad(offset / 60)}:${pad(offset % 60)}`
}

export function check(result: OverviewResult, expectations: Expectation[]): Check[] {
  return expectations.map(expectation => {
    const pattern = new RegExp(expectation.pattern, "i")
    const found = (["now", "next", "shelved"] as const).find(section => result[section].some(task => pattern.test(task.title))) ?? "absent"
    return { ...expectation, found, pass: found === expectation.in }
  })
}
