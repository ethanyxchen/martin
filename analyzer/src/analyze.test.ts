import { expect, test } from "bun:test"
import { servers, slug } from "./analyze"

test("slugs connector names", () => {
  expect(slug("GitHub")).toBe("github")
  expect(slug("Google Drive")).toBe("google-drive")
  expect(slug(" Linear (work) ")).toBe("linear-work")
})

test("builds MCP servers with bearer auth only when a token exists", () => {
  expect(
    servers([
      { name: "GitHub", url: "https://api.githubcopilot.com/mcp/", token: "ghp_x" },
      { name: "Linear", url: "https://mcp.linear.app/mcp", token: null },
    ]),
  ).toEqual({
    github: {
      type: "http",
      url: "https://api.githubcopilot.com/mcp/",
      headers: { Authorization: "Bearer ghp_x" },
      alwaysLoad: true,
    },
    linear: { type: "http", url: "https://mcp.linear.app/mcp", headers: {}, alwaysLoad: true },
  })
})
