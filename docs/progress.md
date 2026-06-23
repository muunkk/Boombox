# Boombox — Autonomous QA & Bugfix Run · Progress Log

> **Canonical progress log** for the ongoing autonomous QA / user-story / bugfix loop.
> Keep this file updated as work proceeds. The canonical feature/status spreadsheet is
> [`docs/user-stories.csv`](./user-stories.csv); this file narrates the run around it.

- **Branch:** `qa/user-story-audit-fixes`
- **Started:** 2026-06-23
- **Goal:** Document every feature as a user story (expected behavior derived from code) →
  test every story + hunt bugs → fix every logistical/UX error & bug → retest → push → PR →
  merge when CI is green. Loop until green, then report.
- **Merge gate (CI on every PR to `main`):** unit tests (`swift test --skip KasetUITests`),
  UI tests (`xcodebuild` on macos-26), SwiftLint `--strict`, SwiftFormat `--lint`, release Dev Build.

## Phase Loop

| Phase | Description | Status |
|-------|-------------|--------|
| P0 | Setup & green baseline (branch, relax UI-test rule, baseline build/test/lint/format) | ✅ Done |
| P1 | Document every feature → user stories → canonical `docs/user-stories.csv` | ✅ Done — **373 stories**, 15 areas |
| P2 | Test every user story + hunt bugs → document all errors in the CSV | 🔄 In progress (bug hunt landing) |
| P3 | Synthesize prioritized fix plan from findings | ⏳ Pending |
| P4 | Fix every logistical/UX error + bug (build→audit→fix sub-loop, isolated worktrees) | ⏳ Pending |
| P5 | Retest every user behavior post-fix → update CSV | ⏳ Pending |
| P6 | Commit → push → PR → watch CI → fix failures → merge when green (loop) | ⏳ Pending |

## Parallel Execution Tracks

Work is parallelized across **workflows** (deterministic fan-out, ephemeral subagents) and
**named agent teams** (persistent, addressable background agents).

| Track | Kind | What | Output |
|-------|------|------|--------|
| A | Workflow `wf_dd03730a-3af` | Feature inventory → user stories → CSV (14 domain readers + coverage critic + gap fill) | `docs/user-stories.csv` |
| B | Agent team: `hunter-playback`, `hunter-data`, `hunter-ui`, `hunter-systems` | Deep static bug hunt by subsystem | `scratchpad/findings/hunter-*.json` |
| C | Agent: `runtime-tester` | Live app launch + log capture + XCUITest suite baseline | `scratchpad/findings/runtime-tester.json` |

## Baseline (2026-06-23, clean `main` state)

| Check | Result |
|-------|--------|
| `swift build` | ✅ Build complete (~12.7s) |
| `swift test --skip KasetUITests` | ✅ 893 tests + 7 perf tests, 0 failures |
| `swiftlint --strict` | ✅ 0 violations in 247 files |
| `swiftformat --lint` | ✅ 0/248 files need formatting |

Toolchain: Swift 6.3.2, Xcode 26.5, SwiftLint 0.64.0, SwiftFormat 0.61.1.

## Setup Changes

- Created branch `qa/user-story-audit-fixes`.
- Relaxed the "always confirm before running UI tests" rule in `AGENTS.md` (maintainer
  authorized autonomous UI/live-app runs for this QA effort; run serially, surface disruption).
- Added the progress-logging requirement to `AGENTS.md` (this file is the canonical log).

## Run Log

- **2026-06-23 00:46** — P0: branch created, baseline confirmed fully green.
- **2026-06-23 00:48** — P1 inventory workflow launched (Track A).
- **2026-06-23 ~00:50** — Track B (4 bug-hunters) + Track C (runtime-tester) launched in parallel.
- **2026-06-23 ~00:58** — Live-app smoke (runtime-tester): app builds, launches, renders Home window, **no crash**.
- **2026-06-23 ~01:00** — Local XCUITest run **blocked by macOS Gatekeeper** (unsigned runner "damaged" on Apple Silicon via `CODE_SIGNING_ALLOWED=NO`). Per maintainer's fallback instruction, local UI execution is **deferred to CI** (the `tests.yml` UI-test job runs the full suite authoritatively on every PR). Stuck run killed; `runtime-tester` redirected to enumerate UI coverage instead.
- **2026-06-23 ~01:02** — P1 inventory workflow finished: **373 user stories** written to `docs/user-stories.csv`.
- **2026-06-23 ~01:02** — Bug-hunters landing: playback 6, data 10, ui 10 findings so far; systems + runtime pending.
- _(updates appended as phases complete)_

## UI-Test Strategy (decision)

Full XCUITest execution is **delegated to CI** (`.github/workflows/tests.yml` → "macOS UI Tests" on macos-26), which is the authoritative merge gate. Local XCUITest runs are blocked by Gatekeeper on Apple Silicon for the unsigned test runner, and are disruptive (grab the GUI). Local runtime verification = build + live-app launch + log/crash capture + unit/VM tests + static audits. A signed local `build-for-testing` + `test-without-building` flow could enable local UI runs later if desired.
