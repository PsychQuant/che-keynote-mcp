# Integration testing against real Keynote — why it needs a human

The unit suite (40 tests) runs anywhere and gates every build. The
**integration tier** (design D7) drives real Keynote 15.3 end-to-end and is
env-gated (`RUN_KEYNOTE_INTEGRATION=1`) because it cannot run headlessly:
**macOS 26 TCC requires a human at the machine to click "Allow" on the
Automation consent dialog once.** This doc records why, so nobody re-litigates
it, and how to run the verification when you are present.

## The TCC principal rule (root cause, probed 2026-07-19)

macOS 26 attributes each Apple event to a *responsible process* and decides
consent per that principal. A process's principal identity depends on how it is
signed:

| Launch form | Code identity | TCC treats it as | Result when no grant exists |
|---|---|---|---|
| `osascript` (Apple-signed) | stable, Apple | inherits ambient grant up the launch chain | **succeeds** (ambient grant present) |
| `swift file.swift` temp binary | anonymous ad-hoc, no bundle id | attributed to responsible parent → inherits ambient grant | **succeeds** |
| `.build/debug/CheKeynoteMCP` | ad-hoc **with** stable bundle id (`com.che-cheng.che-keynote-mcp`) | its own principal → dialog-eligible | **hangs** on the consent dialog (no human to click) |
| `swift test` via `xctest` | Apple-signed, stable (`com.apple.dt.xctest.tool`) | its own principal, ad-hoc test bundle → **not** dialog-eligible on macOS 26 | **instant-denies** (`-1743`), no dialog |
| `.build/release/CheKeynoteMCP` (Developer ID + hardened runtime + apple-events entitlement) | stable Developer ID | its own principal, dialog-eligible | shows **"CheKeynoteMCP wants to control Keynote"** — this is the production end-user surface |

The two facts that matter:

1. **Signing the binary is what isolates it as its own TCC principal.** That is
   correct and desirable — the end user grants *"CheKeynoteMCP → Keynote"* once
   and it sticks. But it also means the signed binary cannot piggy-back on the
   ambient grant that `osascript` and interpreter-run scripts inherit.
2. **`swift test` cannot verify the end-to-end path on macOS 26.** xctest is its
   own principal loading an ad-hoc test bundle, so the consent dialog never
   appears and every Apple event denies with `-1743`. This is not a bug in the
   suite — it is the platform. The `KeynoteIntegrationTests` XCTest cases exist
   as living documentation of the scenarios; they only pass on a machine where
   the *xctest* principal already holds an Automation grant for Keynote (rare).

What the platform *does* let us verify without the dialog:

- **Script validity.** A raw in-process `NSAppleScript` `get version` against
  Keynote returns `15.3` with no error — the exact code path
  `KeynoteController.run(_:)` uses. Templates in `KeynoteScripts.swift` are
  therefore syntactically valid against the live dictionary.
- **Error mapping.** Every denied path surfaces
  `KeynoteError.permissionDenied` as the structured actionable message —
  observed live and repeatedly.
- **Entitlement gate.** `codesign -d --entitlements` confirms the signed binary
  carries `com.apple.security.automation.apple-events` + an embedded
  `NSAppleEventsUsageDescription` (release.sh step 3 enforces this).

## The one-time grant must come first (`--setup`)

The automation consent dialog can only present when the requesting process is a
**foreground app**. The integration driver spawns the binary in the background
(as an MCP-stdio child), so it has no foreground context — a first-time
(`notDetermined`) request there cannot show the dialog and just denies, and
`swift test` cannot show it either. The grant is therefore established once,
separately, through the binary's own `--setup` flow (mirroring che-ical-mcp
`--setup` / che-apple-mail-mcp's Full Disk Access onboarding), which runs the
request inside an `NSApplication`. Because the grant is keyed to the Developer
ID **code identity**, not the launch path, one grant covers the MCP server, the
`--setup` binary, and the integration driver alike.

```bash
cd mcp/che-keynote-mcp
swift build -c release
codesign --force --options runtime --timestamp \
  --entitlements Sources/CheKeynoteMCP/Entitlements.plist \
  --sign "$DEVELOPER_ID" .build/release/CheKeynoteMCP        # DEVELOPER_ID = che-mcps Developer ID

.build/release/CheKeynoteMCP --check-tcc      # dialog-free status read
.build/release/CheKeynoteMCP --setup          # foreground; click Allow once
```

`--setup` foregrounds, presents **"CheKeynoteMCP" wants to control "Keynote"**
(when status is `notDetermined`), then confirms a live `get version` round-trip.
If `--check-tcc` shows `denied` instead of `not yet asked`, a persistent TCC
record is blocking the dialog — clear it first (System Settings → Privacy &
Security → Automation → CheKeynoteMCP → tick Keynote, or `tccutil reset
AppleEvents`), because `tccutil reset AppleEvents <bundle-id>` cannot target a
non-app-bundle CLI (`-10814`).

## Running the full end-to-end verification (maintainer, at the machine)

With the grant in place, `scripts/integration-driver.swift` replays all three
spec scenarios (`KeynoteIntegrationTests`) by driving the **signed** binary over
MCP stdio — the true production TCC surface:

```bash
swift scripts/integration-driver.swift .build/release/CheKeynoteMCP
```

Keynote opens, the driver builds a 3-slide deck (with the adversarial title
`He said "quit" \ 換行 🎉`), reads it back, exports a 3-page PDF, runs the
single-slide skipped-state restore, and the pipelined concurrency check.
Expected tail:

```
ALL 3 SCENARIOS PASSED against real Keynote
```

Record the grant + the pass in the release notes / CHANGELOG for v0.1.0 (spec
task 4.3's "TCC dialog verification recorded"). The grant persists, so
subsequent runs on the same machine no longer prompt.

### Why not run it in an autonomous/headless agent session

It hangs. The signed binary is dialog-eligible but the dialog blocks the Apple
event until a human clicks it; with nobody present, `create_presentation` never
returns. This is by design — TCC consent is a human-in-the-loop gate. The
autonomous portions of CI verify everything *except* the one-time grant; the
grant itself is a maintainer action.
