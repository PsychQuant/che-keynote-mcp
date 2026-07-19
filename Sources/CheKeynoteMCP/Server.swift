import Foundation
import MCP

/// Keynote MCP server shell. Tool handlers are thin wrappers — all Keynote
/// logic lives in `KeynoteController` (single actor, see design D2).
actor KeynoteMCPServer {
    private let server: Server
    private let transport: StdioTransport
    let controller = KeynoteController()

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

    // MARK: - Tool registry (spec: 25 tools across six categories)

    /// v1 tool definitions, aggregated per category as the tool-surface
    /// tasks land. Final count pinned at 25 by ToolSurfaceTests.
    var tools: [Tool] { Self.lifecycleTools + Self.slideTools + Self.contentTools + Self.notesPlaybackExportTools }

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
        if let result = await handleLifecycle(params) { return result }
        if let result = await handleSlides(params) { return result }
        if let result = await handleContent(params) { return result }
        if let result = await handleNotesPlaybackExport(params) { return result }
        return CallTool.Result(
            content: [.text("Error: unknown tool '\(params.name)'")],
            isError: true
        )
    }

    /// Test seam (family pattern — same as che-word-mcp).
    func invokeToolForTesting(name: String, arguments: [String: Value] = [:]) async -> CallTool.Result {
        await dispatch(params: CallTool.Parameters(name: name, arguments: arguments))
    }
}
