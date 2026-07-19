// ToolSurfaceTests.swift — che-keynote-mcp tasks 3.4 + 3.5 (spec
// requirements: "v1 tool surface covers six categories with 25 tools" +
// "The capability boundary is part of the published contract").

import XCTest
@testable import CheKeynoteMCP

final class ToolSurfaceTests: XCTestCase {

    static let allNames: Set<String> = [
        // lifecycle (6)
        "create_presentation", "open_presentation", "save_presentation",
        "close_presentation", "list_presentations", "get_presentation_info",
        // slide CRUD (7)
        "add_slide", "delete_slide", "duplicate_slide", "move_slide",
        "list_slides", "get_slide_info", "set_slide_skipped",
        // content (6)
        "set_slide_title", "set_slide_body", "add_text_item",
        "set_text_item", "list_text_items", "add_image",
        // notes (2)
        "set_presenter_notes", "get_presenter_notes",
        // export (2)
        "export_pdf", "export_images",
        // playback (2)
        "start_slideshow", "stop_slideshow",
    ]

    func testExactly25ToolsMatchingSpecList() async {
        let server = await KeynoteMCPServer()
        let names = await Set(server.tools.map(\.name))
        XCTAssertEqual(Self.allNames.count, 25, "spec list itself must hold 25 names")
        XCTAssertEqual(names, Self.allNames,
                       "registry mismatch — missing: \(Self.allNames.subtracting(names)), extra: \(names.subtracting(Self.allNames))")
    }

    // Spec scenario "boundary is discoverable before calling": content and
    // export tool descriptions state the relevant v1 limits.
    func testBoundaryStatementsInDescriptions() async {
        let server = await KeynoteMCPServer()
        let tools = await server.tools
        let contentDescriptions = tools.filter { ["set_slide_title", "set_slide_body"].contains($0.name) }
            .compactMap(\.description)
        XCTAssertEqual(contentDescriptions.count, 2, "both content setters must carry descriptions")
        for description in contentDescriptions {
            XCTAssertTrue(description.contains("applescript-boundary"),
                          "content tool descriptions must point at the boundary doc")
            XCTAssertTrue(description.contains("hyperlink") || description.contains("equation"),
                          "content tool descriptions must state the dictionary gaps")
        }
        let export = tools.first { $0.name == "export_pdf" }
        XCTAssertTrue(export?.description?.contains("skipped") == true,
                      "export_pdf description must explain the single-slide skipped-toggle mechanism")
    }

    func testPresenterNotesScriptShapes() {
        let set = KeynoteScripts.setPresenterNotes(documentName: "D", slideIndex: 2, notes: "note \"x\"")
        XCTAssertTrue(set.contains("presenter notes"))
        XCTAssertTrue(set.contains(KeynoteController.quoted("note \"x\"")))
        let get = KeynoteScripts.getPresenterNotes(documentName: "D", slideIndex: 2)
        XCTAssertTrue(get.contains("return presenter notes"))
    }

    func testSlideshowScriptShapes() {
        XCTAssertTrue(KeynoteScripts.startSlideshow(documentName: "D").contains("start"))
        XCTAssertTrue(KeynoteScripts.stopSlideshow().contains("stop"))
    }
}
