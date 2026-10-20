import { listen } from "./analyze"
import { sources } from "./sources"
import { work } from "./work"

process.env.PATH = ["/opt/homebrew/bin", "/usr/local/bin", process.env.PATH].filter(Boolean).join(":")
delete process.env.ANTHROPIC_API_KEY

async function run([command, argument]: string[]) {
  if (command === "listen") return listen(await Bun.stdin.json())
  if (command === "work" && argument) return work(argument)
  if (command === "sources") return sources()
  throw new Error(`Unknown command "${command}". Use "listen", "work <since>" or "sources".`)
}

try {
  process.stdout.write(JSON.stringify(await run(process.argv.slice(2))))
  process.exit(0)
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exit(1)
}
