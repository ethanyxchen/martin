import type { McpServerStatus } from "@anthropic-ai/claude-agent-sdk"
import { readOnlyTools } from "./access"
import { session } from "./session"

export type Source = { name: string; status: McpServerStatus["status"] | "missing"; detail: string | null }

async function githubCLI(): Promise<Source> {
  const name = "GitHub"
  if (!Bun.which("gh")) return { name, status: "missing", detail: "Install GitHub CLI with brew install gh" }
  const gh = Bun.spawn(["gh", "api", "user", "--jq", ".login"], { stdout: "pipe", stderr: "ignore" })
  const login = (await new Response(gh.stdout).text()).trim()
  return (await gh.exited) === 0 && login
    ? { name, status: "connected", detail: `GitHub CLI as @${login}` }
    : { name, status: "needs-auth", detail: "Run gh auth login" }
}

async function connectors(): Promise<Source[]> {
  const idle: AsyncIterable<never> = { [Symbol.asyncIterator]: () => ({ next: () => new Promise(() => {}) }) }
  const conversation = session(idle, { tools: [] })
  try {
    let servers: McpServerStatus[] = []
    for (let attempt = 0; attempt < 30; attempt++) {
      servers = await conversation.mcpServerStatus()
      if (servers.length > 0 && servers.every((server) => server.status !== "pending")) break
      await Bun.sleep(500)
    }
    return servers.map((server) => ({
      name: server.name.replace(/^claude\.ai /, ""),
      status: server.status,
      detail: server.status === "connected" ? `${readOnlyTools([server]).size} read-only tools` : (server.error ?? null),
    }))
  } finally {
    conversation.close()
  }
}

export const sources = async () => [await githubCLI(), ...(await connectors())]
