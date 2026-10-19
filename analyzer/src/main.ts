import { analyze } from "./analyze"
import { check } from "./check"
import { render } from "./render"

async function run(command: string | undefined) {
  const input = await Bun.stdin.json()
  if (command === undefined) return render(await analyze(input))
  if (command === "check") return JSON.stringify(await check(input.connectors))
  throw new Error(`Unknown command "${command}". Use no arguments to analyze, or "check".`)
}

try {
  process.stdout.write(await run(process.argv[2]))
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exit(1)
}
