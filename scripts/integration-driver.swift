// integration-driver.swift — drives the SIGNED CheKeynoteMCP binary over MCP
// stdio JSON-RPC and replays the three KeynoteIntegrationTests scenarios
// against real Keynote.
//
// Why this exists (macOS 26 TCC): `swift test` runs the suite inside xctest,
// which carries its own CFBundleIdentifier (com.apple.dt.xctest.tool) and
// loads the AD-HOC-signed debug test bundle — macOS 26 refuses to raise the
// AppleEvents consent dialog for processes running ad-hoc code, so every
// AppleEvent is denied instantly and no Automation grant can ever be
// recorded. The production binary (Developer ID + hardened runtime +
// apple-events entitlement + embedded NSAppleEventsUsageDescription) IS
// dialog-eligible, so integration verification runs through it — which is
// also the exact TCC surface end users see. See docs/integration-testing.md.
//
// Usage:
//   swift build -c release
//   codesign --force --options runtime --timestamp \
//     --entitlements Sources/CheKeynoteMCP/Entitlements.plist \
//     --sign "$DEVELOPER_ID" .build/release/CheKeynoteMCP
//   swift scripts/integration-driver.swift .build/release/CheKeynoteMCP

import Foundation
import PDFKit

// MARK: - Assertion helpers

var failures = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("  ✓ \(label)")
    } else {
        failures += 1
        print("  ✗ FAIL: \(label)")
    }
}

func checkEqual<T: Equatable>(_ lhs: T?, _ rhs: T, _ label: String) {
    check(lhs == rhs, "\(label) (got: \(String(describing: lhs)), want: \(rhs))")
}

// MARK: - Minimal MCP stdio client

final class MCPDriver {
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private var nextID = 0
    private var buffer = Data()

    init(binaryPath: String) throws {
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError
        try process.run()
    }

    func shutdown() {
        stdinPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()
    }

    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        stdinPipe.fileHandleForWriting.write(data)
    }

    /// Reads newline-delimited JSON until a *response* (has id, no method)
    /// arrives; server-initiated notifications are skipped.
    private func readResponse() -> [String: Any] {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any]
                else { continue }
                if object["id"] != nil, object["method"] == nil { return object }
                continue
            }
            let chunk = stdoutPipe.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                print("  ✗ FATAL: server closed stdout with no pending response")
                exit(2)
            }
            buffer.append(chunk)
        }
    }

    func initialize() throws {
        nextID += 1
        try send([
            "jsonrpc": "2.0", "id": nextID, "method": "initialize",
            "params": [
                "protocolVersion": "2025-03-26",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "integration-driver", "version": "1.0"],
            ],
        ])
        _ = readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    /// Sends tools/call and returns the parsed JSON payload of the first
    /// text content block. `expectError: true` inverts the isError check.
    @discardableResult
    func call(_ name: String, _ arguments: [String: Any] = [:],
              expectError: Bool = false) throws -> [String: Any] {
        nextID += 1
        let id = nextID
        try send([
            "jsonrpc": "2.0", "id": id, "method": "tools/call",
            "params": ["name": name, "arguments": arguments],
        ])
        return parseToolResponse(readResponse(), name: name, expectError: expectError)
    }

    /// Pipelined variant: both requests are written BEFORE any response is
    /// read, so they arrive concurrently at the server (actor must
    /// serialize). Responses are matched by id.
    func callPipelined(_ first: (String, [String: Any]),
                       _ second: (String, [String: Any])) throws {
        nextID += 1; let idA = nextID
        nextID += 1; let idB = nextID
        try send(["jsonrpc": "2.0", "id": idA, "method": "tools/call",
                  "params": ["name": first.0, "arguments": first.1]])
        try send(["jsonrpc": "2.0", "id": idB, "method": "tools/call",
                  "params": ["name": second.0, "arguments": second.1]])
        var seen = Set<Int>()
        while seen.count < 2 {
            let response = readResponse()
            guard let id = response["id"] as? Int, id == idA || id == idB else { continue }
            seen.insert(id)
            _ = parseToolResponse(response, name: id == idA ? first.0 : second.0, expectError: false)
        }
    }

    private func parseToolResponse(_ response: [String: Any], name: String,
                                   expectError: Bool) -> [String: Any] {
        guard let result = response["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String
        else {
            failures += 1
            print("  ✗ FAIL: \(name) — malformed tools/call response: \(response)")
            return [:]
        }
        let isError = (result["isError"] as? Bool) ?? false
        if isError != expectError {
            failures += 1
            print("  ✗ FAIL: \(name) — isError=\(isError), expected \(expectError): \(text)")
            return [:]
        }
        guard let data = text.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            if expectError { return ["error": text] }
            failures += 1
            print("  ✗ FAIL: \(name) — non-JSON payload: \(text)")
            return [:]
        }
        return payload
    }
}

// MARK: - Scenarios (mirror Tests/CheKeynoteMCPTests/KeynoteIntegrationTests.swift)

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    print("usage: swift scripts/integration-driver.swift <path-to-signed-CheKeynoteMCP>")
    exit(2)
}
let binaryPath = arguments[1]

let scratch = FileManager.default.temporaryDirectory
    .appendingPathComponent("keynote-driver-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

let driver = try MCPDriver(binaryPath: binaryPath)
try driver.initialize()
print("MCP session initialized against \(binaryPath)")

let adversarialTitle = "He said \"quit\" \\ 換行 🎉"

// Scenario 1 — end-to-end deck authoring (spec: create → 3 slides →
// adversarial readback → save → 3-page PDF export).
print("\n[1/3] end-to-end deck authoring")
do {
    let created = try driver.call("create_presentation")
    let doc = created["document_name"] as? String ?? ""
    check(!doc.isEmpty, "create_presentation returns document_name")

    try driver.call("add_slide", ["document_name": doc])
    try driver.call("add_slide", ["document_name": doc])

    for (index, title) in [(1, "第一張標題"), (2, adversarialTitle), (3, "第三張")] {
        try driver.call("set_slide_title",
                        ["document_name": doc, "slide_index": index, "title": title])
    }
    try driver.call("set_presenter_notes",
                    ["document_name": doc, "slide_index": 2, "notes": "備忘：адversarial ok"])

    let info = try driver.call("get_slide_info", ["document_name": doc, "slide_index": 2])
    checkEqual(info["title"] as? String, adversarialTitle, "adversarial title round-trips")

    let keyPath = scratch.appendingPathComponent("e2e.key").path
    try driver.call("save_presentation", ["document_name": doc, "path": keyPath])
    check(FileManager.default.fileExists(atPath: keyPath), ".key exists after save")

    let pdfPath = scratch.appendingPathComponent("e2e.pdf").path
    try driver.call("export_pdf", ["document_name": doc, "output_path": pdfPath])
    checkEqual(PDFDocument(url: URL(fileURLWithPath: pdfPath))?.pageCount, 3,
               "3-slide deck exports a 3-page PDF")

    try driver.call("close_presentation", ["document_name": doc, "discard_changes": true])
}

// Scenario 2 — single-slide export restores skipped states (spec: 5-slide
// deck, slide 2 pre-skipped, export slide 3 → 1 page + exact restore).
print("\n[2/3] single-slide export restores skipped states")
do {
    let created = try driver.call("create_presentation")
    let doc = created["document_name"] as? String ?? ""
    for _ in 0..<4 { try driver.call("add_slide", ["document_name": doc]) }
    try driver.call("set_slide_skipped",
                    ["document_name": doc, "slide_index": 2, "skipped": true])

    let pdfPath = scratch.appendingPathComponent("single.pdf").path
    try driver.call("export_pdf",
                    ["document_name": doc, "output_path": pdfPath, "slide_index": 3])
    checkEqual(PDFDocument(url: URL(fileURLWithPath: pdfPath))?.pageCount, 1,
               "single-slide export yields a 1-page PDF")

    let slides = try driver.call("list_slides", ["document_name": doc])
    let rows = slides["slides"] as? [[String: Any]] ?? []
    var skippedByIndex = [Int: Bool]()
    for row in rows {
        skippedByIndex[row["slide_index"] as? Int ?? 0] = row["skipped"] as? Bool ?? false
    }
    checkEqual(skippedByIndex[2], true, "pre-existing skipped state restored")
    for index in [1, 3, 4, 5] {
        checkEqual(skippedByIndex[index], false, "slide \(index) un-skipped after restore")
    }

    try driver.call("close_presentation", ["document_name": doc, "discard_changes": true])
}

// Scenario 3 — pipelined calls do not interleave (spec: two concurrent
// title writes both land; the KeynoteController actor serializes).
print("\n[3/3] pipelined concurrent calls do not interleave")
do {
    let created = try driver.call("create_presentation")
    let doc = created["document_name"] as? String ?? ""
    try driver.call("add_slide", ["document_name": doc])

    try driver.callPipelined(
        ("set_slide_title", ["document_name": doc, "slide_index": 1, "title": "並發甲"]),
        ("set_slide_title", ["document_name": doc, "slide_index": 2, "title": "並發乙"])
    )

    let info1 = try driver.call("get_slide_info", ["document_name": doc, "slide_index": 1])
    let info2 = try driver.call("get_slide_info", ["document_name": doc, "slide_index": 2])
    checkEqual(info1["title"] as? String, "並發甲", "pipelined title 1 landed")
    checkEqual(info2["title"] as? String, "並發乙", "pipelined title 2 landed")

    try driver.call("close_presentation", ["document_name": doc, "discard_changes": true])
}

driver.shutdown()

if failures == 0 {
    print("\nALL 3 SCENARIOS PASSED against real Keynote")
    exit(0)
} else {
    print("\n\(failures) assertion(s) FAILED")
    exit(1)
}
