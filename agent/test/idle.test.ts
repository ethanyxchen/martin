import { expect, test } from "bun:test"
import { idleDays } from "../src/idle"

test("weekend days count half, so a branch left Friday at 18:00 turns stale on Monday at 18:00", () => {
  expect(idleDays("2026-11-13T18:00:00-08:00", "2026-11-16T18:00:00-08:00")).toBe(2)
  expect(idleDays("2026-11-13T18:00:00-08:00", "2026-11-16T09:00:00-08:00")).toBeLessThan(2)
})

test("a branch left Tuesday at 18:00 turns stale on Thursday at 18:00", () => {
  expect(idleDays("2026-11-10T18:00:00-08:00", "2026-11-12T18:00:00-08:00")).toBe(2)
  expect(idleDays("2026-11-10T18:00:00-08:00", "2026-11-12T17:00:00-08:00")).toBeLessThan(2)
})

test("days follow the cutoff's time zone, wherever the commit was made", () => {
  expect(idleDays("2026-11-14T02:00:00Z", "2026-11-16T18:00:00-08:00")).toBe(2)
  expect(idleDays("2026-11-14T02:00:00Z", "2026-11-17T02:00:00Z")).toBeCloseTo(49 / 24)
})

test("a commit at or after the cutoff has been idle for no time", () => {
  expect(idleDays("2026-11-16T18:00:00-08:00", "2026-11-16T18:00:00-08:00")).toBe(0)
})
