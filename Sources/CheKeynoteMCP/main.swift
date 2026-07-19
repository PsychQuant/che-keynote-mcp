import Foundation
import MCP

// Entry point — Keynote MCP Server (drives Apple Keynote via in-process
// NSAppleScript; see docs/applescript-boundary.md for the capability
// boundary this server promises).
let server = await KeynoteMCPServer()
try await server.run()
