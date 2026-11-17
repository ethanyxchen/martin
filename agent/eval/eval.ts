import { mkdir } from "node:fs/promises"
import { join } from "node:path"
import { parseArgs } from "node:util"
import { Failure } from "../src/failure"
import { provider } from "../src/providers"
import type { Effort, Usage } from "../src/providers/provider"
import { runJob } from "../src/run"
import { type Overview, type OverviewResult, type ProviderName } from "../src/schema"
import { type Check, check, fixtures, library, type Stage, type Suite } from "./stages"

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

const prices: [string, { input: number, output: number, cacheRead: number, cacheWrite: number }][] = [
  ["claude-opus-5-5", { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 }],
  ["claude-sonnet-5-5", { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 }],
]

type Run = {
  label: string
  stage: string
  model: string | null
  seconds: number
  usage: Usage | null
  cost: number | null
  calls: { tool: string, input: unknown }[]
  result: OverviewResult | null
  error: string | null
  checks: Check[]
}

const name = values.provider as ProviderName
const suite = await load()
const out = values.out ?? join(import.meta.dir, "out", `${new Date().toISOString().replace(/[:.]/g, "-")}-${name}`)
await mkdir(out, { recursive: true })
console.log(`${suite.kind} · ${suite.project} · ${name}${values.model ? ` · ${values.model}` : ""}${values.effort ? ` · ${values.effort}` : ""}\n`)

const runs: Run[] = []
let previous: Overview | null = null
for (const stage of suite.stages) {
  const run = await attempt(stage, previous, "chained")
  runs.push(run)
  if (!run.result) break
  previous = { ...run.result, readAt: stage.cutoff }
}
const last = suite.stages.at(-1)
if (values.scratch && last) runs.push(await attempt(last, null, "scratch"))

await Bun.write(join(out, "summary.json"), JSON.stringify(runs, null, 2))
const failed = runs.flatMap(run => run.checks.filter(item => !item.pass).map(item => `${run.label} ${run.stage}: ${item.task} expected ${item.in}, found ${item.found}`))
const errors = runs.filter(run => run.error).map(run => `${run.label} ${run.stage}: ${run.error}`)
const total = runs.reduce((sum, run) => sum + (run.cost ?? 0), 0)
const checks = runs.flatMap(run => run.checks)
console.log(`\n${checks.filter(item => item.pass).length}/${checks.length} checks · ${runs.reduce((sum, run) => sum + run.seconds, 0).toFixed(0)}s${runs.some(run => run.cost !== null) ? ` · $${total.toFixed(2)}` : ""} · ${out}`)
for (const line of [...errors, ...failed]) console.log(`  ✗ ${line}`)
process.exitCode = errors.length || failed.length ? 1 : 0

async function load(): Promise<Suite> {
  if (values.fixtures) return fixtures(values.fixtures)
  if (values.data && values.project && values.snapshots) return library(values.data, values.project, values.snapshots.split(","))
  console.error("Usage: bun run eval --provider anthropic|openai (--fixtures <folder> | --data <library> --project <name> --snapshots <YYYY-MM-DD,...>) [--scratch] [--model <id>] [--effort low|medium|high|xhigh] [--out <folder>]")
  process.exit(2)
}

async function attempt(stage: Stage, previous: Overview | null, label: string): Promise<Run> {
  const calls: Run["calls"] = []
  const started = performance.now()
  const job = { kind: "overview" as const, provider: name, project: { name: suite.project }, cutoff: stage.cutoff, previous, notes: stage.notes, repository: suite.repository }
  const run: Run = { label, stage: stage.name, model: null, seconds: 0, usage: null, cost: null, calls, result: null, error: null, checks: [] }
  try {
    const outcome = await runJob(job, provider(name), event => event.type === "progress" && calls.push({ tool: event.tool, input: event.input }), {
      connect: suite.connect,
      model: values.model,
      effort: values.effort as Effort | undefined,
    })
    run.model = outcome.model
    run.usage = outcome.usage
    run.cost = cost(outcome.model, outcome.usage)
    run.result = outcome.result as OverviewResult
    run.checks = check(run.result, stage.expect)
  } catch (error) {
    run.error = error instanceof Failure ? error.message : String(error)
  }
  run.seconds = (performance.now() - started) / 1000
  await Bun.write(join(out, `${label}-${stage.name}.json`), JSON.stringify({ job, ...run }, null, 2))
  console.log(line(run))
  return run
}

function cost(model: string, usage: Usage): number | null {
  const price = prices.find(([prefix]) => model.startsWith(prefix))?.[1]
  if (!price) return null
  return (usage.input * price.input + usage.output * price.output + usage.cacheRead * price.cacheRead + usage.cacheWrite * price.cacheWrite) / 1_000_000
}

function line(run: Run): string {
  const head = `${run.label.padEnd(8)} ${run.stage.padEnd(26)} ${run.seconds.toFixed(1).padStart(6)}s`
  if (run.error || !run.usage) return `${head}  error: ${run.error}`
  const thousands = (value: number) => `${(value / 1000).toFixed(1)}k`
  const passed = run.checks.filter(item => item.pass).length
  return [
    head,
    `${run.usage.requests} req`,
    `in ${thousands(run.usage.input)}`,
    `cached ${thousands(run.usage.cacheRead + run.usage.cacheWrite)}`,
    `out ${thousands(run.usage.output)}`,
    run.cost === null ? "" : `$${run.cost.toFixed(3)}`,
    `${run.calls.length} calls`,
    run.checks.length ? `${passed}/${run.checks.length} checks` : "",
  ].filter(Boolean).join("  ")
}
