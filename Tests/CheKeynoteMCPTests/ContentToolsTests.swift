// ContentToolsTests.swift — che-keynote-mcp task 3.3 (spec requirements:
// "v1 tool surface" content slice + "User content enters scripts through
// parameterization, never raw interpolation").

import XCTest
@testable import CheKeynoteMCP

final class ContentToolsTests: XCTestCase {

    static let contentNames = [
        "set_slide_title", "set_slide_body", "add_text_item",
        "set_text_item", "list_text_items", "add_image",
    ]

    func testContentToolsRegistered() async {
        let server = await KeynoteMCPServer()
        let names = await server.tools.map(\.name)
        for name in Self.contentNames {
            XCTAssertTrue(names.contains(name), "missing content tool \(name)")
        }
    }

    // Injection corpus rides the content setters: the generated script must
    // contain the quoted form, and for corpus entries with quote/backslash
    // the raw input must never appear unquoted in script source.
    func testContentSettersOnlyInterpolateQuotedText() {
        for input in ScriptGenerationTests.injectionCorpus {
            let scripts = [
                KeynoteScripts.setSlideTitle(documentName: "D", slideIndex: 1, title: input),
                KeynoteScripts.setSlideBody(documentName: "D", slideIndex: 1, body: input),
                KeynoteScripts.addTextItem(documentName: "D", slideIndex: 1, text: input),
                KeynoteScripts.setTextItem(documentName: "D", slideIndex: 1, itemIndex: 2, text: input),
            ]
            for script in scripts {
                XCTAssertTrue(script.contains(KeynoteController.quoted(input)),
                              "script must contain quoted form for \(input.debugDescription)")
                if input.contains("\"") || input.contains("\\") {
                    XCTAssertFalse(script.contains("to \"\(input)\""),
                                   "raw unescaped input leaked into script for \(input.debugDescription)")
                }
            }
        }
    }

    func testSetTextItemScriptShape() {
        let script = KeynoteScripts.setTextItem(documentName: "Deck.key", slideIndex: 3, itemIndex: 2, text: "hi")
        XCTAssertTrue(script.contains("text item 2"))
        XCTAssertTrue(script.contains("slide 3"))
    }

    func testListTextItemsScriptShape() {
        let script = KeynoteScripts.listTextItems(documentName: "Deck.key", slideIndex: 4)
        XCTAssertTrue(script.contains("object text of every text item"))
        XCTAssertTrue(script.contains("slide 4"))
    }

    func testAddImageScriptUsesQuotedPOSIXFile() {
        let path = "/tmp/pic \"1\".png"
        let script = KeynoteScripts.addImage(documentName: "Deck.key", slideIndex: 1, path: path)
        XCTAssertTrue(script.contains("make new image"))
        XCTAssertTrue(script.contains("POSIX file \(KeynoteController.quoted(path))"))
    }

    // Handler-level: path validation precedes script assembly, so this needs
    // no Keynote — a nonexistent image path returns a structured error.
    func testAddImageRejectsNonexistentPath() async {
        let server = await KeynoteMCPServer()
        let result = await server.invokeToolForTesting(name: "add_image", arguments: [
            "document_name": .string("Deck.key"),
            "slide_index": .int(1),
            "path": .string("/nonexistent/pic.png"),
        ])
        XCTAssertEqual(result.isError, true)
        if case .text(let text, _, _)? = result.content.first {
            XCTAssertTrue(text.contains("找不到"), "error must be the family not-found message; got \(text)")
        } else {
            XCTFail("expected text content")
        }
    }
}
