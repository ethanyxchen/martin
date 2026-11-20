import { z } from "zod"

export const Task = z.strictObject({
  title: z.string(),
  caption: z.string(),
  updated: z.string().nullable(),
})

export const OverviewResult = z.strictObject({
  now: z.array(Task),
  next: z.array(Task),
  shelved: z.array(Task),
})

export const Overview = z.object({
  now: z.array(Task),
  next: z.array(Task),
  shelved: z.array(Task),
  readAt: z.iso.datetime({ offset: true }),
})

export const LookupResult = z.strictObject({
  evidence: z.string(),
  slugs: z.array(z.string()),
})

const ProviderName = z.enum(["anthropic", "openai"])

const Project = z.object({ name: z.string() })

export const Note = z.object({
  id: z.string(),
  title: z.string(),
  date: z.iso.datetime({ offset: true }),
  changedAt: z.iso.datetime({ offset: true }),
  path: z.string(),
})

export const Repository = z.object({ folder: z.string(), slug: z.string() })

export const Owner = z.strictObject({ name: z.string(), emails: z.array(z.string()), login: z.string() })

export const Commit = z.strictObject({
  date: z.iso.datetime({ offset: true }),
  author: z.string(),
  email: z.string(),
  subject: z.string(),
  branch: z.string(),
})

export const OverviewJob = z.object({
  kind: z.literal("overview"),
  provider: ProviderName,
  project: Project,
  owner: Owner,
  cutoff: z.iso.datetime({ offset: true }),
  previous: Overview.nullable(),
  notes: z.array(Note),
  repository: Repository.nullable(),
})

export const LookupJob = z.object({
  kind: z.literal("repositoryLookup"),
  provider: ProviderName,
  project: Project,
  notes: z.array(z.object({ title: z.string(), path: z.string() })),
  candidates: z.array(z.object({ slug: z.string(), summary: z.string().nullable() })),
})

export const Job = z.discriminatedUnion("kind", [OverviewJob, LookupJob])

export type Task = z.infer<typeof Task>
export type OverviewResult = z.infer<typeof OverviewResult>
export type Overview = z.infer<typeof Overview>
export type LookupResult = z.infer<typeof LookupResult>
export type ProviderName = z.infer<typeof ProviderName>
export type Note = z.infer<typeof Note>
export type Repository = z.infer<typeof Repository>
export type Owner = z.infer<typeof Owner>
export type Commit = z.infer<typeof Commit>
export type OverviewJob = z.infer<typeof OverviewJob>
export type LookupJob = z.infer<typeof LookupJob>
export type Job = z.infer<typeof Job>

export type Event =
  | { type: "progress", tool: string, input: unknown }
  | { type: "result", result: OverviewResult | LookupResult, cost: number | null }
  | { type: "error", message: string }
