import { mkdtemp, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import type { Note, OverviewJob } from "../src/schema"

export async function folder(): Promise<string> {
  return mkdtemp(join(tmpdir(), "martin-agent-"))
}

export async function note(directory: string, id: string, text: string, fields: Partial<Note> = {}): Promise<Note> {
  const path = join(directory, `${id}.md`)
  await writeFile(path, text)
  return { id, title: `Note ${id}`, date: "2026-11-01T09:00:00-08:00", changedAt: "2026-11-01T09:00:00-08:00", path, ...fields }
}

export function overviewJob(fields: Partial<OverviewJob> = {}): OverviewJob {
  return {
    kind: "overview",
    provider: "anthropic",
    project: { name: "Lumen" },
    owner: { name: "Ada Park", emails: ["ada@example.com"], login: "ada" },
    cutoff: "2026-11-17T20:00:00-08:00",
    previous: null,
    notes: [],
    repository: null,
    ...fields,
  }
}
