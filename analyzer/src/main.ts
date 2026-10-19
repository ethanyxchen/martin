import { analyze } from "./analyze"
import { render } from "./render"
import { sources } from "./sources"

process.env.PATH = ["/opt/homebrew/bin", "/usr/local/bin", process.env.PATH].filter(Boolean).join(":")
delete process.env.ANTHROPIC_API_KEY

async function run(command: string | undefined) {
  if (command === undefined) return render(await analyze(await Bun.stdin.json()))
  if (command === "sources") return JSON.stringify(await sources())
  throw new Error(`Unknown command "${command}". Use no arguments to analyze, or "sources".`)
}

try {
  process.stdout.write(await run(process.argv[2]))
  process.exit(0)
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exit(1)
}
