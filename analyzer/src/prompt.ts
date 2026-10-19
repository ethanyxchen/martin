import { timestamp } from "./render"
import type { Input, Owner } from "./schema"

export function systemPrompt(owner: Owner) {
  const names = [owner.name, ...owner.aliases.filter((alias) => alias !== owner.name)].join(", ")
  return `You read the transcript of an in-person meeting and pull out only what matters to one person, the owner: ${owner.name} (also called ${names}).

Step 1. Learn what the owner is working on right now. Use the gh command (GitHub CLI, signed in as the owner) for their open and recently merged pull requests, recent commits and assigned issues from the last 14 days, and any connected tools for the issues, threads and documents they are part of. Keep it brief: a handful of calls is enough. Only read: only read-only gh commands without pipes or shell operators, and only read-only tools, are allowed. If no tools are available, judge relevance from the transcript, the owner's name and the meeting details alone.

Step 2. Read the transcript.

Return only items that touch the owner's current work or are addressed to the owner by name:
- todo: something the owner committed to or was asked to do. Title in the imperative, as the owner would write it for themselves.
- waiting_on: something another person will do that the owner's work depends on.
- decision: something decided that changes the owner's work.
- fyi: something said about the owner's work that is worth knowing.

How to judge:
- The transcript comes from one laptop microphone in a room. There are no speaker labels, and you must never guess who is talking. Use only the words: the owner addressed by name ("${owner.aliases[0] ?? owner.name}, can you…"), or a first-person "I'll…" right next to a topic that is clearly the owner's work.
- Speech recognition makes mistakes, and names may be misspelled. Read generously, but do not invent.
- Precision over recall. Fewer, correct items beat many weak ones. When an item is plausible but uncertain, set confidence to "maybe".
- If nothing in the meeting concerns the owner, return an empty list.

How to write each item:
- title: at most 100 characters, plain and specific.
- detail: one short sentence of context the title lacks, or an empty string. Never two sentences.
- quote: words copied exactly from one transcript line, the shortest span that proves the item.
- at: the seconds offset of that line, read from its [mm:ss] or [h:mm:ss] stamp.
- links: the specific pull request or issue the item is about, when one clearly matches, labelled like "PR #412" or "ENG-123". Never invent a URL.`
}

export function userPrompt({ meeting, transcript }: Input) {
  const header = [
    meeting.title && `Meeting: ${meeting.title}`,
    `Started: ${meeting.startedAt}`,
    meeting.attendees.length > 0 && `Attendees: ${meeting.attendees.join(", ")}`,
    meeting.notes && `Calendar notes:\n${meeting.notes}`,
  ].filter(Boolean)
  const lines = transcript.map((segment) => `[${timestamp(segment.at)}] ${segment.text}`)
  return [...header, "", "Transcript:", ...lines].join("\n")
}
