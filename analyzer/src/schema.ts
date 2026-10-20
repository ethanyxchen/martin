export const kinds = ["action", "decision", "question"] as const

export type Kind = (typeof kinds)[number]

export type Bullet = { kind: Kind; text: string }

export type PullRequest = {
  repo: string
  number: number
  title: string
  url: string
  state: "open" | "merged" | "closed"
  mergedAt: string | null
  updatedAt: string
}

export type Owner = { name: string; aliases: string[]; interests: string[] }

export type Meeting = { title: string | null; attendees: string[]; notes: string | null }

export type Input = { owner: Owner; meeting: Meeting; work: PullRequest[]; transcript: string[]; bullets: Bullet[] }

export const schema = {
  type: "object",
  properties: {
    bullets: {
      type: "array",
      items: {
        type: "object",
        properties: {
          kind: { type: "string", enum: kinds },
          text: { type: "string", maxLength: 90 },
        },
        required: ["kind", "text"],
        additionalProperties: false,
      },
    },
  },
  required: ["bullets"],
  additionalProperties: false,
}
