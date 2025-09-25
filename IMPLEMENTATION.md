# Optimized Reconciler — Parity Plan (Clean)

Goal: ship the Optimized Reconciler as a drop‑in replacement for the legacy reconciler (identical behavior, much faster), then flip the default safely.

Legend: [x] done · [>] in progress · [ ] todo

**TL;DR (2025‑09‑25)**
- Core parity achieved: document ordering, block‑level attributes, decorator lifecycle, IME/marked‑text, selection mapping (boundaries + multi‑paragraph). Performance target met.
- Observability: metrics snapshot with histograms + clamped counts; invariants checker.
- Remaining before default flip: gate/remove temporary debug prints; add short docs for flags and (optional) Playground metrics panel.

Updates in this patch (2025‑09‑25)
- Simplified FeatureFlags API and updated tests:
  - Removed deprecated flags: `decoratorSiblingRedecorate`, `leadingNewlineBaselineShift`.
  - Tests now use the back‑compat FeatureFlags initializer (reconcilerSanityCheck, proxyTextViewInputDelegate, optimizedReconciler, reconcilerMetrics, darkLaunchOptimized, selectionParityDebug) or the new `reconcilerMode`/`diagnostics` under the hood.
  - Adjusted docs: feature flags quick reference no longer lists removed flags.
- Verification (iOS 26.0, iPhone 17 Pro):
  - Focused suites: SelectionParityTests (key case), InlineDecoratorBoundaryParityTests, IncrementalUpdaterTextLengthTests — green.
  - Build‑for‑testing succeeds for the Lexical scheme.

**What “Legacy” Does vs “Optimized”**
- Legacy (`Lexical/Core/Reconciler.swift:1`): tree walk computes rangesToDelete/rangesToAdd, maintains `decoratorsToAdd/Decorate/Remove`, applies to `TextStorage`, then block‑level attributes, selection, marked‑text; updates `rangeCache` in one pass.
- Optimized (`Lexical/Core/OptimizedReconciler.swift:1`): diff → deltas → apply with Fenwick‑backed offsets, incrementally updates `rangeCache`, then block‑level attributes, decorator lifecycle, optional marked‑text; metrics + invariants hooks.

---

## Status by Area

**Functional Parity**
- [x] Fresh‑doc child ordering preserved (document‑order delta gen).
- [x] Block‑level attributes after batch (mirrors legacy pass).
- [x] Decorator lifecycle (create/decorate/remove + movement detection) and positions cache.
- [x] IME/marked‑text flow (create selection guard + `setMarkedTextFromReconciler`).
- [x] Inline style changes emit `attributeChange` deltas without mutating string.
- [x] Selection reconciliation edge cases (absolute location mapping at element/text/paragraph boundaries, multi‑paragraph ranges).
- [x] Placeholder visibility and controlled vs non‑controlled behavior audit.

**Correctness/Robustness**
- [x] Controller‑mode editing around batch (`begin/endEditing`).
- [x] Strict range validation (invalid ranges abort and report).
- [x] Insertion location when siblings/parents are new (no “insert at 0” collapse).
- [x] Incremental `RangeCache` updates (childrenLength/textLength); stable Fenwick indexing per node.

**Observability**
- [x] Invariants checker (gated by `reconcilerSanityCheck`).
- [x] Metrics polish (aggregate histograms, clamped counts summary).
- [x] Debug print hygiene: gate all temporary "🔥" logs behind feature flags
  - Parity diagnostics → `selectionParityDebug`
  - General verbose traces (reconciler, delta applier, range cache updater) → `diagnostics.verboseLogs`
  - Metrics snapshot dump → `reconcilerMetrics` or manual `editor.dumpMetricsSnapshot()`

**Migration & Safety**
- [x] Feature flags guard optimized path; dark‑launch mode runs optimized then restores and runs legacy for comparison.
- [ ] Document rollout steps and recovery toggles.

---

## Open Gaps (Prioritized)
- [x] Selection parity to strict equality
  - [x] Align `RangeCache.evaluateNode` boundary mapping for empty elements and element start/end.
  - [x] Unify `SelectionUtils.stringLocationForPoint` Fenwick vs absolute paths so absolute locations match legacy.
  - [x] Ensure multi‑paragraph range lengths and absolute locations match.

- [x] Debug print hygiene
  - [x] Gated/removed direct `print` calls in:
    - `OptimizedReconciler`: before/after apply, success/partial, queued textUpdate (now behind `verboseLogs`)
    - `TextStorageDeltaApplier`: delta handling, insert clamping, post-insert length (behind `verboseLogs`)
    - `IncrementalRangeCacheUpdater`: insertion/remaining passes, cache insert, parent updates (behind `verboseLogs`)
    - Parity-only traces in `RangeCache`, `AbsoluteLocation`, `SelectionUtils` remain behind `selectionParityDebug`.

- [x] Metrics polish
  - [x] Aggregate histograms (durations, Fenwick ops) and clamped counts summary; expose snapshot API and gated console dump.

- [ ] Documentation & flags
  - [ ] Document `darkLaunchOptimized`, `reconcilerSanityCheck`, `selectionParityDebug`, `reconcilerMetrics` with example toggles. (Deprecated flags removed.)

---

## Immediate Work (Next)
- [x] Selection parity strictness (boundaries, multi‑paragraph) with incremental, test‑first patches.
- [x] Gate/remove debug prints; keep opt‑in debug via flags only.
- [ ] Metrics polish visibility in Playground
  - [x] Provide snapshot API and console dump (gated by `reconcilerMetrics`).
  - [ ] Add lightweight metrics panel in Playground to render snapshot.

---

## Test Suites (authoritative on iOS Simulator)
- Parity: `LexicalTests/Tests/OptimizedReconcilerParityTests.swift` (ordering, inline attributes) — green.
- Decorators: `LexicalTests/Phase4/DecoratorLifecycleParityTests.swift` — green.
- Selection: `LexicalTests/Phase4/SelectionParityTests.swift` + `InlineDecoratorBoundaryParityTests.swift` — green.
- TextView/Placeholder: `LexicalTests/Tests/TextViewTests.swift` (incl. IME cancel placeholder) — green.
- Heavy suites (`*.swift.disabled`): perf/stress/edge cases — kept off for now.

Run (examples):
- Unit tests: `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
- Filter: `... -only-testing:LexicalTests/SelectionParityTests test`

---

## Feature Flags (quick reference)
- `optimizedReconciler`: switch to optimized path.
- `darkLaunchOptimized`: run optimized, restore snapshot, run legacy (comparison without user impact).
- `reconcilerSanityCheck`: invariants validator.
- `reconcilerMetrics`: per‑delta and per‑run metrics collection.
- `selectionParityDebug`: verbose logs for selection boundary evaluation.

Migration note
- Internally, flags are represented via `ReconcilerMode { legacy, optimized, darkLaunch }` and `Diagnostics { selectionParity, sanityChecks, metrics, verboseLogs }`.
- The convenience initializer preserves the previous call sites; removed flags are no‑ops and should not be passed any more.

Commit summary (planned)
- Tests: drop deprecated FeatureFlags args; documentation updates.
- No behavior change under existing feature configurations; parity tests remain green.
