import { expect, test } from "bun:test"
import { userPrompt } from "./prompt"

test("lists interests, transcript and bullets already written", () => {
  const prompt = userPrompt({
    owner: { name: "Ethan Chen", aliases: ["Ethan"], interests: ["webhooks"] },
    meeting: { title: null, attendees: ["Sarah Lee"], notes: null },
    transcript: ["Ethan, can you look at the auth PR?", "Sure."],
    bullets: [{ kind: "action", text: "Look at the auth PR" }],
  })
  expect(prompt).toBe(`Meeting: Untitled
Attendees: Sarah Lee

Topics the owner follows: webhooks

Transcript so far:
Ethan, can you look at the auth PR?
Sure.

Bullets already written:
- action: Look at the auth PR`)
})

test("says none when there is no bullet yet", () => {
  const prompt = userPrompt({
    owner: { name: "Ethan", aliases: [], interests: [] },
    meeting: { title: "Standup", attendees: [], notes: null },
    transcript: [],
    bullets: [],
  })
  expect(prompt).toBe(`Meeting: Standup

Transcript so far:

Bullets already written:
- none`)
})
