import { expect, test } from "bun:test"
import { cost, priced } from "../src/prices"

const usage = (input: number, output: number, cacheRead = 0, cacheWrite = 0) => ({ input, output, cacheRead, cacheWrite })

test("prices every request at its own rate", () => {
  expect(cost("claude-haiku-5-5", [usage(10_000, 10_000, 10_000, 10_000)])).toBeCloseTo((0.1 + 0.5 + 0.01 + 0.125) / 100, 6)
})

test("uses Haiku's long-prompt rate only for requests above 100K prompt tokens", () => {
  const short = usage(90_000, 1000, 10_000)
  const long = usage(90_000, 1000, 10_001)
  expect(cost("claude-haiku-5-5", [short])).toBeCloseTo((90_000 * 0.1 + 1000 * 0.5 + 10_000 * 0.01) / 1_000_000)
  expect(cost("claude-haiku-5-5", [long])).toBeCloseTo((90_000 * 0.5 + 1000 * 2.5 + 10_001 * 0.05) / 1_000_000)
  expect(cost("claude-haiku-5-5", [short, long])).toBeCloseTo(cost("claude-haiku-5-5", [short]) + cost("claude-haiku-5-5", [long]))
})

test("matches dated model ids but not other models sharing a prefix", () => {
  expect(priced("claude-sonnet-5-5")).toBe(true)
  expect(priced("claude-sonnet-5-5-20261101")).toBe(true)
  expect(priced("claude-sonnet-5")).toBe(false)
  expect(() => cost("gpt-unknown", [usage(1, 1)])).toThrow("No price for gpt-unknown")
})
