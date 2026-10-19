import { expect, test } from "bun:test"
import { userPrompt } from "./prompt"

test("lists meeting details and one stamped line per segment", () => {
  const prompt = userPrompt({
    owner: { name: "Ethan Chen", aliases: ["Ethan"] },
    meeting: { title: null, startedAt: "2026-10-19T09:00:00Z", attendees: ["Sarah Lee"], notes: null },
    transcript: [
      { at: 75.4, text: "Ethan, can you look at the auth PR?" },
      { at: 3725, text: "Sure." },
    ],
    connectors: [],
  })
  expect(prompt).toBe(`Started: 2026-10-19T09:00:00Z
Attendees: Sarah Lee

Transcript:
[01:15] Ethan, can you look at the auth PR?
[1:02:05] Sure.`)
})
