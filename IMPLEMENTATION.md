# Optimized Reconciler — Parity Plan (Clean)

Goal: ship the Optimized Reconciler as a drop‑in replacement for the legacy reconciler (identical behavior, much faster), then flip the default safely.

Legend: [x] done · [>] in progress · [ ] todo

**TL;DR (2025‑09‑24)**
- Core parity achieved for: document ordering, block‑level attributes, decorator lifecycle, IME/marked‑text. Performance target met (see Playground Performance tab).
- Remaining parity work centers on Selection mapping (absolute location ↔ Point) at boundaries and multi‑paragraph ranges.
- Metrics and invariants exist; polish + docs pending. Temporary debug prints remain and should be gated/removed before default flip.

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
- [>] Selection reconciliation edge cases (absolute location mapping at element/text/paragraph boundaries, multi‑paragraph ranges).
- [ ] Placeholder visibility and controlled vs non‑controlled behavior audit.

**Correctness/Robustness**
- [x] Controller‑mode editing around batch (`begin/endEditing`).
- [x] Strict range validation (invalid ranges abort and report).
- [x] Insertion location when siblings/parents are new (no “insert at 0” collapse).
- [x] Incremental `RangeCache` updates (childrenLength/textLength); stable Fenwick indexing per node.

**Observability**
- [x] Invariants checker (gated by `reconcilerSanityCheck`).
- [>] Metrics polish (aggregate histograms, clamped counts summary).

**Migration & Safety**
- [x] Feature flags guard optimized path; dark‑launch mode runs optimized then restores and runs legacy for comparison.
- [ ] Document rollout steps and recovery toggles.

---

## Open Gaps (Prioritized)
1) Selection parity to strict equality
- Align `RangeCache.evaluateNode` boundary mapping for empty elements and element start/end (debug hooks exist).
- Unify `SelectionUtils.stringLocationForPoint` Fenwick vs absolute paths so absolute locations match legacy.
- Ensure multi‑paragraph range lengths and absolute locations match (newline placement and paragraph boundaries).

2) Metrics and debug hygiene
- Gate or remove all temporary "🔥" logs.
- Produce `ReconcilerMetricsSummary` (delta type counts, failures, clamped insert/update counts) and surface in Playground.

3) Documentation & flags
- Document `darkLaunchOptimized`, `reconcilerSanityCheck`, `decoratorSiblingRedecorate`, `selectionParityDebug` with example toggles.

---

## Immediate Work (Next)
1. Selection parity fixes (boundaries, multi‑paragraph) and enable strict cross‑mode asserts in `SelectionParityTests`.
2. Gate/remove debug prints; keep opt‑in debug via flags only.
3. Metrics summary + brief docs; integrate a lightweight panel in Playground.

---

## Test Suites (authoritative on iOS Simulator)
- Parity: `LexicalTests/Tests/OptimizedReconcilerParityTests.swift` (ordering, inline attributes) — green.
- Decorators: `LexicalTests/Phase4/DecoratorLifecycleParityTests.swift` — green.
- Selection: `LexicalTests/Phase4/SelectionParityTests.swift` — scaffolded; strict cross‑mode checks intentionally deferred until fixes land.
- Heavy suites (`*.swift.disabled`): perf/stress/edge cases — off until parity is strict.

Run (examples):
- Unit tests: `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
- Filter: `... -only-testing:LexicalTests/SelectionParityTests test`

---

## Feature Flags (quick reference)
- `optimizedReconciler`: switch to optimized path.
- `darkLaunchOptimized`: run optimized, restore snapshot, run legacy (comparison without user impact).
- `reconcilerSanityCheck`: invariants validator.
- `reconcilerMetrics`: per‑delta and per‑run metrics collection.
- `decoratorSiblingRedecorate`: conservative redecorate on sibling changes (diagnostic).
- `selectionParityDebug`: verbose logs for selection boundary evaluation.

---

## Changelog
2025‑09‑24 — Decorator lifecycle parity
- Implemented lifecycle parity in `OptimizedReconciler.updateDecoratorLifecycle` (create/dirty/move/remove) and position cache updates.
- Added `DecoratorLifecycleParityTests` covering create → decorate, dirty → re‑decorate, move → re‑decorate, delete cleanup.

2025‑09‑23 — Optimized reconciler fixes
- Stable Fenwick indices across deltas; strict textUpdate validation; incremental RangeCache ancestor bumps; heuristic ordering for element inserts; metrics counters wired; Playground build verified.

---

## Acceptance to Flip Default
- All parity tests green with strict cross‑mode equality for selection mapping.
- Invariants clean under `reconcilerSanityCheck` for test corpus and Playground flows.
- Metrics show no persistent delta failures; temporary debug prints removed/gated.
- Playground (iPhone 17 Pro, iOS 26.0) builds and behaves identically in manual checks.
