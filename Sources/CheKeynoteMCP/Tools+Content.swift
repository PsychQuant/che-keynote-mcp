import Foundation
import MCP

/// Content tools (6). Boundary note (design D5): shape fill color / slide
/// background color / equation / hyperlink insertion are AppleScript
/// dictionary gaps — stated in descriptions, no tool claims them.
extension KeynoteMCPServer {

    static let contentBoundaryNote = "v1 邊界：shape 填色、slide 背景色、equation、hyperlink 插入為 AppleScript dictionary 缺口，本工具組不提供（見 docs/applescript-boundary.md）。"

    static let contentTools: [Tool] = [
        Tool(
            name: "set_slide_title",
            description: "設定投影片標題（default title item）。\(contentBoundaryNote)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                    "title": .object(["type": .string("string"), "description": .string("標題文字")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("title")]),
            ])
        ),
        Tool(
            name: "set_slide_body",
            description: "設定投影片內文（default body item；layout 需含 body）。\(contentBoundaryNote)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                    "body": .object(["type": .string("string"), "description": .string("內文文字（可含換行）")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("body")]),
            ])
        ),
        Tool(
            name: "add_text_item",
            description: "在投影片新增獨立文字框。回傳投影片目前的 text item 數。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                    "text": .object(["type": .string("string"), "description": .string("文字內容")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("text")]),
            ])
        ),
        Tool(
            name: "set_text_item",
            description: "改寫投影片上指定 text item 的文字（1-based item index，順序見 list_text_items）。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                    "item_index": .object(["type": .string("integer"), "description": .string("text item 編號（1-based）")]),
                    "text": .object(["type": .string("string"), "description": .string("新文字內容")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("item_index"), .string("text")]),
            ])
        ),
        Tool(
            name: "list_text_items",
            description: "列出投影片上所有 text item 的文字內容（依 item index 順序）。",
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
            name: "add_image",
            description: "在投影片插入本機圖片檔（路徑先驗證存在才組腳本）。回傳投影片目前的 image 數。",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "document_name": .object(["type": .string("string"), "description": .string("目標 document 名稱")]),
                    "slide_index": .object(["type": .string("integer"), "description": .string("投影片編號（1-based）")]),
                    "path": .object(["type": .string("string"), "description": .string("圖片檔路徑（png/jpg/gif/heic…）")]),
                ]),
                "required": .array([.string("document_name"), .string("slide_index"), .string("path")]),
            ])
        ),
    ]

    func handleContent(_ params: CallTool.Parameters) async -> CallTool.Result? {
        let args = params.arguments ?? [:]
        func doc() -> String? { args["document_name"]?.stringValue }
        func slide() -> Int? { args["slide_index"]?.intValue }
        do {
            switch params.name {
            case "set_slide_title":
                guard let d = doc(), let i = slide(), let t = args["title"]?.stringValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / title")
                }
                try await controller.run(KeynoteScripts.setSlideTitle(documentName: d, slideIndex: i, title: t))
                return ToolResponse.ok(["slide_index": i, "title": t])

            case "set_slide_body":
                guard let d = doc(), let i = slide(), let b = args["body"]?.stringValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / body")
                }
                try await controller.run(KeynoteScripts.setSlideBody(documentName: d, slideIndex: i, body: b))
                return ToolResponse.ok(["slide_index": i, "body_set": true])

            case "add_text_item":
                guard let d = doc(), let i = slide(), let t = args["text"]?.stringValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / text")
                }
                let count = try await controller.run(KeynoteScripts.addTextItem(documentName: d, slideIndex: i, text: t))
                return ToolResponse.ok(["slide_index": i, "text_item_count": Int(count.int32Value)])

            case "set_text_item":
                guard let d = doc(), let i = slide(), let k = args["item_index"]?.intValue, let t = args["text"]?.stringValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / item_index / text")
                }
                try await controller.run(KeynoteScripts.setTextItem(documentName: d, slideIndex: i, itemIndex: k, text: t))
                return ToolResponse.ok(["slide_index": i, "item_index": k])

            case "list_text_items":
                guard let d = doc(), let i = slide() else {
                    return ToolResponse.error("missing parameter: document_name / slide_index")
                }
                let items = try await controller.run(KeynoteScripts.listTextItems(documentName: d, slideIndex: i))
                return ToolResponse.ok(["slide_index": i, "text_items": Self.stringList(from: items)])

            case "add_image":
                guard let d = doc(), let i = slide(), let path = args["path"]?.stringValue else {
                    return ToolResponse.error("missing parameter: document_name / slide_index / path")
                }
                guard FileManager.default.fileExists(atPath: path) else {
                    return ToolResponse.error("找不到輸入檔案: \(path)")
                }
                let count = try await controller.run(KeynoteScripts.addImage(documentName: d, slideIndex: i, path: path))
                return ToolResponse.ok(["slide_index": i, "image_count": Int(count.int32Value)])

            default:
                return nil
            }
        } catch {
            return ToolResponse.error(error)
        }
    }
}
