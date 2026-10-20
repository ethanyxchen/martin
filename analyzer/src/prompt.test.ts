import { expect, test } from "bun:test"
import { userPrompt } from "./prompt"

test("lists work, interests, transcript and bullets already written", () => {
  const prompt = userPrompt({
    owner: { name: "Ethan Chen", aliases: ["Ethan"], interests: ["webhooks"] },
    meeting: { title: null, attendees: ["Sarah Lee"], notes: null },
    work: [
      {
        repo: "acme/api",
        number: 412,
        title: "Rate limit webhooks",
        url: "https://github.com/acme/api/pull/412",
        state: "open",
        mergedAt: null,
        updatedAt: "2026-10-19T09:00:00Z",
      },
    ],
    transcript: ["Ethan, can you look at the auth PR?", "Sure."],
    bullets: [{ kind: "action", text: "Look at the auth PR" }],
  })
  expect(prompt).toBe(`Meeting: Untitled
Attendees: Sarah Lee

The owner's recent pull requests:
- acme/api#412 Rate limit webhooks (open)

Topics the owner follows: webhooks

Transcript so far:
Ethan, can you look at the auth PR?
Sure.

Bullets already written:
- action: Look at the auth PR`)
})

test("says none when there is no work or bullet yet", () => {
  const prompt = userPrompt({
    owner: { name: "Ethan", aliases: [], interests: [] },
    meeting: { title: "Standup", attendees: [], notes: null },
    work: [],
    transcript: [],
    bullets: [],
  })
  expect(prompt).toBe(`Meeting: Standup

The owner's recent pull requests:
- none

Transcript so far:

Bullets already written:
- none`)
})
