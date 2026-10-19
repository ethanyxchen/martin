import { expect, test } from "bun:test"
import { gate, readOnlyCommand, readOnlyTools } from "./access"

test("allows read-only gh commands", () => {
  expect(readOnlyCommand("gh pr list --author @me --state merged")).toBe(true)
  expect(readOnlyCommand("gh issue view 12 --repo acme/api")).toBe(true)
  expect(readOnlyCommand("gh search prs --author @me --updated >2026-10-01")).toBe(false)
  expect(readOnlyCommand("gh search prs --author @me")).toBe(true)
  expect(readOnlyCommand("gh api user")).toBe(true)
  expect(readOnlyCommand("gh api repos/acme/api/commits --jq .[].sha")).toBe(true)
})

test("refuses writes, other programs and shell operators", () => {
  expect(readOnlyCommand("gh pr merge 12")).toBe(false)
  expect(readOnlyCommand("gh pr comment 12 --body hi")).toBe(false)
  expect(readOnlyCommand("gh api -X DELETE repos/acme/api")).toBe(false)
  expect(readOnlyCommand("gh api repos/acme/api/issues -f title=x")).toBe(false)
  expect(readOnlyCommand("gh api --method=POST repos/acme/api/issues")).toBe(false)
  expect(readOnlyCommand("gh api -XPOST repos/acme/api/issues")).toBe(false)
  expect(readOnlyCommand("gh pr list; rm -rf ~")).toBe(false)
  expect(readOnlyCommand("gh pr list && cat ~/.ssh/id_rsa")).toBe(false)
  expect(readOnlyCommand("gh pr view $(whoami)")).toBe(false)
  expect(readOnlyCommand("cat ~/.zshrc")).toBe(false)
})

test("keeps only tools their server marks read-only", () => {
  const tools = readOnlyTools([
    {
      name: "claude.ai Slack",
      status: "connected",
      tools: [
        { name: "slack_read_channel", annotations: { readOnly: true } },
        { name: "slack_send_message", annotations: {} },
        { name: "slack_search", annotations: { readOnly: false } },
      ],
    },
  ])
  expect([...tools]).toEqual(["mcp__claude_ai_Slack__slack_read_channel"])
})

test("gate allows read-only tools and denies everything else", async () => {
  const check = gate(async () => new Set(["mcp__claude_ai_Slack__slack_read_channel"]))
  const decision = async (tool_name: string, tool_input: unknown = {}) => {
    const output = await check(
      { hook_event_name: "PreToolUse", tool_name, tool_input, tool_use_id: "1", session_id: "s", transcript_path: "", cwd: "/" },
      "1",
      { signal: AbortSignal.timeout(1000) },
    )
    return "hookSpecificOutput" in output ? (output.hookSpecificOutput as { permissionDecision: string }).permissionDecision : undefined
  }
  expect(await decision("mcp__claude_ai_Slack__slack_read_channel")).toBe("allow")
  expect(await decision("mcp__claude_ai_Slack__slack_send_message")).toBe("deny")
  expect(await decision("Bash", { command: "gh pr list" })).toBe("allow")
  expect(await decision("Bash", { command: "ls ~" })).toBe("deny")
  expect(await decision("Read", { file_path: "/etc/passwd" })).toBe("deny")
  expect(await decision("StructuredOutput", { items: [] })).toBe("allow")
})
