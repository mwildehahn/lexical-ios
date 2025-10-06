# AppKit Enablement Plan for Lexical

> ⚠️ **Critical:** Keep Selection suite green as a quick preflight and run the full `Lexical-Package` suite after every change; record both commands and timestamps in the log.

_Last updated: 2025-10-06 • Owner: Core iOS Editor_

## Quick Reference
| Item | Value |
| --- | --- |
| Baseline Commit | `a42a942` (origin/main) |
| Current Phase | Phase 1 — Platform Abstraction (PAL) foundation |
| Next Task | 2.4 Tests checkpoint (Selection slice optional, full suite required) |
| Test Discipline | Full Lexical-Package suite after every change (non-negotiable) |
| Selection Suite Command | `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData -only-testing:LexicalTests/SelectionTests test` |
| Full Suite Command | `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test` |
| Verification Status | Selection suite PASS (2025-10-06 @ 08:35 UTC) |
| Full Suite | PASS (2025-10-06 @ 10:15 UTC) |
| How to Resume | 1) Pull latest. 2) (Optional) Run Selection suite (command above). 3) Run full suite (command above). 4) Continue with Phase 1 task list |

## Current Status Summary
- Repository reset to pristine `origin/main` (commit `a42a942`) — iOS editor behaves as before AppKit work.
- Selection test suite passes on iPhone 17 Pro (iOS 26.0) simulator.
- AppKit/SwiftUI files removed; plan is to reintroduce them incrementally with PAL groundwork.
- Tests scripts from prior branch were not part of baseline (`./scripts/run-ios-tests.sh` etc.); use direct `xcodebuild` commands or recreate helpers later (Phase 0.5 optional).

## Phase Roadmap
Each phase lists required tasks and the verification gate before moving forward. Update the checklist and timestamp in the **Progress Log** after each task.

### Phase 0 — Baseline Confirmation ✅
- [x] Reset to `a42a942`.
- [x] Clean DerivedData, run Selection suite.
- [x] Document commands & status in this plan.

### Phase 1 — Platform Abstraction (PAL) Foundation *(in progress)*
Goal: Introduce cross-platform typealiases and shared targets without altering behaviour.
Tasks:
1.1 [x] Add PAL shim files (`CoreShared/LexicalCore/Platform.swift`, `Platform+Pasteboard.swift`, `Platform+Selection.swift`) with UIKit-backed typealiases only.
    - [x] `Platform.swift`: define `typealias UXColor = UIColor`, etc.; no behavioural changes.
    - [x] `Platform+Pasteboard.swift`: centralise UTType helpers; reuse existing constants.
    - [x] `Platform+Selection.swift`: introduce snapshot structs mirroring current selection data (UIKit-backed for now).
1.2 [x] Introduce `LexicalCoreExports.swift` (re-export placeholder) and leave existing imports untouched.
    - [x] Added guarded stub (`#if canImport`) to avoid duplicate symbol exposure until the new target exists.
1.3 [x] Move baseline Foundation utilities into `CoreShared/LexicalCore`.
    - [x] `Errors.swift`
    - [x] `EditorMetrics.swift`
    - [ ] `StyleEvents.swift` (blocked: still references `Editor`/selection helpers; defer to later phase)
1.4 [x] Create `LexicalCore` target in `Package.swift` (iOS only) and wire existing targets to depend on it.
    - [x] Added standalone `LexicalCore` target and hooked `Lexical`/plugin targets to depend on it.
    - [x] Restored `StyleEvents.swift` under `Lexical/Core` until dependencies are abstracted.

### Phase 2 — Core File Migration
Goal: Gradually migrate selection, range cache, and utility files to PAL types.
Tasks:
2.1 [x] Replace UIKit types in low-risk nodes (DecoratorNode, ParagraphNode, supporting node attributes) with PAL aliases.
    - [x] DecoratorNode now exposes `UXView` APIs.
    - [x] TextNode default highlight colors use `UXColor`.
    - [x] Code/Quote custom drawing attributes migrated to `UXColor`/`UXEdgeInsets`.
    - [x] ParagraphNode now imports only Foundation (no UIKit dependency).
2.2 [x] Update `RangeSelection`, `SelectionUtils`, and related helpers to use PAL types (no AppKit yet).
    - [x] Replaced `UITextStorageDirection`/`UITextGranularity` with `UX` aliases across RangeSelection, SelectionUtils, RangeCache, NativeSelection, Editor, and frontends.
    - [x] Bridged frontend protocol + implementations (LexicalView, read-only context) to the PAL enums.
2.3 [x] Convert `Events.swift` and TextView bridges to PAL types.
    - [x] Swapped pasteboard plumbing to `UXPasteboard` across events, copy/paste helpers, and TextView.
2.4 [ ] Tests: Selection suite after each sub-task; full suite before exiting phase. Document outcomes.

### Phase 3 — AppKit Frontend Scaffolding
Goal: Introduce `LexicalAppKit` target with compile-gated stubs.
Tasks:
3.1 [ ] Add `LexicalAppKit` target (NSView wrappers, TextViewMac stub) behind `#if canImport(AppKit)`.
3.2 [ ] Add AppKit adapters and placeholder overlay view (no functionality yet).
3.3 [ ] Selection suite + full iOS suite → PASS.

### Phase 4 — SwiftUI Wrappers
Goal: Provide SwiftUI representations for iOS (and placeholder for macOS once ready).
Tasks:
4.1 [ ] Create `LexicalSwiftUI` target with iOS `LexicalEditorView` and decorator helper.
4.2 [ ] Gate macOS representable until AppKit frontend is functional.
4.3 [ ] Run Selection suite + targeted SwiftUI smoke tests (if any) and log results.

### Phase 5 — AppKit Feature Implementation
Goal: Implement macOS editing host with feature parity and verification.
Tasks:
5.1 [ ] Flesh out TextKit integration (`TextViewMac`, selection mapping, marked text).
5.2 [ ] Implement AppKit overlay/decorator support.
5.3 [ ] Add macOS unit tests (pending enablement) behind new test target.
5.4 [ ] Iterate until macOS build + tests pass locally.

### Phase 6 — macOS Enablement & Packaging
Goal: Turn on macOS products in `Package.swift`, add CI coverage.
Tasks:
6.1 [ ] Update `Package.swift` with macOS platform entry; expose `LexicalAppKit` product.
6.2 [ ] Build macOS demo / playground target.
6.3 [ ] Document enablement steps and verify CI scripts.

## Operational Protocols
- **Testing cadence**
  - After every code change run the full suite command listed above (Lexical-Package).
  - Optionally run the Selection suite command before the full run for faster feedback, but it does **not** replace the full suite requirement.
  - Record PASS/FAIL plus command in the **Progress Log** every time a suite runs.
- **Documentation**
  - Update this plan after each task, including timestamp, command(s), and outcome.
  - Append detailed context to the **Progress Log** (chronological) if more space needed; keep the top summary concise.
- **Scripts**
  - `./scripts/run-ios-tests.sh` etc. are not part of baseline; consider reintroducing in Phase 1.6 (optional). Meanwhile use `xcodebuild` directly.
- **Session recovery checklist**
  1. Pull latest and install Xcode updates if needed.
  2. (Optional) Run the Selection suite for a quick smoke signal.
  3. Run the full Lexical-Package suite to confirm the baseline is green.
  4. Re-read **Quick Reference** rows (commands, next task) and confirm the current phase.
  5. Continue with the first unchecked task in the active phase and log results immediately after execution.

## Progress Log
| Date (UTC) | Phase | Task | Notes |
| --- | --- | --- | --- |
| 2025-10-06 | Phase 0 | Baseline reset | Checkout `origin/main` (`a42a942`); Selection suite PASS (10:03 UTC); plan re-authored |
| 2025-10-06 | Phase 0 | Verification | Selection suite PASS again after plan update (10:12 UTC) |
| 2025-10-06 | Phase 1 | Task 1.1 | Added PAL shim files; Selection suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData -only-testing:LexicalTests/SelectionTests test`, 08:35 UTC) |
| 2025-10-06 | Phase 1 | Full suite check | Full Lexical-Package PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 08:46 UTC) |
| 2025-10-06 | Phase 1 | Task 1.2 | Added guarded `LexicalCoreExports.swift`; cleaned derived data via `xcodebuild … clean`; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 09:21 UTC) |
| 2025-10-06 | Phase 1 | Task 1.3 | Moved `Errors.swift` and `EditorMetrics.swift` into CoreShared; StyleEvents deferred (Editor dependency); full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 09:33 UTC) |
| 2025-10-06 | Phase 1 | Task 1.4 | Added `LexicalCore` SPM target, updated dependencies, kept StyleEvents under `Lexical/Core`; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 09:38 UTC) |
| 2025-10-06 | Phase 2 | Task 2.1 | Converted Decorator/Code/Quote/Text nodes to `UX*` aliases; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 09:50 UTC) |
| 2025-10-06 | Phase 2 | Discipline | Re-confirmed test mandate warning in docs; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 09:55 UTC) |
| 2025-10-06 | Phase 2 | Task 2.2 | Swapped selection helpers to `UXTextStorageDirection`/`UXTextGranularity`; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 10:07 UTC) |
| 2025-10-06 | Phase 2 | Task 2.3 | Migrated Events + copy/paste bridges to `UXPasteboard`; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 10:15 UTC) |

## Appendix — Deferred / Optional Items
- Reinstate helper scripts (`run-ios-tests.sh`, `run-ios-test-suites.sh`) with timeout wrappers after Phase 1.
- Automate Selection + full suite commands via Makefile once PAL migration stabilizes.
- Consider DocC updates for PAL/ AppKit once targets are functional.
