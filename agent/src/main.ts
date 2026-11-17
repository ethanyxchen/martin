import { ZodError } from "zod"
import { Failure } from "./failure"
import { provider as providerNamed } from "./providers"
import type { Provider } from "./providers/provider"
import { runJob } from "./run"
import { type Event, Job, type ProviderName } from "./schema"

export async function serve(input: string, write: (line: string) => void, provider: (name: ProviderName) => Provider = providerNamed): Promise<number> {
  const emit = (event: Event) => write(JSON.stringify(event))
  try {
    const job = Job.parse(JSON.parse(input))
    const { result } = await runJob(job, provider(job.provider), emit)
    emit({ type: "result", result })
    return 0
  } catch (error) {
    emit({ type: "error", message: explain(error) })
    return 1
  }
}

function explain(error: unknown): string {
  if (error instanceof Failure) {
    if (error.cause instanceof Error) console.error(error.cause.message)
    return error.message
  }
  if (error instanceof ZodError || error instanceof SyntaxError) return "The job was malformed."
  console.error(error instanceof Error ? `${error.name}: ${error.message}` : "Unknown error")
  return "Something went wrong."
}

if (import.meta.main) process.exitCode = await serve(await Bun.stdin.text(), line => console.log(line))
