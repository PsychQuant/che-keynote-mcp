// SlideToolsTests.swift — che-keynote-mcp task 3.2 (spec requirements:
// "v1 tool surface" slide-CRUD slice + "Multi-slide operations batch their
// AppleScript" — 45 slides / size 20 → exactly 3 scripts).

import XCTest
@testable import CheKeynoteMCP

final class SlideToolsTests: XCTestCase {

    static let slideNames = [
        "add_slide", "delete_slide", "duplicate_slide", "move_slide",
        "list_slides", "get_slide_info", "set_slide_skipped",
    ]

    func testSlideToolsRegistered() async {
        let server = await KeynoteMCPServer()
        let names = await server.tools.map(\.name)
        for name in Self.slideNames {
            XCTAssertTrue(names.contains(name), "missing slide tool \(name)")
        }
    }

    func testAddSlideScriptShape() {
        let with = KeynoteScripts.addSlide(documentName: "Deck.key", layout: "Title & Content")
        XCTAssertTrue(with.contains("make new slide"))
        XCTAssertTrue(with.contains("slide layout \(KeynoteController.quoted("Title & Content"))"))
        let without = KeynoteScripts.addSlide(documentName: "Deck.key", layout: nil)
        XCTAssertTrue(without.contains("make new slide"))
        XCTAssertFalse(without.contains("slide layout"))
    }

    func testMoveSlideScriptShape() {
        let script = KeynoteScripts.moveSlide(documentName: "Deck.key", from: 5, toBefore: 2)
        XCTAssertTrue(script.contains("move slide 5"))
        XCTAssertTrue(script.contains("before slide 2"))
    }

    func testSetSlideSkippedScriptShape() {
        let script = KeynoteScripts.setSlideSkipped(documentName: "Deck.key", slideIndex: 3, skipped: true)
        XCTAssertTrue(script.contains("set skipped of slide 3 to true"))
    }

    // Spec scenario: 45-slide deck, batch size 20 → 3 script executions
    // covering 1–20, 21–40, 41–45 (not 45 per-slide round-trips).
    func testListSlidesBatchScriptsMatchSpecExample() {
        let scripts = KeynoteScripts.listSlidesBatches(documentName: "Deck.key", slideCount: 45, batchSize: 20)
        XCTAssertEqual(scripts.count, 3)
        XCTAssertTrue(scripts[0].contains("slides 1 thru 20"))
        XCTAssertTrue(scripts[1].contains("slides 21 thru 40"))
        XCTAssertTrue(scripts[2].contains("slides 41 thru 45"))
    }

    func testListSlidesBatchSingleSlideDeck() {
        let scripts = KeynoteScripts.listSlidesBatches(documentName: "Deck.key", slideCount: 1, batchSize: 20)
        XCTAssertEqual(scripts.count, 1)
        XCTAssertTrue(scripts[0].contains("slides 1 thru 1"))
    }

    func testListSlidesBatchEmptyDeck() {
        XCTAssertEqual(KeynoteScripts.listSlidesBatches(documentName: "Deck.key", slideCount: 0, batchSize: 20).count, 0)
    }
}
