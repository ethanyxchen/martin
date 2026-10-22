import { listen } from "./analyze"

delete process.env.ANTHROPIC_API_KEY

async function run([command]: string[]) {
  if (command === "listen") return listen(await Bun.stdin.json())
  throw new Error(`Unknown command "${command}". Use "listen".`)
}

try {
  process.stdout.write(JSON.stringify(await run(process.argv.slice(2))))
  process.exit(0)
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error))
  process.exit(1)
}
