export type Source = { name: string; status: "connected" | "needs-auth" | "missing"; detail: string }

async function githubCLI(): Promise<Source> {
  const name = "GitHub"
  if (!Bun.which("gh")) return { name, status: "missing", detail: "Install GitHub CLI with brew install gh" }
  const gh = Bun.spawn(["gh", "api", "user", "--jq", ".login"], { stdout: "pipe", stderr: "ignore" })
  const login = (await new Response(gh.stdout).text()).trim()
  return (await gh.exited) === 0 && login
    ? { name, status: "connected", detail: `GitHub CLI as @${login}` }
    : { name, status: "needs-auth", detail: "Run gh auth login" }
}

export const sources = async () => [await githubCLI()]
