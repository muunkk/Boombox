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
| P2 | Test every user story + hunt bugs → document all errors in the CSV | ✅ Done — **36 found → 35 confirmed** (44 stories flagged) |
| P3 | Synthesize prioritized fix plan from findings | ✅ Done — 4 disjoint batches, per-finding verified fixes |
| P4 | Fix every logistical/UX error + bug (build→audit→fix sub-loop, isolated worktrees) | ✅ Done — all 35 fixed, 4 batches merged |
| P5 | Retest every user behavior post-fix → update CSV | ✅ Done — **926 unit tests green**; CSV Fix Status updated |
| P6 | Commit → push → PR → watch CI → fix failures → merge when green (loop) | ✅ Done — **PR #22 merged to main** (`8a4b43a`); all 5 CI checks green |

## ✅ Run Complete

All phases done. **PR [#22](https://github.com/muunkk/Boombox/pull/22) merged to `main`** (`8a4b43a`, 2026-06-23). CI fully green on first run — SwiftFormat, SwiftLint, build, **macOS UI Tests (11m51s)**, macOS Unit Tests. Net: 373-story catalog + 35 verified bug fixes + 33 new unit tests. The two usage-limit agent deaths (ui, data) were recovered by main-thread salvage without losing work.

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
- **2026-06-23 ~01:03** — All 4 hunters done: **36 findings** (playback 6, data 10, ui 10, systems 10).
- **2026-06-23 ~01:05** — Adversarial verify workflow: **35 confirmed, 1 refuted** (F006). Corrected severities: 1 high, 13 medium, 21 low. F027 downgraded high→low (xcstrings is shipped dead-weight; runtime reads .lproj).
- **2026-06-23 ~01:08** — P2 documented: `docs/audit-findings.md` written; `user-stories.csv` updated — 44 stories flagged with issues, 329 pass; per-story Test Method/Result/Severity/Fix Status filled.
- **2026-06-23 ~01:10** — P4 launched: 4 fixer agents in isolated worktrees (`fix/playback`, `fix/data`, `fix/ui`, `fix/systems`), disjoint file allowlists, each must leave its worktree green (swiftformat + swiftlint + build + test) and commit.
- **2026-06-23 ~11:07** — P4 fixers run in 4 worktrees. Playback finished & merged first (verified green, 898 tests).
- **2026-06-23 ~11:10** — **Usage limit interrupted** data/ui/systems fixers mid-work (uncommitted edits preserved in worktrees). Recovery: resume-nudged all three.
  - `fixer-data` revived → finished but died again before commit → **salvaged** (worktree was green; formatted/linted/committed `eb12d83`).
  - `fixer-ui` stayed dead → **salvaged**; hit a SIGTRAP test crash traced to a Swift 6 `@MainActor` isolation issue in `UIFixTests` (View-inferred isolation called from a background test thread) — fixed by making the suite `@MainActor`; committed `7848ab7`.
  - `fixer-systems` revived (slower) → finished & committed `e0b6ccb` (incl. HIGH romanizer crash + tests).
- **2026-06-23 ~11:25** — Batches merged into integrated branch (disjoint files → clean merges, no conflicts).
- **2026-06-23 ~11:29** — **Final 4-batch verification GREEN**: swiftformat 0/253, swiftlint 0 violations, build ✓, **926 unit tests, 0 failures** (33 new fix tests added).
- **2026-06-23 ~11:30** — P5: CSV Fix Status updated (44 flagged stories → Fixed & retested); `audit-findings.md` regenerated as RESOLVED.
- _(P6 push/PR/CI/merge next)_

## Fix Batches (P4)

| Batch | Commit | Findings | Result |
|-------|--------|----------|--------|
| `fix/playback` | `defcec4` | F001–F005 | merged, green |
| `fix/ui` | `7848ab7` | F017–F026 | merged, green (recovered) |
| `fix/systems` | `e0b6ccb` | F027–F036 | merged, green |
| `fix/data` | `eb12d83` | F007–F016, F023 | merged, green (recovered) |

## Confirmed Findings (P2 → P4)

35 confirmed bugs (full detail in [`audit-findings.md`](./audit-findings.md)). Highlights:
- **HIGH** F028 — Chinese/Bengali/Hindi romanizers index Swift String with UTF‑16 offsets → wrong output + **out-of-bounds crash** (`fix/systems`).
- **MEDIUM** (13) — shuffle replays current track (F001); WebView crash recovery double-navigates (F005); shared continuation token corrupts pagination (F007/F023); favorites decode all-or-nothing wipes data (F009); "Add to Library" force-plays (F022); tab switch loses navigation drill-down (F020); search filter chips trap on empty results (F017); PlayerBar shortcuts hijack text fields (F024); Carbon hotkey handler leak (F030); scrambled fr/id translations (F027, low/partial); etc.
- **LOW** (21) — unstable list identities, missing a11y ids, cache keying, monitor leaks, doc gaps, etc.

## UI-Test Strategy (decision)

Full XCUITest execution is **delegated to CI** (`.github/workflows/tests.yml` → "macOS UI Tests" on macos-26), which is the authoritative merge gate. Local XCUITest runs are blocked by Gatekeeper on Apple Silicon for the unsigned test runner, and are disruptive (grab the GUI). Local runtime verification = build + live-app launch + log/crash capture + unit/VM tests + static audits. A signed local `build-for-testing` + `test-without-building` flow could enable local UI runs later if desired.

---

# Pass 2 — Second `/goal` loop (branch `qa/pass-2-audit-fixes`)

Re-ran the full document → test → fix → retest loop on the post-pass-1 code, with a **bigger, differently-lensed** agent team and **rate-limit-resilient workflows** (after named background agents proved fragile to transient server limits).

| Phase | Result |
|-------|--------|
| Catalog refresh | ✅ +10 new stories, 20 behavior updates → **383 stories** |
| Deep hunt (8 lenses) | ✅ 54 findings (concurrency, crash, error-state, ux/a11y, playback, data, memory, regression) |
| Adversarial verify | ✅ **51 confirmed, 3 refuted** (3 high, 10 medium, 38 low) |
| Fix (6 batches + cross-batch completion) | ✅ all 51 fixed |
| Retest | ✅ **981 unit tests, 0 failures** (×2 runs), swiftlint/swiftformat clean |
| PR / CI / merge | 🔄 in progress |

**Pass-2 highlights** (full detail in [`audit-findings-pass2.md`](./audit-findings-pass2.md)):
- **HIGH** — 47–59 user-facing strings missing from the runtime `.lproj` (English leaked in all locales); zero-accessibility queue rows; playWithMix metadata stub + state leak; `play(videoId:)` leaked previous track's like/library state; artist album-pagination dropped.
- Plus concurrency (volume-scroll lost-update, unguarded web-queue corrections), error-surfacing toasts/alerts, liked-songs per-request pagination, and broad a11y/localization polish.

**Resilience notes (pass 2):** the catalog-refresh workflow crashed once on a transient server rate-limit (null-guarded + resumed); the 8 named hunters died silently on the same limit and were re-run as a workflow; a test SIGTRAP and a cross-suite shared-singleton race were both diagnosed and fixed. Fixes in commits `0cb06f1` + `ed470ef`.

### Fix Batches (Pass 2)

| Batch | Findings |
|-------|----------|
| player | P2 playback state/metadata/queue (11) |
| data | parsers/pagination/client (7) |
| systems | localization/imagecache/notifications/lyrics (7) |
| playerui | menubar/volume/queue-ui a11y (5) |
| viewmodels | artist/playlist/search/topsongs (4) |
| views | a11y + localization polish (17) |
| cross-batch | localization runtime keys, error toasts, liked pagination |
