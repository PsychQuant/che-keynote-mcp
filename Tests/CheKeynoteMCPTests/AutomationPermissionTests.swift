// AutomationPermissionTests.swift — pure unit coverage for the
// AEDeterminePermissionToAutomateTarget OSStatus → AutomationPermission
// mapping (che-keynote-mcp --setup / --check-tcc flow). No Apple event
// round-trip, so this runs anywhere and gates every build; the live grant
// itself is exercised by --setup + the integration driver (see
// docs/integration-testing.md).

import XCTest
@testable import CheKeynoteMCP

final class AutomationPermissionTests: XCTestCase {

    func testGrantedMapsFromNoErr() {
        XCTAssertEqual(AutomationPermission.map(OSStatus(noErr)), .granted)
        XCTAssertTrue(AutomationPermission.map(OSStatus(noErr)).isGranted)
    }

    func testDeniedMapsFromNotPermitted() {
        // -1743 errAEEventNotPermitted — a persistent TCC deny record.
        XCTAssertEqual(AutomationPermission.map(-1743), .denied)
        XCTAssertFalse(AutomationPermission.map(-1743).isGranted)
    }

    func testNotDeterminedMapsFromWouldRequireConsent() {
        // -1744 errAEEventWouldRequireUserConsent — never asked. This is the
        // state a fresh signed binary reports, distinguishing "ask me" from
        // the "denied" state that the same driver error would otherwise blur.
        XCTAssertEqual(AutomationPermission.map(-1744), .notDetermined)
    }

    func testTargetNotFoundMapsFromProcNotFound() {
        XCTAssertEqual(AutomationPermission.map(-600), .targetNotFound)
    }

    func testUnknownCarriesStatusVerbatim() {
        XCTAssertEqual(AutomationPermission.map(-42), .unknown(-42))
    }

    func testOnlyGrantedIsGranted() {
        for permission in [AutomationPermission.denied, .notDetermined, .targetNotFound, .unknown(-1)] {
            XCTAssertFalse(permission.isGranted, "\(permission) must not report granted")
        }
    }

    func testStatusLinesAreDistinctAndNonEmpty() {
        let lines = [
            AutomationPermission.granted, .denied, .notDetermined,
            .targetNotFound, .unknown(-7),
        ].map(\.statusLine)
        XCTAssertTrue(lines.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(lines).count, lines.count, "each status must render a distinct line")
    }
}
