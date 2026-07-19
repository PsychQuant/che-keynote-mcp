# AppleScript capability boundary — risk register

Dictionary snapshot: **2026-07-18**, baseline **macOS 26 + current Mac App
Store Keynote** (issue #140 clarity decision). Every v1 tool promise is
bounded by this register; tool descriptions state the user-facing subset.
Sources are the deep-search report
([PsychQuant/macdoc#140](https://github.com/PsychQuant/macdoc/issues/140)
attachment) and the repos in `references/`.

| # | Gap / constraint | Detail | Source |
|---|------------------|--------|--------|
| 1 | Shape fill color not settable | AppleScript dictionary has no writable fill for shapes; keynote-cli works around via duplicate-shape tricks (fragile, not adopted in v1) | josephyooo/keynote-cli README |
| 2 | Slide background color not settable | Same dictionary gap as #1 | josephyooo/keynote-cli README |
| 3 | Equation insertion unreachable | Only possible via System Events UI scripting (menu simulation) — v2 evaluation item, needs Accessibility permission | josephyooo/keynote-cli README |
| 4 | Hyperlink insertion unreachable | Same UI-scripting-only situation as #3 | josephyooo/keynote-cli + reichenbach/iwork_mcp READMEs |
| 5 | Chart customization not exposed | Apple does not expose chart creation/editing to AppleScript at all | reichenbach/iwork_mcp README |
| 6 | No native single-slide export API | Per-slide PDF export is done by toggling the `skipped` property of all other slides, exporting, then restoring — v1 implements this technique with guaranteed state restore | iworkautomation.com (Document Export) |
| 7 | Scripting is not concurrency-safe | Concurrent AppleScript sessions against one document corrupt state; all operations serialize through the single `KeynoteController` actor (design D2 — structural, not advisory) | josephyooo/keynote-cli README |
| 8 | ~430ms per AppleEvent round-trip | Measured by prior art; multi-slide operations must batch (20 slides/batch, keynote-cli pattern) or large decks become unusable | reichenbach/iwork_mcp README |
| 9 | Dictionary drifts across Keynote versions | Apple changes the scripting dictionary and (for .key parsing) renames Protobuf definitions between versions; this register and the integration suite are the drift detectors | psobot/keynote-parser README (schema-drift warning) |

## Out-of-scope escalations (v2+ evaluation, not v1)

- **UI-scripting layer** (System Events) for gaps 1–4: fragile (breaks on
  Keynote UI changes), requires Accessibility permission on top of
  AppleEvents. File a follow-up when real demand appears.
- **Direct `.key` parsing** (IWA/Protobuf): viable (keynote-parser proves
  round-trip) but structurally burdened by gap 9, and would require a
  `native-macos-compat.md` exception review for Protobuf/Snappy
  dependencies in the macdoc ecosystem.
