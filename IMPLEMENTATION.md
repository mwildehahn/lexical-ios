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
  - Build‑for‑testing succeeds for the Lexical‑Package test scheme.

Addendum (2025‑09‑25, afternoon)
- Selection parity (strict) — fixes and confirmations
  - Element start parity: `RangeCacheItem.locationFromFenwick` now returns childrenStart (base + preamble) in parity mode; SelectionUtils’ fast path uses absolute base + preamble for optimized, and base for legacy when preamble>0. Empty paragraph and list boundaries now match legacy strictly.
  - End‑of‑children parity: `stringLocationForPoint(.element, offset = childrenCount)` uses raw absolute base to avoid double‑adding preamble in optimized mode. Added parity fallback in `pointAtStringLocation` to map exact end-of-children to `element(offset: childCount)` when the evaluator returns a boundary.
  - Out‑of‑read safety: parity fast‑path avoids `getActiveEditor()` by falling back to cache for legacy and to absolute accumulation when available; tests that call outside `editor.read` were updated to wrap calls.
  - Plugin lists: SelectionParityListTests updated to compute optimized end using `childrenRangeFromFenwick.upperBound`; start/end tests are green.

- Debug print hygiene
  - Removed temporary prints from core tests; kept parity diagnostics gated under `selectionParityDebug` only.

- Swift 6 actor isolation
  - Removed CustomStringConvertible conformance from `EditorMetricsSnapshot` to avoid crossing main actor. Call sites can print fields explicitly. Warning about `nonisolated(unsafe)` resolved.

- Results
  - Green: `LexicalTests/SelectionParityTests`, `LexicalListPluginTests/SelectionParityListTests` under `Lexical-Package` on iOS 26.0.
  - Verified via:
    `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/SelectionParityTests -only-testing:LexicalListPluginTests/SelectionParityListTests test`

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
- Unit tests (always use Lexical‑Package): `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`
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

---

## Bugs (tracked)

- B-0001: Infinite recursion between `absoluteNodeStartLocation` and `RangeCacheItem.locationFromFenwick`
  - Status: Fixed
  - Symptom: Hang/stack overflow when mapping absolute locations under optimized mode (stack trace alternates between both functions).
  - Fix: Use `fenwickTree.getNodeOffset(nodeIndex:)` in AbsoluteLocation fallback; avoid calling back into `locationFromFenwick`.
  - Commit: 5b61d6f

- B-0002: Optimized input — Return/Backspace mismatch vs legacy
  - Status: Repro added; partial fixes landed; off‑by‑one at text‑end still under investigation.
  - Repro Test: `LexicalTests/Phase4/OptimizedInputBehaviorTests.testInsertNewlineAndBackspaceInOptimizedMode` (uses `XCTExpectFailure`).
  - Changes so far:
    - Always normalize previous‑sibling postamble on insert (was parity‑gated).
    - Deterministic parent recompute refreshes each child’s pre/post from pending state after updates.
    - Sync model selection with native selection before text insertion.
  - Next steps:
    - Audit text‑end tie‑breaks in `pointAtStringLocation` for non‑parity mapping.
    - Verify delta generator emits `nodeInsertion` for split pieces during paragraph creation.
  - Commits: 08be794 (+ follow‑up debug print commits)

- B-0003: Playground mode switch not visible on Editor tab
  - Status: Fixed
  - Change: Dedicated bar above editor toolbar hosts the segmented control.
  - Commit: 4564f90

Policy
- For each user‑reported issue, we: (1) add a focused unit test (expected failure until fixed), (2) update this list with status and commit links, and (3) keep verbose debug prints available behind `Diagnostics.verboseLogs` to aid investigation.

---

## Optimized Reconciler — Parity Recovery Plan (2025‑09‑25)

Goal: Make the optimized reconciler feature‑ and behavior‑identical to legacy, then keep it fast. Do this incrementally, test‑first, and without rewrites.

Definition of Done
- Hydration parity: optimized builds TextStorage identical to legacy on first attach and on mode switch.
- Editing parity: Return/Backspace/formatting/list toggles behave exactly like legacy in all covered tests.
- Selection parity: boundary and multi‑paragraph tests green (already enforced), plus new input/formatting tests.
- Stability: dark‑launch mode remains available as a safety net; full iOS suite (Lexical‑Package) passes.

### Roadmap (subtasks)

1) Hydration (initial paint) — optimized path
   - [ ] Fresh‑doc detection triggers sequential INSERTs in document order (runningOffset) with stable Fenwick indices.
   - [ ] Mode‑switch hydration: when switching legacy → optimized, rebuild TextStorage from EditorState.
   - [ ] Tests: HydrationTests (non‑empty state → optimized) and ModeSwitchHydrationTests (legacy → optimized).
   - [ ] Playground: keep dark‑launch toggle in Debug menu as a safety fallback during rollout.

2) Incremental cache hygiene (structure‑only recompute)
   - [ ] Gate parent `childrenLength` recompute to nodeInsertion/nodeDeletion only (skip on pure text/attributes).
   - [ ] Limit recompute scope to affected parents + their ancestors, deepest‑first; refresh each child’s pre/post from pending state.
   - [ ] Tests: IncrementalUpdaterTextLengthTests (leaf updates don’t flip parents), StructureChangeRecomputeTests (insert/delete updates parents deterministically).

3) Selection mapping at text end
   - [ ] Canonicalize exact textRange.upperBound → `.text(offset: textLength)` independent of direction (optimized + legacy parity).
   - [ ] Tests: SelectionUtilsTextEndMappingTests across lengths and affinities.

4) Postamble/newline deltas for element boundaries
   - [ ] Detect element postamble diffs (previous paragraph newline) between current vs pending states.
   - [ ] Emit `textUpdate` at strict lastChildEnd (not parent sums) for both add/remove newline; verify idempotence with cache.
   - [ ] Tests: PostambleDeltaTests and ReturnBackspaceParityTests (driven by `OptimizedInputBehaviorTests`).

5) Formatting parity
   - [ ] Ensure `attributeChange` deltas apply over current text ranges (non‑zero); confirm no accidental string edits.
   - [ ] Tests: FormattingDeltaTests (bold/italic/underline ranges), InlineListToggleTests where relevant.

6) Compare Harness (optional, high‑leverage)
   - [ ] New third tab: **Compare** — two editors (legacy vs optimized) bound to the same EditorState; scripted operations (insert, Return, Backspace, format).
   - [ ] “Diff” action compares attributed strings and reports first divergence (offset/range/attribute set).

7) Full‑suite validation & PR
   - [ ] Flip `OptimizedInputBehaviorTests` to strict and green.
   - [ ] Run SelectionParityTests + SelectionParityListTests (keep green); Formatting/RangeCache suites.
   - [ ] Prepare PR with change list, tests, and a rollback plan (dark‑launch toggle).

### Status Log (update as we go)
- 2025‑09‑25 — Setup
  - [>] Diagnostics in place (verboseLogs); focused test added: `OptimizedInputBehaviorTests` for Return/Backspace.
  - [ ] Hydration: planned; pending implementation and tests.
  - [>] Incremental recompute: gating WIP (limit to structure changes only).
  - [>] Selection text‑end mapping adjusted; verifying with diagnostics under typing flows.
  - [ ] Postamble delta location: refining to lastChildEnd; tests pending.
  - [ ] Formatting deltas parity: pending after hydration/recompute.

### Notes & Guardrails
- Always run the authoritative suite with the `Lexical‑Package` scheme on iOS (iPhone 17 Pro, iOS 26.0) per AGENTS.md.
- For every user‑reported issue, add a focused unit test (expected failure allowed while iterating) and log it in “Bugs (tracked)”.
- No commits to code until focused tests are green; documentation updates are allowed to keep plan accurate.
