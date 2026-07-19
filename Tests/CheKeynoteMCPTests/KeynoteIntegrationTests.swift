// KeynoteIntegrationTests.swift — che-keynote-mcp task 4.1 (design D7,
// integration tier). Drives REAL Keynote end-to-end; gated by
// RUN_KEYNOTE_INTEGRATION=1 (maintainer machine, macOS 26 + current
// Keynote). Skips cleanly when the env gate is unset — CI stays green.

import XCTest
import PDFKit
import MCP
@testable import CheKeynoteMCP

final class KeynoteIntegrationTests: XCTestCase {

    private func requireGate() throws {
        guard ProcessInfo.processInfo.environment["RUN_KEYNOTE_INTEGRATION"] == "1" else {
            throw XCTSkip("set RUN_KEYNOTE_INTEGRATION=1 to drive real Keynote (maintainer machine)")
        }
    }

    private func makeScratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("keynote-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func text(_ result: CallTool.Result) -> String {
        if case .text(let t, _, _)? = result.content.first { return t }
        return ""
    }

    private func json(_ result: CallTool.Result) throws -> [String: Any] {
        let raw = text(result)
        let data = try XCTUnwrap(raw.data(using: .utf8), "non-UTF8 response: \(raw)")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any],
                             "non-JSON response: \(raw)")
    }

    @discardableResult
    private func call(_ server: KeynoteMCPServer, _ name: String,
                      _ args: [String: Value]) async throws -> [String: Any] {
        let result = await server.invokeToolForTesting(name: name, arguments: args)
        XCTAssertNotEqual(result.isError, true, "\(name) failed: \(text(result))")
        return try json(result)
    }

    /// Spec scenario "end-to-end deck authoring": create → 3 slides with
    /// titles/bodies → notes on slide 2 → save → export_pdf with 3 pages.
    /// Also covers spec scenario "TCC attribution" implicitly — the first
    /// run on a fresh grant surface raises the Automation dialog.
    func testEndToEndDeckAuthoring() async throws {
        try requireGate()
        let dir = try makeScratch()
        let server = await KeynoteMCPServer()

        let created = try await call(server, "create_presentation", [:])
        let doc = try XCTUnwrap(created["document_name"] as? String)

        // A fresh Keynote document starts with one title slide; add 2 more
        // and drive titles/bodies through the content tools.
        try await call(server, "add_slide", ["document_name": .string(doc)])
        try await call(server, "add_slide", ["document_name": .string(doc)])

        let adversarialTitle = "He said \"quit\" \\ 換行 🎉"
        for (index, title) in [(1, "第一張標題"), (2, adversarialTitle), (3, "第三張")] {
            try await call(server, "set_slide_title", [
                "document_name": .string(doc), "slide_index": .int(index), "title": .string(title),
            ])
        }
        try await call(server, "set_presenter_notes", [
            "document_name": .string(doc), "slide_index": .int(2), "notes": .string("備忘：адversarial ok"),
        ])

        // Spec scenario "adversarial content round-trips intact" (readback).
        let info = try await call(server, "get_slide_info", [
            "document_name": .string(doc), "slide_index": .int(2),
        ])
        XCTAssertEqual(info["title"] as? String, adversarialTitle,
                       "adversarial title must round-trip exactly through real Keynote")

        let keyPath = dir.appendingPathComponent("e2e.key").path
        try await call(server, "save_presentation", [
            "document_name": .string(doc), "path": .string(keyPath),
        ])
        XCTAssertTrue(FileManager.default.fileExists(atPath: keyPath), ".key must exist after save")

        let pdfPath = dir.appendingPathComponent("e2e.pdf").path
        try await call(server, "export_pdf", [
            "document_name": .string(doc), "output_path": .string(pdfPath),
        ])
        let pdf = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: pdfPath)), "exported PDF must parse")
        XCTAssertEqual(pdf.pageCount, 3, "3-slide deck must export a 3-page PDF")

        try await call(server, "close_presentation", [
            "document_name": .string(doc), "discard_changes": .bool(true),
        ])
    }

    /// Spec scenario "single-slide export via skipped toggle": 5-slide deck
    /// with slide 2 pre-skipped → export slide 3 only → 1-page PDF, and the
    /// original skipped states are restored exactly.
    func testSingleSlideExportRestoresSkippedStates() async throws {
        try requireGate()
        let dir = try makeScratch()
        let server = await KeynoteMCPServer()

        let created = try await call(server, "create_presentation", [:])
        let doc = try XCTUnwrap(created["document_name"] as? String)
        for _ in 0..<4 { try await call(server, "add_slide", ["document_name": .string(doc)]) }
        try await call(server, "set_slide_skipped", [
            "document_name": .string(doc), "slide_index": .int(2), "skipped": .bool(true),
        ])

        let pdfPath = dir.appendingPathComponent("single.pdf").path
        try await call(server, "export_pdf", [
            "document_name": .string(doc), "output_path": .string(pdfPath), "slide_index": .int(3),
        ])
        let pdf = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: pdfPath)))
        XCTAssertEqual(pdf.pageCount, 1, "single-slide export must yield a 1-page PDF")

        let slides = try await call(server, "list_slides", ["document_name": .string(doc)])
        let rows = try XCTUnwrap(slides["slides"] as? [[String: Any]])
        let skippedByIndex = Dictionary(uniqueKeysWithValues: rows.map {
            (($0["slide_index"] as? Int) ?? 0, ($0["skipped"] as? Bool) ?? false)
        })
        XCTAssertEqual(skippedByIndex[2], true, "pre-existing skipped state must be restored")
        for index in [1, 3, 4, 5] {
            XCTAssertEqual(skippedByIndex[index], false, "slide \(index) must be un-skipped after restore")
        }

        try await call(server, "close_presentation", [
            "document_name": .string(doc), "discard_changes": .bool(true),
        ])
    }

    /// Spec scenario "concurrent calls do not interleave": two concurrent
    /// title writes to different slides both land correctly (the actor
    /// serializes; interleaved scripting would corrupt or error).
    func testConcurrentCallsDoNotInterleave() async throws {
        try requireGate()
        let server = await KeynoteMCPServer()
        let created = try await call(server, "create_presentation", [:])
        let doc = try XCTUnwrap(created["document_name"] as? String)
        try await call(server, "add_slide", ["document_name": .string(doc)])

        async let first: [String: Any] = call(server, "set_slide_title", [
            "document_name": .string(doc), "slide_index": .int(1), "title": .string("並發甲"),
        ])
        async let second: [String: Any] = call(server, "set_slide_title", [
            "document_name": .string(doc), "slide_index": .int(2), "title": .string("並發乙"),
        ])
        _ = try await (first, second)

        let info1 = try await call(server, "get_slide_info", ["document_name": .string(doc), "slide_index": .int(1)])
        let info2 = try await call(server, "get_slide_info", ["document_name": .string(doc), "slide_index": .int(2)])
        XCTAssertEqual(info1["title"] as? String, "並發甲")
        XCTAssertEqual(info2["title"] as? String, "並發乙")

        try await call(server, "close_presentation", [
            "document_name": .string(doc), "discard_changes": .bool(true),
        ])
    }
}
