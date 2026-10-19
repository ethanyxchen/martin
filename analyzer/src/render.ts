import type { Item, Kind } from "./schema"

const headings: Record<Kind, string> = {
  todo: "To do",
  waiting_on: "Waiting on",
  decision: "Decisions",
  fyi: "Worth knowing",
}

const order = Object.keys(headings) as Kind[]

export function timestamp(seconds: number) {
  const total = Math.floor(seconds)
  const [h, m, s] = [Math.floor(total / 3600), Math.floor((total % 3600) / 60), total % 60]
  const pad = (n: number) => String(n).padStart(2, "0")
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${pad(m)}:${pad(s)}`
}

function entry(item: Item) {
  const box = item.kind === "todo" || item.kind === "waiting_on" ? "[ ] " : ""
  const links = item.links.map((link) => `[${link.label}](${link.url})`).join(", ")
  return [
    `- ${box}${item.title}${links && ` — ${links}`}`,
    ...(item.detail ? [`  ${item.detail}`] : []),
    `  > "${item.quote}" · ${timestamp(item.at)}`,
  ].join("\n")
}

function section(heading: string, items: Item[]) {
  const sorted = items.toSorted((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind) || a.at - b.at)
  return [`## ${heading}`, ...sorted.map(entry)].join("\n")
}

export function render(items: Item[]) {
  const sure = items.filter((item) => item.confidence === "high")
  const maybe = items.filter((item) => item.confidence === "maybe")
  const sections = [
    ...order.map((kind) => [headings[kind], sure.filter((item) => item.kind === kind)] as const),
    ["Maybe", maybe] as const,
  ].filter(([, group]) => group.length > 0)
  if (sections.length === 0) return "Nothing in this meeting needed you.\n"
  return sections.map(([heading, group]) => section(heading, group)).join("\n\n") + "\n"
}
