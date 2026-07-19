import Foundation
import AppKit

/// Errors surfaced by Keynote automation. Messages are actionable per the
/// keynote-mcp-server spec ("Failures surface as structured actionable
/// errors") — full mapping lives in `map(errorDict:)`.
enum KeynoteError: Error, LocalizedError, Equatable {
    case keynoteNotAvailable
    case permissionDenied
    case scriptError(number: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .keynoteNotAvailable:
            return "Keynote is not installed or not scriptable on this machine. "
                + "Install Keynote from the Mac App Store (baseline: macOS 26 + current Keynote)."
        case .permissionDenied:
            return "Automation permission denied. Grant it in System Settings → "
                + "Privacy & Security → Automation → CheKeynoteMCP → Keynote, then retry."
        case .scriptError(let number, let message):
            return "AppleScript error \(number): \(message)"
        }
    }
}

/// Single choke point for ALL Keynote automation (design D2 — Keynote
/// scripting is not concurrency-safe, so serialization is structural: every
/// tool handler awaits this actor). Scripts execute via in-process
/// NSAppleScript (design D1 — never a subprocess), and user content enters
/// script source only through `quoted(_:)` (design D3 — the single audited
/// quoting helper; the injection corpus in ScriptGenerationTests pins it).
actor KeynoteController {

    private let keynoteBundleID = "com.apple.iWork.Keynote"

    // MARK: - Availability

    nonisolated func isKeynoteInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: keynoteBundleID) != nil
    }

    // MARK: - Script execution (in-process, D1)

    /// Executes AppleScript source in-process and returns the result
    /// descriptor. Throws `KeynoteError` with actionable messages.
    @discardableResult
    func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard isKeynoteInstalled() else { throw KeynoteError.keynoteNotAvailable }
        var errorDict: NSDictionary?
        let script = NSAppleScript(source: source)
        guard let result = script?.executeAndReturnError(&errorDict) else {
            throw Self.map(errorDict: errorDict)
        }
        return result
    }

    /// Maps an NSAppleScript error dictionary to a structured KeynoteError.
    /// -1743 (errAEPrivilegeError, macOS 10.14+) and -1719 / -10004 are the
    /// TCC / privilege family (che-logic-pro-mcp precedent); everything else
    /// carries Keynote's own number + message.
    static func map(errorDict: NSDictionary?) -> KeynoteError {
        guard let errorDict else {
            return .scriptError(number: -1, message: "Script execution failed with no error detail")
        }
        let number = errorDict[NSAppleScript.errorNumber] as? Int ?? -1
        let message = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
        if number == -1743 || number == -1719 || number == -10004
            || message.localizedCaseInsensitiveContains("not allowed")
            || message.localizedCaseInsensitiveContains("not authorized") {
            return .permissionDenied
        }
        return .scriptError(number: number, message: message)
    }

    // MARK: - Quoting (D3 — the single audited helper)

    /// AppleScript string-literal quoting: backslash first, then double
    /// quote; wraps in quotes. Newlines are legal inside AppleScript string
    /// literals and pass through untouched, as do emoji / CJK (NSAppleScript
    /// source is an NSString). This is the ONLY path by which user content
    /// enters script source.
    nonisolated static func quoted(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    // MARK: - Batching (D4 — ~430ms per AppleEvent; group multi-slide work)

    /// Partitions items into fixed-size batches preserving order.
    /// Spec example: 45 items, size 20 → [20, 20, 5].
    nonisolated static func batches<T>(_ items: [T], size: Int = 20) -> [[T]] {
        precondition(size > 0, "batch size must be positive")
        guard !items.isEmpty else { return [] }
        return stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }
}
