# che-keynote-mcp

Swift-native MCP server for Apple Keynote — create, edit, and export
presentations through Claude, driven by in-process `NSAppleScript` (Apple's
supported automation path: TCC permission attributes to this signed binary,
not to an `osascript` subprocess).

Part of the che-mcps family (che-word-mcp / che-pptx-mcp / che-pdf-mcp /
che-logic-pro-mcp / che-ical-mcp).

## Status

v0.1.0 scaffold — v1 tool surface (25 tools, six categories) in progress.
Spec: `keynote-mcp-server` capability in
[PsychQuant/macdoc](https://github.com/PsychQuant/macdoc) openspec;
tracking issue [PsychQuant/macdoc#140](https://github.com/PsychQuant/macdoc/issues/140).

## Baseline

macOS 26 + current Mac App Store Keynote. Older versions are not tested and
not promised (the AppleScript dictionary drifts across Keynote versions).

## v1 capability boundary (honest limits)

AppleScript-dictionary gaps — **not available in v1** and stated in tool
descriptions: shape fill color, slide background color, equation insertion,
hyperlink insertion, chart customization, direct `.key` parsing. Details and
sources: `docs/applescript-boundary.md`.

## References

`references/` is clone-on-demand (only its README is tracked) — see
`references/README.md` for the curated reference repos and the AGPL warning
about WorkKit.

## License

MIT
