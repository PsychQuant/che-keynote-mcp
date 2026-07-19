// ErrorMappingTests.swift — che-keynote-mcp task 2.2 (spec requirement:
// "Failures surface as structured actionable errors"). Feeds synthetic
// NSAppleScript error dictionaries and pins the message shapes.

import XCTest
@testable import CheKeynoteMCP

final class ErrorMappingTests: XCTestCase {

    private func dict(number: Int, message: String) -> NSDictionary {
        [NSAppleScript.errorNumber: number, NSAppleScript.errorMessage: message]
    }

    func testPrivilegeErrorNumbersMapToPermissionDenied() {
        for number in [-1743, -1719, -10004] {
            let mapped = KeynoteController.map(errorDict: dict(number: number, message: "whatever"))
            XCTAssertEqual(mapped, .permissionDenied, "error \(number) must map to permissionDenied")
        }
    }

    func testNotAllowedMessageMapsToPermissionDenied() {
        let mapped = KeynoteController.map(errorDict: dict(number: -2700, message: "Keynote is not allowed to be scripted"))
        XCTAssertEqual(mapped, .permissionDenied)
    }

    func testPermissionDeniedMessageNamesSettingsPath() {
        let message = KeynoteError.permissionDenied.errorDescription ?? ""
        for fragment in ["System Settings", "Privacy & Security", "Automation", "CheKeynoteMCP", "Keynote"] {
            XCTAssertTrue(message.contains(fragment),
                          "TCC-denied message must name the Settings path; missing: \(fragment)")
        }
    }

    func testScriptErrorCarriesNumberAndKeynoteMessage() {
        let mapped = KeynoteController.map(errorDict: dict(number: -1728, message: "Can't get slide 99 of document 1."))
        XCTAssertEqual(mapped, .scriptError(number: -1728, message: "Can't get slide 99 of document 1."))
        let text = mapped.errorDescription ?? ""
        XCTAssertTrue(text.contains("-1728") && text.contains("Can't get slide 99"),
                      "script error text must contain the AppleScript number and Keynote's message")
    }

    func testNilDictionaryStillProducesStructuredError() {
        let mapped = KeynoteController.map(errorDict: nil)
        if case .scriptError(let number, let message) = mapped {
            XCTAssertEqual(number, -1)
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("nil dictionary must map to a scriptError, got \(mapped)")
        }
    }

    func testKeynoteNotAvailableMessageIsActionable() {
        let message = KeynoteError.keynoteNotAvailable.errorDescription ?? ""
        XCTAssertTrue(message.contains("Mac App Store"), "must tell the user where to get Keynote")
        XCTAssertTrue(message.contains("macOS 26"), "must state the baseline")
    }
}
