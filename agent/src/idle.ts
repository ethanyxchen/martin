const dayLength = 24 * 60 * 60 * 1000

export const staleDays = 2

export function idleDays(from: string, cutoff: string): number {
  const shift = offset(cutoff)
  const end = Date.parse(cutoff) + shift
  let start = Date.parse(from) + shift
  let days = 0
  while (start < end) {
    const midnight = (Math.floor(start / dayLength) + 1) * dayLength
    const weekend = [0, 6].includes(new Date(start).getUTCDay())
    days += (Math.min(midnight, end) - start) / dayLength * (weekend ? 0.5 : 1)
    start = midnight
  }
  return days
}

function offset(timestamp: string): number {
  const match = timestamp.match(/([+-])(\d{2}):(\d{2})$/)
  if (!match) return 0
  const [, sign, hours, minutes] = match
  return (sign === "-" ? -1 : 1) * (Number(hours) * 60 + Number(minutes)) * 60 * 1000
}
