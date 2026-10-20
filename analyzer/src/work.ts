import type { PullRequest } from "./schema"

const query = `query($q: String!) {
  search(query: $q, type: ISSUE, first: 100) {
    nodes { ... on PullRequest { number title url state mergedAt updatedAt repository { nameWithOwner } } }
  }
}`

type Node = {
  number: number
  title: string
  url: string
  state: "OPEN" | "MERGED" | "CLOSED"
  mergedAt: string | null
  updatedAt: string
  repository: { nameWithOwner: string }
}

export function pullRequests(response: { data: { search: { nodes: Node[] } } }): PullRequest[] {
  return response.data.search.nodes.map((node) => ({
    repo: node.repository.nameWithOwner,
    number: node.number,
    title: node.title,
    url: node.url,
    state: node.state.toLowerCase() as PullRequest["state"],
    mergedAt: node.mergedAt,
    updatedAt: node.updatedAt,
  }))
}

export async function work(since: string) {
  const day = new Date(since).toISOString().slice(0, 10)
  const gh = Bun.spawn(["gh", "api", "graphql", "-f", `query=${query}`, "-f", `q=is:pr author:@me updated:>=${day}`], {
    stdout: "pipe",
    stderr: "pipe",
  })
  const [output, errors] = await Promise.all([new Response(gh.stdout).text(), new Response(gh.stderr).text()])
  if ((await gh.exited) !== 0) throw new Error(`GitHub CLI could not list your pull requests. ${errors.trim()}`)
  return pullRequests(JSON.parse(output))
}
