import type { Connect } from "./activity"
import { overview } from "./jobs/overview"
import { repositoryLookup } from "./jobs/repositoryLookup"
import type { Effort, Emit, JobSpec, Outcome, Provider } from "./providers/provider"
import type { Job, LookupResult, OverviewResult } from "./schema"

export type Options = { connect?: Connect, model?: string, effort?: Effort }

export async function runJob(job: Job, provider: Provider, emit: Emit, options: Options = {}): Promise<Outcome<OverviewResult | LookupResult>> {
  return job.kind === "overview"
    ? complete(tune(overview(job, options.connect), options), provider, emit)
    : complete(tune(await repositoryLookup(job), options), provider, emit)
}

async function complete<Result>(spec: JobSpec<Result>, provider: Provider, emit: Emit): Promise<Outcome<Result>> {
  const outcome = await provider.run(spec, emit)
  return { ...outcome, result: spec.finish(outcome.result) }
}

function tune<Result>(spec: JobSpec<Result>, options: Options): JobSpec<Result> {
  return {
    ...spec,
    model: options.model ? { anthropic: options.model, openai: options.model } : spec.model,
    effort: options.effort ?? spec.effort,
  }
}
