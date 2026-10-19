import { Client } from "@modelcontextprotocol/sdk/client/index.js"
import { StreamableHTTPClientTransport, StreamableHTTPError } from "@modelcontextprotocol/sdk/client/streamableHttp.js"
import { ErrorCode, McpError } from "@modelcontextprotocol/sdk/types.js"
import { headers, type Connector } from "./schema"

const timeout = 10

export type Status = { name: string; ok: boolean; tools: number; error: string | null }

function reason(error: unknown) {
  if (error instanceof StreamableHTTPError) {
    const body = error.message.replace(/^Streamable HTTP error: [^:]*: ?/, "").trim()
    return body ? `HTTP ${error.code}: ${body}` : `HTTP ${error.code}`
  }
  if (error instanceof McpError && error.code === ErrorCode.RequestTimeout) return `No answer within ${timeout} seconds`
  return error instanceof Error ? error.message : String(error)
}

async function probe(connector: Connector): Promise<Status> {
  const { name, url } = connector
  const client = new Client({ name: "martin", version: "1.0.0" })
  const transport = new StreamableHTTPClientTransport(new URL(url), {
    requestInit: { headers: headers(connector) },
  })
  const options = { signal: AbortSignal.timeout(timeout * 1000) }
  try {
    await client.connect(transport, options)
    const { tools } = await client.listTools(undefined, options)
    return { name, ok: true, tools: tools.length, error: null }
  } catch (error) {
    return { name, ok: false, tools: 0, error: reason(error) }
  } finally {
    await client.close()
  }
}

export const check = (connectors: Connector[]) => Promise.all(connectors.map(probe))
