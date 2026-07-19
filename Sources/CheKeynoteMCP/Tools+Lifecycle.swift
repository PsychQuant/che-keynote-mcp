import Foundation
import MCP

/// Presentation lifecycle tools (6). Thin wrappers — Keynote logic lives in
/// KeynoteController / KeynoteScripts.
extension KeynoteMCPServer {

    static let lifecycleTools: [Tool] = [
        Tool(
            name: "create_presentation",
            description: "建立新 Keynote 簡報（可選 theme 名稱，如 White／Black／Gradient）。回傳 document_name 供後續操作。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "theme": .object(["type": .string("string"), "description": .string("Keynote theme 名稱（省略用預設 theme）")]),
                ]),
            ])
        ),
        Tool(
            name: "open_presentation",
            description: "開啟既有 .key 簡報檔。回傳 document_name。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "path": .object(["type": .string("string"), "description": .string(".key 檔案路徑")]),
                ]),
                "required": .array([.string("path")]),
            ])
        ),
        Tool(
            name: "save_presentation",
            description: "儲存簡報。首次儲存新簡報必須給 path（.key）；已有檔案的簡報省略 path 原地儲存。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "path": .object(["type": .string("string"), "description": .string("另存路徑（省略＝原地儲存）")]),
                ]),
                "required": .array([.string("document_name")]),
            ])
        ),
        Tool(
            name: "close_presentation",
            description: "關閉簡報。discard_changes: true 時不儲存直接關閉（預設會儲存）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "discard_changes": .object(["type": .string("boolean"), "description": .string("true＝放棄未儲存變更")]),
                ]),
                "required": .array([.string("document_name")]),
            ])
        ),
        Tool(
            name: "list_presentations",
            description: "列出目前在 Keynote 開啟的所有簡報名稱。",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
        Tool(
            name: "get_presentation_info",
            description: "取得簡報資訊：名稱、投影片數、theme 名稱。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                ]),
                "required": .array([.string("document_name")]),
            ])
        ),
    ]

    func handleLifecycle(_ params: CallTool.Parameters) async -> CallTool.Result? {
        let args = params.arguments ?? [:]
        do {
            switch params.name {
            case "create_presentation":
                let theme = args["theme"]?.stringValue
                let name = try await controller.run(KeynoteScripts.createPresentation(theme: theme))
                return ToolResponse.ok(["document_name": name.stringValue ?? ""])

            case "open_presentation":
                guard let path = args["path"]?.stringValue else { return ToolResponse.error("missing parameter: path") }
                guard FileManager.default.fileExists(atPath: path) else {
                    return ToolResponse.error("找不到輸入檔案: \(path)")
                }
                let name = try await controller.run(KeynoteScripts.openPresentation(path: path))
                return ToolResponse.ok(["document_name": name.stringValue ?? ""])

            case "save_presentation":
                guard let doc = args["document_name"]?.stringValue else { return ToolResponse.error("missing parameter: document_name") }
                let path = args["path"]?.stringValue
                try await controller.run(KeynoteScripts.savePresentation(documentName: doc, path: path))
                return ToolResponse.ok(["document_name": doc, "saved": true])

            case "close_presentation":
                guard let doc = args["document_name"]?.stringValue else { return ToolResponse.error("missing parameter: document_name") }
                let discard = args["discard_changes"]?.boolValue ?? false
                try await controller.run(KeynoteScripts.closePresentation(documentName: doc, discardingChanges: discard))
                return ToolResponse.ok(["document_name": doc, "closed": true])

            case "list_presentations":
                let names = try await controller.run(KeynoteScripts.listPresentations())
                return ToolResponse.ok(["presentations": Self.stringList(from: names)])

            case "get_presentation_info":
                guard let doc = args["document_name"]?.stringValue else { return ToolResponse.error("missing parameter: document_name") }
                let info = try await controller.run(KeynoteScripts.presentationInfo(documentName: doc))
                return ToolResponse.ok([
                    "name": info.atIndex(1)?.stringValue ?? doc,
                    "slide_count": info.atIndex(2)?.int32Value ?? 0,
                    "theme": info.atIndex(3)?.stringValue ?? "",
                ])

            default:
                return nil
            }
        } catch {
            return ToolResponse.error(error)
        }
    }

    /// Flattens an AppleScript list descriptor into [String].
    static func stringList(from descriptor: NSAppleEventDescriptor) -> [String] {
        guard descriptor.numberOfItems > 0 else {
            return descriptor.stringValue.map { [$0] } ?? []
        }
        return (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0)?.stringValue }
    }
}
