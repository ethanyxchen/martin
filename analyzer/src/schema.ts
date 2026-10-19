export const kinds = ["todo", "waiting_on", "decision", "fyi"] as const

export type Kind = (typeof kinds)[number]

export type Link = { label: string; url: string }

export type Item = {
  kind: Kind
  title: string
  detail: string
  quote: string
  at: number
  confidence: "high" | "maybe"
  links: Link[]
}

export type Owner = { name: string; aliases: string[] }

export type Meeting = { title: string | null; startedAt: string; attendees: string[]; notes: string | null }

export type Segment = { at: number; text: string }

export type Input = { owner: Owner; meeting: Meeting; transcript: Segment[] }

export const schema = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          kind: { type: "string", enum: kinds },
          title: { type: "string", maxLength: 100 },
          detail: { type: "string" },
          quote: { type: "string" },
          at: { type: "number" },
          confidence: { type: "string", enum: ["high", "maybe"] },
          links: {
            type: "array",
            items: {
              type: "object",
              properties: { label: { type: "string" }, url: { type: "string" } },
              required: ["label", "url"],
              additionalProperties: false,
            },
          },
        },
        required: ["kind", "title", "detail", "quote", "at", "confidence", "links"],
        additionalProperties: false,
      },
    },
  },
  required: ["items"],
  additionalProperties: false,
}
