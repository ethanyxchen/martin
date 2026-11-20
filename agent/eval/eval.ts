import { mkdir } from "node:fs/promises"
import { join } from "node:path"
import { parseArgs } from "node:util"
import { Failure } from "../src/failure"
import { models } from "../src/jobs/overview"
import { provider } from "../src/providers"
import type { Effort, Outcome, Usage } from "../src/providers/provider"
import { runJob } from "../src/run"
import type { Overview, OverviewResult, ProviderName } from "../src/schema"
import { invariants, judge, judgeModel, type Kind, material, scored, type Verdict } from "./judge"
import { cost, priced } from "../src/prices"
import { connect, type Project, projects, type Stage } from "./scenario"

type Run = {
  project: string
  label: string
  stage: string
  seconds: number
  calls: { tool: string, input: unknown }[]
  outcome?: Outcome<OverviewResult>
  cost?: number
  judge?: { cost: number, cached: boolean }
  verdicts: Verdict[]
  error?: string
}

const { values } = parseArgs({
  options: {
    provider: { type: "string", default: "anthropic" },
    project: { type: "string" },
    scratch: { type: "boolean", default: false },
    stage: { type: "string" },
    previous: { type: "string" },
    repeat: { type: "string", default: "1" },
    model: { type: "string" },
    effort: { type: "string" },
    out: { type: "string" },
  },
})

const name = values.provider as ProviderName
const model = values.model ?? models[name]
if (!priced(model)) exit(`No price for ${model}, so its runs can't be costed. Add it to src/prices.ts.`)
const selected = await projects(join(import.meta.dir, "..", "fixtures"), values.project)
if (!selected.length) exit(values.project ? `No project named ${values.project}.` : "No projects in fixtures/.")
const repeats = Number(values.repeat)
if (!Number.isInteger(repeats) || repeats < 1) exit("--repeat takes a whole number of runs, at least 1.")
if (values.previous && !(values.stage && values.project)) exit("--previous needs --stage and --project, since the overview belongs to one project.")
const start: Overview | null = values.previous ? await recorded(values.previous) : null
if (values.stage && !selected.some(project => project.stages.some(stage => stage.name === values.stage))) exit(`No stage named ${values.stage}.`)
const out = values.out ?? join(import.meta.dir, "out", `${new Date().toISOString().replace(/[:.]/g, "-")}-${model}`)
const cache = join(import.meta.dir, "cache")
const agent = provider(name)
const grader = provider("anthropic")
console.log(`${selected.map(project => project.scenario.project).join(", ")} · ${model}${values.effort ? ` · ${values.effort}` : ""} · judged by ${judgeModel}\n`)

const rounds = Array.from({ length: repeats }, (_, index) => repeats > 1 ? `${index + 1}` : "")
const runs = (await Promise.all(rounds.flatMap(round => selected.map(project => replay(project, round))))).flat()
await Bun.write(join(out, "summary.json"), JSON.stringify({ model, effort: values.effort ?? null, judge: judgeModel, runs }, null, 2))
report(runs)

async function replay(project: Project, round: string): Promise<Run[]> {
  await mkdir(join(out, project.id), { recursive: true })
  const label = (name: string) => round ? `${name}-${round}` : name
  if (values.stage) {
    const only = project.stages.find(stage => stage.name === values.stage)
    return only ? [await attempt(project, only, start, label(start ? "resumed" : "scratch"))] : []
  }
  const runs: Run[] = []
  let previous: Overview | null = null
  for (const stage of project.stages) {
    const run = await attempt(project, stage, previous, label("chained"))
    runs.push(run)
    if (!run.outcome) break
    previous = { ...run.outcome.result, readAt: stage.cutoff }
  }
  const last = project.stages.at(-1)
  if (values.scratch && last) runs.push(await attempt(project, last, null, label("scratch")))
  return runs
}

async function attempt(project: Project, stage: Stage, previous: Overview | null, label: string): Promise<Run> {
  const { scenario } = project
  const job = { kind: "overview" as const, provider: name, project: { name: scenario.project }, owner: scenario.owner, cutoff: stage.cutoff, previous, notes: stage.notes, repository: scenario.repository }
  const run: Run = { project: scenario.project, label, stage: stage.name, seconds: 0, calls: [], verdicts: [] }
  const started = performance.now()
  try {
    run.outcome = await runJob(job, agent, event => event.type === "progress" && run.calls.push({ tool: event.tool, input: event.input }), {
      connect: connect(scenario),
      model,
      effort: values.effort as Effort | undefined,
    }) as Outcome<OverviewResult>
    run.cost = cost(run.outcome.model, run.outcome.requests)
  } catch (error) {
    run.error = message(error)
  }
  run.seconds = (performance.now() - started) / 1000
  if (run.outcome) {
    run.verdicts = invariants(run.outcome.result, stage.cutoff)
    try {
      const judgement = await judge(stage.rubric, run.outcome.result, await material(project, stage), grader, cache)
      run.judge = { cost: judgement.cost, cached: judgement.cached }
      run.verdicts.push(...judgement.verdicts)
    } catch (error) {
      run.error = `The judge failed: ${message(error)}`
    }
  }
  await Bun.write(join(out, project.id, `${label}-${stage.name}.json`), JSON.stringify({ job, ...run }, null, 2))
  console.log(line(run))
  return run
}

function line(run: Run): string {
  const head = `${run.project.padEnd(10)} ${run.label.padEnd(10)} ${run.stage.padEnd(26)} ${run.seconds.toFixed(1).padStart(6)}s`
  if (!run.outcome) return `${head}  error: ${run.error}`
  const total = sum(run.outcome.requests)
  return [
    head,
    `agent $${run.cost!.toFixed(4)}`,
    run.judge ? `judge $${run.judge.cost.toFixed(4)}${run.judge.cached ? " cached" : ""}` : "",
    `${run.outcome.requests.length} req`,
    `in ${thousands(total.input + total.cacheRead + total.cacheWrite)}`,
    `out ${thousands(total.output)}`,
    `${run.calls.length} calls`,
    `${passed(scored(run.verdicts))}/${scored(run.verdicts).length}`,
    run.error ?? "",
  ].filter(Boolean).join("  ")
}

function report(runs: Run[]) {
  const all = runs.flatMap(run => run.verdicts)
  const verdicts = scored(all)
  const kinds: Kind[] = ["section", "caption", "date", "order", "precision"]
  const projectsLine = [...new Set(runs.map(run => run.project))].map(project => {
    const group = scored(runs.filter(run => run.project === project).flatMap(run => run.verdicts))
    return `${project} ${passed(group)}/${group.length}`
  })
  const kindsLine = kinds.flatMap(kind => {
    const group = verdicts.filter(verdict => verdict.kind === kind)
    return group.length ? [`${kind} ${passed(group)}/${group.length}`] : []
  })
  const skillsLine = [...new Set(verdicts.flatMap(verdict => verdict.skills))].toSorted().map(skill => {
    const group = verdicts.filter(verdict => verdict.skills.includes(skill))
    return `${skill} ${passed(group)}/${group.length}`
  })
  const completed = runs.flatMap(run => run.outcome ? [run] : [])
  const tokens = sum(completed.flatMap(run => run.outcome!.requests))
  const seconds = runs.reduce((total, run) => total + run.seconds, 0)
  const agentCost = completed.reduce((total, run) => total + run.cost!, 0)
  const judgeCost = runs.reduce((total, run) => total + (run.judge?.cost ?? 0), 0)
  const calls = runs.reduce((total, run) => total + run.calls.length, 0)
  console.log(`\n${passed(verdicts)}/${verdicts.length} passed · ${projectsLine.join(" · ")}`)
  const held = all.filter(verdict => verdict.kind === "invariant")
  console.log(kindsLine.join(" · "))
  if (skillsLine.length) console.log(`skills: ${skillsLine.join(" · ")}`)
  console.log(`invariants ${passed(held)}/${held.length} held, not scored`)
  console.log(`${seconds.toFixed(0)}s · in ${thousands(tokens.input + tokens.cacheRead + tokens.cacheWrite)} out ${thousands(tokens.output)} · agent $${agentCost.toFixed(4)} · judge $${judgeCost.toFixed(4)} · ${calls} tool calls · ${out}`)
  const problems = runs.flatMap(run => [
    ...(run.error ? [`${run.project} ${run.label} ${run.stage}: ${run.error}`] : []),
    ...run.verdicts.filter(verdict => !verdict.pass).map(verdict => `${run.project} ${run.label} ${run.stage}: ${verdict.item}: ${verdict.reason}`),
  ])
  for (const problem of problems) console.log(`  ✗ ${problem}`)
  process.exitCode = problems.length ? 1 : 0
}

function passed(verdicts: Verdict[]): number {
  return verdicts.filter(verdict => verdict.pass).length
}

function thousands(value: number): string {
  return `${(value / 1000).toFixed(1)}k`
}

function sum(requests: Usage[]): Usage {
  return requests.reduce((total, usage) => ({
    input: total.input + usage.input,
    cacheRead: total.cacheRead + usage.cacheRead,
    cacheWrite: total.cacheWrite + usage.cacheWrite,
    output: total.output + usage.output,
  }), { input: 0, cacheRead: 0, cacheWrite: 0, output: 0 })
}

function message(error: unknown): string {
  return error instanceof Failure ? error.message : String(error)
}

async function recorded(file: string): Promise<Overview> {
  const run: { job: { cutoff: string }, outcome?: { result: OverviewResult } } = await Bun.file(file).json()
  if (!run.outcome) exit(`${file} holds no overview.`)
  return { ...run.outcome.result, readAt: run.job.cutoff }
}

function exit(text: string): never {
  console.error(text)
  process.exit(2)
}
