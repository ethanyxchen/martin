import type { HookCallback, McpServerStatus } from "@anthropic-ai/claude-agent-sdk"

const ghReads = [
  /^gh (pr|issue) (list|view|status|checks|diff)( |$)/,
  /^gh search (prs|issues|commits|repos|code)( |$)/,
  /^gh (repo|run|release) (list|view)( |$)/,
  /^gh api \S/,
]

const writeFlag = /^(-X|--method|-f|-F|--field|--raw-field|--input)/

export function readOnlyCommand(command: string) {
  const trimmed = command.trim()
  return (
    !/[;&|`$<>\n\\]/.test(trimmed) &&
    ghReads.some((pattern) => pattern.test(trimmed)) &&
    !trimmed.split(/\s+/).some((word) => writeFlag.test(word))
  )
}

export function readOnlyTools(servers: McpServerStatus[]) {
  return new Set(
    servers.flatMap((server) =>
      (server.tools ?? [])
        .filter((tool) => tool.annotations?.readOnly === true)
        .map((tool) => `mcp__${server.name.replace(/[^a-zA-Z0-9_-]/g, "_")}__${tool.name}`),
    ),
  )
}

const decide = (allowed: boolean, reason: string) => ({
  hookSpecificOutput: {
    hookEventName: "PreToolUse" as const,
    permissionDecision: allowed ? ("allow" as const) : ("deny" as const),
    permissionDecisionReason: reason,
  },
})

export function gate(tools: () => Promise<Set<string>>): HookCallback {
  return async (input) => {
    if (input.hook_event_name !== "PreToolUse") return {}
    if (input.tool_name === "StructuredOutput") return decide(true, "Final answer")
    if (input.tool_name === "Bash") {
      const command = String((input.tool_input as { command?: unknown }).command ?? "")
      return readOnlyCommand(command)
        ? decide(true, "Read-only GitHub CLI command")
        : decide(false, "Only read-only gh commands are allowed, without pipes or shell operators.")
    }
    return (await tools()).has(input.tool_name)
      ? decide(true, "Read-only tool")
      : decide(false, "Martin only reads. This tool is not marked read-only.")
  }
}
