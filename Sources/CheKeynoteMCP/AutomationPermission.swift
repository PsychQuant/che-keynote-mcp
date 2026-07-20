import Foundation
import CoreServices

/// The macOS TCC "Automation" (Apple events) permission state of *this*
/// process toward a target app. Wraps `AEDeterminePermissionToAutomateTarget`,
/// the one API that reports the automation-consent status — and, with
/// `askUserIfNeeded: true`, presents the consent dialog — without side effects
/// on the target (unlike sending a real Apple event, it does not run a script).
///
/// This is the check-side complement to `KeynoteController.map(errorDict:)`:
/// that maps an NSAppleScript *failure* to `.permissionDenied`; this reports
/// the standing grant *before* any script runs, so `--check-tcc` / `--setup`
/// can tell "never asked" (`notDetermined`) apart from "explicitly denied".
enum AutomationPermission: Equatable {
    /// Consent granted — Apple events to the target will go through.
    case granted
    /// Explicitly denied — a persistent TCC deny record exists. The dialog
    /// will NOT re-appear; the user must re-enable the entry in System
    /// Settings → Privacy & Security → Automation (or `tccutil reset`).
    case denied
    /// Never asked. `askUserIfNeeded: true` will present the consent dialog
    /// (requires a foreground app context — see `SetupRunner`).
    case notDetermined
    /// The target app is not running / not found (`procNotFound`). Consent may
    /// still be grantable; the caller should ensure the target is launchable.
    case targetNotFound
    /// Any other OSStatus, carried verbatim for diagnostics.
    case unknown(OSStatus)

    var isGranted: Bool { self == .granted }

    // Apple Event Manager OSStatus values (numeric literals: the named
    // constants are not all surfaced as Swift symbols across SDKs).
    static let errAEEventNotPermitted: OSStatus = -1743
    static let errAEEventWouldRequireUserConsent: OSStatus = -1744
    static let procNotFound: OSStatus = -600

    /// Pure mapping from the `AEDeterminePermissionToAutomateTarget` OSStatus
    /// to a case — extracted so the branch logic is unit-testable without a
    /// real Apple event round-trip.
    static func map(_ status: OSStatus) -> AutomationPermission {
        switch status {
        case noErr: return .granted
        case errAEEventNotPermitted: return .denied
        case errAEEventWouldRequireUserConsent: return .notDetermined
        case procNotFound: return .targetNotFound
        default: return .unknown(status)
        }
    }

    /// Human-readable status line for `--check-tcc` / `--setup` output.
    var statusLine: String {
        switch self {
        case .granted: return "✓ granted"
        case .denied: return "✗ denied (persistent TCC record — re-enable in System Settings → Automation, or tccutil reset)"
        case .notDetermined: return "◌ not yet asked (run --setup from an interactive Terminal to grant)"
        case .targetNotFound: return "… Keynote not running (consent still grantable; --setup will launch it)"
        case .unknown(let status): return "? unknown (OSStatus \(status))"
        }
    }

    /// Probe the automation permission toward `bundleID`.
    /// `askUserIfNeeded == true` presents the consent dialog when the status is
    /// `notDetermined` — but only when the process is a foreground app with a
    /// pumping run loop (see `SetupRunner.runSetup`). With `false` it is a
    /// pure, dialog-free status read (used by `--check-tcc`).
    static func probe(bundleID: String, askUserIfNeeded: Bool) -> AutomationPermission {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let aeDesc = target.aeDesc else { return .unknown(-1701) /* errAEDescNotFound */ }
        let status = AEDeterminePermissionToAutomateTarget(
            aeDesc, typeWildCard, typeWildCard, askUserIfNeeded)
        return map(status)
    }
}
