import { Failure } from "../failure"
import type { JobSpec } from "./spec"
import { type LookupJob, LookupResult } from "../schema"
import { prefix } from "../text"

export const excerptLength = 600
export const summaryLength = 600
export const matchLimit = 3

export const system = `List the GitHub repositories that hold this project's code: every one whose name or README names the project, or the product its notes discuss. A repository that is merely about a similar topic does not count. First quote the evidence, then list at most ${matchLimit} slugs exactly as written, or none when nothing names the project.`

export async function repositoryLookup(job: LookupJob): Promise<JobSpec<LookupResult>> {
  return {
    system,
    prompt: prompt(job, await excerpts(job)),
    tools: [],
    result: LookupResult,
    model: { anthropic: "claude-haiku-5-5", openai: "gpt-6-luna" },
    effort: "low",
    finish: result => ({
      evidence: result.evidence,
      slugs: result.slugs.length <= matchLimit ? result.slugs.map(slug => slug.toLowerCase()) : [],
    }),
  }
}

export function prompt(job: LookupJob, excerpts: string[]): string {
  const repositories = job.candidates.map(candidate => [candidate.slug, candidate.summary && prefix(candidate.summary, summaryLength)].filter(Boolean).join(": "))
  return [
    `Project: ${job.project.name}`,
    `Notes:\n${excerpts.length ? excerpts.join("\n\n") : "No notes yet."}`,
    `Repositories:\n${repositories.join("\n")}`,
  ].join("\n\n")
}

async function excerpts(job: LookupJob): Promise<string[]> {
  return Promise.all(job.notes.map(async note => `# ${note.title}\n${prefix(await text(note), excerptLength)}`))
}

async function text(note: LookupJob["notes"][number]): Promise<string> {
  const file = Bun.file(note.path)
  if (!await file.exists()) return ""
  return file.text().catch(() => { throw new Failure(`Couldn't read note “${note.title}”.`) })
}
