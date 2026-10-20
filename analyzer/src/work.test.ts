import { expect, test } from "bun:test"
import { pullRequests } from "./work"

test("flattens GitHub search results", () => {
  const response = {
    data: {
      search: {
        nodes: [
          {
            number: 412,
            title: "Rate limit webhooks",
            url: "https://github.com/acme/api/pull/412",
            state: "MERGED" as const,
            mergedAt: "2026-10-19T08:00:00Z",
            updatedAt: "2026-10-19T08:01:00Z",
            repository: { nameWithOwner: "acme/api" },
          },
        ],
      },
    },
  }
  expect(pullRequests(response)).toEqual([
    {
      repo: "acme/api",
      number: 412,
      title: "Rate limit webhooks",
      url: "https://github.com/acme/api/pull/412",
      state: "merged",
      mergedAt: "2026-10-19T08:00:00Z",
      updatedAt: "2026-10-19T08:01:00Z",
    },
  ])
})
