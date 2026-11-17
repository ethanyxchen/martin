import type { Connect } from "./activity"
import { overview } from "./jobs/overview"
import { repositoryLookup } from "./jobs/repositoryLookup"
import type { JobSpec } from "./jobs/spec"
import type { Effort, Outcome, Provider } from "./providers/provider"
import type { Event, Job, LookupResult, OverviewResult } from "./schema"
import type { Tool } from "./tools"

export type Emit = (event: Event) => void

export type Options = { connect?: Connect, model?: string, effort?: Effort }

export async function runJob(job: Job, provider: Provider, emit: Emit, options: Options = {}): Promise<Outcome<OverviewResult | LookupResult>> {
  if (job.kind === "overview") return complete(overview(job, options.connect), provider, emit, options)
  return complete(await repositoryLookup(job), provider, emit, options)
}

async function complete<Result>(spec: JobSpec<Result>, provider: Provider, emit: Emit, options: Options): Promise<Outcome<Result>> {
  const outcome = await provider.run({
    system: spec.system,
    prompt: spec.prompt,
    result: spec.result,
    model: options.model ?? spec.model[provider.name],
    effort: options.effort ?? spec.effort,
    tools: spec.tools.map(tool => reporting(tool, emit)),
  })
  return { ...outcome, result: spec.finish(outcome.result) }
}

function reporting(tool: Tool, emit: Emit): Tool {
  return {
    ...tool,
    run: input => {
      emit({ type: "progress", tool: tool.name, input })
      return tool.run(input)
    },
  }
}
