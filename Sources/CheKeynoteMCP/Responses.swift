import Foundation
import MCP

/// JSON tool-response helpers (family convention: JSON text content with
/// stable field names; errors are isError text — never silent).
enum ToolResponse {
    static func ok(_ payload: [String: Any]) -> CallTool.Result {
        var object = payload
        object["ok"] = true
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return error("internal: response serialization failed")
        }
        return CallTool.Result(content: [.text(text)])
    }

    static func error(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text("Error: \(message)")], isError: true)
    }

    static func error(_ underlying: Error) -> CallTool.Result {
        error(underlying.localizedDescription)
    }
}
