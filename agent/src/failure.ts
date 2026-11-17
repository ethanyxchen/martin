export class Failure extends Error {}

export function apiFailure(provider: string, error: Error & { status?: number }): Failure {
  const cause = { cause: error }
  const status = error.status
  if (status === undefined) return new Failure(`Couldn't reach ${provider}.`, cause)
  if (status === 401) return new Failure(`The ${provider} API key was rejected.`, cause)
  if (status === 403) return new Failure(`This ${provider} API key can't use the model.`, cause)
  if (status === 429) return new Failure(`${provider} is rate limiting requests. Try again later.`, cause)
  if (status >= 500) return new Failure(`${provider} is having trouble. Try again later.`, cause)
  return new Failure(`${provider} returned an error (${status}).`, cause)
}
