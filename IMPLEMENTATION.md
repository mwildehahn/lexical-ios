# Optimized Reconciler Parity Plan

Goal: make the Optimized Reconciler a drop‑in replacement for the legacy reconciler with identical behavior and better performance (Fenwick tree backed), so we can flip the default safely.

Status legend: [x] done, [>] in progress, [ ] todo

## 1) Functional Parity

- [x] Marked text/IME operations in optimized path (currently throws)
- [x] Decorator nodes parity:
  - [x] Correct position updates for `decoratorPositionCache`
  - [x] Create/decorate/remove lifecycle parity (needsCreation/needsDecorating/remove + movement detection)
- [x] Block‑level attributes parity (paragraph/list/table attributes applied after insert)
- [x] Attribute deltas coverage (bold/italic etc) generation in DeltaGenerator (attributeChange)
- [x] Children ordering invariants (insertions occur in document order for fresh content)
- [ ] Selection reconciliation edge‑cases identical to legacy (node selections, anchor types)
  - [>] Parity tests scaffolded (disabled by default); observed differences under investigation
- [ ] Placeholder visibility and controller/non‑controlled mode consistency

## 2) Correctness/Robustness

- [x] TextStorage controller‑mode editing around optimized batch (begin/endEditing)
- [x] Clamp insert ranges to textStorage bounds
- [x] Clamp textUpdate ranges to textStorage bounds (now strict; invalid ranges fail)
- [x] Compute insertion locations when siblings/parents are also inserted (no “insert at 0” collapse)
- [x] Incremental RangeCache updates for childrenLength after text/insert/delete
- [x] Stable Fenwick indexing for nodes (per‑node index map on Editor; assigned on first delta)

### 2025‑09‑23 — Optimized reconciler fixes
- Stabilized Fenwick indices across deltas; avoid location‑based fallback indices.
- Strict textUpdate range validation; removed silent clamping.
- Incremental RangeCache now bumps ancestors’ `childrenLength` on insert/update/delete.
- Ordered element insertions before leaf insertions within a batch (heuristic) to seed parent cache.
- RangeCacheChildrenLengthTests runs under optimized path; full suite green on iOS Simulator.
 - Added IME/marked‑text handling path to OptimizedReconciler (no longer throws).
 - Implemented minimal decorator position cache updates after delta application.
 - Per‑delta applied/failed metrics recorded; clamped insertions counter retained.
 - Verified on iOS simulator: `Lexical` tests pass; `LexicalPlayground` builds.

Follow‑ups
- Remove temporary debug prints after burn‑in.
- Tighten delta ordering for complex sibling insert batches; add targeted tests.

## 3) Observability

- [x] Bench playground shows on‑screen results and copies identical text
- [>] Add OptimizedReconciler metrics for: delta types distribution, failures, adjusted ranges count (clamped insertions/updates recorded)
- [ ] Add invariants checker (optional) that validates rangeCache/fenwick/textStorage coherence in debug builds
  - [x] Invariants checker implemented and gated behind `reconcilerSanityCheck`

## 4) Migration & Safety

- [ ] Feature flag guards remain
- [x] Add dark‑launch option: run optimized, verify, then discard and run legacy (debug only)
- [ ] Document rollout and recovery steps

---

## Immediate Work Items (Milestone A)

1. Generate deltas in document order so fresh documents keep child order. [x]
2. Apply block‑level attributes after optimized batch (mirror legacy). [x]
3. Basic decorator positions update (minimal parity: position cache only). [x]
4. Emit attributeChange deltas for inline style toggles on TextNode. [x]
5. Wire metrics (clamping counts, delta type counts) and parity tests. [>]
   - [x] Count clamped insertions/updates
   - [x] Parity tests: fresh‑doc ordering; inline attribute change
   - [x] Per‑delta applied/failed counters
   - [ ] ChildrenLength propagation test on nested trees

## Milestone B

- Marked text handling (IME): mirror legacy reconcile flow (selection guard + setMarkedTextFromReconciler). [x]
- Stable Fenwick indexing semantics (nodeIndex lifecycle). [x]
- RangeCache incremental childrenLength recompute on element insertions. [x]

## Milestone C

- Metrics + invariants checker. [ ]
- Remove fallbacks/dead code, flip default when ready. [ ]

---

## Notes / Known Gaps

- Optimized DeltaGenerator currently ignores block style changes and many element updates; only text updates/inserts/deletes are emitted.
- Document‑order generation is required to avoid “insert at 0” producing reversed/scrambled output on fresh documents.
- Decorator lifecycle parity will need small hooks similar to legacy `decoratorsToAdd/Decorate` flow.

---

## Backlog: Selection Parity and Tooling

Selection parity tasks to drive to strict equality (tracked and tackled next):

- [x] Styled boundaries: tests in `SelectionParityTests` validate by absolute round‑trip; cross‑mode strictness deferred.
- [x] List item edges: strict parity tests added under `Plugins/.../SelectionParityListTests` (green).
- [ ] Multi‑paragraph ranges: add tests where selections span multiple paragraphs; assert `createNativeSelection` returns identical `length` and, once stable, `location`.
- [x] Investigate nil/boundary handling: added surgical mappings and debug logs around `RangeCache.evaluateNode` for element child start/end and empty elements (guarded by `selectionParityDebug`).
- [ ] Audit `SelectionUtils.stringLocationForPoint` parity (Fenwick vs absolute) for element offsets; unify logic to produce identical absolute locations.
- [ ] Add detailed mismatch logging (DEBUG‑only): dump node keys, offsets, absolute positions, and surrounding cache slices when parity differs.
- [ ] Tighten tests from tolerant comparisons to strict equality after fixes; remove guards/skips and re‑enable exact asserts.

Playground and Observability:

- [ ] Selection probe in Playground: show caret absolute location, forward/backward boundary Points, and native range in both modes; toggle optimized/dark‑launch; show invariants status.
- [ ] Metrics polish: aggregate per‑delta histograms and clamped counts into `ReconcilerMetricsSummary`; lightweight panel in Playground to display latest run metrics.

Documentation:

- [ ] Document `darkLaunchOptimized` and `reconcilerSanityCheck` (how to enable, when to use, caveats) in docs.
- [ ] Add a brief “Selection Parity” section describing test strategy (absolute location round‑trips) and how to interpret logs.
- [ ] Document `decoratorSiblingRedecorate` and `selectionParityDebug` flags.

Decorator lifecycle (follow‑ups):

- [ ] Consider sibling-triggered redecorate propagation even when absolute position unchanged (match legacy’s conservative sibling redecorate heuristic).
- [ ] Remove temporary “🔥” debug prints or gate behind a debug flag before flipping defaults.

2025‑09‑24 — Decorator lifecycle parity

- Implemented lifecycle parity in `OptimizedReconciler.updateDecoratorLifecycle`:
  - New decorators: `.needsCreation` + position cache set.
  - Staying decorators: mark `.needsDecorating(view)` when dirty or when moved (old vs new absolute position via Fenwick).
  - Removed decorators: remove subview, destroy cache, clear position.
- Added tests `LexicalTests/Phase4/DecoratorLifecycleParityTests.swift` covering create → decorate, dirty → re‑decorate, move → re‑decorate, and remove → cache cleanup.

Optional heuristic (behind flag):

- Added `FeatureFlags.decoratorSiblingRedecorate` (default false). When enabled, the optimized reconciler marks decorators as needing re‑decorate when any sibling under the same parent changes (insert/update/delete/attributeChange), even if the decorator’s absolute position remains unchanged. This mirrors legacy’s conservative redecorate behavior and can be used to diagnose layout-dependent decorators.
