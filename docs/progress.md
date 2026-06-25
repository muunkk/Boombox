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
| PR / CI / merge | ✅ **PR #23 merged to main** (`453ba75`); all 5 CI checks green |

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

---

# Pass 3 — New-axis `/goal` loop (branch `qa/pass-3-audit-fixes`)

After passes 1-2 hit diminishing returns on the original lenses, pass 3 targeted **axes never previously hunted**: security/privacy, performance/main-thread, persistence & migration, network resilience, parser fuzzing, and window/appearance/empty states.

| Phase | Result |
|-------|--------|
| Hunt (6 new-axis lenses, ×2 runs unioned) | 51 findings (SEC lens initially failed on a session limit → resumed) |
| Adversarial verify | **48 confirmed** (2 refuted, 1 dup) — 2 high, 10 medium, 36 low |
| Fix (7 batches + central reconciliation) | **46 fixed**, 2 deferred (low-severity hygiene) |
| Retest | **1052 unit tests, 0 failures** (×2 runs); lint/format clean |
| PR / CI / merge | ✅ **PR #24 merged to main** (`259eda1`); all 5 CI checks green |

**Pass-3 highlights** (detail in [`audit-findings-pass3.md`](./audit-findings-pass3.md)):
- **FUZZ** — a class of **integer-overflow crashes** in duration/timestamp parsing (ParsingHelpers, Song, LRCParser, Podcast) on adversarial API data → overflow-safe arithmetic + depth-capped recursive parsers.
- **PERSIST** — sign-out/account-switch left persisted favorites/queue/recent-searches behind (**privacy leak**) → cleared; schema-versioned playback-session restore.
- **SEC** — WebView had no navigation-policy allowlist, JS-bridge accepted any frame/origin, thumbnail URLs weren't scheme-checked → hardened (verified as defense-in-depth, downgraded to low).
- **PERF** — synchronous CoreAudio HAL polling on the main thread, double queue-encode, Observation re-notify storms → off-main / single-encode / equality-gated.

**Engineering notes (pass 3):** several test-infra issues were diagnosed and fixed without weakening coverage — a swiftformat↔swiftlint modifier-order conflict (resolved by matching the codebase's stable `nonisolated static func` form), `@MainActor`/`@Sendable` test-capture errors, deep-recursion test inputs overflowing the harness on teardown (capped), and **cross-suite `UserDefaults` contamination** of persistence tests (fixed via a per-instance queue-persistence key prefix). The PERF-002 async-save fix was reverted to synchronous (keeping the single-encode win) because fire-and-forget persistence risked losing the queue on quit.

---

# ✅ All passes complete (Passes 1–3 merged)

| Pass | PR | Merge | Confirmed | Fixed |
|------|----|-------|-----------|-------|
| 1 | [#22](https://github.com/muunkk/Boombox/pull/22) | `8a4b43a` | 35 | 35 |
| 2 | [#23](https://github.com/muunkk/Boombox/pull/23) | `453ba75` | 51 | 51 |
| 3 | [#24](https://github.com/muunkk/Boombox/pull/24) | `259eda1` | 48 | 46 (2 deferred) |
| **Total** | | | **134** | **132** |

- **Canonical spreadsheet:** [`user-stories.csv`](./user-stories.csv) — 383 stories with current test/fix status.
- **Findings:** [`audit-findings.md`](./audit-findings.md) (P1), [`audit-findings-pass2.md`](./audit-findings-pass2.md), [`audit-findings-pass3.md`](./audit-findings-pass3.md).
- **Outstanding work:** [`deferred-followups.md`](./deferred-followups.md) — the 2 deferred items + minor cross-batch partials, each tagged _anytime_ vs _needs feedback_ for handling once live-app/runtime feedback is available.
- **Unit tests:** 893 → **1052** (+159). Every pass merged through full CI (incl. macOS UI tests) green.

**Next high-value work is runtime, not static:** the static-analysis well is largely dry; further findings now need live-app/Instruments profiling and the `needs feedback` items above.

---

# 2026-06-24 — Sparkle auto-updates + one-command release pipeline

**Goal:** ship an installable, self-updating Boombox.app plus a single `Scripts/release.sh <version>` command, so a stable build can run as a daily driver while development continues. (Spec: [`superpowers/specs/2026-06-23-sparkle-auto-updates-design.md`](./superpowers/specs/2026-06-23-sparkle-auto-updates-design.md); plan: [`superpowers/plans/2026-06-24-sparkle-auto-updates.md`](./superpowers/plans/2026-06-24-sparkle-auto-updates.md); decision: [`adr/0014-sparkle-auto-updates-drop-sandbox.md`](./adr/0014-sparkle-auto-updates-drop-sandbox.md).)

**Built (branch `feat/sparkle-auto-updates`):**
- **App side** — Sparkle 2.9.3 via SPM; `UpdaterController` (holds `SPUStandardUpdaterController`), `CheckForUpdatesViewModel` (testable publisher seam), `CheckForUpdatesView`; wired into `KasetApp` as `CommandGroup(after: .appInfo)` → **Boombox → Check for Updates…**, with daily background checks.
- **Sandbox dropped** — `Kaset.entitlements` no longer sandboxed (self-distribution, not App Store); `cs.jit` + `network.client` retained.
- **Packaging** — `build-app.sh` embeds `Sparkle.framework`, adds the `@loader_path/../Frameworks` rpath, inside-out-signs the framework's nested helpers (XPC services, `Autoupdate`, `Updater.app`), and injects `SUFeedURL`/`SUPublicEDKey`/`SUEnableAutomaticChecks`/`SUScheduledCheckInterval`.
- **Release pipeline** — `release.sh`: bump → universal Developer ID build → DMG → notarize + staple → `generate_appcast` (auto-signs) → prints the manual `gh release` + `git push` publish steps.

**Verification done:** `swift build` green; **1053** unit tests pass (incl. `CheckForUpdatesViewModelTests`); ad-hoc bundle **launches** with `vmmap` confirming `Sparkle.framework` mapped into the process (rpath fix proven); `codesign --verify --deep --strict` passes; `release.sh` passes `bash -n` and `generate_appcast --download-url-prefix` confirmed as a real flag.

**Remaining for the maintainer (credentialed/outward-facing):** run Sparkle `generate_keys` + paste `SU_PUBLIC_ED_KEY` into `version.env`; `xcrun notarytool store-credentials boombox-notary …`; a real Developer ID `release.sh` run (notarize + appcast); the end-to-end staging test (local feed); `gh release create` + push. See [`release-runbook.md`](./release-runbook.md).

**Follow-ups (deferred):** Keychain-encrypt stored WebView auth cookies; optional one-time migration of favorites/settings from the old sandbox container to `~/Library/Application Support` (dropping the sandbox resets local data once).
