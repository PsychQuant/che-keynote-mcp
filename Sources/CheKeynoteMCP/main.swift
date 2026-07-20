import Foundation
import MCP

// Entry point — Keynote MCP Server (drives Apple Keynote via in-process
// NSAppleScript; see docs/applescript-boundary.md for the capability
// boundary this server promises).
//
// Two maintenance flags run instead of the server (macOS 26 TCC onboarding,
// mirroring the che-ical-mcp --setup / --check-tcc pattern — see SetupRunner):
//   --setup      one-time interactive Automation grant (click Allow)
//   --check-tcc  print current Automation → Keynote status, no dialog
let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--setup") {
    exit(await SetupRunner.runSetup())
}
if arguments.contains("--check-tcc") {
    exit(SetupRunner.printStatus())
}

let server = await KeynoteMCPServer()
try await server.run()
