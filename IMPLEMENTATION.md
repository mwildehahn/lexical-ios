# AppKit Enablement Plan for Lexical

> ⚠️ **Critical:** Keep Selection suite green as a quick preflight and run the full `Lexical-Package` suite after every change; record both commands and timestamps in the log.

_Last updated: 2025-10-06 • Owner: Core iOS Editor_

## Quick Reference
| Item | Value |
| --- | --- |
| Baseline Commit | `a42a942` (origin/main) |
| Current Phase | Phase 5 — AppKit Feature Implementation |
| Next Task | 5.8c Decorator mount/hit-test regression (AppKit) |
| Test Discipline | Full Lexical-Package suite after every change (non-negotiable) |
| Selection Suite Command | `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData -only-testing:LexicalTests/SelectionTests test` |
| Full Suite Command | `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test` |
| Mac Suite Command | `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test` |
| Verification Status | Full + mac suites PASS (2025-10-07 @ 10:12 UTC) |
| Full Suite | PASS (2025-10-07 @ 10:12 UTC) |
| Mac Suite | PASS (2025-10-07 @ 10:12 UTC; 2 tests skipped pending implementation) |
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
2.4 [x] Tests: Selection suite after each sub-task; full suite before exiting phase. Logged runs at 09:50 / 09:55 / 10:07 / 10:15 UTC.

### Phase 3 — AppKit Frontend Scaffolding
Goal: Introduce `LexicalAppKit` target with compile-gated stubs.
Tasks:
3.1 [x] Add AppKit stubs (`LexicalNSView`, `TextViewMac`, `LexicalOverlayViewMac`) behind `#if canImport(AppKit)`.
3.2 [x] Add AppKit adapters and placeholder overlay view (no functionality yet).
    - [x] Added `AppKitFrontendAdapter` skeleton wiring editor, host view, text view, and overlay.
    - [x] Extended stubs to track attached subviews and tappable rects.
3.3 [x] Selection suite + full iOS suite → PASS.

### Phase 4 — SwiftUI Wrappers
Goal: Provide SwiftUI representations for iOS (and placeholder for macOS once ready).
Tasks:
4.1 [x] Create `LexicalSwiftUI` target with iOS `LexicalEditorView` and decorator helper.
    - [x] Added `LexicalEditorView` SwiftUI representable backed by `LexicalView`.
    - [x] Added `SwiftUIDecoratorNode` scaffolding using `UIHostingController`.
4.2 [x] Gate macOS representable until AppKit frontend is functional.
    - [x] Added macOS placeholder view to keep API surface compiling without exposing unfinished functionality.
4.3 [x] Run Selection suite + targeted SwiftUI smoke tests (if any) and log results.
    - [x] Selection suite (`-only-testing:LexicalTests/SelectionTests`) @ 11:16 UTC.

### Phase 5 — AppKit Feature Implementation
Goal: Implement macOS editing host with feature parity and verification.
Tasks:
5.1 [x] Flesh out TextKit integration (`TextViewMac`, selection mapping, marked text).
    - [x] Wired `TextViewMac` with Lexical `Editor`, TextStorage, LayoutManager scaffolding.
    - [x] Added attachment helpers in `LexicalNSView` for text and overlay views.
    - [x] `AppKitFrontendAdapter` now binds host view, text view, and overlay instances.
5.2 [x] Implement AppKit overlay/decorator support.
    - [x] Overlay view now tracks tappable rects and forwards tap callbacks via adapter.
5.3 [x] Add macOS unit tests (pending enablement) behind new test target.
    - [x] Added `LexicalMacTests` SPM target conditioned on macOS with placeholder assertions/skip.
5.4 [ ] Complete selection + IME parity on AppKit.
    - [x] Generalize `Frontend` protocol to PAL types and add AppKit frontend implementation scaffolding.
    - [x] Map native selection changes (NSRange/NSTextRange) to `RangeSelection` and back.
    - [x] Handle marked-text lifecycle (start/update/end) with IME-friendly behavior.
    - [x] Route key commands (delete, movement, formatting) through Lexical commands.
    - [x] Unit-test selection/IME bridging in `LexicalMacTests`.
5.5 [ ] Bridge pasteboard + command surfaces.
    - [x] Mirror `CopyPasteHelpers` using AppKit APIs (`NSPasteboard`, UTType mapping).
    - [x] Wire copy/cut/paste commands from `TextViewMac` into Lexical commands.
    - [x] Implement delete word/line / tab / newline command routing via menu/key equivalents.
    - [x] Add macOS-specific unit coverage for pasteboard + command routing.
5.6 [x] Decorator lifecycle + overlay hit-testing.
    - [x] Implement AppKit decorator mount/unmount API parity (reuse `DecoratorNode`).
    - [x] Calculate overlay rects in AppKit coordinate space (selection/scroll aware).
    - [x] Forward pointer/tap events through adapter to decorator nodes.
    - [x] Add integration tests for decorator hit-testing (mac target).
5.6a [x] **Priority:** Enable LexicalMacTests build + execution.
    - [x] Added `LexicalUIKitAppKit` shim target (re-exports `LexicalUIKit`) and updated `LexicalMacTests` imports; Selection + mac suites green (08:35/08:36 UTC).
    - [x] Verify remaining UIKit dependencies in core rely on PAL/guards; audited shared sources (`Lexical/Core/**`, TextKit, helpers) and confirmed every UIKit import is wrapped in `#if canImport(UIKit)` with AppKit/PAL fallbacks where required.
    - [x] Update `Package.swift` / target membership so `Lexical` stays platform-neutral; documented layout: `Lexical` target now owns Core, Helper, TextKit, PAL, read-only view stacks; `LexicalUIKit` hosts interactive UIKit view + input pipeline; `LexicalAppKit` links shared core via PAL.
    - [x] Restore mac build dependencies (include AppKit-specific helpers) and add any missing shims (e.g. TextKit availability wrappers, pasteboard helpers). Outcome: verified `LexicalAppKit` links only against shared PAL types; no additional shims required beyond existing Platform helpers. Documented shared layout and ensured mac target resolves without pulling UIKit-only sources.
    - [x] `xcodebuild ... LexicalMacTests ...` PASS logged (21:23 UTC, 2 tests skipped).
    - [x] Full Lexical-Package suite PASS logged (09:06 UTC) after shim/audit.
5.7 [ ] Performance / QA passes (scrolling, typing perf, keyboard shortcuts) and prepare macOS sample harness.
    5.7a [ ] Benchmark typing/scrolling responsiveness
        - [x] Add XCTest `measure` harness for typing throughput (AppKit).
        - [x] Capture baseline numbers and log in plan. Baseline (2025-10-07 @ 10:12 UTC): typing insert batch average ≈1.7ms, scroll paging loop average ≈11ms (first iteration 120ms warm-up).
    5.7b [ ] Validate keyboard shortcuts (movement/deletion/format)
        - [x] Expand mac tests to assert command dispatch coverage (delete char/word, indent/outdent, bold toggle).
        - [x] Document any missing shortcuts / TODOs (none observed for covered commands; copy/cut/paste still pending implementation test support).
    5.7c [ ] Build lightweight macOS sample harness for manual QA
        - [x] Scaffold sample harness (`Examples/AppKitHarness/LexicalMacHarness.swift`).
        - [x] Document launch instructions (`Examples/AppKitHarness/README.md`).
    5.7d [x] Document known gaps / perf notes
        - [x] Summarized perf baselines and remaining TODOs (copy/cut/paste command validation) below.
5.8 [ ] Expand unit/integration test suite for AppKit.
    5.8a [x] Add selection/IME regression tests (mac target).
    5.8b [x] Cover pasteboard/command cases.
    5.8c [x] Cover decorator mount/hit-test flows.
        - [x] Added multi-decorator regression (`testOverlayRectsRespectInsetsForMultipleDecorators`) validating frame transforms with non-zero text container insets.
        - [x] Added cache cleanup regression (`testOverlayTargetsClearedAfterDecoratorRemoval`) asserting overlay rect removal and decoratorPositionCache pruning.
    5.8d [x] Ensure snapshot/placeholder tests for placeholder rendering.
        - [x] Added placeholder color regression verifying placeholder tint appears only when the buffer is empty.
        - [x] Added placeholder removal regression ensuring removing placeholder restores default text color.
5.9 [ ] Iterate until macOS build + tests pass locally.

**Phase 5.7 Notes (2025-10-07)**
- Typing benchmark (20 paragraphs of pangram) averages ≈1.7 ms per update; scroll paging loop averages ≈11 ms after the first warm-up iteration (≈120 ms).
- Keyboard shortcuts validated: delete backward, delete word backward (⌥⌫), indent (Tab), toggle bold (⌘B). Copy/cut/paste dispatch remains to be verified once AppKit pasteboard parity lands (tests currently skipped).
- Manual QA harness available under `Examples/AppKitHarness`, mirroring the seeded document used in tests.

**Phase 5.8 Running Notes**
- 5.8a (IME regression) is now covered by `testMarkedTextInsertionBridgesThroughEditor`, which exercises `setMarkedText` + `unmarkText` and confirms the editor clears any marked range after commit.
- Copy/cut/paste command dispatch tests (5.8b) run interception-only listeners so platform handlers still execute; no regressions seen.
- 5.8c introduces multi-decorator assertions (`testOverlayRectsRespectInsetsForMultipleDecorators`) and cache cleanup verification (`testOverlayTargetsClearedAfterDecoratorRemoval`), ensuring overlay transforms honor text container insets and stale rects disappear after removal.
- 5.8d verifies placeholder rendering: `testPlaceholderAppliesPlaceholderColorWhenEmpty` confirms placeholder tint only appears when the buffer is empty, and `testPlaceholderClearsAfterPlaceholderRemoval` regresses default color restoration. Guarded `TextViewMac.showPlaceholderText()` against recursive placeholder updates to avoid TextStorage re-entry loops.

### Phase 6 — macOS Enablement & Packaging
Goal: Turn on macOS products in `Package.swift`, add CI coverage.
Tasks:
6.1 [ ] Expose `LexicalAppKit` product + macOS platform in SPM.
    6.1a [ ] Audit current targets/products for platform assumptions (Lexical, LexicalUIKit, plugins, tests).
    6.1b [ ] Update `Package.swift` (add `.macOS(.v14)` platform, conditional dependencies, public `LexicalAppKit` product, ensure mac-only targets don’t drag UIKit).
    6.1c [ ] Verify SPM graph (`swift package describe`) and run required suites (`Lexical-Package` + `LexicalMacTests`) to confirm iOS + mac builds remain green.
    6.1d [ ] Capture packaging changes in `IMPLEMENTATION.md` progress log (commands, timestamps) and note any targets still iOS-only.
6.2 [ ] Build macOS sample app / playground target.
    6.2a [ ] Evaluate existing `Examples/AppKitHarness` and decide whether to promote it or create a new Xcode target/SwiftPM demo.
    6.2b [ ] Implement the chosen sample (project settings, bundle identifiers, minimal UI wiring) and ensure it links against the SPM `LexicalAppKit` product.
    6.2c [ ] Add build/run instructions plus troubleshooting notes to docs (likely `Examples/AppKitHarness/README.md` or new doc section).
    6.2d [ ] Run mac build of the sample (`xcodebuild -scheme <sample> -destination 'platform=macOS,arch=arm64' build`) and log results.
6.3 [ ] Publish migration notes + API docs for AppKit consumers.
    6.3a [ ] Update README / DocC with instructions for selecting iOS vs. macOS products (including SwiftUI integration expectations).
    6.3b [ ] Document known gaps (e.g., plugins still UIKit-only) and recommended minimum OS versions.
    6.3c [ ] Prepare adoption checklist + release notes draft, referencing new package products and required verification commands.

**Phase 6 Planning Notes (2025-10-07)**
- Package.swift currently declares only `.iOS(.v16)` and exports iOS-centric products; enabling macOS will require conditionalising iOS-only targets (LexicalUIKit + dependent plugins) so mac builds resolve cleanly.
- LexicalAppKit already exists as a target but is not exposed as a product; once macOS is listed in `platforms`, ensure plugins/tests that rely on UIKit remain gated or wrapped with `#if canImport(UIKit)` to avoid compilation errors.
- mac sample deliverable should re-use `Examples/AppKitHarness` where possible to minimise duplication; final plan is to wire it as a standalone Xcode target that consumes the SwiftPM package.
- Documentation work (6.3) should cover product selection, minimum macOS version (14+), and caveats about remaining UIKit-only plugins until future phases.

### Phase 7 — Cross-Platform SwiftUI Surface
Goal: Provide a unified SwiftUI layer that selects the appropriate platform implementation.
Tasks:
7.1 [ ] Hook `LexicalEditorView` to `LexicalAppKit` when running on macOS.
7.2 [ ] Provide decorator bridging helpers so SwiftUI decorators render on both platforms.
7.3 [ ] Expand SwiftUI documentation + samples (macOS/iOS side-by-side).

### Phase 8 — Quality, Docs, & Release Readiness
Goal: Finalize AppKit support and ensure readiness for downstream adoption.
Tasks:
8.1 [ ] Execute end-to-end regression test plans (selection, pasteboard, decorators, accessibility).
8.2 [ ] Update public docs / README with AppKit guidance and SwiftUI usage.
8.3 [ ] Prepare release notes + adoption checklist.

## Operational Protocols
- **Testing cadence**
  - After every code change run the full suite command listed above (Lexical-Package), then immediately run the macOS suite command (LexicalMacTests).
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
| 2025-10-06 | Phase 3 | Task 3.1 | Added AppKit scaffolding stubs (`LexicalNSView`, `TextViewMac`, `LexicalOverlayViewMac`); full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 10:24 UTC) |
| 2025-10-06 | Phase 3 | Task 3.2 | Stubbed `AppKitFrontendAdapter` and overlay plumbing; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 10:31 UTC) |
| 2025-10-06 | Phase 3 | Task 3.3 | iOS test checkpoint (no AppKit runtime yet); full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 10:36 UTC) |
| 2025-10-06 | Phase 4 | Task 4.1 | Created `LexicalSwiftUI` target + decorator scaffolding; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 10:46 UTC) |
| 2025-10-06 | Phase 4 | Task 4.2 | Gated macOS SwiftUI representable behind placeholder; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 11:03 UTC) |
| 2025-10-06 | Phase 4 | Task 4.3 | Selection suite checkpoint (`xcodebuild … -only-testing:LexicalTests/SelectionTests`); pass at 11:16 UTC |
| 2025-10-06 | Phase 5 | Task 5.1 | AppKit TextView scaffolding + adapter binding; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 11:24 UTC) |
| 2025-10-06 | Phase 5 | Task 5.2 | Overlay tap scaffolding; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 11:31 UTC) |
| 2025-10-06 | Phase 5 | Task 5.3 | Added macOS test target scaffolding; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 11:37 UTC) |
| 2025-10-06 | Phase 5 | Task 5.4 | Generalized Frontend to PAL types, extended PAL aliases (UXTextRange) and adjusted Package.swift gating; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 12:36 UTC) |
| 2025-10-06 | Phase 5 | Discipline | Verification rerun after user request; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 12:38 UTC) |
| 2025-10-06 | Phase 5 | Task 5.4 | Added AppKit frontend bridging for native selection + editor sync, extended TextViewMac helpers, added AppKit unit smoke test; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 12:51 UTC) |
| 2025-10-06 | Phase 5 | Discipline | Post-update verification (no code changes); full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 12:52 UTC) |
| 2025-10-06 | Phase 5 | Task 5.4 | Implemented AppKit IME lifecycle + key command routing scaffolding (`setMarkedText`, `unmarkText`, command dispatch), expanded AppKit tests; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 13:03 UTC) |
| 2025-10-06 | Phase 5 | Discipline | Post-change verification (follow-up run); full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 13:05 UTC) |
| 2025-10-06 | Phase 5 | Task 5.4 | Routed AppKit `doCommand` selectors to Lexical command dispatch, registered rich-text listeners for TextViewMac, added mac-only selector + IME tests; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 13:09 UTC) |
| 2025-10-06 | Phase 5 | Discipline | Post-change verification (follow-up run); full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 13:10 UTC) |
| 2025-10-06 | Phase 5 | Task 5.5 | Added AppKit pasteboard bridging (`CopyPasteHelpers` hooks), copy/cut/paste overrides, command routing tests; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 13:32 UTC) |
| 2025-10-06 | Phase 5 | Task 5.6 | Implemented AppKit decorator mount parity, overlay rect refresh, and tap forwarding via adapter/overlay; full suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 15:32 UTC) |
| 2025-10-06 | Phase 5 | Discipline | Post-instruction update: iOS suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 18:06 UTC) |
| 2025-10-06 | Phase 5 | Task 5.6a | LexicalMacTests build attempt **FAIL** (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`, 18:06 UTC) — build blocked by UIKit/MobileCoreServices imports on macOS |
| 2025-10-06 | Phase 5 | Task 5.6a | LexicalMacTests PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64e,id=00006001-000460342181801E' -derivedDataPath .build/DerivedData test`, 21:23 UTC; 2 tests skipped pending implementation) |
| 2025-10-06 | Phase 5 | Discipline | Full Lexical-Package suite PASS (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 21:36 UTC) |
| 2025-10-06 | Phase 5 | Discipline | LexicalMacTests PASS re-run (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64e,id=00006001-000460342181801E' -derivedDataPath .build/DerivedData test`, 21:49 UTC; 2 tests skipped pending implementation) |
| 2025-10-06 | Phase 5 | Discipline | Lexical-Package suite PASS re-run (`xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`, 21:49 UTC) |
| 2025-10-06 | Phase 5 | Task 5.6a | Selection suite FAIL (22:49 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/SelectionTests test`; unresolved helpers (`AttributeUtils`, `SelectionUtils`, `LexicalConstants`) after relocating UIKit sources. |
| 2025-10-07 | Phase 5 | Task 5.6a | Selection suite PASS (06:43 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/SelectionTests test`; helper visibility fixes (AttributeUtils, LexicalConstants, SelectionUtils, TextUtils) + plugin imports updated. || 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (06:56 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`; verifies helper exposure didn’t regress iOS behaviour. |
| 2025-10-07 | Phase 5 | Task 5.6a | LexicalMacTests FAIL (06:57 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' test`; missing module import (`LexicalUIKitAppKit`) after target split. |
| 2025-10-07 | Phase 5 | Discipline | Selection suite PASS (08:35 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/SelectionTests test`; preflight after adding `LexicalUIKitAppKit`. |
| 2025-10-07 | Phase 5 | Task 5.6a | LexicalMacTests PASS (08:36 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' test`; new `LexicalUIKitAppKit` shim resolves module import; 2 tests intentionally skipped pending implementation. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (08:37 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`; post-shim verification. |
| 2025-10-07 | Phase 5 | Task 5.6a | Move TextKit files under LexicalUIKit/TextKit; Package.swift already picks nested sources, shim exposes to AppKit. Pending: guard remaining UIKit imports in core. |
| 2025-10-07 | Phase 5 | Discipline | Selection suite PASS (09:03 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -only-testing:LexicalTests/SelectionTests test`; verifies TextKit files restored to core before further moves. |
| 2025-10-07 | Phase 5 | Task 5.6a | Audit remaining UIKit imports in core; most files already guard with `#if canImport(UIKit)` and rely on PAL types. No structural changes needed—focus next on packaging adjustments. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (09:06 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' test`; confirms baseline remains green after shim/audit. |
| 2025-10-07 | Phase 5 | Task 5.6a | Audited shared sources for UIKit imports; confirmed all remaining UIKit usages are wrapped in `#if canImport(UIKit)` with AppKit/PAL fallbacks. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (07:25 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (07:25 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 2 tests skipped pending implementation. |
| 2025-10-07 | Phase 5 | Task 5.6a | Confirmed mac target dependencies/shims sufficient; no additional AppKit helper files required. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (09:43 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (09:43 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 2 tests skipped pending implementation. |
| 2025-10-07 | Phase 5 | Task 5.6 | Added AppKit decorator overlay integration tests (rect sizing + tap forwarding). |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (07:50 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (07:50 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 2 tests skipped pending implementation. |
| 2025-10-07 | Phase 5 | Task 5.7a | Added AppKit performance smoke tests (typing + scroll); baseline averages ≈1.7 ms per typing batch and ≈11 ms per scroll loop. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (10:12 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (10:12 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; includes new performance smoke tests (2 measured, 2 skipped). |
| 2025-10-07 | Phase 5 | Task 5.7b | Added AppKit keyboard shortcut dispatch tests (delete char/word, indent, bold). No additional gaps observed beyond existing paste/cut/copy TODO. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (10:23 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (10:23 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 13 tests run (2 skipped). |
| 2025-10-07 | Phase 5 | Task 5.7c | Added `Examples/AppKitHarness` with reusable view controller + README for manual QA. |
| 2025-10-07 | Phase 5 | Task 5.8b | Added copy/cut/paste command dispatch tests (payload verified as `UXPasteboard`). |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (10:37 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (10:37 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 16 tests run (2 skipped). |
| 2025-10-07 | Phase 5 | Task 5.8a | Added marked-text regression coverage (AppKit) ensuring set/unmark flows propagate to the editor. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (10:43 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (11:06 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 16 tests run (1 skipped). |
| 2025-10-07 | Phase 5 | Task 5.8c | Expanded decorator coverage: added multi-decorator inset regression and cache cleanup test to ensure overlay rect transforms and position cache lifecycle behave on AppKit. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (11:29 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 18 tests run (1 skipped). |
| 2025-10-07 | Phase 5 | Discipline | Selection suite PASS (11:29 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData -only-testing:LexicalTests/SelectionTests test`. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (11:30 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Task 5.8d | Added AppKit placeholder regression tests and guarded placeholder color application to avoid TextStorage recursion loops. |
| 2025-10-07 | Phase 5 | Discipline | Selection suite PASS (12:07 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData -only-testing:LexicalTests/SelectionTests test`. |
| 2025-10-07 | Phase 5 | Discipline | Full Lexical-Package suite PASS (12:07 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme Lexical-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.0' -derivedDataPath .build/DerivedData test`. |
| 2025-10-07 | Phase 5 | Discipline | LexicalMacTests PASS (12:07 UTC) — `xcodebuild -workspace Playground/LexicalPlayground.xcodeproj/project.xcworkspace -scheme LexicalMacTests -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData test`; 20 tests run (1 skipped). |


## Appendix — Deferred / Optional Items
- Reinstate helper scripts (`run-ios-tests.sh`, `run-ios-test-suites.sh`) with timeout wrappers after Phase 1.
- Automate Selection + full suite commands via Makefile once PAL migration stabilizes.
- Consider DocC updates for PAL/ AppKit once targets are functional.
