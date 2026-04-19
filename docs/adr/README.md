# Architecture Decision Records

This directory contains retained Architecture Decision Records (ADRs) for Boombox.

## What is an ADR?

An ADR is a document that captures an important architectural decision made along with its context and consequences. ADRs help:

- **Preserve context** for why decisions were made
- **Onboard new team members** faster
- **Avoid repeating discussions** about past decisions
- **Document trade-offs** considered during design

## Format

Each ADR follows this format:

```markdown
# ADR-NNNN: Title

## Status
[Proposed | Accepted | Deprecated | Superseded by ADR-XXXX]

## Context
What is the issue that we're seeing that is motivating this decision?

## Decision
What is the change that we're proposing and/or doing?

## Consequences
What becomes easier or more difficult because of this change?
```

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [0001](0001-webview-playback.md) | WebView-Based Playback | Accepted |
| [0002](0002-protocol-based-services.md) | Protocol-Based Service Design | Accepted |
| [0003](0003-modular-api-parsers.md) | Modular API Response Parsers | Accepted |
| [0006](0006-swift-testing-migration.md) | Swift Testing Migration | Accepted |
| [0008](0008-nonisolated-network-helpers.md) | Nonisolated Network Helpers for MainActor Classes | Accepted |
| [0009](0009-prompt-request-workflow.md) | Prompt Request Workflow | Accepted |
| [0010](0010-airplay-fix.md) | Fix AirPlay for WebView-Based Playback | Implemented (with known limitations) |
| [0012](0012-synced-lyrics-architecture.md) | Synced Lyrics Provider Architecture | Accepted |
