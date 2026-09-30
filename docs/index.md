# MacMarkDown — Documentation Index

> **Version**: 1.0.0 | **Date**: 2026-10-01 | **Platform**: macOS 26+

## Overview

MacMarkDown is a native Markdown editor for macOS, written from scratch in pure
Swift and SwiftUI. macOS 26 and Swift 6.4 opened a new era for Apple's
developer frameworks: SwiftUI, the Observation framework, TextKit 2 and Swift
concurrency are now mature enough to carry a complete, high-performance writing
tool. MacMarkDown was written for that era, and these documents describe how it
is designed, built, tested and maintained.

## Document Map

### Architecture

| Document | Description |
|----------|-------------|
| [ADR-001: Pure SwiftUI Architecture](architecture/adr-001-pure-swiftui.md) | Decision to use SwiftUI for all UI |
| [ADR-002: Swift Markdown Parser](architecture/adr-002-swift-markdown.md) | Decision to use Apple's swift-markdown |
| [ADR-003: Native Preview Rendering](architecture/adr-003-native-preview.md) | Decision to render the preview natively |
| [ADR-004: Editor Theme System](architecture/adr-004-editor-themes.md) | Decision to use Swift-defined editor themes |

### Business

| Document | Description |
|----------|-------------|
| [Product Overview](business/overview.md) | Product goals, scope, and roadmap |

### Design

| Document | Description |
|----------|-------------|
| [RFC-001: Core Architecture](design/rfc-001-core-architecture.md) | System architecture and component design |
| [RFC-002: Rendering Pipeline](design/rfc-002-rendering-pipeline.md) | Markdown to native view pipeline |
| [RFC-003: Editor Integration](design/rfc-003-editor-integration.md) | Editor design and key handling |

### Guides

| Document | Description |
|----------|-------------|
| [Development Guide](guide/guide.md) | Setup, build, and development workflow |
| [Contributing Guide](guide/contributing.md) | How to contribute |

### Reference

| Document | Description |
|----------|-------------|
| [Swift 26 Compliance Audit](reference/apple-swift-26-compliance-audit.md) | Swift 6.4 strict concurrency audit |

### Postmortems

| Document | Description |
|----------|-------------|
| [2026-09 Field Incidents](postmortems/2026-09-field-incidents.md) | Risks, incidents and resolutions |

## Quick Links

- **Source Code**: `MacMarkDown/` directory
- **Tests**: `MacMarkDown/Tests/`
- **Scripts**: `scripts/`

## Conventions

All documents are provided in English (`.md`) and Chinese (`.zh.md`) variants.
