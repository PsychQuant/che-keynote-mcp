#!/bin/bash
# release.sh — signed + notarized release pipeline for CheKeynoteMCP
# (PsychQuant/che-keynote-mcp). Ported from che-word-mcp scripts/release.sh
# (PsychQuant/macdoc#119 signature-gate pattern) with the AppleEvents
# entitlements additions (che-ical-mcp #154 entitlements-gate pattern) —
# this binary NEEDS com.apple.security.automation.apple-events + an
# embedded NSAppleEventsUsageDescription for macOS 26 TCC.
#
# Usage: scripts/release.sh <version>        # e.g. scripts/release.sh 0.1.0
#
# Pipeline: unit tests → universal build → Developer ID codesign (hardened
# runtime + timestamp + ENTITLEMENTS) → entitlements gate → PRE-UPLOAD
# SIGNATURE GATE → notarize (Accepted) → sha256 → TOCTOU re-verify →
# gh release create with binary + .sha256.

set -euo pipefail

BINARY_NAME="CheKeynoteMCP"
REPO="PsychQuant/che-keynote-mcp"
DEVELOPER_ID="${DEVELOPER_ID:-F2523DCF6D02BE99B67C7D27F633119292DA4934}"
NOTARY_PROFILE="${NOTARY_PROFILE:-che-mcps-notary}"
ENTITLEMENTS="${ENTITLEMENTS:-Sources/CheKeynoteMCP/Entitlements.plist}"
REQUIREMENT='=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "6W377FS7BS"'

VERSION="${1:-}"
[[ -n "$VERSION" ]] || { echo "usage: scripts/release.sh <version>  (e.g. 0.1.0, no leading v)" >&2; exit 2; }
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z][0-9A-Za-z.-]*)?$ ]] || { echo "error: version '$VERSION' is not semver" >&2; exit 2; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "→ [0/8] pre-flight: notary profile alive? tree clean? tag free?"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || { echo "error: notary profile '$NOTARY_PROFILE' unusable — run: xcrun notarytool store-credentials $NOTARY_PROFILE (interactive, user-only)" >&2; exit 3; }
[[ -z "$(git status --porcelain)" ]] \
    || { echo "error: working tree not clean (including untracked files) — commit, stash, or clean first" >&2; exit 3; }
[[ -f "$ENTITLEMENTS" ]] \
    || { echo "error: entitlements file not found at $ENTITLEMENTS" >&2; exit 3; }
if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null 2>&1; then
    echo "error: local tag v$VERSION already exists" >&2; exit 3
fi
if [[ -n "$(git ls-remote --tags origin "refs/tags/v$VERSION" 2>/dev/null)" ]]; then
    echo "error: remote tag v$VERSION already exists" >&2; exit 3
fi
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "error: release v$VERSION already exists on $REPO" >&2; exit 3
fi

echo "→ [0.5/8] pre-flight: unit suite (integration tests skip unless RUN_KEYNOTE_INTEGRATION=1)"
swift test \
    || { echo "error: test suite failed — refusing to release" >&2; exit 3; }

echo "→ [1/8] universal release build"
swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/$BINARY_NAME"
[[ -f "$BIN" ]] || { echo "error: built binary not found at $BIN" >&2; exit 4; }

echo "→ [2/8] codesign (Developer ID, hardened runtime, timestamp, ENTITLEMENTS)"
codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$DEVELOPER_ID" "$BIN"

echo "→ [3/8] ENTITLEMENTS GATE — signed binary must carry apple-events + usage description"
codesign -d --entitlements - --xml "$BIN" 2>/dev/null | grep -q "com.apple.security.automation.apple-events" \
    || { echo "error: GATE FAILED — signed binary lacks the apple-events entitlement (TCC dialog would never appear on macOS 26)" >&2; exit 5; }
{ otool -s __TEXT __info_plist "$BIN" >/dev/null 2>&1 \
    && strings "$BIN" | grep -q "NSAppleEventsUsageDescription"; } \
    || { echo "error: GATE FAILED — embedded Info.plist with NSAppleEventsUsageDescription missing from binary" >&2; exit 5; }

echo "→ [4/8] PRE-UPLOAD SIGNATURE GATE (requirement-based, matches marketplace wrappers)"
codesign --verify --strict -R "$REQUIREMENT" "$BIN" \
    || { echo "error: GATE FAILED — asset is not a Developer ID Application binary of Team 6W377FS7BS; refusing to release" >&2; exit 5; }
ARCHS=" $(lipo -archs "$BIN" 2>/dev/null) "
[[ "$ARCHS" == *" arm64 "* && "$ARCHS" == *" x86_64 "* ]] \
    || { echo "error: GATE FAILED — binary is not universal (need arm64 + x86_64, got:$ARCHS)" >&2; exit 5; }

echo "→ [5/8] notarize (must be Accepted)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
ditto -c -k --keepParent "$BIN" "$WORKDIR/$BINARY_NAME.zip"
NOTARY_OUT=$(xcrun notarytool submit "$WORKDIR/$BINARY_NAME.zip" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)
echo "$NOTARY_OUT" | grep -q "status: Accepted" \
    || { echo "error: notarization not Accepted:" >&2; echo "$NOTARY_OUT" | tail -5 >&2; exit 6; }

echo "→ [6/8] sha256 asset"
cp "$BIN" "$WORKDIR/$BINARY_NAME"
shasum -a 256 "$WORKDIR/$BINARY_NAME" | awk '{print $1}' > "$WORKDIR/$BINARY_NAME.sha256"

echo "→ [7/8] FINAL GATE — re-verify the exact upload artifact (TOCTOU guard)"
codesign --verify --strict -R "$REQUIREMENT" "$WORKDIR/$BINARY_NAME" \
    || { echo "error: FINAL GATE FAILED — upload artifact no longer passes the signature requirement" >&2; exit 5; }
[[ "$(shasum -a 256 "$WORKDIR/$BINARY_NAME" | awk '{print $1}')" == "$(cat "$WORKDIR/$BINARY_NAME.sha256")" ]] \
    || { echo "error: FINAL GATE FAILED — sha256 asset does not match upload artifact" >&2; exit 5; }

echo "→ [8/8] gh release create (creates tag v$VERSION at HEAD)"
gh release create "v$VERSION" --repo "$REPO" \
    --target "$(git rev-parse HEAD)" \
    --title "v$VERSION" \
    --notes "Developer ID signed + Apple notarized universal binary (arm64 + x86_64) carrying the apple-events entitlement + embedded NSAppleEventsUsageDescription (macOS 26 TCC). Released via scripts/release.sh (entitlements gate + pre-upload signature gate)." \
    "$WORKDIR/$BINARY_NAME" "$WORKDIR/$BINARY_NAME.sha256"

echo "✓ released $BINARY_NAME v$VERSION (signed, notarized, entitlements-gated, sha256 attached)"
