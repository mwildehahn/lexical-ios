# Optimized Reconciler Parity Plan

Goal: make the Optimized Reconciler a drop‑in replacement for the legacy reconciler with identical behavior and better performance (Fenwick tree backed), so we can flip the default safely.

Status legend: [x] done, [>] in progress, [ ] todo

## 1) Functional Parity

- [x] Marked text/IME operations in optimized path (currently throws)
- [ ] Decorator nodes parity:
  - [x] Correct position updates for `decoratorPositionCache`
  - [ ] Create/decorate lifecycle to match legacy (needs cache + view hooks)
- [x] Block‑level attributes parity (paragraph/list/table attributes applied after insert)
- [x] Attribute deltas coverage (bold/italic etc) generation in DeltaGenerator (attributeChange)
- [x] Children ordering invariants (insertions occur in document order for fresh content)
- [ ] Selection reconciliation edge‑cases identical to legacy (node selections, anchor types)
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

## 4) Migration & Safety

- [ ] Feature flag guards remain
- [ ] Add dark‑launch option: run optimized, verify, then discard and run legacy (debug only)
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
