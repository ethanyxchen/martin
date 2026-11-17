import type { Request } from "../providers/provider"
import type { ProviderName } from "../schema"

export type JobSpec<Result> = Omit<Request<Result>, "model"> & {
  model: Record<ProviderName, string>
  finish: (result: Result) => Result
}
