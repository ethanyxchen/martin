import { mkdir } from "node:fs/promises"
import { join } from "node:path"
import { z } from "zod"
import { describe, limits } from "../src/jobs/overview"
import type { Provider } from "../src/providers/provider"
import type { OverviewResult } from "../src/schema"
import { day } from "../src/text"
import { cost } from "./prices"
import { type Project, type Rubric, type Stage, state } from "./scenario"

export const judgeModel = "claude-sonnet-5-5"

export type Kind = "section" | "caption" | "date" | "order" | "precision" | "invariant"
export type Item = { key: string, kind: Kind, expect: string }
export type Verdict = { item: string, kind: Kind, pass: boolean, reason: string }
export type Judgement = { verdicts: Verdict[], cost: number, cached: boolean }

export function scored(verdicts: Verdict[]): Verdict[] {
  return verdicts.filter(verdict => verdict.kind !== "invariant")
}

const system = `You grade a project overview written by an assistant against a rubric. The overview has three sections: now, next and shelved. Each task has a title, a caption and an updated date.

Rubric tasks are themes. A task in the overview matches a theme when it is about the same work, whatever its title. Judge each rubric item on its own, from the overview and the source material, and give a one-line reason that names the overview task you matched, or says none matched.

The precision item fails when the overview has a task that matches no rubric task and no tolerated extra, or two tasks that cover the same theme. Its reason lists each such task.`

export function items(rubric: Rubric): Item[] {
  const tasks = rubric.tasks.flatMap((task): Item[] => {
    if (task.section === "absent") return [{ key: `${task.id} · section`, kind: "section", expect: `No task in the overview is about “${task.id}”.` }]
    return [
      { key: `${task.id} · section`, kind: "section", expect: `A task about “${task.id}” is in ${task.section}.` },
      ...(task.caption ? [{ key: `${task.id} · caption`, kind: "caption" as const, expect: `The caption of the task about “${task.id}” says ${task.caption}.` }] : []),
      ...(task.updated ? [{
        key: `${task.id} · date`,
        kind: "date" as const,
        expect: task.updated === "any"
          ? `The task about “${task.id}” has a reasonable updated date for the latest material about it.`
          : `The task about “${task.id}” is dated ${task.updated}.`,
      }] : []),
    ]
  })
  const order = rubric.order ? [{ key: "order", kind: "order" as const, expect: `Now lists these tasks in this order: ${rubric.order.map(id => `“${id}”`).join(", ")}.` }] : []
  const tolerated = rubric.tolerated.length ? rubric.tolerated.map(extra => `- ${extra}`).join("\n") : "none"
  const precision = { key: "precision", kind: "precision" as const, expect: `Every task matches a rubric task or one of these tolerated extras, and no two tasks cover the same theme. Tolerated extras:\n${tolerated}` }
  return [...tasks, ...order, precision]
}

export async function material(project: Project, stage: Stage): Promise<string> {
  const { owner, repository } = project.scenario
  const notes = await Promise.all(stage.notes.map(async note => `### ${note.title} · meeting ${day(note.date)} · edited ${day(note.changedAt)}\n${await Bun.file(note.path).text()}`))
  const visible = state(project.scenario, new Date(stage.cutoff))
  const commits = visible.commits.map(commit => `- ${commit.date} ${commit.author} <${commit.email}> on ${commit.branch}: ${commit.subject}`)
  const pulls = visible.pullRequests.map(pull => `- ${pull.state.toLowerCase()} by ${pull.author}, opened ${pull.createdAt}${pull.state === "MERGED" ? `, merged ${pull.mergedAt}` : ""}, +${pull.additions} −${pull.deletions} in ${pull.changedFiles} files, ${pull.commits} commits, branch ${pull.branch}: ${pull.title}`)
  const branches = visible.branches.map(branch => `- ${branch.name}: last commit ${branch.lastCommit}, ${branch.ahead} ahead of main, ${branch.merged ? "merged" : "not merged"}`)
  const releases = visible.releases.map(release => `- ${release.name}: ${release.date}`)
  return [
    `Project: ${project.scenario.project}`,
    `Owner: ${owner.name} (${owner.emails.join(", ")}), GitHub ${owner.login}`,
    `Material up to: ${stage.cutoff}`,
    `Notes:\n${notes.join("\n\n") || "None."}`,
    repository ? `Commits:\n${commits.join("\n") || "None."}\n\nPull requests:\n${pulls.join("\n") || "None."}\n\nBranches:\n${branches.join("\n") || "None."}\n\nReleases:\n${releases.join("\n") || "None."}` : "No repository.",
  ].join("\n\n")
}

export async function judge(rubric: Rubric, overview: OverviewResult, source: string, provider: Provider, cache: string): Promise<Judgement> {
  const list = items(rubric)
  const key = new Bun.CryptoHasher("sha256").update(JSON.stringify({ rubric, overview, model: judgeModel })).digest("hex")
  const file = Bun.file(join(cache, `${key}.json`))
  if (await file.exists()) return { verdicts: await file.json(), cost: 0, cached: true }
  const verdict = z.strictObject({ pass: z.boolean(), reason: z.string() })
  const result = z.strictObject(Object.fromEntries(list.map(item => [item.key, verdict])))
  const outcome = await provider.run({
    system,
    prompt: [
      `Source material:\n\n${source}`,
      `Overview:\n${describe(overview)}`,
      `Rubric items:\n${list.map(item => `- ${item.key}: ${item.expect}`).join("\n")}`,
    ].join("\n\n---\n\n"),
    tools: [],
    result,
    model: judgeModel,
    effort: "medium",
  })
  const answers = outcome.result as Record<string, z.infer<typeof verdict>>
  const verdicts = list.map(item => ({ item: item.key, kind: item.kind, ...answers[item.key]! }))
  await mkdir(cache, { recursive: true })
  await Bun.write(file, JSON.stringify(verdicts, null, 2))
  return { verdicts, cost: cost(judgeModel, outcome.requests), cached: false }
}

const references = [
  { name: "pull request number", pattern: /#\d+/ },
  { name: "commit hash", pattern: /\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}\b/ },
  { name: "file name", pattern: /\b[\w-]+\.(swift|ts|tsx|js|jsx|json|md|py|rb|go|rs|kt|java|yml|yaml|sh|plist|css|html|xcodeproj)\b/i },
]

export function invariants(overview: OverviewResult, cutoff: string): Verdict[] {
  const sections = ["now", "next", "shelved"] as const
  const tasks = sections.flatMap(section => overview[section])
  const over = sections.filter(section => overview[section].length > limits[section])
  const dates = tasks.filter(task => task.updated !== null && !(/^\d{4}-\d{2}-\d{2}$/.test(task.updated) && !Number.isNaN(Date.parse(task.updated)) && task.updated <= day(cutoff)))
  const leaks = tasks.flatMap(task => references.filter(reference => reference.pattern.test(`${task.title} ${task.caption}`)).map(reference => `${reference.name} in “${task.title}”`))
  const verdict = (item: string, problems: string[], fine: string): Verdict => ({ item, kind: "invariant", pass: !problems.length, reason: problems.join("; ") || fine })
  return [
    verdict("section limits", over.map(section => `${section} has ${overview[section].length} tasks, over ${limits[section]}`), "Every section is within its limit."),
    verdict("valid dates", dates.map(task => `“${task.title}” is dated ${task.updated}`), "Every date is a valid day up to the cutoff."),
    verdict("no references", leaks, "No pull request numbers, commit hashes or file names."),
  ]
}
