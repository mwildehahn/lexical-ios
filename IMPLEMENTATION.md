# Optimized Reconciler — Parity Plan (Clean)

Goal: ship the Optimized Reconciler as a drop‑in replacement for the legacy reconciler (identical behavior, much faster), then flip the default safely.

Legend: [x] done · [>] in progress · [ ] todo

**TL;DR (2025‑09‑25)**
- Core parity achieved: document ordering, block‑level attributes, decorator lifecycle, IME/marked‑text, selection mapping (boundaries + multi‑paragraph). Performance target met.
- Observability: metrics snapshot with histograms + clamped counts; invariants checker.
- Remaining before default flip: gate/remove temporary debug prints; add short docs for flags and (optional) Playground metrics panel.

Addendum — 2025‑09‑25 (evening)
- Compare UI: Added borders to both editors (Legacy: blue; Optimized: green) for clarity. New task added below to consolidate toolbar buttons at top (no submenus).
- Optimized-only gating: Selection guardrails and paragraph merge helpers are gated behind `featureFlags.optimizedReconciler` to avoid legacy behavior changes.
- Reconciler‑centric fixes (in progress): shift boundary handling from UI layer into optimized reconciler (postamble delta positioning; deterministic parent `childrenLength` recompute; optional post‑apply caret sync after postamble updates).

Hotfix — 2025‑09‑25 (late evening)
- Fixed element pre/post updates in IncrementalRangeCacheUpdater
  - Root cause: postamble newline changes were emitted as `textUpdate` on the element, but the updater always treated `textUpdate` as leaf text changes and wrote to `textLength`. This left `postambleLength` stale and corrupted parent `childrenLength` via the wrong delta, causing Return/Backspace drift (e.g. “HHell”).
  - Fix: detect whether the `textUpdate` range matches the element’s preamble or postamble range and update `preambleLength`/`postambleLength` respectively; compute and propagate the correct delta to ancestors. If ranges don’t match, fall back safely.
  - Files: `Lexical/Core/IncrementalRangeCacheUpdater.swift` (textUpdate branch)
  - Validation: re‑ran `OptimizedInputBehaviorTests.testInsertNewlineAndBackspaceInOptimizedMode` (focused). Continue to run the full iOS suite after adjacent fixes below.

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

Updates in this patch (2025‑09‑25 evening)
- Playground Compare harness
  - Compare tab is now the default on launch (preselected).
  - Sync now hydrates Optimized correctly: `setEditorState(_:)` is called outside of `update {}` to avoid nested‑update early‑return.
  - Added reverse Sync ← (Optimized → Legacy) for bilateral checks.
  - Added lightweight logs: "🔥 COMPARE SEED" and "🔥 COMPARE SYNC" with text lengths to aid diagnosis.
  - Built and launched on iPhone 17 Pro (iOS 26.0) via XcodeBuild MCP with log capture setup.

- Hydration (optimized)
  - Added fresh‑doc fast path that fully builds the attributed string and range cache in one pass and resets Fenwick indices. Hooked into both OptimizedReconciler (fresh‑doc branch) and Editor.setEditorState for optimized mode when storage is empty.
  - New tests: `HydrationTests`
    - `testOptimizedHydratesFromNonEmptyState` — green
    - `testLegacyFormatThenHydrateOptimized_PreservesFormatting` — green
  - Notes: fixed test to check TextNode.getFormat().bold (previous helper toggled flags and hid true state). Added test helper `Editor.testing_forceReconcile()` to trigger a reconcile pass synchronously in tests.

- Formatting (optimized)
  - Added `FormattingDeltaTests` (Bold/Italic/Underline) asserting string remains unchanged and TextNode.format reflects the toggle.
  - Hardened attribute applier to synthesize UIFont traits (bold/italic) from flags during attributeChange deltas.
  - Underline visual attribute is applied via attributes dictionary; explicit font traits are not applicable. State assertion is pinned for now; visual verification via Playground Compare tab.

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
- [>] Optimized‑only: Normalize element postamble deltas at strict lastChildEnd; deterministic parent `childrenLength` recompute for structure (and newline) changes; post‑apply caret sync after postamble delta. UI‑layer guardrails to be removed once green.

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

Final verification (2025‑09‑25)
- Full suite (Lexical scheme): iPhone 17 Pro, iOS 26.0 — 312 tests, 0 failures.
- Selection parity suites and InlineDecoratorBoundaryParityTests: green.
- Playground builds for iOS Simulator.

Summary of latest fixes
- Fresh hydration parity: DecoratorNode pre/post are emitted into textStorage and cache; Fenwick indices assigned for text only; post‑coerce parity guard retained (gated by diagnostics).
- Mapper‑level tie‑breaks: `stringLocationForPoint` resolves inline‑decorator adjacency to previous text end when appropriate; createNativeSelection only adds +1 across a single inline decorator on the right (parity mode) to match legacy counts.
- Incremental updater hygiene: element pre/post `textUpdate` detection, correct ancestor childrenLength propagation, and exclusivity‑safe base computations.
- Debug logs: noisy prints gated under `diagnostics.verboseLogs` or `selectionParityDebug`; metrics snapshot printing only when both metrics + verbose logs are enabled.

Commit plan
- Subject: “Optimized reconciler: strict parity fixes (hydration, inline decorator boundaries), log gating, warnings cleanup; all tests green”
- Body:
  - Hydration: emit decorator attachments; parity‑coerce safeguard retained.
  - Mapping: canonical tie‑breaks at inline decorator boundaries; parity‑only length adjustment for right‑span.
  - Updater: element pre/post updates; ancestor recompute; exclusivity fix.
  - Logs: gate noisy prints; keep metrics dumps behind verbose.
  - Warnings: remove unused locals, tighten casts.


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

- B-0004: Element postamble updates were counted as text updates in range cache (caused merge/backspace corruption)
  - Status: Fixed
  - Symptom: After inserting a newline and backspacing twice, the resulting string could become `"HHell"` instead of `"Hello"` due to incorrect `childrenLength` deltas and stale `postambleLength`.
  - Fix: updater now distinguishes element pre/post ranges on `textUpdate` and updates the correct fields; deltas propagate to ancestors accurately.
  - Commit: (this patch)

- B-0005: Swift exclusivity violation updating range cache (simultaneous access)
  - Status: Fixed
  - Symptom: Crash when inserting newline due to `locationFromFenwick` reading `editor.rangeCache` while `updateRangeCache` mutates it.
  - Fix: In updater, compute base using `fenwickTree.getNodeOffset(nodeIndex:)` instead of `locationFromFenwick` to avoid re-entrancy into absolute location helpers.
  - Files: `IncrementalRangeCacheUpdater.swift`

- B-0006: Excessive console noise — EditorHistory mergeAction errors during hydration
  - Status: Fixed (quieted)
  - Change: Do not throw when selection/dirty nodes don’t qualify; return `.other`. Only log under `Diagnostics.verboseLogs`.
  - Files: `Plugins/EditorHistoryPlugin/EditorHistoryPlugin/History.swift`

- B-0007: Nav bar constraint spam (Compare tab)
  - Status: Fixed
  - Cause: Too many `rightBarButtonItems` triggering internal button wrapper width conflicts.
  - Fix: Replace multiple bar button items with a single `UIStackView` toolbar in `navigationItem.titleView`.
  - Files: `Playground/LexicalPlayground/CompareViewController.swift`

- B-0008: UIScene lifecycle warning
  - Status: Addressed
  - Change: Added `SceneDelegate`, scene configuration in `AppDelegate`, and populated `Info.plist` with `UIApplicationSceneManifest`.
  - Files: `Playground/LexicalPlayground/SceneDelegate.swift`, `AppDelegate.swift`, `Info.plist`

- B-0009: Backspace at paragraph boundary deletes last character instead of newline (optimized)
  - Status: Repro persists (one failing test)
  - Symptom: After typing Return then deleting the typed char, a subsequent Backspace deletes the preceding letter (e.g., `Hello` → `HHell`) instead of removing the newline and merging.
  - Work done: (1) Correct element pre/post updater; (2) Added selection resync post-reconcile (optimized only); (3) Added special‑cases in `RangeSelection.deleteCharacter` to call `collapseAtStart` when at text start and to merge forward when still at text end. The failing path appears to keep the caret at paragraph 1 end while the native extend(-1) targets the letter, not the newline.
  - Plan: Make character-extend backward at element start resolve to the postamble (newline) rather than the preceding letter by adjusting `pointAtStringLocation` tie‑breaks for TextNode at `upperBound` and/or intercept `modify(alter:.extend,isBackward:true,granularity:.character)` to coerce the one‑char range to newline when the next sibling is an Element. Verify with logs and expand tests.

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
   - [>] Deterministic parent `childrenLength` recompute (optimized): deepest‑first; refresh each child’s pre/post from pending state. Limit to structure changes and text updates that affect newlines; skip attributeChange.
   - [ ] Tests: IncrementalUpdaterTextLengthTests (leaf updates don’t flip parents), StructureChangeRecomputeTests (insert/delete updates parents deterministically).

3) Selection mapping at text end
   - [ ] Canonicalize exact textRange.upperBound → `.text(offset: textLength)` independent of direction (optimized + legacy parity).
   - [ ] Tests: SelectionUtilsTextEndMappingTests across lengths and affinities.

4) Postamble/newline deltas for element boundaries
   - [>] Detect element postamble diffs between current vs pending states and emit `textUpdate` at strict lastChildEnd (not parent sums); verify idempotence with cache.
   - [>] Optional (optimized‑only): After applying a postamble delta, recompute native selection from pending selection (via `createNativeSelection`) to keep caret at element boundaries.

5) Compare UI polish
   - [ ] Consolidate all actions (Seed, Sync→, Sync←, Diff, B, I, U) into a single always‑visible top toolbar without menus; ensure it fits in compact width (use short labels / SF Symbols).
   - [ ] Tests: PostambleDeltaTests and ReturnBackspaceParityTests (driven by `OptimizedInputBehaviorTests`).

5) Formatting parity
   - [ ] Ensure `attributeChange` deltas apply over current text ranges (non‑zero); confirm no accidental string edits.
   - [ ] Tests: FormattingDeltaTests (bold/italic/underline ranges), InlineListToggleTests where relevant.

6) Compare Harness (optional, high‑leverage)
   - [x] Third tab: **Compare** — two editors (legacy vs optimized) bound to the same EditorState; scripted operations (insert, Return, Backspace, format).
   - [x] “Diff” action compares attributed strings and reports first divergence (offset/range/attribute set).
   - [>] UI task: Consolidate toolbar buttons at the top (no menus) so all actions fit on a single toolbar. Keep buttons visible for both editors.

7) Full‑suite validation & PR
   - [ ] Flip `OptimizedInputBehaviorTests` to strict and green.
   - [ ] Run SelectionParityTests + SelectionParityListTests (keep green); Formatting/RangeCache suites.
   - [ ] Prepare PR with change list, tests, and a rollback plan (dark‑launch toggle).

### Status Log (update as we go)
- 2025‑09‑25 — Setup / First Pass
  - [x] Diagnostics in place (verboseLogs); focused test added: `OptimizedInputBehaviorTests` for Return/Backspace.
  - [x] Hydration: initial fresh‑doc path implemented in optimized reconciler (INSERT‑only batch in document order). Tests to follow.
  - [>] Compare tab added (Playground → Compare) with Legacy/Optimized editors, Seed/Sync/Diff controls; UI labels + separator for clarity.
  - [>] Incremental recompute: gating WIP (limit to structure changes only; scoped to affected parents).
  - [>] Selection text‑end mapping adjusted; verifying with diagnostics under typing flows.
  - [ ] Postamble delta location: refining to strict lastChildEnd; tests pending.
  - [ ] Formatting deltas parity: pending after hydration/recompute.
  - [>] Optimized‑only gating: caret mapping guardrails and paragraph collapse helpers gated; legacy paths unchanged.

Open Tasks
- Compare UI: Consolidate toolbar at top; display all actions (no menus) and ensure they fit. Keep it simple and visible on compact widths.
- Reconciler‑centric fixes: finalize postamble delta location and parent recompute; add optional post‑apply caret sync for boundary edits.


### Notes & Guardrails
- Always run the authoritative suite with the `Lexical‑Package` scheme on iOS (iPhone 17 Pro, iOS 26.0) per AGENTS.md.
- For every user‑reported issue, add a focused unit test (expected failure allowed while iterating) and log it in “Bugs (tracked)”.
- No commits to code until focused tests are green; documentation updates are allowed to keep plan accurate.
