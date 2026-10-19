import { expect, test } from "bun:test"
import { render, timestamp } from "./render"
import type { Item } from "./schema"

test("formats timestamps", () => {
  expect(timestamp(0)).toBe("00:00")
  expect(timestamp(75.4)).toBe("01:15")
  expect(timestamp(3725)).toBe("1:02:05")
})

const items: Item[] = [
  {
    kind: "fyi",
    title: "Postgres 16 goes to production next Tuesday",
    detail: "Expect about ten minutes of read-only mode.",
    quote: "I want to do production next Tuesday early morning",
    at: 47,
    confidence: "maybe",
    links: [],
  },
  {
    kind: "waiting_on",
    title: "Priya sends the new Stripe sandbox keys",
    detail: "",
    quote: "I'll send you the new Stripe sandbox keys right after standup.",
    at: 128.6,
    confidence: "high",
    links: [],
  },
  {
    kind: "todo",
    title: "Review the rate limiter PR before the release cut",
    detail: "It touches the webhook endpoints.",
    quote: "Eathan, can you take a look at the rate limiter PR before the release cut on Thursday?",
    at: 191.2,
    confidence: "high",
    links: [
      { label: "PR #412", url: "https://github.com/acme/api/pull/412" },
      { label: "ENG-88", url: "https://linear.app/acme/issue/ENG-88" },
    ],
  },
  {
    kind: "todo",
    title: "Add dead letter queue metrics to the webhook dashboard",
    detail: "",
    quote: "I'll add the dead letter queue metrics to the webhook dashboard by tomorrow",
    at: 80.3,
    confidence: "high",
    links: [],
  },
  {
    kind: "decision",
    title: "Webhook retries use exponential backoff capped at one hour",
    detail: "",
    quote: "we're going with exponential backoff capped at one hour for webhooks",
    at: 3725,
    confidence: "high",
    links: [],
  },
]

test("renders a calm note grouped by kind", () => {
  expect(render(items)).toBe(`## To do
- [ ] Add dead letter queue metrics to the webhook dashboard
  > "I'll add the dead letter queue metrics to the webhook dashboard by tomorrow" · 01:20
- [ ] Review the rate limiter PR before the release cut — [PR #412](https://github.com/acme/api/pull/412), [ENG-88](https://linear.app/acme/issue/ENG-88)
  It touches the webhook endpoints.
  > "Eathan, can you take a look at the rate limiter PR before the release cut on Thursday?" · 03:11

## Waiting on
- [ ] Priya sends the new Stripe sandbox keys
  > "I'll send you the new Stripe sandbox keys right after standup." · 02:08

## Decisions
- Webhook retries use exponential backoff capped at one hour
  > "we're going with exponential backoff capped at one hour for webhooks" · 1:02:05

## Maybe
- Postgres 16 goes to production next Tuesday
  Expect about ten minutes of read-only mode.
  > "I want to do production next Tuesday early morning" · 00:47
`)
})

test("renders a single line when nothing needed the owner", () => {
  expect(render([])).toBe("Nothing in this meeting needed you.\n")
})
