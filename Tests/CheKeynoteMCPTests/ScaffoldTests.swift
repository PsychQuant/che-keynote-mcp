// ScaffoldTests.swift — che-keynote-mcp task 1.1: the package scaffold
// builds and the server shell initializes with an empty tool registry
// (25 tools land in the tool-surface tasks; count pinned there).

import XCTest
@testable import CheKeynoteMCP

final class ScaffoldTests: XCTestCase {

    func testToolNamesAreUnique() async {
        let server = await KeynoteMCPServer()
        let names = await server.tools.map(\.name)
        XCTAssertEqual(names.count, Set(names).count, "duplicate tool names in registry")
    }

    func testUnknownToolReturnsStructuredError() async {
        let server = await KeynoteMCPServer()
        let result = await server.invokeToolForTesting(name: "nonexistent_tool")
        XCTAssertEqual(result.isError, true)
    }
}
