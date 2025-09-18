# Implementation Progress: Targeted Reconciler

## Purpose
Track tasks, testing, and rollout steps for introducing anchor-driven reconciliation and targeted TextStorage updates in Lexical iOS. Use this checklist to coordinate engineering and validation work across iterations from PLAN.md. Aleays read PLAN.md before starting with tasks here.

## Workstreams

### 1. Baseline Measurement & Instrumentation
- [x] Instrument existing reconciler metrics to capture node counts, dirty spans, and elapsed time per update.
  - **Tests:** Add unit coverage in `LexicalTests/Tests/MetricsTests.swift` that toggles metrics collection and asserts emitted `ReconcilerMetric` payloads. Run `swift test`.
- [x] Build synthetic-document fixtures (small, medium, large) for benchmarking.
  - **Tests:** Add helper builders under `LexicalTests/Fixtures/` and exercise them via a new `ReconcilerPerformanceTests` XCTest case guarded with `#if DEBUG`. Execute with `swift test --filter ReconcilerPerformanceTests`.
- [x] Capture baseline timing snapshots and document findings in `docs/reconciler-benchmarks.md`.
  - **Tests:** CI sanity by asserting benchmark harness returns non-empty results. Use `swift test --filter ReconcilerPerformanceTests/testGeneratesBaselineSnapshot`.

### 2. Anchor Emission & Storage
- [x] Introduce feature-flag (`FeatureFlags.reconcilerAnchors`) plumbing and default disabled state.
  - **Tests:** Extend `LexicalTests/Tests/FeatureFlagsTests.swift` to verify flag wiring. Run `swift test --filter FeatureFlagsTests`.
- [x] Implement marker emission on block nodes (paragraph, heading, quote) by overriding `getPreamble`/`getPostamble` when flag enabled.
  - **Tests:** Snapshot serialized text via `LexicalTests/Tests/ParagraphNodeTests.swift` to confirm anchors wrap expected content. Run `swift test --filter ParagraphNodeTests`.
- [x] Store anchor metadata (node key hash, marker ids) on `RangeCacheItem` for quick lookup.
  - **Tests:** Add targeted checks in `LexicalTests/Tests/RangeCacheTests.swift` ensuring cache stores anchor info only when flag set. Run `swift test --filter RangeCacheTests`.

- [ ] Update `RangeCache` adjustments to use local offsets (Fenwick tree or equivalent) after delta operations.
### 3. TextStorage Delta Applier
- [x] Implement `TextStorageDeltaApplier` utility that locates anchors and applies scoped mutations to `NSTextStorage`.
  - **Tests:** `LexicalTests/Tests/ReconcilerDeltaTests.swift` validates anchor-only mutations alongside `xcodebuild -scheme Lexical-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0" test -only-testing:LexicalTests/ReconcilerDeltaTests`.
- [x] Integrate delta applier into reconciler when anchor flag is active; maintain legacy delete/insert otherwise.
  - **Tests:** Full assurance via `xcodebuild -scheme Lexical-Package -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0" test`.
- [ ] Update `RangeCache` adjustments to use local offsets (Fenwick tree or equivalent) after delta operations.
  - **Tests:** Add regression case in `LexicalTests/Tests/RangeCacheTests.swift` verifying downstream node locations adjust logarithmically (assert minimal touched nodes). Run `swift test --filter RangeCacheTests/testUpdatesOffsetsWithFenwick`.

### 4. Structural Fallback Detection
- [ ] Detect sibling order changes or decorator insertions that invalidate anchor diffing and trigger legacy reconciliation.
  - **Tests:** Scenario-based coverage in `LexicalTests/Tests/ReconcilerFallbackTests.swift` ensuring fallback path activates and produces correct text. Run `swift test --filter ReconcilerFallbackTests`.
- [ ] Emit structured metrics (`fallbackReason`) when legacy path runs for instrumentation.
  - **Tests:** Extend metrics tests to assert fallback reasons propagate to `EditorMetricsContainer`. Run `swift test --filter MetricsTests/testRecordsFallbackReasons`.

### 5. Selection, Copy/Paste, and Accessibility
- [ ] Update `RangeCache.pointAtStringLocation` to account for anchor characters without disturbing caret math.
  - **Tests:** Extend `LexicalTests/Tests/SelectionTests.swift` with anchor-enabled caret scenarios. Run `swift test --filter SelectionTests`.
- [ ] Sanitize anchors during copy/paste flows and exported plain text.
  - **Tests:** Add coverage in `LexicalTests/Tests/CopyPasteHelpersTests.swift` verifying markers strip cleanly yet survive round-trips in rich text. Run `swift test --filter CopyPasteHelpersTests`.
- [ ] Validate `UIAccessibility` announcements ignore markers.
  - **Tests:** Introduce UI test stub (or accessibility-focused unit test) under `Playground/Tests/` ensuring attributed strings presented to VoiceOver exclude anchors. Run `xcodebuild -scheme Lexical-Package -destination "platform=iOS Simulator,name=iPhone 17,OS=26.0" test`.

### 6. Monitoring & Rollout
- [ ] Add editor flag toggles and runtime diagnostics (`EditorConfig` or debug UI) to flip anchors on/off.
  - **Tests:** Extend `Playground` app UI tests to confirm toggle persistence. Run `xcodebuild ... test` with playground target.
- [ ] Implement automated sanity checker that compares anchor output vs legacy output on sampled updates; disable flag if divergence detected.
  - **Tests:** Add `LexicalTests/Tests/ReconcilerSanityTests.swift` simulating divergence and asserting fallback disables anchors. Run `swift test --filter ReconcilerSanityTests`.
- [ ] Document rollout stages and add migration notes to `docs/Changelog.md`.
  - **Tests:** Lint docs with existing tooling (`swift build` ensures DocC references compile); manual doc review.

## Status Tracking
- Update checkboxes as tasks complete.
- Attach benchmark snapshots and test results to PRs enabling each workstream.
- Ensure `swift test` and the canonical `xcodebuild ... test` command are green before flipping default flags.
