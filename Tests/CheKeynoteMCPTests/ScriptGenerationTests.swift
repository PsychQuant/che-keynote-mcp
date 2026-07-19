// ScriptGenerationTests.swift — che-keynote-mcp task 2.1 (design D1/D2/D3).
// Unit tier: asserts script assembly, quoting, and batching WITHOUT touching
// Keynote (CI-safe). The quoting round-trip executes a pure NSAppleScript
// `return <literal>` — in-process, no AppleEvents to other apps, no TCC.

import XCTest
@testable import CheKeynoteMCP

final class ScriptGenerationTests: XCTestCase {

    // Spec example (keynote-mcp-server, "injection corpus") + extensions.
    // The spec's GIVEN value is the first entry — do not alter it.
    static let injectionCorpus: [String] = [
        "He said \"quit\" \\ 換行:\n🎉 end tell",
        "plain ascii",
        "雙引號\"與反斜線\\混合",
        "line1\nline2\nline3",
        "🎉🀄️ emoji 與 CJK 混排",
        "tell application \"Finder\" to activate",
        "\" & (do shell script \"true\") & \"",
    ]

    // MARK: - D3: quoting helper round-trip (the injection gate)

    func testQuotedRoundTripsInjectionCorpus() throws {
        for input in Self.injectionCorpus {
            let script = "return \(KeynoteController.quoted(input))"
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            XCTAssertNil(error, "script error for input \(input.debugDescription): \(String(describing: error))")
            XCTAssertEqual(result?.stringValue, input,
                           "quoted literal must round-trip exactly for \(input.debugDescription)")
        }
    }

    func testQuotedNeverTerminatesTellBlock() {
        // The corpus `end tell` entry must stay inside the string literal:
        // the quoted form contains no unescaped double-quote before its end.
        let quoted = KeynoteController.quoted(Self.injectionCorpus[0])
        XCTAssertTrue(quoted.hasPrefix("\"") && quoted.hasSuffix("\""))
        let inner = String(quoted.dropFirst().dropLast())
        var i = inner.startIndex
        while i < inner.endIndex {
            let ch = inner[i]
            if ch == "\\" { i = inner.index(i, offsetBy: 2, limitedBy: inner.endIndex) ?? inner.endIndex; continue }
            XCTAssertNotEqual(ch, "\"", "unescaped quote inside quoted literal — tell-block escape possible")
            i = inner.index(after: i)
        }
    }

    // MARK: - Sample operation script shape

    func testSetSlideTitleScriptShape() {
        let script = KeynoteScripts.setSlideTitle(documentName: "Deck.key", slideIndex: 2, title: "第 2 張 \"標題\"")
        XCTAssertTrue(script.contains("tell application \"Keynote\""))
        XCTAssertTrue(script.contains("slide 2"))
        XCTAssertTrue(script.contains(KeynoteController.quoted("Deck.key")))
        XCTAssertTrue(script.contains(KeynoteController.quoted("第 2 張 \"標題\"")))
        XCTAssertFalse(script.contains("第 2 張 \"標題\"\n"),
                       "raw unquoted title must not be interpolated")
    }

    // MARK: - D4: batching partition (spec example 45 → 20/20/5)

    func testBatchesPartitionMatchesSpecExample() {
        let batches = KeynoteController.batches(Array(1...45), size: 20)
        XCTAssertEqual(batches.map(\.count), [20, 20, 5])
        XCTAssertEqual(batches.flatMap { $0 }, Array(1...45))
    }

    func testBatchesEdgeCases() {
        XCTAssertEqual(KeynoteController.batches([Int](), size: 20).count, 0)
        XCTAssertEqual(KeynoteController.batches([1], size: 20).map(\.count), [1])
        XCTAssertEqual(KeynoteController.batches(Array(1...20), size: 20).map(\.count), [20])
    }

    // MARK: - D1: no shell-out anywhere in Sources (grep gate)

    func testNoProcessOrOsascriptInSources() throws {
        let sourcesURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CheKeynoteMCPTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sourcesURL, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("Process("),
                           "\(url.lastPathComponent) spawns a process — violates in-process NSAppleScript requirement")
            XCTAssertFalse(text.lowercased().contains("osascript"),
                           "\(url.lastPathComponent) references osascript — violates D1")
        }
    }
}
