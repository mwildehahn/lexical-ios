# Reconciler Optimisation Plan

## Reconciler Insights
- Reconcile walk recalculates offsets for every node in document order; even clean subtrees must update cursors (`Lexical/Core/Reconciler.swift:300-387`).
- Range cache entries store per-node spans but are rebuilt wholesale because the cache copy is mutated during the sweep (`Lexical/TextKit/RangeCache.swift:16-200`).
- Dirty marking bubbles to ancestors/siblings, so structural edits often flag large regions (`Lexical/Core/Utils.swift:78-139`).
- Paragraph insertion (new line) can restructure lists and decorators, so reconciler must account for list termination and placeholder creation (`Lexical/Core/Selection/RangeSelection.swift:868-960`).
- Block and decorator nodes already use preambles/postambles for layout hints, leaving room for invisible metadata markers (`Lexical/Core/Nodes/ElementNode.swift:312-347`, `Lexical/Core/Nodes/DecoratorNode.swift:102-129`).

## Architecture Decisions Pending
- Introduce optional node anchors: emit zero-width, uniquely formatted preamble/postamble markers carrying condensed `NodeKey` identifiers; guard via feature flags to allow opt-in and quick rollback.
- Build a `TextStorageDeltaApplier` that locates anchors and applies targeted `NSTextStorage` mutations, updating range cache deltas instead of replaying full reconciliations.
- Add a hierarchical offset index (Fenwick/segment tree or equivalent) to adjust downstream `RangeCacheItem.location` values in logarithmic time after mutations.
- Define structural-transform fallbacks: for edits that reorder siblings (list promotion/demotion, decorator insert/remove), detect and trigger legacy full reconcile to stay correct.
- Plan instrumentation and guardrails: timing hooks, anchor sanity checks, and automatic fallback when anchor-derived spans diverge from legacy output.

## Instrumentation & Testing Strategy
- Add an editor-initialised metrics sink (protocol-based container) that records reconciler timings, node counts, cache operations, and fallback reasons.
- Ensure metrics collection can be enabled in tests without affecting production performance; expose hooks to reset/inspect counters.
- Create regression harnesses with large synthetic documents to compare baseline and optimised reconcilers, asserting on metrics deltas rather than raw timing.

## Open Questions
- Best encoding for anchors (private-use Unicode vs attributes) without harming copy/paste, accessibility, or selection semantics.
- Whether attribute-based markers can fully replace sentinel characters, or if we need redundant representations for resilience.
- Frequency and cost of structural transforms today, to determine thresholds for targeted vs fallback reconciliation.
- Which metrics best capture real-world reconciler wins (elapsed time, nodes touched, bytes mutated) without introducing flaky tests.

## Next Steps TODO
- Benchmark current reconciler on long documents to capture baseline costs.
- Prototype feature-flagged anchor emission and validate through copy/paste and accessibility flows.
- Design and document the delta-application algorithm, including range cache update rules and fallback triggers.
- Implement instrumentation hooks to compare legacy vs targeted reconciliation for correctness/performance.
- Draft rollout plan covering staged enablement, toggles, and regression tests for list/newline edge cases.
- Implement metrics container initialisation path and add unit tests that assert metrics for large synthetic states.
