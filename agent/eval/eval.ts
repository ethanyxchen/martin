import { mkdir } from "node:fs/promises"
import { join } from "node:path"
import { parseArgs } from "node:util"
import { Failure } from "../src/failure"
import { models } from "../src/jobs/overview"
import { provider } from "../src/providers"
import type { Effort, Outcome, Usage } from "../src/providers/provider"
import { runJob } from "../src/run"
import type { Overview, OverviewResult, ProviderName } from "../src/schema"
import { invariants, judge, judgeModel, type Kind, material, type Verdict } from "./judge"
import { cost, priced } from "./prices"
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
    model: { type: "string" },
    effort: { type: "string" },
    out: { type: "string" },
  },
})

const name = values.provider as ProviderName
const model = values.model ?? models[name]
if (!priced(model)) exit(`No price for ${model}, so its runs can't be costed. Add it to eval/prices.ts.`)
const selected = await projects(join(import.meta.dir, "..", "fixtures"), values.project)
if (!selected.length) exit(values.project ? `No project named ${values.project}.` : "No projects in fixtures/.")
const out = values.out ?? join(import.meta.dir, "out", `${new Date().toISOString().replace(/[:.]/g, "-")}-${model}`)
const cache = join(import.meta.dir, "cache")
const agent = provider(name)
const grader = provider("anthropic")
console.log(`${selected.map(project => project.scenario.project).join(", ")} · ${model}${values.effort ? ` · ${values.effort}` : ""} · judged by ${judgeModel}\n`)

const runs = (await Promise.all(selected.map(replay))).flat()
await Bun.write(join(out, "summary.json"), JSON.stringify({ model, effort: values.effort ?? null, judge: judgeModel, runs }, null, 2))
report(runs)

async function replay(project: Project): Promise<Run[]> {
  await mkdir(join(out, project.id), { recursive: true })
  const runs: Run[] = []
  let previous: Overview | null = null
  for (const stage of project.stages) {
    const run = await attempt(project, stage, previous, "chained")
    runs.push(run)
    if (!run.outcome) break
    previous = { ...run.outcome.result, readAt: stage.cutoff }
  }
  const last = project.stages.at(-1)
  if (values.scratch && last) runs.push(await attempt(project, last, null, "scratch"))
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
  const head = `${run.project.padEnd(10)} ${run.label.padEnd(8)} ${run.stage.padEnd(26)} ${run.seconds.toFixed(1).padStart(6)}s`
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
    `${passed(run.verdicts)}/${run.verdicts.length}`,
    run.error ?? "",
  ].filter(Boolean).join("  ")
}

function report(runs: Run[]) {
  const verdicts = runs.flatMap(run => run.verdicts)
  const kinds: Kind[] = ["section", "caption", "date", "order", "precision", "invariant"]
  const projectsLine = [...new Set(runs.map(run => run.project))].map(project => {
    const group = runs.filter(run => run.project === project).flatMap(run => run.verdicts)
    return `${project} ${passed(group)}/${group.length}`
  })
  const kindsLine = kinds.flatMap(kind => {
    const group = verdicts.filter(verdict => verdict.kind === kind)
    return group.length ? [`${kind} ${passed(group)}/${group.length}`] : []
  })
  const completed = runs.flatMap(run => run.outcome ? [run] : [])
  const tokens = sum(completed.flatMap(run => run.outcome!.requests))
  const seconds = runs.reduce((total, run) => total + run.seconds, 0)
  const agentCost = completed.reduce((total, run) => total + run.cost!, 0)
  const judgeCost = runs.reduce((total, run) => total + (run.judge?.cost ?? 0), 0)
  const calls = runs.reduce((total, run) => total + run.calls.length, 0)
  console.log(`\n${passed(verdicts)}/${verdicts.length} passed · ${projectsLine.join(" · ")}`)
  console.log(kindsLine.join(" · "))
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

function exit(text: string): never {
  console.error(text)
  process.exit(2)
}
