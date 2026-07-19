# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Swift Package scaffold: `CheKeynoteMCP` executable (MCP swift-sdk 0.12+),
  `KeynoteMCPServer` shell with empty tool registry, embedded Info.plist
  (`NSAppleEventsUsageDescription` via `-sectcreate`) and
  `Entitlements.plist` (`com.apple.security.automation.apple-events`) for
  the macOS 26 TCC pipeline.
