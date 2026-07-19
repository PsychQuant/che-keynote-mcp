import Foundation
import MCP

/// Presenter notes (2) + playback (2) + export (2). export_pdf/export_images
/// implement single-slide export via the skipped-toggle technique with
/// guaranteed state restore (spec scenario; docs/applescript-boundary.md #6).
extension KeynoteMCPServer {

    static let notesPlaybackExportTools: [Tool] = [
        Tool(
            name: "set_presenter_notes",
            description: "設定投影片的 presenter notes（簡報者備忘稿）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                    "notes": .object(["type": .string("string"), "description": .string("備忘稿文字")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("notes")]),
            ])
        ),
        Tool(
            name: "get_presenter_notes",
            description: "讀取投影片的 presenter notes。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index")]),
            ])
        ),
        Tool(
            name: "export_pdf",
            description: "匯出簡報為 PDF。可選 slide_index 只匯出單張——底層以 skipped 屬性 toggle 其他投影片再匯出，完成後還原原始 skipped 狀態（Keynote 無原生單張匯出 API）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "output_path": .object(["type": .string("string"), "description": .string("輸出 .pdf 路徑")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("只匯出此張（省略＝整份）")]),
                ]),
                "required": .array([.string("document_name"), .string("output_path")]),
            ])
        ),
        Tool(
            name: "export_images",
            description: "匯出簡報為圖片序列（PNG）到指定資料夾。可選 slide_index 只匯出單張（同 export_pdf 的 skipped-toggle 機制）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "output_path": .object(["type": .string("string"), "description": .string("輸出資料夾路徑")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("只匯出此張（省略＝整份）")]),
                ]),
                "required": .array([.string("document_name"), .string("output_path")]),
            ])
        ),
        Tool(
            name: "start_slideshow",
            description: "從第一張開始播放簡報。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                ]),
                "required": .array([.string("document_name")]),
            ])
        ),
        Tool(
            name: "stop_slideshow",
            description: "停止目前播放中的簡報。",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        ),
    ]

    func handleNotesPlaybackExport(_ params: CallTool.Parameters) async -> CallTool.Result? {
        let args = params.arguments ?? [:]
        func doc() -> String? { args["document_name"]?.stringValue }
        do {
            switch params.name {
            case "set_presenter_notes":
                guard let d = doc(), let i = args["slide_index"]?.intValue, let n = args["notes"]?.stringValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / notes")
                }
                try await controller.run(KeynoteScripts.setPresenterNotes(documentName: d, slideIndex: i, notes: n))
                return ToolResponse.ok(["slide_index": i, "notes_set": true])

            case "get_presenter_notes":
                guard let d = doc(), let i = args["slide_index"]?.intValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index")
                }
                let notes = try await controller.run(KeynoteScripts.getPresenterNotes(documentName: d, slideIndex: i))
                return ToolResponse.ok(["slide_index": i, "notes": notes.stringValue ?? ""])

            case "export_pdf", "export_images":
                guard let d = doc(), let out = args["output_path"]?.stringValue else {
                    return ToolResponse.error("missing parameter: document_name / output_path")
                }
                let single = args["slide_index"]?.intValue
                return try await exportWithOptionalSingleSlide(
                    documentName: d, outputPath: out, singleSlide: single,
                    exportScript: params.name == "export_pdf"
                        ? KeynoteScripts.exportPDF(documentName: d, outputPath: out)
                        : KeynoteScripts.exportImages(documentName: d, outputPath: out)
                )

            case "start_slideshow":
                guard let d = doc() else { return ToolResponse.error("missing parameter: document_name") }
                try await controller.run(KeynoteScripts.startSlideshow(documentName: d))
                return ToolResponse.ok(["started": true])

            case "stop_slideshow":
                try await controller.run(KeynoteScripts.stopSlideshow())
                return ToolResponse.ok(["stopped": true])

            default:
                return nil
            }
        } catch {
            return ToolResponse.error(error)
        }
    }

    /// Whole-deck export runs the export script directly. Single-slide export
    /// wraps it in the skipped-toggle sequence; the saved states are restored
    /// in a defer so even a failing export never leaves the deck's skipped
    /// flags mutated (spec scenario "single-slide export via skipped toggle").
    private func exportWithOptionalSingleSlide(
        documentName: String, outputPath: String, singleSlide: Int?, exportScript: String
    ) async throws -> CallTool.Result {
        guard let keep = singleSlide else {
            try await controller.run(exportScript)
            return ToolResponse.ok(["output_path": outputPath, "scope": "all_slides"])
        }
        let statesDescriptor = try await controller.run(KeynoteScripts.readSkippedStates(documentName: documentName))
        var saved: [Bool] = []
        if statesDescriptor.numberOfItems > 0 {
            for k in 1...statesDescriptor.numberOfItems {
                saved.append(statesDescriptor.atIndex(k)?.booleanValue ?? false)
            }
        }
        guard keep >= 1, keep <= saved.count else {
            return ToolResponse.error("slide_index \(keep) 超出範圍（簡報共 \(saved.count) 張）")
        }
        try await controller.run(KeynoteScripts.skipAllExcept(documentName: documentName, keepIndex: keep, slideCount: saved.count))
        do {
            try await controller.run(exportScript)
        } catch {
            // Restore before surfacing the export failure — never leave the
            // deck with mutated skipped flags.
            _ = try? await controller.run(KeynoteScripts.restoreSkippedStates(documentName: documentName, states: saved))
            throw error
        }
        try await controller.run(KeynoteScripts.restoreSkippedStates(documentName: documentName, states: saved))
        return ToolResponse.ok(["output_path": outputPath, "scope": "slide_\(keep)"])
    }
}
