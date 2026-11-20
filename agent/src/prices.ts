import type { Usage } from "./providers/provider"

type Rate = { input: number, output: number, cacheRead: number, cacheWrite: number }
type Price = { model: string, rate: Rate, longPrompt?: { above: number, rate: Rate } }

const prices: Price[] = [
  { model: "claude-opus-5-5", rate: { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 } },
  { model: "claude-sonnet-5-5", rate: { input: 2, output: 10, cacheRead: 0.1, cacheWrite: 2.5 } },
  {
    model: "claude-haiku-5-5",
    rate: { input: 0.1, output: 0.5, cacheRead: 0.01, cacheWrite: 0.125 },
    longPrompt: { above: 100_000, rate: { input: 0.5, output: 2.5, cacheRead: 0.05, cacheWrite: 0.625 } },
  },
]

export function priced(model: string): boolean {
  return find(model) !== undefined
}

export function cost(model: string, requests: Usage[]): number {
  const price = find(model)
  if (!price) throw new Error(`No price for ${model}. Add it to src/prices.ts.`)
  return requests.reduce((total, usage) => {
    const prompt = usage.input + usage.cacheRead + usage.cacheWrite
    const rate = price.longPrompt && prompt > price.longPrompt.above ? price.longPrompt.rate : price.rate
    return total + (usage.input * rate.input + usage.output * rate.output + usage.cacheRead * rate.cacheRead + usage.cacheWrite * rate.cacheWrite) / 1_000_000
  }, 0)
}

function find(model: string): Price | undefined {
  return prices.find(price => model === price.model || model.startsWith(`${price.model}-`))
}
