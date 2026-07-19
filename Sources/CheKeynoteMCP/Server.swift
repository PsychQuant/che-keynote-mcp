import Foundation
import MCP

/// Keynote MCP server shell. Tool handlers are thin wrappers — all Keynote
/// logic lives in `KeynoteController` (single actor, see design D2).
actor KeynoteMCPServer {
    private let server: Server
    private let transport: StdioTransport

    static let serverInstructions = """
    # che-keynote-mcp — Apple Keynote MCP Server

    Drives Keynote via in-process NSAppleScript (Apple's supported automation \
    path; TCC permission attributes to this binary). v1 covers presentation \
    lifecycle, slide CRUD, text content, images, presenter notes, PDF/image \
    export, and playback.

    **v1 boundary (AppleScript dictionary limits)**: no shape fill color, no \
    slide background color, no equation or hyperlink insertion, no chart \
    customization, no direct .key parsing. See docs/applescript-boundary.md.

    Requires: macOS 26 + current Mac App Store Keynote (baseline), and the \
    Automation permission (System Settings → Privacy & Security → Automation \
    → CheKeynoteMCP → Keynote) granted on first use.
    """

    init() async {
        self.server = Server(
            name: "che-keynote-mcp",
            version: "0.1.0",
            instructions: Self.serverInstructions,
            capabilities: .init(tools: .init())
        )
        self.transport = StdioTransport()
        await registerToolHandlers()
    }

    func run() async throws {
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    // MARK: - Tool registry (populated by the v1 tool-surface tasks)

    /// v1 tool definitions. Empty at scaffold stage; six categories land in
    /// the tool-surface tasks (spec: 25 tools).
    var tools: [Tool] { [] }

    private func registerToolHandlers() async {
        await server.withMethodHandler(ListTools.self) { [tools] _ in
            ListTools.Result(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(content: [.text("Error: server unavailable")], isError: true)
            }
            return await self.dispatch(params: params)
        }
    }

    private func dispatch(params: CallTool.Parameters) async -> CallTool.Result {
        CallTool.Result(
            content: [.text("Error: unknown tool '\(params.name)' — scaffold stage exposes no tools yet")],
            isError: true
        )
    }

    /// Test seam (family pattern — same as che-word-mcp).
    func invokeToolForTesting(name: String, arguments: [String: Value] = [:]) async -> CallTool.Result {
        await dispatch(params: CallTool.Parameters(name: name, arguments: arguments))
    }
}
