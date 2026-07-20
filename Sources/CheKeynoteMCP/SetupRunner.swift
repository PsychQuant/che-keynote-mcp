import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Drives the `--setup` and `--check-tcc` CLI flows for the macOS TCC
/// "Automation" (Apple events → Keynote) grant.
///
/// **Why a dedicated setup flow (the che-ical-mcp / che-apple-mail-mcp lesson).**
/// The automation consent dialog ("CheKeynoteMCP wants to control Keynote")
/// can only present when the requesting process is a *foreground* app
/// (`.regular` activation) — a bare CLI spawned in the background by another
/// process (an MCP client, `swift test`, or the integration driver) has no
/// foreground context, so a first-time (`notDetermined`) request cannot show
/// the dialog and simply denies. che-ical-mcp hit the identical wall with
/// EventKit's `requestFullAccess` and solved it by running the request inside
/// an `NSApplication` (SetupRunner #143 / #163); che-apple-mail-mcp did the same
/// for Full Disk Access. This mirrors that pattern for Apple events: the user
/// runs `CheKeynoteMCP --setup` once from a Terminal, grants, and — because the
/// grant is keyed to the Developer ID code identity, not the launch path — every
/// later spawn (MCP client, tests) inherits it.
/// The `--setup` action for a given permission state + interactivity. Pure so
/// the one branch that MUST NOT run (prompting from a non-interactive session)
/// is unit-testable without a real dialog — mirrors che-ical-mcp's
/// `setupAccessDecision`. Prompting (`askUserIfNeeded: true`) from a context
/// that cannot present the dialog does not just fail: macOS records a
/// **persistent deny**, so the guard here is a correctness requirement, not a
/// nicety.
enum SetupAction: Equatable {
    case alreadyGranted
    /// A persistent deny record exists — prompting will not re-present; the
    /// user must clear it in System Settings / `tccutil reset` first.
    case denied
    /// Interactive + never-asked → present the consent dialog.
    case prompt
    /// Never-asked but no controlling terminal → MUST NOT prompt (it would
    /// auto-deny and persist the record); print guidance and stop.
    case skipNonInteractive
}

func setupAction(status: AutomationPermission, isInteractive: Bool) -> SetupAction {
    switch status {
    case .granted:
        return .alreadyGranted
    case .denied:
        return .denied
    case .notDetermined, .targetNotFound, .unknown:
        return isInteractive ? .prompt : .skipNonInteractive
    }
}

enum SetupRunner {

    /// True when the process has a controlling terminal on stdin — a proxy for
    /// "a human is here to click Allow". A headless spawn cannot present the
    /// dialog, so `--setup` warns instead of hanging (mirrors che-ical-mcp
    /// NonInteractiveDetection #143).
    static var isInteractive: Bool { isatty(fileno(stdin)) != 0 }

    /// Identity line shared by both flows: which client TCC will record, and at
    /// what path — so the user can match the System Settings → Automation entry.
    private static func identityLines() -> [String] {
        let bundleID = Bundle.main.bundleIdentifier ?? "(no CFBundleIdentifier)"
        let path = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "(unknown)"
        return [
            "CheKeynoteMCP automation client:",
            "  bundle id: \(bundleID)",
            "  binary:    \(path)",
        ]
    }

    /// `--check-tcc`: print identity + current automation status toward the
    /// installed Keynote, with no dialog. Exit 0 iff granted.
    static func printStatus() -> Int32 {
        identityLines().forEach { print($0) }
        guard let bundleID = KeynoteController.installedKeynoteBundleID() else {
            print("  Keynote:   ✗ not installed (baseline: macOS 26 + current Keynote)")
            return 1
        }
        let permission = AutomationPermission.probe(bundleID: bundleID, askUserIfNeeded: false)
        print("  target:    \(bundleID)")
        print("  Automation → Keynote: \(permission.statusLine)")
        return permission.isGranted ? 0 : 1
    }

    /// `--setup`: bring the process foreground and, if consent was never asked,
    /// present the automation dialog; then confirm the real script path works.
    /// Exit 0 iff Keynote automation is granted at the end.
    @MainActor
    static func runSetup() async -> Int32 {
        identityLines().forEach { print($0) }

        guard let bundleID = KeynoteController.installedKeynoteBundleID() else {
            print("✗ Keynote is not installed. Install it (baseline: macOS 26 + current Keynote), then re-run --setup.")
            return 1
        }
        print("  target:    \(bundleID)\n")

        // Dialog-free read FIRST — never poisons TCC state.
        let current = AutomationPermission.probe(bundleID: bundleID, askUserIfNeeded: false)
        switch setupAction(status: current, isInteractive: isInteractive) {
        case .alreadyGranted:
            print("✓ Automation → Keynote already granted.")
        case .denied:
            print("✗ Automation → Keynote is explicitly DENIED (a persistent TCC record blocks the dialog).")
            print("  Clear it, then re-run --setup from a Terminal:")
            print("    • System Settings → Privacy & Security → Automation → CheKeynoteMCP → tick Keynote")
            print("    • or reset all Apple-events grants:  tccutil reset AppleEvents")
            return 1
        case .skipNonInteractive:
            // Do NOT probe with askUserIfNeeded here: from a non-foreground
            // session that would auto-deny and persist the record.
            print("⚠ Non-interactive session: the consent dialog cannot present here, and")
            print("  requesting anyway would record a persistent denial. Not requesting.")
            print("  Run `.build/release/CheKeynoteMCP --setup` from a real Terminal and click Allow.")
            return 1
        case .prompt:
            #if canImport(AppKit)
            // Foreground the process so the system consent dialog can appear
            // frontmost (the crux — see the type doc above).
            let app = NSApplication.shared
            app.setActivationPolicy(.regular)
            app.activate(ignoringOtherApps: true)
            #endif
            print("Requesting Automation permission — click Allow on the \"CheKeynoteMCP wants to control Keynote\" dialog…")
            let afterPrompt = AutomationPermission.probe(bundleID: bundleID, askUserIfNeeded: true)
            guard afterPrompt.isGranted else {
                print("✗ Not granted (\(afterPrompt.statusLine)).")
                print("  If no dialog appeared, run --setup from a foreground Terminal window,")
                print("  or grant manually: System Settings → Privacy & Security → Automation → CheKeynoteMCP → Keynote.")
                return 1
            }
            print("✓ Granted.")
        }

        // Confirm the real production path end-to-end: a benign script through
        // the exact KeynoteController.run used by every tool.
        do {
            let version = try await KeynoteController().run("tell application \"Keynote\" to get version")
            print("✓ Verified: Keynote automation works (Keynote version \(version.stringValue ?? "?")).")
            print("  This grant now covers the MCP server and the integration suite (same code identity).")
            return 0
        } catch {
            print("✗ Grant reported OK but a live script still failed: \(error.localizedDescription)")
            return 1
        }
    }
}
