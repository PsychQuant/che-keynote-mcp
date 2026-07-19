import Foundation
import MCP

/// Slide CRUD tools (7). list_slides batches per design D4.
extension KeynoteMCPServer {

    static let slideTools: [Tool] = [
        Tool(
            name: "add_slide",
            description: "新增投影片（可選 layout 名稱，如 Title & Content；省略用預設 layout）。回傳 slide_index。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "layout": .object(["type": .string("string"), "description": .string("slide layout 名稱（省略＝預設）")]),
                ]),
                "required": .array([.string("document_name")]),
            ])
        ),
        Tool(
            name: "delete_slide",
            description: "刪除指定投影片（1-based index）。",
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
            name: "duplicate_slide",
            description: "複製指定投影片，回傳新投影片編號。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("來源投影片編號（1-based）")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index")]),
            ])
        ),
        Tool(
            name: "move_slide",
            description: "移動投影片到指定位置之前。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("要移動的投影片編號")]),
                    "before_index": .object(["type": .string("integer"), "description": .string("移到此編號的投影片之前")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("before_index")]),
            ])
        ),
        Tool(
            name: "list_slides",
            description: "列出全部投影片（編號、skipped 狀態、標題）。大簡報自動批次查詢（20 張/批），非逐張 AppleEvent。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                ]),
                "required": .array([.string("document_name")]),
            ])
        ),
        Tool(
            name: "get_slide_info",
            description: "取得單張投影片資訊：編號、layout、skipped、標題、text item 數、image 數。",
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
            name: "set_slide_skipped",
            description: "設定投影片 skipped（略過播放/匯出）狀態。單張匯出的底層機制也用此屬性。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                    "skipped": .object(["type": .string("boolean"), "description": .string("true＝略過")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("skipped")]),
            ])
        ),
    ]

    func handleSlides(_ params: CallTool.Parameters) async -> CallTool.Result? {
        let args = params.arguments ?? [:]
        func doc() -> String? { args["document_name"]?.stringValue }
        func index(_ key: String) -> Int? { args[key]?.intValue }
        do {
            switch params.name {
            case "add_slide":
                guard let d = doc() else { return ToolResponse.error("missing parameter: document_name") }
                let layout = args["layout"]?.stringValue
                let result = try await controller.run(KeynoteScripts.addSlide(documentName: d, layout: layout))
                return ToolResponse.ok(["slide_index": Int(result.int32Value)])

            case "delete_slide":
                guard let d = doc(), let i = index("slide_index") else { return ToolResponse.error("missing parameter: document_name / slide_index") }
                try await controller.run(KeynoteScripts.deleteSlide(documentName: d, slideIndex: i))
                return ToolResponse.ok(["deleted": i])

            case "duplicate_slide":
                guard let d = doc(), let i = index("slide_index") else { return ToolResponse.error("missing parameter: document_name / slide_index") }
                let result = try await controller.run(KeynoteScripts.duplicateSlide(documentName: d, slideIndex: i))
                return ToolResponse.ok(["slide_index": Int(result.int32Value)])

            case "move_slide":
                guard let d = doc(), let i = index("slide_index"), let b = index("before_index") else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / before_index")
                }
                try await controller.run(KeynoteScripts.moveSlide(documentName: d, from: i, toBefore: b))
                return ToolResponse.ok(["moved": i, "before": b])

            case "list_slides":
                guard let d = doc() else { return ToolResponse.error("missing parameter: document_name") }
                let count = Int(try await controller.run(KeynoteScripts.slideCount(documentName: d)).int32Value)
                var slides: [[String: Any]] = []
                for script in KeynoteScripts.listSlidesBatches(documentName: d, slideCount: count) {
                    let batch = try await controller.run(script)
                    let numbers = batch.atIndex(1), skipped = batch.atIndex(2), titles = batch.atIndex(3)
                    let n = numbers?.numberOfItems ?? 0
                    guard n > 0 else { continue }
                    for k in 1...n {
                        slides.append([
                            "slide_index": Int(numbers?.atIndex(k)?.int32Value ?? 0),
                            "skipped": skipped?.atIndex(k)?.booleanValue ?? false,
                            "title": titles?.atIndex(k)?.stringValue ?? "",
                        ])
                    }
                }
                return ToolResponse.ok(["slide_count": count, "slides": slides])

            case "get_slide_info":
                guard let d = doc(), let i = index("slide_index") else { return ToolResponse.error("missing parameter: document_name / slide_index") }
                let info = try await controller.run(KeynoteScripts.slideInfo(documentName: d, slideIndex: i))
                return ToolResponse.ok([
                    "slide_index": Int(info.atIndex(1)?.int32Value ?? 0),
                    "layout": info.atIndex(2)?.stringValue ?? "",
                    "skipped": info.atIndex(3)?.booleanValue ?? false,
                    "title": info.atIndex(4)?.stringValue ?? "",
                    "text_item_count": Int(info.atIndex(5)?.int32Value ?? 0),
                    "image_count": Int(info.atIndex(6)?.int32Value ?? 0),
                ])

            case "set_slide_skipped":
                guard let d = doc(), let i = index("slide_index"), let s = args["skipped"]?.boolValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / skipped")
                }
                try await controller.run(KeynoteScripts.setSlideSkipped(documentName: d, slideIndex: i, skipped: s))
                return ToolResponse.ok(["slide_index": i, "skipped": s])

            default:
                return nil
            }
        } catch {
            return ToolResponse.error(error)
        }
    }
}
