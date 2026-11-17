export function characters(text: string): string[] {
  return Array.from(text)
}

export function prefix(text: string, length: number): string {
  return characters(text).slice(0, length).join("")
}

export function day(timestamp: string): string {
  return timestamp.slice(0, 10)
}
