import { expect, test } from "bun:test"
import Ajv from "ajv"
import { schema, type Item } from "./schema"

const validate = new Ajv().compile(schema)

const item: Item = {
  kind: "todo",
  title: "Review the rate limiter PR before Thursday's release cut",
  detail: "",
  quote: "can you take a look at the rate limiter PR before the release cut on Thursday?",
  at: 191.2,
  confidence: "high",
  links: [{ label: "PR #412", url: "https://github.com/acme/api/pull/412" }],
}

test("accepts a valid result", () => {
  expect(validate({ items: [item] })).toBe(true)
})

test("rejects an unknown kind and extra fields", () => {
  expect(validate({ items: [{ ...item, kind: "request" }] })).toBe(false)
  expect(validate({ items: [{ ...item, speaker: "Sarah" }] })).toBe(false)
})
