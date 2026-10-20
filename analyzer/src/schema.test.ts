import { expect, test } from "bun:test"
import Ajv from "ajv"
import { schema, type Bullet } from "./schema"

const validate = new Ajv().compile(schema)

const bullet: Bullet = { kind: "action", text: "Review the rate limiter PR #412 before Thursday" }

test("accepts a valid result", () => {
  expect(validate({ bullets: [bullet] })).toBe(true)
  expect(validate({ bullets: [] })).toBe(true)
})

test("rejects an unknown kind and extra fields", () => {
  expect(validate({ bullets: [{ ...bullet, kind: "todo" }] })).toBe(false)
  expect(validate({ bullets: [{ ...bullet, speaker: "Sarah" }] })).toBe(false)
})
