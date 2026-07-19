// LifecycleToolsTests.swift — che-keynote-mcp task 3.1 (spec requirement:
// "v1 tool surface covers six categories with 25 tools" — lifecycle slice).

import XCTest
import MCP
@testable import CheKeynoteMCP

final class LifecycleToolsTests: XCTestCase {

    static let lifecycleNames = [
        "create_presentation", "open_presentation", "save_presentation",
        "close_presentation", "list_presentations", "get_presentation_info",
    ]

    func testLifecycleToolsRegistered() async {
        let server = await KeynoteMCPServer()
        let names = await server.tools.map(\.name)
        for name in Self.lifecycleNames {
            XCTAssertTrue(names.contains(name), "missing lifecycle tool \(name)")
        }
    }

    func testCreatePresentationScriptShape() {
        let script = KeynoteScripts.createPresentation(theme: "White")
        XCTAssertTrue(script.contains("tell application \"Keynote\""))
        XCTAssertTrue(script.contains("make new document"))
        XCTAssertTrue(script.contains(KeynoteController.quoted("White")))
    }

    func testOpenPresentationScriptUsesPOSIXFileWithQuotedPath() {
        let path = "/tmp/My \"Deck\".key"
        let script = KeynoteScripts.openPresentation(path: path)
        XCTAssertTrue(script.contains("POSIX file \(KeynoteController.quoted(path))"))
        XCTAssertTrue(script.contains("open"))
    }

    func testGetPresentationInfoScriptQueriesCoreProperties() {
        let script = KeynoteScripts.presentationInfo(documentName: "Deck.key")
        for token in ["name", "count of slides", "tell document \(KeynoteController.quoted("Deck.key"))"] {
            XCTAssertTrue(script.contains(token), "info script missing \(token)")
        }
    }

    func testUnknownToolStillErrorsAfterRegistration() async {
        let server = await KeynoteMCPServer()
        let result = await server.invokeToolForTesting(name: "definitely_not_a_tool")
        XCTAssertEqual(result.isError, true)
    }
}
