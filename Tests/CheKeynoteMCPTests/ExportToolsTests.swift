// ExportToolsTests.swift — che-keynote-mcp task 3.5 (spec scenario:
// "single-slide export via skipped toggle" — toggle others, export,
// restore, with restore guaranteed on the failure path too).

import XCTest
@testable import CheKeynoteMCP

final class ExportToolsTests: XCTestCase {

    func testExportPDFScriptShape() {
        let script = KeynoteScripts.exportPDF(documentName: "Deck.key", outputPath: "/tmp/out \"x\".pdf")
        XCTAssertTrue(script.contains("export"))
        XCTAssertTrue(script.contains("as PDF"))
        XCTAssertTrue(script.contains("POSIX file \(KeynoteController.quoted("/tmp/out \"x\".pdf"))"))
    }

    func testExportImagesScriptShape() {
        let script = KeynoteScripts.exportImages(documentName: "Deck.key", outputPath: "/tmp/outdir")
        XCTAssertTrue(script.contains("as slide images"))
    }

    // Single-slide export sequence: read current skipped states → set all
    // others skipped → export → restore. The restore script must be
    // generated from the SAVED states (not blanket-unskip), so a deck with
    // pre-existing skipped slides round-trips its state exactly.
    func testSingleSlideToggleScripts() {
        let saved = [false, true, false, false, false]   // slide 2 was already skipped
        let toggle = KeynoteScripts.skipAllExcept(documentName: "D", keepIndex: 3, slideCount: 5)
        XCTAssertTrue(toggle.contains("set skipped of slide 3 to false"))
        XCTAssertTrue(toggle.contains("set skipped of slide 1 to true"))
        XCTAssertFalse(toggle.contains("set skipped of slide 3 to true"))

        let restore = KeynoteScripts.restoreSkippedStates(documentName: "D", states: saved)
        XCTAssertTrue(restore.contains("set skipped of slide 1 to false"))
        XCTAssertTrue(restore.contains("set skipped of slide 2 to true"),
                      "pre-existing skipped state must be restored, not blanket-unskipped")
        XCTAssertTrue(restore.contains("set skipped of slide 5 to false"))
    }

    func testReadSkippedStatesScriptShape() {
        let script = KeynoteScripts.readSkippedStates(documentName: "D")
        XCTAssertTrue(script.contains("skipped of every slide"))
    }
}
