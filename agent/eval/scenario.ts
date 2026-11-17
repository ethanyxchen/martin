import { readdir } from "node:fs/promises"
import { join, resolve } from "node:path"
import { z } from "zod"
import type { Connect } from "../src/activity"
import { Note, Repository } from "../src/schema"
import { day } from "../src/text"

export const main = "main"

const Timestamp = z.iso.datetime({ offset: true })

export const Commit = z.strictObject({ date: Timestamp, author: z.string(), email: z.string(), subject: z.string(), branch: z.string() })

export const PullRequest = z.strictObject({
  title: z.string(),
  author: z.string(),
  branch: z.string(),
  createdAt: Timestamp,
  mergedAt: Timestamp.nullable(),
  closedAt: Timestamp.nullable(),
  additions: z.int(),
  deletions: z.int(),
  changedFiles: z.int(),
  commits: z.int(),
})

export const Section = z.enum(["now", "next", "shelved", "absent"])

export const Rubric = z.strictObject({
  tasks: z.array(z.strictObject({
    id: z.string(),
    section: Section,
    caption: z.string().optional(),
    updated: z.union([z.iso.date(), z.literal("any")]).optional(),
  })),
  tolerated: z.array(z.string()),
  order: z.array(z.string()).optional(),
})

const Stage = z.strictObject({
  name: z.string(),
  cutoff: Timestamp,
  notes: z.array(Note.omit({ path: true }).extend({ file: z.string() }).strict()),
  rubric: Rubric,
})

export const Scenario = z.strictObject({
  project: z.string(),
  owner: z.strictObject({ name: z.string(), emails: z.array(z.string()), login: z.string() }),
  repository: Repository.nullable(),
  commits: z.array(Commit),
  pullRequests: z.array(PullRequest),
  stages: z.array(Stage),
})

export type Commit = z.infer<typeof Commit>
export type PullRequest = z.infer<typeof PullRequest>
export type Section = z.infer<typeof Section>
export type Rubric = z.infer<typeof Rubric>
export type Scenario = z.infer<typeof Scenario>
export type Stage = Omit<z.infer<typeof Stage>, "notes"> & { notes: Note[] }
export type Project = { id: string, scenario: Scenario, stages: Stage[] }

export type PullState = "OPEN" | "MERGED" | "CLOSED"
export type Branch = { name: string, lastCommit: string, ahead: number, merged: boolean }
export type State = {
  commits: Commit[]
  pullRequests: (PullRequest & { state: PullState, updatedAt: string })[]
  branches: Branch[]
}

export async function projects(root: string, only?: string): Promise<Project[]> {
  const folders = await readdir(root, { withFileTypes: true })
  const all = await Promise.all(folders
    .filter(entry => entry.isDirectory())
    .map(async entry => await Bun.file(join(root, entry.name, "scenario.json")).exists() ? load(join(root, entry.name)) : null))
  return all
    .filter(project => project !== null)
    .filter(project => !only || [project.id, project.scenario.project].some(name => name.toLowerCase() === only.toLowerCase()))
}

export async function load(folder: string): Promise<Project> {
  const scenario = Scenario.parse(await Bun.file(join(folder, "scenario.json")).json())
  return {
    id: folder.split("/").at(-1)!,
    scenario,
    stages: scenario.stages.map(stage => ({
      ...stage,
      notes: stage.notes.map(({ file, ...note }) => ({ ...note, path: resolve(folder, file) })),
    })),
  }
}

export function state(scenario: Pick<Scenario, "commits" | "pullRequests">, cutoff: Date): State {
  const by = (date: string | null) => date !== null && new Date(date) <= cutoff
  const commits = scenario.commits.filter(commit => by(commit.date))
  const pullRequests = scenario.pullRequests.filter(pull => by(pull.createdAt)).map(pull => {
    const end = [pull.mergedAt, pull.closedAt].find(by) ?? null
    const state = status(pull, end)
    const pushes = commits.filter(commit => commit.branch === pull.branch && (!end || new Date(commit.date) <= new Date(end)))
    return { ...pull, state, updatedAt: latest([pull.createdAt, ...(end ? [end] : []), ...pushes.map(commit => commit.date)]) }
  })
  const names = [...new Set(commits.map(commit => commit.branch))].filter(name => name !== main)
  const branches = names.map(name => {
    const own = commits.filter(commit => commit.branch === name)
    const merges = pullRequests.filter(pull => pull.branch === name && pull.state === "MERGED").map(pull => pull.mergedAt!)
    const merge = merges.length ? new Date(latest(merges)) : null
    const ahead = own.filter(commit => !merge || new Date(commit.date) > merge).length
    return { name, lastCommit: latest(own.map(commit => commit.date)), ahead, merged: merge !== null && ahead === 0 }
  })
  return { commits, pullRequests, branches }
}

export function connect(scenario: Scenario): Connect {
  return (_, window) => {
    const visible = state(scenario, window.until)
    const since = (date: string) => new Date(date) >= window.since
    return {
      commits: async (skip, count) => visible.commits
        .filter(commit => since(commit.date))
        .toSorted((a, b) => Date.parse(b.date) - Date.parse(a.date))
        .slice(skip, skip + count)
        .map(commit => ({ date: day(commit.date), author: `${commit.author} <${commit.email}>`, subject: commit.subject })),
      pullRequests: async limit => visible.pullRequests
        .filter(pull => since(pull.updatedAt))
        .toSorted((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt))
        .slice(0, limit)
        .map(pull => ({ updatedAt: pull.updatedAt, state: pull.state, title: pull.title, author: pull.author })),
    }
  }
}

function status(pull: PullRequest, end: string | null): PullState {
  if (end === null) return "OPEN"
  return end === pull.mergedAt ? "MERGED" : "CLOSED"
}

function latest(dates: string[]): string {
  return dates.reduce((a, b) => Date.parse(b) > Date.parse(a) ? b : a)
}
