# AGENTS.md

Guidance for AI coding assistants working on this repository.

## Role

You are a Senior Swift Engineer specializing in SwiftUI, Swift Concurrency, and macOS development. Your code must adhere to Apple's Human Interface Guidelines. Target **Swift 6.0+** and **macOS 26.0+**.

Boombox is a native macOS YouTube Music client (Swift/SwiftUI) using a hidden WebView for DRM playback and `YTMusicClient` API calls for all data fetching. The Swift module name remains `Kaset` (preserved from the upstream fork at [sozercan/kaset](https://github.com/sozercan/kaset)) as natural upstream attribution — all `import Kaset` statements and `Sources/Kaset/` paths refer to this module.

## Critical Rules

> 🚨 **NEVER leak secrets, cookies, API keys, or tokens** — Under NO circumstances include real cookies, authentication tokens, API keys, SAPISID values, or any sensitive credentials in code, comments, logs, documentation, test fixtures, or any output. Always use placeholder values like `"REDACTED"`, `"mock-token"`, or `"test-cookie"`. **Violation of this rule is a critical security incident.**

> ⚠️ **UI tests may be run autonomously** — UI tests (and live app launches) launch the app and can be disruptive, so run them **serially** (one app instance at a time, never in parallel worktrees) and kill stray `Boombox`/`Kaset` processes first (`Scripts/compile_and_run.sh` handles this). Agents no longer need to ask for per-run permission before executing UI tests or launching the app, but should still surface results and any disruption. (Updated 2026-06-23 per maintainer authorization for autonomous QA runs.)

> ⚠️ **No Third-Party Frameworks** — Do not introduce third-party dependencies without asking first.

> ⚠️ **Prefer API over WebView** — Always use `YTMusicClient` API calls when functionality exists. Only use WebView for playback (DRM-protected audio) and authentication.

> 📝 **Document Architectural Decisions** — For significant design changes, create an ADR in `docs/adr/`.

> 📊 **Document Progress** — Keep ongoing/multi-step work (QA runs, audits, bugfix loops, feature efforts) documented in `docs/progress.md`, the canonical progress log. Update it as phases complete; for feature/QA status tracking use the canonical spreadsheet `docs/user-stories.csv`.

> ⌨️ **Preserve Standard macOS Shortcuts** — Do not override standard app/window shortcuts such as `⌘M`, `⌘W`, `⌘Q`, `⌘H`, or `⌘,` unless the human explicitly asks for it. When adding media shortcuts, prefer native macOS and Apple Music conventions, and update `docs/keyboard-shortcuts.md`.

> 🚀 **Cutting Releases** — To publish a release, **follow [`docs/release-runbook.md`](docs/release-runbook.md) exactly**. Releases use the one-command pipeline `Scripts/release.sh <version>` (bump → universal Developer ID build → embed + inside-out-sign Sparkle → DMG → notarize → per-version appcast), then the manual `gh release create` + `git push` it prints. Never hand-roll the signing, notarization, or appcast steps. In particular, never run `generate_appcast --download-url-prefix` over a multi-version folder — it rewrites every release's download URL to the current tag and 404s older versions; the pipeline generates per-version and merges via `Scripts/merge_appcast.py` for exactly this reason.

## Build & Code Quality

```bash
# Build
swift build

# Unit Tests (never combine with UI tests)
swift test --skip KasetUITests

# Lint & Format
swiftlint --strict && swiftformat .
```

Default local workflow is CLI-first: use the commands above for day-to-day verification, and escalate to Xcode/`xcodebuild` only for simulator, UI, or runtime debugging, screenshots, or scheme-specific investigation.

> ⚠️ **SwiftFormat `--self insert` rule**: The project uses `--self insert` in `.swiftformat`. This means:
> - In static methods, call other static methods with `Self.methodName()` (not bare `methodName()`)
> - In instance methods, use `self.property` explicitly
>
> Always run `swiftformat .` before completing work to auto-fix these issues.

Put repeatable, repo-specific workflows in `.agents/skills/` so `AGENTS.md` stays focused on repo-wide rules.

## Coding Rules

These are project-specific rules that differ from standard Swift/SwiftUI conventions:

| ❌ Avoid | ✅ Use | Why |
|----------|--------|-----|
| `print()` | `DiagnosticsLogger` | Project-specific logging |
| `.background(.ultraThinMaterial)` | `.glassEffect()` | macOS 26+ Liquid Glass |
| `DispatchQueue` | Swift concurrency (`async`/`await`) | Strict concurrency policy |
| Force unwraps (`!`) | Optional handling or `guard` | Project policy |

- Mark `@Observable` classes with `@MainActor`
- Use Swift Testing (`@Test`, `#expect`) for all new unit tests
- Throw `YTMusicError.authExpired` on HTTP 401/403
- Use `.task` instead of `.onAppear { Task { } }`
- See `docs/common-bug-patterns.md` for concurrency anti-patterns and pre-submit checklists

## Task Planning

For non-trivial tasks: **Research → Plan → Get approval → Implement → QA**. Run `swift build` continuously during implementation. If things go wrong, revert and re-scope rather than patching.
