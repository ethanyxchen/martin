import { mkdir } from "node:fs/promises"
import { join } from "node:path"
import { parseArgs } from "node:util"
import { Failure } from "../src/failure"
import { models } from "../src/jobs/overview"
import { provider } from "../src/providers"
import type { Effort, Outcome, Usage } from "../src/providers/provider"
import { runJob } from "../src/run"
import type { Overview, OverviewResult, ProviderName } from "../src/schema"
import { cost, priced } from "./prices"
import { type Check, check, fixtures, library, type Stage, type Suite } from "./stages"

type Run = { label: string, stage: string, seconds: number, calls: { tool: string, input: unknown }[] } & (
  | { error: string }
  | { outcome: Outcome<OverviewResult>, cost: number, checks: Check[] }
)

const usage = "Usage: bun run eval --provider anthropic|openai (--fixtures <folder> | --data <library> --project <name> --snapshots <YYYY-MM-DD,...>) [--scratch] [--model <id>] [--effort low|medium|high|xhigh] [--out <folder>]"

const { values } = parseArgs({
  options: {
    provider: { type: "string", default: "anthropic" },
    fixtures: { type: "string" },
    data: { type: "string" },
    project: { type: "string" },
    snapshots: { type: "string" },
    scratch: { type: "boolean", default: false },
    model: { type: "string" },
    effort: { type: "string" },
    out: { type: "string" },
  },
})

const name = values.provider as ProviderName
const model = values.model ?? models[name]
if (!priced(model)) exit(`No price for ${model}, so its runs can't be costed. Add it to eval/prices.ts.`)
const suite = await load()
const out = values.out ?? join(import.meta.dir, "out", `${new Date().toISOString().replace(/[:.]/g, "-")}-${model}`)
await mkdir(out, { recursive: true })
console.log(`${suite.kind} · ${suite.project} · ${model}${values.effort ? ` · ${values.effort}` : ""}\n`)

const runs: Run[] = []
let previous: Overview | null = null
for (const stage of suite.stages) {
  const run = await attempt(stage, previous, "chained")
  runs.push(run)
  if ("error" in run) break
  previous = { ...run.outcome.result, readAt: stage.cutoff }
}
const last = suite.stages.at(-1)
if (values.scratch && last) runs.push(await attempt(last, null, "scratch"))

await Bun.write(join(out, "summary.json"), JSON.stringify(runs, null, 2))
report(runs)

async function load(): Promise<Suite> {
  if (values.fixtures) return fixtures(values.fixtures)
  if (values.data && values.project && values.snapshots) return library(values.data, values.project, values.snapshots.split(","))
  return exit(usage)
}

async function attempt(stage: Stage, previous: Overview | null, label: string): Promise<Run> {
  const calls: Run["calls"] = []
  const job = { kind: "overview" as const, provider: name, project: { name: suite.project }, cutoff: stage.cutoff, previous, notes: stage.notes, repository: suite.repository }
  const started = performance.now()
  const seconds = () => (performance.now() - started) / 1000
  let run: Run
  try {
    const outcome = await runJob(job, provider(name), event => event.type === "progress" && calls.push({ tool: event.tool, input: event.input }), {
      connect: suite.connect,
      model,
      effort: values.effort as Effort | undefined,
    }) as Outcome<OverviewResult>
    run = { label, stage: stage.name, seconds: seconds(), calls, outcome, cost: cost(outcome.model, outcome.requests), checks: check(outcome.result, stage.expect) }
  } catch (error) {
    run = { label, stage: stage.name, seconds: seconds(), calls, error: error instanceof Failure ? error.message : String(error) }
  }
  await Bun.write(join(out, `${label}-${stage.name}.json`), JSON.stringify({ job, ...run }, null, 2))
  console.log(line(run))
  return run
}

function line(run: Run): string {
  const head = `${run.label.padEnd(8)} ${run.stage.padEnd(26)} ${run.seconds.toFixed(1).padStart(6)}s`
  if ("error" in run) return `${head}  error: ${run.error}`
  const total = sum(run.outcome.requests)
  const thousands = (value: number) => `${(value / 1000).toFixed(1)}k`
  return [
    head,
    `$${run.cost.toFixed(4)}`,
    `${run.outcome.requests.length} req`,
    `in ${thousands(total.input)}`,
    `cached ${thousands(total.cacheRead + total.cacheWrite)}`,
    `out ${thousands(total.output)}`,
    `${run.calls.length} calls`,
    run.checks.length ? `${run.checks.filter(item => item.pass).length}/${run.checks.length} checks` : "",
  ].filter(Boolean).join("  ")
}

function report(runs: Run[]) {
  const completed = runs.flatMap(run => "error" in run ? [] : [run])
  const checks = completed.flatMap(run => run.checks)
  const problems = runs.flatMap(run => "error" in run
    ? [`${run.label} ${run.stage}: ${run.error}`]
    : run.checks.filter(item => !item.pass).map(item => `${run.label} ${run.stage}: ${item.task} expected ${item.in}, found ${item.found}`))
  const seconds = runs.reduce((total, run) => total + run.seconds, 0)
  const dollars = completed.reduce((total, run) => total + run.cost, 0)
  console.log(`\n${checks.filter(item => item.pass).length}/${checks.length} checks · ${seconds.toFixed(0)}s · $${dollars.toFixed(4)} · ${out}`)
  for (const problem of problems) console.log(`  ✗ ${problem}`)
  process.exitCode = problems.length ? 1 : 0
}

function sum(requests: Usage[]): Usage {
  return requests.reduce((total, usage) => ({
    input: total.input + usage.input,
    cacheRead: total.cacheRead + usage.cacheRead,
    cacheWrite: total.cacheWrite + usage.cacheWrite,
    output: total.output + usage.output,
  }), { input: 0, cacheRead: 0, cacheWrite: 0, output: 0 })
}

function exit(message: string): never {
  console.error(message)
  process.exit(2)
}
