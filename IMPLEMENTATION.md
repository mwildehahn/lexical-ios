# Optimized Reconciler Parity Plan

Goal: make the Optimized Reconciler a drop‑in replacement for the legacy reconciler with identical behavior and better performance (Fenwick tree backed), so we can flip the default safely.

Status legend: [x] done, [>] in progress, [ ] todo

## 1) Functional Parity

- [ ] Marked text/IME operations in optimized path (currently throws)
- [ ] Decorator nodes parity:
  - [ ] Correct position updates for `decoratorPositionCache`
  - [ ] Create/decorate lifecycle to match legacy (needs cache + view hooks)
- [>] Block‑level attributes parity (paragraph/list/table attributes applied after insert)
- [ ] Attribute deltas coverage (bold/italic etc) generation in DeltaGenerator
- [x] Children ordering invariants (insertions occur in document order for fresh content)
- [ ] Selection reconciliation edge‑cases identical to legacy (node selections, anchor types)
- [ ] Placeholder visibility and controller/non‑controlled mode consistency

## 2) Correctness/Robustness

- [x] TextStorage controller‑mode editing around optimized batch (begin/endEditing)
- [x] Clamp insert ranges to textStorage bounds
- [x] Clamp textUpdate ranges to textStorage bounds
- [x] Compute insertion locations when siblings/parents are also inserted (no “insert at 0” collapse)
- [x] Incremental RangeCache updates for childrenLength after text/insert/delete
- [x] Stable Fenwick indexing for nodes (per‑node index map on Editor)
- [ ] Remove debug prints and replace with structured metrics/logging

## 3) Observability

- [x] Bench playground shows on‑screen results and copies identical text
- [>] Add OptimizedReconciler metrics for: delta types distribution, failures, adjusted ranges count (clamped insertions/updates recorded)
- [ ] Add invariants checker (optional) that validates rangeCache/fenwick/textStorage coherence in debug builds

## 4) Migration & Safety

- [ ] Feature flag guards remain until parity boxes are checked
- [ ] Add dark‑launch option: run optimized, verify, then discard and run legacy (debug only)
- [ ] Document rollout and recovery steps

---

## Immediate Work Items (Milestone A)

1. Generate deltas in document order so fresh documents keep child order. [x]
2. Apply block‑level attributes after optimized batch (mirror legacy). [>]
3. Basic decorator positions update (minimal parity: position cache only). [ ]
4. Emit attributeChange deltas for inline style toggles on TextNode. [x]
5. Wire metrics (clamping counts, delta type counts) and parity tests. [>]

## Milestone B

- Marked text handling (IME): mirror legacy reconcile flow (selection guard + setMarkedTextFromReconciler). [ ]
- Stable Fenwick indexing semantics (nodeIndex lifecycle). [ ]
- RangeCache incremental childrenLength recompute on element insertions. [ ]

## Milestone C

- Metrics + invariants checker. [ ]
- Remove fallbacks/dead code, flip default when ready. [ ]

---

## Notes / Known Gaps

- Optimized DeltaGenerator currently ignores block style changes and many element updates; only text updates/inserts/deletes are emitted.
- Document‑order generation is required to avoid “insert at 0” producing reversed/scrambled output on fresh documents.
- Decorator lifecycle parity will need small hooks similar to legacy `decoratorsToAdd/Decorate` flow.
